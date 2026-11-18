extends RefCounted
## Übersetzer für die internen Wege der Spotify-Apps (wie die Spotify-App angemeldet):
## pathfinder (api-partner, GraphQL) und Spotify Connect (spclient/connect-state). Alles hier ist
## statisch und ohne Netz – es macht aus den Antworten die Form der Web-API (api.spotify.com), die
## der Rest von Uzai schon kennt (Music.track_from, playlist_from, album_from, artist_from), und
## aus Steuerbefehlen der Web-API die Befehle von Spotify Connect. So bleibt die Web-API der
## Rückfall und der Weg der eigenen Spotify-App, ohne dass sich die Oberfläche ändert.

## Persisted-Query-Hashes des Web-Clients (Stand Okt. 2026, wie nocturne-connector). Spotify dreht
## sie mit neuen Web-Clients; passt einer nicht (HTTP 400/412), nimmt Uzai still die Web-API.
const HASHES := {
	"profileAttributes": "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced",
	"homeSection": "c11ff5d8f508cb1a3dad3f15ee80611cda7df7e6fb45212e466fb3e84a680bf9",
	"libraryV3": "9f4da031f81274d572cfedaf6fc57a737c84b43d572952200b2c36aaa8fec1c6",
	"fetchLibraryTracks": "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
	"searchDesktop": "21b3fe49546912ba782db5c47e9ef5a7dbd20329520ba0c7d0fcfadee671d24e",
	"userTopContent": "49ee15704de4a7fdeac65a02db20604aa11e46f02e809c55d9a89f6db9754356",
	"fetchPlaylist": "bb67e0af06e8d6f52b531f97468ee4acd44cd0f82b988e15c2ea47b1148efc77",
	"getAlbum": "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10",
	"getTrack": "612585ae06ba435ad26369870deaae23b5c8800a256cd8a57e08eddc25a37294",
	"queryArtistOverview": "446130b4a0aa6522a686aafccddb0ae849165b5e0436fd802f96e0243617b5d8",
	"areEntitiesInLibrary": "134337999233cc6fdd6b1e6dbf94841409f04a946c5c7b744b09ba0dfe5a85ed",
	"addToLibrary": "7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d",
	"removeFromLibrary": "7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d",
}

## Gerätearten von Spotify Connect → Namen wie in der Web-API.
const DEVICE_TYPES := { "COMPUTER": "Computer", "SMARTPHONE": "Smartphone", "TABLET": "Tablet", "SPEAKER": "Speaker",
	"TV": "TV", "AVR": "AVR", "STB": "STB", "AUDIO_DONGLE": "AudioDongle", "GAME_CONSOLE": "GameConsole",
	"CAST_VIDEO": "CastVideo", "CAST_AUDIO": "CastAudio", "AUTOMOBILE": "Automobile", "SMARTWATCH": "Smartwatch" }


# --- kleine Helfer ------------------------------------------------------------------------------

static func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func arr(v: Variant) -> Array:
	return v if v is Array else []


## Wert über einen Pfad („a/b/c“), {} bzw. null, wenn es ihn nicht gibt.
static func dig(v: Variant, path: String) -> Variant:
	var cur: Variant = v
	for part in path.split("/"):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return null
		cur = (cur as Dictionary)[part]
	return cur


static func s(v: Variant) -> String:
	return "" if v == null else str(v)


## Letzter Teil einer Spotify-URI („spotify:track:abc“ → „abc“).
static func uri_id(uri: String) -> String:
	return uri.get_slice(":", uri.get_slice_count(":") - 1) if uri.begins_with("spotify:") else ""


## Bildquellen von pathfinder ({ url, width, height }) als Web-API-Bilderliste, größtes zuerst.
static func images(sources: Variant) -> Array:
	var list: Array = []
	for src in arr(sources):
		if src is Dictionary and s((src as Dictionary).get("url")) != "":
			list.append({ "url": s(src.url), "width": int(src.get("width", 0)) if src.get("width") != null else 0 })
	list.sort_custom(func(a, b): return int(a.width) > int(b.width))
	return list


## Bild aus Spotify Connect: „spotify:image:<hex>“ → Adresse beim Bilder-Server.
## Erster nicht leerer Wert unter diesen Schlüsseln („“ zählt als fehlend – Spotify schickt die
## größeren Bildfelder oft leer mit, dann blieb der Titel ganz ohne Cover).
static func erstes(d: Dictionary, keys: Array) -> String:
	for k in keys:
		var v := s(d.get(k))
		if v != "":
			return v
	return ""


static func image_url(v: String) -> String:
	if v.begins_with("spotify:image:"):
		return "https://i.scdn.co/image/" + v.substr(14)
	return v


static func _artists(d: Dictionary) -> Array:
	var out: Array = []
	var items: Array = arr(dig(d, "artists/items"))
	if items.is_empty():
		items = arr(dig(d, "firstArtist/items")) + arr(dig(d, "otherArtists/items"))
	for a in items:
		if a is Dictionary:
			var uri := s((a as Dictionary).get("uri"))
			var nm := s(dig(a, "profile/name"))
			if nm == "":
				nm = s((a as Dictionary).get("name"))
			out.append({ "id": uri_id(uri), "name": nm })
	return out


# --- Einträge -----------------------------------------------------------------------------------

## Ein Titel von pathfinder in der Form der Web-API ({} wenn es keiner ist). uri_hint: die Adresse,
## wenn der Titel selbst keine trägt (fetchLibraryTracks hat sie neben den Daten als _uri).
static func track(v: Variant, uri_hint := "") -> Dictionary:
	var d := dict(v)
	var uri := s(d.get("uri"))
	if uri == "":
		uri = uri_hint
	if not uri.begins_with("spotify:track:"):
		return {}
	var dur: Variant = dig(d, "duration/totalMilliseconds")
	if dur == null:
		dur = dig(d, "trackDuration/totalMilliseconds")
	var alb := dict(d.get("albumOfTrack"))
	return {
		"type": "track", "id": uri_id(uri), "uri": uri, "name": s(d.get("name")),
		"duration_ms": int(dur) if dur != null else 0,
		"explicit": s(dig(d, "contentRating/label")) == "EXPLICIT",
		"artists": _artists(d),
		"album": { "id": uri_id(s(alb.get("uri"))), "name": s(alb.get("name")), "images": images(dig(alb, "coverArt/sources")) },
	}


## Ein Album (auch Single/EP) von pathfinder in der Form der Web-API.
static func album(v: Variant) -> Dictionary:
	var d := dict(v)
	var uri := s(d.get("uri"))
	if not uri.begins_with("spotify:album:"):
		return {}
	var typ := s(d.get("type")).to_lower()
	if typ == "ep":
		typ = "single"
	if typ == "":
		typ = "album"
	var date := ""
	var precision := "day"
	var iso := s(dig(d, "date/isoString"))
	if iso.length() >= 10:
		date = iso.substr(0, 10)
		var p := s(dig(d, "date/precision")).to_lower()
		if p == "year":
			date = iso.substr(0, 4)
			precision = "year"
		elif p == "month":
			date = iso.substr(0, 7)
			precision = "month"
	elif dig(d, "date/year") != null:
		date = str(int(dig(d, "date/year")))
		precision = "year"
	var total: Variant = dig(d, "tracksV2/totalCount")
	if total == null:
		total = dig(d, "tracks/totalCount")
	return {
		"id": uri_id(uri), "uri": uri, "name": s(d.get("name")), "album_type": typ,
		"release_date": date, "release_date_precision": precision, "total_tracks": int(total) if total != null else 0,
		"artists": _artists(d), "images": images(dig(d, "coverArt/sources")),
	}


## Ein Künstler von pathfinder in der Form der Web-API.
static func artist(v: Variant) -> Dictionary:
	var d := dict(v)
	var uri := s(d.get("uri"))
	if not uri.begins_with("spotify:artist:"):
		return {}
	var out := { "id": uri_id(uri), "uri": uri, "name": s(dig(d, "profile/name")), "images": images(dig(d, "visuals/avatarImage/sources")), "genres": [] }
	if dig(d, "stats/followers") != null:
		out["followers"] = { "total": int(dig(d, "stats/followers")) }
	return out


## Eine Playlist von pathfinder in der Form der Web-API.
static func playlist(v: Variant) -> Dictionary:
	var d := dict(v)
	var uri := s(d.get("uri"))
	if not uri.begins_with("spotify:playlist:"):
		return {}
	var owner := dict(dig(d, "ownerV2/data"))
	var ouri := s(owner.get("uri"))
	var total: Variant = dig(d, "content/totalCount")
	if total == null:
		total = d.get("count")
	var imgs: Array = arr(dig(d, "images/items"))
	return {
		"id": uri_id(uri), "uri": uri, "name": s(d.get("name")), "description": s(d.get("description")),
		"collaborative": false, "images": images(dig(imgs[0], "sources")) if not imgs.is_empty() else [],
		"owner": { "id": uri_id(ouri) if ouri.begins_with("spotify:user:") else s(owner.get("username")), "display_name": s(owner.get("name")) },
		"items": { "total": int(total) if total != null else -1 },   # -1: unbekannt (libraryV3 liefert keine Anzahl)
	}


# --- Antworten ----------------------------------------------------------------------------------

## libraryV3: die Daten jedes Eintrags (Playlist, Album, Künstler …).
static func library_items(resp: Variant) -> Array:
	var out: Array = []
	for e in arr(dig(resp, "data/me/libraryV3/items")):
		var data := dict(dig(e, "item/data"))
		if data.is_empty():
			continue
		if s(data.get("uri")) == "" and s(dig(e, "item/_uri")) != "":
			data = data.duplicate()
			data["uri"] = s(dig(e, "item/_uri"))
		out.append(data)
	return out


static func library_total(resp: Variant) -> int:
	var t: Variant = dig(resp, "data/me/libraryV3/totalCount")
	return int(t) if t != null else -1


## fetchLibraryTracks: Lieblingssongs als Web-API-Titel.
static func liked(resp: Variant) -> Dictionary:
	var out: Array = []
	for e in arr(dig(resp, "data/me/library/tracks/items")):
		var t := track(dig(e, "track/data"), s(dig(e, "track/_uri")))
		if not t.is_empty():
			out.append(t)
	var total: Variant = dig(resp, "data/me/library/tracks/totalCount")
	return { "items": out, "total": int(total) if total != null else out.size(), "ok": dig(resp, "data/me/library/tracks") != null }


## searchDesktop: Treffer in der Form von /search der Web-API.
static func search(resp: Variant) -> Dictionary:
	var sv := dict(dig(resp, "data/searchV2"))
	var tr: Array = []
	for w in arr(dig(sv, "tracksV2/items")):
		var t := track(dig(w, "item/data"))
		if not t.is_empty():
			tr.append(t)
	var ar: Array = []
	for w in arr(dig(sv, "artists/items")):
		var a := artist(dig(w, "data"))
		if not a.is_empty():
			ar.append(a)
	var al: Array = []
	for w in arr(dig(sv, "albumsV2/items")):
		var x := album(dig(w, "data"))
		if not x.is_empty():
			al.append(x)
	var pl: Array = []
	for w in arr(dig(sv, "playlists/items")):
		var p := playlist(dig(w, "data"))
		if not p.is_empty():
			pl.append(p)
	return { "tracks": { "items": tr }, "artists": { "items": ar }, "albums": { "items": al }, "playlists": { "items": pl }, "ok": not sv.is_empty() }


## userTopContent: Top-Titel bzw. Top-Künstler.
static func top(resp: Variant, kind: String) -> Array:
	var out: Array = []
	for e in arr(dig(resp, "data/me/profile/%s/items" % ("topTracks" if kind == "tracks" else "topArtists"))):
		var data: Variant = (e as Dictionary).get("data") if e is Dictionary and (e as Dictionary).has("data") else e
		var x := track(data) if kind == "tracks" else artist(data)
		if not x.is_empty():
			out.append(x)
	return out


## fetchPlaylist: Titel einer Playlist. ok: Spotify hat die Liste geschickt (auch leer).
static func playlist_page(resp: Variant) -> Dictionary:
	var pl := dict(dig(resp, "data/playlistV2"))
	var content: Variant = pl.get("content")
	var out: Array = []
	for e in arr(dig(content, "items")):
		var t := track(dig(e, "itemV2/data"))
		if not t.is_empty():
			out.append(t)
	var total: Variant = dig(content, "totalCount")
	return { "ok": content is Dictionary, "items": out, "total": int(total) if total != null else out.size(),
		"count": arr(dig(content, "items")).size() }


## getAlbum: Titel eines Albums (ohne Albumangaben – die setzt Music.album_tracks).
static func album_page(resp: Variant) -> Array:
	var al := dict(dig(resp, "data/albumUnion"))
	var tracks: Variant = al.get("tracksV2") if al.has("tracksV2") else al.get("tracks")
	var out: Array = []
	for e in arr(dig(tracks, "items")):
		var data: Variant = (e as Dictionary).get("track") if e is Dictionary and (e as Dictionary).has("track") else e
		var t := track(data)
		if not t.is_empty():
			t.erase("album")
			out.append(t)
	return out


## queryArtistOverview: { artist, top, releases (Web-API-Alben mit album_group) }.
static func artist_overview(resp: Variant) -> Dictionary:
	var au := dict(dig(resp, "data/artistUnion"))
	if au.is_empty():
		return {}
	var top_t: Array = []
	for e in arr(dig(au, "discography/topTracks/items")):
		var t := track(dig(e, "track"))
		if not t.is_empty():
			top_t.append(t)
	var rel: Array = []
	var seen := {}
	for group in [["albums", "album"], ["singles", "single"], ["compilations", "compilation"]]:
		for e in arr(dig(au, "discography/%s/items" % str(group[0]))):
			var list: Array = arr(dig(e, "releases/items"))
			if list.is_empty():
				list = [e]
			for r in list:
				var a := album(r)
				if a.is_empty() or seen.has(str(a.id)):
					continue
				seen[str(a.id)] = true
				a["album_group"] = str(group[1])
				rel.append(a)
	for e in arr(dig(au, "discography/popularReleasesAlbums/items")):
		var a := album(e)
		if not a.is_empty() and not seen.has(str(a.id)):
			seen[str(a.id)] = true
			a["album_group"] = "album" if str(a.album_type) == "album" else "single"
			rel.append(a)
	var info := artist(au)
	if info.is_empty():
		info = { "id": uri_id(s(au.get("uri"))), "uri": s(au.get("uri")), "name": s(dig(au, "profile/name")), "images": [], "genres": [] }
	return { "artist": info, "top": top_t, "releases": rel }


## areEntitiesInLibrary: ja/nein je URI in derselben Reihenfolge ([] wenn die Antwort fehlt).
static func lookup(resp: Variant, n: int) -> Array:
	var items: Array = arr(dig(resp, "data/lookup"))
	if items.size() < n:
		return []
	var out: Array = []
	for i in n:
		var e: Variant = items[i]
		var saved: Variant = dig(e, "data/saved")
		if saved == null:
			saved = dig(e, "saved")
		out.append(bool(saved) if saved != null else false)
	return out


## recently-played (spclient): die zuletzt gehörten Titel-URIs, jeder einmal, neueste zuerst.
static func recent_uris(resp: Variant, limit := 20) -> Array:
	var out: Array = []
	for c in arr(dig(resp, "playContexts")):
		var u := s(dig(c, "lastPlayedTrackUri"))
		if u.begins_with("spotify:track:") and not out.has(u):
			out.append(u)
			if out.size() >= limit:
				break
	return out


# --- Spotify Connect ----------------------------------------------------------------------------

## Was Spotify Connect über den Zustand meldet (Antwort auf PUT connect-state/v1/devices/…):
## { active, devices: [{ id, name, type, active, volume }], track: {...}, playing, progress, duration,
##   shuffle, repeat, context, queue: [{ uri, title, artist, album, art }] }. own: Uzais eigene,
## versteckte Kennung (taucht nicht als Gerät auf). now_ms: jetzt (Unix, Millisekunden).
static func cluster(c: Variant, own: String, now_ms: int) -> Dictionary:
	var cd := dict(c)
	var active := s(cd.get("active_device_id"))
	var devs: Array = []
	var raw := dict(cd.get("devices"))
	for id in raw.keys():
		var d := dict(raw[id])
		var did := s(d.get("device_id")) if s(d.get("device_id")) != "" else str(id)
		if did == own or _ja(dig(d, "capabilities/hidden")):
			continue
		var vol: Variant = d.get("volume")
		devs.append({ "id": did, "name": s(d.get("name")), "type": str(DEVICE_TYPES.get(s(d.get("device_type")), "Unknown")),
			"active": did == active, "volume": roundi(float(vol) / 65535.0 * 100.0) if vol != null else -1, "restricted": false })
	var ps := dict(cd.get("player_state"))
	var tr := dict(ps.get("track"))
	var md := dict(tr.get("metadata"))
	var uri := s(tr.get("uri"))
	var playing: bool = _ja(ps.get("is_playing")) and not _ja(ps.get("is_paused"))
	var pos := int(s(ps.get("position_as_of_timestamp"))) if s(ps.get("position_as_of_timestamp")).is_valid_int() else 0
	var ts := int(s(ps.get("timestamp"))) if s(ps.get("timestamp")).is_valid_int() else now_ms
	var dur := int(s(ps.get("duration"))) if s(ps.get("duration")).is_valid_int() else (int(s(md.get("duration"))) if s(md.get("duration")).is_valid_int() else 0)
	var progress := pos + (maxi(0, now_ms - ts) if playing else 0)
	if dur > 0:
		progress = mini(progress, dur)
	var opts := dict(ps.get("options"))
	var queue: Array = []
	for n in arr(ps.get("next_tracks")):
		var nu := s(dig(n, "uri"))
		if not nu.begins_with("spotify:track:"):
			continue
		var nm := dict(dig(n, "metadata"))
		queue.append(
				{ "id": uri_id(nu), "uri": nu, "title": s(nm.get("title")), "artist": s(nm.get("artist_name")), "artists": [], "artist_id": uri_id(s(nm.get("artist_uri"))),
			"album": s(nm.get("album_title")), "art": image_url(erstes(nm, ["image_url", "image_large_url"])),
			"art_big": image_url(erstes(nm, ["image_large_url", "image_url"])),
			"duration": int(s(nm.get("duration"))) if s(nm.get("duration")).is_valid_int() else 0, "explicit": false, "added": 0 })
		if queue.size() >= 30:
			break
	return {
		"active": active, "devices": devs,
		"track": { "id": uri_id(uri), "uri": uri, "title": s(md.get("title")), "artist": s(md.get("artist_name")), "artist_id": uri_id(s(md.get("artist_uri"))),
			"album": s(md.get("album_title")), "art": image_url(erstes(md, ["image_xlarge_url", "image_large_url", "image_url", "image_small_url"])) },
		"playing": playing, "progress": progress, "duration": dur,
		"shuffle": _ja(opts.get("shuffling_context")),
		"repeat": "track" if _ja(opts.get("repeating_track")) else ("context" if _ja(opts.get("repeating_context")) else "off"),
		"context": s(ps.get("context_uri")), "queue": queue,
	}


## Die Spotify-App auf diesem PC unter den Geräten: der Computer mit dem Namen dieses PCs (ohne Namen – kein
## Windows –: der erste Computer). "" wenn sie nicht dabei ist.
static func dieser_pc(devs: Array, pc_name := "") -> String:
	var pc := pc_name.to_lower()
	for d in devs:
		if d is Dictionary and s((d as Dictionary).get("type")) == "Computer" and (pc == "" or s((d as Dictionary).get("name")).to_lower() == pc):
			return s((d as Dictionary).get("id"))
	return ""


## Spielt gerade ein fremdes Gerät – weder dieser PC noch eines, das der Nutzer hier gewählt hat (gewollt)?
static func fremd_aktiv(info: Dictionary, pc_name := "", gewollt := "") -> bool:
	var aktiv := s(info.get("active"))
	return aktiv != "" and aktiv != gewollt and aktiv != dieser_pc(arr(info.get("devices")), pc_name)


## Which device receives commands.
## ort "pc" (Uzai's default, so playback starts directly on the PC): always the Spotify app on this PC, even
##   while another device is playing. If it is not listed: "" – the caller starts it (Music.ensure_device)
##   instead of falling back to a TV or speaker. Only exception: a device the user picked in
##   "Abspielen auf …" (gewollt), as long as it is the active one.
## ort "aktiv" (previous behavior): the active device, else this PC (by name), else any PC, else the first.
static func pick_target(info: Dictionary, pc_name := "", ort := "aktiv", gewollt := "") -> String:
	var devs: Array = arr(info.get("devices"))
	if ort == "pc":
		if gewollt != "" and s(info.get("active")) == gewollt:
			return gewollt
		return dieser_pc(devs, pc_name)
	if s(info.get("active")) != "":
		for d in devs:
			if str(d.id) == str(info.active):
				return str(d.id)
	var pc := pc_name.to_lower()
	for d in devs:
		if str(d.type) == "Computer" and pc != "" and str(d.name).to_lower() == pc:
			return str(d.id)
	for d in devs:
		if str(d.type) == "Computer":
			return str(d.id)
	return str(devs[0].id) if not devs.is_empty() else ""


## Steuerbefehl der Web-API (Methode, Pfad, Inhalt) als Befehle für Spotify Connect
## (connect-state/v1/player/command). [] wenn es keine Entsprechung gibt.
static func commands_for(method: int, path: String, payload: Variant, command_id := "") -> Array:
	var p := path.get_slice("?", 0)
	var q := {}
	for part in path.get_slice("?", 1).split("&"):
		if part.contains("="):
			q[part.get_slice("=", 0)] = part.get_slice("=", 1).uri_decode()
	var log_params := { "command_id": command_id }
	var body := dict(payload)
	match p:
		"/me/player/pause":
			return [{ "endpoint": "pause", "logging_params": log_params }]
		"/me/player/next":
			return [{ "endpoint": "skip_next", "logging_params": log_params }]
		"/me/player/previous":
			return [{ "endpoint": "skip_prev", "logging_params": log_params }]
		"/me/player/seek":
			return [{ "endpoint": "seek_to", "value": int(q.get("position_ms", "0")), "logging_params": log_params }]
		"/me/player/shuffle":
			return [{ "endpoint": "set_shuffling_context", "value": str(q.get("state", "false")) == "true", "logging_params": log_params }]
		"/me/player/repeat":
			var st := str(q.get("state", "off"))
			return [{ "endpoint": "set_repeating_context", "value": st != "off", "logging_params": log_params },
				{ "endpoint": "set_repeating_track", "value": st == "track", "logging_params": log_params }]
		"/me/player/queue":
			var u := str(q.get("uri", ""))
			if u == "":
				return []
			return [{ "endpoint": "add_to_queue", "track": { "uri": u, "metadata": { "is_queued": "true" }, "provider": "queue" }, "logging_params": log_params }]
		"/me/player/play":
			if method != HTTPClient.METHOD_PUT:
				return []
			# Die vollständige Form, wie sie die Spotify-App am PC nachweislich ausführt (so schickt sie auch
			# github.com/Aran404/SpotAPI, dort am 10.11.2026 an der App am PC geprüft). Die kurze Form davor – ohne
			# metadata, initially_paused, seek_to und die beiden Listen in logging_params – nahm Spotify an (HTTP 200),
			# die App am PC wurde aktives Gerät und lud nichts (Protokoll vom PC, 13.11.); am Fernseher lief sie.
			var origin := { "feature_identifier": "uzai", "referrer_identifier": "uzai" }
			var play_log := { "page_instance_ids": [], "interaction_ids": [], "command_id": command_id }
			var opts := { "initially_paused": false, "seek_to": 0 }
			var ctx := str(body.get("context_uri", ""))
			if ctx != "":
				# Ein einzelner Titel ist selbst der Kontext: nichts zu überspringen.
				var off := dict(body.get("offset"))
				if not ctx.begins_with("spotify:track:"):
					if s(off.get("uri")) != "":
						opts["skip_to"] = { "track_uri": s(off.uri) }
					elif off.get("position") != null:
						opts["skip_to"] = { "track_index": int(off.position) }
				return [{ "endpoint": "play", "context": { "uri": ctx, "url": "context://" + ctx, "metadata": {} }, "play_origin": origin, "options": opts,
					"logging_params": play_log }]
			var uris: Array = arr(body.get("uris"))
			if not uris.is_empty():
				var tracks: Array = []
				for u in uris:
					tracks.append({ "uri": str(u) })
				opts["skip_to"] = { "track_index": 0 }
				return [{ "endpoint": "play", "context": { "pages": [{ "tracks": tracks }], "metadata": {} }, "play_origin": origin, "options": opts,
					"logging_params": play_log }]
			return [{ "endpoint": "resume", "logging_params": log_params }]
	return []


## Was ein Abspielbefehl der Web-API starten soll: { titel, kontext, lose }. titel: der Titel, der zuerst laufen soll
## ("" = die Liste von vorn). kontext: Playlist, Album, Künstler ("" bei einzelnem Titel und loser Liste). lose: eine
## Liste einzelner Titel ohne eigene Adresse. {} wenn nichts Bestimmtes gewünscht ist (Fortsetzen).
static func play_wunsch(payload: Variant) -> Dictionary:
	var body := dict(payload)
	var ctx := s(body.get("context_uri"))
	if ctx.begins_with("spotify:track:"):
		return { "titel": ctx, "kontext": "", "lose": false }
	if ctx != "":
		return { "titel": s(dict(body.get("offset")).get("uri")), "kontext": ctx, "lose": false }
	var uris := arr(body.get("uris"))
	if uris.is_empty():
		return {}
	return { "titel": s(uris[0]), "kontext": "", "lose": true }


## Derselbe Wunsch als einzelner Titel, ohne die Liste drumherum (danach läuft nicht die Liste weiter, sondern was
## Spotify selbst anschließt). {} wenn kein bestimmter Titel gewünscht ist oder es schon ein einzelner Titel ist.
static func play_einzeln(payload: Variant) -> Dictionary:
	var w := play_wunsch(payload)
	var titel := s(w.get("titel"))
	if not titel.begins_with("spotify:track:") or (s(w.get("kontext")) == "" and not _ja(w.get("lose"))):
		return {}
	return { "context_uri": titel }


## Liked Songs as a context of their own, the way the Spotify apps play them (shuffled too). As a loose list, the
## app on the PC did not load them, and fallback "Weg d" (music_spotify.gd) played only the album of the first
## track – for a single with shuffle on, always the same track. "" without a valid account ID.
static func liked_context(user_id: String) -> String:
	if RegEx.create_from_string("^[A-Za-z0-9._-]{1,64}$").search(user_id) == null:
		return ""
	return "spotify:user:%s:collection" % user_id


## Derselbe Wunsch als Titel in seinem Album (album_uri von getTrack): Am PC (13.11., 0.16.62) lud die Spotify-App
## weder lose Titellisten noch einen Titel als eigenen Kontext – Playlist und Album ab Titel liefen sofort. Danach
## läuft das Album weiter, nicht die Liste. {} ohne bestimmten Titel, ohne Album oder wenn es schon ein Kontext ist.
static func play_album(payload: Variant, album_uri: String) -> Dictionary:
	if play_einzeln(payload).is_empty() or not album_uri.begins_with("spotify:album:") or album_uri.length() > 64:
		return {}
	return { "context_uri": album_uri, "offset": { "uri": s(play_wunsch(payload).get("titel")) } }


## Die Wege, einen Abspielbefehl zuzustellen, in der Reihenfolge, in der Uzai sie versucht – der gemerkte (der zuletzt
## zum Laufen führte) zuerst:
##   "a" von Uzais unsichtbarem Gerät an das Zielgerät (so gehen Pause, Weiter und Fortsetzen)
##   "b" mit dem Zielgerät selbst als Absender (so schickt SpotAPI seine Befehle)
##   "c" wie b, aber nur der eine Titel (play_einzeln) – nur wenn ein bestimmter Titel gewünscht ist
##   "d" wie a, der Titel in seinem Album (play_album) – ebenso; so lief es am PC, wo a bis c nichts luden
static func play_wege(gemerkt: String, payload: Variant) -> Array:
	var alle: Array = ["a", "b"]
	if not play_einzeln(payload).is_empty():
		alle.append_array(["c", "d"])
	var out: Array = [gemerkt] if gemerkt in alle else []
	for w in alle:
		if not (w in out):
			out.append(w)
	return out


## Hat der Abspielbefehl gegriffen? info: Intern.cluster danach, ziel: das Zielgerät, vor_titel: der Titel davor.
## "ja": das Gewünschte läuft auf dem Zielgerät. "pausiert": es ist geladen, steht aber. "nein": nichts davon
## (anderes Gerät aktiv, kein Titel, noch der alte Titel).
## Spotify tauscht Titel je nach Land gegen eine andere Fassung aus: Ein neuer, laufender Titel zählt darum auch,
## wenn seine Kennung nicht die gewünschte ist. Steht ein anderer nur da (pausiert), ist das kein Beleg – das kann
## der Titel von gestern sein, den die App beim Aufwachen zeigt.
static func play_stand(info: Dictionary, ziel: String, vor_titel: String, wunsch: Dictionary) -> String:
	var titel := s(dig(info, "track/uri"))
	if ziel == "" or s(info.get("active")) != ziel or titel == "":
		return "nein"
	var spielt := _ja(info.get("playing"))
	var w_titel := s(wunsch.get("titel"))
	var w_kontext := s(wunsch.get("kontext"))
	var genau := titel == w_titel if w_titel != "" else (w_kontext != "" and s(info.get("context")) == w_kontext)
	if genau:
		return "ja" if spielt else "pausiert"
	return "ja" if spielt and titel != vor_titel else "nein"


## Fürs Protokoll, was abgespielt werden soll – ohne Kennungen: „Titelliste (37)“, „playlist ab Titel“, „album“, „Titel“.
static func play_art(payload: Variant) -> String:
	var w := play_wunsch(payload)
	if w.is_empty():
		return ""
	var body := dict(payload)
	if _ja(w.get("lose")):
		return "Titelliste (%d)" % arr(body.get("uris")).size()
	var ctx := s(w.get("kontext"))
	if ctx == "":
		return "Titel"
	var art := ctx.get_slice(":", 1)
	if not (art in ["playlist", "album", "artist", "show"]):
		art = "Liste"
	if s(w.get("titel")) != "":
		return art + " ab Titel"
	return art + (" ab Nummer" if dict(body.get("offset")).get("position") != null else "")


## Fürs Protokoll, was das Zielgerät nach einem Abspielbefehl zeigt.
static func play_bild(info: Dictionary, ziel: String) -> String:
	var jn := func(b: bool) -> String: return "ja" if b else "nein"
	return "Gerät aktiv: %s, Titel geladen: %s, läuft: %s" % [jn.call(ziel != "" and s(info.get("active")) == ziel), jn.call(s(dig(info, "track/uri")) != ""),
		jn.call(_ja(info.get("playing")))]


## Ja/Nein aus einer fremden Antwort: nur ein echtes true zählt. Ein Vergleich mit == bräche bei einem
## anderen Typ (Text, Liste) mit einem Skriptfehler ab.
static func _ja(v: Variant) -> bool:
	return v is bool and bool(v)

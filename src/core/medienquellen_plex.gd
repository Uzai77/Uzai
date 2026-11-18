extends RefCounted
## Plex als Filme-Quelle (Roadmap 35) – die reinen Teile: Anmeldung über plex.tv/link (PIN wie
## bei Fernsehern), die Liste der eigenen und geteilten Server, Bibliotheken, Weiterschauen,
## Details mit Folgen, die Dateien zum Abspielen und die Rückmeldung des Fortschritts. Alles aus
## den JSON-Antworten von plex.tv und dem Plex Media Server (Accept: application/json).
##
## Sicherheit: Uzai nennt Plex nie „offiziell“, gibt sich nicht als anderer Client aus und meldet
## sich nur über den PIN-Weg an (kein Passwort). Bilder und Dateien kommen nur vom gewählten Server
## (Pfade geprüft, Adresse selbst gebaut) oder von Plex selbst (*.plex.tv); der Zugangsschlüssel
## geht nur als Kopfzeile an diesen Server, nie in eine Adresse (sonst stünde er in Zwischenspeichern).

const B := preload("res://src/core/medienquellen_basis.gd")
const MoviesScript := preload("res://src/core/movies.gd")

const PLEX_TV := "https://plex.tv"
const CLIENTS := "https://clients.plex.tv"
const LINK := "https://plex.tv/link"
const PREFIX := "plex:"
const ADDON := "quelle:plex"
const IMG_HOSTS := ["plex.tv"]
const PAGE := 60
const LIB := "com.plexapp.plugins.library"


## plex.tv bzw. clients.plex.tv – für Netz-Proben auf einen nachgebauten Server umlenkbar.
static func tv_base(clients := false) -> String:
	var env := Config.probe_env("UZAI_PLEX_TV")
	if env != "":
		return env.trim_suffix("/")
	return CLIENTS if clients else PLEX_TV


## Kopfzeilen, mit denen sich Uzai als eigene App „Uzai“ bei Plex meldet.
static func headers(client_id: String, version: String, token := "") -> PackedStringArray:
	var h := PackedStringArray(["Accept: application/json", "X-Plex-Product: Uzai", "X-Plex-Version: " + version,
		"X-Plex-Client-Identifier: " + client_id, "X-Plex-Platform: Windows", "X-Plex-Device: PC", "X-Plex-Device-Name: Uzai"])
	if token != "":
		h.append("X-Plex-Token: " + token)
	return h


static func token_ok(t: Variant) -> String:
	return B.ident(t, "token", 8, 200)


# --- Anmeldung ---------------------------------------------------------------------------------

## Antwort auf POST /api/v2/pins bzw. GET /api/v2/pins/<id>: { id, code, token, expires } oder {}.
static func parse_pin(d: Variant) -> Dictionary:
	var p := B.dict(d)
	var id := B.num(p.get("id", 0))
	var code := B.ident(p.get("code", ""), "alnum", 4, 32).to_upper()
	if id <= 0 or code == "":
		return {}
	var tok := token_ok(p.get("authToken")) if p.get("authToken") != null else ""
	var left := B.num(p.get("expiresIn", 900), 900)
	return { "id": id, "code": code, "token": tok, "expires": clampi(left, 30, 3600) }


## Server aus /api/v2/resources: nur Geräte, die „server“ anbieten. Verbindungen geprüft und
## sortiert: verschlüsselt im Heimnetz, verschlüsselt von außen, über Plex-Relay, zuletzt
## unverschlüsselt – das nur im Heimnetz (private Adresse).
static func parse_servers(d: Variant) -> Array:
	var out: Array = []
	for dev in B.arr(d, 100):
		if not (dev is Dictionary) or not B.text(dev.get("provides", ""), 120).split(",").has("server"):
			continue
		var id := B.ident(dev.get("clientIdentifier", ""), "alnum", 8, 64)
		var tok := token_ok(dev.get("accessToken", ""))
		var owned := B.flag(dev.get("owned", false))
		# Eigene Server nehmen sonst die Anmeldung selbst; geteilte brauchen ihren eigenen Schlüssel.
		if id == "" or (tok == "" and not owned):
			continue
		var conns: Array = []
		for c in B.arr(dev.get("connections", []), 16):
			var cc := _connection(c)
			if not cc.is_empty():
				conns.append(cc)
		if conns.is_empty():
			continue
		conns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(a) < _rank(b))
		var name := B.text(dev.get("name", ""), 60)
		out.append({ "id": id, "name": name if name != "" else "Plex-Server", "token": tok, "owned": owned,
			"online": B.flag(dev.get("presence", true)), "conns": conns })
		if out.size() >= 20:
			break
	return out


static func _connection(c: Variant) -> Dictionary:
	if not (c is Dictionary):
		return {}
	var p := B.parse_server(B.text(c.get("uri", ""), 300))
	if p.is_empty():
		return {}
	var local := B.flag(c.get("local", false))
	var http := str(p.scheme) == "http"
	# Unverschlüsselt nur zu einer privaten Adresse im Heimnetz.
	if http and not (local and B.is_private_ip(str(p.host))):
		return {}
	return { "uri": str(p.origin), "local": local, "relay": B.flag(c.get("relay", false)), "http": http }


static func _rank(c: Dictionary) -> int:
	if bool(c.http):
		return 3
	if bool(c.relay):
		return 2
	return 0 if bool(c.local) else 1


## machineIdentifier aus GET /identity (zeigt, dass unter der Adresse wirklich dieser Server ist).
static func parse_identity(d: Variant) -> String:
	return B.ident(B.dict(B.dict(d).get("MediaContainer", {})).get("machineIdentifier", ""), "alnum", 8, 64)


static func _container(d: Variant) -> Dictionary:
	return B.dict(B.dict(d).get("MediaContainer", {}))


# --- Bibliotheken und Titel --------------------------------------------------------------------

## Bibliotheken für Filme und Serien aus /library/sections: { key, title, type, family }.
static func parse_sections(d: Variant) -> Array:
	var out: Array = []
	for s in B.arr(_container(d).get("Directory", []), 60):
		if not (s is Dictionary):
			continue
		var key := B.ident(s.get("key", ""), "digits", 1, 9)
		var t := str(s.get("type", ""))
		if key == "" or t not in ["movie", "show"]:
			continue
		var title := B.text(s.get("title", ""), 60)
		out.append({ "key": key, "title": title, "type": "movie" if t == "movie" else "series", "family": B.family_word(title) })
	return out


## Bild vom Server (verkleinert über den Bild-Dienst des Servers) oder von *.plex.tv.
static func img(origin: String, path: Variant, w: int, h: int) -> String:
	var full := B.allowed_image(path, IMG_HOSTS)
	if full != "":
		return full
	var p := B.safe_path(path)
	if p == "":
		return ""
	return "%s/photo/:/transcode?width=%d&height=%d&minSize=1&upscale=1&url=%s" % [origin, w, h, p.uri_encode()]


static func _tags(v: Variant, max := 8) -> Array:
	var out: Array = []
	for t in B.arr(v, 40):
		var s := B.text(B.dict(t).get("tag", ""), 60)
		if s != "" and not out.has(s):
			out.append(s)
		if out.size() >= max:
			break
	return out


static func _year(m: Dictionary) -> String:
	var y := B.num(m.get("year", 0))
	if y >= 1870 and y <= 2200:
		return str(y)
	var d := B.text(m.get("originallyAvailableAt", ""), 20)
	return d.substr(0, 4) if d.length() >= 4 and d.substr(0, 4).is_valid_int() else ""


static func _logo(m: Dictionary, origin: String) -> String:
	for i in B.arr(m.get("Image", []), 12):
		if str(B.dict(i).get("type", "")) == "clearLogo":
			return img(origin, B.dict(i).get("url", ""), 800, 310)
	return ""


static func _score(m: Dictionary) -> String:
	for k in ["audienceRating", "rating"]:
		var v: Variant = m.get(k)
		if (v is float or v is int) and float(v) > 0.0 and float(v) <= 10.0:
			return "%.1f" % float(v)
	return ""


## MetaPreview (wie Movies.parse_meta_preview) für Film oder Serie. Folgen (Weiterschauen)
## werden zu ihrer Serie mit Angaben zur Folge. lib: { family } der Bibliothek.
static func preview(m: Variant, origin: String, lib := {}) -> Dictionary:
	if not (m is Dictionary):
		return {}
	var t := str(m.get("type", ""))
	if t == "episode":
		return _episode_item(m, origin, lib)
	if t not in ["movie", "show"]:
		return {}
	var rk := B.ident(m.get("ratingKey", ""), "digits", 1, 12)
	var name := B.text(m.get("title", ""))
	if rk == "" or name == "":
		return {}
	var raw_rating := B.text(m.get("contentRating", ""), 24)
	var y := _year(m)
	var it := {
		"id": PREFIX + rk, "type": "movie" if t == "movie" else "series", "name": name,
		"poster": img(origin, m.get("thumb", ""), 400, 600), "background": img(origin, m.get("art", ""), 1920, 1080),
		"logo": _logo(m, origin), "description": B.text(m.get("summary", ""), B.DESC_MAX), "year": y, "release_info": y,
		"imdb_rating": _score(m), "genres": _tags(m.get("Genre", []), 6), "addon_id": ADDON, "poster_shape": "",
		"age": B.age_of(raw_rating), "content_rating": B.rating_label(raw_rating), "family": bool(lib.get("family", false)), "source": "plex",
	}
	var dur := B.num(m.get("duration", 0))
	if t == "movie" and dur > 0:
		it["runtime"] = "%d min" % int(round(dur / 60000.0))
	return it


static func _episode_item(m: Dictionary, origin: String, lib: Dictionary) -> Dictionary:
	var rk := B.ident(m.get("ratingKey", ""), "digits", 1, 12)
	var show := B.ident(m.get("grandparentRatingKey", ""), "digits", 1, 12)
	var name := B.text(m.get("grandparentTitle", ""))
	if rk == "" or show == "" or name == "":
		return {}
	var raw_rating := B.text(m.get("contentRating", ""), 24)
	var pos := B.num(m.get("viewOffset", 0)) / 1000.0
	return {
		"id": PREFIX + show, "type": "series", "name": name,
		"poster": img(origin, m.get("grandparentThumb", ""), 400, 600),
		"background": img(origin, m.get("grandparentArt", m.get("art", "")), 1920, 1080), "logo": "",
		"description": B.text(m.get("summary", ""), B.DESC_MAX), "year": "", "release_info": "", "imdb_rating": "", "genres": [],
		"addon_id": ADDON, "poster_shape": "", "age": B.age_of(raw_rating), "content_rating": B.rating_label(raw_rating),
		"family": bool(lib.get("family", false)), "source": "plex",
		"video_id": PREFIX + rk, "season": B.num(m.get("parentIndex", 0)), "episode": B.num(m.get("index", 0)),
		"episode_title": B.text(m.get("title", "")), "thumbnail": img(origin, m.get("thumb", ""), 640, 360),
		"position": pos, "duration": B.num(m.get("duration", 0)) / 1000.0, "updated": B.num(m.get("lastViewedAt", 0)),
		"next_up": pos <= 0.0,
	}


## Titel einer Liste (Bibliothek, Sammlung, Suche). Nur Filme und Serien, ohne Doppelte.
static func parse_list(d: Variant, origin: String, lib := {}) -> Array:
	return _previews(B.arr(_container(d).get("Metadata", []), 500), origin, lib)


static func _previews(list: Array, origin: String, lib: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for m in list:
		var it := preview(m, origin, lib)
		if it.is_empty() or it.has("video_id") or seen.has(str(it.id)):
			continue
		seen[str(it.id)] = true
		out.append(it)
	return out


## Weiterschauen (/hubs/continueWatching/items oder /library/onDeck): angefangene Filme und Folgen,
## nächste Folgen („Als Nächstes“). libs: Bibliotheken (Familie) nach Nummer.
static func parse_continue(d: Variant, origin: String, libs := {}) -> Array:
	var out: Array = []
	var seen := {}
	for m in B.arr(_container(d).get("Metadata", []), 60):
		if not (m is Dictionary):
			continue
		var lib: Dictionary = libs.get(B.ident(m.get("librarySectionID", ""), "digits", 1, 9), {})
		var it := preview(m, origin, lib)
		if it.is_empty() or seen.has(str(it.id)):
			continue
		seen[str(it.id)] = true
		if not it.has("video_id"):
			var pos := B.num(m.get("viewOffset", 0)) / 1000.0
			it.merge({ "video_id": str(it.id), "season": 0, "episode": 0, "episode_title": "", "thumbnail": "",
				"position": pos, "duration": B.num(m.get("duration", 0)) / 1000.0, "updated": B.num(m.get("lastViewedAt", 0)), "next_up": pos <= 0.0 }, true)
		if int(it.updated) <= 0:
			it.updated = B.num(m.get("addedAt", 0))
		out.append(it)
	return out


## Suche (/hubs/search): die Treffer aller Bereiche mit Filmen und Serien.
static func parse_search(d: Variant, origin: String) -> Array:
	var c := _container(d)
	var list: Array = B.arr(c.get("Metadata", []), 200)
	for h in B.arr(c.get("Hub", []), 20):
		if str(B.dict(h).get("type", "")) in ["movie", "show"]:
			list.append_array(B.arr(B.dict(h).get("Metadata", []), 60))
	return _previews(list, origin, {})


## Sammlungen einer Bibliothek: { id, title, poster, background, count }.
static func parse_collections(d: Variant, origin: String) -> Array:
	var out: Array = []
	for m in B.arr(_container(d).get("Metadata", []), 60):
		if not (m is Dictionary):
			continue
		var rk := B.ident(m.get("ratingKey", ""), "digits", 1, 12)
		var title := B.text(m.get("title", ""), 80)
		if rk == "" or title == "":
			continue
		out.append({ "id": rk, "title": title, "poster": img(origin, m.get("thumb", ""), 400, 600),
			"background": img(origin, m.get("art", ""), 1280, 720), "count": B.num(m.get("childCount", 0)) })
	return out


## Genres einer Bibliothek (/library/sections/<n>/genre): { key, title }.
static func parse_genres(d: Variant) -> Array:
	var out: Array = []
	for g in B.arr(_container(d).get("Directory", []), 120):
		var key := B.ident(B.dict(g).get("key", ""), "digits", 1, 9)
		var title := B.text(B.dict(g).get("title", ""), 40)
		if key != "" and title != "":
			out.append({ "key": key, "title": title })
	return out


# --- Details, Folgen, Abspielen ----------------------------------------------------------------

## Volle Angaben (wie Movies.parse_meta) aus /library/metadata/<n>; leaves: /allLeaves der Serie.
## server_progress: Stand jeder Datei auf dem Server { video_id: { position, duration, watched, updated } }.
static func parse_meta(d: Variant, origin: String, leaves: Variant = null, lib := {}) -> Dictionary:
	var list := B.arr(_container(d).get("Metadata", []), 1)
	if list.is_empty() or not (list[0] is Dictionary):
		return {}
	var m: Dictionary = list[0]
	var out := preview(m, origin, lib)
	if out.is_empty() or out.has("video_id"):
		return {}
	var people := {}
	var cast: Array = []
	for r in B.arr(m.get("Role", []), 40):
		var n := B.text(B.dict(r).get("tag", ""), 80)
		if n == "" or cast.size() >= MoviesScript.CAST_MAX:
			continue
		cast.append(n)
		people[MoviesScript.person_key(n)] = { "name": n, "photo": img(origin, B.dict(r).get("thumb", ""), 185, 278),
			"character": B.text(B.dict(r).get("role", ""), 80) }
	var prog := {}
	var videos: Array = []
	if out.type == "series" and leaves != null:
		for e in B.arr(_container(leaves).get("Metadata", []), 3000):
			if not (e is Dictionary) or str(e.get("type", "")) != "episode":
				continue
			var ek := B.ident(e.get("ratingKey", ""), "digits", 1, 12)
			if ek == "":
				continue
			var vid := PREFIX + ek
			videos.append({ "id": vid, "title": B.text(e.get("title", "")), "season": B.num(e.get("parentIndex", 0)),
				"episode": B.num(e.get("index", 0)), "released": B.text(e.get("originallyAvailableAt", ""), 20),
				"thumbnail": img(origin, e.get("thumb", ""), 640, 360), "overview": B.text(e.get("summary", ""), B.DESC_MAX), "available": true })
			_progress_of(e, vid, prog)
		MoviesScript.sort_videos(videos)
	elif out.type == "movie":
		_progress_of(m, str(out.id), prog)
	var seasons: Array = []
	for v in videos:
		if not (int(v.season) in seasons):
			seasons.append(int(v.season))
	seasons.sort()
	if 0 in seasons:
		seasons.erase(0)
		seasons.append(0)
	var ids := { "imdb": "", "tmdb": "" }
	for g in B.arr(m.get("Guid", []), 10):
		var gid := B.text(B.dict(g).get("id", ""), 80)
		if gid.begins_with("imdb://"):
			ids.imdb = B.ident(gid.substr(7), "alnum", 3, 16)
		elif gid.begins_with("tmdb://"):
			ids.tmdb = B.ident(gid.substr(7), "digits", 1, 12)
	var countries := _tags(m.get("Country", []), 2)
	out.merge({
		"released": B.text(m.get("originallyAvailableAt", ""), 20), "cast": cast, "people": people,
		"director": _tags(m.get("Director", []), 4), "writer": _tags(m.get("Writer", []), 4), "trailers": [], "links": [],
		"country": countries[0] if not countries.is_empty() else "", "awards": "", "videos": videos, "seasons": seasons,
		"imdb_id": str(ids.imdb), "tmdb_id": str(ids.tmdb), "default_video_id": str(out.id) if out.type == "movie" else "",
		"server_progress": prog, "rating_key": B.ident(m.get("ratingKey", ""), "digits", 1, 12),
	}, true)
	return out


static func _progress_of(m: Dictionary, vid: String, into: Dictionary) -> void:
	var pos := B.num(m.get("viewOffset", 0)) / 1000.0
	var seen := B.num(m.get("viewCount", 0)) > 0
	var at := B.num(m.get("lastViewedAt", 0))
	if pos > 0.0 or seen:
		into[vid] = { "position": 0.0 if seen and pos <= 0.0 else pos, "duration": B.num(m.get("duration", 0)) / 1000.0, "watched": seen and pos <= 0.0,
				"updated": at }


static func quality(res: Variant, height: Variant) -> int:
	var r := B.text(res, 10).to_lower()
	match r:
		"4k", "2160": return 2160
		"1080", "1080p": return 1080
		"720", "720p": return 720
		"576", "480", "sd": return 480
	var h := B.num(height, 0)
	if h >= 1600:
		return 2160
	if h >= 1000:
		return 1080
	if h >= 650:
		return 720
	return 480 if h > 0 else 0


static func codec(v: Variant) -> String:
	match B.text(v, 12).to_lower():
		"hevc", "h265": return "HEVC"
		"h264", "avc": return "AVC"
		"av1": return "AV1"
		"vp9": return "VP9"
		"mpeg2video": return "MPEG-2"
	return ""


## Dateien eines Titels zum Abspielen – je Fassung (Media) „Direct Play“ (die Datei selbst) und
## „Direct Stream“ (der Server packt sie ohne Umrechnen des Bilds in HLS um). Format wie die
## Streams der Addons (Movies.parse_stream); dazu externe Untertitel des Servers.
static func parse_streams(d: Variant, origin: String, token: String, client_id: String, label: String) -> Array:
	var list := B.arr(_container(d).get("Metadata", []), 1)
	if list.is_empty() or not (list[0] is Dictionary):
		return []
	var m: Dictionary = list[0]
	var rk := B.ident(m.get("ratingKey", ""), "digits", 1, 12)
	var out: Array = []
	var media := B.arr(m.get("Media", []), 8)
	for i in media.size():
		var md := B.dict(media[i])
		var parts := B.arr(md.get("Part", []), 1)
		if parts.is_empty():
			continue
		var part := B.dict(parts[0])
		var key := B.safe_path(part.get("key", ""))
		var pid := B.ident(part.get("id", ""), "digits", 1, 12)
		if rk == "" or pid == "" or not key.begins_with("/library/parts/"):
			continue
		var hdr := ""
		var subs: Array = []
		var audio := ""
		for s in B.arr(part.get("Stream", []), 80):
			var st := B.dict(s)
			match B.num(st.get("streamType", 0)):
				1:
					if B.flag(st.get("DOVIPresent", false)):
						hdr = "DV"
					elif hdr == "":
						hdr = { "smpte2084": "HDR10", "arib-std-b67": "HLG" }.get(B.text(st.get("colorTrc", ""), 20), "")
				2:
					if audio == "" and B.flag(st.get("selected", false)):
						audio = B.text(st.get("displayTitle", ""), 60)
				3:
					var sk := B.safe_path(st.get("key", ""))
					if sk.begins_with("/library/streams/"):
						var lang := B.ident(st.get("languageCode", st.get("languageTag", "")), "token", 2, 8)
						subs.append({ "id": "plex-sub:" + sk, "url": origin + sk, "lang": lang,
							"label": MoviesScript.lang_label(lang) + "  ·  " + B.text(st.get("displayTitle", "Untertitel"), 40) })
		var q := quality(md.get("videoResolution", ""), md.get("height", 0))
		var size := B.num(part.get("size", 0))
		var file := B.text(part.get("file", ""), 260).replace("\\", "/").get_file()
		var desc := PackedStringArray()
		for x in [B.text(md.get("container", ""), 10).to_upper(), audio, B.text(md.get("title", ""), 40)]:
			if str(x) != "":
				desc.append(str(x))
		var auth := { "X-Plex-Token": token, "X-Plex-Client-Identifier": client_id, "X-Plex-Product": "Uzai" }
		var base := {
			"title": file, "description": "  ·  ".join(desc), "addon_id": ADDON, "addon_name": label, "headers": auth,
			"quality": q, "hdr": hdr, "codec": codec(md.get("videoCodec", "")), "size_bytes": size, "size_text": MoviesScript.size_text(size),
			"is_p2p": false, "info_hash": "", "source": "server", "subtitles": subs, "filename": file, "cached": true,
		}
		var direct := base.duplicate(true)
		direct.merge({ "id": "plex-part:" + pid, "name": "Direct Play", "url": origin + key, "binge_group": "plex-direct", "order": i * 2 }, true)
		out.append(direct)
		var stream := base.duplicate(true)
		stream.merge({ "id": "plex-stream:%s:%d" % [rk, i], "name": "Direct Stream", "url": origin + stream_path(rk, i, client_id),
			"binge_group": "plex-stream", "order": i * 2 + 1, "size_text": "", "subtitles": [] }, true)
		out.append(stream)
	return out


## HLS vom Server ohne Umrechnen des Bilds (Ton und Bild werden nur umverpackt).
static func stream_path(rk: String, media_index: int, client_id: String) -> String:
	var sess := B.random_id()
	return "/video/:/transcode/universal/start.m3u8?path=%s&mediaIndex=%d&partIndex=0&protocol=hls&fastSeek=1&directPlay=0&directStream=1&directStreamAudio=1&videoQuality=100&subtitles=none&location=lan&session=%s&X-Plex-Session-Identifier=%s&X-Plex-Client-Identifier=%s&X-Plex-Product=Uzai&X-Plex-Client-Profile-Name=Generic" % [
		("/library/metadata/" + rk).uri_encode(), media_index, sess, sess, client_id]


# --- Pfade ---------------------------------------------------------------------------------------

static func items_path(lib_key: String, type: String, start: int, size: int, sort := "titleSort", genre := "") -> String:
	var p := "/library/sections/%s/all?type=%d&sort=%s&X-Plex-Container-Start=%d&X-Plex-Container-Size=%d" % [lib_key, 1 if type == "movie" else 2,
			sort.uri_encode(), maxi(start, 0), clampi(size, 1, 200)]
	return p + ("&genre=" + genre if genre != "" else "")


static func collection_path(rk: String, start: int, size: int) -> String:
	return "/library/collections/%s/children?X-Plex-Container-Start=%d&X-Plex-Container-Size=%d" % [rk, maxi(start, 0), clampi(size, 1, 200)]


## Wiedergabe-Stand an den Server (state: playing, paused, stopped), Zeiten in Millisekunden.
static func timeline_path(rk: String, state: String, time_ms: int, dur_ms: int) -> String:
	return "/:/timeline?ratingKey=%s&key=%s&state=%s&time=%d&duration=%d&identifier=%s" % [rk, ("/library/metadata/" + rk).uri_encode(), state, maxi(time_ms, 0),
			maxi(dur_ms, 0), LIB]


## Als gesehen markieren bzw. zurücknehmen.
static func scrobble_path(rk: String, on: bool) -> String:
	return "/:/%s?identifier=%s&key=%s" % ["scrobble" if on else "unscrobble", LIB, rk]

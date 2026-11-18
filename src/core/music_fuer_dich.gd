extends "res://src/core/music_listen.gd"
## Musik, Schicht über music_listen.gd: „Für dich“ – meistgehört, Alben, Neues von deinen Künstlern
## und die Mixe von Spotify (Mix der Woche, Release Radar, Daily Mix) bzw. Uzais eigene Mixe, mit
## Zwischenspeicher für den schnellen Start.

## „Für dich“-Abschnitte der Startseite: Für dich gemacht (Mix der Woche, Release Radar, Daily Mix)
## und Deine Top-Mixe. librespot-nahe Clients (psst, spotatui, nocturne) lesen sie genauso.
const HOME_SECTIONS := ["spotify:section:0JQ5DAUnp4wcj0bCb3wh3S", "spotify:section:0JQ5DAnM3wGh0gz1MXnu89"]
## Persisted-Query-Hash von „homeSection“. Spotify dreht ihn, wenn es einen neuen Web-Client
## ausliefert; passt er nicht (HTTP 400 PersistedQueryNotFound), fällt Uzai auf die alten Wege zurück.
const PF_HOME_HASH := "c11ff5d8f508cb1a3dad3f15ee80611cda7df7e6fb45212e466fb3e84a680bf9"
const MADE_FOR_YOU := "0JQ5DAqbMKFHOzuVTgTizF"           ## Kategorie „Für dich gemacht“
const NEW_DAYS := 42              ## „Neu von deinen Künstlern“: Veröffentlichungen der letzten sechs Wochen
const FY_MAX_AGE := 20 * 60       ## Für dich höchstens alle 20 Minuten neu abrufen (Sekunden)

const Lang := preload("res://src/core/lang.gd")

var top_tracks: Array = []      ## meistgehört, letzte vier Wochen
var top_long: Array = []        ## meistgehört, über Jahre
var saved_albums: Array = []    ## gespeicherte Alben
var new_releases: Array = []    ## neue Alben und Singles deiner Künstler
var mix_ways := ""              ## welche Wege die Mixe gefunden haben (Protokoll, Verbindung prüfen)
var for_you_parts := {}         ## Teil -> "laedt" | "ok" | "leer" | "fehler" | "fehlt" (Freigabe fehlt)
var _home_warned := false           ## pathfinder-Hash veraltet: nur einmal ins Protokoll
var _new_at := 0                    ## „Neu von deinen Künstlern“ zuletzt geholt (schont das Kontingent)
var _new_tracks: Array = []


# --- Für dich ------------------------------------------------------------------

## Alles für „Für dich“ laden: Top-Titel, Alben, Neues von deinen Künstlern und die Mixe von
## Spotify (über die Suche). Jeder Teil meldet sich einzeln (lists_changed "fuerdich").
func load_for_you(force := false) -> void:
	if demo():
		_demo_for_you()
		lists_changed.emit("fuerdich")
		return
	if not has_spotify() or for_you_loading():
		return
	if grundmodus():
		# Grundmodus: Spotify gibt Mixe und Hördaten auf diesem Weg nicht heraus – gar nicht fragen.
		for_you_parts = {}
		return
	var age := int(Time.get_unix_time_from_system()) - _fy_at
	if not force and _fy_at > 0 and age < FY_MAX_AGE:
		return
	if top_tracks.is_empty() and saved_albums.is_empty() and spotify_mixes.is_empty():
		_load_fy_cache()
	_fy_at = int(Time.get_unix_time_from_system())
	for k in ["top", "alben", "neu", "mixe"]:
		for_you_parts[k] = "laedt"
	lists_changed.emit("fuerdich")
	await ensure_me()
	await _parallel([_fy_top, _fy_albums, _fy_new, _fy_mixes])
	if recent_list.is_empty():
		await load_recent()
	if for_you_parts.values().has("ok"):
		_save_fy_cache()
	else:
		_fy_at = 0      # alles fehlgeschlagen (offline?): beim nächsten Besuch gleich nochmal
	lists_changed.emit("fuerdich")


func for_you_loading() -> bool:
	return for_you_parts.values().has("laedt")


func _fy_top() -> void:
	if app_mode():
		# Wie die Spotify-App: Top-Titel über pathfinder (userTopContent; nur „zuletzt“ – für
		# „Lange nicht gehört“ fragt Uzai die Web-API bzw. die eigene Client-ID).
		var pr := await _pf("userTopContent", { "includeTopArtists": false, "includeTopTracks": true,
			"topArtistsInput": { "offset": 0, "limit": 1, "sortBy": "AFFINITY" }, "topTracksInput": { "offset": 0, "limit": 50, "sortBy": "AFFINITY" } })
		if pr.ok:
			top_tracks = []
			for t in Intern.top(pr.data, "tracks"):
				var tr := track_from(t)
				if not tr.is_empty():
					top_tracks.append(tr)
			var rl := await _api(HTTPClient.METHOD_GET, "/me/top/tracks?time_range=long_term&limit=50")
			if rl.ok and rl.data is Dictionary:
				top_long = tracks_from_items(Fremd.liste(rl.data, "items"))
			for_you_parts["top"] = "ok"
			lists_changed.emit("fuerdich")
			return
	var r := await _api(HTTPClient.METHOD_GET, "/me/top/tracks?time_range=short_term&limit=50")
	if not r.ok and str(r.get("why", "")) == "freigabe":
		need_login = relogin_helps()
		for_you_parts["top"] = "fehlt"
		lists_changed.emit("fuerdich")
		return
	if r.ok and r.data is Dictionary:
		top_tracks = tracks_from_items(Fremd.liste(r.data, "items"))
	var r2 := await _api(HTTPClient.METHOD_GET, "/me/top/tracks?time_range=long_term&limit=50")
	if r2.ok and r2.data is Dictionary:
		top_long = tracks_from_items(Fremd.liste(r2.data, "items"))
	for_you_parts["top"] = "ok" if r.ok else "fehler"
	lists_changed.emit("fuerdich")


func _fy_albums() -> void:
	if app_mode():
		var pr := await _pf("libraryV3", _lib_vars("Albums", 50, 0))
		if pr.ok:
			saved_albums = []
			for d in Intern.library_items(pr.data):
				var a := album_from(Intern.album(d))
				if not a.is_empty():
					saved_albums.append(a)
			for_you_parts["alben"] = "ok"
			lists_changed.emit("fuerdich")
			return
	var r := await _api(HTTPClient.METHOD_GET, "/me/albums?limit=50")
	if r.ok and r.data is Dictionary:
		var out: Array = []
		for it in Fremd.liste(r.data, "items"):
			if it is Dictionary:
				var a := album_from((it as Dictionary).get("album"))
				if not a.is_empty():
					out.append(a)
		saved_albums = out
	for_you_parts["alben"] = "ok" if r.ok else "fehler"
	lists_changed.emit("fuerdich")


## „Neu von deinen Künstlern“ – ein eigenes Release Radar: neue Alben und Singles der Künstler,
## die du am meisten hörst und denen du folgst, aus den letzten sechs Wochen.
func _fy_new() -> void:
	# Bis zu 18 Abrufe je Durchgang: nur alle 6 Stunden, sonst ist das Kontingent schnell leer.
	var t0 := int(Time.get_unix_time_from_system())
	if not new_releases.is_empty() and t0 - _new_at < 6 * 3600:
		for_you_parts["neu"] = "ok"
		lists_changed.emit("fuerdich")
		return
	var artists: Array = []
	var seen := {}
	var scope_missing := false
	if app_mode():
		# Wie die Spotify-App: Top-Künstler (userTopContent) und gefolgte (libraryV3) über pathfinder.
		var pa := await _pf("userTopContent", { "includeTopArtists": true, "includeTopTracks": false,
			"topArtistsInput": { "offset": 0, "limit": 20, "sortBy": "AFFINITY" }, "topTracksInput": { "offset": 0, "limit": 1, "sortBy": "AFFINITY" } })
		for a in (Intern.top(pa.data, "artists") if pa.ok else []):
			if not seen.has(str(a.id)):
				seen[str(a.id)] = true
				artists.append(str(a.id))
		var pf2 := await _pf("libraryV3", _lib_vars("Artists", 50, 0))
		for d in (Intern.library_items(pf2.data) if pf2.ok else []):
			var a2 := Intern.artist(d)
			if not a2.is_empty() and not seen.has(str(a2.id)):
				seen[str(a2.id)] = true
				artists.append(str(a2.id))
	for path in ([] if not artists.is_empty()
			else ["/me/top/artists?time_range=short_term&limit=20", "/me/top/artists?time_range=medium_term&limit=20", "/me/following?type=artist&limit=50"]):
		var r := await _api(HTTPClient.METHOD_GET, path)
		if not r.ok and str(r.get("why", "")) == "freigabe":
			scope_missing = true
			continue
		if not r.ok or not (r.data is Dictionary):
			continue
		var d: Dictionary = r.data
		var items := Fremd.liste(d, "artists/items") if d.get("artists") is Dictionary else Fremd.liste(d.get("items"))
		for a in items:
			if a is Dictionary and str(a.get("id", "")) != "" and not seen.has(str(a.id)):
				seen[str(a.id)] = true
				artists.append(str(a.id))
	if artists.is_empty():
		if scope_missing:
			need_login = relogin_helps()
		for_you_parts["neu"] = "fehlt" if scope_missing else "leer"
		lists_changed.emit("fuerdich")
		return
	var found: Array = []
	var braked := false
	for aid in artists.slice(0, 18):
		if not await _artist_releases(str(aid), found):
			braked = true
			break
	new_releases = fresh_releases(found, int(Time.get_unix_time_from_system()), NEW_DAYS).slice(0, 24)
	if not braked:
		_new_at = t0
	_new_tracks = []
	for_you_parts["neu"] = "ok" if not new_releases.is_empty() else "leer"
	lists_changed.emit("fuerdich")


## false: Spotify bremst (dann nicht weiter fragen).
func _artist_releases(aid: String, into: Array) -> bool:
	if app_mode():
		var pr := await _pf("queryArtistOverview", { "uri": "spotify:artist:" + aid, "locale": "", "includePrerelease": true })
		if int(pr.get("code", 0)) == 429:
			return false
		var ov := Intern.artist_overview(pr.data) if pr.ok else {}
		if not ov.is_empty():
			for a in ov["releases"]:
				var al := album_from(a)
				if not al.is_empty():
					into.append(al)
			return true
	var r := await _api(HTTPClient.METHOD_GET, "/artists/%s/albums?include_groups=album,single&limit=10" % aid)
	if r.ok and r.data is Dictionary:
		for a in Fremd.liste(r.data, "items"):
			var al := album_from(a)
			if not al.is_empty():
				into.append(al)
	return int(r.code) != 429


## Mix der Woche, Release Radar, Daily Mix: Wie die Spotify-App kommen deine echten Mixe (mit
## Titeln) der Reihe nach über die Kategorie „Für dich gemacht“, die interne Ansicht made-for-x und
## deine gefolgten Playlists. Eigenen Apps gibt Spotify sie nur noch über die Suche heraus (ohne
## Titelliste): gesucht wird auf Deutsch und Englisch, genommen nur, was Spotify gehört. Welcher Weg
## etwas gebracht hat, steht im Protokoll (logs/spotify.log) und in mix_ways.
func _fy_mixes() -> void:
	var found: Array = []
	var ways := PackedStringArray()
	var ok := false
	if app_mode():
		# Zuerst der Weg der echten Spotify-App über api-partner (pathfinder): die Startseite „Für
		# dich“. Er nimmt die Kennung der Desktop-App an, auch wenn die Web-API (api.spotify.com) sie
		# dauerhaft bremst – darum kommen hier deine echten Mixe mit Titeln, wenn sonst nichts geht.
		var home := await _mixes_via_home()
		if not home.is_empty():
			found.append_array(home)
			ok = true
			ways.append("Startseite")
			_log("Mixe über Startseite (pathfinder): %d Listen" % home.size())
		# Genug echte Mixe von der Startseite: die alten Wege (api.spotify.com) sparen wir uns.
		if pick_spotify_mixes(found).size() >= 4:
			spotify_mixes = pick_spotify_mixes(found)
			mix_ways = ", ".join(ways)
			_log("Mixe: %d gefunden (%s)" % [spotify_mixes.size(), mix_ways])
			for_you_parts["mixe"] = "ok"
			lists_changed.emit("fuerdich")
			return
		var ways_app := [
			["Kategorie", "/browse/categories/%s/playlists?limit=50&locale=%s" % [MADE_FOR_YOU, Lang.api("spotify")]],
			["made-for-x", "/views/made-for-x?content_limit=50&limit=20&types=playlist&locale=%s&platform=web" % Lang.api("spotify")],
			["gefolgt", "/me/playlists?limit=50"],
		]
		for w in ways_app:
			var r := await _api(HTTPClient.METHOD_GET, str(w[1]), null, true)
			var n := 0
			if r.ok and r.data is Dictionary:
				ok = true
				for p in collect_playlists(r.data):
					var pl := playlist_from(p)
					if not pl.is_empty():
						pl["mfy"] = str(w[0]) != "gefolgt"
						found.append(pl)
						n += 1
			_log("Mixe über %s: %s" % [str(w[0]), ("%d Listen" % n) if r.ok else "HTTP %d %s" % [int(r.get("code", 0)), _brief(r.get("data"))]])
			if n > 0:
				ways.append(str(w[0]))
			# Genug echte Mixe beisammen: die übrigen Wege braucht es nicht.
			if pick_spotify_mixes(found).size() >= 4:
				break
	if pick_spotify_mixes(found).size() < 2:
		var n2 := 0
		for q in ["Dein Mix der Woche", "Discover Weekly", "Release Radar", "Daily Mix", "In Dauerschleife"]:
			var r := await _api(HTTPClient.METHOD_GET, "/search?type=playlist&limit=%d&q=%s" % [SEARCH_LIMIT, q.uri_encode()])
			if not r.ok or not (r.data is Dictionary):
				continue
			ok = true
			for p in _items_of(r.data, "playlists"):
				var pl := playlist_from(p)
				if not pl.is_empty():
					found.append(pl)
					n2 += 1
		if n2 > 0:
			ways.append("Suche")
	spotify_mixes = pick_spotify_mixes(found)
	mix_ways = ", ".join(ways)
	if app_mode():
		_log("Mixe: %d gefunden (%s)" % [spotify_mixes.size(), mix_ways if mix_ways != "" else "kein Weg"])
	for_you_parts["mixe"] = ("ok" if not spotify_mixes.is_empty() else "leer") if ok else "fehler"
	lists_changed.emit("fuerdich")


## Deine echten Mixe über die Startseite der Spotify-App (api-partner/pathfinder): Für dich gemacht
## und Deine Top-Mixe. Dieser Weg nimmt die Kennung der Desktop-App an, auch wenn die Web-API
## (api.spotify.com) sie bremst. Gibt Playlists in Uzais Form zurück (mfy = aus „Für dich gemacht“).
func _mixes_via_home() -> Array:
	if _partner == "":
		return []
	var out: Array = []
	var seen := {}
	for sec in HOME_SECTIONS:
		var r := await _pathfinder("homeSection", PF_HOME_HASH,
				{ "uri": sec, "timeZone": str(Lang.ZEITZONE.get(Config.land(), "Europe/Berlin")), "sp_t": "", "sectionItemsOffset": 0, "sectionItemsLimit": 20 })
		if int(r.get("code", 0)) == 429:
			_log("Mixe über Startseite (pathfinder): gebremst (429)")
			break
		if not r.ok or not (r.data is Dictionary):
			if int(r.get("code", 0)) == 400 and not _home_warned:
				_home_warned = true
				_log("Mixe über Startseite (pathfinder): Hash veraltet (HTTP 400) – Uzai nimmt die alten Wege")
			continue
		for p in _pf_home_playlists(r.data):
			if not seen.has(str(p.id)):
				seen[str(p.id)] = true
				out.append(p)
	return out


## Playlists aus einer homeSection-Antwort (data.homeSections.sections[].sectionItems.items[]).
static func _pf_home_playlists(d: Variant) -> Array:
	var out: Array = []
	var sections: Variant = ((d as Dictionary).get("data", {}) as Dictionary).get("homeSections", {}) if d is Dictionary \
			and (d as Dictionary).get("data") is Dictionary else {}
	var secs: Array = (sections as Dictionary).get("sections", []) if sections is Dictionary and (sections as Dictionary).get("sections") is Array else []
	for s in secs:
		if not (s is Dictionary):
			continue
		var si: Variant = (s as Dictionary).get("sectionItems")
		var items: Array = (si as Dictionary).get("items", []) if si is Dictionary and (si as Dictionary).get("items") is Array else []
		for it in items:
			if not (it is Dictionary):
				continue
			var data: Variant = ((it as Dictionary).get("content", {}) as Dictionary).get("data") if (it as Dictionary).get("content") is Dictionary else null
			if not (data is Dictionary) or str((data as Dictionary).get("__typename", "")) != "Playlist":
				continue
			var dd: Dictionary = data
			var uri := str(dd.get("uri", ""))
			if not uri.begins_with("spotify:playlist:"):
				continue
			var owner: Dictionary = (dd.get("ownerV2", {}) as Dictionary).get("data", {}) if dd.get("ownerV2") is Dictionary else {}
			var ouri := str(owner.get("uri", "")) if owner.get("uri") != null else ""
			out.append({
				"kind": "playlist", "id": uri.get_slice(":", 2), "uri": uri, "name": str(dd.get("name", "")),
				"count": 0, "art": _pf_image(dd.get("images")),
				"owner": str(owner.get("name", "")) if owner.get("name") != null else "",
				"owner_id": ouri.get_slice(":", 2) if ouri.begins_with("spotify:user:") else ouri,
				"collab": false, "mine": false, "desc": clean_text(str(dd.get("description", ""))) if dd.get("description") != null else "",
				"mfy": true,
			})
	return out


## Bild-URL aus pathfinders Form images.items[0].sources[0].url.
static func _pf_image(imgs: Variant) -> String:
	if not (imgs is Dictionary):
		return ""
	var items: Variant = (imgs as Dictionary).get("items")
	if not (items is Array) or (items as Array).is_empty() or not (items[0] is Dictionary):
		return ""
	var sources: Variant = (items[0] as Dictionary).get("sources")
	if sources is Array and not (sources as Array).is_empty() and sources[0] is Dictionary:
		return str((sources[0] as Dictionary).get("url", ""))
	return ""


# --- Uzais eigene Mixe und Zwischenspeicher ------------------------------------------------------

func _mix(id: String, name: String, sub: String, desc: String, tracks: Array) -> Dictionary:
	return { "kind": "mix", "id": id, "name": name, "sub": sub, "desc": desc, "tracks": tracks, "count": tracks.size(),
		"arts": arts_of(tracks), "hue": float(HUES.get(id, 0.6)), "uri": "" }


## Uzais eigene Mixe aus deinen Hördaten (nur die, für die es genug Titel gibt).
func own_mixes() -> Array:
	var out: Array = []
	if not top_tracks.is_empty():
		out.append(_mix("mix:top", "Deine Top-Titel", "Diesen Monat", "Was du in den letzten vier Wochen am meisten gehört hast.", top_tracks))
	# Ist das echte Release Radar da (wie die Spotify-App, mit Titeln), braucht es das eigene nicht
	# doppelt; die Reihe „Neu von deinen Künstlern“ (Alben) bleibt.
	if not new_releases.is_empty() and not (mix_titles() and spotify_mixes.any(func(x): return str(x.get("mix", "")) == "radar")):
		var m := _mix("mix:neu", "Neu von deinen Künstlern", "Eigenes Release Radar",
				"Neue Alben und Singles deiner Künstler aus den letzten sechs Wochen, je die ersten Titel.", _new_tracks)
		m["arts"] = arts_of(new_releases)
		m["count"] = new_releases.size()
		m["count_label"] = plural_text(new_releases.size(), "Neuheit", "Neuheiten")
		out.append(m)
	var lange := long_unheard(top_long, top_tracks, recent_list)
	if lange.size() >= 5:
		out.append(_mix("mix:lange", "Lange nicht gehört", "Wiederentdecken", "Früher oft gehört, zuletzt kaum: deine Lieblinge von damals.", lange))
	if not recent_list.is_empty():
		out.append(_mix("mix:zuletzt", "Zuletzt gehört", "Weiterhören", "Was zuletzt bei dir lief.", recent_list))
	return out


## Titel eines Mixes; „Neu von deinen Künstlern“ lädt dafür die ersten Titel jeder Neuheit.
func mix_tracks(mix_id: String) -> Array:
	if mix_id == "mix:neu":
		return await new_release_tracks()
	for m in own_mixes():
		if str(m.id) == mix_id:
			return m.tracks
	return []


func new_release_tracks() -> Array:
	if not _new_tracks.is_empty():
		return _new_tracks
	var per: Dictionary = {}
	var calls: Array = []
	for a in new_releases.slice(0, 16):
		calls.append(_release_part.bind(a, per))
	await _parallel(calls)
	var out: Array = []
	for a in new_releases.slice(0, 16):
		out.append_array(per.get(str(a.id), []))
	_new_tracks = out
	return out


func _release_part(a: Dictionary, into: Dictionary) -> void:
	into[str(a.id)] = await album_tracks(a, 2 if str(a.get("type", "")) == "album" else 1)


func _fy_cache_path() -> String:
	return Config.path("cache/spotify_fuerdich.json")


func _save_fy_cache() -> void:
	var f := FileAccess.open(_fy_cache_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({ "at": int(Time.get_unix_time_from_system()), "top": top_tracks, "long": top_long,
		"albums": saved_albums, "new": new_releases, "mixes": spotify_mixes }))
	f.close()


## Letzter Stand von „Für dich“ (höchstens eine Woche alt), damit die Seite sofort gefüllt ist.
func _load_fy_cache() -> void:
	if not FileAccess.file_exists(_fy_cache_path()):
		return
	var d: Variant = Fremd.json_roh(FileAccess.get_file_as_string(_fy_cache_path()))
	if not (d is Dictionary) or int(Time.get_unix_time_from_system()) - int((d as Dictionary).get("at", 0)) > 7 * 86400:
		return
	# Nur Einträge in der erwarteten Form: Die Datei kann halb geschrieben oder von Hand geändert sein, und die
	# Listen gehen so, wie sie sind, in die Oberfläche.
	top_tracks = Fremd.zeilen(d, "top")
	top_long = Fremd.zeilen(d, "long")
	saved_albums = Fremd.zeilen(d, "albums")
	new_releases = Fremd.zeilen(d, "new")
	spotify_mixes = Fremd.zeilen(d, "mixes")


# --- Vorführung (--demo) ----------------------------------------------------------

func _demo_for_you() -> void:
	var all := demo_tracks()
	var extra := _demo_extra_tracks()
	top_tracks = [all[7], all[0], extra[0], all[3], extra[1], all[8], all[2], extra[2], all[1], all[6]]
	top_long = [all[5], all[4], extra[3], extra[4], all[0], extra[5], all[9], extra[6], extra[7], all[7]]
	recent_list = all
	saved_albums = _demo_saved_albums()
	new_releases = fresh_releases(demo_albums(), int(Time.get_unix_time_from_system()), NEW_DAYS)
	_new_tracks = []
	for a in new_releases:
		_new_tracks.append_array(demo_album_tracks(a).slice(0, 2 if str(a.type) == "album" else 1))
	if liked_list.is_empty():
		liked_list = all.slice(2)
	spotify_mixes = pick_spotify_mixes([
		{ "kind": "playlist", "id": "dw", "uri": "spotify:playlist:demo_dw", "name": "Dein Mix der Woche", "owner_id": "spotify", "owner": "Spotify", "art": "",
			"count": 30 },
		{ "kind": "playlist", "id": "rr", "uri": "spotify:playlist:demo_rr", "name": "Release Radar", "owner_id": "spotify", "owner": "Spotify", "art": "",
			"count": 30 },
		{ "kind": "playlist", "id": "d1", "uri": "spotify:playlist:demo_d1", "name": "Daily Mix 1", "owner_id": "spotify", "owner": "Spotify", "art": "",
			"count": 50 },
		{ "kind": "playlist", "id": "d2", "uri": "spotify:playlist:demo_d2", "name": "Daily Mix 2", "owner_id": "spotify", "owner": "Spotify", "art": "",
			"count": 50 },
		{ "kind": "playlist", "id": "fake", "uri": "spotify:playlist:fake", "name": "Release Radar", "owner_id": "jemand", "owner": "Jemand", "art": "",
			"count": 12 },
	])
	for k in ["top", "alben", "neu", "mixe"]:
		for_you_parts[k] = "ok"

extends "res://src/core/music_spotify.gd"
## Musik, Schicht über music_spotify.gd: die Listen aus Spotify – eigenes Konto, Playlists und ihre
## Titel, Warteschlange, Lieblingssongs, zuletzt gehört, Alben, Suche, Künstlerseiten und die
## Bibliothek (speichern und entfernen).

var now := {}            # { title, artist, album, art, duration, progress, playing, shuffle, repeat, device, id, uri, context, liked, volume }
var playlists: Array = []
var queue_list: Array = []      ## als Nächstes (Titel wie track_from)
var liked_list: Array = []
var recent_list: Array = []
var me := {}                    ## { id, name }
var list_error := ""            ## Fehler beim Laden einer Liste (zeigt die Liste selbst)
## Deine Playlists: noch nichts, laden, da oder Fehler; Abmelden setzt zurück.
const ZUSTAENDE_PLAYLISTS := { "*": [""], "": ["laedt"], "laedt": ["ok", "fehler"], "ok": ["laedt"], "fehler": ["laedt"] }
var playlists_state := "":
	set(neu):
		Zustand.wechsel("musik.playlists", ZUSTAENDE_PLAYLISTS, playlists_state, neu)
		playlists_state = neu
var _recent_loading := false
signal _part_done                ## ein Teil von _parallel ist fertig

const Verlauf := preload("res://src/core/spotify_verlauf.gd")
var verlauf: Array = []         ## eigener Hörverlauf (spotify_verlauf.gd), neueste zuerst
var _verlauf_loaded := false


# --- Eigener Verlauf (nur auf diesem PC) ---------------------------------------------------------

func _verlauf_path() -> String:
	return Config.path("spotify_verlauf.json")


func verlauf_list() -> Array:
	if not _verlauf_loaded:
		_verlauf_loaded = true
		if not demo():
			verlauf = Verlauf.load_list(Config.read_json(_verlauf_path(), {}))
	return verlauf


## Uzai merkt sich mit (Einstellung music.verlauf, Standard an)?
func verlauf_on() -> bool:
	return bool(Config.get_value("music.verlauf", true))


## Ein Eintrag (Verlauf.from_cluster bzw. from_now) kommt dazu; gespeichert nur bei Änderung.
func verlauf_note(e: Dictionary) -> void:
	if e.is_empty() or demo() or not verlauf_on():
		return
	var old := verlauf_list()
	var nxt := Verlauf.add(old, e)
	if nxt.size() == old.size() and not nxt.is_empty() and nxt[0] == old[0]:
		return
	var neu := old.is_empty() or str(nxt[0].u) != str(old[0].u) or nxt.size() != old.size()
	verlauf = nxt
	Config.write_json(_verlauf_path(), Verlauf.to_file(verlauf))
	if neu:
		if grundmodus():
			recent_list = Verlauf.recent(verlauf, 50)
		lists_changed.emit("verlauf")


## Verlauf löschen (Einstellungen › Konten › Spotify).
func verlauf_clear() -> void:
	verlauf = []
	_verlauf_loaded = true
	for p in [_verlauf_path(), _verlauf_path() + ".bak", _verlauf_path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if grundmodus():
		recent_list = []
	lists_changed.emit("verlauf")
	lists_changed.emit("recent")


# --- Bibliothek (Lieblingssongs, Alben) -----------------------------------------

func is_liked(id: String) -> bool:
	for t in liked_list:
		if str(t.id) == id:
			return true
	return false


## URIs für ?uris= (je URI kodiert, mit Komma getrennt; Spotify nimmt höchstens 40).
static func library_query(uris: Array) -> String:
	var parts := PackedStringArray()
	for u in uris.slice(0, 40):
		parts.append(str(u).uri_encode())
	return ",".join(parts)


## IDs je Art aus URIs (für die alten Wege /me/tracks und /me/albums).
static func ids_by_type(uris: Array) -> Dictionary:
	var out := {}
	for u in uris:
		var p := str(u).split(":")
		if p.size() == 3 and p[0] == "spotify":
			if not out.has(p[1]):
				out[p[1]] = []
			(out[p[1]] as Array).append(p[2])
	return out


## In der Bibliothek speichern (save) bzw. entfernen. Seit 2026 über PUT/DELETE /me/library mit
## URIs in der Adresse; klappt das nicht, die alten Wege je Art.
func library_set(uris: Array, save: bool) -> bool:
	if uris.is_empty() or demo():
		return true
	if grundmodus():
		return false
	if app_mode():
		# Wie die Spotify-App: über pathfinder (addToLibrary/removeFromLibrary). Spotify meldet eine
		# Ablehnung hier mit HTTP 200 und einer anderen Antwortart – darum die Art prüfen.
		var op := "addToLibrary" if save else "removeFromLibrary"
		var pr := await _pf(op, { "libraryItemUris": uris })
		if pr.ok:
			var res := Intern.dict(Intern.dig(pr.data, "data/" + ("addLibraryItems" if save else "removeLibraryItems")))
			var typ := Intern.s(res.get("__typename"))
			if typ == "" or typ.ends_with("Response"):
				return true
			_log("Intern %s: abgelehnt (%s)" % [op, typ])
	var method := HTTPClient.METHOD_PUT if save else HTTPClient.METHOD_DELETE
	var r := await _api(method, "/me/library?uris=" + library_query(uris))
	if r.ok:
		return true
	var by := ids_by_type(uris)
	var ok := not by.is_empty()
	for kind in by.keys():
		var path: String = { "track": "/me/tracks", "album": "/me/albums" }.get(kind, "")
		if path == "":
			ok = false
			continue
		var r2 := await _api(method, path + "?ids=" + ",".join(PackedStringArray(by[kind])))
		ok = ok and r2.ok
	return ok


## Liegen diese URIs in der Bibliothek? Array aus true/false in derselben Reihenfolge, [] bei Fehler.
func library_contains(uris: Array) -> Array:
	if uris.is_empty() or grundmodus():
		return []
	if app_mode():
		var pr := await _pf("areEntitiesInLibrary", { "uris": uris })
		var lk := Intern.lookup(pr.data, uris.size()) if pr.ok else []
		if not lk.is_empty():
			return lk
	var r := await _api(HTTPClient.METHOD_GET, "/me/library/contains?uris=" + library_query(uris))
	if r.ok and r.data is Array:
		return r.data
	var by := ids_by_type(uris)
	if by.size() == 1 and by.has("track"):
		var r2 := await _api(HTTPClient.METHOD_GET, "/me/tracks/contains?ids=" + ",".join(PackedStringArray(by.track)))
		if r2.ok and r2.data is Array:
			return r2.data
	return []


# --- Konto, Playlists, Warteschlange, Lieblingssongs, Zuletzt, Suche -----------------------------

## Wer bin ich bei Spotify (ID für „deine“ Playlists).
func ensure_me() -> void:
	if not me.is_empty() or demo() or _grund_ruht():
		return
	# Wie die Spotify-App: Name und Kennung über pathfinder (api.spotify.com bremst diese Anmeldung).
	if app_mode():
		var pr := await _pf("profileAttributes", {})
		var prof := Intern.dict(Intern.dig(pr.data, "data/me/profile")) if pr.ok else {}
		if not prof.is_empty():
			me = { "id": Intern.s(prof.get("username")), "name": Intern.s(prof.get("name")) }
			return
	var r := await _api(HTTPClient.METHOD_GET, "/me")
	if r.ok and r.data is Dictionary:
		var d: Dictionary = r.data
		me = { "id": str(d.get("id", "")), "name": str(d.get("display_name", "")) if d.get("display_name") != null else "" }


## Kontext der Lieblingssongs bei Spotify ("" in der Vorführung oder wenn Uzai die Kennung des Kontos nicht kennt).
func liked_uri() -> String:
	if demo():
		return ""
	await ensure_me()
	var id := str(me.get("id", ""))
	if id == "":
		# Im Grundmodus ruht ensure_me – die Kennung aus der Prüfung des Schlüssels reicht dann.
		id = str(_web_me.get("id", ""))
	return Intern.liked_context(id)


func load_playlists() -> void:
	if not has_spotify() or demo() or _grund_ruht():
		return
	playlists_state = "laedt"
	await ensure_me()
	if app_mode():
		# Wie die Spotify-App: deine Bibliothek über pathfinder (libraryV3), Ordner aufgeklappt.
		var out_pf: Array = []
		var ok_pf := false
		for page in 4:
			var pr := await _pf("libraryV3", _lib_vars("Playlists", 50, page * 50))
			if not pr.ok:
				break
			ok_pf = true
			var items := Intern.library_items(pr.data)
			for d in items:
				var pl := playlist_from(Intern.playlist(d), str(me.get("id", "")))
				if not pl.is_empty():
					out_pf.append(pl)
			var total := Intern.library_total(pr.data)
			if items.size() < 50 or (total >= 0 and (page + 1) * 50 >= total):
				break
		if ok_pf:
			playlists = out_pf
			playlists_state = "ok"
			list_error = ""
			updated.emit()
			lists_changed.emit("playlists")
			_anzahl_nachladen(out_pf)
			return
	var r := await _api(HTTPClient.METHOD_GET, "/me/playlists?limit=50")
	if not r.ok or not (r.data is Dictionary):
		playlists_state = "fehler"
		list_error = why_text(r, "Deine Playlists kamen nicht an.")
		lists_changed.emit("playlists")
		return
	var out: Array = []
	for p in Fremd.liste(r.data, "items"):
		var pl := playlist_from(p, str(me.get("id", "")))
		if not pl.is_empty():
			out.append(pl)
	playlists = out
	playlists_state = "ok"
	updated.emit()
	lists_changed.emit("playlists")


## libraryV3 nennt keine Titelzahl der Playlists (-1): die Web-API (/me/playlists) nachfragen und eintragen.
## Kommt nichts, bleibt die Zahl unbekannt – die Kachel zeigt dann keine statt „0 Titel“.
func _anzahl_nachladen(liste: Array) -> void:
	var offen := {}
	for pl in liste:
		if int((pl as Dictionary).get("count", 0)) < 0:
			offen[str(pl.id)] = pl
	if offen.is_empty():
		return
	var gefunden := 0
	for page in 4:
		var r := await _api(HTTPClient.METHOD_GET, "/me/playlists?limit=50&offset=%d" % (page * 50))
		if not r.ok or not (r.data is Dictionary):
			break
		var items: Array = Fremd.liste(r.data, "items")
		for p in items:
			if not (p is Dictionary):
				continue
			var tr: Variant = (p as Dictionary).get("tracks") if (p as Dictionary).get("tracks") is Dictionary else (p as Dictionary).get("items")
			var pid := str((p as Dictionary).get("id", ""))
			if offen.has(pid) and tr is Dictionary and (tr as Dictionary).get("total") != null:
				offen[pid]["count"] = int((tr as Dictionary).total)
				gefunden += 1
		if items.size() < 50 or gefunden >= offen.size():
			break
	if gefunden > 0 and playlists == liste:
		updated.emit()
		lists_changed.emit("playlists")


## Als Nächstes in Spotify (die Warteschlange, die Spotify gerade abspielt).
func load_queue() -> void:
	if not has_spotify() or demo():
		return
	if app_mode():
		var raw := await _cluster_read()
		if raw.is_empty() and grundmodus():
			return
		if not raw.is_empty():
			var q: Array = []
			for t in Intern.cluster(raw, _connect_dev, _now_ms()).queue:
				var e: Dictionary = t
				if str(e.title) == "" and q.size() < 10:
					var meta := await _track_meta(str(e.uri))
					if not meta.is_empty():
						e = meta
				if str(e.title) != "":
					q.append(e)
			queue_list = q
			lists_changed.emit("queue")
			return
	var r := await _api(HTTPClient.METHOD_GET, "/me/player/queue")
	if not r.ok or not (r.data is Dictionary):
		return
	var out: Array = []
	for t in Fremd.liste(r.data, "queue"):
		var tr := track_from(t)
		if not tr.is_empty():
			out.append(tr)
	queue_list = out.slice(0, 30)
	lists_changed.emit("queue")


## Alle Titel einer Playlist (bis 500). Erst der neue Weg /items, dann /tracks. Gibt Spotify
## sie nicht heraus (fremde Playlists, Mixe von Spotify), bleibt die Liste leer und list_error sagt warum.
## Wie die Spotify-App gibt es danach noch den Weg der Spotify-Apps selbst (_spclient_tracks).
func playlist_tracks(pid: String) -> Array:
	list_error = ""
	if demo():
		if pid == "demo3":
			list_error = restricted_text()
			return []
		return demo_tracks()
	var out: Array = []
	if app_mode():
		# Wie die Spotify-App: Titel über pathfinder (fetchPlaylist) – auch Mixe von Spotify und
		# fremde Playlists, ohne api.spotify.com.
		var got_pf := false
		var off := 0
		while off < 500:
			var pr := await _pf("fetchPlaylist", { "uri": "spotify:playlist:" + pid, "offset": off, "limit": 100, "enableWatchFeedEntrypoint": false })
			var pg := Intern.playlist_page(pr.data) if pr.ok else { "ok": false }
			if not bool(pg.ok):
				break
			got_pf = true
			for t in pg["items"]:
				var tr := track_from(t)
				if not tr.is_empty():
					out.append(tr)
			off += 100
			if int(pg["count"]) < 100 or off >= int(pg["total"]):
				break
		if got_pf:
			return out
	var paths := ["/playlists/%s/items?limit=50&additional_types=track" % pid, "/playlists/%s/tracks?limit=100&additional_types=track" % pid]
	var path := ""
	var first: Dictionary = {}
	for p in paths:
		first = await _api(HTTPClient.METHOD_GET, p)
		if first.ok and first.data is Dictionary:
			path = p
			break
	if path == "" and app_mode() and not (str(first.get("why", "")) in ["abgelaufen", "netz", "app"]):
		_log("Titel %s: Web-API HTTP %d – Weg der Spotify-App (context-resolve)" % [pid, int(first.get("code", 0))])
		out = await _spclient_tracks(pid)
		if not out.is_empty():
			return out
		list_error = "Spotify hat die Titel dieser Liste nicht geschickt – auch nicht auf dem Weg der Spotify-App. „Abspielen“ geht trotzdem."
		return out
	if path == "":
		var why := str(first.get("why", ""))
		if why in ["nutzer", "premium", "abgelaufen", "gesperrt", "netz", "bremse", "freigabe", "app"]:
			list_error = problem_text(why)
		elif int(first.get("code", 0)) in [403, 404]:
			list_error = restricted_text()
		else:
			list_error = why_text(first, "Spotify hat die Titel nicht geschickt.")
		return out
	var r := first
	var pages := 0
	while pages < 10 and out.size() < 500:
		pages += 1
		out.append_array(tracks_from_items(Fremd.liste(r.data, "items")))
		var nxt: Variant = (r.data as Dictionary).get("next")
		if not (nxt is String) or str(nxt) == "":
			break
		r = await _api(HTTPClient.METHOD_GET, str(nxt).replace(_api_base, ""))
		if not r.ok or not (r.data is Dictionary):
			break
	return out


## Titel über die interne Schnittstelle der Spotify-Apps (nur wie die Spotify-App): context-resolve
## liefert die Titel-URIs der Liste als JSON (so liest librespot Playlists), die Angaben dazu kommen
## gebündelt über /tracks?ids=. Ohne Angaben bleiben, falls vorhanden, Name und Künstler aus der Liste.
func _spclient_tracks(pid: String) -> Array:
	var uris: Array = []
	var meta := {}
	var url := _spclient + "/context-resolve/v1/spotify:playlist:" + pid
	var pages := 0
	while url != "" and pages < 6 and uris.size() < 500:
		pages += 1
		var r := await _api(HTTPClient.METHOD_GET, url, null, true)
		if not r.ok or not (r.data is Dictionary):
			_log("Titel %s über context-resolve: HTTP %d %s" % [pid, int(r.get("code", 0)), _brief(r.get("data"))])
			break
		var got := context_tracks(r.data)
		for t in got.tracks:
			if not meta.has(str(t.uri)):
				uris.append(str(t.uri))
				meta[str(t.uri)] = t
		url = spclient_url(_spclient, str(got.next))
	if uris.is_empty():
		return []
	var out: Array = []
	var found := {}
	for i in range(0, uris.size(), 50):
		var ids: Array = uris.slice(i, i + 50).map(func(u): return str(u).get_slice(":", 2))
		var r2 := await _api(HTTPClient.METHOD_GET, "/tracks?ids=" + ",".join(ids))
		if r2.ok and r2.data is Dictionary:
			for t in Fremd.liste(r2.data, "tracks"):
				var tr := track_from(t)
				if not tr.is_empty():
					found[str(tr.uri)] = tr
	for u in uris:
		if found.has(u):
			out.append(found[u])
		elif str(meta[u].get("title", "")) != "":
			out.append(meta[u])
	_log("Titel %s über context-resolve: %d Titel, %d mit Angaben" % [pid, uris.size(), found.size()])
	return out


## Titel eines Albums (mit Albumbild). limit klein: nur die ersten Titel (für Mixe).
func album_tracks(album: Dictionary, limit := 50) -> Array:
	var aid := str(album.get("id", ""))
	if aid == "":
		return []
	if demo():
		return demo_album_tracks(album).slice(0, limit)
	var fake_album := { "name": str(album.get("name", "")),
			"images": [{ "url": str(album.get("art_big", album.get("art", ""))) }, { "url": str(album.get("art", "")) }] }
	var items: Array = []
	var got := false
	if app_mode():
		var pr := await _pf("getAlbum", { "uri": "spotify:album:" + aid, "locale": "", "offset": 0, "limit": clampi(limit, 1, 50) })
		if pr.ok and Intern.dig(pr.data, "data/albumUnion") is Dictionary:
			items = Intern.album_page(pr.data)
			got = true
	if not got:
		var r := await _api(HTTPClient.METHOD_GET, "/albums/%s/tracks?limit=%d" % [aid, clampi(limit, 1, 50)])
		if not r.ok or not (r.data is Dictionary):
			return []
		items = Fremd.liste(r.data, "items")
	var out: Array = []
	for t in items:
		if t is Dictionary:
			var c: Dictionary = (t as Dictionary).duplicate()
			c["album"] = fake_album
			var tr := track_from(c)
			if not tr.is_empty():
				out.append(tr)
	return out


func load_liked() -> void:
	if demo():
		liked_list = demo_tracks().slice(2)
		lists_changed.emit("liked")
		return
	if not has_spotify() or grundmodus():
		return
	var out: Array = []
	if app_mode():
		# Wie die Spotify-App: Lieblingssongs über pathfinder (fetchLibraryTracks).
		var got := false
		for page in 4:
			var pr := await _pf("fetchLibraryTracks", { "offset": page * 50, "limit": 50 })
			var lk := Intern.liked(pr.data) if pr.ok else { "ok": false }
			if not bool(lk.ok):
				break
			got = true
			for t in lk["items"]:
				var tr := track_from(t)
				if not tr.is_empty():
					out.append(tr)
			if (lk["items"] as Array).size() < 50 or (page + 1) * 50 >= int(lk["total"]):
				break
		if got:
			liked_list = out
			lists_changed.emit("liked")
			return
	var path := "/me/tracks?limit=50"
	for i in 4:
		var r := await _api(HTTPClient.METHOD_GET, path)
		if not r.ok or not (r.data is Dictionary):
			break
		out.append_array(tracks_from_items(Fremd.liste(r.data, "items")))
		var nxt: Variant = (r.data as Dictionary).get("next")
		if not (nxt is String) or str(nxt) == "":
			break
		path = str(nxt).replace(_api_base, "")
	liked_list = out
	lists_changed.emit("liked")


## Läufe von load_recent, die gerade unterwegs sind (siehe dort).
var _load_recent_offen := 0


func load_recent() -> void:
	_load_recent_offen += 1
	await _load_recent_lauf()
	_load_recent_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und load_recent täte bis zum Neustart nichts mehr.
	if _load_recent_offen == 0 and _recent_loading:
		_recent_loading = false


func _load_recent_lauf() -> void:
	if demo() and not demo_grund:
		recent_list = demo_tracks()
		lists_changed.emit("recent")
		return
	if grundmodus():
		# Grundmodus: „Zuletzt gehört“ aus Uzais eigenem Verlauf (ohne Netz).
		recent_list = Verlauf.recent(verlauf_list(), 50)
		lists_changed.emit("recent")
		return
	if not has_spotify() or _recent_loading:
		return
	_recent_loading = true
	list_error = ""
	if app_mode():
		# Wie die Spotify-App: „Zuletzt gehört“ über spclient, Angaben je Titel über pathfinder.
		# Ohne eigene ID (GET /me gebremst) gäbe es nur /user//… → 404: dann gleich der Web-Weg.
		await ensure_me()
	if app_mode() and str(me.get("id", "")) != "":
		var rr := await _spc(HTTPClient.METHOD_GET,
				"/recently-played/v3/user/%s/recently-played?format=json&offset=0&limit=50&filter=default,collection-new-episodes&market=from_token" % str(me.get("id",
				"")).uri_encode())
		if rr.ok and rr.data is Dictionary:
			var outr: Array = []
			for u in Intern.recent_uris(rr.data, 20):
				var t := await _track_meta(str(u))
				if not t.is_empty():
					outr.append(t)
			_log("Zuletzt gehört (spclient): %d Titel" % outr.size())
			_recent_loading = false
			recent_list = outr
			lists_changed.emit("recent")
			lists_changed.emit("fuerdich")
			return
		_log("Zuletzt gehört (spclient): HTTP %d %s" % [int(rr.get("code", 0)), _brief(rr.get("data"))])
	var r := await _api(HTTPClient.METHOD_GET, "/me/player/recently-played?limit=50")
	_recent_loading = false
	if not r.ok or not (r.data is Dictionary):
		if str(r.get("why", "")) == "freigabe" and relogin_helps():
			list_error = "„Zuletzt gehört“ braucht eine neue Anmeldung bei Spotify (einmal neu verbinden)."
		else:
			list_error = why_text(r, "„Zuletzt gehört“ kam nicht an.")
		lists_changed.emit("recent")
		return
	var seen := {}
	var out: Array = []
	for t in tracks_from_items(Fremd.liste(r.data, "items")):
		if seen.has(t.id):
			continue
		seen[t.id] = true
		out.append(t)
	recent_list = out
	lists_changed.emit("recent")
	lists_changed.emit("fuerdich")


## Suche nach Titeln, Künstlern, Alben und Playlists (je höchstens 10 Treffer, wie die Spotify-App
## 20). Kommt nichts an, steht in "error", warum.
func search(q: String) -> Dictionary:
	if demo():
		return demo_search(q)
	if not has_spotify():
		var none := parse_search({})
		none["error"] = "Suchen braucht Spotify (Einstellungen → Konten)."
		return none
	if grundmodus():
		var quiet := parse_search({})
		quiet["error"] = "Suche gerade nicht erreichbar. Läuft gerade und Steuern gehen weiter."
		return quiet
	if app_mode():
		# Wie die Spotify-App: Suche über pathfinder (searchDesktop).
		var pr := await _pf("searchDesktop", { "searchTerm": q, "offset": 0, "limit": search_limit(), "numberOfTopResults": 5,
			"includeAudiobooks": false, "includeArtistHasConcertsField": false, "includePreReleases": false, "includeAuthors": false,
			"includeEpisodeContentRatingsV2": false })
		var sr := Intern.search(pr.data) if pr.ok else { "ok": false }
		if bool(sr.ok):
			return parse_search(sr, str(me.get("id", "")))
	var r := await _api(HTTPClient.METHOD_GET, "/search?type=track,artist,album,playlist&limit=%d&q=%s" % [search_limit(), q.uri_encode()])
	if int(r.get("code", 0)) == 400 and search_limit() > SEARCH_LIMIT:
		# Gilt die Grenze von 2026 doch: mit 10 nochmal.
		r = await _api(HTTPClient.METHOD_GET, "/search?type=track,artist,album,playlist&limit=%d&q=%s" % [SEARCH_LIMIT, q.uri_encode()])
	if not r.ok or not (r.data is Dictionary):
		var out := parse_search({})
		out["error"] = why_text(r, "Die Suche kam nicht an.")
		return out
	return parse_search(r.data, str(me.get("id", "")))


# --- Künstler ------------------------------------------------------------------

## Künstler des laufenden Titels: { id, name } (ID leer, wenn Windows den Titel meldet).
func artist_of_now() -> Dictionary:
	if now.is_empty():
		return {}
	var people: Array = now.get("artists", []) if now.get("artists") is Array else []
	if not people.is_empty() and people[0] is Dictionary and str(people[0].get("name", "")) != "":
		return { "id": str(people[0].get("id", "")), "name": str(people[0].name) }
	var nm := str(now.get("artist", "")).get_slice(",", 0).strip_edges()
	return { "id": str(now.get("artist_id", "")), "name": nm } if nm != "" else {}


## Alles für die Künstlerseite: { ok, artist, top, albums, singles, top_from ("top"|"suche"), error }.
## Ohne ID (Titel von Windows) sucht Uzai den Künstler erst über den Namen.
func artist_page(a: Dictionary) -> Dictionary:
	var aid := str(a.get("id", ""))
	var nm := str(a.get("name", ""))
	if demo():
		return demo_artist(nm)
	if not has_spotify():
		return { "ok": false, "error": "Künstlerseiten brauchen Spotify (Einstellungen → Konten)." }
	if app_mode():
		# Wie die Spotify-App: Künstler, beliebte Titel und Veröffentlichungen über pathfinder.
		if aid == "" and nm != "":
			var found_pf: Array = (await search(nm)).artists
			for c in found_pf:
				if str(c.name).to_lower() == nm.to_lower():
					aid = str(c.id)
					break
			if aid == "" and not found_pf.is_empty():
				aid = str(found_pf[0].id)
		if aid != "":
			var pr := await _pf("queryArtistOverview", { "uri": "spotify:artist:" + aid, "locale": "", "includePrerelease": true })
			var ov := Intern.artist_overview(pr.data) if pr.ok else {}
			if not ov.is_empty():
				var art := artist_from(ov["artist"])
				if art.is_empty():
					art = { "kind": "artist", "id": aid, "uri": "spotify:artist:" + aid, "name": nm, "art": "", "art_big": "", "followers": -1, "genres": [] }
				elif str(art.name) == "" and nm != "":
					art["name"] = nm
				var top_pf: Array = []
				for t in ov["top"]:
					var tr := track_from(t)
					if not tr.is_empty():
						top_pf.append(tr)
				var rel_pf := split_releases(ov["releases"])
				return { "ok": true, "artist": art, "top": top_pf.slice(0, 10), "albums": rel_pf.albums, "singles": rel_pf.singles, "top_from": "top", "error": "" }
	if aid == "" and nm != "":
		var s := await _api(HTTPClient.METHOD_GET, "/search?type=artist&limit=5&q=%s" % nm.uri_encode())
		var found: Array = parse_search(s.data if s.ok else {}).artists
		for c in found:
			if str(c.name).to_lower() == nm.to_lower():
				aid = str(c.id)
				break
		if aid == "" and not found.is_empty():
			aid = str(found[0].id)
		if aid == "":
			return { "ok": false, "error": "Spotify kennt „%s“ nicht als Künstler." % nm if s.ok else why_text(s, "Die Suche kam nicht an.") }
	var box := {}
	await _parallel([
		func() -> void: box["info"] = await _api(HTTPClient.METHOD_GET, "/artists/" + aid),
		func() -> void: box["top"] = await _api(HTTPClient.METHOD_GET, "/artists/%s/top-tracks" % aid),
		func() -> void: box["rel1"] = await _api(HTTPClient.METHOD_GET, "/artists/%s/albums?include_groups=album,single&limit=10" % aid),
		func() -> void: box["rel2"] = await _api(HTTPClient.METHOD_GET, "/artists/%s/albums?include_groups=album,single&limit=10&offset=10" % aid),
	])
	var info: Dictionary = box.info
	var artist := artist_from(info.data) if info.ok else {}
	if artist.is_empty():
		artist = { "kind": "artist", "id": aid, "uri": "spotify:artist:" + aid, "name": nm, "art": "", "art_big": "", "followers": -1, "genres": [] }
	elif nm != "" and str(artist.name) == "":
		artist["name"] = nm
	var top: Array = []
	var top_from := "top"
	var tr: Dictionary = box.top
	if tr.ok and tr.data is Dictionary:
		top = tracks_from_items(Fremd.liste(tr.data, "tracks"))
	if top.is_empty():
		# Top-Titel gibt es für eigene Apps nicht (mehr) überall: die beliebtesten Suchtreffer.
		top_from = "suche"
		var q := "artist:\"%s\"" % str(artist.name)
		var sr := await _api(HTTPClient.METHOD_GET, "/search?type=track&limit=%d&q=%s" % [SEARCH_LIMIT, q.uri_encode()])
		if sr.ok:
			top = tracks_of_artist(parse_search(sr.data).tracks, aid, str(artist.name))
	var items: Array = []
	for k in ["rel1", "rel2"]:
		var rr: Dictionary = box[k]
		if rr.ok and rr.data is Dictionary:
			items.append_array(Fremd.liste(rr.data, "items"))
	var rel := split_releases(items)
	var ok: bool = info.ok or not top.is_empty() or not items.is_empty()
	return { "ok": ok, "artist": artist, "top": top.slice(0, 10), "albums": rel.albums, "singles": rel.singles, "top_from": top_from,
		"error": "" if ok else why_text(info, "Spotify hat den Künstler nicht geschickt.") }


## „Alle Titel“ eines Künstlers (src/core/artist_catalog.gd): je Künstler (und mit/ohne
## Gastauftritte) eine Instanz; was schon geladen ist, bleibt. Höchstens KATALOGE_MAX – Uzai läuft oft tagelang,
## und jeder Katalog hält alle geladenen Titel. Eine offene Seite behält ihren Katalog auch danach.
const KATALOGE_MAX := 24
var _catalogs := {}


func artist_catalog(a: Dictionary, guest := false) -> RefCounted:
	var aid := str(a.get("id", ""))
	var key := (aid if aid != "" else "name:" + str(a.get("name", "")).to_lower()) + ("|gast" if guest else "")
	if not _catalogs.has(key):
		_catalogs[key] = ArtistCatalog.new().setup(a, guest)
		Config.cap(_catalogs, KATALOGE_MAX)
	return _catalogs[key]


## Vorführung: Suche in den Beispieldaten.
func demo_search(q: String) -> Dictionary:
	var ql := q.to_lower().strip_edges()
	var all: Array = demo_tracks() + _demo_extra_tracks()
	var tracks: Array = all.filter(func(t): return str(t.title + " " + t.artist + " " + t.album).to_lower().contains(ql))
	var artists: Array = []
	var seen := {}
	for t in all:
		var nm := str(t.artist)
		if nm.to_lower().contains(ql) and not seen.has(nm):
			seen[nm] = true
			artists.append(_demo_artist_info(nm))
	var albums: Array = (demo_albums() + _demo_saved_albums()).filter(func(a): return str(a.name + " " + a.artist).to_lower().contains(ql))
	var pls: Array = playlists.filter(func(p): return str(p.get("name", "")).to_lower().contains(ql))
	return { "tracks": tracks.slice(0, SEARCH_LIMIT), "artists": artists.slice(0, SEARCH_LIMIT), "albums": albums.slice(0, SEARCH_LIMIT), "playlists": pls }


# --- Mehrere Abfragen gleichzeitig ---------------------------------------------------------------

## Mehrere Abrufe gleichzeitig (Net lässt selbst höchstens sechs parallel laufen).
func _parallel(calls: Array) -> void:
	var box := { "left": calls.size() }
	for c in calls:
		_run_part(c, box)
	while int(box.left) > 0:
		await _part_done


func _run_part(c: Callable, box: Dictionary) -> void:
	await c.call()
	box.left = int(box.left) - 1
	_part_done.emit()

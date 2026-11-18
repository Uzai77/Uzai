extends "res://tests/probe_base.gd"
## Probe für die Filme-Quellen (Roadmap 35, Demo-Daten): Quellenwahl, Plex-PIN mit QR-Code und
## Server-Auswahl, Jellyfin mit Heimnetz-Suche, http-Hinweis und Quick Connect, Stremio-Hinweis,
## Startseite mit Plex- und Jellyfin-Reihen, eine Jellyfin-Bibliothek, Details, Dateien vom Server,
## der Player und der Kinderfilter. Ausgabe „MQ ok/FAIL …“.

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("MQ %s %s" % ["ok  " if cond else "FAIL", what])


func run() -> void:
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Config.set_value("controller.glyphs", "xbox")
	Nav.device_changed.emit("pad")
	Config.set_value("movies.sources", ["plex", "jellyfin", "addons"])
	# Die gemalten Demo-Bilder brauchen einen Moment.
	await wait(4.0)
	await _sources()
	await _plex()
	await _jellyfin()
	await _stremio()
	await _home()
	await _detail_and_player()
	await _kids()
	print("MQ Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))


func _close_layers() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.3)


func _to_movies() -> void:
	if main.current != "movies":
		main.goto("movies", "start")
		await wait(1.0)


func _sources() -> void:
	main.goto("movies", "start")
	await wait(1.2)
	main.open_movie_sources(true)
	await shot("01_quellenwahl", 1.2)
	await press("down")
	await shot("02_quellenwahl_jellyfin", 0.8)
	await press("down", 3)
	await shot("03_quellenwahl_stremio", 0.8)
	await _close_layers()


func _plex() -> void:
	await _to_movies()
	main.open_plex_login()
	await shot("10_plex_pin", 1.4)
	var l: Node = Nav.top_layer()
	_ck(l != null and str(l.get("_state")) == "code", "Plex: Code wird gezeigt")
	await _close_layers()
	await _to_movies()
	main.open_plex_login(true)
	await shot("11_plex_server", 1.4)
	await _close_layers()


func _jellyfin() -> void:
	await _to_movies()
	main.open_jellyfin_login("jellyfin")
	await shot("20_jellyfin_start", 1.0)
	var l: Node = Nav.top_layer()
	l.call("_discover")
	await shot("21_jellyfin_gefunden", 1.6)
	_ck(str(l.get("_state")) == "found" and (l.get("_found") as Array).size() == 2, "Jellyfin: Heimnetz-Suche findet zwei Server")
	l.call("_check", "http://192.168.178.40:8096")
	await shot("22_jellyfin_http_hinweis", 1.0)
	_ck(str(l.get("_state")) == "http", "Jellyfin: Hinweis vor unverschlüsselter Verbindung")
	l.call("_login")
	await shot("23_jellyfin_quick_connect", 1.2)
	_ck(str(l.get("_state")) == "code", "Jellyfin: Quick-Connect-Code")
	await _close_layers()


func _stremio() -> void:
	await _to_movies()
	main.open_stremio_login()
	await shot("30_stremio_hinweis", 1.0)
	await press("a")
	await shot("31_stremio_code", 1.4)
	await _close_layers()


func _home() -> void:
	await _to_movies()
	main.goto("movies", "start")
	await wait(0.6)
	var rows: Array = await Movies.call("home_rows")
	var keys: Array = rows.map(func(r): return str(r.get("key", "")))
	_ck(keys.has("quelle:plex/neu/1") and keys.has("quelle:jellyfin/bibliotheken") and keys.has("demo.cinemeta/movie/top"),
			"Startseite: Reihen von Plex, Jellyfin und Addons")
	var cw: Array = Movies.continue_watching()
	_ck(cw.any(func(c): return str(c.id) == "plex:200" or str(c.id) == "plex:201") and cw.any(func(c): return str(c.id).begins_with("jf:")),
			"Weiterschauen gemischt aus Plex und Jellyfin")
	main.sections["movies"]._rebuild_keep()
	await wait(0.3)
	main.sections["movies"].focus_default()
	await shot("40_start_plex", 2.0)
	await press("down")
	await shot("41_reihe_plex_neu", 1.2)
	await press("right", 2)
	await shot("42_plex_karte", 1.0)
	await press("down", 3)
	await shot("43_plex_bibliotheken", 1.2)
	await press("down", 1)
	await shot("44_plex_sammlungen", 1.2)
	var jf_folder := {}
	for r in rows:
		if str(r.get("key", "")) == "quelle:jellyfin/bibliotheken":
			jf_folder = r.folders[0]
	main.open_movie_folder(jf_folder, false)
	await shot("45_jellyfin_bibliothek", 2.0)
	await _close_layers()


func _detail_and_player() -> void:
	await _to_movies()
	var m: Dictionary = await Movies.call("meta", "movie", "plex:105")
	_ck(str(m.get("name", "")) == "Signal 7" and str(m.get("content_rating", "")) == "FSK 16", "Plex-Details mit Freigabe")
	main.open_movie(m)
	await shot("50_plex_detail", 1.6)
	await _close_layers()
	main.open_movie_streams(m, "plex:105", "start")
	await shot("51_plex_dateien", 1.8)
	var list: Array = await Movies.call("streams", "movie", "plex:105")
	_ck(list.size() == 4 and str(list[0].name) == "Direct Play" and int(list[0].quality) == 2160, "Dateien vom Server: 4K zuerst, Direct Play und Direct Stream")
	await press("a")
	await shot("52_player", 2.4)
	await press("y")
	await shot("53_player_wiedergabe", 1.0)
	await press("b")
	await wait(0.4)
	Video.stop()
	await wait(0.6)
	await _close_layers()


func _kids() -> void:
	Config.update_profile(Config.profile_id, { "kid": true, "rules": { "age": 6, "unknown": false } })
	await wait(0.4)
	var rows: Array = await Movies.call("home_rows")
	var all_ok := true
	var n := 0
	for r in rows:
		for it in r.get("items", []):
			n += 1
			if not Movies.kid_ok(it) or (int(it.get("age", -1)) > 6):
				all_ok = false
	_ck(n > 0 and all_ok, "Kinderprofil: nur Titel bis 6 oder aus Familien-Bibliotheken (%d)" % n)
	main.goto("movies", "start")
	await wait(0.3)
	main.sections["movies"]._rebuild_keep()
	await wait(0.3)
	main.sections["movies"].focus_default()
	await shot("60_kinderprofil", 2.0)
	await press("down")
	await shot("61_kinderprofil_reihe", 1.2)
	Config.update_profile(Config.profile_id, { "kid": false })

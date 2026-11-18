extends "res://tests/probe_base.gd"
## Probe für den Bereich Filme (Demo-Daten): Startseite, breite Karte, Alle anzeigen, Detail Film
## und Serie, Quellenwahl, Weiterschauen-Frage, Player, Suche, Entdecken, Bibliothek, Addons,
## Plugins, Einstellungen und Reiter aus. Aufruf siehe probe_base.gd.
## Mit --uzai-part=start,detail,quellen,suche,verwalten,einstellungen nur Teile (Standard: alles).

var parts := PackedStringArray()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-part="):
			parts = a.substr(12).split(",")
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Config.set_value("controller.glyphs", "xbox")
	Nav.device_changed.emit("pad")
	_inject_art()
	if _want("start"):
		await _part_start()
	if _want("detail"):
		await _detail()
	if _want("quellen"):
		await _streams()
	if _want("suche"):
		await _search()
	if _want("verwalten"):
		await _manage()
	if _want("einstellungen"):
		await _settings()


## Nur für die Probe: UZAI_FILME_ART=<Ordner mit bd0…7.png und po0…7.png> gibt den
## Demo-Titeln Bilder (die Demo selbst hat keine), um Masken und Verläufe mit Bildern zu sehen.
func _inject_art() -> void:
	var art := OS.get_environment("UZAI_FILME_ART")
	if art == "" or not ("_demo" in Movies):
		return
	var d: Dictionary = Movies.get("_demo")
	var seen := {}
	var put := func(it: Dictionary) -> void:
		var id := str(it.get("id", ""))
		if not seen.has(id):
			seen[id] = seen.size() % 8
		var n: int = seen[id]
		it["poster"] = art.path_join("po%d.png" % n)
		it["background"] = art.path_join("bd%d.png" % n)
	for r in d.rows:
		for it in r.items:
			put.call(it)
	for it in d.hero:
		put.call(it)
	for k in d.metas.keys():
		put.call(d.metas[k])
	for k in Movies.data.items.keys():
		put.call(Movies.data.items[k])
	for it in Movies.data.library:
		put.call(it)


func _want(p: String) -> bool:
	return parts.is_empty() or parts.has(p)


func _close_layers() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.25)


func _part_start() -> void:
	main.goto("movies", "start")
	await shot("01_start", 1.8)
	await press("down")
	await shot("02_karte_breit", 1.2)
	await press("right", 2)
	await shot("03_karte_rechts", 1.2)
	await press("down")
	await shot("04_reihe_serien", 1.2)
	await press("up", 2)
	await shot("05_weiterschauen", 0.9)
	await press("y")
	await shot("06_weiterschauen_optionen", 0.7)
	await press("b")
	await wait(0.3)
	# Am Ende einer Reihe: „Alle anzeigen“.
	await press("down")
	await press("right", 20, 0.08)
	await shot("07_alle_ansehen_karte", 0.9)
	await press("a")
	await shot("08_alle_ansehen", 1.4)
	await press("down", 3)
	await shot("09_alle_ansehen_runter", 0.9)
	await press("b")
	await wait(0.4)
	main.goto("movies", "filme")
	await shot("10_entdecken_filme", 1.4)
	main.goto("movies", "serien")
	await shot("11_entdecken_serien", 1.2)
	main.goto("movies", "bibliothek")
	await shot("12_bibliothek", 1.0)


func _detail() -> void:
	main.goto("movies", "start")
	await wait(0.6)
	var rows: Array = await Movies.call("home_rows")
	var film: Dictionary = (rows[0].items as Array)[0]
	main.open_movie(film)
	await shot("20_detail_film", 1.4)
	await press("down")
	await shot("21_detail_film_unten", 1.0)
	await press("right")
	await shot("22_detail_aehnlich", 0.9)
	await press("down")
	await shot("22b_detail_aehnlich_karten", 0.9)
	await _close_layers()
	var serie := {}
	for it in Movies.continue_watching():
		if str(it.get("type", "")) == "series":
			serie = it
	main.open_movie(serie)
	await shot("23_detail_serie", 1.4)
	await press("down")
	await shot("24_detail_staffeln", 0.9)
	await press("down")
	await shot("25_detail_folgen", 0.9)
	await press("up")
	await press("right")
	await shot("26_detail_staffel2", 0.9)
	await press("down", 2)
	await shot("27_detail_besetzung", 0.9)
	await _close_layers()


func _streams() -> void:
	var serie: Dictionary = await Movies.call("meta", "series", "tt9200002")
	main.open_movie_streams(serie, "tt9200002:1:4", "ask")
	await shot("30_quellen_laden", 0.5)
	await shot("31_quellen", 1.8)
	await press("down", 2)
	await shot("32_quellen_runter", 0.6)
	await press("y")
	await shot("33_quellen_qualitaet", 0.6)
	await press("b")
	await wait(0.3)
	await press("a")
	await shot("34_weiterschauen_frage", 0.7)
	await press("a")
	await shot("35_player", 2.4)
	await press("b")
	await shot("35b_player_angehalten", 0.6)
	await press("b")
	await shot("36_zurueck_quellen", 1.2)
	await _close_layers()
	var rows2: Array = await Movies.call("home_rows")
	var film: Dictionary = (rows2[0].items as Array)[0]
	main.open_movie_streams(film, str(film.id), "ask")
	await shot("37_quellen_film", 2.2)
	await press("up")
	await press("right", 2)
	await shot("38_quellen_filter", 0.8)
	await _close_layers()


func _search() -> void:
	main.goto("movies", "suche")
	await shot("40_suche_leer", 1.0)
	main.sections["movies"]._run_search("die")
	await shot("41_suche", 1.4)
	await press("a")
	await shot("42_suche_tastatur", 0.8)
	await press("b")
	await wait(0.3)
	main.sections["movies"]._run_search("xyzzy")
	await shot("43_suche_nichts", 1.0)


func _manage() -> void:
	main.goto("movies", "addons")
	await shot("50_addons", 1.0)
	await press("down", 2)
	await shot("51_addons_zeile", 0.6)
	await press("right", 2)
	await shot("52_addons_pfeil", 0.5)
	await press("left", 2)
	await press("a")
	await shot("53_addon_mehr", 0.7)
	await press("b")
	await wait(0.3)
	main.goto("movies", "addons")
	await wait(0.5)
	await press("a")
	await shot("54_addon_installieren", 0.8)
	await press("b")
	await wait(0.3)
	main.goto("movies", "plugins")
	await shot("55_plugins", 1.0)
	await press("down", 3)
	await shot("56_plugins_quelle", 0.6)


func _settings() -> void:
	main.goto("settings", "filme")
	await shot("60_einstellungen_filme", 1.0)
	await press("down", 4)
	await shot("61_einstellungen_filme_unten", 0.6)
	Config.set_value("movies.enabled", false)
	await shot("62_reiter_aus", 1.4)
	Config.set_value("movies.enabled", true)
	await shot("63_reiter_wieder_an", 1.4)

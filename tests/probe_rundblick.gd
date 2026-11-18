extends "res://tests/probe_base.gd"
## Rundblick für die Durchsicht: jeder Bereich und die wichtigsten Ebenen als Bild, in Teilen
## (--uzai-teil=spiele|guide|bereiche|einst|ebenen, ohne: alle). Nur ansehen, nichts prüfen.

var teil := ""


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-teil="):
			teil = a.substr(12)
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Nav.device_changed.emit("pad")
	await wait(2.0)
	if teil in ["", "spiele"]:
		await _spiele()
	if teil in ["", "guide"]:
		await _guide()
	if teil in ["", "bereiche"]:
		await _bereiche()
	if teil in ["", "einst"]:
		await _einst()
	if teil in ["", "ebenen"]:
		await _ebenen()


func _zu() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		n += 1
		await wait(0.4)


func _spiele() -> void:
	main.goto("games", "zuletzt")
	await shot("s01_start", 1.5)
	await press("right", 2)
	await shot("s02_start_drittes", 1.2)
	await press("up")
	await shot("s03_quellen", 0.8)
	await press("right", 3)
	await shot("s04_quelle_gc", 1.2)
	await press("down")
	await shot("s05_gc_regal", 1.0)
	main.goto("games", "zuletzt")
	await wait(1.0)
	await press("a")
	await shot("s06_spielseite", 2.0)
	await press("down")
	await shot("s07_spielseite_pillen", 0.8)
	await press("down")
	await shot("s08_spielseite_weiter1", 1.0)
	await press("down")
	await shot("s09_spielseite_weiter2", 1.0)
	await press("down", 2)
	await shot("s10_spielseite_weiter3", 1.0)
	await press("down", 3)
	await shot("s11_spielseite_weiter4", 1.0)
	await press("y")
	await shot("s12_optionen", 1.2)
	await _zu()
	main.goto("games", "zuletzt")
	await wait(1.0)
	await press("menu")
	await shot("s13_fuer_dich", 1.5)
	await _zu()
	await press("view")
	await shot("s14_freunde_leiste", 1.5)
	await _zu()
	main.open_library("alle", "Alle")
	await shot("s15_raster_alle", 2.0)
	await press("y")
	await shot("s16_raster_optionen", 1.0)
	await _zu()


func _guide() -> void:
	main.goto("games", "zuletzt")
	await wait(1.0)
	main.toggle_guide()
	await shot("g01_guide_start", 1.5)
	for i in 4:
		await press("rb")
		await shot("g%02d_guide_reiter" % (i + 2), 1.2)
	await _zu()
	main.open_power()
	await shot("g06_ausschalten", 1.2)
	await _zu()
	main.open_search("")
	await shot("g07_suche_leer", 2.0)
	await _zu()
	main.open_notifications()
	await shot("g08_mitteilungen", 1.2)
	await _zu()
	main.ask_quit_uzai()
	await shot("g09_dialog_beenden", 1.0)
	await _zu()
	main.open_doktor()
	await shot("g10_doktor", 1.5)
	await _zu()
	main.open_add_game()
	await shot("g11_spiel_hinzufuegen", 1.2)
	await _zu()
	main.open_file_browser("Ordner mit Spielen", true, func(_p: String) -> void: pass, [], "/usr/share")
	await shot("g12_ordnerwahl", 1.2)
	await press("down", 2)
	await shot("g13_ordnerwahl_unten", 0.8)
	await _zu()


func _bereiche() -> void:
	for ziel in [["shop", "entdecken"], ["shop", "specials"], ["shop", "wunschliste"], ["achievements", "profil"], ["achievements", "uebersicht"],
			["achievements", "freunde"], ["achievements", "statistik"], ["achievements", "backlog"], ["music", "alben"], ["music", "jetzt"],
			["videos", "fuerdich"], ["videos", "abos"], ["videos", "shorts"], ["movies", "start"], ["movies", "bibliothek"], ["streams", "start"],
			["streams", "kategorien"], ["browser", ""]]:
		main.goto(str(ziel[0]), str(ziel[1]))
		await shot("b_%s_%s" % [ziel[0], ziel[1]], 2.2)
		await press("down", 3)
		await shot("b_%s_%s_unten" % [ziel[0], ziel[1]], 1.2)
	main.goto("shop", "entdecken")
	await wait(1.5)
	await press("a")
	await shot("b_shop_spiel", 2.5)
	await press("down", 3)
	await shot("b_shop_spiel_unten", 1.2)
	await _zu()
	main.goto("movies", "start")
	await wait(1.5)
	await press("down")
	await press("a")
	await shot("b_film_detail", 2.5)
	await _zu()


func _einst() -> void:
	for c in ["aussehen", "klang", "spiele", "emulation", "konten", "controller", "imspiel", "aufnahmen", "medien", "mitteilungen", "system"]:
		main.goto("settings", c)
		await wait(1.0)
		await press("right")
		await shot("e_%s" % c, 1.0)
		await press("down", 6)
		await shot("e_%s_unten" % c, 0.8)
	main.goto("settings", "aussehen")
	await wait(1.0)
	await press("right")
	await press("a")
	await shot("e_auswahl_farbschema", 1.2)
	await _zu()


func _ebenen() -> void:
	main.goto("games", "zuletzt")
	await wait(1.0)
	var g: Dictionary = Library.recent(1)[0] if not Library.recent(1).is_empty() else {}
	if not g.is_empty():
		main.open_game_achievements(g)
		await shot("l01_erfolge_spiel", 2.0)
		await _zu()
		main.open_game_options(g)
		await shot("l02_spieloptionen", 1.2)
		await press("down", 5)
		await shot("l03_spieloptionen_unten", 0.8)
		await _zu()
	load("res://src/ui/layers/whats_new.gd").open_for(main)
	await shot("l04_neu", 1.5)
	await _zu()
	main.open_profiles("manage")
	await shot("l05_profile", 1.5)
	await _zu()
	main.open_captures()
	await shot("l06_aufnahmen", 2.0)
	await _zu()
	main.open_keyboard("Name des Spiels", "Okami", func(_t: String) -> void: pass)
	await shot("l07_tastatur", 1.5)
	await _zu()
	main.open_bild_ton()
	await shot("l08_bild_ton", 1.5)
	await _zu()
	main.open_room(true)
	await shot("l09_zimmer", 6.0)
	await _zu()

extends "res://tests/probe_base.gd"
## Weitere Bibliotheken (Punkt 6): Reiter der neuen Quellen, das Raster nach Plattform, der Filter
## mit den neuen Launchern, die Spielseite eines Spiels aus zwei Launchern mit „Über …“ und der
## Wahl, die Frage beim ersten Start, die Einrichtungs-Suche mit fehlendem Launcher, die
## Doktor-Karte und die Einstellungen „Weitere Launcher“. Demo-Daten.
## Aufruf: A2_PROJ=<worktree> A2_TIMEOUT=600 bash a2_run.sh res://tests/probe_bibliotheken.gd bibliotheken

const Wizard := preload("res://src/ui/layers/setup_wizard.gd")


func focus_key(k: String) -> bool:
	for c in Nav.focusables(Nav.scope_root()):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return true
	print("nicht gefunden: ", k)
	return false


func close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.35)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	print("BIB sichtbar: ", Library.visible_games().size(), " · doppelt: ",
			Library.games.filter(func(g: Dictionary) -> bool: return str(g.get("dupe_of", "")) != "").size())
	# Reiter der neuen Quellen
	main.goto("games", "gog")
	await wait(1.4)
	await shot("01_reiter_gog", 0.4)
	main.goto("games", "battlenet")
	await wait(1.2)
	await shot("02_reiter_battlenet", 0.4)
	main.goto("games", "xboxpc")
	await wait(1.2)
	await shot("03_reiter_xbox", 0.4)
	# Raster nach Plattform und der Filter
	Config.set_value("library.sort", "title")
	main.open_library("alle", "Alle Spiele")
	await wait(1.0)
	var l: Node = Nav.top_layer()
	l.set("_group", "platform")
	l.call("_refill")
	await shot("04_raster_plattform", 1.0)
	await press("down", 5, 0.2)
	await shot("05_raster_neue_quellen", 0.8)
	await press("y")
	await wait(0.6)
	await shot("06_ordnen_filter", 0.5)
	await press("b")
	l.set("_filter", { "platform": "riot" })
	l.set("_group", "")
	l.call("_refill")
	await shot("07_filter_riot", 1.0)
	l.set("_filter", { "platform": "gog" })
	l.call("_refill")
	await shot("08_filter_gog", 1.0)
	await close_all()
	# Spielseite: Hollow Knight gibt es bei Steam und GOG
	var hk := Library.get_game("steam:367520")
	print("BIB Hollow Knight: ", Library.alternatives(hk).size(), " Launcher, Spielzeit ", Library.playtime(hk))
	main.open_game(hk)
	await wait(1.6)
	focus_key("gp:via")
	await shot("09_spielseite_ueber_steam", 0.5)
	await press("a")
	await wait(0.8)
	await shot("10_wahl_launcher", 0.3)
	await press("down")
	await press("a")
	await wait(0.6)
	await shot("11_spielseite_ueber_gog", 0.4)
	await close_all()
	# Erster Start eines doppelten Spiels: Uzai fragt, über welchen Launcher.
	var cp := Library.get_game("steam:1091500")
	cp.erase("launch_via")
	main.launch(cp)
	await wait(0.8)
	await shot("12_start_frage", 0.3)
	await close_all()
	# Spielseiten der neuen Quellen (Ersatzhülle mit Namen, Symbol in der Pille)
	main.open_game(Library.get_game("riot:league_of_legends"))
	await wait(1.6)
	await shot("13_spielseite_riot", 0.4)
	await close_all()
	main.open_game(Library.get_game("xboxpc:Microsoft.624F8B84B80_8wekyb3d8bbwe"))
	await wait(1.6)
	await shot("14_spielseite_xbox", 0.4)
	await close_all()
	# Einrichtung → Suche: Battle.net fehlt (es gibt Spiele, die es brauchen)
	Library.launchers = { "steam": true, "epic": true, "ea": true, "gog": true, "ubisoft": true, "battlenet": false, "xboxpc": true, "riot": true }
	Library.launcher_need = { "battlenet": true }
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.restart", true)
	Config.set_value("einrichtung.tour", true)
	Config.set_value("einrichtung.step", "spiele")
	Wizard.open_for(main, false)
	await wait(3.0)
	await shot("15_einrichtung_suche", 0.4)
	await wait(5.0)
	await shot("16_einrichtung_suche_fertig", 0.3)
	await close_all()
	Config.set_value("einrichtung.done", true)
	# Uzai-Doktor
	main.open_doktor()
	await wait(1.6)
	focus_key("dk:launcher")
	await shot("17_doktor", 0.4)
	await press("a")
	await wait(1.0)
	await shot("18_doktor_offizielle_seite", 0.4)
	await close_all()
	# Einstellungen → Spiele → Weitere Launcher
	main.goto("settings", "spiele")
	await wait(1.4)
	var sv: Node = main.sections.get("settings")
	if sv:
		sv.call("open_more", "Weitere Launcher")
	await wait(1.2)
	await shot("19_einstellungen_weitere_launcher", 0.4)
	await press("down", 6, 0.15)
	await shot("20_einstellungen_runter", 0.4)
	await close_all()
	# Startseite mit den neuen Spielen unter „Zuletzt“
	main.goto("games", "zuletzt")
	await wait(1.4)
	await shot("21_zuletzt", 0.4)

extends "res://tests/probe_base.gd"
## Probe für „Nach dem Spielen“ (Punkt 24) und den Verlauf je Spiel (Punkte 38, 100): eine Runde
## endet (100 Std. überschritten, zwei Erfolge, ein Bildschirmfoto), dann die Karte „Gerade
## gespielt“ auf der Startseite, die Zusammenfassung und „Deine Spielzeit“ auf der Spielseite.
## Erfolge und Aufnahme legt die Probe selbst an (die Demo hat keine), nur im eigenen Datenordner.


func run() -> void:
	# Das Demo-Spiel mit den meisten Runden.
	var per := {}
	for se in Library.load_sessions():
		per[str(se.id)] = int(per.get(str(se.id), 0)) + 1
	var gid := ""
	for id in per.keys():
		if gid == "" or int(per[id]) > int(per[gid]):
			gid = str(id)
	var g := Library.get_game(gid)
	print("Spiel: ", Library.display_title(g), " (", per.get(gid, 0), " Runden)")
	var secs := 5400
	var now := int(Time.get_unix_time_from_system())
	# Ein paar frühere Abende dazu, damit der Verlauf nach etwas aussieht (nur im Speicher, Demo).
	for i in 11:
		Library.sessions.append({ "id": gid, "at": now - (i + 1) * 86400 * 2 - 3600 * (i % 3), "secs": 1800 + (i * 1370) % 6000 })
	g["playtime"] = 99 * 3600 + 1000
	g["steam_minutes"] = 0
	Library.record_session(gid, secs)
	var key := Unlocks.game_key(g)
	var platform := "ra" if str(g.get("source", "")) == "rom" else "steam"
	for e in [{ "name": "Unter der Erde", "desc": "Den ersten Wächter besiegt.", "at": now - 2400 },
			{ "name": "Ohne Pause", "desc": "Drei Kammern ohne Treffer geschafft.", "at": now - 300 }]:
		(Unlocks._data.history as Array).push_front({ "game": Library.display_title(g), "game_key": key, "api": str(e.name), "name": e.name,
			"desc": e.desc, "platform": platform, "unlocked_at": e.at, "points": 10, "rarity": 20.0 })
	var list: Array = []
	for i in 40:
		list.append({ "id": str(i), "title": "Erfolg %d" % (i + 1), "desc": "", "icon": "", "unlocked": i < 31, "rarity": 50.0 })
	Achievements._games[gid] = { "source": "steam", "total": 40, "unlocked": 31, "list": list }
	# Ein Bildschirmfoto aus der Runde (Aufnahmeordner im eigenen Datenordner).
	var dir := Config.path("aufnahmen_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("capture.folder", dir)
	var img := Image.create(320, 180, false, Image.FORMAT_RGB8)
	img.fill(Color("#2a3140"))
	var stamp := Time.get_datetime_string_from_unix_time(now - 900 + int(Time.get_time_zone_from_system().bias) * 60).replace("T", " ").replace(":", "-")
	img.save_png(dir.path_join("%s %s.png" % [Library.display_title(g), stamp]))
	main.goto("games")
	await wait(0.8)
	main._on_game_ended(g, secs)
	await shot("01_startseite_gerade_gespielt", 2.5)
	main.open_round_summary()
	await shot("02_zusammenfassung", 1.6)
	await press("right")
	await shot("03_zusammenfassung_fokus", 0.6)
	await press("b")
	await wait(0.6)
	# Spielseite: runter bis zum Verlauf.
	main.open_game(Library.get_game(gid))
	await wait(1.8)
	for i in 12:
		var f := Nav.focused()
		if f and f.get_meta("uz_key", "") == "gp:sessions":
			break
		await press("down", 1, 0.3)
	await shot("04_spielseite_verlauf", 1.2)
	await press("left", 3, 0.25)
	await shot("05_verlauf_gewaehlt", 0.8)
	await press("down")
	await shot("06_spielseite_kacheln", 1.0)
	await press("b")
	await wait(0.6)
	# Ausgeschaltet: keine Karte, die kurze Mitteilung führt wieder zum Spiel.
	Config.set_value("system.round_summary", false)
	main.goto("games")
	main.sections["games"].build()
	await shot("07_aus_ohne_karte", 1.5)
	Config.set_value("system.round_summary", true)

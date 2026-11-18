extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Backlog (Roadmap 2) – „Dein Backlog“ auf der Spielseite, Status und Sterne
## wählen, Tagebuch, Profil → Backlog mit „Was spiele ich heute?“, Würfeln, Jahresziel und Listen,
## Raster nach Status, „Ins Tagebuch“ nach einer Runde. Aufruf siehe probe_base.gd.


func run() -> void:
	var er := Library.get_game("steam:1245620")

	main.open_game(er)
	await wait(1.4)
	await _focus("gp:bl:status")
	await shot("01_spielseite_dein_backlog", 1.0)
	await press("a")
	await shot("02_status_waehlen", 0.8)
	await press("b")
	await wait(0.4)
	await _focus("gp:bl:stars")
	await press("a")
	await shot("03_sterne_waehlen", 0.8)
	await press("b")
	await wait(0.4)
	await _focus("gp:bl:diary")
	await press("a")
	await shot("04_tagebuch", 0.9)
	await press("b")
	await wait(0.6)
	await press("b")
	await wait(0.9)

	# Ein Spiel ohne Status, kürzlich gespielt: der Vorschlag steht da, gesetzt wird er nicht.
	var sotc: Dictionary = Library.visible_games().filter(func(g): return str(g.title) == "Shadow of the Colossus")[0]
	main.open_game(sotc)
	await wait(1.4)
	await _focus("gp:bl:suggest")
	await shot("05_vorschlag", 1.0)
	print("Probe: Status vor dem Übernehmen „%s“" % str(sotc.get("status", "")))
	await press("a")
	await wait(0.5)
	print("Probe: Status nach dem Übernehmen „%s“" % str(Library.get_game(str(sotc.id)).get("status", "")))
	await _focus("gp:bl:status")
	await shot("06_vorschlag_uebernommen", 0.8)
	await press("b")
	await wait(0.9)

	await main.goto("achievements", "backlog")
	await wait(1.6)
	await shot("07_profil_backlog", 1.0)
	var page: Node = main.sections.get("achievements")
	var roll := _find(page, func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == "bl:today:roll")
	if roll:
		Nav.focus(roll)
		await wait(0.4)
		await press("a")
		await shot("08_gewuerfelt", 1.0)
	var goal := _find(page, func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == "bl:goal")
	if goal:
		Nav.focus(goal)
		await shot("09_jahresziel", 0.9)
		await press("a")
		await shot("10_ziel_waehlen", 0.8)
		await press("b")
		await wait(0.4)
	var list := _find(page, func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == "bl:list:l_demo1")
	if list:
		Nav.focus(list)
		await shot("11_listen_tagebuch", 1.0)
		await press("a")
		await shot("12_liste_offen", 0.9)
		await _focus("list:g:gc:a82fa16c93bca1")
		await press("x")
		await shot("13_liste_nach_oben", 0.8)
		await press("b")
		await wait(0.6)

	Config.set_value("library.sort", "title")
	main.open_library("alle", "Alle Spiele")
	await wait(1.0)
	var l: Node = Nav.top_layer()
	l.set("_group", "status")
	l.call("_refill")
	await shot("14_raster_nach_status", 1.1)
	await press("y")
	await wait(0.5)
	await _focus("lib:status")
	await press("right")
	await shot("15_filter_backlog", 0.9)
	await press("left")
	await press("b")
	await wait(0.4)
	await press("b")
	await wait(0.8)

	# Nach einer Runde: „Ins Tagebuch“ in der Zusammenfassung.
	var now := int(Time.get_unix_time_from_system())
	main.last_round = { "game_id": str(er.id), "start": now - 3900, "end": now - 60, "secs": 3840, "before": 430000, "after": 433840 }
	main.open_round_summary()
	await wait(1.0)
	await _focus_text("Ins Tagebuch")
	await shot("16_zusammenfassung_tagebuch", 0.8)
	await press("b")
	await wait(0.6)

	await main.goto("games")
	await wait(1.4)
	await shot("17_startseite", 1.0)


func _focus(key: String) -> void:
	var c := _find(Nav.top_layer() if Nav.top_layer() else main, func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == key)
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", key)
	await wait(0.35)


func _focus_text(t: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return n is Button and (n as Button).text == t)
	if c:
		Nav.focus(c)
	else:
		print("Probe: Knopf nicht gefunden: ", t)
	await wait(0.35)


func _find(n: Node, f: Callable) -> Control:
	if n == null:
		return null
	if n is Control and f.call(n):
		return n
	for ch in n.get_children():
		var r := _find(ch, f)
		if r:
			return r
	return null

extends "res://tests/probe_base.gd"
## Probe „Lösungshilfe“ (Demo, Punkt 111): Kachel im Guide (als eigene Kachel gewählt), Themen,
## Treffer zu „Bosse“, zurück, eigenes Suchwort, „Zuletzt gesucht“, Abspielen als Bild in Bild,
## Reiter „Bild in Bild“ mit „Andere Videos“.


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


func _focus_key(key: String) -> bool:
	var top := Nav.top_layer()
	if not top:
		return false
	for c in Nav.focusables(top):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return true
	return false


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("system.guide_tiles", ["help", "", "", ""])
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	main.toggle_guide()
	await wait(1.2)
	print("Kachel gefunden: %s" % str(_focus_key("q:Lösungshilfe")))
	await shot("01_guide_kachel", 0.6)
	await press("a")
	await shot("02_themen", 1.0)
	await press("down")
	await press("a")
	await shot("03_sucht", 0.15)
	await shot("04_treffer_bosse", 1.2)
	print("Treffer: %d" % Nav.focusables(Nav.top_layer()).size())
	await press("b")
	await shot("05_zurueck_zu_bosse", 0.8)
	print("Gewählt nach B: %s" % str(Nav.focused().get_meta("uz_key", "")))
	_focus_key("wt:own")
	await press("a")
	await wait(0.8)
	var kb := Nav.top_layer()
	print("Tastatur offen: %s" % str(kb != null and kb.has_signal("done")))
	await shot("06_tastatur", 0.3)
	kb.text = "Boss Malenia"
	kb.call("_finish")
	await shot("07_treffer_malenia", 1.4)
	await press("b")
	await shot("08_zuletzt_gesucht", 0.8)
	print("Gemerkt: %s" % str(load("res://src/core/walkthrough.gd").remembered(str(g.id))))
	_focus_key("wt:t:Boss Malenia")
	await shot("09_suchwort_gewaehlt", 0.5)
	await press("a")
	await wait(1.4)
	await press("a")
	await shot("10_bild_in_bild", 1.6)
	print("Bild in Bild: %s · Video: %s" % [str(main.pip.active()), str(Video.video.get("title", ""))])
	main.toggle_guide("pip")
	await shot("11_guide_bild_in_bild", 1.4)
	print("Andere Videos: %s" % str(_focus_key("p:help")))
	await shot("12_andere_videos_gewaehlt", 0.5)
	await press("a")
	await shot("13_andere_videos_themen", 1.0)
	await _close_all()
	main.pip.close()
	await wait(0.6)
	Launcher.in_game = false
	Launcher.current = {}

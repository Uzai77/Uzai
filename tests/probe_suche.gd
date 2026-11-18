extends "res://tests/probe_base.gd"
## Suche über alles (Punkt 105): R3 öffnet, Treffer laufen beim Tippen mit, nach der Pause fragt
## das Netz, „Fertig“ zeigt alle Gruppen, Y schaltet das Netz ab, eine Einstellung wird
## angesprungen, Tippfehler, B schließt.


func run() -> void:
	var t0 := Time.get_ticks_msec()
	var idx: Array = main.sections["settings"].search_index()
	print("Einstellungen im Index: %d in %d ms" % [idx.size(), Time.get_ticks_msec() - t0])
	await shot("01_start", 0.3)
	await press("search")
	await shot("02_offen", 0.7)
	await _type("zelda")
	await shot("03_tippen", 0.25)
	await wait(1.4)
	await shot("04_netz_live", 0.2)
	await press("menu")
	await shot("05_treffer", 0.9)
	_where()
	await press("down", 4)
	await shot("06_blaettern", 0.4)
	await press("down", 6)
	await shot("07_netz", 0.5)
	await press("y")
	await shot("08_netz_aus", 0.6)
	await press("y")
	await press("x")
	await wait(0.6)
	await _erase(5)
	await _type("sprache")
	await shot("09_einstellung_tippen", 0.4)
	await press("menu")
	await shot("10_einstellung_treffer", 0.8)
	_where()
	await press("a")
	await shot("11_einstellung_offen", 1.4)
	_where()
	main.open_search()
	await wait(0.8)
	await _type("eldn rign")
	await shot("12_tippfehler", 0.4)
	await press("b")
	await wait(0.6)
	print("Ebenen offen nach B: %d" % Nav.layers.size())
	await shot("13_zu", 0.3)
	for c in Nav.focusables(main.shell):
		if str(c.get_meta("uz_key", "")) == "me:search":
			Nav.focus(c, true)
	await shot("14_lupe", 0.4)
	await press("a")
	await wait(0.8)
	print("Lupe öffnet die Suche: %s" % (Nav.top_layer() != null))
	await press("b")
	await wait(0.6)
	main.open_game_options(Library.visible_games()[0])
	await wait(0.6)
	await press("search")
	await wait(0.6)
	print("Über den Spieloptionen öffnet R3 nichts: Ebenen %d" % Nav.layers.size())


func _type(s: String) -> void:
	var kb := Nav.top_layer()
	for ch in s:
		kb.call("_type", ch)
		await wait(0.09)


func _erase(n: int) -> void:
	var kb := Nav.top_layer()
	for i in n:
		kb.call("_backspace")
		await wait(0.05)


func _where() -> void:
	var f := Nav.focused()
	print("Auswahl: ", str(f.get_meta("uz_key", f.name)) if f else "keine")

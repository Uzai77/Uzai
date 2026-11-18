extends "res://tests/probe_base.gd"
## Guide-Taste: zweiter Druck macht den Guide immer zu – auch mit doppelter Meldung (Godot und
## Helfer), mit Ebenen darüber, im Spiel, nach „Streams ansehen“ und beim Akkord View + Start.
## Aufruf wie probe_base.gd beschreibt; gibt „GT ok/FAIL …“ aus.

var fails := 0


func _open() -> bool:
	return main._guide != null and is_instance_valid(main._guide)


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("GT %s %s (Guide %s, Ebenen %d)" % ["ok  " if cond else "FAIL", what, "offen" if _open() else "zu", Nav.layers.size()])


func _act(name: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = down
	Input.parse_input_event(e)


func run() -> void:
	# 1. Auf und zu, jeweils mit verspäteter Meldung des Helfers (früher öffnete die den Guide
	#    gleich wieder, weil der Guide die Taste selbst schloss).
	await press("guide", 1, 0.05)
	main._on_pad_event("guide")
	await wait(0.6)
	_ck(_open(), "auf, Helfer-Meldung 50 ms später ändert nichts")
	await shot("01_offen", 0.2)
	await press("guide", 1, 0.3)
	main._on_pad_event("guide")
	await wait(0.6)
	_ck(not _open(), "zu, Helfer-Meldung 300 ms später öffnet nicht wieder")
	# 2. Schnell zweimal: auf und gleich wieder zu (früher verschluckte die 450-ms-Sperre den zweiten).
	await press("guide", 1, 0.2)
	await press("guide", 1, 0.2)
	await wait(0.6)
	_ck(not _open(), "zweimal schnell: wieder zu")
	# 3. Ebene über dem Guide (Auswahl, Menü an einer Person): Guide-Taste schließt alles.
	await press("guide", 1, 0.8)
	main.open_choice("Test", [["a", "Eins", ""], ["b", "Zwei", ""]], "a", func(_v: Variant) -> void: pass)
	await wait(0.6)
	_ck(_open() and Nav.layers.size() >= 2, "Auswahl über dem Guide")
	await press("guide", 1, 0.1)
	main._on_pad_event("guide")
	await wait(0.7)
	_ck(not _open() and Nav.layers.is_empty(), "Guide-Taste: Auswahl und Guide zu")
	# Menü an einer Person im Discord-Reiter.
	main.toggle_guide("discord")
	await wait(1.0)
	await press("a", 1, 0.8)
	_ck(Nav.layers.size() >= 2, "Menü an einer Person offen")
	await shot("02_menu_ueber_guide", 0.1)
	await press("guide", 1, 0.1)
	main._on_pad_event("guide")
	await wait(0.7)
	_ck(not _open() and Nav.layers.is_empty(), "Guide-Taste: Menü und Guide zu")
	# 4. Im Spiel.
	Launcher.in_game = true
	Launcher.current = Library.get_game(Library.recent(1)[0].id)
	await press("guide", 1, 0.05)
	main._on_pad_event("guide")
	await wait(0.8)
	_ck(_open(), "im Spiel: auf")
	await press("guide", 1, 0.05)
	main._on_pad_event("guide")
	await wait(0.8)
	_ck(not _open(), "im Spiel: zu")
	Launcher.in_game = false
	# 5. Nach „Streams ansehen“ (Discord vorn): Uzai hat den Fokus wieder → Guide geht normal auf/zu.
	main._away_for_discord = true
	await press("guide", 1, 0.8)
	_ck(_open(), "nach Streams ansehen: auf")
	await press("guide", 1, 0.8)
	_ck(not _open(), "nach Streams ansehen: zu")
	# 6. Akkord: erst Start, dann View (Start allein öffnet schon, der Akkord gehört dazu).
	Nav.focus(main._tab_items[main.current], true)
	await wait(0.3)
	_act("uz_menu", true)
	await wait(0.5)
	_act("uz_view", true)
	main._on_pad_event("guide")
	await wait(0.2)
	_act("uz_view", false)
	_act("uz_menu", false)
	await wait(0.6)
	_ck(_open(), "Start, dann View + Start: Guide auf (nicht auf und gleich zu)")
	_act("uz_view", true)
	await wait(0.05)
	_act("uz_menu", true)
	main._on_pad_event("guide")
	await wait(0.2)
	_act("uz_menu", false)
	_act("uz_view", false)
	await wait(0.6)
	_ck(not _open(), "View, dann Start: Guide zu")
	await shot("03_zu", 0.2)
	print("GT Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))

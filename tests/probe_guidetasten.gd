extends "res://tests/probe_base.gd"
## Probe Guide-Taste: kurz → Guide, gehalten → Schnellmenü (über Godot und über den Helfer),
## Guide halten + X (nichts geht auf), Schnellmenü im Spiel, eigene Kacheln im Guide und ihre
## Seitenleiste, Guide passend zur Lage bei einem Emulator-Spiel. Gibt „GT ok/FAIL …“ aus.

const GuideTiles := preload("res://src/ui/layers/guide_tiles.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("GT %s %s (%s, Ebenen %d)" % ["ok  " if cond else "FAIL", what, _what(), Nav.layers.size()])


func _what() -> String:
	var g = main._guide
	if g == null or not is_instance_valid(g):
		return "zu"
	return "Schnellmenü" if str(g.start_tab) == "schnell" else "Guide"


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


## Guide-Taste über Godot: drücken, ms halten, loslassen.
func _hold(ms: int) -> void:
	Input.action_press("uz_guide")
	Nav._fire("guide")
	await wait(ms / 1000.0)
	Input.action_release("uz_guide")
	await wait(0.6)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("controller.guide_hold", "menu")
	# 1. Ohne Spiel: kurz und lang.
	await _hold(90)
	_ck(_what() == "Guide", "kurz gedrückt: Guide")
	await _close_all()
	await _hold(800)
	_ck(_what() == "Schnellmenü", "gehalten: Schnellmenü, kein Guide dazwischen")
	await shot("01_schnellmenue_start", 0.3)
	await _close_all()
	# 2. Über den Helfer (Xbox-Controller, auch im Spiel).
	main._on_pad_event("guide")
	await wait(0.2)
	_ck(_what() == "zu", "Helfer: gedrückt, noch nichts offen")
	main._on_pad_event("guide-up")
	await wait(0.6)
	_ck(_what() == "Guide", "Helfer: losgelassen → Guide")
	await _close_all()
	main._on_pad_event("guide")
	await wait(0.5)
	main._on_pad_event("guide-hold")
	await wait(0.6)
	main._on_pad_event("guide-up")
	await wait(0.3)
	_ck(_what() == "Schnellmenü", "Helfer: gehalten → Schnellmenü, Loslassen schließt nichts")
	await _close_all()
	# 3. Guide halten + X: nur der Clip, kein Menü.
	Input.action_press("uz_guide")
	Nav._fire("guide")
	await wait(0.15)
	main.clip_hotkey("chord")
	await wait(0.2)
	Input.action_release("uz_guide")
	await wait(0.8)
	_ck(_what() == "zu", "Guide halten + X: weder Guide noch Schnellmenü")
	# 4. Einstellung „Ruhemodus“: Guide öffnet wie früher beim Drücken.
	Config.set_value("controller.guide_hold", "rest")
	Input.action_press("uz_guide")
	Nav._fire("guide")
	await wait(0.3)
	_ck(_what() == "Guide", "Einstellung Ruhemodus: Guide gleich beim Drücken")
	Input.action_release("uz_guide")
	await _close_all()
	Config.set_value("controller.guide_hold", "menu")
	# 5. Im Spiel.
	Launcher.in_game = true
	Launcher.current = Library.get_game(Library.recent(1)[0].id)
	await _hold(800)
	_ck(_what() == "Schnellmenü", "im Spiel: Schnellmenü")
	await shot("02_schnellmenue_spiel", 0.4)
	await press("right", 2, 0.2)
	await shot("03_schnellmenue_fokus", 0.3)
	# Ganz rechts steht noch die schmale Kachel „Anpassen“; der Guide davor.
	await press("right", 5, 0.15)
	_ck(Nav.focused() != null and str(Nav.focused().get_meta("uz_key", "")) == "qm:anpassen", "ganz rechts: Anpassen")
	await press("left", 1, 0.15)
	_ck(Nav.focused() != null and str(Nav.focused().get_meta("uz_key", "")) == "qm:guide", "davor: Guide öffnen")
	await press("a", 1, 0.9)
	_ck(_what() == "Guide", "„Guide“ im Schnellmenü öffnet den ganzen Guide")
	await shot("04_guide_aus_schnellmenue", 0.3)
	await _close_all()
	await _hold(800)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "qm:shot", "wieder auf: vorn steht das Bildschirmfoto")
	while Nav.focused() and str(Nav.focused().get_meta("uz_key", "")) != "qm:quit" and str(Nav.focused().get_meta("uz_key", "")) != "qm:guide":
		await press("right", 1, 0.15)
	_ck(str(Nav.focused().get_meta("uz_key", "")) == "qm:quit", "Spiel beenden")
	await press("a", 1, 0.6)
	await shot("05_beenden_frage", 0.2)
	await _close_all()
	# 6. Eigene Kacheln: Bild in Bild vorn, Bildfilter auf Platz 4.
	Config.set_value("system.guide_tiles", ["pip", "", "", "filter"])
	main.toggle_guide()
	await wait(1.2)
	await shot("06_guide_eigene_kacheln", 0.2)
	await _close_all()
	var s := GuideTiles.open(main)
	await wait(0.8)
	await shot("07_kacheln_seite", 0.2)
	await press("a", 1, 0.8)
	await shot("08_kachel_waehlen", 0.2)
	await _close_all()
	Config.set_value("system.guide_tiles", [])
	_ck(not is_instance_valid(s) or not s.is_inside_tree(), "Seitenleiste zu")
	# 7. Passend zur Lage: Emulator-Spiel mit Speichern/Laden.
	var emu: Dictionary = {}
	Launcher._kind = "rom"
	for g in Library.games:
		Launcher.current = g
		if Launcher.has_hotkey("save") and Launcher.has_hotkey("load"):
			emu = g
			break
	if not emu.is_empty():
		Launcher.current = emu
		main.toggle_guide()
		await wait(1.2)
		await shot("09_guide_emulator_lage", 0.2)
		await _close_all()
		Config.set_value("system.guide_smart", false)
		main.toggle_guide()
		await wait(1.2)
		await shot("10_guide_emulator_ohne_lage", 0.2)
		await _close_all()
		Config.set_value("system.guide_smart", true)
	else:
		print("GT (kein Emulator-Spiel mit Speichern/Laden in der Vorführung)")
	Launcher.in_game = false
	Launcher._kind = ""
	Launcher.current = {}
	await wait(0.5)
	# 8. Einstellungen → Controller.
	main.goto("settings", "controller")
	await wait(1.2)
	await shot("11_einstellungen_controller", 0.2)
	print("GT Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))

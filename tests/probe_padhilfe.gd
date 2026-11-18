extends "res://tests/probe_base.gd"
## Probe „Controller-Problemlöser“ (Punkt 114): Einstieg in den Einstellungen und in Erste Hilfe,
## jede Seite des Problemlösers mit nachgestellten Eingaben (zwei Controller, einer davon als
## Doppelgänger), Drift mit Totzonen-Vorschlag, Trigger, Vibration, Tastensymbole, Ergebnis und
## „Wird nicht erkannt“.

const PadHelp := "res://src/ui/layers/pad_help.gd"
const C := preload("res://src/core/pad_check.gd")


func run() -> void:
	Config.set_value("controller.glyphs", "auto")
	Config.set_value("controller.deadzone", 0.5)
	await _settings()
	await _helper()
	await _missing()
	await _first_aid()


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.15)
	await wait(0.4)


func _settings() -> void:
	main.goto("settings", "controller")
	await wait(0.8)
	var sv = main.sections["settings"]
	sv._enter_content()
	await wait(0.3)
	for c in Nav.focusables(sv._list):
		if str(c.get_meta("uz_key", "")).ends_with("Problemlöser"):
			Nav.focus(c, true)
	await shot("p01_einstellungen_controller", 0.6)


func _helper() -> void:
	var l = load(PadHelp).new()
	l.sim = { "joys": [{ "device": 0, "name": "Xbox Wireless Controller", "vid": C.MICROSOFT, "pid": 0x0B12, "player": 0 },
		{ "device": 1, "name": "DualSense Wireless Controller", "vid": C.SONY, "pid": 0x0CE6, "player": 1 }] }
	main.open_layer(l)
	await wait(0.6)
	l._press(0, JOY_BUTTON_A, Time.get_ticks_msec())
	await shot("p02_was_uzai_sieht", 0.15)
	await press("a")
	await wait(0.6)
	# Ein paar Tasten, dazu der Doppelgänger am zweiten Gerät (wie Steam Input oder DS4Windows).
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_START]:
		l.sim_press(0, b)
		l._press(1, b, Time.get_ticks_msec() + 8)
		await wait(0.16)
	l.sim_press(0, JOY_BUTTON_RIGHT_SHOULDER)
	await shot("p03_tasten_halb", 0.05)
	for b in C.BUTTONS:
		l._press(0, b, Time.get_ticks_msec())
	await shot("p04_tasten_fertig", 0.9)
	await press("a")
	await wait(0.6)
	# Rechter Stick driftet deutlich.
	l.sim_axes = [0.01, -0.02, 0.43, 0.08, 0.0, 0.0]
	await shot("p05_sticks_ruhe", 1.4)
	await wait(2.2)
	for i in 70:
		var v := Vector2.RIGHT.rotated(i * TAU / 35.0) * 0.97
		l.sim_axes = [v.x, v.y, -v.x, v.y, 0.0, 0.0]
		await get_tree().process_frame
		if i == 30:
			await shot("p06_sticks_kreisen", 0.0)
	l.sim_axes = [0.01, -0.02, 0.43, 0.08, 0.0, 0.0]
	await shot("p07_sticks_ergebnis", 0.9)
	await press("right")
	await press("a")
	await wait(0.6)
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	await wait(0.4)
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 1.0, 0.68]
	await shot("p08_trigger", 0.3)
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	await wait(0.2)
	l._trigger_done()
	await shot("p09_trigger_ergebnis", 0.9)
	await press("right")
	await press("a")
	await shot("p10_vibration", 0.75)
	await wait(0.6)
	await press("a")
	await shot("p11_doppelt", 0.8)
	await press("a")
	await shot("p12_symbole", 0.8)
	await press("right")
	await shot("p13_symbole_ps", 0.4)
	await press("left")
	await press("a")
	await shot("p14_ergebnis", 0.9)
	await _close_all()


func _missing() -> void:
	var l = load(PadHelp).new()
	l.sim = { "joys": [] }
	var keep: Array = Pads.pads
	Pads.pads = []
	main.open_layer(l)
	await shot("p15_kein_controller", 0.8)
	await press("a")
	await shot("p16_wird_nicht_erkannt", 0.8)
	await _close_all()
	Pads.pads = keep


func _first_aid() -> void:
	main.goto("settings", "system")
	await wait(0.8)
	var sv = main.sections["settings"]
	sv._show_cat("system")
	await wait(0.3)
	sv.open_more("Erste Hilfe")
	await wait(0.8)
	await press("a")
	await shot("p17_erste_hilfe_controller", 0.8)
	await press("a")
	await shot("p18_aus_erster_hilfe", 1.0)
	await _close_all()

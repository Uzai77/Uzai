extends "res://tests/probe_base.gd"
## Mausklick auf wählbare Elemente (Nav.klick): Der Zeiger wählt schon beim Darüberfahren, ein
## Klick löst aus. Geprüft an einer Hülle der Startseite, einer Zeile der Einstellungen und einer
## Zeile einer Leiste. Ausgabe: je Prüfung eine Zeile „MAUS ok“ oder „MAUS FEHLER“.


func run() -> void:
	await wait(2.0)
	main.goto("games", "zuletzt")
	await wait(1.5)
	await _klick(Vector2(520, 790))
	await wait(1.5)
	var f := Nav.focused()
	_sag(Nav.top_layer() != null and f != null and str(f.get_meta("uz_key", "")) == "gp:play", "Startseite: Klick auf die zweite Hülle öffnet ihre Spielseite")
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.5)
	main.goto("settings", "controller")
	await wait(1.5)
	var war := bool(Config.get_value("controller.swap_ab", false))
	await _klick(Vector2(830, 300))
	await wait(0.5)
	var zeile := Nav.focused()
	_sag(zeile != null and str(zeile.get("title")) == "A und B tauschen" and bool(Config.get_value("controller.swap_ab", false)) != war,
			"Einstellungen: Klick wählt die Zeile und schaltet um")
	Config.set_value("controller.swap_ab", war)
	main.open_add_game()
	await wait(1.5)
	await _klick(Vector2(1480, 285))
	await wait(1.2)
	_sag(Nav.layers.size() >= 2, "Leiste: Klick auf „Programmdatei wählen“ öffnet die Dateiauswahl")


func _klick(p: Vector2) -> void:
	for gedrueckt in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = gedrueckt
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await wait(0.15)


func _sag(ok: bool, was: String) -> void:
	print("MAUS %s  %s" % ["ok    " if ok else "FEHLER", was])

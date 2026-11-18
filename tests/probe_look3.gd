extends "res://tests/probe_startseite.gd"
## Probe „Premium“: die wichtigsten Flächen in einem Lauf – Kopf der Startseite mit den Knöpfen
## und der Tastenzeile, „Für dich“ gewählt, ein Dialog, die Spielseite, der Guide, die
## Einstellungen und Mitteilungen.
## UZAI_LOOK3: "kurz" (nur Startseite, „Für dich“ und Dialog) oder leer (alles).


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_bilder()
	Discs.set_disc("SCES-50760", "ps2", "E:\\")
	await wait(1.0)
	main.goto("games", "zuletzt")
	await wait(0.6)
	var gs = main.sections["games"]
	gs.build()
	main.refresh_chips()
	await wait(0.8)
	gs.focus_default()
	await shot("01_start", 1.6)
	# „Für dich“ liegt hinter der Start-Taste (Seitenleiste von rechts).
	await press("menu")
	await shot("02_fuerdich", 1.0)
	await press("b")
	await wait(0.4)
	main.open_dialog("Emulator löschen?", "„PCSX2 (eigen)“ verschwindet aus Uzai. Systeme, die ihn nutzen, brauchen danach einen anderen Emulator.", [
		["Löschen", func() -> void: pass, "danger"],
		["Behalten", func() -> void: pass],
	])
	await shot("03_dialog", 1.2)
	await _zu()
	if OS.get_environment("UZAI_LOOK3") == "kurz":
		return
	await press("a")
	await shot("04_spielseite", 1.8)
	await _zu()
	main.toggle_guide()
	await shot("05_guide", 1.2)
	await _zu()
	main.goto("settings", "aussehen")
	await shot("06_einstellungen", 1.2)
	main.goto("games", "zuletzt")
	await wait(0.8)
	Toasts.show_toast("Controller verbunden", "Xbox Wireless Controller", "controller")
	await wait(0.3)
	Toasts.show_toast("Spiel nicht gefunden", "Die Verknüpfung zeigt auf ein Spiel, das nicht mehr in der Bibliothek ist.", "warning")
	await shot("07_mitteilungen", 0.9)


func _zu() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.6)

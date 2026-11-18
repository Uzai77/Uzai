extends "res://tests/probe_base.gd"
## Drei Bilder der Einstellungen (0.12): Aussehen mit Vorschau rechts, Klang, die Suche mit
## Treffern beim Tippen.
## Aufruf: siehe probe_base.gd (--demo --no-boot --uzai-script=res://tests/probe_einstellungen_neu.gd).


func focus_key(k: String) -> void:
	for c in Nav.focusables(main.sections["settings"]):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return
	print("Nicht gefunden: ", k)


func run() -> void:
	Config.set_value("theme.preset", "theme")
	main.goto("settings", "aussehen")
	await wait(0.9)
	focus_key("set:aussehen:Cover-Größe")
	await shot("01_aussehen", 0.9)
	main.goto("settings", "klang")
	await wait(0.9)
	focus_key("set:klang:Menüklänge")
	await shot("02_klang", 0.9)
	focus_key("cat:suche")
	await wait(0.4)
	await press("a")
	await wait(0.6)
	var kb: Control = Nav.top_layer()
	if kb and kb.has_method("_type"):
		for ch in "cov":
			kb.call("_type", ch)
			await wait(0.12)
	await shot("03_suche", 0.9)

extends "res://tests/probe_base.gd"
## Uzai auf Englisch (system.language = en vorher in settings.json): Startseite, Medien,
## Einstellungen. Ausgabe „SP …“.

func run() -> void:
	print("SP Sprache: ", TranslationServer.get_locale(), " · ", tr("Einstellungen"))
	await shot("01_start", 0.5)
	main.goto("settings", "system")
	await wait(1.2)
	await shot("02_system", 0.3)
	main.goto("settings", "games")
	await wait(1.0)
	await shot("03_spiele", 0.3)
	main.goto("media")
	await wait(1.0)
	await shot("04_medien", 0.3)
	main.goto("media", "movies")
	await wait(1.2)
	await shot("05_filme", 0.3)
	main.toggle_guide()
	await wait(1.2)
	await shot("06_guide", 0.3)

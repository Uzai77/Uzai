extends "res://tests/probe_base.gd"
## Probe für den Einmal-Code beim Start von Epic-Spielen, die Uzai installiert hat: Einstellungen →
## Konten → Epic Games mit „Mehr …“ und darin die eine Zeile zum Abschalten.


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("accounts.epic_refresh", "probe")
	Config.set_value("accounts.epic_name", "Spieler")
	Library.epic_account.state = "bereit"
	await wait(1.5)
	main.goto("settings", "konten")
	await wait(1.0)
	var sv = main.sections["settings"]
	sv.open_more("Epic Games")
	await wait(0.6)
	await press("down", 2)
	await shot("01_epic_seite_mehr", 0.8)
	sv.open_more("Mehr")
	await wait(0.6)
	await shot("02_epic_mehr_anmeldung_weitergeben", 0.8)
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame

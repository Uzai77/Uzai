extends "res://tests/probe_base.gd"
## Fehlende Launcher und RetroAchievements-Assistent: Einrichtung → Spiele mit fehlendem Steam und
## Epic, die Angebotsseite, Einstellungen → Spiele, der RA-Assistent (Start, Fehler, verbunden).

const SetupWizard := preload("res://src/ui/layers/setup_wizard.gd")


func run() -> void:
	Library.launchers = { "steam": false, "epic": false, "ea": true }
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.step", "spiele")
	var w = SetupWizard.open_for(main, false)
	await wait(2.0)
	await shot("01_einrichtung_spiele", 0.4)
	await press("down")
	await shot("02_launcher_zeile", 0.4)
	main.open_launcher_offer("steam")
	await wait(0.8)
	await shot("03_angebot_steam", 0.3)
	Nav.top_layer().close()
	await wait(0.4)
	main.open_launcher_offer("ea")
	await wait(0.8)
	await shot("04_angebot_ea", 0.3)
	Nav.top_layer().close()
	w.close()
	await wait(0.6)
	main.goto("settings", "spiele")
	await wait(1.2)
	await shot("05_einstellungen_spiele", 0.3)
	var ra = main.open_ra_login()
	await wait(0.9)
	await shot("06_ra_start", 0.3)
	ra._submit("A", "kurz")
	await wait(0.8)
	await shot("07_ra_fehler", 0.3)
	ra._name = "Anna"
	ra._points = 1234
	ra._state = "done"
	ra._refill()
	await wait(0.8)
	await shot("08_ra_verbunden", 0.3)
	print("RA Seite: ", Remote.form_html({ "title": "RetroAchievements", "hint": "h", "link": "https://retroachievements.org/settings",
		"fields": [{ "name": "user", "label": "Benutzername" }, { "name": "key", "label": "Web-API-Schlüssel", "secret": true }] }).length())

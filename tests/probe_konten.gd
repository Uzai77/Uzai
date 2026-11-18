extends "res://tests/probe_base.gd"
## Konten und Datenschutz (Punkte 13, 77): Konten-Seite, „Gespeichert und gesendet“, Rückfrage
## beim Abmelden und die Seite danach. Ausgabe „KO …“.


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("accounts.ra_user", "Pixelpaul")
	Config.set_value("accounts.ra_key", "abcdefghijklmnopqrstuvwxyz012345")
	Config.set_value("accounts.sgdb_key", "0123456789abcdef0123456789abcdef")
	Config.set_value("accounts.discord_client_id", "123456789012345678")
	Config.set_value("accounts.discord_client_secret", "geheimgeheimgeheimgeheimgeheim12")
	Config.set_value("accounts.discord_token", "tok")
	main.goto("settings", "konten")
	await wait(1.2)
	var view: Node = main.sections["settings"]
	await press("down", 12)
	await shot("01_konten_unten", 0.6)
	view.open_more("Gespeichert und gesendet")
	await shot("02_datenschutz", 1.0)
	await press("down", 3)
	await shot("03_datenschutz_dienst", 0.6)
	await press("down", 12)
	await shot("04_datenschutz_unten", 0.6)
	view._confirm_logout("discord")
	await shot("05_rueckfrage_discord", 0.8)
	await press("b")
	await wait(0.5)
	view._confirm_logout("steamgriddb")
	await shot("05b_rueckfrage_schluessel", 0.8)
	await press("b")
	await wait(0.5)
	await view._logout("retroachievements", false)
	print("KO RA nach Abmelden: user=", Config.get_value("accounts.ra_user", "?"), " key=", Config.get_value("accounts.ra_key", "?"))
	print("KO Discord-App bleibt: ", Config.get_value("accounts.discord_client_id", ""))
	await shot("06_nach_abmelden", 1.2)
	# Nicht angemeldet: A führt zur Seite, auf der man sich verbindet (über der Übersicht).
	view._service_tap("epic")
	await shot("07_verbinden_epic", 1.0)

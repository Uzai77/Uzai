extends "res://tests/probe_base.gd"
## Probe: Nuvio-Konto (Einstellungen → Filme, QR-Anmeldung gegen tests/fake_nuvio.py über
## UZAI_NUVIO_API), Freunde im Guide nach Steam/Discord getrennt, Discord-Profil, Anrufen.


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await get_tree().process_frame
	await wait(0.35)


func focus_key(k: String) -> void:
	for c in Nav.focusables(main.sections["settings"]):
		if str(c.get_meta("uz_key", "")) == k:
			Nav.focus(c, true)
			return
	print("Nicht gefunden: ", k)


func run() -> void:
	main.goto("settings", "filme")
	await wait(1.0)
	focus_key("set:filme:Mit Nuvio anmelden")
	await shot("n01_einstellungen", 0.8)
	main.open_nuvio_login()
	await shot("n02_qr", 2.5)
	await _close_all()
	# Angemeldet (Werte wie nach einem Abgleich)
	Config.set_value("nuvio.refresh", "probe")
	Config.set_value("nuvio.email", "lea@example.com")
	NuvioSync.sput("last_sync", int(Time.get_unix_time_from_system()) - 180)
	NuvioSync.sput("profiles", [{ "profile_index": 1, "name": "Lea" }, { "profile_index": 2, "name": "Kinder" }])
	main.sections["settings"].build()
	await wait(0.6)
	focus_key("set:filme:Konto")
	await shot("n03_angemeldet", 0.8)
	Config.set_value("nuvio.refresh", "")
	# Guide: Freunde nach Quelle
	main.toggle_guide("freunde")
	await wait(1.2)
	await shot("n04_guide_freunde", 0.4)
	main.toggle_guide()
	await _close_all()
	# Discord-Profil
	var f: Dictionary = DiscordChat.friends[0] if not DiscordChat.friends.is_empty() else { "id": "1", "name": "Mia", "username": "mia", "state": "online",
			"game": "Valorant", "dm": true }
	var e := { "name": f.name, "avatar": str(f.get("avatar", "")), "state": str(f.get("state", "online")), "game": str(f.get("game", "")), "dm": f, "steam": {},
			"discord": {} }
	var l = load("res://src/ui/layers/discord_profile.gd").new()
	l.friend = e
	main.open_layer(l)
	await shot("n05_discord_profil", 0.9)
	await _close_all()
	Toasts.show_toast("Rufe Mia an …", "Discord klingelt bei deinem Freund. Auflegen: im Guide unter Discord „Verlassen“.", "phone", { "ms": 4000 })
	await shot("n06_anruf", 0.8)
	await wait(4.5)
	# Eingehender Anruf: Guide auf, Karte mittig darüber
	main.toggle_guide("discord")
	await wait(0.8)
	main.open_incoming_call({ "user_id": "x", "channel_id": "dm1", "name": "Mia", "avatar": "" })
	await shot("n07_anruf_karte", 0.9)

extends "res://tests/probe_base.gd"
## Probe Discord-Freunde: Liste mit Aktivität, die Auswahl beim Druck auf A (wie bei
## Steam), das Profil mit „Spielt gerade“ und „Hört gerade“, zum Vergleich die Steam-Auswahl.


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	Config.set_value("theme.corners", "rund")
	Config.set_value("accounts.discord_servers", [])
	await wait(0.6)
	main.goto("friends", "discord")
	await wait(1.2)
	# Oben steht die Freundschaftsanfrage; eins tiefer Sana (spielt).
	await press("down")
	await shot("01_discord_liste", 1.4)
	var sana := DiscordChat.friend("1001")
	var kai := DiscordChat.friend("1002")
	await press("a")
	await shot("02_discord_auswahl", 0.9)
	await press("b")
	await wait(0.4)
	main.goto("friends", "steam")
	await wait(0.8)
	main.open_friend(Social.steam_friends[0], "steam")
	await shot("03_steam_auswahl", 0.9)
	await press("b")
	await wait(0.4)
	main.goto("friends", "discord")
	await wait(0.8)
	await press("down")
	var l = load("res://src/ui/layers/discord_profile.gd").new()
	var f2 := sana.duplicate()
	f2["dm"] = sana
	l.friend = f2
	main.open_layer(l)
	await shot("04_discord_profil_spiel", 1.4)
	await press("b")
	await wait(0.4)
	var l2 = load("res://src/ui/layers/discord_profile.gd").new()
	var f3 := kai.duplicate()
	f3["dm"] = kai
	l2.friend = f3
	main.open_layer(l2)
	await shot("05_discord_profil_musik", 1.2)
	await press("b")
	await wait(0.4)
	await press("down")
	await shot("06_discord_kai_karte", 1.2)
	main.open_friend(kai, "discord")
	await shot("07_discord_kai_auswahl", 0.9)
	await press("b")
	await press("down", 1)
	await shot("08_discord_noor_ohne_aktivitaet", 1.2)
	main.open_friend(DiscordChat.friend("1003"), "discord")
	await shot("09_discord_noor_auswahl", 0.9)
	await press("b")

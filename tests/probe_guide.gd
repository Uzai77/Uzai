extends "res://tests/probe_base.gd"
## Probe für den Guide: alle Reiter außerhalb und im Spiel, die Menüs an Personen und Freunden,
## Ausschalten, Lautstärke, dazu Zwischenbilder vom Aufgehen und vom Reiterwechsel.
## Mit --uzai-extra zeigt sie zusätzlich Zustände, die die Demo sonst nicht hat (mehr Kanäle,
## ungelesene Nachricht, Erfolge des laufenden Spiels, Mitteilungen).

const InGame := preload("res://src/ui/in_game.gd")

var extra := false


func _close_guide() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


func run() -> void:
	extra = "--uzai-extra" in OS.get_cmdline_user_args()
	if extra:
		Toasts.show_toast("Mira ist online", "spielt Elden Ring", "friends")
		Toasts.show_toast("Bildschirmfoto gespeichert", "Elden Ring 2026-10-15.png", "camera")
		Voice.others.append({ "id": "14", "name": "Lernen", "members": [{ "id": "24", "name": "Ole", "avatar": "" }] })
		Voice.others.append({ "id": "15", "name": "AFK", "members": [] })
		Voice.others.append({ "id": "16", "name": "Musik", "members": [{ "id": "25", "name": "Ina", "avatar": "" }, { "id": "26", "name": "Bo", "avatar": "" }] })
	main.goto("games", "zuletzt")
	await wait(0.6)
	# Aufgehen: zwei Zwischenbilder und der Endstand (Discord, weil Leute im Kanal sind)
	main.toggle_guide()
	await shot("g01_auf_a", 0.05)
	await shot("g01_auf_b", 0.08)
	await shot("g02_discord", 0.9)
	# Eigene Kachel (links) und ihr Menü
	await press("left")
	await shot("g03_discord_ich", 0.4)
	await press("a")
	await shot("g04_menue_ich", 0.6)
	await press("b")
	await press("right")
	await press("a")
	await shot("g05_menue_person", 0.6)
	await press("down")
	await press("right", 2)
	await shot("g05b_menue_lauter", 0.4)
	await press("b")
	# Reiterwechsel: Zwischenbild und Endstand
	await press("rb")
	await shot("g06_musik_wechsel", 0.06)
	await shot("g07_musik", 0.6)
	await press("rb")
	if extra:
		SteamChat.unread = { "76561190000000002": 2 }
		SteamChat.changed.emit()
	await shot("g08_freunde", 0.8)
	await press("a")
	await shot("g08b_freund_menue", 0.7)
	await press("b")
	await press("rb")
	await shot("g09_system", 0.6)
	await press("right")
	await shot("g10_system_lautstaerke", 0.4)
	await press("right")
	await shot("g10b_lauter", 0.3)
	await press("rt")
	await shot("g10c_rt", 0.3)
	await press("rb")
	await shot("g11_spiel_menue", 0.7)
	# Ausschalten aus dem Guide (System → Ausschalten)
	await press("lb")
	await press("down", 4)
	await press("a")
	await shot("g12_ausschalten", 0.7)
	await _close_guide()
	# Im Spiel (Steam, ein Freund spielt dasselbe)
	Launcher.in_game = true
	Launcher.current = Library.get_game("steam:1245620")
	if extra:
		var now := int(Time.get_unix_time_from_system())
		Achievements._games["steam:1245620"] = { "source": "steam", "appid": 1245620, "title": "Elden Ring", "total": 42, "unlocked": 17, "last_unlock": now - 7200,
			"list": [
				{ "id": "a", "title": "Fürst des Gehöfts", "desc": "Godrick den Verpflanzten besiegt", "icon": "", "unlocked": true, "date": now - 7200, "rarity": 6.4 },
				{ "id": "b", "title": "Wanderer", "desc": "Das Zwischenland betreten", "icon": "", "unlocked": true, "date": now - 86400 * 3, "rarity": 80.0 }] }
	main.toggle_guide("spiel")
	await shot("g13_im_spiel", 1.0)
	await press("down", 3)
	await shot("g13b_im_spiel_unten", 0.4)
	await press("lb")
	await shot("g14_im_spiel_system", 0.6)
	await press("lb")
	await shot("g15_im_spiel_freunde", 0.8)
	await press("lb", 2)
	await shot("g16_im_spiel_discord", 0.8)
	await _close_guide()
	# Im Spiel (Emulator, niemand spielt mit)
	Launcher.current = Library.get_game(Library.by_system("ps2")[0].id)
	main.toggle_guide("spiel")
	await shot("g17_im_spiel_ps2", 1.0)
	await _close_guide()
	Launcher.in_game = false
	Launcher.current = {}
	await wait(0.3)
	# Startbildschirm eines Spiels (beim Start und im Spiel, falls Uzai sichtbar bleibt)
	var ig = InGame.new()
	ig.game = Library.get_game("steam:1245620")
	ig.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.layer_host.add_child(ig)
	await shot("g18_start", 0.7)
	ig.set_running()
	await shot("g19_laeuft", 0.7)
	ig.queue_free()
	await wait(0.2)
	# Viele Freunde: das Raster scrollt mit dem Fokus
	if extra:
		for i in 10:
			Social.steam_friends.append({ "id": "7656119000000010%d" % i, "name": "Freund %d" % (i + 1), "avatar": "",
				"state": "online" if i % 3 else "away", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "" })
	main.toggle_guide("freunde")
	await shot("g20_freunde_viele", 1.0)
	await press("down", 4)
	await shot("g20b_freunde_unten", 0.6)
	await _close_guide()
	# Video läuft: Spiel-Reiter zeigt das Video
	main.open_video(YouTube.feed, 3)
	await wait(2.0)
	main.toggle_guide("spiel")
	await shot("g21_video", 1.0)
	await _close_guide()
	await wait(0.6)
	# Ohne Sprachkanal: Kanäle mit Leuten zum Beitreten
	Voice.leave()
	main.toggle_guide("discord")
	await shot("g22_discord_ohne_kanal", 1.0)
	await _close_guide()

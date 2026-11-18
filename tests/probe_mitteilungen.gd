extends "res://tests/probe_base.gd"
## Probe Mitteilungen: Pop-up einer Steam-Nachricht und einer Discord-Benachrichtigung in Uzai,
## View öffnet den Chat, das eigene Pop-up-Fenster „im Spiel“ (über einem Spielbild
## zusammengesetzt) und die Einstellungen.


func run() -> void:
	Config.set_value("theme.preset", "uzai")
	main.goto("games")
	await wait(0.8)
	var mira := str(Social.steam_friends[0].id)
	SteamChat.on_incoming({ "friend": mira, "kind": 2 })
	await wait(0.4)
	SteamChat.on_incoming(
			{ "friend": mira, "kind": 1, "text": "Bist du gleich dabei? Ich bin schon im Sprachkanal und wir starten in fünf Minuten.",
			"at": int(Time.get_unix_time_from_system()), "ordinal": 0 })
	await shot("01_popup_steam", 0.9)
	Notify._on_discord({ "channel_id": "5", "message": { "id": "77", "content": "@du kommst du heute Abend?", "author": { "id": "9", "username": "sana" } },
		"icon_url": "", "title": "Sana (#zocken, Retro-Runde)", "body": "@du kommst du heute Abend?" })
	await shot("02_popup_discord", 0.9)
	main.goto("games")
	SteamChat.on_incoming({ "friend": mira, "kind": 1, "text": "Hallo?", "at": int(Time.get_unix_time_from_system()) + 1, "ordinal": 0 })
	await wait(0.6)
	Nav._fire("view")
	await shot("03_view_oeffnet_chat", 1.2)
	await press("b")
	await wait(0.6)
	# Im Spiel: eigenes Fenster oben rechts. Hier ohne Spiel erzwungen; zusammengesetzt über
	# dem Bild der Startseite (als „Spiel“), wie es auf dem Bildschirm läge.
	Toasts.force_overlay = true
	SteamChat.on_incoming(
			{ "friend": str(Social.steam_friends[1].id), "kind": 1, "text": "GG! Noch eine Runde?", "at": int(Time.get_unix_time_from_system()) + 2, "ordinal": 0 })
	await wait(1.0)
	await RenderingServer.frame_post_draw
	var win: Window = Toasts._win
	print("Fenster: sichtbar=%s eingebettet=%s fokuslos=%s oben=%s durchsichtig=%s maus_durch=%s größe=%s pos=%s hauptfenster_fokus=%s" % [
		str(win.visible), str(win.is_embedded()), str(win.unfocusable), str(win.always_on_top), str(win.transparent),
		str(win.mouse_passthrough), str(win.size), str(win.position), str(get_window().has_focus())])
	print("Fenster hat Fokus: %s · Fenster-ID %d · Hauptfenster-Modus %d" % [str(win.has_focus()), win.get_window_id(), get_window().mode])
	var wimg := win.get_texture().get_image()
	wimg.save_png(out.path_join("04_fenster_allein.png"))
	var bg := get_viewport().get_texture().get_image()
	bg.convert(Image.FORMAT_RGBA8)
	wimg.convert(Image.FORMAT_RGBA8)
	var game_bg := Image.create(bg.get_width(), bg.get_height(), false, Image.FORMAT_RGBA8)
	game_bg.fill(Color(0.18, 0.22, 0.3))
	game_bg.blend_rect(bg, Rect2i(Vector2i.ZERO, bg.get_size()), Vector2i.ZERO)
	var scale := float(bg.get_height()) / 1080.0
	if absf(scale - 1.0) > 0.01:
		wimg.resize(int(wimg.get_width() * scale), int(wimg.get_height() * scale))
	var at := Vector2i(bg.get_width() - wimg.get_width() - int(40 * scale), 0)
	game_bg.blend_rect(wimg, Rect2i(Vector2i.ZERO, wimg.get_size()), at)
	game_bg.save_png(out.path_join("05_im_spiel_zusammengesetzt.png"))
	await wait(7.5)
	print("Fenster nach dem Pop-up: sichtbar=%s" % str(is_instance_valid(win) and win.visible))
	Toasts.force_overlay = false
	main.goto("settings", "system")
	await shot("06_einstellungen", 1.2)
	# Guide-Taste „im Spiel“ kurz nach einem Pop-up: Guide geht direkt beim Chat auf.
	main.goto("games")
	await wait(0.5)
	Launcher.in_game = true
	Toasts.force_overlay = true
	SteamChat.on_incoming(
			{ "friend": str(Social.steam_friends[2].id), "kind": 1, "text": "Bin in der Lobby", "at": int(Time.get_unix_time_from_system()) + 3, "ordinal": 0 })
	await wait(0.5)
	Toasts.force_overlay = false
	main.toggle_guide()
	await shot("07_guide_im_spiel_mit_chat", 1.4)
	Launcher.in_game = false

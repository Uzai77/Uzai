extends "res://tests/probe_base.gd"
## Probe YouTube-Zusätze: Reiter „Shorts“ (hohe Karten), Shorts im Player (blättern), SponsorBlock
## (Sprung mit „links: zurück“), „Nur Ton“ in den Hintergrund (Kopfleiste, Guide-Reiter
## „Video-Ton“) und die Einstellungen dazu.


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	await _shorts()
	await _sponsorblock()
	await _background()
	await _settings()


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


func _shorts() -> void:
	main.goto("videos", "shorts")
	await shot("01_shorts_raster", 1.4)
	await press("right", 2)
	await shot("02_shorts_fokus", 0.6)
	await press("a")
	await shot("03_short_player", 1.4)
	await press("down")
	await shot("04_short_blaettern_mitte", 0.12)
	await shot("05_short_naechster", 0.8)
	print("Short: Index %d von %d, Shorts-Modus %s" % [Video.index, Video.queue.size(), Video.shorts])
	await press("up")
	await shot("06_short_zurueck", 0.8)
	print("Short nach hoch: Index %d" % Video.index)
	await press("rt", 2)
	await shot("07_short_lauter", 0.4)
	await press("b")
	await wait(0.8)


func _sponsorblock() -> void:
	main.open_video(YouTube.feed, 3)
	await wait(1.4)
	Video.seek_to(29.0)
	await wait(2.0)
	await shot("10_sponsor_uebersprungen", 0.1)
	print("Nach dem Sprung: %.1f s" % Video.pos)
	await press("left")
	await shot("11_sponsor_zurueck", 0.5)
	print("Nach links: %.1f s" % Video.pos)
	await press("b")
	await wait(0.8)


func _background() -> void:
	main.open_video(YouTube.feed, 1, { "audio": true })
	await shot("20_nur_ton_player", 1.4)
	await press("menu")
	await shot("21_im_hintergrund", 1.2)
	print("Hintergrund: aktiv %s, background %s, Player offen %s" % [Video.active, Video.background, is_instance_valid(main.get("_player"))])
	main.goto("games")
	await shot("22_startseite_mit_ton", 1.2)
	main.toggle_guide("ton")
	await shot("23_guide_video_ton", 1.4)
	await press("rt", 2)
	await shot("24_guide_lauter", 0.5)
	await press("right")
	await shot("25_guide_mit_bild_fokus", 0.4)
	await press("b")
	await wait(0.8)
	# Aus den Optionen eines Videos gleich im Hintergrund starten.
	Video.stop()
	await wait(0.5)
	main.goto("videos", "start")
	await wait(1.0)
	main.open_video_options(YouTube.feed[2], YouTube.feed, 2)
	await shot("26_optionen_hintergrund", 0.9)
	await _close_all()
	main.play_in_background(YouTube.feed, 2)
	await shot("27_direkt_im_hintergrund", 1.2)
	Video.stop()
	await wait(0.6)


func _settings() -> void:
	main.goto("settings", "medien")
	await wait(0.9)
	var sv = main.sections["settings"]
	sv._enter_content()
	await wait(0.3)
	for c in Nav.focusables(sv._list):
		if str(c.get_meta("uz_key", "")).contains("Shorts"):
			Nav.focus(c, true)
			break
	await shot("30_einstellungen_videos", 0.6)
	sv.open_more("Abschnitte überspringen")
	await shot("31_sponsorblock", 0.9)

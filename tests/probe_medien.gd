extends "res://tests/probe_base.gd"
## Probe der vier Medien-Apps in einem Lauf (Demo-Daten): Videos, Filme, Streams und Musik mit
## ihren Startseiten, eine Detailseite, eine Kanalseite und der Player. Für den Vergleich der
## gemeinsamen Medien-Sprache (docs/PLAN_MEDIEN.md). Aufruf siehe probe_base.gd.
## Mit --uzai-part=start,seiten,player nur Teile (Standard: alles).

var parts := PackedStringArray()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-part="):
			parts = a.substr(12).split(",")
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Config.set_value("controller.glyphs", "xbox")
	Nav.device_changed.emit("pad")
	Config.set_value("system.music_mode", "spotify")
	await wait(0.4)
	if _want("start"):
		await _startseiten()
	if _want("seiten"):
		await _seiten()
	if _want("player"):
		await _player()


func _want(p: String) -> bool:
	return parts.is_empty() or parts.has(p)


func _startseiten() -> void:
	main.goto("videos", "fuerdich")
	await shot("01_videos", 1.8)
	await press("down")
	await press("right", 2)
	await shot("02_videos_reihe", 1.0)
	main.goto("movies", "start")
	await shot("03_filme", 1.8)
	await press("down")
	await press("right")
	await shot("04_filme_reihe", 1.4)
	main.goto("streams", "start")
	await shot("05_streams", 1.8)
	await press("down")
	await shot("06_streams_reihe", 1.0)
	main.goto("music", "fuerdich")
	await shot("07_musik", 1.8)
	main.goto("music", "jetzt")
	await shot("08_musik_jetzt", 1.4)


func _seiten() -> void:
	main.goto("movies", "start")
	await wait(0.8)
	var rows: Array = await Movies.call("home_rows")
	if not rows.is_empty() and not (rows[0].items as Array).is_empty():
		main.open_movie((rows[0].items as Array)[0])
		await shot("10_film_detail", 1.6)
		await press("b")
		await wait(0.5)
	main.goto("streams", "start")
	await wait(0.6)
	if not Twitch.top.is_empty():
		var tw: Dictionary = (Twitch.top[0] as Dictionary).get("twitch", {})
		main.open_stream_channel(str(tw.get("login", "")), str(tw.get("name", "")))
		await shot("11_stream_kanal", 1.6)
		await press("b")
		await wait(0.5)
	main.goto("videos", "fuerdich")
	await wait(0.6)
	main.open_channel("UCpixelbude0000000000b0", "Pixelbude")
	await shot("12_video_kanal", 1.6)
	await press("b")
	await wait(0.5)


func _player() -> void:
	main.goto("videos", "fuerdich")
	await wait(0.6)
	main.open_video(YouTube.feed, 3)
	await shot("20_player", 2.4)
	await press("right", 3, 0.1)
	await shot("21_player_spulen", 0.3)
	await press("a")
	await shot("22_player_pause", 0.6)
	await press("b")
	await wait(0.8)

extends "res://tests/probe_base.gd"
## Probe für den Bereich Videos: alle Unterseiten, Kanal, Optionen, Player (mit Ende und
## „Nur Ton“) und die Google-Anmeldung. Aufruf siehe probe_base.gd.
## Mit --uzai-part=listen,kanal,player,login nur Teile (Standard: alles).

var parts := PackedStringArray()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-part="):
			parts = a.substr(12).split(",")
	if _want("listen"):
		await _lists()
	if _want("kanal"):
		await _channel()
	if _want("player"):
		await _player()
	if _want("nurton"):
		await _audio()
	if _want("login"):
		await _login()
	if _want("setup"):
		await _setup()
	if _want("bilder"):
		await _images()


func _want(p: String) -> bool:
	return parts.is_empty() or parts.has(p)


func _lists() -> void:
	var vv = main.sections["videos"]
	main.goto("videos", "fuerdich")
	await shot("01_fuerdich", 1.6)
	await press("down")
	await shot("02_fuerdich_runter", 0.8)
	await press("right", 2)
	await shot("03_fuerdich_rechts", 0.6)
	await press("x")
	await shot("03b_fuerdich_gemerkt", 0.6)
	await press("x")
	await press("down")
	await shot("04_fuerdich_reihe2", 0.8)
	await press("down", 2)
	await shot("05_fuerdich_unten", 0.8)
	await press("up", 4)
	await shot("06_fuerdich_zurueck", 0.8)
	main.goto("videos", "start")
	await shot("07_neu", 1.2)
	await press("down", 2)
	await shot("08_neu_runter", 0.8)
	main.goto("videos", "abos")
	await shot("09_abos", 1.0)
	main.goto("videos", "suche")
	await shot("10_suche_leer", 0.8)
	vv._run_search("retro")
	await shot("11_suche", 1.0)
	main.goto("videos", "merkliste")
	await shot("12_merkliste", 0.8)
	main.goto("videos", "verlauf")
	await shot("13_verlauf", 0.8)
	main.goto("videos", "playlists")
	await shot("14_playlists", 0.8)


func _channel() -> void:
	main.goto("videos", "fuerdich")
	await wait(0.8)
	await press("down")
	await press("right", 2)
	await press("y")
	await shot("20_optionen", 0.7)
	for c in Nav.focusables(Nav.top_layer()):
		if str(c.get_meta("uz_key", "")) == "vopt:Link aufs Handy":
			Nav.focus(c)
	await shot("21_optionen_unten", 0.4)
	await press("a")
	await shot("22_link_handy", 0.8)
	await press("b")
	await wait(0.3)
	await press("b")
	await wait(0.3)
	main.open_channel("UCpixelbude0000000000b0", "Pixelbude")
	await shot("23_kanal", 1.4)
	await press("down")
	await shot("24_kanal_runter", 0.6)
	await press("up", 3)
	await shot("25_kanal_oben", 0.6)
	await press("b")
	await wait(0.4)
	main.open_video_grid("Retro-Abende", "Playlist", func() -> Array: return await YouTube.playlist_videos("PL1"))
	await shot("26_playlist", 1.2)
	await press("b")
	await wait(0.4)


func _player() -> void:
	main.open_video(YouTube.feed, 3)
	await shot("30_player", 2.6)
	await press("right", 3, 0.1)
	await shot("31_player_spulen", 0.3)
	await press("up")
	await shot("32_player_lauter", 0.2)
	await wait(2.0)
	await press("y")
	await shot("33_player_optionen", 0.6)
	await press("b")
	await press("a")
	await shot("34_player_pause", 0.5)
	await press("x")
	await shot("35_player_untertitel", 0.4)
	await press("a")
	Video.seek_to(Video.duration - 1.5)
	await shot("36_player_ende", 2.6)
	await press("b")
	await shot("37_player_ende_abgebrochen", 0.6)
	await press("b")
	await wait(0.8)


func _audio() -> void:
	main.open_video(YouTube.feed, 1, { "audio": true })
	await shot("38_nur_ton", 2.0)
	await press("b")
	await wait(0.8)


func _login() -> void:
	main.open_yt_login()
	await shot("40_login_einrichten", 0.8)
	var login = Nav.top_layer()
	login._info = { "url": "https://www.google.com/device", "user_code": "KXRT-PWQB", "device_code": "x", "interval": 999, "expires": 1800 }
	login._until = Time.get_unix_time_from_system() + 1800
	login._state = "code"
	login._refill()
	await shot("41_login_code", 0.8)
	login._state = "done"
	login._refill()
	await shot("42_login_fertig", 0.6)
	login._state = "error"
	login._msg = "Google antwortet nicht."
	login._refill()
	await shot("43_login_fehler", 0.6)
	login._state = "x"
	await press("b")
	await wait(0.4)


func _setup() -> void:
	# Einrichten-Seite (in der Demo sonst nie zu sehen).
	YouTube.demo = false
	main.goto("videos", "fuerdich")
	await shot("50_einrichten", 1.0)
	YouTube.demo = true
	main.sections["videos"].build()
	await wait(0.3)


## Mit echten Bildern (lokale Dateien statt YouTube): --uzai-art=<Ordner mit hero.jpg, rom/…>
func _images() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uzai-art="):
			dir = a.substr(11)
	if dir == "":
		return
	var files := ["hero.jpg", "rom/snap.png", "rom/title.png", "rom/ico_snap.png"]
	var list: Array = []
	for i in 8:
		var v: Dictionary = (YouTube.feed[i] as Dictionary).duplicate()
		v["id"] = "lokal%d" % i
		v["thumb"] = dir.path_join(files[i % files.size()])
		list.append(v)
	var keep: Array = YouTube.recs
	YouTube.recs = list
	main.goto("videos", "fuerdich")
	await shot("60_bilder_fuerdich", 2.4)
	await press("down")
	await press("down")
	await shot("61_bilder_reihe", 1.6)
	main.open_video_grid("Mit Bildern", "Playlist", func() -> Array: return list)
	await shot("62_bilder_liste", 2.0)
	await press("b")
	await wait(0.4)
	main.open_video(list, 0)
	await shot("63_bilder_player", 2.4)
	await press("b")
	await wait(0.6)
	YouTube.recs = keep

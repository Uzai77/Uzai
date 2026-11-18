extends "res://tests/probe_base.gd"
## Musik-Bereich fotografieren: ohne Spotify (Medientasten) und mit Spotify (Demo-Daten):
## Für dich, Läuft gerade, Playlists, Lieblingssongs, Zuletzt gehört, Suche, Titellisten
## (Mix, Mix von Spotify, Album, fremde Playlist), das Musik-Menü, QR-Code und Geräte.

const TrackList := preload("res://src/ui/layers/track_list.gd")


func run() -> void:
	# Teil a oder b (UZAI_PROBE_PART), damit eine Probe auch auf einem vollen Rechner durchläuft.
	var part := OS.get_environment("UZAI_PROBE_PART")
	if part == "b":
		await _part_b()
		return
	if part == "c":
		await _part_c()
		return
	await _part_a()
	if part != "a":
		await _part_b()


func _part_a() -> void:
	Config.set_value("system.music_mode", "tasten")
	await wait(0.4)
	main.goto("music")
	await shot("01_tasten", 1.2)
	Config.set_value("system.music_mode", "spotify")
	await wait(0.4)
	main.goto("games")
	await wait(0.4)
	main.goto("music", "fuerdich")
	await shot("02_fuerdich", 1.6)
	await press("right", 2)
	await shot("03_fuerdich_rechts", 0.9)
	await press("down")
	await shot("04_fuerdich_neu", 0.9)
	await press("down")
	await shot("05_fuerdich_alben", 0.9)
	await press("down")
	await shot("06_fuerdich_playlists", 0.9)
	main.goto("music", "jetzt")
	await shot("07_jetzt", 1.4)
	await press("right", 6)
	await shot("08_jetzt_queue", 0.8)
	main.goto("music", "playlists")
	await shot("09_playlists", 1.0)
	main.goto("music", "lieblinge")
	await shot("10_lieblinge", 1.0)
	await press("right")
	await press("down", 2)
	await shot("11_lieblinge_zeile", 0.6)
	main.goto("music", "zuletzt")
	await shot("12_zuletzt", 1.2)
	main.goto("music", "suche")
	await shot("13_suche", 0.9)
	var mv = main.sections["music"]
	mv._run_search("Nobuo")
	await shot("14_suche_treffer", 1.0)


func _part_b() -> void:
	Config.set_value("system.music_mode", "spotify")
	await wait(0.4)
	var mv = main.sections["music"]
	main.goto("music", "fuerdich")
	await wait(0.6)
	var mixes: Array = Music.own_mixes()
	await _layer(mixes[0], "20_mix_top")
	await _layer(Music.spotify_mixes[0], "21_spotify_mix")
	await _layer(Music.new_releases[0], "22_album")
	await _layer(Music.playlists[2], "23_playlist_fremd")
	await _layer(mixes[1], "24_mix_neu")
	main.open_music_actions()
	await shot("30_menue", 0.9)
	await press("b")
	await wait(0.4)
	var q = load("res://src/ui/layers/music_qr.gd").new()
	q.link = Music.share_link()
	q.song = "To Zanarkand – Nobuo Uematsu"
	main.open_layer(q)
	await shot("31_qr", 0.8)
	await press("b")
	await wait(0.4)
	main.goto("music", "jetzt")
	await wait(0.6)
	mv._pick_device()
	await shot("32_geraete", 0.8)
	await press("b")
	await wait(0.4)


func _layer(it: Dictionary, name: String) -> void:
	var tl = TrackList.new()
	tl.playlist = it
	tl.main = main
	main.open_layer(tl)
	await shot(name, 1.4)
	await press("b")
	await wait(0.4)


## Zustände: Für dich lädt noch (alte Anmeldung), nichts läuft (mit und ohne Spotify).
func _part_c() -> void:
	Config.set_value("system.music_mode", "spotify")
	await wait(0.4)
	var mv = main.sections["music"]
	main.goto("music", "fuerdich")
	await wait(1.0)
	Music.need_login = true
	Music.spotify_mixes = []
	Music.top_tracks = []
	Music.for_you_parts = { "mixe": "laedt", "top": "laedt", "neu": "ok", "alben": "ok" }
	mv.build()
	await shot("40_fuerdich_laedt", 1.2)
	Music._demo_for_you()
	Music.need_login = false
	main.goto("music", "jetzt")
	await wait(0.6)
	Music.now = {}
	Music.queue_list = []
	Music.updated.emit()
	mv.build()
	await shot("41_jetzt_leer", 1.0)
	Config.set_value("system.music_mode", "tasten")
	await wait(0.4)
	Music.now = {}
	Music.updated.emit()
	main.goto("music")
	mv.build()
	await shot("42_tasten_leer", 1.0)

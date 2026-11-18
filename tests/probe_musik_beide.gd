extends "res://tests/probe_musikquelle.gd"
## Probe „Spotify und eigene Musik“ (Demo): Musik-Tab mit beiden Quellen – Reiter „Eigene Musik“,
## „Für dich“ mit der Reihe aus dem Musikordner, dann ein eigenes Album im Guide (Spotify hält an).


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var dir := Config.path("probe_musik/Musik")
	_make_library(dir)
	Config.set_value("system.music_mode", "spotify")
	Config.set_value("music.local_dir", dir)
	await wait(0.3)
	while Music.local.scanning:
		await wait(0.1)
	print("Beide: %s, Quelle %s, %d Alben" % [str(Music.beide()), Music.aktiv, Music.local.albums.size()])
	await main.goto("music", "eigene")
	await shot("01_eigene_musik", 1.4)
	await main.goto("music", "fuerdich")
	await wait(0.8)
	_focus_text(main.sections.music, "Nachtfahrt")
	await shot("02_fuer_dich", 1.2)
	LocalUi().play(Music.local.albums[0])
	await wait(0.6)
	print("Läuft: %s (%s), Quelle %s" % [str(Music.now.get("title", "")), str(Music.now.get("source", "")), Music.aktiv])
	main.toggle_guide("musik")
	await shot("03_guide_eigene", 1.2)
	await _close_all()
	Music.play_context("spotify:playlist:demo")
	await wait(0.4)
	print("Danach: %s, Quelle %s, eigene Musik spielt: %s" % [str(Music.now.get("title", "")), Music.aktiv, str(Music.local.wants_play())])

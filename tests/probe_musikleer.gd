extends "res://tests/probe_base.gd"
## Probe: Musikordner gewählt, aber leer → Bühne mit „Anderer Ordner“ links und „Spotify verbinden“ rechts.


func run() -> void:
	var dir := OS.get_user_data_dir().path_join("probe_musik_leer")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("system.music_mode", "lokal")
	Config.set_value("music.local_dir", dir)
	await wait(2.0)
	await main.goto("music", "alben")
	await shot("musik_leer", 1.6)

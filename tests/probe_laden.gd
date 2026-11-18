extends "res://tests/probe_base.gd"
## Probe: Videos (Startseite, unten in den Reihen) und Filme nach dem Öffnen – Bilder kommen in
## der Nähe der Auswahl, Reihen oben zuerst. Aufruf siehe probe_base.gd.


func run() -> void:
	main.goto("videos", "fuerdich")
	await shot("01_videos", 1.6)
	await press("down", 3)
	await shot("02_videos_unten", 1.0)
	main.goto("movies", "start")
	await shot("03_filme", 2.0)

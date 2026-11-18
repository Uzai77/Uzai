extends "res://tests/probe_base.gd"
## Probe der Quellenwahl (Demo-Daten): Liste mit Chips, Dateinamen und Sprachen, aufgeklappte
## Zeile mit Fokus und die Sprachauswahl. Aufruf siehe probe_base.gd.


func run() -> void:
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Config.set_value("controller.glyphs", "xbox")
	Nav.device_changed.emit("pad")
	var rows: Array = await Movies.call("home_rows")
	var film: Dictionary = (rows[0].items as Array)[0]
	main.open_movie_streams(film, str(film.id), "ask")
	await shot("streams_1_liste", 2.6)
	await press("down", 2)
	await shot("streams_2_fokus", 0.8)
	await press("x")
	await shot("streams_3_sprache", 0.8)


extends "res://tests/probe_base.gd"
## „Mit Spotify anmelden“ im Vorführmodus: die Anmeldeseite im Uzai-Browser (Platzhalter des nachgebauten Kerns),
## dann „Anmelden“ – der Kern meldet einen Schlüssel, das Fenster schließt – und der Musikbereich mit Demodaten.


func run() -> void:
	Config.set_value("system.music_mode", "spotify")
	main.goto("music", "fuerdich")
	await wait(0.8)
	load("res://src/ui/layers/spotify_anmelden.gd").start(main)
	await wait(1.0)
	await press("down", 3)
	await shot("01_anmelden", 0.3)
	var l: Node = Nav.top_layer()
	if l != null and l.get("spotify") == true:
		l.get("wirt").call("senden", "laden", { "tab": int(l.get("aktiv")), "url": "https://open.spotify.com/", "nutzer": false })
	await wait(1.4)
	main.goto("music", "fuerdich")
	await shot("02_musik", 1.6)

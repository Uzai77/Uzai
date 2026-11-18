extends "res://tests/probe_base.gd"
## Musik im Grundmodus (ohne eigene Spotify-App) fotografieren: die Bibliothek (aus Spotify am PC
## und dem eigenen Verlauf) und Läuft gerade. Start mit UZAI_DEMO_GRUND=1 und --demo.


func run() -> void:
	Config.set_value("system.music_mode", "spotify")
	await wait(0.6)
	main.goto("music", "verlauf")
	await shot("01_grund_bibliothek", 2.2)
	main.goto("music", "jetzt")
	await shot("02_grund_jetzt", 1.6)

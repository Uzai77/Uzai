extends "res://tests/probe_base.gd"
## Probe für den sozialen Erfolge-Durchgang: drei Bilder – die Übersicht mit Vitrine, ein Spiel
## mit dem Freunde-Stand und das große Pop-up (alle Erfolge eines Spiels). PROBE_ONLY=freunde
## fotografiert zusätzlich den Reiter „Freunde“.
##   UZAI_DATA=<leer> xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path <projekt> --resolution 1920x1080 \
##     -- --demo --no-boot --uzai-script=res://tests/probe_erfolge3.gd --uzai-out=<ordner>


func run() -> void:
	var extra := OS.get_environment("PROBE_ONLY")
	main.goto("achievements", "uebersicht")
	await shot("01_vitrine", 2.2)
	if extra.contains("freunde"):
		main.goto("achievements", "freunde")
		await shot("04_freunde", 1.8)
	# Spiel mit Freunden: wie aus dem Freundesprofil geöffnet (Mira zuerst).
	main.goto("games", "zuletzt")
	await wait(0.6)
	var l = load("res://src/ui/layers/game_achievements.gd").new()
	l.game = Library.get_game("steam:1245620")
	l.compare = Social.steam_friends[0]
	main.open_layer(l)
	await wait(1.6)
	await press("down", 2)
	await shot("02_spiel_freunde", 0.8)
	await press("b")
	await wait(0.5)
	# Der große Moment: Pop-up „komplett“ in Uzai selbst (im Spiel läge es im eigenen Fenster).
	Unlocks.test_popup("komplett")
	await shot("03_popup_komplett", 1.75)

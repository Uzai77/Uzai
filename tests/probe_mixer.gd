extends "res://tests/probe_base.gd"
## Probe „Lautstärkemixer“ (Demo): Guide → System mit „Lautstärke“ und „Mikro stumm“, der Mixer
## über dem Spiel (Pegel ändern, stumm, lauter hebt Stumm auf), Mikro aus mit Hinweis im Guide und
## oben in der Kopfleiste.


func _close_all() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.4)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	main.toggle_guide("system")
	await wait(1.0)
	for c in Nav.focusables(Nav.top_layer()):
		if str(c.get_meta("uz_key", "")) == "a:Lautstärke":
			Nav.focus(c, true)
	await shot("m01_guide_system", 0.6)
	await press("a")
	await shot("m02_mixer", 1.2)
	print("Gewählt: %s" % _focused_title())
	await press("down", 2)
	await press("left", 3)
	await shot("m03_spiel_leiser", 0.8)
	await press("down", 3)
	await press("a")
	await shot("m04_discord_stumm", 0.8)
	await press("right")
	await shot("m05_lauter_hebt_stumm_auf", 0.8)
	await press("up", 6)
	await press("down")
	await press("a")
	await shot("m06_mikro_aus", 1.0)
	print("Mikro aus: %s" % str(Mixer.mic_muted))
	await press("b")
	await shot("m07_guide_mikro_hinweis", 0.8)
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	main.goto("games")
	await shot("m08_kopfleiste_mikro_aus", 1.0)
	Mixer.toggle_mic()
	await shot("m09_mikro_wieder_an", 1.0)
	print("Mikro aus am Ende: %s" % str(Mixer.mic_muted))


func _focused_title() -> String:
	var f := Nav.focused()
	return str(f.get("title")) if f and f.get("title") != null else ""

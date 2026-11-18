extends "res://tests/probe_base.gd"
## Probe zu drei Funden vom PC: Cover im Guide nach Schließen und Wiederöffnen, Reiter System bei
## 100 % und 150 % (auch wenn das Fenster erst nach dem Aufgehen seine Größe bekommt) und Shorts,
## die beim Blättern einrasten. Bilder in --uzai-out.


func _to_tab(id: String) -> void:
	while main._guide.tab != id:
		await press("rb")
		await wait(0.35)


func _cover() -> void:
	var img := Image.create(320, 320, false, Image.FORMAT_RGBA8)
	for y in 320:
		for x in 320:
			img.set_pixel(x, y, Color.from_hsv(0.9 + 0.1 * x / 320.0, 0.7, 0.4 + 0.5 * y / 320.0))
	var p := Config.path("probe_cover.png")
	img.save_png(p)
	Music.now["art"] = p
	Music.updated.emit()
	for round in 2:
		main.toggle_guide()
		await wait(0.8)
		await _to_tab("musik")
		await shot("c%d_musik_cover" % (round + 1), 0.9)
		print("Cover Runde %d: %s" % [round + 1, main._guide._music_art.texture != null])
		main.toggle_guide()
		await wait(0.8)


func _system(tag: String) -> void:
	main.toggle_guide()
	await wait(0.9)
	await _to_tab("system")
	await shot(tag + "_oben", 0.7)
	await press("down", 9)
	await shot(tag + "_unten", 0.7)
	main.toggle_guide()
	await wait(0.8)


func _shorts() -> void:
	main.goto("videos", "shorts")
	await wait(1.4)
	await press("right", 2)
	await press("a")
	await wait(1.6)
	# Langsamer laufen lassen (Xvfb zeichnet nur wenige Bilder je Sekunde), damit das Einrasten
	# auf den Bildern zu sehen ist.
	Engine.time_scale = 0.15
	Nav._fire("down")
	await shot("k1_short_einrasten_a", 0.012)
	await shot("k2_short_einrasten_b", 0.012)
	Engine.time_scale = 1.0
	await shot("k3_short_eingerastet", 0.6)
	print("Short: Index %d" % Video.index)
	await wait(0.3)
	Engine.time_scale = 0.15
	Nav._fire("up")
	await shot("k4_short_zurueck_mitte", 0.015)
	Engine.time_scale = 1.0
	await shot("k5_short_zurueck", 0.6)
	await press("b")
	await wait(0.8)


func run() -> void:
	main.goto("games", "zuletzt")
	await wait(0.6)
	if "--nur-shorts" in OS.get_cmdline_user_args():
		await _shorts()
		return
	await _cover()
	await _system("s100")
	Config.set_value("theme.ui_scale", 1.5)
	await wait(1.5)
	main.goto("games", "zuletzt")
	await wait(0.6)
	await _system("s150")
	# Fenster bekommt erst nach dem Aufgehen seine Größe (über dem Spiel, aus dem Minimieren).
	get_window().size = Vector2i(1920, 1620)
	await wait(0.5)
	main.toggle_guide()
	await wait(0.3)
	get_window().size = Vector2i(1920, 1080)
	await wait(0.6)
	await _to_tab("system")
	await press("down", 9)
	await shot("s150_spaete_groesse_unten", 0.8)
	main.toggle_guide()
	await wait(0.8)
	Config.set_value("theme.ui_scale", 1.0)
	await wait(1.5)
	await _shorts()

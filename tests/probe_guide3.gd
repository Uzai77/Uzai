extends "res://tests/probe_base.gd"
## Probe für den Start des Guides nach Plan „Guide 3“ (docs/PLAN_GUIDE3.md), höchstens fünf Bilder:
## ohne Spiel mit neuen Mitteilungen, Downloads und Freunden online; im Spiel (Steam) mit Erfolgen,
## einer Aufnahme dieses Spiels und der Schnellleiste; im Emulator; der Reiter System. Dazu steht
## im Protokoll, wie lange der Aufbau des Guides dauert (Öffnen bis zum ersten Bild).

var _fake: Control


func _close_guide() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


## Ersatz für das Spiel hinter Uzai: das große Bild des Spiels.
func _fake_game(g: Dictionary) -> void:
	if is_instance_valid(_fake):
		_fake.queue_free()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(pic)
	for kind in ["hero", "screenshot", "cover"]:
		Media.game_texture(g, kind, func(t: Texture2D) -> void:
			if t and pic.texture == null:
				pic.texture = t
		)
	main.add_child(host)
	main.move_child(host, main.background.get_index() + 1)
	_fake = host


## Ein Bildschirmfoto „von eben“ im Ordner der Aufnahmen, damit die Zeile „Aufnahmen“ zu sehen ist.
func _fake_shot(title: String) -> void:
	var dir := Capture.shots_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var t := Time.get_datetime_dict_from_system()
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.35, 0.28, 0.2))
	img.save_png(dir.path_join("%s %04d-%02d-%02d %02d-%02d-%02d.png" % [title, t.year, t.month, t.day, t.hour, t.minute, t.second]))


## Öffnen und messen: der Aufbau selbst (synchron, bis toggle_guide zurückkehrt) und bis zum
## ersten gezeichneten Bild (unter Software-Grafik nur als Vergleich brauchbar).
func _open_timed(tab := "") -> void:
	var t0 := Time.get_ticks_usec()
	main.toggle_guide(tab)
	var t1 := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	print("Guide-Aufbau: %.1f ms synchron, %.1f ms bis zum ersten Bild" % [(t1 - t0) / 1000.0, (Time.get_ticks_usec() - t0) / 1000.0])


## Die Auswahl auf das Element mit diesem Schlüssel (uz_key) im Guide setzen.
func _focus_key(key: String) -> void:
	var g: Control = main._guide
	if g == null:
		return
	for c in Nav.focusables(g):
		if str(c.get_meta("uz_key", "")) == key:
			Nav.focus(c, true)
			return


func run() -> void:
	# Ein Download läuft (Vorführung: Hades), dazu zwei neue Mitteilungen und ein Foto von eben.
	Installs.start(Library.get_game("steam:1145360"))
	main.goto("games", "zuletzt")
	await wait(0.8)
	Toasts.show_toast("Mira ist online", "spielt Elden Ring", "friends")
	Toasts.show_toast("Bildschirmfoto gespeichert", "Elden Ring 2026-10-25.png", "camera")
	_fake_shot("Elden Ring")
	await wait(2.0)
	await _open_timed()
	await shot("01_start_ohne", 1.0)
	await _close_guide()
	# Im Spiel (Steam): Erfolge bekannt, eine Aufnahme des Spiels, Mira spielt mit.
	Launcher.in_game = true
	Launcher.current = Library.get_game("steam:1245620")
	_fake_game(Launcher.current)
	Achievements.for_game(Launcher.current)
	await wait(0.8)
	await _open_timed("spiel")
	await shot("02_start_spiel", 1.0)
	# Schnellleiste: Mikro gewählt (Hinweis unten „Mikro aus“), dann A: Mikro aus.
	_focus_key("qs:mic")
	await wait(0.3)
	await press("a")
	await shot("03_start_spiel_leiste", 0.6)
	await _close_guide()
	# Im Spiel (Emulator)
	var ps2: Array = Library.by_system("ps2")
	if not ps2.is_empty():
		Launcher.current = Library.get_game(str(ps2[0].id))
		_fake_game(Launcher.current)
		Achievements.for_game(Launcher.current)
		await wait(0.8)
		await _open_timed("spiel")
		await shot("04_start_ps2", 1.0)
		await press("lb")
		await shot("05_system", 0.6)
		await _close_guide()
	Launcher.in_game = false
	Launcher.current = {}
	if is_instance_valid(_fake):
		_fake.queue_free()
	await wait(0.3)

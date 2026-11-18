extends "res://tests/probe_base.gd"
## Probe für den Guide als Seitenleiste: Start im Spiel (Steam und PS2), Start ohne Spiel, jeder
## Reiter, „Mehr …“, Aufgehen und die Bedienung mit dem Controller (Fokus von oben nach unten,
## Regler mit links/rechts). Hinter dem Guide steht ein Ersatzbild für das laufende Spiel (unter
## Windows liegt Uzai durchsichtig über dem echten Spiel).

var _fake: Control


func _close_guide() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.12)
	await wait(0.5)


## Ersatz für das Spiel hinter Uzai: das große Bild des Spiels, sonst ein Verlauf in seiner Farbe.
func _fake_game(g: Dictionary) -> void:
	if is_instance_valid(_fake):
		_fake.queue_free()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.32, 0.22, 0.14), Color(0.08, 0.1, 0.16)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 1)
	var base := TextureRect.new()
	base.texture = gt
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(base)
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


func _tabs(prefix: String) -> void:
	for t in ["freunde", "discord", "musik", "system"]:
		main.toggle_guide(t)
		await shot(prefix + t, 1.0)
		await _close_guide()


func run() -> void:
	var nur := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nur="):
			nur = a.substr(6)
		# Größe der Oberfläche (150 %: logisch nur 1280 × 720) – prüft, ob die Leiste passt und rollt.
		if a.begins_with("--skala="):
			Config.set_value("theme.ui_scale", float(a.substr(8)))
			await wait(1.5)
	main.goto("games", "zuletzt")
	await wait(0.8)
	# Ohne Spiel
	main.toggle_guide()
	await shot("auf_a", 0.06)
	await shot("auf_b", 0.12)
	await shot("start_ohne", 0.9)
	if nur == "":
		await press("down")
		await shot("start_ohne_fokus2", 0.3)
		await press("down", 3)
		await shot("start_ohne_fokus5", 0.3)
	await _close_guide()
	if nur == "":
		await _tabs("")
	# Im Spiel: Steam (ein Freund spielt dasselbe)
	Launcher.in_game = true
	Launcher.current = Library.get_game("steam:1245620")
	_fake_game(Launcher.current)
	await wait(0.6)
	main.toggle_guide("spiel")
	await shot("start_spiel", 1.1)
	if nur == "":
		for i in 7:
			await press("down")
			await shot("start_spiel_f%d" % (i + 1), 0.3)
		await press("right")
		await shot("start_spiel_rechts", 0.3)
		var g: Control = main._guide
		if g:
			var GG = load("res://src/ui/components/guide_game.gd")
			GG.open_more(g)
			await shot("mehr", 0.8)
		await _close_guide()
		await _tabs("spiel_")
	else:
		await _close_guide()
	# Im Spiel: PS2 (Emulator, wie im Entwurf)
	var ps2: Array = Library.by_system("ps2")
	if not ps2.is_empty():
		Launcher.current = Library.get_game(str(ps2[0].id))
		_fake_game(Launcher.current)
		await wait(0.6)
		main.toggle_guide("spiel")
		await shot("start_ps2", 1.1)
		await _close_guide()
	Launcher.in_game = false
	Launcher.current = {}
	if is_instance_valid(_fake):
		_fake.queue_free()
	await wait(0.3)

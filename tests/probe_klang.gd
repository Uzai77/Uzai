extends "res://tests/probe_base.gd"
## Probe „Klang, Startanimation, Symbole“ (Roadmap 98, 99, 17): Symbol-Kontaktbogen, die
## Startanimationen je Konsole als Bildfolgen, die Einstellungen unter Aussehen → „Start und
## Klang“ und die Menümusik als kurze Hörproben.
## Nur einige Schritte: UZAI_PROBE_STEPS=symbole,start; Name des Kontaktbogens: UZAI_PROBE_TAG=vorher.

const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const LaunchCard := preload("res://src/ui/layers/launch_card.gd")

var _steps: Array = []


func want(step: String) -> bool:
	return _steps.is_empty() or step in _steps


func run() -> void:
	var st := OS.get_environment("UZAI_PROBE_STEPS")
	if st != "":
		_steps = Array(st.split(","))
	if want("symbole"):
		await _symbole(OS.get_environment("UZAI_PROBE_TAG") if OS.get_environment("UZAI_PROBE_TAG") != "" else "nachher")
	if want("folgen"):
		await _folgen()
	if want("start"):
		await _echter_start()
	if want("einstellungen"):
		await _einstellungen()


## Jede Sequenz als Bildfolge mit 15 Bildern je Sekunde (feste Zeitpunkte, daraus wird ein GIF).
func _folgen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	for sys in SystemIntro.REIHE:
		var si: Control = SystemIntro.new().setup({ "source": "rom", "system": sys })
		si.size = Vector2(1920, 1080)
		layer.add_child(si)
		si.set_process(false)
		var n := int(SystemIntro.DAUER * 15.0) + 1
		var name := "%s%d" % [SystemIntro.sequenz(str(sys)), SystemIntro.variante(str(sys))]
		for i in n:
			si.call("at_time", i / 15.0)
			await shot("folge_%s_%02d" % [name, i], 0.02)
		si.queue_free()
		await wait(0.1)
	layer.queue_free()


## Ein echter Spielstart (ohne Emulator): Spielstart-Karte mit der Animation darüber, in Echtzeit.
func _echter_start() -> void:
	var g := {}
	for gm in Library.visible_games():
		if str(gm.get("source", "")) == "rom" and str(gm.get("system", "")) == "ps1":
			g = gm
			break
	var card: Control = LaunchCard.new()
	card.game = g
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.layer_host.add_child(card)
	print("Start mit ", str(g.get("title", "-")), " → ", SystemIntro.sequenz(str(g.get("system", ""))))
	var si: Control = SystemIntro.new().setup(g)
	si.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(si)
	var t0 := Time.get_ticks_msec()
	for at in [0.25, 0.7, 1.15, 1.8, 2.4, 2.9]:
		while Time.get_ticks_msec() - t0 < int(at * 1000.0):
			await get_tree().process_frame
		print("Intro bei %.2f s: " % at, ("t=%.2f a=%.2f" % [float(si.get("_t")), si.modulate.a]) if is_instance_valid(si) else "fertig")
		await shot("start_ps1_%04d" % int(at * 1000.0), 0.0)
	card.queue_free()
	await wait(0.4)


## Aussehen → Start und Klang: Räumlicher Klang, Menümusik, Musikstück, Startanimation je System.
func _einstellungen() -> void:
	Config.set_value("theme.music", 0.3)
	main.goto("settings", "aussehen")
	await wait(1.4)
	var sv = main.sections["settings"]
	for k in [["Menümusik", "musik"], ["Musikstück", "stueck"], ["Startanimation je System", "intro"]]:
		sv.focus_row("set:aussehen:" + str(k[0]))
		await shot("einstellungen_" + str(k[1]), 1.2)
	await shot("einstellungen_intro_b", 1.1)
	Config.set_value("theme.music", 0.0)


## Alle Symbole in einem Raster (40 px wie in Zeilen), darunter eine Auswahl groß (96 px, so
## scharf wie in 4K bei 200 %).
func _symbole(tag: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("#0d0e10")
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	var head := Label.new()
	head.text = "Symbolsatz – %s (%d Symbole)" % [tag, Icons.P.size()]
	head.position = Vector2(60, 24)
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", Color("#f3f1ec"))
	layer.add_child(head)
	var names: Array = Icons.P.keys()
	var cols := 15
	var cw := 120.0
	var ch := 78.0
	for i in names.size():
		var x := 60.0 + (i % cols) * cw
		var y := 84.0 + floorf(i / float(cols)) * ch
		var tr_ := TextureRect.new()
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.texture = Icons.tex(str(names[i]), 36)
		tr_.position = Vector2(x + (cw - 36.0) * 0.5, y)
		tr_.size = Vector2(36, 36)
		tr_.modulate = Color("#f3f1ec")
		layer.add_child(tr_)
		var l := Label.new()
		l.text = str(names[i])
		l.position = Vector2(x, y + 40)
		l.size = Vector2(cw, 20)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color("#a6a49f"))
		layer.add_child(l)
	var big := ["games", "settings", "music", "friends", "trophy", "play", "pause", "more", "steam", "discord", "controller", "power"]
	var by := 84.0 + ceilf(names.size() / float(cols)) * ch + 10.0
	for i in big.size():
		var tr2 := TextureRect.new()
		tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr2.texture = Icons.tex(big[i], 96)
		tr2.position = Vector2(60.0 + i * 150.0, by)
		tr2.size = Vector2(96, 96)
		tr2.modulate = Color("#f3f1ec")
		layer.add_child(tr2)
	await shot("symbole_" + tag, 0.5)
	layer.queue_free()
	await wait(0.2)

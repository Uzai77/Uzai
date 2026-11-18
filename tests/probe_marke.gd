extends "res://tests/probe_base.gd"
## Probe „Marke“: Zeichen „U-Band“ und Wortmarke UZAI groß (im Material, flach, als App-Symbol),
## Tastensymbol der Guide-Taste, die Startanimation (3D) in ihren Phasen, der Puls der Fuge, die
## Kopfzeile und die Startseite in den vier Akzenten zur Wahl.
## UZAI_MARKE_TEIL: "zeichen", "start", "kopf", "system", "akzente" (mit Komma mehrere) oder leer (alles).

const Logo := preload("res://src/ui/components/uzai_logo.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const AKZENTE := [["lavendel", "#b8a6f0"], ["perlgrau", "#d6d9e4"], ["eisblau", "#8fd0e3"], ["koralle", "#f0997e"]]


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var teile := Array(OS.get_environment("UZAI_MARKE_TEIL").split(",", false))
	var teil := func(t: String) -> bool: return teile.is_empty() or t in teile
	if teil.call("zeichen"):
		await _zeichen()
	if teil.call("start"):
		await _start_phasen()
	if teil.call("kopf"):
		main.goto("games", "zuletzt")
		await shot("kopfzeile", 2.0)
		# Varianten des Zeichens in der Kopfzeile (uzai_logo.gd, STILE).
		var bm: Control = main.get("brand_mark")
		for st in Logo.STILE:
			bm.set("stil", st)
			var kachel: bool = st == "kachel"
			var h := 40.0 if kachel else Logo.KOPF_H
			bm.custom_minimum_size = Vector2(Logo.zeichen_breite(h, kachel), h)
			bm.queue_redraw()
			await shot("kopf_%s" % st, 0.5)
		bm.set("stil", "kopf")
		bm.custom_minimum_size = Vector2(Logo.zeichen_breite(Logo.KOPF_H, Logo.KOPF_STIL == "kachel"), Logo.KOPF_H)
		bm.queue_redraw()
		await wait(0.3)
		# Hover (Maus über dem Zeichen).
		bm.call("_hover_auf", 1.0)
		await shot("kopf_hover", 0.4)
		bm.call("_hover_auf", 0.0)
		Config.set_value("theme.accent", "#8fd0e3")
		await wait(1.4)
		main.goto("games", "zuletzt")
		await shot("kopfzeile_eisblau", 1.6)
		Config.set_value("theme.accent", "")
	if teil.call("system"):
		await _systeme()
	if teil.call("akzente"):
		await _akzente()


func _layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	return layer


func _zeichen() -> void:
	var layer := _layer()
	# Links das Zeichen im Material und darunter die Wortmarke, daneben flach im Akzent; rechts das
	# App-Symbol aus icon.svg in drei Größen, das Zeichen mit Wortmarke (SVG) und die Guide-Taste.
	var mark: Control = Logo.new()
	mark.position = Vector2(120, 110)
	mark.size = Vector2(520.0, 520.0)
	layer.add_child(mark)
	var word: Control = Logo.new()
	word.set("mode", "wort")
	word.position = Vector2(120, 760)
	word.size = Vector2(Logo.word_width(120.0), 120.0)
	layer.add_child(word)
	var flach: Control = Logo.new()
	flach.set("mode", "flach")
	flach.position = Vector2(660, 430)
	flach.size = Vector2(Logo.zeichen_breite(200.0, false), 200.0)
	layer.add_child(flach)
	var klein: Control = Logo.new()
	klein.position = Vector2(660, 300)
	klein.set("stil", "kopf")
	klein.size = Vector2(Logo.zeichen_breite(Logo.KOPF_H, false), Logo.KOPF_H)
	layer.add_child(klein)
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var x := 1000.0
	for px in [384, 128, 48]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(px) / 256.0)
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.position = Vector2(x, 110)
		layer.add_child(tr)
		x += px + 40
	var lock := Image.new()
	lock.load_svg_from_string(FileAccess.get_file_as_string("res://assets/uzai_logo.svg"), 0.3)
	var lt := TextureRect.new()
	lt.texture = ImageTexture.create_from_image(lock)
	lt.position = Vector2(1000, 620)
	layer.add_child(lt)
	var g: Control = Glyph.new()
	g.cmd = "guide"
	g.px = 64
	g.position = Vector2(1700, 300)
	layer.add_child(g)
	await shot("zeichen_gross", 0.8)
	# Guide-Signatur: ein Licht läuft einmal durch die Fuge (Mitte des Laufs).
	mark.call("pulse")
	word.call("pulse")
	await shot("zeichen_puls", Logo.PULSE_S * 0.45)
	layer.queue_free()
	await wait(0.2)


func _start_phasen() -> void:
	var layer := _layer()
	var boot = load("res://src/ui/boot.gd").new()
	boot.preview = true
	boot.setup("voll")
	layer.add_child(boot)
	await wait(0.3)
	boot.set_process(false)
	for ph in [[0.6, "1_linie"], [0.95, "2_baender"], [1.25, "3_kachel"], [1.75, "4_name"], [3.0, "5_fertig"]]:
		boot.seek(float(ph[0]))
		await shot("start_%s" % ph[1], 0.25)
	boot.queue_free()
	# Ruhige Fassung (Animationen reduzieren): ohne 3D, Zeichen und Name blenden nur ein.
	Config.set_value("theme.reduce_motion", true)
	var ruhig = load("res://src/ui/boot.gd").new()
	ruhig.preview = true
	ruhig.setup("voll")
	layer.add_child(ruhig)
	await wait(0.2)
	ruhig.set_process(false)
	ruhig.seek(1.5)
	await shot("start_6_ruhig", 0.25)
	Config.set_value("theme.reduce_motion", false)
	layer.queue_free()
	await wait(0.2)


## Die 3D-Startanimationen je System (system_buehne.gd) kurz vor und nach dem Höhepunkt.
func _systeme() -> void:
	var layer := _layer()
	for id in ["ps2", "gc", "ps1", "n64", "switch"]:
		var si: Control = load("res://src/ui/components/system_intro.gd").new().setup({ "source": "rom", "system": id })
		si.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(si)
		si.set_process(false)
		await wait(0.3)
		for t in [0.9, 1.7]:
			si.call("at_time", t)
			await shot("system_%s_%d" % [id, int(t * 10)], 0.25)
		si.queue_free()
	layer.queue_free()
	await wait(0.2)


func _akzente() -> void:
	main.goto("games", "zuletzt")
	await wait(1.2)
	for a in AKZENTE:
		Config.set_value("theme.accent", str(a[1]))
		await wait(1.4)
		main.goto("games", "zuletzt")
		await shot("akzent_%s" % a[0], 1.6)
	Config.set_value("theme.accent", "")

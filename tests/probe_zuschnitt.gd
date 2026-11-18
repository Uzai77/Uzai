extends "res://tests/probe_base.gd"
## Kluge Bildzuschnitte und Farbabstimmung (Punkt 97): Vorher (stumpf mittig, rohe Farbe) und
## Nachher (Zuschnitt.put, Zuschnitt.accent) nebeneinander, mit gerenderten Testbildern; dazu
## Startseite, Videos und Filme zum Gegencheck, dass die Karten wie gewohnt aussehen.

const Z := preload("res://src/core/zuschnitt.gd")
const MediaS := preload("res://src/core/media.gd")
const U := preload("res://src/ui/u.gd")


func run() -> void:
	var hero := await _render(Vector2i(1200, 390), "STARFALL", Vector2(60, 40), 64, Vector2(0.84, 0.55), Color(0.08, 0.1, 0.18), Color(0.25, 0.12, 0.3))
	var cover := await _render(Vector2i(400, 600), "NEON\nRIDERS", Vector2(40, 30), 70, Vector2(0.5, 0.72), Color(0.05, 0.12, 0.2), Color(0.3, 0.05, 0.12))
	var thumb := await _render(Vector2i(640, 360), "", Vector2.ZERO, 0, Vector2(0.18, 0.5), Color(0.12, 0.12, 0.12), Color(0.2, 0.18, 0.15))
	var shot_img := await _render(Vector2i(1280, 720), "LEVEL 3", Vector2(900, 600), 48, Vector2(0.3, 0.4), Color(0.1, 0.25, 0.12), Color(0.02, 0.06, 0.04))
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	get_tree().root.add_child(page)
	var y := 40.0
	_title(page, "Vorher: stumpf mittig", Vector2(60, 6))
	_title(page, "Nachher: kluger Zuschnitt", Vector2(1000, 6))
	for row in [[hero, Vector2(300, 300), "Hero breit → quadratische Karte"], [cover, Vector2(460, 215), "Hochkant-Cover → breite Kachel"],
			[thumb, Vector2(140, 249), "Video 16:9 → Short hochkant"], [shot_img, Vector2(420, 150), "Szene → Hintergrundstreifen"]]:
		var img: Image = row[0]
		var box: Vector2 = row[1]
		var plain := ImageTexture.create_from_image(img)
		var smart := ImageTexture.create_from_image(img)
		smart.set_meta("uz_look", MediaS.look_of(img))
		_tile(page, plain, Vector2(60, y), box, false)
		_tile(page, smart, Vector2(1000, y), box, true)
		# Das ganze Bild klein daneben, damit man sieht, woraus geschnitten wurde.
		var full := TextureRect.new()
		full.texture = plain
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		full.position = Vector2(60 + box.x + 20, y)
		full.size = Vector2(1000 - 60 - box.x - 40, box.y)
		page.add_child(full)
		_title(page, str(row[2]), Vector2(1000 + box.x + 20, y), "s")
		y += box.y + 18.0
	await shot("01_zuschnitt_vorher_nachher", 0.6)
	page.queue_free()
	await _colors()
	main.goto("games")
	await shot("03_start", 1.5)
	main.goto("videos")
	await shot("04_videos", 2.5)
	main.goto("movies")
	await shot("05_filme", 2.5)
	main.goto("shop")
	await shot("06_shop", 3.0)


## Akzentfarben roh und abgestimmt, mit weißer Schrift darauf.
func _colors() -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	get_tree().root.add_child(page)
	_title(page, "Akzentfarbe roh (oben) und abgestimmt (unten)", Vector2(60, 20))
	var cols := [Color(1, 1, 0), Color(0, 1, 0.2), Color(0, 0, 1), Color(0.15, 0.0, 0.4), Color(1, 0.1, 0.6), Color(0.05, 0.3, 0.05), Color(1, 0.55, 0.0),
			Color(0.6, 0.9, 1.0)]
	for i in cols.size():
		for k in 2:
			var c: Color = cols[i] if k == 0 else Z.accent(cols[i])
			var r := ColorRect.new()
			r.color = c
			r.position = Vector2(60 + i * 225, 100 + k * 240)
			r.size = Vector2(205, 200)
			page.add_child(r)
			var l := U.label("Spielen", "l", "text", "bold")
			l.add_theme_color_override("font_color", Color.WHITE)
			l.position = r.position + Vector2(24, 70)
			page.add_child(l)
			# Wie die Lichter im Raum: dieselbe Farbe als weicher Schein auf dunklem Grund.
			var g := ColorRect.new()
			g.color = Color(c, 0.3)
			g.position = r.position + Vector2(0, 470 - k * 0)
			g.size = Vector2(205, 60)
			page.add_child(g)
	await shot("02_farben", 0.6)
	page.queue_free()


func _tile(page: Control, t: Texture2D, at: Vector2, box: Vector2, smart: bool) -> void:
	var clip := Panel.new()
	clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.position = at
	clip.size = box
	page.add_child(clip)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = box
	clip.add_child(tr)
	if smart:
		Z.put(tr, t)
	else:
		tr.texture = t


func _title(page: Control, s: String, at: Vector2, sz := "m") -> void:
	var l := U.label(s, sz, "text", "bold")
	l.position = at
	page.add_child(l)


## Ein Testbild rendern: Verlauf, ein Motiv mit vielen Kanten (Figur, Ringe) bei subj (Anteile),
## und auf Wunsch ein großer Schriftzug.
func _render(size: Vector2i, text: String, text_at: Vector2, fs: int, subj: Vector2, c0: Color, c1: Color) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var g := Gradient.new()
	g.colors = PackedColorArray([c0, c1])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	var bgr := TextureRect.new()
	bgr.texture = gt
	bgr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgr.size = Vector2(size)
	vp.add_child(bgr)
	var fig := _Figure.new()
	fig.size = Vector2(size)
	fig.at = Vector2(size) * subj
	fig.r = minf(size.x, size.y) * 0.3
	vp.add_child(fig)
	if text != "":
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.position = text_at
		vp.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


class _Figure extends Control:
	var at := Vector2.ZERO
	var r := 100.0

	func _draw() -> void:
		for i in 6:
			draw_arc(at, r * (1.0 - i * 0.14), 0, TAU, 64, Color(1, 0.8 - i * 0.1, 0.3 + i * 0.1), 5.0, true)
		draw_circle(at + Vector2(0, -r * 0.35), r * 0.18, Color(0.95, 0.85, 0.75))
		draw_rect(Rect2(at + Vector2(-r * 0.15, -r * 0.15), Vector2(r * 0.3, r * 0.6)), Color(0.2, 0.5, 0.9))
		for k in 8:
			draw_line(at + Vector2(-r, -r + k * r * 0.25), at + Vector2(-r * 0.6, -r + k * r * 0.25), Color(1, 1, 1, 0.9), 3.0)

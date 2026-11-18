extends Control
## Ordner einer Nuvio-Sammlung als Kachel (wie in Nuvio TV): Titelbild aus dem Ordner, sonst sein
## Emoji, sonst der Name groß. Form wie in Nuvio eingestellt (quadratisch, Hochformat, Querformat).
## Der Name steht darunter, außer er ist in Nuvio ausgeblendet. Gewählt bleibt die Kachel gleich
## groß; ein Rahmen zeigt die Auswahl. A öffnet den Ordner.

signal chosen(folder: Dictionary)
signal focused_folder(folder: Dictionary)

const U := preload("res://src/ui/u.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const SIZES := { "SQUARE": Vector2(260, 260), "POSTER": Vector2(228, 342), "LANDSCAPE": Vector2(448, 252) }
const LABEL_H := 52.0

var folder: Dictionary = {}
var nav_ud_cb: Callable
var _frame: Panel
var _ring: Control
var _focus_t := 0.0
var _tw: Tween


static func tile_size(shape: String) -> Vector2:
	return SIZES.get(shape.to_upper(), SIZES.SQUARE)


static func row_height(folders: Array) -> float:
	var h := 0.0
	for f in folders:
		h = maxf(h, tile_size(str(f.get("shape", ""))).y + (LABEL_H if has_label(f) else 0.0))
	return h


## Name unter der Kachel: nur mit Bild oder Emoji (ohne steht er groß in der Kachel) und wenn er
## in Nuvio nicht ausgeblendet ist.
static func has_label(f: Dictionary) -> bool:
	return not bool(f.get("hide_title", false)) and (str(f.get("cover", "")) != "" or str(f.get("emoji", "")) != "")


func setup(f: Dictionary) -> Control:
	folder = f
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sz := tile_size(str(folder.get("shape", "")))
	custom_minimum_size = Vector2(sz.x, sz.y + (LABEL_H if has_label(folder) else 0.0))
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = sz
	U.clip_round(_frame, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	add_child(_frame)
	var title := str(folder.get("title", ""))
	var cover := str(folder.get("cover", ""))
	var emoji := str(folder.get("emoji", ""))
	# Ohne Bild: Emoji bzw. Name groß in der Mitte (wie Nuvio).
	var mid := CenterContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size = sz
	_frame.add_child(mid)
	var big := U.label(emoji if emoji != "" else title, "xxl" if emoji != "" else "l", "text", "title", emoji == "")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if emoji == "":
		big.custom_minimum_size.x = sz.x - 36.0
	mid.add_child(big)
	if cover != "":
		var img := TextureRect.new()
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.size = sz
		img.modulate.a = 0.0
		_frame.add_child(img)
		var wi: WeakRef = weakref(img)
		var wb: WeakRef = weakref(big)
		Art.load_image(cover, int(sz.x * Media.px_scale()), func(t: Texture2D) -> void:
			var r: TextureRect = wi.get_ref()
			if r == null or t == null:
				return
			r.texture = t
			var b: Label = wb.get_ref()
			if b:
				b.visible = false
			U.tw(r, "uz_fade").tween_property(r, "modulate:a", 1.0, U.T_BASE)
		)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = sz
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	if has_label(folder):
		var l := U.label(title, "m", "text", "ui_bold")
		U.ellipsis(l)
		l.position = Vector2(4, sz.y + 12)
		l.size = Vector2(sz.x - 8, LABEL_H - 12)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	set_meta("uz_hint_a", "Öffnen")
	focus_entered.connect(func() -> void: _on_focus(true))
	focus_exited.connect(func() -> void: _on_focus(false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func activate() -> void:
	chosen.emit(folder)


func nav_ud(d: int) -> bool:
	return nav_ud_cb.is_valid() and bool(nav_ud_cb.call(d))


## In der Reihe: an den Enden anschlagen statt schräg in eine andere Reihe zu springen.
func nav_lr(d: int) -> bool:
	if not nav_ud_cb.is_valid() or get_parent() == null:
		return false
	var i := get_index()
	if (d < 0 and i == 0) or (d > 0 and i == get_parent().get_child_count() - 1):
		Nav._bump(self, "left" if d < 0 else "right")
		return true
	return false


func _on_focus(on: bool) -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_method(func(v: float) -> void:
		_focus_t = v
		if is_instance_valid(_ring):
			_ring.queue_redraw()
	, _focus_t, 1.0 if on else 0.0, U.FOCUS_IN if on else U.FOCUS_OUT)
	if on:
		focused_folder.emit(folder)


func _draw_ring() -> void:
	if _focus_t <= 0.01:
		return
	var ring := UzTheme.focus_ring(_focus_t)
	ring.shadow_size = 0
	_ring.draw_style_box(ring, Rect2(Vector2.ZERO, _ring.size))

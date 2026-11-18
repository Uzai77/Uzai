extends Control
## Bildschirm während des Starts und solange ein Spiel läuft (falls Uzai sichtbar bleibt):
## das Bild des Spiels als ruhiger Hintergrund, unten links System, Titel und Zustand. Beim
## Starten läuft unter dem Zustand eine feine Linie, danach zeigt die Guide-Taste, was geht.

const U := preload("res://src/ui/u.gd")

var game: Dictionary = {}
var _status: Label
var _title: Label
var _sub: Control
var _bg: TextureRect
var _sweep: Control
var _running := false
var _t0 := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base := ColorRect.new()
	base.color = UzTheme.col("bg")
	U.full_rect(base)
	add_child(base)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(1, 1, 1, 0.0)
	U.full_rect(_bg)
	add_child(_bg)
	var shade := ColorRect.new()
	shade.color = Color(UzTheme.col("bg"), 0.72)
	U.full_rect(shade)
	add_child(shade)
	# Unten links dunkler, damit die Schrift auf jedem Bild ruhig steht.
	var low := TextureRect.new()
	low.texture = U.fade_texture(true, true)
	low.modulate = Color(UzTheme.col("bg"), 0.85)
	low.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	low.stretch_mode = TextureRect.STRETCH_SCALE
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low.anchor_right = 1.0
	low.anchor_top = 0.45
	low.anchor_bottom = 1.0
	add_child(low)
	var m := U.margin(120, 0, 120, 140)
	U.full_rect(m)
	add_child(m)
	var col := U.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(col)
	var sys := Config.system(str(game.get("system", "")))
	var where := str(sys.get("name", Library.store_name(game, false, "PC")))
	var wl := U.label(where, "m", "muted", "medium")
	col.add_child(wl)
	_title = U.label(Library.display_title(game), "hero", "text", "title", true)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.custom_minimum_size = Vector2(1400, 0)
	_title.max_lines_visible = 2
	col.add_child(_title)
	_status = U.label("Wird gestartet …", "l", "accent", "medium")
	col.add_child(_status)
	_sweep = _Sweep.new()
	col.add_child(_sweep)
	_sub = U.hbox(12)
	_sub.modulate.a = 0.0
	col.add_child(_sub)
	Media.game_texture(game, "hero", func(t: Texture2D) -> void:
		if t and is_instance_valid(_bg):
			_bg.texture = t
			create_tween().tween_property(_bg, "modulate:a", 0.55, 0.6)
	)
	_t0 = Time.get_ticks_msec()
	# Angaben steigen nacheinander kurz auf.
	var i := 0
	for c: Control in [wl, _title, _status]:
		c.modulate.a = 0.0
		var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, U.T_ENTER).set_delay(0.08 + i * U.STAGGER * 2)
		i += 1


func set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


func set_running() -> void:
	_running = true
	_status.text = "Läuft"
	if is_instance_valid(_sweep):
		_sweep.create_tween().tween_property(_sweep, "modulate:a", 0.0, U.T_BASE)
	U.clear(_sub)
	_sub.add_child(U.glyph("guide", 30))
	var l := U.label("Guide: Musik, Freunde, Erfolge, Spielstand, Beenden", "m", "muted", "medium")
	l.clip_text = false
	_sub.add_child(l)
	_sub.create_tween().tween_property(_sub, "modulate:a", 1.0, U.T_MOVE)


func _process(_dt: float) -> void:
	if _running and Engine.get_process_frames() % 60 == 0:
		var s := Launcher.elapsed()
		var mins := floori(s / 60.0)
		_status.text = "Läuft seit %d:%02d Std." % [floori(s / 3600.0), mins % 60] if s >= 3600 else "Läuft seit %d Min." % maxi(1, mins)


## Feine Linie unter „Wird gestartet …“: ein heller Abschnitt wandert ruhig hin und her.
class _Sweep extends Control:
	var _t := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(420, 4)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.1), 2), Rect2(0, 0, w, 3))
		var p := 0.5 - 0.5 * cos(_t * 2.2)
		var seg := w * 0.28
		draw_style_box(UzTheme.box(UzTheme.col("accent", 0.9), 2), Rect2((w - seg) * p, 0, seg, 3))

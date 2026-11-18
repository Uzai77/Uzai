extends "res://src/ui/layers/layer.gd"
## Kurze Tour nach der Einrichtung (Punkt 52): vier ruhige Hinweise auf einer Karte unten über
## der Startseite – je eine Taste mit ihrem Symbol (passend zu Controller oder Tastatur) und ein
## Satz dazu. A weiter, B beendet sofort. Kommt einmal von selbst (E.tour_due), danach unter
## Einstellungen → System → „Kurze Tour“. Die Hinweise selbst stehen in einrichtung.gd (E.TOUR).

const E := preload("res://src/core/einrichtung.gd")
const SELF := "res://src/ui/layers/tour.gd"
const WIDTH := 880.0
const PLATE := 132.0
const SLOT_H := 172.0           ## Höhe für Zeichen und Text (gleich für alle Hinweise: die Karte springt nicht)

const Main := preload("res://src/main.gd")
var main: Main
var _i := 0
var _panel: PanelContainer
var _slot: Control              ## wechselnder Teil: Zeichen, Titel, Text
var _dots: _Dots
var _go: Button
var _busy := false


## Nach der Einrichtung: einmal, wenn sie fällig ist – nach delay Sekunden, wenn die Startseite
## hereingekommen ist. Liegt dann etwas anderes offen (oder läuft ein Spiel), bleibt es dabei:
## Die Tour gibt es unter Einstellungen.
static func offer(m: Main, st: Dictionary, delay := 0.9) -> void:
	if not E.tour_due(st, Library.demo):
		return
	await m.get_tree().create_timer(delay).timeout
	if not is_instance_valid(m) or Launcher.in_game or Nav.top_layer() != null:
		return
	open_for(m)


static func open_for(m: Main) -> Control:
	Config.set_value("einrichtung.tour", true)
	var t = load(SELF).new()
	t.main = m
	m.open_layer(t)
	return t


func build() -> void:
	# Die Startseite bleibt dahinter zu sehen: Die Hinweise gehören zu ihr.
	dim = 0.5
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Tour beenden")
	_panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 40
	sb.content_margin_bottom = 36
	UzTheme.lift(sb, 3)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH * 0.5
	_panel.offset_right = WIDTH * 0.5
	_panel.offset_bottom = -150
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var col := U.vbox(30)
	_panel.add_child(col)
	_slot = Control.new()
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.custom_minimum_size = Vector2(0, SLOT_H)
	col.add_child(_slot)
	var foot := U.hbox(14)
	col.add_child(foot)
	_dots = _Dots.new()
	_dots.count = E.TOUR.size()
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_dots)
	foot.add_child(U.spacer())
	var stop := U.button("Tour beenden", "", "flat")
	stop.custom_minimum_size = Vector2(0, 56)
	stop.pressed.connect(func() -> void:
		Sfx.play("back")
		close()
	)
	foot.add_child(stop)
	_go = U.button("Weiter", "chevron_right", "primary")
	_go.custom_minimum_size = Vector2(220, 56)
	_go.set_meta("uz_default", true)
	_go.pressed.connect(_next)
	foot.add_child(_go)
	_show(0, 0)
	# Steigt von unten leicht auf (wie ein Hinweis, nicht wie ein Dialog).
	_panel.modulate.a = 0.0
	_panel.position.y += 28
	var tw := U.im_tempo(_panel.create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, U.T_ENTER).set_delay(0.08)
	tw.tween_property(_panel, "position:y", _panel.position.y - 28, U.T_ENTER + 0.12).set_delay(0.08)


func _first_focus() -> Control:
	return _go


func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(_panel):
		tw.set_parallel(true)
		tw.tween_property(_panel, "position:y", _panel.position.y + 18, U.T_FAST)


func _next() -> void:
	if _busy:
		return
	var to := E.tour_next(_i, E.TOUR.size(), "a")
	if to < 0:
		close()
		return
	_show(to, 1)


## Hinweis i zeigen. dir 0: sofort (beim Öffnen), 1: der alte gleitet nach links hinaus, der neue
## kommt von rechts – wie die Schritte der Einrichtung, nur kürzer.
func _show(i: int, dir: int) -> void:
	_i = i
	var last := i == E.TOUR.size() - 1
	_go.text = "Fertig" if last else "Weiter"
	_go.set_meta("uz_hint_a", _go.text)
	_dots.set_cur(i, dir != 0)
	var old: Control = _slot.get_child(0) if _slot.get_child_count() > 0 else null
	if old == null:
		_slot.add_child(_page(E.TOUR[i]))
		return
	_busy = true
	var out := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	out.tween_property(old, "modulate:a", 0.0, U.T_FAST)
	out.tween_property(old, "position:x", -40.0 * dir, U.T_FAST)
	await out.finished
	old.queue_free()
	var page := _page(E.TOUR[i])
	_slot.add_child(page)
	page.modulate.a = 0.0
	page.position.x = 50.0 * dir
	var plate: Control = page.get_child(0)
	plate.pivot_offset = Vector2(PLATE, PLATE) * 0.5
	plate.scale = Vector2.ONE * 0.86
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "modulate:a", 1.0, U.T_ENTER)
	tw.tween_property(page, "position:x", 0.0, U.T_ENTER + 0.06)
	tw.tween_property(plate, "scale", Vector2.ONE, U.T_ENTER + 0.1).set_trans(Tween.TRANS_CUBIC)
	_busy = false
	Nav.focus_moved.emit(Nav.focused())


## Zeichen links, rechts „2 von 4“, Titel und ein Satz.
func _page(h: Dictionary) -> Control:
	var row := U.hbox(36)
	U.full_rect(row)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := _Plate.new()
	plate.custom_minimum_size = Vector2(PLATE, PLATE)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if str(h.get("key", "")) != "":
		var g := U.glyph(str(h.key), 64)
		plate.add_child(g)
	else:
		plate.add_child(U.icon(str(h.get("icon", "info")), 44, "text"))
	row.add_child(plate)
	var tc := U.vbox(8)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(tc)
	tc.add_child(U.label("%d von %d" % [_i + 1, E.TOUR.size()], "s", "faint", "medium"))
	tc.add_child(U.label(str(h.title), "xl", "text", "black"))
	var t := U.label(str(h.text), "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(WIDTH - 96.0 - PLATE - 36.0, 0)
	tc.add_child(t)
	return row


## Weiche Scheibe, das Symbol (Taste oder Zeichen) mittig darauf.
class _Plate extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_center)
		# Das Tastensymbol ändert seine Breite mit dem Gerät (Tastatur: „G“, Controller: Kreis).
		for c in get_children():
			if c is Control:
				(c as Control).resized.connect(_center)
		_center()

	func _center() -> void:
		for c in get_children():
			if c is Control:
				var cc := c as Control
				cc.position = (size - cc.get_combined_minimum_size()) * 0.5

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, UzTheme.col("accent", 0.1), true, -1.0, true)
		draw_arc(size * 0.5, r - 1.0, 0, TAU, 64, UzTheme.col("accent", 0.22), 1.5, true)


## Fortschritt: kleine Punkte, der aktuelle als längerer Strich in der Akzentfarbe.
class _Dots extends Control:
	var count := 4
	var cur := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(count * 22 + 22, 10)

	func set_cur(i: int, animate := true) -> void:
		if not animate or not is_inside_tree():
			cur = float(i)
			queue_redraw()
			return
		create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT).tween_method(func(v: float) -> void:
			cur = v
			queue_redraw()
		, cur, float(i), 0.36)

	func _draw() -> void:
		var x := 0.0
		var cy := size.y * 0.5
		for i in count:
			var t := clampf(1.0 - absf(cur - i), 0.0, 1.0)
			var w := lerpf(8.0, 30.0, t)
			var col := UzTheme.col("text", 0.18).lerp(UzTheme.col("accent"), t)
			draw_style_box(UzTheme.box(col, 999), Rect2(x, cy - 4, w, 8))
			x += w + 12.0

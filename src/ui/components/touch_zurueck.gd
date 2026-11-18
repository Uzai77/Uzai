extends Control
## Zurück für Touch (Punkt 64): ein runder Glasknopf links neben dem Schriftzug in der Kopfleiste,
## nur solange mit dem Finger bedient wird und B gerade etwas tut (unten steht dann „Zurück“).
## Tippen ist B – derselbe Weg wie die Taste. Liegt über allen Ebenen (Guide, Seitenleisten,
## Dialoge), damit es immer einen Weg hinaus gibt. Mit Controller, Tastatur und Maus unsichtbar.

const U := preload("res://src/ui/u.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")

const DURCHMESSER := 52.0

var _an := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(DURCHMESSER, DURCHMESSER)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	position = Vector2(UzTheme.GUTTER - DURCHMESSER - 20.0, 30.0)
	modulate.a = 0.0
	visible = false
	set_meta("uz_f", 0.0)
	Nav.device_changed.connect(func(_k: String) -> void: _pruefen())
	Nav.focus_moved.connect(func(_c: Control) -> void: _pruefen.call_deferred())
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_tippen()
	)
	_pruefen.call_deferred()


func _pruefen() -> void:
	if not is_inside_tree():
		return
	var an := Nav.device == "touch" and HintBar.collect().any(func(h: Array) -> bool: return str(h[0]) == "b")
	if an == _an:
		return
	_an = an
	if an:
		visible = true
	var tw := U.tw(self, "uz_zurueck", Tween.TRANS_QUART).set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0 if an else 0.0, U.T_BASE if an else U.T_FAST)
	tw.tween_property(self, "scale", Vector2.ONE if an else Vector2(0.92, 0.92), U.T_BASE).from(Vector2(0.92, 0.92) if an else Vector2.ONE)
	if not an:
		tw.chain().tween_callback(func() -> void: visible = _an)


func _tippen() -> void:
	# Kurz hell wie eine Auswahl, dann B (die Ebene schließt bzw. es geht eine Stufe hoch).
	var tw := U.tw(self, "uz_druck")
	tw.tween_method(_f, 1.0, 0.0, U.T_EXIT)
	Nav._fire("b")


func _f(v: float) -> void:
	set_meta("uz_f", v)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f: float = get_meta("uz_f", 0.0)
	draw_circle(r.get_center(), DURCHMESSER * 0.5, UzTheme.col("glass_hi"), true, -1.0, true)
	if f > 0.01:
		UzTheme.draw_selection(self, r, 999, f)
	var px := 26
	draw_texture_rect(Icons.tex("chevron_left", px), Rect2((size - Vector2(px, px)) * 0.5 - Vector2(1, 0), Vector2(px, px)), false,
		UzTheme.col("text").lerp(UzTheme.col("on_focus"), f))

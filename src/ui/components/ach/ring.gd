extends Control
## Fortschritt als Ring: Gold auf feiner Spur, runde Enden. Füllt sich beim Erscheinen einmal
## weich auf; die Zahl in der Mitte steht von Anfang an fest (nichts zählt hoch).

const U := preload("res://src/ui/u.gd")

var value := 0.0             ## 0…1
var px := 160
var thick := 12.0
var number := ""             ## groß in der Mitte („69“)
var unit := ""               ## klein daneben („%“)
var caption := ""            ## klein darunter
var number_size := "xl"
var instant := false         ## steht gleich voll da (die Seite baut sich nur neu, der Stand ist alt)
var _t := 0.0


func setup(v: float, size_px := 160, thickness := 12.0, num := "", u := "", cap := "") -> Control:
	value = clampf(v, 0.0, 1.0)
	px = size_px
	thick = thickness
	number = num
	unit = u
	caption = cap
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if instant or U.reduziert():
		_t = 1.0
		queue_redraw()
		return
	var wr: WeakRef = weakref(self)
	create_tween().tween_method(func(v: float) -> void:
		var me: Control = wr.get_ref()
		if me:
			me.set("_t", v)
			me.queue_redraw()
	, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT).set_delay(0.12)


func _draw() -> void:
	var c := Vector2(px, px) * 0.5
	var r := px * 0.5 - thick * 0.5 - 1.0
	draw_arc(c, r, 0.0, TAU, 96, UzTheme.col("text", 0.09), thick, true)
	var v := value * _t
	if v > 0.003:
		var col := UzTheme.col("gold") if value >= 0.999 else UzTheme.col("accent")
		var a0 := -PI * 0.5
		var a1 := a0 + TAU * v
		draw_arc(c, r, a0, a1, maxi(6, int(96.0 * v)), col, thick, true)
		draw_circle(c + Vector2(cos(a0), sin(a0)) * r, thick * 0.5, col)
		draw_circle(c + Vector2(cos(a1), sin(a1)) * r, thick * 0.5, col)
	if number == "":
		return
	var f := UzTheme.display("black")
	var fs := UzTheme.size(number_size)
	var fu := UzTheme.font("bold")
	var fus := int(fs * 0.5)
	var nw := f.get_string_size(tr(number), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var uw := fu.get_string_size(tr(unit), HORIZONTAL_ALIGNMENT_LEFT, -1, fus).x + (4.0 if unit != "" else 0.0)
	var cap_h := 0.0 if caption == "" else 22.0
	var base := c.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5 - 4.0 - cap_h * 0.5
	var x := c.x - (nw + uw) * 0.5
	draw_string(f, Vector2(x, base), tr(number), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
	if unit != "":
		draw_string(fu, Vector2(x + nw + 4.0, base), tr(unit), HORIZONTAL_ALIGNMENT_LEFT, -1, fus, UzTheme.col("muted"))
	if caption != "":
		var fc := UzTheme.font("medium")
		var fcs := UzTheme.size("xs")
		var cw := fc.get_string_size(tr(caption), HORIZONTAL_ALIGNMENT_LEFT, -1, fcs).x
		draw_string(fc, Vector2(c.x - cw * 0.5, base + cap_h + 6.0), tr(caption), HORIZONTAL_ALIGNMENT_LEFT, -1, fcs, UzTheme.col("muted"))

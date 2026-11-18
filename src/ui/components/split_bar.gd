extends Control
## Eine Leiste, aufgeteilt nach Anteilen (zum Beispiel Spielzeit pro System), mit kleinen
## Lücken zwischen den Stücken.

var parts: Array = []          ## [{ value, color }]
var _t := 0.0


func setup(p: Array, height := 16) -> Control:
	parts = p
	custom_minimum_size = Vector2(0, height)
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	create_tween().tween_method(func(v: float) -> void:
		_t = v
		queue_redraw()
	, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.2)


func _draw() -> void:
	var total := 0.0
	for p in parts:
		total += float(p.value)
	if total <= 0.0:
		return
	var gap := 4.0
	var w := size.x * _t - gap * (parts.size() - 1)
	var x := 0.0
	var r := int(size.y * 0.5)
	for i in parts.size():
		var seg := maxf(4.0, w * float(parts[i].value) / total)
		var sb := StyleBoxFlat.new()
		sb.bg_color = parts[i].color
		sb.anti_aliasing = true
		# Nur die äußeren Enden ganz rund, innen nur leicht.
		sb.corner_radius_top_left = r if i == 0 else 3
		sb.corner_radius_bottom_left = r if i == 0 else 3
		sb.corner_radius_top_right = r if i == parts.size() - 1 else 3
		sb.corner_radius_bottom_right = r if i == parts.size() - 1 else 3
		draw_style_box(sb, Rect2(x, 0, seg, size.y))
		x += seg + gap

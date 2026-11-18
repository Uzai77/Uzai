extends HBoxContainer
## Zeile mit feiner Linie darunter (das Register der Quellen auf der Startseite).

var inset := 16


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(inset, size.y - 1, size.x - inset, 1), UzTheme.col("stroke"))

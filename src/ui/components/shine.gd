extends Control
## Ein Lichtstreif, der einmal schräg über ein Bild zieht, wenn es gewählt wird. Liegt als
## letztes Kind in der Bildmaske (dadurch folgt er den runden Ecken).

const U := preload("res://src/ui/u.gd")

var _tw: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	set_meta("uz_shine", 1.0)


func play(delay := 0.06) -> void:
	if _tw:
		_tw.kill()
	set_meta("uz_shine", 0.0)
	_tw = create_tween()
	_tw.tween_interval(delay)
	_tw.tween_method(func(v: float) -> void:
		set_meta("uz_shine", v)
		queue_redraw()
	, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _draw() -> void:
	U.draw_shine(self, Rect2(Vector2.ZERO, size))

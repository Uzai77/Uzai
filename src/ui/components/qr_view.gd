extends Control
## Zeigt einen QR-Code: dunkle Punkte auf Weiß mit Ruhezone, damit jedes Handy ihn liest.
## Die drei Ortungsaugen sind weich gerundet (Handys erkennen sie genauso), die Datenpunkte
## bleiben scharfe Quadrate. Beim ersten Zeigen baut sich der Code in 0,45 s schräg auf.
## Aufruf unverändert: QrView.new().setup(text, größe_px). Lange Inhalte (großer Code, gut
## 100 ms Rechenzeit) mit setup_async: die weiße Fläche steht sofort, der Code baut sich auf,
## sobald er im Hintergrund fertig ist.

const QR := preload("res://src/core/qr.gd")
const INK := Color(0.055, 0.06, 0.07)

var text := ""
var px := 360
var _rows: Array = []
var _reveal := 1.0
var _tw: Tween
var _job: Thread


func setup(t: String, size_px := 360) -> Control:
	# Ein neuer Code für einen schon sichtbaren (z. B. erneuerte Steam-Anmeldung) erscheint sofort:
	# Wer gerade scannt, soll nicht ins Leere zielen.
	var was_shown := is_inside_tree() and not _rows.is_empty()
	text = t
	px = size_px
	_rows = QR.encode(t, "M")
	custom_minimum_size = Vector2(px, px)
	_reveal = 1.0 if was_shown else 0.0
	queue_redraw()
	return self


func setup_async(t: String, size_px := 360) -> Control:
	text = t
	px = size_px
	_rows = []
	_reveal = 0.0
	custom_minimum_size = Vector2(px, px)
	_job = Thread.new()
	_job.start(func() -> Array: return QR.encode(t, "M"))
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_job != null)
	if _reveal < 1.0 and not _rows.is_empty():
		_start_reveal()


func _process(_dt: float) -> void:
	if _job == null or _job.is_alive():
		return
	_rows = _job.wait_to_finish()
	_job = null
	set_process(false)
	_start_reveal()


func _exit_tree() -> void:
	if _job != null:
		_job.wait_to_finish()
		_job = null


func _start_reveal() -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tw := _tw
	tw.tween_method(func(v: float) -> void:
		_reveal = v
		queue_redraw()
	, _reveal, 1.0, 0.45)


func _draw() -> void:
	var s := Vector2(px, px)
	draw_rect(Rect2(Vector2.ZERO, s), Color.WHITE)
	if _rows.is_empty():
		return
	var n := _rows.size()
	var cell := floorf(px / float(n + 8))
	var off := floorf((px - cell * n) * 0.5)
	for y in n:
		var row: PackedByteArray = _rows[y]
		for x in n:
			if row[x] != 1 or _in_eye(x, y, n):
				continue
			var a := _alpha(x, y, n)
			if a > 0.0:
				draw_rect(Rect2(off + x * cell, off + y * cell, cell, cell), Color(INK, a))
	for e in [Vector2i(0, 0), Vector2i(n - 7, 0), Vector2i(0, n - 7)]:
		_eye(Vector2(off + e.x * cell, off + e.y * cell), cell, _alpha(e.x + 3, e.y + 3, n))


## Aufbau von links oben nach rechts unten.
func _alpha(x: int, y: int, n: int) -> float:
	if _reveal >= 1.0:
		return 1.0
	var d := float(x + y) / float(2 * n)
	return clampf((_reveal * 1.35 - d) / 0.35, 0.0, 1.0)


static func _in_eye(x: int, y: int, n: int) -> bool:
	return (x < 7 and y < 7) or (x >= n - 7 and y < 7) or (x < 7 and y >= n - 7)


## Ein Ortungsauge: Ring aus 7×7 Modulen und Kern aus 3×3, beides weich gerundet.
func _eye(at: Vector2, cell: float, a: float) -> void:
	if a <= 0.0:
		return
	var outer := Rect2(at, Vector2(cell, cell) * 7.0)
	var ink := Color(INK, a)
	draw_style_box(_rounded(ink, cell * 2.0), outer)
	draw_style_box(_rounded(Color.WHITE, cell * 1.2), outer.grow(-cell))
	draw_style_box(_rounded(ink, cell * 1.1), Rect2(at + Vector2(cell, cell) * 2.0, Vector2(cell, cell) * 3.0))


static func _rounded(c: Color, r: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(r))
	sb.anti_aliasing = true
	return sb

extends Control
## Modus-Leiste oben in der Mitte (wie Leben/Bauen bei Sims und inZOI): drei Wörter – Leben, Bauen,
## Foto – auf einer schmalen matten Leiste, das gewählte hell auf gehobener Fläche mit dem Strich im
## Akzent darunter (er gleitet beim Wechsel). Links die View-Taste, die weiterschaltet. Was der
## Modus kann, steht nicht hier, sondern am Ding (Schild, Kontextmenü) und in der Tastenzeile.
## Beim Laufen blendet sie aus wie die Hinweise; Maus und Finger: ein Wort ist zugleich der Knopf.

signal gewaehlt(id: String)

const U := preload("res://src/ui/u.gd")
const Stil := preload("res://src/room/zimmer_stil.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")

const MODI := [["leben", "Leben"], ["bauen", "Bauen"], ["foto", "Foto"]]
const OBEN := 44.0
const HOEHE := 52.0
const SEG := 150.0

var _wahl := 0
var _strich := -1.0            ## gleitende Lage des Strichs (Index als Kommazahl)
var _sicht := 1.0
var _sicht_ziel := 1.0
var _rects: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	U.full_rect(self)
	set_process(false)
	Nav.device_changed.connect(func(_k: String) -> void: queue_redraw())


func setzen(id: String) -> void:
	var i := index_von(id)
	if i == _wahl and _strich >= 0.0:
		return
	_wahl = i
	if _strich < 0.0:
		_strich = float(i)
	set_process(true)


static func index_von(id: String) -> int:
	for i in MODI.size():
		if str(MODI[i][0]) == id:
			return i
	return 0


## Nächster Modus reihum (View-Taste).
static func naechster(id: String) -> String:
	return str(MODI[(index_von(id) + 1) % MODI.size()][0])


func zeigen(an: bool) -> void:
	var z := 1.0 if an else 0.0
	if is_equal_approx(z, _sicht_ziel):
		return
	_sicht_ziel = z
	set_process(true)


func _process(dt: float) -> void:
	_strich = lerpf(_strich, float(_wahl), 1.0 - exp(-dt * 14.0))
	if absf(_strich - _wahl) < 0.002:
		_strich = float(_wahl)
	_sicht = move_toward(_sicht, _sicht_ziel, dt / U.T_BASE)
	queue_redraw()
	if is_equal_approx(_strich, float(_wahl)) and is_equal_approx(_sicht, _sicht_ziel):
		set_process(false)


func _breite() -> float:
	return 64.0 + SEG * MODI.size()


func _draw() -> void:
	_rects.clear()
	if _sicht <= 0.01:
		return
	var a := _sicht * _sicht * (3.0 - 2.0 * _sicht)
	var w := _breite()
	var x0 := roundf((size.x - w) * 0.5)
	var r := Rect2(x0, OBEN, w, HOEHE)
	Stil.flaeche(self, r, a)
	var gset := Nav.glyph_set()
	var gs := Glyph.size_for("view", 24, gset)
	Glyph.paint(self, "view", 24, Rect2(Vector2(x0 + 20.0, OBEN + (HOEHE - gs.y) * 0.5), gs), gset, 0.75, a)
	var f := UzTheme.font("ui_bold")
	var fs := UzTheme.size("s")
	var sx := x0 + 64.0
	# Gehobene Fläche unter dem gewählten Segment (gleitet mit dem Strich).
	var gx := sx + _strich * SEG
	draw_rect(Rect2(gx + 4.0, OBEN + 5.0, SEG - 8.0, HOEHE - 10.0), Color(Stil.FLAECHE_HOCH, a))
	for i in MODI.size():
		var t := tr(str(MODI[i][1]))
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var k := clampf(1.0 - absf(_strich - i), 0.0, 1.0)
		var c := Stil.LEISE.lerp(Stil.TINTE, k)
		var tx := sx + i * SEG + (SEG - tw) * 0.5
		draw_string(f, Vector2(tx, OBEN + HOEHE * 0.5 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c, a))
		_rects.append(Rect2(sx + i * SEG, OBEN, SEG, HOEHE))
	# Strich im Akzent unter dem gewählten Wort.
	var sw := 36.0
	draw_rect(Rect2(gx + (SEG - sw) * 0.5, OBEN + HOEHE - 9.0, sw, 3.0), Color(UzTheme.col("accent"), a))


func _has_point(p: Vector2) -> bool:
	if _sicht < 0.5:
		return false
	for r in _rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in _rects.size():
			if (_rects[i] as Rect2).has_point((e as InputEventMouseButton).position):
				accept_event()
				gewaehlt.emit(str(MODI[i][0]))
				return

extends Control
## Kontextmenü am Objekt (wie das Objekt-Menü bei Sims und inZOI): eine kurze Liste direkt neben dem
## Möbel, an dem sie hängt – eine Haarlinie führt vom Ding zur Liste, sie wandert mit, wenn sich die
## Kamera bewegt. Oben leise der Name, darunter höchstens sechs Handlungen; eine Zeile kann rechts
## einen Wert tragen (Farbe, Fernseher-Art), ←/→ oder A ändert ihn dann an Ort und Stelle.
## Steuerkreuz wählt, A tut, B schließt. Maus: Zeile unter dem Zeiger, Klick wie A.
##
## Einträge: { id, text, tun: Callable, wert: Callable → String (freiwillig), blaettern: Callable(d)
##   (freiwillig, dann bleibt die Liste offen), gefahr: bool, hinweis: Wort für A (freiwillig),
##   roh: Text nicht übersetzen (Namen aus der Bibliothek) }

signal zu

const U := preload("res://src/ui/u.gd")
const Stil := preload("res://src/room/zimmer_stil.gd")

const BREITE := 380.0
const KOPF := 46.0
const ZEILE := 52.0
const ABSTAND := 54.0          ## vom Ding bis zur Liste

var _titel := ""
var _eintraege: Array = []
var _anker: Callable
var _sel := 0
var _sel_f := 0.0
var _an := 0.0
var _offen := false
var _punkt := Vector2(-1, -1)  ## Ankerpunkt auf dem Schirm (gleitet)
var _rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	U.full_rect(self)
	visible = false
	set_process(false)


func oeffnen(titel: String, eintraege: Array, anker: Callable) -> void:
	_titel = titel
	_eintraege = eintraege.slice(0, 6)
	_anker = anker
	_sel = 0
	_sel_f = 0.0
	_punkt = Vector2(-1, -1)
	_offen = true
	visible = true
	set_process(true)
	var tw := U.tw(self, "uz_kontext", Tween.TRANS_QUART)
	tw.tween_property(self, "_an", 1.0, U.T_BASE)


func schliessen() -> void:
	if not _offen:
		return
	_offen = false
	var tw := U.tw(self, "uz_kontext", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.tween_property(self, "_an", 0.0, U.T_FAST)
	tw.tween_callback(func() -> void:
		if not _offen:
			visible = false
			set_process(false))
	zu.emit()


func offen() -> bool:
	return _offen


func eintrag() -> Dictionary:
	return _eintraege[_sel] if _sel >= 0 and _sel < _eintraege.size() else {}


func schritt(cmd: String) -> void:
	match cmd:
		"up", "down":
			var n := clampi(_sel + (-1 if cmd == "up" else 1), 0, _eintraege.size() - 1)
			if n == _sel:
				Sfx.play("bump")
				return
			_sel = n
			Sfx.play("move")
		"left", "right":
			var e := eintrag()
			if e.get("blaettern") is Callable:
				(e.blaettern as Callable).call(-1 if cmd == "left" else 1)
				queue_redraw()
			else:
				Sfx.play("bump")


## A tut, B schließt. Immer true (die Liste nimmt alle Tasten, solange sie offen ist).
func taste(cmd: String) -> bool:
	match cmd:
		"a":
			var e := eintrag()
			if e.is_empty():
				return true
			if e.get("blaettern") is Callable:
				(e.blaettern as Callable).call(1)
				queue_redraw()
				return true
			schliessen()
			Sfx.play("select")
			if e.get("tun") is Callable:
				(e.tun as Callable).call()
		"b":
			Sfx.play("back")
			schliessen()
	return true


## Was A gerade tut (für die Tastenzeile).
func hinweis_a() -> String:
	var e := eintrag()
	if e.is_empty():
		return ""
	if e.get("blaettern") is Callable:
		return "Ändern"
	return str(e.get("hinweis", "Wählen"))


func _process(dt: float) -> void:
	var p: Variant = _anker.call() if _anker.is_valid() else null
	if p is Vector2:
		_punkt = p if _punkt.x < 0.0 else _punkt.lerp(p, 1.0 - exp(-dt * 14.0))
	elif _punkt.x < 0.0:
		_punkt = size * 0.5
	_sel_f = lerpf(_sel_f, float(_sel), 1.0 - exp(-dt * 20.0))
	queue_redraw()


func _draw() -> void:
	if _an <= 0.01 or _punkt.x < 0.0:
		return
	var a := _an
	var h := KOPF + ZEILE * _eintraege.size() + 10.0
	# Rechts vom Ding, wenn Platz ist, sonst links; senkrecht ein Stück darüber, nie unter die Leisten.
	var rechts := _punkt.x + ABSTAND + BREITE < size.x - UzTheme.GUTTER * 0.5
	var x := _punkt.x + ABSTAND if rechts else _punkt.x - ABSTAND - BREITE
	var y := clampf(_punkt.y - h * 0.35, 120.0, size.y - 170.0 - h)
	x += (1.0 - a) * (-10.0 if rechts else 10.0)
	_rect = Rect2(roundf(x), roundf(y), BREITE, h)
	# Haarlinie vom Ding zur Liste, am Ding ein kleiner eckiger Punkt.
	var kante := Vector2(_rect.position.x if rechts else _rect.end.x, clampf(_punkt.y, _rect.position.y + 20.0, _rect.end.y - 20.0))
	draw_line(_punkt, kante, Color(Stil.TINTE, 0.5 * a), 1.5, true)
	draw_rect(Rect2(_punkt - Vector2(4, 4), Vector2(8, 8)), Color(Stil.TINTE, 0.9 * a))
	Stil.flaeche(self, _rect, a)
	var fk := UzTheme.font("ui_bold")
	var ft := UzTheme.font("medium")
	var fs := UzTheme.size("s")
	var fc := UzTheme.size("cap")
	Stil.text(self, fk, Vector2(_rect.position.x + 22.0, _rect.position.y + 30.0), _titel.to_upper(), fc, Color(Stil.LEISE, a), BREITE - 44.0)
	var oy := _rect.position.y + KOPF
	var sel_r := Rect2(_rect.position.x + 8.0, oy + _sel_f * ZEILE + 3.0, BREITE - 16.0, ZEILE - 6.0)
	UzTheme.draw_selection(self, sel_r, -1, a, 0.0)
	for i in _eintraege.size():
		var e: Dictionary = _eintraege[i]
		var ry := oy + i * ZEILE
		var gef := bool(e.get("gefahr", false))
		var c := UzTheme.col("danger_text") if gef else Stil.TINTE
		var txt := str(e.text) if bool(e.get("roh", false)) else tr(str(e.text))
		draw_string(ft, Vector2(_rect.position.x + 24.0, ry + ZEILE * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT,
				BREITE - 150.0, fs, Color(c, a))
		if e.get("wert") is Callable:
			var w := str((e.wert as Callable).call())
			var ww := ft.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var wx := _rect.end.x - 24.0 - ww
			draw_string(ft, Vector2(wx, ry + ZEILE * 0.5 + fs * 0.36), w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Stil.LEISE, a))
			if e.get("blaettern") is Callable and i == _sel:
				_pfeil(Vector2(wx - 16.0, ry + ZEILE * 0.5), -1, a)
				_pfeil(Vector2(_rect.end.x - 12.0, ry + ZEILE * 0.5), 1, a)


func _pfeil(m: Vector2, d: int, a: float) -> void:
	var s := 5.0
	draw_colored_polygon(PackedVector2Array([m + Vector2(s * d, 0), m + Vector2(-s * d, -s), m + Vector2(-s * d, s)]), Color(Stil.LEISE, a))


# --- Maus und Finger ----------------------------------------------------------------------------

func _has_point(p: Vector2) -> bool:
	return _offen


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouse):
		return
	var p := (e as InputEventMouse).position
	var i := int(floor((p.y - _rect.position.y - KOPF) / ZEILE))
	var drin := _rect.has_point(p) and i >= 0 and i < _eintraege.size()
	if e is InputEventMouseMotion and drin and i != _sel:
		_sel = i
		Sfx.play("move")
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if drin:
			_sel = i
			Nav._fire("a")
		else:
			Nav._fire("b")

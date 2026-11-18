extends Control
## Die Kopfleiste ruht, wenn man unten arbeitet (main.gd _build). Vier Stufen (STUFEN):
## - „leiste“: Der Cursor steht oben (Reiter, Lupe, Profilbild). Alles ganz da, an den Enden der
##   Reiter stehen leise LT und RT (Meta uz_bumper) – nur jetzt, denn nur jetzt helfen sie.
## - „oben“: Der Cursor steht in den Unterbereichen. Leiste ganz da, LT und RT weg.
## - „inhalt“: Der Cursor ist im Inhalt (Regal, Shop, Listen). Reiter und Status treten eine Spur
##   zurück; der Punkt im Akzent zeigt weiter den Bereich.
## - „tief“: Die Liste unter dem Cursor ist gerollt (ab SCHWELLE Pixel). Die Leiste tritt weiter
##   zurück – der Inhalt hat das Licht.
## Zurück nach oben kommt sie im Antwort-Takt (T_ANTWORT), zurücktreten dauert T_ORT; das
## Zeichen bleibt immer, wie es ist. Eine offene Ebene (Seitenleiste, Dialog, Guide) ändert
## nichts: Die Leiste behält die letzte Stufe. Die Zuordnung (stufe) prüft tests/logic_kopf.gd.
## Ein unsichtbares Control ohne Größe: So räumt main._build es beim Neuaufbau mit auf.

const U := preload("res://src/ui/u.gd")

## Deckkraft je Stufe: Reiter (leiste), Status rechts, Tastenhinweise LT/RT (tasten).
const STUFEN := {
	"leiste": { "leiste": 1.0, "status": 1.0, "tasten": 1.0 },
	"oben": { "leiste": 1.0, "status": 1.0, "tasten": 0.0 },
	"inhalt": { "leiste": 0.74, "status": 0.82, "tasten": 0.0 },
	"tief": { "leiste": 0.5, "status": 0.58, "tasten": 0.0 },
}
## Ab so vielen Pixeln gilt eine Liste als gerollt.
const SCHWELLE := 48.0

var kopf: Control        ## die ganze Kopfleiste (main.top_bar)
var strip: Control       ## die Reiter (main.tabs_box)
var status: Control      ## der Status rechts (kopf_status.gd)
var chips: Control       ## die Unterbereiche (main.chips_box)
var inhalt: Control      ## der Inhalt (main.view_host)
var aktuell := "leiste"
var _nachsehen := 0


func setup(k: Control, s: Control, st: Control, ch: Control, inh: Control) -> Node:
	kopf = k
	strip = s
	status = st
	chips = ch
	inhalt = inh
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2.ZERO
	size = Vector2.ZERO
	Nav.focus_moved.connect(_on_focus)
	anwenden.call_deferred(false)


## Welche Stufe gilt, wenn der Cursor hier steht.
static func stufe(in_leiste: bool, in_chips: bool, in_inhalt: bool, gerollt: bool) -> String:
	if in_leiste:
		return "leiste"
	if in_chips:
		return "oben"
	if in_inhalt:
		return "tief" if gerollt else "inhalt"
	return "oben"


## Deckkraft der Tastenhinweise in der aktuellen Stufe (für neu gebaute LT/RT, main._bumper).
func tasten_alpha() -> float:
	return float((STUFEN[aktuell] as Dictionary).tasten)


func _on_focus(c: Control) -> void:
	if c == null or not is_instance_valid(c) or Nav.top_layer() != null:
		return
	anwenden(true)
	# Die Liste rollt dem Cursor erst nach (Feder): nach dem Weg noch einmal nachsehen.
	_nachsehen += 1
	var n := _nachsehen
	get_tree().create_timer(U.T_RAUM).timeout.connect(func() -> void:
		if n == _nachsehen and is_inside_tree() and Nav.top_layer() == null:
			anwenden(true)
	)


## Stufe aus der Lage des Cursors lesen und setzen. animate = false: sofort (nach einem Neubau).
func anwenden(animate: bool) -> void:
	var f := Nav.focused()
	var in_kopf := f != null and is_instance_valid(kopf) and kopf.is_ancestor_of(f)
	var in_chips := f != null and is_instance_valid(chips) and chips.is_ancestor_of(f)
	var in_inhalt := f != null and is_instance_valid(inhalt) and inhalt.is_ancestor_of(f)
	var neu := stufe(in_kopf, in_chips, in_inhalt, in_inhalt and gerollt(f, inhalt))
	setzen(neu, animate)


## Liegt c in einer Liste, die hoch/runter rollt und schon gerollt ist?
static func gerollt(c: Control, bis: Control) -> bool:
	var n := c.get_parent() if c else null
	while n and n != bis:
		if n is ScrollContainer and (n as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return float((n as ScrollContainer).scroll_vertical) >= SCHWELLE
		n = n.get_parent()
	return false


func setzen(neu: String, animate: bool) -> void:
	if not STUFEN.has(neu):
		return
	var war := aktuell
	aktuell = neu
	var w: Dictionary = STUFEN[neu]
	# Heller werden ist Antwort auf den Druck nach oben; zurücktreten darf gemächlicher sein.
	var heller: bool = float(w.leiste) >= float((STUFEN[war] as Dictionary).leiste)
	var dauer := U.T_ANTWORT if heller else U.T_ORT
	_blende(strip, float(w.leiste), dauer, animate, "uz_ruhe")
	_blende(status, float(w.status), dauer, animate, "uz_ruhe")
	if is_instance_valid(strip):
		for ch in strip.get_children():
			if ch is CanvasItem and ch.has_meta("uz_bumper"):
				_blende(ch, float(w.tasten), dauer, animate, "uz_ruhe")


static func _blende(n: CanvasItem, a: float, dauer: float, animate: bool, key: String) -> void:
	if not is_instance_valid(n):
		return
	if not animate or not n.is_inside_tree() or absf(n.modulate.a - a) < 0.005:
		U.stop(n, key)
		n.modulate.a = a
		return
	U.ankommen(n, dauer, key).tween_property(n, "modulate:a", a, dauer)

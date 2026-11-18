extends Control
## Schmaler Fortschrittsbalken (Erfolge, Musik, Lautstärke, Downloads).
## Der Balken springt nicht von Abfrage zu Abfrage: Er folgt neuen Werten als kritisch gedämpfte
## Feder (U.spring_step) und läuft nie ein Stück zurück. Kleine Rückschritte (eine Abfrage kam
## etwas früher als die Rechnung dazwischen) bleiben stehen; ein echter Rückschritt (neuer Titel,
## leiser gestellt) setzt ihn sofort. Bei „Animationen reduzieren“ steht er gleich am Ziel.

const U := preload("res://src/ui/u.gd")
## So viel darf ein neuer Wert unter dem gezeigten liegen, ohne dass der Balken zurückspringt.
const RUECK_TOLERANZ := 0.02

var value := 0.0                 ## Ziel (0 … 1)
var color_name := "accent"
var height := 6.0
var shown := 0.0                 ## gezeigter Stand (folgt value)
var _vel := 0.0


func setup(v: float, col := "accent", h := 6.0, w := 0.0) -> Control:
	value = clampf(v, 0.0, 1.0)
	shown = value
	color_name = col
	height = h
	custom_minimum_size = Vector2(w, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	return self


func set_value(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	var r := folge(shown, nv, U.reduziert() or not is_visible_in_tree())
	value = nv
	if r == nv:
		shown = nv
		_vel = 0.0
		set_process(false)
		queue_redraw()
	elif r == shown and nv < shown:
		# Kleiner Rückschritt: stehen bleiben.
		value = shown
	else:
		set_process(true)


## Wohin der Balken bei einem neuen Wert ziel geht: sofort (Rückgabe ziel) bei einem echten
## Rückschritt oder ohne Bewegung; stehen bleiben (Rückgabe jetzt) bei einem kleinen Rückschritt;
## sonst folgt er (Rückgabe -1). Ohne Fenster testbar.
static func folge(jetzt: float, ziel: float, sofort: bool) -> float:
	if sofort or ziel < jetzt - RUECK_TOLERANZ:
		return ziel
	if ziel < jetzt:
		return jetzt
	return -1.0


func _process(dt: float) -> void:
	var st := U.spring_step(shown, _vel, value, dt)
	shown = minf(st.x, value) if value >= shown else st.x
	_vel = st.y
	if absf(value - shown) < 0.0005 and absf(_vel) < 0.01:
		shown = value
		_vel = 0.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var y := (size.y - height) * 0.5
	var r := Rect2(0, y, size.x, height)
	draw_style_box(UzTheme.box(UzTheme.col("line"), int(height * 0.5)), r)
	if shown > 0.0:
		var fill := Rect2(0, y, maxf(height, size.x * shown), height)
		draw_style_box(UzTheme.box(UzTheme.col(color_name), int(height * 0.5)), fill)

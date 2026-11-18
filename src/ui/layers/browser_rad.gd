extends "res://src/ui/layers/layer.gd"
## Kontextrad des Uzai-Browsers (A halten auf einem Ziel): bis zu sechs Handlungen als Pillen im Kreis
## um das Ziel, je nach Art – Link: Öffnen, Neuer Tab, Ans Handy; Video: Abspielen, Vollbild,
## Fernbedienung. Steuerkreuz oder Stick wählen in die Richtung, A tut es, B schließt.
## optionen = [[symbol, Text, Callable], …]

const Liste := preload("res://src/ui/components/liste.gd")

var mitte := Vector2(960, 540)
var optionen: Array = []
const RADIUS := 170.0

var _knoepfe: Array = []


func build() -> void:
	dim = 0.38
	if is_instance_valid(_scrim):
		_scrim.color = Color(UzTheme.col("bg"), dim)
	var n := optionen.size()
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var m := mitte.clamp(Vector2(RADIUS + 160, RADIUS + 60), vp - Vector2(RADIUS + 160, RADIUS + 60))
	var kern := Kern.new()
	kern.position = m - Vector2(26, 26)
	add_child(kern)
	for i in n:
		var o: Array = optionen[i]
		var b := Liste.knopf(str(o[1]), str(o[0]), "")
		var cb: Callable = o[2]
		b.pressed.connect(func() -> void:
			close()
			cb.call())
		add_child(b)
		# Erst nach dem Aufbau kennt der Knopf seine Größe: dann um den Kern legen (oben beginnend).
		var winkel := -PI * 0.5 + TAU * float(i) / maxf(1.0, n)
		var ziel := m + Vector2(cos(winkel), sin(winkel)) * RADIUS
		b.set_meta("uz_rad_ziel", ziel)
		b.size = b.get_combined_minimum_size()
		b.position = ziel - b.size * 0.5
		b.resized.connect(func() -> void: b.position = (b.get_meta("uz_rad_ziel") as Vector2) - b.size * 0.5)
		b.set_meta("uz_key", "browser:rad:%d" % i)
		_knoepfe.append(b)
	set_meta("uz_hint_b", "Schließen")


func _first_focus() -> Control:
	return _knoepfe[0] if not _knoepfe.is_empty() else null


## Richtung → der Knopf, der in diese Richtung am besten passt (Kreis statt Raster).
func nav_dir(dir: String) -> bool:
	var cur := Nav.focused()
	var von: Vector2 = cur.get_meta("uz_rad_ziel") if cur and cur.has_meta("uz_rad_ziel") else mitte
	var d := { "up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT }[dir] as Vector2
	var best: Control = null
	var best_s := INF
	for b in _knoepfe:
		if b == cur:
			continue
		var w: Vector2 = (b.get_meta("uz_rad_ziel") as Vector2) - von
		var l := w.length()
		if l < 1.0:
			continue
		var cos_w := w.normalized().dot(d)
		if cos_w < 0.25:
			continue
		var s := l * (2.0 - cos_w)
		if s < best_s:
			best_s = s
			best = b
	if best:
		Nav.focus(best)
	else:
		Sfx.play("bump")
	return true


## Der Kern in der Mitte: das Zeichen von Uzai im Kleinen – ein Punkt im Akzent mit Licht darum.
class Kern extends Control:
	func _ready() -> void:
		size = Vector2(52, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 26.0, Color(UzTheme.col("accent"), 0.14))
		draw_circle(c, 14.0, UzTheme.col("accent"))

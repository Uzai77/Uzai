extends Control
## Platzhalter beim Laden (Punkt 93), überall derselbe: ruhige Flächen in der Form des späteren
## Inhalts (Cover, Kachel mit zwei Zeilen, Person, Titelzeile …). Ein heller Schimmer wandert
## langsam von links nach rechts; die Welle hängt an der Lage auf dem Bildschirm, alle Platzhalter
## einer Seite schimmern also wie eine Fläche – kein Pulsieren je Teil, keine Punkte, kein Kreisel.
## Kommt das Ergebnis, blendet es an derselben Stelle in derselben Größe weich ein (swap/fade_out):
## nichts springt. Leichter Modus: nur die ruhige Fläche, ohne Schimmer (zeichnet nicht je Bild).
##
## Formen in Punkten der Fläche: { r: Rect2, rad: Eckenradius (-1: wie Cover), a: Deckkraft-Faktor,
## circle: Kreis, fx: Breite höchstens dieser Anteil der Fläche (Zeilen, die mitwachsen),
## farbe: gemerkte Grundfarbe des Bilds (Media.grundfarbe) – dann ist die Fläche deckend in dieser
## Farbe und das Bild „entwickelt“ sich darüber; der Schimmer liegt nur leise darauf }.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")

const PERIOD := 1.6        ## Sekunden je Welle
const BASE_A := 0.05       ## Deckkraft der ruhigen Fläche …
const GLOW_A := 0.035      ## … und zusätzlich im hellsten Teil des Schimmers
const SCREEN_W := 1920.0
const GROUP := "uz_platzhalter"
## Ruhe (Plan „Gefühl“, Abschnitt 4): Der Schimmer heißt „es lädt gerade“. Liegt ein Platzhalter
## länger als so viele Sekunden, lädt dort nichts mehr sichtbar – er wird zur ruhigen Fläche.
const RUHE_NACH_S := 8.0

var shapes: Array = []
var _seit := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_to_group(GROUP)
	_seit = Time.get_ticks_msec()


func _process(_dt: float) -> void:
	if Leicht.active or not is_visible_in_tree():
		return
	if ruht():
		set_process(false)
	queue_redraw()


## Schimmert der Platzhalter nicht mehr (schon zu lange da)?
func ruht() -> bool:
	return Time.get_ticks_msec() - _seit > int(RUHE_NACH_S * 1000.0)


func _draw() -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0 / PERIOD
	var ruhig := ruht()
	for s in shapes:
		var r: Rect2 = s.r
		var fx := float(s.get("fx", 0.0))
		if fx > 0.0:
			r.size.x = maxf(8.0, minf(r.size.x, size.x * fx) - float(s.get("dx", 0.0)))
		var col := UzTheme.col("text", float(s.get("a", 1.0)) * (BASE_A if ruhig else alpha_at(global_position.x + r.get_center().x, t)))
		var fc: Variant = s.get("farbe")
		if fc is Color:
			var rad0 := int(s.get("rad", -1))
			draw_style_box(UzTheme.box(grund(fc as Color), UzTheme.r_cover() if rad0 < 0 else rad0), r)
			col.a = maxf(0.0, col.a - BASE_A)
		if bool(s.get("circle", false)):
			draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.5, col, true, -1.0, true)
		else:
			var rad := int(s.get("rad", -1))
			draw_style_box(UzTheme.box(col, UzTheme.r_cover() if rad < 0 else rad), r)


## Deckkraft an einer Stelle des Bildschirms (x in Punkten) zur Zeit t (in Wellen). Ohne Fenster
## testbar (tests/logic_vorladen.gd): immer zwischen BASE_A und BASE_A + GLOW_A.
static func alpha_at(x: float, t: float) -> float:
	if Leicht.active:
		return BASE_A
	var w := 0.5 + 0.5 * sin(TAU * (t - x / SCREEN_W * 0.8))
	return BASE_A + GLOW_A * w * w


# --- Formen ------------------------------------------------------------------------------------

static func _make() -> Control:
	return (load("res://src/ui/components/skeleton.gd") as GDScript).new()


## Eine Fläche (Rechteck mit Radius, -1: wie Cover) oder ein Kreis – wie das frühere
## ach/skeleton.gd, das die Erfolge-Seite für ihre Form nutzt.
func setup(sz: Vector2, r := -1, circle := false) -> Control:
	custom_minimum_size = sz
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	shapes = [{ "r": Rect2(Vector2.ZERO, sz), "rad": UzTheme.radius if r < 0 and not circle else r, "circle": circle }]
	return self


## Ein Cover bzw. Bild, das die ganze Fläche füllt (in einer Karte, die schon ihre Größe hat).
## farbe: die gemerkte Grundfarbe des Bilds (Media.grundfarbe, Color oder null) – dann zeigt der
## Platzhalter sofort diese Fläche statt des neutralen Graus.
static func fill(rad := -1, farbe: Variant = null) -> Control:
	var s = _make()
	U.full_rect(s)
	var f: Variant = farbe if farbe is Color else null
	s.shapes = [{ "r": Rect2(Vector2.ZERO, s.size), "rad": rad, "farbe": f }]
	s.resized.connect(func() -> void:
		s.shapes = [{ "r": Rect2(Vector2.ZERO, s.size), "rad": rad, "farbe": f }]
	)
	return s


## Die Grundfarbe als ruhige Fläche: etwas zurückgenommen (das Bild ist meist kontrastreicher
## als sein Mittel), deckend, damit unter dem Platzhalter nichts durchscheint.
static func grund(c: Color) -> Color:
	return Color(c.darkened(0.12), 1.0)


## Eine Reihe Karten (Laden eines Bereichs): weiter rechts blasser – „gleich mehr“, kein Gitter.
static func cards(count: int, card: Vector2, gap := 24.0) -> Control:
	var s = _make()
	for i in count:
		s.shapes.append({ "r": Rect2(Vector2(i * (card.x + gap), 0), card), "a": 1.0 - i * 0.16 })
	s.custom_minimum_size = Vector2(count * (card.x + gap) - gap, card.y)
	s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return s


## Kachel: quadratisches Bild, darunter zwei Zeilen (Musik). Höhe wie die echte Kachel.
static func tile(side: float, below := 76.0) -> Control:
	var s = _make()
	s.shapes = [
		{ "r": Rect2(0, 0, side, side) },
		{ "r": Rect2(2, side + 18, side * 0.7, 16), "rad": 6 },
		{ "r": Rect2(2, side + 46, side * 0.45, 13), "rad": 6, "a": 0.7 },
	]
	s.custom_minimum_size = Vector2(side, side + below)
	return s


## Person: rundes Bild, Name und Zustand (Freundesliste).
static func person(h := 84.0) -> Control:
	var s = _make()
	s.shapes = [
		{ "r": Rect2(14, h * 0.5 - 30, 60, 60), "circle": true },
		{ "r": Rect2(92, h * 0.5 - 18, 220, 16), "rad": 8 },
		{ "r": Rect2(92, h * 0.5 + 8, 150, 12), "rad": 8 },
	]
	s.custom_minimum_size = Vector2(0, h)
	return s


## Titelzeilen (Musik): kleines Cover, Titel und Künstler; die Zeilen wachsen mit der Breite.
static func track_rows(count := 8, row_h := 76.0) -> Control:
	var s = _make()
	for i in count:
		var y := i * row_h + 11.0
		s.shapes.append({ "r": Rect2(62, y, 52, 52), "rad": 8 })
		s.shapes.append({ "r": Rect2(132, y + 6, 420, 16), "rad": 6, "fx": 0.4, "dx": i * 14.0 })
		s.shapes.append({ "r": Rect2(132, y + 32, 260, 13), "rad": 6, "fx": 0.25, "dx": i * 8.0, "a": 0.7 })
	s.custom_minimum_size = Vector2(0, row_h * count)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# --- Übergang ins Ergebnis ---------------------------------------------------------------------

## Das Ergebnis tritt an die Stelle des Platzhalters (gleicher Elternknoten, gleiche Stelle) und
## blendet weich ein; der Platzhalter geht im selben Bild. Formen gleich groß: nichts verrutscht.
static func swap(skel: Control, result: Control) -> void:
	var parent := skel.get_parent() if is_instance_valid(skel) else null
	if parent == null:
		return
	var at := skel.get_index()
	parent.remove_child(skel)
	skel.queue_free()
	result.modulate.a = 0.0
	parent.add_child(result)
	parent.move_child(result, at)
	U.ankommen(result, U.T_ORT, "uz_in").tween_property(result, "modulate:a", 1.0, U.T_ORT)


## Platzhalter über bzw. unter einem Ergebnis, das schon an seinem Platz liegt (Bild in einer
## Karte): ruhig ausblenden und dann entfernen.
static func fade_out(skel: Control) -> void:
	if not is_instance_valid(skel) or not skel.is_inside_tree():
		if is_instance_valid(skel):
			skel.queue_free()
		return
	skel.remove_from_group(GROUP)
	var tw := U.weg(skel, "uz_out")
	tw.tween_property(skel, "modulate:a", 0.0, U.T_WEG)
	tw.tween_callback(skel.queue_free)

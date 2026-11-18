extends RefCounted
## Die eine Listen-Sprache von Uzai, aus dem Guide gezogen und überall gleich: Abschnitt (kleines
## Etikett in Versalien, gesperrt), Haarlinie statt Karten, der Zeilen-Cursor (gehobene, weich
## gerundete Fläche ohne Linie, die Schrift bleibt hell), der ruhige Knopf (echte Fläche, gewählt
## hell; Stil in U.ruhig) und die Tastenzeile (Glyphe + ein Wort, einzeilig, höchstens vier, B zuletzt).
## Blätter (sheet.gd) und Dialoge (dialog.gd) setzen sie zusammen.
## Die Zeile selbst ist guide_row.gd (Guide, Sammel-Listen) bzw. setting_row.gd (Einstellungen,
## Blätter) – beide zeichnen den Cursor hier.

const U := preload("res://src/ui/u.gd")

## So weit ragt der Zeilen-Cursor links und rechts über eine Zeile ohne eigenen Innenrand.
const OUT := 16.0
## Höchstens so viele Hinweise in einer Tastenzeile.
const TASTEN_MAX := 4

static var _caps_font: FontVariation
static var _caps_base: Font


## Abschnitt: kleines Etikett in Versalien, leicht gesperrt, leise („IM SPIEL · 6“). 15 px – kleiner
## wird am Fernseher nichts geschrieben. extra steht nach einem Punkt dahinter (schon übersetzt
## oder eine Zahl).
static func abschnitt(text: String, extra := "") -> HBoxContainer:
	var row := U.hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := U.label(text, "cap", "faint", "medium")
	l.uppercase = true
	l.clip_text = false
	l.add_theme_font_override("font", caps_font())
	row.add_child(l)
	if extra != "":
		var e := U.label("  ·  " + TranslationServer.translate(extra), "cap", "faint", "medium")
		e.uppercase = true
		e.clip_text = false
		e.add_theme_font_override("font", caps_font())
		e.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(e)
	return row


## Schrift der Abschnitte: die mittlere Bedienschrift, gesperrt.
static func caps_font() -> FontVariation:
	var base := UzTheme.font("medium")
	if _caps_font == null or _caps_base != base:
		_caps_base = base
		_caps_font = FontVariation.new()
		_caps_font.base_font = base
		_caps_font.spacing_glyph = 2
	return _caps_font


## Haarlinie zwischen Abschnitten (statt Karten), mit gap Luft darüber und darunter.
static func linie(gap := 14) -> Control:
	var box := U.vbox(0)
	box.set_meta("uz_linie", true)      # wer eine überflüssige Linie wieder wegnimmt, erkennt sie daran
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(U.spacer(0, gap, false))
	var line := ColorRect.new()
	line.color = UzTheme.col("line")
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	box.add_child(U.spacer(0, gap, false))
	return box


## Der Zeilen-Cursor, überall gleich: eine gehobene, weich gerundete Fläche in hellem Graphit
## (UzTheme "sel"), keine Linie, kein Glimmen, die Schrift darauf bleibt hell. t blendet ein
## (0 … 1, im Cursor-Takt), die Zeile wächst nicht. r: Radius wie bei UzTheme.box (−1: Grundradius).
## Jede Zeile, die hier zeichnet, macht beim gleitenden Cursor mit (siehe unten): wandert die
## Auswahl in derselben Liste weiter, zeichnet die neue Zeile die Fläche auf dem Weg dorthin und
## die alte schweigt so lange.
static func cursor(ci: CanvasItem, rect: Rect2, t: float, r := -1) -> void:
	var c := ci as Control
	if c:
		c.set_meta("uz_zr", rect)
		c.set_meta("uz_zt", t)
		var w := _wache(c)
		if w:
			var was: Array = w.zeichnen(c, rect, t)
			if was.is_empty():
				return
			rect = was[0]
			t = was[1]
	_rahmen(ci, rect, t, r)


static var _flaeche: StyleBoxFlat


static func _rahmen(ci: CanvasItem, rect: Rect2, t: float, r := -1) -> void:
	if t <= 0.01:
		return
	if _flaeche == null:
		_flaeche = StyleBoxFlat.new()
		_flaeche.anti_aliasing = true
	var rad := UzTheme.rund(r)
	# Eine Pille, die höher wäre als die Zeile, rundet nur bis zur halben Höhe (sonst eine Naht).
	rad = mini(rad, maxi(0, int(minf(rect.size.x, rect.size.y) * 0.5) - 1))
	_flaeche.set_corner_radius_all(rad)
	var sel := UzTheme.col("sel")
	_flaeche.bg_color = Color(sel, sel.a * clampf(t, 0.0, 1.0))
	ci.draw_style_box(_flaeche, rect)


## Schalter der Listen-Sprache (Guide, Einstellungen): eine weiche Pille – aus Graphit mit
## Haarlinie und leisem Griff, an die Spur im Akzent mit dunklem Griff. t = 0 … 1 (der Griff gleitet).
static func schalter(ci: CanvasItem, r: Rect2, t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var spur := (UzTheme.col("surface_hi") as Color).lerp(UzTheme.col("accent"), t)
	ci.draw_style_box(UzTheme.box(spur, 999, 1, Color(UzTheme.col("line"), 1.0 - t)), r)
	var d := r.size.y - 8.0
	var x := lerpf(r.position.x + 4.0 + d * 0.5, r.end.x - 4.0 - d * 0.5, t)
	ci.draw_circle(Vector2(x, r.get_center().y), d * 0.5, UzTheme.col("muted").lerp(UzTheme.col("on_accent"), t), true, -1.0, true)


## Griff eines Reglers der Listen-Sprache: ein runder heller Punkt (Halbmesser rad).
static func griff(ci: CanvasItem, c: Vector2, rad := 6.0, farbe := Color(0, 0, 0, 0)) -> void:
	ci.draw_circle(c, rad, UzTheme.col("text") if farbe.a <= 0.0 else farbe, true, -1.0, true)


## --- Ein Cursor-Takt --------------------------------------------------------------------------
## Antwort im ersten Bild: ein neuer Cursor steht sofort zu ANTWORT_VON da und setzt sich in
## U.T_ANTWORT; ein alter fällt sofort auf ANTWORT_REST und geht in U.T_ANTWORT.
const ANTWORT_VON := 0.7
const ANTWORT_REST := 0.3
## Feder des gleitenden Cursors (straffer als U.SPRING: nach ~130 ms zu 90 % da, ohne Nachschwingen).
const GLEITEN := 30.0
## So viele Bilder nach dem Fokuswechsel darf die neue Zeile den Cursor noch übernehmen (eine
## gerade erst gebaute Zeile zeichnet ein Bild später).
const UEBERNAHME_BILDER := 3
## Weiter als so viele Zeilenhöhen (bzw. -breiten) gleitet der Cursor nicht.
const WEIT := 3.0
## Langsamer als so viele Pixel je Bild (60 Hz) gleitet der Cursor nie (ruhiges Ende statt Treppe); dazu
## mindestens ein Schritt des Rasters je Bild (src/core/raster.gd).
const MIN_PX := 1.0
const Raster := preload("res://src/core/raster.gd")
## So nah am Ziel setzt sich der gleitende Cursor in einem Schritt (1 px: nach Schritten von je
## einem Pixel nie zwei auf einmal).
const SCHLUSS_PX := 1.0


## Stand der eigenen Fläche einer Zeile im Cursor-Takt bewegen. von: Stand jetzt; setzen(v)
## übernimmt jeden neuen Stand (und zeichnet neu); key: Name der Bewegung an c.
static func takt(c: Node, von: float, on: bool, setzen: Callable, key := "uz_cur") -> void:
	var start := maxf(von, ANTWORT_VON) if on else minf(von, ANTWORT_REST)
	var bis := 1.0 if on else 0.0
	setzen.call(start)
	if not c.is_inside_tree():
		setzen.call(bis)
		return
	var tw := U.ankommen(c, U.T_ANTWORT, key) if on else U.weg(c, key)
	tw.tween_method(setzen, start, bis, U.T_ANTWORT)


## Fokus einer Zeile, deren Stand in der Meta "uz_f" liegt (setting_row, list_item): im Theme mit
## Cursor der Marke im Cursor-Takt, sonst die Auswahl des Themes (U.etikett: Fläche und dunkle Schrift).
static func fokus(c: Control, on: bool) -> void:
	if not UzTheme.cursor_frame():
		U.etikett(c, on)
		return
	takt(c, float(c.get_meta("uz_f", 0.0)), on, func(v: float) -> void:
		if is_instance_valid(c):
			c.set_meta("uz_f", v)
			c.queue_redraw()
	, "uz_ftw")


## A gedrückt auf einer Zeile (Stand in "uz_f"): nur die Fläche drückt – 1 → 0,55 in T_ANTWORT
## und zurück in T_ORT. Schrift und Zeile bleiben stehen (Schrift wird nie skaliert).
static func druck(c: Control) -> void:
	var setzen := func(v: float) -> void:
		if is_instance_valid(c):
			c.set_meta("uz_f", v)
			c.queue_redraw()
	if not c.is_inside_tree():
		return
	var tw := U.ankommen(c, U.T_ORT, "uz_ftw")
	tw.tween_method(setzen, 1.0, DRUCK, U.T_ANTWORT)
	tw.tween_method(setzen, DRUCK, 1.0, U.T_ORT)


## So tief drückt die Fläche beim Bestätigen.
const DRUCK := 0.55


## Ein Schritt einer kritisch gedämpften Feder für etwas, das in ganzen Pixeln steht (Cursor, Regal,
## Bildlauf): mindestens MIN_PX je Bild (bei 60 Hz), denn der Ausläufer der Feder träte sonst in
## ganzen Pixeln auf der Stelle (Schritt, Pause, Schritt); weniger als ein halbes Pixel vor dem Ziel
## gleich ans Ziel. So endet jede Bewegung mit einem kleinen Schritt statt einer Treppe. [Lage, Tempo]
static func feder_px(vor: float, vel: float, ziel: float, d: float, omega: float) -> Vector2:
	return _Wache.feder_px(vor, vel, ziel, d, omega)


## --- Der gleitende Cursor: eine Liste, ein Cursor ------------------------------------------------
## Wandert die Auswahl innerhalb derselben Liste (gleicher Bildlauf, sonst gleiche Fläche) von
## Zeile zu Zeile, verschwindet der Cursor nicht hier und erscheint dort: er gleitet mit einer
## kritisch gedämpften Feder hinüber, auch über Abschnittslinien und in Zeilen anderer Höhe. Kommt
## der Fokus von außen (anderer Bildlauf, Knopf, neue Ebene), steht er im Cursor-Takt da.
## „Animationen reduzieren“: kein Gleiten.
static var _w: _Wache = null


static func _wache(c: Control) -> _Wache:
	if is_instance_valid(_w):
		return _w
	if not c.is_inside_tree():
		return null
	_w = _Wache.new()
	_w.name = "UzGleiter"
	c.get_tree().root.add_child.call_deferred(_w)
	return _w


## Die Zeile, zu der der Cursor gerade gleitet (sonst null) – für Proben und Tests.
static func gleitet_zu() -> Control:
	if not is_instance_valid(_w) or not _w.gleitet:
		return null
	return _w._ref(_w.ziel) as Control


## Wo der gleitende Cursor gerade liegt (Bildschirm), sonst ein leeres Rechteck.
static func gleiter_lage() -> Rect2:
	if gleitet_zu() == null:
		return Rect2()
	var b := _w._ref(_w.bezug) as Control
	return b.get_global_transform() * _w.lage if b else Rect2()


class _Wache extends Node:
	const UU := preload("res://src/ui/u.gd")
	var vorher: WeakRef = null      ## Fokus vor dem letzten Wechsel
	var jetzt: WeakRef = null       ## Fokus seit dem letzten Wechsel
	var bild := -100                ## Bildnummer des letzten Wechsels
	var ziel: WeakRef = null        ## Zeile, die den Cursor trägt
	var quelle: WeakRef = null      ## Zeile, von der er gerade weggleitet (zeichnet so lange nicht)
	var bezug: WeakRef = null       ## gemeinsamer Vorfahr; in seinen Koordinaten gleitet der Cursor
	var gleitet := false
	var lage := Rect2()             ## Cursor jetzt (in bezug)
	var tempo := Rect2()            ## Tempo je Wert (Lage und Größe)

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_viewport().gui_focus_changed.connect(_fokus)
		set_process(false)

	func _fokus(c: Control) -> void:
		vorher = jetzt
		jetzt = weakref(c)
		bild = Engine.get_process_frames()

	func _ref(w: WeakRef) -> Object:
		return w.get_ref() if w else null

	## Was c zeichnen soll: [Rechteck, Stand] – oder [] (nichts, der Cursor ist gerade woanders).
	func zeichnen(c: Control, rect: Rect2, t: float) -> Array:
		if c.has_focus() and _ref(ziel) != c:
			_uebernehmen(c)
		if gleitet:
			if _ref(ziel) == c:
				var b := _ref(bezug) as Control
				if b:
					var r: Rect2 = (c.get_global_transform().affine_inverse() * b.get_global_transform()) * lage
					# Ganze Pixel: der Cursor flimmert sonst an halben Kanten.
					return [Rect2(r.position.round(), r.size.round()), 1.0]
			elif _ref(quelle) == c:
				return []
		return [rect, t]

	func _uebernehmen(c: Control) -> void:
		var alt := _ref(ziel) as Control
		var hatte := gleitet and _ref(bezug) != null
		var war_lage := (_ref(bezug) as Control).get_global_transform() * lage if hatte else Rect2()
		var war_tempo := tempo if hatte else Rect2()
		var q := _ref(quelle) as Control
		gleitet = false
		quelle = null
		ziel = weakref(c)
		set_process(false)
		if q:
			q.queue_redraw()
		if alt == null or alt == c or not alt.is_inside_tree() or UU.reduziert():
			return
		# Nur ein Schritt von alt nach c, eben erst (dazwischen hatte nichts anderes den Fokus).
		if _ref(vorher) != alt or _ref(jetzt) != c or Engine.get_process_frames() - bild > UEBERNAHME_BILDER:
			return
		if alt.has_focus() or not alt.is_visible_in_tree() or not alt.has_meta("uz_zr"):
			return
		if c.get_viewport() != get_viewport() or alt.get_viewport() != get_viewport():
			return
		var wa := _wurzel(alt)
		if wa == null or wa != _wurzel(c):
			return
		var b := _gemeinsam(alt, c)
		if b == null or UU.sichtbar(alt).size.y < 2.0:
			return
		var inv := b.get_global_transform().affine_inverse()
		lage = inv * war_lage if hatte else (inv * alt.get_global_transform()) * (alt.get_meta("uz_zr") as Rect2)
		# Weite Sprünge (an den Anfang, über viele Zeilen) gleiten nicht quer über die Liste: der
		# Cursor steht dann gleich am Ziel, im Cursor-Takt.
		var zr := (inv * c.get_global_transform()) * Rect2(Vector2.ZERO, c.size)
		if absf(zr.get_center().y - lage.get_center().y) > WEIT * maxf(zr.size.y, 40.0) \
				or absf(zr.get_center().x - lage.get_center().x) > WEIT * maxf(zr.size.x, 40.0):
			return
		tempo = war_tempo
		bezug = weakref(b)
		quelle = weakref(alt)
		gleitet = true
		alt.queue_redraw()
		c.queue_redraw()
		set_process(true)

	func _process(dt: float) -> void:
		var c := _ref(ziel) as Control
		var b := _ref(bezug) as Control
		if not gleitet or c == null or b == null or not c.is_inside_tree() or not b.is_inside_tree():
			_ende()
			return
		# Fokus mitten im Gleiten weg auf etwas ohne Listen-Cursor (Chat neben dem Guide): Die
		# Zeile blendet ihre Fläche aus, uz_zt erreicht nie 1 – sonst bliebe der Cursor dort stehen.
		if not c.has_focus():
			_ende()
			return
		var zr: Rect2 = (b.get_global_transform().affine_inverse() * c.get_global_transform()) * (c.get_meta("uz_zr") as Rect2)
		var d := minf(dt, 0.1) * UU.tempo()
		var p := [lage.position.x, lage.position.y, lage.size.x, lage.size.y]
		var v := [tempo.position.x, tempo.position.y, tempo.size.x, tempo.size.y]
		var z := [zr.position.x, zr.position.y, zr.size.x, zr.size.y]
		var da := true
		for i in 4:
			var s := schritt(float(p[i]), float(v[i]), float(z[i]), d)
			p[i] = s.x
			v[i] = s.y
			if absf(s.x - float(z[i])) > 0.01:
				da = false
		lage = Rect2(p[0], p[1], p[2], p[3])
		tempo = Rect2(v[0], v[1], v[2], v[3])
		c.queue_redraw()
		# Am Ziel, und der eigene Fläche der Zeile steht ganz: ab jetzt zeichnet sie selbst.
		if da and float(c.get_meta("uz_zt", 1.0)) >= 0.99:
			_ende()

	## Ein Schritt des Gleitens (Feder GLEITEN, in ganzen Pixeln ohne Treppe, siehe feder_px). Die
	## letzten SCHLUSS_PX setzt der Cursor in einem Schritt: danach hängt er an der Zeile – rollt die
	## Liste noch, liefen sonst Ausläufer und Bildlauf gegeneinander (ein Bild Stillstand).
	static func schritt(vor: float, vel: float, ziel: float, d: float) -> Vector2:
		var s := feder_px(vor, vel, ziel, d, GLEITEN)
		if absf(ziel - s.x) <= SCHLUSS_PX:
			s = Vector2(ziel, 0.0)
		return s

	static func feder_px(vor: float, vel: float, ziel: float, d: float, omega: float) -> Vector2:
		var s := UU.spring_step(vor, vel, ziel, d, omega)
		# Je Bild mindestens ein Schritt des Rasters (ein Punkt, an 4K ein Bildpunkt) und nicht langsamer als
		# MIN_PX je Bild bei 60 Hz. Vorher nur Letzteres: Bei 120 Hz war das ein halber Punkt je Bild – auf
		# ganzen Punkten wieder „Schritt, Pause, Schritt“.
		var min_s := maxf(Raster.schritt, MIN_PX * d * 60.0)
		if absf(s.x - vor) < min_s:
			var w := clampf(ziel - vor, -min_s, min_s)
			s = Vector2(vor + w, w / maxf(d, 0.001))
		if absf(ziel - s.x) < Raster.schritt * 0.5:
			s = Vector2(ziel, 0.0)
		return s

	func _ende() -> void:
		gleitet = false
		set_process(false)
		for w in [ziel, quelle]:
			var n := _ref(w) as CanvasItem
			if n:
				n.queue_redraw()
		quelle = null

	## Die Liste einer Zeile: der nächste Bildlauf (oder ein Vorfahr mit Meta "uz_liste"), sonst die
	## nächste Fläche, die kein Container ist.
	static func _wurzel(c: Node) -> Node:
		var n := c.get_parent()
		var flaeche: Node = null
		while n:
			if n is ScrollContainer or (n is Control and (n as Control).has_meta("uz_liste")):
				return n
			if flaeche == null and n is Control and not (n is Container):
				flaeche = n
			if n is Window:
				break
			n = n.get_parent()
		return flaeche

	static func _gemeinsam(a: Node, b: Node) -> Control:
		var n := a.get_parent()
		while n:
			if n is Control and n.is_ancestor_of(b):
				return n as Control
			n = n.get_parent()
		return null


## Zeichnet die Auswahl einer Zeile außerhalb des Guides: im Theme mit matter Auswahl (Marke) der
## Zeilen-Cursor wie im Guide, sonst die Auswahl des Themes (helle Fläche, U.draw_focus).
static func zeilen_auswahl(c: Control, r := -1, rect := Rect2()) -> void:
	if not UzTheme.cursor_frame():
		U.draw_focus(c, r, rect)
		return
	var f: float = c.get_meta("uz_f", 1.0 if c.has_focus() else 0.0)
	cursor(c, rect if rect.size != Vector2.ZERO else Rect2(Vector2.ZERO, c.size), f, r)


## Ein ruhiger Knopf (Dialoge, Seiten): echte, gerundete Fläche (Haupthandlung im Akzent mit
## dunkler Schrift, sonst getönter Graphit, "danger" rot getönt), gewählt hell mit dunkler Schrift
## (U.ruhig). Nur im Theme mit dem Cursor der Marke – sonst der Knopf des Themes (U.button).
## Der Hauptknopf (art "primary") gilt als Haupthandlung: nur er gibt beim Bestätigen einen Impuls
## am Controller (Nav.haupt).
static func knopf(text: String, icon_name := "", art := "") -> Button:
	if not UzTheme.cursor_frame():
		var tb := U.button(text, icon_name, "primary" if art == "primary" else "normal")
		if art == "primary":
			tb.set_meta("uz_haupt", true)
		return tb
	var b := Button.new()
	if art == "primary":
		b.set_meta("uz_haupt", true)
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 56)
	if icon_name != "":
		b.icon = Icons.tex(icon_name, 24)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_constant_override("h_separation", 12)
	U.ruhig(b, art)
	return b


## Tastenzeile ordnen: B immer zuletzt, höchstens TASTEN_MAX Hinweise (B bleibt immer drin; was
## darüber hinausgeht, wirkt weiter, steht aber nicht unten). hints: [[[tasten…], text], …].
static func tasten_ordnen(hints: Array, max_n := TASTEN_MAX) -> Array:
	var b: Array = hints.filter(func(h): return "b" in (h[0] as Array))
	var rest: Array = hints.filter(func(h): return not ("b" in (h[0] as Array)))
	var platz := maxi(0, max_n - b.size())
	return rest.slice(0, platz) + b

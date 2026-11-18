extends Control
## Das Zeichen von Uzai (Marke „U-Band“, docs/DESIGN.md): ein U aus zwei Bändern, der Länge nach
## geteilt, dazwischen eine helle Lichtlinie durch den ganzen Bogen; auf einer dunklen, weich
## gerundeten Kachel – genau das App-Symbol (icon.svg). Flach und als Vektor gezeichnet: scharf in
## jeder Größe, gefärbt aus dem Akzent des Themes (außen ein heller Verlauf ins tiefe Violett, innen
## eine Spur dunkler, die Linie hell). Kein Punkt, kein Kreis – das U allein ist das Zeichen.
## Die Wortmarke UZAI aus eigenen Buchstaben im selben Bau (U wie das Zeichen, Z mit einer
## Lichtlinie in der Diagonale, A als Λ mit Querstrich aus Licht, I) steht nur, wo der Name stehen
## muss: am Ende der Startanimation, auf der Info-Seite, in der Einrichtung.
## Formen aus src/ui/marke_form.gd (H, B, STRICH, FUGE; wort_umrisse, wort_linien).
##
## mode: "zeichen" (das Zeichen), "flach" (nur das U, für kleine Stellen: draw_mark), "wort".
## stil (nur „zeichen“): "marke" – Kachel und U in den Markenfarben (App-Symbol, Start, Info,
## Einrichtung); "kopf" – in die Kopfzeile eingebunden (KOPF_STIL: das U im Ton der Schrift, nur
## die Linie im Akzent, keine Kachel), mit leisem Hover.
## Bewegung (Handschrift): Die Linie zieht sich in einem Zug durch den Bogen (play), die Bänder
## setzen sich darum. Guide-Taste: ein Licht läuft einmal durch die Linie (pulse).

const U := preload("res://src/ui/u.gd")
const Form := preload("res://src/ui/marke_form.gd")

var mode := "zeichen"                ## "zeichen", "flach" oder "wort"
var stil := "marke"                  ## "marke", "kopf" (siehe oben) oder eine der STILE
var progress := 1.0                  ## Erscheinen: 0 … 1 (blendet ein und setzt sich)
var licht := 1.0                     ## wie weit die Linie gezogen ist (0 … 1)
var ink := Color.TRANSPARENT         ## flach: Farbe der Bänder (leer: aus dem Akzent)
var _lauf := -1.0                    ## Lichtkopf beim Puls (0 … 1; < 0: keiner)
var _hell := 0.0                     ## Aufhellen der Linie (Puls, Hover)
var _hover := 0.0
var _pulse_tw: Tween
var _play_tw: Tween
var _hover_tw: Tween

## Kachel wie im App-Symbol: Das U ist KACHEL_U der Kachelseite hoch, die Ecken KACHEL_R rund.
const KACHEL_U := 150.0 / 240.0
const KACHEL_R := 54.0 / 240.0
## Wortmarke: Breite bei Versalhöhe 1 (marke_form.wort_x).
const WORT_BREITE := 3.26
## Kopfzeile: Höhe des Zeichens (main.brand_mark) und – ohne Kopfzeile, im Spiel – seine Mitte über
## dem Guide (guide.gd, mark_rect).
const KOPF_H := 28.0
const KOPF_MITTE := Vector2(96.0, 59.0)
## Wie das Zeichen in der Kopfzeile steht (tests/probe_marke.gd zeigt alle): „ton“ – das U im Ton
## der Schrift, nur die Linie im Akzent (gewählt); „kachel“ – eine leise Kachel in der Flächenfarbe;
## „akzent“ – das U in den Markenfarben ohne Kachel.
const STILE := ["ton", "kachel", "akzent"]
const KOPF_STIL := "ton"
## Der Puls dauert einen Raumwechsel (U.T_RAUM).
const PULSE_S := U.T_RAUM
## So lange zieht sich die Linie beim Erscheinen (play).
const PLAY_S := U.T_LICHT

static var _formen: Array = []
static var _wort: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if stil != "marke":
		# Leises Hover: die Linie hellt auf, das U hebt sich eine Spur.
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(_hover_auf.bind(1.0))
		mouse_exited.connect(_hover_auf.bind(0.0))


## Breite des Zeichens bei Höhe h (mit Kachel quadratisch, ohne nur das U).
static func zeichen_breite(h: float, kachel := true) -> float:
	return h if kachel else h * Form.B / Form.H


## Breite der Wortmarke bei Versalhöhe h.
static func word_width(h: float) -> float:
	return h * WORT_BREITE


## Die Art der Farben: „marke“ oder eine aus STILE („kopf“ nimmt KOPF_STIL).
func art() -> String:
	if stil in STILE:
		return stil
	return "marke" if stil == "marke" else KOPF_STIL


## Hat dieses Zeichen eine Kachel?
func mit_kachel() -> bool:
	return mode == "zeichen" and art() in ["marke", "kachel"]


# --- Farben ---------------------------------------------------------------------------------

## Farbe des Eloxals zu einem Akzent: satter und tiefer (aus dem Markenviolett #A47BFF wird ein tiefes Violett).
static func elox(akzent: Color) -> Color:
	return Color.from_hsv(akzent.h, clampf(akzent.s * 1.35 + 0.12, 0.0, 0.85), clampf(akzent.v * 0.62, 0.25, 0.7))


## Farbe der Lichtlinie zu einem Akzent.
static func licht_von(akzent: Color) -> Color:
	return Color.from_hsv(akzent.h, clampf(akzent.s * 0.9, 0.0, 0.6), 1.0)


## Die Farben des Zeichens: { aussen: [oben, unten], innen: [oben, unten], linie, kachel: [oben,
## unten], kante, kachel_a } – „marke“ wie icon.svg, sonst eingebunden in das Theme.
static func farben(art: String, akzent: Color) -> Dictionary:
	var e := elox(akzent)
	var f := {
		"aussen": [e.lightened(0.28), e.darkened(0.22)], "innen": [e, e.darkened(0.22).darkened(0.25)],
		"linie": licht_von(akzent), "kachel": [Color("#201d29"), Color("#0c0b10")], "kante": Color("#3d3948"), "kachel_a": 1.0,
	}
	if art == "ton" or art == "kachel":
		var t := UzTheme.col("text")
		f.aussen = [t, t.darkened(0.12)]
		f.innen = [Color(t.darkened(0.42), 1.0), Color(t.darkened(0.5), 1.0)]
		f.linie = akzent
	if art == "kachel":
		f.kachel = [UzTheme.col("surface_hi"), UzTheme.col("surface")]
		f.kante = UzTheme.col("line")
	return f


# --- Bewegung -------------------------------------------------------------------------------

## Erscheinen: Das Zeichen blendet ein und setzt sich (T_RAUM), die Linie zieht sich (PLAY_S).
## Ruhig: nur Einblenden, die Linie steht gleich.
func play(delay := 0.0) -> void:
	progress = 0.0
	licht = 0.0
	queue_redraw()
	if _play_tw and _play_tw.is_valid():
		_play_tw.kill()
	_play_tw = U.ankommen(self, U.T_RAUM, "uz_logo_play")
	if U.reduziert():
		licht = 1.0
		_play_tw.tween_interval(delay)
		_play_tw.tween_method(set_progress, 0.0, 1.0, U.T_RAUM)
		return
	_play_tw.set_parallel(true)
	_play_tw.tween_method(set_progress, 0.0, 1.0, U.T_RAUM).set_delay(delay)
	_play_tw.tween_method(set_licht, 0.0, 1.0, PLAY_S).set_delay(delay + U.T_ORT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_progress(v: float) -> void:
	progress = v
	queue_redraw()


func set_licht(v: float) -> void:
	licht = v
	queue_redraw()


## Guide-Signatur: Ein Licht läuft einmal durch die Linie (PULSE_S). Matte Themes und „Animationen
## reduzieren“: die Linie hellt nur kurz auf.
func pulse() -> void:
	if _pulse_tw and _pulse_tw.is_valid():
		_pulse_tw.kill()
	_pulse_tw = create_tween()
	var ruhig := U.reduziert() or UzTheme.matt()
	_pulse_tw.tween_method(func(v: float) -> void:
		_hell = sin(PI * v)
		_lauf = -1.0 if ruhig else v * 1.2 - 0.1
		queue_redraw()
	, 0.0, 1.0, PULSE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tw.tween_callback(func() -> void:
		_hell = 0.0
		_lauf = -1.0
		queue_redraw()
	)


func _hover_auf(ziel: float) -> void:
	if _hover_tw and _hover_tw.is_valid():
		_hover_tw.kill()
	_hover_tw = U.ankommen(self, U.T_ANTWORT, "uz_logo_hover")
	_hover_tw.tween_method(func(v: float) -> void:
		_hover = v
		queue_redraw()
	, _hover, ziel, U.T_ANTWORT)


## Der tiefste Punkt der Linie (Grund des Bogens) in eigenen Koordinaten – etwa für einen Lichtschein.
func licht_pos() -> Vector2:
	var h := _u_hoehe()
	var cy := -Form.H * 0.5 + Form.B * 0.5
	var rx := Form.B * 0.5 - Form.STRICH * 0.5
	return size * 0.5 + Vector2(0, -(cy - rx)) * h / Form.H


## Höhe des U im Rahmen dieses Zeichens.
func _u_hoehe() -> float:
	if mit_kachel():
		return minf(size.x, size.y) * KACHEL_U
	return minf(size.y, size.x * Form.H / Form.B)


func _draw() -> void:
	var akzent := UzTheme.col("accent")
	var e := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 3.0)
	if e <= 0.0:
		return
	var rise := (1.0 - e) * size.y * 0.04 * (0.0 if U.reduziert() else 1.0)
	var mitte := size * 0.5 + Vector2(0, rise)
	if mode == "flach":
		var fc := ink if ink.a > 0.0 else akzent
		draw_mark(self, mitte, minf(size.y, size.x * Form.H / Form.B), Color(fc, fc.a * e), Color(licht_von(akzent), e * licht))
		return
	if mode == "wort":
		var h := minf(size.y, size.x / WORT_BREITE)
		var f := farben("ton", akzent)
		zeichne_wort(self, Vector2((size.x - word_width(h)) * 0.5, (size.y + h) * 0.5 + rise), h,
			{ "farbe": Color(f.aussen[0], e), "licht": Color(licht_von(akzent), e), "weg": licht })
		return
	var f2 := farben(art(), akzent)
	var linie: Color = f2.linie
	f2.linie = linie.lerp(Color.WHITE, 0.25 * _hover)
	zeichne(self, mitte, _u_hoehe(), f2, {
		"alpha": e, "kachel": 1.0 if mit_kachel() else 0.0, "weg": licht, "lauf": _lauf, "hell": maxf(_hell, 0.6 * _hover),
		"hub": -1.5 * _hover })


# --- Zeichnen (statisch: auch für Startanimation und Tastensymbol) -------------------------------

## Die beiden Bänder des U im Maß des Zeichens (M3, y nach oben): [[außen, innen], Linie]. Einmal.
static func flach_formen() -> Array:
	if _formen.is_empty():
		var rx := Form.B * 0.5 - Form.STRICH * 0.5
		var cy := -Form.H * 0.5 + Form.B * 0.5
		var teile := Form.teilen(Form.u_glyph(Form.H, Form.B, Form.STRICH), [Form.u_linie(rx, cy, Form.H)], Form.FUGE)
		teile.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return Form._laenge(a) > Form._laenge(b))
		_formen = [teile, Form.u_linie(rx, cy, Form.H * 0.5)]
	return _formen


## Das Zeichen um mitte, das U h hoch. f: Farben (farben()), o: Zustand –
##   alpha (Deckkraft), kachel (0 … 1, Deckkraft der Kachel), kachel_k (Größe der Kachel, 1 = wie im
##   App-Symbol), baender (0 … 1: die Bänder setzen sich um die Linie), weg (Linie gezogen 0 … 1),
##   lauf (Lichtkopf, < 0 keiner), hell (Linie heller), glanz (Lichtverlauf über die Kachel, −1 … 1,
##   außerhalb: keiner), hub (Versatz nach oben, px).
static func zeichne(ci: CanvasItem, mitte: Vector2, h: float, f: Dictionary, o: Dictionary) -> void:
	var a := float(o.get("alpha", 1.0))
	if a <= 0.003 or h <= 1.0:
		return
	var k := h / Form.H
	mitte += Vector2(0, float(o.get("hub", 0.0)))
	var ka := float(o.get("kachel", 0.0)) * a * float(f.get("kachel_a", 1.0))
	if ka > 0.003:
		var seite := h / KACHEL_U * float(o.get("kachel_k", 1.0))
		_kachel(ci, mitte, seite, f, ka, float(o.get("glanz", -9.0)))
	var formen := flach_formen()
	var teile: Array = formen[0]
	var setzen := float(o.get("baender", 1.0))
	for i in teile.size():
		var paar: Array = f.aussen if i == 0 else f.innen
		# Die Bänder setzen sich um die Linie: außen von außen, innen von innen, beide blenden ein.
		var weg := (1.0 - setzen) * 0.18 * (1.0 if i == 0 else -1.0)
		var pts := PackedVector2Array()
		for q in (teile[i] as PackedVector2Array):
			var r := q
			if weg != 0.0:
				var mq := Vector2(0, -Form.H * 0.5 + Form.B * 0.5)
				var d := (q - mq) if q.y < mq.y else Vector2(q.x, 0)
				r = q + d.normalized() * weg
			pts.append(mitte + Vector2(r.x, -r.y) * k)
		_verlauf(ci, pts, paar[0], paar[1], a * clampf(setzen * 1.4, 0.0, 1.0))
	var w := float(o.get("weg", 1.0))
	if w > 0.0:
		var linie := PackedVector2Array()
		for q in (formen[1] as PackedVector2Array):
			linie.append(mitte + Vector2(q.x, -q.y) * k)
		var lc: Color = f.linie
		var hell := float(o.get("hell", 0.0))
		lc = lc.lerp(Color.WHITE, 0.35 * hell)
		var breite := maxf(Form.FUGE * k * 0.8, 1.0)
		var stueck := segment(linie, 0.0, w)
		if stueck.size() >= 2:
			ci.draw_polyline(stueck, Color(lc, a * minf(1.0, Form.FUGE * k * 0.8)), breite, true)
		var lauf := float(o.get("lauf", -1.0))
		if lauf >= 0.0 and lauf <= 1.0:
			var kopf := segment(linie, maxf(lauf - 0.08, 0.0), minf(lauf + 0.08, 1.0))
			if kopf.size() >= 2:
				ci.draw_polyline(kopf, Color(1, 1, 1, a * 0.85), breite * 1.4, true)


## Die Kachel: weich gerundet, Verlauf von oben, eine feine Lichtkante oben; glanz läuft als einziger
## Lichtverlauf schräg darüber (in der Kachel geschnitten).
static func _kachel(ci: CanvasItem, mitte: Vector2, seite: float, f: Dictionary, a: float, glanz: float) -> void:
	var poly := _rund_rechteck(mitte, seite, seite * KACHEL_R)
	var oben: Color = f.kachel[0]
	var unten: Color = f.kachel[1]
	var farben := PackedColorArray()
	for q in poly:
		var t := clampf((q.y - (mitte.y - seite * 0.5)) / seite, 0.0, 1.0)
		farben.append(Color(oben.lerp(unten, t), a))
	ci.draw_polygon(poly, farben)
	var ring := poly.duplicate()
	ring.append(poly[0])
	var kc := PackedColorArray()
	var kante: Color = f.kante
	for q in ring:
		var t := clampf((q.y - (mitte.y - seite * 0.5)) / (seite * 0.5), 0.0, 1.0)
		kc.append(Color(kante, a * (1.0 - t)))
	ci.draw_polyline_colors(ring, kc, maxf(seite / 170.0, 1.0), true)
	if glanz > -1.2 and glanz < 1.2:
		# Ein breiter, schräger Streif aus Licht, in die Kachel geschnitten.
		var x := mitte.x + glanz * seite
		var b := seite * 0.35
		var band := PackedVector2Array([Vector2(x - b, mitte.y - seite), Vector2(x, mitte.y - seite), Vector2(x - seite * 0.6, mitte.y + seite),
			Vector2(x - b - seite * 0.6, mitte.y + seite)])
		for teil in Geometry2D.intersect_polygons(poly, band):
			var cols := PackedColorArray()
			for q in (teil as PackedVector2Array):
				# Quer zum Streif weich: Mitte hell, Ränder durchsichtig.
				var u := clampf(((q.x - x) + (q.y - mitte.y + seite) * 0.3 + b * 0.5) / b, 0.0, 1.0)
				cols.append(Color(1, 1, 1, a * 0.07 * sin(PI * u)))
			ci.draw_polygon(teil, cols)


static func _rund_rechteck(mitte: Vector2, seite: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hs := seite * 0.5
	var ecken := [[Vector2(hs - r, -hs + r), -PI * 0.5], [Vector2(hs - r, hs - r), 0.0], [Vector2(-hs + r, hs - r), PI * 0.5], [Vector2(-hs + r, -hs + r), PI]]
	for e in ecken:
		for i in 13:
			var w := float(e[1]) + PI * 0.5 * i / 12.0
			out.append(mitte + (e[0] as Vector2) + Vector2(cos(w), sin(w)) * r)
	return out


## Ein Vieleck mit Verlauf von oben links (oben) nach unten rechts (unten), wie icon.svg; die Kante
## geglättet.
static func _verlauf(ci: CanvasItem, pts: PackedVector2Array, oben: Color, unten: Color, a: float) -> void:
	if a <= 0.003 or pts.size() < 3:
		return
	var lo := pts[0]
	var hi := pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var g := Vector2(0.35, 1.0)
	var cols := PackedColorArray()
	for q in pts:
		var r := (q - lo) / (hi - lo).max(Vector2(0.001, 0.001))
		cols.append(Color(oben.lerp(unten, clampf(r.dot(g) / g.dot(g), 0.0, 1.0)), a))
	ci.draw_polygon(pts, cols)
	var ring := pts.duplicate()
	ring.append(pts[0])
	var rc := cols.duplicate()
	rc.append(cols[0])
	ci.draw_polyline_colors(ring, rc, 1.0, true)


## Das Zeichen flach in einer Farbe (Tastensymbol der Guide-Taste): beide Bänder in
## farbe (das innere eine Spur dunkler), die Linie in licht_c (nur, wo sie breit genug ist).
static func draw_mark(ci: CanvasItem, center: Vector2, h: float, farbe: Color, licht_c := Color.TRANSPARENT) -> void:
	if farbe.a <= 0.003 or h <= 1.0:
		return
	var f := { "aussen": [farbe, farbe], "innen": [farbe.darkened(0.14), farbe.darkened(0.14)], "linie": licht_c }
	zeichne(ci, center, h, f, { "alpha": farbe.a, "weg": 1.0 if licht_c.a > 0.003 and Form.FUGE * h / Form.H >= 1.0 else 0.0 })


## Zeichen und Name in einer Zeile, wo ein Bild die Marke trägt (Fernseher im Zimmer, Schnappschuss):
## das U-Band ohne Kachel in den Markenfarben zum akzent, u_h hoch, oben links bei pos; rechts daneben,
## mittig zum U, die flache Wortmarke UZAI wie am Ende der Startanimation (gesperrt um spur, ohne
## Licht) in farbe. schatten: zuerst alles flach in dieser Farbe, eine Spur tiefer (leer: keiner).
## Gibt die Breite zurück.
static func zeichne_zeile(ci: CanvasItem, pos: Vector2, u_h: float, akzent: Color, farbe: Color, spur := 0.45,
		schatten := Color(0, 0, 0, 0)) -> float:
	var ub := zeichen_breite(u_h, false)
	var h := u_h * 0.3
	var xs: Array = Form.wort_x()
	var p := float(xs[4]) * 0.5 - 0.4
	var links := -p * spur
	var wort_b := (float(xs[4]) + (float(xs[3]) - p) * spur - links) * h
	var mitte := pos + Vector2(ub * 0.5, u_h * 0.5)
	var grund := Vector2(pos.x + ub + u_h * 0.42 - links * h, pos.y + (u_h + h) * 0.5)
	var wo := { "licht": Color(0, 0, 0, 0), "weg": 0.0, "spur": spur }
	if schatten.a > 0.003:
		var v := Vector2(0, maxf(1.0, u_h * 0.05))
		draw_mark(ci, mitte + v, u_h, schatten)
		wo.farbe = schatten
		zeichne_wort(ci, grund + v, h, wo)
	zeichne(ci, mitte, u_h, farben("marke", akzent), { "kachel": 0.0 })
	wo.farbe = farbe
	zeichne_wort(ci, grund, h, wo)
	return grund.x + links * h + wort_b - pos.x


## Die Wortmarke UZAI, links unten bei grund (Grundlinie), Versalhöhe h. o: farbe (Buchstaben),
## licht (Lichter in U, Z, A), weg (0 … 1: die Lichter schreiben sich nacheinander), spur (zusätzliche
## Laufweite in Versalhöhen: Buchstaben weiter auseinander), buchstabe (Callable i -> Deckkraft).
static func zeichne_wort(ci: CanvasItem, grund: Vector2, h: float, o: Dictionary) -> void:
	if _wort.is_empty():
		_wort = [Form.wort_umrisse(), Form.wort_linien(), Form.wort_x()]
	var umrisse: Array = _wort[0]
	var linien: Array = _wort[1]
	var xs: Array = _wort[2]
	var farbe: Color = o.get("farbe", Color.WHITE)
	var lc: Color = o.get("licht", Color.WHITE)
	var weg := float(o.get("weg", 1.0))
	var spur := float(o.get("spur", 0.0))
	var einzel: Callable = o.get("buchstabe", Callable())
	var mitte_x := float(xs[4]) * 0.5
	for i in 4:
		var ba := float(einzel.call(i)) if einzel.is_valid() else 1.0
		if ba <= 0.003:
			continue
		var x0 := float(xs[i]) + (float(xs[i]) - mitte_x + 0.4) * spur
		for poly in (umrisse[i] as Array):
			var pts := PackedVector2Array()
			for q in (poly as PackedVector2Array):
				pts.append(grund + Vector2(x0 + q.x, -q.y) * h)
			draw_shape(ci, pts, Color(farbe, farbe.a * ba))
		if i < 3:
			var lw := clampf(weg * 3.0 - i, 0.0, 1.0)
			if lw > 0.0:
				var ln := PackedVector2Array()
				for q in (linien[i] as PackedVector2Array):
					ln.append(grund + Vector2(x0 + q.x, -q.y) * h)
				var st := segment(ln, 0.0, lw)
				if st.size() >= 2:
					ci.draw_polyline(st, Color(lc, lc.a * ba), maxf(h * (0.05 if i == 2 else 0.035), 1.0), true)


## Eine Fläche mit weicher Kante: Godot glättet Polygone nicht, darum zieht eine geglättete
## Linie die Kante nach (nur fast deckend – halb durchsichtig läge sie sichtbar doppelt).
static func draw_shape(ci: CanvasItem, pts: PackedVector2Array, c: Color) -> void:
	if c.a <= 0.003 or pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, c)
	if c.a >= 0.9:
		var ring := pts.duplicate()
		ring.append(pts[0])
		ci.draw_polyline(ring, c, 1.0, true)


## Das Stück einer Linie zwischen den Anteilen a und b (nach Länge).
static func segment(pts: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	a = clampf(a, 0.0, 1.0)
	b = clampf(b, 0.0, 1.0)
	if pts.size() < 2 or b <= a:
		return PackedVector2Array()
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var von := total * a
	var bis := total * b
	var out := PackedVector2Array()
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		var s0 := acc
		var s1 := acc + seg
		if s1 >= von and out.is_empty():
			out.append(pts[i - 1].lerp(pts[i], (von - s0) / maxf(seg, 0.0001)))
		if not out.is_empty():
			if s1 >= bis:
				out.append(pts[i - 1].lerp(pts[i], (bis - s0) / maxf(seg, 0.0001)))
				break
			out.append(pts[i])
		acc = s1
	return out


## Mittellinie der Lichtlinie auf dem Schirm (für Lichtspuren und Tests): um center bei Höhe h, von
## oben links durch den Bogen nach oben rechts.
static func fuge(center: Vector2, h: float) -> PackedVector2Array:
	var k := h / Form.H
	var out := PackedVector2Array()
	for q in (flach_formen()[1] as PackedVector2Array):
		out.append(center + Vector2(q.x, -q.y) * k)
	return out

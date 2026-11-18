extends RefCounted
## Kluge Bildzuschnitte und einheitliche Farbabstimmung (Punkt 97).
##
## Muss ein Bild in ein anderes Format (Hero breit → Karte, Hochkant-Cover → breite Kachel,
## Screenshot → Hintergrund, Video-Vorschau → Short hochkant), bleibt der wichtige Teil im Bild
## statt stumpf die Mitte. Dafür wird eine kleine Fassung des Bilds (höchstens 64 Punkte lang)
## einmal nach Kanten und Kontrast durchgesehen: Je Spalte und je Zeile steht fest, wie viel dort
## „los ist“ (zwei Profile mit je 16 Fächern). Beim Zuschneiden rückt das Fenster dorthin, wo am
## meisten los ist – aber nur, wenn es sich deutlich lohnt; sonst bleibt es mittig wie bisher.
## Harte, dichte Kanten (Schrift, Schriftzüge, Logos) zählen extra, und das Fenster schneidet
## ungern mitten durch sie hindurch. Nie verzerrt: Der Ausschnitt hat immer genau das
## Seitenverhältnis der Fläche, nur seine Lage ändert sich. Gesichter erkennt das nicht – muss es
## auch nicht: Motive heben sich fast immer durch Kanten vom ruhigen Hintergrund ab.
##
## Farbe: Die Akzentfarbe eines Bilds (Media.vivid_color) kommt in ein festes Helligkeitsband
## (accent): nie grell neben weißer Schrift (Kontrast mindestens 3 : 1), nie so dunkel, dass sie im
## Raum verschwindet. Sehr helle Kachelbilder werden leicht gedämpft (tone_of), und alle Kacheln
## tragen denselben zarten Verlauf (scrim) – Shop-, Film-, Video- und Spielbilder wirken
## nebeneinander ruhig.
##
## Gerechnet wird im Hintergrund-Thread beim Dekodieren (Media._decode), gemerkt je Datei
## (Media: cache/bildlook.json, Schlüssel Pfad und Änderungszeit). Das Zuschneiden selbst kostet
## nichts: Die Fläche zeigt einen Ausschnitt (AtlasTexture) des schon geladenen Bilds.
## Leichter Modus: gröbere Analyse (40 Punkte) und kein zusätzlicher Verlauf – nur was billig ist.
## Ohne Fenster testbar (tests/logic_zuschnitt.gd).

const Leicht := preload("res://src/core/leicht.gd")

const BINS := 16              ## Fächer je Profil
const SIDE := 64              ## Länge der kleinen Fassung für die Analyse (lange Seite)
const SIDE_LEICHT := 40
const HARD_EDGE := 0.2        ## ab diesem Helligkeitssprung zählt eine Kante als hart (Schrift, Logo)
const HARD_BOOST := 1.5       ## … und so viel mehr
const CENTER_PULL := 0.1      ## je Anteil Abstand von der Mitte so viel Abzug (bei Gleichstand: Mitte)
const MIN_GAIN := 0.025       ## erst ab so viel mehr „Inhalt“ im Fenster rückt es von der Mitte weg
const CUT_K := 0.012          ## Abzug, wenn eine Fensterkante mitten durch dichte Kanten schneidet
const STEPS := 48             ## geprüfte Lagen je Achse

## Akzentfarbe: relative Leuchtdichte zwischen diesen Werten. 0,30 heißt: weiße Schrift darauf hat
## mindestens 3 : 1 Kontrast; 0,12 hebt sich noch deutlich vom fast schwarzen Raum ab.
const ACCENT_L := Vector2(0.12, 0.30)
const ACCENT_S := Vector2(0.32, 0.78)

## Helle Kachelbilder (weiße Shop-Kapseln, helle Vorschaubilder) sanft auf diese mittlere
## Helligkeit zurücknehmen, höchstens auf TONE_MIN. Dunkle Bilder bleiben, wie sie sind.
const TONE_FROM := 0.5
const TONE_MIN := 0.84

## Der gemeinsame Verlauf über allen Kachelbildern: oben ein Hauch, unten etwas mehr (dort stehen
## Länge, Fortschritt und Plaketten).
const SCRIM_TOP := 0.07
const SCRIM_BOTTOM := 0.3


# --- Analyse (Hintergrund-Thread) --------------------------------------------------------------

## Kleine Fassung eines Bilds für die Analyse (RGBA, lange Seite höchstens side Punkte, kurze
## mindestens 8). Erst halbieren (mittelt 2 × 2 Punkte: ruhig, ohne Flimmern), den Rest bilinear.
static func small_of(img: Image, side := SIDE) -> Image:
	if img == null or img.is_empty():
		return null
	var im := img.duplicate() as Image
	if im.is_compressed() and im.decompress() != OK:
		return null
	im.clear_mipmaps()
	var w := im.get_width()
	var h := im.get_height()
	var k := float(side) / float(maxi(w, h))
	var tw := clampi(int(round(w * k)), 8, side)
	var th := clampi(int(round(h * k)), 8, side)
	while im.get_width() >= tw * 2 and im.get_height() >= th * 2:
		im.shrink_x2()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != tw or im.get_height() != th:
		im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	return im


## Profile und mittlere Helligkeit einer kleinen Fassung (small_of):
## { x: Inhalt je Spalten-Fach, y: je Zeilen-Fach (je Summe 1), l: mittlere Helligkeit 0…1 }.
static func analyze(small: Image) -> Dictionary:
	if small == null or small.is_empty():
		return {}
	var w := small.get_width()
	var h := small.get_height()
	var data := small.get_data()
	if small.get_format() != Image.FORMAT_RGBA8 or data.size() < w * h * 4:
		return {}
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var alpha := PackedFloat32Array()
	alpha.resize(w * h)
	var lsum := 0.0
	var asum := 0.0
	for i in w * h:
		var r := data[i * 4]
		var g := data[i * 4 + 1]
		var b := data[i * 4 + 2]
		var a := data[i * 4 + 3] / 255.0
		var l := (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
		lum[i] = l
		alpha[i] = a
		lsum += l * a
		asum += a
	var cols := PackedFloat32Array()
	cols.resize(w)
	var rows := PackedFloat32Array()
	rows.resize(h)
	for y in h:
		var y0 := maxi(y - 1, 0) * w
		var y1 := mini(y + 1, h - 1) * w
		var row := y * w
		for x in w:
			var i := row + x
			if alpha[i] < 0.5:
				continue
			var gx := absf(lum[row + mini(x + 1, w - 1)] - lum[row + maxi(x - 1, 0)])
			var gy := absf(lum[y1 + x] - lum[y0 + x])
			var e := gx + gy
			if e > HARD_EDGE:
				e *= 1.0 + HARD_BOOST
			cols[x] += e
			rows[y] += e
	return { "x": pool(cols), "y": pool(rows), "l": lsum / maxf(asum, 1.0) }


## Werte auf BINS Fächer verteilen (anteilig, auch bei weniger als BINS Werten) und auf Summe 1
## bringen. Ganz ohne Inhalt: gleich verteilt.
static func pool(v: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BINS)
	var n := v.size()
	if n == 0:
		out.fill(1.0 / BINS)
		return out
	var k := float(BINS) / float(n)
	for i in n:
		var p0 := i * k
		var p1 := (i + 1) * k
		var b := int(p0)
		while b < BINS and float(b) < p1:
			var part := minf(p1, b + 1.0) - maxf(p0, float(b))
			if part > 0.0:
				out[b] += v[i] * part / k
			b += 1
	var s := 0.0
	for x in out:
		s += x
	if s <= 0.000001:
		out.fill(1.0 / BINS)
		return out
	for b in BINS:
		out[b] /= s
	return out


# --- Lage des Ausschnitts ----------------------------------------------------------------------

## Wo ein Fenster der Breite frac (Anteil 0…1) in einem Profil beginnt (0 … 1 − frac). Mittig, wenn
## sich kein Platz deutlich lohnt; sonst dort, wo das meiste drin ist – ohne mitten durch dichte
## Kanten zu schneiden (Schrift am Rand bleibt ganz drin oder ganz draußen).
static func pick(prof: PackedFloat32Array, frac: float) -> float:
	var span := 1.0 - clampf(frac, 0.0, 1.0)
	var mid := span * 0.5
	if span <= 0.001 or prof.size() != BINS:
		return maxf(mid, 0.0)
	var cum := PackedFloat32Array()
	cum.resize(BINS + 1)
	for b in BINS:
		cum[b + 1] = cum[b] + prof[b]
	var best := mid
	var best_s := _score(prof, cum, mid, frac, mid)
	var center_s := best_s
	for k in STEPS + 1:
		var o := span * float(k) / float(STEPS)
		var s := _score(prof, cum, o, frac, mid)
		if s > best_s + 0.000001:
			best_s = s
			best = o
	return best if best_s > center_s + MIN_GAIN else mid


static func _score(prof: PackedFloat32Array, cum: PackedFloat32Array, o: float, frac: float, mid: float) -> float:
	var s := _cum_at(cum, o + frac) - _cum_at(cum, o) - CENTER_PULL * absf(o - mid)
	# Eine Kante im Bildinneren, die durch dichtes Gebiet läuft (mehr als doppelt so dicht wie im
	# Schnitt), kostet etwas – je dichter, desto mehr.
	if o > 0.001:
		s -= CUT_K * maxf(_dens(prof, o) - 2.0, 0.0)
	if o + frac < 0.999:
		s -= CUT_K * maxf(_dens(prof, o + frac) - 2.0, 0.0)
	return s


static func _cum_at(cum: PackedFloat32Array, t: float) -> float:
	var p := clampf(t, 0.0, 1.0) * BINS
	var i := mini(int(p), BINS - 1)
	return cum[i] + (cum[i + 1] - cum[i]) * (p - i)


## Dichte an einer Stelle, 1 = Durchschnitt (Mittel der beiden Fächer an der Grenze).
static func _dens(prof: PackedFloat32Array, t: float) -> float:
	var p := clampf(t, 0.0, 1.0) * BINS
	var a := clampi(int(round(p)) - 1, 0, BINS - 1)
	var b := clampi(int(round(p)), 0, BINS - 1)
	return (prof[a] + prof[b]) * 0.5 * BINS


## Ein Fenster der Größe win (Bildpunkte) in einem Bild der Größe ts, gelegt nach look (analyze).
## Ohne look: mittig – genau wie bisher.
static func window(look: Dictionary, ts: Vector2, win: Vector2) -> Rect2:
	win = Vector2(minf(win.x, ts.x), minf(win.y, ts.y))
	var pos := (ts - win) * 0.5
	if look.has("x") and win.x < ts.x - 0.5:
		pos.x = pick(look.x, win.x / ts.x) * ts.x
	if look.has("y") and win.y < ts.y - 0.5:
		pos.y = pick(look.y, win.y / ts.y) * ts.y
	return Rect2(pos, win)


## Der Ausschnitt eines Bilds, der eine Fläche (box) randvoll füllt wie
## STRETCH_KEEP_ASPECT_COVERED – gleiches Seitenverhältnis wie die Fläche, also nie verzerrt.
static func region(look: Dictionary, ts: Vector2, box: Vector2) -> Rect2:
	if ts.x <= 0.0 or ts.y <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return Rect2(Vector2.ZERO, ts)
	var s := maxf(box.x / ts.x, box.y / ts.y)
	return window(look, ts, box / s)


# --- Farbe -------------------------------------------------------------------------------------

## Relative Leuchtdichte (WCAG) einer Farbe.
static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## Akzentfarbe eines Spiels aus der kräftigsten Farbe seines Bilds: Farbton bleibt, Sättigung
## gemäßigt, Helligkeit im Band ACCENT_L. So leuchtet ein neongelbes Cover nicht grell hinter
## weißer Schrift, und ein tiefblaues versinkt nicht im Raum.
static func accent(c: Color) -> Color:
	var h := c.h
	var s := clampf(c.s, ACCENT_S.x, ACCENT_S.y)
	var v := clampf(c.v, 0.35, 0.95)
	var l := luminance(Color.from_hsv(h, s, v))
	if l > ACCENT_L.y:
		# Zu hell: dunkler, bis es passt (Halbierungssuche, Farbton und Sättigung bleiben).
		var lo := 0.0
		var hi := v
		for i in 14:
			var m := (lo + hi) * 0.5
			if luminance(Color.from_hsv(h, s, m)) > ACCENT_L.y:
				hi = m
			else:
				lo = m
		v = lo
	elif l < ACCENT_L.x:
		# Zu dunkel: erst heller; reicht das nicht (tiefes Blau), etwas weniger gesättigt.
		var lo2 := v
		var hi2 := 1.0
		if luminance(Color.from_hsv(h, s, 1.0)) >= ACCENT_L.x:
			for i in 14:
				var m2 := (lo2 + hi2) * 0.5
				if luminance(Color.from_hsv(h, s, m2)) < ACCENT_L.x:
					lo2 = m2
				else:
					hi2 = m2
			v = hi2
		else:
			v = 1.0
			var slo := 0.0
			var shi := s
			for i in 14:
				var ms := (slo + shi) * 0.5
				if luminance(Color.from_hsv(h, ms, 1.0)) < ACCENT_L.x:
					shi = ms
				else:
					slo = ms
			s = slo
	return Color.from_hsv(h, s, v)


## Dämpfung für ein Kachelbild nach seiner mittleren Helligkeit (self_modulate): helle Bilder
## leicht zurück, dunkle unverändert.
static func tone(l: float) -> Color:
	if l <= TONE_FROM:
		return Color.WHITE
	var k := clampf(1.0 - (l - TONE_FROM) * 0.45, TONE_MIN, 1.0)
	return Color(k, k, k, 1.0)


static func tone_of(t: Texture2D) -> Color:
	if t == null or not t.has_meta("uz_look"):
		return Color.WHITE
	var look: Variant = t.get_meta("uz_look")
	return tone(float((look as Dictionary).get("l", 0.0))) if look is Dictionary else Color.WHITE


static var _scrim: GradientTexture2D


## Der gemeinsame Verlauf für alle Kachelbilder (einmal angelegt).
static func scrim() -> GradientTexture2D:
	if _scrim == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, SCRIM_TOP), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0),
			Color(0, 0, 0, SCRIM_BOTTOM * 0.45), Color(0, 0, 0, SCRIM_BOTTOM)])
		_scrim = GradientTexture2D.new()
		_scrim.gradient = g
		_scrim.fill_from = Vector2.ZERO
		_scrim.fill_to = Vector2(0, 1)
		_scrim.width = 4
		_scrim.height = 128
	return _scrim


# --- Anzeigen ----------------------------------------------------------------------------------

## Bild in eine TextureRect setzen (STRETCH_KEEP_ASPECT_COVERED): Bringt es eine Analyse mit
## (aus Media), zeigt die Fläche den klugen Ausschnitt statt der Mitte und passt ihn an, wenn sich
## ihre Größe ändert (eine Filmkarte wird breit). tone: helle Bilder leicht dämpfen; scrim: den
## gemeinsamen Verlauf darüberlegen (nicht im leichten Modus). Bilder ohne Analyse (selbst
## erzeugte Farbfelder, weichgezeichnete Fassungen) bleiben genau wie bisher.
static func put(tr: TextureRect, t: Texture2D, tone_on := true, scrim_on := true) -> void:
	if tr == null:
		return
	tr.texture = t
	if tone_on:
		tr.self_modulate = tone_of(t)
	if scrim_on and not Leicht.active and t != null and not tr.has_node("UzScrim"):
		var sc := TextureRect.new()
		sc.name = "UzScrim"
		sc.texture = scrim()
		sc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sc.stretch_mode = TextureRect.STRETCH_SCALE
		sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.add_child(sc)
	if not tr.has_meta("uz_crop_on"):
		tr.set_meta("uz_crop_on", true)
		tr.resized.connect(func() -> void: refit(tr))
	refit(tr)


## Ausschnitt zur aktuellen Größe der Fläche (siehe put). Hat jemand anderes inzwischen ein Bild
## ohne Analyse gesetzt (oder keins), bleibt alles, wie es ist.
static func refit(tr: TextureRect) -> void:
	if not is_instance_valid(tr):
		return
	var t := tr.texture
	if t == null:
		return
	var src: Texture2D = t
	if t is AtlasTexture and t.has_meta("uz_crop"):
		src = (t as AtlasTexture).atlas
	if src == null or not src.has_meta("uz_look"):
		return
	var box := tr.size
	var ts := src.get_size()
	if box.x < 1.0 or box.y < 1.0 or ts.x < 1.0 or ts.y < 1.0:
		return
	var r := region(src.get_meta("uz_look"), ts, box)
	var centered := r.position.distance_to((ts - r.size) * 0.5) < 0.75
	if centered:
		# Mitte: das Bild selbst (die Fläche schneidet es wie immer mittig zu).
		if t != src:
			tr.texture = src
		return
	if t != src:
		var at := t as AtlasTexture
		if not at.region.is_equal_approx(r):
			at.region = r
		return
	var a := AtlasTexture.new()
	a.atlas = src
	a.region = r
	a.set_meta("uz_crop", true)
	# Wer das Bild der Fläche liest (Farbe, weiche Fassung), findet dieselben Angaben.
	for m in ["uz_src", "uz_vivid", "uz_look"]:
		if src.has_meta(m):
			a.set_meta(m, src.get_meta(m))
	tr.texture = a

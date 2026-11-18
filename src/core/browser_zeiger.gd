extends RefCounted
## Uzai-Browser: der Zeiger mit dem Stick – reine Logik ohne Oberfläche (browser.gd zeichnet und schickt).
## Gerechnet wird in CSS-Pixeln im Bild der Seite (wie die Ziele des Sprung-Skripts), mit Kommastellen.
##   Kurve      radiale Totzone, danach neu von 0 an (kein Sprung, kein Ruckeln am Rand der Totzone), dann
##              ein kleiner linearer Anteil plus Potenz: wenig Ausschlag ist sehr fein, voller schnell
##   Tempo      in Bildbreiten je Sekunde (Einheit: Fläche des Bildes, 16:9 = Breite) – gleich schnell auf
##              1080p, 4K, mit Windows-Skalierung oder Zoom; Stufen im Browser-Menü
##   Schub      lange voll gehalten in eine Richtung: nach SCHUB_NACH s weich bis SCHUB × schneller
##   Fein       Schultertaste gehalten: FEIN × Tempo, kein Schub
##   Glätten    die Geschwindigkeit folgt dem Stick weich (an Bildrate entkoppelt), bremst schneller als
##              sie anfährt – kein Nachrutschen
##   Magnet     (Einrasten an) über und nahe an einem Ziel bremst langsame Bewegung (REIBUNG), schnelle bleibt
##              frei; losgelassen gleitet der Zeiger in die Mitte eines nahen kleinen Ziels bzw. in ein großes
##   Treffer    A trifft das Ziel unter dem Zeiger; knapp daneben (TREFFER px) zählt das nächste kleine Ziel
##   Rand       oben/unten gegen den Rand gedrückt: die Seite rollt
## Rahmen (iframes, z. B. Einwilligungs-Banner): kein Einrasten hinein, nur etwas Bremse – ihre Knöpfe kennt
## nur die Seite, der Klick dort ist ein echter Mausklick über den Kern. Tests: tests/logic_browser.gd (_zeiger).

const K := preload("res://src/core/browser_karte.gd")

const TOT := 0.14              ## radiale Totzone innen (Stick-Drift)
const VOLL := 0.95             ## ab hier voller Ausschlag (Sticks erreichen schräg selten 1,0)
const LINEAR := 0.16           ## linearer Anteil der Kurve: der feine Anfang
const EXPO := 2.6              ## Potenz der Kurve
const TEMPI := { "langsam": 0.55, "mittel": 0.8, "schnell": 1.15 }   ## Bildbreiten je Sekunde bei vollem Stick
const STANDARD_TEMPO := "mittel"
const SCHUB := 1.8
const SCHUB_NACH := 0.35       ## s voll halten, bis der Schub beginnt
const SCHUB_DAUER := 0.45      ## s bis zum vollen Schub
const FEIN := 0.3
const AUF := 30.0              ## 1/s: so schnell folgt die Geschwindigkeit beim Anfahren
const AB := 45.0               ## 1/s: … und beim Bremsen
const REIBUNG := 0.42          ## Tempo über einem kleinen Ziel bei langsamer Bewegung
const REIBUNG_GROSS := 0.8     ## … über einem großen Ziel
const REIBUNG_RAHMEN := 0.7    ## … über einem Rahmen (seine Knöpfe sind unsichtbar für Uzai)
const REIBUNG_RAND := 16.0     ## px um ein Ziel, in denen die Bremse weich einsetzt
const EINRASTEN := 26.0        ## so nah (px) rastet er nach dem Loslassen ein
const EINRASTEN_NACH := 0.06   ## s nach dem Loslassen
const EINRASTEN_RATE := 16.0   ## 1/s
const INNEN := 6.0             ## so weit (px) zieht das Einrasten in ein großes Ziel hinein
const TREFFER := 14.0          ## knapp daneben zählt noch
const KLEIN := Vector2(360, 200)   ## bis zu dieser Größe ist ein Ziel „klein“ (rastet in der Mitte ein)
const ZEILE := 64.0            ## breitere Ziele bis zu dieser Höhe: auf die Mittellinie
const RAND_ROLLEN := 1.6       ## Bildhöhen je Sekunde, wenn der Zeiger voll gegen den Rand drückt

var p := Vector2(-1, -1)       ## Stelle im Bild der Seite (CSS-Pixel, Sub-Pixel)
var v := Vector2.ZERO          ## CSS-Pixel je Sekunde (geglättet)
var rand := Vector2.ZERO       ## Wunsch zu rollen, weil der Zeiger gegen den Rand drückt (CSS-Pixel je Sekunde)
var ueber := {}                ## Ziel unter dem Zeiger ({}: keins)
var _voll_t := 0.0
var _richtung := Vector2.ZERO
var _ruhe_t := 0.0
var _gleiten := Vector2(-1, -1)


## Stick → Auslenkung 0…1 mit Richtung: radiale Totzone (neu skaliert), dann Kurve.
static func kurve(s: Vector2, tot := TOT, voll := VOLL) -> Vector2:
	var l := s.length()
	if l <= tot or not is_finite(l):
		return Vector2.ZERO
	var x := clampf((l - tot) / maxf(0.01, voll - tot), 0.0, 1.0)
	var y := LINEAR * x + (1.0 - LINEAR) * pow(x, EXPO)
	return s / l * y


## Längeneinheit des Bildes: bei 16:9 seine Breite, sonst dieselbe Fläche.
static func einheit(vw: float, vh: float) -> float:
	return sqrt(maxf(1.0, vw) * maxf(1.0, vh)) * 4.0 / 3.0


static func tempo(name: String) -> float:
	return float(TEMPI.get(name, TEMPI[STANDARD_TEMPO]))


static func klein(r: Rect2) -> bool:
	return r.size.x <= KLEIN.x and r.size.y <= KLEIN.y


## Das Ziel bei p: eines, das p enthält (das kleinste, etwa der Knopf in der Karte), sonst das nächste
## innerhalb von nah px; {} wenn keins.
static func ziel_bei(punkt: Vector2, ziele: Array, nah := 0.0) -> Dictionary:
	var best := {}
	var best_d := INF
	var best_a := INF
	for z in K.aktive(ziele):
		var r: Rect2 = z.r
		var d := K.abstand(punkt, r)
		if d > nah:
			continue
		var a := r.get_area()
		if d < best_d - 0.01 or (absf(d - best_d) <= 0.01 and a < best_a):
			best = z
			best_d = d
			best_a = a
	return best


## Bremse über einem Ziel (1: frei). staerke: Auslenkung nach der Kurve – schnelle Bewegung bleibt frei.
static func reibung(punkt: Vector2, ziele: Array, staerke: float) -> float:
	var z := ziel_bei(punkt, ziele, REIBUNG_RAND)
	if z.is_empty():
		return 1.0
	var r: Rect2 = z.r
	var basis := REIBUNG_RAHMEN if str(z.art) == "rahmen" else (REIBUNG if klein(r) else REIBUNG_GROSS)
	var nah := 1.0 - clampf(K.abstand(punkt, r) / REIBUNG_RAND, 0.0, 1.0)
	var f := lerpf(1.0, basis, nah)
	return lerpf(f, 1.0, smoothstep(0.3, 0.75, staerke))


## Wohin der Zeiger losgelassen gleitet: Mitte eines nahen kleinen Ziels, in ein großes hinein (eine breite Zeile:
## auf ihre Mittellinie); (-1, -1): bleibt.
static func einrast_punkt(punkt: Vector2, ziele: Array) -> Vector2:
	var z := ziel_bei(punkt, ziele, EINRASTEN)
	if z.is_empty() or str(z.art) == "rahmen":
		return Vector2(-1, -1)
	var r: Rect2 = z.r
	if klein(r):
		return r.get_center()
	# Großes Ziel: knapp am Rand oder daneben ein Stück hinein, sonst bleibt er, wo er ist.
	var innen := r.grow(-minf(INNEN, minf(r.size.x, r.size.y) * 0.25))
	var q := punkt.clamp(innen.position, innen.end)
	# Breite, flache Zeile (Link in einer Liste): auf ihre Mittellinie.
	if r.size.y <= ZEILE:
		q.y = r.get_center().y
	return q if q.distance_to(punkt) > 0.05 else Vector2(-1, -1)


## Was A trifft: { id (-1: nichts Bekanntes), punkt, art }. Im Ziel: genau dort; knapp neben einem Ziel: in
## dessen Mitte (klein) bzw. knapp hinein (groß). Neben einem Rahmen nie hinein (dort weiß nur die Seite Bescheid).
static func treffer(punkt: Vector2, ziele: Array, nah := TREFFER) -> Dictionary:
	var z := ziel_bei(punkt, ziele, nah)
	if z.is_empty():
		return { "id": -1, "punkt": punkt, "art": "" }
	var r: Rect2 = z.r
	if r.has_point(punkt):
		return { "id": int(z.id), "punkt": punkt, "art": str(z.art) }
	if str(z.art) == "rahmen":
		return { "id": -1, "punkt": punkt, "art": "" }
	var innen := r.grow(-minf(INNEN, minf(r.size.x, r.size.y) * 0.25))
	return { "id": int(z.id), "punkt": r.get_center() if klein(r) else punkt.clamp(innen.position, innen.end), "art": str(z.art) }


## Steuerkreuz im Zeiger: zum nächsten Ziel in der Richtung (im Bild) gleiten. Liefert die Id (-1: keins).
func springen(dir: String, ziele: Array, vw: float, vh: float) -> int:
	var von: Rect2 = (ueber.r as Rect2) if not ueber.is_empty() else Rect2(p - Vector2.ONE, Vector2(2, 2))
	var ohne := int(ueber.id) if not ueber.is_empty() else -1
	var sicht := ziele.filter(func(z: Dictionary) -> bool: return K.im_bild(z.r, vw, vh))
	var id := K.bestes(sicht, von, ohne, int(ueber.get("bereich", -1)), dir)
	if id < 0:
		return -1
	var z := K.finde(sicht, id)
	var r := (z.r as Rect2).intersection(Rect2(0, 0, vw, vh))
	_gleiten = r.get_center()
	return id


## Ein Bild weiter: stick roh, dt in Sekunden, o = { tempo, fein, einrasten, ziele_frisch }.
## Liefert, ob sich der Zeiger bewegt hat.
func schritt(stick: Vector2, dt: float, ziele: Array, vw: float, vh: float, o: Dictionary) -> bool:
	dt = clampf(dt, 0.0, 0.1)
	var magnet := bool(o.get("einrasten", true)) and bool(o.get("ziele_frisch", true))
	var bekannt: Array = ziele if bool(o.get("ziele_frisch", true)) else []
	var k := kurve(stick)
	var staerke := k.length()
	var dir := k / staerke if staerke > 0.0 else Vector2.ZERO
	if staerke > 0.9 and (_richtung == Vector2.ZERO or dir.dot(_richtung) > 0.85):
		_voll_t += dt
	else:
		_voll_t = 0.0
	_richtung = dir
	var faktor := 1.0 + (SCHUB - 1.0) * smoothstep(SCHUB_NACH, SCHUB_NACH + SCHUB_DAUER, _voll_t)
	if bool(o.get("fein", false)):
		faktor = FEIN
	var soll := k * float(o.get("tempo", tempo(STANDARD_TEMPO))) * einheit(vw, vh) * faktor
	if magnet and staerke > 0.0:
		soll *= reibung(p, bekannt, staerke)
	var rate := AUF if soll.length() >= v.length() else AB
	v = v.lerp(soll, 1.0 - exp(-dt * rate))
	if staerke == 0.0 and v.length() < 3.0:
		v = Vector2.ZERO
	var alt := p
	if staerke > 0.0:
		_gleiten = Vector2(-1, -1)
		_ruhe_t = 0.0
	else:
		_ruhe_t += dt
	var frei := p + v * dt
	rand = Vector2.ZERO
	if frei.y < 0.0 and k.y < 0.0:
		rand.y = k.y * RAND_ROLLEN * vh
	elif frei.y > vh - 1.0 and k.y > 0.0:
		rand.y = k.y * RAND_ROLLEN * vh
	p = frei.clamp(Vector2.ZERO, Vector2(maxf(0.0, vw - 1.0), maxf(0.0, vh - 1.0)))
	if _gleiten.x >= 0.0:
		p = p.lerp(_gleiten, 1.0 - exp(-dt * 20.0))
		if p.distance_to(_gleiten) < 0.4:
			p = _gleiten
			_gleiten = Vector2(-1, -1)
	elif magnet and _ruhe_t >= EINRASTEN_NACH and v == Vector2.ZERO:
		var m := einrast_punkt(p, bekannt)
		if m.x >= 0.0:
			p = p.lerp(m, 1.0 - exp(-dt * EINRASTEN_RATE))
			if p.distance_to(m) < 0.3:
				p = m
	ueber = ziel_bei(p, bekannt)
	return not p.is_equal_approx(alt)


## Die Seite hat einen anderen Zoom (neues CSS-Bild): der Zeiger bleibt an derselben Stelle des Schirms.
func umrechnen(alt_vw: float, alt_vh: float, vw: float, vh: float) -> void:
	if alt_vw <= 0.0 or alt_vh <= 0.0 or p.x < 0.0:
		return
	p = Vector2(p.x * vw / alt_vw, p.y * vh / alt_vh)
	if _gleiten.x >= 0.0:
		_gleiten = Vector2(-1, -1)
	v = Vector2.ZERO


func setzen(punkt: Vector2) -> void:
	p = punkt
	v = Vector2.ZERO
	rand = Vector2.ZERO
	_voll_t = 0.0
	_ruhe_t = 0.0
	_gleiten = Vector2(-1, -1)
	ueber = {}

extends RefCounted
## Uzai-Browser: die Fokus-Karte einer Seite und das Springen darauf – reine Logik ohne Oberfläche.
## Das Sprung-Skript des Wirts (helper/uzai-browser-karte.js, eigene Welt, von der Seite unsichtbar)
## meldet die anklickbaren Ziele der Seite: Rechteck im Bild der Seite (CSS-Pixel, links oben im
## Fenster), Art (Link, Knopf, Feld …) und Bereich (Kopf, Navigation, Inhalt, Seitenleiste, Fuß,
## Dialog). Unsichtbares, Winziges und Verdecktes lässt das Skript schon weg. Hier entscheidet Uzai,
## wohin ein Druck führt:
##   Steuerkreuz/linker Stick  das nächste Ziel in der Richtung (Abstand in Richtung + doppelt quer,
##                             Überlappung zählt für, große Ziele leicht bevorzugt, ein anderer Bereich
##                             kostet, was daneben liegt, ist nicht darunter, Knöpfe in Karten sind
##                             erreichbar); die Gegenrichtung führt zurück, woher der Sprung kam; liegt
##                             das nächste Ziel weit hinter langem Text, rollt die Seite zuerst ein Stück
##   LB/RB                     in den vorigen/nächsten Bereich (Lesereihenfolge)
##   L3                        Magnet-Zeiger (browser_zeiger.gd): freier Zeiger, bremst über Zielen, rastet ein
## Offener Dialog der Seite (Bereich „dialog“: Cookie-Fenster, Anmeldung, Lightbox): Der Fokus bleibt im
## Dialog (aktive()), wie mit der Tastatur – nichts dahinter ist erreichbar, bis er zu ist.
## Gemerkt wird die Stelle je Seite (Mitte des Ziels in Seiten-Koordinaten), damit „Zurück“ dort
## weitermacht. Tests: tests/logic_browser.gd.

const P := preload("res://src/core/browser_protokoll.gd")

const QUER := 2.0               ## Abstand quer zur Richtung zählt so viel mehr
const ANDERER_BEREICH := 420.0  ## Aufpreis, wenn das Ziel hoch/runter in einem anderen Bereich liegt
const ANDERER_BEREICH_QUER := 140.0   ## … links/rechts (Inhalt ↔ Seitenleiste ist dort normal)
const GEGEN := { "up": "down", "down": "up", "left": "right", "right": "left" }
const GROESSE_BONUS := 0.08     ## je Wurzel der Fläche (gedeckelt) etwas näher
const LESEN := 0.6              ## liegt das nächste Ziel weiter als so viele Bildhöhen hinter dem Rand: erst rollen


## Rohe Ziele der Leitung → [{ id, r: Rect2, art, bereich }].
static func als_ziele(roh: Array) -> Array:
	var out: Array = []
	for z in roh:
		out.append({ "id": int(z[0]), "r": Rect2(float(z[1]), float(z[2]), float(z[3]), float(z[4])),
			"art": P.ARTEN[clampi(int(z[5]), 0, P.ARTEN.size() - 1)], "bereich": int(z[6]) })
	return out


## Die Ziele, die gerade erreichbar sind: liegt ein Dialog offen, nur seine (Fokus-Falle); sonst alle.
static func aktive(ziele: Array) -> Array:
	var dialog := P.BEREICHE.find("dialog")
	var drin := ziele.filter(func(z: Dictionary) -> bool: return int(z.bereich) == dialog)
	return drin if not drin.is_empty() else ziele


static func finde(ziele: Array, id: int) -> Dictionary:
	for z in ziele:
		if int(z.id) == id:
			return z
	return {}


## Liegt das Ziel (zumindest zur Hälfte) im Bild?
static func im_bild(r: Rect2, vw: float, vh: float) -> bool:
	var sicht := r.intersection(Rect2(0, 0, vw, vh))
	return sicht.get_area() >= r.get_area() * 0.5 - 0.5


## Wohin führt ein Druck in Richtung dir? { id } (-1: keins), dazu rollen = dir, wenn die Seite erst
## ein Stück rollen soll (kein Ziel in der Richtung oder nur eines weit hinter langem Text).
## her = { von, nach, dir } – der letzte Sprung: zurück in die Gegenrichtung führt er wieder dorthin, woher
## er kam (hoch aus dem Raster zurück zum selben Link im Kopf, nicht zum nächstbesten).
static func naechstes(alle: Array, von_id: int, dir: String, vw: float, vh: float, her := {}) -> Dictionary:
	var ziele := aktive(alle)
	var von := finde(ziele, von_id)
	if von.is_empty():
		var e := erstes(ziele, vw, vh)
		return { "id": e, "rollen": "" if e >= 0 else dir }
	var r: Rect2 = von.r
	var best := -1
	if not her.is_empty() and int(her.get("nach", -1)) == von_id and str(her.get("dir", "")) == GEGEN.get(dir, ""):
		var zurueck := finde(ziele, int(her.get("von", -1)))
		if not zurueck.is_empty() and wertung(r, zurueck.r, dir) < INF:
			best = int(zurueck.id)
	if best < 0:
		best = bestes(ziele, r, von_id, int(von.bereich), dir)
	if best < 0:
		return { "id": -1, "rollen": dir }
	var best_r: Rect2 = finde(ziele, best).r
	# Langer Text dazwischen: erst lesen lassen (rollen), dann springen.
	if dir in ["down", "up"] and not im_bild(best_r, vw, vh):
		var luecke := (best_r.position.y - r.end.y) if dir == "down" else (r.position.y - best_r.end.y)
		var hinter_rand := (best_r.position.y - vh) if dir == "down" else (-best_r.end.y)
		if luecke > vh * LESEN and hinter_rand > vh * 0.25:
			return { "id": -1, "rollen": dir }
	return { "id": best, "rollen": "" }


## Das beste Ziel von Rechteck r (im Bereich bereich, ohne die Id ohne) in Richtung dir; -1: keins.
## Auch der Zeiger springt damit (browser_zeiger.gd springen).
static func bestes(ziele: Array, r: Rect2, ohne: int, bereich: int, dir: String) -> int:
	var best := -1
	var best_s := INF
	for z in ziele:
		if int(z.id) == ohne:
			continue
		var s := wertung(r, z.r, dir)
		if s == INF:
			continue
		if bereich >= 0 and _gruppe(int(z.bereich)) != _gruppe(bereich):
			s += ANDERER_BEREICH if dir in ["down", "up"] else ANDERER_BEREICH_QUER
		if s < best_s:
			best_s = s
			best = int(z.id)
	return best


## Kopf und Navigation gehören zusammen (die Leiste oben mischt beide): kein Aufpreis dazwischen.
static func _gruppe(b: int) -> int:
	return 0 if b == 1 else b


## Wertung eines Kandidaten c von r aus in Richtung dir (kleiner ist besser, INF: liegt nicht dort).
## Abstand in Richtung + QUER × quer, Überlappung zählt für, große Ziele leicht bevorzugt. Was neben r in
## derselben Zeile (Spalte) liegt, ist nicht „darunter“ (rechts daneben); ein Ziel in r (Knopf in der Karte)
## kommt zuerst, wenn es auf dem Weg hinaus liegt, eines um r herum (die Karte vom Knopf aus), wo sie Platz hat.
static func wertung(r: Rect2, c: Rect2, dir: String) -> float:
	var senk := dir in ["down", "up"]
	if not senk and not dir in ["left", "right"]:
		return INF
	var rc := r.get_center()
	var cc := c.get_center()
	if c.encloses(r) and c != r:
		# Vom Knopf zurück in seine Karte: nur, wo die Karte in der Richtung noch Platz hat (sonst zum Nachbarn).
		var platz := { "down": c.end.y - r.end.y, "up": r.position.y - c.position.y, "right": c.end.x - r.end.x,
			"left": r.position.x - c.position.x }[dir] as float
		return 30.0 if platz >= 24.0 else INF
	if r.encloses(c) and c != r:
		# Liegt der Knopf auf dem Weg hinaus (Mitte in Richtung, nah am Rand, über den es hinausgeht), kommt er zuerst.
		var d := cc - rc
		var weit := { "down": d.y, "up": -d.y, "right": d.x, "left": -d.x }[dir] as float
		if weit <= 1.0:
			return INF
		var bis_rand := { "down": r.end.y - c.end.y, "up": c.position.y - r.position.y, "right": r.end.x - c.end.x,
			"left": c.position.x - r.position.x }[dir] as float
		return maxf(0.0, bis_rand) - 40.0 - minf(sqrt(c.get_area()), 320.0) * GROESSE_BONUS + absf(d.x if senk else d.y) * 0.05
	var haupt := 0.0
	var quer := 0.0
	var ueber := 0.0
	var neben := 0.0
	match dir:
		"down":
			if cc.y <= rc.y + 1.0 or c.end.y <= r.end.y:
				return INF
			haupt = maxf(0.0, c.position.y - r.end.y)
		"up":
			if cc.y >= rc.y - 1.0 or c.position.y >= r.position.y:
				return INF
			haupt = maxf(0.0, r.position.y - c.end.y)
		"right":
			if cc.x <= rc.x + 1.0 or c.end.x <= r.end.x:
				return INF
			haupt = maxf(0.0, c.position.x - r.end.x)
		"left":
			if cc.x >= rc.x - 1.0 or c.position.x >= r.position.x:
				return INF
			haupt = maxf(0.0, r.position.x - c.end.x)
	if senk:
		quer = maxf(0.0, maxf(c.position.x - r.end.x, r.position.x - c.end.x))
		ueber = maxf(0.0, minf(r.end.x, c.end.x) - maxf(r.position.x, c.position.x)) / maxf(1.0, minf(r.size.x, c.size.x))
		neben = maxf(0.0, minf(r.end.y, c.end.y) - maxf(r.position.y, c.position.y)) / maxf(1.0, minf(r.size.y, c.size.y))
	else:
		quer = maxf(0.0, maxf(c.position.y - r.end.y, r.position.y - c.end.y))
		ueber = maxf(0.0, minf(r.end.y, c.end.y) - maxf(r.position.y, c.position.y)) / maxf(1.0, minf(r.size.y, c.size.y))
		neben = maxf(0.0, minf(r.end.x, c.end.x) - maxf(r.position.x, c.position.x)) / maxf(1.0, minf(r.size.x, c.size.x))
	# Zur Hälfte auf gleicher Höhe (Breite): liegt daneben, nicht in der Richtung.
	if neben >= 0.5:
		return INF
	# Seitlich ganz ohne Überlappung (links/rechts in eine andere Zeile): deutlich teurer.
	var s := haupt + quer * QUER - ueber * 40.0
	if ueber <= 0.0 and not senk:
		s += 160.0
	s -= minf(sqrt(c.get_area()), 320.0) * GROESSE_BONUS
	# Bei gleichem Abstand die Mitte, die in Richtung näher liegt (ruhige Spalten).
	s += absf((cc.x - rc.x) if senk else (cc.y - rc.y)) * 0.05
	return s


## Wo der Fokus auf einer neuen Seite beginnt: gemerkte Stelle (Mitte in Seiten-Koordinaten, sy:
## gerollt), sonst das erste große Ziel im Inhalt, das im Bild liegt (Lesereihenfolge), sonst irgendeines
## im Bild, sonst -1.
static func erstes(alle: Array, vw: float, vh: float, gemerkt := Vector2(-1, -1), sy := 0.0) -> int:
	var ziele := aktive(alle)
	if gemerkt.x >= 0.0:
		var p := gemerkt - Vector2(0, sy)
		var best := -1
		var best_d := INF
		for z in ziele:
			var d: float = (z.r as Rect2).get_center().distance_to(p)
			if d < best_d:
				best_d = d
				best = int(z.id)
		if best >= 0 and best_d < maxf(vw, vh):
			return best
	var sicht := in_lesereihe(ziele.filter(func(z: Dictionary) -> bool: return im_bild(z.r, vw, vh)))
	var inhalt := P.BEREICHE.find("inhalt")
	for z in sicht:
		if int(z.bereich) == inhalt and (z.r as Rect2).get_area() >= 1500.0:
			return int(z.id)
	for z in sicht:
		if int(z.bereich) == inhalt:
			return int(z.id)
	return int(sicht[0].id) if not sicht.is_empty() else -1


## Ziele in Lesereihenfolge: Zeile für Zeile von oben, in der Zeile von links; eine Zeile reicht 12 px unter ihr
## oberstes Ziel. Zum Sortieren taugt der paarweise Vergleich (_lesereihe) nicht: Bei versetzten Zielen heißt
## „A vor B“ und „B vor C“ dort nicht immer „A vor C“ – die Reihenfolge wäre dann beliebig.
static func in_lesereihe(ziele: Array) -> Array:
	var nach_y := ziele.duplicate()
	nach_y.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := (a.r as Rect2).position
		var pb := (b.r as Rect2).position
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x))
	var out: Array = []
	var zeile: Array = []
	var oben := 0.0
	for z in nach_y:
		var y := (z.r as Rect2).position.y
		if not zeile.is_empty() and y - oben > 12.0:
			out.append_array(_nach_x(zeile))
			zeile = []
		if zeile.is_empty():
			oben = y
		zeile.append(z)
	out.append_array(_nach_x(zeile))
	return out


static func _nach_x(zeile: Array) -> Array:
	zeile.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := (a.r as Rect2).position
		var pb := (b.r as Rect2).position
		return pa.x < pb.x or (pa.x == pb.x and pa.y < pb.y))
	return zeile


static func _lesereihe(a: Dictionary, b: Dictionary) -> bool:
	var ra: Rect2 = a.r
	var rb: Rect2 = b.r
	if absf(ra.position.y - rb.position.y) > 12.0:
		return ra.position.y < rb.position.y
	return ra.position.x < rb.position.x


## Bereiche der Seite in Lesereihenfolge (nach ihrem obersten, dann linkesten Ziel): [Bereichsnummer].
static func bereiche(ziele: Array) -> Array:
	var erstes_ziel := {}
	for z in ziele:
		var b := int(z.bereich)
		if not erstes_ziel.has(b) or _lesereihe(z, erstes_ziel[b]):
			erstes_ziel[b] = z
	var liste: Array = []
	for z in in_lesereihe(erstes_ziel.values()):
		liste.append(int(z.bereich))
	return liste


## LB/RB: erstes Ziel im vorigen (d = -1) bzw. nächsten (d = 1) Bereich; -1 am Ende (Anstoßen).
## Im Bereich zuerst ein Ziel im Bild, sonst sein oberstes.
static func bereich_sprung(alle: Array, von_id: int, d: int, vw: float, vh: float) -> int:
	var ziele := aktive(alle)
	var liste := bereiche(ziele)
	if liste.is_empty():
		return -1
	var von := finde(ziele, von_id)
	var i := liste.find(int(von.bereich)) if not von.is_empty() else -1
	var j := i + d if i >= 0 else (0 if d > 0 else liste.size() - 1)
	if j < 0 or j >= liste.size():
		return -1
	var drin := ziele.filter(func(z: Dictionary) -> bool: return int(z.bereich) == int(liste[j]))
	drin = in_lesereihe(drin)
	for z in drin:
		if im_bild(z.r, vw, vh):
			return int(z.id)
	return int(drin[0].id)


## Abstand eines Punktes zu einem Rechteck (0: darin).
static func abstand(p: Vector2, r: Rect2) -> float:
	var dx := maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x))
	var dy := maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))
	return sqrt(dx * dx + dy * dy)


## Stelle eines Ziels für „Stelle je Seite“: Mitte in Seiten-Koordinaten.
static func stelle(z: Dictionary, sy: float) -> Vector2:
	return (z.r as Rect2).get_center() + Vector2(0, sy)


## Video-Modus: läuft ein Video groß (Vollbild oder mindestens 40 % des Bildes), wird der
## Controller zur Fernbedienung.
static func video_modus(video: Dictionary, ziele: Array, vw: float, vh: float) -> bool:
	if not bool(video.get("da", false)) or not bool(video.get("laeuft", false)):
		return false
	if bool(video.get("voll", false)):
		return true
	var gross := 0.0
	for z in ziele:
		if z.art == "video":
			gross = maxf(gross, (z.r as Rect2).intersection(Rect2(0, 0, vw, vh)).get_area())
	return gross >= vw * vh * 0.4


## Rechteck aus CSS-Pixeln der Seite in Bildpunkte von Uzais Fenster (die Seite füllt es ganz).
static func auf_schirm(r: Rect2, vw: float, vh: float, schirm: Vector2) -> Rect2:
	var k := Vector2(schirm.x / maxf(vw, 1.0), schirm.y / maxf(vh, 1.0))
	return Rect2(r.position * k, r.size * k)

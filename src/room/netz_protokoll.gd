extends RefCounted
## Nachrichten im Zimmer-Netz, Fassung 2 (Punkt 131; docs/ZIMMER_SICHERHEIT.md W6, docs/PLAN_ZIMMER_ONLINE.md
## Phase 1). Komplett binär: feste Längen, feste Stellen, nur Ganzzahlen mit Wertebereich und
## Kennungen aus festen Listen. Kein Text, keine Namen, kein JSON, keine Godot-Variants – nie
## str_to_var, bytes_to_var, Expression oder ResourceLoader. Alles, was nicht genau passt, wird
## abgelehnt (nicht zurechtgebogen).
##
## Zwei Prüfungen, die zusammen Prüfmauer 2 in Uzai bilden:
##   struktur_ok – Länge, Fassung, Art, jedes Feld im Bereich. Genau dieselben Regeln prüft die
##                 Sandbox als Prüfmauer 1 (helper/uzai-helper.ps1, UzNetzSchema); die Tests
##                 vergleichen beide Seiten an denselben Tausenden Paketen.
##   lesen       – struktur_ok, dann die Bedeutung (Kennungen der Listen, Katalog, Zimmer-Prüfer).
##
## Aufbau (little endian): [0] MAGIC 0x55, [1] VERSION 2, [2] Art, dann je Art fest:
##   1 hallo     8 Byte  [3] Gerät (0 uzai, 1 web), [4..7] Schema-Stempel (u32, muss gleich sein)
##   2 pos      13 Byte  [3] x, [5] y, [7] z in cm (u16: x, z 0..1050, y 0..300),
##                       [9] Blick links/rechts, [11] oben/unten in Milliradiant (s16: ±3142, ±1571)
##   3 emote     4 Byte  [3] Nummer in EMOTES (dieselbe Liste wie figur/avatar.gd)
##   4 satz      4 Byte  [3] Nummer in SAETZE (feste Schnellsätze statt freiem Chat)
##   5 figur     8 Byte  [3] Nummer der Figur, [4..7] je Haustier-Feld die Nummer der Option
##   6 zimmer   32 + 12·n Byte, nur vom Gastgeber: Größe, Boden, vier Wände, Licht, n ≤ 300 Möbel
##                       (Katalog-Nummer, Feld, Drehung, Variante, Stufe, an, eine Farbe)
##   7 tschuess  3 Byte
## Drossel: Token-Eimer je Art und für alle Bytes; wer die Grenzen dauernd reißt, fliegt raus.
## Ohne Fenster und ohne Netz testbar (tests/logic_zimmer_netz.gd, mit Fuzz-Tests).

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")

const VERSION := 2
const MAGIC := 0x55                 ## „U“
const KOPF := 3
const ARTEN := ["", "hallo", "pos", "emote", "satz", "figur", "zimmer", "tschuess"]   ## Nummer = Stelle
const LAENGE := [0, 8, 13, 4, 4, 8, -1, 3]   ## feste Länge je Art (zimmer: aus der Anzahl)
const NUR_VOM_GASTGEBER := ["zimmer"]
const GERAETE := ["uzai", "web"]

## Grenzen der Felder (dieselben Zahlen stehen in UzNetzSchema; der Test vergleicht).
const X_MAX := 1050                 ## cm: größtes Zimmer (20 Felder × 0,5 m) mit Luft
const Y_MAX := 300                  ## cm: bis unter die Decke
const YAW_MAX := 3142               ## Milliradiant (π)
const PITCH_MAX := 1571             ## Milliradiant (π/2)
const ZIMMER_KOPF := 32
const MOEBEL_BYTES := 12
const MAX_MOEBEL := Daten.MAX_MOEBEL
const MAX_VARIANTEN := 16
const MAX_STUFEN := 8
const K_MIN := 1800
const K_MAX := 6500
const H_MAX := 200
const KEINE := 0xFF                 ## Variante/Stufe: Standard des Möbels
const MAX_NACHRICHT := ZIMMER_KOPF + MAX_MOEBEL * MOEBEL_BYTES   ## größte Nachricht überhaupt

## Emotes: genau die der Figur (figur/avatar.gd EMOTES), in dieser Reihenfolge.
static var EMOTES: Array = _ids(Avatar.EMOTES)

## Schnellsätze: feste Kennungen, der Text kommt aus Uzai selbst (übersetzt), nie aus dem Netz.
const SAETZE := [
	["hallo", "Hallo!"], ["willkommen", "Willkommen!"], ["danke", "Danke!"], ["ja", "Ja"], ["nein", "Nein"],
	["moment", "Einen Moment"], ["zimmer", "Schönes Zimmer!"], ["spielen", "Wollen wir was spielen?"],
	["gg", "Gut gespielt!"], ["haha", "Haha"], ["tschuess", "Bis bald!"], ["nacht", "Gute Nacht!"],
]

static var _katalog: Array = []
static var _stempel := -1


static func _ids(liste: Array) -> Array:
	var out: Array = []
	for e in liste:
		out.append(str(e[0]))
	return out


## Katalog-Nummern: die eingebauten Möbel, alphabetisch (eigene Möbel gehen nie ins Netz).
static func katalog() -> Array:
	if _katalog.is_empty():
		_katalog = Katalog.MOEBEL.keys()
		_katalog.sort()
	return _katalog


## Schema-Stempel: SHA-256 über alle Listen, die Nummern bedeuten (Emotes, Sätze, Figur, Katalog,
## Wände, Böden, Licht). Zwei Uzai-Fassungen mit verschiedenen Listen verstehen sich nicht – das
## „hallo“ fällt dann durch, statt dass Nummern Falsches bedeuten.
static func stempel() -> int:
	if _stempel >= 0:
		return _stempel
	var teile: PackedStringArray = ["uzai-zimmer-netz-%d" % VERSION, ",".join(EMOTES), ",".join(_ids(SAETZE))]
	for e in FD.FIGUR_FELDER + FD.TIER_FELDER:
		teile.append(str(e[0]) + ":" + ",".join(_ids(e[3])))
	for id in katalog():
		teile.append(str(id) + ":" + ",".join(_ids(Katalog.varianten(id))) + ":%d" % Katalog.stufen(id).size())
	for l in [G.WANDMATERIAL, G.BODENARTEN, G.ZEITEN, G.WETTER]:
		teile.append(",".join(_ids(l)))
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update("\n".join(teile).to_utf8_buffer())
	_stempel = h.finish().decode_u32(0)
	return _stempel


## Anzahl der Optionen je Figur- und Haustier-Feld (5 Werte, in Byte-Reihenfolge).
static func figur_anzahl() -> Array:
	var out: Array = []
	for e in FD.FIGUR_FELDER + FD.TIER_FELDER:
		out.append((e[3] as Array).size())
	return out


static var _figur_anzahl: Array = figur_anzahl()


# --- Prüfmauer: Aufbau --------------------------------------------------------------------------------

## Stimmt der Aufbau? Nur Länge, Fassung, Art und Wertebereiche – genau wie UzNetzSchema.Pruefen.
static func struktur_ok(b: PackedByteArray, von_gastgeber: bool) -> bool:
	var n := b.size()
	if n < KOPF or n > MAX_NACHRICHT or b[0] != MAGIC or b[1] != VERSION:
		return false
	var art := b[2]
	if art < 1 or art >= ARTEN.size():
		return false
	if ARTEN[art] == "zimmer":
		return von_gastgeber and _zimmer_ok(b)
	if n != int(LAENGE[art]):
		return false
	match art:
		1:
			return b[3] < GERAETE.size()
		2:
			return b.decode_u16(3) <= X_MAX and b.decode_u16(5) <= Y_MAX and b.decode_u16(7) <= X_MAX \
					and absi(b.decode_s16(9)) <= YAW_MAX and absi(b.decode_s16(11)) <= PITCH_MAX
		3:
			return b[3] < EMOTES.size()
		4:
			return b[3] < SAETZE.size()
		5:
			for i in _figur_anzahl.size():
				if b[KOPF + i] >= int(_figur_anzahl[i]):
					return false
			return true
	return true      # tschuess


static func _zimmer_ok(b: PackedByteArray) -> bool:
	var n := b.size()
	if n < ZIMMER_KOPF:
		return false
	var w := b[3]
	var t := b[4]
	if w < Daten.MIN_FELDER or w > Daten.MAX_FELDER or t < Daten.MIN_FELDER or t > Daten.MAX_FELDER:
		return false
	if b[5] >= G.BODENARTEN.size():
		return false
	for k in 4:
		if b[9 + 4 * k] >= G.WANDMATERIAL.size():
			return false
	if b[25] >= G.ZEITEN.size() or b[26] >= G.WETTER.size():
		return false
	var kel := b.decode_u16(27)
	if kel < K_MIN or kel > K_MAX or b[29] > H_MAX:
		return false
	var anzahl := b.decode_u16(30)
	if anzahl > MAX_MOEBEL or n != ZIMMER_KOPF + anzahl * MOEBEL_BYTES:
		return false
	var kat := katalog().size()
	for i in anzahl:
		var o := ZIMMER_KOPF + i * MOEBEL_BYTES
		if b[o] >= kat or b[o + 1] >= w or b[o + 2] >= t or b[o + 3] > 3:
			return false
		if b[o + 4] != KEINE and b[o + 4] >= MAX_VARIANTEN:
			return false
		if b[o + 5] != KEINE and b[o + 5] >= MAX_STUFEN:
			return false
		var fl := b[o + 6]
		if (fl & ~3) != 0:
			return false
		if (fl & 2) == 0 and (b[o + 7] != 0 or b[o + 8] != 0 or b[o + 9] != 0):
			return false
		if b[o + 10] != 0 or b[o + 11] != 0:
			return false
	return true


# --- Lesen (Prüfmauer 2) ---------------------------------------------------------------------------------

## Rohe Bytes → { a: Art, d: geprüfte Felder } oder {} (abgelehnt). von_gastgeber: kommt die
## Nachricht vom Gastgeber (nur der darf ein Zimmer schicken)? Im Ergebnis stehen nur Ganzzahlen
## in ihren Grenzen und Kennungen aus den festen Listen.
static func lesen(b: PackedByteArray, von_gastgeber: bool) -> Dictionary:
	if not struktur_ok(b, von_gastgeber):
		return {}
	var art: String = ARTEN[b[2]]
	match art:
		"hallo":
			if b.decode_u32(4) != stempel():
				return {}
			return { "a": art, "d": { "geraet": GERAETE[b[3]] } }
		"pos":
			return { "a": art, "d": { "x": b.decode_u16(3), "y": b.decode_u16(5), "z": b.decode_u16(7), "yaw": b.decode_s16(9), "pitch": b.decode_s16(11) } }
		"emote":
			return { "a": art, "d": { "id": EMOTES[b[3]] } }
		"satz":
			return { "a": art, "d": { "id": str(SAETZE[b[3]][0]) } }
		"figur":
			return { "a": art, "d": _figur_lesen(b) }
		"zimmer":
			var r := _zimmer_lesen(b)
			return { "a": art, "d": { "raum": r } } if not r.is_empty() else {}
	return { "a": "tschuess", "d": {} }


static func _figur_lesen(b: PackedByteArray) -> Dictionary:
	var f := {}
	var i := KOPF
	for e in FD.FIGUR_FELDER:
		f[str(e[0])] = str(e[3][b[i]][0])
		i += 1
	var t := { "name": FD.TIER_NAME }     # Namen gehen nie übers Netz
	for e in FD.TIER_FELDER:
		t[str(e[0])] = str(e[3][b[i]][0])
		i += 1
	return { "figur": f, "tier": t }


static func _rgb(b: PackedByteArray, o: int) -> String:
	return "#%02x%02x%02x" % [b[o], b[o + 1], b[o + 2]]


## Zimmer: Nummern in Kennungen übersetzen (unbekannte Variante oder Stufe → abgelehnt), dann
## derselbe Prüfer wie für das eigene Zimmer (zimmer_daten.gd → pruefe_raum: Platz, Höchstzahlen).
static func _zimmer_lesen(b: PackedByteArray) -> Dictionary:
	var waende := {}
	for k in 4:
		var o := 9 + 4 * k
		waende[G.SEITEN[k]] = { "m": str(G.WANDMATERIAL[b[o]][0]), "f": _rgb(b, o + 1) }
	var raum := {
		"id": "gast", "name": "Zimmer", "w": b[3], "d": b[4], "waende": waende,
		"boden": { "a": str(G.BODENARTEN[b[5]][0]), "f": _rgb(b, 6) },
		"licht": { "z": str(G.ZEITEN[b[25]][0]), "we": str(G.WETTER[b[26]][0]), "k": b.decode_u16(27), "h": b[29] },
	}
	var moebel: Array = []
	for i in b.decode_u16(30):
		var o := ZIMMER_KOPF + i * MOEBEL_BYTES
		var id: String = katalog()[b[o]]
		var it := { "t": id, "x": b[o + 1], "z": b[o + 2], "r": b[o + 3], "an": (b[o + 6] & 1) != 0 }
		var vl := Katalog.varianten(id)
		if b[o + 4] != KEINE:
			if b[o + 4] >= vl.size():
				return {}
			it["v"] = str(vl[b[o + 4]][0])
		var sl := Katalog.stufen(id)
		if b[o + 5] != KEINE:
			if b[o + 5] >= sl.size():
				return {}
			it["s"] = b[o + 5]
		if (b[o + 6] & 2) != 0:
			it["f"] = _rgb(b, o + 7)
		moebel.append(it)
	raum["moebel"] = moebel
	return Daten.pruefe_raum(raum)


# --- Schreiben ------------------------------------------------------------------------------------------

## Eine Nachricht bauen. Felder wie beim Lesen (pos: Ganzzahlen in cm/Milliradiant; emote, satz:
## Kennung; figur: { figur, tier }; zimmer: { raum }). Was nicht passt, wird gar nicht geschrieben
## (leer) – und was geschrieben wird, liest die Gegenseite genauso (Probe mit dem eigenen Leser).
static func schreiben(art: String, d: Dictionary = {}) -> PackedByteArray:
	var nr := ARTEN.find(art)
	if nr < 1:
		return PackedByteArray()
	var b := PackedByteArray()
	b.resize(ZIMMER_KOPF if art == "zimmer" else int(LAENGE[nr]))
	b[0] = MAGIC
	b[1] = VERSION
	b[2] = nr
	match art:
		"hallo":
			var g := GERAETE.find(d.get("geraet"))
			if g < 0:
				return PackedByteArray()
			b[3] = g
			b.encode_u32(4, stempel())
		"pos":
			var werte: Array = []
			for k in ["x", "y", "z", "yaw", "pitch"]:
				if not (d.get(k) is int):
					return PackedByteArray()
				werte.append(int(d[k]))
			if werte[0] < 0 or werte[0] > X_MAX or werte[1] < 0 or werte[1] > Y_MAX or werte[2] < 0 or werte[2] > X_MAX \
					or absi(werte[3]) > YAW_MAX or absi(werte[4]) > PITCH_MAX:
				return PackedByteArray()
			b.encode_u16(3, werte[0])
			b.encode_u16(5, werte[1])
			b.encode_u16(7, werte[2])
			b.encode_s16(9, werte[3])
			b.encode_s16(11, werte[4])
		"emote", "satz":
			var i := (EMOTES if art == "emote" else _ids(SAETZE)).find(d.get("id"))
			if i < 0:
				return PackedByteArray()
			b[3] = i
		"figur":
			var f := FD.pruefe_figur(d.get("figur"))
			var t := FD.pruefe_tier(d.get("tier"))
			var i := KOPF
			for e in FD.FIGUR_FELDER:
				b[i] = _ids(e[3]).find(f[str(e[0])])
				i += 1
			for e in FD.TIER_FELDER:
				b[i] = _ids(e[3]).find(t[str(e[0])])
				i += 1
		"zimmer":
			if not _zimmer_schreiben(b, d.get("raum")):
				return PackedByteArray()
	return b if lesen(b, true).size() == 2 else PackedByteArray()


static func _rgb_schreiben(b: PackedByteArray, o: int, hex: Variant) -> void:
	var s := G.farbe(hex)
	if s == "":
		return
	b[o] = s.substr(1, 2).hex_to_int()
	b[o + 1] = s.substr(3, 2).hex_to_int()
	b[o + 2] = s.substr(5, 2).hex_to_int()


static func _zimmer_schreiben(b: PackedByteArray, v: Variant) -> bool:
	var raum := Daten.pruefe_raum(v)
	if raum.is_empty():
		return false
	b[3] = int(raum.w)
	b[4] = int(raum.d)
	b[5] = maxi(0, _ids(G.BODENARTEN).find(raum.boden.a))
	_rgb_schreiben(b, 6, raum.boden.f)
	for k in 4:
		var wd: Dictionary = raum.waende[G.SEITEN[k]]
		b[9 + 4 * k] = maxi(0, _ids(G.WANDMATERIAL).find(wd.m))
		_rgb_schreiben(b, 10 + 4 * k, wd.f)
	b[25] = maxi(0, _ids(G.ZEITEN).find(raum.licht.z))
	b[26] = maxi(0, _ids(G.WETTER).find(raum.licht.we))
	b.encode_u16(27, clampi(int(raum.licht.k), K_MIN, K_MAX))
	b[29] = clampi(int(raum.licht.h), 0, H_MAX)
	var liste: Array = []
	for it in raum.moebel:
		var i := katalog().find(str(it.t))
		if i >= 0:      # eigene Möbel bleiben zu Hause
			liste.append([i, it])
	liste = liste.slice(0, MAX_MOEBEL)
	b.encode_u16(30, liste.size())
	for e in liste:
		var it: Dictionary = e[1]
		var id := str(it.t)
		var m := PackedByteArray()
		m.resize(MOEBEL_BYTES)
		m[0] = e[0]
		m[1] = int(it.x)
		m[2] = int(it.z)
		m[3] = int(it.r)
		var vi := _ids(Katalog.varianten(id)).find(str(it.get("v", "")))
		m[4] = vi if vi >= 0 and vi < MAX_VARIANTEN else KEINE
		m[5] = int(it.s) if it.get("s") is int and int(it.s) >= 0 and int(it.s) < mini(MAX_STUFEN, Katalog.stufen(id).size()) else KEINE
		m[6] = 1 if bool(it.get("an", true)) else 0
		if G.farbe(it.get("f")) != "":
			m[6] |= 2
			_rgb_schreiben(m, 7, it.f)
		b.append_array(m)
	return true


## Position aus der Welt (Meter, Bogenmaß) → Felder für „pos“, in die Grenzen gelegt.
static func pos_aus(p: Vector3, yaw: float, pitch: float) -> Dictionary:
	var w := wrapf(yaw, -PI, PI)
	return {
		"x": clampi(roundi(p.x * 100.0), 0, X_MAX), "y": clampi(roundi(p.y * 100.0), 0, Y_MAX), "z": clampi(roundi(p.z * 100.0), 0, X_MAX),
		"yaw": clampi(roundi(w * 1000.0), -YAW_MAX, YAW_MAX), "pitch": clampi(roundi(pitch * 1000.0), -PITCH_MAX, PITCH_MAX),
	}


## Gelesene „pos“ → Ort in Metern.
static func pos_welt(d: Dictionary) -> Vector3:
	return Vector3(int(d.x) / 100.0, int(d.y) / 100.0, int(d.z) / 100.0)


static func satz_text(id: String) -> String:
	for s in SAETZE:
		if str(s[0]) == id:
			return str(s[1])
	return ""


# --- Drossel --------------------------------------------------------------------------------------

## Grenzen je Gast: [Nachrichten je Sekunde, Vorrat]. Dazu alle Bytes zusammen. Dieselben Zahlen
## gelten in der Sandbox (UzNetzSchema.RATE/VORRAT; der Test vergleicht).
const RATEN := {
	"hallo": [0.1, 2.0], "pos": [30.0, 40.0], "emote": [2.0, 4.0], "satz": [0.5, 4.0],
	"figur": [0.2, 3.0], "zimmer": [0.5, 2.0], "tschuess": [1.0, 1.0],
}
const BYTES_JE_SEKUNDE := 16.0 * 1024.0
const BYTES_VORRAT := 32.0 * 1024.0
const VERSTOESSE_RAUS := 25.0       ## so viele abgelehnte Nachrichten (die je Sekunde eine verfallen)


## Token-Eimer je Gast. jetzt in Sekunden (von außen, damit Tests die Zeit vorgeben).
class Drossel:
	var eimer := {}
	var bytes := BYTES_VORRAT
	var verstoesse := 0.0
	var zuletzt := -1.0

	func _nachfuellen(jetzt: float) -> void:
		if zuletzt < 0.0:
			zuletzt = jetzt
		var dt := clampf(jetzt - zuletzt, 0.0, 60.0)
		zuletzt = maxf(zuletzt, jetzt)
		for art in RATEN.keys():
			var r: Array = RATEN[art]
			eimer[art] = minf(float(r[1]), float(eimer.get(art, r[1])) + dt * float(r[0]))
		bytes = minf(BYTES_VORRAT, bytes + dt * BYTES_JE_SEKUNDE)
		verstoesse = maxf(0.0, verstoesse - dt)

	## Darf diese Nachricht (Art, Größe) jetzt durch? Verbraucht Vorrat; sonst zählt ein Verstoß.
	func erlaubt(art: String, groesse: int, jetzt: float) -> bool:
		_nachfuellen(jetzt)
		if not RATEN.has(art) or float(eimer[art]) < 1.0 or bytes < groesse:
			verstoss()
			return false
		eimer[art] = float(eimer[art]) - 1.0
		bytes -= groesse
		return true

	## Auch abgelehnte Nachrichten zählen.
	func verstoss() -> void:
		verstoesse += 1.0

	func rauswerfen() -> bool:
		return verstoesse >= VERSTOESSE_RAUS

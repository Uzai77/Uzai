extends Node
## Zimmer online (Punkt 131; docs/ZIMMER_SICHERHEIT.md, docs/PLAN_ZIMMER_ONLINE.md Phase 1 und 2):
## Protokoll Fassung 2 (binär, feste Längen, Wertebereiche) mit Fuzz-Tests, Abgleich mit der
## Sandbox (gleiche Zahlen, gleiches Urteil über dieselben Pakete), Drossel, die Leitung zur Sandbox
## mit Prüfmauer 2, ein Lauf gegen die echte Prüfmauer 1 über eine Pipe (PowerShell 7, wenn
## UZAI_PWSH gesetzt ist), Einladung, Gastgeber-Logik und dass nichts davon fremde Daten ausführt
## oder online geht.
## Aufruf: godot --headless --path . res://tests/logic_zimmer_netz.tscn

const P := preload("res://src/room/netz_protokoll.gd")
const ZN := preload("res://src/room/zimmer_netz.gd")
const Einladung := preload("res://src/room/einladung.gd")
const Online := preload("res://src/room/online.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Avatar := preload("res://src/room/figur/avatar.gd")

## Gleiche Pakete wie in tests/zimmer_sandbox_cs.ps1 (Abgleich der beiden Prüfmauern): Grundformen
## als Hex, ein Zufallsgenerator (xorshift32) mit fester Saat, ein Fingerabdruck der Urteile.
const VEKTOR_BASIS := [
	"5502010078563412",
	"55020240010000c20150fb2c01",
	"55020302",
	"55020408",
	"5502050101010101",
	"550207",
	"5502060c0a00c2946600e8e0d100e8e0d100e8e0d100e8e0d100008c0a640200000101" + "00ffff010000000000" + "05030201" + "00ff031122330000",
]
const VEKTOR_GRENZEN := [0, 1, 2, 3, 299, 300, 301, 1050, 1051, 1571, 1572, 3142, 3143, 1799, 1800, 6500, 6501, 65535 - 3142, 65535 - 3141,
		65535 - 1570, 65535 - 1571, 32768, 65535]
const VEKTOR_SAAT := 0x13112026
const VEKTOR_ANZAHL := 6000
const VEKTOR_SOLL := "0x953b7a7c/917"   ## Fingerabdruck/angenommen, steht genauso in der PowerShell-Probe

var fails := 0
var rng := RandomNumberGenerator.new()
var _xs := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var seed_ := int(OS.get_environment("UZAI_FUZZ_SEED")) if OS.get_environment("UZAI_FUZZ_SEED") != "" else 131
	rng.seed = seed_
	print("Zufalls-Saat: %d" % seed_)
	_lesen_schreiben()
	_streng()
	_abgleich()
	_vektoren()
	_fuzz()
	_drossel()
	_leitung()
	await _sandbox_pipe()
	_einladung()
	_gastgeber()
	_quelltext()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## Hält ein Ergebnis des Lesers das Schema ein? (leer = abgelehnt, auch in Ordnung)
func _schema_ok(m: Dictionary, von_gastgeber: bool) -> bool:
	if m.is_empty():
		return true
	if m.size() != 2 or not (m.get("a") in P.ARTEN) or str(m.a) == "" or not (m.get("d") is Dictionary):
		return false
	var d: Dictionary = m.d
	match str(m.a):
		"hallo":
			return d.keys() == ["geraet"] and d.geraet in P.GERAETE
		"pos":
			if d.keys() != ["x", "y", "z", "yaw", "pitch"]:
				return false
			for k in d.keys():
				if not (d[k] is int):
					return false
			return d.x >= 0 and d.x <= P.X_MAX and d.y >= 0 and d.y <= P.Y_MAX and d.z >= 0 and d.z <= P.X_MAX \
					and absi(d.yaw) <= P.YAW_MAX and absi(d.pitch) <= P.PITCH_MAX
		"emote":
			return d.keys() == ["id"] and d.id in Avatar.EMOTES.map(func(e: Array) -> String: return str(e[0]))
		"satz":
			return d.keys() == ["id"] and P.satz_text(str(d.id)) != ""
		"figur":
			if d.keys() != ["figur", "tier"] or not (d.figur is Dictionary) or not (d.tier is Dictionary):
				return false
			for e in FD.FIGUR_FELDER:
				if not (d.figur.get(e[0]) is String) or not FD.gueltig(e[3], d.figur[e[0]]):
					return false
			for e in FD.TIER_FELDER:
				if not (d.tier.get(e[0]) is String) or not FD.gueltig(e[3], d.tier[e[0]]):
					return false
			return d.figur.size() == FD.FIGUR_FELDER.size() and d.tier.size() == FD.TIER_FELDER.size() + 1 and d.tier.name == FD.TIER_NAME
		"zimmer":
			if not von_gastgeber or d.keys() != ["raum"]:
				return false
			var r: Dictionary = d.raum
			if str(r.id) != "gast" or str(r.name) != "Zimmer" or (r.moebel as Array).size() > Daten.MAX_MOEBEL:
				return false
			for it in r.moebel:
				if not (str(it.t) in P.katalog()):
					return false
			return Daten.pruefe_raum(r) == r
		"tschuess":
			return d.is_empty()
	return false


func _hex(s: String) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(0, s.length(), 2):
		b.append(s.substr(i, 2).hex_to_int())
	return b


# --- Lesen und Schreiben ---------------------------------------------------------------------------

func _lesen_schreiben() -> void:
	print("Schreiben und wieder lesen")
	var pos := P.schreiben("pos", { "x": 325, "y": 0, "z": 750, "yaw": -1200, "pitch": 300 })
	check(pos.size() == 13 and pos[0] == P.MAGIC and pos[1] == 2 and pos[2] == 2, "Position: 13 Byte, Kopf U, Fassung 2, Art 2")
	check(P.lesen(pos, false).d == { "x": 325, "y": 0, "z": 750, "yaw": -1200, "pitch": 300 }, "Position kommt genau als Ganzzahlen zurück")
	var welt := P.pos_aus(Vector3(3.254, 0.0, 7.5), -1.2, 0.3)
	check(welt == { "x": 325, "y": 0, "z": 750, "yaw": -1200, "pitch": 300 } and P.pos_welt(welt).is_equal_approx(Vector3(3.25, 0, 7.5)),
			"Welt ↔ Zentimeter und Milliradiant")
	check(P.pos_aus(Vector3(-5, 99, 50), 7.0, -9.0).x == 0 and P.pos_aus(Vector3(-5, 99, 50), 7.0, -9.0).z == P.X_MAX
			and P.pos_aus(Vector3(-5, 99, 50), 7.0, -9.0).pitch == -P.PITCH_MAX, "pos_aus legt alles in die Grenzen")
	var faelle := [
		["hallo", { "geraet": "web" }, 8], ["emote", { "id": "winken" }, 4], ["satz", { "id": "gg" }, 4], ["tschuess", {}, 3],
	]
	for f in faelle:
		var b := P.schreiben(f[0], f[1])
		var m := P.lesen(b, false)
		check(b.size() == f[2] and m.get("a") == f[0] and m.d == f[1], "%s: %d Byte, geschrieben und unverändert gelesen" % [f[0], f[2]])
	var fig := { "figur": { "person": "nora" }, "tier": { "art": "drache", "name": "Funke" } }
	var fb := P.schreiben("figur", fig)
	var fm := P.lesen(fb, false)
	check(fb.size() == 8 and fm.d.figur == FD.pruefe_figur(fig.figur) and str(fm.d.tier.art) == "drache",
			"Figur: 8 Byte, Figur und Haustier kommen an")
	check(str(fm.d.tier.name) == FD.TIER_NAME, "Figur: der Name des Haustiers geht nicht übers Netz")
	var raum := Daten.standard_raum()
	raum.moebel[0]["f"] = "#123456"
	raum.waende.links.f = "#abcdef"
	raum.licht.k = 4100
	var zb := P.schreiben("zimmer", { "raum": raum })
	var zm := P.lesen(zb, true)
	check(zb.size() == P.ZIMMER_KOPF + 12 * (raum.moebel as Array).size(), "Standardzimmer: %d Byte (Kopf + 12 je Möbel)" % zb.size())
	var gleich: bool = zm.get("a") == "zimmer" and (zm.d.raum.moebel as Array).size() == (raum.moebel as Array).size()
	if gleich:
		for i in (raum.moebel as Array).size():
			var a: Dictionary = raum.moebel[i]
			var b: Dictionary = zm.d.raum.moebel[i]
			gleich = gleich and a.t == b.t and a.x == b.x and a.z == b.z and a.r == b.r and a.v == b.v and a.get("f") == b.get("f")
	check(gleich and zm.d.raum.waende.links.f == "#abcdef" and int(zm.d.raum.licht.k) == 4100 and zm.d.raum.w == 12,
			"Zimmer vom Gastgeber: Möbel, Wände, Licht kommen genau an")
	check(P.lesen(zb, false).is_empty(), "ein Gast darf kein Zimmer schicken")
	var eigen := Daten.standard_raum()
	eigen.moebel.append({ "t": "eigen_1", "x": 6, "z": 6, "r": 0 })
	check((P.lesen(P.schreiben("zimmer", { "raum": eigen }), true).d.raum.moebel as Array).size() == (Daten.standard_raum().moebel as Array).size(),
			"eigene Möbel bleiben zu Hause")
	for falsch in [["pos", { "x": 1.5, "y": 0, "z": 2, "yaw": 0, "pitch": 0 }], ["pos", { "x": -1, "y": 0, "z": 2, "yaw": 0, "pitch": 0 }],
			["pos", { "x": 1, "z": 2, "yaw": 0, "pitch": 0 }], ["emote", { "id": "herz" }], ["satz", { "id": "Hallo!" }], ["hallo", { "geraet": "admin" }],
			["chat", { "text": "hi" }], ["befehl", {}], ["", {}], ["zimmer", { "raum": { "id": "x" } }]]:
		if not P.schreiben(falsch[0], falsch[1]).is_empty():
			check(false, "falsch geschrieben: %s" % str(falsch))
	check(true, "Schreiber prüft wie der Leser: Kommazahl, außerhalb, fehlendes Feld, unbekanntes Emote/Satz/Gerät, Chat, unbekannte Art")
	check(not ("chat" in P.ARTEN) and P.ARTEN.size() == 8, "kein freier Chat mehr im Protokoll")
	check(P.MAX_NACHRICHT == 32 + 300 * 12, "größte Nachricht: %d Byte (Zimmer mit 300 Möbeln)" % P.MAX_NACHRICHT)


# --- Strenge Prüfung -------------------------------------------------------------------------------

func _ersetzt(b: PackedByteArray, at: int, wert: int) -> PackedByteArray:
	var c := b.duplicate()
	c[at] = wert
	return c


func _u16(b: PackedByteArray, at: int, wert: int) -> PackedByteArray:
	var c := b.duplicate()
	c.encode_u16(at, wert)
	return c


func _s16(b: PackedByteArray, at: int, wert: int) -> PackedByteArray:
	var c := b.duplicate()
	c.encode_s16(at, wert)
	return c


func _streng() -> void:
	print("Strenge Prüfung")
	var pos := P.schreiben("pos", { "x": 100, "y": 0, "z": 100, "yaw": 0, "pitch": 0 })
	check(P.struktur_ok(pos, false), "gültige Position")
	check(not P.struktur_ok(_ersetzt(pos, 0, 0x7B), false) and not P.struktur_ok(_ersetzt(pos, 1, 1), false) and not P.struktur_ok(_ersetzt(pos, 1, 3), false),
			"falscher Kopf, alte und neuere Fassung: abgelehnt")
	for a in [0, 8, 9, 0x7F, 0xFF]:
		if P.struktur_ok(_ersetzt(pos, 2, a), true):
			check(false, "unbekannte Art %d" % a)
	check(true, "unbekannte Arten (0, 8, 9, 127, 255): abgelehnt")
	var lang := pos.duplicate()
	lang.append(0)
	check(not P.struktur_ok(pos.slice(0, 12), false) and not P.struktur_ok(lang, false) and not P.struktur_ok(PackedByteArray(), false),
			"abgeschnitten, ein Byte zu viel, leer: abgelehnt")
	check(P.struktur_ok(_u16(pos, 3, P.X_MAX), false) and not P.struktur_ok(_u16(pos, 3, P.X_MAX + 1), false), "x: 1050 ja, 1051 nein")
	check(P.struktur_ok(_u16(pos, 5, P.Y_MAX), false) and not P.struktur_ok(_u16(pos, 5, P.Y_MAX + 1), false), "y: 300 ja, 301 nein")
	check(P.struktur_ok(_s16(pos, 9, -P.YAW_MAX), false) and not P.struktur_ok(_s16(pos, 9, -P.YAW_MAX - 1), false)
			and not P.struktur_ok(_s16(pos, 9, -32768), false), "Blick: ±3142 ja, darüber und −32768 nein")
	check(P.struktur_ok(_s16(pos, 11, P.PITCH_MAX), false) and not P.struktur_ok(_s16(pos, 11, P.PITCH_MAX + 1), false), "Neigung: ±1571")
	var em := P.schreiben("emote", { "id": "winken" })
	check(P.struktur_ok(_ersetzt(em, 3, 6), false) and not P.struktur_ok(_ersetzt(em, 3, 7), false), "Emote: nur Nummern 0–6 (7 Emotes der Figur)")
	var sz := P.schreiben("satz", { "id": "hallo" })
	check(P.struktur_ok(_ersetzt(sz, 3, 11), false) and not P.struktur_ok(_ersetzt(sz, 3, 12), false), "Schnellsatz: nur Nummern 0–11")
	var fig := P.schreiben("figur", { "figur": {}, "tier": {} })
	var fz := P.figur_anzahl()
	var alle_grenzen := true
	for i in fz.size():
		alle_grenzen = alle_grenzen and P.struktur_ok(_ersetzt(fig, 3 + i, fz[i] - 1), false) and not P.struktur_ok(_ersetzt(fig, 3 + i, fz[i]), false)
	check(alle_grenzen, "Figur: jedes der 5 Felder genau bis zur letzten Option")
	var hallo := P.schreiben("hallo", { "geraet": "uzai" })
	check(not P.struktur_ok(_ersetzt(hallo, 3, 2), false), "hallo: unbekanntes Gerät abgelehnt")
	var fremd := hallo.duplicate()
	fremd.encode_u32(4, P.stempel() ^ 1)
	check(P.struktur_ok(fremd, false) and P.lesen(fremd, false).is_empty(), "hallo mit fremdem Schema-Stempel: Aufbau stimmt, Uzai lehnt ab")
	# Zimmer: jeder Wert im Kopf und in den Möbeln.
	var z := P.schreiben("zimmer", { "raum": Daten.standard_raum() })
	check(P.struktur_ok(z, true) and not P.struktur_ok(z, false), "Zimmer nur vom Gastgeber")
	var kopf_falsch := [
		_ersetzt(z, 3, 7), _ersetzt(z, 3, 21), _ersetzt(z, 4, 7), _ersetzt(z, 5, G.BODENARTEN.size()), _ersetzt(z, 9, G.WANDMATERIAL.size()),
		_ersetzt(z, 21, G.WANDMATERIAL.size()), _ersetzt(z, 25, 5), _ersetzt(z, 26, 5), _u16(z, 27, 1799), _u16(z, 27, 6501), _ersetzt(z, 29, 201),
		_u16(z, 30, z.decode_u16(30) + 1), _u16(z, 30, z.decode_u16(30) - 1), _u16(z, 30, 301), z.slice(0, z.size() - 1),
	]
	var abgelehnt := 0
	for b in kopf_falsch:
		if not P.struktur_ok(b, true):
			abgelehnt += 1
	check(abgelehnt == kopf_falsch.size(), "Zimmer-Kopf: Größe, Boden, Wände, Zeit, Wetter, Kelvin, Helligkeit, Anzahl (%d/%d)" % [abgelehnt, kopf_falsch.size()])
	var o := P.ZIMMER_KOPF
	var moebel_falsch := [
		_ersetzt(z, o, P.katalog().size()), _ersetzt(z, o + 1, int(z[3])), _ersetzt(z, o + 2, int(z[4])), _ersetzt(z, o + 3, 4),
		_ersetzt(z, o + 4, 16), _ersetzt(z, o + 5, 8), _ersetzt(z, o + 6, 4), _ersetzt(_ersetzt(z, o + 6, 1), o + 8, 9), _ersetzt(z, o + 10, 1),
		_ersetzt(z, o + 11, 0x80),
	]
	abgelehnt = 0
	for b in moebel_falsch:
		if not P.struktur_ok(b, true):
			abgelehnt += 1
	check(abgelehnt == moebel_falsch.size(), "Möbel: Katalog, Feld, Drehung, Variante, Stufe, Merkmale, Farbe ohne Merkmal, Reserve (%d/%d)" % [abgelehnt, moebel_falsch.size()])
	# Aufbau stimmt, Bedeutung nicht: nur Prüfmauer 2 (Uzai) kennt die Listen je Möbel.
	var teppich := P.katalog().find("teppich")
	var zv := _ersetzt(_ersetzt(z, o, teppich), o + 4, 15)
	check(P.struktur_ok(zv, true) and P.lesen(zv, true).is_empty(), "Variante, die das Möbel nicht hat: Aufbau ok, Uzai lehnt ab")
	var ohne_stufen := ""
	for id in P.katalog():
		if Katalog.stufen(id).is_empty():
			ohne_stufen = id
			break
	var zs := _ersetzt(_ersetzt(_ersetzt(z, o, P.katalog().find(ohne_stufen)), o + 4, P.KEINE), o + 5, 0)
	check(P.struktur_ok(zs, true) and P.lesen(zs, true).is_empty(), "Stufe bei einem Möbel ohne Stufen (%s): abgelehnt" % ohne_stufen)
	# Fremde Formate werden nie gelesen.
	check(P.lesen(var_to_bytes({ "a": "satz", "d": { "id": "gg" } }), false).is_empty(), "Godot-Variant-Bytes (var_to_bytes): abgelehnt")
	check(P.lesen("Object(Script,\"script/source\":\"extends Node\")".to_utf8_buffer(), false).is_empty(), "str_to_var-Text: abgelehnt")
	check(P.lesen("{\"v\":1,\"a\":\"chat\",\"d\":{\"text\":\"hi\"}}".to_utf8_buffer(), false).is_empty(), "alte JSON-Nachricht (Chat): abgelehnt")
	var riesig := PackedByteArray()
	riesig.resize(4 * 1024 * 1024)
	riesig.fill(P.MAGIC)
	riesig[1] = 2
	riesig[2] = 6
	var t0 := Time.get_ticks_usec()
	check(P.lesen(riesig, true).is_empty(), "4 MiB: gar nicht erst gelesen")
	check(Time.get_ticks_usec() - t0 < 20000, "übergroße Daten kosten keine Zeit (%d µs)" % (Time.get_ticks_usec() - t0))
	var voll := P.schreiben("zimmer", { "raum": Daten.standard_raum() }).slice(0, P.ZIMMER_KOPF)
	voll.encode_u16(30, 300)
	for i in 300:
		voll.append_array(PackedByteArray([0, i % 8, int(i / 8.0) % 8, 0, P.KEINE, P.KEINE, 1, 0, 0, 0, 0, 0]))
	t0 = Time.get_ticks_usec()
	var vr := P.lesen(voll, true)
	check(voll.size() == P.MAX_NACHRICHT and P.struktur_ok(voll, true) and _schema_ok(vr, true), "größtes Zimmer (300 Möbel, %d Byte) wird geprüft" % voll.size())
	print("    (%d µs)" % (Time.get_ticks_usec() - t0))
	var zu_gross := voll.duplicate()
	zu_gross.append_array(voll.slice(P.ZIMMER_KOPF, P.ZIMMER_KOPF + 12))
	zu_gross.encode_u16(30, 301)
	check(not P.struktur_ok(zu_gross, true), "301 Möbel: abgelehnt")


# --- Abgleich mit der Sandbox ---------------------------------------------------------------------

## Eine Ganzzahl-Konstante aus der C#-Quelle („NAME = 123“).
func _cs_zahl(cs: String, name: String) -> int:
	var re := RegEx.create_from_string("\\b" + name + " = (0x[0-9A-Fa-f]+|\\d+)")
	var m := re.search(cs)
	if m == null:
		return -999999
	var s := m.get_string(1)
	return s.hex_to_int() if s.begins_with("0x") else int(s)


## Eine Zahlenliste aus der C#-Quelle („NAME = { 1, 2.5 }“).
func _cs_liste(cs: String, name: String) -> Array:
	var re := RegEx.create_from_string("\\b" + name + " = \\{ ([^}]*) \\}")
	var m := re.search(cs)
	if m == null:
		return []
	var out: Array = []
	for t in m.get_string(1).split(","):
		out.append(float(t.strip_edges()))
	return out


func _abgleich() -> void:
	print("Abgleich mit der Sandbox (helper/uzai-helper.ps1)")
	var src := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var a := src.find("$script:ZimmerNetzSrc = @'")
	var cs := src.substr(a, src.find("\n'@", a) - a)
	check(a >= 0 and cs.length() > 10000, "Quelle der Sandbox gefunden")
	var emote_ids: Array = Avatar.EMOTES.map(func(e: Array) -> String: return str(e[0]))
	check(P.EMOTES == emote_ids and P.EMOTES.size() == 7, "Emotes im Netz = Emotes der Figur (%s)" % ", ".join(P.EMOTES))
	var zahlen := {
		"VERSION": P.VERSION, "MAGIC": P.MAGIC, "GERAETE": P.GERAETE.size(), "EMOTES": P.EMOTES.size(), "SAETZE": P.SAETZE.size(),
		"KATALOG": P.katalog().size(), "WANDMATERIAL": G.WANDMATERIAL.size(), "BODENARTEN": G.BODENARTEN.size(), "ZEITEN": G.ZEITEN.size(),
		"WETTER": G.WETTER.size(), "X_MAX": P.X_MAX, "Y_MAX": P.Y_MAX, "YAW_MAX": P.YAW_MAX, "PITCH_MAX": P.PITCH_MAX, "K_MIN": P.K_MIN,
		"K_MAX": P.K_MAX, "H_MAX": P.H_MAX, "MIN_FELDER": Daten.MIN_FELDER, "MAX_FELDER": Daten.MAX_FELDER, "MAX_MOEBEL": P.MAX_MOEBEL,
		"MAX_VARIANTEN": P.MAX_VARIANTEN, "MAX_STUFEN": P.MAX_STUFEN, "KEINE": P.KEINE, "ZIMMER_KOPF": P.ZIMMER_KOPF, "MOEBEL_BYTES": P.MOEBEL_BYTES,
		"HALLO": 1, "POS": 2, "EMOTE": 3, "SATZ": 4, "FIGUR": 5, "ZIMMER": 6, "TSCHUESS": 7, "ARTEN": P.ARTEN.size(),
		"BYTES_JE_SEKUNDE": int(P.BYTES_JE_SEKUNDE), "BYTES_VORRAT": int(P.BYTES_VORRAT), "VERSTOESSE_RAUS": int(P.VERSTOESSE_RAUS),
		"PING": ZN.PING, "PONG": ZN.PONG, "ENDE": ZN.ENDE, "SENDEN": ZN.SENDEN, "EMPFANGEN": ZN.EMPFANGEN, "TEST_REIN": ZN.TEST_REIN,
		"TEST_RAUS": ZN.TEST_RAUS, "RAUS": ZN.RAUS, "ZAEHLER": ZN.ZAEHLER, "SCHLIESSEN": ZN.SCHLIESSEN, "MAX": ZN.MAX_RAHMEN, "SLOTS": ZN.PLAETZE,
		"TREFF": ZN.TREFF, "EINLADUNG": ZN.EINLADUNG, "ZURUECK": ZN.ZURUECK, "BESUCH": ZN.BESUCH, "KLOPFT": ZN.KLOPFT, "ENTSCHEID": ZN.ENTSCHEID,
		"STAND": ZN.STAND, "TREFF_ZAEHLER": ZN.TREFF_ZAEHLER, "ST_RELAYS": 1, "ST_VERBUNDEN": ZN.STAENDE.find("verbunden"), "ST_ZU": ZN.STAENDE.find("zu"),
		"ST_SIGNATUR_FEHLT": ZN.STAENDE.find("signatur_fehlt"), "ST_GESCHEITERT": ZN.STAENDE.find("gescheitert"),
		"ST_DIREKT_FEHLT": ZN.STAENDE.find("direkt_fehlt"),
	}
	var falsch: Array = []
	for k in zahlen.keys():
		if _cs_zahl(cs, k) != int(zahlen[k]):
			falsch.append("%s (Uzai %d, Sandbox %d)" % [k, zahlen[k], _cs_zahl(cs, k)])
	check(falsch.is_empty(), "%d Zahlen gleich in Uzai und Sandbox %s" % [zahlen.size(), str(falsch) if not falsch.is_empty() else ""])
	check(_cs_liste(cs, "LAENGE") == P.LAENGE.map(func(v: int) -> float: return float(v)), "Längen je Art gleich")
	check(_cs_liste(cs, "FIGUR_ANZAHL") == P.figur_anzahl().map(func(v: int) -> float: return float(v)), "Optionen je Figur-Feld gleich (5 Felder)")
	var rate: Array = [0.0]
	var vorrat: Array = [0.0]
	for art in P.ARTEN.slice(1):
		rate.append(float(P.RATEN[art][0]))
		vorrat.append(float(P.RATEN[art][1]))
	check(_cs_liste(cs, "RATE") == rate and _cs_liste(cs, "VORRAT") == vorrat, "Drossel je Art gleich")
	check(ZN.PLAETZE == Online.MAX_GAESTE_GRENZE, "ein Platz je Gast (höchstens 8)")
	check(P.MAX_NACHRICHT + 1 < ZN.MAX_RAHMEN, "jede Nachricht passt mit Platz in einen Rahmen")


# --- Gleiche Pakete, gleiches Urteil ---------------------------------------------------------------

func _xn() -> int:
	_xs ^= (_xs << 13) & 0xFFFFFFFF
	_xs ^= _xs >> 17
	_xs ^= (_xs << 5) & 0xFFFFFFFF
	return _xs


## Dieselben Pakete erzeugt tests/zimmer_sandbox_cs.ps1 in C# (gleiche Reihenfolge der Zufallszahlen).
func _vektor_urteile() -> String:
	_xs = VEKTOR_SAAT
	var basis: Array = []
	for h in VEKTOR_BASIS:
		basis.append(_hex(h))
	var h := 2166136261
	var an := 0
	for i in VEKTOR_ANZAHL:
		var b := PackedByteArray()
		match _xn() % 8:
			0:
				var n := _xn() % 40
				for k in n:
					b.append(_xn() & 0xFF)
			1:
				var n := 3 + _xn() % 40
				b.resize(n)
				b[0] = P.MAGIC
				b[1] = P.VERSION
				b[2] = _xn() % 9
				for k in range(3, n):
					b[k] = _xn() & 0xFF
			2:
				b = (basis[_xn() % basis.size()] as PackedByteArray).duplicate()
				for k in 1 + _xn() % 3:
					var at := _xn() % b.size()
					b[at] = b[at] ^ (1 << (_xn() % 8))
			3:
				b = basis[_xn() % basis.size()]
				b = b.slice(0, _xn() % b.size())
			4:
				b = (basis[_xn() % basis.size()] as PackedByteArray).duplicate()
				b.append(_xn() & 0xFF)
			5:
				b = (basis[_xn() % basis.size()] as PackedByteArray).duplicate()
				var at := _xn() % b.size()
				b[at] = [0, 1, 0x7F, 0x80, 0xFE, 0xFF][_xn() % 6]
			6:
				# kleine Zahlen an beliebiger Stelle: trifft die Grenzen der Listen (7, 12, 16, 31 …)
				b = (basis[_xn() % basis.size()] as PackedByteArray).duplicate()
				if b.size() < 5:
					b = (basis[1] as PackedByteArray).duplicate()
				var at := 3 + _xn() % (b.size() - 3)
				b[at] = _xn() % 40
			7:
				# 16-Bit-Grenzwerte an beliebiger Stelle (Position, Blick, Kelvin, Anzahl)
				b = (basis[_xn() % basis.size()] as PackedByteArray).duplicate()
				if b.size() < 5:
					b = (basis[1] as PackedByteArray).duplicate()
				var at := 3 + _xn() % (b.size() - 4)
				b.encode_u16(at, VEKTOR_GRENZEN[_xn() % VEKTOR_GRENZEN.size()])
		var vg := (_xn() & 1) == 1
		var ok := P.struktur_ok(b, vg)
		if ok:
			an += 1
		h = ((h ^ (0x31 if ok else 0x30)) * 16777619) & 0xFFFFFFFF
	return "0x%08x/%d" % [h, an]


func _vektoren() -> void:
	print("Gleiche Pakete wie in der Sandbox-Probe")
	var basis_ok := true
	for hx in VEKTOR_BASIS:
		basis_ok = basis_ok and P.struktur_ok(_hex(hx), true)
	check(basis_ok, "alle %d Grundformen sind gültig" % VEKTOR_BASIS.size())
	var u := _vektor_urteile()
	check(u == VEKTOR_SOLL, "%d Pakete: Fingerabdruck der Urteile %s (Sandbox-Probe erwartet %s)" % [VEKTOR_ANZAHL, u, VEKTOR_SOLL])


# --- Fuzz -----------------------------------------------------------------------------------------------

func _zufall_bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = rng.randi() & 0xFF
	return b


## Ein Paket, dessen Aufbau stimmt (alle Felder zufällig im erlaubten Bereich).
func _zufall_gueltig() -> PackedByteArray:
	var art := rng.randi_range(1, 7)
	var b := PackedByteArray()
	b.resize(P.ZIMMER_KOPF if art == 6 else int(P.LAENGE[art]))
	b[0] = P.MAGIC
	b[1] = P.VERSION
	b[2] = art
	match art:
		1:
			b[3] = rng.randi_range(0, 1)
			b.encode_u32(4, P.stempel() if rng.randf() < 0.5 else rng.randi())
		2:
			b.encode_u16(3, rng.randi_range(0, P.X_MAX))
			b.encode_u16(5, rng.randi_range(0, P.Y_MAX))
			b.encode_u16(7, rng.randi_range(0, P.X_MAX))
			b.encode_s16(9, rng.randi_range(-P.YAW_MAX, P.YAW_MAX))
			b.encode_s16(11, rng.randi_range(-P.PITCH_MAX, P.PITCH_MAX))
		3:
			b[3] = rng.randi_range(0, P.EMOTES.size() - 1)
		4:
			b[3] = rng.randi_range(0, P.SAETZE.size() - 1)
		5:
			var fz := P.figur_anzahl()
			for i in fz.size():
				b[3 + i] = rng.randi_range(0, fz[i] - 1)
		6:
			var w := rng.randi_range(8, 20)
			var t := rng.randi_range(8, 20)
			b[3] = w
			b[4] = t
			b[5] = rng.randi_range(0, G.BODENARTEN.size() - 1)
			for k in range(6, 25):
				b[k] = rng.randi() & 0xFF
			for k in 4:
				b[9 + 4 * k] = rng.randi_range(0, G.WANDMATERIAL.size() - 1)
			b[25] = rng.randi_range(0, 4)
			b[26] = rng.randi_range(0, 4)
			b.encode_u16(27, rng.randi_range(P.K_MIN, P.K_MAX))
			b[29] = rng.randi_range(0, P.H_MAX)
			var n := rng.randi_range(0, 60) if rng.randf() < 0.9 else rng.randi_range(0, P.MAX_MOEBEL)
			b.encode_u16(30, n)
			for i in n:
				var fl := rng.randi_range(0, 3)
				var m := PackedByteArray([rng.randi_range(0, P.katalog().size() - 1), rng.randi_range(0, w - 1), rng.randi_range(0, t - 1),
						rng.randi_range(0, 3), P.KEINE if rng.randf() < 0.6 else rng.randi_range(0, 15), P.KEINE if rng.randf() < 0.7 else rng.randi_range(0, 7),
						fl, 0, 0, 0, 0, 0])
				if (fl & 2) != 0:
					m[7] = rng.randi() & 0xFF
					m[8] = rng.randi() & 0xFF
					m[9] = rng.randi() & 0xFF
				b.append_array(m)
	return b


func _fuzz() -> void:
	print("Fuzz-Tests")
	var gueltige: Array = []
	for hx in VEKTOR_BASIS:
		gueltige.append(_hex(hx))
	gueltige.append(P.schreiben("zimmer", { "raum": Daten.standard_raum() }))
	gueltige.append(P.schreiben("hallo", { "geraet": "uzai" }))
	var schlecht := 0
	var durch := 0
	var t0 := Time.get_ticks_msec()
	# 1. Rauschen: zufällige Bytes jeder Länge, oft mit passendem Kopf.
	for i in 4000:
		var b := _zufall_bytes(rng.randi_range(0, 64) if rng.randf() < 0.9 else rng.randi_range(0, 5000))
		if b.size() >= 3 and rng.randf() < 0.6:
			b[0] = P.MAGIC
			b[1] = P.VERSION if rng.randf() < 0.9 else rng.randi_range(0, 3)
			b[2] = rng.randi_range(0, 9)
		var vg := rng.randf() < 0.5
		var m := P.lesen(b, vg)
		if not _schema_ok(m, vg):
			schlecht += 1
		if not m.is_empty():
			durch += 1
	check(schlecht == 0, "4000 × Zufallsbytes: nichts verletzt das Schema (%d zufällig gültig)" % durch)
	# 2. Kaputt gemachte gültige Nachrichten: Bits kippen, abschneiden, einfügen, verdoppeln, Grenzwerte.
	schlecht = 0
	durch = 0
	for i in 5000:
		var b: PackedByteArray = (gueltige[rng.randi_range(0, gueltige.size() - 1)] as PackedByteArray).duplicate()
		match rng.randi_range(0, 4):
			0:
				for k in rng.randi_range(1, 6):
					var at := rng.randi_range(0, b.size() - 1)
					b[at] = b[at] ^ (1 << rng.randi_range(0, 7))
			1:
				b = b.slice(0, rng.randi_range(0, b.size()))
			2:
				var at2 := rng.randi_range(0, b.size())
				b = b.slice(0, at2) + _zufall_bytes(rng.randi_range(1, 30)) + b.slice(at2)
			3:
				b = b + b
			4:
				b[rng.randi_range(0, b.size() - 1)] = [0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF, 0x55, 0x02][rng.randi_range(0, 7)]
		var vg := rng.randf() < 0.5
		var m := P.lesen(b, vg)
		if not _schema_ok(m, vg):
			schlecht += 1
		if not m.is_empty():
			durch += 1
	check(schlecht == 0, "5000 × kaputt gemachte gültige Nachrichten: nichts verletzt das Schema (%d noch gültig)" % durch)
	# 3. Aufbau stimmt, Felder zufällig im Bereich: wird gelesen (oder aus gutem Grund abgelehnt),
	#    bleibt im Schema und lässt sich wieder schreiben.
	schlecht = 0
	durch = 0
	var wieder := 0
	for i in 3000:
		var b := _zufall_gueltig()
		if not P.struktur_ok(b, true):
			schlecht += 1
			continue
		var m := P.lesen(b, true)
		if not _schema_ok(m, true):
			schlecht += 1
			print("    Schema verletzt: ", b.hex_encode().left(120))
		if m.is_empty():
			continue
		durch += 1
		var neu := P.schreiben(str(m.a), m.d)
		var m2 := P.lesen(neu, true)
		if m2.get("a") == m.a and (str(m.a) == "zimmer" or m2 == m):
			wieder += 1
	check(schlecht == 0, "3000 × zufällig gültige Pakete: Aufbau erkannt, Ergebnis im Schema (%d gelesen, Rest: fremder Stempel, Variante, Stufe)" % durch)
	check(wieder == durch, "was gelesen wird, lässt sich genauso wieder schreiben (%d/%d)" % [wieder, durch])
	check(Time.get_ticks_msec() - t0 < 60000, "Fuzz-Lauf in %d ms" % (Time.get_ticks_msec() - t0))


# --- Drossel ----------------------------------------------------------------------------------------------

func _drossel() -> void:
	print("Drossel")
	var d := P.Drossel.new()
	var n := 0
	for i in 20:
		if d.erlaubt("satz", 4, 100.0):
			n += 1
	check(n == 4, "Schnellsätze: 4 auf einmal, dann gebremst (%d)" % n)
	check(not d.erlaubt("satz", 4, 101.0) and d.erlaubt("satz", 4, 102.1), "nach zwei Sekunden wieder ein Satz")
	var p := 0
	for i in 100:
		if d.erlaubt("pos", 13, 102.1):
			p += 1
	check(p == 40, "Position: Vorrat 40 (%d)" % p)
	check(not d.erlaubt("chat", 1, 103.0) and not d.erlaubt("unbekannt", 1, 103.0), "Chat und unbekannte Arten kommen nie durch")
	var b := P.Drossel.new()
	var ok := 0
	for i in 10:
		if b.erlaubt("zimmer", P.MAX_NACHRICHT, 10.0):
			ok += 1
	check(ok == 2, "Zimmer: höchstens 2 auf einmal (%d)" % ok)
	var g := P.Drossel.new()
	check(g.erlaubt("zimmer", 30 * 1024, 5.0) and not g.erlaubt("zimmer", 4 * 1024, 5.0), "Bytes: 32 KiB Vorrat für alles zusammen")
	var r := P.Drossel.new()
	for i in 30:
		r.erlaubt("satz", 4, 1.0)
	check(r.rauswerfen(), "wer die Grenzen dauernd reißt, fliegt raus")
	var ruhig := P.Drossel.new()
	for i in 60:
		ruhig.erlaubt("satz", 4, float(i) * 2.1)
	check(not ruhig.rauswerfen(), "wer sich an die Grenzen hält, bleibt")
	r.erlaubt("pos", 13, 100.0)
	check(not r.rauswerfen(), "Verstöße verfallen mit der Zeit")
	var z := P.Drossel.new()
	z.erlaubt("satz", 1, 50.0)
	z.erlaubt("satz", 1, 10.0)
	check(float(z.eimer.satz) <= 4.0, "Zeit, die zurückspringt, füllt nichts nach")


# --- Leitung (Prüfmauer 2) -------------------------------------------------------------------------------

func _empf(platz: int, m: PackedByteArray) -> PackedByteArray:
	return ZN.rahmen(ZN.EMPFANGEN, PackedByteArray([platz]) + m)


func _leitung() -> void:
	print("Leitung zur Sandbox (Prüfmauer 2)")
	var pos := P.schreiben("pos", { "x": 100, "y": 0, "z": 100, "yaw": 0, "pitch": 0 })
	var r := ZN.rahmen(ZN.EMPFANGEN, PackedByteArray([1]) + pos)
	check(r.size() == 4 + 1 + 1 + 13 and r.decode_u32(0) == 15 and r[4] == ZN.EMPFANGEN, "Rahmen: 4 Byte Länge, Art, Platz, Nachricht")
	check(ZN.rahmen(0).is_empty() and ZN.rahmen(21).is_empty() and ZN.rahmen(ZN.PING, PackedByteArray(range(ZN.MAX_RAHMEN + 1))).is_empty(),
			"unbekannte Art und zu große Nutzlast werden nicht geschrieben")
	var l := ZN.Leitung.new("gastgeber")
	var doppelt := r + _empf(2, P.schreiben("satz", { "id": "danke" }))
	var e1 := l.eingang(doppelt.slice(0, 7), 1.0)
	var e2 := l.eingang(doppelt.slice(7), 1.0)
	check(e1.is_empty() and e2.size() == 2 and e2[0].art == "nachricht" and e2[0].platz == 1 and e2[0].m.a == "pos" and e2[1].m.d.id == "danke",
			"Rahmen über mehrere Stücke, zwei in einem: beide gelesen")
	var fremd := P.schreiben("hallo", { "geraet": "web" })
	fremd.encode_u32(4, 7)
	check(l.eingang(_empf(1, fremd), 2.0).is_empty() and l.verworfen == 1 and l.kaputt == "", "fremder Stempel: Uzai lehnt ab, Leitung bleibt")
	var n := 0
	var raus := false
	for i in 80:
		for e in l.eingang(_empf(4, pos), 3.0):
			if e.art == "nachricht":
				n += 1
			elif e.art == "raus" and e.platz == 4 and e.von == "uzai":
				raus = true
	check(n == 40 and l.gedrosselt == 25 and raus, "Flut, die die Sandbox durchließe: Uzai drosselt selbst (40 durch) und wirft nach 25 Verstößen hinaus")
	check(l.eingang(_empf(4, pos), 9.0).is_empty(), "nach dem Rauswurf hört Uzai den Platz nicht mehr")
	l.schliessen(4)
	check(l.eingang(_empf(4, pos), 10.0).size() == 1, "Platz geschlossen und frei: wieder hörbar")
	var test_raus := l.eingang(ZN.rahmen(ZN.TEST_RAUS, PackedByteArray([0]) + P.schreiben("zimmer", { "raum": Daten.standard_raum() })), 11.0)
	check(test_raus.size() == 1 and test_raus[0].art == "test_raus", "Testbetrieb: was hinausginge, kommt zurück")
	var z := PackedByteArray([0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0])
	var ze := l.eingang(ZN.rahmen(ZN.ZAEHLER, z), 11.0)
	check(ze.size() == 1 and ze[0].angenommen == 0 and ze[0].verworfen == 1 and ze[0].aus_verworfen == 3, "Zähler der Sandbox")
	# Alles, was die Sandbox nie schicken darf, schließt die Leitung: Uzai glaubt ihr dann nichts mehr.
	var kaputt := {
		"Länge 0": PackedByteArray([0, 0, 0, 0]), "Länge über 8 KiB": PackedByteArray([2, 0x20, 0, 0, 7]), "riesige Länge": PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF]),
		"unbekannte Art": ZN.rahmen(ZN.PING).slice(0, 4) + PackedByteArray([99]), "Art der Gegenrichtung (SENDEN)": ZN.rahmen(ZN.SENDEN, PackedByteArray([0]) + pos),
		"Platz außerhalb": _empf(8, pos), "ohne Platz": ZN.rahmen(ZN.EMPFANGEN), "ungültige Nachricht (Prüfmauer 1 versagt)": _empf(1, pos.slice(0, 12)),
		"Zimmer von einem Gast": _empf(1, P.schreiben("zimmer", { "raum": Daten.standard_raum() })),
		"JSON statt Binär": _empf(1, "{\"a\":\"chat\"}".to_utf8_buffer()), "RAUS kaputt": ZN.rahmen(ZN.RAUS, PackedByteArray([1])),
		"Zähler zu kurz": ZN.rahmen(ZN.ZAEHLER, PackedByteArray([1])), "TEST_RAUS ungültig": ZN.rahmen(ZN.TEST_RAUS, PackedByteArray([0, 1, 2])),
		"SELBSTTEST-Antwort in der Sitzung": ZN.rahmen(4, PackedByteArray([1])),
	}
	var zu := 0
	for k in kaputt.keys():
		var lk := ZN.Leitung.new("gastgeber")
		var ev := lk.eingang(kaputt[k], 1.0)
		if lk.kaputt != "" and ev.is_empty() and lk.eingang(r, 1.0).is_empty():
			zu += 1
		else:
			print("    bleibt offen: ", k)
	check(zu == kaputt.size(), "Leitung zu bei: %s (%d/%d)" % [", ".join(kaputt.keys()), zu, kaputt.size()])
	var lg := ZN.Leitung.new("gast")
	check(lg.plaetze() == 1 and lg.eingang(_empf(0, P.schreiben("zimmer", { "raum": Daten.standard_raum() })), 1.0).size() == 1,
			"Gast: ein Platz (der Gastgeber), dessen Zimmer kommt an")
	lg.eingang(_empf(1, pos), 1.0)
	check(lg.kaputt != "", "Gast: ein zweiter Platz gibt es nicht")
	check(lg.senden(0, "zimmer", { "raum": Daten.standard_raum() }).is_empty() and not lg.senden(0, "pos", { "x": 1, "y": 0, "z": 1, "yaw": 0, "pitch": 0 }).is_empty()
			and lg.senden(0, "chat", { "text": "x" }).is_empty() and lg.senden(1, "satz", { "id": "ja" }).is_empty(),
			"Gast schickt kein Zimmer, keinen Chat, nur an Platz 0")
	var ohne_test := ZN.Leitung.new("gastgeber", false)
	var ohne_ev := ohne_test.eingang(ZN.rahmen(ZN.TEST_RAUS, PackedByteArray([0]) + pos), 1.0)
	check(ohne_test.test_rein(0, pos).is_empty() and ohne_ev.is_empty() and ohne_test.kaputt != "",
			"ohne Testbetrieb gibt es TEST_REIN/TEST_RAUS nicht")
	var gross := PackedByteArray()
	gross.resize(ZN.MAX_STUECK + 1)
	var lgr := ZN.Leitung.new("gastgeber")
	lgr.eingang(gross, 1.0)
	check(lgr.kaputt == "stueck", "mehr als 64 KiB auf einmal: Leitung zu")


## Die echte Prüfmauer 1 (C#, Sitzungs-Schleife aus dem Helfer) über eine echte Pipe – unter Linux
## mit PowerShell 7 statt AppContainer. Dieselbe Test-Gegenstelle prüft am PC „Abschottung prüfen“.
func _sandbox_pipe() -> void:
	print("Echte Prüfmauer 1 über eine Pipe")
	var pwsh := OS.get_environment("UZAI_PWSH")
	if pwsh == "" or not FileAccess.file_exists(pwsh):
		print("  (UZAI_PWSH fehlt – übersprungen)")
		return
	var s := ZN.starten(pwsh, PackedStringArray(["-NoProfile", "-NonInteractive", "-File", ProjectSettings.globalize_path("res://tests/zimmer_netz_stdio.ps1"),
			ProjectSettings.globalize_path("res://helper/uzai-helper.ps1"), "gastgeber"]), "gastgeber")
	check(s != null and s.laeuft(), "Sandbox-Schleife gestartet")
	var r: Dictionary = await ZN.pruefen(s, get_tree(), 90.0)
	print("    ", r)
	check(r.leitung, "Leitung: Echo kommt genau zurück")
	check(r.mauer1, "Prüfmauer 1: genau die gültigen Pakete durch, alle bösen verworfen")
	check(r.mauer2, "Prüfmauer 2: liest dieselben, lehnt den fremden Schema-Stempel ab")
	check(r.drossel and r.rauswurf, "Flut gedrosselt, Dauer-Unsinn hinausgeworfen")
	check(r.ausgang, "hinaus geht nur, was ins Schema passt")
	check(r.ende and r.ok, "Ende: die Sandbox beendet sich sauber")
	# Unerwartetes von Uzais Seite beendet die Sandbox (Code 3) statt es zu deuten.
	var s2 := ZN.starten(pwsh, PackedStringArray(["-NoProfile", "-NonInteractive", "-File", ProjectSettings.globalize_path("res://tests/zimmer_netz_stdio.ps1"),
			ProjectSettings.globalize_path("res://helper/uzai-helper.ps1"), "gast"]), "gast")
	s2.schicken(ZN.rahmen(ZN.PING, PackedByteArray([1])))
	var t0 := Time.get_ticks_msec()
	var pong := false
	while Time.get_ticks_msec() - t0 < 60000 and not pong:
		for e in s2.pumpen(0.0):
			pong = pong or e.art == "pong"
		await get_tree().process_frame
	s2.schicken(ZN.rahmen(ZN.TEST_REIN, PackedByteArray([1, 0x55])))    # Gast: Platz 1 gibt es nicht
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000 and s2.laeuft():
		await get_tree().process_frame
	check(pong and not s2.laeuft(), "Gast-Sandbox: Platz 1 von Uzai → sie beendet sich")
	s2.abbrechen()


# --- Einladung --------------------------------------------------------------------------------------------

func _einladung() -> void:
	print("Einladungslink")
	var e := Einladung.neu(1000, 60, true)
	check((e.kennung as PackedByteArray).size() == 16 and (e.schluessel as PackedByteArray).size() == 32, "Kennung 128 Bit, Schlüssel 256 Bit")
	var e2 := Einladung.neu(1000, 60, true)
	check(e.schluessel != e2.schluessel and e.kennung != e2.kennung, "jede Einladung hat eigenen Zufall")
	var l := Einladung.link(e)
	check(l.begins_with("uzai://zimmer#z1.") and l.length() == 14 + 3 + 22 + 1 + 43, "Link-Form: uzai://zimmer#z1.<22>.<43>")
	check(l.find("#") < l.find((Einladung.b64url(e.schluessel))), "Schlüssel steht nur hinter „#“")
	var g := Einladung.lesen(l)
	check(g.get("kennung") == e.kennung and g.get("schluessel") == e.schluessel, "Link wird genau zurückgelesen")
	var frag := l.substr(Einladung.PRAEFIX.length())
	check(Einladung.lesen(frag).get("schluessel") == e.schluessel, "nur der Teil hinter „#“ (Web-Version) geht auch")
	var teile := frag.split(".")
	var falsch: Array = [
		"", "z1", "z2." + teile[1] + "." + teile[2], frag + ".x", "z1." + teile[1] + "." + teile[2] + "A",
		"z1." + teile[1] + "." + teile[2].substr(0, 42) + "+", "z1." + teile[1] + "." + teile[2].substr(0, 42) + "=",
		"https://boese.example/#" + frag, "uzai://zimmer/../../x#" + frag, "uzai://zimmer#" + frag + "&cmd=calc",
		"z1." + teile[1] + "." + teile[2].substr(0, 42) + "B", l + "x".repeat(200),
	]
	var abgelehnt := 0
	for f in falsch:
		if Einladung.lesen(f).is_empty():
			abgelehnt += 1
	# „…B“ statt des letzten Zeichens kann kanonisch sein – dann ist es ein anderer, gültiger Schlüssel.
	var letzte := Einladung.lesen("z1." + teile[1] + "." + teile[2].substr(0, 42) + "B")
	var soll := falsch.size() - (0 if letzte.is_empty() else 1)
	check(abgelehnt == soll, "falsche Form, Länge, Zeichen, Füllung, fremde Adresse, Anhängsel: abgelehnt (%d/%d)" % [abgelehnt, soll])
	check(Einladung.b64url_lesen("AAAAAAAAAAAAAAAAAAAAAB", 16).is_empty(), "nicht kanonisches base64url (Füllbits gesetzt): abgelehnt")
	check(Einladung.passt(e, e.schluessel) and not Einladung.passt(e, e2.schluessel) and not Einladung.passt(e, PackedByteArray([1, 2])), "Schlüssel-Vergleich")
	check(Einladung.gueltig(e, 1000) and Einladung.gueltig(e, 1000 + 3599) and not Einladung.gueltig(e, 1000 + 3600) and not Einladung.gueltig(e, 999),
			"läuft nach 60 Minuten ab, gilt nicht vor dem Start")
	e.benutzt = true
	check(not Einladung.gueltig(e, 1100), "einmalige Einladung nach der Annahme verbraucht")
	check(int(Einladung.neu(0, 7, false).bis) == 3600, "unbekannte Dauer: eine Stunde")


# --- Böser Gast und Flut (Phase 6) ---------------------------------------------------------------------------

func _zufall_id(rng: RandomNumberGenerator) -> String:
	var s := ""
	for i in 16:
		s += "0123456789abcdef"[rng.randi() % 16]
	return s


func _flut() -> void:
	print("Böser Gast und Flut (Phase 6)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var c := Crypto.new()
	var o := Online.new()
	var e: Dictionary = o.einladen(5000, 60, "Mila", "steam")
	# 3000 Anklopfer ohne den Schlüssel der Einladung, verteilt über eine Stunde.
	for i in 3000:
		o.anklopfen(_zufall_id(rng), c.generate_random_bytes(32), 5000 + i)
	check(o.wartend.is_empty() and o.gaeste.is_empty() and o._klopfen.size() <= Online.ANKLOPFEN_JE_MINUTE,
			"3000 Anklopfer ohne Schlüssel: niemand wartet, niemand ist drin, nichts wächst")
	# Abgefangene Einladung: Flut mit dem richtigen Schlüssel und immer neuen Kennungen.
	var hoechstens := 0
	for i in 3000:
		o.anklopfen(_zufall_id(rng), e.schluessel, 9000 + i / 20)
		hoechstens = maxi(hoechstens, o.wartend.size())
	check(hoechstens <= Online.MAX_WARTEND and o.gaeste.is_empty(), "Flut mit gültiger Einladung: nie mehr als %d warten, keiner kommt ohne Annahme herein" % Online.MAX_WARTEND)
	# Müll statt Kennung oder Schlüssel.
	var t := 20000
	var muell_ok := true
	for id in ["", "0", "g".repeat(16), "0".repeat(17), "0000000000000001\n", "../../../../etc", "💥".repeat(16)]:
		t += 61
		muell_ok = muell_ok and o.anklopfen(id, e.schluessel, t) == "ungueltig"
	for key in [PackedByteArray(), PackedByteArray([0]), c.generate_random_bytes(31), c.generate_random_bytes(33), c.generate_random_bytes(65536)]:
		t += 61
		muell_ok = muell_ok and o.anklopfen("00000000000000aa", key, t) == "falscher_schluessel"
	check(muell_ok, "Müll als Kennung oder Schlüssel (leer, zu kurz, zu lang, Pfadzeichen, 64 KiB): abgewiesen")
	# Sperren gilt weiter, auch mit gültiger Einladung; eine Annahme verbraucht die Einladung für alle anderen.
	var o2 := Online.new()
	var e2: Dictionary = o2.einladen(100, 60, "Ben", "discord")
	o2.anklopfen("00000000000000b1", e2.schluessel, 100)
	o2.anklopfen("00000000000000b2", e2.schluessel, 101)
	check(o2.sperren("00000000000000b1") and o2.anklopfen("00000000000000b1", e2.schluessel, 200) == "gesperrt", "gesperrt bleibt draußen, auch mit gültiger Einladung")
	check(o2.annehmen("00000000000000b2", 201) == "ok" and o2.anklopfen("00000000000000b3", e2.schluessel, 300) == "falscher_schluessel"
			and o2.annehmen("00000000000000b3", 301) == "unbekannt", "eine Einladung, ein Gast: wiederholt nutzt sie niemand")
	check(o2.annehmen("00000000000000b2", 302) == "unbekannt" and o2.gaeste.size() == 1, "zweimal hereinlassen: bleibt ein Gast")
	# Zurückgezogen und „Zimmer offline“: danach geht mit alten Einladungen nichts mehr.
	var o3 := Online.new()
	var e3: Dictionary = o3.einladen(100, 60, "Kim", "steam")
	check(o3.zurueckziehen(e3.kennung) and o3.anklopfen("00000000000000c1", e3.schluessel, 110) == "falscher_schluessel", "zurückgezogene Einladung: abgewiesen")
	var e4: Dictionary = o3.einladen(200, 60, "Kim", "steam")
	o3.anklopfen("00000000000000c2", e4.schluessel, 201)
	o3.annehmen("00000000000000c2", 202)
	o3.offline()
	check(o3.gaeste.is_empty() and o3.wartend.is_empty() and o3.anklopfen("00000000000000c3", e4.schluessel, 300) == "falscher_schluessel",
			"Zimmer offline: alle raus, alle Einladungen ungültig")


# --- Gastgeber ---------------------------------------------------------------------------------------------

func _gastgeber() -> void:
	print("Gastgeber")
	check(Online.BEREIT and Online.darf_online(true, false, true, true), "Zimmer online: alle vier Bedingungen erfüllt")
	check(not Online.darf_online(false, false, true, true) and not Online.darf_online(true, true, true, true) and not Online.darf_online(true, false, false, true)
			and not Online.darf_online(true, false, true, false) and not Online.darf_online(true, false),
			"fehlt eine Bedingung (ausgeschaltet, Adminrechte, Abschottung, Hinweis): offline")
	check(Online.abschottung_gemerkt({ "fassung": "1.2.3", "ok": true }, "1.2.3") and not Online.abschottung_gemerkt({ "fassung": "1.2.2", "ok": true }, "1.2.3")
			and not Online.abschottung_gemerkt({ "fassung": "1.2.3", "ok": "true" }, "1.2.3") and not Online.abschottung_gemerkt(null, "1.2.3")
			and not Online.abschottung_gemerkt({ "fassung": "", "ok": true }, ""), "gemerkte Abschottung gilt nur für genau diese Fassung")
	_flut()
	var o := Online.new()
	check(o.einladen(1000, 60, "Mila", "post").is_empty(), "Einladung nur über Steam oder Discord")
	var e: Dictionary = o.einladen(1000, 60, "Mila\u202E\u200B", "discord")
	check(str(e.fuer) == "Mila" and str(e.quelle) == "discord", "Einladung an genau einen Freund (Name bereinigt)")
	var s: PackedByteArray = e.schluessel
	var fremd: PackedByteArray = Einladung.neu(1000, 60, false).schluessel
	check(o.anklopfen("a1b2c3d4e5f60718", fremd, 1000) == "falscher_schluessel", "ohne den Schlüssel der Einladung: abgewiesen")
	check(o.anklopfen("A1B2C3D4E5F60718", s, 1001) == "ungueltig" and o.anklopfen("a1b2", s, 1001) == "ungueltig", "falsche Kennung: abgewiesen")
	check(o.anklopfen("a1b2c3d4e5f60718", s, 1002) == "wartet" and o.wartend[0].name == "Mila" and o.wartend[0].quelle == "discord",
			"Anklopfen: Name und Weg kommen aus der Einladung, nicht vom Gast")
	check(o.anklopfen("a1b2c3d4e5f60718", s, 1003) == "schon_da", "zweimal anklopfen: einmal in der Liste")
	for id in ["0000000000000011", "0000000000000012", "0000000000000013"]:
		o.anklopfen(id, s, 1004)
	check(o.anklopfen("0000000000000014", s, 1005) == "gedrosselt", "mehr als 6 Anklopfer je Minute: gedrosselt")
	check(o.anklopfen("0000000000000014", s, 1070) == "wartet", "eine Minute später wieder möglich")
	for id in ["0000000000000011", "0000000000000012", "0000000000000013"]:
		o.ablehnen(id)
	check(o.gaeste.is_empty(), "niemand ist drin, bevor der Gastgeber annimmt")
	check(o.annehmen("a1b2c3d4e5f60718", 1080) == "ok" and o.gaeste.size() == 1 and o.wartend.size() == 1, "Hereinlassen")
	check(o.annehmen("0000000000000014", 1081) == "abgelaufen", "einmalige Einladung: zweiter Gast kommt damit nicht mehr herein")
	check(o.anklopfen("0000000000000002", s, 1090) == "falscher_schluessel", "verbrauchte Einladung erlaubt kein Anklopfen mehr")
	var e2: Dictionary = o.einladen(1100, 15, "Ben", "steam")
	check(o.anklopfen("0000000000000003", e2.schluessel, 1100 + 15 * 60) == "falscher_schluessel", "abgelaufene Einladung: abgewiesen")
	o.einstellen(1)
	o.anklopfen("0000000000000004", e2.schluessel, 1200)
	check(o.annehmen("0000000000000004", 1201) == "voll", "Höchstzahl erreicht: niemand kommt mehr herein")
	o.einstellen(99)
	check(o.max_gaeste == Online.MAX_GAESTE_GRENZE, "Höchstzahl höchstens 8")
	check(o.annehmen("0000000000000004", 1202) == "ok" and str(o.gaeste[1].name) == "Ben", "mit mehr Platz: herein")
	check(o.rauswerfen("0000000000000004") and o.gaeste.size() == 1 and not o.rauswerfen("0000000000000004"), "Rauswerfen")
	check(o.sperren("a1b2c3d4e5f60718") and o.gaeste.is_empty() and o.gesperrt.has("a1b2c3d4e5f60718"), "Sperren wirft hinaus und merkt sich den Gast")
	check(o.anklopfen("0000000000000005", e2.schluessel, 1203) == "falscher_schluessel", "jede Einladung gilt nur einmal (es gibt keinen Schalter dafür)")
	var e3: Dictionary = o.einladen(1290, 60, "Mila", "discord")
	check(o.anklopfen("a1b2c3d4e5f60718", e3.schluessel, 1300) == "gesperrt", "Gesperrte bleiben draußen, auch mit neuer Einladung")
	check(o.entsperren("a1b2c3d4e5f60718") and o.anklopfen("a1b2c3d4e5f60718", e3.schluessel, 1301) == "wartet", "Entsperren")
	check(o.ablehnen("a1b2c3d4e5f60718") and o.wartend.is_empty(), "Ablehnen")
	for i in 20:
		o._klopfen.clear()
		o.anklopfen("00000000000001%02x" % i, e3.schluessel, 1400 + i)
	check(o.wartend.size() == Online.MAX_WARTEND, "höchstens 8 warten gleichzeitig")
	o.offline()
	check(o.wartend.is_empty() and o.gaeste.is_empty() and o.einladungen.is_empty(), "„Zimmer offline“: alle raus, alle Einladungen zurückgezogen")
	check(o.anklopfen("0000000000000007", e3.schluessel, 1600) == "falscher_schluessel", "nach „offline“ gilt keine alte Einladung mehr")
	check(Online.anzeige_name("  Ma\u202Ex  \n\tim ") == "Max im" and Online.anzeige_name("") == "Freund" and Online.anzeige_name(42) == "Freund"
			and Online.anzeige_name("x".repeat(99)).length() == Online.MAX_NAME, "Freundesname: Steuer-/Richtungszeichen weg, Leerraum zusammen, gekürzt")
	var b := Online.new()
	b.beispiel(100000)
	check(b.wartend.size() == 2 and b.gaeste.size() == 2 and b.gesperrt.size() == 1, "Beispiel-Gäste: 2 klopfen an, 2 sind da, 1 gesperrt")
	check(b.annehmen(str(b.wartend[0].id), 100000) == "ok", "Beispiel: Hereinlassen klappt")


# --- Quelltext ---------------------------------------------------------------------------------------------

func _quelltext() -> void:
	print("Quelltext")
	var verboten := ["str_to_var", "bytes_to_var", "Expression", "ResourceLoader", "load(", "to_native", "base64_to_variant", "OS.execute", "create_process",
			"JSON", "HTTPRequest", "WebRTC", "PacketPeer", "TCPServer", "UDPServer", "StreamPeerTCP", "WebSocket", "var_to_bytes"]
	for f in ["res://src/room/netz_protokoll.gd", "res://src/room/einladung.gd", "res://src/room/online.gd", "res://src/room/online_ui.gd", "res://src/room/zimmer_netz.gd",
			"res://src/room/treffpunkt.gd", "res://src/room/verbindungstest.gd"]:
		var src := FileAccess.get_file_as_string(f)
		var code := ""
		for zeile in src.split("\n"):
			var z := zeile.strip_edges()
			if not z.begins_with("#"):
				code += zeile.split("#")[0] + "\n"
		if f.ends_with("zimmer_netz.gd"):
			# Genau ein Prozessstart: die Sandbox (fester Aufrufer, Argumentliste, keine Shell).
			check(code.count("OS.execute_with_pipe(") == 1, "zimmer_netz.gd: genau ein Prozessstart (die Sandbox)")
			code = code.replace("OS.execute_with_pipe(", "")
		var treffer: Array = []
		for w in verboten:
			if code.contains(w) and not (w == "load(" and code.replace("preload(", "").find("load(") < 0):
				treffer.append(w)
		check(src != "" and treffer.is_empty(),
				"%s: kein Ausführen, kein Laden fremder Daten, kein JSON, keine Netzverbindung %s" % [f.get_file(), str(treffer) if not treffer.is_empty() else ""])

extends RefCounted
## Konsolen im Lowboard des Fernsehers: je eingerichtetem System eine Konsole, der echten Hardware
## nachempfunden – Maße, Fasen, Lüftungsschlitze, Tasten, Klappe oder Lade, LEDs, Buchsen und
## Kunststoffe (matt oder Klavierlack, die typischen Farben). Alles eigene Geometrie, nur
## nachempfunden: keine Logos, Markennamen oder Schriftzüge auf den Modellen, keine fremden Modelle
## oder Texturen (R1–R9). Den Namen des Systems zeigt Uzai nur als eigenen Text.
##
## Startet ein Spiel aus dem Regal, läuft es auf seiner Konsole: Deckel bzw. Lade geht auf, Disc
## oder Modul hinein, zu, die Betriebs-LED geht an, ein Lichtpunkt läuft das Kabel entlang nach
## hinten zum Fernseher (U.reduziert(): ohne Bewegung, nur die LED). Beim Beenden geht sie aus.
##
## Leistung: Jede Konsole ist ein Netz mit einer Fläche je Material (meist vier bis sechs), dazu
## Klappe und LED; ab FERN Metern steht nur ein schlichter Block da. Gebaut wird je Modell einmal.
## Reine Logik (auswahl, staffeln, fuer_spiel) ohne Szene: tests/logic_plattenkonsole.gd.

const F := preload("res://src/room/formen.gd")
const U := preload("res://src/ui/u.gd")

const PC := "pc"
const MAX := 16
const FERN := 4.0              ## ab hier nur der schlichte Block (Meter)
const LED_AN := 1.7

## Fächer des Lowboards (moebel.gd _medienwand): lichte Breite [von, bis] in x, Boden, lichte Höhe.
const FACH_X := { "mitte": Vector2(-0.262, 0.262), "links": Vector2(-0.928, -0.292), "rechts": Vector2(0.292, 0.928) }
const FACH_Y := 0.13
const FACH_H := 0.358
const BODEN_D := 0.018         ## Zwischenboden, wenn ein Fach zwei Ebenen hat
const LUFT := 0.028            ## Abstand zwischen zwei Konsolen
const RAND := 0.008            ## Luft nach oben
## Staffelung: Ebenen je Fach (0 = Schrank mit Türen). Erst die Mitte, dann die Seiten öffnen, dann
## Zwischenböden – nie übereinander gestapelt, nie überlappend.
const STUFEN := [
	{ "mitte": 1, "links": 0, "rechts": 0 },
	{ "mitte": 1, "links": 1, "rechts": 1 },
	{ "mitte": 2, "links": 1, "rechts": 1 },
	{ "mitte": 2, "links": 2, "rechts": 2 },
]
const FOLGE := [["mitte", 0], ["mitte", 1], ["links", 0], ["rechts", 0], ["links", 1], ["rechts", 1]]

## Außenmaße [Breite, Höhe, Tiefe] in Metern, wie die Konsole im Fach steht (nach der echten Hardware).
const MASSE := {
	"gc": Vector3(0.150, 0.114, 0.161), "ps1": Vector3(0.270, 0.057, 0.188), "ps2": Vector3(0.301, 0.079, 0.182),
	"wii": Vector3(0.070, 0.161, 0.215), "n64": Vector3(0.260, 0.076, 0.190), "snes": Vector3(0.200, 0.076, 0.242),
	"megadrive": Vector3(0.280, 0.069, 0.212), "dreamcast": Vector3(0.190, 0.078, 0.196), "xbox": Vector3(0.320, 0.102, 0.260),
	"switch": Vector3(0.245, 0.122, 0.060), "pc": Vector3(0.200, 0.068, 0.200), "nes": Vector3(0.254, 0.089, 0.203),
	"saturn": Vector3(0.260, 0.085, 0.230), "ps3": Vector3(0.325, 0.098, 0.274), "xbox360": Vector3(0.309, 0.083, 0.258),
	"wiiu": Vector3(0.172, 0.046, 0.269), "pce": Vector3(0.140, 0.038, 0.140), "mastersystem": Vector3(0.365, 0.070, 0.170),
	"atari2600": Vector3(0.350, 0.090, 0.230), "arcade": Vector3(0.320, 0.140, 0.180),
	"gba": Vector3(0.1445, 0.0245, 0.0822), "gb": Vector3(0.090, 0.032, 0.148), "gbc": Vector3(0.075, 0.027, 0.133),
	"nds": Vector3(0.133, 0.0219, 0.0739), "3ds": Vector3(0.134, 0.021, 0.0739), "psp": Vector3(0.170, 0.023, 0.074),
	"gamegear": Vector3(0.210, 0.038, 0.113), "allgemein": Vector3(0.240, 0.060, 0.200),
}
## Handhelds liegen flach im Fach (Bildschirm oben, Oberkante nach hinten).
const HANDHELD := {
	"gba": { "form": "quer", "farbe": "#463c86", "glanz": false, "schirm": Vector2(0.066, 0.046), "knopf": "#3a3170" },
	"psp": { "form": "quer", "farbe": "#141417", "glanz": true, "schirm": Vector2(0.098, 0.056), "knopf": "#2a2b2f" },
	"gamegear": { "form": "quer", "farbe": "#1d1d20", "glanz": false, "schirm": Vector2(0.072, 0.058), "knopf": "#2f3035" },
	"gb": { "form": "hoch", "farbe": "#c7c5bf", "glanz": false, "schirm": Vector2(0.062, 0.056), "knopf": "#8b2c5a" },
	"gbc": { "form": "hoch", "farbe": "#6a3f9e", "glanz": false, "schirm": Vector2(0.052, 0.047), "knopf": "#3b2c55" },
	"nds": { "form": "klapp", "farbe": "#e9e9ec", "glanz": true },
	"3ds": { "form": "klapp", "farbe": "#b0222e", "glanz": true },
}

static var _mats := {}
static var _plaene := {}


# --- Logik (ohne Szene) ---------------------------------------------------------------------------

## Welches Modell ein System bekommt (eigene Systeme: ein schlichtes Gehäuse in ihrer Farbe).
static func modell(sid: String) -> String:
	return sid if MASSE.has(sid) and sid != "allgemein" else "allgemein"


static func masse(sid: String) -> Vector3:
	return MASSE[modell(sid)]


## Welche Konsolen im Lowboard stehen: jedes eingeschaltete System mit mindestens einem Spiel (wie
## die Reiter unter Spiele), das mit den meisten Spielen zuerst (es steht in der Mitte, am
## Fernseher), bei Gleichstand in der Reihenfolge der Systeme; zuletzt der PC, wenn es PC-Spiele
## gibt (Steam, Epic, GOG …).
static func auswahl(aktiv: Array, zahl: Dictionary, pc_spiele: int) -> Array:
	var reihe: Array = []
	for sid in aktiv:
		var s := str(sid)
		if s != "" and s != PC and int(zahl.get(s, 0)) > 0 and not (s in reihe):
			reihe.append(s)
	var out := reihe.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var za := int(zahl.get(a, 0))
		var zb := int(zahl.get(b, 0))
		return za > zb if za != zb else reihe.find(a) < reihe.find(b))
	if pc_spiele > 0:
		out.append(PC)
	return out.slice(0, MAX)


## Auf welcher Konsole ein Spiel läuft: auf der seines Systems, PC-Spiele auf dem PC; "" = keiner.
static func fuer_spiel(sid: String, ist_pc: bool, ids: Array) -> String:
	if sid != "" and sid in ids:
		return sid
	if ist_pc and PC in ids:
		return PC
	return ""


## Die Ebenen einer Stufe in der Reihenfolge, in der sie gefüllt werden.
static func ebenen(stufe: Dictionary) -> Array:
	var out: Array = []
	for e: Array in FOLGE:
		var n := int(stufe.get(e[0], 0))
		if int(e[1]) >= n:
			continue
		var h := FACH_H if n == 1 else (FACH_H - BODEN_D) * 0.5
		var fx: Vector2 = FACH_X[e[0]]
		out.append({ "fach": e[0], "ebene": e[1], "y": FACH_Y + (0.0 if int(e[1]) == 0 else h + BODEN_D), "h": h, "x0": fx.x, "x1": fx.y })
	return out


## Wohin die Konsolen kommen: die kleinste Stufe, in der alle Platz haben (sonst die mit den
## wenigsten übrigen). { stufe, ebenen, offen, plaetze [{ id, fach, ebene, x, y, b }], uebrig }
static func staffeln(ids: Array) -> Dictionary:
	var best := {}
	for k in STUFEN.size():
		var r := _fuellen(ids, STUFEN[k])
		r["stufe"] = k
		if best.is_empty() or (r.uebrig as Array).size() < (best.uebrig as Array).size():
			best = r
		if (r.uebrig as Array).is_empty():
			break
	return best


static func _fuellen(ids: Array, stufe: Dictionary) -> Dictionary:
	var ebs := ebenen(stufe)
	var belegt: Array = []
	var breite: Array = []
	for e in ebs:
		belegt.append([])
		breite.append(0.0)
	var uebrig: Array = []
	for id in ids:
		var m := masse(str(id))
		var ok := false
		for i in ebs.size():
			var e: Dictionary = ebs[i]
			var neu := float(breite[i]) + (LUFT if not (belegt[i] as Array).is_empty() else 0.0) + m.x
			if m.y <= float(e.h) - RAND and neu <= float(e.x1) - float(e.x0):
				(belegt[i] as Array).append(str(id))
				breite[i] = neu
				ok = true
				break
		if not ok:
			uebrig.append(str(id))
	var plaetze: Array = []
	for i in ebs.size():
		var e: Dictionary = ebs[i]
		var x := (float(e.x0) + float(e.x1)) * 0.5 - float(breite[i]) * 0.5
		for id: String in belegt[i]:
			var m := masse(id)
			plaetze.append({ "id": id, "fach": e.fach, "ebene": e.ebene, "x": x + m.x * 0.5, "y": float(e.y), "b": m.x })
			x += m.x + LUFT
	return { "ebenen": stufe.duplicate(), "offen": int(stufe.get("links", 0)) > 0, "plaetze": plaetze, "uebrig": uebrig }


# --- Materialien ----------------------------------------------------------------------------------

## Kunststoff: rau 0,6 matt (die meisten Konsolen), 0,2 Klavierlack (Wii, PS3, PSP).
static func kunststoff(c: Color, rau := 0.55, glanz := 0.5) -> StandardMaterial3D:
	var key := "k:%s:%.2f:%.2f" % [c.to_html(), rau, glanz]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rau
		m.metallic_specular = glanz
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]


## Eloxiertes Metall (PC): halb metallisch, sonst wirkt es ohne Spiegelbild der Umgebung schwarz.
static func eloxal(c: Color) -> StandardMaterial3D:
	var key := "e:%s" % c.to_html()
	if not _mats.has(key):
		var m := kunststoff(c, 0.42, 0.8).duplicate() as StandardMaterial3D
		m.metallic = 0.4
		_mats[key] = m
	return _mats[key]


## Öffnungen, Schlitze, Fugen.
static func loch() -> StandardMaterial3D:
	return kunststoff(Color("#070708"), 0.92, 0.15)


## Leuchtet nur bei Strom (eigenes Material je Konsole).
static func _led_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.75)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.3
	return m


# --- Bauen ----------------------------------------------------------------------------------------

## Sammelt Teile je Material in ein Netz (eine Fläche je Material: wenige Draw Calls).
class Bau:
	var lo: Material
	var _st := {}
	var _mat := {}
	var _folge: Array = []

	func _init(loch_mat: Material) -> void:
		lo = loch_mat

	func teil(mat: Material, mesh: Mesh, t: Transform3D) -> void:
		var key := mat.get_instance_id()
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
			_mat[key] = mat
			_folge.append(key)
		(_st[key] as SurfaceTool).append_from(mesh, 0, t)

	static func _t(rot: Vector3, p: Vector3) -> Transform3D:
		return Transform3D(Basis.from_euler(rot * (PI / 180.0)), p)

	## Kiste um ihre Mitte; rad: Fase bzw. Rundung der Kanten, stufen 1 = gerade Fase.
	func k(mat: Material, g: Vector3, m: Vector3, rad := 0.002, stufen := 2, rot := Vector3.ZERO) -> void:
		teil(mat, F.kiste(g, rad, false, stufen), _t(rot, m))

	## Kiste, die auf y steht.
	func s(mat: Material, g: Vector3, x: float, y: float, z: float, rad := 0.002, stufen := 2) -> void:
		k(mat, g, Vector3(x, y + g.y * 0.5, z), rad, stufen)

	## Zylinder ab fuss nach oben (bzw. nach der Drehung rot: X 90° zeigt nach vorn).
	func w(mat: Material, r: float, h: float, fuss: Vector3, rot := Vector3.ZERO, seg := 20, kante := 0.0008) -> void:
		teil(mat, F.walze(r, h, kante, seg), _t(rot, fuss))

	## Ring (liegt flach, wenn rot X 90°).
	func ring(mat: Material, gross: float, dick: float, mitte: Vector3, rot := Vector3(90, 0, 0), seg := 36) -> void:
		teil(mat, F.ring(gross, dick, TAU, seg, 6), _t(rot, mitte))

	func dreh(mat: Material, umriss: PackedVector2Array, fuss: Vector3, seg := 32) -> void:
		teil(mat, F.dreh(umriss, seg), _t(Vector3.ZERO, fuss))

	## Buchse in der Vorderseite (Controller, Speicherkarte, USB): Rahmen und dunkle Öffnung; z vorn.
	func buchse(rahmen: Material, x: float, y: float, z: float, b: float, h: float, tief := 0.58) -> void:
		if rahmen != null:
			k(rahmen, Vector3(b, h, 0.003), Vector3(x, y, z - 0.001), minf(b, h) * 0.3, 1)
		k(lo, Vector3(b * 0.74, h * tief, 0.003), Vector3(x, y, z - 0.0004), minf(b, h) * 0.18, 1)

	## Feine Fuge als Rechteck auf der Oberseite (Klappen, Abdeckungen).
	func naht_oben(mitte: Vector3, b: float, t: float, d := 0.0011) -> void:
		for sz: float in [-1.0, 1.0]:
			k(lo, Vector3(b, 0.0007, d), mitte + Vector3(0, 0, sz * t * 0.5), 0.0002, 1)
			k(lo, Vector3(d, 0.0007, t), mitte + Vector3(sz * b * 0.5, 0, 0), 0.0002, 1)

	## Feine Fuge als Rechteck auf der Vorderseite.
	func naht_vorn(mitte: Vector3, b: float, h: float, d := 0.0011) -> void:
		for sy: float in [-1.0, 1.0]:
			k(lo, Vector3(b, d, 0.0007), mitte + Vector3(0, sy * h * 0.5, 0), 0.0002, 1)
			k(lo, Vector3(d, h, 0.0007), mitte + Vector3(sy * b * 0.5, 0, 0), 0.0002, 1)

	## Feine Fuge auf einer Seite (x-Fläche).
	func naht_seite(mitte: Vector3, t: float, h: float, d := 0.0011) -> void:
		for sy: float in [-1.0, 1.0]:
			k(lo, Vector3(0.0007, d, t), mitte + Vector3(0, sy * h * 0.5, 0), 0.0002, 1)
			k(lo, Vector3(0.0007, h, d), mitte + Vector3(0, 0, sy * t * 0.5), 0.0002, 1)

	## Reihe gleicher Teile (Lüftungsschlitze, Rillen, Rippen).
	func reihe(mat: Material, g: Vector3, start: Vector3, schritt: Vector3, n: int, rad := 0.0004) -> void:
		for i in n:
			k(mat, g, start + schritt * i, rad, 1)

	## Vier Gummifüße unter der Konsole.
	func fuesse(b: float, t: float, r := 0.008, h := 0.003) -> void:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				w(lo, r, h, Vector3(sx * (b * 0.5 - r * 2.2), 0, sz * (t * 0.5 - r * 2.2)), Vector3.ZERO, 12, 0.0008)

	func netz() -> ArrayMesh:
		var am := ArrayMesh.new()
		for key in _folge:
			(_st[key] as SurfaceTool).commit(am)
			am.surface_set_material(am.get_surface_count() - 1, _mat[key])
		return am


## Bauplan eines Modells (einmal je Modell gebaut, Netze geteilt).
static func _plan(sid: String, farbe: Color) -> Dictionary:
	var id := modell(sid)
	var key := id if id != "allgemein" else "allgemein:" + farbe.to_html()
	if _plaene.has(key):
		return _plaene[key]
	var p := { "id": id, "koerper": Bau.new(loch()), "klappe": null, "art": "", "medium": "", "medium_masse": Vector3.ZERO,
		"medium_von": Vector3(0, 0.1, 0), "einlass": Transform3D(), "kabel": Vector3(0, 0.03, -masse(id).z * 0.5), "farbe": farbe }
	match id:
		"gc": _gc(p)
		"ps1": _ps1(p)
		"ps2": _ps2(p)
		"wii": _wii(p)
		"n64": _n64(p)
		"snes": _snes(p)
		"megadrive": _megadrive(p)
		"dreamcast": _dreamcast(p)
		"xbox": _xbox(p)
		"switch": _switch(p)
		"pc": _pc(p)
		"nes": _nes(p)
		"saturn": _saturn(p)
		"ps3": _ps3(p)
		"xbox360": _xbox360(p)
		"wiiu": _wiiu(p)
		"pce": _pce(p)
		"mastersystem": _mastersystem(p)
		"atari2600": _atari(p)
		"arcade": _arcade(p)
		_:
			if HANDHELD.has(id):
				_handheld(p, id)
			else:
				_allgemein(p, farbe)
	p["netz"] = (p.koerper as Bau).netz()
	if p.klappe != null:
		p["klappe_netz"] = (p.klappe as Bau).netz()
	var m := masse(id)
	p["fern_netz"] = F.kiste(m * Vector3(0.98, 0.95, 0.98), minf(0.01, m.y * 0.3), false, 1)
	p["fern_mat"] = p.get("haupt", kunststoff(Color("#2a2b2f")))
	_plaene[key] = p
	return p


static func _mi(mesh: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Eine Konsole als Knoten: Ursprung Mitte unten, Vorderseite +z. Meta: masse, einlass (Knoten,
## an dem das Medium landet), medium, medium_masse, medium_von, klappe/klappe_zu/klappe_auf, led
## und led2 (Materialien), kabel (Austritt hinten).
static func bauen(sid: String, farbe := Color("#3a3c42")) -> Node3D:
	var p := _plan(sid, farbe)
	var id := str(p.id)
	var m := masse(id)
	var k := Node3D.new()
	k.name = "konsole_" + sid
	var nah := _mi(p.netz)
	nah.visibility_range_end = FERN
	k.add_child(nah)
	var fern := _mi(p.fern_netz, p.fern_mat)
	fern.position = Vector3(0, m.y * 0.475, 0)
	fern.visibility_range_begin = FERN
	k.add_child(fern)
	var eltern: Node3D = k
	if p.has("klappe_netz"):
		var kl := Node3D.new()
		kl.name = "klappe"
		kl.transform = p.klappe_zu
		k.add_child(kl)
		var kmi := _mi(p.klappe_netz)
		kmi.visibility_range_end = FERN
		kl.add_child(kmi)
		k.set_meta("klappe", kl)
		k.set_meta("klappe_zu", p.klappe_zu)
		k.set_meta("klappe_auf", p.klappe_auf)
		if str(p.art) == "lade":
			eltern = kl
	var ein := Node3D.new()
	ein.name = "einlass"
	ein.transform = p.einlass
	eltern.add_child(ein)
	k.set_meta("einlass", ein)
	for nm in ["led", "led2"]:
		if p.has(nm):
			var spec: Array = p[nm]
			var mat := _led_mat(spec[2])
			var lmi := _mi(spec[0], mat)
			lmi.transform = spec[1]
			k.add_child(lmi)
			k.set_meta(nm, mat)
			k.set_meta(nm + "_farbe", spec[2])
			k.set_meta(nm + "_an", float(spec[3]) if spec.size() > 3 else LED_AN)
	k.set_meta("masse", m)
	k.set_meta("system", sid)
	k.set_meta("medium", p.medium)
	k.set_meta("medium_masse", p.medium_masse)
	k.set_meta("medium_von", p.medium_von)
	k.set_meta("kabel", p.kabel)
	return k


## LED als runder Punkt (r, Achse nach vorn bzw. oben) oder als Kiste.
static func _led_rund(p: Dictionary, nm: String, r: float, pos: Vector3, farbe: Color, nach_vorn := true, an := LED_AN) -> void:
	p[nm] = [F.walze(r, 0.0012, 0.0004, 12), Bau._t(Vector3(90, 0, 0) if nach_vorn else Vector3.ZERO, pos), farbe, an]


static func _led_kiste(p: Dictionary, nm: String, g: Vector3, mitte: Vector3, farbe: Color, an := LED_AN) -> void:
	p[nm] = [F.kiste(g, minf(g.x, minf(g.y, g.z)) * 0.3, false, 1), Bau._t(Vector3.ZERO, mitte), farbe, an]


## Deckel mit Scharnier hinten: auf = um x nach hinten geklappt.
static func _deckel(p: Dictionary, kl: Bau, scharnier: Vector3, winkel := -78.0) -> void:
	p.klappe = kl
	p.art = "deckel"
	p["klappe_zu"] = Transform3D(Basis(), scharnier)
	p["klappe_auf"] = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(winkel)), scharnier)


## Lade vorn: auf = nach vorn herausgefahren.
static func _lade(p: Dictionary, kl: Bau, ort: Vector3, weg: float) -> void:
	p.klappe = kl
	p.art = "lade"
	p["klappe_zu"] = Transform3D(Basis(), ort)
	p["klappe_auf"] = Transform3D(Basis(), ort + Vector3(0, 0, weg))


# --- Die Modelle ----------------------------------------------------------------------------------

## Würfel in Indigo mit Griff hinten, rundem Deckel oben, vier Buchsen vorn, zwei Kartenklappen.
static func _gc(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var indigo := kunststoff(Color("#4b3f8e"), 0.62, 0.45)
	var indigo_d := kunststoff(Color("#392f6e"), 0.7, 0.35)
	var grau := kunststoff(Color("#2b2a31"), 0.75, 0.3)
	var knopf := kunststoff(Color("#5f5889"), 0.5, 0.5)
	p.haupt = indigo
	var vz := 0.0805
	b.s(grau, Vector3(0.136, 0.007, 0.146), 0, 0, 0, 0.004)
	b.s(indigo, Vector3(0.150, 0.100, 0.161), 0, 0.007, 0, 0.011, 3)
	# Mulde für den Deckel, dunkler abgesetzt.
	b.k(indigo_d, Vector3(0.132, 0.0016, 0.128), Vector3(0, 0.1068, -0.006), 0.012)
	# Griff hinten: zwei Arme, der Bügel leicht abgesenkt.
	for sx: float in [-1.0, 1.0]:
		b.k(indigo, Vector3(0.013, 0.011, 0.036), Vector3(sx * 0.0655, 0.097, -vz - 0.016), 0.004)
	b.k(indigo, Vector3(0.144, 0.011, 0.013), Vector3(0, 0.095, -vz - 0.034), 0.0048, 3)
	# Vorn: Band mit vier Controller-Buchsen, darüber zwei Kartenklappen mit Fuge.
	b.k(indigo_d, Vector3(0.140, 0.026, 0.002), Vector3(0, 0.03, vz + 0.0002), 0.004)
	for i in 4:
		b.buchse(grau, -0.054 + i * 0.036, 0.03, vz + 0.0018, 0.026, 0.015)
	for sx: float in [-1.0, 1.0]:
		b.k(b.lo, Vector3(0.044, 0.016, 0.0012), Vector3(sx * 0.035, 0.07, vz + 0.0002), 0.002, 1)
		b.k(indigo, Vector3(0.042, 0.014, 0.002), Vector3(sx * 0.035, 0.07, vz + 0.0006), 0.002, 1)
		b.k(indigo_d, Vector3(0.012, 0.0025, 0.001), Vector3(sx * 0.035, 0.0635, vz + 0.0016), 0.0008, 1)
	# Oben vorn: Power, Reset und der große Öffner.
	b.w(knopf, 0.0085, 0.0035, Vector3(-0.05, 0.1068, 0.068), Vector3.ZERO, 24)
	b.w(knopf, 0.0058, 0.003, Vector3(-0.026, 0.1068, 0.069), Vector3.ZERO, 20)
	b.w(knopf, 0.011, 0.0042, Vector3(0.047, 0.1068, 0.067), Vector3.ZERO, 28)
	# Lüftung links (Lüfter) und hinten, Anschlüsse hinten.
	b.reihe(b.lo, Vector3(0.0014, 0.0035, 0.09), Vector3(-0.0752, 0.03, -0.01), Vector3(0, 0.0075, 0), 8)
	b.reihe(b.lo, Vector3(0.09, 0.0028, 0.0014), Vector3(0, 0.035, -vz - 0.0002), Vector3(0, 0.0065, 0), 5)
	var kl := Bau.new(loch())
	kl.w(indigo, 0.059, 0.0055, Vector3(0, 0, 0.059), Vector3.ZERO, 48, 0.0018)
	kl.ring(indigo_d, 0.052, 0.0009, Vector3(0, 0.0056, 0.059))
	kl.w(indigo_d, 0.006, 0.0008, Vector3(0, 0.0055, 0.104), Vector3.ZERO, 12)
	_deckel(p, kl, Vector3(0, 0.1084, -0.065))
	p.einlass = Transform3D(Basis(), Vector3(0, 0.099, -0.006))
	p.medium = "minidisc"
	p.medium_von = Vector3(0, 0.1, 0.02)
	_led_rund(p, "led", 0.0021, Vector3(-0.05, 0.096, vz - 0.0005), Color("#5be37a"))
	p.kabel = Vector3(0.03, 0.05, -vz)


## Flaches Grau mit Deckel links, Rücken hinten, rundem Öffner, Power und Reset rechts vorn.
static func _ps1(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var grau := kunststoff(Color("#c8c6bf"), 0.6, 0.4)
	var grau_d := kunststoff(Color("#a7a59e"), 0.62, 0.4)
	var dunkel := kunststoff(Color("#5d5d61"), 0.6, 0.35)
	var knopf := kunststoff(Color("#9c9a94"), 0.5, 0.45)
	p.haupt = grau
	var vz := 0.094
	b.fuesse(0.27, 0.188, 0.007)
	b.s(grau, Vector3(0.27, 0.043, 0.188), 0, 0.003, 0, 0.006, 3)
	b.s(grau, Vector3(0.27, 0.012, 0.045), 0, 0.045, -0.0715, 0.005, 3)
	b.k(grau_d, Vector3(0.262, 0.0016, 0.004), Vector3(0, 0.0468, -0.0475), 0.0008, 1)
	b.reihe(b.lo, Vector3(0.0022, 0.0008, 0.03), Vector3(0.03, 0.0572, -0.072), Vector3(0.0068, 0, 0), 14)
	b.ring(b.lo, 0.0668, 0.0009, Vector3(-0.035, 0.0462, 0.022))
	b.w(knopf, 0.0125, 0.0036, Vector3(0.095, 0.0458, 0.0), Vector3.ZERO, 28)
	b.ring(grau_d, 0.0135, 0.0007, Vector3(0.095, 0.0462, 0.0))
	b.w(knopf, 0.0075, 0.0032, Vector3(0.078, 0.0458, 0.066), Vector3.ZERO, 20)
	b.w(knopf, 0.0075, 0.0032, Vector3(0.112, 0.0458, 0.066), Vector3.ZERO, 20)
	# Vorn: Fuge über die ganze Breite, zwei Buchsen, darüber die Kartenschlitze.
	b.k(b.lo, Vector3(0.262, 0.0011, 0.0008), Vector3(0, 0.03, vz + 0.0002), 0.0002, 1)
	for sx: float in [-1.0, 1.0]:
		b.buchse(dunkel, sx * 0.05, 0.015, vz + 0.0016, 0.036, 0.011)
		b.k(b.lo, Vector3(0.03, 0.0035, 0.0012), Vector3(sx * 0.05, 0.0375, vz + 0.0002), 0.0008, 1)
	b.reihe(b.lo, Vector3(0.0012, 0.003, 0.08), Vector3(-0.1352, 0.012, 0.0), Vector3(0, 0.006, 0), 5)
	var kl := Bau.new(loch())
	kl.w(grau, 0.0655, 0.0045, Vector3(0, 0, 0.066), Vector3.ZERO, 48, 0.0015)
	kl.ring(grau_d, 0.058, 0.0007, Vector3(0, 0.0046, 0.066))
	_deckel(p, kl, Vector3(-0.035, 0.0458, 0.022 - 0.066))
	p.einlass = Transform3D(Basis(), Vector3(-0.035, 0.04, 0.022))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.09, 0.01)
	_led_rund(p, "led", 0.0019, Vector3(0.095, 0.0458, 0.082), Color("#5be37a"), false)
	p.kabel = Vector3(0.06, 0.025, -vz)


## Liegend in Schwarz: gerippte Flosse links, Lade oben vorn, Buchsen und Kartenschlitze unten,
## Power mit LED und Auswurf rechts.
static func _ps2(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#1c1d21"), 0.5, 0.45)
	var glanz := kunststoff(Color("#121316"), 0.22, 0.7)
	var dunkel := kunststoff(Color("#2a2b30"), 0.55, 0.4)
	p.haupt = schwarz
	var vz := 0.091
	b.fuesse(0.29, 0.18, 0.008)
	b.s(schwarz, Vector3(0.2565, 0.074, 0.182), 0.0222, 0.004, 0, 0.005, 3)
	b.s(schwarz, Vector3(0.040, 0.072, 0.176), -0.1295, 0.005, 0, 0.004, 3)
	b.s(b.lo, Vector3(0.003, 0.068, 0.17), -0.1078, 0.007, 0, 0.0005, 1)
	for i in 6:
		var x := -0.1465 + i * 0.0068
		b.k(b.lo, Vector3(0.0024, 0.0012, 0.17), Vector3(x, 0.0772, 0), 0.0003, 1)
		b.k(b.lo, Vector3(0.0024, 0.062, 0.0012), Vector3(x, 0.041, 0.0882), 0.0003, 1)
	b.k(glanz, Vector3(0.244, 0.0012, 0.17), Vector3(0.0222, 0.0784, 0), 0.003, 1)
	b.reihe(b.lo, Vector3(0.0022, 0.0009, 0.05), Vector3(0.06, 0.079, -0.055), Vector3(0.0062, 0, 0), 13)
	# Fugen der Lade, Buchsen, Kartenschlitze, USB und i.LINK.
	b.k(b.lo, Vector3(0.196, 0.0012, 0.001), Vector3(0.0, 0.0636, vz + 0.0002), 0.0003, 1)
	b.k(b.lo, Vector3(0.196, 0.0012, 0.001), Vector3(0.0, 0.0404, vz + 0.0002), 0.0003, 1)
	for x: float in [-0.084, -0.047]:
		b.buchse(dunkel, x, 0.017, vz + 0.0016, 0.031, 0.0125)
		b.k(b.lo, Vector3(0.03, 0.004, 0.0012), Vector3(x, 0.032, vz + 0.0002), 0.0008, 1)
	b.buchse(null, -0.017, 0.02, vz + 0.0016, 0.012, 0.0055)
	b.buchse(null, -0.003, 0.02, vz + 0.0016, 0.012, 0.0055)
	b.buchse(null, 0.012, 0.02, vz + 0.0016, 0.008, 0.0045)
	b.k(glanz, Vector3(0.02, 0.009, 0.004), Vector3(0.122, 0.054, vz + 0.0005), 0.002)
	b.k(glanz, Vector3(0.02, 0.0075, 0.004), Vector3(0.122, 0.037, vz + 0.0005), 0.002)
	var kl := Bau.new(loch())
	kl.k(glanz, Vector3(0.192, 0.0215, 0.004), Vector3(0, 0, 0.0005), 0.002)
	kl.k(dunkel, Vector3(0.17, 0.004, 0.15), Vector3(0, -0.004, -0.076), 0.002)
	kl.ring(b.lo, 0.061, 0.0008, Vector3(0, -0.0018, -0.076))
	_lade(p, kl, Vector3(0.0, 0.052, vz), 0.135)
	p.einlass = Transform3D(Basis(), Vector3(0, -0.0013, -0.076))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.07, 0)
	_led_kiste(p, "led", Vector3(0.003, 0.003, 0.001), Vector3(0.1145, 0.054, vz + 0.0028), Color("#4ce06e"))
	_led_kiste(p, "led2", Vector3(0.003, 0.003, 0.001), Vector3(0.1145, 0.037, vz + 0.0028), Color("#3c7cff"), 1.6)
	p.kabel = Vector3(0.05, 0.03, -vz)


## Stehend auf dem Fuß, weißer Klavierlack: Einzug vorn mit blauem Licht, Power und Reset oben,
## Auswurf unten, Klappe für die Speicherkarte, Türen der Controller-Buchsen an der Seite.
static func _wii(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var weiss := kunststoff(Color("#eef0f2"), 0.24, 0.65)
	var grau := kunststoff(Color("#d3d6da"), 0.4, 0.5)
	p.haupt = weiss
	var vz := 0.1075
	b.s(grau, Vector3(0.07, 0.004, 0.17), 0, 0, 0, 0.002)
	b.s(weiss, Vector3(0.044, 0.157, 0.215), 0, 0.004, 0, 0.0065, 3)
	b.k(b.lo, Vector3(0.0034, 0.128, 0.0012), Vector3(0.006, 0.09, vz + 0.0002), 0.0012, 1)
	b.k(grau, Vector3(0.024, 0.0058, 0.0022), Vector3(0, 0.152, vz + 0.0004), 0.0015, 1)
	b.k(grau, Vector3(0.024, 0.0045, 0.0022), Vector3(0, 0.1445, vz + 0.0004), 0.0015, 1)
	b.k(grau, Vector3(0.016, 0.0055, 0.0022), Vector3(0.006, 0.019, vz + 0.0004), 0.0015, 1)
	b.naht_vorn(Vector3(-0.008, 0.036, vz + 0.0002), 0.02, 0.026)
	b.naht_seite(Vector3(-0.0222, 0.118, -0.02), 0.15, 0.05)
	b.naht_seite(Vector3(-0.0222, 0.062, -0.02), 0.15, 0.05)
	b.reihe(b.lo, Vector3(0.0007, 0.0022, 0.05), Vector3(0.0222, 0.03, -0.05), Vector3(0, 0.0065, 0), 14)
	b.reihe(b.lo, Vector3(0.032, 0.0022, 0.0007), Vector3(0, 0.06, -vz - 0.0002), Vector3(0, 0.0065, 0), 10)
	_led_kiste(p, "led", Vector3(0.004, 0.0018, 0.0008), Vector3(-0.007, 0.152, vz + 0.0017), Color("#5be37a"))
	_led_kiste(p, "led2", Vector3(0.0012, 0.124, 0.0008), Vector3(0.0012, 0.09, vz + 0.0006), Color("#4aa8ff"), 1.8)
	p.einlass = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.006, 0.09, 0.0))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0, 0.13)
	p.kabel = Vector3(0, 0.05, -vz)


## Breit und anthrazit: Buckel mit Modulschacht, Schieber für Power und Reset, Klappe für die
## Erweiterung, Lippe über vier Buchsen, rote LED.
static func _n64(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var anth := kunststoff(Color("#2a2b2e"), 0.62, 0.4)
	var anth_h := kunststoff(Color("#36373b"), 0.58, 0.4)
	var knopf := kunststoff(Color("#5a5b60"), 0.5, 0.45)
	p.haupt = anth
	var vz := 0.095
	b.fuesse(0.25, 0.18, 0.009)
	b.s(anth, Vector3(0.26, 0.046, 0.19), 0, 0.003, 0, 0.014, 3)
	b.s(anth, Vector3(0.236, 0.016, 0.176), 0, 0.047, -0.004, 0.012, 3)
	b.s(anth_h, Vector3(0.135, 0.012, 0.115), 0, 0.063, -0.02, 0.01, 3)
	b.k(b.lo, Vector3(0.09, 0.0012, 0.018), Vector3(0, 0.0752, -0.03), 0.0008, 1)
	b.k(anth, Vector3(0.088, 0.0014, 0.0012), Vector3(0, 0.0753, -0.03), 0.0003, 1)
	for sx: float in [-1.0, 1.0]:
		b.k(b.lo, Vector3(0.016, 0.0012, 0.034), Vector3(sx * 0.088, 0.0632, -0.02), 0.0006, 1)
		b.s(knopf, Vector3(0.014, 0.008, 0.012), sx * 0.088, 0.062, -0.012, 0.003)
	b.naht_oben(Vector3(0, 0.0633, 0.06), 0.11, 0.04)
	b.k(anth, Vector3(0.226, 0.009, 0.012), Vector3(0, 0.046, vz - 0.004), 0.004)
	for i in 4:
		b.buchse(anth_h, -0.072 + i * 0.048, 0.022, vz + 0.0016, 0.026, 0.014)
	b.reihe(b.lo, Vector3(0.003, 0.0012, 0.03), Vector3(-0.1, 0.0632, -0.072), Vector3(0.0075, 0, 0), 6)
	b.reihe(b.lo, Vector3(0.003, 0.0012, 0.03), Vector3(0.0625, 0.0632, -0.072), Vector3(0.0075, 0, 0), 6)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.0828, -0.03))
	p.medium = "modul"
	p.medium_masse = Vector3(0.116, 0.075, 0.018)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_rund(p, "led", 0.0024, Vector3(-0.105, 0.036, vz - 0.0005), Color("#ff3a2c"))
	p.kabel = Vector3(0.05, 0.03, -vz)


## Hellgrau mit runder Front, Modulschacht oben mit Auswurf davor, Schieber für Power und Reset.
static func _snes(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var grau := kunststoff(Color("#cbc9c3"), 0.6, 0.4)
	var grau_d := kunststoff(Color("#8e8c94"), 0.55, 0.45)
	p.haupt = grau
	var vz := 0.121
	b.fuesse(0.19, 0.23, 0.009)
	b.s(grau, Vector3(0.2, 0.05, 0.242), 0, 0.003, 0, 0.022, 3)
	b.s(grau, Vector3(0.17, 0.022, 0.17), 0, 0.05, -0.025, 0.014, 3)
	b.k(b.lo, Vector3(0.094, 0.0012, 0.016), Vector3(0, 0.0722, -0.03), 0.0008, 1)
	b.s(grau_d, Vector3(0.04, 0.007, 0.018), 0, 0.0698, 0.03, 0.004)
	for sx: float in [-1.0, 1.0]:
		b.k(b.lo, Vector3(0.02, 0.0012, 0.03), Vector3(sx * 0.06, 0.0532, 0.075), 0.0006, 1)
		b.s(grau_d, Vector3(0.018, 0.008, 0.012), sx * 0.06, 0.052, 0.08, 0.003)
		b.buchse(grau_d, sx * 0.03, 0.022, vz + 0.0016, 0.022, 0.014)
	b.k(b.lo, Vector3(0.18, 0.0011, 0.0008), Vector3(0, 0.038, vz + 0.0002), 0.0002, 1)
	b.reihe(b.lo, Vector3(0.0025, 0.0012, 0.028), Vector3(-0.05, 0.0722, -0.08), Vector3(0.007, 0, 0), 15)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.0782, -0.03))
	p.medium = "modul"
	p.medium_masse = Vector3(0.12, 0.088, 0.02)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_rund(p, "led", 0.0022, Vector3(-0.075, 0.03, vz - 0.0005), Color("#ff3a2c"))
	p.kabel = Vector3(0.05, 0.03, -vz)


## Schwarz mit dem großen Ring oben (feine Rillen), Schacht in der Mitte, Power- und
## Lautstärkeschieber, Kopfhörerbuchse, Reset, zwei Buchsen vorn.
static func _megadrive(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#141416"), 0.4, 0.55)
	var grau := kunststoff(Color("#2c2c30"), 0.5, 0.45)
	var rille := kunststoff(Color("#232326"), 0.6, 0.4)
	p.haupt = schwarz
	var vz := 0.106
	b.fuesse(0.27, 0.2, 0.009)
	b.s(schwarz, Vector3(0.28, 0.05, 0.212), 0, 0.003, 0, 0.012, 3)
	b.w(schwarz, 0.098, 0.012, Vector3(0, 0.051, -0.008), Vector3.ZERO, 56, 0.004)
	b.w(schwarz, 0.055, 0.0045, Vector3(0, 0.0625, -0.008), Vector3.ZERO, 44, 0.0015)
	for r: float in [0.064, 0.072, 0.08, 0.088]:
		b.ring(rille, r, 0.0008, Vector3(0, 0.0632, -0.008), Vector3(90, 0, 0), 56)
	b.k(b.lo, Vector3(0.075, 0.0012, 0.016), Vector3(0, 0.0672, -0.008), 0.0008, 1)
	b.k(schwarz, Vector3(0.073, 0.0014, 0.0012), Vector3(0, 0.0673, -0.008), 0.0003, 1)
	b.k(b.lo, Vector3(0.024, 0.0012, 0.012), Vector3(-0.105, 0.0532, 0.078), 0.0006, 1)
	b.s(grau, Vector3(0.008, 0.007, 0.01), -0.11, 0.052, 0.078, 0.002)
	b.k(b.lo, Vector3(0.03, 0.0012, 0.01), Vector3(0.098, 0.0532, 0.08), 0.0006, 1)
	b.s(grau, Vector3(0.006, 0.006, 0.008), 0.09, 0.052, 0.08, 0.002)
	b.w(grau, 0.008, 0.0035, Vector3(0.076, 0.0525, 0.07), Vector3.ZERO, 20)
	b.w(b.lo, 0.0028, 0.0012, Vector3(0.11, 0.03, vz - 0.0005), Vector3(90, 0, 0), 12)
	for sx: float in [-1.0, 1.0]:
		b.buchse(grau, sx * 0.04, 0.022, vz + 0.0016, 0.034, 0.014)
	b.reihe(b.lo, Vector3(0.0012, 0.0025, 0.06), Vector3(0.1402, 0.02, -0.03), Vector3(0, 0.006, 0), 5)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.0792, -0.008))
	p.medium = "modul"
	p.medium_masse = Vector3(0.112, 0.085, 0.02)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_rund(p, "led", 0.0022, Vector3(-0.085, 0.0532, 0.082), Color("#ff3a2c"), false)
	p.kabel = Vector3(0.05, 0.03, -vz)


## Weiß, fast quadratisch, gerundete Front, großer runder Deckel, Öffner und Power oben vorn,
## vier Buchsen in einem helleren Band, Lüftergitter an der Seite.
static func _dreamcast(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var weiss := kunststoff(Color("#e8e6e1"), 0.55, 0.45)
	var weiss_d := kunststoff(Color("#d6d4ce"), 0.55, 0.45)
	var grau := kunststoff(Color("#b7b5b0"), 0.5, 0.45)
	var dunkel := kunststoff(Color("#5f6066"), 0.55, 0.4)
	p.haupt = weiss
	var vz := 0.098
	b.fuesse(0.18, 0.18, 0.008)
	b.s(weiss, Vector3(0.19, 0.058, 0.196), 0, 0.003, 0, 0.02, 3)
	b.s(weiss, Vector3(0.176, 0.012, 0.18), 0, 0.058, -0.006, 0.012, 3)
	b.ring(b.lo, 0.0688, 0.0009, Vector3(0, 0.0702, -0.01))
	b.w(grau, 0.0115, 0.004, Vector3(0.068, 0.0695, 0.07), Vector3.ZERO, 28)
	b.w(grau, 0.0085, 0.0036, Vector3(-0.068, 0.0695, 0.07), Vector3.ZERO, 24)
	b.k(weiss_d, Vector3(0.172, 0.022, 0.002), Vector3(0, 0.02, vz + 0.0002), 0.004)
	for i in 4:
		b.buchse(dunkel, -0.06 + i * 0.04, 0.02, vz + 0.0016, 0.026, 0.0135)
	b.reihe(b.lo, Vector3(0.0012, 0.0024, 0.05), Vector3(0.0952, 0.016, -0.02), Vector3(0, 0.0055, 0), 7)
	var kl := Bau.new(loch())
	kl.w(weiss_d, 0.0675, 0.005, Vector3(0, 0, 0.0675), Vector3.ZERO, 52, 0.0018)
	kl.dreh(weiss_d, PackedVector2Array([Vector2(0.06, 0), Vector2(0.05, 0.0018), Vector2(0.0, 0.0024)]), Vector3(0, 0.005, 0.0675))
	_deckel(p, kl, Vector3(0, 0.07, -0.0775))
	p.einlass = Transform3D(Basis(), Vector3(0, 0.064, -0.01))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.1, 0.02)
	_led_rund(p, "led", 0.002, Vector3(-0.05, 0.0703, 0.08), Color("#ff9a3a"), false)
	p.kabel = Vector3(0.05, 0.03, -vz)


## Groß und schwarz: erhabener Deckel mit rundem Juwel in der Mitte (leuchtet grün, ohne Zeichen),
## Lade vorn, vier große Buchsen, Power mit Leuchtring und Auswurf rechts.
static func _xbox(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#19191b"), 0.5, 0.45)
	var schwarz_h := kunststoff(Color("#242427"), 0.45, 0.5)
	var juwel := kunststoff(Color("#0f1a10"), 0.18, 0.8)
	var gruen := kunststoff(Color("#3c6b2c"), 0.45, 0.5)
	p.haupt = schwarz
	var vz := 0.13
	b.fuesse(0.3, 0.24, 0.01, 0.004)
	b.s(schwarz, Vector3(0.32, 0.08, 0.26), 0, 0.004, 0, 0.018, 3)
	b.s(schwarz_h, Vector3(0.29, 0.016, 0.23), 0, 0.084, -0.005, 0.02, 3)
	b.dreh(schwarz_h, PackedVector2Array([Vector2(0.07, 0), Vector2(0.055, 0.004), Vector2(0.04, 0.0055)]), Vector3(0, 0.1, -0.005))
	b.w(juwel, 0.03, 0.002, Vector3(0, 0.1048, -0.005), Vector3.ZERO, 40, 0.001)
	b.k(b.lo, Vector3(0.176, 0.0012, 0.001), Vector3(0, 0.0712, vz + 0.0002), 0.0003, 1)
	b.k(b.lo, Vector3(0.176, 0.0012, 0.001), Vector3(0, 0.0488, vz + 0.0002), 0.0003, 1)
	for i in 4:
		b.buchse(schwarz_h, -0.105 + i * 0.07, 0.024, vz + 0.0016, 0.034, 0.018)
	b.w(schwarz_h, 0.0085, 0.003, Vector3(0.13, 0.066, vz - 0.001), Vector3(90, 0, 0), 24)
	b.w(schwarz_h, 0.0065, 0.003, Vector3(0.13, 0.045, vz - 0.001), Vector3(90, 0, 0), 20)
	b.k(gruen, Vector3(0.012, 0.0016, 0.001), Vector3(0.13, 0.0035, vz - 0.001), 0.0004, 1)
	b.reihe(b.lo, Vector3(0.0014, 0.004, 0.2), Vector3(-0.1602, 0.02, 0), Vector3(0, 0.009, 0), 6)
	b.reihe(b.lo, Vector3(0.0014, 0.004, 0.2), Vector3(0.1602, 0.02, 0), Vector3(0, 0.009, 0), 6)
	var kl := Bau.new(loch())
	kl.k(schwarz_h, Vector3(0.17, 0.02, 0.004), Vector3(0, 0, 0.0005), 0.002)
	kl.k(kunststoff(Color("#2f3033"), 0.5, 0.4), Vector3(0.15, 0.004, 0.15), Vector3(0, -0.004, -0.076), 0.002)
	kl.ring(b.lo, 0.061, 0.0008, Vector3(0, -0.0018, -0.076))
	_lade(p, kl, Vector3(0, 0.06, vz), 0.135)
	p.einlass = Transform3D(Basis(), Vector3(0, -0.0013, -0.076))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.07, 0)
	p.led = [F.ring(0.0098, 0.0011, TAU, 24, 6), Bau._t(Vector3.ZERO, Vector3(0.13, 0.066, vz + 0.002)), Color("#6bff5a"), LED_AN]
	p.led2 = [F.ring(0.0315, 0.0012, TAU, 40, 6), Bau._t(Vector3(90, 0, 0), Vector3(0, 0.1068, -0.005)), Color("#59d64a"), 1.5]
	p.kabel = Vector3(0.06, 0.04, -vz)


## Dock in Dunkelgrau, die Konsole steckt darin: Bildschirm über der Front, links und rechts die
## Joy-Con (Neonrot und Neonblau) mit Sticks und Tasten; Karte oben links, grüne LED am Dock.
static func _switch(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var dock := kunststoff(Color("#2e2f33"), 0.65, 0.35)
	var schwarz := kunststoff(Color("#151517"), 0.25, 0.65)
	var rot := kunststoff(Color("#ff4b3e"), 0.45, 0.5)
	var blau := kunststoff(Color("#11b4e6"), 0.45, 0.5)
	var dunkel := kunststoff(Color("#232326"), 0.5, 0.45)
	p.haupt = dock
	b.s(dock, Vector3(0.173, 0.006, 0.058), 0, 0, 0, 0.003)
	b.s(dock, Vector3(0.173, 0.104, 0.03), 0, 0.004, -0.013, 0.008, 3)
	b.s(dock, Vector3(0.168, 0.07, 0.008), 0, 0.004, 0.022, 0.004, 3)
	b.k(b.lo, Vector3(0.1, 0.0011, 0.0007), Vector3(0, 0.06, 0.0262), 0.0002, 1)
	# Die Konsole im Dock: Mitte, Glas, Joy-Con.
	var y0 := 0.018
	b.s(schwarz, Vector3(0.173, 0.102, 0.0139), 0, y0, 0.006, 0.004, 3)
	for sx: float in [-1.0, 1.0]:
		var jc := rot if sx < 0 else blau
		b.s(jc, Vector3(0.036, 0.102, 0.0139), sx * (0.0865 + 0.018), y0, 0.006, 0.009, 3)
		var jx := sx * (0.0865 + 0.018)
		b.w(dunkel, 0.0072, 0.003, Vector3(jx, y0 + (0.072 if sx < 0 else 0.042), 0.0128), Vector3(90, 0, 0), 20)
		b.w(schwarz, 0.0052, 0.0035, Vector3(jx, y0 + (0.072 if sx < 0 else 0.042), 0.0148), Vector3(90, 0, 0), 20)
		var ky := y0 + (0.042 if sx < 0 else 0.072)
		for d: Vector2 in [Vector2(0, 0.009), Vector2(0, -0.009), Vector2(0.009, 0), Vector2(-0.009, 0)]:
			b.w(dunkel, 0.0032, 0.0018, Vector3(jx + d.x, ky + d.y, 0.0128), Vector3(90, 0, 0), 14)
		b.k(dunkel, Vector3(0.026, 0.006, 0.012), Vector3(jx, y0 + 0.1, 0.006), 0.003)
	b.k(b.lo, Vector3(0.022, 0.0012, 0.004), Vector3(-0.05, y0 + 0.1026, 0.006), 0.0005, 1)
	b.k(dunkel, Vector3(0.008, 0.0016, 0.004), Vector3(-0.066, y0 + 0.1026, 0.006), 0.0005, 1)
	b.k(dunkel, Vector3(0.016, 0.0016, 0.004), Vector3(-0.078, y0 + 0.1026, 0.006), 0.0005, 1)
	p.led2 = [F.kiste(Vector3(0.152, 0.03, 0.0008), 0.0006, false, 1), Bau._t(Vector3.ZERO, Vector3(0, 0.0905, 0.0134)), Color("#cfd6e6"), 0.55]
	_led_kiste(p, "led", Vector3(0.004, 0.0012, 0.0008), Vector3(0.07, 0.009, 0.0262), Color("#5be37a"))
	p.einlass = Transform3D(Basis(), Vector3(-0.05, y0 + 0.088, 0.006))
	p.medium = "karte"
	p.medium_masse = Vector3(0.021, 0.031, 0.0033)
	p.medium_von = Vector3(0, 0.06, 0)
	p.kabel = Vector3(0, 0.03, -0.028)


## Kleiner PC in eloxiertem Anthrazit: schwarze Front mit Power-Taste und weißem Leuchtring, USB
## und Kopfhörer vorn, Lochblech oben, Schlitze an der Seite.
static func _pc(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var alu := eloxal(Color("#3a3c41"))
	var front := kunststoff(Color("#111214"), 0.3, 0.6)
	p.haupt = alu
	var vz := 0.1
	b.fuesse(0.18, 0.18, 0.009, 0.004)
	b.s(alu, Vector3(0.2, 0.064, 0.2), 0, 0.004, 0, 0.006, 3)
	b.k(front, Vector3(0.194, 0.058, 0.003), Vector3(0, 0.036, vz + 0.0006), 0.003)
	b.w(alu, 0.0062, 0.0025, Vector3(0.078, 0.046, vz + 0.0018), Vector3(90, 0, 0), 24)
	b.buchse(null, -0.08, 0.022, vz + 0.0026, 0.013, 0.0055)
	b.buchse(null, -0.062, 0.022, vz + 0.0026, 0.013, 0.0055)
	b.buchse(null, -0.047, 0.022, vz + 0.0026, 0.009, 0.0035)
	b.w(b.lo, 0.0018, 0.0012, Vector3(-0.036, 0.022, vz + 0.0016), Vector3(90, 0, 0), 12)
	for i in 9:
		for j in 6:
			b.k(b.lo, Vector3(0.0055, 0.0008, 0.0055), Vector3(-0.056 + i * 0.014, 0.0682, -0.05 + j * 0.016), 0.0006, 1)
	b.reihe(b.lo, Vector3(0.0008, 0.003, 0.14), Vector3(0.1002, 0.016, -0.01), Vector3(0, 0.0075, 0), 6)
	b.reihe(b.lo, Vector3(0.0008, 0.003, 0.14), Vector3(-0.1002, 0.016, -0.01), Vector3(0, 0.0075, 0), 6)
	p.led = [F.ring(0.0072, 0.0009, TAU, 24, 6), Bau._t(Vector3.ZERO, Vector3(0.078, 0.046, vz + 0.0043)), Color("#e8f0ff"), 2.0]
	p.medium = ""
	p.kabel = Vector3(0.0, 0.03, -vz)


## Zweifarbiges Grau, Klappe vorn oben für das Modul, gerippter Deckel, Power und Reset mit roter LED.
static func _nes(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var hell := kunststoff(Color("#c9c7c2"), 0.6, 0.4)
	var dunkel := kunststoff(Color("#47474b"), 0.55, 0.4)
	var schwarz := kunststoff(Color("#1c1c1f"), 0.55, 0.4)
	p.haupt = hell
	var vz := 0.1015
	b.fuesse(0.24, 0.19, 0.008)
	b.s(hell, Vector3(0.254, 0.085, 0.203), 0, 0.004, 0, 0.004, 1)
	b.s(dunkel, Vector3(0.254, 0.032, 0.006), 0, 0.006, vz - 0.0015, 0.002, 1)
	b.reihe(b.lo, Vector3(0.1, 0.0012, 0.003), Vector3(0, 0.0894, -0.03), Vector3(0, 0, -0.008), 8)
	for i in 2:
		b.k(schwarz, Vector3(0.026, 0.009, 0.004), Vector3(-0.09 + i * 0.034, 0.022, vz + 0.003), 0.001)
	b.buchse(schwarz, 0.06, 0.02, vz + 0.0036, 0.02, 0.012)
	b.buchse(schwarz, 0.09, 0.02, vz + 0.0036, 0.02, 0.012)
	var kl := Bau.new(loch())
	kl.k(dunkel, Vector3(0.16, 0.004, 0.05), Vector3(0, 0, -0.025), 0.0015, 1)
	kl.reihe(b.lo, Vector3(0.15, 0.0008, 0.0016), Vector3(0, 0.002, -0.042), Vector3(0, 0, 0.006), 5)
	_deckel(p, kl, Vector3(0, 0.0892, vz - 0.002), 70.0)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.06, 0.0))
	p.medium = "modul"
	p.medium_masse = Vector3(0.12, 0.022, 0.133)
	p.medium_von = Vector3(0, 0.0, 0.16)
	_led_kiste(p, "led", Vector3(0.004, 0.003, 0.001), Vector3(-0.11, 0.022, vz + 0.003), Color("#ff3a2c"))
	p.kabel = Vector3(0.05, 0.03, -vz)


## Dunkelgrau mit rundem Deckel, Power, Reset und Öffner, Kartenschacht hinten, zwei Buchsen vorn.
static func _saturn(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var grau := kunststoff(Color("#2f3136"), 0.5, 0.45)
	var grau_h := kunststoff(Color("#3d4047"), 0.45, 0.5)
	p.haupt = grau
	var vz := 0.115
	b.fuesse(0.25, 0.22, 0.009)
	b.s(grau, Vector3(0.26, 0.07, 0.23), 0, 0.003, 0, 0.016, 3)
	b.s(grau_h, Vector3(0.23, 0.01, 0.2), 0, 0.072, -0.006, 0.012, 3)
	b.ring(b.lo, 0.0682, 0.0009, Vector3(-0.02, 0.0822, 0.0))
	b.k(b.lo, Vector3(0.09, 0.0012, 0.01), Vector3(0, 0.0822, -0.085), 0.0005, 1)
	for i in 3:
		b.w(grau, 0.0072 + (0.003 if i == 2 else 0.0), 0.0034, Vector3(0.085, 0.0815, 0.07 - i * 0.03), Vector3.ZERO, 22)
	for sx: float in [-1.0, 1.0]:
		b.buchse(grau_h, sx * 0.05, 0.026, vz + 0.0016, 0.03, 0.013)
	var kl := Bau.new(loch())
	kl.w(grau_h, 0.067, 0.004, Vector3(0, 0, 0.067), Vector3.ZERO, 48, 0.0015)
	_deckel(p, kl, Vector3(-0.02, 0.0818, -0.067))
	p.einlass = Transform3D(Basis(), Vector3(-0.02, 0.076, 0.0))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.1, 0.02)
	_led_rund(p, "led", 0.002, Vector3(0.085, 0.0822, 0.095), Color("#5be37a"), false)
	p.kabel = Vector3(0.05, 0.03, -vz)


## Klavierlack in Schwarz mit gewölbtem Deckel, Einzug vorn, Silberband, Sensortasten und USB.
static func _ps3(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var lack := kunststoff(Color("#0e0e10"), 0.16, 0.85)
	var silber := kunststoff(Color("#9ea2a8"), 0.3, 0.8)
	var matt := kunststoff(Color("#1a1a1c"), 0.6, 0.35)
	p.haupt = lack
	var vz := 0.137
	b.s(matt, Vector3(0.3, 0.012, 0.25), 0, 0, 0, 0.004)
	b.s(lack, Vector3(0.325, 0.08, 0.274), 0, 0.01, 0, 0.03, 3)
	b.k(silber, Vector3(0.318, 0.004, 0.003), Vector3(0, 0.014, vz - 0.0002), 0.001)
	b.k(b.lo, Vector3(0.14, 0.0025, 0.0012), Vector3(0, 0.06, vz + 0.0002), 0.0008, 1)
	for i in 4:
		b.buchse(null, -0.13 + i * 0.017, 0.03, vz + 0.0016, 0.012, 0.005)
	b.k(silber, Vector3(0.012, 0.0008, 0.0006), Vector3(0.125, 0.06, vz + 0.0006), 0.0002, 1)
	b.k(silber, Vector3(0.012, 0.0008, 0.0006), Vector3(0.125, 0.045, vz + 0.0006), 0.0002, 1)
	b.reihe(b.lo, Vector3(0.0014, 0.004, 0.22), Vector3(-0.1627, 0.03, 0), Vector3(0, 0.008, 0), 5)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.06, -0.01))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0, 0.2)
	_led_kiste(p, "led", Vector3(0.004, 0.002, 0.0006), Vector3(0.14, 0.06, vz + 0.0006), Color("#5be37a"))
	p.kabel = Vector3(0.05, 0.04, -vz)


## Weiß mit eingezogenen grauen Gittern an den Seiten, Lade links, Leuchtring rechts.
static func _xbox360(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var weiss := kunststoff(Color("#e8e8ea"), 0.3, 0.6)
	var grau := kunststoff(Color("#b9bbbf"), 0.5, 0.5)
	var silber := kunststoff(Color("#c9ccd1"), 0.3, 0.7)
	p.haupt = weiss
	var vz := 0.129
	b.fuesse(0.29, 0.24, 0.01)
	b.s(weiss, Vector3(0.27, 0.083, 0.258), 0, 0.0, 0, 0.012, 3)
	for sx: float in [-1.0, 1.0]:
		b.s(grau, Vector3(0.022, 0.075, 0.25), sx * 0.142, 0.004, 0, 0.008, 3)
		b.reihe(b.lo, Vector3(0.0012, 0.0035, 0.22), Vector3(sx * 0.1532, 0.012, 0), Vector3(0, 0.0075, 0), 8)
	b.k(silber, Vector3(0.012, 0.0012, 0.001), Vector3(0.09, 0.06, vz + 0.0002), 0.0003, 1)
	b.w(silber, 0.013, 0.003, Vector3(0.09, 0.04, vz - 0.001), Vector3(90, 0, 0), 32)
	b.naht_vorn(Vector3(0.06, 0.015, vz + 0.0002), 0.06, 0.014)
	var kl := Bau.new(loch())
	kl.k(weiss, Vector3(0.15, 0.018, 0.004), Vector3(0, 0, 0.0005), 0.002)
	kl.k(grau, Vector3(0.14, 0.004, 0.14), Vector3(0, -0.004, -0.072), 0.002)
	_lade(p, kl, Vector3(-0.045, 0.052, vz), 0.13)
	p.einlass = Transform3D(Basis(), Vector3(0, -0.0013, -0.072))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0.07, 0)
	p.led = [F.ring(0.0145, 0.0011, TAU, 32, 6), Bau._t(Vector3.ZERO, Vector3(0.09, 0.04, vz + 0.0022)), Color("#6bff5a"), LED_AN]
	p.kabel = Vector3(0.05, 0.03, -vz)


## Flach liegend in Klavierlack: Einzug mit blauem Licht, Power mit LED, Klappe für USB und SD.
static func _wiiu(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var lack := kunststoff(Color("#121214"), 0.18, 0.8)
	var grau := kunststoff(Color("#2a2a2d"), 0.45, 0.5)
	p.haupt = lack
	var vz := 0.1345
	b.fuesse(0.16, 0.25, 0.008)
	b.s(lack, Vector3(0.172, 0.043, 0.269), 0, 0.003, 0, 0.012, 3)
	b.k(b.lo, Vector3(0.128, 0.0034, 0.0012), Vector3(-0.01, 0.031, vz + 0.0002), 0.0012, 1)
	b.k(grau, Vector3(0.014, 0.006, 0.002), Vector3(0.068, 0.031, vz + 0.0004), 0.0015, 1)
	b.naht_vorn(Vector3(0.0, 0.013, vz + 0.0002), 0.1, 0.012)
	b.reihe(b.lo, Vector3(0.0012, 0.003, 0.2), Vector3(0.0862, 0.016, 0), Vector3(0, 0.007, 0), 4)
	_led_kiste(p, "led", Vector3(0.003, 0.0016, 0.0006), Vector3(0.068, 0.0362, vz + 0.0008), Color("#4aa8ff"))
	_led_kiste(p, "led2", Vector3(0.124, 0.0011, 0.0006), Vector3(-0.01, 0.0336, vz + 0.0006), Color("#4aa8ff"), 1.2)
	p.einlass = Transform3D(Basis(), Vector3(-0.01, 0.031, -0.01))
	p.medium = "disc"
	p.medium_von = Vector3(0, 0, 0.2)
	p.kabel = Vector3(0.0, 0.025, -vz)


## Klein und hell: Kartenschacht vorn, Schieber, eine Buchse.
static func _pce(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var weiss := kunststoff(Color("#e6e3da"), 0.55, 0.45)
	var grau := kunststoff(Color("#5a5a5f"), 0.55, 0.4)
	p.haupt = weiss
	b.fuesse(0.13, 0.13, 0.006)
	b.s(weiss, Vector3(0.14, 0.035, 0.14), 0, 0.003, 0, 0.006, 3)
	b.s(grau, Vector3(0.11, 0.003, 0.05), 0, 0.035, -0.02, 0.0015, 1)
	b.k(b.lo, Vector3(0.06, 0.0025, 0.0012), Vector3(0, 0.024, 0.0702), 0.0006, 1)
	b.s(grau, Vector3(0.012, 0.005, 0.01), -0.045, 0.036, 0.05, 0.002)
	b.buchse(grau, 0.04, 0.012, 0.0716, 0.014, 0.01)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.024, 0.02))
	p.medium = "karte"
	p.medium_masse = Vector3(0.054, 0.002, 0.085)
	p.medium_von = Vector3(0, 0, 0.1)
	_led_kiste(p, "led", Vector3(0.003, 0.002, 0.0008), Vector3(-0.045, 0.024, 0.0706), Color("#ff3a2c"))
	p.kabel = Vector3(0, 0.02, -0.07)


## Lang und schwarz mit roten Kanten, Schacht oben, Kartenschlitz vorn, Pause-Taste.
static func _mastersystem(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#18181a"), 0.45, 0.5)
	var rot := kunststoff(Color("#b8342c"), 0.45, 0.5)
	p.haupt = schwarz
	var vz := 0.085
	b.fuesse(0.35, 0.16, 0.008)
	b.s(schwarz, Vector3(0.365, 0.06, 0.17), 0, 0.003, 0, 0.008, 1)
	b.s(schwarz, Vector3(0.2, 0.008, 0.12), 0.06, 0.062, -0.01, 0.004, 1)
	b.k(rot, Vector3(0.365, 0.003, 0.003), Vector3(0, 0.05, vz), 0.001, 1)
	b.k(b.lo, Vector3(0.09, 0.0012, 0.016), Vector3(0.06, 0.0702, -0.02), 0.0008, 1)
	b.k(b.lo, Vector3(0.06, 0.003, 0.0012), Vector3(-0.1, 0.03, vz + 0.0002), 0.0006, 1)
	b.k(rot, Vector3(0.018, 0.006, 0.012), Vector3(-0.15, 0.064, 0.05), 0.002)
	for sx: float in [-1.0, 1.0]:
		b.buchse(b.lo, 0.1 + sx * 0.025, 0.02, vz + 0.0016, 0.03, 0.013)
	p.einlass = Transform3D(Basis(), Vector3(0.06, 0.0782, -0.02))
	p.medium = "modul"
	p.medium_masse = Vector3(0.1, 0.075, 0.02)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_kiste(p, "led", Vector3(0.004, 0.002, 0.0008), Vector3(-0.15, 0.02, vz + 0.0006), Color("#ff3a2c"))
	p.kabel = Vector3(0.05, 0.03, -vz)


## Schwarz gerippt mit Holzfront und sechs Kippschaltern, Schacht oben.
static func _atari(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#1a1a1c"), 0.5, 0.45)
	var holz := kunststoff(Color("#6b4a2b"), 0.55, 0.35)
	var metall := kunststoff(Color("#b9bcc2"), 0.3, 0.8)
	p.haupt = schwarz
	var vz := 0.115
	b.fuesse(0.33, 0.21, 0.01)
	b.s(schwarz, Vector3(0.35, 0.06, 0.23), 0, 0.003, 0, 0.008, 1)
	b.s(schwarz, Vector3(0.33, 0.026, 0.16), 0, 0.062, -0.03, 0.008, 1)
	b.k(holz, Vector3(0.34, 0.03, 0.004), Vector3(0, 0.035, vz), 0.0015, 1)
	b.reihe(b.lo, Vector3(0.0016, 0.0008, 0.15), Vector3(-0.15, 0.0882, -0.03), Vector3(0.0125, 0, 0), 25)
	b.k(b.lo, Vector3(0.1, 0.0012, 0.02), Vector3(0, 0.0882, -0.03), 0.0008, 1)
	for i in 6:
		var x := -0.14 + i * 0.056 if i < 3 else 0.028 + (i - 3) * 0.056
		b.w(metall, 0.003, 0.01, Vector3(x, 0.063, 0.07), Vector3(-25, 0, 0), 10)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.094, -0.03))
	p.medium = "modul"
	p.medium_masse = Vector3(0.08, 0.06, 0.02)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_rund(p, "led", 0.0022, Vector3(-0.14, 0.064, 0.09), Color("#ff3a2c"), false)
	p.kabel = Vector3(0.05, 0.03, -vz)


## Arcade-Stick: schwarzes Pult mit rotem Kugelgriff und sechs Tasten.
static func _arcade(p: Dictionary) -> void:
	var b: Bau = p.koerper
	var schwarz := kunststoff(Color("#18181a"), 0.55, 0.4)
	var rot := kunststoff(Color("#c8342c"), 0.3, 0.6)
	var weiss := kunststoff(Color("#e8e6e1"), 0.35, 0.55)
	p.haupt = schwarz
	b.fuesse(0.3, 0.16, 0.01)
	b.s(schwarz, Vector3(0.32, 0.07, 0.18), 0, 0.003, 0, 0.012, 3)
	b.w(schwarz, 0.004, 0.045, Vector3(-0.09, 0.073, 0.0), Vector3.ZERO, 12)
	b.dreh(rot, PackedVector2Array([Vector2(0, -0.019), Vector2(0.012, -0.016), Vector2(0.019, 0.0), Vector2(0.012, 0.016), Vector2(0, 0.019)]),
			Vector3(-0.09, 0.135, 0))
	for i in 6:
		var x := 0.01 + (i % 3) * 0.04 + (0.005 if i >= 3 else 0.0)
		var z := -0.02 + (0.042 if i >= 3 else 0.0)
		b.w(rot if i < 3 else weiss, 0.012, 0.007, Vector3(x, 0.073, z), Vector3.ZERO, 24)
	_led_rund(p, "led", 0.002, Vector3(0.14, 0.073, 0.07), Color("#5be37a"), false)
	p.medium = ""
	p.kabel = Vector3(0, 0.03, -0.09)


## Handhelds, flach liegend: quer (Bildschirm in der Mitte), hoch (Bildschirm oben) oder
## zugeklappt (zwei Schalen, Scharnier hinten).
static func _handheld(p: Dictionary, id: String) -> void:
	var b: Bau = p.koerper
	var h: Dictionary = HANDHELD[id]
	var m := masse(id)
	var farbe := Color(str(h.farbe))
	var gehaeuse := kunststoff(farbe, 0.2 if bool(h.get("glanz", false)) else 0.55, 0.65 if bool(h.get("glanz", false)) else 0.45)
	var rahmen := kunststoff(Color("#232327"), 0.4, 0.5)
	var knopf := kunststoff(Color(str(h.get("knopf", "#2a2b2f"))), 0.45, 0.5)
	p.haupt = gehaeuse
	var oben := m.y
	match str(h.form):
		"quer":
			var mitte_b := m.x - m.z
			b.s(gehaeuse, Vector3(mitte_b, m.y, m.z), 0, 0, 0, m.y * 0.45, 3)
			for sx: float in [-1.0, 1.0]:
				b.w(gehaeuse, m.z * 0.5, m.y, Vector3(sx * mitte_b * 0.5, 0, 0), Vector3.ZERO, 40, m.y * 0.45)
			var sc: Vector2 = h.schirm
			b.k(rahmen, Vector3(sc.x + 0.012, 0.001, sc.y + 0.01), Vector3(0, oben, -0.002), 0.003, 1)
			p.led2 = [F.kiste(Vector3(sc.x, 0.0008, sc.y), 0.0005, false, 1), Bau._t(Vector3.ZERO, Vector3(0, oben + 0.0006, -0.002)), Color("#c9d2c0"), 0.5]
			var dx := mitte_b * 0.5 + m.z * 0.12
			b.k(knopf, Vector3(0.022, 0.003, 0.007), Vector3(-dx, oben, 0.004), 0.0012, 1)
			b.k(knopf, Vector3(0.007, 0.003, 0.022), Vector3(-dx, oben, 0.004), 0.0012, 1)
			b.w(knopf, 0.005, 0.002, Vector3(dx + 0.006, oben - 0.0005, -0.004), Vector3.ZERO, 16)
			b.w(knopf, 0.005, 0.002, Vector3(dx - 0.008, oben - 0.0005, 0.008), Vector3.ZERO, 16)
			b.k(knopf, Vector3(0.008, 0.0015, 0.0035), Vector3(-0.012, oben, m.z * 0.5 - 0.008), 0.001, 1)
			b.k(knopf, Vector3(0.008, 0.0015, 0.0035), Vector3(0.004, oben, m.z * 0.5 - 0.008), 0.001, 1)
			for sx: float in [-1.0, 1.0]:
				b.k(knopf, Vector3(0.03, m.y * 0.55, 0.006), Vector3(sx * (mitte_b * 0.5 + 0.004), m.y * 0.55, -m.z * 0.5 + 0.002), 0.002)
			_led_rund(p, "led", 0.0015, Vector3(-sc.x * 0.5 - 0.004, oben + 0.0002, -sc.y * 0.5), Color("#5be37a"), false)
			p.einlass = Transform3D(Basis(), Vector3(0, m.y * 0.5, -m.z * 0.5 + 0.012))
			p.medium_masse = Vector3(0.057, 0.008, 0.035) if id != "psp" else Vector3(0.064, 0.0042, 0.069)
		"hoch":
			b.s(gehaeuse, m, 0, 0, 0, 0.007, 3)
			var sc2: Vector2 = h.schirm
			b.k(rahmen, Vector3(m.x - 0.014, 0.001, sc2.y + 0.018), Vector3(0, oben, -m.z * 0.5 + sc2.y * 0.5 + 0.02), 0.003, 1)
			p.led2 = [F.kiste(Vector3(sc2.x * 0.8, 0.0008, sc2.y * 0.75), 0.0005, false, 1),
				Bau._t(Vector3.ZERO, Vector3(0, oben + 0.0006, -m.z * 0.5 + sc2.y * 0.5 + 0.02)), Color("#b9c4a0"), 0.5]
			var kz := m.z * 0.5 - 0.035
			b.k(rahmen, Vector3(0.022, 0.003, 0.007), Vector3(-m.x * 0.25, oben, kz), 0.0012, 1)
			b.k(rahmen, Vector3(0.007, 0.003, 0.022), Vector3(-m.x * 0.25, oben, kz), 0.0012, 1)
			b.w(knopf, 0.0048, 0.002, Vector3(m.x * 0.22, oben - 0.0005, kz - 0.004), Vector3.ZERO, 16)
			b.w(knopf, 0.0048, 0.002, Vector3(m.x * 0.32, oben - 0.0005, kz - 0.009), Vector3.ZERO, 16)
			for sx: float in [-1.0, 1.0]:
				b.k(rahmen, Vector3(0.009, 0.0015, 0.003), Vector3(sx * 0.008, oben, m.z * 0.5 - 0.014), 0.001, 1, Vector3(0, 25, 0))
			b.reihe(b.lo, Vector3(0.0014, 0.0008, 0.012), Vector3(m.x * 0.22, oben, m.z * 0.5 - 0.012), Vector3(0.004, 0, 0), 5)
			_led_rund(p, "led", 0.0014, Vector3(-m.x * 0.5 + 0.009, oben + 0.0002, -m.z * 0.5 + 0.03), Color("#ff3a2c"), false)
			p.einlass = Transform3D(Basis(), Vector3(0, m.y * 0.5, -m.z * 0.5 + 0.02))
			p.medium_masse = Vector3(0.057, 0.008, 0.065)
		_:
			var halb := m.y * 0.5
			b.s(gehaeuse, Vector3(m.x, halb - 0.0004, m.z), 0, 0, 0, 0.005, 3)
			b.s(gehaeuse, Vector3(m.x, halb - 0.0004, m.z), 0, halb + 0.0004, 0, 0.005, 3)
			b.k(b.lo, Vector3(m.x - 0.004, 0.0008, m.z - 0.004), Vector3(0, halb, 0), 0.002, 1)
			b.w(rahmen, 0.004, m.x - 0.03, Vector3(-m.x * 0.5 + 0.015, halb, -m.z * 0.5 + 0.003), Vector3(0, 0, -90), 16)
			_led_rund(p, "led", 0.0012, Vector3(m.x * 0.5 - 0.01, halb, m.z * 0.5 + 0.0002), Color("#4aa8ff"))
			p.einlass = Transform3D(Basis(), Vector3(0, 0.003, -m.z * 0.5 + 0.015))
			p.medium_masse = Vector3(0.033, 0.0038, 0.035)
	p.medium = "karte"
	p.medium_von = Vector3(0, 0, -0.07)
	p.kabel = Vector3(0, 0.008, -m.z * 0.5)


## Eigenes System: schlichtes Gehäuse in seiner Farbe mit Schacht, zwei Buchsen und LED.
static func _allgemein(p: Dictionary, farbe: Color) -> void:
	var b: Bau = p.koerper
	var haupt := kunststoff(farbe.darkened(0.15), 0.55, 0.45)
	var dunkel := kunststoff(farbe.darkened(0.55), 0.55, 0.4)
	p.haupt = haupt
	b.fuesse(0.23, 0.19, 0.008)
	b.s(haupt, Vector3(0.24, 0.057, 0.2), 0, 0.003, 0, 0.008, 3)
	b.k(b.lo, Vector3(0.09, 0.0012, 0.016), Vector3(0, 0.0602, -0.02), 0.0008, 1)
	for sx: float in [-1.0, 1.0]:
		b.buchse(dunkel, sx * 0.04, 0.022, 0.1016, 0.026, 0.013)
	b.reihe(b.lo, Vector3(0.0012, 0.003, 0.12), Vector3(0.1202, 0.016, 0), Vector3(0, 0.007, 0), 5)
	p.einlass = Transform3D(Basis(), Vector3(0, 0.07, -0.02))
	p.medium = "modul"
	p.medium_masse = Vector3(0.08, 0.06, 0.018)
	p.medium_von = Vector3(0, 0.1, 0)
	_led_rund(p, "led", 0.0022, Vector3(0.095, 0.035, 0.0995), Color("#5be37a"))
	p.kabel = Vector3(0.05, 0.03, -0.1)


# --- Im Lowboard ----------------------------------------------------------------------------------

## Konsolen nach der Staffelung in das Lowboard (root, Möbel-Raum) stellen; z_vorn: Vorderkante,
## z_hinten: Rückwand. Dazu je ein Kabel nach hinten (alle zusammen ein Netz). Gibt { id: Knoten }.
static func einraeumen(root: Node3D, lage: Dictionary, z_vorn: float, z_hinten: float) -> Dictionary:
	var out := {}
	var kabel := Bau.new(loch())
	var gummi := kunststoff(Color("#141416"), 0.7, 0.3)
	for pl: Dictionary in lage.get("plaetze", []):
		var id := str(pl.id)
		var sys: Dictionary = Config.system(id) if id != PC else {}
		var k := bauen(id, Color(str(sys.get("color", "#3a3c42"))))
		var m: Vector3 = k.get_meta("masse")
		k.position = Vector3(float(pl.x), float(pl.y), z_vorn - m.z * 0.5)
		root.add_child(k)
		out[id] = k
		var aus: Vector3 = k.position + (k.get_meta("kabel") as Vector3)
		var boden := float(pl.y) + 0.004
		var weg := _kabel_weg(aus, Vector3(float(pl.x) * 0.92, boden, z_hinten + 0.004), boden)
		kabel.teil(gummi, _rohr(weg, 0.0024), Transform3D())
		k.set_meta("kabel_weg", weg)
	if not out.is_empty():
		root.add_child(_mi(kabel.netz()))
	root.set_meta("konsolen", out)
	return out


## Weg des Kabels: aus der Rückseite nach hinten, auf den Boden des Fachs, zur Rückwand.
static func _kabel_weg(aus: Vector3, ziel: Vector3, boden: float) -> PackedVector3Array:
	var a := aus
	var b := Vector3(aus.x, boden, aus.z - 0.03)
	var c := ziel
	var out := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	out.append(c + Vector3(0, 0.01, -0.004))
	return out


## Schlauch entlang eines Wegs (Kabel), sechs Seiten.
static func _rohr(weg: PackedVector3Array, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := weg.size()
	var seiten := 6
	for i in n:
		var vor := (weg[mini(i + 1, n - 1)] - weg[maxi(i - 1, 0)]).normalized()
		var hilf := Vector3.UP if absf(vor.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := vor.cross(hilf).normalized()
		var v := vor.cross(u).normalized()
		for j in seiten:
			var a := float(j) / seiten * TAU
			var nrm := u * cos(a) + v * sin(a)
			st.set_color(Color.WHITE)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(j) / seiten, float(i) / n))
			st.add_vertex(weg[i] + nrm * r)
	for i in n - 1:
		for j in seiten:
			var a0 := i * seiten + j
			var a1 := i * seiten + (j + 1) % seiten
			var b0 := a0 + seiten
			var b1 := a1 + seiten
			for x in [a0, b0, a1, a1, b0, b1]:
				st.add_index(x)
	return st.commit()


# --- Strom, Medium, Einlegen ----------------------------------------------------------------------

## Betriebs-LED (und zweites Licht: Einzug, Juwel, Bildschirm) an oder aus.
static func strom(k: Node3D, an: bool) -> void:
	for nm in ["led", "led2"]:
		if not k.has_meta(nm):
			continue
		var m: StandardMaterial3D = k.get_meta(nm)
		var c: Color = k.get_meta(nm + "_farbe")
		m.emission_energy_multiplier = float(k.get_meta(nm + "_an", LED_AN)) if an else 0.0
		m.albedo_color = c if an else c.darkened(0.75)
	k.set_meta("an", an)


static func ist_an(k: Node3D) -> bool:
	return bool(k.get_meta("an", false))


## Das Medium des Spiels: Disc (mit Aufdruck in der Farbe der Hülle), Modul oder Karte (Etikett).
static func medium_bauen(k: Node3D, farbe: Color) -> Node3D:
	var art := str(k.get_meta("medium", ""))
	var n := Node3D.new()
	n.name = "medium"
	match art:
		"disc", "minidisc":
			var r := 0.06 if art == "disc" else 0.04
			n.add_child(_teil_mi(F.walze(r, 0.0012, 0.0004, 48), kunststoff(Color("#d9dce2"), 0.16, 0.9), Vector3(0, -0.0006, 0)))
			n.add_child(_teil_mi(F.walze(r - 0.0025, 0.0013, 0.0004, 48), kunststoff(farbe, 0.5, 0.4), Vector3(0, -0.0006, 0)))
			n.add_child(_teil_mi(F.walze(0.0085, 0.0015, 0.0003, 20), kunststoff(Color("#c7cad0"), 0.3, 0.6), Vector3(0, -0.0007, 0)))
			n.add_child(_teil_mi(F.walze(0.0075, 0.0017, 0.0003, 20), loch(), Vector3(0, -0.0008, 0)))
		"modul", "karte":
			var g: Vector3 = k.get_meta("medium_masse")
			var grau := kunststoff(Color("#6f7075") if art == "modul" else Color("#3b3c40"), 0.55, 0.4)
			n.add_child(_teil_mi(F.kiste(g, minf(0.002, minf(g.x, minf(g.y, g.z)) * 0.3), false, 1), grau, Vector3.ZERO))
			if g.y >= g.z:
				n.add_child(_teil_mi(F.kiste(Vector3(g.x * 0.78, g.y * 0.55, 0.0008), 0.0003, false, 1), kunststoff(farbe, 0.6, 0.35),
					Vector3(0, -g.y * 0.08, g.z * 0.5)))
			else:
				n.add_child(_teil_mi(F.kiste(Vector3(g.x * 0.8, 0.0008, g.z * 0.6), 0.0003, false, 1), kunststoff(farbe, 0.6, 0.35),
					Vector3(0, g.y * 0.5, g.z * 0.1)))
		_:
			return null
	return n


static func _teil_mi(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := _mi(mesh, mat)
	mi.position = pos
	return mi


## Startort des Mediums in der Welt (davor bzw. darüber).
static func start_ort(k: Node3D) -> Transform3D:
	var ein: Node3D = k.get_meta("einlass")
	var auf := ein.global_transform
	if k.has_meta("klappe") and ein.get_parent() == k.get_meta("klappe"):
		# Lade: über der offenen Lade.
		auf = k.global_transform * (k.get_meta("klappe_auf") as Transform3D) * ein.transform
	return auf.translated_local(k.get_meta("medium_von") as Vector3)


## Klappe bzw. Lade auf (läuft, während die Hülle anfliegt).
static func oeffnen(wer: Node, k: Node3D, verzug := 0.0) -> void:
	if not k.has_meta("klappe") or U.reduziert():
		return
	var kl: Node3D = k.get_meta("klappe")
	wer.create_tween().tween_property(kl, "transform", k.get_meta("klappe_auf"), U.T_RAUM).set_trans(Tween.TRANS_CUBIC).set_ease(
			Tween.EASE_IN_OUT).set_delay(verzug)


## Medium (in der Welt, am Startort) hinein, Klappe zu, Strom an, Lichtpunkt am Kabel entlang.
static func einlegen(wer: Node, k: Node3D, medium: Node3D) -> Tween:
	var ein: Node3D = k.get_meta("einlass")
	_raus(k)
	var t := wer.create_tween()
	var kl: Node3D = k.get_meta("klappe") if k.has_meta("klappe") else null
	if medium != null:
		k.set_meta("drin", medium)
	if U.reduziert():
		if medium != null:
			medium.reparent(ein, false)
			medium.transform = Transform3D()
		if kl != null:
			kl.transform = k.get_meta("klappe_zu")
		strom(k, true)
		t.tween_interval(U.T_ANTWORT)
		return t
	if medium != null:
		var von := medium.global_transform
		t.tween_method(func(x: float) -> void:
			if is_instance_valid(medium) and is_instance_valid(ein):
				medium.global_transform = von.interpolate_with(ein.global_transform, x)
		, 0.0, 1.0, U.T_RAUM).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(func() -> void:
			if is_instance_valid(medium) and is_instance_valid(ein):
				medium.reparent(ein, false)
				medium.transform = Transform3D())
	if kl != null:
		t.tween_property(kl, "transform", k.get_meta("klappe_zu"), U.T_RAUM if ein.get_parent() == kl else U.T_ORT).set_trans(
				Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Die Konsole kann bis hierher weg sein (das Lowboard wurde neu gebaut, während das Medium einflog).
	t.tween_callback(func() -> void:
		if is_instance_valid(k):
			strom(k, true)
			_puls(wer, k))
	if k.has_meta("led"):
		var led: StandardMaterial3D = k.get_meta("led")
		var an := float(k.get_meta("led_an", LED_AN))
		t.tween_method(func(e: float) -> void: led.emission_energy_multiplier = e, an * 2.4, an, U.T_ORT)
	return t


## Sofort eingelegt und an (das Zimmer kommt, während das Spiel schon läuft).
static func einstecken(k: Node3D, farbe: Color) -> void:
	if not k.has_meta("drin"):
		var m := medium_bauen(k, farbe)
		if m != null:
			(k.get_meta("einlass") as Node3D).add_child(m)
			k.set_meta("drin", m)
	strom(k, true)


static func _raus(k: Node3D) -> void:
	if k.has_meta("drin"):
		var alt: Variant = k.get_meta("drin")
		if alt is Node and is_instance_valid(alt):
			(alt as Node).queue_free()
		k.remove_meta("drin")


## Ein warmer Lichtpunkt läuft das Kabel entlang nach hinten (zum Fernseher).
static func _puls(wer: Node, k: Node3D) -> void:
	if not is_instance_valid(k) or not k.has_meta("kabel_weg") or k.get_parent() == null:
		return
	var weg: PackedVector3Array = k.get_meta("kabel_weg")
	var licht := StandardMaterial3D.new()
	licht.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	licht.albedo_color = Color(1.0, 0.86, 0.62)
	licht.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var kugel := SphereMesh.new()
	kugel.radius = 0.0042
	kugel.height = 0.0084
	kugel.radial_segments = 10
	kugel.rings = 5
	var p := _mi(kugel, licht)
	(k.get_parent() as Node3D).add_child(p)
	p.position = weg[0]
	var t := wer.create_tween()
	t.tween_method(func(x: float) -> void:
		if is_instance_valid(p):
			p.position = entlang(weg, x)
			licht.albedo_color.a = sin(PI * x) * 0.9
	, 0.0, 1.0, U.T_LICHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(p.queue_free)


## Punkt auf einem Weg (Anteil x der Länge).
static func entlang(weg: PackedVector3Array, x: float) -> Vector3:
	if weg.size() < 2:
		return weg[0] if weg.size() == 1 else Vector3.ZERO
	var laenge := 0.0
	for i in weg.size() - 1:
		laenge += weg[i].distance_to(weg[i + 1])
	var rest := clampf(x, 0.0, 1.0) * laenge
	for i in weg.size() - 1:
		var d := weg[i].distance_to(weg[i + 1])
		if rest <= d or i == weg.size() - 2:
			return weg[i].lerp(weg[i + 1], clampf(rest / maxf(d, 0.00001), 0.0, 1.0))
		rest -= d
	return weg[weg.size() - 1]

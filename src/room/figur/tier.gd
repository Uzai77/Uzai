extends Node3D
## Dein Haustier (Punkt 131 c): Katze, Hund, Fuchs, Hase oder kleiner Drache – eigene, rundliche
## Formen ohne Vorbild, Fell aus dem Haut-Shader (Bauch, Tigerstreifen, Flecken, Sternenfell),
## Gesicht gezeichnet (Augen, Mund). Alle Bewegungen gerechnet und ruhig: atmen, Ohren zucken,
## Schwanz pendeln, laufen (Hase hoppelt), sitzen, liegen, schlafen (eingerollt, ein leises
## „z“), sich freuen (hüpfen) und gestreichelt werden (Augen zu, Schwanz wedelt, ein Herz).
##
## Verhalten (verhalten(dt, lage)): folgt dir in kleinem Abstand und setzt sich zu dir; passiert
## lange nichts, legt es sich schlafen (im Körbchen, wenn es eines gibt); sitzt du vor dem
## Fernseher, legt es sich davor; bei neuen Erfolgen und Freischaltungen freut es sich. Ursprung:
## Boden unter der Körpermitte, Blick nach +z.

const D := preload("res://src/room/figur/figur_daten.gd")
const FF := preload("res://src/room/figur/figur_formen.gd")
const FS := preload("res://src/room/figur/figur_stoffe.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const EBENE := 1 << 12

var werte := {}
var art := "katze"
var name_text := ""
var zustand := "sitzen"          ## folgen, sitzen, liegen, schlafen, fernsehen, freuen, gestreichelt, hin
var _k := {}                     ## Teile: koerper, kopf, ohr_l/r, schwanz [..], beine {vl, vr, hl, hr}, fluegel
var _gesicht: ShaderMaterial
var _maul: ShaderMaterial
var _zett: Label3D
var _herz: MeshInstance3D
var _herz_t := -1.0
var _zett_t := 0.0

var _t := 0.0
var _phase := 0.0
var _vel := Vector3.ZERO
var _tempo := 0.0
var _yaw := 0.0
var _w := { "lauf": 0.0, "sitz": 1.0, "lieg": 0.0, "schlaf": 0.0, "freu": 0.0, "streich": 0.0 }
var _freu_t := -1.0
var _streich_t := -1.0
var _ohr_t := 0.0
var _blink_in := 3.0
var _blink_t := -1.0
var _blick := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var groesse := 1.0


func _init() -> void:
	_rng.seed = 11


# --- Bauen ---------------------------------------------------------------------------------------

func bauen(w: Dictionary) -> void:
	werte = D.pruefe_tier(w)
	art = str(werte.art)
	name_text = str(werte.name)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_k.clear()
	groesse = { "katze": 1.0, "hund": 1.12, "fuchs": 1.05, "hase": 0.95, "drache": 1.05 }.get(art, 1.0) as float
	var fell := D.farbe(D.FELL, str(werte.fell))
	var zweit := fell.lightened(0.62).lerp(Color("#f6efe4"), 0.6)
	if str(werte.fell) in ["weiss", "creme"]:
		zweit = fell.darkened(0.08).lerp(Color("#d9c5a8"), 0.25)
	if art == "drache":
		zweit = Color("#f3e2b6")
	var m_nr := { "uni": 0, "bauch": 1, "getigert": 2, "gefleckt": 3, "pfoten": 1, "sterne": 5 }.get(str(werte.muster), 0) as int
	var bauch_an := m_nr != 0 or art in ["fuchs", "drache"]
	var mk := 1 if (bauch_an and m_nr == 0) else m_nr
	var m_koerper := FS.fell(fell, zweit, mk, Vector3(0, -1, 0.15), 0.42 if bauch_an else 9.0, Vector3(0, 0, 1))
	var m_kopf := FS.fell(fell, zweit, mk if mk != 2 else 2, Vector3(0, -0.45, 1), 0.62 if bauch_an else 9.0, Vector3(0, 1, 0.3))
	var m_glied := FS.fell(fell, zweit, 2 if mk == 2 else (5 if mk == 5 else 0), Vector3(0, -1, 0), 9.0, Vector3(0, 1, 0))
	var m_pfote := FS.fell(zweit if str(werte.muster) == "pfoten" else fell, zweit, 0)
	var root := Node3D.new()
	root.name = "tier"
	root.scale = Vector3.ONE * groesse
	add_child(root)
	_k.wurzel = root
	var koerper := _knoten(root, Vector3(0, 0.17, 0))
	_k.koerper = koerper
	var rund := 1.12 if art == "hase" else 1.0
	_teil(koerper, FF.ei(Vector3(0.115, 0.105, 0.17) * rund, 26), m_koerper, Vector3(0, 0, -0.02))
	_teil(koerper, FF.ei(Vector3(0.1, 0.1, 0.1) * rund, 22), m_koerper, Vector3(0, 0.02, 0.08))
	# Kopf mit Schnauze und Nase; das Gesicht zeichnet der Shader.
	var kopf := _knoten(koerper, Vector3(0, 0.1, 0.14))
	_k.kopf = kopf
	_gesicht = (m_kopf as ShaderMaterial).duplicate() as ShaderMaterial
	_gesicht.set_shader_parameter("gesicht", true)
	_gesicht.set_shader_parameter("augen", 5 if art == "katze" else 6)
	_gesicht.set_shader_parameter("iris", Color("#8bbf4a") if art == "katze" else (Color("#e0a33a") if art == "drache" else Color("#3b2a20")))
	_gesicht.set_shader_parameter("augen_lage", Vector2(0.4, 0.14))
	_gesicht.set_shader_parameter("augen_groesse", 1.05 if art != "drache" else 1.15)
	_gesicht.set_shader_parameter("brauen", 2)
	_gesicht.set_shader_parameter("mund", -1)
	_gesicht.set_shader_parameter("wangen", 1 if art in ["katze", "hase", "drache"] else 0)
	_gesicht.set_shader_parameter("nase", false)
	var kr := { "hund": 0.098, "hase": 0.094, "drache": 0.1 }.get(art, 0.092) as float
	_teil(kopf, FF.ei(Vector3(kr, kr * 0.95, kr * 0.92), 30), _gesicht, Vector3(0, 0.06, 0.02))
	var schnauze := { "hund": Vector3(0.052, 0.04, 0.06), "fuchs": Vector3(0.042, 0.033, 0.068), "drache": Vector3(0.05, 0.038, 0.055) }.get(art,
			Vector3(0.046, 0.034, 0.04)) as Vector3
	_maul = FS.fell(zweit if bauch_an else fell.lightened(0.12), zweit, 0).duplicate() as ShaderMaterial
	_maul.set_shader_parameter("gesicht", true)
	_maul.set_shader_parameter("augen", -1)
	_maul.set_shader_parameter("brauen", 2)
	_maul.set_shader_parameter("mund", 4)
	_maul.set_shader_parameter("mund_y", -0.32)
	_maul.set_shader_parameter("mund_groesse", 2.4)
	_maul.set_shader_parameter("wangen", 0)
	_maul.set_shader_parameter("nase", false)
	var sz := 0.06 + kr * 0.55
	_teil(kopf, FF.ei(schnauze, 20), _maul, Vector3(0, 0.03, sz))
	_teil(kopf, FF.ei(Vector3(0.016, 0.011, 0.011), 12), S.lack(Color("#2a1f1f") if art != "drache" else Color("#5b3a3a"), 0.25, 0.7),
			Vector3(0, 0.05, sz + schnauze.z - 0.004))
	_ohren(kopf, fell, zweit, m_kopf, kr)
	# Beine: vorn schlank, hinten mit Keule; Pfoten (bei „Weiße Pfoten“ hell).
	_k.beine = {}
	for b in [["vl", 1.0, 0.1], ["vr", -1.0, 0.1], ["hl", 1.0, -0.11], ["hr", -1.0, -0.11]]:
		var hinten := float(b[2]) < 0.0
		var n := _knoten(koerper, Vector3(float(b[1]) * 0.062, -0.045, float(b[2])))
		if hinten:
			_teil(n, FF.ei(Vector3(0.048, 0.062, 0.07), 18), m_koerper, Vector3(0, 0.02, 0.0))
		_teil(n, FF.glied(0.03, 0.026, 0.085), m_glied)
		var pfote := 0.042 if (art == "hase" and hinten) else 0.032
		_teil(n, FF.ei(Vector3(0.032, 0.021, pfote + 0.006), 14), m_pfote, Vector3(0, -0.1, 0.012 + (0.025 if art == "hase" and hinten else 0.0)))
		_k.beine[str(b[0])] = n
	_schwanz(koerper, fell, zweit, m_glied, m_koerper)
	if art == "drache":
		_drache(koerper, zweit, fell)
	match str(werte.halsband):
		"band":
			_teil(koerper, F.ring(0.07, 0.011, TAU, 28, 8), S.lack(Color("#b23a35"), 0.4, 0.5), Vector3(0, 0.085, 0.11), Vector3(PI * 0.5 + 0.6, 0, 0))
			_teil(koerper, FF.ei(Vector3.ONE * 0.016, 12), FS.gold(), Vector3(0, 0.035, 0.165))
		"tuch":
			var tuch := FS.kleid(Color("#2f6a6c"), "punkte", Color("#f3f1ec"), 0.4)
			_teil(koerper, F.ring(0.072, 0.016, TAU, 28, 8), tuch, Vector3(0, 0.085, 0.11), Vector3(PI * 0.5 + 0.6, 0, 0))
			_teil(koerper, F.dreh(PackedVector2Array([Vector2(0, 0), Vector2(0.045, 0.06), Vector2(0, 0.065)]), 3, [1]), tuch, Vector3(0, -0.02, 0.17),
					Vector3(PI, 0, 0), Vector3(1, 1, 0.3))
	# Zzz beim Schlafen und ein kleines Herz beim Streicheln.
	_zett = Label3D.new()
	_zett.text = "z"
	_zett.font = UzTheme.font("ui_bold")
	_zett.font_size = 64
	_zett.pixel_size = 0.0016
	_zett.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zett.modulate = Color(1, 1, 1, 0)
	_zett.outline_size = 0
	_zett.no_depth_test = false
	_zett.layers = EBENE
	add_child(_zett)
	_herz = MeshInstance3D.new()
	_herz.mesh = FF.herz(0.05)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("#e8737f")
	hm.emission_enabled = true
	hm.emission = Color("#e8737f")
	hm.emission_energy_multiplier = 0.4
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_herz.material_override = hm
	_herz.visible = false
	_herz.layers = EBENE
	add_child(_herz)
	bild(0.0)


func _knoten(eltern: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	eltern.add_child(n)
	return n


func _teil(eltern: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, skal := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = skal
	mi.layers = EBENE
	eltern.add_child(mi)
	return mi


func _ohren(kopf: Node3D, fell: Color, zweit: Color, m_kopf: Material, kr: float) -> void:
	var innen := FS.fell(Color("#e8a7a0") if art != "drache" else zweit, zweit, 0)
	for s: float in [1.0, -1.0]:
		var o := _knoten(kopf, Vector3(s * kr * 0.58, 0.06 + kr * 0.72, 0.0))
		_k["ohr" + ("_l" if s > 0 else "_r")] = o
		match art:
			"katze", "fuchs":
				var h := 0.07 if art == "katze" else 0.095
				var b := 0.04 if art == "katze" else 0.048
				var kegel := PackedVector2Array([Vector2(0, 0), Vector2(b, 0.004), Vector2(b * 0.55, h * 0.55), Vector2(0.004, h), Vector2(0, h)])
				_teil(o, F.dreh(kegel, 18, [1]), m_kopf, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.45))
				_teil(o, F.dreh(kegel, 14, [1]), innen, Vector3(0, 0.006, 0.01), Vector3.ZERO, Vector3(0.62, 0.78, 0.3))
				o.rotation = Vector3(-0.1, 0, -s * 0.28)
				if art == "fuchs":
					_teil(o, FF.ei(Vector3(0.014, 0.02, 0.008), 10), FS.fell(Color("#2e2b2a"), zweit, 0), Vector3(0, h - 0.012, 0))
			"hund":
				_teil(o, FF.ei(Vector3(0.034, 0.062, 0.016), 16), FS.fell(fell.darkened(0.25), zweit, 0), Vector3(s * 0.02, -0.045, 0))
				o.rotation = Vector3(0, 0, s * 0.35)
			"hase":
				_teil(o, FF.ei(Vector3(0.032, 0.088, 0.016), 18), m_kopf, Vector3(0, 0.075, 0))
				_teil(o, FF.ei(Vector3(0.019, 0.066, 0.008), 14), innen, Vector3(0, 0.072, 0.01))
				o.rotation = Vector3(-0.18, 0, -s * 0.16)
			"drache":
				var horn := PackedVector2Array([Vector2(0, 0), Vector2(0.016, 0.002), Vector2(0.006, 0.05), Vector2(0, 0.056)])
				_teil(o, F.dreh(horn, 12, [1]), FS.glanz(Color("#f1e3c4"), 0.4), Vector3(0, 0, -0.02), Vector3(-0.5, 0, 0))
				_teil(o, FF.ei(Vector3(0.012, 0.032, 0.03), 12), innen, Vector3(s * 0.035, -0.04, -0.01), Vector3(0, 0, -s * 0.9))
				o.rotation = Vector3(0, 0, -s * 0.2)


func _schwanz(koerper: Node3D, fell: Color, zweit: Color, m_glied: Material, m_koerper: Material) -> void:
	var kette: Array = []
	var eltern := _knoten(koerper, Vector3(0, 0.04, -0.17))
	match art:
		"katze":
			for i in 4:
				var n := _knoten(eltern if i == 0 else kette[i - 1], Vector3(0, 0, 0) if i == 0 else Vector3(0, -0.075, 0))
				_teil(n, FF.glied(0.022 - i * 0.002, 0.02 - i * 0.002, 0.08), m_glied)
				kette.append(n)
		"hund":
			for i in 2:
				var n := _knoten(eltern if i == 0 else kette[i - 1], Vector3.ZERO if i == 0 else Vector3(0, -0.075, 0))
				_teil(n, FF.glied(0.026 - i * 0.006, 0.02 - i * 0.006, 0.08), m_glied)
				kette.append(n)
		"fuchs":
			for i in 3:
				var n := _knoten(eltern if i == 0 else kette[i - 1], Vector3.ZERO if i == 0 else Vector3(0, -0.07, 0))
				var r := [0.04, 0.055, 0.05][i] as float
				_teil(n, FF.ei(Vector3(r, 0.07, r), 16), FS.fell(fell if i < 2 else zweit, zweit, 0), Vector3(0, -0.045, 0))
				kette.append(n)
		"hase":
			var n := _knoten(eltern, Vector3.ZERO)
			_teil(n, FF.ei(Vector3.ONE * 0.042, 16), FS.fell(zweit, zweit, 0), Vector3(0, -0.02, 0))
			kette.append(n)
		"drache":
			for i in 3:
				var n := _knoten(eltern if i == 0 else kette[i - 1], Vector3.ZERO if i == 0 else Vector3(0, -0.08, 0))
				_teil(n, FF.glied(0.035 - i * 0.009, 0.028 - i * 0.009, 0.085), m_koerper)
				kette.append(n)
			_teil(kette[2], F.dreh(PackedVector2Array([Vector2(0, 0), Vector2(0.03, 0.03), Vector2(0, 0.07)]), 4, [1]), FS.glanz(zweit.darkened(0.1), 0.5),
					Vector3(0, -0.13, 0), Vector3(PI, 0, 0), Vector3(1, 1, 0.3))
	_k.schwanz = kette


func _drache(koerper: Node3D, zweit: Color, fell: Color) -> void:
	var haut := FS.glanz(fell.darkened(0.18).lerp(zweit, 0.15), 0.55)
	var fl: Array = []
	for s: float in [1.0, -1.0]:
		var n := _knoten(koerper, Vector3(s * 0.06, 0.085, 0.0))
		_teil(n, FF.ei(Vector3(0.068, 0.036, 0.008), 18), haut, Vector3(s * 0.05, 0.03, -0.03), Vector3(0.35, s * 0.3, s * 0.75))
		_teil(n, FF.ei(Vector3(0.045, 0.026, 0.007), 14), haut, Vector3(s * 0.035, 0.005, -0.06), Vector3(0.2, s * 0.4, s * 0.45))
		fl.append(n)
	_k.fluegel = fl
	for i in 3:
		_teil(koerper, F.dreh(PackedVector2Array([Vector2(0, 0), Vector2(0.02, 0.0), Vector2(0, 0.04)]), 4, [1]), haut,
				Vector3(0, 0.1 - i * 0.012, -0.03 - i * 0.055), Vector3(-0.4, 0, 0), Vector3(1, 1, 0.4))


# --- Verhalten ------------------------------------------------------------------------------------

## Sich freuen (neuer Erfolg, Freischaltung).
func freuen() -> void:
	_freu_t = 0.0
	if zustand == "schlafen":
		zustand = "sitzen"


func streicheln() -> void:
	_streich_t = 0.0
	_herz_t = 0.0
	if zustand == "schlafen":
		zustand = "sitzen"


## Ein Schritt Verhalten. lage: { spieler: Vector3, spieler_yaw: float, ruhe: float (s ohne
## Eingabe), fernsehen: bool, tv: Vector3 (Platz davor, y = Blickrichtung als Winkel) oder null,
## tv_ziel: Vector3, korb: Vector3 oder null, frei: Callable(Vector3) -> Vector3 }.
func verhalten(dt: float, lage: Dictionary) -> void:
	var sp: Vector3 = lage.spieler
	var ziel := position
	var schauen: Variant = sp
	var neu := zustand
	if _freu_t >= 0.0 or _streich_t >= 0.0:
		neu = "freuen" if _freu_t >= 0.0 else "gestreichelt"
	elif bool(lage.get("fernsehen", false)) and lage.get("tv") != null:
		ziel = lage.tv
		schauen = lage.get("tv_ziel")
		neu = "fernsehen" if position.distance_to(ziel) < 0.12 else "hin"
	elif float(lage.get("ruhe", 0.0)) > 24.0:
		ziel = lage.korb if lage.get("korb") != null else position
		schauen = null
		neu = "schlafen" if position.distance_to(ziel) < 0.12 else "hin"
	else:
		# Folgen: hinter dir, leicht seitlich; nah genug: hinsetzen und dich ansehen.
		var y := float(lage.get("spieler_yaw", 0.0))
		var hinter := sp + Basis(Vector3.UP, y) * Vector3(0.55, 0, 0.75)
		var d := Vector2(position.x - sp.x, position.z - sp.z).length()
		if zustand in ["folgen", "hin"] and d > 1.05:
			ziel = hinter
			neu = "folgen"
		elif d > 1.7:
			ziel = hinter
			neu = "folgen"
		else:
			neu = "sitzen"
	zustand = neu
	# Bewegen: weich beschleunigen, um Möbel herum gleiten, nicht in dich hineinlaufen.
	var soll_v := Vector3.ZERO
	if zustand in ["folgen", "hin"]:
		var dv := ziel - position
		dv.y = 0
		var l := dv.length()
		if l > 0.05:
			var tempo := clampf(l * 1.6, 0.3, 1.9 if l > 2.5 else 1.3)
			soll_v = dv / l * tempo
	_vel = _vel.lerp(soll_v, 1.0 - exp(-dt * 5.0))
	var n := position + _vel * dt
	var weg := Vector2(n.x - sp.x, n.z - sp.z)
	if weg.length() < 0.42 and weg.length() > 0.001:
		var p2 := Vector2(sp.x, sp.z) + weg.normalized() * 0.42
		n = Vector3(p2.x, 0, p2.y)
	var frei: Callable = lage.get("frei", Callable())
	var korb: Variant = lage.get("korb")
	var zum_korb := korb is Vector3 and zustand in ["schlafen", "hin"] and Vector2(n.x - (korb as Vector3).x, n.z - (korb as Vector3).z).length() < 0.5
	if frei.is_valid() and not zum_korb:
		n = frei.call(n)
	_tempo = Vector2(n.x - position.x, n.z - position.z).length() / maxf(dt, 0.0001)
	position = Vector3(n.x, 0, n.z)
	# Drehen: in Laufrichtung, im Stand zu dem, was es ansieht.
	var soll_yaw := _yaw
	if _vel.length() > 0.12:
		soll_yaw = atan2(_vel.x, _vel.z)
	elif schauen is Vector3 and zustand in ["sitzen", "fernsehen", "freuen", "gestreichelt"]:
		var dz: Vector3 = (schauen as Vector3) - position
		if Vector2(dz.x, dz.z).length() > 0.2:
			soll_yaw = atan2(dz.x, dz.z)
	_yaw = lerp_angle(_yaw, soll_yaw, 1.0 - exp(-dt * (6.0 if _vel.length() > 0.12 else 2.5)))
	rotation.y = _yaw
	if schauen is Vector3:
		var lk := to_local(schauen as Vector3)
		_blick = _blick.lerp(Vector2(clampf(atan2(lk.x, lk.z), -0.7, 0.7), clampf(atan2(lk.y - 0.3, Vector2(lk.x, lk.z).length()), -0.3, 0.6)), 1.0 - exp(-dt * 3.0))
	else:
		_blick = _blick.lerp(Vector2.ZERO, 1.0 - exp(-dt * 2.0))
	bild(dt)


## Nur Bewegung rechnen (im Editor: ohne Raum).
func bild(dt: float) -> void:
	if _k.is_empty():
		return
	_t += dt
	var k := func(r: float) -> float: return 1.0 - exp(-dt * r)
	var soll := { "lauf": 0.0, "sitz": 0.0, "lieg": 0.0, "schlaf": 0.0, "freu": 0.0, "streich": 0.0 }
	match zustand:
		"folgen", "hin": soll.lauf = clampf(_tempo / 0.5, 0.0, 1.0)
		"sitzen", "gestreichelt": soll.sitz = 1.0
		"fernsehen": soll.lieg = 1.0
		"schlafen": soll.schlaf = 1.0
		"freuen": soll.sitz = 0.4
	if zustand in ["folgen", "hin"] and _tempo < 0.15:
		soll.sitz = 1.0 - soll.lauf
	if _freu_t >= 0.0:
		_freu_t += dt
		soll.freu = 1.0 - smoothstep(2.0, 2.6, _freu_t)
		if _freu_t > 2.6:
			_freu_t = -1.0
	if _streich_t >= 0.0:
		_streich_t += dt
		soll.streich = smoothstep(0.0, 0.4, _streich_t) * (1.0 - smoothstep(2.4, 3.0, _streich_t))
		if _streich_t > 3.0:
			_streich_t = -1.0
	for key in _w.keys():
		_w[key] = lerpf(float(_w[key]), float(soll[key]), k.call(2.4 if key in ["schlaf", "lieg"] else 6.0))
	var lauf := float(_w.lauf)
	var sitz := float(_w.sitz)
	var lieg := maxf(float(_w.lieg), float(_w.schlaf))
	var schlaf := float(_w.schlaf)
	var freu := float(_w.freu)
	var streich := float(_w.streich)
	if _tempo > 0.05:
		_phase = fmod(_phase + dt * (_tempo * 11.0 + 2.0), TAU)
	var atem := sin(_t * (1.4 if schlaf < 0.5 else 0.8))
	var kp: Node3D = _k.koerper
	var kopf: Node3D = _k.kopf
	var beine: Dictionary = _k.beine
	# Körper: Höhe, Neigung; Hase hoppelt, alle anderen traben.
	var hop := 0.0
	if art == "hase":
		hop = absf(sin(_phase * 0.5)) * 0.06 * lauf
	var trab := absf(sin(_phase)) * 0.012 * lauf
	var freu_hop := maxf(0.0, sin(_freu_t * TAU * 1.6)) * 0.12 * freu if _freu_t >= 0.0 else 0.0
	var h := 0.17 + hop + trab + freu_hop
	h = lerpf(h, 0.13, sitz * 0.6)
	h = lerpf(h, 0.085, lieg)
	kp.position = Vector3(0, h + atem * 0.002, 0)
	kp.rotation = Vector3(-0.5 * sitz * (1.0 - lieg) + 0.05 * sin(_phase * 0.5) * lauf * (1.0 if art == "hase" else 0.3), 0.0, 0.0)
	if _freu_t >= 0.0:
		kp.rotation.y = sin(_freu_t * 3.2) * 0.5 * freu
	kp.scale = Vector3(1.0 + atem * 0.012, 1.0 + atem * 0.015 - freu_hop * 0.4, 1.0)
	# Beine: diagonal im Trab; sitzend die Hinterbeine gefaltet; liegend unter dem Körper.
	var s := sin(_phase)
	for b in beine.keys():
		var n: Node3D = beine[b]
		var vorn := str(b).begins_with("v")
		var gegen := 1.0 if b in ["vl", "hr"] else -1.0
		var x := s * 0.6 * lauf * gegen
		if art == "hase":
			x = (sin(_phase * 0.5) * 0.7 * lauf) * (1.0 if vorn else -1.0)
		if not vorn:
			x = lerpf(x, -1.2, sitz * (1.0 - lieg))
		else:
			x = lerpf(x, 0.45, sitz * (1.0 - lieg))
		x = lerpf(x, -1.45 if vorn else 1.35, lieg)
		if vorn and lieg > 0.5 and schlaf < 0.5:
			x = lerpf(x, -1.5, lieg)
		n.rotation = Vector3(x, 0, 0)
	# Kopf: sieht dich (oder den Fernseher) an; schlafend auf den Pfoten; gestreichelt hebt er sich.
	var kx := -_blick.y * 0.8 + 0.42 * sitz * (1.0 - lieg)
	kx = lerpf(kx, 0.55, schlaf)
	kx -= 0.35 * streich
	var ky := _blick.x * 0.9 * (1.0 - schlaf)
	kopf.rotation = Vector3(kx + 0.03 * sin(_t * 0.7), ky, 0.22 * streich * sin(_t * 1.5) + 0.04 * sin(_t * 0.43))
	kopf.position = Vector3(0, lerpf(0.1, 0.03, schlaf), lerpf(0.14, 0.17, schlaf))
	# Ohren zucken ab und zu.
	_ohr_t -= dt
	var zuck := 0.0
	if _ohr_t < 0.0:
		zuck = exp(_ohr_t * 12.0) if _ohr_t > -0.5 else 0.0
		if _ohr_t < -2.0:
			_ohr_t = _rng.randf_range(2.0, 6.0)
	for o in ["ohr_l", "ohr_r"]:
		if _k.has(o):
			var on: Node3D = _k[o]
			var basis_z := on.get_meta("rz", on.rotation.z) as float
			if not on.has_meta("rz"):
				on.set_meta("rz", basis_z)
			on.rotation.z = basis_z + (0.25 * zuck if o == "ohr_l" else 0.0) * (1.0 - schlaf) - (0.2 * streich if art != "hase" else 0.0) * signf(basis_z + 0.0001)
	# Schwanz: pendelt ruhig, wedelt bei Freude und Streicheln, liegt beim Schlafen um den Körper.
	var wedel := (sin(_t * 14.0) * 0.6) * maxf(freu, streich)
	var ruhe := sin(_t * 1.1) * 0.25
	var kette: Array = _k.schwanz
	for i in kette.size():
		var sn: Node3D = kette[i]
		var heb := 0.0
		match art:
			"katze": heb = -1.9 if i == 0 else 0.35
			"hund": heb = -2.1 if i == 0 else 0.25
			"fuchs": heb = -1.25 if i == 0 else 0.3
			"hase": heb = 0.0
			"drache": heb = -1.0 if i == 0 else 0.2
		heb = lerpf(heb, -1.45 if i == 0 else 0.1, lieg * 0.7)
		var seit := (ruhe * (1.0 - schlaf) + wedel) * (0.6 if i == 0 else 1.0)
		seit = lerpf(seit, 0.9 if i > 0 else 0.6, schlaf)
		sn.rotation = Vector3(heb + sin(_phase + i) * 0.15 * lauf, 0, seit)
	if _k.has("fluegel"):
		var fl: Array = _k.fluegel
		for i in fl.size():
			var sg := 1.0 if i == 0 else -1.0
			(fl[i] as Node3D).rotation = Vector3(0, 0, sg * (0.25 * sin(_t * (2.0 + freu * 16.0)) * (0.3 + freu) - 0.2 * lieg))
	# Gesicht: blinzeln, lachen, schlafen.
	_blink_in -= dt
	if _blink_in <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_in = _rng.randf_range(2.5, 6.0)
	var bl := 0.0
	if _blink_t >= 0.0:
		_blink_t += dt
		bl = sin(clampf(_blink_t / 0.18, 0.0, 1.0) * PI)
		if _blink_t > 0.18:
			_blink_t = -1.0
	_gesicht.set_shader_parameter("blinzeln", bl)
	_gesicht.set_shader_parameter("freude", maxf(freu, streich))
	_gesicht.set_shader_parameter("schlaf", schlaf)
	_maul.set_shader_parameter("offen", freu * 0.6 * (0.6 + 0.4 * sin(_t * 9.0)))
	_zz(dt, schlaf)
	_herz_bild(dt)


func _zz(dt: float, schlaf: float) -> void:
	if schlaf < 0.6:
		_zett.modulate.a = 0.0
		_zett_t = 0.0
		return
	_zett_t = fmod(_zett_t + dt * 0.45, 1.0)
	var kopf_w := (_k.kopf as Node3D).global_position
	_zett.global_position = kopf_w + Vector3(0.05 + _zett_t * 0.06, 0.12 + _zett_t * 0.22, 0.0)
	# Größer über die Punktgröße, nicht über die Schriftgröße: Jede Schriftgröße legt in der Engine einen
	# eigenen Satz Zeichenbilder an – früher 40 Stück für dieses eine „z“, in jedem Bild eine andere.
	_zett.pixel_size = 0.0016 * (40.0 + _zett_t * 40.0) / 64.0
	_zett.modulate = Color(0.95, 0.93, 0.98, sin(_zett_t * PI) * 0.75 * schlaf)


func _herz_bild(dt: float) -> void:
	if _herz_t < 0.0:
		_herz.visible = false
		return
	_herz_t += dt
	var t := _herz_t / 1.6
	if t >= 1.0:
		_herz_t = -1.0
		_herz.visible = false
		return
	_herz.visible = true
	var kopf_w := (_k.kopf as Node3D).global_position
	_herz.global_position = kopf_w + Vector3(0, 0.17 + t * 0.22, 0)
	_herz.scale = Vector3.ONE * (0.6 + 0.4 * smoothstep(0.0, 0.2, t)) * groesse
	_herz.rotation = Vector3(0, sin(t * 4.0) * 0.4, 0)
	(_herz.material_override as StandardMaterial3D).albedo_color.a = 1.0 - smoothstep(0.55, 1.0, t)


## Mitte für Treffer (Streicheln) in der Welt.
func mitte() -> Vector3:
	return global_position + Vector3(0, 0.2 * groesse, 0)


## Sofort an einen Ort (beim Hereinkommen), mit Blickrichtung.
func setze(p: Vector3, yaw: float, z := "sitzen") -> void:
	position = Vector3(p.x, 0, p.z)
	_yaw = yaw
	rotation.y = yaw
	zustand = z
	for key in _w.keys():
		_w[key] = 0.0
	_w.sitz = 1.0 if z in ["sitzen", "folgen"] else 0.0
	_w.lieg = 1.0 if z == "fernsehen" else 0.0
	_w.schlaf = 1.0 if z == "schlafen" else 0.0
	_vel = Vector3.ZERO

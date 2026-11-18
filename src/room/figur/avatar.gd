extends Node3D
## Deine Figur (Punkt 131 c): ein Mensch aus „Characters PSX“ (figur_psx.gd, assets/figur/psx) mit
## Mixamo-Skelett und eigener Textur; dazu der Controller in der rechten Hand (an ihrem Knochen).
## Bewegungen werden hier gerechnet: Atmen, Gewicht verlagern, Umsehen, Gehen, Rennen, Springen,
## Ducken, Sitzen mit Controller in der Hand und die Emotes. Posen werden weich übergeblendet
## (Gewichte mit Nachlauf), Emotes haben eine Ein- und Ausblendung – nichts springt.
##
## Posen: je Gelenk (GELENKE) eine Drehung in einem Rahmen, der in Ruhe am Körper ausgerichtet ist
## (Arme hängend). _anwenden rechnet sie in Knochendrehungen um (die Arme kommen dabei aus der
## A-Haltung des Modells nach unten).
##
## Ursprung: zwischen den Füßen auf dem Boden, Blick nach +z. Steuerung von außen über tempo, sitz,
## spielt, luft, ducken, blick_auf und emote(); bild(dt) rechnet ein Bild.
##
## Ebenen: Oberkörper, Arme und Kopf auf EBENE_KOERPER, der Controller auf
## EBENE_HAENDE – so blendet die Ich-Ansicht den Körper aus (sein Schatten bleibt). Becken, Beine
## und Füße auf EBENE_BEINE: die bleiben in der Ich-Ansicht – wer nach unten schaut, sieht seine Füße.

const D := preload("res://src/room/figur/figur_daten.gd")
const FF := preload("res://src/room/figur/figur_formen.gd")
const FP := preload("res://src/room/figur/figur_psx.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")

const EBENE_KOERPER := 1 << 10
const EBENE_HAENDE := 1 << 11
const EBENE_BEINE := 1 << 12
## Gelenk der Posen → Knochen im Modell.
const KNOCHEN := { "huefte": "Hips", "bauch": "Spine", "brust": "Spine1", "hals": "Neck", "kopf": "Head",
	"ob_l": "LeftArm", "un_l": "LeftForeArm", "hand_l": "LeftHand", "ob_r": "RightArm", "un_r": "RightForeArm", "hand_r": "RightHand",
	"bein_l": "LeftUpLeg", "knie_l": "LeftLeg", "fuss_l": "LeftFoot", "bein_r": "RightUpLeg", "knie_r": "RightLeg", "fuss_r": "RightFoot" }
## Fingerglieder (je nach Modell sind nur einige da).
const FINGER := ["HandIndex1", "HandIndex2", "HandIndex3", "HandMiddle1", "HandMiddle2", "HandMiddle3", "HandRing1", "HandRing2", "HandRing3",
	"HandPinky1", "HandPinky2", "HandPinky3"]

const EMOTES := [["winken", "Winken"], ["jubeln", "Jubeln"], ["tanzen", "Tanzen"], ["daumen", "Daumen hoch"],
	["klatschen", "Klatschen"], ["sitzen", "Hinsetzen"], ["zucken", "Schulterzucken"]]
## Dauer in Sekunden (−1: bis du wieder losläufst).
const DAUER := { "winken": 2.4, "jubeln": 2.3, "tanzen": 4.8, "daumen": 1.9, "klatschen": 2.3, "sitzen": -1.0, "zucken": 1.7, "streicheln": 2.4 }
const GELENKE := ["huefte", "bauch", "brust", "hals", "kopf", "ob_l", "un_l", "hand_l", "ob_r", "un_r", "hand_r",
	"bein_l", "knie_l", "fuss_l", "bein_r", "knie_r", "fuss_r"]

var werte := {}
var g := {}                      ## Gelenk-Name → Knochen-Nummer im Skelett
var controller: Node3D
var skelett: Skeleton3D
var _md := {}                    ## die aufbereitete Figur (figur_psx.gd)
var _koerper: Node3D
var _huefte := 0.9               ## Höhe der Hüfte in Ruhe
var _arm_ab: Array = []          ## je Knochen: Drehung der Arme nach unten (oder null)
var _drehen: Array = []          ## Knochen, deren Drehung gesetzt wird
var _finger: Array = []          ## je Seite [Knochen-Nummern der Fingerglieder] in FINGER-Reihenfolge
var _daumen := -1
var _e: Array = []               ## je Knochen: Drehung der Pose (Basis)
var _v: Array = []               ## je Knochen: Rahmen der Pose (Basis, Zwischenwerte)
var _b: Array = []

## Steuerung
var tempo := 0.0                 ## Laufen in m/s
var sitz := false
var sitz_hoehe := 0.47
var spielt := false              ## Controller in der Hand (beim Sitzen)
var luft := false                ## in der Luft (Sprung)
var ducken := 0.0                ## 0 stehen … 1 geduckt
var blick_auf := Vector3.ZERO    ## dorthin schaut der Kopf (Welt), wenn blick_an
var blick_an := false
## Fotomodus: eine Pose halten (Emote-Kennung) zur Zeit foto_t, ohne Ablauf.
var foto_pose := ""
var foto_t := 0.0

var _t := 0.0
var _phase := 0.0
var _w_lauf := 0.0
var _w_renn := 0.0
var _w_luft := 0.0
var _w_duck := 0.0
var _w_sitz := 0.0
var _w_spiel := 0.0
var _emote := ""
var _emote_t := 0.0
var _emote_w := 0.0
var _emote_alt := {}             ## Pose beim Ende eines Emotes (weiches Auslaufen)
var _kopf_blick := Vector2.ZERO
var _ebene := 0                  ## beim Bauen: feste Ebene für die nächsten Teile (0: nach hand)


# --- Bauen ---------------------------------------------------------------------------------------

func bauen(w: Dictionary) -> void:
	werte = D.pruefe_figur(w)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	g.clear()
	controller = null
	_md = FP.daten(str(werte.person))
	if _md.is_empty():
		# Ohne die Modelle (FP.vorhanden): leerer Knoten. bild() und kopf_mitte() kennen den Fall (g bleibt leer).
		skelett = null
		return
	var md := _md
	_huefte = float(md.huefte)
	_koerper = Node3D.new()
	_koerper.name = "koerper"
	add_child(_koerper)
	skelett = FP.skelett(md)
	_koerper.add_child(skelett)
	var namen: Array = md.namen
	for j: String in KNOCHEN.keys():
		g[j] = namen.find(KNOCHEN[j])
	# Je Knochen: Drehung der Arme nach unten (vom Oberarm an vererbt).
	var n := namen.size()
	_arm_ab.resize(n)
	_e.resize(n)
	_v.resize(n)
	_b.resize(n)
	for i: int in md.reihe:
		var p: int = md.eltern[i]
		_arm_ab[i] = (md.arm_ab as Dictionary).get(i, _arm_ab[p] if p >= 0 else null)
		_e[i] = Basis()
	_drehen = g.values()
	_finger = []
	for s in ["Left", "Right"]:
		var liste: Array = []
		for f in FINGER:
			var fi: int = namen.find(s + f)
			liste.append(fi)
			if fi >= 0:
				_drehen.append(fi)
		_finger.append(liste)
	_daumen = namen.find("RightHandThumb1")
	# Der Körper: oben (Brust, Arme, Kopf) und unten (Becken, Beine, Füße) mit der Textur der Figur.
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = md.textur
	mat.roughness = 0.82
	mat.metallic_specular = 0.25
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var netze: Array = md.netze
	for k in netze.size():
		var mi := MeshInstance3D.new()
		mi.name = "koerper_oben" if k == 0 else "koerper_unten"
		mi.mesh = netze[k]
		mi.skin = md.haut
		mi.material_override = mat
		mi.layers = EBENE_KOERPER if k == 0 else EBENE_BEINE
		skelett.add_child(mi)
		mi.skeleton = NodePath("..")
	# Der Controller hängt an der rechten Hand.
	_controller()
	bild(0.0)


## Ein Rahmen an einem Knochen: ausgerichtet wie der Körper in Ruhe (für Teile mit eigener Form).
## mitte: Punkt im Modell, auf den der Punkt alt des Bau-Rahmens fällt; skal je Achse.
func _raum(knochen: String, mitte: Vector3, skal: Vector3, alt: Vector3) -> Node3D:
	var i: int = (_md.namen as Array).find(knochen)
	var ba := BoneAttachment3D.new()
	ba.bone_idx = i
	skelett.add_child(ba)
	var gr: Transform3D = _md.global[i]
	var r := gr.basis.inverse()
	if _arm_ab[i] != null:
		r = gr.basis.inverse() * (_arm_ab[i] as Basis).inverse()
	var raum := Node3D.new()
	var b := r * Basis.from_scale(skal)
	raum.transform = Transform3D(b, gr.affine_inverse() * mitte - b * alt)
	ba.add_child(raum)
	return raum


func _teil(eltern: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, skal := Vector3.ONE, hand := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = skal
	mi.layers = _ebene if _ebene != 0 else (EBENE_HAENDE if hand else EBENE_KOERPER)
	eltern.add_child(mi)
	return mi


## Eigener Fantasie-Controller (keine Marke): rundliche Form, zwei Griffe, Sticks, der goldene
## Spielerpunkt aus Uzais Startbild. Liegt in der rechten Hand.
func _controller() -> void:
	var hand := _raum("RightHand", (_md.global[g.hand_r] as Transform3D).origin, Vector3.ONE, Vector3.ZERO)
	controller = Node3D.new()
	controller.name = "controller"
	hand.add_child(controller)
	var koerper := S.lack(Color("#2c2d31"), 0.42, 0.5)
	_teil(controller, F.kiste(Vector3(0.15, 0.032, 0.066), 0.015), koerper, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true)
	for s: float in [1.0, -1.0]:
		_teil(controller, FF.ei(Vector3(0.032, 0.026, 0.048), 14), koerper, Vector3(s * 0.058, -0.008, -0.032), Vector3(0.3, 0, 0), Vector3.ONE, true)
		_teil(controller, F.walze(0.0095, 0.013, 0.004, 14), S.lack(Color("#47484d"), 0.6, 0.3), Vector3(s * 0.034, 0.012, 0.004), Vector3.ZERO, Vector3.ONE, true)
	for i in 4:
		var w := float(i) * PI * 0.5
		_teil(controller, FF.ei(Vector3.ONE * 0.0055, 8), S.lack(Color("#d8d3c9"), 0.4, 0.5), Vector3(0.055 + cos(w) * 0.011, 0.016, -0.014 + sin(w) * 0.011),
				Vector3.ZERO, Vector3.ONE, true)
	_teil(controller, FF.ei(Vector3(0.008, 0.004, 0.008), 10), S.leuchte(Color("#e7c27d"), 1.6), Vector3(0, 0.017, 0.006), Vector3.ZERO, Vector3.ONE, true)
	controller.position = Vector3(0.06, -0.09, 0.03)
	controller.rotation = Vector3(-1.2, 0.0, 0.0)
	controller.visible = false


# --- Bewegung ------------------------------------------------------------------------------------

## Ein Emote abspielen ("" beendet das laufende weich).
func emote(id: String) -> void:
	if id != "" and not DAUER.has(id):
		return
	if _emote != "" and id != _emote:
		_emote_alt = _emote_pose(_emote, _emote_t)
	_emote = id
	_emote_t = 0.0


## Fotomodus: Pose halten (id aus EMOTES, "" = einfach stehen) bzw. weich lösen (foto_ende).
func foto_halten(id: String, t: float) -> void:
	if id == "":
		foto_ende()
		return
	if foto_pose != id:
		_emote_w = 0.0
	foto_pose = id
	foto_t = t
	_emote = ""


func foto_ende() -> void:
	if foto_pose != "":
		_emote_alt = _emote_pose(foto_pose, foto_t)
		foto_pose = ""


func emote_laeuft() -> String:
	return _emote


func bild(dt: float) -> void:
	if g.is_empty():
		return
	_t += dt
	var k := func(rate: float) -> float: return 1.0 - exp(-dt * rate)
	_w_lauf = lerpf(_w_lauf, clampf(tempo / 0.7, 0.0, 1.0), k.call(10.0))
	_w_renn = lerpf(_w_renn, smoothstep(2.7, 3.8, tempo), k.call(8.0))
	_w_luft = lerpf(_w_luft, 1.0 if luft else 0.0, k.call(14.0 if luft else 20.0))
	_w_duck = lerpf(_w_duck, clampf(ducken, 0.0, 1.0), k.call(16.0))
	_w_sitz = lerpf(_w_sitz, 1.0 if sitz else 0.0, k.call(5.0))
	_w_spiel = lerpf(_w_spiel, 1.0 if (sitz and spielt) else 0.0, k.call(4.0))
	# Schrittlänge wächst mit dem Tempo (Rennen: lange Schritte statt Trippeln).
	if tempo > 0.05:
		_phase = fmod(_phase + dt * tempo * TAU / schritt_laenge(tempo), TAU)
	elif _w_lauf < 0.02:
		_phase = 0.0
	# Laufen beendet Emotes (außer kurz anlaufen beim Tanzen).
	if _emote != "" and tempo > 0.35:
		emote("")
	var p := _idle()
	if _w_lauf > 0.001:
		p = _mix(p, _lauf(clampf(tempo / 2.0, 0.35, 1.0) + 0.25 * _w_renn), _w_lauf)
	if _w_duck > 0.001:
		p = _mix(p, _ducken(p), _w_duck)
	if _w_luft > 0.001:
		p = _mix(p, _springen(), _w_luft)
	if _w_sitz > 0.001:
		p = _mix(p, _sitzen(), _w_sitz)
	if foto_pose != "" and DAUER.has(foto_pose):
		# Fotomodus: die Pose steht still (der Atem läuft weiter).
		var fp := _emote_pose(foto_pose, foto_t)
		_emote_w = lerpf(_emote_w, 1.0, k.call(8.0))
		p = _mix(p, fp, _emote_w)
	elif _emote != "":
		_emote_t += dt
		var d := float(DAUER.get(_emote, 2.0))
		var w := smoothstep(0.0, 0.32, _emote_t)
		if d > 0.0:
			w *= 1.0 - smoothstep(d - 0.42, d, _emote_t)
		var e := _emote_pose(_emote, _emote_t)
		_emote_w = w
		p = _mix(p, e, w)
		if d > 0.0 and _emote_t >= d:
			_emote = ""
			_emote_alt = {}
	elif not _emote_alt.is_empty():
		_emote_w = lerpf(_emote_w, 0.0, k.call(6.0))
		p = _mix(p, _emote_alt, _emote_w)
		if _emote_w < 0.01:
			_emote_alt = {}
	# Hände: locker leicht gekrümmt, mit dem Controller gegriffen, beim Daumen hoch eine Faust.
	p.faust = maxf(maxf(0.18, _w_spiel * 0.75), float(p.get("daumen", 0.0)))
	_kopf_umsehen(p, dt)
	_anwenden(p)
	controller.visible = _w_spiel > 0.5


## Länge eines Doppelschritts (m) beim Tempo t: gehend etwa zwei Schritte je Sekunde, rennend
## länger statt schneller (auch das Kopfwippen im Zimmer folgt dem).
static func schritt_laenge(t: float) -> float:
	return clampf(1.4 + 0.45 * (t - 1.4), 1.4, 2.6)


## Pose aufs Skelett: je Gelenk eine Drehung im Körperrahmen (V = V_eltern · E), der Knochen
## bekommt V · Arme-nach-unten · Ruhelage, gesetzt als Drehung gegenüber seinem Elternknochen.
func _anwenden(p: Dictionary) -> void:
	for j in GELENKE:
		_e[g[j]] = Basis.from_euler(p.get(j, Vector3.ZERO))
	var f := float(p.get("faust", 0.0))
	for seite in 2:
		var vz := -1.0 if seite == 0 else 1.0
		for i in FINGER.size():
			var fi: int = _finger[seite][i]
			if fi >= 0:
				_e[fi] = Basis(Vector3(0, 0, 1), vz * f * (0.55 if i % 3 == 0 else 0.75))
	var eltern: Array = _md.eltern
	var glob: Array = _md.global
	for i: int in _md.reihe:
		var par: int = eltern[i]
		var v: Basis = _e[i] if par < 0 else (_v[par] as Basis) * (_e[i] as Basis)
		_v[i] = v
		var a: Variant = _arm_ab[i]
		_b[i] = (v * (a as Basis) if a != null else v) * (glob[i] as Transform3D).basis
	for i: int in _drehen:
		var par: int = eltern[i]
		var lokal: Basis = (_b[i] as Basis) if par < 0 else (_b[par] as Basis).inverse() * (_b[i] as Basis)
		skelett.set_bone_pose_rotation(i, lokal.get_rotation_quaternion())
	# Hüfte: Höhe und Schub nach vorn (Sitzen, Hocken, Springen).
	var h: int = g.huefte
	var hp: int = eltern[h]
	var ziel: Vector3 = (glob[h] as Transform3D).origin + Vector3(0, float(p.get("y", 0.0)), float(p.get("vor", 0.0)))
	skelett.set_bone_pose_position(h, ziel if hp < 0 else (glob[hp] as Transform3D).affine_inverse() * ziel)
	_koerper.rotation.y = float(p.get("dreh", 0.0))
	# Daumen: hoch beim Emote, sonst locker an der Hand.
	var dh := float(p.get("daumen", 0.0))
	var dn := _daumen
	if dn >= 0:
		var dr: Basis = (_b[dn] as Basis) * Basis(Vector3(0, 0, 1), -dh * 0.6)
		skelett.set_bone_pose_rotation(dn, ((_b[eltern[dn]] as Basis).inverse() * dr).get_rotation_quaternion())


static func _null() -> Dictionary:
	var p := {}
	for j in GELENKE:
		p[j] = Vector3.ZERO
	return p


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := a.duplicate()
	for key in b.keys():
		var va: Variant = a.get(key, Vector3.ZERO if b[key] is Vector3 else 0.0)
		if b[key] is Vector3:
			out[key] = (va as Vector3).lerp(b[key], w)
		elif b[key] is float:
			out[key] = lerpf(float(va), float(b[key]), w)
	return out


func _idle() -> Dictionary:
	var t := _t
	var b := sin(t * 1.8)
	var s := sin(t * 0.5)
	var p := _null()
	p.brust = Vector3(0.012 * b, 0, 0)
	p.ob_l = Vector3(0.02, 0, 0.09 + 0.012 * b)
	p.ob_r = Vector3(0.02, 0, -0.09 - 0.012 * b)
	p.un_l = Vector3(-0.17, 0.1, 0)
	p.un_r = Vector3(-0.17, -0.1, 0)
	p.hand_l = Vector3(0, 0.2, -0.04)
	p.hand_r = Vector3(0, -0.2, 0.04)
	p.huefte = Vector3(0, 0.04 * s, 0.022 * s)
	p.bauch = Vector3(0.01, -0.02 * s, -0.016 * s)
	p.bein_l = Vector3(0, 0, 0.02 - 0.022 * s)
	p.bein_r = Vector3(0, 0, -0.02 - 0.022 * s)
	p.kopf = Vector3(0.02 * sin(t * 0.37), 0.07 * sin(t * 0.23), 0.02 * sin(t * 0.31))
	p.y = 0.003 * b
	return p


func _lauf(amp: float) -> Dictionary:
	var f := _phase
	var sf := sin(f)
	var cf := cos(f)
	var r := _w_renn
	var p := _null()
	p.bein_l = Vector3(-0.5 * amp * sf - 0.1 * r, 0, 0.02)
	p.bein_r = Vector3(0.5 * amp * sf - 0.1 * r, 0, -0.02)
	p.knie_l = Vector3(0.08 + (0.95 + 0.5 * r) * amp * maxf(0.0, cf), 0, 0)
	p.knie_r = Vector3(0.08 + (0.95 + 0.5 * r) * amp * maxf(0.0, -cf), 0, 0)
	p.fuss_l = Vector3(-(p.bein_l.x + p.knie_l.x) * 0.55 - 0.08 * amp, 0, 0)
	p.fuss_r = Vector3(-(p.bein_r.x + p.knie_r.x) * 0.55 - 0.08 * amp, 0, 0)
	p.ob_l = Vector3(0.42 * amp * sf, 0, 0.1)
	p.ob_r = Vector3(-0.42 * amp * sf, 0, -0.1)
	p.un_l = Vector3(-0.25 - (0.4 + 0.8 * r) * amp * maxf(0.0, -sf) - 0.5 * r, 0.1, 0)
	p.un_r = Vector3(-0.25 - (0.4 + 0.8 * r) * amp * maxf(0.0, sf) - 0.5 * r, -0.1, 0)
	p.hand_l = Vector3(0, 0.2, -0.04)
	p.hand_r = Vector3(0, -0.2, 0.04)
	p.huefte = Vector3(0.06 * r, 0.11 * amp * sf, 0.025 * amp * cf)
	p.brust = Vector3(0.05 * r, -0.15 * amp * sf, -0.02 * amp * cf)
	p.bauch = Vector3(0.07 * amp + 0.1 * r, 0, 0)
	p.kopf = Vector3(-0.05 * amp - 0.12 * r, 0.05 * amp * sf, 0)
	p.y = -0.014 * amp + 0.024 * amp * cos(2.0 * f) - 0.03 * r
	return p


## In der Luft: Knie angezogen, Arme etwas nach oben und außen.
func _springen() -> Dictionary:
	var p := _null()
	p.bein_l = Vector3(-0.55, 0, 0.04)
	p.bein_r = Vector3(-0.35, 0, -0.04)
	p.knie_l = Vector3(0.95, 0, 0)
	p.knie_r = Vector3(0.75, 0, 0)
	p.fuss_l = Vector3(0.2, 0, 0)
	p.fuss_r = Vector3(0.25, 0, 0)
	p.ob_l = Vector3(-0.35, 0, 0.45)
	p.ob_r = Vector3(-0.35, 0, -0.45)
	p.un_l = Vector3(-0.5, 0.1, 0)
	p.un_r = Vector3(-0.5, -0.1, 0)
	p.bauch = Vector3(0.08, 0, 0)
	p.kopf = Vector3(-0.06, 0, 0)
	p.y = 0.08
	return p


## Geduckt: in die Hocke, Oberkörper vor. Gehen geht weiter (die Beine aus p schwingen kleiner mit).
func _ducken(p: Dictionary) -> Dictionary:
	var q := p.duplicate()
	var bl: Vector3 = p.bein_l
	var br: Vector3 = p.bein_r
	q.bein_l = Vector3(-1.05 + bl.x * 0.5, 0, 0.1)
	q.bein_r = Vector3(-1.05 + br.x * 0.5, 0, -0.1)
	q.knie_l = Vector3(1.65 + (p.knie_l as Vector3).x * 0.3, 0, 0)
	q.knie_r = Vector3(1.65 + (p.knie_r as Vector3).x * 0.3, 0, 0)
	q.fuss_l = Vector3(-0.6, 0, 0)
	q.fuss_r = Vector3(-0.6, 0, 0)
	q.bauch = Vector3(0.38, 0, 0)
	q.brust = Vector3(0.12, 0, 0)
	q.kopf = Vector3(-0.35, 0, 0)
	q.ob_l = Vector3(-0.45, 0, 0.12)
	q.ob_r = Vector3(-0.45, 0, -0.12)
	q.un_l = Vector3(-0.7, 0.1, 0)
	q.un_r = Vector3(-0.7, -0.1, 0)
	q.y = -0.3
	q.vor = -0.04
	return q


func _sitzen() -> Dictionary:
	var p := _null()
	var t := _t
	p.y = sitz_hoehe + 0.06 - _huefte
	p.bein_l = Vector3(-1.42, 0.06, 0.05)
	p.bein_r = Vector3(-1.42, -0.06, -0.05)
	p.knie_l = Vector3(1.28, 0, 0)
	p.knie_r = Vector3(1.28, 0, 0)
	p.fuss_l = Vector3(0.1, 0, 0)
	p.fuss_r = Vector3(0.1, 0, 0)
	p.bauch = Vector3(-0.08, 0, 0)
	p.brust = Vector3(0.06 + 0.012 * sin(t * 1.6), 0, 0)
	p.kopf = Vector3(0.03, 0, 0)
	# Hände auf den Oberschenkeln – oder den Controller halten, die Daumen arbeiten ein wenig.
	var ruhig := _null()
	ruhig.ob_l = Vector3(-0.28, 0, 0.1)
	ruhig.ob_r = Vector3(-0.28, 0, -0.1)
	ruhig.un_l = Vector3(-0.6, -0.15, 0)
	ruhig.un_r = Vector3(-0.6, 0.15, 0)
	var spiel := _null()
	var z := 0.03 * sin(t * 7.3) + 0.02 * sin(t * 11.1)
	spiel.ob_l = Vector3(-0.42, 0, 0.16)
	spiel.ob_r = Vector3(-0.42, 0, -0.16)
	spiel.un_l = Vector3(-1.22, -0.72, 0)
	spiel.un_r = Vector3(-1.22, 0.72, 0)
	spiel.hand_l = Vector3(-0.1 + z, 0.2, 0.35)
	spiel.hand_r = Vector3(-0.1 - z, -0.2, -0.35)
	for j in ["ob_l", "ob_r", "un_l", "un_r", "hand_l", "hand_r"]:
		p[j] = (ruhig[j] as Vector3).lerp(spiel[j], _w_spiel)
	return p


## Posen der Emotes zur Zeit t (eigene Bewegungen, gerechnet).
func _emote_pose(id: String, t: float) -> Dictionary:
	var p := _idle()
	match id:
		"winken":
			var w := sin(t * 9.0)
			p.ob_r = Vector3(-0.2, 0.0, -2.5)
			p.un_r = Vector3(-0.25, 0.0, 0.42 * w)
			p.hand_r = Vector3(0.0, -0.4, 0.15 * w)
			p.ob_l = Vector3(0.02, 0, 0.12)
			p.brust = Vector3(0, 0.08, 0.06)
			p.kopf = Vector3(0.0, -0.12, 0.13)
		"jubeln":
			var j := maxf(0.0, sin((t - 0.25) * TAU * 1.15)) if t > 0.25 and t < 2.0 else 0.0
			var hock := (1.0 - j) * smoothstep(0.0, 0.25, t) * (0.6 + 0.4 * cos(t * TAU * 1.15))
			p.y = 0.11 * j - 0.05 * hock
			p.bein_l = Vector3(-0.3 * hock, 0, 0.05)
			p.bein_r = Vector3(-0.3 * hock, 0, -0.05)
			p.knie_l = Vector3(0.6 * hock, 0, 0)
			p.knie_r = Vector3(0.6 * hock, 0, 0)
			p.fuss_l = Vector3(-0.3 * hock + 0.25 * j, 0, 0)
			p.fuss_r = Vector3(-0.3 * hock + 0.25 * j, 0, 0)
			var arm := 2.6 + 0.12 * sin(t * 12.0)
			p.ob_l = Vector3(-0.2, 0, arm)
			p.ob_r = Vector3(-0.2, 0, -arm)
			p.un_l = Vector3(-0.3, 0, 0.1)
			p.un_r = Vector3(-0.3, 0, -0.1)
			p.kopf = Vector3(-0.18, 0, 0)
			p.brust = Vector3(-0.08, 0, 0)
		"tanzen":
			var b := t * TAU * 1.6
			var sb := sin(b)
			p.huefte = Vector3(0, 0.15 * sin(b * 0.5), 0.12 * sb)
			p.bauch = Vector3(0.04, 0, -0.08 * sb)
			p.brust = Vector3(0, -0.1 * sin(b * 0.5), -0.06 * sb)
			p.y = -0.04 + 0.03 * absf(sb)
			p.bein_l = Vector3(-0.2 - 0.2 * maxf(0.0, sb), 0, 0.06 - 0.12 * sb)
			p.bein_r = Vector3(-0.2 - 0.2 * maxf(0.0, -sb), 0, -0.06 - 0.12 * sb)
			p.knie_l = Vector3(0.3 + 0.35 * maxf(0.0, sb), 0, 0)
			p.knie_r = Vector3(0.3 + 0.35 * maxf(0.0, -sb), 0, 0)
			p.fuss_l = Vector3(-0.15, 0, 0)
			p.fuss_r = Vector3(-0.15, 0, 0)
			p.ob_l = Vector3(-0.7 + 0.45 * sb, 0, 0.55)
			p.ob_r = Vector3(-0.7 - 0.45 * sb, 0, -0.55)
			p.un_l = Vector3(-1.45, -0.2, 0)
			p.un_r = Vector3(-1.45, 0.2, 0)
			p.kopf = Vector3(0.07 * sin(b * 2.0), 0.1 * sin(b * 0.5), 0.12 * sin(b + 0.6))
			p.dreh = 0.4 * sin(b * 0.25)
		"daumen":
			var hoch := smoothstep(0.1, 0.55, t)
			p.ob_r = Vector3(-0.95 * hoch, 0, -0.3 * hoch - 0.09)
			p.un_r = Vector3(-1.35 * hoch - 0.17, 0.3 * hoch, 0)
			p.hand_r = Vector3(0, -0.2 - 1.2 * hoch, 0.04)
			p.daumen = hoch
			p.kopf = Vector3(-0.04, -0.1, 0.12 * hoch)
		"klatschen":
			var c := 0.5 + 0.5 * sin(t * TAU * 2.8)
			p.ob_l = Vector3(-0.78, 0, -0.18 - 0.2 * c)
			p.ob_r = Vector3(-0.78, 0, 0.18 + 0.2 * c)
			p.un_l = Vector3(-1.05, -0.35, 0)
			p.un_r = Vector3(-1.05, 0.35, 0)
			p.hand_l = Vector3(0, 0, 0.9)
			p.hand_r = Vector3(0, 0, -0.9)
			p.kopf = Vector3(-0.05, 0, 0.05 * sin(t * 6.0))
		"sitzen":
			var a := sin(t * 1.4)
			p.y = 0.22 - _huefte
			p.bein_l = Vector3(-1.3, 0.5, 0.82)
			p.bein_r = Vector3(-1.3, -0.5, -0.82)
			p.knie_l = Vector3(2.35, 0, 0)
			p.knie_r = Vector3(2.35, 0, 0)
			p.fuss_l = Vector3(-0.2, 0, -0.5)
			p.fuss_r = Vector3(-0.2, 0, 0.5)
			p.bauch = Vector3(0.1, 0, 0)
			p.brust = Vector3(0.06 + 0.012 * a, 0, 0)
			p.ob_l = Vector3(-0.42, 0, 0.32)
			p.ob_r = Vector3(-0.42, 0, -0.32)
			p.un_l = Vector3(-0.55, -0.3, 0)
			p.un_r = Vector3(-0.55, 0.3, 0)
			p.kopf = Vector3(0.02, 0.15 * sin(t * 0.3), 0.05 * sin(t * 0.4))
		"zucken":
			var z := smoothstep(0.15, 0.5, t) * (1.0 - smoothstep(1.0, 1.45, t))
			p.ob_l = Vector3(-0.15, 0, 0.32 * z + 0.09)
			p.ob_r = Vector3(-0.15, 0, -0.32 * z - 0.09)
			p.un_l = Vector3(-1.45 * z - 0.17, -0.9 * z, 0)
			p.un_r = Vector3(-1.45 * z - 0.17, 0.9 * z, 0)
			p.hand_l = Vector3(0, 0, -0.9 * z)
			p.hand_r = Vector3(0, 0, 0.9 * z)
			p.brust = Vector3(-0.04 * z, 0, 0)
			p.hals = Vector3(0.08 * z, 0, 0)
			p.kopf = Vector3(-0.05 * z, 0, 0.2 * z)
			p.y = 0.012 * z
		"streicheln":
			var h := smoothstep(0.0, 0.5, t)
			var tap := sin(t * 7.0) * smoothstep(0.5, 0.8, t)
			p.y = -0.34 * h
			p.bein_l = Vector3(-1.15 * h, 0, 0.12)
			p.bein_r = Vector3(-0.7 * h, 0, -0.08)
			p.knie_l = Vector3(1.95 * h, 0, 0)
			p.knie_r = Vector3(1.7 * h, 0, 0)
			p.fuss_l = Vector3(-0.75 * h, 0, 0)
			p.fuss_r = Vector3(-0.95 * h, 0, 0)
			p.bauch = Vector3(0.38 * h, 0, 0)
			p.brust = Vector3(0.22 * h, 0, 0)
			p.ob_r = Vector3((-1.15 + 0.12 * tap) * h, 0, -0.18)
			p.un_r = Vector3(-0.35 * h, 0, 0)
			p.hand_r = Vector3(-0.4 * h, 0, 0)
			p.ob_l = Vector3(-0.5 * h, 0, 0.2)
			p.un_l = Vector3(-1.0 * h, 0, 0)
			p.kopf = Vector3(0.38 * h, 0, 0.06)
			p.vor = 0.04 * h
	return p


func _kopf_umsehen(p: Dictionary, dt: float) -> void:
	var soll := Vector2.ZERO
	if blick_an and is_inside_tree():
		var l := to_local(blick_auf) - Vector3(0, 1.5, 0)
		var yaw := atan2(l.x, l.z)
		var pitch := -atan2(l.y, Vector2(l.x, l.z).length())
		soll = Vector2(clampf(yaw, -0.9, 0.9), clampf(pitch, -0.45, 0.4))
		if absf(yaw) > 1.9:
			soll = Vector2.ZERO
	soll *= 1.0 - _emote_w * 0.8
	_kopf_blick = _kopf_blick.lerp(soll, 1.0 - exp(-dt * 4.0))
	var k: Vector3 = p.kopf
	p.kopf = k + Vector3(_kopf_blick.y * 0.7, _kopf_blick.x * 0.7, 0)
	var h: Vector3 = p.hals
	p.hals = h + Vector3(_kopf_blick.y * 0.3, _kopf_blick.x * 0.3, 0)


## Lage des Kopfes in der Welt (für die Kamera).
func kopf_mitte() -> Vector3:
	if g.is_empty() or skelett == null:
		return global_position + Vector3(0, 1.57, 0)
	var k: int = g.kopf
	var ruhe: Transform3D = _md.global[k]
	return skelett.global_transform * (skelett.get_bone_global_pose(k) * (ruhe.affine_inverse() * (_md.kopf_mitte as Vector3)))


## Sichtbar für Kameras mit dieser Ebenen-Maske (alle Teile).
func ebenen_alle(n: Node = null) -> Array:
	var out: Array = []
	var stapel: Array = [self if n == null else n]
	while not stapel.is_empty():
		var k: Node = stapel.pop_back()
		for c in k.get_children():
			if c is MeshInstance3D:
				out.append(c)
			stapel.append(c)
	return out

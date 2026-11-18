extends RefCounted
## Weitere Möbel für „Dein Zimmer“ (moebel.gd ruft hierher): Ohrensessel, Schlafsofa, Bett, Pouf,
## runder Couchtisch, Satztische, Gaming-Schreibtisch, Sideboard, Wand- und Leiterregal,
## Arcade-Automat (eigene Fantasie-Gestaltung: Planeten-Hüpfer mit Uzais goldenem Spielerpunkt, keine
## fremden Spiele oder Marken, R4), Bogen- und Papierlampe, Deckenfluter, Lichtervorhang und
## Lichtergirlande, Bogenhanf, Hängepflanze, Kräuter, Läufer, Fell, Bilderwand, Strahlenuhr, Vorhang.
##
## Alles aus eigenen Formen (formen.gd) und den Materialien des Zimmers (stoffe.gd), mit den Bausteinen
## und Anpassungen von moebel.gd (_m, _g, _beine, _griff …) und denselben Metas (sitz, blick, lampen,
## schatten, wiegen, uhr). Leistung: viele gleiche Teile (Lamellen, Strahlen, Knöpfe, Fransen) fasst
## moebel.gd buendeln zu einem Netz zusammen, Blätter und Lämpchen sind ein MultiMesh – ein
## Zeichenaufruf je Material; keine eigenen Shader, Bildschirm und Leuchtschild sind kleine Bilder.

const M := preload("res://src/room/moebel.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")

const WARM := Color(1.0, 0.76, 0.52)
const GOLD := Color("#e7c27d")
const DUNKEL := Color("#232427")
## Arcade: [Korpus, Kantenband, Grund der Seitenbilder, Akzent].
const ARCADE := {
	"nacht": [Color("#1f2a44"), Color("#f2b544"), Color("#27335a"), Color("#ff8a5c")],
	"kirsch": [Color("#6e1f2b"), Color("#f3e2c4"), Color("#7d2836"), Color("#ffc65c")],
	"mint": [Color("#2f6b5f"), Color("#f2d16b"), Color("#357a6c"), Color("#ff7aa8")],
	"holz": [Color("#5a3b26"), Color("#c9a173"), Color("#4e3221"), Color("#7fd6c8")],
}
## Gaming-Schreibtisch: [Platte, Gestell, Leuchtstreifen].
const GAMING := { "schwarz": [Color("#1c1d20"), Color("#121214"), Color("#6fd2ff")],
	"weiss": [Color("#e9e7e1"), Color("#d4d1ca"), Color("#ffb36b")], "nacht": [Color("#263048"), Color("#14161c"), Color("#c77dff")] }
const METALL := { "messing": Color("#b8925a"), "schwarz": Color("#232326"), "chrom": Color("#c9cacc") }
const TOEPFE := { "weiss": Color("#ece6dc"), "terrakotta": Color("#c97b54"), "schwarz": Color("#2b2b2e"), "creme": Color("#e6dccb"),
	"salbei": Color("#87977a") }
const FELLE := { "weiss": Color("#efe9dd"), "grau": Color("#a9a49c"), "braun": Color("#6b5442") }

static var _bilder := {}


## Baut das Möbel id in root (w, d: Grundfläche in Metern samt Stufe; st: Stufe). false: kein Möbel von hier.
static func bauen(root: Node3D, id: String, v: String, w: float, d: float, st: int) -> bool:
	match id:
		"ohrensessel": _ohrensessel(root, v)
		"schlafsofa": _schlafsofa(root, v)
		"bett": _bett(root, v, w, d)
		"pouf": _pouf(root, v)
		"couchtisch_rund": _couchtisch_rund(root, v, w)
		"satztisch": _satztisch(root, v)
		"gamingtisch": _gamingtisch(root, v, w - 0.1)
		"sideboard": _sideboard(root, v, w - 0.04)
		"wandregal": _wandregal(root, v, w - 0.06)
		"leiterregal": _leiterregal(root, v)
		"arcade": _arcade(root, v)
		"bogenlampe": _bogenlampe(root, v)
		"deckenfluter": _deckenfluter(root, v)
		"papierlampe": _papierlampe(root, v)
		"lichtervorhang": _lichtervorhang(root, v, w)
		"girlande": _girlande(root, v, w)
		"bogenhanf": _bogenhanf(root, v, st)
		"haengepflanze": _haengepflanze(root, v)
		"kraeuter": _kraeuter(root, v)
		"laeufer": _laeufer(root, v, w, d)
		"fell": _fell(root, v)
		"bilderwand": _bilderwand(root, v)
		"wanduhr_strahlen": _strahlenuhr(root, v)
		"vorhang": _vorhang(root, v, w)
		_:
			return false
	# Auch in gedrehten Knoten (Bedienfeld, Lehne, Kopfhörer) je Material ein Netz.
	for c in root.get_children():
		if c is Node3D and not (c is GeometryInstance3D):
			M.buendeln(c)
	M.buendeln(root)
	return true


# --- Kleine Helfer ---------------------------------------------------------------------------------

## Ein Teil, das in einem gedrehten Knoten sitzt (geneigte Lehne, schräges Bedienfeld).
static func _knoten(root: Node3D, pos: Vector3, rot_grad: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_grad
	root.add_child(n)
	return n


## Kugel (Drehkörper, im Zwischenspeicher von formen.gd).
static func _kugel(r: float, seg := 18) -> ArrayMesh:
	var u := PackedVector2Array()
	for i in 9:
		var a := -PI * 0.5 + PI * float(i) / 8.0
		u.append(Vector2(0.0 if i in [0, 8] else cos(a) * r, sin(a) * r + r))
	return F.dreh(u, seg)


## Stab von a nach b (Kiste mit quadratischem Querschnitt, dicke in Metern).
static func _stab(root: Node3D, a: Vector3, b: Vector3, dicke: float, mat: Material, rad := 0.002) -> MeshInstance3D:
	var mi := M._kiste(root, Vector3(dicke, a.distance_to(b), dicke), mat, (a + b) * 0.5, rad, false)
	var r := (b - a).normalized()
	var neben := Vector3.FORWARD if absf(r.y) < 0.99 else Vector3.RIGHT
	var x := neben.cross(r).normalized()
	mi.basis = Basis(x, r, x.cross(r).normalized())
	return mi


## Lämpchen als MultiMesh (ein Zeichenaufruf): Orte, Netz, Material.
static func _viele(root: Node3D, orte: Array, mesh: Mesh, mat: Material, drehungen: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = orte.size()
	for i in orte.size():
		var b: Basis = drehungen[i] if i < drehungen.size() else Basis()
		mm.set_instance_transform(i, Transform3D(b, orte[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


static func _sitz(root: Node3D, augen: float, z := 0.05) -> void:
	root.set_meta("sitz", { "pos": Vector3(0, augen, z), "ziel": Vector3(0, augen - 0.1, 4.0) })


## Ein Bild aus einer Zeichenvorschrift (Pixel für Pixel, einmal je Sitzung).
static func _bild(name: String, w: int, h: int, farbe: Callable, mipmaps := true) -> ImageTexture:
	if _bilder.has(name):
		return _bilder[name]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, farbe.call(float(x) / w, float(y) / h, x, y))
	if mipmaps:
		img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_bilder[name] = tex
	return tex


# --- Sitzen und Liegen -----------------------------------------------------------------------------

## Ohrensessel: tiefer Sitz, hohe, leicht geneigte Lehne, gepolsterte Armlehnen und die „Ohren“ oben
## seitlich, ein wenig nach außen gestellt; schlanke Holzbeine.
static func _ohrensessel(root: Node3D, v: String) -> void:
	var st := M._m(S.stoff(v, 110.0, 0.1))
	var stellen: Array = []
	for x: float in [-0.33, 0.33]:
		for z: float in [-0.3, 0.3]:
			stellen.append(Vector2(x, z))
	M._beine(root, stellen, 0.16, S.holz("walnuss", 1), 0.019)
	M._steht(root, Vector3(0.82, 0.2, 0.8), st, 0, 0.16, 0, 0.05)
	M._kiste(root, Vector3(0.58, 0.12, 0.6), st, Vector3(0, 0.42, 0.07), 0.05)
	for s: int in [-1, 1]:
		M._kiste(root, Vector3(0.12, 0.26, 0.78), st, Vector3(s * 0.35, 0.49, 0.0), 0.05)
		M._kiste(root, Vector3(0.12, 0.44, 0.3), st, Vector3(s * 0.36, 0.86, -0.25), 0.05, true, Vector3(-8, s * -10, s * -4))
	var lehne := _knoten(root, Vector3(0, 0.36, -0.34), Vector3(-9, 0, 0))
	M._kiste(lehne, Vector3(0.6, 0.78, 0.12), st, Vector3(0, 0.39, 0), 0.06)
	M._kiste(lehne, Vector3(0.5, 0.42, 0.1), st, Vector3(0, 0.36, 0.1), 0.05)
	M._schatten(root, Vector2(0.84, 0.82), 0.55)
	_sitz(root, 1.08, 0.08)
	M._blick(root, Vector3(0, 1.35, 1.6), Vector3(0, 0.55, 0))


## Schlafsofa (Tagesbett): Holzrahmen mit Rücken und Seitenteilen, eine Matratze, drei Rückenkissen
## (an die Rückwand gelehnt, ohne sie zu schneiden) und eine gefaltete Decke vorn auf der Matratze.
static func _schlafsofa(root: Node3D, v: String) -> void:
	var st := M._m(S.stoff(v, 90.0, 0.1))
	var holz := M._g(S.holz("eiche", 0))
	M._beine(root, [Vector2(-0.92, -0.4), Vector2(0.92, -0.4), Vector2(-0.92, 0.4), Vector2(0.92, 0.4)], 0.1, S.holz("eiche", 1), 0.02)
	M._steht(root, Vector3(1.96, 0.14, 0.92), holz, 0, 0.1, 0, 0.006)
	M._steht(root, Vector3(1.96, 0.52, 0.045), holz, 0, 0.1, -0.44, 0.006)
	for s: int in [-1, 1]:
		M._steht(root, Vector3(0.045, 0.42, 0.92), holz, s * 0.958, 0.1, 0, 0.006)
	M._kiste(root, Vector3(1.86, 0.18, 0.86), st, Vector3(0, 0.33, 0.02), 0.06)
	var hell := S.stoff("creme" if v != "creme" else "salbei", 90.0, 0.1)
	for i in 3:
		M._kiste(root, Vector3(0.58, 0.42, 0.18), hell if i != 1 else st, Vector3((i - 1) * 0.6, 0.65, -0.27), 0.08, true, Vector3(-12, 0, 0))
	var decke := S.stoff("graphit" if v != "graphit" else "senf", 60.0, 0.5)
	M._kiste(root, Vector3(0.4, 0.05, 0.5), decke, Vector3(0.62, 0.445, 0.16), 0.02, true, Vector3(0, -4, 0))
	M._kiste(root, Vector3(0.38, 0.04, 0.46), decke, Vector3(0.63, 0.49, 0.15), 0.018, true, Vector3(0, 3, 0))
	M._schatten(root, Vector2(1.98, 0.94), 0.55)
	_sitz(root, 1.02, 0.12)
	M._blick(root, Vector3(0, 1.4, 2.2), Vector3(0, 0.45, 0))


## Bett: Holzrahmen auf kurzen Beinen, gepolstertes Kopfteil, Matratze, Bettdecke mit Umschlag und
## seitlich fallendem Stoff, ein oder zwei Kissen (je nach Breite).
static func _bett(root: Node3D, v: String, w: float, d: float) -> void:
	var holz := M._g(S.holz("eiche", 0))
	var bw := w - 0.04
	var hd := d * 0.5
	var stellen: Array = []
	for x: float in [-bw * 0.5 + 0.06, bw * 0.5 - 0.06]:
		for z: float in [-hd + 0.12, hd - 0.08]:
			stellen.append(Vector2(x, z))
	M._beine(root, stellen, 0.12, S.holz("eiche", 1), 0.024)
	M._steht(root, Vector3(bw, 0.22, d - 0.1), holz, 0, 0.12, 0.05, 0.006)
	var kopf := M._m(S.stoff(v, 70.0, 0.2))
	M._steht(root, Vector3(bw, 0.9, 0.09), kopf, 0, 0.1, -hd + 0.05, 0.035)
	M._steht(root, Vector3(bw + 0.02, 0.03, 0.11), holz, 0, 1.0, -hd + 0.05, 0.006)
	var laken := S.stoff_farbig(Color("#f1ece2"), 160.0)
	var mlang := d - 0.32
	var mz := -hd + 0.12 + mlang * 0.5
	M._kiste(root, Vector3(bw - 0.1, 0.2, mlang), laken, Vector3(0, 0.44, mz), 0.05)
	# Bettdecke: vom Fußende bis knapp vor die Kissen, mit Umschlag oben und Stoff an den Seiten.
	var st := M._m(S.stoff(v, 120.0, 0.25))
	var dl := mlang * 0.7
	var dz := -hd + 0.12 + mlang - dl * 0.5 + 0.03
	M._kiste(root, Vector3(bw - 0.04, 0.07, dl), st, Vector3(0, 0.575, dz), 0.03)
	for s: int in [-1, 1]:
		M._kiste(root, Vector3(0.03, 0.2, dl - 0.04), st, Vector3(s * (bw * 0.5 - 0.015), 0.48, dz), 0.012)
	M._kiste(root, Vector3(0.03, 0.2, bw - 0.06), st, Vector3(0, 0.48, dz + dl * 0.5 - 0.015), 0.012, true, Vector3(0, 90, 0))
	M._teil(root, F.walze(0.045, bw - 0.06, 0.02, 20), laken, Vector3(-(bw - 0.06) * 0.5, 0.6, dz - dl * 0.5 + 0.03), Vector3(0, 0, -90))
	var n := 1 if bw < 1.3 else 2
	var kb := minf(0.62, (bw - 0.22) / n - 0.04)
	for i in n:
		var x := 0.0 if n == 1 else (i - 0.5) * (kb + 0.06)
		M._kiste(root, Vector3(kb, 0.13, 0.4), laken, Vector3(x, 0.615, -hd + 0.34), 0.06, true, Vector3(-10, 0, 0))
	M._schatten(root, Vector2(bw, d - 0.1), 0.55, false, 0.18, Vector3(0, 0, 0.05))
	_sitz(root, 1.2, hd - 0.4)
	M._blick(root, Vector3(0, 1.9, hd + 1.2), Vector3(0, 0.45, 0))


## Strickpouf: runde Rippen rundum (ein Netz), oben eine gepolsterte Scheibe.
static func _pouf(root: Node3D, v: String) -> void:
	var st := M._m(S.stoff(v, 40.0, 0.4))
	M._teil(root, F.walze(0.185, 0.37, 0.05, 32), st, Vector3.ZERO)
	for i in 18:
		var a := float(i) / 18.0 * TAU
		var k := M._kiste(root, Vector3(0.072, 0.34, 0.05), st, Vector3(sin(a) * 0.196, 0.185, cos(a) * 0.196), 0.024)
		k.rotation.y = a
	M._teil(root, F.walze(0.2, 0.05, 0.024, 36), st, Vector3(0, 0.345, 0))
	M._schatten(root, Vector2(0.46, 0.46), 0.5, true)
	_sitz(root, 0.95, 0.0)


# --- Tische ---------------------------------------------------------------------------------------

## Runder Couchtisch: Platte mit weicher Kante, Ablage darunter, drei Beine (Beine wählbar).
static func _couchtisch_rund(root: Node3D, v: String, w: float) -> void:
	var r := 0.43 if w < 1.2 else 0.71
	var h := M._m(S.holz(v, 0))
	M._teil(root, F.walze(r, 0.04, 0.014, 56), h, Vector3(0, 0.38, 0))
	M._teil(root, F.walze(r * 0.74, 0.022, 0.008, 48), h, Vector3(0, 0.12, 0))
	var stellen: Array = []
	for i in 3:
		var a := float(i) / 3.0 * TAU + PI / 6.0
		stellen.append(Vector2(sin(a), cos(a)) * r * 0.78)
	M._beine(root, stellen, 0.38, S.holz(v, 1), 0.024)
	M._schatten(root, Vector2(r * 2.0, r * 2.0), 0.45, true)
	M._blick(root, Vector3(0, 1.3, 1.4), Vector3(0, 0.4, 0))


## Satztische: zwei runde Tabletts mit Rand auf feinem Metallgestell, der kleine halb unter dem großen.
static func _satztisch(root: Node3D, v: String) -> void:
	var h := M._m(S.holz(v, 0))
	var g := M._g(S.metall(Color("#1d1d1f"), 0.45))
	# Der kleine fährt durch die Lücke zwischen zwei Beinen des großen (nichts schneidet sich).
	for t: Array in [[0.22, 0.5, Vector2(-0.02, -0.02)], [0.15, 0.4, Vector2(0.067, 0.03)]]:
		var r: float = t[0]
		var hh: float = t[1]
		var m: Vector2 = t[2]
		var u := PackedVector2Array([Vector2(0, 0), Vector2(r, 0), Vector2(r, 0.03), Vector2(r - 0.008, 0.03), Vector2(r - 0.008, 0.012), Vector2(0, 0.012)])
		M._teil(root, F.dreh(u, 40, [1, 2, 3, 4]), h, Vector3(m.x, hh - 0.03, m.y))
		M._teil(root, F.ring(r * 0.9, 0.005, TAU, 32, 6), g, Vector3(m.x, hh - 0.04, m.y), Vector3(90, 0, 0))
		for i in 3:
			var a := float(i) / 3.0 * TAU + (0.0 if r > 0.2 else PI / 3.0)
			M._teil(root, F.walze(0.0065, hh - 0.03, 0.002, 8), g, Vector3(m.x + sin(a) * r * 0.9, 0, m.y + cos(a) * r * 0.9))
	M._schatten(root, Vector2(0.46, 0.46), 0.4, true)


## Gaming-Schreibtisch: dünne Platte mit Schreibtischunterlage über die ganze Breite, Tastatur und
## Maus, T-Gestell aus Metall, Kabelwanne, Kopfhörer am Haken und ein feiner Leuchtstreifen unter der
## Vorderkante (nur Leuchtfarbe, kein eigenes Licht).
static func _gamingtisch(root: Node3D, v: String, b: float) -> void:
	var f: Array = GAMING.get(v, GAMING.schwarz)
	var platte := M._m(S.lack(f[0], 0.5, 0.4))
	var gestell := M._g(S.lack(f[1], 0.42, 0.5))
	var hb := b * 0.5
	M._steht(root, Vector3(b, 0.025, 0.72), platte, 0, 0.72, 0, 0.004)
	M._kiste(root, Vector3(b - 0.06, 0.003, 0.36), S.stoff_farbig(Color("#18191c"), 300.0), Vector3(0, 0.7465, 0.14), 0.0015, false)
	var licht := S.leuchte(f[2], 1.8)
	M._kiste(root, Vector3(b - 0.08, 0.005, 0.006), licht, Vector3(0, 0.716, 0.352), 0.002, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s: int in [-1, 1]:
		var x := s * (hb - 0.12)
		M._steht(root, Vector3(0.06, 0.69, 0.06), gestell, x, 0.03, 0.0, 0.006)
		M._steht(root, Vector3(0.07, 0.03, 0.66), gestell, x, 0.0, 0.0, 0.006)
		M._steht(root, Vector3(0.05, 0.035, 0.62), gestell, x, 0.685, 0.0, 0.004)
	M._steht(root, Vector3(b - 0.24, 0.05, 0.04), gestell, 0, 0.64, -0.24, 0.004)
	M._steht(root, Vector3(b * 0.55, 0.05, 0.12), gestell, 0, 0.58, -0.25, 0.004)
	# Tastatur (Rahmen, Tastenfeld, schwacher Schein darunter) und Maus.
	var tas := S.lack(Color("#202125"), 0.55, 0.3)
	M._steht(root, Vector3(0.44, 0.016, 0.14), tas, -0.08, 0.748, 0.12, 0.004)
	M._steht(root, Vector3(0.42, 0.006, 0.12), S.lack(Color("#2c2d32"), 0.6, 0.3), -0.08, 0.764, 0.12, 0.002)
	M._kiste(root, Vector3(0.43, 0.003, 0.004), licht, Vector3(-0.08, 0.749, 0.192), 0.001, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var maus := PackedVector2Array([Vector2(0, 0), Vector2(0.03, 0), Vector2(0.032, 0.012), Vector2(0.024, 0.03), Vector2(0, 0.036)])
	M._teil(root, F.dreh(maus, 20), tas, Vector3(0.26, 0.748, 0.13), Vector3.ZERO, Vector3(1.0, 1.0, 1.7))
	# Kopfhörer am Haken rechts.
	M._kiste(root, Vector3(0.02, 0.012, 0.06), gestell, Vector3(hb + 0.01, 0.705, 0.18), 0.003, false)
	var kh := _knoten(root, Vector3(hb + 0.03, 0.62, 0.2), Vector3(0, 90, 0))
	M._teil(kh, F.ring(0.08, 0.011, PI, 20, 8), tas, Vector3.ZERO)
	for s2: int in [-1, 1]:
		M._teil(kh, F.walze(0.045, 0.035, 0.012, 20), tas, Vector3(s2 * 0.08, -0.03, -0.0175), Vector3(90, 0, 0))
	M._schatten(root, Vector2(b, 0.72), 0.45)
	M._blick(root, Vector3(0, 1.45, 1.3), Vector3(0, 0.75, 0))


# --- Regale und Stauraum ---------------------------------------------------------------------------

## Sideboard: niedriger Korpus auf konischen Beinen, Türen mit senkrechten Lamellen (ein Netz),
## überstehende Platte; Griffe wählbar.
static func _sideboard(root: Node3D, v: String, b: float) -> void:
	var h := M._m(S.holz(v, 0))
	var dunkel := S.holz("walnuss" if v != "walnuss" else "schwarz", 1)
	var t := 0.42
	M._steht(root, Vector3(b, 0.56, t), h, 0, 0.16, -0.02, 0.004)
	M._steht(root, Vector3(b - 0.04, 0.52, 0.01), dunkel, 0, 0.18, -0.02 + t * 0.5 + 0.002, 0.002)
	var n := maxi(2, int(round(b / 0.45)))
	var tb := (b - 0.04) / n
	for k in n:
		var x0 := -b * 0.5 + 0.02 + tb * k
		var lam := int(tb / 0.034)
		var schritt := (tb - 0.02) / lam
		for j in lam:
			M._steht(root, Vector3(schritt - 0.008, 0.5, 0.016), h, x0 + 0.01 + schritt * (j + 0.5), 0.19, -0.02 + t * 0.5 + 0.012, 0.003)
		M._griff(root, Vector3(x0 + tb * (0.85 if k % 2 == 0 else 0.15), 0.6, -0.02 + t * 0.5 + 0.02), tb, true)
	M._steht(root, Vector3(b + 0.02, 0.025, t + 0.02), h, 0, 0.72, -0.02, 0.004)
	var stellen: Array = []
	for x2: float in [-b * 0.5 + 0.07, b * 0.5 - 0.07]:
		for z: float in [-0.18, 0.14]:
			stellen.append(Vector2(x2, z))
	M._beine(root, stellen, 0.16, S.holz(v, 1), 0.02)
	M._schatten(root, Vector2(b, t), 0.45, false, 0.18, Vector3(0, 0, -0.02))
	M._blick(root, Vector3(0, 1.3, 1.6), Vector3(0, 0.5, 0))


## Wandregal: zwei schwebende Bretter (Halter unsichtbar), darauf Bücher, eine kleine Pflanze, ein
## gerahmtes Bild an die Wand gelehnt und eine Vase.
static func _wandregal(root: Node3D, v: String, b: float) -> void:
	var h := M._m(S.holz(v, 0))
	var z := -0.25 + 0.11
	for i in 2:
		M._steht(root, Vector3(b, 0.028, 0.22), h, 0, i * 0.38, z, 0.004)
	var farben := ["#7a3b2e", "#2f4a5c", "#c49a52", "#4f5d47", "#d8ccb4", "#8a6a8f"]
	var x := -b * 0.5 + 0.06
	for k in 7:
		var bd: float = [0.03, 0.026, 0.038, 0.024, 0.032, 0.028, 0.036][k]
		var bh: float = [0.22, 0.19, 0.24, 0.2, 0.17, 0.23, 0.2][k]
		M._steht(root, Vector3(bd, bh, 0.16), S.stoff_farbig(Color(farben[k % farben.size()]), 200.0), x + bd * 0.5, 0.028, z, 0.003)
		x += bd + 0.003
	# Kleine Pflanze rechts unten.
	var px := b * 0.5 - 0.14
	var topf := PackedVector2Array([Vector2(0, 0), Vector2(0.045, 0), Vector2(0.055, 0.1), Vector2(0.05, 0.1), Vector2(0, 0.09)])
	M._teil(root, F.dreh(topf, 24, [1, 2]), S.lack(Color("#e6dccb"), 0.55, 0.4), Vector3(px, 0.028, z))
	var gruen := S.blatt(Color("#4f7a4a"))
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var bl := M._teil(root, F.blatt(0.11, 0.05, 0.4, 0), gruen, Vector3(px, 0.12, z))
		bl.rotation = Vector3(deg_to_rad(-35.0), a, 0)
	# Oben: liegende Bücher, gelehntes Bild, Vase.
	for k in 3:
		M._steht(root, Vector3(0.24 - k * 0.02, 0.03, 0.17), S.stoff_farbig(Color(farben[(k + 2) % farben.size()]), 200.0), -b * 0.5 + 0.2, 0.408 + k * 0.03, z,
				0.003)
	var bild := _knoten(root, Vector3(0.05, 0.408, z - 0.06), Vector3(-8, 0, 0))
	M._kiste(bild, Vector3(0.26, 0.2, 0.018), S.holz("schwarz", 0), Vector3(0, 0.1, 0), 0.003)
	var m := StandardMaterial3D.new()
	m.albedo_texture = M.motiv("huegel")
	m.roughness = 0.85
	M._teil(bild, F.flaeche(0.21, 0.15), m, Vector3(0, 0.1, 0.0095))
	var vase := PackedVector2Array([Vector2(0, 0), Vector2(0.04, 0), Vector2(0.05, 0.05), Vector2(0.025, 0.14), Vector2(0.03, 0.16), Vector2(0, 0.16)])
	M._teil(root, F.dreh(vase, 24), S.lack(Color("#b0603c"), 0.3, 0.6), Vector3(b * 0.5 - 0.15, 0.408, z))
	M._blick(root, Vector3(0, 0.2, 1.2), Vector3(0, 0.2, z))


## Leiterregal: zwei schräg an die Wand gelehnte Holme, vier Böden (unten tief, oben schmal), darauf
## Bücher, ein Korb und eine Pflanze.
static func _leiterregal(root: Node3D, v: String) -> void:
	var h := M._m(S.holz(v, 0))
	var hoch := 1.8
	var unten := 0.2
	var oben := -0.22
	for s: int in [-1, 1]:
		_stab(root, Vector3(s * 0.43, 0, unten), Vector3(s * 0.43, hoch, oben), 0.035, h, 0.003)
	var boeden := [[0.32, 0.38], [0.72, 0.29], [1.1, 0.21], [1.46, 0.13]]
	var farben := ["#2f4a5c", "#c49a52", "#7a3b2e", "#d8ccb4", "#4f5d47"]
	for i in boeden.size():
		var y: float = boeden[i][0]
		var tiefe: float = boeden[i][1]
		var vorn := lerpf(unten, oben, y / hoch) + 0.02
		var zm := vorn - tiefe * 0.5
		M._steht(root, Vector3(0.82, 0.024, tiefe), h, 0, y, zm, 0.004)
		match i:
			0:
				var korb := PackedVector2Array([Vector2(0, 0), Vector2(0.13, 0), Vector2(0.15, 0.17), Vector2(0.14, 0.17), Vector2(0, 0.012)])
				M._teil(root, F.dreh(korb, 28, [1, 2]), S.oberflaeche("rattan", ""), Vector3(-0.2, y + 0.024, zm))
			1, 3:
				var x := -0.36 if i == 1 else 0.02
				for k in 5:
					var bd := 0.028 + 0.006 * float(k % 3)
					M._steht(root, Vector3(bd, 0.2 - 0.015 * float(k % 2), minf(0.16, tiefe - 0.03)), S.stoff_farbig(Color(farben[(k + i) % farben.size()]), 200.0),
							x + bd * 0.5, y + 0.024, zm, 0.003)
					x += bd + 0.003
			2:
				var topf := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0), Vector2(0.06, 0.11), Vector2(0, 0.1)])
				M._teil(root, F.dreh(topf, 24, [1, 2]), S.lack(Color("#c97b54"), 0.55, 0.4), Vector3(0.2, y + 0.024, zm))
				var gruen := S.blatt(Color("#3f6b44"))
				for k in 7:
					var bl := M._teil(root, F.blatt(0.11, 0.05, 0.5, 0), gruen, Vector3(0.2, y + 0.13, zm))
					bl.rotation = Vector3(deg_to_rad(-25.0 - 10.0 * float(k % 2)), float(k) / 7.0 * TAU, 0)
	M._schatten(root, Vector2(0.9, 0.42), 0.4)
	M._blick(root, Vector3(0, 1.1, 1.8), Vector3(0, 0.85, -0.05))


# --- Technik --------------------------------------------------------------------------------------

## Arcade-Automat (eigene Gestaltung): Seitenwände mit eigenem Umriss und Seitenbild, Kantenband,
## schräges Bedienfeld mit Steuerknüppel und Knöpfen, geneigter Röhrenschirm mit dem Fantasiespiel
## „Planeten-Hüpfer“ (Uzais goldener Spielerpunkt), leuchtendes Kopfschild mit Sonnenstreifen (ohne
## Schrift), Münztür mit zwei glimmenden Schlitzen.
static func _arcade(root: Node3D, v: String) -> void:
	var f: Array = ARCADE.get(v, ARCADE.nacht)
	var korpus := M._m(S.holz("walnuss", 0) if v == "holz" else S.lack(f[0], 0.45, 0.45))
	var band := M._g(S.lack(f[1], 0.35, 0.6))
	var umriss := PackedVector2Array([Vector2(-0.4, 0.0), Vector2(0.36, 0.0), Vector2(0.36, 0.8), Vector2(0.41, 0.84), Vector2(0.41, 0.95),
		Vector2(0.18, 1.02), Vector2(0.13, 1.06), Vector2(-0.02, 1.52), Vector2(0.07, 1.57), Vector2(0.07, 1.76), Vector2(-0.4, 1.8)])
	var seite := StandardMaterial3D.new()
	seite.albedo_texture = _seitenbild(v, f)
	seite.roughness = 0.5
	seite.metallic_specular = 0.4
	seite.vertex_color_use_as_albedo = true
	# Kantenband: derselbe Umriss 6 mm größer und schmaler – es zeigt sich nur als Rand um die Seite.
	var aussen: PackedVector2Array = Geometry2D.offset_polygon(umriss, 0.006, Geometry2D.JOIN_MITER)[0]
	for s: int in [-1, 1]:
		M._teil(root, F.profil(umriss, 0.018, 0.002), seite, Vector3(s * 0.31, 0, 0))
		M._teil(root, F.profil(aussen, 0.012, 0.003), band, Vector3(s * 0.31, 0, 0))
	# Korpus zwischen den Seiten: Rücken, Front unten, Deckel, Boden.
	M._steht(root, Vector3(0.6, 1.78, 0.018), korpus, 0, 0.0, -0.39, 0.002)
	M._steht(root, Vector3(0.6, 0.8, 0.02), korpus, 0, 0.0, 0.35, 0.002)
	M._kiste(root, Vector3(0.6, 0.02, 0.475), korpus, Vector3(0, 1.77, -0.165), 0.002, true, Vector3(4.86, 0, 0))
	M._steht(root, Vector3(0.6, 0.11, 0.02), korpus, 0, 0.84, 0.4, 0.002)
	# Schräge Zwischenstücke, wo der Umriss knickt (unter dem Bedienfeld, vor und über dem Schirm).
	for e: Array in [[Vector3(0, 0.82, 0.385), 0.066, 51.3], [Vector3(0, 1.04, 0.155), 0.066, -51.3], [Vector3(0, 1.545, 0.025), 0.105, 60.9]]:
		M._kiste(root, Vector3(0.6, e[1], 0.02), korpus, e[0], 0.002, true, Vector3(e[2], 0, 0))
	# Münztür.
	M._steht(root, Vector3(0.24, 0.3, 0.008), S.metall(Color("#3a3b3f"), 0.4), 0, 0.3, 0.364, 0.002)
	# Münzschlitz (dunkel) und darunter die glimmende Rückgabe-Leiste.
	M._kiste(root, Vector3(0.012, 0.045, 0.006), S.lack(Color("#0c0c0e"), 0.5), Vector3(0, 0.5, 0.37), 0.002, false)
	M._kiste(root, Vector3(0.11, 0.014, 0.006), S.leuchte(Color("#ff8a3c"), 1.4), Vector3(0, 0.4, 0.37), 0.002, false)
	# Bedienfeld: schräg, Knüppel und sechs Knöpfe, zwei Startknöpfe.
	var feld := _knoten(root, Vector3(0, 0.976, 0.292), Vector3(17.6, 0, 0))
	M._kiste(feld, Vector3(0.6, 0.02, 0.25), S.lack(Color("#141518"), 0.55, 0.3), Vector3.ZERO, 0.003)
	M._kiste(feld, Vector3(0.6, 0.002, 0.012), band, Vector3(0, 0.011, 0.11), 0.001, false)
	var akzent := S.lack(f[3], 0.3, 0.6)
	M._teil(feld, F.walze(0.032, 0.006, 0.002, 20), S.lack(Color("#0c0c0e"), 0.5), Vector3(-0.17, 0.01, 0.02))
	M._teil(feld, F.walze(0.006, 0.07, 0.002, 10), S.metall(Color("#c9cacc"), 0.25), Vector3(-0.17, 0.01, 0.02))
	M._teil(feld, _kugel(0.022), akzent, Vector3(-0.17, 0.075, 0.02))
	var knopf_farben := [akzent, S.lack(f[1], 0.3, 0.6), S.lack(Color("#f3efe7"), 0.3, 0.6)]
	for k in 6:
		var kx := 0.02 + float(k % 3) * 0.06 + (0.0 if k < 3 else 0.015)
		var kz := -0.03 + (0.0 if k < 3 else 0.06)
		M._teil(feld, F.walze(0.017, 0.016, 0.004, 16), knopf_farben[k % 2], Vector3(kx, 0.01, kz))
	for s3: int in [-1, 1]:
		M._teil(feld, F.walze(0.009, 0.01, 0.003, 12), knopf_farben[2], Vector3(0.21 + s3 * 0.025, 0.01, -0.08))
	# Schirm: Rahmen und Bild, nach hinten geneigt.
	var schirm := _knoten(root, Vector3(0, 1.287, 0.0455), Vector3(-18.0, 0, 0))
	M._kiste(schirm, Vector3(0.6, 0.48, 0.02), S.lack(Color("#0b0b0d"), 0.35, 0.5), Vector3.ZERO, 0.004)
	var bild := StandardMaterial3D.new()
	bild.albedo_color = Color.BLACK
	bild.emission_enabled = true
	bild.emission_texture = _spielbild()
	bild.emission_energy_multiplier = 1.25
	bild.roughness = 0.2
	bild.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	M._teil(schirm, F.flaeche(0.46, 0.345), bild, Vector3(0, 0.0, 0.0105))
	# Kopfschild: leuchtende Sonnenstreifen.
	var kopf := StandardMaterial3D.new()
	kopf.albedo_color = Color(0.1, 0.1, 0.1)
	kopf.emission_enabled = true
	kopf.emission_texture = _kopfbild(v, f)
	kopf.emission_energy_multiplier = 1.15
	kopf.roughness = 0.3
	M._steht(root, Vector3(0.6, 0.2, 0.02), korpus, 0, 1.565, 0.06, 0.002)
	M._teil(root, F.flaeche(0.56, 0.16), kopf, Vector3(0, 1.665, 0.0705))
	M._schatten(root, Vector2(0.66, 0.82), 0.5)
	M._blick(root, Vector3(0, 1.45, 1.35), Vector3(0, 1.15, 0.1))


## Seitenbild des Automaten: Grundfarbe, große Sonne mit Streifen, Bergkämme und Sterne (eigene Grafik).
static func _seitenbild(v: String, f: Array) -> ImageTexture:
	var grund: Color = f[2]
	var akz: Color = f[3]
	var band: Color = f[1]
	# Feste Farben vor der Vorschrift: Sie läuft je Bildpunkt.
	var unten := grund.darkened(0.35)
	var kaemme: Array[Color] = []
	for k in 2:
		kaemme.append(grund.darkened(0.25 + k * 0.2))
	var stern := band.lightened(0.4)
	var zeichnen := func(u: float, t: float, x: int, y: int) -> Color:
		var c := grund.lerp(unten, t)
		if t < 0.42 and int(t * 60.0) % 4 != 0 and Vector2(u - 0.42, (t - 0.42) * 0.55).length() < 0.3:
			c = akz.lerp(band, clampf((0.42 - t) * 3.0, 0.0, 1.0))
		for k in 2:
			if t > 0.5 + k * 0.1 + 0.05 * sin(u * (7.0 + k * 3.0) + k):
				c = kaemme[k]
		if t < 0.36 and (x * 7 + y * 13) % 97 == 0:
			c = stern
		return c
	return _bild("arcade_seite_" + v, 96, 192, zeichnen)


## Das Fantasiespiel im Schirm: Planeten-Hüpfer – Plattformen, Sterne, ein Mond und der goldene
## Spielerpunkt im Sprung, mit Zeilen wie auf einer Röhre (eigene Pixelgrafik).
static func _spielbild() -> ImageTexture:
	# Feste Farben und Formen vor der Vorschrift: Sie läuft je Bildpunkt.
	var nacht_a := Color("#140f2e")
	var nacht_b := Color("#3a1d4f")
	var stern := Color("#f3efe7")
	var mond := Color("#e8dcc0")
	var gras := Color("#57c4a5")
	var erde := Color("#2f7d6b")
	var stege: Array[Vector3] = [Vector3(0.08, 0.3, 0.82), Vector3(0.38, 0.62, 0.66), Vector3(0.62, 0.9, 0.78), Vector3(0.18, 0.4, 0.5)]
	var spur: Array[Color] = []
	for k in 4:
		spur.append(GOLD.darkened(0.3 + k * 0.12))
	var zeichnen := func(u: float, t: float, x: int, y: int) -> Color:
		var c := nacht_a.lerp(nacht_b, t)
		if (x * 31 + y * 17) % 61 == 0 and t < 0.6:
			c = stern
		if Vector2(u - 0.8, (t - 0.2) * 0.75).length() < 0.07:
			c = mond
		for p in stege:
			if u > p.x and u < p.y and t > p.z and t < p.z + 0.05:
				c = gras if t < p.z + 0.018 else erde
		if t > 0.94:
			c = erde
		if Vector2(u - 0.47, (t - 0.5) * 0.75).length() < 0.045:
			c = GOLD
		for k in 4:
			if Vector2(u - (0.3 + k * 0.04), (t - (0.62 - k * 0.04)) * 0.75).length() < 0.012:
				c = spur[k]
		if y % 3 == 2:
			c = c.darkened(0.35)
		return c
	return _bild("arcade_spiel", 128, 96, zeichnen, false)


## Kopfschild: Sonnenstreifen über einem Verlauf, kleine Sterne am Rand – ohne Schrift.
static func _kopfbild(v: String, f: Array) -> ImageTexture:
	var akz: Color = f[3]
	var band: Color = f[1]
	var oben := Color("#1b1440")
	var unten := Color("#3d1f55")
	var stern := Color("#f3efe7")
	var zeichnen := func(u: float, t: float, x: int, y: int) -> Color:
		var c := oben.lerp(unten, t)
		if int(t * 24.0) % 3 != 0 and Vector2((u - 0.5) * 3.3, (t - 0.95) * 1.0).length() < 0.75:
			c = band.lerp(akz, clampf((0.95 - t) * 1.6, 0.0, 1.0))
		if absf(u - 0.5) > 0.36 and (x * 13 + y * 7) % 29 == 0:
			c = stern
		return c
	return _bild("arcade_kopf_" + v, 160, 48, zeichnen)


# --- Lampen ---------------------------------------------------------------------------------------

## Bogenlampe: schwerer Fuß, ein Bogen aus einem Stück (über das eigene Feld hinaus nach vorn) und ein
## Metallschirm, innen hell; das Licht fällt nach unten.
static func _bogenlampe(root: Node3D, v: String) -> void:
	var c: Color = METALL.get(v, METALL.messing)
	var met := M._m(S.metall(c, 0.3))
	M._steht(root, Vector3(0.3, 0.12, 0.22), M._g(S.lack(Color("#e6e1d8"), 0.25, 0.6)), 0, 0, -0.3, 0.012)
	var pfad := PackedVector3Array([Vector3(0, 0.12, -0.3), Vector3(0, 1.1, -0.33), Vector3(0, 1.78, -0.12), Vector3(0, 1.98, 0.3),
		Vector3(0, 1.85, 0.68), Vector3(0, 1.68, 0.8)])
	var dicke := PackedFloat32Array()
	for i in pfad.size():
		dicke.append(0.011)
	M._teil(root, F.schlauch(pfad, dicke, dicke, PackedVector3Array([Vector3.RIGHT]), 10, 6), met, Vector3.ZERO)
	var aussen := PackedVector2Array([Vector2(0.2, 0), Vector2(0.19, 0.06), Vector2(0.14, 0.15), Vector2(0.05, 0.2), Vector2(0.012, 0.21),
		Vector2(0.01, 0.2), Vector2(0.045, 0.19), Vector2(0.13, 0.14), Vector2(0.18, 0.055), Vector2(0.19, 0)])
	var schirm := M._teil(root, F.dreh(aussen, 40, [0, 4, 5, 9]), met, Vector3(0, 1.45, 0.8))
	schirm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Innen hell: der Umriss von oben nach unten, damit die Fläche nach innen zeigt.
	var innen := PackedVector2Array([Vector2(0, 0.19), Vector2(0.045, 0.186), Vector2(0.128, 0.138), Vector2(0.176, 0.055), Vector2(0.186, 0.002)])
	M._teil(root, F.dreh(innen, 40), S.lack(Color("#f3efe7"), 0.5, 0.3), Vector3(0, 1.45, 0.8))
	var birne := S.leuchte(WARM, 3.5)
	M._teil(root, _kugel(0.04, 14), birne, Vector3(0, 1.5, 0.8)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	M._lampe(root, Vector3(0, 1.42, 0.8), 1.35, 4.8, [], [birne], [[Vector3(0, 1.48, 0.8), 0.3]])
	M._schatten(root, Vector2(0.34, 0.26), 0.5, false, 0.18, Vector3(0, 0, -0.3))


## Deckenfluter: schlanker Stab auf rundem Fuß, oben eine Schale aus Opalstoff, die nach oben an die
## Decke strahlt.
static func _deckenfluter(root: Node3D, v: String) -> void:
	var met := M._g(S.metall(M.MESSING, 0.32))
	M._teil(root, F.walze(0.14, 0.022, 0.008, 36, true), S.metall(Color("#26262a"), 0.45), Vector3.ZERO)
	M._teil(root, F.walze(0.01, 1.62, 0.003, 12), met, Vector3(0, 0.02, 0))
	var u := PackedVector2Array([Vector2(0.03, 0), Vector2(0.12, 0.05), Vector2(0.21, 0.13), Vector2(0.205, 0.135), Vector2(0.115, 0.057), Vector2(0.026, 0.006)])
	var m := S.schirm(v, M._farbe(Color(0, 0, 0, 0)))
	var schale := M._teil(root, F.dreh(u, 44, [0, 2, 3, 5]), m, Vector3(0, 1.62, 0))
	schale.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	schale.layers = M.SCHIRM_EBENE
	M._teil(root, F.walze(0.03, 0.03, 0.006, 16), met, Vector3(0, 1.6, 0))
	var birne := S.leuchte(WARM, 3.5)
	M._teil(root, F.walze(0.03, 0.04, 0.02, 14), birne, Vector3(0, 1.64, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	M._lampe(root, Vector3(0, 1.8, 0), 1.2, 4.6, [m], [birne], [[Vector3(0, 1.76, 0), 0.32]])
	M._schatten(root, Vector2(0.28, 0.28), 0.45, true)


## Papierleuchte: Dreibein aus Holz, darauf eine Papierkugel mit feinen Rippen, die von innen leuchtet.
static func _papierlampe(root: Node3D, v: String) -> void:
	var holz := M._g(S.holz("eiche", 1))
	for i in 3:
		var a := float(i) / 3.0 * TAU
		_stab(root, Vector3(sin(a) * 0.2, 0, cos(a) * 0.2), Vector3(sin(a) * 0.035, 0.98, cos(a) * 0.035), 0.022, holz, 0.004)
	var r := 0.23
	var u := PackedVector2Array()
	for k in 13:
		var w := -PI * 0.5 + PI * float(k) / 12.0
		u.append(Vector2(maxf(cos(w) * r, 0.03), sin(w) * r * 0.94))
	var m := S.schirm(v, M._farbe(Color(0, 0, 0, 0)))
	var kugel := M._teil(root, F.dreh(u, 40), m, Vector3(0, 1.2, 0))
	kugel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kugel.layers = M.SCHIRM_EBENE
	var rippe := S.lack(M._farbe(S.stoff_farbe(v)).darkened(0.12), 0.7, 0.2)
	for k in range(2, 11):
		var w2 := -PI * 0.5 + PI * float(k) / 12.0
		var rr := cos(w2) * r + 0.002
		var ring := M._teil(root, F.ring(rr, 0.0025, TAU, 36, 4), rippe, Vector3(0, 1.2 + sin(w2) * r * 0.94, 0), Vector3(90, 0, 0))
		ring.layers = M.SCHIRM_EBENE
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var birne := S.leuchte(WARM, 3.5)
	M._teil(root, _kugel(0.035, 12), birne, Vector3(0, 1.17, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	M._lampe(root, Vector3(0, 1.2, 0), 1.0, 4.0, [m], [birne], [[Vector3(0, 1.2, 0), 0.4]])
	M._schatten(root, Vector2(0.42, 0.42), 0.4, true)


## Lichtervorhang: viele dünne Fäden mit Lämpchen hängen von einem Draht unter der Decke (Lämpchen
## je Farbe ein MultiMesh, die Fäden ein Netz).
static func _lichtervorhang(root: Node3D, v: String, breite: float) -> void:
	var z := -0.235
	var draht := S.lack(Color("#2a2826"), 0.6)
	M._kiste(root, Vector3(breite - 0.06, 0.004, 0.004), draht, Vector3(0, 0, z), 0.0015, false)
	var farben: Array = [WARM] if v == "warm" else ([GOLD] if v == "gold" else [Color("#ff6b6b"), Color("#ffd166"), Color("#4fd18b"), Color("#4fa8ff")])
	var orte: Array = []
	for k in farben.size():
		orte.append([])
	var n := int(breite / 0.11)
	var scheine: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var x := (float(i) + 0.5) / n * (breite - 0.08) - (breite - 0.08) * 0.5
		var lang := rng.randf_range(0.9, 1.3)
		M._kiste(root, Vector3(0.0018, lang, 0.0018), draht, Vector3(x, -lang * 0.5, z + 0.004), 0.0008, false)
		var m := int(lang / 0.11)
		for j in m:
			(orte[(i + j) % farben.size()] as Array).append(Vector3(x, -0.06 - j * 0.11, z + 0.008))
		if i % 4 == 1:
			scheine.append([Vector3(x, -lang * 0.5, z + 0.03), 0.09])
	var birnen: Array = []
	var netz := _kugel(0.008, 8)
	for k in farben.size():
		var b := S.leuchte(farben[k], 3.5)
		birnen.append(b)
		_viele(root, orte[k], netz, b)
	var l := M._lampe(root, Vector3(0, -0.6, z + 0.15), 0.45 * breite / 2.0, 2.6, [], birnen, scheine)
	if farben.size() > 1:
		l.light_color = Color("#ffd0e8")
		(root.get_meta("lampen")[0] as Dictionary)["bunt"] = true


## Lichtergirlande: zwei durchhängende Bögen mit großen Kugellampen an kurzen Fassungen.
static func _girlande(root: Node3D, v: String, breite: float) -> void:
	var z := -0.22
	var draht := S.lack(Color("#1f1e1d"), 0.6)
	var bunt := v == "bunt"
	var farben: Array = [WARM if v == "warm" else GOLD] if not bunt else [Color("#ff8a65"), Color("#ffd166"), Color("#7fd6c8"), Color("#c77dff")]
	var pfad := PackedVector3Array()
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		var bogen := fmod(t * 2.0, 1.0) if i < n else 1.0
		pfad.append(Vector3((t - 0.5) * breite * 0.96, -0.16 * 4.0 * bogen * (1.0 - bogen), z))
	var dicke := PackedFloat32Array()
	for i in pfad.size():
		dicke.append(0.0028)
	M._teil(root, F.schlauch(pfad, dicke, dicke, PackedVector3Array([Vector3.BACK]), 6, 2), draht, Vector3.ZERO)
	var orte: Array = []
	for k in farben.size():
		orte.append([])
	var fassungen: Array = []
	var scheine: Array = []
	var m := maxi(4, int(breite / 0.24))
	for j in m:
		var t2 := (float(j) + 0.5) / m
		var bogen2 := fmod(t2 * 2.0, 1.0)
		var p := Vector3((t2 - 0.5) * breite * 0.96, -0.16 * 4.0 * bogen2 * (1.0 - bogen2), z)
		fassungen.append(p + Vector3(0, -0.035, 0))
		(orte[j % farben.size()] as Array).append(p + Vector3(0, -0.085, 0))
		if j % 2 == 0:
			scheine.append([p + Vector3(0, -0.06, 0.03), 0.1])
	_viele(root, fassungen, F.walze(0.009, 0.03, 0.003, 10), draht)
	var birnen: Array = []
	var netz := _kugel(0.024, 14)
	for k in farben.size():
		var b := S.leuchte(farben[k], 3.2)
		birnen.append(b)
		_viele(root, orte[k], netz, b)
	var l := M._lampe(root, Vector3(0, -0.15, -0.05), 0.5 * breite / 2.0, 2.6, [], birnen, scheine)
	if bunt:
		l.light_color = Color("#ffd8c0")
		(root.get_meta("lampen")[0] as Dictionary)["bunt"] = true


# --- Pflanzen -------------------------------------------------------------------------------------

## Bogenhanf: aufrechte, schwertförmige Blätter in zwei Grüntönen aus einem schlichten Topf.
static func _bogenhanf(root: Node3D, v: String, st: int) -> void:
	var k: float = [0.75, 1.0, 1.3][clampi(st, 0, 2)]
	var tr := 0.13 * k
	var th := 0.24 * k
	M._topf(root, tr, th, TOEPFE.get(v, TOEPFE.weiss))
	var gruen := [S.blatt(Color("#2c5236")), S.blatt(Color("#47704a"))]
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 + st
	# Alle Blätter in einem Knoten: zwei Netze (je Grünton), sie wiegen sich gemeinsam.
	var krone := _knoten(root, Vector3(0, th * 0.86, 0), Vector3.ZERO)
	var n := 11
	for i in n:
		var a := float(i) / n * TAU * 1.618
		var r := rng.randf_range(0.0, tr * 0.55)
		var lang := rng.randf_range(0.45, 0.72) * k
		var bl := M._teil(krone, F.blatt(lang, 0.07 * k, 0.06, 1), gruen[i % 2], Vector3(cos(a) * r, 0, sin(a) * r))
		bl.rotation = Vector3(deg_to_rad(-90.0 + rng.randf_range(4.0, 16.0)), -a + PI * 0.5, 0)
	M._wiegen(root, krone)
	M._schatten(root, Vector2(tr * 2.0, tr * 2.0), 0.5, true)


## Hängeampel unter der Decke: Haken, vier Kordeln mit Knoten, Topf und herabhängende Ranken mit
## herzförmigen Blättern (ein MultiMesh); sie wiegt sich leise.
static func _haengepflanze(root: Node3D, v: String) -> void:
	var decke := 2.7
	var kordel := S.stoff_farbig(Color("#e8dcc4"), 60.0, 0.4)
	M._teil(root, F.walze(0.025, 0.02, 0.006, 16), S.metall(M.MESSING, 0.3), Vector3(0, decke - 0.02, 0))
	var ampel := Node3D.new()
	ampel.position = Vector3(0, decke - 0.02, 0)
	root.add_child(ampel)
	var topf_y := -0.86
	for i in 4:
		var a := float(i) / 4.0 * TAU + PI / 4.0
		_stab(ampel, Vector3(0, -0.02, 0), Vector3(sin(a) * 0.04, -0.42, cos(a) * 0.04), 0.006, kordel, 0.002)
		_stab(ampel, Vector3(sin(a) * 0.04, -0.42, cos(a) * 0.04), Vector3(sin(a) * 0.13, topf_y + 0.1, cos(a) * 0.13), 0.006, kordel, 0.002)
		_stab(ampel, Vector3(sin(a) * 0.13, topf_y + 0.1, cos(a) * 0.13), Vector3(sin(a) * 0.085, topf_y - 0.01, cos(a) * 0.085), 0.006, kordel, 0.002)
		_stab(ampel, Vector3(sin(a) * 0.085, topf_y - 0.01, cos(a) * 0.085), Vector3(0, topf_y - 0.04, 0), 0.006, kordel, 0.002)
	M._teil(ampel, _kugel(0.018, 10), kordel, Vector3(0, -0.44, 0))
	var topf := PackedVector2Array([Vector2(0, 0), Vector2(0.08, 0), Vector2(0.12, 0.06), Vector2(0.125, 0.14), Vector2(0.115, 0.14), Vector2(0, 0.13)])
	M._teil(ampel, F.dreh(topf, 32, [1, 3, 4]), S.lack(TOEPFE.get(v, TOEPFE.creme), 0.55, 0.4), Vector3(0, topf_y, 0))
	var ranke := S.lack(Color("#4f7a4a"), 0.6)
	var orte: Array = []
	var dreh: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 7:
		var a2 := float(i) / 7.0 * TAU
		var lang := rng.randf_range(0.35, 0.75)
		var start := Vector3(sin(a2) * 0.13, topf_y + 0.145, cos(a2) * 0.13)
		_stab(ampel, start, start + Vector3(sin(a2) * 0.05, -lang, cos(a2) * 0.05), 0.003, ranke, 0.001)
		var m := int(lang / 0.06)
		for j in m:
			var t := float(j) / maxf(1.0, m - 1)
			orte.append(start + Vector3(sin(a2) * 0.05 * t, -lang * t, cos(a2) * 0.05 * t))
			dreh.append(Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), a2 + rng.randf_range(-1.2, 1.2), rng.randf_range(-0.4, 0.4))))
	for k in 9:
		var a3 := float(k) / 9.0 * TAU
		orte.append(Vector3(sin(a3) * 0.06, topf_y + 0.15, cos(a3) * 0.06))
		dreh.append(Basis.from_euler(Vector3(-0.6, a3, 0)))
	var mmi := _viele(ampel, orte, F.blatt(0.07, 0.065, 0.3, 0), S.blatt(Color("#3f7a45")), dreh)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	M._wiegen(root, ampel)


## Drei Kräutertöpfe auf einem Holztablett: Basilikum (Blätter), Rosmarin (Nadeln) und Schnittlauch.
static func _kraeuter(root: Node3D, v: String) -> void:
	M._steht(root, Vector3(0.42, 0.02, 0.17), S.holz("eiche", 0), 0, 0, 0, 0.004)
	var topf := PackedVector2Array([Vector2(0, 0), Vector2(0.045, 0), Vector2(0.058, 0.095), Vector2(0.062, 0.1), Vector2(0.055, 0.1), Vector2(0, 0.09)])
	var tm := M._g(S.lack(TOEPFE.get(v, TOEPFE.terrakotta), 0.6, 0.3))
	var erde := S.stoff_farbig(Color("#3a2c22"), 300.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3:
		var x := (i - 1) * 0.135
		M._teil(root, F.dreh(topf, 24, [1, 3]), tm, Vector3(x, 0.02, 0))
		M._teil(root, F.walze(0.05, 0.008, 0.002, 16), erde, Vector3(x, 0.105, 0))
		match i:
			0:
				var orte: Array = []
				var dreh: Array = []
				for k in 22:
					var a := float(k) * 2.4
					orte.append(Vector3(x + sin(a) * 0.03, 0.12 + float(k) * 0.004, cos(a) * 0.03))
					dreh.append(Basis.from_euler(Vector3(rng.randf_range(-0.9, -0.3), a, 0)))
				_viele(root, orte, F.blatt(0.05, 0.035, 0.3, 0), S.blatt(Color("#4c8a3e")), dreh)
			1:
				var nadel := S.lack(Color("#5c7559"), 0.6)
				for k in 9:
					var a2 := float(k) / 9.0 * TAU
					_stab(root, Vector3(x + sin(a2) * 0.012, 0.11, cos(a2) * 0.012), Vector3(x + sin(a2) * 0.05, 0.27, cos(a2) * 0.05), 0.006, nadel, 0.002)
			2:
				var halm := S.lack(Color("#5f9a4a"), 0.55)
				for k in 14:
					var a3 := float(k) * 2.4
					var rr := rng.randf_range(0.0, 0.035)
					_stab(root, Vector3(x + sin(a3) * rr, 0.11, cos(a3) * rr), Vector3(x + sin(a3) * (rr + 0.02), rng.randf_range(0.22, 0.3), cos(a3) * (rr + 0.02)), 0.004,
							halm, 0.0015)
	M._schatten(root, Vector2(0.42, 0.17), 0.35)


# --- Teppiche ------------------------------------------------------------------------------------

## Läufer: schmaler, gestreifter Webteppich (Muster wählbar) mit Fransen an beiden Enden (ein Netz).
static func _laeufer(root: Node3D, v: String, w: float, d: float) -> void:
	var c := M._farbe(S.stoff_farbe(v))
	var rand := c.darkened(0.3) if c.get_luminance() > 0.3 else c.lightened(0.3)
	if str(M._it.get("f2", "")) != "":
		rand = Color(str(M._it.f2))
	var mu_id := str(M._it.get("mu", ""))
	var mu := _muster_nr(mu_id if mu_id != "" else "streifen")
	var mf := Color(str(M._it.mf)) if str(M._it.get("mf", "")) != "" else Color("#efe6d6")
	var lang := d - 0.14
	M._kiste(root, Vector3(w - 0.14, 0.012, lang), S.stoff_farbig(rand, 60.0, 1.0), Vector3(0, 0.006, 0), 0.004, false)
	M._kiste(root, Vector3(w - 0.24, 0.016, lang - 0.1), S.stoff_voll(c, 60.0, 1.0, 0.3, 0.0, mu, mf), Vector3(0, 0.008, 0), 0.004, false)
	var franse := S.stoff_farbig(Color("#e9dfcc"), 200.0, 0.5)
	for s: int in [-1, 1]:
		for i in 22:
			var x := -(w - 0.16) * 0.5 + (w - 0.16) * (float(i) + 0.5) / 22.0
			M._kiste(root, Vector3(0.008, 0.004, 0.06), franse, Vector3(x, 0.003, s * (lang * 0.5 + 0.028)), 0.0015, false, Vector3(0, float((i * 7) % 5 - 2) * 3.0, 0))
	for mi in root.get_children():
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Muster-Nummer (gestalt.gd MUSTER) ohne gestalt.gd zu laden (moebel.gd hat es schon).
static func _muster_nr(id: String) -> int:
	return M.G.muster_nr(id)


## Fell: weicher, unregelmäßiger Umriss (Lammfell-Optik) in zwei Lagen mit hohem Flor.
static func _fell(root: Node3D, v: String) -> void:
	var c := M._farbe(FELLE.get(v, FELLE.weiss))
	var u := PackedVector2Array()
	var n := 40
	for i in n:
		var a := float(i) / n * TAU
		var r := 0.6 + 0.07 * sin(a * 3.0 + 0.4) + 0.05 * sin(a * 5.0) + 0.1 * pow(absf(sin(a * 2.0)), 6.0)
		u.append(Vector2(cos(a) * r * 0.62, sin(a) * r * 0.42))
	var unten := M._teil(root, F.profil(u, 0.02, 0.008), S.stoff_farbig(c.darkened(0.08), 25.0, 1.0), Vector3(0, 0.01, 0), Vector3(0, 0, 90))
	unten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var oben := PackedVector2Array()
	for p in u:
		oben.append(p * 0.86)
	var o := M._teil(root, F.profil(oben, 0.02, 0.008), S.stoff_farbig(c, 25.0, 1.0), Vector3(0, 0.016, 0), Vector3(0, 0, 90))
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Deko an der Wand ------------------------------------------------------------------------------

## Bilderwand: großes Hochformat in der Mitte, links ein kleines, rechts zwei übereinander – Rahmen in
## Schwarz, Eiche und Weiß, mit Passepartout; die Motive sind die eigenen Bilder (moebel.gd motiv).
static func _bilderwand(root: Node3D, v: String) -> void:
	var z := -0.235
	var motive := ["huegel", "sonne", "wellen", "punkte"]
	var i0 := maxi(0, motive.find(v))
	var rahmen := [M._g(S.holz("schwarz", 0)), S.holz("eiche", 0), S.lack(Color("#f1ece3"), 0.5, 0.3)]
	var teile := [[Vector2(0.0, 0.42), Vector2(0.5, 0.66), 0], [Vector2(-0.6, 0.48), Vector2(0.34, 0.44), 1],
		[Vector2(0.56, 0.62), Vector2(0.3, 0.3), 2], [Vector2(0.56, 0.24), Vector2(0.3, 0.3), 1]]
	for k in teile.size():
		var mitte: Vector2 = teile[k][0]
		var g: Vector2 = teile[k][1]
		M._kiste(root, Vector3(g.x, g.y, 0.025), rahmen[int(teile[k][2])], Vector3(mitte.x, mitte.y, z), 0.004)
		M._kiste(root, Vector3(g.x - 0.05, g.y - 0.05, 0.004), S.lack(Color("#f4efe6"), 0.85, 0.2), Vector3(mitte.x, mitte.y, z + 0.012), 0.001, false)
		var bw := g.x - 0.12
		var bh := g.y - 0.12
		var m := StandardMaterial3D.new()
		m.albedo_texture = M.motiv(motive[(i0 + k) % motive.size()])
		m.roughness = 0.85
		# Ausschnitt im Seitenverhältnis des Rahmens (das Motiv ist 192 × 132).
		var sx := minf(1.0, (bw / bh) / (192.0 / 132.0))
		var sy := minf(1.0, (bh / bw) * (192.0 / 132.0))
		m.uv1_scale = Vector3(sx, sy, 1)
		m.uv1_offset = Vector3((1.0 - sx) * 0.5, (1.0 - sy) * 0.5, 0)
		M._teil(root, F.flaeche(bw, bh), m, Vector3(mitte.x, mitte.y, z + 0.0145))
	M._blick(root, Vector3(0, 1.55, 1.3), Vector3(0, 1.55, z))


## Strahlenuhr: Scheibe in der Mitte, 24 Strahlen in zwei Längen mit kleinen Kugeln (ein Netz),
## Stundenmarken und Zeiger, die die Uhrzeit des PCs zeigen (moebel.gd stelle_uhr).
static func _strahlenuhr(root: Node3D, v: String) -> void:
	var z := -0.235
	var y := 0.36
	var mat := M._m(S.metall(METALL.messing, 0.3) if v == "messing" else (S.holz("walnuss", 0) if v == "holz" else S.lack(DUNKEL, 0.4, 0.5)))
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var l := 0.3 if i % 2 == 0 else 0.22
		var mi := M._kiste(root, Vector3(0.008, l - 0.1, 0.008), mat, Vector3(sin(a) * (0.1 + (l - 0.1) * 0.5), y + cos(a) * (0.1 + (l - 0.1) * 0.5), z - 0.004),
				0.002, false)
		mi.rotation.z = -a
		var kr := 0.013 if i % 2 == 0 else 0.009
		M._teil(root, _kugel(kr, 10), mat, Vector3(sin(a) * l, y + cos(a) * l - kr, z - 0.004))
	M._teil(root, F.walze(0.115, 0.03, 0.008, 40), mat, Vector3(0, y, z - 0.012), Vector3(90, 0, 0))
	M._teil(root, F.walze(0.1, 0.004, 0.001, 40), S.lack(Color("#f3efe7"), 0.6), Vector3(0, y, z + 0.019), Vector3(90, 0, 0))
	var zeiger := S.lack(Color("#1e1e20"), 0.5)
	for i in 12:
		var a2 := float(i) / 12.0 * TAU
		var mk := M._kiste(root, Vector3(0.005, 0.014 if i % 3 == 0 else 0.008, 0.003), zeiger, Vector3(sin(a2) * 0.085, y + cos(a2) * 0.085, z + 0.023), 0.001,
				false)
		mk.rotation.z = -a2
	var std := _knoten(root, Vector3(0, y, z + 0.027), Vector3.ZERO)
	M._kiste(std, Vector3(0.009, 0.055, 0.004), zeiger, Vector3(0, 0.024, 0), 0.002, false)
	var minu := _knoten(root, Vector3(0, y, z + 0.031), Vector3.ZERO)
	M._kiste(minu, Vector3(0.006, 0.08, 0.004), zeiger, Vector3(0, 0.035, 0), 0.002, false)
	M._teil(root, F.walze(0.008, 0.01, 0.003, 12), S.metall(M.MESSING), Vector3(0, y, z + 0.029), Vector3(90, 0, 0))
	root.set_meta("uhr", [std, minu])
	M.stelle_uhr(root)


## Vorhang an der Wand: Stange mit Endkugeln und Ringen, zwei Stoffbahnen mit Falten bis zum Boden,
## zur Seite gerafft – auch ohne Fenster ein weicher Rahmen.
static func _vorhang(root: Node3D, v: String, breite: float) -> void:
	var z := -0.25 + 0.075
	var stoff := M._m(S.stoff(v, 90.0, 0.1))
	var stange := M._g(S.metall(Color("#2b2c30"), 0.35))
	M._teil(root, F.walze(0.011, breite + 0.06, 0.003, 12), stange, Vector3(-(breite + 0.06) * 0.5, 2.44, z), Vector3(0, 0, -90))
	for s: int in [-1, 1]:
		M._teil(root, _kugel(0.024, 14), stange, Vector3(s * (breite * 0.5 + 0.05), 2.416, z))
		M._kiste(root, Vector3(0.012, 0.06, 0.07), stange, Vector3(s * (breite * 0.5 - 0.02), 2.44, z - 0.035), 0.003, false)
	var bahn := clampf(breite * 0.3, 0.32, 0.8)
	var falten := maxi(4, int(bahn / 0.07))
	for s2: int in [-1, 1]:
		var x := s2 * (breite * 0.5 - bahn * 0.5 - 0.02)
		var mi := M._teil(root, F.vorhang(bahn, 2.38, falten, 0.035), stoff, Vector3(x, 0.03, z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for k in falten:
			M._teil(root, F.ring(0.016, 0.0028, TAU, 16, 4), stange, Vector3(x - bahn * 0.5 + bahn * (float(k) + 0.5) / falten, 2.44, z), Vector3(0, 90, 0))
	M._blick(root, Vector3(0, 1.4, 1.8), Vector3(0, 1.3, z))

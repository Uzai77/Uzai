extends RefCounted
## Möbel rund um Figur und Haustier, im Stil der übrigen Möbel (moebel.gd ruft hierher): Jackenständer
## (A: Figur wechseln – statt des früheren Spiegels, der das ganze Zimmer ein zweites Mal zeichnete),
## Tierkörbchen (dort schläft dein Haustier) und zwei Belohnungen fürs Spielen – Lavalampe und
## Leuchtschild (meilensteine.gd). Alles aus eigenen Formen; die Metas folgen moebel.gd (lampen,
## schatten, blick, sitz …), dazu „liegeplatz“ (wo das Tier im Korb liegt).

const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const FF := preload("res://src/room/figur/figur_formen.gd")
const LAVA_S := preload("res://src/room/figur/shaders/lava.gdshader")

const WARM := Color(1.0, 0.76, 0.52)
const SCHIRM_EBENE := 2
const LAVA := { "orange": [Color("#ff8a3d"), Color("#c2361f")], "lila": [Color("#c77dff"), Color("#5a2a8a")], "mint": [Color("#7fe0b8"), Color("#2b7a6a")] }
const NEON := { "rosa": Color("#ff6fa8"), "blau": Color("#6fb8ff"), "gold": Color("#ffc65c") }


static func bauen(root: Node3D, id: String, v: String) -> void:
	match id:
		"jackenstaender": _jackenstaender(root, v)
		"tierkorb": _korb(root, v)
		"lavalampe": _lava(root, v)
		"neonschild": _neon(root, v)


static func _teil(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, skal := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = skal
	root.add_child(mi)
	return mi


static func _schatten(root: Node3D, groesse: Vector2, staerke := 0.5, rund := false) -> void:
	var liste: Array = root.get_meta("schatten", [])
	liste.append([Vector3.ZERO, groesse, minf(0.85, staerke * 1.25), rund, 0.16])
	root.set_meta("schatten", liste)


static func _lampe(root: Node3D, pos: Vector3, farbe: Color, energie: float, reichweite: float, leuchten: Array) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = farbe
	l.light_energy = energie
	l.omni_range = reichweite
	l.omni_attenuation = 1.3
	l.light_specular = 0.3
	l.light_cull_mask = 0xFFFFF & ~SCHIRM_EBENE
	root.add_child(l)
	var lampen: Array = root.get_meta("lampen", [])
	lampen.append({ "licht": l, "energie": energie, "weite": reichweite, "schirme": [], "birnen": leuchten, "bunt": true })
	root.set_meta("lampen", lampen)


## Jackenständer wie ein Bugholz-Garderobenständer: gedrechselte Säule auf vier geschwungenen Beinen,
## zwei Kränze gebogener Haken mit Kugelenden (alles Holz nach Variante, ein Netz). Daran ein Wollmantel,
## der in weichen Falten fällt (hängende Ärmel, Kragen, Knopfleiste), um seinen Kragen ein Strickschal
## mit Fransen, oben eine Rippstrickmütze mit Bommel und am Haken daneben eine Ledertasche am Riemen.
## Gedeckte Farben (JACKE). Je Stoff ein Netz (FF.verbinden): fünf Zeichenaufrufe, keine eigenen Schatten.
const JACKE := { "mantel": Color("#4f5663"), "schal": Color("#a8874a"), "muetze": Color("#62663f"), "tasche": Color("#7a4a2c") }
## Mantel von oben (Aufhänger) nach unten: [Höhe, halbe Breite, halbe Tiefe]. Oben die Schultern, die am
## Haken nach unten sacken, unten etwas ausgestellt.
const MANTEL := [
	Vector3(0.0, 0.075, 0.052), Vector3(-0.03, 0.115, 0.06), Vector3(-0.07, 0.155, 0.068), Vector3(-0.12, 0.183, 0.073),
	Vector3(-0.2, 0.198, 0.076), Vector3(-0.4, 0.205, 0.078), Vector3(-0.6, 0.216, 0.082), Vector3(-0.8, 0.234, 0.088),
	Vector3(-0.86, 0.238, 0.09)]
const HAKEN_OBEN := 1.56     ## Höhe des oberen Hakenkranzes (der untere: 1,42)
const MANTEL_HAKEN := -35.0  ## Winkel des Hakens mit dem Mantel (0 = nach vorn, ins Zimmer)
const TASCHEN_HAKEN := MANTEL_HAKEN + 90.0  ## der Haken rechts daneben


static func _jackenstaender(root: Node3D, v: String) -> void:
	var r := PackedVector3Array([Vector3.RIGHT])
	# Säule: Bund, an dem die Beine sitzen, schlanker Schaft, je ein Wulst an den Hakenkränzen, Knauf.
	var saeule := PackedVector2Array([Vector2(0.0, 0.2), Vector2(0.022, 0.2), Vector2(0.028, 0.212), Vector2(0.029, 0.24),
		Vector2(0.026, 0.3), Vector2(0.03, 0.318), Vector2(0.022, 0.335), Vector2(0.019, 0.5), Vector2(0.0165, 1.38),
		Vector2(0.022, 1.395), Vector2(0.022, 1.44), Vector2(0.017, 1.455), Vector2(0.016, 1.52), Vector2(0.022, 1.535),
		Vector2(0.022, 1.58), Vector2(0.016, 1.595), Vector2(0.014, 1.72), Vector2(0.024, 1.75), Vector2(0.026, 1.775),
		Vector2(0.018, 1.8), Vector2(0.0, 1.805)])
	var holz: Array = [[F.dreh(saeule, 24, [1]), Transform3D()]]
	# Vier Beine, als Bugholz geschwungen, mit kleinen Füßen.
	var bein := PackedVector3Array([Vector3(0, 0.29, 0.012), Vector3(0, 0.25, 0.035), Vector3(0, 0.17, 0.075),
		Vector3(0, 0.085, 0.13), Vector3(0, 0.03, 0.185), Vector3(0, 0.013, 0.222)])
	var bein_r := PackedFloat32Array([0.017, 0.017, 0.016, 0.015, 0.013, 0.012])
	var bein_m := F.schlauch(bein, bein_r, bein_r, r, 12, 4, Vector3.ZERO, -1.0, Vector2(-1.0, 1.0))
	var fuss := FF.ei(Vector3(0.015, 0.012, 0.015), 12)
	for i in 4:
		var b := Basis(Vector3.UP, TAU * i / 4.0 + PI / 4.0)
		holz.append([bein_m, Transform3D(b, Vector3.ZERO)])
		holz.append([fuss, Transform3D(b, b * Vector3(0, 0.012, 0.224))])
	# Haken: aus der Säule hinaus, unten eine Mulde (dort hängt der Aufhänger), dann hoch zur Kugel.
	var haken := PackedVector3Array([Vector3(0, 0, 0.012), Vector3(0, -0.013, 0.065), Vector3(0, -0.01, 0.11),
		Vector3(0, 0.018, 0.142), Vector3(0, 0.058, 0.152), Vector3(0, 0.084, 0.146)])
	var haken_r := PackedFloat32Array([0.0095, 0.009, 0.0085, 0.008, 0.0078, 0.0075])
	var haken_m := F.schlauch(haken, haken_r, haken_r, r, 10, 4, Vector3.ZERO, -1.0, Vector2(-1.0, -1.0))
	var kugel := FF.ei(Vector3(0.0125, 0.0125, 0.0125), 10)
	for k in 8:
		var oben := k < 4
		var b := Basis(Vector3.UP, deg_to_rad(MANTEL_HAKEN + 90.0 * k + (0.0 if oben else 45.0)))
		var g := 1.0 if oben else 0.85
		var fuss_h := Vector3(0, HAKEN_OBEN if oben else 1.42, 0)
		holz.append([haken_m, Transform3D(b.scaled(Vector3.ONE * g), fuss_h)])
		holz.append([kugel, Transform3D(b.scaled(Vector3.ONE * g), fuss_h + b * (haken[5] * g))])
	_teil(root, FF.verbinden("jackenstaender_holz", holz), S.holz(v, 1), Vector3.ZERO)
	# Mantel: hängt am Aufhänger hinten im Kragen, also gut eine Kragentiefe vor dem Haken, unten ein
	# wenig zur Säule hin.
	var bm := Basis(Vector3.UP, deg_to_rad(MANTEL_HAKEN))
	var tm := Transform3D(bm * Basis(Vector3.RIGHT, 0.035), bm * Vector3(0, HAKEN_OBEN, 0.085 + 0.045))
	_teil(root, FF.verbinden("jackenstaender_mantel", _mantel(tm)), _gewand(JACKE.mantel, 160.0, 0.15, 0.09, 0.45), Vector3.ZERO)
	_teil(root, FF.verbinden("jackenstaender_schal", _schal(tm)), _gewand(JACKE.schal, 60.0, 0.35, 0.1, 0.9), Vector3.ZERO)
	# Mütze über dem Knauf: Rippstrick mit umgeschlagenem Bund, Bommel.
	var mh := PackedVector3Array()
	var mr := PackedFloat32Array()
	for e: Vector2 in [Vector2(0.0, 0.094), Vector2(0.03, 0.097), Vector2(0.05, 0.097), Vector2(0.056, 0.09),
			Vector2(0.09, 0.088), Vector2(0.125, 0.072), Vector2(0.15, 0.042), Vector2(0.162, 0.012)]:
		mh.append(Vector3(0, e.x, 0))
		mr.append(e.y)
	var muetze: Array = [
		[F.schlauch(mh, mr, mr, r, 48, 3, Vector3(24, 0.0016, 0.0009), -1.0, Vector2(0.2, 0.9)), Transform3D()],
		[FF.ei(Vector3(0.04, 0.036, 0.04), 16), Transform3D(Basis(), Vector3(0, 0.185, 0))],
	]
	_teil(root, FF.verbinden("jackenstaender_muetze", muetze), _gewand(JACKE.muetze, 55.0, 0.4, 0.08, 0.8), Vector3(0.006, 1.668, 0),
			Vector3(-0.05, 0.0, -0.08))
	var bt := Basis(Vector3.UP, deg_to_rad(TASCHEN_HAKEN))
	_teil(root, FF.verbinden("jackenstaender_tasche", _tasche(Transform3D(bt, bt * Vector3(0, HAKEN_OBEN - 0.013, 0.085)))),
			_fein(S.stoff_voll(JACKE.tasche, 140.0, 0.0, 0.12, 0.65, 0, Color.WHITE), 0.12, 0.5), Vector3.ZERO)
	_schatten(root, Vector2(0.5, 0.5), 0.45, true)
	root.set_meta("blick", { "pos": Vector3(0, 1.45, 1.4), "ziel": Vector3(0, 1.15, 0) })


## Halbe Breite und halbe Tiefe des Mantels in der Höhe y (unter dem Aufhänger).
static func _mantel_mass(y: float) -> Vector2:
	for i in MANTEL.size() - 1:
		var a: Vector3 = MANTEL[i]
		var b: Vector3 = MANTEL[i + 1]
		if y <= a.x and y >= b.x:
			var t := (a.x - y) / (a.x - b.x)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	var l: Vector3 = MANTEL[MANTEL.size() - 1]
	return Vector2(l.y, l.z)


## Wo die Vorderseite des Mantels in der Höhe y bei x liegt (z).
static func _mantel_vorn(x: float, y: float) -> float:
	var m := _mantel_mass(y)
	return m.y * sqrt(maxf(0.0, 1.0 - pow(x / m.x, 2.0)))


## Mantel: Rumpf mit Falten (vorn die ruhige Knopfleiste), Kragen, hängende Ärmel, vier Knöpfe.
static func _mantel(tm: Transform3D) -> Array:
	var r := PackedVector3Array([Vector3.RIGHT])
	var mp := PackedVector3Array()
	var mb := PackedFloat32Array()
	var md := PackedFloat32Array()
	for e: Vector3 in MANTEL:
		mp.append(Vector3(0, e.x, 0))
		mb.append(e.y)
		md.append(e.z)
	var teile: Array = [[F.schlauch(mp, mb, md, r, 48, 4, Vector3(5, 0.003, 0.02), PI * 0.5, Vector2(0.45, 0.22)), tm]]
	# Kragen: liegt auf den Schultern auf, oben die dunkle Halsöffnung.
	teile.append([F.schlauch(PackedVector3Array([Vector3(0, 0.02, -0.004), Vector3(0, 0.0, 0.0), Vector3(0, -0.035, 0.004)]),
			PackedFloat32Array([0.088, 0.095, 0.124]), PackedFloat32Array([0.064, 0.066, 0.066]), r, 40, 3,
			Vector3(5, 0.001, 0.002), PI * 0.5, Vector2(0.18, -1.0)), tm])
	for s: float in [-1.0, 1.0]:
		var arm := PackedVector3Array([Vector3(s * 0.12, -0.07, 0.0), Vector3(s * 0.178, -0.11, 0.008), Vector3(s * 0.21, -0.25, 0.022),
			Vector3(s * 0.22, -0.45, 0.034), Vector3(s * 0.214, -0.62, 0.04)])
		teile.append([F.schlauch(arm, PackedFloat32Array([0.044, 0.044, 0.042, 0.039, 0.037]),
				PackedFloat32Array([0.04, 0.04, 0.037, 0.034, 0.032]), PackedVector3Array([Vector3.BACK]), 24, 4,
				Vector3(4, 0.0008, 0.004), -1.0, Vector2(-1.0, 0.2)), tm])
	var knopf := _getoent(FF.ei(Vector3(0.011, 0.011, 0.005), 10), 0.32)
	for y: float in [-0.16, -0.29, -0.42, -0.55]:
		teile.append([knopf, tm * Transform3D(Basis(), Vector3(0, y, _mantel_vorn(0.0, y) + 0.003))])
	return teile


## Schal: um den Kragen gelegt (dort hochkant und gebauscht), beide Enden hängen vorn, links länger;
## Fransen an den Enden.
static func _schal(tm: Transform3D) -> Array:
	var sp := PackedVector3Array()
	var sq := PackedVector3Array()
	var sb := PackedFloat32Array()
	var sd := PackedFloat32Array()
	var schraeg_l := Vector3(0.6, 0.8, 0).normalized()
	var schraeg_r := Vector3(-0.6, 0.8, 0).normalized()
	for e: Array in [[-0.062, -0.5, Vector3.RIGHT, 0.06, 0.009], [-0.07, -0.3, Vector3.RIGHT, 0.06, 0.009],
			[-0.08, -0.13, Vector3.RIGHT, 0.058, 0.0095], [-0.105, -0.045, schraeg_l, 0.05, 0.012, 0.062],
			[-0.135, -0.022, Vector3.UP, 0.04, 0.015, 0.0], [-0.0955, -0.018, Vector3.UP, 0.038, 0.015, -0.0636],
			[0.0, -0.015, Vector3.UP, 0.038, 0.015, -0.09], [0.0955, -0.018, Vector3.UP, 0.038, 0.015, -0.0636],
			[0.135, -0.022, Vector3.UP, 0.04, 0.015, 0.0], [0.105, -0.045, schraeg_r, 0.05, 0.012, 0.062],
			[0.08, -0.13, -Vector3.RIGHT, 0.058, 0.0095], [0.084, -0.26, -Vector3.RIGHT, 0.06, 0.009],
			[0.09, -0.38, -Vector3.RIGHT, 0.06, 0.009]]:
		var x: float = e[0]
		var y: float = e[1]
		var dick: float = e[4]
		var z: float = e[5] if e.size() > 5 else _mantel_vorn(x, y) + dick + 0.006
		sp.append(Vector3(x, y, z))
		sq.append(e[2])
		sb.append(e[3])
		sd.append(dick)
	var teile: Array = [[F.schlauch(sp, sb, sd, sq, 16, 4, Vector3(3, 0.0028, 0.0035), -1.0, Vector2(0.85, 0.85)), tm]]
	var franse := F.kiste(Vector3(0.008, 0.045, 0.005), 0.0015)
	for ende in [0, sp.size() - 1]:
		var p := sp[ende]
		for k in 7:
			var b := Basis(Vector3.FORWARD, 0.07 * sin(k * 2.3 + ende))
			teile.append([franse, tm * Transform3D(b, p + Vector3((k - 3) * 0.02, -0.0225, 0.001 * (k % 2)))])
	return teile


## Ledertasche am Haken: Riemen über den Haken, weicher Korpus, Klappe mit Lasche (dunkler).
static func _tasche(tt: Transform3D) -> Array:
	var riemen := PackedVector3Array()
	for e: Vector2 in [Vector2(-0.112, -0.325), Vector2(-0.085, -0.22), Vector2(-0.04, -0.075), Vector2(-0.013, -0.004),
			Vector2(0.0, 0.0115), Vector2(0.013, -0.004), Vector2(0.04, -0.075), Vector2(0.085, -0.22), Vector2(0.112, -0.325)]:
		riemen.append(Vector3(e.x, e.y, 0.0))
	var rb := PackedFloat32Array()
	rb.resize(riemen.size())
	rb.fill(0.012)
	var rd := PackedFloat32Array()
	rd.resize(riemen.size())
	rd.fill(0.0022)
	return [
		[F.schlauch(riemen, rb, rd, PackedVector3Array([Vector3.BACK]), 8, 3, Vector3.ZERO, -1.0, Vector2(-1.0, -1.0)), tt],
		[F.kiste(Vector3(0.27, 0.21, 0.08), 0.028), tt * Transform3D(Basis(), Vector3(0, -0.425, 0))],
		[F.kiste(Vector3(0.274, 0.125, 0.01), 0.005), tt * Transform3D(Basis(), Vector3(0, -0.385, 0.045))],
		[_getoent(F.kiste(Vector3(0.028, 0.05, 0.007), 0.002), 0.55), tt * Transform3D(Basis(), Vector3(0, -0.445, 0.052))],
	]


## Stoff und Leder für Kleidung: feiner als an Polstermöbeln (Karte kleiner gekachelt, Relief zurückgenommen),
## kaum Samtschimmer an den Kanten (sonst leuchtete der Umriss). Einmal je Grundmaterial und Maß.
static var _gewaender := {}


static func _gewand(c: Color, webung: float, flor: float, mass: float, relief: float) -> Material:
	return _fein(S.stoff_farbig(c, webung, flor), mass, relief)


static func _fein(grund: Material, mass: float, relief: float) -> Material:
	var key := "%d|%.3f|%.2f" % [grund.get_instance_id(), mass, relief]
	if not _gewaender.has(key):
		var m := grund.duplicate() as ShaderMaterial
		m.set_shader_parameter("t_mass", mass)
		m.set_shader_parameter("t_staerke", relief)
		m.set_shader_parameter("schimmer", 0.1)
		_gewaender[key] = m
	return _gewaender[key]


## Dasselbe Netz mit einer einheitlichen Eckpunktfarbe (dunklere Knöpfe, Lasche im selben Material).
static func _getoent(mesh: ArrayMesh, hell: float) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var farben := PackedColorArray()
	farben.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	farben.fill(Color(hell, hell, hell))
	arr[Mesh.ARRAY_COLOR] = farben
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Rundes Körbchen aus Flechtwerk mit einem dicken Kissen.
static func _korb(root: Node3D, v: String) -> void:
	var rand := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.0), Vector2(0.23, 0.04), Vector2(0.235, 0.11), Vector2(0.215, 0.13),
		Vector2(0.2, 0.11), Vector2(0.19, 0.04), Vector2(0.0, 0.04)])
	_teil(root, F.dreh(rand, 40, [1, 3, 5, 6], true), S.holz("eiche", 1), Vector3.ZERO)
	_teil(root, F.ring(0.212, 0.026, TAU, 40, 10), S.stoff(v, 60.0), Vector3(0, 0.12, 0), Vector3(PI * 0.5, 0, 0))
	_teil(root, FF.ei(Vector3(0.19, 0.045, 0.19), 28, 0.25), S.stoff(v, 70.0, 0.4), Vector3(0, 0.07, 0))
	_schatten(root, Vector2(0.48, 0.48), 0.5, true)
	root.set_meta("liegeplatz", Vector3(0, 0.08, 0))
	root.set_meta("blick", { "pos": Vector3(0, 0.9, 0.9), "ziel": Vector3(0, 0.1, 0) })


## Lavalampe: Fuß und Kappe aus Metall, dazwischen das Glas mit langsam steigendem Wachs.
static func _lava(root: Node3D, v: String) -> void:
	var f: Array = LAVA.get(v, LAVA.orange)
	var metall := S.metall(Color("#b9b3aa"), 0.3)
	var fuss := PackedVector2Array([Vector2(0, 0), Vector2(0.07, 0), Vector2(0.072, 0.012), Vector2(0.045, 0.12), Vector2(0.0, 0.12)])
	_teil(root, F.dreh(fuss, 32, [1, 2]), metall, Vector3.ZERO)
	var glas := PackedVector2Array([Vector2(0, 0), Vector2(0.044, 0), Vector2(0.056, 0.08), Vector2(0.038, 0.2), Vector2(0.024, 0.24), Vector2(0, 0.24)])
	var m := ShaderMaterial.new()
	m.shader = LAVA_S
	m.set_shader_parameter("wachs", f[0])
	m.set_shader_parameter("fluessig", f[1])
	var g := _teil(root, F.dreh(glas, 32), m, Vector3(0, 0.12, 0))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_teil(root, F.dreh(PackedVector2Array([Vector2(0, 0), Vector2(0.026, 0), Vector2(0.018, 0.05), Vector2(0, 0.055)]), 24, [1]), metall, Vector3(0, 0.355, 0))
	root.set_meta("lava", m)
	_lampe(root, Vector3(0, 0.26, 0), (f[0] as Color).lerp(WARM, 0.3), 0.55, 2.2, [])
	_schatten(root, Vector2(0.16, 0.16), 0.4, true)


## Leuchtschild „gg“ in Neonröhren-Optik auf einer Acrylplatte (eigene Schrift: die Uzai-Schrift).
static func _neon(root: Node3D, v: String) -> void:
	var c: Color = NEON.get(v, NEON.rosa)
	var z := -0.22
	_teil(root, F.kiste(Vector3(0.82, 0.42, 0.012), 0.01), S.glas(Color(0.9, 0.92, 0.95, 0.16)), Vector3(0, 0.21, z))
	for s: float in [-1.0, 1.0]:
		_teil(root, F.walze(0.008, 0.03, 0.002, 10), S.metall(Color("#c9c4bb"), 0.3), Vector3(s * 0.36, 0.38, z - 0.02), Vector3(PI * 0.5, 0, 0))
	var schrift := Label3D.new()
	schrift.text = "gg"
	schrift.font = UzTheme.display("black")
	schrift.font_size = 220
	schrift.pixel_size = 0.0016
	schrift.position = Vector3(0, 0.22, z + 0.012)
	schrift.modulate = Color(c.r * 2.4, c.g * 2.4, c.b * 2.4)
	schrift.outline_size = 22
	schrift.outline_modulate = Color(c.r, c.g, c.b, 0.35)
	schrift.shaded = false
	schrift.double_sided = false
	schrift.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(schrift)
	var punkt := S.leuchte(c, 3.0)
	_teil(root, FF.ei(Vector3(0.022, 0.022, 0.01), 14), punkt, Vector3(0.27, 0.12, z + 0.014))
	root.set_meta("neon", schrift)
	root.set_meta("neon_farbe", c)
	_lampe(root, Vector3(0, 0.22, z + 0.25), c, 0.7, 2.4, [punkt])


## Lavalampe und Leuchtschild nach an/aus (moebel.schalten setzt Licht und Birnen).
static func schalten(root: Node3D, an: bool) -> void:
	if root.has_meta("lava"):
		(root.get_meta("lava") as ShaderMaterial).set_shader_parameter("an", 1.0 if an else 0.0)
	if root.has_meta("neon"):
		var c: Color = root.get_meta("neon_farbe")
		var k := 2.4 if an else 0.55
		(root.get_meta("neon") as Label3D).modulate = Color(c.r * k, c.g * k, c.b * k)

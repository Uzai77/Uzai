extends Node
## Startanimationen je System als echte 3D-Szenen (für system_intro.gd): PlayStation 2, GameCube,
## PlayStation, Nintendo 64 und Switch – in derselben Machart wie die Startanimation von Uzai
## (boot.gd): eigener SubViewport in den echten Bildpunkten, dunkler Raum mit Dunst, spiegelnder
## Boden, Glanz und Licht. Alles eigener Entwurf (R4): Anmutung der Konsole in Farbe, Material und
## Bewegung, kein Nachbau der Original-Starts, keine Logos, keine Schriftzüge (der Name kommt von
## system_intro.gd darüber).
##
## Jede Szene ist eine Rechnung der Zeit: stellen(t) setzt alles für den Zeitpunkt t (0 … DAUER) –
## Vorschau, Proben und Abbruch springen beliebig. Die Szenen bauen nur aus Grundkörpern von Godot
## (kein eigener Netzbau), der Aufbau kostet beim Spielstart kaum etwas.
##   ps2     gläserne Säulen wachsen aus einem spiegelnden Boden in blauer Tiefe, Lichtteilchen
##           steigen, die Kamera gleitet hinein; zum Höhepunkt hebt sich das Licht
##   gc      ein violetter Würfel aus acht Teilen rollt in drei Kippern heran, setzt auf, öffnet
##           sich kurz (Licht aus den Fugen) und schließt sich
##   ps1     zwei dunkle Platten öffnen einen Lichtspalt zu reinem Weiß, die Kamera fährt hindurch
##           in einen ruhigen, warmen grauen Raum
##   n64     vier bunte Körper (Kugel, Würfel, Ring, Spitzkörper) fliegen kreiselnd aus der Tiefe
##           heran, reihen sich auf und wippen
##   switch  zwei leuchtende Seitenteile (Blau, Rot) gleiten herein und rasten in der Mitte ein –
##           Lichtschlag, ein Ring läuft aus, Ruhe

const ARTEN := ["ps2", "gc", "ps1", "n64", "switch"]
const HOEHEPUNKT := 1.36
const DAUER := 2.6

const BODEN_SHADER := """shader_type spatial;
uniform vec4 farbe : source_color = vec4(0.01, 0.012, 0.02, 1.0);
uniform float weite = 18.0;
varying vec3 welt;
void vertex() {
	welt = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float f = exp(-dot(welt.xz, welt.xz) / weite);
	ALBEDO = farbe.rgb;
	ROUGHNESS = mix(1.0, 0.08, f);
	SPECULAR = 0.5 * f;
}
"""
## Lichtteilchen (PS2): steigen langsam, jedes mit eigener Lage (Transform) und Phase (CUSTOM.x).
const TEILCHEN_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 farbe : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float zeit = 0.0;
uniform float staerke = 1.0;
void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + vec3(0.0, zeit * (0.15 + 0.2 * INSTANCE_CUSTOM.x), 0.0);
	vec3 r = INV_VIEW_MATRIX[0].xyz;
	vec3 u = INV_VIEW_MATRIX[1].xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(o + (r * VERTEX.x + u * VERTEX.y) * 0.05, 1.0);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = farbe.rgb * staerke * exp(-d * d * 6.0) * 1.6;
}
"""

var art := ""
var sv: SubViewport
var welt: Node3D
var cam: Camera3D
var env: Environment
var _n := {}                     ## Teile der Szene (Name -> Knoten oder Material)


static func hat(seq: String) -> bool:
	return seq in ARTEN


func setup(a: String) -> Node:
	art = a
	return self


func _ready() -> void:
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = Vector2i(64, 36)
	add_child(sv)
	welt = Node3D.new()
	sv.add_child(welt)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 40.0
	we.environment = env
	welt.add_child(we)
	cam = Camera3D.new()
	cam.fov = 32.0
	cam.near = 0.05
	cam.far = 80.0
	welt.add_child(cam)
	cam.current = true
	match art:
		"ps2":
			_ps2()
		"gc":
			_gc()
		"ps1":
			_ps1()
		"n64":
			_n64()
		"switch":
			_switch()


func textur() -> ViewportTexture:
	return sv.get_texture()


func groesse(px: Vector2i) -> void:
	if px.x >= 2 and px.y >= 2 and sv.size != px:
		sv.size = px


## Die Szene zum Zeitpunkt t stellen.
func stellen(t: float) -> void:
	match art:
		"ps2":
			_ps2_t(t)
		"gc":
			_gc_t(t)
		"ps1":
			_ps1_t(t)
		"n64":
			_n64_t(t)
		"switch":
			_switch_t(t)


# --- Bausteine ------------------------------------------------------------------------------

static func _ein(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _stoff(c: Color, metall: float, rau: float, leuchten := 0.0, klarlack := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metall
	m.roughness = rau
	if leuchten > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = leuchten
	if klarlack > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = klarlack
		m.clearcoat_roughness = 0.05
	return m


func _koerper(mesh: Mesh, m: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	welt.add_child(mi)
	return mi


func _boden(c: Color, y := 0.0, weite := 18.0) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BODEN_SHADER
	sm.shader = sh
	sm.set_shader_parameter("farbe", c)
	sm.set_shader_parameter("weite", weite)
	_koerper(pm, sm, Vector3(0, y, 0))


func _licht(at: Vector3, c: Color, e: float, weite := 8.0, nebel := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = e
	l.omni_range = weite
	l.light_volumetric_fog_energy = nebel
	l.position = at
	welt.add_child(l)
	return l


func _spot(at: Vector3, ziel: Vector3, c: Color, e: float, winkel := 30.0) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = c
	s.light_energy = e
	s.spot_range = 30.0
	s.spot_angle = winkel
	s.shadow_enabled = true
	welt.add_child(s)
	s.look_at_from_position(at, ziel)
	return s


func _kamera(von: Vector3, ziel: Vector3) -> void:
	cam.look_at_from_position(von, ziel)


# --- PlayStation 2 --------------------------------------------------------------------------

func _ps2() -> void:
	env.background_color = Color(0.004, 0.008, 0.025)
	env.ambient_light_color = Color(0.05, 0.08, 0.2)
	env.volumetric_fog_albedo = Color(0.3, 0.45, 1.0)
	env.volumetric_fog_density = 0.035
	_boden(Color(0.006, 0.01, 0.03))
	var glas := _stoff(Color(0.08, 0.16, 0.42), 0.3, 0.04, 0.35, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000
	var saeulen: Array = []
	for i in 18:
		var x := rng.randf_range(1.3, 7.0) * (-1.0 if i % 2 == 0 else 1.0)
		var z := rng.randf_range(-16.0, -2.0)
		var h := rng.randf_range(1.6, 5.5)
		var w := rng.randf_range(0.35, 0.7)
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, w)
		var mi := _koerper(bm, glas, Vector3(x, 0, z))
		saeulen.append([mi, h, 0.05 + i * 0.045])
	_n["saeulen"] = saeulen
	# Lichtteilchen.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mm.mesh = qm
	mm.instance_count = 140
	for i in 140:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf_range(-8, 8), rng.randf_range(0.0, 4.0), rng.randf_range(-18, 3))))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-20, -5, -30), Vector3(40, 20, 40))
	var tm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TEILCHEN_SHADER
	tm.shader = sh
	mmi.material_override = tm
	welt.add_child(mmi)
	_n["teilchen"] = tm
	_n["tiefe"] = _licht(Vector3(0, 2.5, -14), Color(0.35, 0.55, 1.0), 2.0, 22.0, 3.0)
	_spot(Vector3(-3, 6, 4), Vector3(0, 1, -6), Color(0.7, 0.8, 1.0), 4.0, 40.0)


func _ps2_t(t: float) -> void:
	for s: Array in _n.saeulen:
		var mi: MeshInstance3D = s[0]
		var h: float = s[1]
		var k := _ein((t - float(s[2])) / 0.8)
		mi.visible = k > 0.002
		mi.scale = Vector3(1, maxf(k, 0.002), 1)
		mi.position.y = h * k * 0.5
	var m: ShaderMaterial = _n.teilchen
	m.set_shader_parameter("zeit", t)
	m.set_shader_parameter("staerke", _ein(t / 0.5))
	var hoch := exp(-pow((t - HOEHEPUNKT) / 0.35, 2.0))
	(_n.tiefe as OmniLight3D).light_energy = 1.2 + 4.0 * hoch + 1.5 * _ein(t / 1.2)
	env.volumetric_fog_density = 0.03 + 0.02 * hoch
	var k := _io(t / DAUER)
	_kamera(Vector3(0, lerpf(0.9, 1.5, k), lerpf(6.0, 1.5, k)), Vector3(0, lerpf(1.4, 2.0, k), -10))


# --- GameCube -------------------------------------------------------------------------------

func _gc() -> void:
	env.background_color = Color(0.012, 0.006, 0.025)
	env.ambient_light_color = Color(0.15, 0.1, 0.25)
	env.volumetric_fog_albedo = Color(0.6, 0.45, 0.9)
	_boden(Color(0.012, 0.008, 0.02), 0.0, 10.0)
	var lack := _stoff(Color(0.28, 0.14, 0.62), 0.25, 0.22, 0.0, 1.0)
	var wuerfel := Node3D.new()
	welt.add_child(wuerfel)
	var teile: Array = []
	for i in 8:
		var d := Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1)
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.47
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = lack
		mi.position = d * 0.25
		wuerfel.add_child(mi)
		teile.append([mi, d])
	var kern := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3.ONE * 0.5
	kern.mesh = km
	var kl := _stoff(Color(0.75, 0.6, 1.0), 0.0, 1.0, 0.0)
	kl.emission_enabled = true
	kl.emission = Color(0.75, 0.6, 1.0)
	kern.material_override = kl
	wuerfel.add_child(kern)
	_n["wuerfel"] = wuerfel
	_n["teile"] = teile
	_n["kern"] = kl
	_n["kern_l"] = _licht(Vector3(0, 0.5, 0), Color(0.75, 0.6, 1.0), 0.0, 3.0, 4.0)
	_spot(Vector3(-3, 5, 4), Vector3(0, 0.4, 0), Color(1.0, 0.97, 1.0), 6.0, 35.0)
	_spot(Vector3(3, 3, -4), Vector3(0, 0.4, 0), Color(0.7, 0.75, 1.0), 8.0, 30.0)


func _gc_t(t: float) -> void:
	# Drei Kipper (je 0,3 s) von x = −3 bis 0, jeweils um die vordere untere Kante.
	var w: Node3D = _n.wuerfel
	var pos := Vector3(-3, 0.5, 0)
	var dreh := 0.0
	for k in 3:
		var p := _io((t - 0.2 - k * 0.3) / 0.3)
		if p <= 0.0:
			break
		var x0 := -3.0 + k
		var a := -PI * 0.5 * p
		var drehpunkt := Vector3(x0 + 0.5, 0, 0)
		var r := Vector2(-0.5, 0.5).rotated(a)
		pos = drehpunkt + Vector3(r.x, r.y, 0)
		dreh = a
	w.position = pos
	w.rotation = Vector3(0, 0, dreh)
	# Aufgehen: kurz auseinander, Licht aus den Fugen, wieder zu.
	var auf := sin(PI * clampf((t - 1.15) / 0.6, 0.0, 1.0))
	for tl: Array in _n.teile:
		(tl[0] as MeshInstance3D).position = (tl[1] as Vector3) * (0.25 + 0.12 * auf)
	(_n.kern as StandardMaterial3D).emission_energy_multiplier = 0.2 + 5.0 * auf
	(_n.kern_l as OmniLight3D).light_energy = 3.0 * auf
	var k := _io(t / DAUER)
	_kamera(Vector3(lerpf(2.6, 1.5, k), lerpf(1.9, 1.4, k), lerpf(4.8, 3.8, k)), Vector3(lerpf(-1.2, 0.0, _io(t / 1.2)), 0.05, 0))


# --- PlayStation ----------------------------------------------------------------------------

func _ps1() -> void:
	env.background_color = Color(0, 0, 0)
	env.ambient_light_color = Color(0.3, 0.29, 0.27)
	env.volumetric_fog_albedo = Color(1.0, 0.98, 0.95)
	env.volumetric_fog_density = 0.015
	var platte := _stoff(Color(0.06, 0.06, 0.065), 0.6, 0.35)
	for s in [-1.0, 1.0]:
		var bm := BoxMesh.new()
		bm.size = Vector3(8, 10, 0.25)
		_n["platte%d" % int(s)] = _koerper(bm, platte, Vector3(s * 4.0, 0, 0))
	var licht := _stoff(Color(1, 1, 1), 0.0, 1.0)
	licht.emission_enabled = true
	licht.emission = Color(1, 1, 1)
	licht.emission_energy_multiplier = 3.0
	var qm := QuadMesh.new()
	qm.size = Vector2(60, 30)
	_koerper(qm, licht, Vector3(0, 0, -6))
	_n["licht"] = licht
	_n["raum"] = _licht(Vector3(0, 1, -2), Color(1, 0.98, 0.95), 6.0, 14.0, 2.0)
	var bm2 := StandardMaterial3D.new()
	bm2.albedo_color = Color(0.62, 0.6, 0.57)
	bm2.roughness = 0.9
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	_n["boden"] = _koerper(pm, bm2, Vector3(0, -1.6, -3))


func _ps1_t(t: float) -> void:
	var spalt := _io((t - 0.15) / 0.6)
	for s in [-1, 1]:
		(_n["platte%d" % s] as MeshInstance3D).position.x = s * (4.0 + 0.04 + 5.0 * pow(spalt, 1.6))
	# Reines Weiß, dann ein ruhiges, warmes Grau.
	var grau := _io((t - 0.9) / 0.8)
	var m: StandardMaterial3D = _n.licht
	m.emission = Color(1, 1, 1).lerp(Color(0.66, 0.64, 0.6), grau)
	m.emission_energy_multiplier = lerpf(4.0, 1.0, grau) * _ein(t / 0.3)
	(_n.raum as OmniLight3D).light_energy = (6.0 - 3.0 * grau) * spalt
	(_n.boden as MeshInstance3D).visible = grau > 0.0
	var k := _io((t - 0.4) / 1.4)
	_kamera(Vector3(0, lerpf(0.0, 0.4, k), lerpf(6.0, -1.5, k)), Vector3(0, lerpf(0.0, -0.2, k), -6))


# --- Nintendo 64 ----------------------------------------------------------------------------

func _n64() -> void:
	env.background_color = Color(0.01, 0.02, 0.07)
	env.ambient_light_color = Color(0.2, 0.25, 0.45)
	env.volumetric_fog_albedo = Color(0.25, 0.4, 1.0)
	env.volumetric_fog_density = 0.03
	_boden(Color(0.01, 0.015, 0.05), -1.0, 14.0)
	var formen: Array = []
	var kugel := SphereMesh.new()
	kugel.radius = 0.42
	kugel.height = 0.84
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.66
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.46
	var spitze := CylinderMesh.new()
	spitze.top_radius = 0.0
	spitze.bottom_radius = 0.44
	spitze.height = 0.85
	var farben := [Color(0.9, 0.12, 0.12), Color(0.1, 0.65, 0.25), Color(0.98, 0.75, 0.1), Color(0.15, 0.35, 0.95)]
	var meshes := [kugel, box, ring, spitze]
	for i in 4:
		var mi := _koerper(meshes[i], _stoff(farben[i], 0.0, 0.32, 0.0, 0.6))
		formen.append(mi)
	_n["formen"] = formen
	_spot(Vector3(-3, 4, 5), Vector3(0, 0.3, 0), Color(1, 0.98, 0.95), 7.0, 40.0)
	_spot(Vector3(3, 2, -4), Vector3(0, 0.3, 0), Color(0.6, 0.75, 1.0), 9.0, 35.0)
	_n["blitz"] = _licht(Vector3(0, 0.6, 2.0), Color(1, 1, 1), 0.0, 8.0, 2.0)


func _n64_t(t: float) -> void:
	var formen: Array = _n.formen
	for i in 4:
		var mi: MeshInstance3D = formen[i]
		var k := _ein((t - 0.1 - i * 0.12) / 0.9)
		var ziel := Vector3(-2.1 + i * 1.4, 0.35, 0)
		var von := Vector3((i - 1.5) * 5.0, 2.5 - i, -18)
		var wip := sin(TAU * 2.0 * maxf(t - 1.2, 0.0) + i * 1.3) * 0.08 * _ein((t - 1.1) / 0.3)
		mi.position = von.lerp(ziel, k) + Vector3(0, wip, 0)
		var spin := (1.0 - k) * 9.0
		mi.rotation = Vector3(0.4 + spin * 0.6, 0.6 * t + spin, spin * 0.3)
	(_n.blitz as OmniLight3D).light_energy = 6.0 * exp(-pow((t - HOEHEPUNKT) / 0.2, 2.0))
	var k2 := _io(t / DAUER)
	_kamera(Vector3(0, lerpf(1.1, 0.8, k2), lerpf(7.5, 6.2, k2)), Vector3(0, 0.25, 0))


# --- Switch ---------------------------------------------------------------------------------

func _switch() -> void:
	env.background_color = Color(0.01, 0.01, 0.014)
	env.ambient_light_color = Color(0.25, 0.25, 0.3)
	env.volumetric_fog_albedo = Color(0.8, 0.8, 0.85)
	env.volumetric_fog_density = 0.015
	_boden(Color(0.01, 0.01, 0.014), -1.7, 10.0)
	for s in [-1, 1]:
		var c := Color(0.0, 0.6, 0.95) if s < 0 else Color(1.0, 0.27, 0.27)
		var bm := BoxMesh.new()
		bm.size = Vector3(1.1, 3.0, 0.32)
		var mi := _koerper(bm, _stoff(c, 0.1, 0.28, 0.5, 0.8))
		_n["teil%d" % s] = mi
		_n["schein%d" % s] = _licht(Vector3.ZERO, c, 0.0, 3.0, 3.0)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.96
	tm.outer_radius = 1.0
	var rm := _stoff(Color(1, 1, 1), 0.0, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(1, 1, 1)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring := _koerper(tm, rm, Vector3(0, 0, 0.3))
	ring.rotation = Vector3(PI * 0.5, 0, 0)
	_n["ring"] = ring
	_n["ring_m"] = rm
	_n["klick"] = _licht(Vector3(0, 0, 1.5), Color(1, 1, 1), 0.0, 8.0, 3.0)
	_spot(Vector3(-2.5, 4, 5), Vector3.ZERO, Color(1, 1, 1), 5.0, 40.0)


func _switch_t(t: float) -> void:
	const KLICK := 0.95
	var k := clampf((t - 0.15) / (KLICK - 0.15), 0.0, 1.0)
	k = k * k * (2.0 - k)
	for s in [-1, 1]:
		var mi: MeshInstance3D = _n["teil%d" % s]
		mi.position = Vector3(s * lerpf(5.5, 0.56, k), 0, 0)
		(_n["schein%d" % s] as OmniLight3D).position = mi.position + Vector3(0, 0, 0.6)
		(_n["schein%d" % s] as OmniLight3D).light_energy = 1.2 * k
	var nach := maxf(t - KLICK, 0.0)
	var schlag := exp(-nach / 0.12) if t >= KLICK else 0.0
	(_n.klick as OmniLight3D).light_energy = 10.0 * schlag
	var ring: MeshInstance3D = _n.ring
	var rk := clampf(nach / 0.7, 0.0, 1.0)
	ring.visible = t >= KLICK and rk < 1.0
	ring.scale = Vector3.ONE * lerpf(0.6, 4.0, _ein(rk))
	var rm: StandardMaterial3D = _n.ring_m
	rm.albedo_color = Color(1, 1, 1, 1.0 - rk)
	rm.emission_energy_multiplier = 3.0 * (1.0 - rk)
	_kamera(Vector3(0, 0.2, lerpf(7.5, 6.8, _io(t / DAUER))), Vector3(0, 0.1, 0))

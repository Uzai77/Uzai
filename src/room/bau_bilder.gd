extends Node
## Vorschaubilder des Bau-Menüs (katalog_ui.gd): Möbel und Oberflächen (Wand, Boden, Decke) werden
## einmal auf einer kleinen, eigenen Bühne gerendert – mit den echten Bausteinen und Shadern des
## Zimmers (moebel.gd, wand.gdshader, boden.gdshader) – und für die Sitzung gemerkt. Eins nach dem
## anderen, zwei Bilder je Auftrag, die Bühne gibt es nur, solange etwas wartet. Gemerkt werden
## höchstens MAX Bilder; zuerst fällt, was am längsten nicht gebraucht wurde.
##
## Schlüssel: „m|<möbel>|<variante>“, „w|<material>|<muster>|<farbe>|<musterfarbe>“,
## „b|<art>|<farbe>|<zweite>“, „d|<art>|<farbe>“. Aufträge sind reine Daten mit festen Kennungen.

signal fertig(schluessel: String)

const Moebel := preload("res://src/room/moebel.gd")
const Katalog := preload("res://src/room/katalog.gd")
const S := preload("res://src/room/stoffe.gd")
const G := preload("res://src/room/gestalt.gd")
const Raum := preload("res://src/room/raum.gd")

const BILD := 256                 ## Kantenlänge in Bildpunkten (Kachel ≈ 128, doppelt für 4K)
const MAX := 160

static var _bilder := {}          ## Schlüssel → Texture2D
static var _schatten := {}        ## Schlüssel → Rect2: Bodenschatten eines Möbels in Anteilen des Bildes
static var _reihe: Array = []     ## zuletzt gebraucht hinten

var _warte: Array = []            ## [Schlüssel, Auftrag]
var _laeuft := false
var _buehne: SubViewport
var _cam: Camera3D
var _haupt: DirectionalLight3D    ## Hauptlicht: für Oberflächen streifend (zeigt Putz, Fugen, Holz)


static func moebel_schluessel(id: String, v: String) -> String:
	return "m|%s|%s" % [id, v]


static func wand_schluessel(m: String, mu: String, f: String, mf: String) -> String:
	return "w|%s|%s|%s|%s" % [m, mu, f, mf]


static func boden_schluessel(a: String, f: String, f2: String) -> String:
	return "b|%s|%s|%s" % [a, f, f2]


static func decke_schluessel(a: String, f: String) -> String:
	return "d|%s|%s" % [a, f]


## Fertiges Bild (null: noch nicht da).
func bild(schluessel: String) -> Texture2D:
	var t: Texture2D = _bilder.get(schluessel)
	if t != null and (_reihe.is_empty() or _reihe.back() != schluessel):
		_reihe.erase(schluessel)
		_reihe.append(schluessel)
	return t


static func hat(schluessel: String) -> bool:
	return _bilder.has(schluessel)


static func schatten(schluessel: String) -> Rect2:
	return _schatten.get(schluessel, Rect2())


## Bild bestellen (schon da oder bestellt: nichts). vorn: vor allen anderen.
func anfordern(schluessel: String, vorn := false) -> void:
	if _bilder.has(schluessel):
		return
	for w in _warte:
		if str(w) == schluessel:
			return
	if vorn:
		_warte.push_front(schluessel)
	else:
		_warte.append(schluessel)
	if not _laeuft:
		_abarbeiten()


## Nur noch diese Bilder rendern (ein anderer Bereich ist gewählt: was dort wartete, fällt weg).
func nur_noch(schluessel: Array) -> void:
	_warte = _warte.filter(func(s: String) -> bool: return s in schluessel)


## Bilder vergessen, deren Schlüssel so beginnt (eigenes Möbel geändert).
static func vergessen(praefix: String) -> void:
	for s in _bilder.keys():
		if str(s).begins_with(praefix):
			_bilder.erase(s)
			_schatten.erase(s)
			_reihe.erase(s)


func _abarbeiten() -> void:
	_laeuft = true
	_buehne_bauen()
	while not _warte.is_empty() and is_inside_tree():
		var schluessel: String = _warte.pop_front()
		_haupt.rotation_degrees = Vector3(-42, 28, 0)
		var n := _bauen(schluessel)
		if not is_instance_valid(n):
			continue
		_buehne.add_child(n)
		_buehne.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			break
		var img := _buehne.get_texture().get_image()
		n.queue_free()
		if img:
			img.generate_mipmaps()
			_merken(schluessel, ImageTexture.create_from_image(img))
			fertig.emit(schluessel)
	_laeuft = false
	if is_instance_valid(_buehne):
		_buehne.queue_free()
		_buehne = null
		_haupt = null


static func _merken(schluessel: String, t: Texture2D) -> void:
	_bilder[schluessel] = t
	_reihe.erase(schluessel)
	_reihe.append(schluessel)
	while _reihe.size() > MAX:
		var alt: String = _reihe.pop_front()
		_bilder.erase(alt)
		_schatten.erase(alt)


## Das Motiv eines Auftrags auf die Bühne, Kamera ausgerichtet.
func _bauen(schluessel: String) -> Node3D:
	var t := schluessel.split("|")
	match t[0]:
		"m":
			if t.size() < 3 or not Katalog.has(t[1]):
				return null
			return _moebel(schluessel, t[1], t[2])
		"w":
			if t.size() < 5:
				return null
			return _wand(t[1], t[2], t[3], t[4])
		"b":
			if t.size() < 4:
				return null
			return _boden(t[1], t[2], t[3])
		"d":
			if t.size() < 3:
				return null
			return _decke(t[1], t[2])
	return null


func _moebel(schluessel: String, id: String, v: String) -> Node3D:
	var n := Moebel.bauen(id, v if Katalog.variante_gueltig(id, v) else Katalog.std_variante(id), true)
	if not is_instance_valid(n):
		return null
	# Lichtscheine addieren Licht und schreiben dabei volle Deckkraft: ohne sie bleibt der
	# Hintergrund durchsichtig (sonst stünden Lampen vor schwarzen Kästen).
	_ohne_schein(n)
	var box := _box(n)
	var mitte := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.15)
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 0.92
	var dir := Vector3(0.62, 0.48, 1.0).normalized()
	_cam.look_at_from_position(mitte + dir * dist, mitte, Vector3.UP)
	# Bodenschatten: die Grundfläche, wie die Kamera sie sieht (nicht für Wand und Decke).
	if Katalog.ebene(id) in ["boden", "klein", "teppich"]:
		var p0 := box.position
		var ecken := [p0, p0 + Vector3(box.size.x, 0, 0), p0 + Vector3(0, 0, box.size.z), p0 + Vector3(box.size.x, 0, box.size.z)]
		var r2 := Rect2()
		for i in ecken.size():
			var q := _projektion(ecken[i])
			r2 = Rect2(q, Vector2.ZERO) if i == 0 else r2.expand(q)
		_schatten[schluessel] = r2
	return n


## Punkt auf der Bühne → Anteil im Bild (0 … 1).
func _projektion(p: Vector3) -> Vector2:
	var t := _cam.global_transform if _cam.is_inside_tree() else _cam.transform
	var lokal := t.affine_inverse() * p
	if lokal.z >= -0.001:
		return Vector2(0.5, 0.5)
	var f := 0.5 / tan(deg_to_rad(_cam.fov * 0.5))
	return Vector2(0.5 + lokal.x / -lokal.z * f, 0.5 - lokal.y / -lokal.z * f)


## Ein Stück Wand (1,2 m, um die Paneelkante herum) mit dem Shader des Zimmers.
func _wand(m: String, mu: String, f: String, mf: String) -> Node3D:
	var art: int = Raum.WAND_ARTEN.get(m, 0)
	var mat := ShaderMaterial.new()
	mat.shader = Raum.WAND_S
	mat.set_shader_parameter("raum", Vector2(100, 100))
	mat.set_shader_parameter("hoehe", Raum.HOEHE)
	mat.set_shader_parameter("eigen_ao", 0.0)
	mat.set_shader_parameter("art", art)
	S.textur_setzen(mat, str(Raum.WAND_TEXTUR.get(art, "putz")))
	mat.set_shader_parameter("muster", G.muster_nr(mu) if art == 2 else 0)
	var fc := Color(f) if G.farbe(f) != "" else Color("#e8e0d1")
	# Musterfarbe wie im Zimmer (raum.gd setze_gestalt): leer heißt passend zur Farbe.
	var mfc := Color(mf) if G.farbe(mf) != "" else (Color("#76866a") if art == 3 else (fc.darkened(0.22) if fc.get_luminance() > 0.4 else fc.lightened(0.3)))
	mat.set_shader_parameter("farbe", fc)
	mat.set_shader_parameter("muster_farbe", mfc)
	mat.set_shader_parameter("paneel_farbe", mfc)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.0, 3.0)
	q.mesh = qm
	q.material_override = mat
	var n := Node3D.new()
	n.add_child(q)
	var ziel := Vector3(50.0, 1.05, 0.0)
	q.position = ziel
	# Gut 0,8 m Wand um die Paneelkante, Licht schräg von links oben (Relief sichtbar).
	_cam.look_at_from_position(ziel + Vector3(-0.2, 0.12, 1.5), ziel + Vector3(-0.03, 0, 0), Vector3.UP)
	_haupt.rotation_degrees = Vector3(-38, -58, 0)
	return n


## Ein Stück Boden, schräg von oben.
func _boden(a: String, f: String, f2: String) -> Node3D:
	var ba: Array = Raum.BODEN_ARTEN.get(a, Raum.BODEN_ARTEN.dielen)
	var mat := ShaderMaterial.new()
	mat.shader = Raum.BODEN_S
	mat.set_shader_parameter("raum", Vector2(100, 100))
	mat.set_shader_parameter("eigen_ao", 0.0)
	mat.set_shader_parameter("art", int(ba[0]))
	S.textur_setzen(mat, str(Raum.BODEN_TEXTUR.get(int(ba[0]), "dielen")))
	mat.set_shader_parameter("diele", float(ba[1]))
	mat.set_shader_parameter("glanz", float(ba[2]))
	var bf := Color(f) if G.farbe(f) != "" else Color(str(G.BODEN_STD.get(a, "#c29466")))
	mat.set_shader_parameter("hell", bf)
	mat.set_shader_parameter("dunkel", bf.darkened(float(ba[3])))
	mat.set_shader_parameter("zweit", Color(f2) if G.farbe(f2) != "" else Color(str(G.BODEN_STD2.get(a, "#d2c9bc"))))
	return _flaeche(mat)


## Decke: Putz oder Holz (Balken und Stuck zeichnet die Kachel darüber).
func _decke(a: String, f: String) -> Node3D:
	var mat := ShaderMaterial.new()
	mat.shader = Raum.WAND_S
	mat.set_shader_parameter("raum", Vector2(100, 100))
	mat.set_shader_parameter("hoehe", 200.0)
	mat.set_shader_parameter("eigen_ao", 0.0)
	mat.set_shader_parameter("art", 4 if a == "holz" else 0)
	S.textur_setzen(mat, "holz_hell" if a == "holz" else "putz", 0.6 if a == "holz" else 1.0)
	mat.set_shader_parameter("farbe", Color(f) if G.farbe(f) != "" else Color("#efebe4"))
	return _flaeche(mat)


func _flaeche(mat: ShaderMaterial) -> Node3D:
	var p := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.0, 5.0)
	p.mesh = pm
	p.material_override = mat
	var n := Node3D.new()
	n.add_child(p)
	var ziel := Vector3(50.0, 0.0, 50.0)
	p.position = ziel
	_cam.look_at_from_position(ziel + Vector3(-0.28, 1.35, 1.05), ziel, Vector3.UP)
	_haupt.rotation_degrees = Vector3(-34, -50, 0)
	return n


static func _ohne_schein(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).material_override
			if m is ShaderMaterial and (m as ShaderMaterial).shader == Moebel.SCHEIN_S:
				(c as MeshInstance3D).visible = false
		_ohne_schein(c)


## Kleine Fotobühne: warmes Hauptlicht von vorn links oben, kühles Fülllicht, ein Kantenlicht von
## hinten (hebt die Umrisse vom dunklen Grund ab).
func _buehne_bauen() -> void:
	if _buehne:
		return
	_buehne = SubViewport.new()
	_buehne.size = Vector2i(BILD, BILD)
	_buehne.own_world_3d = true
	_buehne.transparent_bg = true
	_buehne.msaa_3d = Viewport.MSAA_4X
	_buehne.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_buehne)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f2e6d6")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	_buehne.add_child(we)
	for l in [[Vector3(-42, 28, 0), 1.3, "#fff1de"], [Vector3(-15, -140, 0), 0.45, "#dfe6f2"], [Vector3(-28, 160, 0), 0.7, "#ffe9cf"]]:
		var licht := DirectionalLight3D.new()
		licht.rotation_degrees = l[0]
		licht.light_energy = float(l[1])
		licht.light_color = Color(str(l[2]))
		_buehne.add_child(licht)
		if not is_instance_valid(_haupt):
			_haupt = licht
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_buehne.add_child(_cam)


static func _box(n: Node3D) -> AABB:
	var out := AABB()
	var erst := true
	var stapel: Array = [[n, Transform3D()]]
	while not stapel.is_empty():
		var e: Array = stapel.pop_back()
		for c in (e[0] as Node).get_children():
			if c is Node3D:
				var t: Transform3D = (e[1] as Transform3D) * (c as Node3D).transform
				if c is MeshInstance3D and (c as MeshInstance3D).mesh and (c as MeshInstance3D).visible:
					var b := t * (c as MeshInstance3D).get_aabb()
					out = b if erst else out.merge(b)
					erst = false
				stapel.append([c, t])
	return out

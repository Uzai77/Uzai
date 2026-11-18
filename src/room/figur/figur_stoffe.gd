extends RefCounted
## Materialien für das Haustier (Fell mit Gesicht, Stoff, Glanz, Gold). Die Figur selbst trägt die
## Textur ihres Modells (figur_psx.gd). Gleiche Materialien gibt es nur einmal.

const HAUT_S := preload("res://src/room/figur/shaders/haut.gdshader")
const KLEID_S := preload("res://src/room/figur/shaders/kleid.gdshader")

const MUSTER_NR := { "uni": 0, "streifen": 1, "karo": 2, "punkte": 3, "band": 4, "sterne": 5, "pixel": 6 }

static var _cache := {}


static func _hol(key: String, bau: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = bau.call()
	return _cache[key]


## Fell eines Haustiers (eigenes Material je Teil-Art, damit Bauch und Streifen je Teil passen).
static func fell(grund: Color, zweit: Color, muster: int, achse := Vector3(0, -1, 0.35), ab := 0.3, streifen := Vector3(0, 0, 1)) -> ShaderMaterial:
	var key := "fell:%s:%s:%d:%s:%.2f:%s" % [grund.to_html(), zweit.to_html(), muster, str(achse), ab, str(streifen)]
	return _hol(key, func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = HAUT_S
		m.set_shader_parameter("grund", grund)
		m.set_shader_parameter("zweit", zweit)
		m.set_shader_parameter("fell", 1)
		m.set_shader_parameter("muster", muster)
		m.set_shader_parameter("bauch_achse", achse)
		m.set_shader_parameter("bauch_ab", ab)
		m.set_shader_parameter("streifen_achse", streifen)
		return m) as ShaderMaterial


static func kleid(farbe: Color, muster := "uni", muster_farbe := Color.WHITE, schimmer := 0.3, rauheit := 0.9) -> ShaderMaterial:
	var key := "kleid:%s:%s:%s:%.2f:%.2f" % [farbe.to_html(), muster, muster_farbe.to_html(), schimmer, rauheit]
	return _hol(key, func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = KLEID_S
		m.set_shader_parameter("farbe", farbe)
		m.set_shader_parameter("muster", int(MUSTER_NR.get(muster, 0)))
		m.set_shader_parameter("muster_farbe", muster_farbe)
		m.set_shader_parameter("schimmer", schimmer)
		m.set_shader_parameter("rauheit", rauheit)
		return m) as ShaderMaterial


static func glanz(c: Color, rauheit := 0.35) -> StandardMaterial3D:
	return _hol("glanz:%s:%.2f" % [c.to_html(), rauheit], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rauheit
		m.metallic_specular = 0.6
		m.vertex_color_use_as_albedo = true
		return m) as StandardMaterial3D


static func gold() -> StandardMaterial3D:
	return _hol("gold", func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#e2b45c")
		m.metallic = 0.6
		m.metallic_specular = 0.9
		m.roughness = 0.24
		m.rim_enabled = true
		m.rim = 0.3
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m) as StandardMaterial3D

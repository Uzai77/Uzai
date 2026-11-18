extends RefCounted
## Materialien des Zimmers: ein einheitlicher, warmer Stil aus wenigen eigenen Shadern (Holz,
## Stoff, Wand, Boden) und schlichten Standard-Materialien (Lack, Metall, Glas, Keramik). Farben
## sind auf Wohnlichkeit abgestimmt: gedeckt, warm, nie grell. Gleiche Materialien gibt es nur
## einmal (Zwischenspeicher), das hält die Zahl der Wechsel beim Zeichnen klein.

const STOFF_S := preload("res://src/room/shaders/stoff.gdshader")
const GLIMMEN_S := preload("res://src/room/shaders/glimmen.gdshader")
const HUELLE_S := preload("res://src/room/shaders/huelle.gdshader")
const POKAL_S := preload("res://src/room/shaders/pokal.gdshader")
const STEIN_S := preload("res://src/room/shaders/stein.gdshader")
const G := preload("res://src/room/gestalt.gd")

const STOFF_FARBEN := {
	"salbei": Color("#87977a"), "senf": Color("#c4913c"), "terrakotta": Color("#b0603c"),
	"nachtblau": Color("#34425e"), "creme": Color("#e4d9c6"), "graphit": Color("#4b4d52"),
}
## Holz: [hell, dunkel, Rauheit, Lack]
const HOLZ_FARBEN := {
	"eiche": [Color("#c9a173"), Color("#a3774b"), 0.5, 0.45],
	"walnuss": [Color("#7d5538"), Color("#4e3221"), 0.42, 0.5],
	"weiss": [Color("#efebe4"), Color("#e2dcd2"), 0.38, 0.5],
	"schwarz": [Color("#2e2b29"), Color("#1d1b1a"), 0.36, 0.55],
	"kirsche": [Color("#b06a43"), Color("#7d412a"), 0.44, 0.5],
	"esche": [Color("#e3d0ae"), Color("#c2a77e"), 0.5, 0.4],
	"raeuchereiche": [Color("#6a4f3b"), Color("#3f2d22"), 0.46, 0.45],
}

static var _cache := {}

## Karten der Oberflächen (assets/zimmer/tex, Herkunft in assets/zimmer/LIZENZ.txt): Name → Maß einer
## Kachel in Metern (x, y), Mittelwert der Farbkarte, Mittelwert der Rauheit, Stärke der Normalkarte,
## ob die Farbkarte Farbe trägt (sonst nur Helligkeit). Gleich benannte Dateien: <name>_farbe.jpg,
## <name>_normal.jpg, <name>_rau.jpg (ohne Farbkarte: weiß).
const TEXTUREN := {
	"dielen": [Vector2(2.0, 1.0), Color(0.401, 0.276, 0.145), 0.284, 1.0, true],
	"marmor": [Vector2(1.2, 1.2), Color(0.098, 0.099, 0.1), 0.097, 0.7, false],
	"fliesen": [Vector2(0.9, 0.9), Color(0.815, 0.815, 0.815), 0.295, 1.0, false],
	"messing": [Vector2(0.5, 0.5), Color(0.773, 0.593, 0.311), 0.159, 0.8, true],
	"putz": [Vector2(1.4, 1.4), Color(0.837, 0.837, 0.837), 0.855, 1.0, false],
	"beton": [Vector2(2.2, 2.2), Color(0.613, 0.613, 0.613), 0.713, 1.0, false],
	"stoff": [Vector2(0.22, 0.22), Color(0.766, 0.766, 0.766), 0.899, 1.0, false],
	"leinen": [Vector2(0.3, 0.3), Color(0.768, 0.768, 0.768), 0.918, 1.0, false],
	"cord": [Vector2(0.24, 0.24), Color(0.768, 0.768, 0.768), 0.881, 1.0, false],
	"teppich": [Vector2(1.3, 1.3), Color(0.727, 0.727, 0.727), 0.928, 1.0, false],
	"leder": [Vector2(0.5, 0.5), Color(0.728, 0.728, 0.728), 0.602, 1.0, false],
	"holz_eiche": [Vector2(1.0, 1.0), Color(0.693, 0.528, 0.355), 0.482, 1.0, true],
	"holz_walnuss": [Vector2(1.0, 1.0), Color(0.361, 0.238, 0.161), 0.481, 1.0, true],
	"holz_hell": [Vector2(1.0, 1.0), Color(0.84, 0.757, 0.614), 0.473, 1.0, true],
	"lack": [Vector2(0.6, 0.6), Color(0.98, 0.98, 0.98), 0.34, 0.35, false],
	"metall_buerste": [Vector2(0.4, 0.4), Color(0.817, 0.817, 0.817), 0.357, 1.0, false],
	"kunststoff": [Vector2(0.3, 0.3), Color(0.97, 0.97, 0.97), 0.553, 1.0, false],
	"haut": [Vector2(0.3, 0.3), Color(1.0, 1.0, 1.0), 0.537, 1.0, false],
}
static var _tex := {}
const KARTEN_ARTEN := ["farbe", "normal", "rau"]


## Eine Karte laden (einmal je Sitzung); fehlt sie, null (die Shader haben dann weiß bzw. flach).
static func textur(name: String, art: String) -> Texture2D:
	# Nur Namen aus der festen Liste TEXTUREN und drei Karten-Arten, alles unter res://assets/zimmer/tex.
	if not TEXTUREN.has(name) or not art in KARTEN_ARTEN:
		return null
	var key := name + ":" + art
	if not _tex.has(key):
		var pfad := _karten_pfad(name, art)
		_tex[key] = load(pfad) if ResourceLoader.exists(pfad) else null
	return _tex[key]


static func _karten_pfad(name: String, art: String) -> String:
	return "res://assets/zimmer/tex/%s_%s.jpg" % [name, art]


## Die Karten, die in dieser Sitzung gebraucht wurden („holz_eiche:farbe“ …), sortiert: fürs Vorladen beim
## nächsten Mal (zimmer_welt.gd vorlade_pfade).
static func karten_gebraucht() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _tex:
		if _tex[k] != null:
			out.append(k)
	out.sort()
	return out


## Zu gemerkten Namen die Dateien. Nur Namen aus TEXTUREN mit einer der drei Arten; alles andere fällt weg.
static func karten_pfade(namen: Array) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in namen:
		if not v is String or (v as String).length() > 48:
			continue
		var name := (v as String).get_slice(":", 0)
		var art := (v as String).get_slice(":", 1)
		if not TEXTUREN.has(name) or not art in KARTEN_ARTEN:
			continue
		var pfad := _karten_pfad(name, art)
		if ResourceLoader.exists(pfad) and not out.has(pfad):
			out.append(pfad)
	return out


## Karten eines Satzes auf ein Hüllen-Material (wand.gdshader, boden.gdshader) legen.
static func textur_setzen(m: ShaderMaterial, name: String, mass_faktor := 1.0) -> void:
	var t: Array = TEXTUREN.get(name, TEXTUREN.putz)
	m.set_shader_parameter("t_farbe", textur(name, "farbe"))
	m.set_shader_parameter("t_normal", textur(name, "normal"))
	m.set_shader_parameter("t_rau", textur(name, "rau"))
	m.set_shader_parameter("t_mass", (t[0] as Vector2) * mass_faktor)
	m.set_shader_parameter("t_mittel", t[1])
	m.set_shader_parameter("t_rau_mittel", float(t[2]))
	m.set_shader_parameter("t_staerke", float(t[3]))
	m.set_shader_parameter("t_farbe_an", 1.0 if bool(t[4]) else 0.0)


## Standard-Material mit Karten (Möbel): Farbe tönt die Karte um ihren Mittelwert, Normal- und
## Rauheitskarte dazu, dreiseitig auf das Möbel gelegt (wandert mit ihm, keine UV nötig).
static func textur_material(name: String, farbe: Color, rauheit_faktor := 1.0, mass_faktor := 1.0, metallisch := 0.0) -> StandardMaterial3D:
	var t: Array = TEXTUREN.get(name, TEXTUREN.putz)
	var m := StandardMaterial3D.new()
	var tf := textur(name, "farbe")
	var mittel: Color = t[1]
	if tf != null and bool(t[4]):
		m.albedo_texture = tf
		m.albedo_color = Color(farbe.r / maxf(mittel.r, 0.02), farbe.g / maxf(mittel.g, 0.02), farbe.b / maxf(mittel.b, 0.02)).clamp(Color(0, 0, 0), Color(2, 2, 2))
	elif tf != null:
		m.albedo_texture = tf
		m.albedo_color = farbe / maxf(mittel.r, 0.02)
	else:
		m.albedo_color = farbe
	var tn := textur(name, "normal")
	if tn != null:
		m.normal_enabled = true
		m.normal_texture = tn
		m.normal_scale = float(t[3])
	var tr := textur(name, "rau")
	m.roughness = clampf(rauheit_faktor, 0.0, 1.0)
	if tr != null:
		m.roughness_texture = tr
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallisch
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / maxf((t[0] as Vector2).x * mass_faktor, 0.01)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.vertex_color_use_as_albedo = true
	return m


static func _hol(key: String, bau: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = bau.call()
	return _cache[key]


## Welche Furnier-Karte ein Holz bekommt (TEXTUREN); lackierte Hölzer tragen die Lack-Karte.
const HOLZ_KARTE := { "eiche": "holz_eiche", "walnuss": "holz_walnuss", "weiss": "lack", "schwarz": "lack", "kirsche": "holz_eiche",
	"esche": "holz_hell", "raeuchereiche": "holz_walnuss" }


## Holz in einer Katalog-Variante: Furnier-Karte (Albedo, Normal, Rauheit), dreiseitig aufs Möbel
## gelegt; achse bleibt für alte Aufrufe (die Karte liegt ohnehin in allen drei Richtungen).
static func holz(variante: String, achse := 0) -> Material:
	return _hol("holz:%s:%d" % [variante, achse], func() -> Material:
		var f: Array = HOLZ_FARBEN.get(variante, HOLZ_FARBEN.eiche)
		var karte := str(HOLZ_KARTE.get(variante, "holz_eiche"))
		var mittel := (f[0] as Color).lerp(f[1], 0.45)
		var m := textur_material(karte, mittel if karte != "lack" else (f[0] as Color), float(f[2]) * (1.1 if karte != "lack" else 0.95), 1.0)
		m.metallic_specular = float(f[3]) * 0.75
		return m)


## Holz in eigenen Farben (gebeizt oder frei gewählt): die Karte wird in den Mittelton gebeizt.
static func holz_farbig(hell: Color, dunkel: Color, rauheit: float, lack_: float, achse := 0, maserung := 7.0) -> Material:
	return _hol("holzf:%s:%s:%.2f:%.2f:%d:%.1f" % [hell.to_html(), dunkel.to_html(), rauheit, lack_, achse, maserung], func() -> Material:
		var karte := "lack" if maserung < 3.0 else ("holz_walnuss" if hell.get_luminance() < 0.3 else "holz_eiche")
		var m := textur_material(karte, hell.lerp(dunkel, 0.45) if karte != "lack" else hell, rauheit * 1.1, 1.0)
		m.metallic_specular = lack_ * 0.75
		return m)


## Jede Oberfläche aus dem Anpassen (gestalt.gd): Material-Kennung, Farbe („“ = natürliche Farbe
## des Materials), Muster (nur Stoffe) mit Musterfarbe („“ = passend abgeleitet). Holz wird mit
## einer Farbe gebeizt (Maserung bleibt), alles andere bekommt die Farbe direkt.
static func oberflaeche(mat: String, f: String, achse := 0, muster := "", mf := "") -> Material:
	var art := G.material_art(mat)
	var c := Color(f) if f != "" else Color(G.material_farbe(mat))
	match art:
		"holz":
			var b: Array = HOLZ_FARBEN.get(mat, HOLZ_FARBEN.eiche)
			var hell: Color = b[0]
			var dunkel: Color = b[1]
			if f != "":
				hell = hell.lerp(c, 0.78)
				dunkel = dunkel.lerp(c.darkened(0.32), 0.78)
			return holz_farbig(hell, dunkel, float(b[2]), float(b[3]), achse, 1.5 if mat in ["weiss", "schwarz"] else 7.0)
		"lack":
			return lack(c, 0.62 if mat == "lack_matt" else 0.1, 0.35 if mat == "lack_matt" else 0.8)
		"metall":
			# Nicht ganz metallisch: ohne Spiegelbild der Umgebung (Kompatibilitäts-Renderer) würde
			# blankes Metall fast schwarz wirken; der Glanz kommt über Specular und Rim.
			return _metall_mat(c, { "metall": 0.5, "stahl": 0.3, "chrom": 0.12, "messing": 0.26, "kupfer": 0.28 }.get(mat, 0.3), 0.3 if mat == "metall" else 0.6)
		"stoff", "leder":
			if mat == "leder":
				return _hol("leder:%s" % c.to_html(), func() -> Material:
					var m := textur_material("leder", c, 0.58, 1.0)
					m.metallic_specular = 0.55
					return m)
			var mc := Color(mf) if mf != "" else (c.darkened(0.32) if c.get_luminance() > 0.45 else c.lightened(0.42))
			var w: float = { "samt": 320.0, "cord": 60.0, "boucle": 55.0, "leinen": 180.0, "leder": 30.0 }.get(mat, 140.0)
			var fl: float = { "boucle": 1.0, "samt": 0.2 }.get(mat, 0.0)
			var sch: float = { "samt": 0.75, "leder": 0.12, "leinen": 0.18 }.get(mat, 0.32)
			var gl: float = { "leder": 0.65, "samt": 0.15 }.get(mat, 0.0)
			var mu := G.muster_nr(muster)
			if mat == "cord" and mu == 0:
				mu = 2
				mc = c.darkened(0.18)
			return stoff_voll(c, w, fl, sch, gl, mu, mc)
		"stein", "rattan":
			var nr: int = { "marmor": 0, "beton": 1, "terrazzo": 2, "rattan": 3 }.get(mat, 0)
			return _hol("stein:%s:%d" % [c.to_html(), nr], func() -> Material:
				var m := ShaderMaterial.new()
				m.shader = STEIN_S
				m.set_shader_parameter("farbe", c)
				m.set_shader_parameter("zweit", c.darkened(0.5) if nr != 2 else Color("#b0603c"))
				m.set_shader_parameter("art", nr)
				return m)
	return lack(c)


static func stoff_voll(c: Color, webung: float, flor: float, schimmer: float, glanz: float, muster: int, mc: Color) -> Material:
	return _hol("stoffv:%s:%.0f:%.2f:%.2f:%.2f:%d:%s" % [c.to_html(), webung, flor, schimmer, glanz, muster, mc.to_html()], func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = STOFF_S
		m.set_shader_parameter("farbe", c)
		m.set_shader_parameter("webung", webung)
		m.set_shader_parameter("flor", flor)
		m.set_shader_parameter("schimmer", schimmer)
		m.set_shader_parameter("glanz", glanz)
		m.set_shader_parameter("muster", muster)
		m.set_shader_parameter("muster_farbe", mc)
		_stoff_karte(m, webung, flor, glanz)
		return m)


## Normal- und Rauheitskarte eines Stoffs nach Webung: Teppichflor, grobes Leinen, Cord, feiner
## Webstoff; Leder (glanz hoch) bekommt die Lederkarte.
static func _stoff_karte(m: ShaderMaterial, webung: float, flor: float, glanz: float) -> void:
	var name := "stoff"
	if glanz > 0.5:
		name = "leder"
	elif flor > 0.5:
		name = "teppich"
	elif webung < 70.0:
		name = "cord"
	elif webung < 120.0:
		name = "leinen"
	var t: Array = TEXTUREN.get(name, TEXTUREN.stoff)
	m.set_shader_parameter("t_normal", textur(name, "normal"))
	m.set_shader_parameter("t_rau", textur(name, "rau"))
	m.set_shader_parameter("t_mass", (t[0] as Vector2).x)
	m.set_shader_parameter("t_rau_mittel", float(t[2]))


static func _metall_mat(c: Color, rauheit: float, metallisch: float) -> Material:
	return _hol("metall2:%s:%.2f:%.2f" % [c.to_html(), rauheit, metallisch], func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallisch
		m.metallic_specular = 0.85
		m.roughness = rauheit
		m.rim_enabled = metallisch > 0.5
		m.rim = 0.3
		m.rim_tint = 0.8
		m.vertex_color_use_as_albedo = true
		return m)


static func stoff_farbe(variante: String) -> Color:
	return STOFF_FARBEN.get(variante, STOFF_FARBEN.creme)


static func stoff(variante: String, webung := 140.0, flor := 0.0) -> Material:
	return stoff_farbig(stoff_farbe(variante), webung, flor)


static func stoff_farbig(c: Color, webung := 140.0, flor := 0.0) -> Material:
	return _hol("stoff:%s:%.0f:%.2f" % [c.to_html(), webung, flor], func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = STOFF_S
		m.set_shader_parameter("farbe", c)
		m.set_shader_parameter("webung", webung)
		m.set_shader_parameter("flor", flor)
		_stoff_karte(m, webung, flor, 0.0)
		return m)


## Lampenschirm: Stoff, der von innen leuchtet, solange die Lampe an ist (eigenes Material je
## Lampe, weil an/aus je Lampe gilt).
static func schirm(variante: String, farbe := Color(0, 0, 0, 0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STOFF_S
	m.set_shader_parameter("farbe", farbe if farbe.a > 0.0 else stoff_farbe(variante))
	m.set_shader_parameter("webung", 90.0)
	m.set_shader_parameter("schimmer", 0.15)
	_stoff_karte(m, 90.0, 0.0, 0.0)
	return m


## Glatte, lackierte Fläche (Kunststoff, Lack, Keramik). Glanz gedämpft und nie spiegelglatt:
## stilisiert, ohne harte Plastik-Glanzpunkte.
static func lack(c: Color, rauheit := 0.4, glanz := 0.5) -> Material:
	return _hol("lack:%s:%.2f:%.2f" % [c.to_html(), rauheit, glanz], func() -> Material:
		# Lack und Kunststoff: Orangenhaut als Normalkarte, Rauheit leicht unruhig – kein Plastik-Glanzpunkt.
		var m := textur_material("kunststoff" if rauheit >= 0.5 else "lack", c, clampf(rauheit * 1.05, 0.08, 1.0), 1.0)
		m.metallic_specular = glanz * 0.7
		return m)


static func metall(c: Color, rauheit := 0.3) -> Material:
	return _hol("metall:%s:%.2f" % [c.to_html(), rauheit], func() -> Material:
		# Forward+ spiegelt den Raum (Sonde, SSR): echtes Metall mit Bürstung. Kompatibilität hat
		# kein Spiegelbild – dort halb metallisch, sonst stünde es schwarz da.
		var forward := RenderingServer.get_current_rendering_method() != "gl_compatibility"
		var m := textur_material("metall_buerste", c, clampf(rauheit * 1.1, 0.05, 1.0), 1.0, 1.0 if forward else 0.45)
		m.metallic_specular = 0.85
		return m)


## Metall für Pokale: gespiegelte Umgebung als günstiger Fake (shaders/pokal.gdshader, wie eine
## Matcap) – der Kompatibilitäts-Renderer hat keine Reflexionen im Raum. Die Stärke folgt dem
## Licht im Zimmer (pokale_umgebung).
static func pokal_metall(c: Color, rauheit := 0.2) -> Material:
	return _hol("pokal:%s:%.2f" % [c.to_html(), rauheit], func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = POKAL_S
		m.set_shader_parameter("farbe", c)
		m.set_shader_parameter("rauheit", rauheit)
		return m)


## Wie hell die gespiegelte Umgebung der Pokale ist (0 dunkel … 1 hell), dazu ihre Farben.
static func pokale_umgebung(staerke: float, oben: Color, fenster: Color, boden: Color) -> void:
	for k: String in _cache:
		if k.begins_with("pokal:"):
			var m := _cache[k] as ShaderMaterial
			m.set_shader_parameter("umgebung", staerke)
			m.set_shader_parameter("oben_farbe", oben)
			m.set_shader_parameter("fenster_farbe", fenster)
			m.set_shader_parameter("boden_farbe", boden)


static func glas(tint := Color(0.85, 0.9, 0.92, 0.12)) -> Material:
	return _hol("glas:%s" % tint.to_html(), func() -> Material:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = tint
		m.roughness = 0.04
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)


## Leuchtet selbst (Glühbirne, Lämpchen, Bildschirm-Rand); energie nach Tageszeit von außen.
static func leuchte(c: Color, energie := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energie
	m.roughness = 0.4
	return m


## Blätter: beidseitig, matt, mit Farbverlauf der Eckpunkte (zur Spitze heller).
static func blatt(c: Color) -> Material:
	return _hol("blatt:%s" % c.to_html(), func() -> Material:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.42
		m.metallic_specular = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		return m)


## Glimmen der Auswahl (ein Material für alle; Stärke wird angeglichen).
static func glimmen() -> ShaderMaterial:
	return _hol("glimmen", func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = GLIMMEN_S
		m.set_shader_parameter("farbe", Color("#e7c27d"))
		return m) as ShaderMaterial


static func huelle() -> Material:
	return _hol("huelle", func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = HUELLE_S
		return m)


## Farbe einer Spielhülle: Farbe des Systems (wie die Ersatz-Cover), je Spiel leicht anders.
static func huellen_farbe(g: Dictionary) -> Color:
	var sid := str(g.get("system", ""))
	var c := Color("#2b2d33")
	var sys: Dictionary = Config.system(sid) if sid != "" else {}
	if not sys.is_empty():
		c = Color(str(sys.get("color", "#2a2f3d")))
	elif sid == "steam":
		c = Color("#1b2838")
	elif sid == "epic":
		c = Color("#26282c")
	elif sid == "ea":
		c = Color("#3a1d24")
	elif Library.Stores.is_extra(sid):
		c = Color(Library.Stores.color_of(sid))
	var h := float(absi(str(g.get("title", "")).hash()) % 1000) / 1000.0
	return c.lerp(c.lightened(0.22) if h > 0.5 else c.darkened(0.2), absf(h - 0.5) * 0.9)

extends RefCounted
## Baut die Möbel des Zimmers aus eigenen Formen (formen.gd) und Materialien (stoffe.gd), dazu
## einige echte Möbel aus freien Modellen (MODELLE, CC0 / CC BY 4.0, assets/zimmer/modelle/
## LIZENZ.txt) – ohne Etiketten, keine Marken. Ursprung: Mitte der Grundfläche auf dem
## Boden, Vorderseite nach +z. Im Lowboard stehen die Konsolen der eingerichteten Systeme
## (konsolen.gd, nachempfunden, ohne Logos); ohne Systeme die eigene Fantasie-Konsole mit dem
## goldenen Spielerpunkt aus Uzais Startbild (R4).
##
## Am fertigen Möbel hängen als Meta, was das Zimmer braucht:
##   blick   { pos, ziel }  Kamera zum Ansehen (im Möbel-Raum)
##   sitz    { pos, ziel }  Augenhöhe beim Hinsetzen
##   lampen  [{ licht, energie, reichweite, schirme, birnen, schein }]  zum Ein- und Ausschalten
##   faecher [{ pos, breite, tiefe, hoehe }]  Plätze für Hüllen, Pokale und Platten
##   bildschirm (MeshInstance3D), schlitz (Node3D, Fantasie-Konsole), konsolen { System: Knoten },
##   platte/teller/tonarm/tonarm_hub/huelle/etikett_bild/ps_led (Plattenspieler), uhr
##
## Anpassen (gestalt.gd): bauen_it liest Farbe, Material und Muster des Hauptteils (_m) und des
## Gestells (_g), die Größenstufe, Beine (_beine), Griffe (_griff) und baut eigene Möbel aus dem
## Baukasten (_eigen). Ohne Anpassung sieht jedes Möbel genau aus wie im Katalog.

const Katalog := preload("res://src/room/katalog.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const BILDSCHIRM_S := preload("res://src/room/shaders/bildschirm.gdshader")
const MoebelFigur := preload("res://src/room/figur/moebel_figur.gd")
const SCHEIN_S := preload("res://src/room/shaders/schein.gdshader")
const MODELL_STOFF_S := preload("res://src/room/shaders/modell_stoff.gdshader")
const Licht := preload("res://src/room/licht.gd")
const G := preload("res://src/room/gestalt.gd")
const Konsolen := preload("res://src/room/konsolen.gd")
const Mehr := preload("res://src/room/moebel_mehr.gd")

const WARM := Color(1.0, 0.76, 0.52)       ## Glühlampe, etwa 2700 K
const MESSING := Color("#b8925a")
const DUNKEL := Color("#232427")
const GOLD := Color("#e7c27d")
## Lampenschirme liegen auf einer eigenen Ebene, die die Lampen selbst nicht beleuchten: Sonst
## strahlt die Glühlampe die Innenseite aus nächster Nähe grell weiß an. Der Schirm leuchtet dann
## nur aus sich heraus (warm, je nach Tageszeit), Sonne und Umgebung wirken weiter.
const SCHIRM_EBENE := 2
## Wände, Decke, Boden und Teppiche (raum.gd HUELLE_EBENE): Lampen leuchten sie im Shader an
## (lichter.gdshaderinc) – mit Form (Lichtkegel des Schirms) und ohne eigenen Zeichendurchgang.
const HUELLE_EBENE := 4

## Material des Gestells, wenn nur eine Farbe gewählt ist (sonst Lack).
const GESTELL_MAT := { "lautsprecher": "stoff", "teppich": "stoff", "teppich_rund": "stoff", "stehlampe": "messing",
	"beistelltisch": "walnuss", "bild": "eiche", "bett": "eiche", "schlafsofa": "eiche", "papierlampe": "eiche", "deckenfluter": "messing",
	"laeufer": "stoff", "bilderwand": "schwarz", "vorhang": "metall", "satztisch": "metall", "gamingtisch": "metall" }

static var _bilder := {}
static var _it := {}            ## das Möbel, das gerade gebaut wird (seine Anpassungen)
## Systeme, deren Konsolen im Lowboard stehen (zimmer_welt.gd setzt sie vor dem Bau der Medienwand;
## leer: die eigene Fantasie-Konsole wie bisher).
static var konsolen: Array = []


static func bauen(id: String, v: String, an := true) -> Node3D:
	return bauen_it({ "t": id, "v": v, "an": an })


## Ein Möbel aus seinen Daten (zimmer_daten.gd) samt aller Anpassungen.
static func bauen_it(it: Dictionary) -> Node3D:
	_it = it
	var id := str(it.get("t", ""))
	var v := str(it.get("v", ""))
	var an := bool(it.get("an", true))
	var root := Node3D.new()
	root.name = id
	var g := Katalog.groesse_it({ "t": id, "s": it.get("s"), "r": 0 })
	var w := float(g.x) * Katalog.ZELLE
	var d := float(g.y) * Katalog.ZELLE
	var st := Katalog.stufe_von(it)
	if Katalog.ist_eigen(id):
		_eigen(root, Katalog.eigen(id))
	match id:
		"sofa": _sofa(root, v, w - 0.04, false)
		"sessel": _sofa(root, v, 0.92, true)
		"sitzsack": _sitzsack(root, v)
		"hocker": _hocker(root, v)
		"couchtisch": _couchtisch(root, v, w - 0.2)
		"beistelltisch": _beistelltisch(root, v)
		"schreibtisch": _schreibtisch(root, v, w - 0.08)
		"kommode": _kommode(root, v, w - 0.04)
		"spieleregal": _regal(root, v, Katalog.hoehe_it(it), 3 if st in [0, 3] else 5, true, w - 0.04)
		"buecherregal": _regal(root, v, minf(1.6, Katalog.hoehe_it(it)) if st in [1, 2] else Katalog.hoehe_it(it), 3 if st in [0, 3] else 4, false, w - 0.04)
		"trophaeenschrank": _vitrine(root, v, w - 0.1)
		"plattenregal": _plattenregal(root, v, 2 if st == 1 else 1, 2 if st == 2 else 1)
		"medienwand": _medienwand(root, v)
		"lautsprecher": _lautsprecher(root, v)
		"plattenspieler": _plattenspieler(root, v)
		"stehlampe": _stehlampe(root, v)
		"tischlampe": _tischlampe(root, v)
		"deckenlampe": _deckenlampe(root, v)
		"lichterkette": _lichterkette(root, v, w)
		"led_leiste": _led_leiste(root, v, w)
		"pflanze": _pflanze(root, v, [0.68, 1.0, 1.38][st])
		"topfpflanze": _pflanze(root, v, 0.32)
		"teppich": _teppich(root, v, w, d, false)
		"teppich_rund": _teppich(root, v, w, d, true)
		"bild": _bild(root, v, w)
		"wanduhr": _uhr(root, v)
		"buecher": _buecher(root, v)
		"jackenstaender", "tierkorb", "lavalampe", "neonschild": MoebelFigur.bauen(root, id, v)
		"gamingstuhl": _gamingstuhl(root, v)
		"monitor": _monitor(root, v)
		"rechner": _rechner(root, v)
		"regallautsprecher": _regallautsprecher(root, v)
		"kissen": _kissen(root, v)
		"decke": _decke(root, v)
		"poster": _poster(root, v)
		"minikuehlschrank": _minikuehlschrank(root, v)
		"snackschale": _snackschale(root, v)
		"figuren": _figuren(root, v)
		_:
			if MODELLE.has(id):
				_modell(root, id, v, w, d)
			else:
				Mehr.bauen(root, id, v, w, d, st)    # weitere Möbel (moebel_mehr.gd)
	_it = {}
	schalten(root, an)
	return root


# --- Anpassungen ------------------------------------------------------------------------------------

static func _angepasst(felder: Array) -> bool:
	for k in felder:
		if str(_it.get(k, "")) != "":
			return true
	return false


## Material des Hauptteils (Bezug, Korpus): std ohne Anpassung, sonst aus Material, Farbe, Muster.
static func _m(std: Material, achse := 0) -> Material:
	if not _angepasst(["m", "f", "mu"]):
		return std
	return S.oberflaeche(_haupt_id(), str(_it.get("f", "")) if _it.has("f") else _variante_farbe(), achse, str(_it.get("mu", "")), str(_it.get("mf", "")))


## Material des Gestells (Beine, Rahmen, Fuß, Topf …).
static func _g(std: Material, achse := 1) -> Material:
	if not _angepasst(["m2", "f2"]):
		return std
	var mat := str(_it.get("m2", ""))
	if mat == "":
		mat = str(GESTELL_MAT.get(str(_it.get("t", "")), "lack_matt"))
	return S.oberflaeche(mat, str(_it.get("f2", "")), achse)


## Kennung des Hauptmaterials: gewählt, sonst nach Art der Katalog-Varianten (Stoff oder Holz).
static func _haupt_id() -> String:
	var m := str(_it.get("m", ""))
	if m != "":
		return m
	var t := str(_it.get("t", ""))
	var vs := Katalog.varianten(t)
	if vs == Katalog.STOFFE:
		return "stoff"
	if vs == Katalog.HOELZER:
		return str(_it.get("v", "eiche"))
	return { "medienwand": "walnuss", "pflanze": "lack_matt", "topfpflanze": "lack_matt" }.get(t, "lack_matt")


## Farbe der Katalog-Variante (Stoffe), damit „nur Muster“ die bisherige Farbe behält.
static func _variante_farbe() -> String:
	var t := str(_it.get("t", ""))
	if Katalog.varianten(t) == Katalog.STOFFE and str(_it.get("m", "")) in ["", "stoff", "samt", "cord", "boucle", "leinen"]:
		return "#" + S.stoff_farbe(str(_it.get("v", ""))).to_html(false)
	return ""


## Farbe für Schirme, Bücher und Teppiche: gewählt oder die der Variante.
static func _farbe(std: Color) -> Color:
	return Color(str(_it.f)) if str(_it.get("f", "")) != "" else std


## Beine an den Stellen (x, z), Höhe h: Holz konisch (Standard), Haarnadel, Metall rund, Kufen
## oder ein zurückgesetzter Sockel über die ganze Fläche.
static func _beine(root: Node3D, stellen: Array, h: float, std: Material, r := 0.022) -> void:
	var art := str(_it.get("be", ""))
	match art:
		"haarnadel":
			var mat := _g(S.metall(Color("#1d1d1f"), 0.45))
			for p: Vector2 in stellen:
				for s: int in [-1, 1]:
					var mi := _teil(root, F.walze(0.0045, h * 1.02, 0.001, 8), mat, Vector3(p.x, 0, p.y))
					mi.rotation = Vector3(0.0, 0.0, s * 0.14)
		"rund":
			var mat2 := _g(S.metall(Color("#c9cacc"), 0.2))
			for p: Vector2 in stellen:
				_teil(root, F.walze(r * 0.75, h, 0.003, 14), mat2, Vector3(p.x, 0, p.y))
		"kufen":
			var mat3 := _g(S.metall(Color("#26262a"), 0.4))
			var xs := {}
			for p: Vector2 in stellen:
				xs[snappedf(p.x, 0.01)] = true
			var zs: Array = stellen.map(func(q: Vector2) -> float: return q.y)
			var z0: float = zs.min()
			var z1: float = zs.max()
			for x: float in xs.keys():
				_steht(root, Vector3(0.03, 0.02, z1 - z0 + 0.08), mat3, x, 0, (z0 + z1) * 0.5, 0.008)
				for z: float in [z0, z1]:
					_steht(root, Vector3(0.03, h, 0.03), mat3, x, 0.0, z, 0.008)
		"sockel":
			var x0 := 0.0
			var x1 := 0.0
			var zz0 := 0.0
			var zz1 := 0.0
			for p: Vector2 in stellen:
				x0 = minf(x0, p.x)
				x1 = maxf(x1, p.x)
				zz0 = minf(zz0, p.y)
				zz1 = maxf(zz1, p.y)
			_steht(root, Vector3(x1 - x0 + r * 2.0, h + 0.004, zz1 - zz0 + r * 2.0), _g(S.lack(Color("#232427"), 0.6, 0.3)), (x0 + x1) * 0.5, 0, (zz0 + zz1) * 0.5,
					0.006)
		_:
			var mat4 := _g(std)
			for p: Vector2 in stellen:
				_bein(root, mat4, p.x, p.y, h, r)


## Griff einer Schublade oder Tür an pos (Vorderseite +z), breite: Breite der Front.
static func _griff(root: Node3D, pos: Vector3, breite: float, senkrecht := false) -> void:
	var std := S.metall(MESSING, 0.3)
	match str(_it.get("gr", "")):
		"buegel":
			var m := _g(std) if _angepasst(["m2", "f2"]) else std
			var l := minf(0.12, breite * 0.4)
			var g := Vector3(0.012, l, 0.012) if senkrecht else Vector3(l, 0.012, 0.012)
			_kiste(root, g, m, pos + Vector3(0, 0, 0.022), 0.005, false)
			for s: int in [-1, 1]:
				var o := Vector3(0, s * l * 0.42, 0.01) if senkrecht else Vector3(s * l * 0.42, 0, 0.01)
				_kiste(root, Vector3(0.008, 0.008, 0.022), m, pos + o, 0.003, false)
		"leiste":
			var m2 := _g(S.metall(Color("#2b2c30"), 0.4)) if _angepasst(["m2", "f2"]) else S.metall(Color("#2b2c30"), 0.4)
			var g2 := Vector3(0.014, minf(0.5, breite * 0.7), 0.018) if senkrecht else Vector3(minf(0.5, breite * 0.7), 0.014, 0.018)
			_kiste(root, g2, m2, pos + Vector3(0, 0, 0.008), 0.004, false)
		"keine":
			pass
		_:
			_teil(root, F.walze(0.012, 0.02, 0.004, 12), std, pos + Vector3(0, 0, 0.002), Vector3(90, 0, 0))


# --- Bausteine -----------------------------------------------------------------------------------

## Teile mit demselben Material (und gleichem Aufbau der Netze, gleicher Ebene) zu einem Netz
## zusammenfassen: ein Zeichenaufruf statt vieler (Lamellen, Knöpfe, Strahlen, Fransen). Was sich
## bewegt (Meta „wiegen“, Uhrzeiger) oder Kinder hat, bleibt einzeln; Kleinteile unter
## zimmer_welt.gd SCHATTEN_KLEIN bleiben unter sich und werfen keinen Schatten.
static func buendeln(root: Node3D) -> void:
	var fest := {}
	for e: Array in root.get_meta("wiegen", []):
		fest[e[0]] = true
	var gruppen := {}
	for c in root.get_children():
		if not (c is MeshInstance3D) or fest.has(c) or c.get_child_count() > 0:
			continue
		var mi := c as MeshInstance3D
		if mi.material_override == null or not (mi.mesh is ArrayMesh) or mi.mesh.get_surface_count() != 1:
			continue
		var gr := mi.get_aabb().size * mi.transform.basis.get_scale()
		var klein := maxf(gr.x, maxf(gr.y, gr.z)) < 0.16
		var key := "%d|%d|%d|%d|%s" % [mi.material_override.get_instance_id(), mi.mesh.surface_get_format(0), mi.layers, mi.cast_shadow, klein]
		if not gruppen.has(key):
			gruppen[key] = []
		(gruppen[key] as Array).append(mi)
	for key: String in gruppen:
		var liste: Array = gruppen[key]
		if liste.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi: MeshInstance3D in liste:
			st.append_from(mi.mesh, 0, mi.transform)
		var neu := MeshInstance3D.new()
		neu.mesh = st.commit()
		var erst: MeshInstance3D = liste[0]
		neu.material_override = erst.material_override
		neu.layers = erst.layers
		neu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key.ends_with("true") else erst.cast_shadow
		for mi: MeshInstance3D in liste:
			root.remove_child(mi)
			mi.free()
		root.add_child(neu)


static func _teil(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, skal := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = skal
	root.add_child(mi)
	return mi


## Kiste: bis 4 mm Radius eine gerade Fase (Holz, Metall, Kunststoff), darüber rund (Polster).
## Alte Aufrufe mit den früheren „weichen“ 1,2–1,8 cm für Bretter sind auf Fasen gedeckelt (_fase).
static func _kiste(root: Node3D, groesse: Vector3, mat: Material, mitte: Vector3, rad := 0.0025, ao := true, rot := Vector3.ZERO) -> MeshInstance3D:
	return _teil(root, F.kiste(groesse, _fase(rad), ao), mat, mitte, rot)


## Kantenradius wie am echten Möbel: die früheren „weichen“ Bretter (0,5–2 cm) bekommen eine Fase
## von 3 mm; echte Rundungen (Polster, Kissen, Gehäuse ab 2 cm) bleiben.
static func _fase(rad: float) -> float:
	return 0.003 if rad > 0.004 and rad <= 0.02 else rad


## Kiste, deren Unterkante auf y steht.
static func _steht(root: Node3D, groesse: Vector3, mat: Material, x: float, y: float, z: float, rad := 0.0025) -> MeshInstance3D:
	return _kiste(root, groesse, mat, Vector3(x, y + groesse.y * 0.5, z), rad)


## Weicher Kontaktschatten unter dem Möbel: nur vermerkt (Mitte, Größe, Stärke, rund, Weichheit);
## die Welt zeichnet alle zusammen in eine Schattenkarte des Bodens (zimmer_welt.gd). So wirken sie
## auch unter Teppichen und im Kompatibilitäts-Renderer ohne durchsichtige Flächen.
static func _schatten(root: Node3D, groesse: Vector2, staerke := 0.5, rund := false, weich := 0.18, mitte := Vector3.ZERO) -> void:
	if mitte.y > 0.01:
		return
	var liste: Array = root.get_meta("schatten", [])
	liste.append([mitte, groesse, minf(0.85, staerke * 1.25), rund, weich])
	root.set_meta("schatten", liste)


static func _bein(root: Node3D, mat: Material, x: float, z: float, h: float, r := 0.022) -> void:
	# Leicht verjüngt: unten schmaler als oben.
	var u := PackedVector2Array([Vector2(0, 0), Vector2(r * 0.7, 0), Vector2(r, h), Vector2(0, h)])
	_teil(root, F.dreh(u, 14, [1, 2]), mat, Vector3(x, 0, z))


## Eine Lampe: echtes Licht (ohne Schatten) nur für die Möbel; Wände, Boden und Decke rechnet
## lichter.gdshaderinc. schein: [[Ort, Größe], …] für die Lichtscheine (shaders/schein.gdshader).
static func _lampe(root: Node3D, pos: Vector3, energie: float, reichweite: float, schirme: Array, birnen: Array, schein: Array = []) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = WARM
	l.light_energy = energie
	l.omni_range = reichweite
	l.omni_attenuation = 1.5     # wie uz_abfall in shaders/lichter.gdshaderinc
	l.shadow_enabled = false
	l.shadow_blur = 1.0
	l.light_specular = 0.25 if not Licht.renderer_jetzt() == "forward" else 0.6
	# Forward+: echte Lichter treffen auch Wände, Boden und Decke (viele Lichter kosten dort wenig);
	# Kompatibilität rechnet die Hülle im Shader (lichter.gdshaderinc), darum ohne HUELLE_EBENE.
	l.light_cull_mask = (0xFFFFF & ~SCHIRM_EBENE) if Licht.renderer_jetzt() == "forward" else (0xFFFFF & ~SCHIRM_EBENE & ~HUELLE_EBENE)
	root.add_child(l)
	var lampen: Array = root.get_meta("lampen", [])
	lampen.append({ "licht": l, "energie": energie, "weite": reichweite, "schirme": schirme, "birnen": birnen, "schein": _schein(root, schein) })
	root.set_meta("lampen", lampen)
	return l


## Lichtscheine einer Lampe als ein Netz: je Schein ein Viereck, alle Ecken in der Mitte (der
## Shader zieht sie zur Kamera hin auf). null ohne Scheine.
static func _schein(root: Node3D, punkte: Array) -> ShaderMaterial:
	if punkte.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := AABB()
	for p in punkte:
		var m: Vector3 = p[0]
		var r: float = p[1]
		var b := AABB(m - Vector3.ONE * r * 1.5, Vector3.ONE * r * 3.0)
		box = b if box.size == Vector3.ZERO else box.merge(b)
		for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_uv(e)
			st.set_uv2(Vector2(r, 0))
			st.add_vertex(m)
	var mesh := st.commit()
	mesh.custom_aabb = box
	var mat := ShaderMaterial.new()
	mat.shader = SCHEIN_S
	mat.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mat


## Lampen eines Möbels schalten (Licht, leuchtender Schirm, Birnen, Lichtschein): an/aus, faktor
## nach Tageszeit, farbe des Lichts, hell (0 … 2) und weit (Reichweite 0,5 … 2) aus dem Anpassen.
static func schalten(root: Node3D, an: bool, faktor := 1.0, farbe := WARM, hell := 1.0, weit := 1.0) -> void:
	for l in root.get_meta("lampen", []):
		var licht: OmniLight3D = l.licht
		var bunt := bool(l.get("bunt", false))
		licht.visible = an and hell > 0.001
		licht.light_energy = float(l.energie) * faktor * hell
		licht.omni_range = float(l.get("weite", licht.omni_range)) * weit
		if not bunt:
			licht.light_color = farbe
		var glut := minf(hell, 1.35)
		# Forward+: der Schirm leuchtet etwas dezenter (Glühen und Belichtung kommen dazu; früher auch das
		# indirekte Licht der SDFGI – ohne sie wirkte er bei 0,45 matt).
		var schirm_glut := 0.75 if Licht.renderer_jetzt() == "forward" else 0.85
		for s in l.schirme:
			(s as ShaderMaterial).set_shader_parameter("leuchten", schirm_glut * faktor * glut if an else 0.0)
			(s as ShaderMaterial).set_shader_parameter("licht", Color(1.0, 0.72, 0.42).lerp(farbe, 0.85) if farbe != WARM else Color(1.0, 0.72, 0.42))
		for b in l.birnen:
			var bm := b as StandardMaterial3D
			bm.emission_energy_multiplier = 3.5 * maxf(faktor, 0.4) * glut if an else 0.0
			if not bunt:
				bm.emission = farbe
				bm.albedo_color = farbe.lerp(Color.WHITE, 0.4)
		var sm: ShaderMaterial = l.get("schein")
		if sm:
			sm.set_shader_parameter("farbe", licht.light_color)
			sm.set_shader_parameter("staerke", 0.32 * sqrt(faktor) * glut if an else 0.0)
	MoebelFigur.schalten(root, an)


static func _blick(root: Node3D, pos: Vector3, ziel: Vector3) -> void:
	root.set_meta("blick", { "pos": pos, "ziel": ziel })


# --- Sitzen --------------------------------------------------------------------------------------

static func _sofa(root: Node3D, v: String, breite: float, sessel: bool) -> void:
	var st := _m(S.stoff(v))
	var holz := S.holz("walnuss", 1)
	var tiefe := 0.9
	var hw := breite * 0.5
	var stellen: Array = []
	for x: float in [-hw + 0.08, hw - 0.08]:
		for z: float in [-tiefe * 0.5 + 0.08, tiefe * 0.5 - 0.1]:
			stellen.append(Vector2(x, z))
	_beine(root, stellen, 0.12, holz, 0.02)
	# Unterbau, Rücken, Armlehnen: weich gepolstert.
	_steht(root, Vector3(breite, 0.2, tiefe), st, 0, 0.11, 0, 0.05)
	_steht(root, Vector3(breite, 0.5, 0.2), st, 0, 0.26, -tiefe * 0.5 + 0.1, 0.07)
	for s: int in [-1, 1]:
		_steht(root, Vector3(0.17, 0.33, tiefe), st, s * (hw - 0.085), 0.26, 0, 0.075)
	var innen := breite - 0.34
	var n := 1 if sessel else (3 if breite > 2.2 else 2)
	var kb := innen / n
	for i in n:
		var x := -innen * 0.5 + kb * (i + 0.5)
		# Sitzkissen (rund und satt) und Rückenkissen (leicht nach hinten geneigt).
		_kiste(root, Vector3(kb - 0.02, 0.16, tiefe - 0.24), st, Vector3(x, 0.39, 0.1), 0.07)
		_kiste(root, Vector3(kb - 0.04, 0.42, 0.2), st, Vector3(x, 0.66, -tiefe * 0.5 + 0.27), 0.09, true, Vector3(-9, 0, 0))
	if not sessel:
		# Zwei Zierkissen in einem warmen Ton dazu: sie sitzen auf dem Sitzkissen (Oberkante 0,47 m) und
		# lehnen vor dem Rückenkissen (Vorderseite bei z ≈ −0,08, nach hinten geneigt), neben der Armlehne –
		# nur leicht gedreht, damit keine Ecke im Rückenkissen oder in der Armlehne steckt.
		var zier := S.stoff("creme" if v != "creme" else "senf")
		_kiste(root, Vector3(0.38, 0.36, 0.13), zier, Vector3(-hw + 0.4, 0.665, 0.035), 0.06, true, Vector3(-12, 8, 4))
		_kiste(root, Vector3(0.36, 0.34, 0.13), S.stoff("senf" if v != "senf" else "terrakotta"), Vector3(hw - 0.44, 0.655, 0.04), 0.06, true,
				Vector3(-12, -9, -4))
		# Eine Decke über der Armlehne (nur vorn, wo kein Rückenkissen ist), außen leicht überhängend.
		_kiste(root, Vector3(0.28, 0.035, 0.46), S.stoff("graphit" if v != "graphit" else "creme", 60.0, 0.5), Vector3(hw - 0.075, 0.612, 0.21), 0.015, true,
				Vector3(0, 0, -8))
	_schatten(root, Vector2(breite + 0.05, tiefe), 0.55)
	root.set_meta("sitz", { "pos": Vector3(0, 1.08, 0.1), "ziel": Vector3(0, 0.95, 4.0) })
	_blick(root, Vector3(0, 1.45, 2.0), Vector3(0, 0.45, 0))


static func _sitzsack(root: Node3D, v: String) -> void:
	var u := PackedVector2Array([Vector2(0, 0), Vector2(0.3, 0.005), Vector2(0.42, 0.06), Vector2(0.46, 0.2),
		Vector2(0.43, 0.36), Vector2(0.33, 0.5), Vector2(0.2, 0.57), Vector2(0.08, 0.56), Vector2(0, 0.53)])
	_teil(root, F.dreh(u, 40, [], true), _m(S.stoff(v, 70.0)), Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1.0, 1.0, 1.08))
	_schatten(root, Vector2(0.9, 0.95), 0.55, true)
	root.set_meta("sitz", { "pos": Vector3(0, 0.82, 0.05), "ziel": Vector3(0, 0.9, 4.0) })
	_blick(root, Vector3(0, 1.3, 1.5), Vector3(0, 0.3, 0))


static func _hocker(root: Node3D, v: String) -> void:
	_teil(root, F.walze(0.21, 0.42, 0.07, 32, true), _m(S.stoff(v, 90.0)), Vector3.ZERO)
	_schatten(root, Vector2(0.44, 0.44), 0.5, true)
	root.set_meta("sitz", { "pos": Vector3(0, 0.95, 0), "ziel": Vector3(0, 0.9, 4.0) })


# --- Tische und Kommode ------------------------------------------------------------------------------

static func _couchtisch(root: Node3D, v: String, b := 1.3) -> void:
	var h := _m(S.holz(v, 0))
	var t := 0.72 if b > 0.9 else 0.62
	_steht(root, Vector3(b, 0.045, t), h, 0, 0.375, 0, 0.018)
	_steht(root, Vector3(b - 0.1, 0.025, t - 0.1), h, 0, 0.11, 0, 0.01)
	var stellen: Array = []
	for x: float in [-b * 0.5 + 0.05, b * 0.5 - 0.05]:
		for z: float in [-t * 0.5 + 0.05, t * 0.5 - 0.05]:
			stellen.append(Vector2(x, z))
	if str(_it.get("be", "")) == "":
		for p: Vector2 in stellen:
			_steht(root, Vector3(0.05, 0.375, 0.05), _g(S.holz(v, 1)), p.x, 0, p.y, 0.012)
	else:
		_beine(root, stellen, 0.375, S.holz(v, 1), 0.025)
	_schatten(root, Vector2(b, t), 0.45)
	_blick(root, Vector3(0, 1.3, 1.3), Vector3(0, 0.4, 0))


static func _beistelltisch(root: Node3D, v: String) -> void:
	var h := _m(S.holz(v, 0))
	_teil(root, F.walze(0.22, 0.032, 0.012, 40), h, Vector3(0, 0.52, 0))
	_teil(root, F.walze(0.022, 0.5, 0.005, 16), _g(S.holz(v, 1)), Vector3(0, 0.02, 0))
	_teil(root, F.walze(0.15, 0.025, 0.01, 32, true), _g(h), Vector3.ZERO)
	_schatten(root, Vector2(0.42, 0.42), 0.45, true)


static func _schreibtisch(root: Node3D, v: String, b := 1.42) -> void:
	var h := _m(S.holz(v, 0))
	var hb := b * 0.5
	_steht(root, Vector3(b, 0.04, 0.72), h, 0, 0.72, 0, 0.012)
	# Rechts ein Schubladenblock, links zwei Beine.
	var bx := hb - 0.23
	_steht(root, Vector3(0.42, 0.7, 0.66), h, bx, 0.02, 0, 0.012)
	for i in 3:
		_steht(root, Vector3(0.38, 0.2, 0.012), h, bx, 0.06 + i * 0.22, 0.33, 0.006)
		_griff(root, Vector3(bx, 0.16 + i * 0.22, 0.34), 0.38)
	if str(_it.get("be", "")) == "":
		for z: float in [-0.31, 0.31]:
			_steht(root, Vector3(0.045, 0.72, 0.045), _g(S.holz(v, 1)), -hb + 0.05, 0, z, 0.01)
	else:
		_beine(root, [Vector2(-hb + 0.05, -0.31), Vector2(-hb + 0.05, 0.31)], 0.72, S.holz(v, 1), 0.022)
	# Zugeklappter Laptop und ein Becher mit Stiften.
	_steht(root, Vector3(0.36, 0.022, 0.25), S.lack(Color("#8e9196"), 0.35, 0.6), -0.15, 0.76, 0.05, 0.008)
	_teil(root, F.walze(0.04, 0.1, 0.006, 20), S.lack(Color("#d9c8ae"), 0.35), Vector3(bx - 0.03, 0.76, -0.2))
	_schatten(root, Vector2(b, 0.72), 0.45)


static func _kommode(root: Node3D, v: String, b := 0.96) -> void:
	var h := _m(S.holz(v, 0))
	_steht(root, Vector3(b, 0.7, 0.45), h, 0, 0.08, 0, 0.014)
	# Breitere Kommoden: zwei Reihen Schubladen nebeneinander.
	var spalten := 1 if b < 1.2 else 2
	var fb := (b - 0.06) / spalten
	for k in spalten:
		var x := -b * 0.5 + 0.03 + fb * (k + 0.5)
		for i in 3:
			_steht(root, Vector3(fb - 0.02, 0.205, 0.014), h, x, 0.1 + i * 0.225, 0.226, 0.006)
			_griff(root, Vector3(x, 0.2 + i * 0.225, 0.233), fb)
	var stellen: Array = []
	for x2: float in [-b * 0.5 + 0.06, b * 0.5 - 0.06]:
		for z: float in [-0.18, 0.18]:
			stellen.append(Vector2(x2, z))
	_beine(root, stellen, 0.08, S.holz(v, 1), 0.018)
	_schatten(root, Vector2(b, 0.45), 0.45)


# --- Regale ------------------------------------------------------------------------------------

static func _regal(root: Node3D, v: String, hoehe: float, boeden: int, spiele: bool, b := 0.96) -> void:
	var h := _m(S.holz(v, 1), 1)
	var hq := _m(S.holz(v, 0))
	var t := 0.36
	var dick := 0.028
	var zm := -0.25 + t * 0.5 + 0.02
	# Breite Regale: in der Mitte eine Trennwand, Fächer je Hälfte.
	var spalten := 1 if b < 1.4 else 2
	for s: int in [-1, 1]:
		_steht(root, Vector3(dick, hoehe, t), h, s * (b * 0.5 - dick * 0.5), 0, zm, 0.008)
	if spalten == 2:
		_steht(root, Vector3(dick, hoehe - dick, t), h, 0, 0, zm, 0.008)
	_steht(root, Vector3(b - 0.02, hoehe - 0.04, 0.012), _g(hq, 0) if _angepasst(["m2", "f2"]) else hq, 0, 0.02, zm - t * 0.5 + 0.008, 0.004)
	var faecher: Array = []
	var unten := 0.075
	var abstand := (hoehe - dick - unten) / boeden
	var fb := (b - dick * (spalten + 1)) / spalten
	for i in boeden:
		var y := unten + abstand * i
		for k in spalten:
			var x := -b * 0.5 + dick + fb * 0.5 + k * (fb + dick)
			_steht(root, Vector3(fb + 0.002, dick, t), hq, x, y - dick, zm, 0.006)
			faecher.append({ "pos": Vector3(x, y, zm + 0.02), "breite": fb - 0.02, "tiefe": t - 0.04, "hoehe": abstand - dick })
	# Sockelblende unten und Deckel oben.
	_steht(root, Vector3(b - dick * 2.0, unten - dick, 0.018), hq, 0, 0.0, zm + t * 0.5 - 0.012, 0.004)
	_steht(root, Vector3(b, dick, t + 0.01), hq, 0, hoehe - dick, zm, 0.008)
	root.set_meta("faecher", faecher)
	if not spiele:
		_buecher_reihen(root, faecher, v)
	_schatten(root, Vector2(b, t), 0.5, false, 0.16, Vector3(0, 0, zm))
	_blick(root, Vector3(0, hoehe * 0.55 + 0.25, 1.35), Vector3(0, hoehe * 0.5, zm))


## Bücher und ein paar Dinge in einem Bücherregal (gemischte Farben, mal stehend, mal liegend).
static func _buecher_reihen(root: Node3D, faecher: Array, v: String) -> void:
	var farben := ["#7a3b2e", "#2f4a5c", "#c49a52", "#4f5d47", "#d8ccb4", "#8a6a8f", "#3b3a3d", "#a7543a"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(v + "buecher")
	for fi in faecher.size():
		var f: Dictionary = faecher[fi]
		var x: float = -float(f.breite) * 0.5 + 0.02
		var ende: float = float(f.breite) * 0.5 - 0.02
		if fi % 2 == 1:
			ende -= 0.2
		while x < ende - 0.03:
			var bd := rng.randf_range(0.022, 0.045)
			var bh := minf(rng.randf_range(0.18, 0.26), float(f.hoehe) - 0.02)
			var bt := rng.randf_range(0.15, 0.22)
			var c := Color(farben[rng.randi() % farben.size()])
			_steht(root, Vector3(bd, bh, bt), S.stoff_farbig(c, 200.0), (f.pos as Vector3).x + x + bd * 0.5, (f.pos as Vector3).y, (f.pos as Vector3).z, 0.004)
			x += bd + 0.002
		if fi % 2 == 1:
			# Eine kleine Vase am Ende.
			var u := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0), Vector2(0.06, 0.06), Vector2(0.03, 0.15), Vector2(0.035, 0.17), Vector2(0, 0.17)])
			_teil(root, F.dreh(u, 24), S.lack(Color("#d8cdbb"), 0.25, 0.6), Vector3((f.pos as Vector3).x + ende + 0.1, (f.pos as Vector3).y, (f.pos as Vector3).z))


static func _vitrine(root: Node3D, v: String, b := 0.9) -> void:
	var h := _m(S.holz(v, 1), 1)
	var hq := _m(S.holz(v, 0))
	var t := 0.4
	var zm := -0.25 + t * 0.5 + 0.02
	# Unterschrank mit zwei Türen, darüber die Vitrine aus Glas mit Licht.
	_steht(root, Vector3(b, 0.56, t), hq, 0, 0.04, zm, 0.012)
	for s: int in [-1, 1]:
		_steht(root, Vector3(b * 0.5 - 0.02, 0.48, 0.014), hq, s * b * 0.25, 0.08, zm + t * 0.5 + 0.002, 0.006)
		if str(_it.get("gr", "")) == "":
			_teil(root, F.walze(0.008, 0.12, 0.003, 10), S.metall(MESSING, 0.3), Vector3(s * 0.035, 0.27, zm + t * 0.5 + 0.02))
		else:
			_griff(root, Vector3(s * 0.035, 0.33, zm + t * 0.5 + 0.01), 0.3, true)
	var oben := 1.84
	for s: int in [-1, 1]:
		_steht(root, Vector3(0.03, oben - 0.6, t), h, s * (b * 0.5 - 0.015), 0.6, zm, 0.008)
	_steht(root, Vector3(b, 0.04, t + 0.01), hq, 0, oben - 0.04, zm, 0.01)
	_steht(root, Vector3(b - 0.04, oben - 0.62, 0.01), S.lack(Color("#a8957c"), 0.7, 0.3), 0, 0.6, zm - t * 0.5 + 0.01, 0.003)
	var glas := S.glas()
	_steht(root, Vector3(b - 0.06, oben - 0.66, 0.006), glas, 0, 0.6, zm + t * 0.5 - 0.004, 0.002)
	var faecher: Array = []
	var spalten := 1 if b < 1.4 else 2
	if spalten == 2:
		_steht(root, Vector3(0.024, oben - 0.64, t - 0.02), h, 0, 0.6, zm, 0.006)
	var sb := (b - 0.06) / spalten
	for i in 3:
		var y := 0.6 + 0.02 + i * 0.4
		_steht(root, Vector3(b - 0.06, 0.012, t - 0.05), S.glas(Color(0.9, 0.93, 0.94, 0.28)), 0, y - 0.012, zm - 0.01, 0.003)
		for k in spalten:
			var x := -b * 0.5 + 0.03 + sb * (k + 0.5)
			faecher.append({ "pos": Vector3(x, y, zm - 0.01), "breite": sb - 0.04, "tiefe": t - 0.08, "hoehe": 0.38 })
	root.set_meta("faecher", faecher)
	# Licht in der Vitrine: warmes Band oben, das die Pokale anstrahlt.
	var band := S.leuchte(Color(1.0, 0.86, 0.66), 1.6)
	_steht(root, Vector3(b - 0.1, 0.012, 0.03), band, 0, oben - 0.06, zm + 0.08, 0.004)
	_lampe(root, Vector3(0, oben - 0.16, zm + 0.17), 0.75, 1.6, [], [band], [[Vector3(0, oben - 0.07, zm + 0.12), 0.16]])
	_schatten(root, Vector2(b, t), 0.5, false, 0.16, Vector3(0, 0, zm))
	_blick(root, Vector3(0, 1.32, 1.25), Vector3(0, 1.12, zm))


## Plattenregal aus quadratischen Fächern (je 0,44 m): breit = 2 × so breit, hoch = 2 × so hoch.
static func _plattenregal(root: Node3D, v: String, breit := 1, hoch := 1) -> void:
	var h := _m(S.holz(v, 0))
	var hs := _m(S.holz(v, 1), 1)
	var dick := 0.032
	var t := 0.4
	var spalten := 2 * breit
	var reihen := 2 * hoch
	var fb := (0.96 - dick * 3.0) * 0.5
	var b := fb * spalten + dick * (spalten + 1)
	var fh := (0.74 - dick * 3.0) * 0.5
	var hoehe := fh * reihen + dick * (reihen + 1)
	var zm := -0.25 + t * 0.5 + 0.03
	for i in spalten + 1:
		_steht(root, Vector3(dick, hoehe - dick * 2.0, t), hs, -b * 0.5 + dick * 0.5 + i * (fb + dick), dick, zm, 0.006)
	for j in reihen + 1:
		_steht(root, Vector3(b, dick, t), h, 0, j * (fh + dick), zm, 0.008)
	_steht(root, Vector3(b - 0.02, hoehe - 0.02, 0.01), h, 0, 0.01, zm - t * 0.5 + 0.006, 0.003)
	var faecher: Array = []
	for j in reihen:
		for i in spalten:
			var x := -b * 0.5 + dick + fb * 0.5 + i * (fb + dick)
			faecher.append({ "pos": Vector3(x, dick + j * (fh + dick), zm), "breite": fb, "tiefe": t - 0.03, "hoehe": fh })
	root.set_meta("faecher", faecher)
	_schatten(root, Vector2(b, t), 0.5, false, 0.16, Vector3(0, 0, zm))
	_blick(root, Vector3(0, 0.75 + hoehe * 0.4, 1.05 + 0.2 * (breit - 1)), Vector3(0, hoehe * 0.48, zm))


# --- Technik ---------------------------------------------------------------------------------------

static func _medienwand(root: Node3D, v: String) -> void:
	var h := _m(S.holz("walnuss", 0))
	var hs := _m(S.holz("walnuss", 1), 1)
	var b := 1.9
	var t := 0.42
	var zm := -0.25 + t * 0.5 + 0.02
	var stellen: Array = []
	for x: float in [-0.88, 0.88]:
		for z: float in [zm - 0.15, zm + 0.15]:
			stellen.append(Vector2(x, z))
	_beine(root, stellen, 0.1, S.holz("walnuss", 1), 0.018)
	# Unterteil: Boden, Deckplatte, links und rechts ein Schrank mit Lamellentüren, in der Mitte
	# ein offenes Fach für die Konsole. Mehr Konsolen (konsolen.gd staffeln): die Seiten werden
	# offene Fächer, dann kommen Zwischenböden dazu.
	var seite := 0.68
	var lage := Konsolen.staffeln(konsolen)
	var ebenen: Dictionary = lage.get("ebenen", {})
	# Rückwand: im offenen Lowboard warmes Holz (sonst drei schwarze Löcher), sonst wie bisher dunkel.
	var rueck := _m(S.holz("raeuchereiche", 0)) if bool(lage.get("offen", false)) else S.lack(Color("#2a2420"), 0.8, 0.2)
	_steht(root, Vector3(b, 0.03, t), h, 0, 0.1, zm, 0.01)
	_steht(root, Vector3(b, 0.032, t), h, 0, 0.488, zm, 0.012)
	for s: int in [-1, 1]:
		var tx := s * (b * 0.5 - seite * 0.5)
		if bool(lage.get("offen", false)):
			_steht(root, Vector3(0.02, 0.36, t - 0.01), h, s * (b * 0.5 - 0.01), 0.129, zm - 0.005, 0.006)
			_steht(root, Vector3(0.02, 0.36, t - 0.01), h, s * 0.28, 0.129, zm - 0.005, 0.006)
			continue
		_steht(root, Vector3(seite, 0.36, t - 0.01), h, tx, 0.129, zm - 0.005, 0.008)
		_steht(root, Vector3(seite - 0.04, 0.34, 0.016), hs, tx, 0.139, zm + t * 0.5 + 0.004, 0.006)
		for k in 9:
			_steht(root, Vector3(0.012, 0.32, 0.01), hs, tx - 0.28 + k * 0.07, 0.149, zm + t * 0.5 + 0.014, 0.003)
	var rb := b - 0.04 if bool(lage.get("offen", false)) else b - seite * 2.0
	_steht(root, Vector3(rb, 0.36, 0.014), rueck, 0, 0.129, zm - t * 0.5 + 0.012, 0.004)
	for fach: String in Konsolen.FACH_X:
		if int(ebenen.get(fach, 0)) == 2:
			var fx: Vector2 = Konsolen.FACH_X[fach]
			var hh := (Konsolen.FACH_H - Konsolen.BODEN_D) * 0.5
			_steht(root, Vector3(fx.y - fx.x + 0.012, Konsolen.BODEN_D, t - 0.03), h, (fx.x + fx.y) * 0.5, Konsolen.FACH_Y + hh, zm - 0.01, 0.003)
	if konsolen.is_empty():
		_konsole(root, Vector3(0, 0.13, zm + 0.03))
	else:
		Konsolen.einraeumen(root, lage, zm + t * 0.5 - 0.025, zm - t * 0.5 + 0.019)
	match v:
		"roehre": _roehre(root, zm)
		"beamer": _beamer(root, zm)
		_: _flach(root, zm)
	_schatten(root, Vector2(b, t), 0.5, false, 0.16, Vector3(0, 0, zm))
	_blick(root, Vector3(0, 1.22, 1.9), Vector3(0, 0.9, zm))


## Eigene Fantasie-Konsole: flacher, weich gerundeter Quader in Graphit mit Schlitz und dem
## goldenen Punkt als Betriebslicht.
static func _konsole(root: Node3D, pos: Vector3) -> void:
	var k := Node3D.new()
	k.name = "konsole"
	k.position = pos
	root.add_child(k)
	_steht(k, Vector3(0.38, 0.085, 0.27), S.lack(Color("#2b2c30"), 0.42, 0.55), 0, 0, 0, 0.03)
	_steht(k, Vector3(0.38, 0.012, 0.27), S.lack(Color("#3a3b40"), 0.3, 0.6), 0, 0.085, 0, 0.006)
	_steht(k, Vector3(0.2, 0.004, 0.012), S.lack(Color("#111214"), 0.6, 0.2), 0, 0.094, -0.02, 0.002)
	var licht := S.leuchte(GOLD, 1.4)
	_teil(k, F.walze(0.009, 0.004, 0.002, 16), licht, Vector3(0.14, 0.045, 0.136), Vector3(90, 0, 0))
	var schlitz := Node3D.new()
	schlitz.name = "schlitz"
	schlitz.position = Vector3(0, 0.1, -0.02)
	k.add_child(schlitz)
	root.set_meta("schlitz", schlitz)
	root.set_meta("konsole_licht", licht)


static func _bildschirm(root: Node3D, groesse: Vector2, pos: Vector3, art: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = groesse
	var m := ShaderMaterial.new()
	m.shader = BILDSCHIRM_S
	m.set_shader_parameter("art", art)
	# Das Bild so hell wie das Original (bildschirm.gdshader gleicht die Nachbearbeitung aus).
	m.set_shader_parameter("hell", 1.0)
	var mi := _teil(root, q, m, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("bildschirm", mi)
	return mi


static func _flach(root: Node3D, zm: float) -> void:
	var rahmen := S.lack(Color("#141518"), 0.3, 0.5)
	_steht(root, Vector3(0.32, 0.018, 0.2), rahmen, 0, 0.52, zm, 0.008)
	_steht(root, Vector3(0.05, 0.12, 0.03), rahmen, 0, 0.53, zm - 0.02, 0.008)
	_kiste(root, Vector3(1.34, 0.77, 0.035), rahmen, Vector3(0, 0.99, zm - 0.01), 0.008)
	_bildschirm(root, Vector2(1.31, 0.74), Vector3(0, 0.99, zm + 0.0081), 1)


static func _roehre(root: Node3D, zm: float) -> void:
	var gehaeuse := S.lack(Color("#cfc6b6"), 0.5, 0.4)
	var dunkel := S.lack(Color("#3a3733"), 0.55, 0.35)
	_kiste(root, Vector3(0.8, 0.62, 0.14), gehaeuse, Vector3(0, 0.84, zm + 0.12), 0.05)
	_kiste(root, Vector3(0.66, 0.52, 0.36), gehaeuse, Vector3(0, 0.8, zm - 0.08), 0.1)
	_kiste(root, Vector3(0.62, 0.48, 0.02), dunkel, Vector3(-0.06, 0.86, zm + 0.19), 0.04)
	_bildschirm(root, Vector2(0.58, 0.44), Vector3(-0.06, 0.86, zm + 0.201), 0)
	# Bedienleiste rechts mit zwei Drehknöpfen.
	for i in 2:
		_teil(root, F.walze(0.022, 0.02, 0.006, 20), dunkel, Vector3(0.31, 0.95 - i * 0.12, zm + 0.19), Vector3(90, 0, 0))
	_steht(root, Vector3(0.06, 0.006, 0.006), S.leuchte(Color(0.9, 0.3, 0.25), 2.0), 0.31, 0.66, zm + 0.193, 0.002)


static func _beamer(root: Node3D, zm: float) -> void:
	# Leinwand an der Wand (mit Kassette oben), davor auf dem Möbel ein Kurzdistanz-Beamer.
	_teil(root, F.walze(0.045, 2.1, 0.01, 20), S.lack(Color("#e8e6e1"), 0.4), Vector3(-1.05, 2.3, -0.2), Vector3(0, 0, -90))
	_kiste(root, Vector3(1.98, 1.12, 0.006), S.lack(Color("#1a1a1b"), 0.9, 0.1), Vector3(0, 1.66, -0.225), 0.002)
	_bildschirm(root, Vector2(1.9, 1.04), Vector3(0, 1.66, -0.22), 2)
	var gehaeuse := S.lack(Color("#e4e1db"), 0.45, 0.4)
	_steht(root, Vector3(0.52, 0.11, 0.32), gehaeuse, 0, 0.52, zm + 0.02, 0.035)
	_steht(root, Vector3(0.5, 0.012, 0.1), S.stoff("graphit", 260.0), 0, 0.6, zm + 0.13, 0.004)
	_steht(root, Vector3(0.2, 0.012, 0.05), S.leuchte(Color(0.95, 0.97, 1.0), 2.0), 0, 0.625, zm - 0.07, 0.004)


static func _lautsprecher(root: Node3D, v: String) -> void:
	var h := _m(S.holz(v, 1), 1)
	for x: float in [-0.09, 0.09]:
		for z: float in [-0.1, 0.1]:
			_bein(root, S.metall(Color("#2a2a2c"), 0.4), x, z, 0.08, 0.012)
	_steht(root, Vector3(0.24, 0.9, 0.27), h, 0, 0.08, 0, 0.016)
	_steht(root, Vector3(0.21, 0.86, 0.012), _g(S.stoff("graphit", 320.0), 0), 0, 0.1, 0.135, 0.006)
	_schatten(root, Vector2(0.26, 0.28), 0.45)


## Plattenspieler mit Riemenantrieb: Holzzarge mit schwarzer Deckplatte, Aluteller mit Stroboskop-
## Punkten, Filzmatte, Platte mit Rillen und Etikett, S-förmig abgesetzter Tonarm mit Gegengewicht,
## Lift und Stütze, Start/Stop, 33/45, Pitch, Scharniere der Haube; hinten eine Halterung, in der die
## Hülle des laufenden Titels steht (plattenspieler.gd). Teller und Arm sind eigene Knoten.
static func _plattenspieler(root: Node3D, v: String) -> void:
	var bau := Konsolen.Bau.new(Konsolen.loch())
	var holz := _m(S.holz(v, 0))
	var deck := S.lack(Color("#161618"), 0.5, 0.35)
	var alu := S.oberflaeche("stahl", "")
	var chrom := S.oberflaeche("chrom", "")
	var schwarz := S.lack(Color("#1c1c1e"), 0.45, 0.4)
	for x: float in [-0.185, 0.185]:
		for z: float in [-0.14, 0.14]:
			bau.w(schwarz, 0.022, 0.012, Vector3(x, 0, z), Vector3.ZERO, 24, 0.003)
			bau.ring(chrom, 0.0222, 0.0012, Vector3(x, 0.011, z))
	bau.s(holz, Vector3(0.44, 0.058, 0.35), 0, 0.012, 0, 0.008, 3)
	bau.s(deck, Vector3(0.436, 0.006, 0.346), 0, 0.07, 0, 0.003, 2)
	bau.w(chrom, 0.03, 0.004, Vector3(-0.05, 0.076, 0), Vector3.ZERO, 32)
	# Tonarm: Grundplatte und Lager, Stütze, Lift.
	bau.w(schwarz, 0.032, 0.005, Vector3(0.155, 0.076, -0.09), Vector3.ZERO, 32, 0.0015)
	bau.w(chrom, 0.016, 0.026, Vector3(0.155, 0.081, -0.09), Vector3.ZERO, 24, 0.002)
	bau.w(chrom, 0.004, 0.028, Vector3(0.155, 0.076, 0.08), Vector3.ZERO, 12)
	bau.k(schwarz, Vector3(0.014, 0.003, 0.006), Vector3(0.155, 0.1055, 0.08), 0.001, 1)
	bau.w(chrom, 0.005, 0.02, Vector3(0.196, 0.076, -0.045), Vector3.ZERO, 14)
	bau.k(schwarz, Vector3(0.004, 0.003, 0.024), Vector3(0.196, 0.097, -0.035), 0.001, 1)
	# Bedienung vorn: Start/Stop, 33 und 45, Pitch; Scharniere der Haube hinten.
	bau.s(alu, Vector3(0.034, 0.005, 0.02), -0.17, 0.076, 0.145, 0.0015)
	bau.s(alu, Vector3(0.016, 0.004, 0.012), -0.125, 0.076, 0.148, 0.0012)
	bau.s(alu, Vector3(0.016, 0.004, 0.012), -0.105, 0.076, 0.148, 0.0012)
	bau.k(bau.lo, Vector3(0.006, 0.001, 0.07), Vector3(0.198, 0.0765, 0.095), 0.0004, 1)
	bau.s(alu, Vector3(0.012, 0.006, 0.008), 0.198, 0.076, 0.1, 0.0015)
	for x: float in [-0.15, 0.15]:
		bau.k(schwarz, Vector3(0.032, 0.012, 0.012), Vector3(x, 0.078, -0.174), 0.002)
	# Halterung für die Hülle.
	bau.s(holz, Vector3(0.32, 0.012, 0.034), -0.05, 0, -0.205, 0.003)
	bau.k(bau.lo, Vector3(0.31, 0.002, 0.006), Vector3(-0.05, 0.0122, -0.205), 0.0005, 1)
	_teil(root, bau.netz(), null, Vector3.ZERO)
	var led := S.leuchte(Color(1.0, 0.36, 0.22), 0.0)
	led.albedo_color = Color(0.32, 0.12, 0.08)
	_teil(root, F.walze(0.0018, 0.0012, 0.0004, 12), led, Vector3(-0.145, 0.076, 0.15))
	root.set_meta("ps_led", led)
	# Teller (dreht sich): Alu mit Stroboskop-Punkten, Matte, Platte mit Rillen, Achse.
	var teller := Node3D.new()
	teller.name = "teller"
	teller.position = Vector3(-0.05, 0.08, 0.0)
	root.add_child(teller)
	var tb := Konsolen.Bau.new(Konsolen.loch())
	tb.w(alu, 0.152, 0.018, Vector3.ZERO, Vector3.ZERO, 64, 0.0025)
	for i in 72:
		var a := float(i) / 72.0 * TAU
		tb.k(S.lack(Color("#2a2a2c"), 0.6, 0.3), Vector3(0.0034, 0.003, 0.0012), Vector3(cos(a) * 0.1521, 0.0085, sin(a) * 0.1521), 0.0003, 1,
				Vector3(0, -rad_to_deg(a) + 90.0, 0))
	tb.w(S.stoff_farbig(Color("#2b2b2e"), 220.0), 0.148, 0.002, Vector3(0, 0.018, 0), Vector3.ZERO, 56, 0.0006)
	tb.w(S.lack(Color("#0b0b0c"), 0.22, 0.7), 0.1505, 0.0018, Vector3(0, 0.02, 0), Vector3.ZERO, 64, 0.0006)
	for r: float in [0.064, 0.078, 0.093, 0.108, 0.122, 0.137, 0.147]:
		tb.ring(S.lack(Color("#1d1d20"), 0.75, 0.2), r, 0.0005, Vector3(0, 0.0218, 0), Vector3(90, 0, 0), 56)
	tb.w(chrom, 0.0035, 0.016, Vector3(0, 0.018, 0), Vector3.ZERO, 12)
	var platte := _teil(teller, tb.netz(), null, Vector3.ZERO)
	var etikett := _teil(teller, F.walze(0.0475, 0.0006, 0.0002, 40), S.lack(GOLD, 0.6, 0.3), Vector3(0, 0.0216, 0))
	var bild := _teil(teller, _scheibe(0.046, 40), StandardMaterial3D.new(), Vector3(0, 0.0224, 0))
	bild.visible = false
	root.set_meta("teller", teller)
	root.set_meta("platte", platte)
	root.set_meta("etikett", etikett)
	root.set_meta("etikett_bild", bild)
	# Tonarm: Drehpunkt (Schwenk), darin der Lift (Heben), darin Rohr, Kopf, System, Gegengewicht.
	var arm := Node3D.new()
	arm.name = "tonarm"
	arm.position = Vector3(0.155, 0.112, -0.09)
	root.add_child(arm)
	var hub := Node3D.new()
	hub.name = "tonarm_hub"
	arm.add_child(hub)
	var ab := Konsolen.Bau.new(Konsolen.loch())
	ab.k(schwarz, Vector3(0.018, 0.012, 0.018), Vector3.ZERO, 0.003)
	ab.w(chrom, 0.0035, 0.205, Vector3(0, 0, 0.0), Vector3(90, 0, 0), 14, 0.001)
	ab.w(chrom, 0.0035, 0.034, Vector3(0, 0, -0.034), Vector3(90, 0, 0), 14, 0.001)
	ab.w(schwarz, 0.015, 0.026, Vector3(0, 0, -0.066), Vector3(90, 0, 0), 28, 0.003)
	ab.k(schwarz, Vector3(0.016, 0.004, 0.032), Vector3(-0.004, -0.002, 0.212), 0.0012, 1, Vector3(0, -20, 0))
	ab.k(S.lack(Color("#8e2a24"), 0.4, 0.5), Vector3(0.012, 0.009, 0.018), Vector3(-0.005, -0.0075, 0.214), 0.0012, 1, Vector3(0, -20, 0))
	ab.k(chrom, Vector3(0.014, 0.0015, 0.003), Vector3(0.006, -0.001, 0.226), 0.0005, 1, Vector3(0, -20, 0))
	_teil(hub, ab.netz(), null, Vector3.ZERO)
	root.set_meta("tonarm", arm)
	root.set_meta("tonarm_hub", hub)
	# Hülle des laufenden Titels (erst sichtbar, wenn etwas läuft).
	var huelle := Node3D.new()
	huelle.name = "huelle"
	huelle.position = Vector3(-0.05, 0.006, -0.205)
	huelle.rotation_degrees = Vector3(-8, 0, 0)
	huelle.visible = false
	root.add_child(huelle)
	var rand := StandardMaterial3D.new()
	rand.albedo_color = Color("#d9cdb6")
	rand.roughness = 0.85
	var vorn := StandardMaterial3D.new()
	vorn.roughness = 0.72
	vorn.albedo_color = Color("#d9cdb6")
	_teil(huelle, F.kiste(Vector3(0.314, 0.314, 0.0035), 0.0008, false, 1), rand, Vector3(0, 0.157, 0))
	_teil(huelle, F.flaeche(0.31, 0.31), vorn, Vector3(0, 0.157, 0.0019))
	root.set_meta("huelle", huelle)
	root.set_meta("huelle_bild", vorn)
	root.set_meta("huelle_rand", rand)
	_schatten(root, Vector2(0.44, 0.35), 0.4)


## Flache Scheibe in der xz-Ebene (oben sichtbar) mit ebenen UV: ein Bild füllt den Kreis.
static func _scheibe(r: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := float(i) / seg * TAU
		var a1 := float(i + 1) / seg * TAU
		for p: Vector2 in [Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.y * 0.5))
			st.add_vertex(Vector3(p.x * r, 0.0, p.y * r))
	return st.commit()


# --- Licht -----------------------------------------------------------------------------------------

## Lampenschirm aus Stoff mit Innen- und Außenseite (kegelförmig).
static func _schirm(root: Node3D, v: String, unten: float, oben: float, hoehe: float, pos: Vector3) -> ShaderMaterial:
	var u := PackedVector2Array([Vector2(unten, 0), Vector2(oben, hoehe), Vector2(oben - 0.004, hoehe), Vector2(unten - 0.004, 0), Vector2(unten, 0)])
	var m := S.schirm(v, _farbe(Color(0, 0, 0, 0)))
	var mi := _teil(root, F.dreh(u, 40, [0, 1, 2, 3, 4]), m, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = SCHIRM_EBENE
	return m


static func _stehlampe(root: Node3D, v: String) -> void:
	var met := _g(S.metall(MESSING, 0.32))
	_teil(root, F.walze(0.15, 0.024, 0.008, 36, true), S.metall(Color("#26262a"), 0.45), Vector3.ZERO)
	_teil(root, F.walze(0.011, 1.3, 0.003, 12), met, Vector3(0, 0.02, 0))
	var schirm := _schirm(root, v, 0.22, 0.16, 0.3, Vector3(0, 1.28, 0))
	var birne := S.leuchte(WARM, 3.5)
	_teil(root, F.walze(0.03, 0.07, 0.025, 16), birne, Vector3(0, 1.32, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lampe(root, Vector3(0, 1.4, 0), 1.25, 4.6, [schirm], [birne], [[Vector3(0, 1.43, 0), 0.36]])
	_schatten(root, Vector2(0.3, 0.3), 0.45, true)


static func _tischlampe(root: Node3D, v: String) -> void:
	var u := PackedVector2Array(
			[Vector2(0, 0), Vector2(0.06, 0), Vector2(0.085, 0.05), Vector2(0.09, 0.12), Vector2(0.06, 0.2), Vector2(0.025, 0.24), Vector2(0.02, 0.27),
			Vector2(0, 0.27)])
	_teil(root, F.dreh(u, 32), _g(S.lack(Color("#e8dfd0"), 0.22, 0.6)), Vector3.ZERO)
	var schirm := _schirm(root, v, 0.15, 0.1, 0.18, Vector3(0, 0.25, 0))
	var birne := S.leuchte(WARM, 3.5)
	_teil(root, F.walze(0.022, 0.05, 0.018, 12), birne, Vector3(0, 0.27, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lampe(root, Vector3(0, 0.32, 0), 0.7, 2.6, [schirm], [birne], [[Vector3(0, 0.34, 0), 0.22]])
	_schatten(root, Vector2(0.18, 0.18), 0.4, true)


static func _deckenlampe(root: Node3D, v: String) -> void:
	# Hängt an der Decke: Ursprung bleibt am Boden, die Lampe hängt von DECKE herab.
	var decke := 2.7
	_teil(root, F.walze(0.06, 0.02, 0.008, 24), S.lack(Color("#efece6"), 0.6), Vector3(0, decke - 0.02, 0))
	_teil(root, F.walze(0.004, 0.62, 0.001, 8), S.lack(Color("#1d1d1f"), 0.6), Vector3(0, decke - 0.64, 0))
	var u := PackedVector2Array([Vector2(0.27, 0), Vector2(0.26, 0.04), Vector2(0.2, 0.15), Vector2(0.08, 0.22), Vector2(0.03, 0.235),
		Vector2(0.026, 0.23), Vector2(0.075, 0.214), Vector2(0.195, 0.145), Vector2(0.254, 0.038), Vector2(0.264, 0)])
	var m := S.schirm(v, _farbe(Color(0, 0, 0, 0)))
	var schirm := _teil(root, F.dreh(u, 48, [0, 4, 5, 9]), m, Vector3(0, decke - 0.88, 0))
	schirm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	schirm.layers = SCHIRM_EBENE
	var birne := S.leuchte(WARM, 3.5)
	_teil(root, F.walze(0.035, 0.08, 0.03, 16), birne, Vector3(0, decke - 0.86, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lampe(root, Vector3(0, decke - 0.95, 0), 1.55, 6.0, [m], [birne], [[Vector3(0, decke - 0.8, 0), 0.4]])


static func _lichterkette(root: Node3D, v: String, breite: float) -> void:
	var c := WARM if v == "warm" else GOLD
	var birne := S.leuchte(c, 3.5)
	var bunt: Array = []
	if v == "bunt":
		for k in ["#ff6b6b", "#ffd166", "#4fd18b", "#4fa8ff", "#c77dff"]:
			bunt.append(S.leuchte(Color(k), 3.5))
	var draht := S.lack(Color("#2a2826"), 0.6)
	var n := int(18.0 * breite / 2.0)
	var y0 := 0.0
	var z := -0.22
	var prev := Vector3.ZERO
	var scheine: Array = []
	for i in n + 1:
		var t := float(i) / n
		var x := (t - 0.5) * breite * 0.96
		# Zwei Bögen, die durchhängen.
		var bogen := fmod(t * 2.0, 1.0)
		var y := y0 + 0.11 * (4.0 * bogen * (1.0 - bogen)) * -1.0 + 0.11
		var p := Vector3(x, y, z)
		if i > 0:
			var mitte := (p + prev) * 0.5
			var l := p.distance_to(prev)
			var mi := _kiste(root, Vector3(l, 0.004, 0.004), draht, mitte, 0.0015, false)
			mi.rotation.z = atan2(p.y - prev.y, p.x - prev.x)
		if i > 0 and i < n:
			_teil(root, F.walze(0.009, 0.026, 0.008, 10), birne if bunt.is_empty() else bunt[i % bunt.size()], p + Vector3(0, -0.03, 0.01))
			scheine.append([p + Vector3(0, -0.025, 0.02), 0.075])
		prev = p
	var l := _lampe(root, Vector3(0, 0.0, -0.05), 0.45 * breite / 2.0, 2.4, [], [birne] + bunt, scheine)
	if not bunt.is_empty():
		l.light_color = Color("#ffd0e8")
		(root.get_meta("lampen")[0] as Dictionary)["bunt"] = true


## LED-Leiste: schmales Aluprofil mit leuchtendem Streifen; „oben“ unter der Decke (Licht fällt an
## die Wand), „hinten“ tief hinter Möbeln. Die Farbe kommt aus dem Licht des Raums oder der Leiste.
static func _led_leiste(root: Node3D, v: String, breite: float) -> void:
	var y := 0.0 if v == "oben" else -1.95
	var z := -0.235
	_kiste(root, Vector3(breite - 0.04, 0.016, 0.022), S.metall(Color("#c9cacc"), 0.35), Vector3(0, y, z), 0.003, false)
	var streifen := S.leuchte(Color(0.6, 0.4, 1.0), 3.5)
	var mi := _kiste(root, Vector3(breite - 0.06, 0.006, 0.012), streifen, Vector3(0, y - 0.01, z + 0.002), 0.002, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Mehrere schwache Lichter entlang der Leiste, damit die Wand gleichmäßig angestrahlt wird.
	var n := maxi(1, int(round(breite / 0.9)))
	for i in n:
		var x := (float(i) + 0.5) / n * breite - breite * 0.5
		var l := _lampe(root, Vector3(x, y - 0.06, z + 0.12), 0.5, 1.9, [], [streifen] if i == 0 else [])
		l.omni_attenuation = 1.6
	for e in root.get_meta("lampen", []):
		(e as Dictionary)["farblicht"] = true


# --- Deko --------------------------------------------------------------------------------------------

static func _topf(root: Node3D, r: float, h: float, farbe: Color) -> void:
	var u := PackedVector2Array(
			[Vector2(0, 0), Vector2(r * 0.78, 0), Vector2(r * 0.86, 0.02), Vector2(r, h * 0.92), Vector2(r * 1.04, h), Vector2(r * 0.94, h), Vector2(r * 0.9, h * 0.9),
			Vector2(0, h * 0.9)])
	_teil(root, F.dreh(u, 36, [1, 3, 4, 5], true), _g(S.lack(farbe, 0.55, 0.4)), Vector3.ZERO)
	_teil(root, F.walze(r * 0.9, 0.01, 0.003, 24), S.stoff_farbig(Color("#3a2c22"), 300.0, 1.0), Vector3(0, h * 0.86, 0))


## Ein Teil, das sich im Zimmer leise wiegt (Blätter, Krone): Meta „wiegen“ am Möbel – [[Knoten,
## Grunddrehung]]; das Zimmer bewegt sie in kleinen, langsamen Ausschlägen (zimmer.gd _wiegen_bild).
static func _wiegen(root: Node3D, n: Node3D) -> void:
	var l: Array = root.get_meta("wiegen", [])
	l.append([n, n.rotation])
	root.set_meta("wiegen", l)


static func _pflanze(root: Node3D, v: String, groesse: float) -> void:
	var k := groesse
	var topf_farbe := Color("#c97b54") if v == "kaktus" else (Color("#e6dfd4") if v == "monstera" else Color("#5d5f62"))
	var tr := 0.17 * maxf(k, 0.45)
	var th := 0.3 * maxf(k, 0.45)
	_topf(root, tr, th, topf_farbe)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(v) + int(k * 100.0)
	match v:
		"monstera":
			var gruen := S.blatt(Color("#2f5f3a"))
			var stiel := S.lack(Color("#52794a"), 0.6)
			var n := 11 if k > 0.6 else 6
			for i in n:
				var ang := float(i) / n * TAU * 1.618 + rng.randf_range(-0.25, 0.25)
				var neig := rng.randf_range(18.0, 58.0)
				var lang := rng.randf_range(0.42, 0.95) * k
				var fuss := Vector3(0, th * 0.92, 0)
				var spitze := fuss + Vector3(cos(ang) * sin(deg_to_rad(neig)) * lang, cos(deg_to_rad(neig)) * lang, sin(ang) * sin(deg_to_rad(neig)) * lang)
				var st_mi := _kiste(root, Vector3(0.008, lang, 0.008), stiel, fuss + (spitze - fuss) * 0.5, 0.0035, false)
				var richtung := (spitze - fuss).normalized()
				st_mi.basis = Basis.looking_at(richtung, Vector3.FORWARD if absf(richtung.y) > 0.99 else Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
				var gr := rng.randf_range(0.75, 1.1)
				var bl := _teil(root, F.blatt((0.34 * k + 0.08) * gr, (0.36 * k + 0.08) * gr, 0.3), gruen, spitze)
				bl.rotation = Vector3(deg_to_rad(rng.randf_range(-35.0, 5.0)), -ang + PI * 0.5, deg_to_rad(rng.randf_range(-18, 18)))
				_wiegen(root, bl)
		"olive":
			var stamm := S.holz("walnuss", 1)
			_teil(root, F.walze(0.018 * k + 0.006, 0.75 * k, 0.004, 10), stamm, Vector3(0, th - 0.02, 0))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = F.blatt(0.08 * k + 0.02, 0.022 * k + 0.008, 0.1, 1)
			var n2 := 220 if k > 0.6 else 70
			mm.instance_count = n2
			var mitte := Vector3(0, th + 0.78 * k, 0)
			for i in n2:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.9), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.05, 0.27) * k
				var b := Basis.from_euler(Vector3(rng.randf_range(-1.2, 0.3), rng.randf_range(0, TAU), rng.randf_range(-0.5, 0.5)))
				mm.set_instance_transform(i, Transform3D(b, mitte + d))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = S.blatt(Color("#5f7a4e"))
			root.add_child(mmi)
			_wiegen(root, mmi)
		_:
			var gruen2 := S.lack(Color("#4f7a4a"), 0.55, 0.35)
			var hh := 0.62 * k + 0.08
			var u := PackedVector2Array(
					[Vector2(0, 0), Vector2(0.06 * k + 0.02, 0), Vector2(0.065 * k + 0.022, hh * 0.85), Vector2(0.04 * k + 0.01, hh), Vector2(0, hh + 0.01)])
			_teil(root, F.dreh(u, 16), gruen2, Vector3(0, th * 0.9, 0))
			if k > 0.6:
				for s: int in [-1, 1]:
					var ast := Node3D.new()
					ast.position = Vector3(s * 0.07, th + hh * (0.35 if s < 0 else 0.5), 0)
					root.add_child(ast)
					_teil(ast, F.walze(0.035, 0.1, 0.015, 12), gruen2, Vector3(0, 0, 0), Vector3(0, 0, -s * 90))
					_teil(ast, F.walze(0.035, 0.18, 0.03, 12), gruen2, Vector3(s * 0.08, 0, 0))
	_schatten(root, Vector2(tr * 2.0, tr * 2.0), 0.5, true)


static func _teppich(root: Node3D, v: String, w: float, d: float, rund: bool) -> void:
	var c := _farbe(S.stoff_farbe(v))
	var rand := c.darkened(0.28) if c.get_luminance() > 0.3 else c.lightened(0.25)
	if str(_it.get("f2", "")) != "":
		rand = Color(str(_it.f2))
	var mu := G.muster_nr(str(_it.get("mu", "")))
	var mf := Color(str(_it.mf)) if str(_it.get("mf", "")) != "" else rand
	var innen := S.stoff_voll(c, 60.0, 1.0, 0.32, 0.0, mu, mf) if mu > 0 else S.stoff_farbig(c, 60.0, 1.0)
	if rund:
		_teil(root, F.walze(w * 0.48, 0.012, 0.004, 64), S.stoff_farbig(rand, 60.0, 1.0), Vector3.ZERO)
		_teil(root, F.walze(w * 0.4, 0.012, 0.004, 64), innen, Vector3(0, 0.004, 0))
	else:
		# Lagen je 4 mm höher (früher 1,5 mm): von oben im Bauen kämpften die Flächen sonst um die
		# Tiefe und flackerten.
		_kiste(root, Vector3(w - 0.08, 0.012, d - 0.08), S.stoff_farbig(rand, 60.0, 1.0), Vector3(0, 0.006, 0), 0.005, false)
		_kiste(root, Vector3(w - 0.32, 0.016, d - 0.32), innen, Vector3(0, 0.008, 0), 0.005, false)
		if mu == 0:
			_kiste(root, Vector3(w - 0.5, 0.02, d - 0.5), S.stoff_farbig(c.darkened(0.08), 60.0, 1.0), Vector3(0, 0.01, 0), 0.005, false)
			_kiste(root, Vector3(w - 0.56, 0.024, d - 0.56), S.stoff_farbig(c, 60.0, 1.0), Vector3(0, 0.012, 0), 0.005, false)
	for mi in root.get_children():
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _bild(root: Node3D, v: String, breite := 1.0) -> void:
	var z := -0.235
	var k := clampf(breite / 1.0, 1.0, 2.1)
	_kiste(root, Vector3(0.78, 0.58, 0.03) * Vector3(k, k, 1), _g(S.holz("schwarz" if v != "sonne" else "eiche", 0), 0), Vector3(0, 0.29 * k, z), 0.006)
	_kiste(root, Vector3(0.72, 0.52, 0.004) * Vector3(k, k, 1), S.lack(Color("#f1ece3"), 0.85, 0.2), Vector3(0, 0.29 * k, z + 0.014), 0.001, false)
	var m := StandardMaterial3D.new()
	m.albedo_texture = motiv(v)
	m.roughness = 0.85
	_teil(root, F.flaeche(0.56 * k, 0.38 * k), m, Vector3(0, 0.29 * k, z + 0.0165))
	_blick(root, Vector3(0, 1.55, 1.1), Vector3(0, 1.55, z))


## Motiv eines Bilds: kleine, ruhige Grafik in warmen Tönen, hier gezeichnet (keine fremden Bilder).
## Farben und alles, was nur von Zeile oder Spalte abhängt, stehen vor der inneren Schleife: Je Bildpunkt die
## Farbtexte neu zu lesen kostete beim ersten Bau 8 bis 26 ms je Motiv im Hauptfaden.
static func motiv(v: String) -> ImageTexture:
	if _bilder.has(v):
		return _bilder[v]
	var w := 192
	var h := 132
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	match v:
		"huegel":
			_motiv_huegel(img, w, h)
		"sonne":
			_motiv_sonne(img, w, h)
		"wellen":
			_motiv_wellen(img, w, h)
		_:
			_motiv_punkte(img, w, h)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_bilder[v] = tex
	return tex


## Drei Hügelkämme vor einem warmen Himmel mit Sonne.
static func _motiv_huegel(img: Image, w: int, h: int) -> void:
	var oben := Color("#e9dcc6")
	var unten := Color("#f2c9a0")
	var sonne := Color("#d9784f")
	var kaemme: Array[Color] = [Color("#9aa184"), Color("#6f7a5e"), Color("#4b5543")]
	var kamm := PackedFloat64Array()   # Höhe der drei Kämme je Spalte
	kamm.resize(w * 3)
	for x in w:
		var u := float(x) / w
		for k in 3:
			kamm[x * 3 + k] = 0.55 + k * 0.12 + 0.07 * sin(u * (4.0 + k * 2.0) + k * 1.7)
	for y in h:
		var t := float(y) / h
		var himmel := oben.lerp(unten, t * 0.6)
		for x in w:
			var c := himmel
			if Vector2(float(x) / w - 0.7, t - 0.3).length() < 0.11:
				c = sonne
			for k in 3:
				if t > kamm[x * 3 + k]:
					c = kaemme[k]
			img.set_pixel(x, y, c)


## Halbe Sonne über dem Meer, ihr Widerschein in Streifen.
static func _motiv_sonne(img: Image, w: int, h: int) -> void:
	var himmel := Color("#f1e3cc")
	var hell := Color("#d9894f")
	var tief := Color("#c8603e")
	var meer_a := Color("#2f4258")
	var meer_b := Color("#22303f")
	for y in h:
		var t := float(y) / h
		var scheibe := hell.lerp(tief, clampf((0.62 - t) * 2.0, 0.0, 1.0))
		var meer := meer_a.lerp(meer_b, (t - 0.62) * 2.0)
		var streifen := int(t * 60.0) % 3 == 0
		for x in w:
			var u := float(x) / w
			var c := himmel
			if t < 0.62 and Vector2(u - 0.5, (t - 0.62) * 0.7).length() < 0.2:
				c = scheibe
			if t >= 0.62:
				c = meer
				if streifen and absf(u - 0.5) < 0.2 - (t - 0.62) * 0.4:
					c = hell
			img.set_pixel(x, y, c)


## Sechs Wellenlinien in drei Farben.
static func _motiv_wellen(img: Image, w: int, h: int) -> void:
	var papier := Color("#e8e0d2")
	var farben: Array[Color] = [Color("#2f4a5c"), Color("#c4913c"), Color("#87977a")]
	var welle := PackedFloat64Array()   # Höhe der sechs Linien je Spalte
	welle.resize(w * 6)
	for x in w:
		var u := float(x) / w
		for k in 6:
			welle[x * 6 + k] = 0.15 + k * 0.14 + 0.04 * sin(u * 9.0 + k)
	for y in h:
		var t := float(y) / h
		for x in w:
			var c := papier
			for k in 6:
				if absf(t - welle[x * 6 + k]) < 0.022:
					c = farben[k % 3]
			img.set_pixel(x, y, c)


## Raster aus Punkten in vier Farben.
static func _motiv_punkte(img: Image, w: int, h: int) -> void:
	var papier := Color("#ece4d6")
	var farben: Array[Color] = [Color("#b0603c"), Color("#c4913c"), Color("#34425e"), Color("#87977a")]
	for y in h:
		var t := float(y) / h
		var gy := (fmod(t * 5.5, 1.0) - 0.5) * 1.1
		var reihe := int(t * 5.5) * 3
		for x in w:
			var u := float(x) / w
			var c := papier
			if Vector2(fmod(u * 8.0, 1.0) - 0.5, gy).length() < 0.28:
				c = farben[(int(u * 8.0) + reihe) % 4]
			img.set_pixel(x, y, c)


static func _uhr(root: Node3D, v: String) -> void:
	var z := -0.235
	var rahmen := _m(S.holz(v, 0))
	_teil(root, F.walze(0.17, 0.035, 0.012, 48), rahmen, Vector3(0, 0.2, z - 0.015), Vector3(90, 0, 0))
	_teil(root, F.walze(0.15, 0.004, 0.001, 48), S.lack(Color("#f3efe7"), 0.6), Vector3(0, 0.2, z + 0.019), Vector3(90, 0, 0))
	var zeiger := S.lack(Color("#1e1e20"), 0.5)
	for i in 12:
		var a := float(i) / 12.0 * TAU
		var l := 0.022 if i % 3 == 0 else 0.012
		var mi := _kiste(root, Vector3(0.006, l, 0.003), zeiger, Vector3(sin(a) * 0.125, 0.2 + cos(a) * 0.125, z + 0.024), 0.001, false)
		mi.rotation.z = -a
	var std := Node3D.new()
	std.position = Vector3(0, 0.2, z + 0.028)
	root.add_child(std)
	_kiste(std, Vector3(0.012, 0.08, 0.004), zeiger, Vector3(0, 0.035, 0), 0.002, false)
	var minu := Node3D.new()
	minu.position = Vector3(0, 0.2, z + 0.032)
	root.add_child(minu)
	_kiste(minu, Vector3(0.008, 0.115, 0.004), zeiger, Vector3(0, 0.05, 0), 0.002, false)
	_teil(root, F.walze(0.01, 0.01, 0.003, 12), S.metall(MESSING), Vector3(0, 0.2, z + 0.03), Vector3(90, 0, 0))
	root.set_meta("uhr", [std, minu])
	stelle_uhr(root)


## Zeiger auf die Uhrzeit des PCs stellen.
static func stelle_uhr(root: Node3D) -> void:
	var z: Array = root.get_meta("uhr", [])
	if z.size() < 2:
		return
	var t := Time.get_time_dict_from_system()
	var m := float(t.minute) + float(t.second) / 60.0
	(z[0] as Node3D).rotation.z = -((float(t.hour % 12) + m / 60.0) / 12.0 * TAU)
	(z[1] as Node3D).rotation.z = -(m / 60.0 * TAU)


static func _buecher(root: Node3D, v: String) -> void:
	var farben := [_farbe(S.stoff_farbe(v)), Color("#d8ccb4"), Color("#7a3b2e"), Color("#4f5d47")]
	var papier := S.lack(Color("#efe8da"), 0.9, 0.1)
	var y := 0.0
	for i in 4:
		var g := Vector3(0.26 - i * 0.025, 0.035 + (i % 2) * 0.008, 0.19 - i * 0.012)
		var b := Node3D.new()
		b.position = Vector3(0.0, y, 0.0)
		b.rotation_degrees = Vector3(0, [4.0, -7.0, 12.0, -3.0][i], 0)
		root.add_child(b)
		_steht(b, g, S.stoff_farbig(farben[i], 220.0), 0, 0, 0, 0.004)
		_steht(b, Vector3(g.x - 0.012, g.y - 0.008, g.z * 0.96), papier, 0.008, 0.004, 0, 0.002)
		y += g.y
	_schatten(root, Vector2(0.26, 0.2), 0.35)


# --- Baukasten: eigene Möbel ----------------------------------------------------------------------

## Standard-Material je Bauteil (wenn im Teil keins gewählt ist).
const TEIL_MAT := { "platte": "eiche", "kasten": "eiche", "kissen": "stoff", "walze": "lack_matt", "kugel": "lack_matt",
	"bein": "walnuss", "stange": "messing", "schirm": "leinen", "leuchte": "lack_glanz", "griff": "messing", "bogen": "metall" }
const MAX_LICHTER := 4


# --- Echte Möbel aus freien Modellen (assets/zimmer/modelle, LIZENZ.txt dort) --------------------------

## Je Kennung: Datei, Maßstab (skal; passend = höchstens so groß wie die Felder), Stoff-Materialien
## (Namensteile – in Wunschfarbe über shaders/modell_stoff.gdshader), Lampen [[Ort im Modell, Energie,
## Reichweite], …], Sitz und Blick (im Möbel-Raum), wand = mit der Rückseite an der Wand.
const MODELLE := {
	"sofa_samt": { "datei": "sofa_samt.gltf", "stoff": ["fabric"], "sitz": [Vector3(0, 1.05, 0.05), Vector3(0, 0.95, 4.0)],
		"blick": [Vector3(0, 1.45, 2.2), Vector3(0, 0.45, 0)] },
	"sofa_leder": { "datei": "sofa_leder.gltf", "sitz": [Vector3(0, 1.08, 0.05), Vector3(0, 0.95, 4.0)], "blick": [Vector3(0, 1.5, 2.4), Vector3(0, 0.5, 0)] },
	"sessel_samt": { "datei": "sessel_samt.gltf", "stoff": ["fabric"], "sitz": [Vector3(0, 1.0, 0.02), Vector3(0, 0.9, 4.0)],
		"blick": [Vector3(0, 1.35, 1.6), Vector3(0, 0.4, 0)] },
	"sessel_damast": { "datei": "sessel_damast.gltf", "sitz": [Vector3(0, 1.0, 0.02), Vector3(0, 0.9, 4.0)], "blick": [Vector3(0, 1.35, 1.6), Vector3(0, 0.4, 0)] },
	"pflanze_busch": { "datei": "pflanze_busch.gltf", "skal": 1.15, "blick": [Vector3(0, 1.2, 1.3), Vector3(0, 0.5, 0)] },
	"vase_blumen": { "datei": "vase_blumen.gltf", "skal": 1.3, "passend": false },
	"tasse": { "datei": "tasse.gltf", "passend": false },
	"spielzeugauto": { "datei": "spielzeugauto.gltf", "skal": 2.6, "passend": false },
	"radio": { "datei": "radio.gltf", "skal": 0.95, "passend": false },
	"stehlampe_dreiarm": { "datei": "stehlampe_dreiarm.gltf", "lampen": [[Vector3(0.15, 1.55, 0.0), 1.3, 4.0]],
		"blick": [Vector3(0, 1.4, 1.8), Vector3(0, 1.2, 0)] },
	"wandlampe": { "datei": "wandlampe.gltf", "skal": 1.25, "wand": true, "lampen": [[Vector3(0, -0.12, 0.14), 0.7, 2.6]] },
}
const MODELL_ORDNER := "res://assets/zimmer/modelle/"       # .gltf mit eigener .bin und Texturen
static var _szenen := {}
static var _helligkeit := {}


## Dateien der Modelle, die diese Möbel brauchen: fürs Vorladen im Hintergrund (zimmer_welt.gd vorlade_pfade).
## Ein Modell lädt sonst mitten im Bau im Hauptfaden (gemessen: das Ledersofa 0,8 s, die Pflanze 0,4 s).
static func modell_pfade(moebel: Array) -> Array[String]:
	var out: Array[String] = []
	for it: Variant in moebel:
		if not it is Dictionary:
			continue
		var m: Dictionary = MODELLE.get(str((it as Dictionary).get("t", "")), {})
		if m.is_empty():
			continue
		var pfad := MODELL_ORDNER + str(m.datei)
		if not out.has(pfad):
			out.append(pfad)
	return out


static func _modell(root: Node3D, id: String, v: String, w: float, d: float) -> void:
	var m: Dictionary = MODELLE.get(id, {})
	if m.is_empty():
		return
	var pfad := MODELL_ORDNER + str(m.datei)
	if not _szenen.has(pfad):
		_szenen[pfad] = load(pfad)
	var szene := _szenen[pfad] as PackedScene
	if szene == null:
		return
	var n := szene.instantiate() as Node3D
	if n == null:
		return
	var halter := Node3D.new()
	halter.name = "modell"
	root.add_child(halter)
	halter.add_child(n)
	# Maß: Hülle des Modells, Maßstab fest oder passend in die Felder; unten auf dem Boden, Mitte im
	# Feld (Wandmöbel: mit der Rückseite an der Wand).
	var box := _modell_box(n)
	var skal := float(m.get("skal", 1.0))
	var wand := bool(m.get("wand", false))
	if bool(m.get("passend", true)) and box.size.x > 0.001 and box.size.z > 0.001:
		skal = minf(skal, minf((w - 0.04) / box.size.x, (d - 0.02) / box.size.z))
	n.scale = Vector3.ONE * skal
	var mitte := box.get_center()
	n.position = Vector3(-mitte.x * skal, -box.position.y * skal, (-0.235 - box.position.z * skal) if wand else -mitte.z * skal)
	# Materialien: Stoff in Wunschfarbe (Katalog-Variante oder Anpassen); alles wirft Schatten.
	var stoff: Array = m.get("stoff", [])
	for mi: MeshInstance3D in _modell_netze(n):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D and _stoff_name(str(mat.resource_name), stoff):
				mi.set_surface_override_material(s, _modell_stoff(mat as StandardMaterial3D, v))
	for l in m.get("lampen", []):
		var p: Vector3 = n.position + (l[0] as Vector3) * skal
		_lampe(root, p, float(l[1]), float(l[2]), [], [], [[p, 0.1]])
	if not wand:
		_schatten(root, Vector2(box.size.x, box.size.z) * skal + Vector2(0.04, 0.04), 0.5, box.size.x * skal < 0.3)
	if m.has("sitz"):
		root.set_meta("sitz", { "pos": m.sitz[0], "ziel": m.sitz[1] })
	if m.has("blick"):
		_blick(root, m.blick[0], m.blick[1])


## Hülle eines Modells in seinem eigenen Raum (alle Netze).
static func _modell_box(n: Node3D) -> AABB:
	var out := AABB()
	var erst := true
	var stapel: Array = [[n, Transform3D()]]
	while not stapel.is_empty():
		var e: Array = stapel.pop_back()
		var k: Node = e[0]
		var t: Transform3D = e[1]
		for c in k.get_children():
			if c is Node3D:
				var ct: Transform3D = t * (c as Node3D).transform
				if c is MeshInstance3D and (c as MeshInstance3D).mesh:
					var b := ct * (c as MeshInstance3D).get_aabb()
					out = b if erst else out.merge(b)
					erst = false
				stapel.append([c, ct])
	return out


static func _modell_netze(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_modell_netze(c))
	return out


static func _stoff_name(name: String, teile: Array) -> bool:
	var l := name.to_lower()
	for t in teile:
		if l.contains(str(t).to_lower()):
			return true
	return false


## Ein Stoff-Material des Modells in Wunschfarbe: Helligkeit aus seiner Grundfarbkarte, Farbe aus
## der Variante bzw. dem Anpassen; Normal-, Rauheits- und AO-Karte des Modells bleiben.
static func _modell_stoff(alt: StandardMaterial3D, v: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MODELL_STOFF_S
	m.set_shader_parameter("farbe", _farbe(S.stoff_farbe(v)))
	m.set_shader_parameter("mittel", _karte_mittel(alt.albedo_texture))
	if alt.albedo_texture:
		m.set_shader_parameter("t_farbe", alt.albedo_texture)
	if alt.normal_enabled and alt.normal_texture:
		m.set_shader_parameter("t_normal", alt.normal_texture)
		m.set_shader_parameter("normal_an", 1.0)
	if alt.roughness_texture:
		m.set_shader_parameter("t_rau", alt.roughness_texture)
		m.set_shader_parameter("rau_kanal", mini(int(alt.roughness_texture_channel), 3))
		m.set_shader_parameter("rau_an", 1.0)
	m.set_shader_parameter("rauheit", alt.roughness)
	if alt.ao_enabled and alt.ao_texture:
		m.set_shader_parameter("t_ao", alt.ao_texture)
		m.set_shader_parameter("ao_kanal", mini(int(alt.ao_texture_channel), 3))
		m.set_shader_parameter("ao_an", 1.0)
	return m


## Mittlere Helligkeit einer Farbkarte (einmal je Karte; ohne Bild 0,5).
static func _karte_mittel(tex: Texture2D) -> float:
	if tex == null:
		return 0.5
	var key := tex.get_rid()
	if _helligkeit.has(key):
		return float(_helligkeit[key])
	var mittel := 0.5
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		if not img.is_compressed():
			img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
			var summe := 0.0
			for y in 16:
				for x in 16:
					var c := img.get_pixel(x, y)
					summe += c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			mittel = maxf(summe / 256.0, 0.05)
	_helligkeit[key] = mittel
	return mittel


# --- Spielplatz, Deko und Snacks (eigene Formen) ------------------------------------------------------

static func _kugel_netz(r: float) -> SphereMesh:
	var k := SphereMesh.new()
	k.radius = r
	k.height = r * 2.0
	k.radial_segments = 18
	k.rings = 9
	return k


## Gaming-Stuhl: Fußkreuz mit fünf Armen und Rollen, Gasfeder, Sitzschale mit Wangen, hohe
## geneigte Lehne mit Seitenwangen, Kopfkissen, Armlehnen; Nähte als helle Keder.
static func _gamingstuhl(root: Node3D, v: String) -> void:
	var st := _m(S.stoff(v, 40.0, 0.0))
	var schwarz := _g(S.lack(Color("#1b1b1e"), 0.55, 0.4))
	var metall := S.metall(Color("#9a9ca0"), 0.3)
	for i in 5:
		var arm := Node3D.new()
		arm.rotation.y = float(i) / 5.0 * TAU
		root.add_child(arm)
		_kiste(arm, Vector3(0.045, 0.03, 0.32), schwarz, Vector3(0, 0.05, 0.16), 0.006)
		_kiste(arm, Vector3(0.03, 0.05, 0.05), schwarz, Vector3(0, 0.025, 0.31), 0.012, false)
	_teil(root, F.walze(0.028, 0.3, 0.004, 16), metall, Vector3(0, 0.03, 0))
	_teil(root, F.walze(0.05, 0.07, 0.006, 16), schwarz, Vector3(0, 0.06, 0))
	_kiste(root, Vector3(0.52, 0.1, 0.52), st, Vector3(0, 0.46, 0.02), 0.03)
	for s: int in [-1, 1]:
		_kiste(root, Vector3(0.09, 0.07, 0.48), st, Vector3(s * 0.235, 0.54, 0.0), 0.03)
	var lehne := Node3D.new()
	lehne.position = Vector3(0, 0.5, -0.24)
	lehne.rotation.x = deg_to_rad(-8)
	root.add_child(lehne)
	_kiste(lehne, Vector3(0.5, 0.8, 0.1), st, Vector3(0, 0.4, 0), 0.03)
	for s: int in [-1, 1]:
		_kiste(lehne, Vector3(0.08, 0.56, 0.13), st, Vector3(s * 0.23, 0.34, 0.06), 0.03)
		_kiste(lehne, Vector3(0.012, 0.6, 0.004), S.lack(Color("#d9d2c4"), 0.7, 0.3), Vector3(s * 0.15, 0.36, 0.052), 0.001, false)
		_steht(root, Vector3(0.03, 0.2, 0.03), schwarz, s * 0.3, 0.5, 0.02, 0.004)
		_kiste(root, Vector3(0.07, 0.025, 0.26), schwarz, Vector3(s * 0.3, 0.71, 0.02), 0.006)
	_kiste(lehne, Vector3(0.26, 0.11, 0.07), S.stoff("graphit" if v != "graphit" else "creme", 40.0), Vector3(0, 0.67, 0.07), 0.03)
	_schatten(root, Vector2(0.66, 0.66), 0.45, true)
	root.set_meta("sitz", { "pos": Vector3(0, 1.1, 0.02), "ziel": Vector3(0, 1.0, 4.0) })
	_blick(root, Vector3(0, 1.3, 1.7), Vector3(0, 0.7, 0))


## Monitor auf Standfuß, leicht geneigt; der Schirm zeigt dasselbe Bild wie der Fernseher.
static func _monitor(root: Node3D, v: String) -> void:
	var geh := _m(S.lack(Color("#e9e7e1") if v == "weiss" else Color("#1a1b1e"), 0.45, 0.4))
	_teil(root, F.walze(0.11, 0.012, 0.004, 32), geh, Vector3(0, 0, -0.06))
	_steht(root, Vector3(0.05, 0.3, 0.025), geh, 0, 0.01, -0.09, 0.004)
	var kopf := Node3D.new()
	kopf.position = Vector3(0, 0.31, -0.06)
	kopf.rotation.x = deg_to_rad(-4)
	root.add_child(kopf)
	_kiste(kopf, Vector3(0.61, 0.36, 0.02), geh, Vector3.ZERO, 0.004)
	_kiste(kopf, Vector3(0.6, 0.35, 0.004), S.lack(Color("#0a0b0d"), 0.08, 0.9), Vector3(0, 0, 0.011), 0.001, false)
	_bildschirm(kopf, Vector2(0.59, 0.335), Vector3(0, 0, 0.0135), 1)
	_blick(root, Vector3(0, 0.45, 0.9), Vector3(0, 0.3, 0))


## Spiele-PC: Gehäuse mit Gitterfront, Glasseite, zwei leuchtenden Lüfterringen und Lichtstreifen.
static func _rechner(root: Node3D, v: String) -> void:
	var geh := _m(S.lack(Color("#e9e7e1") if v == "weiss" else Color("#1c1d20"), 0.5, 0.4))
	var dunkel := S.lack(Color("#111214"), 0.6, 0.3)
	var licht := S.leuchte(Color("#6fd2ff"), 1.4)
	_steht(root, Vector3(0.21, 0.44, 0.42), geh, 0, 0.012, 0, 0.005)
	for i in 4:
		_teil(root, F.walze(0.012, 0.012, 0.002, 10), dunkel, Vector3((-1 if i % 2 == 0 else 1) * 0.08, 0, (-1 if i < 2 else 1) * 0.17))
	_kiste(root, Vector3(0.19, 0.4, 0.004), dunkel, Vector3(0, 0.232, 0.212), 0.001, false)
	for i in 3:
		_kiste(root, Vector3(0.15, 0.004, 0.004), S.lack(Color("#2c2d31"), 0.5, 0.3), Vector3(0, 0.3 + i * 0.05, 0.215), 0.001, false)
	_teil(root, F.walze(0.006, 0.003, 0.001, 12), S.metall(Color("#c9cacc"), 0.2), Vector3(0.07, 0.452, 0.18))
	_kiste(root, Vector3(0.004, 0.36, 0.34), S.lack(Color("#141518"), 0.7, 0.2), Vector3(0.1, 0.232, -0.01), 0.001, false)
	_kiste(root, Vector3(0.004, 0.01, 0.3), licht, Vector3(0.103, 0.07, -0.01), 0.001, false)
	for i in 2:
		_teil(root, F.ring(0.05, 0.004, TAU, 24, 6), licht, Vector3(0.103, 0.17 + i * 0.13, -0.09), Vector3(0, 0, 90))
	_kiste(root, Vector3(0.004, 0.36, 0.34), S.glas(), Vector3(0.106, 0.232, -0.01), 0.001, false)
	_schatten(root, Vector2(0.24, 0.44), 0.4)


## Zwei kleine Regallautsprecher: Holzgehäuse, dunkle Front, Tief- und Hochtöner.
static func _regallautsprecher(root: Node3D, v: String) -> void:
	var holz := _m(S.holz(v, 0))
	var front := _g(S.lack(Color("#1d1d20"), 0.75, 0.25))
	var tief := PackedVector2Array([Vector2(0, 0), Vector2(0.055, 0), Vector2(0.05, 0.012), Vector2(0.015, 0.03), Vector2(0, 0.03)])
	var hoch := PackedVector2Array([Vector2(0, 0), Vector2(0.025, 0), Vector2(0.02, 0.01), Vector2(0, 0.012)])
	for s: int in [-1, 1]:
		var x := s * 0.12
		_steht(root, Vector3(0.17, 0.28, 0.22), holz, x, 0, -0.02, 0.004)
		_kiste(root, Vector3(0.15, 0.26, 0.004), front, Vector3(x, 0.14, 0.092), 0.001, false)
		_teil(root, F.dreh(tief, 24, [1, 2]), S.lack(Color("#2a2b2e"), 0.6, 0.3), Vector3(x, 0.095, 0.094), Vector3(90, 0, 0))
		_teil(root, F.dreh(hoch, 20, [1]), S.metall(Color("#b9bbbe"), 0.35), Vector3(x, 0.215, 0.094), Vector3(90, 0, 0))
	_schatten(root, Vector2(0.46, 0.24), 0.35)


static func _kissen(root: Node3D, v: String) -> void:
	_kiste(root, Vector3(0.42, 0.13, 0.42), _m(S.stoff(v, 120.0, 0.3)), Vector3(0, 0.065, 0), 0.06, true, Vector3(0, 12, 0))
	_schatten(root, Vector2(0.42, 0.42), 0.3, true)


## Gefaltete Wolldecke: drei Lagen, leicht gegeneinander verdreht.
static func _decke(root: Node3D, v: String) -> void:
	var st := _m(S.stoff(v, 60.0, 0.5))
	_kiste(root, Vector3(0.44, 0.05, 0.34), st, Vector3(0, 0.025, 0), 0.02, true, Vector3(0, -6, 0))
	_kiste(root, Vector3(0.42, 0.045, 0.32), st, Vector3(0.01, 0.072, -0.01), 0.02, true, Vector3(0, 4, 0))
	_kiste(root, Vector3(0.4, 0.04, 0.3), st, Vector3(-0.01, 0.112, 0.01), 0.02, true, Vector3(0, -3, 0))
	_schatten(root, Vector2(0.44, 0.34), 0.3)


## Poster ohne Rahmen (eigenes Motiv), mit vier Klebestreifen in den Ecken.
static func _poster(root: Node3D, v: String) -> void:
	var z := -0.244
	var papier := StandardMaterial3D.new()
	papier.albedo_texture = motiv(v)
	papier.roughness = 0.92
	_kiste(root, Vector3(0.6, 0.85, 0.002), S.lack(Color("#f3eee4"), 0.9, 0.15), Vector3(0, 0.45, z + 0.001), 0.0005, false)
	_teil(root, F.flaeche(0.58, 0.83), papier, Vector3(0, 0.45, z + 0.003))
	var band := S.lack(Color("#f0ece2"), 0.55, 0.2)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			_kiste(root, Vector3(0.05, 0.016, 0.002), band, Vector3(sx * 0.27, 0.45 + sy * 0.4, z + 0.005), 0.0005, false, Vector3(0, 0, 45.0 * sx * sy))
	_blick(root, Vector3(0, 1.5, 1.0), Vector3(0, 1.5, z))


## Minikühlschrank: Sockel, Korpus, Tür mit Fuge und Chromgriff.
static func _minikuehlschrank(root: Node3D, v: String) -> void:
	var farbe: Color = { "schwarz": Color("#232427"), "creme": Color("#eee6d6"), "mint": Color("#a9d3c4") }.get(v, Color("#eee6d6"))
	var geh := _m(S.lack(farbe, 0.35, 0.5))
	var dunkel := S.lack(Color("#1b1b1e"), 0.6, 0.3)
	_steht(root, Vector3(0.46, 0.04, 0.44), dunkel, 0, 0, -0.01, 0.004)
	_steht(root, Vector3(0.47, 0.78, 0.45), geh, 0, 0.04, -0.01, 0.012)
	_kiste(root, Vector3(0.45, 0.74, 0.012), geh, Vector3(0, 0.43, 0.22), 0.006)
	_kiste(root, Vector3(0.02, 0.3, 0.02), S.metall(Color("#c9cacc"), 0.2), Vector3(0.18, 0.5, 0.235), 0.006)
	_kiste(root, Vector3(0.004, 0.74, 0.014), dunkel, Vector3(-0.227, 0.43, 0.22), 0.001, false)
	_schatten(root, Vector2(0.48, 0.46), 0.5)
	_blick(root, Vector3(0, 1.1, 1.2), Vector3(0, 0.45, 0))


## Snackschale: flache Schale, darin Chips, Obst oder Süßes (ein paar Dutzend Stücke).
static func _snackschale(root: Node3D, v: String) -> void:
	var u := PackedVector2Array([Vector2(0, 0), Vector2(0.06, 0), Vector2(0.12, 0.03), Vector2(0.14, 0.07), Vector2(0.13, 0.075), Vector2(0.11, 0.045),
		Vector2(0.05, 0.012), Vector2(0, 0.012)])
	_teil(root, F.dreh(u, 32, [1, 2, 3, 4]), _m(S.lack(Color("#e8e2d6"), 0.3, 0.5)), Vector3.ZERO)
	var inhalt: Material = S.lack(Color("#8e4a7a"), 0.3, 0.5)
	var r := 0.015
	if v == "chips":
		inhalt = S.lack(Color("#e8b85a"), 0.75, 0.2)
		r = 0.022
	elif v == "obst":
		inhalt = S.lack(Color("#c94f3d"), 0.35, 0.5)
		r = 0.03
	var zweit := S.lack(Color("#e2b23a"), 0.4, 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kugel := _kugel_netz(1.0)
	for i in 14:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.08
		var skal := Vector3(r * (1.6 if v == "chips" else 1.0), r * (0.3 if v == "chips" else 1.0), r)
		_teil(root, kugel, zweit if v == "obst" and i % 3 == 0 else inhalt, Vector3(cos(a) * d, 0.03 + rng.randf() * 0.03, sin(a) * d),
				Vector3(rng.randf() * 90.0, rng.randf() * 90.0, 0), skal)
	_schatten(root, Vector2(0.3, 0.3), 0.25, true)


## Drei kleine Figuren auf Sockeln: stilisiert, ohne Vorbild (Kegelstumpf, Kopf, Ärmchen).
static func _figuren(root: Node3D, v: String) -> void:
	var farben: Array = { "bunt": [Color("#d9534f"), Color("#4f8fd9"), Color("#e8b84a")], "pastell": [Color("#f1b7c4"), Color("#b7d9f1"), Color("#d6f1b7")] } \
			.get(v, [GOLD, GOLD, GOLD])
	var sockel := S.lack(Color("#2a2b2e"), 0.5, 0.4)
	var koerper := PackedVector2Array([Vector2(0, 0), Vector2(0.028, 0), Vector2(0.022, 0.07), Vector2(0.03, 0.09), Vector2(0, 0.09)])
	for i in 3:
		var x := (i - 1) * 0.13
		var c: Color = farben[i]
		var mat := S.pokal_metall(c, 0.25) if v == "gold" else S.lack(c, 0.3, 0.5)
		_teil(root, F.walze(0.035, 0.01, 0.002, 20), sockel, Vector3(x, 0, 0))
		_teil(root, F.dreh(koerper, 20, [1, 2]), mat, Vector3(x, 0.01, 0))
		_teil(root, _kugel_netz(0.03), mat, Vector3(x, 0.125, 0))
		for s: int in [-1, 1]:
			_teil(root, F.walze(0.007, 0.05, 0.002, 10), mat, Vector3(x + s * 0.03, 0.045, 0.0), Vector3(0, 0, -s * 30.0))
	_schatten(root, Vector2(0.4, 0.1), 0.25)


static func teil_material(t: Dictionary) -> Material:
	var a := str(t.get("a", "platte"))
	var mat := str(t.get("m", TEIL_MAT.get(a, "eiche")))
	return S.oberflaeche(mat, str(t.get("f", "")), 0 if a in ["platte", "kasten"] else 1, str(t.get("mu", "")))


## Ein eigenes Möbel aus dem Baukasten (gestalt.gd, pruefe_eigenes): jedes Teil eine eigene Form,
## Maße in Zentimetern, y = Unterkante, Ursprung Mitte der Grundfläche. Schirme und Leuchtkugeln
## bringen Licht mit (höchstens MAX_LICHTER je Möbel).
static func _eigen(root: Node3D, d: Dictionary) -> void:
	var lichter := 0
	for t in d.get("teile", []):
		var a := str(t.a)
		var g := Vector3(float(t.b), float(t.h), float(t.t)) / 100.0
		var pos := Vector3(float(t.x), float(t.y), float(t.z)) / 100.0
		var n := Node3D.new()
		n.position = pos
		n.rotation_degrees = Vector3(0, -float(t.r), 0)
		root.add_child(n)
		var mat := teil_material(t)
		match a:
			"platte":
				_kiste(n, g, mat, Vector3(0, g.y * 0.5, 0), minf(0.006, g.y * 0.4))
			"kasten":
				_kiste(n, g, mat, Vector3(0, g.y * 0.5, 0), minf(0.014, minf(g.x, minf(g.y, g.z)) * 0.3))
			"kissen":
				_kiste(n, g, mat, Vector3(0, g.y * 0.5, 0), minf(g.x, minf(g.y, g.z)) * 0.42)
			"walze":
				_teil(n, F.walze(0.5, 1.0, 0.03, 32), mat, Vector3.ZERO, Vector3.ZERO, Vector3(g.x, g.y, g.z))
			"kugel":
				_teil(n, _kugel(), mat, Vector3.ZERO, Vector3.ZERO, g)
			"bein":
				var u := PackedVector2Array([Vector2(0, 0), Vector2(0.35, 0), Vector2(0.5, 1.0), Vector2(0, 1.0)])
				_teil(n, F.dreh(u, 14, [1, 2]), mat, Vector3.ZERO, Vector3.ZERO, g)
			"stange":
				_teil(n, F.walze(0.5, 1.0, 0.1, 12), mat, Vector3.ZERO, Vector3.ZERO, g)
			"griff":
				_kiste(n, g, mat, Vector3(0, g.y * 0.5, 0), minf(g.y, g.z) * 0.45, false)
			"bogen":
				var bogen := _teil(n, F.ring(0.5, maxf(0.01, g.z / maxf(g.x, 0.01) * 0.5), PI, 32, 10), mat, Vector3(0, 0, 0), Vector3.ZERO, Vector3(g.x, g.y * 2.0, g.x))
				bogen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			"schirm", "leuchte":
				var f := Color(str(t.f)) if str(t.get("f", "")) != "" else Color("#e8dfd0")
				if a == "schirm":
					var u2 := PackedVector2Array([Vector2(0.5, 0), Vector2(0.36, 1.0), Vector2(0.35, 1.0), Vector2(0.49, 0), Vector2(0.5, 0)])
					var sm := S.schirm("", f)
					var mi := _teil(n, F.dreh(u2, 40, [0, 1, 2, 3, 4]), sm, Vector3.ZERO, Vector3.ZERO, g)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.layers = SCHIRM_EBENE
					var birne := S.leuchte(WARM, 3.5)
					_teil(n, F.walze(0.025, 0.06, 0.02, 12), birne, Vector3(0, g.y * 0.3, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if lichter < MAX_LICHTER:
						_lampe(n, Vector3(0, g.y * 0.45, 0), 0.9, 3.2, [sm], [birne])
						lichter += 1
				else:
					var gl := S.leuchte(f.lerp(WARM, 0.3), 3.0)
					var k := _teil(n, _kugel(), gl, Vector3.ZERO, Vector3.ZERO, g)
					k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if lichter < MAX_LICHTER:
						_lampe(n, Vector3(0, g.y * 0.5, 0), 0.7, 2.8, [], [gl])
						lichter += 1
	# Lampen hängen an den Teilen: für Schalten und Anpassen am Möbel sammeln.
	var alle: Array = []
	for c in root.get_children():
		alle.append_array((c as Node).get_meta("lampen", []))
	if not alle.is_empty():
		root.set_meta("lampen", alle)
	if str(d.get("ebene", "boden")) == "boden":
		_schatten(root, Vector2(float(d.w), float(d.d)) * Katalog.ZELLE * 0.9, 0.45)
	_blick(root, Vector3(0, 1.3, 1.4), Vector3(0, 0.5, 0))


static var _kugel_mesh: ArrayMesh


## Kugel mit Durchmesser 1 (Ursprung unten), für Kugeln und Leuchtkugeln im Baukasten.
static func _kugel() -> ArrayMesh:
	if _kugel_mesh == null:
		var u := PackedVector2Array()
		for i in 13:
			var a := -PI * 0.5 + PI * float(i) / 12.0
			u.append(Vector2(cos(a) * 0.5, 0.5 + sin(a) * 0.5))
		u[0] = Vector2(0, 0)
		u[12] = Vector2(0, 1)
		_kugel_mesh = F.dreh(u, 32)
	return _kugel_mesh


## Ein eigenes Möbel für sich (Baukasten-Bühne, Katalog-Vorschau), Licht an.
static func eigen_bauen(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(d.get("id", "")) if str(d.get("id", "")) != "" else "eigen"
	_it = {}
	_eigen(root, d)
	schalten(root, true)
	return root

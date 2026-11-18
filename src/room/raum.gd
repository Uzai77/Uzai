extends Node3D
## Die Hülle des Zimmers: Boden, vier Wände (links das Fenster, rechts die Tür), Decke,
## Sockelleisten, draußen der Himmel – und das Licht nach Tageszeit und Wetter (Licht-Konzept in
## licht.gd): Sonne bzw. Mond durchs Fenster als einzige Lichtquelle mit echten Schatten, kühles
## Himmelslicht, ein warmes Zurückwerfen vom Sonnenfleck (Bounce, fuell), Umgebung von oben, der
## Seite und vom Boden, ein weicher Lichtstrahl im Fenster, Tonwerte (Filmic), Farbkorrektur.
## Zwei Wege (licht.gd werte): In Forward+ (Vulkan/D3D12) vorberechnetes Licht – die Hülle bekommt
## ihr Licht aus Lichtkarten, die lichtbacken.gd bei jeder Änderung backt (weiche Schatten aller Lampen
## und der Sonne, Himmel als Umgebung, Abprall vom Sonnenfleck; die Reflexionssonde gibt Glanz);
## echte Lichter treffen nur Möbel und Figur (GEBACKEN, ABPRALL_LAMPEN), AgX ohne Auto-Belichtung.
## SDFGI, SSIL, SSR und Volumen-Nebel bleiben als Schalter der Stufen, sind aber überall aus.
## Im Kompatibilitäts-Rückfall (OpenGL) gibt es nichts davon; dann wie früher: wenige echte Lichter,
## der Rest gerechnet
## (lichter.gdshaderinc, Kontaktschatten), Wände, Decke, Boden und Teppiche auf HUELLE_EBENE, die
## Lampen rechnen die Shader. In der Stufe Leicht gibt es keine Sonne mit Schatten; dann zeichnen
## die Shader den Sonnenfleck aus dem Fenster selbst. Oberflächen kommen aus Karten (stoffe.gd
## TEXTUREN) auf Raumkoordinaten.
##
## Alles Gestaltbare kommt aus den Daten des Raums (gestalt.gd): Wand je Seite (Farbe, Material,
## Tapete), Boden, Sockel, Decke, Fenster mit Vorhängen, Tür, Tageszeit und Wetter. Farben und
## Licht gleiten weich in den neuen Stand (setze_gestalt, setze_licht); ändert sich die Form
## (Fenster, Tür, Leisten, Decke), wird nur die Hülle neu gebaut (anpassen).
##
## Von oben (Übersicht, Bau-Modus) blendet die Hülle die Wände aus, die zwischen Kamera und Raum
## stehen – sie werfen aber weiter Schatten.

signal lampen_geaendert
## Licht, Form oder Farben haben sich geändert (Reflexionssonde neu; lichtbacken.gd backt neu).
signal licht_geaendert

const S := preload("res://src/room/stoffe.gd")
const F := preload("res://src/room/formen.gd")
const G := preload("res://src/room/gestalt.gd")
const Katalog := preload("res://src/room/katalog.gd")
const WAND_S := preload("res://src/room/shaders/wand.gdshader")
const BODEN_S := preload("res://src/room/shaders/boden.gdshader")
const HIMMEL_S := preload("res://src/room/shaders/himmel.gdshader")
const KULISSE_S := preload("res://src/room/shaders/kulisse.gdshader")
const STRAHL_S := preload("res://src/room/shaders/strahl.gdshader")
const STOFF_WEHEN_S := preload("res://src/room/shaders/stoff_wehen.gdshader")
const Licht := preload("res://src/room/licht.gd")

const HUELLE_EBENE := 4      ## Wände, Decke, Boden, Teppiche (Lampen wirken hier im Shader)
## Lichtstrahl, Staub, Regen: nur Schein, kein Licht – die Kameras beim Backen sehen sie nicht
## (lichtbacken.gd: der Strahl endet auf dem Boden und lag sonst als helle Fläche in der Lichtkarte).
const EFFEKT_EBENE := 1 << 16
## Forward+ mit gebackenem Licht: Anteil des Himmels als Umgebungslicht beim Backen der Hülle (je
## Tageszeit mal „amb“), davon für Möbel und Figur im laufenden Bild „amb_moebel“, Himmelslicht durchs
## Fenster und warmer Abprall vom Sonnenfleck. Die Umgebung kam früher in Ultra und Hoch aus SDFGI, die
## den Himmel drinnen nur durchs Fenster sah und Möbel in sich verdeckte; ohne sie leuchtete er jede
## Fläche von allen Seiten voll an (der Tag hell, flach und blass, Holz bläulich).
const GEBACKEN := { "amb": 0.3, "amb_moebel": 0.5, "himmel": 0.7, "fuell": 0.25 }
## Abprall der Lampen auf Möbel und Figur (Forward+ gebacken): Das von Wänden und Decke zurückgeworfene
## Lampenlicht kam früher über SDFGI; jetzt eine warme Grundhelle, die mit der Stärke aller brennenden
## Lampen wächst (zimmer_welt.gd lampen_auffrischen). Nur im laufenden Bild – die Hülle backt ohne sie.
const ABPRALL_LAMPEN := 0.014
const ABPRALL_FARBE := Color(1.0, 0.8, 0.6)

const HOEHE := 2.7
const DICKE := 0.14
const BANK_UEBER := 0.004          ## Fensterbank: Oberseite so weit über der Laibung (kein Z-Fighting)
const FENSTER := { "unten": 0.88, "oben": 2.28, "breite": 1.9 }
const TUER := { "breite": 0.92, "hoehe": 2.08 }
const WEICH := 0.45          ## Sekunden für Farbwechsel
const WEICH_LICHT := 0.8     ## Sekunden für Tageszeit, Wetter und Stimmung

const WAND_ARTEN := { "anstrich": 0, "kalk": 1, "tapete": 2, "paneel": 3, "holz": 4, "ziegel": 5, "beton": 6, "fliesen": 7 }
## Karten je Wandart und je Boden-Shader-Art (stoffe.gd TEXTUREN).
const WAND_TEXTUR := { 0: "putz", 1: "putz", 2: "stoff", 3: "putz", 4: "holz_hell", 5: "beton", 6: "beton", 7: "fliesen" }
const BODEN_TEXTUR := { 0: "dielen", 1: "teppich", 2: "fliesen", 3: "dielen", 4: "fliesen", 5: "marmor", 6: "beton", 7: "marmor" }
## Bodenart → [Shader-Art, Dielenbreite, Glanz, dunkler um].
const BODEN_ARTEN := {
	"dielen": [0, 0.19, 0.45, 0.28], "landhaus": [0, 0.27, 0.4, 0.3], "fischgrat": [3, 0.19, 0.5, 0.3],
	"fliesen": [2, 0.19, 0.3, 0.22], "schachbrett": [4, 0.19, 0.6, 0.1], "terrazzo": [5, 0.19, 0.6, 0.35],
	"beton": [6, 0.19, 0.3, 0.2], "teppichboden": [1, 0.19, 0.0, 0.15], "marmor": [7, 0.19, 0.7, 0.1],
}

## Tageszeiten (Licht-Konzept in licht.gd).
const ZEITEN := Licht.ZEITEN
## Wetter: wie viel Sonne und Himmelslicht bleibt, wohin der Himmel sich färbt, Wolken.
const WETTER := {
	"klar": { "sonne": 1.0, "himmel": 1.0, "grau": "#000000", "grau_k": 0.0, "wolken": -1.0, "hell": 1.0, "weiss": 0.0, "dunst": 0.0 },
	"wolkig": { "sonne": 0.42, "himmel": 0.85, "grau": "#aab0b8", "grau_k": 0.38, "wolken": 1.0, "hell": 0.9, "weiss": 0.0, "dunst": 0.0 },
	"regen": { "sonne": 0.16, "himmel": 0.62, "grau": "#6c737c", "grau_k": 0.62, "wolken": 1.0, "hell": 0.72, "weiss": 0.0, "dunst": 0.25 },
	"schnee": { "sonne": 0.32, "himmel": 0.95, "grau": "#d5dae0", "grau_k": 0.5, "wolken": 1.0, "hell": 0.95, "weiss": 0.75, "dunst": 0.2 },
	"nebel": { "sonne": 0.28, "himmel": 0.8, "grau": "#c3c7cc", "grau_k": 0.7, "wolken": 0.3, "hell": 0.9, "weiss": 0.0, "dunst": 0.85 },
}

var w := 6.0
var d := 5.0
var leicht := false
var forward := true        ## Forward+ (sonst Kompatibilitäts-Rückfall)
var env: Environment
var lut_umkehr: ImageTexture      ## Farbkorrektur rückwärts (für das Spielbild im Fernseher)
var _lut_umkehr_bild: Image
var _sonde: ReflectionProbe
var _sonde_timer: SceneTreeTimer
var sonne: DirectionalLight3D
var himmelslicht: SpotLight3D
var fuell: OmniLight3D     ## Bounce: warmes Licht, das der Sonnenfleck zurück in den Raum wirft
var stufe := {}            ## Werte der Grafik-Stufe (licht.gd STUFE_WERTE)
var schlank := false       ## schlanker Weg neben dem laufenden Spiel (schlank_setzen)
var _sonde_offen := false  ## die Sonde hätte neu aufnehmen sollen, während der schlanke Weg galt
var huellen_mats: Array = []   ## Materialien mit lichter.gdshaderinc (Wände, Decke, Boden)
var _strahl: MeshInstance3D
var _strahl_mat: ShaderMaterial
var _strahl_dir := Vector3.ZERO
var _strahl_soll := Vector3.ZERO     ## zuletzt gewünschte Richtung (auch, solange der Strahl aus ist)
var _staub: CPUParticles3D       ## Staub, der im Lichtstrahl schwebt (nur mit Strahl)
var _staub_mat: StandardMaterial3D
var _lut: GradientTexture1D
var _stimmung: Dictionary = Licht.STIMMUNG_WERTE[""]
var lampen_faktor := 1.0
var _lampen_summe := 0.0
var himmel_backen := 0.0           ## Anteil des Himmels als Umgebung der Hülle beim Backen (lichtbacken.gd)
var zeit := "tag"
var wetter := "klar"
var _wand_mats := {}       ## Seite → ShaderMaterial (jede Wand für sich)
var _wand_mat: ShaderMaterial
var _boden_mat: ShaderMaterial
var _himmel_mat: ShaderMaterial
var _decke_mat: ShaderMaterial
var _leiste_mat: StandardMaterial3D
var _rahmen_mat: StandardMaterial3D
var _vorhang_mat: ShaderMaterial
var _rollo_mat: ShaderMaterial   ## wie der Vorhang, aber ohne Wehen (Rollo-Bahn)
var _tuer_mat: StandardMaterial3D
var _balken_mat: Material
var _waende := {}          ## Seite ("hinten", "links", "vorn", "rechts") → [MeshInstance3D, …]
var _gardine: MeshInstance3D  ## wirft keinen Schatten: von oben ausgeblendet statt nur schattend
var _decke: Array = []
var _sky: ProceduralSkyMaterial
var _himmel: MeshInstance3D
var _glas: MeshInstance3D
var _glas_innen: Material
var _glas_oben: StandardMaterial3D
var _geo: Node3D           ## alles Gebaute der Hülle (wird bei neuer Form ersetzt)
var _wetter_knoten: Node3D
var _form := ""            ## Kennzeichen der gebauten Form (anpassen baut nur neu, wenn es sich ändert)
var _gestalt := {}         ## zuletzt gesetzte Gestaltung (raum)
var _licht_tw: Tween
var fenster_box := AABB()  ## für „Fenster ansehen“ (A wechselt die Tageszeit)
var fenster := FENSTER.duplicate()
var bau_nr := 0                ## zählt jeden Neubau der Hülle (zimmer_welt.gd schnitt)


## werte: Grafik-Stufe (licht.gd STUFE_WERTE); true/false wie früher (leicht/mittel).
func bauen(raum: Dictionary, werte: Variant) -> void:
	stufe = werte if werte is Dictionary else Licht.werte("leicht" if bool(werte) else "mittel")
	leicht = int(stufe.get("schatten", 0)) == 0
	forward = str(stufe.get("renderer", Licht.renderer_jetzt())) == "forward"
	w = float(raum.w) * Katalog.ZELLE
	d = float(raum.d) * Katalog.ZELLE
	for s in G.SEITEN:
		var m := ShaderMaterial.new()
		m.shader = WAND_S
		m.set_shader_parameter("raum", Vector2(w, d))
		m.set_shader_parameter("hoehe", HOEHE)
		_wand_mats[s] = m
	_wand_mat = _wand_mats.hinten
	_boden_mat = ShaderMaterial.new()
	_boden_mat.shader = BODEN_S
	_boden_mat.set_shader_parameter("raum", Vector2(w, d))
	_decke_mat = ShaderMaterial.new()
	_decke_mat.shader = WAND_S
	_decke_mat.set_shader_parameter("farbe", Color("#efebe4"))
	_decke_mat.set_shader_parameter("raum", Vector2(w, d))
	_decke_mat.set_shader_parameter("hoehe", HOEHE)
	_leiste_mat = _eigen_lack(Color("#f1ede6"), 0.45, 0.4)
	_rahmen_mat = _eigen_lack(Color("#f3f0ea"), 0.4, 0.45)
	_vorhang_mat = (S.stoff("creme", 90.0) as ShaderMaterial).duplicate() as ShaderMaterial
	_rollo_mat = _vorhang_mat.duplicate() as ShaderMaterial
	# Vorhänge wehen sanft im Luftzug (stoff_wehen.gdshader, nur am Saum); das Rollo bleibt still.
	_vorhang_mat.shader = STOFF_WEHEN_S
	_vorhang_mat.set_shader_parameter("wehen", 0.016)
	_vorhang_mat.set_shader_parameter("wehen_hoehe", HOEHE - 0.24)
	_tuer_mat = (S.holz("weiss", 1) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_balken_mat = S.holz("walnuss", 0)
	_himmel_mat = ShaderMaterial.new()
	_himmel_mat.shader = HIMMEL_S
	_glas_innen = S.glas(Color(0.86, 0.92, 0.96, 0.08))
	_glas_oben = StandardMaterial3D.new()
	_glas_oben.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glas_oben.cull_mode = BaseMaterial3D.CULL_DISABLED
	huellen_mats = (_wand_mats.values() as Array) + [_decke_mat, _boden_mat]
	for m: ShaderMaterial in huellen_mats:
		# Forward+: die Hülle ist gebacken (ohne SSAO auf ihr) – Ecken und Kanten etwas dunkler im Shader.
		m.set_shader_parameter("eigen_ao", 0.6 if forward else 1.0)
	_umgebung()
	_lichter()
	_wetter_knoten = Node3D.new()
	add_child(_wetter_knoten)
	anpassen(raum, false)
	setze_licht(raum.get("licht", {}), false)


static func _eigen_lack(c: Color, rauheit: float, glanz: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rauheit
	m.metallic_specular = glanz
	m.vertex_color_use_as_albedo = true
	return m


## Neuer Stand der Gestaltung: die Form nur neu bauen, wenn sie sich ändert, Farben weich.
func anpassen(raum: Dictionary, weich := true) -> void:
	var g: Dictionary = raum
	var form := str([g.get("fenster", {}).get("a"), g.get("fenster", {}).get("g"), g.get("fenster", {}).get("v"),
		g.get("tuer", {}).get("a"), g.get("tuer", {}).get("p"), g.get("sockel", {}).get("a"), g.get("decke", {}).get("a")])
	if form != _form:
		_form = form
		_geo_bauen(g)
		sonde_neu()
		weich = false
		if is_instance_valid(sonne) and is_instance_valid(_sky) and _himmel_mat.get_shader_parameter("oben") != null:
			_werte_setzen(_ziel_werte(zeit, wetter))
	setze_gestalt(g, weich)


func _geo_bauen(g: Dictionary) -> void:
	bau_nr += 1
	if is_instance_valid(_geo):
		_geo.queue_free()
	_geo = Node3D.new()
	add_child(_geo)
	_waende.clear()
	_decke.clear()
	_gardine = null
	var fe: Dictionary = g.get("fenster", {})
	var art := str(fe.get("a", "sprossen"))
	var gi := clampi(int(fe.get("g", 1)), 0, G.FENSTERGROESSEN.size() - 1)
	fenster = FENSTER.duplicate()
	fenster.breite = minf(float(G.FENSTERGROESSEN[gi][1]), d - 1.0)
	if gi == 3:
		fenster.unten = 0.06
	_boden()
	_waende_bauen(g, art != "keins")
	if art != "keins":
		_fenster(g)
	else:
		fenster_box = AABB()
		_himmel = null
		_glas = null
	_tuer(g)
	_decke_deko(str(g.get("decke", {}).get("a", "glatt")))
	_wetter_bauen()
	# Glas des Fensters für den gerechneten Sonnenfleck (lichter.gdshaderinc); ohne Fenster keiner.
	var fz := d * 0.5
	var fb := float(fenster.breite) if art != "keins" else 0.0
	var teile := Vector2(1.0 if art in ["sprossen", "fluegel", "raster"] else 0.0, 1.0 if art in ["sprossen", "raster"] else 0.0)
	for m: ShaderMaterial in huellen_mats:
		m.set_shader_parameter("fenster", Vector4(fz - fb * 0.5, fz + fb * 0.5, float(fenster.unten), float(fenster.oben)))
		m.set_shader_parameter("fenster_teile", teile)
	_strahl_dir = Vector3.ZERO


func _box(groesse: Vector3, mat: Material, mitte: Vector3, seite := "") -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = groesse
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = mitte
	if mat in huellen_mats:
		mi.layers = HUELLE_EBENE
	_geo.add_child(mi)
	if seite != "":
		if not _waende.has(seite):
			_waende[seite] = []
		_waende[seite].append(mi)
	return mi


func _stueck(mesh: Mesh, mat: Material, pos: Vector3, seite := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_geo.add_child(mi)
	if seite != "":
		if not _waende.has(seite):
			_waende[seite] = []
		_waende[seite].append(mi)
	return mi


func _boden() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 0.02, d + 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _boden_mat
	mi.position = Vector3(w * 0.5, 0, d * 0.5)
	mi.layers = HUELLE_EBENE
	_geo.add_child(mi)
	# Unter dem Boden ein Sockel, damit das Zimmer von oben nicht wie ein Blatt Papier schwebt.
	var sockel := _box(Vector3(w + DICKE * 2.0, 0.12, d + DICKE * 2.0), S.lack(Color("#1d1c1b"), 0.8, 0.2), Vector3(w * 0.5, -0.0605, d * 0.5))
	sockel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _waende_bauen(g: Dictionary, mit_fenster: bool) -> void:
	var t := DICKE
	var h := HOEHE
	# Hinten (z = 0) und vorn (z = d) über die ganze Breite, Ecken mit.
	_box(Vector3(w + t * 2.0, h, t), _wand_mats.hinten, Vector3(w * 0.5, h * 0.5, -t * 0.5), "hinten")
	_box(Vector3(w + t * 2.0, h, t), _wand_mats.vorn, Vector3(w * 0.5, h * 0.5, d + t * 0.5), "vorn")
	# Links mit Fensteröffnung: unten, oben, davor, dahinter.
	var wl: ShaderMaterial = _wand_mats.links
	if mit_fenster:
		var fz := d * 0.5
		var fb := float(fenster.breite)
		var fu := float(fenster.unten)
		var fo := float(fenster.oben)
		_box(Vector3(t, fu, d), wl, Vector3(-t * 0.5, fu * 0.5, d * 0.5), "links")
		_box(Vector3(t, h - fo, d), wl, Vector3(-t * 0.5, fo + (h - fo) * 0.5, d * 0.5), "links")
		var vorn_l := fz - fb * 0.5
		_box(Vector3(t, fo - fu, vorn_l), wl, Vector3(-t * 0.5, fu + (fo - fu) * 0.5, vorn_l * 0.5), "links")
		var hinten_l := d - (fz + fb * 0.5)
		_box(Vector3(t, fo - fu, hinten_l), wl, Vector3(-t * 0.5, fu + (fo - fu) * 0.5, fz + fb * 0.5 + hinten_l * 0.5), "links")
	else:
		_box(Vector3(t, h, d), wl, Vector3(-t * 0.5, h * 0.5, d * 0.5), "links")
	_box(Vector3(t, h, d), _wand_mats.rechts, Vector3(w + t * 0.5, h * 0.5, d * 0.5), "rechts")
	# Decke.
	var decke := _box(Vector3(w + t * 2.0, 0.1, d + t * 2.0), _decke_mat, Vector3(w * 0.5, h + 0.05, d * 0.5))
	_decke.append(decke)
	# Sockelleisten (lackiert, weich gerundet), schmal oder hoch.
	var art := str(g.get("sockel", {}).get("a", "schmal"))
	if art == "keine":
		return
	var lh := 0.075 if art == "schmal" else 0.14
	var lt := 0.016 if art == "schmal" else 0.02
	_leiste(Vector3(w, lh, lt), Vector3(w * 0.5, lh * 0.5, lt * 0.5), "hinten")
	_leiste(Vector3(w, lh, lt), Vector3(w * 0.5, lh * 0.5, d - lt * 0.5), "vorn")
	if mit_fenster and float(fenster.unten) < lh + 0.02:
		var fz2 := d * 0.5
		var fb2 := float(fenster.breite) + 0.08
		_leiste(Vector3(lt, lh, fz2 - fb2 * 0.5), Vector3(lt * 0.5, lh * 0.5, (fz2 - fb2 * 0.5) * 0.5), "links")
		var r2 := d - (fz2 + fb2 * 0.5)
		_leiste(Vector3(lt, lh, r2), Vector3(lt * 0.5, lh * 0.5, fz2 + fb2 * 0.5 + r2 * 0.5), "links")
	else:
		_leiste(Vector3(lt, lh, d), Vector3(lt * 0.5, lh * 0.5, d * 0.5), "links")
	var tz := _tuer_z(g)
	var tb := float(TUER.breite) + 0.14
	_leiste(Vector3(lt, lh, tz - tb * 0.5), Vector3(w - lt * 0.5, lh * 0.5, (tz - tb * 0.5) * 0.5), "rechts")
	var rest := d - (tz + tb * 0.5)
	_leiste(Vector3(lt, lh, rest), Vector3(w - lt * 0.5, lh * 0.5, tz + tb * 0.5 + rest * 0.5), "rechts")


func _leiste(gr: Vector3, mitte: Vector3, seite: String) -> void:
	if gr.x <= 0.01 or gr.z <= 0.01:
		return
	_stueck(F.kiste(gr, 0.006, false), _leiste_mat, mitte, seite)


## Mitte der Zimmertür am Boden (rechte Wand), für den Eintritt durch sie (zimmer.gd _eintreten_tuer).
func tuer_mitte() -> Vector3:
	return Vector3(w, 0.0, _tuer_z(_gestalt))


func _tuer_z(g: Dictionary) -> float:
	match str(g.get("tuer", {}).get("p", "vorn")):
		"mitte": return d * 0.5
		"hinten": return 0.95
	return d - 0.95


func _fenster(g: Dictionary) -> void:
	var fz := d * 0.5
	var fb := float(fenster.breite)
	var fu := float(fenster.unten)
	var fo := float(fenster.oben)
	var art := str(g.get("fenster", {}).get("a", "sprossen"))
	var x := -DICKE * 0.55
	var r := 0.055
	# Rahmen: außen herum, je nach Art Mittelpfosten, Kämpfer (Oberlicht) oder kleine Sprossen.
	var stuecke := [
		[Vector3(0.07, r, fb), Vector3(x, fu + r * 0.5, fz)], [Vector3(0.07, r, fb), Vector3(x, fo - r * 0.5, fz)],
		[Vector3(0.07, fo - fu, r), Vector3(x, (fu + fo) * 0.5, fz - fb * 0.5 + r * 0.5)],
		[Vector3(0.07, fo - fu, r), Vector3(x, (fu + fo) * 0.5, fz + fb * 0.5 - r * 0.5)],
	]
	match art:
		"sprossen":
			stuecke.append([Vector3(0.06, fo - fu, 0.045), Vector3(x, (fu + fo) * 0.5, fz)])
			stuecke.append([Vector3(0.06, 0.04, fb), Vector3(x, fo - 0.42, fz)])
		"fluegel":
			stuecke.append([Vector3(0.06, fo - fu, 0.06), Vector3(x, (fu + fo) * 0.5, fz)])
		"raster":
			var spalten := maxi(2, int(round(fb / 0.45)))
			for i in range(1, spalten):
				stuecke.append([Vector3(0.05, fo - fu, 0.022), Vector3(x, (fu + fo) * 0.5, fz - fb * 0.5 + fb * float(i) / spalten)])
			var zeilen := maxi(2, int(round((fo - fu) / 0.45)))
			for j in range(1, zeilen):
				stuecke.append([Vector3(0.05, 0.022, fb), Vector3(x, fu + (fo - fu) * float(j) / zeilen, fz)])
	var seite: Array = _waende.links
	for s in stuecke:
		seite.append(_stueck(F.kiste(s[0], 0.008, false), _rahmen_mat, s[1]))
	var glas := MeshInstance3D.new()
	_glas = glas
	glas.mesh = F.flaeche(fb, fo - fu)
	glas.material_override = _glas_innen
	glas.position = Vector3(x - 0.01, (fu + fo) * 0.5, fz)
	glas.rotation_degrees = Vector3(0, 90, 0)
	glas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geo.add_child(glas)
	seite.append(glas)
	# Fensterbank innen (nicht bei bodentiefen Fenstern): von knapp im Rahmen bis 14 cm in den Raum, die
	# Oberseite BANK_UEBER über der Laibung darunter. Früher lag sie genau in deren Ebene (y = fu) und
	# reichte durch sie hindurch: beide Flächen kämpften um dieselben Bildpunkte (Z-Fighting), die Bank
	# flackerte bei jeder kleinen Bewegung.
	if fu > 0.3:
		var hinten := x + 0.033
		var vorn := 0.14
		_stueck(F.kiste(Vector3(vorn - hinten, 0.035, fb + 0.16), 0.008, true), _rahmen_mat,
				Vector3((vorn + hinten) * 0.5, fu - 0.0175 + BANK_UEBER, fz), "links")
	_vorhaenge(str(g.get("fenster", {}).get("v", "lang")), fz, fb, fu, fo)
	# Draußen: Himmel, Hügel und Wiese (himmel.gdshader rechnet nach der Blickrichtung) auf einer großen
	# Kugel um das Fenster – aus jedem Blickwinkel, auch steil nach unten, liegt dort etwas. Früher eine
	# Fläche 4,5 m vor dem Fenster: ganz nah sah man unter ihr das Schwarz dahinter.
	var him := MeshInstance3D.new()
	_himmel = him
	var kugel := SphereMesh.new()
	kugel.radius = 30.0
	kugel.height = 60.0
	kugel.radial_segments = 32
	kugel.rings = 16
	him.mesh = kugel
	him.material_override = _himmel_mat
	him.position = Vector3(0.0, (fu + fo) * 0.5, fz)
	him.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	him.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_geo.add_child(him)
	fenster_box = AABB(Vector3(-0.1, fu, fz - fb * 0.5), Vector3(0.25, fo - fu, fb))


## Vorhänge: lang (bis zum Boden), Gardine (lichtdurchlässig dazwischen) und Vorhänge, kurz (bis
## zur Fensterbank), Rollo (oben halb heruntergelassen) oder keine.
func _vorhaenge(art: String, fz: float, fb: float, fu: float, fo: float) -> void:
	if art == "keine":
		return
	if art == "rollo":
		var kasten := _stueck(F.kiste(Vector3(0.06, 0.07, fb + 0.06), 0.01, false), _rahmen_mat, Vector3(0.035, fo + 0.05, fz), "links")
		kasten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var tief := (fo - fu) * 0.32
		var bahn := _stueck(F.kiste(Vector3(0.006, tief, fb - 0.02), 0.002, false), _rollo_mat, Vector3(0.03, fo + 0.02 - tief * 0.5, fz), "links")
		bahn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_stueck(F.kiste(Vector3(0.016, 0.022, fb - 0.02), 0.006, false), _rahmen_mat, Vector3(0.032, fo + 0.02 - tief, fz), "links")
		return
	var hoehe := HOEHE - 0.24 if art != "kurz" else HOEHE - 0.18 - fu + 0.06
	var unten := 0.06 if art != "kurz" else fu - 0.04
	for s: int in [-1, 1]:
		var v := MeshInstance3D.new()
		v.mesh = F.vorhang(0.5, hoehe, 4, 0.055)
		v.material_override = _vorhang_mat
		if forward:
			# Er bewegt sich immer: sein Schatten ließe die Sonne jedes Bild neu rechnen – nur beim Backen
			# (lichtbacken.gd _bewegte_schatten).
			v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			v.set_meta("uz_backschatten", true)
		v.position = Vector3(0.09, unten, fz + s * (fb * 0.5 + 0.12))
		v.rotation_degrees = Vector3(0, 90, 0)
		_geo.add_child(v)
		_waende.links.append(v)
	if art == "gardine":
		var gm := S.glas(Color(0.96, 0.94, 0.9, 0.2))
		var gv := MeshInstance3D.new()
		gv.mesh = F.vorhang(fb + 0.2, HOEHE - 0.26, 9, 0.03)
		gv.material_override = gm
		gv.position = Vector3(0.05, 0.08, fz)
		gv.rotation_degrees = Vector3(0, 90, 0)
		gv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_geo.add_child(gv)
		_gardine = gv
	var stange := MeshInstance3D.new()
	stange.mesh = F.walze(0.012, fb + 0.8, 0.004, 12)
	stange.material_override = S.metall(Color("#2b2a29"), 0.4)
	stange.position = Vector3(0.1, HOEHE - 0.16, fz - (fb + 0.8) * 0.5)
	stange.rotation_degrees = Vector3(90, 0, 0)
	_geo.add_child(stange)
	_waende.links.append(stange)


func _tuer(g: Dictionary) -> void:
	var tz := _tuer_z(g)
	var tb := float(TUER.breite)
	var th := float(TUER.hoehe)
	var x := w - 0.012
	var art := str(g.get("tuer", {}).get("a", "kassette"))
	var teile := [
		[Vector3(0.03, th + 0.07, 0.07), Vector3(x - 0.004, (th + 0.07) * 0.5, tz - tb * 0.5 - 0.035)],
		[Vector3(0.03, th + 0.07, 0.07), Vector3(x - 0.004, (th + 0.07) * 0.5, tz + tb * 0.5 + 0.035)],
		[Vector3(0.03, 0.07, tb + 0.14), Vector3(x - 0.004, th + 0.035, tz)],
	]
	for s in teile:
		_stueck(F.kiste(s[0], 0.008, false), _leiste_mat, s[1], "rechts")
	_stueck(F.kiste(Vector3(0.04, th, tb), 0.01, false), _tuer_mat, Vector3(x - 0.008, th * 0.5, tz), "rechts")
	match art:
		"kassette":
			# Zwei eingelassene Füllungen.
			for y: float in [0.62, 1.48]:
				_stueck(F.kiste(Vector3(0.012, 0.62 if y < 1.0 else 0.7, tb - 0.24), 0.01, false), _tuer_mat, Vector3(x - 0.03, y, tz), "rechts")
		"glas":
			_stueck(F.kiste(Vector3(0.012, 0.36, tb - 0.24), 0.01, false), _tuer_mat, Vector3(x - 0.03, 0.5, tz), "rechts")
			var gl := _stueck(F.flaeche(tb - 0.26, 0.92), S.glas(Color(0.9, 0.92, 0.9, 0.35)), Vector3(x - 0.031, 1.38, tz), "rechts")
			gl.rotation_degrees = Vector3(0, -90, 0)
			for y2: float in [0.91, 1.85]:
				_stueck(F.kiste(Vector3(0.016, 0.04, tb - 0.22), 0.008, false), _tuer_mat, Vector3(x - 0.03, y2, tz), "rechts")
		"landhaus":
			for i in range(1, 5):
				_stueck(F.kiste(Vector3(0.006, th - 0.06, 0.006), 0.002, false), S.lack(Color(0, 0, 0, 1), 0.9, 0.1),
						Vector3(x - 0.029, th * 0.5, tz - tb * 0.5 + tb * float(i) / 5.0), "rechts")
			_stueck(F.kiste(Vector3(0.014, 0.12, tb - 0.04), 0.008, false), _tuer_mat, Vector3(x - 0.03, 1.0, tz), "rechts")
	var griff := { "messing": S.metall(Color("#b8925a"), 0.3), "schwarz": S.metall(Color("#1e1e20"), 0.45), "chrom": S.metall(Color("#d6d8db"), 0.1) }.get(
			str(g.get("tuer", {}).get("gf", "messing")), S.metall(Color("#b8925a"), 0.3)) as Material
	var k1 := _stueck(F.walze(0.008, 0.06, 0.003, 12), griff, Vector3(x - 0.03, 1.02, tz - tb * 0.5 + 0.09), "rechts")
	k1.rotation_degrees = Vector3(0, 0, 90)
	_stueck(F.kiste(Vector3(0.016, 0.016, 0.12), 0.006, false), griff, Vector3(x - 0.085, 1.02, tz - tb * 0.5 + 0.13), "rechts")


## Decke: glatt, Holzbalken quer, Holzdecke (Bretter) oder ein Stuckrand an den Wänden.
func _decke_deko(art: String) -> void:
	match art:
		"balken":
			var n := maxi(2, int(round(w / 1.2)))
			for i in n:
				var x := (float(i) + 0.5) / n * w
				var b := _stueck(F.kiste(Vector3(0.14, 0.16, d), 0.01, false), _balken_mat, Vector3(x, HOEHE - 0.08, d * 0.5))
				_decke.append(b)
		"stuck":
			for s in [[Vector3(w, 0.09, 0.09), Vector3(w * 0.5, HOEHE - 0.045, 0.045)], [Vector3(w, 0.09, 0.09), Vector3(w * 0.5, HOEHE - 0.045, d - 0.045)],
					[Vector3(0.09, 0.09, d), Vector3(0.045, HOEHE - 0.045, d * 0.5)], [Vector3(0.09, 0.09, d), Vector3(w - 0.045, HOEHE - 0.045, d * 0.5)]]:
				var st := _stueck(F.kiste(s[0], 0.03, false), _leiste_mat, s[1])
				_decke.append(st)


func _umgebung() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#101012")
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if forward else Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if forward:
		# AgX: Lichter laufen weich aus, kräftige Farben kippen nicht (ACES machte aus Orange Rot);
		# die Belichtung je Tageszeit ist darauf gerechnet (_werte_setzen).
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_white = 8.0
	else:
		# Filmic für den Kompatibilitäts-Rückfall (AgX wusch dort den Tag aus).
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 6.0
	# Glühen nur über Lampen (hohe Schwelle): warme Lampen mit leichtem Bloom. In Leicht übernehmen
	# die Lichtscheine an den Lampen (shaders/schein.gdshader) – fast ohne Kosten.
	env.glow_enabled = bool(stufe.get("glow", false))
	env.glow_intensity = 0.2 if forward else 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.0 if forward else 0.02
	env.glow_hdr_threshold = 2.1 if forward else 1.25
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if forward:
		for i in 7:
			env.set_glow_level(i, i in [1, 2, 4])
		# Globale Beleuchtung je Bild (SDFGI): in keiner Stufe mehr an – das Licht der Hülle ist gebacken
		# (lichtbacken.gd). Falls eine Stufe sie wieder will: kleine Zellen, Himmelslicht nur durchs Fenster.
		env.sdfgi_enabled = bool(stufe.get("gi", false))
		# Drei Kaskaden (0,1 m: 6,4 / 12,8 / 25,6 m um die Kamera) reichen für das größte Zimmer (10 × 10 m)
		# auch von oben; die vierte (51 m) enthielt nichts und kostete Proben je Bild.
		env.sdfgi_cascades = 3
		env.sdfgi_min_cell_size = 0.1
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.55
		env.sdfgi_read_sky_light = true
		env.sdfgi_energy = 1.0
		env.sdfgi_normal_bias = 1.1
		env.sdfgi_probe_bias = 1.1
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		# Umgebungsverdeckung und indirektes Licht im Bild: Kontakt unter Möbeln, in Ecken, an Kanten.
		env.ssao_enabled = bool(stufe.get("ssao", false))
		env.ssao_radius = 0.55
		env.ssao_intensity = 1.5
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.08
		env.ssao_sharpness = 0.98
		env.ssao_light_affect = 0.05
		env.ssil_enabled = bool(stufe.get("ssil", false))
		env.ssil_radius = 2.0
		env.ssil_intensity = 0.9
		env.ssil_sharpness = 0.98
		env.ssil_normal_rejection = 1.0
		# Reflexionen im Bild (Boden, Glas, Lack) – die Sonde füllt, was das Bild nicht sieht.
		env.ssr_enabled = bool(stufe.get("ssr", false))
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.2
		# Staub im Sonnenlicht als echter Volumen-Nebel (Ultra); sonst der Strahl als Fläche.
		env.volumetric_fog_enabled = bool(stufe.get("nebel", false))
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(1.0, 0.98, 0.95)
		env.volumetric_fog_anisotropy = 0.65
		env.volumetric_fog_length = 24.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_gi_inject = 0.4
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0
		# Keine Auto-Belichtung: Sie hob die Nacht wieder auf Tageshelligkeit (dunkles Bild → mehr
		# Belichtung) und machte die Belichtung unbestimmt – das Spielbild im Fernseher braucht die
		# genaue Belichtung, um sie auszugleichen (zimmer_welt.gd tv_ton). Die Belichtung je Tageszeit
		# steht in licht.gd ZEITEN.
	env.adjustment_enabled = true
	_lut = GradientTexture1D.new()
	_lut.width = 128
	_lut.gradient = Gradient.new()
	env.adjustment_color_correction = _lut
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if forward and bool(stufe.get("sonde", false)):
		_sonde = ReflectionProbe.new()
		_sonde.update_mode = ReflectionProbe.UPDATE_ONCE
		_sonde.size = Vector3(w + 0.4, HOEHE + 0.4, d + 0.4)
		_sonde.origin_offset = Vector3.ZERO
		_sonde.position = Vector3(w * 0.5, HOEHE * 0.5, d * 0.5)
		_sonde.box_projection = true
		_sonde.interior = true
		_sonde.enable_shadows = false
		_sonde.max_distance = maxf(w, d) * 2.5
		_sonde.intensity = 1.0
		_sonde.cull_mask = 0xFFFFF & ~(1 << 19)
		# Umgebungslicht im Raum vom Himmel (Farben von oben, der Seite und vom Boden je Tageszeit), nicht
		# aus der Aufnahme der Sonde: die gab jedem Punkt das volle Licht des Raums ohne Verdeckung – alles
		# hell und flach.
		_sonde.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		add_child(_sonde)
	# Kulisse für den Blick von oben: große Kugel um das Zimmer, innen sichtbar.
	var km := ShaderMaterial.new()
	km.shader = KULISSE_S
	km.set_shader_parameter("mitte", Vector3(w * 0.5, 0.0, d * 0.5))
	var kugel := SphereMesh.new()
	kugel.radius = 40.0
	kugel.height = 80.0
	kugel.radial_segments = 32
	kugel.rings = 16
	var k := MeshInstance3D.new()
	k.mesh = kugel
	k.material_override = km
	k.position = Vector3(w * 0.5, 0.0, d * 0.5)
	k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(k)


## Reflexionssonde sofort neu aufnehmen (lichtbacken.gd nach dem Backen; ohne licht_geaendert).
func sonde_jetzt() -> void:
	if _sonde == null or not is_inside_tree():
		return
	_sonde.visible = false
	_sonde.set_deferred("visible", true)


## Ist eine Fläche gerade ausgeblendet (von oben geschnitten, schnitt; beim Wandziehen weg)? Dann sieht
## die Backkamera sie nicht – ihre Karte wäre leer und die Fläche danach schwarz (lichtbacken.gd lässt
## sie dann aus und backt sie, sobald sie wieder da ist).
func ausgeblendet(flaeche: String) -> bool:
	var liste: Array = _decke if flaeche == "decke" else _waende.get(flaeche, [])
	for mi in liste:
		if is_instance_valid(mi) and mi is GeometryInstance3D and (mi as GeometryInstance3D).material_override in huellen_mats:
			var g := mi as GeometryInstance3D
			return not g.visible or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	return false


## Die Materialien der sechs Flächen (lichtbacken.gd): Name → ShaderMaterial.
func back_materialien() -> Dictionary:
	return { "boden": _boden_mat, "decke": _decke_mat, "hinten": _wand_mats.hinten, "vorn": _wand_mats.vorn,
		"links": _wand_mats.links, "rechts": _wand_mats.rechts }


## Reflexionssonde neu aufnehmen (Möbel oder Licht haben sich geändert), gesammelt nach einer
## halben Sekunde Ruhe: die Sonde rechnet den Raum sechsmal, das soll nicht jedes Bild passieren.
func sonde_neu() -> void:
	licht_geaendert.emit()
	if _sonde == null or not is_inside_tree():
		return
	# Neben dem laufenden Spiel nicht (sechs Durchgänge auf einmal): erst danach.
	if schlank:
		_sonde_offen = true
		return
	if _sonde_timer and _sonde_timer.time_left > 0.0:
		return
	_sonde_timer = get_tree().create_timer(0.5)
	_sonde_timer.timeout.connect(func() -> void:
		if is_instance_valid(_sonde) and _sonde.is_inside_tree():
			_sonde.visible = false
			_sonde.set_deferred("visible", true))


func _lichter() -> void:
	# Hauptlicht: Sonne bzw. Mond durchs Fenster – das einzige Licht mit echten Schatten.
	sonne = DirectionalLight3D.new()
	sonne.shadow_enabled = not leicht
	sonne.visible = not leicht
	sonne.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sonne.directional_shadow_max_distance = 12.0
	if forward:
		# Schatten ohne PCSS (light_angular_distance 0) und mit kleinem Filter: Die Engine dreht die
		# Proben weicher Schatten je Bildpunkt (Rauschen), ohne TAA blieb das als feine schräge
		# Schraffur auf Wänden und Tür stehen und kroch bei jeder Bewegung. Die Abstände (bias) wie
		# von der Engine vorgesehen – kleiner gab Streifen der Fläche auf sich selbst (Akne).
		sonne.shadow_blur = 1.0
		sonne.shadow_bias = 0.06
		sonne.shadow_normal_bias = 1.6
		sonne.light_angular_distance = 0.0
	else:
		sonne.shadow_blur = 2.2 if int(stufe.get("schatten", 0)) >= 4096 else 1.6
		sonne.shadow_bias = 0.04
		sonne.shadow_normal_bias = 1.4
		sonne.light_angular_distance = 1.2
	add_child(sonne)
	if not leicht:
		RenderingServer.directional_shadow_atlas_set_size(int(stufe.schatten), true)
	# Proben je Schattenkante: je Stufe und Upscaler (zimmer_basis.gd _forward_global).
	# Himmelslicht: kühles, weiches Licht, das durchs Fenster in den Raum fällt (ohne Schatten).
	himmelslicht = SpotLight3D.new()
	himmelslicht.position = Vector3(-0.6, 2.1, d * 0.5)
	himmelslicht.rotation_degrees = Vector3(-24, -90, 0)
	himmelslicht.spot_angle = 64.0
	himmelslicht.spot_range = 8.0
	himmelslicht.spot_attenuation = 1.1
	himmelslicht.spot_angle_attenuation = 1.8
	himmelslicht.light_specular = 0.15
	# Ohne Schatten: Das Himmelslicht ist weich und breit; sein stark gefilterter Schatten (blur 3)
	# lag als Rauschmuster auf der Wand gegenüber dem Fenster (Tür) und kostete einen Schattendurchgang.
	himmelslicht.shadow_enabled = false
	add_child(himmelslicht)
	# Bounce: der Sonnenfleck wirft warmes Licht zurück (Lage und Farbe in _werte_setzen).
	fuell = OmniLight3D.new()
	fuell.omni_range = 4.2
	fuell.omni_attenuation = 1.0
	fuell.light_specular = 0.0
	add_child(fuell)
	# Lichtstrahl im Fenster: weicher Fake (Form in _strahl_bauen).
	_strahl_mat = ShaderMaterial.new()
	_strahl_mat.shader = STRAHL_S
	_strahl = MeshInstance3D.new()
	_strahl.material_override = _strahl_mat
	_strahl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strahl.layers = EFFEKT_EBENE
	add_child(_strahl)


## Der Strahl: das Glas des Fensters, entlang der Sonnenrichtung bis zum Boden (oder zur
## gegenüberliegenden Wand) gezogen; vier Seiten, u läuft je Seite 0 … 1, v vom Fenster zum Ende.
func _strahl_bauen(dir: Vector3) -> void:
	_strahl_soll = dir
	_strahl.visible = bool(stufe.get("strahl", true)) and _himmel != null and not schlank
	if _staub and not _strahl.visible:
		_staub.visible = false
	if not _strahl.visible or dir.is_equal_approx(_strahl_dir):
		return
	_strahl_dir = dir
	var fz := d * 0.5
	var fb := float(fenster.breite)
	var fu := float(fenster.unten)
	var fo := float(fenster.oben)
	var ecken := [Vector3(0.02, fu, fz - fb * 0.5), Vector3(0.02, fu, fz + fb * 0.5), Vector3(0.02, fo, fz + fb * 0.5), Vector3(0.02, fo, fz - fb * 0.5)]
	var enden: Array = []
	for p: Vector3 in ecken:
		var l := 7.0
		if dir.y < -0.01:
			l = minf(l, maxf(p.y, 0.05) / -dir.y)
		if dir.x > 0.01:
			l = minf(l, (w - 0.05) / dir.x)
		enden.append(p + dir * l)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ecken[i]
		var b: Vector3 = ecken[(i + 1) % 4]
		var ea: Vector3 = enden[i]
		var eb: Vector3 = enden[(i + 1) % 4]
		var n := (b - a).cross(ea - a).normalized()
		for v in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [eb, Vector2(1, 1)], [a, Vector2(0, 0)], [eb, Vector2(1, 1)], [ea, Vector2(0, 1)]]:
			st.set_normal(n)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	_strahl.mesh = st.commit()
	_staub_bauen(ecken, enden)


## Staub im Lichtstrahl: ein paar Dutzend winzige helle Punkte, die langsam treiben – so hell wie der
## Strahl (nachts fast nichts). Nur in den Stufen mit Strahl.
func _staub_bauen(ecken: Array, enden: Array) -> void:
	if _staub == null:
		_staub_mat = StandardMaterial3D.new()
		_staub_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_staub_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_staub_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_staub_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_staub_mat.albedo_color = Color(1.0, 0.94, 0.82, 0.3)
		# Weiche runde Punkte (kein harter Pixel-Fleck).
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		var weich := GradientTexture2D.new()
		weich.gradient = gr
		weich.fill = GradientTexture2D.FILL_RADIAL
		weich.fill_from = Vector2(0.5, 0.5)
		weich.fill_to = Vector2(1.0, 0.5)
		weich.width = 16
		weich.height = 16
		_staub_mat.albedo_texture = weich
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.012)
		q.material = _staub_mat
		_staub = CPUParticles3D.new()
		_staub.mesh = q
		_staub.amount = 70
		_staub.lifetime = 9.0
		_staub.preprocess = 9.0
		_staub.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_staub.gravity = Vector3(0, -0.004, 0)
		_staub.direction = Vector3(0, 1, 0)
		_staub.spread = 180.0
		_staub.initial_velocity_min = 0.005
		_staub.initial_velocity_max = 0.03
		_staub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_staub.layers = EFFEKT_EBENE
		add_child(_staub)
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	for i in 4:
		a += ecken[i]
		b += enden[i]
	a /= 4.0
	b /= 4.0
	# Der mittlere Teil des Strahls (am Fenster und am Boden ist er schmal oder schon verblasst).
	_staub.position = a.lerp(b, 0.45)
	var lang := a.distance_to(b)
	_staub.emission_box_extents = Vector3(maxf(absf(b.x - a.x) * 0.4, 0.3), maxf(absf(b.y - a.y) * 0.4, 0.3), float(fenster.breite) * 0.4)
	_staub.visible = _strahl.visible and lang > 0.5


## Schlanker Weg neben dem laufenden Spiel (zimmer_welt.gd schlank_setzen): ohne Glühen (die Lichtscheine
## der Lampen bleiben), SSAO, SSIL, SSR, GI und Volumen-Nebel, ohne Lichtstrahl und Staub, weniger Regen
## und Schnee, die Reflexionssonde nimmt nicht neu auf (wenn nötig, danach). Aus: wie die Stufe es will.
func schlank_setzen(an: bool) -> void:
	if an == schlank:
		return
	schlank = an
	if env:
		env.glow_enabled = bool(stufe.get("glow", false)) and not an
		if forward:
			env.ssao_enabled = bool(stufe.get("ssao", false)) and not an
			env.ssil_enabled = bool(stufe.get("ssil", false)) and not an
			env.ssr_enabled = bool(stufe.get("ssr", false)) and not an
			env.sdfgi_enabled = bool(stufe.get("gi", false)) and not an
			env.volumetric_fog_enabled = bool(stufe.get("nebel", false)) and not an
	if is_instance_valid(_strahl):
		if an:
			_strahl.visible = false
			if _staub:
				_staub.visible = false
		elif _strahl_soll != Vector3.ZERO:
			_strahl_dir = Vector3.ZERO
			_strahl_bauen(_strahl_soll)
	if _wetter_knoten and _wetter_knoten.get_child_count() > 0:
		_wetter_bauen()
	if not an and _sonde_offen:
		_sonde_offen = false
		sonde_neu()


## Regen oder Schnee draußen vor dem Fenster (nur dort zu sehen): schlichte Teilchen, wenig Arbeit.
func _wetter_bauen() -> void:
	for c in _wetter_knoten.get_children():
		c.queue_free()
	if wetter not in ["regen", "schnee"] or _himmel == null:
		return
	var p := CPUParticles3D.new()
	p.layers = EFFEKT_EBENE
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var regen := wetter == "regen"
	p.amount = (160 if leicht else 420) if regen else (120 if leicht else 300)
	if schlank:
		p.amount = mini(p.amount, 140 if regen else 100)
	p.lifetime = 1.1 if regen else 6.0
	p.preprocess = p.lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.2, 0.1, float(fenster.breite) * 0.5 + 1.6)
	p.position = Vector3(-2.6, 3.6, d * 0.5)
	p.direction = Vector3(0.15, -1, 0) if regen else Vector3(0.1, -1, 0.05)
	p.spread = 4.0 if regen else 25.0
	p.gravity = Vector3(0, -2.0, 0) if regen else Vector3(0, -0.05, 0)
	p.initial_velocity_min = 5.5 if regen else 0.35
	p.initial_velocity_max = 7.0 if regen else 0.6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.82, 0.86, 0.92, 0.35) if regen else Color(1, 1, 1, 0.9)
	var mesh: Mesh
	if regen:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.22, 0.006)
		mesh = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.014
		sm.height = 0.028
		sm.radial_segments = 6
		sm.rings = 3
		mesh = sm
	mesh.surface_set_material(0, m)
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wetter_knoten.add_child(p)


# --- Gestaltung -----------------------------------------------------------------------------------

## Farben und Materialien aus den Daten des Raums; weich: Farben gleiten in den neuen Stand.
func setze_gestalt(g: Dictionary, weich := true) -> void:
	_gestalt = g
	var waende: Dictionary = g.get("waende", {})
	for s in G.SEITEN:
		var wd: Dictionary = waende.get(s, G.std_wand())
		var m: ShaderMaterial = _wand_mats[s]
		var art: int = WAND_ARTEN.get(str(wd.get("m", "anstrich")), 0)
		m.set_shader_parameter("art", art)
		S.textur_setzen(m, WAND_TEXTUR.get(art, "putz"))
		m.set_shader_parameter("paneel", 0.0)
		m.set_shader_parameter("muster", G.muster_nr(str(wd.get("mu", ""))) if art == 2 else 0)
		var f := Color(str(wd.get("f", "#e8e0d1")))
		var mf_s := str(wd.get("mf", ""))
		var mf := Color(mf_s) if mf_s != "" else (Color("#76866a") if art == 3 else (f.darkened(0.22) if f.get_luminance() > 0.4 else f.lightened(0.3)))
		_weich(m, "farbe", f, weich)
		_weich(m, "muster_farbe", mf, weich)
		_weich(m, "paneel_farbe", mf, weich)
	var b: Dictionary = g.get("boden", {})
	var ba: Array = BODEN_ARTEN.get(str(b.get("a", "dielen")), BODEN_ARTEN.dielen)
	var bf := Color(str(b.get("f", "#c29466")))
	var f2s := str(b.get("f2", ""))
	var zweit := Color(f2s) if f2s != "" else Color(str(G.BODEN_STD2.get(str(b.get("a", "")), "#d2c9bc")))
	_boden_mat.set_shader_parameter("art", int(ba[0]))
	S.textur_setzen(_boden_mat, BODEN_TEXTUR.get(int(ba[0]), "dielen"))
	_boden_mat.set_shader_parameter("diele", float(ba[1]))
	_boden_mat.set_shader_parameter("glanz", float(ba[2]))
	_weich(_boden_mat, "hell", bf, weich)
	_weich(_boden_mat, "dunkel", bf.darkened(float(ba[3])), weich)
	_weich(_boden_mat, "zweit", zweit, weich)
	var dk: Dictionary = g.get("decke", {})
	var dc := Color(str(dk.get("f", "#efebe4")))
	_weich(_decke_mat, "farbe", dc, weich)
	_decke_mat.set_shader_parameter("art", 4 if str(dk.get("a", "")) == "holz" else 0)
	S.textur_setzen(_decke_mat, "holz_hell" if str(dk.get("a", "")) == "holz" else "putz", 0.6 if str(dk.get("a", "")) == "holz" else 1.0)
	_weich_std(_leiste_mat, Color(str(g.get("sockel", {}).get("f", "#f1ede6"))), weich)
	var fe: Dictionary = g.get("fenster", {})
	_weich_std(_rahmen_mat, Color(str(fe.get("rf", "#f3f0ea"))), weich)
	_weich(_vorhang_mat, "farbe", Color(str(fe.get("vf", "#e4d9c6"))), weich)
	_weich(_rollo_mat, "farbe", Color(str(fe.get("vf", "#e4d9c6"))), weich)
	var tf := Color(str(g.get("tuer", {}).get("f", "#efebe4")))
	_weich_std(_tuer_mat, tf, weich)
	# Neue Farben: neu backen (licht_geaendert), die Sonde nimmt sie auf (Glanz).
	sonde_neu()


func _weich(m: ShaderMaterial, param: String, ziel: Variant, weich: bool) -> void:
	var jetzt: Variant = m.get_shader_parameter(param)
	if not weich or jetzt == null or not is_inside_tree():
		m.set_shader_parameter(param, ziel)
		return
	var tw := create_tween()
	tw.tween_property(m, "shader_parameter/" + param, ziel, WEICH).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _weich_std(m: StandardMaterial3D, ziel: Color, weich: bool) -> void:
	if not weich or not is_inside_tree():
		m.albedo_color = ziel
		return
	create_tween().tween_property(m, "albedo_color", ziel, WEICH).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Licht: Tageszeit, Wetter -----------------------------------------------------------------------

## Welche Tageszeit gerade gilt („auto“ nach der Uhr des PCs).
static func zeit_jetzt(wahl: String, stunde := -1) -> String:
	if wahl != "auto" and ZEITEN.has(wahl):
		return wahl
	var h := stunde if stunde >= 0 else int(Time.get_time_dict_from_system().hour)
	if h >= 5 and h < 9:
		return "morgen"
	if h >= 9 and h < 17:
		return "tag"
	if h >= 17 and h < 21:
		return "abend"
	return "nacht"


## Tageszeit und Wetter aus dem Licht des Raums (gestalt.gd); weich: das Licht gleitet hinüber.
func setze_licht(l: Variant, weich := true) -> void:
	var ld: Dictionary = l if l is Dictionary else { "z": str(l) }
	_stimmung = Licht.stimmung({ "licht": ld })
	zeit = zeit_jetzt(str(ld.get("z", "auto")))
	var we := str(ld.get("we", "klar"))
	if not WETTER.has(we):
		we = "klar"
	if we != wetter:
		wetter = we
		_wetter_bauen()
	var ziel := _ziel_werte(zeit, wetter)
	if _licht_tw and _licht_tw.is_valid():
		_licht_tw.kill()
	if not weich or not is_inside_tree():
		_werte_setzen(ziel)
		return
	var start := _jetzt_werte()
	_licht_tw = create_tween()
	_licht_tw.tween_method(func(t: float) -> void: _werte_setzen(_mischen(start, ziel, t)), 0.0, 1.0, WEICH_LICHT).set_trans(Tween.TRANS_SINE).set_ease(
			Tween.EASE_IN_OUT)


## Zielwerte für Tageszeit und Wetter: das Licht-Konzept aus licht.gd ZEITEN, das Wetter dämpft
## die Sonne, färbt den Himmel grau und macht das Umgebungslicht weicher.
func _ziel_werte(z_id: String, we: String) -> Dictionary:
	var z: Dictionary = ZEITEN[z_id]
	var wt: Dictionary = WETTER[we]
	var grau := Color(str(wt.grau))
	var gk: float = wt.grau_k
	var nacht := z_id == "nacht"
	var oben := Color(str(z.oben)).lerp(grau * (0.35 if nacht else 1.0), gk)
	var hor := Color(str(z.horizont)).lerp(grau * (0.4 if nacht else 1.0), gk)
	var sf := Color(str(z.sonne)).lerp(Color(0.85, 0.88, 0.92), gk * 0.6)
	var huegel := Color(str(z.huegel)).lerp(Color(0.92, 0.94, 0.97) * (0.35 if nacht else 1.0), float(wt.weiss))
	var dunst: float = wt.dunst
	var hell_draussen: float = (1.25 if z_id == "tag" else 1.1) * float(wt.hell)
	var wolken: float = float(wt.wolken) if float(wt.wolken) >= 0.0 else (0.25 if nacht else 0.6)
	var se := float(z.sonne_e) * float(wt.sonne)
	var trueb := grau * (0.3 if nacht else 0.75)
	return {
		"sonne_farbe": sf, "sonne_e": se,
		"sonne_rot": Vector3(-float(z.hoch), -90.0 + float(z.seite), 0),
		"himmel_farbe": Color(str(z.himmel)).lerp(Color(0.86, 0.89, 0.93), gk * 0.5), "himmel_e": float(z.himmel_e) * 1.6 * float(wt.himmel),
		"bounce": float(z.bounce), "strahl": float(z.strahl) * se * (1.0 + dunst * 0.6),
		"sky_oben": Color(str(z.decke)).lerp(trueb, gk * 0.4), "sky_hor": Color(str(z.wand)).lerp(trueb, gk * 0.3),
		"sky_boden": Color(str(z.boden)),
		"amb": float(z.amb) * lerpf(1.0, 1.2, gk),
		"belichtung": float(z.belichtung if forward else z.get("belichtung_kompat", z.belichtung)) * float(_stimmung.belichtung) * 1.12,
		"kontrast": float(_stimmung.kontrast), "saettigung": float(_stimmung.saettigung) * lerpf(1.0, 0.9, gk),
		"tief": Color(str(z.tief)), "spitze": Color(str(z.spitze)).lerp(Color.WHITE, gk * 0.5),
		"lampen": float(z.lampen) * lerpf(1.0, 1.15, gk),
		"h_oben": oben, "h_hor": hor, "h_sonne_farbe": sf * (1.0 - gk * 0.8),
		"h_groesse": 0.035 if not nacht else 0.022,
		"h_nacht": float(z.nacht) * (1.0 - gk), "h_nah": huegel.lerp(hor, dunst * 0.7), "h_fern": huegel.lerp(hor, 0.45 + dunst * 0.5),
		"h_hell": hell_draussen, "h_wolken": wolken, "glas": hor.lerp(oben, 0.45) * (0.6 if nacht else 1.0),
	}


func _jetzt_werte() -> Dictionary:
	var g := _lut.gradient
	return {
		"sonne_farbe": sonne.light_color, "sonne_e": sonne.light_energy, "sonne_rot": sonne.rotation_degrees,
		"himmel_farbe": himmelslicht.light_color, "himmel_e": himmelslicht.light_energy,
		"bounce": float(get_meta("bounce", 0.3)),
		"strahl": float(_strahl_mat.get_shader_parameter("staerke")) / _strahl_k() if _strahl_mat.get_shader_parameter("staerke") != null else 0.0,
		"sky_oben": _sky.sky_top_color, "sky_hor": _sky.sky_horizon_color, "sky_boden": _sky.ground_bottom_color,
		"amb": himmel_backen / float(GEBACKEN.amb) if _gebacken() else env.ambient_light_energy,
		"belichtung": env.tonemap_exposure,
		"kontrast": env.adjustment_contrast, "saettigung": env.adjustment_saturation,
		"tief": get_meta("tief", Color.BLACK), "spitze": g.colors[g.colors.size() - 1] if g.colors.size() > 0 else Color.WHITE,
		"lampen": lampen_faktor,
		"h_oben": _himmel_param("oben", Color.BLACK), "h_hor": _himmel_param("horizont", Color.BLACK),
		"h_sonne_farbe": _himmel_param("sonne_farbe", Color.BLACK),
		"h_groesse": _himmel_param("sonne_groesse", 0.03), "h_nacht": _himmel_param("nacht", 0.0),
		"h_nah": _himmel_param("huegel_nah", Color.BLACK), "h_fern": _himmel_param("huegel_fern", Color.BLACK),
		"h_hell": _himmel_param("hell", 1.0), "h_wolken": _himmel_param("wolken", 0.5), "glas": _glas_oben.albedo_color,
	}


## Stärke des Lichtstrahls im Fenster je Stufe (Ultra halb, _werte_setzen).
func _strahl_k() -> float:
	return 0.5 if str(stufe.get("stufe", "")) == "ultra" else 1.0


## Forward+ ohne SDFGI: Licht der Hülle gebacken (lichtbacken.gd), Umgebung und Himmelslicht gedämpft.
func _gebacken() -> bool:
	return forward and not bool(stufe.get("gi", false))


func _himmel_param(k: String, std: Variant) -> Variant:
	var v: Variant = _himmel_mat.get_shader_parameter(k)
	return v if v != null else std


static func _mischen(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in b.keys():
		var va: Variant = a.get(k, b[k])
		var vb: Variant = b[k]
		if typeof(va) != typeof(vb):
			out[k] = vb
		elif va is Color:
			out[k] = (va as Color).lerp(vb, t)
		elif va is float:
			out[k] = lerpf(va, vb, t)
		elif va is Vector2:
			out[k] = (va as Vector2).lerp(vb, t)
		elif va is Vector3:
			out[k] = (va as Vector3).lerp(vb, t)
		else:
			out[k] = vb
	return out


func _werte_setzen(v: Dictionary) -> void:
	sonne.light_color = v.sonne_farbe
	sonne.light_energy = v.sonne_e
	# Die Sonne steht draußen links vor dem Fenster und scheint schräg hinein.
	sonne.rotation_degrees = v.sonne_rot
	var dir := Basis.from_euler(sonne.rotation) * Vector3(0, 0, -1)
	var fenster_da := _himmel != null
	himmelslicht.light_color = v.himmel_farbe
	var gi := forward and bool(stufe.get("gi", false))
	# Gebacken (Forward+, lichtbacken.gd): Umgebung, Himmelslicht und Abprall gedämpft wie mit globaler
	# Beleuchtung, nur etwas weniger (die Karten tragen keinen vollen Abprall) – der Raum behält Tiefe.
	var gb: Dictionary = GEBACKEN if _gebacken() else { "amb": 0.8, "himmel": 1.0, "fuell": 1.0 }
	himmelslicht.light_energy = (float(v.himmel_e) * (0.7 if gi else float(gb.himmel))) if fenster_da else 0.0
	# Umgebung als Himmel von oben (Decke), von der Seite (Wände) und von unten (Boden): ein
	# günstiges Bounce-Licht, das Schattenseiten nicht schwarz, sondern farbig hält.
	_sky.sky_top_color = v.sky_oben
	_sky.sky_horizon_color = v.sky_hor
	_sky.ground_horizon_color = (v.sky_hor as Color).lerp(v.sky_boden, 0.5)
	_sky.ground_bottom_color = v.sky_boden
	_sky.sky_curve = 0.25
	_sky.ground_curve = 0.15
	_sky.sky_energy_multiplier = 1.0
	if _gebacken():
		# Gebacken: Der Himmel zählt als Umgebung nur zum Teil. Die Engine wiegt ihn allein über
		# ambient_light_sky_contribution; der Rest ist die feste Farbe – hier der Abprall der Lampen.
		himmel_backen = clampf(float(v.amb) * float(gb.amb), 0.0, 1.0)
		env.ambient_light_sky_contribution = himmel_backen * float(gb.amb_moebel)
		env.ambient_light_color = ABPRALL_FARBE
		env.ambient_light_energy = ABPRALL_LAMPEN * _lampen_summe
	else:
		# Mit SDFGI liefert das Licht selbst die Umgebung; der Himmel bleibt nur als leiser Grund.
		env.ambient_light_energy = float(v.amb) * (0.22 if gi else float(gb.amb))
		env.ambient_light_sky_contribution = 1.0
	env.tonemap_exposure = float(v.belichtung)
	env.adjustment_contrast = v.kontrast
	env.adjustment_saturation = v.saettigung
	_lut_setzen(v.tief, v.spitze)
	_decke_mat.set_shader_parameter("eigen", 0.0)
	lampen_faktor = v.lampen
	# Bounce: vom Sonnenfleck auf dem Boden, in dessen Farbe, zurück in den Raum.
	set_meta("bounce", v.bounce)
	var mitte := Vector3(0.0, (float(fenster.unten) + float(fenster.oben)) * 0.5, d * 0.5)
	var fleck := mitte + dir * (mitte.y / maxf(-dir.y, 0.05))
	var bf := _boden_farbe()
	fuell.position = Vector3(clampf(fleck.x, 0.4, w - 0.4), 0.35, clampf(fleck.z, 0.4, d - 0.4))
	fuell.light_color = (bf * v.sonne_farbe).lerp(v.sonne_farbe, 0.25)
	# Mit SDFGI kommt das Zurückwerfen echt; der Fülltropfen bleibt nur ein Hauch.
	fuell.light_energy = (float(v.sonne_e) * float(v.bounce) * (0.2 if gi else float(gb.fuell))) if fenster_da else 0.0
	# Sonnenfleck im Shader nur ohne echte Sonne (Stufe Leicht).
	for m: ShaderMaterial in huellen_mats:
		m.set_shader_parameter("fleck_farbe", (v.sonne_farbe as Color) * float(v.sonne_e) * 0.85 if leicht and fenster_da else Color.BLACK)
		m.set_shader_parameter("fleck_dir", dir)
		# Relief auf gebackenem Licht (lichter.gdshaderinc uz_relief): wie stark die Sonne zählt.
		m.set_shader_parameter("relief_sonne", float(v.sonne_e) if forward and fenster_da and not leicht else 0.0)
	_strahl_bauen(dir)
	# Volumen-Nebel (Ultra): die Sonne zeichnet den Strahl selbst.
	sonne.light_volumetric_fog_energy = 1.0 if bool(stufe.get("nebel", false)) else 0.0
	_strahl_mat.set_shader_parameter("farbe", (v.sonne_farbe as Color).lerp(Color.WHITE, 0.15))
	# Ultra zeigte den Strahl früher als Volumen-Nebel – zart; als Fläche halb so stark, sonst lag am Tag
	# ein heller Schleier über der Fensterseite.
	var strahl := float(v.strahl) * _strahl_k()
	_strahl_mat.set_shader_parameter("staerke", strahl)
	if _staub_mat:
		_staub_mat.albedo_color.a = clampf(strahl * 0.7, 0.0, 0.35)
	# Himmel vor dem Fenster: Sonne bzw. Mond an der Stelle, aus der das Licht kommt.
	_himmel_mat.set_shader_parameter("oben", v.h_oben)
	_himmel_mat.set_shader_parameter("horizont", v.h_hor)
	_himmel_mat.set_shader_parameter("sonne_farbe", v.h_sonne_farbe)
	# Sonne bzw. Mond draußen dort, woher das Licht kommt (seitlich, Höhe etwas flacher: sonst stünde
	# sie fast immer über dem Fensterrahmen).
	var zur_sonne := -dir
	_himmel_mat.set_shader_parameter("sonne", Vector2(atan2(zur_sonne.z, -zur_sonne.x), asin(clampf(zur_sonne.y, -1.0, 1.0)) * 0.55))
	_himmel_mat.set_shader_parameter("sonne_groesse", v.h_groesse)
	_himmel_mat.set_shader_parameter("nacht", v.h_nacht)
	_himmel_mat.set_shader_parameter("huegel_nah", v.h_nah)
	_himmel_mat.set_shader_parameter("huegel_fern", v.h_fern)
	_himmel_mat.set_shader_parameter("hell", v.h_hell)
	_himmel_mat.set_shader_parameter("wolken", v.h_wolken)
	_glas_oben.albedo_color = v.glas
	lampen_geaendert.emit()
	sonde_neu()


## Stärke aller brennenden Lampen (zimmer_welt.gd, auch beim Flimmern des Fernsehers): Abprall auf
## Möbel und Figur (ABPRALL_LAMPEN).
func lampen_abprall(summe: float) -> void:
	_lampen_summe = summe
	if not _gebacken() or env == null:
		return
	var e := ABPRALL_LAMPEN * summe
	if not is_equal_approx(env.ambient_light_energy, e):
		env.ambient_light_energy = e


## Mittlere Farbe des Bodens (für den Bounce).
func _boden_farbe() -> Color:
	var h: Variant = _boden_mat.get_shader_parameter("hell")
	var dk: Variant = _boden_mat.get_shader_parameter("dunkel")
	if h is Color and dk is Color:
		return (h as Color).lerp(dk, 0.5)
	return Color("#a87f58")


## Farbkorrektur als Kurve je Farbkanal: Schatten leicht in die Farbe der Tageszeit (kühl),
## Lichter leicht warm, die Mitte bleibt neutral. Schwarz bleibt schwarz (früher hob die Kurve es
## in die Farbe der Tageszeit an – das Bild wirkte milchig).
func _lut_setzen(tief: Color, spitze: Color) -> void:
	# Unverändert (Wetter oder Stimmung gleiten, die Tageszeit bleibt): nichts neu rechnen – die Kurve
	# rückwärts kostet 0,8 ms, und das Licht gleitet 0,8 s lang in jedem Bild hierher.
	var g := _lut.gradient
	if g.colors.size() == 5 and tief.is_equal_approx(get_meta("tief", Color(-1, 0, 0))) and spitze.is_equal_approx(g.colors[4]):
		return
	set_meta("tief", tief)
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([
		Color.BLACK, Color(0.18, 0.18, 0.18).lerp(tief * 1.6, 0.18), Color(0.5, 0.5, 0.5),
		Color(0.82, 0.82, 0.82).lerp(spitze * 0.82, 0.5), spitze])
	_lut_umkehr_bauen()


## Die Kurve rückwärts (je Kanal, 256 Stützstellen): Damit gleicht der Bildschirm des Fernsehers
## die Farbkorrektur aus (bildschirm.gdshader). Gerechnet wie die Engine die Kurve liest (Textur
## mit _lut.width Punkten, linear gefiltert); die Kurve steigt in jedem Kanal, also Halbierung.
func _lut_umkehr_bauen() -> void:
	var n := 512
	var tw := float(_lut.width)
	var vor: Array[Color] = []
	for i in n + 1:
		var x := float(i) / n
		vor.append(_lut.gradient.sample(clampf((x * tw - 0.5) / (tw - 1.0), 0.0, 1.0)))
	if _lut_umkehr_bild == null:
		_lut_umkehr_bild = Image.create(256, 1, false, Image.FORMAT_RGBF)
	for j in 256:
		var y := (float(j) + 0.5) / 256.0
		var c := Color(0, 0, 0)
		for k in 3:
			var lo := 0
			var hi := n
			while hi - lo > 1:
				var m := (lo + hi) >> 1
				if vor[m][k] < y:
					lo = m
				else:
					hi = m
			var a: float = vor[lo][k]
			var b: float = vor[hi][k]
			var t := clampf((y - a) / maxf(b - a, 0.00001), 0.0, 1.0) if y > a else 0.0
			c[k] = (float(lo) + t) / n
		_lut_umkehr_bild.set_pixel(j, 0, c)
	if lut_umkehr == null:
		lut_umkehr = ImageTexture.create_from_image(_lut_umkehr_bild)
	else:
		lut_umkehr.update(_lut_umkehr_bild)


## Lampen für die Hülle (lichter.gdshaderinc): Liste aus zimmer_welt.gd (lampen_auffrischen).
func lampen_setzen(n: int, pos: PackedVector4Array, farbe: PackedVector4Array, dir: PackedVector4Array) -> void:
	for m: ShaderMaterial in huellen_mats:
		m.set_shader_parameter("lampen_n", n)
		m.set_shader_parameter("lampe_pos", pos)
		m.set_shader_parameter("lampe_farbe", farbe)
		m.set_shader_parameter("lampe_dir", dir)


## Kontaktschatten der Möbel (Karte von oben, siehe zimmer_welt.gd).
func setze_ao(tex: Texture2D) -> void:
	_boden_mat.set_shader_parameter("ao_karte", tex)


## Von oben: Wände zwischen Kamera und Raum (und die Decke) ausblenden, Schatten bleiben.
func schnitt(kamera: Vector3, an: bool) -> void:
	var weg := {
		"hinten": an and kamera.z < 0.0, "vorn": an and kamera.z > d,
		"links": an and kamera.x < 0.0, "rechts": an and kamera.x > w,
	}
	for seite in _waende.keys():
		for mi in _waende[seite]:
			if not is_instance_valid(mi):
				continue
			if (mi as Node).has_meta("uz_backschatten"):
				# Wehender Vorhang (Forward+): wirft im laufenden Bild keinen Schatten – ausblenden statt
				# „nur Schatten“.
				(mi as Node3D).visible = not weg[seite]
			else:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if weg[
						seite] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_instance_valid(_gardine):
		_gardine.visible = not weg.links
	for mi in _decke:
		if is_instance_valid(mi):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if an else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Der Himmel draußen ist eine Kulisse fürs Fenster: von oben würde er als Wand dastehen. Dann
	# leuchtet das Glas selbst sanft in der Farbe des Himmels.
	if _himmel:
		_himmel.visible = not an
	if _glas:
		_glas.material_override = _glas_oben if an else _glas_innen
	_wetter_knoten.visible = not an
	_strahl_mat.set_shader_parameter("oben", 1.0 if an else 0.0)

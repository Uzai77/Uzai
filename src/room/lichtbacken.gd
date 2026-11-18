extends Node
## Gebackenes Licht der Raumhülle (Forward+): Boden, Decke und die vier Wände bekommen ihr Licht aus
## Lichtkarten, die das Zimmer selbst rechnet, wenn sich etwas ändert (Möbel, Lampen, Tageszeit, Wetter,
## Form) – wie früher in Spielen vorberechnetes Licht, nur zur Laufzeit gebacken. Im laufenden Bild
## kostet die Hülle dann nur zwei Texturzugriffe statt Lampen mit Schattenproben und globaler
## Beleuchtung je Bildpunkt (die echten Lichter leuchten nur noch Möbel und Figur, nicht die Hülle).
##
## Wie gebacken wird (auf der Grafikkarte, mit der Engine selbst): Je Fläche schaut eine orthografische
## Kamera in einer eigenen kleinen 3D-Ansicht (SubViewport, HDR) senkrecht auf die Fläche, mit Nah- und
## Fernebene knapp davor und dahinter – sie sieht nur die Fläche selbst. Die Hüllen-Shader erkennen diese
## Kamera an einer Lücke in ihren Ebenen (BACK_LUECKE fehlt in CAMERA_VISIBLE_LAYERS; jede andere
## Kamera, Sonde und Schattenansicht sieht alle Ebenen) und zeigen dann nur, wie viel Licht
## ankommt (weiß, matt, ohne Eigenlicht); das ist die Lichtkarte. Beleuchtet wird sie von Kopien aller
## Lichter (Lampen, Sonne bzw. Mond, Himmelslicht, Abprall), die nur die Hülle treffen und beim Backen
## mit weichen Schatten in hoher Qualität rechnen – mehr Lampen mit Schatten (BACK_LAMPEN), als im
## laufenden Bild bezahlbar wären; MSAA glättet die Kanten, die höchste Filterstufe der Engine die
## Schatten (SCHATTEN_QUALITAET, gilt im ganzen Zimmer) (ohne TAA: dessen Verlauf hielt das Licht früherer Backvorgänge zu zwei Dritteln fest – die
## Karten wurden nie ganz neu). Die Sonne ist dabei ein Strahler vor dem Fenster (_sonne_als_strahler), im laufenden Bild
## auch (_sonne_laufzeit): dessen Schatten rechnet die Engine nur neu, wenn sich etwas bewegt.
## Umgebungslicht: der Himmel des Raums (Farben von oben, der Seite und vom Boden je Tageszeit, raum.gd)
## und der warme Abprall vom Sonnenfleck (fuell). Nach dem Backen nimmt die Reflexionssonde den neu
## beleuchteten Raum auf (Glanz für Boden und Möbel).
##
## Zwei Sätze Karten (A, B): gebacken wird je Fläche in den, der gerade nicht zu sehen ist, dann blenden
## die Shader in BLENDE_S weich über (lm_mix). Vor dem ersten Backen (oder nach einer neuen Größe) leuchten
## die Kopien der Lichter die Hülle im laufenden Bild (lm_an = 0), danach nicht mehr.
##
## Ausgeblendete Flächen (von oben geschnittene Wände und die Decke, raum.gd schnitt: „nur Schatten“)
## sieht die Backkamera nicht – ihre Karte wäre leer und die Wand danach schwarz (so wurden nach einer
## neuen Raumgröße im Bau-Menü manchmal ganze Wände schwarz). Sie werden ausgelassen und behalten ihre
## bisherige Karte (ohne Karte: die Kopien der Lichter); sobald sie wieder zu sehen sind, wird nachgebacken.
##
## Shader-Seite: shaders/lichter.gdshaderinc (uz_backen, uz_lm, uz_lm_anteil), wand.gdshader, boden.gdshader.

const Zustand := preload("res://src/core/zustand.gd")

## Ebene, die nur den Backkameras fehlt (kein Knoten liegt darauf; die Shader fragen sie ab). Eine
## Ebene, die nur sie hätten, ginge nicht: Kameras kennen nur 20 Ebenen, und Sonden und Schattenansichten
## sehen alle.
const BACK_LUECKE := 1 << 17
const HUELLE_EBENE := 4            ## raum.gd HUELLE_EBENE
const EFFEKT_EBENE := 1 << 16      ## raum.gd EFFEKT_EBENE (Strahl, Staub, Regen: beim Backen unsichtbar)
const FLAECHEN := ["boden", "decke", "hinten", "vorn", "links", "rechts"]
const ABSTAND := 0.5               ## Kamera so weit vor der Fläche
## Sichtbar für die Backkamera: von 0,5 mm vor der Fläche (Kabel und Teppiche auf dem Boden, Bilder an
## der Wand liegen darüber und färbten sonst die Karte) bis 1 cm dahinter.
const NAH := 0.0005
const FERN := 0.01
## Sonne: Strahler so weit vor dem Fenster (fast parallel). Weiter weg wächst der Abstand, den die
## Schattentiefe der Engine als „davor“ gelten lässt, mit dem Quadrat – das Licht kam durch die Wand.
const SONNE_WEIT := 8.0
const WARTEN_S := 0.25             ## Änderungen kommen in Schüben: so lange Ruhe, dann backen …
const SPAETESTENS_S := 1.0         ## … aber spätestens nach so langer Zeit
const BLENDE_S := 0.45
const BACK_LAMPEN := 4             ## so viele Lampen werfen beim Backen Schatten (die kräftigsten)
## Je Stufe: [Kantenlänge eines Kartenpunkts in m, Schattenatlas der Backansicht, MSAA]. Gebacken wird in
## BACK_BILDER Bildern (das erste rechnet die Schatten, danach steht alles).
const QUALITAET := {
	"ultra": [0.02, 4096, Viewport.MSAA_4X], "hoch": [0.03, 4096, Viewport.MSAA_4X],
	"mittel": [0.04, 2048, Viewport.MSAA_2X], "leicht": [0.06, 2048, Viewport.MSAA_2X],
}
const BACK_BILDER := 2

## Offen getypt (Node3D statt Raum): logic_zgrafik unterschiebt eine eigene Hülle.
var huelle: Node3D                 ## raum.gd
var stufe := "mittel"
var sonne_backen := true           ## Sonne bzw. Mond mitbacken (Leicht: der Sonnenfleck kommt aus dem Shader)
## Filterstufe weicher Schatten beim Backen – und im ganzen Zimmer (zimmer_basis.gd _forward_global): Jeder
## Aufruf der Engine dafür (auch mit demselben Wert) verwirft alle Pipelines aller 3D-Shader – früher
## zweimal je Backen; danach wurde jede Fläche beim Zeichnen neu übersetzt, und das Bild wartete.
const SCHATTEN_QUALITAET := RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
static var _qualitaet_jetzt := -1  ## zuletzt gesetzte Filterstufe (-1: wie im Projekt)
var gebacken := 0                  ## fertige Backvorgänge (Proben, launch.log)
var letzte_ms := 0.0               ## Dauer des letzten Backens (Wanduhr, über alle Bilder)

var _saetze: Array = [[], []]      ## je Satz: [{ name, vp, cam, u, v }]
var _zeigt := {}                   ## Fläche → Satz, der zu sehen ist (-1: keiner, die Kopien leuchten sie)
var _ziele := {}                   ## beim Backen: Fläche → Satz, in den gebacken wird (nur sichtbare Flächen)
var _ausgelassen: Array = []       ## beim letzten Backen ausgeblendete Flächen (nachbacken, wenn sie wieder da sind)
## Gebackenes Licht: ruhe, nach einer Änderung warten (WARTEN_S Ruhe, spätestens SPAETESTENS_S), backen
## (BACK_BILDER Bilder); kam beim Backen etwas dazu, gleich wieder warten.
const ZUSTAENDE := { "ruhe": ["warten"], "warten": ["backen"], "backen": ["ruhe", "warten"] }
var _zustand := "ruhe":
	set(neu):
		Zustand.wechsel("zimmer.lichtbacken", ZUSTAENDE, _zustand, neu)
		_zustand = neu
var _warte := 0.0
var _seit := 0.0
var _bilder := 0
var _nochmal := false
var _masse := Vector3.ZERO         ## Größe des Raums, für die die Sätze gebaut sind
var _kopien: Node3D                ## Kopien der Lichter (nur Hülle)
var _env: Environment
var _tw: Tween
var _start_ms := 0
var _mats := {}                    ## Fläche → ShaderMaterial
var _laufzeit_sonne: SpotLight3D   ## die Sonne im laufenden Bild (_sonne_laufzeit)


func _ready() -> void:
	_kopien = Node3D.new()
	_kopien.name = "Backlichter"
	add_child(_kopien)
	_env = Environment.new()
	set_process(true)


## Etwas hat sich geändert (Möbel, Lampen, Licht, Form): bald neu backen.
func anstossen() -> void:
	match _zustand:
		"ruhe":
			_zustand = "warten"
			_warte = 0.0
			_seit = 0.0
		"warten":
			_warte = 0.0
		"backen":
			_nochmal = true


func _process(dt: float) -> void:
	_sonne_laufzeit()
	if _zustand == "ruhe" and not _ausgelassen.is_empty():
		for name: String in _ausgelassen:
			if not _versteckt(name):
				anstossen()
				break
	match _zustand:
		"warten":
			_warte += dt
			_seit += dt
			if _warte >= WARTEN_S or _seit >= SPAETESTENS_S:
				_beginnen()
		"backen":
			_bilder += 1
			if _bilder >= BACK_BILDER:
				_beenden()


## Filterstufe weicher Schatten (Richtungs- und Punktlichter) setzen, nur wenn sie sich ändert; -1: wieder
## wie in den Projekteinstellungen (Zimmer zu).
static func qualitaet_setzen(q: int) -> void:
	if q == _qualitaet_jetzt:
		return
	_qualitaet_jetzt = q
	if q < 0:
		RenderingServer.directional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)))
		RenderingServer.positional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2)))
	else:
		RenderingServer.directional_soft_shadow_filter_set_quality(q)
		RenderingServer.positional_soft_shadow_filter_set_quality(q)


func _q() -> Array:
	return QUALITAET.get(stufe, QUALITAET.mittel)


# --- Flächen und Sätze -------------------------------------------------------------------------------

## Die sechs Flächen des Raums: { name: [Mitte, rechts, oben, Normale (in den Raum), Breite, Höhe] }.
## rechts × oben = Normale; die Karte liegt mit „oben“ nach oben im Bild.
static func flaechen(w: float, d: float, h: float) -> Dictionary:
	return {
		"boden": [Vector3(w * 0.5, 0.0, d * 0.5), Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, w, d],
		"decke": [Vector3(w * 0.5, h, d * 0.5), Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, w, d],
		"hinten": [Vector3(w * 0.5, h * 0.5, 0.0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, w, h],
		"vorn": [Vector3(w * 0.5, h * 0.5, d), Vector3.LEFT, Vector3.UP, Vector3.FORWARD, w, h],
		"links": [Vector3(0.0, h * 0.5, d * 0.5), Vector3.FORWARD, Vector3.UP, Vector3.RIGHT, d, h],
		"rechts": [Vector3(w, h * 0.5, d * 0.5), Vector3.BACK, Vector3.UP, Vector3.LEFT, d, h],
	}


## Größe der Karte in Punkten (ein Punkt Rand je Seite) und Abbildung Welt → Karte: u = dot((P, 1), u4),
## v = dot((P, 1), v4) – für den Shader (lm_*_u, lm_*_v).
static func abbildung(f: Array, punkt: float) -> Dictionary:
	var c: Vector3 = f[0]
	var r: Vector3 = f[1]
	var o: Vector3 = f[2]
	var px := Vector2i(ceili(float(f[4]) / punkt) + 2, ceili(float(f[5]) / punkt) + 2)
	var bw := px.x * punkt
	var bh := px.y * punkt
	var u := Vector4(r.x / bw, r.y / bw, r.z / bw, (bw * 0.5 - c.dot(r)) / bw)
	var v := Vector4(-o.x / bh, -o.y / bh, -o.z / bh, (bh * 0.5 + c.dot(o)) / bh)
	return { "px": px, "breite": bw, "hoehe": bh, "u": u, "v": v }


func _saetze_bauen() -> void:
	for s in _saetze:
		for e: Dictionary in s:
			if is_instance_valid(e.vp):
				(e.vp as Node).queue_free()
	_saetze = [[], []]
	_mats = huelle.call("back_materialien")
	var w := float(huelle.get("w"))
	var d := float(huelle.get("d"))
	var h := float(huelle.get("HOEHE"))
	_masse = Vector3(w, h, d)
	var q := _q()
	var welt3d: World3D = (get_parent() as Node3D).get_world_3d()
	var fl := flaechen(w, d, h)
	for i in 2:
		for name: String in FLAECHEN:
			var f: Array = fl[name]
			var a := abbildung(f, float(q[0]))
			var vp := SubViewport.new()
			vp.size = a.px
			vp.world_3d = welt3d
			vp.use_hdr_2d = true
			vp.transparent_bg = true
			vp.msaa_3d = int(q[2])
			vp.use_taa = false
			# Schattenatlas nur beim Backen (_beginnen, _beenden): zwölf Atlanten mit 4096² und 32 Bit
			# hielten sonst rund 800 MB Grafikspeicher fest.
			vp.positional_shadow_atlas_size = 0
			vp.positional_shadow_atlas_16_bits = false
			vp.audio_listener_enable_3d = false
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.size = float(a.hoehe)
			cam.near = ABSTAND - NAH
			cam.far = ABSTAND + FERN
			cam.cull_mask = 0xFFFFF & ~EFFEKT_EBENE & ~BACK_LUECKE
			cam.environment = _env
			cam.transform = Transform3D(Basis(f[1], f[2], f[3]), (f[0] as Vector3) + (f[3] as Vector3) * ABSTAND)
			vp.add_child(cam)
			add_child(vp)
			cam.current = true
			(_saetze[i] as Array).append({ "name": name, "vp": vp, "u": a.u, "v": a.v, "n": f[3] })
	for e: Dictionary in _saetze[0]:
		var m: ShaderMaterial = _mats.get(e.name)
		if m:
			m.set_shader_parameter("lm_n", e.n)
			m.set_shader_parameter("lm_a", (e.vp as SubViewport).get_texture())
			m.set_shader_parameter("lm_a_u", e.u)
			m.set_shader_parameter("lm_a_v", e.v)
	for e: Dictionary in _saetze[1]:
		var m: ShaderMaterial = _mats.get(e.name)
		if m:
			m.set_shader_parameter("lm_b", (e.vp as SubViewport).get_texture())
			m.set_shader_parameter("lm_b_u", e.u)
			m.set_shader_parameter("lm_b_v", e.v)


func _setzen(param: String, wert: Variant) -> void:
	for m: ShaderMaterial in _mats.values():
		m.set_shader_parameter(param, wert)


## Sieht die Backkamera die Fläche gerade nicht (raum.gd ausgeblendet)?
func _versteckt(name: String) -> bool:
	return huelle != null and huelle.has_method("ausgeblendet") and bool(huelle.call("ausgeblendet", name))


## Hat eine Fläche noch keine Karte (dann leuchten die Kopien der Lichter sie)?
func _ohne_karte() -> bool:
	for name: String in FLAECHEN:
		if int(_zeigt.get(name, -1)) < 0:
			return true
	return false


# --- Backen ------------------------------------------------------------------------------------------

func _beginnen() -> void:
	_nochmal = false
	var masse := Vector3(float(huelle.get("w")), float(huelle.get("HOEHE")), float(huelle.get("d")))
	if _saetze[0].is_empty() or not masse.is_equal_approx(_masse) or _mats != huelle.call("back_materialien"):
		_saetze_bauen()
		# Neue Größe: die alten Karten passen nicht mehr – bis zum Backen leuchten die Kopien die Hülle.
		_zeigen_aus()
	# Je sichtbare Fläche in den Satz, der gerade nicht zu sehen ist; ausgeblendete behalten ihre Karte.
	_ziele = {}
	_ausgelassen = []
	for name: String in FLAECHEN:
		if _versteckt(name):
			_ausgelassen.append(name)
		else:
			_ziele[name] = 1 if int(_zeigt.get(name, -1)) == 0 else 0
	_umgebung_kopieren()
	_lichter_kopieren()
	_kopien.visible = true
	# Weiche Schatten in der höchsten Filterstufe – das Zimmer hat sie schon (_forward_global), sie bleibt.
	qualitaet_setzen(SCHATTEN_QUALITAET)
	_bewegte_schatten(true)
	for e: Dictionary in _backansichten():
		(e.vp as SubViewport).positional_shadow_atlas_size = int(_q()[1])
		(e.vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bilder = 0
	_start_ms = Time.get_ticks_msec()
	_zustand = "backen"


## Die Backansichten dieses Backens (je sichtbare Fläche die ihres Zielsatzes).
func _backansichten() -> Array:
	var out: Array = []
	for i in 2:
		for e: Dictionary in _saetze[i]:
			if int(_ziele.get(str(e.name), -1)) == i:
				out.append(e)
	return out


func _beenden() -> void:
	var ansichten := _backansichten()
	for e: Dictionary in ansichten:
		(e.vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		(e.vp as SubViewport).positional_shadow_atlas_size = 0
	_bewegte_schatten(false)
	letzte_ms = float(Time.get_ticks_msec() - _start_ms)
	gebacken += 1
	if gebacken <= 2:
		var punkte := 0
		for e: Dictionary in ansichten:
			punkte += (e.vp as SubViewport).size.x * (e.vp as SubViewport).size.y
		Launcher.log_launch("Zimmer-Licht gebacken (%s): %d Flächen, %d Kartenpunkte (%d mm), %d Lichter, davon %d mit Schatten, %d Bilder in %.0f ms" % [
				"beim Betreten" if gebacken == 1 else "nach einer Änderung", ansichten.size(), punkte, roundi(float(_q()[0]) * 1000.0), _kopien.get_child_count(),
				_kopien.get_children().filter(func(k: Node) -> bool: return (k as Light3D).shadow_enabled).size(), _bilder, letzte_ms])
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	# Je Fläche: das erste Bild aus den Karten kommt weich aus dem laufenden Licht (lm_an), sonst blendet
	# die alte Karte in die neue (lm_mix). Jede Blende beginnt beim Wert, der gerade gilt, und führt jede
	# Fläche mit Karte zu Ende – auch die, die diesmal nicht gebacken wurde: Das vorige Backen kann erst
	# 0,3 s her sein, seine Blende ist dann eben abgebrochen. Früher begann nur die neue; lm_an blieb
	# dann für immer stehen (gemessen: 0,60), die Kopien der Lichter gingen aus, und Wände, Boden und
	# Decke blieben um diesen Rest dunkler.
	var plan: Array = []
	for name: String in FLAECHEN:
		var m: ShaderMaterial = _mats.get(name)
		if m == null:
			continue
		if _ziele.has(name):
			if int(_zeigt.get(name, -1)) < 0:
				m.set_shader_parameter("lm_mix", float(_ziele[name]))
			_zeigt[name] = int(_ziele[name])
		var satz := int(_zeigt.get(name, -1))
		if satz < 0:
			continue
		for z: Array in [["lm_an", 1.0], ["lm_mix", float(satz)]]:
			var jetzt: Variant = m.get_shader_parameter(str(z[0]))
			var von := float(jetzt) if jetzt != null else 0.0
			if not is_equal_approx(von, float(z[1])):
				plan.append([m, z[0], von, z[1]])
	_tw.tween_method(func(k: float) -> void:
		for p: Array in plan:
			(p[0] as ShaderMaterial).set_shader_parameter(str(p[1]), lerpf(float(p[2]), float(p[3]), k)), 0.0, 1.0, BLENDE_S)
	_tw.tween_callback(func() -> void: _kopien.visible = _zustand == "backen" or _ohne_karte())
	if huelle.has_method("sonde_jetzt"):
		huelle.call("sonde_jetzt")
	if _nochmal:
		_zustand = "warten"
		_warte = 0.0
		_seit = 0.0
	else:
		_zustand = "ruhe"


## Keine Karten zu sehen: die Kopien der Lichter leuchten die Hülle im laufenden Bild.
func _zeigen_aus() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_zeigt = {}
	_setzen("lm_an", 0.0)
	_kopien.visible = true


## Umgebung der Backkameras: Himmel und Umgebungslicht wie im Raum, sonst nichts (linear, ohne
## Nachbearbeitung – die Karte ist Licht, kein Bild).
func _umgebung_kopieren() -> void:
	var env: Environment = huelle.get("env")
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0, 0)
	if env:
		_env.sky = env.sky
		_env.ambient_light_source = env.ambient_light_source
		# Ohne die feste Umgebungsfarbe: Sie ist der Abprall der Lampen auf Möbel (raum.gd ABPRALL_LAMPEN),
		# die Hülle bekommt ihr Lampenlicht gebacken.
		_env.ambient_light_color = Color.BLACK
		_env.ambient_light_energy = env.ambient_light_energy
		# Der Himmel trifft die Hülle stärker als Möbel und Figur (raum.gd GEBACKEN, himmel_backen).
		var hb: Variant = huelle.get("himmel_backen")
		_env.ambient_light_sky_contribution = float(hb) if hb != null else env.ambient_light_sky_contribution
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = false
	_env.adjustment_enabled = false
	_env.ssao_enabled = false
	_env.ssil_enabled = false
	_env.ssr_enabled = false
	_env.sdfgi_enabled = false
	_env.fog_enabled = false
	_env.volumetric_fog_enabled = false


## Alle Lichter des Raums (außer den Kopien) als Kopie, die nur die Hülle trifft; die Lichter selbst
## treffen die Hülle nicht mehr. Schatten: die Sonne und die BACK_LAMPEN kräftigsten Lampen.
func _lichter_kopieren() -> void:
	for k in _kopien.get_children():
		k.queue_free()
	var lampen: Array = []
	var stapel: Array[Node] = [get_parent()]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		if n == _kopien:
			continue
		stapel.append_array(n.get_children())
		if not (n is Light3D) or not (n as Light3D).is_visible_in_tree():
			continue
		var l := n as Light3D
		if not l.has_meta("uz_huelle"):
			l.set_meta("uz_huelle", (l.light_cull_mask & HUELLE_EBENE) != 0)
		l.light_cull_mask &= ~HUELLE_EBENE
		if not bool(l.get_meta("uz_huelle")) or l.light_energy <= 0.0:
			continue
		if l is DirectionalLight3D:
			continue
		var k := l.duplicate(0) as Light3D
		k.light_cull_mask = HUELLE_EBENE
		k.light_specular = 0.0
		k.light_volumetric_fog_energy = 0.0
		k.remove_meta("uz_huelle")
		_kopien.add_child(k)
		k.global_transform = l.global_transform
		if l is OmniLight3D:
			lampen.append([l.light_energy * (l as OmniLight3D).omni_range, k])
			k.shadow_enabled = false
	var sonne: DirectionalLight3D = huelle.get("sonne")
	if sonne_backen and is_instance_valid(sonne) and sonne.light_energy > 0.0:
		var k := _sonne_als_strahler(sonne)
		k.light_cull_mask = HUELLE_EBENE
		k.light_specular = 0.0
		k.shadow_enabled = true
		_kopien.add_child(k)
	lampen.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for i in mini(BACK_LAMPEN, lampen.size()):
		var k: OmniLight3D = lampen[i][1]
		k.shadow_enabled = true
		k.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		k.shadow_blur = maxf(k.shadow_blur, 1.5)
		k.shadow_bias = 0.04
		k.shadow_normal_bias = 1.2


## Die Sonne (bzw. der Mond) beim Backen: ein Strahler weit vor dem Fenster, der durch die Öffnung in
## den Raum zielt – seine Schatten rechnet die Engine wie die der Lampen (die Schatten einer
## gerichteten Sonne passten sich der flachen Backkamera nicht an: sie fehlten, der ganze Raum lag in
## der Sonne). Ohne Abfall mit der Entfernung leuchtet er wie die Sonne, fast parallel.
func _sonne_als_strahler(l: DirectionalLight3D, k: SpotLight3D = null) -> SpotLight3D:
	if k == null:
		k = SpotLight3D.new()
	var dir := -l.global_transform.basis.z.normalized()
	var fe: Dictionary = huelle.get("fenster")
	var d := float(huelle.get("d"))
	var mitte := Vector3(0.0, (float(fe.get("unten", 0.9)) + float(fe.get("oben", 2.3))) * 0.5, d * 0.5)
	k.light_color = l.light_color
	k.light_energy = l.light_energy
	k.light_indirect_energy = l.light_indirect_energy
	k.spot_range = SONNE_WEIT + 14.0
	k.spot_attenuation = 0.0
	var halb := Vector2(float(fe.get("breite", 1.9)), float(fe.get("oben", 2.3)) - float(fe.get("unten", 0.9))).length() * 0.5 + 0.8
	k.spot_angle = rad_to_deg(atan(halb / SONNE_WEIT))
	k.spot_angle_attenuation = 0.2
	k.shadow_blur = 1.5
	# Kleiner Tiefenabstand (die Engine rechnet ihn bei Strahlern in Tiefe der Schattenkarte, die mit der
	# Entfernung grob wird): sonst ließ die Wand rund ums Fenster Licht durch.
	k.shadow_bias = 0.002
	k.shadow_normal_bias = 1.0
	var ort := mitte - dir * SONNE_WEIT
	var t := Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD), ort)
	if not k.transform.is_equal_approx(t):
		k.transform = t
	return k


## Die Sonne im laufenden Bild (Möbel, Figur): derselbe Strahler, dessen Schatten die Engine wie die
## der Lampen nur neu rechnet, wenn sich etwas bewegt – die gerichtete Sonne zeichnete ihre Schatten in
## jedem Bild neu (jedes Möbel im Raum). Folgt der Sonne jedes Bild (Tageszeit gleitet), die gerichtete
## Sonne selbst bleibt aus.
func _sonne_laufzeit() -> void:
	var sonne: DirectionalLight3D = huelle.get("sonne")
	if not sonne_backen or not is_instance_valid(sonne):
		return
	if sonne.visible:
		sonne.visible = false
	if _laufzeit_sonne == null:
		_laufzeit_sonne = SpotLight3D.new()
		_laufzeit_sonne.name = "Sonne"
		_laufzeit_sonne.light_cull_mask = 0xFFFFF & ~HUELLE_EBENE
		_laufzeit_sonne.shadow_enabled = true
		add_child(_laufzeit_sonne)
	_laufzeit_sonne.light_specular = sonne.light_specular
	_sonne_als_strahler(sonne, _laufzeit_sonne)
	_laufzeit_sonne.visible = sonne.light_energy > 0.0


## Was sich im laufenden Bild bewegt (Pflanzen wiegen sich, Plattenteller, Tonarm), wirft dort keinen
## Schatten – sonst rechneten die Lampenschatten jedes Bild neu. Beim Backen schon (in Ruhelage).
func _bewegte_schatten(an: bool) -> void:
	var stapel: Array[Node] = [get_parent()]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		stapel.append_array(n.get_children())
		if n is GeometryInstance3D and n.has_meta("uz_backschatten"):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if an \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

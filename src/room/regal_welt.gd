extends Node3D
## Die 3D-Welt des Regals (src/ui/layers/regal_seite.gd): ein ruhiger, dunkler Raum mit einem
## Regal aus dunklem Lack, darauf die Spiele als Hüllen mit dem Rücken nach vorn (Maße und Format
## je System aus src/library/regal.gd). Warmes Licht von oben aus einer Leiste unter dem oberen
## Brett, ein weiches Licht von vorn und ein farbiges Licht hinter der gewählten Hülle, das wie der
## Raum der Farbe des Covers folgt. Die gewählte Hülle zieht sich mit einer Feder heraus und dreht
## sich zur Kamera; beim Öffnen fährt die Kamera heran und die Hüllen kippen nacheinander nach.
##
## Leistung: Nur die Hüllen im Bild gibt es wirklich (ein Vorrat an Knoten, beim Fahren neu
## belegt), Cover und Rücken kommen erst, wenn eine Hülle ins Bild kommt (Media; ohne Bild zeichnet
## der Shader der Vorderseite Uzais Ersatz – kein eigenes Bild je Hülle), und steht alles still,
## zeichnet der Viewport nicht weiter (UPDATE_ONCE).
## Leicht (leichter Modus): ohne Schatten, Spiegelung, Umgebungsverdeckung, Unschärfe und Glühen.
## Ruhig („Animationen reduzieren“): ohne Kamerafahrt, Nachkippen und Schwung, Herausziehen ohne
## Nachfedern.

const Regal := preload("res://src/library/regal.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const Inhalt := preload("res://src/room/inhalt.gd")
const U := preload("res://src/ui/u.gd")
const HUELLE_S := preload("res://src/room/shaders/regal_huelle.gdshader")
const VORN_S := preload("res://src/room/shaders/huelle_vorn.gdshader")
const Screenscraper := preload("res://src/core/screenscraper.gd")
const BadgeLogos := preload("res://src/core/badge_logos.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

## Ein Cover ist angekommen (die Seite stimmt Licht und Raum danach, wenn es das gewählte ist).
signal cover_da(id: String)

const FOV := 30.0
const ABSTAND := 4.6            ## Kamera vor den Rücken, in Hüllenhöhen
const EINZUG := 1.05            ## Kamerafahrt beim Öffnen (s)
const RAND := 0.12              ## so weit über den Bildrand hinaus stehen Hüllen schon bereit (m)
const SEITE := 0.024            ## Stärke der Seitenwände des Regals (m)
const LICHT := Color("#ffd6a5")
const RAUM := Color("#050506")
const LACK := Color("#1c1a18")

var leicht := false
var ruhig := false
var forward := true
var spiele: Array = []
var xs := PackedFloat32Array()
var trenner: Array = []
var abschnitte: Array = []
var hoehe := 0.19
var tiefe := 0.135
var laenge := 0.0
var auswahl := 0
var zieh_ziel := 1.0           ## wie weit die gewählte Hülle heraus soll (beim schnellen Blättern weniger)
var kamera: Camera3D

var _grenzen := Vector2(0, 1)
var _cam_x := 0.0
var _cam_v := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _einzug := 1.0
var _zeit := 0.0
var _env: Environment
var _farblicht: OmniLight3D
var _vornlicht: OmniLight3D
var _leiste: SpotLight3D
var _stimmung := Color("#9a8a74")
var _stimmung_soll := Color("#9a8a74")
var _huellen := {}             ## Index → Huelle (nur sichtbare)
var _frei: Array = []          ## Vorrat an Huelle-Knoten
var _farben := {}              ## Spiel-ID → Farbe des Rückens (aus dem Cover)
var _cover := {}               ## Spiel-ID → Textur (nur, solange die Hülle im Bild ist)
var _wartet := {}              ## Spiel-ID → Cover wird geladen
var _ohne := {}                ## Spiel-ID → hat kein Bild (die Hülle zeigt Uzais Ersatz-Vorderseite)
var _ruecken := {}             ## Spiel-ID → Bild des Rückens (ScreenScraper box-2D-side), solange im Bild
var _versucht := {}            ## Spiel-ID → passendes Format schon bei SteamGridDB gesucht
var _trenner_knoten: Array = []
var _bretter: Node3D
var _unruhe := 0.0             ## so lange zeichnet der Viewport auf jeden Fall weiter (s)
var _ersatz_ab := -1.0         ## nach dieser Zeit (s) sucht die gewählte Hülle ggf. ein passenderes Motiv
var _ruecken_font: Font
var _logos := {}               ## "Schlüssel|m" bzw. "|b" (bunt) → Textur bzw. false (noch keins)
var _gebaut := false


# --- Aufbau ------------------------------------------------------------------------------------------

func bauen(leicht_: bool, ruhig_: bool) -> void:
	leicht = leicht_
	ruhig = ruhig_
	forward = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_ruecken_font = UzTheme.display("bold")
	kamera = Camera3D.new()
	kamera.fov = FOV
	kamera.near = 0.02
	kamera.far = 8.0
	kamera.current = true
	add_child(kamera)
	if forward and not leicht:
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = true
		ca.dof_blur_amount = 0.06
		kamera.attributes = ca
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = RAUM
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#211d1a")
	_env.ambient_light_energy = 0.3
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.1
	if not leicht:
		_env.glow_enabled = true
		_env.glow_intensity = 0.35
		_env.glow_hdr_threshold = 1.2
		_env.glow_bloom = 0.0
	if forward and not leicht:
		_env.ssr_enabled = true
		_env.ssr_max_steps = 56
		_env.ssr_fade_in = 0.08
		_env.ssr_fade_out = 1.4
		_env.ssr_depth_tolerance = 0.04
		_env.ssao_enabled = true
		_env.ssao_radius = 0.05
		_env.ssao_intensity = 1.4
		_env.ssao_detail = 0.4
	we.environment = _env
	add_child(we)
	_licht()
	# Echte Systemlogos kommen zur Laufzeit (abschaltbar); ist eins fertig geladen, ins Kopfband.
	var ll := BadgeLogos.loader()
	if ll and ll.has_signal("logo_ready"):
		ll.connect("logo_ready", _logo_da)
	_gebaut = true


func _licht() -> void:
	var sonne := DirectionalLight3D.new()
	sonne.light_color = Color("#fff1e0")
	sonne.light_energy = 0.2
	sonne.rotation_degrees = Vector3(-38, -20, 0)
	sonne.shadow_enabled = not leicht
	sonne.directional_shadow_max_distance = 3.0
	sonne.shadow_blur = 1.6
	add_child(sonne)
	_leiste = SpotLight3D.new()
	_leiste.light_color = LICHT
	_leiste.light_energy = 2.4
	_leiste.spot_angle = 64.0
	_leiste.spot_attenuation = 1.2
	_leiste.rotation_degrees = Vector3(-82, 0, 0)
	_leiste.shadow_enabled = not leicht and forward
	_leiste.shadow_bias = 0.06
	_leiste.shadow_normal_bias = 1.6
	_leiste.shadow_blur = 2.0
	add_child(_leiste)
	_farblicht = OmniLight3D.new()
	_farblicht.light_energy = 1.25
	_farblicht.omni_attenuation = 1.6
	add_child(_farblicht)
	_vornlicht = OmniLight3D.new()
	_vornlicht.light_color = Color("#fff3e6")
	_vornlicht.light_energy = 0.6
	_vornlicht.light_specular = 0.2
	add_child(_vornlicht)


## Spiele aufs Brett: spiele (sortiert), Lage aus Regal.anordnen, Abschnitte. Das Regal wächst mit.
func belegen(list: Array, lage: Dictionary, abs_: Array, waehle: int) -> void:
	spiele = list
	xs = lage.x
	trenner = lage.trenner
	laenge = float(lage.laenge)
	abschnitte = abs_
	hoehe = Regal.hoehe_max(list)
	tiefe = 0.0
	for g in list:
		tiefe = maxf(tiefe, Regal.masse(str(g.get("system", ""))).z)
	if tiefe <= 0.0:
		tiefe = 0.135
	for i in _huellen.keys():
		_freigeben(int(i))
	_grenzen = Regal.grenzen(laenge, _halbe_breite())
	_bretter_bauen()
	_trenner_bauen()
	auswahl = clampi(waehle, 0, maxi(0, list.size() - 1))
	_cam_x = _kamera_ziel()
	_cam_v = 0.0
	_unruhe = 0.5


func _x(i: int) -> float:
	return xs[i] if i >= 0 and i < xs.size() else 0.0


func _kamera_ziel() -> float:
	return Regal.kamera_ziel(_x(auswahl), _grenzen, _halbe_breite(), SEITE)


## Brett mit tiefer Kante vorn (dort schwebt die herausgezogene Hülle über ihrem Spiegelbild),
## oberes Brett mit Lichtleiste, Seiten, Rückwand, die Front darunter und die Wand des Raums.
func _bretter_bauen() -> void:
	if is_instance_valid(_bretter):
		_bretter.queue_free()
	_bretter = Node3D.new()
	add_child(_bretter)
	var a := _grenzen.x
	var b := _grenzen.y
	var l := b - a
	var mitte := (a + b) * 0.5
	var vorn := _vorn()
	var hinten := -tiefe - 0.014
	var t := vorn - hinten
	var lack := S.lack(LACK, 0.22, 0.75)
	var oben := hoehe + 0.05
	_kiste(Vector3(l + 0.002, 0.024, t), Vector3(mitte, -0.012, hinten + t * 0.5), lack)
	_kiste(Vector3(l + 0.002, 0.026, t), Vector3(mitte, oben + 0.013, hinten + t * 0.5), lack)
	# Lichtleiste unter der Vorderkante des oberen Bretts (warm, glüht leicht).
	_kiste(Vector3(l, 0.003, 0.006), Vector3(mitte, oben - 0.0015, vorn - 0.03), S.leuchte(LICHT, 1.4))
	var rueck := StandardMaterial3D.new()
	rueck.albedo_color = Color("#1a181c")
	rueck.roughness = 0.88
	_kiste(Vector3(l + 0.002, oben + 0.05, 0.01), Vector3(mitte, (oben + 0.05) * 0.5 - 0.025, hinten - 0.005), rueck)
	# Front unter dem Brett: dunkler, matter Lack (dort steht unten die Schrift).
	_kiste(Vector3(l + SEITE * 2.0, 0.6, 0.02), Vector3(mitte, -0.324, vorn - 0.012), S.lack(Color("#111113"), 0.6, 0.3))
	for x in [a - SEITE * 0.5, b + SEITE * 0.5]:
		_kiste(Vector3(SEITE, oben + 0.626, t + 0.004), Vector3(x, (oben + 0.026 - 0.6) * 0.5, hinten + t * 0.5), lack)
	var wand := StandardMaterial3D.new()
	wand.albedo_color = Color("#0e0d10")
	wand.roughness = 1.0
	_kiste(Vector3(l + 12.0, 3.0, 0.02), Vector3(mitte, 0.2, hinten - 0.32), wand)
	# Buchstütze hinter der letzten Hülle, wenn danach noch Brett frei ist.
	if b - laenge > 0.06 and not spiele.is_empty():
		var metall := S.metall(Color("#a2a2a8"), 0.3)
		var hs := hoehe * 0.62
		_kiste(Vector3(0.003, hs, tiefe * 0.8), Vector3(laenge + 0.0035, hs * 0.5, -tiefe * 0.5), metall)
		_kiste(Vector3(0.05, 0.003, tiefe * 0.8), Vector3(laenge + 0.028, 0.0015, -tiefe * 0.5), metall)


func _vorn() -> float:
	return tiefe * 0.5 + (Regal.ZUG_VOR + 0.04) * hoehe / 0.19


func _kiste(m: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = F.kiste(m, 0.0025, false, 1)
	mi.material_override = mat
	mi.position = pos
	_bretter.add_child(mi)
	return mi


## Trenner an jeder Abschnittsgrenze: eine schmale Karte zwischen den Hüllen, oben ein kleiner
## Reiter mit dem Abschnitt (A, B … bzw. „Heute“).
func _trenner_bauen() -> void:
	for n in _trenner_knoten:
		if is_instance_valid(n):
			n.queue_free()
	_trenner_knoten.clear()
	var mat := S.lack(Color("#26262b"), 0.4, 0.4)
	for a in range(1, abschnitte.size()):
		if a - 1 >= trenner.size():
			break
		var name := tr(str(abschnitte[a].name))
		var n := Node3D.new()
		n.position = Vector3(float(trenner[a - 1]), 0, 0)
		var karte := MeshInstance3D.new()
		karte.mesh = F.kiste(Vector3(0.0014, hoehe, tiefe * 0.92), 0.0005, false, 1)
		karte.material_override = mat
		karte.position = Vector3(0, hoehe * 0.5, -tiefe * 0.5)
		n.add_child(karte)
		var gr := 30
		var px := 0.0004 * hoehe / 0.19
		var breite := _ruecken_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x * px + 0.01
		var reiter := MeshInstance3D.new()
		var rh := 0.017 * hoehe / 0.19
		reiter.mesh = F.kiste(Vector3(maxf(0.02, breite), rh, 0.002), 0.0016, false, 1)
		reiter.material_override = mat
		reiter.position = Vector3(0, hoehe + rh * 0.5 - 0.003, -0.006)
		n.add_child(reiter)
		var l := _label(name, gr, Color("#dedcd6"))
		l.pixel_size = px
		l.position = Vector3(0, hoehe + rh * 0.5 - 0.003, -0.006 + 0.001 + 0.0008)
		n.add_child(l)
		add_child(n)
		_trenner_knoten.append(n)


func _label(text: String, groesse: int, farbe: Color) -> Label3D:
	var l := Label3D.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.font = _ruecken_font
	l.font_size = groesse
	l.outline_size = 0
	l.modulate = farbe
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.render_priority = 1
	return l


# --- Auswahl und Stimmung ----------------------------------------------------------------------------

func waehlen(i: int) -> void:
	auswahl = clampi(i, 0, maxi(0, spiele.size() - 1))
	_unruhe = maxf(_unruhe, 0.2)
	_ersatz_ab = 0.15


## Passt das Motiv der gewählten Hülle nicht, sucht Uzai ein passenderes – erst wenn die Auswahl
## kurz steht (beim schnellen Blättern nicht für jede).
func _ersatz_pruefen(dt: float) -> void:
	if _ersatz_ab < 0.0:
		return
	_ersatz_ab -= dt
	if _ersatz_ab >= 0.0 or auswahl >= spiele.size():
		return
	_ersatz_ab = -1.0
	var g: Dictionary = spiele[auswahl]
	if _huellen.has(auswahl):
		_ruecken_laden(auswahl, g, true)
	if not _ohne.has(str(g.get("id", ""))):
		_passend_holen(g)


## Licht und Raum folgen dieser Farbe (der Farbe des Covers), weich.
func stimmung(c: Color) -> void:
	var h := Color.from_hsv(c.h, clampf(c.s, 0.0, 0.8), clampf(c.v, 0.6, 1.0))
	if h.is_equal_approx(_stimmung_soll):
		return
	_stimmung_soll = h
	if ruhig or leicht:
		_stimmung = h
	_unruhe = maxf(_unruhe, U.T_LICHT)


## Beim Öffnen: Kamera fährt heran, die Hüllen im Bild kippen nacheinander nach.
func einziehen() -> void:
	if ruhig:
		_einzug = 1.0
		return
	_einzug = 0.0
	_zeit = 0.0
	for i in _huellen.keys():
		_huellen[i].kipp_ab = 0.22 + minf(absi(int(i) - auswahl) * 0.032, 0.7)
	_unruhe = EINZUG + 0.8


## Farbe des Rückens eines Spiels (sobald das Cover da war, aus dem Cover).
func ruecken_von(g: Dictionary) -> Color:
	var id := str(g.get("id", ""))
	if _farben.has(id):
		return _farben[id]
	var sys := Config.system(str(g.get("system", "")))
	return Regal.ruecken_farbe(null, Color(str(sys.get("color", "#3a3a42"))), id)


## Farbe des Covers zum Spiel (für Licht und Raum), sonst null.
func farbe_von(g: Dictionary) -> Variant:
	var t: Variant = _cover.get(str(g.get("id", "")))
	if t is Texture2D:
		return Media.color_of(t)
	return null


# --- Jedes Bild --------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not _gebaut:
		return
	dt = minf(dt, 0.05)
	_zeit += dt
	_ersatz_pruefen(dt)
	var ziel := _kamera_ziel()
	var vor_x := _cam_x
	var f := U.spring_step(_cam_x, _cam_v, ziel, dt, 26.0) if ruhig else Regal.feder(_cam_x, _cam_v, ziel, dt, 11.0, 1.0)
	_cam_x = f.x
	_cam_v = f.y
	var tempo := (_cam_x - vor_x) / maxf(dt, 0.001)
	# Schwung: bei schneller Fahrt neigen sich die Hüllen kurz gegen die Richtung.
	var lean_ziel := 0.0 if ruhig or leicht else clampf(tempo * 0.09, -0.07, 0.07)
	var fl := Regal.feder(_lean, _lean_v, lean_ziel, dt, 14.0, 0.7)
	_lean = fl.x
	_lean_v = fl.y
	if _einzug < 1.0:
		_einzug = minf(1.0, _einzug + dt / EINZUG)
	_kamera_setzen()
	_stimmung = _stimmung.lerp(_stimmung_soll, clampf(dt * 3.2, 0.0, 1.0))
	_licht_setzen()
	_sichtbare()
	var bewegt := absf(_cam_v) > 0.002 or absf(_lean) > 0.0005 or _einzug < 1.0
	for i in _huellen.keys():
		if _huellen[i].schritt(dt, self):
			bewegt = true
	_unruhe = maxf(0.0, _unruhe - dt)
	var vp := get_viewport() as SubViewport
	if vp:
		var soll := SubViewport.UPDATE_ALWAYS if bewegt or _unruhe > 0.0 else SubViewport.UPDATE_ONCE
		if soll == SubViewport.UPDATE_ALWAYS or vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = soll


## Bild weiterzeichnen (ein Cover kam, die Größe änderte sich …).
func unruhe(sek := 0.3) -> void:
	_unruhe = maxf(_unruhe, sek)


func _kamera_setzen() -> void:
	var s := hoehe / 0.19
	var blick := Vector3(_cam_x, hoehe * 0.45, 0.0)
	var pos := Vector3(_cam_x, hoehe * 0.62, hoehe * ABSTAND)
	if _einzug < 1.0:
		var e := 1.0 - pow(1.0 - _einzug, 3.0)
		pos += Vector3(-0.3 * s, 0.2 * s, 0.85 * s) * (1.0 - e)
		blick += Vector3(-0.1 * s, 0.0, 0.0) * (1.0 - e)
	kamera.look_at_from_position(pos, blick, Vector3.UP)
	var ca := kamera.attributes as CameraAttributesPractical
	if ca:
		# Scharf bis knapp hinter die Rücken, dahinter (Rückwand, Raum) weich.
		ca.dof_blur_far_distance = pos.distance_to(blick) + tiefe * 0.7
		ca.dof_blur_far_transition = 0.3 * s


func _licht_setzen() -> void:
	var oben := hoehe + 0.05
	_leiste.position = Vector3(_cam_x, oben - 0.004, _vorn() - 0.06)
	_leiste.spot_range = hoehe * 3.0
	var x := _x(auswahl)
	_farblicht.position = Vector3(x, hoehe * 0.8, -tiefe + 0.03)
	_farblicht.omni_range = hoehe * 2.4
	_farblicht.light_color = _stimmung
	_vornlicht.position = Vector3(x - hoehe * 0.5, hoehe * 2.6, hoehe * 1.9)
	_vornlicht.omni_range = hoehe * 5.0
	_env.background_color = RAUM.lerp(_stimmung, 0.03)
	_env.ambient_light_color = Color("#1e1a17").lerp(_stimmung, 0.2)


## Halbe Breite des Bilds in der Ebene der Rücken (m).
func _halbe_breite() -> float:
	return hoehe * ABSTAND * tan(deg_to_rad(FOV * 0.5)) * _seitenverhaeltnis()


## Nur die Hüllen im Bild (samt Rand) gibt es; was hinausfährt, gibt seinen Knoten frei.
func _sichtbare() -> void:
	var cz := maxf(kamera.global_position.z, hoehe * ABSTAND)
	var halb := cz * tan(deg_to_rad(FOV * 0.5)) * _seitenverhaeltnis() + RAND
	var cx := kamera.global_position.x
	var r := Regal.bereich(xs, cx - halb, cx + halb)
	for i in _huellen.keys():
		if int(i) < r.x or int(i) > r.y:
			_freigeben(int(i))
	for i in range(r.x, r.y + 1):
		if not _huellen.has(i):
			_belegen(i)


func _seitenverhaeltnis() -> float:
	var vp := get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var s := vp.get_visible_rect().size
	return s.x / maxf(s.y, 1.0)


func _freigeben(i: int) -> void:
	var h: Huelle = _huellen.get(i)
	_huellen.erase(i)
	if h == null:
		return
	_cover.erase(str(h.spiel.get("id", "")))
	_ruecken.erase(str(h.spiel.get("id", "")))
	h.visible = false
	h.idx = -1
	_frei.append(h)


func _belegen(i: int) -> void:
	var h: Huelle
	if _frei.is_empty():
		h = Huelle.new()
		h.bauen(HUELLE_S)
		add_child(h)
	else:
		h = _frei.pop_back()
	var g: Dictionary = spiele[i]
	h.idx = i
	h.visible = true
	h.setzen(g, _x(i), ruecken_von(g), _ruecken_font, logo_tex)
	# Nachkippen beim Öffnen: je weiter von der Auswahl, desto später.
	h.kipp_ab = -1.0
	if _einzug < 1.0 and not ruhig:
		h.kipp_ab = 0.22 + minf(absi(i - auswahl) * 0.032, 0.7)
	h.p = 1.0 if i == auswahl and _einzug >= 1.0 and zieh_ziel >= 1.0 and absf(_cam_v) < 0.01 else 0.0
	h.pv = 0.0
	_huellen[i] = h
	_cover_laden(i, g)


## Cover lazy: erst wenn die Hülle im Bild ist, in der Reihenfolge von Regal.bildarten: eigenes
## Cover, dann der echte Scan der Verpackung (Libretro, ScreenScraper – er liegt unverändert auf der
## Hülle), dann ein Motiv (passendes Format, übliches Cover) unter Uzais Band. Ohne Bild zeigt die
## Hülle Uzais Ersatz-Vorderseite (im Shader, kostet nichts). Dazu der Rücken (ruecken_laden).
func _cover_laden(i: int, g: Dictionary) -> void:
	var id := str(g.get("id", ""))
	_ruecken_laden(i, g)
	var da: Variant = _cover.get(id)
	if da is Texture2D:
		(_huellen[i] as Huelle).cover_setzen(da)
		return
	if _ohne.has(id) or _wartet.has(id):
		return
	_wartet[id] = true
	var arten := cover_arten(g)
	_kette(g, arten, func(t: Variant) -> void:
		_wartet.erase(id)
		if not is_inside_tree():
			return
		if not (t is Texture2D):
			_ohne[id] = true
			return
		var tex: Texture2D = t
		var sys := Config.system(str(g.get("system", "")))
		_farben[id] = Regal.ruecken_farbe(Media.color_of(tex), Color(str(sys.get("color", "#3a3a42"))), id)
		_auf_huelle(id, tex, true)
	)


## Bild des Rückens: liegt es schon da (Medienordner, Cache) oder kennt ScreenScraper es
## (box-2D-side), trägt die Hülle den echten Rücken statt Uzais Aufbau. Nur für Emulator-Spiele.
## Gefragt wird ScreenScraper nur für die gewählte Hülle (netz) oder wenn seine Antwort schon im
## Eintrag steht – sonst fräße das Blättern das Tageskontingent.
func _ruecken_laden(i: int, g: Dictionary, netz := false) -> void:
	var id := str(g.get("id", ""))
	var da: Variant = _ruecken.get(id)
	if da is Texture2D:
		(_huellen[i] as Huelle).ruecken_setzen(da)
		return
	if _wartet.has("r:" + id) or _ohne.has("r:" + id):
		return
	if Media.local_path(g, "ruecken") == "":
		var ss: Variant = g.get("ss")
		var bekannt := ss is Dictionary and (ss as Dictionary).get("medien") is Dictionary and (ss.medien as Dictionary).has("ruecken")
		if not (netz or bekannt) or not Screenscraper.verfuegbar() or not str(g.get("source", "")) in ["rom", "disc"]:
			return
	_wartet["r:" + id] = true
	Media.game_texture(g, "ruecken", func(t: Variant) -> void:
		_wartet.erase("r:" + id)
		if not is_inside_tree():
			return
		if not (t is Texture2D):
			_ohne["r:" + id] = true
			return
		_ruecken[id] = t
		for k in _huellen.keys():
			var h: Huelle = _huellen[k]
			if str(h.spiel.get("id", "")) == id:
				h.ruecken_setzen(t)
		unruhe(0.4)
	)


## Bildarten der Reihe nach versuchen, bis eine ein Bild bringt (cb mit Textur bzw. null).
func _kette(g: Dictionary, arten: Array, cb: Callable, k := 0) -> void:
	if k >= arten.size():
		cb.call(null)
		return
	Media.game_texture(g, str(arten[k]), func(t: Variant) -> void:
		if t is Texture2D:
			cb.call(t)
		elif is_inside_tree():
			_kette(g, arten, cb, k + 1)
	)


## Welches Bildformat die Vorderseite eines Spiels braucht (mit dem Rahmen des Systems darüber).
static func gewuenschte_bildart(g: Dictionary) -> String:
	var sid := str(g.get("system", ""))
	return Regal.bildart_fuer(Regal.motiv_flaeche(Regal.vorderseite(sid), Regal.rahmen_von(sid)).size)


## Bildarten für die Vorderseite in ihrer Reihenfolge (Regal.bildarten) – auch das Spieleregal im
## Zimmer nimmt sie (inhalt.gd huellen_cover), damit beide dasselbe Bild zeigen.
static func cover_arten(g: Dictionary) -> Array:
	var wunsch := gewuenschte_bildart(g)
	var vorhanden := {}
	for k in ["cover_scan", wunsch]:
		vorhanden[k] = Media.local_path(g, k) != ""
	var sid := str(g.get("system", ""))
	return Regal.bildarten(g, wunsch, vorhanden, not Regal.rahmen_von(sid).is_empty(), str(Config.get_value("accounts.sgdb_key", "")) != "")


## Passt das Bild der gewählten Hülle nicht (Seitenverhältnis), holt Uzai einmal eines im
## passenden Format von SteamGridDB – nur mit eigenem Schlüssel (Konto in den Einstellungen), wie
## alle Bilder über Media und dort gemerkt. Ohne Schlüssel oder ohne Treffer bleibt der Zuschnitt.
func _passend_holen(g: Dictionary) -> void:
	var id := str(g.get("id", ""))
	var h: Huelle = _huellen.get(auswahl)
	# Nur ein Motiv unter Uzais Band – ein Scan liegt unverändert auf der Hülle.
	if h == null or h.passt_bild or not h.rahmen_drauf or _versucht.has(id):
		return
	if str(Config.get_value("accounts.sgdb_key", "")) == "":
		return
	var wunsch := gewuenschte_bildart(g)
	if wunsch == "cover":
		return
	_versucht[id] = true
	Media.game_texture(g, wunsch, func(t: Variant) -> void:
		if t is Texture2D and is_inside_tree():
			_auf_huelle(id, t, false)
	)


func _auf_huelle(id: String, tex: Texture2D, mit_farbe: bool) -> void:
	_cover[id] = tex
	for k in _huellen.keys():
		var h: Huelle = _huellen[k]
		if str(h.spiel.get("id", "")) == id:
			h.cover_setzen(tex)
			if mit_farbe and _farben.has(id):
				h.farbe_soll = Regal.ruecken_von(Regal.format_daten(str(h.spiel.get("system", ""))), _farben[id])
	unruhe(0.5)
	cover_da.emit(id)


## Logo zu einem Schlüssel (src/core/badge_logos.gd: eigene Datei im Medienordner, sonst – nur wenn
## „Echte Konsolen-Logos“ an ist – aus dem Cache bzw. geladen) als Textur: einfarbig weiß zum
## Einfärben, mit bunt in seinen eigenen Farben (das PS-Zeichen; Textur mit uz_bunt), wenn das
## geladene Bild farbig ist. null: noch keins oder aus – dann Kürzel, Schriftzug bzw. ein anderes
## Logo (Huelle).
func logo_tex(key: String, bunt := false) -> Texture2D:
	if key == "":
		return null
	var mk := key + ("|b" if bunt else "|m")
	if not _logos.has(mk):
		var got := BadgeLogos.line_logo(key, 40.0, 800.0, bunt)
		_logos[mk] = got.get("tex", false) if not got.is_empty() else false
	var t: Variant = _logos[mk]
	return t if t is Texture2D else null


## Wie logo_tex, ohne eigene Welt (Spieleregal im Zimmer): gemerkt für alle; ein noch fehlendes
## Logo wird nach einer halben Minute wieder versucht.
static func logo_statisch(key: String, bunt := false) -> Texture2D:
	if key == "":
		return null
	var _logos_alle: Dictionary = Inhalt.merker("uz_logos_zimmer")
	var mk := key + ("|b" if bunt else "|m")
	var jetzt := Time.get_ticks_msec()
	var e: Variant = _logos_alle.get(mk)
	if e == null or (not (e is Texture2D) and jetzt - int(e) > 30000):
		var got := BadgeLogos.line_logo(key, 40.0, 800.0, bunt)
		var t: Variant = got.get("tex") if not got.is_empty() else null
		_logos_alle[mk] = t if t is Texture2D else jetzt
		e = _logos_alle[mk]
	return e if e is Texture2D else null


## Schriftzug im Band der Vorderseite eines Systems (PS2: die Wortmarke), einfarbig; null ohne.
func logo_fuer(system_id: String) -> Texture2D:
	return logo_tex(Regal.marke_von(system_id))


func _logo_da(key: String) -> void:
	_logos.erase(key + "|b")
	_logos.erase(key + "|m")
	for i in _huellen.keys():
		(_huellen[i] as Huelle).logos_neu()
	unruhe(0.4)


## Bildschirmlage einer Hülle (Mitte des Rückens) für die Maus; null, wenn sie nicht im Bild ist.
func bildlage(i: int) -> Variant:
	var h: Huelle = _huellen.get(i)
	if h == null:
		return null
	var p := h.global_position + Vector3(0, h.masse.y * 0.5, h.masse.z * 0.5)
	if kamera.is_position_behind(p):
		return null
	return kamera.unproject_position(p)


func sichtbare_indizes() -> Array:
	return _huellen.keys()


## Eine Hülle im Regal wie die echte: Körper (Kiste mit runden Kanten, eigener Shader: Kunststoff in
## der Farbe der Hülle, Felder des Rückens, CD-Hülle klar, Karton matt), auf der Seite +x die
## Vorderseite (huelle_vorn.gdshader: echter Scan unverändert unter der Folie, sonst Uzais
## Ersatz-Vorderseite bzw. ein Motiv mit dem Band des Systems), auf dem Rücken das Bild des echten
## Rückens (ScreenScraper) oder die Logos und Texte der Felder (Regal.ruecken_aufbau), der Titel und
## – wenn bekannt – die Seriennummer. Ursprung unten in der Mitte der Hülle.
class Huelle extends Node3D:
	const FELDER_MAX := 6
	var idx := -1
	var spiel: Dictionary = {}
	var masse := Vector3(0.014, 0.19, 0.135)
	var p := 0.0                ## herausgezogen 0 … 1
	var pv := 0.0
	var kipp_ab := -1.0         ## Nachkippen beim Öffnen: ab dieser Zeit (s), −1 = keins
	var farbe_ist := Color.GRAY
	var farbe_soll := Color.GRAY
	var x0 := 0.0
	var region := "pal"
	var nummer := ""             ## Seriennummer auf dem Rücken ("" = unbekannt, dann keine)
	var _koerper: MeshInstance3D
	var _mat: ShaderMaterial
	var _vorn: Node3D            ## Vorderseite: Einleger, Rahmen des Systems, Logos
	var _cover: MeshInstance3D   ## Fläche über der ganzen Front (huelle_vorn.gdshader)
	var _vmat: ShaderMaterial
	var _rlogo: Sprite3D
	var _rzeichen: Sprite3D      ## Zeichen am anderen Ende des Bands (PS2: das farbige PS-Logo)
	var _rtext: Label3D
	var _vtitel: Label3D         ## Titel auf Uzais Ersatz-Vorderseite
	var _font: Font
	var _logos: Callable         ## (Schlüssel, bunt) → Texture2D oder null (regal_welt.logo_tex)
	var _tex: Texture2D
	var _rtex: Texture2D         ## Bild des echten Rückens (oder null)
	var scan := false            ## das Bild ist ein echter Scan: unverändert, ohne Uzais Band
	var rahmen_drauf := false    ## Uzai zeigt das Band des Systems (Ersatz-Vorderseite, Motiv ohne Band)
	var passt_bild := true       ## Motiv passt ohne merklichen Zuschnitt auf die Fläche
	var _titel: Label3D
	var _nummer: Label3D
	var _f_logo: Array = []      ## Sprite3D je Feld des Rückens
	var _f_text: Array = []      ## Label3D je Feld des Rückens
	var _fmt := ""
	var _fd: Dictionary = {}
	var _aufbau: Dictionary = {}
	var _glimmen := 0.0
	var hat_logo := false        ## am Rücken steht ein echtes Logo (sonst Kürzel bzw. Schriftzug)

	func bauen(shader: Shader) -> void:
		_koerper = MeshInstance3D.new()
		_mat = ShaderMaterial.new()
		_mat.shader = shader
		_koerper.material_override = _mat
		add_child(_koerper)
		_vorn = Node3D.new()
		add_child(_vorn)
		_cover = MeshInstance3D.new()
		_cover.mesh = QuadMesh.new()
		_vmat = ShaderMaterial.new()
		_vmat.shader = VORN_S
		_cover.material_override = _vmat
		_vorn.add_child(_cover)
		_rlogo = _sprite()
		_vorn.add_child(_rlogo)
		_rzeichen = _sprite()
		_vorn.add_child(_rzeichen)
		_rtext = _schrift()
		_vorn.add_child(_rtext)
		_vtitel = _schrift()
		_vtitel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vtitel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vorn.add_child(_vtitel)
		_titel = _schrift()
		add_child(_titel)
		_nummer = _schrift()
		add_child(_nummer)
		for i in 3:
			var s := _sprite()
			add_child(s)
			_f_logo.append(s)
			var l := _schrift()
			add_child(l)
			_f_text.append(l)

	func _sprite() -> Sprite3D:
		var s := Sprite3D.new()
		s.shaded = true
		s.double_sided = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		s.render_priority = 1
		s.visible = false
		return s

	func _schrift() -> Label3D:
		var l := Label3D.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		l.render_priority = 1
		l.visible = false
		return l

	## Längs gelesen wie auf den echten Hüllen: von oben nach unten (Kopf der Schrift nach rechts).
	static func laengs() -> Basis:
		return Basis(Vector3.FORWARD, PI * 0.5)

	func setzen(g: Dictionary, x: float, farbe: Color, font: Font, logos: Callable) -> void:
		spiel = g
		x0 = x
		_logos = logos
		var sid := str(g.get("system", ""))
		var fd := Regal.format_daten(sid)
		_fd = fd
		masse = fd.m
		var fmt := Regal.format_von(sid)
		if fmt != _fmt:
			_fmt = fmt
			_koerper.mesh = F.kiste(masse, Regal.kanten_rad(sid), false, 2)
			_koerper.position = Vector3(0, masse.y * 0.5, 0)
			_vorn.rotation = Vector3(0, PI * 0.5, 0)
			_vorn.position = Vector3(masse.x * 0.5 + 0.0004, masse.y * 0.5, 0)
			format_setzen(_mat, sid)
		var bekannt := Library.serial_of(g) if Regal.RUECKEN.has(fmt) else ""
		nummer = Regal.seriennummer(g, bekannt) if Regal.RUECKEN.has(fmt) and bool(Regal.RUECKEN[fmt].get("nummer", false)) else ""
		region = Regal.region_von(g, nummer)
		farbe = Regal.ruecken_von(fd, farbe)
		farbe_ist = farbe
		farbe_soll = farbe
		_font = font
		_aufbau = Regal.ruecken_aufbau(sid, region, farbe, nummer != "")
		_mat.set_shader_parameter("band_hoehe", 1.0 - float(_aufbau.kopf))
		_farbe_setzen(farbe)
		_mat.set_shader_parameter("glimmen", 0.0)
		_vmat.set_shader_parameter("glimmen", 0.0)
		_glimmen = 0.0
		_tex = null
		_rtex = null
		_mat.set_shader_parameter("hat_ruecken", false)
		_titel_setzen(g, font)
		_nummer_setzen(font)
		_ruecken_setzen()
		_vorn_setzen()
		position = Vector3(x, 0, -masse.z * 0.5)
		rotation = Vector3.ZERO

	## Werte des Formats im Material (regal_huelle.gdshaderinc) – auch für die Hüllen im Zimmer.
	static func format_setzen(mat: ShaderMaterial, sid: String) -> void:
		var fd := Regal.format_daten(sid)
		var fmt := Regal.format_von(sid)
		mat.set_shader_parameter("halb", (fd.m as Vector3) * 0.5)
		mat.set_shader_parameter("plastik", fd.plastik)
		mat.set_shader_parameter("schale", fd.get("schale", fd.plastik))
		mat.set_shader_parameter("klar", bool(fd.get("klar", false)))
		mat.set_shader_parameter("schimmer", fd.get("schimmer", fd.plastik))
		mat.set_shader_parameter("art", Regal.art_nr(sid))
		mat.set_shader_parameter("folie", float(fd.folie))
		# Feine Kante unter dem Kopfband (nicht bei Kartons und nicht, wo die Felder der echten
		# Aufmachung selbst die Grenze ziehen – PS2: schwarz auf weiß).
		mat.set_shader_parameter("kante_staerke", 0.18 if fd.band is Color and not Regal.RUECKEN.has(fmt) else 0.0)

	## Felder des Rückens (Regal.ruecken_aufbau) im Material; ohne grund: die Farbe des Titelfelds
	## kommt anders (Zimmer: je Hülle).
	static func felder_setzen(mat: ShaderMaterial, a: Dictionary) -> void:
		var ys := PackedVector4Array()
		var cs := PackedVector3Array()
		var felder: Array = a.felder
		for i in FELDER_MAX:
			if i < felder.size():
				var c: Color = (felder[i].farbe as Color).srgb_to_linear()
				ys.append(Vector4(float(felder[i].y0), float(felder[i].y1), 0, 0))
				cs.append(Vector3(c.r, c.g, c.b))
			else:
				ys.append(Vector4(-1, -1, 0, 0))
				cs.append(Vector3.ZERO)
		mat.set_shader_parameter("felder", mini(felder.size(), FELDER_MAX))
		mat.set_shader_parameter("feld_y", ys)
		mat.set_shader_parameter("feld_c", cs)
		mat.set_shader_parameter("band_hoehe", 1.0 - float(a.kopf))

	func _logo(key: String, bunt := false) -> Texture2D:
		if key == "" or not _logos.is_valid():
			return null
		var t: Variant = _logos.call(key, bunt)
		return t if t is Texture2D else null

	## Farben des Rückens (Titelfeld aus dem Cover bzw. fest, Felder; bei Kartons folgt das Kopfband
	## der Farbe des Rückens) samt Schrift.
	func _farbe_setzen(farbe: Color) -> void:
		var a := Regal.ruecken_aufbau(str(spiel.get("system", "")), region, farbe, nummer != "")
		var felder: Array = a.felder
		felder_setzen(_mat, a)
		_mat.set_shader_parameter("ruecken", a.grund)
		if _tex == null:
			_ersatz_farben(farbe)
		_titel.modulate = a.titel_farbe
		_nummer.modulate = a.titel_farbe
		for i in mini(felder.size(), 3):
			var f: Dictionary = felder[i]
			var sc: Color = f.get("schrift", Color.WHITE)
			(_f_text[i] as Label3D).modulate = sc
			var s: Sprite3D = _f_logo[i]
			s.modulate = Color.WHITE if s.texture and s.texture.has_meta("uz_bunt") else sc

	## Titel längs im Titelfeld, von oben nach unten, so groß, wie der Rücken es zulässt.
	func _titel_setzen(g: Dictionary, font: Font) -> void:
		var tl := titel_lage(g, masse, _aufbau, font)
		_titel.font = font
		_titel.font_size = int(tl.gr)
		_titel.pixel_size = float(tl.px)
		_titel.text = str(tl.text)
		_titel.basis = laengs()
		_titel.position = tl.pos
		_titel.visible = true

	## Text, Größe und Lage des Titels auf dem Rücken (Ursprung unten in der Mitte der Hülle) – auch
	## fürs Spieleregal im Zimmer (inhalt.gd), damit beide gleich aussehen.
	static func titel_lage(g: Dictionary, m: Vector3, aufbau: Dictionary, font: Font) -> Dictionary:
		var tb: Vector2 = aufbau.titel
		var platz := m.y * (tb.y - tb.x) * 0.92
		var gr := 44
		var px := m.x * 0.44 / (gr * 0.72)
		var titel := Regal.ruecken_titel(Library.display_title(g))
		var w := font.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x * px
		if w > platz:
			px = maxf(px * 0.74, px * platz / w)
			w = font.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x * px
			while w > platz and titel.length() > 4:
				titel = Regal.ruecken_titel(titel, titel.length() - 2)
				w = font.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x * px
		return { "text": titel, "gr": gr, "px": px, "pos": Vector3(0, m.y * (tb.x + tb.y) * 0.5, m.z * 0.5 + 0.0006) }

	## Seriennummer ganz unten, klein und quer (nur wenn bekannt).
	func _nummer_setzen(font: Font) -> void:
		var nb: Vector2 = _aufbau.nummer
		_nummer.visible = nummer != "" and nb.y > nb.x
		if not _nummer.visible:
			return
		var gr := 32
		var sw := maxf(1.0, font.get_string_size(nummer, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x)
		_nummer.font = font
		_nummer.font_size = gr
		_nummer.pixel_size = minf(masse.x * 0.8 / sw, masse.y * (nb.y - nb.x) * 0.36 / (gr * 0.72))
		_nummer.text = nummer
		_nummer.basis = Basis.IDENTITY
		_nummer.position = Vector3(0, masse.y * (nb.x + nb.y) * 0.5, masse.z * 0.5 + 0.0006)

	## Logos und Texte in den Feldern des Rückens: das echte Logo (zur Laufzeit, badge_logos.gd; das
	## PS-Zeichen farbig), sonst ein anderes Logo (logo_ersatz), sonst der Schriftzug bzw. das Kürzel
	## in Uzais Schrift.
	func _ruecken_setzen() -> void:
		hat_logo = false
		for s in _f_logo:
			(s as Sprite3D).visible = false
		for l in _f_text:
			(l as Label3D).visible = false
		var felder: Array = _aufbau.felder
		var z := masse.z * 0.5 + 0.0007
		for i in mini(felder.size(), 3):
			var f: Dictionary = felder[i]
			var fh := masse.y * (float(f.y1) - float(f.y0))
			var mitte := Vector3(0, masse.y * (float(f.y0) + float(f.y1)) * 0.5, z)
			var sc: Color = f.get("schrift", Color.WHITE)
			var lab: Label3D = _f_text[i]
			if str(f.get("text", "")) != "":
				_text_quer(lab, str(f.text), masse.x * 0.62, fh * 0.6, mitte, sc)
				continue
			var tex := _logo(str(f.get("logo", "")), bool(f.get("bunt", false)))
			if tex == null and str(f.get("logo_ersatz", "")) != "":
				tex = _logo(str(f.logo_ersatz))
			var spr: Sprite3D = _f_logo[i]
			if tex:
				var ts := Vector2(tex.get_size())
				spr.texture = tex
				spr.position = mitte
				spr.modulate = Color.WHITE if tex.has_meta("uz_bunt") else sc
				if bool(f.get("laengs", false)):
					spr.pixel_size = minf(fh * 0.86 / ts.x, masse.x * 0.5 / ts.y)
					spr.basis = laengs()
				elif bool(f.get("kurz", false)):
					var lage := Regal.logo_lage(ts, masse.x, fh)
					if float(lage.px) <= 0.0:
						continue
					spr.pixel_size = float(lage.px)
					spr.basis = Basis.IDENTITY if bool(lage.quer) else laengs()
				else:
					spr.pixel_size = minf(masse.x * 0.72 / ts.x, fh * 0.72 / ts.y)
					spr.basis = Basis.IDENTITY
				spr.visible = true
				hat_logo = true
				continue
			var ersatz := _mit_zeichen(str(f.get("ersatz", "")))
			if ersatz != "" and _font:
				var gr := 40
				var sw := maxf(1.0, _font.get_string_size(ersatz, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x)
				lab.font = _font
				lab.font_size = gr
				lab.pixel_size = minf(fh * 0.86 / sw, masse.x * 0.42 / (gr * 0.72))
				lab.text = ersatz
				lab.modulate = sc
				lab.basis = laengs()
				lab.position = mitte
				lab.visible = true
			elif bool(f.get("kurz", false)):
				var kurz := str(Config.system(str(spiel.get("system", ""))).get("short", ""))
				if kurz != "":
					_text_quer(lab, kurz, masse.x * 0.7, fh * 0.7, mitte, sc)

	func _text_quer(lab: Label3D, text: String, breite: float, hoehe: float, pos: Vector3, farbe: Color) -> void:
		if _font == null:
			return
		var gr := 32
		var sw := maxf(1.0, _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x)
		lab.font = _font
		lab.font_size = gr
		lab.pixel_size = minf(breite / sw, hoehe / (gr * 0.72))
		lab.text = text
		lab.modulate = farbe
		lab.basis = Basis.IDENTITY
		lab.position = pos
		lab.visible = true

	## „PlayStation®2“: das ® nur, wenn die Schrift es hat.
	func _mit_zeichen(t: String) -> String:
		if t.contains("®") and (_font == null or not _font.has_char(0xAE)):
			return t.replace("®", " ")
		return t

	## Ein Logo kam nachträglich (Download fertig) oder die Einstellung wechselte: Rücken und
	## Vorderseite neu.
	func logos_neu() -> void:
		_ruecken_setzen()
		_farbe_setzen(farbe_ist)
		_vorn_setzen()
		_ruecken_bild_zeigen()

	## Das Bild für die Vorderseite (null: Uzais Ersatz-Vorderseite, die Hülle zeichnet sie selbst).
	func cover_setzen(t: Texture2D) -> void:
		_tex = t
		_vorn_setzen()

	## Bild des echten Rückens (ScreenScraper box-2D-side; null: Uzais Aufbau). Liegt es quer, wird
	## es gedreht (von oben nach unten gelesen wie die Rücken).
	func ruecken_setzen(t: Texture2D) -> void:
		_rtex = t
		_mat.set_shader_parameter("hat_ruecken", t != null)
		if t:
			_mat.set_shader_parameter("ruecken_bild", t)
			_mat.set_shader_parameter("ruecken_quer", t.get_width() > t.get_height())
		_ruecken_bild_zeigen()

	## Mit dem Bild des echten Rückens entfallen Uzais Felder, Titel und Seriennummer.
	func _ruecken_bild_zeigen() -> void:
		if _rtex == null:
			return
		_titel.visible = false
		_nummer.visible = false
		for n in _f_logo + _f_text:
			(n as Node3D).visible = false
		hat_logo = false

	## Vorderseite wie die echte. Ein echter Scan (Regal.ist_scan) liegt unverändert auf dem
	## Einleger – kein eigenes Band, nie gestreckt, nie doppelt (Regal.einpassen: weicht sein Format ab,
	## bleibt ein schmaler Rand der Hülle). Sonst zeigt Uzai das Band des Systems in seiner echten Form
	## und Farbe (Regal.RAHMEN) – darin der Schriftzug (PS2: die Wortmarke „PlayStation®2“) und am
	## anderen Ende das Zeichen (PS2: das farbige PS-Logo), nur zur Laufzeit (badge_logos.gd), sonst der
	## Name in Uzais Schrift – über einem Motiv (randvoll zugeschnitten, Zuschnitt.gd) bzw. über Uzais
	## Ersatz-Vorderseite mit dem Titel.
	func _vorn_setzen() -> void:
		var sid := str(spiel.get("system", ""))
		var front := Vector2(masse.z, masse.y)
		var ein := Regal.einleger(sid)
		var rahmen := Regal.rahmen_von(sid)
		var look: Dictionary = _tex.get_meta("uz_look", {}) if _tex else {}
		scan = _tex != null and Regal.ist_scan(str(_tex.get_meta("uz_src", "")), look.get("r", {}))
		rahmen_drauf = not rahmen.is_empty() and not scan
		var rad := Regal.kanten_rad(sid)
		(_cover.mesh as QuadMesh).size = front - Vector2(rad, rad) * 2.0
		_cover.position = Vector3(0, 0, 0)
		var m := _vmat
		m.set_shader_parameter("seite", front)
		m.set_shader_parameter("rad", rad)
		m.set_shader_parameter("einleger", Vector4(ein.position.x, ein.position.y, ein.size.x, ein.size.y))
		m.set_shader_parameter("plastik", _fd.plastik)
		m.set_shader_parameter("schale", _fd.get("schale", _fd.plastik))
		m.set_shader_parameter("art", Regal.art_nr(sid))
		m.set_shader_parameter("klar", bool(_fd.get("klar", false)))
		m.set_shader_parameter("folie", float(_fd.folie))
		m.set_shader_parameter("scharnier", Regal.SCHARNIER)
		_ersatz_farben(farbe_ist)
		passt_bild = true
		m.set_shader_parameter("hat_bild", _tex != null)
		var flaeche := Regal.motiv_flaeche(ein.size, rahmen if rahmen_drauf else {})
		if _tex:
			var ts := Vector2(_tex.get_size())
			m.set_shader_parameter("bild", _tex)
			if scan:
				var e := Regal.einpassen(ts, ein.size)
				var l: Rect2 = e.lage
				var uv: Rect2 = e.uv
				m.set_shader_parameter("bild_lage", Vector4(l.position.x, l.position.y, l.size.x, l.size.y))
				m.set_shader_parameter("bild_uv", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
			else:
				var o := Vector2(_tex.get_meta("uz_orig") as Vector2i) if _tex.has_meta("uz_orig") else ts
				passt_bild = Regal.passt(o, flaeche.size)
				var reg := Zuschnitt.region(look, ts, flaeche.size)
				m.set_shader_parameter("bild_lage", Vector4(flaeche.position.x, flaeche.position.y, flaeche.size.x, flaeche.size.y))
				m.set_shader_parameter("bild_uv", Vector4(reg.position.x / ts.x, reg.position.y / ts.y, reg.size.x / ts.x, reg.size.y / ts.y))
		m.set_shader_parameter("band_seite", int(Regal.SEITEN.get(str(rahmen.get("seite", "")), -1)) if rahmen_drauf else -1)
		_rlogo.visible = false
		_rzeichen.visible = false
		_rtext.visible = false
		_vtitel.visible = false
		if not rahmen_drauf:
			return
		var a := float(rahmen.anteil)
		var bc: Color = rahmen.farbe
		m.set_shader_parameter("band_anteil", a)
		m.set_shader_parameter("band_form", int(Regal.FORMEN.get(str(rahmen.get("form", "gerade")), 0)))
		m.set_shader_parameter("band_farbe", bc)
		m.set_shader_parameter("band_farbe2", rahmen.get("farbe2", bc))
		m.set_shader_parameter("mit_linie", rahmen.has("linie"))
		m.set_shader_parameter("linie", rahmen.get("linie", bc))
		# Ursprung des Einlegers (unten links) in der Lage von _vorn (Mitte der Front).
		var o0 := ein.position - front * 0.5
		if _tex == null:
			_ersatz_titel(o0 + flaeche.position, flaeche.size)
		_band_inhalt(sid, rahmen, o0, ein.size)

	## Farben der Ersatz-Vorderseite: die Farbe des Rückens, wo sie aus dem Spiel kommt, sonst die
	## des Systems (je Spiel etwas anders) – oben heller, unten tief.
	func _ersatz_farben(f: Color) -> void:
		if _fd.get("ruecken") is Color:
			var sys := Config.system(str(spiel.get("system", "")))
			f = Regal.ruecken_farbe(null, Color(str(sys.get("color", "#3a3a42"))), str(spiel.get("id", "")))
		var h := Color.from_hsv(f.h, clampf(f.s * 1.1, 0.25, 0.75), clampf(f.v, 0.4, 0.7))
		_vmat.set_shader_parameter("grund", h)
		_vmat.set_shader_parameter("grund2", h.darkened(0.7))

	## Titel groß in der Mitte der Ersatz-Vorderseite (Uzais Schrift, umbrochen).
	func _ersatz_titel(o: Vector2, fl: Vector2) -> void:
		if _font == null:
			return
		var titel := Regal.ruecken_titel(Library.display_title(spiel), 60)
		var gr := 64
		var px := fl.x * 0.8 / 720.0
		_vtitel.font = _font
		_vtitel.font_size = gr
		_vtitel.pixel_size = px
		_vtitel.width = 720.0
		_vtitel.text = titel
		_vtitel.modulate = Color("#f3f2ef")
		_vtitel.position = Vector3(o.x + fl.x * 0.5, o.y + fl.y * 0.62, 0.0006)
		_vtitel.visible = true

	## Schriftzug und Zeichen im Band: oben und unten quer, links und rechts längs (von unten nach
	## oben gelesen wie auf den echten Streifen). Lage des Schriftzugs nach marke_lage.
	func _band_inhalt(sid: String, rahmen: Dictionary, o: Vector2, ein: Vector2) -> void:
		var seite := str(rahmen.seite)
		var quer := seite in ["oben", "unten"]
		var a := float(rahmen.anteil)
		var dick := (ein.y if quer else ein.x) * a
		var lang := ein.x if quer else ein.y
		# Mitte des Bands quer zu seiner Richtung und Lage entlang (0 … lang) → Punkt auf _vorn.
		var mitte := 0.0
		match seite:
			"oben":
				mitte = o.y + ein.y - dick * 0.5
			"unten":
				mitte = o.y + dick * 0.5
			"links":
				mitte = o.x + dick * 0.5
			"rechts":
				mitte = o.x + ein.x - dick * 0.5
		var punkt := func(s: float) -> Vector3:
			return Vector3(o.x + s, mitte, 0.0006) if quer else Vector3(mitte, o.y + s, 0.0006)
		var lf: Color = rahmen.logo
		var rand := dick * 0.35
		var dreh := Basis.IDENTITY if quer else Basis(Vector3.FORWARD, -PI * 0.5)
		# Zeichen: am Ende (rechts bzw. oben), quadratisch, nie gedreht.
		var zl := 0.0
		var zd := Regal.zeichen_von(sid, region)
		var ztex: Texture2D = null
		if not zd.is_empty():
			ztex = _logo(str(zd.key), bool(zd.bunt))
			if ztex == null and str(zd.ersatz) != "":
				ztex = _logo(str(zd.ersatz))
		if ztex:
			var zs := Vector2(ztex.get_size())
			var zpx := minf(dick * 0.66 / maxf(1.0, zs.y), dick * 0.86 / maxf(1.0, zs.x))
			zl = (zs.x if quer else zs.y) * zpx
			_rzeichen.texture = ztex
			_rzeichen.pixel_size = zpx
			_rzeichen.modulate = Color.WHITE if ztex.has_meta("uz_bunt") else lf
			_rzeichen.basis = Basis.IDENTITY
			_rzeichen.position = punkt.call(lang - rand - zl * 0.5)
			_rzeichen.visible = true
		var platz := lang * (0.5 if quer else 0.62)
		var hoch := dick * 0.62
		var knoten: Node3D = null
		var bl := 0.0
		var ltex := _logo(Regal.marke_von(sid))
		if ltex:
			var px := minf(platz / ltex.get_width(), hoch / ltex.get_height())
			_rlogo.texture = ltex
			_rlogo.pixel_size = px
			_rlogo.modulate = Color.WHITE if ltex.has_meta("uz_bunt") else lf
			_rlogo.visible = true
			bl = ltex.get_width() * px
			knoten = _rlogo
		else:
			var name := _mit_zeichen(str(rahmen.get("name", Config.system(sid).get("name", ""))))
			if name == "" or _font == null:
				return
			var gr := 48
			var sw := maxf(1.0, _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, gr).x)
			var px2 := minf(platz / sw, hoch / (gr * 0.72))
			_rtext.font = _font
			_rtext.font_size = gr
			_rtext.pixel_size = px2
			_rtext.text = name
			_rtext.modulate = lf
			_rtext.visible = true
			bl = sw * px2
			knoten = _rtext
		knoten.basis = dreh
		var s0 := rand + bl * 0.5
		match str(rahmen.get("marke_lage", "")):
			"mitte":
				s0 = lang * 0.5
			"rechts":
				s0 = lang - rand - zl - (rand if zl > 0.0 else 0.0) - bl * 0.5
		knoten.position = punkt.call(s0)

	## Ein Schritt der Bewegung; true, solange sich etwas bewegt.
	func schritt(dt: float, w: Node) -> bool:
		var gewaehlt := idx == int(w.auswahl)
		var nachbar := absi(idx - int(w.auswahl)) == 1
		var ziel := float(w.zieh_ziel) if gewaehlt else 0.0
		var vorher := p
		if bool(w.ruhig):
			var f := U.spring_step(p, pv, ziel, dt, 30.0)
			p = f.x
			pv = f.y
		else:
			var f2 := Regal.feder(p, pv, ziel, dt, 13.0, 0.74)
			p = f2.x
			pv = f2.y
		var lage := Regal.zug_lage(p, masse.z, float(w.hoehe) / 0.19)
		var mit := 0.0
		if nachbar:
			# Die Nachbarn rutschen ein Stück mit (Reibung), bevor die Hülle frei ist.
			var andere: Huelle = (w.get("_huellen") as Dictionary).get(int(w.auswahl))
			if andere:
				mit = clampf(andere.p, 0.0, 1.0) * 0.006
		var kipp := 0.0
		if kipp_ab >= 0.0:
			var t := (float(w.get("_zeit")) - kipp_ab) / 0.55
			if t >= 1.0:
				kipp_ab = -1.0
			elif t >= 0.0:
				kipp = deg_to_rad(11.0) * exp(-4.6 * t) * cos(t * 7.5)
			else:
				kipp = deg_to_rad(11.0)
		var neig := float(w.get("_lean")) * (0.8 + float(absi(idx * 7919) % 100) / 250.0) * (1.0 - clampf(p, 0.0, 1.0))
		position = Vector3(x0, float(lage.hoch), -masse.z * 0.5 + float(lage.vor) + mit)
		rotation = Vector3(kipp, deg_to_rad(float(lage.dreh)), neig)
		if not farbe_ist.is_equal_approx(farbe_soll):
			farbe_ist = farbe_ist.lerp(farbe_soll, clampf(dt * 6.0, 0.0, 1.0))
			if farbe_ist.is_equal_approx(farbe_soll) \
					or (Vector3(farbe_ist.r, farbe_ist.g, farbe_ist.b) - Vector3(farbe_soll.r, farbe_soll.g, farbe_soll.b)).length() < 0.004:
				farbe_ist = farbe_soll
			_farbe_setzen(farbe_ist)
		var gl := clampf(p, 0.0, 1.0)
		if absf(gl - _glimmen) > 0.002:
			_glimmen = gl
			_mat.set_shader_parameter("glimmen", gl)
			_vmat.set_shader_parameter("glimmen", gl)
		return absf(p - vorher) > 0.0004 or absf(pv) > 0.01 or kipp_ab >= 0.0

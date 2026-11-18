extends Node3D
## Die 3D-Welt des Zimmers, gebaut aus den Daten (zimmer_daten.gd): Hülle mit Licht (raum.gd),
## Möbel (moebel.gd) und was darin steht (inhalt.gd), dazu Kamera, eigene Nachbearbeitung
## (Umgebungsverdeckung, Tiefenunschärfe, Vignette) und das Bild im Fernseher. Bedienung und
## Kamerafahrten macht zimmer.gd; diese Datei weiß nur, was wo steht.
##
## Qualitätsstufen (licht.gd STUFE_WERTE): Hoch und Mittel mit Sonnenschatten und eigener
## Nachbearbeitung (unterschiedlich viele Proben), Leicht (am leichten Modus, Punkt 65) ohne echte
## Schatten und ohne Nachbearbeitung – der Sonnenfleck kommt dann aus den Hüllen-Shadern.
## Licht ändern (Anpassung): licht_neu() nach Tageszeit oder Stimmung, lampe_neu(i) nach einer Lampe.

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Raum := preload("res://src/room/raum.gd")
const Moebel := preload("res://src/room/moebel.gd")
const Licht := preload("res://src/room/licht.gd")
const Lichtbacken := preload("res://src/room/lichtbacken.gd")
const Inhalt := preload("res://src/room/inhalt.gd")
const S := preload("res://src/room/stoffe.gd")
const F := preload("res://src/room/formen.gd")
const G := preload("res://src/room/gestalt.gd")
const NACH_S := preload("res://src/room/shaders/nach.gdshader")
const RASTER_S := preload("res://src/room/shaders/raster.gdshader")
const Spielbild := preload("res://src/room/spielbild.gd")
const Konsolen := preload("res://src/room/konsolen.gd")
const U := preload("res://src/ui/u.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")
const Boot := preload("res://src/ui/boot.gd")
## Licht des Fernsehers auf Boden und Wänden (mal Stimmung, abends und nachts voll, am Tag 0,3) – wie vor 0.16.39.
const TV_LICHT := 0.9

var raum: Dictionary = {}
var leicht := false
var stufe := "mittel"
var werte: Dictionary = {}    ## Werte der Stufe (licht.gd STUFE_WERTE)
var huelle: Raum
var backen: Lichtbacken      ## gebackenes Licht der Hülle (nur Forward+)
var knoten: Array = []        ## je Möbel (Index wie raum.moebel) der Knoten
var boxen: Array = []         ## je Möbel die Hülle in Weltkoordinaten (AABB)
var plaetze := {}             ## Möbel-Index → Plätze (Hüllen, Pokale, Platten)
var kamera: Camera3D
var _schnitt_lage := -1        ## zuletzt geschnitten (schnitt): von oben, Seiten der Kamera, Möbel, Bau der Hülle
var _knoten_nr := 0            ## zählt jeden neuen Möbelknoten (schnitt)
var nach_mat: ShaderMaterial
var raster: MeshInstance3D
var raster_mat: ShaderMaterial
var tv_vp: SubViewport
var tv_titel: Label
var tv_zeile: Label
var tv_marke: Control         ## Zeichen und Wortmarke oben links im Ruhebild
var tv_licht: ColorRect
var tv_spiel: TextureRect     ## das laufende Spiel (Stufe 2, spielbild.gd), liegt über allem
var laeuft_titel := ""        ## läuft ein Spiel: sein Titel (Fernseher ohne Bild: „Läuft gerade“)
var _tv_tex: ImageTexture
var _moebel_root: Node3D
var _tv_farbe := Color("#e7c27d")
var _tv_farbe_ms := -100000         ## wann die Farbe des Lichts zuletzt aus dem Spielbild kam
var _tv_flimmer := 1.0           ## Licht des Fernsehers flimmert leicht mit dem Bild (zimmer.gd _lebendig)
var schlank := false              ## schlanker Weg neben dem laufenden Spiel (zimmer_basis.gd _spar_setzen)
## Lichter der Hülle, wie lampen_auffrischen sie zuletzt gesetzt hat – das Flimmern des Fernsehers ändert
## nur dessen Eintrag (_tv_licht), statt alle Lampen neu zu sammeln.
var _hl_n := 0
var _hl_pos := PackedVector4Array()
var _hl_farbe := PackedVector4Array()
var _hl_dir := PackedVector4Array()
var _hl_tv := -1                  ## Platz des Fernsehers in den Lichtern der Hülle (-1: nicht dabei)
var _hl_tv_en := 0.0              ## seine Stärke ohne Flimmern
var _teppich_mats: Array = []
var _ao_tex: Texture2D           ## die letzte Karte der Kontaktschatten (boden_schatten)
var _ao_lauf := 0                ## zählt die Aufträge dafür: nur das Ergebnis des letzten gilt
var _vignette: TextureRect
var _vignette_soll := 1.0          ## Deckkraft der Vignette nach der Stimmung
var _vignette_leise := false
var _schirme: Array = []           ## Bildschirme der Möbel (MeshInstance3D mit bildschirm.gdshader)
var _nach_flaeche: MeshInstance3D    ## Fläche der Nachbearbeitung vor der Kamera (nach.gdshader)
var huellen := {}             ## Hüllenart je System (aus zimmer.json, für alle Regale)


func bauen(r: Dictionary, s: String) -> void:
	_bau_anfang(r, s)
	alle_moebel()
	licht_neu()
	karten_merken()


## Wie bauen(), nur über mehrere Bilder verteilt – für Zimmer, die neben der Oberfläche entstehen (das kleine
## Zimmerbild im Profil, zimmer_bild.gd). In einem Zug hielt der erste Bau alles rund 1 s lang an (gemessen: Hülle
## 0,2 s, Möbel 0,7 s; ihre Netze entstehen beim ersten Mal, danach kommen sie aus dem Zwischenspeicher – der
## zweite Bau kostet 0,1 s). Hier entsteht je Bild so viel, wie in je_bild_ms passt; ein einzelnes großes Möbel
## kann darüber liegen (Medienwand beim ersten Mal 0,2 s). frei sagt, ob gerade gebaut werden darf (sonst wartet
## der Bau, etwa solange ein Bereich hereingleitet). Wer so baut, zeigt die Welt erst danach und gibt sie vorher
## nicht frei. Zurück: false, wenn die Welt unterwegs den Baum verlassen hat.
func bauen_gestreckt(r: Dictionary, s: String, frei := Callable(), je_bild_ms := 6) -> bool:
	var baum := get_tree()
	_bau_anfang(r, s)
	_moebel_leeren()
	var t := 0
	for i in (raum.moebel as Array).size():
		# Vor jedem Möbel: ist die Zeit dieses Bildes um (oder ruht der Bau), das nächste Bild abwarten.
		while t == 0 or Time.get_ticks_msec() - t >= je_bild_ms or (frei.is_valid() and not frei.call()):
			await baum.process_frame
			if not is_inside_tree():
				return false
			if not frei.is_valid() or frei.call():
				t = Time.get_ticks_msec()
		knoten.append(_moebel_knoten(i))
		boxen.append(AABB())
	await baum.process_frame
	if not is_inside_tree():
		return false
	_moebel_boxen()
	inhalt_fuellen()
	await baum.process_frame
	if not is_inside_tree():
		return false
	boden_schatten()
	huelle.sonde_neu()
	licht_neu()
	karten_merken()
	return true


# --- Vorladen ------------------------------------------------------------------------------------
# Was ein Bau von der Platte holt – Karten der Stoffe (assets/zimmer/tex) und Modelle (assets/zimmer/modelle) –,
# lädt sonst mitten im Bau im Hauptfaden (gemessen: die Karten der Hülle zusammen 0,13 s, ein Ledersofa 0,8 s).
# Wer Zeit hat (das Zimmerbild im Profil, die Tür zum Zimmer), lädt es vorab im Hintergrund (Arbeit.vorladen); der
# Bau findet es dann fertig vor. Die Modelle ergeben sich aus den Möbeln des Raums. Welche Karten ein Zimmer
# braucht, merkt sich Uzai vom letzten Bau (cache/zimmer_karten.json: nur Namen, die stoffe.gd gegen seine feste
# Liste prüft).

const KARTEN_DATEI := "cache/zimmer_karten.json"
const KARTEN_DATEI_MAX := 8192
static var _karten_stand := ""          ## zuletzt gelesene bzw. geschriebene Namen (kein Schreiben ohne Änderung)


## Die Dateien, die der Bau dieses Raums voraussichtlich lädt.
static func vorlade_pfade(r: Dictionary) -> Array[String]:
	var namen: Array = []
	var datei := Config.path(KARTEN_DATEI)
	if FileAccess.file_exists(datei) and FileAccess.get_size(datei) <= KARTEN_DATEI_MAX:
		var v: Variant = Config.read_json(datei, [])
		if v is Array:
			namen = v
	var out := S.karten_pfade(namen)
	if _karten_stand == "":
		_karten_stand = ",".join(PackedStringArray(namen.filter(func(n: Variant) -> bool: return n is String)))
	var moebel: Variant = r.get("moebel", [])
	out.append_array(Moebel.modell_pfade(moebel if moebel is Array else []))
	return out


## Nach einem Bau: die Karten merken, die bis hierher gebraucht wurden.
static func karten_merken() -> void:
	var namen := S.karten_gebraucht()
	var stand := ",".join(namen)
	if stand == _karten_stand:
		return
	_karten_stand = stand
	Config.write_json(Config.path(KARTEN_DATEI), Array(namen))


## Hülle, Kamera, Nachbearbeitung, Raster und Fernsehbild: alles außer den Möbeln und ihrem Licht.
func _bau_anfang(r: Dictionary, s: String) -> void:
	raum = r
	stufe = s if Licht.STUFE_WERTE.has(s) else "mittel"
	werte = Licht.werte(stufe)
	leicht = stufe == "leicht"
	# Forward+: Kontakt und Verdeckung kommen aus SSAO und SDFGI, nicht aus der Eckpunktfarbe.
	F.ao_an = str(werte.get("renderer", "forward")) != "forward"
	huelle = Raum.new()
	add_child(huelle)
	huelle.bauen(raum, werte)
	huelle.connect("lampen_geaendert", lampen_auffrischen)
	# Forward+: das Licht der Hülle wird gebacken (lichtbacken.gd), sobald sich etwas ändert.
	if bool(huelle.forward):
		backen = Lichtbacken.new()
		backen.name = "Lichtbacken"
		backen.huelle = huelle
		backen.stufe = stufe
		backen.sonne_backen = not leicht
		add_child(backen)
		huelle.connect("licht_geaendert", backen.anstossen)
		backen.anstossen()
	_moebel_root = Node3D.new()
	_moebel_root.name = "moebel"
	add_child(_moebel_root)
	kamera = Camera3D.new()
	kamera.fov = 70.0
	kamera.near = 0.03
	kamera.far = 60.0
	kamera.current = true
	add_child(kamera)
	_nachbearbeitung()
	_raster()
	_fernsehbild()
	_vignette_bauen()


## Alle Möbel neu (nach Rückgängig oder beim Aufbau) samt Inhalt.
func alle_moebel() -> void:
	_moebel_leeren()
	for i in (raum.moebel as Array).size():
		knoten.append(_moebel_knoten(i))
		boxen.append(AABB())
	_moebel_boxen()
	inhalt_fuellen()
	boden_schatten()
	huelle.sonde_neu()


## Möbel stehen anders (verschoben, gedreht), ihre Knoten bleiben: neue Lage, Hüllen, Bodenschatten, Licht.
## Der Bau eines Möbels hängt nicht von Ort und Drehung ab (moebel.gd bauen_it) – alle neu zu bauen
## (alle_moebel) kostete bei jedem Absetzen 26 ms im Standardzimmer (gemessen), ohne dass sich an einem
## Knoten etwas änderte.
func moebel_versetzt(indizes: Array) -> void:
	for v: Variant in indizes:
		var i := int(v)
		if i >= 0 and i < knoten.size() and i < (raum.moebel as Array).size() and is_instance_valid(knoten[i]):
			setze_ort(knoten[i], raum.moebel[i], i)
	# Der Schnitt der Wände (schnitt) und die Quader fürs Laufen (zimmer.gd) rechnen an dieser Nummer neu.
	_knoten_nr = (_knoten_nr + 1) % 0x40000
	_moebel_boxen()
	boden_schatten()
	huelle.sonde_neu()


## Ein Möbel kam ans Ende von raum.moebel dazu: nur sein Knoten wird gebaut, die anderen bleiben.
func moebel_dazu() -> void:
	if knoten.size() + 1 != (raum.moebel as Array).size():
		alle_moebel()          # passt nicht zusammen: lieber alles neu
		return
	knoten.append(_moebel_knoten(knoten.size()))
	boxen.append(AABB())
	_moebel_boxen()
	inhalt_fuellen()
	boden_schatten()
	huelle.sonde_neu()


func _moebel_leeren() -> void:
	for n in knoten:
		if is_instance_valid(n):
			n.queue_free()
	knoten.clear()
	boxen.clear()


## Stehen alle Möbel: ihre Hüllen (boxen) und die Ebene der Teppiche.
func _moebel_boxen() -> void:
	for i in knoten.size():
		boxen[i] = box_von(knoten[i])
		# Kompatibilität: Teppiche bekommen das Licht wie die Hülle im Shader (Forward+: echte Lichter;
		# die Hülle selbst ist dort gebacken).
		if Katalog.ebene(str(raum.moebel[i].t)) == "teppich" and not bool(huelle.forward):
			for c in (knoten[i] as Node3D).get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).layers = Raum.HUELLE_EBENE


func _moebel_knoten(i: int) -> Node3D:
	var it: Dictionary = raum.moebel[i]
	if str(it.get("t", "")) == "medienwand":
		Moebel.konsolen = konsolen_ids()
	var n := Moebel.bauen_it(it)
	_knoten_nr = (_knoten_nr + 1) % 0x40000
	Moebel.konsolen = []
	_moebel_root.add_child(n)
	if n.has_meta("konsolen"):
		konsolen_strom(n)
	if leicht:
		_ohne_schatten(n)
	schatten_sparen(n, str(it.get("t", "")))
	_bewegtes_merken(n)
	setze_ort(n, it, i)
	if n.has_meta("bildschirm"):
		var bs: MeshInstance3D = n.get_meta("bildschirm")
		(bs.material_override as ShaderMaterial).set_shader_parameter("bild", tv_vp.get_texture())
	_schirme_sammeln(n)
	return n


## Alle Bildschirme eines Möbels (Fernseher, Monitor) merken: Sie gleichen die Nachbearbeitung aus.
func _schirme_sammeln(n: Node) -> void:
	_schirme = _schirme.filter(func(mi: Variant) -> bool: return is_instance_valid(mi))
	var stapel: Array[Node] = [n]
	while not stapel.is_empty():
		var k: Node = stapel.pop_back()
		stapel.append_array(k.get_children())
		if k is MeshInstance3D and (k as MeshInstance3D).material_override is ShaderMaterial \
				and ((k as MeshInstance3D).material_override as ShaderMaterial).shader == Moebel.BILDSCHIRM_S:
			_schirme.append(k)
	tv_ton()


## Das Spielbild bleibt, wie es ist: Die Bildschirme bekommen Belichtung, Tonemapping, Kontrast,
## Sättigung und Farbkorrektur des Zimmers, um sie rückwärts auszugleichen (bildschirm.gdshader),
## und die Schwelle des Glühens, unter der ihr Leuchten bleibt.
func tv_ton() -> void:
	if huelle == null or huelle.env == null:
		return
	var env: Environment = huelle.env
	var ton := 0
	if env.tonemap_mode == Environment.TONE_MAPPER_AGX:
		ton = 4
	elif env.tonemap_mode == Environment.TONE_MAPPER_FILMIC:
		ton = 2
	var lut_an := env.adjustment_enabled and huelle.lut_umkehr != null
	# Ohne Typ in der Schleife: Ein freigegebener Bildschirm (Stufenwechsel baut neu) ließe sonst schon die
	# Zuweisung scheitern, vor der Prüfung.
	for v: Variant in _schirme:
		if not is_instance_valid(v):
			continue
		var m := (v as MeshInstance3D).material_override as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("ton", ton)
		m.set_shader_parameter("weiss", env.tonemap_white)
		m.set_shader_parameter("belichtung", env.tonemap_exposure)
		m.set_shader_parameter("kontrast", env.adjustment_contrast if env.adjustment_enabled else 1.0)
		m.set_shader_parameter("saettigung", env.adjustment_saturation if env.adjustment_enabled else 1.0)
		m.set_shader_parameter("lut_an", lut_an)
		m.set_shader_parameter("lut_umkehr", huelle.lut_umkehr)
		m.set_shader_parameter("grenze", env.glow_hdr_threshold * 0.95 if env.glow_enabled else 100.0)


## Sitzt du vor dem Fernseher, liegt keine Vignette über dem Bild (sie dunkelte die Ecken des Spiels).
func vignette_leise(an: bool) -> void:
	if _vignette == null or an == _vignette_leise:
		return
	_vignette_leise = an
	create_tween().tween_property(_vignette, "modulate:a", 0.0 if an else _vignette_soll, U.T_RAUM)


## Nur ein Möbel neu bauen (Anpassen): Knoten tauschen, Hülle, Inhalt der Regale und Licht
## auffrischen (Farbe und Material ändern den Kontaktschatten nicht; schatten: doch neu rechnen).
## Mit „pop“ setzt es sich sichtbar weich an seinen Platz.
func moebel_neu(i: int, pop := true, schatten := false) -> Node3D:
	if i < 0 or i >= knoten.size():
		return null
	var alt: Node3D = knoten[i]
	var n := _moebel_knoten(i)
	knoten[i] = n
	if is_instance_valid(alt):
		alt.queue_free()
	boxen[i] = box_von(n)
	huelle.sonde_neu()
	if Katalog.nutzen(str(raum.moebel[i].t)) in ["spiele", "pokale", "platten"]:
		inhalt_fuellen()
	lampen_auffrischen()
	if schatten:
		boden_schatten()
	if pop:
		var t := n.transform
		n.scale = Vector3(0.97, 0.97, 0.97)
		n.transform = Transform3D(t.basis.scaled(Vector3(0.97, 0.97, 0.97)), t.origin)
		U.ankommen(n, U.T_ORT, "uz_pop").tween_property(n, "transform", t, U.T_ORT)
	return n


## Kleinteile werfen keine Schatten: Jeder Schatten wird in jedem Bild neu gezeichnet (Sonne immer, die
## Lampen, solange sich in ihrer Reichweite etwas bewegt – die Figur atmet), je Lampe in sechs
## Würfelseiten. Teile unter SCHATTEN_KLEIN (Griffe, Knöpfe, Tasse, Pokale, Kleinkram im Regal) werfen
## nur fingerbreite Schatten, die SSAO und der Kontaktschatten am Boden ohnehin zeigen; flache Dinge an
## der Wand (FLACH_OHNE_SCHATTEN) werfen keinen sichtbaren. Pflanzen behalten ihre Blätterschatten.
const SCHATTEN_KLEIN := 0.16
const FLACH_OHNE_SCHATTEN := ["bild", "poster", "wanduhr", "lichterkette", "led_leiste", "neonschild", "bilderwand", "wanduhr_strahlen",
	"lichtervorhang", "girlande"]


static func schatten_sparen(n: Node, typ: String) -> void:
	if "pflanze" in typ or typ == "vase_blumen":
		return
	var alles := typ in FLACH_OHNE_SCHATTEN
	var stapel: Array = [[n, Vector3.ONE]]
	while not stapel.is_empty():
		var e: Array = stapel.pop_back()
		var k: Node = e[0]
		var sk: Vector3 = e[1]
		if k is Node3D:
			sk = sk * (k as Node3D).transform.basis.get_scale()
		for c in k.get_children():
			stapel.append([c, sk])
		if not (k is GeometryInstance3D) or (k as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			continue
		var gr := (k as VisualInstance3D).get_aabb().size * sk
		if alles or maxf(gr.x, maxf(gr.y, gr.z)) < SCHATTEN_KLEIN:
			(k as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Was sich im laufenden Bild bewegt (Pflanzen wiegen sich, Plattenteller, Tonarm): wirft dort keinen
## Schatten (die Lampenschatten blieben sonst nie liegen), beim Backen schon (lichtbacken.gd).
static func _bewegtes_merken(n: Node3D) -> void:
	var teile: Array = []
	for e: Array in n.get_meta("wiegen", []):
		teile.append(e[0])
	for k in ["teller", "tonarm", "tonarm_hub"]:
		if n.has_meta(k):
			teile.append(n.get_meta(k))
	for t: Variant in teile:
		if not (t is Node):
			continue
		var stapel: Array[Node] = [t as Node]
		while not stapel.is_empty():
			var k: Node = stapel.pop_back()
			stapel.append_array(k.get_children())
			if k is GeometryInstance3D and (k as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				k.set_meta("uz_backschatten", true)
				(k as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _ohne_schatten(n: Node) -> void:
	for c in n.get_children():
		if c is Light3D:
			(c as Light3D).shadow_enabled = false
		_ohne_schatten(c)


## Lage eines Möbels aus seinen Daten: Mitte der belegten Felder, gedreht, auf seiner Höhe.
func lage(it: Dictionary, ohne := -1) -> Transform3D:
	var g := Katalog.groesse_it(it)
	var z := Katalog.ZELLE
	var y := Daten.standhoehe(raum, it, ohne)
	var p := Vector3((float(it.x) + g.x * 0.5) * z, y, (float(it.z) + g.y * 0.5) * z)
	return Transform3D(Basis(Vector3.UP, float(it.r) * PI * 0.5), p)


func setze_ort(n: Node3D, it: Dictionary, ohne := -1) -> void:
	n.transform = lage(it, ohne)


## Hülle eines Möbels in Weltkoordinaten (aus allen sichtbaren Teilen, ohne Schatten und Licht).
func box_von(n: Node3D) -> AABB:
	var out := AABB()
	var erst := true
	var stapel: Array = [[n, n.transform]]
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


## Kontaktschatten aller Möbel in eine Karte des Bodens (von oben, 48 Bildpunkte je Meter):
## weiche, abgerundete Flecken unter allem, was auf dem Boden steht. Boden und Teppiche
## verrechnen sie mit ihrer Farbe.
const AO_DICHTE := 48.0


func boden_schatten() -> void:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	var bw := int(w * AO_DICHTE)
	var bh := int(d * AO_DICHTE)
	# Die Flecken (Mitte, Größe, Stärke, rund, weich) liest der Hauptfaden aus den Möbeln …
	var flecken: Array = []
	for n in knoten:
		var nt := (n as Node3D).transform
		for sch in (n as Node3D).get_meta("schatten", []):
			var m: Vector3 = nt * (sch[0] as Vector3)
			var g: Vector2 = sch[1]
			# Gedreht um 90° oder 270°: Breite und Tiefe tauschen.
			if absf(nt.basis.x.z) > 0.5:
				g = Vector2(g.y, g.x)
			flecken.append([m.x, m.z, g.x, g.y, float(sch[2]), bool(sch[3]), float(sch[4])])
	# Teppiche und Lampen sofort (die Teppiche behalten bis dahin die letzte Karte).
	_teppich_mats.clear()
	for i in knoten.size():
		if Katalog.ebene(str(raum.moebel[i].t)) == "teppich":
			for c in (knoten[i] as Node3D).get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
					var sm := (c as MeshInstance3D).material_override as ShaderMaterial
					if _ao_tex != null:
						sm.set_shader_parameter("ao_karte", _ao_tex)
					sm.set_shader_parameter("ao_raum", Vector2(w, d))
					if not _teppich_mats.has(sm):
						_teppich_mats.append(sm)
	lampen_auffrischen()
	# … die Karte selbst rechnet der Hilfsfaden: Bildpunkt für Bildpunkt im Skript, gemessen 22 ms im
	# Standardzimmer – bei jedem Absetzen, Drehen, Wegräumen und Rückgängig stand dafür das Bild. Sie kommt
	# ein, zwei Bilder später; folgt inzwischen ein neuer Stand, gilt nur der letzte.
	_ao_lauf += 1
	var lauf := _ao_lauf
	var bytes: Variant = await Arbeit.ergebnis(ao_karte.bind(bw, bh, flecken))
	if lauf != _ao_lauf or not is_inside_tree() or huelle == null or not (bytes is PackedByteArray):
		return
	_ao_tex = ImageTexture.create_from_image(Image.create_from_data(bw, bh, false, Image.FORMAT_L8, bytes))
	(huelle as Node).call("setze_ao", _ao_tex)
	for sm: ShaderMaterial in _teppich_mats:
		if is_instance_valid(sm):
			sm.set_shader_parameter("ao_karte", _ao_tex)


## Die Karte der Kontaktschatten (ein Byte je Bildpunkt, 255 = kein Schatten) aus den Flecken
## [x, z, Breite, Tiefe, Stärke, rund, weich] in Metern. Reine Rechnung, läuft im Hilfsfaden.
static func ao_karte(bw: int, bh: int, flecken: Array) -> PackedByteArray:
	var werte := PackedFloat32Array()
	werte.resize(bw * bh)
	werte.fill(1.0)
	for f: Array in flecken:
		var mx: float = f[0]
		var mz: float = f[1]
		var g := Vector2(float(f[2]), float(f[3]))
		var st: float = f[4]
		var rund: bool = f[5]
		var weich: float = f[6]
		var x0 := clampi(int((mx - g.x * 0.5 - weich) * AO_DICHTE), 0, bw - 1)
		var x1 := clampi(int((mx + g.x * 0.5 + weich) * AO_DICHTE), 0, bw - 1)
		var z0 := clampi(int((mz - g.y * 0.5 - weich) * AO_DICHTE), 0, bh - 1)
		var z1 := clampi(int((mz + g.y * 0.5 + weich) * AO_DICHTE), 0, bh - 1)
		var r := minf(0.06, minf(g.x, g.y) * 0.3)
		for pz in range(z0, z1 + 1):
			for px in range(x0, x1 + 1):
				var p := Vector2((px + 0.5) / AO_DICHTE - mx, (pz + 0.5) / AO_DICHTE - mz)
				var sd: float
				if rund:
					sd = (p / (g * 0.5)).length() * minf(g.x, g.y) * 0.5 - minf(g.x, g.y) * 0.5
				else:
					var q := Vector2(absf(p.x), absf(p.y)) - g * 0.5 + Vector2(r, r)
					sd = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
				var a := 1.0 - smoothstep(-weich * 0.25, weich, sd)
				if a <= 0.0:
					continue
				var i := pz * bw + px
				werte[i] = werte[i] * (1.0 - st * pow(a, 1.6))
	var bytes := PackedByteArray()
	bytes.resize(bw * bh)
	for i in werte.size():
		bytes[i] = int(clampf(werte[i], 0.0, 1.0) * 255.0)
	return bytes


# --- Inhalt --------------------------------------------------------------------------------------

## Spiele, Pokale und Platten in die Regale. Regale mit derselben Auswahl und Sortierung teilen
## sich ihre Spiele (über alle Fächer verteilt, nicht ein Fach voll, der Rest leer); eine eigene
## Reihenfolge und selbst Eingeräumtes gelten nur für ihr Regal (Eingeräumtes steht Fach für Fach
## dicht, ab Augenhöhe). Was vorher drin stand, wird vorher weggeräumt.
func inhalt_fuellen() -> void:
	plaetze.clear()
	var gruppen := {}            ## Schlüssel → { liste, faecher, bei }
	var pokale := {}
	var platten := {}
	var schilder: Array = []
	var cover := 0
	for i in knoten.size():
		var it: Dictionary = raum.moebel[i]
		var t := str(it.t)
		if not (t in ["spieleregal", "trophaeenschrank", "plattenregal"]):
			continue
		var n: Node3D = knoten[i]
		for c in n.get_children():
			if c.has_meta("uz_inhalt"):
				c.queue_free()
		var rg: Dictionary = it.get("rg", G.std_regal(t))
		if t == "spieleregal":
			var k := regal_gruppe(rg, i)
			if not gruppen.has(k):
				gruppen[k] = { "liste": Inhalt.spiele(rg), "faecher": 0, "bei": 0 }
			gruppen[k].faecher += ((n.get_meta("faecher", []) as Array).size())
	for i in knoten.size():
		var it: Dictionary = raum.moebel[i]
		var t := str(it.t)
		var n: Node3D = knoten[i]
		var rg: Dictionary = it.get("rg", G.std_regal(t))
		var vorher := n.get_child_count()
		var r := {}
		match t:
			"spieleregal":
				var k := regal_gruppe(rg, i)
				var gr: Dictionary = gruppen[k]
				var liste: Array = gr.liste
				var pro_fach := 999 if str(rg.get("fi", "")) == "eigene" else maxi(6, ceili(float(liste.size()) / float(maxi(1, int(gr.faecher)))) + 1)
				var opt := rg.duplicate()
				# Leeres Regal (noch nichts eingeräumt): ganz leer, auch ohne Deko – kein Stapel, der wie Spiele aussieht.
				if str(rg.get("fi", "")) == "eigene" and liste.is_empty():
					opt["de"] = "keine"
				opt["huellen"] = huellen
				opt["cover_bisher"] = cover
				r = Inhalt.regal_fuellen(n, liste, int(gr.bei), pro_fach, schilder, self, opt)
				gr.bei = int(r.bis)
				cover = int(r.get("cover", cover))
			"trophaeenschrank":
				var kp := str(rg)
				if not pokale.has(kp):
					pokale[kp] = { "liste": Inhalt.pokale(rg), "bei": 0 }
				r = Inhalt.schrank_fuellen(n, pokale[kp].liste, int(pokale[kp].bei))
				pokale[kp].bei = int(r.bis)
			"plattenregal":
				var kq := str(rg.get("so", ""))
				if not platten.has(kq):
					platten[kq] = { "liste": Inhalt.platten(rg), "bei": 0 }
				r = Inhalt.plattenregal_fuellen(n, platten[kq].liste, int(platten[kq].bei), rg)
				platten[kq].bei = int(r.bis)
		for c in range(vorher, n.get_child_count()):
			n.get_child(c).set_meta("uz_inhalt", true)
			schatten_sparen(n.get_child(c), "")
		if not r.is_empty():
			plaetze[i] = r.plaetze
	tv_auffrischen()


## Welche Regale sich ihre Spiele teilen: gleiche Auswahl und Sortierung; eigene Reihenfolge und
## selbst Eingeräumtes nur je Regal (i).
static func regal_gruppe(rg: Dictionary, i: int) -> String:
	var k := "%s|%s" % [str(rg.get("so", "zuletzt")), str(rg.get("fi", "alle"))]
	if str(rg.get("so", "")) == "manuell" or str(rg.get("fi", "")) == "eigene":
		k += "|%d" % i
	return k


## Alles Licht neu: Tageszeit, Wetter und Stimmung (Hülle), dann die Lampen – nach Änderungen an
## raum.licht (Anpassung).
func licht_neu(weich := false) -> void:
	(huelle as Node).call("setze_licht", raum.get("licht", {}), weich)
	lampen_auffrischen()


## Eine Lampe hat neue Werte (it.l): alle Lampen neu (kostet fast nichts).
func lampe_neu(_i: int) -> void:
	lampen_auffrischen()


## Lampen nach Tageszeit (abends kräftig, am Tag nur leicht) und nach dem Licht des Raums und der
## Lampe selbst (licht_von): echte Lichter für die Möbel, dazu die Liste für die Hülle
## (lichter.gdshaderinc) – die kräftigsten zwölf, samt Fernseher als Lichtquelle. sonde = false: nur
## das Licht des Fernsehers hat sich bewegt (Flimmern, Farbe des Spielbilds, mehrmals je Sekunde) – die
## Reflexionssonde rechnet dafür nicht den ganzen Raum sechsmal neu (vorher alle halbe Sekunde).
func lampen_auffrischen(sonde := true) -> void:
	var f: float = huelle.lampen_faktor
	var st := Licht.stimmung(raum)
	var liste: Array = []
	var forward: bool = huelle.forward
	var mit_schatten: Array = []      ## [Stärke, OmniLight3D] der Lampen, die Schatten werfen könnten
	var summe := 0.0                  ## Stärke aller brennenden Lampen (Abprall auf Möbel, raum.gd)
	for i in mini(knoten.size(), (raum.moebel as Array).size()):
		var it: Dictionary = raum.moebel[i]
		if Katalog.nutzen(str(it.t)) == "lampe" or str(it.t) == "trophaeenschrank":
			if not is_instance_valid(knoten[i]):
				continue
			var l := licht_von(raum, it)
			Moebel.schalten(knoten[i], bool(it.an), f, l[0], l[1], l[2])
			if not bool(it.an):
				continue
			if forward:
				# Echte Lichter treffen die Hülle; die kräftigsten Lampen werfen Schatten (unten).
				for e in (knoten[i] as Node3D).get_meta("lampen", []):
					var licht_e: OmniLight3D = e.licht
					if licht_e.visible:
						summe += licht_e.light_energy
					if str(it.t) in ["stehlampe", "tischlampe", "deckenlampe", "stehlampe_dreiarm", "wandlampe"] and not bool(e.get("farblicht", false)) \
							and licht_e.visible:
						mit_schatten.append([licht_e.light_energy * licht_e.omni_range, licht_e])
					elif licht_e.shadow_enabled:
						licht_e.shadow_enabled = false
				continue
			var art := Licht.art(str(it.t))
			for e in (knoten[i] as Node3D).get_meta("lampen", []):
				var licht: OmniLight3D = e.licht
				if not licht.visible:
					continue
				var p: Vector3 = (knoten[i] as Node3D).transform * licht.position
				var en := licht.light_energy
				var c := licht.light_color
				# Die Vitrine leuchtet nach innen: auf der Hülle nur ein schwacher Punkt. Farblicht
				# (LED-Leiste) färbt die Wand kräftig.
				if str(it.t) == "trophaeenschrank":
					en *= 0.35
				elif bool(e.get("farblicht", false)):
					en *= Licht.FARBLICHT_HUELLE
				liste.append([en, Vector4(p.x, p.y, p.z, licht.omni_range), Vector4(c.r * en, c.g * en, c.b * en, art), Vector4.ZERO])
	mit_schatten.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	if forward:
		(huelle as Node).call("lampen_abprall", summe)
	# Relief auf dem gebackenen Licht der Hülle (lichter.gdshaderinc uz_relief): die vier kräftigsten Lampen.
	if forward:
		var rp := PackedVector4Array()
		for e: Array in mit_schatten.slice(0, 4):
			var lr: OmniLight3D = e[1]
			var p := lr.global_position if lr.is_inside_tree() else lr.position
			rp.append(Vector4(p.x, p.y, p.z, lr.light_energy))
		rp.resize(4)
		for m: ShaderMaterial in huelle.huellen_mats:
			m.set_shader_parameter("relief_n", mini(mit_schatten.size(), 4))
			m.set_shader_parameter("relief_pos", rp)
	# Schatten werfen nur die kräftigsten Lampen (Stufe: lampen_schatten). Würfel-Schatten (wie
	# vorgegeben): Doppel-Paraboloid sparte gemessen kaum etwas (die Engine zeichnet je Würfelseite nur,
	# was darin liegt) und verzerrt.
	for k in mit_schatten.size():
		var licht_s: OmniLight3D = mit_schatten[k][1]
		var mit := k < int(werte.get("lampen_schatten", 0)) and not schlank
		if licht_s.shadow_enabled != mit:
			licht_s.shadow_enabled = mit
	# Der Fernseher als weiches Licht nach vorn (abends und nachts deutlich, am Tag kaum).
	var tv := medienwand()
	if tv >= 0 and is_instance_valid(knoten[tv]) and (knoten[tv] as Node3D).has_meta("bildschirm"):
		var n: Node3D = knoten[tv]
		var bs: MeshInstance3D = n.get_meta("bildschirm")
		var vorn := (n.transform.basis * Vector3(0, 0, 1)).normalized()
		var p: Vector3 = n.transform * bs.position + vorn * 0.25
		var dunkel := 1.0 if huelle.zeit in ["abend", "nacht"] else 0.3
		var en0 := TV_LICHT * float(st.tv) * dunkel
		var en := en0 * (_tv_flimmer if tv_spiel and tv_spiel.visible else 1.0)
		var c := _tv_farbe.lerp(Color("#7f9cff"), 0.6)
		liste.append([en, Vector4(p.x, p.y, p.z, 3.6), Vector4(c.r * en, c.g * en, c.b * en, 3), Vector4(vorn.x, vorn.y, vorn.z, 0), en0])
	liste.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var pos := PackedVector4Array()
	var farbe := PackedVector4Array()
	var dir := PackedVector4Array()
	_hl_tv = -1
	for k in Licht.HUELLEN_LAMPEN:
		var e: Array = liste[k] if k < liste.size() else [0.0, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
		pos.append(e[1])
		farbe.append(e[2])
		dir.append(e[3])
		if e.size() > 4:
			_hl_tv = k
			_hl_tv_en = float(e[4])
	var anzahl := mini(liste.size(), Licht.HUELLEN_LAMPEN)
	_hl_n = anzahl
	_hl_pos = pos
	_hl_farbe = farbe
	_hl_dir = dir
	(huelle as Node).call("lampen_setzen", anzahl, pos, farbe, dir)
	for m: ShaderMaterial in _teppich_mats:
		m.set_shader_parameter("lampen_n", anzahl)
		m.set_shader_parameter("lampe_pos", pos)
		m.set_shader_parameter("lampe_farbe", farbe)
		m.set_shader_parameter("lampe_dir", dir)
		for k in ["fleck_farbe", "fleck_dir", "fenster"]:
			m.set_shader_parameter(k, huelle.huellen_mats[0].get_shader_parameter(k))
	if _vignette:
		_vignette_soll = float(st.vignette) / 0.3
		if not _vignette_leise:
			_vignette.modulate.a = _vignette_soll
	if sonde:
		huelle.sonde_neu()
	tv_ton()
	# Gespiegelte Umgebung der Pokale: so hell wie das Licht im Raum (Vitrine an: immer etwas).
	var z := Licht.zeit(huelle.zeit)
	var hell := clampf(float(z.amb) * 1.6 + float(z.lampen) * f * 0.5 + 0.2, 0.25, 1.1)
	S.pokale_umgebung(hell, Color(1.0, 0.92, 0.8), Color(str(z.himmel)).lerp(Color.WHITE, 0.3), Color(str(z.boden)).lerp(Color("#6b4a30"), 0.5))


## Farbe, Helligkeit (0 … 2) und Reichweite (0,5 … 2) einer Lampe: eigene Farbe der Lampe, sonst
## die gemeinsame Lampenfarbe des Raums, sonst die Farbtemperatur (Lampe, sonst Raum). LED-Leisten
## leuchten in der LED-Farbe des Raums. Helligkeit = Lampe × Raum.
static func licht_von(r: Dictionary, it: Dictionary) -> Array:
	var rl: Dictionary = r.get("licht", {})
	var l: Dictionary = it.get("l", {})
	var farblicht := bool(Katalog.info(str(it.t)).get("farblicht", false))
	var c: Color
	if str(l.get("c", "")) != "":
		c = Color(str(l.c))
	elif farblicht:
		c = Color(str(rl.get("fa", "#7a5cff")))
	elif str(rl.get("lf", "")) != "":
		c = Color(str(rl.lf))
	else:
		var k := int(l.get("k", rl.get("k", 2700)))
		c = Moebel.WARM if k == 2700 else G.kelvin_farbe(k).lerp(Color.WHITE, 0.25)
	var h := float(l.get("h", 100)) / 100.0 * float(rl.get("h", 100)) / 100.0
	return [c, h, float(l.get("w", 100)) / 100.0]


## Von oben: Wände zwischen Kamera und Raum ausblenden – und was an ihnen hängt.
func schnitt(kamera_pos: Vector3, an: bool) -> void:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	# Nur bei einem Wechsel umstellen (die Kamera ruft das jedes Bild): Schatten, Sichtbarkeit und
	# Materialien setzen kostete sonst je Bild Zeit des Prozessors.
	var lage := (1 if an else 0) | (2 if kamera_pos.z < 0.0 else 0) | (4 if kamera_pos.x < 0.0 else 0) | (8 if kamera_pos.z > d else 0) \
			| (16 if kamera_pos.x > w else 0) | (_knoten_nr << 5) | (int(huelle.bau_nr) << 24)
	if lage == _schnitt_lage:
		return
	_schnitt_lage = lage
	(huelle as Node).call("schnitt", kamera_pos, an)
	for i in knoten.size():
		var it: Dictionary = raum.moebel[i]
		if Katalog.ebene(str(it.t)) != "wand":
			continue
		var weg := false
		match int(it.r):
			0: weg = an and kamera_pos.z < 0.0
			1: weg = an and kamera_pos.x < 0.0
			2: weg = an and kamera_pos.z > d
			3: weg = an and kamera_pos.x > w
		(knoten[i] as Node3D).visible = not weg


# --- Treffer --------------------------------------------------------------------------------------

## Welches Möbel trifft ein Blick von o in Richtung r (bis max Meter)? Nur Möbel, mit denen man
## etwas tun kann (nur_nutzbar). -1 ohne Treffer.
func treffer(o: Vector3, r: Vector3, max_d: float, nur_nutzbar := true, kegel := true) -> int:
	var best := -1
	var best_d := max_d
	for i in boxen.size():
		if nur_nutzbar and Katalog.nutzen(str(raum.moebel[i].t)) == "":
			continue
		var b: AABB = boxen[i]
		var hit: Variant = b.grow(0.04).intersects_ray(o, r)
		if hit is Vector3:
			var dd := o.distance_to(hit)
			if dd < best_d:
				best_d = dd
				best = i
	if best >= 0 or not kegel:
		return best
	# Kein direkter Treffer: das nächste nutzbare Möbel in einem schmalen Kegel.
	var best_w := deg_to_rad(13.0)
	for i in boxen.size():
		if nur_nutzbar and Katalog.nutzen(str(raum.moebel[i].t)) == "":
			continue
		var c: Vector3 = (boxen[i] as AABB).get_center()
		var v := c - o
		var dist := v.length()
		if dist > max_d or dist < 0.05:
			continue
		var w := r.angle_to(v)
		if w < best_w:
			best_w = w
			best = i
	return best


func fenster_getroffen(o: Vector3, r: Vector3, max_d: float) -> bool:
	var hit: Variant = huelle.fenster_box.intersects_ray(o, r)
	return hit is Vector3 and o.distance_to(hit) < max_d


# --- Nachbearbeitung, Raster, Fernsehbild ----------------------------------------------------------

func _nachbearbeitung() -> void:
	nach_mat = ShaderMaterial.new()
	nach_mat.shader = NACH_S
	nach_mat.render_priority = -100
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	q.mesh = qm
	q.material_override = nach_mat
	q.extra_cull_margin = 16384.0
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Forward+: Umgebungsverdeckung macht die Engine (SSAO), gegen Stufen rauscht die Engine selbst
	# (use_debanding); die Fläche zeichnet dort nur, solange Tiefenunschärfe an ist (fokus) – sonst
	# kostete sie je Bild eine Kopie des ganzen Bilds und änderte nichts.
	_nach_flaeche = q
	q.visible = int(werte.ao) > 0
	nach_mat.set_shader_parameter("ao_proben", int(werte.ao))
	nach_mat.set_shader_parameter("dof_proben", int(werte.dof))
	# Kein Filmkorn mehr (las sich als Unschärfe/Rauschen).
	nach_mat.set_shader_parameter("korn", 0.0)
	kamera.add_child(q)
	q.position = Vector3(0, 0, -0.5)


## Vignette als 2D-Fläche über dem Bild (in allen Stufen, kostet einen Verlauf).
func _vignette_bauen() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -1
	add_child(cl)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.06), Color(0.02, 0.015, 0.03, 0.62)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.0)
	gt.width = 256
	gt.height = 144
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_vignette)


func fokus(entfernung: float, tiefe: float, staerke: float) -> void:
	nach_mat.set_shader_parameter("fokus", entfernung)
	nach_mat.set_shader_parameter("fokus_tiefe", tiefe)
	nach_mat.set_shader_parameter("unschaerfe", staerke)
	if is_instance_valid(_nach_flaeche):
		_nach_flaeche.visible = int(werte.ao) > 0 or (int(werte.dof) > 0 and staerke > 0.0)


func _raster() -> void:
	raster_mat = ShaderMaterial.new()
	raster_mat.shader = RASTER_S
	raster_mat.set_shader_parameter("zelle", Katalog.ZELLE)
	raster_mat.render_priority = 10
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	raster_mat.set_shader_parameter("raum", Vector2(w, d))
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	raster = MeshInstance3D.new()
	raster.mesh = pm
	raster.material_override = raster_mat
	raster.position = Vector3(w * 0.5, 0.03, d * 0.5)
	raster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raster.visible = false
	add_child(raster)


## Bereich (in Feldern) im Raster hervorheben; frei: passt hierhin. getragen: unter einem Möbel in der
## Hand – dann klar grün (passt) bzw. rot, sonst im Akzent (Feld, Möbel unter dem Feld).
func raster_bereich(x: int, z: int, gw: int, gd: int, frei: bool, hoehe := 0.03, getragen := false) -> void:
	var c := Katalog.ZELLE
	raster_mat.set_shader_parameter("bereich", Vector4(x * c, z * c, gw * c, gd * c))
	raster_mat.set_shader_parameter("frei", 1.0 if frei else 0.0)
	raster_mat.set_shader_parameter("getragen", 1.0 if getragen else 0.0)
	raster.position.y = hoehe


## Einrichten: eine Wand gewählt – ein schmaler Streifen am Boden entlang dieser Wand leuchtet.
func raster_wand(seite: String) -> void:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	var b := 0.24
	var r: Vector4 = { "hinten": Vector4(0, 0, w, b), "vorn": Vector4(0, d - b, w, b), "links": Vector4(0, 0, b, d),
		"rechts": Vector4(w - b, 0, b, d) }.get(seite, Vector4(0, 0, w, b))
	raster_mat.set_shader_parameter("bereich", r)
	raster_mat.set_shader_parameter("frei", 1.0)
	raster_mat.set_shader_parameter("getragen", 0.0)
	raster.position.y = 0.03


## Was der Fernseher zeigt, solange kein Spiel läuft: ein ruhiges Uzai-Bild in der Farbe des
## zuletzt gespielten Spiels, dessen Name und „Bereit“. Läuft ein Spiel, legt sich sein Bild
## darüber (tv_live, Stufe 2).
func _fernsehbild() -> void:
	tv_vp = SubViewport.new()
	# Gezeichnet in 960 × 540 (so groß kommt das Spielbild, spielbild.gd FANG), angeordnet in 640 × 360:
	# vorher wurde das Spielbild hier auf 640 × 360 verkleinert und im Fernseher unscharf.
	tv_vp.size = Vector2i(960, 540)
	tv_vp.size_2d_override = Vector2i(640, 360)
	tv_vp.size_2d_override_stretch = true
	tv_vp.disable_3d = true
	tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(tv_vp)
	var bg := ColorRect.new()
	bg.color = Color("#0e0f12")
	bg.size = Vector2(640, 360)
	tv_vp.add_child(bg)
	tv_licht = ColorRect.new()
	tv_licht.size = Vector2(640, 360)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec4 farbe : source_color = vec4(0.9, 0.76, 0.49, 1.0);\nvoid fragment() {\n\tvec2 p = UV - vec2(0.78, 0.2);\n\tfloat a = exp(-dot(p * vec2(1.4, 2.0), p * vec2(1.4, 2.0)) * 3.2);\n\tvec2 q = UV - vec2(0.15, 0.95);\n\ta += 0.5 * exp(-dot(q, q) * 5.0);\n\tCOLOR = vec4(farbe.rgb, a * 0.55);\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	tv_licht.material = sm
	tv_vp.add_child(tv_licht)
	# Die Marke oben links: das U-Band und daneben flach die Wortmarke wie im Intro (boot.gd).
	tv_marke = Control.new()
	tv_marke.position = Vector2(44, 32)
	tv_marke.size = Vector2(300, 40)
	tv_marke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv_marke.draw.connect(func() -> void:
		Logo.zeichne_zeile(tv_marke, Vector2.ZERO, 34.0, UzTheme.col("accent"), Boot.WORT_FARBE, Boot.WORT_SPUR))
	tv_vp.add_child(tv_marke)
	tv_zeile = Label.new()
	tv_zeile.add_theme_font_override("font", UzTheme.font("ui"))
	tv_zeile.add_theme_font_size_override("font_size", 22)
	tv_zeile.add_theme_color_override("font_color", Color("#a6a49f"))
	tv_zeile.position = Vector2(44, 236)
	tv_vp.add_child(tv_zeile)
	tv_titel = Label.new()
	tv_titel.add_theme_font_override("font", UzTheme.display("title"))
	tv_titel.add_theme_font_size_override("font_size", 46)
	tv_titel.add_theme_color_override("font_color", Color("#f3f1ec"))
	tv_titel.position = Vector2(42, 262)
	tv_titel.size = Vector2(560, 60)
	tv_titel.clip_text = true
	tv_titel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tv_vp.add_child(tv_titel)
	tv_spiel = TextureRect.new()
	tv_spiel.size = Vector2(640, 360)
	tv_spiel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tv_spiel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tv_spiel.visible = false
	var schwarz := ColorRect.new()
	schwarz.color = Color.BLACK
	schwarz.size = Vector2(640, 360)
	schwarz.show_behind_parent = true
	tv_spiel.add_child(schwarz)
	tv_vp.add_child(tv_spiel)


## Fernsehbild neu: zeile (z. B. „Zuletzt gespielt“, „Startet …“), titel, Farbe des Lichts.
func tv_zeigen(zeile: String, titel: String, farbe: Color) -> void:
	if tv_vp == null:
		return
	tv_zeile.text = zeile
	tv_titel.text = titel
	tv_marke.queue_redraw()      # Akzent kann sich geändert haben
	_tv_farbe = farbe
	(tv_licht.material as ShaderMaterial).set_shader_parameter("farbe", farbe)
	tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func tv_auffrischen() -> void:
	if laeuft_titel != "":
		tv_zeigen("Läuft gerade", laeuft_titel, Color("#e7c27d"))
		return
	var g := Library.get_game(str(Config.get_value("system.last_game", "")))
	if g.is_empty():
		var r := Library.recent(1)
		g = r[0] if not r.is_empty() else {}
	if g.is_empty():
		tv_zeigen("Bereit", tr("Dein Zimmer"), Color("#e7c27d"))
	else:
		tv_zeigen("Zuletzt gespielt", Library.display_title(g), S.huellen_farbe(g).lightened(0.25))


## Das laufende Spiel im Fernseher: neues Bild (nur im Speicher). Das erste Bild blendet weich
## über das Uzai-Bild (sofort: ohne Blende); der Fernseher wirft dann das Licht des Spiels in den Raum.
func tv_live(img: Image, sofort := false) -> void:
	if tv_vp == null or img == null or img.is_empty():
		return
	if _tv_tex and Vector2i(_tv_tex.get_size()) == img.get_size():
		_tv_tex.update(img)
	else:
		_tv_tex = ImageTexture.create_from_image(img)
		tv_spiel.texture = _tv_tex
	if not tv_spiel.visible and sofort:
		tv_spiel.visible = true
		tv_spiel.modulate.a = 1.0
		tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif not tv_spiel.visible:
		tv_spiel.visible = true
		tv_spiel.modulate.a = 0.0
		tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var tw := create_tween()
		tw.tween_property(tv_spiel, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void: tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	else:
		tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Licht des Spiels: die mittlere Farbe höchstens alle 0,3 s (das Live-Bild kommt 30–60-mal je Sekunde).
	var jetzt := Time.get_ticks_msec()
	if jetzt - _tv_farbe_ms < int(Spielbild.FARBE_S * 1000.0) and not sofort:
		return
	_tv_farbe_ms = jetzt
	var c := Spielbild.mittelfarbe(img).lightened(0.15)
	if absf(c.r - _tv_farbe.r) + absf(c.g - _tv_farbe.g) + absf(c.b - _tv_farbe.b) > 0.08:
		_tv_farbe = c
		_tv_licht()


## Licht des Fernsehers ein wenig heller oder dunkler (wie ein Bild, das sich bewegt).
func tv_flimmern(k: float) -> void:
	_tv_flimmer = k
	_tv_licht()


## Nur das Licht des Fernsehers auf der Hülle neu (Farbe des Spielbilds, Flimmern) – mehrmals je Sekunde,
## daher ohne alle Lampen und Möbel neu zu sammeln (lampen_auffrischen). Ist er nicht unter den Lichtern
## der Hülle, doch alles.
func _tv_licht() -> void:
	if _hl_tv < 0 or _hl_tv >= _hl_farbe.size():
		lampen_auffrischen(false)
		return
	var en := _hl_tv_en * (_tv_flimmer if tv_spiel and tv_spiel.visible else 1.0)
	var c := _tv_farbe.lerp(Color("#7f9cff"), 0.6)
	_hl_farbe[_hl_tv] = Vector4(c.r * en, c.g * en, c.b * en, 3)
	(huelle as Node).call("lampen_setzen", _hl_n, _hl_pos, _hl_farbe, _hl_dir)
	for m: ShaderMaterial in _teppich_mats:
		m.set_shader_parameter("lampe_farbe", _hl_farbe)


## Schlanker Weg neben dem laufenden Spiel (zimmer_basis.gd _spar_setzen): keine Lampenschatten auf Möbeln
## (die Hülle hat sie gebacken), die Hülle lässt ihre teuren Effekte weg (raum.gd schlank_setzen).
func schlank_setzen(an: bool) -> void:
	if an == schlank:
		return
	schlank = an
	if huelle:
		huelle.schlank_setzen(an)
	lampen_auffrischen(false)


## Kein Spielbild mehr (Spiel zu, nur schwarze Bilder): wieder das Uzai-Bild.
func tv_live_aus() -> void:
	if tv_spiel == null or not tv_spiel.visible:
		return
	tv_spiel.visible = false
	tv_auffrischen()
	lampen_auffrischen()


## Für Bilder, die das Zimmer verlassen (Vorschau beim Teilen): nichts aus der Bibliothek und
## kein Spielbild – Regale ohne Spiele, Pokale und Platten, der Fernseher zeigt nur „uzai“.
## an = false stellt alles wieder her.
func privat(an: bool) -> void:
	for n in knoten:
		if not is_instance_valid(n):
			continue
		for c in (n as Node3D).get_children():
			if c.has_meta("uz_inhalt") and c is Node3D:
				(c as Node3D).visible = not an
	if an:
		if tv_spiel:
			tv_spiel.visible = false
		tv_zeigen("Bereit", tr("Dein Zimmer"), Color("#e7c27d"))
	else:
		tv_auffrischen()
		if tv_spiel and _tv_tex and laeuft_titel != "":
			tv_spiel.visible = true
			tv_spiel.modulate.a = 1.0
			tv_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Material des Bildschirms (null ohne Fernseher).
func tv_material() -> ShaderMaterial:
	var tv := medienwand()
	if tv < 0 or not is_instance_valid(knoten[tv]) or not (knoten[tv] as Node3D).has_meta("bildschirm"):
		return null
	return (((knoten[tv] as Node3D).get_meta("bildschirm") as MeshInstance3D).material_override) as ShaderMaterial


## Einschalten wie ein echter Fernseher (Röhre: Linie, die sich öffnet; sonst weich aufleuchten).
func tv_einschalten(dauer := 0.55) -> void:
	var m := tv_material()
	if m == null:
		return
	m.set_shader_parameter("einschalten", 0.0)
	create_tween().tween_method(func(v: float) -> void: m.set_shader_parameter("einschalten", v), 0.0, 1.0, dauer).set_trans(Tween.TRANS_SINE).set_ease(
			Tween.EASE_OUT)


func medienwand() -> int:
	for i in knoten.size():
		if str(raum.moebel[i].t) == "medienwand":
			return i
	return -1


# --- Konsolen im Lowboard (konsolen.gd) -----------------------------------------------------------

## Welche Konsolen im Lowboard stehen: eingeschaltete Systeme mit Spielen, dazu der PC.
func konsolen_ids() -> Array:
	var zahl := {}
	var pc := 0
	for g: Dictionary in Library.visible_games():
		var sid := str(g.get("system", ""))
		if sid == "":
			continue
		if Config.system(sid).is_empty():
			pc += 1
		else:
			zahl[sid] = int(zahl.get(sid, 0)) + 1
	var aktiv: Array = Config.systems_enabled().map(func(s: Dictionary) -> String: return str(s.get("id", "")))
	return Konsolen.auswahl(aktiv, zahl, pc)


## Die Konsole, auf der ein Spiel läuft (oder null).
func konsole_fuer(g: Dictionary) -> Node3D:
	var tv := medienwand()
	if tv < 0 or g.is_empty() or not is_instance_valid(knoten[tv]):
		return null
	var ks: Dictionary = (knoten[tv] as Node3D).get_meta("konsolen", {})
	var sid := str(g.get("system", ""))
	var id := Konsolen.fuer_spiel(sid, sid != "" and Config.system(sid).is_empty(), ks.keys())
	return ks.get(id) as Node3D if id != "" else null


## Strom nach dem laufenden Spiel: seine Konsole an (Medium drin), alle anderen aus.
func konsolen_strom(n: Node3D = null) -> void:
	if n == null:
		var tv := medienwand()
		if tv < 0 or not is_instance_valid(knoten[tv]):
			return
		n = knoten[tv]
	var ks: Dictionary = n.get_meta("konsolen", {})
	var g: Dictionary = Launcher.current if Launcher.in_game else {}
	var sid := str(g.get("system", ""))
	var an := Konsolen.fuer_spiel(sid, sid != "" and Config.system(sid).is_empty(), ks.keys()) if not g.is_empty() else ""
	for id: String in ks:
		var k: Node3D = ks[id]
		if id == an:
			if not Konsolen.ist_an(k):
				Konsolen.einstecken(k, S.huellen_farbe(g))
		elif Konsolen.ist_an(k):
			Konsolen.strom(k, false)


func plattenspieler() -> int:
	for i in knoten.size():
		if str(raum.moebel[i].t) == "plattenspieler":
			return i
	return -1

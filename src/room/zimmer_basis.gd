extends "res://src/ui/layers/layer.gd"
## Dein Zimmer, unterste Schicht: was alle Teile brauchen – Kopfzeile, Hinweise, Meldungen und
## Infokarte, das Ziel vor dir (suchen, zeigen, Glimmen), Plätze vor Möbeln, die Kamera-Ziele,
## Grafikstufe, Licht, Welt neu aufbauen, Raster des Bau-Modus, Merken und Speichern.
## Das Zimmer besteht aus Schichten; jede erbt von der darunter und kennt nur sie:
## zimmer_basis.gd → zimmer_foto.gd → zimmer_ansehen.gd → zimmer_einrichten.gd → zimmer.gd.

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Raum := preload("res://src/room/raum.gd")
const S := preload("res://src/room/stoffe.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Bewohner := preload("res://src/room/figur/bewohner.gd")
const Licht := preload("res://src/room/licht.gd")
const Anpassen := preload("res://src/room/anpassen.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const Leistung := preload("res://src/room/leistung.gd")
const Lichtbacken := preload("res://src/room/lichtbacken.gd")
const G := preload("res://src/room/gestalt.gd")
const KatalogUi := preload("res://src/room/katalog_ui.gd")
const Bildzeit := preload("res://src/room/bildzeit.gd")
const Raumton := preload("res://src/room/raumton.gd")
const Fernsehspiel := preload("res://src/room/fernsehspiel.gd")
const Zustand := preload("res://src/core/zustand.gd")

const AUGEN := 1.62
const RADIUS := 0.24           ## so nah kommst du an Wände und Möbel
const REICHWEITE := 1.7        ## so weit reicht A: nur, wovor du stehst
const REICHWEITE_TV := 14.0    ## der Fernseher geht aus dem ganzen Raum (hinsehen, A)
const OBEN_ABSTAND := 10.4
const OBEN_HOEHE := 0.86       ## Neigung von oben (Bogenmaß, ≈ 49°)

const Main := preload("res://src/main.gd")
const AnpassenUi := preload("res://src/room/anpassen_ui.gd")
const Baukasten := preload("res://src/room/baukasten.gd")
const KontextUi := preload("res://src/room/kontext_ui.gd")
const ModusUi := preload("res://src/room/modus_ui.gd")
const TastenUi := preload("res://src/room/tasten_ui.gd")
var main: Main
var daten: Dictionary = {}
var raum: Dictionary = {}
## Freundestest, Gast: du stehst im Zimmer des Gastgebers (zimmer.gd besuch_an). Dann wird nichts gebaut, nichts
## angepasst und nie gespeichert – das Zimmer gehört dem Gastgeber, dein eigenes bleibt unberührt.
var besuch := false
var leicht := false
var stufe := "mittel"          ## Qualitätsstufe der Grafik (licht.gd STUFEN)
var welt: Welt
var vp: SubViewport
var svc: SubViewportContainer
var _ansicht: TextureRect      ## zeigt die 3D-Ansicht in echten Bildpunkten (_aufloesung)
var _ruhe_gemeldet := -1        ## zuletzt in launch.log genannte Rate hinter dem Spiel (je Wert einmal)
var _spiel_lage := ""          ## Spiel im Fernseher: „startet“, „zimmer“ (aufgestanden), „vollbild“
var _spar := false              ## schlanker Weg neben dem laufenden Spiel (Forward+; Kompatibilität: sparsam)
var _spar_vorher := {}          ## was _spar_setzen umgestellt hat (zum Zurückstellen)
var _spar_gemeldet := false
var bildzeit: Bildzeit           ## misst Bildzeiten neben dem laufenden Spiel (launch.log)
var _pipeline_folge: Array = []  ## MSAA-Stufen, die die Engine noch je ein Bild lang erwarten soll (_pipelines_weiter)
var leistung: Leistung           ## Bildrate, Ruhe und 3D-Auflösung nach gemessener Zeit (leistung.gd)

## Was du im Zimmer gerade tust – eine Tabelle für alle Schichten (zimmer_basis.gd bis zimmer.gd): laufen (Leben),
## ansehen (vor dem Regal), sitzen, bauen, katalog (Bau-Menü), anpassen (Seitenleiste), rad (Stimmung), baukasten,
## foto, betrachten (ein Möbel von nahem), wand (Raum größer/kleiner), fahrt (die Kamera fährt: Tür, Fernseher,
## ins und aus dem Spiel), fernsehen (vor dem Fernseher, das Spiel startet), spiel (wartet hinter dem Spiel, ruhen).
## In die Fahrt geht es von überall (Guide › Zum Spiel, Spielstart im Zimmer); zurück führt sie ins Laufen.
const ZUSTAENDE_MODUS := {
	"*": ["fahrt"],
	"laufen": ["ansehen", "sitzen", "bauen", "foto", "anpassen", "rad", "betrachten", "wand"],
	"ansehen": ["laufen"],
	"sitzen": ["laufen"],
	"bauen": ["laufen", "katalog", "anpassen", "wand", "baukasten"],
	"katalog": ["bauen"],
	"anpassen": ["laufen", "bauen", "baukasten"],
	"rad": ["laufen", "bauen"],
	"baukasten": ["laufen", "bauen"],
	"foto": ["laufen"],
	"betrachten": ["laufen"],
	"wand": ["laufen", "bauen"],
	"fahrt": ["laufen", "fernsehen", "spiel"],
	"fernsehen": ["laufen"],
	"spiel": ["laufen"],
}
var modus := "laufen":
	set(neu):
		Zustand.wechsel("zimmer.modus", ZUSTAENDE_MODUS, modus, neu)
		modus = neu
var blick := "ich"             ## ich, oben
var pos := Vector3(5.0, 0.0, 4.3)
var yaw := 0.45
var pitch := -0.08
var _yaw_soll := 0.45
var _rate := 6.0
var _oben_az := 0.62
var _oben_zoom := 1.06

var _ziel := -1                ## Möbel vor dir (Index), -1 keins
var _ziel_fenster := false
var _glimmen_an: Node3D = null
var _glimmen := 0.0

var _ans := -1                 ## Möbel, das gerade angesehen wird
var _ans_plaetze: Array = []
var _ans_sel := 0
var _ans_merk := {}            ## Möbel-Index → zuletzt gewählter Platz

var _sitz := -1
var _sitz_blick := Vector2.ZERO

var cursor := Vector2i(6, 5)
var _halten := {}              ## getragenes Möbel { t, x, z, r, v, an }
var _halten_idx := -1          ## Index in raum.moebel (-1: neu aus dem Katalog)
var _halten_knoten: Node3D
var _halten_dabei: Array = []  ## [{ idx, dx, dz }] Kleines, das auf dem Getragenen steht
var _rueck: Array = []         ## Rückgängig-Stapel (Schnappschüsse des Raums)

var _ziel_pill: PanelContainer
var _ziel_text: Label
var _ziel_aktion: Label
var _ziel_glyph: Control
var _info: VBoxContainer
var _info_kicker: Label
var _info_titel: Label
var _info_meta: Label
var _kopf: VBoxContainer
var _kopf_titel: Label
var _kopf_sub: Label
var _hinweise_sig := ""
var _tasten_ui: TastenUi            ## Tastenhinweise im Bild (tasten_ui.gd)
var _wand := ""                ## Einrichten: gewählte Wand (Feld außerhalb des Rasters), sonst „“
var _wahl := -1                ## Einrichten: gewähltes Möbel auf dem Feld, wenn mehreres dort liegt (-1: das oberste)
var _schild_pos := Vector2(-1, -1)   ## Lage des Schilds am Ziel (unten mittig), gleitet mit
var _meldung: PanelContainer
var _meldung_l: Label
var _speicher_timer: Timer
var _shell_versteckt := false
var bewohner: Bewohner           ## deine Figur und dein Haustier (src/room/figur/)
var _ziel_tier := false

var _ui: AnpassenUi                ## Seitenleiste „Anpassen“
var _katalog: KatalogUi           ## Möbelkatalog (katalog_ui.gd)
var _seiten: Anpassen
var _baukasten: Baukasten
var _anp_moebel := -1          ## Möbel, das gerade angepasst wird (Kamera)
var _schritt_offen := true     ## nächste Änderung im Anpassen ist ein neuer Rückgängig-Schritt

var spielbild: Spielbild        ## das laufende Spiel im Fernseher (Stufe 2)
var raumton: Raumton            ## sein Ton aus dem Fernseher, solange du nicht davor sitzt
var _spiel_lief := false
var _foto := {}                 ## Fotomodus: Kamera { pos, yaw, pitch, fov }, Pose, Figur an
var _modus_ui: ModusUi          ## Modus-Leiste oben: Leben, Bauen, Foto (modus_ui.gd)
var _kontext: KontextUi           ## Kontextmenü am Objekt (kontext_ui.gd)
var _kontext_punkt: Variant = null   ## Punkt im Raum, an dem das Kontextmenü hängt
## Beim Laufen aufs Regal geschaut: der Platz (Hülle, Pokal, Platte), auf den der Blick fällt – ohne
## eigenen Modus (zimmer_ansehen.gd _blick_platz).
var _bp := {}
var _bp_m := -1


# --- Grafikstufe und Startseite ausblenden -------------------------------------------------------

## Qualitätsstufe aus room.grafik (auto: leichter Modus → Leicht, sonst was auf dieser Grafikkarte
## gemessen wurde, beim ersten Mal eigene Grafikkarte → Hoch, sonst Mittel) und die Einstellungen der
## 3D-Ansicht dazu. Upscaler und 3D-Auflösung nach licht.gd aufloesung(), angepasst von leistung.gd.
func _stufe_waehlen() -> void:
	# Sparsam neben dem Spiel: erst zurück (merkt sich dann die neuen Werte), am Ende wieder an.
	var spar := _spar
	if spar:
		_spar_setzen(false, false)
	var wahl := str(Config.get_value("room.grafik", "auto"))
	stufe = Licht.stufe_jetzt(wahl, Leicht.active, RenderingServer.get_video_adapter_name(), "", Config.get_value("room.grafik_auto", {}))
	leicht = stufe == "leicht"
	var w: Dictionary = Licht.werte(stufe)
	var r := Licht.aufloesung(w, vp.size.x, vp.size.y)
	vp.msaa_3d = { 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X }.get(int(r.get("msaa", w.msaa)), Viewport.MSAA_DISABLED)
	# Die 3D-Ansicht in den echten Bildpunkten des Bildschirms (_aufloesung).
	if not svc.resized.is_connected(_aufloesung):
		svc.resized.connect(_aufloesung)
	_aufloesung.call_deferred()
	vp.use_taa = bool(w.get("taa", false))
	if leistung == null:
		leistung = Leistung.new()
		leistung.vp = vp
		leistung.menu_fps = func() -> int: return int(main._menu_fps()) if main else 0
		var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
		leistung.hz = hz if hz > 1.0 else 60.0     # unbekannt (auch NaN): wie 60 Hz
		leistung.licht_info = func() -> String:
			var b: Variant = welt.get("backen") if welt else null
			return "Licht %d-mal gebacken (zuletzt %.0f ms)" % [int(b.get("gebacken")), float(b.get("letzte_ms"))] if b != null else "nicht gebacken"
		add_child(leistung)
	leistung.einstellen(stufe, wahl, r)
	if str(w.renderer) == "forward":
		_forward_global(w, r)
		leistung.gi_text = "Licht der Hülle gebacken (Karten %d mm, %d Lampen mit Schatten), ohne GI je Bild, Reflexionssonde %s%s, Lampenschatten auf Möbeln %d" \
				% [roundi(float(Lichtbacken.QUALITAET.get(stufe, Lichtbacken.QUALITAET.mittel)[0]) * 1000.0), Lichtbacken.BACK_LAMPEN,
				"nur bei Änderung" if bool(w.get("sonde", false)) else "aus", ", SSAO" if bool(w.get("ssao", false)) else "",
				int(w.get("lampen_schatten", 0))]
	else:
		leistung.gi_text = "Kompatibilität: Licht im Shader"
	# Schatten von Lampen und Sonne (Forward+: die Sonne ist ein Strahler vor dem Fenster, lichtbacken.gd)
	# im Atlas der Ansicht; ohne beides keiner (spart Speicher). Die Engine rechnet sie nur neu, wenn
	# sich in ihrer Reichweite etwas bewegt.
	var ls := int(w.get("lampen_schatten", 0))
	var sonne_schatten := int(w.get("schatten", 0)) > 0 and str(w.renderer) == "forward"
	vp.positional_shadow_atlas_size = 4096 if ls >= 2 else (2048 if ls > 0 or sonne_schatten else 0)
	# 32 Bit: Die Sonne ist ein Strahler 12 m vor dem Fenster – mit 16 Bit Tiefe ließ sie die Wand durch.
	vp.positional_shadow_atlas_16_bits = false
	_pipelines_planen()
	if spar:
		_spar_setzen(true, false)


## Pipelines vorab (leistung.gd pipelines_erwarten): Die Engine erwartet zuerst die MSAA-Stufe der Ansicht
## (das erste Bild braucht sie), dann je ein Bild lang die der Backansichten (lichtbacken.gd) und die des
## schlanken Wegs (ohne), zuletzt wieder die der Ansicht. Jedes Mal übersetzt sie im Hintergrund, was ihr
## für die Flächen des Zimmers noch fehlt – vor dem ersten Backen, Umsehen oder Wechsel in den schlanken Weg.
## Nur Forward+.
func _pipelines_planen() -> void:
	if Licht.renderer_jetzt() != "forward" or vp == null:
		return
	var haupt := int(vp.msaa_3d)
	var backen := int((Lichtbacken.QUALITAET.get(stufe, Lichtbacken.QUALITAET.mittel) as Array)[2])
	_pipeline_folge = []
	for m: int in [backen, Viewport.MSAA_DISABLED]:
		if m != haupt and not (m in _pipeline_folge):
			_pipeline_folge.append(m)
	Leistung.pipelines_erwarten(haupt)
	if leistung:
		var namen := { Viewport.MSAA_DISABLED: "ohne", Viewport.MSAA_2X: "2×", Viewport.MSAA_4X: "4×", Viewport.MSAA_8X: "8×" }
		var teile := PackedStringArray([str(namen.get(haupt, "?"))])
		for m: int in _pipeline_folge:
			teile.append(str(namen.get(m, "?")))
		leistung.vorab_text = "Pipelines vorab für MSAA %s und 32-Bit-Schatten" % " / ".join(teile)
	if not _pipeline_folge.is_empty() and not RenderingServer.frame_post_draw.is_connected(_pipelines_weiter):
		RenderingServer.frame_post_draw.connect(_pipelines_weiter)


## Nach jedem gezeichneten Bild die nächste MSAA-Stufe (_pipelines_planen); am Ende die der Ansicht, wie sie
## jetzt ist (auch im schlanken Weg).
func _pipelines_weiter() -> void:
	if not is_inside_tree() or _closing or vp == null or _pipeline_folge.is_empty():
		_pipeline_folge = []
		RenderingServer.frame_post_draw.disconnect(_pipelines_weiter)
		if is_inside_tree() and not _closing and vp:
			Leistung.pipelines_erwarten(int(vp.msaa_3d))
		return
	Leistung.pipelines_erwarten(int(_pipeline_folge.pop_front()))


## Was die Engine nur für alle Welten zugleich kennt (Forward+): die Filterstufe weicher Schatten. Im
## ganzen Zimmer dieselbe wie beim Backen (Lichtbacken.SCHATTEN_QUALITAET, in jeder Stufe): Jeder Wechsel
## ließ die Engine alle Pipelines aller 3D-Shader verwerfen – früher zweimal je Backen, danach übersetzte
## sie jede Fläche beim Zeichnen neu (kurz nach dem Betreten in Ultra rund 20 Bilder/s). Im laufenden Bild
## werfen ohnehin nur wenige Lichter Schatten (Sonne auf Möbel, in Hoch und Ultra ein, zwei Lampen; Leicht
## keine). Beim Verlassen wieder wie im Projekt (zimmer.gd, _global_wie_projekt).
## Gesetzt wird nur bei einem Wechsel (Lichtbacken.qualitaet_setzen): Die Engine verwirft bei jedem Aufruf
## alles, auch beim selben Wert – und _stufe_waehlen läuft bei jeder neuen Größe der Ansicht.
func _forward_global(_w: Dictionary, _r: Dictionary) -> void:
	Lichtbacken.qualitaet_setzen(Lichtbacken.SCHATTEN_QUALITAET)


## Globale Einstellungen der Engine wieder wie im Projekt (Zimmer verlassen).
static func _global_wie_projekt() -> void:
	Lichtbacken.qualitaet_setzen(-1)


## Größe der 3D-Ansicht in echten Bildpunkten: Die Oberfläche ist auf 1920 × 1080 angelegt
## (canvas_items) – der Behälter misst darin, auf einem 4K-Fernseher wurde das Zimmer darum in 1080p
## gerechnet und doppelt hochgezogen (grobe, flimmernde Kanten, körnige Flächen).
func _ansicht_groesse() -> Vector2i:
	if not is_instance_valid(svc) or not svc.is_inside_tree():
		return Vector2i.ZERO
	var k := maxf(get_viewport().get_final_transform().get_scale().x, 1.0)
	return Vector2i((svc.size * k).round())


## Die 3D-Ansicht in echten Bildpunkten zeigen: Sie hängt nicht im Behälter (der streckte sie auf
## seine Größe in Oberflächen-Einheiten); ein Bild in seiner Fläche zeigt sie 1 : 1. Bewegung und
## Blende des Behälters (Ankommen, Gehen) gelten weiter für das Bild. Neue Größe → Stufe neu
## (Auflösungsgrenze in Mittel und Leicht).
func _aufloesung() -> void:
	if vp == null or not is_instance_valid(svc) or not vp.is_inside_tree():
		return
	if not is_instance_valid(_ansicht):
		_ansicht = TextureRect.new()
		_ansicht.texture = vp.get_texture()
		_ansicht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_ansicht.stretch_mode = TextureRect.STRETCH_SCALE
		_ansicht.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(_ansicht)
		svc.add_child(_ansicht)
	var g := _ansicht_groesse()
	if g.x > 1 and g.y > 1 and g != vp.size:
		vp.size = g
		_stufe_waehlen()


## Bildrate, solange das Zimmer hinter dem Spiel wartet (main_fenster.gd _ruhe_takt; 0 = wie im Menü).
## Im Zimmer selbst läuft es neben dem Spiel mit voller Rate wie sonst auch – wer sich dort umsieht,
## soll es flüssig sehen; Luft für das Spiel schafft der schlanke Weg (_spar_setzen), nicht die Bildrate.
## Erst wenn alle im Zimmer aufs Spiel schauen (du im Vollbild, jeder Gast ebenso:
## Fernsehspiel.alle_fokussiert), sieht es niemand: dann Leistung.spiel_kappe – der kleinste ganzzahlige
## Teil der Bildschirmrate mit mindestens 60 Bildern. Gezeichnet wird dabei nichts (Uzai liegt minimiert,
## ruhen); weiter läuft nur, was im Takt bleiben muss – nie unter 60, damit Rückweg und Netz-Takt der Gäste
## gleichmäßig bleiben. Gäste eines Besuchs zählen hier nicht mit (die Liste bleibt leer): Ihr Bild des Zimmers
## entsteht bei ihnen, und der Besuch selbst läuft im eigenen Knoten weiter (freundestest.gd). Jeder neue
## Wert steht einmal in launch.log.
func ruhe_fps() -> int:
	var hz := leistung.hz if leistung else 60.0
	var soll := Leistung.spiel_kappe(hz) if Fernsehspiel.alle_fokussiert(str(main.tv_zustand()), []) else 0
	if _ruhe_gemeldet != soll:
		_ruhe_gemeldet = soll
		Launcher.log_launch(("Zimmer hinter dem Spiel: höchstens %d Bilder/s (Bildschirm %.0f Hz, alle schauen aufs Spiel; gezeichnet wird nichts)"
				% [soll, hz]) if soll > 0 else "Zimmer hinter dem Spiel: volle Bildrate (jemand ist im Zimmer unterwegs)")
	return soll


## Das Spiel liegt vorn (an, fernsehspiel „vollbild“): Das Zimmer bleibt offen, wartet aber unsichtbar
## dahinter – keine Eingaben, kein Bild der 3D-Ansicht, keine Aufnahme des Spiels für den Fernseher. Aus
## (zurück ins Zimmer): wieder wie zuvor; die Kamera setzt aus_dem_spiel bzw. tv_wechsel.
func ruhen(an: bool) -> void:
	if an:
		modus = "spiel"
		_info_weg()
		_glimmen_setzen(null)
		visible = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		leistung.hinten()
	else:
		visible = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Schlanker Weg, solange neben dem Zimmer ein Spiel läuft (sitzend, aufgestanden, Guide darüber), in
## jeder Stufe gleich: Das Spiel braucht Grafikkarte und Prozessor. Licht bleibt gebacken (kostet je
## Bild nichts), weg fällt, was je Bild rechnet: MSAA und SMAA (FXAA statt dessen), 3D-Auflösung mit
## FSR 1 bei höchstens 67 % (leistung.gd SCHLANK, kleiner bis 50 %, wenn die Grafikkarte nicht nachkommt),
## SSAO, SSIL, SSR, Glühen (die Lichtscheine der Lampen bleiben), Volumen-Nebel und Lichtstrahl, Lampen-
## schatten auf Möbeln (die Hülle hat sie gebacken), neue Aufnahmen der Reflexionssonde; draußen weniger
## Regen und Schnee (zimmer_welt.gd, raum.gd schlank_setzen). Die Grafikkarte gibt Uzai dem Spiel den Vorrang (Helfer „uzai-vorrang“,
## nur Uzais eigener Prozess); der Prozessor bleibt normal („unter normal“ ließ Uzai hinter den
## Rechenfäden des Emulators warten). Im Kompatibilitäts-Renderer wie bisher sparsame Grafik (licht.gd
## spar_werte). Aus stellt alles genau zurück.
func _spar_setzen(an: bool, mit_vorrang := true) -> void:
	if an == _spar or welt == null or vp == null or welt.huelle == null:
		return
	_spar = an
	var sonne: DirectionalLight3D = welt.huelle.sonne
	var forward: bool = welt.huelle.forward
	if an and forward:
		_spar_vorher = { "msaa": vp.msaa_3d, "taa": vp.use_taa }
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.use_taa = false
		if leistung:
			leistung.schlank_setzen(true)
		welt.schlank_setzen(true)
		if not _spar_gemeldet:
			_spar_gemeldet = true
			Launcher.log_launch("Zimmer neben dem Spiel: schlanker Weg (jede Stufe gleich, jetzt %s) – 3D-Auflösung %d %% (%s, Grenzen 50–67 %%), ohne MSAA, SSAO, SSR, Glühen, Nebel, Lichtstrahl und Lampenschatten auf Möbeln; Licht gebacken, Schatten gespeichert"
					% [stufe, roundi(float(vp.scaling_3d_scale) * 100.0), leistung.upscaler_text() if leistung else "?"])
	elif an:
		var w: Dictionary = Licht.werte(stufe)
		var s := Licht.spar_werte(w, int(vp.size.x))
		_spar_vorher = { "msaa": vp.msaa_3d, "atlas": vp.positional_shadow_atlas_size, "schatten": int(w.get("schatten", 0)) }
		vp.msaa_3d = { 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X }.get(int(s.msaa), Viewport.MSAA_DISABLED)
		# Kleinere 3D-Auflösung (FSR 1), und leistung.gd zielt auf weniger Zeit der Grafikkarte.
		if leistung:
			leistung.spar(true, float(s.skala))
		# Schatten von Lampen und Sonne bleiben (still liegend kosten sie nichts), nur in kleinerem Atlas.
		vp.positional_shadow_atlas_size = mini(vp.positional_shadow_atlas_size, 2048)
		if int(_spar_vorher.schatten) > int(s.schatten) and int(s.schatten) > 0:
			RenderingServer.directional_shadow_atlas_set_size(int(s.schatten), true)
		if is_instance_valid(sonne):
			_spar_vorher["winkel"] = sonne.light_angular_distance
			sonne.light_angular_distance = 0.0
		if not _spar_gemeldet:
			_spar_gemeldet = true
			Launcher.log_launch("Zimmer neben dem Spiel: sparsame Grafik (Stufe %s: MSAA %s, 3D-Auflösung %d %% (%s), ohne Lampenschatten, SSIL, SSR, Nebel)"
					% [stufe, "2×" if int(s.msaa) >= 2 else "aus", roundi(float(vp.scaling_3d_scale) * 100.0),
					leistung.upscaler_text() if leistung else "?"])
	elif forward:
		if _spar_vorher.has("msaa"):
			vp.msaa_3d = _spar_vorher.msaa
			vp.use_taa = bool(_spar_vorher.get("taa", false))
		if leistung:
			leistung.schlank_setzen(false)
		welt.schlank_setzen(false)
		_spar_vorher = {}
	else:
		if leistung:
			leistung.spar(false)
		if _spar_vorher.has("msaa"):
			vp.msaa_3d = _spar_vorher.msaa
			vp.positional_shadow_atlas_size = int(_spar_vorher.atlas)
			if int(_spar_vorher.schatten) > 0:
				RenderingServer.directional_shadow_atlas_set_size(int(_spar_vorher.schatten), true)
		if is_instance_valid(sonne) and _spar_vorher.has("winkel"):
			sonne.light_angular_distance = float(_spar_vorher.winkel)
		_spar_vorher = {}
	# Die Engine erwartet, wie die Ansicht jetzt zeichnet (die Pipelines dafür liegen schon bereit, _pipelines_planen;
	# stehen dort noch Stufen an, setzt _pipelines_weiter am Ende die der Ansicht). Diese Zeilen standen seit 73c16e8
	# vor dem „else“ darüber und nahmen es sich: Der Zweig „Kompatibilität, aus“ lief dadurch auch beim
	# Einschalten – im Kompatibilitäts-Renderer war die sparsame Grafik sofort wieder weg, und in Forward+ stellte
	# er, solange noch Pipelines anstanden (Zimmer über dem laufenden Spiel geöffnet), MSAA zurück und brach an
	# einem Schlüssel ab, den es dort nicht gibt – der Vorrang für das Spiel wurde dann nie gesetzt.
	if forward and _pipeline_folge.is_empty():
		Leistung.pipelines_erwarten(int(vp.msaa_3d))
	if mit_vorrang:
		_vorrang(an)
	if bildzeit:
		bildzeit.stufe_text = _stufe_text()


## Grafik als Text für die Bildzeiten (launch.log): Stufe und ob der schlanke oder sparsame Weg gilt.
func _stufe_text() -> String:
	if not _spar:
		return "Stufe %s" % stufe
	return ("schlanker Weg (Stufe %s)" if welt and welt.huelle and bool(welt.huelle.forward) else "Stufe %s, sparsam") % stufe


## Netze der Möbel (launch.log nach dem Betreten, leistung.gd): wie viele die Engine einzeln zeichnet
## (je Netz und Fläche ein Aufruf, dazu der Tiefen-Durchgang) und welche Möbel die meisten haben – so
## sieht man am PC, woher viele Zeichenaufrufe kommen.
func _netze_text() -> String:
	if welt == null:
		return ""
	var je := {}
	var summe := 0
	var stueck := 0
	for i in mini(welt.knoten.size(), (raum.moebel as Array).size()):
		var n: Variant = welt.knoten[i]
		if not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var k := _netze_in(n)
		var t := str(raum.moebel[i].t)
		je[t] = int(je.get(t, 0)) + k
		summe += k
		stueck += 1
	var arten := je.keys()
	arten.sort_custom(func(a: Variant, b: Variant) -> bool: return int(je[a]) > int(je[b]))
	var teile := PackedStringArray()
	for t: Variant in arten.slice(0, 4):
		teile.append("%s %d" % [Katalog.name_of(str(t)), int(je[t])])
	return "Möbel: %d Stück mit %d Netzflächen (meiste: %s)" % [stueck, summe, ", ".join(teile)]


static func _netze_in(n: Node) -> int:
	var k := 0
	var stapel: Array[Node] = [n]
	while not stapel.is_empty():
		var c: Node = stapel.pop_back()
		if c is Node3D and not (c as Node3D).visible:
			continue
		stapel.append_array(c.get_children())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			k += (c as MeshInstance3D).mesh.get_surface_count()
		elif c is MultiMeshInstance3D:
			k += 1
	return k


## Zustand des Spiels im Fernseher (fernsehspiel.gd): Messung je Lage. Schlank ist das Zimmer, solange
## das Spiel läuft – in jeder Lage (sitzend, aufgestanden, Guide darüber).
func _spar_lage(z: String) -> void:
	_spiel_lage = z
	var laeuft := Launcher.in_game and Spielbild.spiel_laeuft()
	_spar_setzen(laeuft)
	if bildzeit:
		var lage: String = str({ "startet": "vor dem Fernseher", "zimmer": "aufgestanden", "vollbild": "hinter dem Spiel" }.get(z, "")) if laeuft else ""
		bildzeit.setzen(lage, _stufe_text())


## Uzai nimmt sich selbst zurück (an) bzw. wieder wie vorher – nur der eigene Prozess, über den Helfer.
func _vorrang(leise: bool) -> void:
	if not Config.is_windows() or not Helper.available:
		return
	# Nur die Grafikkarte: Uzais Prozessor „unter normal“ wartete hinter den Rechenfäden des Emulators
	# (einzelne Bilder doppelt so lang – Ruckler beim Laufen), gebraucht wird er kaum.
	var r := await Helper.run("uzai-vorrang", { "leise": leise, "pid": OS.get_process_id(), "cpu": false,
		"hwnd": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) }, 3.0)
	if leise:
		var res: Dictionary = r.result if r.get("ok", false) and r.get("result") is Dictionary else {}
		Launcher.log_launch("Zimmer neben dem Spiel: Uzai nimmt sich zurück – %s" % ("Grafikkarte %s, Prozessor bleibt %s" % [
				"unter normal" if bool(res.get("gpu", false)) else "unverändert", str(res.get("cpu", "?"))] if bool(res.get("ok", false))
				else "ging nicht (%s)" % str(res.get("grund", r.get("error", "?")))))


func _verstecke_shell(an: bool) -> void:
	# Die Oberfläche dahinter ist ganz verdeckt: nicht zeichnen (spart die Hälfte der Arbeit).
	if main == null or not ("shell" in main):
		return
	if an:
		_shell_versteckt = true
		main.shell.visible = false
		main.background.visible = false
	elif _shell_versteckt:
		_shell_versteckt = false
		# Über dem Spiel (Guide, Uzai durchsichtig) bleibt die Startseite versteckt.
		if is_instance_valid(main.shell) and not main._parked and not main._overlay_mode:
			main.shell.visible = true
			main.background.visible = true


# --- Verlassen -----------------------------------------------------------------------------------

## Verlassen ohne Dunkel-Loch: Die Oberfläche steht zuerst wieder da (samt Hinweisen, im selben
## Bild), dann geht das Zimmer darüber – zurück in die Kachel, aus der es kam (_exit_motion), sonst
## blendet es nur aus.
func close() -> void:
	if _closing:
		return
	U.stop(svc, "uz_zimmer_ein")
	_spar_setzen(false)
	if bildzeit:
		bildzeit.setzen("", "")
	_verstecke_shell(false)
	if has_method("_hinweis_grund"):
		call("_hinweis_grund", true)
	super()


## Von layer.gd beim Schließen: Liegt die Kachel des Zimmers (Live-Bild, Zimmer-Kachel) wieder unter
## der Auswahl, schrumpft das Zimmer in T_WEG in ihr Rechteck, während die Ebene ausblendet.
func _exit_motion(_tw: Tween) -> void:
	if not is_instance_valid(svc) or U.reduziert() or main == null:
		return
	var r: Rect2 = main.zimmer_kachel_rect(Nav.focused())
	if r.size.x <= 0.0:
		return
	var voll := size if size.x > 1.0 else U.view_size()
	var k := clampf(maxf(r.size.x / voll.x, r.size.y / voll.y), 0.05, 1.0)
	svc.pivot_offset = Vector2.ZERO
	var t := U.ankommen(svc, U.T_WEG, "uz_zimmer_aus").set_parallel(true)
	t.tween_property(svc, "scale", Vector2(k, k), U.T_WEG)
	t.tween_property(svc, "position", (r.get_center() - voll * k * 0.5).round(), U.T_WEG)
	var hud: Variant = get("_hud")
	if hud is Control and is_instance_valid(hud):
		U.weg(hud as Control, "uz_zimmer_hud").tween_property(hud as Control, "modulate:a", 0.0, U.T_ANTWORT)


# --- Oberfläche über dem Zimmer ------------------------------------------------------------------

func _hud_lage() -> void:
	var s := size if size.x > 0 else U.view_size()
	_info.position = Vector2(UzTheme.GUTTER, s.y - 210)
	_ziel_pill.reset_size()
	_meldung.reset_size()
	_meldung.position = Vector2((s.x - _meldung.size.x) * 0.5, 64)


func _kopf_auffrischen() -> void:
	var zeit := str(raum.licht.get("z", "auto"))
	var z := tr(Daten.wahl_name(Daten.ZEITEN, Raum.zeit_jetzt(zeit) if zeit == "auto" else zeit))
	var st := str(_seiten.call("_stimmung_name")) if _seiten and str(raum.licht.get("st", "")) != "" else ""
	_kopf_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_kopf_titel.text = "Dein Zimmer"
	_kopf_sub.text = "%s · %s" % [str(raum.name), z] + (" · %s" % st if st != "" else "")
	if modus == "foto":
		_kopf_sub.text = tr("Pose: %s") % tr(str(FOTO_POSEN[int(_foto.get("pose", 0))][1]))
	elif _spiel_lief and Spielbild.titel() != "":
		_kopf_sub.text += " · " + tr("Im Fernseher: %s") % Spielbild.titel()
	_kopf.visible = modus not in ["baukasten", "fahrt", "fernsehen"]
	if welt:
		welt.vignette_leise(modus == "fernsehen")


## Was die Tasten gerade tun – nur, was jetzt geht. Die Hinweise liegen im Bild (tasten_ui.gd: eine
## Tastenzeile, Aktionstasten zuerst, B zuletzt); was A am Ziel tut, steht am Schild
## direkt am Möbel und nicht noch einmal unten. Die Hinweisleiste von main bleibt im Zimmer leer,
## kennt die Hinweise aber (Rechtsklick „Optionen“, Zurück-Knopf für Touch).
func _hinweise_auffrischen() -> void:
	var h: Array = []
	if bewohner and bewohner.leiste_offen():
		h = bewohner.hinweise()
	elif _kontext and _kontext.offen():
		h = [["a", str(_kontext.hinweis_a())], ["b", "Schließen"]]
	if h.is_empty():
		h = _umbau_hinweise()
	match "" if not h.is_empty() else modus:
		"laufen":
			var a := _ziel_handlung()
			if a != "":
				h.append(["a", a])
			elif blick != "oben":
				h.append(["a", "Springen"])
			if _ziel >= 0 and not _ziel_tier and not _ziel_fenster:
				h.append(["y", "Aktionen"])
			h.append(["x", BLICK_NAMEN[_naechster_blick()]])
			h.append(["b", "Zum Guide" if _spiel_lief and Launcher.in_game else "Klassische Ansicht"])
			h.append(["lt", "Stimmung"])
			h.append(["rt", "Emotes"])
			h.append(["menu", "Zimmer"])
		"ansehen":
			var p := _platz()
			match str(p.get("art", "")):
				"spiel":
					h.append(["a", "Spielen" if Library.is_installed(p.daten) else "Installieren"])
					h.append(["y", "Spielseite"])
				"pokal":
					h.append(["a", "Erfolge"])
				"platte":
					h.append(["a", "Auflegen"])
			h.append(["x", "Einrichten"])
			if _ans >= 0 and str(raum.moebel[_ans].t) == "spieleregal":
				h.append(["menu", "Einräumen"])
			h.append(["b", "Zurück"])
		"sitzen":
			if _spiel_lief and welt.medienwand() >= 0:
				h.append(["a", "Zum Spiel"])
			h.append(["x", BLICK_NAMEN[_naechster_blick()]])
			h.append(["b", "Aufstehen"])
		"bauen":
			var i := _feld_wahl()
			var t := str(_halten.t) if not _halten.is_empty() else (str(raum.moebel[i].t) if i >= 0 else "")
			h = bau_hinweise({ "tragen": not _halten.is_empty(), "farben": Katalog.varianten(t).size() if t != "" else 0,
				"moebel": i >= 0, "wand": _wand if i < 0 else "", "rueck": not _rueck.is_empty(), "drehbar": t != "" and Katalog.ebene(t) != "wand" })
		"katalog":
			h = _katalog.hinweise()
		"anpassen":
			h = _ui.hinweise()
		"baukasten":
			h = _baukasten.hinweise()
		"rad":
			h = []
		"foto":
			h = [["a", "Foto"], ["y", "Pose"], ["x", "Figur zeigen" if not bool(_foto.get("figur", true)) else "Figur ausblenden"],
				["b", "Fertig"], ["lb", ""], ["rb", "Zoom"], ["lt", ""], ["rt", "Höhe"]]
		"fahrt", "spiel":
			h = []
		"fernsehen":
			# Vor dem Fernseher, während das Spiel startet: keine Tasten (gleich geht es hinein); lief es
			# nicht an, steht B auf.
			h = [] if str(main.tv_zustand()) == "startet" else [["b", "Aufstehen"]]
	_leisten_auffrischen()
	if is_instance_valid(_tasten_ui):
		var am_ziel := _schild_aktion()
		var bild := h.filter(func(e: Array) -> bool: return not (str(e[0]) == "a" and str(am_ziel[1]) != "" and not bool(am_ziel[2])))
		_tasten_ui.setzen(bild)
	var sig := str(h)
	if sig == _hinweise_sig:
		return
	_hinweise_sig = sig
	set_meta("uz_hint_b", "")
	set_meta("uz_hints", h)
	set_meta("uz_hints_eigen", true)
	if main and "hint_bar" in main and is_instance_valid(main.hint_bar):
		main.hint_bar.refresh()


## Tastenzeile fürs Umbauen beim Laufen (zimmer_umbau.gd; []: wie sonst).
func _umbau_hinweise() -> Array:
	return []


## Einrichten: was gerade geht. z = { tragen, farben, moebel, wand, rueck, drehbar }. Höchstens vier
## Aktionstasten, darüber höchstens zwei kleine (am Möbel Drehen und Katalog, sonst das Zimmer-Menü)
## – nie eine lange Liste. RT öffnet den Katalog immer; gezeigt wird es dort, wo A etwas anderes tut.
## Modus-Leiste, Dock der Kategorien und die Lage der Tastenzeile folgen dem Modus.
func _leisten_auffrischen() -> void:
	if is_instance_valid(_modus_ui):
		_modus_ui.setzen(modus_gruppe(modus))
		_modus_ui.zeigen(modus in ["laufen", "bauen", "katalog", "foto", "sitzen", "ansehen"] and not (_kontext and _kontext.offen()))
	if is_instance_valid(_katalog):
		_katalog.dock(modus in ["bauen", "katalog"])
	if is_instance_valid(_tasten_ui):
		var u := 150.0 if modus in ["bauen", "katalog"] else 56.0
		if not is_equal_approx(float(_tasten_ui.unten), u):
			_tasten_ui.set("unten", u)
			_tasten_ui.queue_redraw()


## Zu welchem Modus der Modus-Leiste ein Zustand gehört.
static func modus_gruppe(m: String) -> String:
	if m in ["bauen", "katalog", "baukasten"]:
		return "bauen"
	if m == "foto":
		return "foto"
	return "leben"


static func bau_hinweise(z: Dictionary) -> Array:
	var h: Array = []
	var drehen := bool(z.get("drehbar", false))
	if bool(z.get("tragen", false)):
		h.append(["a", "Absetzen"])
		h.append(["x", "Wegräumen"])
		if int(z.get("farben", 0)) > 1:
			h.append(["y", "Farbe"])
		h.append(["b", "Abbrechen"])
		if drehen:
			h.append(["lb", ""])
			h.append(["rb", "Drehen"])
		return h
	if str(z.get("wand", "")) != "":
		h.append(["a", "Wand gestalten"])
		h.append(["y", "Raum größer/kleiner"])
	elif bool(z.get("moebel", false)):
		h.append(["a", "Hochheben"])
		h.append(["y", "Aktionen"])
	else:
		h.append(["a", "Katalog"])
		h.append(["y", "Boden"])
	if bool(z.get("rueck", false)):
		h.append(["x", "Rückgängig"])
	h.append(["b", "Fertig"])
	if bool(z.get("moebel", false)):
		if drehen:
			h.append(["lb", ""])
			h.append(["rb", "Drehen"])
		h.append(["rt", "Katalog"])
	else:
		h.append(["menu", "Zimmer"])
	return h


const BLICK_NAMEN := { "ich": "Ich-Ansicht", "schulter": "Schulterblick", "oben": "Von oben" }


## Ansichten der Reihe nach: Ich → über die Schulter → von oben → Ich.
func _naechster_blick() -> String:
	return str({ "ich": "schulter", "schulter": "oben" }.get(blick, "ich"))


func _melden(text: String) -> void:
	_meldung_l.text = text
	_meldung.reset_size()
	_hud_lage()
	var tw := U.tw(_meldung, "uz_zm")
	tw.tween_property(_meldung, "modulate:a", 1.0, U.T_BASE)
	tw.tween_interval(2.2)
	tw.tween_property(_meldung, "modulate:a", 0.0, U.T_MOVE)


func _info_zeigen(kicker: String, titel: String, meta: String) -> void:
	_info_kicker.text = kicker
	_info_titel.text = titel
	_info_meta.text = meta
	if _info.modulate.a < 0.99:
		U.tw(_info, "uz_zi").tween_property(_info, "modulate:a", 1.0, U.T_BASE)


func _info_weg() -> void:
	U.tw(_info, "uz_zi").tween_property(_info, "modulate:a", 0.0, U.T_FAST)


# --- Das Ziel vor dir ----------------------------------------------------------------------------

func _frei(p: Vector3) -> Vector3:
	var w := float(raum.w) * Katalog.ZELLE
	var t := float(raum.d) * Katalog.ZELLE
	p.x = clampf(p.x, RADIUS, w - RADIUS)
	p.z = clampf(p.z, RADIUS, t - RADIUS)
	for runde in 2:
		for i in (raum.moebel as Array).size():
			var it: Dictionary = raum.moebel[i]
			if Katalog.ebene(str(it.t)) != "boden":
				continue
			var g := Katalog.groesse_it(it)
			var x0 := float(it.x) * Katalog.ZELLE + 0.06 - RADIUS
			var z0 := float(it.z) * Katalog.ZELLE + 0.06 - RADIUS
			var x1 := float(int(it.x) + g.x) * Katalog.ZELLE - 0.06 + RADIUS
			var z1 := float(int(it.z) + g.y) * Katalog.ZELLE - 0.06 + RADIUS
			if p.x > x0 and p.x < x1 and p.z > z0 and p.z < z1:
				var aus := [p.x - x0, x1 - p.x, p.z - z0, z1 - p.z]
				var m: float = aus.min()
				if m == aus[0]:
					p.x = x0
				elif m == aus[1]:
					p.x = x1
				elif m == aus[2]:
					p.z = z0
				else:
					p.z = z1
		p.x = clampf(p.x, RADIUS, w - RADIUS)
		p.z = clampf(p.z, RADIUS, t - RADIUS)
	return p


func _augen() -> Vector3:
	return Vector3(pos.x, AUGEN + float(get("_hoehe")) - float(get("_duck_senken")), pos.z)


func _blickrichtung() -> Vector3:
	return (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.12 if blick == "oben" else pitch)) * Vector3.FORWARD


func _ziel_suchen() -> void:
	var o := _augen()
	var r := _blickrichtung()
	var neu := welt.treffer(o, r, REICHWEITE)
	if neu < 0:
		var tv := welt.treffer(o, r, REICHWEITE_TV)
		if tv >= 0 and Katalog.nutzen(str(raum.moebel[tv].t)) == "fernseher":
			neu = tv
	if neu < 0:
		# Auch was nichts tut (Tisch, Bild, Kommode): direkt im Blick lässt es sich verschieben, anpassen und
		# wegräumen (Y, A halten). Teppiche nicht – auf die schaut man beim Laufen ständig.
		var alles := welt.treffer(o, r, REICHWEITE, false, false)
		if alles >= 0 and alles < (raum.moebel as Array).size() and Katalog.ebene(str(raum.moebel[alles].t)) != "teppich":
			neu = alles
	var fenster := false
	# Das Haustier vor dir (näher als das Möbel): A streichelt es.
	var tier := bewohner != null and bewohner.tier_im_blick(o, r, REICHWEITE) \
			and (neu < 0 or o.distance_to((welt.boxen[neu] as AABB).get_center()) > o.distance_to(bewohner.tier.mitte()))
	if tier:
		neu = -1
	if neu < 0 and not tier and welt.fenster_getroffen(o, r, REICHWEITE + 0.4):
		fenster = true
	if neu != _ziel or fenster != _ziel_fenster or tier != _ziel_tier:
		_ziel = neu
		_ziel_fenster = fenster
		_ziel_tier = tier
		_glimmen_setzen(welt.knoten[_ziel] if _ziel >= 0 else (bewohner.tier as Node3D if tier else null))
		_ziel_zeigen()
		_hinweise_auffrischen()


func _ziel_handlung() -> String:
	if _ziel_fenster:
		return "Tageszeit"
	if _ziel_tier:
		return "Streicheln"
	if _ziel < 0:
		return ""
	var it: Dictionary = raum.moebel[_ziel]
	if not _bp.is_empty():
		match str(_bp.art):
			"spiel": return "Spielen" if Library.is_installed(_bp.daten) else "Installieren"
			"pokal": return "Erfolge"
			"platte": return "Auflegen"
	match Katalog.nutzen(str(it.t)):
		"spiele": return "Spiel aussuchen" if not (welt.plaetze.get(_ziel, []) as Array).is_empty() or str(it.t) != "spieleregal" else "Spiele einräumen"
		"pokale": return "Pokale ansehen"
		"platten": return "Platte aussuchen"
		"musik":
			if Music.now.is_empty():
				return "Musik öffnen"
			return "Pausieren" if bool(Music.now.get("playing", false)) else "Abspielen"
		"fernseher": return "Zum Spiel" if _spiel_lief else "Öffnen"       # das Schild nennt den Namen schon
		"sitzen": return "Hinsetzen"
		"lampe": return "Ausschalten" if bool(it.an) else "Einschalten"
		"figur": return "Figur wechseln"
		"tier": return "Haustier ändern"
	return ""


## Das Schild am Ziel: [Name, was A tut, Warnung]. Beim Laufen das Möbel vor dir, im Einrichten das
## Möbel unter dem Feld, das getragene (passt es nicht, sagt das Schild es gleich – nicht erst
## nach dem Drücken) oder die gewählte Wand.
func _schild_aktion() -> Array:
	if _kontext and _kontext.offen():
		return ["", "", false]
	match modus:
		"laufen":
			var a := _ziel_handlung()
			if a == "":
				return ["", "", false]
			if not _bp.is_empty():
				return [_platz_titel(_bp), a, false]
			# Eigene Möbel und das Haustier tragen Namen des Nutzers: nie übersetzen.
			if _ziel_fenster:
				return [tr("Fenster"), a, false]
			if _ziel_tier:
				return [bewohner.tier_name(), a, false]
			# Am Plattenspieler: was läuft (Titel · Künstler, nie übersetzt), sonst „läuft nichts“.
			if Katalog.nutzen(str(raum.moebel[_ziel].t)) == "musik":
				return [_laeuft_text(), a, false]
			return [_moebel_name(str(raum.moebel[_ziel].t)), a, false]
		"bauen", "katalog":
			if not _halten.is_empty():
				var t := str(_halten.t)
				if not Daten.passt(raum, _halten, _halten_idx):
					return [_moebel_name(t), tr("Hier ist kein Platz"), true]
				return [_moebel_name(t), "Absetzen", false]
			if modus == "katalog":
				return ["", "", false]
			var i := _feld_wahl()
			if i < 0 and _an_tuer():
				return [tr("Tür"), "Platz und Art", false]
			if _wand != "" and i < 0:
				return [tr(str(G.SEITEN_NAMEN.get(_wand, ""))), "Wand gestalten", false]
			if i >= 0:
				return [_moebel_name(str(raum.moebel[i].t)), "Hochheben", false]
	return ["", "", false]


## Was am Plattenspieler läuft: „Titel · Künstler“ (gekürzt), sonst „Plattenspieler – läuft nichts“.
func _laeuft_text() -> String:
	var now: Dictionary = Music.now
	if now.is_empty() or str(now.get("title", "")) == "":
		return tr("Plattenspieler – läuft nichts")
	var t := str(now.title)
	if str(now.get("artist", "")) != "":
		t += " · " + str(now.artist)
	return t if t.length() <= 48 else t.substr(0, 47).strip_edges() + "…"


## Name eines Platzes im Regal (Spiel, Pokal, Platte) – Namen aus der Bibliothek, nie übersetzt.
func _platz_titel(p: Dictionary) -> String:
	match str(p.get("art", "")):
		"spiel": return Library.display_title(p.daten)
		"pokal": return Library.display_title((p.daten as Dictionary).spiel)
		"platte": return str((p.daten as Dictionary).get("name", ""))
	return ""


func _moebel_name(t: String) -> String:
	return Katalog.name_of(t) if Katalog.ist_eigen(t) else tr(Katalog.name_of(t))


func _ziel_zeigen() -> void:
	var s := _schild_aktion()
	if str(s[1]) == "":
		U.tw(_ziel_pill, "uz_zp").tween_property(_ziel_pill, "modulate:a", 0.0, U.T_FAST)
		return
	var warnung := bool(s[2])
	_ziel_text.text = str(s[0])
	_ziel_aktion.text = str(s[1])
	_ziel_glyph.visible = not warnung
	_ziel_aktion.add_theme_color_override("font_color", UzTheme.col("danger_text") if warnung else UzTheme.col("muted"))
	_ziel_pill.reset_size()
	if _ziel_pill.modulate.a < 0.05:
		_schild_pos = Vector2(-1, -1)     # neu erscheinen: gleich an seinen Platz, nicht hingleiten
	U.tw(_ziel_pill, "uz_zp").tween_property(_ziel_pill, "modulate:a", 1.0, U.T_BASE)


## Zielt der Blick auf ein Möbel mit Bildschirm (Fernseher, Medienwand, Monitor)? Dann steht das
## Schild nie auf dem Bild, sondern knapp darunter (_schild_bild).
func _ziel_bildschirm() -> bool:
	if modus != "laufen" or not _bp.is_empty() or _ziel_tier or _ziel < 0 or _ziel >= welt.knoten.size():
		return false
	var n: Variant = welt.knoten[_ziel]
	return is_instance_valid(n) and (n as Node).has_meta("bildschirm")


## Fläche des Bildschirms am Ziel in der Ansicht (leer: nicht ganz vor der Kamera).
func _bildschirm_flaeche() -> Rect2:
	var bs: Variant = (welt.knoten[_ziel] as Node).get_meta("bildschirm")
	if not (bs is MeshInstance3D) or not ((bs as MeshInstance3D).mesh is QuadMesh):
		return Rect2()
	var q := (bs as MeshInstance3D).mesh as QuadMesh
	var cam: Camera3D = welt.kamera
	var r := Rect2()
	for i in 4:
		var e := Vector2(-0.5 if i in [0, 3] else 0.5, -0.5 if i < 2 else 0.5)
		var p3: Vector3 = (bs as MeshInstance3D).global_transform * Vector3(e.x * q.size.x, e.y * q.size.y, 0.0)
		if cam.is_position_behind(p3):
			return Rect2()
		var p := cam.unproject_position(p3)
		r = Rect2(p, Vector2.ZERO) if i == 0 else r.expand(p)
	return r


## Wo das Schild steht: in der Ich-Ansicht ruhig unter dem Punkt in der Mitte (dort zielt man),
## sonst über dem Ziel im Raum – es gleitet mit, wenn Kamera oder Möbel sich bewegen.
func _schild_bild(dt: float) -> void:
	if _ziel_pill.modulate.a <= 0.01:
		return
	var s := size if size.x > 0 else U.view_size()
	var ps := _ziel_pill.size
	var soll := Vector2(s.x * 0.5, s.y * 0.5 + 84.0 + ps.y)
	var p3: Variant = _schild_punkt()
	if not (modus == "laufen" and blick == "ich") and p3 is Vector3:
		var cam: Camera3D = welt.kamera
		if not cam.is_position_behind(p3):
			soll = cam.unproject_position(p3) - Vector2(0, 14)
	var oben := 150.0 + ps.y
	var unten := s.y - 200.0
	if _ziel_bildschirm():
		# Fernseher, Medienwand, Monitor: nie auf dem Bild – knapp unter seiner Unterkante, passt es
		# dort nicht, knapp darüber; ist kein Platz, bleibt nur der Tastenhinweis unten.
		var r := _bildschirm_flaeche()
		if r.size.x > 0.0:
			var luft := 12.0
			if r.end.y + luft + ps.y <= unten:
				soll = Vector2(r.get_center().x, r.end.y + luft + ps.y)
			elif r.position.y - luft >= oben:
				soll = Vector2(r.get_center().x, r.position.y - luft)
			else:
				_ziel_pill.visible = false
				return
	_ziel_pill.visible = true
	soll.x = clampf(soll.x, UzTheme.GUTTER + ps.x * 0.5, s.x - UzTheme.GUTTER - ps.x * 0.5)
	soll.y = clampf(soll.y, oben, unten)
	if _schild_pos.x < 0.0:
		_schild_pos = soll
	_schild_pos = _schild_pos.lerp(soll, 1.0 - exp(-dt * 14.0))
	_ziel_pill.position = (_schild_pos - Vector2(ps.x * 0.5, ps.y)).round()


## Punkt im Raum, über dem das Schild steht (null: keiner).
func _schild_punkt() -> Variant:
	var b := AABB()
	if modus in ["bauen", "katalog"] and not _halten.is_empty() and is_instance_valid(_halten_knoten):
		b = welt.box_von(_halten_knoten)
		b.position += _halten_knoten.get_parent().global_position if _halten_knoten.get_parent() is Node3D else Vector3.ZERO
	elif modus == "bauen":
		var i := _feld_wahl()
		if i < 0 and _wand != "":
			var w := float(raum.w) * Katalog.ZELLE
			var d := float(raum.d) * Katalog.ZELLE
			var m := { "hinten": Vector3(w * 0.5, 0, 0.1), "vorn": Vector3(w * 0.5, 0, d - 0.1), "links": Vector3(0.1, 0, d * 0.5), "rechts": Vector3(w - 0.1, 0, d * 0.5) }
			return (m[_wand] as Vector3) + Vector3(0, 0.6, 0)
		if i < 0 or i >= welt.boxen.size():
			return null
		b = welt.boxen[i]
	elif _ziel_tier and bewohner:
		return bewohner.tier.mitte() + Vector3(0, 0.45, 0)
	elif not _bp.is_empty() and _bp_m >= 0 and _bp_m < welt.knoten.size():
		return (_platz_lage(_bp, _bp_m)[0] as Vector3) + Vector3(0, 0.16, 0)
	elif _ziel >= 0 and _ziel < welt.boxen.size():
		b = welt.boxen[_ziel]
	else:
		return null
	var c := b.get_center()
	return Vector3(c.x, b.end.y + 0.12, c.z)


## Warmes Glimmen um das Möbel, das du ansiehst (wie das Glimmen um die Auswahl im Menü).
func _glimmen_setzen(n: Node3D) -> void:
	# Möbel mit Bildschirm (Fernseher, Medienwand, Monitor) glimmen gar nicht – weder Bild noch Gehäuse:
	# Das Glimmen lag auf dem Spielbild und um es herum und verfälschte es. Was A dort tut, steht im
	# Tastenhinweis unten.
	if n and n.has_meta("bildschirm"):
		n = null
	if n == _glimmen_an:
		return
	if is_instance_valid(_glimmen_an):
		_overlay(_glimmen_an, null)
	_glimmen_an = n
	_glimmen = 0.0
	if n:
		_overlay(n, S.glimmen())


static func _overlay(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_overlay = m
		if not (c is Label3D):
			_overlay(c, m)


# --- Kamera ------------------------------------------------------------------------------------

## Wohin die Kamera will: [Transform3D, Blickwinkel, Fokus-Entfernung].
func _kamera_soll() -> Array:
	var bw: Array = bewohner.kamera_soll() if bewohner else []
	if not bw.is_empty():
		return bw
	match modus:
		"ansehen":
			return _ansehen_kamera()
		"sitzen":
			var n: Node3D = welt.knoten[_sitz]
			var s: Dictionary = n.get_meta("sitz", {})
			var a: Vector3 = n.transform * (s.pos as Vector3)
			var z: Vector3 = n.transform * (s.ziel as Vector3)
			var t := Transform3D(Basis(), a).looking_at(z, Vector3.UP)
			t.basis = t.basis * Basis(Vector3.UP, _sitz_blick.x) * Basis(Vector3.RIGHT, _sitz_blick.y)
			return [t, 64.0, a.distance_to(z)]
		"bauen", "katalog", "baukasten":
			return _oben_kamera(Vector3((cursor.x + 0.5) * Katalog.ZELLE, 0.3, (cursor.y + 0.5) * Katalog.ZELLE), 0.18)
		"anpassen":
			if _anp_moebel >= 0 and _anp_moebel < welt.boxen.size():
				return _oben_kamera((welt.boxen[_anp_moebel] as AABB).get_center(), 0.85)
			return _oben_kamera(Vector3(float(raum.w) * Katalog.ZELLE * 0.5, 0.3, float(raum.d) * Katalog.ZELLE * 0.5), 0.0)
		"fahrt", "fernsehen", "spiel":
			return [welt.kamera.transform, welt.kamera.fov, 2.0]
		"foto":
			var fb := Basis(Vector3.UP, float(_foto.yaw)) * Basis(Vector3.RIGHT, float(_foto.pitch))
			var fp: Vector3 = _foto.pos
			return [Transform3D(fb, fp), float(_foto.fov), fp.distance_to(Vector3(pos.x, 1.0, pos.z))]
	if blick == "oben":
		return _oben_kamera(pos, 0.25)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var f := 3.0
	if _ziel >= 0:
		f = _augen().distance_to((welt.boxen[_ziel] as AABB).get_center())
	# Kopfwippen beim Gehen: dezent, abschaltbar (Kamera und Bild).
	var wipp := Vector3.ZERO
	if modus == "laufen" and bool(Config.get_value("room.wippen", true)):
		var ph := float(get("_wipp"))
		var vel: Vector3 = get("_vel")
		var k := 0.0 if bool(call("in_der_luft")) else clampf(Vector2(vel.x, vel.z).length() / 1.4, 0.0, 1.6)
		wipp = Vector3(0, -absf(sin(ph)) * 0.011 * k, 0) + b.x * sin(ph) * 0.006 * k
	return [Transform3D(b, _augen() + wipp), sicht_fov(), f]


## Einstellungen der Ego-Kamera (Zimmer-Menü › Kamera und Bild).
static func maus_empf() -> float:
	return clampf(float(Config.get_value("room.maus", 1.0)), 0.2, 4.0)


static func stick_empf() -> float:
	return clampf(float(Config.get_value("room.stick", 1.0)), 0.3, 3.0)


static func y_achse() -> float:
	return -1.0 if bool(Config.get_value("room.y_umkehren", false)) else 1.0


static func sicht_fov() -> float:
	return clampf(float(Config.get_value("room.fov", 70)), 55.0, 100.0)


static func tiefe_an() -> bool:
	return bool(Config.get_value("room.tiefe", false))


func _oben_kamera(folgen: Vector3, anteil: float) -> Array:
	var w := float(raum.w) * Katalog.ZELLE
	var d := float(raum.d) * Katalog.ZELLE
	var mitte := Vector3(w * 0.5, 0.4, d * 0.5).lerp(Vector3(folgen.x, 0.4, folgen.z), anteil)
	if modus == "katalog":
		# Der Katalog liegt unten: das Zimmer rückt im Bild nach oben.
		mitte += Vector3(sin(_oben_az), 0.0, cos(_oben_az)) * 2.2
	var zoom := _oben_zoom
	if modus == "anpassen":
		# Die Seitenleiste liegt rechts: das Zimmer rückt im Bild nach links; ein Möbel holt die
		# Kamera näher heran.
		var nah := _anp_moebel >= 0
		mitte += Vector3(cos(_oben_az), 0.0, -sin(_oben_az)) * (0.9 if nah else maxf(w, d) * 0.2)
		zoom *= 0.55 if nah else 1.0
	var dist := OBEN_ABSTAND * zoom * maxf(w, d) / 6.0
	var o := mitte + Vector3(sin(_oben_az) * cos(OBEN_HOEHE), sin(OBEN_HOEHE), cos(_oben_az) * cos(OBEN_HOEHE)) * dist
	var t := Transform3D(Basis(), o).looking_at(mitte, Vector3.UP)
	return [t, 34.0, dist]


# --- Licht und Aufstehen -------------------------------------------------------------------------

func _licht_neu(weich := true) -> void:
	(welt.huelle as Node).call("setze_licht", raum.licht, weich)
	welt.lampen_auffrischen()
	_kopf_auffrischen()


func _aufstehen() -> void:
	if _sitz >= 0:
		var n: Node3D = welt.knoten[_sitz]
		pos = _frei(n.transform * Vector3(0, 0, 0.95))
		var dir := (n.transform * Vector3(0, 0, 3.0)) - pos
		_yaw_soll = atan2(-dir.x, -dir.z)
		yaw = _yaw_soll
	_sitz = -1
	modus = "laufen"
	_rate = 3.0
	_hinweise_auffrischen()


# --- Plätze vor Möbeln (für Ansehen) -------------------------------------------------------------

## Reihenfolge der Plätze: Fächer von oben nach unten, links nach rechts; im Fach nach x bzw.
## bei Platten von vorn nach hinten.
func _platz_vor(a: Dictionary, b: Dictionary) -> bool:
	if absf(float(a.y) - float(b.y)) > 0.05:
		return float(a.y) > float(b.y)
	if int(a.fach) != int(b.fach):
		return float(a.x) < float(b.x)
	if a.has("tief"):
		return int(a.tief) < int(b.tief)
	return float(a.x) < float(b.x)


func _platz() -> Dictionary:
	if modus != "ansehen" or _ans_plaetze.is_empty():
		return {}
	return _ans_plaetze[clampi(_ans_sel, 0, _ans_plaetze.size() - 1)]


func _platz_zeigen() -> void:
	var p := _platz()
	if p.is_empty():
		var t := str(raum.moebel[_ans].t)
		# Spieleregale räumst du selbst ein (Menü-Taste); Pokale und Platten kommen von selbst.
		_info_zeigen(tr(Katalog.name_of(t)), tr("Noch leer"), tr("Selbst einräumen") if t == "spieleregal" else tr("Füllt sich automatisch."))
		return
	_ans_merk[_ans] = _ans_sel
	match str(p.art):
		"spiel":
			var g: Dictionary = p.daten
			var sys := str(g.get("system", ""))
			var sname := str(Config.system(sys).get("name", "")) if sys != "" else ""
			if sname == "":
				sname = Library.store_name(g, false, "PC")
			var zeit := Library.playtime(g)
			var teile: Array = []
			teile.append(U.playtime(zeit) if zeit > 0 else tr("Noch nicht gespielt"))
			var lp := Library.last_played(g)
			if lp > 0:
				teile.append(tr("zuletzt %s") % U.lower_first(tr(U.ago(lp))))
			_info_zeigen(sname, Library.display_title(g), " · ".join(teile))
		"pokal":
			var e: Dictionary = p.daten
			var stufe := str({ "platin": "Platin", "gold": "Gold", "silber": "Silber", "bronze": "Bronze" }.get(str(e.stufe), ""))
			_info_zeigen(tr(stufe), Library.display_title(e.spiel), tr("%d von %d Erfolgen") % [int(e.frei), int(e.gesamt)])
		"platte":
			var d: Dictionary = p.daten
			_info_zeigen(tr("Platte"), str(d.name), str(d.sub))
	_hinweise_auffrischen()


## Mitte eines Platzes in der Welt und die Richtung „nach vorn“ (aus dem Möbel heraus).
func _platz_lage(p: Dictionary, moebel := -1) -> Array:
	var mi := moebel if moebel >= 0 else _ans
	var m: Node3D = welt.knoten[mi] if mi >= 0 else null
	var vorn := (m.global_transform.basis.z if m else Vector3.BACK).normalized()
	var mitte := Vector3.ZERO
	match str(p.art):
		"spiel":
			if p.has("mm"):
				mitte = m.global_transform * (p.basis as Transform3D).origin
			else:
				var k: Node3D = p.knoten
				mitte = k.global_transform * Vector3(0, float(k.get_meta("hoehe", 0.19)) * 0.5, 0)
		"pokal":
			mitte = (p.knoten as Node3D).global_position + Vector3(0, 0.1, 0)
		"platte":
			mitte = (p.knoten as Node3D).global_position + Vector3(0, 0.12, 0)
	return [mitte, vorn]


func _ansehen_kamera() -> Array:
	var p := _platz()
	var m: Node3D = welt.knoten[_ans]
	if p.is_empty():
		var b: Dictionary = m.get_meta("blick", { "pos": Vector3(0, 1.4, 1.4), "ziel": Vector3(0, 1.0, 0) })
		var a: Vector3 = m.transform * (b.pos as Vector3)
		var z: Vector3 = m.transform * (b.ziel as Vector3)
		return [Transform3D(Basis(), a).looking_at(z, Vector3.UP), 55.0, a.distance_to(z)]
	var l := _platz_lage(p)
	var mitte: Vector3 = l[0]
	var vorn: Vector3 = l[1]
	var abstand := 0.66
	var hoch := 0.1
	match str(p.art):
		"pokal":
			abstand = 0.66
			hoch = 0.17
		"platte":
			abstand = 0.78
			hoch = 0.32
	var o := mitte + vorn * abstand + Vector3(0, hoch, 0)
	return [Transform3D(Basis(), o).looking_at(mitte, Vector3.UP), 50.0, o.distance_to(mitte)]


# --- Raster des Bau-Modus ------------------------------------------------------------------------

func _raster_auffrischen() -> void:
	if _wand != "" and _halten.is_empty() and _feld_wahl() < 0:
		welt.raster_wand(_wand)
		_glimmen_setzen(null)
		return
	if not _halten.is_empty():
		var g := Katalog.groesse_it(_halten)
		var ok := Daten.passt(raum, _halten, _halten_idx)
		welt.raster_bereich(int(_halten.x), int(_halten.z), g.x, g.y, ok, 0.03, true)
		return
	var i := _feld_wahl()
	if i >= 0:
		var it: Dictionary = raum.moebel[i]
		var g2 := Katalog.groesse_it(it)
		welt.raster_bereich(int(it.x), int(it.z), g2.x, g2.y, true)
		_glimmen_setzen(welt.knoten[i])
		_glimmen = 0.0
	else:
		welt.raster_bereich(cursor.x, cursor.y, 1, 1, true)
		_glimmen_setzen(null)


## Einrichten: das gewählte Möbel unter dem Feld (-1: keins). Liegt mehreres dort (Tasse auf dem
## Tisch, Bild über der Kommode), das mit Y › „… wählen“ gewählte, sonst das oberste; ein Schritt über
## den Rand wählt das Wandmöbel, das dort hängt (sonst die Wand selbst).
func _feld_wahl() -> int:
	if not _halten.is_empty():
		return -1
	if _wand != "":
		return Daten.an_wandfeld(raum, cursor)
	# Eine Frage statt zwei: Jede baut die Belegung des ganzen Raums (gemessen 0,27 ms bei 32 Möbeln, 2,9 ms
	# bei 300), und das Schild fragt in jedem Bild. Das oberste Möbel ist das erste der Liste (wie an_feld).
	var da := Daten.alle_an_feld(raum, cursor.x, cursor.y)
	if da.is_empty():
		return -1
	return _wahl if _wahl >= 0 and _wahl < (raum.moebel as Array).size() and _wahl in da else int(da[0])


## Einrichten: ein Schritt über den Rand vor der Tür gewählt. Die Tür bleibt immer (durch sie kommst du
## herein, zimmer.gd _eintreten_tuer) – A wählt ihren Platz an der Wand und ihre Art.
func _an_tuer() -> bool:
	if _wand != "rechts" or welt == null or welt.huelle == null:
		return false
	var t: Vector3 = welt.huelle.call("tuer_mitte")
	return absf((float(cursor.y) + 0.5) * Katalog.ZELLE - t.z) < 0.5


func _ablegen_abbrechen() -> void:
	if _halten_idx < 0:
		if is_instance_valid(_halten_knoten):
			_halten_knoten.queue_free()
	else:
		welt.setze_ort(welt.knoten[_halten_idx], raum.moebel[_halten_idx], _halten_idx)
		for d in _halten_dabei:
			welt.setze_ort(welt.knoten[int(d.idx)], raum.moebel[int(d.idx)], int(d.idx))
		cursor = Vector2i(int(raum.moebel[_halten_idx].x), int(raum.moebel[_halten_idx].z))
	_halten = {}
	_halten_idx = -1
	_halten_knoten = null
	_halten_dabei = []
	_raster_auffrischen()
	_hinweise_auffrischen()


# --- Merken (Rückgängig) und Ändern --------------------------------------------------------------

## Ein Rückgängig-Schritt je Zeile: die erste Änderung merkt den Stand, weitere auf derselben Zeile
## (Farben durchblättern, Regler schieben) gehören zum selben Schritt.
func _merken(immer := false) -> void:
	if not _schritt_offen and not immer:
		return
	_schritt_offen = false
	var snap := Daten.schnappschuss(raum)
	snap["_extra"] = { "eigene": (daten.get("eigene", []) as Array).duplicate(true), "stimmungen": (daten.get("stimmungen", []) as Array).duplicate(true),
		"farben": (daten.get("farben", []) as Array).duplicate(), "huellen": (daten.get("huellen", {}) as Dictionary).duplicate(),
		"vorlagen": (daten.get("vorlagen", []) as Array).duplicate(true), "figur": (daten.get("figur", {}) as Dictionary).duplicate(),
		"tier": (daten.get("tier", {}) as Dictionary).duplicate() }
	_rueck.append(snap)
	while _rueck.size() > Daten.MAX_SCHRITTE:
		_rueck.pop_front()


func _geaendert() -> void:
	_speichern_bald()
	_kopf_auffrischen()
	if modus == "anpassen":
		_ui._neu_zeichnen()


# --- Welt neu aufbauen ---------------------------------------------------------------------------

## Die Welt ganz neu bauen (Raumgröße, Vorlage, eigene Möbel): Kamera bleibt, wo sie war.
func _welt_neu() -> void:
	# Sparsame Grafik gehört zur alten Welt: erst zurück, dann für die neue wieder an.
	var spar := _spar
	_spar_setzen(false, false)
	var cam_t := welt.kamera.global_transform
	var cam_fov := welt.kamera.fov
	var raster_an := welt.raster.visible
	if bewohner:
		welt.remove_child(bewohner)       # Figur und Haustier ziehen in die neue Welt mit
	welt.queue_free()
	welt = Welt.new()
	welt.huellen = daten.get("huellen", {})
	vp.add_child(welt)
	welt.bauen(raum, stufe)
	if bewohner:
		bewohner.umziehen(welt)
	# Läuft ein Spiel, zeigt auch der neue Fernseher es gleich wieder.
	if _spiel_lief:
		welt.laeuft_titel = Spielbild.titel()
		welt.tv_auffrischen()
		if spielbild and spielbild.letztes:
			welt.tv_live(spielbild.letztes)
	welt.kamera.global_transform = cam_t
	welt.kamera.fov = cam_fov
	welt.raster.visible = raster_an
	cursor = Vector2i(clampi(cursor.x, 0, int(raum.w) - 1), clampi(cursor.y, 0, int(raum.d) - 1))
	pos = _frei(pos)
	_glimmen_an = null
	_ziel = -1
	_anp_moebel = -1 if _anp_moebel >= (raum.moebel as Array).size() else _anp_moebel
	if spar:
		_spar_setzen(true, false)


## Posen der Figur im Fotomodus: [Emote, Name, Augenblick im Emote, der gut aussieht].
const FOTO_POSEN := [["", "Stehen", 0.0], ["winken", "Winken", 1.05], ["jubeln", "Jubeln", 0.62], ["daumen", "Daumen hoch", 0.9],
	["tanzen", "Tanzen", 1.25], ["klatschen", "Klatschen", 0.95], ["zucken", "Schulterzucken", 0.8], ["sitzen", "Hinsetzen", 2.0]]


# --- Speichern ---------------------------------------------------------------------------------

func _speichern_bald() -> void:
	if besuch:
		return
	_speicher_timer.start()


## Beim Besuch (Freundestest) geht nichts, was das Zimmer ändert: kurzer Hinweis, true = gesperrt.
func besuch_sperre() -> bool:
	if not besuch:
		return false
	Sfx.play("bump")
	Toasts.show_toast("Nur der Gastgeber", "Beim Besuch änderst du nichts.", "lock", { "quiet": true })
	return true

extends Node
## Leistung des Zimmers: wie oft und wie groß die 3D-Ansicht gerechnet wird, und was das kostet.
## Ziel ist die volle Bildrate des Bildschirms bei gutem Bild – gespart wird an den Kosten je Bild
## (licht.gd, raum.gd, zimmer_welt.gd), nicht an der Zahl der Bilder.
##
##   Bildrate: wie im Menü (main _menu_fps, display_fit.gd: bis 144 Hz alle Bilder des Bildschirms);
##     Config room.fps „60“ oder „30“ begrenzt auf einen ganzzahligen Teil der Bildschirmrate (jedes
##     Bild steht gleich lange). Jedes Bild wird neu gerechnet – keinen Ruhe-Takt mehr: Die Figur atmet,
##     Lampen und Fernseher flimmern, Staub schwebt; ein halber Takt war als Ruckeln zu sehen.
##     Neben einem laufenden Spiel ebenso: Wer im Zimmer ist, sieht es flüssig; kommt die Grafikkarte
##     nicht nach, wird die 3D-Auflösung kleiner (schlanker Weg, SCHLANK), nicht die Bildrate. Erst wenn
##     alle im Zimmer aufs Spiel schauen (Vollbild, fernsehspiel.gd alle_fokussiert), wartet es unsichtbar
##     dahinter mit spiel_kappe: dem kleinsten ganzzahligen Teil der Bildschirmrate, der noch mindestens
##     SPIEL_MIN_FPS hat (165 Hz → 82, 144 → 72, 120 → 60, 60 → 60; zimmer_basis.gd ruhe_fps).
##   Auflösung: licht.gd aufloesung() gibt Upscaler und Grenzen der Skala; hier wird die Zeit der
##     Grafikkarte gemessen (RenderingServer.viewport_get_measured_render_time_gpu) und die Skala in
##     wenigen festen Stufen (SKALEN) angepasst – nach unten nach RUNTER_S über dem Ziel, nach oben erst
##     nach RAUF_S deutlich darunter, nie öfter als alle WECHSEL_S (kein Pumpen; jeder Wechsel baut die
##     Puffer neu). Ziel: die Grafikkarte braucht je Bild höchstens ANTEIL der Bildzeit (Luft für
##     gleichmäßige Bilder), neben dem laufenden Spiel ANTEIL_SPIEL (der Rest gehört dem Spiel). Neben dem
##     Spiel gilt in jeder Stufe derselbe schlanke Rahmen (SCHLANK: FSR 1 bei 50–67 %, FXAA statt MSAA,
##     zimmer_basis.gd _spar_setzen schaltet die teuren Effekte ab). Die Skala, bei der es sich
##     eingependelt hat, merkt sich Uzai je Grafikkarte, Stufe und Bildschirmhöhe (Config
##     room.grafik_skala) als Startwert für das nächste Betreten.
##   Automatisch (room.grafik „auto“): nach LERNEN_S merkt sich Uzai je Grafikkarte, ob die Stufe eins
##     höher passt (bei größter Skala geschätzt noch viel Luft) oder eins tiefer (zu langsam bei
##     kleinster) – gilt ab dem nächsten Betreten (Config room.grafik_auto, licht.gd stufe_jetzt).
##   launch.log: beim Betreten Stufe, Auflösung, Upscaler, Kantenglättung, GI und Zielrate; nach
##     BERICHT_S Ist-Bildrate, Zeit der Grafikkarte und des Prozessors je Bild, Zeichenaufrufe und
##     Primitive der Ansicht und ihrer Schatten und die Möbel mit den meisten Netzen; jeder Wechsel der
##     Skala (höchstens MAX_ZEILEN je Zimmer).
##   Ablauf je Bild: selbst gemessen vom ersten _process bis nach dem Zeichnen (RenderingServer
##     frame_post_draw) – Skripte, Zeichnen und das Warten auf Grafikkarte und Bildschirm, für jedes Bild
##     einzeln, samt dem teuersten Abschnitt des Zimmers darin (bildzeit.gd nennt so den längsten Ablauf).
##     Performance.TIME_PROCESS taugte dafür nicht: ein Höchstwert je Sekunde, der eine einzelne lange
##     Umstellung (Aufstehen, Guide) noch eine Sekunde nach dem Wechsel in jede Messung trug.
##   Pipelines vorab: Godot 4.5 übersetzt die Pipelines jeder Fläche schon beim Anlegen im Hintergrund –
##     aber nur für das, was die Engine erwartet: MSAA wie in den Projekteinstellungen (aus) und Schatten-
##     atlas mit 16 Bit. Das Zimmer zeichnet mit MSAA (Stufe, Backen) und 32-Bit-Schatten; jede Fläche
##     wurde darum erst beim ersten Zeichnen übersetzt, und das Bild wartete (beim Betreten in Ultra einige
##     Sekunden lang rund 20 Bilder/s). Solange das Zimmer offen ist, erwartet die Engine, was es braucht
##     (pipelines_erwarten, zimmer_basis.gd _pipelines_planen: Ansicht, Backen, schlanker Weg); beim
##     Schließen gilt wieder das Projekt. launch.log nennt nach BERICHT_S, wie viele „beim Zeichnen“ blieben.
##   Anzeige: Ist „Leistung in der Ecke“ an (Config system.perf_corner), zeigt das Zimmer oben links
##     Bilder je Sekunde, Zeit der Grafikkarte und des Prozessors je Bild (perf_live.gd zimmer_parts).
##
## Rechnen ohne Fenster prüfbar (tests/logic_zgrafik.gd): zielrate, bewegungsrate, skala_schritt, ziel_ms.

const Licht := preload("res://src/room/licht.gd")
const Leicht := preload("res://src/core/leicht.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const U := preload("res://src/ui/u.gd")

## Bildrate im Zimmer (Config room.fps): wie der Bildschirm oder höchstens 60 bzw. 30 je Sekunde.
const RATEN := [["bildschirm", "Wie der Bildschirm"], ["60", "60 Bilder/s"], ["30", "30 Bilder/s"]]
const SKALEN := [1.0, 0.87, 0.77, 0.67, 0.59, 0.5]
const ANTEIL := 0.75
const ANTEIL_SPIEL := 0.3         ## neben dem Spiel: höchstens so viel der Bildzeit (der Rest gehört dem Spiel)
const SPIEL_MIN_FPS := 60         ## hinter dem Spiel nie weniger Bilder (spiel_kappe)
## Schlanker Weg neben dem laufenden Spiel, in jeder Stufe gleich: FSR 1 bei höchstens 67 %, kleiner bis 50 %,
## FXAA statt MSAA und SMAA.
const SCHLANK := { "modus": "fsr", "aa": "fxaa", "msaa": 0, "start": 0.67, "max": 0.67, "min": 0.5 }
const RAUF_ANTEIL := 0.6          ## so weit unter dem Ziel (RAUF_S lang) → eine Stufe größer
const RUNTER_S := 2.0
const RAUF_S := 5.0
const WECHSEL_S := 4.0
const BLOCK_S := 0.5              ## Messwerte je so viele Sekunden mitteln
const BERICHT_S := 8.0
const LERNEN_S := 12.0
const LERNEN_LUFT := 0.5          ## Automatisch: bei größter Skala geschätzt so wenig vom Ziel → eine Stufe höher
const ANZEIGE_S := 0.5
const MAX_ZEILEN := 12

var vp: SubViewport
var dynamisch := true             ## Skala nach der gemessenen Zeit (Proben schalten das ab)
var halten := false               ## Fotomodus: Skala bleibt, wie das Zimmer sie setzt
var stufe := ""
var wahl := ""                    ## room.grafik („auto“ lernt)
var rahmen := {}                  ## licht.gd aufloesung(): modus, aa, start, max, min
var gi_text := ""                 ## Licht als Text (launch.log; zimmer_basis.gd)
var licht_info: Callable          ## → String: wie oft und wie lange zuletzt gebacken wurde (lichtbacken.gd)
var skala := 1.0
var spar_grenze := 1.0            ## Kompatibilität neben dem laufenden Spiel (licht.gd spar_werte): höchstens so groß
var spiel := false                ## ein Spiel läuft (Ziel ANTEIL_SPIEL)
var schlank := false              ## schlanker Weg neben dem Spiel (SCHLANK statt des Rahmens der Stufe)
var menu_fps: Callable            ## → int: Bildrate, die main im Menü setzt (0 = wie der Bildschirm)
var hz := 60.0
var rate := 60                    ## Zielbildrate jetzt
var gpu_ms := 0.0                 ## zuletzt gemittelte Zeit der Grafikkarte je Bild (Ansicht + Fenster)
var cpu_ms := 0.0                 ## zuletzt gemittelte Zeit des Prozessors je Bild fürs Zeichnen (Ansicht, Fenster)
var ablauf_ms := 0.0              ## Ablauf je Bild (Skripte, Zeichnen, Warten), Mittel seit dem letzten Block
var abstand_ms := 0.0             ## echter Abstand der Bilder, Mittel dazu (der Rest: Physik, Ereignisse, Kappe)
var skript_ms := 0.0              ## zuletzt gemittelte Zeit aller Skripte (_process) je Bild
var bild_ms := 0.0                ## echte Zeit vom vorigen zu diesem Bild (ohne die Glättung der Engine)
var ablauf_bild_ms := 0.0         ## Ablauf des zuletzt gezeichneten Bilds: erster _process bis nach dem Zeichnen
var skript_bild_ms := 0.0         ## davon die Skripte (alle _process)
var teuerster_bild := ""          ## teuerster Abschnitt des Zimmers in diesem Bild („Spielbild 1.2 ms“)
var netze_info: Callable          ## → String: Möbel mit den meisten Netzen (zimmer.gd, launch.log nach BERICHT_S)
var vorab_text := ""              ## welche Pipelines vorab übersetzt werden (zimmer_basis.gd _pipelines_planen)

var _gesetzt := -1                ## was hier zuletzt in Engine.max_fps geschrieben wurde
var _fps_wahl := "bildschirm"
var _seit_start := 0.0
var _gemeldet := false
var _summe := 0.0
var _cpu_summe := 0.0
var _ablauf_summe := 0.0
var _abstand_summe := 0.0
var _ablauf_n := 0
var _n := 0
var _block := 0.0
var _ueber := 0.0
var _unter := 0.0
var _seit_wechsel := 0.0
var _rahmen_stufe := {}           ## Rahmen der Stufe, solange der schlanke Weg gilt
var _skala_stufe := 1.0
var _pipelines := []              ## übersetzte Pipelines der Engine beim Betreten (Zeichnen, Flächen, Spezialisierung)
var _ablauf_max := 0.0            ## längster Ablauf je Bild seit dem Bericht (und was ihn kostete)
var _ablauf_max_text := ""
var _bericht := false
var _gelernt := false
var _zeilen := 0
var _messen := false
var _lern_summe := 0.0
var _lern_n := 0
var _anzeige: CanvasLayer
var _anzeige_zeile: HBoxContainer
var _anzeige_s := 0.0
var _skript_summe := 0.0          ## Skripte je Bild (vom ersten bis zum letzten _process), Summe seit dem Bericht
var _skript_n := 0
var _ende: Node                   ## läuft als letzter _process im Bild (misst das Ende der Skripte)
var _t_anfang := 0

## Zeit je Abschnitt des Zimmers (µs, Summe) und Zahl der Bilder dazu: zimmer.gd, spielbild.gd messen ihre
## Teile, launch.log zeigt die teuersten (skript_text).
static var _abschnitte := {}
static var _abschnitt_bilder := 0
static var _abschnitte_bild := {}   ## dasselbe nur für das laufende Bild (teuerster Abschnitt des längsten Bilds)

const MSAA_EINST := "rendering/anti_aliasing/quality/msaa_3d"
const ATLAS16_EINST := "rendering/lights_and_shadows/positional_shadow/atlas_16_bits"
static var _projekt := {}            ## Projekteinstellungen vor pipelines_erwarten (zum Zurückstellen)


# --- Rechnen (ohne Fenster prüfbar) ------------------------------------------------------------------

## Zielbildrate im Zimmer: menu = was main im Menü setzt (0 = wie der Bildschirm), wahl = room.fps
## („60“, „30“: ganzzahliger Teil der Bildschirmrate nahe daran, nie mehr als das Menü).
static func zielrate(wahl_fps: String, bildschirm_hz: float, menu: int) -> int:
	var h := bildschirm_hz if bildschirm_hz > 1.0 else 60.0
	var r := menu if menu > 0 else roundi(h)
	if wahl_fps in ["60", "30"]:
		r = mini(r, bewegungsrate(h, int(wahl_fps)))
	return r


## Ganzzahliger Teil der Bildschirmrate (jedes Bild steht gleich lange), möglichst nah an ziel
## (120 Hz → 60, 144 → 72, 165 → 55, 60 → 60); hart: höchstens ziel (144 Hz, 60 → 48). Unbekannt: 60 Hz.
static func bewegungsrate(bildschirm_hz: float, ziel: int, hart := false) -> int:
	var h := bildschirm_hz if bildschirm_hz > 1.0 else 60.0
	if h <= ziel + 0.5:
		return roundi(h)
	var n := ceilf(h / float(ziel)) if hart else maxf(1.0, roundf(h / float(ziel)))
	return roundi(h / n)


## Nächste Skala: ueber_s/unter_s = so lange (s) über bzw. deutlich unter dem Ziel. Wechselt höchstens
## eine Stufe aus SKALEN, innerhalb von [kleinste, groesste].
static func skala_schritt(jetzt: float, ueber_s: float, unter_s: float, kleinste: float, groesste: float) -> float:
	var stufen: Array = [groesste]
	for k: float in SKALEN:
		if k < groesste - 0.02 and k >= kleinste - 0.001:
			stufen.append(k)
	if stufen[stufen.size() - 1] > kleinste + 0.02:
		stufen.append(kleinste)
	# Wo stehen wir (nächste Stufe zur jetzigen Skala)?
	var i := 0
	for j in stufen.size():
		if absf(float(stufen[j]) - jetzt) < absf(float(stufen[i]) - jetzt):
			i = j
	if ueber_s >= RUNTER_S and i < stufen.size() - 1:
		return float(stufen[i + 1])
	if unter_s >= RAUF_S and i > 0:
		return float(stufen[i - 1])
	return float(stufen[i])


## Bildrate, solange das Zimmer hinter dem Spiel wartet und alle aufs Spiel schauen (zimmer_basis.gd
## ruhe_fps): der kleinste ganzzahlige Teil der Bildschirmrate, der noch mindestens SPIEL_MIN_FPS hat
## (jedes Bild steht gleich lange): 165 Hz → 82, 144 → 72, 120 → 60, 240 → 60, 60 → 60, 100 → 100;
## unbekannt wie 60 Hz. Knapp darunter zählt wie darauf (119,88 Hz → 60).
static func spiel_kappe(bildschirm_hz: float) -> int:
	var h := bildschirm_hz if bildschirm_hz > 1.0 else 60.0
	var n := maxi(1, floori((h + 0.5) / float(SPIEL_MIN_FPS)))
	return int(h / float(n) + 0.1)


## Bildzeit-Ziel der Grafikkarte je Bild (ms) bei Bildrate r: neben dem Spiel weniger.
static func ziel_ms(r: int, im_spiel: bool) -> float:
	return 1000.0 / float(maxi(r, 1)) * (ANTEIL_SPIEL if im_spiel else ANTEIL)


## Startskala: was auf dieser Karte, Stufe und Bildschirmhöhe zuletzt galt (gemerkt), sonst rahmen.start;
## immer innerhalb der Grenzen.
static func startskala(r: Dictionary, gemerkt: Variant, karte: String, st: String, hoehe: int) -> float:
	var k := float(r.get("start", 1.0))
	if gemerkt is Dictionary:
		var g := gemerkt as Dictionary
		if str(g.get("karte", "")) == karte and karte != "" and str(g.get("stufe", "")) == st and int(g.get("hoehe", 0)) == hoehe:
			k = float(g.get("skala", k))
	return clampf(k, float(r.get("min", 1.0)), float(r.get("max", 1.0)))


## Ein Abschnitt ist fertig (seit t0 in µs): Zeit dazuzählen. Gibt die jetzige Zeit zurück (nächster Abschnitt).
static func abschnitt(name: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	_abschnitte[name] = int(_abschnitte.get(name, 0)) + (t - t0)
	_abschnitte_bild[name] = int(_abschnitte_bild.get(name, 0)) + (t - t0)
	return t


## Die n teuersten Abschnitte je Bild als Text: „Figur und Haustier 0,8 ms, Kamera 0,3 ms, …“.
static func skript_text(n := 3) -> String:
	if _abschnitt_bilder <= 0 or _abschnitte.is_empty():
		return "–"
	var namen := _abschnitte.keys()
	namen.sort_custom(func(a: Variant, b: Variant) -> bool: return int(_abschnitte[a]) > int(_abschnitte[b]))
	var teile := PackedStringArray()
	for k in namen.slice(0, n):
		teile.append("%s %.2f ms" % [k, float(_abschnitte[k]) / 1000.0 / _abschnitt_bilder])
	return ", ".join(teile)


static func _abschnitte_leeren() -> void:
	_abschnitte.clear()
	_abschnitte_bild.clear()
	_abschnitt_bilder = 0


## Der teuerste Abschnitt des laufenden Bilds als Text („Spielbild 1.20 ms“, „“ ohne).
static func _teuerster_jetzt() -> String:
	var bester := ""
	var us := 0
	for k: String in _abschnitte_bild:
		if int(_abschnitte_bild[k]) > us:
			us = int(_abschnitte_bild[k])
			bester = k
	return "%s %.2f ms" % [bester, us / 1000.0] if bester != "" else ""


# --- Im Zimmer ---------------------------------------------------------------------------------------

func _ready() -> void:
	# Skriptzeit je Bild: dieser Knoten läuft als erster (_process), _ende als letzter.
	process_priority = -1000000
	_ende = _EndeSkript.new()
	_ende.process_priority = 1000000
	add_child(_ende)
	_abschnitte_leeren()
	RenderingServer.frame_post_draw.connect(_gezeichnet)
	_pipelines = _pipelines_jetzt()


## Wie viele Pipelines die Engine bisher übersetzt hat: beim Zeichnen (das Bild wartet darauf), für neue
## Flächen und als Spezialisierung (im Hintergrund).
static func _pipelines_jetzt() -> Array:
	return [Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)]


## Pipelines vorab: Die Engine soll für alle Flächen MSAA msaa (Viewport.MSAA_*) und 32-Bit-Schatten
## erwarten – sie übersetzt dann im Hintergrund, was ihr dafür noch fehlt, bevor es gezeichnet wird.
static func pipelines_erwarten(msaa: int) -> void:
	if _projekt.is_empty():
		_projekt = { MSAA_EINST: ProjectSettings.get_setting(MSAA_EINST, 0), ATLAS16_EINST: ProjectSettings.get_setting(ATLAS16_EINST, true) }
	_einstellung(ATLAS16_EINST, false)
	_einstellung(MSAA_EINST, msaa)


## Zimmer zu: wieder wie im Projekt (andere 3D-Ansichten zeichnen, wie sie es immer taten).
static func pipelines_zurueck() -> void:
	for k: String in _projekt:
		_einstellung(k, _projekt[k])
	_projekt = {}


static func _einstellung(k: String, v: Variant) -> void:
	if ProjectSettings.get_setting(k) != v:
		ProjectSettings.set_setting(k, v)


## Seit dem Betreten übersetzte Pipelines als Text (launch.log nach BERICHT_S).
func _pipelines_text() -> String:
	var jetzt := _pipelines_jetzt()
	var d := []
	for i in 3:
		d.append(int(jetzt[i]) - (int(_pipelines[i]) if i < _pipelines.size() else 0))
	return "Pipelines seit dem Betreten übersetzt: beim Zeichnen %d (das Bild wartet), Flächen %d, Spezialisierung %d" % d


func _process(_dt: float) -> void:
	var t := Time.get_ticks_usec()
	if _t_anfang > 0:
		bild_ms = (t - _t_anfang) / 1000.0
	_t_anfang = t


## Vom letzten _process im Bild (_ende): Zeit der Skripte dieses Bilds.
func _skripte_ende() -> void:
	if _t_anfang > 0:
		skript_bild_ms = (Time.get_ticks_usec() - _t_anfang) / 1000.0
		_skript_summe += skript_bild_ms
		_skript_n += 1
		_abschnitt_bilder += 1


## Nach dem Zeichnen (auch ohne Zimmer vorn): Ablauf dieses Bilds und sein teuerster Abschnitt.
func _gezeichnet() -> void:
	if _t_anfang <= 0:
		return
	ablauf_bild_ms = (Time.get_ticks_usec() - _t_anfang) / 1000.0
	teuerster_bild = _teuerster_jetzt()
	_abschnitte_bild.clear()
	_ablauf_summe += ablauf_bild_ms
	_abstand_summe += bild_ms
	_ablauf_n += 1
	# Der längste Ablauf zählt erst, wenn das Zimmer steht (das Bauen beim Betreten ist kein Ruckler).
	if ablauf_bild_ms > _ablauf_max and _seit_start >= 1.0:
		_ablauf_max = ablauf_bild_ms
		_ablauf_max_text = ablauf_text(ablauf_bild_ms, skript_bild_ms, teuerster_bild)


## Ein langer Ablauf als Text: „31.0 ms (Skripte 2.1 ms, teuerster Abschnitt Spielbild 1.20 ms)“.
static func ablauf_text(ms: float, skripte: float, teuerster: String) -> String:
	return "%.1f ms (Skripte %.1f ms%s)" % [ms, skripte, (", teuerster Abschnitt " + teuerster) if teuerster != "" else ""]


## Neue Stufe oder neue Größe der Ansicht (zimmer_basis.gd _stufe_waehlen): Upscaler, Kantenglättung
## und Grenzen der Skala.
func einstellen(neu_stufe: String, neu_wahl: String, r: Dictionary) -> void:
	var neu := neu_stufe != stufe or r != rahmen
	stufe = neu_stufe
	wahl = neu_wahl
	rahmen = r
	_fps_wahl = str(Config.get_value("room.fps", "bildschirm"))
	if vp == null:
		return
	_anwenden(r)
	if neu:
		skala = startskala(r, Config.get_value("room.grafik_skala", {}), RenderingServer.get_video_adapter_name(), stufe, vp.size.y)
		_seit_wechsel = 0.0
		_leeren()
	_skala_setzen(skala)
	if not _messen and vp.is_inside_tree():
		_messen = true
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Upscaler und Kantenglättung des Rahmens r in die Ansicht.
func _anwenden(r: Dictionary) -> void:
	# FSR 1 zieht nur hoch, wenn die Skala unter 1 liegt (Sicherheitsnetz, Mittel und Leicht auf großen
	# Bildschirmen); Schärfe wie vorgegeben (0,2: schärfer machte den Putz körnig).
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if str(r.get("modus", "")) == "fsr" else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.2
	# SMAA glättet Kanten nach dem Bild (kostet kaum etwas, ohne zeitliches Verwischen); FXAA im schlanken
	# Weg (noch weniger, auf der kleineren 3D-Auflösung).
	vp.screen_space_aa = { "smaa": Viewport.SCREEN_SPACE_AA_SMAA, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA }.get(str(r.get("aa", "")),
			Viewport.SCREEN_SPACE_AA_DISABLED)


## Kompatibilität sparsam neben dem laufenden Spiel: Skala höchstens grenze (1 = aus).
func spar(an: bool, grenze := 1.0) -> void:
	spar_grenze = grenze if an else 1.0
	_skala_setzen(skala)


## Schlanker Weg neben dem laufenden Spiel (Forward+, jede Stufe gleich): Rahmen SCHLANK statt dem der
## Stufe, die Skala beginnt höchstens bei dessen Start und passt sich wie sonst an; aus: Rahmen und Skala
## der Stufe zurück.
func schlank_setzen(an: bool) -> void:
	if an == schlank or vp == null:
		return
	schlank = an
	if an:
		_rahmen_stufe = rahmen
		_skala_stufe = skala
		rahmen = SCHLANK.duplicate()
		skala = minf(skala, float(SCHLANK.start))
	else:
		rahmen = _rahmen_stufe
		skala = _skala_stufe
		_rahmen_stufe = {}
	_anwenden(rahmen)
	_seit_wechsel = 0.0
	_leeren()
	_skala_setzen(skala)


## Gilt gerade (Rahmen, Sparen): die Skala in die Ansicht.
func _skala_setzen(k: float) -> void:
	var hi := minf(float(rahmen.get("max", 1.0)), maxf(spar_grenze, float(rahmen.get("min", 1.0))))
	var lo := minf(float(rahmen.get("min", 1.0)), hi)
	skala = clampf(k, lo, hi)
	if vp and not halten and not is_equal_approx(vp.scaling_3d_scale, skala):
		vp.scaling_3d_scale = skala


## Upscaler und Kantenglättung als Text (launch.log, Anzeige): „MSAA 4× + SMAA“, „FSR 1 + MSAA 2×“, „FSR 1 + FXAA“ …
func upscaler_text() -> String:
	var modus := str(rahmen.get("modus", ""))
	var teile := PackedStringArray()
	if skala < 0.999:
		teile.append("FSR 1" if modus == "fsr" else "bilinear")
	if vp and vp.msaa_3d != Viewport.MSAA_DISABLED:
		teile.append("MSAA %d×" % int({ Viewport.MSAA_2X: 2, Viewport.MSAA_4X: 4, Viewport.MSAA_8X: 8 }.get(vp.msaa_3d, 2)))
	if str(rahmen.get("aa", "")) in ["smaa", "fxaa"]:
		teile.append(str(rahmen.aa).to_upper())
	return " + ".join(teile) if not teile.is_empty() else "ohne Kantenglättung"


## Jedes Bild, solange das Zimmer vorn liegt: die 3D-Ansicht wird jedes Bild neu gerechnet, die
## Bildrate gilt.
func vor_bild() -> void:
	if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rate_setzen()


## Zimmer liegt nicht vorn (Menü, Guide darüber): Bildrate zurück an main, Anzeige weg.
func hinten() -> void:
	_rate_zurueck()
	_anzeige_zeigen(false)


## Am Ende jedes Bilds: Zeit messen, Skala anpassen, berichten, Anzeige.
func nach_bild(dt: float) -> void:
	_seit_start += dt
	_seit_wechsel += dt
	if not _gemeldet and _seit_start >= 1.0:
		_gemeldet = true
		melden()
	_messen_bild(dt)
	_anzeige_s += dt
	if _anzeige_s >= ANZEIGE_S:
		_anzeige_s = 0.0
		_anzeige_zeigen(bool(Config.get_value("system.perf_corner", false)) and not halten)


func _messen_bild(dt: float) -> void:
	if not _messen or vp == null:
		return
	var g := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	if g > 0.0:
		_summe += g + RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_cpu_summe += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()) \
				+ RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) \
				+ RenderingServer.get_frame_setup_time_cpu()
		_n += 1
	_block += dt
	if _block < BLOCK_S or _n == 0:
		return
	gpu_ms = _summe / _n
	cpu_ms = _cpu_summe / _n
	if _ablauf_n > 0:
		ablauf_ms = _ablauf_summe / _ablauf_n
		abstand_ms = _abstand_summe / _ablauf_n
	if _skript_n > 0:
		skript_ms = _skript_summe / _skript_n
		_skript_summe = 0.0
		_skript_n = 0
	var ziel := ziel_ms(rate, spiel or schlank or spar_grenze < 0.999)
	_ueber = _ueber + _block if gpu_ms > ziel else 0.0
	_unter = _unter + _block if gpu_ms < ziel * RAUF_ANTEIL else 0.0
	if _seit_start > 2.0 and not spiel and not schlank:
		_lern_summe += gpu_ms
		_lern_n += 1
	_block = 0.0
	_summe = 0.0
	_cpu_summe = 0.0
	_ablauf_summe = 0.0
	_abstand_summe = 0.0
	_ablauf_n = 0
	_n = 0
	# Neben dem Spiel bleibt die Bildrate; kommt die Grafikkarte nicht nach, wird nur die
	# 3D-Auflösung kleiner.
	if dynamisch and not halten and _seit_wechsel >= WECHSEL_S and str(rahmen.get("modus", "")) != "bilinear":
		var neu := skala_schritt(skala, _ueber, _unter, float(rahmen.get("min", 1.0)),
				minf(float(rahmen.get("max", 1.0)), maxf(spar_grenze, float(rahmen.get("min", 1.0)))))
		if not is_equal_approx(neu, skala):
			var alt := skala
			_skala_setzen(neu)
			_seit_wechsel = 0.0
			_ueber = 0.0
			_unter = 0.0
			_zeile("Zimmer-Grafik: 3D-Auflösung %d %% → %d %% (Grafikkarte Ø %.1f ms, Ziel %.1f ms bei %d Bildern/s)"
					% [roundi(alt * 100.0), roundi(skala * 100.0), gpu_ms, ziel, rate])
	if not _bericht and _seit_start >= BERICHT_S:
		_bericht = true
		_zeile("Zimmer-Grafik nach %d s: %s" % [roundi(_seit_start), text_messung(ziel)])
		_ablauf_max = 0.0
		_ablauf_max_text = ""
	if not _gelernt and _seit_start >= LERNEN_S and _lern_n >= 8 and not spiel and not schlank and spar_grenze >= 0.999:
		_gelernt = true
		_skala_merken()
		if wahl == "auto":
			_lernen(_lern_summe / _lern_n, ziel)


## Die Skala, bei der es sich eingependelt hat, als Startwert fürs nächste Betreten (je Karte, Stufe, Höhe).
func _skala_merken() -> void:
	if not dynamisch or schlank or str(rahmen.get("modus", "")) == "bilinear" or vp == null:
		return
	Config.set_value("room.grafik_skala", { "karte": RenderingServer.get_video_adapter_name(), "stufe": stufe, "hoehe": vp.size.y,
		"skala": snappedf(skala, 0.01) })


## Automatisch: passt eine Stufe höher (bei größter Skala geschätzt noch viel Luft) oder muss eine
## tiefer (zu langsam bei kleinster)? Gilt ab dem nächsten Betreten.
func _lernen(ms: float, ziel: float) -> void:
	var neu := stufe
	var gross := float(rahmen.get("max", 1.0))
	# Zeit bei größter Skala geschätzt: wächst höchstens mit der Zahl der Bildpunkte.
	var bei_gross := ms * pow(gross / maxf(skala, 0.1), 2.0)
	var klein := skala <= float(rahmen.get("min", 1.0)) + 0.01
	if bei_gross < ziel * LERNEN_LUFT and not Leicht.active:
		neu = Licht.stufe_daneben(stufe, 1)
	elif klein and ms > ziel * 1.1:
		neu = Licht.stufe_daneben(stufe, -1)
	var karte := RenderingServer.get_video_adapter_name()
	var vorher: Variant = Config.get_value("room.grafik_auto", {})
	var war := str((vorher as Dictionary).get("stufe", "")) if vorher is Dictionary and str((vorher as Dictionary).get("karte", "")) == karte else ""
	if neu == stufe and war == "":
		Config.set_value("room.grafik_auto", { "karte": karte, "stufe": stufe, "ms": snappedf(ms, 0.1) })
		_zeile("Zimmer-Grafik automatisch: Stufe %s passt (Grafikkarte Ø %.1f ms, Ziel %.1f ms)" % [stufe, ms, ziel])
	elif neu != stufe:
		Config.set_value("room.grafik_auto", { "karte": karte, "stufe": neu, "ms": snappedf(ms, 0.1) })
		_zeile("Zimmer-Grafik automatisch: ab dem nächsten Betreten Stufe %s statt %s (Grafikkarte Ø %.1f ms bei %d %%, bei %d %% geschätzt %.1f ms, Ziel %.1f ms)"
				% [neu, stufe, ms, roundi(skala * 100.0), roundi(gross * 100.0), bei_gross, ziel])


## Bildrate setzen, solange das Zimmer vorn liegt. Engine.max_fps nur ändern, wenn dort noch steht, was
## main im Menü setzt oder was hier gesetzt wurde (Ruhe-Rate im Spiel, Mitteilungen: die gelten).
func _rate_setzen() -> void:
	var menu: int = int(menu_fps.call()) if menu_fps.is_valid() else 0
	rate = zielrate(_fps_wahl, hz, menu)
	# Gleich der Bildschirmrate: V-Sync begrenzt ohnehin (0 – ohne zusätzlichen Takt, der ruckeln kann).
	var soll := 0 if float(rate) >= hz - 0.5 else rate
	if Engine.max_fps == soll:
		_gesetzt = soll
		return
	if Engine.max_fps == _gesetzt or Engine.max_fps == menu:
		Engine.max_fps = soll
		_gesetzt = soll


## Bildrate zurück an main (nur, was hier gesetzt wurde und noch gilt).
func _rate_zurueck() -> void:
	if _gesetzt >= 0 and Engine.max_fps == _gesetzt:
		Engine.max_fps = int(menu_fps.call()) if menu_fps.is_valid() else 0
	_gesetzt = -1


## Bildrate im Zimmer neu gewählt (Config room.fps).
func fps_waehlen(w: String) -> void:
	_fps_wahl = w
	if _gesetzt >= 0:
		_rate_setzen()


## 3D-Auflösung in Bildpunkten, wie sie gerechnet wird.
func intern() -> Vector2i:
	return Vector2i((Vector2(vp.size) * skala).round()) if vp else Vector2i.ZERO


func _leeren() -> void:
	_summe = 0.0
	_cpu_summe = 0.0
	_ablauf_summe = 0.0
	_abstand_summe = 0.0
	_ablauf_n = 0
	_n = 0
	_block = 0.0
	_ueber = 0.0
	_unter = 0.0


func _zeile(t: String) -> void:
	if _zeilen >= MAX_ZEILEN:
		return
	_zeilen += 1
	Launcher.log_launch(t)


## Kurz nach dem Betreten (einmal, die Ansicht hat dann ihre echte Größe): was gilt.
func melden() -> void:
	_zeile("Zimmer-Grafik: " + text_jetzt())


## Was gilt, als Text (launch.log, Proben).
func text_jetzt() -> String:
	return "Stufe %s (Wahl %s), 3D %s von %s (%d %%, %s, Grenzen %d–%d %%), %s, Ziel %d Bilder/s (Wahl %s, Bildschirm %.0f Hz, Engine.max_fps %d), %s%s" \
			% [stufe, wahl, str(intern()), str(vp.size), roundi(skala * 100.0), upscaler_text(), roundi(float(rahmen.get("min", 1.0)) * 100.0),
			roundi(float(rahmen.get("max", 1.0)) * 100.0), _gi(), rate, _fps_wahl, hz, Engine.max_fps,
			"Skala nach Messung" if dynamisch and str(rahmen.get("modus", "")) != "bilinear" else "Skala fest",
			(", " + vorab_text) if vorab_text != "" else ""]


## Licht und Effekte als Text: wie die Stufe sie setzt, neben dem Spiel mit dem, was der schlanke Weg weglässt.
func _gi() -> String:
	var t := gi_text if gi_text != "" else "GI ?"
	return t + ("; schlanker Weg neben dem Spiel: ohne SSAO, SSR, Glühen, Nebel, Lichtstrahl und Lampenschatten auf Möbeln" if schlank else "")


## Was gemessen wurde, als Text (launch.log nach BERICHT_S, Proben). Prozessor: Skripte (alle _process
## eines Bilds, dazu die teuersten Abschnitte des Zimmers), Zeichnen (Befehle an die Grafikkarte) und der
## Ablauf je Bild (selbst gemessen: Skripte, Zeichnen und das Warten auf Grafikkarte und Bildschirm) –
## Mittel und der längste seit dem Betreten samt dem, was er kostete. Dazu die Möbel mit den meisten Netzen.
func text_messung(ziel: float) -> String:
	var rid := vp.get_viewport_rid()
	var info := func(art: int, was: int) -> int: return RenderingServer.viewport_get_render_info(rid, art, was)
	return "%.0f Bilder/s (Ziel %d), Grafikkarte Ø %.1f ms je Bild (Ziel %.1f ms), Prozessor: Skripte Ø %.2f ms (teuerste im Zimmer: %s), Zeichnen Ø %.2f ms, Ablauf je Bild Ø %.1f ms von %.1f ms Abstand (Rest: Physik, Ereignisse, Kappe), längster %s; 3D %s (%d %%, %s), Zeichenaufrufe Ansicht %d / Schatten %d, Primitive Ansicht %d / Schatten %d, %s%s; %s" \
			% [Engine.get_frames_per_second(), rate, gpu_ms, ziel, skript_ms, skript_text(3), cpu_ms, ablauf_ms, abstand_ms,
			_ablauf_max_text if _ablauf_max_text != "" else "–", str(intern()), roundi(skala * 100.0), upscaler_text(),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			_gi() + ((", " + str(licht_info.call())) if licht_info.is_valid() else ""),
			("; " + str(netze_info.call())) if netze_info.is_valid() else "", _pipelines_text()]


# --- Anzeige -----------------------------------------------------------------------------------------

## Kleine Anzeige oben links (wie „Leistung in der Ecke“ über dem Spiel): Bilder je Sekunde, Zeit der
## Grafikkarte und des Prozessors je Bild. Nicht im Fotomodus.
func _anzeige_zeigen(an: bool) -> void:
	if not an:
		if _anzeige:
			_anzeige.visible = false
		return
	if _anzeige == null:
		_anzeige = CanvasLayer.new()
		_anzeige.layer = 90
		add_child(_anzeige)
		var pille := PanelContainer.new()
		var sb := UzTheme.box(Color(UzTheme.col("surface_hi"), 0.82), 999, 1, UzTheme.col("stroke"))
		sb.content_margin_left = 18
		sb.content_margin_right = 20
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		pille.add_theme_stylebox_override("panel", sb)
		pille.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pille.name = "Pille"
		_anzeige.add_child(pille)
		_anzeige_zeile = U.hbox(16)
		pille.add_child(_anzeige_zeile)
	_anzeige.visible = true
	# Läuft ein Spiel, zeigt die Ecke (perf_corner.gd, eigenes Fenster) dort schon den PC: darunter.
	(_anzeige.get_node("Pille") as Control).position = Vector2(28, 104 if Launcher.in_game else 32)
	var teile := PerfLive.zimmer_parts(Engine.get_frames_per_second(), gpu_ms, skript_ms + cpu_ms)
	if _anzeige_zeile.get_child_count() != teile.size():
		U.clear(_anzeige_zeile)
		for t in teile:
			var paar := U.hbox(6)
			var k := U.label("", "s", "muted", "medium")
			k.clip_text = false
			paar.add_child(k)
			var v := U.label("", "s", "text", "ui_bold")
			v.clip_text = false
			v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			paar.add_child(v)
			_anzeige_zeile.add_child(paar)
	for i in teile.size():
		var paar := _anzeige_zeile.get_child(i)
		(paar.get_child(0) as Label).text = str(teile[i][0])
		(paar.get_child(0) as Label).visible = str(teile[i][0]) != ""
		(paar.get_child(1) as Label).text = str(teile[i][1])


func _exit_tree() -> void:
	_rate_zurueck()
	pipelines_zurueck()
	if RenderingServer.frame_post_draw.is_connected(_gezeichnet):
		RenderingServer.frame_post_draw.disconnect(_gezeichnet)
	if _messen:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
		if is_instance_valid(vp):
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), false)


## Läuft als letzter _process im Bild und sagt es der Leistung (Skriptzeit je Bild).
class _EndeSkript extends Node:
	func _process(_dt: float) -> void:
		var l := get_parent()
		if l and l.has_method("_skripte_ende"):
			l.call("_skripte_ende")

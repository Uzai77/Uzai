extends Node
## Was Uzai je Bild braucht, solange das Zimmer neben einem laufenden Spiel zeichnet – für launch.log,
## damit man am PC sieht, ob das Zimmer dem Spiel Zeit wegnimmt: Bilder je Sekunde, Bildzeit (Mittel,
## 95 %, längste – echte Abstände der Bilder, leistung.gd bild_ms), Ruckler, Zeit der Grafikkarte für das
## Fenster und das 3D-Zimmer (Zeitstempel der Engine, RenderingServer.viewport_set_measure_render_time),
## die Zeit des Prozessors fürs Zeichnen, der Ablauf je Bild (leistung.gd: erster _process bis nach dem
## Zeichnen, Mittel und der längste samt seinem teuersten Abschnitt) und (skripte) die Skripte allein.
## Gemessen wird nur, solange `lage` gesetzt ist (Spiel läuft, Zimmer vorn) und erst ANLAUF_S nach einem
## Wechsel – die Umstellung selbst (Aufstehen, Guide auf) ist kein Ruckler des Zimmers. Die erste Zeile
## kommt ERSTE_S nach dem Wechsel, danach höchstens alle ABSTAND_S, je Zimmer höchstens MAX_ZEILEN.

const ERSTE_S := 6.0
const ABSTAND_S := 60.0
const ANLAUF_S := 1.0
const MAX_ZEILEN := 12
const MAX_PROBEN := 4096

var lage := ""                       ## "" = nicht messen; sonst z. B. „aufgestanden“
var stufe_text := ""                 ## Grafik dazu (Stufe, schlanker Weg …)
var skripte: Callable                ## → String: Zeit der Skripte und die teuersten Abschnitte (leistung.gd)
var leistung: Node                   ## leistung.gd: echte Bildabstände und Ablauf je Bild
var _vp: Viewport
var _dts := PackedFloat32Array()
var _ablaeufe := PackedFloat32Array()
var _laengster := ""
var _laengster_ms := 0.0
var _gpu_fenster := 0.0
var _gpu_zimmer := 0.0
var _cpu_zeichnen := 0.0
var _n := 0
var _seit := 0.0
var _anlauf := ANLAUF_S
var _faellig := ERSTE_S
var _zeilen := 0
var _gemessen := false


## Das 3D-Zimmer (SubViewport) zusätzlich zum Fenster messen.
func zimmer(vp: Viewport) -> void:
	_vp = vp


## Neue Lage (oder "" = aus): Messung beginnt von vorn (nach ANLAUF_S), die erste Zeile kommt nach ERSTE_S.
func setzen(neu: String, stufe: String) -> void:
	stufe_text = stufe
	if neu == lage:
		return
	lage = neu
	_leeren()
	_anlauf = ANLAUF_S
	_faellig = ERSTE_S
	if lage != "" and not _gemessen:
		_gemessen = true
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		if _vp:
			RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)


func _leeren() -> void:
	_dts.clear()
	_ablaeufe.clear()
	_laengster = ""
	_laengster_ms = 0.0
	_gpu_fenster = 0.0
	_gpu_zimmer = 0.0
	_cpu_zeichnen = 0.0
	_n = 0
	_seit = 0.0


func _process(dt: float) -> void:
	if lage == "" or _zeilen >= MAX_ZEILEN:
		return
	if _anlauf > 0.0:
		_anlauf -= dt
		return
	# Werte des zuletzt gezeichneten Bilds (leistung.gd misst bis nach dem Zeichnen).
	var bild := float(leistung.get("bild_ms")) if leistung else 0.0
	var ablauf := float(leistung.get("ablauf_bild_ms")) if leistung else 0.0
	if _dts.size() < MAX_PROBEN:
		_dts.append(bild if bild > 0.0 else dt * 1000.0)
		if ablauf > 0.0:
			_ablaeufe.append(ablauf)
	if ablauf > _laengster_ms:
		_laengster_ms = ablauf
		_laengster = str(leistung.call("ablauf_text", ablauf, float(leistung.get("skript_bild_ms")), str(leistung.get("teuerster_bild"))))
	_gpu_fenster += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if _vp:
		_gpu_zimmer += RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())
	_cpu_zeichnen += RenderingServer.get_frame_setup_time_cpu()
	_n += 1
	_seit += dt
	if _seit < _faellig:
		return
	_zeilen += 1
	Launcher.log_launch("Zimmer neben dem Spiel (%s): %s%s" % [lage, zusammenfassung(_dts, _ablaeufe, _gpu_fenster / _n, _gpu_zimmer / _n,
			_cpu_zeichnen / _n, Engine.max_fps, _laengster) + (("; " + str(skripte.call())) if skripte.is_valid() else ""),
			(" · " + stufe_text) if stufe_text != "" else ""])
	_leeren()
	_faellig = ABSTAND_S


func _exit_tree() -> void:
	if _gemessen:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
		if is_instance_valid(_vp):
			RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), false)


## Eine Zeile aus den Bildzeiten und Abläufen je Bild (ms) und den Mitteln (ms). kappe: Engine.max_fps
## (0 = ohne); laengster: der längste Ablauf als Text (leistung.gd ablauf_text). Ruckler: Bilder, die
## mehr als 1,6-mal so lange standen wie geplant (1000 / Kappe, ohne Kappe das Mittel).
static func zusammenfassung(dts: PackedFloat32Array, ablaeufe: PackedFloat32Array, gpu_fenster: float, gpu_zimmer: float, cpu: float,
		kappe: int, laengster := "") -> String:
	if dts.is_empty():
		return "keine Bilder"
	var s := dts.duplicate()
	s.sort()
	var summe := 0.0
	for d in s:
		summe += d
	var mittel := summe / s.size()
	var p95: float = s[clampi(ceili(s.size() * 0.95) - 1, 0, s.size() - 1)]
	var fps := 1000.0 / maxf(0.001, mittel)
	var t := "%.0f Bilder/s%s, Bildzeit Ø %.1f ms, 95 %% ≤ %.1f ms, längste %.1f ms" % [fps, (" (Kappe %d)" % kappe) if kappe > 0 else "",
			mittel, p95, s[s.size() - 1]]
	var soll := 1000.0 / float(kappe) if kappe > 0 else mittel
	var ruck := 0
	for d in s:
		if d > soll * 1.6:
			ruck += 1
	t += "; Ruckler (Bild > 1,6 × %.1f ms) %d von %d" % [soll, ruck, s.size()]
	t += "; Grafikkarte Ø %.1f ms (davon 3D-Zimmer %.1f ms)" % [gpu_fenster + gpu_zimmer, gpu_zimmer]
	var ab := 0.0
	for a in ablaeufe:
		ab += a
	t += "; Prozessor: Zeichnen Ø %.1f ms, Ablauf je Bild Ø %.1f ms, längster %s" % [cpu, ab / maxf(1.0, float(ablaeufe.size())),
			laengster if laengster != "" else "–"]
	return t

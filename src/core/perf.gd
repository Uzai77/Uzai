extends Node
## Leistungsziele (Punkt 88): Uzai misst sich selbst – wie schnell es bedienbar ist, wie viel
## Arbeitsspeicher es samt Helfern braucht, wie viel Rechenzeit es neben einem Spiel kostet und ob
## das Menü flüssig läuft. Die Werte stehen unter Einstellungen → System → Leistung, je Sitzung und
## je Spiel eine Zeile in logs/leistung.log. Nichts verlässt den PC.
##
## Speicher und Rechenzeit fragt Uzai alle SAMPLE_S Sekunden beim Helfer ab (Windows zählt sie je
## Prozess). Die Bildzeiten im Menü kosten nichts: nur die Zeit zwischen zwei Bildern, solange das
## Menü sichtbar und nicht im Sparmodus ist.

const Lang := preload("res://src/core/lang.gd")
const Leicht := preload("res://src/core/leicht.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const PerfCorner := preload("res://src/ui/perf_corner.gd")
const Raster := preload("res://src/core/raster.gd")

const GOAL_START_MS := 3000
const GOAL_MEM_MB := 300.0
const GOAL_GAME_CPU := 1.0        ## % der ganzen CPU – „fast 0 %“
const GOAL_HITCH_PCT := 1.0       ## so viele Bilder im Menü dürfen zu spät kommen
const SAMPLE_S := 30.0
const FRAMES := 4096              ## Bildzeiten im Menü (gut eine Minute bei 60 Hz)
const LATE := 1.6                 ## ein Bild ist zu spät, wenn es so viele Bildwechsel brauchte
const GAME_SETTLE_S := 20.0

const Main := preload("res://src/main.gd")
var main: Main
var start_ms := -1                ## bis die Startseite bedienbar und zu sehen war (mit Startanimation)
var mem_mb := -1.0                ## Uzai und Helfer, zuletzt gemessen
var mem_uzai_mb := -1.0           ## davon Uzai selbst
var mem_peak_mb := -1.0
var game_cpu := -1.0              ## zuletzt gemessen, während ein Spiel lief
var game_name := ""

var _ft := PackedFloat32Array()
var _ft_i := 0
var _prev_us := 0
var _last: Dictionary = {}        ## letzte Messung { cpu_ms, wall_ms, in_game, cores }
var _game: Dictionary = {}        ## laufendes Spiel { cpu_ms, wall_ms } zu Beginn
var _sampling := false
var _corner: Window                ## Leistung in der Ecke über dem Spiel (src/ui/perf_corner.gd)


func _ready() -> void:
	_ft.resize(FRAMES)
	_ft.fill(-1.0)
	var t := Timer.new()
	t.wait_time = SAMPLE_S
	t.autostart = true
	t.timeout.connect(sample)
	add_child(t)
	Launcher.started.connect(func(g: Dictionary) -> void:
		game_name = Library.display_title(g)
		_game = {}
		game_cpu = -1.0
		# Erst messen, wenn der Start (Abdunkeln, Uzai parken) vorbei ist.
		get_tree().create_timer(GAME_SETTLE_S).timeout.connect(sample)
	)
	Launcher.ended.connect(func(_g: Dictionary, _s: int) -> void:
		_end_game()
		_corner_check()
		# Im Guide umgeschaltetes Energieprofil zurückstellen (src/core/perf_live.gd).
		PerfLive.restore_plan()
	)
	Config.changed.connect(func(key: String) -> void:
		if key == "system.perf_corner":
			_corner_check()
	)


## main: die Startseite ist bedienbar (Startanimation vorbei); gezählt wird bis zu ihrem Bild.
## phasen: main.startphase – wann main, Oberfläche, Startseite und Animation fertig waren.
func booted(phasen: Array = []) -> void:
	if start_ms >= 0:
		return
	await RenderingServer.frame_post_draw
	start_ms = Time.get_ticks_msec()
	Media.log_line("leistung", startphasen_text(Config.autoload_ms, phasen, start_ms))
	Media.log_line("leistung", dienste_text(Config.autoload_ms, Config.autoload_fertig_ms))
	get_tree().create_timer(3.0).timeout.connect(sample)
	# Eine Minute nach dem Start: wofür der Speicher gebraucht wird (Uzai, Helfer, Bilder, Objekte).
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		await sample()
		Media.log_line("leistung", speicher_text()))
	# How smoothly the menu runs on this PC (to diagnose stutter and refresh-rate problems): one line every
	# TAKT_S while enough menu frames have been counted, at most TAKT_MAX per session.
	var takt := Timer.new()
	takt.wait_time = TAKT_S
	takt.autostart = true
	takt.timeout.connect(_takt_zeile)
	add_child(takt)
	# Nach einem Absturz mitten im Spiel: das Energieprofil von vorher wiederherstellen.
	if not Launcher.in_game and str(Config.get_value("system.power_restore", "")) != "":
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			if not Launcher.in_game:
				PerfLive.restore_plan()
		)


func _process(_dt: float) -> void:
	# Ecke: nur im Spiel bei geschlossenem Guide (der Guide sagt es nicht, darum kurz nachsehen).
	if Engine.get_process_frames() % 6 == 0 and (Launcher.in_game or is_instance_valid(_corner)):
		_corner_check()
	var now := Time.get_ticks_usec()
	if not _counting():
		_prev_us = 0
		return
	if _prev_us > 0:
		_ft[_ft_i] = (now - _prev_us) / 1000.0
		_ft_i = (_ft_i + 1) % FRAMES
	_prev_us = now


const TAKT_S := 150.0
const TAKT_MAX := 8
const TAKT_MIN_BILDER := 600
var _takt_n := 0


func _takt_zeile() -> void:
	if _takt_n >= TAKT_MAX:
		return
	var m := menu_stats()
	if int(m.frames) < TAKT_MIN_BILDER:
		return
	_takt_n += 1
	Media.log_line("leistung", "Bildtakt: %d Bilder/s bei %s (Grenze %s), %s zu spät, 99 %% unter %.1f ms, %d Bilder; Treiber %s, %s; %s, Skala %.2f, Raster %.2f, Einrasten %s; V-Sync %d; leichter Modus %s; Bildschirme: %s" % bildtakt_werte(m))
	reset_frames()


## Werte für die Zeile „Bildtakt“: Bilder je Sekunde im Menü gegen die Rate des Bildschirms, Anteil zu später Bilder, was die Rate
## begrenzt, Treiber, Fenster, Skala und Raster, alle Bildschirme. Nichts Persönliches (keine Namen, keine Pfade).
func bildtakt_werte(m: Dictionary) -> Array:
	var w := get_window()
	var hier := w.current_screen if w else 0
	var schirme := PackedStringArray()
	for i in DisplayServer.get_screen_count():
		var gr := DisplayServer.screen_get_size(i)
		schirme.append("%d×%d %s%s" % [gr.x, gr.y, _hz_text(DisplayServer.screen_get_refresh_rate(i)), " (Uzai)" if i == hier else ""])
	var modi := { Window.MODE_WINDOWED: "Fenster", Window.MODE_MAXIMIZED: "maximiert", Window.MODE_FULLSCREEN: "Vollbild",
		Window.MODE_EXCLUSIVE_FULLSCREEN: "exklusives Vollbild", Window.MODE_MINIMIZED: "minimiert" }
	return [
		roundi(float(m.fps)), _hz_text(DisplayServer.screen_get_refresh_rate(hier)), str(Engine.max_fps) if Engine.max_fps > 0 else "keine",
		pct_text(float(m.late_pct)), float(m.p99_ms), int(m.frames), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), str(modi.get(w.mode if w else -1, "?")), Raster.skala, Raster.schritt,
		"an" if w and w.snap_2d_transforms_to_pixel else "aus", DisplayServer.window_get_vsync_mode(), "an" if Leicht.active else "aus",
		", ".join(schirme)]


static func _hz_text(hz: float) -> String:
	return "%.0f Hz" % hz if hz > 1.0 else "? Hz"


## Leistung in der Ecke zeigen oder verstecken (Einstellung „In der Ecke anzeigen“).
func _corner_check() -> void:
	var want := Launcher.in_game and not Launcher.guide_open and bool(Config.get_value("system.perf_corner", false)) \
		and (Config.is_windows() or Library.demo)
	if want:
		if not is_instance_valid(_corner):
			_corner = PerfCorner.new()
			add_child(_corner)
		_corner.call("appear")
	elif is_instance_valid(_corner):
		_corner.call("disappear")
		# Spiel vorbei: das Fenster ganz weg (bis zum nächsten).
		if not Launcher.in_game:
			_corner.queue_free()
			_corner = null


## Bildzeiten neu sammeln (der leichte Modus wurde umgeschaltet: ab jetzt zählt der neue Stand).
func reset_frames() -> void:
	_ft.fill(-1.0)
	_ft_i = 0
	_prev_us = 0


## Nur das sichtbare Menü in voller Bildrate zählt (nicht im Spiel, nicht im Sparmodus, nicht
## im ruhenden Menü des leichten Modus).
func _counting() -> bool:
	if OS.low_processor_usage_mode or Leicht.idle or Launcher.in_game or start_ms < 0:
		return false
	var w := get_window()
	return w.visible and w.mode != Window.MODE_MINIMIZED


## Speicher und Rechenzeit beim Helfer abfragen.
func sample() -> void:
	if _sampling or not Helper.available:
		return
	_sampling = true
	var r: Dictionary = await Helper.run("usage", { "pids": [OS.get_process_id()] + Helper.pids() })
	_sampling = false
	if not bool(r.get("ok", false)):
		return
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	var mem := 0.0
	var cpu := 0.0
	for p in res.get("procs", []):
		if p is Dictionary:
			mem += float(p.get("mem", 0)) / 1048576.0
			cpu += float(p.get("cpu", 0))
			if int(p.get("pid", 0)) == OS.get_process_id():
				mem_uzai_mb = float(p.get("mem", 0)) / 1048576.0
	if mem <= 0.0:
		return
	mem_mb = mem
	mem_peak_mb = maxf(mem_peak_mb, mem)
	var cur := { "cpu_ms": cpu, "wall_ms": float(Time.get_ticks_msec()), "in_game": Launcher.in_game, "cores": maxi(1, int(res.get("cores", 1))) }
	if Launcher.in_game:
		if _game.is_empty():
			_game = cur
		else:
			game_cpu = cpu_percent(float(_game.cpu_ms), cpu, float(cur.wall_ms) - float(_game.wall_ms), int(cur.cores))
	_last = cur


func _end_game() -> void:
	if game_cpu >= 0.0 and not _game.is_empty():
		var mins := (float(_last.get("wall_ms", 0)) - float(_game.wall_ms)) / 60000.0
		Media.log_line("leistung", "Spiel %s: Uzai %s CPU über %d min" % [game_name, pct_text(game_cpu), int(mins)])
	_game = {}


## Rein: Zeile „Startphasen“ – wo die Zeit bis zur bedienbaren Startseite blieb. autoloads: [[Name, ms]] in der
## Reihenfolge des Starts (Config.autoload_ms, zuletzt „main“), phasen: [[Name, ms]] aus main, ende: Startseite zu sehen.
static func startphasen_text(autoloads: Array, phasen: Array, ende: int) -> String:
	var teile := PackedStringArray()
	var dienste: Array = []          # [ms, Name]
	for i in range(autoloads.size() - 1):
		dienste.append([int(autoloads[i + 1][1]) - int(autoloads[i][1]), str(autoloads[i][0])])
	var erst := int(autoloads[0][1]) if not autoloads.is_empty() else 0
	var main_ms := int(autoloads.back()[1]) if not autoloads.is_empty() else 0
	teile.append("Godot %d ms" % erst)
	if not dienste.is_empty():
		dienste.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
		var teuer := PackedStringArray()
		for d in dienste.slice(0, 5):
			teuer.append("%s %d" % [d[1], d[0]])
		teile.append("Dienste %d ms (%s)" % [main_ms - erst, ", ".join(teuer)])
	var vorher := main_ms
	for p in phasen:
		if str(p[0]) == "main":
			vorher = int(p[1])
			continue
		teile.append("%s %d ms" % [str(p[0]).capitalize(), int(p[1]) - vorher])
		vorher = int(p[1])
	teile.append("bis zum Bild %d ms" % (ende - vorher))
	return "Startphasen (%s): %s – zusammen %s" % [Config.VERSION, " · ".join(teile), secs_text(ende)]


## Rein: Zeile „Grunddienste“ – was das _ready jedes Grunddiensts gekostet hat (Abstand zum vorigen fertigen), die
## teuersten zuerst. angekommen: Config.autoload_ms (der letzte Eintrag vor „main“ ist der Beginn), fertig:
## Config.autoload_fertig_ms in Aufrufreihenfolge.
static func dienste_text(angekommen: Array, fertig: Array) -> String:
	var beginn := 0
	for a in angekommen:
		if str(a[0]) != "main" and str(a[0]) != "Main":
			beginn = maxi(beginn, int(a[1]))
	var dauer: Array = []
	var vorher := beginn
	for f in fertig:
		dauer.append([int(f[1]) - vorher, str(f[0])])
		vorher = int(f[1])
	var summe := vorher - beginn
	dauer.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var teile := PackedStringArray()
	for d in dauer.slice(0, 10):
		teile.append("%s %d" % [d[1], d[0]])
	return "Grunddienste (%s): Config erzeugt bei %d ms, _ready zusammen %d ms – %s" % [Config.VERSION, int(Config.erzeugt_ms), summe,
		", ".join(teile)]


## Zeile „Speicher“: Uzai und Helfer, in Uzai die Daten der Skripte, Bilder und Objekte (Godot zählt mit).
func speicher_text() -> String:
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var vid := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var stat := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	return "Speicher (%s): zusammen %s, Uzai selbst %s, Helfer %s · in Uzai: Daten %s, Bilder %s (Grafik gesamt %s), %d Objekte, %d Knoten, %d Ressourcen" % [
		Config.VERSION, mb_text(mem_mb), mb_text(mem_uzai_mb), mb_text(mem_mb - mem_uzai_mb if mem_mb >= 0.0 and mem_uzai_mb >= 0.0 else -1.0),
		mb_text(stat), mb_text(tex), mb_text(vid), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))]


## Zeile für logs/leistung.log (main beim Beenden).
func log_session() -> void:
	var m := menu_stats()
	Media.log_line("leistung", "Sitzung %s: Start %s, Speicher %s (Spitze %s), Menü %s zu spät (%d Bilder, %d Bilder/s%s)%s" % [
		Config.VERSION, secs_text(start_ms), mb_text(mem_mb), mb_text(mem_peak_mb), pct_text(float(m.late_pct)), int(m.frames), roundi(float(m.fps)),
		", leichter Modus" if Leicht.active else "", (", im Spiel " + pct_text(game_cpu) + " CPU") if game_cpu >= 0.0 else ""])


func menu_stats() -> Dictionary:
	return frame_stats(_ft, refresh_ms())


static func refresh_ms() -> float:
	var hz := DisplayServer.screen_get_refresh_rate()
	if not (hz > 1.0):     # unbekannt (auch NaN): wie 60 Hz
		hz = 60.0
	# Gedrosselt (display_fit.gd: halbe Rate über 144 Hz): ein Bild je Drosselschritt ist pünktlich.
	if Engine.max_fps > 0 and Engine.max_fps < hz:
		hz = Engine.max_fps
	return 1000.0 / hz


# --- Rechnen (ohne Fenster, getestet in tests/logic_leistung.gd) -------------------------------

## Rechenzeit in % der ganzen CPU (wie der Task-Manager): verbrauchte Zeit aller Kerne durch
## verstrichene Zeit mal Kerne.
static func cpu_percent(cpu0_ms: float, cpu1_ms: float, wall_ms: float, cores: int) -> float:
	if wall_ms <= 0.0 or cores <= 0:
		return -1.0
	return clampf((cpu1_ms - cpu0_ms) / (wall_ms * cores) * 100.0, 0.0, 100.0)


## Bildzeiten (ms, -1 = leer): Anzahl, Anteil zu spät, 99. Perzentil, Bilder je Sekunde.
static func frame_stats(times: PackedFloat32Array, interval_ms: float) -> Dictionary:
	var v := PackedFloat32Array()
	for t in times:
		if t > 0.0:
			v.append(t)
	if v.is_empty():
		return { "frames": 0, "late": 0, "late_pct": 0.0, "p99_ms": 0.0, "fps": 0.0 }
	v.sort()
	var late := 0
	var sum := 0.0
	for t in v:
		sum += t
		if t > interval_ms * LATE:
			late += 1
	return {
		"frames": v.size(),
		"late": late,
		"late_pct": late * 100.0 / v.size(),
		"p99_ms": v[mini(v.size() - 1, int(ceil(v.size() * 0.99)) - 1)],
		"fps": 1000.0 / (sum / v.size()),
	}


## Zeilen für die Einstellungen: [Titel, Wert, Beschreibung, im Ziel (true/false/null = unbekannt),
## eigenes Symbol (nur die Zeile „Leichter Modus“)].
static func rows(p: Dictionary) -> Array:
	var out: Array = []
	var st := int(p.get("start_ms", -1))
	out.append(["Start", secs_text(st), "Bis die Startseite bedienbar war, mit Startanimation. Ziel: unter %s." % secs_text(GOAL_START_MS),
		null if st < 0 else st <= GOAL_START_MS])
	var mem := float(p.get("mem_mb", -1.0))
	out.append(
			["Arbeitsspeicher", mb_text(mem),
			"Uzai mit seinen Helfern (Uzai selbst %s), Spitze in dieser Sitzung %s. Ziel: unter %s." % [mb_text(float(p.get("mem_uzai_mb", -1.0))),
			mb_text(float(p.get("mem_peak_mb", -1.0))), mb_text(GOAL_MEM_MB)],
		null if mem < 0.0 else mem <= GOAL_MEM_MB])
	var gc := float(p.get("game_cpu", -1.0))
	out.append(
			["Rechenzeit im Spiel", pct_text(gc),
			"Was Uzai neben dem Spiel braucht, gemessen beim letzten Spiel dieser Sitzung. Ziel: fast nichts (unter %s)." % pct_text(GOAL_GAME_CPU),
		null if gc < 0.0 else gc <= GOAL_GAME_CPU])
	var m: Dictionary = p.get("menu", {})
	var n := int(m.get("frames", 0))
	# Erst übersetzen, dann füllen: „0.0 %“ im Wert ließ die Übersetzung des fertigen Texts nur halb greifen.
	out.append(["Menü", (TranslationServer.translate("%d Bilder/s · %s zu spät") % [roundi(float(m.fps)), pct_text(float(m.late_pct))]) if n > 0 else "Noch nicht gemessen",
		"Wie flüssig das Menü lief: Anteil der Bilder, die mindestens einen Bildwechsel zu spät kamen (die langsamsten 1 %% brauchten %d ms). Ziel: unter %s." % [
			roundi(float(m.get("p99_ms", 0.0))), pct_text(GOAL_HITCH_PCT)],
		null if n < 120 else float(m.late_pct) <= GOAL_HITCH_PCT])
	if p.has("light"):
		var lv := str(p.light)
		for md in Leicht.MODES:
			if md[0] == lv:
				lv = str(md[1])
		out.append(["Leichter Modus", lv, "Einfachere Effekte und höchstens 60 Bilder/s im Menü (Einstellungen → Aussehen). Nach dem Umschalten misst Uzai das Menü neu – so lässt sich vorher und nachher vergleichen.", null, "speed"])
	return out


static func secs_text(ms: int) -> String:
	return "–" if ms < 0 else Lang.dec("%.1f s" % (ms / 1000.0))


static func mb_text(mb: float) -> String:
	return "–" if mb < 0.0 else "%d MB" % roundi(mb)


static func pct_text(p: float) -> String:
	return "–" if p < 0.0 else Lang.dec("%.1f %%" % p)

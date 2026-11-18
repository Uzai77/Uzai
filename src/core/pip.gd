extends Node
## Bild in Bild: Das Video (YouTube, Filme, Streams – alles, was über Video und mpv läuft) spielt
## in einem kleinen Fenster in einer Ecke weiter, während Uzai oder ein Spiel davor liegt.
##
## Rein: im Player ≡ (Start/Options) oder Optionen → „Bild in Bild“. Das Bild schrumpft weich in
## die Ecke (Standard unten rechts, Mittel = 28 % der Bildschirmbreite, 16:9), dahinter steht Uzai
## wieder dort, wo du vor dem Video warst – du kannst ein Spiel starten. Im Spiel liegt das Fenster
## über dem Spiel, ohne ihm je den Fokus zu nehmen.
##
## Das Fenster ist mpvs eigenes. Der Helfer (UzPip in helper/uzai-helper.ps1) macht es zu einem
## Werkzeugfenster ohne Fokus (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW: nicht in Taskleiste und
## Alt+Tab), rundet unter Windows 11 die Ecken, bewegt es mit SetWindowPos ohne Aktivieren und
## lässt die Größe in einem eigenen Faden weich gleiten. Mit der Maus lässt es sich ziehen (mpv).
##
## Steuern geht über den Guide (im Spiel gehört der Controller dem Spiel): Solange Bild in Bild
## läuft, öffnet die Guide-Taste den Guide gleich im Reiter „Bild in Bild“ (erster Reiter, wie
## „Video“ beim Vollbild) – vorn Vollbild (ohne Spiel), Pause und Schließen, darunter ±10 s,
## Verschieben (linker Stick, LT/RT Größe, A fertig, B zurück), Größe, Ecke, Deckkraft und die
## Lautstärke (LT/RT; so laut wie im Vollbild, außer die eigene Stufe ist eingeschaltet, siehe
## Video.volume_level). Freunde, Chat und der Rest des Guides bleiben einen Reiter weiter. Lage,
## Größe und Deckkraft merkt sich Uzai (pip.*).
##
## Lage (lage): "oben" – über Uzai und dem Spiel aus Uzai; "unter" – direkt unter Uzai, solange der
## Guide offen ist (der Guide bleibt bedienbar, über dem Spiel scheint das Bild gedimmt durch);
## "weg" – versteckt im Ruhemodus; "fremd" – versteckt, solange ein anderes Programm oder der
## Desktop vorn liegt (Alt+Tab): Bild in Bild ist nur über Uzai und dem Spiel „immer oben“ und
## kommt zurück, sobald eins von beiden wieder vorn ist (Nachsehen über den Helfer, solange Uzai
## selbst keinen Fokus hat; unser_vorn). Spiel beendet: das Bild bleibt. Ausschalten schließt es. Clips und
## Bildschirmfotos zeigen den Bildschirm, wie du ihn siehst (also mit Bild in Bild). Exklusives
## Vollbild kann kein Fenster überdecken: Uzai erkennt es (SHQueryUserNotificationState) und rät
## ruhig zum randlosen Vollbild-Fenster. Mehrere Bildschirme: das Bild zieht auf den des Spiels.
##
## Ohne Windows oder ohne mpv (Demo, Proben) zeichnet Uzai eine Vorschau mit dem Bild des Videos
## an derselben Stelle – mit derselben Rechnung und demselben Ablauf.

signal changed

const VideoCard := preload("res://src/ui/components/video_card.gd")
const U := preload("res://src/ui/u.gd")

## Breite je Größe als Anteil am Arbeitsbereich (Bildschirm ohne Taskleiste), Höhe 16:9.
const SIZES := { "s": 0.2, "m": 0.28, "l": 0.38 }
const SIZE_ORDER := ["s", "m", "l"]
const SIZE_NAMES := { "s": "Klein", "m": "Mittel", "l": "Groß" }
const OPACITY := [100, 85, 70]
## Ecken als Lage im freien Platz: 0,0 oben links … 1,1 unten rechts.
const CORNERS := { "oben_links": Vector2(0, 0), "oben_rechts": Vector2(1, 0), "unten_links": Vector2(0, 1), "unten_rechts": Vector2(1, 1) }
const CORNER_NAMES := { "oben_links": "Oben links", "oben_rechts": "Oben rechts", "unten_links": "Unten links", "unten_rechts": "Unten rechts", "frei": "Frei" }
const MARGIN := 28.0           ## Abstand zum Rand bei 100 % Skalierung
const MIN_W := 320.0           ## nie schmaler (bei 100 %)
const ENTER_MS := 340          ## Schrumpfen in die Ecke
const MOVE_MS := 180           ## Größe, Ecke, Einrasten
const FOLLOW_MS := 60          ## Verschieben mit dem Stick: weich hinterher
const MOVE_SPEED := 1500.0     ## Pixel pro Sekunde bei vollem Ausschlag (100 %)
const DEADZONE := 0.2
const SNAP := 0.07             ## so nah an einem Rand (Anteil des freien Platzes) rastet es ein
const FRONT_S := 0.6           ## so oft nachsehen, wer vorn liegt (nur ohne Fokus bei Uzai)
const FREMD_N := 2             ## so oft hintereinander ein fremdes Programm vorn, dann versteckt
const QUNS_D3D_FULLSCREEN := 3 ## SHQueryUserNotificationState: exklusives Direct3D-Vollbild
const Zustand := preload("res://src/core/zustand.gd")
## Bild in Bild (Wechsel nur über step()): aus, an oder gerade verschieben.
const ZUSTAENDE_MODUS := { "aus": ["an"], "an": ["aus", "bewegen"], "bewegen": ["an", "aus"] }
## Lage des Bilds: über Uzai und dem Spiel, unter dem offenen Guide, versteckt im Ruhemodus oder
## solange ein fremdes Programm vorn liegt; aus heißt wieder oben.
const ZUSTAENDE_LAGE := { "*": ["oben"], "oben": ["unter", "weg", "fremd"], "unter": ["weg"], "weg": ["unter"], "fremd": ["unter", "weg"] }

## Offen getypt (Node statt Main): Tests betreiben Bild in Bild mit einer Attrappe (logic_bild_in_bild).
var main: Node
var mode := "aus":             ## "aus", "an", "bewegen"
	set(neu):
		Zustand.wechsel("bildinbild.modus", ZUSTAENDE_MODUS, mode, neu)
		mode = neu
var lage := "oben":            ## "oben", "unter", "weg", "fremd"
	set(neu):
		Zustand.wechsel("bildinbild.lage", ZUSTAENDE_LAGE, lage, neu)
		lage = neu
var exclusive := false         ## das laufende Spiel scheint exklusiv im Vollbild zu laufen
var work := Rect2i(0, 0, 1920, 1080)   ## Arbeitsbereich des Bildschirms (physische Pixel)
var mon := Rect2i(0, 0, 1920, 1080)
var scale := 1.0
var _hwnd := 0
var _pid := 0
var _guide_on := false
var _rest_on := false
var _raise_t := 0.0
var _push_t := 0.0
var _push := false
var _move_from := Vector2.ONE
var _move_size := "m"
var _hint_gid := ""
var _sim: Control
var _busy := false
var _front_t := 0.0
var _front_busy := false
var _fremd_n := 0
var _spiel := { "id": "", "pids": [] }   ## Prozesse des laufenden Spiels (einmal je Spiel geholt)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Video.stopped.connect(_on_stopped)
	Video.started.connect(_on_started)
	Video.reached_end.connect(_on_end)
	Launcher.window_ready.connect(func(_g: Dictionary) -> void:
		_spiel.id = ""
		_event("spiel_fenster"))
	Launcher.ended.connect(func(_g: Dictionary, _s: int) -> void:
		exclusive = false
		_event("spiel_ende"))


# --- Rechnen (ohne Fenster, getestet in tests/logic_bild_in_bild.gd) --------------------------

## Skalierung aus den DPI des Bildschirms (96 = 100 %).
static func dpi_scale(dpi: int) -> float:
	return clampf(float(dpi) / 96.0, 1.0, 4.0) if dpi > 0 else 1.0


## Größe des Bildes im Arbeitsbereich: Anteil der Breite, 16:9, nie kleiner als MIN_W und nie
## größer als der Platz (Hochkant-Bildschirme).
static func size_for(area: Rect2i, key: String, s := 1.0) -> Vector2i:
	var m := MARGIN * s
	var w := maxf(float(area.size.x) * float(SIZES.get(key, SIZES.m)), MIN_W * s)
	w = minf(w, float(area.size.x) - 2.0 * m)
	var h := w * 9.0 / 16.0
	if h > float(area.size.y) - 2.0 * m:
		h = float(area.size.y) - 2.0 * m
		w = h * 16.0 / 9.0
	return Vector2i(maxi(16, roundi(w)), maxi(9, roundi(h)))


## Rechteck an der Lage f (0…1 im freien Platz, mit Rand).
static func place(area: Rect2i, f: Vector2, sz: Vector2i, s := 1.0) -> Rect2i:
	var m := roundi(MARGIN * s)
	var free := free_space(area, sz, s)
	var fx := clampf(f.x, 0.0, 1.0)
	var fy := clampf(f.y, 0.0, 1.0)
	return Rect2i(area.position + Vector2i(m + roundi(free.x * fx), m + roundi(free.y * fy)), sz)


## Umkehrung von place: wo im freien Platz liegt ein Rechteck (z. B. mit der Maus verschoben)?
static func fractions(area: Rect2i, r: Rect2i, s := 1.0) -> Vector2:
	var m := roundi(MARGIN * s)
	var free := free_space(area, r.size, s)
	var off := Vector2(r.position - area.position - Vector2i(m, m))
	return Vector2(clampf(off.x / free.x, 0.0, 1.0) if free.x > 0.0 else 0.5, clampf(off.y / free.y, 0.0, 1.0) if free.y > 0.0 else 0.5)


## Ganz im Arbeitsbereich halten (nie halb aus dem Bild).
static func clamp_rect(r: Rect2i, area: Rect2i) -> Rect2i:
	var sz := Vector2i(mini(r.size.x, area.size.x), mini(r.size.y, area.size.y))
	var p := Vector2i(clampi(r.position.x, area.position.x, area.end.x - sz.x), clampi(r.position.y, area.position.y, area.end.y - sz.y))
	return Rect2i(p, sz)


## Nah am Rand: ganz an den Rand (Ecken rasten so von selbst ein).
static func snap(f: Vector2, dist := SNAP) -> Vector2:
	var out := f
	for i in 2:
		if out[i] < dist:
			out[i] = 0.0
		elif out[i] > 1.0 - dist:
			out[i] = 1.0
	return out


## Name der Ecke ("unten_rechts" …) oder "frei".
static func corner_of(f: Vector2) -> String:
	for k in CORNERS.keys():
		if (CORNERS[k] as Vector2).is_equal_approx(f):
			return str(k)
	return "frei"


static func step_size(key: String, d: int) -> String:
	var i := SIZE_ORDER.find(key)
	if i < 0:
		i = 1
	return str(SIZE_ORDER[clampi(i + d, 0, SIZE_ORDER.size() - 1)])


static func next_opacity(cur: int) -> int:
	var i := OPACITY.find(cur)
	return int(OPACITY[(i + 1) % OPACITY.size()]) if i >= 0 else 100


## Stick → Schritt in der Lage (0…1): Totzone, weiche Kurve, Pixel pro Sekunde × Skalierung.
static func stick_delta(axis: Vector2, dt: float, free: Vector2, s := 1.0) -> Vector2:
	var l := axis.length()
	if l < DEADZONE:
		return Vector2.ZERO
	var k := clampf((l - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	var px := axis / l * pow(k, 1.6) * MOVE_SPEED * s * dt
	return Vector2(px.x / free.x if free.x > 0.0 else 0.0, px.y / free.y if free.y > 0.0 else 0.0)


## Freier Platz (Pixel), in dem sich das Bild bewegt.
static func free_space(area: Rect2i, sz: Vector2i, s := 1.0) -> Vector2:
	var m := roundi(MARGIN * s)
	return Vector2(maxi(0, area.size.x - 2 * m - sz.x), maxi(0, area.size.y - 2 * m - sz.y))


## Ablauf: aus dem Zustand { mode, lage, guide } und einem Ereignis den neuen Zustand und was zu
## tun ist. Ereignisse: an (aus dem Player), start (gleich als Bild in Bild), vollbild, schliessen,
## ausschalten, gestoppt, guide_auf, guide_zu, bewegen, bewegen_fertig, bewegen_zurueck, ruhe,
## wach, spiel_fenster, spiel_ende, fremd_vorn (anderes Programm vorn), wieder_vorn (Uzai oder Spiel).
static func step(st: Dictionary, ev: String, in_game := false) -> Dictionary:
	var m := str(st.get("mode", "aus"))
	var l := str(st.get("lage", "oben"))
	var guide := bool(st.get("guide", false))
	var acts: Array = []
	match ev:
		"an", "start":
			if m == "aus":
				m = "an"
				l = "unter" if guide else "oben"
				acts = ["klein"] if ev == "an" else ["fenster"]
		"vollbild":
			if m != "aus":
				if in_game:
					acts = ["erst_spiel"]
				else:
					acts = (["zeigen"] if l == "weg" or l == "fremd" else []) + ["gross"]
					m = "aus"
					l = "oben"
		"schliessen", "ausschalten":
			if m != "aus":
				m = "aus"
				l = "oben"
				acts = ["stopp"] if ev == "schliessen" else ["aus"]
		"gestoppt":
			if m != "aus":
				m = "aus"
				l = "oben"
				acts = ["aufraeumen"]
		"guide_auf":
			if m != "aus" and l == "oben":
				l = "unter"
				acts = ["unter_uzai"]
			elif m != "aus" and l == "fremd":
				# Guide-Taste, während ein anderes Programm vorn lag: Uzai kommt nach vorn, das Bild mit.
				l = "unter"
				acts = ["zeigen", "unter_uzai"]
		"guide_zu":
			if m == "bewegen":
				m = "an"
				acts.append("merken")
			if m == "an" and l != "weg" and l != "fremd":
				l = "oben"
				acts.append("nach_oben")
		"bewegen":
			if m == "an" and l != "weg" and l != "fremd":
				m = "bewegen"
				l = "oben"
				acts = ["nach_oben"]
		"bewegen_fertig":
			if m == "bewegen":
				m = "an"
				l = "unter" if guide else "oben"
				acts = ["einrasten", "merken"] + (["unter_uzai"] if guide else [])
		"bewegen_zurueck":
			if m == "bewegen":
				m = "an"
				l = "unter" if guide else "oben"
				acts = ["zuruecksetzen"] + (["unter_uzai"] if guide else [])
		"ruhe":
			if m != "aus" and l != "weg":
				m = "an"
				l = "weg"
				acts = ["verstecken"]
		"wach":
			if m != "aus" and l == "weg":
				l = "unter" if guide else "oben"
				acts = ["zeigen"] + (["unter_uzai"] if guide else ["nach_oben"])
		"spiel_fenster":
			if m != "aus":
				acts = ["umziehen", "vollbild_pruefen"]
		"spiel_ende":
			if m != "aus" and l == "oben":
				acts = ["nach_oben"]
		"fremd_vorn":
			if m == "an" and l == "oben":
				l = "fremd"
				acts = ["verstecken"]
		"wieder_vorn":
			if m != "aus" and l == "fremd":
				l = "unter" if guide else "oben"
				acts = ["zeigen"] + (["unter_uzai"] if guide else ["nach_oben"])
	return { "mode": m, "lage": l, "actions": acts }


## Liegt vorn, was zu Uzai gehört? fg: Antwort des Helfers { fg_hwnd, fg_pid, game_pid (Prozess des
## Spielfensters) }. Unser: Uzai, das Video (mpv) und im Spiel dessen Fenster bzw. Prozesse. Weiß
## Uzai nicht, wer vorn liegt (kein Vordergrund, Spiel ohne bekanntes Fenster und ohne Prozess),
## zählt es als unser – dann bleibt das Bild, wie es ist.
static func unser_vorn(fg: Dictionary, own_pid: int, mpv_pid: int, in_game: bool, game_hwnd: int, game_pids: Array) -> bool:
	var fpid := int(fg.get("fg_pid", 0))
	var fh := int(fg.get("fg_hwnd", 0))
	if fpid <= 0 or fh == 0:
		return true
	if fpid == own_pid or (mpv_pid > 0 and fpid == mpv_pid):
		return true
	if not in_game:
		return false
	var gp := int(fg.get("game_pid", 0))
	if game_hwnd == 0 and gp <= 0 and game_pids.is_empty():
		return true
	return (game_hwnd != 0 and fh == game_hwnd) or (gp > 0 and fpid == gp) or game_pids.has(fpid)


## „WxH+X+Y“ für mpvs --geometry (relativ zum Bildschirm).
static func geometry(r: Rect2i, monitor: Rect2i) -> String:
	var p := r.position - monitor.position
	return "%dx%d%s%d%s%d" % [r.size.x, r.size.y, "+" if p.x >= 0 else "-", absi(p.x), "+" if p.y >= 0 else "-", absi(p.y)]


# --- Zustand -------------------------------------------------------------------------------------

func active() -> bool:
	return mode != "aus"


## Zahl aus den Einstellungen; fehlt sie oder ist sie kaputt, der Standard.
static func _num(key: String, fallback: float) -> float:
	var v: Variant = Config.get_value(key, fallback)
	return float(v) if v is int or v is float else fallback


func size_key() -> String:
	var k := str(Config.get_value("pip.size", "m"))
	return k if SIZES.has(k) else "m"


func opacity() -> int:
	var o := int(_num("pip.opacity", 100))
	return o if OPACITY.has(o) else 100


func lage_f() -> Vector2:
	return Vector2(clampf(_num("pip.fx", 1.0), 0.0, 1.0), clampf(_num("pip.fy", 1.0), 0.0, 1.0))


func corner() -> String:
	return corner_of(lage_f())


## Wo das Bild gerade hingehört (physische Pixel).
func rect() -> Rect2i:
	return place(work, lage_f(), size_for(work, size_key(), scale), scale)


## Echtes Fenster (Windows, mpv) oder Vorschau (Demo, Proben)?
func _real() -> bool:
	return Config.is_windows() and not Video.sim and Helper.available


func _event(ev: String) -> void:
	var in_game := bool(Launcher.in_game)
	var res := step({ "mode": mode, "lage": lage, "guide": _guide_on }, ev, in_game)
	mode = str(res.mode)
	lage = str(res.lage)
	for a in res.actions:
		await _do(str(a))
	changed.emit()


# --- Rein, raus, zu ------------------------------------------------------------------------------

## Aus dem Player: Bild schrumpft in die Ecke. Nicht bei „Nur Ton“ (es gibt kein Bild).
func enter() -> bool:
	if mode != "aus" or not Video.active or Video.audio_only:
		return false
	await _event("an")
	return true


## Gleich als Bild in Bild starten (Guide im Spiel: „Weiterschauen“).
func start(list: Array, idx := 0) -> void:
	if mode != "aus" or list.is_empty():
		return
	_guide_on = _guide_open()
	await _read_screen(Launcher.game_hwnd() if Launcher.in_game else 0)
	var r := rect()
	# Erst der Zustand, dann das Video: Video.started kommt noch in Video.play.
	await _event("start")
	Video.play(list, idx, { "pip": true, "pip_geometry": geometry(r, mon) })


## Zurück ins Vollbild (Uzai vorn, Player wie vorher). Im Spiel nicht – erst das Spiel beenden.
func leave() -> void:
	await _event("vollbild")


func close() -> void:
	await _event("schliessen")


## Ausschalten (main.power_off): Bild in Bild endet mit Uzai.
func power_off() -> void:
	await _event("ausschalten")


func _do(a: String) -> void:
	match a:
		"klein":
			await _shrink()
		"fenster":
			_hwnd = 0
		"gross":
			await _grow()
		"erst_spiel":
			Toasts.show_toast("Vollbild nach dem Spiel", "Solange ein Spiel läuft, bleibt das Video als Bild in Bild.", "pip", { "ms": 3500 })
		"stopp":
			await _remember_rect()
			_sim_hide()
			# Abwarten, bis mpv wirklich zu ist: Gleich danach startet oft schon das nächste Video
			# (ein anderer Stream aus Uzai) und soll nicht ins endende mpv laden.
			await Video.stop()
		"aus":
			# Ausschalten wartet auf niemanden: gleich beenden (sonst überlebte mpv Uzai).
			_sim_hide()
			Video.stop()
		"aufraeumen":
			_sim_hide()
			Video.pip = false
			_hwnd = 0
		"unter_uzai":
			await _behind()
		"nach_oben":
			await _raise(false)
		"merken":
			_save_lage(snap(lage_f()))
		"einrasten":
			_save_lage(snap(lage_f()))
			_apply(MOVE_MS)
		"zuruecksetzen":
			_save_lage(_move_from)
			Config.set_value("pip.size", _move_size)
			_apply(MOVE_MS)
		"verstecken":
			_show(false)
		"zeigen":
			_show(true)
		"umziehen":
			await get_tree().create_timer(0.8).timeout
			await _read_screen(Launcher.game_hwnd())
			_apply(MOVE_MS)
			await _raise(true)
		"vollbild_pruefen":
			await _check_exclusive()


func _shrink() -> void:
	_busy = true
	_guide_on = _guide_open()
	await Video.set_pip(true)
	if _real():
		await _read_screen(Launcher.game_hwnd() if Launcher.in_game else 0)
		var r := rect()
		await _call("place", { "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "ms": ENTER_MS, "top": true })
		# Die Art (ohne Fokus, ohne Taskleiste) erst klein umstellen: Dafür verschwindet das Fenster
		# einen Augenblick – im Vollbild sähe man das Blinken.
		await get_tree().create_timer(ENTER_MS / 1000.0 + 0.03).timeout
		var st := await _call("style", { "style": true, "alpha": opacity() })
		if bool(st.get("fg", false)) and Launcher.in_game and not _guide_open():
			Launcher.focus_game()
	else:
		_sim_area()
		_sim_show(true)
	_busy = false


func _grow() -> void:
	_busy = true
	_remember_rect()
	if _real():
		await _read_screen(0)
		await _call("place",
				{ "x": mon.position.x, "y": mon.position.y, "w": mon.size.x, "h": mon.size.y, "ms": ENTER_MS - 60, "style": false, "alpha": 100, "top": true })
		await get_tree().create_timer((ENTER_MS - 40) / 1000.0).timeout
	else:
		_sim_grow()
		await get_tree().create_timer((ENTER_MS - 60) / 1000.0).timeout
	await Video.set_pip(false)
	_busy = false
	if main and main.has_method("open_movie_player"):
		main.open_movie_player()


## Zu Ende als Bild in Bild: wie im Player das nächste Video der Liste (YouTube, „Automatisch
## weiter“). Filme startet Movies selbst (nächste Folge), sonst bleibt das letzte Bild stehen.
func _on_end() -> void:
	if mode == "aus" or Video.video.has("movies") or not Video.has_next() or not bool(Config.get_value("youtube.autoplay", true)):
		return
	var vid := str(Video.video.get("id", ""))
	await get_tree().create_timer(3.0).timeout
	if mode != "aus" and Video.active and Video.at_end and str(Video.video.get("id", "")) == vid:
		Video.next()


func _on_stopped() -> void:
	if mode != "aus":
		_event("gestoppt")
	else:
		Video.pip = false


## Neues Video als Bild in Bild: In derselben mpv-Sitzung (nächstes Video) passt Uzai die Lage
## nach dem Laden noch einmal an; startet mpv neu (Filme, gleich als Bild in Bild), bekommt das
## neue Fenster die Art (ohne Fokus, keine Taskleiste) und kommt an seinen Platz.
func _on_started(_v: Dictionary) -> void:
	if not Video.pip or mode == "aus":
		return
	if not _real():
		_sim_area()
		if not is_instance_valid(_sim) or not _sim.visible:
			_sim_show(false)
		_sim_texture()
		return
	var pid := Video.mpv_pid()
	if pid != _pid:
		_hwnd = 0
	_pid = pid
	for i in 24:
		await get_tree().create_timer(0.25).timeout
		if not Video.pip or not Video.active:
			return
		var f := await _call("find")
		if int(f.get("hwnd", 0)) != 0:
			break
	await _read_screen(Launcher.game_hwnd() if Launcher.in_game else 0)
	var r := rect()
	var res := await _call("place",
			{ "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "ms": 160, "style": true, "alpha": opacity(), "top": lage == "oben" })
	if lage == "unter":
		await _behind()
	elif lage == "weg" or lage == "fremd":
		_show(false)
	# mpv hat sich beim Öffnen den Fokus genommen: im Spiel zurück ans Spiel.
	if bool(res.get("fg", false)) and Launcher.in_game and not _guide_open():
		Launcher.focus_game()
	# Nach dem Laden (mpv passt die Größe an ein neues Video an): noch einmal an den Platz.
	var t0 := Time.get_ticks_msec()
	while Video.active and Video.pip and Video.loading and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().create_timer(0.3).timeout
	if Video.active and Video.pip and mode != "aus":
		_apply(0)


# --- Bedienen (Guide) ----------------------------------------------------------------------------

func set_size(key: String) -> void:
	if not SIZES.has(key):
		return
	Config.set_value("pip.size", key)
	_apply(MOVE_MS)
	changed.emit()


func set_corner(name_: String) -> void:
	if not CORNERS.has(name_):
		return
	_save_lage(CORNERS[name_])
	_apply(MOVE_MS)
	changed.emit()


func cycle_opacity() -> int:
	var o := next_opacity(opacity())
	Config.set_value("pip.opacity", o)
	if _real():
		_call("alpha", { "alpha": o })
	elif is_instance_valid(_sim):
		_sim.modulate.a = o / 100.0
	changed.emit()
	return o


## Verschieben anfangen: das Bild liegt dafür ganz oben, der Guide tritt zurück.
func move_begin() -> void:
	if mode != "an":
		return
	_move_from = lage_f()
	_move_size = size_key()
	await _event("bewegen")


## keep: an der neuen Stelle lassen (A), sonst zurück (B).
func move_end(keep: bool) -> void:
	if mode != "bewegen":
		return
	await _event("bewegen_fertig" if keep else "bewegen_zurueck")


## Stick-Ausschlag (−1…1) für dt Sekunden.
func move_by_stick(axis: Vector2, dt: float) -> void:
	var sz := size_for(work, size_key(), scale)
	var d := stick_delta(axis, dt, free_space(work, sz, scale), scale)
	if d == Vector2.ZERO:
		return
	_save_lage((lage_f() + d).clamp(Vector2.ZERO, Vector2.ONE))
	_push = true


## Ein Schritt mit dem Steuerkreuz (oder den Pfeiltasten): ein Achtel des freien Platzes.
func nudge(dir: Vector2) -> void:
	_save_lage((lage_f() + dir * 0.125).clamp(Vector2.ZERO, Vector2.ONE))
	_push = true


func _save_lage(f: Vector2) -> void:
	Config.set_value("pip.fx", snappedf(f.x, 0.0001))
	Config.set_value("pip.fy", snappedf(f.y, 0.0001))


## Mit der Maus verschoben? Die echte Lage des Fensters übernehmen.
func _remember_rect() -> void:
	if not _real() or not Video.active or not Video.pip:
		return
	var inf := await _call("info", {})
	var r: Array = inf.get("rect", [])
	if r.size() == 4 and int(r[2]) > 0:
		var cur := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		if cur.size.x < mon.size.x - 4:
			_save_lage(fractions(work, cur, scale))


func _apply(ms: int) -> void:
	var r := clamp_rect(rect(), work)
	if _real():
		_call("place", { "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "ms": ms })
	elif is_instance_valid(_sim):
		_sim_to(Rect2(r), ms / 1000.0)


# --- Laufend -------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if mode == "aus":
		_fremd_n = 0
		return
	var g := _guide_open()
	if g != _guide_on:
		_guide_on = g
		_event("guide_auf" if g else "guide_zu")
	var rest_on: bool = main != null and is_instance_valid(main.get("rest")) and bool(main.rest.active)
	if rest_on != _rest_on:
		_rest_on = rest_on
		_event("ruhe" if rest_on else "wach")
	if _push:
		_push_t -= dt
		if _push_t <= 0.0:
			_push = false
			_push_t = 0.033
			_apply(FOLLOW_MS)
	# Liegt ein anderes Programm oder der Desktop vorn, versteckt sich das Bild; ist Uzai oder das
	# Spiel wieder vorn, kommt es zurück.
	if mode == "an" and not g and (lage == "oben" or lage == "fremd") and _real():
		_front_t += dt
		if (_front_t >= FRONT_S or (lage == "fremd" and _uzai_vorn())) and not _front_busy:
			_front_t = 0.0
			_check_front()
	# Im Spiel: liegt ein fremdes Fenster über dem Bild (Spiel „immer oben“), wieder nach oben.
	_raise_t += dt
	if _raise_t >= 2.0:
		_raise_t = 0.0
		if lage == "oben" and Launcher.in_game and not g and not _busy and _real():
			_raise(true)


func _guide_open() -> bool:
	if main == null:
		return false
	var gd: Variant = main.get("_guide")
	return gd != null and is_instance_valid(gd)


## Uzai selbst liegt vorn (Fokus) oder bedient gerade ein Fenster dahinter (Browser, Fernbedienung
## eines Fensters, Video vorn: Nav.pad_unfocused) – ohne den Helfer zu fragen.
func _uzai_vorn() -> bool:
	return (is_inside_tree() and get_window().has_focus()) or Nav.pad_unfocused


## Wer liegt vorn? Fremd (zweimal hintereinander): Bild versteckt; wieder Uzai oder Spiel: zurück.
func _check_front() -> void:
	var ours := _uzai_vorn()
	if not ours:
		_front_busy = true
		var pids := await _spiel_pids()
		var r := await _call("front", { "game": Launcher.game_hwnd() if Launcher.in_game else 0 })
		_front_busy = false
		if r.is_empty() or mode != "an":
			return
		ours = unser_vorn(r, OS.get_process_id(), Video.mpv_pid(), bool(Launcher.in_game), Launcher.game_hwnd(), pids)
	_fremd_n = 0 if ours else _fremd_n + 1
	if ours and lage == "fremd":
		_event("wieder_vorn")
	elif not ours and lage == "oben" and _fremd_n >= FREMD_N and not _guide_open():
		_event("fremd_vorn")


## Prozesse des laufenden Spiels, einmal je Spiel (und neu, sobald sein Fenster da ist).
func _spiel_pids() -> Array:
	if not Launcher.in_game:
		return []
	var gid := str(Launcher.current.get("id", ""))
	if str(_spiel.id) != gid:
		_spiel = { "id": gid, "pids": [] }
		var pids: Array = await Launcher.game_pids()
		if str(_spiel.id) == gid:
			_spiel.pids = pids
	return _spiel.pids


# --- Fenster (Helfer) ----------------------------------------------------------------------------

func _call(op: String, args := {}) -> Dictionary:
	if not _real():
		return {}
	var a := args.duplicate()
	a["op"] = op
	a["pid"] = Video.mpv_pid()
	if _hwnd != 0:
		a["hwnd"] = _hwnd
	var r := await Helper.run("pip", a, 3.0)
	if not r.ok or not (r.result is Dictionary):
		return {}
	var res: Dictionary = r.result
	if int(res.get("hwnd", 0)) != 0:
		_hwnd = int(res.hwnd)
	return res


## Bildschirm für das Bild: der des Spiels (ref), sonst der, auf dem mpv liegt.
func _read_screen(ref: int) -> void:
	if not _real():
		_sim_area()
		return
	var inf := await _call("info", { "ref": ref })
	var m: Array = inf.get("mon", [])
	var w: Array = inf.get("work", [])
	if m.size() == 4 and int(m[2]) > 0:
		mon = Rect2i(int(m[0]), int(m[1]), int(m[2]), int(m[3]))
	if w.size() == 4 and int(w[2]) > 0:
		work = Rect2i(int(w[0]), int(w[1]), int(w[2]), int(w[3]))
	scale = dpi_scale(int(inf.get("dpi", 96)))


func _behind() -> void:
	if _real():
		await _call("behind", { "after": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE) })
	elif is_instance_valid(_sim):
		_sim_layer(false)


func _raise(only_covered: bool) -> void:
	if _real():
		await _call("raise", { "own": OS.get_process_id(), "covered": only_covered })
	elif is_instance_valid(_sim):
		_sim_layer(true)


func _show(on: bool) -> void:
	if _real():
		_call("show", { "on": on })
		if on:
			_call("raise", { "own": OS.get_process_id(), "covered": false })
	elif is_instance_valid(_sim):
		_sim.visible = on


## Exklusives Vollbild: kein Fenster kommt darüber. Einmal je Spiel ein ruhiger Hinweis.
func _check_exclusive() -> void:
	if not _real() or not Launcher.in_game:
		return
	await get_tree().create_timer(1.5).timeout
	var inf := await _call("info", { "ref": Launcher.game_hwnd() })
	exclusive = int(inf.get("quns", 0)) == QUNS_D3D_FULLSCREEN
	var gid := str(Launcher.current.get("id", ""))
	if exclusive and gid != _hint_gid:
		_hint_gid = gid
		Toasts.show_toast("Bild in Bild ist hier verdeckt", exclusive_hint(), "pip", { "ms": 9000 })
	changed.emit()


## „Bild in Bild · Läuft · 3:12 von 10:00“ (Guide) – schon übersetzt: Die Zeile im Guide übersetzt
## selbst nicht (dort stehen auch Titel).
static func status_text() -> String:
	var t := func(s: String) -> String: return TranslationServer.translate(s)
	var bits := PackedStringArray([t.call("Bild in Bild")])
	if Video.is_live():
		bits.append(t.call("Live"))
	elif Video.loading and not Video.paused:
		bits.append(t.call("lädt …"))
	elif Video.duration > 0.0:
		bits.append(t.call("Angehalten bei %s von %s" if Video.paused else "Läuft  ·  %s von %s") % [YouTube.time_text(Video.pos), YouTube.time_text(Video.duration)])
	return "  ·  ".join(bits)


static func exclusive_hint() -> String:
	return "Spiel im Vollbild-Fenster (randlos) starten, damit Bild in Bild sichtbar ist."


# --- Vorschau ohne mpv (Demo, Proben) ------------------------------------------------------------

func _sim_area() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	work = Rect2i(Vector2i.ZERO, Vector2i(vp))
	mon = work
	scale = 1.0


## Die Vorschau liegt in Uzai über allem (wie das echte Fenster) bzw. unter den Ebenen (Guide).
func _sim_layer(top: bool) -> void:
	if not is_instance_valid(_sim) or main == null or not is_instance_valid(main.get("layer_host")):
		return
	var host: Control = main.layer_host
	if top:
		main.move_child(_sim, main.get_child_count() - 1)
	else:
		main.move_child(_sim, host.get_index())


func _sim_show(animate: bool) -> void:
	if main == null:
		return
	if not is_instance_valid(_sim):
		_sim = _SimPip.new()
		main.add_child(_sim)
	_sim.visible = true
	_sim.modulate.a = opacity() / 100.0
	_sim_layer(lage != "unter")
	_sim_texture()
	var r := Rect2(rect())
	if animate:
		_sim.set_rect(Rect2(Vector2.ZERO, Vector2(work.size)), 0.0)
		_sim_to(r, ENTER_MS / 1000.0)
	else:
		_sim.set_rect(r, 1.0)


func _sim_texture() -> void:
	if not is_instance_valid(_sim):
		return
	var v := Video.video
	(_sim as _SimPip).poster = VideoCard.poster_texture(v)
	var url := VideoCard.thumb_url(v)
	if url != "":
		var vid := str(v.get("id", ""))
		var sim := _sim
		Media.url_texture(url, 640, func(t: Texture2D) -> void:
			if t and is_instance_valid(sim) and str(Video.video.get("id", "")) == vid:
				(sim as _SimPip).poster = t
		)


func _sim_to(r: Rect2, sec: float) -> void:
	if not is_instance_valid(_sim):
		return
	var s := _sim as _SimPip
	var from := Rect2(s.position, s.size)
	var k0 := s.round_k
	if sec <= 0.0:
		s.set_rect(r, 1.0)
		return
	var tw := U.tw(s, "uz_pip", Tween.TRANS_QUART)
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(s):
			s.set_rect(Rect2(from.position.lerp(r.position, k), from.size.lerp(r.size, k)), lerpf(k0, 1.0, k))
	, 0.0, 1.0, sec)


func _sim_grow() -> void:
	if not is_instance_valid(_sim):
		return
	var s := _sim as _SimPip
	var from := Rect2(s.position, s.size)
	var to := Rect2(Vector2.ZERO, Vector2(work.size))
	_sim_layer(true)
	var tw := U.tw(s, "uz_pip", Tween.TRANS_QUART)
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(s):
			s.set_rect(Rect2(from.position.lerp(to.position, k), from.size.lerp(to.size, k)), 1.0 - k)
	, 0.0, 1.0, (ENTER_MS - 60) / 1000.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s):
			s.visible = false)


func _sim_hide() -> void:
	if not is_instance_valid(_sim) or not _sim.visible:
		return
	var s := _sim
	var tw := U.tw(s, "uz_pip_fade")
	tw.tween_property(s, "modulate:a", 0.0, U.T_BASE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s):
			s.visible = false)


## Vorschau: Bild des Videos mit runden Ecken, feinem Rand und Schatten, unten der Fortschritt,
## bei Pause das Zeichen in der Mitte. Der Schatten liegt in einer eigenen Fläche dahinter, die
## runde Fläche davor schneidet Bild und Anzeige zu (clip_children).
class _SimPip extends Control:
	var poster: Texture2D:
		set(t):
			poster = t
			if is_instance_valid(_img):
				_img.texture = t
	var round_k := 1.0
	var _shade: Panel
	var _clip: Panel
	var _img: TextureRect
	var _top: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shade = Panel.new()
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_shade)
		_clip = Panel.new()
		_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		add_child(_clip)
		_img = TextureRect.new()
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_img.texture = poster
		_clip.add_child(_img)
		_top = Control.new()
		_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top.draw.connect(_draw_top)
		_clip.add_child(_top)
		_style()

	func set_rect(r: Rect2, k: float) -> void:
		position = r.position
		size = r.size
		if is_instance_valid(_clip):
			for c: Control in [_shade, _clip, _img, _top]:
				c.position = Vector2.ZERO
				c.size = r.size
		if absf(k - round_k) > 0.001:
			round_k = k
			_style()

	func _style() -> void:
		if not is_instance_valid(_clip):
			return
		var rad := int(18.0 * round_k)
		var sh := UzTheme.box(Color(0.05, 0.05, 0.06), rad)
		sh.shadow_color = Color(0, 0, 0, 0.5 * round_k)
		sh.shadow_size = int(30.0 * round_k)
		sh.shadow_offset = Vector2(0, 10.0 * round_k)
		_shade.add_theme_stylebox_override("panel", sh)
		_clip.add_theme_stylebox_override("panel", UzTheme.box(Color(0.05, 0.05, 0.06), rad))

	func _process(_dt: float) -> void:
		if visible and is_instance_valid(_top):
			_top.queue_redraw()

	func _draw_top() -> void:
		var sz := _top.size
		var rad := 18.0 * round_k
		var edge := UzTheme.box(Color(0, 0, 0, 0), int(rad), maxi(1, int(2.0 * round_k)), Color(1, 1, 1, 0.16 * round_k))
		edge.draw_center = false
		_top.draw_style_box(edge, Rect2(Vector2.ZERO, sz))
		if Video.duration > 0.0 and round_k > 0.5:
			var p := clampf(Video.pos / Video.duration, 0.0, 1.0)
			var bar := Rect2(0, sz.y - 5.0, sz.x, 5.0)
			_top.draw_rect(bar, Color(1, 1, 1, 0.22))
			_top.draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), UzTheme.col("accent"))
		if (Video.paused or Video.loading) and round_k > 0.5:
			var c := sz * 0.5
			var rr := minf(sz.y * 0.16, 44.0)
			_top.draw_circle(c, rr, Color(0, 0, 0, 0.5))
			if Video.paused:
				var bw := rr * 0.22
				var bht := rr * 0.8
				_top.draw_rect(Rect2(c + Vector2(-bw * 1.6, -bht * 0.5), Vector2(bw, bht)), UzTheme.col("text"))
				_top.draw_rect(Rect2(c + Vector2(bw * 0.6, -bht * 0.5), Vector2(bw, bht)), UzTheme.col("text"))

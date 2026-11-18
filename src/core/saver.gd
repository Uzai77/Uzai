extends Node
## Ruhebildschirm (Punkt 94), wie beim Apple TV: Bleibt Uzai im Menü eine Weile unbedient
## (rest.saver, Minuten), zieht eine ruhige Kamerafahrt über die großen Bilder deiner Spiele,
## dazu Spielname, Uhrzeit und – falls etwas läuft – die Musik. Nur Bilder, die schon auf dem PC
## liegen (eigene Bilder, Medienordner, Steam-Cache, Uzais Zwischenspeicher; auf Wunsch eigene
## Bildschirmfotos): Für den Ruhebildschirm lädt Uzai nichts aus dem Netz.
##
## Nie im Spiel, bei einem Video oder Film im Bild, im Ruhemodus, ohne Fensterfokus, beim
## Tippen oder während der Controller-Problemlöser misst. Gezählt wird nur Zeit, in der er
## kommen dürfte. Jede Eingabe beendet ihn, ohne selbst etwas auszulösen
## (src/ui/layers/saver_screen.gd fängt alles ab). Auf Wunsch geht es danach in den Ruhemodus
## (rest.saver_rest). Ohne Fenster geprüft in tests/logic_ruhebild.gd.

const Leicht := preload("res://src/core/leicht.gd")
const SaverScreen := preload("res://src/ui/layers/saver_screen.gd")
const U := preload("res://src/ui/u.gd")

const CHECK_S := 5.0
const RECENT_DAYS := 60       ## zuletzt gespielte Spiele kommen zuerst
const SCAN_STEP := 40         ## so viele Spiele je neuem Bild höchstens nach einem Bild durchsehen
const SHOTS_MAX := 12
const SHOT_EVERY := 3         ## eigene Bildschirmfotos: jedes dritte Bild
## Kamerafahrt: so viele Bilder wie im Menü (0), ohne den Sparmodus der Engine. Mit 30
## Bildern je Sekunde und dem Sparmodus (unregelmäßige Pausen zwischen den Bildern) ruckelte die langsame
## Fahrt auf 120-Hz- und VRR-Fernsehern sichtbar.
const FPS_MOTION := 0
const FPS_STILL := 12
const MINUTES := [["0", "Aus"], ["2", "Nach 2 Min."], ["5", "Nach 5 Min."], ["10", "Nach 10 Min."], ["20", "Nach 20 Min."], ["30", "Nach 30 Min."]]
const REST_AFTER := [["0", "Nie"], ["30", "Nach 30 Min."], ["60", "Nach 1 Std."], ["120", "Nach 2 Std."]]

const Main := preload("res://src/main.gd")
var main: Main
var screen: Control             ## der offene Ruhebildschirm (auch beim Ausblenden), sonst null
var _idle_from := 0             ## seit wann (ms) niemand bedient hat und nichts dagegen sprach
var _shown_at := 0
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _pending: Array = []        ## Spiele bzw. fertige Bilder, die noch nicht durchgesehen sind
var _found: Array = []          ## gefundene Bilder dieser Runde
var _cycle: Array = []          ## Reihenfolge der nächsten Runde
var _last_path := ""
var _zu_klein := {}             ## Bilder, die den Bildschirm nur hochgezogen füllen würden (saver_screen.gd)
var auto := true                ## kommt von selbst (nicht in Rundgängen und Proben, --uzai-…)
var bei_ruhe := false           ## läuft im Ruhemodus (rest.gd): eine Taste weckt den Ruhemodus mit


func _ready() -> void:
	_idle_from = Time.get_ticks_msec()
	# Automatische Rundgänge und Proben: nie von selbst, sonst stünde er mitten in den Bildern.
	auto = not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--uzai-"))
	var t := Timer.new()
	t.wait_time = CHECK_S
	t.timeout.connect(_check)
	add_child(t)
	t.start()
	Nav.command.connect(func(_c: String) -> void: poke())
	Nav.focus_moved.connect(func(_c: Control) -> void: poke())
	Helper.pad_event.connect(func(_k: String) -> void: poke())
	Launcher.started.connect(func(_g: Dictionary) -> void: stop(true))
	Remote.show_requested.connect(func() -> void: stop())
	Remote.launch_requested.connect(func(_id: String) -> void: stop(true))


## Bedient: die Wartezeit beginnt von vorn.
func poke() -> void:
	_idle_from = Time.get_ticks_msec()


## Nur beobachten (der offene Ruhebildschirm fängt die Eingaben selbst ab).
func _input(event: InputEvent) -> void:
	if SaverScreen.wakes(event):
		poke()


func _notification(what: int) -> void:
	# Ein anderes Fenster kam nach vorn (Steam-Dialog, Desktop): weg damit, sonst stünde er dort.
	# Im Ruhemodus nicht: dort hat Uzai oft keinen Fokus (Spiel dahinter), Tasten wecken trotzdem.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(screen) and not bei_ruhe:
		stop(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		poke()


func minutes() -> int:
	return int(str(Config.get_value("rest.saver", "10")))


func _check() -> void:
	var now := Time.get_ticks_msec()
	var why := blocked()
	if is_instance_valid(screen):
		if bei_ruhe:
			return
		if why != "":
			stop()
		elif rest_due(int(str(Config.get_value("rest.saver_rest", "0"))), now - _shown_at):
			_to_rest()
		return
	if why != "" or not auto:
		_idle_from = now
	elif due(minutes(), now - _idle_from):
		start()


## Warum gerade kein Ruhebildschirm kommen darf ("" = er darf).
func blocked() -> String:
	var top := Nav.top_layer()
	var f := get_viewport().gui_get_focus_owner()
	var w := get_window()
	return block({
		"boot": main != null and is_instance_valid(main._boot),
		"game": Launcher.in_game or Launcher.is_starting(),
		"video": Video.active and not Video.background,
		"rest": main != null and main.rest != null and bool(main.rest.active),
		"away": main != null and (bool(main._parked) or bool(main._overlay_mode)),
		"focus": w.has_focus() and w.mode != Window.MODE_MINIMIZED,
		"pad": top != null and top != screen and top.has_meta("uz_pad_owned"),
		"typing": f is LineEdit or f is TextEdit,
	})


static func block(ctx: Dictionary) -> String:
	if bool(ctx.get("boot", false)):
		return "Startanimation"
	if bool(ctx.get("game", false)):
		return "Spiel"
	if bool(ctx.get("video", false)):
		return "Video"
	if bool(ctx.get("rest", false)):
		return "Ruhemodus"
	if bool(ctx.get("away", false)) or not bool(ctx.get("focus", true)):
		return "nicht vorn"
	if bool(ctx.get("pad", false)):
		return "Controller-Test"
	if bool(ctx.get("typing", false)):
		return "Texteingabe"
	return ""


static func due(mins: int, idle_ms: int) -> bool:
	return mins > 0 and idle_ms >= mins * 60000


static func rest_due(mins: int, shown_ms: int) -> bool:
	return mins > 0 and shown_ms >= mins * 60000


## Einfache Fassung (nur überblenden, 12 Bilder pro Sekunde): auf Wunsch, mit „Animationen
## reduzieren“, im leichten Modus (Leicht.active, Aufrufer) oder wenn das Menü auf diesem PC
## schon oft Bilder verpasst.
static func simple(motion: bool, reduce: bool, late_pct: float, frames: int) -> bool:
	return not motion or reduce or (frames >= 600 and late_pct > 5.0)


# --- Ein und aus -----------------------------------------------------------------------------

## preview: aus den Einstellungen („Vorschau“) – auch wenn er sonst aus ist. ruhe: im Ruhemodus
## (statt den Bildschirm auszuschalten); dann weckt das Ende den Ruhemodus mit.
func start(preview := false, ruhe := false) -> void:
	if is_instance_valid(screen) or main == null:
		return
	bei_ruhe = ruhe
	if not preview and blocked() != "":
		return
	prepare(Library.visible_games(), _own_shots())
	var late := 0.0
	var frames := 0
	if main.perf != null:
		var st: Dictionary = main.perf.menu_stats()
		late = float(st.get("late_pct", 0.0))
		frames = int(st.get("frames", 0))
	var still := simple(str(Config.get_value("rest.saver_motion", "fahrt")) == "fahrt", bool(Config.get_value("theme.reduce_motion", false)) or Leicht.active,
			late, frames)
	screen = SaverScreen.new()
	screen.saver = self
	screen.simple = still
	main.add_child(screen)
	_shown_at = Time.get_ticks_msec()
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	main.set_idle(true, FPS_STILL if still else FPS_MOTION, still)
	Helper.hlog("Ruhebildschirm an%s" % (" (Ruhemodus)" if ruhe else (" (Vorschau)" if preview else "")))


## Ruhebildschirm weg (eine Eingabe, ein Spielstart, ein Fenster davor). instant: ohne Ausblenden.
func stop(instant := false) -> void:
	poke()
	var aus_ruhe := bei_ruhe
	bei_ruhe = false
	if not is_instance_valid(screen):
		return
	if aus_ruhe and main and main.rest != null and bool(main.rest.active):
		main.rest.wake("ruhebild")
	var s := screen
	s.leave(instant)
	s.tree_exited.connect(func() -> void:
		if screen == s:
			screen = null
	, CONNECT_ONE_SHOT)
	Input.mouse_mode = _mouse_mode
	if main and get_window().has_focus() and not Launcher.in_game and not bool(main._parked):
		main.set_idle(false)


func _to_rest() -> void:
	stop(true)
	if main and main.rest != null:
		main.rest.enter("ruhebild")


# --- Bilder ----------------------------------------------------------------------------------

## Reihenfolge der Spiele: Favoriten und zuletzt Gespieltes zuerst (gemischt), dann der Rest.
static func order(games: Array, now: int, rng: RandomNumberGenerator) -> Array:
	var first: Array = []
	var rest: Array = []
	for g in games:
		var last := maxi(int(g.get("last_played", 0)), int(g.get("steam_last", 0)))
		if bool(g.get("favorite", false)) or (last > 0 and now - last <= RECENT_DAYS * 86400):
			first.append(g)
		else:
			rest.append(g)
	_shuffle(first, rng)
	_shuffle(rest, rng)
	return first + rest


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## Eigene Bildschirmfotos zwischen die Spiele: jedes every-te Bild, solange welche da sind.
static func interleave(games: Array, shots: Array, every := SHOT_EVERY) -> Array:
	var out: Array = []
	var si := 0
	for g in games:
		if si < shots.size() and out.size() % every == every - 1:
			out.append(shots[si])
			si += 1
		out.append(g)
	while si < shots.size():
		out.append(shots[si])
		si += 1
	return out


## Bildunterschrift: Plattform und Spielzeit („PlayStation 2 · 14 Std. gespielt“).
static func sub_text(system_name: String, played_s: int) -> String:
	var bits := PackedStringArray()
	if system_name != "":
		bits.append(system_name)
	if played_s > 0:
		bits.append(U.playtime(played_s))
	return "  ·  ".join(bits)



func _own_shots() -> Array:
	if not bool(Config.get_value("rest.saver_shots", false)):
		return []
	var out: Array = []
	for it in Capture.list_items():
		if str(it.get("kind", "")) == "shot":
			out.append(
					{ "slide": true, "path": str(it.path), "title": str(it.get("title", "")), "sub":
							TranslationServer.translate("Dein Bildschirmfoto") + "  ·  " + U.date(int(it.get("mtime", 0))),
					"logo": "" })
			if out.size() >= SHOTS_MAX:
				break
	return out


## Neue Runde: Spiele (und Bildschirmfotos) in Reihenfolge, noch nichts durchgesehen. rng: fester
## Zufall für Tests, sonst neu gemischt.
func prepare(games: Array, shots: Array, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_pending = interleave(order(games, int(Time.get_unix_time_from_system()), rng), shots)
	_found.clear()
	_cycle.clear()
	_zu_klein.clear()
	_last_path = ""


## Das nächste Bild: { path, title, sub, logo } oder {} (gar keins auf dem PC). Erst werden die
## Spiele nach und nach durchgesehen (je Bild höchstens SCAN_STEP, damit nichts hakt), danach
## wiederholt sich das Gefundene in neuer Reihenfolge.
func next_slide() -> Dictionary:
	var checks := 0
	while not _pending.is_empty() and checks < SCAN_STEP:
		var it: Dictionary = _pending.pop_front()
		checks += 1
		# Fertige Bilder (Bildschirmfotos) tragen "slide"; Spiele haben selbst oft einen "path" (ROM).
		var s := it if bool(it.get("slide", false)) else slide_for(it)
		if not s.is_empty() and not _zu_klein.has(str(s.path)) and FileAccess.file_exists(str(s.path)):
			_found.append(s)
			_last_path = str(s.path)
			return s
	if _found.is_empty():
		return {}
	if _cycle.is_empty():
		_cycle = _found.duplicate()
		_cycle.shuffle()
		# Nicht zweimal dasselbe Bild hintereinander.
		if _cycle.size() > 1 and str(_cycle[0].path) == _last_path:
			_cycle.push_back(_cycle.pop_front())
	var s: Dictionary = _cycle.pop_front()
	_last_path = str(s.path)
	return s


## Dieses Bild ist kleiner als der Bildschirm (saver_screen.gd): diese Runde nicht mehr zeigen.
func zu_klein(path: String) -> void:
	_zu_klein[path] = true
	_found = _found.filter(func(x: Dictionary) -> bool: return str(x.path) != path)
	_cycle = _cycle.filter(func(x: Dictionary) -> bool: return str(x.path) != path)


## Bild eines Spiels, nur was schon auf dem PC liegt (Media.local_path fragt nie das Netz).
static func slide_for(g: Dictionary) -> Dictionary:
	var hero := Media.local_path(g, "hero")
	if hero == "":
		return {}
	var sys := str(g.get("system", ""))
	var sname := str(Config.system(sys).get("name", "")) if sys != "" and not Config.system(sys).is_empty() else Library.store_name(g, false, "")
	return { "path": hero, "title": Library.display_title(g), "sub": sub_text(sname, Library.playtime(g)),
		"logo": Media.local_path(g, "logo"), "id": str(g.get("id", "")) }

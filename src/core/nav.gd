extends Node
## Steuerung mit Controller, Tastatur, Maus und Touch. Uzai bewegt den Fokus selbst (räumlich,
## mit Gedächtnis pro Reihe), damit es sich wie eine Konsole anfühlt: gedrückt halten
## wiederholt, Reihen merken sich die letzte Position, Listen scrollen weich mit. Maus und Touch
## gehen über src/core/zeiger.gd, aber durch dieselben Wege (focus, _fire, activate).
##
## Befehle: up down left right a b x y lb rb lt rt guide menu (dazu quick: Schnellmenü-Taste)
## Geräte (device): pad, keys, mouse, touch – danach richten sich die Tastensymbole.

signal command(cmd: String)
signal device_changed(kind: String)
signal focus_moved(control: Control)
## Die Auswahl stößt am Rand an (genau einmal je Druck bzw. je Halten). Klang und Impuls kommen
## über Sfx „bump“ (der Klang löst den Pads-Impuls „rand“ selbst aus); wer mehr will, hört hier zu.
signal rand(control: Control, dir: String)

const DIRS := ["up", "down", "left", "right"]
## Medien-, Lautstärke- und Browsertasten: lösen in Uzai nie eine Bedienung aus (siehe _input).
const MEDIA_KEYS := [KEY_MEDIAPLAY, KEY_MEDIASTOP, KEY_MEDIANEXT, KEY_MEDIAPREVIOUS,
	KEY_MEDIARECORD, KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_VOLUMEMUTE, KEY_BACK, KEY_FORWARD, KEY_REFRESH,
	KEY_STOP, KEY_SEARCH, KEY_FAVORITES, KEY_HOMEPAGE, KEY_LAUNCHMAIL, KEY_LAUNCHMEDIA]
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const PadCheck := preload("res://src/core/pad_check.gd")
const PadsS := preload("res://src/core/pads.gd")
const Handheld := preload("res://src/core/handheld.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const Zeiger := preload("res://src/core/zeiger.gd")
const Schweben := preload("res://src/core/schweben.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Raster := preload("res://src/core/raster.gd")

var device := "keys"
var pad_name := ""
var pad_vid := -1                  ## Herstellernummer des zuletzt benutzten Controllers (Tastensymbole)
var root_scope: Control
var layers: Array[Control] = []
var game_mode := false:          ## im Spiel: nur die Guide-Taste zählt
	set(neu):
		game_mode = neu
		_eingabe_melden()
var _gmem := {}
var _held := {}                    ## Richtung → geplanter nächster Schritt (Uhr, ms)
var _held_steps := {}
## Uhr der Wiederholung (ms): läuft mit den Bildern (_process), nicht mit der Wanduhr – so liegt
## jeder Schritt auf dem Plan (400, dann 162 / 120 / 96 ms), ohne Drift und auch in Proben mit
## fester Bildrate.
var _uhr := 0.0
## Abstand bis zum nächsten Schritt, solange eine Richtung gehalten wird und wiederholt (ms), sonst 0.
var _takt_ms := 0
var _wiederholt := false           ## der laufende Schritt kommt aus dem Halten
var _rand_dir := ""                ## in diese Richtung hat das laufende Halten schon angestoßen
var _stick_dir := ""             ## Richtung, in die der linke Stick gerade zeigt
var _stick_next := 0.0           ## wann der Stick das nächste Mal weiterschaltet (Uhr, ms)
var _stick_steps := 0
## Der laufende Richtungsschritt kommt vom linken Stick (nicht vom Steuerkreuz): der Zeiger im Browser
## nimmt den Stick selbst analog und überhört diese Schritte.
var vom_stick := false
var _trig := { "lt": false, "rt": false }
var _view_down := false
var _view_combo := false         ## View war Teil von View + Start (Guide): beim Loslassen nichts
var _menu_down := false
var _tweens := {}
## Woher der letzte Befehl „guide“ kam: "pad" (Guide-Taste, Taste G) oder "combo" (View + Start).
## main.toggle_guide erkennt daran doppelte Meldungen derselben Geste (siehe dort).
var guide_src := "pad"
## Eine Ebene geht gerade auf (Layer.open bis push_layer, ein Bild lang): Befehle warten so lange
## und gehen dann an die neue Ebene – nie an die Karte dahinter (sie öffnete sonst ein zweites Mal
## oder verlöre die Auswahl, an die das Bild beim Schließen zurückfliegt), und nichts geht verloren.
## Ein zweites A in diesem Augenblick gilt als dasselbe Drücken.
var _opening: WeakRef = null
var _opening_ms := 0
var _held_cmds: Array = []
const HOLD_MS := 600
var zeiger: Node                   ## Maus und Touch (src/core/zeiger.gd)
var schweben: Node                 ## Maus darüber: Klick-Modus, Hand über Wählbarem (src/core/schweben.gd)
var _quick := {}                   ## Schnellmenü-Taste (controller.quick_key, handheld.gd)
var _lern: Callable                ## wartet auf eine Taste zum Belegen (lernen)
var _lern_bis := 0
## Langes A: Elemente mit der Meta uz_on_hold_a (Quellen der Spiele) lösen A erst beim Loslassen
## aus; bleibt A so lange gedrückt, gilt stattdessen das lange Drücken (Menü zum Anordnen).
const A_HOLD_MS := 450
var _a_down: Control = null
var _a_down_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_actions()
	zeiger = Zeiger.new()
	zeiger.nav = self
	add_child(zeiger)
	schweben = Schweben.new()
	schweben.nav = self
	add_child(schweben)
	_quick = Handheld.belegung(Config.get_value("controller.quick_key", {}))
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("controller."):
			setup_actions()
			_quick = Handheld.belegung(Config.get_value("controller.quick_key", {}))
		# Andere Tastensymbole gewählt: alle Symbole sofort neu zeichnen (auch oben in der Leiste).
		if k == "controller.glyphs":
			device_changed.emit(device)
	)
	Input.joy_connection_changed.connect(_on_joy_changed)
	for id in Input.get_connected_joypads():
		_set_pad(id)
		_pads_seen[_pad_key(id)] = true
	# Wie eine Konsole: kein Mauszeiger mitten im Bild, bis die Maus bewegt wird. Mit Controller
	# gelten gleich dessen Tastensymbole.
	if Config.get_value("controller.hide_mouse", true):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if not Input.get_connected_joypads().is_empty():
		device = "pad"


# --- Tastenbelegung ------------------------------------------------------------

func setup_actions() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev", "ui_accept", "ui_select", "ui_cancel", "ui_page_up", "ui_page_down",
			"ui_home", "ui_end"]:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
	var dz := clampf(float(Config.get_value("controller.deadzone", 0.5)), 0.15, 0.9)
	var swap := bool(Config.get_value("controller.swap_ab", false))
	# Stick und Trigger sind analog und senden laufend neue Werte. Sie stehen deshalb nicht in
	# der Belegung, sondern werden in _process abgefragt (mit Schwelle und eigener Wiederholung).
	_define("uz_up", [KEY_UP], [JOY_BUTTON_DPAD_UP], [], dz)
	_define("uz_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [], dz)
	_define("uz_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [], dz)
	_define("uz_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [], dz)
	_define("uz_a", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_B if swap else JOY_BUTTON_A], [], dz)
	_define("uz_b", [KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_A if swap else JOY_BUTTON_B], [], dz)
	_define("uz_x", [KEY_X], [JOY_BUTTON_Y if swap else JOY_BUTTON_X], [], dz)
	_define("uz_y", [KEY_Y, KEY_Z], [JOY_BUTTON_X if swap else JOY_BUTTON_Y], [], dz)
	_define("uz_lb", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [], dz)
	_define("uz_rb", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [], dz)
	_define("uz_lt", [KEY_PAGEUP, KEY_1], [], [], 0.5)
	_define("uz_rt", [KEY_PAGEDOWN, KEY_3], [], [], 0.5)
	_define("uz_guide", [KEY_G, KEY_HOME], [JOY_BUTTON_GUIDE], [], dz)
	_define("uz_menu", [KEY_M], [JOY_BUTTON_START], [], dz)
	_define("uz_view", [KEY_V], [JOY_BUTTON_BACK], [], dz)
	# Globale Suche: rechter Stick drücken (R3) oder F auf der Tastatur – von überall in Uzai.
	_define("uz_search", [KEY_F], [JOY_BUTTON_RIGHT_STICK], [], dz)


func _define(action: String, keys: Array, buttons: Array, axes: Array, deadzone: float) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, deadzone)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.device = -1
		InputMap.action_add_event(action, e)
	for ax in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = ax[0]
		e.axis_value = ax[1]
		e.device = -1
		InputMap.action_add_event(action, e)


# --- Eingaben ------------------------------------------------------------------

## Controller-Eingaben gehen an Uzai nur, wenn Uzai vorn ist. Sonst (Spiel, Discord im
## Maus-Modus) würden sie im Hintergrund Dinge auslösen. Die Guide-Taste kommt dann vom Helfer.
var passthrough := false:
	set(neu):
		passthrough = neu
		_eingabe_melden()
## Controller auch ohne Fensterfokus annehmen (Video im Ausweichmodus: mpv liegt vorn).
var pad_unfocused := false:
	set(neu):
		pad_unfocused = neu
		_eingabe_melden()


## Bis dahin (Ticks) zählt der Controller auch ohne Fokus-Meldung von Godot: Windows führt Uzais Fenster als das
## vordere, Godot hat davon nur nichts erfahren. main._start_vorn stellt das über den Helfer fest und verlängert die
## Frist, solange es so ist (src/core/startwache.gd).
var vorn_gilt_bis := 0


func _pad_allowed() -> bool:
	return not passthrough and (pad_unfocused or get_window().has_focus() or Time.get_ticks_msec() < vorn_gilt_bis)


## Wohin Controller und Tasten gerade gehen (Zustand.lage(), Fehlerbericht), aus game_mode, passthrough und
## pad_unfocused: menue (Uzai wird bedient), spiel (ohne Ebene darüber zählt nur die Guide-Taste), durchlass
## (nichts an Uzai, z. B. Discord im Maus-Modus); _ohne_fokus: der Controller zählt auch ohne Fensterfokus.
func eingabe_lage() -> String:
	if passthrough:
		return "durchlass"
	return ("spiel" if game_mode else "menue") + ("_ohne_fokus" if pad_unfocused else "")


func _eingabe_melden() -> void:
	Zustand.melden("steuerung.eingabe", eingabe_lage())


## Ohne Fensterfokus (im Spiel) bleibt nur der Weg zurück: Guide-Taste und View + Start. Der
## Helfer meldet beides auch, liest aber nur XInput – PlayStation- und Nintendo-Controller kämen
## sonst nicht mehr aus dem Spiel. Kommt beides an, fängt main.toggle_guide die zweite Meldung ab.
func _guide_unfocused(b: InputEventJoypadButton) -> void:
	if not b.pressed:
		return
	# Share-/Aufnahme-Taste (Xbox Series, Switch Pro): Clip speichern, auch mitten im Spiel.
	if b.button_index == JOY_BUTTON_MISC1:
		command.emit("capture")
		return
	var combo := bool(Config.get_value("controller.guide_combo", true))
	var hit := b.button_index == JOY_BUTTON_GUIDE
	if combo and b.button_index == JOY_BUTTON_START and Input.is_joy_button_pressed(b.device, JOY_BUTTON_BACK):
		hit = true
	if combo and b.button_index == JOY_BUTTON_BACK and Input.is_joy_button_pressed(b.device, JOY_BUTTON_START):
		hit = true
	if hit:
		_fire_guide("pad" if b.button_index == JOY_BUTTON_GUIDE else "combo")


## Start (Menü) ist gerade gedrückt – für main.toggle_guide (Akkord View + Start).
func start_held() -> bool:
	return _menu_down


func _fire_guide(src: String) -> void:
	guide_src = src
	_fire("guide")
	guide_src = "pad"


## Außerhalb eines Spiels liegt ein anderes Fenster vorn (Spotify-Start, Steam-Dialog, Browser):
## Uzai nimmt den Controller dann nicht an. Früher ohne jeden Hinweis – jetzt sagt eine Mitteilung
## über dem fremden Fenster einmal, dass die Guide-Taste Uzai zurückholt (wieder erst, nachdem Uzai
## vorn war – wer gerade bewusst in einem Emulator Tasten belegt, wird nicht ständig gestört).
var _hint_shown := false


func _hint_unfocused(b: InputEventJoypadButton) -> void:
	if not b.pressed or game_mode or passthrough or _hint_shown or b.button_index == JOY_BUTTON_GUIDE:
		return
	_hint_shown = true
	command.emit("unfocused")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_hint_shown = false
		# Zurück nach vorn (aus dem Spiel, vom Wächter geweckt): Controller melden sich jetzt neu.
		_wake_ms = Time.get_ticks_msec()


func _input(event: InputEvent) -> void:
	if _lern.is_valid() and _lernen_input(event):
		get_viewport().set_input_as_handled()
		return
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and not _pad_allowed():
		if event is InputEventJoypadButton:
			_guide_unfocused(event as InputEventJoypadButton)
			_hint_unfocused(event as InputEventJoypadButton)
			# Kam das Loslassen von View oder Start ohne Fokus an (Uzai parkt gerade), blieb die Taste sonst „gedrückt“,
			# und der nächste Druck allein öffnete den Guide als View + Start.
			if event.is_action_released("uz_view", true):
				_view_down = false
			if event.is_action_released("uz_menu", true):
				_menu_down = false
		return
	# Medientasten sind nie Bedienung. Eingespeist (Helfer, Tastatur-Software) tragen sie
	# mitunter die Scan-Nummer einer Buchstabentaste – Pause/Play hätte sonst den Guide geöffnet.
	if event is InputEventKey and (event as InputEventKey).keycode in MEDIA_KEYS:
		return
	if zeiger.input(event):
		get_viewport().set_input_as_handled()
		return
	_track_device(event)
	# Schnellmenü-Taste der Handhelds (oder selbst belegt): wie Guide-Taste halten.
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo() \
			and Handheld.ist_schnelltaste(event, _quick, not Handheld.aktiv.is_empty()):
		if not (game_mode and layers.is_empty()):
			command.emit("quick")
		get_viewport().set_input_as_handled()
		return
	# Stick und Trigger: siehe _poll_analog. Jede kleine Bewegung käme hier sonst als neuer
	# Tastendruck an, und der Fokus würde durch das ganze Menü rasen.
	if event is InputEventJoypadMotion:
		return
	# In Textfeldern tippt die Tastatur Text; nur Enter, Esc und Pfeile hoch/runter steuern.
	if event is InputEventKey and focused() is LineEdit:
		var kc: int = event.keycode
		if not (kc in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_DOWN, KEY_TAB]):
			return
	# Nur echte Bewegung zeigt den Zeiger: Windows meldet auch ohne Berührung eine Mausbewegung,
	# wenn unter dem Zeiger ein Fenster erscheint (nach dem Spiel, Guide, Videoplayer).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN and (event as InputEventMouseMotion).relative.length() > 2.0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Unsichtbarer Zeiger wählt nichts aus (sonst spränge der Fokus bei einer Scheinbewegung).
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 0.5 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		schweben.bewegt((event as InputEventMouseMotion).position)
	# Tab wählt wie am PC das nächste Element (Umschalt: das vorige); Strg + Tab wechselt den
	# Bereich wie Reiter im Browser (sonst Bild↑/Bild↓, 1/3).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if event.ctrl_pressed:
			_fire("lt" if event.shift_pressed else "rt")
		else:
			tab_step(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	# Kontextmenü-Taste und Umschalt + F10: wie ein Rechtsklick „Optionen“.
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_MENU or (event.keycode == KEY_F10 and event.shift_pressed)):
		optionen()
		get_viewport().set_input_as_handled()
		return
	for dir in DIRS:
		if event.is_action_pressed("uz_" + dir, false, true) and not event.is_echo():
			_held[dir] = _uhr + float(Config.get_value("controller.repeat_delay", 0.4)) * 1000.0
			_held_steps[dir] = 0
			_takt_ms = 0
			_rand_dir = ""
			_fire(dir)
			get_viewport().set_input_as_handled()
			return
	# Aufnahme: Share-Taste, oder X, während die Guide-Taste gehalten wird (Clip speichern).
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_MISC1:
			command.emit("capture")
			get_viewport().set_input_as_handled()
			return
		if jb.button_index == JOY_BUTTON_X and Input.is_joy_button_pressed(jb.device, JOY_BUTTON_GUIDE):
			command.emit("capture_chord")
			get_viewport().set_input_as_handled()
			return
	for cmd in ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "guide", "menu", "view", "search"]:
		if event.is_action_pressed("uz_" + cmd, false, true) and not event.is_echo():
			if cmd == "view":
				_view_down = true
				_view_combo = false
				if _menu_down and Config.get_value("controller.guide_combo", true):
					_view_combo = true
					_fire_guide("combo")
			elif cmd == "menu":
				_menu_down = true
				if _view_down and Config.get_value("controller.guide_combo", true):
					_view_combo = true
					_fire_guide("combo")
				else:
					_fire("menu")
			else:
				_fire(cmd)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("uz_" + cmd, true):
			if cmd == "view":
				# Kurz View allein (nicht als Teil von View + Start): öffnet ein Pop-up (Chat).
				if _view_down and not _view_combo:
					_fire("view")
				_view_down = false
			elif cmd == "menu":
				_menu_down = false


func _process(dt: float) -> void:
	# Ruhezustand: Die Wanduhr springt, das Bild dazwischen fehlt – das gilt als Aufwachen.
	var wall := Time.get_unix_time_from_system()
	if _wall_s > 0.0 and wall - _wall_s > 5.0:
		_wake_ms = Time.get_ticks_msec()
	_wall_s = wall
	Raster.pruefen(get_tree().root)
	_step_springs(dt)
	if _a_down:
		_a_hold_step()
	if _lern.is_valid() and Time.get_ticks_msec() > _lern_bis:
		_lernen_ende({}, "zeit")
	_uhr += dt * 1000.0
	var now := _uhr
	for dir in _held.keys():
		if not Input.is_action_pressed("uz_" + dir, true):
			_held.erase(dir)
			continue
		if now >= float(_held[dir]):
			var steps := int(_held_steps.get(dir, 0))
			_held[dir] = naechster_schritt(float(_held[dir]), now, repeat_ms(steps))
			_held_steps[dir] = steps + 1
			_takt_ms = repeat_ms(steps)
			_wiederholt = true
			_fire(dir)
			_wiederholt = false
	if _held.is_empty() and _stick_dir == "":
		_takt_ms = 0
	_poll_analog(now)


## Nächster Schritt beim Halten: auf dem Plan (geplant + Abstand), nicht ab „jetzt“ – sonst
## rundet jeder Schritt auf das nächste Bild auf, und der Takt wird langsamer (60 Hz: 167 statt
## 162 ms). Lag ein Bild so lange, dass der Plan schon vorbei ist, beginnt er neu ab jetzt
## (kein Nachholen mehrerer Schritte auf einmal).
static func naechster_schritt(geplant: float, jetzt: float, abstand: int) -> float:
	var n := geplant + abstand
	return n if n > jetzt else jetzt + abstand


## Takt des Haltens in Sekunden: so lange dauert es bis zum nächsten Schritt, solange eine Richtung
## gehalten wird und schon wiederholt; sonst 0. Das Regal und die Listen gleiten danach gleichmäßig.
func halten_takt() -> float:
	return _takt_ms / 1000.0


func _a_hold_step() -> void:
	var c := _a_down
	if not is_instance_valid(c) or focused() != c:
		_a_down = null
	elif not Input.is_action_pressed("uz_a", true):
		_a_down = null
		activate(c)
	elif Time.get_ticks_msec() - _a_down_at >= A_HOLD_MS:
		_a_down = null
		var cb: Variant = c.get_meta("uz_on_hold_a")
		if cb is Callable and (cb as Callable).is_valid():
			Sfx.play("select")
			_rumble(c)
			(cb as Callable).call()


## Abstand beim Gedrückthalten: anfangs ruhig, nach einigen Schritten etwas schneller.
func repeat_ms(steps: int) -> int:
	# Nie unter 30 ms: Mit 0 (von Hand in der Datei) liefe die Auswahl in jedem Bild einen Schritt weiter.
	var rate := clampf(float(Config.get_value("controller.repeat_rate", 0.12)), 0.03, 1.0)
	var f := 1.35 if steps < 3 else (1.0 if steps < 10 else 0.8)
	return int(rate * f * 1000.0)


## Stick und Trigger abfragen. Der Stick zählt nur in seiner Hauptrichtung (schräg springt
## nichts doppelt), mit Schwelle zum Drücken und kleinerer zum Loslassen. Die Trigger
## schalten genau einmal pro Druck, egal wie lange sie gehalten werden.
func _poll_analog(now: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	if not _pad_allowed():
		_stick_dir = ""
		_trig = { "lt": false, "rt": false }
		return
	var dz := clampf(float(Config.get_value("controller.deadzone", 0.5)), 0.15, 0.9)
	var v := Vector2.ZERO
	var lt := 0.0
	var rt := 0.0
	for id in pads:
		var p := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		if p.length() > v.length():
			v = p
		lt = maxf(lt, Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT))
		rt = maxf(rt, Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT))
	var dir := stick_dir(v, dz, _stick_dir)
	if dir != _stick_dir:
		_stick_dir = dir
		_stick_steps = 0
		_takt_ms = 0
		if dir != "":
			_stick_next = now + float(Config.get_value("controller.repeat_delay", 0.4)) * 1000.0
			_rand_dir = ""
			vom_stick = true
			_fire(dir)
			vom_stick = false
	elif dir != "" and now >= _stick_next:
		# Weit gedrückt geht es etwas schneller als knapp über der Schwelle.
		var push := clampf((v.length() - dz) / maxf(0.05, 1.0 - dz), 0.0, 1.0)
		var ab := int(repeat_ms(_stick_steps) * lerpf(1.3, 1.0, push))
		_stick_next = naechster_schritt(_stick_next, now, ab)
		_stick_steps += 1
		_takt_ms = ab
		_wiederholt = true
		vom_stick = true
		_fire(dir)
		vom_stick = false
		_wiederholt = false
	for t in [["lt", lt], ["rt", rt]]:
		var down: bool = _trig[t[0]]
		var val: float = t[1]
		if not down and val > 0.6:
			_trig[t[0]] = true
			if not (game_mode and layers.is_empty()):
				device = "pad"
			_fire(t[0])
		elif down and val < 0.3:
			_trig[t[0]] = false


## Hauptrichtung des Sticks. Wer schon eine Richtung hält, behält sie bis unter die
## Loslass-Schwelle, damit ein leicht schräger Stick nicht hin und her springt.
static func stick_dir(v: Vector2, dz: float, held: String) -> String:
	var len := v.length()
	if held != "" and len > dz * 0.65:
		var keep := { "up": -v.y, "down": v.y, "left": -v.x, "right": v.x }[held] as float
		if keep > dz * 0.5:
			return held
	if len < dz:
		return ""
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"


func _track_device(event: InputEvent) -> void:
	var kind := ""
	if event is InputEventKey:
		kind = "keys"
	elif event is InputEventJoypadButton:
		kind = "pad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		kind = "pad"
	if kind == "pad" and kind != device:
		_set_pad(event.device)
	set_device(kind)


## Gerät gewechselt (Zeiger meldet mouse und touch): Tastensymbole und Zeiger danach.
func set_device(kind: String) -> void:
	if kind == "" or kind == device:
		return
	device = kind
	if (kind == "pad" or kind == "touch") and Config.get_value("controller.hide_mouse", true):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	device_changed.emit(kind)


func _on_joy_changed(id: int, connected: bool) -> void:
	if connected:
		_set_pad(id)
		var key := _pad_key(id)
		if pad_toast_due(Time.get_ticks_msec(), _wake_ms, _pads_seen.has(key)):
			Toasts.show_toast("Controller verbunden", pad_name, "controller", { "quiet": true, "ms": 2500 })
		_pads_seen[key] = true
	device_changed.emit(device)


## Controller-Meldung: Beim Start und Aufwachen melden sich alle Controller (neu) an – das muss
## niemand sehen. Gemeldet wird nur ein Controller, der in dieser Sitzung noch nicht da war, und
## nicht kurz nach dem Start oder dem Aufwachen (Ruhezustand, zurück aus dem Spiel). Dann leise:
## ohne Klang, nicht in der Mitteilungsliste.
const PAD_TOAST_START_MS := 15000
const PAD_TOAST_WAKE_MS := 15000

var _pads_seen := {}               ## Controller dieser Sitzung (Name und GUID)
var _wake_ms := -PAD_TOAST_WAKE_MS ## zuletzt aufgewacht (Uhr seit Start, ms)
var _wall_s := 0.0                 ## Wanduhr im letzten Bild (Sprung = PC war im Ruhezustand)


static func pad_toast_due(now_ms: int, wake_ms: int, seen: bool) -> bool:
	if seen or now_ms < PAD_TOAST_START_MS:
		return false
	return now_ms - wake_ms >= PAD_TOAST_WAKE_MS


func _pad_key(id: int) -> String:
	return "%s|%s" % [Input.get_joy_name(id), Input.get_joy_guid(id)]


## Welche Tastensymbole angezeigt werden: keys, xbox, ps, nintendo, deck, handheld. Mit Touch die
## des Controllers, wenn einer da ist (Handhelds), sonst die der Tastatur.
func glyph_set() -> String:
	var s := str(Config.get_value("controller.glyphs", "auto"))
	if s != "auto":
		return s
	if device != "pad" and not (device == "touch" and not Input.get_connected_joypads().is_empty()):
		return "keys"
	var hh := Handheld.tasten_fuer(Handheld.aktiv, pad_name, pad_vid)
	return hh if hh != "" else PadCheck.glyphs_for(pad_name, pad_vid)


func _set_pad(id: int) -> void:
	pad_name = Input.get_joy_name(id)
	pad_vid = PadsS.vid_of(id)


## Rechtsklick, langes Tippen, Kontextmenü-Taste: was unten bei Y steht (Optionen, Favorit …);
## steht dort nichts und ist ein Spiel gewählt, dessen Optionen (wie Menü). true = etwas getan.
func optionen() -> bool:
	for h in HintBar.collect():
		if str(h[0]) == "y":
			_fire("y")
			return true
	var f := active()
	if f and f.get("game") is Dictionary and not (f.get("game") as Dictionary).is_empty():
		_fire("menu")
		return true
	if f:
		Sfx.play("bump", 1.0, f)
	return false


## Tab: das nächste (d = 1) bzw. vorige Element in Lesereihenfolge – Zeilen von oben nach unten,
## darin von links nach rechts. Ebenen mit eigener Auswahl bekommen rechts/links.
func tab_step(d: int) -> void:
	var all := focusables(scope_root()).filter(func(c: Control) -> bool: return Zeiger._alpha(c) > 0.05)
	if all.size() <= 1:
		_fire("right" if d > 0 else "left")
		return
	var order := reading_order(all)
	var i := order.find(focused())
	focus(order[posmod(i + d, order.size())] if i >= 0 else order[0])


## Elemente in Lesereihenfolge: was sich senkrecht überdeckt, steht in einer Zeile.
static func reading_order(list: Array) -> Array:
	var by_y := list.duplicate()
	by_y.sort_custom(func(a: Control, b: Control) -> bool: return a.get_global_rect().position.y < b.get_global_rect().position.y)
	var lines: Array = []
	for c: Control in by_y:
		var r := c.get_global_rect()
		var put := false
		for ln in lines:
			if r.get_center().y >= float(ln[0]) and r.get_center().y <= float(ln[1]):
				(ln[2] as Array).append(c)
				put = true
				break
		if not put:
			lines.append([r.position.y, r.end.y, [c]])
	var out: Array = []
	for ln in lines:
		var row: Array = ln[2]
		row.sort_custom(func(a: Control, b: Control) -> bool: return a.get_global_rect().position.x < b.get_global_rect().position.x)
		out.append_array(row)
	return out


## Nächste Taste (oder Controller-Knopf) belegen: cb(belegung: Dictionary, grund: String) mit
## grund "" (belegt), "belegt" (Uzai braucht sie schon), "abbruch" (Esc/B) oder "zeit".
func lernen(cb: Callable, sec := 8.0) -> void:
	_lern = cb
	_lern_bis = Time.get_ticks_msec() + int(sec * 1000.0)


func _lernen_input(e: InputEvent) -> bool:
	if not (e is InputEventKey or e is InputEventJoypadButton):
		return e is InputEventMouseButton
	if not e.is_pressed() or e.is_echo():
		return true
	if (e is InputEventKey and (e as InputEventKey).keycode == KEY_ESCAPE) or e.is_action_pressed("uz_b", false, true):
		_lernen_ende({}, "abbruch")
		return true
	var b := Handheld.belegung_aus(e)
	_lernen_ende(b, "" if not b.is_empty() else "belegt")
	return true


func _lernen_ende(b: Dictionary, grund: String) -> void:
	var cb := _lern
	_lern = Callable()
	if cb.is_valid():
		cb.call(b, grund)


func _fire(cmd: String) -> void:
	if game_mode and layers.is_empty() and cmd != "guide":
		return
	if cmd != "guide" and cmd != "view" and _holding():
		if cmd != "a" and _held_cmds.size() < 8:
			_held_cmds.append(cmd)
		return
	if cmd in DIRS:
		# Ebenen ohne Auswahl (Videoplayer: hoch/runter Lautstärke, links/rechts spulen) bekommen
		# die Richtung direkt – unabhängig davon, wo der Fokus gerade steht. Vorher ging der erste
		# Druck nach einem Fokusverlust nur ins Zurückholen des Fokus und änderte nichts.
		var tl := top_layer()
		if tl and tl.has_method("nav_dir") and tl.call("nav_dir", cmd):
			return
		move(cmd)
		return
	# View gehört den Pop-ups (Nachricht öffnen), egal welche Ebene offen ist.
	if cmd == "view":
		command.emit(cmd)
		return
	var cur := active()
	if cmd == "a" and cur:
		if cur.has_meta("uz_on_hold_a") and Input.is_action_pressed("uz_a", true):
			_a_down = cur
			_a_down_at = Time.get_ticks_msec()
			return
		activate(cur)
		return
	if cur and (cmd == "x" or cmd == "y") and cur.has_meta("uz_on_" + cmd):
		var cb: Callable = cur.get_meta("uz_on_" + cmd)
		if cb.is_valid():
			var vor: Variant = _klang_marke()
			cb.call()
			_klang_danach("select", vor)
			return
	# B gehört zuerst dem gewählten Element, wenn es gerade selbst etwas offen hat (Regler beim
	# Einstellen: B beendet das Einstellen, statt zurückzugehen).
	if cmd == "b" and cur and cur.has_method("nav_b") and cur.call("nav_b"):
		return
	var top := top_layer()
	if top and top.has_method("nav_command") and top.call("nav_command", cmd):
		return
	command.emit(cmd)


## Linksklick auf ein wählbares Element (für gui_input): Ist es schon gewählt, löst der Klick es
## aus, sonst holt er nur die Auswahl – überall gleich. Stand vorher wortgleich in 46 Dateien.
func klick(c: Control, e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if c.has_focus():
			activate(c)
		else:
			c.grab_focus()
		c.accept_event()


## Bestätigen. Der Klang des Drucks kommt nach der Handlung: Öffnet sie eine Ebene, klingt deren
## „open“ (vor dem Aufbau hier schon gespielt) statt „select“ davor und „open“ danach – egal, wie
## lange der Aufbau dauert (sonst war „select“ bei schweren Ebenen schon verklungen und nicht mehr
## zu ersetzen: Klack, dann Öffnen). Spielt die Handlung selbst einen Klang, bleibt „select“ still.
func activate(c: Control) -> void:
	if c.has_method("activate"):
		var name := str(c.call("activate_sound")) if c.has_method("activate_sound") else "select"
		_rumble(c)
		_press(c)
		var vor: Variant = _klang_marke()
		c.call("activate")
		_klang_danach(name, vor)
	elif c is BaseButton and not (c as BaseButton).disabled:
		_rumble(c)
		_press(c)
		var vor: Variant = _klang_marke()
		(c as BaseButton).pressed.emit()
		_klang_danach("select", vor)


## Der zuletzt gespielte Klang (Eintrag in Sfx._recent), um zu sehen, ob eine Handlung selbst klang.
func _klang_marke() -> Variant:
	var r: Variant = Sfx.get("_recent")
	return (r as Array).back() if r is Array and not (r as Array).is_empty() else null


func _klang_danach(name: String, vor: Variant) -> void:
	if _klang_marke() == vor:
		Sfx.play(name)


## Kurzes Eindrücken beim Bestätigen (Cover haben ihr eigenes Wachsen und bleiben aus).
func _press(c: Control) -> void:
	if not c.is_inside_tree():
		return
	if c.has_method("press_feedback"):
		c.call("press_feedback")
		return
	var rest: Vector2 = c.get_meta("uz_rest_scale", c.scale)
	c.set_meta("uz_rest_scale", rest)
	if c.pivot_offset == Vector2.ZERO:
		c.pivot_offset = c.size * 0.5
	# Takt „Antwort“: ein, dann in T_ORT zurück (Kurve „Ankommen“, ohne Nachfedern).
	var tw := U.ankommen(c, U.T_ORT, "uz_press")
	tw.tween_property(c, "scale", rest * (1.0 if U.reduziert() else 0.96), U.T_ANTWORT)
	tw.tween_property(c, "scale", rest, U.T_ORT)
	tw.tween_callback(func() -> void: c.remove_meta("uz_rest_scale"))


## Impuls beim Bestätigen: nur bei Haupthandlungen (haupt), als Pads-Impuls „auswahl“ (Spielen
## bringt ihn schon mit dem Klang „launch“).
func _rumble(c: Control = null) -> void:
	if device == "pad" and Config.get_value("controller.vibration", true) and haupt(c):
		Pads.pulse("auswahl")


## Haupthandlung (Bestätigen, Kaufen, Installieren): Meta "uz_haupt" am Element (Liste.knopf
## setzt sie für den Hauptknopf).
static func haupt(c: Control) -> bool:
	return c != null and is_instance_valid(c) and bool(c.get_meta("uz_haupt", false))


# --- Ebenen (Overlays) ---------------------------------------------------------

func push_layer(layer: Control, first: Control = null) -> void:
	var prev := focused()
	layer.set_meta("uz_prev_focus", prev)
	layer.set_meta("uz_prev_key", str(prev.get_meta("uz_key", "")) if prev else "")
	layers.append(layer)
	var f := first if first and first.is_visible_in_tree() else default_in(layer)
	if f:
		focus(f, true)
	release_hold(layer)


## Eingaben warten, bis layer oben liegt (siehe _opening).
func hold_for(layer: Control) -> void:
	_opening = weakref(layer)
	_opening_ms = Time.get_ticks_msec()


## layer liegt oben (oder geht doch nicht auf): Wartendes der Reihe nach ausführen.
func release_hold(layer: Control) -> void:
	if _opening == null or _opening.get_ref() != layer:
		return
	_opening = null
	var q := _held_cmds
	_held_cmds = []
	if not q.is_empty():
		_replay.call_deferred(q)


func _replay(q: Array) -> void:
	for c in q:
		_fire(str(c))


## Wartet gerade eine Ebene? Spätestens nach HOLD_MS (oder wenn sie weg ist) nicht mehr – dann
## kommt erst das Wartende dran, danach der neue Befehl.
func _holding() -> bool:
	if _opening == null:
		return false
	var l: Variant = _opening.get_ref()
	if l == null or not is_instance_valid(l) or not (l as Node).is_inside_tree() or Time.get_ticks_msec() - _opening_ms > HOLD_MS:
		var q := _held_cmds
		_opening = null
		_held_cmds = []
		_replay(q)
		return false
	return true


func pop_layer(layer: Control) -> void:
	var idx := layers.find(layer)
	if idx < 0:
		return
	layers.remove_at(idx)
	_restore_focus(layer)
	# Auch wenn der Fokus gar nicht weg war (Ebene ohne Auswahl): Hinweise unten neu lesen.
	focus_moved.emit(focused())


func _restore_focus(layer: Control) -> void:
	var prev: Variant = (layer.get_meta("uz_prev_focus") if layer.has_meta("uz_prev_focus") else null)
	if is_instance_valid(prev) and prev is Control and prev.is_visible_in_tree() and scope_root().is_ancestor_of(prev):
		focus(prev, true)
	else:
		var key := str(layer.get_meta("uz_prev_key", ""))
		if key != "":
			for c in focusables(scope_root()):
				if str(c.get_meta("uz_key", "")) == key:
					focus(c, true)
					return
		var d := default_in(scope_root())
		if d:
			focus(d, true)


func top_layer() -> Control:
	while not layers.is_empty() and not is_instance_valid(layers[layers.size() - 1]):
		layers.pop_back()
	return null if layers.is_empty() else layers[layers.size() - 1]


func scope_root() -> Control:
	var t := top_layer()
	return t if t else root_scope


# --- Fokus ---------------------------------------------------------------------

func focused() -> Control:
	return get_viewport().gui_get_focus_owner()


## Das gewählte Element, sofern es zur obersten Ebene gehört. Hat eine Ebene nichts zum Wählen
## (leere Seitenleiste), bleibt der Fokus dahinter stehen – A, X und Y dürfen dann nichts
## hinter der Ebene auslösen, und die Hinweise unten zeigen nur, was die Ebene kann.
func active() -> Control:
	var f := focused()
	if f == null:
		return null
	var top := top_layer()
	if top and top != f and not top.is_ancestor_of(f):
		return null
	# Ein Bereich, der gerade hinausgleitet (uz_skip), löst nichts mehr aus: A in den ersten
	# Bildern nach LT/RT öffnete sonst ein Cover des alten Bereichs.
	var n: Node = f
	while n:
		if n is Control and (n as Control).has_meta("uz_skip"):
			return null
		n = n.get_parent()
	return f


func focus(c: Control, silent := false) -> void:
	if c == null or not is_instance_valid(c):
		return
	# Liegt eine Ebene oben, gehört ihr der Fokus. Will etwas dahinter ihn haben (verzögert nach
	# einem Bereichswechsel oder Neuaufbau), bekommt es ihn erst, wenn die Ebene zugeht – sonst
	# stand die Auswahl hinter einem Dialog, und A drückte ins Leere.
	var top := top_layer()
	if top != null and top != c and not top.is_ancestor_of(c):
		top.set_meta("uz_prev_focus", c)
		top.set_meta("uz_prev_key", str(c.get_meta("uz_key", "")))
		return
	if not silent and c != focused():
		Sfx.play("move", 1.0, c)
	c.grab_focus()


func focusables(root: Control) -> Array[Control]:
	var out: Array[Control] = []
	if root and root.is_visible_in_tree():
		_collect(root, out)
	return out


func _collect(n: Node, out: Array[Control]) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			if not c.visible or c.has_meta("uz_skip"):
				continue
			if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				out.append(c)
			_collect(c, out)


## Erster Fokus in root: uz_prefer (gerade dringender, z. B. Steams Overlay nach einer
## Einladung) vor uz_default, sonst das erste Element.
func default_in(root: Control) -> Control:
	if root == null:
		return null
	var all := focusables(root)
	for c in all:
		if c.has_meta("uz_prefer"):
			return c
	for c in all:
		if c.has_meta("uz_default"):
			return c
	return all[0] if not all.is_empty() else null


func _row_node(c: Node) -> Control:
	var n := c.get_parent()
	while n and n != scope_root():
		if n is Control and n.has_meta("uz_row"):
			return n
		n = n.get_parent()
	return null


func _group_node(c: Node) -> Control:
	var n := c
	while n and n != scope_root():
		if n is Control and n.has_meta("uz_group"):
			return n
		n = n.get_parent()
	return null


static func _gap(a1: float, a2: float, b1: float, b2: float) -> float:
	return maxf(0.0, maxf(a1, b1) - minf(a2, b2))


func move(dir: String) -> void:
	# Raster mit eigener Navigation (Bibliothek): ohne erst alle Elemente einzusammeln.
	var now := focused()
	if now and now.has_meta("uz_grid_nav") and now.is_visible_in_tree() and not now.has_meta("uz_skip"):
		var gm: Variant = now.get_meta("uz_grid_nav")
		if gm is Callable and (gm as Callable).is_valid() and bool((gm as Callable).call(now, dir)):
			return
	var root := scope_root()
	var cands := focusables(root)
	if cands.is_empty():
		return
	var cur := focused()
	if cur == null or not cands.has(cur):
		focus(default_in(root))
		return
	if (dir == "left" or dir == "right") and cur.has_method("nav_lr") and cur.call("nav_lr", -1 if dir == "left" else 1):
		return
	if (dir == "up" or dir == "down") and cur.has_method("nav_ud") and cur.call("nav_ud", -1 if dir == "up" else 1):
		return
	var a := cur.get_global_rect()
	# Knopfleisten (uz_row): links/rechts bleibt in der Leiste, solange dort etwas kommt – auch wenn
	# ein Element der Reihe darüber näher liegt (sonst kam man z. B. nie auf „Übertragen“ ganz links).
	if dir == "left" or dir == "right":
		var row := _row_node(cur)
		if row:
			var pick: Control = null
			var near := INF
			for e in cands:
				if e == cur or not row.is_ancestor_of(e):
					continue
				var rb := e.get_global_rect()
				var d := (rb.position.x - a.end.x) if dir == "right" else (a.position.x - rb.end.x)
				if d > -12.0 and d < near:
					near = d
					pick = e
			if pick:
				focus(pick)
				return
			# „fest“: Am Ende der Leiste ist Schluss – sonst ging es von ihrem letzten Knopf in eine Reihe
			# darüber oder darunter, die weiter nach rechts reicht (Steam-Seiten unter „Über das Spiel“).
			if str(row.get_meta("uz_row")) == "fest":
				_bump(cur, dir)
				return
	# Liegt die Auswahl in einer Liste, die hoch/runter rollt, zählt für Elemente außerhalb (Reiter
	# oben, Leiste unten) der ganze Inhalt dazwischen mit – auch was gerade hinausgerollt ist. Sonst
	# lag die Reiterleiste nach dem Runterrollen „näher“ als die Reihe darüber, und hoch sprang
	# am Kopfteil (Profil-Banner, Shop-Rampenlicht) vorbei direkt nach oben.
	var vs := _v_scroller(cur) if dir == "up" or dir == "down" else null
	var vs_rect := vs.get_global_rect() if vs else Rect2()
	var vs_above := float(vs.scroll_vertical) if vs else 0.0
	var vs_below := maxf(0.0, vs.get_v_scroll_bar().max_value - vs.size.y - vs_above) if vs else 0.0
	# Umlauf (uz_umlauf, die Leiste des Guide): hoch und runter bleiben in diesem Kasten, und über
	# den Rand hinaus geht es am anderen Ende weiter (_umlauf_ziel). Von außerhalb einer rollenden
	# Liste zählt dort nur, was in ihr zu sehen ist – sonst ging es von der festen Leiste unten
	# „runter“ in Zeilen, die gerade hinausgerollt sind.
	var um := _umlauf_node(cur) if dir == "up" or dir == "down" else null
	var best: Control = null
	var best_score := INF
	for e in cands:
		if e == cur or (um and (not um.is_ancestor_of(e) or _hinausgerollt(e, cur))):
			continue
		var b := e.get_global_rect()
		if vs and not vs.is_ancestor_of(e):
			if dir == "up" and b.end.y <= vs_rect.position.y + 12.0:
				b.position.y -= vs_above
			elif dir == "down" and b.position.y >= vs_rect.end.y - 12.0:
				b.position.y += vs_below
		var main := 0.0
		var cross := 0.0
		match dir:
			"right":
				if b.position.x < a.end.x - 12 and not (b.position.x > a.position.x + a.size.x * 0.6):
					continue
				main = b.position.x - a.end.x
				cross = _gap(a.position.y, a.end.y, b.position.y, b.end.y) + absf(b.get_center().y - a.get_center().y) * 0.15
			"left":
				if b.end.x > a.position.x + 12 and not (b.end.x < a.end.x - a.size.x * 0.6):
					continue
				main = a.position.x - b.end.x
				cross = _gap(a.position.y, a.end.y, b.position.y, b.end.y) + absf(b.get_center().y - a.get_center().y) * 0.15
			"down":
				if b.position.y < a.end.y - 12 and not (b.position.y > a.position.y + a.size.y * 0.6):
					continue
				main = b.position.y - a.end.y
				cross = _gap(a.position.x, a.end.x, b.position.x, b.end.x) + absf(b.position.x - a.position.x) * 0.08
			"up":
				if b.end.y > a.position.y + 12 and not (b.end.y < a.end.y - a.size.y * 0.6):
					continue
				main = a.position.y - b.end.y
				cross = _gap(a.position.x, a.end.x, b.position.x, b.end.x) + absf(b.position.x - a.position.x) * 0.08
		var score := maxf(0.0, main) + cross * 2.2
		if score < best_score:
			best_score = score
			best = e
	# Am Rand: mit Umlauf ans andere Ende – nur bei einem neuen Druck; wer hält, bleibt am Rand stehen.
	if best == null and um and not _wiederholt:
		best = _umlauf_ziel(um, cands, cur, dir)
	if best == null:
		_bump(cur, dir)
		return
	var from_g := _group_node(cur)
	var to_g := _group_node(best)
	if to_g and to_g != from_g:
		if to_g.get_meta("uz_enter", "") == "sel":
			for c in cands:
				if to_g.is_ancestor_of(c) and c.get_meta("uz_selected", false):
					best = c
					break
		elif to_g.has_meta("uz_mem"):
			var m: Variant = _gmem.get(str(to_g.get_meta("uz_group")))
			if is_instance_valid(m) and m is Control and cands.has(m):
				best = m
			else:
				for c in cands:
					if to_g.is_ancestor_of(c) and c.has_meta("uz_entry"):
						best = c
						break
	focus(best)


## Der Kasten um c, in dem hoch/runter umläuft (Meta uz_umlauf), oder null.
func _umlauf_node(c: Node) -> Control:
	var n := c.get_parent()
	var root := scope_root()
	while n:
		if n is Control and n.has_meta("uz_umlauf"):
			return n
		if n == root:
			break
		n = n.get_parent()
	return null


## Steht e in einer rollenden Liste, in der cur nicht steht, und ist dort gerade nicht zu sehen?
func _hinausgerollt(e: Control, cur: Control) -> bool:
	var sc := _v_scroller(e)
	if sc == null or sc.is_ancestor_of(cur):
		return false
	var r := sc.get_global_rect()
	var b := e.get_global_rect()
	return b.end.y <= r.position.y + 12.0 or b.position.y >= r.end.y - 12.0


## Umlauf: das Ziel am anderen Ende des Kastens – bei „hoch“ die unterste Reihe, bei „runter“ die
## oberste, darin das Element, das waagerecht am nächsten liegt. Was in einer rollenden Liste steht,
## zählt mit seinem Platz im ganzen Inhalt; was fest darunter oder darüber steht (Schnellleiste, Kopf),
## bleibt darunter bzw. darüber, auch wenn die Liste gerade weit gerollt ist.
func _umlauf_ziel(um: Control, cands: Array[Control], cur: Control, dir: String) -> Control:
	var drin: Array[Control] = []
	var roller: Array[ScrollContainer] = []
	for e in cands:
		if e != cur and um.is_ancestor_of(e):
			drin.append(e)
			var sc := _v_scroller(e)
			if sc and not roller.has(sc):
				roller.append(sc)
	var lagen: Array[Rect2] = []
	var rand_i := -1
	for i in drin.size():
		var b := drin[i].get_global_rect()
		for sc in roller:
			if sc.is_ancestor_of(drin[i]):
				continue
			var r := sc.get_global_rect()
			if b.position.y >= r.end.y - 12.0:
				b.position.y += maxf(0.0, sc.get_v_scroll_bar().max_value - sc.size.y - float(sc.scroll_vertical))
			elif b.end.y <= r.position.y + 12.0:
				b.position.y -= float(sc.scroll_vertical)
		lagen.append(b)
		if rand_i < 0 or (dir == "up" and b.end.y > lagen[rand_i].end.y) or (dir == "down" and b.position.y < lagen[rand_i].position.y):
			rand_i = i
	if rand_i < 0:
		return null
	var a := cur.get_global_rect()
	var best: Control = null
	var nah := INF
	for i in drin.size():
		if minf(lagen[i].end.y, lagen[rand_i].end.y) - maxf(lagen[i].position.y, lagen[rand_i].position.y) <= 4.0:
			continue
		var d := absf(lagen[i].position.x - a.position.x)
		if d < nah:
			nah = d
			best = drin[i]
	return best


## B aus dem Inhalt nach oben: die Seite um c rollt wieder ganz nach oben (Kopf mit Banner bzw.
## Rampenlicht sichtbar). true, wenn c in einer solchen Seite lag und sie gerollt war.
func scroll_page_top(c: Control) -> bool:
	var sc := _v_scroller(c) if c else null
	var hit := false
	while sc:
		if sc.scroll_vertical > 0:
			_scroll_to(sc, "scroll_vertical", 0.0, false)
			hit = true
		sc = _v_scroller(sc)
	return hit


## Die nächste Liste um c, die hoch/runter rollt (Reihen, die nur seitlich rollen, zählen nicht).
func _v_scroller(c: Control) -> ScrollContainer:
	var n := c.get_parent()
	while n and n != scope_root():
		if n is ScrollContainer and (n as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return n
		n = n.get_parent()
	return null


## Rand: die Auswahl stößt genau einmal an (6 px, dumpfer Klang, kurzer Impuls) – beim Druck bzw.
## beim ersten Stoß während des Haltens. Wer weiter hält, bekommt Ruhe; nach dem Loslassen stößt
## der nächste Druck wieder an.
func _bump(c: Control, dir: String) -> void:
	if _wiederholt and _rand_dir == dir:
		return
	_rand_dir = dir
	Sfx.play("bump", 1.0, c, dir)
	rand.emit(c, dir)
	var w := U.weg_px(U.W_ANSTOSS)
	if w <= 0.0:
		return
	var off := { "left": Vector2(-w, 0), "right": Vector2(w, 0), "up": Vector2(0, -w), "down": Vector2(0, w) }[dir] as Vector2
	# Reihen, die ihre Elemente jedes Bild selbst setzen (Regal der Startseite), stoßen als Ganzes an:
	# Die Lage eines Covers mitten im Gleiten zu merken und danach wiederherzustellen, ließ es
	# neben dem Bild stehen (erstes Spiel verschwand nach schnellem Wischen bis an den Anfang).
	var host := c.get_parent() as Control
	if host and host.has_meta("uz_bump_host"):
		c = host
	# Ruhelage merken: ein zweiter Anschlag mitten im ersten darf nicht von der verschobenen Lage starten.
	var base: Vector2 = c.get_meta("uz_bump_base", c.position)
	c.set_meta("uz_bump_base", base)
	var tw := U.ankommen(c, U.T_ANTWORT, "uz_bump")
	tw.tween_property(c, "position", base + off, U.T_ANTWORT / 3.0)
	tw.tween_property(c, "position", base, U.T_ANTWORT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: c.remove_meta("uz_bump_base"))


## Gemerkte Auswahl der Gruppen (uz_mem) in root vergessen: beim Betreten eines Bereichs fängt
## jede Reihe wieder vorn an.
func forget_in(root: Control) -> void:
	for k in _gmem.keys():
		var c: Variant = _gmem[k]
		if not is_instance_valid(c) or (root and (root == c or root.is_ancestor_of(c))):
			_gmem.erase(k)


func _on_focus_changed(c: Control) -> void:
	if c == null:
		return
	var g := _group_node(c)
	if g:
		_gmem[str(g.get_meta("uz_group"))] = c
	reveal(c)
	focus_moved.emit(c)


## Scrollt alle umgebenden ScrollContainer weich, bis das Element sichtbar ist.
## Reihen mit Meta "uz_anchor" halten das fokussierte Element links (wie bei Konsolen).
func reveal(c: Control, instant := false) -> void:
	var n := c.get_parent()
	while n:
		if n is ScrollContainer:
			_reveal_in(n as ScrollContainer, c, instant)
		n = n.get_parent()


func _reveal_in(sc: ScrollContainer, c: Control, instant: bool) -> void:
	var sr := sc.get_global_rect()
	var r := Rect2(c.global_position, c.size)
	var pad: float = sc.get_meta("uz_pad", 80.0)
	if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var cur := float(sc.scroll_horizontal)
		var target := cur
		if sc.has_meta("uz_anchor"):
			target = cur + (r.position.x - sr.position.x) - float(sc.get_meta("uz_anchor"))
		elif r.position.x < sr.position.x + pad:
			target = cur + (r.position.x - sr.position.x - pad)
		elif r.end.x > sr.end.x - pad:
			target = cur + (r.end.x - sr.end.x + pad)
		var maxv := maxf(0.0, sc.get_h_scroll_bar().max_value - sc.size.x)
		_scroll_to(sc, "scroll_horizontal", clampf(target, 0.0, maxv), instant)
	if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var cur_v := float(sc.scroll_vertical)
		var target_v := cur_v
		var pad_v: float = sc.get_meta("uz_pad_v", 120.0)
		var top: Variant = sc.get_meta("uz_top_node") if sc.has_meta("uz_top_node") else null
		if top is Control and is_instance_valid(top) and (top == c or (top as Control).is_ancestor_of(c)):
			# Kopfbereich (etwa die Spielseite mit dem großen Bild): ganz nach oben, wie beim Öffnen.
			target_v = 0.0
		elif _top_row_in(sc, c, cur_v):
			# Oberste Reihe der Liste: ganz nach oben, damit der Kopf darüber (Banner, Rampenlicht,
			# Überschrift) wieder ganz zu sehen ist – nicht nur so weit, dass die Reihe passt.
			target_v = 0.0
		elif r.position.y < sr.position.y + pad_v:
			target_v = cur_v + (r.position.y - sr.position.y - pad_v)
		elif r.end.y > sr.end.y - pad_v:
			target_v = cur_v + (r.end.y - sr.end.y + pad_v)
		var maxv_v := maxf(0.0, sc.get_v_scroll_bar().max_value - sc.size.y)
		_scroll_to(sc, "scroll_vertical", clampf(target_v, 0.0, maxv_v), instant)


## c gehört zur obersten Reihe in sc (darüber nichts mehr zum Wählen) und passt bei ganz nach
## oben gerollter Liste noch ins Bild.
func _top_row_in(sc: ScrollContainer, c: Control, cur_v: float) -> bool:
	var top := c.global_position.y - sc.global_position.y + cur_v
	if top + c.size.y > sc.size.y - 20.0:
		return false
	for e in focusables(sc):
		if e.global_position.y < c.global_position.y - 24.0:
			return false
	return true


## Mausrad: weich um delta Pixel weiter, auch mehrere Rastungen schnell hintereinander (das Ziel
## wächst, die Feder nimmt die Geschwindigkeit mit).
func scroll_by(sc: ScrollContainer, prop: String, delta: float) -> void:
	var key := "%d:%s" % [sc.get_instance_id(), prop]
	var base := float(sc.get(prop))
	if _springs.has(key):
		base = float(_springs[key].target)
	var bar: ScrollBar = sc.get_h_scroll_bar() if prop == "scroll_horizontal" else sc.get_v_scroll_bar()
	var maxv := maxf(0.0, bar.max_value - (sc.size.x if prop == "scroll_horizontal" else sc.size.y))
	_scroll_to(sc, prop, clampf(base + delta, 0.0, maxv), false)


## Ziehen und Wischen setzen die Liste selbst: laufende Federn geben nach.
func stop_scroll(sc: ScrollContainer, prop: String) -> void:
	var key := "%d:%s" % [sc.get_instance_id(), prop]
	_springs.erase(key)
	_bruch(sc, prop, 0.0)
	_bruch_planen()
	if _tweens.has(key) and is_instance_valid(_tweens[key]):
		(_tweens[key] as Tween).kill()
	_tweens.erase(key)


## Scrollen mit einer kleinen Feder pro Liste: Ein neues Ziel übernimmt die laufende
## Geschwindigkeit, statt neu anzusetzen. Beim Halten gleitet die Liste dadurch gleichmäßig,
## ohne das Anfahren und Abbremsen bei jedem Schritt. Wiederholt das Halten, gleitet zudem das
## Ziel selbst im Takt des Haltens zum neuen Wert (statt zu springen), so bleibt das Tempo gleich.
## „Animationen reduzieren“: sofort am Ziel.
func _scroll_to(sc: ScrollContainer, prop: String, value: float, instant: bool) -> void:
	var key := "%d:%s" % [sc.get_instance_id(), prop]
	if _tweens.has(key) and is_instance_valid(_tweens[key]):
		(_tweens[key] as Tween).kill()
	_tweens.erase(key)
	var now := float(sc.get(prop))
	if instant or U.reduziert() or absf(now - value) < 1.0 and not _springs.has(key):
		_springs.erase(key)
		sc.set(prop, int(round(value)))
		_bruch(sc, prop, 0.0)
		_bruch_planen()
		return
	var sp: Dictionary = _springs.get(key, {})
	if sp.is_empty() or absf(float(sp.get("set", now)) - now) > 2.0:
		# Neu, oder jemand anderes hat gescrollt (Maus, Neuaufbau): von dort aus weiter.
		sp = { "sc": weakref(sc), "prop": prop, "pos": now, "vel": 0.0, "at": -1e9 }
	# Schritte dicht hintereinander (Halten): weichere Feder, gleichmäßiges Gleiten.
	sp["omega"] = U.SPRING_HOLD if _uhr - float(sp.get("at", -1e9)) < 260.0 else U.SPRING
	sp["at"] = _uhr
	var takt := halten_takt()
	if takt > 0.0:
		sp["z0"] = _spring_ziel(sp) if sp.has("target") else now
		sp["zt"] = 0.0
		sp["zd"] = takt
	else:
		sp.erase("zd")
	sp["target"] = value
	sp["set"] = now
	_springs[key] = sp


## Ziel einer Feder jetzt: beim Halten auf dem Weg vom alten zum neuen Wert (gleitendes Ziel).
static func _spring_ziel(sp: Dictionary) -> float:
	if not sp.has("zd") or float(sp.zt) >= float(sp.zd):
		return float(sp.target)
	var a := clampf(float(sp.zt) / maxf(float(sp.zd), 0.001), 0.0, 1.0)
	return lerpf(float(sp.z0), float(sp.target), a)


var _springs := {}


func _step_springs(dt: float) -> void:
	if _springs.is_empty():
		return
	dt = minf(dt, 0.1)
	for key in _springs.keys():
		var sp: Dictionary = _springs[key]
		var sc := (sp.sc as WeakRef).get_ref() as ScrollContainer
		if sc == null or not sc.is_inside_tree():
			_springs.erase(key)
			continue
		var prop: String = sp.prop
		var cur := float(sc.get(prop))
		if absf(cur - float(sp.set)) > 2.0:
			# Von außen verstellt: die Feder gibt nach.
			_springs.erase(key)
			_bruch(sc, prop, 0.0)
			continue
		if sp.has("zd"):
			sp.zt = float(sp.zt) + dt
		var target := _spring_ziel(sp)
		var st := Liste.feder_px(float(sp.pos), float(sp.vel), target, dt, float(sp.get("omega", U.SPRING)))
		sp.pos = st.x
		sp.vel = st.y
		var ramp_da := not sp.has("zd") or float(sp.zt) >= float(sp.zd)
		if ramp_da and absf(st.x - target) < Raster.schritt * 0.5 and absf(st.y) < 4.0:
			sc.set(prop, int(round(target)))
			_bruch(sc, prop, 0.0)
			_springs.erase(key)
			continue
		_lage_setzen(sc, prop, st.x)
		# Am Rand klemmt der Container selbst: das gilt dann als gesetzt.
		sp.set = float(sc.get(prop))
	_bruch_planen()


## --- Bildlauf feiner als ganze Punkte -------------------------------------------------------------
## Ein ScrollContainer rollt nur in ganzen Punkten (scroll_horizontal/-vertical sind ganze Zahlen; auch ein
## Bruchteil im Rollbalken wird abgeschnitten – nachgesehen). An einem 4K-Fernseher sind das 2 Bildpunkte, und
## eine Feder, die je Bild um 3,4 Punkte weiterrückt, sprang 3, 3, 4, 3 … Darum steht der ganze Teil im Container
## und der Rest (ein Vielfaches eines Bildpunkts, Raster.schritt) als Verschiebung des Inhalts beim RenderingServer.
## Die Lage der Knoten selbst bleibt ganzzahlig (Auswahl, Maus und Rechnungen wie bisher). Godot schreibt die Lage
## eines Knotens nur neu, wenn sie sich ändert; das Einordnen des Containers läuft verzögert (call_deferred) –
## darum setzt _bruch_anwenden die Verschiebung erst danach, einmal je Bild für alle Listen.
var _bruch_offen: Array[WeakRef] = []
var _bruch_geplant := false


## Lage x (Punkte, Kommazahl) einer Liste: ganzer Teil in den Container, Rest als Verschiebung.
func _lage_setzen(sc: ScrollContainer, prop: String, x: float) -> void:
	if Raster.schritt >= 1.0:
		sc.set(prop, int(round(x)))
		_bruch(sc, prop, 0.0)
		return
	var q := Raster.rund(x)
	var ganz := floorf(q)
	sc.set(prop, int(ganz))
	# Am Rand geklemmt: dort gibt es keinen Rest.
	_bruch(sc, prop, q - ganz if float(sc.get(prop)) == ganz else 0.0)


## Rest einer Achse merken (0: keiner) und die Liste für dieses Bild vormerken.
func _bruch(sc: ScrollContainer, prop: String, rest: float) -> void:
	var alt: Vector2 = sc.get_meta("uz_bruch", Vector2.ZERO)
	var neu := Vector2(rest, alt.y) if prop == "scroll_horizontal" else Vector2(alt.x, rest)
	if neu == alt:
		return
	if neu == Vector2.ZERO:
		sc.remove_meta("uz_bruch")
	else:
		sc.set_meta("uz_bruch", neu)
	for w in _bruch_offen:
		if w.get_ref() == sc:
			return
	_bruch_offen.append(weakref(sc))


func _bruch_planen() -> void:
	if not _bruch_offen.is_empty() and not _bruch_geplant:
		_bruch_geplant = true
		_bruch_anwenden.call_deferred()


## Die Verschiebung jedes vorgemerkten Inhalts beim RenderingServer setzen (nach dem Einordnen der Container).
func _bruch_anwenden() -> void:
	_bruch_geplant = false
	for w in _bruch_offen:
		var sc := w.get_ref() as ScrollContainer
		if sc == null or not sc.is_inside_tree():
			continue
		var b: Vector2 = sc.get_meta("uz_bruch", Vector2.ZERO)
		for c in sc.get_children():
			if c is Control:
				var t := (c as Control).get_transform()
				t.origin -= b
				RenderingServer.canvas_item_set_transform((c as Control).get_canvas_item(), t)
	_bruch_offen.clear()

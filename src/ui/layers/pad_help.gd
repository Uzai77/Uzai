extends "res://src/ui/layers/layer.gd"
## Controller-Problemlöser (Punkt 114): Schritt für Schritt, was am Controller nicht stimmt. Erst,
## was Uzai sieht (Controller, Verbindung, Akku, Eingaben live), dann jede Taste einmal, die Sticks
## (Drift in Ruhe – mit passender Totzone zum Übernehmen – und wie weit sie nach außen kommen), die
## Trigger, die Vibration, doppelte Eingaben (Steam Input, DS4Windows, Steams Desktop-Belegung) und
## ob die Tastensymbole stimmen; am Ende eine Übersicht. „Wird nicht erkannt“ erklärt ehrlich die
## Wege in Windows und Steam – Uzai installiert dafür nichts und ändert nichts an Windows.
##
## In den Messschritten (Tasten, Sticks, Trigger) gehören alle Eingaben dem Test: nichts bewegt das
## Menü, nichts löst etwas aus. B halten überspringt den Schritt, mit der Tastatur Enter oder Esc.
## Die Bewertungen stehen in src/core/pad_check.gd. Öffnen: PadHelp.open_for(main).

const PadCheck := preload("res://src/core/pad_check.gd")
const PadTest := preload("res://src/ui/layers/pad_test.gd")
const PadsS := preload("res://src/core/pads.gd")
const Lang := preload("res://src/core/lang.gd")
const SELF := "res://src/ui/layers/pad_help.gd"
const Zustand := preload("res://src/core/zustand.gd")

const STEPS := [["sieht", "Was Uzai sieht"], ["tasten", "Tasten"], ["sticks", "Sticks"], ["trigger", "Trigger"],
	["vibration", "Vibration"], ["doppelt", "Doppelte Eingaben"], ["symbole", "Tastensymbole"], ["ergebnis", "Ergebnis"]]
const CAPTURE := ["tasten", "sticks", "trigger"]
## Seiten des Problemlösers: Schritt für Schritt vor (Weiter, Überspringen) und zurück (B), „Wird nicht erkannt“
## von der ersten Seite aus, „Noch einmal“ vom Ergebnis zu den Tasten.
const ZUSTAENDE_SEITE := { "": ["sieht"], "sieht": ["tasten", "fehlt"], "fehlt": ["sieht"], "tasten": ["sticks", "sieht"],
	"sticks": ["trigger", "tasten"], "trigger": ["vibration", "sticks"], "vibration": ["doppelt", "trigger"], "doppelt": ["symbole", "vibration"],
	"symbole": ["ergebnis", "doppelt"], "ergebnis": ["tasten"] }
## Messung der Sticks: Ruhelage, dann kreisen, dann fertig; neu betreten misst von vorn.
const ZUSTAENDE_STICKS := { "": ["ruhe"], "ruhe": ["kreis"], "kreis": ["", "ruhe"] }
const HOLD_SKIP := 0.9
const REST_S := 3.0             ## so lange misst Uzai die Ruhelage der Sticks
const CIRCLE_S := 15.0          ## so lange darf das Kreisen dauern
const TRIGGER_S := 15.0
const KEY_GRACE_MS := 140       ## Tastatur im Messschritt: erst „Weiter“, wenn keine Controller-Taste dazugehört
const SAME_MS := 90.0
const RAIL_W := 300.0

const Main := preload("res://src/main.gd")
var main: Main
## Nur für Proben: { "joys": [{ device, name, vid, pid }] } statt Godots Geräteliste; Eingaben
## kommen dann über sim_press und sim_axes.
var sim: Dictionary = {}
var sim_axes: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

var _id := "":                  ## gezeigte Seite: ein Schritt oder „fehlt“
	set(neu):
		Zustand.wechsel("controller.hilfe", ZUSTAENDE_SEITE, _id, neu)
		_id = neu
var _res := {}                  ## Schritt -> [Zustand („ok“, „fix“, „warn“, „skip“), kurzer Satz]
var _capture := false
var _cur := -1                  ## geprüftes Godot-Gerät
var _cur_ms := -100000
var _events: Array = []         ## Tastendrücke, Tastatur, Maus – für PadCheck.dupes
var _last_pad_ms := -100000
var _key_at := 0
var _hold := 0.0
var _pressed := {}
var _sim_down: Array = []
var _phase := "":
	set(neu):
		Zustand.wechsel("controller.sticks", ZUSTAENDE_STICKS, _phase, neu)
		_phase = neu
var _t := 0.0
var _rest_l: Array = []
var _rest_r: Array = []
var _reach_l: Array = []
var _reach_r: Array = []
var _trig := {}
var _busy := false

var _sub: Label
var _rail: VBoxContainer
var _slot: Control
var _page: VBoxContainer
var _say_l: Label
var _hold_bar: ColorRect
var _view: Control
var _sticks: _Sticks
var _trigs: _Triggers
var _live := {}                 ## Gerät -> _Live (Seite „Was Uzai sieht“)


static func open_for(m: Main) -> Control:
	var l = load(SELF).new()
	m.open_layer(l)
	return l


## Ebene weg: Seite und Messung aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("controller.hilfe")
	Zustand.vergessen("controller.sticks")


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	var bg := ColorRect.new()
	bg.color = Color(UzTheme.col("bg"), 0.96)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	add_child(bg)
	var root := U.margin(96, 70, 96, 120)
	U.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var col := U.vbox(34)
	root.add_child(col)
	var head := U.vbox(6)
	head.add_child(U.label("Controller-Problemlöser", "xl", "text", "title"))
	_sub = U.label("", "m", "muted", "regular")
	head.add_child(_sub)
	col.add_child(head)
	var body := U.hbox(64)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_rail = U.vbox(4)
	_rail.custom_minimum_size = Vector2(RAIL_W, 0)
	body.add_child(_rail)
	for s in STEPS:
		_rail.add_child(_RailRow.make(str(s[1])))
	_slot = Control.new()
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_slot)
	_hold_bar = ColorRect.new()
	_hold_bar.color = UzTheme.col("accent")
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_bar.anchor_top = 1.0
	_hold_bar.anchor_bottom = 1.0
	_hold_bar.offset_top = -96
	_hold_bar.offset_bottom = -92
	_hold_bar.offset_left = 96
	_hold_bar.size.x = 0
	add_child(_hold_bar)
	_cur = _first_joy()
	_update_sub()
	Pads.changed.connect(_on_pads)
	Input.joy_connection_changed.connect(_on_joy)
	_show("sieht", 0)


func _first_focus() -> Control:
	return Nav.default_in(_page) if is_instance_valid(_page) else null


# --- Geräte ------------------------------------------------------------------------------------

func _joys() -> Array:
	return sim.get("joys", []) if not sim.is_empty() else PadsS.godot_joys()


func _first_joy() -> int:
	var j := _joys()
	return int(j[0].device) if not j.is_empty() else -1


func _joy(dev: int) -> Dictionary:
	for j in _joys():
		if int(j.device) == dev:
			return j
	return {}


## Pads.pads (mit Akku und Verbindung); in Proben bekommen sie der Reihe nach die Geräte aus sim.
func _entries() -> Array:
	var joys := _joys()
	if Pads.pads.is_empty() and not joys.is_empty():
		# Pads hat noch nicht neu gelesen (oder Probe): nur Godots Sicht, ohne Akku.
		return PadsS.merge([], [], joys.map(func(j: Dictionary) -> Dictionary:
			return { "device": int(j.device), "name": str(j.get("name", "")), "vid": int(j.get("vid", 0)), "pid": int(j.get("pid", 0)),
					"player": int(j.get("player", -1)) }))
	var out: Array = []
	for i in Pads.pads.size():
		var p: Dictionary = (Pads.pads[i] as Dictionary).duplicate()
		if not sim.is_empty():
			p.device = int(joys[i].device) if i < joys.size() else -1
		out.append(p)
	return out


func _family() -> String:
	var j := _joy(_cur)
	return PadsS.family_of(str(j.get("name", "")), int(j.get("vid", 0))) if not j.is_empty() else "xbox"


func _update_sub() -> void:
	if not is_instance_valid(_sub):
		return
	if _cur < 0:
		# Windows (Helfer) meldet womöglich einen, aber Uzai bekommt von ihm keine Eingaben.
		_sub.text = "Kein Controller sendet Eingaben an Uzai" if not _entries().is_empty() else "Kein Controller verbunden"
		return
	var t := str(_joy(_cur).get("name", "Controller"))
	for p in _entries():
		if int(p.get("device", -1)) == _cur:
			t = "%s · %s" % [p.get("name", t), PadsS.detail_text(p)]
			var bt := PadsS.battery_text(p)
			if bt != "":
				t += " · " + bt
	_sub.text = "Geprüft wird: " + t


func _on_pads() -> void:
	_update_sub()
	if _id == "sieht" and not _busy:
		_show("sieht", 0)


func _on_joy(dev: int, on: bool) -> void:
	if not on and dev == _cur:
		_cur = _first_joy()
		if _capture:
			_finish(_id, "skip", "Der Controller wurde getrennt.")
	elif on and _cur < 0:
		_cur = dev
	_update_sub()


# --- Eingaben ----------------------------------------------------------------------------------

## In den Messschritten bekommt nur der Test die Eingaben (vor Nav, das später dran ist). Alles,
## was im selben Augenblick wie eine Controller-Taste kommt, merkt sich Uzai für „Doppelte Eingaben“.
func _input(event: InputEvent) -> void:
	if _closing:
		return
	var now := Time.get_ticks_msec()
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_press(jb.device, jb.button_index, now)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_flash(event.device)
	elif _capture and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_note("key", now, k.keycode)
			if k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_BACKSPACE]:
				_key_at = now + KEY_GRACE_MS
	elif _capture and event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_note("click", now, 0)
	elif _capture and event is InputEventMouseMotion:
		var ax := _axes()
		if Vector2(ax[0], ax[1]).length() > 0.3 or Vector2(ax[2], ax[3]).length() > 0.3:
			_note("move", now, 0)
	else:
		return
	if _capture:
		get_viewport().set_input_as_handled()


## Nur für Proben: ein Tastendruck an einem Gerät aus sim.
func sim_press(dev: int, b: int) -> void:
	_sim_down = [b]
	_press(dev, b, Time.get_ticks_msec())
	await get_tree().create_timer(0.12).timeout
	_sim_down = []


func _press(dev: int, b: int, now: int) -> void:
	_note("pad", now, b, dev)
	_last_pad_ms = now
	_flash(dev)
	# Gewählt wird der Controller, an dem jemand drückt – aber nicht der Doppelgänger, der im selben
	# Augenblick dieselbe Taste meldet.
	if dev != _cur and (not _capture or _cur < 0) and now - _cur_ms > 200:
		_cur = dev
		_update_sub()
		for d in _live:
			if is_instance_valid(_live[d]):
				(_live[d] as _Live).chosen = int(d) == dev
				(_live[d] as _Live).queue_redraw()
	if dev == _cur:
		_cur_ms = now
	if _id == "tasten" and _capture and dev == _cur and not _pressed.has(b):
		_pressed[b] = true
		if b in PadCheck.BUTTONS:
			Sfx.play("move")
		_tasten_text()


func _note(kind: String, t: int, b: int, dev := -1) -> void:
	_events.append({ "t": t, "kind": kind, "device": dev, "button": b })
	if _events.size() > 800:
		_events = _events.slice(_events.size() - 500)


func _flash(dev: int) -> void:
	var l: Variant = _live.get(dev)
	if l != null and is_instance_valid(l):
		(l as _Live).flash()


func _axes() -> Array:
	if not sim.is_empty():
		return sim_axes
	var out := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if _cur >= 0:
		for a in 6:
			out[a] = Input.get_joy_axis(_cur, a)
	return out


func _buttons_down() -> Array:
	if not sim.is_empty():
		return _sim_down
	var out: Array = []
	if _cur >= 0:
		for b in range(JOY_BUTTON_SDL_MAX):
			if Input.is_joy_button_pressed(_cur, b):
				out.append(b)
	return out


func nav_dir(_cmd: String) -> bool:
	return _capture


## B: auf der ersten und der letzten Seite schließen, sonst einen Schritt zurück („Wird nicht
## erkannt“ zurück zur ersten Seite).
func nav_command(cmd: String) -> bool:
	if _capture:
		return true
	if cmd == "b" and not (_id in ["sieht", "ergebnis"]):
		Sfx.play("back")
		var i := _step_index(_id)
		_show("sieht" if i <= 0 else str(STEPS[i - 1][0]), -1)
		return true
	return super.nav_command(cmd)


func _process(dt: float) -> void:
	if _closing:
		return
	if _capture:
		# B halten überspringt; mit der Tastatur Enter oder Esc – aber nicht, wenn die „Taste“ nur
		# Steams Desktop-Belegung war, die zu einer Controller-Taste gehört.
		var held := Input.is_joy_button_pressed(_cur, JOY_BUTTON_B) if _cur >= 0 and sim.is_empty() else false
		_hold = _hold + dt if held else 0.0
		_hold_bar.size.x = (size.x - 192.0) * clampf(_hold / HOLD_SKIP, 0.0, 1.0)
		if _hold >= HOLD_SKIP:
			_hold = 0.0
			_skip()
			return
		var now := Time.get_ticks_msec()
		if _key_at > 0 and now >= _key_at:
			var key_t := _key_at - KEY_GRACE_MS
			_key_at = 0
			if absf(float(_last_pad_ms - key_t)) > SAME_MS:
				_skip()
				return
	elif _hold_bar.size.x > 0.0:
		_hold_bar.size.x = 0.0
	match _id:
		"tasten":
			_tick_tasten()
		"sticks":
			_tick_sticks(dt)
		"trigger":
			_tick_trigger(dt)


# --- Seiten ------------------------------------------------------------------------------------

func _step_index(id: String) -> int:
	for i in STEPS.size():
		if STEPS[i][0] == id:
			return i
	return -1


func _next() -> void:
	var i := _step_index(_id)
	if i >= 0 and i < STEPS.size() - 1:
		_show(str(STEPS[i + 1][0]), 1)


## Läufe von _show, die gerade unterwegs sind (siehe dort).
var _show_offen := 0


## Seite id zeigen. dir 0: sofort, 1: die alte gleitet nach links hinaus und die neue kommt von
## rechts, -1 umgekehrt – wie die Schritte der Einrichtung.
func _show(id: String, dir: int) -> void:
	_show_offen += 1
	await _show_lauf(id, dir)
	_show_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _show täte bis zum Neustart nichts mehr.
	if _show_offen == 0 and _busy:
		_busy = false


func _show_lauf(id: String, dir: int) -> void:
	if _busy:
		return
	_busy = true
	_id = id
	_live.clear()
	_view = null
	_sticks = null
	_trigs = null
	_say_l = null
	var old := _page
	if old and dir != 0:
		var out := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		out.tween_property(old, "modulate:a", 0.0, U.T_FAST)
		out.tween_property(old, "position:x", -40.0 * dir, U.T_FAST)
		await out.finished
	if old:
		old.queue_free()
	_page = U.vbox(26)
	U.full_rect(_page)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.add_child(_page)
	call("_page_" + id)
	_set_capture(id in CAPTURE and _cur >= 0)
	_update_rail()
	if dir != 0:
		_page.modulate.a = 0.0
		_page.position.x = 50.0 * dir
		var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(_page, "modulate:a", 1.0, U.T_ENTER)
		tw.tween_property(_page, "position:x", 0.0, U.T_ENTER + 0.06)
	_busy = false
	if id in CAPTURE and _cur < 0:
		_finish(id, "skip", "Kein Controller verbunden.")
	_focus_page()


func _focus_page() -> void:
	if Nav.top_layer() != self:
		return
	var d := Nav.default_in(_page)
	if d:
		Nav.focus(d, true)
	elif Nav.focused() and is_ancestor_of(Nav.focused()):
		Nav.focused().release_focus()
	Nav.focus_moved.emit(Nav.focused())


func _set_capture(on: bool) -> void:
	_capture = on
	_hold = 0.0
	_key_at = 0
	if on:
		set_meta("uz_pad_owned", true)
		set_meta("uz_hint_b", "Halten: Überspringen" if Nav.device == "pad" else "Überspringen")
	else:
		remove_meta("uz_pad_owned")
		set_meta("uz_hint_b", "Schließen" if _id in ["sieht", "ergebnis"] else "Zurück")
	Nav.focus_moved.emit(Nav.focused())


func _update_rail() -> void:
	var cur := _step_index(_id if _id != "fehlt" else "sieht")
	for i in STEPS.size():
		var r: _RailRow = _rail.get_child(i)
		var st := "cur" if i == cur else str(_res.get(STEPS[i][0], [""])[0])
		r.set_state(st, i == cur)


func _title(t: String, text: String) -> void:
	_page.add_child(U.label(t, "l", "text", "bold"))
	if text != "":
		_page.add_child(U.label(text, "m", "muted", "regular", true))


## Knopfreihe aus [Text, Callable, Symbol]; der erste ist der wichtigste und gewählt.
func _buttons(list: Array) -> HBoxContainer:
	var row := U.hbox(14)
	for i in list.size():
		var b: Array = list[i]
		var btn := U.button(str(b[0]), str(b[2]) if b.size() > 2 else "", "primary" if i == 0 else "flat")
		btn.pressed.connect(b[1])
		if i == 0:
			btn.set_meta("uz_default", true)
		row.add_child(btn)
	return row


func _say(t: String) -> void:
	if is_instance_valid(_say_l):
		_say_l.text = t


## Ergebnis eines Schritts merken. In den Messschritten erscheint es als Karte auf der Seite (mit
## „Weiter“ und was es sonst dazu gibt), übersprungene Schritte gehen gleich weiter.
func _finish(id: String, status: String, text: String, extra: Array = []) -> void:
	_res[id] = [status, text]
	_set_capture(false)
	_update_rail()
	if status == "skip" and id in CAPTURE:
		_next()
		return
	if not (id in CAPTURE):
		return
	# Ein Moment Ruhe: Wer gerade noch Tasten drückt, löst nicht gleich „Weiter“ aus.
	await get_tree().create_timer(0.45).timeout
	if _id != id or _closing:
		return
	# Die Anweisung hat sich erledigt: An ihre Stelle tritt das Ergebnis.
	if is_instance_valid(_say_l):
		_say_l.visible = false
	var card := _result_card(status, text, extra + [["Weiter", _next, "chevron_right"]])
	_page.add_child(card)
	card.modulate.a = 0.0
	U.tw(card, "uz_in").tween_property(card, "modulate:a", 1.0, U.T_ENTER)
	_focus_page()


func _skip() -> void:
	match _id:
		"tasten":
			var miss := PadCheck.missing(_pressed)
			if _pressed.is_empty():
				_finish("tasten", "skip", "Übersprungen.")
			else:
				_finish("tasten", "warn", "Nicht angekommen: %s." % _names(miss))
		_:
			_finish(_id, "skip", "Übersprungen.")


func _names(list: Array) -> String:
	var fam := _family()
	return ", ".join(list.map(func(b: int) -> String: return tr(PadCheck.button_name(b, fam))))


func _result_card(status: String, text: String, buttons: Array) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 28 if side in ["left", "right"] else 22)
	p.add_theme_stylebox_override("panel", sb)
	var row := U.hbox(22)
	p.add_child(row)
	var m := _Mark.new()
	m.custom_minimum_size = Vector2(40, 40)
	m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	m.state = status
	row.add_child(m)
	var v := U.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(U.label(text, "m", "text", "medium", true))
	if not buttons.is_empty():
		v.add_child(_buttons(buttons))
	return p


# --- 1. Was Uzai sieht -------------------------------------------------------------------------

func _page_sieht() -> void:
	var list := _entries()
	if list.is_empty() and _joys().is_empty():
		_title("Kein Controller zu sehen",
				"Controller anschließen oder einschalten. Tastatur: Enter wählt, Esc schließt.")
		_page.add_child(_buttons([["Was tun?", func() -> void: _show("fehlt", 1), "info"], ["Erneut suchen", _rescan, "refresh"]]))
		return
	_title("Was Uzai sieht", "Taste drücken, um einen Controller zu wählen.")
	var cards := U.vbox(10)
	_page.add_child(cards)
	for p in list:
		cards.add_child(_pad_card(p))
	for h in PadCheck.device_hints(_joys()):
		_page.add_child(_note_row(_hint_text(str(h))))
	_page.add_child(U.spacer(0, 4, false))
	_page.add_child(_buttons([["Prüfung starten", func() -> void: _show("tasten", 1), "play"],
		["Wird nicht erkannt?", func() -> void: _show("fehlt", 1), "info"]]))


func _pad_card(p: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel())
	sb.content_margin_left = 24
	sb.content_margin_right = 26
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	var row := U.hbox(20)
	panel.add_child(row)
	var ic := U.icon("controller", 30, "muted")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var v := U.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(U.label(str(p.name), "m", "text", "bold"))
	var parts := PackedStringArray([PadsS.detail_text(p)])
	if int(p.get("vid", 0)) > 0:
		parts.append("Kennung %04X:%04X" % [int(p.vid), int(p.get("pid", 0))])
	v.add_child(U.label(" · ".join(parts), "s", "muted", "regular"))
	var bt := PadsS.battery_text(p)
	if bt != "":
		var b := U.label(bt, "s", "muted", "medium")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	var dev := int(p.get("device", -1))
	var live := _Live.new()
	live.chosen = dev >= 0 and dev == _cur
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(live)
	if dev >= 0:
		_live[dev] = live
	return panel


func _note_row(t: String) -> Control:
	var row := U.hbox(14)
	var ic := U.icon("warning", 24, "warn")
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var l := U.label(t, "s", "muted", "regular", true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _hint_text(h: String) -> String:
	if h == "steam":
		return "Steam Input ist aktiv. Eingaben können doppelt ankommen."
	return "Zusätzlicher Xbox-360-Controller erkannt (DS4Windows o. Ä.). Eingaben kommen doppelt."


func _rescan() -> void:
	Pads.refresh(true)
	Toasts.show_toast("Uzai sucht neu", "Neue Controller erscheinen von selbst.", "refresh", { "ms": 2500 })


# --- Wird nicht erkannt ------------------------------------------------------------------------

const MISSING_STEPS := [
	"Kabel: anderes Kabel oder anderen USB-Anschluss versuchen.",
	"Bluetooth: Kopplungsmodus starten (Xbox: Verbindungstaste halten; PlayStation: PS und Create), dann „Koppeln“.",
	"Steam: Einstellungen → Controller prüfen.",
	"DS4Windows o. Ä. beenden.",
	"Erkennt Windows ihn nicht, liegt es an Controller, Kabel oder Adapter.",
]


func _page_fehlt() -> void:
	_title("Wird nicht erkannt", "")
	var v := U.vbox(12)
	_page.add_child(v)
	for i in MISSING_STEPS.size():
		var row := U.hbox(16)
		var n := U.label("%d" % (i + 1), "m", "accent", "bold")
		n.custom_minimum_size = Vector2(26, 0)
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(n)
		var l := U.label(str(MISSING_STEPS[i]), "m", "muted", "regular", true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
	_page.add_child(
			_buttons([["Erneut suchen", _rescan, "refresh"], ["Koppeln", func() -> void: load("res://src/ui/layers/pad_pair.gd").open_for(main), "bluetooth"],
			["Zurück", func() -> void: _show("sieht", -1), "chevron_left"]]))


# --- 2. Tasten ---------------------------------------------------------------------------------

func _page_tasten() -> void:
	_pressed.clear()
	_title("Tasten", "Jede Taste einmal drücken. Guide und Teilen zählen nicht.")
	var v = PadTest._PadView.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.ps = _family() == "ps"
	_page.add_child(v)
	v.custom_minimum_size = Vector2(0, 300)
	_view = v
	_say_l = U.label("", "m", "text", "medium", true)
	_page.add_child(_say_l)
	_tasten_text()


func _tasten_text() -> void:
	var miss := PadCheck.missing(_pressed)
	var n := PadCheck.BUTTONS.size()
	if miss.is_empty():
		_say(tr("Alle %d Tasten kommen an.") % n)
	else:
		_say("%s  ·  %s" % [tr("%d von %d") % [n - miss.size(), n], tr("Fehlt noch: %s") % _names(miss)])


func _tick_tasten() -> void:
	if not is_instance_valid(_view):
		return
	_view.state = { "buttons": _buttons_down(), "axes": _axes() }
	_view.done = _pressed
	_view.queue_redraw()
	if _capture and PadCheck.missing(_pressed).is_empty():
		_finish("tasten", "ok", "Alle %d Tasten kommen an." % PadCheck.BUTTONS.size())


# --- 3. Sticks ---------------------------------------------------------------------------------

func _page_sticks() -> void:
	_phase = "ruhe"
	_t = 0.0
	_rest_l.clear()
	_rest_r.clear()
	_reach_l = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	_reach_r = _reach_l.duplicate()
	_title("Sticks", "")
	_sticks = _Sticks.new()
	_sticks.custom_minimum_size = Vector2(0, 340)
	_sticks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sticks.deadzone = float(Config.get_value("controller.deadzone", 0.5))
	_page.add_child(_sticks)
	_say_l = U.label("Beide Sticks loslassen.", "m", "text", "medium", true)
	_page.add_child(_say_l)


func _tick_sticks(dt: float) -> void:
	if not is_instance_valid(_sticks):
		return
	var ax := _axes()
	var l := Vector2(ax[0], ax[1])
	var r := Vector2(ax[2], ax[3])
	_sticks.l = l
	_sticks.r = r
	_sticks.queue_redraw()
	if not _capture:
		return
	if _phase == "ruhe":
		if l.length() > 0.45 or r.length() > 0.45:
			if _t > 0.0:
				_say("Nicht berühren – Uzai fängt noch einmal an.")
			_rest_l.clear()
			_rest_r.clear()
			_t = 0.0
		else:
			_rest_l.append(l)
			_rest_r.append(r)
			_t += dt
		_sticks.progress = _t / REST_S
		if _t >= REST_S:
			_phase = "kreis"
			_t = 0.0
			_sticks.drift_l = PadCheck.drift(_rest_l)
			_sticks.drift_r = PadCheck.drift(_rest_r)
			_say("Beide Sticks außen im Kreis drehen.")
	elif _phase == "kreis":
		PadCheck.reach_add(_reach_l, l)
		PadCheck.reach_add(_reach_r, r)
		_sticks.reach_l = _reach_l
		_sticks.reach_r = _reach_r
		_t += dt
		if (PadCheck.reach_min(_reach_l) >= PadCheck.REACH_OK and PadCheck.reach_min(_reach_r) >= PadCheck.REACH_OK) or _t >= CIRCLE_S:
			_sticks_done()


func _sticks_done() -> void:
	_phase = ""
	var dl := float(_sticks.drift_l)
	var dr := float(_sticks.drift_r)
	var lines := PackedStringArray()
	var warn := false
	for s in [["Der linke Stick", dl, PadCheck.reach_min(_reach_l)], ["Der rechte Stick", dr, PadCheck.reach_min(_reach_r)]]:
		var lvl := PadCheck.drift_level(float(s[1]))
		if lvl != "ruhig":
			warn = true
			if float(s[1]) >= PadCheck.DRIFT_MAX:
				lines.append(
						tr("%s steht in Ruhe weit draußen (%s). Stick reinigen oder reparieren lassen.") % [tr(str(s[0])),
						_dec(float(s[1]))])
			else:
				lines.append(tr("%s driftet leicht (%s in Ruhe)." if lvl == "leicht" else "%s driftet deutlich (%s in Ruhe).") % [tr(str(s[0])), _dec(float(s[1]))])
		if float(s[2]) < PadCheck.REACH_OK:
			warn = true
			lines.append(tr("%s kommt nicht in jede Richtung ganz nach außen (bis %s).") % [tr(str(s[0])), _dec(float(s[2]))])
	var extra: Array = []
	var cur := float(Config.get_value("controller.deadzone", 0.5))
	var dz := PadCheck.deadzone_for(maxf(dl, dr), cur)
	if dz > cur + 0.001:
		lines.append(tr("Totzone %s empfohlen (eingestellt: %s).") % [_dec(dz), _dec(cur)])
		extra.append([tr("Totzone %s übernehmen") % _dec(dz), func() -> void: _apply_deadzone(dz), "check"])
	elif warn and dz > 0.0:
		lines.append(tr("Totzone reicht (%s).") % _dec(cur))
	if not warn:
		lines.append("Beide Sticks in Ordnung.")
	else:
		lines.append("In Spielen zählt die Totzone des Spiels oder von Steam Input.")
	_finish("sticks", "warn" if warn else "ok", "\n".join(lines), extra)


func _apply_deadzone(dz: float) -> void:
	Config.set_value("controller.deadzone", dz)
	if is_instance_valid(_sticks):
		_sticks.deadzone = dz
	_res["sticks"] = ["fix", str(_res.get("sticks", ["", ""])[1]) + "\n" + tr("Totzone auf %s gestellt.") % _dec(dz)]
	_update_rail()
	Toasts.show_toast("Totzone %s" % _dec(dz), "Gilt ab sofort in Uzais Menü.", "check", { "sound": "select", "ms": 3000 })
	_next()


func _dec(v: float) -> String:
	return Lang.dec("%.2f" % v)


# --- 4. Trigger --------------------------------------------------------------------------------

func _page_trigger() -> void:
	_t = 0.0
	_trig = { "lt_rest": 1.0, "rt_rest": 1.0, "lt_peak": 0.0, "rt_peak": 0.0 }
	var fam := _family()
	_title("Trigger", "")
	_trigs = _Triggers.new()
	_trigs.names = ["L2", "R2"] if fam == "ps" else (["ZL", "ZR"] if fam == "nintendo" else ["LT", "RT"])
	_trigs.custom_minimum_size = Vector2(0, 320)
	_trigs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(_trigs)
	_say_l = U.label("Beide Trigger langsam ganz durchdrücken und loslassen.", "m", "text", "medium", true)
	_page.add_child(_say_l)


func _tick_trigger(dt: float) -> void:
	if not is_instance_valid(_trigs):
		return
	var ax := _axes()
	var lt := clampf(float(ax[4]), 0.0, 1.0)
	var rt := clampf(float(ax[5]), 0.0, 1.0)
	_trigs.v = [lt, rt]
	_trigs.queue_redraw()
	if not _capture:
		return
	_t += dt
	_trig.lt_peak = maxf(float(_trig.lt_peak), lt)
	_trig.rt_peak = maxf(float(_trig.rt_peak), rt)
	# Ruhewert: der kleinste Wert, sobald die Messung läuft – ein hängender Trigger kommt nie auf 0.
	if _t > 0.25:
		_trig.lt_rest = minf(float(_trig.lt_rest), lt)
		_trig.rt_rest = minf(float(_trig.rt_rest), rt)
	_trigs.peak = [float(_trig.lt_peak), float(_trig.rt_peak)]
	var full: bool = float(_trig.lt_peak) >= PadCheck.TRIGGER_FULL and float(_trig.rt_peak) >= PadCheck.TRIGGER_FULL
	if (full and lt < 0.1 and rt < 0.1) or _t >= TRIGGER_S:
		_trigger_done()


func _trigger_done() -> void:
	var lines := PackedStringArray()
	var warn := false
	for k in [["lt", 0], ["rt", 1]]:
		var name := str(_trigs.names[k[1]])
		var rest := float(_trig[k[0] + "_rest"]) if _t > 0.25 else 0.0
		var peak := float(_trig[k[0] + "_peak"])
		match PadCheck.trigger_verdict(rest, peak):
			"fehlt":
				lines.append(tr("%s kam gar nicht an.") % name)
			"haengt":
				lines.append(tr("%s steht in Ruhe auf %d %%.") % [name, int(round(rest * 100.0))])
			"kurz":
				lines.append(tr("%s kommt nur bis %d %%.") % [name, int(round(peak * 100.0))])
			_:
				continue
		warn = true
	if not warn:
		lines.append("Beide Trigger in Ordnung.")
	_finish("trigger", "warn" if warn else "ok", "\n".join(lines))


# --- 5. Vibration ------------------------------------------------------------------------------

func _page_vibration() -> void:
	_title("Vibration", "Links, dann rechts.")
	var v = PadTest._PadView.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.ps = _family() == "ps"
	_page.add_child(v)
	v.custom_minimum_size = Vector2(0, 320)
	_view = v
	if _cur < 0:
		_res["vibration"] = ["skip", "Kein Controller verbunden."]
		_page.add_child(_buttons([["Weiter", _next, "chevron_right"]]))
		return
	_say_l = U.label("Hast du beide Seiten gespürt?", "m", "text", "medium")
	_page.add_child(_say_l)
	_page.add_child(_buttons([["Ja, beide", func() -> void: _vib_answer(true), "check"],
		["Nein", func() -> void: _vib_answer(false), "close"], ["Noch einmal", _rumble, "refresh"]]))
	_rumble.call_deferred()


func _rumble() -> void:
	var v = _view
	if not is_instance_valid(v) or _cur < 0:
		return
	for side in [["left", 0.7, 0.0], ["right", 0.0, 0.7]]:
		await get_tree().create_timer(0.3).timeout
		if not is_instance_valid(v) or _id != "vibration":
			return
		v.motor = side[0]
		v.queue_redraw()
		if sim.is_empty():
			Pads.rumble(_cur, side[1], side[2], 0.35)
		await get_tree().create_timer(0.45).timeout
		if is_instance_valid(v):
			v.motor = ""
			v.queue_redraw()


func _vib_answer(yes: bool) -> void:
	if yes:
		_res["vibration"] = ["ok", "Beide Motoren laufen."]
		_next()
		return
	_res["vibration"] = ["warn", "Keine Vibration gespürt."]
	_update_rail()
	U.clear(_page)
	_view = null
	_title("Keine Vibration", "")
	for t in ["Vibration am Controller oder in seiner App prüfen.",
			"Steam Input gibt Vibration nicht immer weiter.",
			"Uzais Vibration: Einstellungen → Controller → Gefühl."]:
		_page.add_child(_note_row(t))
	_page.add_child(_buttons([["Weiter", _next, "chevron_right"]]))
	_focus_page()


# --- 6. Doppelte Eingaben ----------------------------------------------------------------------

func _page_doppelt() -> void:
	var d := PadCheck.dupes(_events, SAME_MS)
	var verdict := PadCheck.dupe_verdict(d)
	var hints := PadCheck.device_hints(_joys())
	var texts := {
		"ok": ["Jeder Tastendruck kam genau einmal an.", "Kein zweites Gerät und keine Tastatur oder Maus, die mitdrückt."],
		"wenig": ["Noch zu wenige Tastendrücke.", "Erst den Schritt „Tasten“ durchgehen."],
		"pads": ["Eingaben kommen doppelt.", "Steam Input für diesen Controller ausschalten oder DS4Windows beenden."],
		"keys": ["Mit den Tasten kamen Tastatur oder Maus.", "Steams Desktop-Layout ohne Tastatur und Maus einstellen."],
		"mouse": ["Die Sticks bewegen auch die Maus.", "Steams Desktop-Layout ohne Maus einstellen."],
	}
	var t: Array = texts[verdict]
	var status := "ok" if verdict == "ok" else ("skip" if verdict == "wenig" else "warn")
	if verdict in ["ok", "wenig"] and not hints.is_empty():
		status = "warn"
	_res["doppelt"] = [status, str(t[0])]
	_update_rail()
	_title("Doppelte Eingaben", "")
	_page.add_child(_result_card(status, tr(str(t[0])) + "\n" + tr(str(t[1])), []))
	for h in hints:
		_page.add_child(_note_row(_hint_text(str(h))))
	_page.add_child(_buttons([["Weiter", _next, "chevron_right"]]))


# --- 7. Tastensymbole --------------------------------------------------------------------------

const GLYPH_SETS := [["xbox", "Xbox"], ["ps", "PlayStation"], ["nintendo", "Nintendo"]]


func _page_symbole() -> void:
	var j := _joy(_cur)
	var detected := PadCheck.glyphs_for(str(j.get("name", Nav.pad_name)), int(j.get("vid", Nav.pad_vid)))
	var shown := str(Config.get_value("controller.glyphs", "auto"))
	if shown == "auto" or shown == "keys":
		shown = detected
	_title("Tastensymbole", tr("Tastensymbole: %s.") % _set_name(shown))
	var row := U.hbox(20)
	_page.add_child(row)
	for g in GLYPH_SETS:
		var id := str(g[0])
		var b := U.button("", "", "flat")
		b.custom_minimum_size = Vector2(300, 168)
		if id == shown:
			b.set_meta("uz_default", true)
		b.pressed.connect(func() -> void: _choose_glyphs(id, detected))
		var v := U.vbox(14)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		U.full_rect(v)
		b.add_child(v)
		var gl := U.hbox(10)
		gl.alignment = BoxContainer.ALIGNMENT_CENTER
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in ["a", "b", "x", "y"]:
			var gg := U.glyph(k, 44)
			gg.force = id
			gl.add_child(gg)
		v.add_child(gl)
		var name := U.label(str(g[1]) + ("  ·  erkannt" if id == detected else ""), "m", "text", "medium")
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name)
		# Gewählt wird die Kachel hell: dann dunkle Schrift.
		b.focus_entered.connect(func() -> void: name.add_theme_color_override("font_color", UzTheme.col("on_focus")))
		b.focus_exited.connect(func() -> void: name.add_theme_color_override("font_color", UzTheme.col("text")))
		row.add_child(b)


func _set_name(id: String) -> String:
	for g in GLYPH_SETS:
		if g[0] == id:
			return tr(str(g[1]))
	return "Xbox"


func _choose_glyphs(chosen: String, detected: String) -> void:
	var before := str(Config.get_value("controller.glyphs", "auto"))
	var setting := PadCheck.glyph_setting(chosen, detected)
	if setting != before:
		Config.set_value("controller.glyphs", setting)
	if chosen == detected and before in ["auto", "keys", chosen]:
		_res["symbole"] = ["ok", tr("Stimmen: %s.") % _set_name(chosen)]
	else:
		_res["symbole"] = ["fix", tr("Auf %s gestellt.") % _set_name(chosen)]
	_next()


# --- 8. Ergebnis -------------------------------------------------------------------------------

func _page_ergebnis() -> void:
	var warn := _res.values().any(func(r: Array) -> bool: return str(r[0]) == "warn")
	_title("Ergebnis", "" if warn else "Alles Geprüfte funktioniert.")
	var v := U.vbox(14)
	_page.add_child(v)
	for i in range(1, STEPS.size() - 1):
		var id := str(STEPS[i][0])
		var r: Array = _res.get(id, ["skip", "Nicht geprüft."])
		var row := U.hbox(18)
		var m := _Mark.new()
		m.custom_minimum_size = Vector2(30, 30)
		m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		m.state = str(r[0])
		row.add_child(m)
		var name := U.label(str(STEPS[i][1]), "m", "text", "bold")
		name.custom_minimum_size = Vector2(250, 0)
		name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(name)
		var t := U.label(str(r[1]).get_slice("\n", 0), "m", "muted", "regular", true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		v.add_child(row)
	_page.add_child(_buttons([["Fertig", close, "check"], ["Noch einmal", _again, "refresh"]]))


func _again() -> void:
	_res.clear()
	_events.clear()
	_show("tasten", -1)


# --- Zeichnungen -------------------------------------------------------------------------------

## Zustand eines Schritts: offen (Punkt), gerade dran (Ring), ok/behoben (Haken), Hinweis (!),
## übersprungen (Strich). Ändert er sich, ploppt das Zeichen kurz auf.
class _Mark extends Control:
	var state := "":
		set(v):
			if v == state:
				return
			state = v
			if is_inside_tree():
				pivot_offset = size * 0.5
				scale = Vector2.ONE * 0.7
				U.im_tempo(create_tween()).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2.ONE, 0.32)
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var w := maxf(2.0, r * 0.16)
		match state:
			"ok", "fix":
				var col := UzTheme.col("ok") if state == "ok" else UzTheme.col("accent")
				draw_circle(c, r, Color(col, 0.16), true, -1.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0.02 * r), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.46, -r * 0.32)]), col, w, true)
			"warn":
				var wc := UzTheme.col("warn")
				draw_circle(c, r, Color(wc, 0.16), true, -1.0, true)
				draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.12), wc, w, true)
				draw_circle(c + Vector2(0, r * 0.4), w * 0.62, wc, true, -1.0, true)
			"skip":
				draw_arc(c, r - 1.0, 0, TAU, 40, UzTheme.col("faint", 0.6), 1.5, true)
				draw_line(c + Vector2(-r * 0.32, 0), c + Vector2(r * 0.32, 0), UzTheme.col("faint"), w, true)
			"cur":
				draw_arc(c, r - 1.0, 0, TAU, 40, UzTheme.col("accent"), w, true)
				draw_circle(c, r * 0.32, UzTheme.col("accent"), true, -1.0, true)
			_:
				draw_circle(c, r * 0.22, UzTheme.col("faint", 0.7), true, -1.0, true)


## Eine Zeile links: Zeichen und Name des Schritts; der aktuelle hell, die anderen leise.
class _RailRow extends HBoxContainer:
	const UU := preload("res://src/ui/u.gd")
	var mark: _Mark
	var label: Label

	static func make(t: String) -> _RailRow:
		var r := _RailRow.new()
		r.add_theme_constant_override("separation", 16)
		r.custom_minimum_size = Vector2(0, 50)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.mark = _Mark.new()
		r.mark.custom_minimum_size = Vector2(26, 26)
		r.mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(r.mark)
		r.label = UU.label(t, "m", "muted", "medium")
		r.label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(r.label)
		return r

	func set_state(st: String, current: bool) -> void:
		mark.state = st
		label.add_theme_font_override("font", UzTheme.font("bold" if current else "medium"))
		label.add_theme_color_override("font_color", UzTheme.col("text"))
		UU.tw(label, "uz_rail").tween_property(label, "modulate:a", 1.0 if current else 0.55, UU.T_FOCUS)


## Punkt rechts in der Controller-Karte: leuchtet bei jeder Eingabe kurz auf; der geprüfte
## Controller trägt einen feinen Ring.
class _Live extends Control:
	var chosen := false
	var glow := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(28, 28)

	func flash() -> void:
		glow = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			glow = v
			queue_redraw()
		, 1.0, 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var c := size * 0.5
		var acc := UzTheme.col("accent")
		if glow > 0.0:
			draw_circle(c, 9.0 + 5.0 * glow, Color(acc, 0.25 * glow), true, -1.0, true)
		draw_circle(c, 6.0, UzTheme.col("faint", 0.5).lerp(acc, glow), true, -1.0, true)
		if chosen:
			draw_arc(c, 12.0, 0, TAU, 40, Color(acc, 0.7), 1.5, true)


## Beide Sticks von oben: Rand, Totzone von Uzais Menü (gestrichelt wirkender feiner Ring), die
## gemessene Drift (in Ruhe – grün, gelb oder rot), wie weit der Stick je Achtel kam, und wo er
## gerade steht. Während der Ruhemessung läuft außen ein Fortschrittsbogen.
class _Sticks extends Control:
	var l := Vector2.ZERO
	var r := Vector2.ZERO
	var deadzone := 0.5
	var progress := 0.0
	var drift_l := -1.0
	var drift_r := -1.0
	var reach_l: Array = []
	var reach_r: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rad := minf(size.y * 0.42, size.x * 0.2)
		_stick(Vector2(size.x * 0.3, size.y * 0.47), rad, l, drift_l, reach_l, "Links")
		_stick(Vector2(size.x * 0.7, size.y * 0.47), rad, r, drift_r, reach_r, "Rechts")

	func _stick(c: Vector2, rad: float, v: Vector2, drift: float, reach: Array, title: String) -> void:
		var ink := UzTheme.col("muted")
		var acc := UzTheme.col("accent")
		draw_circle(c, rad, Color(UzTheme.col("surface"), 1.0), true, -1.0, true)
		draw_arc(c, rad, 0, TAU, 96, Color(ink, 0.45), 2.0, true)
		draw_arc(c, rad * clampf(deadzone, 0.0, 1.0), 0, TAU, 72, Color(ink, 0.3), 1.2, true)
		if progress > 0.0 and progress < 1.0 and drift < 0.0:
			draw_arc(c, rad + 10.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 72, acc, 3.0, true)
		if reach.size() == 8 and reach.any(func(x: float) -> bool: return x > 0.0):
			var pts := PackedVector2Array()
			for i in 9:
				var k := i % 8
				pts.append(c + Vector2.RIGHT.rotated(k * TAU / 8.0) * rad * maxf(float(reach[k]), 0.05))
			draw_colored_polygon(pts, Color(acc, 0.12))
			draw_polyline(pts, Color(acc, 0.55), 1.5, true)
		if drift >= 0.0:
			var dc := UzTheme.col("ok") if drift < 0.08 else (UzTheme.col("warn") if drift < 0.2 else UzTheme.col("danger"))
			draw_circle(c, maxf(rad * drift, 3.0), Color(dc, 0.28), true, -1.0, true)
			draw_arc(c, maxf(rad * drift, 3.0), 0, TAU, 48, dc, 1.5, true)
		var k2 := c + v.limit_length(1.0) * rad
		draw_line(c, k2, Color(acc, 0.35), 1.5, true)
		draw_circle(k2, 11.0, acc, true, -1.0, true)
		var f := UzTheme.font("medium")
		var fs := 19
		var t := tr(title)
		if drift >= 0.0:
			t += "  ·  " + tr("Ruhe %s") % Lang.dec("%.2f" % drift)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + rad + 40.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("muted"))


## Beide Trigger als stehende Balken: Füllung = wie weit gerade gedrückt, feiner Strich = weitester Druck.
class _Triggers extends Control:
	var v := [0.0, 0.0]
	var peak := [0.0, 0.0]
	var names := ["LT", "RT"]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y - 60.0
		var w := 88.0
		var f := UzTheme.font("bold")
		for i in 2:
			var x := size.x * (0.36 if i == 0 else 0.64) - w * 0.5
			var r := Rect2(x, 8.0, w, h)
			draw_style_box(UzTheme.box(UzTheme.col("surface"), 22, 1, UzTheme.col("stroke")), r)
			var fill := clampf(float(v[i]), 0.0, 1.0)
			if fill > 0.01:
				var fr := Rect2(x, 8.0 + h * (1.0 - fill), w, maxf(h * fill, 22.0))
				draw_style_box(UzTheme.box(UzTheme.col("accent"), 22), fr)
			var pk := clampf(float(peak[i]), 0.0, 1.0)
			if pk > 0.02:
				var py := 8.0 + h * (1.0 - pk)
				draw_line(Vector2(x - 12.0, py), Vector2(x + w + 12.0, py), UzTheme.col("text", 0.7), 2.0, true)
			var t := "%s  %d %%" % [names[i], int(round(fill * 100.0))]
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(f, Vector2(x + w * 0.5 - tw * 0.5, size.y - 12.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UzTheme.col("muted"))

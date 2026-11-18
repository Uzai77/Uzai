extends "res://src/ui/layers/layer.gd"
## Controller testen: ein gezeichneter Controller, der live zeigt, was gedrückt ist – Tasten,
## Steuerkreuz, beide Sticks (Position und Druck), Trigger (wie weit) –, darunter die genauen Werte
## und die zuletzt gedrückte Taste. Start halten testet die Vibration (erst links, dann rechts),
## B halten geht zurück (ein kurzer Druck auf B wird nur angezeigt). Mit der Tastatur: Esc.
##
## Wiederverwendbar (Einstellungen › Controller, Guide, Ersteinrichtung):
##   var t = preload("res://src/ui/layers/pad_test.gd").new()
##   t.device = -1            # -1: folgt dem Controller, der zuletzt bedient wurde
##   t.back_text = "Weiter"   # Wort neben „B halten“
##   t.closed.connect(...)    # wie jede Ebene
##   main.open_layer(t)

const Lang := preload("res://src/core/lang.gd")
const PadCheck := preload("res://src/core/pad_check.gd")

const HOLD_BACK := 0.8
const HOLD_RUMBLE := 0.6

var device := -1
var back_text := "Zurück"
## Nur für Proben: { "buttons": [JOY_BUTTON_…], "axes": [lx, ly, rx, ry, lt, rt] } statt echter Eingaben.
var sim: Dictionary = {}

var _cur := -1
var _view: _PadView
var _title: Label
var _sub: Label
var _values: Label
var _last_l: Label
var _rumble_l: Label
var _hold_bar: ColorRect
var _hold_b := 0.0
var _hold_m := 0.0
var _rumbling := false
var _last_name := ""
var _werte_muster := "Links  X %s  Y %s     Rechts  X %s  Y %s     LT %d %%   RT %d %%"


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	set_meta("uz_hint_b", "Halten: " + back_text)
	set_meta("uz_hints", [["menu", "Halten: Vibration testen"]])
	set_meta("uz_hints_center", true)
	_cur = device if device >= 0 else _first_pad()
	# Fast deckend: die Seite dahinter (Einstellungen, Guide) soll nicht durch die Zeichnung scheinen.
	var bg := ColorRect.new()
	bg.color = Color(UzTheme.col("bg"), 0.96)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	add_child(bg)
	var root := U.margin(96, 70, 96, 120)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(root)
	add_child(root)
	var col := U.vbox(10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	_title = U.label("Controller testen", "xl", "text", "title")
	col.add_child(_title)
	_sub = U.label("", "m", "muted", "regular")
	col.add_child(_sub)
	_view = _PadView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_view)
	_last_l = U.label("Drück eine Taste.", "l", "text", "ui_bold")
	_last_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_last_l)
	# Die Werte ändern sich in jedem Bild: Das Muster wird einmal von Hand übersetzt (_werte_muster), die Zeile selbst
	# nie – sonst liefe auf Englisch jede neue Zahlenfolge durch den Katalog und füllte dessen Speicher.
	_values = U.label("", "s", "muted", "medium")
	_values.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_werte_muster = tr("Links  X %s  Y %s     Rechts  X %s  Y %s     LT %d %%   RT %d %%")
	_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_values)
	_rumble_l = U.label("Start (≡) halten: Vibration testen – erst links (tief), dann rechts (hell).  ·  B halten: %s." % back_text, "s", "faint", "regular")
	_rumble_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_rumble_l)
	var bar_wrap := CenterContainer.new()
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar_wrap)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(UzTheme.col("line"), 0.6)
	bar_bg.custom_minimum_size = Vector2(320, 4)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(bar_bg)
	_hold_bar = ColorRect.new()
	_hold_bar.color = UzTheme.col("accent")
	_hold_bar.size = Vector2(0, 4)
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hold_bar)
	_update_head()


func _first_pad() -> int:
	var ids := Input.get_connected_joypads()
	return int(ids[0]) if not ids.is_empty() else -1


func _update_head() -> void:
	if not is_instance_valid(_sub):
		return
	if not sim.is_empty():
		_sub.text = str(sim.get("name", "Xbox Wireless Controller")) + " · Spieler 1"
		return
	if _cur < 0 or not (_cur in Input.get_connected_joypads()):
		_sub.text = "Kein Controller verbunden – schließ einen an oder schalte ihn ein."
		return
	var t := Input.get_joy_name(_cur)
	for p in Pads.pads:
		if int(p.get("device", -1)) == _cur:
			t = "%s · %s" % [p.get("name", t), Pads.detail_text(p)]
			var bt := Pads.battery_text(p)
			if bt != "":
				t += " · " + bt
	_sub.text = t


func _input(event: InputEvent) -> void:
	if device >= 0:
		return
	# Folgt dem Controller, der gerade bedient wird.
	var d := -1
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		d = event.device
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		d = event.device
	if d >= 0 and d != _cur:
		_cur = d
		_update_head()


func _process(dt: float) -> void:
	if _closing or not is_instance_valid(_view):
		return
	var st := _state()
	_view.state = st
	_view.ps = Nav.glyph_set() == "ps" or Pads.family_of(Input.get_joy_name(_cur) if _cur >= 0 else "", -1) == "ps"
	_view.queue_redraw()
	var ax: Array = st.axes
	_values.text = _werte_muster % [_f(ax[0]), _f(ax[1]), _f(ax[2]), _f(ax[3]),
			int(round(float(ax[4]) * 100.0)), int(round(float(ax[5]) * 100.0))]
	var pressed: Array = st.buttons
	if not pressed.is_empty():
		var n := _name_of(int(pressed[pressed.size() - 1]), _view.ps)
		if n != _last_name:
			_last_name = n
			_last_l.text = n
	# Halten: B geht zurück, Start testet die Vibration.
	_hold_b = _hold_b + dt if Input.is_action_pressed("uz_b") and Nav.device == "pad" else 0.0
	_hold_m = _hold_m + dt if Input.is_action_pressed("uz_menu") and not Input.is_action_pressed("uz_view") else 0.0
	var k := maxf(_hold_b / HOLD_BACK, 0.0 if _rumbling else _hold_m / HOLD_RUMBLE)
	_hold_bar.size = Vector2(320.0 * clampf(k, 0.0, 1.0), 4)
	if _hold_b >= HOLD_BACK:
		_hold_b = 0.0
		Sfx.play("back")
		close()
	elif _hold_m >= HOLD_RUMBLE and not _rumbling:
		rumble_test()


func _f(v: Variant) -> String:
	return Lang.dec("%+.2f" % float(v))


func _name_of(b: int, ps: bool) -> String:
	return PadCheck.button_name(b, "ps" if ps else "xbox")


func _state() -> Dictionary:
	if not sim.is_empty():
		return { "buttons": sim.get("buttons", []), "axes": sim.get("axes", [0, 0, 0, 0, 0, 0]) }
	var out := { "buttons": [], "axes": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] }
	if _cur < 0:
		return out
	for b in range(JOY_BUTTON_SDL_MAX):
		if Input.is_joy_button_pressed(_cur, b):
			out.buttons.append(b)
	for a in 6:
		out.axes[a] = Input.get_joy_axis(_cur, a)
	return out


## Vibration testen: 0,35 s links (tiefer Motor), kurze Pause, 0,35 s rechts (heller Motor).
func rumble_test() -> void:
	if _rumbling:
		return
	if _cur < 0:
		_rumble_l.text = "Kein Controller verbunden."
		return
	_rumbling = true
	_view.motor = "left"
	_rumble_l.text = "Vibration links (tiefer Motor) …"
	Pads.rumble(_cur, 0.7, 0.0, 0.35)
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree():
		return
	_view.motor = "right"
	_rumble_l.text = "Vibration rechts (heller Motor) …"
	Pads.rumble(_cur, 0.0, 0.7, 0.35)
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree():
		return
	_view.motor = ""
	_rumble_l.text = "Gespürt? Sonst ist die Vibration in Windows, Steam oder am Controller aus.  ·  B halten: %s." % back_text
	_rumbling = false


## Nichts zum Wählen: Richtungen, A, X, Y, Schulter- und Triggertasten zeigt die Ansicht nur an.
func nav_dir(_cmd: String) -> bool:
	return true


func nav_command(cmd: String) -> bool:
	if cmd == "guide":
		return false
	if cmd == "b" and Nav.device != "pad":
		Sfx.play("back")
		close()
	return true


## Der gezeichnete Controller.
class _PadView extends Control:
	const XC := { "a": "#5ab95e", "b": "#e2555f", "x": "#4f95e8", "y": "#e3b53c" }
	const PC := { "a": "#8fb3ff", "b": "#ff8a96", "x": "#f29ad8", "y": "#6fd8b2" }
	var state: Dictionary = { "buttons": [], "axes": [0, 0, 0, 0, 0, 0] }
	var ps := false
	var motor := ""
	## Schon geprüfte Tasten (Problemlöser, pad_help.gd): leise in der Akzentfarbe.
	var done: Dictionary = {}
	var _s := 1.0
	var _o := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 420)

	func _p(x: float, y: float) -> Vector2:
		return _o + Vector2(x, y) * _s

	func _down(b: int) -> bool:
		return b in (state.get("buttons", []) as Array)

	## Gedrückt voll in der Akzentfarbe, schon geprüft zart, sonst die Grundfarbe.
	func _fill(b: int, base: Color) -> Color:
		if _down(b):
			return UzTheme.col("accent")
		return base.lerp(UzTheme.col("accent"), 0.42) if done.has(b) else base

	func _draw() -> void:
		_s = minf(size.x / 940.0, size.y / 600.0)
		_o = (size - Vector2(940, 600) * _s) * 0.5
		var body := Color(UzTheme.col("surface_hi"), 0.95)
		var line := UzTheme.col("line")
		var acc := UzTheme.col("accent")
		var ink := UzTheme.col("muted")
		var ax: Array = state.get("axes", [0, 0, 0, 0, 0, 0])
		# Körper: Mitte und zwei Griffe; beim Vibrationstest leuchtet die Seite des Motors.
		var grips := [[250.0, 390.0, 130.0, "left"], [690.0, 390.0, 130.0, "right"], [215.0, 470.0, 92.0, "left"], [725.0, 470.0, 92.0, "right"]]
		for g in grips:
			draw_circle(_p(g[0], g[1]), float(g[2]) * _s, body)
		draw_style_box(UzTheme.box(body, int(120 * _s)), Rect2(_p(170, 150), Vector2(600, 260) * _s))
		# Vibrationstest: unten am Griff der Seite, deren Motor gerade läuft, leuchten Wellen.
		if motor != "":
			var gx := 215.0 if motor == "left" else 725.0
			for i in 3:
				draw_arc(_p(gx, 470), (100.0 + i * 16.0) * _s, PI * 0.2, PI * 0.8, 32, Color(acc, 0.9 - i * 0.25), 4.0 * _s, true)
		# Trigger (wie weit) und Schultertasten.
		for t in [[170.0, 4, "LT" if not ps else "L2"], [580.0, 5, "RT" if not ps else "R2"]]:
			var r := Rect2(_p(t[0], 52), Vector2(190, 24) * _s)
			draw_style_box(UzTheme.box(Color(line, 0.8), int(12 * _s)), r)
			var v := clampf(float(ax[t[1]]), 0.0, 1.0)
			if v > 0.01:
				draw_style_box(UzTheme.box(acc, int(12 * _s)), Rect2(r.position, Vector2(maxf(r.size.x * v, 24 * _s), r.size.y)))
			_text(str(t[2]), r.get_center(), 15, UzTheme.col("text"))
		for sh in [[170.0, JOY_BUTTON_LEFT_SHOULDER, "LB" if not ps else "L1"], [580.0, JOY_BUTTON_RIGHT_SHOULDER, "RB" if not ps else "R1"]]:
			var r := Rect2(_p(sh[0], 96), Vector2(190, 34) * _s)
			draw_style_box(UzTheme.box(_fill(sh[1], Color(line, 0.9)), int(17 * _s)), r)
			_text(str(sh[2]), r.get_center(), 16, UzTheme.col("on_accent") if _down(sh[1]) else UzTheme.col("text"))
		# Sticks: Ring, darin der Knopf an seiner Position; gedrückt golden.
		_stick(Vector2(300, 250), Vector2(float(ax[0]), float(ax[1])), JOY_BUTTON_LEFT_STICK, ink, acc)
		_stick(Vector2(560, 370), Vector2(float(ax[2]), float(ax[3])), JOY_BUTTON_RIGHT_STICK, ink, acc)
		# Steuerkreuz.
		var dc := Vector2(390, 370)
		draw_rect(Rect2(_p(dc.x - 17, dc.y - 17), Vector2(34, 34) * _s), Color(line, 0.9))
		for d in [[JOY_BUTTON_DPAD_UP, Vector2(0, -36)], [JOY_BUTTON_DPAD_DOWN, Vector2(0, 36)], [JOY_BUTTON_DPAD_LEFT, Vector2(-36, 0)],
				[JOY_BUTTON_DPAD_RIGHT, Vector2(36, 0)]]:
			var c2: Vector2 = dc + (d[1] as Vector2)
			draw_style_box(UzTheme.box(_fill(d[0], Color(line, 0.9)), int(6 * _s)), Rect2(_p(c2.x - 18, c2.y - 18), Vector2(36, 36) * _s))
		# Tasten A/B/X/Y (bzw. Kreuz, Kreis, Quadrat, Dreieck).
		var fc := Vector2(660, 250)
		var cols := PC if ps else XC
		for f in [[JOY_BUTTON_Y, Vector2(0, -50), "y"], [JOY_BUTTON_B, Vector2(50, 0), "b"], [JOY_BUTTON_A, Vector2(0, 50), "a"],
				[JOY_BUTTON_X, Vector2(-50, 0), "x"]]:
			var c3 := _p(fc.x + (f[1] as Vector2).x, fc.y + (f[1] as Vector2).y)
			var col := Color(str(cols[f[2]]))
			var on := _down(f[0])
			draw_circle(c3, 25 * _s, col if on else Color(line, 0.95).lerp(col, 0.38 if done.has(f[0]) else 0.0))
			if not on:
				draw_arc(c3, 24 * _s, 0, TAU, 40, Color(col, 0.7), 2.0 * _s, true)
			_face(str(f[2]), c3, UzTheme.col("bg") if on else col)
		# View, Guide, Menü (und Teilen).
		for m in [[JOY_BUTTON_BACK, Vector2(420, 220)], [JOY_BUTTON_START, Vector2(520, 220)], [JOY_BUTTON_MISC1, Vector2(470, 280)]]:
			var c4: Vector2 = m[1]
			draw_style_box(UzTheme.box(_fill(m[0], Color(line, 0.95)), int(11 * _s)), Rect2(_p(c4.x - 20, c4.y - 11), Vector2(40, 22) * _s))
		draw_circle(_p(470, 170), 24 * _s, _fill(JOY_BUTTON_GUIDE, Color(line, 0.95)))
		_text("PS" if ps else "⌂", _p(470, 170), 16, UzTheme.col("on_accent") if _down(JOY_BUTTON_GUIDE) else UzTheme.col("muted"))

	func _stick(c: Vector2, v: Vector2, btn: int, ink: Color, acc: Color) -> void:
		var pressed := _down(btn)
		var base := _p(c.x, c.y)
		draw_circle(base, 64 * _s, Color(UzTheme.col("bg"), 0.55))
		draw_arc(base, 64 * _s, 0, TAU, 64, Color(ink, 0.5), 2.0 * _s, true)
		# Totzone der Bedienung (Einstellungen › Feineinstellung) als feiner Ring.
		var dz := clampf(float(Config.get_value("controller.deadzone", 0.5)), 0.15, 0.9)
		draw_arc(base, 64 * _s * dz, 0, TAU, 48, Color(ink, 0.25), 1.0 * _s, true)
		var k := base + v.limit_length(1.0) * 40.0 * _s
		draw_circle(k, 30 * _s, acc if pressed else UzTheme.col("text"))
		draw_circle(k, 22 * _s, Color(acc, 0.85) if pressed else UzTheme.col("surface_hi").lerp(acc, 0.35 if done.has(btn) else 0.0))

	func _face(id: String, c: Vector2, col: Color) -> void:
		if not ps:
			_text(id.to_upper(), c, 20, col)
			return
		var r := 10.0 * _s
		var w := 2.6 * _s
		match id:
			"a":
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, w, true)
				draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, w, true)
			"b":
				draw_arc(c, r, 0, TAU, 32, col, w, true)
			"x":
				draw_rect(Rect2(c - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), col, false, w)
			"y":
				var pts := PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r, r * 0.75), c + Vector2(-r, r * 0.75), c + Vector2(0, -r * 1.05)])
				draw_polyline(pts, col, w, true)

	func _text(t: String, c: Vector2, fs0: int, col: Color) -> void:
		var font := UzTheme.font("bold")
		var fs := maxi(10, int(fs0 * _s))
		var w := font.get_string_size(tr(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.5 - fs * 0.12), tr(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

extends "res://src/ui/layers/layer.gd"
## PIN eines Profils (Roadmap 109), ganz mit dem Controller: Ziffernfeld 3 × 4 mit dem Steuerkreuz,
## A tippt, X löscht die letzte Ziffer, B bricht ab. Auf der Tastatur gehen Ziffern, Rücktaste und
## Eingabe direkt. Die PIN selbst verlässt diese Ebene nie: geprüft und neu angelegt wird sie als
## gesalzener, langsamer Hash (src/core/profiles.gd) in einem eigenen Faden – die Oberfläche läuft
## weiter, die Punkte atmen so lange.
##
## mode:
##   check   PIN des Profils `target` prüfen → passed
##   parent  PIN eines Erwachsenen (Config.parent_ids) prüfen → passed
##   set     neue PIN zweimal eingeben → made(record) mit dem fertigen Hash
## Nach Fehlversuchen wartet Uzai länger (Bremse, übersteht einen Neustart).

signal passed
signal made(record: Dictionary)

const Profiles := preload("res://src/core/profiles.gd")
const ProfileAvatar := preload("res://src/ui/components/profile_avatar.gd")

const KEY := 96.0
const GAP := 22.0

var mode := "check"
var target: Dictionary = {}       ## Profil, um das es geht (Bild und Name oben)
var reason := ""                   ## kurzer Satz, wofür die PIN gebraucht wird
var _pin := ""
var _first := ""                   ## set: die erste Eingabe
var _dots: Control
var _title: Label
var _status: Label
var _keys: Array = []
var _job: Thread
var _busy := false
var _wait_timer: Timer


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	set_meta("uz_hint_b", "Abbrechen")
	set_meta("uz_hints", [["x", "Löschen"]])
	set_meta("uz_hints_center", true)
	var col := U.vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.custom_minimum_size.x = 760
	add_child(col)
	var who := Config.profile() if mode == "parent" else target
	if not who.is_empty():
		var av = ProfileAvatar.new().setup(who, 104)
		av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(av)
		var n := U.label(str(who.get("name", "")), "l", "text", "bold")
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
	col.add_child(U.spacer(0, 4, false))
	_title = U.label(_title_text(), "xl", "text", "bold")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	if reason != "":
		var rl := U.label(reason, "m", "muted", "regular", true)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rl)
	_dots = _Dots.new()
	_dots.custom_minimum_size = Vector2(420, 40)
	_dots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_dots)
	_status = U.label("", "s", "muted", "medium")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 28
	col.add_child(_status)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP * 0.8))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "ok"]:
		var key := _Key.new()
		key.id = k
		key.custom_minimum_size = Vector2(KEY, KEY)
		key.set_meta("uz_key", "pin:" + k)
		key.set_meta("uz_hint_a", { "del": "Löschen", "ok": "Bestätigen" }.get(k, "Tippen"))
		key.pressed_key.connect(_on_key)
		if k == "5":
			key.set_meta("uz_default", true)
		grid.add_child(key)
		_keys.append(key)
	col.add_child(U.spacer(0, 10, false))
	var honest := U.label(
			"Die PIN hält neugierige Blicke und Kinder fern. Sie ist keine Sicherheitsgrenze: Wer an dein Windows-Konto kommt, kommt auch an diese Daten.", "s", "faint",
			"regular", true)
	honest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	honest.custom_minimum_size.x = 700
	col.add_child(honest)
	# Sanft herein: von etwas unten, die Tasten nacheinander.
	col.modulate.a = 0.0
	col.position.y += 18
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "modulate:a", 1.0, U.T_ENTER)
	tw.tween_property(col, "position:y", col.position.y - 18, U.T_ENTER)
	_wait_timer = Timer.new()
	_wait_timer.wait_time = 0.5
	_wait_timer.timeout.connect(_update_wait)
	add_child(_wait_timer)
	_wait_timer.start()
	_update_wait()


func _title_text() -> String:
	match mode:
		"set":
			return "PIN wiederholen" if _first != "" else "Neue PIN"
		"parent":
			return "Eltern-PIN"
	return "PIN eingeben"


func _ids() -> Array:
	if mode == "parent":
		return Config.parent_ids()
	return [str(target.get("id", ""))] if mode == "check" else []


## Wartezeit nach Fehlversuchen: Tasten ruhen, ein Satz sagt, wie lange noch.
func _update_wait() -> void:
	if mode == "set" or _busy:
		return
	var w := Config.pin_wait(_ids())
	for k in _keys:
		k.resting = w > 0
	if w > 0:
		_status.text = "Zu viele Versuche. Bitte warte noch %d:%02d." % [w / 60, w % 60]
		U.set_label_color(_status, "warn")
	elif _status.text.begins_with("Zu viele"):
		_status.text = ""


func _on_key(k: String) -> void:
	if _busy or (mode != "set" and Config.pin_wait(_ids()) > 0):
		Sfx.play("bump")
		return
	match k:
		"del":
			if _pin.is_empty():
				Sfx.play("bump")
				return
			_pin = _pin.substr(0, _pin.length() - 1)
		"ok":
			_submit()
			return
		_:
			if _pin.length() >= Profiles.PIN_MAX:
				Sfx.play("bump")
				return
			_pin += k
	_dots.n = _pin.length()
	_dots.queue_redraw()
	if _status.text != "" and not _status.text.begins_with("Zu viele"):
		_status.text = ""


func _submit() -> void:
	if not Profiles.pin_format_ok(_pin):
		_fail("Die PIN hat 4 bis 8 Ziffern.", false)
		return
	if mode == "set":
		if _first == "":
			_first = _pin
			_pin = ""
			_dots.n = 0
			_title.text = _title_text()
			Sfx.play("tick")
			_dots.queue_redraw()
			return
		if _pin != _first:
			_first = ""
			_title.text = _title_text()
			_fail("Die beiden PINs waren verschieden. Bitte noch einmal.", false)
			return
		_run(func() -> Variant: return Profiles.make_pin(_first))
		return
	var recs: Array = []
	for id in _ids():
		var p := Profiles.find(Config.profiles, str(id))
		if p.has("pin"):
			recs.append(p.pin)
	var pin := _pin
	_run(func() -> Variant:
		for r in recs:
			if Profiles.check_pin(r, pin):
				return true
		return false
	)


## Langsames Rechnen im eigenen Faden; die Punkte atmen so lange.
func _run(work: Callable) -> void:
	_busy = true
	_dots.busy = true
	_job = Thread.new()
	_job.start(work)
	set_process(true)


func _process(_dt: float) -> void:
	if _dots and _dots.busy:
		_dots.queue_redraw()
	if _job == null or _job.is_alive():
		return
	var res: Variant = _job.wait_to_finish()
	_job = null
	_busy = false
	_dots.busy = false
	set_process(false)
	if mode == "set":
		if res is Dictionary and not (res as Dictionary).is_empty():
			Sfx.play("toggle_on")
			made.emit(res)
			close()
		return
	Config.pin_result(_ids(), bool(res))
	if bool(res):
		Sfx.play("toggle_on")
		passed.emit()
		close()
	else:
		var left := Config.pin_tries_left(_ids())
		_fail(tr("Falsche PIN. Noch %d Versuche ohne Pause.") % left if left > 0 else tr("Falsche PIN."), true)
		_update_wait()


func _fail(text: String, wrong: bool) -> void:
	Sfx.play("error")
	_status.text = text
	U.set_label_color(_status, "danger_text" if wrong else "warn")
	_pin = ""
	_dots.n = 0
	_dots.shake()


func handle(cmd: String) -> bool:
	if cmd == "x":
		_on_key("del")
		return true
	if cmd == "menu":
		_on_key("ok")
		return true
	return false


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo or Nav.top_layer() != self:
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_0 and k <= KEY_9:
		_on_key(str(k - KEY_0))
	elif k >= KEY_KP_0 and k <= KEY_KP_9:
		_on_key(str(k - KEY_KP_0))
	elif k == KEY_BACKSPACE:
		_on_key("del")
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_on_key("ok")
	else:
		return
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _job != null:
		_job.wait_to_finish()
		_job = null


## Punkte für die getippten Ziffern: leere Ringe bis vier, dann wächst die Reihe mit. Rechnet die
## PIN, atmen sie; falsch, schüttelt sich die Reihe kurz.
class _Dots extends Control:
	var n := 0
	var busy := false
	var _shake := 0.0

	func shake() -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_shake = v
			queue_redraw()
		, 1.0, 0.0, 0.42)

	func _draw() -> void:
		var slots := maxi(4, n)
		var gap := 34.0
		var w := (slots - 1) * gap
		var x0 := size.x * 0.5 - w * 0.5 + sin(_shake * 28.0) * 14.0 * _shake
		var y := size.y * 0.5
		var t := Time.get_ticks_msec() / 1000.0
		for i in slots:
			var c := Vector2(x0 + i * gap, y)
			if i < n:
				var a := 1.0
				if busy:
					a = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 6.0 - i * 0.7))
				draw_circle(c, 9.0, UzTheme.col("text", a), true, -1.0, true)
			else:
				draw_arc(c, 8.0, 0.0, TAU, 40, UzTheme.col("text", 0.32), 2.0, true)


## Eine Taste des Ziffernfelds: rundes Glas, gewählt die helle Auswahl.
class _Key extends Control:
	signal pressed_key(k: String)
	const UU := preload("res://src/ui/u.gd")
	var id := ""
	var resting := false:
		set(v):
			resting = v
			modulate.a = 0.4 if v else 1.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(func() -> void: UU.focus_anim(self, true))
		focus_exited.connect(func() -> void: UU.focus_anim(self, false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				grab_focus()
				Nav.activate(self)
				accept_event()
		)

	func activate() -> void:
		pressed_key.emit(id)

	func activate_sound() -> String:
		return "tick"

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var f: float = get_meta("uz_f", 0.0)
		var glass := StyleBoxFlat.new()
		glass.bg_color = UzTheme.col("text", 0.07 if id != "ok" else 0.13)
		glass.set_corner_radius_all(int(size.x * 0.5) - 1)
		glass.anti_aliasing = true
		draw_style_box(glass, r)
		UU.draw_focus(self, int(size.x * 0.5) - 1, r)
		var ink := UzTheme.col("text").lerp(UzTheme.col("on_focus"), f)
		if id == "del" or id == "ok":
			var ip := 34
			var tex := Icons.tex("chevron_left" if id == "del" else "check", ip)
			draw_texture_rect(tex, Rect2((size - Vector2(ip, ip)) * 0.5, Vector2(ip, ip)), false, ink if id == "del" else ink.lerp(UzTheme.col("accent_ink"), 1.0 - f))
		else:
			var font := UzTheme.display("bold")
			var fs := 40
			var sz := font.get_string_size(id, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, Vector2((size.x - sz.x) * 0.5, (size.y - sz.y) * 0.5 + font.get_ascent(fs)), id, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

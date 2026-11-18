extends Control
## One person in the Discord voice channel as a row of the Guide bar: avatar (a green, pulsing ring
## while speaking), name, what the person is doing; on the right LIVE, mic off or sound off, and a
## thin bar with the volume that applies only to you (tick at 100 %). Your own row is labelled „Du“
## and otherwise looks like every other row: muted is the crossed-out mic on the right, and X toggles
## mute: in your row your mic, in other rows that person for you, so mute behaves the same everywhere
## instead of differing between yourself and others. Y toggles the sound, only in your row.
## Same interface as the former tile (setup, refresh, appear, chosen, hold), so the menu and rebuilds
## stay the same.

signal chosen(member: Dictionary)

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const People := preload("res://src/ui/components/guide_people.gd")

const GuideRow := preload("res://src/ui/components/guide_row.gd")

const AV := 44

var member: Dictionary = {}
var live := false               ## du überträgst gerade (nur bei dir selbst)
var hold := false:              ## Menü an der Zeile offen: Auswahl bleibt sichtbar
	set(v):
		hold = v
		if is_inside_tree():
			_focus_to(v or has_focus())
var _f := 0.0
var _avatar: Control
var _ring: Control
var _name: Label
var _state: Label
var _badges: HBoxContainer
var _pulse := 0.0


func setup(m: Dictionary) -> Control:
	member = m
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 60
	set_meta("uz_key", "vm:" + str(member.get("id", "")))
	var m := U.margin(0, 4, 0, 4)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var row := U.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(AV, AV) + Vector2(4, 4)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	_avatar = Avatar.new()
	_avatar.setup(str(member.get("name", "?")), str(member.get("avatar", "")), "", AV)
	_avatar.position = Vector2(2, 2)
	holder.add_child(_avatar)
	_ring = _Ring.new()
	_ring.set("row", self)
	_ring.size = holder.custom_minimum_size
	holder.add_child(_ring)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nl := U.hbox(8)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nl)
	_name = U.label("", "20", "text", "ui_bold")
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Namen bleiben, wie sie sind
	nl.add_child(_name)
	if is_me():
		var du := U.label("Du", "cap", "faint", "medium")
		du.clip_text = false
		du.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nl.add_child(du)
	_state = U.ellipsis(U.label("", "16", "muted", "regular"))
	col.add_child(_state)
	_badges = U.hbox(10)
	_badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_badges)
	refresh(member)
	focus_entered.connect(_focus_to.bind(true))
	focus_exited.connect(func() -> void: _focus_to(hold))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func is_me() -> bool:
	return bool(member.get("me", false))


## Neuen Stand übernehmen, ohne die Zeile neu zu bauen (der Fokus bleibt).
func refresh(m: Dictionary) -> void:
	member = m
	if _name == null:
		return
	var me := is_me()
	_name.text = str(m.get("name", "?"))
	# So breit wie der Name (höchstens 260), damit „Du“ gleich dahinter steht.
	_name.custom_minimum_size.x = minf(260.0, UzTheme.ui("ui_bold").get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 2.0)
	var st := ""
	if me:
		var game := Library.display_title(Launcher.current) if Launcher.in_game else ""
		st = People.me_status(bool(m.get("speaking", false)), Mixer.mic_aus(), Voice.self_deaf, live, game, Video.active)
	else:
		st = Voice.status_text(m)
	_state.text = st
	U.set_label_color(_state, "speak" if st == "spricht" else "muted")
	U.clear(_badges)
	# Bei dir zählt das Mikro überall (Windows oder Discord), bei anderen ihr Stand in Discord.
	var muted: bool = Mixer.mic_aus() if me else (m.get("self_mute", false) or m.get("mute", false) or m.get("local_mute", false))
	var deaf: bool = Voice.self_deaf if me else (m.get("self_deaf", false) or m.get("deaf", false))
	if (live and me) or m.get("streaming", false):
		_badges.add_child(_Tag.new())
	if muted or deaf:
		_badges.add_child(U.icon("headset_off" if deaf else "mic_off", 20, "muted"))
	if me:
		set_meta("uz_hint_x", "Stumm aus" if muted else "Stumm")
		set_meta("uz_hint_y", "Ton an" if Voice.self_deaf else "Ton aus")
	else:
		var vb := _Vol.new()
		vb.value = clampf(float(m.get("volume", 100)) / 200.0, 0.0, 1.0)
		_badges.add_child(vb)
		set_meta("uz_hint_x", "Stumm aus" if m.get("local_mute", false) else "Stumm")
	set_process(m.get("speaking", false))
	if not m.get("speaking", false):
		_pulse = 0.0
	if _ring:
		_ring.queue_redraw()


func _process(dt: float) -> void:
	_pulse = fmod(_pulse + dt * 1.6, 1.0)
	_ring.queue_redraw()


func activate() -> void:
	chosen.emit(member)


## Weich einblenden, „Ankommen“ in T_ORT (gestaffelt aufgerufen vom Guide, U.staffel).
func appear(delay: float) -> void:
	modulate.a = 0.0
	U.ankommen(self, U.T_ORT, "uz_app").tween_property(self, "modulate:a", 1.0, U.T_ORT).set_delay(delay)


## Der eine Cursor-Takt (Liste.takt): im ersten Bild zu 70 % da, gesetzt in T_ANTWORT.
func _focus_to(on: bool) -> void:
	GuideRow.Liste.takt(self, _f, on, func(v: float) -> void:
		_f = v
		queue_redraw())


func _draw() -> void:
	GuideRow.draw_cursor(self, Rect2(-GuideRow.OUT, 0, size.x + GuideRow.OUT * 2.0, size.y), _f)


## Lautstärke nur für dich: dünner Balken (halb voll = 100 %, Strich dort).
class _Vol extends Control:
	var value := 0.5

	func _ready() -> void:
		custom_minimum_size = Vector2(88, 20)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_rect(Rect2(0, y - 1, size.x, 2), UzTheme.col("line"))
		draw_rect(Rect2(0, y - 1, size.x * value, 2), UzTheme.col("text", 0.8))
		draw_rect(Rect2(size.x * 0.5 - 1, y - 4, 2, 8), UzTheme.col("faint"))


## LIVE: eckiges Schild mit Rand im Akzent.
class _Tag extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var f := UzTheme.font("bold")
		custom_minimum_size = Vector2(f.get_string_size(tr("LIVE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18, 26)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(-0.5), UzTheme.col("accent"), false, 1.0)
		var f := UzTheme.font("bold")
		var w := f.get_string_size(tr("LIVE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f, Vector2((size.x - w) * 0.5, (size.y + f.get_ascent(15) - f.get_descent(15)) * 0.5), tr("LIVE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				UzTheme.col("accent"))


## Sprechen: Ring um das Bild, außen ein weicher, pulsierender Schein (für dich stumm: grau).
class _Ring extends Control:
	var row: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m: Dictionary = row.get("member")
		if not m.get("speaking", false):
			return
		var c := size * 0.5
		var rad := size.x * 0.5
		var green := UzTheme.col("faint") if m.get("local_mute", false) else UzTheme.col("speak")
		var p: float = row.get("_pulse")
		draw_arc(c, rad + 1 + p * 6, 0, TAU, 48, Color(green, 0.45 * (1.0 - p)), 2.0, true)
		draw_arc(c, rad, 0, TAU, 48, green, 2.5, true)

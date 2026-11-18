extends Control
## Eine Zeile der Guide-Leiste – die eine Listen-Sprache aller Reiter: links ein Symbol (oder ein
## eigenes Bild), dann der Titel, leise dahinter ein Zusatz („Aufnahme · letzte 30 s sichern“),
## rechts was die Zeile tut oder zeigt: ein Wert, eine Taste (X), ein Pfeil, ein Schalter oder ein
## Regler. Gewählt trägt sie den Cursor der Marke: einen eckigen weißen Rahmen (draw_cursor), die
## Schrift bleibt hell.
## Schalter und Regler nehmen links/rechts selbst (nav_lr → stepped). Mit hold_cb wartet A aufs
## Loslassen: kurz → activated, gehalten → hold_cb (Aufnahme: kurz sichern, halten aufnehmen).

signal activated
signal stepped(d: int)

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const H := 50                    ## Höhe einer Zeile (logische Pixel)
const HOLD_MS := 450             ## ab hier gilt A als gehalten
const OUT := Liste.OUT           ## so weit ragt der Cursor links und rechts über die Zeile

var title := ""
var extra := ""                  ## leise hinter dem Titel: „Titel · Zusatz“
var sub := ""                    ## zweite Zeile (selten)
var value := ""                  ## rechts als Text
var key_cmd := ""                ## rechts eine Taste (Glyphe), z. B. "x"
var chevron := false             ## rechts ›
var switch_state := -1           ## -1 kein Schalter, 0 aus, 1 an
var slider := -1.0               ## < 0 kein Regler, sonst 0 … 1
var icon_name := ""
var icon_color := "muted"
var lead: Control = null         ## eigenes Element links (Avatar, Cover) statt des Symbols
var trail: Control = null        ## eigenes Element rechts (vor Wert/Pfeil)
var own_text := false            ## Titel und Zusatz sind Namen (nicht übersetzen)
var hold_cb := Callable()
var min_h := H
var hold := false:               ## Menü an der Zeile offen: Auswahl bleibt sichtbar
	set(v):
		hold = v
		if is_inside_tree():
			_focus_to(v or has_focus())
var value_color := "muted"       ## Farbe des Werts rechts (warn: echtes Problem)
var _f := 0.0                    ## Cursor 0 … 1

var _title_l: Label
var _extra_l: Label
var _sub_l: Label
var _value_l: Label
var _bar: Control
var _sw: Control


func setup(t: String, ic := "", x := "", v := "") -> Control:
	title = t
	icon_name = ic
	extra = x
	value = v
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := U.margin(0, 4, 0, 4)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var row := U.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	if lead:
		lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lead)
	elif icon_name != "":
		var ic := U.icon(icon_name, 22, icon_color)
		ic.custom_minimum_size = Vector2(24, 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var col := U.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Mit Regler steht der Titel fest links, der Balken nimmt den Rest.
	if slider >= 0.0:
		col.custom_minimum_size.x = 150
	else:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var line := U.hbox(0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	_title_l = U.label(title, "20", "text", "ui")
	_title_l.clip_text = false
	line.add_child(_title_l)
	_extra_l = U.ellipsis(U.label("", "17", "muted", "medium"))
	_extra_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_extra_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_extra_l)
	if own_text:
		_title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_extra_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sub_l = U.ellipsis(U.label(sub, "cap", "muted", "regular"))
	_sub_l.visible = sub != ""
	col.add_child(_sub_l)
	set_extra(extra)
	if slider >= 0.0:
		_bar = _Bar.new()
		_bar.set("host", self)
		_bar.set("frac", slider)
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_bar)
	if trail:
		trail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(trail)
	_value_l = U.label(value, "17", value_color, "medium")
	_value_l.clip_text = false
	_value_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if slider >= 0.0:
		_value_l.custom_minimum_size.x = 44
		_value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value_l.add_theme_color_override("font_color", UzTheme.col("text"))
	_value_l.visible = value != "" or slider >= 0.0
	row.add_child(_value_l)
	if switch_state >= 0:
		_sw = _Switch.new()
		_sw.set("host", self)
		_sw.set("on", switch_state == 1)
		row.add_child(_sw)
	if key_cmd != "":
		var gl := U.glyph(key_cmd, 24)
		gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gl)
	if chevron:
		var ch := U.icon("chevron_right", 20, "faint")
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ch)
	custom_minimum_size.y = maxf(min_h, m.get_combined_minimum_size().y)
	focus_entered.connect(_focus_to.bind(true))
	focus_exited.connect(func() -> void: _focus_to(hold))
	gui_input.connect(_on_input)


## Eigener Rahmen im Cursor-Takt (Liste.takt); wandert die Auswahl in der Liste weiter, gleitet
## der eine Rahmen hinüber (Liste.cursor).
func _focus_to(on: bool) -> void:
	Liste.takt(self, _f, on, _set_f)


func _set_f(v: float) -> void:
	_f = v
	queue_redraw()


func _on_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	# Regler: Klick auf den Balken setzt den Wert dort (Maus und Touch).
	if _bar and has_focus() and _bar.get_global_rect().grow(8).has_point(get_global_mouse_position()):
		var f := clampf((get_global_mouse_position().x - _bar.global_position.x) / maxf(_bar.size.x, 1.0), 0.0, 1.0)
		var d := roundi((f - slider) * 20.0)
		if d != 0:
			stepped.emit(d)
		accept_event()
		return
	if has_focus():
		Nav.activate(self)
	else:
		grab_focus()
	accept_event()


func set_extra(t: String) -> void:
	extra = t
	if _extra_l:
		_extra_l.text = ("  ·  " + t) if t != "" else ""


func set_title(t: String) -> void:
	title = t
	if _title_l:
		_title_l.text = t


func set_value(t: String) -> void:
	value = t
	if _value_l:
		_value_l.text = t
		_value_l.visible = t != "" or slider >= 0.0


func set_switch(on: bool) -> void:
	switch_state = 1 if on else 0
	if _sw:
		_sw.set("on", on)
		_sw.queue_redraw()


## Links/rechts: Regler und Schalter stellen selbst, alles andere wandert weiter (Nav).
func nav_lr(d: int) -> bool:
	if slider >= 0.0 or switch_state >= 0:
		stepped.emit(d)
		return true
	return false


func activate() -> void:
	if not hold_cb.is_valid():
		activated.emit()
		return
	# A gehalten? Bis zum Loslassen warten (höchstens HOLD_MS), dann das eine oder das andere.
	var t0 := Time.get_ticks_msec()
	while is_inside_tree() and _pressed():
		if Time.get_ticks_msec() - t0 >= HOLD_MS:
			Pads.pulse("clip")
			hold_cb.call()
			return
		await get_tree().process_frame
	activated.emit()


static func _pressed() -> bool:
	return Input.is_action_pressed("uz_a", true) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _draw() -> void:
	draw_cursor(self, Rect2(-OUT, 0, size.x + OUT * 2.0, size.y), _f)


## Der Cursor der Leiste, überall gleich (gemeinsamer Baustein, liste.gd): gehobene gerundete Fläche.
static func draw_cursor(ci: CanvasItem, rect: Rect2, t: float) -> void:
	Liste.cursor(ci, rect, t)


## Regler: dünne Spur, gefüllt im Akzent, runder Griff. Gewählt: in der Tinte der Auswahl.
class _Bar extends Control:
	var host: Control
	var frac := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(80, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if host:
			host.draw.connect(queue_redraw)

	func _draw() -> void:
		var y := size.y * 0.5
		var x := size.x * clampf(frac, 0.0, 1.0)
		draw_style_box(UzTheme.box(UzTheme.col("line"), 999), Rect2(0, y - 2, size.x, 4))
		if x > 0.5:
			draw_style_box(UzTheme.box(UzTheme.col("accent"), 999), Rect2(0, y - 2, maxf(x, 4.0), 4))
		Liste.griff(self, Vector2(clampf(x, 7.0, size.x - 7.0), y), 7.0)


## Schalter: weiche Pille (Liste.schalter), an die Spur im Akzent; „An“/„Aus“ steht als Wert davor.
class _Switch extends Control:
	var host: Control
	var on := false

	func _ready() -> void:
		custom_minimum_size = Vector2(38, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if host:
			host.draw.connect(queue_redraw)

	func _draw() -> void:
		Liste.schalter(self, Rect2(Vector2(0, (size.y - 22.0) * 0.5), Vector2(38, 22)), 1.0 if on else 0.0)

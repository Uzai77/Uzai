extends Control
## Eine Zeile für Geräte und Netze (Bild & Ton, WLAN, Bluetooth): Symbol, Name, leise Zeile
## darunter, rechts der Zustand mit Haken für das, was gerade gilt, ein Schloss für Netze mit
## Passwort und die Signalstärke in vier Balken. Namen kommen von Windows bzw. von Geräten in
## Funkreichweite und werden nie übersetzt. Gewählt: helle Fläche wie alle Zeilen.

signal activated

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var title := ""
var subtitle := ""
var icon_name := ""
var state := ""              ## rechts („Aktiv“, „Verbunden“) – Uzais eigener Text
var on := false              ## gilt gerade: Haken statt nur Text
var lock := false
var bars := -1               ## 0..4 Signalbalken, -1 = keine
var dim := false             ## geht hier nicht (Firmen-WLAN, WEP): leiser
var min_h := 78
var _title_l: Label
var _sub_l: Label
var _state_l: Label
var _check: TextureRect

const BAR_W := 5.0
const BAR_GAP := 3.0
const BAR_H := 20.0


func setup(t: String, sub := "", ic := "") -> Control:
	title = t
	subtitle = sub
	icon_name = ic
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := U.margin(20, 10, 22, 10)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(18)
	m.add_child(row)
	if icon_name != "":
		var ic := U.icon(icon_name, 26, "faint" if dim else "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_title_l = U.ellipsis(U.label(title, "m", "muted" if dim else "text", "ui_bold" if on else "ui"))
	_title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_title_l)
	_sub_l = U.ellipsis(U.label(subtitle, "s", "faint" if dim else "muted", "regular"))
	_sub_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_sub_l.visible = subtitle != ""
	col.add_child(_sub_l)
	_check = U.icon("check", 22, "ok")
	_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check.visible = on
	row.add_child(_check)
	_state_l = U.label(state, "s", "text" if on else "muted", "medium")
	_state_l.clip_text = false
	_state_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_state_l.visible = state != ""
	row.add_child(_state_l)
	if lock:
		var lk := U.icon("lock", 20, "faint")
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lk)
	if bars >= 0:
		var b := Control.new()
		b.custom_minimum_size = Vector2(BAR_W * 4 + BAR_GAP * 3, BAR_H)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.draw.connect(_draw_bars.bind(b))
		draw.connect(b.queue_redraw)
		row.add_child(b)
	custom_minimum_size.y = maxf(min_h, m.get_combined_minimum_size().y)
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		U.etikett(self, false)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Zustand ändern, ohne die Zeile neu zu bauen (Verbinden läuft, Gerät ist jetzt aktiv).
func set_state(t: String, is_on := on) -> void:
	state = t
	on = is_on
	if _state_l:
		_state_l.text = t
		_state_l.visible = t != ""
		_check.visible = is_on


func activate() -> void:
	activated.emit()


func _draw() -> void:
	Liste.zeilen_auswahl(self)


## Vier Balken von klein nach groß; die erreichten in Tinte, die übrigen leise. Auf der hellen
## Auswahl in deren dunkler Schrift (im selben Takt wie die Schrift).
func _draw_bars(c: Control) -> void:
	var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
	var full := UzTheme.col("text").lerp(UzTheme.col("on_focus"), f)
	var low := Color(full, 0.22)
	for i in 4:
		var h := BAR_H * (0.4 + 0.2 * i)
		var r := Rect2(i * (BAR_W + BAR_GAP), BAR_H - h, BAR_W, h)
		c.draw_rect(r, full if i < bars else low)

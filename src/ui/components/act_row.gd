extends Control
## Eine Handlung als Zeile (Guide): Symbol in einer runden Glasfläche, Titel, kleiner Zusatz,
## rechts ein Wert. Gewählt: helle Fläche, Schrift dunkel.

signal activated

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var title := ""
var sub := ""
var value := ""
var icon_name := ""
var danger := false
var game: Dictionary = {}           ## gesetzt: statt des Symbols das Bild des Spiels
var min_h := 74
var _value_l: Label
var _title_l: Label
var _sub_l: Label
var _ib: Control


func setup(t: String, ic: String, s := "", v := "", red := false) -> Control:
	title = t
	icon_name = ic
	sub = s
	value = v
	danger = red
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := U.margin(12, 10, 18, 10)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(16)
	m.add_child(row)
	var ib := _IconBox.new()
	ib.icon_name = icon_name
	ib.danger = danger
	ib.row = self
	ib.game = game
	row.add_child(ib)
	_ib = ib
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_title_l = U.ellipsis(U.label(title, "m", "danger_text" if danger else "text", "ui" if UzTheme.strict() else "ui_bold"))
	col.add_child(_title_l)
	_sub_l = U.ellipsis(U.label(sub, "s", "muted", "regular"))
	_sub_l.visible = sub != ""
	col.add_child(_sub_l)
	_value_l = U.label(value, "s", "muted", "medium")
	_value_l.clip_text = false
	_value_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_value_l)
	custom_minimum_size.y = maxf(min_h, m.get_combined_minimum_size().y)
	# Die runde Glasfläche blendet im selben Takt wie die helle Auswahl um (nicht schlagartig).
	draw.connect(_ib.queue_redraw)
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


func set_value(v: String) -> void:
	value = v
	if _value_l:
		_value_l.text = v


func set_title(t: String, s := "") -> void:
	title = t
	sub = s
	if _title_l:
		_title_l.text = t
		_sub_l.text = s
		_sub_l.visible = s != ""


func activate() -> void:
	activated.emit()


func _draw() -> void:
	Liste.zeilen_auswahl(self, UzTheme.radius + 2)


## Runde Glasfläche mit Symbol; wird auf heller Auswahl selbst dunkel getönt.
class _IconBox extends Control:
	const UU := preload("res://src/ui/u.gd")
	var icon_name := ""
	var danger := false
	var row: Control
	var game: Dictionary = {}

	func _ready() -> void:
		custom_minimum_size = Vector2(30, 46) if UzTheme.strict() and game.is_empty() else Vector2(46, 46)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cc)
		var ic := UU.icon(icon_name, 22, "danger_text" if danger else "text")
		cc.add_child(ic)
		if game.is_empty():
			return
		# Spielbild statt Symbol: erst das quadratische Symbol des Spiels, sonst das Cover.
		var img := UU.rounded_image(15.0)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.modulate.a = 0.0
		add_child(img)
		var me: WeakRef = weakref(self)
		var show := func(t: Texture2D) -> void:
			if me.get_ref() == null or t == null:
				return
			img.texture = t
			ic.visible = false
			create_tween().tween_property(img, "modulate:a", 1.0, 0.25)
		Media.game_texture(game, "icon", func(t: Texture2D) -> void:
			if t:
				show.call(t)
			else:
				Media.game_texture(game, "cover", show)
		)

	func _draw() -> void:
		# Eckig (Marke): das Symbol steht frei neben dem Wort, ohne Fläche darum (wie im Guide).
		if UzTheme.strict() and game.is_empty():
			return
		var f: float = 0.0
		if is_instance_valid(row):
			f = row.get_meta("uz_f", 1.0 if row.has_focus() else 0.0)
		var rest := Color(UzTheme.col("danger"), 0.16) if danger else UzTheme.col("glass_hi")
		var bg := rest.lerp(UzTheme.col("on_focus", 0.08), f)
		draw_style_box(UzTheme.box(bg, 15), Rect2(Vector2.ZERO, size))

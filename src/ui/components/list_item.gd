extends Control
## Eine Zeile in Listen (Freunde, Mitteilungen, Playlists, Erfolge): vorne Bild oder Symbol,
## dann Titel und Untertitel, hinten ein kurzer Wert.

signal activated

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var title := ""
var subtitle := ""
var trailing := ""
var icon_name := ""
var image_url := ""
var image_size := Vector2(56, 56)   ## Größe des kleinen Bilds (Spielstände: 16:9)
var avatar := false
var status := ""
var sub_color := "muted"
var locked := false
var min_h := 76
var sub_lines := 1          ## mehr als 1: der Untertitel bricht um (Mitteilungen: ganzer Satz statt „…“)
var row_width := 0
var _focus := false


func setup(t: String, sub := "", trail := "") -> Control:
	title = t
	subtitle = sub
	trailing = trail
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	if row_width > 0:
		custom_minimum_size.x = row_width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := U.margin(14, 10, 18, 10)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(18)
	m.add_child(row)
	if avatar:
		var av := Avatar.new()
		av.setup(title, image_url, status, 52)
		row.add_child(av)
	elif image_url != "":
		var frame := Panel.new()
		# Kleines Bild: dieselbe Rundung wie Cover, nur etwas knapper.
		frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), maxi(4, int(round(UzTheme.r_cover() * 0.7)))))
		U.clip_round(frame, CanvasItem.CLIP_CHILDREN_AND_DRAW)
		frame.custom_minimum_size = image_size
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		U.full_rect(tr)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			tr.modulate = Color(1, 1, 1, 0.45)
		frame.add_child(tr)
		row.add_child(frame)
		var cb := func(t: Texture2D) -> void:
			if is_instance_valid(tr) and t:
				tr.texture = t
		if image_url.begins_with("http"):
			Media.url_texture(image_url, 128, cb)
		else:
			Media.file_texture(image_url, maxi(128, int(image_size.x * 2.0)), cb)
	elif icon_name != "":
		# Symbol frei neben dem Text, nicht in einem getönten Quadrat.
		var ic := U.icon(icon_name, 28, "muted")
		ic.custom_minimum_size = Vector2(40, 52)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := U.ellipsis(U.label(title, "m", "faint" if locked else "text", "ui"))
	col.add_child(tl)
	if subtitle != "" and sub_lines > 1:
		var sl := U.label(subtitle, "s", sub_color, "regular", true)
		sl.max_lines_visible = sub_lines
		col.add_child(sl)
		m.minimum_size_changed.connect(func() -> void: custom_minimum_size.y = maxf(min_h, m.get_combined_minimum_size().y))
	elif subtitle != "":
		col.add_child(U.ellipsis(U.label(subtitle, "s", sub_color, "regular")))
	row.add_child(col)
	if trailing != "":
		# Rechts ein kurzer Wert, leise wie im Guide („Gerade eben“, „2:12“).
		var tr2 := U.label(trailing, "s", "muted", "medium")
		tr2.clip_text = false
		tr2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tr2)
	custom_minimum_size.y = maxf(min_h, m.get_combined_minimum_size().y)
	focus_entered.connect(func() -> void:
		Liste.fokus(self, true)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		Liste.fokus(self, false)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func activate() -> void:
	activated.emit()


## A gedrückt: nur der Rahmen drückt (Liste.druck), die Zeile wird nicht skaliert.
func press_feedback() -> void:
	Liste.druck(self)


func _draw() -> void:
	Liste.zeilen_auswahl(self)

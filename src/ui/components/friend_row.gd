extends Control
## Ein Freund in der Liste: Profilbild mit Status, der Name, darunter was er gerade macht
## (im Spiel grün mit Punkt), rechts neue Nachrichten (Gold) oder „Beitreten“. Wer offline
## ist, tritt etwas zurück. Gewählt: helle Fläche, Schrift dunkel (wie jede Zeile in Uzai).

signal activated

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var who := ""
var line := ""
var line_color := "muted"
var image_url := ""
var status := ""
var unread := 0
var joinable := false
var badge_icon := ""             ## kleines Symbol rechts (z. B. Kopfhörer im Sprachkanal)
var glyph_icon := ""             ## statt Profilbild ein Symbol im Kreis (Sprachkanal)
var stack: Array = []            ## kleine Bilder rechts übereinander: [{ name, avatar }]
var faded := false               ## offline: Bild und Name leiser
var min_h := 84
var _avatar: Control


func setup(name_: String, line_: String, img := "", st := "") -> Control:
	who = name_
	line = line_
	image_url = img
	status = st
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = min_h
	var m := U.margin(14, 10, 18, 10)
	U.full_rect(m)
	add_child(m)
	var row := U.hbox(18)
	m.add_child(row)
	if glyph_icon != "":
		var disc := PanelContainer.new()
		disc.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("discord", 0.16), 999))
		disc.custom_minimum_size = Vector2(60, 60)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(U.icon(glyph_icon, 28, "discord"))
		disc.add_child(cc)
		_avatar = disc
	else:
		_avatar = Avatar.new()
		_avatar.setup(who, image_url, status, 60)
		_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if faded:
		_avatar.modulate = Color(1, 1, 1, 0.55)
	row.add_child(_avatar)
	var col := U.vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var wl := U.ellipsis(U.label(who, "m", "muted" if faded else "text", "ui_bold"))
	wl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Namen bleiben, wie sie sind
	col.add_child(wl)
	if line != "":
		col.add_child(U.ellipsis(U.label(line, "s", line_color, "regular")))
	row.add_child(col)
	if not stack.is_empty():
		var st := U.hbox(-10)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for p in stack.slice(0, 4):
			var a := Avatar.new()
			a.setup(str(p.get("name", "")), str(p.get("avatar", "")), "", 34)
			st.add_child(a)
		row.add_child(st)
	if unread > 0:
		row.add_child(_count_pill(unread))
	elif joinable:
		row.add_child(_join_pill())
	elif badge_icon != "":
		var ic := U.icon(badge_icon, 22, "discord")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	focus_entered.connect(func() -> void:
		U.etikett(self, true)
		if faded:
			U.tw(_avatar, "uz_fade").tween_property(_avatar, "modulate:a", 1.0, U.T_BASE)
		queue_redraw()
	)
	focus_exited.connect(func() -> void:
		U.etikett(self, false)
		if faded:
			U.tw(_avatar, "uz_fade").tween_property(_avatar, "modulate:a", 0.55, U.T_BASE)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Goldene Zahl für ungelesene Nachrichten.
func _count_pill(n: int) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("accent"), 999)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := U.label(str(n) if n < 100 else "99+", "s", "on_accent", "ui_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 14
	p.add_child(l)
	return p


## „Beitreten“: das Spiel des Freundes lässt dich gerade mitspielen.
func _join_pill() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("ok", 0.14), 999)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(6)
	var ic := U.icon("play", 16, "ok")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := U.label("Beitreten", "16", "ok", "ui_bold")
	l.clip_text = false
	h.add_child(l)
	p.add_child(h)
	return p


func activate() -> void:
	activated.emit()


## Geteilte Elemente (src/ui/flug.gd): das Profilbild fliegt ins Profil, der Name bleibt stehen.
func flug_bild() -> Dictionary:
	if _avatar == null or not is_instance_valid(_avatar) or not _avatar.has_method("flug_bild"):
		return {}
	var d: Dictionary = _avatar.call("flug_bild")
	if not d.is_empty():
		d["hide"] = _avatar
	return d


func _draw() -> void:
	Liste.zeilen_auswahl(self)

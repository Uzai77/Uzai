extends "res://src/ui/layers/layer.gd"
## Kanalseite oder Playlist als eigene Seite über allem. Oben ein breites Banner – das echte
## Banner des Kanals, sonst ein ruhiges Farbfeld in seiner Farbe –, das große Profilbild, Name
## und Angaben, darunter „Alle abspielen“, „Zufällig“ und Abonnieren. Dann alle Videos im Raster.
## Beim Blättern zieht das Banner langsamer mit und blendet aus (Tiefe statt harter Kante).
## X abonniert den Kanal oder beendet das Abo.

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")

const GUTTER := 96
const CARD_W := 408.0
const BANNER_H := 420.0

var heading := ""
var subheading := ""
var loader: Callable
var channel_id := ""
const Main := preload("res://src/main.gd")
var main: Main
var _list: Array = []
var _grid: GridContainer
var _status: Label
var _sub_l: Label
var _banner: Control
var _banner_img: TextureRect
var _sc: ScrollContainer
var _btn_row: HBoxContainer
var _skeleton: Control
var _avatar: Control


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	if channel_id != "":
		_update_hints()
		# Geteilte Elemente (src/ui/flug.gd): das runde Bild der Kanal-Kachel landet auf dem Profilbild.
		set_meta("uz_flug", "ch:" + channel_id)
	_build_banner()
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 140.0)
	U.full_rect(_sc)
	add_child(_sc)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(col)
	col.add_child(U.spacer(0, BANNER_H - 170.0, false))
	col.add_child(_build_head())
	var inner := U.margin(GUTTER, 44, GUTTER, 90)
	col.add_child(inner)
	var stack := U.vbox(16)
	inner.add_child(stack)
	_status = U.label("", "l", "muted")
	_status.visible = false
	stack.add_child(_status)
	_skeleton = _build_skeleton()
	stack.add_child(_skeleton)
	_grid = GridContainer.new()
	_grid.columns = U.cols_for(4)
	_grid.add_theme_constant_override("h_separation", 32)
	_grid.add_theme_constant_override("v_separation", 40)
	_grid.set_meta("uz_group", "kanal-videos")
	stack.add_child(_grid)
	# Ein unsichtbarer Platzhalter, damit die Steuerung schon während des Ladens hier bleibt.
	var hold := Control.new()
	hold.focus_mode = Control.FOCUS_ALL
	hold.custom_minimum_size = Vector2(1, 1)
	hold.set_meta("uz_hint_a", "—")
	hold.name = "Hold"
	stack.add_child(hold)
	_load()


# --- Kopf --------------------------------------------------------------------------------------

func _build_banner() -> void:
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_right = 1.0
	_banner.offset_bottom = BANNER_H
	add_child(_banner)
	var poster := TextureRect.new()
	poster.texture = VideoCard.poster_for(heading)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_SCALE
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(poster)
	_banner.add_child(poster)
	_banner_img = TextureRect.new()
	_banner_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_banner_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_img.modulate.a = 0.0
	U.full_rect(_banner_img)
	_banner.add_child(_banner_img)
	# Nach unten läuft das Banner weich in den Raum aus; oben leicht dunkler.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	var bg := UzTheme.col("bg")
	g.colors = PackedColorArray([Color(bg, 0.35), Color(bg, 0.05), Color(bg, 0.7), Color(bg, 1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var fade := TextureRect.new()
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(fade)
	_banner.add_child(fade)
	var info := YouTube.channel_info(channel_id) if channel_id != "" else {}
	var url := str(info.get("banner", ""))
	if url != "" and not YouTube.demo:
		var wr: WeakRef = weakref(_banner_img)
		Media.url_texture(url, 1920, func(t: Texture2D) -> void:
			var img: TextureRect = wr.get_ref()
			if t and img and is_instance_valid(img):
				img.texture = t
				U.tw(img, "uz_fade").tween_property(img, "modulate:a", 1.0, U.T_AMBIENT)
		)


func _build_head() -> Control:
	var m := U.margin(GUTTER, 0, GUTTER, 0)
	var row := U.hbox(40)
	m.add_child(row)
	var info := YouTube.channel_info(channel_id) if channel_id != "" else {}
	if channel_id != "":
		var av := Avatar.new()
		av.setup(heading, str(info.get("avatar", _sub_thumb())), "", 176)
		av.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(av)
		_avatar = av
	else:
		row.add_child(_list_tile())
	var titles := U.vbox(6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(titles)
	var kind := U.label("Playlist" if channel_id == "" else "Kanal", "s", "accent", "medium")
	titles.add_child(kind)
	var h := U.ellipsis(U.label(heading, "xxl", "text", "black"))
	# Name des Kanals bzw. der Playlist: nie übersetzen (nur „Mag ich“ ist ein Wort von Uzai).
	if heading != "Mag ich":
		h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	U.shadow(h, 0.4)
	titles.add_child(h)
	_sub_l = U.label("", "m", "muted")
	titles.add_child(_sub_l)
	_update_sub_line()
	titles.add_child(U.spacer(0, 14, false))
	_btn_row = U.hbox(16)
	_btn_row.set_meta("uz_group", "kanal-knoepfe")
	titles.add_child(_btn_row)
	_build_buttons()
	return m


## Wo das Bild der Kanal-Kachel landet (src/ui/flug.gd): das große Profilbild im Kopf.
func flug_ziel() -> Control:
	return _avatar if is_instance_valid(_avatar) else null


## Für Playlists statt des Profilbilds: eine Kachel in der Farbe der Liste mit Symbol.
func _list_tile() -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(176, 176)
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel()))
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	var tr := TextureRect.new()
	tr.texture = VideoCard.poster_for(heading)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	U.full_rect(tr)
	p.add_child(tr)
	var c := CenterContainer.new()
	U.full_rect(c)
	c.add_child(U.icon("heart_f" if heading == "Mag ich" else "list", 64, "text"))
	p.add_child(c)
	return p


func _update_sub_line() -> void:
	if not is_instance_valid(_sub_l):
		return
	var parts := PackedStringArray()
	if not _list.is_empty():
		parts.append(U.plural(_list.size(), "Video", "Videos"))
	elif subheading != "" and subheading != "Kanal" and subheading != "Playlist":
		parts.append(subheading)
	if channel_id != "":
		var f := int(YouTube.channel_info(channel_id).get("followers", 0))
		if f > 0:
			parts.append(YouTube.followers_text(f))
		if YouTube.is_subscribed(channel_id):
			parts.append("abonniert")
	_sub_l.text = "  ·  ".join(parts) if not parts.is_empty() else ""


func _build_buttons() -> void:
	if not is_instance_valid(_btn_row):
		return
	var had := Nav.focused() != null and _btn_row.is_ancestor_of(Nav.focused())
	var key := str(Nav.focused().get_meta("uz_key", "")) if had else ""
	U.clear(_btn_row)
	var play := U.button("Alle abspielen", "play", "primary")
	play.set_meta("uz_key", "kanal:play")
	play.set_meta("uz_default", true)
	play.set_meta("uz_hint_a", "Abspielen")
	play.pressed.connect(func() -> void: _play_all(false))
	_btn_row.add_child(play)
	var mix := U.button("Zufällig", "shuffle")
	mix.set_meta("uz_key", "kanal:mix")
	mix.set_meta("uz_hint_a", "Zufällig abspielen")
	mix.pressed.connect(func() -> void: _play_all(true))
	_btn_row.add_child(mix)
	if channel_id != "":
		var subbed := YouTube.is_subscribed(channel_id)
		var sb := U.button("Abonniert" if subbed else "Abonnieren", "check" if subbed else "plus")
		sb.set_meta("uz_key", "kanal:abo")
		sb.set_meta("uz_hint_a", "Abo beenden" if subbed else "Abonnieren")
		sb.pressed.connect(_toggle_sub)
		_btn_row.add_child(sb)
	if had:
		for b in _btn_row.get_children():
			if str((b as Control).get_meta("uz_key", "")) == key:
				Nav.focus(b, true)


func _play_all(shuffle: bool) -> void:
	if _list.is_empty():
		return
	var l := _list.duplicate()
	if shuffle:
		l.shuffle()
	close()
	main.open_video(l, 0)


func _toggle_sub() -> void:
	if YouTube.is_subscribed(channel_id):
		YouTube.unsubscribe(channel_id)
		Toasts.show_toast("Abo beendet", heading, "channel", { "sound": "select", "quiet": true })
	else:
		YouTube.subscribe(channel_id, heading, str(YouTube.channel_info(channel_id).get("avatar", "")))
		Toasts.show_toast("Abonniert", heading, "channel", { "sound": "select", "quiet": true })
	_update_hints()
	_update_sub_line()
	_build_buttons()
	Nav.focus_moved.emit(Nav.focused())


func _sub_thumb() -> String:
	for s in YouTube.data.subs:
		if str(s.id) == channel_id:
			return str(s.get("thumb", ""))
	return ""


## Platzhalter-Karten in der Form der kommenden Reihe, solange geladen wird (der eine ruhige
## Schimmer aller Platzhalter, kein Pulsieren, kein Text).
func _build_skeleton() -> Control:
	return Skeleton.cards(4, Vector2(CARD_W, round(CARD_W * 9.0 / 16.0)), 32)


func _process(_dt: float) -> void:
	# Tiefe: das Banner zieht beim Blättern halb so schnell mit und blendet aus.
	if is_instance_valid(_sc) and is_instance_valid(_banner):
		var y := float(_sc.scroll_vertical)
		_banner.position.y = -y * 0.5
		_banner.modulate.a = clampf(1.0 - y / (BANNER_H * 1.2), 0.0, 1.0)


# --- Videos ------------------------------------------------------------------------------------

func _load() -> void:
	if not loader.is_valid():
		return
	_list = await loader.call()
	if not is_inside_tree():
		return
	if is_instance_valid(_skeleton):
		_skeleton.queue_free()
	_status.text = "" if not _list.is_empty() else (YouTube.error if YouTube.error != "" else "Keine Videos gefunden.")
	_status.visible = _status.text != ""
	_update_sub_line()
	_build_buttons()
	for i in _list.size():
		var v: Dictionary = _list[i]
		var c = VideoCard.new()
		c.setup(v, CARD_W, channel_id == "")
		var resume := YouTube.resume_pos(str(v.get("id", "")))
		c.set_meta("uz_hint_a", ("Weiterschauen ab " + YouTube.time_text(resume)) if resume > 20 else "Abspielen")
		c.set_meta("uz_hint_y", "Optionen")
		var idx := i
		c.set_meta("uz_on_y", func() -> void: main.open_video_options(v, _list, idx))
		c.chosen.connect(func(_v: Dictionary) -> void:
			close()
			main.open_video(_list, idx)
		)
		_grid.add_child(c)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var hold := find_child("Hold", true, false)
	if hold:
		if hold.has_focus() and Nav.top_layer() == self:
			Nav.focus(Nav.default_in(_btn_row), true)
		hold.queue_free()


func _update_hints() -> void:
	set_meta("uz_hints", [["x", "Abo beenden" if YouTube.is_subscribed(channel_id) else "Abonnieren"]])


func handle(cmd: String) -> bool:
	if cmd == "x" and channel_id != "":
		_toggle_sub()
		return true
	if cmd == "menu":
		var f := Nav.focused()
		if f and f.get("video") is Dictionary:
			var v: Dictionary = f.get("video")
			main.open_video_options(v, _list, _list.find(v))
		return true
	return false

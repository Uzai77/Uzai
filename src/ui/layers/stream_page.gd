extends "res://src/ui/layers/layer.gd"
## Kanal oder Kategorie von Twitch als eigene Seite über allem (wie die Kanalseite bei Videos).
## Kanal: oben das Banner des Kanals (sonst ein ruhiges Farbfeld in seiner Farbe), das große
## Profilbild, Name, Follower und – wenn er gerade live ist – Kategorie und Zuschauer; darunter
## „Live ansehen“ und „Link aufs Handy“. Dann „Jetzt live“, „Letzte Übertragungen“ und „Clips“.
## Kategorie: die Spielhülle statt des Profilbilds, darunter alle Streams, die gerade laufen.
## Beim Blättern zieht das Banner langsamer mit und blendet aus.

const Skeleton := preload("res://src/ui/components/skeleton.gd")
const StreamCard := preload("res://src/ui/components/stream_card.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const TP := preload("res://src/core/twitch_parse.gd")

const GUTTER := 96
const CARD_W := 408.0
const BANNER_H := 420.0

var login := ""                ## Kanal (oder leer)
var game: Dictionary = {}      ## Kategorie (oder leer)
var heading := ""
const Main := preload("res://src/main.gd")
var main: Main
var _data: Dictionary = {}
var _status: Label
var _sub_l: Label
var _banner_img: TextureRect
var _banner: Control
var _sc: ScrollContainer
var _btn_row: HBoxContainer
var _stack: VBoxContainer
var _skeleton: Control
var _head_art: Control
var _title_l: Label


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	if heading == "":
		heading = str(game.get("title", login))
	if game.is_empty() and login != "":
		# Geteilte Elemente (src/ui/flug.gd): das runde Bild der Kanal-Kachel landet auf dem Profilbild.
		set_meta("uz_flug", "ch:tw:" + login)
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
	col.add_child(U.spacer(0, int(BANNER_H) - 170, false))
	col.add_child(_build_head())
	var inner := U.margin(GUTTER, 44, GUTTER, 90)
	col.add_child(inner)
	_stack = U.vbox(16)
	inner.add_child(_stack)
	_status = U.label("", "l", "muted")
	_status.visible = false
	_stack.add_child(_status)
	_skeleton = _build_skeleton()
	_stack.add_child(_skeleton)
	# Ein unsichtbarer Platzhalter, damit die Steuerung schon während des Ladens hier bleibt.
	var hold := Control.new()
	hold.focus_mode = Control.FOCUS_ALL
	hold.custom_minimum_size = Vector2(1, 1)
	hold.set_meta("uz_hint_a", "—")
	hold.name = "Hold"
	_stack.add_child(hold)
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


func _set_banner(url: String) -> void:
	if url == "" or not is_instance_valid(_banner_img):
		return
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
	_head_art = Control.new()
	_head_art.custom_minimum_size = Vector2(176, 176) if game.is_empty() else Vector2(150, 200)
	_head_art.size_flags_vertical = Control.SIZE_SHRINK_END
	_head_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_head_art)
	_fill_art("")
	var titles := U.vbox(6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(titles)
	titles.add_child(U.label("Kategorie" if not game.is_empty() else "Kanal", "s", "accent", "medium"))
	_title_l = U.ellipsis(U.label(heading, "xxl", "text", "black"))
	_title_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Kanals bzw. der Kategorie: nie übersetzen
	U.shadow(_title_l, 0.4)
	titles.add_child(_title_l)
	_sub_l = U.label("", "m", "muted")
	titles.add_child(_sub_l)
	titles.add_child(U.spacer(0, 14, false))
	_btn_row = U.hbox(16)
	_btn_row.set_meta("uz_group", "skanal-knoepfe")
	titles.add_child(_btn_row)
	return m


## Wo das Bild der Kanal-Kachel landet (src/ui/flug.gd): das Profilbild im Kopf.
func flug_ziel() -> Control:
	if game.is_empty() and is_instance_valid(_head_art) and _head_art.get_child_count() > 0:
		return _head_art.get_child(0)
	return null


## Profilbild (Kanal) oder Spielhülle (Kategorie) links im Kopf.
func _fill_art(url: String) -> void:
	U.clear(_head_art)
	if game.is_empty():
		var av := Avatar.new()
		av.setup(heading, url, "", 176)
		_head_art.add_child(av)
		return
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = _head_art.custom_minimum_size
	_head_art.add_child(p)
	var ph := TextureRect.new()
	ph.texture = VideoCard.poster_for(heading)
	ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ph.stretch_mode = TextureRect.STRETCH_SCALE
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(ph)
	p.add_child(ph)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(img)
	p.add_child(img)
	var box := VideoCard.thumb_url({ "id": "", "thumb": url if url != "" else str(game.get("thumb", "")) })
	if box != "":
		var wr: WeakRef = weakref(img)
		Media.url_texture(box, 170, func(t: Texture2D) -> void:
			var r: TextureRect = wr.get_ref()
			if t and r and is_instance_valid(r):
				r.texture = t
		)


func _build_buttons() -> void:
	if not is_instance_valid(_btn_row):
		return
	U.clear(_btn_row)
	var live: Dictionary = _data.get("live", {})
	var first := true
	if not live.is_empty():
		var b := U.button("Live ansehen", "play", "primary")
		b.set_meta("uz_key", "skanal:live")
		b.set_meta("uz_hint_a", "Live ansehen")
		b.set_meta("uz_default", true)
		b.pressed.connect(func() -> void: _play([live], 0))
		_btn_row.add_child(b)
		first = false
	var items: Array = _data.get("items", [])
	if not game.is_empty() and not items.is_empty():
		var b2 := U.button("Beliebtesten Stream ansehen", "play", "primary")
		b2.set_meta("uz_key", "skanal:erster")
		b2.set_meta("uz_hint_a", "Live ansehen")
		b2.set_meta("uz_default", true)
		b2.pressed.connect(func() -> void: _play(items, 0))
		_btn_row.add_child(b2)
		first = false
	var vids: Array = _data.get("videos", [])
	if live.is_empty() and game.is_empty() and not vids.is_empty():
		var b3 := U.button("Neueste Übertragung", "play", "primary")
		b3.set_meta("uz_key", "skanal:neueste")
		b3.set_meta("uz_hint_a", "Abspielen")
		b3.set_meta("uz_default", true)
		b3.pressed.connect(func() -> void: _play(vids, 0))
		_btn_row.add_child(b3)
		first = false
	if game.is_empty():
		var q := U.button("Link aufs Handy", "qr", "normal" if not first else "primary")
		q.set_meta("uz_key", "skanal:qr")
		q.set_meta("uz_hint_a", "QR-Code zeigen")
		q.pressed.connect(func() -> void:
			var l = load("res://src/ui/layers/video_qr.gd").new()
			l.video = live if not live.is_empty() else { "id": "tw:" + login, "title": heading, "channel": heading, "url": TP.WEB + "/" + login,
					"twitch": { "kind": "kanal" } }
			main.open_layer(l)
		)
		_btn_row.add_child(q)


func _update_sub_line() -> void:
	var parts := PackedStringArray()
	if game.is_empty():
		var u: Dictionary = _data.get("user", {})
		var f := int(u.get("followers", 0))
		if f > 0:
			parts.append(YouTube.followers_text(f).replace("Abonnenten", "Follower").replace("Abonnent", "Follower"))
		var live: Dictionary = _data.get("live", {})
		if not live.is_empty():
			parts.append("Live: " + str(live.get("info", "")) if str(live.get("info", "")) != "" else "Gerade live")
		elif not (_data.get("videos", []) as Array).is_empty():
			parts.append("Gerade offline")
	else:
		var g: Dictionary = _data.get("game", game)
		var vt := TP.viewers_text(int(g.get("viewers", game.get("viewers", 0))))
		if vt != "":
			parts.append(vt)
		var n := int(g.get("channels", game.get("channels", 0)))
		if n > 0:
			parts.append(TP.count_text(n) + (" Kanal" if n == 1 else " Kanäle") + " live")
	_sub_l.text = "  ·  ".join(parts) if not parts.is_empty() else ""


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


# --- Inhalt ------------------------------------------------------------------------------------

func _load() -> void:
	if game.is_empty():
		_data = await Twitch.channel(login)
	else:
		_data = await Twitch.game_streams(game)
	if not is_inside_tree():
		return
	if is_instance_valid(_skeleton):
		_skeleton.queue_free()
	var first: Control = null
	if game.is_empty():
		var u: Dictionary = _data.get("user", {})
		if str(u.get("name", "")) != "" and str(u.name) != heading:
			heading = str(u.name)
			_title_l.text = heading
		_fill_art(str(u.get("avatar", "")))
		_set_banner(str(u.get("banner", "")))
		var live: Dictionary = _data.get("live", {})
		if not live.is_empty():
			first = _section("Jetzt live", "", [live], "skanal:live")
		var vids: Array = _data.get("videos", [])
		if not vids.is_empty():
			var g := _section("Letzte Übertragungen", U.plural(vids.size(), "Übertragung", "Übertragungen"), vids, "skanal:vods")
			first = first if first else g
		var clips: Array = _data.get("clips", [])
		if not clips.is_empty():
			var c := _section("Clips", "beliebt im letzten Monat", clips, "skanal:clips")
			first = first if first else c
		_status.text = "" if bool(_data.get("ok", false)) \
				and first != null else (str(_data.get("error", "")) if str(_data.get("error", "")) != "" else "Hier gibt es gerade nichts zu sehen.")
	else:
		var items: Array = _data.get("items", [])
		if not items.is_empty():
			first = _section("Gerade live", U.plural(items.size(), "Stream", "Streams"), items, "skategorie")
		_status.text = "" if first != null else "Gerade läuft hier nichts – oder Twitch ist nicht erreichbar."
	_status.visible = _status.text != ""
	_update_sub_line()
	_build_buttons()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var hold := find_child("Hold", true, false)
	if hold:
		if hold.has_focus() and Nav.top_layer() == self:
			var d := Nav.default_in(_btn_row)
			Nav.focus(d if d else first, true)
		hold.queue_free()


## Überschrift und Raster; gibt die erste Karte zurück.
func _section(head: String, extra: String, list: Array, group: String) -> Control:
	var row := U.hbox(14)
	var l := U.label(head, "l", "text", "bold")
	l.clip_text = false
	row.add_child(l)
	if extra != "":
		var e := U.label(extra, "m", "faint", "medium")
		e.clip_text = false
		e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(e)
	_stack.add_child(row)
	var grid := GridContainer.new()
	grid.columns = U.cols_for(4)
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 40)
	grid.set_meta("uz_group", group)
	for i in list.size():
		var v: Dictionary = list[i]
		var c = StreamCard.new()
		c.setup_stream(v, CARD_W)
		var kind := str((v.get("twitch", {}) as Dictionary).get("kind", ""))
		var pos := Twitch.resume_pos(str(v.get("id", "")))
		c.set_meta("uz_hint_a", "Live ansehen" if kind == "live" else (("Weiterschauen ab " + YouTube.time_text(pos)) if pos > 20 else "Abspielen"))
		var idx := i
		c.chosen.connect(func(_v: Dictionary) -> void: _play(list, idx))
		grid.add_child(c)
	_stack.add_child(grid)
	_stack.add_child(U.spacer(0, 24, false))
	return grid.get_child(0) if grid.get_child_count() > 0 else null


func _play(list: Array, idx: int) -> void:
	if idx < 0 or idx >= list.size():
		return
	var pos := Twitch.resume_pos(str((list[idx] as Dictionary).get("id", "")))
	close()
	main.open_video(list, idx, { "start": pos } if pos > 20 else {})

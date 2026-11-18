extends "res://src/ui/layers/sheet.gd"
## Optionen zu einem Video: abspielen, von vorn, nur Ton (auch gleich im Hintergrund), merken,
## Kanal, Verlauf – und den Link per QR-Code aufs Handy (statt den Browser auf dem PC zu öffnen).
## Oben das Vorschaubild.

const VideoCard := preload("res://src/ui/components/video_card.gd")
const VideoQr := preload("res://src/ui/layers/video_qr.gd")

var video: Dictionary = {}
var list: Array = []
var index := 0
var play_opts := {}             ## an open_video weitergereicht (Shorts nacheinander)
const Main := preload("res://src/main.gd")
var main: Main


func build() -> void:
	var sub := PackedStringArray()
	if str(video.get("channel", "")) != "":
		sub.append(str(video.channel))
	if int(video.get("duration", 0)) > 0:
		sub.append(YouTube.time_text(int(video.duration)))
	elif bool(video.get("live", false)):
		sub.append("Live")
	setup(str(video.get("title", "Video")), "  ·  ".join(sub), 880)
	heading_raw = video.has("title")   # Titel bleiben, wie der Kanal sie schreibt
	set_header_image(thumb_box(video, Vector2(192, 108)))
	super()


## Kleines Vorschaubild mit runden Ecken (Farbfeld des Kanals, bis das Bild da ist).
static func thumb_box(v: Dictionary, s: Vector2) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = s
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var poster := TextureRect.new()
	poster.texture = VideoCard.poster_texture(v)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_SCALE
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(poster)
	p.add_child(poster)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(img)
	p.add_child(img)
	var url := VideoCard.thumb_url(v)
	if url != "":
		var wr: WeakRef = weakref(img)
		Media.url_texture(url, 480, func(t: Texture2D) -> void:
			var r: TextureRect = wr.get_ref()
			if t and r and is_instance_valid(r):
				r.texture = t
		)
	var prog := YouTube.progress_of(str(v.get("id", "")))
	if prog > 0.01:
		var bar := ColorRect.new()
		bar.color = UzTheme.col("accent") if prog < 1.0 else UzTheme.col("muted")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.anchor_right = prog
		bar.offset_top = -5
		p.add_child(bar)
	return p


func _row(kind: String, t: String, icon: String, v: Variant = null) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, "", v)
	r.icon_name = icon
	r.set_meta("uz_key", "vopt:" + t)
	return r


func fill() -> void:
	var vid := str(video.get("id", ""))
	var resume := YouTube.resume_pos(vid)
	var play = _row("action", ("Weiterschauen ab " + YouTube.time_text(resume)) if resume > 20 else "Abspielen", "play")
	play.on_activate = func() -> void:
		close()
		main.open_video(_list(), index, play_opts)
	add_row(play)
	if resume > 20:
		var again = _row("action", "Von vorn abspielen", "restart")
		again.on_activate = func() -> void:
			close()
			main.open_video(_list(), index, play_opts.merged({ "start": 0 }))
		add_row(again)
	var audio = _row("action", "Nur Ton abspielen", "music")
	audio.on_activate = func() -> void:
		close()
		main.open_video(_list(), index, { "audio": true })
	add_row(audio)
	# Gleich im Hintergrund: kein Player, der Ton läuft wie Musik weiter (Guide → „Video-Ton“).
	var bg = _row("action", "Im Hintergrund hören", "volume")
	bg.subtitle = "Nur Ton, du bleibst hier"
	bg.on_activate = func() -> void:
		close()
		main.play_in_background(_list(), index)
	add_row(bg)
	var later = _row("toggle", "Merken", "bookmark", YouTube.in_later(vid))
	later.changed.connect(func(_v: Variant) -> void: YouTube.toggle_later(video))
	add_row(later)
	var cid := str(video.get("channel_id", ""))
	if cid != "":
		add_gap()
		var ch = _row("action", "Kanal öffnen", "channel")
		ch.value_text = str(video.get("channel", ""))
		ch.on_activate = func() -> void:
			close()
			main.open_channel(cid, str(video.get("channel", "Kanal")))
		add_row(ch)
		var ab = _row("toggle", "Kanal abonnieren", "plus", YouTube.is_subscribed(cid))
		ab.changed.connect(func(v: Variant) -> void:
			if v:
				YouTube.subscribe(cid, str(video.get("channel", "")))
			else:
				YouTube.unsubscribe(cid)
		)
		add_row(ab)
	add_gap()
	var link = _row("action", "Link aufs Handy", "qr")
	link.value_text = "QR-Code"
	link.on_activate = func() -> void:
		var q = VideoQr.new()
		q.video = video
		main.open_layer(q)
	add_row(link)
	if YouTube.resume_pos(vid) > 0 or YouTube.progress_of(vid) > 0:
		var rm = _row("action", "Aus dem Verlauf entfernen", "trash")
		rm.on_activate = func() -> void:
			YouTube.remove_history(vid)
			close()
		add_row(rm)


func _list() -> Array:
	return list if not list.is_empty() else [video]

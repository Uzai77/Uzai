extends "res://src/ui/layers/modal.gd"
## Ein Video aufs Handy: QR-Code mit dem Link, daneben Bild, Titel und die kurze Adresse.
## Ersetzt „Im Browser öffnen“ – Uzai bleibt vorn, das Handy übernimmt (teilen, kommentieren,
## unterwegs weiterschauen). Nichts öffnet sich auf dem PC.

const QrView := preload("res://src/ui/components/qr_view.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")

var video: Dictionary = {}


func build() -> void:
	width = 1120.0
	set_meta("uz_hint_b", "Schließen")
	super()


static func link_for(v: Dictionary) -> String:
	# Twitch (Streams): die Adresse des Kanals, der Übertragung oder des Clips.
	if v.get("twitch") is Dictionary:
		return str(v.get("url", "https://www.twitch.tv/"))
	var vid := str(v.get("id", ""))
	return "https://youtu.be/" + vid if vid.length() == 11 else "https://www.youtube.com/"


func fill() -> void:
	var url := link_for(video)
	var row := U.hbox(52)
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qr = QrView.new()
	qr.setup(url, 340)
	frame.add_child(qr)
	row.add_child(frame)
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(U.label("Link aufs Handy", "xl", "text", "black"))
	var t := U.label("Mit der Handykamera scannen.", "m", "muted",
			"regular", true)
	t.custom_minimum_size = Vector2(560, 0)
	col.add_child(t)
	col.add_child(U.spacer(0, 4, false))
	var vr := U.hbox(18)
	col.add_child(vr)
	var thumb := Panel.new()
	thumb.custom_minimum_size = Vector2(176, 99)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	thumb.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var poster := TextureRect.new()
	poster.texture = VideoCard.poster_texture(video)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_SCALE
	U.full_rect(poster)
	thumb.add_child(poster)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	U.full_rect(img)
	thumb.add_child(img)
	var turl := VideoCard.thumb_url(video)
	if turl != "":
		var wr: WeakRef = weakref(img)
		Media.url_texture(turl, 480, func(tx: Texture2D) -> void:
			var r: TextureRect = wr.get_ref()
			if tx and r and is_instance_valid(r):
				r.texture = tx
		)
	vr.add_child(thumb)
	var info := U.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := U.label(str(video.get("title", "")), "m", "text", "bold", true)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel des Videos: nie übersetzen
	title.max_lines_visible = 2
	title.custom_minimum_size = Vector2(360, 0)
	info.add_child(title)
	info.add_child(U.label(url.replace("https://", ""), "m", "accent", "medium"))
	vr.add_child(info)
	col.add_child(U.spacer(0, 6, false))
	var done := U.button("Fertig", "check", "primary")
	done.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	done.set_meta("uz_default", true)
	done.set_meta("uz_hint_a", "Schließen")
	done.pressed.connect(close)
	col.add_child(done)

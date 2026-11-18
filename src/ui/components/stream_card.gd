extends "res://src/ui/components/video_card.gd"
## Ein Stream als Karte (Bereich Streams): wie eine Videokarte, darunter Kanal, Kategorie und
## Zuschauer statt Aufrufen. Kategorien stehen im Hochformat (wie eine Spielhülle) mit den
## Zuschauern darunter. Angefangene Übertragungen zeigen unten, wie weit man schon ist.
## Die Bilder kommen größer als bei YouTube (Twitch liefert jede Größe), damit sie auf 4K scharf
## bleiben.

const TP := preload("res://src/core/twitch_parse.gd")

var portrait := false


## v: Stream, Übertragung oder Clip (twitch_parse.stream_item & Co.) oder eine Kategorie
## (game_item, tall = true).
func setup_stream(v: Dictionary, w: float, tall := false) -> Control:
	setup(v, w, true)
	portrait = tall
	play_glyph = not tall
	if tall:
		_thumb_h = round(w * 4.0 / 3.0)
	img_w = int(w * 1.1)
	meta_override = line_for(v, w - 4.0)
	if meta_override == "":
		meta_override = " "
	return self


## Zeile unter dem Titel. Passt sie nicht, fällt zuerst die Kategorie weg, dann die Zahl.
static func line_for(v: Dictionary, width: float) -> String:
	var tw: Variant = v.get("twitch")
	var parts: Array = []           # [Text, Wichtigkeit] wie VideoCard.meta_text
	if not (tw is Dictionary):
		# Kategorie
		var vt := TP.viewers_text(int(v.get("viewers", 0)))
		if vt != "":
			parts.append([vt, 0])
		return fit_parts(parts, width, UzTheme.font("regular"), UzTheme.size("s"))
	parts.append([str(v.get("channel", "")), 0])
	match str(tw.get("kind", "")):
		"live":
			var vt2 := TP.viewers_text(int(tw.get("viewers", 0)))
			if vt2 != "":
				parts.append([vt2, 1])
			if str(tw.get("game", "")) != "":
				parts.append([str(tw.game), 2])
		_:
			var pos := Twitch.resume_pos(str(v.get("id", "")))
			var dur := int(v.get("duration", 0))
			if pos > 20 and dur > pos:
				parts.append([left_text(int(dur - pos)), 1])
			else:
				var vv := YouTube.views_text(int(v.get("views", 0)))
				if vv != "":
					parts.append([vv, 2])
				if int(v.get("published", 0)) > 0:
					parts.append([U.ago(int(v.published)), 1])
	return fit_parts(parts.filter(func(p: Array) -> bool: return str(p[0]) != ""), width, UzTheme.font("regular"), UzTheme.size("s"))


func refresh_state() -> void:
	super()
	if is_instance_valid(_meta):
		meta_override = line_for(video, card_w - 4.0)
		_meta.text = meta_override


func _build_badges() -> void:
	super()
	var prog := Twitch.progress_of(str(video.get("id", "")))
	if prog <= 0.01:
		return
	var h := 5.0
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = Vector2(0, _thumb_h - h)
	bg.size = Vector2(card_w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.add_child(bg)
	var bar := ColorRect.new()
	bar.color = UzTheme.col("accent")
	bar.position = Vector2(0, _thumb_h - h)
	bar.size = Vector2(maxf(h, card_w * prog), h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.add_child(bar)

extends RefCounted
## Seltenheit sichtbar machen: eine Farbe je Stufe (von leise über hell und Blassgold bis Gold)
## und ein kleines Etikett aus Raute und Text („◆ Ultra selten · 3,1 %“). Die Stufen selbst
## stehen in Ach.rarity_tier().

const Ach := preload("res://src/core/achievements.gd")
const U := preload("res://src/ui/u.gd")
const Lang := preload("res://src/core/lang.gd")

static var _gem: Texture2D


## Farbe einer Stufe, nur aus den Farben des Schemas gemischt.
static func color(tier: int) -> Color:
	match tier:
		3:
			return UzTheme.col("accent")
		2:
			return UzTheme.col("accent").lerp(UzTheme.col("text"), 0.55)
		1:
			return UzTheme.col("text", 0.86)
	return UzTheme.col("muted")


## Kleine Raute als Bild (weiß, wird eingefärbt). Mit „uz_icon“, damit sie auf der hellen
## Auswahl wie die Schrift dunkel wird.
static func gem_tex() -> Texture2D:
	if _gem == null:
		var img := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="M12 2.5 21.5 12 12 21.5 2.5 12Z" fill="#fff"/></svg>'
		if img.load_svg_from_string(svg, 2.0) != OK:
			img = Image.create(48, 48, false, Image.FORMAT_RGBA8)
		_gem = ImageTexture.create_from_image(img)
	return _gem


static func gem(tier: int, px := 14) -> TextureRect:
	var t := TextureRect.new()
	t.texture = gem_tex()
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color(tier)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.set_meta("uz_icon", true)
	return t


## „◆ Ultra selten · 3,1 %“. Ohne Anteil (pct < 0) bleibt das Etikett leer.
static func tag(pct: float, size := "s", with_pct := true) -> HBoxContainer:
	var h := U.hbox(9)
	var tier := Ach.rarity_tier(pct)
	if tier < 0:
		return h
	h.add_child(gem(tier, 15 if size != "xs" else 12))
	var txt := Ach.rarity_name(tier)
	if with_pct:
		txt += "  ·  " + Ach.pct_text(pct)
	var l := U.label(txt, size, "accent" if tier == 3 else ("text" if tier == 2 else "muted"), "medium")
	l.clip_text = false
	h.add_child(l)
	return h


## Kurzes Datum: „12. Okt. 2026“ (ohne Jahr, wenn es dieses Jahr war).
static func date(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_date_dict_from_unix_time(unix + bias)
	var now := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	return Lang.date_text(int(d.day), int(d.month), int(d.year) if int(d.year) != int(now.year) else 0, true)


## „Heute“, „Gestern“, „Vor 3 Tagen“, danach das Datum.
static func when(unix: int) -> String:
	if unix <= 0:
		return ""
	var a := U.ago(unix)
	if a == "Letzte Woche" or a.ends_with("Wochen") or a == U.date(unix):
		return date(unix)
	return a

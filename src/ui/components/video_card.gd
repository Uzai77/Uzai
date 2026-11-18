extends Control
## Ein Video als Karte: Vorschaubild 16:9 mit Länge und Fortschritt, darunter Titel und eine
## Zeile mit Kanal, Aufrufen und Alter. Gewählt wächst das Bild nach oben und trägt den einen
## Cursor der Kacheln (UzTheme.draw_tile_focus); ein Lichtstreif zieht nur, wo das Theme ihn will;
## der Text bleibt ruhig stehen.
## Solange (oder falls) es kein Bild gibt, steht ein ruhiges Farbfeld in der Farbe des Kanals
## da – jeder Kanal behält seine Farbe, wie bei den Profilbildern. Shorts stehen hochkant (9:16,
## setup(…, portrait = true)); das Bild wird dafür dort geschnitten, wo das Wichtige ist (Zuschnitt).

signal chosen(video: Dictionary)
signal focused_video(video: Dictionary)

const Shine := preload("res://src/ui/components/shine.gd")
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

const FOCUS_SCALE := 1.06
const SEP := "  ·  "

var video: Dictionary = {}
var card_w := 400.0
var show_channel := true
## Eigene Hoch/Runter-Steuerung (Reihen unter einem festen Kopf): func(d: int) -> bool
var nav_ud_cb: Callable
var key_prefix := ""              ## gleiches Video in mehreren Reihen: eigener Schlüssel je Reihe
var meta_override := ""           ## eigene Zeile unter dem Titel (z. B. „24 Videos“)
var badge_text := ""              ## eigenes Abzeichen unten rechts statt der Länge
var badge_icon := ""
var stacked := false              ## wie ein Stapel (Playlists)
var img_w := 480                  ## Breite, in der das Bild geladen wird (Streams: größer, für 4K)
## Bild erst mit wake() laden (Reihen weit unten bzw. weit rechts, medien_reihen.gd): Sonst holte
## eine Startseite mit 300 Karten alle Bilder auf einmal, und das große Bild der Bühne wartete
## hinter ihnen.
var lazy := false
var play_glyph := true            ## Dreieck im Platzhalter; Kategorien (Streams) spielen nichts ab
var _wait_url := ""
var _thumb_h := 225.0
var _thumb: Control
var _clip: Panel
var _img: TextureRect
var _ring: Control
var _shine: Control
var _badges: Control
var _meta: Label
var _focus_t := 0.0
var _tw: Tween
var _poster: TextureRect


func setup(v: Dictionary, w := 400.0, with_channel := true, portrait := false) -> Control:
	video = v
	card_w = w
	show_channel = with_channel
	_thumb_h = round(w * (16.0 / 9.0 if portrait else 9.0 / 16.0))
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(card_w, _thumb_h + 102)
	set_meta("uz_key", "v:" + key_prefix + str(video.get("id", video.get("title", ""))))
	set_meta("uz_flug", "v:" + str(video.get("id", video.get("title", ""))))
	# Das Bild ist eine eigene Ebene: es wächst beim Wählen von der Unterkante aus nach oben.
	_thumb = Control.new()
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.size = Vector2(card_w, _thumb_h)
	_thumb.pivot_offset = Vector2(card_w * 0.5, _thumb_h)
	_thumb.draw.connect(_draw_shadow)
	add_child(_thumb)
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	U.clip_round(_clip, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.size = _thumb.size
	_thumb.add_child(_clip)
	var poster := TextureRect.new()
	poster.texture = poster_texture(video)
	poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	poster.stretch_mode = TextureRect.STRETCH_SCALE
	poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poster.size = _clip.size
	_clip.add_child(poster)
	_poster = poster
	if play_glyph:
		var glyph := PlayGlyph.new()
		glyph.size = _clip.size
		_clip.add_child(glyph)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.size = _clip.size
	_clip.add_child(_img)
	_badges = Control.new()
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.size = _clip.size
	_clip.add_child(_badges)
	_build_badges()
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = _thumb.size
	_ring.draw.connect(_draw_ring)
	_thumb.add_child(_ring)
	var text := U.vbox(3)
	text.position = Vector2(2, _thumb_h + 14)
	text.size = Vector2(card_w - 4, 84)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text)
	var t := U.label(str(video.get("title", "")), "m", "text", "bold", true)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Titel bleiben, wie der Kanal sie schreibt
	t.max_lines_visible = 2
	t.add_theme_constant_override("line_spacing", -2)
	# Feste Höhe für zwei Zeilen: dann stehen die Zeilen darunter in einer Reihe auf einer Linie,
	# und zu lange Titel enden mit „…“ (ohne feste Höhe meldet Godot dafür nur 1 Pixel).
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size = Vector2(card_w - 4, two_lines(t))
	text.add_child(t)
	_meta = U.label("", "s", "muted")
	_meta.clip_text = true
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta.custom_minimum_size = Vector2(card_w - 4, 0)
	text.add_child(_meta)
	_meta.text = meta_override if meta_override != "" else meta_text(video, show_channel, card_w - 4)
	var url := thumb_url(video)
	if url != "":
		_wait_url = url
		if not lazy:
			wake()
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(_on_gui_input)


## Bild jetzt laden (einmal). Liegt es schon bereit, kommt es sofort (ohne Einblenden) – beim
## Blättern kein Aufflackern.
func wake() -> void:
	lazy = false
	if _wait_url == "":
		return
	var url := _wait_url
	_wait_url = ""
	_sync = true
	Media.url_texture(url, img_w, _on_tex)
	_sync = false


## Höhe von zwei Zeilen eines Labels (mit seinem Zeilenabstand).
static func two_lines(l: Label) -> float:
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	return f.get_height(fs) * 2.0 + float(l.get_theme_constant("line_spacing"))


## Bild für eine Karte: hqdefault (480 breit, die schwarzen Balken schneidet das Zuschneiden
## auf 16:9 weg) ist deutlich schärfer als mqdefault. In der Demo nur lokale Bilder.
static func thumb_url(v: Dictionary) -> String:
	var own := str(v.get("thumb", ""))
	if YouTube.demo:
		return own if own != "" and not own.begins_with("http") else ""
	var id := str(v.get("id", ""))
	# YouTube-IDs haben 11 Zeichen ohne Doppelpunkt (Streams: „tw:…“ kann auch 11 lang sein).
	if id.length() == 11 and not id.contains(":"):
		return YouTube.thumb_for(id, true)
	return str(v.get("thumb", ""))


## Badges (Länge, LIVE, Fortschritt, Merkliste) neu setzen, z. B. nach „Merken“.
func refresh_state() -> void:
	if not is_instance_valid(_badges):
		return
	U.clear(_badges)
	_build_badges()
	if is_instance_valid(_meta) and meta_override == "":
		_meta.text = meta_text(video, show_channel, card_w - 4)


func _build_badges() -> void:
	var dur := int(video.get("duration", 0))
	var live := bool(video.get("live", false))
	if badge_text != "" or badge_icon != "":
		var own := U.panel("bg", 8, 0, 0.8)
		var orow := U.hbox(7)
		if badge_icon != "":
			var oi := U.icon(badge_icon, 18, "text")
			oi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			orow.add_child(oi)
		if badge_text != "":
			var ol := U.label(badge_text, "15", "text", "ui_bold")
			ol.clip_text = false
			orow.add_child(ol)
		var om := U.margin(9, 3, 10, 4)
		om.add_child(orow)
		own.add_child(om)
		_badges.add_child(own)
		var osz := own.get_combined_minimum_size()
		own.position = Vector2(card_w - 12 - osz.x, _thumb_h - 14 - osz.y)
	elif dur > 0 or live:
		var tag := U.panel("danger" if live else "bg", 8, 0, 1.0 if live else 0.8)
		var l := U.label("LIVE" if live else YouTube.time_text(dur), "15", "text", "ui_bold")
		l.clip_text = false
		var m := U.margin(9, 3, 9, 4)
		m.add_child(l)
		tag.add_child(m)
		_badges.add_child(tag)
		var ts := tag.get_combined_minimum_size()
		tag.position = Vector2(card_w - 12 - ts.x, _thumb_h - 14 - ts.y)
	var prog := YouTube.progress_of(str(video.get("id", "")))
	if prog > 0.01:
		var h := 5.0
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.position = Vector2(0, _thumb_h - h)
		bg.size = Vector2(card_w, h)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badges.add_child(bg)
		var bar := ColorRect.new()
		bar.color = UzTheme.col("accent") if prog < 1.0 else UzTheme.col("muted")
		bar.position = Vector2(0, _thumb_h - h)
		bar.size = Vector2(maxf(h, card_w * prog), h)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badges.add_child(bar)
	if YouTube.in_later(str(video.get("id", ""))):
		var bm := U.panel("bg", 17, 0, 0.72)
		bm.custom_minimum_size = Vector2(34, 34)
		var ic := U.icon("bookmark_f", 18, "accent")
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bm.add_child(ic)
		bm.position = Vector2(card_w - 46, 12)
		_badges.add_child(bm)


# --- Zeile unter dem Titel ----------------------------------------------------------------------

## Kanal · Aufrufe · Alter – passt das nicht in eine Zeile, fällt zuerst die Zahl der Aufrufe weg,
## dann das Alter. Nie ein abgeschnittenes „· …“ am Ende.
static func meta_text(v: Dictionary, with_channel: bool, width: float) -> String:
	var parts: Array = []           # [Text, Wichtigkeit] in Anzeige-Reihenfolge; hoch fällt zuerst weg
	if with_channel and str(v.get("channel", "")) != "":
		parts.append([str(v.channel), 0])
	var id := str(v.get("id", ""))
	var resume := YouTube.resume_pos(id)
	var dur := int(v.get("duration", 0))
	if resume > 20 and dur > resume:
		parts.append([left_text(dur - resume), 1])
	else:
		var vt := YouTube.views_text(int(v.get("views", 0)))
		if vt != "":
			parts.append([vt, 2])
		if int(v.get("published", 0)) > 0:
			parts.append([U.ago(int(v.published)), 1])
	return fit_parts(parts, width, UzTheme.font("regular"), UzTheme.size("s"))


static func fit_parts(parts: Array, width: float, font: Font, fs: int) -> String:
	var cur := parts.duplicate()
	while true:
		var texts := PackedStringArray()
		for p in cur:
			texts.append(str(p[0]))
		var s := SEP.join(texts)
		if cur.size() <= 1 or font == null or font.get_string_size(TranslationServer.translate(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return s
		var drop := 0
		for i in cur.size():
			if int(cur[i][1]) > int(cur[drop][1]):
				drop = i
		if int(cur[drop][1]) == 0:
			return s
		cur.remove_at(drop)
	return ""


## Restzeit kurz: „noch 52 Min.“, „noch 1 Std. 12 Min.“ (übersetzt: die Zeilen zeigen Titel unübersetzt)
static func left_text(sec: int) -> String:
	if sec >= 3600:
		var m := floori(sec / 60.0) % 60
		return (TranslationServer.translate("noch %d Std. %d Min.") % [floori(sec / 3600.0), m]) if m > 0 \
				else TranslationServer.translate("noch %d Std.") % floori(sec / 3600.0)
	return TranslationServer.translate("noch %d Min.") % maxi(1, ceili(sec / 60.0))


# --- Farbfeld statt Bild ---------------------------------------------------------------------

static var _posters := {}


## Ruhiges Farbfeld in der Farbe des Kanals (gleicher Farbton wie sein Profilbild): oben links
## etwas Licht, nach unten rechts tiefer. Klein gerechnet, weich vergrößert, zwischengespeichert.
static func poster_texture(v: Dictionary) -> Texture2D:
	var seed := str(v.get("channel", ""))
	if seed == "":
		seed = str(v.get("channel_id", v.get("title", "")))
	return poster_for(seed)


static func poster_for(seed: String) -> Texture2D:
	var hue := float(absi(seed.hash()) % 360) / 360.0
	var bucket := int(round(hue * 48.0)) % 48
	if _posters.has(bucket):
		return _posters[bucket]
	var h := float(bucket) / 48.0
	var w := 64
	var hh := 36
	var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	var top := Color.from_hsv(h, 0.40, 0.38)
	var low := Color.from_hsv(fposmod(h + 0.04, 1.0), 0.50, 0.12)
	var glow := Color.from_hsv(fposmod(h - 0.02, 1.0), 0.30, 0.60)
	for y in hh:
		for x in w:
			var u := float(x) / float(w - 1)
			var vv := float(y) / float(hh - 1)
			var c := top.lerp(low, clampf(u * 0.5 + vv * 0.7, 0.0, 1.0))
			var d := Vector2((u - 0.2) * 1.5, vv - 0.1).length()
			var g := clampf(1.0 - d / 0.9, 0.0, 1.0)
			c = c.lerp(glow, g * g * 0.42)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	# Farbe gleich mitgeben: sonst läse der Hintergrund sie beim Zeigen auf der Bühne von der
	# Grafikkarte zurück (get_image) – das hält in Uzai.exe das Bild an.
	tex.set_meta("uz_vivid", [Color.from_hsv(h, 0.42, 0.62)])
	_posters[bucket] = tex
	return tex


var _sync := false


func _on_tex(t: Texture2D) -> void:
	if t == null or not is_instance_valid(_img):
		return
	# Kluger Ausschnitt (Shorts hochkant), Ton und gemeinsamer Verlauf (Punkt 97).
	Zuschnitt.put(_img, t)
	if _sync:
		_img.modulate.a = 1.0
		return
	_img.modulate.a = 0.0
	U.tw(_img, "uz_fade").tween_property(_img, "modulate:a", 1.0, U.T_BASE)


# --- Auswahl ---------------------------------------------------------------------------------

## Gewählt: der Ring steht im Cursor-Takt (Liste.takt), das Bild wächst in T_ORT (Kurve
## „Ankommen“, ohne Nachfedern), der Lichtstreif zieht nur, wo das Theme ihn will.
func _on_focus(on: bool) -> void:
	if on and _wait_url != "":
		wake()
	_tw = U.ankommen(_thumb, U.T_ORT, "uz_gross")
	_tw.tween_property(_thumb, "scale", Vector2.ONE * (U.wachsen(FOCUS_SCALE) if on else 1.0), U.T_ORT if on else U.T_WEG)
	Liste.takt(self, _focus_t, on, _set_focus_t)
	if on:
		if UzTheme.focus_shine() and not Leicht.active and not U.reduziert():
			if _shine == null or not is_instance_valid(_shine):
				_shine = Shine.new()
				_clip.add_child(_shine)
			_clip.move_child(_shine, _clip.get_child_count() - 1)
			_shine.play()
		focused_video.emit(video)


## A gedrückt: das Bild sinkt kurz ein und kommt zurück (Takt „Antwort“); der Ring bleibt.
func press_feedback() -> void:
	_set_focus_t(1.0)
	var sc := U.wachsen(FOCUS_SCALE)
	_tw = U.ankommen(_thumb, U.T_ORT, "uz_gross")
	_tw.tween_property(_thumb, "scale", Vector2.ONE * (sc - (0.0 if U.reduziert() else 0.045)), U.T_ANTWORT)
	_tw.tween_property(_thumb, "scale", Vector2.ONE * sc, U.T_ORT)


func _set_focus_t(v: float) -> void:
	_focus_t = v
	if is_instance_valid(_ring):
		_ring.queue_redraw()
	if is_instance_valid(_thumb):
		_thumb.queue_redraw()


func _draw_shadow() -> void:
	if stacked:
		# Zwei schmalere Lagen dahinter: sieht aus wie ein Stapel Videos.
		for i in [2, 1]:
			var lay := UzTheme.box(UzTheme.col("text", 0.10 if i == 1 else 0.05), UzTheme.r_cover())
			var inset: float = 14.0 * i
			_thumb.draw_style_box(lay, Rect2(inset, -7.0 * i, _thumb.size.x - inset * 2.0, _thumb.size.y))
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(UzTheme.r_cover())
	sh.shadow_color = Color(0, 0, 0, 0.26 + 0.24 * _focus_t)
	sh.shadow_size = int(14 + 18 * _focus_t)
	sh.shadow_offset = Vector2(0, 8 + 8 * _focus_t)
	_thumb.draw_style_box(sh, Rect2(Vector2.ZERO, _thumb.size))


## Der eine Cursor für Cover und Kacheln (UzTheme.draw_tile_focus): in der Marke eine feine
## Lichtkante mit weichem Schein, in anderen Themes Band und Ring – nie ein eigener Rahmen hier.
func _draw_ring() -> void:
	var t := minf(_focus_t, 1.0)
	UzTheme.draw_tile_hover(_ring, Rect2(Vector2.ZERO, _ring.size), UzTheme.r_cover(), _hover_t * (1.0 - t))
	if t <= 0.01:
		return
	UzTheme.draw_tile_focus(_ring, Rect2(Vector2.ZERO, _ring.size), UzTheme.r_cover(), t)


## Maus darüber (schweben.gd): derselbe Schein wie die Auswahl, nur leiser – zeigt, was ein Klick öffnet.
var _hover_t := 0.0
var _hover_tw: Tween


func zeiger_schweben(an: bool) -> void:
	if _hover_tw:
		_hover_tw.kill()
	_hover_tw = create_tween()
	_hover_tw.tween_method(func(v: float) -> void:
		_hover_t = v
		if is_instance_valid(_ring):
			_ring.queue_redraw(), _hover_t, 1.0 if an else 0.0, U.T_ANTWORT)


func nav_ud(d: int) -> bool:
	if nav_ud_cb.is_valid():
		return bool(nav_ud_cb.call(d))
	return false


## In einer Reihe (nav_ud_cb gesetzt): am Anfang oder Ende anschlagen statt schräg in eine
## andere Reihe zu springen.
func nav_lr(d: int) -> bool:
	if not nav_ud_cb.is_valid() or get_parent() == null:
		return false
	var i := get_index()
	if (d < 0 and i == 0) or (d > 0 and i == get_parent().get_child_count() - 1):
		Nav._bump(self, "left" if d < 0 else "right")
		return true
	return false


func activate() -> void:
	chosen.emit(video)


## Geteilte Elemente (src/ui/flug.gd): das Vorschaubild (sonst das Farbfeld). Solange es fliegt,
## bleibt nur die Schrift darunter stehen.
func flug_bild() -> Dictionary:
	var n: TextureRect = _img if is_instance_valid(_img) and _img.texture else _poster
	if n == null or not is_instance_valid(n) or n.texture == null:
		return {}
	return { "node": n, "hide": _thumb }


func _on_gui_input(e: InputEvent) -> void:
	Nav.klick(self, e)


## Weiches Abspielzeichen auf dem Farbfeld (verschwindet unter dem echten Bild).
class PlayGlyph extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.15
		draw_circle(c, r, Color(1, 1, 1, 0.13))
		var s := r * 0.42
		var pts := PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s * 1.05, 0), c + Vector2(-s * 0.7, s)])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.62))

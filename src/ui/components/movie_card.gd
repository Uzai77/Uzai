extends Control
## Ein Film oder eine Serie als Karte – wie in Nuvio TV, in Uzais Gestaltung.
##
## Arten:
##  poster – Plakat im Hochformat (2:3). Bleibt man kurz darauf stehen, wird die Karte breit und
##           zeigt das Hintergrundbild mit Schriftzug (Querformat), die Nachbarn rücken weiter.
##  grid   – Plakat mit Titel und Jahr darunter (Raster: Alle anzeigen, Bibliothek, Suche).
##  wide   – Weiterschauen: Querformat mit Folge, Restzeit und Fortschrittsbalken.
##  more   – „Alle anzeigen“ am Ende einer Reihe.
##  episode – Folge einer Serie: Vorschaubild, darauf Nummer, Titel, Inhalt und Datum (wie Nuvio),
##           mit Haken für Gesehenes und Balken für Angefangenes (item._watched, item._frac).
## Gewählt: der eine Cursor der Kacheln (UzTheme.draw_tile_focus) im Cursor-Takt, breite Karten
## wachsen leicht in T_ORT, der Lichtstreif zieht nur, wo das Theme ihn will.
## Ohne Bild steht ein ruhiges Farbfeld in der Farbe des Titels mit dem Namen darauf.

signal chosen(item: Dictionary)
signal focused_item(item: Dictionary)

const U := preload("res://src/ui/u.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const Shine := preload("res://src/ui/components/shine.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")

const POSTER := Vector2(228, 342)
const WIDE := Vector2(448, 252)
const EPISODE := Vector2(480, 270)
const GRID_LABEL_H := 64.0
const FOCUS_SCALE := 1.04
const EXPAND_DWELL := 0.34

var item: Dictionary = {}
var mode := "poster"
var expand := false                ## poster: gewählt breit werden (Querformat). Aus: die Karte bleibt, wie sie ist
var watched := false               ## Haken oben rechts (gesehener Film)
var nav_ud_cb: Callable            ## Reihen unter einem festen Kopf: func(d: int) -> bool
var key_prefix := ""
## Bilder erst mit wake() laden (Reihen weit unten bzw. weit rechts, medien_reihen.gd).
var lazy := false
var _img_due := false

var _w := 228.0
var _h := 342.0
var _frame: Control
var _clip: Panel
var _ph: TextureRect
var _ph_text: VBoxContainer
var _img: TextureRect
var _wide: Control
var _bd_ph: TextureRect
var _bd_img: TextureRect
var _scrim: Control
var _wtext: VBoxContainer
var _logo: TextureRect
var _wtitle: Label
var _badges: Control
var _ring: Control
var _shine: Control
var _label: VBoxContainer
var _focus_t := 0.0
var _expand_t := 0.0
var _tw: Tween
var _xtw: Tween
var _dwell: Timer
var _bd_loaded := false
var _prog := 0.0


func setup(it: Dictionary, m := "poster") -> Control:
	item = it
	mode = m
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base := WIDE if mode == "wide" else (EPISODE if mode == "episode" else POSTER)
	_w = base.x
	_h = base.y
	set_meta("uz_key", "m:%s%s:%s" % [key_prefix, mode, str(item.get("id", item.get("key", "")))])
	if mode != "more" and mode != "episode" and str(item.get("id", "")) != "":
		set_meta("uz_flug", "m:" + str(item.id))
	if mode == "wide":
		_prog = Art.frac(float(item.get("position", 0.0)), float(item.get("duration", 0.0)))
	elif mode == "episode":
		_prog = float(item.get("_frac", 0.0))
		watched = bool(item.get("_watched", false))
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_shadow)
	add_child(_frame)
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	U.clip_round(_clip, CanvasItem.CLIP_CHILDREN_AND_DRAW)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_clip)
	var seed := str(item.get("id", item.get("name", item.get("title", ""))))
	if mode == "more":
		_build_more()
	else:
		_ph = _tex_rect(Art.poster_tex(seed), TextureRect.STRETCH_SCALE)
		_clip.add_child(_ph)
		if mode != "wide" and mode != "episode":
			_ph_text = _poster_text()
			_clip.add_child(_ph_text)
		_img = _tex_rect(null, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		_clip.add_child(_img)
		if mode == "wide" or mode == "episode" or (mode == "poster" and expand):
			_build_wide(seed)
		_badges = Control.new()
		_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badges.draw.connect(_draw_badges)
		_clip.add_child(_badges)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_frame.add_child(_ring)
	if mode == "grid":
		_label = U.vbox(2)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := U.label(str(item.get("name", "")), "s", "text", "bold")
		U.ellipsis(t)
		_label.add_child(t)
		var sub := PackedStringArray()
		var y := str(item.get("year", ""))
		if y != "":
			sub.append(y)
		var r := Art.rating_text(item.get("imdb_rating", ""))
		if r != "":
			sub.append("★ " + r)
		var s := U.label(Art.SEP.join(sub), "xs", "muted", "medium")
		U.ellipsis(s)
		_label.add_child(s)
		add_child(_label)
	_layout()
	if mode != "more":
		_img_due = true
		if not lazy:
			wake()
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(_on_gui_input)
	if mode == "poster" and expand:
		_dwell = Timer.new()
		_dwell.one_shot = true
		_dwell.wait_time = EXPAND_DWELL
		_dwell.timeout.connect(_grow)
		add_child(_dwell)


## Bild jetzt laden (einmal). Liegt es schon bereit, steht es sofort (ohne Einblenden) – beim
## Blättern kein Aufflackern.
func wake() -> void:
	lazy = false
	if not _img_due:
		return
	_img_due = false
	_sync = true
	if mode == "wide" or mode == "episode":
		_load_backdrop()
	else:
		Art.load_image(str(item.get("poster", "")), int(POSTER.x) + 12, _on_poster)
	_sync = false


func _tex_rect(t: Texture2D, stretch: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = stretch
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Schrift auf einem Bild bleibt hell, auch im hellen Farbschema (Papier): dort wäre die dunkle
## Schrift auf dem abgedunkelten Bildrand mit ihrem Schatten nur ein verwaschener Doppelstrich.
static func on_image(l: Label, tone := "text") -> Label:
	if UzTheme.light:
		l.add_theme_color_override("font_color", Color(str(UzTheme.PRESETS.uzai.get(tone, UzTheme.PRESETS.uzai.text))))
	return l


## Name und Jahr auf dem Farbfeld (verschwindet unter dem echten Plakat).
func _poster_text() -> VBoxContainer:
	var v := U.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_END
	var t := U.label(str(item.get("name", "")), "l", "text", "bold", true)
	t.max_lines_visible = 4
	t.add_theme_constant_override("line_spacing", -3)
	U.shadow(on_image(t), 0.5)
	v.add_child(t)
	var y := str(item.get("year", ""))
	if y != "":
		v.add_child(on_image(U.label("%s%s%s" % [Art.type_label(str(item.get("type", ""))), Art.SEP, y], "xs", "muted", "medium"), "muted"))
	return v


## Querformat: Hintergrundbild, unten dunkler, darauf Schriftzug oder Name (und bei
## Weiterschauen Folge, Restzeit und Balken).
func _build_wide(seed: String) -> void:
	_wide = Control.new()
	_wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wide.modulate.a = 0.0 if mode == "poster" else 1.0
	_clip.add_child(_wide)
	_bd_ph = _tex_rect(Art.backdrop_tex(seed), TextureRect.STRETCH_SCALE)
	_wide.add_child(_bd_ph)
	_bd_img = _tex_rect(null, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_wide.add_child(_bd_img)
	_scrim = Control.new()
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.draw.connect(_draw_scrim)
	_wide.add_child(_scrim)
	_wtext = U.vbox(4)
	_wtext.alignment = BoxContainer.ALIGNMENT_END
	_wide.add_child(_wtext)
	if mode == "episode":
		_episode_text()
		return
	var logo_url := str(item.get("logo", ""))
	_logo = _tex_rect(null, TextureRect.STRETCH_KEEP_ASPECT)
	_logo.custom_minimum_size = Vector2(0, 64 if mode == "wide" else 84)
	_logo.visible = false
	_wtext.add_child(_logo)
	_wtitle = U.label(str(item.get("name", "")), "m" if mode == "wide" else "l", "text", "bold", true)
	_wtitle.max_lines_visible = 2
	U.shadow(on_image(_wtitle), 0.6)
	_wtext.add_child(_wtitle)
	var sub := ""
	if mode == "wide":
		var parts := PackedStringArray()
		if bool(item.get("next_up", false)):
			parts.append("Als Nächstes")
		if int(item.get("episode", 0)) > 0:
			parts.append(Art.episode_code(int(item.get("season", 0)), int(item.episode)))
		var lt := Art.left_text(float(item.get("position", 0.0)), float(item.get("duration", 0.0)))
		if lt != "":
			parts.append(lt)
		sub = Art.SEP.join(parts)
	else:
		sub = Art.meta_line(item)
	if sub != "":
		var s := U.label(sub, "s", "muted", "medium")
		U.shadow(on_image(s, "muted"), 0.6)
		s.clip_text = true
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_wtext.add_child(s)
	if mode == "wide":
		_wtext.add_child(U.spacer(0, 10, false))
	if logo_url != "":
		Art.load_image(logo_url, 360, func(t: Texture2D) -> void:
			if t and is_instance_valid(_logo):
				_logo.texture = t
				_logo.visible = true
				_wtitle.visible = false
		)


## „Alle anzeigen“: ruhige Glasfläche mit Pfeil in einem Kreis.
func _build_more() -> void:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(c)
	var v := U.vbox(14)
	c.add_child(v)
	var circle := Control.new()
	circle.custom_minimum_size = Vector2(72, 72)
	circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.draw.connect(func() -> void: circle.draw_circle(Vector2(36, 36), 36.0, UzTheme.col("text", 0.1), true, -1.0, true))
	var ic := U.icon("chevron_right", 32, "text")
	ic.position = Vector2(20, 20)
	circle.add_child(ic)
	v.add_child(circle)
	var l := U.label("Alle anzeigen", "m", "text", "ui_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	# Durchsichtige Glasfläche: nicht als Maske benutzen, sonst wäre der Inhalt genauso durchsichtig.
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	_clip.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("text", 0.07), UzTheme.r_cover()))


func _layout() -> void:
	var w := lerpf(_w, roundf(_h * 16.0 / 9.0), _expand_t) if mode == "poster" and expand else _w
	var lab := GRID_LABEL_H if mode == "grid" else 0.0
	custom_minimum_size = Vector2(w, _h + lab)
	_frame.size = Vector2(w, _h)
	_frame.pivot_offset = Vector2(w * 0.5, _h)
	_clip.size = _frame.size
	_ring.size = _frame.size
	for ch in _clip.get_children():
		if ch == _ph_text or ch == _shine:
			continue
		(ch as Control).position = Vector2.ZERO
		(ch as Control).size = _frame.size
	if _ph_text:
		_ph_text.position = Vector2(18, 18)
		_ph_text.size = Vector2(_w - 36, _h - 36)
		for ch in _ph_text.get_children():
			if ch is Label:
				(ch as Label).custom_minimum_size.x = _w - 36
	if _wide:
		for ch in _wide.get_children():
			(ch as Control).position = Vector2.ZERO
			(ch as Control).size = _frame.size
		var pad := 22.0 if mode == "poster" else 18.0
		var tw := (roundf(_h * 16.0 / 9.0) if mode == "poster" else w) - pad * 2.0
		_wtext.position = Vector2(pad, pad)
		_wtext.size = Vector2(tw, _h - pad * 2.0)
		for ch in _wtext.get_children():
			if ch is Label:
				(ch as Label).custom_minimum_size.x = minf(tw, 520.0)
		if is_instance_valid(_logo):
			_logo.custom_minimum_size.x = minf(tw * 0.7, 320.0)
	if _label:
		_label.position = Vector2(2, _h + 12)
		_label.size = Vector2(w - 4, GRID_LABEL_H - 12)
	_frame.queue_redraw()
	_ring.queue_redraw()


var _sync := false


func _on_poster(t: Texture2D) -> void:
	if t == null or not is_instance_valid(_img):
		return
	# Kluger Ausschnitt, auch während die Karte breit wird; Ton und Verlauf (Punkt 97).
	Zuschnitt.put(_img, t)
	if _ph_text:
		_ph_text.visible = false
	if _sync:
		_img.modulate.a = 1.0
		return
	_img.modulate.a = 0.0
	U.ankommen(_img, U.T_ORT, "uz_fade").tween_property(_img, "modulate:a", 1.0, U.T_ORT)


func _load_backdrop() -> void:
	if _bd_loaded or _bd_img == null:
		return
	_bd_loaded = true
	var url := str(item.get("thumbnail", "")) if mode == "wide" or mode == "episode" else ""
	if url == "":
		url = str(item.get("_backdrop", "")) if mode == "episode" else Art.backdrop_url(item)
	Art.load_image(url, 640, func(t: Texture2D) -> void:
		if t == null or not is_instance_valid(_bd_img):
			return
		# Breite Karten haben ihren eigenen Verlauf für die Schrift: nur Ausschnitt und Ton.
		Zuschnitt.put(_bd_img, t, true, false)
		if _sync:
			_bd_img.modulate.a = 1.0
			return
		_bd_img.modulate.a = 0.0
		U.ankommen(_bd_img, U.T_ORT, "uz_fade").tween_property(_bd_img, "modulate:a", 1.0, U.T_ORT)
	)


# --- Auswahl -------------------------------------------------------------------------------------

func _on_focus(on: bool) -> void:
	if on and _img_due:
		wake()
	# Plakate (Filme, Serien) bleiben gewählt so groß, wie sie sind: nur Rahmen und Glanz zeigen
	# die Auswahl. Breite Karten wachsen ein wenig (Kurve „Ankommen“, ohne Nachfedern).
	_tw = U.ankommen(_frame, U.T_ORT, "uz_gross")
	_tw.tween_property(_frame, "scale", Vector2.ONE * _gross(on), U.T_ORT if on else U.T_WEG)
	Liste.takt(self, _focus_t, on, _set_focus_t)
	if on:
		if UzTheme.focus_shine() and not Leicht.active and not U.reduziert():
			if _shine == null or not is_instance_valid(_shine):
				_shine = Shine.new()
				_clip.add_child(_shine)
			_clip.move_child(_shine, _clip.get_child_count() - 1)
			_shine.play()
		if _dwell:
			_dwell.start()
		focused_item.emit(item)
	else:
		if _dwell:
			_dwell.stop()
		_set_expand(0.0, U.T_ORT)


## Größe gewählt bzw. nicht gewählt; „Animationen reduzieren“: kein Wachsen.
func _gross(on: bool) -> float:
	if not on or mode == "poster":
		return 1.0
	return U.wachsen(FOCUS_SCALE if mode != "grid" else 1.06)


## Stehen geblieben: die Karte wird breit und zeigt das Hintergrundbild (wie in Nuvio).
func _grow() -> void:
	if not has_focus():
		return
	_load_backdrop()
	_set_expand(1.0, U.T_RAUM)


func _set_expand(to: float, dur: float) -> void:
	if not (mode == "poster" and expand):
		return
	if _xtw:
		_xtw.kill()
	if absf(_expand_t - to) < 0.001:
		return
	_xtw = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_xtw.tween_method(func(v: float) -> void:
		_expand_t = v
		if is_instance_valid(_wide):
			_wide.modulate.a = clampf(v * 1.4 - 0.2, 0.0, 1.0)
		_layout()
	, _expand_t, to, dur)


## Sofort schmal (z. B. bevor die Reihe neu gebaut wird).
func collapse() -> void:
	if _dwell:
		_dwell.stop()
	if _xtw:
		_xtw.kill()
	_expand_t = 0.0
	if is_instance_valid(_wide) and mode == "poster":
		_wide.modulate.a = 0.0
	_layout()


## A gedrückt: kurz einsinken und zurück (Takt „Antwort“, ohne Nachfedern); der Ring bleibt.
func press_feedback() -> void:
	_set_focus_t(1.0)
	var sc := _gross(true)
	_tw = U.ankommen(_frame, U.T_ORT, "uz_gross")
	_tw.tween_property(_frame, "scale", Vector2.ONE * (sc - (0.0 if U.reduziert() else 0.04)), U.T_ANTWORT)
	_tw.tween_property(_frame, "scale", Vector2.ONE * sc, U.T_ORT)


func _set_focus_t(v: float) -> void:
	_focus_t = v
	if is_instance_valid(_ring):
		_ring.queue_redraw()
	if is_instance_valid(_frame):
		_frame.queue_redraw()


func _draw_shadow() -> void:
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(UzTheme.r_cover())
	sh.shadow_color = Color(0, 0, 0, 0.28 + 0.22 * _focus_t)
	sh.shadow_size = int(14 + 18 * _focus_t)
	sh.shadow_offset = Vector2(0, 8 + 8 * _focus_t)
	_frame.draw_style_box(sh, Rect2(Vector2.ZERO, _frame.size))


## Der eine Cursor für Cover und Kacheln (UzTheme.draw_tile_focus) – kein eigener Rahmen hier.
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


## Unten dunkler, damit Schriftzug und Text auf jedem Bild lesbar bleiben (wie Nuvio).
func _draw_scrim() -> void:
	var s := _scrim.size
	var stops := [[0.0, 0.0], [0.38, 0.06], [0.58, 0.32], [0.78, 0.68], [1.0, 0.9]]
	if mode == "poster":
		stops = [[0.0, 0.0], [0.45, 0.04], [0.68, 0.38], [1.0, 0.86]]
	elif mode == "episode":
		stops = [[0.0, 0.0], [0.2, 0.04], [0.38, 0.26], [0.54, 0.56], [0.7, 0.76], [0.86, 0.88], [1.0, 0.95]]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var y0 := s.y * float(a[0])
		var y1 := s.y * float(b[0])
		var ca := Color(0, 0, 0, float(a[1]))
		var cb := Color(0, 0, 0, float(b[1]))
		_scrim.draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(s.x, y0), Vector2(s.x, y1), Vector2(0, y1)]),
			PackedColorArray([ca, ca, cb, cb]))
	if mode == "poster":
		# Von links etwas dunkler: dort steht der Name.
		var cl := Color(0, 0, 0, 0.42)
		var cr := Color(0, 0, 0, 0.0)
		_scrim.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x * 0.6, 0), Vector2(s.x * 0.6, s.y), Vector2(0, s.y)]),
			PackedColorArray([cl, cr, cr, cl]))


## Fortschritt (Weiterschauen) und der Haken für Gesehenes.
func _draw_badges() -> void:
	var s := _badges.size
	if (mode == "wide" or mode == "episode") and _prog > 0.0 and not watched:
		var h := 5.0
		var r := Rect2(18, s.y - 14 - h, s.x - 36, h)
		_badges.draw_style_box(UzTheme.box(Color(1, 1, 1, 0.22), 3), r)
		_badges.draw_style_box(UzTheme.box(UzTheme.col("accent"), 3), Rect2(r.position, Vector2(maxf(h, r.size.x * _prog), h)))
	if watched:
		var c := Vector2(s.x - 26, 26)
		_badges.draw_circle(c, 16.0, Color(0, 0, 0, 0.62), true, -1.0, true)
		var pts := PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 5), c + Vector2(7, -5)])
		_badges.draw_polyline(pts, UzTheme.col("text"), 2.6, true)


## Folge: kleine Nummer, Titel, zwei Zeilen Inhalt und das Datum.
func _episode_text() -> void:
	var avail := bool(item.get("available", true))
	var badge := PanelContainer.new()
	var bsb := UzTheme.box(Color(0, 0, 0, 0.55), 8)
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bsb.content_margin_top = 3
	bsb.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", bsb)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(on_image(U.label(Art.episode_code(int(item.get("season", 0)), int(item.get("episode", 0))), "cap", "text", "ui_bold")))
	_wtext.add_child(badge)
	_wtitle = U.label(str(item.get("title", "")), "m", "text", "bold")
	_wtitle.clip_text = true
	_wtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	U.shadow(on_image(_wtitle), 0.6)
	_wtext.add_child(_wtitle)
	var ov := str(item.get("overview", "")).strip_edges()
	if ov != "":
		var o := Art.fit_lines(on_image(U.label(ov, "xs", "muted", "regular", true), "muted"), _w - 36.0, 2)
		o.set_meta("uz_fixed", true)
		_wtext.add_child(o)
	var when := str(item.get("released", "")).get_slice("T", 0)
	var d := when.split("-")
	var date := "%s.%s.%s" % [d[2], d[1], d[0]] if d.size() == 3 else when
	var info := "Noch nicht erschienen" + (Art.SEP + date if date != "" else "") if not avail else date
	if info != "":
		var il := U.label(info, "cap", "faint" if avail else "warn", "medium")
		_wtext.add_child(on_image(il, "faint") if avail else il)
	_wtext.add_child(U.spacer(0, 6, false))
	if not avail:
		_frame.modulate = Color(1, 1, 1, 0.62)


## Gesehen-Haken nachträglich ändern (ohne Neuaufbau).
func set_watched(on: bool) -> void:
	watched = on
	if is_instance_valid(_badges):
		_badges.queue_redraw()


func nav_ud(d: int) -> bool:
	if nav_ud_cb.is_valid():
		return bool(nav_ud_cb.call(d))
	return false


## In einer Reihe: an den Enden anschlagen statt schräg in eine andere Reihe zu springen.
func nav_lr(d: int) -> bool:
	if not nav_ud_cb.is_valid() or get_parent() == null:
		return false
	var i := get_index()
	if (d < 0 and i == 0) or (d > 0 and i == get_parent().get_child_count() - 1):
		Nav._bump(self, "left" if d < 0 else "right")
		return true
	return false


func activate() -> void:
	chosen.emit(item)


## Geteilte Elemente (src/ui/flug.gd): das Plakat – aufgeklappt oder quer das Hintergrundbild,
## ohne geladenes Bild das Farbfeld. Solange es fliegt, ist nur die Bildfläche verborgen: Ring und
## Schrift stehen beim Zurück im ersten Bild.
func flug_bild() -> Dictionary:
	if is_instance_valid(_wide) and _wide.modulate.a > 0.5 and is_instance_valid(_bd_img) and _bd_img.texture:
		return { "node": _bd_img, "hide": _clip }
	if is_instance_valid(_img) and _img.texture and _img.visible:
		return { "node": _img, "hide": _clip }
	if is_instance_valid(_ph) and _ph.texture:
		return { "node": _ph, "hide": _clip }
	return {}


func _on_gui_input(e: InputEvent) -> void:
	Nav.klick(self, e)

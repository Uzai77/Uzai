extends "res://src/ui/layers/layer.gd"
## Der Videoplayer. mpv zeigt das Bild darunter, Uzai legt die eigene Leiste darüber
## (durchsichtiges Fenster). Die Leiste erscheint bei jeder Eingabe und verschwindet nach
## ein paar Sekunden wieder.
##
## Unten: Kanal, Titel groß, rechts daneben „Als Nächstes“, darunter die Zeitleiste – ruhig: eine
## feine Linie (4 px), der Griff erscheint nur beim Spulen und in der Pause genau am Ende des
## Füllstands; beim Spulen wird die Leiste kräftiger und eine Blase über dem Griff zeigt die
## Zielzeit. Links die Stelle (mit „UT“, sobald Untertitel an sind), rechts die Restzeit („−12:34“).
## SponsorBlock-Abschnitte sind helle Marken (nicht gold). Oben rechts Uhr und wann das Video
## endet. Die Leiste gleitet W_ORT von unten herein (T_ORT, Ankommen) und geht in T_WEG (Gehen).
## Kurze Hinweise (Untertitel, übersprungene Werbung) erscheinen oben in der Mitte – im Player,
## nicht als Mitteilung.
##
## A Pause · ←/→ 10 s · LT/RT 1 Min. · ↑/↓ Lautstärke · LB/RB voriges/nächstes Video
## X Untertitel · Y Optionen (auch Tonspur und Untertitel-Spur) · ≡ Bild in Bild (src/core/pip.gd) · B Beenden · Guide wie überall
## Bei „Nur Ton“ legt ≡ das Video in den Hintergrund: der Player geht zu, der Ton läuft weiter
## (Guide → „Video-Ton“). Kurz nach einem übersprungenen Abschnitt führt ← zurück an seinen Anfang.
##
## Shorts: ↑/↓ blättern (das davor, das nächste), LT/RT Lautstärke, am Ende kommt gleich das
## nächste. Ohne mpv (Vorführung) steht das Bild hochkant in der Mitte und gleitet beim Blättern.

const Sheet := preload("res://src/ui/layers/sheet.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const VideoOptions := preload("res://src/ui/layers/video_options.gd")
const VideoQr := preload("res://src/ui/layers/video_qr.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")

const Main := preload("res://src/main.gd")
var main: Main
var _pad: Control
var _osc: Control
var _osc_t := 0.0
var _title: Label
var _channel_row: HBoxContainer
var _time_l: Label
var _left_l: Label
var _ut_l: Label                ## „UT“ neben der Zeit, solange Untertitel an sind
var _ends_l: Label
var _bar: Control
var _foot: Control              ## Titel und Zeitleiste unten (gleitet mit der Leiste)
var _osc_on := false
var _center: Control
var _center_icon: TextureRect
var _backdrop: TextureRect
var _audio_box: Control
var _audio_art: TextureRect
var _levels: Control
var _end_box: Control
var _end_kind: Label
var _end_title: Label
var _end_sub: Label
var _end_art: TextureRect
var _end_poster: TextureRect
var _end_ring: Control
var _end_t := 0.0
var _end_total := 8.0
var _clock: Label
var _head: Control
var _next_box: Control
var _next_title: Label
var _next_poster: TextureRect
var _vol_box: Control
var _vol_bar = null
var _vol_l: Label
var _vol_ic: TextureRect
var _vol_t := 0.0
var _notice: PanelContainer
var _notice_l: Label
var _notice_icon: TextureRect
var _notice_t := 0.0
var _last_seek := 0
var _seek_streak := 0
var _seek_t := 0.0
var _seek_hold := 0.0
var _seek_text := ""
var _spin := 0.0
var _level_t := 0.0
var _short_frame: Panel         ## Shorts ohne mpv-Bild (Vorführung): das Bild hochkant in der Mitte
var _short_img: TextureRect
var _short_dir := 0             ## letzte Blätterrichtung (1 runter, -1 hoch) für das Gleiten
var _short_ghost: Panel         ## das eben verlassene Short, gleitet beim Blättern hinaus
var _short_ghost_img: TextureRect
var _short_at := 0              ## Zeit (ms) des letzten Blätterschritts
const SHORT_GAP_MS := 240       ## so lange rastet ein Schritt ein; gehaltener Stick blättert nicht durch
const SHORT_SNAP := 0.3         ## Dauer des Einrastens (s)


func _init() -> void:
	super()
	dim = 0.0


func build() -> void:
	set_meta("uz_hint_b", "Beenden")
	set_meta("uz_hints", hints_for(Video.shorts, Video.audio_only, Video.video.has("movies")))
	_backdrop = TextureRect.new()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_backdrop)
	add_child(_backdrop)
	_build_short_frame()
	_build_audio_box()
	_build_center()
	_build_osc()
	_build_end()
	_build_volume()
	_build_notice()
	_pad = _Pad.new()
	_pad.player = self
	_pad.focus_mode = Control.FOCUS_ALL
	_pad.custom_minimum_size = Vector2(1, 1)
	_pad.set_meta("uz_hint_a", "Pause")
	_pad.set_meta("uz_hint_x", "Untertitel")
	_pad.set_meta("uz_hint_y", "Optionen")
	add_child(_pad)
	Video.changed.connect(_on_state)
	Video.started.connect(_on_started)
	Video.reached_end.connect(_on_end)
	Video.stopped.connect(_on_stopped)
	Video.skipped.connect(_on_skipped)
	Video.volume_changed.connect(_show_volume)
	_on_started(Video.video)
	show_osc()
	# Lief das Video eben noch als Bild in Bild (neues Video aus Uzai, Vollbild aus dem Guide):
	# zurück ins Vollbild.
	if Video.pip and main and main.pip != null:
		main.pip.leave()


func _first_focus() -> Control:
	return _pad


## Geteilte Elemente (src/ui/flug.gd): Das Vorschaubild der Karte geht im Bild des Players auf
## (über mpv: Es wächst auf den Schirm und gibt dann das Video frei).
func flug_ziel() -> Control:
	return _short_img if is_instance_valid(_short_frame) and _short_frame.visible else _backdrop


## Tastenhinweise unten je Art: Shorts blättern mit hoch/runter, bei „Nur Ton“ geht ≡ in den
## Hintergrund (Filme: dort gibt es kein „Nur Ton“ im Hintergrund).
static func hints_for(shorts: bool, audio: bool, film: bool) -> Array:
	if shorts:
		return [["ud", "Blättern"], ["lt", ""], ["rt", "Lautstärke"], ["menu", "Bild in Bild"]]
	return [["ud", "Lautstärke"], ["menu", "Im Hintergrund" if audio and not film else "Bild in Bild"], ["lb", "Voriges"], ["rb", "Nächstes"]]


## Shorts in der Vorführung: das Bild hochkant (9:16) in der Mitte, mit runden Ecken und Schatten.
## Dazu ein zweiter Rahmen für das eben verlassene Short: Beim Blättern schiebt das neue es wie im
## Feed hinaus und rastet in der Mitte ein.
func _build_short_frame() -> void:
	_short_ghost = _short_panel()
	_short_ghost_img = _short_ghost.get_child(0)
	_short_frame = _short_panel()
	_short_img = _short_frame.get_child(0)


func _short_panel() -> Panel:
	var f := Panel.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel())
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 40
	f.add_theme_stylebox_override("panel", sb)
	f.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.set_anchors_preset(Control.PRESET_CENTER)
	f.visible = false
	add_child(f)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(img)
	f.add_child(img)
	return f


## Rahmen auf 86 % der Höhe, 9:16, mittig. Beim Blättern kommt das neue Short eine ganze Höhe aus
## der Richtung herein und rastet weich ein; das alte gleitet zur anderen Seite hinaus.
func _place_short_frame() -> void:
	var vh := get_viewport_rect().size.y
	var h := roundf(vh * 0.86)
	var w := roundf(h * 9.0 / 16.0)
	for f: Panel in [_short_frame, _short_ghost]:
		f.offset_left = -w * 0.5
		f.offset_right = w * 0.5
		f.offset_top = -h * 0.5
		f.offset_bottom = h * 0.5
	if _short_dir == 0:
		return
	var travel := (h + 48.0) * _short_dir
	var y := (vh - h) * 0.5          # Ruhelage (auch wenn das vorige Einrasten noch läuft)
	var tw := U.tw(_short_frame, "uz_short", Tween.TRANS_CUBIC).set_parallel(true)
	tw.tween_property(_short_frame, "position:y", y, SHORT_SNAP).from(y + travel)
	if _short_ghost.visible:
		var gw := U.tw(_short_ghost, "uz_short", Tween.TRANS_CUBIC).set_parallel(true)
		gw.tween_property(_short_ghost, "position:y", y - travel, SHORT_SNAP).from(y)
		gw.tween_property(_short_ghost, "modulate:a", 0.45, SHORT_SNAP).from(1.0)
		gw.chain().tween_callback(_short_ghost.hide)
	_short_dir = 0


# --- Aufbau ------------------------------------------------------------------------------------

func _build_audio_box() -> void:
	_audio_box = CenterContainer.new()
	U.full_rect(_audio_box)
	_audio_box.offset_bottom = -260
	_audio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_audio_box)
	var v := U.vbox(26)
	_audio_box.add_child(v)
	var art := Panel.new()
	art.custom_minimum_size = Vector2(576, 324)
	art.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel()))
	art.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	art.name = "Art"
	_audio_art = TextureRect.new()
	_audio_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_audio_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	U.full_rect(_audio_art)
	art.add_child(_audio_art)
	v.add_child(art)
	var tag := U.hbox(14)
	tag.alignment = BoxContainer.ALIGNMENT_CENTER
	_levels = Control.new()
	_levels.custom_minimum_size = Vector2(34, 26)
	_levels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_levels.draw.connect(_draw_levels)
	tag.add_child(_levels)
	var tl := U.label("Nur Ton", "m", "music", "ui_bold")
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(tl)
	v.add_child(tag)


## Fünf kleine Pegel, die sich nur bewegen, solange wirklich etwas spielt.
func _draw_levels() -> void:
	var c := UzTheme.col("music")
	for i in 5:
		var playing := not Video.paused and not Video.loading and not Video.at_end
		var amp := 0.25
		if playing:
			amp = 0.35 + 0.65 * absf(sin(_level_t * (2.1 + i * 0.73) + i * 1.7))
		var h := maxf(4.0, _levels.size.y * amp)
		var r := Rect2(i * 7.0, (_levels.size.y - h) * 0.5, 4.0, h)
		_levels.draw_style_box(UzTheme.box(c, 2), r)


func _build_center() -> void:
	_center = Control.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.custom_minimum_size = Vector2(160, 160)
	_center.offset_left = -80
	_center.offset_top = -80
	_center.offset_right = 80
	_center.offset_bottom = 80
	_center.draw.connect(_draw_center)
	add_child(_center)
	_center_icon = U.icon("pause", 60, "text")
	_center_icon.position = Vector2(50, 50)
	_center.add_child(_center_icon)


func _draw_center() -> void:
	var c := _center.size * 0.5
	if Video.loading and not Video.at_end:
		# Ladekreis auf einer zarten Scheibe.
		_center.draw_circle(c, 62, Color(UzTheme.col("bg"), 0.45))
		_center.draw_arc(c, 40, 0, TAU, 64, Color(UzTheme.col("text"), 0.12), 5.0, true)
		_center.draw_arc(c, 40, _spin, _spin + TAU * 0.3, 32, UzTheme.col("text"), 5.0, true)
		return
	if Video.paused and not Video.at_end:
		_center.draw_circle(c, 72, Color(UzTheme.col("bg"), 0.55))


func _build_osc() -> void:
	_osc = Control.new()
	_osc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_osc)
	add_child(_osc)
	# Verlauf unten und oben, damit Text auf hellen Videos lesbar bleibt – flach und zurückhaltend,
	# das Bild bleibt das Bild.
	for top in [false, true]:
		var gr := TextureRect.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		var a := 0.72 if not top else 0.5
		g.colors = PackedColorArray([Color(0, 0, 0, a), Color(0, 0, 0, a * 0.5), Color(0, 0, 0, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0 if top else 1)
		gt.fill_to = Vector2(0, 1 if top else 0)
		gt.width = 8
		gt.height = 128
		gr.texture = gt
		gr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gr.stretch_mode = TextureRect.STRETCH_SCALE
		gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gr.anchor_right = 1.0
		if top:
			gr.offset_bottom = 200
		else:
			gr.anchor_top = 1.0
			gr.anchor_bottom = 1.0
			gr.offset_top = -440
		_osc.add_child(gr)
	# Oben rechts: Uhr und wann das Video zu Ende ist.
	var head := U.margin(96, 40, 96, 0)
	head.anchor_right = 1.0
	_osc.add_child(head)
	_head = head
	var hcol := U.vbox(2)
	hcol.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(hcol)
	_clock = U.label(U.clock(), "l", "text", "ui_bold")
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Uhrzeit
	_clock.clip_text = false
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hcol.add_child(_clock)
	_ends_l = U.label("", "s", "muted", "medium")
	_ends_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hcol.add_child(_ends_l)
	# Unten: Kanal, Titel und rechts „Als Nächstes“; darunter die Zeitleiste. In einer eigenen Hülle,
	# die mit der Leiste ein Stück gleitet (_set_osc).
	_foot = Control.new()
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_foot)
	_osc.add_child(_foot)
	var foot := U.margin(96, 0, 96, 104)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.add_child(foot)
	var col := U.vbox(12)
	foot.add_child(col)
	var top_row := U.hbox(48)
	col.add_child(top_row)
	var tcol := U.vbox(10)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_END
	top_row.add_child(tcol)
	_channel_row = U.hbox(12)
	tcol.add_child(_channel_row)
	_title = U.label("", "xxl", "text", "bold", true)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Titel bleiben, wie der Kanal sie schreibt
	_title.max_lines_visible = 2
	_title.add_theme_constant_override("line_spacing", -8)
	U.shadow(_title, 0.5)
	tcol.add_child(_title)
	_next_box = _build_next()
	top_row.add_child(_next_box)
	col.add_child(U.spacer(0, 30, false))
	var trow := U.hbox(24)
	col.add_child(trow)
	var tbox := U.hbox(10)
	tbox.custom_minimum_size = Vector2(84, 0)
	trow.add_child(tbox)
	_time_l = U.label("0:00", "m", "text", "ui_bold")
	# Stelle und Restzeit laufen jede Sekunde weiter: nie durch die Übersetzung (jede Sekunde wäre dort ein neuer Text).
	_time_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_time_l.clip_text = false
	_time_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tbox.add_child(_time_l)
	# „UT“ steht neben der Zeit, solange Untertitel an sind – so sieht man den Stand, ohne zu raten.
	_ut_l = U.label("UT", "cap", "accent", "ui_bold")
	_ut_l.clip_text = false
	_ut_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ut_l.visible = false
	tbox.add_child(_ut_l)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 32)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	trow.add_child(_bar)
	_left_l = U.label("−0:00", "m", "muted", "ui")
	_left_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_left_l.clip_text = false
	_left_l.custom_minimum_size = Vector2(96, 0)
	_left_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trow.add_child(_left_l)


## „Als Nächstes“: kleines Bild und Titel rechts neben dem großen Titel.
func _build_next() -> Control:
	var box := U.hbox(16)
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	var thumb := Panel.new()
	thumb.custom_minimum_size = Vector2(160, 90)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface"), UzTheme.r_cover()))
	thumb.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_next_poster = TextureRect.new()
	_next_poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	U.full_rect(_next_poster)
	thumb.add_child(_next_poster)
	box.add_child(thumb)
	var col := U.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(300, 0)
	var row := U.hbox(8)
	row.add_child(U.label("Als Nächstes", "s", "muted", "medium"))
	row.add_child(U.glyph("rb", 24))
	col.add_child(row)
	_next_title = U.label("", "m", "text", "bold", true)
	_next_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_next_title.max_lines_visible = 2
	_next_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_next_title.custom_minimum_size = Vector2(300, VideoCard.two_lines(_next_title))
	col.add_child(_next_title)
	box.add_child(col)
	return box


func _draw_bar() -> void:
	var w := _bar.size.x
	if Video.is_live():
		# Live: ein ruhiger, voller Balken ohne Knopf (es gibt nichts zu spulen).
		_bar.draw_style_box(UzTheme.box(Color(1, 1, 1, 0.34), 3), Rect2(0, _bar.size.y * 0.5 - 3.0, w, 6))
		return
	var k := _seek_t
	# Ruhig: eine feine Linie, beim Spulen kräftiger; der Griff nur beim Spulen und in der Pause.
	var h := lerpf(4.0, 8.0, k)
	var cy := _bar.size.y * 0.5
	var y := cy - h * 0.5
	var rad := int(h * 0.5)
	_bar.draw_style_box(UzTheme.box(Color(1, 1, 1, 0.22), rad), Rect2(0, y, w, h))
	var d := maxf(Video.duration, 1.0)
	# SponsorBlock: helle Marken auf der Leiste, deutlich anders als der Füllstand im Akzent.
	for s in Video.segments:
		var x0 := w * clampf(float(s.start) / d, 0.0, 1.0)
		var x1 := w * clampf(float(s.end) / d, 0.0, 1.0)
		_bar.draw_style_box(UzTheme.box(Color(1, 1, 1, 0.5), rad), Rect2(x0, y, maxf(h, x1 - x0), h))
	var p := clampf(Video.pos / d, 0.0, 1.0) if Video.duration > 0 else 0.0
	var kx := w * p
	# Der Füllstand endet genau unter der Mitte des Griffs.
	_bar.draw_style_box(UzTheme.box(UzTheme.col("accent"), rad), Rect2(0, y, maxf(h, kx), h))
	var g := griff_staerke(k, Video.paused, Video.at_end)
	if g <= 0.01:
		return
	var r := lerpf(8.0, 12.0, k)
	# Eckig (Marke): ein eckiger Griff wie bei jedem Regler, kein Glimmen darum.
	if UzTheme.strict():
		_bar.draw_rect(Rect2(kx - r * 0.6, cy - r, r * 1.2, r * 2.0), Color(UzTheme.col("focus"), g))
		if k > 0.01 and _seek_text != "":
			_draw_bubble(kx, cy - r - 10.0, k)
		return
	_bar.draw_circle(Vector2(kx, cy + 2.0), r + 2.0, Color(0, 0, 0, 0.3 * g))
	if k > 0.01:
		_bar.draw_circle(Vector2(kx, cy), r + 7.0 * k, Color(UzTheme.col("accent"), 0.22 * k))
	_bar.draw_circle(Vector2(kx, cy), r, Color(UzTheme.col("focus"), g))
	if k > 0.01 and _seek_text != "":
		_draw_bubble(kx, cy - r - 10.0, k)


## Wie deutlich der Griff auf der Zeitleiste steht: voll beim Spulen (k) und in der Pause, sonst
## gar nicht (am Ende nie) – die Linie allein ist ruhiger.
static func griff_staerke(seek_k: float, paused: bool, at_end: bool) -> float:
	if at_end:
		return 0.0
	return clampf(maxf(seek_k, 1.0 if paused else 0.0), 0.0, 1.0)


## Rechts steht die Restzeit („−12:34“), nicht die Gesamtlänge; ohne Länge „–:––“.
static func left_text(pos: float, duration: float) -> String:
	if duration <= 0.0:
		return "–:––"
	return "−" + YouTube.time_text(maxf(duration - pos, 0.0))


## Blase über dem Knopf: Zielzeit groß, Sprung klein daneben.
func _draw_bubble(x: float, bottom: float, k: float) -> void:
	var f := UzTheme.ui("ui_bold")
	var fs := UzTheme.size("m")
	var f2 := UzTheme.font("medium")
	var fs2 := UzTheme.size("s")
	var t1 := YouTube.time_text(Video.pos)
	var w1 := f.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w2 := f2.get_string_size(tr(_seek_text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var bw := w1 + w2 + 22.0 + 40.0
	var bh := 44.0
	var bx := clampf(x - bw * 0.5, 0.0, maxf(0.0, _bar.size.x - bw))
	var rect := Rect2(bx, bottom - bh, bw, bh)
	var sb := UzTheme.flaeche(Color(UzTheme.col("surface_hi"), 0.94 * k), 999)
	sb.shadow_color = Color(0, 0, 0, 0.35 * k)
	sb.shadow_size = 14
	_bar.draw_style_box(sb, rect)
	var base := rect.position.y + (bh + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	_bar.draw_string(f, Vector2(rect.position.x + 20.0, base), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UzTheme.col("text"), k))
	_bar.draw_string(f2, Vector2(rect.position.x + 20.0 + w1 + 22.0, base), tr(_seek_text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(UzTheme.col("accent"), k))


func _build_end() -> void:
	_end_box = CenterContainer.new()
	U.full_rect(_end_box)
	_end_box.offset_bottom = -200
	_end_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_box.visible = false
	add_child(_end_box)
	var panel := PanelContainer.new()
	var sb := UzTheme.flaeche(Color(UzTheme.col("surface"), 0.95), UzTheme.r_panel())
	sb.content_margin_left = 28
	sb.content_margin_right = 44
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	panel.add_theme_stylebox_override("panel", sb)
	_end_box.add_child(panel)
	var row := U.hbox(36)
	panel.add_child(row)
	var art := Panel.new()
	art.custom_minimum_size = Vector2(448, 252)
	art.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	art.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_end_poster = TextureRect.new()
	_end_poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_end_poster.stretch_mode = TextureRect.STRETCH_SCALE
	U.full_rect(_end_poster)
	art.add_child(_end_poster)
	_end_art = TextureRect.new()
	_end_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_end_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	U.full_rect(_end_art)
	art.add_child(_end_art)
	_end_ring = Control.new()
	U.full_rect(_end_ring)
	_end_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_ring.draw.connect(_draw_end_ring)
	art.add_child(_end_ring)
	row.add_child(art)
	var col := U.vbox(10)
	col.custom_minimum_size = Vector2(560, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_end_kind = U.label("", "m", "accent", "medium")
	col.add_child(_end_kind)
	_end_title = U.label("", "xl", "text", "bold", true)
	_end_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel des nächsten Videos bzw. der Folge
	_end_title.max_lines_visible = 3
	col.add_child(_end_title)
	_end_sub = U.label("", "m", "muted")
	col.add_child(_end_sub)


## Countdown als Ring um das Abspielzeichen auf dem Bild des nächsten Videos.
func _draw_end_ring() -> void:
	var c := _end_ring.size * 0.5
	_end_ring.draw_rect(Rect2(Vector2.ZERO, _end_ring.size), Color(0, 0, 0, 0.32))
	_end_ring.draw_circle(c, 50, Color(UzTheme.col("bg"), 0.55))
	if _end_t > 0.0:
		_end_ring.draw_arc(c, 50, 0, TAU, 64, Color(UzTheme.col("text"), 0.18), 4.0, true)
		var f := clampf(_end_t / _end_total, 0.0, 1.0)
		_end_ring.draw_arc(c, 50, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - f), 64, UzTheme.col("focus"), 4.0, true)
	var s := 15.0
	var pts := PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s * 1.05, 0), c + Vector2(-s * 0.7, s)])
	if Video.has_next() or _end_t <= 0.0:
		_end_ring.draw_colored_polygon(pts, UzTheme.col("text"))


func _build_volume() -> void:
	_vol_box = U.panel("bg", 999, 0, 0.78)
	_vol_box.anchor_left = 1.0
	_vol_box.anchor_right = 1.0
	_vol_box.offset_left = -470
	_vol_box.offset_right = -96
	_vol_box.offset_top = 128
	_vol_box.offset_bottom = 190
	_vol_box.modulate.a = 0.0
	add_child(_vol_box)
	var m := U.margin(24, 12, 26, 12)
	_vol_box.add_child(m)
	var row := U.hbox(16)
	m.add_child(row)
	_vol_ic = U.icon("volume", 28, "text")
	row.add_child(_vol_ic)
	_vol_bar = ProgressBarUz.new().setup(1.0, "accent", 6, 210)
	_vol_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_vol_bar)
	_vol_l = U.label("100", "m", "text", "ui_bold")
	_vol_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # nur eine Zahl
	_vol_l.custom_minimum_size = Vector2(48, 0)
	_vol_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_vol_l)


## Kurzer Hinweis oben in der Mitte (Untertitel, übersprungene Werbung, Qualität).
func _build_notice() -> void:
	_notice = PanelContainer.new()
	var sb := UzTheme.flaeche(Color(UzTheme.col("surface_hi"), 0.94), 999)
	sb.content_margin_left = 22
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	_notice.add_theme_stylebox_override("panel", sb)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.offset_top = 40
	_notice.modulate.a = 0.0
	add_child(_notice)
	var row := U.hbox(12)
	_notice.add_child(row)
	_notice_icon = U.icon("skip", 24, "accent")
	_notice_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_notice_icon)
	_notice_l = U.label("", "m", "text", "ui_bold")
	_notice_l.clip_text = false
	row.add_child(_notice_l)


func notice(text: String, icon := "info", sec := 1.8) -> void:
	# Liegt das Video vorn, zeigt die Leiste in mpv den Hinweis (Uzai liegt dahinter) – schon
	# übersetzt, das Skript in mpv kennt nur fertigen Text.
	Video.osd("notice", [tr(text), sec])
	if not is_instance_valid(_notice):
		return
	_notice_l.text = text
	_notice_icon.texture = Icons.tex(icon, 24)
	_notice_t = sec
	var tw := U.tw(_notice, "uz_notice", Tween.TRANS_QUART).set_parallel(true)
	tw.tween_property(_notice, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_notice, "offset_top", 40.0, U.T_MOVE).from(24.0)


# --- Zustand -----------------------------------------------------------------------------------

func _on_started(v: Dictionary) -> void:
	if v.is_empty() or not is_instance_valid(_title):
		return
	set_meta("uz_flug", "v:" + str(v.get("id", v.get("title", ""))))
	set_meta("uz_flug_art", "aufloesen")
	_title.text = str(v.get("title", ""))
	_fill_channel_row(v)
	_hide_end()
	var showing_backdrop := Video.sim or Video.audio_only
	var short_frame := Video.shorts and Video.sim and not Video.audio_only
	_backdrop.visible = showing_backdrop
	_audio_box.visible = Video.audio_only
	_short_frame.visible = short_frame
	var poster := VideoCard.poster_texture(v)
	_backdrop.texture = poster
	# Shorts hochkant: dahinter nur ein ruhiger, dunkler Schein desselben Bildes.
	_backdrop.modulate = Color(0.32, 0.32, 0.34) if Video.audio_only else (Color(0.3, 0.3, 0.32) if short_frame else Color(0.8, 0.8, 0.82))
	_audio_art.texture = poster
	_short_img.texture = poster
	if short_frame:
		_place_short_frame()
	var url := VideoCard.thumb_url(v)
	if showing_backdrop and url != "":
		var vid := str(v.get("id", ""))
		Media.url_texture(url, 1280, func(t: Texture2D) -> void:
			if t and is_instance_valid(_backdrop) and str(Video.video.get("id", "")) == vid:
				_backdrop.texture = t
				_audio_art.texture = t
				_short_img.texture = t
		)
	if showing_backdrop and Video.shorts:
		_warm_neighbors()
	set_meta("uz_hints", hints_for(Video.shorts, Video.audio_only, Video.video.has("movies")))
	_refresh_hints()
	_update_next()
	show_osc()


## Shorts: Bilder des nächsten und vorigen schon laden, damit beim Blättern gleich das scharfe
## Bild einrastet (sonst kam erst der Farbverlauf und dann, mitten im Gleiten, das Bild).
func _warm_neighbors() -> void:
	for i in [Video.index + 1, Video.index - 1]:
		if i >= 0 and i < Video.queue.size() and Video.queue[i] is Dictionary:
			var u := VideoCard.thumb_url(Video.queue[i])
			if u != "":
				Media.url_texture(u, 1280, func(_t: Texture2D) -> void: pass)


func _fill_channel_row(v: Dictionary) -> void:
	U.clear(_channel_row)
	var ch := str(v.get("channel", ""))
	if ch != "":
		var av := Avatar.new()
		var thumb := str(YouTube.channel_info(str(v.get("channel_id", ""))).get("avatar", ""))
		if v.get("twitch") is Dictionary:
			thumb = str(v.twitch.get("avatar", ""))
		av.setup(ch, thumb, "", 36)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_channel_row.add_child(av)
		var cl := U.label(ch, "m", "text", "medium")
		cl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Kanals
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_channel_row.add_child(cl)
	var parts := PackedStringArray()
	var vt := YouTube.views_text(int(v.get("views", 0)))
	if vt != "":
		parts.append(vt)
	if int(v.get("published", 0)) > 0:
		parts.append(U.ago(int(v.published)))
	# Twitch (Streams): Kategorie und Zuschauer statt Aufrufen.
	if v.get("twitch") is Dictionary and str(v.get("info", "")) != "":
		parts = PackedStringArray([str(v.info)])
	if not parts.is_empty():
		var ml := U.label(("·  " if ch != "" else "") + "  ·  ".join(parts), "m", "muted")
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_channel_row.add_child(ml)


func _update_next() -> void:
	if not is_instance_valid(_next_box):
		return
	_next_box.visible = Video.has_next()
	if not Video.has_next():
		return
	var nv: Dictionary = Video.queue[Video.index + 1]
	_next_title.text = str(nv.get("title", ""))
	_next_poster.texture = VideoCard.poster_texture(nv)
	var url := VideoCard.thumb_url(nv)
	if url != "":
		var nid := str(nv.get("id", ""))
		Media.url_texture(url, 480, func(t: Texture2D) -> void:
			if t and is_instance_valid(_next_poster) and Video.has_next() and str(Video.queue[Video.index + 1].get("id", "")) == nid:
				_next_poster.texture = t
		)


func _on_state() -> void:
	if not is_instance_valid(_bar):
		return
	_bar.queue_redraw()
	_center.queue_redraw()
	_time_l.text = YouTube.time_text(Video.pos)
	_left_l.text = left_text(Video.pos, Video.duration)
	if is_instance_valid(_ut_l) and _ut_l.visible != Video.subs:
		_ut_l.visible = Video.subs
	_center_icon.visible = Video.paused and not Video.loading and not Video.at_end
	_ends_l.text = ends_text(Video.duration - Video.pos, Video.speed, Video.paused) if Video.duration > 0 and not Video.at_end else ""
	if Video.is_live():
		# Live (Twitch): kein Ende, keine Länge.
		_time_l.text = "LIVE"
		_time_l.add_theme_color_override("font_color", UzTheme.col("danger"))
		_left_l.text = ""
		_ends_l.text = "Pausiert" if Video.paused else "Live"
	elif _time_l.has_theme_color_override("font_color"):
		_time_l.remove_theme_color_override("font_color")
	if _end_box.visible:
		return
	var hint_a := "Weiter" if Video.paused else "Pause"
	if str(_pad.get_meta("uz_hint_a", "")) != hint_a:
		_pad.set_meta("uz_hint_a", hint_a)
		_refresh_hints()


## „Endet um 11:42“ – wann das Video zu Ende ist (bei Pause: „Pausiert“).
static func ends_text(left: float, speed: float, paused: bool) -> String:
	if paused:
		return "Pausiert"
	var t := Time.get_unix_time_from_system() + maxf(left, 0.0) / maxf(speed, 0.1)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(t) + bias)
	if Config.get_value("theme.clock_24h", true):
		return "Endet um %02d:%02d" % [d.hour, d.minute]
	var h: int = d.hour % 12
	return "Endet um %d:%02d %s" % [12 if h == 0 else h, d.minute, "PM" if d.hour >= 12 else "AM"]


## Läuft ein Film oder eine Folge aus „Filme“? Dann kommen nächste Folge und Countdown aus Movies.
func _film() -> bool:
	return Video.video.has("movies") and not Movies.now_playing().is_empty()


func _film_next() -> Dictionary:
	var np := Movies.now_playing()
	if np.is_empty() or str((np.meta as Dictionary).get("type", "")) != "series":
		return {}
	return Movies.next_episode(np.meta, str(np.video_id))


func _on_end() -> void:
	if _film():
		_on_film_end()
		return
	# Shorts: gleich das nächste, ohne Karte und Countdown (wie beim Blättern).
	if Video.shorts and Video.has_next():
		_short_dir = 1
		_play_next()
		return
	var autoplay := Video.has_next() and bool(Config.get_value("youtube.autoplay", true))
	_end_total = 8.0
	_end_t = _end_total if autoplay else -1.0
	_show_end_card()
	Video.osd("endcard", [str((Video.queue[Video.index + 1] as Dictionary).get("title", "")) if Video.has_next() else "", _end_t])
	if autoplay:
		_set_end_hints("Jetzt abspielen", "Abbrechen")
	elif Video.has_next():
		_set_end_hints("Nächstes Video", "Beenden")
	else:
		_set_end_hints("Nochmal ansehen", "Beenden")
	show_osc()


## Ende eines Films oder einer Folge: nächste Folge mit Countdown (startet Movies selbst) oder Schluss.
func _on_film_end() -> void:
	var nxt := _film_next()
	var left := Movies.autoplay_left()
	_end_total = maxf(left, 1.0) if left >= 0.0 else 8.0
	_end_t = left if left >= 0.0 and not nxt.is_empty() else -1.0
	var np := Movies.now_playing()
	_end_kind.text = "Nächste Folge" if not nxt.is_empty() else "Zu Ende"
	_end_title.text = ("S%d F%d  ·  %s" % [int(nxt.get("season", 0)), int(nxt.get("episode", 0)), str(nxt.get("title", ""))]) if not nxt.is_empty() else str(
			Video.video.get("title", ""))
	_film_sub = str((np.get("meta", {}) as Dictionary).get("name", ""))
	_end_sub.text = _film_sub
	_end_poster.texture = VideoCard.poster_texture(Video.video)
	_end_art.texture = null
	_end_box.visible = true
	_next_box.visible = false
	_end_box.modulate.a = 0.0
	var tw := U.tw(_end_box, "uz_end", Tween.TRANS_QUART).set_parallel(true)
	tw.tween_property(_end_box, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_end_box, "scale", Vector2.ONE, U.T_ENTER).from(Vector2.ONE * 0.97)
	_end_box.pivot_offset = _end_box.size * 0.5
	_end_ring.queue_redraw()
	Video.osd("endcard", [_end_title.text if not nxt.is_empty() else "", _end_t])
	if _end_t > 0.0:
		_set_end_hints("Jetzt abspielen", "Abbrechen")
	elif not nxt.is_empty():
		_set_end_hints("Nächste Folge", "Beenden")
	else:
		_set_end_hints("Nochmal ansehen", "Beenden")
	show_osc()


var _film_sub := ""


func _show_end_card() -> void:
	var nv: Dictionary = Video.queue[Video.index + 1] if Video.has_next() else Video.video
	_end_kind.text = "Als Nächstes" if Video.has_next() else "Video zu Ende"
	_end_title.text = str(nv.get("title", ""))
	_end_sub.text = str(nv.get("channel", ""))
	_end_poster.texture = VideoCard.poster_texture(nv)
	_end_art.texture = null
	var url := VideoCard.thumb_url(nv)
	if url != "":
		Media.url_texture(url, 480, func(t: Texture2D) -> void:
			if t and is_instance_valid(_end_art):
				_end_art.texture = t
		)
	_end_box.visible = true
	_next_box.visible = false
	_end_box.modulate.a = 0.0
	var tw := U.tw(_end_box, "uz_end", Tween.TRANS_QUART).set_parallel(true)
	tw.tween_property(_end_box, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_end_box, "scale", Vector2.ONE, U.T_ENTER).from(Vector2.ONE * 0.97)
	_end_box.pivot_offset = _end_box.size * 0.5
	_end_ring.queue_redraw()


func _set_end_hints(a: String, b: String) -> void:
	_pad.set_meta("uz_hint_a", a)
	set_meta("uz_hint_b", b)
	_refresh_hints()


func _hide_end() -> void:
	Video.osd("endcard_hide")
	if is_instance_valid(_end_box):
		_end_box.visible = false
	if is_instance_valid(_next_box):
		_next_box.visible = Video.has_next()
	_end_t = 0.0
	set_meta("uz_hint_b", "Beenden")
	if is_instance_valid(_pad):
		_pad.set_meta("uz_hint_a", "Weiter" if Video.paused else "Pause")
		_refresh_hints()


func _on_skipped(t: String) -> void:
	notice(tr("%s übersprungen  ·  links: zurück") % tr(t), "skip", 4.0)


func _exit_tree() -> void:
	for pair in [[Video.changed, _on_state], [Video.started, _on_started], [Video.reached_end, _on_end], [Video.stopped, _on_stopped],
			[Video.skipped, _on_skipped], [Video.volume_changed, _show_volume]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if main and main.hint_bar:
		main.hint_bar.get_parent().visible = true


func _on_stopped() -> void:
	if not _closing:
		close()
		if main:
			main.on_video_closed()


func _process(dt: float) -> void:
	_spin = fposmod(_spin + dt * 5.5, TAU)
	if Video.loading:
		_center.queue_redraw()
	if _osc_t > 0.0 and not Video.paused and not Video.loading and not Video.at_end:
		_osc_t -= dt
		if _osc_t <= 0.0:
			_set_osc(false)
	if _seek_hold > 0.0:
		_seek_hold -= dt
		if _seek_hold <= 0.0:
			U.tw(self, "uz_seek").tween_method(_set_seek_t, _seek_t, 0.0, U.T_MOVE)
	if _notice_t > 0.0:
		_notice_t -= dt
		if _notice_t <= 0.0:
			U.tw(_notice, "uz_notice").tween_property(_notice, "modulate:a", 0.0, U.T_MOVE)
	if _vol_t > 0.0:
		_vol_t -= dt
		_vol_box.modulate.a = clampf(_vol_t / 0.4, 0.0, 1.0)
	if _audio_box.visible:
		_level_t += dt
		_levels.queue_redraw()
	if _end_box.visible and _end_t > 0.0:
		_end_t -= dt
		var left := ceili(maxf(_end_t, 0.0))
		if _film():
			# Den Start übernimmt Movies (gleiche Quelle wie zuletzt), hier nur die Anzeige.
			_end_sub.text = "%s  ·  startet in %d s" % [_film_sub, left]
			_end_ring.queue_redraw()
		else:
			_end_sub.text = "%s  ·  startet in %d s" % [str((Video.queue[Video.index + 1] as Dictionary).get("channel", "")) if Video.has_next() else "", left]
			_end_ring.queue_redraw()
			if _end_t <= 0.0:
				_play_next()
	# Liegt etwas darüber (Guide, Optionen): Leiste, Titel und Uhr des Players weg. Früher schienen
	# beim Guide über einem pausierten Video Titel, Balken und „Als Nächstes“ rund um die Karte durch,
	# und kurz standen zwei Uhren übereinander.
	var covered := Nav.top_layer() != self
	if is_instance_valid(_osc) and _osc.visible == covered:
		_osc.visible = not covered
	if is_instance_valid(_head) and _head.visible == covered:
		_head.visible = not covered
	if Engine.get_process_frames() % 30 == 0 and is_instance_valid(_clock):
		_clock.text = U.clock()


func show_osc() -> void:
	_osc_t = 3.5
	_set_osc(true)
	Video.osd("show", [3.5])


## Die Leiste kommt W_ORT von unten (Titel und Zeitleiste gleiten, die Uhr oben steht) in T_ORT
## mit „Ankommen“ und geht in T_WEG mit „Gehen“ – nichts springt, nichts wartet.
func _set_osc(on: bool) -> void:
	if not is_instance_valid(_osc):
		return
	if on and _osc_on and _osc.modulate.a > 0.99:
		return
	_osc_on = on
	var tw := (U.ankommen(_osc, U.T_ORT, "uz_osc") if on else U.weg(_osc, "uz_osc")).set_parallel(true)
	tw.tween_property(_osc, "modulate:a", 1.0 if on else 0.0, U.T_ORT if on else U.T_WEG)
	if is_instance_valid(_foot):
		var w := U.weg_px(U.W_ORT)
		var ziel := 0.0 if on else w * 0.5
		tw.tween_property(_foot, "offset_top", ziel, U.T_ORT if on else U.T_WEG)
		tw.tween_property(_foot, "offset_bottom", ziel, U.T_ORT if on else U.T_WEG)
		if on and _foot.offset_top < 1.0:
			_foot.offset_top = w
			_foot.offset_bottom = w
	if main and main.hint_bar:
		main.hint_bar.get_parent().visible = on


func _refresh_hints() -> void:
	if main and main.hint_bar:
		main.hint_bar.refresh()


func _set_seek_t(v: float) -> void:
	_seek_t = v
	if is_instance_valid(_bar):
		_bar.queue_redraw()


# --- Steuerung ---------------------------------------------------------------------------------

func _seek(dir: int, big := false) -> void:
	if Video.is_live():
		notice("Live – hier gibt es nichts zu spulen", "live", 1.4)
		show_osc()
		return
	var now := Time.get_ticks_msec()
	_seek_streak = _seek_streak + 1 if now - _last_seek < 450 else 0
	_last_seek = now
	var step := 60.0 if big else (10.0 if _seek_streak < 6 else 30.0)
	Video.seek(step * dir)
	_seek_text = ("+" if dir > 0 else "−") + ("%d s" % int(step) if step < 60 else "1 Min.")
	_seek_hold = 1.2
	Video.osd("seek", [tr(_seek_text)])
	if _seek_t < 0.99:
		U.tw(self, "uz_seek", Tween.TRANS_CUBIC).tween_method(_set_seek_t, _seek_t, 1.0, U.T_FOCUS)
	show_osc()


func _volume(dir: int) -> void:
	var before := Video.volume_level()
	var now := Video.volume(Video.VOLUME_STEP * dir)
	# Leise: nur am Anschlag (0 oder 130 %) ein kurzer Ton, sonst nichts über dem Video.
	if now == before:
		Sfx.play("bump")


## Pegel kurz oben rechts zeigen (Uzai darüber, Demo). Liegt mpv vorn, zeigt ihn Uzais Leiste in
## mpv (Video.set_volume schickt ihn mit). Kommt auch aus dem Guide und den Optionen.
func _show_volume(level: int) -> void:
	# Liegt etwas darüber (Guide, Optionen), zeigt das seinen eigenen Pegel.
	if not is_instance_valid(_vol_box) or Nav.top_layer() != self:
		return
	_vol_bar.set_value(float(level) / float(Video.VOLUME_MAX))
	_vol_l.text = str(level)
	_vol_ic.texture = Icons.tex("volume_down" if level == 0 else "volume", 28)
	_vol_t = 1.4
	_vol_box.modulate.a = 1.0


## Richtungen kommen direkt hierher (Nav.nav_dir), egal wo der Fokus steht: hoch/runter ist immer
## die Lautstärke, links/rechts spult. Die unsichtbare Fläche bekommt den Fokus still zurück.
func nav_dir(dir: String) -> bool:
	if is_instance_valid(_pad) and Nav.focused() != _pad and _pad.is_visible_in_tree():
		_pad.grab_focus()
	match dir:
		"up":
			if Video.shorts:
				_short_step(-1)
			else:
				_volume(1)
		"down":
			if Video.shorts:
				_short_step(1)
			else:
				_volume(-1)
		"left":
			# Eben einen Abschnitt übersprungen: links führt an seinen Anfang zurück.
			if Video.undo_skip():
				notice("Zurück zum Abschnitt", "rewind", 1.6)
				show_osc()
			else:
				_seek(-1)
		"right":
			_seek(1)
		_:
			return false
	return true


## Shorts blättern: d = 1 das nächste, -1 das davor; am Rand stößt es leise an.
func _short_step(d: int) -> void:
	if (d > 0 and not Video.has_next()) or (d < 0 and not Video.has_prev()):
		Sfx.play("bump")
		notice("Keine weiteren Shorts" if d > 0 else "Das ist der erste Short", "video", 1.4)
		return
	# Ein Schritt rastet erst ein; dicht folgende (gehaltener Stick, Tastenwiederholung) zählen nicht.
	var now := Time.get_ticks_msec()
	if now - _short_at < SHORT_GAP_MS:
		return
	_short_at = now
	Sfx.play("tick", 1.0 + 0.06 * d)
	_short_dir = d
	# Das bisherige Bild bleibt als zweiter Rahmen stehen und gleitet hinaus (_place_short_frame).
	if is_instance_valid(_short_frame) and _short_frame.visible and _short_img.texture:
		_short_ghost_img.texture = _short_img.texture
		_short_ghost.modulate.a = 1.0
		_short_ghost.visible = true
	# mpv vorn: dort zeigt Uzais Leiste das Einrasten (Video schickt „swipe“ mit dem Laden).
	_hide_end()
	if d > 0:
		Video.next()
	else:
		Video.prev()
	show_osc()


func _play_next() -> void:
	_hide_end()
	Video.next()


func activate_pad() -> void:
	if Video.at_end and _film():
		_hide_end()
		if not _film_next().is_empty():
			var err: Variant = await Movies.play_next()
			if str(err) != "":
				notice(str(err), "warning", 2.4)
		else:
			Video.seek_to(0.0)
			Video.set_pause(false)
		return
	if Video.at_end:
		if Video.has_next():
			_play_next()
		else:
			_hide_end()
			Video.seek_to(0.0)
			Video.set_pause(false)
		return
	Video.toggle_pause()
	Sfx.play("select")
	show_osc()


func nav_command(cmd: String) -> bool:
	match cmd:
		"b":
			if _end_box.visible and _end_t > 0.0 and _film():
				Movies.cancel_autoplay()
				_end_t = -1.0
				_end_sub.text = _film_sub + "  ·  angehalten"
				Video.osd("endcard", [_end_title.text, -1])
				_end_ring.queue_redraw()
				_set_end_hints("Nächste Folge", "Beenden")
				Sfx.play("back")
				return true
			if _end_box.visible and _end_t > 0.0:
				# Countdown abbrechen: die Karte bleibt, aber nichts startet von selbst.
				_end_t = -1.0
				_end_sub.text = str((Video.queue[Video.index + 1] as Dictionary).get("channel", "")) + "  ·  angehalten" if Video.has_next() else ""
				Video.osd("endcard", [str((Video.queue[Video.index + 1] as Dictionary).get("title", "")) if Video.has_next() else "", -1])
				_end_ring.queue_redraw()
				_set_end_hints("Nächstes Video" if Video.has_next() else "Nochmal ansehen", "Beenden")
				Sfx.play("back")
				return true
			Sfx.play("back")
			Video.stop()
			return true
		"lt":
			if Video.shorts:
				_volume(-1)
			else:
				_seek(-1, true)
			return true
		"rt":
			if Video.shorts:
				_volume(1)
			else:
				_seek(1, true)
			return true
		"lb":
			Video.prev()
			show_osc()
			return true
		"rb":
			if _film() and not _film_next().is_empty():
				# Film: nächste Folge über Movies (gleiche Quelle wie zuletzt).
				_hide_end()
				Movies.play_next()
			elif Video.has_next():
				_play_next()
			else:
				notice("Kein weiteres Video in der Liste", "video", 1.6)
			return true
		"x":
			Video.set_subs(not Video.subs)
			notice("Untertitel an" if Video.subs else "Untertitel aus", "subtitles", 1.6)
			show_osc()
			return true
		"y":
			_open_options()
			return true
		"menu":
			if Video.audio_only and not _film():
				to_background()
			else:
				to_pip()
			return true
		"a":
			# Kommt nur hier an, wenn der Fokus gerade nicht auf dem Player liegt (sonst _Pad.activate).
			if is_instance_valid(_pad):
				_pad.grab_focus()
			activate_pad()
			return true
		"guide":
			return false
	return false


func _open_options() -> void:
	show_osc()
	# Spuren vorher holen (ein kurzer Steuerbefehl an mpv), damit die Liste gleich vollständig ist.
	await Video.load_tracks()
	if _closing or not is_inside_tree():
		return
	var s = Sheet.new()
	s.setup("Wiedergabe", str(Video.video.get("title", "")), 820)
	s.subheading_raw = true      # Titel des Videos
	s.set_header_image(VideoOptions.thumb_box(Video.video, Vector2(176, 99)))
	s.fill_func = func(sheet) -> void:
		# Trailer aus dem Shop (direkte Adresse): keine YouTube-Qualitätsstufen, nichts zum Merken.
		var direct := Video.is_direct(Video.video)
		# Lautstärke des Videos (mpv), dieselbe Stufe wie hoch/runter im Player und LT/RT im Guide.
		var vol = SettingRow.new()
		vol.setup("slider", "Lautstärke", "", float(Video.volume_level()))
		vol.icon_name = "volume"
		vol.min_v = 0.0
		vol.max_v = float(Video.VOLUME_MAX)
		vol.step = float(Video.VOLUME_STEP)
		vol.fmt = "%d %%"
		vol.fmt_scale = 1.0
		vol.changed.connect(func(v: Variant) -> void: Video.set_volume(int(round(float(v)))))
		sheet.add_row(vol)
		var q = SettingRow.new()
		q.setup("choice", "Qualität", "", "ton" if Video.audio_only else Video.quality)
		q.icon_name = "quality"
		q.options = [["720", "720p"], ["1080", "1080p"], ["1440", "1440p"], ["2160", "4K"], ["ton", "Nur Ton"]]
		q.changed.connect(func(v: Variant) -> void:
			if str(v) == "ton":
				Video.set_audio_only(true)
			else:
				Video.set_quality(str(v))
			main.video_mode_changed()
			_on_started(Video.video)
			notice("Nur Ton" if str(v) == "ton" else "Qualität: " + ("4K" if str(v) == "2160" else str(v) + "p"), "quality", 1.6)
		)
		if not direct or Video.video.has("twitch"):
			sheet.add_row(q)
		# Mehrere Tonspuren (Filme): Sprache wählen. Untertitel: welche Spur, sonst nur an/aus.
		var audio := Video.track_options(Video.tracks, "audio")
		if audio.size() > 1:
			var at = SettingRow.new()
			at.setup("choice", "Tonspur", "", Video.selected_track(Video.tracks, "audio"))
			at.icon_name = "speaker"
			at.options = audio
			at.changed.connect(func(v: Variant) -> void:
				Video.set_track("audio", v)
				notice("Tonspur: " + _option_label(audio, v), "speaker", 1.6)
			)
			sheet.add_row(at)
		var subs := Video.track_options(Video.tracks, "sub")
		var sub = SettingRow.new()
		if subs.size() > 1:
			sub.setup("choice", "Untertitel", "", Video.selected_track(Video.tracks, "sub"))
			sub.options = subs
			sub.changed.connect(func(v: Variant) -> void:
				Video.set_track("sub", v)
				notice("Untertitel: " + _option_label(subs, v), "subtitles", 1.6)
			)
		else:
			sub.setup("toggle", "Untertitel", "", Video.subs)
			sub.changed.connect(func(v: Variant) -> void: Video.set_subs(bool(v)))
		sub.icon_name = "subtitles"
		sheet.add_row(sub)
		var sp = SettingRow.new()
		sp.setup("choice", "Geschwindigkeit", "", Video.speed)
		sp.icon_name = "speed"
		sp.options = [[0.75, "0,75×"], [1.0, "Normal"], [1.25, "1,25×"], [1.5, "1,5×"], [1.75, "1,75×"], [2.0, "2×"]]
		sp.changed.connect(func(v: Variant) -> void: Video.set_speed(float(v)))
		sheet.add_row(sp)
		# Schlaf-Timer (src/core/schlaf_timer.gd): nach Zeit oder am Ende dieser Folge in den Ruhemodus.
		var st: Node = main.rest.schlaf if main and main.rest != null else null
		if st:
			var sl = SettingRow.new()
			sl.setup("choice", "Schlaf-Timer", "", st.stufe)
			sl.icon_name = "clock"
			sl.options = st.optionen(true, st.art())
			sl.changed.connect(func(v: Variant) -> void: st.setzen(str(v)))
			sheet.add_row(sl)
		var later = SettingRow.new()
		later.setup("toggle", "Merken", "", YouTube.in_later(str(Video.video.get("id", ""))))
		later.icon_name = "bookmark"
		later.changed.connect(func(_v: Variant) -> void: YouTube.toggle_later(Video.video))
		# Filme: nichts zum Merken oder Abonnieren (das ist YouTube).
		var film := Video.video.has("movies")
		if not direct and not film:
			sheet.add_row(later)
		var cid := str(Video.video.get("channel_id", ""))
		if cid != "" and not film:
			var ab = SettingRow.new()
			ab.setup("toggle", "Kanal abonnieren", "", YouTube.is_subscribed(cid))
			ab.icon_name = "plus"
			ab.changed.connect(func(v: Variant) -> void:
				if v:
					YouTube.subscribe(cid, str(Video.video.get("channel", "")))
				else:
					YouTube.unsubscribe(cid)
			)
			sheet.add_row(ab)
		var link = SettingRow.new()
		link.setup("action", "Link aufs Handy", "")
		link.icon_name = "qr"
		link.value_text = "QR-Code"
		link.on_activate = func() -> void:
			var qv = VideoQr.new()
			qv.video = Video.video
			main.open_layer(qv)
		if not film:
			sheet.add_row(link)
		# Nur Ton wie Musik weiterhören, während du in Uzai woanders bist (Filme bleiben im Player).
		if not film and not Video.pip:
			var bg = SettingRow.new()
			bg.setup("action", "Im Hintergrund weiterhören", "")
			bg.icon_name = "music"
			bg.subtitle = "Nur Ton, wie Musik – steuern im Guide"
			bg.on_activate = func() -> void:
				sheet.close()
				to_background()
			sheet.add_row(bg)
		if not Video.audio_only:
			var pp = SettingRow.new()
			pp.setup("action", "Bild in Bild", "")
			pp.icon_name = "pip"
			pp.subtitle = "Klein in der Ecke weiterschauen, auch beim Spielen"
			pp.on_activate = func() -> void:
				sheet.close()
				to_pip()
			sheet.add_row(pp)
		if not Video.segments.is_empty():
			sheet.add_gap()
			var names := PackedStringArray()
			for seg in Video.segments:
				names.append("%s (%s)" % [TranslationServer.translate(YouTube.category_name(str(seg.category))), YouTube.time_text(float(seg.start))])
			sheet.add_label("SponsorBlock überspringt hier: " + ", ".join(names), "s", "faint")
	main.open_layer(s)


static func _option_label(opts: Array, v: Variant) -> String:
	for o in opts:
		if str(o[0]) == str(v):
			return str(o[1])
	return ""


## Nur Ton im Hintergrund: Bild aus, Player zu, der Ton läuft weiter (main.video_to_background).
func to_background() -> void:
	if _closing or main == null:
		return
	if not Video.to_background():
		notice("Das geht nur bei Videos", "music", 1.8)
		return
	Sfx.play("select")
	close()
	main.video_to_background()


## Bild in Bild: Das Video schrumpft in die Ecke und läuft weiter, Uzai steht dahinter wieder dort,
## wo du vor dem Video warst – von da aus startest du ein Spiel (src/core/pip.gd).
func to_pip() -> void:
	if _closing or main == null or main.pip == null:
		return
	if Video.audio_only:
		notice("Bei „Nur Ton“ gibt es kein Bild", "pip", 1.8)
		return
	Sfx.play("select")
	close()
	main.on_video_closed()
	main.pip.enter()


## Unsichtbares Steuerelement, das alle Richtungen und A an den Player weitergibt.
class _Pad extends Control:
	var player: Node

	func nav_lr(d: int) -> bool:
		return player.nav_dir("left" if d < 0 else "right")

	func nav_ud(d: int) -> bool:
		return player.nav_dir("up" if d < 0 else "down")

	func activate() -> void:
		player.activate_pad()

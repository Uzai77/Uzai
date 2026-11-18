extends Control
## Eine Karte in „Für dich“ (Seitenleiste auf Start, fuer_dich_leiste.gd), gebaut wie die
## Aktivitätskarten von PS5 und Xbox: oben eine große mit Bild, darunter kleinere. Jede Karte ist ein Knopf: A führt direkt hin
## (data.act), Y bei Spielen zur Spielseite.
##
## Ruhend: Bild bzw. dunkles Farbfeld in der Farbe des Spiels, weiche Höhe (Stufe 1), links unten
## dunkler auslaufend für die Schrift. Gewählt: hebt sich um 8 px, heller Ring mit zartem Goldband
## und Glimmen, ein Lichtstreif zieht einmal darüber (wie Cover und Kacheln, docs/DESIGN.md).
## Die Schrift liegt immer auf Bild oder dunklem Feld – darum feste helle Farben, auch auf „Papier“.
## Matt (Marke, Graphit): keine Kontur – Tiefe über Fläche, weichen Schatten und eine feine
## Lichtkante oben (Premium-Durchgang); gewählt hebt sich die Karte, der Schatten wird tiefer, und
## sie trägt den einen Cursor der Kacheln (feine Lichtkante, weicher Schein, UzTheme.draw_tile_focus).
## Kein Lichtstreif. Bilder kommen nur über Media (kein Zurücklesen von der Grafikkarte).

const U := preload("res://src/ui/u.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const MovieArt := preload("res://src/ui/components/movie_art.gd")
const BG := preload("res://src/ui/components/background.gd")

const INK := Color("#f3f1ec")
const INK_SOFT := Color(0.953, 0.945, 0.925, 0.74)
const GROUND := Color("#15161a")
const LIFT := 8.0
const THUMB := Vector2(102, 136)   ## Cover rechts in der großen Karte (höchstens)

var data: Dictionary = {}
var big := false
var on_down: Callable           ## runter aus der unteren Reihe: zu den Quellen
## Leiser Fokus (Seitenleiste „Für dich“): gewählt ein weicher Schein im Akzent und eine hellere
## Lichtkante oben statt des Rings der Kacheln – kein heller Rahmen in der ruhigen Leiste.
var leise := false
var _w := 540.0
var _h := 200.0
var _r := 22
var _frame: Control
var _clip: Panel
var _ground: ColorRect
var _img: TextureRect
var _im_bau := false             ## Bild kommt noch im Aufbau (aus dem Speicher): steht sofort
var _thumb: Control
var _over: Control
var _lift := 0.0
var _matt := false


func setup(d: Dictionary, is_big: bool, sz: Vector2) -> Control:
	data = d
	big = is_big
	_w = sz.x
	_h = sz.y
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(_w, _h)
	_matt = UzTheme.matt()
	_r = UzTheme.r_panel() if UzTheme.strict() else maxi(8, UzTheme.r_panel() - (4 if big else 8))
	set_meta("uz_hint_a", str(data.get("hint", "Öffnen")))
	set_meta("uz_key", "fy:" + str(data.get("kind", "")))
	add_to_group("uz_fuer_dich")     # Mitteilungen weichen aus (toasts.gd, _meiden)
	var fg: Dictionary = data.get("game", {})
	if not fg.is_empty():
		# Geteilte Elemente (src/ui/flug.gd): das Cover der Karte fliegt in die Hülle der Spielseite.
		set_meta("uz_flug", "g:" + str(fg.get("id", "")))
	# Lichtstreif nur, wo das Theme ihn will (Graphit: focus.shine = false).
	if not _matt and UzTheme.focus_shine():
		set_meta("uz_shiny", true)
	var ya: Variant = data.get("y_act")
	if ya is Callable and (ya as Callable).is_valid():
		set_meta("uz_hint_y", str(data.get("y_hint", "Optionen")))
		set_meta("uz_on_y", ya)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_frame)
	add_child(_frame)
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(GROUND, _r))
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_clip)
	_frame.add_child(_clip)
	_ground = ColorRect.new()
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.color = _tint()
	U.full_rect(_ground)
	_clip.add_child(_ground)
	_game_tint()
	if not _matt:
		_clip.add_child(_Glow.new())
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.modulate.a = 0.0
	U.full_rect(_img)
	_clip.add_child(_img)
	var scrim := _Scrim.new()
	scrim.big = big
	U.full_rect(scrim)
	_clip.add_child(scrim)
	if big:
		_build_thumb()
	_frame.add_child(_content())
	_over = _Over.new()
	_over.card = self
	_over.radius = _r
	U.full_rect(_over)
	_frame.add_child(_over)
	_im_bau = true
	_load_image()
	_im_bau = false
	resized.connect(_on_resized)
	focus_entered.connect(func() -> void:
		U.focus_anim(self, true)
		_lift_to(-U.weg_px(LIFT))
	)
	focus_exited.connect(func() -> void:
		U.focus_anim(self, false)
		_lift_to(0.0)
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func nav_ud(d: int) -> bool:
	if d > 0 and on_down.is_valid():
		return bool(on_down.call())
	return false


func activate() -> void:
	var cb: Variant = data.get("act")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


## Geteilte Elemente (src/ui/flug.gd): das scharfe Cover rechts in der großen Karte fliegt in die
## Hülle der Spielseite und beim Schließen zurück. Zeigt die Karte ein breites Bild (anderes
## Motiv), fliegt nichts – die Seite blendet wie immer.
func flug_bild() -> Dictionary:
	if _thumb == null or not is_instance_valid(_thumb) or not _thumb.visible or not _thumb.has_meta("tex"):
		return {}
	var ct: TextureRect = _thumb.get_meta("tex")
	if ct == null or not is_instance_valid(ct) or ct.texture == null:
		return {}
	return { "node": ct, "radius": UzTheme.rund(12), "hide": _thumb }


## Die Karte kommt an (erster Aufbau, Tausch): sie steigt W_ANSTOSS von unten an ihren Platz,
## während sie einblendet (Takt „Ankommen“, T_ORT, nach verz). Ruhig: sie steht gleich.
func ankunft(verz := 0.0) -> void:
	var von := U.weg_px(U.W_ANSTOSS)
	if von <= 0.0 or not is_inside_tree():
		return
	_set_lift(von)
	var tw := U.ankommen(self, U.T_ORT, "uz_lift")
	if verz > 0.0:
		tw.tween_interval(verz)
	tw.tween_method(_set_lift, von, 0.0, U.T_ORT)


# --- Inhalt -------------------------------------------------------------------------------

## Text links (Grund als Pille oben, Titel und Zusatz unten), rechts das Bild der Art:
## Gesichter, Säulen der Woche oder (große Karte ohne breites Bild) das Cover.
func _content() -> Control:
	var m := U.margin(24, 20, 24, 20) if big else U.margin(18, 14, 16, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(m)
	var row := U.hbox(16)
	m.add_child(row)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var side := _side()
	var top := U.hbox(10)
	col.add_child(top)
	var room := _w - (48.0 if big else 34.0)
	if side != null and not big:
		room -= side.custom_minimum_size.x + 10.0
	top.add_child(_why_pill(room))
	if side != null and not big:
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(gap)
		side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(side)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fill)
	# Breite der Schrift in der großen Karte: was rechts steht (Gesichter, Säulen, Cover) bleibt frei.
	var text_w := _w * 0.66
	if big and side != null:
		text_w = _w - 48.0 - side.custom_minimum_size.x - 16.0
	elif big and _thumb != null:
		text_w = _w - 48.0 - THUMB.x - 16.0
	var t := U.label(str(data.get("title", "")), "30" if big else "m", "text", "bold", big)
	t.add_theme_color_override("font_color", INK)
	U.shadow(t, 0.5)
	if big:
		t.add_theme_constant_override("line_spacing", -6)
		MovieArt.fit_lines(t, text_w, 2)
	else:
		U.ellipsis(t)
	col.add_child(t)
	var sub := str(data.get("sub_small", data.get("sub", ""))) if not big else str(data.get("sub", ""))
	var s := U.label(sub, "s", "text", "medium")
	s.add_theme_color_override("font_color", INK_SOFT)
	U.shadow(s, 0.4)
	U.ellipsis(s)
	if big:
		s.custom_minimum_size = Vector2(text_w, 0)
	col.add_child(s)
	var frac := float(data.get("frac", -1.0))
	if frac >= 0.0 and data.has("frac"):
		col.add_child(U.spacer(0, 6, false))
		var bar := _Progress.new()
		bar.frac = frac
		bar.color = accent_on_dark()
		bar.custom_minimum_size = Vector2(_w * 0.42 if big else 0.0, 4)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if big else Control.SIZE_EXPAND_FILL
		col.add_child(bar)
	if big and side != null:
		var sc := U.vbox(0)
		sc.alignment = BoxContainer.ALIGNMENT_END
		sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(side)
		row.add_child(sc)
	elif big and _thumb != null:
		# Platz für das Cover rechts (falls es kein breites Bild gibt), damit der Titel nicht darunter läuft.
		row.add_child(U.spacer(int(THUMB.x), 0, false))
	return m


## Was rechts steht: Gesichter (Freunde, Sprachkanal) oder die Säulen der Woche.
func _side() -> Control:
	var people: Array = data.get("people", [])
	if not people.is_empty():
		var faces := U.hbox(-10)
		faces.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Klein mit Spiel (Freund spielt gerade) nur das eine Gesicht: sonst wird der Grund gekürzt.
		var shown := people.slice(0, 4 if big else (1 if data.has("game") else 3))
		var px := 40 if big else 26
		for p in shown:
			var f := _Face.new()
			f.who = str((p as Dictionary).get("name", "?"))
			f.url = str((p as Dictionary).get("avatar", ""))
			f.px = px
			f.custom_minimum_size = Vector2(px + 6, px + 6)
			faces.add_child(f)
		faces.custom_minimum_size = Vector2(shown.size() * (px + 6) - (shown.size() - 1) * 10, px + 6)
		return faces
	var bars: Array = data.get("bars", [])
	if not bars.is_empty():
		var b := _Bars.new()
		b.values = bars
		b.labels = data.get("labels", []) if big else []
		b.color = accent_on_dark()
		b.custom_minimum_size = Vector2(196, 104) if big else Vector2(86, 36)
		return b
	return null


## Grund der Empfehlung: kleines dunkles Schild ohne Kontur (ein Etikett auf dem Bild), Symbol und
## Wort im Akzent. Zu lange Gründe („Mira und Jonas spielen gerade“) kürzt sie mit „…“ statt die
## Karte zu sprengen.
func _why_pill(room: float) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(Color(0.02, 0.02, 0.03, 0.62 if _matt else 0.5), 999)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var w := U.hbox(6)
	var acc := accent_on_dark()
	var ic := U.icon(str(data.get("icon", "spark")), 15, "accent")
	ic.modulate = acc
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w.add_child(ic)
	var text := str(data.get("why", ""))
	var l := U.label(text, "cap", "accent", "ui_bold")
	l.add_theme_color_override("font_color", acc)
	var fnt := UzTheme.font("ui_bold")
	var tw := fnt.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("cap")).x + 2.0
	var max_w := maxf(60.0, room - 43.0)
	if tw > max_w:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(max_w, 0)
	else:
		l.clip_text = false
	w.add_child(l)
	p.add_child(w)
	return p


## Akzent als Schrift auf dunklem Grund: zu dunkle Akzente (Papier: Blau) werden heller.
static func accent_on_dark() -> Color:
	var a := UzTheme.col("accent")
	return a if a.get_luminance() >= 0.45 else a.lerp(Color.WHITE, 0.45)


# --- Bild ---------------------------------------------------------------------------------

## Grundfarbe sofort (System, Kanal, Akzent); bei Spielen danach die Farbe des Covers (_game_tint).
func _tint() -> Color:
	var g: Dictionary = data.get("game", {})
	var base := UzTheme.col("accent")
	if not g.is_empty():
		base = Color(str(Config.system(str(g.get("system", ""))).get("color", "#2a2f3a")))
	else:
		match str(data.get("kind", "")):
			"voice": base = UzTheme.col("discord")
			"freunde": base = UzTheme.col("steam")
			"medien": base = UzTheme.col("music") if bool(data.get("music", false)) else Color.from_hsv(MovieArt.hue_of(str(data.get("art_seed", ""))), 0.5, 0.6)
	return GROUND.lerp(base, 0.3)


func _game_tint() -> void:
	var g: Dictionary = data.get("game", {})
	if g.is_empty():
		return
	var wg: WeakRef = weakref(_ground)
	Media.game_tint(g, func(c: Variant) -> void:
		var gr: ColorRect = wg.get_ref()
		if gr and c is Color and gr.is_inside_tree():
			gr.create_tween().tween_property(gr, "color", GROUND.lerp(c as Color, 0.42), 0.4)
	)


## Spiele: große Karte zuerst das Kopfbild, kleine zuerst das breite Bild; ohne beides das Cover
## weich als Grund (große Karte: scharf rechts daneben). Filme und Musik: ihr Bild aus dem Netz.
## Ein Bild aus dem Speicher (noch im Aufbau) steht sofort, eins aus dem Netz kommt in T_ORT.
## Das Bild einer Karte vorab holen (Media behält es): „Für dich“ steht als Seitenleiste hinter
## der Start-Taste und soll beim Öffnen gleich mit Bild dastehen. Dieselbe erste Wahl wie
## _load_image (Ersatzbilder kommen erst beim Aufbau).
static func vorladen(d: Dictionary, is_big: bool) -> void:
	var nichts := func(_t: Texture2D) -> void: pass
	var g: Dictionary = d.get("game", {})
	if g.is_empty():
		var url := str(d.get("art_url", ""))
		if url.begins_with("http"):
			Media.url_texture(url, 920 if is_big else 520, nichts)
		elif url != "":
			Media.file_texture(url, 920 if is_big else 520, nichts)
		return
	Media.game_texture(g, "hero" if is_big else "wide", nichts)


func _load_image() -> void:
	var wi: WeakRef = weakref(_img)
	var me: WeakRef = weakref(self)
	var shown := func(t: Texture2D) -> void:
		var r: TextureRect = wi.get_ref()
		if r and t:
			r.texture = t
			var k: Object = me.get_ref()
			if k and bool(k.get("_im_bau")):
				U.stop(r, "uz_bild")
				r.modulate.a = 1.0
			else:
				U.ankommen(r, U.T_ORT, "uz_bild").tween_property(r, "modulate:a", 1.0, U.T_ORT)
	var g: Dictionary = data.get("game", {})
	if g.is_empty():
		var url := str(data.get("art_url", ""))
		if url.begins_with("http"):
			Media.url_texture(url, 920 if big else 520, shown)
		elif url != "":
			Media.file_texture(url, 920 if big else 520, shown)
		elif str(data.get("art_seed", "")) != "":
			shown.call(MovieArt.backdrop_tex(str(data.art_seed)))
		return
	var wt: WeakRef = weakref(_thumb) if _thumb else null
	var soft_cover := func() -> void:
		Media.game_texture(g, "cover", func(t: Texture2D) -> void:
			if t == null:
				return
			var th: Control = wt.get_ref() if wt else null
			if th:
				th.visible = true
				var ct: TextureRect = th.get_meta("tex")
				ct.texture = t
			Media.soft(t, BG.soft_steps(5.0), func(st: Texture2D) -> void:
				var r: TextureRect = wi.get_ref()
				if r and st:
					r.texture = st
					U.ankommen(r, U.T_ORT, "uz_bild").tween_property(r, "modulate:a", 0.75, U.T_ORT)
			)
		)
	var first := "hero" if big else "wide"
	var second := "wide" if big else "hero"
	Media.game_texture(g, first, func(t: Texture2D) -> void:
		if t:
			shown.call(t)
			return
		Media.game_texture(g, second, func(t2: Texture2D) -> void:
			if t2:
				shown.call(t2)
			else:
				soft_cover.call()
		)
	)


## Cover scharf rechts in der großen Karte – nur, wenn es kein breites Bild gibt. Ohne Bild steht
## das gezeichnete Ersatz-Cover dort (Demo, Spiele ohne Bilder).
func _build_thumb() -> void:
	var g: Dictionary = data.get("game", {})
	if g.is_empty() or not data.get("people", []).is_empty():
		return
	var th := Panel.new()
	th.add_theme_stylebox_override("panel", UzTheme.box(Color(0, 0, 0, 0.3), 12))
	th.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.size = _thumb_size(_h)
	th.position = Vector2(_w - 22.0 - th.size.x, 22.0)
	var art := CoverArt.new()
	art.show_title = false
	art.compact = true
	U.full_rect(art)
	th.add_child(art)
	art.setup(g)
	var ct := TextureRect.new()
	ct.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ct.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(ct)
	th.add_child(ct)
	th.set_meta("tex", ct)
	# Ohne jedes Bild (auch kein Cover) bleibt das Ersatz-Cover sichtbar: erst zeigen, wenn klar ist,
	# dass es kein breites Bild gibt.
	th.visible = false
	_clip.add_child(th)
	_thumb = th
	var wt: WeakRef = weakref(th)
	Media.game_file(g, "hero", func(p: String) -> void:
		if p != "":
			return
		Media.game_file(g, "wide", func(p2: String) -> void:
			var t: Control = wt.get_ref()
			if t and p2 == "":
				t.visible = true
		)
	)


static func _thumb_size(h: float) -> Vector2:
	var th := minf(THUMB.y, h - 44.0)
	return Vector2(roundf(th * 0.75), th)


## Die große Karte nimmt die Höhe, die über dem Regal frei ist (games.gd): Cover rechts mitführen.
func _on_resized() -> void:
	_w = size.x
	_h = size.y
	if _thumb:
		var ts := _thumb_size(_h)
		_thumb.size = ts
		_thumb.position = Vector2(_w - 22.0 - ts.x, 22.0)


# --- Auswahl ------------------------------------------------------------------------------

## Heben (gewählt) im Takt „Ankommen“ (T_ORT), senken mit „Gehen“ (T_WEG); der Ring der Auswahl
## steht derweil schon im ersten Bild (U.focus_anim).
func _lift_to(y: float) -> void:
	var tw := U.ankommen(self, U.T_ORT, "uz_lift") if y < 0.0 else U.weg(self, "uz_lift")
	tw.tween_method(_set_lift, _lift, y, U.T_ORT if y < 0.0 else U.T_WEG)


func _set_lift(y: float) -> void:
	_lift = y
	if _frame:
		_frame.position.y = y
	queue_redraw()


## Schatten unter der Karte (eigene Fläche, nie am zuschneidenden Knoten); gewählt etwas tiefer.
## Auch matt: Der Schatten ist die Tiefe, die die Karte vom Raum trennt (statt einer Kontur).
func _draw() -> void:
	var f: float = get_meta("uz_f", 0.0)
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(_r)
	var sc := UzTheme.col("shadow")
	sh.shadow_color = Color(sc.r, sc.g, sc.b, UzTheme.shadow_alpha(sc.a * (0.3 + 0.16 * f)))
	sh.shadow_size = int(18 + 12 * f)
	sh.shadow_offset = Vector2(0, 8 + 6 * f)
	draw_style_box(sh, Rect2(Vector2(0, _lift), size))
	if leise and f > 0.01:
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(_r)
		glow.shadow_color = Color(UzTheme.col("accent"), 0.30 * minf(f, 1.0))
		glow.shadow_size = 26
		draw_style_box(glow, Rect2(Vector2(0, _lift), size))
	if _over:
		_over.queue_redraw()


## Ring, Goldband und Lichtstreif über der Karte (über Bild und Text).
class _Over extends Control:
	const UU := preload("res://src/ui/u.gd")
	## Deckkraft der Lichtkante oben auf der Karte (auf Bild oder Farbfeld).
	const KANTE_A := 0.11
	var card: Control
	var radius := 18

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if card.get("_matt") == true:
			# Keine Kontur: eine feine Lichtkante oben (Licht von oben, läuft an den Ecken aus),
			# gewählt der eine Cursor der Kacheln (feine Lichtkante rundum, weicher Schein).
			var rad := float(radius)
			var leise: bool = card.get("leise") == true
			var e := Color(1, 1, 1, KANTE_A + (0.16 * minf(card.get_meta("uz_f", 0.0), 1.0) if leise else 0.0))
			if size.x > rad * 4.0:
				draw_polyline_colors(PackedVector2Array([Vector2(rad, 0.5), Vector2(rad * 2.0, 0.5), Vector2(size.x - rad * 2.0, 0.5), Vector2(size.x - rad, 0.5)]),
					PackedColorArray([Color(e, 0.0), e, e, Color(e, 0.0)]), 1.0, true)
			if not leise:
				UzTheme.draw_tile_focus(self, r, radius, minf(card.get_meta("uz_f", 0.0), 1.0))
			return
		if card.has_meta("uz_shine") and UzTheme.focus_shine():
			set_meta("uz_shine", card.get_meta("uz_shine"))
			UU.draw_shine(self, r.grow(-2))
		var f: float = card.get_meta("uz_f", 0.0)
		if f <= 0.01:
			return
		var band := StyleBoxFlat.new()
		band.draw_center = false
		band.set_border_width_all(6)
		band.border_color = Color(UzTheme.col("accent"), 0.24 * minf(f, 1.0))
		band.set_corner_radius_all(radius + 9)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			band.set_expand_margin(side, 9)
		band.anti_aliasing = true
		draw_style_box(band, r)
		draw_style_box(UzTheme.focus_ring(minf(f, 1.0), radius), r)


## Links und unten dunkler, damit Schrift auf jedem Bild lesbar bleibt; oben ein Hauch für die Pille.
class _Scrim extends Control:
	var big := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := size
		var k := 0.0 if big else 0.08
		# Von links (Text) nach rechts (Bild).
		var l0 := Color(0.03, 0.03, 0.04, 0.78 + k)
		var l1 := Color(0.03, 0.03, 0.04, 0.42 + k)
		var l2 := Color(0.03, 0.03, 0.04, 0.0)
		var xm := s.x * (0.45 if big else 0.6)
		var xe := s.x * (0.82 if big else 1.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(xm, 0), Vector2(xm, s.y), Vector2(0, s.y)]), PackedColorArray([l0, l1, l1, l0]))
		draw_polygon(PackedVector2Array([Vector2(xm, 0), Vector2(xe, 0), Vector2(xe, s.y), Vector2(xm, s.y)]), PackedColorArray([l1, l2, l2, l1]))
		# Unten dunkler (Titel, Zusatz).
		var b0 := Color(0.03, 0.03, 0.04, 0.0)
		var b1 := Color(0.03, 0.03, 0.04, 0.55)
		var y0 := s.y * 0.4
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(s.x, y0), Vector2(s.x, s.y), Vector2(0, s.y)]), PackedColorArray([b0, b0, b1, b1]))


## Weiches Licht oben rechts im Farbfeld (wenn noch kein Bild da ist, wirkt die Karte nicht flach).
class _Glow extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * Vector2(0.82, 0.1)
		var rad := size.x * 0.55
		for i in 6:
			var t := float(i) / 6.0
			draw_circle(c, rad * (1.0 - t * 0.8), Color(1, 1, 1, 0.012 + t * 0.008))


## Dünner Fortschrittsbalken (Erfolge, Film).
class _Progress extends Control:
	var frac := 0.0
	var color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(Color(1, 1, 1, 0.2), 2), r)
		if frac > 0.0:
			draw_style_box(UzTheme.box(color, 2), Rect2(r.position, Vector2(maxf(4.0, r.size.x * clampf(frac, 0.0, 1.0)), r.size.y)))


## Sieben Säulen der Woche, heute im Akzent ganz rechts. Groß mit den Tagen darunter.
class _Bars extends Control:
	var values: Array = []
	var labels: Array = []
	var color := Color.WHITE
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		var wr: WeakRef = weakref(self)
		create_tween().tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.set("_t", v)
				me.queue_redraw()
		, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.15)

	func _draw() -> void:
		var n := values.size()
		if n == 0:
			return
		var lab_h := 24.0 if not labels.is_empty() else 0.0
		var area := size.y - lab_h
		var col_w := size.x / n
		var bw := minf(18.0, col_w * 0.56)
		var mx := 1
		for v in values:
			mx = maxi(mx, int(v))
		var font := UzTheme.font("medium")
		for i in n:
			var v := float(values[i]) / float(mx)
			var h := maxf(4.0, area * v * _t) if int(values[i]) > 0 else 4.0
			var x := col_w * i + (col_w - bw) * 0.5
			var today := i == n - 1
			var c := color if today else Color(1, 1, 1, 0.3 if int(values[i]) > 0 else 0.14)
			draw_style_box(UzTheme.box(c, int(minf(bw * 0.5, 6.0))), Rect2(x, area - h, bw, h))
			if lab_h > 0.0 and i < labels.size():
				var t := str(labels[i])
				var fs := UzTheme.size("cap")
				var tw := font.get_string_size(tr(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(col_w * i + (col_w - tw) * 0.5, size.y - 4), tr(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 1, 1, 0.85) if today else Color(1, 1, 1, 0.5))


## Ein Gesicht: rundes Bild mit dunklem Rand, damit sich mehrere übereinanderlegen lassen.
class _Face extends Control:
	const Av := preload("res://src/ui/components/avatar.gd")
	var who := ""
	var url := ""
	var px := 36

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av = Av.new()
		av.setup(who, url, "", px)
		av.position = Vector2(3, 3)
		add_child(av)

	func _draw() -> void:
		draw_circle(size * 0.5, px * 0.5 + 3.0, Color(0.06, 0.06, 0.07, 0.9))

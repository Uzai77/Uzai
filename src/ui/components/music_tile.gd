extends Control
## Kachel für Musik: Mix, Playlist oder Album als quadratisches Bild, darunter Name und eine Zeile.
## Ohne eigenes Bild malt sie ein ruhiges, einfarbiges Cover (ein Farbton, hell nach dunkel) –
## Mixe mit ihrem Namen groß im Bild, wie man es von Spotify kennt. Mixe aus vielen Titeln
## zeigen bis zu vier Albumbilder als Mosaik.
## Gewählt: der eine Cursor der Kacheln (UzTheme.draw_tile_focus) im Cursor-Takt (Liste.takt), die
## Kachel hebt sich in T_ORT um 12 px, der Lichtstreif zieht nur, wo das Theme ihn will.

signal chosen(item: Dictionary)
signal focused_item(item: Dictionary)

const Shine := preload("res://src/ui/components/shine.gd")
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Leicht := preload("res://src/core/leicht.gd")

const LIFT := 12.0
const TEXT_H := 76.0

var item: Dictionary = {}
var side := 260.0
var title_text := ""
var sub_text := ""
var cover_text := ""           ## Name im Bild (Mixe); leer: wie title_text
var big_name := false          ## Name groß ins Bild (Mixe)
var kicker := ""               ## kleine Zeile oben im Bild („Spotify“, „Mix“)
var icon_name := "music"       ## Symbol im Bild, solange es kein Bild gibt
var hue := -1.0                ## Farbton des gemalten Covers (0…1), -1: aus dem Namen
var art_urls: Array = []       ## ein Bild oder bis zu vier (Mosaik)
var art_only := false          ## nur das Bild, ohne Text und ohne Auswahl (Kopf einer Titelliste)
var round_art := false         ## rundes Bild (Künstler)

var _lift: Control
var _clip: Panel
var _imgs: Array = []
var _scrim: TextureRect
var _name: Label
var _icon: TextureRect
var _shine: Control
var _focus_t := 0.0              ## Ring (Cursor-Takt)
var _hub := 0.0                  ## Anheben (0…1), eigene Bewegung in T_ORT
var _loaded := 0

static var _grads := {}
static var _gloss: Texture2D
static var _shade: Texture2D
static var _glow: Texture2D


func setup(it: Dictionary, size_px := 260.0) -> Control:
	item = it
	side = size_px
	title_text = str(it.get("name", ""))
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE if art_only else Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_IGNORE if art_only else Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(side, side if art_only else side + TEXT_H)
	if not has_meta("uz_key"):
		set_meta("uz_key", "mt:" + str(item.get("id", title_text)))
	if hue < 0.0:
		hue = float(absi((cover_text if cover_text != "" else title_text).hash()) % 1000) / 1000.0
	_lift = Control.new()
	_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift.size = Vector2(side, side)
	add_child(_lift)
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(Color.from_hsv(hue, 0.4, 0.3), _radius()))
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.size = Vector2(side, side)
	_lift.add_child(_clip)
	_build_art()
	if art_only:
		return
	var text := U.vbox(3)
	text.position = Vector2(2, side + 14)
	text.size = Vector2(side - 4, TEXT_H - 14)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text)
	var t := U.ellipsis(U.label(title_text, "m", "text", "bold"))
	t.custom_minimum_size = Vector2(side - 4, 0)
	text.add_child(t)
	if sub_text != "":
		text.add_child(U.ellipsis(U.label(sub_text, "s", "muted")))
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(_on_gui_input)


## Gemaltes Cover, darüber die Bilder (sobald geladen), Name und Symbol.
func _build_art() -> void:
	var bg := TextureRect.new()
	bg.texture = tonal(hue)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = _clip.size
	_clip.add_child(bg)
	var gl := TextureRect.new()
	gl.texture = gloss()
	gl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gl.stretch_mode = TextureRect.STRETCH_SCALE
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gl.size = _clip.size
	_clip.add_child(gl)
	if not big_name:
		var px := int(side * 0.3)
		_icon = U.icon(icon_name, px, "text")
		_icon.modulate = Color(1, 1, 1, 0.55)
		_icon.size = Vector2(px, px)
		_icon.position = (Vector2(side, side) - Vector2(px, px)) * 0.5
		_clip.add_child(_icon)
	var urls: Array = art_urls.filter(func(u): return str(u) != "")
	var n := 4 if urls.size() >= 4 else mini(urls.size(), 1)
	var cell := side * 0.5 if n == 4 else side
	for i in n:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size = Vector2(cell, cell)
		tr.position = Vector2(float(i % 2) * cell, float(i >> 1) * cell) if n == 4 else Vector2.ZERO
		tr.modulate.a = 0.0
		_clip.add_child(tr)
		_imgs.append(tr)
		# Liegt das Bild schon bereit, steht es sofort (ohne Einblenden) – kein Aufflackern beim Blättern.
		_sync = true
		Media.url_texture(str(urls[i]), int(cell * 1.5) if n == 4 else 480, _on_tex.bind(tr))
		_sync = false
	if big_name:
		# Dunkler Verlauf von unten in der Farbe des Mixes, damit der Name auf Bildern lesbar bleibt.
		_scrim = TextureRect.new()
		_scrim.texture = shade()
		_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_scrim.stretch_mode = TextureRect.STRETCH_SCALE
		_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scrim.size = _clip.size
		_scrim.modulate = Color.from_hsv(hue, 0.6, 0.16)
		# Kam ein Bild schon im Aufbau (aus dem Speicher), steht der Verlauf gleich mit.
		_scrim.modulate.a = 0.92 if _loaded > 0 else 0.0
		_clip.add_child(_scrim)
		var pad := roundf(side * 0.08)
		if kicker != "":
			var k := U.label(kicker, str(int(clampf(side * 0.06, 14, 18))), "text", "bold")
			k.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
			k.position = Vector2(pad, pad - 2)
			k.size = Vector2(side - pad * 2, 24)
			_clip.add_child(k)
		# Ein langes Wort („Spieleklassiker“) passt kleiner in eine Zeile, statt mitten im Wort zu brechen.
		var big := cover_text if cover_text != "" else title_text
		var longest := 0
		for w in big.split(" ", false):
			longest = maxi(longest, w.length())
		var fs := clampf((side - pad * 2) / maxf(1.0, longest * 0.53), side * 0.075, side * 0.118)
		_name = U.label(big, str(int(fs)), "text", "black", true)
		_name.add_theme_color_override("font_color", Color(1, 1, 1))
		_name.add_theme_constant_override("line_spacing", -int(side * 0.02))
		_name.max_lines_visible = 3
		_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_name.position = Vector2(pad, pad)
		_name.size = Vector2(side - pad * 2, side - pad * 2)
		U.shadow(_name, 0.35)
		_clip.add_child(_name)
	elif kicker != "":
		var tag := U.panel("bg", 999, 0, 0.72)
		var l := U.label(kicker, "cap", "text", "ui_bold")
		l.clip_text = false
		var m := U.margin(10, 3, 10, 4)
		m.add_child(l)
		tag.add_child(m)
		tag.position = Vector2(10, 10)
		_clip.add_child(tag)


var _sync := false


func _on_tex(t: Texture2D, tr: TextureRect) -> void:
	if t == null or not is_instance_valid(tr):
		return
	tr.texture = t
	_loaded += 1
	if _sync:
		tr.modulate.a = 1.0
	else:
		U.ankommen(tr, U.T_ORT, "uz_fade").tween_property(tr, "modulate:a", 1.0, U.T_ORT)
	if _loaded == 1:
		if is_instance_valid(_icon):
			_icon.visible = false
		if is_instance_valid(_scrim):
			if _sync:
				_scrim.modulate.a = 0.92
			else:
				U.ankommen(_scrim, U.T_ORT, "uz_fade").tween_property(_scrim, "modulate:a", 0.92, U.T_ORT)


## Das erste geladene Bild (für den Lichtschein im Raum), sonst null.
func texture() -> Texture2D:
	for tr in _imgs:
		if is_instance_valid(tr) and (tr as TextureRect).texture:
			return (tr as TextureRect).texture
	return null


func _on_focus(on: bool) -> void:
	Liste.takt(self, _focus_t, on, _set_focus_t)
	_heben(1.0 if on else 0.0, U.T_ORT if on else U.T_WEG)
	if on:
		if UzTheme.focus_shine() and not Leicht.active and not U.reduziert():
			if _shine == null or not is_instance_valid(_shine):
				_shine = Shine.new()
				_clip.add_child(_shine)
			_clip.move_child(_shine, _clip.get_child_count() - 1)
			_shine.play()
		focused_item.emit(item)


func _set_focus_t(v: float) -> void:
	_focus_t = v
	queue_redraw()


## Heben auf to (Kurve „Ankommen“, ohne Nachfedern); „Animationen reduzieren“: kein Weg.
func _heben(to: float, dur: float) -> void:
	var t := U.ankommen(self, dur, "uz_hub") if to >= _hub else U.weg(self, "uz_hub")
	t.tween_method(_set_hub, _hub, to, dur)


func _set_hub(v: float) -> void:
	_hub = v
	if is_instance_valid(_lift):
		_lift.position.y = -U.weg_px(LIFT) * v
	queue_redraw()


## A gedrückt: die Kachel sinkt kurz ein und hebt sich wieder (Takt „Antwort“); der Ring bleibt.
func press_feedback() -> void:
	_set_focus_t(1.0)
	var t := U.ankommen(self, U.T_ORT, "uz_hub")
	t.tween_method(_set_hub, _hub, 0.55, U.T_ANTWORT)
	t.tween_method(_set_hub, 0.55, 1.0, U.T_ORT)


func _draw() -> void:
	var f := clampf(_focus_t, 0.0, 1.2)
	var r := Rect2(Vector2(0, -U.weg_px(LIFT) * _hub), Vector2(side, side))
	# Jede Kachel liegt mit weichem Schatten im Raum; die gewählte schwebt etwas höher.
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(_radius())
	sh.shadow_color = Color(0, 0, 0, 0.3 + 0.2 * f)
	sh.shadow_size = int(16 + 16 * f)
	sh.shadow_offset = Vector2(0, 8 + 10 * f)
	draw_style_box(sh, r)
	# Der eine Cursor für Cover und Kacheln (UzTheme.draw_tile_focus) – kein eigener Rahmen hier.
	if _focus_t > 0.01:
		UzTheme.draw_tile_focus(self, r, _radius(), clampf(_focus_t, 0.0, 1.0))


func _radius() -> int:
	return int(side / 2.0) if round_art else UzTheme.r_cover()


func activate() -> void:
	chosen.emit(item)


func _on_gui_input(e: InputEvent) -> void:
	Nav.klick(self, e)


# --- Gemalte Flächen (einmal je Farbton) ------------------------------------------

## Ein Farbton von hell (oben links) nach dunkel (unten rechts). Kein Verlauf über mehrere Farben.
static func tonal(h: float) -> Texture2D:
	var key := int(h * 1000.0)
	if _grads.has(key):
		return _grads[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color.from_hsv(h, 0.38, 0.66), Color.from_hsv(h, 0.5, 0.4), Color.from_hsv(fposmod(h + 0.015, 1.0), 0.58, 0.2)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.05, 0.0)
	t.fill_to = Vector2(0.95, 1.0)
	t.width = 128
	t.height = 128
	_grads[key] = t
	return t


## Weiches Licht oben rechts (weiß, wird nicht eingefärbt).
static func gloss() -> Texture2D:
	if _gloss:
		return _gloss
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.9, 0.05)
	t.fill_to = Vector2(0.15, 0.75)
	t.width = 128
	t.height = 128
	_gloss = t
	return _gloss


## Von unten dunkel nach oben durchsichtig (wird in der Farbe des Mixes eingefärbt).
static func shade() -> Texture2D:
	if _shade:
		return _shade
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 1.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 128
	_shade = t
	return _shade


## Weicher, runder Lichtschein (weiß, wird eingefärbt) für den Schein hinter großen Bildern.
static func glow_tex() -> Texture2D:
	if _glow:
		return _glow
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_glow = t
	return _glow

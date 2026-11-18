extends Control
## Große Kachel auf der Medien-Startseite (Musik, Videos, Filme, Streams): ein ruhiger Farbton je
## Art, groß der Name, darunter, was gerade los ist („Läuft: …“, „3 neu“, „2 live“), rechts das
## Zeichen der Art. Gewählt: der eine Cursor der Kacheln (UzTheme.draw_tile_focus) im Cursor-Takt
## (Liste.takt), die Kachel hebt sich in T_ORT, der Lichtstreif zieht nur, wo das Theme ihn will –
## wie die Kacheln in Musik. A öffnet den Bereich.

signal chosen(kind: String)

const MusicTile := preload("res://src/ui/components/music_tile.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Shine := preload("res://src/ui/components/shine.gd")
const U := preload("res://src/ui/u.gd")

const SIZE := Vector2(400, 236)
const LIFT := 12.0

var kind := ""
var title := ""
var kicker := ""                 ## Dienst klein oben („Spotify“, „YouTube“)
var status := ""                 ## was gerade los ist
var status_live := false         ## Zustand in Grün (läuft, live)
var icon_name := "play"
var hue := 0.0
var logo_path := ""              ## eigenes Logo (eigene Apps, apps_extern.gd) statt des großen Zeichens

var _lift: Control
var _clip: Panel
var _status_l: Label
var _shine: Control
var _focus_t := 0.0              ## Ring (Cursor-Takt)
var _hub := 0.0                  ## Anheben (0…1), eigene Bewegung in T_ORT


func setup(k: String, t: String, ic: String, h: float, kick := "") -> Control:
	kind = k
	title = t
	icon_name = ic
	hue = h
	kicker = kick
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = SIZE
	if not has_meta("uz_key"):
		set_meta("uz_key", "media:" + kind)
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", "Öffnen")
	_lift = Control.new()
	_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift.size = SIZE
	add_child(_lift)
	_clip = Panel.new()
	_clip.add_theme_stylebox_override("panel", UzTheme.box(Color.from_hsv(hue, 0.4, 0.3), _radius()))
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.size = SIZE
	_lift.add_child(_clip)
	for tex in [MusicTile.tonal(hue), MusicTile.gloss()]:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size = SIZE
		_clip.add_child(tr)
	# Das Zeichen der Art groß und leise rechts, halb aus der Kachel hinaus.
	var big := U.icon(icon_name, 168, "text")
	big.modulate = Color(1, 1, 1, 0.16)
	big.size = Vector2(168, 168)
	big.position = Vector2(SIZE.x - 150, SIZE.y - 150)
	_clip.add_child(big)
	if logo_path != "":
		# Logo der App oben rechts, ganz zu sehen; das große Zeichen tritt dann zurück.
		var lg := TextureRect.new()
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lg.size = Vector2(112, 112)
		lg.position = Vector2(SIZE.x - 112 - 22, 22)
		_clip.add_child(lg)
		var wl: WeakRef = weakref(lg)
		var wb: WeakRef = weakref(big)
		Media.file_texture(logo_path, 112, func(t: Texture2D) -> void:
			var r: TextureRect = wl.get_ref()
			var b: Control = wb.get_ref()
			if r and t:
				r.texture = t
				if b:
					b.visible = false)
	var pad := 26.0
	if kicker != "":
		var k := U.label(kicker, "cap", "text", "ui_bold")
		k.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		k.position = Vector2(pad, pad - 4)
		k.size = Vector2(SIZE.x - pad * 2, 22)
		_clip.add_child(k)
	var col := U.vbox(2)
	col.position = Vector2(pad, SIZE.y - pad - 78)
	col.size = Vector2(SIZE.x - pad * 2 - 40, 78)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(col)
	var t := U.label(title, "xl", "text", "black")
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	U.shadow(t, 0.3)
	col.add_child(t)
	_status_l = U.ellipsis(U.label(status, "s", "text", "medium"))
	col.add_child(_status_l)
	_paint_status()
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Zustand neu setzen, ohne die Kachel neu zu bauen (Musik wechselt den Titel).
func set_status(text: String, live := false) -> void:
	status = text
	status_live = live
	_paint_status()


func _paint_status() -> void:
	if not is_instance_valid(_status_l):
		return
	_status_l.text = status
	_status_l.visible = status != ""
	_status_l.add_theme_color_override("font_color", UzTheme.col("ok") if status_live else Color(1, 1, 1, 0.78))


func activate() -> void:
	press_feedback()
	chosen.emit(kind)


func _on_focus(on: bool) -> void:
	Liste.takt(self, _focus_t, on, _set_focus_t)
	_heben(1.0 if on else 0.0, U.T_ORT if on else U.T_WEG)
	if on and UzTheme.focus_shine() and not Leicht.active and not U.reduziert():
		if _shine == null or not is_instance_valid(_shine):
			_shine = Shine.new()
			_clip.add_child(_shine)
		_clip.move_child(_shine, _clip.get_child_count() - 1)
		_shine.play()


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
	var r := Rect2(Vector2(0, -U.weg_px(LIFT) * _hub), SIZE)
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
	return UzTheme.r_panel()

extends Control
## Ruhebildschirm (src/core/saver.gd): Bild um Bild der eigenen Spiele, jedes mit einer langsamen
## Kamerafahrt und weich ineinander geblendet (nur Bilder, die den Bildschirm ohne Hochziehen füllen); unten links das Spiel (Logo oder Name), oben rechts
## Uhrzeit und Datum, unten rechts die laufende Musik. Die Bilder sind leicht gedämpft, Uhr und
## Schrift rücken mit jedem Bild ein Stück weiter – auf OLED-Fernsehern brennt sich nichts ein.
##
## Liegt über allem (auch über den Tastenhinweisen) und ist für die Steuerung die oberste Ebene:
## Jede Eingabe wird hier abgefangen und beendet ihn, ohne dahinter etwas auszulösen. Solange die
## Taste oder der Stick danach noch gedrückt ist, bleibt er unsichtbar oben – sonst liefe eine
## gehaltene Richtung gleich im Menü weiter.

const U := preload("res://src/ui/u.gd")
const Lang := preload("res://src/core/lang.gd")

const SLIDE_S := 14.0         ## so lange steht ein Bild
const FADE_S := 2.8           ## Überblendung zum nächsten
const ZOOM := 1.08            ## Kamerafahrt: so weit (das Bild wird in dieser Größe geladen)
## Maximum upscaling for an image (file pixels to screen pixels); the screensaver skips smaller images because
## they would look washed out or pixelated.
const SCHARF_MAX := 1.02
const KLEIN_REIHE_MAX := 60   ## so viele zu kleine Bilder höchstens am Stück überspringen
const IN_S := 1.6
const OUT_S := 0.45
const RELEASE_MAX_S := 1.5    ## höchstens so lange auf das Loslassen warten
const DIM := 0.86             ## Bilder etwas gedämpft: ruhiger, schont OLED
const DRIFT_PX := 22.0        ## so weit wandern Uhr und Schrift von Bild zu Bild
const EDGE := Vector2(112, 96)
const LOGO_MAX := Vector2(440, 150)
const EMPTY_DRIFT_S := 40.0
const AXIS_WAKE := 0.5        ## Stick und Trigger: erst so weit zählt es (ein driftender Stick nicht)
const MOUSE_WAKE_PX := 6.0    ## Windows meldet auch Scheinbewegungen von ein, zwei Punkten

var saver: Node
var simple := false           ## nur überblenden, keine Kamerafahrt (saver.simple)

var _pics: Array[_Bild] = []
var _front := 0
var _caption: VBoxContainer
var _logo: TextureRect
var _title: Label
var _sub: Label
var _clock_box: VBoxContainer
var _clock: Label
var _date: Label
var _now: HBoxContainer
var _now_icon: TextureRect
var _now_l: Label
var _empty: VBoxContainer
var _empty_clock: Label
var _next: Timer
var _drift: Timer
var _leaving := false
var _gen := 0
var _misses := 0
var _klein := 0               ## zu kleine Bilder am Stück (SCHARF_MAX)
var _shown := 0               ## so viele Bilder schon gezeigt
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(black)
	add_child(black)
	for i in 2:
		var p := _Bild.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.self_modulate = Color(DIM, DIM, DIM)
		p.modulate.a = 0.0
		add_child(p)
		_pics.append(p)
	# Oben und unten weich abgedunkelt, damit Uhr und Schrift auf jedem Bild lesbar bleiben.
	add_child(_shade(true))
	add_child(_shade(false))
	_build_caption()
	_build_clock()
	_build_now()
	_build_empty()
	resized.connect(_layout)
	_layout()
	_next = Timer.new()
	_next.one_shot = true
	_next.timeout.connect(_advance)
	add_child(_next)
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.timeout.connect(_tick)
	add_child(tick)
	tick.start()
	_drift = Timer.new()
	_drift.wait_time = EMPTY_DRIFT_S
	_drift.timeout.connect(_drift_empty)
	add_child(_drift)
	Nav.push_layer(self)
	_tick()
	modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(self, "modulate:a", 1.0, IN_S)
	_advance()


func _shade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.55 if top else 0.0), Color(0, 0, 0, 0.0 if top else 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.anchor_right = 1.0
	if top:
		t.anchor_bottom = 0.28
	else:
		t.anchor_top = 0.55
		t.anchor_bottom = 1.0
	return t


func _build_caption() -> void:
	_caption = U.vbox(6)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.modulate.a = 0.0
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.custom_minimum_size = LOGO_MAX
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.visible = false
	_caption.add_child(_logo)
	_title = U.shadow(U.label("", "xxl", "text", "bold"))
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Spielnamen bleiben, wie sie sind
	_caption.add_child(_title)
	_sub = U.shadow(U.label("", "m", "muted", "medium"))
	_caption.add_child(_sub)
	add_child(_caption)


func _build_clock() -> void:
	_clock_box = U.vbox(0)
	_clock_box.anchor_left = 1.0
	_clock_box.anchor_right = 1.0
	_clock_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_clock = U.shadow(U.label("", "hero", "text", "regular"))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_box.add_child(_clock)
	_date = U.label("", "m", "muted", "medium")
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_box.add_child(_date)
	# Uhrzeit und Datum stehen schon in der eingestellten Sprache da und wechseln ständig: nie durch die Übersetzung.
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_date.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_clock_box.modulate.a = 0.82
	add_child(_clock_box)


func _build_now() -> void:
	_now = U.hbox(12)
	_now.anchor_left = 1.0
	_now.anchor_right = 1.0
	_now.anchor_top = 1.0
	_now.anchor_bottom = 1.0
	_now.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_now.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_now_icon = U.icon("music", 24, "muted")
	_now.add_child(_now_icon)
	_now_l = U.shadow(U.label("", "m", "muted", "medium"))
	_now_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_now.add_child(_now_l)
	_now.visible = false
	add_child(_now)


## Ohne ein einziges Spielbild auf dem PC: nur die Uhr, mittig, die langsam wandert.
func _build_empty() -> void:
	_empty = U.vbox(10)
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_clock = U.label("", "hero", "text", "regular")
	_empty_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_empty.add_child(_empty_clock)
	var hint := U.label("Bilder deiner Spiele, sobald welche installiert sind.", "s", "faint", "medium")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(hint)
	_empty.modulate.a = 0.0
	_empty.visible = false
	add_child(_empty)


func _area() -> Vector2:
	return size if size.x > 0 else get_viewport_rect().size


func _layout() -> void:
	var area := _area()
	for p in _pics:
		p.size = area
		p.queue_redraw()
	_place_corners(Vector2.ZERO, false)


## Uhr, Bildunterschrift und Musik an ihre Ecken, um off verschoben (OLED-Schutz).
func _place_corners(off: Vector2, animate: bool) -> void:
	var cap := { "offset_left": EDGE.x + off.x, "offset_bottom": -EDGE.y - off.y }
	var clk := { "offset_right": -EDGE.x + off.y, "offset_top": EDGE.y * 0.8 + off.x * 0.5 }
	var nw := { "offset_right": -EDGE.x - off.x * 0.5, "offset_bottom": -EDGE.y - off.y }
	# Die Bildunterschrift rückt nur, solange sie ausgeblendet ist (_caption_to).
	var pairs: Array = [[_clock_box, clk], [_now, nw]] if animate else [[_caption, cap], [_clock_box, clk], [_now, nw]]
	for pair in pairs:
		var n: Control = pair[0]
		for k in (pair[1] as Dictionary):
			if animate:
				n.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).tween_property(n, k, float(pair[1][k]), 4.0)
			else:
				n.set(k, float(pair[1][k]))


# --- Bilder ----------------------------------------------------------------------------------

func _advance() -> void:
	if _leaving or saver == null:
		return
	var s: Dictionary = saver.next_slide()
	if s.is_empty():
		if _shown == 0:
			_show_empty()
		else:
			_next.start(SLIDE_S)
		return
	_gen += 1
	var gen := _gen
	var area := _area() * (1.0 if simple else ZOOM)
	Media.fit_texture(str(s.path), area, func(tex: Texture2D) -> void:
		if gen != _gen or _leaving:
			return
		if tex == null:
			# Kaputte Datei: das nächste Bild versuchen, irgendwann aufgeben.
			_misses += 1
			if _misses < 6:
				_advance()
			elif _shown == 0:
				_show_empty()
			return
		_misses = 0
		# Nur Bilder in der Auflösung des Bildschirms: Was hochgezogen werden müsste, fällt für diese Runde raus.
		var fahrt := zoom_fuer(Media.orig_groesse(tex), _area() * Media.px_scale(), 1.0 if simple else ZOOM)
		if fahrt <= 0.0:
			saver.zu_klein(str(s.path))
			_klein += 1
			if _klein < KLEIN_REIHE_MAX:
				_advance.call_deferred()
			elif _shown == 0:
				_show_empty()
			else:
				_klein = 0
				_next.start(SLIDE_S)
			return
		_klein = 0
		_show(tex, s, fahrt)
	)


func _show(tex: Texture2D, s: Dictionary, zoom: float) -> void:
	_empty.visible = false
	_drift.stop()
	var back := _pics[1 - _front]
	var old := _pics[_front]
	back.texture = tex
	var area := _area()
	var m := kenburns(_rng.randi_range(0, 2), Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6)), zoom, area)
	back.fahrt = m
	back.u = 0.0
	if back.has_meta("uz_move"):
		var prev: Tween = back.get_meta("uz_move")
		if prev and prev.is_valid():
			prev.kill()
	if zoom > 1.0:
		var mv := back.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		mv.tween_property(back, "u", 1.0, SLIDE_S + FADE_S * 2.0)
		back.set_meta("uz_move", mv)
	move_child(back, old.get_index())   # das neue Bild liegt über dem alten
	var fd := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	fd.tween_property(back, "modulate:a", 1.0, FADE_S)
	fd.tween_property(old, "modulate:a", 0.0, FADE_S)
	_front = 1 - _front
	_shown += 1
	_caption_to(s)
	_place_corners(Vector2(_rng.randf_range(-DRIFT_PX, DRIFT_PX), _rng.randf_range(-DRIFT_PX * 0.5, DRIFT_PX * 0.5)), true)
	_next.start(SLIDE_S)


## Bildunterschrift tauschen: erst aus, dann (mit dem neuen Bild) langsam wieder ein.
func _caption_to(s: Dictionary) -> void:
	var tw := _caption.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_caption, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void:
		_title.text = str(s.get("title", ""))
		_sub.text = str(s.get("sub", ""))
		_sub.visible = _sub.text != ""
		_title.visible = true
		_logo.visible = false
		_logo.texture = null
		var off := Vector2(_rng.randf_range(-DRIFT_PX, DRIFT_PX), _rng.randf_range(-DRIFT_PX * 0.5, DRIFT_PX * 0.5))
		_caption.offset_left = EDGE.x + off.x
		_caption.offset_bottom = -EDGE.y - off.y
		var logo := str(s.get("logo", ""))
		if logo != "":
			var gen := _gen
			Media.file_texture(logo, int(LOGO_MAX.x), func(t: Texture2D) -> void:
				if t == null or gen != _gen:
					return
				_logo.texture = t
				_logo.visible = true
				_title.visible = false
			)
	)
	tw.tween_interval(1.0)
	tw.tween_property(_caption, "modulate:a", 1.0, 1.4)


## Wie weit die Kamerafahrt bei diesem Bild gehen darf: orig = Größe der Datei, schirm = Bildschirm in
## Bildpunkten. Das Bild füllt den Schirm (zugeschnitten); hätte es dafür hochgezogen werden müssen
## (mehr als SCHARF_MAX), 0 – dann bleibt es weg. Sonst höchstens zoom und nie weiter, als die Datei
## Bildpunkte hat (1,0 = keine Fahrt, nur Überblenden).
static func zoom_fuer(orig: Vector2i, schirm: Vector2, zoom: float) -> float:
	if orig.x <= 0 or orig.y <= 0 or schirm.x <= 0.0 or schirm.y <= 0.0:
		return 0.0
	var hoch := maxf(schirm.x / float(orig.x), schirm.y / float(orig.y))
	if hoch > SCHARF_MAX:
		return 0.0
	return clampf(1.0 / hoch, 1.0, zoom)


## Kamerafahrt eines Bildes: { s0, p0, s1, p1 } – Maßstab und Verschiebung am Anfang und am
## Ende. kind 0 hinein, 1 heraus, 2 seitlich bei gleicher Größe; dir: Richtung (je −1 … 1). Die
## Verschiebung bleibt immer innerhalb dessen, was die Vergrößerung hergibt: kein Rand zu sehen.
static func kenburns(kind: int, dir: Vector2, zoom: float, area: Vector2) -> Dictionary:
	var d := dir.clamp(Vector2(-1, -1), Vector2(1, 1)) * 0.9
	var room := (zoom - 1.0) * 0.5 * area
	match kind:
		0:
			return { "s0": 1.0, "p0": Vector2.ZERO, "s1": zoom, "p1": d * room }
		1:
			return { "s0": zoom, "p0": d * room, "s1": 1.0, "p1": Vector2.ZERO }
	var side := Vector2(signf(d.x) if d.x != 0.0 else 1.0, d.y)
	return { "s0": zoom, "p0": -side * room * 0.9, "s1": zoom, "p1": side * room * 0.9 }


func _show_empty() -> void:
	_empty.visible = true
	_clock_box.visible = false
	_caption.visible = false
	_drift_empty()
	_drift.start()


func _drift_empty() -> void:
	var area := _area()
	var sz := _empty.get_combined_minimum_size()
	_empty.size = sz
	var c := (area - sz) * 0.5
	var to := (c + Vector2(_rng.randf_range(-0.2, 0.2) * area.x, _rng.randf_range(-0.16, 0.16) * area.y)).clamp(Vector2.ZERO, (area - sz).max(Vector2.ZERO))
	var tw := _empty.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_empty, "modulate:a", 0.0, 1.2 if _empty.modulate.a > 0.0 else 0.0)
	tw.tween_property(_empty, "position", to, 0.01)
	tw.tween_property(_empty, "modulate:a", 0.6, 1.6)


# --- Uhr und Musik ---------------------------------------------------------------------------

func _tick() -> void:
	var t := U.clock()
	_clock.text = t
	_empty_clock.text = t
	var d := Time.get_date_dict_from_system()
	_date.text = Lang.date_text(int(d.day), int(d.month))
	var video_bg := Video.active and Video.background
	var line := now_line(Music.now, video_bg, Video.video)
	_now.visible = line != "" and not _empty.visible
	if line != "" and line != _now_l.text:
		_now_l.text = line
		_now_icon.texture = Icons.tex("video" if video_bg else "music", 24)
	# Etwas anderes will nach vorn (Dialog, Anruf): Platz machen.
	if not _leaving and Nav.top_layer() != self:
		saver.stop()


## Zeile unten rechts: laufende Musik („Titel · Künstler“) oder ein Video, das nur als Ton läuft.
static func now_line(music: Dictionary, video_bg: bool, video: Dictionary) -> String:
	if video_bg and str(video.get("title", "")) != "":
		return str(video.get("title", ""))
	if not bool(music.get("playing", false)) or str(music.get("title", "")) == "":
		return ""
	var artist := str(music.get("artist", ""))
	return str(music.title) + ("  ·  " + artist if artist != "" else "")


# --- Eingaben --------------------------------------------------------------------------------

## Alles abfangen: Die Eingabe beendet den Ruhebildschirm und erreicht sonst nichts. Nur
## Medientasten bleiben bei der Musik.
func _input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).keycode in Nav.MEDIA_KEYS:
		return
	get_viewport().set_input_as_handled()
	if not _leaving and saver and wakes(e):
		saver.stop()


## Zählt als Bedienung (weckt; sonst beginnt die Wartezeit von vorn)? Medientasten nie – sie
## gehören der Musik; ein leicht driftender Stick und Scheinbewegungen der Maus auch nicht.
static func wakes(e: InputEvent) -> bool:
	if e is InputEventKey:
		var k := e as InputEventKey
		return k.pressed and not k.echo and not (k.keycode in Nav.MEDIA_KEYS)
	if e is InputEventMouseButton:
		return (e as InputEventMouseButton).pressed
	if e is InputEventMouseMotion:
		# In Bildschirmpunkten: Im Fenster hochgerechnet wären 2 Punkte Zittern bei 4K schon 4.
		var mm := e as InputEventMouseMotion
		return (mm.screen_relative if mm.screen_relative != Vector2.ZERO else mm.relative).length() > MOUSE_WAKE_PX
	if e is InputEventJoypadButton:
		return (e as InputEventJoypadButton).pressed
	if e is InputEventJoypadMotion:
		return absf((e as InputEventJoypadMotion).axis_value) > AXIS_WAKE
	if e is InputEventScreenTouch:
		return (e as InputEventScreenTouch).pressed
	return false


## Was trotzdem über die Steuerung kommt (Stick und Trigger fragt sie selbst ab, die Guide-Taste
## meldet der Helfer): ebenfalls nur aufwecken.
func nav_command(_cmd: String) -> bool:
	_wake()
	return true


func nav_dir(_cmd: String) -> bool:
	_wake()
	return true


func _wake() -> void:
	if not _leaving and saver:
		saver.stop()


func leave(instant := false) -> void:
	if _leaving:
		return
	_leaving = true
	_gen += 1
	_next.stop()
	_drift.stop()
	if instant or not is_inside_tree():
		_finish()
		return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, OUT_S)
	await tw.finished
	var t0 := Time.get_ticks_msec()
	while is_inside_tree() and held() and Time.get_ticks_msec() - t0 < int(RELEASE_MAX_S * 1000.0):
		await get_tree().process_frame
	_finish()


func _finish() -> void:
	Nav.pop_layer(self)
	queue_free()


## Ist noch etwas gedrückt (Taste, Maus, Controller-Taste, Stick oder Trigger)?
static func held() -> bool:
	if Input.is_anything_pressed():
		return true
	for id in Input.get_connected_joypads():
		for ax in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			if absf(Input.get_joy_axis(id, ax)) > 0.3:
				return true
	return false


## Ein Bild des Ruhebildschirms: füllt die Fläche (zugeschnitten wie beim Laden) und zeigt den Ausschnitt
## der Kamerafahrt (fahrt aus kenburns, u von 0 bis 1). Gezeichnet als Ausschnitt der Textur statt als
## bewegter, vergrößerter Knoten – so gleitet es auch unterhalb eines Bildpunkts ruhig.
class _Bild extends Control:
	var texture: Texture2D:
		set(t):
			texture = t
			queue_redraw()
	var fahrt := {}:
		set(m):
			fahrt = m
			queue_redraw()
	var u := 0.0:
		set(v):
			u = v
			queue_redraw()

	func _draw() -> void:
		if texture == null or size.x <= 0.0:
			return
		var tex := Vector2(texture.get_width(), texture.get_height())
		# Wie STRETCH_KEEP_ASPECT_COVERED: der mittlere Teil der Textur im Seitenverhältnis der Fläche.
		var deck := minf(tex.x / size.x, tex.y / size.y)
		var basis := Rect2((tex - size * deck) * 0.5, size * deck)
		var s := lerpf(float(fahrt.get("s0", 1.0)), float(fahrt.get("s1", 1.0)), u)
		var p: Vector2 = (fahrt.get("p0", Vector2.ZERO) as Vector2).lerp(fahrt.get("p1", Vector2.ZERO) as Vector2, u)
		var a := ausschnitt(s, p, size, basis.size)
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), Rect2(basis.position + a.position, a.size))

	## Sichtbarer Ausschnitt der Textur (Bildpunkte) bei Maßstab s und Verschiebung p um die Mitte
	## (wie kenburns sie liefert): Die Fläche bleibt stehen, nur der Ausschnitt wandert – Bruchteile von
	## Bildpunkten inklusive. Die Oberfläche rastet Lagen auf ganze Bildpunkte ein
	## (snap_2d_transforms_to_pixel); ein bewegtes Bild lief dadurch in Stufen und wackelte.
	static func ausschnitt(s: float, p: Vector2, area: Vector2, tex: Vector2) -> Rect2:
		if area.x <= 0.0 or area.y <= 0.0 or s <= 0.0:
			return Rect2(Vector2.ZERO, tex)
		var k := tex / area
		var mitte := area * 0.5
		return Rect2((mitte - (mitte + p) / s) * k, area / s * k)

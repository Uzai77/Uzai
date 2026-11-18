extends Control
## Kachel (Erfolg, Spiel, Rückblick): eine ruhige Fläche. Gewählt hebt sie sich um 12 px,
## bekommt den hellen Ring mit zartem Goldband (wie die Cover) und ein Lichtstreif zieht
## einmal darüber. Inhalt kommt in build_body() unter „body“ und hebt sich mit.
## shift: Versatz der ganzen Kachel (Platte und Inhalt) gegen ihren Platz im Layout – für Wege im
## Takt (eine Kachel rückt auf ihren neuen Platz, kommt von unten an), ohne den Container anzufassen.

signal chosen

const U := preload("res://src/ui/u.gd")
const ProgressBarUz := preload("res://src/ui/components/progress_bar.gd")

var tile_size := Vector2(400, 160)
var body: Control
var bg := "surface"
var bg_alpha := 0.9
var lift := 12.0
var shift := Vector2.ZERO: set = set_shift
var _lift := 0.0


## Ein Fortschrittsbalken, der sich beim Erscheinen füllt (Feder des Balkens, im ruhigen Modus
## sofort am Ziel) – statt fertig dazustehen.
static func fill_bar(frac: float, col := "accent", h := 6.0, w := 0.0) -> Control:
	var bar := ProgressBarUz.new().setup(0.0, col, h, w)
	var ziel := clampf(frac, 0.0, 1.0)
	bar.ready.connect(func() -> void:
		if is_instance_valid(bar):
			bar.call_deferred("set_value", ziel)
	, CONNECT_ONE_SHOT)
	return bar


## Von einem Versatz (px) zum eigenen Platz: Weg mit der Kurve „Ankommen“ (dur), Deckkraft
## optional von 0 (fade), beides verzögert (delay, etwa U.staffel(i)). Ruhig: ohne Weg.
func arrive_from(off: Vector2, dur := U.T_RAUM, delay := 0.0, fade := false) -> void:
	var von := Vector2(U.weg_px(off.x), U.weg_px(off.y))
	var tw := U.ankommen(self, dur, "uz_arrive").set_parallel(true)
	if von != Vector2.ZERO:
		shift = von
		tw.tween_property(self, "shift", Vector2.ZERO, dur).set_delay(delay)
	if fade:
		modulate.a = 0.0
		tw.tween_property(self, "modulate:a", 1.0, U.T_ORT).set_delay(delay)


func set_shift(v: Vector2) -> void:
	shift = v
	if is_instance_valid(body):
		body.position = Vector2(shift.x, -_lift + shift.y)
	queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	custom_minimum_size = tile_size
	# Lichtstreif nur, wo das Theme ihn will (Graphit: focus.shine = false).
	if UzTheme.focus_shine():
		set_meta("uz_shiny", true)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(body)
	add_child(body)
	build_body()
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## Überschreiben: Inhalt unter body anlegen.
func build_body() -> void:
	pass


func activate() -> void:
	chosen.emit()


func radius() -> int:
	return UzTheme.r_panel()


func _on_focus(on: bool) -> void:
	U.focus_anim(self, on)
	var tw := U.tw(self, "uz_lift", Tween.TRANS_CUBIC)
	tw.tween_method(_set_lift, _lift, lift if on else 0.0, U.T_FOCUS if on else U.T_BASE)


func _set_lift(v: float) -> void:
	_lift = v
	if is_instance_valid(body):
		body.position = Vector2(shift.x, -v + shift.y)
	queue_redraw()


## Einmal den Lichtstreif laufen lassen (z. B. für frisch Freigeschaltetes beim Erscheinen).
func shine(delay := 0.3) -> void:
	set_meta("uz_shine", 0.0)
	var st := create_tween()
	st.tween_interval(delay)
	st.tween_method(func(v: float) -> void:
		if is_instance_valid(self):
			set_meta("uz_shine", v)
			queue_redraw()
	, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _draw() -> void:
	var f: float = float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
	var rad := radius()
	var r := Rect2(Vector2(shift.x, -_lift + shift.y), size)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(rad)
	sh.shadow_color = Color(0, 0, 0, 0.22 + 0.24 * f)
	sh.shadow_size = int(12 + 18 * f)
	sh.shadow_offset = Vector2(0, 6 + 8 * f)
	draw_style_box(sh, r)
	draw_style_box(UzTheme.box(UzTheme.col(bg, bg_alpha).lerp(UzTheme.col("surface_hi"), 0.5 * f), rad), r)
	_draw_extra(r, f)
	if UzTheme.focus_shine():
		U.draw_shine(self, r)
	if f > 0.01:
		var band := StyleBoxFlat.new()
		band.draw_center = false
		band.set_border_width_all(6)
		band.border_color = Color(UzTheme.col("accent"), 0.22 * f)
		band.set_corner_radius_all(rad + 9)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			band.set_expand_margin(side, 9)
		band.anti_aliasing = true
		draw_style_box(band, r)
		var ring := UzTheme.focus_ring(f, rad)
		ring.shadow_size = 0
		draw_style_box(ring, r)


## Überschreiben: zusätzlich unter dem Inhalt zeichnen (Schein, Fortschritt …).
func _draw_extra(_r: Rect2, _f: float) -> void:
	pass

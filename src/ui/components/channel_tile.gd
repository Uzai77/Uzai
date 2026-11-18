extends Control
## Ein Kanal als rundes Bild mit Namen darunter (Abos, Suche). Gewählt: der Cursor der Kacheln,
## rund – feine Lichtkante am Bild, weicher Schein im Akzent (in anderen Themes Band und Ring) –
## im Cursor-Takt (Liste.takt), das Bild wächst leicht. Darunter steht, wie viel es diese Woche
## Neues gab – nur wenn es etwas gab. Öffnet sich die Kanalseite, fliegt das Bild dorthin
## (src/ui/flug.gd, Schlüssel „ch:<id>“).

signal chosen(channel: Dictionary)

const Avatar := preload("res://src/ui/components/avatar.gd")
const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const Leicht := preload("res://src/core/leicht.gd")

var channel: Dictionary = {}
var fresh := 0
var px := 132
var _av: Control
var _name: Label
var _focus_t := 0.0
var _tw: Tween


func setup(ch: Dictionary, new_count := 0, size_px := 132) -> Control:
	channel = ch
	fresh = new_count
	px = size_px
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var w := float(px + 82)
	custom_minimum_size = Vector2(w, px + 118)
	set_meta("uz_key", "ch:" + str(channel.get("id", "")))
	set_meta("uz_flug", "ch:" + str(channel.get("id", "")))
	_av = Avatar.new()
	_av.setup(str(channel.get("title", "")), str(channel.get("thumb", "")), "", px)
	_av.position = Vector2((w - px) * 0.5, 18)
	_av.pivot_offset = Vector2(px, px) * 0.5
	add_child(_av)
	var col := U.vbox(2)
	col.position = Vector2(0, 18 + px + 20)
	col.size = Vector2(w, 70)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_name = U.label(str(channel.get("title", "")), "m", "text", "bold", true)
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Name von YouTube bzw. Twitch
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.max_lines_visible = 2
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var f := _name.get_theme_font("font")
	var fs := _name.get_theme_font_size("font_size")
	var lines := 2 if f.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w else 1
	_name.custom_minimum_size = Vector2(w, f.get_height(fs) * lines + float(_name.get_theme_constant("line_spacing")) * (lines - 1))
	col.add_child(_name)
	if fresh > 0:
		var nl := U.label(("%d neue diese Woche" % fresh) if fresh > 1 else "1 neues diese Woche", "s", "muted")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(w, 0)
		col.add_child(nl)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	gui_input.connect(_on_gui_input)
	set_process(false)


## Gewählt: Ring im Cursor-Takt (Liste.takt), das Bild wächst in T_ORT (Kurve „Ankommen“).
func _on_focus(on: bool) -> void:
	Liste.takt(self, _focus_t, on, _set_focus_t)
	_tw = U.ankommen(_av, U.T_ORT, "uz_gross")
	_tw.tween_property(_av, "scale", Vector2.ONE * (U.wachsen(1.07) if on else 1.0), U.T_ORT if on else U.T_WEG)
	set_process(true)


## A gedrückt: das Bild sinkt kurz ein und kommt zurück (Takt „Antwort“); der Ring bleibt.
func press_feedback() -> void:
	_set_focus_t(1.0)
	var sc := U.wachsen(1.07)
	_tw = U.ankommen(_av, U.T_ORT, "uz_gross")
	_tw.tween_property(_av, "scale", Vector2.ONE * (sc - (0.0 if U.reduziert() else 0.05)), U.T_ANTWORT)
	_tw.tween_property(_av, "scale", Vector2.ONE * sc, U.T_ORT)
	set_process(true)


func _set_focus_t(v: float) -> void:
	_focus_t = v
	queue_redraw()


func _process(_dt: float) -> void:
	# Schatten und Ring folgen dem wachsenden Bild, solange es wächst (danach ruht die Kachel wieder:
	# eine Abo-Liste hat schnell hundert davon).
	queue_redraw()
	if not (_tw and _tw.is_valid() and _tw.is_running()):
		set_process(false)


func _draw() -> void:
	var c := _av.position + Vector2(px, px) * 0.5
	var r := px * 0.5 * _av.scale.x
	# Weicher Schatten unter dem Bild.
	var sh := StyleBoxFlat.new()
	sh.draw_center = false
	sh.set_corner_radius_all(int(r))
	var t := clampf(_focus_t, 0.0, 1.0)
	sh.shadow_color = Color(0, 0, 0, 0.3 + 0.2 * t)
	sh.shadow_size = int(14 + 14 * t)
	sh.shadow_offset = Vector2(0, 8 + 6 * t)
	draw_style_box(sh, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	if t <= 0.01:
		return
	if UzTheme.matt():
		# Cursor der Marke, rund: weicher Schein im Akzent außen, feine Lichtkante direkt am Bild.
		if not Leicht.active:
			for k in 4:
				draw_arc(c, r + 5.0 + k * 5.0, 0, TAU, 96, Color(UzTheme.col("accent"), UzTheme.TILE_GLOW_A * 0.32 * t * (1.0 - k * 0.22)), 6.0, true)
		draw_arc(c, r + 1.0, 0, TAU, 96, Color(UzTheme.frame_color(), UzTheme.TILE_EDGE_A * t), float(UzTheme.TILE_EDGE_W), true)
		return
	draw_arc(c, r + 9.0, 0, TAU, 96, Color(UzTheme.col("accent"), 0.24 * t), 6.0, true)
	draw_arc(c, r + 2.5, 0, TAU, 96, Color(UzTheme.col("focus"), t), 3.0, true)


func activate() -> void:
	chosen.emit(channel)


## Geteilte Elemente (src/ui/flug.gd): das runde Bild fliegt auf die Kanalseite; solange es fliegt,
## bleibt nur die Schrift darunter stehen.
func flug_bild() -> Dictionary:
	if not is_instance_valid(_av):
		return {}
	var d: Dictionary = _av.flug_bild()
	if d.is_empty():
		return {}
	d["hide"] = _av
	return d


func _on_gui_input(e: InputEvent) -> void:
	Nav.klick(self, e)

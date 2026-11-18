extends Window
## Leistung klein in der Ecke über dem Spiel (Roadmap 5, Einstellung „In der Ecke anzeigen“):
## „CPU 34 %  GPU 87 %  71 °C  VRAM 6,1 GB“ oben links. Derselbe Weg wie die Pop-ups über dem
## Spiel (toast_window.gd): ein eigenes kleines Uzai-Fenster – randlos, durchsichtig, immer oben,
## nie fokussierbar, für die Maus durchlässig, nicht in Aufnahmen. Nichts läuft im Spiel selbst.
## Es lebt nur, solange ein Spiel läuft und der Guide zu ist (src/core/perf.gd); gefragt wird im
## Abstand von PerfLive.every_s (im leichten Modus seltener).
## Grenze: Spiele im exklusiven Vollbild lassen kein Fenster darüber zu.

const PerfLive := preload("res://src/core/perf_live.gd")
const U := preload("res://src/ui/u.gd")

const BASE := Vector2i(520, 64)      ## Größe in 1080p-Punkten
const MARGIN := 24                   ## Abstand zum Bildschirmrand

var _row: HBoxContainer
var _pill: PanelContainer
var _timer: Timer


func _init() -> void:
	visible = false
	title = "Uzai Leistung"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unfocusable = true
	mouse_passthrough = true
	transient = false
	exclusive = false
	force_native = true
	exclude_from_capture = true
	wrap_controls = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	content_scale_size = BASE
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)
	_pill = PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface_hi"), 0.82), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 18
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.position = Vector2(4, 8)
	root.add_child(_pill)
	_row = U.hbox(16)
	_pill.add_child(_row)
	_timer = Timer.new()
	_timer.autostart = false
	_timer.timeout.connect(_tick)
	add_child(_timer)


## Zeigen (ohne Fokus) oben links auf dem Bildschirm, auf dem Uzai liegt.
func appear() -> void:
	if visible:
		return
	var scr := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var spos := DisplayServer.screen_get_position(scr)
	var ssize := DisplayServer.screen_get_size(scr)
	var k := clampf(float(ssize.y) / 1080.0, 0.5, 4.0)
	size = Vector2i(roundi(BASE.x * k), roundi(BASE.y * k))
	position = spos + Vector2i(roundi(MARGIN * k), roundi(MARGIN * k))
	show_values(PerfLive.last)
	visible = true
	_timer.wait_time = PerfLive.every_s()
	_timer.start()
	_tick()
	if Config.is_windows() and Helper.available:
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())
		Helper.run("toast-window", { "hwnd": hwnd }, 2.0)


func disappear() -> void:
	if not visible:
		return
	visible = false
	_timer.stop()


func _tick() -> void:
	var s: Dictionary = await PerfLive.fetch()
	if visible:
		show_values(s)


## Teile neu setzen; gleiche Anzahl → nur die Texte (nichts springt).
func show_values(s: Dictionary) -> void:
	var parts := PerfLive.corner_parts(s)
	if _row.get_child_count() != parts.size():
		U.clear(_row)
		for p in parts:
			var pair := U.hbox(6)
			var k := U.label("", "s", "muted", "medium")
			k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			k.clip_text = false
			pair.add_child(k)
			var v := U.label("", "s", "text", "ui_bold")
			v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			v.clip_text = false
			pair.add_child(v)
			_row.add_child(pair)
	for i in parts.size():
		var pair := _row.get_child(i)
		(pair.get_child(0) as Label).text = str(parts[i][0])
		(pair.get_child(0) as Label).visible = str(parts[i][0]) != ""
		(pair.get_child(1) as Label).text = str(parts[i][1])

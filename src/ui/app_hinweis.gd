extends Window
## Tastenzeile über einer eigenen App (src/core/app_steuerung.gd): steht beim Start kurz unten in der
## Mitte („B Zurück · Guide Uzai“) und geht dann von selbst. Derselbe Weg wie die Pop-ups über dem
## Spiel (toast_window.gd): ein eigenes kleines Uzai-Fenster – randlos, durchsichtig, immer oben, nie
## fokussierbar, für die Maus durchlässig, nicht in Aufnahmen. Die App behält den Fokus.

const U := preload("res://src/ui/u.gd")
const Bildrate := preload("res://src/core/bildrate.gd")

const BASE := Vector2i(720, 96)      ## Größe in 1080p-Punkten
const UNTEN := 40                    ## Abstand zum unteren Bildschirmrand

var _pill: PanelContainer


func _init() -> void:
	visible = false
	title = "Uzai Hinweis"
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
	var root := CenterContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)
	_pill = PanelContainer.new()
	var sb := UzTheme.box(Color(UzTheme.col("surface_hi"), 0.9), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 26
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pill)


## Zeigt die Hinweise ([[taste, text], …]) für ms Millisekunden unten auf Uzais Bildschirm, dann weg.
func zeigen(hints: Array, ms: int) -> void:
	var row := U.hbox(28)
	for h in hints:
		var pair := U.hbox(10)
		pair.add_child(U.glyph(str(h[0]), 30))
		var l := U.label(str(h[1]), "m", "text", "medium")
		l.clip_text = false
		pair.add_child(l)
		row.add_child(pair)
	_pill.add_child(row)
	var scr := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var spos := DisplayServer.screen_get_position(scr)
	var ssize := DisplayServer.screen_get_size(scr)
	var k := clampf(float(ssize.y) / 1080.0, 0.5, 4.0)
	size = Vector2i(roundi(BASE.x * k), roundi(BASE.y * k))
	position = spos + Vector2i((ssize.x - size.x) / 2, ssize.y - size.y - roundi(UNTEN * k))
	_pill.modulate.a = 0.0
	visible = true
	# Uzai ruht hinter der App (12 Bilder/s): fürs weiche Ein- und Ausblenden kurz mehr.
	Bildrate.heben(self)
	if Config.is_windows() and Helper.available:
		Helper.run("toast-window", { "hwnd": DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id()) }, 2.0)
	var tw := _pill.create_tween()
	tw.tween_property(_pill, "modulate:a", 1.0, U.T_ORT)
	tw.tween_interval(maxf(0.0, ms / 1000.0))
	tw.tween_property(_pill, "modulate:a", 0.0, U.T_WEG)
	tw.finished.connect(func() -> void:
		Bildrate.senken(self)
		queue_free())

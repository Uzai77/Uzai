extends Window
## Eigenes kleines Fenster für Pop-ups über einem laufenden Spiel, oben rechts: randlos,
## durchsichtig, immer oben, nie fokussierbar und für die Maus durchlässig. Uzais Hauptfenster
## bleibt dabei minimiert, das Spiel behält den Fokus (Windows zeigt ein nicht fokussierbares
## Fenster ohne Aktivieren; der Helfer setzt zur Sicherheit WS_EX_NOACTIVATE, WS_EX_TOPMOST und
## WS_EX_TOOLWINDOW). Das Fenster lebt nur, solange ein Pop-up zu sehen ist und erscheint nicht
## in Aufnahmen oder Übertragungen des Bildschirms (Windows 10 2004 und neuer).
## Grenze: Läuft ein Spiel im exklusiven Vollbild, zeigt Windows kein anderes Fenster darüber.

const Bildrate := preload("res://src/core/bildrate.gd")

const BASE := Vector2i(660, 620)     ## Größe in 1080p-Punkten (Platz für drei Karten und Schatten)
const MARGIN_RIGHT := 40             ## Abstand zum rechten Bildschirmrand (die Karte sitzt dann wie in Uzai)

var box: VBoxContainer


func _init() -> void:
	# Erst verstecken: Fenster-Art (eigenes Fenster) und Fokus lassen sich nur vor dem Zeigen setzen.
	visible = false
	title = "Uzai Mitteilung"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unfocusable = true
	mouse_passthrough = true
	transient = false
	exclusive = false
	force_native = true
	# Nachrichten sind privat: nicht in Aufnahmen, Übertragungen und Bildschirmfotos.
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
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_right = -56
	box.offset_left = -56 - 500
	box.offset_top = 40
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(box)


## Zeigen (ohne Fokus) auf dem Bildschirm, auf dem Uzai liegt.
func appear() -> void:
	if visible:
		return
	var scr := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var spos := DisplayServer.screen_get_position(scr)
	var ssize := DisplayServer.screen_get_size(scr)
	var k := clampf(float(ssize.y) / 1080.0, 0.5, 4.0)
	size = Vector2i(roundi(BASE.x * k), roundi(BASE.y * k))
	position = spos + Vector2i(ssize.x - size.x - roundi(MARGIN_RIGHT * k), 0)
	visible = true
	# Im Spiel läuft Uzai sparsam (12 Bilder/s): für weiche Bewegung kurz mehr.
	Bildrate.heben(self)
	if Config.is_windows() and Helper.available:
		var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())
		Helper.run("toast-window", { "hwnd": hwnd }, 2.0)


func disappear() -> void:
	if not visible:
		return
	visible = false
	Bildrate.senken(self)

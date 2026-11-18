extends CanvasLayer
## Zeigt Erfolgs-Pop-ups (achievement_toast.gd) nacheinander: unten in der Mitte (oder oben,
## Einstellungen → Mitteilungen). In Uzai liegen sie über allem; läuft ein Spiel, in einem
## eigenen randlosen Fenster über dem Spiel (wie die Mitteilungen, toast_window.gd: nie
## fokussierbar, für die Maus durchlässig, immer oben). Kommen mehrere, warten sie in einer
## Reihe; je mehr warten, desto kürzer bleibt jedes stehen (Unlocks.hold_for).

const Toast := preload("res://src/ui/components/achievement_toast.gd")
const Bildrate := preload("res://src/core/bildrate.gd")

const MARGIN_BOTTOM := 92.0      ## Unterkante der Pille über dem Bildschirmrand (1080p-Punkte)
const MARGIN_TOP := 36.0
const GAP := 0.18                ## Pause zwischen zwei Pop-ups
const HOLD_KOMPLETT := 4.6       ## so lange steht der letzte Erfolg eines Spiels (nichts wartet)
const HOLD_DESC := 1.4           ## so viel länger steht ein Erfolg mit Beschreibung (Zeit zum Lesen)
const SOUND2_AT := 0.55          ## zweiter Klang der Art „komplett“: wenn die Pille offen steht
const SOUND2_PITCH := 1.5        ## eine Quinte höher (bleibt in der Pentatonik des Klangsatzes)

var force_overlay := false       ## Pop-ups im eigenen Fenster, auch ohne Spiel (Proben)
var shown := 0                   ## gezeigte Pop-ups (Tests)
var current: Control
var _queue: Array = []
var _root: Control
var _win: Window


func _ready() -> void:
	layer = 101
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)


func waiting() -> int:
	return _queue.size()


func busy() -> bool:
	return is_instance_valid(current)


func show_entry(e: Dictionary, deco: Dictionary) -> void:
	_queue.append([e, deco])
	if is_instance_valid(current):
		current.call("shorten", Unlocks.hold_for(_queue.size()))
	else:
		_next()


## Alle wartenden und das laufende weg (etwa beim Beenden).
func clear() -> void:
	_queue.clear()
	if is_instance_valid(current):
		current.queue_free()
	current = null
	_hide_window()


func _next() -> void:
	if _queue.is_empty():
		_hide_window()
		return
	var item: Array = _queue.pop_front()
	var e: Dictionary = item[0]
	var deco: Dictionary = item[1]
	var over := _use_overlay()
	var host := _root
	if over:
		host = _overlay_root()
	# Der große Moment (alle Erfolge eines Spiels) steht länger, solange nichts wartet.
	var hold := Unlocks.hold_for(_queue.size())
	if str(deco.get("variant", "")) == "komplett" and _queue.is_empty():
		hold = maxf(hold, HOLD_KOMPLETT)
	# Mit Beschreibung etwas länger, solange nichts wartet: erst „Erfolg freigeschaltet“, dann die Beschreibung.
	if str(e.get("desc", "")).strip_edges() != "" and _queue.is_empty():
		hold += HOLD_DESC
	var toast: Control = Toast.new().setup(e, deco, hold)
	host.add_child(toast)
	_place(toast, host)
	current = toast
	shown += 1
	toast.finished.connect(func() -> void:
		toast.queue_free()
		if current == toast:
			current = null
		await get_tree().create_timer(GAP).timeout
		if not is_instance_valid(current):
			_next()
	)
	if bool(Config.get_value("notify.unlock_sound", true)):
		Sfx.play(str(deco.get("sound", "unlock")))
		# Zweiter, hellerer Klang aus demselben Klangsatz, wenn die Pille offen steht (komplett).
		if str(deco.get("sound2", "")) != "":
			get_tree().create_timer(SOUND2_AT).timeout.connect(Sfx.play.bind(str(deco.sound2), SOUND2_PITCH))
	_rumble(bool(deco.get("rare", false)))
	toast.call("play")


## Unten oder oben in der Mitte; der Bereich des Pop-ups ist größer als die Pille (Ring, Schatten).
func _place(toast: Control, host: Control) -> void:
	var vs := host.get_viewport_rect().size if host == _root else Vector2(Toast.AREA)
	var top := str(Config.get_value("notify.unlock_pos", "unten")) == "oben"
	var pill_off := Toast.AREA.y * 0.5 - Toast.R      # Abstand Bereich-Oberkante → Pille
	toast.position.x = roundf((vs.x - Toast.AREA.x) * 0.5)
	if host != _root:
		toast.position.y = 0.0 if not top else MARGIN_TOP - pill_off
	elif top:
		toast.position.y = MARGIN_TOP - pill_off
	else:
		toast.position.y = vs.y - MARGIN_BOTTOM - (pill_off + Toast.H)


## Wie die Mitteilungen: im eigenen Fenster, wenn Uzai selbst nicht zu sehen ist.
func _use_overlay() -> bool:
	if force_overlay:
		return true
	return Toasts.use_overlay()


func _overlay_root() -> Control:
	if not is_instance_valid(_win):
		_win = _Win.new()
		add_child(_win)
	_win.call("appear", str(Config.get_value("notify.unlock_pos", "unten")) == "oben")
	return _win.get_meta("root")


func _hide_window() -> void:
	if is_instance_valid(_win):
		_win.call("disappear")


## Kurzer Impuls am Controller über Pads.pulse("achievement") (Pads prüft selbst, ob
## Vibration bei Ereignissen an ist, und erreicht im Spiel XInput-Controller über den Helfer).
func _rumble(_strong: bool) -> void:
	var pads := get_node_or_null("/root/Pads")
	if pads != null and pads.has_method("pulse"):
		pads.call("pulse", "achievement")


## Fenster über dem Spiel: randlos, durchsichtig, immer oben, nie fokussierbar, Maus geht durch.
## Größe in 1080p-Punkten wie der Bereich des Pop-ups, auf dem Bildschirm mittig unten/oben.
class _Win extends Window:
	func _init() -> void:
		visible = false
		title = "Uzai Erfolg"
		borderless = true
		transparent = true
		transparent_bg = true
		always_on_top = true
		unfocusable = true
		mouse_passthrough = true
		transient = false
		exclusive = false
		force_native = true
		wrap_controls = false
		content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		content_scale_size = Vector2i(Toast.AREA)
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.anchor_right = 1.0
		root.anchor_bottom = 1.0
		add_child(root)
		set_meta("root", root)

	func appear(top: bool) -> void:
		var scr := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
		var spos := DisplayServer.screen_get_position(scr)
		var ssize := DisplayServer.screen_get_size(scr)
		var k := clampf(float(ssize.y) / 1080.0, 0.5, 4.0)
		size = Vector2i(roundi(Toast.AREA.x * k), roundi(Toast.AREA.y * k))
		var pill_off := Toast.AREA.y * 0.5 - Toast.R
		var y := 0
		if not top:
			y = ssize.y - roundi((MARGIN_BOTTOM + pill_off + Toast.H) * k)
		position = spos + Vector2i((ssize.x - size.x) / 2, y)
		if visible:
			return
		visible = true
		# Im Spiel läuft Uzai sparsam: für eine weiche Bewegung kurz 60 Bilder/s.
		Bildrate.heben(self)
		if Config.is_windows() and Helper.available:
			var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window_id())
			Helper.run("toast-window", { "hwnd": hwnd }, 2.0)

	func disappear() -> void:
		if not visible:
			return
		visible = false
		Bildrate.senken(self)

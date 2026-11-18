extends Node
## The mouse over the interface (attached to Nav, like zeiger.gd): click mode.
##
## Hovering selects nothing. Uzai's selection moves as it does with a controller; if it followed the mouse,
## tabs and categories would switch as soon as the cursor passes over them, and rows would scroll away under
## the mouse. A click selects and activates in one step (zeiger.gd). As hover feedback, the pointer turns
## into a hand over everything selectable – immediately, without a frame that lags behind.

const U := preload("res://src/ui/u.gd")

var nav: Node
var _hover: Control                    ## Kachel unter der Maus, die gerade leuchtet (zeiger_schweben)
var _ausstehend := false
var _pos := Vector2.ZERO
var zeiger_form := Input.CURSOR_ARROW   ## zuletzt gesetzte Form des Mauszeigers (Hand über Wählbarem)


## Bei jeder echten Mausbewegung (Nav._input). Nav sieht die Bewegung, bevor Godot weiß, was unter der Maus liegt –
## darum erst danach auswerten (noch im selben Bild), sonst hinge die Hand ein Ereignis hinterher.
func bewegt(pos: Vector2) -> void:
	_pos = pos
	if not _ausstehend:
		_ausstehend = true
		_auswerten.call_deferred()


func _auswerten() -> void:
	_ausstehend = false
	var c := ziel()
	var form := Input.CURSOR_POINTING_HAND if c != null else Input.CURSOR_ARROW
	if form != zeiger_form:
		zeiger_form = form
		Input.set_default_cursor_shape(form)
	_leuchten(c)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if nav:
		nav.device_changed.connect(func(kind: String) -> void:
			if kind in ["pad", "touch"]:
				_leuchten(null))


## Unter der Maus leuchtet, was wählbar ist; gewählt wird dabei nichts. Wer es selbst kann (Spiele, Videos, Streams,
## Filme, Reiter oben: zeiger_schweben), zeichnet den Schein selbst, unter seinem Bild. Andere Kacheln (Musik, Shop,
## „Für dich“, Apps …) bekommen ihn von hier, darübergelegt (_glanz) – Zeilen und Knöpfe nicht. null: nichts leuchtet
## (Maus weg, Controller in der Hand).
func _leuchten(c: Control) -> void:
	_glanz_auf(c if c != null and not eigener_schein(c) and kachel_artig(c) else null)
	if c != null and not eigener_schein(c):
		c = null
	if c == _hover:
		return
	if is_instance_valid(_hover):
		_schweben(_hover, false)
	_hover = c
	if c != null:
		_schweben(c, true)


## Zeigt selbst, dass die Maus darüber ist: zeiger_schweben, oder ein ruhiger Knopf (U.ruhig – Spielseite, Dialoge …).
static func eigener_schein(c: Control) -> bool:
	return c.has_method("zeiger_schweben") or (c is Button and c.has_meta("uz_kf"))


static func _schweben(c: Control, an: bool) -> void:
	if c.has_method("zeiger_schweben"):
		c.call("zeiger_schweben", an)
	elif c is Button:
		U.knopf_schweben(c as Button, an)


## Sieht aus wie eine Kachel: nicht zu klein, nicht so breit wie eine Zeile (Einstellungen, Listen, Knöpfe).
static func kachel_artig(c: Control) -> bool:
	var s := c.size * c.get_global_transform().get_scale().abs()
	return s.x >= 64.0 and s.y >= 64.0 and s.x <= s.y * 3.2


# --- Schein für Kacheln ohne eigenen ------------------------------------------------------

var glanz_ziel: Control                 ## Kachel, um die der Schein von hier liegt (null: keine)
var _glanz_t := 0.0
var _glanz_ebene: CanvasLayer
var _glanz: Control


func _glanz_auf(c: Control) -> void:
	if c == glanz_ziel:
		return
	if c != null:
		_glanz_t = 0.0
	glanz_ziel = c
	if c == null and _glanz == null:
		return
	if _glanz == null:
		_glanz_ebene = CanvasLayer.new()
		_glanz_ebene.layer = 64
		add_child(_glanz_ebene)
		_glanz = Control.new()
		_glanz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glanz.draw.connect(_glanz_zeichnen)
		_glanz_ebene.add_child(_glanz)
	set_process(true)


func _process(dt: float) -> void:
	# Kachel weg, unsichtbar oder unter einer neuen Ebene (Dialog): der Schein geht.
	var c := glanz_ziel
	if c != null and (not is_instance_valid(c) or not c.is_visible_in_tree() or _wird_geloescht(c)
			or (nav.scope_root() and not (nav.scope_root() as Control).is_ancestor_of(c))):
		glanz_ziel = null
	var soll := 1.0 if is_instance_valid(glanz_ziel) else 0.0
	_glanz_t = move_toward(_glanz_t, soll, dt / U.T_ANTWORT)
	if _glanz:
		_glanz.queue_redraw()
	if _glanz_t <= 0.0 and glanz_ziel == null:
		set_process(false)


var _glanz_zuletzt := Rect2()


func _glanz_zeichnen() -> void:
	if is_instance_valid(glanz_ziel):
		_glanz_zuletzt = glanz_ziel.get_global_rect()
	if _glanz_t <= 0.01 or _glanz_zuletzt.size == Vector2.ZERO:
		return
	var rc := int(glanz_ziel.get_meta("uz_radius", UzTheme.r_cover())) if is_instance_valid(glanz_ziel) else UzTheme.r_cover()
	UzTheme.draw_tile_hover(_glanz, _glanz_zuletzt, rc, _glanz_t)


func _notification(what: int) -> void:
	# Die Maus verlässt das Fenster: nichts leuchtet weiter.
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_leuchten(null)


## Das wählbare Element unter der Maus (null: keins) – nicht, was gerade abgebaut wird oder kaum sichtbar ist.
func ziel() -> Control:
	var h := get_viewport().gui_get_hovered_control()
	# Meldet Godot nichts (gleich nach dem Zurückholen des Fensters, ohne Fenster in Tests): dieselbe Suche wie für Touch.
	if h == null:
		h = nav.zeiger.control_at(_pos)
	var scope: Control = nav.scope_root()
	while h and h != scope:
		if h.focus_mode == Control.FOCUS_ALL and h.is_visible_in_tree() and not h.has_meta("uz_skip") \
				and not (h is BaseButton and (h as BaseButton).disabled) and not h is LineEdit:
			break
		h = h.get_parent() as Control
	if h == null or h == scope or (scope and not scope.is_ancestor_of(h)):
		return null
	if nav.zeiger._alpha(h) < 0.3 or _wird_geloescht(h):
		return null
	return h


static func _wird_geloescht(c: Node) -> bool:
	var n := c
	while n:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false

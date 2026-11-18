extends Control
## Hält eine Leiste (Reiter, Unterbereiche, Quellen), die breiter sein kann als ihr Platz – etwa
## mit großer Oberfläche (Einstellungen → Aussehen). Passt sie, steht sie wie gebaut. Sonst
## gleitet sie mit der Auswahl (bzw. dem gewählten Reiter), und was am Rand nicht mehr ganz Platz
## hat, blendet weich aus (beim Gleiten über die letzten FADE Pixel), statt über den Rand oder auf
## Nachbarn zu ragen. Nichts wird abgeschnitten: Auswahl und Glimmen bleiben ganz, weil nichts
## zuschneidet (nur die Deckkraft der Einträge ändert sich).

const U := preload("res://src/ui/u.gd")

const EDGE := 64.0             ## so weit bleibt die Auswahl vom Rand weg
const FADE := 18.0             ## so weit darf ein Eintrag noch halb sichtbar über den Rand gleiten

var strip: Control
var _x := 0.0                  ## aktuelle Verschiebung (≤ 0)
var _v := 0.0
var _goal := 0.0
var _snap := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(false)


func hold(s: Control) -> Control:
	strip = s
	add_child(s)
	s.minimum_size_changed.connect(_fit)
	s.sort_children.connect(_fit)
	# Ein anderer Reiter wird gewählt (LB/RB aus der Seite heraus): die Leiste zeichnet neu.
	s.draw.connect(_fit)
	resized.connect(_fit)
	return self


func _ready() -> void:
	Nav.focus_moved.connect(func(_c: Control) -> void: _fit())
	_fit()


func _get_minimum_size() -> Vector2:
	return Vector2(0, strip.get_combined_minimum_size().y if is_instance_valid(strip) else 0.0)


## Ein neuer Inhalt (Bereich gewechselt): ohne Gleiten an die richtige Stelle.
func snap() -> void:
	_snap = true
	_fit()


func _fit() -> void:
	if not is_instance_valid(strip) or not is_inside_tree():
		return
	update_minimum_size()
	var sw := strip.get_combined_minimum_size().x
	strip.size = Vector2(maxf(sw, size.x), size.y)
	var over := sw - size.x
	if over <= 0.5:
		_goal = 0.0
	else:
		var item := _tracked()
		if item != null:
			var l := item.position.x + _goal
			var r := item.position.x + item.size.x + _goal
			if l < EDGE:
				_goal += EDGE - l
			elif r > size.x - EDGE:
				_goal -= r - (size.x - EDGE)
		_goal = clampf(_goal, -over, 0.0)
	if _snap or not is_visible_in_tree():
		_snap = false
		_x = _goal
		_v = 0.0
	_apply()
	set_process(absf(_x - _goal) > 0.5)


## Was sichtbar bleiben soll: die Auswahl in der Leiste, sonst der gewählte Reiter.
func _tracked() -> Control:
	var f := get_viewport().gui_get_focus_owner()
	while f != null and f.get_parent() != strip:
		f = f.get_parent() as Control
	if f != null:
		return f
	for ch in strip.get_children():
		if ch is Control and bool(ch.get_meta("uz_selected", false)):
			return ch
	return null


func _process(dt: float) -> void:
	var s := U.spring_step(_x, _v, _goal, dt)
	_x = s.x
	_v = s.y
	if absf(_x - _goal) < 0.5 and absf(_v) < 2.0:
		_x = _goal
		set_process(false)
	_apply()


func _apply() -> void:
	strip.position = Vector2(roundf(_x), 0.0)
	var w := size.x
	var fits := strip.get_combined_minimum_size().x <= w + 0.5
	for ch in strip.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		var a := 1.0
		if not fits and c.size.x > 0.0:
			var l := c.position.x + _x
			var over := maxf(maxf(0.0, -l), maxf(0.0, l + c.size.x - w))
			a = 1.0 - smoothstep(0.0, FADE, over)
		c.modulate.a = a

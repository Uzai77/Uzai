extends "res://src/ui/layers/layer.gd"
## Eine Quelle der Startseite verschieben (langes A → Verschieben, quellen_ordnung.gd): Die Quelle
## bekommt einen Goldrahmen, links/rechts (auch LB/RB) gleitet sie an ihren neuen Platz und die
## Nachbarin weich an ihren alten. A, B oder ein Klick ist fertig. Die Ebene selbst ist unsichtbar
## (nichts dunkelt ab, nichts rückt zurück); der Fokus bleibt auf der Quelle.

const Q := preload("res://src/ui/sections/quellen_ordnung.gd")

const Main := preload("res://src/main.gd")
var main: Main
var section: Object              ## Bereich bzw. Reihe (app_gruppe.gd)
var sub_id := ""
var box: Control             ## Reihe mit der Quelle (Spiele: main.chips_box, Apps: Leiste oben bzw. Ordner)
var prefix := "chip:"        ## uz_key der Einträge: prefix + ID
var _item: Control
var _on := 0.0               ## Rahmen 0…1 (blendet weich ein und aus)


func _init() -> void:
	super()
	dim = 0.0
	depth = false


func build() -> void:
	set_meta("uz_silent", true)
	set_meta("uz_hint_b", "")          # B ist auch „Fertig“: einmal genannt reicht (bei A)
	set_meta("uz_hints", [["lr", "Verschieben"], ["a", "Fertig"]])
	_item = _chip()
	create_tween().tween_property(self, "_on", 1.0, U.T_BASE).set_trans(Tween.TRANS_CUBIC)


func _chip() -> Control:
	if not is_instance_valid(box):
		return null
	for c in box.get_children():
		if str(c.get_meta("uz_key", "")) == prefix + sub_id:
			return c
	return null


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_item) or not _item.is_visible_in_tree():
		return
	var r := Rect2(_item.global_position - global_position, _item.size * _item.get_global_transform().get_scale()).grow_individual(4, 2, 4, 2)
	var acc := UzTheme.col("accent")
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(2)
	sb.border_color = Color(acc, 0.9 * _on)
	# Pille um eine Quelle, eckiger Rahmen um eine große Kachel (Apps).
	sb.set_corner_radius_all(int(r.size.y * 0.5) if r.size.y < 80.0 else UzTheme.r_panel() + 4)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func nav_dir(cmd: String) -> bool:
	if cmd == "left" or cmd == "right":
		_shift(-1 if cmd == "left" else 1)
	return true


func nav_command(cmd: String) -> bool:
	if cmd == "guide":
		return false
	if cmd in ["a", "b"]:
		Sfx.play("select" if cmd == "a" else "back")
		close()
		return true
	if cmd in ["lb", "rb"]:
		_shift(-1 if cmd == "lb" else 1)
	return true


func _shift(d: int) -> void:
	if not is_instance_valid(_item) or section == null:
		return
	var box := _item.get_parent() as Control
	var at := _item.get_index()
	if at + d < 0 or at + d >= box.get_child_count():
		return
	var other := box.get_child(at + d) as Control
	if not str(other.get_meta("uz_key", "")).begins_with(prefix) or Q.step(section, sub_id, d) < 0:
		Sfx.play("bump")
		return
	var from := { _item: _item.position.x, other: other.position.x }
	box.move_child(_item, at + d)
	Sfx.play("move")
	# Nach dem Ordnen der Leiste: beide von ihrem alten Platz an den neuen gleiten lassen.
	await get_tree().process_frame
	for c in from.keys():
		var ctl := c as Control
		if not is_instance_valid(ctl):
			continue
		var to := ctl.position.x
		ctl.position.x = float(from[c])
		U.im_tempo(ctl.create_tween()).tween_property(ctl, "position:x", to, U.T_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Lange Reihe (Kacheln der Apps): die Reihe folgt der verschobenen Kachel.
	if is_instance_valid(_item):
		Nav.reveal(_item)

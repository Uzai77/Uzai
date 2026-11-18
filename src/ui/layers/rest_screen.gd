extends "res://src/ui/layers/layer.gd"
## Ruhemodus (siehe src/core/rest.gd): fast schwarz, in der Mitte ein Mond, „Ruhemodus“, darunter
## was mit dem Spiel ist und dass jede Taste weckt. Meist ist der Bildschirm ohnehin aus; geht er
## von selbst an (Maus gestreift), steht hier ruhig, was los ist. Der Block wandert langsam, damit
## sich auf OLED-Fernsehern nichts einbrennt. Jede Taste, jeder Klick weckt.
## „Nur hören“ nutzt dieselbe Ebene mit eigenem Titel und Zeichen (der Titel läuft weiter).

var rest: Node
var game_title := ""
var note := ""
var titel := "Ruhemodus"
var symbol := "moon"
var _block: Control
var _drift: Timer


func _init() -> void:
	super()
	dim = 1.0                  # ganz schwarz: OLED schonen, nichts lenkt ab
	closable = false
	depth = false
	set_meta("uz_silent", true)
	set_meta("uz_hints_center", true)
	set_meta("uz_hint_b", "Aufwecken")


func build() -> void:
	if is_instance_valid(_scrim):
		_scrim.color = Color(0, 0, 0, 1.0)
		_scrim.gui_input.connect(_on_click)
	gui_input.connect(_on_click)
	var col := U.vbox(14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(U.icon(symbol, 64, "muted"))
	var t := U.label(titel, "36", "text", "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if game_title != "":
		var g := U.label(game_title, "m", "text", "medium")
		g.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels: nie übersetzen
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(g)
	if note != "":
		var n := U.label(note, "s", "muted", "regular", true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = 640
		col.add_child(n)
	col.add_child(U.spacer(0, 10, false))
	var h := U.label("Zum Aufwecken eine beliebige Taste drücken", "s", "muted", "medium")
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	col.modulate.a = 0.55
	_block = col
	add_child(col)
	_place.call_deferred(false)
	_drift = Timer.new()
	_drift.wait_time = 40.0
	_drift.timeout.connect(_place.bind(true))
	add_child(_drift)
	_drift.start()


## Block an eine neue, zufällige Stelle nahe der Mitte (OLED-Schutz).
func _place(animate: bool) -> void:
	if not is_instance_valid(_block):
		return
	var sz := _block.get_combined_minimum_size()
	_block.size = sz
	var area := size if size.x > 0 else get_viewport_rect().size
	var c := (area - sz) * 0.5
	var off := Vector2(randf_range(-0.18, 0.18) * area.x, randf_range(-0.15, 0.15) * area.y) if animate else Vector2.ZERO
	var to := (c + off).clamp(Vector2.ZERO, (area - sz).max(Vector2.ZERO))
	if animate:
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(_block, "modulate:a", 0.0, 1.2)
		tw.tween_property(_block, "position", to, 0.01)
		tw.tween_property(_block, "modulate:a", 0.55, 1.2)
	else:
		_block.position = to


func _on_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		_wake()


func _wake() -> void:
	if rest and is_instance_valid(rest):
		rest.wake("ui")


func nav_command(_cmd: String) -> bool:
	_wake()
	return true


func nav_dir(_cmd: String) -> bool:
	_wake()
	return true

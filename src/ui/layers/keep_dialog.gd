extends "res://src/ui/layers/dialog.gd"
## „Behalten?“ nach einer neuen Auflösung oder Bildwiederholrate (Bild & Ton): wie bei Windows läuft
## eine Frist von BildTon.KEEP_S Sekunden, ein Balken läuft dabei leer. Ohne „Behalten“ – Frist um,
## B oder „Zurücksetzen“ – kommt der alte Modus zurück. Die Auswahl steht zuerst auf „Zurücksetzen“:
## Ein versehentlicher Druck behält nichts. Die Frist selbst zählt in BildTon (core), nicht hier.

const BildTon := preload("res://src/core/bild_ton.gd")

var _kept := false
var _count_l: Label
var _bar: Control
var _back_btn: Button


func fill() -> void:
	if heading == "":
		heading = "Diese Auflösung behalten?"
	icon_name = "monitor"
	buttons = [["Behalten", func() -> void: _kept = true], ["Zurücksetzen", func() -> void: pass]]
	super()
	# Nach dem Knopf: Der Dialog schließt sich vor dessen Handlung – erst danach steht _kept fest.
	closed.connect(func() -> void: BildTon.answer(_kept), CONNECT_DEFERRED)
	if not is_instance_valid(panel) or not panel.visible:
		return
	_count_l = U.label("", "s", "muted", "medium")
	_count_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_count_l)
	box.move_child(_count_l, box.get_child_count() - 2)
	_bar = ProgressBarUz.new().setup(1.0, "accent", 4.0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_bar)
	box.move_child(_bar, box.get_child_count() - 2)
	for b in box.find_children("*", "Button", true, false):
		if (b as Button).text == "Zurücksetzen":
			_back_btn = b
	_tick()


func _first_focus() -> Control:
	return _back_btn if is_instance_valid(_back_btn) else super()


func _process(_dt: float) -> void:
	if _closing:
		return
	# Frist um (oder schon anderswo beantwortet): Dialog geht, BildTon hat zurückgestellt.
	if not BildTon.asking():
		close()
		return
	_tick()


func _tick() -> void:
	if not is_instance_valid(_count_l):
		return
	var left := BildTon.ask_left()
	_count_l.text = tr("Ohne Antwort geht es in %d s zurück.") % left
	var ms := Time.get_ticks_msec() - int(BildTon.ask.get("t0", Time.get_ticks_msec()))
	_bar.set_value(1.0 - clampf(ms / (BildTon.KEEP_S * 1000.0), 0.0, 1.0))

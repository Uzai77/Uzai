extends "res://src/ui/layers/layer.gd"
## Dialog in der Bildschirmmitte: schwebt (Höhenstufe 3) im Material „Kernlicht“ und steigt beim
## Öffnen leicht auf.

var width := 760.0
var box: VBoxContainer
var panel: PanelContainer


func build() -> void:
	panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.radius + 6, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 44
	sb.content_margin_bottom = 40
	UzTheme.lift(sb, 3)
	panel.add_theme_stylebox_override("panel", sb)
	# Material „Kernlicht“ (bleibt, auch wenn ein Dialog seine Fläche neu setzt).
	UzTheme.kernlicht(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(width, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	box = U.vbox(18)
	panel.add_child(box)
	fill()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.resized.connect(func() -> void: panel.pivot_offset = Vector2(panel.size.x * 0.5, panel.size.y))


## Fläche vor Schrift (layer.gd): die Karte steht gleich deckend da, ihre Schrift folgt.
func flaeche() -> Control:
	return panel


## Wächst von unten her auf (96 → 100 %): wirkt wie ein leichtes Aufsteigen, ohne Überschwingen.
func _enter_motion(_fl: Control) -> void:
	panel.scale = Vector2.ONE * U.wachsen(0.96)
	U.ankommen(panel, U.T_RAUM, "uz_karte").tween_property(panel, "scale", Vector2.ONE, U.T_RAUM)


func _exit_motion(tw: Tween) -> void:
	if is_instance_valid(panel):
		U.stop(panel, "uz_karte")
		tw.set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE * U.wachsen(0.97), U.T_WEG)


func fill() -> void:
	pass

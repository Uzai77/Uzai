extends HBoxContainer
## Fünf Sterne für eine Bewertung in halben Sternen (Backlog, src/library/backlog.gd): gefüllt in
## der Akzentfarbe, ein halber Stern ist links gefüllt und rechts nur Umriss. Nur Anzeige.

const U := preload("res://src/ui/u.gd")

var half := 0
var px := 26


func setup(h: int, size_px := 26) -> HBoxContainer:
	half = clampi(h, 0, 10)
	px = size_px
	add_theme_constant_override("separation", int(px * 0.18))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 5:
		add_child(_star(clampi(half - i * 2, 0, 2)))
	return self


## fill: 0 leer, 1 halb, 2 voll.
func _star(fill: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(px, px)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := U.icon("star", px, "faint" if fill == 0 else "accent")
	U.full_rect(outline)
	cell.add_child(outline)
	if fill > 0:
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.size = Vector2(px * (0.5 if fill == 1 else 1.0), px)
		clip.custom_minimum_size = clip.size
		cell.add_child(clip)
		var full := U.icon("star_f", px, "accent")
		full.position = Vector2.ZERO
		full.size = Vector2(px, px)
		clip.add_child(full)
	return cell

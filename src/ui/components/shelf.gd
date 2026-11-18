extends ScrollContainer
## Waagerechte Reihe (Cover, Karten). Folgt dem Fokus weich; das fokussierte Element
## bleibt links stehen, wie man es von Konsolen kennt.

var row: HBoxContainer
var gutter := 96


func setup(group: String, gap := 24, anchor := true, pad_v := 24, side := 96, pad_b := -1) -> ScrollContainer:
	gutter = side
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_meta("uz_group", group)
	set_meta("uz_mem", true)
	if anchor:
		set_meta("uz_anchor", float(side))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_theme_constant_override("margin_top", pad_v)
	m.add_theme_constant_override("margin_bottom", pad_v if pad_b < 0 else pad_b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	return self


func add(item: Control) -> Control:
	row.add_child(item)
	return item


func items() -> Array:
	return row.get_children()

extends "res://src/ui/layers/modal.gd"
## Meldung mit Knöpfen. buttons = [["Text", Callable, "danger"?], ...]; jeder Knopf schließt den
## Dialog. Der erste Knopf ist der helle Hauptknopf. Ein Knopf mit "danger" (Löschen, Entfernen)
## ist rot getönt, und die Auswahl liegt dann zuerst auf dem sicheren Knopf. Ein Knopf mit "start" bekommt
## die Auswahl, auch wenn er nicht vorn steht – für Dialoge, die von selbst kommen (Anklopfen).
## Mit icon_name steht ein Zeichen in einem weichen Kreis über dem Titel; bei Startfehlern
## („… startet nicht“) setzt Uzai es selbst.

var heading := ""
var text := ""
var buttons: Array = []
var icon_name := ""
var tone := ""                  ## "warn" oder "danger" färbt das Zeichen

const Liste := preload("res://src/ui/components/liste.gd")


func fill() -> void:
	width = 820.0
	# Etwas mehr Ruhe dahinter, und die Fläche bekommt den feinen Rand der anderen Ebenen.
	dim = 0.74
	if _scrim:
		_scrim.color = Color(UzTheme.col("bg"), dim)
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 44
	sb.content_margin_bottom = 40
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 44
	sb.shadow_offset = Vector2(0, 14)
	panel.add_theme_stylebox_override("panel", sb)
	var ic := icon_name
	var tn := tone
	if ic == "" and heading.ends_with("startet nicht"):
		ic = "warning"
		tn = "warn"
	var has_danger := buttons.any(func(b): return b is Array and (b as Array).size() > 2 and str(b[2]) == "danger")
	if ic == "" and has_danger:
		ic = "trash"
		tn = "danger"
	var strict := UzTheme.strict()
	if ic != "":
		box.add_child(_badge(ic, tn))
	# Überschrift wie im Guide und in den Blättern: Titelschrift.
	var h := U.label(heading, "xl", "text", "title" if strict else "black", true)
	h.custom_minimum_size = Vector2(width - 96.0, 0)
	box.add_child(h)
	if text != "":
		var t := U.label(text, "m", "muted", "regular", true)
		t.custom_minimum_size = Vector2(width - 96.0, 0)
		box.add_child(t)
	box.add_child(U.spacer(0, 10, false))
	var row := U.hbox(14)
	box.add_child(row)
	var default_set := false
	var start_i := start_knopf(buttons)
	for i in buttons.size():
		var spec: Array = buttons[i]
		var danger := spec.size() > 2 and str(spec[2]) == "danger"
		var b: Button
		if strict:
			# Eckig (Marke): ruhige Knöpfe mit Haarlinie, gewählt derselbe Rahmen wie überall;
			# „Entfernen“ trägt nur rote Schrift – keine rote Fläche, kein zweiter Cursor.
			b = Liste.knopf(str(spec[0]), "", "danger" if danger else ("primary" if i == 0 else ""))
		elif danger:
			b = _danger_button(str(spec[0]))
		else:
			b = U.button(str(spec[0]), "", "primary" if i == 0 else "normal")
		var cb: Callable = spec[1]
		b.pressed.connect(func() -> void:
			close()
			if cb.is_valid():
				cb.call()
		)
		# Startauswahl: der Knopf mit "start", sonst der erste, der nichts zerstört.
		if not default_set and not danger and (start_i < 0 or i == start_i):
			b.set_meta("uz_default", true)
			default_set = true
		row.add_child(b)


## Nummer des Knopfs mit "start" (−1 ohne).
static func start_knopf(liste: Array) -> int:
	for i in liste.size():
		if liste[i] is Array and (liste[i] as Array).size() > 2 and str(liste[i][2]) == "start":
			return i
	return -1


## Zeichen in einem weich getönten Kreis; eckig (Marke) frei über dem Titel, ohne Fläche.
func _badge(ic: String, tn: String) -> Control:
	var col := "danger_text" if tn == "danger" else ("warn" if tn == "warn" else "text")
	if UzTheme.strict():
		var free := U.icon(ic, 32, col if tn != "" else "muted")
		free.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		return free
	var bg := UzTheme.col("danger", 0.16) if tn == "danger" else (UzTheme.col("warn", 0.14) if tn == "warn" else UzTheme.col("glass_hi"))
	var c := Control.new()
	c.custom_minimum_size = Vector2(64, 64)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: c.draw_circle(Vector2(32, 32), 32.0, bg, true, -1.0, true))
	var icon := U.icon(ic, 30, col)
	icon.position = Vector2(17, 17)
	c.add_child(icon)
	return c


## Rot getönter Pillenknopf für Handlungen, die etwas entfernen. Gewählt wird er kräftig rot.
func _danger_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 56)
	var sb := UzTheme.box(UzTheme.col("danger", 0.16), 999)
	sb.content_margin_left = 30
	sb.content_margin_right = 32
	var fo := UzTheme.box(UzTheme.col("danger"), 999)
	fo.content_margin_left = 30
	fo.content_margin_right = 32
	fo.shadow_color = UzTheme.col("danger", 0.35)
	fo.shadow_size = 14
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", fo)
	b.add_theme_stylebox_override("pressed", fo)
	b.add_theme_stylebox_override("focus", fo)
	b.add_theme_font_override("font", UzTheme.ui("ui_bold"))
	b.add_theme_color_override("font_color", UzTheme.col("danger_text"))
	for k in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	return b

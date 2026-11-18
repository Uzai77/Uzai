extends RefCounted
## Kleine Vorschauen für die rechte Spalte der Einstellungen: Was eine Wahl bewirkt, sieht man,
## statt es nur zu lesen. Farbschemata, Ecken, Cover-Form und -Größe, Schrift, Uhr,
## Startanimation, Akzentfarbe, ein Pfad in voller Länge und kleine Wertetabellen.

const U := preload("res://src/ui/u.gd")
const Boot := preload("res://src/ui/boot.gd")
const SystemIntro := preload("res://src/ui/components/system_intro.gd")


## Alle Farbschemata als kleine Fenster; das gewählte hat einen hellen Ring.
static func themes(current: String) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in UzTheme.PRESETS.keys():
		var pr: Dictionary = UzTheme.PRESETS[id]
		var on := str(id) == current
		var cell := U.hbox(14)
		cell.add_child(mini_fenster(pr, on))
		var l := U.label(str(pr.name), "s", "text" if on else "muted", "medium" if on else "regular")
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(l)
		grid.add_child(cell)
	return grid


## Ein Farbschema als kleines Fenster (Grund, Karte, Cursor, Text, Akzent). pr: Rollen wie in
## UzTheme.PRESETS, als Farbe oder „#rrggbb“. Auch in der Auswahlliste (choice_list.gd).
static func mini_fenster(pr: Dictionary, on := false, groesse := Vector2(76, 50)) -> Control:
	var mini := Control.new()
	mini.custom_minimum_size = groesse
	mini.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.draw.connect(func() -> void: _draw_mini_window(mini, pr, on))
	return mini


static func _farbe(v: Variant) -> Color:
	return v if v is Color else Color(str(v))


static func _draw_mini_window(c: Control, pr: Dictionary, on: bool) -> void:
	var r := Rect2(Vector2(3, 3), c.size - Vector2(6, 6))
	if on:
		c.draw_style_box(UzTheme.box(Color(0, 0, 0, 0), 13, 2, UzTheme.col("focus")), r.grow(3))
	# Kein Rand in der Linienfarbe (wirkte wie ein heller Strich): ein weicher Schatten hebt das Fenster ab.
	var win := UzTheme.box(_farbe(pr.bg), 10)
	win.shadow_color = Color(0, 0, 0, 0.4)
	win.shadow_size = 8
	win.shadow_offset = Vector2(0, 3)
	c.draw_style_box(win, r)
	var card := Rect2(r.position + Vector2(7, 7), Vector2(r.size.x - 14, r.size.y - 14))
	c.draw_style_box(UzTheme.box(_farbe(pr.surface), 6), card)
	c.draw_style_box(UzTheme.box(_farbe(pr.get("focus", pr.text)), 4), Rect2(card.position + Vector2(5, 5), Vector2(card.size.x * 0.62, 9)))
	c.draw_rect(Rect2(card.position + Vector2(6, 19), Vector2(card.size.x * 0.45, 3)), _farbe(pr.muted))
	c.draw_circle(card.end - Vector2(8, 7), 3.2, _farbe(pr.accent))


## Drei Möglichkeiten nebeneinander (Ecken, Cover-Form, Cover-Größe); die gewählte ist hell.
static func shapes(what: String, current: String) -> Control:
	var specs: Array = []
	match what:
		"corners":
			# Wie große Flächen: Rundung × 1,6 (so groß wirkt sie auf Karten und Covern).
			specs = [["eckig", "Eckig", Vector2(132, 92), 5.0], ["leicht", "Leicht", Vector2(132, 92), 16.0], ["rund", "Rund", Vector2(132, 92), 26.0]]
		"cover_shape":
			specs = [["hoch", "Hochformat", Vector2(90, 120), -1.0], ["quer", "Querformat", Vector2(170, 80), -1.0], ["quadrat", "Quadrat", Vector2(104, 104), -1.0]]
		"cover_size":
			specs = [["s", "Klein", Vector2(74, 98), -1.0], ["m", "Mittel", Vector2(90, 120), -1.0], ["l", "Groß", Vector2(108, 144), -1.0]]
	var row := U.hbox(34)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for sp in specs:
		var on := str(sp[0]) == current
		var col := U.vbox(12)
		col.alignment = BoxContainer.ALIGNMENT_END
		var box := Control.new()
		var sz: Vector2 = sp[2]
		box.custom_minimum_size = Vector2(maxf(sz.x, 96.0), 146)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rad: float = sp[3]
		box.draw.connect(func() -> void:
			var r := Rect2(Vector2((box.size.x - sz.x) * 0.5, box.size.y - sz.y), sz)
			var rr := int(rad if rad >= 0.0 else float(UzTheme.r_cover()))
			if on:
				box.draw_style_box(UzTheme.box(UzTheme.col("sel"), rr), r)
				box.draw_rect(Rect2(r.position + Vector2(10, r.size.y - 18), Vector2(r.size.x * 0.5, 5)), UzTheme.col("on_focus", 0.5))
			else:
				box.draw_style_box(UzTheme.box(UzTheme.col("glass_hi"), rr, 1, UzTheme.col("stroke")), r)
		)
		col.add_child(box)
		var l := U.label(str(sp[1]), "s", "text" if on else "faint", "medium")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		row.add_child(col)
	return row


## Ein Spieltitel und eine Zeile Text in der gewählten Schrift.
static func font_sample() -> Control:
	var col := U.vbox(6)
	var box := U.panel("glass", UzTheme.r_panel() - 8, 26)
	var inner := U.vbox(6)
	box.add_child(inner)
	var t := Label.new()
	t.text = "Shadow of the Colossus"
	t.add_theme_font_override("font", UzTheme.display("title"))
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", UzTheme.col("text"))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(t)
	inner.add_child(U.label("Weiterspielen · 14 Std. gespielt · zuletzt gestern", "m", "muted", "regular"))
	inner.add_child(U.label("0123456789 – Äpfel, Öfen, Übermut, Spaß", "s", "faint", "regular"))
	col.add_child(box)
	return col


## Die Uhr groß, so wie sie oben rechts steht.
static func clock() -> Control:
	var col := U.vbox(2)
	var l := Label.new()
	l.text = U.clock()
	l.add_theme_font_override("font", UzTheme.ui("ui_bold"))
	l.add_theme_font_size_override("font_size", 84)
	l.add_theme_color_override("font_color", UzTheme.col("text"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	return col


## Die Startanimation läuft klein und still in Schleife.
static func boot(mode: String) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(544, 306)
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color(0, 0, 0, 1), UzTheme.r_panel() - 6, 1, UzTheme.col("stroke")))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mode == "aus":
		var cc := CenterContainer.new()
		U.full_rect(cc)
		cc.add_child(U.label("Direkt zur Startseite.", "m", "faint", "medium"))
		frame.add_child(cc)
		return frame
	var b: Control = Boot.new()
	b.set("preview", true)
	b.call("setup", mode)
	frame.add_child(b)
	return frame


## Startanimationen je System-Familie, eine nach der anderen in Schleife.
static func system_intro() -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(544, 306)
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color(0, 0, 0, 1), UzTheme.r_panel() - 6, 1, UzTheme.col("stroke")))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var si: Control = SystemIntro.new()
	si.set("preview", true)
	U.full_rect(si)
	frame.add_child(si)
	return frame


## Die Akzentfarbe an den Stellen, an denen sie vorkommt.
static func accent(c: Color) -> Control:
	var row := U.hbox(26)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(84, 84)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.draw.connect(func() -> void:
		# Marke: ein gerundetes Farbfeld mit Haarlinie wie in den Zeilen.
		if UzTheme.strict():
			UzTheme.draw_hairline(sw, Rect2(sw.size * 0.5 - Vector2(40, 40), Vector2(80, 80)), UzTheme.r_panel(), c)
			return
		sw.draw_circle(sw.size * 0.5, 40.0, c, true, -1.0, true)
		sw.draw_arc(sw.size * 0.5, 40.0, 0, TAU, 48, UzTheme.col("text", 0.2), 1.5, true)
	)
	row.add_child(sw)
	var demo := Control.new()
	demo.custom_minimum_size = Vector2(300, 84)
	demo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	demo.draw.connect(func() -> void:
		var f := UzTheme.ui("ui")
		demo.draw_string(f, Vector2(0, 26), TranslationServer.translate("Erfolge"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UzTheme.col("text"))
		demo.draw_rect(Rect2(2, 36, 34, 3), c)
		demo.draw_string(f, Vector2(110, 26), TranslationServer.translate("38 / 52"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UzTheme.col("muted"))
		demo.draw_style_box(UzTheme.box(UzTheme.col("text", 0.12), 3), Rect2(0, 62, 280, 6))
		demo.draw_style_box(UzTheme.box(c, 3), Rect2(0, 62, 280 * 0.73, 6))
	)
	row.add_child(demo)
	return row


## Ein Pfad in voller Länge (die Zeile links kürzt ihn) und ein kurzer Satz dazu.
static func path_box(p: String, note := "") -> Control:
	var col := U.vbox(10)
	if p != "":
		var box := U.panel("glass", UzTheme.radius + 2, 18)
		var row := U.hbox(14)
		box.add_child(row)
		var ic := U.icon("folder" if p.get_extension() == "" else "file", 24, "muted")
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var l := U.label(p.replace("/", "/​").replace("\\", "\\​"), "s", "text", "medium", true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		col.add_child(box)
	if note != "":
		col.add_child(U.label(note, "s", "muted", "regular", true))
	return col


## Kleine Tabelle: [[Bezeichnung, Wert], …].
static func table(rows: Array) -> Control:
	var col := U.vbox(0)
	for i in rows.size():
		var r: Array = rows[i]
		var line := U.hbox(20)
		var m := U.margin(0, 9, 0, 9)
		m.add_child(line)
		var k := U.label(str(r[0]), "m", "muted", "regular")
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(k)
		var v := U.label(str(r[1]), "m", "text", "medium")
		v.clip_text = false
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(v)
		col.add_child(m)
		if i < rows.size() - 1:
			var sep := ColorRect.new()
			sep.color = UzTheme.col("text", 0.07)
			sep.custom_minimum_size = Vector2(0, 1)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(sep)
	return col

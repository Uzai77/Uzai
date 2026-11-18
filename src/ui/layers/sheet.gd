extends "res://src/ui/layers/layer.gd"
## Seitenleiste von rechts mit Überschrift und einer Liste (Optionen, Auswahl, Details). Mit links
## (vor build setzen) kommt sie gespiegelt von links (Freunde auf Select, freunde_leiste.gd).

var heading := ""
var heading_raw := false     ## Überschrift ist ein eigener Name (Liste, Ordner): nie übersetzen
var subheading := ""
var subheading_raw := false  ## Zusatz ist ein eigener Name (Spiel, Künstler): nie übersetzen
var width := 760.0
var panel: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var _header_extra: Control
var fill_func: Callable
var _edge: TextureRect
var _edge_unten: TextureRect
## Erklärzeile unten (Einstellungen): zeigt, was die gewählte Zeile tut. Vor dem Öffnen setzen.
var help_on := false
var _help_l: Label
## Von links statt von rechts: Anker, Schatten, Rundung, Kante und Flug gespiegelt.
var links := false

const Liste := preload("res://src/ui/components/liste.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")

## Höhe des weichen Auslaufs oben in der Liste.
const EDGE := 40.0
## Leiste von links: Platz für ihre eigenen Tastenhinweise unten (wie im Guide, guide.gd FOOT_H).
const FUSS_H := 88.0
## So weit gleitet die Leiste beim Schließen zurück nach rechts (sie blendet dabei aus).
const W_ZU := 48.0


func setup(h: String, sub := "", w := 760.0) -> Control:
	heading = h
	subheading = sub
	width = w
	return self


func build() -> void:
	# Mitteilungen erscheinen links unten, nicht über der Liste (siehe toasts.gd); liegt die Leiste
	# links, stehen sie wie sonst rechts.
	if not links:
		set_meta("uz_toast_spot", "left")
	panel = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), 0)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 52
	sb.content_margin_bottom = 110 if not links else 0
	# Schwebt (Höhenstufe 3) mit weichem Schatten und zum Bild hin runden Ecken. Keine helle Kante:
	# die sah am Fernseher wie ein weißer Strich aus; der Schatten trennt die Leiste genug.
	UzTheme.lift(sb, 3)
	sb.shadow_offset = Vector2(8 if links else -8, 0)
	if links:
		sb.corner_radius_top_right = UzTheme.r_panel()
		sb.corner_radius_bottom_right = UzTheme.r_panel()
	else:
		sb.corner_radius_top_left = UzTheme.r_panel()
		sb.corner_radius_bottom_left = UzTheme.r_panel()
	# Eckig (Marke): ein Blatt wie der Guide – matt, eckig, eine Haarlinie an der Kante zum Bild.
	if UzTheme.strict():
		sb.set_corner_radius_all(0)
		if links:
			sb.border_width_right = 1
		else:
			sb.border_width_left = 1
		sb.border_color = UzTheme.col("line")
	panel.add_theme_stylebox_override("panel", sb)
	# Material „Kernlicht“: Licht von oben, ein Hauch Akzent, Lichtkante, Korn (nicht im leichten Modus).
	UzTheme.kernlicht(panel)
	panel.anchor_bottom = 1.0
	if links:
		panel.offset_right = width
	else:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.offset_left = -width
	add_child(panel)
	var col := U.vbox(18)
	panel.add_child(col)
	var head := U.hbox(18)
	col.add_child(head)
	if _header_extra:
		head.add_child(_header_extra)
	var titles := U.vbox(4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	# Überschrift wie im Guide: Titelschrift, darunter leise der Zusatz.
	var strict := UzTheme.strict()
	var t := U.label(heading, "xl", "text", "title" if strict else "bold", true)
	if heading_raw:
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	titles.add_child(t)
	if subheading != "":
		var st := U.label(subheading, "s" if strict else "m", "muted", "regular", true)
		if subheading_raw:
			st.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		titles.add_child(st)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = false
	scroll.set_meta("uz_pad_v", 80.0)
	# Die Liste läuft oben weich aus, sobald sie gescrollt ist (statt hart unter dem Titel
	# abgeschnitten zu werden), und unten, solange darunter noch Zeilen folgen: Der Verlauf hinter
	# den Hinweisen beginnt erst unter der Liste, die letzte Zeile war mitten durchgeschnitten.
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(frame)
	U.full_rect(scroll)
	frame.add_child(scroll)
	_edge = TextureRect.new()
	_edge.texture = U.fade_texture(true)
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.anchor_right = 1.0
	_edge.offset_bottom = EDGE
	_edge.modulate = Color(UzTheme.col("surface"), 0.0)
	frame.add_child(_edge)
	_edge_unten = TextureRect.new()
	_edge_unten.texture = U.fade_texture(true, true)
	_edge_unten.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge_unten.stretch_mode = TextureRect.STRETCH_SCALE
	_edge_unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_unten.anchor_top = 1.0
	_edge_unten.anchor_bottom = 1.0
	_edge_unten.anchor_right = 1.0
	_edge_unten.offset_top = -EDGE * 1.5
	_edge_unten.modulate = Color(UzTheme.col("surface"), 0.0)
	frame.add_child(_edge_unten)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_edge())
	kante_unten_fuer(scroll)
	if help_on:
		var hm := U.margin(8, 4, 8, 0)
		_help_l = U.label("", "s", "muted", "regular", true)
		_help_l.custom_minimum_size.y = 64
		_help_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		hm.add_child(_help_l)
		col.add_child(hm)
	if links:
		# Von links: Die Tasten stehen unten in der Leiste (wie im Guide) – die Hinweise des
		# Hauptfensters lägen rechts unten über dem Bild daneben, außerhalb der Leiste.
		set_meta("uz_hints_eigen", true)
		# Der Auslauf unten (main.gd) läge über diesen Hinweisen; die Liste endet ohnehin darüber.
		set_meta("uz_ohne_auslauf", true)
		var fuss := Control.new()
		fuss.custom_minimum_size.y = FUSS_H
		fuss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hb := HintBar.new()
		hb.inside = true
		hb.gap = 18
		hb.anchor_right = 1.0
		hb.anchor_top = 0.5
		hb.anchor_bottom = 0.5
		hb.offset_left = 8.0
		hb.offset_right = -8.0
		hb.grow_vertical = Control.GROW_DIRECTION_BOTH
		fuss.add_child(hb)
		col.add_child(fuss)
		hb.refresh.call_deferred(true)
	var pad := U.margin(8, 8, 8, 8)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	content = U.vbox(6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	fill()


## Fläche vor Schrift (layer.gd): die Leiste kommt deckend von rechts, ihre Schrift danach.
func flaeche() -> Control:
	return panel


## Die Leiste gleitet W_LEISTE von rechts (links: von links) herein (Raumwechsel, T_RAUM), in
## ganzen Pixeln mit sauberem Schluss (U.px_schluss); ruhig steht sie gleich.
func _enter_motion(_fl: Control) -> void:
	var w := U.weg_px(U.W_LEISTE)
	if w == 0.0:
		return
	var p := panel
	var b := width
	var setzen := func(v: float) -> void:
		p.offset_left = -v if links else -b + v
		p.offset_right = b - v if links else v
	setzen.call(w)
	U.px_weg(U.ankommen(panel, U.T_RAUM, "uz_leiste"), panel, "uz_px_leiste", w, U.T_RAUM, setzen)


func _exit_motion(tw: Tween) -> void:
	U.stop(panel, "uz_leiste")
	var w := U.weg_px(W_ZU)
	tw.set_parallel(true)
	tw.tween_property(panel, "offset_left", -w if links else -width + w, U.T_WEG)
	tw.tween_property(panel, "offset_right", width - w if links else w, U.T_WEG)


## Weicher Auslauf oben: erscheint, sobald die Liste nicht mehr ganz oben steht.
func _update_edge() -> void:
	if not is_instance_valid(_edge) or not is_instance_valid(scroll):
		return
	var a := clampf(float(scroll.scroll_vertical) / EDGE, 0.0, 1.0)
	_edge.modulate = Color(UzTheme.col("surface"), a)


## Der weiche Auslauf unten folgt diesem Bildlauf: zu sehen, solange darunter noch etwas kommt.
## Die eigene Liste ruft es selbst; ein Bereich mit eigenem Bildlauf in der Leiste (Freunde) meldet
## seinen nach jedem Aufbau.
func kante_unten_fuer(sc: ScrollContainer) -> void:
	var bar := sc.get_v_scroll_bar()
	var zeigen := func(_v: float = 0.0) -> void:
		if is_instance_valid(_edge_unten):
			var rest := float(bar.max_value - bar.page - bar.value)
			_edge_unten.modulate = Color(UzTheme.col("surface"), clampf(rest / EDGE, 0.0, 1.0))
	bar.value_changed.connect(zeigen)
	bar.changed.connect(zeigen)            # Inhalt gefüllt oder gewachsen
	zeigen.call()


## Erklärung zur gewählten Zeile unten in der Leiste (nur mit help_on).
func set_help(text: String) -> void:
	if is_instance_valid(_help_l):
		_help_l.text = text


func set_header_image(c: Control) -> void:
	_header_extra = c


## Inhalt eintragen (überschreiben oder fill_func setzen).
func fill() -> void:
	if fill_func.is_valid():
		fill_func.call(self)


func add_row(c: Control) -> Control:
	content.add_child(c)
	return c


## Ein Etikett in der Liste. Kurz und ohne Punkt (mit den Vorgaben) ist es ein Abschnitt: im
## eckigen Theme (Marke) in kleinen Versalien wie im Guide; sonst ein leiser Satz.
func add_label(text: String, size := "s", color := "faint") -> Label:
	if UzTheme.strict() and size == "s" and color == "faint" and is_section_text(text):
		var row := Liste.abschnitt(text)
		var hm := U.margin(4, 6, 0, 2)
		hm.add_child(row)
		content.add_child(hm)
		return row.get_child(0) as Label
	var l := U.label(text, size, color, "medium", true)
	content.add_child(l)
	return l


## Abschnitt statt Satz: kurz, einzeilig, ohne Punkt oder Auslassung am Ende.
static func is_section_text(text: String) -> bool:
	var t := text.strip_edges()
	return t != "" and t.length() <= 34 and not t.contains("\n") and not t.ends_with(".") and not t.ends_with("…") and not t.ends_with(":")


## Luft zwischen Gruppen; die übliche (14) ist im eckigen Theme eine Haarlinie wie im Guide.
func add_gap(h := 14) -> void:
	if h == 14 and UzTheme.strict():
		content.add_child(Liste.linie(10))
		return
	content.add_child(U.spacer(0, h, false))


func refill() -> void:
	var keep := Nav.focused()
	var idx := -1
	if keep and content.is_ancestor_of(keep):
		idx = Nav.focusables(content).find(keep)
	U.clear(content)
	fill()
	await get_tree().process_frame
	if idx >= 0:
		var items := Nav.focusables(content)
		if not items.is_empty():
			Nav.focus(items[mini(idx, items.size() - 1)], true)

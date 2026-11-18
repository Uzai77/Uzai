extends "res://src/ui/layers/sheet.gd"
## Auswahl aus einer Liste. options = [[wert, "Text", "Zusatz"?, { avatar, status }?], ...] – mit dem
## vierten Eintrag steht links das Profilbild (Freunde) oder, mit { farben }, ein kleines Fenster in
## den Farben eines Farbschemas (die Liste liegt über der Vorschau der Einstellungen); sonst nur Text.
## Jede Zeile hat rechts einen runden Auswahlpunkt; der aktuelle Wert ist gefüllt. Alle Titel
## stehen bündig untereinander, und die Leiste ist nur so breit, wie die Texte es brauchen.

signal picked(value: Variant)

## Sehr lange Listen (Mosaik › „Spiel hinzufügen“: eine Zeile je Spiel der Bibliothek) bauen die ersten Zeilen
## sofort und den Rest in Scheiben (U.in_scheiben). Gemessen in einem Zug: 1000 Zeilen 0,25 s, 3000 Zeilen 1,4 s.
const ZEILEN_SOFORT := 30
const ZEILEN_JE_BILD := 40
const MESSEN_ALLE := 200        ## bis zu so vielen Einträgen wird jeder für die Breite gemessen

var options: Array = []
var value: Variant = null


func build() -> void:
	# Breite nach dem längsten Eintrag (mit Luft für Punkt und Ränder), nie breiter als vorgesehen – ist die
	# größte Breite erreicht, braucht es die übrigen Einträge nicht mehr.
	var f := UzTheme.ui("ui")
	var w := f.get_string_size(tr(heading), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("xl")).x
	# Sehr lange Listen: nur die Einträge mit den meisten Zeichen messen (3000 Messungen kosteten rund 60 ms).
	var ab := 0
	if options.size() > MESSEN_ALLE:
		for o in options:
			ab = maxi(ab, str(o[1]).length())
		ab -= 3
	for o in options:
		if w + 120.0 >= width:
			break
		if str(o[1]).length() < ab:
			continue
		var bild := 0.0
		if o.size() > 3 and o[3] is Dictionary:
			bild = 86.0 if (o[3] as Dictionary).has("farben") else 62.0
		w = maxf(w, f.get_string_size(tr(str(o[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x + 120.0 + bild)
	width = clampf(w + 120.0, 560.0, width)
	super()


func fill() -> void:
	var baue := func(i: int) -> Control:
		var o: Array = options[i]
		var v: Variant = o[0]
		var it := _Option.new()
		it.title = str(o[1])
		it.sub = str(o[2]) if o.size() > 2 else ""
		it.person = o[3] if o.size() > 3 and o[3] is Dictionary else {}
		it.selected = v == value
		if it.selected:
			it.set_meta("uz_default", true)
		it.activated.connect(func() -> void:
			picked.emit(v)
			close()
		)
		return it
	# Bis zum gewählten Wert ohne Pause: Auf ihm steht beim Öffnen die Auswahl.
	var bis := Callable()
	if options.any(func(o: Array) -> bool: return o[0] == value):
		bis = func(c: Node) -> bool: return c.has_meta("uz_default")
	U.in_scheiben(content, options.size(), baue, ZEILEN_SOFORT, ZEILEN_JE_BILD, bis)


## Eine Zeile mit Titel, leisem Zusatz und rundem Auswahlpunkt.
class _Option extends Control:
	signal activated

	const U := preload("res://src/ui/u.gd")
	const Liste := preload("res://src/ui/components/liste.gd")
	const Avatar := preload("res://src/ui/components/avatar.gd")
	const Preview := preload("res://src/ui/components/setting_preview.gd")

	var title := ""
	var sub := ""
	var selected := false
	var person := {}               ## { avatar, status }: Profilbild links; { farben }: Farbschema im Kleinen


	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		set_meta("uz_hint_a", "Auswählen")
		var m := U.margin(22, 12, 64, 12)
		U.full_rect(m)
		add_child(m)
		var col := U.vbox(2)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		if person.is_empty():
			m.add_child(col)
		else:
			var row := U.hbox(16)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.add_child(row)
			if person.has("farben"):
				# Etwas kleiner als in der Vorschau: Alle elf Schemata bleiben ohne Blättern zu sehen.
				row.add_child(Preview.mini_fenster(person.farben, false, Vector2(70, 46)))
			else:
				var av := Avatar.new()
				av.setup(title, str(person.get("avatar", "")), str(person.get("status", "")), 46)
				av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(av)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(col)
		col.add_child(U.ellipsis(U.label(title, "m", "text", "ui_bold" if selected else "ui")))
		if sub != "":
			col.add_child(U.ellipsis(U.label(sub, "s", "muted", "regular")))
		custom_minimum_size.y = maxf(66.0, m.get_combined_minimum_size().y)
		focus_entered.connect(func() -> void:
			U.etikett(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			U.etikett(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		var c := Vector2(size.x - 36.0, size.y * 0.5)
		# Eckig (Marke): der Zeilen-Cursor wie im Guide; der gewählte Wert trägt ein Häkchen im
		# Akzent, die anderen nichts – keine Kreise.
		if UzTheme.strict():
			Liste.zeilen_auswahl(self)
			if selected:
				var px := 24.0
				draw_texture_rect(Icons.tex("check", int(px)), Rect2(c - Vector2(px, px) * 0.5, Vector2(px, px)), false, UzTheme.col("accent"))
			return
		U.draw_focus(self)
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		var dark := UzTheme.col("on_focus")
		if selected:
			draw_circle(c, 13.0, UzTheme.col("accent").lerp(dark, f), true, -1.0, true)
			var ck := UzTheme.text_on(UzTheme.col("accent")).lerp(UzTheme.col("sel"), f)
			draw_polyline(PackedVector2Array([c + Vector2(-5.5, 0.5), c + Vector2(-1.5, 4.5), c + Vector2(6, -4)]), ck, 2.6, true)
		else:
			draw_arc(c, 12.0, 0, TAU, 40, UzTheme.col("faint").lerp(Color(dark, 0.55), f), 2.0, true)

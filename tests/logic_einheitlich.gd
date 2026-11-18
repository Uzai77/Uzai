extends Node
## Einheitlich: eine Listen-Sprache überall (liste.gd). Tastenzeile (höchstens vier, B zuletzt),
## Abschnitt in Versalien, Haarlinie, Blatt-Etiketten (kurz = Abschnitt), der ruhige Knopf der
## Marke (echte gerundete Fläche, gewählt hell mit dunkler Schrift, ohne Linie), der Zeilen-Cursor
## (gefüllte gerundete Fläche, Schrift bleibt hell), Schalter der
## Einstellungen mit „An“/„Aus“, und der Guide baut seine Abschnitte aus denselben Teilen.
## Aufruf: godot --headless --path . res://tests/logic_einheitlich.tscn

const Liste := preload("res://src/ui/components/liste.gd")
const U := preload("res://src/ui/u.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const GuideBasis := preload("res://src/ui/layers/guide_basis.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Tastenzeile")
	var h := [[["a"], "Öffnen"], [["b"], "Zurück"], [["x"], "Suchen"], [["y"], "Optionen"], [["lb", "rb"], "Seite"]]
	var t := Liste.tasten_ordnen(h)
	check(t.size() == 4, "höchstens vier Hinweise (%d)" % t.size())
	check((t.back() as Array)[0] == ["b"], "B zuletzt")
	check(t.map(func(e): return e[0][0]) == ["a", "x", "y", "b"], "Reihenfolge A, X, Y, B – was zu viel ist, fällt hinten weg")
	check(Liste.tasten_ordnen([[["a"], "Spielen"]]).size() == 1, "ohne B bleibt es, wie es ist")

	print("Abschnitt und Haarlinie")
	var ab := Liste.abschnitt("Im Spiel", "6")
	var l0 := ab.get_child(0) as Label
	check(l0.uppercase and l0.text == "Im Spiel" and ab.get_child_count() == 2, "Etikett in Versalien, Zusatz dahinter")
	check(l0.get_theme_font_size("font_size") == UzTheme.size("cap"), "15 px (cap), nicht kleiner")
	var li := Liste.linie(10)
	check(li.get_child_count() == 3 and (li.get_child(1) as ColorRect).custom_minimum_size.y == 1.0, "Haarlinie: 1 px mit Luft darüber und darunter")
	ab.free()
	li.free()

	print("Blätter: kurze Etiketten sind Abschnitte")
	check(Sheet.is_section_text("Start") and Sheet.is_section_text("Außerhalb von Uzai"), "kurz und ohne Punkt: Abschnitt")
	check(not Sheet.is_section_text("Nur https. Uzai zeigt Links als QR-Code und öffnet sie nie selbst."), "Satz bleibt Satz")
	check(not Sheet.is_section_text("Freunde werden geladen …"), "mit Auslassung: kein Abschnitt")

	print("Ruhiger Knopf der Marke (Graphit): Fläche, weich gerundet, gewählt hell")
	check(UzTheme.strict() and UzTheme.cursor_frame(), "Graphit: eine Form und der Cursor der Marke")
	check(UzTheme.radius >= 8 and UzTheme.radius <= 12 and UzTheme.r_panel() >= 12 and UzTheme.r_panel() <= 16
			and UzTheme.r_cover() >= 10 and UzTheme.r_cover() <= 16, "weich gerundet: Zeilen %d, Karten %d, Cover %d" % [UzTheme.radius, UzTheme.r_panel(), UzTheme.r_cover()])
	check(UzTheme.box(Color.BLACK, 40).corner_radius_top_left == UzTheme.r_max() and UzTheme.box(Color.BLACK, 999).corner_radius_top_left >= 900,
			"feste Rundungen höchstens wie eine Karte, Pillen bleiben Pillen")
	var b := U.button("Behalten", "play", "primary")
	var nb := b.get_theme_stylebox("normal") as StyleBoxFlat
	check(b.get_theme_stylebox("focus") is StyleBoxEmpty, "gewählt: keine Linie, die Fläche selbst ist der Cursor")
	check(nb != null and nb.border_width_left == 0 and nb.border_width_right == 0 and nb.border_width_bottom == 0 and nb.corner_radius_top_left >= 900
			and nb.bg_color.is_equal_approx(UzTheme.col("accent")), "Hauptknopf ruht als Pille im Akzent, ohne Rahmen")
	check(nb != null and nb.border_width_top == 1 and nb.border_color.a >= 0.999 and nb.border_color.get_luminance() > nb.bg_color.get_luminance(),
			"Lichtkante oben: eine Spur heller als die Fläche, deckend (keine hellen Pixel an den Rundungen)")
	check(nb != null and nb.shadow_size > 0 and nb.shadow_color.a > 0.0, "Haupthandlung ruht gehoben (weicher Schatten schon in Ruhe)")
	check(b.get_theme_color("font_color").get_luminance() < 0.3, "Hauptknopf: dunkle Schrift auf dem Akzent")
	U.knopf_stand(b, 1.0)
	check(nb.bg_color.is_equal_approx(UzTheme.col("focus")) and b.get_theme_color("font_focus_color").get_luminance() < 0.3 and nb.shadow_size > 0,
			"gewählt: hell gefüllt, dunkle Schrift, weicher Schatten")
	b.free()
	var n2 := U.button("Optionen", "more")
	var nb2 := n2.get_theme_stylebox("normal") as StyleBoxFlat
	check(nb2.bg_color.a > 0.99 and nb2.border_width_left == 0 and nb2.border_width_bottom == 0 and n2.get_theme_color("font_color").get_luminance() > 0.6,
			"Nebenknopf: deckende Fläche (nie Wort mit bloßem Rahmen), Schrift hell")
	check(nb2.shadow_size == 0, "Nebenknopf ruht flach – gehoben ruht nur die Haupthandlung")
	n2.free()
	var d := Liste.knopf("Entfernen", "", "danger")
	check(d.get_theme_color("font_color") == UzTheme.col("danger_text") and d.get_theme_stylebox("focus") is StyleBoxEmpty,
			"Löschen: rote Schrift, derselbe Cursor")
	d.free()
	check(UzTheme.col("sel").get_luminance() > UzTheme.col("surface_hi").get_luminance() + 0.05 and UzTheme.col("on_focus").get_luminance() > 0.6,
			"Zeilen-Cursor: heller Graphit, Schrift bleibt hell")

	print("Schalter der Einstellungen wie im Guide")
	var row = SettingRow.new()
	row.setup("toggle", "Favorit", "", true)
	add_child(row)
	row.size = Vector2(700, 72)
	row.call("_layout_value")
	var va: Control = row.get("_va")
	check(va.custom_minimum_size.x > SettingRow.SW_ECKIG.x + 14.0, "Platz für „An“/„Aus“ vor dem eckigen Schalter")
	row.queue_free()

	print("Der Guide baut aus denselben Teilen")
	var g = GuideBasis.new()
	var gs: HBoxContainer = g.call("_section", "Musik")
	check((gs.get_child(0) as Label).uppercase and (gs.get_child(0) as Label).get_theme_font("font") == Liste.caps_font(), "Abschnitt im Guide = Liste.abschnitt")
	gs.free()
	g.free()

	print("")
	# „Systemschrift“ (Einstellungen › Aussehen › Schrift): Jede Stärke braucht ihre eigene Systemschrift – teilen
	# sich alle eine, gewinnt die zuletzt gesetzte Stärke und alles steht fett da.
	print("Systemschrift")
	var schrift_vorher := str(Config.get_value("theme.font", "theme"))
	Config.set_value("theme.font", "system")
	var basen := {}
	for f: Font in [UzTheme.font_regular, UzTheme.font_medium, UzTheme.font_bold, UzTheme.font_black]:
		var bf: Font = (f as FontVariation).base_font
		if bf is SystemFont:
			basen[bf.get_instance_id()] = (bf as SystemFont).font_weight
	var gewichte: Array = basen.values()
	gewichte.sort()
	check(basen.size() == 4 and gewichte == [400, 560, 700, 800], "vier Stärken, vier Schriften mit 400, 560, 700, 800 (%s)" % str(gewichte))
	var wn := UzTheme.font_regular.get_string_size("Einstellungen", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var wf := UzTheme.font_black.get_string_size("Einstellungen", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	print("       Breite normal %.0f, fett %.0f (gleich, wenn der Rechner nur einen Schnitt hat)" % [wn, wf])
	Config.set_value("theme.font", schrift_vorher)

	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

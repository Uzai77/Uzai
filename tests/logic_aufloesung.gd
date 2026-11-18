extends Node
## Logik für „Alle Auflösungen“ (Punkt 63): Rasterspalten nach Fensterbreite, Guide-Karte bei
## höheren Fenstern mittig, Größe der Oberfläche begrenzt. Dazu „Größe der Oberfläche“ bis 150 %:
## knappe Höhe (U.tight/by_room), Guide eingepasst, Vorschauen verkleinert (fit_box.gd), Leisten
## gleiten mit der Auswahl (strip_pan.gd), Neuaufbau erst, wenn der Regler ruht.
## Aufruf: godot --headless --path . res://tests/logic_aufloesung.tscn

const U := preload("res://src/ui/u.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const FitBox := preload("res://src/ui/components/fit_box.gd")
const StripPan := preload("res://src/ui/components/strip_pan.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _pan_test() -> void:
	var host := Control.new()
	host.size = Vector2(400, 60)
	add_child(host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var items: Array = []
	for i in 8:
		var b := Button.new()
		b.custom_minimum_size = Vector2(100, 40)
		b.focus_mode = Control.FOCUS_ALL
		row.add_child(b)
		items.append(b)
	var pan := StripPan.new().hold(row)
	host.add_child(pan)
	pan.size = Vector2(400, 60)
	await get_tree().process_frame
	await get_tree().process_frame
	check(pan.get_combined_minimum_size().x == 0.0, "fordert keine Breite (die Seite bleibt im Fenster)")
	check((items[0] as Control).modulate.a > 0.99 and (items[7] as Control).modulate.a < 0.01, "vorn sichtbar, was nicht passt, ausgeblendet")
	(items[6] as Control).grab_focus()
	for i in 60:
		await get_tree().process_frame
	var r := (items[6] as Control).get_global_rect()
	check(r.position.x >= host.global_position.x and r.end.x <= host.global_position.x + 400.0 + 0.5, "Auswahl rückt ins Bild")
	check((items[6] as Control).modulate.a > 0.99 and (items[0] as Control).modulate.a < 0.01, "dafür tritt der Anfang zurück")
	host.queue_free()


func _ready() -> void:
	print("Raster: Spalten nach Breite (logische Pixel)")
	check(U.cols_for(4, 96.0, 1920.0) == 4 and U.cols_for(8, 96.0, 1920.0) == 8, "1080p, 4K, 4:3, 16:10: wie gebaut")
	check(U.cols_for(4, 96.0, 2560.0) == 5 and U.cols_for(6, 96.0, 2560.0) == 8, "21:9 (2560 × 1080): mehr Spalten statt breiterer Kacheln")
	check(U.cols_for(6, 96.0, 2580.0) == 8, "3440 × 1440 ebenso")
	check(U.cols_for(4, 96.0, 1745.0) == 3, "Oberfläche 110 %: eine Spalte weniger statt Überlauf")
	check(U.cols_for(4, 96.0, 1600.0) == 3 and U.cols_for(4, 96.0, 1280.0) == 2 and U.cols_for(7, 96.0, 1280.0) == 4, "120 % bis 150 %: weniger Spalten")
	check(U.cols_for(4, 96.0, 400.0) == 2 and U.cols_for(1, 96.0, 400.0) == 1, "nie weniger als zwei (oder die gebaute Zahl)")
	print("Guide: Leiste links, rechts bleibt das Spiel")
	check(Guide.panel_w(1920.0) == 620.0 and Guide.panel_w(1440.0) == 620.0, "16:9, 4K und 4:3: 620 logische Pixel")
	check(Guide.panel_w(1100.0) <= 550.0, "sehr schmal: höchstens die Hälfte, das Spiel bleibt zu sehen")
	print("Knappe Höhe (große Oberfläche)")
	check(U.tight(1080.0) == 0.0 and U.tight(1440.0) == 0.0 and U.tight(982.0) < 0.3, "1080p, 4:3 und 110 %: wie gebaut")
	check(is_equal_approx(U.tight(900.0), 0.5) and U.tight(720.0) == 1.0 and U.tight(600.0) == 1.0, "120 %: halb, 150 %: ganz knapp")
	check(U.by_room(82.0, 42.0, 1080.0) == 82.0 and U.by_room(82.0, 42.0, 720.0) == 42.0 and U.by_room(82.0, 42.0, 900.0) == 62.0, "Abstände schrumpfen stufenlos")
	print("Guide: bei knapper Höhe rollt die Liste")
	check(Guide.body_room(1080.0) >= 800.0, "1080 Zeilen: Platz für Spielblock und Liste")
	check(Guide.body_room(720.0) >= 440.0 and Guide.HEAD_H + Guide.FOOT_H < 300.0, "150 %: Kopf und Hinweise bleiben stehen, die Liste rollt (probe_guide_panel --skala=1.5)")
	print("Vorschau passt sich an (fit_box.gd)")
	check(FitBox.k_for(Vector2(300, 200), Vector2(400, 300)) == 1.0, "passt: volle Größe")
	check(is_equal_approx(FitBox.k_for(Vector2(600, 200), Vector2(300, 300)), 0.5), "zu breit: halb so groß")
	check(is_equal_approx(FitBox.k_for(Vector2(300, 600), Vector2(400, 300)), 0.5), "zu hoch: halb so groß")
	print("Leiste gleitet mit der Auswahl (strip_pan.gd)")
	await _pan_test()
	print("Größe der Oberfläche: große Werte bleiben wählbar")
	var keep: Variant = Config.get_value("theme.ui_scale", 1.0)
	Config.set_value("theme.ui_scale", 1.5)
	check(is_equal_approx(UzTheme.ui_scale(), 1.5) and UzTheme.SCALE_MAX >= 1.5, "150 % bleibt, wie eingestellt (kein Feature weg)")
	check(UzTheme.SCALE_FIT >= UzTheme.SCALE_MAX, "geprüft ohne Überlauf bis ganz oben (probe_aufloesung, 120/135/150 %)")
	Config.set_value("theme.ui_scale", 0.85)
	check(is_equal_approx(UzTheme.ui_scale(), 0.85), "kleiner bleibt wie eingestellt")
	Config.set_value("theme.ui_scale", keep)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

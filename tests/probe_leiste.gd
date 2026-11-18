extends "res://tests/probe_base.gd"
## Bilder der Leiste oben: Cursor auf einem Wort-Reiter (LT/RT sichtbar, Status rechts mit
## laufender Musik, neuer Mitteilung und einem schwachen Controller), Cursor auf einem App-Symbol
## (Name sichtbar), Cursor im Inhalt (die Leiste ruht, der Punkt zeigt den Bereich), dazu der Bogen
## des Symbolsatzes der Leiste (Linie und gefüllt, groß und in Leistengröße).
## Prüfungen der Bedienung: tests/probe_reiter.gd, Logik: tests/logic_leiste.gd, tests/logic_kopf.gd.

const A := preload("res://src/core/apps_extern.gd")
const SATZ := [["games", "Spiele"], ["shop", "Shop"], ["user", "Profil"], ["friends", "Freunde"], ["music", "Musik"], ["video", "Videos"],
	["film", "Filme"], ["live", "Streams"], ["room", "Zimmer"], ["apps", "Meine Apps"], ["add", "Hinzufügen"], ["settings", "Einstellungen"]]


func run() -> void:
	Config.set_value(A.KEY, [])
	A.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	# Der Xbox-Controller ist schwach: nur dann steht sein Akku oben (sonst nur im Guide).
	Pads.demo_raw.xinput[0].blevel = 1
	Pads.refresh()
	# Eine neue Mitteilung: der Punkt im Akzent am Profilbild.
	Toasts.unread = maxi(Toasts.unread, 1)
	main._rebuild()
	await wait(1.6)
	Nav.focus(main._tab_items["shop"], true)
	await shot("leiste_wort_fokus", 1.2)
	Nav.focus(main._tab_items["music"], true)
	await shot("leiste_symbol_fokus", 1.2)
	# Cursor im Inhalt: LT/RT weg, die Leiste tritt zurück, der Punkt zeigt den Bereich.
	main.goto("games")
	await wait(1.4)
	await shot("leiste_ruhe", 0.8)
	await _bogen()
	Config.set_value(A.KEY, [])


func _bogen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	var head := Label.new()
	head.text = "Symbolsatz der Leiste – Linie (ruhend) und gefüllt (Cursor, aktiv); 24er Raster, Strich 2"
	head.position = Vector2(80, 50)
	head.add_theme_font_override("font", UzTheme.ui("ui_bold"))
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", UzTheme.col("text"))
	layer.add_child(head)
	for i in SATZ.size():
		var x := 80.0 + float(i % 6) * 300.0
		var y := 140.0 + float(i / 6) * 440.0
		var n: String = SATZ[i][0]
		var j := 0
		for v in [n, n + "_f"]:
			var big := TextureRect.new()
			big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			big.texture = Icons.tex(v, 96)
			big.size = Vector2(96, 96)
			big.position = Vector2(x + j * 120.0, y)
			big.modulate = UzTheme.col("text")
			layer.add_child(big)
			var small := TextureRect.new()
			small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			small.texture = Icons.tex(v, 28)
			small.size = Vector2(28, 28)
			small.position = Vector2(x + j * 120.0 + 34.0, y + 120.0)
			small.modulate = UzTheme.col("muted") if j == 0 else UzTheme.col("text")
			layer.add_child(small)
			j += 1
		var l := Label.new()
		l.text = "%s  ·  %s" % [SATZ[i][1], n]
		l.position = Vector2(x, y + 170.0)
		l.add_theme_font_override("font", UzTheme.ui("ui"))
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", UzTheme.col("muted"))
		layer.add_child(l)
	await shot("symbolsatz_leiste", 0.8)
	layer.queue_free()

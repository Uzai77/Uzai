extends "res://tests/probe_base.gd"
## Probe Startseite: das Spielbild klar hinter dem Regal (ohne Weichzeichner), still – mit einem
## selbst gemalten Bild als Hero (Himmel, Berge, Kanten zum Prüfen der Schärfe).


func _paint(path: String) -> void:
	var w := 1920
	var h := 1080
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var sky := Color("#7fb3d5").lerp(Color("#f3d9a4"), float(y) / h)
		for x in w:
			var ridge := 620.0 + sin(x * 0.006) * 90.0 + sin(x * 0.021) * 25.0
			var c := sky if y < ridge else Color("#2f3b33").lerp(Color("#15201a"), float(y - ridge) / (h - ridge))
			if (x / 120 + y / 120) % 2 == 0 and y > 900:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	img.fill_rect(Rect2i(1400, 380, 60, 300), Color("#d8d2c4"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g: Dictionary = Library.by_system("ps2")[0]
	var p := Config.path("media/probe_hero.jpg")
	_paint(p)
	Library.set_field(str(g.id), "images", { "hero": p })
	await wait(1.0)
	# Erst ein anderes Spiel, dann zurück: sonst gilt das Bild als schon gezeigt.
	main.sections["games"]._focus_game(str(Library.recent(3)[1].id))
	await wait(1.0)
	main.sections["games"]._focus_game(str(g.id))
	await shot("start_klar", 3.5)

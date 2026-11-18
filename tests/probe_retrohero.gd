extends "res://tests/probe_base.gd"
## Probe „Retro-Bühne“: Emulator-Spiele ohne großes Bild (Hero). Die Spielseite und die Startseite
## zeigen die Spielszene ungeschnitten als Bildschirm rechts, ganzzahlig vergrößert, dahinter das
## Cover weich als Licht. Bilder hier selbst gemalt (die Demo hat keine): Cover und eine kleine
## Pixel-Szene (Game Boy Advance, 240 × 160).

const SPIEL := "gba:99397f66953f91"


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var g := Library.get_game(SPIEL)
	var dir := OS.get_user_data_dir().path_join("probe_retro")
	DirAccess.make_dir_recursive_absolute(dir)
	var cover := dir.path_join("cover.png")
	var szene := dir.path_join("szene.png")
	_malen(300, 400, Color("#2f6b3a"), Color("#e8c060"), 3, 1).save_png(cover)
	_malen(240, 160, Color("#3a7ad0"), Color("#70c050"), 5, 8).save_png(szene)
	g["images"] = { "cover": cover, "shot": szene }
	Media.forget(g)
	main.open_game(g)
	await shot("retrohero_spielseite", 2.4)
	await press("b")
	await wait(0.8)
	main.goto("games", "gba")
	await wait(0.6)
	var gs = main.sections["games"]
	gs.build()
	await wait(0.8)
	gs._focus_game(SPIEL)
	await shot("retrohero_startseite", 2.0)


## Verlauf mit Flächen; block > 1 malt grobe Klötzchen wie in alten Spielen.
func _malen(w: int, h: int, c1: Color, c2: Color, seed_i: int, block: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), c1.darkened(0.5).lerp(c1, float(y) / h))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	for k in 14:
		var rw := rng.randi_range(w / 10, w / 3) / block * block
		var rh := rng.randi_range(h / 10, h / 3) / block * block
		var x := rng.randi_range(0, w - rw) / block * block
		var y := rng.randi_range(0, h - rh) / block * block
		img.fill_rect(Rect2i(x, y, maxi(rw, block), maxi(rh, block)), c2.lerp(c1, rng.randf() * 0.6))
	return img

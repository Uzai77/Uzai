extends "res://tests/probe_base.gd"
## Probe „Startseite“: der Reiter Spiele in der Marke – mit eingelegter Disc (Ico, PS2) vorn in
## „Zuletzt“, ein Spiel mit Bildern (Cover und großes Bild, hier selbst gemalt: weicher
## Hintergrund, Schild), die Quellenleiste, „Für dich“ auf Start (Seitenleiste), eine andere Quelle.
## UZAI_STARTSEITE_TEIL: "seite", "akzente", "leisten" oder leer (seite und akzente). „leisten“
## zeigt nur „Für dich“ (Start, rechts, oben und weiter unten) und die Freunde (Select, links). „akzente“ zeigt die Startseite
## in den vier Akzenten zur Wahl (wie tests/probe_akzent.gd über „theme.accent“).

const AKZENTE := [["lavendel", "#b8a6f0"], ["perlgrau", "#d6d9e4"], ["eisblau", "#8fd0e3"], ["koralle", "#f0997e"]]
## Spiele, die in der Probe gemalte Bilder bekommen: Kennung, zwei Farben.
const BILDER := [["ps2:d0bd3fcb9f628e", "#5a3f8f", "#e0a050"], ["steam:1245620", "#2c2a24", "#c8a050"],
	["ps2:74a8e64542ec02", "#3d5a6e", "#d8d0c0"], ["xboxpc:Microsoft.624F8B84B80_8wekyb3d8bbwe", "#1f4a3a", "#f0c040"]]


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var teil := OS.get_environment("UZAI_STARTSEITE_TEIL")
	_bilder()
	# Ico (PS2) liegt im Laufwerk: steht vorn in „Zuletzt“, der Kopf sagt „Disc eingelegt“.
	Discs.set_disc("SCES-50760", "ps2", "E:\\")
	await wait(1.0)
	if teil in ["", "seite"]:
		await _seite()
	if teil in ["", "akzente"]:
		await _akzente()
	if teil == "leisten":
		await _leisten()


## Die beiden Seitenleisten des Hauptmenüs: „Für dich“ rechts auf Start, die Freunde links auf Select.
func _leisten() -> void:
	main.goto("games", "zuletzt")
	await wait(0.6)
	var gs = main.sections["games"]
	gs.build()
	await wait(0.8)
	gs.focus_default()
	await wait(1.0)
	await press("menu")
	await shot("leiste_fuerdich", 1.2)
	await press("down", 10, 0.25)
	await shot("leiste_fuerdich_unten", 1.0)
	await press("menu")
	await wait(0.5)
	await press("view")
	await shot("leiste_freunde_links", 1.4)
	await press("view")
	await wait(0.4)


## Cover und großes Bild für einige Spiele (die Demo hat keine): Verlauf mit ein paar Flächen,
## damit der weiche Hintergrund und das Schild auf dem Cover zu sehen sind.
func _bilder() -> void:
	var dir := OS.get_user_data_dir().path_join("probe_bilder")
	DirAccess.make_dir_recursive_absolute(dir)
	var i := 0
	for b in BILDER:
		var g := Library.get_game(str(b[0]))
		if g.is_empty():
			continue
		var c1 := Color(str(b[1]))
		var c2 := Color(str(b[2]))
		var cover := dir.path_join("c%d.png" % i)
		var hero := dir.path_join("h%d.png" % i)
		_malen(300, 400, c1, c2, i).save_png(cover)
		_malen(960, 400, c1, c2, i + 3).save_png(hero)
		g["images"] = { "cover": cover, "hero": hero }
		Media.forget(g)
		i += 1


func _malen(w: int, h: int, c1: Color, c2: Color, seed_i: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), c1.darkened(0.55).lerp(c1, float(y) / h))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	for k in 7:
		var rw := rng.randi_range(w / 8, w / 3)
		var rh := rng.randi_range(h / 8, h / 2)
		img.fill_rect(Rect2i(rng.randi_range(0, w - rw), rng.randi_range(0, h - rh), rw, rh), c2.lerp(c1, rng.randf() * 0.6))
	return img


func _seite() -> void:
	main.goto("games", "zuletzt")
	await wait(0.6)
	var gs = main.sections["games"]
	# Neu bauen: die Cover vom Start kannten die gemalten Bilder noch nicht.
	gs.build()
	main.refresh_chips()
	await wait(0.8)
	gs.focus_default()
	await shot("start_disc", 1.6)
	await press("right")
	await shot("start_zweites", 1.4)
	await press("right", 2, 0.4)
	await shot("start_drittes", 1.6)
	await press("up")
	await shot("start_quellen", 1.0)
	await press("down")
	await press("menu")
	await shot("start_fuerdich", 1.0)
	await press("down")
	await shot("start_fuerdich_zweite", 0.6)
	await press("menu")
	await wait(0.4)
	main.goto("games", "ps2")
	await wait(1.0)
	gs.focus_default()
	await press("right", 2, 0.4)
	await shot("start_ps2", 1.4)


func _akzente() -> void:
	for a in AKZENTE:
		Config.set_value("theme.accent", str(a[1]))
		await wait(1.2)
		main.goto("games", "zuletzt")
		await wait(0.8)
		main.sections["games"].focus_default()
		await shot("akzent_%s" % a[0], 1.6)
	Config.set_value("theme.accent", "")

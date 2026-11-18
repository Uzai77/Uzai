extends "res://tests/probe_base.gd"
## Probe Ruhebildschirm (Punkt 94): Bilder im Medienordner der Probe (selbst gemalt, nichts aus dem
## Netz), Ruhebildschirm mit Kamerafahrt und Bildunterschrift, Überblendung zum nächsten Bild,
## Taste weckt ohne auszulösen, nur überblenden, ohne jedes Bild nur die Uhr, Einstellungen.
## Gibt „RB ok/FAIL …“ aus.

var fails := 0

const PALETTES := [
	["Shadow of the Colossus", Color("#c9b48a"), Color("#3d4a5c"), Color("#1d2430")],
	["Ōkami", Color("#f2c46d"), Color("#c0573e"), Color("#3b1f2b")],
	["Ico", Color("#9fc3d6"), Color("#56707f"), Color("#24313a")],
	["Silent Hill 2", Color("#8d9091"), Color("#4d5152"), Color("#202324")],
	["Final Fantasy X", Color("#7fd3e8"), Color("#2c7aa0"), Color("#0e2a3d")],
]


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("RB %s %s" % ["ok  " if cond else "FAIL", what])


## Eine ruhige Landschaft: Himmel im Verlauf, Sonne, drei Bergketten davor.
func _paint(path: String, sky: Color, mid: Color, low: Color, seed_v: int) -> void:
	var w := 640
	var h := 360
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sun := Vector2(rng.randf_range(0.2, 0.8) * w, rng.randf_range(0.18, 0.4) * h)
	var ridges: Array = []
	for r in 3:
		ridges.append([rng.randf_range(0.0, 6.0), rng.randf_range(0.008, 0.02), rng.randf_range(0.03, 0.06), 0.45 + r * 0.14])
	for y in h:
		var t := float(y) / h
		var base := sky.lerp(mid, t * 0.9)
		for x in w:
			var c := base
			var d := Vector2(x, y).distance_to(sun)
			c = c.lerp(Color(1, 0.96, 0.85), clampf(1.0 - d / 70.0, 0.0, 1.0) * 0.9 + clampf(1.0 - d / 260.0, 0.0, 1.0) * 0.18)
			for r in 3:
				var rg: Array = ridges[r]
				var top: float = (
						float(rg[3]) + sin(x * float(rg[1]) + float(rg[0])) * float(rg[2]) + sin(x * float(rg[1]) * 2.7 + float(rg[0]) * 2.0) * float(rg[2]) * 0.4) * h
				if y > top:
					c = mid.lerp(low, 0.35 + r * 0.32).lerp(sky, 0.18 - r * 0.06)
			img.set_pixel(x, y, c)
	# Etwas größer als der Bildschirm der Probe (1080p): nur solche Bilder zeigt der Ruhebildschirm, mit Fahrt.
	img.resize(2112, 1188, Image.INTERPOLATE_CUBIC)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var media := Config.media_dir()
	for i in PALETTES.size():
		var p: Array = PALETTES[i]
		_paint(media.path_join("ps2/hero/%s.png" % p[0]), p[1], p[2], p[3], i + 3)
	# Uzai merkt sich „kein Bild“ 10 s lang (Media.local_path); die Bilder kamen eben erst dazu.
	Media._local.clear()
	print("RB blocked: '%s'" % main.saver.blocked())

	var sec_before := str(main.current)
	# 1. Ruhebildschirm (Vorschau, sonst nach der eingestellten Zeit).
	main.saver.start(true)
	await wait(0.4)
	_ck(is_instance_valid(main.saver.screen), "Ruhebildschirm offen")
	_ck(Nav.top_layer() == main.saver.screen, "oberste Ebene, Eingaben gehören ihm")
	await shot("01_einblenden", 0.5)
	await shot("02_bild_mit_schrift", 3.0)
	await shot("03_kamerafahrt", 4.0)
	# 2. Nächstes Bild (sonst nach 14 s): mitten in der Überblendung und danach.
	main.saver.screen._advance()
	await shot("04_ueberblendung", 1.3)
	await shot("05_naechstes_bild", 3.2)
	# 3. Eine Taste weckt – und löst dahinter nichts aus.
	var fired: Array = []
	var on_cmd := func(c: String) -> void: fired.append(c)
	Nav.command.connect(on_cmd)
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.physical_keycode = KEY_ENTER
	k.pressed = true
	get_tree().root.push_input(k)
	await wait(0.2)
	await shot("06_ausblenden", 0.0)
	await wait(1.0)
	_ck(not is_instance_valid(main.saver.screen), "Taste: Ruhebildschirm weg")
	_ck(fired.is_empty() and Nav.layers.is_empty() and str(main.current) == sec_before, "nichts ausgelöst, kein Fenster, gleicher Bereich (%s)" % str(fired))
	await shot("07_zurueck", 0.2)
	Nav.command.disconnect(on_cmd)
	# 4. Stick und Guide-Taste (Helfer) wecken ebenso.
	main.saver.start(true)
	await wait(1.0)
	Nav._fire("down")
	await wait(1.2)
	_ck(not is_instance_valid(main.saver.screen) and Nav.layers.is_empty(), "Stick: weg, Fokus nicht bewegt")
	main.saver.start(true)
	await wait(1.0)
	main._on_pad_event("guide")
	await wait(1.2)
	_ck(not is_instance_valid(main.saver.screen) and (main._guide == null or not is_instance_valid(main._guide)),
			"Guide-Taste über den Helfer: weckt nur, kein Guide")
	# 5. Nur überblenden (schwacher PC / Einstellung).
	Config.set_value("rest.saver_motion", "ruhig")
	main.saver.start(true)
	await wait(0.4)
	_ck(bool(main.saver.screen.simple), "„Nur überblenden“: ohne Kamerafahrt")
	await shot("08_nur_ueberblenden", 3.5)
	main.saver.stop(true)
	Config.set_value("rest.saver_motion", "fahrt")
	await wait(0.5)
	# 6. Kein einziges Bild auf dem PC: nur die Uhr, mittig.
	var empty := Config.path("leer_media")
	DirAccess.make_dir_recursive_absolute(empty)
	Config.set_value("library.media_dir", empty)
	Media._local.clear()
	main.saver.start(true)
	await shot("09_ohne_bilder", 3.0)
	main.saver.stop(true)
	Config.set_value("library.media_dir", "")
	Media._local.clear()
	await wait(0.6)
	# 7. Nach der eingestellten Zeit von selbst (falls das Fenster hier als „vorn“ gilt).
	Config.set_value("rest.saver", "2")
	main.saver.auto = true    # in Proben sonst nie von selbst
	main.saver._idle_from = Time.get_ticks_msec() - 3 * 60000
	main.saver._check()
	await wait(0.3)
	if main.saver.blocked() == "":
		_ck(is_instance_valid(main.saver.screen), "nach 2 Minuten ohne Bedienung: kommt von selbst")
	else:
		print("RB (übersprungen: hier gilt Uzai als „%s“)" % main.saver.blocked())
	main.saver.stop(true)
	main.saver.auto = false
	await wait(0.5)
	# 8. Einstellungen → System → Ruhemodus & Spielstände.
	main.goto("settings", "system")
	await wait(1.0)
	var sv = main.sections["settings"]
	for c in Nav.focusables(sv):
		if str(c.get_meta("uz_key", "")).contains("Ruhebildschirm"):
			Nav.focus(c, true)
			break
	await shot("10_einstellung_system", 0.8)
	sv.open_more("Ruhemodus & Spielstände")
	await shot("11_unterseite", 0.8)
	print("RB fertig, Fehler: %d" % fails)

extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Regal einer Konsole (src/ui/layers/regal_seite.gd) – PS2 mit rund vierzig
## Spielen (zu den Demo-Spielen kommen erfundene Titel ohne Bild; ihre Cover zeichnet Uzai selbst):
## Übersicht nach der Kamerafahrt, eine weiter rechts gewählte und herausgezogene Hülle, dazu
## PS1 (CD-Hüllen mit schwarzem Rücken) und GameCube. Die Spiele bekommen selbst gerechnete
## Motive als eigenes Cover (600 × 900 wie bei SteamGridDB, ohne Rahmen – Uzai legt den Rahmen des
## Systems darüber und schneidet zu), eines („Fernweh“) ist ein Scan wie „FIFA Street 2“ mit
## eigenem Band samt Schrift und farbigem Logo – Uzai schneidet es weg, nichts doppelt. Einige
## tragen die Seriennummer im Dateinamen (unten am Rücken). Die echten Logos kommen wie in Uzai zur
## Laufzeit (src/core/badge_logos.gd). Ist Wikimedia nicht erreichbar (Testumgebung), legt die
## Probe selbst gezeichnete Platzhalter als „eigene Datei“ (<Medien>/logos) hin – Schriftzüge in
## Uzais Schrift und ein vierfarbiges Feld statt des PS-Logos, nur für Lage und Größe, keine echten
## Logos.
## Mit Bildzeiten (Software-Grafik: nur Vergleich).
## Aufruf siehe probe_base.gd (--demo).

const TITEL := ["Aurora Drift", "Basalt", "Cinder Road", "Dämmerlicht", "Echo Valley", "Fernweh", "Glasgarten",
	"Hollow Crown", "Island of Kites", "Jadeturm", "Kaltfront", "Lumen", "Mirage Rally", "Nachtzug", "Obsidian",
	"Polarlicht", "Quarzwerk", "Rostfeuer", "Salzwind", "Tidewater", "Umbra", "Vesper", "Wellenbrecher",
	"Xenolith", "Yarrow", "Zinnober", "Ankerlicht", "Brandung", "Copper Moon", "Drachenpass"]

const BadgeLogos := preload("res://src/core/badge_logos.gd")

var _t: Array = []
var _rec := false
var _prev := 0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _rec and _prev > 0:
		_t.append((now - _prev) / 1000.0)
	_prev = now


func messen(name: String, secs := 3.0) -> void:
	_t.clear()
	_prev = 0
	_rec = true
	await wait(secs)
	_rec = false
	var v := _t.duplicate()
	v.sort()
	if not v.is_empty():
		print("MESS %-24s Median %6.1f ms (%d Bilder)" % [name, v[v.size() / 2], v.size()])


## Ein ruhiges Motiv (Verlauf mit weichen Kreisen), auf Wunsch mit schwarzem Band oben wie ein Scan.
func _motiv(name: String, w: int, h: int, a: Color, b: Color, seed_: int, band: bool) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), a.lerp(b, float(y) / h))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in 6:
		var c := Vector2(rng.randf() * w, rng.randf() * h)
		var r := rng.randf_range(0.1, 0.3) * minf(w, h)
		var col := b.lerp(Color.WHITE, 0.4) if i % 2 == 0 else a.lerp(Color.BLACK, 0.3)
		for yy in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r)), 2):
			for xx in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r)), 2):
				var d := Vector2(xx, yy).distance_to(c) / r
				if d < 1.0:
					img.fill_rect(Rect2i(xx, yy, 2, 2), img.get_pixel(xx, yy).lerp(col, (1.0 - d) * 0.6))
	if band:
		# Wie ein echter PS2-Scan: schwarzes Band mit weißer Schrift links, farbigem Logo rechts.
		var bh := int(h * 0.09)
		img.fill_rect(Rect2i(0, 0, w, bh), Color.BLACK)
		for i in 11:
			img.fill_rect(Rect2i(int(w * (0.04 + i * 0.038)), int(bh * 0.28), int(w * 0.024), int(bh * 0.46)), Color.WHITE)
		var ls := int(bh * 0.34)
		for k in 4:
			img.fill_rect(Rect2i(int(w * 0.82) + (k % 2) * ls, int(bh * 0.16) + (k / 2) * ls, ls, ls),
				[Color("#e60012"), Color("#f5b800"), Color("#00a650"), Color("#0070d1")][k])
	var p := Config.media_dir().path_join("probe_regal_" + name + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
	return p


## Schriftzug in Uzais Schrift als eigene Logo-Datei (nur für die Probe, siehe oben).
func _platzhalter(key: String, text: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 120)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UzTheme.display("bold"))
	l.add_theme_font_size_override("font_size", 84)
	l.add_theme_color_override("font_color", Color.WHITE)
	vp.add_child(l)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var p := Config.media_dir().path_join("logos").path_join(key + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	vp.get_texture().get_image().save_png(p)
	vp.queue_free()


## Vierfarbiges Feld als Platzhalter für das farbige PS-Logo (nur Lage und Farbe, kein Logo).
func _platzhalter_bunt(key: String) -> void:
	var img := Image.create(200, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var farben := [Color("#e60012"), Color("#f5b800"), Color("#00a650"), Color("#0070d1")]
	for k in 4:
		img.fill_rect(Rect2i(10 + k * 46, 20 + (k % 2) * 30, 40, 120), farben[k])
	var p := Config.media_dir().path_join("logos").path_join(key + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	var n := 0
	for t in TITEL:
		n += 1
		# Jedes dritte mit Seriennummer im Dateinamen (dann steht sie unten am Rücken).
		var datei: String = ("SLES-%d %s" % [54700 + n, t]) if n % 3 == 0 else str(t)
		Library.games.append({ "id": "ps2:probe%02d" % n, "title": t, "system": "ps2", "source": "rom", "installed": true,
			"playtime": (n * 7919) % 200000, "path": "D:/Spiele/PS2/%s.iso" % datei })
	var motive: Array = []
	var farben := [[Color("#1a2a6c"), Color("#f2a541")], [Color("#3a0d2e"), Color("#e94f37")], [Color("#0b3d2e"), Color("#a7e8bd")],
		[Color("#2b1d0e"), Color("#ffcf56")], [Color("#101935"), Color("#8ad6ff")], [Color("#3d1f5c"), Color("#ff8fb1")]]
	for k in farben.size():
		motive.append(_motiv("motiv%d" % k, 600, 900, farben[k][0], farben[k][1], k + 3, false))
	var scan := _motiv("scan", 512, 728, Color("#1d3557"), Color("#e63946"), 11, true)
	var nr := 0
	for g in Library.games:
		if str(g.get("system", "")) in ["ps2", "ps1", "gc"]:
			g["images"] = { "cover": scan if str(g.get("title", "")) == "Fernweh" else motive[nr % motive.size()] }
			Media.forget(g)
			nr += 1
	main.goto("games")
	await wait(1.0)
	var gs: Node = main.sections.get("games")
	# Logos vorab anstoßen (Laden aus dem Netz bzw. Cache, wie die Quellen-Zeile der Startseite).
	for k in ["ps2", "ps1", "gc", "ps2_wortmarke", "ps_logo_farbe", "ps_zeichen"]:
		BadgeLogos.image_for_key(k)
	await wait(6.0)
	for e in [["ps2_wortmarke", "PlayStation®2"], ["gc", "GAMECUBE"]]:
		if BadgeLogos.image_for_key(str(e[0])).is_empty():
			await _platzhalter(str(e[0]), str(e[1]))
	if BadgeLogos.image_for_key("ps_logo_farbe").is_empty():
		_platzhalter_bunt("ps_logo_farbe")
	BadgeLogos.forget()
	gs.open_regal("ps2", "PlayStation 2")
	await wait(0.5)
	await shot("01_regal_einfahrt", 0.0)
	await wait(2.4)
	await shot("02_regal_uebersicht", 0.2)
	var l: Node = Nav.top_layer()
	await messen("Regal still")
	for i in 7:
		Nav._fire("right")
		await wait(0.09)
	await messen("Regal fahren", 1.0)
	# Rechenzeit ohne Grafik: Schritt samt Anzeige und ein Bild der Welt (Hüllen neu belegt).
	var welt: Node = l.get("welt")
	var t0 := Time.get_ticks_usec()
	for i in 20:
		l.nav_dir("right")
		welt._process(1.0 / 60.0)
	print("MESS Rechnen je Schritt         %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	t0 = Time.get_ticks_usec()
	for i in 60:
		welt._process(1.0 / 60.0)
	print("MESS Rechnen je Bild (Fahrt)    %.2f ms" % ((Time.get_ticks_usec() - t0) / 60000.0))
	for i in 20:
		l.nav_dir("left")
	await wait(1.6)
	await shot("03_regal_gewaehlt", 0.2)
	# Nahaufnahme der Rücken (Kamera näher heran, ohne gewählte Hülle draußen).
	welt.zieh_ziel = 0.0
	var cam: Camera3D = welt.get("kamera")
	await wait(0.6)
	welt.set_process(false)
	var hh := float(welt.get("hoehe"))
	var x := float((welt.get("xs") as PackedFloat32Array)[int(welt.get("auswahl"))])
	cam.look_at_from_position(Vector3(x, hh * 0.55, hh * 1.7), Vector3(x, hh * 0.5, 0.0), Vector3.UP)
	(welt.get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await wait(0.4)
	await shot("03b_regal_ruecken_nah", 0.0)
	welt.set_process(true)
	welt.zieh_ziel = 1.0
	l.close()
	await wait(0.8)
	gs.open_regal("ps1", "PlayStation")
	await wait(2.6)
	Nav._fire("rb")
	await wait(1.6)
	await shot("04_regal_cd_huellen", 0.2)
	Nav.top_layer().close()
	await wait(0.8)
	gs.open_regal("gc", "GameCube")
	await wait(2.6)
	Nav._fire("right")
	await wait(1.6)
	await shot("05_regal_gamecube", 0.2)

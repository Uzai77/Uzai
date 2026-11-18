extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Mosaik (src/ui/layers/mosaik_seite.gd) – eine Sammlung mit allen Spielen im
## Auto-Mosaik 10 × 10 über einem eigenen Hintergrund (Glas, ganzer Schirm), ein thematischer Ordner
## in 4 × 3 mit eigenem Hintergrund (Spiele, Bilder, ein Ordner als reines Glas) und derselbe beim
## Gestalten. Die Bilder rechnet die Probe selbst (keine
## fremden Grafiken). Aufruf siehe probe_base.gd.

const Mosaik := preload("res://src/library/mosaik.gd")


## Ein ruhiges Bild: Verlauf zwischen zwei Farben, darauf weiche Kreise.
func _bild(name: String, w: int, h: int, a: Color, b: Color, seed_: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), a.lerp(b, float(y) / h))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in 5:
		var c := Vector2(rng.randf() * w, rng.randf() * h)
		var r := rng.randf_range(0.12, 0.35) * minf(w, h)
		var col := b.lerp(Color.WHITE, 0.35) if i % 2 == 0 else a.lerp(Color.BLACK, 0.3)
		for yy in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r))):
			for xx in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r))):
				var d := Vector2(xx, yy).distance_to(c) / r
				if d < 1.0:
					img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(col, (1.0 - d) * 0.55))
	var p := Config.media_dir().path_join("probe_" + name + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
	return p


func run() -> void:
	var gs: Node = main.sections.get("games")
	Mosaik.sicher_geladen("", true)

	# 1) Alle Spiele als Sammlung, Auto-Mosaik in 10 × 10.
	var alle := Library.create_folder("Alles", "")
	for g in Library.visible_games():
		Library.set_in_folder(str(g.id), alle, true)
	Mosaik.raster_setzen("ordner:" + alle, Vector2i(10, 10))
	var grund := _bild("grund", 1280, 720, Color("#1a1430"), Color("#c06a4a"), 21)
	Mosaik.hintergrund_setzen("ordner:" + alle, { "dunkel": 0.2, "bild": { "art": "datei", "pfad": grund, "fx": 0.5, "fy": 0.5 } })
	gs.open_mosaik("ordner:" + alle, "Alles")
	await wait(1.6)
	await shot("01_raster_10x10", 0.8)
	# Leistung: Neuaufbau einer vollen 10 × 10-Seite (Umbau beim Gestalten) und Bilder je Bild.
	var l10: Node = Nav.top_layer()
	var t0 := Time.get_ticks_usec()
	l10._bauen()
	print("Probe: Neuaufbau 10 × 10 (%d Kacheln) %.1f ms" % [l10._raster.get_child_count(), (Time.get_ticks_usec() - t0) / 1000.0])
	l10._gestalten(true)
	await wait(0.5)
	var erste: Dictionary = l10._sichtbar()[0]
	t0 = Time.get_ticks_usec()
	l10._groesse(str(erste.id), 1, 1)
	print("Probe: Größe ändern im 10 × 10 (Gestalten, %d Felder) %.1f ms" % [l10._raster.get_child_count(), (Time.get_ticks_usec() - t0) / 1000.0])
	t0 = Time.get_ticks_usec()
	l10._packen(str(erste.id))
	l10.nav_dir("right")
	print("Probe: Verschieben im 10 × 10 %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	l10._gestalten(false)
	var b0 := Engine.get_frames_drawn()
	await wait(1.0)
	print("Probe: Bilder je Sekunde danach ", Engine.get_frames_drawn() - b0)
	await press("b")
	await wait(0.8)

	# 2) Thematischer Ordner in 4 × 3 mit eigenem Hintergrund: Spiele hoch, Bilder, ein Ordner.
	var fid := Library.create_folder("Abenteuer", "")
	for g in Library.by_system("ps2").slice(0, 3):
		Library.set_in_folder(str(g.id), fid, true)
	var spiele: Array = Library.in_folder(fid)
	var ks: Array = []
	var bilder := [
		[0, 0, 1, 2, _bild("hoch1", 300, 560, Color("#16324a"), Color("#8fd0e3"), 7)],
		[3, 0, 1, 1, _bild("klein1", 300, 300, Color("#2b1d12"), Color("#e7c27d"), 13)],
		[0, 2, 2, 1, _bild("weit2", 640, 280, Color("#1d1d3a"), Color("#b8a6f0"), 5)],
	]
	for b in bilder:
		ks.append({ "id": "k%d" % (ks.size() + 1), "art": "bild", "s": 0, "x": b[0], "y": b[1], "w": b[2], "h": b[3],
			"bild": { "art": "datei", "pfad": b[4], "fx": 0.5, "fy": 0.5 } })
	for i in mini(2, spiele.size()):
		ks.append({ "id": "k%d" % (ks.size() + 1), "art": "spiel", "ref": str(spiele[i].id), "s": 0, "x": 1 + i, "y": 0, "w": 1, "h": 2,
			"bild": { "art": "cover", "fx": 0.5, "fy": 0.5 }, "logo": true })
	if spiele.size() > 2:
		ks.append({ "id": "k%d" % (ks.size() + 1), "art": "spiel", "ref": str(spiele[2].id), "s": 0, "x": 3, "y": 2, "w": 1, "h": 1,
			"bild": { "art": "cover", "fx": 0.5, "fy": 0.5 } })
	ks.append({ "id": "k%d" % (ks.size() + 1), "art": "ordner", "ref": alle, "s": 0, "x": 3, "y": 1, "w": 1, "h": 1 })
	ks.append({ "id": "k%d" % (ks.size() + 1), "art": "leer", "s": 0, "x": 2, "y": 2, "w": 1, "h": 1 })
	Mosaik.ablegen("ordner:" + fid, { "cols": 4, "rows": 3, "kacheln": Mosaik.sauber({ "cols": 4, "rows": 3, "kacheln": ks }).kacheln, "weg": [] })
	Mosaik.hintergrund_setzen("ordner:" + fid, { "dunkel": 0.3,
		"bild": { "art": "datei", "pfad": grund, "fx": 0.5, "fy": 0.6, "z": 1.2 } })
	gs.open_mosaik("ordner:" + fid, "Abenteuer")
	await wait(1.6)
	await shot("02_raster_4x3_hintergrund", 0.8)

	# 3) Derselbe Ordner beim Gestalten (leere Felder, Pille oben links).
	var l: Node = Nav.top_layer()
	l._gestalten(true)
	await shot("03_gestalten_4x3", 0.9)
	print("Probe: Raster ", Mosaik.raster("ordner:" + fid), " Hintergrund ", not Mosaik.hintergrund("ordner:" + fid).is_empty())
	# Ohne Bild: Raster mit dem Steuerkreuz (A übernimmt), Ausschnitt des Hintergrunds (B bricht ab),
	# Seite blättern.
	l._raster_start()
	await press("right")
	await press("down")
	await wait(0.3)
	print("Probe: Vorschau ", l._ra(), " gespeichert ", Mosaik.raster("ordner:" + fid))
	await press("a")
	await wait(0.4)
	print("Probe: übernommen ", Mosaik.raster("ordner:" + fid), " Kacheln ", (l._d.kacheln as Array).size())
	var fx0: float = float(Mosaik.hintergrund("ordner:" + fid).bild.fx)
	l._ausschnitt_start("_grund")
	l._ausschnitt_aendern(Vector2(0.2, 0.0), 0.3)
	await press("b")
	await wait(0.3)
	print("Probe: Ausschnitt abgebrochen, fx ", fx0, " → ", float(Mosaik.hintergrund("ordner:" + fid).bild.fx))
	l._ausschnitt_start("_grund")
	l._ausschnitt_aendern(Vector2(0.2, 0.0), 0.3)
	await press("a")
	await wait(0.3)
	print("Probe: Ausschnitt übernommen ", Mosaik.hintergrund("ordner:" + fid).bild)
	await press("rb")
	await wait(0.5)
	print("Probe: Seite ", l._seite, " Raster-Lage ", l._raster.position, " Maßstab ", l._raster.scale)

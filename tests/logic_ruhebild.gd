extends Node
## Ruhebildschirm ohne Fenster: wann er kommt und wann nicht, was als Bedienung zählt, Reihenfolge
## und Auswahl der Bilder (nur von der Platte, nie aus dem Netz), Kamerafahrt ohne Rand, Zeile
## unten rechts – und dass eine Eingabe nur weckt, ohne hinter ihm etwas auszulösen.
## Aufruf: godot --headless --path . res://tests/logic_ruhebild.tscn

const Saver := preload("res://src/core/saver.gd")
const SaverScreen := preload("res://src/ui/layers/saver_screen.gd")

var fails := 0


class FakeSaver extends Node:
	var stops := 0
	var slides: Array = []

	func next_slide() -> Dictionary:
		return slides.pop_front() if not slides.is_empty() else {}

	func stop(_instant := false) -> void:
		stops += 1

	func zu_klein(_path: String) -> void:
		pass


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_when()
	_wakes()
	_order()
	_texts()
	_kenburns()
	_slides()
	await _screen()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _when() -> void:
	print("Wann er kommt")
	check(str(Config.get_value("rest.saver", "")) == "10", "Standard: nach 10 Minuten")
	check(not Saver.due(0, 99999999), "„Aus“: nie")
	check(not Saver.due(10, 10 * 60000 - 1) and Saver.due(10, 10 * 60000), "erst nach der eingestellten Zeit")
	check(not Saver.rest_due(0, 99999999) and Saver.rest_due(30, 30 * 60000) and not Saver.rest_due(30, 29 * 60000), "Ruhemodus danach nur, wenn eingestellt")
	var free := { "boot": false, "game": false, "video": false, "rest": false, "away": false, "focus": true, "pad": false, "typing": false }
	check(Saver.block(free) == "", "im Menü, vorn, nichts läuft: darf")
	for k in ["boot", "game", "video", "rest", "away", "pad", "typing"]:
		var c := free.duplicate()
		c[k] = true
		check(Saver.block(c) != "", "nicht bei %s (%s)" % [k, Saver.block(c)])
	var nf := free.duplicate()
	nf.focus = false
	check(Saver.block(nf) == "nicht vorn", "nicht, wenn Uzai nicht vorn ist")
	check(Saver.simple(false, false, 0.0, 0), "„Nur überblenden“ gewählt: einfach")
	check(Saver.simple(true, true, 0.0, 0), "Animationen reduziert: einfach")
	check(Saver.simple(true, false, 9.0, 2000) and not Saver.simple(true, false, 9.0, 100), "ruckelndes Menü (genug Messwerte): einfach")
	check(not Saver.simple(true, false, 1.0, 2000), "sonst mit Kamerafahrt")


func _wakes() -> void:
	print("Was weckt")
	var k := InputEventKey.new()
	k.keycode = KEY_A
	k.pressed = true
	check(SaverScreen.wakes(k), "Taste gedrückt")
	k.echo = true
	check(not SaverScreen.wakes(k), "Tastenwiederholung nicht")
	var up := InputEventKey.new()
	up.keycode = KEY_A
	check(not SaverScreen.wakes(up), "Loslassen nicht")
	var media := InputEventKey.new()
	media.keycode = KEY_MEDIAPLAY
	media.pressed = true
	check(not SaverScreen.wakes(media), "Medientaste nicht (gehört der Musik)")
	var mm := InputEventMouseMotion.new()
	mm.screen_relative = Vector2(2, 1)
	mm.relative = Vector2(40, 20)    # im Fenster hochgerechnet (4K-Skalierung): zählt nicht
	check(not SaverScreen.wakes(mm), "Scheinbewegung der Maus nicht (in Bildschirmpunkten)")
	mm.screen_relative = Vector2(14, 3)
	check(SaverScreen.wakes(mm), "echte Mausbewegung")
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	check(SaverScreen.wakes(mb), "Klick")
	var jb := InputEventJoypadButton.new()
	jb.pressed = true
	check(SaverScreen.wakes(jb), "Controller-Taste")
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.22
	check(not SaverScreen.wakes(jm), "leicht driftender Stick nicht")
	jm.axis_value = -0.8
	check(SaverScreen.wakes(jm), "Stick bewegt")
	jm.axis = JOY_AXIS_TRIGGER_RIGHT
	jm.axis_value = 0.7
	check(SaverScreen.wakes(jm), "Trigger gedrückt")


func _order() -> void:
	print("Reihenfolge")
	var now := int(Time.get_unix_time_from_system())
	var games: Array = []
	for i in 12:
		games.append({ "id": "g%d" % i, "title": "Spiel %d" % i })
	games[7]["favorite"] = true
	games[9]["last_played"] = now - 3 * 86400
	games[2]["last_played"] = now - 400 * 86400
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var o := Saver.order(games, now, rng)
	check(o.size() == 12, "alle Spiele dabei")
	var first := [str(o[0].id), str(o[1].id)]
	first.sort()
	check(first == ["g7", "g9"], "Favoriten und kürzlich Gespieltes zuerst (%s)" % str(first))
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	check(str(Saver.order(games, now, rng2)) == str(o), "gleicher Zufall: gleiche Reihenfolge")
	var mixed := Saver.interleave(["a", "b", "c", "d", "e"], ["S1", "S2"], 3)
	check(mixed == ["a", "b", "S1", "c", "d", "S2", "e"], "eigene Bildschirmfotos: jedes dritte Bild (%s)" % str(mixed))
	check(Saver.interleave(["a"], ["S1", "S2"], 3) == ["a", "S1", "S2"], "übrige Bildschirmfotos ans Ende")
	check(Saver.interleave(["a", "b"], [], 3) == ["a", "b"], "ohne Bildschirmfotos nur Spiele")


func _texts() -> void:
	print("Texte")
	check(Saver.sub_text("PlayStation 2", 14 * 3600) == "PlayStation 2  ·  14 Std. gespielt", "Plattform und Spielzeit")
	check(Saver.sub_text("Steam", 0) == "Steam", "ohne Spielzeit nur die Plattform")
	check(SaverScreen.now_line({ "playing": true, "title": "To Zanarkand", "artist": "Nobuo Uematsu" }, false, {}) == "To Zanarkand  ·  Nobuo Uematsu",
			"Musik unten rechts")
	check(SaverScreen.now_line({ "playing": false, "title": "X" }, false, {}) == "", "angehaltene Musik: nichts")
	check(SaverScreen.now_line({}, true, { "title": "Ein Video" }) == "Ein Video", "Video nur als Ton")


func _kenburns() -> void:
	print("Kamerafahrt")
	var area := Vector2(1920, 1080)
	var ok := true
	for kind in 3:
		for dir in [Vector2(1, 1), Vector2(-1, 0.4), Vector2(0, -1), Vector2(0.3, 0), Vector2(5, -5)]:
			var m := SaverScreen.kenburns(kind, dir, SaverScreen.ZOOM, area)
			for i in 11:
				var t := i / 10.0
				var s := lerpf(float(m.s0), float(m.s1), t)
				var p: Vector2 = (m.p0 as Vector2).lerp(m.p1, t)
				var room := (s - 1.0) * 0.5 * area
				if s < 1.0 - 0.0001 or absf(p.x) > room.x + 0.01 or absf(p.y) > room.y + 0.01:
					ok = false
	check(ok, "nie ein Rand zu sehen (hinein, heraus, seitlich, jede Richtung)")
	var still := SaverScreen.kenburns(1, Vector2(1, 1), 1.0, area)
	check(float(still.s0) == 1.0 and float(still.s1) == 1.0 and (still.p0 as Vector2) == Vector2.ZERO, "einfache Fassung: steht still")
	# Gezeichnet wird ein Ausschnitt der Textur (ruhig auch unter einem Bildpunkt): immer innerhalb der Textur.
	var tex := area * SaverScreen.ZOOM
	var drin := true
	for kind in 3:
		var m2 := SaverScreen.kenburns(kind, Vector2(0.8, -0.5), SaverScreen.ZOOM, area)
		for i in 11:
			var t := i / 10.0
			var a := SaverScreen._Bild.ausschnitt(lerpf(float(m2.s0), float(m2.s1), t), (m2.p0 as Vector2).lerp(m2.p1, t), area, tex)
			drin = drin and a.position.x >= -0.01 and a.position.y >= -0.01 and a.end.x <= tex.x + 0.01 and a.end.y <= tex.y + 0.01
	var ganz := SaverScreen._Bild.ausschnitt(1.0, Vector2.ZERO, area, tex)
	var nah := SaverScreen._Bild.ausschnitt(SaverScreen.ZOOM, Vector2.ZERO, area, tex)
	check(drin and ganz.is_equal_approx(Rect2(Vector2.ZERO, tex)) and nah.size.is_equal_approx(area),
			"Ausschnitt der Kamerafahrt bleibt in der Textur; ganz nah ein Bildpunkt je Bildpunkt")
	# Only images at the screen's resolution; lower-resolution images look pixelated.
	var uhd := Vector2(3840, 2160)
	check(SaverScreen.zoom_fuer(Vector2i(3840, 1240), uhd, SaverScreen.ZOOM) == 0.0 and SaverScreen.zoom_fuer(Vector2i(1920, 1080), uhd, SaverScreen.ZOOM) == 0.0,
			"4K: Steam-Banner (3840 × 1240) und Full-HD-Bilder bleiben weg")
	check(is_equal_approx(SaverScreen.zoom_fuer(Vector2i(3840, 2160), uhd, SaverScreen.ZOOM), 1.0)
			and is_equal_approx(SaverScreen.zoom_fuer(Vector2i(5120, 2880), uhd, SaverScreen.ZOOM), SaverScreen.ZOOM)
			and is_equal_approx(SaverScreen.zoom_fuer(Vector2i(4000, 2250), uhd, SaverScreen.ZOOM), 4000.0 / 3840.0)
			and is_equal_approx(SaverScreen.zoom_fuer(Vector2i(1920, 1080), Vector2(1920, 1080), SaverScreen.ZOOM), 1.0),
			"genau passend: keine Fahrt; größer: Fahrt nur so weit, wie die Datei Bildpunkte hat")
	check(SaverScreen.zoom_fuer(Vector2i.ZERO, uhd, SaverScreen.ZOOM) == 0.0, "ohne Größe: nicht zeigen")


func _png(path: String, col: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(col)
	img.save_png(path)


func _slides() -> void:
	print("Bilder nur von der Platte")
	var media := Config.media_dir()
	_png(media.path_join("ps2/hero/Okami.png"), Color.ORANGE)
	_png(media.path_join("gc/hero/Wind Waker.png"), Color.SKY_BLUE)
	var games: Array = [
		{ "id": "r1", "title": "Okami", "system": "ps2", "source": "rom", "favorite": true, "path": "D:/Spiele/PS2/Okami.iso" },
		{ "id": "r2", "title": "Ohne Bild", "system": "ps2", "source": "rom" },
		{ "id": "r3", "title": "Wind Waker", "system": "gc", "source": "rom", "playtime": 7200 },
		{ "id": "r4", "title": "Auch ohne", "system": "gba", "source": "rom" },
	]
	var shot := media.path_join("shots/eigenes.png")
	_png(shot, Color.DARK_GREEN)
	var sv := Saver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	sv.prepare(games,
			[{ "slide": true, "path": shot, "title": "Okami", "sub": "Dein Bildschirmfoto", "logo": "" },
			{ "slide": true, "path": media.path_join("fehlt.png"), "title": "weg" }], rng)
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var order: Array = []
	for i in 9:
		var s := sv.next_slide()
		order.append(str(s.get("path", "")).get_file())
		seen[str(s.get("path", ""))] = s
	check(seen.size() == 3 and seen.has(shot), "drei Bilder: zwei Spiele mit Bild und das Bildschirmfoto (%s)" % str(order))
	check(not seen.has(media.path_join("fehlt.png")), "fehlende Datei wird übersprungen")
	check(seen.has(media.path_join("ps2/hero/Okami.png")), "Spiel mit eigenem Pfad (ROM) bekommt sein Bild")
	var same := false
	for i in range(1, order.size()):
		if order[i] == order[i - 1]:
			same = true
	check(not same, "nie zweimal dasselbe Bild hintereinander")
	var ok_slide: Dictionary = seen.get(media.path_join("ps2/hero/Okami.png"), {})
	check(str(ok_slide.get("title", "")) == "Okami" and str(ok_slide.get("sub", "")).begins_with(str(Config.system("ps2").get("name", "?"))),
			"Bildunterschrift: Name und Plattform (%s)" % str(ok_slide.get("sub", "")))
	check(Time.get_ticks_msec() - t0 < 500, "schnell, ohne auf etwas zu warten")
	sv.zu_klein(shot)
	var ohne := true
	for i in 6:
		ohne = ohne and str(sv.next_slide().get("path", "")) != shot
	check(ohne, "zu kleines Bild: kommt in dieser Runde nicht wieder")
	check(Media._resolving.is_empty() and Media._pending.is_empty(), "nichts aus dem Netz angefragt")
	var none := Saver.new()
	none.prepare([{ "id": "x", "title": "Nichts", "system": "gba", "source": "rom" }], [], rng)
	check(none.next_slide().is_empty(), "gar kein Bild: leer (dann nur die Uhr)")
	sv.free()
	none.free()


func _screen() -> void:
	print("Eingabe weckt nur")
	var fake := FakeSaver.new()
	add_child(fake)
	var scr := SaverScreen.new()
	scr.saver = fake
	scr.simple = true
	add_child(scr)
	await get_tree().process_frame
	check(Nav.top_layer() == scr and fake.stops == 0, "oberste Ebene für die Steuerung, bleibt offen")
	var fired: Array = []
	var on_cmd := func(c: String) -> void: fired.append(c)
	Nav.command.connect(on_cmd)
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.physical_keycode = KEY_ENTER
	k.pressed = true
	get_tree().root.push_input(k)
	check(fake.stops == 1, "Taste weckt")
	check(fired.is_empty(), "und löst sonst nichts aus (%s)" % str(fired))
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	get_tree().root.push_input(jb)
	check(fake.stops == 2 and fired.is_empty(), "Controller-Taste A: weckt, wählt nichts aus")
	var small := InputEventMouseMotion.new()
	small.relative = Vector2(1, 1)
	small.screen_relative = Vector2(1, 1)
	get_tree().root.push_input(small)
	check(fake.stops == 2, "Scheinbewegung der Maus weckt nicht")
	Nav._fire("down")
	Nav._fire("guide")
	check(fake.stops == 4 and fired.is_empty(), "Stick (von der Steuerung abgefragt) und Guide: nur wecken")
	scr.leave(true)
	check(not Nav.layers.has(scr), "danach ist die Steuerung wieder frei")
	await get_tree().process_frame
	Nav.command.disconnect(on_cmd)
	fake.queue_free()

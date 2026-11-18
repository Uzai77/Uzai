extends Node
## Kluge Bildzuschnitte und einheitliche Farbabstimmung (Punkt 97) mit erzeugten Testbildern:
## Motiv am Rand bleibt im Ausschnitt, ruhige Bilder bleiben mittig, Schrift oben auf einem Cover
## wird nicht abgeschnitten, nie verzerrt, Akzentfarbe im Helligkeitsband, Zwischenspeicher,
## Anzeige über AtlasTexture, Rechenzeit. Aufruf: godot --headless --path . res://tests/logic_zuschnitt.tscn

const Z := preload("res://src/core/zuschnitt.gd")
const MediaS := preload("res://src/core/media.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_crop()
	_color()
	_cache()
	await _show()
	_speed()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# --- Testbilder --------------------------------------------------------------------------------

## Breites Bild (Hero-Form): ruhiger dunkler Verlauf, rechts ein Motiv mit vielen Kanten.
static func wide_subject(w := 480, h := 120, at := 0.8) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(0.1 + 0.08 * x / w, 0.12, 0.16))
	var cx := int(w * at)
	for y in range(int(h * 0.15), int(h * 0.85)):
		for x in range(cx - w / 12, cx + w / 12):
			var on := ((x / 6) + (y / 6)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.8, 0.3) if on else Color(0.2, 0.1, 0.05))
	return img


## Hochkant-Cover: weicher Farbverlauf, oben ein Schriftzug (dichte harte Kanten), unten nichts.
static func cover_title(w := 200, h := 300) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(0.15, 0.2 + 0.3 * y / h, 0.5))
	for y in range(10, 44):
		for x in range(24, w - 24):
			if (x / 3) % 3 != 0 and (y / 4) % 4 != 3:
				img.set_pixel(x, y, Color(1, 1, 1))
	# Ein weiches Motiv in der Mitte (wenig harte Kanten).
	for y in range(120, 200):
		for x in range(60, 140):
			var d := Vector2(x - 100, y - 160).length() / 40.0
			if d < 1.0:
				img.set_pixel(x, y, Color(0.15, 0.2 + 0.3 * y / h, 0.5).lerp(Color(0.8, 0.5, 0.4), 1.0 - d))
	return img


## Gleichmäßiges Rauschen: nirgends mehr los als anderswo.
static func noise(w := 320, h := 180) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v))
	return img


static func look(img: Image) -> Dictionary:
	return MediaS.look_of(img)


# --- Zuschnitt ---------------------------------------------------------------------------------

func _crop() -> void:
	print("Zuschnitt")
	var ws := wide_subject()
	var lw := look(ws)
	check(lw.has("x") and lw.has("y") and (lw.x as PackedFloat32Array).size() == Z.BINS, "Analyse liefert zwei Profile mit 16 Fächern")
	var r := Z.region(lw, Vector2(480, 120), Vector2(200, 200))
	check(absf(r.size.x / r.size.y - 1.0) < 0.01, "Ausschnitt hat das Seitenverhältnis der Fläche (nie verzerrt)")
	var subj := Rect2(480 * 0.8 - 40, 0, 80, 120)
	check(r.encloses(Rect2(subj.position.x, r.position.y, subj.size.x, r.size.y)),
			"Motiv am rechten Rand bleibt ganz im quadratischen Ausschnitt (x %d…%d)" % [r.position.x, r.end.x])
	var mid := Rect2((480 - 120) / 2.0, 0, 120, 120)
	check(not mid.encloses(Rect2(subj.position.x, 0, subj.size.x, 120)), "stumpf mittig hätte das Motiv abgeschnitten")
	var left := Z.region(look(wide_subject(480, 120, 0.15)), Vector2(480, 120), Vector2(120, 120))
	check(left.position.x < 60 - 40 + 1 and left.end.x >= 72 + 40 - 1, "Motiv links: Ausschnitt geht nach links (x %d…%d)" % [left.position.x, left.end.x])
	var n := noise()
	var rn := Z.region(look(n), Vector2(320, 180), Vector2(100, 180))
	check(absf(rn.get_center().x - 160.0) < 320 * 0.06, "gleichmäßiges Bild: bleibt (fast) mittig (Mitte %d)" % rn.get_center().x)
	var flat := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.3, 0.3, 0.3))
	var rf := Z.region(look(flat), Vector2(64, 64), Vector2(64, 20))
	check(is_equal_approx(rf.position.y, 22.0), "einfarbiges Bild: genau mittig wie bisher")
	# Hochkant-Cover in eine breite Kachel: der Schriftzug oben bleibt ganz drin.
	var ct := cover_title()
	var rc := Z.region(look(ct), Vector2(200, 300), Vector2(460, 215))
	check(rc.position.y <= 10.0 and rc.end.y >= 44.0, "Cover → breite Kachel: Schriftzug oben bleibt ganz (y %d…%d)" % [rc.position.y, rc.end.y])
	check(absf(rc.size.x / rc.size.y - 460.0 / 215.0) < 0.01, "breite Kachel: Seitenverhältnis stimmt")
	# Ohne Analyse: genau die Mitte (wie STRETCH_KEEP_ASPECT_COVERED).
	var r0 := Z.region({}, Vector2(480, 120), Vector2(200, 200))
	check(r0.position.is_equal_approx(Vector2(180, 0)) and r0.size.is_equal_approx(Vector2(120, 120)), "ohne Analyse mittig")
	# Nie über den Rand und nie verzerrt, für viele Formen.
	var ok := true
	for box in [Vector2(10, 300), Vector2(300, 10), Vector2(1, 1), Vector2(1920, 820), Vector2(216, 288), Vector2(400, 225)]:
		for img_s in [Vector2(480, 120), Vector2(200, 300), Vector2(320, 180)]:
			var rr := Z.region(lw, img_s, box)
			if rr.position.x < -0.01 or rr.position.y < -0.01 or rr.end.x > img_s.x + 0.01 or rr.end.y > img_s.y + 0.01:
				ok = false
			if absf(rr.size.x / rr.size.y - box.x / box.y) > 0.02 * box.x / box.y:
				ok = false
	check(ok, "alle Formen: Ausschnitt im Bild und unverzerrt")
	# Dichte Kanten am Rand (Schrift) werden nicht mittendurch geschnitten.
	var prof := PackedFloat32Array([0.16, 0.16, 0.16, 0.02, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05])
	var o := Z.pick(Z.pool(prof), 0.55)
	check(o < 0.001, "Schrift am Rand bleibt ganz im Fenster (Beginn %.3f)" % o)
	# Media: Ausschnitt für eine feste Fläche (Hintergrund, Spielseite, Ruhebildschirm).
	var cut := MediaS.cover_image(ws.duplicate(), Vector2i(120, 120), lw)
	check(cut.get_width() == 120 and cut.get_height() == 120, "fit-Ausschnitt hat genau die Größe der Fläche")
	var cc := cut.get_pixel(60, 60)
	var mid_cut := MediaS.cover_image(ws.duplicate(), Vector2i(120, 120))
	check(cc.r > 0.15 and mid_cut.get_pixel(60, 60).r < 0.25 and _edges(cut) > _edges(mid_cut) * 3.0,
			"fit-Ausschnitt zeigt das Motiv, mittig nur den leeren Verlauf")


static func _edges(img: Image) -> float:
	var e := 0.0
	for y in img.get_height():
		for x in range(1, img.get_width()):
			e += absf(img.get_pixel(x, y).get_luminance() - img.get_pixel(x - 1, y).get_luminance())
	return e


# --- Farbe -------------------------------------------------------------------------------------

func _color() -> void:
	print("Farbabstimmung")
	var white_ok := true
	var bg_ok := true
	var hue_ok := true
	for c in [Color(1, 1, 0), Color(0, 1, 0.2), Color(0, 0, 1), Color(0.15, 0.0, 0.4), Color(1, 0.1, 0.6), Color(0.05, 0.3, 0.05), Color(1, 0.55, 0.0),
			Color(0.6, 0.9, 1.0)]:
		var a := Z.accent(c)
		var l := Z.luminance(a)
		if (1.05 / (l + 0.05)) < 2.99:
			white_ok = false
			print("       zu hell: %s → %s (L %.3f)" % [c, a, l])
		if l < Z.ACCENT_L.x - 0.005:
			bg_ok = false
			print("       zu dunkel: %s → %s (L %.3f)" % [c, a, l])
		if absf(a.h - c.h) > 0.02 and absf(a.h - c.h) < 0.98:
			hue_ok = false
	check(white_ok, "Akzentfarbe: weiße Schrift darauf hat mindestens 3 : 1 Kontrast (auch Neongelb)")
	check(bg_ok, "Akzentfarbe: nie so dunkel, dass sie im Raum verschwindet (auch Tiefblau)")
	check(hue_ok, "Akzentfarbe behält den Farbton")
	var y := Z.accent(Color(1, 1, 0))
	check(y.s >= 0.3 and y.s <= Z.ACCENT_S.y + 0.001, "Sättigung gemäßigt (%.2f)" % y.s)
	check(Z.tone(0.9).r < 1.0 and Z.tone(0.9).r >= Z.TONE_MIN - 0.001 and Z.tone(0.2) == Color.WHITE, "helle Bilder leicht gedämpft, dunkle nicht")
	var bright := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	bright.fill(Color(0.95, 0.95, 0.95))
	check(float(look(bright).l) > 0.85, "Helligkeit eines weißen Bilds erkannt")
	var red := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	red.fill(Color(0.1, 0.1, 0.1))
	red.fill_rect(Rect2i(0, 0, 32, 20), Color(0.85, 0.15, 0.12))
	var lr := look(red)
	check(lr.get("c") is Color and (lr.c as Color).h < 0.08 and Z.luminance(lr.c) <= Z.ACCENT_L.y + 0.001, "Analyse bringt die abgestimmte Spielfarbe mit")
	var sc := Z.scrim()
	check(sc != null and sc == Z.scrim(), "ein gemeinsamer Verlauf für alle Kacheln")


# --- Zwischenspeicher --------------------------------------------------------------------------

func _cache() -> void:
	print("Zwischenspeicher")
	var lw := look(wide_subject())
	var e := MediaS.look_encode(lw, 1234)
	var back := MediaS.look_decode(JSON.parse_string(JSON.stringify(e)))
	check(back.has("x") and absf(float(back.l) - float(lw.l)) < 0.002, "Eintrag übersteht Speichern und Laden")
	var r1 := Z.region(lw, Vector2(480, 120), Vector2(200, 200))
	var r2 := Z.region(back, Vector2(480, 120), Vector2(200, 200))
	check(absf(r1.position.x - r2.position.x) < 6.0, "gleicher Ausschnitt nach dem Laden (%d / %d)" % [r1.position.x, r2.position.x])
	check((back.c as Color).is_equal_approx(Color.html((lw.c as Color).to_html(false))), "Farbe übersteht Speichern und Laden")
	var bad := [[1, "zz", "00", 5, ""], [1, "00".repeat(16), "00".repeat(16), 5, "<script>"], "x", [1, 2, 3], [1, "00".repeat(16), "00".repeat(16), "5", ""]]
	var rejected := true
	for b in bad:
		if not MediaS.look_decode(b).is_empty():
			rejected = false
	check(rejected, "kaputte oder fremde Einträge werden verworfen")
	# Über Media: einmal gerechnet, dann gemerkt (auch die Spielfarbe ohne geladenes Bild).
	var p := Config.path("cache/zuschnitt_test.png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	wide_subject().save_png(p)
	check(Media.look_cached(p).is_empty(), "vorher nichts gemerkt")
	var img := Media.load_image(p)
	var l1 := Media.look_for(p, img)
	var l2 := Media.look_cached(p)
	check(l1.has("x") and l2.has("x"), "nach dem ersten Mal gemerkt")
	Media.save_looks_now()
	Media._looks_due = true
	Media.save_looks_now()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.path(MediaS.LOOKS_FILE)))
	check(saved is Dictionary and (saved as Dictionary).has(p), "Zwischenspeicher liegt auf der Platte")


# --- Anzeige -----------------------------------------------------------------------------------

func _show() -> void:
	print("Anzeige")
	var ws := wide_subject()
	var tex := ImageTexture.create_from_image(ws)
	tex.set_meta("uz_look", look(ws))
	tex.set_meta("uz_vivid", [Color(0.5, 0.4, 0.2)])
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = Vector2(200, 200)
	add_child(tr)
	Z.put(tr, tex)
	var at := tr.texture as AtlasTexture
	check(at != null and at.atlas == tex and absf(at.region.size.x / at.region.size.y - 1.0) < 0.01 and at.region.position.x > 180.0,
			"Karte zeigt den klugen Ausschnitt (AtlasTexture, Beginn %d)" % (at.region.position.x if at else -1))
	check(at != null and at.has_meta("uz_vivid") and Media.color_of(at) == Color(0.5, 0.4, 0.2), "Ausschnitt trägt Farbe und Analyse des Bilds weiter")
	check(tr.has_node("UzScrim"), "gemeinsamer Verlauf liegt über dem Bild")
	tr.size = Vector2(480, 120)
	check(tr.texture == tex, "Fläche hat die Form des Bilds: wieder das Bild selbst")
	tr.size = Vector2(100, 300)
	var at2 := tr.texture as AtlasTexture
	check(at2 != null and absf(at2.region.size.x / at2.region.size.y - 1.0 / 3.0) < 0.01, "Größe ändert sich (Karte wird breit/schmal): Ausschnitt folgt")
	tr.texture = null
	tr.size = Vector2(200, 200)
	check(tr.texture == null, "Bild freigegeben: nichts wird wieder gesetzt")
	var plain := ImageTexture.create_from_image(ws)
	Z.put(tr, plain)
	check(tr.texture == plain and tr.self_modulate == Color.WHITE, "Bild ohne Analyse: genau wie bisher")
	var white := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	white.fill(Color(0.97, 0.97, 0.97))
	var wt := ImageTexture.create_from_image(white)
	wt.set_meta("uz_look", look(white))
	Z.put(tr, wt)
	check(tr.self_modulate.r < 1.0, "helles Kachelbild leicht gedämpft (%.2f)" % tr.self_modulate.r)
	tr.queue_free()
	await get_tree().process_frame


# --- Rechenzeit --------------------------------------------------------------------------------

func _speed() -> void:
	print("Rechenzeit")
	var hero := Image.create(3840, 1240, false, Image.FORMAT_RGB8)
	hero.fill(Color(0.2, 0.3, 0.4))
	var cover := Image.create(600, 900, false, Image.FORMAT_RGB8)
	cover.fill(Color(0.5, 0.2, 0.1))
	var t0 := Time.get_ticks_usec()
	for i in 3:
		look(hero)
	var th := (Time.get_ticks_usec() - t0) / 3000.0
	t0 = Time.get_ticks_usec()
	for i in 10:
		look(cover)
	var tc := (Time.get_ticks_usec() - t0) / 10000.0
	print("       Hero 3840 × 1240: %.1f ms, Cover 600 × 900: %.1f ms (Hintergrund-Thread, einmal je Bild)" % [th, tc])
	check(tc < 25.0, "Cover-Analyse schnell (%.1f ms)" % tc)
	check(th < 120.0, "Hero-Analyse vertretbar (%.1f ms)" % th)
	var lw := look(wide_subject())
	t0 = Time.get_ticks_usec()
	for i in 1000:
		Z.region(lw, Vector2(480, 120), Vector2(200 + i % 50, 200))
	var tr := (Time.get_ticks_usec() - t0) / 1000.0
	print("       Ausschnitt wählen: %.1f µs" % tr)
	check(tr < 400.0, "Ausschnitt wählen kostet fast nichts (auch beim Breitwerden je Bild)")

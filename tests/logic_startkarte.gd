extends Node
## Spielstart-Karte ohne Bildschirm: Bildwahl, nie hochziehen, Logo-Grenze, Steam-Hinweise,
## Zustandstext, Bildvorbereitung im Hintergrund-Thread.
## Aufruf: godot --headless --path . res://tests/logic_startkarte.tscn

const Art := preload("res://src/ui/layers/launch_art.gd")

var fails := 0
const V := Vector2(1920, 1080)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Bildwahl (Rückfallkette)")
	var hero2x := Vector2(3840, 1240)
	var hero1x := Vector2(1920, 620)
	var cover := Vector2(600, 900)
	check(Art.pick({ "hero": hero2x, "cover": cover }, V, 1.0).mode == "hero", "1080p: großer Hero ganzflächig")
	check(Art.pick({ "hero": hero2x }, V, 2.0).mode == "hero", "4K: Hero 3840 reicht (Streifen, nicht hochgezogen)")
	check(Art.pick({ "hero": hero1x, "cover": cover }, V, 1.0).mode == "hero", "1080p: Hero 1920 als Streifen")
	var p4 := Art.pick({ "hero": hero1x, "cover": cover }, V, 2.0)
	check(p4.mode == "box" and p4.front == "cover" and p4.back == "hero", "4K: kleiner Hero → Hülle scharf, Hero weich dahinter")
	var pb := Art.pick({ "cover": cover }, V, 1.0)
	check(pb.mode == "box" and pb.front == "cover" and pb.back == "cover", "nur Hülle: Hülle vorn, Grund aus der Hülle")
	var pw := Art.pick({ "wide": Vector2(460, 215) }, V, 1.0)
	check(pw.mode == "box" and pw.front == "wide", "nur breites Bild: als Element")
	var ps := Art.pick({ "hero": Vector2(960, 310) }, V, 1.0)
	check(ps.mode == "box" and ps.front == "hero", "nur winziger Hero: als Element, nie hochgezogen")
	check(Art.pick({}, V, 1.0).mode == "plain", "ohne Bilder: Farben und gesetzter Titel")

	print("Nie hochziehen")
	check(Art.band_scale(hero2x, V, 1.0) < 1.0, "1080p: Hero 3840 wird verkleinert (%.2f)" % Art.band_scale(hero2x, V, 1.0))
	check(Art.band_scale(hero2x, V, 2.0) <= Art.UP_TOL + 0.001, "4K: höchstens %.2f-fach (%.2f)" % [Art.UP_TOL, Art.band_scale(hero2x, V, 2.0)])
	check(Art.band_scale(hero1x, V, 1.0) <= Art.UP_TOL + 0.001, "1080p, Hero 1920: höchstens UP_TOL")
	var b := Art.band(hero1x, V, 1.0)
	check(b.position.y > 0.0 and b.end.y < V.y and b.size.x >= V.x, "Streifen: volle Breite, oben und unten weicher Auslauf")
	var full := Art.band(Vector2(3840, 2160), V, 1.0)
	check(full.position.x <= 0.0 and full.position.y <= 0.0 and full.end.x >= V.x and full.end.y >= V.y, "16:9-Bild deckt den Schirm")

	print("Logo und Hülle in Bildschirmpunkten")
	var l1 := Art.fit_native(Vector2(640, 360), Art.LOGO_BOX, 1.0)
	check(l1 == Vector2(587, 330), "1080p: 640er Logo eingepasst %s" % l1)
	var l2 := Art.fit_native(Vector2(640, 360), Art.LOGO_BOX, 2.0)
	check(l2 == Vector2(320, 180), "4K: 640er Logo nie über seine Größe (320 UI = 640 Punkte) %s" % l2)
	var l3 := Art.fit_native(Vector2(1280, 720), Art.LOGO_BOX, 2.0)
	check(is_equal_approx(l3.y, 330.0) and l3.x * 2.0 == roundf(l3.x * 2.0), "4K: großes Logo eingepasst, ganze Bildschirmpunkte %s" % l3)
	check(Art.fit_native(Vector2(200, 100), Art.LOGO_BOX, 1.0) == Vector2(200, 100), "kleines Logo bleibt 1:1")
	check(not Art.logo_ok(Vector2(180, 50), Art.LOGO_BOX, 1.0), "winziges Logo: lieber der gesetzte Titel")
	check(not Art.logo_ok(Vector2(400, 110), Art.LOGO_BOX, 2.0), "4K: 400er Logo wäre 200 UI breit → Titel")
	check(Art.logo_ok(Vector2(640, 360), Art.LOGO_BOX, 2.0), "4K: Steam-Logo 640 reicht")
	var bx := Art.fit_native(Vector2(600, 900), Art.BOX_BOX, 2.0)
	check(bx == Vector2(300, 450), "4K: Hülle 600 × 900 in ihrer Größe %s" % bx)

	print("Steam-Hinweise (appmanifest)")
	check(Art.steam_note({ "StateFlags": "4" }).text == "", "installiert: kein Hinweis")
	check(str(Art.steam_note({ "StateFlags": str(4 | 131072) }).text).contains("überprüft Dateien"), "Prüfen")
	var up := Art.steam_note({ "StateFlags": str(2 | 1024 | 1048576), "BytesToDownload": "1000", "BytesDownloaded": "250" })
	check(str(up.text) == "Steam lädt ein Update · 25 %" and is_equal_approx(float(up.frac), 0.25), "Update lädt: %s" % up.text)
	check(str(Art.steam_note({ "statEflags": str(2 | 4 | 4194304) }).text).contains("installiert ein Update"), "Committing, Schlüssel ohne Groß/klein")
	check(str(Art.steam_note({ "StateFlags": "6" }).text).contains("bereitet ein Update vor"), "Update nötig")
	check(Art.steam_note({ "StateFlags": str(2 | 4 | 512) }).text == "", "pausiertes Update: kein Hinweis")

	print("Zustandstext ohne Titel")
	check(Art.status_text("Steam startet Portal 2 …", "Portal 2") == "Steam startet …", "Steam startet …")
	check(Art.status_text("Portal 2 startet …", "Portal 2") == "Wird gestartet …", "Titel startet → Wird gestartet")
	check(Art.status_text("PCSX2 startet …", "Ōkami") == "PCSX2 startet …", "Emulator bleibt")
	check(Art.status_text("", "x") == "Wird gestartet …", "leer")

	print("Vorbereiten im Hintergrund-Thread")
	var dir := OS.get_user_data_dir().path_join("startkarte_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var hp := dir.path_join("hero.png")
	var hi := Image.create(3840, 1240, false, Image.FORMAT_RGB8)
	hi.fill(Color(0.2, 0.3, 0.6))
	hi.save_png(hp)
	var lp := dir.path_join("logo.png")
	var li := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	li.fill(Color(1, 1, 1, 0))
	li.fill_rect(Rect2i(100, 200, 1000, 300), Color(1, 0.9, 0.7, 1))
	li.save_png(lp)
	for pxs in [1.0, 2.0]:
		var box := { "m": Mutex.new(), "done": false, "res": null }
		var id := WorkerThreadPool.add_task(Art.prepare.bind(box, { "hero": hp, "logo": lp }, V, pxs))
		WorkerThreadPool.wait_for_task_completion(id)
		var r: Dictionary = box.res
		var bi: Image = r.back_img
		var lg: Image = r.logo_img
		check(r.mode == "hero" and bi.has_mipmaps(), "%.0f×: Hero mit Mipmaps (für den weichen Rand)" % pxs)
		check(bi.get_width() <= 3840 and bi.get_width() >= mini(3840, int(Art.band(Vector2(3840, 1240), V, pxs).size.x * pxs)),
				"%.0f×: Hero nicht kleiner als gezeichnet (%d)" % [pxs, bi.get_width()])
		var lsz: Vector2 = r.logo_size
		check(Vector2(lg.get_size()) == (lsz * pxs).round(), "%.0f×: Logo genau in Bildschirmpunkten (%s = %s)" % [pxs, lg.get_size(), lsz * pxs])
		check(lg.get_width() <= 1000 and lg.get_height() <= 300, "%.0f×: durchsichtiger Rand abgeschnitten, nie vergrößert" % pxs)
		check(r.glow_img is Image and float(r.glow_pad) > 0.0, "%.0f×: Hof unter dem Logo" % pxs)
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)

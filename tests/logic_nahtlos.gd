extends Node
## Nahtlos und Signaturen (Plan „Gefühl“, Paket D): Mitteilungen nie über dem Cursor und erst in
## Ruhe, Grundfarbe je Bild (Prüfung, Mittel, Platzhalter), kein Ersatz-Cover unter einem deckenden
## Bild (Geister-Titel), Fortschrittsbalken ohne Rückschritt, Lage der Wortmarke im Guide und beim
## Start, Rechteck der Zimmer-Kachel.
## Aufruf: godot --headless --path . res://tests/logic_nahtlos.tscn

const ToastsS := preload("res://src/ui/toasts.gd")
const MediaS := preload("res://src/core/media.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const Bar := preload("res://src/ui/components/progress_bar.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Boot := preload("res://src/ui/boot.gd")
const Logo := preload("res://src/ui/components/uzai_logo.gd")
const MainE := preload("res://src/main_ebenen.gd")
const U := preload("res://src/ui/u.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Echte Zeit abwarten (Zeitgeber zählen ohne Fenster nach Bildern, nicht nach der Uhr).
func _warte_ms(ms: int) -> void:
	var ende := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < ende:
		await get_tree().process_frame


func _ready() -> void:
	var view := Vector2(1920, 1080)
	print("Mitteilungen: Platz")
	check(ToastsS.spot_frei(view, 120.0, []) == "oben", "nichts im Weg: rechts oben")
	# Cursor auf „Für dich“ oben rechts (wie in der Probe: 1278…1828 × 188…424).
	var fy := Rect2(1278, 188, 550, 236)
	check(ToastsS.spot_frei(view, 120.0, [fy]) == "unten", "Cursor oben rechts: rechts unten")
	check(ToastsS.spot_frei(view, 120.0, [Rect2(96, 600, 216, 288)]) == "oben", "Cursor links unten: oben bleibt frei")
	# Cursor unten rechts und „Für dich“ oben: nie über den Cursor.
	var unten := Rect2(1596, 860, 216, 120)
	check(ToastsS.spot_frei(view, 120.0, [unten, fy]) == "oben", "unten der Cursor, oben „Für dich“: über „Für dich“, nicht über den Cursor")
	var oben_r := Rect2(view.x - ToastsS.RIGHT - ToastsS.W, ToastsS.TOP, ToastsS.W, 120.0)
	check(not oben_r.intersects(Rect2(96, 600, 216, 288)), "Rechteck oben rechts liegt rechts")

	print("Mitteilungen: Ruhe")
	Toasts.unruhe()
	check(not Toasts.ruhig(), "gleich nach einem Wechsel: keine Ruhe")
	await _warte_ms(int((U.T_RAUM + 0.1) * 1000.0))
	check(Toasts.ruhig(), "T_RAUM danach: Ruhe")
	Toasts.unruhe(0.3)
	await _warte_ms(int((U.T_RAUM + 0.1) * 1000.0))
	check(not Toasts.ruhig(), "längerer Wechsel (Zimmer, Spielstart): wartet länger")

	print("Grundfarbe je Bild")
	check(MediaS.grund_pruefen("a.png", "1a2b3c") is Color, "gültig: Farbe")
	check(MediaS.grund_pruefen("a.png", "1a2b3") == null and MediaS.grund_pruefen("a.png", "zzzzzz") == null, "falsche Länge oder kein Hex: nichts")
	check(MediaS.grund_pruefen("a.png", 123) == null and MediaS.grund_pruefen(5, "1a2b3c") == null, "falsche Typen: nichts")
	check(MediaS.grund_pruefen("x".repeat(2000), "1a2b3c") == null and MediaS.grund_pruefen("", "1a2b3c") == null, "Schlüssel zu lang oder leer: nichts")
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.4))
	var m: Variant = MediaS.mittelfarbe(img)
	var nah := m is Color and absf((m as Color).r - 0.8) < 0.01 and absf((m as Color).g - 0.2) < 0.01 and absf((m as Color).b - 0.4) < 0.01
	check(nah, "Mittel eines einfarbigen Bilds: diese Farbe")
	var halb := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	halb.fill(Color(1, 1, 1, 0))
	halb.fill_rect(Rect2i(0, 0, 32, 16), Color(0, 0, 1, 1))
	var mh: Variant = MediaS.mittelfarbe(halb)
	check(mh is Color and (mh as Color).b > 0.95 and (mh as Color).r < 0.05, "durchsichtige Punkte zählen nicht")
	var leer := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	leer.fill(Color(0, 0, 0, 0))
	check(MediaS.mittelfarbe(leer) == null, "ganz durchsichtig: keine Farbe")
	var p := "res://icon.svg"
	check(Media.grundfarbe(p) == null, "unbekanntes Bild: keine Grundfarbe")
	Media._grund_merken(p, img)
	var g: Variant = Media.grundfarbe(p)
	check(g is Color and absf((g as Color).g - 0.2) < 0.01, "gemerkt: Grundfarbe zur Datei")

	print("Platzhalter in der Grundfarbe")
	var sk: Control = Skeleton.fill(0, Color(0.8, 0.2, 0.4))
	add_child(sk)
	sk.size = Vector2(216, 288)
	await get_tree().process_frame
	check((sk.shapes[0] as Dictionary).get("farbe") is Color, "Skeleton.fill übernimmt die Farbe")
	check(Skeleton.grund(Color(0.8, 0.2, 0.4)).a == 1.0, "Fläche deckend")
	var sk2: Control = Skeleton.fill(0, "kaputt")
	add_child(sk2)
	sk2.size = Vector2(10, 10)
	await get_tree().process_frame
	check((sk2.shapes[0] as Dictionary).get("farbe") == null, "keine Farbe: neutral wie bisher")
	sk.queue_free()
	sk2.queue_free()

	print("Kein Geister-Titel unter dem Bild")
	var gm := { "id": "probe:1", "title": "Ein langer Titel", "source": "steam", "installed": true }
	var card: Control = CoverCard.new().setup(gm, false, Vector2(216, 288))
	card.lazy = true
	add_child(card)
	await get_tree().process_frame
	card.call("_build")
	var tex := ImageTexture.create_from_image(img)
	card.set("_sync_tex", true)
	card.call("_on_texture", tex, int(card.get("_img_gen")))
	card.set("_sync_tex", false)
	check(not (card.get("_art") as Control).visible, "Bild sofort da: Ersatz-Cover weg")
	card.set("_requested", true)
	card.call("unload_image")
	check((card.get("_art") as Control).visible, "Bild entladen: Ersatz-Cover wieder da")
	card.call("_on_texture", tex, int(card.get("_img_gen")))
	check((card.get("_art") as Control).visible, "Bild blendet ein: Ersatz-Cover noch darunter")
	await _warte_ms(int((U.T_BASE + 0.15) * 1000.0))
	check(not (card.get("_art") as Control).visible, "Bild deckt: Ersatz-Cover weg")
	card.queue_free()

	print("Fortschrittsbalken")
	check(Bar.folge(0.5, 0.49, false) == 0.5, "kleiner Rückschritt: bleibt stehen")
	check(Bar.folge(0.5, 0.1, false) == 0.1, "echter Rückschritt (neuer Titel): sofort")
	check(Bar.folge(0.5, 0.7, false) == -1.0, "vorwärts: folgt als Feder")
	check(Bar.folge(0.5, 0.7, true) == 0.7, "ruhig oder unsichtbar: sofort")
	var bar: Control = Bar.new().setup(0.2, "accent", 6, 200)
	add_child(bar)
	bar.size = Vector2(200, 6)
	bar.set_value(0.8)
	var vorher := float(bar.get("shown"))
	var mono := true
	var t_ende := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < t_ende:
		await get_tree().process_frame
		var s := float(bar.get("shown"))
		if s < vorher - 0.0001 or s > 0.8001:
			mono = false
		vorher = s
	check(mono and absf(float(bar.get("shown")) - 0.8) < 0.02, "läuft ohne Überschwingen zum Ziel (%.3f)" % float(bar.get("shown")))
	bar.queue_free()

	print("Zeichen oben links")
	var r := Guide.mark_rect(null, view)
	check(r.position == Vector2(96, Logo.KOPF_MITTE.y - Logo.KOPF_H * 0.5) and is_equal_approx(r.size.y, Logo.KOPF_H), "im Spiel: oben links an seinem Platz")
	check(is_equal_approx(r.size.x, Logo.zeichen_breite(Logo.KOPF_H, Logo.KOPF_STIL == "kachel")), "Breite wie das Zeichen")
	var bm: Control = Logo.new()
	add_child(bm)
	bm.position = Vector2(120, 40)
	bm.size = Vector2(70, 30)
	await get_tree().process_frame
	check(Guide.mark_rect(bm, view) == Rect2(120, 40, 70, 30), "über der Kopfzeile: genau dort")
	bm.queue_free()
	var zr: Rect2 = Boot.zeichen_rect(view)
	check(absf(zr.get_center().x - 960.0) < 1.0 and is_equal_approx(zr.size.x, zr.size.y), "Start: das Zeichen mittig, Kachel quadratisch")
	check(float(Boot.phasen(0.2).linie) == 0.0 and float(Boot.phasen(0.2).baender) == 0.0, "Start: vor der Linie unsichtbar")

	print("Zimmer-Kachel")
	check(MainE.zimmer_kachel_rect(null) == Rect2(), "ohne Kachel: kein Rechteck")
	var kachel := Control.new()
	kachel.set_meta("uz_key", "apps:zimmer")
	add_child(kachel)
	kachel.position = Vector2(100, 120)
	kachel.size = Vector2(320, 180)
	var andere := Control.new()
	andere.set_meta("uz_key", "g:steam:1")
	add_child(andere)
	andere.size = Vector2(216, 288)
	await get_tree().process_frame
	check(MainE.zimmer_kachel_rect(kachel) == Rect2(100, 120, 320, 180), "Live-Bild: sein Rechteck")
	check(MainE.zimmer_kachel_rect(andere) == Rect2(), "anderes Element: kein Rechteck")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

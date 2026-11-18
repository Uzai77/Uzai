extends Node
## Die gemeinsame Medien-Sprache (docs/PLAN_MEDIEN.md) ohne Bildschirm: die Reihen unter der Bühne
## (Einrasten, Gedächtnis je Reihe, Hoch/Runter, Reihen darüber für die Steuerung aus), die Pillen
## der Bühne aus den Hinweisen einer Karte (A zuerst, dann X oder Y, höchstens zwei), die leise
## Zeile zu Videos und Streams, die Platzhalter, und der Player (Restzeit, Griff nur beim Spulen
## und in der Pause), das große Bild der Bühne (erst überblenden, wenn es fertig ist; Nachbarn in
## passender Größe vorgeladen).
## Aufruf: godot --headless --path . res://tests/logic_medien.tscn

const MedienReihen := preload("res://src/ui/components/medien_reihen.gd")
const MedienBuehne := preload("res://src/ui/components/medien_buehne.gd")
const VideosView := preload("res://src/ui/sections/videos_view.gd")
const StreamsView := preload("res://src/ui/sections/streams_view.gd")
const VideoPlayer := preload("res://src/ui/layers/video_player.gd")
const MovieBackdrop := preload("res://src/ui/components/movie_backdrop.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Eine schlichte Karte mit eigener Hoch/Runter-Steuerung (wie Video- und Filmkarten).
class _Karte extends Control:
	var nav_ud_cb: Callable
	var item: Dictionary = {}

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(120, 80)

	func nav_ud(d: int) -> bool:
		return bool(nav_ud_cb.call(d)) if nav_ud_cb.is_valid() else false


func _ready() -> void:
	await _reihen()
	_pillen()
	_zeilen()
	_player()
	_platzhalter()
	await _buehnenbild()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _reihen() -> void:
	print("Reihen unter der Bühne")
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var r = MedienReihen.new().setup(MedienBuehne.H)
	host.add_child(r)
	var rows: Array = []
	var cards: Array = []
	for i in 3:
		var row: Dictionary = r.add_row("Reihe %d" % i, "", "t%d" % i, 80.0)
		rows.append(row)
		var in_row: Array = []
		for k in 4:
			var c := _Karte.new()
			c.item = { "id": "%d-%d" % [i, k] }
			r.add_card(row, c, c.item)
			in_row.append(c)
		cards.append(in_row)
	check(r.row_count() == 3 and r.first_card() == cards[0][0], "drei Reihen, die erste Karte ist die erste der ersten Reihe")
	check(cards[0][0].has_meta("uz_entry") and not cards[0][1].has_meta("uz_entry"), "nur die erste Karte einer Reihe ist der Einstieg")
	check(cards[1][2].nav_ud_cb.is_valid(), "Karten geben Hoch/Runter an die Reihen ab")
	var got: Array = []
	r.row_focused.connect(func(idx: int, card: Control, it: Dictionary, dir: int) -> void: got.append([idx, card, it, dir]))
	await get_tree().process_frame
	cards[0][1].grab_focus()
	await get_tree().process_frame
	check(got.size() == 1 and int(got[0][0]) == 0 and got[0][1] == cards[0][1] and str((got[0][2] as Dictionary).get("id", "")) == "0-1",
			"die Bühne erfährt Reihe, Karte und Eintrag")
	cards[0][2].grab_focus()
	await get_tree().process_frame
	check(int(got[1][3]) == 1, "nach rechts geblättert: Richtung +1 (%d)" % int(got[1][3]))
	cards[0][0].grab_focus()
	await get_tree().process_frame
	check(int(got[2][3]) == -1, "nach links: Richtung −1")
	check(r.current() == 0 and not r.scrolled(), "erste Reihe: die Seite steht oben")
	# Runter: zur zweiten Reihe, dort zur ersten Karte (noch kein Gedächtnis).
	check(cards[0][0].nav_ud(1) and cards[1][0].has_focus(), "runter geht in die zweite Reihe, Karte 1")
	await get_tree().process_frame
	check(r.current() == 1 and r.scrolled(), "zweite Reihe gewählt: die Seite ist gerollt")
	check((rows[0].box as Control).has_meta("uz_skip") and not (rows[1].box as Control).has_meta("uz_skip"), "die Reihe darüber ist für die Steuerung aus")
	check(MedienReihen.hidden_above(1, 0) and not MedienReihen.hidden_above(1, 1) and not MedienReihen.hidden_above(1, 2), "hidden_above: nur Reihen über der gewählten")
	cards[1][3].grab_focus()
	await get_tree().process_frame
	check(cards[1][3].nav_ud(1) and cards[2][0].has_focus(), "runter in die dritte Reihe")
	await get_tree().process_frame
	check(cards[2][0].nav_ud(-1) and cards[1][3].has_focus(), "hoch: die zweite Reihe erinnert sich an Karte 4")
	await get_tree().process_frame
	check(cards[1][3].nav_ud(-1) and cards[0][0].has_focus(), "hoch in die erste Reihe (gemerkte Karte 1)")
	await get_tree().process_frame
	check(not cards[0][0].nav_ud(-1), "über der ersten Reihe: false – Nav geht zu den Unterreitern")
	cards[2][1].grab_focus()
	await get_tree().process_frame
	check(cards[2][1].nav_ud(1) and cards[2][1].has_focus(), "unter der letzten Reihe: anstoßen, die Auswahl bleibt")
	check(r.card_in(1) == cards[1][3] and r.card_in(5) == null, "card_in: gemerkte Karte, außerhalb null")
	r.reset()
	check(r.current() == 0 and not (rows[0].box as Control).has_meta("uz_skip") and r.card_in(1) == cards[1][0], "reset: oben, nichts verdeckt, Gedächtnis leer")
	check(MedienReihen.anriss_sichtbar(0.0, 300.0, 680.0) and MedienReihen.anriss_sichtbar(400.0, 300.0, 680.0)
			and not MedienReihen.anriss_sichtbar(600.0, 300.0, 680.0) and not MedienReihen.anriss_sichtbar(0.0, 0.0, 680.0)
			and MedienReihen.anriss_sichtbar(620.0, 60.0, 680.0), "anriss_sichtbar: was ganz passt oder mit Überschrift und einem Streifen")
	# Reihen in üblicher Höhe: die nächste ist angeschnitten zu sehen (Überschrift und ein Streifen).
	var mittel = MedienReihen.new().setup(MedienBuehne.H)
	mittel.instant = true
	host.add_child(mittel)
	for i in 3:
		var mr: Dictionary = mittel.add_row("Mittel %d" % i, "", "m%d" % i, 380.0)
		mittel.add_card(mr, _Karte.new(), {})
	await get_tree().process_frame
	await get_tree().process_frame
	var mb: Array = mittel.rows.map(func(x: Dictionary) -> Control: return x.box)
	check(is_equal_approx((mb[0] as Control).modulate.a, 1.0) and is_equal_approx((mb[1] as Control).modulate.a, MedienReihen.ANRISS_A)
			and is_equal_approx((mb[2] as Control).modulate.a, 0.0), "oben: die erste Reihe ganz, die zweite angeschnitten und leiser, die dritte aus")
	mittel.queue_free()
	# Sehr hohe Reihen: von der nächsten passte nicht einmal die Überschrift mit einem Streifen – sie bleibt aus.
	var gross = MedienReihen.new().setup(MedienBuehne.H)
	gross.instant = true
	host.add_child(gross)
	var gk: Array = []
	for i in 3:
		var gr: Dictionary = gross.add_row("Groß %d" % i, "", "g%d" % i, 600.0)
		var gc := _Karte.new()
		gross.add_card(gr, gc, {})
		gk.append(gc)
	await get_tree().process_frame
	await get_tree().process_frame
	var gb: Array = gross.rows.map(func(x: Dictionary) -> Control: return x.box)
	check(is_equal_approx((gb[0] as Control).modulate.a, 1.0) and is_equal_approx((gb[1] as Control).modulate.a, 0.0),
			"sehr hoch: die erste Reihe ganz, die nächste aus (%.1f)" % (gb[1] as Control).modulate.a)
	gross.snap(1)
	check(is_equal_approx((gb[1] as Control).modulate.a, 1.0) and is_equal_approx((gb[2] as Control).modulate.a, 0.0), "runter: die gewählte da, die nächste weiter aus")
	gross.queue_free()
	# Eine Reihe nachträglich an Stelle 1 einfügen (weitere Reihen der YouTube-Startseite).
	var neu: Dictionary = r.add_row("Dazwischen", "", "neu", 80.0, MedienReihen.GAP, 1)
	var nk := _Karte.new()
	r.add_card(neu, nk, { "id": "neu" })
	check(r.row_count() == 4 and r.rows[1] == neu and (neu.box as Control).get_index() == 1, "eingefügte Reihe steht an Stelle 1")
	await get_tree().process_frame
	check(cards[0][0].nav_ud(1) and nk.has_focus(), "runter aus der ersten Reihe trifft die eingefügte")
	host.queue_free()
	await get_tree().process_frame


func _pillen() -> void:
	print("Pillen der Bühne")
	var c := Control.new()
	add_child(c)
	c.set_meta("uz_hint_a", "Abspielen")
	c.set_meta("uz_hint_x", "Merken")
	c.set_meta("uz_on_x", func() -> void: pass)
	c.set_meta("uz_hint_y", "Optionen")
	c.set_meta("uz_on_y", func() -> void: pass)
	var t := MedienBuehne.tasten_von(c)
	var worte := t.map(func(p: Array) -> String: return str(p[0]) + ":" + str(p[1]))
	check(t.size() == 2 and t[0][0] == "a" and t[0][1] == "Abspielen" and t[1][0] == "x" and t[1][1] == "Merken", "A zuerst, dann X – höchstens zwei (%s)" % str(worte))
	check(t[0][2] is Callable and t[1][2] is Callable, "beide Pillen sind mit der Maus klickbar")
	c.remove_meta("uz_on_x")
	var t2 := MedienBuehne.tasten_von(c)
	check(t2.size() == 2 and t2[1][0] == "y" and t2[1][1] == "Optionen", "ohne X-Handlung steht Y (%s)" % str(t2[1][1]))
	c.set_meta("uz_hint_a", "—")
	c.remove_meta("uz_on_y")
	check(MedienBuehne.tasten_von(c).is_empty(), "Platzhalter-Hinweis „—“ und nichts auf X/Y: keine Pille")
	check(MedienBuehne.tasten_von(null).is_empty(), "ohne Karte keine Pille")
	c.queue_free()


func _zeilen() -> void:
	print("Leise Zeile der Bühne")
	var v := { "id": "zzTestVid01", "channel": "Pixelbude", "views": 47000, "published": int(Time.get_unix_time_from_system()) - 3 * 86400 }
	var z := VideosView.buehne_zeile(v)
	check(z.begins_with("Pixelbude  ·  47 Tsd. Aufrufe  ·  "), "Video: Kanal · Aufrufe · Alter (%s)" % z)
	check(VideosView.buehne_zeile({ "id": "x", "title": "ohne alles" }) == "", "ohne Angaben leer, nie „· …“")
	var urls := VideosView.big_urls({ "id": "zzTestVid01" })
	check(urls.size() == 2 and urls[0].contains("maxresdefault") and urls[1].contains("hqdefault"), "große Bilder: maxres zuerst, dann hq (%s)" % str(urls))
	check(VideosView.big_urls({ "id": "tw:abc", "thumb": "https://example.test/t.jpg" }) == ["https://example.test/t.jpg"], "eigene Adresse, wie sie ist")
	check(VideosView.big_urls({ "id": "tw:abc" }).is_empty(), "ohne Bild leer")
	var now := 1_760_000_000
	var live := { "id": "tw:1", "channel": "Pixelbude", "twitch": { "kind": "live", "game": "Okami", "viewers": 3200, "started": now - 3600 } }
	var zl := StreamsView.buehne_zeile(live, now)
	check(zl.begins_with("Pixelbude  ·  Okami  ·  3.200 Zuschauer"), "Stream live: Kanal · Kategorie · Zuschauer · seit (%s)" % zl)
	var vod := { "id": "tw:2", "channel": "Pixelbude", "duration": 7200, "published": now - 86400, "twitch": { "kind": "vod" } }
	var zv := StreamsView.buehne_zeile(vod, now)
	check(zv.begins_with("Pixelbude  ·  "), "Übertragung: Kanal · Alter (%s)" % zv)
	check(StreamsView.buehne_zeile({ "id": "g", "viewers": 312000 }, now) == "312 Tsd. Zuschauer", "Kategorie: nur die Zuschauer")


func _player() -> void:
	print("Player")
	check(VideoPlayer.left_text(754.0, 2000.0) == "−20:46", "Restzeit mit Minuszeichen (%s)" % VideoPlayer.left_text(754.0, 2000.0))
	check(VideoPlayer.left_text(0.0, 0.0) == "–:––", "ohne Länge „–:––“")
	check(VideoPlayer.left_text(2100.0, 2000.0) == "−0:00", "nie negativ")
	check(VideoPlayer.griff_staerke(0.0, false, false) == 0.0, "Griff ruht beim Abspielen")
	check(VideoPlayer.griff_staerke(0.6, false, false) == 0.6, "Griff kommt mit dem Spulen")
	check(VideoPlayer.griff_staerke(0.0, true, false) == 1.0, "Griff steht in der Pause")
	check(VideoPlayer.griff_staerke(1.0, true, true) == 0.0, "am Ende kein Griff")
	var h := VideoPlayer.hints_for(false, false, false)
	check(h.size() <= 4, "höchstens vier Hinweise unten (%d)" % h.size())


func _platzhalter() -> void:
	print("Platzhalter")
	var s = MedienReihen.skeleton(MedienBuehne.H, Vector2(352, 300), 2)
	var shapes: Array = s.shapes
	check(shapes.size() == 3 + 2 * 7, "Bühne (3 Zeilen) und zwei Reihen mit Überschrift und sechs Karten (%d Formen)" % shapes.size())
	var karten := shapes.filter(func(f: Dictionary) -> bool: return (f.r as Rect2).size == Vector2(352, 300))
	check(karten.size() == 12 and (karten[0].r as Rect2).position.x == 96.0, "Karten in Kartengröße, bündig mit dem Rand")
	check((karten[0].r as Rect2).position.y > MedienBuehne.H and (shapes[1].r as Rect2).position.y < MedienBuehne.H, "Bühne über, Reihen unter der Kante")
	s.free()


func _bild(name: String, c: Color) -> String:
	var p := Config.path("cache/test_buehne_%s.png" % name)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var img := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	img.fill(c)
	img.save_png(p)
	return p


func _vorn(bd: Control) -> TextureRect:
	return (bd._slides[bd._front] as Control).get_node("Img") as TextureRect


func _warte(cond: Callable, n := 240) -> bool:
	for i in n:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _buehnenbild() -> void:
	print("Großes Bild der Bühne")
	var pa := _bild("a", Color.RED)
	var pb := _bild("b", Color.GREEN)
	var pc := _bild("c", Color.BLUE)
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var bd: Control = MovieBackdrop.new()
	bd.layout = "hero"
	host.add_child(bd)
	var area: Vector2 = bd.image_rect().size
	bd.show_item({ "id": "a", "_urls": [pa] }, true)
	check(bd._front_gen == bd._gen and _vorn(bd).texture == null, "erster Aufbau: Farbfeld steht sofort da")
	check(await _warte(func() -> bool: return _vorn(bd).texture != null), "dann kommt das Bild darauf")
	var ta: Texture2D = _vorn(bd).texture
	check(ta != null and ta.get_height() < 700 and ta.get_width() <= int(area.x * Media.px_scale()),
			"nur der sichtbare Ausschnitt geladen (%s für %s)" % [str(ta.get_size() if ta else Vector2.ZERO), str(area)])
	bd.vorladen([[pb]])
	check(await _warte(func() -> bool: return Media.cached_url_fit(pb, area) != null), "Nachbar in derselben Größe vorgeladen")
	bd.show_item({ "id": "b", "_urls": [pb] })
	check(bd._front_gen == bd._gen and _vorn(bd).texture == Media.cached_url_fit(pb, area) and _vorn(bd).modulate.a == 1.0,
			"vorgeladen: Bild blendet sofort über, ohne Farbfeld dazwischen")
	await get_tree().create_timer(0.3).timeout
	bd.show_item({ "id": "c", "_urls": [pc] })
	var nur_b := true
	var ok := await _warte(func() -> bool:
		if bd._front_gen != bd._gen and _vorn(bd).texture != Media.cached_url_fit(pb, area):
			nur_b = false
		return bd._front_gen == bd._gen)
	check(ok and nur_b, "neues Bild noch nicht fertig: das letzte bleibt ruhig stehen")
	check(_vorn(bd).texture != null and _vorn(bd).texture == Media.cached_url_fit(pc, area) and _vorn(bd).modulate.a == 1.0,
			"übergeblendet wird erst mit dem fertigen Bild")
	bd.show_item({ "id": "d", "_urls": [Config.path("cache/gibt_es_nicht.png")] })
	check(await _warte(func() -> bool: return bd._front_gen == bd._gen), "kein Bild: das Farbfeld blendet über")
	check(_vorn(bd).texture == null, "… ohne Bild darauf")
	host.queue_free()
	for p in [pa, pb, pc]:
		DirAccess.remove_absolute(p)

extends Node
## Nahtlose Übergänge (Punkt 90): Feder, Ausschnitte (auch Zuschnitte als AtlasTexture), Flug hin
## und zurück mit Verstecken und Wiederzeigen, Rückfall ohne Karte, „Animationen reduzieren“ und
## Eingaben, während eine Ebene aufgeht. Aufruf: godot --headless --path . res://tests/logic_flug.tscn

const Flug := preload("res://src/ui/flug.gd")
const Leicht := preload("res://src/core/leicht.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Feder")
	check(Flug.feder(0.0) == 0.0 and Flug.feder(1.0) == 1.0 and Flug.feder(-1.0) == 0.0 and Flug.feder(2.0) == 1.0, "beginnt bei 0, endet genau bei 1")
	var top := 0.0
	var steigt := true
	var vorher := 0.0
	for i in 101:
		var v := Flug.feder(i / 100.0)
		top = maxf(top, v)
		if v < vorher - 1e-6:
			steigt = false
		vorher = v
	check(steigt, "steigt bis zum Ziel ohne Rückschritt")
	check(top <= 1.0 + 1e-6, "ohne Überschwingen (höchstens %.2f %%)" % ((top - 1.0) * 100.0))
	check(absf(Flug.feder(0.999) - 1.0) < 0.002, "am Ende fehlt weniger als 0,2 % (kein Sprung beim Landen)")
	var t30 := Flug.feder(0.3 / Flug.T_AUF)
	check(t30 > 0.9, "nach 0,3 s fast da (%.0f %%)" % (t30 * 100.0))
	check(Flug.feder(0.1 / Flug.T_AUF) < 0.55, "aber nicht schlagartig (nach 0,1 s %.0f %%)" % (Flug.feder(0.1 / Flug.T_AUF) * 100.0))

	print("Ausschnitte")
	var r := Flug.fuellen(Rect2(0, 0, 600, 900), 4.0 / 3.0)
	check(r.size.is_equal_approx(Vector2(600, 450)) and is_equal_approx(r.position.y, 225.0), "Hochkant in Querformat: mittiger Streifen")
	r = Flug.fuellen(Rect2(100, 0, 1600, 900), 3.0 / 4.0)
	check(is_equal_approx(r.size.x, 675.0) and is_equal_approx(r.position.x, 100.0 + (1600.0 - 675.0) * 0.5), "Querformat in Hochkant: mittig im Bereich")
	var a := Flug.ausschnitt(Rect2(0, 0, 600, 900), Vector2(580, 50), 400, 16.0 / 9.0)
	check(Rect2(0, 0, 600, 900).encloses(a) and is_equal_approx(a.size.x / a.size.y, 16.0 / 9.0), "Ausschnitt bleibt im Bild und unverzerrt (auch am Rand)")
	var e := Flug.einpassen(Vector2(616, 353), Rect2(0, 0, 300, 450))
	check(is_equal_approx(e.size.x, 300.0) and e.position.y > 100.0, "eingepasst: ganzes Bild mittig")
	var z := Flug.zwischen(Rect2(0, 0, 100, 100), Rect2(1000, 500, 300, 400), 1.0, 0.0, 0.5)
	check(is_equal_approx(z.get_center().x, 1150.0) and is_equal_approx(z.get_center().y, 50.0) and z.size.is_equal_approx(Vector2(200, 250)),
			"zwischen: Mitte je Achse eigen (Bogen), Größe gemischt")

	print("Zuschnitt (AtlasTexture)")
	var img := Image.create(600, 900, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.4, 0.5))
	var base := ImageTexture.create_from_image(img)
	var crop := AtlasTexture.new()
	crop.atlas = base
	crop.region = Rect2(0, 120, 600, 800)
	crop.set_meta("uz_crop", true)
	var g := Flug.grund(crop)
	check(g[0] == base and (g[1] as Rect2).is_equal_approx(Rect2(0, 120, 600, 800)), "Grundbild und Bereich eines Zuschnitts")
	var inner := AtlasTexture.new()
	inner.atlas = crop
	inner.region = Rect2(100, 100, 200, 200)
	var g2 := Flug.grund(inner)
	check(g2[0] == base and (g2[1] as Rect2).is_equal_approx(Rect2(100, 220, 200, 200)), "verschachtelte Ausschnitte addieren sich")
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var card := TextureRect.new()
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card.texture = crop
	card.position = Vector2(100, 600)
	card.size = Vector2(216, 288)
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("uz_flug", "g:test")
	host.add_child(card)
	await get_tree().process_frame
	var b := Flug.bild_von(card)
	check(not b.is_empty() and b.tex == base, "Bild einer Karte: das Grundbild, kein Neuladen")
	check((b.src as Rect2).is_equal_approx(Rect2(0, 120, 600, 800)) and (b.voll as Rect2).is_equal_approx(Rect2(0, 0, 600, 900)),
			"Ausschnitt wie auf der Karte, wandern darf er im ganzen Bild")
	check((b.rect as Rect2).is_equal_approx(Rect2(100, 600, 216, 288)), "Lage auf dem Schirm")
	card.visible = false
	check(Flug.bild_von(card).is_empty(), "unsichtbar: kein Bild")
	card.visible = true

	print("Flug hin und zurück")
	var layer := _seite("g:test")
	host.add_child(layer)
	await get_tree().process_frame
	var q := Flug._quelle_von(card)
	check(q.get("key") == "g:test" and not (q.bild as Dictionary).is_empty(), "Quelle: Schlüssel und Bild der gewählten Karte")
	var ziel: Control = layer.call("flug_ziel")
	check(Flug.auf(layer, q), "Karte und Seite gehören zusammen: es fliegt")
	var f := _flug(host)
	check(f != null and f.get_index() == layer.get_index() + 1, "Bild liegt über der Seite (landen)")
	check(Flug.verborgen(card) and Flug.verborgen(ziel), "Karte und Ziel verborgen, solange es fliegt")
	check(card.modulate.a == 1.0 and card.visible and ziel.modulate.a == 1.0, "dabei bleiben modulate und visible unberührt (Auswahl und Reihen laufen weiter)")
	await _bis_weg(host)
	check(not Flug.verborgen(card) and not Flug.verborgen(ziel), "gelandet: beide wieder da")
	check(_flug(host) == null, "Bild nach dem Landen weg")
	Flug.zu(layer)
	f = _flug(host)
	check(f != null and Flug.verborgen(ziel) and Flug.verborgen(card), "zurück: Bild der Seite fliegt, Karte wartet verborgen")
	await _bis_weg(host)
	check(not Flug.verborgen(card) and not Flug.verborgen(ziel), "zurück gelandet: alles wieder sichtbar")

	print("B mitten im Flug")
	var layer2 := _seite("g:test")
	host.add_child(layer2)
	await get_tree().process_frame
	Flug.auf(layer2, Flug._quelle_von(card))
	for i in 4:
		await get_tree().process_frame
	var f1 := _flug(host)
	var lage: Rect2 = (f1.get("_jetzt") as Dictionary).get("rect", Rect2())
	Flug.zu(layer2)
	var f2: Control = Flug._laufend.get("g:test")
	check(f2 != null and f2 != f1 and ((f2.get("_a") as Dictionary).rect as Rect2).is_equal_approx(lage), "Rückflug beginnt dort, wo das Bild gerade war")
	for i in 3:
		await get_tree().process_frame
	check(Flug.verborgen(card) and Flug.verborgen(layer2.call("flug_ziel")), "Karte bleibt verborgen, bis das Bild zurück ist")
	await _bis_weg(host)
	check(not Flug.verborgen(card) and not Flug.verborgen(layer2.call("flug_ziel")), "nichts bleibt verborgen")

	print("Rückfall und Grenzen")
	var layer3 := _seite("g:test")
	host.add_child(layer3)
	await get_tree().process_frame
	Flug.auf(layer3, Flug._quelle_von(card))
	await _bis_weg(host)
	card.set_meta("uz_flug", "g:anders")
	Flug.zu(layer3)
	await _bis_weg(host)
	check(not Flug.verborgen(layer3.call("flug_ziel")) and not Flug.verborgen(card), "Karte nicht mehr da: Bild blendet aus, nichts bleibt verborgen")
	card.set_meta("uz_flug", "g:test")
	var fremd := _seite("g:anderes")
	host.add_child(fremd)
	await get_tree().process_frame
	check(not Flug.auf(fremd, Flug._quelle_von(card)), "andere Seite (Schlüssel passt nicht): kein Flug")
	Config.set_value("theme.reduce_motion", true)
	var ruhig := _seite("g:test")
	host.add_child(ruhig)
	await get_tree().process_frame
	check(not Flug.auf(ruhig, Flug._quelle_von(card)) and _flug(host) == null, "Animationen reduzieren: kein Flug, nur Überblenden")
	Config.set_value("theme.reduce_motion", false)
	Leicht.active = true
	var t0 := Time.get_ticks_msec()
	Flug.auf(ruhig, Flug._quelle_von(card))
	await _bis_weg(host)
	var leicht_ms := Time.get_ticks_msec() - t0
	Leicht.active = false
	t0 = Time.get_ticks_msec()
	Flug.zu(ruhig)
	await _bis_weg(host)
	check(leicht_ms < (Flug.T_AUF + Flug.T_AUS) * 1000.0 * 0.9, "leichter Modus: kürzer (%d ms)" % leicht_ms)
	ziel = layer.call("flug_ziel")
	ziel.get_parent().remove_child(ziel)
	Flug.zu(layer)
	await _bis_weg(host)
	check(not Flug.verborgen(card) and _flug(host) == null, "Ziel der Seite weg (neu gebaut): kein Flug, nichts verborgen")
	ziel.free()

	print("Eingaben, während eine Ebene aufgeht")
	var seen: Array = []
	Nav.command.connect(func(c: String) -> void: seen.append(c))
	var neu := Control.new()
	host.add_child(neu)
	Nav.hold_for(neu)
	Nav._fire("a")
	Nav._fire("lb")
	Nav._fire("rb")
	check(seen.is_empty(), "solange die Ebene aufgeht: nichts geht an die Ansicht dahinter")
	Nav.release_hold(neu)
	await get_tree().process_frame
	check(seen == ["lb", "rb"], "danach der Reihe nach ausgeführt, das zweite A verworfen (%s)" % str(seen))
	seen.clear()
	Nav.hold_for(neu)
	Nav._fire("lb")
	Nav._opening_ms -= Nav.HOLD_MS + 10
	Nav._fire("rb")
	await get_tree().process_frame
	check(seen == ["lb", "rb"], "Ebene hängt: spätestens nach %d ms geht alles weiter, in Reihenfolge (%s)" % [Nav.HOLD_MS, str(seen)])
	seen.clear()
	Nav.hold_for(neu)
	Nav._fire("lb")
	neu.queue_free()
	await get_tree().process_frame
	Nav._fire("rb")
	await get_tree().process_frame
	check(seen == ["lb", "rb"], "Ebene vorher entfernt: nichts bleibt hängen (%s)" % str(seen))

	host.queue_free()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Eine Seite mit Ziel (wie die Spielseite: Hülle im Kopf).
func _seite(key: String) -> Control:
	var s := GDScript.new()
	s.source_code = "extends Control\nvar ziel: TextureRect\nfunc flug_ziel() -> Control:\n\treturn ziel\n"
	s.reload()
	var l := Control.new()
	l.set_script(s)
	l.size = Vector2(1920, 1080)
	l.set_meta("uz_flug", key)
	var z := TextureRect.new()
	z.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	z.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var img := Image.create(600, 900, false, Image.FORMAT_RGB8)
	z.texture = ImageTexture.create_from_image(img)
	z.position = Vector2(1500, 300)
	z.size = Vector2(270, 360)
	l.add_child(z)
	l.set("ziel", z)
	return l


func _flug(host: Control) -> Control:
	for c in host.get_children():
		if c.get_script() == Flug and not c.is_queued_for_deletion():
			return c
	return null


func _bis_weg(host: Control) -> void:
	var t := Time.get_ticks_msec()
	while _flug(host) != null and Time.get_ticks_msec() - t < 4000:
		await get_tree().process_frame
	await get_tree().process_frame

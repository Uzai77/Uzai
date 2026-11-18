extends Node
## Takt (docs/PLAN_GEFUEHL.md, Paket A): Zeiten, die drei Kurven im ersten Bild, „Animationen
## reduzieren“ (U.reduziert), Staffel höchstens vier Glieder, Ortswechsel mit U.abgang/U.ankunft
## ohne leeres Bild, Cursor-Antwort im ersten Bild und Ebenen „Fläche vor Schrift“ mit Schließen
## ohne Ruck am Ende. Aufruf: godot --headless --path . res://tests/logic_takt.tscn

const U := preload("res://src/ui/u.gd")
const Modal := preload("res://src/ui/layers/modal.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Config.set_value("theme.reduce_motion", false)
	print("Zeiten")
	check(is_equal_approx(U.T_ANTWORT, 0.09) and is_equal_approx(U.T_WEG, 0.16) and is_equal_approx(U.T_ORT, 0.2)
			and is_equal_approx(U.T_RAUM, 0.36) and is_equal_approx(U.T_LICHT, 0.8), "fünf Zeiten 90 / 160 / 200 / 360 / 800 ms")
	check(is_equal_approx(U.T_FAST, 0.12) and is_equal_approx(U.T_MOVE, 0.3), "alte Namen bleiben mit ihren Werten")

	print("Kurven")
	var bild := 1.0 / 60.0
	var an := U.kurve("ankommen", bild / U.T_ORT)
	check(an > 0.2 and an < 0.3, "Ankommen ist im ersten Bild schon gut ein Fünftel da (%.0f %%)" % (an * 100.0))
	var raum := U.kurve("raum", bild / U.T_RAUM)
	check(raum > 0.15 and raum < 0.3, "Raumwechsel (quart) im ersten Bild %.0f %%" % (raum * 100.0))
	var geh := U.kurve("gehen", bild / U.T_WEG)
	check(geh > 0.15, "Gehen beginnt sofort (%.0f %% im ersten Bild)" % (geh * 100.0))
	for art in ["ankommen", "raum", "gehen"]:
		var vor := 0.0
		var ok := true
		var erster := -1.0
		var letzter := 0.0
		for i in range(1, 61):
			var v := U.kurve(art, i / 60.0)
			if v < vor - 1e-6 or v > 1.0 + 1e-6:
				ok = false
			if erster < 0.0:
				erster = v - vor
			letzter = v - vor
			vor = v
		check(ok, "%s steigt ohne Überschwingen bis 1" % art)
		check(letzter < erster * 0.4, "%s endet weich: letzter Schritt %.3f, erster %.3f" % [art, letzter, erster])
	check(U.trans_ankommen(U.T_ORT) == Tween.TRANS_CUBIC and U.trans_ankommen(U.T_RAUM) == Tween.TRANS_QUART, "Ankommen: cubic bis T_ORT, quart ab T_RAUM")

	print("Staffel")
	var top := 0.0
	for i in 12:
		top = maxf(top, U.staffel(i))
	check(is_equal_approx(top, (U.STAFFEL_MAX - 1) * U.STAFFEL) and U.STAFFEL_MAX == 4, "höchstens 4 Glieder × 30 ms (letztes bei %d ms)" % roundi(top * 1000.0))

	print("Ruhig")
	check(not U.reduziert() and U.weg_px(24.0) == 24.0 and is_equal_approx(U.wachsen(0.96), 0.96), "normal: Wege und Wachsen")
	Config.set_value("theme.reduce_motion", true)
	check(U.reduziert(), "U.reduziert() liest „Animationen reduzieren“")
	check(U.weg_px(U.W_BEREICH) == 0.0 and U.wachsen(0.96) == 1.0 and U.staffel(3) == 0.0, "ruhig: 0 px Weg, kein Wachsen, keine Staffel")
	check(U.tempo() >= U.RUHIG_TEMPO - 0.001, "ruhig: Dauern kürzer (Tempo %.1f)" % U.tempo())
	Config.set_value("theme.reduce_motion", false)

	await _cursor()
	await _kaskade()
	await _ortswechsel(false)
	await _ortswechsel(true)
	await _im_container()
	await _ebene()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _cursor() -> void:
	print("Cursor")
	var c := Control.new()
	c.size = Vector2(300, 60)
	add_child(c)
	U.focus_anim(c, true)
	check(float(c.get_meta("uz_f", 0.0)) >= 0.7, "neuer Cursor steht sofort zu 70 %% da (%.2f)" % float(c.get_meta("uz_f", 0.0)))
	await _warte(U.T_ANTWORT + 0.05)
	check(is_equal_approx(float(c.get_meta("uz_f", 0.0)), 1.0), "… und sitzt nach T_ANTWORT")
	U.focus_anim(c, false)
	check(float(c.get_meta("uz_f", 1.0)) <= 0.3, "alter Cursor fällt sofort auf 30 %")
	c.queue_free()


func _kaskade() -> void:
	print("Kaskade")
	var root := Control.new()
	root.size = Vector2(800, 900)
	add_child(root)
	var list := VBoxContainer.new()
	list.size = Vector2(800, 900)
	root.add_child(list)
	for i in 8:
		var r := Control.new()
		r.custom_minimum_size = Vector2(800, 60)
		list.add_child(r)
	await get_tree().process_frame
	U.cascade(root, 9)
	await _warte(0.16)
	var a: Array = list.get_children().map(func(n: Control) -> float: return n.modulate.a)
	check(float(a[0]) > float(a[3]) and absf(float(a[7]) - float(a[3])) < 0.02,
			"gestaffelt, ab dem vierten Glied kommt der Rest mit (%.2f / %.2f / %.2f)" % [a[0], a[3], a[7]])
	await _warte(U.T_ORT + U.STAFFEL * 4 + 0.1)
	check(list.get_children().all(func(n: Control) -> bool: return is_equal_approx(n.modulate.a, 1.0) and n.scale == Vector2.ONE),
			"alle Reihen da, nichts skaliert")
	root.queue_free()


## Ein Ortswechsel: der alte Inhalt geht in einer Hülle, der neue kommt – nie ein leeres Bild.
func _ortswechsel(ruhig: bool) -> void:
	print("Ortswechsel%s" % (" (ruhig)" if ruhig else ""))
	Config.set_value("theme.reduce_motion", ruhig)
	var buehne := Control.new()
	buehne.size = Vector2(1920, 1080)
	add_child(buehne)
	var host := Control.new()
	host.position = Vector2(200, 300)
	host.size = Vector2(900, 400)
	buehne.add_child(host)
	var alt := Label.new()
	alt.text = "Alt"
	alt.position = Vector2(20, 30)
	host.add_child(alt)
	await get_tree().process_frame
	var g0 := alt.get_global_rect()
	var h := U.abgang(host, 1)
	check(h != null and host.get_child_count() == 0 and alt.get_parent() == h, "alter Inhalt liegt in der Hülle, der Platz ist frei")
	check(h != null and h.get_parent() == buehne and h.has_meta("uz_skip"), "Hülle liegt außerhalb des Layouts und ist nicht wählbar")
	check(alt.get_global_rect().position.distance_to(g0.position) < 0.5, "alter Inhalt bleibt, wo er war")
	var neu := Label.new()
	neu.text = "Neu"
	host.add_child(neu)
	U.ankunft(host, 1)
	var deckung := 1.0
	var alt_weg_ms := -1
	var max_dx := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 450:
		await get_tree().process_frame
		var ha := h.modulate.a if is_instance_valid(h) else 0.0
		# Übereinander decken zwei Deckkräfte a_neu + a_alt · (1 − a_neu), nicht ihre Summe.
		deckung = minf(deckung, host.modulate.a + ha * (1.0 - host.modulate.a))
		if alt_weg_ms < 0 and ha <= 0.001:
			alt_weg_ms = Time.get_ticks_msec() - t0
		if is_instance_valid(h):
			max_dx = maxf(max_dx, absf(h.position.x - 200.0))
	check(deckung >= 0.85, "nie ein leeres Bild (Alt und Neu decken übereinander mindestens %.0f %%)" % (deckung * 100.0))
	check(alt_weg_ms >= 0 and alt_weg_ms <= int((U.NACH_WEG + U.T_WEG) / U.tempo() * 1000.0) + 60,
			"Doppelbelichtung nur kurz: das Alte ist nach %d ms weg" % alt_weg_ms)
	check(not is_instance_valid(h) or h.is_queued_for_deletion(), "Hülle danach frei")
	check(is_equal_approx(host.modulate.a, 1.0) and absf(host.position.x - 200.0) < 0.01 and is_equal_approx(host.size.x, 900.0),
			"neuer Inhalt steht an seinem Platz")
	# Zweimal schnell hintereinander (LB, LB): die Ruhelage wandert nicht.
	U.abgang(host, -1)
	U.ankunft(host, -1)
	await get_tree().process_frame
	await get_tree().process_frame
	U.abgang(host, -1)
	U.ankunft(host, -1)
	await _warte(0.45)
	check(absf(host.position.x - 200.0) < 0.01, "unterbrochen: der Inhalt kommt an derselben Stelle an (%.1f)" % host.position.x)
	if ruhig:
		check(max_dx < 0.5, "ruhig: die Hülle gleitet nicht (%.1f px)" % max_dx)
	else:
		check(max_dx > 10.0 and max_dx <= U.W_ORT + 0.5, "die Hülle gleitet W_ORT zur Gegenseite (%.1f px)" % max_dx)
	buehne.queue_free()
	Config.set_value("theme.reduce_motion", false)


func _im_container() -> void:
	print("Ortswechsel im Container")
	var buehne := Control.new()
	buehne.size = Vector2(1920, 1080)
	add_child(buehne)
	var m := MarginContainer.new()
	m.position = Vector2(100, 100)
	m.size = Vector2(800, 200)
	m.add_theme_constant_override("margin_left", 40)
	buehne.add_child(m)
	var host := HBoxContainer.new()
	m.add_child(host)
	for i in 3:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(100, 100)
		host.add_child(c)
	await get_tree().process_frame
	var x0 := (host.get_child(1) as Control).get_global_rect().position.x
	var h := U.abgang(host, -1)
	check(h != null and h.get_parent() == buehne, "Hülle beim nächsten Vorfahren ohne Layout")
	var c1 := h.get_child(1) as Control if h else null
	check(c1 != null and absf(c1.get_global_rect().position.x - x0) < 0.5, "Kinder behalten ihre Lage auf dem Schirm")
	U.ankunft(host, -1)
	await _warte(0.5)
	check(not is_instance_valid(h) or h.is_queued_for_deletion(), "Hülle frei")
	buehne.queue_free()


## Fläche vor Schrift: der Dialog kommt deckend, seine Schrift danach; Schließen läuft aus.
func _ebene() -> void:
	print("Ebene")
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var d = Modal.new()
	d.set_meta("uz_silent", true)
	d.open(host)
	check(d.flaeche() == d.panel, "der Dialog nennt seine Fläche")
	await get_tree().process_frame
	var schrift: CanvasItem = d.panel.get_child(0)
	check(is_equal_approx(d.modulate.a, 1.0) and is_equal_approx(d.panel.modulate.a, 1.0), "Fläche steht im ersten Bild deckend da")
	check(schrift.modulate.a < 0.2, "Schrift kommt danach (%.2f)" % schrift.modulate.a)
	var scrim: ColorRect = d.get("_scrim")
	check(scrim.color.a < d.dim, "Abdunklung blendet ein")
	await _warte(U.T_RAUM + 0.15)
	check(is_equal_approx(schrift.modulate.a, 1.0) and is_equal_approx(scrim.color.a, d.dim) and d.panel.scale.is_equal_approx(Vector2.ONE),
			"nach T_RAUM steht alles")
	d.close()
	var werte: Array = [1.0]
	for i in 30:
		await get_tree().process_frame
		if not is_instance_valid(d):
			break
		werte.append(d.modulate.a)
	var schritte: Array = []
	for i in range(1, werte.size()):
		var s := float(werte[i - 1]) - float(werte[i])
		if s > 0.001:
			schritte.append(s)
	check(schritte.size() >= 3, "Schließen läuft über mehrere Bilder (%d)" % schritte.size())
	if schritte.size() >= 3:
		check(float(schritte.back()) < float(schritte[0]) * 0.6, "kein Ruck am Ende: letzter Schritt %.3f, erster %.3f" % [schritte.back(), schritte[0]])
	host.queue_free()


func _warte(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await get_tree().process_frame

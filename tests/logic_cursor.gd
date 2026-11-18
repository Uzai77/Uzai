extends Node
## Cursor und Halten (docs/PLAN_GEFUEHL.md, Paket B): der gleitende Rahmen in Listen (auch über
## Abschnittslinien, nicht von außen, nicht bei „Animationen reduzieren“), Antwort im ersten Bild,
## der Halte-Takt (400 / 162 / 120 / 96 ms ohne Drift), der Rand stößt genau einmal an (6 px),
## das Regal fährt beim Halten gleichmäßig (Simulation, Schwankung < 1,4 : 1), Cover wachsen ohne
## Überschwingen und lassen kein Ersatz-Cover unter dem Bild.
## Aufruf: godot --headless --path . res://tests/logic_cursor.tscn → „Ergebnis: alles ok“

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")
const CoverRow := preload("res://src/ui/components/cover_row.gd")
const CoverCard := preload("res://src/ui/components/cover_card.gd")
const NavS := preload("res://src/core/nav.gd")

const DT := 1.0 / 60.0

var fails := 0
var ui: Control


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	# Bilder im Takt eines Fernsehers (headless liefe es sonst so schnell es geht).
	Engine.max_fps = 60
	Config.set_value("theme.reduce_motion", false)
	ui = Control.new()
	ui.size = Vector2(1280, 720)
	add_child(ui)
	Nav.root_scope = ui
	await _gleiter()
	await _halte_takt()
	await _rand()
	_regal_tempo()
	await _cover()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _warte(sek: float) -> void:
	await get_tree().create_timer(sek).timeout


# --- Gleitender Rahmen ------------------------------------------------------------------------

func _gleiter() -> void:
	print("Gleitender Rahmen")
	var sc := ScrollContainer.new()
	sc.position = Vector2(100, 40)
	sc.size = Vector2(600, 640)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(sc)
	var box := U.vbox(0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	var rows: Array = []
	for i in 6:
		if i == 3:
			box.add_child(Liste.linie(14))
		var r: Control = GuideRow.new().setup("Zeile %d" % i, "info")
		box.add_child(r)
		rows.append(r)
	var knopf := Button.new()
	knopf.text = "außen"
	knopf.position = Vector2(800, 40)
	knopf.size = Vector2(200, 50)
	ui.add_child(knopf)
	await _frames(3)
	Nav.focus(rows[0], true)
	await _warte(0.4)
	check(float(rows[0].get("_f")) >= 0.99, "erste Zeile trägt den Rahmen")

	# Eine Zeile weiter: der Rahmen gleitet, die alte Zeile schweigt.
	Nav.focus(rows[1], true)
	check(float(rows[0].get("_f")) <= Liste.ANTWORT_REST + 0.001, "alte Zeile fällt sofort auf 30 %% (%.2f)" % float(rows[0].get("_f")))
	check(float(rows[1].get("_f")) >= Liste.ANTWORT_VON - 0.001, "neue Zeile steht sofort zu 70 %% da (%.2f)" % float(rows[1].get("_f")))
	await _frames(2)
	check(Liste.gleitet_zu() == rows[1], "der Rahmen gleitet zur neuen Zeile")
	var y0: float = (rows[0] as Control).global_position.y
	var y1: float = (rows[1] as Control).global_position.y
	var lage := Liste.gleiter_lage()
	check(lage.position.y > y0 + 0.5 and lage.position.y < y1, "nach zwei Bildern liegt er dazwischen (%.1f zwischen %.1f und %.1f)" % [lage.position.y, y0, y1])
	var t0 := Time.get_ticks_usec()
	var ende := -1.0
	while Time.get_ticks_usec() - t0 < 1000000:
		await get_tree().process_frame
		if Liste.gleitet_zu() == null:
			ende = (Time.get_ticks_usec() - t0) / 1000.0 + 2.0 * DT * 1000.0
			break
	check(ende > 0.0 and ende <= 450.0, "im Lauf angekommen nach %d ms" % roundi(ende))
	# Das Gleiten selbst (60 Bilder je Sekunde, in ganzen Pixeln gezeichnet): eine Zeile (50 px)
	# weit ist es nach 130 ms zu 90 % da und nach höchstens 300 ms am Ziel; jedes Bild bewegt sich,
	# bis es steht (keine Treppe), und der letzte Schritt ist klein.
	var x := 50.0
	var v := 0.0
	var n90 := -1
	var n_da := -1
	var px_alt := 50
	var schritte: Array = []
	for i in 60:
		var st: Vector2 = Liste._Wache.schritt(x, v, 0.0, DT)
		x = st.x
		v = st.y
		var px := roundi(x)
		schritte.append(absi(px - px_alt))
		px_alt = px
		if n90 < 0 and absf(x) <= 5.0:
			n90 = i + 1
		if absf(x) <= 0.01:
			n_da = i + 1
			break
	var ohne_pause := not schritte.has(0)
	var groesst: int = schritte.max()
	check(n_da > 0 and n_da * DT <= 0.3 and n90 * DT <= 0.135, "Gleiten: 90 %% nach %d ms, am Ziel nach %d ms (≤ 300)" % [roundi(n90 * DT * 1000.0), roundi(n_da * DT * 1000.0)])
	check(ohne_pause and int(schritte.back()) <= 0.4 * groesst, "ohne Stillstand, letzter Schritt %d px von größtem %d px (≤ 40 %%): %s" % [int(schritte.back()), groesst, str(schritte)])
	check(float(rows[1].get("_f")) >= 0.99, "danach trägt die neue Zeile den Rahmen selbst")

	# Über die Abschnittslinie.
	Nav.focus(rows[2], true)
	await _warte(0.4)
	Nav.focus(rows[3], true)
	await _frames(2)
	check(Liste.gleitet_zu() == rows[3], "gleitet auch über die Abschnittslinie")
	await _warte(0.4)
	# Weiter Sprung (vier Zeilen und eine Linie): steht gleich am Ziel.
	Nav.focus(rows[0], true)
	await _frames(2)
	check(Liste.gleitet_zu() == null and float(rows[0].get("_f")) >= Liste.ANTWORT_VON - 0.001, "weiter Sprung: kein Flug quer über die Liste, Antwort im ersten Bild")
	await _warte(0.3)

	# Von außen: kein Gleiten, Antwort im ersten Bild.
	Nav.focus(knopf, true)
	await _warte(0.2)
	check(float(rows[3].get("_f")) < 0.01, "Fokus geht nach außen: der Rahmen geht")
	Nav.focus(rows[5], true)
	check(float(rows[5].get("_f")) >= Liste.ANTWORT_VON - 0.001, "von außen: steht sofort zu 70 % da")
	await _frames(2)
	check(Liste.gleitet_zu() == null, "von außen gleitet nichts")
	await _warte(U.T_ANTWORT + 0.05)
	check(float(rows[5].get("_f")) >= 0.99, "und setzt sich in T_ANTWORT")

	# „Animationen reduzieren“: kein Gleiten.
	Config.set_value("theme.reduce_motion", true)
	Nav.focus(rows[4], true)
	await _frames(2)
	check(Liste.gleitet_zu() == null, "„Animationen reduzieren“: kein Gleiten")
	Config.set_value("theme.reduce_motion", false)
	await _warte(0.3)

	# Einstellungs-Zeilen (Stand in der Meta uz_f) machen genauso mit.
	var b2 := U.vbox(0)
	b2.position = Vector2(100, 400)
	b2.size = Vector2(600, 200)
	ui.add_child(b2)
	var s0: Control = SettingRow.new().setup("action", "Eins")
	var s1: Control = SettingRow.new().setup("action", "Zwei")
	b2.add_child(s0)
	b2.add_child(s1)
	await _frames(3)
	Nav.focus(s0, true)
	await _warte(0.4)
	Nav.focus(s1, true)
	check(float(s1.get_meta("uz_f", 0.0)) >= Liste.ANTWORT_VON - 0.001, "Einstellungs-Zeile: Antwort im ersten Bild")
	await _frames(2)
	check(not UzTheme.cursor_frame() or Liste.gleitet_zu() == s1, "Einstellungs-Zeilen: der Rahmen gleitet")
	await _warte(0.4)
	sc.queue_free()
	knopf.queue_free()
	b2.queue_free()
	await _frames(2)


# --- Halte-Takt -------------------------------------------------------------------------------

func _halte_takt() -> void:
	print("Halte-Takt")
	var box := U.vbox(0)
	box.position = Vector2(20, 20)
	ui.add_child(box)
	var btns: Array = []
	for i in 30:
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(200, 18)
		b.focus_mode = Control.FOCUS_ALL
		box.add_child(b)
		btns.append(b)
	await _frames(3)
	Nav.focus(btns[0], true)
	await _frames(2)
	var zeiten: Array = []
	var cb := func(_c: Control) -> void: zeiten.append(Nav._uhr)
	Nav.focus_moved.connect(cb)
	Nav.set_process(false)
	Input.action_press("uz_down")
	var ev := InputEventAction.new()
	ev.action = "uz_down"
	ev.pressed = true
	var t0: float = Nav._uhr
	Nav._input(ev)
	var takte: Array = []
	for i in 130:
		Nav._process(DT)
		takte.append(Nav.halten_takt())
	Input.action_release("uz_down")
	Nav._process(DT)
	Nav.set_process(true)
	Nav.focus_moved.disconnect(cb)
	# Plan: 0, 400, dann 3 × 162, 7 × 120, danach 96 ms.
	var plan := [0.0]
	var t := 400.0
	var k := 0
	while t < 130 * DT * 1000.0:
		plan.append(t)
		t += Nav.repeat_ms(k)
		k += 1
	var ok := zeiten.size() == plan.size()
	var drift := 0.0
	for i in mini(zeiten.size(), plan.size()):
		var d: float = float(zeiten[i]) - t0 - float(plan[i])
		drift = maxf(drift, d)
		if d < -0.01 or d >= DT * 1000.0 + 0.01:
			ok = false
	check(ok, "%d Schritte, jeder im Bild seines Plans (größte Abweichung %.1f ms < ein Bild), ohne Drift" % [zeiten.size(), drift])
	var gaps: Array = []
	for i in range(1, zeiten.size()):
		gaps.append(roundi(float(zeiten[i]) - float(zeiten[i - 1])))
	print("     Abstände: ", gaps)
	var mittel := (float(zeiten[zeiten.size() - 1]) - float(zeiten[4])) / maxf(1.0, zeiten.size() - 5.0) if zeiten.size() > 8 else 0.0
	check(Nav.repeat_ms(0) == 162 and Nav.repeat_ms(3) == 120 and Nav.repeat_ms(10) == 96, "Abstände 162 / 120 / 96 ms")
	check(absf(float(zeiten[1]) - t0 - 400.0) < DT * 1000.0, "erster Wiederholschritt nach 400 ms")
	check(mittel > 0.0 and mittel < 120.0, "im Mittel so schnell wie geplant (%.1f ms)" % mittel)
	check(float(takte[0]) == 0.0 and float(takte[takte.size() - 1]) > 0.0, "halten_takt(): 0 vor der ersten Wiederholung, danach der Abstand")
	check(Nav.halten_takt() == 0.0, "halten_takt(): nach dem Loslassen 0")
	check(NavS.naechster_schritt(1000.0, 1500.0, 120) == 1620.0, "nach einem langen Hänger kein Nachholen")
	box.queue_free()
	await _frames(2)


# --- Rand -------------------------------------------------------------------------------------

func _rand() -> void:
	print("Rand")
	var box := U.vbox(0)
	box.position = Vector2(20, 20)
	ui.add_child(box)
	var btns: Array = []
	for i in 3:
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(200, 30)
		box.add_child(b)
		btns.append(b)
	await _frames(3)
	Nav.focus(btns[2], true)
	await _frames(2)
	var stoesse := [0]
	var cb := func(_c: Control, _d: String) -> void: stoesse[0] += 1
	Nav.rand.connect(cb)
	var ev := InputEventAction.new()
	ev.action = "uz_down"
	ev.pressed = true
	Input.action_press("uz_down")
	Nav._input(ev)
	var base: Vector2 = btns[2].get_meta("uz_bump_base", btns[2].position)
	var weit := 0.0
	var tb := Time.get_ticks_usec()
	while Time.get_ticks_usec() - tb < 250000:
		await get_tree().process_frame
		weit = maxf(weit, (btns[2].position - base).length())
	check(weit > 2.0 and weit <= U.W_ANSTOSS + 0.01, "Anstoß höchstens 6 px (%.1f)" % weit)
	# Weiterhalten: 1,5 s lang bleibt es still.
	Nav.set_process(false)
	for i in 90:
		Nav._process(DT)
	Nav.set_process(true)
	check(stoesse[0] == 1, "gehalten stößt der Rand genau einmal an (%d)" % stoesse[0])
	Input.action_release("uz_down")
	Nav._process(DT)
	await _frames(2)
	Input.action_press("uz_down")
	Nav._input(ev)
	Input.action_release("uz_down")
	check(stoesse[0] == 2, "neuer Druck: wieder genau ein Anstoß")
	Config.set_value("theme.reduce_motion", true)
	await _warte(0.3)
	var p0: Vector2 = btns[2].position
	Input.action_press("uz_down")
	Nav._input(ev)
	Input.action_release("uz_down")
	await _frames(3)
	check(btns[2].position == p0 and stoesse[0] == 3, "„Animationen reduzieren“: Anstoß ohne Weg, Klang bleibt")
	Config.set_value("theme.reduce_motion", false)
	Nav.rand.disconnect(cb)
	box.queue_free()
	await _frames(2)


# --- Regal beim Halten (Simulation im Takt von Nav) -------------------------------------------

func _regal_tempo() -> void:
	print("Regal beim Halten")
	var schritt := 250.0
	var neu := _regal_sim(schritt, false)
	var alt := _regal_sim(schritt, true)
	check(neu < 1.4, "Tempo schwankt %.2f : 1 (Ziel < 1,4; vorher exponentielles Folgen %.2f : 1)" % [neu, alt])
	check(alt > 3.0, "Gegenprobe: das alte Folgen ruckte (%.2f : 1)" % alt)


## Schwankung des Tempos (größtes / kleinstes je Bild) im Abschnitt mit 120-ms-Takt.
func _regal_sim(schritt: float, alt: bool) -> float:
	var off := 0.0
	var vel := 0.0
	var ziel := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var zt := 0.0
	var zd := 0.0
	var naechst := 400.0
	var steps := 0
	var fires: Array = [0.0]
	var t := 0.0
	var offs: Array = []
	var times: Array = []
	ziel = schritt
	z1 = schritt
	while t < 2000.0:
		t += DT * 1000.0
		if t >= naechst:
			fires.append(t)
			var ab := Nav.repeat_ms(steps)
			naechst = NavS.naechster_schritt(naechst, t, ab)
			steps += 1
			ziel += schritt
			z0 = CoverRow.ziel_jetzt(z0, z1, zt, zd)
			z1 = ziel
			zt = 0.0
			zd = ab / 1000.0
		if alt:
			off = lerpf(off, ziel, 1.0 - exp(-DT * 12.0))
		else:
			zt += DT
			var st := CoverRow.folgen(off, vel, CoverRow.ziel_jetzt(z0, z1, zt, zd), DT, zd > 0.0)
			off = st.x
			vel = st.y
		offs.append(off)
		times.append(t)
	var lo := INF
	var hi := 0.0
	for i in range(1, offs.size()):
		if float(times[i]) >= float(fires[6]) and float(times[i]) < float(fires[10]):
			var v := float(offs[i]) - float(offs[i - 1])
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return hi / maxf(lo, 0.001)


# --- Cover ------------------------------------------------------------------------------------

func _cover() -> void:
	print("Cover")
	var card: Control = CoverCard.new().setup({ "id": "probe:1", "title": "Probe", "source": "pc" }, false, Vector2(200, 260))
	card.position = Vector2(300, 200)
	ui.add_child(card)
	await _frames(3)
	var s_max := 0.0
	var ziel: float = card.call("_gross", true)
	card.grab_focus()
	var ring_erst := float(card.get("_focus_t"))
	var tc := Time.get_ticks_usec()
	while Time.get_ticks_usec() - tc < 400000:
		await get_tree().process_frame
		s_max = maxf(s_max, card.scale.x)
	check(ring_erst >= Liste.ANTWORT_VON - 0.001, "Ring steht im ersten Bild zu 70 %% da (%.2f)" % ring_erst)
	check(s_max <= ziel + 0.0005 and absf(card.scale.x - ziel) < 0.002, "wächst ohne Überschwingen (größte %.4f, Ziel %.4f)" % [s_max, ziel])
	var img := Image.create(20, 26, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.4, 0.5))
	card.call("_on_texture", ImageTexture.create_from_image(img), int(card.get("_img_gen")))
	await _warte(U.T_ORT + 0.1)
	var art: Control = card.get("_art")
	check(art != null and not art.visible, "Bild deckt: kein Ersatz-Cover darunter (keine Geister-Titel)")
	card.call("unload_image")
	check(art.visible, "Bild entladen: Ersatz-Cover wieder da")
	card.queue_free()
	await _frames(2)

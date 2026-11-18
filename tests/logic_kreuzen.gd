extends Node
## Fugen (docs/PLAN_GEFUEHL2.md, Paket E1): Kurve „Kreuzen“ – Alt und Neu decken übereinander in
## jedem Bild mindestens 85 % (a_neu + a_alt · (1 − a_neu), nicht die Summe), für jedes Kurvenpaar
## der Oberfläche; Pixel-Schluss (U.px_schluss) – Wege in ganzen Pixeln, je Bild mindestens 1 px
## näher, nie zurück, enden bei 0, auch rückwärts und unterbrochen; dazu U.slide_x und die Tiefe
## hinter Ebenen im echten Tween, „Der große Titel weicht zuerst“ und U.abheben.
## Aufruf: godot --headless --path . res://tests/logic_kreuzen.tscn

const U := preload("res://src/ui/u.gd")
const Layer := preload("res://src/ui/layers/layer.gd")
const Raster := preload("res://src/core/raster.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const BILD := 1.0 / 60.0
const DECKUNG := 0.85

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Config.set_value("theme.reduce_motion", false)
	_kurven()
	_pixel()
	await _raster()
	await _slide()
	await _tiefe()
	await _titel()
	await _abheben()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Deckkraft des Alten mit „Kreuzen“ nach t Sekunden (hält NACH_WEG, dann sine in-out in T_WEG).
static func alt_kreuzen(t: float) -> float:
	return 1.0 - U.kurve("kreuzen", (t - U.NACH_WEG) / U.T_WEG)


static func alt_gehen(t: float) -> float:
	return 1.0 - U.kurve("gehen", t / U.T_WEG)


## Neues mit „Ankommen“ (dauer, Kurve art), das lag Bilder nach dem Alten beginnt.
static func neu(t: float, art: String, dauer: float, lag: int) -> float:
	return U.kurve(art, (t - lag * BILD) / dauer)


## Kleinste Deckung über alle Bilder bis 0,6 s.
static func tiefste(alt: Callable, neu_c: Callable) -> float:
	var m := 1.0
	for i in 37:
		var t := i * BILD
		var an: float = neu_c.call(t)
		var aa: float = alt.call(t)
		m = minf(m, an + aa * (1.0 - an))
	return m


func _kurven() -> void:
	print("Kreuzen")
	check(is_equal_approx(alt_kreuzen(BILD), 1.0), "das Alte hält das erste Bild ganz (das Neue beginnt darin)")
	var vor := 1.0
	var ok := true
	var erster := -1.0
	var letzter := 0.0
	for i in range(1, 16):
		var v := alt_kreuzen(i * BILD)
		if v > vor + 1e-6:
			ok = false
		if vor - v > 1e-6:
			if erster < 0.0:
				erster = vor - v
			letzter = vor - v
		vor = v
	check(ok and is_zero_approx(alt_kreuzen(U.NACH_WEG + U.T_WEG)), "fällt ohne Umkehr auf 0 in NACH_WEG + T_WEG")
	check(letzter < 0.4 * maxf(erster, 0.05) or letzter < 0.05, "endet weich (sine in-out: Tempo 0 am Ende, letzter Schritt %.3f)" % letzter)
	# Paare der Oberfläche: Bereich (neu: Ankommen T_ORT), Unterbereich/App (ankunft T_ORT),
	# Bibliothek auf (Raster T_ORT nach NACH_WEG), Bibliothek zu (Startseite T_WEG sofort).
	var paare := [
		["Bereich, Unterbereich, App", "ankommen", U.T_ORT],
		["Bibliothek zu (Startseite kommt in T_WEG)", "ankommen", U.T_WEG],
		["Seite (Grund in T_WEG)", "ankommen", U.T_WEG],
	]
	for p in paare:
		for lag in [0, 1]:
			var d := tiefste(alt_kreuzen, func(t: float) -> float: return neu(t, str(p[1]), float(p[2]), lag))
			check(d >= DECKUNG, "%s, Neues %d Bild(er) später: Deckung nie unter %.0f %% (%.1f %%)" % [p[0], lag, DECKUNG * 100.0, d * 100.0])
	# Die Begründung: mit „Gehen“ statt „Kreuzen“ fiel die Deckung darunter (gemessen 0,69–0,72).
	var alt_weg := tiefste(alt_gehen, func(t: float) -> float: return neu(t, "ankommen", U.T_ORT, 1))
	check(alt_weg < DECKUNG, "zum Vergleich „Gehen“: Deckung %.0f %% (das Loch, das Kreuzen schließt)" % (alt_weg * 100.0))


## Pixel-Schluss an einer Kurve von von px nach 0 über n Bilder, unterbrochen ab Bild cut neu ab
## dem Stand dort. Liefert die Werte je Bild.
static func px_reihe(von: float, art: String, n: int, cut := -1) -> Array:
	var o := Object.new()
	o.set_meta("k", roundf(von))
	var out: Array = []
	var start := von
	var t0 := 0
	for i in range(1, n + 1):
		if i == cut:
			start = float(out.back())
			o.set_meta("k", roundf(start))
			t0 = i - 1
		var v := start * (1.0 - U.kurve(art, float(i - t0) / float(n - t0)))
		out.append(U.px_schluss(o, "k", v))
	o.free()
	return out


static func px_ok(werte: Array, von: float) -> String:
	var vor := roundf(von)
	for v in werte:
		var f := float(v)
		if f != roundf(f):
			return "kein ganzes Pixel (%.2f)" % f
		if absf(f) > absf(vor) or (f != 0.0 and signf(f) != signf(vor)):
			return "zurück oder über 0 (%.0f nach %.0f)" % [f, vor]
		if vor != 0.0 and f == vor:
			return "Stillstand bei %.0f px" % f
		vor = f
	if float(werte.back()) != 0.0:
		return "endet nicht bei 0 (%.0f)" % float(werte.back())
	return ""


func _pixel() -> void:
	print("Pixel-Schluss")
	for fall in [[56.0, "raum", 22], [-56.0, "raum", 22], [24.0, "ankommen", 12], [14.0, "raum", 22], [72.0, "raum", 22], [3.0, "raum", 22]]:
		var r := px_reihe(float(fall[0]), str(fall[1]), int(fall[2]))
		var fehler := px_ok(r, float(fall[0]))
		check(fehler == "", "%+.0f px (%s, %d Bilder): ganze Pixel, je Bild näher, endet bei 0 %s" % [float(fall[0]), fall[1], fall[2], fehler])
	# Ohne Pixel-Schluss: gerundet steht der Ausläufer (1 px, Stillstand, 1 px) – das Nachrucken.
	var roh: Array = []
	for i in range(1, 23):
		roh.append(roundf(56.0 * (1.0 - U.kurve("raum", i / 22.0))))
	check(px_ok(roh, 56.0).begins_with("Stillstand"), "zum Vergleich nur gerundet: %s" % px_ok(roh, 56.0))
	var u := px_reihe(56.0, "raum", 22, 6)
	check(px_ok(u, 56.0) == "", "unterbrochen und neu angesetzt: weiter ohne Sprung zurück %s" % px_ok(u, 56.0))
	var o := Object.new()
	o.set_meta("k", 5.0)
	check(U.px_schluss(o, "k", 0.0) == 0.0, "der letzte Wert der Kurve (0) setzt sofort ans Ziel")
	o.set_meta("k", 2.0)
	check(U.px_schluss(o, "k", -0.4) == 0.0, "kein Schritt über das Ziel hinaus")
	o.free()


## Grid on a 4K TV, where movement has to stay smooth at high refresh rates: one UI point is 2 pixels; movement
## runs on half points, and at 120 Hz there is no frame in which it stands still.
func _raster() -> void:
	print("Raster an 4K, 120 Hz")
	var vorher := Raster.skala
	Raster.setzen(null, 2.0)
	check(Raster.schritt == 0.5 and Raster.rund(10.3) == 10.5 and Raster.rund(10.2) == 10.0, "doppelte Größe: Schritt ein halber Punkt")
	# Pixel-Schluss auf halben Punkten (44 Bilder bei 120 Hz)
	for fall in [[56.0, "raum", 44], [-24.0, "ankommen", 24], [3.0, "raum", 44]]:
		var r := px_reihe(float(fall[0]), str(fall[1]), int(fall[2]))
		var fehler := ""
		var vor := float(fall[0])
		for v in r:
			var f := float(v)
			if f * 2.0 != roundf(f * 2.0):
				fehler = "kein halber Punkt (%.3f)" % f
			elif vor != 0.0 and f == vor:
				fehler = "Stillstand bei %.1f" % f
			elif absf(f) > absf(vor):
				fehler = "zurück (%.1f nach %.1f)" % [f, vor]
			vor = f
		if float(r.back()) != 0.0:
			fehler = "endet nicht bei 0"
		check(fehler == "", "Pixel-Schluss %+.0f (%s, %d Bilder bei 120 Hz): halbe Punkte, je Bild näher %s" % [float(fall[0]), fall[1], fall[2], fehler])
	# Feder der Listen bei 120 Hz: kein Bild ohne Bewegung, bis sie steht.
	var p := 0.0
	var vel := 0.0
	var stand := 0
	var bilder := 0
	while p != 300.0 and bilder < 400:
		var s := Liste.feder_px(p, vel, 300.0, 1.0 / 120.0, U.SPRING)
		if Raster.rund(s.x) == Raster.rund(p):
			stand += 1
		p = s.x
		vel = s.y
		bilder += 1
	check(p == 300.0 and stand == 0, "Feder 0 → 300 Punkte bei 120 Hz: %d Bilder, keins steht (%d)" % [bilder, stand])
	# Bildlauf: ganzer Teil im Container, Rest als Verschiebung des Inhalts.
	var sc := ScrollContainer.new()
	sc.size = Vector2(800, 200)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var inhalt := Control.new()
	inhalt.custom_minimum_size = Vector2(5000, 200)
	sc.add_child(inhalt)
	await get_tree().process_frame
	await get_tree().process_frame
	# Nav liest die Skala sonst in jedem Bild neu (hier ohne Fenster: 1).
	Nav.set_process(false)
	Raster.setzen(null, 2.0)
	Nav._scroll_to(sc, "scroll_horizontal", 300.0, false)
	var lagen: Array = []
	for i in 200:
		Nav._step_springs(1.0 / 120.0)
		var b: Vector2 = sc.get_meta("uz_bruch", Vector2.ZERO)
		lagen.append(float(sc.scroll_horizontal) + b.x)
		if not sc.has_meta("uz_bruch") and sc.scroll_horizontal == 300:
			break
	await get_tree().process_frame
	Nav.set_process(true)
	var halbe := lagen.filter(func(x: float) -> bool: return x != floorf(x)).size()
	var steht := 0
	for i in range(1, lagen.size()):
		if lagen[i] == lagen[i - 1]:
			steht += 1
	check(lagen.back() == 300.0 and not sc.has_meta("uz_bruch"), "Bildlauf endet genau bei 300, ohne Rest")
	check(halbe > 0 and steht == 0, "Bildlauf auf halben Punkten (%d Bilder mit Rest), kein Bild steht (%d)" % [halbe, steht])
	Raster.setzen(null, 1.0)
	Nav._scroll_to(sc, "scroll_horizontal", 0.0, true)
	check(sc.scroll_horizontal == 0 and not sc.has_meta("uz_bruch"), "sofort gesetzt: kein Rest")
	sc.queue_free()
	Raster.setzen(null, vorher)


func _slide() -> void:
	print("U.slide_x im Tween")
	var c := Control.new()
	c.size = Vector2(400, 100)
	add_child(c)
	await get_tree().process_frame
	U.slide_x(c, U.W_BEREICH, U.T_RAUM)
	var werte: Array = []
	var vor := U.W_BEREICH
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(U.T_RAUM * 1000.0) + 120:
		await get_tree().process_frame
		if c.offset_left != vor:
			vor = c.offset_left
			werte.append(vor)
	var fehler := px_ok(werte, U.W_BEREICH) if not werte.is_empty() else "keine Bewegung"
	check(fehler == "" and c.offset_right == c.offset_left, "gleitet in ganzen Pixeln und steht bei 0 (%d Stände) %s" % [werte.size(), fehler])
	c.queue_free()


func _tiefe() -> void:
	print("Tiefe hinter Ebenen")
	var shell := Control.new()
	shell.size = Vector2(1920, 1080)
	add_child(shell)
	await get_tree().process_frame
	shell.pivot_offset = shell.size * 0.5
	Layer._tiefe(shell, Layer.DEPTH_SCALE)
	var raender: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(U.T_RAUM * 1000.0) + 120:
		await get_tree().process_frame
		raender.append((1.0 - shell.scale.x) * 960.0)
	var ganz := true
	for r in raender:
		if absf(float(r) - roundf(float(r))) > 0.01:
			ganz = false
	check(ganz, "der Rand der Oberfläche wandert in ganzen Pixeln")
	check(absf(shell.scale.x - Layer.DEPTH_SCALE) < 0.001, "steht danach auf %.3f, am Rand auf ganzem Pixel (%.4f)" % [Layer.DEPTH_SCALE, shell.scale.x])
	Layer._tiefe(shell, 1.0, U.T_ANTWORT, true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(U.T_ANTWORT * 1000.0) + 120:
		await get_tree().process_frame
	check(shell.scale == Vector2.ONE, "zurück im Antwort-Takt genau auf 100 %")
	shell.queue_free()


func _titel() -> void:
	print("Der große Titel weicht zuerst")
	var buehne := Control.new()
	buehne.size = Vector2(1920, 1080)
	add_child(buehne)
	var host := Control.new()
	host.position = Vector2(100, 100)
	host.size = Vector2(800, 400)
	buehne.add_child(host)
	var box := VBoxContainer.new()
	host.add_child(box)
	var titel := Label.new()
	titel.text = "Elden Ring"
	titel.set_meta("uz_titel", true)
	box.add_child(titel)
	var rest := Label.new()
	rest.text = "Spielzeit"
	box.add_child(rest)
	await get_tree().process_frame
	var h := U.abgang(host, 1)
	var hull_bei_titel_weg := -1.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
		if hull_bei_titel_weg < 0.0 and is_instance_valid(titel) and titel.self_modulate.a <= 0.001 and is_instance_valid(h):
			hull_bei_titel_weg = h.modulate.a
	check(hull_bei_titel_weg >= 0.4, "der Titel ist weg, während der Rest noch kreuzt (Hülle dann %.0f %%)" % (hull_bei_titel_weg * 100.0))
	var t2 := Label.new()
	t2.set_meta("uz_titel", true)
	host.add_child(t2)
	U.titel_weichen(host)
	await get_tree().process_frame
	U.titel_zurueck(host)
	await _warte(0.15)
	check(is_equal_approx(t2.self_modulate.a, 1.0), "titel_zurueck: der Titel steht wieder ganz da")
	U.titel_weichen(host)
	await _warte(U.T_ANTWORT + 0.05)
	U.titel_zurueck(host, U.T_ANTWORT)
	await get_tree().process_frame
	var mitte := t2.self_modulate.a
	await _warte(U.T_ANTWORT + U.T_ORT + 0.1)
	check(mitte < 0.2 and is_equal_approx(t2.self_modulate.a, 1.0), "sanft zurück (Seite schließt): erst nach der Schrift, dann ganz da")
	buehne.queue_free()


func _abheben() -> void:
	print("U.abheben")
	var buehne := Control.new()
	buehne.size = Vector2(1920, 1080)
	add_child(buehne)
	var col := VBoxContainer.new()
	col.position = Vector2(50, 60)
	col.size = Vector2(600, 600)
	buehne.add_child(col)
	var oben := Control.new()
	oben.custom_minimum_size = Vector2(600, 200)
	col.add_child(oben)
	var regal := Control.new()
	regal.custom_minimum_size = Vector2(600, 300)
	regal.focus_mode = Control.FOCUS_ALL
	col.add_child(regal)
	await get_tree().process_frame
	var g0 := regal.get_global_rect()
	U.abheben(regal)
	check(regal.get_parent() == buehne and regal.has_meta("uz_skip"), "verlässt das Layout zum nächsten Vorfahren ohne Container, nicht wählbar")
	check(regal.get_global_rect().position.distance_to(g0.position) < 0.5 and regal.size.is_equal_approx(g0.size), "bleibt, wo es auf dem Schirm stand")
	await get_tree().process_frame
	check(is_equal_approx(regal.modulate.a, 1.0) or regal.modulate.a > 0.95, "hält das erste Bild (Kreuzen)")
	await _warte(U.T_WEG + 0.15)
	check(not is_instance_valid(regal) or regal.is_queued_for_deletion(), "danach frei")
	buehne.queue_free()


func _warte(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await get_tree().process_frame

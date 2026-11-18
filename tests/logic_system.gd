extends Node
## Logik des Rahmens ohne Bildschirmfotos: Feder fürs Scrollen, gleitende Reiter-Anzeiger,
## Tokens, Hinweise, Ebenen-Fokus. Aufruf:
##   godot --headless --path . res://tests/logic_system.tscn   → „Ergebnis: alles ok“

const U := preload("res://src/ui/u.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const BG := preload("res://src/ui/components/background.gd")
const Glyph := preload("res://src/ui/components/glyph.gd")
const PowerOff := preload("res://src/ui/power_off.gd")
const Quelle := preload("res://tests/quelle.gd")
const GlasWerte := preload("res://tests/glas_werte.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Feder")
	_spring()
	print("Halten: gleichmäßig statt Anfahren und Bremsen")
	_hold()
	print("Reiter-Anzeiger")
	_stretch()
	await _strip()
	await _plain_tab()
	print("Tokens")
	_tokens()
	print("Hinweise und Ebenen")
	_hints()
	await _layer_focus()
	print("Hintergrund")
	check(is_zero_approx(BG.pan_offset(3, 7)), "mittlerer Bereich: Lichter stehen in der Mitte")
	check(is_equal_approx(BG.pan_offset(0, 7), -BG.pan_offset(6, 7)) and BG.pan_offset(0, 7) > 0.0, "Schwenk links und rechts gleich weit")
	check(absf(BG.pan_offset(0, 7)) <= 4.0 * BG.PAN_STEP, "Schwenk bleibt klein (%.0f px)" % absf(BG.pan_offset(0, 7)))
	print("Ausschalten")
	await _power_off()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _spring() -> void:
	for fps in [60.0, 30.0, 12.0]:
		var pos := 0.0
		var vel := 0.0
		var over := false
		var t := 0.0
		var settled := -1.0
		while t < 1.0:
			var st := U.spring_step(pos, vel, 100.0, 1.0 / fps)
			pos = st.x
			vel = st.y
			t += 1.0 / fps
			if pos > 100.5:
				over = true
			if settled < 0.0 and absf(pos - 100.0) < 1.0:
				settled = t
		check(not over and settled > 0.0 and settled < 0.4, "Feder bei %d Bildern/s: kein Überschwingen, steht nach %.2f s" % [int(fps), settled])
	var big := U.spring_step(0.0, 0.0, 100.0, 5.0)
	check(absf(big.x - 100.0) < 0.01 and absf(big.y) < 0.01, "riesiger Zeitschritt (Ruckler) bleibt stabil")


## Halten: alle 120 ms ein Schritt von 76 px (Zeile). Verglichen wird, wie stark die
## Geschwindigkeit zwischen den Schritten einbricht – früher (neu startendes Abbremsen) und jetzt.
func _hold() -> void:
	var dt := 1.0 / 60.0
	var step := 76.0
	var every := 0.12
	# Feder
	var pos := 0.0
	var vel := 0.0
	var target := 0.0
	var next := 0.0
	var t := 0.0
	var vs: Array[float] = []
	while t < 1.5:
		if t >= next:
			target += step
			next += every
		var st := U.spring_step(pos, vel, target, dt, U.SPRING_HOLD)
		var moved := (st.x - pos) / dt
		pos = st.x
		vel = st.y
		if t > 0.5:
			vs.append(moved)
		t += dt
	var spring_ratio := _min_ratio(vs)
	# Früher: bei jedem Schritt neues Abbremsen über 0,24 s (kubisch), von der aktuellen Lage aus.
	pos = 0.0
	target = 0.0
	next = 0.0
	t = 0.0
	var from := 0.0
	var t_start := 0.0
	var tws: Array[float] = []
	while t < 1.5:
		if t >= next:
			target += step
			next += every
			from = pos
			t_start = t
		var k := clampf((t - t_start) / 0.24, 0.0, 1.0)
		var np := lerpf(from, target, 1.0 - pow(1.0 - k, 3.0))
		if t > 0.5:
			tws.append((np - pos) / dt)
		pos = np
		t += dt
	var tween_ratio := _min_ratio(tws)
	print("       langsamstes Tempo im Verhältnis zum Mittel: früher %.2f, jetzt %.2f" % [tween_ratio, spring_ratio])
	check(spring_ratio > 0.6, "Feder hält beim Halten das Tempo (%.2f)" % spring_ratio)
	check(spring_ratio > tween_ratio + 0.25, "deutlich gleichmäßiger als das neu startende Abbremsen")


static func _min_ratio(vs: Array[float]) -> float:
	if vs.is_empty():
		return 0.0
	var sum := 0.0
	var lo := INF
	for v in vs:
		sum += v
		lo = minf(lo, v)
	var mean := sum / vs.size()
	return lo / mean if mean > 0.0 else 0.0


func _stretch() -> void:
	var a := Rect2(100, 0, 80, 50)
	var b := Rect2(300, 0, 60, 50)
	check(TabStrip.stretch(a, b, 1.0) == b, "am Ende genau am Ziel")
	var s0 := TabStrip.stretch(a, b, 0.0)
	check(is_equal_approx(s0.position.x, a.position.x) and is_equal_approx(s0.end.x, a.end.x), "am Anfang genau am Start")
	var mid := TabStrip.stretch(a, b, 0.3)
	check(mid.size.x > maxf(a.size.x, b.size.x), "unterwegs gedehnt: Vorderkante eilt voraus (%.0f px)" % mid.size.x)
	var back := TabStrip.stretch(b, a, 0.3)
	check(back.position.x < b.position.x - 40.0 and back.end.x > a.end.x, "nach links: linke Kante führt")
	var prev := -INF
	var mono := true
	for i in 21:
		var r := TabStrip.stretch(a, b, i / 20.0)
		if r.end.x < prev - 0.01:
			mono = false
		prev = r.end.x
	check(mono, "Vorderkante läuft nie zurück")


func _strip() -> void:
	var holder := Control.new()
	holder.size = Vector2(1200, 80)
	add_child(holder)
	var strip := TabStrip.new()
	strip.style = "tab"
	holder.add_child(strip)
	var items: Array = []
	for i in 3:
		var it = NavItem.new()
		it.setup(["Spiele", "Shop", "Erfolge"][i], "", "tab", i == 0)
		strip.add_child(it)
		items.append(it)
	await get_tree().process_frame
	await get_tree().process_frame
	check(items[0].managed and items[1].managed, "Reiter in der Leiste zeichnen nicht selbst")
	var w0: float = items[1].size.x
	items[1].set_selected(true)
	items[0].set_selected(false)
	await get_tree().process_frame
	check(is_equal_approx(items[1].size.x, w0), "Auswahl wechselt ohne Verrutschen (fette Schrift hat ihren Platz)")
	# Cursor auf die Leiste, dann einen Reiter weiter
	items[0].grab_focus()
	strip._process(1.0)
	items[1].grab_focus()
	strip._process(0.05)
	var mid_ink0: float = items[0]._ink
	var mid_ink1: float = items[1]._ink
	strip._process(1.0)
	strip._process(1.0)
	check(mid_ink0 > 0.0 and mid_ink0 < 1.0 or mid_ink1 > 0.0 and mid_ink1 < 1.0,
			"Schrift wird unterwegs nach und nach dunkel (%.2f / %.2f)" % [mid_ink0, mid_ink1])
	check(is_equal_approx(items[1]._ink, 1.0) and is_zero_approx(items[0]._ink), "am Ziel: nur der gewählte Reiter dunkel")
	var lab0: Label = items[0]._label
	check(lab0.get_theme_color("font_color") == UzTheme.col("muted"), "verlassener Reiter wird wieder leise (nicht hell hängen geblieben)")
	items[1].release_focus()
	strip._process(1.0)
	check(is_zero_approx(items[1]._ink), "ohne Cursor: Schrift hell, nur der Goldstrich bleibt")
	var lr: Rect2 = strip._line
	var ir: Rect2 = items[1].ink_rect()
	check(absf(lr.get_center().x - (items[1].position.x + ir.get_center().x)) < 1.0, "Goldstrich mittig unter dem gewählten Reiter")
	holder.queue_free()
	await get_tree().process_frame


## Ohne Leiste zeichnet ein Reiter selbst – auch dort darf ein abgewählter Reiter nicht hell bleiben.
func _plain_tab() -> void:
	var box := HBoxContainer.new()
	add_child(box)
	var a = NavItem.new()
	a.setup("Spiele", "", "tab", true)
	var b = NavItem.new()
	b.setup("Shop", "", "tab", false)
	box.add_child(a)
	box.add_child(b)
	await get_tree().process_frame
	a.grab_focus()
	await get_tree().create_timer(0.3).timeout
	b.grab_focus()
	a.set_selected(false)
	b.set_selected(true)
	await get_tree().create_timer(0.4).timeout
	var lab: Label = a._label
	check(not a.managed and lab.get_theme_color("font_color") == UzTheme.col("muted"), "einzelner Reiter: abgewählt wird wieder leise")
	box.queue_free()
	await get_tree().process_frame


func _tokens() -> void:
	check(UzTheme.size("cap") == 15 and UzTheme.size("m") == 22, "Schriftstufen: cap 15 … m 22")
	check(UzTheme.space("m") == 16 and UzTheme.space("xl") == 32 and UzTheme.GUTTER == 96, "Abstände im 4-px-Raster, Rand 96")
	var ok := true
	for i in range(1, UzTheme.ELEVATION.size()):
		if float(UzTheme.ELEVATION[i].a) <= 0.0:
			ok = false
	check(ok and int(UzTheme.ELEVATION[3].s) > int(UzTheme.ELEVATION[1].s), "Höhenstufen: schwebend weiter als ruhend")
	# Graphit trägt die Marke (matt, weich gerundet, ein Cursor): Matte Flächen statt Glas, die
	# Auswahl ist eine gehobene matte Fläche mit heller Schrift, der Ring um Cover hell.
	var pm: Color = UzTheme.col("primary")
	check(UzTheme.cursor_frame() and pm.a > 0.99 and UzTheme.col("glass").a > 0.99 and UzTheme.col("on_focus").get_luminance() > 0.6
			and UzTheme.col("focus").get_luminance() > 0.8, "Graphit: matte Flächen, Schrift auf der Auswahl hell, Cursor hell")
	var cb := UzTheme.focus_fill(999)
	check(cb.border_width_top == 0 and cb.expand_margin_top == 0.0 and cb.corner_radius_top_left >= UzTheme.radius,
			"ein Cursor: gefüllte Fläche ohne Linie, gerundet")
	# Schatten, Glimmen und Glas mit den Werten des früheren Glas-Aussehens geprüft (Graphit ist flach).
	UzTheme.grund = GlasWerte.werte()
	UzTheme.apply()
	var sb := UzTheme.lift(StyleBoxFlat.new(), 3)
	check(sb.shadow_size == int(UzTheme.ELEVATION[3].s) and sb.shadow_offset.y > 0.0, "lift setzt weichen Schatten nach unten")
	var gb := UzTheme.with_glow(StyleBoxFlat.new(), 1.0)
	check(gb.shadow_offset == Vector2.ZERO and is_equal_approx(gb.shadow_color.a, float(UzTheme.GLOW.a)), "Glimmen ohne Versatz, zart")
	var p: Color = UzTheme.col("primary")
	var f: Color = UzTheme.col("focus")
	# Kein gedämpftes Hell mehr (sah gedrückt aus): der ruhende Hauptknopf ist Glas, den Akzent
	# trägt sein Symbol.
	check(p.a < 0.3 and f.a > 0.99, "Hauptknopf ruht als Glas, nur die Auswahl ist eine helle Fläche")
	UzTheme.grund = GlasWerte.Aussehen.werte()
	UzTheme.apply()
	var ai: Color = UzTheme.col("accent_ink")
	check(ai != Color.MAGENTA and ai.get_luminance() >= 0.3, "Akzent als Symbolfarbe ist auf dunklem Raum lesbar")
	check(U.glow_for(Vector2(1000, 72)) < U.glow_for(Vector2(160, 56)), "breite Zeilen glimmen zarter als kleine Pillen")
	var g = Glyph.new()
	check("subtle" in g, "Tastensymbol kennt die leise Form")
	g.free()


func _hints() -> void:
	var m := HintBar.merge([["lb", ""], ["rb", "Bereich"], ["b", "Zurück"]])
	check(m.size() == 2 and (m[0][0] as Array) == ["lb", "rb"] and m[0][1] == "Bereich", "„LB RB Bereich“ statt einsamem LB")
	check(m[1][0] == ["b"] and m[1][1] == "Zurück", "einfache Hinweise bleiben einzeln")


## Hat eine Ebene nichts zum Wählen, bleibt der Fokus dahinter – A, X, Y dürfen ihn nicht auslösen.
func _layer_focus() -> void:
	var root := Control.new()
	root.size = Vector2(800, 600)
	add_child(root)
	var behind := Button.new()
	behind.text = "dahinter"
	root.add_child(behind)
	var layer := Control.new()
	root.add_child(layer)
	await get_tree().process_frame
	behind.grab_focus()
	check(Nav.active() == behind, "ohne Ebene zählt der Fokus")
	Nav.layers.append(layer)
	check(Nav.active() == null, "Ebene ohne Auswahl: nichts dahinter auslösbar")
	var hints := HintBar.collect()
	check(not hints.any(func(h): return h[0] == "a"), "Hinweise zeigen kein A für etwas hinter der Ebene")
	var inside := Button.new()
	layer.add_child(inside)
	await get_tree().process_frame
	inside.grab_focus()
	check(Nav.active() == inside, "in der Ebene zählt der Fokus wieder")
	Nav.layers.erase(layer)
	root.queue_free()
	await get_tree().process_frame


## Ausschalt-Animation: welche Wege sie auslösen, wann sie sofort beendet, Klang, Abkürzen, Grenze.
func _power_off() -> void:
	for r in ["quit", "quit_full", "hung", "wm_close", "sleep", "restart", "shutdown"]:
		check(PowerOff.mode_for(r, true, true) == "voll", "%s: volle Ausschalt-Animation" % r)
		check(PowerOff.mode_for(r, false, true) == "aus", "%s: Einstellung aus → sofort" % r)
		check(PowerOff.mode_for(r, true, false) == "aus", "%s: Fenster nicht zu sehen → sofort" % r)
		check(PowerOff.mode_for(r, true, true, true) == "kurz", "%s: Animationen reduzieren → kurze Fassung" % r)
	for r in ["forced", "second", ""]:
		check(PowerOff.mode_for(r, true, true) == "aus", "„%s“ beendet sofort" % r)
	check(PowerOff.window_shown(true, Window.MODE_EXCLUSIVE_FULLSCREEN, false), "Vollbild: Fenster zu sehen")
	check(not PowerOff.window_shown(true, Window.MODE_MINIMIZED, false), "minimiert: sofort beenden")
	check(not PowerOff.window_shown(false, Window.MODE_FULLSCREEN, false), "versteckt: sofort beenden")
	check(not PowerOff.window_shown(true, Window.MODE_FULLSCREEN, true), "ohne Bildschirm: sofort beenden")
	check(not PowerOff.window_shown(true, Window.MODE_FULLSCREEN, false, true), "im Spiel geparkt: sofort beenden")
	check(not PowerOff.window_shown(true, Window.MODE_FULLSCREEN, false, false, true), "durchsichtig über Spiel/Video: sofort beenden")
	check(is_equal_approx(PowerOff.delay_for("voll", 1.25), PowerOff.LENGTH), "Beenden wartet die Animation ab (%.2f s)" % PowerOff.delay_for("voll", 1.25))
	check(PowerOff.delay_for("voll", 5.0) <= 1.6 and PowerOff.delay_for("kurz", 5.0) <= 1.6, "nie länger als 1,6 s, auch mit langem eigenem Klang")
	check(PowerOff.delay_for("aus", 1.25) == 0.0, "aus: kein Aufschub")
	check(is_equal_approx(PowerOff.delay_for("kurz", 1.25), 1.25), "kurz: wartet nur den Klang ab")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	var x := InputEventJoypadButton.new()
	x.button_index = JOY_BUTTON_X
	x.pressed = true
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	var ent := InputEventKey.new()
	ent.keycode = KEY_ENTER
	ent.pressed = true
	var echo := InputEventKey.new()
	echo.keycode = KEY_ENTER
	echo.pressed = true
	echo.echo = true
	check(PowerOff.is_skip(a) and PowerOff.is_skip(b) and PowerOff.is_skip(ent), "A, B und Enter kürzen ab")
	check(not PowerOff.is_skip(x) and not PowerOff.is_skip(up) and not PowerOff.is_skip(echo), "X, Loslassen und Tastenwiederholung kürzen nicht ab")
	check(Config.DEFAULTS.system.get("power_off") == true, "Einstellung „Ausschalt-Animation“ ist ab Werk an")
	# Klang: eigene Datei, um 1 s, ohne Übersteuern und nicht lauter als der Start, endet in Stille.
	check(load("res://assets/sounds/power_off.wav") is AudioStreamWAV, "assets/sounds/power_off.wav ist da (importiert)")
	# Die Rohdatei (ohne die Kompression beim Import) prüfen.
	var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/sounds/power_off.wav"))
	if wav:
		var n := wav.data.size() / 4
		var peak := 0.0
		var tail := 0.0
		for i in n:
			var v := absf(wav.data.decode_s16(i * 4) / 32768.0)
			peak = maxf(peak, v)
			if i > n - int(0.05 * wav.mix_rate):
				tail = maxf(tail, v)
		var len_s := float(n) / wav.mix_rate
		check(wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS, "Klang: 16 Bit Stereo")
		check(len_s > 0.9 and len_s < PowerOff.LENGTH, "Klang %.2f s, kürzer als die Animation" % len_s)
		check(peak > 0.05 and peak <= db_to_linear(-15.0), "Klang leise, nicht lauter als der Start (Spitze %.2f)" % peak)
		check(tail < 0.01, "Klang endet in Stille")
	check("power_off" in Sfx.NAMES and Sfx.length("power_off") > 0.9, "Sfx kennt den Ausschaltklang")
	# Welche Wege die Animation auslösen (im Quelltext, ohne Uzai wirklich zu beenden).
	var main_src := Quelle.lesen("res://src/main.gd")
	var menu_src := FileAccess.get_file_as_string("res://src/ui/layers/power_menu.gd")
	var quit_fn := main_src.substr(main_src.find("func _quit_uzai("), 1200)
	check(quit_fn.find("start_wake_watch()") >= 0 and quit_fn.find("start_wake_watch()") < quit_fn.find("await power_off(")
			and quit_fn.find("await power_off(") < quit_fn.find("get_tree().quit()"),
		"Uzai schließen / ganz beenden: Wächter, dann Animation, dann beenden")
	check(main_src.contains("auto_accept_quit = false") and main_src.contains("await power_off(\"wm_close\")"),
			"Alt+F4/Taskleiste: Beenden wartet auf die Animation")
	check(menu_src.contains("m.power_off_pc(action)"), "Ruhezustand, Neustart, Herunterfahren: erst die Animation")
	# PC aus bzw. neu (Freund: „mega extra warning“): erst die Rückfrage, Abbrechen vorn, nur Halten bestätigt.
	var PC := load("res://src/ui/layers/power_confirm.gd")
	check(menu_src.contains("PowerConfirm.new()") and menu_src.find("PowerConfirm.new()") < menu_src.find("await ausschalten_pc(main, action)"),
			"Neustart/Herunterfahren: Rückfrage vor dem Ausschalten")
	var t_aus: Dictionary = PC.texte("shutdown", "")
	var t_neu: Dictionary = PC.texte("restart", "Elden Ring")
	check(str(t_aus.titel) == "PC ausschalten?" and str(t_aus.knopf) == "Ausschalten" and str(t_aus.spiel) == "",
			"Rückfrage Ausschalten: kurzer Titel, ohne Spiel kein Hinweis auf Spielstände")
	check(str(t_neu.titel) == "PC neu starten?" and str(t_neu.spiel).begins_with("Elden Ring wird beendet") and str(t_neu.spiel).contains("verloren"),
			"Rückfrage Neustart mit Spiel: nennt das Spiel und Ungespeichertes")
	check(PC.anteil(0) == 0.0 and is_equal_approx(PC.anteil(PC.HALTEN_MS / 2), 0.5) and PC.anteil(PC.HALTEN_MS + 300) == 1.0 and PC.HALTEN_MS >= 800,
			"Bestätigen: Ring füllt sich über rund eine Sekunde")
	var pc_src := FileAccess.get_file_as_string("res://src/ui/layers/power_confirm.gd")
	check(pc_src.contains("ab.set_meta(\"uz_default\", true)") and pc_src.contains("_knopf.pressed.connect(_halten)") and pc_src.contains("while is_inside_tree() and not _closing and _gedrueckt()"),
			"Rückfrage: Auswahl auf Abbrechen, Ausschalten erst nach Halten")
	# Ablauf: endet von selbst nach LENGTH (spätestens CAP), Abkürzen geht schnell.
	for case in ["normal", "skip"]:
		await get_tree().process_frame
		var p: Control = PowerOff.new()
		add_child(p)
		var t0 := Time.get_ticks_msec()
		var box := { "done": -1 }
		p.finished.connect(func() -> void: box.done = Time.get_ticks_msec() - t0)
		if case == "skip":
			await get_tree().create_timer(0.3).timeout
			var ev := InputEventJoypadButton.new()
			ev.button_index = JOY_BUTTON_B
			ev.pressed = true
			p._input(ev)
		while int(box.done) < 0 and Time.get_ticks_msec() - t0 < 3000:
			await get_tree().process_frame
		var ms := int(box.done)
		if case == "normal":
			check(ms >= int(PowerOff.LENGTH * 1000) - 80 and ms <= int(PowerOff.CAP * 1000) + 150, "Animation endet von selbst (%d ms)" % ms)
		else:
			check(ms > 0 and ms <= 300 + int(PowerOff.SKIP_FADE * 1000) + 120, "zweiter Druck auf B kürzt ab (%d ms)" % ms)
		p.queue_free()

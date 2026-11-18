extends Node
## Logik des Bereichs Einstellungen ohne Bilder: Einstellungszeilen (Schieber, Wechselwerte,
## Schalter, Info-Zeilen), gekürzte Pfade, Dialog-Startauswahl, Dateiauswahl, Mitteilungen,
## Uzai-Zeichen und kleine Texthelfer.
## Aufruf: godot --headless --path . res://tests/logic_einstellungen.tscn

const SettingRow := preload("res://src/ui/components/setting_row.gd")
const Mark := preload("res://src/ui/components/uzai_logo.gd")
const Form := preload("res://src/ui/marke_form.gd")
const Boot := preload("res://src/ui/boot.gd")
const QrView := preload("res://src/ui/components/qr_view.gd")
const SettingsView := preload("res://src/ui/sections/settings_view.gd")
const FileBrowser := preload("res://src/ui/layers/file_browser.gd")
const Dialog := preload("res://src/ui/layers/dialog.gd")
const Keyboard := preload("res://src/ui/layers/keyboard.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_rows()
	_texts()
	_mark()
	await _dialog()
	await _keyboard()
	_toasts()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _rows() -> void:
	print("Einstellungszeilen")
	var got: Array = []
	var s = SettingRow.new()
	s.setup("slider", "Totzone", "", 0.5)
	s.min_v = 0.2
	s.max_v = 0.8
	s.step = 0.05
	s.changed.connect(func(v: Variant) -> void: got.append(v))
	s.nav_lr(1)
	check(is_equal_approx(float(s.value), 0.55), "Schieber: ein Schritt nach rechts (0,55)")
	for i in 10:
		s.nav_lr(1)
	check(is_equal_approx(float(s.value), 0.8), "Schieber bleibt am Ende stehen (0,8)")
	var n := got.size()
	s.nav_lr(1)
	check(got.size() == n, "am Anschlag kein weiteres „geändert“")
	check(s._full_text() == "80 %", "Schieber zeigt Prozent")
	s.free()

	var c = SettingRow.new()
	c.setup("choice", "Ecken", "", "leicht")
	c.options = [["eckig", "Eckig"], ["leicht", "Leicht"], ["rund", "Rund"]]
	c._step_choice(1)
	check(c.value == "rund", "Wechselwert: weiter zum nächsten")
	c._step_choice(1)
	check(c.value == "eckig", "Wechselwert: am Ende wieder von vorn")
	c._step_choice(-1)
	check(c.value == "rund", "Wechselwert: links zurück")
	check(c._option_text() == "Rund", "Wechselwert zeigt den Text, nicht den Schlüssel")
	c.free()

	var t = SettingRow.new()
	t.setup("toggle", "Vibration", "", false)
	var flips: Array = []
	t.changed.connect(func(v: Variant) -> void: flips.append(v))
	t.nav_lr(1)
	t.nav_lr(1)
	check(bool(t.value) and flips.size() == 1, "Schalter: rechts schaltet an, zweimal rechts nur einmal")
	t.activate()
	check(not bool(t.value) and flips.size() == 2, "Schalter: A schaltet um")
	check(t.activate_sound() == "toggle_on", "Schalter klingt nach „an“, wenn er gleich angeht")
	t.free()

	var called := [false]
	var info = SettingRow.new()
	info.setup("info", "Version", "", null)
	info.on_activate = func() -> void: called[0] = true
	info.activate()
	check(not called[0], "Info-Zeile: A tut nichts")
	check(info._hint() == "—", "Info-Zeile: kein A-Hinweis unten")
	info.free()

	_nur_a()

	var a = SettingRow.new()
	a.setup("action", "Ordner")
	a.subtitle = "PS2"
	a.dot = Color.RED
	a.tone = "faint"
	check(a.subtitle == "PS2" and a.tone == "faint" and a.dot == Color.RED, "Zusätze lassen sich vor und nach dem Einhängen setzen")
	a.free()


func _texts() -> void:
	print("Texte")
	var f := UzTheme.ui("ui")
	var long := "D:/Spiele/PlayStation 2/Sammlung/Japan-Importe/Neu"
	var fit := SettingRow.fit_text(long, 320.0, f, 22)
	check(fit.begins_with("…/") and fit.ends_with("/Neu"), "langer Pfad verliert vorne Ordner: " + fit)
	check(f.get_string_size(fit, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x <= 320.0, "gekürzter Pfad passt in die Breite")
	check(SettingRow.fit_text("Rund", 320.0, f, 22) == "Rund", "kurzer Wert bleibt, wie er ist")
	var win := SettingRow.fit_text("C:\\Emulatoren\\PCSX2\\Versionen\\2.0\\pcsx2-qt.exe", 260.0, f, 22)
	check(win.begins_with("…\\") and win.ends_with("pcsx2-qt.exe"), "Windows-Pfad mit Backslash: " + win)
	var plain := SettingRow.fit_text("Uzai-Leiste über dem Video und noch viel mehr Text", 200.0, f, 22)
	check(plain.ends_with("…"), "langer Text endet mit …")
	var sv = SettingsView.new()
	check(sv._lang_names("de, en,xx") == "Deutsch, Englisch, xx", "Untertitel-Sprachen als Namen")
	var order: Array = sv._section_order()
	check(order == ["games", "shop", "achievements", "apps"], "Bereiche der Leiste (Einstellungen steht immer da, Freunde auf Select): %s" % str(order))
	sv.free()
	var fb = FileBrowser.new()
	fb._dir = "D:/Spiele/PS2"
	check(fb._crumb_text() == "Laufwerke  ›  D:  ›  Spiele  ›  PS2", "Dateiauswahl: Weg als Zeile")
	fb._dir = "/"
	check(fb._crumb_text() == "System", "Dateiauswahl: Wurzel ohne überzähliges ›")
	fb._dir = "D:/a/b/c/d/e"
	check(fb._crumb_text().contains("…"), "Dateiauswahl: tiefe Wege gekürzt")
	check(fb._parent_of("C:/") == "" and fb._parent_of("/") == "" and fb._parent_of("D:/Spiele/PS2") == "D:/Spiele", "Dateiauswahl: eine Ebene höher")
	check(fb._drive_name("C:/") == "Laufwerk C:", "Dateiauswahl: Laufwerk benannt")
	fb.free()
	check(QrView._in_eye(0, 0, 25) and QrView._in_eye(24, 3, 25) and QrView._in_eye(2, 22, 25) and not QrView._in_eye(12, 12, 25), "QR: Ortungsaugen erkannt")


func _mark() -> void:
	print("Zeichen")
	# Marke „U-Band“: ein U aus zwei Bändern (außen, innen), dazwischen die Fuge aus Licht – kein
	# Punkt, kein Kreis drumherum.
	var formen: Array = Mark.flach_formen()
	var teile: Array = formen[0]
	check(teile.size() == 2, "zwei Bänder, nichts sonst (kein Punkt)")
	var drin := true
	for poly in teile:
		for q in (poly as PackedVector2Array):
			drin = drin and absf(q.x) <= Form.B * 0.5 + 0.001 and absf(q.y) <= Form.H * 0.5 + 0.001
	check(drin, "Bänder im Maß des Zeichens (%.1f × %.1f)" % [Form.B, Form.H])
	check(Geometry2D.intersect_polygons(teile[0], teile[1]).is_empty(), "Bänder berühren sich nicht (die Fuge bleibt offen)")
	check(Form._laenge(teile[0]) > Form._laenge(teile[1]), "außen das längere Band")
	var fuge: PackedVector2Array = formen[1]
	check(fuge[0].x < 0.0 and fuge[fuge.size() - 1].x > 0.0 and is_equal_approx(fuge[0].y, Form.H * 0.5), "Fuge von oben links durch den Bogen nach oben rechts")
	var tief := 1e9
	for q in fuge:
		tief = minf(tief, q.y)
	var m: Control = Mark.new()
	m.set("stil", "ton")
	m.size = Vector2(Mark.zeichen_breite(190.0, false), 190.0)
	check(absf(m.call("licht_pos").y - (95.0 - tief * 100.0)) < 1.0, "Lichtschein am Grund des Bogens")
	check(not m.call("mit_kachel"), "in der Kopfzeile ohne Kachel")
	m.set("stil", "marke")
	m.size = Vector2(190.0, 190.0)
	check(m.call("mit_kachel") and is_equal_approx(m.call("_u_hoehe"), 190.0 * Mark.KACHEL_U), "als Marke auf der Kachel wie im App-Symbol (U %d %% der Kachel)" % int(Mark.KACHEL_U * 100))
	m.free()
	check(is_equal_approx(Mark.zeichen_breite(1.9, false), 1.7) and is_equal_approx(Mark.zeichen_breite(10.0), 10.0)
		and is_equal_approx(Mark.word_width(1.0), float(Form.wort_x()[4])), "Maße: U 1,7 × 1,9, Kachel quadratisch, Wortmarke %.2f" % Mark.WORT_BREITE)
	check(Form.wort_linien().size() == 3 and Form.wort_umrisse().size() == 4, "Wortmarke: vier Buchstaben, drei Lichter (U, Z, A)")
	# Kopfzeile eingebunden: das U im Ton der Schrift, nur die Linie im Akzent.
	var fk: Dictionary = Mark.farben(Mark.KOPF_STIL, UzTheme.col("accent"))
	check(Mark.KOPF_STIL in Mark.STILE and (fk.aussen[0] as Color) == UzTheme.col("text") and (fk.linie as Color) == UzTheme.col("accent"),
		"Kopfzeile: U im Ton der Schrift, Linie im Akzent")
	var fm: Dictionary = Mark.farben("marke", Color("#a47bff"))
	check((fm.aussen[0] as Color).to_html(false) == "795cb9" and (fm.linie as Color).to_html(false) == "ad88ff", "Marke: Farben wie icon.svg")
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	check(svg.contains("795cb9") and svg.contains("ad88ff") and svg.contains("rx=\"54\""), "App-Symbol: dieselbe Kachel und dieselben Farben")


func _dialog() -> void:
	print("Dialog")
	var host := Control.new()
	get_tree().root.add_child(host)
	# Ohne Hauptszene: Die Steuerung braucht trotzdem eine Wurzel, zu der sie zurückkehrt.
	var keep_scope: Control = Nav.root_scope
	Nav.root_scope = host
	var d = Dialog.new()
	d.heading = "Emulator löschen?"
	d.text = "Test"
	d.buttons = [["Löschen", func() -> void: pass, "danger"], ["Behalten", func() -> void: pass]]
	d.open(host)
	await get_tree().process_frame
	await get_tree().process_frame
	var def: Control = Nav.default_in(d)
	check(def is Button and (def as Button).text == "Behalten", "Löschen-Dialog wählt zuerst den sicheren Knopf")
	d.close()
	var e = Dialog.new()
	e.heading = "Ōkami startet nicht"
	e.text = "Kein Emulator."
	e.buttons = [["Einstellungen öffnen", func() -> void: pass], ["Schließen", func() -> void: pass]]
	e.open(host)
	await get_tree().process_frame
	var def2: Control = Nav.default_in(e)
	check(def2 is Button and (def2 as Button).text == "Einstellungen öffnen", "Startfehler: Hauptknopf zuerst")
	e.close()
	await get_tree().create_timer(0.3).timeout
	Nav.root_scope = keep_scope
	host.queue_free()


## Zeilen der Einstellungen (nur_a, settings_bausteine.gd _add): Werte ändert nur A, links/rechts
## bleibt Bewegung (Nav sucht die Spalte, links aus einer Unterseite hinaus). Außerhalb der
## Einstellungen (Spieloptionen, Seitenleisten) gilt weiter das Obige.
func _nur_a() -> void:
	print("Einstellungen: Steuerkreuz bewegt, A ändert")
	var t = SettingRow.new()
	t.setup("toggle", "Vibration", "", false)
	t.nur_a = true
	check(not t.nav_lr(1) and not t.nav_lr(-1) and not bool(t.value), "Schalter: links/rechts ändern nichts (Nav bewegt)")
	t.activate()
	check(bool(t.value), "Schalter: A kippt")
	t.set_meta("uz_lr_block", true)
	check(t.nav_lr(1) and bool(t.value), "rechts neben der Zeile ist nichts: Anstoß, kein Wechsel")
	var zurueck := [0]
	t.set_meta("uz_links_zurueck", func() -> void: zurueck[0] += 1)
	check(t.nav_lr(-1) and zurueck[0] == 1 and bool(t.value), "Unterseite: links geht hinaus, der Wert bleibt")
	t.free()

	var c2 = SettingRow.new()
	c2.setup("choice", "Uhr", "", true)
	c2.options = [[true, "24 Stunden"], [false, "12 Stunden"]]
	c2.nur_a = true
	check(not c2.nav_lr(1) and c2.value == true, "Auswahl: rechts wechselt nicht")
	c2.activate()
	check(c2.value == false and c2._hint() == "Wechseln", "Auswahl mit zwei Werten: A wechselt")
	c2.free()
	var c3 = SettingRow.new()
	c3.setup("choice", "Ecken", "", "leicht")
	c3.options = [["eckig", "Eckig"], ["leicht", "Leicht"], ["rund", "Rund"]]
	c3.nur_a = true
	check(c3._hint() == "Auswählen", "Auswahl mit mehr Werten: A heißt „Auswählen“ (öffnet die Liste)")
	c3.activate()
	check(c3.value == "rund", "ohne Hauptfenster (Test): A wechselt zum nächsten Wert")
	c3._waehlen("eckig")
	check(c3.value == "eckig", "Wert aus der Auswahlliste übernommen")
	c3.free()

	var s = SettingRow.new()
	s.setup("slider", "Totzone", "", 0.5)
	s.min_v = 0.2
	s.max_v = 0.8
	s.step = 0.05
	s.nur_a = true
	var got: Array = []
	s.changed.connect(func(v: Variant) -> void: got.append(v))
	check(not s.nav_lr(1) and is_equal_approx(float(s.value), 0.5), "Regler: rechts ändert nichts, solange nicht eingestellt wird")
	check(s._hint() == "Einstellen" and not s.nav_b(), "Regler: A heißt „Einstellen“, B geht normal zurück")
	s.activate()
	check(s._stellen and str(s.get_meta("uz_hint_a")) == "Fertig" and str(s.get_meta("uz_hint_lr")) == "Ändern", "A beginnt das Einstellen (Hinweise „Ändern“, „Fertig“)")
	s.nav_lr(1)
	s.nav_lr(1)
	s.nav_lr(-1)
	check(is_equal_approx(float(s.value), 0.55) and got.size() == 3, "beim Einstellen: links/rechts ändern (0,55)")
	check(s.nav_b() and not s._stellen and not s.has_meta("uz_hint_lr"), "B beendet das Einstellen (statt zurückzugehen)")
	check(not s.nav_lr(1) and is_equal_approx(float(s.value), 0.55), "danach bewegt rechts wieder")
	s.activate()
	s.activate()
	check(not s._stellen and str(s.get_meta("uz_hint_a")) == "Einstellen", "A beendet das Einstellen ebenso")
	s.free()
	var hb := load("res://src/ui/components/hint_bar.gd")
	check(hb.merge([["a", "Fertig"], ["lr", "Ändern"], ["b", "Fertig"]]) == [[["lr"], "Ändern"], [["a", "b"], "Fertig"]],
			"Hinweise beim Einstellen: „Ändern“ und „A B Fertig“ (nicht zweimal dasselbe Wort)")


## Bildschirmtastatur: LB/RB schieben die Schreibmarke, Tippen und Löschen wirken dort; das
## Steuerkreuz läuft am Rand auf der anderen Seite weiter.
func _keyboard() -> void:
	print("Bildschirmtastatur")
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	get_tree().root.add_child(host)
	var keep_scope: Control = Nav.root_scope
	Nav.root_scope = host
	var keep_device := str(Nav.device)
	# Mit echter Tastatur oder Maus kommt die Tastatur ohne Tastenfeld; die Pfeile schieben die Schreibmarke.
	Nav.device = "keys"
	var kk = Keyboard.new()
	kk.heading = "Suche"
	kk.text = "abc"
	kk.open(host)
	for i in 3:
		await get_tree().process_frame
	check(not kk._keys.visible and str(Nav.focused().get("label")) == "Fertig", "Tastatur/Maus: ohne Tastenfeld, Auswahl auf „Fertig“")
	var links := InputEventKey.new()
	links.keycode = KEY_LEFT
	links.pressed = true
	kk._input(links)
	check(int(kk.caret) == 2, "Tastatur/Maus: Pfeil links schiebt die Schreibmarke")
	Nav.set_device("pad")
	await get_tree().process_frame
	check(kk._keys.visible, "zum Controller gegriffen: das Tastenfeld klappt auf")
	kk.close()
	for i in 20:
		await get_tree().process_frame
	# Mit dem Controller: das volle Tastenfeld.
	Nav.device = "pad"
	var kb = Keyboard.new()
	kb.heading = "Nachricht"
	kb.text = "Hallo Wlt"
	kb.open(host)
	for i in 3:
		await get_tree().process_frame
	check(int(kb.caret) == 9, "Schreibmarke steht am Anfang am Ende des Textes")
	Nav._fire("lb")
	Nav._fire("lb")
	check(int(kb.caret) == 7, "LB: einen Buchstaben nach links")
	kb._type("e")
	check(str(kb.text) == "Hallo Welt" and int(kb.caret) == 8, "Tippen fügt an der Schreibmarke ein")
	Nav._fire("x")
	check(str(kb.text) == "Hallo Wlt" and int(kb.caret) == 7, "X löscht vor der Schreibmarke")
	Nav._fire("y")
	check(str(kb.text) == "Hallo W lt", "Y: Leerzeichen an der Schreibmarke")
	Nav._fire("rb")
	Nav._fire("rb")
	Nav._fire("rb")
	Nav._fire("rb")
	check(int(kb.caret) == str(kb.text).length(), "RB: nach rechts, am Ende bleibt sie stehen")
	for i in 20:
		Nav._fire("lb")
	check(int(kb.caret) == 0, "LB am Anfang bleibt stehen")
	kb._backspace()
	check(str(kb.text) == "Hallo W lt", "Löschen am Anfang tut nichts")
	kb._delete_forward()
	check(str(kb.text) == "allo W lt" and int(kb.caret) == 0, "Entf löscht hinter der Schreibmarke")
	var by_label := func(l: String) -> Control:
		for c in Nav.focusables(kb):
			if str(c.get("label")) == l:
				return c
		return null
	Nav.focus(by_label.call("q"), true)
	Nav.move("left")
	check(Nav.focused() == by_label.call("ü"), "links am linken Rand → rechter Rand derselben Reihe")
	Nav.move("right")
	check(Nav.focused() == by_label.call("q"), "rechts am rechten Rand → linker Rand")
	Nav.move("right")
	check(Nav.focused() == by_label.call("w"), "mitten in der Reihe: ganz normal weiter")
	Nav.focus(by_label.call("Groß"), true)
	Nav.move("left")
	check(Nav.focused() == by_label.call("Fertig"), "untere Leiste: links am Rand → „Fertig“")
	Nav.move("right")
	check(Nav.focused() == by_label.call("Groß"), "und rechts wieder zurück")
	Nav.focus(by_label.call("1"), true)
	Nav.move("up")
	check(Nav.focused() == by_label.call("Groß"), "hoch aus der Zahlenreihe → untere Leiste")
	Nav.move("down")
	check(Nav.focused() == by_label.call("1"), "runter aus der Leiste → Zahlenreihe")
	kb.close()
	await get_tree().create_timer(0.3).timeout
	# Text snippets as their own keys (for example „.com“ for the browser).
	check(".com" in Keyboard.kuerzel_fuer("adresse") and "https://" in Keyboard.kuerzel_fuer("adresse"),
			"Textstücke für Adressen: „.com“ und „https://“ sind dabei")
	check("@" in Keyboard.kuerzel_fuer("email") and Keyboard.kuerzel_fuer("suche").is_empty(),
			"für E-Mail das @, für anderes keine")
	kb = Keyboard.new()
	kb.heading = "Adresse"
	kb.text = "uzai"
	kb.kuerzel = Keyboard.kuerzel_fuer("adresse")
	kb.open(host)
	for i in 3:
		await get_tree().process_frame
	by_label = func(l: String) -> Control:
		for c in Nav.focusables(kb):
			if str(c.get("label")) == l:
				return c
		return null
	var com: Control = by_label.call(".com")
	check(com != null, "die Tastatur zeigt die Textstücke als Tasten")
	if com != null:
		Nav.focus(com, true)
		Nav._fire("a")
		check(str(kb.text) == "uzai.com" and int(kb.caret) == 8, "A auf „.com“ fügt es an der Schreibmarke ein")
		Nav.focus(by_label.call("1"), true)
		Nav.move("up")
		check(Nav.focused() != null and Nav.focused().get_parent() == com.get_parent(), "hoch aus der Zahlenreihe → Textstücke")
		Nav.move("up")
		check(Nav.focused() == by_label.call("Groß"), "hoch aus den Textstücken → untere Leiste")
		Nav.move("down")
		check(Nav.focused() != null and Nav.focused().get_parent() == com.get_parent(), "runter aus der Leiste → Textstücke")
		Nav.move("down")
		check(Nav.focused() != null and Nav.focused().get_parent() == by_label.call("1").get_parent(), "und weiter runter → Zahlenreihe")
		Nav.focus(com, true)
		Nav.move("left")
		check(str(Nav.focused().get("label")) == "https://", "links am Rand der Textstücke → das letzte")
	kb.close()
	await get_tree().create_timer(0.3).timeout
	Nav.root_scope = keep_scope
	Nav.device = keep_device
	host.queue_free()


func _toasts() -> void:
	print("Mitteilungen")
	var before: int = Toasts.unread
	Toasts.show_toast("Test-Mitteilung", "Unterzeile", "info", { "ms": 200 })
	check(str(Toasts.history[0].title) == "Test-Mitteilung" and Toasts.unread == before + 1, "landet in der Liste und zählt als neu")
	var n: int = Toasts.history.size()
	Toasts.show_toast("Leise", "", "info", { "quiet": true, "ms": 200 })
	check(Toasts.history.size() == n, "leise Hinweise bleiben aus der Liste")
	for i in 70:
		Toasts.show_toast("Viele %d" % i, "", "info", { "ms": 100, "quiet": i % 2 == 1 })
	check(Toasts.history.size() <= 60, "Liste hält höchstens 60")

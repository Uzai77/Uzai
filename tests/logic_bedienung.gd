extends Node
## Bedienung mit Maus, Tastatur, Touch und auf Handhelds (Punkt 64): nachgestellte Godot-Ereignisse
## (Maus, Rad, Touch, Tasten, Controller) gegen eine kleine Oberfläche mit Reihe und Liste – Klick
## und Tippen lösen genau einmal aus, Ziehen und Wischen rollen (mit Schwung) ohne auszulösen,
## langes Tippen und Rechtsklick sind „Optionen“, Rand-Geste und Zurück-Knopf sind B, daneben
## Tippen trifft noch; Wechsel der Tastensymbole; Handheld-Erkennung mit Beispielwerten aus echten
## Geräten; Schnellmenü-Taste; Akku; Energieprofile; Treffer in einer Theme-Oberfläche.
## Aufruf: godot --headless --path . res://tests/logic_bedienung.tscn → „Ergebnis: alles ok“

const Handheld := preload("res://src/core/handheld.gd")
const DisplayFit := preload("res://src/core/display_fit.gd")
const HintBar := preload("res://src/ui/components/hint_bar.gd")
const TouchZurueck := preload("res://src/ui/components/touch_zurueck.gd")
const PcAkku := preload("res://src/ui/components/pc_akku.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")

var fails := 0
var ui: Control
var row: ScrollContainer
var list: ScrollContainer
var row_btn: Array = []
var list_btn: Array = []
var klein: Button
var presses := {}
var cmds: Array = []
var optionen := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_erkennung()
	_belegung()
	_akku()
	_leistung()
	Nav.command.connect(func(c: String) -> void: cmds.append(c))
	Nav.pad_unfocused = true
	await _bauen()
	await _tastatur()
	await _maus()
	await _touch()
	await _symbole()
	await _schnelltaste()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# --- Handhelds (nur Logik) --------------------------------------------------------------------

func _erkennung() -> void:
	print("Handheld erkennen (Beispielwerte echter Geräte)")
	var deck := Handheld.erkennen({ "maker": "Valve", "product": "Jupiter", "version": "1" })
	check(deck.get("id") == "deck" and is_equal_approx(float(deck.skala), 1.5) and deck.tasten == "deck", "Steam Deck (LCD): Valve „Jupiter“ → 150 %, Deck-Tasten")
	check(Handheld.erkennen({ "maker": "Valve", "product": "Galileo" }).get("id") == "deck", "Steam Deck OLED: „Galileo“")
	check(Handheld.erkennen({ "product": "Jupiter" }).is_empty(), "„Jupiter“ ohne Valve ist kein Deck")
	var ally := Handheld.erkennen({ "maker": "ASUSTeK COMPUTER INC.", "product": "ROG Ally RC71L_RC71L", "family": "ROG Ally" })
	check(ally.get("id") == "ally" and is_equal_approx(float(ally.skala), 1.5) and ally.tasten == "handheld", "ROG Ally → 150 %, Handheld-Tasten")
	check(Handheld.erkennen({ "maker": "ASUSTeK COMPUTER INC.", "product": "ROG Ally X RC72LA_RC72LA" }).get("id") == "ally", "ROG Ally X")
	var legion := Handheld.erkennen({ "maker": "LENOVO", "product": "83E1", "family": "Legion Go 8APU1", "version": "Legion Go 8APU1" })
	check(legion.get("id") == "legion" and is_equal_approx(float(legion.skala), 1.4), "Legion Go (Name in Familie/Version, 8,8″) → 140 %")
	check(Handheld.erkennen({ "maker": "Micro-Star International Co., Ltd.", "product": "Claw A1M" }).get("id") == "claw", "MSI Claw")
	check(Handheld.erkennen({ "maker": "Contoso", "product": "Claw Hammer 15" }).is_empty(), "„Claw“ ohne MSI ist keine Claw")
	check(Handheld.erkennen({ "maker": "AYANEO", "product": "AYANEO 2S" }).get("id") == "handheld", "andere Handhelds am Namen (AYANEO)")
	check(Handheld.erkennen({ "maker": "LENOVO", "product": "21CB", "family": "ThinkPad X1 Carbon Gen 10", "zoll": 14.0, "intern": true }).is_empty(),
			"Laptop 14″ ist kein Handheld")
	var seven := Handheld.erkennen({ "maker": "To be filled by O.E.M.", "product": "Default string", "zoll": 7.0, "intern": true })
	check(seven.get("id") == "handheld" and seven.grund == "bildschirm", "ohne Namen: eingebauter 7″-Bildschirm → Handheld")
	check(Handheld.erkennen({ "zoll": 7.0, "intern": false }).is_empty(), "7″ extern (kleiner Monitor) ist kein Handheld")
	check(Handheld.erkennen({ "model": "GenericDevice" }).is_empty(), "Godots Platzhalter-Name zählt nicht")
	check(Handheld._clean("ROG\u0007 Ally\n" + "x".repeat(100)).length() <= 64 and not Handheld._clean("ROG\u0007 Ally").contains("\u0007"),
			"BIOS-Texte: Steuerzeichen weg, gekürzt")
	# Über den Bildschirm von display-info (15,5 × 8,7 cm ≈ 7″, eingebaut) und den Weg beim Start.
	var seen := { "tech": "intern", "w_cm": 15, "h_cm": 9, "hz": 60.0 }
	DisplayFit.mark_handheld(seen, "")
	check(seen.get("handheld") == "handheld" and DisplayFit.kind_of(seen) == "handheld", "display_fit: 7″ eingebaut → Art „handheld“")
	var ss := { "maker": "Valve", "product": "Jupiter", "tech": "intern", "w_cm": 0, "h_cm": 0 }
	DisplayFit.mark_handheld(ss, "")
	check(ss.get("geraet") == "Steam Deck" and DisplayFit.summary(ss).begins_with("Steam Deck"), "Zusammenfassung nennt das Gerät")
	Config.set_value("theme.ui_scale", 1.0)
	check(DisplayFit.apply(ss, true) == "handheld" and is_equal_approx(UzTheme.ui_scale(), 1.5), "Automatisch einstellen: Deck → Oberfläche 150 %")
	Handheld.erkennen({})
	DisplayFit.mark_handheld({ "maker": "LENOVO", "family": "Legion Go 8APU1" }, "")
	check(DisplayFit.apply({ "handheld": "legion", "maker": "LENOVO", "family": "Legion Go 8APU1" }, false) == "handheld"
			and is_equal_approx(UzTheme.ui_scale(), 1.4), "Legion Go ohne gemeldete Größe → 140 %")
	Config.set_value("theme.ui_scale", 1.0)
	check(DisplayFit.kind_of({ "tech": "intern", "w_cm": 31, "h_cm": 17 }) == "laptop", "Laptop bleibt Laptop")
	# Tastensymbole der eingebauten Controller.
	check(Handheld.tasten_fuer(deck, "Steam Virtual Gamepad", 0x28DE) == "deck", "Deck: eingebauter Controller (Valve) → Deck-Symbole")
	check(Handheld.tasten_fuer(deck, "Xbox Wireless Controller", 0x045E) == "", "Deck: angesteckter Xbox-Controller behält Xbox-Symbole")
	check(Handheld.tasten_fuer(ally, "XInput Gamepad", -1) == "handheld", "Ally: XInput ohne Hersteller ist der eingebaute")
	check(Handheld.tasten_fuer(ally, "DualSense Wireless Controller", 0x054C) == "", "Ally: PlayStation-Controller bleibt PlayStation")
	check(Handheld.tasten_fuer({}, "XInput Gamepad", -1) == "", "kein Handheld: nichts Eigenes")
	Handheld.aktiv = {}


func _belegung() -> void:
	print("Schnellmenü-Taste")
	check(Handheld.belegung({ "art": "taste", "code": KEY_F15 }).get("code") == KEY_F15, "F15 belegbar")
	check(Handheld.belegung({ "art": "taste", "code": KEY_A }).is_empty(), "A (Tippen) nicht belegbar")
	check(Handheld.belegung({ "art": "taste", "code": KEY_ENTER, "mods": KEY_MASK_CTRL }).is_empty(), "Enter nie, auch mit Strg")
	check(not Handheld.belegung({ "art": "taste", "code": KEY_K, "mods": KEY_MASK_CTRL | KEY_MASK_ALT }).is_empty(), "Strg + Alt + K belegbar")
	check(Handheld.belegung({ "art": "taste", "code": KEY_F4, "mods": KEY_MASK_ALT }).is_empty(), "Alt + F4 nie")
	check(Handheld.belegung({ "art": "knopf", "code": JOY_BUTTON_PADDLE1 }).get("art") == "knopf", "Paddel 1 belegbar")
	check(Handheld.belegung({ "art": "knopf", "code": JOY_BUTTON_A }).is_empty() and Handheld.belegung({ "art": "knopf", "code": JOY_BUTTON_MISC1 }).is_empty(),
			"A und Teilen nie")
	check(Handheld.belegung("F15").is_empty() and Handheld.belegung({ "art": "x", "code": 1 }).is_empty()
			and Handheld.belegung({ "art": "taste", "code": "77" }).is_empty(), "kaputte Werte fallen weg")
	check(Handheld.belegung_text({}) == "Nicht belegt" and Handheld.belegung_text({ "art": "taste", "code": KEY_F15, "mods": 0 }) == "F15", "Namen der Belegung")


func _akku() -> void:
	print("Akku des PCs")
	var a := Handheld.parse_akku({ "ok": true, "akku": true, "prozent": 64, "laedt": false, "netz": false, "minuten": 95 })
	check(a.prozent == 64 and Handheld.akku_stufe(64) == 2 and Handheld.akku_text(a) == "64 %", "64 % → Stufe 2, „64 %“")
	check(Handheld.akku_text(a, true) == "64 % · noch 1 h 35 min", "lange Form mit Restzeit")
	check(Handheld.parse_akku({ "ok": true, "akku": true, "prozent": 999, "minuten": "x" }).prozent == 100, "Werte begrenzt")
	check(not bool(Handheld.parse_akku({ "ok": false, "akku": true }).akku), "ohne ok: kein Akku")
	check(Handheld.akku_stufe(-1) == -1 and Handheld.akku_stufe(8) == 0 and Handheld.akku_stufe(90) == 3, "Stufen")
	var am_netz := Handheld.parse_akku({ "ok": true, "akku": true, "prozent": 100, "netz": true })
	check(not PcAkku.zeigen(am_netz) and PcAkku.zeigen(a), "Laptop am Netz: oben nichts; im Akkubetrieb: Akku")
	Handheld.aktiv = { "id": "deck" }
	check(PcAkku.zeigen(am_netz), "Handheld: Akku immer oben")
	Handheld.aktiv = {}
	check(not PcAkku.zeigen(Handheld.parse_akku({ "ok": true, "akku": false, "prozent": 100 })), "ohne Akku (Desktop-PC): nichts")


func _leistung() -> void:
	print("Leistung über die Energieprofile")
	var plans := [{ "id": "381b4222-f694-41f0-9685-ff5bb260df2e" }, { "id": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" },
			{ "id": "a1841308-3541-4fab-bc81-f71556f20b4a" }]
	check(Handheld.naechstes_profil(plans, "a1841308-3541-4fab-bc81-f71556f20b4a") == "381b4222-f694-41f0-9685-ff5bb260df2e", "Energiesparen → Ausbalanciert")
	check(Handheld.naechstes_profil(plans, "381b4222-f694-41f0-9685-ff5bb260df2e") == "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "Ausbalanciert → Höchstleistung")
	check(Handheld.naechstes_profil(plans, "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") == "a1841308-3541-4fab-bc81-f71556f20b4a",
			"Höchstleistung → wieder Energiesparen")
	check(Handheld.naechstes_profil([plans[0]], plans[0].id) == "", "nur ein Profil: nichts umzuschalten")
	GuideQuick.plaene = { "can_set": true, "plans": plans, "active": plans[0].id }
	check(not GuideQuick.ids({ "leistung": GuideQuick.leistung_da() }).has("leistung"), "am Desktop-PC kein „Leistung“ im Schnellmenü")
	Handheld.aktiv = { "id": "ally" }
	check(GuideQuick.ids({ "leistung": GuideQuick.leistung_da() }).has("leistung"), "auf dem Handheld „Leistung“ im Schnellmenü")
	Handheld.aktiv = {}
	GuideQuick.plaene = {}


# --- Oberfläche zum Bedienen ------------------------------------------------------------------

func _btn(name: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = name
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_ALL
	presses[name] = 0
	b.pressed.connect(func() -> void: presses[name] = int(presses[name]) + 1)
	return b


func _bauen() -> void:
	ui = Control.new()
	ui.size = Vector2(1920, 1080)
	add_child(ui)
	row = ScrollContainer.new()
	row.position = Vector2(100, 100)
	row.size = Vector2(800, 200)
	row.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	row.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(row)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	row.add_child(hb)
	for i in 10:
		var b := _btn("r%d" % i, Vector2(200, 150))
		hb.add_child(b)
		row_btn.append(b)
	row_btn[0].set_meta("uz_hint_y", "Optionen")
	row_btn[0].set_meta("uz_on_y", func() -> void: optionen += 1)
	list = ScrollContainer.new()
	list.position = Vector2(1100, 100)
	list.size = Vector2(400, 300)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(list)
	var vb := VBoxContainer.new()
	list.add_child(vb)
	for i in 12:
		var b := _btn("l%d" % i, Vector2(380, 80))
		vb.add_child(b)
		list_btn.append(b)
	klein = _btn("klein", Vector2(40, 40))
	klein.position = Vector2(1300, 700)
	ui.add_child(klein)
	Nav.root_scope = ui
	for i in 3:
		await get_tree().process_frame


func _maus_knopf(btn: int, down: bool, pos: Vector2, dev := 0) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = pos
	e.global_position = pos
	e.device = dev
	if btn in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		e.factor = 1.0
	get_viewport().push_input(e, true)


func _maus_weg(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	get_viewport().push_input(e, true)


func _klick(pos: Vector2) -> void:
	_maus_knopf(MOUSE_BUTTON_LEFT, true, pos)
	_maus_knopf(MOUSE_BUTTON_LEFT, false, pos)


func _finger(idx: int, down: bool, pos: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.pressed = down
	t.position = pos
	get_viewport().push_input(t, true)


func _wisch(idx: int, pos: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	get_viewport().push_input(d, true)


func _taste(kc: Key, shift := false, ctrl := false) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = kc
		k.physical_keycode = kc
		k.pressed = down
		k.shift_pressed = shift
		k.ctrl_pressed = ctrl
		get_viewport().push_input(k, true)


func _warte(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _mitte(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _summe() -> int:
	var n := 0
	for k in presses.keys():
		n += int(presses[k])
	return n


func _zuruecksetzen() -> void:
	for k in presses.keys():
		presses[k] = 0
	cmds.clear()
	optionen = 0


# --- Tastatur ----------------------------------------------------------------------------------

func _tastatur() -> void:
	print("Tastatur")
	Nav.focus(row_btn[0], true)
	_taste(KEY_TAB)
	check(Nav.focused() == row_btn[1], "Tab: nächstes Element in der Zeile")
	_taste(KEY_TAB, true)
	check(Nav.focused() == row_btn[0], "Umschalt + Tab: zurück")
	Nav.focus(list_btn[0], true)
	_taste(KEY_TAB)
	check(Nav.focused() == list_btn[1], "Tab in der Liste: darunter")
	var order := Nav.reading_order([list_btn[0], row_btn[1], row_btn[0], klein])
	check(order[0] == row_btn[0] and order[1] == row_btn[1] and order[order.size() - 1] == klein,
			"Lesereihenfolge: Zeilen oben nach unten, darin links nach rechts")
	cmds.clear()
	_taste(KEY_TAB, false, true)
	_taste(KEY_TAB, true, true)
	check(cmds == ["rt", "lt"], "Strg + Tab wechselt den Bereich (%s)" % str(cmds))
	_taste(KEY_ESCAPE)
	check(cmds.back() == "b", "Esc ist Zurück")
	Nav.focus(row_btn[0], true)
	_taste(KEY_MENU)
	check(optionen == 1, "Kontextmenü-Taste: Optionen (was unten bei Y steht)")
	_taste(KEY_F10, true)
	check(optionen == 2, "Umschalt + F10: Optionen")
	_taste(KEY_RIGHT)
	check(Nav.focused() == row_btn[1], "Pfeil rechts: Fokus wie mit dem Steuerkreuz")
	await _warte(0.1)
	_zuruecksetzen()


# --- Maus -------------------------------------------------------------------------------------

func _maus() -> void:
	print("Maus")
	Nav.focus(klein, true)
	_klick(_mitte(klein))
	check(int(presses.klein) == 1, "Klick außerhalb rollender Flächen: kommt sofort, genau einmal")
	row.scroll_horizontal = 0
	await get_tree().process_frame
	var p0 := _mitte(row_btn[1])
	_klick(p0)
	check(int(presses.r1) == 1 and _summe() == 2, "Klick in einer Reihe: kommt nach dem Loslassen, genau einmal")
	_zuruecksetzen()
	# Ziehen: rollt, löst nichts aus.
	_maus_knopf(MOUSE_BUTTON_LEFT, true, p0)
	for i in 10:
		_maus_weg(p0 - Vector2(20 * (i + 1), 0), Vector2(-20, 0))
	_maus_knopf(MOUSE_BUTTON_LEFT, false, p0 - Vector2(200, 0))
	await get_tree().process_frame
	# Ab der Schwelle (hier nach dem ersten Schritt von 20 px) folgt die Reihe 1:1, ohne Sprung.
	check(absi(row.scroll_horizontal - 180) <= 2 and _summe() == 0, "Ziehen in der Reihe: rollt 1:1 ab der Schwelle (%d px), kein Klick" % row.scroll_horizontal)
	# Rechtsklick: erst wählen, dann Optionen.
	row.scroll_horizontal = 0
	await get_tree().process_frame
	Nav.focus(klein, true)
	_maus_knopf(MOUSE_BUTTON_RIGHT, true, _mitte(row_btn[0]))
	_maus_knopf(MOUSE_BUTTON_RIGHT, false, _mitte(row_btn[0]))
	check(Nav.focused() == row_btn[0] and optionen == 1, "Rechtsklick: wählt das Element und öffnet Optionen")
	# Maustaste „Zurück“.
	cmds.clear()
	_maus_knopf(MOUSE_BUTTON_XBUTTON1, true, Vector2(10, 10))
	_maus_knopf(MOUSE_BUTTON_XBUTTON1, false, Vector2(10, 10))
	check(cmds == ["b"], "Maustaste Zurück ist B")
	# Mausrad: senkrecht über einer Reihe ohne Seite drumherum rollt die Reihe (weich).
	_maus_knopf(MOUSE_BUTTON_WHEEL_DOWN, true, _mitte(row_btn[1]))
	_maus_knopf(MOUSE_BUTTON_WHEEL_DOWN, true, _mitte(row_btn[1]))
	await get_tree().process_frame
	var mid := row.scroll_horizontal
	await _warte(0.5)
	check(mid < 240 and absi(row.scroll_horizontal - 240) <= 2, "Mausrad in der Reihe: waagerecht, weich (%d → %d)" % [mid, row.scroll_horizontal])
	_maus_knopf(MOUSE_BUTTON_WHEEL_DOWN, true, _mitte(list_btn[0]))
	await _warte(0.5)
	check(list.scroll_vertical == 120, "Mausrad in der Liste: senkrecht (%d)" % list.scroll_vertical)
	# Nachgebildete Maus aus Touch zählt nicht doppelt.
	_zuruecksetzen()
	_maus_knopf(MOUSE_BUTTON_LEFT, true, _mitte(klein), InputEvent.DEVICE_ID_EMULATION)
	_maus_knopf(MOUSE_BUTTON_LEFT, false, _mitte(klein), InputEvent.DEVICE_ID_EMULATION)
	check(_summe() == 0, "von Godot nachgebildete Maus (aus Touch) fällt weg")
	# Hinweise sind klickbar.
	var hb := HintBar.new()
	hb.position = Vector2(400, 950)
	ui.add_child(hb)
	Nav.focus(klein, true)
	hb.refresh(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var a_hint: Control = null
	for ch in hb.get_children():
		if str(ch.get_meta("uz_hint_key", "")) == "a":
			a_hint = ch
	_zuruecksetzen()
	if a_hint:
		_klick(_mitte(a_hint))
	check(a_hint != null and int(presses.klein) == 1, "Klick auf den Hinweis „A“ löst A aus")
	hb.queue_free()
	row.scroll_horizontal = 0
	list.scroll_vertical = 0
	await _warte(0.1)
	_zuruecksetzen()


# --- Touch -------------------------------------------------------------------------------------

func _touch() -> void:
	print("Touch")
	Nav.focus(klein, true)
	_finger(0, true, _mitte(row_btn[2]))
	_finger(0, false, _mitte(row_btn[2]))
	check(Nav.device == "touch", "Touch erkannt")
	check(int(presses.r2) == 1 and _summe() == 1 and Nav.focused() == row_btn[2], "Tippen: wählt und löst sofort aus (wie A), genau einmal")
	_zuruecksetzen()
	_finger(0, true, _mitte(klein) + Vector2(-38, 0))
	_finger(0, false, _mitte(klein) + Vector2(-38, 0))
	check(int(presses.klein) == 1, "knapp daneben getippt: trifft trotzdem (größere Trefferfläche)")
	_finger(0, true, Vector2(1700, 900))
	_finger(0, false, Vector2(1700, 900))
	check(_summe() == 1, "weit daneben: nichts")
	# Wischen mit Schwung.
	_zuruecksetzen()
	row.scroll_horizontal = 0
	await get_tree().process_frame
	var p := _mitte(row_btn[2])
	_finger(0, true, p)
	for i in 8:
		await _warte(0.016)
		p -= Vector2(40, 0)
		_wisch(0, p, Vector2(-40, 0))
	var at_release := row.scroll_horizontal
	_finger(0, false, p)
	await _warte(0.35)
	check(at_release >= 260 and row.scroll_horizontal > at_release + 60 and _summe() == 0,
			"Wischen: rollt mit dem Finger und gleitet nach (%d → %d), kein Tippen" % [at_release, row.scroll_horizontal])
	await _warte(1.2)
	var still := row.scroll_horizontal
	await _warte(0.2)
	check(still == row.scroll_horizontal, "der Schwung läuft aus")
	# Senkrecht in der Liste.
	var q := _mitte(list_btn[2])
	_finger(1, true, q)
	for i in 5:
		await _warte(0.02)
		q -= Vector2(0, 20)
		_wisch(1, q, Vector2(0, -20))
	await _warte(0.08)
	_finger(1, false, q)
	check(list.scroll_vertical >= 80 and _summe() == 0, "Wischen in der Liste: senkrecht (%d px)" % list.scroll_vertical)
	# Langes Tippen: Optionen, beim Loslassen nichts.
	row.scroll_horizontal = 0
	await get_tree().process_frame
	_zuruecksetzen()
	_finger(0, true, _mitte(row_btn[0]))
	await _warte(0.7)
	_finger(0, false, _mitte(row_btn[0]))
	check(optionen == 1 and _summe() == 0, "langes Tippen: Optionen, kein Auslösen")
	# Zurück-Geste vom linken Rand.
	cmds.clear()
	_finger(0, true, Vector2(8, 600))
	for i in 6:
		_wisch(0, Vector2(8 + 25 * (i + 1), 604), Vector2(25, 0))
	_finger(0, false, Vector2(158, 604))
	check(cmds == ["b"], "vom linken Rand nach rechts wischen: Zurück")
	# Zurück-Knopf: nur mit Touch und nur, wenn B etwas tut.
	var tz := TouchZurueck.new()
	ui.add_child(tz)
	var ebene := Control.new()
	ebene.size = Vector2(300, 300)
	ebene.position = Vector2(1500, 300)
	var eb := _btn("eb", Vector2(200, 60))
	ebene.add_child(eb)
	ui.add_child(ebene)
	await get_tree().process_frame
	Nav.push_layer(ebene)
	await _warte(0.4)
	check(tz.visible and tz.modulate.a > 0.9, "Ebene offen, Touch: Zurück-Knopf erscheint")
	cmds.clear()
	_finger(0, true, _mitte(tz))
	_finger(0, false, _mitte(tz))
	check(cmds == ["b"], "Zurück-Knopf: B")
	Nav.pop_layer(ebene)
	ebene.queue_free()
	_taste(KEY_DOWN)
	await _warte(0.4)
	check(not tz.visible, "mit der Tastatur: kein Zurück-Knopf")
	tz.queue_free()
	await get_tree().process_frame
	_zuruecksetzen()


# --- Tastensymbole -----------------------------------------------------------------------------

func _symbole() -> void:
	print("Tastensymbole wechseln mit dem Gerät")
	Config.set_value("controller.glyphs", "auto")
	var changes := [0]
	var cb := func(_k: String) -> void: changes[0] += 1
	Nav.device_changed.connect(cb)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_LEFT_STICK
	jb.pressed = true
	jb.device = 0
	get_viewport().push_input(jb, true)
	jb = jb.duplicate()
	jb.pressed = false
	get_viewport().push_input(jb, true)
	check(Nav.device == "pad" and Nav.glyph_set() == "xbox", "Controller: Xbox-Symbole (%s)" % Nav.glyph_set())
	_taste(KEY_DOWN)
	check(Nav.device == "keys" and Nav.glyph_set() == "keys", "Taste gedrückt: Tastatur-Symbole")
	get_viewport().push_input(jb.duplicate(), true)
	check(Nav.device == "pad", "zurück zum Controller")
	_maus_weg(Vector2(500, 500), Vector2(1.5, 0))
	check(Nav.device == "pad", "Schein-Bewegung der Maus (Windows) wechselt nichts")
	for i in 4:
		_maus_weg(Vector2(500 + i * 15, 500), Vector2(15, 0))
	check(Nav.device == "mouse" and Nav.glyph_set() == "keys", "echte Mausbewegung: Tastatur-Symbole")
	check(changes[0] >= 4, "jeder Wechsel meldet sich (Symbole zeichnen neu)")
	Handheld.aktiv = Handheld.erkennen({ "maker": "ASUSTeK COMPUTER INC.", "product": "ROG Ally RC71L_RC71L" })
	get_viewport().push_input(jb.duplicate(), true)
	check(Nav.glyph_set() == "handheld", "Ally, eingebauter Controller: Handheld-Symbole")
	Handheld.aktiv = Handheld.erkennen({ "maker": "Valve", "product": "Jupiter" })
	Nav.pad_name = "Steam Virtual Gamepad"
	Nav.pad_vid = 0x28DE
	check(Nav.glyph_set() == "deck", "Steam Deck: Deck-Symbole (L1/R1)")
	Config.set_value("controller.glyphs", "ps")
	check(Nav.glyph_set() == "ps", "fest gewählt gilt immer")
	Config.set_value("controller.glyphs", "auto")
	Handheld.aktiv = {}
	Nav.device_changed.disconnect(cb)


# --- Schnellmenü-Taste ---------------------------------------------------------------------------

func _schnelltaste() -> void:
	print("Schnellmenü-Taste und Belegen")
	cmds.clear()
	_taste(KEY_F15)
	check(not cmds.has("quick"), "F15 am normalen PC: nichts")
	Handheld.aktiv = { "id": "claw", "name": "MSI Claw" }
	_taste(KEY_F15)
	check(cmds.has("quick"), "F15 auf dem Handheld: Schnellmenü")
	Handheld.aktiv = {}
	var got := []
	Nav.lernen(func(b: Dictionary, grund: String) -> void: got.append([b, grund]))
	_taste(KEY_A)
	check(got.size() == 1 and got[0][1] == "belegt", "Belegen: A wird abgelehnt (braucht das Tippen)")
	Nav.lernen(func(b: Dictionary, grund: String) -> void: got.append([b, grund]))
	_taste(KEY_F9)
	check(got.size() == 2 and got[1][1] == "" and int(got[1][0].code) == KEY_F9, "Belegen: F9 angenommen")
	Config.set_value("controller.quick_key", got[1][0])
	cmds.clear()
	_taste(KEY_F9)
	check(cmds.has("quick"), "belegte Taste öffnet das Schnellmenü")
	Nav.lernen(func(b: Dictionary, grund: String) -> void: got.append([b, grund]))
	_taste(KEY_ESCAPE)
	check(got.size() == 3 and got[2][1] == "abbruch", "Esc bricht das Belegen ab")
	Config.set_value("controller.quick_key", {})



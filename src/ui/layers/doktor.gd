extends "res://src/ui/layers/layer.gd"
## Uzai-Doktor (Punkt 133): alle bekannten Probleme dieses PCs als Karten – Controller, Launcher,
## Emulatoren, Spieleordner, Speicher, Helfer, Anmeldungen, Uhrzeit, Netz. Jede Karte sagt
## klar, was los ist; A („Beheben“) geht den sicheren Weg in Uzai (koppeln, suchen, neu wählen,
## neu anmelden, aufräumen, WLAN-Liste, Bluetooth einschalten). Was Uzai nicht selbst darf – Uhr
## stellen, Netzwerkeinstellungen, Virenscanner –, erklärt „So geht's“ nur. Y zeigt bei jeder Karte die Schritte zum
## Selbermachen, X prüft neu. Darunter, was geprüft und in Ordnung ist, und „Erste Hilfe“.
## Erreichbar über Einstellungen → System und im Guide (System). Regeln: src/core/doktor.gd,
## gesammelt in src/core/doktor_lage.gd.

const Arbeit := preload("res://src/core/arbeit.gd")
const Doktor := preload("res://src/core/doktor.gd")
const EmuSucheS := preload("res://src/core/emu_suche.gd")
const Lage := preload("res://src/core/doktor_lage.gd")
const E := preload("res://src/core/einrichtung.gd")
const PadPair := preload("res://src/ui/layers/pad_pair.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const WinEinst := preload("res://src/core/win_einst.gd")
const Liste := preload("res://src/ui/components/liste.gd")
const SELF := "res://src/ui/layers/doktor.gd"
const COLS := 2
## Schmaler wird eine Karte nicht (große Oberfläche): dann eine Spalte, sonst endeten Titel mit „…“.
const CARD_MIN_W := 600.0
const GAP := 28.0
const CARD_H := 214.0
## Die einzige Anfrage des Doktors ins Netz (nur beim Öffnen, höchstens alle fünf Minuten): Steams
## öffentliche Server-Zeit. Sie zeigt, ob das Netz da ist, und über die Kopfzeile „Date“, ob die
## Uhr stimmt (Net._note). Nichts Persönliches geht mit.
const NET_PROBE := "https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/"
const NET_FRESH_MS := 300000

const Main := preload("res://src/main.gd")
var main: Main
var _facts := {}
var _cards: Array = []
var _state := {}                  ## Karte → "läuft" | "ok" | "nein" (während bzw. nach „Beheben“)
var _note := {}                   ## Karte → Satz zum Ergebnis
var _status: _Status
var _sub_l: Label
var _grid: GridContainer
var _ok_box: HFlowContainer
var _ok_head: Control
var _sc: ScrollContainer
var _sig := ""
var _busy := false
var _fix_over := {}               ## Karte → anderer Weg nach einem Fehlschlag (Emulator nicht gefunden)


static func open_for(m: Main) -> Control:
	var l = load(SELF).new()
	l.main = m
	m.open_layer(l)
	return l


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	# Ganz deckend: Durch eine fast deckende Fläche schimmerten Texte der Startseite in den Karten.
	var bg := ColorRect.new()
	bg.color = UzTheme.col("bg")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(bg)
	add_child(bg)
	var root := U.margin(96, 64, 96, 110)
	U.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var col := U.vbox(30)
	root.add_child(col)
	var head := U.hbox(26)
	col.add_child(head)
	_status = _Status.new()
	head.add_child(_status)
	var hv := U.vbox(4)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(U.label("Uzai-Doktor", "xl", "text", "title"))
	_sub_l = U.label("", "m", "muted", "regular", true)
	_sub_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # in _refresh von Hand übersetzt
	hv.add_child(_sub_l)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = true
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_sc)
	# Rand für Glimmen und Wachsen der gewählten Karte.
	var pad := U.margin(14, 14, 14, 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(pad)
	var page := U.vbox(0)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(page)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid)
	_ok_head = U.margin(4, 38, 0, 14)
	_ok_head.add_child(Liste.abschnitt("Geprüft und in Ordnung") if UzTheme.strict() else U.label("Geprüft und in Ordnung", "s", "muted", "bold"))
	page.add_child(_ok_head)
	_ok_box = HFlowContainer.new()
	_ok_box.add_theme_constant_override("h_separation", 12)
	_ok_box.add_theme_constant_override("v_separation", 12)
	_ok_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_ok_box)
	page.add_child(U.spacer(0, 34, false))
	var more := _Card.new()
	page.add_child(more)
	var aid = SettingRow.new()
	aid.setup("action", "Erste Hilfe", "")
	aid.subtitle = "Die zehn häufigsten Probleme mit kurzen Schritten"
	aid.icon_name = "info"
	aid.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
	aid.set_meta("uz_key", "dk:erste_hilfe")
	aid.on_activate = func() -> void: go_settings(main, "system/Erste Hilfe")
	more.rows.add_child(aid)
	var hint = SettingRow.new()
	hint.setup("toggle", "Hinweis bei Problemen", "", bool(Config.get_value("system.doktor_hint", true)))
	hint.subtitle = "Ein kurzer Hinweis auf der Startseite und ein Punkt im Guide, wenn etwas Wichtiges nicht geht"
	hint.icon_name = "bell"
	hint.focus_radius = aid.focus_radius
	hint.set_meta("uz_key", "dk:hinweis")
	hint.changed.connect(func(v: Variant) -> void: Config.set_value("system.doktor_hint", bool(v)))
	more.rows.add_child(hint)
	set_meta("uz_hints", [["x", "Erneut prüfen"], ["y", "Mehr dazu"]])
	set_meta("uz_hint_b", "Zurück")
	_refresh()
	_probe_net()
	_probe_windows()


## WLAN und Bluetooth beim Helfer nachlesen (nur lesen, ohne WLAN-Suche) und dann neu zeigen.
func _probe_windows(force := false) -> void:
	await WinEinst.refresh_lage(force)
	if is_inside_tree():
		_refresh()


func _first_focus() -> Control:
	return Nav.default_in(_grid) if is_instance_valid(_grid) and _grid.get_child_count() > 0 else Nav.default_in(self)


func handle(cmd: String) -> bool:
	match cmd:
		"x":
			Sfx.play("select")
			_state.clear()
			_note.clear()
			_refresh(true)
			_probe_net(true)
			_probe_windows(true)
			return true
		"y":
			var f := Nav.focused()
			if f is _ProblemCard:
				_explain((f as _ProblemCard).data)
				return true
	return false


# --- Lage und Karten -------------------------------------------------------------------------

func _refresh(pulse := false) -> void:
	if not is_inside_tree():
		return
	_facts = Lage.gather()
	_cards = Doktor.cards(_facts)
	var sm := Doktor.summary(_cards)
	var oks := Doktor.ok_checks(_facts, _cards)
	_status.set_state("wichtig" if int(sm.wichtig) > 0 else ("hinweis" if int(sm.hinweis) > 0 else "ok"), pulse)
	var n_checked := oks.size() + _checked_bad()
	_sub_l.text = "%s · %s" % [tr(str(sm.text)), tr("%d Dinge geprüft") % n_checked] if not _cards.is_empty() else tr(
			"Alles in Ordnung – Uzai hat %d Dinge geprüft.") % n_checked
	var sig := JSON.stringify([_cards, _state, _note, oks])
	if sig == _sig:
		return
	_sig = sig
	var keep := ""
	var f := Nav.focused()
	if f and is_ancestor_of(f):
		keep = str(f.get_meta("uz_key", ""))
	U.clear(_grid)
	var cols := COLS
	var w := (U.view_size().x - 96.0 * 2.0 - 28.0 - GAP * (cols - 1)) / cols
	if w < CARD_MIN_W:
		cols = 1
		w = U.view_size().x - 96.0 * 2.0 - 28.0
	_grid.columns = cols
	var i := 0
	for c in _cards:
		var card := _ProblemCard.new()
		card.data = c
		card.state = str(_state.get(str(c.id), ""))
		card.note = str(_note.get(str(c.id), ""))
		card.custom_minimum_size = Vector2(w, CARD_H)
		card.set_meta("uz_key", "dk:" + str(c.id))
		card.set_meta("uz_hint_a", str(c.fix_label) if bool(c.self) and str(c.fix) != "" else "So geht's")
		card.activated.connect(func() -> void: _fix(c))
		_grid.add_child(card)
		card.build()
		# Karten erscheinen nacheinander (nicht bei jeder Auffrischung).
		if _state.is_empty() and not pulse:
			card.modulate.a = 0.0
			card.create_tween().tween_property(card, "modulate:a", 1.0, U.T_ENTER).set_delay(0.04 * i)
		i += 1
	U.clear(_ok_box)
	for o in oks:
		_ok_box.add_child(_chip(str(o)))
	_ok_head.visible = not oks.is_empty()
	if Nav.top_layer() == self:
		var target: Control = null
		if keep != "":
			for c2 in Nav.focusables(self):
				if str(c2.get_meta("uz_key", "")) == keep:
					target = c2
		if target == null:
			target = _first_focus()
		if target:
			Nav.focus(target, true)


## Wie viele Prüfungen eine Karte haben (für „… Dinge geprüft“).
func _checked_bad() -> int:
	var seen := {}
	for c in _cards:
		seen[str(c.check)] = true
	return seen.size()


func _chip(text: String) -> Control:
	var p := PanelContainer.new()
	# Eckig (Marke): nur Haken und Wort, keine Pille darum.
	var sb := UzTheme.box(UzTheme.col("text", 0.0 if UzTheme.strict() else 0.06), 999)
	sb.content_margin_left = 16
	sb.content_margin_right = 20
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(9)
	p.add_child(h)
	var ic := U.icon("check", 20, "ok")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(U.label(text, "s", "text", "medium"))
	return p


## Läufe von _probe_net, die gerade unterwegs sind (siehe dort).
var _probe_net_offen := 0


## Netz und Uhr einmal nachfragen (siehe NET_PROBE) – nie in der Vorführung.
func _probe_net(force := false) -> void:
	_probe_net_offen += 1
	await _probe_net_lauf(force)
	_probe_net_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _probe_net täte bis zum Neustart nichts mehr.
	if _probe_net_offen == 0 and _busy:
		_busy = false


func _probe_net_lauf(force := false) -> void:
	if Library.demo or _busy:
		return
	if not force and Net.last_ok_ms > 0 and Time.get_ticks_msec() - Net.last_ok_ms < NET_FRESH_MS:
		return
	_busy = true
	await Net.request(NET_PROBE, PackedStringArray(), HTTPClient.METHOD_GET, "", 8.0)
	_busy = false
	if is_inside_tree():
		_refresh()


# --- Beheben ---------------------------------------------------------------------------------

func _fix(c: Dictionary) -> void:
	var id := str(c.id)
	var fix := str(_fix_over.get(id, c.fix))
	if str(_state.get(id, "")) == "läuft":
		return
	if not bool(c.self) or fix == "":
		_explain(c)
		return
	if fix.begins_with("emu_seite:"):
		go_emulator(main, fix.trim_prefix("emu_seite:"))
	elif fix.begins_with("retro:"):
		_retro(fix.trim_prefix("retro:"))
	elif fix.begins_with("emu:"):
		_find_emu(id, fix.trim_prefix("emu:"))
	elif fix.begins_with("ordner:"):
		_pick_dir(id, fix.trim_prefix("ordner:"))
	elif fix.begins_with("konto:"):
		_login(fix.trim_prefix("konto:"))
	elif fix.begins_with("seite:"):
		go_settings(main, fix.trim_prefix("seite:"))
	else:
		match fix:
			"koppeln":
				PadPair.open_for(main)
			"pad_help":
				load("res://src/ui/layers/pad_help.gd").open_for(main)
			"launcher":
				_launcher()
			"speicher":
				if Library.demo:
					_done(id, "Zwischenspeicher geleert – 10,6 GB frei.", "speicher")
				else:
					go_settings(main, "system/Speicher")
			"helfer":
				_mark(id, "läuft", "Startet neu …")
				Helper.retry()
				for i in 20:
					await get_tree().create_timer(1.0).timeout
					if not is_inside_tree():
						return
					if Helper.state() == "ok":
						break
				_mark(id, "ok" if Helper.state() == "ok" else "nein", "Läuft wieder." if Helper.state() == "ok"
						else "Startet weiterhin nicht – „Mehr dazu“ zeigt, woran es liegen kann.")
			"suche":
				Library.scan(true)
				Toasts.show_toast("Bibliothek wird neu eingelesen", "Neue Spiele erscheinen von selbst.", "refresh")
				_mark(id, "läuft", "Liest ein …")
			"absturz":
				main.open_crash_report()
			"wlan":
				var w = load("res://src/ui/layers/win_wlan.gd").open_for(main)
				w.closed.connect(func() -> void:
					if is_inside_tree():
						_probe_windows(true))
			"bt_an":
				_bt_on(id)


## „Bluetooth ist aus – einschalten?“: der Druck auf „Einschalten“ ist der ausdrückliche Wunsch.
func _bt_on(id: String) -> void:
	_mark(id, "läuft", "Schaltet ein …")
	if Library.demo:
		await get_tree().create_timer(0.8).timeout
		if is_inside_tree():
			Lage.demo_extra.erase("bt")
			_done(id, "Bluetooth ist an.")
		return
	var code := WinEinst.code_of(await Helper.run("radio-set", WinEinst.radio_args("bt", true), 12.0))
	if not is_inside_tree():
		return
	if code == "ok":
		await WinEinst.refresh_lage(true)
		if is_inside_tree():
			_done(id, "Bluetooth ist an.")
	else:
		_mark(id, "nein", str(WinEinst.status(code)[1]))


## Karte zeigt einen Zwischenstand oder ein Ergebnis.
func _mark(id: String, st: String, note: String) -> void:
	_state[id] = st
	_note[id] = note
	_refresh()


## Erledigt: kurz „Behoben“ zeigen, dann neu prüfen (die Karte verschwindet dann).
func _done(id: String, note: String, demo_key := "") -> void:
	_mark(id, "ok", note)
	Sfx.play("toggle_on")
	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree():
		return
	if Library.demo and demo_key != "":
		Lage.demo_fixed[demo_key] = true
	_state.erase(id)
	_note.erase(id)
	_refresh(true)


## Was Uzai nicht selbst tut: die Schritte als Dialog, dazu „Erneut prüfen“.
func _explain(c: Dictionary) -> void:
	var how: Array = c.get("how", [])
	var lines := PackedStringArray([tr(str(c.text))])
	if not how.is_empty():
		lines.append("")
	for i in how.size():
		lines.append("%d.  %s" % [i + 1, tr(str(how[i]))])
	var buttons: Array = []
	if bool(c.self) and str(c.fix) != "":
		buttons.append([str(c.fix_label), func() -> void: _fix(c)])
	buttons.append(["Erneut prüfen", func() -> void:
		_probe_net(true)
		_refresh(true)])
	buttons.append(["Schließen", func() -> void: pass])
	main.open_dialog(str(c.title), "\n".join(lines), buttons, str(c.icon), "warn" if str(c.sev) == "wichtig" else "")


## Emulator an den üblichen Orten suchen (nur lesen, im Hintergrund) und eintragen. Findet Uzai
## nichts und kann es ihn von der offiziellen Quelle einrichten, geht es dort weiter (mit Zustimmung).
func _find_emu(id: String, eid: String) -> void:
	var offer := ""
	for e in _facts.get("emus_missing", []):
		if str(e.get("id", "")) == eid:
			offer = str(e.get("angebot", ""))
	_mark(id, "läuft", "Sucht an den üblichen Orten …")
	if Library.demo:
		await get_tree().create_timer(1.4).timeout
		if not is_inside_tree():
			return
		if offer != "":
			_fix_over[id] = "retro:" + offer
			_mark(id, "nein", "Nicht auf diesem PC – A zeigt die offizielle Quelle.")
			_retro(offer)
		else:
			_done(id, "Gefunden: C:\\Emulatoren\\Dolphin\\Dolphin.exe", "emu:" + eid)
		return
	var e := Config.emulator(eid)
	var sw: GDScript = load("res://src/ui/layers/setup_wizard.gd")
	var env: Dictionary = sw.search_env()
	var drives: Array = sw._drives()
	var libs: Array = SteamScanner.library_dirs(Library.steam_root()) if Library.steam_root() != "" else []
	var hints: Dictionary = await sw.emu_hints(self)
	if not is_inside_tree():
		return
	var emu := { "id": eid, "name": str(e.get("name", eid)), "exe_hint": str(e.get("exe_hint", "")) }
	var fund: Variant = await Arbeit.ergebnis(_emu_finden.bind(emu, drives, env, libs, hints), Arbeit.LANG)
	if not is_inside_tree():
		return
	var exe: String = fund if fund is String else ""
	if exe != "":
		Config.set_emulator(eid, "exe", exe)
		Library.scan()
		_done(id, "Gefunden: %s" % (exe.replace("/", "\\") if Config.is_windows() else exe))
	elif offer != "":
		_fix_over[id] = "retro:" + offer
		_mark(id, "nein", "Nicht auf diesem PC – A zeigt die offizielle Quelle.")
		_retro(offer)
	else:
		_fix_over[id] = "emu_seite:" + eid
		_mark(id, "nein", "Nicht gefunden. A öffnet den Emulator – dort die Programmdatei wählen.")


## Programmdatei eines Emulators suchen (im Hintergrund): erst die üblichen Plätze, dann Startmenü,
## Registry, laufende Programme und eigene Ordner (begrenzt). "" wenn nichts da ist.
static func _emu_finden(emu: Dictionary, drives: Array, env: Dictionary, libs: Array, hints: Dictionary) -> String:
	var roots: Array = E.emu_roots(drives, env).filter(func(p: Variant) -> bool: return DirAccess.dir_exists_absolute(str(p)))
	for p: Variant in E.emu_candidates(emu, roots, libs):
		if FileAccess.file_exists(str(p)):
			return str(p)
	var id := str(emu.id)
	var more: Dictionary = EmuSucheS.find([emu], E.ALT_EXE, drives, env, libs, hints)
	return str(more[id].exe) if more.has(id) else ""


## Retro einrichten (src/ui/layers/retro_einrichten.gd) mit der Karte dieses Emulators; danach neu prüfen.
func _retro(eid: String) -> void:
	var l: Control = load("res://src/ui/layers/retro_einrichten.gd").open_for(main, {}, [], eid)
	l.closed.connect(func() -> void:
		if is_inside_tree():
			_fix_over.clear()
			_state.clear()
			_note.clear()
			_refresh(true))


## Spieleordner neu wählen (Uzais eigene Dateiauswahl, nie ein Windows-Dialog).
func _pick_dir(id: String, sys: String) -> void:
	var name := str(Config.system(sys).get("name", sys))
	main.open_file_browser(tr("Neuer Ordner für %s") % name, true, func(p: String) -> void:
		Config.set_rom_dir(sys, p)
		Config.set_system(sys, "enabled", true)
		Library.scan()
		if is_inside_tree():
			_done(id, "Übernommen: %s" % p.get_file(), "ordner:" + sys)
	)


func _launcher() -> void:
	var miss: Array = _facts.get("launchers_missing", [])
	if miss.is_empty():
		return
	if miss.size() == 1:
		main.open_launcher_offer(str(miss[0].id))
		return
	var opts: Array = miss.map(func(m: Dictionary) -> Array: return [str(m.id), str(m.name)])
	main.open_choice("Welcher Launcher?", opts, null, func(v: Variant) -> void: main.open_launcher_offer(str(v)))


func _login(sid: String) -> void:
	match sid:
		"twitch":
			main.open_twitch_login()
		"nuvio":
			main.open_nuvio_login()
		"youtube":
			main.open_layer(load("res://src/ui/layers/yt_tv_login.gd").new())
		"epic":
			main.open_layer(load("res://src/ui/layers/epic_login.gd").new())
		_:
			go_settings(main, "konten")


## Eine Stelle in den Einstellungen öffnen: alle Ebenen (Doktor, Guide) schließen, dann die
## Kategorie, Unterseite („kat/Seite“) oder Zeile („kat#Zeile“). Statisch: die Ebene ist dann weg.
static func go_settings(m: Main, target: String) -> void:
	for l in Nav.layers.duplicate():
		if is_instance_valid(l) and l.has_method("close"):
			l.close()
	await m.get_tree().process_frame
	if not is_instance_valid(m):
		return
	var cat := target.get_slice("/", 0).get_slice("#", 0)
	await m.goto("settings", cat)
	var sv: Variant = m.sections.get("settings") if m.sections is Dictionary else null
	if sv == null or not is_instance_valid(sv):
		return
	if target.contains("/"):
		# „kategorie/Unterseite#Zeile“: die Unterseite auf und gleich die Zeile darin wählen.
		var more := target.get_slice("/", 1).get_slice("#", 0)
		sv.open_more(more, ("set:%s:%s:%s" % [cat, more, target.get_slice("#", 1)]) if target.contains("#") else "")
	elif target.contains("#"):
		await m.get_tree().process_frame
		await m.get_tree().process_frame
		sv.focus_row("set:%s:%s" % [cat, target.get_slice("#", 1)])


## Die Seite eines Emulators in den Einstellungen (Programmdatei wählen).
static func go_emulator(m: Main, eid: String) -> void:
	await go_settings(m, "emulation")
	var sv: Variant = m.sections.get("settings") if is_instance_valid(m) and m.sections is Dictionary else null
	if sv != null and is_instance_valid(sv) and sv.has_method("open_emulator"):
		sv.open_emulator(eid)


# --- Bausteine -------------------------------------------------------------------------------

## Eine Problemkarte: Zeichen in einer getönten Scheibe, Titel, Erklärung, unten der Weg
## („Beheben“ bzw. „So geht's“) oder der Stand nach dem Beheben. Gewählt wird sie hell (wie Zeilen).
class _ProblemCard extends Control:
	signal activated
	const UU := preload("res://src/ui/u.gd")
	var data: Dictionary = {}
	var state := ""
	var note := ""
	var _spin := 0.0
	var _act_l: Label
	var _badge_c: Control

	func build() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var m := UU.margin(32, 28, 32, 26)
		UU.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var h := UU.hbox(24)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(h)
		var badge := Control.new()
		badge.custom_minimum_size = Vector2(64, 64)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(badge)
		_badge_c = badge
		var v := UU.vbox(8)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var t := UU.ellipsis(UU.label(str(data.get("title", "")), "l", "text", "bold"))
		v.add_child(t)
		var d := UU.label(str(data.get("text", "")), "s", "muted", "regular", true)
		d.max_lines_visible = 3
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(d)
		var row := UU.hbox(10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		var self_fix := bool(data.get("self", false)) and str(data.get("fix", "")) != ""
		var ic_name := "check" if state == "ok" else ("warning" if state == "nein" else ("chevron_right" if self_fix else "info"))
		var ic := UU.icon(ic_name, 22, "ok" if state == "ok" else "accent_ink")
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var txt := note if note != "" else (str(data.get("fix_label", "")) if self_fix else "So geht's")
		if state == "ok" and note == "":
			txt = "Behoben"
		_act_l = UU.ellipsis(UU.label(txt, "m", "ok" if state == "ok" else "accent_ink", "medium"))
		_act_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_act_l)
		focus_entered.connect(func() -> void: _anim(true))
		focus_exited.connect(func() -> void: _anim(false))
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)
		badge.draw.connect(func() -> void:
			var col := _tone()
			var c := badge.size * 0.5
			draw_badge(badge, c, col)
		)
		set_process(state == "läuft")

	func _tone() -> Color:
		if state == "ok":
			return UzTheme.col("ok")
		return UzTheme.col("warn") if str(data.get("sev", "")) == "wichtig" else UzTheme.col("accent")

	func draw_badge(ci: Control, c: Vector2, col: Color) -> void:
		# Eckig (Marke): das Zeichen steht frei, ohne getönte Scheibe.
		if not UzTheme.strict():
			ci.draw_circle(c, 32.0, Color(col, 0.14), true, -1.0, true)
		if state == "läuft":
			ci.draw_arc(c, 31.0, _spin * 5.0, _spin * 5.0 + 2.0, 32, col, 3.0, true)
		var tex: Texture2D = Icons.tex("check" if state == "ok" else str(data.get("icon", "info")), 30)
		if tex:
			ci.draw_texture_rect(tex, Rect2(c - Vector2(15, 15), Vector2(30, 30)), false, col)

	func _process(dt: float) -> void:
		_spin += dt
		if is_instance_valid(_badge_c):
			_badge_c.queue_redraw()

	func _anim(on: bool) -> void:
		UU.etikett(self, on)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(x: float) -> void:
			set_meta("uz_f", x)
			queue_redraw()
		, float(get_meta("uz_f", 0.0)), 1.0 if on else 0.0, UU.T_FOCUS if on else UU.T_BASE)

	func activate() -> void:
		activated.emit()

	func _draw() -> void:
		var f: float = get_meta("uz_f", 0.0)
		var r := Rect2(Vector2.ZERO, size)
		var rad := UzTheme.r_panel()
		if UzTheme.strict():
			# Ein Feld der Listen-Sprache: Haarlinie statt Glasfläche, gewählt der Cursor der Marke.
			UzTheme.draw_hairline(self, r, rad)
			Liste.cursor(self, r, f, rad)
			if str(data.get("sev", "")) == "wichtig" and state != "ok":
				draw_style_box(UzTheme.box(UzTheme.col("warn"), 2), Rect2(6, 10, 3, size.y - 20))
			return
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), rad), r)
		# Wichtige Karten tragen links einen schmalen Streifen in Warnfarbe.
		if str(data.get("sev", "")) == "wichtig" and state != "ok":
			draw_style_box(UzTheme.box(Color(UzTheme.col("warn"), 0.85), 3), Rect2(0, rad, 4, size.y - rad * 2.0))
		UzTheme.draw_selection(self, r, rad, f)


## Kopf links: großer Zustand – Haken (alles gut), Ausrufezeichen in Warnfarbe oder ein leiser Punkt
## für Hinweise; nach „Erneut prüfen“ läuft einmal ein Ring aus.
class _Status extends Control:
	var kind := "ok"
	var _ring := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(96, 96)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_state(k: String, pulse := false) -> void:
		kind = k
		if pulse:
			_ring = 0.0
			var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tw.tween_method(func(v: float) -> void:
				_ring = v
				queue_redraw()
			, 0.0, 1.0, 0.8)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := UzTheme.col("ok") if kind == "ok" else (UzTheme.col("warn") if kind == "wichtig" else UzTheme.col("accent"))
		if UzTheme.strict():
			# Eckig (Marke): das Zeichen frei in einem Rahmen aus Haarlinie; nach „Erneut prüfen“
			# läuft einmal ein Rahmen aus.
			if _ring < 1.0:
				var g := 14.0 * _ring
				draw_rect(Rect2(c - Vector2(44 + g, 44 + g), Vector2(88 + g * 2.0, 88 + g * 2.0)), Color(col, 0.5 * (1.0 - _ring)), false, 2.0)
			draw_rect(Rect2(c - Vector2(44, 44), Vector2(88, 88)), Color(col, 0.4), false, 1.0)
		else:
			if _ring < 1.0:
				draw_arc(c, 44.0 + 14.0 * _ring, 0, TAU, 64, Color(col, 0.5 * (1.0 - _ring)), 2.0, true)
			draw_circle(c, 44.0, Color(col, 0.14), true, -1.0, true)
			draw_arc(c, 43.0, 0, TAU, 64, Color(col, 0.4), 2.0, true)
		var tex: Texture2D = Icons.tex("check" if kind == "ok" else ("warning" if kind == "wichtig" else "pulse"), 44)
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false, col)


## Karte mit Zeilen (wie in den Einstellungen).
class _Card extends MarginContainer:
	var rows: VBoxContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(k, 6)
		rows = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 0)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rows)
		resized.connect(queue_redraw)

	func _draw() -> void:
		if UzTheme.strict():
			draw_rect(Rect2(0, 0, size.x, 1), UzTheme.col("line"))
			return
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))

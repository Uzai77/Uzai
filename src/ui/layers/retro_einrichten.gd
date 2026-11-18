extends "res://src/ui/layers/layer.gd"
## Retro einrichten (Roadmap 19, 104, R5): oben, welche Systeme Uzai bei dir gefunden hat und was
## ihnen fehlt; darunter je fehlendem Emulator eine Karte mit Fassung, Lizenz und Größe. A zeigt die
## Zustimmung (src/ui/layers/retro_zustimmung.gd) und lädt danach – Fortschritt auf der Karte, A
## während des Ladens bricht ab. Y zeigt die Lizenz, X richtet alle auf einmal ein. Darunter: nach
## Updates sehen, was Uzai nicht automatisch einrichtet (Switch nie) und dass es nie BIOS,
## Firmware oder Spiele lädt. Regeln: src/core/retro_auto.gd, Laden: src/core/retro_laden.gd.
## Erreichbar aus der Einrichtung (Schritt „Suche“), dem Uzai-Doktor und Einstellungen → Emulation.

const RA := preload("res://src/core/retro_auto.gd")
const Laden := preload("res://src/core/retro_laden.gd")
const Zustimmung := preload("res://src/ui/layers/retro_zustimmung.gd")
const SELF := "res://src/ui/layers/retro_einrichten.gd"
const COLS := 2
const GAP := 28.0
const CARD_H := 200.0
const CARD_MIN_W := 600.0

const Main := preload("res://src/main.gd")
var main: Main
var extra := {}                 ## gefundene Spieleordner der Einrichtung: { System → Spiele }
var schon_da: Array = []        ## Emulatoren, die die Einrichtung gleich selbst einträgt
var fokus := ""                 ## Karte, auf der die Auswahl beginnt (Emulator-ID)
var _l: Node
var _lage: Array = []
var _karten: Array = []         ## [{ key, ids, kerne, systeme, angebot }]
var _views := {}                ## key → _Karte
var _sub_l: Label
var _chips: HFlowContainer
var _grid: GridContainer
var _rows: VBoxContainer
var _upd_row: Control
var _sig := ""


static func open_for(m: Main, extra_ := {}, schon_da_: Array = [], fokus_ := "") -> Control:
	var l = load(SELF).new()
	l.main = m
	l.extra = extra_
	l.schon_da = schon_da_
	l.fokus = fokus_
	m.open_layer(l)
	return l


func build() -> void:
	dim = 0.94
	_scrim.color = Color(UzTheme.col("bg"), dim)
	depth = false
	set_meta("uz_hint_b", "Zurück")
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
	head.add_child(_Badge.new())
	var hv := U.vbox(4)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(U.label("Retro einrichten", "xl", "text", "title"))
	_sub_l = U.label("", "m", "muted", "regular", true)
	_sub_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hv.add_child(_sub_l)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	var pad := U.margin(14, 10, 14, 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	var page := U.vbox(0)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(page)
	page.add_child(_section("Deine Systeme"))
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 12)
	_chips.add_theme_constant_override("v_separation", 12)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_chips)
	page.add_child(U.spacer(0, 36, false))
	page.add_child(_section("Von der offiziellen Quelle einrichten"))
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_grid)
	page.add_child(U.spacer(0, 36, false))
	var card := _Rows.new()
	page.add_child(card)
	_rows = card.rows
	_l = Laden.inst()
	_l.changed.connect(_on_job)
	_neu()
	_angebote_holen()


func _first_focus() -> Control:
	for k in _karten:
		if str(k.key) == fokus and _views.has(fokus):
			return _views[fokus]
	return Nav.default_in(_grid) if _grid.get_child_count() > 0 else Nav.default_in(self)


func _section(t: String) -> Control:
	var m := U.margin(4, 0, 0, 16)
	m.add_child(U.label(t, "s", "muted", "bold"))
	return m


func handle(cmd: String) -> bool:
	var f := Nav.focused()
	if cmd == "y" and f is _Karte:
		Sfx.play("select")
		_lizenz((f as _Karte).data)
		return true
	if cmd == "x" and _offen().size() >= 2:
		Sfx.play("select")
		_alle()
		return true
	return false


# --- Lage und Karten --------------------------------------------------------------------------

func _neu() -> void:
	if not is_inside_tree():
		return
	_lage = _l.lage(extra, schon_da)
	var plan := RA.plan(_lage)
	var ra_eigen: bool = not _l.installiert("retroarch").is_empty() and _l.exe_da(str(Config.emulator("retroarch").get("exe", "")))
	for id in plan.emus:
		var k := _karte(str(id))
		k.systeme = plan.systeme[id]
		if str(id) == "retroarch":
			k.kerne = plan.kerne
			k.ids = [] if ra_eigen else ["retroarch"]
	# Was gerade lädt oder geladen hat (auch Updates), bleibt als Karte stehen.
	for key in _l.auftraege.keys():
		if not str(key).begins_with("kern:"):
			_karte(str(key))
	var fehlt := RA.fehlt_text(_lage)
	if _lage.is_empty():
		_sub_l.text = tr("Keine Emulator-Spiele. Ordner unter Einstellungen → Emulation wählen.")
	elif fehlt != "":
		_sub_l.text = tr(fehlt) + ". " + tr("Von der offiziellen Quelle.")
	else:
		_sub_l.text = tr("Alles bereit – jedes System hat seinen Emulator.")
	var sig := JSON.stringify([_lage, _karten.map(func(k: Dictionary) -> Array: return [k.key, k.ids, k.kerne])])
	if sig == _sig:
		return
	_sig = sig
	_fill_chips()
	_fill_cards()
	_fill_rows()


func _karte(id: String) -> Dictionary:
	for k in _karten:
		if str(k.key) == id:
			return k
	var k := { "key": id, "ids": [id], "kerne": [], "systeme": [], "angebot": {} }
	_karten.append(k)
	return k


func _fill_chips() -> void:
	U.clear(_chips)
	for r in _lage:
		var sys := Config.system(str(r.system))
		var c := _Chip.new()
		c.dot = Color(str(sys.get("color", "#888888")))
		c.titel = str(r.name)
		c.spiele = int(r.spiele)
		var emu_name := str(RA.eintrag(str(r.angebot)).get("name", ""))
		if bool(r.bereit):
			c.zustand = ["ok", tr("Bereit")]
		elif str(r.angebot) != "":
			c.zustand = ["warn", tr("%s fehlt") % (("%s · %s" % [emu_name, str(RA.KERN_INFO.get(str(r.kern), [r.kern])[0])]) if str(r.kern) != "" else emu_name)]
		elif str(r.grund) == "switch":
			c.zustand = ["faint", tr("Nie automatisch")]
		elif str(r.grund) == "kern_selbst":
			c.zustand = ["faint", tr("Kern in RetroArch laden")]
		else:
			c.zustand = ["faint", tr("Selbst einrichten")]
		_chips.add_child(c)


func _fill_cards() -> void:
	var f := Nav.focused()
	var had := f != null and is_instance_valid(f) and _grid.is_ancestor_of(f)
	var keep := str(f.get_meta("uz_key", "")) if had else ""
	U.clear(_grid)
	_views.clear()
	var cols := COLS
	var w := (U.view_size().x - 96.0 * 2.0 - 28.0 - GAP * (cols - 1)) / cols
	if w < CARD_MIN_W:
		cols = 1
		w = U.view_size().x - 96.0 * 2.0 - 28.0
	_grid.columns = cols
	for k in _karten:
		var v := _Karte.new()
		v.data = k
		v.custom_minimum_size = Vector2(w, CARD_H)
		v.set_meta("uz_key", "ra:" + str(k.key))
		v.activated.connect(func() -> void: _aktion(k))
		_grid.add_child(v)
		v.build()
		_views[str(k.key)] = v
		_zeige(k)
	if _karten.is_empty():
		var none := U.label("Hier gibt es gerade nichts einzurichten.", "m", "faint")
		_grid.add_child(none)
	if not had:
		return
	for c in Nav.focusables(_grid):
		if str(c.get_meta("uz_key", "")) == keep:
			Nav.focus(c, true)
			return
	var d := _first_focus()
	if d:
		Nav.focus(d, true)


func _fill_rows() -> void:
	U.clear(_rows)
	var offen := _offen()
	if offen.size() >= 2:
		var all = _row("action", "Alle einrichten", tr("%d Emulatoren") % offen.size(), "download",
				"Alle fehlenden Emulatoren von den offiziellen Quellen.")
		all.tone = "accent"
		all.on_activate = _alle
	_upd_row = _row("action", "Nach Updates sehen", "", "refresh", "Spielstände und Einstellungen bleiben.")
	_upd_row.on_activate = _updates
	var nie := _namen(func(r: Dictionary) -> bool: return str(r.grund) == "switch")
	if not nie.is_empty():
		_row("info", "Switch", tr("Nie automatisch"), "lock", "Keine automatische Einrichtung. Eigenen Emulator unter Einstellungen → Emulation eintragen.")
	var selbst := _namen(func(r: Dictionary) -> bool: return str(r.grund) == "selbst")
	if not selbst.is_empty():
		_row("info", "Selbst einrichten", ", ".join(selbst), "chip", "Eigenen Emulator unter Einstellungen → Emulation eintragen.")
	var kern := _namen(func(r: Dictionary) -> bool: return str(r.grund) == "kern_selbst")
	if not kern.is_empty():
		_row("info", "Kern fehlt in deinem RetroArch", ", ".join(kern), "retro",
				"In RetroArch: Online-Aktualisierung → Kerne herunterladen.")
	_row("info", "BIOS, Firmware und Spiele", tr("Nie"), "info", "Keine BIOS, Firmware, Schlüssel oder Spiele.")
	_row("info", "Ordner der Emulatoren", Laden.win(_l.ordner()), "folder",
			"")


func _row(kind: String, t: String, val: String, icon: String, desc: String) -> Control:
	var r = SettingRow.new()
	r.setup(kind, t, desc)
	r.icon_name = icon
	r.value_text = val
	r.tone = "faint" if kind == "info" else ""
	r.focus_radius = maxi(UzTheme.radius, UzTheme.r_panel() - 6)
	r.set_meta("uz_key", "ra:row:" + t)
	_rows.add_child(r)
	return r


func _namen(f: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	for r in _lage:
		if f.call(r):
			out.append(str(r.short))
	return out


## Karten, die man noch einrichten kann (Angebot da, nicht schon dabei oder fertig).
func _offen() -> Array:
	return _karten.filter(func(k: Dictionary) -> bool:
		var st := _stand(k)
		return str(st.phase) in ["", "fehler", "abgebrochen"] and (_ok(k) or (k.ids as Array).is_empty() and not (k.kerne as Array).is_empty()))


func _ok(k: Dictionary) -> bool:
	return bool((k.angebot as Dictionary).get("ok", false))


func _angebote_holen() -> void:
	for k in _karten.duplicate():
		if (k.ids as Array).is_empty() or _ok(k):
			continue
		var a: Dictionary = await _l.angebot(str(k.ids[0]))
		if not is_inside_tree():
			return
		k.angebot = a
		_zeige(k)
	if is_inside_tree():
		_fill_rows()


# --- Zustand einer Karte -----------------------------------------------------------------------

## Zusammengefasster Stand aller Aufträge einer Karte: { phase, text, frac }.
func _stand(k: Dictionary) -> Dictionary:
	var keys: Array = (k.ids as Array).duplicate()
	for c in k.kerne:
		keys.append("kern:" + str(c))
	var jobs: Array = keys.filter(func(x: String) -> bool: return _l.auftraege.has(x)).map(func(x: String) -> Dictionary: return _l.auftraege[x])
	if jobs.is_empty():
		return { "phase": "", "text": "", "frac": 0.0 }
	for j in jobs:
		if str(j.phase) == "laeuft":
			var frac := float(j.got) / float(j.total) if int(j.total) > 0 else 0.0
			var t := str(j.text)
			if t == "Lädt …" and int(j.total) > 0:
				t = tr("Lädt … %s von %s") % [RA.groesse_text(int(j.got)), RA.groesse_text(int(j.total))]
			var i := keys.find(keys.filter(func(x: String) -> bool: return _l.auftraege.get(x) == j)[0])
			if keys.size() > 1:
				t = "%d/%d · %s" % [i + 1, keys.size(), tr(t)]
			return { "phase": "laeuft", "text": t, "frac": frac }
	for j in jobs:
		if str(j.phase) == "wartet":
			return { "phase": "wartet", "text": tr("Wartet …"), "frac": 0.0 }
	for j in jobs:
		if str(j.phase) == "fehler":
			return { "phase": "fehler", "text": str(j.text), "frac": 0.0 }
	for j in jobs:
		if str(j.phase) == "abgebrochen":
			return { "phase": "abgebrochen", "text": tr("Abgebrochen – nichts ist liegen geblieben."), "frac": 0.0 }
	return { "phase": "fertig", "text": "", "frac": 1.0 }


func _zeige(k: Dictionary) -> void:
	var v: Variant = _views.get(str(k.key))
	if not (v is _Karte) or not is_instance_valid(v):
		return
	var a: Dictionary = k.angebot
	var e := RA.eintrag(str(k.key))
	var sys := PackedStringArray()
	var n := 0
	for sid in k.systeme:
		for r in _lage:
			if str(r.system) == str(sid):
				sys.append(str(r.short))
				n += int(r.spiele)
	var st := _stand(k)
	var kv := v as _Karte
	kv.titel = str(e.get("name", k.key)) if not (k.ids as Array).is_empty() else tr("RetroArch-Kerne")
	var zeile := tr("für %s") % ", ".join(sys) if not sys.is_empty() else ""
	if n > 0:
		zeile += " · " + U.plural(n, "Spiel", "Spiele")
	if not (k.kerne as Array).is_empty():
		zeile += (" · " if zeile != "" else "") + tr("mit %s") % ", ".join(
				PackedStringArray((k.kerne as Array).map(func(c: String) -> String: return str(RA.KERN_INFO.get(c, [c])[0]))))
	kv.zeile = zeile
	if bool(a.get("ok", false)):
		kv.meta = "%s · %s · %s" % [str(a.fassung),
				str(RA.lizenz(str(a.lizenz)).get("name", a.lizenz)).replace("GNU General Public License", "GPL").replace("Creative Commons", "CC"),
				RA.groesse_text(int(a.groesse)) if int(a.groesse) > 0 else str(a.web)]
	elif (k.ids as Array).is_empty():
		kv.meta = tr("Kerne vom Buildbot · freie Lizenzen")
	elif str(a.get("error", "")) != "":
		kv.meta = str(a.error)
	else:
		kv.meta = tr("Fragt die offizielle Quelle …")
	var phase := str(st.phase)
	kv.state = phase
	kv.frac = float(st.frac)
	match phase:
		"laeuft", "wartet":
			kv.aktion = str(st.text)
			kv.set_meta("uz_hint_a", "Abbrechen")
		"fertig":
			var bios := _bios(k)
			kv.aktion = tr("Bereit · BIOS fehlt noch – A zeigt, wohin") if bios != "" else tr("Bereit")
			kv.set_meta("uz_hint_a", "BIOS-Hinweis" if bios != "" else "Auswählen")
		"fehler":
			kv.aktion = str(st.text)
			kv.set_meta("uz_hint_a", "Erneut versuchen")
		"abgebrochen":
			kv.aktion = str(st.text)
			kv.set_meta("uz_hint_a", "Einrichten")
		_:
			if bool(a.get("ok", false)) or (k.ids as Array).is_empty():
				kv.aktion = tr("Einrichten")
				kv.set_meta("uz_hint_a", "Einrichten")
			elif str(a.get("error", "")) != "":
				kv.aktion = tr("Erneut fragen")
				kv.set_meta("uz_hint_a", "Erneut fragen")
			else:
				kv.aktion = tr("Einen Moment …")
				kv.set_meta("uz_hint_a", "Auswählen")
	kv.set_meta("uz_hint_y", "Lizenz")
	if _offen().size() >= 2:
		kv.set_meta("uz_hint_x", "Alle einrichten")
	elif kv.has_meta("uz_hint_x"):
		kv.remove_meta("uz_hint_x")
	kv.refresh()
	# Die Tastenhinweise unten folgen dem Zustand (Einrichten → Abbrechen → BIOS-Hinweis).
	var now := "%s|%s" % [kv.get_meta("uz_hint_a", ""), kv.get_meta("uz_hint_x", "")]
	if now != str(kv.get_meta("uz_hints_shown", "")):
		kv.set_meta("uz_hints_shown", now)
		if kv.has_focus():
			Nav.focus_moved.emit(kv)


func _on_job(key: String) -> void:
	if not is_inside_tree():
		return
	var j: Dictionary = _l.auftraege.get(key, {})
	for k in _karten:
		_zeige(k)
	if str(j.get("phase", "")) in ["fertig", "fehler", "abgebrochen"]:
		if str(j.phase) == "fertig" and not _l.beschaeftigt():
			Sfx.play("toggle_on")
		_sig = ""
		_neu()


## BIOS-Hinweise einer fertigen Karte ("" wenn keiner nötig ist oder schon etwas im Ordner liegt).
func _bios(k: Dictionary) -> String:
	var id := str(k.key) if not (k.ids as Array).is_empty() else "retroarch"
	var dir := Laden.win(_l.emu_dir(id))
	var lines := PackedStringArray()
	for sid in k.systeme:
		var ordner := str((RA.eintrag(id).get("bios", {}) as Dictionary).get(sid, ""))
		if ordner == "":
			continue
		if not Library.demo and not DirAccess.get_files_at(_l.emu_dir(id).path_join(ordner)).is_empty():
			continue
		var t := RA.bios_hinweis(str(sid), str(Config.system(str(sid)).get("name", sid)), id, dir)
		if t != "":
			lines.append(t)
	return "\n\n".join(lines)


# --- Handeln -----------------------------------------------------------------------------------

func _aktion(k: Dictionary) -> void:
	var st := _stand(k)
	match str(st.phase):
		"laeuft", "wartet":
			main.open_dialog(tr("%s: Laden abbrechen?") % _titel(k), "", [
				["Weiter laden", func() -> void: pass],
				["Abbrechen", func() -> void: _abbrechen(k), "danger"],
			], "download")
		"fertig":
			var b := _bios(k)
			if b != "":
				main.open_dialog("BIOS deiner Konsole", b, [["OK", func() -> void: pass]], "info")
			else:
				Toasts.show_toast(tr("%s ist bereit") % _titel(k), "Spiele starten jetzt direkt im Vollbild.", "check", { "quiet": true })
		_:
			if not (k.ids as Array).is_empty() and not _ok(k):
				k.angebot = {}
				_zeige(k)
				var a: Dictionary = await _l.angebot(str(k.ids[0]), true)
				if is_inside_tree():
					k.angebot = a
					_zeige(k)
					_fill_rows()
				return
			_zustimmen([k])


func _titel(k: Dictionary) -> String:
	return str(RA.eintrag(str(k.key)).get("name", k.key)) if not (k.ids as Array).is_empty() else tr("RetroArch-Kerne")


func _abbrechen(k: Dictionary) -> void:
	for id in k.ids:
		_l.abbrechen(str(id))
	for c in k.kerne:
		_l.abbrechen("kern:" + str(c))


func _teil(k: Dictionary) -> Dictionary:
	var a: Dictionary = k.angebot
	if (k.ids as Array).is_empty():
		a = { "name": tr("RetroArch-Kerne"), "fassung": "", "web": "buildbot.libretro.com", "lizenz": "", "groesse": -1, "pruefung": "CRC32 des Buildbots",
				"nur_kerne": true }
	var sys := PackedStringArray()
	for sid in k.systeme:
		sys.append(str(Config.system(str(sid)).get("short", sid)))
	return { "angebot": a, "kerne": k.kerne, "systeme": Array(sys) }


func _zustimmen(liste: Array, update := false) -> void:
	Zustimmung.open_for(main, liste.map(_teil), Laden.win(_l.ordner()), func() -> void: _start(liste), update)


func _start(liste: Array) -> void:
	var ids: Array = []
	var kerne: Array = []
	var sys := {}
	for k in liste:
		for id in k.ids:
			ids.append(id)
			sys[id] = k.systeme
		for c in k.kerne:
			kerne.append(c)
		if not (k.kerne as Array).is_empty():
			sys["retroarch"] = k.systeme
	_l.einrichten(ids, kerne, sys)
	for k in liste:
		_zeige(k)
	_fill_rows()


func _alle() -> void:
	var offen := _offen()
	if offen.is_empty():
		return
	_zustimmen(offen)


func _lizenz(k: Dictionary) -> void:
	var t := _teil(k)
	var keys: Array = []
	if not bool(t.angebot.get("nur_kerne", false)):
		keys.append([str(RA.eintrag(str(k.key)).get("lizenz", "")), [_titel(k)]])
	for c in k.kerne:
		var info: Array = RA.KERN_INFO.get(c, [])
		if info.is_empty():
			continue
		var found := false
		for x in keys:
			if str(x[0]) == str(info[1]):
				(x[1] as Array).append(str(info[0]))
				found = true
		if not found:
			keys.append([str(info[1]), [str(info[0])]])
	if keys.size() == 1:
		Zustimmung.Lizenz.open_for(main, str(keys[0][0]), PackedStringArray(keys[0][1]))
		return
	main.open_choice("Welche Lizenz?",
			keys.map(func(x: Array) -> Array: return [x[0], "%s · %s" % [str(RA.lizenz(str(x[0])).get("name", x[0])), ", ".join(PackedStringArray(x[1]))]]), null,
			func(v: Variant) -> void:
		for x in keys:
			if str(x[0]) == str(v):
				Zustimmung.Lizenz.open_for(main, str(v), PackedStringArray(x[1])))


func _updates() -> void:
	if not is_instance_valid(_upd_row):
		return
	_upd_row.value_text = tr("Fragt nach …")
	var res: Array = await _l.updates()
	if not is_inside_tree():
		return
	# Die Zeilen können inzwischen neu gebaut sein (ein Auftrag wurde fertig): dann gibt es diese nicht mehr.
	if is_instance_valid(_upd_row):
		_upd_row.value_text = ""
	if res.is_empty():
		main.open_dialog("Nach Updates sehen", "Keine eingerichteten Emulatoren.",
				[["OK", func() -> void: pass]], "refresh")
		return
	var lines := PackedStringArray()
	var neu: Array = []
	for r in res:
		if str(r.neu) != "":
			lines.append(tr("%s: %s → %s") % [r.name, r.alt, r.neu])
			var k := _karte(str(r.id))
			k.angebot = r.angebot
			k.ids = [str(r.id)]
			neu.append(k)
		else:
			lines.append(tr("%s: aktuell") % ("%s %s" % [r.name, r.alt]).strip_edges())
		if str(r.hinweis) != "":
			lines.append("   " + str(r.hinweis))
	if neu.is_empty():
		main.open_dialog("Alles aktuell", "\n".join(lines), [["OK", func() -> void: pass]], "check")
		return
	_sig = ""
	_neu()
	main.open_dialog("Neue Fassungen", "\n".join(lines), [
		["Aktualisieren …", func() -> void: _zustimmen(neu, true)],
		["Später", func() -> void: pass],
	], "refresh")


# --- Bausteine ---------------------------------------------------------------------------------

## Kopf: ein Modul in einer getönten Scheibe.
class _Badge extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(96, 96)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var c := size * 0.5
		var col := UzTheme.col("accent")
		draw_circle(c, 44.0, Color(col, 0.14), true, -1.0, true)
		draw_arc(c, 43.0, 0, TAU, 64, Color(col, 0.4), 2.0, true)
		var tex: Texture2D = Icons.tex("retro", 44)
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false, col)


## Ein gefundenes System: Punkt in seiner Farbe, Name, Zahl der Spiele, Zustand.
class _Chip extends Control:
	const UU := preload("res://src/ui/u.gd")
	var dot := Color.GRAY
	var titel := ""
	var spiele := 0
	var zustand: Array = ["faint", ""]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := UU.margin(22, 14, 24, 14)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var h := UU.hbox(14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(h)
		var d := Control.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.draw.connect(func() -> void: d.draw_circle(Vector2(6, 6), 6.0, dot, true, -1.0, true))
		h.add_child(d)
		var v := UU.vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var t := UU.label(titel, "m", "text", "bold")
		v.add_child(t)
		var s := UU.label("%s · %s" % [UU.plural(spiele, "Spiel", "Spiele"), str(zustand[1])], "s", str(zustand[0]) if str(zustand[0]) != "faint" else "muted",
				"medium")
		s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(s)
		custom_minimum_size = m.get_combined_minimum_size()
		m.resized.connect(func() -> void: custom_minimum_size = m.get_combined_minimum_size())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), r)
		if str(zustand[0]) == "warn":
			draw_style_box(UzTheme.box(Color(UzTheme.col("warn"), 0.85), 3), Rect2(0, 14, 4, size.y - 28.0))


## Karte eines Emulators: Zeichen, Name, wofür, Fassung · Lizenz · Größe, unten der Weg bzw. der
## Fortschritt mit Balken. Gewählt wird sie hell (wie die Karten des Doktors).
class _Karte extends Control:
	signal activated
	const UU := preload("res://src/ui/u.gd")
	const Bar := preload("res://src/ui/components/progress_bar.gd")
	var data: Dictionary = {}
	var titel := ""
	var zeile := ""
	var meta := ""
	var aktion := ""
	var state := ""
	var frac := 0.0
	var _spin := 0.0
	var _t: Label
	var _z: Label
	var _m: Label
	var _a: Label
	var _ic: TextureRect
	var _bar: Control
	var _badge: Control

	func build() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var m := UU.margin(32, 26, 32, 24)
		UU.full_rect(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var h := UU.hbox(24)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(h)
		_badge = Control.new()
		_badge.custom_minimum_size = Vector2(64, 64)
		_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.draw.connect(_draw_badge)
		h.add_child(_badge)
		var v := UU.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		_t = UU.ellipsis(UU.label("", "l", "text", "bold"))
		_z = UU.ellipsis(UU.label("", "s", "muted", "medium"))
		_m = UU.ellipsis(UU.label("", "s", "faint", "medium"))
		for l in [_t, _z, _m]:
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			v.add_child(l)
		v.add_child(UU.spacer(0, 0, true))
		var row := UU.hbox(10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		_ic = UU.icon("chevron_right", 22, "accent_ink")
		_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_ic)
		_a = UU.ellipsis(UU.label("", "m", "accent_ink", "medium"))
		_a.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(_a)
		_bar = Bar.new().setup(0.0, "accent", 6.0)
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_bar)
		focus_entered.connect(func() -> void: _anim(true))
		focus_exited.connect(func() -> void: _anim(false))
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if has_focus():
					Nav.activate(self)
				else:
					grab_focus()
				accept_event())

	func refresh() -> void:
		if not is_instance_valid(_t):
			return
		_t.text = titel
		_z.text = zeile
		_m.text = meta
		_a.text = aktion
		var running := state == "laeuft" or state == "wartet"
		_bar.visible = running
		_bar.call("set_value", frac)
		var tone := "ok" if state == "fertig" else ("warn" if state == "fehler" else "accent_ink")
		_ic.texture = Icons.tex("check" if state == "fertig" else ("warning" if state == "fehler" else ("close" if running else "chevron_right")), 22)
		if not has_focus():
			_ic.modulate = UzTheme.col(tone)
			UU.set_label_color(_a, tone)
		set_process(running)
		_badge.queue_redraw()
		queue_redraw()

	func _draw_badge() -> void:
		var c := _badge.size * 0.5
		var col := UzTheme.col("ok") if state == "fertig" else (UzTheme.col("warn") if state == "fehler" else UzTheme.col("accent"))
		_badge.draw_circle(c, 32.0, Color(col, 0.14), true, -1.0, true)
		if state == "laeuft":
			if frac > 0.0:
				_badge.draw_arc(c, 31.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col, 3.0, true)
			else:
				_badge.draw_arc(c, 31.0, _spin * 5.0, _spin * 5.0 + 2.0, 32, col, 3.0, true)
		var tex: Texture2D = Icons.tex("check" if state == "fertig" else ("download" if state in ["laeuft", "wartet"] else "chip"), 30)
		if tex:
			_badge.draw_texture_rect(tex, Rect2(c - Vector2(15, 15), Vector2(30, 30)), false, col)

	func _process(dt: float) -> void:
		_spin += dt
		_badge.queue_redraw()

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
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), rad), r)
		if state == "" or state == "abgebrochen":
			draw_style_box(UzTheme.box(Color(UzTheme.col("accent"), 0.85), 3), Rect2(0, rad, 4, size.y - rad * 2.0))
		UzTheme.draw_selection(self, r, rad, f)


## Karte mit Zeilen (wie in den Einstellungen).
class _Rows extends MarginContainer:
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
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.05), UzTheme.r_panel()), Rect2(Vector2.ZERO, size))

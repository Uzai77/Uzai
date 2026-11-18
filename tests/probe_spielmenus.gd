extends "res://tests/probe_base.gd"
## Probe „Spielmenüs“: Vorher/Nachher der Menüs an einem Spiel in Graphit, Deutsch, 1920 × 1080 –
## Spiel-Optionen (Steam-, Emulator-, eigenes PC-Spiel) samt Untermenü „Spiel-Einstellungen“ (wenn es eins
## gibt), Spielseite (Kopf und weiter unten) und Sammel-Aktionen im Raster. Je Bild eine Zählung in zahlen.jsonl: Zeilen im Blatt, Knöpfe im
## Kopf der Spielseite, Abschnitte und Seitenlänge. Läuft auf altem und neuem Stand gleich.

const SettingRow := preload("res://src/ui/components/setting_row.gd")

var _f: FileAccess

const GAMES := [["steam", "steam:1245620"], ["rom", "ps2:74a8e64542ec02"], ["pc", "pc:d736d82439562c"]]


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_f = FileAccess.open(out.path_join("zahlen.jsonl"), FileAccess.WRITE)
	await wait(1.2)
	main.goto("games", "zuletzt")
	await wait(1.0)

	# --- Spiel-Optionen --------------------------------------------------------------------------
	for e in GAMES:
		var g := Library.get_game(str(e[1]))
		if g.is_empty():
			continue
		main.open_game_options(g)
		await wait(1.2)
		var sh = Nav.top_layer()
		await shot("opt_%s" % e[0], 0.4)
		var rows := _rows(sh)
		var line := { "screen": "opt_%s" % e[0], "zeilen": rows.size(), "titel": rows.map(func(r): return str(r.title)) }
		var fs := Nav.focusables(sh)
		if fs.size() > 6:
			Nav.focus(fs[-1], true)
			await shot("opt_%s_unten" % e[0], 0.7)
		# Untermenü „Spiel-Einstellungen“ (neuer Stand) bzw. „Eigene Angaben“ (alter Stand)
		var subs := 0
		for key in ["opt:Spiel-Einstellungen", "opt:Eigene Angaben"]:
			var r := _by_key(sh, key)
			if r == null:
				continue
			r.on_activate.call()
			await wait(1.2)
			var sub = Nav.top_layer()
			var srows := _rows(sub)
			line["unter_" + key.trim_prefix("opt:")] = srows.size()
			line["unter_titel_" + key.trim_prefix("opt:")] = srows.map(func(x): return str(x.title))
			subs += srows.size()
			await shot("opt_%s_%s" % [e[0], key.trim_prefix("opt:").replace(" ", "_")], 0.4)
			var sfs := Nav.focusables(sub)
			if sfs.size() > 7:
				Nav.focus(sfs[-1], true)
				await shot("opt_%s_%s_unten" % [e[0], key.trim_prefix("opt:").replace(" ", "_")], 0.7)
			sub.close()
			await wait(0.5)
			break
		line["zeilen_gesamt"] = rows.size() + subs
		_line(line)
		await _close_all()

	# --- Eingebaute Spielseite ---------------------------------------------------------------------
	for e in GAMES:
		var g := Library.get_game(str(e[1]))
		if g.is_empty():
			continue
		main.open_game(g, true)
		await wait(3.2)
		var gp = Nav.top_layer()
		await shot("seite_%s" % e[0], 0.3)
		var head := _group(gp, "gp:buttons")
		var secs := _sections(gp)
		var sc: ScrollContainer = gp.find_children("*", "ScrollContainer", true, false)[0]
		var h := (sc.get_child(0) as Control).size.y
		_line({ "screen": "seite_%s" % e[0], "knoepfe_kopf": head.size(),
			"knoepfe_titel": head.map(func(b): return str(b.text) if b.text != "" else str(b.get_meta("uz_hint_a", ""))),
			"abschnitte": secs.size(), "abschnitt_titel": secs, "seitenlaenge": int(h), "waehlbar": Nav.focusables(gp).size() })
		var y := 900
		var n := 1
		while y < h - 600 and n <= 4:
			sc.scroll_vertical = y
			await shot("seite_%s_%d" % [e[0], n], 0.5)
			y += 900
			n += 1
		await _close_all()

	# --- Sammel-Aktionen ---------------------------------------------------------------------------
	main.open_library("zuletzt", "Zuletzt")
	await wait(1.6)
	var lg = Nav.top_layer()
	lg.call("_set_select", true)
	await wait(4.2)     # Hinweis „Mehrere Spiele auswählen“ abwarten
	lg.call("_pick_all")
	await wait(0.3)
	lg.call("_open_bulk")
	await wait(1.2)
	var bs = Nav.top_layer()
	await shot("sammel", 0.4)
	var brows := _rows(bs)
	var bline := { "screen": "sammel", "zeilen": brows.size(), "titel": brows.map(func(r): return str(r.title)) }
	var er := _by_key(bs, "bulk:Eigene Angaben")
	if er:
		er.on_activate.call()
		await wait(1.2)
		var sub = Nav.top_layer()
		bline["unter_Eigene Angaben"] = _rows(sub).size()
		await shot("sammel_angaben", 0.4)
		sub.close()
		await wait(0.5)
	_line(bline)
	await _close_all()

	_f.close()


func _rows(n: Node) -> Array:
	return n.find_children("*", "", true, false).filter(func(x): return x is SettingRow and x.is_visible_in_tree())


func _by_key(n: Node, key: String) -> Control:
	for c in n.find_children("*", "", true, false):
		if c is Control and str(c.get_meta("uz_key", "")) == key:
			return c
	return null


func _group(n: Node, g: String) -> Array:
	for c in n.find_children("*", "", true, false):
		if str(c.get_meta("uz_group", "")) == g:
			return c.get_children().filter(func(b): return b is Button and b.visible)
	return []


## Überschriften der Abschnitte (VBox mit Meta „uz_extra“).
func _sections(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "VBoxContainer", true, false):
		if c.has_meta("uz_extra") and c.is_visible_in_tree():
			var ls: Array = c.find_children("*", "Label", true, false)
			out.append(str(ls[0].text) if not ls.is_empty() else "?")
	return out


func _close_all() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		await wait(0.35)
		n += 1
	await wait(0.3)


func _line(d: Dictionary) -> void:
	_f.store_line(JSON.stringify(d))
	_f.flush()

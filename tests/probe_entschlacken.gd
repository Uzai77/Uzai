extends "res://tests/probe_base.gd"
## Probe „Entschlacken“: Vorher/Nachher derselben Bildschirme in Graphit, Deutsch, 1920 × 1080 –
## Einstellungen (Aussehen, System, Aufnahmen, Controller), Guide (Start, Spiel, System, Freunde)
## und Zwischenfenster (Guide › Mehr, Spiel-Optionen, Ausschalten, Freunde-Aktionen, Kacheln im
## Guide). Je Bild eine Zählung in zahlen.jsonl: Beschriftungen, Wörter, Sätze (ab 6 Wörtern),
## Nebentexte, Tastenhinweise. Dazu die Einstellungen als Ganzes: Zeilen auf den Hauptseiten,
## alle Zeilen, Info-Zeilen und Wörter im Erklärtext. Läuft auf altem und neuem Stand gleich.

const HintBar := preload("res://src/ui/components/hint_bar.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const SettingRow := preload("res://src/ui/components/setting_row.gd")

var _f: FileAccess
var _vr: Rect2


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_vr = get_viewport().get_visible_rect()
	_f = FileAccess.open(out.path_join("zahlen.jsonl"), FileAccess.WRITE)
	await wait(1.2)

	# --- Einstellungen als Ganzes -------------------------------------------------------------
	var sv = main.sections["settings"]
	main.goto("settings", "aussehen")
	await wait(1.2)
	var inv: Array = sv.search_index()
	var words := 0
	for r in inv:
		words += _words(str(r.desc))
	var main_rows := 0
	var main_words := 0
	var info := 0
	var per_cat := {}
	for c in sv.CATS:
		main.goto("settings", str(c[0]))
		await wait(0.6)
		var rows: Array = sv._list.find_children("*", "", true, false).filter(func(n): return n is SettingRow)
		main_rows += rows.size()
		per_cat[str(c[0])] = rows.size()
		for r in rows:
			main_words += _words(str(r.desc))
			if str(r.kind) == "info":
				info += 1
	_line({ "screen": "einstellungen_gesamt", "zeilen_alle": inv.size(), "woerter_alle": words, "zeilen_hauptseiten": main_rows,
		"woerter_hauptseiten": main_words, "info_hauptseiten": info, "je_bereich": per_cat,
		"bereich_woerter": sv.CATS.reduce(func(a, c): return a + _words(str(c[3])), 0) })

	# --- Einstellungen: Bilder ------------------------------------------------------------------
	for cid in ["aussehen", "system", "aufnahmen", "controller"]:
		main.goto("settings", cid)
		await wait(1.0)
		var first := Nav.default_in(sv._list)
		if first:
			Nav.focus(first, true)
		await shot("set_%s" % cid, 0.7)
		_measure("set_%s" % cid, sv)
		# Neuer Stand: das Seltene liegt unter „Mehr …“ am Ende (alter Stand: gibt es nicht).
		if sv._mores.has("Mehr"):
			sv.open_more("Mehr")
			await wait(1.2)
			await shot("set_%s_mehr" % cid, 0.4)
			_measure("set_%s_mehr" % cid, Nav.top_layer())
			await _close_all()

	# --- Guide ohne Spiel -------------------------------------------------------------------------
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.toggle_guide()
	await wait(1.4)
	await shot("guide_start", 0.5)
	_measure("guide_start", Nav.top_layer())
	await _close_all()
	main.toggle_guide("freunde")
	await wait(1.4)
	await shot("guide_freunde", 0.5)
	_measure("guide_freunde", Nav.top_layer())
	await _close_all()

	# --- Guide im Spiel ---------------------------------------------------------------------------
	var g := Library.get_game("steam:1245620")
	if g.is_empty():
		g = Library.games[0]
	Launcher.in_game = true
	Launcher.current = g
	main.toggle_guide("spiel")
	await wait(1.6)
	await shot("guide_spiel", 0.5)
	_measure("guide_spiel", Nav.top_layer())
	var gd = Nav.top_layer()
	if gd:
		GuideGame.open_more(gd)
		await wait(1.2)
		await shot("zw_guide_mehr", 0.4)
		_measure("zw_guide_mehr", Nav.top_layer())
		await _close_all()
	main.toggle_guide("system")
	await wait(1.4)
	await shot("guide_system", 0.5)
	_measure("guide_system", Nav.top_layer())
	await _close_all()
	Launcher.in_game = false
	Launcher.current = {}
	await wait(0.6)

	# --- Zwischenfenster ----------------------------------------------------------------------
	main.goto("games", "zuletzt")
	await wait(0.8)
	main.open_game_options(g)
	await wait(1.2)
	await shot("zw_spieloptionen", 0.4)
	_measure("zw_spieloptionen", Nav.top_layer())
	await _close_all()
	main.open_power()
	await wait(1.2)
	await shot("zw_ausschalten", 0.4)
	_measure("zw_ausschalten", Nav.top_layer())
	await _close_all()
	if not Social.steam_friends.is_empty():
		main.open_friend(Social.steam_friends[0])
		await wait(1.2)
		await shot("zw_freund", 0.4)
		_measure("zw_freund", Nav.top_layer())
		await _close_all()
	load("res://src/ui/layers/guide_tiles.gd").open(main)
	await wait(1.2)
	await shot("zw_kacheln", 0.4)
	_measure("zw_kacheln", Nav.top_layer())
	await _close_all()

	# --- Freunde (gesendete Anfragen) -----------------------------------------------------------
	main.goto("friends")
	await wait(1.6)
	await shot("freunde", 0.5)
	_measure("freunde", main.friends_view())
	_f.close()


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
	print("Messung: ", JSON.stringify(d).left(300))


## Zählung über alles Sichtbare unter root (nur, was im Bild liegt).
func _measure(name: String, root: Node) -> void:
	var m := { "screen": name, "beschriftungen": 0, "woerter": 0, "saetze": 0, "nebentexte": 0, "satz_texte": [] }
	if root == null:
		m["fehlt"] = true
		_line(m)
		return
	_walk(root, m, 1.0)
	var hints: Array = HintBar.merge(HintBar.collect())
	m["hinweise"] = hints.size()
	m["hinweis_texte"] = hints.map(func(h): return "+".join(PackedStringArray(h[0])) + " " + str(h[1]))
	_line(m)


func _walk(n: Node, m: Dictionary, alpha: float) -> void:
	if n is CanvasItem:
		if not (n as CanvasItem).visible:
			return
		alpha *= (n as CanvasItem).modulate.a
		if alpha < 0.05:
			return
	if n is Control:
		var c := n as Control
		var on_screen := c.get_global_rect().intersects(_vr) and c.size.x > 2 and c.size.y > 2
		if on_screen and (c is Label or (c is Button and str((c as Button).text) != "")):
			var text: String = str(c.get("text")).strip_edges()
			if text != "" and c.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
				var w := _words(text)
				m["beschriftungen"] += 1
				m["woerter"] += w
				if w >= 6:
					m["saetze"] += 1
					(m["satz_texte"] as Array).append(text.replace("\n", " ").left(120))
				if c.get_theme_font_size("font_size") <= UzTheme.size("s"):
					m["nebentexte"] += 1
	for ch in n.get_children():
		_walk(ch, m, alpha)


static var _rx: RegEx


static func _words(t: String) -> int:
	if _rx == null:
		_rx = RegEx.create_from_string("[A-Za-zÄÖÜäöüß0-9]")
	var k := 0
	for w in t.replace("\n", " ").split(" ", false):
		if _rx.search(w.strip_edges()) != null:
			k += 1
	return k

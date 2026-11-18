extends Node
## Seitenleisten bleiben in sich: Uzai auf Englisch mit Demo-Daten aufbauen, die Seitenleisten
## öffnen (Einstellungen mit jeder Unterseite und jeder Auswahlliste, Spieloptionen, Freunde,
## Mitteilungen, Mixer, Guide …) und für jede melden, ob ein sichtbares Element über
## den Rand der Leiste reicht (Zeile, Knopf, langer Text) oder eine Schrift ohne „…“ hart abbricht.
## Je Oberflächengröße (100 % und 150 %; 1280 × 720, 1920 × 1080 und 2560 × 1440 sind logisch
## dieselben 1920 × 1080 bzw. 1280 × 720 Punkte, siehe uz_theme.gd ui_scale).
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_leisten_rand.tscn

const Lang := preload("res://src/core/lang.gd")
const SheetS := preload("res://src/ui/layers/sheet.gd")
const MixerSheet := preload("res://src/ui/layers/mixer_sheet.gd")
const FriendActions := preload("res://src/ui/layers/friend_actions.gd")
const ProfileEdit := preload("res://src/ui/layers/profile_edit.gd")
const Spielstaende := preload("res://src/ui/layers/spielstaende.gd")
const SettingRowS := preload("res://src/ui/components/setting_row.gd")
const WinWlan := preload("res://src/ui/layers/win_wlan.gd")
const WinBt := preload("res://src/ui/layers/win_bt.gd")
const WinEnergie := preload("res://src/ui/layers/win_energie.gd")

## Unschärfe in Punkten (Rundung der Lage beim Hereingleiten).
const TOL := 1.5

var fails := 0
var main: Node
var _gesehen := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	Lang.apply("en")
	Library.load_demo()
	Config.set_value("theme.boot", "aus")
	await get_tree().process_frame
	main = load("res://src/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _warte(1.2)
	for skala in [1.0, 1.5]:
		Config.set_value("theme.ui_scale", skala)
		await _warte(1.6)
		print("Oberfläche %d %% (%s Punkte)" % [int(skala * 100.0), str(get_tree().root.get_visible_rect().size)])
		# Die Einstellungen (mit Auswahllisten) auf der kleineren Fläche: Breiten sind logisch
		# dieselben, nur die Höhe und was sich nach der Fensterbreite richtet, wird knapper.
		if skala > 1.0:
			await _einstellungen(true)
		await _durchgang(true)
	# Echte Bibliotheken und Freundeslisten haben lange Namen: dieselben Leisten noch einmal damit.
	print("Lange Namen (150 %)")
	for g in Library.games:
		g["title"] = str(g.get("title", "")) + " – Definitive Remastered Collector's Edition Deluxe"
	for f in Social.steam_friends:
		if f is Dictionary:
			f["name"] = str(f.get("name", "")) + " the Magnificent Wanderer of the North"
			if str(f.get("game", "")) != "":
				f["game"] = str(f.get("game", "")) + ": Complete Edition with All Expansions"
	await _durchgang(false)
	Config.set_value("theme.ui_scale", 1.0)
	check(_gesehen >= 100, "genug Seitenleisten geprüft (%d)" % _gesehen)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	Lang.release()
	get_tree().quit(1 if fails > 0 else 0)


## alle = false: nur die Leisten, in denen Namen stehen (Spiele, Freunde), und der Guide.
func _durchgang(alle: bool) -> void:
	main.goto("games")
	await _warte(0.4)
	var spiele: Array = Library.visible_games()
	for g in spiele.slice(0, 3):
		await _leiste("Spieloptionen › " + Library.display_title(g), func() -> void: main.open_game_options(g))
	if not spiele.is_empty():
		await _leiste("Spielstände", func() -> void: Spielstaende.open_for(main, spiele[0], "load", func(_r: Variant) -> void: pass))
		await _leiste("Ordner des Spiels", func() -> void: main.open_game_folders(spiele[0]))
	await _leiste("Für dich", func() -> void: main.sections["games"].call("open_fuer_dich"))
	await _leiste("Freunde wählen", func() -> void: main.open_friend_picker("Friends", func(_k: Variant, _f: Variant) -> void: pass))
	await _leiste("Freunde (links)", func() -> void: main.open_friends())
	if not Social.steam_friends.is_empty():
		var f: Dictionary = Social.steam_friends[0]
		await _leiste("Freund", func() -> void:
			var l = FriendActions.new()
			l.friend = f
			main.open_layer(l))
		await _leiste("Erfolge vergleichen", func() -> void: main.open_compare_picker(f))
	if not alle:
		await _guide()
		return
	await _leiste("Musik", func() -> void: main.open_music_actions())
	await _leiste("Mitteilungen", func() -> void: main.open_notifications())
	await _leiste("Bild und Ton", func() -> void: main.open_bild_ton())
	await _leiste("Profil bearbeiten", func() -> void: ProfileEdit.open_for(main, Config.profile_id))
	await _leiste("Spiel hinzufügen", func() -> void: main.open_add_game())
	await _leiste("App hinzufügen", func() -> void: main.open_add_app())
	await _leiste("Dateien", func() -> void: main.open_file_browser("Folder", true, func(_p: Variant) -> void: pass))
	await _leiste("Mixer", func() -> void: MixerSheet.open_for(main))
	await _leiste("Downloads", func() -> void:
		var l = load("res://src/ui/layers/downloads.gd").new()
		main.open_layer(l))
	await _leiste("Zimmer online", func() -> void: main.open_layer(load("res://src/room/online_ui.gd").new()))
	await _leiste("Video", func() -> void: main.open_video_options({ "id": "demo", "title": "A rather long video title that keeps going and going", "channel": "Channel" }))
	for w in [WinWlan, WinBt, WinEnergie]:
		await _leiste(str(w.resource_path.get_file()), func() -> void: w.open_for(main))
	await _leiste("Leistung", func() -> void: load("res://src/ui/components/guide_leistung.gd").open(main))
	await _leiste("Kacheln", func() -> void: load("res://src/ui/layers/guide_tiles.gd").open(main))
	await _leiste("Controller", func() -> void: load("res://src/ui/components/guide_pads.gd").open_all(main))
	await _guide()


## Der Guide ist die Leiste links: jeder Reiter, dazu „Mehr …“ des Spiels und die Musik-Listen.
func _guide() -> void:
	main.toggle_guide()
	await _warte(0.8)
	var g: Control = Nav.top_layer()
	if g == null or not g.has_method("_show_tab"):
		check(false, "Guide offen")
		return
	for id in g.call("_tabs"):
		var tid := str(id[0]) if id is Array else str(id)
		g.call("_show_tab", tid, true, 1)
		await _warte(0.7)
		_pruefen(g, "Guide › " + tid, g.call("flaeche"))
	var tiefe := Nav.layers.size()
	await _leiste("Guide › Spiel › Mehr", func() -> void: load("res://src/ui/components/guide_game.gd").open_more(g))
	await _zu(tiefe)
	for f in ["_open_queue", "_open_recent"]:
		await _leiste("Guide › Musik › " + f, func() -> void: g.call(f))
		await _zu(tiefe)
	await _zu()


## Jede Kategorie und ihre Unterseiten; mit listen auch ihre Auswahllisten.
func _einstellungen(listen: bool) -> void:
	var s: Node = main.sections.get("settings")
	var cats: Array = load("res://src/ui/sections/settings_bausteine.gd").CATS
	for c in cats:
		var cat := str(c[0])
		main.goto("settings", cat)
		await _warte(0.5)
		_pruefen_mitte(s, "Einstellungen › " + cat)
		if listen:
			await _auswahlen(s.get("_list"), "Einstellungen › " + cat)
		var titel: Array = (s.get("_mores") as Dictionary).keys()
		for t in titel:
			if not (s.get("_mores") as Dictionary).has(t):
				s.call("_show_cat", cat)
				await _warte(0.3)
			if not (s.get("_mores") as Dictionary).has(t):
				continue
			var wo := "Einstellungen › %s › %s" % [cat, str(t)]
			var sh: Control = await _leiste(wo, func() -> void: s.call("open_more", t), false)
			if sh and listen:
				await _auswahlen(sh.get("content"), wo)
			await _zu()


## Auswahlen mit mehr als zwei Werten öffnen ihre Liste (setting_row.gd nur_a): jede prüfen.
func _auswahlen(box: Variant, wo: String) -> void:
	if not (box is Control) or not is_instance_valid(box):
		return
	var tiefe := Nav.layers.size()
	for r in Nav.focusables(box):
		if not (is_instance_valid(r) and r.get("kind") == "choice" and (r.get("options") as Array).size() > 2 and r.get("nur_a")):
			continue
		var titel := str(r.get("title"))
		r.call("activate")
		await _warte(0.42)
		if Nav.layers.size() > tiefe and Nav.top_layer() is SheetS:
			_pruefen(Nav.top_layer(), wo + " › " + titel)
		while Nav.layers.size() > tiefe:
			Nav.top_layer().close()
			await _warte(0.12)
		await _warte(0.1)


## Eine Leiste öffnen, prüfen und (zu = true) wieder schließen. Gibt die Leiste zurück.
func _leiste(wo: String, oeffnen: Callable, zu := true) -> Control:
	var tiefe := Nav.layers.size()
	await oeffnen.call()
	await _warte(0.45)
	var top := Nav.top_layer()
	var sh: Control = null
	if Nav.layers.size() > tiefe and top is SheetS:
		sh = top
		_pruefen(sh, wo)
	elif Nav.layers.size() > tiefe:
		print("  –    %s: keine Seitenleiste (%s)" % [wo, top.get_script().resource_path.get_file() if top and top.get_script() else "?"])
	else:
		print("  –    %s: nichts geöffnet" % wo)
	if zu:
		await _zu(tiefe)
	return sh


func _pruefen(sh: Control, wo: String, flaeche: Control = null) -> void:
	var panel: Control = flaeche if flaeche != null else sh.get("panel")
	if panel == null or not panel.is_visible_in_tree():
		print("  –    %s: Leiste vom Theme gespiegelt" % wo)
		return
	_gesehen += 1
	var pr := panel.get_global_rect()
	var vs := get_tree().root.get_visible_rect().size
	var funde: Array = []
	if pr.position.x < -TOL or pr.end.x > vs.x + TOL:
		funde.append("Leiste %d statt %d breit" % [int(pr.size.x), int(float(sh.get("width"))) if "width" in sh else 0])
	_suchen(panel, pr, pr, funde)
	# Tastenhinweise der Leiste: eigene stehen in ihr (oben mitgeprüft), sonst die des Hauptfensters.
	if not sh.has_meta("uz_hints_eigen") and main.get("hint_bar") is Control:
		for h in (main.get("hint_bar") as Control).get_children():
			if h is Control and (h as Control).visible and (h as Control).modulate.a > 0.01:
				var hr := (h as Control).get_global_rect()
				if hr.position.x < pr.position.x - TOL or hr.end.x > pr.end.x + TOL:
					funde.append("Tastenhinweis %s außerhalb der Leiste" % str(h.get_meta("uz_hint_key", "")))
	check(funde.is_empty(), "%s%s" % [wo, "" if funde.is_empty() else ": " + "; ".join(funde.slice(0, 5))])


## Die Mitte der Einstellungen (keine Leiste, dieselben Zeilen): nichts bricht mitten im Wort um,
## keine Zeile verschwindet, kein Wert ist breiter als sein Platz.
func _pruefen_mitte(s: Node, wo: String) -> void:
	var sc: Variant = s.get("_scroll")
	if not (sc is Control):
		return
	var r := (sc as Control).get_global_rect()
	var funde: Array = []
	_suchen(sc, r, r, funde)
	check(funde.is_empty(), "%s (Mitte)%s" % [wo, "" if funde.is_empty() else ": " + "; ".join(funde.slice(0, 5))])


## Sichtbare Elemente unter n, beschnitten wie auf dem Schirm (clip_contents der Vorfahren): ragt
## eines seitlich über die Leiste, wird es gemeldet (seine Kinder nicht mehr). Dazu Schrift, die
## ohne „…“ am eigenen Rand abbricht.
func _suchen(n: Node, leiste: Rect2, clip: Rect2, funde: Array) -> void:
	for ch in n.get_children():
		if not (ch is Control) or not (ch as Control).visible or ch.has_meta("uz_skip"):
			continue
		var c := ch as Control
		if c.modulate.a <= 0.01 and c.self_modulate.a <= 0.01:
			continue
		var r := c.get_global_rect().intersection(clip)
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if r.position.x < leiste.position.x - TOL or r.end.x > leiste.end.x + TOL:
			funde.append("%s ragt %d px hinaus" % [_name(c), int(maxf(leiste.position.x - r.position.x, r.end.x - leiste.end.x))])
			continue
		if r.position.y < leiste.position.y - TOL or r.end.y > leiste.end.y + TOL:
			funde.append("%s ragt %d px über oben/unten" % [_name(c), int(maxf(leiste.position.y - r.position.y, r.end.y - leiste.end.y))])
			continue
		if c.has_method("_full_text") and "_va" in c and _wert_zu_breit(c):
			funde.append("%s: Wert breiter als sein Platz" % _name(c))
		if c is Label and _hart(c as Label):
			funde.append("%s bricht ohne … ab" % _name(c))
		if c is Label and _im_wort(c as Label):
			funde.append("%s bricht mitten im Wort um" % _name(c))
		if c is Label and (c as Label).max_lines_visible > 0 and (c as Label).get_line_count() > (c as Label).max_lines_visible \
				and (c as Label).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			funde.append("%s verliert Zeilen" % _name(c))
		_suchen(c, leiste, r if c.clip_contents else clip, funde)


## Einstellungszeile: der gezeichnete Wert (gekürzt) passt nicht in seinen Platz.
func _wert_zu_breit(c: Control) -> bool:
	var va: Variant = c.get("_va")
	var shown := str(c.get("_shown"))
	if not (va is Control) or shown == "" or str(c.get("kind")) == "toggle":
		return false
	var f: Font = SettingRowS._font()
	return f.get_string_size(c.tr(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x > (va as Control).size.x + 2.0


## Umbrechende Schrift mit einem Wort, das breiter ist als ihr Platz: es bricht mitten im Wort.
func _im_wort(l: Label) -> bool:
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF or l.size.x < 2.0:
		return false
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var t := l.text if l.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else l.tr(l.text)
	for w in t.split(" ", false):
		if f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x + 1.0:
			return true
	return false


## Schrift, die breiter ist als ihr Platz und ohne Auslassung abgeschnitten wird.
func _hart(l: Label) -> bool:
	if not l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return false
	var f := l.get_theme_font("font")
	var t := l.text if l.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else tr(l.text)
	return f != null and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x > l.size.x + 2.0


func _name(c: Control) -> String:
	var t := ""
	if c is Label:
		t = (c as Label).text
	elif c is Button:
		t = (c as Button).text
	elif "title" in c:
		t = str(c.get("title"))
	var art := c.get_class() if c.get_script() == null else str(c.get_script().resource_path.get_file())
	return "%s „%s“" % [art, tr(t).left(40)] if t != "" else art


func _zu(tiefe := -1) -> void:
	var n := 0
	while Nav.top_layer() and Nav.layers.size() > maxi(tiefe, 0) and n < 8:
		Nav.top_layer().close()
		n += 1
		await _warte(0.12)
	await _warte(0.1)


func _warte(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

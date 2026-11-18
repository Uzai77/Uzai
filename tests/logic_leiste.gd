extends Node
## Leiste oben ohne Reiter „Apps“ (src/core/leiste_oben.gd, app_gruppe.gd, nav_item.gd compact):
## Reiterliste aus der Config, Reihenfolge, Ausblenden und Zurückholen, Entfernen eigener Apps,
## Überlauf in den Ordner „Meine Apps“, alte Ziele, Symbolsatz mit gefüllten Fassungen, der
## aufklappende Name; Freunde als Seitenleiste auf Select (freunde_leiste.gd).
## Aufruf: godot --headless --path . res://tests/logic_leiste.tscn

const L := preload("res://src/core/leiste_oben.gd")
const A := preload("res://src/core/apps_extern.gd")
const Q := preload("res://src/ui/sections/quellen_ordnung.gd")
const AppGruppe := preload("res://src/ui/app_gruppe.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")
const FriendsView := preload("res://src/ui/sections/friends_view.gd")

## Die Begriffe der Leiste: jedes Symbol mit Linie und gefüllter Fassung.
const SATZ := ["games", "shop", "friends", "user", "music", "video", "film", "live", "room", "apps", "add", "settings"]

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var keep: Dictionary = Config.settings.duplicate(true)
	_symbole()
	_config()
	_reiter()
	_ueberlauf()
	_ziele()
	_ordnen()
	await _name_klappt()
	await _freunde()
	Config.settings = keep
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _symbole() -> void:
	print("Symbolsatz der Leiste")
	var fehlt: Array = []
	var gleich: Array = []
	for n in SATZ:
		if not Icons.P.has(n) or not Icons.P.has(n + "_f"):
			fehlt.append(n)
			continue
		var a := Icons.image(n, 48.0)
		var b := Icons.image(n + "_f", 48.0)
		if a.is_invisible() or b.is_invisible() or a.get_data() == b.get_data():
			gleich.append(n)
	check(fehlt.is_empty(), "jedes Symbol mit gefüllter Fassung (%s)" % ", ".join(fehlt))
	check(gleich.is_empty(), "Linie und Fassung zeichnen sich und unterscheiden sich (%s)" % ", ".join(gleich))
	check(Icons.tab_icon("music", true) == "music_f" and Icons.tab_icon("music", false) == "music" and Icons.tab_icon("search", true) == "search",
			"tab_icon: gefüllt nur, wenn es die Fassung gibt")
	var dick: Array = []
	for n in SATZ:
		for k in [n, n + "_f"]:
			if str(Icons.P.get(k, "")).contains("stroke-width"):
				dick.append(k)
	check(dick.is_empty(), "ein Strich für alle, auch in den Masken (%s)" % ", ".join(dick))
	check(L.ICONS.values().all(func(i: String) -> bool: return Icons.P.has(i)), "Symbole der eingebauten Apps vorhanden")


func _config() -> void:
	print("Config: Schlüssel bleiben")
	var sp := Config.path("settings.json")
	Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": Config.SETTINGS_VERSION,
		"theme": { "rev": int(Config.DEFAULTS.theme.rev), "sections": ["games", "shop", "friends", "achievements", "apps", "settings"] },
		"apps": { "order": ["room", "music"], "hidden": ["streams"], "last": "videos" } })
	Config.load_settings()
	check(Config.get_value("apps.order", []) == ["room", "music"] and Config.get_value("apps.hidden", []) == ["streams"]
			and str(Config.get_value("apps.last", "")) == "videos", "apps.order, apps.hidden, apps.last unverändert übernommen")


func _ids(arr: Array) -> Array:
	return arr.map(func(t: Dictionary) -> String: return str(t.id))


func _reiter() -> void:
	print("Reiterliste aus der Config")
	Config.set_value(A.KEY, [])
	var all := L.all_apps()
	check(_ids(all) == ["music", "videos", "movies", "streams", "room"], "eingebaut: Musik, Videos, Filme, Streams, Zimmer")
	check(_ids(L.shown(all, ["room", "music"], ["streams"])) == ["room", "music", "videos", "movies"], "eigene Reihenfolge, Ausgeblendetes fehlt")
	check(L.shown(all, [], [], true).is_empty(), "Gruppe „apps“ ausgeblendet: keine App-Symbole")
	check(L.shown(all, [], ["music", "videos", "movies", "streams", "room"]).size() == 5, "alles ausgeblendet: lieber alle als keine")
	var n := A.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	var k := A.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	all = L.all_apps()
	check(_ids(all).slice(5) == [str(n.id), str(k.id)], "eigene Apps dahinter")
	check(L.monogram("Kodi") == "K" and L.monogram("  7even") == "7" and L.monogram("!!") == "•", "Anfangsbuchstabe für Programme ohne Symbol")
	Config.set_value("apps.order", [])
	Config.set_value("apps.hidden", [str(k.id)])
	check(not _ids(L.shown(all, [], Config.get_value("apps.hidden", []))).has(str(k.id)), "eigene App ausblenden")
	# Entfernen: weg aus Liste, Reihenfolge und Ausgeblendetem; Rückgängig holt sie zurück.
	Config.set_value("apps.order", [str(k.id), "music"])
	check(L.remove_app(str(k.id), "Kodi"), "Kodi entfernt")
	check(A.get_entry(str(k.id)).is_empty() and not (Config.get_value("apps.order", []) as Array).has(str(k.id))
			and not (Config.get_value("apps.hidden", []) as Array).has(str(k.id)), "auch aus Reihenfolge und Ausgeblendetem")
	check(not L.remove_app("music", "Musik"), "eingebaute Apps lassen sich nicht entfernen (nur ausblenden)")
	A.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	Config.set_value("apps.hidden", [])
	Config.set_value("apps.order", [])


func _ueberlauf() -> void:
	print("Überlauf")
	var apps := L.all_apps()
	var ext: Array = _ids(apps).filter(func(x: String) -> bool: return A.is_ext_id(x))
	var p := L.plan(apps, true, -1)
	check(p.bar == _ids(apps) and (p.folder as Array).is_empty() and bool(p.add), "genug Platz: alle als Symbol, „+“ am Ende")
	p = L.plan(apps, true, 8)
	check(p.bar == _ids(apps) and (p.folder as Array).is_empty(), "passt genau (7 Apps + „+“): kein Ordner")
	p = L.plan(apps, true, 7)
	check(p.bar == ["music", "videos", "movies", "streams", "room", L.FOLDER] and p.folder == ext, "zu eng: eigene Apps in den Ordner %s" % str(p.bar))
	p = L.plan(apps, true, 4)
	check(p.bar == ["music", "videos", L.FOLDER] and p.folder == ["movies", "streams", "room"] + ext, "sehr eng: auch eingebaute von hinten %s" % str(p.folder))
	p = L.plan(apps, false, 1)
	check(p.bar == [L.FOLDER] and (p.folder as Array).size() == apps.size(), "kein Platz: alles im Ordner, nichts geht verloren")
	var mixed: Array = [apps[5], apps[0], apps[6], apps[1]]
	p = L.plan(mixed, false, 3)
	check(p.bar == ["music", "videos", L.FOLDER] and p.folder == [str(apps[5].id), str(apps[6].id)], "Ordner in der Reihenfolge von apps.order")


func _ziele() -> void:
	print("Alte Ziele")
	var apps := ["music", "videos", "room"]
	check(L.resolve_goto("apps", "", apps, ["games", "music", "videos", "room", "settings"], "videos") == ["videos", ""], "goto(apps): die zuletzt benutzte App")
	check(L.resolve_goto("media", "", apps, ["games", "music", "settings"], "") == ["music", ""], "goto(media): sonst die erste App")
	check(L.resolve_goto("apps", "room", apps, [], "") == ["room", ""], "goto(apps, Zimmer): das Zimmer")
	check(L.resolve_goto("apps", "", apps, ["games", L.FOLDER, "settings"], "music") == [L.FOLDER, ""], "mit Ordner: goto(apps) zeigt ihn")
	check(L.resolve_goto("music", "jetzt", apps, [], "") == ["music", "jetzt"], "goto(music, jetzt): unverändert")


func _ordnen() -> void:
	print("Langes A: Verschieben, Ausblenden, Zurückholen")
	var box := HBoxContainer.new()
	add_child(box)
	var ids: Array = ["music", "videos", "movies", "streams", "room"]
	var g = AppGruppe.new(self, func() -> Array: return ids, func() -> Control: return box, "tab:")
	check(_ids(g.subtabs()) == ids and g.chip_box() == box and str(g.key_prefix) == "tab:", "Gruppe der Symbole")
	check(g.menu_extra("music").is_empty() and g.menu_extra(str(L.all_apps()[5].id)) == [["remove", "Entfernen"]], "„Entfernen“ nur bei eigenen Apps")
	Config.set_value("apps.order", [])
	check(Q.step(g, "music", 1) == 1 and (Config.get_value("apps.order", []) as Array).slice(0, 2) == ["videos", "music"], "Musik einen Platz nach rechts gemerkt")
	check(Q.step(g, "music", -1) == -1, "am Rand: geht nicht (nie über die Wörter oder das „+“)")
	Q.hide(self, g, "streams", "Streams")
	check(Config.get_value("apps.hidden", []) == ["streams"] and _rebuilt > 0, "Streams ausgeblendet, Leiste neu eingeteilt")
	check(_ids(Q.hidden_tabs(g.all_subtabs(), Config.get_value("apps.hidden", []))) == ["streams"], "in „Ausgeblendete Apps“ zum Zurückholen")
	Q._set_hidden(self, g, [])
	check((Config.get_value("apps.hidden", []) as Array).is_empty(), "zurückgeholt")
	box.free()


## Für AppGruppe/quellen_ordnung (statt main).
var _rebuilt := 0


func _rebuild() -> void:
	_rebuilt += 1


func apps_umgestellt() -> void:
	pass


func open_choice(_a: Variant, _b: Variant, _c: Variant, _d: Variant) -> void:
	pass


func _name_klappt() -> void:
	print("Symbol-Reiter: Name unter dem Cursor")
	var strip = TabStrip.new()
	add_child(strip)
	var a = NavItem.new()
	a.setup("Musik", "music", "tab", false)
	a.compact = true
	var b = NavItem.new()
	b.setup("Videos", "video", "tab", true)
	b.compact = true
	strip.add_child(a)
	strip.add_child(b)
	await get_tree().process_frame
	var w0: float = a.get_combined_minimum_size().x
	check(not a._clip.visible and a.name_width() > 20.0, "ruhend nur das Symbol")
	check((a._icon as TextureRect).texture == Icons.tex("music", NavItem.ICON_PX) and (b._icon as TextureRect).texture == Icons.tex("video_f", NavItem.ICON_PX),
			"ruhend Linie, aktiver Reiter gefüllt")
	a.grab_focus()
	await get_tree().create_timer(U_T()).timeout
	check(a._clip.visible and a.get_combined_minimum_size().x > w0 + 20.0, "unter dem Cursor: der Name klappt auf (%.0f → %.0f)" % [w0, a.get_combined_minimum_size().x])
	check((a._icon as TextureRect).texture == Icons.tex("music_f", NavItem.ICON_PX), "unter dem Cursor gefüllt")
	b.grab_focus()
	await get_tree().create_timer(U_T()).timeout
	check(not a._clip.visible and is_equal_approx(a.get_combined_minimum_size().x, w0), "Cursor weiter: wieder nur das Symbol")
	var m = NavItem.new()
	m.setup("Kodi", "", "tab", false)
	m.compact = true
	m.mono = "K"
	strip.add_child(m)
	await get_tree().process_frame
	check(m._icon.get_script() != null and m.name_width() > 0.0, "eigene App ohne Symbol: Buchstabe statt Symbol")
	strip.free()


static func U_T() -> float:
	return preload("res://src/ui/u.gd").T_ORT + 0.15


func _freunde() -> void:
	print("Freunde: Seitenleiste auf Select")
	var main_src := FileAccess.get_file_as_string("res://src/main.gd")
	check(main_src.contains("if sec_id == \"friends\":\n\t\topen_friends(sub_id)"), "jeder Sprung auf „friends“ öffnet die Seitenleiste")
	check(main_src.contains("elif top is FreundeLeiste:") and main_src.contains("elif top == null and not Launcher.in_game:\n\t\t\t\t\topen_friends()"),
			"Select: Pop-up zuerst, im Zimmer der Modus, sonst Freunde auf/zu")
	check(main_src.contains("if sid == \"friends\":\n\t\t\tcontinue"), "Freunde nicht mehr oben in der Leiste")
	var hb := FileAccess.get_file_as_string("res://src/ui/components/hint_bar.gd")
	check(hb.contains("hints.append([\"view\", \"Freunde\"])"), "Hinweis „Select Freunde“, wo Platz ist")
	var fv = FriendsView.new()
	fv.sub = "steam"
	add_child(fv)
	fv.build()
	check(fv.get_child_count() == 1 and fv.get_child(0) is ScrollContainer, "nur die Liste, keine Karte daneben")
	fv.free()
	print("Freunde: von links, der Guide hat Vorrang")
	var fl = load("res://src/ui/layers/freunde_leiste.gd").new()
	check(fl.links == true and fl.has_meta("uz_links_leiste"), "Freunde-Leiste kommt von links")
	fl.free()
	var guide_src := FileAccess.get_file_as_string("res://src/main_guide.gd")
	var gz := guide_src.find("l.has_meta(\"uz_links_leiste\")")
	check(gz > 0 and gz < guide_src.find("_guide = Guide.new()"), "der Guide schließt die Leiste links, bevor er kommt")
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var sh = load("res://src/ui/layers/sheet.gd").new()
	sh.setup("Probe", "", 600.0)
	sh.links = true
	sh.open(host)
	await get_tree().create_timer(0.8).timeout
	check(sh.panel.anchor_left == 0.0 and sh.panel.anchor_right == 0.0 and is_equal_approx(sh.panel.offset_left, 0.0)
			and is_equal_approx(sh.panel.offset_right, 600.0), "Seitenleiste links: am linken Rand, ganz hereingeglitten")
	var sb := sh.panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null and sb.shadow_offset.x > 0.0 and sb.border_width_left == 0, "Schatten und Kante zum Bild hin gespiegelt")
	check(not sh.has_meta("uz_toast_spot"), "Mitteilungen dann rechts statt links unten")
	sh.close()
	await get_tree().create_timer(0.4).timeout
	host.queue_free()

extends "res://tests/probe_base.gd"
## Leiste oben im echten Uzai: Spiele · Shop · Profil als Wörter, die Apps als Symbole (Name unter
## dem Cursor, gefüllt, wenn gewählt), „+“, Zahnrad; links/rechts und LT/RT durch alle Reiter, A auf
## App-Symbolen, langes A (Verschieben, Ausblenden, Zurückholen), viele eigene Apps → Ordner, alte
## Ziele („apps“, „media“, „friends“), Freunde auf Select. Ausgabe „RT ok/FAIL …“, keine Bilder
## (die macht tests/probe_leiste.gd).

const A := preload("res://src/core/apps_extern.gd")
const L := preload("res://src/core/leiste_oben.gd")

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("RT %s %s" % ["ok  " if cond else "FAIL", what])


func _keys() -> Array:
	var out: Array = []
	for c in main.tabs_box.get_children():
		var k := str(c.get_meta("uz_key", ""))
		if k.begins_with("tab:"):
			out.append(k.substr(4))
	return out


func _focus_key() -> String:
	return str(Nav.focused().get_meta("uz_key", "")) if Nav.focused() else ""


func _pick(text: String) -> bool:
	var l := Nav.top_layer()
	if l == null:
		return false
	for c in l.find_children("*", "", true, false):
		if c is Control and str(c.get("title")) == text and (c as Control).focus_mode != Control.FOCUS_NONE:
			Nav.focus(c, true)
			await wait(0.3)
			await press("a", 1, 0.8)
			return true
	return false


func _hold_a() -> void:
	Input.action_press("uz_a")
	Nav._fire("a")
	await wait(0.7)
	Input.action_release("uz_a")
	await wait(0.6)


func run() -> void:
	Config.set_value(A.KEY, [])
	await wait(1.0)
	var k := _keys()
	print("RT Leiste: %s" % str(k))
	_ck(k == ["games", "shop", "achievements", "music", "videos", "movies", "streams", "browser", "room", "+", "settings"], "Wörter, App-Symbole, „+“, Zahnrad")
	_ck(not main.sections.has("friends") and not k.has("friends"), "keine Freunde oben")
	_ck(main.order == ["games", "shop", "achievements", "music", "videos", "movies", "streams", "browser", "room", "settings"], "LT/RT-Reihenfolge: %s" % str(main.order))
	await _bar_fits("%dx%d" % [get_window().size.x, get_window().size.y])

	# Links/rechts durch alle Reiter.
	Nav.focus(main._tab_items["achievements"], true)
	await wait(0.8)
	await press("right", 1, 1.0)
	_ck(main.current == "music" and _focus_key() == "tab:music", "rechts vom Profil: Musik (Symbol)")
	_ck(main._tab_items["music"]._clip.visible, "Name „Musik“ unter dem Cursor")
	await press("right", 6, 1.0)
	_ck(main.current == "settings", "rechts bis zu den Einstellungen (kein „+“ mehr dazwischen)")
	await press("rt", 1, 1.2)
	_ck(main.current == "games", "RT am Ende: zurück zu Spiele")
	await press("lt", 1, 1.2)
	_ck(main.current == "settings", "LT: Einstellungen")
	await press("lt", 1, 1.2)
	_ck(main.current == "room", "LT: Zimmer")

	# A auf dem Symbol: hinein; B zurück auf das Symbol.
	Nav.focus(main._tab_items["videos"], true)
	await wait(1.2)
	await press("a", 1, 1.0)
	_ck(main.current == "videos" and main.view_host.is_ancestor_of(Nav.focused()), "A auf Videos: in die App")
	await press("b", 1, 0.6)
	await press("b", 1, 0.6)
	_ck(_focus_key() == "tab:videos", "B: zurück auf ihr Symbol (%s)" % _focus_key())
	Nav.focus(main._tab_items["room"], true)
	await wait(1.0)
	await press("a", 1, 4.0)
	_ck(main.room_layer() != null, "A auf Zimmer: gleich im Zimmer")
	await press("b", 1, 1.6)
	_ck(main.room_layer() == null and _focus_key() == "tab:room", "B im Zimmer: zurück aufs Symbol")

	# Langes A: Verschieben, Ausblenden, Zurückholen.
	Nav.focus(main._tab_items["music"], true)
	await wait(0.6)
	await _hold_a()
	await _pick("Verschieben")
	await wait(0.4)
	await press("right", 1, 0.6)
	await press("a", 1, 0.6)
	_ck(_keys().slice(3, 5) == ["videos", "music"] and main.order.slice(3, 5) == ["videos", "music"], "Musik einen Platz nach rechts: %s" % str(main.order))
	main._rebuild()
	await wait(1.4)
	_ck(_keys().slice(3, 5) == ["videos", "music"], "Reihenfolge gemerkt")
	Nav.focus(main._tab_items["streams"], true)
	await wait(0.6)
	await _hold_a()
	await _pick("Ausblenden")
	await wait(1.6)
	_ck(not _keys().has("streams"), "Streams ausgeblendet")
	Nav.focus(main._tab_items["music"], true)
	await wait(0.4)
	await press("x", 1, 0.6)
	await _pick("Ausgeblendete Apps (1)")
	await wait(0.6)
	await _pick("Streams")
	await wait(1.6)
	_ck(_keys().has("streams"), "X (wie langes A) → Streams wieder da")

	# Viele eigene Apps: Ordner „Meine Apps“, nichts abgeschnitten.
	for i in 12:
		A.add_prog("C:\\Programme\\Probe%d\\app%d.exe" % [i, i], "Probe %d" % i)
	main._rebuild()
	await wait(1.6)
	_ck(_keys().has(L.FOLDER) and not main.folder_kids.is_empty(), "zu viele Symbole: Ordner (%d Apps darin)" % main.folder_kids.size())
	await _bar_fits("viele Apps")
	main.goto(L.FOLDER)
	await wait(1.2)
	_ck(main.current == L.FOLDER and str(Nav.focused().get_meta("uz_key", "")).begins_with("app:") if Nav.focused() else false, "Ordner zeigt die Apps")
	var one := str(main.folder_kids[0])
	main.goto(one)
	await wait(1.0)
	_ck(main.current == one and main._tab_items[L.FOLDER].selected, "eigene App im Ordner: Ordner-Symbol gewählt")
	Config.set_value(A.KEY, [])
	await wait(1.6)
	_ck(not _keys().has(L.FOLDER), "wieder wenige: kein Ordner")

	# Alte Ziele.
	main.goto("media", "movies")
	await wait(1.1)
	_ck(main.current == "movies", "goto(media, movies): Filme")
	main.goto("apps")
	await wait(1.1)
	_ck(main.current in main.app_kids, "goto(apps): eine App (%s)" % main.current)

	# Freunde: Select bzw. goto("friends").
	Nav.focus(main._tab_items["games"], true)
	await wait(0.8)
	Nav._fire("view")
	await wait(1.0)
	_ck(main.friends_view() != null, "Select: Freunde als Seitenleiste")
	Nav._fire("view")
	await wait(0.8)
	_ck(main.friends_view() == null and Nav.top_layer() == null, "noch einmal Select: zu")
	main.goto("friends")
	await wait(1.0)
	_ck(main.friends_view() != null and main.current != "friends", "goto(friends): Seitenleiste")
	await press("b", 1, 0.8)
	_ck(main.friends_view() == null, "B: zu")
	print("RT Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))


## Reiter und Statuszeile oben: nichts abgeschnitten, nichts überlappt (auch mit aufgeklapptem Namen).
func _bar_fits(what: String) -> void:
	await get_tree().process_frame
	var right_end: float = main.tabs_box.get_global_rect().end.x
	var status_l := INF
	for c in [main.music_box, main.friends_box, main.pad_box, main.clock_label]:
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).size.x > 0.0:
			status_l = minf(status_l, (c as Control).get_global_rect().position.x)
	var vw: float = get_viewport().get_visible_rect().size.x
	print("RT %s: Reiter bis %.0f, Statuszeile ab %.0f, Bild %.0f breit" % [what, right_end, status_l, vw])
	_ck(right_end < status_l and main.avatar_box.get_global_rect().end.x <= vw and main._tab_items["settings"].is_visible_in_tree(),
			"%s: Reiter und Statuszeile ohne Überlappung, nichts abgeschnitten" % what)

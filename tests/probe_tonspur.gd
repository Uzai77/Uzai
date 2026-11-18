extends "res://tests/probe_base.gd"
## Fehler 33: Im Filme-Player Tonspur und Untertitel wählen (Y → Wiedergabe). Ausgabe „TS ok/FAIL …“.

var fails := 0


func _ck(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("TS %s %s" % ["ok  " if cond else "FAIL", what])


func _row(sheet: Node, title: String) -> Node:
	for c in sheet.find_children("*", "", true, false):
		if "title" in c and str(c.get("title")) == title and "options" in c:
			return c
	return null


func run() -> void:
	var film := { "id": "film:demo", "title": "Demo-Film", "movies": { "id": "tt0000001" }, "url": "https://example.invalid/film.mkv", "duration": 5400 }
	main.open_video([film], 0)
	await wait(2.0)
	await press("y", 1, 0.8)
	await wait(0.8)
	var sheet: Node = Nav.layers.back() if not Nav.layers.is_empty() else null
	_ck(sheet != null and sheet.get_script().resource_path.ends_with("sheet.gd"), "Y öffnet „Wiedergabe“")
	if sheet == null:
		return
	var at := _row(sheet, "Tonspur")
	_ck(at != null and (at.options as Array).size() == 3, "Tonspur mit drei Sprachen")
	var st := _row(sheet, "Untertitel")
	_ck(st != null and (st.options as Array).size() == 4 and str(st.options[0][1]) == "Aus", "Untertitel: Aus + drei Spuren")
	await shot("01_wiedergabe", 0.4)
	if at != null:
		at.emit_signal("changed", 2)
		await wait(0.4)
		_ck(Video.selected_track(Video.tracks, "audio") == 2, "Englisch gewählt")
	print("TS Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))

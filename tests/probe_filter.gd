extends "res://tests/probe_base.gd"
## Bildschirm-Probe: Raster mit Abschnitten, „Ordnen und filtern“, Ansichten per LB/RB, leerer
## Filter und 3000 Spiele. Aufruf siehe probe_base.gd.


func run() -> void:
	Config.set_value("library.sort", "title")
	main.open_library("alle", "Alle Spiele")
	await shot("01_raster", 1.0)
	await press("y")
	await shot("02_ordnen", 0.8)
	await press("down")
	await press("right")
	await shot("03_abschnitte_im_ordnen", 0.9)
	await press("b")
	await shot("04_nach_plattform", 1.0)
	await press("down", 3, 0.25)
	await shot("05_runter_ueber_abschnitte", 0.9)
	await press("y")
	await press("down")
	await press("right", 2)
	await press("b")
	await shot("06_nach_spielreihe", 1.0)
	# Genre und Jahr wie über „Genre und Jahr von Steam holen“ (Demo: aus dem Beispiel-Shop).
	await Library.fetch_store_meta(Library.visible_games())
	var l: Node = Nav.top_layer()
	l.set("_group", "genre")
	l.call("_refill")
	await shot("07_nach_genre", 1.0)
	await press("y")
	await press("down", 9, 0.1)
	await shot("08_ordnen_filter", 0.8)
	await press("b")
	Config.set_value("library.presets", [
		{ "name": "Installiert nach System", "filter": { "installed": "ja" }, "group": "platform", "sort": "title" },
		{ "name": "Nie gespielt", "filter": { "played": "nein" }, "group": "", "sort": "added" },
	])
	await press("rb")
	await shot("09_ansicht_rb", 1.0)
	await press("rb")
	await shot("10_ansicht_rb_2", 1.0)
	await press("y")
	await press("down", 24, 0.08)
	await shot("11_ordnen_ansichten", 0.8)
	await press("b")
	l.set("_filter", { "platform": "ps2", "installed": "nein" })
	l.set("_group", "")
	l.call("_refill")
	await shot("12_leer", 0.9)
	await press("b")
	await wait(0.6)
	await _big()


## 3000 Spiele: wie lange Aufbau, Umsortieren und Gruppieren dauern.
func _big() -> void:
	var plats := ["ps2", "ps1", "gc", "gba", "switch"]
	for i in 2953:
		var p: String = plats[i % plats.size()]
		Library.games.append({ "id": "%s:big%d" % [p, i], "title": "Testspiel %04d" % i, "system": p, "source": "rom",
			"installed": true, "playtime": (i * 977) % 400000 })
	Library._reindex()
	Config.set_value("library.filter", {})
	Config.set_value("library.group", "")
	var t0 := Time.get_ticks_msec()
	main.open_library("alle", "Alle Spiele")
	await get_tree().process_frame
	var t1 := Time.get_ticks_msec()
	await shot("13_3000", 1.0)
	var l: Node = Nav.top_layer()
	print("3000 Spiele: aufgebaut %d Karten" % (l.get("_cards") as Array).filter(func(c): return c.get("_built")).size())
	var t2 := Time.get_ticks_msec()
	l.set("_group", "platform")
	l.call("_fill")
	await get_tree().process_frame
	var t3 := Time.get_ticks_msec()
	print("3000 Spiele: öffnen %d ms, nach Plattform neu %d ms (%d Karten)" % [t1 - t0, t3 - t2, (l.get("_cards") as Array).size()])
	await shot("14_3000_plattform", 1.0)
	# Was ein Schritt selbst kostet (ohne das Zeichnen, das hier die Software-Grafik übernimmt).
	var worst := 0
	for i in 12:
		var t4 := Time.get_ticks_usec()
		Nav._fire("down")
		worst = maxi(worst, Time.get_ticks_usec() - t4)
		await wait(0.12)
	print("3000 Spiele: ein Schritt runter höchstens %.1f ms" % (worst / 1000.0))
	await shot("15_3000_runter", 0.8)

extends Node
## Filter, Abschnitte und gespeicherte Ansichten im Spiele-Raster (Roadmap 39, 40) ohne Bildschirm,
## mit der Demo-Bibliothek. Aufruf: godot --headless --path . res://tests/logic_filter.tscn

const GameFilter := preload("res://src/library/game_filter.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _titles(list: Array) -> Array:
	return list.map(func(g): return str(g.title))


func _group(parts: Array, title: String) -> Dictionary:
	for p in parts:
		if str(p.title) == title:
			return p
	return {}


func _sum(parts: Array) -> int:
	var n := 0
	for p in parts:
		n += (p.games as Array).size()
	return n


func _ready() -> void:
	Library.load_demo()
	var all := Library.visible_games()
	# 61 Einträge, davon 2 doppelt (Hollow Knight und Cyberpunk 2077 auch bei GOG, Punkt 6).
	check(all.size() == 59, "Demo-Bibliothek geladen (%d Spiele)" % all.size())

	print("Filter einzeln und zusammen")
	var ps2 := GameFilter.apply(all, { "platform": "ps2" })
	check(ps2.size() == 10 and ps2.all(func(g): return g.system == "ps2"), "System: nur PS2 (%d)" % ps2.size())
	check(GameFilter.apply(all, { "platform": "epic" }).size() == 6, "Laden: Epic Games")
	var not_inst := GameFilter.apply(all, { "installed": "nein" })
	check(_titles(not_inst) == ["Control", "Death Stranding", "Star Wars Battlefront II"], "nicht installiert: die drei gekauften Epic-Spiele")
	check(GameFilter.apply(all, { "installed": "ja" }).size() == all.size() - 3, "installiert: der Rest")
	var never := GameFilter.apply(all, { "played": "nein" })
	check(never.all(func(g): return Library.playtime(g) == 0 and Library.last_played(g) == 0) and _titles(never).has("Cyberpunk 2077"),
			"nie gespielt: ohne Spielzeit und ohne „zuletzt“ (%d)" % never.size())
	check(never.size() + GameFilter.apply(all, { "played": "ja" }).size() == all.size(), "gespielt und nie gespielt ergeben zusammen alles")
	var favs := GameFilter.apply(all, { "fav": true })
	check(not favs.is_empty() and favs.all(func(g): return g.get("favorite", false)), "nur Favoriten (%d)" % favs.size())
	var both := GameFilter.apply(all, { "platform": "ps2", "fav": true })
	check(both.all(func(g): return g.system == "ps2" and g.get("favorite", false)) and both.size() <= ps2.size() and both.size() <= favs.size(),
			"mehrere Filter zusammen: beides muss passen")
	check(GameFilter.apply(all, {}) == all, "leerer Filter: alles, gleiche Reihenfolge")
	check(GameFilter.apply(all, { "platform": "ps2", "installed": "nein" }).is_empty(), "nichts passt: leere Liste")

	print("Spielzeit-Spannen")
	check(GameFilter.in_time(0, "lt1") and GameFilter.in_time(3599, "lt1") and not GameFilter.in_time(3600, "lt1"), "unter 1 Std. (0 zählt mit)")
	check(GameFilter.in_time(3600, "1-10") and not GameFilter.in_time(36000, "1-10") and GameFilter.in_time(36000, "10-50"), "Grenzen gehören zur höheren Spanne")
	check(GameFilter.in_time(180000, "gt50") and not GameFilter.in_time(179999, "gt50"), "über 50 Std.")
	var long := GameFilter.apply(all, { "time": "gt50" })
	check(long.all(func(g): return Library.playtime(g) >= 180000) and _titles(long).has("Die Sims 4"), "Spielzeit-Filter über die Bibliothek (%d)" % long.size())

	print("Genre und Jahr aus dem Steam-Shop")
	check(Library.lacks_store_meta(all).size() == 7, "anfangs fehlt bei allen 7 Steam-Spielen die Angabe")
	Library.remember_store_meta(1245620, { "genres": PackedStringArray(["Action", "Rollenspiel", "Action"]), "release": "25. Feb. 2022" })
	var elden := Library.get_game("steam:1245620")
	check(elden.genres == ["Action", "Rollenspiel"] and int(elden.year) == 2022, "Genres (ohne Doppelte) und Jahr am Spiel gemerkt")
	Library.remember_store_meta(367520, { "genres": PackedStringArray(["Action", "Abenteuer", "Indie"]), "release": "Feb 24, 2017" })
	Library.remember_store_meta(413150, { "genres": PackedStringArray(["Indie", "Rollenspiel"]), "release": "26. Feb. 2016", "coming": false })
	Library.remember_store_meta(2379780, { "genres": PackedStringArray(["Strategie"]), "release": "Demnächst", "coming": true })
	Library.remember_store_meta(1086940, {})
	check(not Library.get_game("steam:2379780").has("year"), "„Demnächst“: kein Jahr, nichts geraten")
	check(Library.get_game("steam:1086940").genres == [] and not Library.get_game("steam:1086940").has("year"),
			"Shop kennt das Spiel nicht: als nachgesehen gemerkt, ohne Angabe")
	check(Library.lacks_store_meta(all).size() == 2, "danach fehlen nur noch zwei")
	Library.remember_store_meta(999, { "genres": PackedStringArray(["Action"]) })
	check(Library.get_game("steam:999").is_empty(), "Shop-Angaben zu fremden Spielen ändern die Bibliothek nicht")
	check(GameFilter.year_of("25. Feb. 2022") == 2022 and GameFilter.year_of("Feb 25, 2022") == 2022 and GameFilter.year_of("Q1 2024") == 2024,
			"Jahr aus deutschem, englischem und Quartals-Datum")
	check(GameFilter.year_of("Demnächst") == 0 and GameFilter.year_of("12345") == 0 and GameFilter.year_of("1998") == 1998,
			"ohne Jahreszahl: 0; lange Zahlen zählen nicht")
	var action := GameFilter.apply(all, { "genre": "Action" })
	check(_titles(action) == ["Hollow Knight", "Elden Ring"] or _titles(action) == ["Elden Ring", "Hollow Knight"], "Genre-Filter findet jedes genannte Genre")
	check(GameFilter.apply(all, { "genre": "Rollenspiel" }).size() == 2, "auch das zweite Genre zählt (Elden Ring, Stardew Valley)")
	var unknown_gen := GameFilter.apply(all, { "genre": "?" })
	check(unknown_gen.size() == all.size() - 4, "„Genre unbekannt“: alle ohne Angabe, auch das nachgesehene leere (%d)" % unknown_gen.size())
	check(GameFilter.apply(all, { "decade": 2010 }).size() == 2 and GameFilter.apply(all, { "decade": 2020 }).size() == 1, "Jahrzehnt aus dem Jahr")
	check(GameFilter.apply(all, { "decade": -1 }).size() == all.size() - 3, "Jahrzehnt unbekannt")

	print("Abschnitte")
	var by_title := Library.sorted(all, "title")
	var plat := GameFilter.groups(by_title, "platform")
	check(_sum(plat) == all.size(), "Plattform: jedes Spiel genau einmal (%d Abschnitte)" % plat.size())
	check(not _group(plat, "PlayStation 2").is_empty() and not _group(plat, "Epic Games").is_empty() and not _group(plat, "PC-Spiele").is_empty(),
			"Überschriften mit Namen von System und Laden")
	var names := plat.map(func(p): return str(p.title))
	var sorted_names := names.duplicate()
	sorted_names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	check(names == sorted_names, "Plattformen nach dem Alphabet")
	var ps2_titles: Array = _titles(_group(plat, "PlayStation 2").games)
	var ps2_sorted := ps2_titles.duplicate()
	ps2_sorted.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	check(ps2_titles == ps2_sorted, "im Abschnitt bleibt die Sortierung der Liste")
	var gen := GameFilter.groups(by_title, "genre")
	check(str(gen[gen.size() - 1].title) == "Unbekannt" and bool(gen[gen.size() - 1].unknown), "Genre: „Unbekannt“ steht am Ende")
	check(_titles(_group(gen, "Action").games) == ["Elden Ring", "Hollow Knight"], "Abschnitt nach dem zuerst genannten Genre")
	check(_titles(_group(gen, "Indie").games) == ["Stardew Valley"], "Stardew Valley steht unter Indie (zuerst genannt)")
	check(_sum(gen) == all.size(), "Genre: kein Spiel doppelt")
	var dec := GameFilter.groups(by_title, "decade")
	check(dec.map(func(p): return str(p.title)) == ["2020er", "2010er", "Unbekannt"], "Jahrzehnte: Neues zuerst, Unbekanntes am Ende")
	var yr := GameFilter.groups(by_title, "year")
	check(yr.map(func(p): return str(p.title)) == ["2022", "2017", "2016", "Unbekannt"], "Erscheinungsjahr absteigend")
	var none := GameFilter.groups(by_title, "")
	check(none.size() == 1 and str(none[0].title) == "" and none[0].games == by_title, "ohne Abschnitte: ein Raster ohne Überschrift")
	check(GameFilter.groups(by_title, "quatsch").size() == 1, "unbekannte Gruppierung: wie ohne")
	check(GameFilter.groups([], "genre").is_empty() and GameFilter.groups([], "series").is_empty(), "leere Liste: keine Abschnitte")

	print("Spielreihen (vorsichtig)")
	check(GameFilter.series_of("The Legend of Zelda: The Wind Waker") == "The Legend of Zelda", "Untertitel nach dem Doppelpunkt weg")
	check(GameFilter.series_of("Final Fantasy VII") == "Final Fantasy" and GameFilter.series_of("Final Fantasy X") == "Final Fantasy", "römische Zahl am Ende weg")
	check(GameFilter.series_of("Metal Gear Solid 3: Snake Eater") == "Metal Gear Solid" and GameFilter.series_of("Tekken 3") == "Tekken", "Nummer am Ende weg")
	check(GameFilter.series_of("Resident Evil 2 Remake") == "Resident Evil" and GameFilter.series_of("Skyrim Special Edition") == "Skyrim",
			"Remake und Edition weg")
	check(GameFilter.series_of("Halo 3 - ODST") == "Halo" and GameFilter.series_of("FIFA 23") == "FIFA", "Bindestrich als Untertitel, Jahreszahl als Nummer")
	check(GameFilter.series_of("Ico") == "Ico" and GameFilter.series_of("1942") == "1942" and GameFilter.series_of("Hades") == "Hades",
			"zu kurz oder ohne Zusatz: der ganze Titel")
	check(GameFilter.series_of("Ōkami") == "Ōkami" and GameFilter.series_of("Mega Man X") == "Mega Man", "Sonderzeichen bleiben; X zählt als Zahl")
	var ser := GameFilter.groups(by_title, "series")
	check(_titles(_group(ser, "The Legend of Zelda").games).size() == 3, "Zelda: drei Spiele")
	check(_titles(_group(ser, "Final Fantasy").games) == ["Final Fantasy VII", "Final Fantasy X"], "Final Fantasy: VII und X")
	check(_titles(_group(ser, "Metal Gear Solid").games) == ["Metal Gear Solid", "Metal Gear Solid 3: Snake Eater"], "Metal Gear Solid mit und ohne Nummer")
	check(_group(ser, "Metroid Prime").is_empty() and _group(ser, "Metroid").is_empty(), "Metroid Prime, Fusion, Dread: nicht geraten")
	check(str(ser[ser.size() - 1].title) == "Einzelne Spiele" and _titles(ser[ser.size() - 1].games).has("Ico"), "der Rest steht am Ende unter „Einzelne Spiele“")
	check(_sum(ser) == all.size(), "Reihen: jedes Spiel genau einmal")
	var twins := [{ "id": "steam:1", "title": "Control", "source": "steam" }, { "id": "epic:1", "title": "Control", "source": "epic" }]
	check(GameFilter.groups(twins, "series").size() == 1 and str(GameFilter.groups(twins, "series")[0].title) == "Einzelne Spiele",
			"dasselbe Spiel zweimal ist keine Reihe")

	print("Erfolge (nur Bekanntes)")
	var ga := [{ "id": "a", "title": "A" }, { "id": "b", "title": "B" }, { "id": "c", "title": "C" }, { "id": "d", "title": "D" }]
	var ach := { "a": [3, 10], "b": [10, 10], "c": [0, 0] }
	check(_titles(GameFilter.apply(ga, { "ach": "mit" }, ach)) == ["A", "B"], "mit Erfolgen: nur mit bekannter Zahl über 0")
	check(_titles(GameFilter.apply(ga, { "ach": "offen" }, ach)) == ["A"], "Erfolge offen")
	check(_titles(GameFilter.apply(ga, { "ach": "komplett" }, ach)) == ["B"], "alle Erfolge geholt")
	Achievements._games["x:1"] = { "unlocked": 2, "total": 5 }
	Achievements._games["x:2"] = { "unlocked": 0, "total": 0, "error": "weg" }
	check(Achievements.known({ "id": "x:1" }) == [2, 5] and Achievements.known({ "id": "x:2" }).is_empty() and Achievements.known({ "id": "x:3" }).is_empty(),
			"Achievements.known: Geladenes ja, Fehler und Unbekanntes nicht")

	print("Gespeichertes prüfen")
	var dirty := { "platform": 5, "installed": "vielleicht", "played": "nein", "fav": "ja", "genre": "Action", "decade": 2015, "time": "x", "ach": "offen",
			"boom": true }
	check(GameFilter.clean(dirty) == { "played": "nein", "genre": "Action", "ach": "offen" }, "unbekannte Felder und falsche Werte fallen weg")
	check(GameFilter.clean({ "decade": 2010.0 }) == { "decade": 2010 } and GameFilter.clean({ "decade": -1 }) == { "decade": -1 },
			"Jahrzehnt aus JSON (Kommazahl) wird wieder ganze Zahl")
	check(GameFilter.clean("kaputt").is_empty() and GameFilter.clean_group("genre") == "genre" and GameFilter.clean_group("rm -rf") == "",
			"Unsinn wird zu „nichts“")
	var raw: Array = [{ "name": "RPG", "filter": { "genre": "Rollenspiel" }, "group": "platform", "sort": "title" },
		{ "name": "rpg", "filter": {} }, { "name": "", "filter": {} }, "kein Eintrag",
		{ "name": "Kaputt", "filter": "x", "group": 7, "sort": "quatsch" }]
	for i in 30:
		raw.append({ "name": "Ansicht %d" % i })
	var pre := GameFilter.clean_presets(raw, LibraryGrid.SORTS)
	check(pre.size() == GameFilter.PRESETS_MAX, "höchstens %d Ansichten" % GameFilter.PRESETS_MAX)
	check(str(pre[0].name) == "RPG" and pre[0].filter == { "genre": "Rollenspiel" } and pre[0].group == "platform" and pre[0].sort == "title",
			"gültige Ansicht bleibt ganz")
	check(str(pre[1].name) == "Kaputt" and pre[1].filter == {} and pre[1].group == "" and pre[1].sort == "",
			"doppelter Name und leerer Name fallen weg, Kaputtes wird leer")
	var cfg := { "library": { "filter": "x", "group": 3, "presets": {} } }
	Config.sanitize(cfg, Config.DEFAULTS)
	check(cfg.library.filter == {} and cfg.library.group == "" and cfg.library.presets == [], "Einstellungen mit falschem Typ: Standard")
	# Auch ohne Eintrag in DEFAULTS: Der Ersatzwert an der Lesestelle gibt den Typ vor.
	check(Config.passend("ja", false) == false and Config.passend(1.0, true) == true and Config.passend(false, true) == false,
			"Schalter: nur wahr oder falsch, sonst der Ersatzwert")
	check(Config.passend("70", 70) == 70 and Config.passend(55.0, 70) == 55.0 and Config.passend([], 1.5) == 1.5 and Config.passend(3, 1.5) == 3,
			"Zahl: Ganzzahl und Kommazahl gelten beide, Text und Liste nicht")
	check(Config.passend("x", []) == [] and Config.passend({}, ["a"]) == ["a"] and Config.passend([1], []) == [1], "Liste bleibt Liste")
	check(Config.passend([], {}) == {} and Config.passend(null, { "a": 1 }) == { "a": 1 } and Config.passend({ "b": 2 }, {}) == { "b": 2 },
			"Verzeichnis bleibt Verzeichnis")
	check(Config.passend(7, "") == 7 and Config.passend(true, null) == true and Config.passend("x", null) == "x",
			"Text oder nichts als Ersatzwert: der Wert geht unverändert durch")
	var vorher: Variant = Config.settings.get("pruefung_typ")
	Config.settings["pruefung_typ"] = { "an": "ja", "zahl": "viel", "liste": 3, "gut": true }
	check(bool(Config.get_value("pruefung_typ.an", true)) and int(Config.get_value("pruefung_typ.zahl", 4)) == 4
			and (Config.get_value("pruefung_typ.liste", []) as Array).is_empty() and Config.get_value("pruefung_typ.gut", false) == true,
			"get_value: falscher Typ in der Datei bricht den Leser nicht ab")
	if vorher == null:
		Config.settings.erase("pruefung_typ")
	else:
		Config.settings["pruefung_typ"] = vorher
	var sm := GameFilter.summary({ "installed": "ja", "platform": "ps2", "genre": "Action", "decade": 1990, "time": "gt50" })
	check(sm == "PlayStation 2 · Installiert · Action · 1990er · Über 50 Std.", "Kurzfassung im Kopf (%s)" % sm)
	check(GameFilter.summary({ "genre": "?", "decade": -1 }) == "Genre unbekannt · Jahr unbekannt", "Unbekanntes heißt auch so")

	print("3000 Spiele")
	var big: Array = []
	var plats := ["steam", "epic", "ps2", "ps1", "gba", "switch", "pc"]
	var genres := ["Action", "Abenteuer", "Rollenspiel", "Strategie", "Indie", "Rennspiel"]
	var w1 := ["Asche", "Basalt", "Chrom", "Dunst", "Echo", "Flut", "Glut", "Hain", "Iris", "Jade", "Kobalt", "Lava", "Moos", "Nebel", "Onyx", "Puls", "Quarz",
			"Rost", "Sand", "Tau"]
	var w2 := ["Krone", "Pfad", "Turm", "Welle", "Feder", "Kante", "Linie", "Insel", "Wacht", "Spur", "Bucht", "Tor", "Grat", "Hall", "Mark", "Riff", "Saum",
			"Wall", "Zinne", "Bogen"]
	for i in 3000:
		var p: String = plats[i % plats.size()]
		var word := "%s%s" % [w1[i % 20], w2[floori(i / 20.0) % 20]]
		var g := { "id": "%s:%d" % [p, i], "title": "%s %d" % [word, i % 3 + 1] if i % 2 == 0 else "%s: Kapitel %d" % [word, i],
			"source": p if p in ["steam", "epic", "pc"] else "rom", "system": p, "installed": i % 5 != 0, "playtime": (i * 977) % 400000 }
		if i % 4 != 0:
			g["genres"] = [genres[i % genres.size()], genres[(i + 2) % genres.size()]]
			g["year"] = 1985 + i % 40
		if i % 11 == 0:
			g["favorite"] = true
		big.append(g)
	# Dreimal messen und je Schritt den schnellsten Lauf nehmen: Die Grenzen gelten für den Code,
	# nicht für eine Maschine, die gerade nebenher anderes rechnet.
	var hit: Array = []
	var parts_g: Array = []
	var parts_s: Array = []
	var parts_d: Array = []
	var fc: Dictionary = {}
	var best := [INF, INF, INF]
	for _lauf in 3:
		var t0 := Time.get_ticks_usec()
		hit = GameFilter.apply(big, { "installed": "ja", "genre": "Action", "time": "1-10" })
		var t1 := Time.get_ticks_usec()
		parts_g = GameFilter.groups(big, "genre")
		parts_s = GameFilter.groups(big, "series")
		parts_d = GameFilter.groups(big, "decade")
		var t2 := Time.get_ticks_usec()
		fc = GameFilter.facets(big)
		var t3 := Time.get_ticks_usec()
		best = [minf(best[0], t1 - t0), minf(best[1], t2 - t1), minf(best[2], t3 - t2)]
	print("    Filter %.1f ms, drei Gruppierungen %.1f ms, Auswahl %.1f ms" % [best[0] / 1000.0, best[1] / 1000.0, best[2] / 1000.0])
	check(not hit.is_empty() and _sum(parts_g) == 3000 and _sum(parts_s) == 3000 and _sum(parts_d) == 3000, "alles bleibt vollständig")
	check(parts_s.size() == 400 and str(parts_s[0].title) == "AscheBogen", "400 Reihen in großer Bibliothek, nach dem Alphabet (%d)" % parts_s.size())
	check((fc.platform as Dictionary).size() == plats.size() and int(fc.no_genre) == 750, "Auswahl zählt Plattformen und fehlende Genres")
	check(best[0] < 60000 and best[1] < 250000 and best[2] < 60000, "schnell genug für den Controller (unter 60/250/60 ms)")

	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)

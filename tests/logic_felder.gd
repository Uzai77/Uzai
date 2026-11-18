extends Node
## Eigene Angaben je Spiel und Mehrfachbearbeitung (Roadmap 41, 42) ohne Bildschirm, mit der
## Demo-Bibliothek. Aufruf: godot --headless --path . res://tests/logic_felder.tscn

const GameFields := preload("res://src/library/game_fields.gd")
const GameFilter := preload("res://src/library/game_filter.gd")
const LibraryGrid := preload("res://src/ui/layers/library_grid.gd")
const Backup := preload("res://src/core/backup.gd")

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


func _ready() -> void:
	print("Text säubern")
	check(GameFields.clean_text("  Koop \n\t Couch  ", 32) == "Koop Couch", "Leerraum und Zeilenumbrüche zusammengefasst")
	check(GameFields.clean_text("a\u0001b\u007fc", 32) == "a b c" and GameFields.clean_text("\u0001", 32) == "", "Steuerzeichen fallen weg")
	check(GameFields.clean_text("x".repeat(50), GameFields.TAG_MAX).length() == GameFields.TAG_MAX, "auf die Länge gekürzt")

	print("Tags")
	var t: Array = GameFields.with_tag([], "Koop")
	t = GameFields.with_tag(t, "koop")
	t = GameFields.with_tag(t, "  ")
	check(t == ["Koop"], "kein doppelter Tag, Leeres zählt nicht")
	check(GameFields.with_tag([], "couch", ["Couch", "Koop"]) == ["Couch"], "vorhandene Schreibung wird übernommen")
	var many: Array = []
	for i in 30:
		many = GameFields.with_tag(many, "Tag %d" % i)
	check(many.size() == GameFields.TAGS_MAX, "höchstens %d Tags" % GameFields.TAGS_MAX)
	check(GameFields.without_tag(["Koop", "Couch"], "KOOP") == ["Couch"], "Entfernen ohne Rücksicht auf Groß/klein")
	var at := GameFields.all_tags([{ "tags": ["Koop", "Couch"] }, { "tags": ["koop"] }, { "tags": "kaputt" }, {}])
	check(at == { "Koop": 2, "Couch": 1 }, "alle Tags mit Anzahl, gleiche Tags zusammen (%s)" % str(at))
	check(GameFields.by_count({ "B": 1, "A": 1, "C": 3 }) == ["C", "A", "B"], "Vorschläge: häufige zuerst, sonst Alphabet")

	print("Links: nur https, nie täuschend")
	check(GameFields.link_problem("https://zelda.fandom.com/wiki/Wind_Waker") == "", "normaler https-Link")
	check(GameFields.link_problem("https://example.org:8443/a?b=c#d") == "", "mit Port, Abfrage und Anker")
	check(GameFields.link_problem("http://example.org") != "", "http nicht")
	for bad in ["javascript:alert(1)", "file:///C:/Windows/system32", "steam://run/570", "ftp://x.org", "www.example.org", "data:text/html,x"]:
		check(GameFields.link_problem(bad) != "", "abgelehnt: %s" % bad)
	check(GameFields.link_problem("https://bank.de@evil.example/login") != "", "Anmeldedaten vor der Adresse (täuschendes Ziel)")
	check(GameFields.link_problem("https://exa mple.org") != "" and GameFields.link_problem("https://example.org/\nx") != "", "Leerzeichen und Zeilenumbruch")
	check(GameFields.link_problem("https://example.org\\..\\x") != "", "Backslash")
	check(GameFields.link_problem("https://") != "" and GameFields.link_problem("https://localhost") != "" and GameFields.link_problem("https://.org") != "",
			"ohne richtige Adresse")
	check(GameFields.link_problem("https://a.de/" + "x".repeat(600)) != "", "zu lang")
	check(GameFields.host_of("https://www.Example.org:443/x") == "example.org", "Adresse ohne www. und Port")
	check(GameFields.link_title({ "name": "", "url": "https://www.speedrun.com/okami" }) == "speedrun.com"
			and GameFields.link_title({ "name": "Lösung", "url": "https://a.de" }) == "Lösung", "ohne Namen steht die Adresse da")
	var raw_links: Array = [{ "name": "Wiki", "url": "https://wiki.example.org" }, { "name": "Böse", "url": "http://x.org" }, "kaputt", { "url": 5 }]
	for i in 10:
		raw_links.append({ "name": "L%d" % i, "url": "https://l%d.example.org" % i })
	var lo := GameFields.links_of({ "links": raw_links })
	check(lo.size() == GameFields.LINKS_MAX and str(lo[0].name) == "Wiki" and lo.all(func(l): return str(l.url).begins_with("https://")),
			"nur gültige Links, höchstens %d" % GameFields.LINKS_MAX)

	print("Beim Laden prüfen (library.json von Hand geändert)")
	var g := { "id": "x", "tags": ["Koop", "koop", 7, "", "Couch"], "category": "  Sammlung  ", "age": "usk99", "region": "pal",
		"links": [{ "url": "javascript:alert(1)" }, { "name": "A\nB", "url": "https://a.example.org" }] }
	GameFields.sanitize(g)
	check(g.tags == ["Koop", "Couch"], "Tags ohne Doppelte und Unsinn")
	check(g.category == "Sammlung" and not g.has("age") and g.region == "pal", "Kategorie gesäubert, unbekannte Freigabe weg, Region bleibt")
	check(g.links.size() == 1 and g.links[0].name == "A B", "Link ohne https fällt beim Laden weg")
	var g2 := { "id": "y", "tags": "x", "category": 5, "links": "x" }
	GameFields.sanitize(g2)
	check(not g2.has("tags") and not g2.has("category") and not g2.has("links"), "falsche Typen fallen ganz weg")

	print("Bleiben beim Einlesen")
	for k in GameFields.FIELDS:
		check(k in Library.USER_FIELDS, "„%s“ gehört zu den eigenen Feldern" % k)
	check(Backup.allowed("library.json"), "library.json (mit den Angaben) kommt in jede Sicherung")
	Library.load_demo()
	var all := Library.visible_games()
	var ps2: Array = all.filter(func(x): return x.system == "ps2")
	var ok_id := str(ps2[0].id)
	Library.set_field(ok_id, "tags", ["Koop"])
	Library.set_field(ok_id, "region", "pal")
	var found := (Library.get_game(ok_id) as Dictionary).duplicate(true)
	found.erase("tags")
	found.erase("region")
	found["tags"] = ["vom Scanner"]
	found["title"] = "Neu eingelesen"
	Library._merge([found], ["rom"])
	var after := Library.get_game(ok_id)
	check(after.tags == ["Koop"] and after.region == "pal", "Einlesen überschreibt eigene Angaben nicht")
	# Das Einlesen oben hat die übrigen Demo-Spiele als fehlend markiert: frisch laden.
	Library.load_demo()
	all = Library.visible_games()
	ps2 = all.filter(func(x): return x.system == "ps2")

	print("Änderungen an einem Spiel")
	var h := { "id": "h", "system": "ps2" }
	check(GameFields.apply_op(h, "tag_add", "Koop") and h.tags == ["Koop"], "Tag dazu")
	check(not GameFields.apply_op(h, "tag_add", "KOOP"), "derselbe Tag noch einmal: keine Änderung")
	check(GameFields.apply_op(h, "tag_remove", "koop") and not h.has("tags"), "Tag weg, leere Liste fällt ganz weg")
	check(GameFields.apply_op(h, "category", "Sammlung", ["Sammlung"]) and not GameFields.apply_op(h, "category", "sammlung", ["Sammlung"]),
			"Kategorie, gleiche Schreibung zählt nicht doppelt")
	check(GameFields.apply_op(h, "category", "") and not h.has("category"), "Kategorie entfernen")
	check(GameFields.apply_op(h, "age", "usk12") and not GameFields.apply_op(h, "age", "usk99") and h.age == "usk12", "Altersfreigabe nur aus der Liste")
	check(GameFields.apply_op(h, "region", "ntsc-j") and GameFields.apply_op(h, "region", "") and not h.has("region"), "Region setzen und entfernen")
	check(GameFields.apply_op(h, "fav", true) and h.favorite == true and GameFields.apply_op(h, "fav", false) and not h.has("favorite"), "Favorit an und aus")
	check(GameFields.apply_op(h, "hidden", true) and not GameFields.apply_op(h, "hidden", true), "Ausblenden")
	var f_all := { "id": "f1", "name": "Mit Freunden", "system": "" }
	var f_gc := { "id": "f2", "name": "Cube", "system": "gc" }
	check(GameFields.apply_op(h, "folder_add", f_all) and h.folders == ["f1"], "in einen Ordner für alle Systeme")
	check(not GameFields.apply_op(h, "folder_add", f_gc), "nicht in einen Ordner eines anderen Systems")
	check(not GameFields.apply_op(h, "folder_add", { "id": "auto:ps2:RPG", "system": "ps2" }), "automatische Ordner (Unterordner) bleiben, wie sie sind")
	check(GameFields.apply_op(h, "folder_remove", f_all) and not h.has("folders"), "aus dem Ordner")
	check(not GameFields.apply_op(h, "quatsch", 1), "unbekannte Änderung tut nichts")
	var cnt_list := [{ "id": "a", "system": "ps2", "tags": ["Koop"] }, { "id": "b", "system": "ps2" }, { "id": "c", "system": "gc" }]
	check(GameFields.op_count(cnt_list, "tag_add", "koop", ["Koop"]) == 2 and cnt_list[1].has("tags") == false,
			"Zählen ändert nichts und zählt nur echte Änderungen")
	check(GameFields.op_count(cnt_list, "folder_add", f_gc) == 1, "Ordner eines Systems: nur die passenden Spiele")

	print("Viele Spiele auf einmal (Bibliothek)")
	var ids: Array = ps2.slice(0, 3).map(func(x): return str(x.id))
	var changes := [0]
	var on_changed := func() -> void: changes[0] += 1
	Library.changed.connect(on_changed)
	check(Library.update_many(ids, "tag_add", "Koop") == 3 and changes[0] == 1, "drei Spiele, eine Meldung an die Oberfläche")
	check(Library.update_many(ids, "tag_add", "Koop") == 0 and changes[0] == 1, "noch einmal: nichts geändert, keine Meldung")
	var fourth := str(ps2[3].id)
	Library.update_many([fourth], "tag_add", "koop")
	check(Library.get_game(fourth).tags == ["Koop"], "„koop“ wird zum vorhandenen „Koop“")
	check(Library.update_many(ids + [fourth, "gibt:esnicht"], "category", "Lieblinge") == 4, "Kategorie für vier, Unbekanntes wird übersprungen")
	var loose: Array = ps2.filter(func(x): return not Library.is_in_folder(x, "f_demo2")).slice(0, 3).map(func(x): return str(x.id))
	check(Library.update_many(ids + loose, "folder_add", Library.folder("f_demo2")) == loose.size()
			and Library.is_in_folder(Library.get_game(loose[0]), "f_demo2"), "in den PS2-Ordner „Klassiker“: nur die noch nicht drin sind (%d)" % loose.size())
	var gc_id := str(all.filter(func(x): return x.system == "gc")[0].id)
	check(Library.update_many([gc_id], "folder_add", Library.folder("f_demo2")) == 0, "ein GameCube-Spiel passt nicht in den PS2-Ordner")
	check(Library.update_many(loose, "folder_remove", Library.folder("f_demo2")) == loose.size(), "wieder heraus")
	Library.update_many(ids.slice(0, 1), "age", "pegi16")
	Library.update_many(ids.slice(1, 3), "region", "pal")
	Library.changed.disconnect(on_changed)

	print("Filtern nach eigenen Angaben")
	all = Library.visible_games()
	check(GameFilter.apply(all, { "tag": "koop" }).size() == 4 and GameFilter.apply(all, { "tag": "KOOP" }).size() == 4, "Tag-Filter (Groß/klein egal)")
	check(GameFilter.apply(all, { "tag": "?" }).size() == all.size() - 4, "„Ohne Tag“")
	check(GameFilter.apply(all, { "category": "Lieblinge" }).size() == 4 and GameFilter.apply(all, { "category": "?" }).size() == all.size() - 4,
			"Kategorie und „Ohne Kategorie“")
	check(_titles(GameFilter.apply(all, { "age": "pegi16" })) == [str(Library.get_game(ids[0]).title)], "Altersfreigabe")
	check(GameFilter.apply(all, { "region": "pal" }).size() == 2 and GameFilter.apply(all, { "region": "?" }).size() == all.size() - 2, "Region und „ohne Angabe“")
	check(GameFilter.apply(all, { "tag": "Koop", "region": "pal" }).size() == 2, "mit anderen Filtern kombiniert")
	var fc := GameFilter.facets(all)
	check(fc.tag == { "Koop": 4 } and fc.category == { "Lieblinge": 4 } and fc.age == { "pegi16": 1 } and fc.region == { "pal": 2 },
			"Auswahl zählt die eigenen Angaben")
	check(int(fc.no_tag) == all.size() - 4 and int(fc.no_category) == all.size() - 4, "und was keine hat")
	var sm := GameFilter.summary({ "tag": "Koop", "category": "?", "age": "usk18", "region": "ntsc-j" })
	check(sm == "Tag: Koop · Ohne Kategorie · USK 18 · NTSC-J", "Kurzfassung im Kopf (%s)" % sm)
	var cl := GameFilter.clean({ "tag": "Koop", "category": "?", "age": "usk99", "region": "pal" })
	check(cl == { "tag": "Koop", "category": "?", "region": "pal" }, "gespeicherter Filter: unbekannte Freigabe fällt weg")

	print("Abschnitte nach eigenen Angaben")
	var by_title := Library.sorted(all, "title")
	Library.update_many([ids[0]], "tag_add", "Couch")
	var tg := GameFilter.groups(by_title, "tag")
	check(tg.map(func(p): return str(p.title)) == ["Couch", "Koop", "Ohne Tag"], "Tags nach dem Alphabet, „Ohne Tag“ am Ende")
	check(_group(tg, "Couch").games.size() == 1 and _group(tg, "Koop").games.size() == 4, "ein Spiel mit zwei Tags steht unter beiden")
	var cg := GameFilter.groups(by_title, "category")
	check(str(cg[0].title) == "Lieblinge" and str(cg[cg.size() - 1].title) == "Ohne Kategorie" and bool(cg[cg.size() - 1].unknown),
			"Kategorie, „Ohne Kategorie“ am Ende")
	var ag := GameFilter.groups(by_title, "age")
	check(str(ag[0].title) == "PEGI 16" and str(ag[ag.size() - 1].title) == "Unbekannt", "Altersfreigabe mit lesbarem Namen")
	var rg := GameFilter.groups(by_title, "region")
	check(str(rg[0].title) == "PAL" and (rg[0].games as Array).size() == 2, "Region")
	var sizes := 0
	for p in cg:
		sizes += (p.games as Array).size()
	check(sizes == all.size(), "Kategorie: jedes Spiel genau einmal")

	print("Raster: Texte der Mehrfachbearbeitung")
	check(LibraryGrid._names([{ "title": "A" }, { "title": "B" }]) == "A, B"
			and LibraryGrid._names([{ "title": "A" }, { "title": "B" }, { "title": "C" }, { "title": "D" }]) == "A, B und 2 weitere", "Namen der Auswahl kurz")
	check(LibraryGrid._common([{ "c": "x" }, { "c": "x" }], func(x): return x.c) == "x"
			and LibraryGrid._common([{ "c": "x" }, { "c": "y" }], func(x): return x.c) == "Verschieden"
			and LibraryGrid._common([{}], func(x): return str(x.get("c", ""))) == "Keine", "gemeinsamer Wert, verschieden oder keiner")
	check(LibraryGrid._op_text("tag_add", "Koop") == "Tag „Koop“ hinzufügen?" and LibraryGrid._op_text("age", "usk16") == "Altersfreigabe USK 16 setzen?"
			and LibraryGrid._op_text("folder_remove", { "name": "Klassiker" }) == "Aus „Klassiker“ nehmen?", "Rückfragen sagen, was passiert")

	print("3000 Spiele")
	var big: Array = []
	var tags := ["Koop", "Couch", "Durchgespielt", "Liste", "Retro", "Sammlung"]
	for i in 3000:
		var e := { "id": "pc:%d" % i, "title": "Spiel %d" % i, "source": "pc", "system": "pc" }
		if i % 3 != 0:
			e["tags"] = [tags[i % tags.size()], tags[(i + 1) % tags.size()]]
		if i % 5 == 0:
			e["category"] = "Kategorie %d" % (i % 7)
		big.append(e)
	var t0 := Time.get_ticks_usec()
	var hit := GameFilter.apply(big, { "tag": "Retro" })
	var parts := GameFilter.groups(big, "tag")
	var fc_big := GameFilter.facets(big)
	var t1 := Time.get_ticks_usec()
	var cnt := GameFields.op_count(big, "tag_add", "Neu")
	var t2 := Time.get_ticks_usec()
	print("    Filter, Abschnitte und Auswahl %.1f ms, Zählen für die Rückfrage %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	check(not hit.is_empty() and parts.size() == tags.size() + 1 and (fc_big.tag as Dictionary).size() == tags.size() and cnt == 3000, "alles vollständig")
	check(t1 - t0 < 250000 and t2 - t1 < 250000, "schnell genug (unter 250 ms)")

	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)

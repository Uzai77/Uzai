extends Node
## Backlog (Roadmap 2) ohne Bildschirm, mit der Demo-Bibliothek: Status, Sterne, Rezension,
## Tagebuch, Vorschläge, „Was spiele ich heute?“, Jahresziel, Listen, Filter und Abschnitte,
## Speichern/Laden. Aufruf: godot --headless --path . res://tests/logic_backlog.tscn

const Backlog := preload("res://src/library/backlog.gd")
const GameFilter := preload("res://src/library/game_filter.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _titles(list: Array) -> Array:
	return list.map(func(g): return str(g.title))


func _ready() -> void:
	var now := 1_790_000_000      # fester Zeitpunkt (Mitte Sept. 2026)
	var day := 86400

	print("Status")
	var g := { "id": "x:1", "title": "Test" }
	check(Backlog.set_status(g, "spiele", now) and g.status == "spiele" and int(g.status_at) == now and not g.has("done_at"),
			"„Spiele ich“ gesetzt, mit Zeitpunkt")
	check(not Backlog.set_status(g, "spiele", now + 5), "derselbe Status noch einmal: keine Änderung")
	check(not Backlog.set_status(g, "quatsch", now), "unbekannter Status wird abgelehnt")
	check(Backlog.set_status(g, "durch", now + day) and int(g.done_at) == now + day, "Durchgespielt merkt sich, wann")
	check(Backlog.set_status(g, "voll", now + 9 * day) and int(g.done_at) == now + day, "von Durchgespielt auf 100 %: das Datum bleibt")
	check(Backlog.set_status(g, "pausiert", now + 10 * day) and not g.has("done_at"), "nicht mehr fertig: kein Datum mehr")
	check(Backlog.set_status(g, "", now) and not g.has("status") and not g.has("status_at"), "Status weg: alles weg")

	print("Sterne und Rezension")
	check(Backlog.set_stars(g, 7) and Backlog.stars_of(g) == 7 and Backlog.stars_text(7) == "3½ von 5", "3½ Sterne")
	check(Backlog.stars_text(10) == "5 von 5" and Backlog.stars_text(1) == "½ von 5" and Backlog.stars_text(0) == Backlog.NO_STARS, "Texte zu halben Sternen")
	check(Backlog.set_stars(g, 99) and Backlog.stars_of(g) == 10, "über 5 Sterne: höchstens 5")
	check(Backlog.set_stars(g, 0) and not g.has("stars"), "0 nimmt die Bewertung weg")
	check(Backlog.set_review(g, "  Großartig\n\tund schwer  ") and Backlog.review_of(g) == "Großartig und schwer", "Rezension gesäubert")
	check(Backlog.set_review(g, "x".repeat(2000)) and Backlog.review_of(g).length() == Backlog.REVIEW_MAX, "Rezension gekürzt")
	check(Backlog.set_review(g, "   ") and not g.has("review"), "leere Rezension: weg")

	print("Tagebuch")
	check(Backlog.add_diary(g, now - day, 3600, "Erster Abend") and Backlog.add_diary(g, now, 0, ""), "zwei Einträge")
	var d := Backlog.diary_of(g)
	check(d.size() == 2 and int(d[0].at) == now and not d[0].has("note") and str(d[1].note) == "Erster Abend" and int(d[1].secs) == 3600,
			"neueste zuerst, Dauer und Notiz")
	check(Backlog.add_diary(g, now, 60, "Zweimal gespeichert") and Backlog.diary_of(g).size() == 2, "gleicher Zeitpunkt ersetzt den Eintrag")
	check(Backlog.has_entry(g, now) and not Backlog.has_entry(g, now + 1), "Eintrag zu einer Runde erkennbar")
	check(not Backlog.add_diary(g, 0, 10, "x"), "ohne Zeitpunkt kein Eintrag")
	for i in Backlog.DIARY_MAX + 20:
		Backlog.add_diary(g, now + 100 + i, 0, "")
	check(Backlog.diary_of(g).size() == Backlog.DIARY_MAX, "höchstens %d Einträge" % Backlog.DIARY_MAX)
	check(Backlog.remove_diary(g, now + 100 + Backlog.DIARY_MAX + 19) and not Backlog.remove_diary(g, 12345), "Eintrag löschen; Unbekanntes tut nichts")

	print("Vorschlag für den Status (nie gesetzt, nur angeboten)")
	var s1 := { "id": "a" }
	check(str(Backlog.suggest(s1, 3600, now - 2 * day, [], now).get("status", "")) == "spiele", "gespielt vor 2 Tagen ohne Status: „Spiele ich“")
	check(not s1.has("status"), "… und nichts gesetzt")
	check(Backlog.suggest(s1, 0, 0, [], now).is_empty(), "nie gespielt: kein Vorschlag")
	var s2 := { "id": "b", "status": "spiele" }
	check(str(Backlog.suggest(s2, 9000, now - 90 * day, [], now).get("status", "")) == "pausiert", "seit 90 Tagen nicht gespielt: „Pausiert“")
	check(str(Backlog.suggest(s2, 9000, now - 90 * day, [42, 42], now).get("status", "")) == "voll", "alle Erfolge: „100 %“ geht vor")
	var s3 := { "id": "c", "status": "abgebrochen" }
	check(Backlog.suggest(s3, 9000, now - day, [42, 42], now).is_empty(), "abgebrochen: kein Vorschlag")
	var s4 := { "id": "d", "status": "durch", "done_at": now }
	check(Backlog.suggest(s4, 9000, now - day, [3, 42], now).is_empty() and str(Backlog.suggest(s4, 9000, now - day, [42, 42], now).get("status", "")) == "voll",
			"durchgespielt: nur noch „100 %“, wenn alles geholt ist")

	print("Was spiele ich heute?")
	var lib: Array = [
		{ "id": "p", "title": "Spiele ich", "status": "spiele" },
		{ "id": "w", "title": "Will ich", "status": "will" },
		{ "id": "w2", "title": "Will ich, fehlt", "status": "will" },
		{ "id": "f", "title": "Fertig", "status": "durch", "done_at": now },
		{ "id": "a", "title": "Abgebrochen", "status": "abgebrochen" },
		{ "id": "h", "title": "Versteckt", "status": "will", "hidden": true },
		{ "id": "n", "title": "Nie gespielt" },
		{ "id": "o", "title": "Gespielt, frisch" },
	]
	var info := { "p": { "playtime": 7200, "last": now - day, "installed": true }, "w": { "installed": true },
		"w2": { "installed": false }, "n": { "installed": true }, "o": { "playtime": 600, "last": now - day, "installed": true } }
	var cands := Backlog.candidates(lib, info, now)
	var ids: Array = cands.map(func(c): return str(c.game.id))
	check(ids.has("p") and ids.has("w") and ids.has("w2"), "Spiele ich und Will ich kommen in Frage")
	check(not ids.has("f") and not ids.has("a") and not ids.has("h"), "nie: fertig, abgebrochen, ausgeblendet")
	check(not ids.has("n") and not ids.has("o"), "mit eigenem Backlog nur aus dem Backlog – nichts ohne Status")
	var plain: Array = lib.map(func(x): return { "id": x.id, "title": x.title })
	var loose_ids: Array = Backlog.candidates(plain, info, now).map(func(c): return str(c.game.id))
	check(loose_ids.has("n") and not loose_ids.has("o"), "ohne Backlog: Unberührtes (installiert), nicht gerade erst Gespieltes")
	var cw2: Array = cands.filter(func(c): return str(c.game.id) == "w2")
	var cw: Array = cands.filter(func(c): return str(c.game.id) == "w")
	check(not cw2.is_empty() and float(cw2[0].weight) < float(cw[0].weight) and str(cw2[0].why).contains("noch nicht installiert"),
			"nicht installiert: seltener und mit Hinweis")
	var cp: Array = cands.filter(func(c): return str(c.game.id) == "p")
	check(str(cp[0].why) == "Du spielst es gerade · zuletzt gestern", "erklärbar: „weil …“ (%s)" % str(cp[0].why))
	var p1 := Backlog.pick_today(cands, 7)
	check(not p1.is_empty() and Backlog.pick_today(cands, 7).game == p1.game, "gleicher Wurf, gleicher Vorschlag")
	var seen := {}
	var skip: Array = []
	for i in cands.size():
		var p := Backlog.pick_today(cands, 7 + i, skip)
		seen[str(p.game.id)] = true
		skip.append(str(p.game.id))
	check(seen.size() == cands.size(), "Würfeln geht der Reihe nach alle durch (%d von %d)" % [seen.size(), cands.size()])
	check(Backlog.pick_today([], 1).is_empty(), "ohne Kandidaten: kein Vorschlag")

	print("Jahresziel")
	var y := Backlog.year_of(now)
	var jan1 := int(Time.get_unix_time_from_datetime_dict({ "year": y, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0 }))
	var lib2: Array = [
		{ "id": "1", "status": "durch", "done_at": jan1 + 5 * day },
		{ "id": "2", "status": "voll", "done_at": jan1 + 40 * day },
		{ "id": "3", "status": "durch", "done_at": jan1 - 3 * day },
		{ "id": "4", "status": "pausiert", "done_at": jan1 + 50 * day },
	]
	check(_ids(Backlog.done_in(lib2, y)) == ["2", "1"], "durchgespielt in %d: nur dieses Jahr, neueste zuerst; ein altes Datum ohne Status zählt nicht" % y)
	var st := Backlog.goal_state(lib2, y, 12, now)
	check(int(st.done) == 2 and int(st.left) == 10 and is_equal_approx(float(st.frac), 2.0 / 12.0), "2 von 12")
	check(int(st.ahead) < 0 and Backlog.goal_text(st).contains("hinter dem Plan"), "im September mit 2 von 12: ruhig „hinter dem Plan“")
	var st2 := Backlog.goal_state(lib2, y, 2, now)
	check(Backlog.goal_text(st2).begins_with("Ziel erreicht"), "Ziel erreicht")
	check(Backlog.goal_state(lib2, y - 1, 5, now).ahead == 0, "vergangenes Jahr: kein Tempo")
	check(Backlog.clean_goals({ "2026": 12, "abc": 3, "1800": 4, "2027": -1, "2028": 9999 }) == { "2026": 12, "2028": Backlog.GOAL_MAX },
			"Ziele beim Laden geprüft")

	print("Listen")
	var lists: Array = []
	var l1 := Backlog.new_list(lists, "  Couch\nAbende ", now)
	check(str(l1.name) == "Couch Abende" and str(l1.id).begins_with("l_") and lists.size() == 1, "neue Liste, Name gesäubert")
	check(Backlog.new_list(lists, "   ", now).is_empty(), "ohne Namen keine Liste")
	check(Backlog.list_toggle(l1, "a", true) and Backlog.list_toggle(l1, "b", true) and Backlog.list_toggle(l1, "c", true)
			and not Backlog.list_toggle(l1, "a", true), "drei Spiele, keins doppelt")
	check(Backlog.list_move(l1, "c", -1) and l1.games == ["a", "c", "b"], "nach oben")
	check(not Backlog.list_move(l1, "a", -1) and not Backlog.list_move(l1, "b", 1), "am Rand: nichts")
	check(Backlog.list_toggle(l1, "c", false) and l1.games == ["a", "b"], "heraus")
	var dirty := [{ "id": "l_x", "name": "Gut", "games": ["a", "a", 7, ""] }, { "id": "l_x", "name": "Doppelt" }, { "name": "Ohne ID" }, "kaputt",
			{ "id": "l_y", "name": "" }]
	var clean := Backlog.clean_lists(dirty)
	check(clean.size() == 1 and clean[0].games == ["a", "7"], "Listen beim Laden geprüft")

	print("Bibliothek: Speichern, Laden, Einlesen")
	Library.load_demo()
	var er := Library.get_game("steam:1245620")
	check(Backlog.status_of(er) == "spiele" and Backlog.stars_of(er) == 9 and Backlog.diary_of(er).size() == 2,
			"Demo: Elden Ring „Spiele ich“, 4½ Sterne, zwei Tagebuch-Einträge")
	check(Library.lists.size() == 2 and int(Library.goals.get(str(Time.get_date_dict_from_system().year), 0)) == 12, "Demo: zwei Listen und ein Jahresziel")
	for k in Backlog.FIELDS:
		check(k in Library.USER_FIELDS, "„%s“ bleibt beim Einlesen" % k)
	var found := (er as Dictionary).duplicate(true)
	for k in Backlog.FIELDS:
		found.erase(k)
	Library._merge([found], ["steam"])
	er = Library.get_game("steam:1245620")
	check(Backlog.status_of(er) == "spiele" and Backlog.review_of(er) != "", "neu eingelesen: Status und Rezension sind noch da")
	var changes := [0]
	var on_changed := func() -> void: changes[0] += 1
	Library.changed.connect(on_changed)
	check(Library.set_status("steam:1245620", "durch") and changes[0] == 1 and int(er.done_at) > 0, "Library.set_status meldet einmal")
	check(not Library.set_status("steam:1245620", "durch") and changes[0] == 1, "noch einmal: keine Meldung")
	check(not Library.set_status("gibt:esnicht", "will"), "unbekanntes Spiel: nichts")
	var ps2: Array = Library.visible_games().filter(func(x): return str(x.get("system", "")) == "ps2").slice(0, 3)
	var pids: Array = ps2.map(func(x): return str(x.id))
	check(Library.update_many(pids, "status", "will") >= 1 and pids.all(func(i): return Backlog.status_of(Library.get_game(i)) == "will"),
			"viele auf einmal: Status „Will ich spielen“")
	Library.changed.disconnect(on_changed)
	var lc := [0]
	var on_lists := func() -> void: lc[0] += 1
	Library.backlog_changed.connect(on_lists)
	var nl := Library.new_list("Neu", "steam:1245620")
	check(not nl.is_empty() and lc[0] == 1 and Library.list_games(str(nl.id)).size() == 1, "neue Liste mit erstem Spiel, eine Meldung")
	var gone := Library.delete_list(str(nl.id))
	check(gone.size() == 2 and Library.list_by_id(str(nl.id)).is_empty(), "Liste gelöscht")
	Library.put_list(gone[0], gone[1])
	check(not Library.list_by_id(str(nl.id)).is_empty() and Library.lists[gone[1]].id == nl.id, "Rückgängig: an ihrem Platz zurück")
	Library.set_list_games(str(nl.id), ["b", "a", "a"])
	check(Library.list_by_id(str(nl.id)).games == ["b", "a"], "Reihenfolge zurücksetzen (Rückgängig), ohne Doppelte")
	Library.backlog_changed.disconnect(on_lists)
	# Speichern und wieder laden (kein Demo-Modus, eigener Datenordner).
	Library.demo = false
	Library.set_goal(2030, 7)
	Library.save()
	var games_before := Library.games.size()
	Library.games = []
	Library.lists = []
	Library.goals = {}
	Library.load_library()
	check(Library.games.size() == games_before and Backlog.status_of(Library.get_game("steam:1245620")) == "durch", "gespeichert und geladen: Status")
	check(Library.lists.size() == 3 and int(Library.goals.get("2030", 0)) == 7, "gespeichert und geladen: Listen und Ziele")
	# Persönliches (Backlog) steht seit den Profilen in spieler.json des Profils (src/core/profiles.gd).
	var raw: Variant = Config.read_json(Config.path("spieler.json"), {})
	var gid := str(Library.games[0].id)
	if not (raw.games as Dictionary).has(gid):
		raw.games[gid] = {}
	raw.games[gid]["status"] = "unsinn"
	raw.games[gid]["stars"] = "viele"
	raw.games[gid]["diary"] = [{ "at": "gestern" }, { "at": 5, "note": "ok\nzeile" }]
	Config.write_json(Config.path("spieler.json"), raw)
	Library.load_library()
	var g0: Dictionary = Library.games[0]
	check(not g0.has("status") and not g0.has("stars") and Backlog.diary_of(g0).size() == 1 and str(Backlog.diary_of(g0)[0].note) == "ok zeile",
			"von Hand kaputt geändert: nur Gültiges bleibt")
	Library.load_demo()

	print("Filter und Abschnitte")
	var all := Library.visible_games()
	var playing := GameFilter.apply(all, { "status": "spiele" })
	check(not playing.is_empty() and playing.all(func(x): return Backlog.status_of(x) == "spiele"), "Filter „Spiele ich“ (%d)" % playing.size())
	var none := GameFilter.apply(all, { "status": "?" })
	check(none.size() + all.filter(func(x): return Backlog.status_of(x) != "").size() == all.size(), "„Ohne Status“ ergänzt sich mit den anderen")
	check(GameFilter.apply(all, { "stars": "5" }).all(func(x): return Backlog.stars_of(x) == 10) and GameFilter.apply(all, { "stars": "ge4" }).size() >= 4,
			"Filter nach Sternen")
	check(_titles(GameFilter.apply(all, { "stars": "lt3" })) == ["Battlefield 2042"], "unter 3 Sternen: nur das abgebrochene Battlefield")
	var parts := GameFilter.groups(all, "status")
	check(str(parts[0].title) == "Spiele ich" and str(parts[parts.size() - 1].title) == Backlog.NO_STATUS and bool(parts[parts.size() - 1].unknown),
			"Abschnitte nach Status: „Spiele ich“ zuerst, „Ohne Status“ am Ende")
	var sp := GameFilter.groups(all, "stars")
	check(str(sp[0].title) == "5 von 5" and str(sp[sp.size() - 1].title) == Backlog.NO_STARS, "Abschnitte nach Bewertung: beste zuerst")
	var fc := GameFilter.facets(all)
	check(int((fc.status as Dictionary).get("will", 0)) >= 3 and (fc.stars as Dictionary).has("ge4"), "Auswahl zählt Status und Sterne")
	check(GameFilter.summary({ "status": "will", "stars": "ge4" }) == "Will ich spielen · Ab 4 Sternen", "Kopfzeile")
	check(GameFilter.clean({ "status": "will", "stars": "ge4" }) == { "status": "will", "stars": "ge4" }
			and GameFilter.clean({ "status": "x", "stars": "y" }).is_empty(), "gespeicherte Ansichten: nur gültige Werte")

	print("Viele Spiele, schnell")
	var big: Array = []
	for i in 3000:
		var e := { "id": "pc:%d" % i, "title": "Spiel %d" % i, "source": "pc", "system": "pc" }
		if i % 4 != 0:
			e["status"] = Backlog.STATUSES[i % Backlog.STATUSES.size()][0]
		if i % 3 == 0:
			e["stars"] = 1 + i % 10
		big.append(e)
	var binfo := {}
	for e in big:
		binfo[e.id] = { "playtime": 0, "last": 0, "installed": true }
	var t0 := Time.get_ticks_usec()
	GameFilter.groups(big, "status")
	GameFilter.facets(big)
	var bc := Backlog.candidates(big, binfo, now)
	Backlog.pick_today(bc, 3)
	var t1 := Time.get_ticks_usec()
	print("    Abschnitte, Auswahl und Vorschlag für 3000 Spiele: %.1f ms" % ((t1 - t0) / 1000.0))
	check(t1 - t0 < 250000, "schnell genug (unter 250 ms)")

	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _ids(list: Array) -> Array:
	return list.map(func(x): return str(x.id))

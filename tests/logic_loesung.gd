extends Node
## Lösungshilfe (Punkt 111): Suchbegriff je Spiel und Sprache, eigene Suchwörter säubern und
## merken, Treffer auswählen, Vorführung, Kachel im Guide. Ohne Netz.
## Aufruf: godot --headless --path . res://tests/logic_loesung.tscn

const W := preload("res://src/core/walkthrough.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_query()
	_terms()
	_pick()
	_demo()
	_guide()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _query() -> void:
	print("Suchbegriff")
	check(W.query("Elden Ring", "komplett", "", "de") == "Elden Ring Komplettlösung deutsch", "Deutsch: Komplettlösung auf Deutsch")
	check(W.query("Elden Ring", "komplett", "", "en") == "Elden Ring full walkthrough", "Englisch: walkthrough")
	check(W.query("Elden Ring", "bosse", "", "de").ends_with("alle Bosse Guide deutsch"), "Thema Bosse")
	check(W.query("Elden Ring", "gibtsnicht", "", "en") == "Elden Ring full walkthrough", "unbekanntes Thema: Komplettlösung")
	check(W.query("Elden Ring", "", "Boss Malenia", "de") == "Elden Ring Boss Malenia Guide deutsch", "eigenes Suchwort bekommt Guide und deutsch")
	check(W.query("Elden Ring", "", "Boss Malenia", "en") == "Elden Ring Boss Malenia guide", "eigenes Suchwort englisch")
	check(W.query("Elden Ring", "", "Malenia Lösung deutsch", "de") == "Elden Ring Malenia Lösung deutsch",
			"schon nach Lösung und Deutsch gefragt: nichts doppelt")
	check(W.query("Elden Ring", "", "malenia guide", "en") == "Elden Ring malenia guide", "englisch: guide nicht doppelt")
	check(W.query("", "komplett", "", "de") == "", "ohne Spielnamen keine Suche")
	check(W.clean_title("DOOM™ Eternal®") == "DOOM Eternal", "Marken-Zeichen fallen weg")
	check(W.clean_title("Shadow of the Colossus (Europe) [!]") == "Shadow of the Colossus", "Klammern aus Dateinamen fallen weg")
	check(W.clean_title("x".repeat(200)).length() == W.TITLE_MAX, "Spielname gekürzt")
	check(W.clean_term("  Boss\tMalenia \n ") == "Boss Malenia", "Suchwort: Steuerzeichen und Leerzeichen")
	check(W.clean_term("a".repeat(100)).length() == W.TERM_MAX, "Suchwort gekürzt")
	check(W.query("Elden Ring", "", "x".repeat(500), "de").length() <= 160, "Suchbegriff nie endlos")


func _terms() -> void:
	print("Gemerkte Suchwörter")
	var e: Array = []
	e = W.remember(e, "steam:1", "Malenia", 100)
	e = W.remember(e, "steam:1", "Radahn", 110)
	check(W.terms_of(e, "steam:1") == ["Radahn", "Malenia"], "neueste zuerst")
	e = W.remember(e, "steam:1", "malenia", 120)
	check(W.terms_of(e, "steam:1") == ["malenia", "Radahn"], "schon da (Groß/klein egal): nach vorn, nicht doppelt")
	for i in 10:
		e = W.remember(e, "steam:1", "Wort %d" % i, 200 + i)
	check(W.terms_of(e, "steam:1").size() == W.TERMS_MAX and str(W.terms_of(e, "steam:1")[0]) == "Wort 9", "höchstens TERMS_MAX je Spiel")
	e = W.remember(e, "ps2:sotc", "Koloss 13", 300)
	check(W.terms_of(e, "ps2:sotc") == ["Koloss 13"] and W.terms_of(e, "steam:1").size() == W.TERMS_MAX, "je Spiel getrennt")
	check(W.terms_of(e, "gibtsnicht").is_empty() and W.terms_of(e, "").is_empty(), "fremdes Spiel: nichts")
	var before := e.duplicate(true)
	var e2 := W.remember(e, "steam:1", "   ", 400)
	check(e2 == before and e == before, "leeres Suchwort ändert nichts, Eingabe bleibt unberührt")
	var many: Array = []
	for i in W.GAMES_MAX + 5:
		many = W.remember(many, "g:%d" % i, "x", i)
	check(many.size() == W.GAMES_MAX and W.terms_of(many, "g:0").is_empty() and not W.terms_of(many, "g:%d" % (W.GAMES_MAX + 4)).is_empty(),
			"höchstens GAMES_MAX Spiele, die ältesten fallen raus")
	var f := W.forget(e, "ps2:sotc", "KOLOSS 13")
	check(W.terms_of(f, "ps2:sotc").is_empty() and not f.any(func(x): return str(x.get("game", "")) == "ps2:sotc"), "vergessen: letztes Wort weg, Spiel weg")
	f = W.forget(e, "steam:1", "Wort 9")
	check(not W.terms_of(f, "steam:1").has("Wort 9") and W.terms_of(f, "steam:1").size() == W.TERMS_MAX - 1, "vergessen: nur dieses Wort")
	var broken: Variant = [{ "game": "steam:1", "terms": [42, "", "  ok  ", "OK", null, "x".repeat(100)] }, "kaputt", { "game": 7 }]
	check(W.terms_of(broken, "steam:1") == ["ok", "x".repeat(W.TERM_MAX)], "von Hand geändert: Kaputtes fällt weg")
	check(W.terms_of("kein Array", "steam:1").is_empty() and W.remember(null, "steam:1", "a", 1).size() == 1, "kaputter Speicher: neu anfangen")


func _pick() -> void:
	print("Treffer")
	var found := [
		{ "id": "aaaaaaaaaaa", "title": "Lösung", "channel": "K", "duration": 3725 },
		{ "id": "aaaaaaaaaaa", "title": "doppelt" },
		{ "id": "bbbbbbbbbbb", "title": "Short", "short": true },
		{ "id": "ccccccccccc", "title": "Live", "live": true },
		"kaputt",
		{ "id": "", "title": "ohne ID" },
		{ "id": "ddddddddddd", "title": "Guide", "channel": "", "duration": 95 },
	]
	var p := W.pick(found)
	check(p.size() == 2 and str(p[0].id) == "aaaaaaaaaaa" and str(p[1].id) == "ddddddddddd", "nur echte Videos, jedes einmal")
	check(bool(p[0].get("help", false)) and not (found[0] as Dictionary).has("help"), "als Lösungshilfe markiert, Eingabe unberührt")
	var lots: Array = []
	for i in 40:
		lots.append({ "id": "v%010d" % i, "title": "T" })
	check(W.pick(lots).size() == W.RESULTS_MAX, "höchstens RESULTS_MAX")
	check(W.line_of(p[0]) == "K  ·  1:02:05" and W.line_of(p[1]) == "1:35", "Zeile: Kanal und Länge")


func _demo() -> void:
	print("Vorführung")
	var d: Variant = Config.read_json("res://tests/demo_youtube.json", {})
	var er := W.demo_results(d, "ELDEN RING™", "")
	check(er.size() >= 4 and er.all(func(v): return str(v.game) == "Elden Ring"), "Treffer zum Spiel")
	var mal := W.demo_results(d, "Elden Ring", "Boss Malenia")
	check(not mal.is_empty() and str(mal[0].title).contains("Malenia") and mal.size() == er.size(), "Suchwort zuerst, die anderen dahinter")
	check(str(W.demo_results(d, "Elden Ring", "Bosse")[0].title).contains("Bosse"), "Thema: passende Treffer zuerst")
	check(W.demo_results(d, "Elden Ring", "und der").size() == er.size(), "kurze Wörter ordnen nichts um")
	check(W.demo_results(d, "Tetris", "").is_empty() and W.demo_results({}, "Elden Ring", "").is_empty(), "fremdes Spiel oder keine Daten: nichts")
	var ids := {}
	for v in (d as Dictionary).get("help_videos", []):
		check(YouTube.valid_id(str(v.id)) and not ids.has(v.id), "Beispiel-ID gültig: %s" % str(v.id))
		ids[v.id] = true


func _guide() -> void:
	print("Guide")
	check(GuideGame.CHOICES.any(func(c): return str(c[0]) == "help" and str(c[2]) == "bulb"), "als eigene Kachel wählbar")
	check(Icons.P.has("bulb"), "Symbol da")
	var was: bool = Launcher.in_game
	Launcher.in_game = false
	check(not W.available(), "ohne Spiel keine Lösungshilfe")
	Launcher.in_game = was
	var g := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	check(W.lang_now() == "en", "Sprache Englisch")
	TranslationServer.set_locale("de")
	check(W.lang_now() == "de", "Sprache Deutsch")
	TranslationServer.set_locale(g)

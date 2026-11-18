extends Node
## Logiktests für Bühne und Reihen des Shops (ohne Oberfläche und ohne Netz): Auswahl der Bühne,
## Grund-Zeile, Spiele der Freunde, Preiszeile der Karten, alte Unterbereiche.
## Aufruf: godot --headless --path . res://tests/logic_shop_reihen.tscn

const Reihen := preload("res://src/core/store_reihen.gd")
const ShopCard := preload("res://src/ui/components/shop_card.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _spiel(id: int, preis: int, rabatt := 0, extra := {}) -> Dictionary:
	var d := { "appid": id, "name": "Spiel %d" % id, "price": preis, "discount": rabatt,
		"original": int(round(preis * 100.0 / (100 - rabatt))) if rabatt > 0 and rabatt < 100 else preis, "free": false }
	d.merge(extra, true)
	return d


func _ready() -> void:
	var now := 1_800_000_000
	print("Bühne")
	var specials := [_spiel(1, 999, 20), _spiel(2, 1999, 60), _spiel(3, 500, 75)]
	var top := [_spiel(4, 2999), _spiel(2, 1999, 60), _spiel(5, 3999)]
	var neu := [_spiel(6, 2499), _spiel(4, 2999)]
	var gratis := [_spiel(7, 0, 100, { "giveaway": true, "free": true, "original": 1499 })]
	var freunde := [_spiel(8, 5999), _spiel(3, 500, 75)]
	var b := Reihen.buehne(specials, top, neu, gratis, freunde, { 3: true })
	check(b.size() == 6, "höchstens sechs Spiele (%d)" % b.size())
	check(int(b[0].appid) == 2, "der größte Rabatt zuerst (nicht das Spiel aus der Bibliothek)")
	check(int(b[1].appid) == 8 and int(b[2].appid) == 7 and int(b[3].appid) == 6, "dann ein Spiel der Freunde, das Gratis-Spiel, das neueste")
	var ids: Array = b.map(func(x: Dictionary) -> int: return int(x.appid))
	check(not ids.has(3), "Spiele aus der Bibliothek bleiben weg")
	check(ids.size() == ids.filter(func(x: int) -> bool: return ids.count(x) == 1).size(), "nichts doppelt")
	var klein := Reihen.buehne([], [_spiel(9, 999)], [], [], [], { 9: true })
	check(klein.size() == 1 and int(klein[0].appid) == 9, "fast alles gehört dir: dann auch aus der Bibliothek, nie leer")
	check(Reihen.buehne([], [], [], [], [], {}).is_empty(), "ohne Daten: leer")
	var epic := { "store": "epic", "appid": 0, "id": "epic:x", "name": "Gratis bei Epic", "giveaway": true, "free": true, "price": 0 }
	var mit_epic := Reihen.buehne([], [], [], [epic], [], {})
	check(mit_epic.size() == 1 and Reihen.key_of(epic) == "epic:x", "Gratis-Spiel von Epic (ohne App-ID) kommt mit")

	print("Grund-Zeile")
	var g := Reihen.grund(_spiel(2, 1999, 60, { "until": now + 5 * 3600 }), { "now": now })
	check(g.size() == 2 and str(g[0]) == "Angebot" and str(g[1]) == "endet in 5 Std.", "Angebot mit Frist in Stunden: %s" % str(g))
	var g2 := Reihen.grund(_spiel(2, 1999, 60, { "until": now + 10 * 86400 }), { "now": now })
	check(g2.size() == 2 and str(g2[1]).begins_with("bis "), "Angebot mit Datum: %s" % str(g2))
	check(Reihen.grund(_spiel(2, 1999, 60, { "until": now - 10 }), { "now": now }) == ["Angebot"], "abgelaufene Frist steht nicht mehr da")
	check(Reihen.grund(_spiel(1, 999), { "owned": true, "freunde": ["Mira"] }) == ["In deiner Bibliothek", "Mira spielt gerade"],
			"in der Bibliothek, und wer es spielt")
	check(Reihen.grund(_spiel(1, 999), { "freunde": ["Mira", "Noor"] }) == ["Topseller", "Mira und Noor spielen gerade"], "zwei Freunde mit Namen")
	check(Reihen.grund(_spiel(1, 999), { "freunde": ["A", "B", "C"] }) == ["Topseller", "3 Freunde spielen gerade"], "drei Freunde als Zahl")
	check(Reihen.grund(_spiel(1, 999), { "neu": true, "wunsch": true }) == ["Neu", "Auf deiner Wunschliste"], "neu und auf der Wunschliste")
	check(Reihen.grund(_spiel(1, 0, 0, { "coming": true }), {}) == ["Bald erhältlich"], "bald erhältlich")
	check(Reihen.grund(_spiel(1, 0, 0, { "free": true }), {}) == ["Kostenlos spielbar"], "kostenlos spielbar")
	var gg := Reihen.grund(gratis[0].merged({ "until": now + 3600 }), { "now": now })
	check(gg == ["Gratis", "endet in 1 Std."], "Gratis-Aktion mit Frist: %s" % str(gg))
	check(Reihen.grund({ "giveaway": true, "upcoming": true, "from": now + 86400 }, { "now": now })[0].begins_with("Ab "), "angekündigte Gratis-Aktion")
	check(Reihen.frist(0, now) == "" and Reihen.frist(now + 100, now) == "endet in 1 Std.", "Frist: ohne Ende nichts, knapp mindestens 1 Std.")

	print("Spiele der Freunde")
	var friends := [
		{ "id": "1", "name": "Mira", "state": "game", "game": "ELDEN RING", "game_id": "1245620" },
		{ "id": "2", "name": "Jonas", "state": "game", "game": "Hollow Knight", "game_id": "367520" },
		{ "id": "3", "name": "Lea", "state": "online", "game": "", "game_id": "" },
		{ "id": "4", "name": "Noor", "state": "game", "game": "ELDEN RING", "game_id": "1245620" },
		{ "id": "5", "name": "Kaputt", "state": "game", "game": "x", "game_id": "abc" },
		"kaputt",
	]
	check(Reihen.freunde_ids(friends) == [1245620, 367520], "App-IDs der gespielten Spiele, jede einmal, nur Zahlen")
	check(Reihen.freunde_namen(friends, 1245620) == ["Mira", "Noor"] and Reihen.freunde_namen(friends, 5).is_empty(), "wer welches Spiel spielt")
	check(Reihen.freunde_text([]) == "" and Reihen.freunde_text(["Mira"]) == "Mira spielt gerade", "Satz für eine Person")
	var items := [_spiel(367520, 1499), _spiel(1245620, 5999), _spiel(99, 100)]
	var reihe := Reihen.freunde_reihe(items, friends, { 1245620: true })
	check(reihe.size() == 2 and int(reihe[0].appid) == 367520 and int(reihe[1].appid) == 1245620, "Reihe: erst, was du nicht hast, dann der Rest; nur gespielte Spiele")
	check(Reihen.freunde_reihe([], friends, {}).is_empty(), "ohne Einträge: leer")

	print("Preiszeile der Karten")
	var pz := ShopCard.preis_zeile(_spiel(1, 1249, 50), false)
	check(str(pz.text) == "12,49 €" and str(pz.alt) == "24,98 €" and str(pz.farbe) == "text", "Preis mit altem Preis: %s" % str(pz))
	check(ShopCard.preis_zeile(_spiel(1, 1249), false).alt == "", "ohne Rabatt kein alter Preis")
	check(ShopCard.preis_zeile(_spiel(1, 1249), true).text == "In deiner Bibliothek" and ShopCard.preis_zeile(_spiel(1, 1249), true).farbe == "ok", "in der Bibliothek")
	check(ShopCard.preis_zeile({ "free": true, "price": 0 }, false).text == "Kostenlos", "kostenlos nur mit echtem is_free")
	check(ShopCard.preis_zeile({ "price": 0, "coming": true }, false).text == "Bald erhältlich", "bald erhältlich")
	check(ShopCard.preis_zeile({ "price": 0 }, false).text == "", "ohne Preis: nichts Erfundenes")
	var gz := ShopCard.preis_zeile(gratis[0], false)
	check(str(gz.text).begins_with("Gratis") and str(gz.alt) == "14,99 €" and str(gz.farbe) == "sale", "Gratis-Aktion mit altem Preis: %s" % str(gz))

	print("Unter 10 € und alte Unterbereiche")
	var billig := Reihen.unter_preis([_spiel(1, 999), _spiel(2, 1999), _spiel(3, 499), _spiel(4, 1000), _spiel(5, 300)], { 5: true })
	check(billig.size() == 3 and int(billig[0].appid) == 3 and int(billig[2].appid) == 4, "unter 10 €, günstigste zuerst, ohne Bibliothek")
	check(Reihen.unter_preis([_spiel(1, 999), _spiel(2, 500)], {}).is_empty(), "unter drei Spielen keine Reihe")
	check(Reihen.ziel("top_sellers") == ["entdecken", "top_sellers"] and Reihen.ziel("gratis") == ["specials", ""], "alte Ziele führen an ihre Stelle")
	check(Reihen.ziel("genres") == ["entdecken", ""] and Reihen.ziel("wunschliste") == ["wunschliste", ""], "Genres in Entdecken, heutige Namen bleiben")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

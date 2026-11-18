extends Node
## Globale Suche (Punkt 105): Rangfolge, Tippfehler, Umlaute, Anfangsbuchstaben – mit den Spielen
## der Demo-Bibliothek. Aufruf: godot --headless --path . res://tests/logic_suche.tscn

const Search := preload("res://src/core/search.gd")

var fails := 0
var titles: Array = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/demo_library.json"))
	for g in (d.games if d is Dictionary else d):
		titles.append(str(g.title))
	print("Schreibweisen")
	check(Search.norm("Ōkami") == "okami" and Search.norm("Pokémon: Smaragd!") == "pokemon smaragd", "Akzente und Satzzeichen")
	check(Search.norm("Final Fantasy VII") == "final fantasy 7" and Search.norm("Diablo IV") == "diablo 4", "römische Zahlen als Ziffern")
	check(Search.score("uebersicht", "Übersicht") > 0 and Search.score("ubersicht", "Übersicht") > 0 and Search.score("Übersicht", "Übersicht") == Search.EXACT,
			"Umlaut mit und ohne Punkte, als ue")
	check(Search.distance("zelda", "zedla") == 1 and Search.distance("ring", "rign") == 1 and Search.distance("", "abc") == 3, "Abstand mit Vertauschen")
	print("Rangfolge")
	check(_top("okami") == ["Ōkami"], "okami → Ōkami")
	check(_top("hades")[0] == "Hades", "genau vor allem anderen")
	check(_top("pokemon") == ["Pokémon Smaragd"], "ohne Akzent")
	check(_top("kart") == ["Mario Kart: Double Dash!!"], "Wortanfang mitten im Namen")
	check(_top("zelda wind")[0] == "The Legend of Zelda: The Wind Waker", "mehrere Wörter, Reihenfolge egal")
	check(_top("wind zelda")[0] == "The Legend of Zelda: The Wind Waker", "… auch umgekehrt")
	var mgs := _top("mgs")
	check(mgs.size() == 2 and mgs[0] == "Metal Gear Solid", "Anfangsbuchstaben, kürzerer Name zuerst")
	check(_top("ff7") == ["Final Fantasy VII"], "Anfangsbuchstaben mit Zahl (ff7)")
	check(_top("battlefront 2") == ["Star Wars Battlefront II"], "Ziffer für römische Zahl")
	check(_top("eldn ring") == ["Elden Ring"] and _top("zedla").size() == 3, "ein Tippfehler je Wort")
	check(_top("hdes") == ["Hades"] and _top("xq").is_empty() and _top("hds").is_empty(), "Tippfehler erst ab 4 Buchstaben, Unsinn findet nichts")
	print("       met → ", _top("met"))
	print("Gleich gute Treffer")
	var weights := { "The Legend of Zelda: Breath of the Wild": 3.0, "The Legend of Zelda: The Minish Cap": 1.0, "The Legend of Zelda: The Wind Waker": 2.0 }
	var z := Search.best(titles, "zelda", func(t): return t, func(t): return weights.get(t, 0.0), 5)
	check(z == ["The Legend of Zelda: Breath of the Wild", "The Legend of Zelda: The Wind Waker", "The Legend of Zelda: The Minish Cap"],
			"zuletzt Gespieltes zuerst")
	check(Search.best(titles, "", func(t): return t, Callable(), 5).is_empty(), "leere Eingabe: nichts")
	print("Vorbereitet (beim Tippen)")
	var prep := Search.prepare(titles, func(t): return t)
	check(Search.rank(prep, "zelda", 3) == _top("zelda").slice(0, 3) and Search.rank(prep, "zelda", 0).size() == 3, "rank = best, 0 = alle")
	var many: Array = []
	for i in 3000:
		many.append("%s %s %d" % [titles[i % titles.size()], ["Deluxe", "Remastered", "Gold", "Ultimate"][i % 4], i])
	var t0 := Time.get_ticks_usec()
	var big := Search.prepare(many, func(t): return t)
	var t1 := Time.get_ticks_usec()
	var hits := Search.rank(big, "zedla wind", 0)
	var t2 := Time.get_ticks_usec()
	print("       3000 Namen: vorbereiten %d ms, eine Eingabe %d ms" % [(t1 - t0) / 1000, (t2 - t1) / 1000])
	check(hits.size() > 0 and str(hits[0]).begins_with("The Legend of Zelda: The Wind Waker"), "3000 Namen, Tippfehler und zwei Wörter")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _top(q: String) -> Array:
	return Search.best(titles, q, func(t): return t, Callable(), 6)

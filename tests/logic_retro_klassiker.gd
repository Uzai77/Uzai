extends Node
## Reihe „Retro-Klassiker“ im Shop ohne Bildschirm und ohne Netz: welche Shop-Treffer passen,
## Prüfung des Zwischenspeichers, Regel R5 (keine Adressen) und welche Systeme als Retro gelten.
## Aufruf: godot --headless --path . res://tests/logic_retro_klassiker.tscn

const RK := preload("res://src/core/retro_klassiker.gd")
const RS := preload("res://src/core/retro_systeme.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Retro-Systeme")
	check(RS.is_retro_game({ "source": "rom", "system": "gba" }) and RS.is_retro_game({ "source": "disc", "system": "ps2" }), "Emulator- und Disc-Spiele zählen")
	check(not RS.is_retro_game({ "source": "steam", "system": "steam" }) and not RS.is_retro_game({ "source": "rom", "system": "switch" }),
			"Steam und Switch nicht")
	var known_ids: Array = Config.systems().map(func(x: Dictionary) -> String: return str(x.id))
	check(RS.SYSTEME.all(func(k: String) -> bool: return known_ids.has(k)), "jedes Retro-System gibt es in data/systems.json")
	check(not ResourceLoader.exists("res://src/ui/layers/retro_system.gd") and not ResourceLoader.exists("res://src/core/retro_katalog.gd")
			and not ResourceLoader.exists("res://src/ui/components/console_art.gd"), "Retro-Katalog und Konsolen-Zeichnungen sind weg")

	print("Retro-Klassiker: was passt")
	check(RK.legal_match("Ōkami", "Okami HD"), "Okami → Okami HD")
	check(RK.legal_match("Persona 4", "Persona 4 Golden"), "Persona 4 → Golden")
	check(RK.legal_match("Final Fantasy VII", "FINAL FANTASY VII"), "gleich, andere Schreibung")
	check(not RK.legal_match("Mega Man", "Mega Man 11"), "keine Fortsetzung (Zahl)")
	check(not RK.legal_match("Final Fantasy", "FINAL FANTASY VII"), "keine Fortsetzung (römisch)")
	check(not RK.legal_match("Resident Evil", "Resident Evil Village"), "kein anderes Spiel mit gleichem Anfang")
	check(not RK.legal_match("Silent Hill 2", "SILENT HILL f"), "kein Spiel, dem Wörter fehlen")
	check(RK.legal_match("Tomb Raider I-III Remastered", "Tomb Raider I-III Remastered Starring Lara Croft", true), "Sammlung mit Zusatz im Namen (locker)")
	check(not RK.legal_match("Mega Man X Legacy Collection", "Mega Man X Legacy Collection 2", true), "auch locker: keine zweite Sammlung")
	check(RK.not_a_game("Okami HD Soundtrack") and RK.not_a_game("Sonic Origins - Digital Artbook") and not RK.not_a_game("Sonic Origins"),
			"Soundtrack und Artbook sind keine Spiele")

	print("Retro-Klassiker: Sammlungen")
	check(RK.shop_collections().size() >= 10, "Sammlungen für den Shop")
	check(RK.SAMMLUNGEN.all(func(c: Dictionary) -> bool: return c.keys() == ["suche"]), "nur das Suchwort")
	var hits := [{ "appid": 1, "name": "Okami HD Soundtrack" }, { "appid": 2, "name": "Okami HD" }, { "appid": 0, "name": "Okami" },
		{ "appid": 3, "name": "Okami" }, "kaputt", { "appid": 4, "name": "Okamiden 2" }]
	var picked := RK.pick(hits, "Okami", 2)
	check(_ids(picked) == [3, 2], "genauester Treffer zuerst, Soundtrack und ohne Nummer fallen weg")
	check(RK.pick(hits, "Okami", 1).size() == 1, "höchstens limit")
	check(_ids(RK.merge_unique([[{ "appid": 5 }, { "appid": 6 }], [{ "appid": 6 }, { "appid": 7 }], "x"], 2)) == [5, 6], "jedes Angebot einmal, begrenzt")

	print("Zwischenspeicher (fremde Datei)")
	var clean := RK.clean_cached([{ "appid": 10, "name": "Gut" }, { "appid": "10", "name": "Text" }, { "appid": -1, "name": "x" },
		{ "appid": 999999999, "name": "zu groß" }, { "appid": 11 }, { "appid": 12, "name": "y".repeat(300) }, 42,
			{ "appid": 13.0, "name": "Zahl", "url": "https://böse" }])
	check(_ids(clean) == [10, 13], "nur gültige Einträge (%s)" % str(_ids(clean)))
	check(clean.all(func(it: Dictionary) -> bool: return it.keys().size() == 2), "nur bekannte Felder")
	check(RK.clean_cached("x").is_empty() and RK.clean_cached(null).is_empty(), "kein Array: nichts")
	var many: Array = []
	for i in 50:
		many.append({ "appid": 100 + i, "name": "n" })
	check(RK.clean_cached(many).size() == 20, "höchstens 20 je Suchwort")

	print("Regeln (R4/R5)")
	var bad := false
	for c in RK.SAMMLUNGEN:
		var blob := JSON.stringify(c).to_lower()
		if blob.contains("://") or blob.contains("www.") or blob.contains(".com") or blob.contains(".org"):
			bad = true
	check(not bad, "Sammlungen: nur Namen, keine Adressen")

	print("Demo-Shop")
	Library.demo = true
	var demo: Array = Store._demo_retro()
	check(demo.size() >= 10 and demo.all(func(it: Dictionary) -> bool: return int(it.appid) > 0 and int(it.price) > 0), "Demo: Sammlungen mit Preis")
	var classics: Array = []
	for c in RK.shop_collections():
		classics.append_array(RK.pick(demo, str(c.suche), 1, true))
	check(classics.size() >= 10, "Demo: Reihe Retro-Klassiker findet die Sammlungen (%d)" % classics.size())
	Library.demo = false
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _ids(list: Array) -> Array:
	return list.map(func(it: Variant) -> int: return int((it as Dictionary).get("appid", 0)))

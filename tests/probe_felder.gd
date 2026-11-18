extends "res://tests/probe_base.gd"
## Bildschirm-Probe: eigene Angaben in den Spieloptionen (Tags, Links mit QR), „Deine Angaben“ auf
## der Spielseite, Filter und Abschnitte danach und mehrere Spiele auf einmal bearbeiten.
## Aufruf siehe probe_base.gd.


func run() -> void:
	var all := Library.visible_games()
	var ps2: Array = all.filter(func(g): return g.system == "ps2")
	var sotc: Dictionary = ps2[0]
	var gid := str(sotc.id)
	# Ein paar Angaben wie nach einer Weile Benutzung.
	Library.update_many([str(ps2[1].id), str(ps2[2].id)], "tag_add", "Durchgespielt")
	Library.update_many([str(ps2[2].id), str(ps2[3].id), str(ps2[4].id)], "category", "Lieblinge")

	main.open_game_options(sotc)
	await wait(0.8)
	await _focus("opt:Tags")
	await shot("01_optionen_eigene_angaben", 0.6)
	await press("a")
	await shot("02_tags_leer", 0.8)
	await _focus("tag:Durchgespielt")
	await press("a")
	await shot("03_tag_vorschlag_genommen", 0.8)
	Library.set_field(gid, "tags", ["Durchgespielt", "Koop", "Couch"])
	(Nav.top_layer() as Object).call("refill")
	await shot("04_tags_drei", 0.8)
	await press("b")
	Library.set_field(gid, "category", "Lieblinge")
	Library.set_field(gid, "age", "usk12")
	Library.set_field(gid, "region", "pal")
	Library.set_field(gid, "links", [{ "name": "Lösung", "url": "https://www.ign.com/wikis/shadow-of-the-colossus" },
		{ "name": "", "url": "https://www.speedrun.com/sotc" }])
	(Nav.top_layer() as Object).call("refill")
	await wait(0.4)
	await _focus("opt:Links")
	await shot("05_optionen_ausgefuellt", 0.7)
	await press("a")
	await shot("06_links", 0.8)
	await press("a")
	await shot("07_link_qr", 1.0)
	await press("b")
	await wait(0.4)
	await press("b")
	await press("b")
	await wait(0.6)

	main.open_game(Library.get_game(gid))
	await wait(1.2)
	await _focus_prefix("gp:link:")
	await shot("08_spielseite_deine_angaben", 1.0)
	await press("b")
	await wait(0.8)

	Config.set_value("library.sort", "title")
	main.open_library("alle", "Alle Spiele")
	await wait(1.0)
	var l: Node = Nav.top_layer()
	l.set("_group", "tag")
	l.call("_refill")
	await shot("09_raster_nach_tag", 1.0)
	await press("y")
	await wait(0.5)
	await _focus("lib:tag")
	await press("right")
	await shot("10_ordnen_tag_filter", 0.9)
	await press("left")
	await _focus("lib:select")
	await shot("11_ordnen_mehrere_auswaehlen", 0.6)
	await press("a")
	await wait(0.9)
	l.set("_group", "")
	l.call("_refill")
	await wait(0.6)
	await press("a")
	await press("right")
	await press("a")
	await press("right")
	await press("a")
	await shot("12_auswahl_drei", 0.8)
	await press("y")
	await shot("13_auswahl_bearbeiten", 0.9)
	await _focus("bulk:Eigene Angaben")
	await press("a")
	await wait(0.8)
	await _focus("bulk:Tag hinzufügen")
	await press("a")
	await shot("14_tag_waehlen", 0.8)
	await press("down")
	await press("a")
	await shot("15_rueckfrage", 0.8)
	await press("a")
	await shot("16_geaendert", 0.9)
	await press("b")
	await wait(0.6)
	await _focus("bulk:Ordner")
	await press("a")
	await wait(0.5)
	await press("down")
	await press("a")
	await shot("17_ordner_rein_raus", 0.8)
	await press("a")
	await shot("18_ordner_rueckfrage", 0.8)
	await press("b")
	await wait(0.4)
	await press("b")
	await wait(0.6)
	await press("x")
	await shot("19_alle_ausgewaehlt", 0.8)
	await press("b")
	await shot("20_auswahl_beendet", 0.8)


## Das Element mit diesem uz_key in der obersten Ebene wählen (und hinscrollen).
func _focus(key: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")) == key)
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", key)
	await wait(0.35)


func _focus_prefix(prefix: String) -> void:
	var c := _find(Nav.top_layer(), func(n: Node) -> bool: return str(n.get_meta("uz_key", "")).begins_with(prefix))
	if c:
		Nav.focus(c)
	else:
		print("Probe: nicht gefunden: ", prefix)
	await wait(0.35)


func _find(n: Node, f: Callable) -> Control:
	if n == null:
		return null
	if n is Control and f.call(n):
		return n
	for ch in n.get_children():
		var r := _find(ch, f)
		if r:
			return r
	return null

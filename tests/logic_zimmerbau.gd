extends Node
## Einrichten im Zimmer, neu gedacht (direkt im Raum, Hinweise im Bild): eine Tastenzeile wie überall
## (A, Y, X, die kleinen Tasten, B zuletzt), nur was gerade geht (höchstens vier Aktionstasten, darüber
## höchstens zwei), Wand als Feld außerhalb des Raums (keine Ecken), wohin ein Blick fällt (Boden,
## Wand), alles von früher erreichbar – verteilt statt in einer Ecke: Modus-Leiste (Leben, Bauen,
## Foto), Bauen › Raum, Zimmer-Menü (auch „Online“) –, Speicherformat unverändert.
## Aufruf: godot --headless --path . res://tests/logic_zimmerbau.tscn

const TastenUi := preload("res://src/room/tasten_ui.gd")
const Zimmer := preload("res://src/room/zimmer.gd")
const Anpassen := preload("res://src/room/anpassen.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const ModusUi := preload("res://src/room/modus_ui.gd")
const KatalogUi := preload("res://src/room/katalog_ui.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Inhalt := preload("res://src/room/inhalt.gd")
const G := preload("res://src/room/gestalt.gd")
const RegalTafel := preload("res://src/room/regal_tafel.gd")
const Teilen := preload("res://src/room/zimmer_teilen.gd")
const RegalLogik := preload("res://src/library/regal.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Ein Zimmer ohne 3D: nur was die Seiten der Seitenleiste lesen.
class _Stub extends Control:
	var raum: Dictionary = {}
	var modus := "laufen"
	var daten: Dictionary = {}


## Ein Automat über alle Schichten (zimmer_basis.gd ZUSTAENDE_MODUS, gemeldet an src/core/zustand.gd): tools/zustaende.py
## sieht nur zimmer_basis.gd – hier jede Schicht.
func _modus_tabelle() -> void:
	var gesetzt := {}
	var re := RegEx.create_from_string("(?<![.\\w])modus = \"([a-z]*)\"")
	for d in ["zimmer_basis", "zimmer_foto", "zimmer_ansehen", "zimmer_einrichten", "zimmer_umbau", "zimmer_regal", "zimmer"]:
		for m in re.search_all(FileAccess.get_file_as_string("res://src/room/%s.gd" % d)):
			gesetzt[m.get_string(1)] = true
	var modi_tab: Array = Zimmer.ZUSTAENDE_MODUS.keys().filter(func(k: String) -> bool: return k != "*")
	check(gesetzt.size() == modi_tab.size() and modi_tab.all(func(z: String) -> bool: return gesetzt.has(z)),
			"zimmer.modus: jeder Modus, den eine Schicht setzt, steht in der Tabelle (%d)" % modi_tab.size())


func _ready() -> void:
	print("Tastenzeile: Aktionstasten zuerst, B zuletzt")
	var o := TastenUi.ordnen([["a", "Hochheben"], ["y", "Anpassen"], ["x", "Rückgängig"], ["b", "Fertig"], ["lb", ""], ["rb", "Drehen"], ["rt", "Katalog"]])
	check(o.kreuz == { "a": "Hochheben", "y": "Anpassen", "x": "Rückgängig", "b": "Fertig" }, "Aktionstasten erkannt")
	check(o.zeile == [[["lb", "rb"], "Drehen"], [["rt"], "Katalog"]], "LB RB als Paar, RT daneben – bei den kleinen Tasten")
	var o2 := TastenUi.ordnen([["b", "Fertig"], ["b", "Zurück"], ["menu", "Zimmer"], ["menu", "Zimmer"]])
	check(o2.kreuz == { "b": "Fertig" } and o2.zeile.size() == 1, "jede Taste nur einmal")
	var r := TastenUi.reihe([["b", "Fertig"], ["x", "Rückgängig"], ["menu", "Zimmer"], ["a", "Hochheben"], ["y", "Anpassen"], ["lb", ""], ["rb", "Drehen"]])
	check(r.map(func(e): return "+".join(PackedStringArray(e.tasten))) == ["a", "y", "x", "menu", "lb+rb", "b"],
			"Tastenzeile: A, Y, X, dann die kleinen Tasten, B zuletzt")
	check(not bool(r[0].klein) and bool(r[3].klein) and not bool(r[5].klein), "Schulter- und Menütasten leiser und kleiner")

	print("Einrichten: nur was gerade geht")
	var faelle := {
		"leeres Feld": { "rueck": true },
		"Möbel": { "moebel": true, "drehbar": true, "rueck": true },
		"Wandmöbel": { "moebel": true, "drehbar": false },
		"Wand": { "wand": "hinten", "rueck": true },
		"Tragen": { "tragen": true, "farben": 6, "drehbar": true },
		"Tragen ohne Farben": { "tragen": true, "farben": 1, "drehbar": true },
	}
	for name_ in faelle.keys():
		var h := Zimmer.bau_hinweise(faelle[name_])
		var oo := TastenUi.ordnen(h)
		check((oo.kreuz as Dictionary).size() <= 4 and (oo.zeile as Array).size() <= 2 and (oo.kreuz as Dictionary).has("b"),
				"%s: höchstens vier Aktionstasten und zwei darüber, B immer (%s)" % [name_, str(h)])
	var tragen := TastenUi.ordnen(Zimmer.bau_hinweise({ "tragen": true, "farben": 6, "drehbar": true })).kreuz as Dictionary
	check(str(tragen.get("a")) == "Absetzen" and str(tragen.get("x")) == "Wegräumen" and str(tragen.get("y")) == "Farbe" and str(tragen.get("b")) == "Abbrechen",
			"Tragen: A absetzen, X wegräumen, Y Farbe, B zurück")
	check(not TastenUi.ordnen(Zimmer.bau_hinweise({ "tragen": true, "farben": 1 })).kreuz.has("y"), "ohne zweite Farbe kein Y")
	check(not TastenUi.ordnen(Zimmer.bau_hinweise({})).kreuz.has("x"), "nichts zum Rückgängigmachen: kein X")
	var moebel := Zimmer.bau_hinweise({ "moebel": true, "drehbar": true })
	check(moebel.has(["a", "Hochheben"]) and moebel.has(["y", "Aktionen"]) and moebel.has(["rb", "Drehen"]) and moebel.has(["rt", "Katalog"]),
			"am Möbel: hochheben, Aktionen am Möbel, drehen, Katalog")
	check(not Zimmer.bau_hinweise({ "moebel": true, "drehbar": false }).has(["rb", "Drehen"]), "Wandmöbel drehen sich nicht: kein Drehen")
	var leer := Zimmer.bau_hinweise({})
	check(leer.has(["a", "Katalog"]) and leer.has(["y", "Boden"]) and leer.has(["menu", "Zimmer"]), "leeres Feld: Katalog, Boden, Zimmer")
	check(Zimmer.bau_hinweise({ "wand": "links" }).has(["a", "Wand gestalten"]), "Wand: gestalten")

	print("Erst wählen, dann platzieren")
	check(Zimmer.start_feld(Vector2i(4, 3), 12, 10) == Vector2i(4, 3) and Zimmer.start_feld(Vector2i(-1, 3), 12, 10) == Vector2i(0, 3)
			and Zimmer.start_feld(Vector2i(5, 10), 12, 10) == Vector2i(5, 9), "Möbel aus dem Menü erscheint in der Bildmitte, im Raum")
	var quelle := FileAccess.get_file_as_string("res://src/room/zimmer_einrichten.gd")
	var vorschau := quelle.substr(quelle.find("func _katalog_vorschau"), 600)
	check(not vorschau.contains("nehmen("), "Wählen im Menü stellt kein Möbel ins Zimmer (erst A)")
	var basis := FileAccess.get_file_as_string("res://src/room/zimmer_basis.gd")
	var schild := basis.substr(basis.find("func _schild_aktion"), 1800)
	check(not schild.contains("Hinstellen") and schild.contains("\"Absetzen\""), "getragen ist man immer im Bauen: das Schild sagt „Absetzen“")
	var raster := FileAccess.get_file_as_string("res://src/room/shaders/raster.gdshader")
	var auffr := basis.substr(basis.find("func _raster_auffrischen"), 700)
	check(raster.contains("uniform vec3 gruen") and raster.contains("mix(farbe, gruen, getragen)") and auffr.contains("ok, 0.03, true)"),
			"Feld unter dem Getragenen: klar grün, wenn es passt, sonst rot (das Feld allein im Akzent)")

	print("Wand als Feld außerhalb des Raums")
	check(Zimmer.wand_an(Vector2i(3, -1), 12, 10) == "hinten" and Zimmer.wand_an(Vector2i(3, 10), 12, 10) == "vorn"
			and Zimmer.wand_an(Vector2i(-1, 4), 12, 10) == "links" and Zimmer.wand_an(Vector2i(12, 4), 12, 10) == "rechts"
			and Zimmer.wand_an(Vector2i(5, 5), 12, 10) == "", "über den Rand: die Wand dort, im Raum keine")
	check(Zimmer.feld_im_rahmen(Vector2i(0, 0), Vector2i(-1, 0), 12, 10) == Vector2i(-1, 0), "ein Schritt über den linken Rand: linke Wand")
	check(Zimmer.feld_im_rahmen(Vector2i(-1, 0), Vector2i(-2, 0), 12, 10) == Vector2i(-1, 0), "weiter hinaus geht es nicht")
	check(Zimmer.feld_im_rahmen(Vector2i(-1, 0), Vector2i(-1, -1), 12, 10) == Vector2i(-1, 0), "keine Ecken: bleibt bei der Wand")
	check(Zimmer.feld_im_rahmen(Vector2i(11, 9), Vector2i(12, 9), 12, 10) == Vector2i(12, 9), "rechte Wand")

	print("Wohin der Blick fällt")
	var augen := Vector3(3.0, 1.62, 3.0)
	var unten: Variant = Zimmer.blick_feld(augen, (Vector3(3.0, 0.0, 2.0) - augen).normalized(), 12, 10)
	check(unten == Vector2i(6, 4), "schräg nach unten: das Feld am Boden (%s)" % str(unten))
	var wand: Variant = Zimmer.blick_feld(augen, Vector3(0, 0, -1), 12, 10)
	check(wand == Vector2i(6, -1), "geradeaus zur hinteren Wand: das Feld dahinter (%s)" % str(wand))
	var links: Variant = Zimmer.blick_feld(augen, Vector3(-1, 0.1, 0).normalized(), 12, 10)
	check(links == Vector2i(-1, 6), "zur linken Wand (%s)" % str(links))
	check(Zimmer.blick_feld(augen, Vector3(0, 1, 0), 12, 10) == null, "zur Decke: nichts")

	print("Alles von früher erreichbar – verteilt statt in einer Ecke")
	var stub := _Stub.new()
	stub.daten = Daten.standard()
	stub.raum = stub.daten.raeume[0]
	add_child(stub)
	var seiten := Anpassen.new(stub)
	var texte := _texte(seiten.seite_zimmer(), 2)
	for t in ["Deine Figur", "Dein Haustier", "Zimmer teilen", "Zimmer-Datei einführen", "Zimmer-Code einführen", "Online",
			"Eigene Möbel", "Hüllen je System", "Grafik", "Beim Einschalten"]:
		check(t in texte, "Zimmer-Menü: „%s“" % t)
	var modi: Array = ModusUi.MODI.map(func(m: Array) -> String: return str(m[0]))
	check(modi == ["leben", "bauen", "foto"], "Modus-Leiste: Leben, Bauen, Foto (statt „Möbel einrichten“ und „Fotomodus“ im Menü)")
	check(ModusUi.naechster("leben") == "bauen" and ModusUi.naechster("bauen") == "foto" and ModusUi.naechster("foto") == "leben", "View schaltet reihum")
	check(Zimmer.modus_gruppe("katalog") == "bauen" and Zimmer.modus_gruppe("sitzen") == "leben" and Zimmer.modus_gruppe("foto") == "foto",
			"jeder Zustand gehört zu einem Modus")
	_modus_tabelle()
	var raum_namen: Array = KatalogUi.RAUM_TEILE.map(func(r: Array) -> String: return str(r[1]))
	for t in ["Wände und Tapeten", "Böden", "Decke und Leisten", "Fenster und Türen", "Licht und Stimmung", "Raumgröße", "Vorlagen"]:
		check(t in raum_namen, "Bauen › Raum: „%s“" % t)
	for rt in KatalogUi.RAUM_TEILE:
		check(not (seiten.raum_seite(str(rt[0])).get("zeilen", []) as Array).is_empty() and KatalogUi.ist_raum(str(rt[0])),
				"Raum-Bereich „%s“ hat seine Feinseite" % rt[1])
	var kats: Array = KatalogUi.kategorien().map(func(k: Array) -> String: return str(k[0]))
	check(kats.slice(0, 7) == KatalogUi.RAUM_TEILE.map(func(r: Array) -> String: return str(r[0])) and kats.size() == 7 + Katalog.KATEGORIEN.size(),
			"Leiste: erst der Raum, dann die Möbel nach Zweck")
	var erste: Array = seiten.seite_zimmer().zeilen
	check(erste.filter(func(z: Dictionary) -> bool: return str(z.art) != "abschnitt").size() <= 8, "Zimmer-Menü kurz: höchstens 8 Zeilen")
	check(not (seiten.seite_wand("hinten").zeilen as Array).is_empty() and not (seiten.seite_boden().zeilen as Array).is_empty(),
			"Wand und Boden direkt als Seite")

	_umbau()

	print("Alles Platzierte ist erreichbar (Tisch unter der Tasse, Bild hinter dem Schreibtisch)")
	var sr := Daten.standard_raum()
	var ix := func(t: String, x: int) -> int:
		for i in (sr.moebel as Array).size():
			if str(sr.moebel[i].t) == t and (x < 0 or int(sr.moebel[i].x) == x):
				return i
		return -1
	var tisch: int = ix.call("couchtisch", -1)
	var tasse: int = ix.call("tasse", -1)
	var auf_feld := Daten.alle_an_feld(sr, 6, 4)
	check(auf_feld.size() >= 2 and auf_feld[0] == tasse and tisch in auf_feld, "Feld mit Tasse: Tasse zuerst, der Tisch darunter wählbar")
	var bild_r: int = ix.call("bild", 11)
	check(Daten.an_feld(sr, 11, 5) != bild_r and bild_r in Daten.alle_an_feld(sr, 11, 5), "Bild über dem Schreibtisch: auf dem Feld mit dabei")
	check(Daten.an_wandfeld(sr, Vector2i(12, 5)) == bild_r and Daten.an_wandfeld(sr, Vector2i(-1, 7)) == ix.call("bild", 0),
			"ein Schritt über den Rand: das Bild an der Wand ist gewählt")
	check(Daten.an_wandfeld(sr, Vector2i(1, -1)) == -1 and Daten.an_wandfeld(sr, Vector2i(5, -1)) == ix.call("lichterkette", -1)
			and Daten.an_wandfeld(sr, Vector2i(5, 5)) == -1, "leere Wand und Felder im Raum: kein Wandmöbel")
	var lang: Array = []
	for t in ["Hochheben", "drehen", "farbe", "spiele", "Tisch wählen", "Teppich wählen", "anpassen", "Wegräumen"]:
		lang.append({ "id": t, "text": t })
	var kurz: Array = Zimmer.kuerzen(lang).map(func(e: Dictionary) -> String: return str(e.id))
	check(kurz.size() <= 6 and "Hochheben" in kurz and "Wegräumen" in kurz and "Tisch wählen" in kurz and "Teppich wählen" in kurz
			and not ("drehen" in kurz), "Liste am Möbel höchstens sechs Zeilen: Drehen (LB/RB) fällt zuerst, Wählen und Wegräumen bleiben")
	var zs := FileAccess.get_file_as_string("res://src/room/zimmer_basis.gd")
	check(zs.substr(zs.find("func _ziel_suchen"), 1400).contains("welt.treffer(o, r, REICHWEITE, false, false)"),
			"beim Laufen: auch Möbel ohne eigene Handlung (Tisch, Bild) lassen sich ansehen, verschieben, wegräumen")
	var ze := FileAccess.get_file_as_string("res://src/room/zimmer_einrichten.gd")
	check(ze.substr(ze.find("func _aktionen_laufen"), 4000).contains("\"Wegräumen\""), "Y-Liste beim Laufen: Wegräumen")

	print("Speicherformat unverändert")
	check(Daten.FORMAT == "uzai-zimmer" and Daten.VERSION == 2, "Fassung 2 wie bisher")
	var alt := { "format": "uzai-zimmer", "version": 1, "aktuell": "zimmer", "raeume": [{ "id": "zimmer", "name": "Alt", "w": 12, "d": 10,
		"wand": "salbei", "boden": "walnuss", "licht": "nacht", "moebel": [{ "t": "sofa", "x": 4, "z": 7, "r": 2, "v": "senf", "an": true }] }] }
	var d := Daten.pruefe(alt)
	check((d.raeume[0].moebel as Array).size() == 1 and str(d.raeume[0].name) == "Alt", "alter Speicherstand lädt")
	check(Daten.pruefe(Daten.standard()) == Daten.standard(), "Standard unverändert gültig")
	stub.queue_free()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Umbauen beim Laufen (zimmer_umbau.gd): Wand ziehen, Tragen, Wand vor dir, Regal von Hand.
func _umbau() -> void:
	print("Raumgröße: eine Wand ziehen")
	var h := Zimmer.bau_hinweise({ "wand": "hinten" })
	check(["y", "Raum größer/kleiner"] in h, "Bauen, Wand gewählt: Y zieht sie (Raum größer/kleiner)")
	var r := Daten.standard_raum()
	r.w = 12
	r.d = 10
	r.moebel = [
		{ "t": "sitzsack", "x": 10, "z": 4, "r": 0, "v": "terrakotta" },     # an der rechten Wand
		{ "t": "pflanze", "x": 8, "z": 5, "r": 0, "v": "monstera" },        # mitten im Raum
		{ "t": "pflanze", "x": 0, "z": 2, "r": 0, "v": "monstera" },        # an der linken Wand
	]
	var p := Zimmer.wand_plan(r, "rechts", 2)
	check(bool(p.ok) and int(p.w) == 14 and int(p.raum.moebel[0].x) == 12 and int(p.raum.moebel[1].x) == 8, "rechts +2: breiter, was an der Wand steht, rückt mit")
	check(p.mit == [0], "rechts +2: genau das Möbel an der Wand rückt mit (%s)" % str(p.mit))
	var pl := Zimmer.wand_plan(r, "links", 1)
	check(bool(pl.ok) and int(pl.w) == 13 and int(pl.raum.moebel[0].x) == 11 and int(pl.raum.moebel[1].x) == 9 and int(pl.raum.moebel[2].x) == 0,
			"links +1: der Rest rückt in den Koordinaten, das an der linken Wand bleibt an ihr")
	var pk := Zimmer.wand_plan(r, "rechts", -4)
	check(not bool(pk.ok) and 1 in (pk.blockiert as Array), "rechts −4: die Pflanze in der Mitte ist im Weg (rot)")
	check(bool(Zimmer.wand_plan(r, "rechts", -1).ok), "rechts −1: das Möbel an der Wand rückt nach innen mit")
	check((Zimmer.wand_plan(r, "vorn", Daten.MAX_FELDER).raum as Dictionary).is_empty(), "nie größer als erlaubt")
	check((Zimmer.wand_plan(r, "hinten", -(int(r.d) - Daten.MIN_FELDER + 1)).raum as Dictionary).is_empty(), "nie kleiner als erlaubt")
	check(int(r.w) == 12 and int(r.moebel[0].x) == 10, "der Plan ändert den Raum nicht (erst A übernimmt)")
	check(Zimmer.wand_aussen("links") == Vector2i(-1, 0) and Zimmer.wand_aussen("vorn") == Vector2i(0, 1), "Außen-Richtung je Wand")

	print("Beim Laufen: Wand vor dir, Tragen am Raster")
	var z := Katalog.ZELLE
	var o := Vector3(3.0, 1.6, 1.2)
	check(Zimmer.wand_vor(o, Vector3(0, 0, -1), Vector3(3.0, 0, 1.2), 12, 10) == "hinten", "nah vor der hinteren Wand: „Raum größer/kleiner“")
	check(Zimmer.wand_vor(Vector3(3.0, 1.6, 4.5), Vector3(0, 0, -1), Vector3(3.0, 0, 4.5), 12, 10) == "", "weit weg: kein Schild")
	check(Zimmer.wand_vor(Vector3(3.0, 1.6, 2.0), Vector3(0, -0.8, -0.6).normalized(), Vector3(3.0, 0, 2.0), 12, 10) == "", "Blick auf den Boden: keine Wand")
	var g := Vector2i(2, 2)
	var c := Zimmer.tragen_feld(Vector3(3.0, 1.6, 3.0), Vector3(0, -0.5, -0.86).normalized(), Vector3(3.0, 0, 3.0), 0.0, g, 12, 10, false)
	check(c.x >= 0 and c.y >= 0 and c.x + g.x <= 12 and c.y + g.y <= 10, "Getragenes bleibt im Raum (%s)" % str(c))
	check(float(c.y + g.y) * z <= 3.0 - 0.3, "Getragenes schwebt vor dir, nicht unter deinen Füßen (%s)" % str(c))
	var c2 := Zimmer.tragen_feld(Vector3(0.6, 1.6, 0.6), Vector3(0, 0.1, -1).normalized(), Vector3(0.6, 0, 0.6), 0.0, Vector2i(1, 1), 12, 10, true)
	check(c2.y == 0, "Wandmöbel: an die Wand, auf die du schaust (%s)" % str(c2))
	check(Zimmer._meter_text(5) == "2,5" and Zimmer._meter_text(12) == "6", "Maße in Metern (2,5 × 6 m)")

	print("Regal von Hand: Fach, Lage, Stapel, eigene Ordnung")
	var dvd := { "id": "a", "system": "ps2" }
	var st := {}
	Inhalt.lage_schritt(st, "dvd", "liegend", 0.3)
	var b1 := float(st.x)
	Inhalt.lage_schritt(st, "dvd", "liegend", 0.3)
	Inhalt.lage_schritt(st, "dvd", "liegend", 0.3)
	check(is_equal_approx(float(st.x), b1) and int(st.n) == 3, "liegende Hüllen stapeln sich (drei brauchen den Platz von einer)")
	var w_steh := Inhalt.reihe_breite([[dvd, "stehend"], [dvd, "stehend"]], {}, 0.3)
	var w_vorn := Inhalt.reihe_breite([[dvd, "vorn"]], {}, 0.3)
	check(w_steh < 0.04 and w_vorn > 0.13, "stehend schmal, Cover nach vorn breit (%.3f / %.3f)" % [w_steh, w_vorn])
	var flach := 0
	var stapel := {}
	for i in 20:
		Inhalt.lage_schritt(stapel, "dvd", "liegend", 0.1)
		flach = int(stapel.n)
	check(flach * 0.0145 <= 0.1, "ein Stapel bleibt unter dem nächsten Brett")
	var faecher := [{ "pos": Vector3(-0.23, 0.075, 0.0), "breite": 0.42, "tiefe": 0.32, "hoehe": 0.4 },
		{ "pos": Vector3(0.23, 0.075, 0.0), "breite": 0.42, "tiefe": 0.32, "hoehe": 0.4 },
		{ "pos": Vector3(-0.23, 0.5, 0.0), "breite": 0.42, "tiefe": 0.32, "hoehe": 0.4 },
		{ "pos": Vector3(0.23, 0.5, 0.0), "breite": 0.42, "tiefe": 0.32, "hoehe": 0.4 }]
	var ob := Inhalt.oben_fach(faecher)
	check(absf(float(ob.pos.y) - (0.9 + Inhalt.DECKEL)) < 0.001 and absf(float(ob.breite) - 0.88) < 0.001 and absf(float(ob.pos.x)) < 0.001,
			"oben auf dem Regal: auf dem Deckel, so breit wie beide Spalten")
	var plaetze := [
		{ "art": "spiel", "daten": { "id": "a" }, "fach": 2, "x": -0.3 }, { "art": "spiel", "daten": { "id": "b" }, "fach": 2, "x": -0.28 },
		{ "art": "spiel", "daten": { "id": "c" }, "fach": 0, "x": -0.3, "knoten": true }, { "art": "spiel", "daten": { "id": "d" }, "fach": 0, "x": -0.1 },
	]
	var ziel := [plaetze[3]]
	var neu := Zimmer.hand_ordnung({ "so": "zuletzt", "fi": "alle" }, plaetze, "a", 0, ziel, 0, "liegend", ["c", "a", "b", "d", "e"])
	check(str(neu.so) == "manuell" and neu.pl == { "a": 0, "b": 2, "c": 0, "d": 0 },
			"erstes Umstellen: alles bleibt in seinem Fach, die Hülle im neuen (%s)" % str(neu.pl))
	check(neu.lg == { "a": "liegend", "c": "vorn" }, "Lage gemerkt: liegend, und was mit dem Cover vorn stand, bleibt so (%s)" % str(neu.lg))
	check(neu.ma == ["c", "a", "d", "b", "e"], "Reihenfolge: die Hülle vor „d“, Neues hinten (%s)" % str(neu.ma))
	var neu2 := Zimmer.hand_ordnung(neu, plaetze, "c", -1, [], 0, "stehend", neu.ma)
	check(int(neu2.pl.c) == -1 and not (neu2.lg as Dictionary).has("c") and int(neu2.pl.b) == 2, "zweites Umstellen: nur die eine Hülle wandert (oben drauf)")
	var rg := G.pruefe_regal(neu, "spieleregal")
	check(rg.get("pl") == neu.pl and rg.get("lg") == neu.lg, "Prüfer behält Fach und Lage von Hand")
	var boese := G.pruefe_regal({ "so": "manuell", "pl": { "a": 99, "b": "x", "c": -1, "d": 2.0 }, "lg": { "a": "fliegend", "c": "vorn", "z": "liegend" } },
			"spieleregal")
	check(boese.get("pl") == { "c": -1, "d": 2 } and boese.get("lg") == { "c": "vorn" }, "Prüfer: nur gültige Fächer und Lagen (%s)" % str(boese))
	check(not G.pruefe_regal({ "so": "titel", "pl": { "a": 1 } }, "spieleregal").has("pl"), "andere Sortierung: die Ordnung von Hand gilt nicht mehr")
	var geteilt := { "t": "spieleregal", "rg": neu.duplicate(true) }
	Teilen._ohne_bibliothek(geteilt)
	check(not geteilt.rg.has("pl") and not geteilt.rg.has("lg") and not geteilt.rg.has("ma"), "Teilen: keine Spiel-IDs (Fach und Lage bleiben zu Hause)")
	var leer_raum := { "moebel": [{ "t": "spieleregal", "rg": neu.duplicate(true) }] }
	Daten.regale_leeren(leer_raum)
	check(not ((leer_raum.moebel[0] as Dictionary).get("rg", {}) as Dictionary).has("pl"), "Regale leeren: auch die Ordnung von Hand")

	print("Hüllen wie im Regal des Hauptmenüs")
	check(Inhalt.format_von({ "system": "ps2" }) == "ps2" and Inhalt.format_von({ "system": "ps1" }) == "ps1"
			and Inhalt.format_von({ "system": "gc" }) == "gc" and Inhalt.format_von({ "system": "switch" }) == "switch"
			and Inhalt.format_von({ "system": "steam" }) == "dvd", "Format je System wie im Hauptmenü (PS2, PS1, GameCube, Switch, PC)")
	check(Inhalt.mass_von({ "system": "ps2" }) == RegalLogik.masse("ps2") and Inhalt.mass_von({ "system": "ps1" }) == RegalLogik.masse("ps1"),
			"dieselben Maße wie im Hauptmenü")
	check(Inhalt.format_von({ "system": "snes" }, { "snes": "jewel" }) == "jewel" and Inhalt.format_von({ "system": "nds" }, { "nds": "klein" }) == "psp",
			"Einstellung „Hüllen je System“ wählt ein Format des Hauptmenüs")
	check(Inhalt.ruecken_farbe({ "system": "ps2", "id": "x" }).is_equal_approx(Color("#f3f3f1"))
			and Inhalt.ruecken_farbe({ "system": "ps1", "id": "x" }).is_equal_approx(Color("#0d0d0f")), "PS2-Rücken weiß, PS1 schwarz")
	var mat_pal := Inhalt._mm_material("ps2|pal")
	var mat_ntsc := Inhalt._mm_material("ps2|ntsc")
	check(int(mat_pal.get_shader_parameter("felder")) == 3 and int(mat_ntsc.get_shader_parameter("felder")) == 2,
			"PS2-Rücken: PS-Feld, PAL-Streifen, Wortmarke (NTSC ohne PAL)")
	check(mat_pal.shader.code.contains("regal_huelle.gdshaderinc")
			and (load("res://src/room/shaders/regal_huelle.gdshader") as Shader).code.contains("regal_huelle.gdshaderinc"),
			"Zimmer und Hauptmenü zeichnen die Hülle mit demselben Kern")

	print("Welche Spiele: mehrere Systeme")
	check(G.pruefe_filter("systeme:ps2,gamecube") == "systeme:gamecube,ps2", "zwei Systeme, sortiert")
	check(G.pruefe_filter("systeme:ps2") == "system:ps2" and G.pruefe_filter("systeme:ps2,ps2") == "system:ps2", "eins allein bleibt „system:…“")
	check(G.pruefe_filter("systeme:PS 2,\u0000") == G.FILTER_STD, "fremde Kennungen fallen weg")
	check(RegalTafel.systeme_umschalten("system:ps2", "gamecube") == "systeme:gamecube,ps2", "A nimmt ein System dazu")
	check(RegalTafel.systeme_umschalten("systeme:gamecube,ps2", "ps2") == "system:gamecube", "A nimmt eins wieder weg")
	check(RegalTafel.systeme_umschalten("system:ps2", "ps2") == "alle" and RegalTafel.systeme_umschalten("favoriten", "ps2") == "system:ps2",
			"keins mehr: alle Spiele; aus anderer Auswahl: nur dieses")
	check(Inhalt.passt_filter({ "system": "ps2" }, "systeme:gamecube,ps2") and not Inhalt.passt_filter({ "system": "n64" }, "systeme:gamecube,ps2"),
			"Regal zeigt die Spiele beider Systeme")
	var ki := RegalTafel.kacheln("spiele", 0, "spieleregal", [["System", [["system:ps2", "PS2"], ["system:gamecube", "GameCube"]]]], [])
	var sys_k: Array = ki.filter(func(k: Dictionary) -> bool: return bool(k.get("mehrfach", false)))
	check(sys_k.size() == 2 and not bool(sys_k[0].sofort), "System-Kacheln zum Anhaken (keine Probe beim Drüberfahren)")
	var ord := RegalTafel.kacheln("ordnung", 0, "spieleregal", [], [])
	check(ord.any(func(k: Dictionary) -> bool: return str(k.wert) == "hand_weg"), "Sortierung: „Sortierung zurücksetzen“ (nach dem Umstellen von Hand)")


## Texte aller Zeilen einer Seite und ihrer Unterseiten (bis tiefe).
func _texte(seite: Dictionary, tiefe: int) -> Array:
	var out: Array = []
	for z in seite.get("zeilen", []):
		out.append(str(z.get("text", "")))
		if tiefe > 0 and str(z.get("art", "")) == "seite" and z.get("oeffnen") is Callable:
			out.append_array(_texte((z.oeffnen as Callable).call(), tiefe - 1))
	return out

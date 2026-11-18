extends Node
## Dein Zimmer (Punkt 131): Daten streng prüfen, Raster und Belegung, Drehen, Kleines auf Flächen,
## Wandmöbel, Rückgängig, Speichern und Laden, Tageszeit, Abnutzung der Hüllen.
## Aufruf: godot --headless --path . res://tests/logic_zimmer.tscn

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Raum := preload("res://src/room/raum.gd")
const Inhalt := preload("res://src/room/inhalt.gd")
const G := preload("res://src/room/gestalt.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Teilen := preload("res://src/room/zimmer_teilen.gd")
const Moebel := preload("res://src/room/moebel.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _datei(text: String) -> String:
	var p := OS.get_user_data_dir().path_join("zimmer_test_%d.json" % randi())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p


## Spieleregale füllst du selbst: neu leer, einmalige Umstellung alter Zimmer (nur die Regale), nur
## Spiele der eigenen Bibliothek, je Regal eigene Liste, Teilen ohne Spiele.
func _regale() -> void:
	print("Regale füllst du selbst")
	var std := Daten.standard()
	check(str(std.get("regale", "")) == Daten.REGALE_EIGEN and str(Daten.pruefe(std).regale) == Daten.REGALE_EIGEN, "neues Zimmer: Vermerk „Regale selbst einräumen“")
	var regale := 0
	for m in std.raeume[0].moebel:
		if str(m.t) == "spieleregal":
			regale += 1
			check(not m.has("rg") or str(m.rg.get("fi", "")) == "eigene", "Standardzimmer: Regal %d ohne automatische Auswahl" % regale)
	check(regale >= 1 and Inhalt.spiele(G.std_regal("spieleregal")).is_empty() and Inhalt.spiele({}).is_empty(), "neues Regal steht leer")
	# Ein Zimmer von früher: Regale mit Auswahl „alle“ und eigener Reihenfolge, dazu andere Möbel und eine Vorlage.
	var alt := Daten.standard()
	alt.erase("regale")
	var andere: Array = []
	for m in alt.raeume[0].moebel:
		if str(m.t) == "spieleregal":
			m["rg"] = { "so": "titel", "fi": "alle", "da": "cover", "ab": false, "de": "viel", "ma": ["steam:1", "ps2:x"] }
		elif str(m.t) == "trophaeenschrank":
			m["rg"] = { "so": "titel", "fi": "platin" }
	var vr := Daten.standard_raum()
	vr.moebel[1]["rg"] = { "so": "zuletzt", "fi": "system:ps2" }
	alt.vorlagen = [{ "id": "v_alt", "name": "Alt", "raum": vr }]
	var vorher_geprueft := Daten.pruefe(Daten.standard())
	for m in vorher_geprueft.raeume[0].moebel:
		if str(m.t) != "spieleregal" and str(m.t) != "trophaeenschrank":
			andere.append(m)
	var neu := Daten.pruefe(alt)
	var leer := true
	var andere_neu: Array = []
	for m in neu.raeume[0].moebel:
		if str(m.t) == "spieleregal":
			leer = leer and str(m.rg.fi) == "eigene" and not m.rg.has("ma") and str(m.rg.da) == "cover" and str(m.rg.de) == "viel" and m.rg.ab == false
		elif str(m.t) == "trophaeenschrank":
			check(str(m.rg.fi) == "platin", "Umstellung: Pokalschrank bleibt, wie er war")
		else:
			andere_neu.append(m)
	check(leer, "Umstellung: Spieleregale leer, Darstellung, Deko und Abnutzung bleiben")
	check(andere_neu == andere, "Umstellung: alle anderen Möbel unverändert (%d)" % andere.size())
	var vrn: Dictionary = neu.vorlagen[0].raum.moebel[1]
	check(str(neu.regale) == Daten.REGALE_EIGEN and (not vrn.has("rg") or str(vrn.rg.fi) == "eigene"), "Umstellung: auch eigene Vorlagen; danach der Vermerk")
	# Danach gilt, was du einräumst: ein zweites Prüfen räumt nichts mehr aus.
	for m in neu.raeume[0].moebel:
		if str(m.t) == "spieleregal":
			m["rg"] = G.pruefe_regal({ "fi": "eigene", "ma": ["a", "b"] }, "spieleregal")
			break
	var wieder := Daten.pruefe(neu)
	var noch := false
	for m in wieder.raeume[0].moebel:
		if str(m.t) == "spieleregal" and m.has("rg") and m.rg.get("ma", []) == ["a", "b"]:
			noch = true
	check(noch and Daten.pruefe(wieder) == wieder, "nur einmal: Eingeräumtes bleibt beim nächsten Laden")
	# Gespeichert und wieder geladen: nichts geht verloren.
	var pfad := OS.get_user_data_dir().path_join("zimmer_regale_%d.json" % randi())
	check(Daten.speichern(wieder, pfad) and Daten.laden(pfad) == wieder, "Speichern und Laden behalten die Regale")
	DirAccess.remove_absolute(pfad)
	DirAccess.remove_absolute(pfad + ".bak")

	print("Nur die eigene Bibliothek")
	Library.load_demo()
	var ids: Array = Library.visible_games().filter(func(g: Dictionary) -> bool: return str(g.get("source", "")) != "disc") \
			.map(func(g: Dictionary) -> String: return str(g.id)).slice(0, 3)
	check(ids.size() == 3, "Demo-Bibliothek mit Spielen")
	if ids.size() == 3:
		var rg := G.pruefe_regal({ "fi": "eigene", "ma": [ids[2], "fremd:spiel", ids[0], ids[2], 42] }, "spieleregal")
		var drin: Array = Inhalt.spiele(rg).map(func(g: Dictionary) -> String: return str(g.id))
		check(drin == [ids[2], ids[0]], "eingeräumt: deine Reihenfolge, fremde IDs zeigen nichts, nichts doppelt")
		rg["so"] = "titel"
		var t: Array = Inhalt.spiele(rg)
		check(t.size() == 2 and Library.display_title(t[0]).naturalnocasecmp_to(Library.display_title(t[1])) <= 0, "auf Wunsch nach Titel sortiert")
		check(Inhalt.spiele(G.pruefe_regal({ "fi": "alle" }, "spieleregal")).size() > 2, "Auswahl „Alle Spiele“ gibt es weiter")
	check(Welt.regal_gruppe({ "so": "titel", "fi": "eigene" }, 3) != Welt.regal_gruppe({ "so": "titel", "fi": "eigene" }, 4)
			and Welt.regal_gruppe({ "so": "titel", "fi": "alle" }, 3) == Welt.regal_gruppe({ "so": "titel", "fi": "alle" }, 4),
			"Eingeräumtes gehört nur seinem Regal; gleiche Auswahl teilt sich die Spiele wie bisher")

	print("Teilen")
	var it := { "t": "spieleregal", "rg": { "so": "manuell", "fi": "eigene", "ma": ["steam:geheim"] } }
	Teilen._ohne_bibliothek(it)
	check(str(it.rg.fi) == "eigene" and not it.rg.has("ma"), "geteilt: Regal bleibt „selbst einräumen“, ohne deine Spiele")
	var ein := Daten.standard()
	for m in ein.raeume[0].moebel:
		if str(m.t) == "spieleregal":
			m["rg"] = { "so": "titel", "fi": "alle", "da": "cover" }
	var auszug := Teilen.auszug(Daten.pruefe(ein), Daten.pruefe(ein).raeume[0])
	var alle_bleibt := false
	for m in auszug.raeume[0].moebel:
		if str(m.t) == "spieleregal" and m.has("rg") and str(m.rg.get("fi", "")) == "alle":
			alle_bleibt = true
	check(alle_bleibt and Teilen.gleich(auszug, Teilen.pruefen(auszug)), "neues geteiltes Zimmer: deine Auswahl reist mit, unverändert")
	var alt_geteilt: Dictionary = auszug.duplicate(true)
	alt_geteilt.erase("regale")
	var leer_geteilt := true
	for m in Teilen.pruefen(alt_geteilt).raeume[0].moebel:
		if str(m.t) == "spieleregal" and m.has("rg") and str(m.rg.get("fi", "")) != "eigene":
			leer_geteilt = false
	check(leer_geteilt, "geteiltes Zimmer von früher: Regale kommen leer an")


func _ready() -> void:
	print("Standardzimmer")
	var std := Daten.standard()
	var geprueft := Daten.pruefe(std)
	check(not geprueft.is_empty(), "Standardzimmer besteht die Prüfung")
	var r0: Dictionary = std.raeume[0]
	check((geprueft.raeume[0].moebel as Array).size() == (r0.moebel as Array).size(),
			"kein Möbel des Standardzimmers fällt weg (%d)" % (r0.moebel as Array).size())
	check(Daten.pruefe(Daten.pruefe(std)) == geprueft, "Prüfen ist stabil (zweimal gleich)")
	var arten := {}
	for m in r0.moebel:
		arten[m.t] = true
	check(arten.has("spieleregal") and arten.has("trophaeenschrank") and arten.has("plattenregal") and arten.has("medienwand"),
			"Regal, Pokalschrank, Plattenregal und Fernseher sind da")
	for id in Katalog.MOEBEL.keys():
		var info := Katalog.info(id)
		var ok := Katalog.variante_gueltig(id, Katalog.std_variante(id)) and str(info.kat) in Katalog.KATEGORIEN.map(func(k: Array) -> String: return str(k[0]))
		if not ok:
			check(false, "Katalog: %s hat Kategorie und Standardvariante" % id)
	check(true, "Katalog: alle %d Möbel mit Kategorie und gültiger Standardvariante" % Katalog.MOEBEL.size())
	# Walking space, so a room is never too full to walk around in: in every template the free floor is connected
	# and enough of it is free, measured as when walking (zimmer_basis.gd _frei: distance RADIUS to walls and
	# furniture). The old default room had 29 % in two pieces (the front right corner was cut off).
	var VorlagenS: GDScript = load("res://src/room/vorlagen.gd")
	for v in VorlagenS.LISTE:
		var b := begehbar(VorlagenS.roh(str(v[0])))
		check(int(b.teile) == 1 and float(b.anteil) >= 0.3, "Vorlage %s: frei begehbar, ein Stück (%d %% des Bodens frei, %d Teile)"
				% [v[0], int(float(b.anteil) * 100.0), int(b.teile)])

	print("Strenge Prüfung")
	check(Daten.pruefe(null).is_empty() and Daten.pruefe([]).is_empty() and Daten.pruefe("x").is_empty(), "kein Wörterbuch: abgelehnt")
	check(Daten.pruefe({ "format": "anders", "version": 1, "raeume": [Daten.standard_raum()] }).is_empty(), "fremdes Format: abgelehnt")
	check(Daten.pruefe({ "format": Daten.FORMAT, "version": 99, "raeume": [Daten.standard_raum()] }).is_empty(), "neuere Fassung: abgelehnt")
	check(Daten.pruefe({ "format": Daten.FORMAT, "version": 1, "raeume": [] }).is_empty(), "ohne Räume: abgelehnt")
	check(Daten.aus_text("{ kaputt").is_empty() and Daten.aus_text("").is_empty(), "kaputtes JSON: abgelehnt")
	var gross := "{\"format\":\"uzai-zimmer\",\"x\":\"" + "a".repeat(Daten.MAX_BYTES) + "\"}"
	check(Daten.aus_text(gross).is_empty(), "zu groß: gar nicht erst gelesen")
	var raum := Daten.standard_raum()
	raum["fremd"] = "res://boese.gd"
	raum["name"] = "Mein\u0007 Zimmer\n mit einem sehr, sehr langen Namen, der nicht passt"
	raum.moebel = [
		{ "t": "sofa", "x": 2, "z": 2, "r": 0, "v": "salbei", "skript": "OS.execute" },
		{ "t": "res://src/main.gd", "x": 0, "z": 0, "r": 0 },
		{ "t": "sofa", "x": 3, "z": 2, "r": 0 },
		{ "t": "sessel", "x": 0.5, "z": 6, "r": 0 },
		{ "t": "sessel", "x": 30, "z": 6, "r": 0 },
		{ "t": "sessel", "x": 8, "z": 6, "r": 5 },
		{ "t": "sessel", "x": 8, "z": 6, "r": 0, "v": "neon", "an": "ja" },
		{ "t": "medienwand", "x": 0, "z": 0, "r": 0 },
		{ "t": "medienwand", "x": 6, "z": 0, "r": 0 },
		{ "t": "bild", "x": 4, "z": 5, "r": 0 },
		{ "t": "bild", "x": 4, "z": 0, "r": 0 },
		{ "t": "sessel", "x": 1e20, "z": 1, "r": 0 },
	]
	var d := Daten.pruefe({ "format": Daten.FORMAT, "version": 1, "aktuell": "fehlt", "raeume": [raum, raum.duplicate(true)], "extra": [1, 2] })
	check(not d.is_empty() and (d.raeume as Array).size() == 1, "doppelte Raum-ID: nur einmal")
	check(str(d.aktuell) == "zimmer", "unbekannter aktueller Raum: der erste")
	var r: Dictionary = d.raeume[0]
	check(not r.has("fremd") and not d.has("extra"), "unbekannte Felder fallen weg")
	check(str(r.name).length() <= Daten.MAX_NAME and not str(r.name).contains("\u0007") and not str(r.name).contains("\n"), "Name ohne Steuerzeichen, gekürzt")
	var ml: Array = r.moebel
	check(ml.size() == 4, "nur die gültigen Möbel bleiben (%d von 12)" % ml.size())
	check(not (ml[0] as Dictionary).has("skript"), "unbekannte Felder an Möbeln fallen weg")
	check(ml.all(func(m: Dictionary) -> bool: return Katalog.has(str(m.t))), "nur Kennungen aus dem eingebauten Katalog")
	var sessel: Array = ml.filter(func(m: Dictionary) -> bool: return m.t == "sessel")
	check(sessel.size() == 1 and str(sessel[0].v) == Katalog.std_variante("sessel") and sessel[0].an == true, "falsche Farbe und falsches an: Standard")
	check(ml.filter(func(m: Dictionary) -> bool: return m.t == "medienwand").size() == 1, "Fernseher höchstens einmal")
	check(ml.filter(func(m: Dictionary) -> bool: return m.t == "bild").size() == 1, "Bild nur an der Wand")
	var viele: Array = []
	for i in Daten.MAX_MOEBEL + 50:
		viele.append({ "t": "topfpflanze", "x": i % 12, "z": (i / 12) % 10, "r": 0 })
	var rv := Daten.standard_raum()
	rv.moebel = viele
	var dv := Daten.pruefe({ "format": Daten.FORMAT, "version": 1, "raeume": [rv] })
	check((dv.raeume[0].moebel as Array).size() <= Daten.MAX_MOEBEL, "höchstens %d Möbel" % Daten.MAX_MOEBEL)
	check(Daten.pruefe_raum({ "id": "Gross", "w": 12, "d": 10 }).is_empty() and Daten.pruefe_raum({ "id": "ok", "w": 3, "d": 10 }).is_empty()
			and Daten.pruefe_raum({ "id": "ok", "w": 12.5, "d": 10 }).is_empty(), "Raum-ID und Größe streng")

	print("Raster und Belegung")
	var leer := Daten.standard_raum()
	leer.moebel = []
	check(Katalog.groesse("sofa", 0) == Vector2i(4, 2) and Katalog.groesse("sofa", 1) == Vector2i(2, 4), "gedreht liegt das Sofa quer")
	var tisch := { "t": "couchtisch", "x": 4, "z": 4, "r": 0, "v": "eiche", "an": true }
	check(Daten.passt(leer, tisch), "Tisch passt ins leere Zimmer")
	leer.moebel.append(tisch)
	check(not Daten.passt(leer, { "t": "sessel", "x": 5, "z": 3, "r": 0 }), "Sessel überlappt den Tisch: nein")
	check(Daten.passt(leer, { "t": "teppich", "x": 3, "z": 3, "r": 0 }), "Teppich darunter: ja (eigene Ebene)")
	check(Daten.passt(leer, { "t": "tischlampe", "x": 5, "z": 5, "r": 0 }), "Tischlampe auf dem Tisch: ja")
	check(Daten.passt(leer, { "t": "tischlampe", "x": 0, "z": 0, "r": 0 }), "Tischlampe auf dem Boden: ja")
	leer.moebel.append({ "t": "sofa", "x": 4, "z": 7, "r": 2, "v": "salbei", "an": true })
	check(not Daten.passt(leer, { "t": "buecher", "x": 5, "z": 7, "r": 0 }), "Bücher aufs Sofa (keine Fläche): nein")
	check(not Daten.passt(leer, { "t": "sessel", "x": 11, "z": 0, "r": 0 }), "über den Rand hinaus: nein")
	check(Daten.passt(leer, { "t": "sessel", "x": 10, "z": 0, "r": 0 }), "genau an den Rand: ja")
	var lampe := { "t": "tischlampe", "x": 5, "z": 5, "r": 0, "v": "senf", "an": true }
	leer.moebel.append(lampe)
	check(is_equal_approx(Daten.standhoehe(leer, lampe, 2), 0.42), "Lampe steht auf der Tischfläche (0,42 m)")
	check(Daten.darauf(leer, 0) == [2], "was auf dem Tisch steht, wird erkannt")
	check(Daten.passt(leer, { "t": "couchtisch", "x": 4, "z": 4, "r": 0 }, 0), "der Tisch passt an seinen eigenen Platz (ohne sich selbst)")
	check(Daten.passt(leer, { "t": "couchtisch", "x": 5, "z": 4, "r": 0 }, 0), "mit der Lampe darauf ein Feld weiter: ja")
	leer.moebel.append({ "t": "buecher", "x": 8, "z": 4, "r": 0, "v": "senf", "an": true })
	check(not Daten.passt(leer, { "t": "couchtisch", "x": 6, "z": 4, "r": 0 }, 0), "auf Bücher am Boden schieben: nein")
	leer.moebel.pop_back()
	check(Daten.an_feld(leer, 5, 5) == 2 and Daten.an_feld(leer, 4, 4) == 0 and Daten.an_feld(leer, 0, 0) == -1,
			"Feld zeigt zuerst Kleines, dann das Möbel darunter")
	check(Daten.wand_drehung(leer, "bild", 0, 4) == 1 and Daten.wand_drehung(leer, "bild", 4, 0) == 0 and Daten.wand_drehung(leer, "bild", 11, 4) == 3,
			"Wandmöbel drehen sich zur nächsten Wand")
	check(Daten.wand_drehung(leer, "bild", 5, 5) == -1, "mitten im Raum: keine Wand")
	var frei: Variant = Daten.freie_stelle(leer, "sessel", 5, 5)
	check(frei is Dictionary and Daten.passt(leer, frei), "nächste freie Stelle passt")
	check(Daten.noch_erlaubt(Daten.standard_raum(), "medienwand") == 0 and Daten.noch_erlaubt(leer, "sofa") == -1, "Fernseher gibt es nur einmal, Sofas beliebig")

	print("Neue Möbel bauen (moebel_mehr.gd)")
	for id: String in ["ohrensessel", "schlafsofa", "bett", "pouf", "couchtisch_rund", "satztisch", "gamingtisch", "sideboard", "wandregal",
			"leiterregal", "arcade", "bogenlampe", "deckenfluter", "papierlampe", "lichtervorhang", "girlande", "bogenhanf", "haengepflanze",
			"kraeuter", "laeufer", "fell", "bilderwand", "wanduhr_strahlen", "vorhang"]:
		var n := Moebel.bauen_it({ "t": id, "v": Katalog.std_variante(id), "an": true })
		var netze := 0
		var stapel: Array[Node] = [n]
		while not stapel.is_empty():
			var k: Node = stapel.pop_back()
			stapel.append_array(k.get_children())
			if k is GeometryInstance3D:
				netze += 1
		var ok := Katalog.has(id) and netze > 0 and netze <= 32
		if Katalog.nutzen(id) == "lampe":
			ok = ok and not (n.get_meta("lampen", []) as Array).is_empty()
		if Katalog.nutzen(id) == "sitzen":
			ok = ok and n.has_meta("sitz")
		check(ok, "%s: gebaut, %d Zeichenaufrufe" % [id, netze])
		n.free()
	var sofa := Moebel.bauen("sofa", "salbei")
	var zier: Array = []
	for c in sofa.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).position.y > 0.63 and (c as MeshInstance3D).position.z > -0.05:
			zier.append(c)
	check(zier.size() == 2, "Sofa: die Zierkissen sitzen vor den Rückenkissen (nicht in ihnen)")
	sofa.free()

	print("Rückgängig")
	var stapel: Array = []
	Daten.merke(stapel, leer)
	leer.moebel.remove_at(1)
	check((stapel[0].moebel as Array).size() == 3 and (leer.moebel as Array).size() == 2, "Schnappschuss ist eine echte Kopie")
	for i in Daten.MAX_SCHRITTE + 10:
		Daten.merke(stapel, leer)
	check(stapel.size() == Daten.MAX_SCHRITTE, "Rückgängig reicht %d Schritte zurück" % Daten.MAX_SCHRITTE)

	print("Speichern und Laden")
	var pfad := OS.get_user_data_dir().path_join("zimmer_test.json")
	check(Daten.speichern(std, pfad), "speichern")
	var geladen := Daten.laden(pfad)
	check(geladen == Daten.pruefe(std), "geladen = gespeichert")
	var kaputt := _datei("{\"format\":\"uzai-zimmer\",\"version\":1,\"raeume\":\"nein\"}")
	check(str(Daten.laden(kaputt).raeume[0].id) == "zimmer", "kaputte Datei: Standardzimmer")
	check(Daten.laden(OS.get_user_data_dir().path_join("gibt_es_nicht.json")) == Daten.standard(), "fehlende Datei: Standardzimmer")
	DirAccess.remove_absolute(pfad)
	DirAccess.remove_absolute(pfad + ".bak")
	DirAccess.remove_absolute(kaputt)

	_regale()

	print("Licht und Hüllen")
	check(Raum.zeit_jetzt("auto", 7) == "morgen" and Raum.zeit_jetzt("auto", 12) == "tag" and Raum.zeit_jetzt("auto", 19) == "abend"
			and Raum.zeit_jetzt("auto", 2) == "nacht", "„Wie draußen“ nach der Uhr")
	check(Raum.zeit_jetzt("nacht", 12) == "nacht" and Raum.zeit_jetzt("quatsch", 12) == "tag", "feste Tageszeit gilt, Unbekanntes wie draußen")
	check(Inhalt.abnutzung(0) == 0.0 and Inhalt.abnutzung(3600 * 2) < Inhalt.abnutzung(3600 * 40) and Inhalt.abnutzung(3600 * 5000) == 1.0,
			"viel gespielt = abgegriffener (0 … 1)")
	check(Inhalt.huellen_art({ "system": "ps1" }) == "jewel" and Inhalt.huellen_art({ "system": "gba" }) == "modul"
			and Inhalt.huellen_art({ "system": "switch" }) == "klein" and Inhalt.huellen_art({ "system": "steam" }) == "dvd", "Hülle passt zum System")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Wie weit man im Raum gehen kann: Punkte im 10-cm-Raster, an denen die Figur steht (Abstand wie zimmer_basis.gd
## _frei zu Wänden und Bodenmöbeln), ihr Anteil am Boden und in wie viele getrennte Stücke sie zerfallen.
static func begehbar(raum: Dictionary) -> Dictionary:
	const R := 0.24
	const SCHRITT := 0.1
	var breite := float(raum.w) * Katalog.ZELLE
	var tiefe := float(raum.d) * Katalog.ZELLE
	var boxen: Array = []
	for it in raum.moebel:
		if Katalog.ebene(str(it.t)) != "boden":
			continue
		var g := Katalog.groesse_it(it)
		boxen.append([float(it.x) * Katalog.ZELLE + 0.06 - R, float(it.z) * Katalog.ZELLE + 0.06 - R,
			float(int(it.x) + g.x) * Katalog.ZELLE - 0.06 + R, float(int(it.z) + g.y) * Katalog.ZELLE - 0.06 + R])
	var nx := int(breite / SCHRITT)
	var nz := int(tiefe / SCHRITT)
	var frei := {}
	for a in nx:
		for b in nz:
			var px := (a + 0.5) * SCHRITT
			var pz := (b + 0.5) * SCHRITT
			if px < R or pz < R or px > breite - R or pz > tiefe - R:
				continue
			var ok := true
			for bx in boxen:
				if px > bx[0] and px < bx[2] and pz > bx[1] and pz < bx[3]:
					ok = false
					break
			if ok:
				frei[Vector2i(a, b)] = true
	var gesehen := {}
	var teile := 0
	for k in frei.keys():
		if gesehen.has(k):
			continue
		teile += 1
		var offen: Array = [k]
		gesehen[k] = true
		while not offen.is_empty():
			var p: Vector2i = offen.pop_back()
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = p + o
				if frei.has(n) and not gesehen.has(n):
					gesehen[n] = true
					offen.append(n)
	return { "teile": teile, "anteil": float(frei.size()) / float(maxi(1, nx * nz)) }

extends Node
## Zimmer anpassen (Punkt 131): Fassung 1 bleibt lesbar, Fassung 2 streng geprüft (Wände, Boden,
## Decke, Fenster, Tür, Licht, Möbel-Felder, Regale, eigene Möbel, Stimmungen, Farben, Hüllen),
## Größenstufen, Umzug bei neuer Raumgröße, Vorlagen ohne Verluste, Sortierung und Auswahl der
## Spiele im Regal, Licht der Lampen.
## Aufruf: godot --headless --path . res://tests/logic_zanpassung.tscn

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const Inhalt := preload("res://src/room/inhalt.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Zimmer := preload("res://src/room/zimmer.gd")
const Moebel := preload("res://src/room/moebel.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _datei(text: String) -> String:
	var p := OS.get_user_data_dir().path_join("zanpassung_test_%d.json" % randi())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p


func _v2(raum: Dictionary, extra := {}) -> Dictionary:
	var d := { "format": Daten.FORMAT, "version": 2, "aktuell": str(raum.get("id", "zimmer")), "raeume": [raum] }
	d.merge(extra, true)
	return d


func _ready() -> void:
	print("Fassung 1 bleibt lesbar")
	var alt := { "format": "uzai-zimmer", "version": 1, "aktuell": "zimmer", "raeume": [{ "id": "zimmer", "name": "Alt", "w": 12, "d": 10,
		"wand": "salbei", "boden": "walnuss", "licht": "nacht", "moebel": [{ "t": "sofa", "x": 4, "z": 7, "r": 2, "v": "senf", "an": true }] }] }
	var p := _datei(JSON.stringify(alt))
	var d := Daten.laden(p)
	var r: Dictionary = d.raeume[0]
	check(int(d.version) == Daten.VERSION and str(r.name) == "Alt", "alte Datei geladen, als Fassung %d" % Daten.VERSION)
	check(G.SEITEN.all(func(s: String) -> bool: return str(r.waende[s].f) == "#a9b49b" and str(r.waende[s].m) == "anstrich"),
			"Wand „Salbei“ → alle vier Wände salbeigrün")
	check(str(r.boden.a) == "dielen" and str(r.boden.f) == "#7a5236", "Boden „Walnuss“ → Dielen in Walnuss")
	check(str(r.licht.z) == "nacht" and str(r.licht.we) == "klar", "Licht „Nacht“ → Tageszeit Nacht, Wetter klar")
	check((r.moebel as Array).size() == 1 and str(r.moebel[0].v) == "senf", "Möbel bleiben")
	DirAccess.remove_absolute(p)
	var pv := OS.get_user_data_dir().path_join("zanpassung_rund.json")
	check(Daten.speichern(d, pv) and Daten.laden(pv) == d, "gespeichert und wieder geladen: gleich")
	DirAccess.remove_absolute(pv)
	DirAccess.remove_absolute(pv + ".bak")

	print("Gestaltung des Raums streng")
	check(G.pruefe_raum_gestalt(G.std_raum()) == G.std_raum(), "Standard besteht die Prüfung unverändert")
	var g := G.pruefe_raum_gestalt({
		"waende": { "hinten": { "m": "res://boese.gd", "f": "rot", "mu": "ornament", "mf": "#ABCDEF" }, "links": "kaputt", "fremd": {} },
		"boden": { "a": "lava", "f": "#123", "f2": "#00ff00" },
		"fenster": { "a": "bogen", "g": 99, "v": "rollo", "vf": 7 },
		"tuer": { "a": "glas", "p": "oben", "f": "#112233" },
		"licht": { "z": "abend", "we": "hagel", "k": 100, "h": 999, "lf": "#FF0000", "st": "../x", "boese": 1 },
	})
	check(str(g.waende.hinten.m) == "anstrich" and str(g.waende.hinten.f) == "#e8e0d1", "unbekanntes Material und falsche Farbe: Standard")
	check(str(g.waende.hinten.mu) == "ornament" and str(g.waende.hinten.mf) == "#abcdef", "gültiges Muster und Farbe (klein geschrieben) bleiben")
	check(g.waende.links == G.std_wand() and not g.waende.has("fremd"), "kaputte Wand: Standard, fremde Seite fällt weg")
	check(str(g.boden.a) == "dielen" and str(g.boden.f) == "#c29466" and str(g.boden.f2) == "#00ff00", "Boden: unbekannte Art und kurze Farbe → Standard")
	check(str(g.fenster.a) == "sprossen" and int(g.fenster.g) == G.FENSTERGROESSEN.size() - 1 and str(g.fenster.v) == "rollo" and str(g.fenster.vf) == "#e4d9c6",
			"Fenster: Art, Größe begrenzt, Vorhang")
	check(str(g.tuer.a) == "glas" and str(g.tuer.p) == "vorn" and str(g.tuer.f) == "#112233", "Tür: Platz nur aus der Liste")
	check(str(g.licht.we) == "klar" and int(g.licht.k) == 1800 and int(g.licht.h) == 200 and str(g.licht.lf) == "#ff0000" and str(g.licht.st) == ""
			and not g.licht.has("boese"), "Licht: Bereiche begrenzt, fremde Felder weg")

	print("Möbel-Felder streng")
	var raum := Daten.standard_raum()
	raum.moebel = [
		{ "t": "sofa", "x": 4, "z": 7, "r": 2, "v": "salbei", "f": "#B0603C", "m": "samt", "mu": "karo", "mf": "nein", "s": 2, "be": "haarnadel", "gr": "buegel",
			"l": { "k": 9000 } },
		{ "t": "couchtisch", "x": 5, "z": 4, "r": 0, "m": "res://x.tres", "f2": "#000000", "m2": "messing", "s": 99, "be": "raketen" },
		{ "t": "stehlampe", "x": 0, "z": 9, "r": 0, "l": { "k": 4000, "c": "#ff4fa3", "h": 500, "w": 10, "x": 1 } },
		{ "t": "spieleregal", "x": 0, "z": 0, "r": 0,
			"rg": { "so": "manuell", "fi": "system:snes\u0007", "da": "cover", "ab": false, "de": "viel", "ma": ["a", "a", "b", 5, "c".repeat(200)] } },
		{ "t": "kommode", "x": 9, "z": 0, "r": 0, "rg": { "so": "titel" } },
		{ "t": "spieleregal", "x": 2, "z": 0, "r": 0, "rg": { "so": "zuletzt", "fi": "lava:1", "da": "gemischt", "ab": true, "de": "wenig" } },
	]
	var sauber := Daten.pruefe_raum(raum)
	var m: Array = sauber.moebel
	check(m.size() == 6, "alle sechs Möbel bleiben (%d)" % m.size())
	check(str(m[0].f) == "#b0603c" and str(m[0].m) == "samt" and str(m[0].mu) == "karo" and not m[0].has("mf"),
			"Sofa: Farbe, Material, Muster; falsche Musterfarbe fällt weg")
	check(int(m[0].s) == 2 and str(m[0].be) == "haarnadel" and not m[0].has("gr") and not m[0].has("l"),
			"Sofa: Größe, Beine; Griffe und Licht passen nicht zum Sofa")
	check(not m[1].has("m") and str(m[1].m2) == "messing" and int(m[1].get("s", Katalog.std_stufe("couchtisch"))) == 2 and not m[1].has("be"),
			"Tisch: fremdes Material weg, Größe begrenzt, unbekannte Beine weg")
	check(int(m[2].l.k) == 4000 and str(m[2].l.c) == "#ff4fa3" and int(m[2].l.h) == 200 and int(m[2].l.w) == 50 and not m[2].l.has("x"),
			"Lampe: Licht begrenzt, fremde Felder weg")
	var rg: Dictionary = m[3].rg
	check(str(rg.so) == "manuell" and str(rg.fi) == "system:snes" and str(rg.da) == "cover" and rg.ab == false and str(rg.de) == "viel",
			"Regal: Einstellungen, Steuerzeichen aus der Auswahl entfernt")
	check(rg.ma.size() == 3 and rg.ma[0] == "a" and rg.ma[1] == "b" and str(rg.ma[2]).length() <= 96,
			"eigene Reihenfolge: ohne Doppelte und Nicht-Texte, Texte gekürzt")
	check(not m[4].has("rg"), "Kommode bekommt keine Regal-Einstellungen")
	check(str(m[5].rg.fi) == "eigene" and str(m[5].rg.so) == "zuletzt" and not m[5].rg.has("ma"),
			"unbekannte Auswahl → nur Eingeräumtes (leer); die gewählte Sortierung bleibt")
	check(G.pruefe_filter("tag:" + "x".repeat(500)).length() <= 4 + G.MAX_WERT and G.pruefe_filter("ordner:") == "eigene" and G.pruefe_filter(42) == "eigene",
			"Auswahl: Länge begrenzt, leer oder falsch → nur Eingeräumtes")
	check(G.std_regal("spieleregal").fi == "eigene" and G.std_regal("spieleregal").so == "manuell" and not G.std_regal("spieleregal").has("ma"),
			"neues Spieleregal: leer, eingeräumt in deiner Reihenfolge")

	print("Größenstufen")
	check(Katalog.groesse_it({ "t": "sofa", "r": 0 }) == Vector2i(4, 2) and Katalog.groesse_it({ "t": "sofa", "s": 2, "r": 1 }) == Vector2i(2, 5),
			"Sofa: Dreisitzer 4×2, Viersitzer gedreht 2×5")
	check(Katalog.groesse_it({ "t": "spieleregal", "s": 2, "r": 0 }) == Vector2i(4, 1)
			and is_equal_approx(Katalog.flaeche_it({ "t": "spieleregal", "s": 0 }), 1.12), "Regal: breit 4 Felder, niedrig mit Abstellfläche")
	check(Katalog.flaeche_it({ "t": "spieleregal", "s": 1 }) == 0.0 and is_equal_approx(Katalog.flaeche_it({ "t": "couchtisch", "s": 0 }), 0.42),
			"hohes Regal ohne Fläche, Tisch behält seine")
	var leer := Daten.standard_raum()
	leer.moebel = [{ "t": "spieleregal", "x": 0, "z": 0, "r": 0, "v": "eiche", "an": true, "s": 0 }]
	check(Daten.passt(leer, { "t": "topfpflanze", "x": 0, "z": 0, "r": 0 }), "auf ein niedriges Regal passt eine Pflanze")
	check(is_equal_approx(Daten.standhoehe(leer, { "t": "topfpflanze", "x": 1, "z": 0, "r": 0 }), 1.12), "… und steht auf seiner Oberkante")

	print("Eigene Möbel (Baukasten)")
	var eigen := { "id": "e_tisch1", "name": "Mein\nTisch", "ebene": "boden", "w": 3, "d": 2, "teile": [
		{ "a": "platte", "x": 0, "y": 70, "z": 0, "b": 120, "h": 4, "t": 60, "f": "#c9a173", "m": "eiche" },
		{ "a": "bein", "x": -55, "y": 0, "z": -25, "b": 5, "h": 70, "t": 5, "r": 7 },
		{ "a": "skript", "x": 0 },
		{ "a": "schirm", "x": 0, "y": 74, "z": 0, "b": 30, "h": 22, "t": 30, "m": "res://boese" },
		"kaputt",
	] }
	var e := G.pruefe_eigenes(eigen)
	check(not e.is_empty() and (e.teile as Array).size() == 3, "unbekannte und kaputte Teile fallen weg (%d bleiben)" % (e.teile as Array).size()
			if not e.is_empty() else "eigenes Möbel geprüft")
	check(str(e.name) == "MeinTisch" and int(e.teile[1].r) == 0 and not e.teile[2].has("m"),
			"Name ohne Steuerzeichen, Drehung in 15°-Schritten, fremdes Material weg")
	check(G.pruefe_eigenes({ "id": "tisch", "teile": eigen.teile }).is_empty() and G.pruefe_eigenes({ "id": "e_x", "teile": [] }).is_empty(),
			"ohne „e_“ oder ohne Teile: abgelehnt")
	var viele: Array = []
	for i in G.MAX_TEILE + 20:
		viele.append({ "a": "kugel", "x": i, "y": 0, "z": 0 })
	check((G.pruefe_eigenes({ "id": "e_viel", "teile": viele }).teile as Array).size() == G.MAX_TEILE, "höchstens %d Teile" % G.MAX_TEILE)
	check(G.eigen_masse(e.teile) == Vector2i(3, 2), "Grundfläche aus den Teilen: 3 × 2 Felder")
	var raum_e := Daten.standard_raum()
	raum_e.moebel = [{ "t": "e_tisch1", "x": 4, "z": 4, "r": 0 }, { "t": "e_fehlt", "x": 0, "z": 0, "r": 0 }, { "t": "tischlampe", "x": 5, "z": 4, "r": 0 }]
	var de := Daten.pruefe(_v2(raum_e, { "eigene": [eigen, eigen, { "id": "e_kaputt" }] }))
	check((de.eigene as Array).size() == 1, "doppelte und kaputte eigene Möbel fallen weg")
	var me: Array = de.raeume[0].moebel
	check(me.size() == 2 and str(me[0].t) == "e_tisch1", "Zimmer darf nur bekannte eigene Möbel benutzen")
	check(Katalog.ist_eigen("e_tisch1") and Katalog.in_kategorie("eigene").has("e_tisch1") and Katalog.nutzen("e_tisch1") == "lampe",
			"eigenes Möbel im Katalog unter „Eigene“, mit Schirm eine Lampe")
	check(is_equal_approx(Katalog.flaeche_it(me[0]), 0.74) and is_equal_approx(Daten.standhoehe(de.raeume[0], me[1]), 0.74),
			"Tischlampe steht auf der Platte des eigenen Tischs")
	var n := Moebel.bauen_it(me[0])
	check(n.get_child_count() == 3 and (n.get_meta("lampen", []) as Array).size() == 1, "Baukasten-Möbel gebaut: 3 Teile, 1 Licht")
	n.free()

	print("Stimmungen, Farben, Hüllen")
	var ds := Daten.pruefe(_v2(Daten.standard_raum(), {
		"stimmungen": [{ "id": "s_abc", "name": "Lesen", "licht": { "z": "abend", "k": 3000, "h": 80 } }, { "id": "BÖSE", "name": "x" },
			{ "id": "s_abc", "name": "doppelt" }],
		"farben": ["#AABBCC", "#aabbcc", "blau", "#12345", "#ff4fa3"],
		"huellen": { "snes": "jewel", "ps1": "auto", "../x": "dvd", "gba": "diskette" },
	}))
	check((ds.stimmungen as Array).size() == 1 and str(ds.stimmungen[0].licht.z) == "abend" and int(ds.stimmungen[0].licht.k) == 3000,
			"eigene Stimmung geprüft, falsche und doppelte weg")
	check(ds.farben == ["#aabbcc", "#ff4fa3"], "eigene Farben: nur gültige, ohne Doppelte")
	check(ds.huellen == { "snes": "jewel" }, "Hüllen je System: nur gültige Kennungen und Arten")
	check(Inhalt.huellen_art({ "system": "snes" }, ds.huellen) == "jewel" and Inhalt.huellen_art({ "system": "snes" }) == "modul",
			"Hülle je System eingestellt, sonst wie das System")
	var warm := G.kelvin_farbe(2200)
	var kalt := G.kelvin_farbe(6500)
	check(warm.r > warm.b + 0.4 and absf(kalt.r - kalt.b) < 0.08, "Farbtemperatur: 2200 K warm, 6500 K fast weiß")

	print("Licht der Lampen")
	var rl := { "licht": G.std_licht() }
	rl.licht.h = 50
	var l1: Array = Welt.licht_von(rl, { "t": "stehlampe" })
	check(l1[0] == Moebel.WARM and is_equal_approx(float(l1[1]), 0.5), "Standard: warmweiß, Helligkeit des Raums")
	var l2: Array = Welt.licht_von(rl, { "t": "stehlampe", "l": { "c": "#ff4fa3", "h": 200, "w": 150 } })
	check(l2[0] == Color("#ff4fa3") and is_equal_approx(float(l2[1]), 1.0) and is_equal_approx(float(l2[2]), 1.5), "eigene Farbe, Helligkeit × Raum, Reichweite")
	rl.licht.lf = "#2fd6ff"
	check(Welt.licht_von(rl, { "t": "tischlampe" })[0] == Color("#2fd6ff"), "gemeinsame Lampenfarbe des Raums")
	check(Welt.licht_von(rl, { "t": "led_leiste" })[0] == Color(str(rl.licht.fa)), "LED-Leiste leuchtet in der LED-Farbe")
	rl.licht.lf = ""
	rl.licht.k = 4000
	var l3: Array = Welt.licht_von(rl, { "t": "stehlampe" })
	check((l3[0] as Color).b > Moebel.WARM.b, "4000 K: kühler als warmweiß")

	print("Neue Raumgröße")
	var gr := Daten.pruefe_raum(Daten.standard_raum())
	var anzahl := (gr.moebel as Array).size()
	var weg := Zimmer.umziehen(gr, 16, 12)
	check(weg == 0 and (gr.moebel as Array).size() == anzahl, "größer: nichts fällt weg")
	check(Daten.pruefe_raum(gr).moebel.size() == anzahl, "größer: alles passt weiter")
	# Das Regal an der rechten Wand (Standardzimmer: Spieleregal, gedreht zur rechten Wand).
	var schrank: Array = (gr.moebel as Array).filter(func(x: Dictionary) -> bool: return str(x.t) == "spieleregal" and int(x.r) == 3)
	check(not schrank.is_empty() and int(schrank[0].x) + Katalog.groesse_it(schrank[0]).x == 16, "Schrank an der rechten Wand wandert mit")
	var weg2 := Zimmer.umziehen(gr, 8, 8)
	var nach := Daten.pruefe_raum(gr)
	check((nach.moebel as Array).size() == (gr.moebel as Array).size(),
			"kleiner: was bleibt, passt (%d bleiben, %d ohne Platz)" % [(gr.moebel as Array).size(), weg2])
	check(weg2 + (gr.moebel as Array).size() == anzahl, "kleiner: nichts geht verloren, ohne es zu zählen")

	print("Vorlagen")
	for v in Vorlagen.LISTE:
		var id := str(v[0])
		var roh := Vorlagen.roh(id)
		var fertig := Vorlagen.raum(id)
		check(not fertig.is_empty() and (fertig.moebel as Array).size() == (roh.moebel as Array).size(),
				"Vorlage „%s“: alle %d Möbel passen" % [id, (roh.moebel as Array).size()])
		var hat_regal := (fertig.moebel as Array).any(func(x: Dictionary) -> bool: return str(x.t) == "spieleregal")
		var hat_tv := (fertig.moebel as Array).any(func(x: Dictionary) -> bool: return str(x.t) == "medienwand")
		if not (hat_regal and hat_tv):
			check(false, "Vorlage „%s“ hat Regal und Fernseher" % id)

	print("Spiele im Regal")
	var spiele: Array = [
		{ "id": "a", "title": "Zelda", "system": "snes", "playtime": 3600, "last_played": 300, "favorite": true, "status": "durch", "genres": ["Abenteuer"] },
		{ "id": "b", "title": "Astro", "system": "steam", "playtime": 90000, "last_played": 100, "tags": ["Koop"], "genres": ["Action"] },
		{ "id": "c", "title": "Metroid", "system": "snes", "playtime": 0, "last_played": 0, "status": "will", "category": "Sammlung A" },
	]
	var ids := func(l: Array) -> Array: return l.map(func(x: Dictionary) -> String: return str(x.id))
	check(ids.call(Inhalt.sortiert(spiele, "titel")) == ["b", "c", "a"], "nach Titel")
	check(ids.call(Inhalt.sortiert(spiele, "zuletzt")) == ["a", "b", "c"], "zuletzt gespielt zuerst")
	check(ids.call(Inhalt.sortiert(spiele, "spielzeit")) == ["b", "a", "c"], "nach Spielzeit")
	check(ids.call(Inhalt.sortiert(spiele, "backlog")) == ["c", "a", "b"], "nach Backlog-Status (Will ich spielen vor Durchgespielt, ohne Status zuletzt)")
	check(ids.call(Inhalt.sortiert(spiele, "genre")) == ["a", "b", "c"], "nach Genre: Abenteuer, Action, ohne Genre zuletzt")
	check(ids.call(Inhalt.sortiert(spiele, "manuell", ["c", "a"])) == ["c", "a", "b"], "eigene Reihenfolge, Neues dahinter")
	var f := func(fi: String) -> Array: return ids.call(spiele.filter(func(x: Dictionary) -> bool: return Inhalt.passt_filter(x, fi)))
	check(f.call("system:snes") == ["a", "c"] and f.call("favoriten") == ["a"] and f.call("ungespielt") == ["c"], "Auswahl: System, Favoriten, ungespielt")
	check(f.call("tag:Koop") == ["b"] and f.call("sammlung:Sammlung A") == ["c"] and f.call("status:will") == ["c"] and f.call("genre:Action") == ["b"],
			"Auswahl: Tag, Sammlung, Backlog-Status, Genre")
	check(f.call("alle").size() == 3 and f.call("system:gibtsnicht").is_empty(), "alle bzw. keins")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

extends Node
## Figur und Haustier (Punkt 131 c, d): Daten streng prüfen (festes Schema, nur Kennungen, Name mit
## Grenzen), Laden/Speichern mit Rückfall, nur Freies tragen, Meilensteine nur durchs Spielen, die
## Meldung neuer Freischaltungen genau einmal, was Gäste später sehen dürfen, und die Möbel dazu.
## Aufruf: godot --headless --path . res://tests/logic_zfigur.tscn

const D := preload("res://src/room/figur/figur_daten.gd")
const M := preload("res://src/room/figur/meilensteine.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const P := preload("res://src/room/netz_protokoll.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _datei(text: String) -> String:
	var p := OS.get_user_data_dir().path_join("figur_test_%d.json" % randi())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p


func _ready() -> void:
	print("Standard")
	var std := D.standard()
	check(D.pruefe(std) == std, "Standard besteht die Prüfung unverändert")
	check(D.pruefe(D.pruefe(std)) == D.pruefe(std), "Prüfen ist stabil")
	for e in D.FIGUR_FELDER + D.TIER_FELDER:
		if not D.gueltig(e[3], str(e[4])):
			check(false, "Standard von %s steht in seiner Liste" % e[0])
	check(true, "jeder Standardwert steht in seiner Liste (%d Felder)" % (D.FIGUR_FELDER.size() + D.TIER_FELDER.size()))
	var frauen := D.PERSONEN.filter(func(p: Array) -> bool: return str(p[2]) == "w").size()
	var maenner := D.PERSONEN.filter(func(p: Array) -> bool: return str(p[2]) == "m").size()
	check(frauen >= 8 and maenner >= 6 and D.TIER_ARTEN.size() >= 5, "Vielfalt: %d Frauen, %d Männer, fünf Tierarten" % [frauen, maenner])
	var dateien_ok := true
	for p in D.PERSONEN:
		dateien_ok = dateien_ok and ResourceLoader.exists("res://assets/figur/psx/%s.fbx" % p[0]) and ResourceLoader.exists("res://assets/figur/psx/%s.png" % p[0])
	# Die Modelle liegen nur beim Herausgeber (nicht im öffentlichen Repository, assets/figur/LIZENZ.txt).
	var FPS: GDScript = load("res://src/room/figur/figur_psx.gd")
	if FPS.vorhanden():
		check(dateien_ok, "jede Figur hat Modell und Textur")
	else:
		print("  –    Figuren-Modelle nicht da (Build aus dem öffentlichen Repository): Prüfung der Dateien übersprungen")
	var av_src := FileAccess.get_file_as_string("res://src/room/figur/avatar.gd")
	check(av_src.contains("if _md.is_empty():") and FileAccess.get_file_as_string("res://src/room/figur/figur_psx.gd").contains("return {}   # Ohne die Modelle"),
			"ohne Modelle: leere Figur statt Absturz")
	var schluessel := {}
	for e in D.FIGUR_FELDER:
		schluessel[e[0]] = true
	check(schluessel.size() == D.FIGUR_FELDER.size(), "Feldnamen sind eindeutig")

	print("Strenge Prüfung")
	check(D.pruefe(null).is_empty() and D.pruefe([]).is_empty() and D.pruefe("x").is_empty(), "kein Wörterbuch: abgelehnt")
	check(D.pruefe({ "format": "anders", "version": 1 }).is_empty(), "fremdes Format: abgelehnt")
	check(D.pruefe({ "format": D.FORMAT, "version": 2 }).is_empty() and D.pruefe({ "format": D.FORMAT, "version": "1" }).is_empty(), "falsche Fassung: abgelehnt")
	var boese := {
		"format": D.FORMAT, "version": 1,
		"figur": { "person": "res://boese.gd", "kopf": "kranz", "skript": "OS.execute()", "ohren": ["gold"] },
		"tier": { "art": "einhorn", "fell": "mint", "name": "Fluffy\u0007\n<b>[url]x[/url]</b>" + String.chr(0x202e) + "" + "a".repeat(80) },
		"zusatz": { "groß": true },
	}
	var g := D.pruefe(boese)
	check(not g.is_empty() and g.keys().size() == 4 and not g.has("zusatz"), "unbekannte Felder fallen weg")
	check(str(g.figur.person) == "lea", "ungültige Figur wird zum Standard")
	check(g.figur.keys() == ["person"], "nur die Figur, keine alten oder fremden Felder")
	var gut := D.pruefe({ "format": D.FORMAT, "version": 1, "figur": { "person": "noah" } })
	check(str(gut.figur.person) == "noah", "gültige Figur bleibt")
	check(not (g.figur as Dictionary).has("skript"), "keine fremden Schlüssel in der Figur")
	check(str(g.tier.art) == "katze" and str(g.tier.fell) == "mint", "Tierart unbekannt: Standard, Fell bleibt")
	var nm := str(g.tier.name)
	check(nm.length() <= D.MAX_NAME, "Name höchstens %d Zeichen (%d)" % [D.MAX_NAME, nm.length()])
	check(not ("<" in nm or "[" in nm or "\n" in nm or "\u0007" in nm or "" + String.chr(0x202e) + "" in nm),
			"Name ohne Steuer-, Format- und Richtungszeichen: „%s“" % nm)
	check(D.pruefe_gemeldet(["stunden_100", "../../x", 3, "stunden_100"]) == ["stunden_100"] and D.pruefe_gemeldet("x") == [],
			"gemeldet: nur Kennungen, ohne Doppelte")
	check(D.name_sauber("  Mö  Ü-chen. ") == "Mö Ü-chen." and D.name_sauber("") == D.TIER_NAME and D.name_sauber(42) == D.TIER_NAME,
			"Namen: Umlaute ja, Leerraum gekürzt, leer = Standard")
	check(D.name_sauber("ミケ") == "ミケ" and D.name_sauber("😀😀") == D.TIER_NAME, "andere Schriften ja, Emojis nein")
	check(D.aus_text("{ kaputt").is_empty() and D.aus_text("[]").is_empty(), "kaputtes JSON: abgelehnt")
	check(D.aus_text("{\"format\":\"uzai-figur\",\"x\":\"" + "a".repeat(D.MAX_BYTES) + "\"}").is_empty(), "zu groß: gar nicht erst gelesen")

	print("Gäste")
	var gast := D.fuer_gaeste(boese)
	check(gast.keys().size() == 4 and not gast.has("gemeldet"), "Gäste sehen nur Figur und Tier, nicht den eigenen Spielstand")
	var txt := JSON.stringify(gast)
	check(txt.length() < 1500, "Gast-Daten sind klein (%d Bytes)" % txt.length())
	check(D.pruefe(JSON.parse_string(txt)).figur == gast.figur, "Gast-Daten lassen sich wieder prüfen")

	print("In zimmer.json (Fassung 2)")
	var zstd := Daten.standard()
	check(zstd.has("figur") and zstd.has("tier") and zstd.gemeldet == [], "Standardzimmer bringt Figur und Haustier mit")
	check(Daten.pruefe(zstd).figur == D.standard_figur() and Daten.pruefe(zstd).tier == D.standard_tier(), "Prüfen lässt den Standard unverändert")
	var zboese := Daten.standard()
	zboese.figur = boese.figur
	zboese.tier = boese.tier
	zboese.gemeldet = ["stunden_100", "../../x", 3]
	var zg := Daten.pruefe(zboese)
	check(zg.figur == g.figur and zg.tier == g.tier and zg.gemeldet == ["stunden_100"], "im Zimmer genauso streng geprüft wie im Gast-Paket")
	var ohne := Daten.standard()
	ohne.erase("figur")
	ohne.erase("tier")
	ohne.erase("gemeldet")
	ohne.version = 1
	check(Daten.pruefe(ohne).figur == D.standard_figur() and Daten.pruefe(ohne).gemeldet == [], "ältere Datei ohne Figur: Standardfigur")
	var pfad := OS.get_user_data_dir().path_join("figur_test_zimmer.json")
	var neu := Daten.standard()
	neu.figur.person = "finn"
	neu.tier.art = "drache"
	neu.tier.name = "Funke"
	neu.gemeldet = ["stunde_1"]
	check(Daten.speichern(neu, pfad), "speichern klappt")
	var zurueck := Daten.laden(pfad)
	check(str(zurueck.figur.person) == "finn" and str(zurueck.tier.name) == "Funke" and zurueck.gemeldet == ["stunde_1"],
			"laden gibt Figur, Tier und Gemeldetes zurück")
	DirAccess.remove_absolute(pfad)
	DirAccess.remove_absolute(pfad + ".bak")

	print("Netz: Figur-Nachricht")
	var nachricht := P.schreiben("figur", D.fuer_gaeste(boese))
	check(nachricht.size() == 8, "Figur und Haustier passen in eine Nachricht (%d Bytes, nur Nummern)" % nachricht.size())
	var gelesen := P.lesen(nachricht, false)
	check(str(gelesen.get("a", "")) == "figur" and (gelesen.d as Dictionary).figur == g.figur and str(gelesen.d.tier.art) == str(g.tier.art),
			"Gäste-Figur wird genau wie die eigene geprüft")
	check(str(gelesen.d.tier.name) == D.TIER_NAME, "der Name des Haustiers geht nicht übers Netz")
	for e in ["winken", "jubeln", "tanzen", "daumen", "klatschen", "sitzen", "zucken"]:
		if not (e in P.EMOTES):
			check(false, "Emote %s ist im Netz erlaubt" % e)
	check(P.EMOTES.size() == 7, "alle Emotes der Figur sind im Netz erlaubt, sonst keine")

	print("Meilensteine – nur durchs Spielen")
	check(M.erreicht({}).is_empty(), "ohne Spielen: nichts erreicht")
	var f := { "hours_total": 120.5, "games_played": 12, "perfect": 1, "ach_total": 30, "streak_best": 7 }
	var er := M.erreicht(f)
	check("stunden_100" in er and "stunden_10" in er and "stunde_1" in er and "platin_1" in er and "serie_7" in er,
			"100 Stunden, erstes Platin, 7-Tage-Serie erreicht")
	check(not ("spiele_50" in er) and not ("erfolge_100" in er), "50 Spiele und 100 Erfolge noch nicht")
	check(M.erreicht({ "hours_total": "999", "perfect": NAN }).is_empty() or not ("stunden_100" in M.erreicht({ "hours_total": "999" })),
			"Text statt Zahl zählt nicht")
	check(M.ist_frei("person:mia", []) and not M.ist_frei("person:sara", []) and M.ist_frei("person:sara", er), "Sara erst nach dem ersten Platin")
	check(not M.ist_frei("moebel:lavalampe", []) and M.ist_frei("moebel:lavalampe", er) and not M.ist_frei("moebel:neonschild", er),
			"Lavalampe nach 100 Stunden, Leuchtschild nach 50 Spielen")
	check(M.bedingung("person:sara", []) != "" and M.bedingung("person:sara", er) == "", "Bedingung nur, solange gesperrt")
	var getragen := D.standard_figur()
	getragen.person = "leon"
	check(str(M.nur_freies(getragen, D.FIGUR_FELDER, er).person) == "lea", "nur Freies wird getragen (Leon fällt zurück)")
	getragen.person = "sara"
	check(str(M.nur_freies(getragen, D.FIGUR_FELDER, er).person) == "sara", "Freigeschaltetes bleibt (Sara nach dem Platin)")
	check(not M.ist_frei("person:juna", []) and M.ist_frei("person:juna", er) and M.ist_frei("person:mia", []), "Juna nach 10 Stunden, die anderen gleich")
	var tier := D.standard_tier()
	tier.muster = "sterne"
	check(str(M.nur_freies(tier, D.TIER_FELDER, [], "tier_").muster) == "bauch", "Sternenfell erst nach 100 Erfolgen")
	for m in M.LISTE:
		for fr in m.frei:
			var teile := str(fr).split(":")
			var ok := false
			if teile[0] == "moebel":
				ok = Katalog.has(teile[1])
			else:
				var feld := teile[0].trim_prefix("tier_")
				var felder := D.TIER_FELDER if teile[0].begins_with("tier_") else D.FIGUR_FELDER
				var e := D.feld(felder, feld)
				ok = not e.is_empty() and D.gueltig(e[3], teile[1]) and str(e[4]) != teile[1]
			if not ok:
				check(false, "Freigabe %s gibt es wirklich (und nicht als Standard)" % fr)
		if not M.NAMEN.has(str(m.frei[0])):
			check(false, "Freigabe %s hat einen Namen" % m.frei[0])
	check(true, "alle %d Meilensteine geben echte Dinge frei" % M.LISTE.size())

	print("Meldungen genau einmal")
	var neue := M.neu(er, [])
	check(neue.size() == er.size(), "beim ersten Mal: alles Erreichte ist neu")
	check(M.neu(er, er).is_empty(), "danach: nichts doppelt")
	var t1 := M.meldung(["platin_1"])
	check(t1[0].contains("Sara") and t1[1] != "", "eine Freischaltung: Titel nennt die Sache")
	var t2 := M.meldung(neue)
	check(t2[0].contains("%d" % 7) or t2[0].contains("neue"), "mehrere: eine Zusammenfassung („%s“)" % t2[0])
	check(M.meldung([])[0] == "", "nichts Neues: keine Meldung")
	check(is_equal_approx(M.fortschritt("stunden_100", { "hours_total": 50 }), 0.5), "Fortschritt zum nächsten Meilenstein")

	print("Möbel dazu")
	for id in ["jackenstaender", "tierkorb", "lavalampe", "neonschild"]:
		check(Katalog.has(id) and Katalog.variante_gueltig(id, Katalog.std_variante(id)), "%s steht im Katalog" % id)
	check(not Katalog.has("spiegel") and Katalog.ERSETZT.get("spiegel") == "jackenstaender", "kein Spiegel mehr (keine zweite Ansicht): Jackenständer an seiner Stelle")
	var raum := Daten.standard_raum()
	var hat := false
	for m2 in raum.moebel:
		hat = hat or str(m2.t) == "jackenstaender"
		check(str(m2.t) != "spiegel", "Standardzimmer ohne Spiegel")
	check(hat, "Standardzimmer hat einen Jackenständer")
	check((Daten.pruefe(Daten.standard()).raeume[0].moebel as Array).size() == (raum.moebel as Array).size(), "Jackenständer passt (nichts fällt weg)")
	check(Katalog.nutzen("jackenstaender") == "figur" and Katalog.nutzen("tierkorb") == "tier", "Jackenständer wechselt die Figur, Körbchen das Haustier")

	print("Alte Zimmer mit Spiegel")
	var alt := Daten.standard_raum()
	alt.moebel = [{ "t": "spiegel", "x": 3, "z": 9, "r": 2, "v": "walnuss", "an": true }]
	var umgezogen := Daten.pruefe_raum(alt)
	check((umgezogen.moebel as Array).size() == 1 and str(umgezogen.moebel[0].t) == "jackenstaender" and int(umgezogen.moebel[0].x) == 3
			and int(umgezogen.moebel[0].z) == 9 and str(umgezogen.moebel[0].v) == "walnuss", "Spiegel → Jackenständer an derselben Stelle, Holz bleibt")
	alt.moebel = [{ "t": "sofa", "x": 2, "z": 8, "r": 2, "v": "salbei", "an": true }, { "t": "spiegel", "x": 3, "z": 9, "r": 2, "v": "eiche", "an": true }]
	umgezogen = Daten.pruefe_raum(alt)
	check((umgezogen.moebel as Array).size() == 2 and str(umgezogen.moebel[1].t) == "jackenstaender" and Daten.passt(umgezogen, umgezogen.moebel[1], 1),
			"steht davor schon etwas: der Jackenständer gleich daneben, nichts fällt weg")
	var b := FileAccess.get_file_as_string("res://src/room/figur/bewohner.gd")
	check(b.find("SubViewport") < 0 and b.find("spiegel") < 0 and not FileAccess.file_exists("res://src/room/figur/shaders/spiegel.gdshader"),
			"kein Spiegelbild mehr: keine zweite Ansicht, kein Spiegel-Shader")
	var ze := FileAccess.get_file_as_string("res://src/room/zimmer_einrichten.gd")
	var gd := FileAccess.get_file_as_string("res://src/room/figur/garderobe.gd")
	check(ze.substr(ze.find("func _figur_wechseln"), 300).contains("bewohner.garderobe_auf()") and gd.contains("bewohner.vor_figur(true)")
			and b.contains("or _vor_figur"), "Jackenständer: die Kamera tritt vor die Figur, die Figur wechselt gleich im Zimmer (Leiste, kein Menü)")
	check(gd.contains("bewohner.avatar.bauen({ \"person\"") and gd.contains("bewohner.avatar.bauen(_vorher)") and gd.contains("M.nur_freies("),
			"←/→ zieht an, B nimmt zurück, behalten nur, was frei ist")
	_jackenstaender_bau()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Jackenständer gebaut: wenige Netze (je Stoff eins), Eckpunkte im Rahmen, Kleidung aus Stoff in gedeckten
## Farben; der Schlauch (formen.gd) zeigt nach außen und wird von außen gezeichnet.
func _jackenstaender_bau() -> void:
	var Moebel := load("res://src/room/moebel.gd")
	var F := load("res://src/room/formen.gd")
	var n: Node3D = Moebel.bauen("jackenstaender", "eiche")
	var netze := 0
	var punkte := 0
	var stoffe := 0
	var bunt := 0.0
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		netze += 1
		var arr := mi.mesh.surface_get_arrays(0)
		punkte += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var sm := mi.material_override as ShaderMaterial
		if sm != null and sm.get_shader_parameter("farbe") is Color:
			stoffe += 1
			var f: Color = sm.get_shader_parameter("farbe")
			bunt = maxf(bunt, f.s * f.v)
	print("  Jackenständer: %d Netze, %d Eckpunkte, %d Stoffe" % [netze, punkte, stoffe])
	check(netze <= 5 and punkte < 25000, "Jackenständer: höchstens 5 Netze, unter 25000 Eckpunkten (%d, %d)" % [netze, punkte])
	check(stoffe == 4 and bunt < 0.5, "Mantel, Schal, Mütze und Tasche aus Stoff, gedeckte Farben (Sättigung × Helligkeit %.2f)" % bunt)
	n.free()
	# Gerader Schlauch längs y: Normalen nach außen, Dreiecke von außen im Uhrzeigersinn (Godot: vorn).
	var m: ArrayMesh = F.schlauch(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 1, 0)]),
			PackedFloat32Array([0.1, 0.1, 0.1]), PackedFloat32Array([0.05, 0.05, 0.05]), PackedVector3Array([Vector3.RIGHT]),
			16, 2, Vector3(5, 0.005, 0.01), PI * 0.5, Vector2(-1.0, -1.0))
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var aussen := true
	for i in v.size():
		aussen = aussen and nr[i].dot(Vector3(v[i].x, 0, v[i].z)) > 0.0
	var vorn := true
	for t in range(0, idx.size(), 3):
		var p0 := v[idx[t]]
		var mitte := (p0 + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		vorn = vorn and (v[idx[t + 1]] - p0).cross(v[idx[t + 2]] - p0).dot(Vector3(mitte.x, 0, mitte.z)) < 0.0
	check(aussen and vorn, "Schlauch: Normalen nach außen, von außen sichtbar")
	# Winkel PI/2 liegt auf Tangente × quer: hier (y × x) hinten, bei −z.
	var leiste := 0
	var glatt := true
	for i in v.size():
		if v[i].z < -0.045 and absf(v[i].x) < 0.002:
			leiste += 1
			glatt = glatt and absf(v[i].z + 0.05) < 0.0005
	check(leiste > 0 and glatt, "Schlauch: an der Knopfleiste keine Falten (%d Punkte)" % leiste)

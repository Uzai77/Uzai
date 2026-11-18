extends Node
## Plattenspieler und Konsolen im Zimmer: welche Konsolen für welche Systeme (eingerichtet = an und
## mit Spielen, PC dazu), Staffelung im Lowboard ohne Überlappen, Modelle ohne Schrift und mit
## wenigen Flächen, Strom und Einlegen, Plattenteller dreht nur bei Wiedergabe (33⅓ U/min), Tonarm
## auf und zurück, Cover nur aus dem eigenen Speicher über load_*_from_buffer (nie ResourceLoader).
## Aufruf: godot --headless --path . res://tests/logic_plattenkonsole.tscn

const Konsolen := preload("res://src/room/konsolen.gd")
const Platten := preload("res://src/room/plattenspieler.gd")
const Moebel := preload("res://src/room/moebel.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_auswahl()
	_staffeln()
	_modelle()
	_lowboard()
	_teller()
	_cover()
	_quelltext()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _auswahl() -> void:
	print("Welche Konsolen im Schrank stehen")
	var aktiv := ["ps2", "ps1", "gc", "gba", "switch", "wii"]
	var zahl := { "ps2": 10, "ps1": 6, "gc": 6, "gba": 5, "switch": 3, "n64": 4 }
	var ids := Konsolen.auswahl(aktiv, zahl, 20)
	check(ids == ["ps2", "ps1", "gc", "gba", "switch", "pc"], "eingeschaltet und mit Spielen, meiste zuerst, PC zuletzt: %s" % str(ids))
	check(not ("wii" in ids) and not ("n64" in ids), "ohne Spiele (Wii) bzw. ausgeschaltet (N64): keine Konsole")
	check(Konsolen.auswahl(aktiv, zahl, 0).size() == 5, "ohne PC-Spiele kein PC")
	check(Konsolen.auswahl([], {}, 0).is_empty(), "nichts eingerichtet: keine Konsole (die Fantasie-Konsole bleibt)")
	check(Konsolen.fuer_spiel("gc", false, ids) == "gc" and Konsolen.fuer_spiel("steam", true, ids) == "pc", "Spiel läuft auf seiner Konsole, Steam auf dem PC")
	check(Konsolen.fuer_spiel("n64", false, ids) == "" and Konsolen.fuer_spiel("steam", true, ["gc"]) == "", "ohne passende Konsole: keine")
	check(Konsolen.modell("mein_system") == "allgemein" and Konsolen.modell("gc") == "gc", "eigene Systeme: schlichtes Gehäuse")


func _staffeln() -> void:
	print("Staffelung im Lowboard")
	var leer := Konsolen.staffeln([])
	check(int(leer.stufe) == 0 and not bool(leer.offen) and (leer.plaetze as Array).is_empty(), "keine Konsolen: Mitte, Türen zu")
	var zwei := Konsolen.staffeln(["ps2", "gc"])
	check(int(zwei.stufe) == 0 and (zwei.plaetze as Array).all(func(p: Dictionary) -> bool: return p.fach == "mitte"), "zwei passen ins Mittelfach")
	var demo := Konsolen.staffeln(["ps2", "ps1", "gc", "gba", "switch", "pc"])
	check(int(demo.stufe) == 1 and bool(demo.offen) and (demo.uebrig as Array).is_empty(), "sechs: Seiten werden offene Fächer, alle haben Platz")
	check(_ohne_ueberlappen(demo), "sechs: nichts überlappt, alles im Fach")
	var viele: Array = ["ps2", "ps1", "gc", "n64", "snes", "megadrive", "dreamcast", "xbox", "wii", "switch", "nes", "saturn", "gba", "psp", "pc"]
	var v := Konsolen.staffeln(viele)
	check(int(v.stufe) >= 2, "fünfzehn: Zwischenböden (Stufe %d)" % int(v.stufe))
	check((v.plaetze as Array).size() + (v.uebrig as Array).size() == viele.size(), "jede Konsole steht oder ist gezählt übrig")
	check(_ohne_ueberlappen(v), "fünfzehn: nichts überlappt, nichts zu hoch")
	var mitte_zuerst: Dictionary = (demo.plaetze as Array).filter(func(p: Dictionary) -> bool: return p.id == "ps2")[0]
	check(str(mitte_zuerst.fach) == "mitte", "die mit den meisten Spielen steht in der Mitte am Fernseher")


func _ohne_ueberlappen(lage: Dictionary) -> bool:
	var ebs := Konsolen.ebenen(lage.ebenen)
	for e: Dictionary in ebs:
		var drin: Array = (lage.plaetze as Array).filter(func(p: Dictionary) -> bool: return p.fach == e.fach and int(p.ebene) == int(e.ebene))
		drin.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
		var rechts := float(e.x0) - 1.0
		for p: Dictionary in drin:
			var m := Konsolen.masse(str(p.id))
			var l := float(p.x) - m.x * 0.5
			if l < float(e.x0) - 0.0001 or float(p.x) + m.x * 0.5 > float(e.x1) + 0.0001 or l < rechts + 0.01 or m.y > float(e.h):
				return false
			if absf(float(p.y) - float(e.y)) > 0.0001:
				return false
			rechts = float(p.x) + m.x * 0.5
	return true


func _modelle() -> void:
	print("Modelle: eigene Geometrie, wenige Flächen, ohne Schrift")
	var gut := true
	var flaechen := 0
	for id: String in Konsolen.MASSE:
		var k := Konsolen.bauen(id, Color("#556677"))
		add_child(k)
		var nah := k.get_child(0) as MeshInstance3D
		var fern := k.get_child(1) as MeshInstance3D
		flaechen = maxi(flaechen, nah.mesh.get_surface_count())
		if not k.has_meta("einlass") or not k.has_meta("led") or nah.visibility_range_end != Konsolen.FERN or fern.visibility_range_begin != Konsolen.FERN:
			gut = false
			print("    ", id, ": Meta oder Fernstufe fehlt")
		if not k.find_children("*", "Label3D", true, false).is_empty():
			gut = false
		var aabb := nah.get_aabb()
		var m: Vector3 = k.get_meta("masse")
		if aabb.size.x > m.x * 1.25 + 0.002 or aabb.size.y > m.y * 1.25 + 0.002:
			gut = false
			print("    ", id, ": größer als die Maße ", aabb.size, " ", m)
		k.queue_free()
	check(gut, "alle %d Modelle: Einlass, LED, Fernstufe, keine Schrift, Maße stimmen" % Konsolen.MASSE.size())
	check(flaechen <= 8, "höchstens 8 Flächen je Konsole (Draw Calls): %d" % flaechen)
	var gc := Konsolen.bauen("gc")
	add_child(gc)
	check(str(gc.get_meta("medium")) == "minidisc" and gc.has_meta("klappe"), "GameCube: Mini-Disc unter dem Deckel")
	check(str(Konsolen.bauen("n64").get_meta("medium")) == "modul" and str(Konsolen.bauen("ps2").get_meta("medium")) == "disc", "N64 Modul, PS2 Disc")
	Konsolen.strom(gc, true)
	var led: StandardMaterial3D = gc.get_meta("led")
	check(led.emission_energy_multiplier > 1.0 and Konsolen.ist_an(gc), "Strom an: LED leuchtet")
	Konsolen.strom(gc, false)
	check(led.emission_energy_multiplier == 0.0 and not Konsolen.ist_an(gc), "Strom aus: LED aus")
	Konsolen.einstecken(gc, Color.RED)
	var ein: Node3D = gc.get_meta("einlass")
	check(ein.get_child_count() == 1 and Konsolen.ist_an(gc), "eingesteckt: Disc im Einlass, LED an")
	check(gc.get_meta("klappe_auf") != gc.get_meta("klappe_zu"), "Deckel hat eine offene Stellung")
	var weg := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)])
	check(Konsolen.entlang(weg, 0.5).is_equal_approx(Vector3(1, 0, 0)) and Konsolen.entlang(weg, 1.0).is_equal_approx(Vector3(1, 1, 0)),
			"Lichtpunkt läuft das Kabel entlang")


func _lowboard() -> void:
	print("Lowboard der Medienwand")
	Moebel.konsolen = ["ps2", "ps1", "gc", "gba", "switch", "pc"]
	var n := Moebel.bauen("medienwand", "flach")
	Moebel.konsolen = []
	add_child(n)
	var ks: Dictionary = n.get_meta("konsolen", {})
	check(ks.size() == 6 and not n.has_meta("schlitz"), "sechs Konsolen im Lowboard, keine Fantasie-Konsole")
	var boxen: Array = []
	for id: String in ks:
		var k: Node3D = ks[id]
		var m: Vector3 = k.get_meta("masse")
		boxen.append(AABB(k.position - Vector3(m.x * 0.5, 0, m.z * 0.5), m))
	var frei := true
	for i in boxen.size():
		for j in range(i + 1, boxen.size()):
			if (boxen[i] as AABB).grow(-0.001).intersects(boxen[j]):
				frei = false
	check(frei, "Konsolen berühren sich nicht")
	check((ks.values() as Array).all(func(k: Node3D) -> bool: return k.has_meta("kabel_weg")), "jede Konsole mit Kabel nach hinten")
	var leer := Moebel.bauen("medienwand", "flach")
	add_child(leer)
	check(leer.has_meta("schlitz") and not leer.has_meta("konsolen"), "ohne Systeme: die eigene Fantasie-Konsole wie bisher")


func _teller() -> void:
	print("Plattenteller und Tonarm")
	check(absf(Platten.DREH * 60.0 / TAU - 100.0 / 3.0) < 0.0001, "33⅓ U/min")
	var z := Platten.neu()
	var dt := 1.0 / 60.0
	var dreht_nie := true
	for i in 120:
		z = Platten.schritt(z, false, 0.0, dt)
		if float(z.dreh) != 0.0 or float(z.winkel) != 0.0:
			dreht_nie = false
	check(dreht_nie and float(z.arm) == Platten.ARM_RUHE, "ohne Wiedergabe: Teller steht, Arm auf der Stütze")
	var hob := false
	for i in 60:
		z = Platten.schritt(z, true, 0.0, dt)
		hob = hob or float(z.hub) > 0.5
	check(is_equal_approx(float(z.dreh), Platten.DREH), "nach einer Sekunde volle Drehzahl")
	for i in 180:
		z = Platten.schritt(z, true, 0.0, dt)
	check(hob and absf(float(z.arm) - Platten.ARM_AUSSEN) < 0.002 and float(z.hub) == 0.0, "Arm gehoben, geschwenkt, auf der Einlaufrille abgesenkt")
	var vorher := float(z.arm)
	for i in 60:
		z = Platten.schritt(z, true, 0.5, dt)
	check(float(z.arm) > vorher and float(z.hub) == 0.0, "der Arm wandert mit dem Titel nach innen, ohne sich zu heben")
	for i in 240:
		z = Platten.schritt(z, false, 0.5, dt)
	check(float(z.dreh) == 0.0 and float(z.arm) == Platten.ARM_RUHE and float(z.hub) == 0.0, "Pause: Teller läuft aus, Arm zurück auf die Stütze %s")
	var r := Platten.schritt(Platten.neu(), true, 0.0, dt, true)
	check(float(r.dreh) == Platten.DREH and float(r.arm) == Platten.ARM_AUSSEN, "Animationen reduzieren: sofort am Ziel")
	var ps := Moebel.bauen("plattenspieler", "walnuss")
	add_child(ps)
	var hat := ["teller", "tonarm", "tonarm_hub", "huelle", "huelle_bild", "etikett", "etikett_bild", "ps_led"].all(func(k: String) -> bool: return ps.has_meta(k))
	check(hat, "Plattenspieler: Teller, Tonarm mit Lift, Hülle, Etikett, Drehzahl-LED")
	Platten.anwenden(ps, { "dreh": Platten.DREH, "winkel": 1.0, "arm": 0.5, "hub": 0.0 })
	check(is_equal_approx((ps.get_meta("tonarm") as Node3D).rotation.y, -0.5) and is_equal_approx((ps.get_meta("teller") as Node3D).rotation.y, -1.0),
			"Zustand landet auf Teller und Arm")
	check(not (ps.get_meta("huelle") as Node3D).visible, "läuft nichts: keine Hülle")


func _cover() -> void:
	print("Cover: nur eigener Speicher, nur aus Bytes")
	var cache := "C:/Users/du/AppData/Roaming/Uzai/cache"
	var temp := "C:/Users/du/AppData/Local/Temp"
	var url := "https://i.scdn.co/image/ab67616d0000b273abc"
	check(Platten.cover_pfad(url, cache, temp) == cache + "/img/web/%s.jpg" % url.md5_text(), "Spotify-Bild: der Platz im Zwischenspeicher der Musik")
	check(Platten.cover_pfad(cache + "/musik/cover/a.jpg", cache, temp) != "", "eigene Musik: Cover aus cache/musik")
	check(Platten.cover_pfad(temp + "\\uzai-cover-123.png", cache, temp) != "", "Windows-Mediensitzung: uzai-cover-*.png des Helfers")
	check(Platten.cover_pfad(temp + "/anderes.png", cache, temp) == "" and Platten.cover_pfad("C:/Users/du/Music/folder.jpg", cache, temp) == "",
			"fremde Dateien: nein")
	check(Platten.cover_pfad(cache + "/../geheim.png", cache, temp) == "" and Platten.cover_pfad("//server/freigabe/a.png", cache, temp) == "",
			"kein .. und keine Freigaben")
	check(Platten.cover_pfad(cache + "/x.tres", cache, temp) == "", "nur Bildendungen")
	var dir := OS.get_user_data_dir().path_join("plattenkonsole_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(1024, 768, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.2, 0.1))
	img.save_png(dir.path_join("a.png"))
	var gel := Platten.cover_laden(dir.path_join("a.png"))
	check(gel != null and gel.get_width() == Platten.COVER_SEITE and gel.get_height() == Platten.COVER_SEITE, "PNG geladen, quadratisch, auf 512 verkleinert")
	check(gel != null and Platten.mittelfarbe(gel).r > 0.7, "mittlere Farbe für die Kante der Hülle")
	img.save_jpg(dir.path_join("b.png"))
	check(Platten.cover_laden(dir.path_join("b.png")) != null, "Format nach den Bytes, nicht nach der Endung (JPG in .png)")
	var f := FileAccess.open(dir.path_join("kaputt.png"), FileAccess.WRITE)
	f.store_buffer(
			PackedByteArray([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]))
	f.close()
	check(Platten.cover_laden(dir.path_join("kaputt.png")) == null, "kaputte Datei: kein Bild")
	var riesig := Image.create(2100, 64, false, Image.FORMAT_L8)
	riesig.save_png(dir.path_join("riesig.png"))
	check(Platten.cover_laden(dir.path_join("riesig.png")) == null, "mehr als 2048 Punkte je Seite: abgelehnt")
	var gross := PackedByteArray()
	gross.resize(Platten.COVER_MAX_BYTES + 1)
	check(Platten.cover_aus_bytes(gross) == null, "mehr als 4 MB: abgelehnt")
	for n in ["a.png", "b.png", "kaputt.png", "riesig.png"]:
		DirAccess.remove_absolute(dir.path_join(n))


func _quelltext() -> void:
	print("Quelltext")
	var ps := _ohne_kommentare(FileAccess.get_file_as_string("res://src/room/plattenspieler.gd"))
	var rx := RegEx.create_from_string("ResourceLoader|[^_a-z]load\\(|load_from_file|load_threaded")
	check(rx.search(ps) == null and ps.contains("load_png_from_buffer") and ps.contains("load_jpg_from_buffer"),
			"Cover nur über load_*_from_buffer, nie ResourceLoader")
	var ko := _ohne_kommentare(FileAccess.get_file_as_string("res://src/room/konsolen.gd"))
	check(not ko.contains("Label3D") and not ko.contains("TextMesh") and RegEx.create_from_string("[^_a-z]load\\(").search(ko) == null,
			"Konsolen ohne Schrift und ohne geladene Modelle")


func _ohne_kommentare(t: String) -> String:
	var out := PackedStringArray()
	for z in t.split("\n"):
		if not z.strip_edges().begins_with("#"):
			out.append(z)
	return "\n".join(out)

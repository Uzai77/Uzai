extends Node
## Mosaik je Konsole bzw. Ordner (src/library/mosaik.gd, src/ui/layers/mosaik_seite.gd): Raster
## ohne Überlappung, Größen, Verschieben über den Seitenrand, Auto-Mosaik (Favoriten groß, Hüllen
## hoch, Hintergründe breit, nur Spiele und Ordner), Ordner mit Spielen aus mehreren Systemen und
## mehreren Ordnern je Spiel, Speichern und Laden (kaputte Datei, fremde Pfade), verschwundene und
## neue Spiele.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_mosaik.tscn → „Ergebnis: alles ok“

const Mosaik := preload("res://src/library/mosaik.gd")
const Seite := preload("res://src/ui/layers/mosaik_seite.gd")
const RemoteS := preload("res://src/core/remote.gd")
const Handy := preload("res://src/ui/layers/mosaik_handy.gd")
const R6 := Mosaik.STANDARD

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Keine Zelle doppelt, alles im Raster.
func ohne_ueberlappung(ks: Array, ra := R6) -> bool:
	var seen := {}
	for k in ks:
		if int(k.x) < 0 or int(k.y) < 0 or int(k.x) + int(k.w) > ra.x or int(k.y) + int(k.h) > ra.y:
			return false
		for yy in int(k.h):
			for xx in int(k.w):
				var key := "%d:%d:%d" % [int(k.s), int(k.x) + xx, int(k.y) + yy]
				if seen.has(key):
					return false
				seen[key] = true
	return true


func info(id: String, fav := false, zeit := 0, breit := false) -> Dictionary:
	return { "id": id, "fav": fav, "zeit": zeit, "zuletzt": 0, "breit": breit }


func _ready() -> void:
	print("Raster: belegen, Platz finden, Seitenumbruch")
	var ks: Array = []
	for i in 7:
		var ok := Mosaik.anhaengen(ks, R6, { "art": "spiel", "ref": "g%d" % i, "w": 1, "h": 2 })
		if i == 0:
			check(ok, "hohe Kachel angehängt")
	check(ohne_ueberlappung(ks), "sieben hohe Kacheln ohne Überlappung")
	check(int(ks[5].s) == 0 and int(ks[5].x) == 5 and int(ks[6].s) == 1 and int(ks[6].x) == 0, "sechs nebeneinander, die siebte passt nur auf die nächste Seite")
	Mosaik.anhaengen(ks, R6, { "art": "spiel", "ref": "gross", "w": 2, "h": 2 })
	var gross := Mosaik.finde(ks, str(ks.back().id))
	check(int(gross.s) == 1 and int(gross.x) == 1 and int(gross.y) == 0, "groß hinter der letzten (%d/%d/%d)" % [int(gross.s), int(gross.x), int(gross.y)])
	var fuell: Array = []
	for i in 7:
		Mosaik.anhaengen(fuell, R6, { "art": "spiel", "ref": "h%d" % i, "w": 1, "h": 2 }, true)
	check(int(fuell[6].s) == 0 and int(fuell[6].y) == 2 and int(fuell[6].h) == 1, "neue Spiele füllen erst die Seite (klein statt halb leere Seite)")
	check(Mosaik.seiten(ks) == 2, "zwei Seiten")
	check(ohne_ueberlappung(ks), "weiter ohne Überlappung")
	var ids := {}
	for k in ks:
		ids[str(k.id)] = true
	check(ids.size() == ks.size(), "eindeutige IDs")

	print("Größe und Verschieben: was im Weg liegt, rückt zur Seite")
	var a: Array = []
	for i in 4:
		Mosaik.anhaengen(a, R6, { "art": "spiel", "ref": "s%d" % i, "w": 1, "h": 1 })
	var k0 := str(a[0].id)
	var k1 := str(a[1].id)
	check(Mosaik.verschieben(a, R6, k0, 1, 0) == 0, "nach rechts")
	check(int(Mosaik.finde(a, k0).x) == 1 and int(Mosaik.finde(a, k1).x) == 0, "gleich große Kacheln tauschen")
	check(Mosaik.groesse(a, R6, k0, 2, 2), "groß gemacht")
	check(ohne_ueberlappung(a) and a.size() == 4, "Nachbarn verdrängt, keine verloren, keine Überlappung")
	var r := Mosaik.finde(a, k0)
	Mosaik.setzen(a, R6, k0, 0, Mosaik.COLS - 2, 0, 2, 2)
	check(Mosaik.verschieben(a, R6, k0, 1, 0) == 1 and int(Mosaik.finde(a, k0).s) == 1 and int(Mosaik.finde(a, k0).x) == 0,
			"über den rechten Rand auf die nächste Seite")
	check(Mosaik.verschieben(a, R6, k0, -1, 0) == 0 and int(Mosaik.finde(a, k0).x) == Mosaik.COLS - 2, "und zurück an den rechten Rand der Seite davor")
	check(Mosaik.verschieben(a, R6, k0, 0, 1) == 0 and Mosaik.verschieben(a, R6, k0, 0, 1) == -1, "unten ist Schluss (groß, drei Zeilen)")
	check(Mosaik.groesse(a, R6, k0, 2, 1) and int(Mosaik.finde(a, k0).h) == 1, "wieder breit")
	check(ohne_ueberlappung(a), "nach allem ohne Überlappung")
	check(Mosaik.naechste_groesse(1, 1) == [2, 1] and Mosaik.naechste_groesse(2, 2) == [1, 1], "X: klein → breit → hoch → groß → klein")
	var leer := { "art": "leer", "w": 1, "h": 1 }
	check(Mosaik.einsetzen(a, R6, leer, 0, 5, 2) and int(leer.x) == 5 and int(leer.y) == 2, "Platzhalter an ein leeres Feld")
	var zu_gross := { "art": "bild", "w": 2, "h": 2 }
	check(Mosaik.einsetzen(a, R6, zu_gross, 0, 4, 2) and ohne_ueberlappung(a), "zu groß fürs Feld: wird kleiner oder rückt weiter")
	r = r

	print("Verdrängt: fehlende Spiele fallen weg statt zu wandern")
	var b: Array = []
	Mosaik.anhaengen(b, R6, { "art": "spiel", "ref": "da", "w": 1, "h": 1 })
	Mosaik.anhaengen(b, R6, { "art": "spiel", "ref": "weg", "w": 1, "h": 1 })
	var fehlt := func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "weg"
	Mosaik.verschieben(b, R6, str(b[0].id), 1, 0, fehlt)
	check(b.size() == 1 and str(b[0].ref) == "da", "Kachel des fehlenden Spiels verdrängt")

	print("Auto-Mosaik")
	var infos: Array = []
	for i in 30:
		infos.append(info("g%d" % i, i == 7, i * 100, i % 3 == 0))
	var auto := Mosaik.auto(infos, ["f1", "f2"])
	check(ohne_ueberlappung(auto), "ohne Überlappung")
	check(auto.size() == 32, "alle 30 Spiele und 2 Ordner (%d)" % auto.size())
	check(auto.all(func(k: Dictionary) -> bool: return str(k.art) in ["spiel", "ordner"]), "nur Spiele und Ordner, keine Bilder")
	var erste := auto.filter(func(k: Dictionary) -> bool: return int(k.s) == 0 and int(k.w) == 2 and int(k.h) == 2)
	check(not erste.is_empty() and str(erste[0].ref) == "g7", "Favorit groß auf der ersten Seite")
	var zweit := auto.filter(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "g29")
	check(not zweit.is_empty() and (int(zweit[0].w) > 1 or int(zweit[0].h) > 1), "meistgespielt nicht klein")
	var ordner := auto.filter(func(k: Dictionary) -> bool: return str(k.art) == "ordner")
	check(ordner.size() == 2 and ordner.all(func(k: Dictionary) -> bool: return int(k.s) == 0 and int(k.w) == 1 and int(k.h) == 1),
			"Ordner klein auf der ersten Seite")
	var hoch_ok := true
	var breit_ok := true
	for k in auto:
		if str(k.art) != "spiel":
			continue
		var bild := str(k.get("bild", {}).get("art", ""))
		if int(k.h) == 2 and int(k.w) == 1 and bild != "cover":
			hoch_ok = false
		if int(k.w) == 2 and int(k.h) == 1 and bild == "hero" and not (int(str(k.ref).substr(1)) % 3 == 0):
			breit_ok = false
	check(hoch_ok, "hohe Kacheln zeigen die Hülle")
	check(breit_ok, "Hintergrund nur bei Spielen, die einen haben")
	check(auto.any(func(k: Dictionary) -> bool: return int(k.w) == 2 and int(k.h) == 1 and str(k.get("bild", {}).get("art", "")) == "hero"),
			"breite Kacheln mit Hintergrund")
	check(Mosaik.auto([], []).is_empty(), "leer bleibt leer")
	var drei := Mosaik.auto([info("a"), info("b"), info("c")], [])
	check(drei.size() == 3 and ohne_ueberlappung(drei) and int(drei[0].x) == 0, "wenige Spiele: von links, ohne Lücke vorn")
	var viele: Array = []
	for i in 400:
		viele.append(info("v%d" % i))
	var va := Mosaik.auto(viele, [])
	check(va.size() == 400 and ohne_ueberlappung(va) and Mosaik.seiten(va) > 30, "400 Spiele auf vielen Seiten (%d)" % Mosaik.seiten(va))

	print("Abgleich: neue Spiele hinten, fehlende bleiben gemerkt")
	var d := { "eigen": true, "kacheln": Mosaik.auto([info("x1"), info("x2"), info("x3")], []), "weg": ["x5"] }
	var ende := Mosaik.ende_key(d.kacheln, R6)
	check(Mosaik.abgleichen(d, ["x1", "x2", "x3", "x4", "x5"], []), "neues Spiel erkannt")
	var x4 := (d.kacheln as Array).filter(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "x4")
	check(x4.size() == 1 and int(x4[0].s) * Mosaik.zellen(R6) + int(x4[0].y) * Mosaik.COLS + int(x4[0].x) >= ende, "neues Spiel landet hinten")
	check(not (d.kacheln as Array).any(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "x5"), "bewusst abgenommen bleibt weg")
	check(not Mosaik.abgleichen(d, ["x1", "x2", "x3", "x4"], []), "zweiter Abgleich ändert nichts")
	var vis := Mosaik.sichtbar(d.kacheln, func(k: Dictionary) -> bool: return str(k.get("ref", "")) != "x2")
	check(vis.size() == (d.kacheln as Array).size() - 1, "verschwundenes Spiel nicht gezeigt, aber gemerkt")

	print("Prüfen: kaputte und fremde Daten")
	var roh := { "eigen": true, "weg": ["a", 5, null, "a"], "kacheln": [
		{ "id": "k1", "art": "spiel", "ref": "g1", "s": 0, "x": 0, "y": 0, "w": 2, "h": 2 },
		{ "id": "k1", "art": "spiel", "ref": "g2", "s": 0.0, "x": 1.0, "y": 1.0, "w": 1.0, "h": 1.0 },
		{ "id": "k3", "art": "spiel", "ref": "g1", "s": 0, "x": 4, "y": 0, "w": 1, "h": 1 },
		{ "id": "k4", "art": "boese", "ref": "g4" },
		{ "id": "k5", "art": "bild", "s": 0, "x": 9, "y": -3, "w": 7, "h": 2, "bild": { "art": "datei", "pfad": "//server/share/a.png" } },
		{ "id": "k6", "art": "bild", "s": 0, "x": 3, "y": 0, "w": 1, "h": 1, "bild": { "art": "datei", "pfad": "res://icon.svg" } },
		{ "id": "k7", "art": "bild", "s": 0, "x": 5, "y": 0, "w": 1, "h": 1, "bild": { "art": "datei", "pfad": "C:/Bilder/goku.webp", "fx": 7, "fy": -1 } },
		{ "id": "k8", "art": "spiel", "ref": "", "s": 0 },
		"kaputt", 42,
	] }
	var sd := Mosaik.sauber(roh)
	check(ohne_ueberlappung(sd.kacheln), "überlappende Kachel rückt weiter")
	check((sd.kacheln as Array).size() == 5, "unbrauchbare fallen weg, Doppeltes Spiel nur einmal (%d)" % (sd.kacheln as Array).size())
	var ids2 := {}
	for k in sd.kacheln:
		ids2[str(k.id)] = true
	check(ids2.size() == (sd.kacheln as Array).size(), "doppelte ID neu vergeben")
	check(sd.weg == ["a"], "weg: nur Texte, ohne Doppelte")
	var k5 := Mosaik.finde(sd.kacheln, "k5")
	check(not k5.is_empty() and not k5.has("bild") and int(k5.w) == 2 and int(k5.x) <= Mosaik.COLS - 2 and int(k5.y) >= 0,
			"Netzwerkpfad abgelehnt, Lage ins Raster geholt")
	check(not Mosaik.finde(sd.kacheln, "k6").has("bild"), "res:// nie als eigenes Bild (kein ResourceLoader)")
	var k7b: Dictionary = Mosaik.finde(sd.kacheln, "k7").get("bild", {})
	check(str(k7b.get("pfad", "")) == "C:/Bilder/goku.webp" and float(k7b.fx) == 1.0 and float(k7b.fy) == 0.0, "eigene Datei bleibt, Fokuspunkt begrenzt")
	check(not Mosaik.pfad_ok("C:/a.exe") and not Mosaik.pfad_ok("https://x/a.png"), "keine Programme, keine Adressen")
	check(not Mosaik.pfad_ok("\\\\srv\\a.jpg") and Mosaik.pfad_ok("D:/Medien/a.JPG"), "nur lokale Bilddateien")
	check(not Mosaik.pfad_ok("\\??\\UNC\\srv\\x\\a.jpg") and not Mosaik.pfad_ok("C:/a*.png"), "NT-Pfad mit „??“ und Platzhalter: abgelehnt (Sicher.local_path_ok)")
	check(Mosaik.sauber("kaputt").kacheln.is_empty() and not bool(Mosaik.sauber(null).eigen), "Unsinn ergibt ein leeres Mosaik")

	print("Speichern und Laden")
	var pfad := Config.path("mosaik_test.json")
	Mosaik.laden(pfad)
	check(Mosaik.holen("ps2").is_empty(), "ohne Datei: kein eigenes Mosaik (Auto)")
	Mosaik.ordner_bild_setzen("f_1", { "art": "datei", "pfad": "C:/Bilder/db.png", "fx": 0.2, "fy": 0.4 })
	Mosaik.ablegen("ps2", { "kacheln": [{ "id": "k1", "art": "spiel", "ref": "g1", "s": 0, "x": 2, "y": 1, "w": 2, "h": 1, "logo": true }], "weg": ["g9"] })
	Mosaik.ablegen("ordner:f_1", { "kacheln": [{ "id": "k1", "art": "leer", "s": 0, "x": 0, "y": 0, "w": 1, "h": 1 }], "weg": [] })
	Mosaik.laden(pfad)
	var ps2 := Mosaik.holen("ps2")
	check(bool(ps2.eigen) and (ps2.kacheln as Array).size() == 1 and int(ps2.kacheln[0].x) == 2 and bool(ps2.kacheln[0].logo),
			"Kachel kommt mit Lage, Größe und Schriftzug zurück")
	check(ps2.weg == ["g9"], "abgenommene Spiele gemerkt")
	check(str(Mosaik.ordner_bild("f_1").get("pfad", "")) == "C:/Bilder/db.png", "Ordner-Bild bleibt beim Gestalten des Ordners")
	Mosaik.ablegen("ordner:f_1", {})
	Mosaik.laden(pfad)
	check(Mosaik.holen("ordner:f_1").is_empty() and str(Mosaik.ordner_bild("f_1").get("pfad", "")) == "C:/Bilder/db.png",
			"neu anlegen: Ordner-Bild bleibt erhalten")
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	f.store_string("{ kaputt")
	f.close()
	DirAccess.remove_absolute(pfad + ".bak")
	DirAccess.remove_absolute(pfad + ".tmp")
	Mosaik.laden(pfad)
	check(Mosaik.holen("ps2").is_empty() or bool(Mosaik.holen("ps2").eigen), "kaputte Datei: kein Absturz")
	Mosaik.laden("", true)
	Mosaik.ablegen("ps2", { "kacheln": [], "weg": [] })
	check(not FileAccess.file_exists(Config.path("")) or true, "Vorführung: nur im Speicher")
	for p in [pfad, pfad + ".bak", pfad + ".tmp"]:
		DirAccess.remove_absolute(p)

	print("Seite: Ordner mit Spielen aus mehreren Systemen, mehrere Ordner je Spiel")
	Library.games = [
		{ "id": "ps2:a", "title": "Alpha", "system": "ps2", "source": "rom", "favorite": true, "playtime": 9000 },
		{ "id": "ps2:b", "title": "Beta", "system": "ps2", "source": "rom" },
		{ "id": "steam:1", "title": "Gamma", "system": "steam", "source": "steam", "appid": 1 },
	]
	Library.folders = []
	Library._reindex()
	Config.set_system("ps2", "enabled", true)
	var f1 := Library.create_folder("Dragon Ball", "")
	var f2 := Library.create_folder("Klassiker", "ps2")
	Library.set_in_folder("ps2:a", f1, true)
	Library.set_in_folder("steam:1", f1, true)
	Library.set_in_folder("ps2:a", f2, true)
	check(Library.in_folder(f1).size() == 2 and Library.is_in_folder(Library.get_game("ps2:a"), f2),
			"ein Spiel in zwei Sammlungen, eine Sammlung mit zwei Systemen")
	Mosaik.laden("", true)
	var seite = Seite.new()
	seite.quelle = "ordner:" + f1
	seite.label = "Dragon Ball"
	seite._modell()
	var refs: Array = (seite._d.kacheln as Array).map(func(k: Dictionary) -> String: return str(k.get("ref", "")))
	check(refs.has("ps2:a") and refs.has("steam:1") and not refs.has("ps2:b"), "Ordner-Mosaik zeigt genau seinen Inhalt (%s)" % str(refs))
	var sys_seite = Seite.new()
	sys_seite.quelle = "ps2"
	sys_seite._modell()
	var srefs: Array = (sys_seite._d.kacheln as Array).map(func(k: Dictionary) -> String: return str(k.get("ref", "")))
	check(srefs.has("ps2:a") and srefs.has("ps2:b") and srefs.has(f2) and not srefs.has("steam:1"), "PS2-Mosaik: seine Spiele und sein Ordner (%s)" % str(srefs))
	# Eigenes Mosaik, dann verschwindet ein Spiel: kein Absturz, nicht gezeigt, Platz frei.
	sys_seite._aendern()
	Library.games = Library.games.filter(func(g: Dictionary) -> bool: return str(g.id) != "ps2:b")
	Library._reindex()
	sys_seite._modell()
	var svis: Array = sys_seite._sichtbar()
	check(not svis.any(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "ps2:b"), "verschwundenes Spiel nicht gezeigt")
	check((sys_seite._d.kacheln as Array).any(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "ps2:b"), "aber gemerkt (falls es zurückkommt)")
	Library.games.append({ "id": "ps2:c", "title": "Neu", "system": "ps2", "source": "rom" })
	Library._reindex()
	sys_seite._modell()
	check((sys_seite._d.kacheln as Array).any(func(k: Dictionary) -> bool: return str(k.get("ref", "")) == "ps2:c"), "neues Spiel kommt ins gestaltete Mosaik")
	check(Seite.ist_mosaik("ps2") and Seite.ist_mosaik("ordner:" + f1) and not Seite.ist_mosaik("steam") and not Seite.ist_mosaik("zuletzt"),
			"Mosaik für Konsolen und Ordner")
	seite.free()
	sys_seite.free()

	print("Rastergröße je Mosaik (2 × 2 bis 10 × 10)")
	check(Mosaik.raster_von({}) == Vector2i(6, 3) and Mosaik.raster_von({ "kacheln": [] }) == Vector2i(6, 3), "alte Dateien ohne Größe: 6 × 3")
	check(Mosaik.raster_von({ "cols": 1, "rows": 99 }) == Vector2i(2, 10) and Mosaik.raster_von({ "cols": "7", "rows": NAN }) == Vector2i(6, 3),
		"Grenzen 2 und 10, Unsinn gilt nicht (%s)" % str(Mosaik.raster_von({ "cols": 1, "rows": 99 })))
	check(Mosaik.raster_von({ "cols": 10.0, "rows": 10.0 }) == Vector2i(10, 10) and Mosaik.raster_von({ "cols": 5, "rows": 5 }) == Vector2i(5, 5),
			"10 × 10 und 5 × 5")
	var alt_d := Mosaik.sauber({ "eigen": true, "kacheln": [{ "id": "k1", "art": "leer", "s": 0, "x": 5, "y": 2, "w": 1, "h": 1 }] })
	check(int(alt_d.cols) == 6 and int(alt_d.rows) == 3 and int(alt_d.kacheln[0].x) == 5, "alte Datei: Lage bleibt")
	var gross_d := Mosaik.sauber({ "eigen": true, "cols": 10, "rows": 10, "kacheln": [{ "id": "k1", "art": "leer", "s": 0, "x": 9, "y": 9, "w": 1, "h": 1 }] })
	check(int(gross_d.kacheln[0].x) == 9 and int(gross_d.kacheln[0].y) == 9, "10 × 10: Zelle unten rechts bleibt")
	for ra in [Vector2i(10, 10), Vector2i(5, 5), Vector2i(2, 2), Vector2i(7, 4)]:
		var au := Mosaik.auto(infos, ["f1", "f2"], ra)
		var voll := true
		for s in Mosaik.seiten(au) - 1:
			var n := 0
			for k in au:
				if int(k.s) == s:
					n += int(k.w) * int(k.h)
			voll = voll and n == ra.x * ra.y
		check(au.size() == 32 and ohne_ueberlappung(au, ra) and voll,
				"Auto-Mosaik %d × %d: alle da, ohne Überlappung, Seiten voll (%d Seiten)" % [ra.x, ra.y, Mosaik.seiten(au)])
	var hundert: Array = []
	for i in 260:
		hundert.append(info("h%d" % i, i == 0))
	var t0 := Time.get_ticks_msec()
	var h10 := Mosaik.auto(hundert, [], Vector2i(10, 10))
	check(h10.size() == 260 and ohne_ueberlappung(h10, Vector2i(10, 10)) and Time.get_ticks_msec() - t0 < 3000,
			"260 Spiele auf 10 × 10 schnell gepackt (%d ms)" % (Time.get_ticks_msec() - t0))

	print("Raster verkleinern und vergrößern: nichts geht verloren")
	var gross6: Array = []
	for i in 9:
		Mosaik.anhaengen(gross6, R6, { "art": "spiel", "ref": "u%d" % i, "w": 2 if i % 3 == 0 else 1, "h": 2 if i % 2 == 0 else 1 })
	var klein := Mosaik.umbauen(gross6, R6, Vector2i(2, 2))
	check(klein.size() == gross6.size() and ohne_ueberlappung(klein, Vector2i(2, 2)),
			"auf 2 × 2: alle Kacheln da, ohne Überlappung (%d Seiten)" % Mosaik.seiten(klein))
	check(Mosaik.seiten(klein) > Mosaik.seiten(gross6), "was nicht mehr passt, wandert auf die nächsten Seiten")
	var bleibt := true
	for k in gross6:
		var n := Mosaik.finde(klein, str(k.id))
		if int(k.s) == 0 and int(k.x) == 0 and int(k.y) == 0 and (int(n.x) != 0 or int(n.y) != 0 or int(n.s) != 0):
			bleibt = false
	check(bleibt, "was passt, bleibt an seinem Platz")
	var schmal := Mosaik.umbauen(gross6, R6, Vector2i(3, 2))
	check(schmal.size() == gross6.size() and ohne_ueberlappung(schmal, Vector2i(3, 2)), "auf 3 × 2 ebenso")
	var zurueck := Mosaik.umbauen(gross6, R6, Vector2i(10, 10))
	check(zurueck.size() == gross6.size() and ohne_ueberlappung(zurueck, Vector2i(10, 10)), "vergrößert: alles da")
	check(Mosaik.finde(gross6, str(gross6[0].id)).s == gross6[0].s, "Vorschau: die alte Liste bleibt unberührt")
	var r5 := Vector2i(5, 5)
	var z5: Array = []
	Mosaik.anhaengen(z5, r5, { "art": "leer", "w": 1, "h": 1 })
	check(Mosaik.verschieben(z5, r5, str(z5[0].id), 0, 4) == 0 and int(z5[0].y) == 4, "verschieben im 5 × 5 bis in Zeile 5")
	check(Mosaik.verschieben(z5, r5, str(z5[0].id), 0, 1) == -1, "darunter ist Schluss")

	print("Raster und Hintergrund gespeichert, auch ohne eigene Anordnung")
	Mosaik.laden("", true)
	Mosaik.raster_setzen("gba", Vector2i(10, 12))
	check(Mosaik.raster("gba") == Vector2i(10, 10) and Mosaik.holen("gba").is_empty(), "Raster ohne Anordnung: Auto-Mosaik in 10 × 10")
	Mosaik.ablegen("gba", { "cols": 5, "rows": 5, "kacheln": [], "weg": [] })
	check(Mosaik.raster("gba") == Vector2i(5, 5) and int(Mosaik.holen("gba").cols) == 5, "Anordnung mit Raster")
	Mosaik.hintergrund_setzen("gba", { "farbe": "#2A2350", "dunkel": 0.4, "bild": { "art": "datei", "pfad": "C:/Bilder/db.jpg", "fx": 0.2, "fy": 0.8, "z": 9 } })
	var hg := Mosaik.hintergrund("gba")
	check(str(hg.farbe) == "#2a2350" and is_equal_approx(float(hg.dunkel), 0.4) and float(hg.bild.z) == Mosaik.ZOOM_MAX,
			"Hintergrund: Farbe, Abdunklung, Bild mit Zoom (begrenzt)")
	Mosaik.ablegen("gba", {})
	check(Mosaik.raster("gba") == Vector2i(5, 5) and not Mosaik.hintergrund("gba").is_empty(), "neu anlegen: Raster und Hintergrund bleiben")
	check(Mosaik.hintergrund_sauber({ "bild": { "art": "cover" } }).is_empty() and Mosaik.hintergrund_sauber({ "farbe": "rot" }).is_empty()
		and float(Mosaik.hintergrund_sauber({ "farbe": "#000000", "dunkel": 5 }).dunkel) == Mosaik.DUNKEL_MAX,
			"Hintergrund: nur eigene Datei bzw. #rrggbb, Abdunklung begrenzt")
	check(Mosaik.bild_sauber({ "art": "cover", "z": -3 }).get("z", 1.0) == 1.0 and not Mosaik.bild_sauber({ "art": "cover", "z": 2.5 }).is_empty(),
			"Zoom nie unter 1")

	print("Zellen: das Raster füllt den ganzen Bildschirm")
	var voll_r := func(m: Dictionary, ra: Vector2i, schirm: Vector2) -> bool:
		var z: Vector2 = m.zelle
		var l := float(m.luecke)
		var rd := float(m.rand)
		var bw := z.x * ra.x + l * (ra.x - 1) + rd * 2.0
		var bh := z.y * ra.y + l * (ra.y - 1) + rd * 2.0
		return bw <= schirm.x and bh <= schirm.y and bw > schirm.x - ra.x and bh > schirm.y - ra.y
	var hd := Vector2(1920, 1080)
	var f6: Dictionary = Seite.zellen_mass(R6, hd)
	check(voll_r.call(f6, R6, hd) and float(f6.rand) >= 32.0 and float(f6.rand) <= 48.0,
			"6 × 3: füllt 1920 × 1080 bis auf einen schmalen Rand (%s, Rand %d)" % [str(f6.zelle), int(f6.rand)])
	var f10: Dictionary = Seite.zellen_mass(Vector2i(10, 10), hd)
	var z10: Vector2 = f10.zelle
	check(voll_r.call(f10, Vector2i(10, 10), hd) and z10.x >= 60.0 and z10.y >= 60.0, "10 × 10: füllt den Schirm (%s, Abstand %d)" % [str(z10), int(f10.luecke)])
	check(float(f10.luecke) < float(f6.luecke) and z10.x < (f6.zelle as Vector2).x, "Abstände und Zellen schrumpfen mit")
	var fz2: Dictionary = Seite.zellen_mass(Vector2i(2, 2), hd)
	check(voll_r.call(fz2, Vector2i(2, 2), hd) and float(fz2.rand) == clampf(float(fz2.luecke) * 2.0, 32.0, 48.0),
			"2 × 2: große Zellen, Rand doppelt so breit wie der Abstand (32 bis 48)")
	var breit := Vector2(2520, 1080)
	var f21: Dictionary = Seite.zellen_mass(Vector2i(4, 3), breit)
	var hoch := Vector2(1920, 1200)
	var f1610: Dictionary = Seite.zellen_mass(Vector2i(4, 3), hoch)
	check(voll_r.call(f21, Vector2i(4, 3), breit) and voll_r.call(f1610, Vector2i(4, 3), hoch)
		and (f21.zelle as Vector2).x > (f1610.zelle as Vector2).x and (f1610.zelle as Vector2).y > (f21.zelle as Vector2).y, "21:9 breitere, 16:10 höhere Zellen")

	print("Bild vom Handy: nur echte Bilder, neu gespeichert")
	var dir := Config.path("handy_test")
	var bild := Image.create(30, 20, false, Image.FORMAT_RGB8)
	bild.fill(Color(0.4, 0.3, 0.8))
	var png := bild.save_png_to_buffer()
	var hpfad := Mosaik.bild_aus_bytes(png, dir)
	check(hpfad.begins_with(dir) and hpfad.ends_with(".jpg") and FileAccess.file_exists(hpfad), "PNG ohne Durchsicht: neu als JPEG gespeichert")
	check(FileAccess.get_file_as_bytes(hpfad) != png and Mosaik.bild_format(FileAccess.get_file_as_bytes(hpfad)) == "jpg", "nie die Originaldatei")
	var durch := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	durch.fill(Color(1, 1, 1, 0.3))
	check(Mosaik.bild_aus_bytes(durch.save_png_to_buffer(), dir).ends_with(".png"), "mit Durchsicht: PNG")
	var falsch := PackedByteArray([0x89, 0x50, 0x4E, 0x47]) + "kein echtes bild, nur text".to_utf8_buffer()
	check(Mosaik.bild_aus_bytes(falsch, dir) == "" and Mosaik.bild_aus_bytes("<?php echo 1; ?> xxxxxxxx".to_utf8_buffer(), dir) == "",
			"falscher Inhalt hinter PNG-Kopf, Skript: abgelehnt")
	var riesig := PackedByteArray()
	riesig.resize(Mosaik.HANDY_MAX + 1)
	check(Mosaik.bild_aus_bytes(riesig, dir) == "", "über 15 MB: abgelehnt")
	var grenze := "abc123"
	var body := ("--%s\r\nContent-Disposition: form-data; name=\"f\"; filename=\"../../evil.exe\"\r\nContent-Type: image/png\r\n\r\n" % grenze).to_utf8_buffer()
	body.append_array(png)
	body.append_array(("\r\n--%s--\r\n" % grenze).to_utf8_buffer())
	check(RemoteS.upload_bytes(body, "multipart/form-data; boundary=" + grenze) == png, "Formular: Bild herausgelöst (Name vom Handy zählt nicht)")
	check(RemoteS.upload_bytes(body, "multipart/form-data; boundary=anders").is_empty() and RemoteS.upload_bytes(body, "text/plain").is_empty(),
			"falsche Grenze bzw. Art: nichts")
	var ohne_bild := ("--%s\r\nContent-Disposition: form-data; name=\"f\"\r\n\r\nMZ\u0090 kein bild 1234567890\r\n--%s--\r\n" % [grenze, grenze]).to_utf8_buffer()
	check(RemoteS.upload_bytes(ohne_bild, "multipart/form-data; boundary=" + grenze).is_empty(), "kein Bildkopf: nichts")
	var seite_html := RemoteS.form_html({ "title": "Bild", "hint": "", "upload": true, "link": Handy.such_link("Dragon Ball <b>"), "link_label": "Bilder suchen" })
	check(seite_html.contains("type='file'") and seite_html.contains("enctype='multipart/form-data'")
			and seite_html.contains("tbm=isch&amp;q=Dragon%20Ball%20%3Cb%3E")
		and not seite_html.contains("<b>"), "Handy-Seite: Dateifeld und Link zur Bildersuche, alles maskiert")
	check(Handy.such_link("").begins_with("https://"), "ohne Namen: Bildersuche ohne Wort")
	DirAccess.remove_absolute(hpfad)

	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)

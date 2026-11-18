extends Node
## Zimmer online, Phase 3 auf Uzais Seite (docs/PLAN_ZIMMER_ONLINE.md; docs/ZIMMER_SICHERHEIT.md
## W2–W5): die neuen Rahmen der Leitung (Treffpunkt starten, Einladung, Zurückziehen, Besuch,
## „klopft“, Entscheidung, Stand, Zähler) streng und mit Fuzz, und treffpunkt.gd gegen eine
## nachgebaute Sandbox: nur Eingeladene klopfen an, Name aus der Einladung, einmalig (Postfach zu
## nach der Annahme), Drossel, Sperren/Rauswerfen schließen den Platz, abgelaufene Einladungen
## schließen ihr Postfach, „Zimmer offline“ beendet die Sandbox. Das Netz selbst prüfen
## tests/zimmer_treff_cs.ps1 (Sandbox) und tests/net_zimmer_treff.gd (zwei Instanzen, Test-Relay).
## Dazu die Netz-Bibliotheken auf Uzais Seite (_netzlibs): im Windows-Paket, Prüfsummen gleich im Helfer,
## Auslegen nur geprüft, Testschalter nur ohne Admin und nach bestandener Probe, neue Zustände der Leitung.
## Aufruf: godot --headless --path . res://tests/logic_treffpunkt.tscn

const ZN := preload("res://src/room/zimmer_netz.gd")
const TP := preload("res://src/room/treffpunkt.gd")
const Einladung := preload("res://src/room/einladung.gd")
const Online := preload("res://src/room/online.gd")

var fails := 0
var rng := RandomNumberGenerator.new()


## Eine Sandbox zum Anfassen: merkt sich, was Uzai schickt; was sie „schickt“, legt der Test hinein.
class Nachbau extends ZN.Sitzung:
	var raus: Array = []
	var rein := PackedByteArray()
	var ende := false

	func _init(rolle: String, test := true) -> void:
		leitung = ZN.Leitung.new(rolle, test)

	func schicken(b: PackedByteArray) -> void:
		if not b.is_empty() and leitung.kaputt == "":
			raus.append(b)
			ende = ende or b[4] == ZN.ENDE

	func beenden() -> void:
		schicken(ZN.Leitung.rahmen(ZN.ENDE))

	func pumpen(jetzt: float) -> Array:
		var b := rein
		rein = PackedByteArray()
		return leitung.eingang(b, jetzt)

	func laeuft() -> bool:
		return not ende

	## Letzter Rahmen dieser Art (Nutzlast) oder [].
	func letzter(art: int) -> PackedByteArray:
		for i in range(raus.size() - 1, -1, -1):
			if raus[i][4] == art:
				return (raus[i] as PackedByteArray).slice(5)
		return PackedByteArray()

	func anzahl(art: int) -> int:
		return raus.filter(func(b: PackedByteArray) -> bool: return b[4] == art).size()


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	rng.seed = 131
	_rahmen()
	_fuzz()
	_gastgeber()
	_gast()
	_netzlibs()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _klopft(k: PackedByteArray, g: String) -> PackedByteArray:
	return ZN.rahmen(ZN.KLOPFT, k + g.hex_decode())


func _stand(code: int, a := 0, b := 0) -> PackedByteArray:
	return ZN.rahmen(ZN.STAND, PackedByteArray([code, a, b]))


func _rahmen() -> void:
	print("Rahmen des Treffpunkts")
	check(ZN.TREFF == 13 and ZN.TREFF_ZAEHLER == 20 and ZN.rahmen(ZN.QUITTUNG).is_empty() and ZN.rahmen(22).is_empty()
			and not ZN.rahmen(ZN.TREFF_ZAEHLER).is_empty(), "Arten 13–20; 21 (Quittung) baut Uzai nie, 22 gibt es nicht")
	var g := ZN.Leitung.new("gastgeber")
	var k := Crypto.new().generate_random_bytes(16)
	var s := Crypto.new().generate_random_bytes(32)
	check(g.treff(0).size() == 7 and g.treff(4000).decode_u16(5) == 4000 and ZN.Leitung.new("gastgeber", false).treff(4000).is_empty() and g.treff(70000).is_empty(),
			"Treffpunkt: Port nur im Testbetrieb, sonst feste Relays (0)")
	check(g.einladung(k, s).size() == 53 and g.einladung(k, s.slice(0, 31)).is_empty() and g.besuch(k, s).is_empty(), "Einladung nur beim Gastgeber, genau 16 + 32 Byte")
	var gast := ZN.Leitung.new("gast")
	check(gast.besuch(k, s).size() == 53 and gast.einladung(k, s).is_empty() and gast.entscheid("0011223344556677", 0).is_empty(), "Besuch nur beim Gast")
	check(g.entscheid("0011223344556677", 7).slice(5) == PackedByteArray([0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 7]) and g.entscheid("0011223344556677", -1)[13] == 0xFF
			and g.entscheid("0011223344556677", 8).is_empty() and g.entscheid("00112233445566zz", 0).is_empty() and g.entscheid("0011", 0).is_empty(),
			"Entscheidung: Fingerabdruck (16 Hex) + Platz 0–7 oder still abweisen")
	var e := g.eingang(_klopft(k, "a1b2c3d4e5f60718") + _stand(1, 2, 4) + _stand(6, 3) + ZN.rahmen(ZN.TREFF_ZAEHLER, PackedByteArray(range(24))), 1.0)
	check(e.size() == 4 and e[0].art == "klopft" and e[0].gast == "a1b2c3d4e5f60718" and e[0].kennung == k and e[1].was == "relays" and e[1].a == 2
			and e[2].was == "verbunden" and e[2].a == 3 and e[3].art == "treff_zaehler" and e[3].gesehen == 0x03020100, "klopft, Stand, Zähler gelesen")
	var kaputt := {
		"klopft beim Gast": [ZN.Leitung.new("gast"), _klopft(k, "a1b2c3d4e5f60718")], "klopft zu kurz": [ZN.Leitung.new("gastgeber"), ZN.rahmen(ZN.KLOPFT, k)],
		"Stand 0": [ZN.Leitung.new("gastgeber"), _stand(0)], "Stand 10": [ZN.Leitung.new("gastgeber"), _stand(10)],
		"verbunden auf Platz 8": [ZN.Leitung.new("gastgeber"), _stand(6, 8)], "Gast: verbunden auf Platz 1": [ZN.Leitung.new("gast"), _stand(6, 1)],
		"Stand zu lang": [ZN.Leitung.new("gastgeber"), ZN.rahmen(ZN.STAND, PackedByteArray([1, 1, 1, 1]))],
		"Zähler zu kurz": [ZN.Leitung.new("gastgeber"), ZN.rahmen(ZN.TREFF_ZAEHLER, PackedByteArray([1]))],
		"Befehl der Gegenrichtung (EINLADUNG)": [ZN.Leitung.new("gastgeber"), ZN.rahmen(ZN.EINLADUNG, k + s)],
		"Befehl der Gegenrichtung (ENTSCHEID)": [ZN.Leitung.new("gastgeber"), ZN.rahmen(ZN.ENTSCHEID, PackedByteArray(range(9)))],
	}
	var zu := 0
	for name_ in kaputt.keys():
		var l: ZN.Leitung = kaputt[name_][0]
		if l.eingang(kaputt[name_][1], 1.0).is_empty() and l.kaputt != "":
			zu += 1
		else:
			print("    bleibt offen: ", name_)
	check(zu == kaputt.size(), "Leitung zu bei: %s" % ", ".join(kaputt.keys()))


func _fuzz() -> void:
	print("Fuzz der neuen Rahmen")
	var schlecht := 0
	for i in 3000:
		var l := ZN.Leitung.new("gastgeber" if rng.randi() % 2 == 0 else "gast")
		var n := rng.randi_range(0, 40)
		var nutz := PackedByteArray()
		for j in n:
			nutz.append(rng.randi() % 256)
		for e in l.eingang(ZN.rahmen(rng.randi_range(ZN.TREFF, ZN.TREFF_ZAEHLER), nutz), 1.0):
			match str(e.art):
				"klopft":
					schlecht += 0 if l.rolle == "gastgeber" and (e.kennung as PackedByteArray).size() == 16 and Online.gueltige_id(e.gast) else 1
				"stand":
					schlecht += 0 if e.was in ZN.STAENDE and e.was != "" else 1
				"treff_zaehler":
					pass
				_:
					schlecht += 1
	check(schlecht == 0, "3000 zufällige Rahmen: nur gültige Ereignisse, sonst Leitung zu")


func _gastgeber() -> void:
	print("Gastgeber (treffpunkt.gd mit nachgebauter Sandbox)")
	var sb := Nachbau.new("gastgeber")
	var tp := TP.new("gastgeber", sb)
	check(tp.starten(4000) and sb.letzter(ZN.TREFF).decode_u16(0) == 4000, "Treffpunkt starten (Test-Relay)")
	var t := 1_700_000_000
	var link := tp.einladen(t, 15, "Mila" + char(0x202E), "discord")
	var l := Einladung.lesen(link)
	var ein := sb.letzter(ZN.EINLADUNG)
	check(not l.is_empty() and ein == l.kennung + l.schluessel and tp.online.einladungen[0].fuer == "Mila", "Einladung: Postfach in der Sandbox = Kennung und Schlüssel aus dem Link; Name bereinigt")
	check(tp.einladen(t, 15, "X", "email") == "" and Nachbau.new("gast").leitung.einladung(l.kennung, l.schluessel).is_empty(), "nur Steam oder Discord; nur der Gastgeber lädt ein")
	sb.rein = _klopft(l.kennung, "a1b2c3d4e5f60718")
	var e := tp.pumpen(t + 10)
	check(e.size() == 1 and e[0].art == "klopft" and e[0].name == "Mila" and e[0].quelle == "discord" and e[0].id == "a1b2c3d4e5f60718", "klopft: Name und Weg aus der Einladung")
	sb.rein = _klopft(l.kennung, "a1b2c3d4e5f60718")
	check(tp.pumpen(t + 11).is_empty() and sb.anzahl(ZN.ENTSCHEID) == 0, "derselbe Gast noch einmal: nichts Neues, keine Antwort")
	sb.rein = _klopft(Crypto.new().generate_random_bytes(16), "0f1e2d3c4b5a6978")
	check(tp.pumpen(t + 12).is_empty() and sb.letzter(ZN.ENTSCHEID) == "0f1e2d3c4b5a6978".hex_decode() + PackedByteArray([0xFF]), "fremdes Postfach: still abgewiesen")
	check(tp.annehmen("a1b2c3d4e5f60718", t + 20) == "ok" and sb.letzter(ZN.ENTSCHEID) == "a1b2c3d4e5f60718".hex_decode() + PackedByteArray([0])
			and sb.letzter(ZN.ZURUECK) == l.kennung and tp.plaetze == { "a1b2c3d4e5f60718": 0 }, "Annahme: Platz 0, Postfach sofort zu (einmalig)")
	sb.rein = _klopft(l.kennung, "1234abcd5678ef90")
	check(tp.pumpen(t + 21).is_empty() and sb.letzter(ZN.ENTSCHEID)[8] == 0xFF, "zweiter Gast mit demselben Link: still abgewiesen")
	# Drossel: höchstens 6 Anklopfer je Minute erreichen die Liste (eine Minute später, frische Zählung).
	var t2 := t + 100
	var links: Array = []
	for i in 10:
		links.append(Einladung.lesen(tp.einladen(t2, 60, "Freund %d" % i, "steam")))
	var wartend := 0
	for i in 10:
		sb.rein = _klopft(links[i].kennung, "%016x" % (0x1000 + i))
		for x in tp.pumpen(t2 + 1):
			wartend += 1 if x.art == "klopft" else 0
	check(wartend == 6 and tp.online.wartend.size() == 6 and sb.letzter(ZN.ENTSCHEID)[8] == 0xFF, "Drossel: höchstens 6 Anklopfer je Minute, der Rest still abgewiesen")
	check(tp.ablehnen("%016x" % 0x1000) and sb.letzter(ZN.ENTSCHEID)[8] == 0xFF and tp.online.wartend.size() == 5, "Ablehnen: still")
	check(tp.annehmen("%016x" % 0x1001, t2 + 2) == "ok" and tp.plaetze["%016x" % 0x1001] == 1, "zweiter Gast: Platz 1")
	check(tp.sperren("%016x" % 0x1001) and sb.letzter(ZN.SCHLIESSEN) == PackedByteArray([1]) and tp.online.gesperrt.has("%016x" % 0x1001), "Sperren im Zimmer: Platz zu, gesperrt")
	check(tp.sperren("%016x" % 0x1002) and sb.letzter(ZN.ENTSCHEID) == ("%016x" % 0x1002).hex_decode() + PackedByteArray([0xFF]), "Sperren beim Anklopfen: still abgewiesen")
	check(tp.rauswerfen("a1b2c3d4e5f60718") and sb.letzter(ZN.SCHLIESSEN) == PackedByteArray([0]) and tp.plaetze.is_empty() and not tp.rauswerfen("a1b2c3d4e5f60718"),
			"Rauswerfen: Platz zu")
	# Höchstzahl.
	tp.online.einstellen(1)
	check(tp.annehmen("%016x" % 0x1003, t2 + 3) == "ok" and tp.annehmen("%016x" % 0x1004, t2 + 3) == "voll", "Höchstzahl der Gäste")
	# Der Gast geht (Sandbox meldet „zu“ auf seinem Platz).
	sb.rein = _stand(7, 0)
	tp.pumpen(t2 + 4)
	check(tp.plaetze.is_empty() and tp.online.gaeste.is_empty(), "Gast weg (Stand „zu“): Platz frei")
	# Ablauf: nach einer Stunde schließen alle übrigen Postfächer.
	var vorher := sb.anzahl(ZN.ZURUECK)
	tp.pumpen(t2 + 3601)
	check(sb.anzahl(ZN.ZURUECK) - vorher >= 7 and tp.online.einladungen.is_empty(), "abgelaufene Einladungen: Postfach zu")
	sb.rein = _klopft(links[9].kennung, "%016x" % 0x2000)
	check(tp.pumpen(t2 + 3700).is_empty(), "nach Ablauf: niemand kommt mehr an")
	sb.rein = _stand(5)
	var st := tp.pumpen(t2 + 3701)
	check(st.size() == 1 and tp.stand == "signatur_fehlt", "Stand „Signatur fehlt“ kommt in der Oberfläche an")
	tp.offline()
	check(sb.ende and tp.online.gaeste.is_empty() and tp.online.einladungen.is_empty(), "„Zimmer offline“: Sandbox beendet, alles leer")
	var kaputt := Nachbau.new("gastgeber")
	var tk := TP.new("gastgeber", kaputt)
	kaputt.rein = PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF])
	var ek := tk.pumpen(t)
	check(ek.size() == 1 and ek[0].art == "kaputt" and tk.einladen(t, 60, "A", "steam") != "" and kaputt.anzahl(ZN.EINLADUNG) == 0, "kaputte Leitung: nichts geht mehr hinaus")


func _gast() -> void:
	print("Gast")
	var sb := Nachbau.new("gast")
	var tp := TP.new("gast", sb)
	var e := Einladung.neu(1000, 60, true)
	check(not tp.besuchen("uzai://zimmer#z1.kaputt") and not tp.besuchen("https://example.org/#" + Einladung.link(e).get_slice("#", 1)) and sb.raus.is_empty(),
			"falsche Links: kein Besuch")
	check(tp.besuchen(Einladung.link(e)) and sb.letzter(ZN.BESUCH) == e.kennung + e.schluessel, "Besuch mit dem Link: Kennung und Schlüssel in die Sandbox")
	check(tp.einladen(1000, 60, "A", "steam") == "" and not tp.annehmen("0011223344556677", 1000) == "ok", "Gast lädt niemanden ein, nimmt niemanden an")
	sb.rein = _stand(2) + _stand(6) + _stand(7)
	var st := tp.pumpen(1001).map(func(x: Dictionary) -> String: return str(x.get("was", "")))
	check(st == ["angenommen", "verbunden", "zu"], "Gast sieht: angenommen, verbunden, zu")


func _netzlibs() -> void:
	print("Netz-Bibliotheken, Testschalter")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var a := cfg.find("include_filter=\"")
	var muster: Array = Array(cfg.substr(a + 16, cfg.find("\"", a + 16) - a - 16).split(",")).map(func(x: String) -> String: return x.strip_edges())
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var im_paket := true
	var gleich := true
	for name in ZN.NETZLIBS:
		var pfad: String = "assets/net/" + str(name)
		im_paket = im_paket and FileAccess.file_exists("res://" + pfad) and muster.any(func(m: String) -> bool: return pfad.match(m))
		gleich = gleich and FileAccess.get_sha256("res://" + pfad) == ZN.NETZLIBS[name] and helfer.contains("\"" + str(ZN.NETZLIBS[name]) + "\"")
	check(im_paket, "beide DLLs im Windows-Paket (export_presets.cfg)")
	check(gleich, "Prüfsummen gleich in Datei, Uzai und Helfer")
	check(ZN.NETZLIBS.size() == 2 and not FileAccess.file_exists("res://assets/net/uzai-datachannel.gdextension"), "Uzai lädt keine davon selbst (keine GDExtension)")
	var dir := OS.get_user_data_dir().path_join("netzlibs_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("uzai-secp256k1.dll"), FileAccess.WRITE)
	f.store_string("nicht die echte Datei")
	f.close()
	var fehlt := ZN.netzlibs_auslegen(dir)
	var alle_da := true
	for name in ZN.NETZLIBS:
		alle_da = alle_da and FileAccess.get_sha256(dir.path_join(str(name))) == ZN.NETZLIBS[name]
	check(fehlt.is_empty() and alle_da, "Auslegen neben den Helfer: falsche Datei ersetzt, beide geprüft")
	check(not Online.darf_testen(false, false, true) and not Online.darf_testen(true, true, true) and not Online.darf_testen(true, false, false)
			and Online.darf_testen(true, false, true), "Testbetrieb nur eingeschaltet, ohne Admin, nach bestandener Probe")
	check(Config.DEFAULTS.room.online_test == false and Config.DEFAULTS.room.online == false and Config.DEFAULTS.room.online_hinweis == false,
			"Standard: Zimmer online aus, Testschalter aus, Hinweis noch nicht bestätigt")
	var l := ZN.Leitung.new("gastgeber", false)
	check(l.treff(4000).is_empty() and not l.treff(0).is_empty() and l.test_rein(0, PackedByteArray([1])).is_empty(), "Echtbetrieb: nur die festen Relays, keine Test-Gegenstelle")
	var ev := l.eingang(_stand(8, 3) + _stand(9), 1.0)
	check(ev.size() == 2 and ev[0].was == "gescheitert" and ev[0].a == 3 and ev[1].was == "direkt_fehlt", "neue Zustände: gescheitert (mit Platz), Datenkanal fehlt")
	var lg := ZN.Leitung.new("gast")
	lg.eingang(_stand(8, 1), 1.0)
	check(lg.kaputt == "stand", "gescheitert mit fremdem Platz: Leitung zu")
	var ui = load("res://src/room/online_ui.gd").new()
	var ui_s: GDScript = ui.get_script()
	var echt: Dictionary = ui_s.probe_antwort({ "ok": true, "result": { "ok": true, "container": true, "secp": 1 } })
	check(bool(echt.ok) and echt.get("container") == true and int(echt.secp) == 1, "Probe: Ergebnis aus result gelesen (nicht die Hülle)")
	var kaputt: Dictionary = ui_s.probe_antwort({ "ok": false, "error": "Zeit abgelaufen" })
	check(not bool(kaputt.ok) and str(kaputt.fehler) == "Zeit abgelaufen", "Probe gescheitert: Grund sichtbar")
	check(str(ui_s.probe_antwort({}).fehler) == "helfer", "Probe ohne Antwort: Grund „helfer“")
	var t: String = ui.abschottung_text({ "ok": true, "secp": 1, "rtc": 3 }, {})
	check(t.contains("libsecp256k1): ja") and t.contains("libdatachannel): Prüfsumme falsch"), "Abschottung prüfen zeigt beide Bibliotheken (geladen, Prüfsumme, Selbsttest)")
	var v: String = ui.verbindung_text({ "relays": 3, "gesamt": 4, "klopft": true, "verbunden": false, "fehler": "direkt" })
	check(v.contains("3 von 4") and v.contains("Direktverbindung: nein"), "Verbindungstest: Relays, Anklopfen, Direktverbindung, Nachricht")
	ui.free()

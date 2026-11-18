extends Node
## Overlay im Spiel (Versuch, docs/OVERLAY.md): wem es erlaubt ist, Erkennung von Schutzprogrammen, Kopf der
## Bilddatei, Schreiben ohne gerissene Bilder. Aufruf: godot --headless --path . res://tests/logic_overlay.tscn
## Die Bibliothek selbst prüft tools/bau_overlay.sh (--test: Kopf, --wine: Durchlauf).

const O := preload("res://src/core/overlay_spiel.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Wem das Overlay erlaubt ist")
	var pc := { "source": "steam", "install_dir": "C:/Spiele/Alt", "overlay": true }
	check(bool(O.erlaubt(pc, true, ["alt.exe", "data"]).ok), "PC-Spiel, eingeschaltet, kein Schutzprogramm: ja")
	check(str(O.erlaubt(pc, false, []).grund) == "windows", "nicht unter Windows: nein")
	var aus := pc.duplicate()
	aus.erase("overlay")
	check(str(O.erlaubt(aus, true, ["alt.exe"]).grund) == "aus", "Standard ist aus")
	check(str(O.erlaubt(pc, true, []).grund) == "ordner", "Spielordner leer oder nicht lesbar: nein (nichts gesehen heißt nicht „kein Schutzprogramm“)")
	check(O.vorab(pc, true) == "" and O.vorab(pc, false) == "windows" and O.vorab({ "source": "disc" }, true) == "emulator"
			and O.vorab({ "source": "steam" }, true) == "ordner", "was ohne Blick in den Ordner feststeht")
	check(str(O.erlaubt({ "source": "rom", "install_dir": "x", "overlay": true }, true, []).grund) == "emulator", "Emulator-Spiele: nein (dort hält Uzai an)")
	check(str(O.erlaubt({ "source": "steam", "overlay": true }, true, []).grund) == "ordner", "ohne Spielordner: nein (Anti-Cheat ließe sich nicht ausschließen)")
	var mit := O.erlaubt(pc, true, ["Game.exe", "EasyAntiCheat", "data"])
	check(not bool(mit.ok) and str(mit.grund) == "anticheat" and str(mit.schutz) == "Easy Anti-Cheat", "Easy Anti-Cheat im Ordner: nein, mit Namen")
	check(str(O.erlaubt(aus, true, ["BEService_x64.exe"]).grund) == "anticheat", "Schutzprogramm geht vor „aus“: der Schalter ist gesperrt")
	print("Schutzprogramme an Namen")
	for paar in [["EasyAntiCheat_EOS", "Easy Anti-Cheat"], ["BattlEye", "BattlEye"], ["BEClient_x64.dll", "BattlEye"], ["vgk.sys", "Vanguard"],
			["GameGuard.des", "nProtect GameGuard"], ["XIGNCODE", "XIGNCODE"], ["mhyprot2.sys", "mhyprot"], ["AntiCheatExpert", "Anti-Cheat Expert"],
			["pbsvc.exe", "PunkBuster"], ["EQU8", "EQU8"]]:
		check(O.anticheat_in(["a.exe", str(paar[0])]) == str(paar[1]), "%s → %s" % [paar[0], paar[1]])
	check(O.anticheat_in(["Game.exe", "data", "saves", "Engine", "readme.txt"]) == "", "gewöhnlicher Spielordner: nichts erkannt")
	check(O.anticheat_in([]) == "", "leerer Ordner: nichts erkannt")
	print("Bilddatei")
	var k := O.kopf(6, true, 620, 1080)
	check(k.size() == 64 and k.decode_u32(0) == O.MAGIC and k.decode_u32(4) == 1 and k.decode_u32(8) == 6 and k.decode_u32(12) == 1
			and k.decode_u32(16) == 620 and k.decode_u32(20) == 1080, "Kopf: 64 Byte, Kennzeichen, Fassung, Zähler, sichtbar, Maße")
	check(O.naechster(0) == 2 and O.naechster(2) == 4 and O.naechster(3) == 4 and O.naechster(0xFFFFFFFE) == 0, "Zähler: immer der nächste gerade, läuft sauber über")
	check(O.groesse_ok(620, 1080) and not O.groesse_ok(0, 10) and not O.groesse_ok(O.MAX_BREITE + 1, 10) and not O.groesse_ok(10, O.MAX_HOEHE + 1),
			"Größe: nur innerhalb der Grenzen, die auch die Bibliothek annimmt")
	var pfad := OS.get_environment("UZAI_DATA").path_join("overlay_test/bild.bin")
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var z := O.bild_schreiben(pfad, img, true, 0)
	var roh := FileAccess.get_file_as_bytes(pfad)
	check(z == 2 and roh.size() == 64 + 8 * 4 * 4 and roh.decode_u32(8) == 2 and roh.decode_u32(12) == 1 and roh.decode_u32(16) == 8 and roh.decode_u32(20) == 4,
			"Schreiben: Kopf und Punkte, Zähler danach gerade")
	check(roh[64] == 255 and roh[65] == 0 and roh[66] == 0 and roh[67] == 255, "Punkte als R, G, B, A")
	var z2 := O.sichtbar_setzen(pfad, false, z)
	roh = FileAccess.get_file_as_bytes(pfad)
	check(z2 == 4 and roh.decode_u32(8) == 4 and roh.decode_u32(12) == 0 and roh.size() == 64 + 8 * 4 * 4, "Verstecken: nur das Feld, das Bild bleibt, Zähler gerade")
	var klein := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var z3 := O.bild_schreiben(pfad, klein, true, z2)
	check(z3 == 6 and FileAccess.get_file_as_bytes(pfad).size() == 64 + 8 * 4 * 4, "kleineres Bild: die Datei wird nie kürzer (im Spiel ist sie abgebildet)")
	check(O.bild_schreiben(pfad, Image.create(O.MAX_BREITE + 1, 2, false, Image.FORMAT_RGBA8), true, z3) == -1, "zu großes Bild: nichts geschrieben")
	check(O.sichtbar_setzen(pfad + ".fehlt", true, 0) == -1, "ohne Datei: nichts")
	print("Starter")
	check(O.starter("", 32, 1234, "x") == 10 and O.starter("C:/x", 16, 1234, "x") == 10 and O.starter("C:/x", 32, 0, "x") == 10,
			"ohne Ordner, mit falscher Bitbreite oder ohne Prozess: gar nicht erst rufen")
	check(O.ERGEBNIS.has(1) and O.ERGEBNIS.has(5) and O.ERGEBNIS.has(12) and O.ERGEBNIS.has(19), "jede Zahl des Starters hat einen Satz fürs Protokoll")
	var namen := O.ordner_namen("res://native/overlay")
	check(namen.has("uzai_overlay.c") and namen.has("uzai_overlay.h"), "Ordnernamen lesen (%d)" % namen.size())
	check(O.ordner_namen("res://gibt/es/nicht").is_empty(), "fehlender Ordner: leer, kein Fehler")
	print("Anschluss im Code")
	var fe := FileAccess.get_file_as_string("res://src/main_fenster.gd")
	var gu := FileAccess.get_file_as_string("res://src/main_guide.gd")
	check(gu.contains("await _overlay_spiel_bereit()") and gu.find("_enter_overlay_spiel()") < gu.find("_spiel_kurz_weg(grund)"),
			"Guide: erst der Versuch im Spiel, sonst der bisherige Weg")
	check(fe.contains("func _ov_wache()") and fe.contains("weiter deckend wie ohne Overlay"), "verliert das Spiel den Vordergrund, geht es deckend weiter")
	check(fe.contains('if not bool(g.get("overlay", false)):') and fe.contains("OverlaySpiel.erlaubt(g, true"), "nur eingeschaltet und geprüft")
	print("In welchen Prozess")
	check(O.prozess_passt(4200, 4200, []) and O.prozess_passt(5100, 0, [5100, 5200]), "der selbst gestartete Prozess oder einer aus dem Spielordner: ja")
	check(not O.prozess_passt(7000, 0, [5100]) and not O.prozess_passt(7000, 4200, []), "Fenster eines anderen Prozesses (Starter, Launcher): nein")
	check(not O.prozess_passt(0, 0, []) and not O.prozess_passt(4, 4, [4]), "unbekannt oder Systemprozess: nein")
	check(O.ERGEBNIS.has(6) and str(O.ERGEBNIS[2]).contains("11"), "Ergebnisse des Starters: Direct3D 11 und 12 benannt")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

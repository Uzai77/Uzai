extends Node
## Eigene Spiele hinzufügen (Punkt 117): Ordner durchsuchen ohne Installer und Hilfsprogramme,
## die richtige Programmdatei je Spiel, Namensvorschläge, Prüfung von Datei, Parametern und Ordner.
## Aufruf: godot --headless --path . res://tests/logic_eigene_spiele.tscn

const GameFinder := preload("res://src/library/game_finder.gd")
const SpielSymbol := preload("res://src/library/spiel_symbol.gd")

var fails := 0
var root := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	root = OS.get_user_data_dir().path_join("eigene_spiele_test")
	_fixtures()
	_scan()
	_names()
	_checks()
	_symbol()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Ein Spieleordner wie auf echten PCs: GOG, Unity, Unreal, Installer-Reste, Laufzeit-Pakete.
func _fixtures() -> void:
	_file("Hades/Hades.exe", 40)
	_file("Hollow_Knight [GOG]/hollow_knight.exe", 30)
	_file("Hollow_Knight [GOG]/unins000.exe", 2)
	_file("Hollow_Knight [GOG]/UnityCrashHandler64.exe", 2)
	_file("Celeste v1.4.0.0/Celeste.exe", 20)
	_file("Celeste v1.4.0.0/Celeste_Launcher.exe", 25)
	_file("SomeGame/SomeGame.exe", 1)
	_file("SomeGame/SomeGame/Binaries/Win64/SomeGame-Win64-Shipping.exe", 80)
	_file("SomeGame/Engine/Binaries/Win64/CrashReportClient.exe", 30)
	_file("_CommonRedist/vcredist_x64.exe", 10)
	_file("Nur Setup/setup.exe", 10)
	_file("Tief/a/b/c/d/tief.exe", 10)
	_file("Hades/readme.txt", 1)


func _scan() -> void:
	print("Ordner durchsuchen")
	var found := GameFinder.scan(root)
	var by_title := {}
	for c in found:
		by_title[str(c.title)] = c
	check(by_title.has("Hades") and by_title.has("Hollow Knight") and by_title.has("Celeste") and by_title.has("Some Game"),
			"ein Spiel je Unterordner, mit lesbarem Namen (%s)" % str(by_title.keys()))
	check(found.size() == 4, "Installer-Reste, Laufzeit-Pakete und zu tiefe Ordner zählen nicht (%d)" % found.size())
	check(str(by_title.get("Hollow Knight", {}).get("exe", "")).ends_with("hollow_knight.exe"), "Deinstaller und Crash-Handler sind nie das Spiel")
	check(str(by_title.get("Celeste", {}).get("exe", "")).ends_with("/Celeste.exe"), "Programm wie der Ordner vor dem Launcher")
	check(str(by_title.get("Some Game", {}).get("exe", "")).ends_with("SomeGame.exe") and not str(by_title.get("Some Game", {}).get("exe", "")).contains("Engine"),
			"Unreal: das Spiel, nie der Crash-Reporter aus Engine")
	check((by_title.get("Some Game", {}).get("others", []) as Array).size() == 1, "die andere Programmdatei steht zur Wahl")
	var known := { root.path_join("Hades/Hades.exe").to_lower(): true }
	check(GameFinder.scan(root, known).filter(func(c: Dictionary) -> bool: return str(c.title) == "Hades").is_empty(), "schon in Uzai: fehlt in der Liste")
	var one := GameFinder.scan(root.path_join("Hades"))
	check(one.size() == 1 and str(one[0].folder) == root.path_join("Hades") and str(one[0].title) == "Hades", "ein einzelner Spieleordner ist selbst das Spiel")
	check(GameFinder.scan(root.path_join("gibt_es_nicht")).is_empty() and GameFinder.scan("").is_empty(), "fehlender Ordner: leer, kein Fehler")


func _names() -> void:
	print("Namen")
	check(GameFinder.clean_title("Hollow_Knight [GOG]") == "Hollow Knight", "Unterstriche und [Beiwerk] weg")
	check(GameFinder.clean_title("Celeste v1.4.0.0") == "Celeste", "Versionsnummer am Ende weg")
	check(GameFinder.clean_title("Witcher 3 (GOG)") == "Witcher 3" and GameFinder.clean_title("God of War (2018)") == "God of War (2018)",
			"(GOG) weg, Jahreszahl bleibt")
	check(GameFinder.clean_title("DOOMEternal") == "DOOM Eternal" and GameFinder.clean_title("HollowKnight") == "Hollow Knight",
			"zusammengeschriebene Namen getrennt")
	check(GameFinder.clean_title("Half-Life 2") == "Half-Life 2" and GameFinder.clean_title("Hades.II") == "Hades II",
			"Bindestrich bleibt, Punkt zwischen Wörtern wird Leerzeichen")
	check(GameFinder.suggest_name("C:/Spiele/X/Binaries/Win64/Frostpunk-Win64-Shipping.exe", "Win64") == "Frostpunk",
			"nichtssagender Ordner: Name aus der Datei ohne -Win64-Shipping")
	check(GameFinder.clean_title("Doom64") == "Doom64", "Zahl im Namen bleibt")
	check(GameFinder.name_for_pick("C:/Users/Robin/Desktop/Elden Ring.lnk") == "Elden Ring"
			and GameFinder.name_for_pick("C:/Users/Robin/Desktop/Hades - Verknüpfung.lnk") == "Hades",
			"Verknüpfung gewählt: ihr Name, nicht der Ordner („Desktop“)")
	check(GameFinder.name_for_pick("C:/Users/Robin/Desktop/Celeste.exe") == "Celeste", "Programm auf dem Desktop: Dateiname, nicht „Desktop“")
	check(GameFinder.name_for_pick("C:/Spiele/Hades/Hades.exe") == "Hades", "Programm im Spieleordner: wie bisher")


func _checks() -> void:
	print("Prüfen")
	var exe := root.path_join("Hades/Hades.exe")
	check(GameFinder.exe_problem(exe) == "", "vorhandene .exe in Ordnung")
	check(GameFinder.exe_problem(root.path_join("Hades/readme.txt")) != "" and GameFinder.exe_problem(root.path_join("Hades/fehlt.exe")) != ""
			and GameFinder.exe_problem("Hades.exe") != "", "andere Endung, fehlende Datei, relativer Pfad abgelehnt")
	check(GameFinder.args_problem("-windowed -w 1920 \"-name=A B\"", exe) == "", "normale Startparameter")
	check(GameFinder.args_problem("a & b", exe) == "", "& bei .exe harmlos (keine Shell)")
	check(GameFinder.args_problem("-x & calc", "C:/g/start.bat") != "" and GameFinder.args_problem("%PATH%", "C:/g/start.cmd") != "",
			"bei Batch-Dateien keine Zeichen, die weitere Befehle starten")
	check(GameFinder.args_problem("\"offen", exe) != "" and GameFinder.args_problem("a\nb", exe) != "" and GameFinder.args_problem("x".repeat(2000), exe) != "",
			"offenes Anführungszeichen, Zeilenumbruch, zu lang abgelehnt")
	check(GameFinder.dir_problem("") == "" and GameFinder.dir_problem(root.path_join("Hades")) == "" and GameFinder.dir_problem(root.path_join("fehlt")) != "",
			"Arbeitsordner: leer oder vorhanden")
	check(Library.add_manual("X", root.path_join("Hades/readme.txt")).is_empty() and Library.add_manual("X", exe, "a\nb").is_empty(),
			"Bibliothek nimmt nichts Ungeprüftes")
	var g := Library.add_manual("", exe)
	check(str(g.get("title", "")) == "Hades" and str(g.get("source", "")) == "pc", "ohne Namen: Vorschlag aus dem Ordner")
	check(Library.add_manual("Anders", exe) == g, "zweimal dieselbe Datei: derselbe Eintrag")
	# Unter „Steam“ (wie Steams „Nicht-Steam-Spiel“), dort vorn, solange es frisch hinzugefügt ist.
	check(Library.eigen(g) and not Library.eigen({ "source": "pc", "scanned": true }), "selbst hinzugefügt ≠ aus einem PC-Ordner eingelesen")
	check(Library.by_tab("steam").has(g) and Library.by_tab("pc").has(g) and not Library.by_system("steam").has(g),
			"steht unter Steam und unter PC")
	var jetzt := int(Time.get_unix_time_from_system())
	var alt := { "id": "test:alt", "source": "steam", "title": "Alt", "last_played": jetzt - 3600 }
	var neu := { "id": "test:neu", "source": "steam", "title": "Neu", "last_played": jetzt + 3600 }
	var reihe := Library.sorted([alt, g, neu], "recent")
	check(reihe[0] == neu and reihe[1] == g and reihe[2] == alt,
			"„Zuletzt“: das neue eigene Spiel zählt ab dem Hinzufügen wie gerade gespielt (%s)" % str(reihe.map(func(x): return x.title)))
	Library.remove(str(g.id))
	# Internet-Verknüpfungen: Start-Links von Launchern ja, Webseiten nein (wie pc_scanner.gd).
	var link := _text("Links/Galaxy.url", "[InternetShortcut]\nURL=goggalaxy://openGameView/1207658924\n")
	var web := _text("Links/Seite.url", "[InternetShortcut]\nURL=https://example.com/\n")
	var leer := _text("Links/Leer.url", "[InternetShortcut]\n")
	check(GameFinder.exe_problem(link) == "" and GameFinder.exe_problem(web) != "" and GameFinder.exe_problem(leer) != "",
			".url: Launcher-Link ja, Webseite und leere Verknüpfung nein")
	var lg := Library.add_manual("Galaxy-Spiel", link)
	check(str(lg.get("url", "")) == "goggalaxy://openGameView/1207658924", ".url: Adresse steht im Eintrag (Start über den Launcher)")
	Library.remove(str(lg.id))


## Symbol der Desktop-Verknüpfung (spiel_symbol.gd): das des Spiels, Uzai nur ohne alles.
func _symbol() -> void:
	print("Symbol der Verknüpfung")
	var hades := root.path_join("Hades/Hades.exe")
	check(SpielSymbol.direkt({ "source": "pc", "target": hades }, "") == hades, "eigenes Spiel: seine Programmdatei")
	check(SpielSymbol.direkt({ "source": "rom", "target": hades }, root.path_join("Celeste v1.4.0.0/Celeste.exe")).ends_with("Celeste.exe"),
			"ROM: das Programm des Emulators")
	check(SpielSymbol.direkt({ "source": "pc", "target": root.path_join("Hades/readme.txt") }, "") == "", "nur .exe oder .ico")
	check(SpielSymbol.gueltig("\\\\server\\x\\a.exe", func(_p: String) -> bool: return true) == ""
			and SpielSymbol.gueltig("C:/a/../b.exe", func(_p: String) -> bool: return true) == ""
			and SpielSymbol.gueltig("C:/a/b.exe", func(_p: String) -> bool: return true) == "C:/a/b.exe",
			"kein Netzwerkpfad, kein „..“; sauberer Pfad geht")
	check(SpielSymbol.gueltig(root.path_join("fehlt.exe")) == "", "fehlende Datei taugt nicht")
	check(SpielSymbol.ordner({ "source": "steam", "install_dir": root.path_join("Hollow_Knight [GOG]") }) != ""
			and SpielSymbol.ordner({ "source": "steam", "install_dir": "C:/Program Files" }) == "", "Installationsordner, nie ein Sammelordner")
	check(SpielSymbol.aus_ordner(root.path_join("Hollow_Knight [GOG]"), "Hollow Knight").ends_with("hollow_knight.exe"),
			"Steam/GOG: die Programmdatei im Installationsordner, nicht der Deinstaller")
	check(SpielSymbol.aus_ordner(root.path_join("Nur Setup")) == "", "nur ein Installer: nichts")
	var img := Image.create_empty(184, 69, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.8))
	var ico := SpielSymbol.ico_aus_bild(img)
	check(ico.size() > 22 and ico.decode_u16(2) == 1 and ico.decode_u16(4) == 1 and ico.decode_u32(18) == 22
			and ico.decode_u32(14) == ico.size() - 22 and ico.slice(22, 26) == PackedByteArray([0x89, 0x50, 0x4E, 0x47]),
			"Bild als .ico: Kopf, Verzeichnis, PNG darin")
	img.save_png(root.path_join("icon.png"))
	var out := SpielSymbol.ico_schreiben(root.path_join("icon.png"), root.path_join("symbole"), "steam:570/../x")
	check(out.ends_with("/symbole/steam_570____x.ico") and FileAccess.file_exists(out), "Bibliothekssymbol als .ico im Datenordner, Name ohne Pfadzeichen")
	check(SpielSymbol.ico_schreiben(root.path_join("Hades/readme.txt"), root.path_join("symbole"), "x") == "", "keine Bilddatei: nichts")


func _text(rel: String, text: String) -> String:
	var p := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p


func _file(rel: String, kb: int) -> void:
	var p := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	var b := PackedByteArray()
	b.resize(kb * 1024)
	f.store_buffer(b)
	f.close()

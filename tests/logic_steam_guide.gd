extends Node
## Steams Guide-Taste abschalten (src/core/steam_guide.gd): nur der eine Wert in localconfig.vdf
## ändert sich, alles andere bleibt Byte für Byte; bei unbekanntem Aufbau wird nichts geschrieben;
## vor der ersten Änderung liegt eine Sicherung daneben.
## Aufruf: godot --headless --path . res://tests/logic_steam_guide.tscn

const G := preload("res://src/core/steam_guide.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_text()
	_fremd()
	_dateien()
	_tempo()
	await _start_frage()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## On start: inform first, then disable, so users notice that Uzai turns off Steam's Guide button.
func _start_frage() -> void:
	print("Beim Start: vorher sagen")
	check(G.entscheidung(false, "ja") == "stellen" and G.entscheidung(false, "nein") == "behalten" and G.entscheidung(false, "") == "spaeter",
			"„Verstanden“ schaltet ab, „Steam behalten“ lässt es, weggedrückt fragt beim nächsten Start wieder")
	check(G.entscheidung(true, "") == "nichts" and G.entscheidung(true, "nein") == "nichts", "steht schon aus: nichts mehr zu tun")
	check(G.entscheidung(null, "x") == "spaeter", "unbekannte Antwort: später")
	check(G.frage_text(true).contains("Steam startet dafür kurz neu") and not G.frage_text(false).contains("startet"),
			"der Neustart von Steam wird nur genannt, wenn Steam läuft")
	check(G.frage_text(false).contains("auch, wenn Uzai nicht läuft") and G.frage_text(true).contains("Einstellungen › Controller"),
			"sagt, dass es auch ohne Uzai gilt und wo man es zurückstellt")
	# Die Frage kommt als Callable aus main (wartet auf den Dialog): Das Ergebnis kommt über await an.
	var frage := func(laeuft: bool) -> String:
		await get_tree().process_frame
		return "ja" if laeuft else "nein"
	check(str(await frage.call(true)) == "ja" and str(await frage.call(false)) == "nein", "Antwort einer wartenden Frage kommt an")


## So sieht Steams Datei aus (gekürzt): Wurzel, eigene Abschnitte, JSON in Zeichenketten.
func _beispiel(guide: String, nl := "\n") -> String:
	var lines := [
		"\"UserLocalConfigStore\"",
		"{",
		"\t\"Broadcast\"",
		"\t{",
		"\t\t\"Permissions\"\t\t\"1\"",
		"\t}",
		"\t\"Software\"",
		"\t{",
		"\t\t\"Valve\"",
		"\t\t{",
		"\t\t\t\"Steam\"",
		"\t\t\t{",
		"\t\t\t\t\"Controller_CheckGuideButton\"\t\t\"1\"",
		"\t\t\t\t\"Pfad\"\t\t\"C:\\\\Spiele\\\\\"",
		"\t\t\t}",
		"\t\t}",
		"\t}",
		"\t\"WebStorage\"",
		"\t{",
		"\t\t\"FriendStoreLocalPrefs_1\"\t\t\"{\\\"ePersonaState\\\":1,\\\"Controller_CheckGuideButton\\\":\\\"}\\\"}\"",
		"\t}",
	]
	if guide != "":
		lines.insert(2, "\t\"Controller_CheckGuideButton\"\t\t\"%s\"" % guide)
	lines.append("\t\"Zuletzt\"\t\t\"ä ö ü – 漢字\"")
	lines.append("}")
	return nl.join(PackedStringArray(lines)) + nl


func _text() -> void:
	print("Nur der eine Wert ändert sich")
	var an := _beispiel("1")
	var aus := G.mit_wert(an, "0")
	check(aus == _beispiel("0"), "vorhandener Eintrag: nur der Wert wird zu 0")
	check(aus.length() == an.length() and aus.substr(0, 40) == an.substr(0, 40), "Länge und Rest unverändert")
	check(G.mit_wert(aus, "0") == aus, "steht schon auf 0: Text unverändert")
	check(G.mit_wert(aus, "1") == an, "zurück auf 1: wieder genau der alte Text")
	check(G.aus_in(aus) == true and G.aus_in(an) == false, "Stand wird erkannt")
	# Gleichnamige Schlüssel tiefer (Software/Valve/Steam) oder im JSON zählen nicht.
	var ohne := _beispiel("")
	var l := G.lage(ohne)
	check(bool(l.ok) and int(l.von) == -1, "tiefer liegender gleicher Schlüssel und JSON-Inhalt zählen nicht")
	check(G.aus_in(ohne) == false, "fehlt der Eintrag: Steam-Standard „an“")
	var eingefuegt := G.mit_wert(ohne, "0")
	check(eingefuegt == _beispiel("0"), "fehlender Eintrag: Zeile direkt hinter der Wurzel-Klammer")
	check(G.mit_wert(ohne, "1") == ohne, "auf 1 ohne Eintrag: nichts einzufügen")
	var crlf := _beispiel("", "\r\n")
	check(G.mit_wert(crlf, "0") == _beispiel("0", "\r\n"), "Windows-Zeilenenden bleiben Windows-Zeilenenden")
	check(G.mit_wert(_beispiel("1", "\r\n"), "0") == _beispiel("0", "\r\n"), "mit CRLF: Wert ersetzt")
	check(G.mit_wert(an, "2") == "" and G.mit_wert(an, "") == "", "nur 0 oder 1")
	var gross := an.replace("\"Controller_CheckGuideButton\"\t\t\"1\"\n\t\"Broadcast\"", "\"controller_checkguidebutton\"\t\t\"1\"\n\t\"Broadcast\"")
	check(G.lage(gross).von != -1 and G.mit_wert(gross, "0").count("\"0\"") == 1, "Groß/klein wie bei Steam egal")


func _fremd() -> void:
	print("Unbekannter Aufbau: nichts schreiben")
	var gut := _beispiel("1")
	var faelle := {
		"leer": "",
		"abgeschnitten": gut.substr(0, gut.length() / 2),
		"Klammer fehlt am Ende": gut.substr(0, gut.rfind("}")),
		"Kommentar": gut.replace("\t\"Broadcast\"", "\t// hier\n\t\"Broadcast\""),
		"Wort ohne Anführungszeichen": gut.replace("\"Permissions\"", "Permissions"),
		"zweite Wurzel": gut + "\"Noch\"\n{\n}\n",
		"andere Wurzel": gut.replace("UserLocalConfigStore", "AppState"),
		"doppelter Schlüssel": gut.replace("\t\"Broadcast\"\n", "\t\"Controller_CheckGuideButton\"\t\t\"1\"\n\t\"Broadcast\"\n"),
		"Wert offen": gut.replace("\"Permissions\"\t\t\"1\"", "\"Permissions\"\t\t\"1"),
		"zu viele }": gut + "}\n",
		"Wert als Abschnitt erwartet": gut.replace("\t\"Broadcast\"\n\t{", "\t\"Broadcast\"\t\"x\"\n\t{"),
		"BOM": "\ufeff" + gut,
	}
	for name in faelle:
		check(G.mit_wert(str(faelle[name]), "0") == "", "%s: nichts geändert" % name)
	check(G.aus_in("\"UserLocalConfigStore\"\n{\n\t\"Controller_CheckGuideButton\"\t\t\"0\"\n}\n") == true, "kleinste gültige Datei")


func _dateien() -> void:
	print("Dateien: Sicherung, nur Ziffern-Ordner, fremde Dateien bleiben")
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	root = root.path_join("steam_guide_test")
	for id in ["12345", "678", "abc", "0", "-5"]:
		DirAccess.make_dir_recursive_absolute(root.path_join("userdata/%s/config" % id))
	_put(root.path_join("userdata/12345/config/localconfig.vdf"), _beispiel("1").to_utf8_buffer())
	_put(root.path_join("userdata/678/config/localconfig.vdf"), _beispiel("").to_utf8_buffer())
	_put(root.path_join("userdata/abc/config/localconfig.vdf"), _beispiel("1").to_utf8_buffer())
	_put(root.path_join("userdata/0/config/localconfig.vdf"), _beispiel("1").to_utf8_buffer())
	var files := G.dateien(root)
	check(files.size() == 2 and files[0].contains("/12345/") != files[1].contains("/12345/"), "nur echte Konto-Ordner (Ziffern, > 0)")
	var p := root.path_join("userdata/12345/config/localconfig.vdf")
	check(G.datei_aus(p) == false, "vorher an")
	check(G.datei_stellen(p, "0") == "geändert", "abgeschaltet")
	check(FileAccess.get_file_as_string(p) == _beispiel("0"), "Datei: nur der Wert anders")
	check(FileAccess.get_file_as_string(p + G.SICHERUNG) == _beispiel("1"), "Sicherung vom Stand vorher")
	check(not FileAccess.file_exists(p + G.NEU), "keine Zwischendatei übrig")
	check(G.datei_stellen(p, "0") == "schon", "zweites Mal: nichts zu tun")
	check(G.datei_stellen(p, "1") == "geändert" and FileAccess.get_file_as_string(p) == _beispiel("1"), "zurück auf an")
	check(FileAccess.get_file_as_string(p + G.SICHERUNG) == _beispiel("1"), "Sicherung bleibt die erste")
	var q := root.path_join("userdata/678/config/localconfig.vdf")
	check(G.datei_stellen(q, "0") == "geändert" and G.datei_aus(q) == true, "fehlender Eintrag: eingefügt")
	# Kein reines UTF-8 (z. B. Latin-1): lieber nicht anfassen.
	var latin := _beispiel("1").to_utf8_buffer()
	latin.append(0xE4)
	_put(p, latin)
	check(G.datei_stellen(p, "0") == "fremd" and FileAccess.get_file_as_bytes(p) == latin, "kein UTF-8: Datei bleibt Byte für Byte")
	var kaputt := _beispiel("1").substr(0, 50).to_utf8_buffer()
	_put(p, kaputt)
	check(G.datei_stellen(p, "0") == "fremd" and FileAccess.get_file_as_bytes(p) == kaputt, "abgeschnittene Datei bleibt, wie sie ist")
	check(G.datei_stellen(root.path_join("fehlt.vdf"), "0") == "fehler", "fehlende Datei: Fehler, nichts angelegt")
	check(not FileAccess.file_exists(root.path_join("fehlt.vdf")), "fehlende Datei wird nicht angelegt")
	check(G.dateien("").is_empty() and G.dateien(root.path_join("gibtsnicht")).is_empty(), "ohne Steam: keine Dateien")


## Echte Dateien sind mehrere MB groß (viele Spiele, JSON in WebStorage): Zerlegen bleibt schnell.
func _tempo() -> void:
	print("Große Datei")
	var parts := PackedStringArray()
	parts.append("\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n")
	for i in 40000:
		parts.append("\t\t\t\t\t\"%d\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"%d\"\n\t\t\t\t\t\t\"Playtime\"\t\t\"%d\"\n\t\t\t\t\t\t\"cloud\"\t\t\"{\\\"a\\\":{\\\"b\\\":%d}}\"\n\t\t\t\t\t}\n" % [i, 1700000000 + i, i % 977, i])
	parts.append("\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n")
	var big := "".join(parts)
	var t0 := Time.get_ticks_msec()
	var neu := G.mit_wert(big, "0")
	var ms := Time.get_ticks_msec() - t0
	print("       %.1f MB in %d ms" % [big.length() / 1048576.0, ms])
	check(neu.length() == big.length() + "\n\t\"Controller_CheckGuideButton\"\t\t\"0\"".length(), "große Datei: Zeile eingefügt")
	check(G.aus_in(neu) == true, "große Datei: schneller Weg erkennt „aus“")
	check(ms < 4000, "große Datei in unter 4 s zerlegt")


func _put(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()

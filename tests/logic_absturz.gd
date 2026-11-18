extends Node
## Absturzschutz (Punkt 55): Erkennen eines unerwarteten Endes, Sicherer Modus nach zwei Enden
## beim Starten, Fehlerbericht ohne Persönliches und in QR-Größe, QR bis Version 40 wie die
## Referenz (Project Nayuki). Aufruf: godot --headless --path . res://tests/logic_absturz.tscn

const CrashGuard := preload("res://src/core/crash_guard.gd")
const Qr := preload("res://src/core/qr.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_verdict()
	_marker()
	_clean()
	_log_tail()
	_report()
	_safe_mode()
	_watch()
	_qr()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _verdict() -> void:
	print("Wie ging das letzte Uzai zu?")
	check(CrashGuard.verdict({}, 10, false).is_empty(), "keine Markierung: sauber")
	var m := { "pid": 77, "started": 1000, "seen": 1030, "version": "0.8.3", "streak": 0, "stable": false, "where": "movies" }
	check(CrashGuard.verdict(m, 77, false).is_empty(), "eigene Markierung zählt nicht")
	check(CrashGuard.verdict(m, 10, true).is_empty(), "Prozess läuft noch (zweites oder hängendes Uzai): kein Absturz")
	var off := m.duplicate()
	off.where = "aus"
	check(CrashGuard.verdict(off, 10, false).is_empty(), "Windows fuhr herunter: kein Absturz")
	var v := CrashGuard.verdict(m, 10, false)
	check(bool(v.quick) and int(v.streak) == 1 and str(v.where) == "movies" and int(v.at) == 1030, "Ende kurz nach dem Start: erstes in Folge, Ort und Zeit")
	check(not CrashGuard.needs_safe(v), "ein Ende: noch kein Sicherer Modus")
	var again := m.duplicate()
	again.streak = 1
	check(CrashGuard.needs_safe(CrashGuard.verdict(again, 10, false)), "zweites Ende beim Starten in Folge: Sicherer Modus")
	var stable := m.duplicate()
	stable.stable = true
	stable.streak = 0
	var vs := CrashGuard.verdict(stable, 10, false)
	check(not bool(vs.quick) and int(vs.streak) == 0 and not CrashGuard.needs_safe(vs), "Absturz nach gelungenem Start: Hinweis, kein Sicherer Modus")


func _marker() -> void:
	print("Markierung")
	var d := Config.data_dir.path_join("test_absturz")
	DirAccess.make_dir_recursive_absolute(d)
	CrashGuard.write(d, { "pid": 4242, "started": 1, "where": "" })
	check(int(CrashGuard.read(d).get("pid", 0)) == 4242, "schreiben und lesen")
	CrashGuard.clear(d, 999)
	check(FileAccess.file_exists(CrashGuard.marker_path(d)), "fremde Markierung bleibt liegen")
	CrashGuard.clear(d, 4242)
	check(not FileAccess.file_exists(CrashGuard.marker_path(d)) and CrashGuard.read(d).is_empty(), "eigene Markierung weg, kein .bak bleibt zurück")
	var f := FileAccess.open(CrashGuard.marker_path(d), FileAccess.WRITE)
	f.store_string("{\"pid\": 42")
	f.close()
	var broken := CrashGuard.read(d)
	check(not CrashGuard.verdict(broken, 10, false).is_empty(), "halb geschriebene Markierung: Uzai lief, also unerwartet beendet")
	DirAccess.remove_absolute(CrashGuard.marker_path(d))
	# Config führt die Markierung des laufenden Uzai.
	Config.run_started()
	var mine := CrashGuard.read(Config.data_dir)
	check(int(mine.get("pid", 0)) == OS.get_process_id() and str(mine.get("version", "")) == Config.VERSION, "Config legt die eigene Markierung an")
	Config.run_where("spiel")
	check(str(CrashGuard.read(Config.data_dir).get("where", "")) == "spiel", "Ort wird mitgeschrieben")
	check(CrashGuard.verdict(CrashGuard.read(Config.data_dir), OS.get_process_id(), true).is_empty(), "laufendes Uzai gilt nie als abgestürzt")


func _clean() -> void:
	print("Bericht ohne Persönliches")
	var homes := ["C:\\Users\\Robin"]
	var c := CrashGuard.clean("ERROR: kann C:\\Users\\Robin\\AppData\\Roaming\\Uzai\\settings.json nicht ersetzen", homes)
	check(not c.contains("Robin") and c.contains("settings.json"), "eigener Benutzerordner raus, Dateiname bleibt: " + c)
	c = CrashGuard.clean("open C:/Users/Anna Maria/x.txt and D:\\Users\\bob\\y", [])
	check(not c.contains("Anna") and not c.contains("Maria") and not c.contains("bob") and c.contains("x.txt"),
			"fremde Benutzerordner raus (auch mit Leerzeichen): " + c)
	c = CrashGuard.clean("GET https://api.example.com/v1/me?access_token=abc123secret&x=1 failed", [])
	check(c.contains("https://api.example.com") and not c.contains("abc123secret") and not c.contains("/v1/me"), "Adresse nur bis zum Server: " + c)
	c = CrashGuard.clean("Konto max.mustermann@example.org, Freund 76561198000000001, PC 192.168.1.23", [])
	check(not c.contains("mustermann") and not c.contains("76561198000000001") and not c.contains("192.168"), "E-Mail, Steam-ID und IP raus: " + c)
	c = CrashGuard.clean("refresh_token=Zm9vYmFyYmF6 key: 0123456789abcdef0123456789abcdef01234567", [])
	check(not c.contains("Zm9vYmFyYmF6") and not c.contains("0123456789abcdef"), "Schlüssel raus: " + c)
	c = CrashGuard.clean("   at: _on_movie_streams_loaded_callback (res://src/ui/layers/movie_streams.gd:123)", [])
	check(c.contains("_on_movie_streams_loaded_callback") and c.contains("res://src/ui/layers/movie_streams.gd:123"),
			"Funktionsnamen und Skriptpfade bleiben: " + c)


func _log_tail() -> void:
	print("Protokoll")
	var text := "\n".join([
		"Godot Engine v4.5.1.stable.official",
		"Uzai: YouTube (Fernseher-Anmeldung): Code ABCD-EFGH",
		"WARNING: Uzai: Windows-Helfer (main) konnte nicht starten",
		"     at: push_warning (core/variant/variant_utility.cpp:1034)",
		"ERROR: Kaputtes Bild in C:\\Users\\Robin\\Pictures\\a.png",
		"ERROR: Kaputtes Bild in C:\\Users\\Robin\\Pictures\\a.png",
		"SCRIPT ERROR: Invalid access to property 'title' on a base object of type 'Nil'.",
		"          at: _row (res://src/ui/sections/media_view.gd:146)",
		"CrashHandlerException: Program crashed",
		"Dumping the backtrace.",
		"[0] Godot.exe+0x1234",
		"[1] Godot.exe+0x5678",
		"-- END OF BACKTRACE --",
		"ERROR: " + "x".repeat(400),
	])
	var lines := CrashGuard.log_tail(text, ["C:\\Users\\Robin"])
	var all := "\n".join(lines)
	check(not all.contains("ABCD-EFGH") and not all.contains("Godot Engine"), "gewöhnliche Ausgaben bleiben draußen")
	check(all.contains("SCRIPT ERROR") and all.contains("media_view.gd:146") and all.contains("[1] Godot.exe+0x5678"), "Fehler, Ort und Rückverfolgung drin")
	check(all.count("Kaputtes Bild") == 1 and not all.contains("Robin"), "doppelte Zeilen einmal, ohne Benutzername")
	check(lines[lines.size() - 1].length() <= CrashGuard.LINE_MAX, "lange Zeilen gekürzt")
	check(CrashGuard.log_tail(text, [], 3).size() == 3, "nur die letzten Zeilen")


func _report() -> void:
	print("Fehlerbericht")
	var lines := PackedStringArray()
	for i in 40:
		lines.append("ERROR: Fehler Nummer %d in res://src/core/movies.gd:%d" % [i, i])
	var info := { "version": "0.8.3", "os": "Windows 10.0.22631", "godot": "4.5.1", "gpu": "NVIDIA GeForce RTX 3070", "safe": true,
		"crash": { "quick": true, "streak": 2, "where": "movies" }, "where": "in Filme" }
	var r := CrashGuard.build(info, lines)
	check(str(r.url).to_utf8_buffer().size() <= CrashGuard.MAX_URL, "Adresse passt in den QR (%d Bytes)" % str(r.url).to_utf8_buffer().size())
	check(str(r.url).begins_with(CrashGuard.ISSUE_URL + "?title="), "führt zu einer neuen GitHub-Meldung")
	check(int(r.lines) > 0 and int(r.lines) < 40 and str(r.text).contains("Nummer 39") and not str(r.text).contains("Nummer 0 "),
			"die neuesten Zeilen bleiben, die ältesten fallen weg")
	check(str(r.title) == "Absturz in Uzai 0.8.3" and str(r.text).contains("kurz nach dem Start") and str(r.text).contains("2× in Folge")
			and str(r.text).contains("Sicherer Modus"), "Titel, Ende und Sicherer Modus im Text")
	check(not str(r.url).contains(" ") and not str(r.url).contains("\n"), "Adresse sauber kodiert")
	var plain := CrashGuard.build({ "version": "0.8.3", "crash": {} }, PackedStringArray())
	check(str(plain.title) == "Fehler in Uzai 0.8.3" and not str(plain.text).contains("Protokoll"), "ohne Absturz und ohne Zeilen: schlichte Meldung")


func _safe_mode() -> void:
	print("Sicherer Modus")
	Config.set_value("theme.boot", "voll")
	Config.set_value("movies.plugins_on", true)
	Config.safe_mode = true
	check(str(Config.get_value("theme.boot", "")) == "aus" and not bool(Config.get_value("movies.plugins_on", true)), "Startanimation und Plugins aus")
	check(str(Config.get_value("system.on_start", "")) == "home" and not bool(Config.get_value("library.scan_on_start", true)), "kein Spiel von selbst, kein Scan")
	check(str(Config.get_value("theme.font_file", "x")) == "" and str(Config.get_value("theme.background_image", "x")) == "",
			"keine eigenen Dateien für Schrift und Bild")
	Config.safe_mode = false
	check(str(Config.get_value("theme.boot", "")) == "voll" and bool(Config.get_value("movies.plugins_on", false)), "Einstellungen selbst unverändert")


func _watch() -> void:
	print("Wächter nach Absturz")
	var j := Helper.crash_job("C:/Spiele/Uzai/Uzai.exe", PackedStringArray(["--headless", "--rendering-driver", "opengl3"]),
		PackedStringArray(["--launch=steam:42", "--nach-neustart=77", "--nach-absturz", "--sicherer-modus", "--woken", "--windowed"]),
		4242, "C:/Users/x/AppData/Roaming/Uzai/laeuft.json", "ps.exe", "helfer.ps1", "auftrag", true)
	check(j.args == ["--rendering-driver", "opengl3", "--", "--windowed", "--nach-absturz"],
			"dieselben Argumente, ohne Einmaliges, mit --nach-absturz: %s" % str(j.args))
	check(str(j.exe) == "C:\\Spiele\\Uzai\\Uzai.exe" and str(j.dir) == "C:\\Spiele\\Uzai" and str(j.marker).ends_with("\\laeuft.json"), "Windows-Pfade")
	check(int(j.pid) == 4242 and str(j.watch) == "auftrag", "Kennung und Guide-Wächter für den Fall im Spiel")
	var u := Helper.crash_job("/opt/uzai/uzai", PackedStringArray(), PackedStringArray(), 1, "/d/laeuft.json", "", "", "", false)
	check(str(u.exe) == "/opt/uzai/uzai" and str(u.marker) == "/d/laeuft.json", "ohne Windows bleiben Pfade, wie sie sind")
	var m := { "pid": 5, "started": 1, "seen": 2, "stable": true, "streak": 0, "where": "music", "auto": 1 }
	check(not CrashGuard.verdict(m, 9, false).is_empty() and int(m.auto) < 2, "nach einem Neustart darf er noch einmal (höchstens zweimal in Folge)")


func _qr() -> void:
	print("QR bis Version 40 (wie die Referenz)")
	var cases := [
		["Hallo Welt äöü", "L", 7, 3, "53246cde134706d3e681fb8eff40e847"],
		["https://github.com/Uzai77/Uzai/issues/new?title=a&body=" + "b".repeat(900), "L", 27, 2, "005a4c7bb190d7e6e86672e4d7db3be9"],
		["s".repeat(2900), "L", 40, 0, "7d07e35f3a863b629cfd208888ff222d"],
		["t".repeat(1000), "H", 40, 3, "811c63b3baf67a987265dd39ebe7ece1"],
		["u".repeat(1200), "M", 33, 6, "68ae607ca51ca1f465fb08a217ad84c6"],
	]
	for c in cases:
		var rows := Qr.encode(str(c[0]), str(c[1]), int(c[3]), int(c[2]))
		var lines := PackedStringArray()
		for r in rows:
			var line := ""
			for b in r:
				line += "1" if b == 1 else "0"
			lines.append(line)
		check("\n".join(lines).md5_text() == str(c[4]), "Version %d, Stufe %s, Maske %d" % [c[2], c[1], c[3]])
	check(Qr.encode("x".repeat(3000), "L").is_empty(), "zu lang: kein Code statt eines falschen")
	var big := Qr.encode("w".repeat(1300), "M")
	check(big.size() == 4 * 30 + 17, "Version wird passend gewählt (1300 Bytes, Stufe M: 30)")

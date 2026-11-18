extends Node
## „Spiele neu einlesen“ und die Disc vom Laufwerk, ohne Windows: Der Scanner lässt leere und
## unvollständige Dateien weg (ohne gute Dateien zu verwerfen), Pfade mit „\“ ergeben keine
## Doppelten, Einträge ohne Datei oder nicht mehr gefunden verschwinden beim Einlesen – Spielzeit
## bleibt –, ausgeschaltete Systeme bleiben unberührt. Disc direkt: Parameter für DuckStation und
## PCSX2, nur echte Laufwerke, und nichts bleibt zurück (keine Datei, kein Eintrag).
## Aufruf: godot --headless --path . res://tests/logic_neueinlesen.tscn

const RomScanner := preload("res://src/library/rom_scanner.gd")
const DiscSerialS := preload("res://src/library/disc_serial.gd")
const DiscsS := preload("res://src/core/discs.gd")
const QR := preload("res://src/core/quick_resume.gd")
const Sicher := preload("res://src/core/sicher.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_scanner()
	await _merge()
	await _scan_echt()
	_disc_args()
	_disc_ohne_reste()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _put(p: String, text := "x") -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _scanner() -> void:
	print("Scanner: unbrauchbare Dateien")
	var root := Config.path("einlesen/ps1")
	_put(root.path_join("Gut.iso"), "daten")
	_put(root.path_join("Leer.iso"), "")
	_put(root.path_join("FF (Disc 1).cue"), "FILE \"FF (Disc 1).bin\" BINARY\n  TRACK 01 MODE2/2352\n")
	_put(root.path_join("FF (Disc 1).bin"), "bin")
	_put(root.path_join("FF (Disc 2).cue"), "FILE \"FF (Disc 2).bin\" BINARY\n")
	_put(root.path_join("FF (Disc 2).bin"), "bin")
	_put(root.path_join("FF.m3u"), "FF (Disc 1).cue\r\nFF (Disc 2).cue\r\n")
	_put(root.path_join("Halb.cue"), "FILE \"Halb (Track 1).bin\" BINARY\nFILE \"Halb (Track 2).bin\" BINARY\n")
	_put(root.path_join("Halb (Track 1).bin"), "bin")
	_put(root.path_join("Bom.cue"), char(0xFEFF) + "FILE \"Bom.bin\" BINARY\n")
	_put(root.path_join("Bom.bin"), "bin")
	_put(root.path_join("Umlaut.cue"), "FILE \"Spür.bin\" BINARY\n")
	_put(root.path_join("Ohne Spur.cue"), "REM nur ein Kommentar\n")
	_put(root.path_join("Leer.m3u"), "\n# nichts\n")
	var sys := Config.system("ps1")
	var res := RomScanner.scan_full(sys, root)
	var games: Array = res[0]
	var skipped: Array = res[1]
	var names := games.map(func(g): return str(g.path).get_file())
	names.sort()
	check(names == ["Bom.cue", "FF.m3u", "Gut.iso", "Umlaut.cue"], "brauchbar: Gut.iso, FF.m3u (deckt beide Discs), Bom.cue, Umlaut.cue (%s)" % str(names))
	var why := {}
	for k in skipped:
		why[str(k.path).get_file()] = str(k.why)
	check(why.get("Leer.iso", "") == "leer", "0 Byte: übersprungen („leer“)")
	check(why.get("Halb.cue", "") == "unvollständig", ".cue mit fehlender Spur: übersprungen")
	check(why.get("Ohne Spur.cue", "") == "unvollständig" and why.get("Leer.m3u", "") == "unvollständig", ".cue ohne Spur, .m3u ohne Disc: übersprungen")
	check(not why.has("Bom.cue"), "Byte-Order-Mark vor FILE: kein Fehlalarm")
	check(not why.has("Umlaut.cue"), "Umlaut im Spurnamen (Kodierung unklar): im Zweifel behalten")
	check(RomScanner.problem(root.path_join("gibt es nicht.iso")) != "", "fehlende Datei: unbrauchbar")
	check(RomScanner.problem(root.path_join("Gut.iso")) == "", "gute Datei: kein Problem")
	# Derselbe Ordner mit „\“ geschrieben (eingetippt): keine einzelnen Discs neben der .m3u.
	var back := RomScanner.scan(sys, root.replace("/", "\\")) if OS.get_name() == "Windows" else RomScanner.scan(sys, root + "/")
	check(back.size() == 4, "Ordner mit Trenner am Ende: dieselben vier Spiele (%d)" % back.size())
	var cov: Array = RomScanner._references(root.path_join("FF.m3u"))
	check(cov.size() == 2 and str(cov[0]).ends_with("/FF (Disc 1).cue"), ".m3u: Verweise mit „/“")
	# Fremde Liste mit Windows-Freigaben: nie nachsehen (NTLM an den genannten Rechner).
	_put(root.path_join("Fremd.m3u"), "\\\\203.0.113.5\\x\\disc1.chd\n//203.0.113.5/x/disc2.chd\n\\??\\UNC\\203.0.113.5\\x\\d3.chd\n")
	check(RomScanner._references(root.path_join("Fremd.m3u")).is_empty() and DiscSerialS.sheet_files(root.path_join("Fremd.m3u")).is_empty(),
			".m3u mit Freigaben: keine Verweise (nie ein Zugriff übers Netz)")
	DirAccess.remove_absolute(root.path_join("Fremd.m3u"))
	# Sammlung auf einem NAS: Verweise auf denselben Rechner bleiben, ein anderer Rechner nie (ohne Zugriff geprüft).
	check(Sicher.verweis_ok("//nas/roms/ps1/x.bin", "//NAS/roms/ps1") and Sicher.verweis_ok("\\\\nas\\roms\\x.bin", "//nas/roms")
			and not Sicher.verweis_ok("//203.0.113.5/x.bin", "//nas/roms") and not Sicher.verweis_ok("\\??\\UNC\\nas\\x.bin", "//nas/roms")
			and Sicher.verweis_ok("D:/Roms/x.bin", "//nas/roms"), "NAS: derselbe Rechner ja, fremder Rechner und NT-Pfad nein")
	var dc := Config.path("einlesen/dc")
	_put(dc.path_join("Spiel.gdi"), "2\n1 0 4 2352 \"Track 01.bin\" 0\n2 600 0 2352 track02.raw 0\n")
	_put(dc.path_join("Track 01.bin"), "bin")
	_put(dc.path_join("track02.raw"), "raw")
	check(RomScanner.problem(dc.path_join("Spiel.gdi")) == "", ".gdi mit Leerzeichen im Spurnamen: vollständig")
	DirAccess.remove_absolute(dc.path_join("track02.raw"))
	check(RomScanner.problem(dc.path_join("Spiel.gdi")) == "unvollständig", ".gdi ohne zweite Spur: unvollständig")


func _merge() -> void:
	print("Zusammenführen: was nicht mehr gefunden wird")
	var root := Config.path("einlesen/m")
	var a := root.path_join("A.iso")
	var b := root.path_join("B.iso")
	var c := root.path_join("C.iso")
	for p in [a, b, c]:
		_put(p, "daten")
	var mk := func(id: String, p: String, sys := "ps1") -> Dictionary:
		return { "id": id, "title": id, "system": sys, "source": "rom", "path": p, "installed": true }
	Library.games = [mk.call("ps1:a", a), mk.call("ps1:b", b), mk.call("ps1:weg", root.path_join("weg.iso")), mk.call("wii:c", c, "wii")]
	Library.games[1]["playtime"] = 3600
	Library._reindex()
	# Nur A wurde gefunden; B liegt noch da, gehört aber nicht mehr dazu (Ordner gewechselt, .m3u …).
	var gone: int = Library._merge([mk.call("ps1:a", a)], ["rom"], [], ["ps1"])
	check(not bool(Library.get_game("ps1:a").get("missing", false)), "gefunden: bleibt")
	check(bool(Library.get_game("ps1:b").get("missing", false)), "Datei da, aber nicht mehr gefunden: verschwindet (früher „kaputt“)")
	check(int(Library.get_game("ps1:b").get("playtime", 0)) == 3600, "Spielzeit bleibt am Eintrag")
	check(bool(Library.get_game("ps1:weg").get("missing", false)), "Datei weg: verschwindet")
	check(not bool(Library.get_game("wii:c").get("missing", false)), "System nicht durchsucht (aus oder Ordner fehlt): bleibt unberührt")
	check(gone == 2, "zwei Spiele fehlen jetzt (%d)" % gone)
	check(Library.visible_games().all(func(g): return str(g.id) != "ps1:b"), "nicht mehr sichtbar")
	gone = Library._merge([mk.call("ps1:a", a), mk.call("ps1:b", b)], ["rom"], [], ["ps1"])
	check(not bool(Library.get_game("ps1:b").get("missing", false)) and gone == 0, "taucht wieder auf: alles wieder da, nichts neu entfernt")
	# Ohne Liste der Systeme (ältere Aufrufer): wie früher nur, wenn die Datei fehlt.
	Library._merge([mk.call("ps1:a", a)], ["rom"])
	check(not bool(Library.get_game("ps1:b").get("missing", false)), "ohne Systemliste: Datei da → bleibt (wie früher)")
	var m3: Dictionary = mk.call("ps1:a", a)
	Library.get_game("ps1:a")["discs"] = [a, b]
	Library._merge([m3], ["rom"], [], ["ps1"])
	check(not Library.get_game("ps1:a").has("discs"), "aus mehreren Discs wurde eine: alte Disc-Liste weg")
	check(Library.scan_text({ "games": 12, "gone": 2 }) == "12 Spiele  ·  2 entfernt (Datei fehlt oder unvollständig)", "Meldung nennt, was entfernt wurde")
	check(Library.scan_text({ "games": 1, "gone": 0, "skipped": 0 }) == "1 Spiel  ·  nichts kaputt", "Meldung ohne Befund")
	# Eine Quelle, deren Einlesen nicht ging (Scan abgebrochen, Helfer ohne Antwort), behält ihre Spiele.
	var st := { "id": "steam:570", "title": "Dota 2", "system": "steam", "source": "steam", "appid": 570, "installed": true }
	var ep := { "id": "epic:x", "title": "Epic-Spiel", "system": "epic", "source": "epic", "installed": true }
	Library.games = [mk.call("ps1:a", a), st, ep]
	Library._reindex()
	gone = Library._merge([mk.call("ps1:a", a)], [], ["steam"], ["ps1"])
	check(not bool(Library.get_game("steam:570").get("missing", false)), "Steam nicht gelesen (steht in „bleibt“): Steam-Spiele bleiben sichtbar")
	check(bool(Library.get_game("epic:x").get("missing", false)) and gone == 1, "Epic gelesen und leer: das Epic-Spiel ist wirklich weg")
	Library.get_game("epic:x").erase("missing")
	Library._merge([], ["epic"], ["epic"])
	check(not bool(Library.get_game("epic:x").get("missing", false)), "Epic nachsehen bricht ab: das Spiel bleibt")
	# Der Hintergrund-Scan merkt sich, ob er abbrach (statt einer Liste kam nichts).
	var leer: Array = await Library._threaded(func() -> Array: return [])
	check(leer.is_empty() and not Library._scan_abbruch, "Scan liefert eine leere Liste: kein Abbruch")
	var kaputt: Array = await Library._threaded(func() -> Variant: return null)
	check(kaputt.is_empty() and Library._scan_abbruch, "Scan liefert nichts (Fehler im Auftrag): als Abbruch gemerkt")


## Ganzes Einlesen mit einem System ohne Disc-Erkennung (kein Netz nötig).
func _scan_echt() -> void:
	print("Einlesen von Hand")
	var root := Config.path("einlesen/saturn")
	_put(root.path_join("Gut.cue"), "FILE \"Gut.bin\" BINARY\n")
	_put(root.path_join("Gut.bin"), "bin")
	_put(root.path_join("Kaputt.cue"), "FILE \"Kaputt.bin\" BINARY\n")
	_put(root.path_join("Kaputt.bin"), "bin")
	Config.set_system("saturn", "enabled", true)
	Config.set_rom_dir("saturn", root)
	Library.games = []
	Library._reindex()
	Library.scan(false, true)
	while Library.scanning:
		await get_tree().process_frame
	var sat := func() -> Array: return Library.visible_games().filter(func(g): return str(g.system) == "saturn")
	check(sat.call().size() == 2, "beide Spiele gefunden (%d)" % sat.call().size())
	var kid := ""
	for g in sat.call():
		if str(g.path).ends_with("Kaputt.cue"):
			kid = str(g.id)
	Library.get_game(kid)["playtime"] = 120
	# Die Spur der einen Disc fehlt jetzt: „Spiele neu einlesen“ nimmt sie heraus.
	DirAccess.remove_absolute(root.path_join("Kaputt.bin"))
	Library.scan(false, true)
	while Library.scanning:
		await get_tree().process_frame
	check(sat.call().size() == 1 and str(sat.call()[0].path).ends_with("Gut.cue"), "unvollständige Disc verschwindet nach dem Neu-Einlesen")
	check(int(Library.last_scan.get("gone", 0)) == 1 and int(Library.last_scan.get("skipped", 0)) == 1,
			"Ergebnis: 1 entfernt, 1 übersprungen (%s)" % str(Library.last_scan))
	check(int(Library.get_game(kid).get("playtime", 0)) == 120, "ihre Spielzeit bleibt gemerkt")
	check(FileAccess.file_exists(root.path_join("Kaputt.cue")), "Uzai löscht dabei keine Spieldatei")
	_put(root.path_join("Kaputt.bin"), "bin")
	Library.scan()
	while Library.scanning:
		await get_tree().process_frame
	check(sat.call().size() == 2, "Spur wieder da: Spiel wieder da")
	Config.set_system("saturn", "enabled", false)
	Library.scan()
	while Library.scanning:
		await get_tree().process_frame
	Config.set_system("saturn", "enabled", true)
	check(sat.call().size() == 2, "System kurz aus und wieder an: nichts verloren")
	Config.set_system("saturn", "enabled", false)


func _disc_args() -> void:
	print("Disc direkt vom Laufwerk: Parameter")
	check(DiscsS.drive_letter("E:\\") == "E" and DiscsS.drive_letter("e:") == "E" and DiscsS.drive_letter("F:/") == "F", "Laufwerk „E:\\“, „e:“, „F:/“")
	for bad in ["", "E", "E:\\Spiele", "\\\\server\\x", "C:\\..\\", "-disc", "E:\\\" -x"]:
		check(DiscsS.drive_letter(bad) == "", "kein Laufwerk: %s" % bad)
	var ds := DiscsS.direct_args("duckstation", str(Config.emulator("duckstation").args), "E:\\")
	check(ds == "-batch -fullscreen -nogui -- \\\\.\\E:", "DuckStation: Laufwerk statt Datei (%s)" % ds)
	var p2 := DiscsS.direct_args("pcsx2", str(Config.emulator("pcsx2").args), "E:\\")
	check(p2 == "-fullscreen -nogui -batch -disc E:\\", "PCSX2: -disc E:\\, ohne „--“ (%s)" % p2)
	check(DiscsS.direct_args("pcsx2", "-nogui -- {rom}", "D:") == "-nogui -disc D:\\", "PCSX2: eigene Parameter ohne Anführungszeichen")
	check(DiscsS.direct_args("mednafen", "\"{rom}\"", "E:\\") == "", "andere Emulatoren: nicht direkt")
	check(DiscsS.direct_args("duckstation", "-batch", "E:\\") == "", "Parameter ohne {rom}: nicht direkt")
	check(DiscsS.direct_args("duckstation", "\"{rom}\"", "E:\\x") == "", "kein echtes Laufwerk: nichts")


func _disc_ohne_reste() -> void:
	print("Disc direkt: nichts bleibt zurück")
	var exe := Config.path("einlesen/emu/duckstation.exe")
	_put(exe, "exe")
	Config.set_emulator("duckstation", "exe", exe)
	Config.set_system("ps1", "enabled", true)
	Config.set_system("ps1", "emulator", "duckstation")
	Library.games = []
	Library._reindex()
	check(DiscsS.direct_any(), "DuckStation eingerichtet: Laufwerk wird abgefragt, auch ohne PS1-Spiele")
	# Redump-Liste schon da (sonst lüde Uzai sie für den Namen der Disc aus dem Netz).
	Library.set_disc_db("ps1", { "serials": { "SCES-00867": "Final Fantasy VII (Europe) (Disc 1)" }, "files": {} })
	var before := _list(Config.path(""))
	Discs.set_disc("SCES-00867", "ps1", "E:\\")
	await get_tree().process_frame
	check(Discs.can_play(), "Disc ohne Abbild: A spielt direkt")
	var g := Discs.direct_game()
	check(str(g.get("_disc_drive", "")) == "E:\\" and str(g.get("source", "")) == "rom" and str(g.get("id", "")).begins_with("disc:"),
			"Spiel nur für diesen Start")
	var cmd: Dictionary = Launcher._rom_command(g)
	check(not cmd.has("error") and str(cmd.get("args", "")).ends_with("-- \\\\.\\E:"),
			"Start: DuckStation mit dem Laufwerk (%s)" % str(cmd.get("args", cmd.get("error", ""))))
	check(not QR.supported(g), "keine Stände für die Disc vom Laufwerk")
	check(Library.games.is_empty() and Library.get_game(str(g.id)).is_empty(), "kein Eintrag in der Bibliothek")
	Library.touch(str(g.id))
	Library.record_session(str(g.id), 600)
	check(Library.games.is_empty(), "auch nach dem Spielen kein Eintrag")
	var after := _list(Config.path(""))
	check(after == before, "keine neue Datei im Datenordner (%s)" % str(after.filter(func(x): return not before.has(x))))
	Config.set_system("ps1", "emulator", "retroarch")
	check(not Discs.can_play() and Discs.direct_game().is_empty(), "Emulator kann es nicht: „Abbild zuordnen“ bleibt")
	Config.set_system("ps1", "emulator", "duckstation")
	Discs.set_disc("", "", "")
	Config.set_emulator("duckstation", "exe", "")


func _list(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		out.append(dir.path_join(f))
	for d in da.get_directories():
		out.append_array(_list(dir.path_join(d)))
	out.sort()
	return out

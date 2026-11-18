extends Node
## Ruhemodus und Spielstände ohne Windows: Ordner und Dateien der Emulatoren, Sichern und
## Wiederherstellen des Platzes, Ablage mit mehreren Ständen (automatisch, eigene, alte Form),
## Wiederherstellen nach Absturz, Ladeparameter, Texte, Anti-Cheat-Erkennung, Regeln für PC-Spiele,
## Zeitsprung nach dem Schlafen, Ruhe-Anzeige und Ein-/Ausschlafen ohne Helfer.
## Aufruf: godot --headless --path . res://tests/logic_ruhemodus.tscn

const QR := preload("res://src/core/quick_resume.gd")
const Rest := preload("res://src/core/rest.gd")
const RestScreen := preload("res://src/ui/layers/rest_screen.gd")
const U := preload("res://src/ui/u.gd")

var fails := 0


class FakeMain extends Node:
	var layer_host: Control
	var _guide: Control = null
	var _guide_gen := 0
	var opened := 0

	func open_layer(l: Control, first: Control = null) -> Control:
		opened += 1
		l.open(layer_host, first)
		return l


class FakeRest extends Node:
	var woke := 0

	func wake(_src := "") -> void:
		woke += 1


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_dirs()
	_files()
	_entry_and_args()
	_texts()
	_records()
	_ablage()
	_alte_form()
	_retroarch_entry()
	_recover()
	await _rom_command()
	_anti_cheat()
	_policy()
	_sleep_gap()
	await _screen()
	await _enter_wake()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _tmp(name: String) -> String:
	var d := Config.path("test_ruhe").path_join(name)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _touch(p: String, text := "x") -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _dirs() -> void:
	print("Ordner der Emulatoren")
	var env := { "documents": "C:/Users/x/Documents", "appdata": "", "localappdata": "C:/Users/x/AppData/Local/" }
	var ds := QR.expand_dirs(QR.profile("duckstation"), "C:/Emu/DuckStation/duckstation-qt.exe", env)
	check(ds == ["C:/Emu/DuckStation/savestates", "C:/Users/x/AppData/Local/DuckStation/savestates", "C:/Users/x/Documents/DuckStation/savestates"],
			"DuckStation: neben der .exe, Local, Dokumente; leeres AppData fällt weg (%s)" % str(ds))
	var none := QR.expand_dirs(QR.profile("pcsx2"), "", { "documents": "", "appdata": "", "localappdata": "" })
	check(none.is_empty(), "ohne Emulator-Pfad und Windows-Ordner: keine Ordner")
	var dup := QR.expand_dirs({ "dirs": ["{emudir}/a", "{documents}/a"] }, "C:/X/e.exe", { "documents": "c:\\x" })
	check(dup.size() == 1, "gleiche Ordner (Groß/Klein, Trenner) nur einmal")
	check(QR.profile("mgba").is_empty() and not QR.profile("retroarch").is_empty(), "Profile nur für verlässliche Emulatoren")
	for id in QR.PROFILES.keys():
		check(not Config.emulator(str(id)).is_empty(), "Profil %s gehört zu einem Emulator aus data/emulators.json" % id)
		check(str((Config.emulator(str(id)).get("keys", {}) as Dictionary).get("save", "")) != "", "%s hat ab Werk ein Speichern-Kürzel" % id)
		check(QR.describe(str(id), "F2").contains("F2"), "%s: Beschreibung nennt das Kürzel" % id)
	check(str(Config.emulator("duckstation").keys.save) == "F2", "DuckStation: Speichern ist ab Werk F2 (F1 lädt)")


func _files() -> void:
	print("Dateien finden und sichern")
	var root := _tmp("scan")
	_touch(root.path_join("SLES-50330_1.sav"))
	_touch(root.path_join("SCUS-94163_1.sav"))
	_touch(root.path_join("notiz.txt"))
	_touch(root.path_join("sub/tief/SLES-50330_2.sav"))
	_touch(root.path_join("sub/tief/zu/tief/x.sav"))
	var s := QR.scan([root], "\\.sav$")
	check(s.size() == 3, "drei Spielstände bis zwei Ebenen tief, nicht .txt, nicht tiefer (%d)" % s.size())
	check(s.has(root.path_join("SLES-50330_1.sav")) and int((s[root.path_join("SLES-50330_1.sav")] as Array)[1]) == 1, "Pfad mit Größe")
	var before := { "a.sav": [100, 10], "b.sav": [100, 10] }
	check(QR.changed_file(before, before) == "", "nichts geändert: keine Datei")
	check(QR.changed_file(before, { "a.sav": [100, 10], "b.sav": [105, 12] }) == "b.sav", "geänderte Datei gefunden")
	check(QR.changed_file(before, { "a.sav": [100, 10], "b.sav": [100, 10], "c.sav": [107, 9] }) == "c.sav", "neue Datei gefunden")
	check(QR.changed_file(before, { "a.sav": [110, 10], "c.sav": [120, 9] }) == "c.sav", "mehrere: die jüngste")
	check(QR.changed_file({}, { "leer.sav": [120, 0] }) == "", "leere (noch geschriebene) Datei zählt nicht")
	var g := { "path": "D:/Spiele/PS1/SLES-50330 Gran Turismo.cue" }
	var tok := QR.name_tokens(g)
	check(tok.has("sles-50330 gran turismo") and tok.has("sles-50330") and tok.has("sles_50330"), "Erkennung: Dateiname und Seriennummer (%s)" % str(tok))
	var cand := QR.backup_candidates(s, tok, "")
	check(cand.size() == 2 and not cand.has(root.path_join("SCUS-94163_1.sav")), "gesichert werden nur die Stände dieses Spiels")
	var cand2 := QR.backup_candidates(s, [], root.path_join("SCUS-94163_1.sav"))
	check(cand2 == [root.path_join("SCUS-94163_1.sav")], "die Datei vom letzten Mal wird immer gesichert")


func _entry_and_args() -> void:
	print("RetroArch und Ladeparameter")
	check(QR.entry_for("C:/RA/states/Spiel.state3") == { "path": "C:/RA/states/Spiel.state3.entry", "slot": 3 }, "Platz 3 → Spiel.state3.entry, -e 3")
	check(QR.entry_for("C:/RA/states/Spiel.state") == { "path": "C:/RA/states/Spiel.state0.entry", "slot": 0 }, "Platz 0 → Spiel.state0.entry")
	check(QR.entry_for("C:/RA/states/Spiel.state.auto").is_empty(), "Auto-Stand ist kein Platz")
	check(QR.launch_args({ "emulator": "retroarch", "slot": 3 }) == "-e 3", "RetroArch: -e 3")
	var f := "C:/Uzai/quickresume/rom_1.sav"
	var want := f.replace("/", "\\") if OS.get_name() == "Windows" else f
	check(QR.launch_args({ "emulator": "duckstation", "file": f }) == "-statefile \"%s\"" % want, "DuckStation: -statefile")
	check(QR.launch_args({ "emulator": "pcsx2", "file": f }) == "-statefile \"%s\"" % want, "PCSX2: -statefile")
	check(QR.launch_args({ "emulator": "ppsspp", "file": f }) == "--state=\"%s\"" % want, "PPSSPP: --state=")
	check(QR.launch_args({ "emulator": "dolphin", "file": f }) == "-s \"%s\"" % want, "Dolphin: -s")
	check(QR.launch_args({ "emulator": "mgba", "file": f }) == "", "ohne Profil: keine Parameter")
	var rg := QR.resume_game({ "id": "x", "title": "T" }, { "emulator": "retroarch", "slot": 1 })
	check(str(rg.get("_resume_args", "")) == "-e 1" and str(rg.id) == "x", "Fortsetzen startet eine Kopie des Spiels mit Ladeparametern")


func _texts() -> void:
	print("Texte")
	check(QR.ago_short(30) == "gerade eben", "gerade eben")
	check(QR.ago_short(600) == "vor 10 Min.", "vor 10 Min.")
	check(QR.ago_short(7200) == "vor 2 Std.", "vor 2 Std.")
	check(QR.ago_short(90000) == "gestern", "gestern")
	check(QR.ago_short(3 * 86400) == "vor 3 Tagen", "vor 3 Tagen")
	check(QR.ago_short(20 * 86400) == "vor 2 Wochen", "vor 2 Wochen")
	check(QR.ago_short(-5) == "gerade eben", "Uhr verstellt: kein „vor -1 Min.“")
	check(QR.RESUME_TEXT == "Weiter, wo du warst", "Knopf: „Weiter, wo du warst“ (ohne Fachwort)")
	check(QR.state_line({ "kind": "own", "at": 1000 }, 1000 + 7300) == "Selbst gesichert  ·  vor 2 Std.", "Zeile: selbst gesichert, vor 2 Std.")
	check(QR.state_line({ "kind": "auto", "at": 1000 }, 1000 + 90000) == "Beim Beenden  ·  gestern", "Zeile: beim Beenden, gestern")
	var noon := 1767268800    # 1.1.2026 12:00 UTC
	check(QR.when_text(noon - 3600, noon, 0) == "Heute, 11:00", "Heute, 11:00 (%s)" % QR.when_text(noon - 3600, noon, 0))
	check(QR.when_text(noon - 86400, noon, 0) == "Gestern, 12:00", "Gestern, 12:00")
	check(QR.when_text(noon - 12 * 3600, noon, -60) == "Gestern, 23:00", "Ortszeit zählt (UTC−1): Mitternacht UTC ist dort noch gestern")
	var older := QR.when_text(noon - 5 * 86400, noon, 0)
	check(older.ends_with(", 12:00") and older.begins_with("27."), "älter: Datum und Uhrzeit (%s)" % older)
	check(Rest.safe_name("rom:ps1/Gran Turismo") == "rom_ps1_Gran_Turismo", "Dateiname aus der Spiel-ID")


func _records() -> void:
	print("Gespeicherte Stände")
	var st := _tmp("store")
	var file := st.path_join("rom_test.sav")
	_touch(file)
	var g := { "id": "rom:test:1", "source": "rom", "system": "ps1", "emulator": "duckstation", "path": "D:/x.cue" }
	check(QR.supported(g), "PS1 mit DuckStation: Schnellfortsetzen geht")
	check(not QR.supported({ "id": "s", "source": "steam" }), "Steam-Spiel: nein")
	check(not QR.supported({ "id": "m", "source": "rom", "emulator": "mgba" }), "mGBA: nein (lädt beim Start keinen Stand)")
	QR.add("rom:test:1", { "emulator": "duckstation", "at": 1000, "file": file })
	check(not QR.record(g, true).is_empty(), "Stand gespeichert und gültig")
	check(QR.record(g).is_empty() and not QR.WEITER_ANBIETEN, "„Weiter, wo du warst“ wird nicht mehr angeboten (aus)")
	check(QR.record({ "id": "rom:test:1", "source": "rom", "system": "ps1", "emulator": "pcsx2" }, true).is_empty(), "anderer Emulator am Spiel: Stand gilt nicht")
	Config.set_value("rest.quick_resume", false)
	check(QR.record(g, true).is_empty(), "Einstellung aus: keine gemerkte Stelle")
	Config.set_value("rest.quick_resume", true)
	check(not QR.supported({ "id": "disc:SLES-50330", "source": "rom", "system": "ps2", "emulator": "pcsx2" }), "Disc vom Laufwerk: keine Stände (nichts bleibt zurück)")
	QR.remove("rom:test:1", str((QR.states(g)[0] as Dictionary).id))
	check(QR.record(g, true).is_empty() and FileAccess.file_exists(file), "entfernt: Eintrag weg, Datei außerhalb von Uzais Ablage bleibt")
	check(str(Config.get_value("rest.pc_suspend", "")) == "safe" and str(Config.get_value("controller.guide_hold", "")) == "menu",
			"Standard: PC-Spiele nur ohne Anti-Cheat anhalten, Guide halten öffnet das Schnellmenü")


func _own(name: String, text := "x") -> String:
	var p := Config.path(QR.DIR).path_join(name)
	_touch(p, text)
	return p


func _ablage() -> void:
	print("Ablage mit mehreren Ständen")
	var gid := "rom:ablage:1"
	var g := { "id": gid, "source": "rom", "system": "ps1", "emulator": "duckstation", "path": "D:/a.cue" }
	var files: Array = []
	for i in 4:
		var f := _own("a_%d.sav" % i)
		var sh := _own("a_%d.jpg" % i)
		files.append([f, sh])
		QR.add(gid, { "emulator": "duckstation", "at": 1000 + i * 100, "file": f, "shot": sh, "slot_file": "C:/DS/savestates/SLUS-1_1.sav" })
	var autos := QR.states(g, "auto")
	check(autos.size() == QR.AUTO_MAX, "höchstens %d Stände vom Beenden (%d)" % [QR.AUTO_MAX, autos.size()])
	check(int((autos[0] as Dictionary).at) == 1300 and int((autos[2] as Dictionary).at) == 1100, "neuester vorn, der älteste ist gegangen")
	check(not FileAccess.file_exists(str(files[0][0])) and not FileAccess.file_exists(str(files[0][1])), "der verdrängte Stand: Uzais Kopie und Bild weg")
	check(int(QR.record(g, true).get("at", 0)) == 1300, "„Weiter, wo du warst“ nimmt den neuesten")
	QR.mark_stale(gid)
	check(QR.record(g, true).is_empty() and QR.states(g).size() == 3, "anders weitergespielt: nicht mehr vorn, aber alle Stände bleiben")
	QR.add(gid, { "emulator": "duckstation", "at": 1400, "file": _own("a_4.sav") })
	check(int(QR.record(g, true).get("at", 0)) == 1400, "neu gemerkt: wieder vorn")
	for i in QR.OWN_MAX:
		var r := QR.add(gid, { "emulator": "duckstation", "at": 2000 + i, "file": _own("o_%d.sav" % i) }, "own")
		if r.is_empty():
			check(false, "eigener Platz %d angelegt" % i)
	check(QR.own_full(gid) and QR.own_count(gid) == QR.OWN_MAX, "eigene Plätze: %d belegt, dann voll" % QR.OWN_MAX)
	check(QR.add(gid, { "emulator": "duckstation", "at": 3000, "file": _own("o_x.sav") }, "own").is_empty(), "voll ist voll: kein eigener Stand wird verdrängt")
	for i in 3:
		QR.add(gid, { "emulator": "duckstation", "at": 4000 + i, "file": _own("b_%d.sav" % i) })
	check(QR.states(g, "own").size() == QR.OWN_MAX and QR.states(g, "auto").size() == QR.AUTO_MAX, "neue automatische verdrängen nie eigene")
	check(int(QR.record(g, true).get("at", 0)) == 4002 and str(QR.record(g, true).get("kind", "")) == "auto", "„Weiter, wo du warst“ ist immer ein Stand vom Beenden")
	var own0: Dictionary = QR.states(g, "own")[0]
	QR.remove(gid, str(own0.id))
	check(QR.own_count(gid) == QR.OWN_MAX - 1 and not FileAccess.file_exists(str(own0.file)), "eigenen Stand entfernt: Platz wieder frei")
	var outside := _tmp("fremd").path_join("SLUS-1_1.sav")
	_touch(outside)
	QR.add(gid, { "emulator": "duckstation", "at": 5000, "file": outside }, "own")
	QR.remove(gid, str((QR.states(g, "own")[0] as Dictionary).id))
	check(FileAccess.file_exists(outside), "nie gelöscht: eine Datei außerhalb von Uzais Ablage")
	check(QR.is_own_file(Config.path(QR.DIR).path_join("x.sav")) and not QR.is_own_file(Config.path("quickresume_x/y.sav")) and not QR.is_own_file(""),
			"eigene Ablage genau erkannt (nicht „quickresume_x“)")
	var latest := QR.latest()
	check(latest.is_empty(), "Spiel nicht in der Bibliothek: nichts unter „Zuletzt“")


func _alte_form() -> void:
	print("Ablage aus der alten Form übernehmen")
	var f := _own("alt.sav")
	Config.write_json(Config.path(QR.INDEX), { "rom:alt:1": { "emulator": "duckstation", "at": 700, "file": f, "slot_file": "C:/x_1.sav", "title": "Alt" }, "kaputt": 5 })
	QR._idx_path = ""
	var g := { "id": "rom:alt:1", "source": "rom", "system": "ps1", "emulator": "duckstation", "path": "D:/alt.cue" }
	var st := QR.states(g)
	check(st.size() == 1 and str((st[0] as Dictionary).kind) == "auto" and str((st[0] as Dictionary).id) != "", "alter Stand wird zum Stand vom Beenden")
	check(int(QR.record(g, true).get("at", 0)) == 700, "und bleibt „Weiter, wo du warst“")
	check(not QR.index().has("kaputt"), "Unsinn in der Datei fällt weg")
	var d: Variant = Config.read_json(Config.path(QR.INDEX), {})
	check(d is Dictionary and ((d as Dictionary).get("rom:alt:1", {}) as Dictionary).has("states"), "neue Form gleich gespeichert")


func _retroarch_entry() -> void:
	print("RetroArch: Einstiegsdatei nur für den Start")
	var states := _tmp("ra/states")
	var slot := states.path_join("Spiel.state2")
	var old_entry := states.path_join("Spiel.state2.entry")
	_touch(old_entry, "alt-eintrag")
	Config.write_json(Config.path(QR.INDEX), { "rom:ra:1": { "emulator": "retroarch", "at": 800, "file": old_entry, "slot_file": slot, "slot": 2 } })
	QR._idx_path = ""
	var g := { "id": "rom:ra:1", "source": "rom", "system": "snes", "emulator": "retroarch", "path": "D:/Spiel.sfc" }
	var rec: Dictionary = QR.record(g, true)
	check(QR.is_own_file(str(rec.get("file", ""))) and FileAccess.get_file_as_string(str(rec.file)) == "alt-eintrag", "alte Einstiegsdatei: Kopie in Uzais Ablage")
	QR.cleanup_entries()
	check(not FileAccess.file_exists(old_entry), "nach dem Spiel: Einstiegsdatei bei RetroArch wieder weg")
	var rg := QR.resume_game(g, rec)
	check(str(rg.get("_resume_args", "")) == "-e 2" and FileAccess.get_file_as_string(old_entry) == "alt-eintrag", "Start: Kopie als Spiel.state2.entry, -e 2")
	QR.cleanup_entries()
	_touch(old_entry, "fremd")
	check(QR.resume_game(g, rec).is_empty() and FileAccess.get_file_as_string(old_entry) == "fremd", "fremde Einstiegsdatei am Platz: nicht anfassen, ohne Stand starten")
	DirAccess.remove_absolute(old_entry)


func _recover() -> void:
	print("Nach einem Absturz beim Sichern oder Laden")
	var dir := _tmp("emu_slots")
	var slot := dir.path_join("SLUS-1_1.sav")
	_touch(slot, "original")
	var bdir := Config.path(QR.DIR).path_join("sicherung")
	var backup := bdir.path_join("laden_SLUS-1_1.sav")
	_touch(backup, "original")
	_touch(slot, "uzais-stand")
	var fresh := dir.path_join("SLUS-1_2.sav")
	_touch(fresh, "1234")
	var kept := dir.path_join("SLUS-1_3.sav")
	_touch(kept, "der emulator hat inzwischen selbst gespeichert")
	QR.journal_put([{ "slot": slot, "backup": backup, "ours": -1 }, { "slot": fresh, "backup": "", "ours": 4 }, { "slot": kept, "backup": "", "ours": 4 }])
	QR._idx_path = ""
	check(QR.recover() == 2, "zwei Plätze wiederhergestellt")
	check(FileAccess.get_file_as_string(slot) == "original" and not FileAccess.file_exists(backup), "Platz wieder wie vorher, Sicherung aufgeräumt")
	check(not FileAccess.file_exists(fresh), "von Uzai eingesetzte Datei auf leerem Platz: wieder weg")
	check(FileAccess.file_exists(kept), "hat der Emulator selbst dorthin gespeichert (andere Größe): bleibt")
	check(QR.recover() == 0 and not QR.index().has("_offen"), "Auftrag erledigt: beim nächsten Start nichts mehr")
	# Ließ sich ein Platz im Spiel nicht zurücklegen (der Emulator hielt die Datei fest), bleibt die Sicherung liegen
	# und kommt beim nächsten Start zurück – aber nur, wenn der Emulator seitdem nicht selbst dorthin gespeichert hat.
	var p1 := dir.path_join("SLUS-2_1.sav")
	var b1 := bdir.path_join("0_SLUS-2_1.sav")
	_touch(p1, "uzais-stand")
	_touch(b1, "original")
	var p2 := dir.path_join("SLUS-2_2.sav")
	var b2 := bdir.path_join("1_SLUS-2_2.sav")
	_touch(p2, "inzwischen neu gespeichert")
	_touch(b2, "original")
	QR.journal_put([{ "slot": p1, "backup": b1, "ours": -1, "stand": FileAccess.get_modified_time(p1) },
		{ "slot": p2, "backup": b2, "ours": -1, "stand": FileAccess.get_modified_time(p2) - 60 }])
	QR._idx_path = ""
	check(QR.recover() == 1 and FileAccess.get_file_as_string(p1) == "original" and not FileAccess.file_exists(b1),
			"nicht zurückgelegter Platz: beim nächsten Start wieder wie vorher")
	check(FileAccess.get_file_as_string(p2) == "inzwischen neu gespeichert" and not FileAccess.file_exists(b2),
			"hat der Emulator seitdem dorthin gespeichert: sein neuerer Stand bleibt")
	var rsrc := FileAccess.get_file_as_string("res://src/core/rest.gd")
	check(not rsrc.contains("for b in backups.values():\n\t\tDirAccess.remove_absolute(str(b))") and rsrc.contains("_spaeter_zurueck(bleibt)"),
			"eine Sicherung wird nie gelöscht, bevor der Platz zurückgelegt ist")


func _rom_command() -> void:
	print("Start mit Ladeparametern")
	var dir := _tmp("emu")
	var exe := dir.path_join("duckstation.exe")
	var rom := dir.path_join("spiel.cue")
	_touch(exe)
	_touch(rom)
	Config.set_emulator("duckstation", "exe", exe)
	var g := { "id": "rom:t", "source": "rom", "system": "ps1", "emulator": "duckstation", "path": rom, "title": "T" }
	var plain: Dictionary = Launcher._rom_command(g)
	check(str(plain.get("args", "")).begins_with("-batch"), "ohne Fortsetzen: Parameter wie immer")
	var res: Dictionary = Launcher._rom_command(QR.resume_game(g, { "emulator": "duckstation", "file": "C:/q/a.sav" }))
	var args := str(res.get("args", ""))
	check(args.begins_with("-statefile ") and args.find("-statefile") < args.find("--"), "Fortsetzen: -statefile vor „--“ (%s)" % args)
	Config.set_emulator("duckstation", "exe", "")
	await get_tree().process_frame


func _anti_cheat() -> void:
	print("Anti-Cheat erkennen")
	check(Rest.anti_cheat_of(["Game.exe", "EasyAntiCheat"]) == "Easy Anti-Cheat", "Ordner EasyAntiCheat")
	check(Rest.anti_cheat_of(["start_protected_game.exe"]) == "Easy Anti-Cheat", "start_protected_game.exe")
	check(Rest.anti_cheat_of(["BEClient_x64.dll"]) == "BattlEye", "BattlEye")
	check(Rest.anti_cheat_of(["c:/riot games/valorant", "vgc.exe"]) == "Riot Vanguard", "Vanguard")
	check(Rest.anti_cheat_of(["EAAntiCheat.GameServiceLauncher.exe"]) == "EA Anti-Cheat", "EA Anti-Cheat vor dem allgemeinen Treffer")
	check(Rest.anti_cheat_of(["SomeAntiCheat.dll"]) == "Anti-Cheat", "allgemein: *anticheat*")
	check(Rest.anti_cheat_of(["game.exe", "data", "Engine"]) == "", "nichts gefunden")
	var root := _tmp("pcgame")
	_touch(root.path_join("Binaries/Win64/game.exe"))
	_touch(root.path_join("Binaries/Win64/EasyAntiCheat/Settings.json"))
	var names := Rest.folder_names(root)
	check(Rest.anti_cheat_of(names) == "Easy Anti-Cheat", "im Spielordner (zwei Ebenen tief) gefunden")
	var r = Rest.new()
	check(r.anti_cheat_for({ "id": "pc:1", "install_dir": root }) == "Easy Anti-Cheat", "je Spiel ermittelt")
	check(r.anti_cheat_for({ "id": "pc:2", "title": "VALORANT", "install_dir": "" }) == "Riot Vanguard", "Riot-Spiele: Vanguard liegt außerhalb")
	r.free()


func _policy() -> void:
	print("PC-Spiele anhalten?")
	check(Rest.online_only({ "genres": PackedStringArray(["Action", "Massively Multiplayer"]) }), "MMO: online")
	check(Rest.online_only({ "features": PackedStringArray(["Online-PvP"]) }), "nur Online-PvP: online")
	check(not Rest.online_only({ "features": PackedStringArray(["Einzelspieler", "Online-PvP"]) }), "mit Einzelspieler: nicht nur online")
	check(not Rest.online_only({}), "ohne Angaben: nicht online")
	var off := Rest.pc_policy("off", "", false)
	check(not bool(off.suspend), "Einstellung Aus: nie anhalten")
	var ac := Rest.pc_policy("safe", "BattlEye", false)
	check(not bool(ac.suspend) and str(ac.note).contains("BattlEye"), "Anti-Cheat: weiterlaufen und sagen, warum")
	var on := Rest.pc_policy("safe", "", true)
	check(not bool(on.suspend) and str(on.note).contains("Online"), "Online-Spiel: weiterlaufen")
	check(bool(Rest.pc_policy("safe", "", false).suspend), "offline ohne Anti-Cheat: anhalten")
	var a := Mixer.game_args(12, "C:/Games/X", 0)
	check(a.get("pids") == [12] and str(a.get("dir", "")) == "C:\\Games\\X" and not a.has("hwnd"), "Ton: Prozess und Ordner des Spiels")


func _sleep_gap() -> void:
	print("Aufwachen erkennen")
	check(not Rest.slept(2, 2.0, 20), "normaler Takt")
	check(not Rest.slept(22, 2.0, 20), "kurzes Stocken zählt nicht")
	check(Rest.slept(23, 2.0, 20), "mehr als 20 s Sprung: hat geschlafen")
	check(Rest.slept(3600, 2.0, 20), "eine Stunde Schlaf")


func _screen() -> void:
	print("Ruhe-Anzeige")
	var host := Control.new()
	U.full_rect(host)
	add_child(host)
	var fr := FakeRest.new()
	add_child(fr)
	var s = RestScreen.new()
	s.rest = fr
	s.game_title = "Gran Turismo"
	s.note = "Angehalten. Es geht genau dort weiter."
	s.open(host)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Nav.top_layer() == s, "liegt oben auf dem Stapel")
	check(not s.closable, "B schließt nicht einfach (weckt)")
	Nav._fire("b")
	Nav._fire("a")
	Nav._fire("down")
	check(fr.woke == 3, "B, A und Richtung wecken (%d)" % fr.woke)
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	s._on_click(ev)
	check(fr.woke == 4, "Klick weckt")
	s.close()
	await get_tree().create_timer(0.3).timeout
	host.queue_free()
	fr.queue_free()


func _enter_wake() -> void:
	print("Einschlafen und Aufwecken (ohne Helfer, ohne Spiel)")
	var host := Control.new()
	U.full_rect(host)
	add_child(host)
	var fm := FakeMain.new()
	fm.layer_host = host
	add_child(fm)
	var r = Rest.new()
	r.main = fm
	add_child(r)
	var keep := Nav.pad_unfocused
	await r.enter("test")
	await get_tree().process_frame
	await get_tree().process_frame
	check(r.active and fm.opened == 1, "Ruhemodus an, Anzeige offen")
	check(Nav.pad_unfocused, "jede Taste zählt, auch ohne Fensterfokus")
	r.enter("doppelt")
	check(fm.opened == 1, "zweites Halten öffnet nichts doppelt")
	Helper.pad_event.emit("pad-wake")
	await get_tree().create_timer(0.4).timeout
	check(not r.active, "Taste am Controller (Helfer) weckt")
	check(Nav.pad_unfocused == keep, "Controller-Fokus wieder wie vorher")
	check(Nav.top_layer() == null or Nav.top_layer().get_script() != RestScreen, "Anzeige zu")
	# Guide halten führt nur mit der Einstellung „Ruhemodus“ direkt hinein (Standard: Schnellmenü).
	Config.set_value("controller.guide_hold", "menu")
	r._woke_at = -100000
	Helper.pad_event.emit("guide-hold")
	await get_tree().process_frame
	check(not r.active, "Schnellmenü eingestellt: Halten schläft nicht ein (main öffnet das Schnellmenü)")
	Config.set_value("controller.guide_hold", "rest")
	r._woke_at = Time.get_ticks_msec()
	Helper.pad_event.emit("guide-hold")
	await get_tree().process_frame
	check(not r.active, "Guide gleich nach dem Wecken weiter gehalten: schläft nicht wieder ein")
	r._woke_at = -100000
	Helper.pad_event.emit("guide-hold")
	await get_tree().create_timer(0.2).timeout
	check(r.active, "Guide halten (Helfer) schläft ein")
	r.wake("test")
	await get_tree().create_timer(0.4).timeout
	check(not r.active, "wieder wach")
	# Gemerkter Stand mit Unsinn (eine Antwort des Helfers in falscher Form): Aufwachen geht trotzdem.
	await r.enter("test")
	r._st["pids"] = "kaputt"
	r._st["muted"] = true
	r._st["audio"] = null
	await r.wake("test")
	check(not r.active and not r._waking, "Unsinn im gemerkten Stand: trotzdem wach")
	# Und bricht das Aufwachen selbst mit einem Fehler ab, endet der Ruhemodus trotzdem (früher blieb Uzai bis zum
	# Neustart darin hängen). Die Fehlermeldung im Protokoll ist gewollt.
	await r.enter("test")
	r._st["screen"] = "ja"
	await r.wake("test")
	check(not r.active and not r._waking and r._st.is_empty() and Nav.pad_unfocused == keep, "Aufwachen bricht ab: der Ruhemodus endet trotzdem")
	check(Nav.top_layer() == null or Nav.top_layer().get_script() != RestScreen, "die Ruhe-Anzeige ist zu")
	# Stürzt Uzai ab, während ein Spiel angehalten ist (Guide offen, Ruhemodus), bliebe es für immer eingefroren.
	# Der Helfer merkt sich, was er angehalten hat, und setzt es fort, sobald Uzais Leitung zu ist.
	var hs := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(hs.contains("$script:Angehalten[[int]$a.pid] = $true") and hs.contains("$script:Angehalten.Remove([int]$a.pid)"),
			"Helfer: merkt sich angehaltene Prozesse und streicht fortgesetzte")
	check(hs.find("foreach ($p in @($script:Angehalten.Keys))") > hs.rfind("[Console]::In.ReadLine()"),
			"Helfer: setzt sie fort, wenn Uzai endet (nach der Befehlsschleife)")
	check(hs.contains("$script:Stumm = @{ pids") and hs.find("if ($script:Stumm) { try { [void][UzAudio]::AppMute(") > hs.rfind("[Console]::In.ReadLine()"),
			"Helfer: was der Ruhemodus stumm geschaltet hat, bekommt den Ton zurück, wenn Uzai endet")
	Config.set_value("controller.guide_hold", "aus")
	r._woke_at = -100000
	Helper.pad_event.emit("guide-hold")
	await get_tree().process_frame
	check(not r.active, "Einstellung aus: Halten tut nichts")
	Config.set_value("controller.guide_hold", "menu")
	r.queue_free()
	fm.queue_free()
	host.queue_free()

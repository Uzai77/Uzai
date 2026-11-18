extends Node
## Logik von Remote Play Together ohne Windows und ohne Steam: wann über den Spender gestartet
## wird, Auftragsdatei, Zustand und Reparatur der Dateien im Spender, Erkennung der
## Programmdatei (auch aus appinfo.vdf). Aufruf:
##   UZAI_DATA=<leer> godot --headless --path . res://tests/logic_remoteplay.tscn → „Ergebnis: alles ok“
## Die C#-Teile (Starter, Einladung) prüft tests/remoteplay_cs.ps1.

const RP := preload("res://src/core/remote_play.gd")
const PADS := preload("res://src/core/remote_play_pads.gd")
const CI := preload("res://src/core/call_invite.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Wann über den Spender")
	_wants()
	print("Auftragsdatei")
	_job()
	print("Dateien im Spender")
	_files()
	print("Programmdatei erkennen")
	_pick()
	print("appinfo.vdf")
	_appinfo()
	print("Rückmeldung des Starters")
	_status()
	print("Spieler 2 erkennen, Adminrechte")
	_pads_admin()
	print("INI-Bearbeitung")
	_ini()
	print("Spieler 2: PCSX2 und DuckStation")
	_ps()
	print("Spieler 2: Dolphin")
	_dolphin()
	print("Spieler 2: Eden und yuzu-Ableger")
	_yuzu()
	print("Spieler 2: Dateien und Rücksicherung")
	_pads_files()
	print("Alle im Discord-Call einladen")
	_call_invite()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _wants() -> void:
	var rom := { "source": "rom", "system": "ps2" }
	var pc := { "source": "pc", "path": "C:/Spiele/x.exe" }
	check(not RP.wants_for(rom, false, true), "Emulator-Spiel normal, solange die Einstellung aus ist")
	check(RP.wants_for(rom, true, true), "Emulator-Spiel über den Spender, wenn „immer“ an ist")
	check(not RP.wants_for(rom, true, false), "ohne eingerichteten Spender startet es normal")
	check(not RP.wants_for(pc, true, true), "„immer“ gilt nur für Emulator-Spiele")
	check(RP.wants_for({ "source": "pc", "_rp": true }, false, true), "„Mit Remote Play Together starten“ bei PC-Spiel")
	check(RP.wants_for({ "source": "rom", "_rp": true }, false, false), "ausdrücklich gewählt: auch ohne Spender (Uzai sagt dann, was fehlt)")
	check(not RP.wants_for({ "source": "steam", "_rp": true }, true, true), "Steam-Spiele nie über den Spender")
	check(RP.wants_for({ "source": "epic", "_rp": true }, false, true), "Epic-Spiel auf ausdrücklichen Wunsch (ohne Kopierschutz)")
	check(not RP.wants_for({ "source": "epic" }, true, true, true), "Epic-Spiele nie von selbst")
	check(RP.wants_for(pc, false, true, true), "„PC-Spiele immer“ startet PC-Spiele über den Spender")
	check(not RP.wants_for(pc, false, false, true), "… aber nicht ohne Spender")
	check(not RP.wants_for(rom, false, true, true), "„PC-Spiele immer“ gilt nicht für Emulator-Spiele")
	check(RP.possible_for({ "source": "epic" }), "Option auch bei Epic-Spielen")
	check(not RP.wants_for({ "source": "pc", "url": "com.epicgames.launcher://x", "_rp": true }, true, true), "Internet-Verknüpfungen nie")
	check(RP.possible_for(rom) and RP.possible_for(pc) and not RP.possible_for({ "source": "steam" }),
			"Option in den Spieloptionen nur bei Emulator- und PC-Spielen")
	# Steam zeigt beim Spender dessen Namen statt „Spielt Nicht-Steam-Spiel: …“: von selbst
	# (ohne „Mit Freund spielen“) geht nach der Umstellung nichts mehr darüber.
	check(bool(Config.get_value("remoteplay.default_v2", false)) and not bool(Config.get_value("remoteplay.emulators", true))
			and not bool(Config.get_value("remoteplay.pc", false)),
		"Standard nach der Umstellung: Emulator- und PC-Spiele starten normal")
	var lib_g := { "id": "rom:ygo", "source": "rom", "system": "ps1", "title": "Yu-Gi-Oh! Forbidden Memories" }
	var with_friend := lib_g.duplicate()
	with_friend["_rp"] = true
	check(RP.wants_for(with_friend, false, true) and not lib_g.has("_rp") and not RP.wants_for(lib_g, false, true),
		"„Mit Freund spielen“ gilt nur für diesen Start (der Eintrag der Bibliothek bleibt ohne Spender)")


func _job() -> void:
	var cmd := { "exe": "D:\\Emus\\PCSX2\\pcsx2-qt.exe", "dir": "D:\\Emus\\PCSX2", "args": "-fullscreen -- \"D:\\ROMs\\FIFA Street 2.iso\"",
		"env": { "PCSX2_X": "a=b", "BAD=NAME": "x" } }
	var t := RP.job_text("42", 1700000000, cmd)
	var kv := RP.parse_kv(t)
	check(str(kv.get("id")) == "42" and str(kv.get("zeit")) == "1700000000", "id und Zeit")
	check(str(kv.get("exe")) == cmd.exe and str(kv.get("dir")) == cmd.dir, "Programm und Ordner")
	check(str(kv.get("args")) == cmd.args, "Parameter mit Anführungszeichen bleiben gleich")
	check(kv.env == ["PCSX2_X=a=b"], "Umgebung: Werte mit = bleiben, ungültige Namen fallen weg")
	check(t.contains("\r\n") and t.begins_with("#"), "Windows-Zeilenenden, Kopfzeile als Kommentar")
	var nl := RP.parse_kv(RP.job_text("1", 1, { "exe": "a.exe", "args": "-x\n-y\r\nzeit=0" }))
	check(str(nl.get("args")) == "-x -y  zeit=0" and str(nl.get("zeit")) == "1", "Zeilenumbrüche in Parametern können keine Schlüssel unterschieben")
	var bom := RP.parse_kv("\ufeffid=7\nkaputt\n=leer\n")
	check(str(bom.get("id")) == "7" and bom.size() == 2, "BOM, Zeilen ohne = und ohne Schlüssel werden übergangen")


func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else "<fehlt>"


func _files() -> void:
	check(RP.state_of(true, true, true) == "bereit", "Starter + Sicherung: bereit")
	check(RP.state_of(true, false, false) == "nicht_eingerichtet", "nur Original: nicht eingerichtet")
	check(RP.state_of(true, true, false) == "ueberschrieben", "Original + Sicherung: Steam hat ersetzt")
	check(RP.state_of(false, true, false) == "starter_fehlt", "nur Sicherung: Starter fehlt")
	check(RP.state_of(true, false, true) == "ohne_original", "Starter ohne Sicherung")
	check(RP.state_of(false, false, false) == "fehlt", "nichts da")
	check(RP.original_path("C:/Steam/common/RetroArch/retroarch.exe") == "C:/Steam/common/RetroArch/retroarch.uzai-original.exe", "Name der Sicherung")

	var dir := Config.path("rptest/RetroArch")
	DirAccess.make_dir_recursive_absolute(dir)
	var exe := dir.path_join("retroarch.exe")
	var backup := RP.original_path(exe)
	var starter := Config.path("rptest/starter.exe")
	_write(starter, "MZ STARTER UzaiStarter v1")
	_write(exe, "ORIGINAL 1")
	check(RP.state(exe, starter) == "nicht_eingerichtet", "frischer Spender erkannt")
	check(RP.place(exe, starter) == "", "einrichten")
	check(_read(exe) == "MZ STARTER UzaiStarter v1" and _read(backup) == "ORIGINAL 1", "Starter an der Stelle, Original gesichert")
	check(RP.place(exe, starter) == "" and _read(backup) == "ORIGINAL 1", "zweimal einrichten ändert nichts")
	_write(exe, "ORIGINAL 2")
	check(RP.state(exe, starter) == "ueberschrieben", "Steam-Update erkannt")
	check(RP.place(exe, starter) == "" and _read(exe) == "MZ STARTER UzaiStarter v1" and _read(backup) == "ORIGINAL 2",
			"still neu angelegt, neues Original wird die Sicherung")
	DirAccess.remove_absolute(exe)
	check(RP.place(exe, starter) == "" and _read(exe) == "MZ STARTER UzaiStarter v1", "fehlender Starter wird ersetzt")
	_write(exe, "MZ alter Starter UzaiStarter v0")
	check(RP.state(exe, starter) == "bereit", "Starter einer älteren Uzai-Version wird erkannt (nie als Original)")
	check(RP.place(exe, starter) == "" and _read(exe) == "MZ STARTER UzaiStarter v1" and _read(backup) == "ORIGINAL 2",
			"alter Starter wird ausgetauscht, Sicherung bleibt")
	check(RP.bytes_contain("abcUzaiStarterx".to_ascii_buffer(), "UzaiStarter".to_ascii_buffer())
			and not RP.bytes_contain("UzaiStarte".to_ascii_buffer(), "UzaiStarter".to_ascii_buffer()), "Kennung in Bytes suchen")
	_write(dir.path_join(RP.JOB_FILE), "x")
	check(RP.restore(exe, starter) == "" and _read(exe) == "ORIGINAL 2" and not FileAccess.file_exists(backup),
			"rückgängig: Original zurück, keine Sicherung mehr")
	check(not FileAccess.file_exists(dir.path_join(RP.JOB_FILE)), "rückgängig räumt Auftrag und Status weg")
	RP.place(exe, starter)
	_write(exe, "ORIGINAL 3")
	check(RP.restore(exe, starter) == "" and _read(exe) == "ORIGINAL 3" and not FileAccess.file_exists(backup),
			"rückgängig nach Steam-Update: neue Datei bleibt, alte Sicherung weg")
	check(RP.place(dir.path_join("fehlt.exe"), starter) != "", "fehlende Programmdatei: Hinweis statt Absturz")
	check(RP.place(exe, Config.path("rptest/kein_starter.exe")) != "", "fehlender Starter: Hinweis")


func _pick() -> void:
	var ra := [{ "rel": "retroarch.exe", "size": 9000000 }, { "rel": "retroarch_angle.exe", "size": 9500000 },
		{ "rel": "unins000.exe", "size": 3000000 }, { "rel": "_CommonRedist/vcredist/vc_redist.x64.exe", "size": 25000000 }]
	var p := RP.pick_main_exe(ra, [], "RetroArch")
	check(str(p.rel) == "retroarch.exe" and p.sure, "Name passt zum Spiel (vor der größeren Datei)")
	check(not (p.candidates as Array).has("unins000.exe") and not (p.candidates as Array).has("_CommonRedist/vcredist/vc_redist.x64.exe"),
			"Deinstaller und Laufzeiten sind keine Kandidaten")
	var q := RP.pick_main_exe(ra, ["retroarch_angle.exe"], "RetroArch")
	check(str(q.rel) == "retroarch_angle.exe" and q.sure, "Steams Startoption (appinfo) hat Vorrang")
	var sub := RP.pick_main_exe([{ "rel": "Game/Binaries/Win64/Spiel-Win64-Shipping.exe", "size": 80000000 }, { "rel": "Spiel.exe", "size": 300000 }],
			["Game\\Binaries\\Win64\\Spiel-Win64-Shipping.exe"], "Ganz anders")
	check(str(sub.rel) == "Game/Binaries/Win64/Spiel-Win64-Shipping.exe", "Startoption mit Unterordner und Backslashes")
	var big := RP.pick_main_exe([{ "rel": "a.exe", "size": 10 }, { "rel": "b.exe", "size": 50 }], [], "Etwas")
	check(str(big.rel) == "b.exe" and not big.sure and (big.candidates as Array)[0] == "b.exe", "sonst die größte – Uzai fragt nach (größte oben)")
	var one := RP.pick_main_exe([{ "rel": "x.exe", "size": 10 }, { "rel": "UnityCrashHandler64.exe", "size": 999 }], [], "Etwas")
	check(str(one.rel) == "x.exe" and one.sure, "eine einzige echte Datei: sicher")
	var done := RP.pick_main_exe([{ "rel": "retroarch.exe", "size": 50000 }, { "rel": "retroarch.uzai-original.exe", "size": 9000000 }], [], "RetroArch")
	check(str(done.rel) == "retroarch.exe" and done.sure, "schon eingerichtet: die Datei mit Sicherung")
	var none := RP.pick_main_exe([{ "rel": "unins000.exe", "size": 1 }], [], "X")
	check(str(none.rel) == "", "keine Programmdatei: leer")
	# Echte Ordner auflisten
	var dir := Config.path("rptest/Spiel")
	DirAccess.make_dir_recursive_absolute(dir.path_join("bin"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("_CommonRedist"))
	_write(dir.path_join("bin/spiel.exe"), "12345")
	_write(dir.path_join("_CommonRedist/setup.exe"), "1")
	_write(dir.path_join("liesmich.txt"), "1")
	var list := RP.list_exes(dir)
	check(list.size() == 1 and str(list[0].rel) == "bin/spiel.exe" and int(list[0]["size"]) == 5, "Ordner auflisten (mit Größe, Laufzeit-Ordner übersprungen)")
	var det := RP.detect_exe({ "title": "Spiel", "install_dir": dir, "appid": 0 })
	check(str(det.get("exe")) == dir.path_join("bin/spiel.exe") and str(det.error) == "", "Erkennung liefert den vollen Pfad")
	check(str(RP.detect_exe({ "title": "Weg", "install_dir": dir.path_join("nicht_da") }).get("error", "")) != "", "fehlender Ordner: Hinweis")


## Kleines appinfo.vdf im Format 29 (Schlüssel als Nummern) mit drei Apps.
func _entry(appid: int, body: PackedByteArray) -> PackedByteArray:
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, appid)
	head.encode_u32(4, body.size())
	head.append_array(body)
	return head


func _vdf_string(key_index: int, value: String) -> PackedByteArray:
	var b := PackedByteArray([1, 0, 0, 0, 0])
	b.encode_u32(1, key_index)
	b.append_array(value.to_utf8_buffer())
	b.append(0)
	return b


func _appinfo() -> void:
	var meta := PackedByteArray()
	meta.resize(60)     # Zustand, Zeit, Token, Prüfsummen, Änderung
	var body := meta.duplicate()
	body.append_array(_vdf_string(65, "retroarch.exe"))
	body.append_array(_vdf_string(66, "windows"))
	body.append_array(_vdf_string(65, "retroarch.sh"))
	body.append_array(_vdf_string(65, "Tools\\helper.EXE"))
	body.append_array(_vdf_string(65, "retroarch.exe"))
	var other := meta.duplicate()
	other.append_array(_vdf_string(65, "falsch.exe"))
	var file := PackedByteArray()
	file.resize(16)
	file.encode_u32(0, 0x07564429)
	file.encode_u32(4, 1)
	file.encode_u64(8, 0)
	file.append_array(_entry(10, other))
	file.append_array(_entry(1118310, body))
	file.append_array(_entry(20, other))
	file.append_array(PackedByteArray([0, 0, 0, 0]))
	var p := Config.path("rptest/appinfo.vdf")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(file)
	f.close()
	var blob := RP.appinfo_entry(p, 1118310)
	check(blob.size() == body.size(), "Eintrag der App gefunden (über andere hinweg)")
	var exes := RP.exes_in_blob(blob)
	check(exes == ["retroarch.exe", "Tools\\helper.EXE"], "nur .exe, in Steams Reihenfolge, ohne Doppelte (%s)" % [exes])
	check(RP.appinfo_entry(p, 999).is_empty(), "unbekannte App: leer")
	var old := file.duplicate()
	old.encode_u32(0, 0x07564428)
	_write(p, "")
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(old.slice(0, 8) + old.slice(16))
	f.close()
	check(RP.appinfo_entry(p, 1118310).size() == body.size(), "auch Format 28 (ohne Schlüsseltabelle)")
	_write(p, "kein vdf, nur Text")
	check(RP.appinfo_entry(p, 1118310).is_empty(), "unlesbare Datei: leer statt Fehler")
	# Eine beschädigte Datei nennt eine Größe weit über ihr Ende hinaus: nichts anfordern, leer zurück.
	var riesig := file.slice(0, 16)
	riesig.resize(28)
	riesig.encode_u32(16, 1118310)
	riesig.encode_u32(20, 0xFFFFFFF0)
	f = FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(riesig)
	f.close()
	check(riesig.decode_u32(16) == 1118310 and RP.appinfo_entry(p, 1118310).is_empty(), "Größe über das Dateiende hinaus: leer, kein Speicher angefordert")
	var H = load("res://src/core/helper.gd")
	check(H.ps32_exe() == "" or H.ps32_exe().is_absolute_path(), "32-Bit-PowerShell nur mit vollem Pfad (sonst keins)")
	var quellen := FileAccess.get_file_as_string("res://src/core/remote_play.gd") + FileAccess.get_file_as_string("res://src/core/social.gd")
	check(not quellen.contains("SysWOW64") and quellen.count("Helper.ps32_exe()") == 2, "der Pfad dafür entsteht an einer Stelle")


func _status() -> void:
	var dir := Config.path("rptest/Spender")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("remoteplay.donor_exe", dir.path_join("retroarch.exe"))
	Config.set_value("remoteplay.donor_appid", 1118310)
	var id := RP.write_job({ "exe": "C:\\x.exe", "args": "-a", "dir": "C:\\" })
	var job := RP.parse_kv(_read(dir.path_join(RP.JOB_FILE)))
	check(id != "" and str(job.get("id")) == id and str(job.get("exe")) == "C:\\x.exe", "Auftrag liegt neben dem Starter")
	check(absi(int(str(job.get("zeit"))) - int(Time.get_unix_time_from_system())) < 5, "Zeit in Sekunden seit 1970 (wie im Starter)")
	check(RP.read_status(id).is_empty(), "noch keine Rückmeldung")
	_write(dir.path_join(RP.STATUS_FILE), "id=alt\r\npid=99\r\nzustand=laeuft\r\n")
	check(RP.read_status(id).is_empty(), "Rückmeldung eines alten Auftrags zählt nicht")
	_write(dir.path_join(RP.STATUS_FILE), "id=%s\r\npid=4242\r\nzustand=laeuft\r\nfehler=\r\n" % id)
	check(int(RP.read_status(id).get("pid", "0")) == 4242, "Spielprozess aus der Rückmeldung")
	RP.clear_job()
	check(not FileAccess.file_exists(dir.path_join(RP.JOB_FILE)), "Auftrag zurückziehen")
	check(RP.configured() and RP.wants({ "source": "rom", "_rp": true }), "eingerichtet erkannt")
	check(RP.overlay_hint("Grund.").contains("Umschalt+Tab") and RP.overlay_hint("Grund.").contains("Guide → „Steam-Overlay“"),
			"Rückfall nennt das Steam-Overlay (Guide oder Tasten)")
	Config.set_value("remoteplay.donor_exe", "")
	Config.set_value("remoteplay.donor_appid", 0)


func _pads_admin() -> void:
	check(RP.pad_change(-1, -1, 2) == "", "ohne Ausgangswert keine Meldung")
	check(RP.pad_change(1, 1, 2) == "verbunden", "ein Controller mehr als beim Start: verbunden")
	check(RP.pad_change(1, 2, 2) == "", "gleich wie zuletzt: nichts")
	check(RP.pad_change(1, 2, 1) == "getrennt", "wieder so viele wie beim Start: getrennt")
	check(RP.pad_change(2, 2, 1) == "", "eigener Controller weg (unter dem Start): keine Meldung über Spieler 2")
	check(RP.pad_change(1, 2, 3) == "verbunden", "noch ein Gast: wieder verbunden")
	check(RP.pad_change(1, 1, -1) == "", "unbekannt: nichts")
	check(not RP.pad_hint_due(0, 1000, 1, 1, false), "ohne Einladung kein Hinweis")
	check(not RP.pad_hint_due(1000, 1060, 1, 1, false), "vor 90 s kein Hinweis")
	check(RP.pad_hint_due(1000, 1095, 1, 1, false), "nach 90 s ohne zweiten Controller: Hinweis")
	check(not RP.pad_hint_due(1000, 1095, 1, 1, true), "Hinweis nur einmal")
	check(not RP.pad_hint_due(1000, 1095, 1, 2, false), "Controller ist da: kein Hinweis")
	check(RP.admin_problem("x.exe", "", false) == "", "keine Adminrechte nötig: kein Problem")
	check(RP.admin_problem("x.exe", "manifest", true) == "", "Steam läuft als Admin: geht")
	check(RP.admin_problem("x.exe", "kompat", false).contains("Kompatibilität"), "Kompatibilität: sagt, wo man es ausschaltet")
	check(RP.admin_problem("x.exe", "manifest", false).contains("Steam als Administrator"), "Manifest: sagt, dass Steam Adminrechte braucht")


func _ini() -> void:
	var t := "; Kopf\r\n[A]\r\nx = 1\r\ny = 2\r\n\r\n[B]\r\nz = 3\r\n"
	check(str(PADS.ini_get(t, "A", "y")) == "2" and PADS.ini_get(t, "A", "q") == null and PADS.ini_get(t, "C", "x") == null, "Werte lesen, fehlende sind null")
	var t2 := PADS.ini_set(t, "A", "y", "5")
	check(t2 == t.replace("y = 2", "y = 5"), "Wert ändern, Rest bleibt Zeichen für Zeichen (CRLF, Leerzeile, Kommentar)")
	var t3 := PADS.ini_set(t, "A", "w", "7")
	check(str(PADS.ini_get(t3, "A", "w")) == "7" and t3.contains("w = 7\r\n\r\n[B]"), "neuer Schlüssel vor der Leerzeile")
	check(PADS.ini_set(t3, "A", "w", null) == t, "Schlüssel wieder weg: wie vorher")
	var t4 := PADS.set_section(t, "C", ["k = v"])
	check(t4.ends_with("z = 3\r\n\r\n[C]\r\nk = v\r\n"), "neuer Abschnitt am Ende")
	check(PADS.set_section(t4, "C", null) == t, "Abschnitt wieder entfernen: wie vorher")
	var q := "[Controls]\nplayer_0_a=1\n"
	check(PADS.ini_set(q, "Controls", "player_1_a", "2") == "[Controls]\nplayer_0_a=1\nplayer_1_a=2\n", "Qt-Schreibweise ohne Leerzeichen bleibt")
	# Viele Schlüssel in einem Zug (oeffnen, setzen, fertig): Byte für Byte dasselbe wie ini_set nacheinander.
	var faelle := [
		[t, "A", [["y", "5"], ["w", "7"], ["x", "0"], ["w", "8"]]],                             # CRLF, „a = b“, neuer Schlüssel vor der Leerzeile
		[q, "Controls", [["player_1_a", "2"], ["player_0_a", "9"], ["player_2_a", "3"]]],     # Qt-Schreibweise
		["[A]\nk=1\nk=2\nm=3\nk=4\n\n\n[B]\nz=1\n", "A", [["m", "5"], ["k", "9"], ["neu", "1"]]],  # doppelter Schlüssel: nur der erste bleibt
		["[A]\nx = 1", "C", [["k", "v"], ["l", "w"]]],                                           # Abschnitt fehlt, Datei ohne Zeilenende
		["frei = 1\n\n[A]\nx = 1\n", "", [["frei", "2"], ["dazu", "3"]]],                     # Teil vor dem ersten Abschnitt
		["", "A", [["k", "v"]]],
	]
	var alle_gleich := true
	for fall: Array in faelle:
		var alt := str(fall[0])
		var doc := PADS.oeffnen(str(fall[0]), str(fall[1]))
		for paar: Array in fall[2]:
			alt = PADS.ini_set(alt, str(fall[1]), str(paar[0]), str(paar[1]))
			PADS.setzen(doc, str(paar[0]), str(paar[1]))
			if str(PADS.wert(doc, str(paar[0]))) != str(paar[1]):
				alle_gleich = false
		if PADS.fertig(doc) != alt:
			alle_gleich = false
			print("    anders: ", str(fall[0]).c_escape())
	check(alle_gleich, "in einem Zug geändert: dasselbe Ergebnis wie Schlüssel für Schlüssel")
	var nichts := PADS.oeffnen("[A]\r\nx=1", "A")
	check(str(PADS.wert(nichts, "x")) == "1" and PADS.wert(nichts, "y") == null and PADS.geaendert(nichts) == 0 and PADS.fertig(nichts) == "[A]\r\nx=1",
			"nur gelesen: Der Text bleibt Zeichen für Zeichen, wie er war")
	check(PADS.shift_binding("SDL-0/A") == "SDL-1/A" and PADS.shift_binding("XInput-1/+LeftTrigger") == "XInput-2/+LeftTrigger", "Belegung: nächstes Gerät")
	check(PADS.shift_binding("SDL-0/LeftShoulder & SDL-0/A") == "SDL-1/LeftShoulder & SDL-1/A", "Akkorde")
	check(PADS.shift_binding("Keyboard/W") == "" and PADS.shift_binding("SDL-0/A & Keyboard/W") == "", "Tastatur fällt weg")


const PCSX2_INI := "[UI]\r\nTheme = darkfusion\r\n\r\n[Pad1]\r\nType = DualShock2\r\nInvertL = 0\r\nDeadzone = 0.1\r\nUp = SDL-0/DPadUp\r\nUp = Keyboard/Up\r\nCross = SDL-0/A\r\nL2 = SDL-0/+LeftTrigger\r\nLLeft = SDL-0/-LeftX\r\nSmallMotor = SDL-0/SmallMotor\r\n\r\n[Pad2]\r\nType = None\r\n\r\n[Hotkeys]\r\nToggleFullscreen = Keyboard/Alt & Keyboard/Return\r\n"


func _ps() -> void:
	var plan := PADS.plan_ps(PCSX2_INI, "DualShock2", 1)
	var t := str(plan.text)
	var p2: Array = PADS.section_lines(t, "Pad2")
	check(str(PADS.lines_get(p2, "Type")) == "DualShock2", "Spieler 2 eingesteckt (Typ wie Spieler 1)")
	check(str(PADS.lines_get(p2, "Up")) == "SDL-1/DPadUp" and str(PADS.lines_get(p2, "L2")) == "SDL-1/+LeftTrigger", "Belegung auf den zweiten Controller")
	check(not t.contains("Up = Keyboard/Up\r\nCross = SDL-1"), "Tastatur von Spieler 1 nicht übernommen")
	check(p2.filter(func(l): return str(l).contains("Keyboard")).is_empty(), "keine Tastatur bei Spieler 2")
	check(str(PADS.lines_get(p2, "Deadzone")) == "0.1", "Einstellungen wie Totzone übernommen")
	check(str(PADS.ini_get(t, "UI", "Theme")) == "darkfusion" and str(PADS.ini_get(t, "Hotkeys", "ToggleFullscreen")) == "Keyboard/Alt & Keyboard/Return",
			"andere Abschnitte bleiben")
	check(PADS.section_lines(t, "Pad1") == PADS.section_lines(PCSX2_INI, "Pad1"), "Spieler 1 bleibt unverändert")
	check(PADS.undo_text(t, plan) == PCSX2_INI, "Rücksicherung ergibt genau die alte Datei")
	# Schon selbst belegt: nichts anfassen.
	var own := PADS.set_section(PCSX2_INI, "Pad2", ["Type = DualShock2", "Cross = SDL-1/B"])
	check(PADS.plan_ps(own, "DualShock2", 1).is_empty(), "eigene Belegung für Spieler 2 bleibt")
	var off := PADS.set_section(PCSX2_INI, "Pad2", ["Type = None", "Cross = SDL-1/B"])
	var po := PADS.plan_ps(off, "DualShock2", 1)
	check(str(PADS.ini_get(str(po.text), "Pad2", "Type")) == "DualShock2" and str(PADS.ini_get(str(po.text), "Pad2", "Cross")) == "SDL-1/B",
			"eigene Belegung, aber ausgesteckt: nur einstecken")
	check(PADS.undo_text(str(po.text), po) == off, "… und danach wieder ausstecken")
	# Spieler 1 nur auf der Tastatur.
	var kb := "[Pad1]\nType = DualShock2\nCross = Keyboard/X\n"
	var pk := PADS.plan_ps(kb, "DualShock2", 0)
	check(str(PADS.ini_get(str(pk.text), "Pad2", "Cross")) == "SDL-0/A" and str(PADS.ini_get(str(pk.text), "Pad2", "R2")) == "SDL-0/+RightTrigger",
			"Spieler 1 auf Tastatur: Spieler 2 bekommt den ersten Controller mit Standardbelegung")
	# DuckStation: Pad2 fehlt ganz, Typ AnalogController.
	var ds := "[Main]\nSettingsVersion = 3\n\n[Pad1]\nType = AnalogController\nCross = SDL-0/A\nAnalog = SDL-0/Guide\n"
	var pd := PADS.plan_ps(ds, "AnalogController", 1)
	check(str(PADS.ini_get(str(pd.text), "Pad2", "Type")) == "AnalogController" and str(PADS.ini_get(str(pd.text), "Pad2", "Analog")) == "SDL-1/Guide",
			"DuckStation: Pad2 neu angelegt")
	check(PADS.undo_text(str(pd.text), pd) == ds, "DuckStation: Rücksicherung entfernt Pad2 wieder")
	# Während des Spiels selbst umbelegt: bleibt.
	var changed := PADS.ini_set(str(plan.text), "Pad2", "Cross", "SDL-1/B")
	check(str(PADS.ini_get(PADS.undo_text(changed, plan), "Pad2", "Cross")) == "SDL-1/B", "selbst geänderte Belegung wird nicht zurückgestellt")


const GC_INI := "[GCPad1]\nDevice = XInput/0/Gamepad\nButtons/A = `Button A`\nButtons/B = `Button B`\nMain Stick/Up = `Left Y+`\n[GCPad2]\nDevice = \n[GCPad3]\nDevice = \n"


func _dolphin() -> void:
	var g := PADS.plan_gc(GC_INI, 1)
	var p2: Array = PADS.section_lines(str(g.text), "GCPad2")
	check(str(PADS.lines_get(p2, "Device")) == "XInput/1/Gamepad" and str(PADS.lines_get(p2, "Buttons/A")) == "`Button A`",
			"GameCube: Spieler 2 auf XInput/1 mit gleicher Belegung")
	check(PADS.section_lines(str(g.text), "GCPad3") == PADS.section_lines(GC_INI, "GCPad3"), "Spieler 3 bleibt")
	check(PADS.undo_text(str(g.text), g) == GC_INI, "Rücksicherung")
	var sdl := "[GCPad1]\nDevice = SDL/0/Xbox Series X Controller\nButtons/A = `Button S`\n"
	var gs := PADS.plan_gc(sdl, 0)
	var s2: Array = PADS.section_lines(str(gs.text), "GCPad2")
	check(str(PADS.lines_get(s2, "Device")) == "XInput/0/Gamepad" and str(PADS.lines_get(s2, "Triggers/L")) == "`Trigger L`",
			"Spieler 1 über SDL: Spieler 2 als nächster XInput-Controller mit Standardbelegung")
	check(PADS.plan_gc("[GCPad2]\nDevice = XInput/1/Gamepad\nButtons/A = `Button A`\n", 1).is_empty(), "eigene Belegung bleibt")
	var core := "[Core]\nSIDevice0 = 6\nSIDevice1 = 0\nCPUThread = True\n"
	var c := PADS.plan_dolphin_ini(core)
	check(str(PADS.ini_get(str(c.text), "Core", "SIDevice1")) == "6" and PADS.undo_text(str(c.text), c) == core,
			"Anschluss 2: Standard-Controller, danach wieder aus")
	check(PADS.plan_dolphin_ini("[Core]\nSIDevice1 = 12\n").is_empty(), "WiiU-Adapter an Anschluss 2 bleibt")
	var c2 := PADS.plan_dolphin_ini("[Core]\nCPUThread = True\n")
	check(str(PADS.ini_get(str(c2.text), "Core", "SIDevice1")) == "6" and PADS.ini_get(PADS.undo_text(str(c2.text), c2), "Core", "SIDevice1") == null,
			"fehlender Schlüssel: gesetzt und danach wieder entfernt")
	var wii := "[Wiimote1]\nDevice = XInput/0/Gamepad\nSource = 1\nButtons/A = `Button A`\nExtension = Nunchuk\n[Wiimote2]\nSource = 0\n"
	var w := PADS.plan_wii(wii)
	var w2: Array = PADS.section_lines(str(w.text), "Wiimote2")
	check(str(PADS.lines_get(w2, "Device")) == "XInput/1/Gamepad" and str(PADS.lines_get(w2, "Source")) == "1"
			and str(PADS.lines_get(w2, "Extension")) == "Nunchuk", "Wii: zweite emulierte Wiimote wie Spieler 1")
	check(PADS.undo_text(str(w.text), w) == wii, "Wii: Rücksicherung")
	check(str(PADS.plan_wii("[Wiimote1]\nSource = 2\n").get("note", "")).contains("echte"), "echte Wiimotes: nichts ändern, Hinweis")
	check(str(PADS.plan_wii("[Wiimote1]\nDevice = DInput/0/Keyboard Mouse\nSource = 1\n").get("note", "")) != "", "Wiimote auf Tastatur: Hinweis statt Unsinn")


const QT := "[Controls]\nplayer_0_type\\default=true\nplayer_0_type=0\nplayer_0_connected=true\nplayer_0_button_a\\default=false\nplayer_0_button_a=\"engine:sdl,port:0,guid:030000005e040000e002000000007801,button:1\"\nplayer_0_lstick=\"engine:sdl,port:0,guid:030000005e040000e002000000007801,axis_x:0,axis_y:1,deadzone:0.150000\"\nplayer_0_motionleft=\"engine:keyboard,code:55\"\nplayer_1_connected\\default=true\nplayer_1_connected=false\n\n[System]\nuse_docked_mode=1\n"


func _yuzu() -> void:
	var y := PADS.plan_yuzu(QT)
	var t := str(y.text)
	check(str(PADS.ini_get(t, "Controls", "player_1_connected")) == "true" and str(PADS.ini_get(t, "Controls", "player_1_connected\\default")) == "false",
			"Spieler 2 eingesteckt")
	check(str(PADS.ini_get(t, "Controls", "player_1_button_a")) == "\"engine:sdl,port:1,guid:030000005e040000e002000000007801,button:1\"",
			"Taste auf port 1, gleicher Controller-Typ")
	check(str(PADS.ini_get(t, "Controls", "player_1_lstick")).contains("port:1,")
			and str(PADS.ini_get(t, "Controls", "player_1_lstick")).contains("deadzone:0.150000"), "Stick mit Totzone")
	check(str(PADS.ini_get(t, "Controls", "player_1_button_a\\default")) == "false", "„nicht Standard“-Merker mitkopiert")
	check(PADS.ini_get(t, "Controls", "player_1_motionleft") == null, "Tastatur-Belegungen nicht kopiert")
	check(str(PADS.ini_get(t, "Controls", "player_0_button_a")).contains("port:0"), "Spieler 1 bleibt")
	check(str(PADS.ini_get(t, "System", "use_docked_mode")) == "1", "anderer Abschnitt bleibt")
	check(PADS.undo_text(t, y) == QT, "Rücksicherung ergibt genau die alte Datei")
	check(PADS.plan_yuzu(QT.replace("player_1_connected=false", "player_1_connected=true")).is_empty(), "Spieler 2 schon eingesteckt: nichts tun")
	var hh := PADS.plan_yuzu(QT.replace("player_0_type=0", "player_0_type=4"))
	check(str(PADS.ini_get(str(hh.text), "Controls", "player_1_type")) == "0" and str(PADS.ini_get(str(hh.text), "Controls", "player_0_type")) == "4",
			"Handheld: Spieler 2 als Pro Controller, Spieler 1 bleibt")
	check(str(PADS.plan_yuzu("[UI]\nx=1\n").get("note", "")) != "", "ohne Steuerung: Hinweis")
	check(str(PADS.plan_yuzu("[Controls]\nplayer_0_button_a=\"engine:keyboard,code:65\"\nplayer_1_connected=false\n").get("note", "")).contains("Tastatur"),
			"Spieler 1 auf Tastatur: Hinweis")


func _pads_files() -> void:
	check(PADS.kind_of("pcsx2", "") == "pcsx2" and PADS.kind_of("eigen_1", "D:/Emus/PCSX2/pcsx2-qt.exe") == "pcsx2", "Emulator nach Kennung oder Dateiname")
	check(PADS.kind_of("custom", "D:/Eden/eden.exe") == "eden" and PADS.kind_of("x", "D:/a/Dolphin.exe") == "dolphin", "eigene Einträge für Eden und Dolphin")
	var c := PADS.candidates("pcsx2", "D:/PCSX2", "C:/Users/u/Documents", "C:/Users/u/AppData/Roaming", "C:/Users/u/AppData/Local", false)
	check(c.ini[0] == "C:/Users/u/Documents/PCSX2/inis/PCSX2.ini", "PCSX2: Dokumente")
	check(PADS.candidates("pcsx2", "D:/PCSX2", "", "", "", true).ini == ["D:/PCSX2/inis/PCSX2.ini"], "PCSX2 tragbar: neben dem Programm")
	check(PADS.candidates("eden", "D:/Eden", "", "C:/R", "", false).ini[0] == "C:/R/eden/config/qt-config.ini", "Eden: AppData")
	check(PADS.candidates("dolphin", "D:/Dolphin", "", "", "", true).gc == ["D:/Dolphin/User/Config/GCPadNew.ini"], "Dolphin tragbar: User-Ordner")
	check(PADS.candidates("mgba", "D:/mGBA", "", "", "", false).is_empty(), "mGBA: nichts zu tun")
	check(PADS.support_text("mgba", "gba").contains("nur einen Spieler"), "GBA: ehrlich, ein Spieler am Gerät")
	check(PADS.support_text("retroarch", "snes").contains("von selbst"), "RetroArch: Spieler 2 von selbst")
	check(PADS.support_text("pcsx2", "ps2").contains("zurück"), "PCSX2: Uzai belegt und stellt zurück")
	# Ganzer Ablauf mit echten Dateien in einem tragbaren PCSX2-Ordner.
	var dir := Config.path("rp-test/PCSX2")
	DirAccess.make_dir_recursive_absolute(dir.path_join("inis"))
	_write(dir.path_join("portable.ini"), "")
	_write(dir.path_join("inis/PCSX2.ini"), PCSX2_INI)
	# Wie im Betrieb: Der Emulator ist eingetragen (nur unter seinen Ordnern darf die Rückstellung schreiben).
	var emus_alt: Variant = Config.get_value("emulators", {})
	Config.set_value("emulators.pcsx2.exe", dir.path_join("pcsx2-qt.exe"))
	var r := PADS.prepare("pcsx2", dir.path_join("pcsx2-qt.exe"), "ps2", 1, 1)
	check((r.done as Array).size() == 1, "Datei für die Sitzung geändert")
	check(str(PADS.ini_get(_read(dir.path_join("inis/PCSX2.ini")), "Pad2", "Cross")) == "SDL-1/A", "Spieler 2 steht in der Datei")
	check((Config.get_value(PADS.RESTORE_KEY, []) as Array).size() == 1, "Rücksicherung gemerkt (übersteht einen Absturz)")
	PADS.restore_all()
	check(_read(dir.path_join("inis/PCSX2.ini")) == PCSX2_INI, "nach dem Spiel: Datei wie vorher")
	check((Config.get_value(PADS.RESTORE_KEY, []) as Array).is_empty(), "Rücksicherung erledigt")
	# Präparierte Rückstellung (etwa aus einer fremden Sicherung): fremde Datei, Vorspann-Abschnitt, Freigabe – nichts
	# wird angefasst.
	var fremd := Config.path("rp-test/fremd.txt")
	_write(fremd, "wichtig\n")
	_write(dir.path_join("inis/PCSX2.ini"), "vorn=1\n[Pad1]\nType = DualShock2\n")
	Config.set_value(PADS.RESTORE_KEY, [
		{ "file": fremd, "sections": { "": { "new": [], "old": ["boese"] } } },
		{ "file": dir.path_join("inis/PCSX2.ini"), "sections": { "": { "new": [], "old": ["boese"] } } },
		{ "file": "\\\\203.0.113.5\\x\\PCSX2.ini", "keys": [{ "section": "Pad1", "key": "Type", "old": "x", "new": "DualShock2" }] }])
	PADS.restore_all()
	check(_read(fremd) == "wichtig\n" and _read(dir.path_join("inis/PCSX2.ini")) == "vorn=1\n[Pad1]\nType = DualShock2\n",
			"präparierte Rückstellung: fremde Datei, Vorspann und Freigabe bleiben unberührt")
	check(not PADS.rueck_ok(fremd) and not PADS.rueck_ok("\\\\203.0.113.5\\x\\PCSX2.ini") and PADS.rueck_ok(dir.path_join("inis/PCSX2.ini")),
			"Rückstellung nur für bekannte Dateien unter dem Ordner des Emulators")
	Config.set_value("emulators", emus_alt)
	var g := PADS.prepare("mgba", "D:/mGBA/mGBA.exe", "gba", 1, 1)
	check((g.done as Array).is_empty() and str(g.note) == "", "GBA: nichts geändert")


func _call_invite() -> void:
	# Namen vergleichen
	check(CI.fold("PixelPaul") == "pixel paul" and CI.fold("pixel_paul") == "pixel paul" and CI.fold("pixel.paul") == "pixel paul",
			"Groß/klein, CamelCase und Trennzeichen egal")
	check(CI.fold("Mïra  Müller") == "mira muller" and CI.fold("Ōkami ★") == "okami", "Akzente und Zeichen fallen weg")
	check(CI.fold("Kai99") == "kai 99" and CI.tokens("Kai99") == PackedStringArray(["kai"]), "Zahlen trennen und zählen nicht als Wort")
	check(CI.levenshtein("kitten", "sitting") == 3 and CI.levenshtein("", "abc") == 3 and CI.levenshtein("x", "x") == 0, "Levenshtein")
	check(CI.name_score("Mira", "mira") == 1.0 and CI.name_score("Jöns", "jons") == 1.0, "gleich nach dem Vereinfachen: 1")
	check(CI.name_score("Mira", "Mira Müller") >= 0.85, "gleiches Wort im Namen (Mira ↔ Mira Müller)")
	check(CI.name_score("pixelpaul", "Paul") >= 0.65, "Teilname (paul in pixelpaul)")
	check(CI.name_score("pixelpaul", "Paul Berger") >= CI.MIN_SCORE and CI.name_score("pixelpaul", "Paul Berger") < CI.SURE,
			"Wort im Namen (Paul Berger ↔ pixelpaul): Vorschlag, nicht sicher")
	check(CI.name_score("Jonas", "Jonsa") >= 0.55 and CI.name_score("Jonas", "Jonsa") < 0.86, "Tippfehler: Vorschlag, aber nicht sicher")
	check(CI.name_score("Sana", "Ben") < CI.MIN_SCORE and CI.name_score("", "Ben") == 0.0, "fremde Namen passen nicht")
	var friends := [
		{ "id": "76561190000000001", "name": "Mira", "state": "online" },
		{ "id": "76561190000000002", "name": "Jonas K.", "state": "online" },
		{ "id": "76561190000000003", "name": "xX_Paule_Xx", "real": "Paul Berger", "state": "online" },
		{ "id": "76561190000000004", "name": "Kai", "state": "offline" },
		{ "id": "76561190000000005", "name": "Kaito", "state": "online" },
		{ "id": "76561190000000009", "name": "Ich", "state": "online" },
	]
	var paul := { "id": "1", "name": "pixelpaul", "username": "paul.berger" }
	var sp := CI.suggest(paul, friends)
	check(not sp.is_empty() and str(sp[0].id) == "76561190000000003", "Klarname zählt: paul.berger ↔ Paul Berger")
	check(CI.sure(sp), "eindeutiger Vorschlag gilt als gewählt")
	var kai := CI.suggest({ "id": "2", "name": "Kai" }, friends)
	check(kai.size() >= 2 and str(kai[0].id) == "76561190000000004" and str(kai[1].id) == "76561190000000005", "Kai vor Kaito, beide vorgeschlagen")
	check(CI.suggest({ "id": "9", "name": "Sana" }, friends).is_empty(), "kein Vorschlag ohne Ähnlichkeit")
	check(CI.suggest({ "id": "1", "name": "a" }, friends, 3).size() <= 3, "höchstens drei Vorschläge")
	check(not CI.sure([{ "score": 0.9 }, { "score": 0.88 }]), "zwei fast gleich gute: nachfragen")
	# Zuordnungen
	var map := CI.map_set({}, "1", "76561190000000003", "pixelpaul", "xX_Paule_Xx", 100)
	check(CI.map_steam(map, "1") == "76561190000000003" and CI.map_steam(map, "2") == "", "Zuordnung merken und lesen")
	var map2 := CI.map_set(map, "2", "76561190000000004", "Kai", "Kai")
	check(map.size() == 1 and map2.size() == 2, "map_set ändert die alte Zuordnung nicht")
	check(CI.map_remove(map2, "1").size() == 1 and CI.map_set(map2, "2", "").size() == 1, "Zuordnung entfernen")
	var raw := { "1": "76561190000000003", "2": { "steam": "76561190000000004", "discord_name": "Kai" }, "3": { "steam": "" }, "4": 5 }
	var clean := CI.clean_map(raw)
	check(clean.size() == 2 and CI.map_steam(clean, "1") == "76561190000000003" and CI.clean_map("kaputt").is_empty(),
			"von Hand geänderte Einträge: gültige bleiben")
	var rows := CI.map_rows(map2, friends)
	check(rows.size() == 2 and str(rows[0].discord_name) == "Kai" and str(rows[1].steam_name) == "xX_Paule_Xx", "Liste für die Einstellungen, nach Namen")
	var before: Variant = Config.get_value(CI.MAP_KEY, null)
	CI.remember("77", "76561190000000001", "Mira", "Mira")
	check(CI.map_steam(CI.load_map(), "77") == "76561190000000001", "in der Uzai-Konfiguration gespeichert")
	CI.forget("77")
	check(CI.map_steam(CI.load_map(), "77") == "", "und wieder vergessen")
	Config.set_value(CI.MAP_KEY, before if before != null else {})
	# Wen einladen
	var members := [
		{ "id": "4", "name": "Ich", "me": true },
		{ "id": "1", "name": "pixelpaul", "username": "paul.berger" },
		{ "id": "2", "name": "Kai" },
		{ "id": "3", "name": "Mira" },
		{ "id": "5", "name": "Sana" },
		{ "id": "6", "name": "MEE6", "bot": true },
		{ "id": "7", "name": "Zweitkonto" },
	]
	var m := CI.map_set({}, "2", "76561190000000004", "Kai", "Kai")
	m = CI.map_set(m, "7", "76561190000000009", "Zweitkonto", "Ich")
	var plan := CI.build_plan(members, m, {}, friends, "4", "76561190000000009", ["76561190000000001"])
	var st := {}
	for r in plan.rows:
		st[str(r.id)] = str(r.status)
	check(int(plan.self) == 2 and not st.has("4") and not st.has("7"), "du selbst nicht – auch nicht über ein zugeordnetes Zweitkonto")
	check(not st.has("6"), "Bots nicht")
	check(st.get("3") == "joined", "Mira ist schon in der Sitzung: nicht nochmal")
	check(st.get("2") == "invite" and st.get("1") == "invite", "zugeordnet und sicherer Vorschlag: einladen")
	check(st.get("5") == "unmapped", "ohne Zuordnung und ohne Vorschlag: nachfragen")
	check((plan.invite as Array).size() == 2 and int(plan.guests) == 3, "zwei Einladungen, drei Gäste")
	var p2 := CI.build_plan(members, m, { "2": "", "5": "76561190000000002" }, friends, "4", "76561190000000009", [])
	var st2 := {}
	for r in p2.rows:
		st2[str(r.id)] = r
	check(str(st2["2"].status) == "excluded" and str(st2["5"].status) == "invite" and str(st2["5"].how) == "choice",
			"Wahl für diesmal geht vor (Nicht einladen, anderer Freund)")
	check(str(st2["5"].steam_name) == "Jonas K.", "Steam-Name zur Wahl")
	var p3 := CI.build_plan([{ "id": "1", "name": "A" }, { "id": "2", "name": "B" }],
			CI.map_set(CI.map_set({}, "1", "76561190000000001"), "2", "76561190000000001"), {}, friends, "", "", [])
	check(str(p3.rows[1].status) == "duplicate" and (p3.invite as Array).size() == 1, "zwei Discord-Konten, ein Steam-Freund: einmal einladen")
	var p4 := CI.build_plan([{ "id": "1", "name": "A" }], CI.map_set({}, "1", "76561199999999999"), {}, friends, "", "", [])
	check(str(p4.rows[0].status) == "not_friend", "zugeordnet, aber nicht (mehr) befreundet: erklären statt einladen")
	var p5 := CI.build_plan([{ "id": "1", "name": "A" }], CI.map_set({}, "1", "76561199999999999"), {}, [], "", "", [])
	check(str(p5.rows[0].status) == "invite", "Freundesliste unbekannt: trotzdem einladen")
	check(CI.limit_warning(3) == "" and CI.limit_warning(4).contains("4 Spieler"), "Hinweis ab dem vierten Gast")
	# Ergebnis und Mitteilung
	var done := CI.apply_result(plan.rows, { "ok": true, "joined": ["76561190000000001"], "results": {
		"76561190000000003": { "ok": true, "skipped": "", "reason": "" }, "76561190000000004": { "ok": false, "skipped": "", "reason": "abgelehnt" } } })
	var sd := {}
	for r in done:
		sd[str(r.id)] = r
	check(str(sd["1"].status) == "invited" and str(sd["2"].status) == "failed" and str(sd["2"].reason) == "abgelehnt",
			"je Person: eingeladen oder Fehler mit Grund")
	check(CI.summary(done) == "1 eingeladen: pixelpaul · 1 schon dabei · 1 ging nicht · 1 ohne Steam-Zuordnung", "Mitteilung: " + CI.summary(done))
	var three := [{ "name": "Paul", "status": "invited" }, { "name": "Mira", "status": "invited" }, { "name": "Kai", "status": "invited" },
			{ "name": "Sana", "status": "unmapped" }]
	check(CI.summary(three) == "3 eingeladen: Paul, Mira, Kai · 1 ohne Steam-Zuordnung", "Mitteilung wie besprochen")
	check(CI.summary([{ "name": "A", "status": "not_friend" }, { "name": "B", "status": "not_friend" }]) == "Niemand eingeladen · 2 keine Steam-Freunde",
			"niemand eingeladen")
	check(CI.explain([{ "name": "Sana", "status": "unmapped" }]).contains("Steam-Freunde") and CI.explain([{ "name": "A", "status": "invite" }]) == "",
			"Erklärung nur, wenn jemand fehlt")

extends Node
## Spieler & Controller ohne Windows: Zuordnung (Automatik, selbst zugeordnet, tauschen, entfernen),
## Geräte je Emulator, die Konfig-Schreiber mit Beispiel-Dateien und „fehlende Belegung“ je Emulator
## (leer, Tastatur-Standard, kaputt aus 0.13.0, eigene funktionierende – was geschrieben wird, was
## bleibt). Aufruf:
##   UZAI_DATA=<leer> godot --headless --path . res://tests/logic_spieler.tscn → „Ergebnis: alles ok“

const S := preload("res://src/core/spieler.gd")
const E := preload("res://src/core/spieler_emus.gd")
const Ini := preload("res://src/core/remote_play_pads.gd")

const G_XBOX := "030000005e040000130b000000007200"
const G_DS := "030000004c050000e60c000000006800"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Kennungen")
	_ids()
	print("Zuordnung")
	_assign()
	print("Geräte je Emulator")
	_players()
	print("DuckStation und PCSX2")
	_ps()
	print("Dolphin")
	_dolphin()
	print("RetroArch")
	_retroarch()
	print("Eden & Co.")
	_yuzu()
	print("Spieler 3 und 4: Multitap, Eden ab Spieler 2")
	_mehr_spieler()
	print("Dateien")
	_files()
	print("Nach 0.13.0: Originale zurück, ein Controller bleibt unberührt")
	_zurueck()
	print("Fehlende Belegung: Geräte")
	_f_geraete()
	print("Fehlende Belegung: PCSX2")
	_f_pcsx2()
	print("Fehlende Belegung: DuckStation")
	_f_duckstation()
	print("Fehlende Belegung: Dolphin")
	_f_dolphin()
	print("Fehlende Belegung: RetroArch, PPSSPP, Eden")
	_f_andere()
	print("Fehlende Belegung: Dateien und launch.log")
	_f_dateien()
	print("Zwei bis vier Controller (Xbox, DualSense, Switch Pro gemischt)")
	_f_viele()
	print("Start: Spieler 1 = der Controller, mit dem gestartet wurde")
	_s_wer()
	print("Start: PCSX2/DuckStation – Gerät wechselt auch bei vorhandener Belegung")
	_s_ps()
	print("Start: Dolphin und RetroArch")
	_s_andere()
	print("Start: die richtige Einstellungsdatei")
	_s_dateien()
	print("Start: Disc vom Laufwerk und alle Startwege")
	_s_wege()
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _pads() -> Array:
	return [
		{ "key": "x0", "device": 0, "guid": G_XBOX, "name": "Xbox Wireless Controller", "xinput": 0, "player": 0, "family": "xbox" },
		{ "key": "j1", "device": 1, "guid": G_DS, "name": "PS5 Controller", "xinput": -1, "player": -1, "family": "ps" },
		{ "key": "x1", "device": 2, "guid": G_XBOX.to_upper(), "name": "Xbox Wireless Controller", "xinput": 1, "player": 1, "family": "xbox" },
	]


func _ids() -> void:
	var ids := S.ids_for(_pads())
	check(str(ids[0].id) == G_XBOX + "#0" and str(ids[2].id) == G_XBOX + "#1", "gleiche GUID: der wievielte zählt")
	check(int(ids[2].port) == 1 and int(ids[1].port) == 0, "port je Bauart")
	check(S.clean_guid("../../etc") == "" and S.clean_guid(G_XBOX) == G_XBOX, "GUID nur aus 32 Hex-Zeichen")
	var demo := S.ids_for([{ "key": "x0", "device": -1, "guid": "" }])
	check(str(demo[0].id) == "k:x0", "ohne GUID: Schlüssel aus Pads")


func _assign() -> void:
	var a := S.auto_fill([], ["A", "B"], {})
	check(a == ["A", "B", "", ""], "Automatik: der Reihe nach")
	a = S.auto_fill(a, ["A", "B", "C"], {})
	check(a == ["A", "B", "C", ""], "neuer Controller: nächster freier Platz")
	a = S.auto_fill(a, ["A", "C"], {})
	check(a == ["A", "", "C", ""], "weg: Platz wird frei, die anderen bleiben")
	check(S.auto_fill(a, ["A", "C"], {}, false) == ["A", "", "C", ""], "ohne Automatik bleibt es")
	check(S.auto_fill([], ["A", "B"], {}, false) == ["", "", "", ""], "ohne Automatik: neue bekommen keinen Platz")
	# Selbst zuordnen
	var r := S.assign(["A", "B", "", ""], {}, "B", 1)
	check(r.slots == ["B", "A", "", ""] and int(r.mem.B) == 1 and int(r.mem.A) == 2, "zuordnen auf belegten Platz: tauschen")
	r = S.assign(["A", "", "", ""], {}, "C", 1)
	check(r.slots == ["C", "A", "", ""], "neuer auf Platz 1: der bisherige rückt auf den nächsten freien")
	# Gemerkt: B kommt wieder und bekommt Platz 4 zurück, auch wenn es anders verbunden wird.
	var mem := { "B": 4 }
	check(S.auto_fill([], ["B", "A"], mem) == ["A", "", "", "B"], "gemerkter Platz kommt zurück")
	check(S.auto_fill(["", "", "", "A"], ["A", "B"], mem) == ["A", "", "", "B"], "gemerkt verdrängt einen automatischen")
	check(S.auto_fill(["", "", "", "A"], ["A", "B"], { "A": 4, "B": 4 }) == ["B", "", "", "A"], "zwei gemerkt auf einem Platz: wer sitzt, bleibt")
	# Tauschen, entfernen
	r = S.swap(["A", "B", "C", ""], {}, 1, 3)
	check(r.slots == ["C", "B", "A", ""] and int(r.mem.C) == 1 and int(r.mem.A) == 3, "tauschen merkt beide")
	r = S.remove(["A", "B", "", ""], {}, 2)
	check(r.slots == ["A", "", "", ""] and int(r.mem.B) == 0, "entfernen")
	check(S.auto_fill(r.slots, ["A", "B"], r.mem) == ["A", "", "", ""], "entfernt: Automatik setzt ihn nicht wieder hin")
	r = S.assign(r.slots, r.mem, "B", 3)
	check(r.slots == ["A", "", "B", ""], "entfernt, dann selbst zugeordnet: geht wieder")
	check(S.norm_slots(["A", 3, null]) == ["A", "", "", ""] and S.norm_mem({ "A": 9, "B": 2, 5: 1 }) == { "B": 2 }, "fremde Werte aus der Config")


func _players() -> void:
	var p := _pads()
	var ids := S.ids_for(p)
	var pl := S.players([str(ids[1].id), str(ids[2].id), str(ids[0].id), ""], p)
	check(int(pl[0].sdl) == 2 and int(pl[1].sdl) == 1 and int(pl[2].sdl) == 0, "SDL-Nummern: Spieler-Nummer, sonst die nächste freie")
	check(int(pl[0].ra) == 2 and int(pl[1].ra) == 1 and int(pl[2].ra) == 0, "RetroArch: erst XInput-Anschlüsse, dann die übrigen")
	check(int(pl[1].dolphin_n) == 1 and int(pl[2].dolphin_n) == 0, "Dolphin: der wievielte mit diesem Namen")
	check((pl[3] as Dictionary).is_empty(), "freier Platz: leer")
	check(E.dolphin_device(pl[0]) == "SDL/0/PS5 Controller" and E.dolphin_device(pl[1]) == "XInput/1/Gamepad", "Dolphin-Gerät")


func _pl(sdl: int, xi := -1, name := "Xbox Wireless Controller", guid := G_XBOX, port := 0, ra := -1, dn := 0) -> Dictionary:
	return { "id": "x", "name": name, "guid": guid, "port": port, "sdl": sdl, "xinput": xi, "ra": ra if ra >= 0 else sdl, "dolphin_n": dn }


const PCSX2 := "[UI]\r\nTheme = darkfusion\r\n\r\n[Pad1]\r\nType = DualShock2\r\nDeadzone = 0.1\r\nUp = SDL-0/DPadUp\r\nUp = Keyboard/Up\r\nCross = SDL-0/A\r\nL2 = SDL-0/+LeftTrigger\r\n\r\n[Pad2]\r\nType = None\r\n\r\n[Hotkeys]\r\nToggleFullscreen = Keyboard/Alt & Keyboard/Return\r\n"


func _ps() -> void:
	check(E.retarget("SDL-0/A", "SDL-3") == "SDL-3/A" and E.retarget("Keyboard/Alt & XInput-0/A", "XInput-2") == "Keyboard/Alt & XInput-2/A", "Gerät tauschen")
	check(E.retarget("DInput-0/Button1", "SDL-1") == "", "DInput: eigene Tastennamen – nicht übernehmen")
	var r := E.plan_ps(PCSX2, "DualShock2", [_pl(2), _pl(0), {}, {}])
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Pad1", "Cross")) == "SDL-2/A" and str(Ini.ini_get(t, "Pad1", "Deadzone")) == "0.1", "Spieler 1: eigene Belegung, neues Gerät")
	var p1: Array = Ini.section_lines(t, "Pad1")
	check(p1.has("Up = Keyboard/Up") and p1.has("Up = SDL-2/DPadUp"), "Tastatur-Belegung bleibt neben dem Controller")
	check(str(Ini.ini_get(t, "Pad2", "Type")) == "DualShock2" and str(Ini.ini_get(t, "Pad2", "R2")) == "SDL-0/+RightTrigger", "Spieler 2: übliche Belegung")
	check(Ini.section_lines(t, "Hotkeys") == Ini.section_lines(PCSX2, "Hotkeys") and t.contains("Theme = darkfusion\r\n"),
			"fremde Abschnitte bleiben, CRLF bleibt")
	check(r.done == [1, 2] and str(r.note) == "", "eingerichtet: Spieler 1 und 2")
	check(str(E.plan_ps(t, "DualShock2", [_pl(2), _pl(0), {}, {}]).text) == t, "zweimal: nichts ändert sich")
	var r3 := E.plan_ps(PCSX2, "DualShock2", [_pl(0), {}, _pl(1), {}])
	check(str(Ini.ini_get(str(r3.text), "Pad", "MultitapPort1")) == "true" and str(Ini.ini_get(str(r3.text), "Pad4", "Cross")) == "SDL-1/A"
			and Ini.ini_get(str(r3.text), "Pad2", "Type") == "None" and str(r3.mt) == "an" and r3.done.has(3),
			"Spieler 3: Multitap an, Spieler 3 auf 1C ([Pad4]), Spieler 2 frei bleibt, wie er ist")
	var ds := "[Main]\nSettingsVersion = 3\n\n[Pad1]\nType = AnalogController\nCross = XInput-0/A\n"
	var rd := E.plan_ps(ds, "AnalogController", [_pl(1, 1), {}, {}, {}])
	check(str(Ini.ini_get(str(rd.text), "Pad1", "Cross")) == "XInput-1/A", "DuckStation mit XInput: XInput-Anschluss")


const GC := "[GCPad1]\nDevice = XInput/0/Gamepad\nButtons/A = `Button A`\nButtons/B = `Button B`\nMain Stick/Dead Zone = 15.0\n[GCPad2]\nDevice = DInput/0/Keyboard Mouse\nButtons/A = `X`\n"


func _dolphin() -> void:
	var r := E.plan_gc(GC, [_pl(1, 1), _pl(0, -1, "PS5 Controller"), {}, {}])
	var t := str(r.text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/1/Gamepad" and str(Ini.ini_get(t, "GCPad1", "Main Stick/Dead Zone")) == "15.0",
			"GC Spieler 1: eigene Belegung, nächster XInput-Anschluss")
	check(str(Ini.ini_get(t, "GCPad2", "Device")) == "SDL/0/PS5 Controller" and str(Ini.ini_get(t, "GCPad2", "Buttons/A")) == "`Button A`"
			and str(Ini.ini_get(t, "GCPad2", "Main Stick/Up")) == "`Left Y+`" and str(Ini.ini_get(t, "GCPad2", "Triggers/L")) == "`Trigger L`",
			"GC Spieler 2: SDL-Gerät mit XInput-Namen (Dolphins SDL-Teil nimmt sie, Y+ = oben)")
	check(Ini.section_lines(t, "GCPad3") == null, "freie Spieler: kein neuer Abschnitt")
	var core := "[General]\nISOPath0 = C:/Spiele\n[Core]\nSIDevice0 = 6\nSIDevice1 = 0\nSIDevice2 = 12\n"
	var c := str(E.plan_dolphin_ini(core, [_pl(0), _pl(1), _pl(2), {}]).text)
	check(str(Ini.ini_get(c, "Core", "SIDevice1")) == "6" and str(Ini.ini_get(c, "Core", "SIDevice2")) == "12", "SIDevice: einstecken, Bongos bleiben")
	check(Ini.ini_get(c, "Core", "SIDevice3") == null and str(Ini.ini_get(c, "General", "ISOPath0")) == "C:/Spiele", "sonst nichts")
	var wii := "[Wiimote1]\nSource = 1\nDevice = XInput/0/Gamepad\nButtons/A = `Button A`\nIR/Up = `Right Y+`\n[Wiimote2]\nSource = 2\n"
	var w := E.plan_wii(wii, [_pl(1, 1), _pl(0, 0), _pl(3, -1, "PS5 Controller"), {}])
	var wt := str(w.text)
	check(str(Ini.ini_get(wt, "Wiimote1", "Device")) == "XInput/1/Gamepad", "Wii Spieler 1: Gerät getauscht")
	check(str(Ini.ini_get(wt, "Wiimote2", "Source")) == "2", "echte Wiimote bleibt")
	check(str(Ini.ini_get(wt, "Wiimote3", "Device")) == "SDL/0/PS5 Controller" and str(Ini.ini_get(wt, "Wiimote3", "Extension")) == "Nunchuk"
			and str(w.note) == "", "ohne Vorlage für das Gerät: übliche Wiimote mit Nunchuk")


func _retroarch() -> void:
	var cfg := "video_driver = \"d3d11\"\ninput_joypad_driver = \"xinput\"\ninput_player1_joypad_index = \"0\"\ninput_player2_joypad_index = \"1\"\n"
	var r := E.plan_retroarch(cfg, [_pl(1, 1, "", G_XBOX, 0, 1), {}, {}, {}], 2)
	var t := str(r.text)
	check(str(Ini.ini_get(t, "", "input_player1_joypad_index")) == "\"1\"", "Spieler 1 auf Gerät 1")
	check(str(Ini.ini_get(t, "", "input_player2_joypad_index")) == "\"4\"", "freier Spieler 2 säße auf demselben Gerät: unbenutzte Nummer")
	check(Ini.ini_get(t, "", "input_player3_joypad_index") == null and t.begins_with("video_driver = \"d3d11\"\n"), "sonst nichts")
	var sdl := "input_joypad_driver = \"sdl2\"\n"
	check(str(Ini.ini_get(str(E.plan_retroarch(sdl, [_pl(3, 1, "", G_XBOX, 0, 1), {}, {}, {}], 4).text), "", "input_player1_joypad_index")) == "\"3\"",
			"SDL-Treiber: SDL-Nummer")


const QT := "[UI]\ntheme=default\n\n[Controls]\nplayer_0_type=0\nplayer_0_connected=true\nplayer_0_button_a=\"engine:sdl,port:0,guid:030000005e040000130b000000007200,button:1\"\nplayer_0_button_a\\default=false\nplayer_0_lstick=\"engine:sdl,port:0,guid:030000005e040000130b000000007200,axis_x:0,axis_y:1\"\nplayer_1_type=0\nplayer_1_connected=false\nplayer_1_connected\\default=true\nplayer_1_button_a=\"engine:keyboard,code:67\"\n"


func _yuzu() -> void:
	var r := E.plan_yuzu(QT, [_pl(0, -1, "PS5 Controller", G_DS, 0), _pl(0, 0, "X", G_XBOX, 1), {}, {}])
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Controls", "player_0_button_a")).contains("guid:" + G_DS)
			and str(Ini.ini_get(t, "Controls", "player_0_button_a")).contains("port:0"),
			"Spieler 1: GUID und port des zugeordneten Controllers")
	check(str(Ini.ini_get(t, "Controls", "player_1_button_a")).contains("port:1,guid:" + G_XBOX), "Spieler 2: Belegung von Spieler 1 übernommen")
	check(str(Ini.ini_get(t, "Controls", "player_1_connected")) == "true" and str(Ini.ini_get(t, "Controls", "player_1_connected\\default")) == "false",
			"Spieler 2 eingesteckt")
	check(str(Ini.ini_get(t, "UI", "theme")) == "default" and r.done == [1, 2], "fremde Abschnitte bleiben")
	check(str(E.plan_yuzu("[UI]\n", [_pl(0), {}, {}, {}]).note) != "", "ohne [Controls]: Hinweis")


func _files() -> void:
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	var emu := root.path_join("emu_test/DuckStation")
	DirAccess.make_dir_recursive_absolute(emu)
	# Wie im Betrieb: Der Emulator ist eingetragen – nur unter seinen Ordnern stellt restore_all zurück (RR-07).
	var emus_alt: Variant = Config.get_value("emulators", {})
	Config.set_value("emulators.duckstation.exe", emu.path_join("duckstation-qt-x64-ReleaseLTCG.exe"))
	FileAccess.open(emu.path_join("portable.txt"), FileAccess.WRITE).close()
	var ini := emu.path_join("settings.ini")
	var orig := "[Main]\nSettingsVersion = 3\n\n[Pad1]\nType = AnalogController\nCross = SDL-0/A\n"
	var f := FileAccess.open(ini, FileAccess.WRITE)
	f.store_string(orig)
	f.close()
	var env := { "docs": root.path_join("nirgends_docs"), "appdata": root.path_join("nirgends_app"), "localappdata": root.path_join("nirgends_local") }
	check(E.path_ok(ini, [emu]) and not E.path_ok(emu.path_join("../DuckStation/settings.ini"), [emu]), "Pfad: kein „..“")
	check(not E.path_ok(ini, [root.path_join("anderswo")]) and not E.path_ok(emu.path_join("portable.txt"), [emu]), "Pfad: nur im Ordner, nur bekannte Namen")
	var res := E.apply("duckstation", emu.path_join("duckstation-qt-x64-ReleaseLTCG.exe"), "ps1", [_pl(1), {}, {}, {}], 2, env)
	check((res.files as Array).size() == 1 and str(Ini.ini_get(FileAccess.get_file_as_string(ini), "Pad1", "Cross")) == "SDL-1/A", "geschrieben")
	check(E.has_backups() and not FileAccess.file_exists(ini + ".uzai-neu"), "Original gesichert, keine halbe Datei übrig")
	E.apply("duckstation", emu.path_join("duckstation-qt-x64-ReleaseLTCG.exe"), "ps1", [_pl(3), {}, {}, {}], 4, env)
	check(E.restore_all() == 1 and FileAccess.get_file_as_string(ini) == orig, "Original zurückgeholt (das vom ersten Mal)")
	# Dateien, die kein sauberes UTF-8 sind, fasst Uzai nicht an: Godot ersetzt solche Zeichen beim Lesen (gemessen),
	# und Uzai schriebe die Datei kaputt zurück – etwa einen Pfad mit „ü“ in einer alten Kodierung.
	var latin := "[Main]\nPfad = C:/Users/J".to_ascii_buffer()
	latin.append(0xFC)
	latin.append_array("rgen\n\n[Pad1]\nType = AnalogController\nCross = SDL-0/A\n".to_ascii_buffer())
	f = FileAccess.open(ini, FileAccess.WRITE)
	f.store_buffer(latin)
	f.close()
	check(not bool(Ini.lesen_treu(ini).ok), "Datei in anderer Zeichenkodierung: erkannt (die Fehlerzeile von Godot dazu ist gewollt)")
	var fremd := E.apply("duckstation", emu.path_join("duckstation-qt-x64-ReleaseLTCG.exe"), "ps1", [_pl(1), {}, {}, {}], 2, env)
	check((fremd.files as Array).is_empty() and FileAccess.get_file_as_bytes(ini) == latin and str(fremd.note).contains("Zeichenkodierung"),
			"… und bleibt Byte für Byte, wie sie ist")
	var mit_null := "[Pad1]\nCross = SDL-0/A\n".to_ascii_buffer()
	mit_null.append(0)
	mit_null.append_array("Rest\n".to_ascii_buffer())
	f = FileAccess.open(ini, FileAccess.WRITE)
	f.store_buffer(mit_null)
	f.close()
	check(not bool(Ini.lesen_treu(ini).ok), "Datei mit Nullbyte: nicht anfassen (Godot läse nur bis dorthin)")
	# Die UTF-8-Marke am Anfang (PPSSPP schreibt sie) bleibt erhalten; Godot lässt sie beim Lesen weg.
	var mit_marke := PackedByteArray([0xEF, 0xBB, 0xBF])
	mit_marke.append_array("[Main]\nName = Jürgen\n\n[Pad1]\nType = AnalogController\nCross = SDL-0/A\n".to_utf8_buffer())
	f = FileAccess.open(ini, FileAccess.WRITE)
	f.store_buffer(mit_marke)
	f.close()
	var treu := Ini.lesen_treu(ini)
	check(bool(treu.ok) and bool(treu.bom) and str(treu.text).begins_with("[Main]"), "Datei mit UTF-8-Marke: lesbar, Marke gemerkt")
	E.apply("duckstation", emu.path_join("duckstation-qt-x64-ReleaseLTCG.exe"), "ps1", [_pl(1), {}, {}, {}], 2, env)
	var danach := FileAccess.get_file_as_bytes(ini)
	check(danach.slice(0, 3) == PackedByteArray([0xEF, 0xBB, 0xBF]) and danach.get_string_from_utf8().contains("Name = Jürgen")
			and str(Ini.ini_get(danach.slice(3).get_string_from_utf8(), "Pad1", "Cross")) == "SDL-1/A", "geschrieben mit Marke, Umlaute unversehrt")
	E.restore_all()
	var none := E.apply("pcsx2", root.path_join("emu_test/PCSX2/pcsx2-qt.exe"), "ps2", [_pl(1), {}, {}, {}], 2, env)
	check((none.files as Array).is_empty() and str(none.note).contains("nicht gefunden"), "ohne Datei: nichts anlegen, Hinweis")
	check(E.describe("ppsspp").contains("Ein Spieler") and not E.supported("ppsspp") and E.kind_of("eigen_1", "C:/x/PPSSPPWindows64.exe") == "ppsspp",
			"PPSSPP: ein Spieler, keine Datei")
	Config.set_value("emulators", emus_alt)


func _zurueck() -> void:
	# Ein von 0.13.0 umgeschriebenes pcsx2.ini und sein Original in Uzais Ablage.
	var dir := OS.get_user_data_dir().path_join("zurueck_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var ini := dir.path_join("PCSX2.ini")
	var f := FileAccess.open(ini, FileAccess.WRITE)
	f.store_string("[Pad1]\nCross = SDL-3/A\n")
	f.close()
	var orig := FileAccess.open(dir.path_join("orig.ini"), FileAccess.WRITE)
	orig.store_string(PCSX2)
	orig.close()
	Config.set_value(E.KEY_ZURUECK, false)
	Config.set_value(E.KEY_ZURUECK2, false)
	Config.set_value(S.KEY_EMUS, null)
	(Config.settings.get("spieler", {}) as Dictionary).erase("emulatoren")
	DirAccess.make_dir_recursive_absolute(Config.path(E.BACKUP_DIR))
	var name := E.backup_name("pcsx2", ini)
	DirAccess.copy_absolute(dir.path_join("orig.ini"), Config.path(E.BACKUP_DIR).path_join(name))
	Config.set_value(E.KEY_BACKUPS, { name: ini })
	E.einmal_zurueck()
	check(FileAccess.get_file_as_string(ini) == PCSX2 and not E.has_backups(), "nicht selbst eingeschaltet: Original zurück")
	E.einmal_zurueck()
	check(bool(Config.get_value(E.KEY_ZURUECK, false)), "nur einmal")
	# Zweite Runde: erste schon gelaufen, Schalter selbst ausgeschaltet – trotzdem zurück.
	f = FileAccess.open(ini, FileAccess.WRITE)
	f.store_string("[Pad1]\nCross = SDL-3/A\n")
	f.close()
	DirAccess.copy_absolute(dir.path_join("orig.ini"), Config.path(E.BACKUP_DIR).path_join(name))
	Config.set_value(E.KEY_BACKUPS, { name: ini })
	Config.set_value(E.KEY_ZURUECK, true)
	Config.set_value(E.KEY_ZURUECK2, false)
	Config.set_value(S.KEY_EMUS, false)
	E.einmal_zurueck()
	check(FileAccess.get_file_as_string(ini) == PCSX2, "selbst ausgeschaltet: Original auch zurück (zweite Runde)")
	# Selbst eingeschaltet: bleibt, wie es ist.
	f = FileAccess.open(ini, FileAccess.WRITE)
	f.store_string("[Pad1]\nCross = SDL-3/A\n")
	f.close()
	DirAccess.copy_absolute(dir.path_join("orig.ini"), Config.path(E.BACKUP_DIR).path_join(name))
	Config.set_value(E.KEY_BACKUPS, { name: ini })
	Config.set_value(E.KEY_ZURUECK2, false)
	Config.set_value(S.KEY_EMUS, true)
	E.einmal_zurueck()
	check(FileAccess.get_file_as_string(ini) != PCSX2 and E.has_backups(), "selbst eingeschaltet: nichts zurückgelegt")
	Config.set_value(S.KEY_EMUS, null)
	(Config.settings.get("spieler", {}) as Dictionary).erase("emulatoren")
	E.restore_all()
	check(not bool(Config.get_value(S.KEY_EMUS, false)), "„Vor jedem Start einrichten“ von Haus aus aus")
	check(bool(Config.get_value(S.KEY_FEHLEND, true)), "„Fehlende Belegung automatisch“ von Haus aus an")
	var src := (load("res://src/core/spieler_emus.gd") as GDScript).source_code
	check(src.contains("KEY_EMUS, false)) and belegt >= 2 and supported(kind):"), "nach Uzais Zuordnung umschreiben nur ab zwei Spielern und nur auf Wunsch")


# --- Fehlende Belegung (Standard): je Emulator leer, Tastatur, kaputt, eigene ------------------------

## Was angeschlossen ist, wie geraete() es liefert.
func _g(xi: Array, sdl: Array, fam: Array, sicher := true) -> Dictionary:
	return { "n": maxi(xi.size(), 1) if not fam.is_empty() else 0, "xi": xi, "xi_sicher": sicher, "sdl": sdl, "familien": fam }


const XBOX0 := { "id": "x", "name": "Xbox Wireless Controller", "guid": G_XBOX, "port": 0, "sdl": 0, "xinput": 0, "ra": 0, "dolphin_n": 0, "family": "xbox" }
const DS0 := { "id": "d", "name": "DualSense", "sdl_name": "DualSense Wireless Controller", "guid": G_DS, "port": 0, "sdl": 0, "xinput": -1,
	"ra": 0, "dolphin_n": 0, "family": "ps" }

## So liefert PCSX2 2.x [Pad1] aus: nur Tastatur.
const PCSX2_STD := "[UI]\nSettingsVersion = 1\n\n[InputSources]\nKeyboard = true\nSDL = true\nXInput = false\n\n[Pad1]\nType = DualShock2\nDeadzone = 0\nAxisScale = 1.33\nUp = Keyboard/Up\nRight = Keyboard/Right\nDown = Keyboard/Down\nLeft = Keyboard/Left\nTriangle = Keyboard/I\nCircle = Keyboard/L\nCross = Keyboard/K\nSquare = Keyboard/J\nStart = Keyboard/Return\nLUp = Keyboard/W\nLDown = Keyboard/S\n\n[Pad2]\nType = None\n\n[Hotkeys]\nToggleFullscreen = Keyboard/Alt & Keyboard/Return\n"


func _f_geraete() -> void:
	var g := E.geraete(_pads())
	check(g.xi == [0, 1] and bool(g.xi_sicher) and int(g.n) == 3, "XInput-Anschlüsse vom Helfer")
	check((g.sdl as Array).has(0) and (g.sdl as Array).has(1) and (g.sdl as Array).has(2) and not (g.sdl as Array).has(3),
			"SDL: jede Nummer, die passen kann – 3 nicht")
	check((g.familien as Array).has("ps") and (g.familien as Array).has("xbox"), "Bauarten")
	var ohne := E.geraete([{ "key": "j0", "device": 0, "guid": G_XBOX, "name": "Xbox Controller", "xinput": -1, "player": 0, "family": "xbox" }])
	check(not bool(ohne.xi_sicher), "Xbox-Controller ohne Helfer: XInput-Anschluss unbekannt")
	check(E.ps_geraet(XBOX0) == "XInput-0" and E.ps_geraet(DS0) == "SDL-0", "PCSX2/DuckStation: Xbox über XInput, sonst SDL")
	var pl := E.spieler_fehlend(["", "", "", ""], _pads())
	check(not (pl[0] as Dictionary).is_empty() and str(pl[0].name) == "Xbox Wireless Controller", "ohne Zuordnung: der erste Controller ist Spieler 1")


func _f_pcsx2() -> void:
	var gx := _g([0], [0], ["xbox"])
	# Leer (nie eingerichtet): XInput-0 mit üblicher Belegung, XInput einschalten.
	var r := E.plan_ps_fehlend("[UI]\nSettingsVersion = 1\n", "pcsx2", [XBOX0, {}, {}, {}], gx)
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Pad1", "Cross")) == "XInput-0/A" and str(Ini.ini_get(t, "Pad1", "LUp")) == "XInput-0/-LeftY"
			and str(Ini.ini_get(t, "Pad1", "Type")) == "DualShock2", "leer: Spieler 1 → XInput-0, Namen wie PCSX2s Automatik")
	check(str(Ini.ini_get(t, "InputSources", "XInput")) == "true", "leer: XInput im Emulator eingeschaltet")
	check(Ini.ini_get(t, "Pad1", "Analog") == null, "kein „Analog“ auf Guide (die Taste gehört Uzai)")
	check(r.log == ["Spieler 1 → XInput-0 (Belegung war leer)"], str(r.log))
	check(str(E.plan_ps_fehlend(t, "pcsx2", [XBOX0, {}, {}, {}], gx).text) == t, "zweimal: nichts ändert sich")
	# Tastatur-Standard, DualSense über SDL: Tastatur bleibt daneben.
	r = E.plan_ps_fehlend(PCSX2_STD, "pcsx2", [DS0, {}, {}, {}], _g([], [0], ["ps"]))
	t = str(r.text)
	var p1: Array = Ini.section_lines(t, "Pad1")
	check(p1.has("Cross = Keyboard/K") and p1.has("Cross = SDL-0/A") and p1.has("LUp = SDL-0/-LeftY") and p1.has("Deadzone = 0"),
			"Tastatur-Standard: Controller kommt dazu, Tastatur und Einstellungen bleiben")
	check(str(Ini.ini_get(t, "InputSources", "XInput")) == "false" and str(Ini.ini_get(t, "Pad2", "Type")) == "None", "SDL ist schon an; Spieler 2 bleibt leer")
	check(Ini.section_lines(t, "Hotkeys") == Ini.section_lines(PCSX2_STD, "Hotkeys") and t.begins_with("[UI]\nSettingsVersion = 1\n"), "sonst nichts angefasst")
	check(r.log == ["Spieler 1 → SDL-0 (Belegung war nur Tastatur)"], str(r.log))
	# Kaputt aus 0.13.0: „SDL-3/A“, nur ein Xbox-Controller da.
	var kaputt := "[Pad1]\r\nType = DualShock2\r\nCross = SDL-3/B\r\nUp = SDL-3/DPadUp\r\nUp = Keyboard/Up\r\n"
	r = E.plan_ps_fehlend(kaputt, "pcsx2", [XBOX0, {}, {}, {}], gx)
	t = str(r.text)
	p1 = Ini.section_lines(t, "Pad1")
	check(p1.has("Cross = XInput-0/B") and p1.has("Up = XInput-0/DPadUp") and p1.has("Up = Keyboard/Up") and not t.contains("SDL-3"),
			"kaputt (SDL-3): eigene Tasten bleiben, Gerät jetzt XInput-0")
	check(p1.has("Circle = XInput-0/B") and t.contains("\r\n"), "fehlende Tasten ergänzt, CRLF bleibt")
	check(r.log == ["Spieler 1 → XInput-0 (Belegung zeigte auf SDL-3 – nicht angeschlossen)"], str(r.log))
	# Eigene, funktionierende Belegung: nie anfassen – auch nicht, wenn Uzai XInput nähme.
	var eigen := "[InputSources]\nSDL = true\n[Pad1]\nType = DualShock2\nCross = SDL-0/B\nCircle = SDL-0/A\n"
	r = E.plan_ps_fehlend(eigen, "pcsx2", [XBOX0, {}, {}, {}], gx)
	check(str(r.text) == eigen and r.log == ["Spieler 1: eigene Belegung bleibt (SDL-0)"], "eigene Belegung (SDL-0) bleibt Zeichen für Zeichen")
	# XInput belegt, aber im Emulator aus: Quelle an, Belegung bleibt.
	r = E.plan_ps_fehlend("[InputSources]\nXInput = false\n[Pad1]\nCross = XInput-0/A\n", "pcsx2", [XBOX0, {}, {}, {}], gx)
	check(str(Ini.ini_get(str(r.text), "InputSources", "XInput")) == "true" and str(Ini.ini_get(str(r.text), "Pad1", "Cross")) == "XInput-0/A"
			and str(r.log[0]).contains("XInput war im Emulator aus"), "XInput aus: einschalten")
	# Ohne Helfer ist der XInput-Anschluss unbekannt: dann bleibt die Belegung (im Zweifel nie umschreiben).
	var x1 := "[InputSources]\nXInput = true\n[Pad1]\nCross = XInput-1/A\n"
	check(str(E.plan_ps_fehlend(x1, "pcsx2", [DS0, {}, {}, {}], _g([], [0], ["xbox"], false)).text) == x1, "XInput-Anschluss unbekannt: bleibt")
	# PCSX2 ab 2.4 schreibt FaceSouth: neue SDL-Belegung dann auch so.
	var neu := "[Hotkeys]\nX = SDL-0/FaceNorth\n[Pad1]\nType = DualShock2\nCross = Keyboard/K\n"
	check(str(Ini.ini_get(str(E.plan_ps_fehlend(neu, "pcsx2", [DS0, {}, {}, {}], _g([], [0], ["ps"])).text), "Pad1", "Square")).contains("SDL-0/FaceWest"),
			"PCSX2 ab 2.4: FaceSouth & Co.")
	# Zwei Controller: Spieler 2 bekommt [Pad2], wenn er nicht schon Spieler 1 ist.
	var x1p := XBOX0.duplicate()
	x1p.xinput = 1
	x1p.sdl = 1
	r = E.plan_ps_fehlend(PCSX2_STD, "pcsx2", [XBOX0, x1p, {}, {}], _g([0, 1], [0, 1], ["xbox"]))
	check(str(Ini.ini_get(str(r.text), "Pad2", "Type")) == "DualShock2" and str(Ini.ini_get(str(r.text), "Pad2", "Cross")) == "XInput-1/A"
			and r.done == [1, 2], "Spieler 2: Anschluss eingesteckt, XInput-1")
	var p1x1 := "[InputSources]\nXInput = true\n[Pad1]\nCross = XInput-1/A\n[Pad2]\nType = None\n"
	r = E.plan_ps_fehlend(p1x1, "pcsx2", [XBOX0, x1p, {}, {}], _g([0, 1], [0, 1], ["xbox"]))
	check(Ini.ini_get(str(r.text), "Pad2", "Cross") == null, "Spieler 2: sein Controller steuert schon Spieler 1 – nichts doppelt")
	check(E.plan_ps_fehlend(PCSX2_STD, "pcsx2", [{}, {}, {}, {}], gx).log.is_empty(), "kein Spieler: nichts")


func _f_duckstation() -> void:
	# Uzai bis 0.15 legte neuen DuckStations FaceSouth an – das kennt DuckStation nicht.
	var alt := "[InputSources]\nSDL = true\n\n[Pad1]\nType = AnalogController\nCross = SDL-0/FaceSouth\nCircle = SDL-0/FaceEast\nUp = SDL-0/DPadUp\n"
	var r := E.plan_ps_fehlend(alt, "duckstation", [DS0, {}, {}, {}], _g([], [0], ["ps"]))
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Pad1", "Cross")) == "SDL-0/A" and str(Ini.ini_get(t, "Pad1", "Circle")) == "SDL-0/B" and not t.contains("Face"),
			"FaceSouth → A (Kreuz, Kreis … gehen wieder)")
	check(str(r.log[0]).contains("repariert") and str(r.log[1]).contains("eigene Belegung bleibt"), str(r.log))
	check(E.ps_zustand("[Pad1]\nCross = SDL-0/FaceSouth\n", 1, "duckstation", _g([], [0], ["ps"])).art == "kaputt", "FaceSouth allein: kaputt")
	# Anschluss 1 auf „None“: wieder einstecken.
	r = E.plan_ps_fehlend("[Pad1]\nType = None\n", "duckstation", [XBOX0, {}, {}, {}], _g([0], [0], ["xbox"]))
	check(str(Ini.ini_get(str(r.text), "Pad1", "Type")) == "AnalogController" and str(Ini.ini_get(str(r.text), "Pad1", "Square")) == "XInput-0/X"
			and str(r.log[0]).contains("Anschluss war leer"), "Typ None: AnalogController, XInput-0")
	# Tastatur-Standard mit SDL: A/B/X/Y (DuckStation kennt kein FaceSouth).
	r = E.plan_ps_fehlend("[Pad1]\nType = AnalogController\nCross = Keyboard/K\n", "duckstation", [DS0, {}, {}, {}], _g([], [0], ["ps"]))
	check(str(r.text).contains("Triangle = SDL-0/Y") and not str(r.text).contains("Face"), "DuckStation: SDL-0/Y für Dreieck")
	# Andere Anschluss-Art (Lenkrad): nur Gerät, keine fremden Tasten.
	r = E.plan_ps_fehlend("[Pad1]\nType = NeGcon\nI = SDL-4/A\n", "duckstation", [DS0, {}, {}, {}], _g([], [0], ["ps"]))
	check(str(Ini.ini_get(str(r.text), "Pad1", "I")) == "SDL-0/A" and Ini.ini_get(str(r.text), "Pad1", "Cross") == null,
			"NeGcon: Gerät getauscht, keine DualShock-Tasten")


func _f_dolphin() -> void:
	var gx := _g([0], [0], ["xbox"])
	# Dolphins Standard: Tastatur.
	var kb := "[GCPad1]\nDevice = DInput/0/Keyboard Mouse\nButtons/A = X\nButtons/B = Z\nMain Stick/Up = UP\n[GCPad2]\nDevice = DInput/0/Keyboard Mouse\n"
	var r := E.plan_gc_fehlend(kb, [XBOX0, {}, {}, {}], gx)
	var t := str(r.text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad1", "Buttons/A")) == "`Button A`"
			and str(Ini.ini_get(t, "GCPad1", "Main Stick/Up")) == "`Left Y+`" and str(Ini.ini_get(t, "GCPad1", "Rumble/Motor")) == "`Motor L`",
			"Tastatur: XInput/0/Gamepad mit üblicher Belegung (Y+ oben, Motor L)")
	check(str(Ini.ini_get(t, "GCPad2", "Device")) == "DInput/0/Keyboard Mouse", "ohne Spieler 2: Anschluss 2 bleibt")
	check(r.log == ["Spieler 1 → XInput/0/Gamepad (Belegung war nur Tastatur)"], str(r.log))
	# Kaputt: XInput-Anschluss 2 steckt nicht – Tasten bleiben, Anschluss wird 0.
	var x2 := "[GCPad1]\nDevice = XInput/2/Gamepad\nButtons/A = `Button B`\nMain Stick/Dead Zone = 15.0\n"
	t = str(E.plan_gc_fehlend(x2, [XBOX0, {}, {}, {}], gx).text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad1", "Buttons/A")) == "`Button B`"
			and str(Ini.ini_get(t, "GCPad1", "Main Stick/Dead Zone")) == "15.0", "kaputt (XInput/2): eigene Tasten, Anschluss 0")
	# SDL-Belegung eines DualSense: bleibt, solange einer da ist; nur Xbox da → übliche XInput-Belegung.
	var ds := "[GCPad1]\nDevice = SDL/0/PS5 Controller\nButtons/A = `Button E`\n"
	check(str(E.plan_gc_fehlend(ds, [DS0, {}, {}, {}], _g([], [0], ["ps"])).text) == ds, "DualSense-Belegung, DualSense da: bleibt (auch bei anderem Namen)")
	t = str(E.plan_gc_fehlend(ds, [XBOX0, {}, {}, {}], gx).text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad1", "Buttons/A")) == "`Button A`",
			"DualSense-Belegung, nur Xbox da: übliche Belegung")
	t = str(E.plan_gc_fehlend("", [DS0, {}, {}, {}], _g([], [0], ["ps"])).text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "SDL/0/DualSense Wireless Controller", "neue Datei, DualSense: Name, wie SDL ihn meldet")
	# Dolphin.ini: Anschluss 1 leer → Controller.
	var core := "[Core]\nSIDevice0 = 0\nSIDevice1 = 0\n"
	var c := E.plan_dolphin_ini_fehlend(core, [XBOX0, {}, {}, {}])
	check(str(Ini.ini_get(str(c.text), "Core", "SIDevice0")) == "6" and str(Ini.ini_get(str(c.text), "Core", "SIDevice1")) == "0",
			"SIDevice0: eingesteckt, 1 bleibt")
	check(str(E.plan_dolphin_ini_fehlend("[Core]\nGFXBackend = D3D\n", [XBOX0, {}, {}, {}]).text) == "[Core]\nGFXBackend = D3D\n",
			"fehlt SIDevice0: gilt schon Controller")
	# Wii: Tastatur → emulierte Wiimote mit Nunchuk; echte Wiimote bleibt.
	var wii := "[Wiimote1]\nSource = 1\nDevice = DInput/0/Keyboard Mouse\nButtons/A = Click 0\n[Wiimote2]\nSource = 2\n"
	var x1p := XBOX0.duplicate()
	x1p.xinput = 1
	var w := E.plan_wii_fehlend(wii, [XBOX0, x1p, {}, {}], _g([0, 1], [0, 1], ["xbox"]))
	t = str(w.text)
	check(str(Ini.ini_get(t, "Wiimote1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "Wiimote1", "Extension")) == "Nunchuk"
			and str(Ini.ini_get(t, "Wiimote1", "Nunchuk/Stick/Up")) == "`Left Y+`" and str(Ini.ini_get(t, "Wiimote1", "IR/Up")) == "`Right Y+`",
			"Wii Spieler 1: emulierte Wiimote mit Nunchuk")
	check(str(Ini.ini_get(t, "Wiimote2", "Source")) == "2" and Ini.ini_get(t, "Wiimote2", "Device") == null and str(w.log[1]).contains("echte Wiimote"),
			"echte Wiimote bleibt")


func _f_andere() -> void:
	var g1 := _g([0], [0], ["xbox"])
	# RetroArch: Autoconfig an, Spieler 1 auf ein Gerät, das es gibt.
	var ra := "input_autodetect_enable = \"false\"\ninput_joypad_driver = \"xinput\"\ninput_player1_joypad_index = \"3\"\n"
	var r := E.plan_ra_fehlend(ra, [XBOX0, {}, {}, {}], g1)
	check(str(Ini.ini_get(str(r.text), "", "input_autodetect_enable")) == "\"true\""
			and str(Ini.ini_get(str(r.text), "", "input_player1_joypad_index")) == "\"0\"",
			"RetroArch: Autoconfig an, Gerät 3 → 0")
	check(str(r.log[1]) == "Spieler 1 → Gerät 0 (Belegung zeigte auf Gerät 3 – nicht angeschlossen)", str(r.log))
	var ok := "input_player1_joypad_index = \"0\"\n"
	check(str(E.plan_ra_fehlend(ok, [XBOX0, {}, {}, {}], g1).text) == ok, "RetroArch: Gerät 0 bleibt")
	# PPSSPP: nur Tastatur → Standard von PPSSPP (mit Controller) zurück; mit Controller bleibt alles.
	var kb := "[ControlMapping]\nUp = 1-19\nCross = 1-52,1-62\n\n[Other]\nX = 1\n"
	var p := E.plan_ppsspp_fehlend(kb, g1)
	check(Ini.section_lines(str(p.text), "ControlMapping") == null and str(Ini.ini_get(str(p.text), "Other", "X")) == "1", "PPSSPP nur Tastatur: Standard zurück")
	var pad := "[ControlMapping]\nUp = 1-19,20-19\nCross = 1-52:1-62,10-96\n"
	check(str(E.plan_ppsspp_fehlend(pad, g1).text) == pad, "PPSSPP mit Controller-Belegung: bleibt")
	check(str(E.plan_ppsspp_fehlend("[General]\n", g1).text) == "[General]\n", "PPSSPP ohne Belegung: Standard gilt schon")
	# Eden & Co.
	var qt := "[Controls]\nplayer_0_button_a=\"engine:keyboard,code:67\"\nplayer_1_button_a=\"engine:sdl,port:0,guid:%s,button:1\"\nplayer_1_lstick=\"engine:sdl,port:0,guid:%s,axis_x:0,axis_y:1\"\n" % [G_XBOX, G_XBOX]
	var y := E.plan_yuzu_fehlend(qt, [XBOX0, {}, {}, {}])
	check(str(Ini.ini_get(str(y.text), "Controls", "player_0_button_a")).contains("engine:sdl,port:0,guid:" + G_XBOX + ",button:1")
			and str(Ini.ini_get(str(y.text), "Controls", "player_0_connected")) == "true", "Eden: Belegung des Emulators von Spieler 2 übernommen")
	var eig := "[Controls]\nplayer_0_button_a=\"engine:sdl,port:0,guid:abc,button:1\"\n"
	check(str(E.plan_yuzu_fehlend(eig, [XBOX0, {}, {}, {}]).text) == eig, "Eden: eigene SDL-Belegung bleibt")
	var nur := "[Controls]\nplayer_0_button_a=\"engine:keyboard,code:67\"\n"
	y = E.plan_yuzu_fehlend(nur, [XBOX0, {}, {}, {}])
	check(str(y.text) == nur and str(y.log[0]).contains("Eingabegerät"), "Eden nur Tastatur: nicht raten, Hinweis")


func _f_dateien() -> void:
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	var env := { "docs": root.path_join("f_docs"), "appdata": root.path_join("f_app"), "localappdata": root.path_join("f_local") }
	var g1 := _g([0], [0], ["xbox"])
	# PCSX2 tragbar, Tastatur-Standard.
	var pc := root.path_join("f_emu/PCSX2")
	var emus_alt: Variant = Config.get_value("emulators", {})
	Config.set_value("emulators.pcsx2.exe", pc.path_join("pcsx2-qt.exe"))
	Config.set_value("emulators.dolphin.exe", root.path_join("f_emu/Dolphin/Dolphin.exe"))
	DirAccess.make_dir_recursive_absolute(pc.path_join("inis"))
	FileAccess.open(pc.path_join("portable.ini"), FileAccess.WRITE).close()
	var ini := pc.path_join("inis/PCSX2.ini")
	var f := FileAccess.open(ini, FileAccess.WRITE)
	f.store_string(PCSX2_STD)
	f.close()
	var res := E.fehlend("pcsx2", pc.path_join("pcsx2-qt.exe"), "ps2", [XBOX0, {}, {}, {}], g1, env)
	check((res.files as Array).size() == 1 and str(Ini.ini_get(FileAccess.get_file_as_string(ini), "Pad1", "LUp")).contains("Keyboard/W")
			and FileAccess.get_file_as_string(ini).contains("LUp = XInput-0/-LeftY"), "PCSX2-Datei geschrieben")
	check(res.log.slice(1) == ["Spieler 1 → XInput-0 (Belegung war nur Tastatur)"]
			and str(res.log[0]) == "Datei %s (tragbar: portable.ini neben pcsx2-qt.exe)" % ini
			and E.has_backups(), "launch.log-Zeilen (Datei und warum), Original gesichert")
	var vorher := FileAccess.get_file_as_string(ini)
	res = E.fehlend("pcsx2", pc.path_join("pcsx2-qt.exe"), "ps2", [XBOX0, {}, {}, {}], g1, env)
	check((res.files as Array).is_empty() and FileAccess.get_file_as_string(ini) == vorher and str(res.log[1]).contains("eigene Belegung bleibt (XInput-0)"),
			"nächster Start: Uzais Belegung gilt als eigene, nichts mehr geschrieben")
	check(str(E.fehlend("pcsx2", pc.path_join("pcsx2-qt.exe"), "ps2", [XBOX0, {}, {}, {}], _g([], [], []), env).log[0]).contains("kein Controller"),
			"kein Controller: nichts geändert, im Log")
	# Dolphin tragbar ohne GCPadNew.ini (Steuerung nie geöffnet): neben Dolphin.ini anlegen.
	var dol := root.path_join("f_emu/Dolphin")
	DirAccess.make_dir_recursive_absolute(dol.path_join("User/Config"))
	FileAccess.open(dol.path_join("portable.txt"), FileAccess.WRITE).close()
	f = FileAccess.open(dol.path_join("User/Config/Dolphin.ini"), FileAccess.WRITE)
	f.store_string("[Core]\nCPUThread = True\n")
	f.close()
	var gc := dol.path_join("User/Config/GCPadNew.ini")
	res = E.fehlend("dolphin", dol.path_join("Dolphin.exe"), "gc", [XBOX0, {}, {}, {}], g1, env)
	check(FileAccess.file_exists(gc) and str(Ini.ini_get(FileAccess.get_file_as_string(gc), "GCPad1", "Device")) == "XInput/0/Gamepad",
			"Dolphin: GCPadNew.ini neben Dolphin.ini angelegt")
	check(FileAccess.get_file_as_string(dol.path_join("User/Config/Dolphin.ini")) == "[Core]\nCPUThread = True\n", "Dolphin.ini: Anschluss 1 gilt schon")
	check(not E.path_ok(root.path_join("f_emu/GCPadNew.ini"), [root], true), "anlegen nur neben Dolphin.ini")
	var n := E.restore_all()
	check(n == 2 and FileAccess.get_file_as_string(ini) == PCSX2_STD and FileAccess.get_file_as_string(gc) == "",
			"Originale zurück (angelegte Datei: leer = wie keine)")
	res = E.fehlend("dolphin", dol.path_join("Dolphin.exe"), "gc", [XBOX0, {}, {}, {}], g1, env)
	check((res.files as Array).size() == 1, "leere Datei: wieder einrichtbar")
	E.restore_all()
	# Präparierte Liste (etwa aus einer fremden Sicherung): ein Ziel außerhalb der Emulator-Ordner wird nie überschrieben.
	var fremd := root.path_join("f_fremd/settings.ini")
	DirAccess.make_dir_recursive_absolute(fremd.get_base_dir())
	f = FileAccess.open(fremd, FileAccess.WRITE)
	f.store_string("wichtig\n")
	f.close()
	var bn := E.backup_name("pcsx2", fremd)
	DirAccess.make_dir_recursive_absolute(Config.path(E.BACKUP_DIR))
	f = FileAccess.open(Config.path(E.BACKUP_DIR).path_join(bn), FileAccess.WRITE)
	f.store_string("boese\n")
	f.close()
	Config.set_value(E.KEY_BACKUPS, { bn: fremd })
	check(E.restore_all() == 0 and FileAccess.get_file_as_string(fremd) == "wichtig\n", "präparierte Rücksicherung: fremde Datei bleibt")
	Config.set_value(E.KEY_BACKUPS, {})
	DirAccess.remove_absolute(Config.path(E.BACKUP_DIR).path_join(bn))
	Config.set_value("emulators", emus_alt)
	check(str(E.fehlend("cemu", "C:/x/Cemu.exe", "wiiu", [XBOX0, {}, {}, {}], g1, env).log[0]).contains("richtet Uzai nicht ein"), "unbekannter Emulator: im Log")
	var lsrc := (load("res://src/core/launcher.gd") as GDScript).source_code
	check(lsrc.contains("log_launch(\"Controller: %s%s%s\" % [name, \" \" if str(l).begins_with(\"Spieler\") else \": \", str(l)])"),
			"launch.log: „Controller: PCSX2 Spieler 1 → …“")


## Vier gemischte Controller in der Reihenfolge, in der Windows sie meldet (Godot-Gerätenummer).
func _vier() -> Array:
	return [
		{ "key": "x0", "device": 0, "guid": G_XBOX, "name": "Xbox Wireless Controller", "xinput": 0, "player": 0, "family": "xbox" },
		{ "key": "j1", "device": 1, "guid": G_DS, "name": "DualSense", "sdl_name": "DualSense Wireless Controller", "xinput": -1, "player": 1,
			"family": "ps" },
		{ "key": "j2", "device": 2, "guid": G_PRO, "name": "Switch Pro", "sdl_name": "Nintendo Switch Pro Controller", "xinput": -1, "player": -1,
			"family": "nintendo" },
		{ "key": "x1", "device": 3, "guid": G_XBOX, "name": "Xbox Wireless Controller", "xinput": 1, "player": 3, "family": "xbox" },
	]


const G_PRO := "030000007e0500000920000000006800"


func _f_viele() -> void:
	var p4 := _vier()
	var ids := S.ids_for(p4)
	var conn: Array = ids.map(func(e): return str(e.id))
	var slots := S.auto_fill([], conn.slice(0, 2), {})
	check(slots == [conn[0], conn[1], "", ""], "zwei Controller: Spieler 1 und 2 in der Reihenfolge des Verbindens")
	slots = S.auto_fill(slots, conn, {})
	check(slots == conn, "vier Controller gemischt: Spieler 1–4 der Reihe nach")
	slots = S.auto_fill(slots, [conn[0], conn[2], conn[3]], {})
	check(slots == [conn[0], "", conn[2], conn[3]], "Spieler 2 geht: die anderen behalten ihren Platz")
	slots = S.auto_fill(slots, conn, {})
	check(slots == conn, "kommt wieder: wieder Spieler 2")
	var pl := S.players(conn, p4)
	check(E.ps_geraet(pl[0]) == "XInput-0" and E.ps_geraet(pl[1]) == "SDL-1" and E.ps_geraet(pl[2]) == "SDL-2" and E.ps_geraet(pl[3]) == "XInput-1",
			"PCSX2/DuckStation: Xbox über XInput, DualSense und Switch Pro über SDL, Nummern ohne Doppelte")
	var g := E.geraete(p4)
	# PCSX2: Spieler 1 und 2 (ohne Multitap), beide frisch.
	var r := E.plan_ps_fehlend(PCSX2_STD, "pcsx2", pl, g)
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Pad1", "Cross")) == "Keyboard/K" and (Ini.section_lines(t, "Pad1") as Array).has("Cross = XInput-0/A")
			and (Ini.section_lines(t, "Pad2") as Array).has("Cross = SDL-1/A") and str(Ini.ini_get(t, "Pad2", "Type")) == "DualShock2",
			"PCSX2 mit vier: Pad1 XInput-0, Pad2 SDL-1 (DualSense)")
	check(str(Ini.ini_get(t, "InputSources", "XInput")) == "true" and str(Ini.ini_get(t, "InputSources", "SDL")) == "true", "beide Quellen an")
	check(r.log == ["Spieler 1 → XInput-0 (Belegung war nur Tastatur)", "Spieler 2 → SDL-1 (Anschluss war leer)"], str(r.log))
	# Dolphin: GameCube 1–4 gemischt, frisch.
	var gc := E.plan_gc_fehlend("", pl, g)
	t = str(gc.text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad2", "Device")) == "SDL/0/DualSense Wireless Controller"
			and str(Ini.ini_get(t, "GCPad3", "Device")) == "SDL/0/Nintendo Switch Pro Controller" and str(Ini.ini_get(t, "GCPad4", "Device")) == "XInput/1/Gamepad",
			"Dolphin GameCube 1–4: je Controller sein Gerät (XInput-Anschluss bzw. SDL-Name)")
	var core := str(E.plan_dolphin_ini_fehlend("[Core]\nSIDevice0 = 6\nSIDevice1 = 0\nSIDevice2 = 0\nSIDevice3 = 0\n", pl).text)
	check(str(Ini.ini_get(core, "Core", "SIDevice3")) == "6" and str(Ini.ini_get(core, "Core", "SIDevice1")) == "6", "Dolphin: Anschlüsse 2–4 eingesteckt")
	# Drei Controller: Spieler 3 im Emulator mit eigener Belegung bleibt, die anderen werden ergänzt.
	var drei := "[GCPad3]\nDevice = SDL/0/Pro Controller\nButtons/A = `Button E`\n"
	t = str(E.plan_gc_fehlend(drei, pl.slice(0, 3) + [{}], E.geraete(p4.slice(0, 3))).text)
	check(str(Ini.ini_get(t, "GCPad3", "Buttons/A")) == "`Button E`" and str(Ini.ini_get(t, "GCPad2", "Device")).begins_with("SDL/0/DualSense")
			and Ini.section_lines(t, "GCPad4") == null, "drei Controller: eigene Belegung von Spieler 3 bleibt, Spieler 4 frei")
	# Immer nach Uzais Zuordnung mit vier: RetroArch je Spieler sein Gerät.
	var ra := str(E.plan_retroarch("input_joypad_driver = \"xinput\"\n", pl, 4).text)
	check(str(Ini.ini_get(ra, "", "input_player1_joypad_index")) == "\"0\"" and str(Ini.ini_get(ra, "", "input_player4_joypad_index")) == "\"1\""
			and str(Ini.ini_get(ra, "", "input_player2_joypad_index")) == "\"2\"", "RetroArch nach Zuordnung: erst XInput-Anschlüsse, dann die übrigen")
	# Neuer Controller mitten im Spiel: Hinweis nur für den neuen, nur einmal, nicht bei RetroArch.
	var jetzt: Array = []
	for i in p4.size():
		var e: Dictionary = p4[i].duplicate()
		e["uz_id"] = conn[i]
		e["spieler"] = i + 1
		jetzt.append(e)
	var neu := E.neu_im_spiel("dolphin", conn.slice(0, 2), jetzt, {})
	check(neu.size() == 2 and int(neu[0].slot) == 3 and int(neu[1].slot) == 4, "Dolphin: Spieler 3 und 4 neu im Spiel → Hinweis")
	check(E.neu_im_spiel("pcsx2", conn.slice(0, 1), jetzt, {}).map(func(e): return int(e.slot)) == [2, 3, 4], "PCSX2: Spieler 2–4 (3 und 4 über den Multitap)")
	check(E.neu_im_spiel("dolphin", conn.slice(0, 2), jetzt, { conn[2]: true, conn[3]: true }).is_empty(), "je Controller nur einmal")
	check(E.neu_im_spiel("retroarch", [], jetzt, {}).is_empty(), "RetroArch nimmt neue Controller selbst")


# --- Start: player 1 = the controller in use (a custom mapping used to stay on SDL-0) ---

func _s_wer() -> void:
	var p := _pads()
	var ids: Array = S.ids_for(p).map(func(e): return str(e.id))
	for i in p.size():
		p[i]["uz_id"] = ids[i]
	var slots: Array = [ids[0], ids[1], ids[2], ""]
	# Mit dem DualSense gestartet: er ist Spieler 1, der Xbox-Controller rückt auf seinen Platz.
	var w := E.spieler_start(slots, p, {}, ids[1])
	check(str(w.players[0].name) == "PS5 Controller" and str(w.players[1].name) == "Xbox Wireless Controller" and int(w.players[2].xinput) == 1,
			"benutzt: Spieler 1, der bisherige Spieler 1 tauscht mit ihm")
	check(str(w.grund) == "mit diesem Controller gestartet" and w.slots == [ids[1], ids[0], ids[2], ""], "Grund und Plätze")
	check(E.spieler_start(slots, p, {}, ids[0]).slots == slots, "schon Spieler 1: nichts tauscht")
	# Ohne Controller gestartet (Maus/Tastatur): Uzais Zuordnung.
	w = E.spieler_start(slots, p, {}, "")
	check(str(w.players[0].name) == "Xbox Wireless Controller" and str(w.grund).contains("Zuordnung"), "ohne benutzten Controller: nach Zuordnung")
	check(str(E.spieler_start(slots, p, {}, "weg#0").grund).contains("Zuordnung"), "benutzter Controller nicht mehr da: nach Zuordnung")
	# Selbst zugeordnet, mehrere Spieler: das gilt.
	w = E.spieler_start(slots, p, { ids[0]: 1 }, ids[1])
	check(str(w.players[0].name) == "Xbox Wireless Controller" and str(w.grund).begins_with("selbst zugeordnet"),
			"selbst gesetztes Spieler 1 gewinnt bei mehreren")
	# Nur ein Spieler belegt (der andere Controller selbst entfernt): immer der benutzte.
	w = E.spieler_start([ids[0], "", "", ""], p, { ids[0]: 1, ids[1]: 0 }, ids[1])
	check(str(w.players[0].name) == "PS5 Controller" and w.slots == [ids[1], ids[0], "", ""], "ein Spieler: der benutzte ist Spieler 1, auch gegen gemerkt")
	var one := [p[1]]
	w = E.spieler_start(["", "", "", ""], one, { ids[1]: 0 }, ids[1])
	check(str(w.players[0].name) == "PS5 Controller", "ein Controller, selbst entfernt: trotzdem Spieler 1")
	# Pads: Godot-Gerät → Kennung.
	check(Pads.id_of_device(p, 1) == ids[1] and Pads.id_of_device(p, -1) == "" and Pads.id_of_device(p, 9) == "", "Pads: zuletzt benutztes Gerät → Kennung")
	# launch.log: je Controller Godot-Gerät, Name, GUID, XInput, SDL-Nummer.
	var gl := E.geraete_log(p, ids[1])
	check(str(gl[0]) == "Gerät 0: Xbox Wireless Controller · xbox · GUID %s · XInput Anschluss 0 · SDL-0 (SDL-Spieler 0)" % G_XBOX, str(gl[0]))
	check(str(gl[1]).contains("Gerät 1: PS5 Controller") and str(gl[1]).contains("XInput –") and str(gl[1]).contains("SDL-2 (SDL-Spieler -1) · damit gestartet"),
			str(gl[1]))


func _s_ps() -> void:
	var gx := _g([0], [0], ["xbox"])
	# Von Uzai installiertes PCSX2 (retro_auto.gd): [Pad1] auf SDL-0 mit FaceSouth. Gespielt wird mit dem
	# Xbox-Controller an XInput-Anschluss 0 → XInput-0, Tastennamen A/B/X/Y, XInput an.
	var ra := load("res://src/core/retro_auto.gd")
	var uz := str(ra.grund_dateien("pcsx2")["inis/PCSX2.ini"])
	check(uz.contains("Cross = SDL-0/FaceSouth"), "Ausgangslage: Uzais PCSX2 zeigt auf SDL-0")
	var r := E.plan_ps_start(uz, "pcsx2", [XBOX0, {}, {}, {}], gx)
	var t := str(r.text)
	var p1: Array = Ini.section_lines(t, "Pad1")
	check(p1.has("Cross = XInput-0/A") and p1.has("Triangle = XInput-0/Y") and p1.has("LUp = XInput-0/-LeftY") and not t.contains("SDL-0/"),
			"vorhandene Belegung auf SDL-0: Gerät jetzt XInput-0 (alle Tasten)")
	check(str(Ini.ini_get(t, "InputSources", "XInput")) == "true" and str(Ini.ini_get(t, "InputSources", "SDL")) == "true", "XInput an, SDL bleibt an")
	check(r.log == ["Spieler 1 → XInput-0 (Belegung zeigte auf SDL-0; XInput-Anschluss 0 vom Windows-Helfer)"], str(r.log))
	r = E.plan_ps_start(t, "pcsx2", [XBOX0, {}, {}, {}], gx)
	check(str(r.text) == t and r.log == ["Spieler 1: XInput-0 (stimmt schon; XInput-Anschluss 0 vom Windows-Helfer)"] and r.done.is_empty(),
			"zweiter Start: nichts mehr geschrieben")
	# Eigene Tasten (Kreuz und Kreis vertauscht) bleiben, nur das Gerät wechselt; Tastatur bleibt daneben.
	var eigen := "[InputSources]\nSDL = true\n[Pad1]\nType = DualShock2\nCross = SDL-0/B\nCircle = SDL-0/A\nUp = Keyboard/Up\n"
	t = str(E.plan_ps_start(eigen, "pcsx2", [XBOX0, {}, {}, {}], gx).text)
	p1 = Ini.section_lines(t, "Pad1")
	check(p1.has("Cross = XInput-0/B") and p1.has("Circle = XInput-0/A") and p1.has("Up = Keyboard/Up") and p1.has("Square = XInput-0/X"),
			"eigene Tasten bleiben, nur das Gerät wechselt, Fehlendes ergänzt")
	# Xbox und DualSense; mit dem DualSense gestartet: Pad1 → SDL des DualSense, Pad2 → XInput-0.
	var p := _pads().slice(0, 2)
	var ids: Array = S.ids_for(p).map(func(e): return str(e.id))
	var w := E.spieler_start([ids[0], ids[1], "", ""], p, {}, ids[1])
	var g2 := E.geraete(p)
	r = E.plan_ps_start("[InputSources]\nXInput = true\n[Pad1]\nType = DualShock2\nCross = XInput-0/A\n[Pad2]\nType = None\n", "pcsx2", w.players, g2)
	t = str(r.text)
	check(str(Ini.ini_get(t, "Pad1", "Cross")) == "SDL-1/A" and str(Ini.ini_get(t, "Pad2", "Cross")) == "XInput-0/A"
			and str(Ini.ini_get(t, "Pad2", "Type")) == "DualShock2", "zwei Controller: Pad1 = benutzter (SDL-1), Pad2 = der andere (XInput-0)")
	check(str(r.log[0]).begins_with("Spieler 1 → SDL-1 (Belegung zeigte auf XInput-0; kein XInput-Gerät")
			and str(r.log[1]).begins_with("Spieler 2 → XInput-0 (Anschluss war leer"),
			str(r.log))
	# Allein, aber [Pad2] hört auf den Controller von Spieler 1: auf einen freien Anschluss.
	var doppelt := "[InputSources]\nXInput = true\n[Pad1]\nType = DualShock2\nCross = XInput-0/A\n[Pad2]\nType = DualShock2\nCross = XInput-0/B\nUp = Keyboard/W\n"
	r = E.plan_ps_start(doppelt, "pcsx2", [XBOX0, {}, {}, {}], gx)
	t = str(r.text)
	check(str(Ini.ini_get(t, "Pad2", "Cross")) == "XInput-1/B" and (Ini.section_lines(t, "Pad2") as Array).has("Up = Keyboard/W")
			and str(r.log[-1]).contains("→ XInput-1"), "Pad2 auf demselben Controller: wandert auf XInput-1, Tasten bleiben")
	# DuckStation: dieselbe Regel, Namen A/B/X/Y, Typ None → AnalogController.
	r = E.plan_ps_start("[Pad1]\nType = AnalogController\nCross = SDL-0/A\n", "duckstation", [XBOX0, {}, {}, {}], gx)
	check(str(Ini.ini_get(str(r.text), "Pad1", "Cross")) == "XInput-0/A" and str(Ini.ini_get(str(r.text), "InputSources", "XInput")) == "true",
			"DuckStation: SDL-0 → XInput-0")
	# Geräte: SDL-0 gilt nicht mehr als angeschlossen, nur weil irgendein Controller steckt.
	var nur1 := E.geraete([{ "key": "x1", "device": 0, "guid": G_XBOX, "name": "Xbox", "xinput": 1, "player": 1, "family": "xbox" }])
	check(nur1.sdl == [1], "ein Xbox-Controller an Anschluss 2: nur SDL-1 (früher auch SDL-0)")
	check(E.ps_zustand("[Pad1]\nCross = SDL-0/A\n", 1, "pcsx2", nur1).art == "kaputt", "SDL-0 dann: nicht angeschlossen")


func _s_andere() -> void:
	var p := _pads().slice(0, 2)
	var ids: Array = S.ids_for(p).map(func(e): return str(e.id))
	var w := E.spieler_start([ids[0], ids[1], "", ""], p, {}, ids[1])
	var g2 := E.geraete(p)
	# Dolphin: GCPad1 hatte eine eigene Xbox-Belegung, gestartet mit dem DualSense.
	var gc := "[GCPad1]\nDevice = XInput/0/Gamepad\nButtons/A = `Button B`\nButtons/B = `Button A`\nMain Stick/Up = `Left Y+`\n"
	var r := E.plan_dolphin_start(gc, w.players, g2, "GCPad")
	var t := str(r.text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "SDL/0/PS5 Controller" and str(Ini.ini_get(t, "GCPad1", "Buttons/A")) == "`Button A`",
			"Dolphin: Spieler 1 = DualSense (übliche Belegung, andere Quelle)")
	check(str(Ini.ini_get(t, "GCPad2", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad2", "Buttons/A")) == "`Button B`",
			"Dolphin: Spieler 2 = Xbox mit der eigenen Xbox-Belegung")
	check(str(r.log[0]) == "Spieler 1 → SDL/0/PS5 Controller (Belegung zeigte auf XInput/0/Gamepad)", str(r.log))
	# Xbox-Belegung auf Anschluss 2, gespielt an Anschluss 1: Tasten bleiben.
	var x1 := "[GCPad1]\nDevice = XInput/1/Gamepad\nButtons/A = `Button B`\n"
	t = str(E.plan_dolphin_start(x1, [XBOX0, {}, {}, {}], _g([0, 1], [0, 1], ["xbox"]), "GCPad").text)
	check(str(Ini.ini_get(t, "GCPad1", "Device")) == "XInput/0/Gamepad" and str(Ini.ini_get(t, "GCPad1", "Buttons/A")) == "`Button B`",
			"Dolphin: andere XInput-Nummer, eigene Tasten bleiben")
	var wii := "[Wiimote1]\nSource = 2\n"
	check(str(E.plan_dolphin_start(wii, [XBOX0, {}, {}, {}], _g([0], [0], ["xbox"]), "Wiimote").text) == wii, "echte Wiimote bleibt")
	# RetroArch mit zwei Controllern: Spieler 1 = benutzter.
	var ra := "input_joypad_driver = \"xinput\"\ninput_player1_joypad_index = \"0\"\ninput_player2_joypad_index = \"1\"\n"
	r = E.plan_ra_start(ra, w.players, g2)
	t = str(r.text)
	check(str(Ini.ini_get(t, "", "input_player1_joypad_index")) == "\"1\"" and str(Ini.ini_get(t, "", "input_player2_joypad_index")) == "\"0\"",
			"RetroArch: Spieler 1 → Gerät des DualSense, Spieler 2 → Xbox")
	check(str(E.plan_ra_start(ra, [XBOX0, {}, {}, {}], _g([0], [0], ["xbox"])).text) == ra, "RetroArch mit einem Controller: wie bisher")


func _s_dateien() -> void:
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	var env := { "docs": root.path_join("s_docs"), "appdata": root.path_join("s_app"), "localappdata": root.path_join("s_local") }
	# PCSX2 nicht tragbar, aber mit alter inis\PCSX2.ini neben der exe: PCSX2 liest Dokumente\PCSX2.
	var pc := root.path_join("s_emu/PCSX2")
	DirAccess.make_dir_recursive_absolute(pc.path_join("inis"))
	var alt := pc.path_join("inis/PCSX2.ini")
	var f := FileAccess.open(alt, FileAccess.WRITE)
	f.store_string(PCSX2_STD)
	f.close()
	var pi := E.ps_ini("pcsx2", pc.path_join("pcsx2-qt.exe"), env)
	check(str(pi[0]) == str(env.docs).path_join("PCSX2/inis/PCSX2.ini") and str(pi[1]).contains("Dokumente"),
			"nicht tragbar: Dokumente\\PCSX2, nie die alte Datei neben der exe")
	var res := E.fehlend("pcsx2", pc.path_join("pcsx2-qt.exe"), "ps2", [XBOX0, {}, {}, {}], _g([0], [0], ["xbox"]), env, true)
	check((res.files as Array).is_empty() and FileAccess.get_file_as_string(alt) == PCSX2_STD and str(res.log[0]).contains("nicht gefunden")
			and str(res.log[1]).contains("Dokumente") and str(res.log[1]).contains("fehlt"), "Datei in Dokumente fehlt: nichts woanders schreiben, Log sagt wo gesucht")
	# portable.txt mit Unterordner (PCSX2 erlaubt das), mit „..“ nicht.
	f = FileAccess.open(pc.path_join("portable.txt"), FileAccess.WRITE)
	f.store_string("daten\r\n")
	f.close()
	check(str(E.ps_ini("pcsx2", pc.path_join("pcsx2-qt.exe"), env)[0]) == pc.path_join("daten/inis/PCSX2.ini"), "portable.txt mit Ordner: daten\\inis")
	f = FileAccess.open(pc.path_join("portable.txt"), FileAccess.WRITE)
	f.store_string("..\\woanders")
	f.close()
	check(str(E.ps_ini("pcsx2", pc.path_join("pcsx2-qt.exe"), env)[0]) == "", "portable.txt mit „..“: nichts")
	DirAccess.remove_absolute(pc.path_join("portable.txt"))
	# Von Uzai installiert: portable.ini neben pcsx2-qt.exe, [Pad1] auf SDL-0 → XInput-0.
	FileAccess.open(pc.path_join("portable.ini"), FileAccess.WRITE).close()
	var ra := load("res://src/core/retro_auto.gd")
	f = FileAccess.open(alt, FileAccess.WRITE)
	f.store_string(str(ra.grund_dateien("pcsx2")["inis/PCSX2.ini"]))
	f.close()
	res = E.fehlend("pcsx2", pc.path_join("pcsx2-qt.exe"), "ps2", [XBOX0, {}, {}, {}], _g([0], [0], ["xbox"]), env, true)
	check((res.files as Array) == [alt] and str(Ini.ini_get(FileAccess.get_file_as_string(alt), "Pad1", "Cross")) == "XInput-0/A",
			"Uzais PCSX2 (tragbar): Pad1 jetzt XInput-0")
	check(str(res.log[0]) == "Datei %s (tragbar: portable.ini neben pcsx2-qt.exe)" % alt and str(res.log[1]).begins_with("Spieler 1 → XInput-0"), str(res.log))
	# Spiele mit eigener Controller-Einstellung in PCSX2: im Log.
	DirAccess.make_dir_recursive_absolute(pc.path_join("gamesettings"))
	f = FileAccess.open(pc.path_join("gamesettings/SLES-12345_ABCDEF01.ini"), FileAccess.WRITE)
	f.store_string("[Pad]\nUseGameSettingsForController = true\n")
	f.close()
	check(E.pcsx2_spiel_eigene(alt) == 1, "PCSX2: Spiel mit eigener Controller-Einstellung erkannt")
	E.restore_all()
	# DuckStation: settings.ini neben der exe heißt tragbar; sonst Dokumente (wenn da), sonst LocalAppData.
	var ds := root.path_join("s_emu/DuckStation")
	DirAccess.make_dir_recursive_absolute(ds)
	var exe := ds.path_join("duckstation-qt-x64-ReleaseLTCG.exe")
	check(str(E.ps_ini("duckstation", exe, env)[0]) == str(env.localappdata).path_join("DuckStation/settings.ini"), "DuckStation neu: %LOCALAPPDATA%")
	DirAccess.make_dir_recursive_absolute(str(env.docs).path_join("DuckStation"))
	check(str(E.ps_ini("duckstation", exe, env)[0]) == str(env.docs).path_join("DuckStation/settings.ini"), "DuckStation alt: Dokumente")
	FileAccess.open(ds.path_join("settings.ini"), FileAccess.WRITE).close()
	check(str(E.ps_ini("duckstation", exe, env)[0]) == ds.path_join("settings.ini") and Ini.is_portable("duckstation", ds),
			"DuckStation: settings.ini neben der exe = tragbar")


func _s_wege() -> void:
	var lsrc := (load("res://src/core/launcher.gd") as GDScript).source_code
	var rom := lsrc.substr(lsrc.find("func _launch_rom("), 900)
	check(rom.find("_spieler_einrichten(g, cmd)") > 0 and rom.find("_spieler_einrichten(g, cmd)") < rom.find("_start_process("),
			"jeder Emulator-Start (auch Disc, Weiterspielen): erst einrichten, dann starten")
	check(lsrc.contains("var drv := str(g.get(\"_disc_drive\", \"\"))")
			and lsrc.substr(lsrc.find("func _launch_remote_play("), 2500).contains("_spieler_einrichten(g, cmd)"),
			"Disc über _rom_command, Remote Play richtet auch ein")
	var dsrc := (load("res://src/core/discs.gd") as GDScript).source_code
	check(dsrc.contains("e[\"source\"] = \"rom\"") and dsrc.contains("e[\"_disc_drive\"] = drive"),
			"Disc vom Laufwerk startet als Emulator-Spiel (über _launch_rom)")
	var esrc := (load("res://src/core/spieler_emus.gd") as GDScript).source_code
	check(esrc.contains("spieler_start(SpielerS.slots_now(), Pads.pads, SpielerS.mem_now(), benutzt)") and esrc.contains("var benutzt := Pads.benutzt_id()"),
			"vor dem Start: Spieler 1 = der zuletzt benutzte Controller")
	# Disc-Start mit PCSX2: dieselbe Datei und Regel wie ein Abbild (System ps2, exe aus den Emulatoren).
	var f: Array = E.files_for("pcsx2", "C:/Emu/PCSX2/pcsx2-qt.exe", "ps2", { "docs": "C:/Users/x/Documents", "appdata": "", "localappdata": "" })
	check(f.size() == 1 and str(f[0][0]) == "C:/Users/x/Documents/PCSX2/inis/PCSX2.ini" and str(f[0][1]) == "ps",
			"Disc-Start PCSX2: Dokumente\\PCSX2\\inis\\PCSX2.ini")


## Players 2, 3 and 4 are set up automatically at start in the same way as player 1.
func _mehr_spieler() -> void:
	var g4 := _g([0, 1, 2, 3], [0, 1, 2, 3], ["xbox"])
	var vier := [_pl(0, 0), _pl(1, 1, "Xbox Wireless Controller", G_XBOX, 1), _pl(2, 2, "Xbox Wireless Controller", G_XBOX, 2),
			_pl(3, 3, "Xbox Wireless Controller", G_XBOX, 3)]
	# PCSX2 mit vier: Multitap an Anschluss 1, Spieler 2 auf 2A und 1B, 3 auf 1C, 4 auf 1D.
	var r := E.plan_ps_start(PCSX2_STD, "pcsx2", vier, g4)
	var t := str(r.text)
	check(str(Ini.ini_get(t, "Pad", "MultitapPort1")) == "true" and str(r.mt) == "an", "PCSX2: vier Spieler → Multitap an Anschluss 1")
	check(str(Ini.ini_get(t, "Pad2", "Cross")) == "XInput-1/A" and str(Ini.ini_get(t, "Pad3", "Cross")) == "XInput-1/A"
			and str(Ini.ini_get(t, "Pad4", "Cross")) == "XInput-2/A" and str(Ini.ini_get(t, "Pad5", "Cross")) == "XInput-3/A",
			"Spieler 2 auf 2A und 1B (mit und ohne Multitap), 3 → 1C, 4 → 1D")
	check(str(Ini.ini_get(t, "Pad5", "Type")) == "DualShock2" and r.done == [1, 2, 3, 4], "alle vier eingerichtet")
	check(Ini.section_lines(t, "Hotkeys") == Ini.section_lines(PCSX2_STD, "Hotkeys"), "fremde Abschnitte bleiben")
	var r2 := E.plan_ps_start(t, "pcsx2", vier, g4.merged({ "mt_uzai": true }))
	check(str(r2.text) == t and str(r2.mt) == "", "zweiter Start mit vier: nichts mehr geschrieben")
	# Wieder nur zwei: den von Uzai eingeschalteten Multitap aus; einen selbst eingeschalteten nicht.
	var zwei: Array = [vier[0], vier[1], {}, {}]
	var aus := E.plan_ps_start(t, "pcsx2", zwei, g4.merged({ "mt_uzai": true }))
	check(str(Ini.ini_get(str(aus.text), "Pad", "MultitapPort1")) == "false" and str(aus.mt) == "aus", "zwei Spieler: Uzais Multitap wieder aus")
	var selbst := E.plan_ps_start(t, "pcsx2", zwei, g4)
	check(str(Ini.ini_get(str(selbst.text), "Pad", "MultitapPort1")) == "true" and str(selbst.mt) == "", "selbst eingeschalteter Multitap bleibt")
	# DuckStation: MultitapMode; nur an Anschluss 2 eingestellt: bleibt, Hinweis.
	var ds := "[Main]\nSettingsVersion = 3\n\n[Pad1]\nType = AnalogController\nCross = XInput-0/A\n"
	var rd := E.plan_ps_start(ds, "duckstation", [vier[0], {}, vier[2], {}], g4)
	check(str(Ini.ini_get(str(rd.text), "ControllerPorts", "MultitapMode")) == "Port1Only" and str(Ini.ini_get(str(rd.text), "Pad4", "Cross")) == "XInput-2/A",
			"DuckStation: Spieler 3 → Multitap Port1Only, [Pad4]")
	var p2 := ds + "\n[ControllerPorts]\nMultitapMode = Port2Only\n"
	var rp := E.plan_ps_start(p2, "duckstation", [vier[0], {}, vier[2], {}], g4)
	check(str(Ini.ini_get(str(rp.text), "ControllerPorts", "MultitapMode")) == "Port2Only" and Ini.section_lines(str(rp.text), "Pad4") == null
			and str(rp.log).contains("Anschluss 2"), "Multitap selbst an Anschluss 2: bleibt, Hinweis")
	check(E.plan_ps_start(ds, "duckstation", [vier[0], {}, {}, {}], g4).get("mt", "") == "", "ein Spieler: Multitap bleibt aus")
	# Eden: Spieler 2 mit demselben Modell bekommt die Belegung von Spieler 1 mit seinem Anschluss; die
	# GUID bleibt, wie Eden sie schrieb (auch mit Prüfsumme); ein anderes Modell: Hinweis.
	var qt := QT.replace("guid:030000005e040000130b000000007200", "guid:0300abcd5e040000130b000000007200")
	var ry := E.plan_yuzu_start(qt, [_pl(0, 0, "Xbox", G_XBOX, 0), _pl(1, 1, "Xbox", G_XBOX, 1), _pl(0, -1, "DualSense", G_DS, 0), {}])
	var ty := str(ry.text)
	check(str(Ini.ini_get(ty, "Controls", "player_1_button_a")) == "\"engine:sdl,port:1,guid:0300abcd5e040000130b000000007200,button:1\""
			and str(Ini.ini_get(ty, "Controls", "player_1_connected")) == "true", "Eden: Spieler 2 (gleiches Modell) → Belegung mit Anschluss 1, eingesteckt")
	check(Ini.ini_get(ty, "Controls", "player_2_button_a") == null and str(ry.log).contains("Spieler 3: DualSense einmal im Emulator belegen"),
			"Eden: anderes Modell ohne Belegung → Hinweis statt raten")
	check(ry.done == [2] and str(Ini.ini_get(ty, "Controls", "player_0_button_a")).contains("port:0"), "Spieler 1 bleibt")
	check(str(E.plan_yuzu_start(ty, [_pl(0, 0, "Xbox", G_XBOX, 0), _pl(1, 1, "Xbox", G_XBOX, 1), {}, {}]).text) == ty, "zweiter Start: nichts mehr")


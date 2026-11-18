extends Node
## Emulatoren laufen im Hintergrund weiter und lesen den Controller nur mit Fokus
## (src/core/emu_hintergrund.gd): Schlüssel je Emulator, nur diese Zeilen, alte Werte zurück (auch
## nach einem Absturz), nichts zurück, was jemand inzwischen selbst geändert hat, und klare Zeilen
## für launch.log, wo ein Emulator keine Einstellung hat.
##   UZAI_DATA=<leer> godot --headless --path . res://tests/logic_emu_hintergrund.tscn → „Ergebnis: alles ok“

const H := preload("res://src/core/emu_hintergrund.gd")
const Ini := preload("res://src/core/remote_play_pads.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Planen")
	var ra := "video_driver = \"d3d11\"\npause_nonactive = \"true\"\ninput_joypad_driver = \"xinput\"\n"
	var p := H.plan("retroarch", ra)
	check(str(Ini.ini_get(p.text, "", "pause_nonactive")) == "\"false\"" and str(Ini.ini_get(p.text, "", "input_joypad_background")) == "\"false\"",
			"RetroArch: weiterlaufen ohne Fokus, Controller nur mit Fokus")
	check(str(p.text).begins_with("video_driver = \"d3d11\"\npause_nonactive = \"false\"\ninput_joypad_driver") and (p.keys as Array).size() == 2,
			"RetroArch: nur diese Zeilen, Reihenfolge bleibt")
	check((p.keys as Array)[0].old == "\"true\"" and (p.keys as Array)[1].old == null, "alte Werte gemerkt (fehlte: null)")
	check(H.plan("retroarch", "pause_nonactive = \"false\"\ninput_joypad_background = \"false\"\n").keys.is_empty(), "schon richtig: nichts zu tun")
	var dol := "[Interface]\nPauseOnFocusLost = True\n[Input]\nBackgroundInput = True\n[Core]\nCPUThread = True\n"
	p = H.plan("dolphin", dol)
	check(str(Ini.ini_get(p.text, "Interface", "PauseOnFocusLost")) == "False" and str(Ini.ini_get(p.text, "Input", "BackgroundInput")) == "False"
			and str(Ini.ini_get(p.text, "Core", "CPUThread")) == "True", "Dolphin: Pause bei Fokusverlust aus, Hintergrund-Eingaben aus, Rest bleibt")
	check(H.plan("dolphin", "[Core]\nCPUThread = True\n").keys.is_empty(), "Dolphin ohne Schlüssel: Standard passt schon, nichts schreiben")
	p = H.plan("duckstation", "[Main]\nSettingsVersion = 3\nPauseOnFocusLoss = true\n")
	check(str(Ini.ini_get(p.text, "Main", "PauseOnFocusLoss")) == "false" and str(Ini.ini_get(p.text, "Main", "DisableBackgroundInput")) == "true",
			"DuckStation: weiterlaufen, Hintergrund-Eingaben aus")
	p = H.plan("pcsx2", "[UI]\nPauseOnFocusLoss = false\n")
	check(str(Ini.ini_get(p.text, "UI", "PauseOnFocusLoss")) == "true" and bool(p.anhalten) and (p.fehlt as Array).is_empty(),
			"PCSX2 liest den Controller auch im Hintergrund: ohne Fokus anhalten (weiter, sobald es wieder vorn ist)")
	check((p.keys as Array).size() == 1 and str(p.renderer).begins_with("automatisch"), "PCSX2 randlos und automatisch: nur die Pause, Grafik im Log")
	check(H.plan("pcsx2", "[UI]\nPauseOnFocusLoss = true\n").keys.size() == 0, "PCSX2 hält schon an: nichts ändern")
	check(not bool(H.plan("dolphin", "").anhalten), "Dolphin hört ohne Fokus weg: läuft weiter")
	var ps2 := "[UI]\nPauseOnFocusLoss = true\n[EmuCore/GS]\nRenderer = 15\nFullscreenMode = 3840 x 2160 @ 120 hz\nExclusiveFullscreenControl = -1\n"
	p = H.plan("pcsx2", ps2)
	check(str(Ini.ini_get(p.text, "EmuCore/GS", "FullscreenMode")) == "" and str(Ini.ini_get(p.text, "EmuCore/GS", "ExclusiveFullscreenControl")) == "-1"
			and str(p.renderer) == "Direct3D 12", "PCSX2 exklusiv (D3D12, „3840 x 2160 @ 120 hz“) → randlos; Steuerung für Vulkan bleibt")
	var zur := Ini.undo_text(str(p.text), { "keys": p.keys })
	check(str(Ini.ini_get(zur, "EmuCore/GS", "FullscreenMode")) == "3840 x 2160 @ 120 hz", "nach dem Spiel: exklusiver Modus wieder wie vorher")
	p = H.plan("pcsx2", "[EmuCore/GS]\nRenderer = 14\n")
	check(str(Ini.ini_get(p.text, "EmuCore/GS", "ExclusiveFullscreenControl")) == "0" and str(p.renderer) == "Vulkan",
			"PCSX2 mit Vulkan auf „automatisch“: exklusives Vollbild nie (der Treiber entschiede sonst selbst)")
	check(H.pcsx2_vollbild("[EmuCore/GS]\nExclusiveFullscreenControl = 1\nRenderer = 3\n").size() == 1
			and H.pcsx2_vollbild("[EmuCore/GS]\nExclusiveFullscreenControl = 0\nRenderer = 14\nFullscreenMode = Borderless Fullscreen\n").is_empty(),
			"„erlaubt“ wird „nie“; schon randlos: nichts")
	check(H.bericht("PCSX2", "pcsx2", true, H.plan("pcsx2", ps2)).contains("Vollbild randlos statt exklusiv"), "im Protokoll")
	p = H.plan("ppsspp", "[General]\nPauseOnLostFocus = True\n[Control]\nHapticFeedback = False\n")
	check(str(Ini.ini_get(p.text, "General", "PauseOnLostFocus")) == "False" and str(Ini.ini_get(p.text, "Control", "GamepadOnlyFocused")) == "True",
			"PPSSPP: weiterlaufen, Controller nur mit Fokus")
	var qt := "[UI]\npauseWhenInBackground\\default=false\npauseWhenInBackground=true\n"
	p = H.plan("yuzu", qt)
	check(H.plan("yuzu", qt).keys.is_empty() and bool(p.anhalten), "Eden & Co. (Controller im Hintergrund): hält ohne Fokus an – war schon so")
	qt = "[UI]\npauseWhenInBackground\\default=true\npauseWhenInBackground=false\n"
	p = H.plan("yuzu", qt)
	check(str(Ini.ini_get(p.text, "UI", "pauseWhenInBackground")) == "true" and str(p.text).contains("pauseWhenInBackground=true")
			and not str(p.text).contains(" = "), "Eden: Standard (weiterlaufen) → anhalten, Schreibweise der Datei bleibt")
	p = H.plan("cemu", "irgendwas")
	check(p.keys.is_empty() and p.text == "irgendwas" and p.fehlt == ["pause", "eingabe"], "unbekannter Emulator: nichts anfassen")
	check(H.art("eden", "C:/e/eden.exe") == "yuzu" and H.art("", "D:/RA/retroarch.exe") == "retroarch" and H.art("x", "C:/p/PPSSPPWindows64.exe") == "ppsspp",
			"Art nach Kennung oder Dateiname")

	print("Protokoll")
	var b := H.bericht("PCSX2", "pcsx2", true, H.plan("pcsx2", "[UI]\nPauseOnFocusLoss = false\n"))
	check(b.contains("hält ohne Fokus an") and b.contains("PauseOnFocusLoss=true") and not b.contains("kann das Spiel Eingaben mitlesen"), b)
	b = H.bericht("RetroArch", "retroarch", true, H.plan("retroarch", "pause_nonactive = \"false\"\ninput_joypad_background = \"false\"\n"))
	check(b.contains("war schon so") and b.contains("Controller nur mit Fokus"), b)
	check(H.bericht("Cemu", "cemu", false, {}).contains("keine Einstellung"), "unbekannt: klar im Log")

	print("Dateien und zurück")
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	var dir := root.path_join("emu_hg/RetroArch")
	DirAccess.make_dir_recursive_absolute(dir)
	var cfg := dir.path_join("retroarch.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string(ra)
	f.close()
	var env := { "docs": root.path_join("nirgends_docs"), "appdata": root.path_join("nirgends_app"), "localappdata": root.path_join("nirgends_local") }
	check(H.datei_ok(cfg, [dir]) and not H.datei_ok(dir.path_join("../RetroArch/retroarch.cfg"), [dir]) and not H.datei_ok(cfg, [root.path_join("anders")]),
			"Pfad: nur im Ordner des Emulators, kein „..“")
	Config.set_value(H.RESTORE_KEY, [])
	# Wie im Betrieb: RetroArch ist eingetragen – nur unter den Ordnern eingetragener Emulatoren stellt zurueck() zurück.
	Config.set_value("emulators.retroarch.exe", dir.path_join("retroarch.exe"))
	var r := H.vor_start("retroarch", dir.path_join("retroarch.exe"), "RetroArch", env)
	var jetzt := FileAccess.get_file_as_string(cfg)
	check((r.done as Array).size() == 1 and jetzt.contains("pause_nonactive = \"false\"") and jetzt.contains("input_joypad_background = \"false\""),
			"vor dem Start geschrieben")
	check(not FileAccess.file_exists(cfg + ".uzai-neu") and (Config.get_value(H.RESTORE_KEY, []) as Array).size() == 1,
			"keine halbe Datei, Rücksicherung in Config")
	check(H.zurueck() == 1 and FileAccess.get_file_as_string(cfg) == ra, "nach dem Spiel: genau wie vorher")
	check((Config.get_value(H.RESTORE_KEY, []) as Array).is_empty() and H.zurueck() == 0, "danach nichts mehr offen")
	# RetroArch schreibt beim Beenden alles neu; hat jemand den Wert im Spiel selbst geändert, bleibt er.
	H.vor_start("retroarch", dir.path_join("retroarch.exe"), "RetroArch", env)
	f = FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("video_driver = \"d3d11\"\npause_nonactive = \"true\"\ninput_joypad_driver = \"xinput\"\ninput_joypad_background = \"false\"\n")
	f.close()
	H.zurueck()
	var nach := FileAccess.get_file_as_string(cfg)
	check(nach.contains("pause_nonactive = \"true\"") and not nach.contains("input_joypad_background"), "selbst Geändertes bleibt, Uzais Wert geht")
	Config.set_value(H.KEY_AN, false)
	f = FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string(ra)
	f.close()
	r = H.vor_start("retroarch", dir.path_join("retroarch.exe"), "RetroArch", env)
	check((r.done as Array).is_empty() and FileAccess.get_file_as_string(cfg) == ra, "ausgeschaltet: nichts")
	Config.set_value(H.KEY_AN, null)
	# Byte für Byte: BOM bleibt, fremde Kodierung (Latin-1) wird nicht angefasst.
	var mit_bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	mit_bom.append_array(ra.to_utf8_buffer())
	f = FileAccess.open(cfg, FileAccess.WRITE)
	f.store_buffer(mit_bom)
	f.close()
	r = H.vor_start("retroarch", dir.path_join("retroarch.exe"), "RetroArch", env)
	var nb := FileAccess.get_file_as_bytes(cfg)
	check((r.done as Array).size() == 1 and nb.size() > 3 and nb[0] == 0xEF and nb[1] == 0xBB and nb[2] == 0xBF, "BOM bleibt beim Einstellen")
	H.zurueck()
	check(FileAccess.get_file_as_bytes(cfg) == mit_bom, "und nach dem Spiel Byte für Byte wie vorher")
	var latin := ra.to_utf8_buffer()
	latin.append_array(PackedByteArray([0x23, 0x20, 0xE4, 0x0A]))   # "# ä" in Latin-1
	f = FileAccess.open(cfg, FileAccess.WRITE)
	f.store_buffer(latin)
	f.close()
	r = H.vor_start("retroarch", dir.path_join("retroarch.exe"), "RetroArch", env)
	check((r.done as Array).is_empty() and FileAccess.get_file_as_bytes(cfg) == latin and str(r.log).contains("Zeichenkodierung"),
			"fremde Kodierung: nicht anfassen, im Log")
	f = FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string(ra)
	f.close()
	r = H.vor_start("pcsx2", root.path_join("emu_hg/PCSX2/pcsx2-qt.exe"), "PCSX2", env)
	check((r.done as Array).is_empty() and str(r.log).contains("nicht gefunden"), "ohne Datei: nichts anlegen, im Log")
	r = H.vor_start("cemu", root.path_join("emu_hg/Cemu/Cemu.exe"), "Cemu", env)
	check((r.done as Array).is_empty() and str(r.log).contains("keine Einstellung"), "Cemu: keine Einstellung, im Log")
	# Abgestürzt mit offener Rücksicherung: ein Eintrag auf eine fremde Datei wird nie angefasst.
	Config.set_value(H.RESTORE_KEY, [{ "file": root.path_join("emu_hg/fremd.txt"), "keys": [] }, "unsinn", { "file": cfg, "keys": "kaputt" }])
	check(H.zurueck() == 0, "kaputte Rücksicherung: nichts geschrieben")

	print("Im Launcher")
	var ls := FileAccess.get_file_as_string("res://src/core/launcher.gd")
	var a := ls.find("func _launch_rom(")
	var lr := ls.substr(a, ls.find("\nfunc ", a + 5) - a)
	check(lr.find("_hintergrund_einrichten(cmd)") > 0 and lr.find("_hintergrund_einrichten(cmd)") < lr.find("_start_process("), "vor dem Start des Emulators")
	a = ls.find("func _finish(")
	check(ls.substr(a, ls.find("\nfunc ", a + 5) - a).contains("EmuHintergrund.zurueck()"), "nach dem Spiel zurück")
	a = ls.find("func _restore_pads(")
	check(ls.substr(a, ls.find("\nfunc ", a + 5) - a).contains("EmuHintergrund.zurueck()"), "nach einem Absturz beim nächsten Start zurück")
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

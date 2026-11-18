extends Node
## „Nach dem Schließen im Hintergrund bereit“: wann der Wächter starten darf, sein Auftrag, die
## Einstellung und der Wächter-Teil des Helfer-Skripts. Aufruf:
##   godot --headless --path . res://tests/logic_wecken.tscn   → „Ergebnis: alles ok“
## Mit UZAI_HELPER_SHELL=<pwsh> läuft der Wächter zusätzlich einmal unter PowerShell 7 (ohne XInput
## muss er sich sofort sauber beenden).

const HelperScript := preload("res://src/core/helper.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Wann der Wächter starten darf")
	check(HelperScript.wake_allowed(true, PackedStringArray(), false), "normales Uzai: ja")
	check(HelperScript.wake_allowed(true, PackedStringArray(["--windowed"]), false), "auch im Fenster")
	check(HelperScript.wake_allowed(true, PackedStringArray([HelperScript.WOKEN]), false), "auch nach dem Wecken wieder")
	check(not HelperScript.wake_allowed(false, PackedStringArray(), false), "Einstellung aus: nein")
	check(not HelperScript.wake_allowed(true, PackedStringArray(), true), "zweites Uzai (gibt nur weiter): nein")
	check(not HelperScript.wake_allowed(true, PackedStringArray(["--demo"]), false), "Vorführmodus: nein")
	check(not HelperScript.wake_allowed(true, PackedStringArray(["--no-boot"]), false), "Proben (--no-boot): nein")
	check(not HelperScript.wake_allowed(true, PackedStringArray(["--uzai-test=/tmp/x"]), false), "Rundgang: nein")

	print("Auftrag")
	var job := HelperScript.wake_payload("C:/Spiele/Uzai Konsole/Uzai.exe", PackedStringArray(["--headless", "--path", "C:/p"]), true,
			"C:/Users/a/AppData/Roaming/Uzai/uzai.pid", 4242)
	check(str(job.exe) == "C:\\Spiele\\Uzai Konsole\\Uzai.exe", "Programm mit Backslashes")
	check(str(job.dir) == "C:\\Spiele\\Uzai Konsole", "Arbeitsordner ist der Programmordner")
	check(job.args == ["--path", "C:/p", "--", HelperScript.WOKEN], "ohne --headless, nur --woken als eigenes Argument (%s)" % str(job.args))
	check(str(job.pid_file) == "C:\\Users\\a\\AppData\\Roaming\\Uzai\\uzai.pid", "uzai.pid als Zeichen für „Uzai lief wieder an“")
	check(int(job.parent) == 4242 and bool(job.combo), "wartet auf dieses Uzai, View + Start wie eingestellt")
	var back: Variant = JSON.parse_string(Marshalls.base64_to_utf8(Marshalls.utf8_to_base64(JSON.stringify(job))))
	check(back is Dictionary and str(back.exe) == str(job.exe), "übersteht Base64 + JSON (Umlaute, Leerzeichen)")

	print("Einstellung")
	check(bool(Config.DEFAULTS.system.get("background_wake", false)), "standardmäßig an")
	check(bool(Config.get_value("system.background_wake", false)), "in den geladenen Einstellungen da")
	if not Config.is_windows() and HelperScript._test_shell() == "":
		check(not Helper.wake_active(), "ohne Windows: nicht aktiv (Ausschalten-Menü wie bisher)")
		check(not Helper.start_wake_watch(), "ohne Windows: startet keinen Wächter")

	print("Helfer-Skript")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var at_watch := ps.find("if ($Watch -ne '')")
	check(ps.contains("[string]$Watch = ''"), "Parameter -Watch")
	check(at_watch > 0 and at_watch < ps.find("public static class UzWin"), "Wächter vor dem großen C#-Teil (übersetzt nur seinen kleinen)")
	var watch := ps.substr(at_watch, ps.find("public static class UzWin") - at_watch)
	check(watch.contains("EntryPoint = \"#100\""), "liest die Guide-Taste wie der Controller-Wächter (XInputGetStateEx)")
	check(watch.contains("SetProcessWorkingSetSize") and watch.contains("0x4000"), "gibt Arbeitsspeicher frei, niedrige Priorität")
	check(watch.contains("SetPriorityClass(GetCurrentProcess(), 0x20)"), "vor dem Start von Uzai wieder normale Priorität")
	check(watch.contains("Local\\UzaiGuideWake"), "nur ein Wächter je Sitzung")
	check(not watch.to_lower().contains("hkcu:") and not watch.to_lower().contains("registry") and not watch.to_lower().contains("schtasks"),
			"keine Registry, keine geplanten Aufgaben")
	check(watch.contains("FullscreenInFront") and watch.contains("HOLD_MS"), "Vollbild-Programm vorn: nur langes Halten weckt")
	check(watch.contains("public short RY; public uint Reserved; }"), "XInputGetStateEx: Platz für die vier Bytes mehr (XINPUT_STATE_EX)")

	print("Startbildschirm vorn halten (UzCover)")
	var at_cover := ps.find("public static class UzCover")
	var cover := ps.substr(at_cover, ps.find("public static class UzCursor") - at_cover)
	check(at_cover > 0 and cover.contains("public static void Stop(IntPtr h, bool keepTop, bool behindFront)"), "Stopp gibt den obersten Platz selbst frei")
	var loop := cover.substr(cover.find("static void Loop()"))
	check(loop.find("lock (gate) {") >= 0 and loop.find("lock (gate) {") < loop.find("SetWindowPos"),
			"Anheben nur unter der Sperre (kein Anheben mehr nach dem Stopp)")
	check(cover.contains("new IntPtr(-2)") and cover.contains("GetForegroundWindow()"), "nicht mehr oben, beim Abgeben hinter den wartenden Dialog")
	check(cover.contains("Cloaked(w)"), "versteckte Fenster (Startmenü, Store-Apps) zählen nicht als Verdeckung")
	check(ps.contains("[UzCover]::Stop([IntPtr]([long]$a.hwnd), [bool]$a.top, [bool]$a.behind_front)"), "Befehl cover reicht top und behind_front weiter")
	check(ps.count("public uint Reserved; }") == 2, "beide XInputGetStateEx-Strukturen mit Platz")

	if HelperScript._test_shell() != "":
		print("Wächter unter PowerShell 7")
		var dir := OS.get_cache_dir().path_join("uzai-wecken-%d" % Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(dir)
		var script := dir.path_join("uzai-helper.ps1")
		var f := FileAccess.open(script, FileAccess.WRITE)
		f.store_string(ps)
		f.close()
		var p2 := { "exe": "/bin/false", "dir": dir, "args": ["--", "--woken"], "combo": true, "pid_file": dir.path_join("uzai.pid"), "parent": 0 }
		var t0 := Time.get_ticks_msec()
		var out: Array = []
		var code := OS.execute(HelperScript._test_shell(),
				PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Watch", Marshalls.utf8_to_base64(JSON.stringify(p2))]), out, true)
		check(code == 0, "beendet sich ohne XInput sauber (Code %d)" % code)
		check(Time.get_ticks_msec() - t0 < 30000, "und gleich (%d ms)" % (Time.get_ticks_msec() - t0))
		# Echter Start wie beim Schließen: Der Wächter wartet auf das Ende dieses Prozesses.
		check(Helper.wake_active() and Helper.start_wake_watch() and Helper.wake_started, "Helper.start_wake_watch startet den Wächter")
		check(Helper.start_wake_watch(), "zweiter Aufruf startet keinen zweiten")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

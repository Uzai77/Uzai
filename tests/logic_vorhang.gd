extends Node
## Vorhang zwischen Uzai und dem Spiel (src/core/vorhang.gd, UzEbenen im Helfer) ohne Bildschirm:
## Aufträge je Anlass, Zeitgrenzen, wann er nach der Rückkehr geht, wo die Abläufe ihn ziehen.
## Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich: C# übersetzt mit C# 5, die Regeln des Fadens (Loch,
## Vollbild, Zeitgrenze) und dass die Befehle nur Zahlen annehmen.
## Aufruf: godot --headless --path . res://tests/logic_vorhang.tscn

const V := preload("res://src/core/vorhang.gd")
const HelperScript := preload("res://src/core/helper.gd")
const Fenster := preload("res://src/main_fenster.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _fn(src: String, kopf: String) -> String:
	var a := src.find(kopf)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)


func _ready() -> void:
	print("Aufträge")
	var st := V.auftrag("start", 4242)
	check(st.an == true and int(st.hwnd) == 4242 and int(st.farbe) == 0 and int(st.max_ms) == V.START_MS and st.loch == true and st.loch_uzai == false,
			"Übergabe ans Spiel: schwarz, kurz, wartende Fenster ausgespart, Uzai nicht")
	check(int(st.loch_ms) == V.LOCH_MS and V.LOCH_MS >= 300 and V.LOCH_MS <= 1500,
			"Übergabe: Loch erst nach %d ms – ein Ladefenster, das gleich wieder geht, bleibt verdeckt" % V.LOCH_MS)
	var sr := V.auftrag("starter", 4242)
	check(sr.loch == true and int(sr.max_ms) == V.STARTER_MS and V.STARTER_MS > V.START_MS and V.STARTER_MS <= 60000,
			"Starter vorn (Steam-Dialog, Launcher): länger schwarz um ihn, bis das Spiel selbst kommt")
	var be := V.auftrag("beenden", 4242)
	check(be.an == true and be.loch == false and int(be.max_ms) == V.BEENDEN_MS and int(be.farbe) == 0 and int(be.ein_ms) == V.EIN_MS,
			"Beenden (Emulator): weich ins Schwarz, auch seine Rückfrage verdeckt, mit Zeitgrenze")
	check(int(st.ein_ms) == 0 and int(V.auftrag("ende", 1).ein_ms) == 0, "Start und Rückkehr: sofort ganz da (Uzai stellt erst danach um)")
	var wa := V.auftrag("warten", 4242, Color("#101820"))
	check(wa.an == true and int(wa.farbe) == 0x101820 and int(wa.max_ms) == V.WARTEN_MS and wa.loch_uzai == true and int(wa.loch_ms) == 0,
			"Dialog wartet: Uzais Grundfarbe, Uzai selbst ausgespart, Loch sofort (er wartet schon)")
	var en := V.auftrag("ende", 4242)
	check(en.an == true and int(en.max_ms) == V.ENDE_MS and en.loch == false and en.loch_uzai == false, "Rückkehr: alles gedeckt, bis Uzai gezeichnet hat")
	check(V.auftrag("", 4242).an == false and V.auftrag("weg", 0).an == false and int(V.auftrag("x", 1).weich_ms) == V.WEICH_MS,
			"alles andere zieht ihn weich auf")
	check(V.auftrag("start", 0).an == false and V.auftrag("start", -3).an == false, "ohne Uzais Fenster nie zu")
	for a in V.ANLAESSE:
		var j := V.auftrag(str(a), 1)
		check(int(j.max_ms) >= 200 and int(j.max_ms) <= V.MAX_MS, "„%s“: Zeitgrenze %d ms innerhalb dessen, was der Helfer annimmt" % [a, int(j.max_ms)])
		for k in j.keys():
			check(j[k] is int or j[k] is bool or (k == "loch_pids" and (j[k] as Array).all(func(x: Variant) -> bool: return x is int)),
					"„%s“: nur Zahlen und Ja/Nein (%s)" % [a, k])
	check(be.immer == true and V.auftrag("start", 1).immer == false and V.auftrag("ende", 1).immer == false,
			"„beenden“ deckt auch über dem Spiel im Vollbild (Uzai beendet es gleich hart) – sonst endet der Vorhang, wenn das Spiel deckt")
	var sl := V.auftrag("schliessen", 4242, Color.BLACK, [4711, 4711, 3, 0, "x", 815.0, -2])
	check(sl.an == true and sl.loch == true and sl.loch_uzai == false and int(sl.max_ms) == V.SCHLIESSEN_MS and int(sl.loch_ms) == V.LOCH_MS
			and sl.immer == false and int(sl.farbe) == 0, "Spielfenster weg, Spiel noch nicht zu: schwarz, Loch erst nach der Frist")
	check(sl.loch_pids == [4711, 815], "Loch nur um Fenster des Spiels: nur Prozessnummern über 4, ohne Doppelte (%s)" % str(sl.loch_pids))
	var viele: Array = []
	for i in 200:
		viele.append(100 + i)
	check((V.auftrag("schliessen", 1, Color.BLACK, viele).loch_pids as Array).size() == V.LOCH_PIDS_MAX, "höchstens %d Prozesse" % V.LOCH_PIDS_MAX)
	check(not V.auftrag("start", 1, Color.BLACK, [4711]).has("loch_pids"), "beim Start ein Loch um jedes wartende Fenster (Steam-Dialog) wie bisher")
	check(V.SCHLIESSEN_MS >= int(preload("res://src/core/launcher.gd").QUIT_MAX_S * 1000.0) and V.SCHLIESSEN_MS <= 60000,
			"„schliessen“ hält mindestens so lange wie der Wächter fürs Beenden, nie lange darüber")
	check(V.farbe(Color(1, 0, 0)) == 0xFF0000 and V.farbe(Color("#0a0b0c")) == 0x0a0b0c, "Farbe als 0xRRGGBB")
	check(V.wache(5, 77).an == true and int(V.wache(5, 77).spiel) == 77 and int(V.wache(5, 77).max_ms) == V.WACHE_MS, "Wache auf das Spielfenster")
	check(V.wache(5, 0).an == false and V.wache(0, 77).an == false, "ohne Spielfenster keine Wache")

	print("Nach der Wache")
	check(V.nach_wache(200, true, false, 0, false, 3000) == "schliessen", "Uzai beendet gerade: gleich „schliessen“ (kein Loch um fremde Fenster)")
	check(V.nach_wache(200, false, false, 0, false, 3000) == "", "endet von selbst: erst kurz nachsehen (meist ist es gleich zu)")
	check(V.nach_wache(3000, false, false, 0, false, 3000) == "schliessen", "läuft nach %d ms noch ohne Fenster: „schliessen“ statt Start-Vorhang mit Loch um jedes Fenster" % 3000)
	check(V.nach_wache(500, false, true, 2, false, 3000) == "folgen", "neues Spielfenster im Vollbild: Wache folgt, Vorhang geht")
	check(V.nach_wache(500, false, true, 1, false, 3000) == "", "… erst, wenn es so bleibt")
	check(V.nach_wache(5000, true, true, 0, true, 3000) == "folgen", "Fenster des Spiels vorn (Rückfrage, Starter): Wache folgt ihm, es hat sein Loch")
	check(V.nach_wache(5000, true, false, 0, true, 3000) == "", "„schliessen“ steht: nur noch warten, bis Uzai das Ende sieht")

	print("Rückkehr")
	check(not V.darf_weg(0, true, 100), "noch nichts gezeichnet: bleibt")
	check(not V.darf_weg(1, true, 100), "ein Bild reicht nicht (das erste zeigt noch das alte)")
	check(V.darf_weg(2, true, 80), "zwei Bilder und vorn: weg")
	check(not V.darf_weg(5, false, 300) and not V.darf_weg(5, false, 650), "gezeichnet, aber nicht vorn: warten (sonst läge die Taskleiste über Uzai)")
	check(V.darf_weg(5, false, V.NICHT_VORN_MS), "… nicht ewig (%d ms)" % V.NICHT_VORN_MS)
	check(V.darf_weg(0, false, V.ENDE_MS), "Zeitgrenze: spätestens nach %d ms" % V.ENDE_MS)
	check(V.START_MS <= 10000 and V.WACHE_MS <= 10000 and V.ENDE_MS <= V.WACHE_MS and V.BEENDEN_MS <= 15000 and V.NICHT_VORN_MS < V.ENDE_MS,
			"schwarz nie lange")

	print("Abläufe")
	var eb := _src("res://src/main_ebenen.gd")
	var mn := _src("res://src/main.gd")
	var fe := _src("res://src/main_fenster.gd")
	var win := _fn(eb, "func _on_game_window(")
	check(win.find("await _vorhang(\"start\"") >= 0 and win.find("await _vorhang(\"start\"") < win.find("await _park()"),
			"Spielstart: Vorhang zu, bevor Uzai durchsichtig wird")
	check(win.contains("\"start\" if Launcher.window_is_game else \"starter\"") and _fn(fe, "func _on_game_window_changed(").contains("_vorhang(\"start\")"),
			"erst ein Starter: Vorhang „starter“, kommt das Spielfenster, die übliche Frist")
	check(win.find("if not Launcher.filter_active() and not app:") >= 0 and win.find("if not Launcher.filter_active() and not app:") < win.find("await _vorhang(\"start\""),
			"Bildfilter läuft schon: kein Vorhang über ShaderGlass (er deckte das gefilterte Bild bis auf einen Ausschnitt)")
	var vh := _fn(fe, "func _vorhang(")
	check(vh.contains("-> bool") and vh.contains("\"sichtbar\""), "Uzai wartet, bis der Helfer meldet: der Vorhang steht auf dem Bildschirm")
	var rk := _fn(fe, "func _vorhang_nach_rueckkehr(")
	check(rk.contains("Window.MODE_MINIMIZED") and rk.contains("b0 < 0"), "Rückkehr: Bilder zählen erst, wenn Uzais Fenster wieder offen ist")
	check(_fn(fe, "func _park(").contains("vorhang_wache()"), "im Spiel: Wache aufs Spielfenster")
	var ende := _fn(mn, "func _on_game_ended(")
	check(ende.find("await _vorhang(\"ende\")") >= 0 and ende.find("await _vorhang(\"ende\")") < ende.find("_restore_window()")
			and ende.contains("_vorhang_nach_rueckkehr()"), "Spielende: Vorhang zu, Uzai zurück, Vorhang weg, wenn Uzai gezeichnet hat")
	check(_fn(mn, "func _on_game_failed(").contains("_vorhang(\"\")"), "Fehlstart: Vorhang auf")
	check(_fn(fe, "func _watch_cover(").contains("_vorhang(\"warten\")"), "wartendes Fenster beim Start: Desktop bleibt verdeckt")
	var aus := _fn(fe, "func _vorhang_ausgeloest(")
	check(_src("res://src/main_guide.gd").contains("_vorhang_ausgeloest()") and aus.contains("Launcher.schnell_pruefen()"),
			"Vorhang zu → Uzai sieht sofort nach, ob das Spiel aus ist")
	check(aus.contains("Vorhang.nach_wache(") and aus.contains("Launcher.quitting") and aus.contains("await _vorhang(\"schliessen\", pids)")
			and not aus.contains("_vorhang(\"start\")") and Fenster.WACHE_LAEUFT_MS <= V.WACHE_MS,
			"läuft das Spiel weiter (speichert, fährt herunter), wird er nach höchstens %d ms zu „schliessen“ – nie mehr Loch um fremde Fenster" % Fenster.WACHE_LAEUFT_MS)
	check(aus.contains("fg_full") and aus.contains("\"vorhang-wache\"") and aus.contains("Launcher.spiel_pids()"),
			"neues Spielfenster: die Wache folgt ihm (Prozesse samt Kindern)")
	check(_fn(fe, "func vorhang_wache(").contains("_spiel_weg = false"), "Wache wieder scharf: der Guide liegt wieder durchsichtig über dem Spiel")
	var ls := _src("res://src/core/launcher.gd")
	check(_fn(ls, "func schnell_pruefen(").contains("POLL_SCHNELL_S") and _fn(ls, "func _finish(").contains("_timer.wait_time = POLL_S"),
			"schneller Takt nur kurz, danach wieder normal")
	check(_fn(fe, "func vorhang_wache(").contains("Fernsehspiel.uzai_vorn(_tv)"), "im Zimmer: keine Wache (Uzai deckt selbst)")
	for c in ["vorhang", "vorhang-wache"]:
		check(c in HelperScript.EBENEN and c in HelperScript.FAST, "„%s“: schneller Weg, immer derselbe Helfer-Prozess" % c)
	check(HelperScript.ebenen_weg(true) == "fast" and HelperScript.ebenen_weg(false) == "main",
			"Vorhang auf dem schnellen Weg, sobald sein Prozess läuft – auch wenn er noch nicht bereit ist (früher für immer im Hauptweg)")
	var hr := _fn(_src("res://src/core/helper.gd"), "func run(")
	check(hr.contains("ebenen_weg(_fast.io != null)") and not hr.contains("_ebenen_lane = l\n"), "run(): Ebenen nie nach dem gerade bereiten Weg")
	check(hr.find("while not l.ready:") > hr.find("ebenen_weg("), "… der Befehl wartet, bis der schnelle Weg bereit ist")
	check(Fenster.cover_should_yield({ "fg_hwnd": 9, "fg_pid": 3, "fg_w": 500, "fg_h": 300 }, 1), "kleines fremdes Fenster bekommt weiter den Vorrang")

	print("Helfer-Quellen")
	var ps := _src("res://helper/uzai-helper.ps1").replace("\r\n", "\n")
	for c in ["vorhang", "vorhang-wache"]:
		check(ps.count("        '%s' {" % c) == 1, "fester Befehl „%s“ genau einmal" % c)
	for c in ["tv-bild", "fenster-zeigen"]:
		check(ps.count("        '%s' {" % c) == 0 and not (c in HelperScript.FAST), "„%s“ ist weg (kein Live-Fenster über dem Fernseher mehr)" % c)
	var cs_a := ps.find("$script:EbenenSrc = @'")
	var cs := ps.substr(cs_a, ps.find("'@", cs_a) - cs_a)
	check(cs.contains("0x08000000u") and cs.contains("0x00000080u") and cs.contains("0x00000020u"), "Fenster: nie aktiv, ohne Taskleiste, durchlässig")
	for bad in ["SetForegroundWindow", "keybd_event", "SendInput", "AttachThreadInput", "Process.Start", "OpenProcess", "File."]:
		check(not cs.contains(bad), "UzEbenen ohne %s" % bad)
	check(cs.contains("MsgWaitForMultipleObjects") and cs.contains("jetzt >= bis") and cs.contains("wecker.Set()"),
			"eigener Faden mit Zeitgrenze, von Aufträgen sofort geweckt (früher bis zu 120 ms Schlaf)")
	check(cs.contains("UpdateWindow(vWnd); DwmFlush();") and cs.find("DwmFlush") < cs.find("vErledigt = zeigen"),
			"„steht“ erst, wenn gemalt und von Windows dargestellt")
	check(cs.contains("Ueberdeckt(!lochAn, mon)") and cs.contains("SetWindowPos(vWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NUR_Z)"),
			"Taskleiste darüber (bzw. beim Ende jedes Fenster): Vorhang legt sich zurück nach oben")
	check(cs.contains("SetWinEventHook(3, 3, IntPtr.Zero, evProc, 0, 0, 2)") and cs.contains("SetWinEventHook(0x8001, 0x8003, IntPtr.Zero, evProc, (uint)pid, 0, 0)")
			and cs.count("SetWinEventHook(") == 3,
			"Meldungen von Windows nur außerhalb des fremden Prozesses (WINEVENT_OUTOFCONTEXT, nichts wird injiziert)")
	check(cs.contains("timeBeginPeriod(1)") and cs.contains("timeEndPeriod(1)") and cs.contains("bool fein = vSichtbar"),
			"feiner Takt nur, solange der Vorhang steht")
	check(cs.contains("Versteckt(fg)") and cs.contains("IsHungAppWindow(fg)"), "Vollbild zählt erst, wenn es sich zeigt und antwortet")
	check(cs.contains("int roh = Beim(Art(") and cs.contains("vImmer = false;\n                vLochPids = null;"),
			"Beenden: „immer“ und Loch nur ums Spiel gelten im Faden; die Wache setzt beides zurück")
	var fo_a := ps.find("    public static bool Focus(IntPtr h) {")
	var fo := ps.substr(fo_a, ps.find("\n    }\n", fo_a) - fo_a)
	check(fo.contains("!IsHungAppWindow(fgw)") and fo.contains("if (koppeln) AttachThreadInput(me, fg, true);"),
			"Fokus koppelt sich nie an ein hängendes Fenster (sonst hinge der Helfer mit – Vorhang und Beenden kamen nicht mehr durch)")
	var cmd := ps.substr(ps.find("        'vorhang' {"), ps.find("        'cursor-park' {") - ps.find("        'vorhang' {"))
	check(cmd.contains("Get-Zahl $a.max_ms 200 180000") and cmd.contains("Get-Zahl $a.farbe 0 16777215") and cmd.contains("Get-Hwnd $a.hwnd")
			and cmd.contains("Get-Zahl $a.loch_ms 0 5000") and cmd.contains("Get-Zahl $a.ein_ms 0 1000") and cmd.contains("Get-Zahl $a.quelle 5 2147483647"), "Befehle prüfen jede Zahl")
	check(cmd.contains("Get-Zahl $_ 5 2147483647") and cmd.contains("Select-Object -First 64") and cmd.contains("($a.immer -is [bool] -and $a.immer)"),
			"„loch_pids“ nur als Prozessnummern (höchstens 64), „immer“ nur als echtes Ja")
	check(cmd.contains("[UzEbenen]::Stand($n, 800)") and cmd.contains("sichtbar = ($stand -eq 1)"), "„vorhang“ antwortet erst, wenn er steht (höchstens 0,8 s)")
	check(not cmd.contains("SetForegroundWindow") and not cmd.contains("Focus("), "nichts davon aktiviert ein Fenster")
	await _pwsh()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _pwsh() -> void:
	if HelperScript._test_shell() == "":
		print("  (PowerShell-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")
		return
	print("Helfer unter PowerShell 7")
	var dir := OS.get_cache_dir().path_join("uzai-vorhang-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("uzai-helper.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string(_src("res://helper/uzai-helper.ps1"))
	f.close()
	var probe := dir.path_join("probe.ps1")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	pf.store_string("""
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$cs = [regex]::Match($src, '(?s)\\$script:EbenenSrc = @''\\n(.*?)\\n''@').Groups[1].Value
try { Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; "CS ok" } catch { "CS FEHLER " + $_.Exception.Message }
$m = New-Object UzEbenen+RECT; $m.Left = 0; $m.Top = 0; $m.Right = 1920; $m.Bottom = 1080
$f = New-Object UzEbenen+RECT; $f.Left = -1; $f.Top = 0; $f.Right = 1921; $f.Bottom = 1081
$d = New-Object UzEbenen+RECT; $d.Left = 660; $d.Top = 340; $d.Right = 1260; $d.Bottom = 740
$n = New-Object UzEbenen+RECT; $n.Left = 2000; $n.Top = 0; $n.Right = 2600; $n.Bottom = 400
$m2 = New-Object UzEbenen+RECT; $m2.Left = 1920; $m2.Top = 0; $m2.Right = 3840; $m2.Bottom = 1080
"ART " + [UzEbenen]::Art($m, $m, $true, $true, $f, $true) + " " + [UzEbenen]::Art($m, $m, $true, $true, $d, $true) + " " + [UzEbenen]::Art($m, $m, $false, $false, $d, $true) + " " + [UzEbenen]::Art($m, $m2, $true, $true, $n, $true) + " " + [UzEbenen]::Art($m, $m, $true, $true, $d, $false) + " " + [UzEbenen]::Art($m, $m, $true, $true, $f, $false) + " " + [UzEbenen]::Art($m, $m, $true, $false, $f, $true) + " " + [UzEbenen]::Art($m, $m2, $true, $true, $m2, $true)
"LOCH " + [UzEbenen]::MitLochfrist(2, 1000, 500, 700) + " " + [UzEbenen]::MitLochfrist(2, 1300, 500, 700) + " " + [UzEbenen]::MitLochfrist(1, 0, 0, 700) + " " + [UzEbenen]::MitLochfrist(2, 5, 5, 0)
"OBEN " + [UzEbenen]::ObenStoert($false, 'Shell_TrayWnd') + " " + [UzEbenen]::ObenStoert($false, 'Shell_SecondaryTrayWnd') + " " + [UzEbenen]::ObenStoert($false, 'ShaderGlass') + " " + [UzEbenen]::ObenStoert($true, 'Irgendwas')
"EIN " + [UzEbenen]::EinAlpha(1000, 1000, 180) + " " + [UzEbenen]::EinAlpha(1000, 1090, 180) + " " + [UzEbenen]::EinAlpha(1000, 1180, 180) + " " + [UzEbenen]::EinAlpha(1000, 1000, 0)
$v = [long]0
$a1 = [UzEbenen]::Weiter(1000, 5000, 0, [ref]$v); $a2 = [UzEbenen]::Weiter(1200, 5000, 0, [ref]$v); $a3 = [UzEbenen]::Weiter(1450, 5000, 0, [ref]$v)
$v = [long]0
$b1 = [UzEbenen]::Weiter(1000, 5000, 2, [ref]$v); $b2 = [UzEbenen]::Weiter(5000, 5000, 1, [ref]$v); $b3 = [UzEbenen]::Weiter(1300, 5000, 0, [ref]$v); $b4 = [UzEbenen]::Weiter(1350, 5000, 1, [ref]$v)
"WEITER $a1 $a2 $a3 | $b1 $b2 $b3 $b4 $v"
"BEIM " + [UzEbenen]::Beim(0, $true, $null, 5) + " " + [UzEbenen]::Beim(0, $false, $null, 5) + " " + [UzEbenen]::Beim(2, $false, [int[]]@(7, 8), 8) + " " + [UzEbenen]::Beim(2, $false, [int[]]@(7, 8), 9) + " " + [UzEbenen]::Beim(2, $false, [int[]]@(), 9) + " " + [UzEbenen]::Beim(2, $false, $null, 9)
"FARBE " + [UzEbenen]::Farbe(0x102030).ToString("X6") + " " + [UzEbenen]::Farbe(-5) + " " + [UzEbenen]::Grenze(1) + " " + [UzEbenen]::Grenze(99999999)
$errs = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tok, [ref]$errs)
"PARSE " + $errs.Count
""")
	pf.close()
	var o: Array = []
	OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, script]), o, true)
	var txt := str(o[0] if not o.is_empty() else "")
	check(txt.contains("CS ok"), "C# UzEbenen übersetzt mit C# 5" + ("" if txt.contains("CS ok") else " – " + txt.get_slice("CS", 1).left(300)))
	check(txt.contains("ART 0 2 1 1 1 0 1 0"),
			"Vollbild vorn: nichts · Dialog: Loch (beim Ende nicht) · ohne Kandidat: alles · versteckt/hängt: alles · Vollbild auf dem anderen Bildschirm: nichts (%s)"
			% txt.get_slice("ART ", 1).get_slice("\n", 0))
	check(txt.contains("LOCH 1 2 1 2"), "Loch erst nach der Frist (%s)" % txt.get_slice("LOCH ", 1).get_slice("\n", 0))
	check(txt.contains("EIN 0 127 255 255"), "Einblenden in der Frist, ohne Frist sofort (%s)" % txt.get_slice("EIN ", 1).get_slice("\n", 0))
	check(txt.contains("OBEN True True False True"), "beim Start nur die Taskleiste überdecken, ShaderGlass nicht; beim Ende alles (%s)"
			% txt.get_slice("OBEN ", 1).get_slice("\n", 0))
	check(txt.contains("WEITER 3 3 0 | 2 0 3 1 0"), "Vollbild erst nach %d ms fertig, Zeitgrenze beendet immer (%s)" % [400, txt.get_slice("WEITER ", 1).get_slice("\n", 0)])
	check(txt.contains("FARBE 302010 0 200 180000"), "Farbe → COLORREF, Grenzen fest")
	check(txt.contains("BEIM 1 0 2 1 2 2"), "Beenden: über dem Vollbild nur mit „immer“; Loch nur um Fenster des Spiels, ohne Liste um jedes (%s)"
			% txt.get_slice("BEIM ", 1).get_slice("\n", 0))
	check(txt.contains("PARSE 0"), "Helfer ohne Parse-Fehler")
	# Jeder Auftrag mit falschen Daten scheitert an der Prüfung, bevor etwas Windows berührt.
	for job in [
			{ "cmd": "vorhang", "args": { "an": true, "hwnd": "1; Remove-Item C:\\", "max_ms": 3000, "farbe": 0 }, "key": "grund", "want": "daten" },
			{ "cmd": "vorhang", "args": { "an": true, "hwnd": 77, "max_ms": 99999999, "farbe": 0 }, "key": "grund", "want": "daten" },
			{ "cmd": "vorhang", "args": { "an": true, "hwnd": 77, "max_ms": 3000, "farbe": "schwarz" }, "key": "grund", "want": "daten" },
			{ "cmd": "vorhang", "args": { "an": "true", "hwnd": 77, "max_ms": 3000, "farbe": 0 }, "key": "an", "want": "False" },
			{ "cmd": "vorhang-wache", "args": { "an": true, "hwnd": 77, "spiel": 88, "max_ms": -1, "farbe": 0 }, "key": "grund", "want": "daten" },
			{ "cmd": "vorhang", "args": { "an": true, "hwnd": "x", "max_ms": 3000, "farbe": 0, "loch_pids": ["1; calc", 4711], "immer": "ja" },
				"key": "grund", "want": "daten" }]:
		var out: Array = []
		OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Once",
				Marshalls.utf8_to_base64(JSON.stringify({ "id": 1, "cmd": job.cmd, "args": job.args }))]), out, true)
		var got := ""
		for line in str(out[0] if not out.is_empty() else "").split("\n"):
			var jp := JSON.new()
			if line.strip_edges().begins_with("{") and jp.parse(line.strip_edges()) == OK and jp.data is Dictionary \
					and (jp.data as Dictionary).get("result") is Dictionary:
				got = str(jp.data.result.get(job.key, ""))
		check(got.to_lower() == str(job.want).to_lower(), "%s %s → %s" % [job.cmd, JSON.stringify(job.args).left(70), got])
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir)

extends Node
## Guide → Beenden (src/core/launcher.gd quit_game) ohne Bildschirm: was je Art des Spiels wozu gehört,
## wann eine Rückfrage des Emulators als beantwortet gilt, in welcher Reihenfolge höflich und hart
## beendet wird, dass Uzai nur zurückkommt, wenn das Spiel wirklich zu ist, und dass der Helfer nur
## den eigenen Prozessbaum anfasst. Rückfragen zu ShaderGlass (Arbeitsordner, Fernsehbild) gleich mit.
## Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich: UzBaum übersetzt mit C# 5, die Regel für den Baum
## (Kinder, Startzeit, Geschütztes) und dass die neuen Befehle nur Zahlen annehmen.
## Aufruf: godot --headless --path . res://tests/logic_beenden.tscn

const L := preload("res://src/core/launcher.gd")
const HelperScript := preload("res://src/core/helper.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p).replace("\r\n", "\n")


func _fn(src: String, kopf: String) -> String:
	var a := src.find(kopf)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)


func _ready() -> void:
	print("Was wozu gehört")
	var rom := L.quit_plan("rom", 4711, true)
	check(bool(rom.baum) and not bool(rom.ordner) and bool(rom.dialog_hart) and bool(rom.vorhang) and float(rom.sauber_s) <= 5.0,
			"Emulator: erst höflich (kurz), Rückfrage = Beenden, dann sein Prozessbaum, Vorhang zu")
	var pc := L.quit_plan("pc", 4711, true)
	check(bool(pc.baum) and not bool(pc.ordner) and not bool(pc.dialog_hart) and not bool(pc.vorhang) and float(pc.sauber_s) >= 6.0,
			"PC-Spiel (auch Epic ohne Launcher): Zeit zum Speichern, dann der Baum ab dem Starter")
	var st := L.quit_plan("steam", 0, true)
	check(not bool(st.baum) and bool(st.ordner) and not bool(st.fenster_pid) and float(st.sauber_s) >= 6.0,
			"Steam: Zeit zum Speichern, dann nur Prozesse im Spielordner (früher blieb es offen)")
	check(not bool(L.quit_plan("steam", 0, false).ordner), "Steam ohne Spielordner: nichts Hartes")
	var ep := L.quit_plan("epic", 0, true)
	check(bool(ep.ordner) and bool(ep.fenster_pid) and not bool(ep.baum), "Epic über den Launcher: Spielordner und das Fenster, dem Uzai folgte")
	var ln := L.quit_plan("link", 0, true)
	check(not bool(ln.ordner) and bool(ln.fenster_pid), "Verknüpfung: nur der Prozess hinter dem gefolgten Fenster")
	check(bool(L.quit_plan("gog", 0, true).fenster_pid) and bool(L.quit_plan("gog", 0, true).ordner), "weitere Launcher wie Epic")
	check(bool(L.quit_plan("steam", 999, true).baum) and not bool(L.quit_plan("steam", 999, true).ordner),
			"selbst gestartet (Remote Play): der eigene Baum statt des Ordners")
	var gut := ["D:\\SteamLibrary\\steamapps\\common\\Hades", "C:\\Program Files\\Epic Games\\Fortnite", "C:\\GOG Games\\Witcher 3\\",
		"E:/Spiele/Celeste", "C:\\Users\\Max\\Spiele\\Celeste"]
	var schlecht := ["", "C:\\", "C:", "D:\\Games", "C:\\Program Files", "C:\\Program Files (x86)\\", "D:\\SteamLibrary\\steamapps\\common",
		"C:\\Program Files\\Epic Games", "C:\\Users\\Max", "C:\\Users\\Max\\AppData", "C:\\Windows\\System32\\..\\Windows", "\\\\server\\share\\spiel"]
	check(gut.all(func(d: String) -> bool: return L.kill_dir_ok(d)), "echte Spielordner dürfen beim Beenden geleert werden")
	check(not schlecht.any(func(d: String) -> bool: return L.kill_dir_ok(d)), "Laufwerk, Sammelordner, Profil und Netzpfade nie")

	print("Starter, der das Spiel startet und sich beendet (SP Football Life 2027: „FL 2027 start.exe“ → FL_2027.exe)")
	check(L.nachfolger_erlaubt(false, "C:/Games/SP Football Life 2027", 5), "in den ersten Minuten im Spielordner: Nachfolger suchen")
	check(not L.nachfolger_erlaubt(true, "C:/Games/SP Football Life 2027", 5), "nur einmal je Start")
	check(not L.nachfolger_erlaubt(false, "C:/Games/SP Football Life 2027", L.NACHFOLGER_S + 1), "nach Stunden: nicht mehr (dann ist das Spiel wirklich zu)")
	check(not L.nachfolger_erlaubt(false, "C:\\Program Files", 5) and not L.nachfolger_erlaubt(false, "", 5), "nie in Sammelordnern oder ohne Ordner")
	check(L.nachfolger_aus([4242, 5151], 4242, 99) == 5151 and L.nachfolger_aus([4242, 99], 4242, 99) == 0 and L.nachfolger_aus(["x"], 1, 2) == 0,
			"Nachfolger: weder der alte Prozess noch Uzai selbst")

	print("Rückfrage des Emulators")
	check(L.quit_is_dialog({ "fg_game": true, "fg_hwnd": 55, "fg_full": false }, 44), "kleines Fenster desselben Programms vorn: Rückfrage")
	check(not L.quit_is_dialog({ "fg_game": true, "fg_hwnd": 44, "fg_full": false }, 44), "das Spielfenster selbst ist keine")
	check(not L.quit_is_dialog({ "fg_game": true, "fg_hwnd": 55, "fg_full": true }, 44), "ein neues Vollbild-Fenster auch nicht")
	check(not L.quit_is_dialog({ "fg_game": false, "fg_hwnd": 55, "fg_full": false }, 44), "fremdes Fenster (Steam, Discord): nicht")
	check(not L.quit_is_dialog({}, 44), "keine Antwort: nicht")

	print("Ablauf")
	var ls := _src("res://src/core/launcher.gd")
	var q := _fn(ls, "func quit_game(")
	var ab := _fn(ls, "func _quit_ablauf(")
	var i_close := ab.find("\"close-window\"")
	var i_wait := ab.find("_wait_quit(float(plan.sauber_s)")
	var i_cover := ab.rfind("await _quit_vorhang(\"beenden\")")
	var i_hard := ab.find("_quit_hard(plan, win_pid)")
	check(i_close > 0 and i_close < i_wait and i_wait < i_cover and i_cover < i_hard, "erst höflich, dann warten, dann Vorhang zu, dann hart")
	check(ab.find("if not _quit_hart:") < i_close and ab.find("if bool(plan.vorhang):\n\t\t\tawait _quit_vorhang(\"beenden\")") < i_close,
			"Emulator: Vorhang zu, bevor er gebeten wird; sofort hart: ohne höfliche Bitte")
	check(q.contains("if ende == \"\":\n\t\t_finish()") and q.contains("_quit_haengt(ende)") and _fn(ls, "func _quit_haengt(").contains("quit_stuck.emit"),
			"Uzai kommt zurück, wenn das Spiel zu ist – sonst bleibt Uzai bedienbar (quit_stuck: Guide mit Wahl)")
	check(not ls.contains("Toasts.show_toast(\"Spiel läuft noch\""), "nicht mehr nur eine Mitteilung, nach der nichts mehr ging")
	check(ab.contains("_unpause_for_quit()") and ab.find("_unpause_for_quit()") < i_close, "angehaltener Emulator läuft erst wieder (sonst schließt er nie)")
	check(q.contains("if quitting:") and q.contains("_quit_hart = true") and q.find("if quitting:") < q.find("_quit_waechter(q)"),
			"noch einmal Beenden, während es beendet: keine zweite Kette, sondern sofort hart")
	var wq := _fn(ls, "func _wait_quit(")
	check(wq.contains("quit_nicht_warten(_quit_hart, fenster_haengt or hung)") and wq.contains("\"window-hung\""),
			"höfliches Warten endet beim zweiten Druck und bei einem Fenster, das nicht reagiert")
	check(wq.contains("_quit_vorhang(\"schliessen\")") and wq.contains("\"alive\", true"), "Spielfenster weg, Spiel noch nicht zu: Vorhang „schliessen“")
	check(_fn(ls, "func _quit_weiter(").contains("q == _quit_id and in_game and gen == _launch_gen"), "endet es von selbst oder übernimmt der Wächter: nichts doppelt")
	var wa := _fn(ls, "func _quit_waechter(")
	check(wa.contains("quit_max_s") and wa.contains("quitting = false") and wa.contains("_quit_id += 1") and wa.contains("_quit_haengt(QUIT_ZU_LANG)"),
			"Wächter: nach höchstens %.0f s ist Beenden fertig, Uzai bleibt bedienbar" % L.QUIT_MAX_S)
	check(L.QUIT_MAX_S > float(L.QUIT_SAUBER_S.pc) + L.QUIT_NACH_S + 6.0 and L.QUIT_MAX_S <= 30.0, "Wächter erst nach der Zeit zum Speichern und dem harten Beenden, aber nie lange")
	var fin := _fn(ls, "func _finish(")
	check(fin.contains("quitting = false") and fin.contains("quit_haengt = false") and fin.contains("_quit_hart = false") and fin.contains("_quit_id += 1"),
			"Spielende räumt den Beenden-Zustand ganz ab")
	check(_fn(ls, "func _set_paused_lauf(").contains("if on and quitting:"), "Guide während des Beendens hält das Spiel nicht an")
	check(_fn(ls, "func set_paused(").contains("await _set_paused_lauf(on)") and _fn(ls, "func set_paused(").contains("_pause_busy = false"),
			"bricht das Anhalten mit einem Fehler ab, löst die Hülle die Marke (sonst hielte Uzai nie wieder ein Spiel an)")
	check(_fn(ls, "func _quit_alive(").contains("\"prozessbaum\""), "„noch da?“ fragt den ganzen Baum (Starter → Spiel)")
	var qh := _fn(ls, "func _quit_hard(")
	check(qh.contains("\"baum-beenden\"") and qh.contains("_hung_pid_sicher(more)") and not ls.contains("func _kill_hung("),
			"hart: ein Weg für alles (auch „Sofort beenden“) – Baum, Spielordner, hängendes Fenster")
	var hs := _fn(ls, "func _hung_pid_sicher(")
	check(hs.contains("kill_dir_ok(dir)") and hs.contains("_kind == \"link\"") and hs.contains("\"prozessbaum\""),
			"Prozess hinter dem hängenden Fenster nur, wenn er sicher zum Spiel gehört (Spielordner nur, wenn er echt ist)")
	check(not qh.contains("OS.kill") and not ab.contains("OS.execute"), "keine Befehle über die Shell")
	var lo := _fn(ls, "func loslassen(")
	check(lo.contains("if not in_game or quitting:") and lo.contains("_finish()") and not lo.contains("\"kill\""),
			"„Zur Startseite“: Uzai lässt das Spiel laufen und kommt zurück – nie mitten im Beenden")
	check(L.quit_gleich_hart(true, false, false) and L.quit_gleich_hart(false, true, false) and L.quit_gleich_hart(false, false, true)
			and not L.quit_gleich_hart(false, false, false), "sofort hart: verlangt, Fenster hängt, oder der letzte Versuch scheiterte – sonst erst höflich")
	check(L.quit_nicht_warten(true, false) and L.quit_nicht_warten(false, true) and not L.quit_nicht_warten(false, false),
			"höflich warten nur, solange es antwortet und niemand noch einmal drückt")
	check(L.quit_grund(true, true) == L.KILL_DENIED and L.quit_grund(false, false) == L.KEIN_PROZESS and L.quit_grund(false, true) == L.WINDOWS_LEHNT_AB,
			"„läuft noch“ sagt, warum")
	var unp := _fn(ls, "func _unpause_for_quit(")
	check(unp.contains("2000"), "Warten aufs Weiterlaufen mit Zeitgrenze")
	for c in ["prozessbaum", "baum-beenden", "window-hung"]:
		check(c in HelperScript.FAST, "„%s“ über den schnellen Weg" % c)
	var mn := _src("res://src/main.gd")
	check(mn.contains("Launcher.quit_cover = beenden_vorhang") and mn.contains("Launcher.quit_stuck.connect(_on_quit_stuck)"), "main hängt Vorhang und „läuft noch“ an")
	var fe := _src("res://src/main_fenster.gd")
	var bv := _fn(fe, "func beenden_vorhang(")
	check(bv.contains("Fernsehspiel.uzai_vorn(_tv)") and bv.contains("_kulisse"), "im Zimmer und hinter einer eigenen App: kein Vorhang (Uzai liegt vorn)")
	check(bv.contains("_overlay_mode and _overlay_deckend"), "deckender Guide: kein Vorhang darüber")
	var mg := _src("res://src/main_guide.gd")
	var st_ := _fn(mg, "func _on_quit_stuck(")
	check(st_.contains("toggle_guide()") and st_.contains("Launcher.loslassen()") and st_.contains("Launcher.quit_game(true)") and st_.contains("_vorhang_unter_guide()"),
			"läuft noch: Guide geht auf (deckend), Wahl: sofort beenden, zur Startseite, zurück zum Spiel")
	var kn: Array = load("res://src/main_guide.gd").quit_stuck_knoepfe(true, Callable(), Callable(), Callable())
	check(kn.size() == 3 and str(kn[0][0]) == "Sofort beenden" and str(kn[0][2]) == "danger" and str(kn[1][0]) == "Zur Startseite" and str(kn[2][0]) == "Zurück zum Spiel",
			"Knöpfe: Sofort beenden (gefährlich, nicht vorgewählt), Zur Startseite (vorgewählt), Zurück zum Spiel zuletzt")
	var kn2: Array = load("res://src/main_guide.gd").quit_stuck_knoepfe(false, Callable(), Callable(), Callable())
	check(kn2.size() == 2 and str(kn2[0][0]) == "Zur Startseite", "Adminrechte: kein sinnloses „Sofort beenden“")
	var MG = load("res://src/main_guide.gd")
	check(MG.guide_deckend(true, false, false) and MG.guide_deckend(false, true, false) and MG.guide_deckend(false, false, true)
			and not MG.guide_deckend(false, false, false),
			"Guide deckend, solange Beenden läuft oder nicht ging oder das Spielfenster weg ist – sonst durchsichtig über dem Spiel")
	var tg := _fn(mg, "func toggle_guide(")
	check(tg.contains("_enter_overlay(guide_deckend(Launcher.quitting, Launcher.quit_haengt, _spiel_weg))"), "toggle_guide fragt guide_deckend")
	var gc := _fn(mg, "func _on_guide_closed(")
	check(gc.find("await _vorhang(\"schliessen\")") > 0 and gc.find("await _vorhang(\"schliessen\")") < gc.rfind("_leave_overlay()"),
			"deckender Guide zu, während es sich schließt: erst Vorhang, dann gibt Uzai ab")
	var eo := _fn(fe, "func _enter_overlay(")
	check(eo.contains("background.visible = deckend") and eo.contains("_vorhang_unter_guide()"), "deckend: Uzais Grund, der Vorhang darunter geht erst nach dem Zeichnen")
	var gs := _fn(_src("res://src/ui/layers/guide_spiel.gd"), "func _ask_quit(")
	check(gs.find("if Launcher.quitting:") >= 0 and gs.find("if Launcher.quitting:") < gs.find("open_dialog") and gs.contains("Launcher.quit_game(true)"),
			"Guide › Beenden während des Beendens: gleich „Sofort beenden“")
	check(_fn(ls, "func quit_sofort(").contains("quitting or hung or quit_haengt"), "„Sofort beenden“ heißt der Eintrag, solange es beendet, hängt oder nicht ging")
	for f in ["res://src/ui/components/guide_game.gd", "res://src/ui/components/guide_quick.gd"]:
		check(_src(f).contains("Launcher.quit_sofort()"), "%s zeigt „Sofort beenden“" % f.get_file())
	check(_fn(_src("res://src/room/spielbild.gd"), "func _fang_args(").contains("Launcher.filter_pid()"),
			"Spiel im Fernseher mit Bildfilter: der Fernseher zeigt das Bild von ShaderGlass")
	check(_fn(ls, "func filter_pid(").contains("not _sg_hidden"), "… nur, solange es zu sehen ist")
	check(_fn(ls, "func _apply_filter(").contains("log_launch(\"Bildfilter"), "ShaderGlass-Start steht in logs/launch.log (Filter, Fenster, Werte)")
	var hr := _fn(_src("res://src/core/helper.gd"), "func run(")
	check(hr.contains("if cmd == \"hide-windows\":\n\t\t_hide_lane = l") and hr.contains("cmd == \"show-hidden\" and _hide_lane != null"),
			"ShaderGlass wieder zeigen im selben Helfer, der es versteckt hat (sonst blieb der Filter unsichtbar)")
	await _ablauf()

	print("Helfer-Quellen")
	var ps := _src("res://helper/uzai-helper.ps1")
	for c in ["prozessbaum", "baum-beenden"]:
		check(ps.count("        '%s' {" % c) == 1, "fester Befehl „%s“ genau einmal" % c)
	var a := ps.find("        'prozessbaum' {")
	var cmd := ps.substr(a, ps.find("        'alive' {", a) - a)
	check(cmd.count("Get-Zahl $a.pid 5 2147483647") == 2 and cmd.contains("$root -eq $PID"), "nur eine Zahl als Prozess, nie der Helfer selbst")
	check(cmd.contains("Stop-GameProcess ([int]$id)") and not cmd.contains(".Kill()"), "beendet nur über Stop-GameProcess (nie Geschütztes)")
	var cs_a := ps.find("$script:BaumSrc = @'")
	var cs := ps.substr(cs_a, ps.find("'@", cs_a) - cs_a)
	check(cs.contains("OpenProcess(0x1000u") and cs.count("OpenProcess(") == 2, "UzBaum öffnet Prozesse nur zum Nachsehen (PROCESS_QUERY_LIMITED_INFORMATION)")
	for bad in ["TerminateProcess", "Process.Start", "CreateProcess", "WriteProcessMemory", "File.", "Registry"]:
		check(not cs.contains(bad), "UzBaum ohne %s" % bad)
	check(ps.contains("Get-SpielBaum") and ps.contains("[string[]]$script:KillNever"), "Geschütztes (Windows, Steam, Discord, Uzai) bleibt draußen")
	var cw_a := ps.find("        'close-window' {")
	var cw := ps.substr(cw_a, ps.find("        'new-window' {", cw_a) - cw_a)
	check(cw.contains("Get-Hwnd $a.hwnd") and cw.contains("Get-Zahl $a.pid 5 2147483647") and cw.contains("$p -eq $PID"),
			"„close-window“: nur Zahlen, nie an den Helfer selbst")
	var sg_a := ps.find("        'shaderglass' {")
	var sg := ps.substr(sg_a, ps.find("        'spotify-start' {", sg_a) - sg_a)
	check(sg.contains("-WorkingDirectory $sgDir") and sg.contains("Split-Path -Parent ([string]$a.exe)"),
			"ShaderGlass startet in seinem Ordner, egal wie Uzai gestartet wurde")
	await _pwsh()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Beenden wirklich ablaufen lassen (ohne Windows): ein eigener Launcher-Knoten, dessen Spiel-Profil
## beim Beenden hängt wie ein Helfer, der nie antwortet.
func _ablauf() -> void:
	print("Ablauf mit Wächter (ohne Windows)")
	var stub := GDScript.new()
	stub.source_code = "extends Node\nsignal los\nvar haengen := true\nfunc before_quit() -> void:\n\tif haengen:\n\t\tawait los\nfunc restore() -> void:\n\tpass\nfunc on_window(_g = null) -> void:\n\tpass\nfunc restore_pending() -> void:\n\tpass\n"
	stub.reload()
	var l: Node = L.new()
	add_child(l)
	var prof: Node = l.profile
	l.profile = stub.new()
	l.add_child(l.profile)
	prof.queue_free()
	var stuck: Array = []
	l.quit_stuck.connect(func(_g: Dictionary, t: String) -> void: stuck.append(t))
	l.quit_max_s = 0.4
	check(l.lauf() == "aus", "Lebenslauf (Zustand.lage, Fehlerbericht): aus")
	l.in_game = true
	l.current = { "id": "probe-beenden", "title": "Probe", "source": "pc" }
	l._start_time = int(Time.get_unix_time_from_system())
	check(l.lauf() == "wartet", "Lebenslauf: das Spiel läuft, sein Fenster kommt noch")
	l.quit_game()
	check(l.quitting and not l._quit_hart, "Beenden läuft, erst höflich")
	check(l.lauf() == "beenden", "Lebenslauf: beenden")
	l.quit_game()
	check(l.quitting and l._quit_hart, "zweiter Druck: keine zweite Kette, sondern sofort hart")
	check(l.lauf() == "beenden_hart", "Lebenslauf: beenden_hart")
	await get_tree().create_timer(0.7).timeout
	check(not l.quitting and l.in_game and l.quit_haengt and stuck.size() == 1 and str(stuck[0]) == L.QUIT_ZU_LANG,
			"Helfer antwortet nie: der Wächter beendet „Beenden“ – quitting bleibt nicht hängen, Uzai bleibt bedienbar")
	check(l.quit_sofort(), "danach heißt es im Guide „Sofort beenden“")
	check(l.lauf() == "haengt", "Lebenslauf: Beenden ging nicht (haengt)")
	l.profile.emit_signal("los")
	await get_tree().process_frame
	await get_tree().process_frame
	check(l.in_game and not l.quitting and stuck.size() == 1, "die alte Kette kommt doch noch zurück: sie tut nichts mehr")
	l.profile.haengen = false
	l.quit_game()
	await get_tree().create_timer(0.2).timeout
	check(not l.in_game and not l.quitting and not l.quit_haengt and stuck.size() == 1, "nächster Versuch klappt: zurück, alles aufgeräumt")
	check(l.lauf() == "aus", "Lebenslauf: wieder aus")
	await get_tree().create_timer(0.6).timeout
	check(stuck.size() == 1, "kein Wächter mehr danach")
	l.in_game = true
	l.current = { "id": "probe-beenden", "title": "Probe", "source": "pc" }
	l.loslassen()
	check(not l.in_game, "„Zur Startseite“: Uzai kommt zurück, das Spiel bleibt, wie es ist")
	l.queue_free()


func _pwsh() -> void:
	if HelperScript._test_shell() == "":
		print("  (PowerShell-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")
		return
	print("Helfer unter PowerShell 7")
	var dir := OS.get_cache_dir().path_join("uzai-beenden-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("uzai-helper.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string(_src("res://helper/uzai-helper.ps1"))
	f.close()
	var probe := dir.path_join("probe.ps1")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	pf.store_string("""
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$cs = [regex]::Match($src, '(?s)\\$script:BaumSrc = @''\\n(.*?)\\n''@').Groups[1].Value
try { Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; "CS ok" } catch { "CS FEHLER " + $_.Exception.Message }
# 100 Wurzel (Start 10) → 200 (20) → 300 (30); 400 nennt 100 als Eltern, startete aber vorher (alte Nummer);
# 500 ist geschützt (Steam), 600 darunter; 700 gehört jemand anderem.
$p = [int[]]@(100, 200, 300, 400, 500, 600, 700)
$e = [int[]]@(1, 100, 200, 100, 100, 500, 1)
$s = [long[]]@(10, 20, 30, 5, 25, 26, 1)
$n = [bool[]]@($false, $false, $false, $false, $true, $false, $false)
"BAUM " + ([UzBaum]::Nachkommen(100, $p, $e, $s, $n, 64) -join ',')
"GRENZE " + ([UzBaum]::Nachkommen(100, $p, $e, $s, $n, 2) -join ',')
$p2 = [int[]]@(200, 300, 700); $e2 = [int[]]@(100, 200, 1); $s2 = [long[]]@(20, 30, 1); $n2 = [bool[]]@($false, $false, $false)
"OHNE " + ([UzBaum]::Nachkommen(100, $p2, $e2, $s2, $n2, 64) -join ',')
$n3 = [bool[]]@($true, $false, $false, $false, $false, $false, $false)
"GESCHUETZT [" + ([UzBaum]::Nachkommen(100, $p, $e, $s, $n3, 64) -join ',') + "]"
$s4 = [long[]]@(0, 0, 0, 0, 0, 0, 0)
"UNBEKANNT " + ([UzBaum]::Nachkommen(100, $p, $e, $s4, $n, 64) -join ',')
$p5 = [int[]]@(100, 4, 0); $e5 = [int[]]@(1, 100, 100); $s5 = [long[]]@(10, 20, 20); $n5 = [bool[]]@($false, $false, $false)
"SYSTEM " + ([UzBaum]::Nachkommen(100, $p5, $e5, $s5, $n5, 64) -join ',')
$errs = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tok, [ref]$errs)
"PARSE " + $errs.Count
""")
	pf.close()
	var o: Array = []
	OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, script]), o, true)
	var txt := str(o[0] if not o.is_empty() else "")
	check(txt.contains("CS ok"), "C# UzBaum übersetzt mit C# 5" + ("" if txt.contains("CS ok") else " – " + txt.get_slice("CS", 1).left(300)))
	check(txt.contains("BAUM 100,200,300\n") or txt.contains("BAUM 100,200,300\r"),
			"Baum: Wurzel, Kind, Enkel – ohne alte Nummer, ohne Geschütztes und was darunter liegt (%s)" % txt.get_slice("BAUM ", 1).get_slice("\n", 0))
	check(txt.contains("GRENZE 100,200"), "höchstens so viele wie erlaubt")
	check(txt.contains("OHNE 200,300"), "Starter schon zu: seine Kinder zählen weiter (%s)" % txt.get_slice("OHNE ", 1).get_slice("\n", 0))
	check(txt.contains("GESCHUETZT []"), "geschützte Wurzel: nichts")
	check(txt.contains("UNBEKANNT 100,200,400,300"), "ohne Startzeiten zählt die Elternnummer (%s)" % txt.get_slice("UNBEKANNT ", 1).get_slice("\n", 0))
	check(txt.contains("SYSTEM 100\n") or txt.contains("SYSTEM 100\r"), "System-Prozesse (0, 4) nie (%s)" % txt.get_slice("SYSTEM ", 1).get_slice("\n", 0))
	check(txt.contains("PARSE 0"), "Helfer ohne Parse-Fehler")
	# Falsche Daten scheitern an der Prüfung, bevor etwas Windows berührt.
	for job in [
			{ "cmd": "prozessbaum", "args": { "pid": "1; Remove-Item C:\\" }, "key": "grund", "want": "daten" },
			{ "cmd": "prozessbaum", "args": { "pid": 3 }, "key": "grund", "want": "daten" },
			{ "cmd": "baum-beenden", "args": { "pid": 0 }, "key": "grund", "want": "daten" },
			{ "cmd": "baum-beenden", "args": { "pid": "4711 -Force" }, "key": "grund", "want": "daten" },
			{ "cmd": "baum-beenden", "args": { "pid": true }, "key": "grund", "want": "daten" },
			{ "cmd": "close-window", "args": { "hwnd": "0;calc", "pid": "x" }, "key": "sent", "want": "False" },
			{ "cmd": "close-window", "args": { "hwnd": 0, "pid": 2 }, "key": "sent", "want": "False" }]:
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

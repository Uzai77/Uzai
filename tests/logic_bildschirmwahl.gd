extends Node
## Bildschirm (src/core/bildschirm.gd): Wahl, Neustart für ein scharfes Bild bei mehreren
## Bildschirmen, die Umgebungsvariable dafür, Größe der Oberfläche je Bildschirm.
## Aufruf: godot --headless --path . res://tests/logic_bildschirmwahl.tscn

const B := preload("res://src/core/bildschirm.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Wahl")
	check(B.index("auto", 2) == -1 and B.index("", 2) == -1 and B.index(null, 2) == -1, "auto, leer, nichts: automatisch")
	check(B.index("1", 2) == 0 and B.index("2", 2) == 1 and B.index(2, 2) == 1, "Nummer 1 und 2 (auch als Zahl)")
	check(B.index("3", 2) == -1 and B.index("0", 2) == -1 and B.index("-1", 2) == -1, "Nummer, die es nicht gibt: automatisch")
	check(B.index("1; rm", 2) == -1 and B.index("1.5", 2) == -1, "nur ganze Zahlen")
	var liste := B.wahl_liste([Vector2i(1920, 1080), Vector2i(3840, 2160)], 0, "Automatisch", "Hauptbildschirm")
	check(liste.size() == 3 and liste[0] == ["auto", "Automatisch"], "Liste beginnt mit „Automatisch“")
	check(liste[1][0] == "1" and str(liste[1][1]).contains("1920 × 1080") and str(liste[1][1]).ends_with("Hauptbildschirm"), "1: Größe und Hauptbildschirm")
	check(liste[2][0] == "2" and str(liste[2][1]).contains("3840 × 2160") and not str(liste[2][1]).contains("Haupt"), "2: Größe")

	print("Neustart für ein scharfes Bild")
	B.eigen = false
	var a := "0,0,1920x1080;1920,0,1280x720"
	check(B.neustart_noetig(true, 2, true, [], "", a), "Windows, zwei Bildschirme, noch nichts gemerkt: Neustart")
	check(not B.neustart_noetig(false, 2, true, [], "", a), "nicht unter Windows: nie")
	check(not B.neustart_noetig(true, 1, true, [], "", "0,0,1920x1080"), "ein Bildschirm: nie")
	check(not B.neustart_noetig(true, 2, false, [], "", a), "abgeschaltet oder Sicherer Modus: nie")
	check(not B.neustart_noetig(true, 2, true, ["--sicherer-modus"], "", a) and not B.neustart_noetig(true, 2, true, ["--demo"], "", a)
			and not B.neustart_noetig(true, 2, true, ["--uzai-script=res://tests/x.gd"], "", a), "Sicherer Modus, Demo, Proben: nie")
	check(B.neustart_noetig(true, 2, true, ["--nach-absturz", "--launch=x"], "", a), "nach einem Absturz und mit Verknüpfung: wie sonst")
	check(not B.neustart_noetig(true, 2, true, [], a, a), "gemerkt: alle gleich skaliert, Anordnung unverändert – kein Neustart")
	check(B.neustart_noetig(true, 2, true, [], a, "0,0,1920x1080;1920,0,3840x2160"), "Anordnung anders als gemerkt: Neustart")
	B.eigen = true
	check(not B.neustart_noetig(true, 2, true, [], "", a), "dieser Lauf rechnet schon scharf: kein zweiter Neustart")
	B.eigen = false
	check(B.anordnung([Rect2i(0, 0, 1920, 1080), Rect2i(1920, 0, 1280, 720)]) == a, "Anordnung als Text")
	check(B.anordnung([]) == "" and B.anordnung(["x", 3]) == "", "leer und Unsinn: leer")
	check(B.gleich_skaliert([96, 96]) and not B.gleich_skaliert([96, 288]) and not B.gleich_skaliert([]), "gleich skaliert?")

	print("Umgebungsvariable")
	check(B.schicht_dazu("") == "HighDpiAware", "leer: nur die Schicht")
	check(B.schicht_dazu("RunAsInvoker") == "RunAsInvoker HighDpiAware", "andere Schichten bleiben")
	check(B.schicht_dazu("RunAsInvoker HIGHDPIAWARE") == "RunAsInvoker HIGHDPIAWARE", "schon da (andere Schreibweise): nicht doppelt")
	check(B.schicht_weg("RunAsInvoker HighDpiAware") == "RunAsInvoker" and B.schicht_weg("HighDpiAware") == "" and B.schicht_weg("") == "", "wieder heraus")
	check(B.schicht_weg(B.schicht_dazu("  A   B ")) == "A B", "hin und zurück: die anderen bleiben")
	# Wirklich an der Umgebung dieses Prozesses: setzen, „neues Uzai“ spielen, alles wieder weg.
	var vorher := OS.get_environment(B.VARIABLE)
	OS.set_environment(B.VARIABLE, "RunAsInvoker")
	B.vor_neustart(false)
	check(OS.get_environment(B.BEWEIS) == "" and OS.get_environment(B.VARIABLE) == "RunAsInvoker", "nicht gewünscht: Umgebung unberührt")
	B.vor_neustart(true)
	check(OS.get_environment(B.BEWEIS) == "1" and OS.get_environment(B.VARIABLE) == "RunAsInvoker HighDpiAware", "gewünscht: Schicht und Beweis gesetzt")
	B.start()
	check(B.eigen and OS.get_environment(B.BEWEIS) == "" and OS.get_environment(B.VARIABLE) == "RunAsInvoker",
			"das neue Uzai merkt es sich und räumt die Umgebung auf (Helfer und Spiele erben nichts)")
	B.eigen = false
	B.start()
	check(not B.eigen, "ohne Beweis: kein scharfer Lauf")
	B.vor_neustart(true)
	B.nach_neustart()
	check(OS.get_environment(B.BEWEIS) == "" and OS.get_environment(B.VARIABLE) == "RunAsInvoker", "nach dem Start des neuen: dieses Uzai räumt wieder auf")
	OS.set_environment(B.VARIABLE, "")
	B.vor_neustart(true)
	B.nach_neustart()
	check(not OS.has_environment(B.VARIABLE) or OS.get_environment(B.VARIABLE) == "", "war die Variable leer, ist sie danach wieder weg")
	if vorher != "":
		OS.set_environment(B.VARIABLE, vorher)

	print("Startparameter")
	check(B.ohne_schirm(["--screen", "1", "--rendering-method", "gl_compatibility"]) == ["--rendering-method", "gl_compatibility"], "alter Bildschirm fällt weg")
	check(B.mit_schirm(["--screen", "0"], "2", 2) == ["--screen", "1"], "gewählter Bildschirm kommt dazu (Godot zählt ab 0)")
	check(B.mit_schirm(["--screen", "0", "-v"], "auto", 2) == ["-v"] and B.mit_schirm([], "5", 2) == [], "automatisch oder nicht da: ohne")

	print("Größe der Oberfläche je Bildschirm")
	var k := B.schluessel(Vector2i(3840, 2160), 288)
	check(k == "3840x2160@288", "Schlüssel aus Größe und Skalierung")
	check(B.skala_von({}, k) == 0.0 and B.skala_von(null, k) == 0.0 and B.skala_von({ k: "groß" }, k) == 0.0, "unbekannt, nichts, Unsinn: 0")
	var s := B.skala_merken({}, k, 1.0)
	s = B.skala_merken(s, "1920x1080@96", 0.85)
	check(is_equal_approx(B.skala_von(s, k), 1.0) and is_equal_approx(B.skala_von(s, "1920x1080@96"), 0.85), "zwei Bildschirme, zwei Größen")
	check(is_equal_approx(B.skala_von(B.skala_merken(s, k, 9.0), k), 2.0) and is_equal_approx(B.skala_von(B.skala_merken(s, k, 0.1), k), 0.6), "nur im Bereich des Reglers")
	var viele := {}
	for i in 20:
		viele = B.skala_merken(viele, "s%d" % i, 1.0)
	check(viele.size() == B.SKALEN_MAX and viele.has("s19") and not viele.has("s0"), "höchstens %d gemerkt, die ältesten fallen weg" % B.SKALEN_MAX)
	check(B.skala_merken({ "x": "kaputt", "y": 1.2 }, k, 1.0).keys() == ["y", k], "kaputte Einträge fallen beim Merken heraus")

	print("Angeschlossen")
	var cfg := Quelle.lesen("res://src/core/config.gd")
	var rem := Quelle.lesen("res://src/core/remote.gd")
	var mn := Quelle.lesen("res://src/main.gd")
	check(cfg.find("Bildschirm.start()") > 0 and cfg.find("Bildschirm.start()") < cfg.find("_wait_for_previous()\n"),
			"Config räumt die Umgebung auf, bevor der erste Kindprozess startet")
	check(rem.contains("if _scharf_neu_starten():") and rem.find("if _scharf_neu_starten():") < rem.find("_control = TCPServer.new()\n\tif _control.listen"),
			"Remote entscheidet über den Neustart, bevor es den Anschluss belegt")
	check(rem.contains("is_second = true\n\tget_tree().quit()\n\treturn true"), "das alte Uzai baut nichts auf und endet")
	check(mn.contains("_start_vorn()") and mn.contains("_restore_window()") and mn.contains("_schirm_takt(_started and not _closing and not _video_overlay)"),
			"main: Startwache und Sekundentakt für den Bildschirm")
	check(mn.count("OS.create_process(OS.get_executable_path()") == 1 and mn.contains("func _uzai_starten(args: Array) -> void:"),
			"jeder Neustart aus main geht über _uzai_starten (scharfes Bild bleibt)")
	var fen := Quelle.lesen("res://src/main_fenster.gd")
	var st := fen.substr(fen.find("func _schirm_start()"), 2600)
	check(st.contains("Bildschirm.skala_von(") and st.contains("Config.set_value(\"theme.ui_scale\", gemerkt)") and not st.contains("_schirm_merken()"),
			"beim Start gilt die Größe von diesem Bildschirm – sie wird nicht mit der vom anderen überschrieben")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

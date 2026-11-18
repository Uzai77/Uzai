extends Node
## Spiel im Fernseher des Zimmers (src/room/fernsehspiel.gd) ohne Bildschirm: Zustände und Übergänge,
## was die Guide-Taste wann tut, Zeitgrenzen, der Platz genau vor dem Fernseher, und das straffe
## Laufen und Umsehen im Zimmer (Totzone, lineare Kurve; die Formeln wie Source in logic_bewegung).
## Aufruf: godot --headless --path . res://tests/logic_fernsehspiel.tscn

const F := preload("res://src/room/fernsehspiel.gd")
const Ansehen := preload("res://src/room/zimmer_ansehen.gd")
const Zimmer := preload("res://src/room/zimmer.gd")
const Vorhang := preload("res://src/core/vorhang.gd")
const Spielbild := preload("res://src/room/spielbild.gd")
const Raumton := preload("res://src/room/raumton.gd")
const HelperScript := preload("res://src/core/helper.gd")
const Zustand := preload("res://src/core/zustand.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _folge(z: String, ereignisse: Array) -> Array:
	var weg: Array = []
	for e in ereignisse:
		z = F.weiter(z, str(e))
		weg.append(z)
	return weg


## Kopf der Zwischendatei, wie UzTvFang (Helfer) ihn schreibt (tests/tvfang_cs.ps1 prüft die andere Seite).
func _kopf(seq: int, w: int, h: int, zeile := -1, laenge := -1, magic := Spielbild.FANG_MAGIC, version := 1, farbe := 0) -> PackedByteArray:
	var k := PackedByteArray()
	k.resize(Spielbild.FANG_KOPF)
	k.encode_u32(0, magic)
	k.encode_u32(4, version)
	k.encode_u32(8, seq)
	k.encode_u32(12, w)
	k.encode_u32(16, h)
	k.encode_u32(20, w * 4 if zeile < 0 else zeile)
	k.encode_u32(24, w * h * 4 if laenge < 0 else laenge)
	k.encode_u32(28, farbe)
	return k


func _live_bild() -> void:
	print("Live-Bild beim Herumlaufen (Windows Graphics Capture)")
	check(_kopf(2, 1, 1).slice(0, 4).get_string_from_ascii() == "UZTV", "Kennung „UZTV“ wie im Helfer")
	var k := Spielbild.kopf_aus(_kopf(6, 960, 540), Spielbild.FANG_KOPF + 1280 * 720 * 4)
	check(k == { "seq": 6, "w": 960, "h": 540, "len": 960 * 540 * 4, "farbe": -1 }, "gültiger Kopf → Größe und Folgenummer (ohne Farbe: -1)")
	k = Spielbild.kopf_aus(_kopf(8, 4, 2, -1, -1, Spielbild.FANG_MAGIC, 1, 0x80102030), -1)
	check(int(k.get("farbe", -2)) == 0x102030, "Feld 28: mittlere Farbe vom Helfer (0x80 = gültig)")
	check(int(Spielbild.kopf_aus(_kopf(8, 4, 2, -1, -1, Spielbild.FANG_MAGIC, 1, 0x00102030), -1).get("farbe", -2)) == -1, "ohne Gültig-Bit: keine Farbe")
	check(Spielbild.kopf_aus(_kopf(7, 960, 540), -1).is_empty(), "ungerade Nummer: wird gerade geschrieben – nicht lesen")
	check(Spielbild.kopf_aus(_kopf(0, 0, 0), -1).is_empty(), "Nummer 0: noch kein Bild (oder gestoppt)")
	check(Spielbild.kopf_aus(_kopf(2, 2000, 10), -1).is_empty() and Spielbild.kopf_aus(_kopf(2, 1280, 1280), -1).is_empty(), "zu groß: abgelehnt")
	check(Spielbild.kopf_aus(_kopf(2, 960, 540, 960 * 3), -1).is_empty() and Spielbild.kopf_aus(_kopf(2, 960, 540, -1, 5), -1).is_empty(),
			"Zeile und Länge müssen genau passen")
	check(Spielbild.kopf_aus(_kopf(2, 960, 540, -1, -1, 0x12345678), -1).is_empty() and Spielbild.kopf_aus(_kopf(2, 960, 540, -1, -1,
			Spielbild.FANG_MAGIC, 2), -1).is_empty(), "fremde Kennung oder Version: abgelehnt")
	check(Spielbild.kopf_aus(_kopf(2, 960, 540), 1000).is_empty(), "Pixel passen nicht in die Datei: abgelehnt")
	check(Spielbild.kopf_aus(PackedByteArray([1, 2, 3]), -1).is_empty(), "zu kurz: abgelehnt")
	check(Spielbild.datei_ok("C:\\Users\\a\\AppData\\Local\\Temp\\uzai-tvbild-4711.bin") and Spielbild.datei_ok("/tmp/uzai-tvbild-1.bin"),
			"Zwischendatei des Helfers erkannt")
	for bad in ["C:\\Windows\\win.ini", "uzai-tvbild-1.bin", "C:\\Temp\\..\\uzai-tvbild-1.bin", "C:\\Temp\\uzai-tvbild-1.bin.exe",
			"C:\\Temp\\uzai-tvbild-x.bin", ""]:
		check(not Spielbild.datei_ok(bad), "keine andere Datei: „%s“" % bad)
	# Ganzer Weg wie im Spiel: Datei schreiben (wie der Helfer), lesen, ins selbe Bild legen.
	var root := OS.get_environment("UZAI_DATA")
	if root == "":
		root = OS.get_user_data_dir()
	var pfad := root.path_join("uzai-tvbild-99.bin")
	var px := PackedByteArray()
	px.resize(4 * 2 * 4)
	px.fill(200)
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	f.store_buffer(_kopf(2, 4, 2))
	f.store_buffer(px)
	# Feste Größe wie beim Helfer (UzTvFang.Dateigroesse).
	var rest := PackedByteArray()
	rest.resize(Spielbild.FANG_MAX_PX * 4 - px.size())
	f.store_buffer(rest)
	f.close()
	var sb := Spielbild.new()
	sb._fang_datei = pfad
	var bilder: Array = []
	sb.bild.connect(func(img: Image) -> void: bilder.append(img))
	sb._fang_lesen()
	check(bilder.size() == 1 and (bilder[0] as Image).get_size() == Vector2i(4, 2) and (bilder[0] as Image).get_format() == Image.FORMAT_RGBA8,
			"Datei → Bild (RGBA, 4×2)")
	sb._fang_lesen()
	check(bilder.size() == 1, "gleiche Folgenummer: kein zweites Mal")
	f = FileAccess.open(pfad, FileAccess.READ_WRITE)
	f.store_buffer(_kopf(4, 4, 2))
	f.close()
	sb._fang_lesen()
	check(bilder.size() == 2 and bilder[1] == bilder[0], "neues Bild gleicher Größe: dasselbe Image (keine neue Textur je Bild)")
	sb._fang_fa.close()
	sb.free()
	DirAccess.remove_absolute(pfad)
	check(Spielbild.fang_fps("mittel") >= 30 and Spielbild.fang_fps("hoch") <= 60 and Spielbild.fang_fps("leicht") >= 15,
			"30–60 Bilder/s beim Herumlaufen")
	for st in Spielbild.FANG:
		var fw: Array = Spielbild.FANG[st]
		check(int(fw[1]) <= 960 and int(fw[2]) <= 540, "„%s“: klein (%d×%d)" % [st, int(fw[1]), int(fw[2])])
	for st in Spielbild.TAKT:
		check(float(Spielbild.TAKT[st][0]) >= 0.25, "Rückfall PrintWindow „%s“: höchstens 4 Bilder/s (bremst das Spiel)" % st)
	var sbs := _src("res://src/room/spielbild.gd")
	check(_fn(sbs, "func _schritt(").find("fang_moeglich()") < _fn(sbs, "func _schritt(").find("_warte -= dt"), "erst Windows Graphics Capture, PrintWindow nur als Rückfall")
	check(_fn(sbs, "func _fang_start(").contains("weg = \"printwindow\"") and _fn(sbs, "func _fang_start(").contains("Launcher.log_launch("),
			"Weg und Rückfall stehen in launch.log")
	check(_fn(sbs, "func _exit_tree(").contains("_fang_aus()") and _fn(sbs, "func _fang_aus(").contains("\"an\": false"), "Zimmer zu: Aufnahme aus")
	var an := _src("res://src/room/zimmer_ansehen.gd")
	check(_fn(an, "func _tv_im_bild(").contains("not visible"), "Aufnahme nie, solange das Zimmer hinter dem Spiel wartet")
	check(_fn(_src("res://src/room/zimmer_basis.gd"), "func ruhe_fps(").contains("Launcher.log_launch("), "Bildrate hinter dem Spiel in launch.log")
	check(_src("res://src/core/helper.gd").find("\"tv-fang\"") < 0, "„tv-fang“ immer im Hauptweg (derselbe Helfer-Prozess, übersetzt nicht im schnellen Weg)")
	for st in Spielbild.FANG:
		check(int((Spielbild.FANG[st] as Array)[0]) <= 30, "„%s“: höchstens 30 Bilder/s beim Herumlaufen (Kopie kostet Spiel und Zimmer Zeit)" % st)
	_schwarz_und_spiegel()
	_sparsam()


## Schwarze Bilder: Farbe vom Helfer, Raster-Mittel, einmal der Spiegel, dann „kein Bild“.
func _schwarz_und_spiegel() -> void:
	print("Schwarze Bilder und Spiegel")
	check(Spielbild.farbe_schwarz(0x000000) and Spielbild.farbe_schwarz(0x020202) and not Spielbild.farbe_schwarz(0x202020)
			and not Spielbild.farbe_schwarz(-1), "Farbe des Helfers: schwarz wie fast_schwarz (unbekannt zählt nicht)")
	check(Spielbild.spiel_weg("schwarz", false, false) == "spiegel" and Spielbild.spiel_weg("Fenster 80070057", false, false) == "spiegel",
			"nur schwarz oder Fenster abgelehnt (Call of Duty: 80070057) → einmal der Spiegel")
	check(Spielbild.spiel_weg("schwarz", true, false) == "" and Spielbild.spiel_weg("schwarz", false, true) == ""
			and Spielbild.spiel_weg("nicht unterstützt", false, false) == "" and Spielbild.spiel_weg("daten", false, false) == "",
			"Spiegel nur einmal, nicht bei altem Windows oder falschen Daten")
	# Mittel aus dem Raster: ein 4:3-Bild mit schwarzen Rändern im 16:9-Fenster (PS2 in PCSX2).
	var img := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(120, 0, 720, 540), Color(0.4, 0.4, 0.4))
	var m := Spielbild.mittelfarbe(img)
	check(absf(m.r - 0.3) < 0.04 and not Spielbild.fast_schwarz(img), "Mittel über das ganze Bild (4:3 mit Rändern: %.2f statt 0,30)" % m.r)
	img.fill(Color(0.004, 0.004, 0.004))
	check(Spielbild.fast_schwarz(img), "fast schwarz bleibt schwarz")
	var sb := Spielbild.new()
	sb.weg = "wgc"
	var leer := [0]
	sb.kein_bild.connect(func() -> void: leer[0] += 1)
	for i in Spielbild.SCHWARZ_BILDER - 1:
		sb._neu(img, 0)
	check(not sb.spiegel and leer[0] == 0, "noch keine Schwelle: nichts")
	sb._neu(img, 0)
	check(sb.spiegel and sb._spiegel_versucht and leer[0] == 0, "nur schwarz → Spiegel versuchen (statt gleich „Läuft gerade“)")
	sb._fang_spiegel = true
	for i in Spielbild.SCHWARZ_BILDER:
		sb._neu(img, 0)
	check(leer[0] == 1, "auch der Spiegel schwarz → kein Bild (einmal, nicht bei jedem Bild)")
	var hell := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	hell.fill(Color(0.5, 0.5, 0.5))
	var bilder := [0]
	sb.bild.connect(func(_i: Image) -> void: bilder[0] += 1)
	sb._neu(hell, 0x808080)
	check(bilder[0] == 1 and sb._schwarz == 0, "helles Bild: sofort wieder da")
	# Weg und Rückfälle gelten je Spiel: Früher blieb ein offenes Zimmer nach einem Rückfall auf PrintWindow (Spiel mit
	# Adminrechten) für jedes weitere Spiel dabei – langsam, und es bremste das Spiel.
	sb.weg = "printwindow"
	sb._fang_fehler = Spielbild.FANG_VERSUCHE
	var lief := Launcher.in_game
	Launcher.in_game = false
	sb._schritt(0.016)
	check(sb.weg == "" and not sb.spiegel and not sb._spiegel_versucht and sb._fang_fehler == 0,
			"Spiel aus: Weg wieder offen, Spiegel wieder möglich – das nächste Spiel versucht erst Windows Graphics Capture")
	Launcher.in_game = lief
	sb.free()
	var sbs := _src("res://src/room/spielbild.gd")
	check(_fn(sbs, "func _fang_args(").contains("\"spiegel\"") and _fn(sbs, "func _fang_start(").contains("spiel_weg(grund"),
			"Spiegel geht als Wunsch an den Helfer, auch nach „Fenster …“-Fehlern")
	check(_fn(sbs, "func _messwerte(").contains("zustand") and _fn(sbs, "func _messwerte(").contains("erstes")
			and _fn(sbs, "func _fang_weiter(").contains("_messwerte(res)"), "Messwerte des Helfers (Fenster, HDR, erstes Bild) in launch.log")


## Schlanker Weg neben dem laufenden Spiel (Kompatibilität: sparsam), Bildrate und Bildzeiten.
func _sparsam() -> void:
	print("Sparsam neben dem Spiel")
	var Licht := load("res://src/room/licht.gd")
	var Bildzeit := load("res://src/room/bildzeit.gd")
	var u: Dictionary = Licht.werte("ultra", "forward")
	var s: Dictionary = Licht.spar_werte(u, 3840)
	check(int(s.msaa) <= 2 and int(s.lampen_schatten) == 0 and int(s.schatten) == 2048 and not bool(s.ssil) and not bool(s.ssr)
			and not bool(s.nebel), "Ultra aufgestanden: MSAA höchstens 2×, keine Lampenschatten, Sonne 2048, ohne SSIL/SSR/Nebel")
	check(bool(s.ssao) == bool(u.ssao) and bool(s.gi) == bool(u.gi), "SSAO und GI bleiben (der Raum sieht gleich aus)")
	check(absf(float(s.skala) - 0.67) < 0.01 and float(Licht.spar_werte(u, 2560).skala) == 0.8 and float(Licht.spar_werte(u, 1920).skala) == 1.0,
			"3D-Auflösung nur auf großen Bildschirmen kleiner (4K 67 %, 1440p 80 %, 1080p voll)")
	var l: Dictionary = Licht.spar_werte(Licht.werte("leicht", "forward"), 3840)
	check(int(l.msaa) == 0 and int(l.schatten) == 0, "Leicht bleibt Leicht")
	var dts := PackedFloat32Array()
	var ab := PackedFloat32Array()
	for i in 100:
		dts.append(16.0 if i < 95 else 40.0)
		ab.append(3.0)
	var z: String = Bildzeit.zusammenfassung(dts, ab, 2.0, 3.0, 1.5, 60, "31.0 ms (Skripte 2.1 ms)")
	check(z.contains("Bilder/s (Kappe 60)") and z.contains("95 % ≤ 16.0 ms") and z.contains("längste 40.0 ms") and z.contains("Grafikkarte Ø 5.0 ms")
			and z.contains("3D-Zimmer 3.0 ms") and z.contains("Ruckler (Bild > 1,6 × 16.7 ms) 5 von 100") and z.contains("Ablauf je Bild Ø 3.0 ms, längster 31.0 ms"), z)
	check(Bildzeit.zusammenfassung(PackedFloat32Array(), PackedFloat32Array(), 0, 0, 0, 0) == "keine Bilder", "ohne Bilder: klar")
	var bz := _src("res://src/room/bildzeit.gd")
	check(bz.find("TIME_PROCESS") < 0 and _fn(bz, "func _process(").contains("_anlauf") and _fn(bz, "func _process(").contains("ablauf_bild_ms"),
			"Bildzeiten: echte Abläufe je Bild, die Umstellung selbst (erste Sekunde) zählt nicht")
	var ls := _src("res://src/room/leistung.gd")
	check(_fn(ls, "func _ready(").contains("frame_post_draw.connect(_gezeichnet)") and _fn(ls, "func _gezeichnet(").contains("_teuerster_jetzt()"),
			"Ablauf je Bild bis nach dem Zeichnen, mit dem teuersten Abschnitt")
	var an := _src("res://src/room/zimmer_ansehen.gd")
	var zb := _src("res://src/room/zimmer_basis.gd")
	check(_fn(an, "func tv_wechsel(").contains("_spar_lage(z)") and _fn(zb, "func _spar_lage(").contains("_spar_setzen(laeuft)")
			and _fn(an, "func _spiel_pruefen(").contains("_spar_lage(_spiel_lage)"),
			"schlank, solange das Spiel läuft – sitzend, aufgestanden und mit dem Guide darüber")
	check(_fn(zb, "func close(").contains("_spar_setzen(false)") and _fn(zb, "func _spar_setzen(").contains("leistung.schlank_setzen(false)")
			and _fn(zb, "func _spar_setzen(").contains("welt.schlank_setzen(false)"), "Zimmer zu oder Spiel aus: alles zurück, wie die Stufe es will")
	check(_fn(zb, "func _vorrang(").contains("\"uzai-vorrang\"") and _fn(zb, "func _vorrang(").contains("OS.get_process_id()"),
			"Uzai nimmt sich selbst zurück (nur der eigene Prozess)")
	check(_fn(zb, "func _vorrang(").contains("\"cpu\": false"), "nur die Grafikkarte zurück – der Prozessor bleibt normal (Ruckler)")
	var ks := _fn(zb, "func ruhe_fps(")
	check(ks.contains("Leistung.spiel_kappe(") and ks.contains("Fernsehspiel.alle_fokussiert(") and not ks.contains("leicht"),
			"weniger Bilder nur, wenn alle aufs Spiel schauen: ganzer Teil der Bildschirmrate, nie unter 60")
	var zs := _src("res://src/room/zimmer.gd")
	check(not zs.contains("leistung.kappe") and not _src("res://src/room/leistung.gd").contains("var kappe"),
			"im Zimmer neben dem Spiel volle Bildrate (keine Kappe, wer sich umsieht, sieht es flüssig)")
	check(_fn(zs, "func _process(").find("if modus == \"spiel\":") < _fn(zs, "func _process(").find("leistung.vor_bild()"),
			"wartet das Zimmer hinter dem Spiel: kein Bild, keine Eingabe")
	var rz := _fn(zb, "func ruhen(")
	check(rz.contains("visible = false") and rz.contains("UPDATE_DISABLED") and rz.contains("modus = \"spiel\""), "ruhen: unsichtbar, die 3D-Ansicht zeichnet nicht")
	var sp := _fn(zb, "func _spar_setzen(")
	check(sp.contains("if an and forward:") and sp.contains("leistung.schlank_setzen(true)") and sp.contains("welt.schlank_setzen(true)")
			and sp.contains("MSAA_DISABLED") and _fn(zb, "func _spar_lage(").contains("_spiel_lage = z"),
			"Forward+ neben dem Spiel: schlanker Weg (FSR 1, ohne MSAA) für jede Stufe")
	# Die vier Zweige (an/aus × Forward+/Kompatibilität) hängen an einer Kette; was danach für alle gilt,
	# steht hinter ihr – ein „if“ davor nahm dem letzten Zweig sein „else“ (er lief dann auch beim Einschalten).
	var sp_aus := sp.find("\telse:\n\t\tif leistung:\n\t\t\tleistung.spar(false)")
	var sp_pipe := sp.find("\tif forward and _pipeline_folge.is_empty():")
	check(sp_aus > sp.find("\telif forward:") and sp_pipe > sp_aus and not sp.substr(sp_pipe).contains("\n\telse:"),
			"schlanker Weg: „Kompatibilität aus“ ist der letzte Zweig der Kette, die Pipelines kommen danach")
	var rs := _fn(_src("res://src/room/raum.gd"), "func schlank_setzen(")
	check(rs.contains("env.ssao_enabled") and rs.contains("env.glow_enabled") and rs.contains("env.ssr_enabled") and rs.contains("env.volumetric_fog_enabled")
			and rs.contains("_strahl.visible = false"), "schlank: ohne SSAO, Glühen, SSR, Nebel und Lichtstrahl")
	check(_fn(_src("res://src/room/raum.gd"), "func sonde_neu(").contains("if schlank:"), "schlank: die Sonde nimmt nicht neu auf (erst danach)")
	var zw := _src("res://src/room/zimmer_welt.gd")
	var flimmern := _fn(zw, "func tv_flimmern(").get_slice("\n\n", 0)
	check(_fn(zw, "func lampen_auffrischen(").contains("and not schlank") and flimmern.contains("_tv_licht()")
			and not flimmern.contains("lampen_auffrischen"),
			"schlank ohne Lampenschatten auf Möbeln; das Flimmern des Fernsehers ändert nur sein eigenes Licht")


## Fokus-Modus (nur vor dem Fernseher und im Vollbild hat das Spiel den Controller) und der Spielton
## aus dem Fernseher (raumton.gd): Pegel, Antworten des Helfers, Abläufe im Code.
func _fokus_und_ton() -> void:
	print("Fokus-Modus")
	for z in F.ZUSTAENDE:
		check(F.fokus_gesperrt(str(z)) == (z == "zimmer"), "„%s“: Spiel darf %s nach vorn" % [z, "nicht" if z == "zimmer" else ""])
	check(not F.ton_im_raum("vollbild") and F.ton_im_raum("zimmer") and F.ton_im_raum("startet"), "Ton normal nur im Vollbild, sonst aus dem Fernseher")
	var la := _src("res://src/core/launcher.gd")
	var fg := _fn(la, "func focus_game(")
	check(fg.find("if fokus_gesperrt:") >= 0 and fg.find("if fokus_gesperrt:") < fg.find("Helper.run(\"focus\""), "Launcher.focus_game: im Zimmer nie das Spiel nach vorn")
	var fe := _src("res://src/main_fenster.gd")
	check(fe.contains("Launcher.fokus_gesperrt = Fernsehspiel.fokus_gesperrt(z)") and fe.contains("_tv_zimmer_wache.call_deferred(_tv_gen)"),
			"jeder Wechsel des Zustands stellt die Sperre; aufgestanden wacht Uzai über den Fokus")
	var wa := _fn(fe, "func _tv_zimmer_wache(")
	check(wa.contains("fg_game") and wa.contains("\"focus\", { \"pid\": OS.get_process_id() }") and not wa.contains("\"keys\""),
			"Fokus zurück nur, wenn ein Fenster des Spiels vorn liegt – nur Uzais eigener Prozess, keine Tasten")
	check(Ansehen.TV_ANTEIL >= 0.75 and Ansehen.TV_ANTEIL <= 0.8, "beim Start vor dem Fernseher: Bildschirm füllt fast das Bild (%d %%)" % roundi(Ansehen.TV_ANTEIL * 100.0))

	print("Spielton aus dem Fernseher")
	var vorn := Raumton.pegel(Transform3D(), Vector3(0, 0, -1.0))
	check(is_equal_approx(vorn.x, vorn.y) and is_equal_approx(vorn.x, Raumton.GEDAEMPFT), "nah und vorn: mittig, nur leicht gedämpft (%.2f)" % vorn.x)
	var weit := Raumton.pegel(Transform3D(), Vector3(0, 0, -Raumton.NAH_M * 4.0))
	check(absf(weit.x - 0.25 * Raumton.GEDAEMPFT) < 0.001, "viermal so weit: ein Viertel (%.2f)" % weit.x)
	var sehr_weit := Raumton.pegel(Transform3D(), Vector3(0, 0, -500.0))
	check(is_equal_approx(sehr_weit.x, Raumton.MIN_PEGEL * Raumton.GEDAEMPFT), "nie ganz still")
	var rechts := Raumton.pegel(Transform3D(), Vector3(2.0, 0, 0))
	check(rechts.y > rechts.x and is_equal_approx(rechts.x, rechts.y * (1.0 - Raumton.BALANCE)), "Fernseher rechts: rechts lauter (%.2f / %.2f)" % [rechts.x, rechts.y])
	var links := Raumton.pegel(Transform3D(), Vector3(-2.0, 0, 0))
	check(links.x > links.y, "Fernseher links: links lauter")
	var hinten := Raumton.pegel(Transform3D(), Vector3(0, 0, 1.0))
	check(is_equal_approx(hinten.x, hinten.y) and hinten.x < vorn.x, "hinter dir: mittig und leiser")
	var gedreht := Raumton.pegel(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5, 1.6, 5)), Vector3(3, 1.6, 5))
	check(absf(gedreht.x - gedreht.y) < 0.001, "Blick zählt: nach links gedreht liegt der Fernseher links vor dir genau vorn")
	var gedreht2 := Raumton.pegel(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5, 1.6, 5)), Vector3(5, 1.6, 3))
	check(gedreht2.y > gedreht2.x, "… und was vorher vorn lag, liegt jetzt rechts")
	check(Raumton.pegel(Transform3D(), null) == Vector2(Raumton.OHNE_TV, Raumton.OHNE_TV), "kein Fernseher im Raum: leise, mittig")
	check(Raumton.gerundet(Vector2(0.12345, 1.7)) == Vector2(0.123, 1.0), "auf Tausendstel, höchstens 1")
	check(Raumton.TAKT_HZ <= 10.0 and Raumton.SCHWELLE > 0.0 and Raumton.PULS_S < Raumton.LEASE_S and Raumton.GLAETTEN_S > 0.1,
			"gedrosselt (≤ 10 je Sekunde, nur bei Änderung), Lebenszeichen vor Ablauf der Wache, weich")

	print("Antworten des Helfers")
	var ok := Raumton.antwort({ "ok": true, "result": { "json": '{"found":true,"kanal":true,"sessions":2,"alt":[1000,980]}' } })
	check(bool(ok.found) and bool(ok.kanal) and int(ok.sessions) == 2 and ok.alt == [1000, 980] and not bool(ok.error), "gesetzt, alte Werte gelesen")
	check(Raumton.antwort({ "ok": true, "result": { "json": '{"found":true,"alt":[1000,"x"]}' } }).alt == [], "fremde alte Werte: verworfen")
	check(Raumton.werte([1, 2, 3, 4, 5, 6, 7, 8, 9]) == [] and Raumton.werte([-1]) == [] and Raumton.werte([1001]) == [] and Raumton.werte("1") == []
			and Raumton.werte([0, 999.6]) == [0, 1000], "alte Werte: höchstens acht Zahlen 0..1000")
	var aus := Raumton.antwort({ "ok": true, "result": { "json": '{"found":false,"zurueck":0,"weg":1}' } })
	check(int(aus.weg) == 1 and not bool(aus.error), "zurück: eine Sitzung war schon weg (Vermerk bleibt)")
	check(bool(Raumton.antwort({ "ok": false, "error": "nur unter Windows" }).error) and bool(Raumton.antwort({ "ok": true, "result": { "json": '{"found":false,"timeout":true}' } }).error),
			"ohne Helfer oder Zeitüberschreitung: Fehler (Vermerk bleibt)")

	print("Ton: Abläufe im Code")
	check("raum-ton" in HelperScript.FAST and "raum-ton" in HelperScript.EBENEN, "„raum-ton“: schneller Weg, immer derselbe Helfer-Prozess (alte Werte liegen dort)")
	var rt := _src("res://src/room/raumton.gd")
	check(_fn(rt, "func _exit_tree(").contains("zurueck()"), "Zimmer zu (auch Uzai beendet): zurück")
	check(_fn(rt, "func _process(").contains("if not Launcher.in_game:") and _fn(rt, "func _process(").contains("_aus()"), "Spielende und Fokus: zurück")
	check(_fn(_src("res://src/main_ebenen.gd"), "func _on_game_window(").contains("Raumton.aufraeumen()"), "nach einem Absturz: beim nächsten Start des Spiels zurück")
	var zi := _src("res://src/room/zimmer.gd")
	check(zi.contains("raumton = Raumton.new()") and zi.contains("raumton.zustand"), "das Zimmer hört zu (Kamera, Fernseher, Zustand)")


func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _fn(src: String, kopf: String) -> String:
	var a := src.find(kopf)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)


## Die Tabelle (main_fenster.gd meldet jeden Wechsel von _tv an src/core/zustand.gd) kennt genau die Wechsel von weiter().
func _tabelle() -> void:
	var schluessel: Array = F.ZUSTAENDE_TV.keys().filter(func(k: String) -> bool: return k != "*")
	var stimmt := schluessel.size() == F.ZUSTAENDE.size() and F.ZUSTAENDE.all(func(z: String) -> bool: return z in schluessel)
	var wechsel := {}
	for z in F.ZUSTAENDE:
		for e in ["einlegen", "vollbild", "aufstehen", "ende", "quatsch"]:
			var n := F.weiter(str(z), e)
			stimmt = stimmt and Zustand.erlaubt(F.ZUSTAENDE_TV, str(z), n)
			wechsel["%s>%s" % [z, n]] = true
	for z in schluessel:
		for w in F.ZUSTAENDE_TV[z]:
			stimmt = stimmt and wechsel.has("%s>%s" % [z, w])
	check(stimmt and _src("res://src/main_fenster.gd").contains("Zustand.wechsel(\"zimmer.fernseher\", Fernsehspiel.ZUSTAENDE_TV, _tv, z)"),
			"Tabelle zimmer.fernseher: genau die Wechsel von weiter(), _tv meldet jeden")


func _ready() -> void:
	print("Zustände")
	check(_folge("", ["einlegen", "vollbild", "aufstehen", "vollbild", "ende"]) == ["startet", "vollbild", "zimmer", "vollbild", ""],
			"Einlegen → hinein ins Vollbild → Guide: zurück ins Zimmer → A am Fernseher: wieder hinein → Ende")
	check(_folge("", ["vollbild"]) == [""], "ohne Einlegen kein Vollbild")
	check(F.weiter("", "aufstehen") == "zimmer", "Guide › Dein Zimmer im Spiel: im Zimmer")
	check(F.weiter("startet", "aufstehen") == "startet" and F.weiter("zimmer", "aufstehen") == "zimmer", "beim Start und im Zimmer: kein Aufstehen")
	check(F.weiter("startet", "einlegen") == "startet" and F.weiter("vollbild", "einlegen") == "vollbild", "zweimal Einlegen ändert nichts")
	check(not ("fernseher" in F.ZUSTAENDE) and not ("guide" in F.ZUSTAENDE), "kein eigener Zustand „vor dem Fernseher“ mehr (Vollbild ersetzt ihn)")
	for alt in ["fenster", "guide_auf", "guide_zu", "fernseher", "minimiert"]:
		check(F.weiter("startet", alt) == "startet" and F.weiter("zimmer", alt) == "zimmer", "altes Ereignis „%s“: wirkt nicht mehr" % alt)
	for z in F.ZUSTAENDE:
		check(F.weiter(str(z), "ende") == "", "Ende aus „%s“ → aus" % z)
		check(F.weiter(str(z), "quatsch") == str(z), "unbekanntes Ereignis in „%s“: bleibt" % z)
	check(F.weiter("unsinn", "einlegen") == "startet", "unbekannter Zustand gilt als aus")
	_tabelle()

	print("Guide-Taste")
	check(F.guide_taste("vollbild") == "aufstehen", "im Vollbild: zurück ins Zimmer – ohne Guide, ohne Halten")
	for z in ["", "startet", "zimmer"]:
		check(F.guide_taste(z) == "guide", "„%s“: Guide wie immer (im Zimmer öffnet erst der nächste Druck ihn)" % z)
	check(F.uzai_vorn("startet") and F.uzai_vorn("zimmer") and not F.uzai_vorn("vollbild") and not F.uzai_vorn(""),
			"Uzai deckt selbst: Start, Zimmer (dann keine Wache)")

	print("Alle aufs Spiel fokussiert (Bildrate des Zimmers)")
	check(F.alle_fokussiert("vollbild", []), "allein im Vollbild: niemand sieht das Zimmer")
	check(not F.alle_fokussiert("zimmer", []) and not F.alle_fokussiert("startet", []) and not F.alle_fokussiert("", []),
			"im Zimmer (oder beim Start): volle Bildrate")
	check(F.alle_fokussiert("vollbild", [{ "fokus": true }, { "fokus": true }]), "Gäste alle im Vollbild: ebenso")
	check(not F.alle_fokussiert("vollbild", [{ "fokus": true }, { "fokus": false }]), "ein Gast läuft im Zimmer: volle Bildrate")
	check(not F.alle_fokussiert("vollbild", [{}]) and not F.alle_fokussiert("vollbild", ["quatsch"]), "Gast ohne Angabe zählt als im Zimmer")

	print("Zeitgrenzen")
	check(Launcher.WINDOW_MAX_MS < 180 * 1000, "Start im Fernseher endet spätestens mit dem Launcher (%d ms), vor der Grenze des Vorn-Haltens (180 s)" % Launcher.WINDOW_MAX_MS)
	check(Vorhang.WARTEN_MS >= Launcher.WINDOW_MAX_MS and Vorhang.WARTEN_MS <= Vorhang.MAX_MS, "Vorhang um wartende Fenster hält so lange wie der Start")
	check(F.PRUEF_S >= 0.5 and F.PRUEF_S <= 2.0, "Fokus-Wache prüft maßvoll (je %.1f s)" % F.PRUEF_S)

	print("Platz vor dem Fernseher")
	# Flachbild an der Rückwand (z = 0), Bildschirm 1,31 × 0,74 m, Mitte bei x = 3, Höhe 0,99.
	var gt := Transform3D(Basis(), Vector3(3.0, 0.99, 0.2))
	var s: Array = Ansehen.sitz_vor(gt, Vector2(1.31, 0.74), 6.0, 5.0, 16.0 / 9.0)
	var cam: Transform3D = s[0]
	var blick := -cam.basis.z
	check(blick.distance_to(Vector3(0, 0, -1)) < 0.001, "genau von vorn (von dort gerade hinein)")
	check(absf(cam.origin.y - 0.99) < 0.001 and absf(cam.origin.x - 3.0) < 0.001, "auf Höhe und Mitte des Bildschirms")
	var d := cam.origin.z - 0.2
	var halb := d * tan(deg_to_rad(float(s[1])) * 0.5) * 16.0 / 9.0
	check(absf(0.655 / halb - Ansehen.TV_ANTEIL) < 0.01, "Bildschirm füllt %.0f %% der Breite" % (0.655 / halb * 100.0))
	var eng: Array = Ansehen.sitz_vor(gt, Vector2(1.31, 0.74), 6.0, 1.2, 16.0 / 9.0)
	check((eng[0] as Transform3D).origin.z <= 1.2 - 0.15 + 0.001, "kleiner Raum: nie hinter der Wand gegenüber")
	var schraeg := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.2, 0.99, 2.5))
	var s2: Array = Ansehen.sitz_vor(schraeg, Vector2(1.31, 0.74), 6.0, 5.0, 16.0 / 9.0)
	check((-(s2[0] as Transform3D).basis.z).distance_to(Vector3(-1, 0, 0)) < 0.001, "Fernseher an der Seitenwand: ebenso von vorn")

	print("Laufen und Umsehen (straff)")
	check(Zimmer.stick_kurve(Vector2(0.12, 0.05), 1.0) == Vector2.ZERO, "Totzone: leichter Drift bewegt nichts")
	var klein := Zimmer.stick_kurve(Vector2(Zimmer.TOTZONE + 0.02, 0.0), 1.0)
	check(klein.x > 0.0 and klein.x < 0.05, "knapp über der Totzone: fein, ohne Sprung (%.3f)" % klein.x)
	check(is_equal_approx(Zimmer.stick_kurve(Vector2(0.97, 0.0), 1.0).x, 1.0), "fast voller Ausschlag zählt voll (Rand)")
	var halb_l := Zimmer.stick_kurve(Vector2(0.55, 0.0), 1.0).x
	check(absf(halb_l - (0.55 - Zimmer.TOTZONE) / (1.0 - Zimmer.TOTZONE - Zimmer.RAND)) < 0.001, "Laufen linear (%.2f bei 55 %%)" % halb_l)
	var halb_b := Zimmer.stick_kurve(Vector2(0.55, 0.0), Zimmer.KURVE_BLICK).x
	check(is_equal_approx(halb_b, halb_l), "Umsehen: linear wie das Laufen (%.2f)" % halb_b)
	var rund := Zimmer.stick_kurve(Vector2(0.6, 0.6), 1.0)
	check(rund.length() <= 1.0001 and absf(rund.x - rund.y) < 0.0001, "runde Totzone, schräg nicht schneller")
	var vorher := -1.0
	var stetig := true
	for i in 41:
		var v := Zimmer.stick_kurve(Vector2(i / 40.0, 0.0), Zimmer.KURVE_BLICK).x
		stetig = stetig and v >= vorher - 0.00001
		vorher = v
	check(stetig, "Kurve steigt stetig")
	var kb := Zimmer.Bew.neu(Vector3(1, 0, 2.5))
	for i in 15:
		Zimmer.Bew.schritt(kb, Vector3(1, 0, 0), Zimmer.TEMPO, false, false, Zimmer.Bew.welt_aus(6.0, 5.0, 2.7, []), 1.0 / 60.0)
	check((kb.vel as Vector3).x > Zimmer.TEMPO * 0.85, "nach 0,25 s fast volles Tempo (Source: Beschleunigung 10, keine Schwimm-Glättung)")
	check(Zimmer.stick_kurve(Vector2(0.13, 0.0), Zimmer.KURVE_BLICK, Zimmer.TOTZONE_BLICK).x > 0.0, "Umsehen: kleine Totzone (%.2f)" % Zimmer.TOTZONE_BLICK)
	check(is_equal_approx(Zimmer.maus_empf(), 1.0) and is_equal_approx(Zimmer.stick_empf(), 1.0) and is_equal_approx(Zimmer.y_achse(), 1.0)
			and is_equal_approx(Zimmer.sicht_fov(), 70.0) and not Zimmer.tiefe_an(), "Standard: Empfindlichkeit 100 %, Y normal, 70°, Tiefenschärfe aus")
	var mb := _fn(_src("res://src/room/zimmer.gd"), "func _maus_blick(")
	check(mb.contains("yaw -= r.x * k") and mb.contains("_yaw_soll = yaw") and not mb.contains("lerp"), "Maus roh: Pixel × Empfindlichkeit, ohne Nachziehen")
	check(Zimmer.TEMPO >= 2.2 and Zimmer.TEMPO <= 2.6 and Zimmer.TEMPO_RENNEN >= 3.6 and Zimmer.TEMPO_RENNEN <= 4.4,
			"Gehen %.2f m/s, Rennen %.1f m/s (HL2 190 und 320 u/s im Zimmer-Maßstab)" % [Zimmer.TEMPO, Zimmer.TEMPO_RENNEN])
	var hoch := Zimmer.SPRUNG * Zimmer.SPRUNG / (2.0 * Zimmer.SCHWERE)
	check(hoch > 0.3 and hoch < 0.6, "Sprung %.2f m hoch" % hoch)
	var zsrc := _src("res://src/room/zimmer.gd")
	check(not zsrc.contains("_look_vel"), "Umsehen ohne Trägheit")
	var kam := _fn(zsrc, "func _kamera(")
	check(kam.contains("_direkt") and kam.contains("if ich and (nah or _direkt > 0.0) else 0.0"),
			"Ich-Ansicht ohne Nachlauf, andere Blicke gleiten weich (nie ein Sprung)")
	check(kam.contains("blick in [\"ich\", \"schulter\"]"), "auch der Schulterblick ohne Nachlauf")
	check(kam.contains("tiefe_an() and modus == \"ansehen\"") and kam.contains("99.0, 0.0"), "Tiefenschärfe nur auf Wunsch, beim Laufen und Bauen nie")
	check(kam.contains("cam.near = 0.2 if oben"), "von oben: Nahebene weiter weg (kein Flackern flacher Lagen)")
	check(kam.contains("6.5"), "Bau-Modus und Ansehen: Kamera unverändert")

	print("Abläufe im Code")
	var eb := _src("res://src/main_ebenen.gd")
	var fe := _src("res://src/main_fenster.gd")
	var gu := _src("res://src/main_guide.gd")
	var an := _src("res://src/room/zimmer_ansehen.gd")
	check(_fn(an, "func _einlegen_fernseher(").contains("main.launch(g, true)"), "Einlegen startet im Fernseher")
	check(_fn(eb, "func launch(").contains("alle_ebenen_zu(zim)") and _fn(eb, "func launch(").contains("launch(g2, im_fernseher)"),
			"das Zimmer bleibt offen; auch nach der Wahl des Launchers")
	var eb_w := _fn(eb, "func _on_game_window(")
	check(eb_w.contains("_tv == \"startet\"") and eb_w.contains("_tv_einsteigen()"), "Spielfenster da: die Kamera fährt in den Fernseher")
	check(_fn(fe, "func _tv_einsteigen(").contains("zim.call(\"ins_spiel\")") and _fn(an, "func ins_spiel(").contains("zum_spiel()"),
			"… erst das Spiel im Fernseher, dann hinein")
	var zs := _fn(eb, "func zimmer_zum_spiel(")
	check(zs.contains("zimmer.call(\"ruhen\", true)") and zs.contains("await _park()") and zs.contains("Fernsehspiel.weiter(_tv, \"vollbild\")")
			and zs.find("ruhen") < zs.find("await _park()"), "Vollbild: das Zimmer bleibt offen und wartet dahinter, Uzai ruht")
	check(_fn(fe, "func _park(").contains("_ruhe_takt()") and _fn(fe, "func _ruhe_takt(").contains("zim.call(\"ruhe_fps\")"),
			"im Vollbild bestimmt das wartende Zimmer die Bildrate")
	var tg := _fn(gu, "func toggle_guide(")
	check(tg.contains("Fernsehspiel.guide_taste(_tv) == \"aufstehen\"") and tg.contains("tv_aufstehen()") and not tg.contains("zum_spiel")
			and tg.find("tv_aufstehen()") < tg.find("_guide_gen += 1") and tg.find("tv_aufstehen()") < tg.find("_druck_merken("),
			"Guide-Taste im Vollbild: sofort zurück ins Zimmer, bevor der Guide auf- oder zugeht und ohne aufs Loslassen zu warten")
	var au := _fn(eb, "func tv_aufstehen(")
	check(au.contains("zim.call(\"aus_dem_spiel\")") and au.contains("_enter_overlay()") and au.contains("Nav.layers.insert"),
			"zurück ins Zimmer: Uzai vorn, die Kamera fährt aus dem Fernseher; der Guide nimmt das Zimmer nicht mit")
	var ad := _fn(an, "func aus_dem_spiel(")
	check(ad.contains("svc.modulate.a = 0.0") and ad.contains("spielbild.letztes = null") and ad.find("svc.modulate.a = 1.0") > ad.find("_spiel_voll.texture"),
			"zurück ohne Schwarz: erst durchsichtig (dahinter das Spiel), dann deckt das frische Bild genau, was zu sehen war")
	check(_fn(eb, "func tv_vollbild(").contains("zum_spiel") and _fn(eb, "func open_room(").contains("tv_aufstehen()"),
			"Guide › Zum Spiel fährt hinein; Guide › Dein Zimmer im Vollbild holt das wartende Zimmer")
	check(_fn(fe, "func _leave_overlay(").contains("_tv == \"zimmer\"") and _fn(gu, "func _on_guide_closed(").contains("_tv == \"zimmer\""),
			"im Zimmer: Uzai bleibt vorn, das Spiel läuft weiter")
	var gg := _src("res://src/ui/components/guide_game.gd")
	var zz := _fn(gg, "static func zimmer_zeilen(")
	check(zz.contains("\"Zum Spiel\"") and zz.contains("\"Dein Zimmer\"") and not zz.contains("\"Vollbild\"") and not zz.contains("\"Aufstehen\""),
			"Guide: im Zimmer „Zum Spiel“, über dem Spiel „Dein Zimmer“")
	for alt in ["func _tv_fenster(", "func tv_bild(", "func _tv_pruefen(", "func tv_zurueck(", "func tv_im_zimmer(", "func tv_fenster_zeigen("]:
		check(not fe.contains(alt) and not eb.contains(alt), "kein toter Weg mehr: %s" % alt.trim_prefix("func ").trim_suffix("("))
	for alt in ["func _fernsehen_an(", "func tv_rechteck(", "func _guide2_hinweis(", "func _aus_dem_spiel("]:
		check(not an.contains(alt), "kein toter Weg mehr: %s" % alt.trim_prefix("func ").trim_suffix("("))
	check(not _src("res://src/room/zimmer_basis.gd").contains("\"guide\", \"Aufstehen\"") and not _src("res://src/room/zimmer.gd").contains("_fernseher_spielen"),
			"keine verwaisten Hinweise")
	check(not fe.contains("_cover_why.has(\"tv\")") and not _src("res://helper/uzai-helper.ps1").contains("'tv-bild'"),
			"kein Vorn-Halten „tv“, kein Live-Fenster über dem Fernseher mehr")

	_live_bild()
	_fokus_und_ton()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

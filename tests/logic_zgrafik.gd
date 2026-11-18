extends Node
## Licht im Zimmer (src/room/licht.gd): Licht-Konzept der Tageszeiten, Form der Lampen für die
## Hüllen-Shader, Tonwerte der Stimmungen, Grafik-Stufen. Die einstellbaren Licht-Daten selbst
## (raum.licht, it.l) prüft gestalt.gd (tests/logic_zanpassung.gd).
## Aufruf: godot --headless --path . res://tests/logic_zgrafik.tscn

const Licht := preload("res://src/room/licht.gd")
const G := preload("res://src/room/gestalt.gd")
const Welt := preload("res://src/room/zimmer_welt.gd")
const Leistung := preload("res://src/room/leistung.gd")
const Lichtbacken := preload("res://src/room/lichtbacken.gd")
const Raum := preload("res://src/room/raum.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Tageszeiten")
	for z in ["morgen", "tag", "abend", "nacht"]:
		var t: Dictionary = Licht.zeit(z)
		var fehlt := ["oben", "horizont", "huegel", "sonne", "sonne_e", "hoch", "seite", "himmel", "himmel_e", "decke", "wand", "boden",
			"amb", "bounce", "lampen", "strahl", "nacht", "belichtung", "tief", "spitze"].filter(func(k: String) -> bool: return not t.has(k))
		check(fehlt.is_empty(), "%s: alle Werte da %s" % [z, str(fehlt)])
		check(float(t.amb) > 0.0 and float(t.amb) < 0.6, "%s: Umgebung bleibt gedämpft (Kontrast)" % z)
	check(float(Licht.zeit("nacht").sonne_e) < float(Licht.zeit("tag").sonne_e) * 0.3, "Nacht: Mond deutlich schwächer als die Sonne")
	check(float(Licht.zeit("tag").lampen) < float(Licht.zeit("abend").lampen), "Lampen wirken abends stärker als am Tag")
	check(Licht.zeit("quatsch") == Licht.zeit("tag"), "Unbekannte Tageszeit: Tag")

	print("Lampen und Stimmungen")
	check(Licht.art("stehlampe") == 1 and Licht.art("deckenlampe") == 2 and Licht.art("lichterkette") == 0 and Licht.art("led_leiste") == 0,
			"Form je Lampe (Schirm, Decke, Punkt)")
	for s in G.STIMMUNGEN:
		check(Licht.STIMMUNG_WERTE.has(s[0]), "Stimmung %s hat Tonwerte" % s[0])
	var raum := { "licht": G.pruefe_licht({ "z": "nacht", "st": "kino" }) }
	check(str(raum.licht.get("st", "")) == "kino" and Licht.stimmung(raum) == Licht.STIMMUNG_WERTE.kino, "Stimmung aus raum.licht.st")
	check(Licht.stimmung({ "licht": { "st": "s_eigen1" } }) == Licht.STIMMUNG_WERTE[""], "eigene Stimmung: neutrale Tonwerte")
	check(Licht.stimmung({ "licht": "abend" }) == Licht.STIMMUNG_WERTE[""] and Licht.stimmung({}) == Licht.STIMMUNG_WERTE[""], "Fassung 1 und leeres Licht")
	check(float(Licht.STIMMUNG_WERTE.kino.tv) > float(Licht.STIMMUNG_WERTE[""].tv), "Kino: Fernseher leuchtet stärker in den Raum")
	var l := Welt.licht_von({ "licht": { "k": 2700, "h": 50 } }, { "t": "stehlampe", "l": { "h": 200, "w": 150 } })
	check(is_equal_approx(float(l[1]), 1.0) and is_equal_approx(float(l[2]), 1.5), "Helligkeit Lampe × Raum, Reichweite der Lampe")

	print("Grafik-Stufen")
	check(Licht.stufe_jetzt("hoch", true) == "hoch" and Licht.stufe_jetzt("auto", true) == "leicht", "feste Wahl gilt, sonst leichter Modus → Leicht")
	check(Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 3060") == "hoch" and Licht.stufe_jetzt("auto", false, "Intel(R) UHD Graphics 620") == "mittel"
			and Licht.stufe_jetzt("auto", false, "AMD Radeon(TM) Graphics") == "mittel", "auto: eigene Grafikkarte Hoch, im Prozessor Mittel")
	check(Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 5080", "forward") == "ultra" and Licht.stufe_jetzt("auto", false, "AMD Radeon RX 7900 XTX", "forward") == "ultra"
			and Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 4060", "forward") == "hoch" and Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 5080", "compat") == "hoch",
			"auto beim ersten Mal: starke Karte Ultra (Kompatibilität Hoch), andere eigene Hoch")
	check(int(Licht.STUFE_WERTE.ultra.lampen_schatten) == 2 and int(Licht.STUFE_WERTE.hoch.lampen_schatten) == 1,
			"Lampenschatten: Ultra die zwei, Hoch die eine kräftigste Lampe")
	check(Licht.stufe_jetzt("quatsch", false, "") == "mittel", "Unbekanntes: Mittel")
	check(int(Licht.STUFE_WERTE.leicht.schatten) == 0 and int(Licht.STUFE_WERTE.leicht.ao) == 0 and not bool(Licht.STUFE_WERTE.leicht.strahl),
			"Leicht: ohne echte Schatten, Nachbearbeitung und Lichtstrahl")
	check(int(Licht.STUFE_WERTE.hoch.schatten) > int(Licht.STUFE_WERTE.mittel.schatten) and int(Licht.STUFE_WERTE.hoch.msaa) >= int(Licht.STUFE_WERTE.mittel.msaa),
			"Hoch: feinere Schatten, mindestens so viel Kantenglättung (dazu SMAA)")
	for s in Licht.STUFEN:
		check(s[0] == "auto" or Licht.STUFE_WERTE.has(s[0]), "Stufe %s hat Werte" % s[0])
	var gel := { "karte": "NVIDIA GeForce RTX 5080", "stufe": "ultra" }
	check(Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 5080", "forward", gel) == "ultra"
			and Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 3060", "forward", gel) == "hoch"
			and Licht.stufe_jetzt("auto", false, "NVIDIA GeForce RTX 5080", "compat", gel) == "hoch"
			and Licht.stufe_jetzt("auto", true, "NVIDIA GeForce RTX 5080", "forward", gel) == "leicht"
			and Licht.stufe_jetzt("mittel", false, "NVIDIA GeForce RTX 5080", "forward", gel) == "mittel",
			"auto: Gemessenes gilt nur für dieselbe Karte, nicht im leichten Modus und nicht gegen eine feste Wahl")
	check(Licht.stufe_daneben("hoch", 1) == "ultra" and Licht.stufe_daneben("ultra", 1) == "ultra" and Licht.stufe_daneben("mittel", -1) == "leicht"
			and Licht.stufe_daneben("leicht", -1) == "leicht", "eine Stufe rauf oder runter, am Rand bleibt sie")

	print("Auflösung und Kantenglättung")
	var u := Licht.werte("ultra", "forward")
	check(int(u.msaa) == 4 and not bool(u.taa) and int(Licht.werte("hoch", "forward").msaa) == 2, "Ultra MSAA 4×, Hoch 2×, ohne TAA")
	for st in ["ultra", "hoch", "mittel", "leicht"]:
		var ws := Licht.werte(st, "forward")
		check(not bool(ws.gi) and not bool(ws.ssil) and not bool(ws.ssr) and not bool(ws.nebel),
				"%s: keine globale Beleuchtung, kein SSIL, SSR oder Nebel je Bild (Licht der Hülle gebacken)" % st)
	check(int(Licht.werte("mittel", "forward").msaa) == 2 and int(Licht.werte("ultra", "compat").msaa) == 4, "Mittel und Kompatibilität behalten MSAA")
	var a4 := Licht.aufloesung(u, 3840, 2160)
	check(a4.modus == "fsr" and str(a4.aa) == "smaa" and int(a4.msaa) == 4 and is_equal_approx(float(a4.start), 1.0) and is_equal_approx(float(a4.min), 0.77),
			"4K Ultra: nativ mit MSAA 4× und SMAA, Sicherheitsnetz bis 77 %% – %s" % str(a4))
	var h4 := Licht.aufloesung(Licht.werte("hoch", "forward"), 3840, 2160)
	check(h4.modus == "fsr" and is_equal_approx(float(h4.min), 0.67), "4K Hoch: notfalls bis 67 %%")
	var a1 := Licht.aufloesung(u, 1920, 1080)
	check(a1.modus == "fsr" and is_equal_approx(float(a1.start), 1.0) and is_equal_approx(float(a1.min), 0.87), "1080p Ultra: nativ, notfalls bis 87 %%")
	var m4 := Licht.aufloesung(Licht.werte("mittel", "forward"), 3840, 2160)
	check(m4.modus == "fsr" and absf(float(m4.max) - 2560.0 / 3840.0) < 0.01, "Mittel 4K: FSR 1, höchstens 2560 breit")
	var c4 := Licht.aufloesung(Licht.werte("leicht", "compat"), 3840, 2160)
	check(c4.modus == "bilinear" and is_equal_approx(float(c4.min), float(c4.max)), "Kompatibilität: fest, ohne Anpassen")

	print("Gebackenes Licht")
	var fl := Lichtbacken.flaechen(6.0, 5.0, 2.7)
	check(fl.size() == 6, "sechs Flächen")
	for n: String in fl:
		var f: Array = fl[n]
		check((f[1] as Vector3).cross(f[2] as Vector3).is_equal_approx(f[3]), "%s: rechts × oben = Normale (Kamera schaut auf die Fläche)" % n)
	var ab := Lichtbacken.abbildung(fl.boden, 0.02)
	check(ab.px == Vector2i(302, 252), "Boden 6 × 5 m mit 2 cm: 302 × 252 Punkte (ein Punkt Rand) – %s" % str(ab.px))
	var uv := func(a: Dictionary, p: Vector3) -> Vector2:
		var q := Vector4(p.x, p.y, p.z, 1.0)
		return Vector2(q.dot(a.u), q.dot(a.v))
	check((uv.call(ab, Vector3(3.0, 0.0, 2.5)) as Vector2).is_equal_approx(Vector2(0.5, 0.5)), "Mitte des Bodens → Mitte der Karte")
	check((uv.call(ab, Vector3(0.0, 0.0, 0.0)) as Vector2).is_equal_approx(Vector2(1.0 / 302.0, 1.0 / 252.0)), "Ecke x = 0, z = 0 → oben links (ein Punkt Rand)")
	var ah := Lichtbacken.abbildung(fl.hinten, 0.02)
	check((uv.call(ah, Vector3(0.0, 2.7, 0.0)) as Vector2).x < 0.01 and (uv.call(ah, Vector3(0.0, 2.7, 0.0)) as Vector2).y < 0.02, "Rückwand: oben links ist oben links")
	var al := Lichtbacken.abbildung(fl.links, 0.02)
	check((uv.call(al, Vector3(0.0, 0.0, 5.0)) as Vector2).x < 0.01 and (uv.call(al, Vector3(0.0, 0.0, 5.0)) as Vector2).y > 0.98,
			"Fensterwand von innen: z = d links, unten unten")
	# Gespeicherte Schatten: Die Engine zeichnet die Schatten eines Lichts jedes Bild neu, sobald ein
	# Schattenwerfer darin einen Shader mit TIME im Vertex-Teil hat – nur der wehende Vorhang darf das.
	var kern := FileAccess.get_file_as_string("res://src/room/shaders/stoff_kern.gdshaderinc")
	var wa := kern.find("#ifdef WEHEN")
	var we := kern.find("#endif", wa)
	check(wa > 0 and we > wa and kern.find("TIME", wa) < we and not (kern.substr(0, wa) + kern.substr(we)).contains("TIME"),
			"Stoff: TIME nur im Wehen-Teil")
	check(not FileAccess.get_file_as_string("res://src/room/shaders/stoff.gdshader").contains("WEHEN")
			and FileAccess.get_file_as_string("res://src/room/shaders/stoff_wehen.gdshader").contains("#define WEHEN"),
			"stiller Stoff ohne Wehen, Vorhang-Shader mit")

	print("Bildrate und dynamische Auflösung")
	check(Leistung.zielrate("bildschirm", 120.0, 0) == 120 and Leistung.zielrate("bildschirm", 240.0, 120) == 120
			and Leistung.zielrate("bildschirm", 60.0, 0) == 60 and Leistung.zielrate("bildschirm", 0.0, 0) == 60,
			"Bildrate wie im Menü: 120 Hz → 120, über 144 Hz die Menü-Rate, unbekannt 60")
	check(Leistung.zielrate("60", 120.0, 0) == 60 and Leistung.zielrate("60", 144.0, 0) == 72 and Leistung.zielrate("30", 120.0, 0) == 30
			and Leistung.zielrate("60", 50.0, 0) == 50 and Leistung.zielrate("60", 120.0, 40) == 40,
			"Wahl 60/30: ganzzahliger Teil der Bildschirmrate, nie mehr als das Menü")
	check(is_equal_approx(Leistung.startskala(a4, { "karte": "K", "stufe": "ultra", "hoehe": 2160, "skala": 0.87 }, "K", "ultra", 2160), 0.87)
			and is_equal_approx(Leistung.startskala(a4, { "karte": "K", "stufe": "ultra", "hoehe": 2160, "skala": 0.87 }, "L", "ultra", 2160), 1.0)
			and is_equal_approx(Leistung.startskala(a4, { "karte": "K", "stufe": "hoch", "hoehe": 2160, "skala": 0.87 }, "K", "ultra", 2160), 1.0)
			and is_equal_approx(Leistung.startskala(a4, { "karte": "K", "stufe": "ultra", "hoehe": 2160, "skala": 0.3 }, "K", "ultra", 2160), 0.77),
			"Startskala: was zuletzt auf derselben Karte, Stufe und Höhe galt, innerhalb der Grenzen")
	check(Leistung.bewegungsrate(120.0, 60) == 60 and Leistung.bewegungsrate(144.0, 60) == 72 and Leistung.bewegungsrate(60.0, 60) == 60
			and Leistung.bewegungsrate(240.0, 60) == 60 and Leistung.bewegungsrate(0.0, 60) == 60 and Leistung.bewegungsrate(120.0, 120) == 120
			and Leistung.bewegungsrate(144.0, 60, true) == 48 and Leistung.bewegungsrate(165.0, 120, true) == 83,
			"Bewegung: ganzzahliger Teil der Bildschirmrate nahe 60 (120 Hz → 60, 144 → 72); als Grenze nie darüber")
	check(is_equal_approx(Leistung.skala_schritt(0.67, 2.5, 0.0, 0.5, 0.77), 0.59), "lange über dem Ziel: eine Stufe kleiner")
	check(is_equal_approx(Leistung.skala_schritt(0.67, 0.0, 6.0, 0.5, 0.77), 0.77), "lange deutlich darunter: eine Stufe größer")
	check(is_equal_approx(Leistung.skala_schritt(0.67, 1.0, 3.0, 0.5, 0.77), 0.67), "kurz darüber oder darunter: bleibt (kein Pumpen)")
	check(is_equal_approx(Leistung.skala_schritt(0.5, 9.0, 0.0, 0.5, 0.77), 0.5) and is_equal_approx(Leistung.skala_schritt(0.77, 0.0, 9.0, 0.5, 0.77), 0.77),
			"an den Grenzen bleibt sie")
	check(is_equal_approx(Leistung.skala_schritt(0.6667, 9.0, 0.0, 0.6, 0.6667), 0.6), "FSR 1 (4K Mittel): von 67 %% eine Stufe zur kleinsten")
	check(Leistung.ziel_ms(60, true) < Leistung.ziel_ms(60, false) and is_equal_approx(Leistung.ziel_ms(60, false), 1000.0 / 60.0 * Leistung.ANTEIL),
			"neben dem laufenden Spiel zielt das Zimmer auf weniger Zeit der Grafikkarte")
	check(Leistung.spiel_kappe(165.0) == 82 and Leistung.spiel_kappe(144.0) == 72 and Leistung.spiel_kappe(120.0) == 60
			and Leistung.spiel_kappe(60.0) == 60 and Leistung.spiel_kappe(240.0) == 60 and Leistung.spiel_kappe(100.0) == 100
			and Leistung.spiel_kappe(0.0) == 60 and Leistung.spiel_kappe(119.88) == 60 and Leistung.spiel_kappe(59.94) == 60
			and Leistung.spiel_kappe(50.0) == 50,
			"neben dem Spiel: kleinster ganzer Teil der Bildschirmrate mit mindestens 60 (165 → 82, 144 → 72, 120 → 60), unbekannt 60")
	for hz in [60.0, 75.0, 90.0, 120.0, 144.0, 165.0, 170.0, 175.0, 180.0, 200.0, 240.0, 360.0]:
		var k := Leistung.spiel_kappe(hz)
		var n := roundf(hz / float(k))
		check(k >= 59 and absf(float(k) - hz / n) < 1.0, "%.0f Hz: Kappe %d – nie unter 60, ganzer Teil (÷ %d)" % [hz, k, int(n)])
	check(float(Leistung.SCHLANK.max) <= 0.67 and float(Leistung.SCHLANK.min) >= 0.5 and str(Leistung.SCHLANK.modus) == "fsr"
			and str(Leistung.SCHLANK.aa) == "fxaa" and int(Leistung.SCHLANK.msaa) == 0,
			"schlanker Weg: FSR 1 bei 50–67 %, FXAA, ohne MSAA – in jeder Stufe gleich")
	check(Leistung.ziel_ms(82, true) <= 1000.0 / 82.0 * 0.35, "neben dem Spiel höchstens rund ein Drittel der Bildzeit für die Grafikkarte")
	check(Leistung.ablauf_text(31.0, 2.1, "Spielbild 1.20 ms") == "31.0 ms (Skripte 2.1 ms, teuerster Abschnitt Spielbild 1.20 ms)"
			and Leistung.ablauf_text(5.0, 1.0, "") == "5.0 ms (Skripte 1.0 ms)", "längster Ablauf mit dem, was ihn kostete")

	print("Pipelines vorab")
	var msaa_vorher: Variant = ProjectSettings.get_setting(Leistung.MSAA_EINST, 0)
	var atlas_vorher: Variant = ProjectSettings.get_setting(Leistung.ATLAS16_EINST, true)
	Leistung.pipelines_erwarten(Viewport.MSAA_4X)
	check(int(ProjectSettings.get_setting(Leistung.MSAA_EINST)) == Viewport.MSAA_4X and ProjectSettings.get_setting(Leistung.ATLAS16_EINST) == false,
			"im Zimmer erwartet die Engine dessen MSAA und 32-Bit-Schatten (übersetzt vorab im Hintergrund)")
	Leistung.pipelines_erwarten(Viewport.MSAA_DISABLED)
	check(int(ProjectSettings.get_setting(Leistung.MSAA_EINST)) == Viewport.MSAA_DISABLED, "schlanker Weg: ohne MSAA")
	Leistung.pipelines_zurueck()
	check(ProjectSettings.get_setting(Leistung.MSAA_EINST, 0) == msaa_vorher and ProjectSettings.get_setting(Leistung.ATLAS16_EINST, true) == atlas_vorher,
			"Zimmer zu: wieder wie im Projekt")
	var zb := FileAccess.get_file_as_string("res://src/room/zimmer_basis.gd")
	var plan := zb.substr(zb.find("func _pipelines_planen"), 1400)
	check(plan.contains("Lichtbacken.QUALITAET") and plan.contains("Viewport.MSAA_DISABLED") and plan.contains("frame_post_draw.connect(_pipelines_weiter)"),
			"vorab je ein Bild: MSAA der Ansicht, der Backansichten und des schlanken Wegs")
	var lb := FileAccess.get_file_as_string("res://src/room/lichtbacken.gd")
	var rs_aufrufe := lb.count("soft_shadow_filter_set_quality(")
	check(rs_aufrufe == 4 and lb.substr(lb.find("static func qualitaet_setzen"), 200).contains("if q == _qualitaet_jetzt:"),
			"Filterstufe der Schatten nur bei einem Wechsel (jeder Aufruf verwirft alle Pipelines) – nicht mehr je Backen")
	check(zb.substr(zb.find("func _forward_global"), 200).contains("Lichtbacken.qualitaet_setzen(") and zb.count("soft_shadow_filter_set_quality(") == 0,
			"das Zimmer setzt die Filterstufe nur über Lichtbacken.qualitaet_setzen")

	print("Ausgeblendete Flächen nicht backen (sonst schwarz)")
	var huelle := Raum.new()
	add_child(huelle)
	var r := Daten.standard_raum()
	huelle.bauen(r, Licht.werte("mittel"))
	huelle.schnitt(Vector3(3.0, 9.0, -4.0), true)
	check(huelle.ausgeblendet("hinten") and huelle.ausgeblendet("decke") and not huelle.ausgeblendet("vorn") and not huelle.ausgeblendet("boden"),
			"von oben hinter der hinteren Wand: hintere Wand und Decke ausgeblendet, vordere und Boden nicht")
	huelle.schnitt(Vector3(3.0, 1.6, 2.0), false)
	check(not huelle.ausgeblendet("hinten") and not huelle.ausgeblendet("decke"), "Ich-Ansicht: alles wieder da")
	huelle.queue_free()
	var be := lb.substr(lb.find("func _beginnen"), 1600)
	check(be.contains("_versteckt(name)") and be.contains("_ausgelassen.append(name)") and lb.contains("if not _versteckt(name):"),
			"Backen lässt ausgeblendete Flächen aus und backt sie nach, sobald sie wieder zu sehen sind")
	check(lb.substr(lb.find("func _beenden"), 3000).contains("_zeigt[name] = int(_ziele[name])"), "je Fläche gilt ihre eigene Karte")

	print("Zwei Backvorgänge kurz nacheinander: jede Blende läuft zu Ende")
	var bk := Lichtbacken.new()
	bk.huelle = Node3D.new()
	add_child(bk)
	bk.gebacken = 5
	for name: String in Lichtbacken.FLAECHEN:
		bk._mats[name] = ShaderMaterial.new()
		bk._ziele[name] = 0
	bk._zustand = "warten"
	bk._zustand = "backen"
	bk._beenden()
	await get_tree().create_timer(0.2).timeout
	var halb := float((bk._mats.boden as ShaderMaterial).get_shader_parameter("lm_an"))
	# Das zweite Backen endet, bevor die erste Blende durch ist; die Decke ist dabei ausgeblendet.
	for name: String in Lichtbacken.FLAECHEN:
		bk._ziele[name] = 1
	bk._ziele.erase("decke")
	bk._zustand = "warten"
	bk._zustand = "backen"
	bk._beenden()
	await get_tree().create_timer(Lichtbacken.BLENDE_S + 0.25).timeout
	var offen: Array = []
	for name: String in Lichtbacken.FLAECHEN:
		var bm: ShaderMaterial = bk._mats[name]
		var mix_soll := 0.0 if name == "decke" else 1.0
		if not is_equal_approx(float(bm.get_shader_parameter("lm_an")), 1.0) or not is_equal_approx(float(bm.get_shader_parameter("lm_mix")), mix_soll):
			offen.append(name)
	check(halb > 0.05 and halb < 0.95 and offen.is_empty() and not bk._kopien.visible,
			"lm_an steht danach überall auf 1 (blieb bei %.2f stehen: Hülle zu dunkel), nicht fertig: %s" % [halb, str(offen)])
	bk.huelle.free()
	bk.queue_free()

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

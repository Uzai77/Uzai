extends Node
## Klangdesign, Menümusik, Startanimation je System und Symbolsatz (Roadmap 99, 17, 98):
## Panorama und Kontext, Musik aus bei Spiel und Video, Theme-Felder streng geprüft,
## Startanimation abschaltbar und nie im leichten Modus, einheitliche Symbole.
## Klangsatz „Tick“ (Plan „Gefühl“ 3): Regeln (ein Druck ein Klang, Rate, Ruhe, Abend, Richtung),
## Staffelung und Längen der erzeugten Dateien, Klangsatz „Glas“, die Sätze „Glas kurz“, „Filz“ und
## „Luft“ (tools/synth_klang2.py), „Perle“ (tools/synth_klang3.py, Fassungen), „Samt“, „Kiesel“, „Pad“, „Haptik“
## (tools/synth_klang4.py: weich, leise, dunkel – Messziele), der Standard „Handpan“ (tools/synth_klang5.py: tiefe,
## weiche Handpan mit Nachklang, eigene Höchstlängen), die Klänge der Einrichtung, Haptik.
## Aufruf: godot --headless --path . res://tests/logic_klang.tscn

const Klang := preload("res://src/core/klang.gd")
const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const Leicht := preload("res://src/core/leicht.gd")
const PadsS := preload("res://src/core/pads.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_raum()
	_kontext()
	_musik_logik()
	_intro()
	_symbole()
	_tick_regeln()
	_tick_dateien()
	_klang2_dateien()
	_fassungen_logik()
	_klang3_dateien()
	_klang4_dateien()
	_klang5_dateien()
	_haptik()
	await _sfx()
	await _sfx_tick()
	await _musik_laeuft()
	_satz_umbau()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _raum() -> void:
	print("Raum")
	check(is_equal_approx(Klang.pan_for(0.0, 1920.0, 0.22), -0.22), "ganz links: −Raum")
	check(is_equal_approx(Klang.pan_for(960.0, 1920.0, 0.22), 0.0), "Mitte: mittig")
	check(is_equal_approx(Klang.pan_for(1920.0, 1920.0, 0.22), 0.22), "ganz rechts: +Raum")
	check(is_equal_approx(Klang.pan_for(480.0, 1920.0, 0.4), -0.2), "Viertel links: halber Raum")
	check(is_equal_approx(Klang.pan_for(5000.0, 1920.0, 3.0), Klang.RAUM_MAX), "außerhalb und zu viel Raum: begrenzt")
	check(Klang.pan_for(NAN, 1920.0, 0.2) == 0.0 and Klang.pan_for(10.0, 0.0, 0.2) == 0.0 and Klang.pan_for(10.0, 100.0, NAN) == 0.0, "Unsinn: mittig")
	check(Klang.pan_for(0.0, 1920.0, 0.0) == 0.0, "Raum 0: immer mittig")


func _kontext() -> void:
	print("Kontext")
	var oben := Klang.kontext("move", 0.0, "", false)
	var unten := Klang.kontext("move", 1.0, "", false)
	check(oben.x > 1.0 and unten.x < 1.0 and absf(oben.x - unten.x) <= 0.031, "Bewegen: oben eine Spur höher, unten tiefer (≤ 3 %)")
	check(Klang.kontext("move", -1.0, "", false) == Vector2(1, 1), "ohne Lage: unverändert")
	var ende := Klang.kontext("bump", 0.5, "down", false)
	var anfang := Klang.kontext("bump", 0.5, "up", false)
	check(ende.x < 1.0 and ende.x == Klang.kontext("bump", 0.5, "right", false).x, "Anschlag am Listenende (unten/rechts): tiefer")
	check(anfang.x > 1.0 and anfang.y < 1.0, "Anschlag am Anfang: heller und leiser")
	check(is_equal_approx(Klang.kontext("select", 0.5, "", true).y, Klang.EBENE_LAUT), "in einer Ebene: etwas leiser")
	check(Klang.kontext("guide", 0.9, "down", false) == Vector2(1, 1), "andere Klänge: unverändert")


func _musik_logik() -> void:
	print("Menümusik: Entscheidung")
	var ruhig := { "an": true, "leicht": false, "spiel": false, "startet": false, "video": false, "musik": false, "vorn": true, "stueck": true }
	check(Klang.musik_soll(ruhig), "alles ruhig und an: spielt")
	for k in ["spiel", "startet", "video", "musik", "leicht"]:
		var z := ruhig.duplicate()
		z[k] = true
		check(not Klang.musik_soll(z), "%s: aus" % k)
	for k in ["an", "vorn", "stueck"]:
		var z2 := ruhig.duplicate()
		z2[k] = false
		check(not Klang.musik_soll(z2), "nicht %s: aus" % k)
	check(not Klang.musik_soll({}), "ohne Angaben: aus")
	var mit_klang := ruhig.duplicate()
	mit_klang["spielklang"] = true
	check(not Klang.musik_soll(mit_klang), "Klang einer Spielseite läuft: Menümusik schweigt")
	var seite := { "an": true, "laut": true, "spiel": false, "startet": false, "video": false, "musik": false, "vorn": true }
	check(Klang.spielklang_soll(seite), "Spielklang: Seite offen, alles ruhig, eingeschaltet: läuft")
	for k in ["spiel", "startet", "video", "musik"]:
		var zs := seite.duplicate()
		zs[k] = true
		check(not Klang.spielklang_soll(zs), "Spielklang bei %s: aus" % k)
	for k in ["an", "laut", "vorn"]:
		var zs2 := seite.duplicate()
		zs2[k] = false
		check(not Klang.spielklang_soll(zs2), "Spielklang ohne %s: aus" % k)
	check(not Klang.spielklang_soll({}), "Spielklang ohne Angaben (kein Schlüssel, aus): aus")
	check(float(Config.get_value("theme.music", 1.0)) == 0.0, "Standard: Menümusik aus (0 %)")
	check(Klang.stueck("theme") == Klang.MUSIK_STD and Klang.stueck("retro") == "retro", "Stück: Standard oder eigene Wahl")
	check(Klang.stueck("unsinn") == Klang.MUSIK_STD and Klang.stueck("") == Klang.MUSIK_STD and Klang.MUSIK.has(Klang.MUSIK_STD), "unbekannte Wahl: das Standardstück")
	check(Klang.musik_db(0.0) <= -79.0 and is_equal_approx(Klang.musik_db(1.0), Klang.MUSIK_PEGEL_DB), "Regler 0: still, 100 %: Grundpegel")
	check(Klang.musik_db(0.5) < Klang.musik_db(1.0), "leiser mit dem Regler")
	for id in Klang.MUSIK.keys():
		check(ResourceLoader.exists("%s/%s.ogg" % [Klang.MUSIK_DIR, id]), "Stück „%s“ liegt bei" % id)


func _intro() -> void:
	print("Startanimation je System")
	var nes := { "source": "rom", "system": "nes" }
	check(SystemIntro.soll(nes, "theme", false, false), "Emulator-Spiel, Standard: läuft")
	check(not SystemIntro.soll(nes, "aus", false, false), "abgeschaltet: läuft nicht")
	check(SystemIntro.soll(nes, "3d", false, false), "3D-Szenen: läuft")
	check(not SystemIntro.soll(nes, "theme", true, false), "leichter Modus: nie")
	check(not SystemIntro.soll(nes, "theme", false, true), "Animationen reduzieren: nie")
	check(not SystemIntro.soll({ "source": "steam", "system": "" }, "theme", false, false), "Steam-Spiel: keine")
	check(SystemIntro.soll({ "source": "rom", "system": "pico8" }, "theme", false, false), "unbekanntes System: neutrale Sequenz")
	check(str(Config.get_value("theme.system_intro", "")) == "theme", "Standard: an")
	var fam := {}
	for s in Config.systems():
		var f := SystemIntro.familie(str(s.id))
		check(f != "", "System %s → %s" % [str(s.id), f])
		fam[f] = true
	check(fam.size() == 6, "alle sechs Familien kommen vor")
	check(SystemIntro.familie("snes") == "16bit" and SystemIntro.familie("gba") == "handheld" and SystemIntro.familie("ps2") == "disc"
			and SystemIntro.familie("arcade") == "arcade" and SystemIntro.familie("n64") == "3d" and SystemIntro.familie("nes") == "8bit", "Zuordnung stimmt")
	check(SystemIntro.DAUER >= 2.0 and SystemIntro.DAUER <= 3.0, "zwei bis drei Sekunden")
	# Läuft sie, endet sie von selbst und nimmt keine Eingaben.
	var si: Control = SystemIntro.new().setup(nes)
	add_child(si)
	check(si.mouse_filter == Control.MOUSE_FILTER_IGNORE and si.focus_mode == Control.FOCUS_NONE, "fängt keine Eingaben ab")
	si.queue_free()


func _symbole() -> void:
	print("Symbolsatz")
	var leer := []
	var eigen := []
	for name in Icons.P.keys():
		var body := str(Icons.P[name])
		if body.contains("stroke-width") or body.contains("stroke-linecap"):
			eigen.append(name)
		var img := Icons.image(str(name), 48.0)
		if img.get_width() != 48 or img.is_invisible():
			leer.append(name)
	check(eigen.is_empty(), "kein Symbol mit eigener Strichstärke (%s)" % ", ".join(eigen))
	check(leer.is_empty(), "alle %d Symbole zeichnen sich (%s)" % [Icons.P.size(), ", ".join(leer)])
	for n in ["games", "settings", "play", "pause", "steam", "discord", "store_gog", "more"]:
		check(Icons.P.has(n), "Name „%s“ bleibt" % n)
	var t := Icons.tex("play", 40)
	check(t.get_width() >= 80, "mindestens doppelt fein gerastert (%d px für 40)" % t.get_width())
	check(Icons.image("gibtsnicht", 24.0).get_width() == 24, "unbekannter Name: Ersatzsymbol")


func _sfx() -> void:
	print("Klang-Ausgabe")
	check(Sfx._panners.size() == 8, "jeder Spieler mit eigenem Panorama")
	check(AudioServer.get_bus_index("UI_P0") >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index("UI_P0")) == "UI",
			"Leitungen münden in „UI“ (Begrenzer bleibt)")
	Config.set_value("theme.sounds", true)
	var vw := get_viewport().get_visible_rect().size.x
	var links := Control.new()
	links.position = Vector2(0, 100)
	links.size = Vector2(60, 40)
	add_child(links)
	var rechts := Control.new()
	rechts.position = Vector2(vw - 60.0, 100)
	rechts.size = Vector2(60, 40)
	add_child(rechts)
	await get_tree().process_frame
	Sfx.play("select", 1.0, links)
	var p1: AudioStreamPlayer = Sfx.last_player
	var pan1: float = Sfx._panners[Sfx._players.find(p1)].pan
	await get_tree().create_timer(0.1).timeout
	Sfx.play("back", 1.0, rechts)
	var p2: AudioStreamPlayer = Sfx.last_player
	var pan2: float = Sfx._panners[Sfx._players.find(p2)].pan
	check(pan1 < -0.1 and pan2 > 0.1 and absf(pan1) <= Klang.RAUM_MAX, "links klingt links (%.2f), rechts rechts (%.2f)" % [pan1, pan2])
	await get_tree().create_timer(0.1).timeout
	Config.set_value("theme.sound_space", false)
	Sfx.play("select", 1.0, links)
	check(Sfx._panners[Sfx._players.find(Sfx.last_player)].pan == 0.0, "„Räumlicher Klang“ aus: mittig")
	Config.set_value("theme.sound_space", true)
	await get_tree().create_timer(0.35).timeout
	Sfx.play("bump", 1.0, links, "down")
	var pb := Sfx.last_player.pitch_scale
	await get_tree().create_timer(0.35).timeout
	Sfx.play("bump", 1.0, links, "up")
	check(pb < 1.0 and Sfx.last_player.pitch_scale > pb, "Anschlag unten tiefer als oben (%.2f / %.2f)" % [pb, Sfx.last_player.pitch_scale])
	links.queue_free()
	rechts.queue_free()


func _tick_regeln() -> void:
	print("Tick: Regeln")
	# Ein Druck, ein Klang.
	check(Klang.gleicher_druck(10, 5) and Klang.gleicher_druck(200, 1) and not Klang.gleicher_druck(100, 6), "selber Druck: ≤ 60 ms oder ≤ 2 Bilder")
	var d := Klang.ein_druck([[3, "select"]], "open", 4)
	check(bool(d.spielen) and d.ersetzen == [0], "„open“ ersetzt „select“ (A auf eine Karte klingt einmal)")
	d = Klang.ein_druck([[0, "move"]], "tab", 2)
	check(bool(d.spielen) and d.ersetzen == [0], "„tab“ ersetzt „move“")
	check(not bool(Klang.ein_druck([[4, "open"]], "move", 0).spielen), "„move“ nach „open“ bleibt still")
	check(not bool(Klang.ein_druck([[3, "select"]], "select", 3).spielen), "gleicher Klang doppelt sich nicht")
	check(bool(Klang.ein_druck([[3, "select"]], "back", 3).spielen), "gleich wichtig: der spätere (genauere) gewinnt")
	check(bool(Klang.ein_druck([], "move", 0).spielen) and (Klang.ein_druck([], "move", 0).ersetzen as Array).is_empty(), "allein: spielt")
	# Rate und Halten.
	check(not bool(Klang.bewegen(69, 0).ok) and bool(Klang.bewegen(70, 0).ok), "Bewegen höchstens alle 70 ms")
	var r := Klang.bewegen(400, 3)
	check(int(r.reihe) == 0 and float(r.db) == 0.0, "langsam: volle Stärke")
	var reihe := 0
	var dbs: Array = []
	for i in 8:
		var b := Klang.bewegen(120, reihe)
		reihe = int(b.reihe)
		dbs.append(float(b.db))
	check(dbs[0] < 0.0 and dbs[0] > -8.0 and is_equal_approx(dbs[7], Klang.HALTEN_DB) and dbs.max() <= 0.0 and dbs.min() >= -8.0,
			"Halten: jeder Schritt hörbar, bis −8 dB leiser (%.1f … %.1f)" % [dbs[0], dbs[7]])
	var z1 := Klang.zufall(1.0, -1.0)
	var z2 := Klang.zufall(-3.0, 3.0)
	check(is_equal_approx(z1.x, 1.015) and is_equal_approx(z1.y, -0.5) and is_equal_approx(z2.x, 0.985) and is_equal_approx(z2.y, 0.5),
			"nie zweimal gleich: Tonhöhe ±1,5 %, Lautstärke ±0,5 dB")
	# Ruhe und Abend.
	check(Klang.ruhe_db(5000, -1) == 0.0, "kurz ruhig: volle Stärke")
	check(Klang.ruhe_db(Klang.RUHE_MS + 1, -1) == -6.0, "über 10 min ruhig: 6 dB leiser")
	check(Klang.ruhe_db(0, 0) == -6.0 and is_equal_approx(Klang.ruhe_db(10, 1500), -3.0) and Klang.ruhe_db(10, 3000) == 0.0,
			"nach der Pause: in 3 s wieder voll")
	check(Klang.abend_db(22, "select") == -4.0 and Klang.abend_db(3, "notify") == -4.0 and Klang.abend_db(6, "move") == -4.0, "22–7 Uhr: 4 dB leiser")
	check(Klang.abend_db(7, "select") == 0.0 and Klang.abend_db(21, "select") == 0.0, "tagsüber: unverändert")
	check(Klang.abend_db(23, "error") == 0.0, "Fehler bleiben abends laut")
	check(is_equal_approx(Klang.zusatz_db("notify", 12, 0, -1, true), 3.0) and Klang.zusatz_db("select", 12, 0, -1, true) == 0.0, "Mitteilung über dem Spiel: +3 dB")
	check(is_equal_approx(Klang.zusatz_db("select", 23, Klang.RUHE_MS + 5, -1, false), -10.0), "Abend und Ruhe zählen zusammen")
	# Eingaben, Richtung.
	var knopf := InputEventJoypadButton.new()
	knopf.pressed = true
	var los := InputEventJoypadButton.new()
	var stick := InputEventJoypadMotion.new()
	stick.axis_value = 0.2
	check(Klang.ist_eingabe(knopf) and not Klang.ist_eingabe(los) and not Klang.ist_eingabe(stick), "Eingabe: Drücke ja, Loslassen und Stick-Rauschen nein")
	check(is_equal_approx(float(Klang.tab_pan("left")), -0.3) and is_equal_approx(float(Klang.tab_pan("right")), 0.3) and Klang.tab_pan("") == null,
			"Bereichswechsel: aus der Richtung (±0,3)")


## Die erzeugten Dateien (tools/synth_tick.py) gegen die Palette: Länge, Klang ≤ Bewegung + 60 ms,
## Staffelung der Spitzen zu „select“; dazu der Klangsatz „Glas“.
func _tick_dateien() -> void:
	print("Tick: Dateien")
	var spitze := {}
	var ms := {}
	var formate_ok := true
	var tick_namen: Array = Klang.PALETTE.keys().filter(func(k): return not (k in Klang.EINRICHTUNG))
	for name in tick_namen:
		var w := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/sounds/%s.wav" % name))
		if w == null:
			check(false, "%s.wav lesbar" % name)
			continue
		formate_ok = formate_ok and w.stereo and w.format == AudioStreamWAV.FORMAT_16_BITS and w.mix_rate == 44100
		var n := w.data.size() / 4
		var p := 0
		for i in n * 2:
			p = maxi(p, absi(w.data.decode_s16(i * 2)))
		spitze[name] = linear_to_db(p / 32767.0)
		ms[name] = n * 1000.0 / w.mix_rate
	check(formate_ok and spitze.size() == tick_namen.size(), "%d Klänge, 44,1 kHz, Stereo, 16 Bit" % spitze.size())
	var lang: Array = []
	var nachklang: Array = []
	var pegel: Array = []
	for name in ms.keys():
		var soll: Array = Klang.PALETTE[name]
		if absf(float(ms[name]) - float(soll[0])) > 2.0:
			lang.append("%s %.0f/%d" % [name, ms[name], soll[0]])
		if float(ms[name]) > float(soll[2]) + Klang.NACHKLANG_MS:
			nachklang.append(name)
		if absf(float(spitze[name]) - float(spitze.get("select", 0.0)) - float(soll[1])) > 1.5:
			pegel.append("%s %+.1f/%+.1f" % [name, float(spitze[name]) - float(spitze.get("select", 0.0)), soll[1]])
	check(lang.is_empty(), "Längen wie in der Palette %s" % ", ".join(lang))
	check(nachklang.is_empty(), "kein Klang länger als seine Bewegung + 60 ms %s" % ", ".join(nachklang))
	check(pegel.is_empty(), "Staffelung der Spitzen zu „select“ (±1,5 dB) %s" % ", ".join(pegel))
	check(absf(float(spitze.get("select", 0.0)) + 17.0) < 0.5, "„select“ bei −17 dBFS (mit dem Standardregler etwa −24)")
	check(float(ms.get("guide", 9999.0)) <= 200.0 and float(ms.get("boot", 9999.0)) <= 1300.0, "Guide %.0f ms (vorher 1,3 s), Start %.0f ms (vorher 4,8 s)" % [ms.get("guide", 0.0), ms.get("boot", 0.0)])
	check(float(spitze.get("power_off", 0.0)) <= float(spitze.get("boot", -99.0)) and float(spitze.get("power_off", 0.0)) < (spitze.values() as Array).max(),
			"Ausschalten ist nicht mehr der lauteste")
	check(float(ms.get("move", 99.0)) < Klang.RATE_MS, "Bewegen (%.0f ms) endet vor dem nächsten (70 ms)" % ms.get("move", 0.0))
	# Palette hier und im Werkzeug gleich (Länge, Pegel, Bewegung).
	var src := FileAccess.get_file_as_string("res://tools/synth_tick.py")
	var re := RegEx.create_from_string('\\("(\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+(\\d+),')
	var gleich := 0
	var anders: Array = []
	for m in re.search_all(src):
		var soll: Array = Klang.PALETTE.get(m.get_string(1), [])
		if soll.size() == 3 and int(m.get_string(2)) == int(soll[0]) and is_equal_approx(float(m.get_string(3)), float(soll[1])) \
				and int(m.get_string(4)) == int(soll[2]):
			gleich += 1
		else:
			anders.append(m.get_string(1))
	check(gleich == tick_namen.size() and anders.is_empty(), "Palette in klang.gd und tools/synth_tick.py gleich %s" % ", ".join(anders))
	var quelle := FileAccess.get_file_as_string("res://assets/sounds/KLANG-QUELLE.txt")
	check(quelle.contains("synth_tick.py") and quelle.contains("glas/boot.wav") and quelle.count(".wav") >= 42, "Herkunft mit SHA-256 je Datei (KLANG-QUELLE.txt)")
	var glas := 0
	for name in tick_namen:
		if ResourceLoader.exists("res://assets/sounds/glas/%s.wav" % name):
			glas += 1
	check(glas == tick_namen.size(), "Klangsatz „Glas“: alle %d alten Klänge da" % glas)


## Die Sätze aus tools/synth_klang2.py: alle Klänge da, Format, kein Klang länger als seine Bewegung
## + 60 ms (Start höchstens 2 s), Staffelung, beginnt und endet bei null (kein Knacken).
func _klang2_dateien() -> void:
	print("Klangsätze Filz & Glas, Glas kurz, Filz, Luft")
	var src := FileAccess.get_file_as_string("res://tools/synth_klang2.py")
	var ids: Array = Klang.SAETZE.map(func(o): return str(o[0]))
	check(ids[0] == "handpan" and Klang.SATZ_STD == "handpan" and ids.has("samt") and ids.has("perle") and ids.has("filzglas") and ids.has("glas")
			and ids.has("tick") and ids.has("glaskurz") and ids.has("filz") and ids.has("luft"),
			"wählbar: %s („Handpan“ zuerst, „Samt“, „Perle“ und „Filz & Glas“ bleiben)" % ", ".join(ids))
	var grund: Array = Sfx.NAMES.filter(func(n): return not (n in Klang.EINRICHTUNG))
	check(src.contains('"filzglas": ("Filz & Glas"') and src.contains("GLAS_ANTEIL = 0.45") and src.contains("GLAS_TAU = 0.75"),
			"„Filz & Glas“: Glas-Schimmer mit knapp der Hälfte der Energie, klingt etwas schneller ab als der Körper")
	check(Klang.satz_ordner("tick") == "res://assets/sounds" and Klang.satz_ordner("filz") == "res://assets/sounds/filz",
			"Ordner je Satz")
	var quelle := FileAccess.get_file_as_string("res://assets/sounds/KLANG-QUELLE.txt")
	# Bewegung je Klang im Werkzeug wie in der Palette.
	var re := RegEx.create_from_string('\\("(\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+(\\d+),')
	var bew_anders: Array = []
	var gefunden := 0
	for m in re.search_all(src):
		gefunden += 1
		if int(m.get_string(4)) != int((Klang.PALETTE.get(m.get_string(1), [0, 0, -1]) as Array)[2]):
			bew_anders.append(m.get_string(1))
	check(gefunden == grund.size() and bew_anders.is_empty(), "Bewegung in tools/synth_klang2.py wie in der Palette %s" % ", ".join(bew_anders))
	for id in ["filzglas", "glaskurz", "filz", "luft"]:
		var da := 0
		var format_ok := true
		var zu_lang: Array = []
		var knack: Array = []
		var spitze := {}
		var in_quelle := 0
		for name in Sfx.NAMES:
			var res := "%s/%s.wav" % [Klang.satz_ordner(id), name]
			if not ResourceLoader.exists(res):
				continue
			da += 1
			if quelle.contains("  %s/%s.wav" % [id, name]):
				in_quelle += 1
			var w := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(res))
			if w == null:
				format_ok = false
				continue
			format_ok = format_ok and w.stereo and w.format == AudioStreamWAV.FORMAT_16_BITS and w.mix_rate == 44100
			var n := w.data.size() / 4
			var ms := n * 1000.0 / w.mix_rate
			var grenze := 2000.0 if name == "boot" else float(Klang.PALETTE[name][2] + Klang.NACHKLANG_MS)
			if ms > grenze:
				zu_lang.append("%s %.0f ms" % [name, ms])
			var p := 0
			for i in n * 2:
				p = maxi(p, absi(w.data.decode_s16(i * 2)))
			spitze[name] = linear_to_db(p / 32767.0)
			var rand := 0
			for i in 4:
				rand = maxi(rand, absi(w.data.decode_s16(i * 2)))
				rand = maxi(rand, absi(w.data.decode_s16((n * 2 - 1 - i) * 2)))
			if rand > 40:
				knack.append(name)
		check(da == grund.size() and format_ok, "„%s“: alle %d Klänge, 44,1 kHz, Stereo, 16 Bit" % [id, da])
		check(zu_lang.is_empty(), "„%s“: kein Klang länger als seine Bewegung + 60 ms, Start ≤ 2 s %s" % [id, ", ".join(zu_lang)])
		check(knack.is_empty(), "„%s“: beginnt und endet bei null %s" % [id, ", ".join(knack)])
		var sel: float = spitze.get("select", 0.0)
		var lautester: float = (spitze.values() as Array).max() if not spitze.is_empty() else 0.0
		check(sel > -24.0 and sel < -16.0 and (spitze.values() as Array).all(func(v): return float(v) <= -6.0),
				"„%s“: leise, nie über −6 dBFS („select“ %.1f dBFS)" % [id, sel])
		check(float(spitze.get("move", 0.0)) < sel - 5.0 and float(spitze.get("tick", 0.0)) < sel - 5.0,
				"„%s“: Bewegen und Raste deutlich leiser als Bestätigen" % id)
		check(float(spitze.get("power_off", 0.0)) < lautester, "„%s“: Ausschalten ist nicht der lauteste" % id)
		check(in_quelle == grund.size(), "„%s“: Herkunft mit SHA-256 je Datei" % id)


## Fassungen (Klang.variante) und aufsteigende Schritte (Klang.stufe_ton); die Ereignisse der Einrichtung.
func _fassungen_logik() -> void:
	print("Fassungen und Stufen")
	check(Klang.variante(1, 0, 0.7) == 0 and Klang.variante(0, -1, 0.3) == 0, "eine Fassung: immer diese")
	var nie_gleich := true
	var gesehen := {}
	var vorher := -1
	for i in 400:
		var k := Klang.variante(4, vorher, fmod(i * 0.618034, 1.0))
		nie_gleich = nie_gleich and k != vorher and k >= 0 and k < 4
		gesehen[k] = true
		vorher = k
	check(nie_gleich and gesehen.size() == 4, "vier Fassungen: alle kommen vor, nie zweimal dieselbe hintereinander")
	check(Klang.variante(3, -1, 0.0) == 0 and Klang.variante(3, -1, 1.0) == 2 and Klang.variante(3, 7, 0.5) == 1 and Klang.variante(2, 0, 0.9) == 1,
			"Ränder: Zufall 0 und 1, unbekannte vorige Fassung")
	check(is_equal_approx(Klang.stufe_ton(0), 1.0) and is_equal_approx(Klang.stufe_ton(3), pow(2.0, 7.0 / 12.0)) and is_equal_approx(Klang.stufe_ton(5), 2.0),
			"Schritte: E-Dur pentatonisch, Stufe 5 eine Oktave höher")
	var steigt := true
	for i in 10:
		steigt = steigt and Klang.stufe_ton(i + 1) > Klang.stufe_ton(i)
	check(steigt and is_equal_approx(Klang.stufe_ton(-3), 1.0) and is_equal_approx(Klang.stufe_ton(99), 4.0), "aufsteigend und begrenzt (höchstens zwei Oktaven)")
	check(Klang.EINRICHTUNG.all(func(n): return Sfx.NAMES.has(n) and Sfx.PRIO.has(n) and Sfx.ERSATZ_IM_SATZ.has(n) and Klang.PALETTE.has(n))
			and Sfx.ERSATZ_IM_SATZ.size() == Klang.EINRICHTUNG.size(), "Einrichtung: %s – Name, Rang, Palette, Ersatz in anderen Sätzen" % ", ".join(Klang.EINRICHTUNG))


## Eine erzeugte Datei: { ok, ms, spitze (dBFS), rand (größter Betrag der ersten und letzten zwei Werte) }.
func _wav(res: String) -> Dictionary:
	var w := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(res))
	if w == null:
		return { "ok": false }
	var n := w.data.size() / 4
	var p := 0
	for i in n * 2:
		p = maxi(p, absi(w.data.decode_s16(i * 2)))
	var rand := 0
	for i in 4:
		rand = maxi(rand, absi(w.data.decode_s16(i * 2)))
		rand = maxi(rand, absi(w.data.decode_s16((n * 2 - 1 - i) * 2)))
	return { "ok": w.stereo and w.format == AudioStreamWAV.FORMAT_16_BITS and w.mix_rate == 44100, "ms": n * 1000.0 / w.mix_rate,
		"spitze": linear_to_db(p / 32767.0), "rand": rand }


## „Perle“ (tools/synth_klang3.py, Standard bis 0.16): alle Klänge samt Einrichtung und Fassungen, Format,
## kein Klang länger als seine Bewegung + 60 ms (Start ≤ 2 s), gestaffelt, beginnt und endet bei null, Herkunft.
func _klang3_dateien() -> void:
	print("Klangsatz Perle")
	var src := FileAccess.get_file_as_string("res://tools/synth_klang3.py")
	var quelle := FileAccess.get_file_as_string("res://assets/sounds/KLANG-QUELLE.txt")
	check(quelle.contains("synth_tick.py") and quelle.contains("synth_klang2.py") and quelle.contains("synth_klang3.py"),
			"Herkunft: Tick, Filz & Glas … und Perle in KLANG-QUELLE.txt")
	var re := RegEx.create_from_string('\\("(\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+(\\d+),\\s+(\\d),')
	var tab := {}
	for m in re.search_all(src):
		tab[m.get_string(1)] = [int(m.get_string(2)), float(m.get_string(3)), int(m.get_string(4)), int(m.get_string(5))]
	check(tab.size() == Sfx.NAMES.size() and Sfx.NAMES.all(func(n): return tab.has(n)), "Tabelle: alle %d Klänge samt Einrichtung" % tab.size())
	var anders: Array = []
	for n in tab:
		var pal: Array = Klang.PALETTE.get(n, [0, 0.0, -1])
		if int(tab[n][2]) != int(pal[2]) or (n in Klang.EINRICHTUNG and (int(tab[n][0]) != int(pal[0]) or not is_equal_approx(float(tab[n][1]), float(pal[1])))):
			anders.append(n)
	check(anders.is_empty(), "Bewegung wie in der Palette, Einrichtung ganz wie dort %s" % ", ".join(anders))
	var fass := func(n: String) -> int: return int((tab.get(n, [0, 0.0, 0, 1]) as Array)[3])
	check(fass.call("move") >= 3 and fass.call("tick") >= 2 and fass.call("select") >= 2 and fass.call("back") >= 2 and fass.call("move") <= Sfx.FASSUNGEN_MAX,
			"mehrere Fassungen: Bewegen %d, Raste %d, Bestätigen %d, Zurück %d" % [fass.call("move"), fass.call("tick"), fass.call("select"), fass.call("back")])
	var dateien := 0
	var da := 0
	var format_ok := true
	var zu_lang: Array = []
	var knack: Array = []
	var in_quelle := 0
	var spitze := {}
	for n in tab:
		for k in int(tab[n][3]):
			dateien += 1
			var datei := "%s.wav" % n if k == 0 else "%s_v%d.wav" % [n, k + 1]
			var res := "res://assets/sounds/perle/" + datei
			if not ResourceLoader.exists(res):
				continue
			da += 1
			if quelle.contains("  perle/" + datei):
				in_quelle += 1
			var w := _wav(res)
			format_ok = format_ok and bool(w.get("ok", false))
			if not bool(w.get("ok", false)):
				continue
			var grenze := 2000.0 if n == "boot" else float(int(tab[n][2]) + Klang.NACHKLANG_MS)
			if float(w.ms) > grenze:
				zu_lang.append("%s %.0f ms" % [datei, w.ms])
			if int(w.rand) > 40:
				knack.append(datei)
			if k == 0:
				spitze[n] = float(w.spitze)
	check(da == dateien and format_ok, "alle %d Dateien (%d Klänge mit Fassungen), 44,1 kHz, Stereo, 16 Bit" % [da, tab.size()])
	check(zu_lang.is_empty(), "kein Klang länger als seine Bewegung + 60 ms, Start ≤ 2 s %s" % ", ".join(zu_lang))
	check(knack.is_empty(), "beginnt und endet bei null %s" % ", ".join(knack))
	check(in_quelle == dateien, "Herkunft mit SHA-256 je Datei (%d)" % in_quelle)
	var sel: float = spitze.get("select", 0.0)
	check(sel > -24.0 and sel < -16.0 and (spitze.values() as Array).all(func(v): return float(v) <= -6.0), "leise, nie über −6 dBFS („select“ %.1f dBFS)" % sel)
	check(float(spitze.get("move", 0.0)) < sel - 5.0 and float(spitze.get("tick", 0.0)) < sel - 5.0, "Bewegen und Raste deutlich leiser als Bestätigen")
	check(float(spitze.get("power_off", 0.0)) < (spitze.values() as Array).max(), "Ausschalten ist nicht der lauteste")
	check(float(tab["move"][0]) < Klang.RATE_MS + 1.0 and float(tab["tick"][0]) < Klang.RATE_MS,
			"Bewegen %d ms, Raste %d ms: vorbei, bevor der nächste kommt" % [tab["move"][0], tab["tick"][0]])
	var src4 := FileAccess.get_file_as_string("res://tools/synth_klang4.py")
	check(not src.contains("def baue_einr") and src.contains("tools/synth_klang5.py --einrichtung") and not src4.contains("def baue_einr")
			and src4.contains("tools/synth_klang5.py --einrichtung"),
			"die Klänge der Einrichtung rendert nur noch tools/synth_klang5.py (synth_klang3.py und synth_klang4.py überschreiben sie nicht)")
	src = FileAccess.get_file_as_string("res://tools/synth_klang5.py")
	# Klänge der Einrichtung (eigener Ordner, unabhängig vom Satz; EINR_TABELLE in tools/synth_klang5.py: Höchstlänge ms).
	var re_su := RegEx.create_from_string('\\("(su_\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+"')
	var su_da := 0
	var su_ok := true
	var su_fehler: Array = []
	var su_zahl := 0
	for m in re_su.search_all(src):
		su_zahl += 1
		var datei := "einrichtung/%s.wav" % m.get_string(1)
		var w := _wav("res://assets/sounds/" + datei)
		if not bool(w.get("ok", false)):
			su_ok = false
			su_fehler.append(datei)
			continue
		su_da += 1
		if float(w.ms) > float(m.get_string(2)) + 0.5 or float(w.spitze) > -6.0 or int(w.rand) > 40 or not quelle.contains("  " + datei):
			su_fehler.append(datei)
	check(su_zahl >= 12 and su_da == su_zahl and su_ok and su_fehler.is_empty(),
			"Einrichtung: %d Klänge in assets/sounds/einrichtung, höchstens so lang wie in der Tabelle, ≤ −6 dBFS, bei null, Herkunft %s" % [su_da, ", ".join(su_fehler)])



## Messwerte einer Datei: Spitze und Kurzzeit-RMS (lautestes 50-ms-Fenster) in dBFS, Spektralschwerpunkt (Hz, nach
## Betrag gewichtet, Teiltöne ab −60 dB; DFT in 50-Hz-Schritten bis 11 kHz, Goertzel) und Energieanteil über 6 kHz,
## knackt: 1 ms nach dem Einsatz (5 % der Spitze) schon über der Hälfte der Spitze (Anstieg unter etwa 2 ms).
## bis_s > 0: das Spektrum nur über die ersten bis_s Sekunden (lange Klänge; der Nachklang ist nur noch Raum).
func _messung(res: String, bis_s := 0.0) -> Dictionary:
	var w := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(res))
	if w == null or not w.stereo:
		return {}
	var n := w.data.size() / 4
	var mono := PackedFloat32Array()
	mono.resize(n)
	var summe := PackedFloat64Array()
	summe.resize(n + 1)
	var p := 0.0
	for i in n:
		var a := w.data.decode_s16(i * 4) / 32767.0
		var b := w.data.decode_s16(i * 4 + 2) / 32767.0
		mono[i] = (a + b) * 0.5
		p = maxf(p, maxf(absf(a), absf(b)))
		summe[i + 1] = summe[i] + (a * a + b * b) * 0.5
	var fen := int(0.05 * w.mix_rate)
	var best := 0.0
	for i in range(0, maxi(1, n - fen + 1), int(0.005 * w.mix_rate)):
		best = maxf(best, (summe[mini(n, i + fen)] - summe[i]) / fen)
	var mags := PackedFloat64Array()
	var mx := 0.0
	var n_spektrum := mini(n, int(bis_s * w.mix_rate)) if bis_s > 0.0 else n
	for k in range(1, 221):
		var c := 2.0 * cos(TAU * k * 50.0 / w.mix_rate)
		var s1 := 0.0
		var s2 := 0.0
		for i in n_spektrum:
			var s0 := mono[i] + c * s1 - s2
			s2 = s1
			s1 = s0
		var m := sqrt(maxf(0.0, s1 * s1 + s2 * s2 - c * s1 * s2))
		mags.append(m)
		mx = maxf(mx, m)
	var zaehler := 0.0
	var nenner := 0.0
	var e_hoch := 0.0
	var e_alle := 0.0
	for k in mags.size():
		var f := (k + 1) * 50.0
		if mags[k] >= mx * 0.001:
			zaehler += f * mags[k]
			nenner += mags[k]
		e_alle += mags[k] * mags[k]
		if f > 6000.0:
			e_hoch += mags[k] * mags[k]
	var pm := 0.0
	for i in n:
		pm = maxf(pm, absf(mono[i]))
	var ein := 0
	while ein < n and absf(mono[ein]) < 0.05 * pm:
		ein += 1
	var frueh := 0.0
	for i in range(ein, mini(n, ein + int(0.001 * w.mix_rate))):
		frueh = maxf(frueh, absf(mono[i]))
	return { "spitze": linear_to_db(p), "rms": linear_to_db(sqrt(best)), "schwerpunkt": zaehler / maxf(nenner, 1e-12),
		"ueber6k": e_hoch / maxf(e_alle, 1e-12), "knackt": frueh > 0.5 * pm }


## Die vier weichen Sätze aus tools/synth_klang4.py („Samt“ Standard, „Kiesel“, „Pad“, „Haptik“): alle Klänge mit
## Fassungen, Format, Längen, Staffelung, Herkunft – und die Ziele gegen „penetrant“: Bewegen und Raste dunkel
## (Schwerpunkt < 1,5 kHz, < 5 % über 6 kHz), ohne Knacken, Spitze ≤ −12 dBFS, mindestens 6 dB unter „select“;
## „select“ und „back“ unter 2,2 kHz; alles leiser als „Perle“.
func _klang4_dateien() -> void:
	print("Klangsätze Samt, Kiesel, Pad, Haptik")
	var src := FileAccess.get_file_as_string("res://tools/synth_klang4.py")
	var quelle := FileAccess.get_file_as_string("res://assets/sounds/KLANG-QUELLE.txt")
	var ids := ["samt", "kiesel", "pad", "haptik"]
	var waehlbar: Array = Klang.SAETZE.map(func(o): return str(o[0]))
	var alle_da := quelle.contains("synth_klang4.py")
	for i in ids:
		alle_da = alle_da and src.contains('"%s": ("' % i) and waehlbar.has(i) and Klang.SAETZE_GESTAFFELT.has(i)
	check(alle_da, "vier Sätze wählbar, gestaffelt, Herkunft in KLANG-QUELLE.txt")
	var re := RegEx.create_from_string('\\("(\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+(\\d+),\\s+(\\d),')
	var tab := {}
	for m in re.search_all(src):
		tab[m.get_string(1)] = [int(m.get_string(2)), float(m.get_string(3)), int(m.get_string(4)), int(m.get_string(5))]
	var anders: Array = []
	for n in tab:
		var pal: Array = Klang.PALETTE.get(n, [0, 0.0, -1])
		if int(tab[n][2]) != int(pal[2]) or (n in Klang.EINRICHTUNG and (int(tab[n][0]) != int(pal[0]) or not is_equal_approx(float(tab[n][1]), float(pal[1])))):
			anders.append(n)
	check(tab.size() == Sfx.NAMES.size() and Sfx.NAMES.all(func(n): return tab.has(n)) and anders.is_empty(),
			"Tabelle: alle %d Klänge, Bewegung wie in der Palette, Einrichtung ganz wie dort %s" % [tab.size(), ", ".join(anders)])
	check(int(tab["move"][3]) == 4 and int(tab["tick"][3]) == 3 and int(tab["select"][3]) == 3 and int(tab["back"][3]) == 2
			and float(tab["move"][1]) <= -6.0 and float(tab["tick"][1]) <= -6.0, "Fassungen: Bewegen 4, Raste 3, Bestätigen 3, Zurück 2; Bewegen und Raste leise gestaffelt")
	var perle := { "move": _messung("res://assets/sounds/perle/move.wav"), "select": _messung("res://assets/sounds/perle/select.wav") }
	for id in ids:
		var dateien := 0
		var da := 0
		var format_ok := true
		var zu_lang: Array = []
		var knack: Array = []
		var in_quelle := 0
		var spitze := {}
		for n in tab:
			for k in int(tab[n][3]):
				dateien += 1
				var datei := "%s.wav" % n if k == 0 else "%s_v%d.wav" % [n, k + 1]
				var res := "res://assets/sounds/%s/%s" % [id, datei]
				if not ResourceLoader.exists(res):
					continue
				da += 1
				if quelle.contains("  %s/%s" % [id, datei]):
					in_quelle += 1
				var w := _wav(res)
				format_ok = format_ok and bool(w.get("ok", false))
				if not bool(w.get("ok", false)):
					continue
				var grenze := 2000.0 if n == "boot" else float(int(tab[n][2]) + Klang.NACHKLANG_MS)
				if float(w.ms) > grenze or absf(float(w.ms) - float(tab[n][0])) > 1.0:
					zu_lang.append("%s %.0f ms" % [datei, w.ms])
				if int(w.rand) > 40:
					knack.append(datei)
				if k == 0:
					spitze[n] = float(w.spitze)
		check(da == dateien and format_ok and in_quelle == dateien, "„%s“: alle %d Dateien, 44,1 kHz, Stereo, 16 Bit, Herkunft mit SHA-256" % [id, da])
		check(zu_lang.is_empty() and knack.is_empty(), "„%s“: Länge wie in der Tabelle (≤ Bewegung + 60 ms), beginnt und endet bei null %s" % [id, ", ".join(zu_lang + knack)])
		check((spitze.values() as Array).all(func(v): return float(v) <= -6.0) and float(spitze.get("power_off", 0.0)) < (spitze.values() as Array).max(),
				"„%s“: nie über −6 dBFS, Ausschalten nicht der lauteste" % id)
		var sel := _messung("res://assets/sounds/%s/select.wav" % id)
		var bk := _messung("res://assets/sounds/%s/back.wav" % id)
		var nav_ok := true
		var nav_txt: Array = []
		for n in ["move", "tick"]:
			for k in int(tab[n][3]):
				var m := _messung("res://assets/sounds/%s/%s" % [id, "%s.wav" % n if k == 0 else "%s_v%d.wav" % [n, k + 1]])
				var ok := not m.is_empty() and float(m.schwerpunkt) < 1500.0 and float(m.ueber6k) < 0.05 and not bool(m.knackt) and float(m.spitze) <= -12.0 \
						and float(m.rms) <= float(sel.rms) - 6.0
				nav_ok = nav_ok and ok
				if k == 0:
					nav_txt.append("%s %.0f Hz %.1f dBFS" % [n, float(m.get("schwerpunkt", 0.0)), float(m.get("spitze", 0.0))])
		check(nav_ok, "„%s“: Bewegen und Raste (alle Fassungen) dunkel, ohne Knacken, ≤ −12 dBFS, 6 dB unter „select“ (%s)" % [id, ", ".join(nav_txt)])
		check(float(sel.schwerpunkt) < 2200.0 and float(bk.schwerpunkt) < 2200.0 and float(sel.ueber6k) < 0.05 and not bool(sel.knackt),
				"„%s“: Bestätigen %.0f Hz, Zurück %.0f Hz (unter 2,2 kHz), ohne Knacken" % [id, sel.schwerpunkt, bk.schwerpunkt])
		var mv := _messung("res://assets/sounds/%s/move.wav" % id)
		check(float(sel.rms) < float(perle.select.rms) and float(mv.rms) < float(perle.move.rms) and float(sel.spitze) > -28.0,
				"„%s“: leiser als „Perle“ (Bestätigen %+.1f dB, Bewegen %+.1f dB), aber hörbar" % [id, float(sel.rms) - float(perle.select.rms),
				float(mv.rms) - float(perle.move.rms)])
	# Zum Vergleich: „Perle“ verfehlt die Ziele (darum der neue Standard).
	check(float(perle.move.schwerpunkt) > 1500.0 or bool(perle.move.knackt), "„Perle“ zum Vergleich: Bewegen %.0f Hz%s" % [perle.move.schwerpunkt,
			", knackt" if bool(perle.move.knackt) else ""])


## Der Standard „Handpan“ (tools/synth_klang5.py): alle Klänge mit Fassungen, Format, Höchstlängen, Herkunft, Pegel
## im Verhältnis der Hörprobe, 10 dB leiser (Kurzzeit-RMS: Bestätigen −29 dBFS, Bewegen 7 dB darunter), nie über −6 dBFS, ohne Knacken,
## dunkel (Bewegen und Raste unter 1,5 kHz, Bestätigen und Zurück unter 2,2 kHz). Sie klingt bewusst nach: statt
## „Bewegung + 60 ms“ gelten die Höchstlängen der Tabelle, Ausschalten endet vor der Grenze von power_off.gd (1,6 s).
func _klang5_dateien() -> void:
	print("Klangsatz Handpan")
	var src := FileAccess.get_file_as_string("res://tools/synth_klang5.py")
	var quelle := FileAccess.get_file_as_string("res://assets/sounds/KLANG-QUELLE.txt")
	check(quelle.contains("synth_klang5.py") and Klang.SAETZE_GESTAFFELT.has("handpan") and Klang.satz_ordner("handpan") == "res://assets/sounds/handpan"
			and src.contains("REF_DB = -29.0") and src.contains("VERH = (1.0, 2.0, 3.01, 0.5)") and src.contains("ANSTIEG_S = 0.014"),
			"„Handpan“: gestaffelt, eigener Ordner, Herkunft; Vorlage „Tief rund“ (Teiltöne 1 : 2 : 3,01 : 0,5, 14 ms Anstieg, select −29 dBFS)")
	var re := RegEx.create_from_string('\\("(\\w+)",\\s+(\\d+),\\s+(-?[\\d.]+),\\s+(\\d),\\s+"')
	var tab := {}
	for m in re.search_all(src):
		tab[m.get_string(1)] = [int(m.get_string(2)), float(m.get_string(3)), int(m.get_string(4))]
	check(tab.size() == Sfx.NAMES.size() and Sfx.NAMES.all(func(n): return tab.has(n)), "Tabelle: alle %d Klänge samt Einrichtung" % tab.size())
	check(int(tab["move"][2]) == 4 and int(tab["tick"][2]) == 3 and int(tab["select"][2]) == 3 and int(tab["back"][2]) == 2
			and float(tab["move"][1]) <= -6.0 and float(tab["tick"][1]) <= -6.0, "Fassungen: Bewegen 4, Raste 3, Bestätigen 3, Zurück 2; Bewegen und Raste leise gestaffelt")
	var dateien := 0
	var da := 0
	var format_ok := true
	var zu_lang: Array = []
	var knack: Array = []
	var in_quelle := 0
	var spitze := {}
	var laenge := {}
	for n in tab:
		for k in int(tab[n][2]):
			dateien += 1
			var datei := "%s.wav" % n if k == 0 else "%s_v%d.wav" % [n, k + 1]
			var res := "res://assets/sounds/handpan/" + datei
			if not ResourceLoader.exists(res):
				continue
			da += 1
			if quelle.contains("  handpan/" + datei):
				in_quelle += 1
			var w := _wav(res)
			format_ok = format_ok and bool(w.get("ok", false))
			if not bool(w.get("ok", false)):
				continue
			if float(w.ms) > float(tab[n][0]) + 0.5:
				zu_lang.append("%s %.0f ms" % [datei, w.ms])
			if int(w.rand) > 40:
				knack.append(datei)
			if k == 0:
				spitze[n] = float(w.spitze)
				laenge[n] = float(w.ms)
	check(da == dateien and format_ok and in_quelle == dateien, "alle %d Dateien, 44,1 kHz, Stereo, 16 Bit, Herkunft mit SHA-256" % da)
	check(zu_lang.is_empty() and knack.is_empty(), "höchstens so lang wie in der Tabelle, beginnt und endet bei null %s" % ", ".join(zu_lang + knack))
	check((spitze.values() as Array).all(func(v): return float(v) <= -6.0) and float(spitze.get("power_off", 0.0)) < (spitze.values() as Array).max(),
			"nie über −6 dBFS, Ausschalten nicht der lauteste")
	check(float(laenge.get("power_off", 9999.0)) < 1600.0 and float(laenge.get("select", 9999.0)) < 1100.0 and float(laenge.get("open", 0.0)) > 2000.0,
			"Ausschalten %.0f ms (endet vor 1,6 s), Bestätigen kurz (%.2f s, oft hintereinander), Öffnen klingt %.1f s nach"
			% [laenge.get("power_off", 0.0), float(laenge.get("select", 0.0)) / 1000.0, float(laenge.get("open", 0.0)) / 1000.0])
	var sel := _messung("res://assets/sounds/handpan/select.wav", 0.4)
	var bk := _messung("res://assets/sounds/handpan/back.wav", 0.4)
	var mv := _messung("res://assets/sounds/handpan/move.wav", 0.3)
	var tk := _messung("res://assets/sounds/handpan/tick.wav", 0.3)
	check(absf(float(sel.rms) + 29.0) < 0.6 and absf(float(mv.rms) + 36.0) < 0.6 and float(mv.rms) <= float(sel.rms) - 6.0
			and float(tk.rms) <= float(sel.rms) - 6.0,
			"Pegel (Hörprobe −10 dB): Bestätigen %.1f, Bewegen %.1f, Raste %.1f dBFS" % [sel.rms, mv.rms, tk.rms])
	var dunkel := true
	for m in [mv, tk]:
		dunkel = dunkel and float(m.schwerpunkt) < 1500.0 and float(m.ueber6k) < 0.05 and not bool(m.knackt) and float(m.spitze) <= -12.0
	check(dunkel and float(sel.schwerpunkt) < 2200.0 and float(bk.schwerpunkt) < 2200.0 and not bool(sel.knackt) and not bool(bk.knackt),
			"dunkel und weich: Bewegen %.0f Hz, Raste %.0f Hz, Bestätigen %.0f Hz, Zurück %.0f Hz, ohne Knacken"
			% [mv.schwerpunkt, tk.schwerpunkt, sel.schwerpunkt, bk.schwerpunkt])


func _haptik() -> void:
	print("Haptik")
	var alle_ok := true
	for k in PadsS.PULSES_UI.keys():
		for st in PadsS.ui_plan(k):
			alle_ok = alle_ok and int(st[3]) >= 25 and int(st[3]) <= 60 and float(st[1]) <= 1.0 and float(st[2]) <= 1.0
	check(alle_ok, "Impulse der Oberfläche 25–60 ms, nie dauerhaft")
	var g := PadsS.ui_plan("guide")
	check(g.size() == 1 and float(g[0][1]) > 0.0 and float(g[0][2]) == 0.0 and int(g[0][3]) == 45, "Guide: tiefer Motor, 45 ms")
	var a := PadsS.ui_plan("auswahl")
	check(a.size() == 1 and float(a[0][1]) == 0.0 and float(a[0][2]) > 0.0, "Haupthandlung: heller Motor")
	var f := PadsS.ui_plan("fehler")
	check(f.size() == 2 and int(f[1][0]) == 90 and int(f[0][3]) == 30, "Fehler: zweimal tief, 90 ms Abstand")
	check(PadsS.ui_plan("move").is_empty() and PadsS.ui_plan("back").is_empty(), "Cursor, Zurück: kein Impuls")
	check(not PadsS.rand_frei(120) and PadsS.rand_frei(PadsS.RAND_HALTEN_MS), "Rand: nur der erste Stoß je Halten")
	var an := { "vibration": true, "events": true }
	check(PadsS.pulse_allowed("auswahl", an, false, true) and not PadsS.pulse_allowed("auswahl", { "vibration": false }, false, true), "Schalter „Vibration bei Haupthandlungen“")
	check(not PadsS.pulse_allowed("rand", an, false, false), "nur, wenn Uzai vorn ist")
	check(PadsS.pulse_allowed("guide", an, true, true) and not PadsS.pulse_allowed("auswahl", an, true, true), "im Spiel nur der Guide (sonst wie heute Clip, Erfolg, Nachricht)")
	check(Sfx.HAPTIK.keys().all(func(k): return k in ["guide", "launch", "bump", "error"]) and Sfx.HAPTIK.values().all(func(v): return PadsS.PULSES_UI.has(v)),
			"Klänge mit Impuls: nur Guide, Spielen, Rand, Fehler")


## Sfx mit dem Satz „Tick“: ein Druck ein Klang, Ruhe, Richtung, Klangsatz umschalten.
func _sfx_tick() -> void:
	print("Tick: Ausgabe")
	Config.set_value("theme.sounds", true)
	check(Config.DEFAULTS.theme.get("sound_set") == "handpan" and Config.DEFAULTS.theme.get("sound_set") == Klang.SATZ_STD,
			"Standard: Klangsatz „Handpan“")
	Config.set_value("theme.sound_set", "tick")
	check(Sfx.sound_set() == "tick", "„Tick“ wählbar")
	check(Sfx.length("guide") <= 0.2 and Sfx.length("boot") < 1.3, "Tick geladen (Guide %.2f s)" % Sfx.length("guide"))
	await get_tree().create_timer(0.1).timeout
	Sfx.play("select")
	var p_sel: AudioStreamPlayer = Sfx.last_player
	var v_sel := p_sel.volume_db
	Sfx.play("open")
	var p_open: AudioStreamPlayer = Sfx.last_player
	check(p_open != p_sel and p_open.playing and p_sel.volume_db <= -79.0, "A auf eine Karte: „open“ ersetzt „select“ (einmal zu hören)")
	Sfx.play("move")
	check(Sfx.last_player == p_open, "„move“ im selben Druck bleibt still")
	await get_tree().create_timer(0.12).timeout
	# Ruhe: über 10 min keine Eingabe → 6 dB leiser, mit der ersten Eingabe in 3 s wieder voll.
	var now := Time.get_ticks_msec()
	Sfx._letzte_eingabe = now
	Sfx._rampe_ab = -1
	Sfx.play("select")
	var v0 := Sfx.last_player.volume_db
	check(absf(v0 - v_sel) < 0.01, "gleiche Lage, gleiche Stärke")
	await get_tree().create_timer(0.12).timeout
	Sfx._letzte_eingabe = Time.get_ticks_msec() - Klang.RUHE_MS - 1000
	Sfx.play("select")
	check(absf(Sfx.last_player.volume_db - (v0 - 6.0)) < 0.05, "nach 10 min Ruhe: 6 dB leiser (%.1f dB)" % (Sfx.last_player.volume_db - v0))
	var knopf := InputEventJoypadButton.new()
	knopf.pressed = true
	Sfx._on_eingabe(knopf)
	check(Sfx._rampe_ab >= 0 and Time.get_ticks_msec() - Sfx._letzte_eingabe < 100, "erste Eingabe danach startet die Rampe")
	Sfx._rampe_ab = Time.get_ticks_msec() - 1500
	await get_tree().create_timer(0.12).timeout
	Sfx.play("select")
	check(absf(Sfx.last_player.volume_db - (v0 - 3.0)) < 0.3, "nach 1,5 s halb oben (%.1f dB)" % (Sfx.last_player.volume_db - v0))
	Sfx._rampe_ab = -1
	# Bereichswechsel aus seiner Richtung.
	await get_tree().create_timer(0.12).timeout
	Sfx.play("tab", 1.0, null, "left")
	check(is_equal_approx(Sfx._panners[Sfx._players.find(Sfx.last_player)].pan, -0.3), "LB/LT: „tab“ kommt von links")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	Sfx._on_eingabe(rb)
	await get_tree().create_timer(0.12).timeout
	Sfx.play("tab")
	var erwartet := 0.3 if InputMap.has_action("uz_rb") else 0.0
	check(not InputMap.has_action("uz_rb") or is_equal_approx(Sfx._panners[Sfx._players.find(Sfx.last_player)].pan, erwartet), "RB gedrückt: „tab“ kommt von rechts")
	# Klangsatz „Glas“: die alten Klänge, mit ihren alten Stärken.
	Config.set_value("theme.sound_set", "glas")
	check(Sfx.sound_set() == "glas" and Sfx.length("guide") > 1.0 and Sfx.length("boot") > 4.0, "„Glas“ gewählt: die alten Klänge (Guide %.1f s)" % Sfx.length("guide"))
	await get_tree().create_timer(0.12).timeout
	Sfx.play("move")
	var vg := Sfx.last_player.volume_db
	await get_tree().create_timer(0.3).timeout
	Config.set_value("theme.sound_set", "unsinn")
	check(Sfx.sound_set() == "handpan", "unbekannter Satz: „Handpan“")
	Config.set_value("theme.sound_set", "tick")
	check(Sfx.length("guide") <= 0.2, "zurück zu „Tick“ (Guide %.2f s)" % Sfx.length("guide"))
	Sfx.play("move")
	check(vg < Sfx.last_player.volume_db - 5.0, "„Glas“ mit alter Stärke (Bewegen × 0,32)")
	# Die neuen Sätze: eigene Dateien, eigene Staffelung (ohne GAIN), kurz.
	for id in ["samt", "kiesel", "pad", "haptik", "perle", "filzglas", "glaskurz", "filz", "luft"]:
		Config.set_value("theme.sound_set", id)
		check(Sfx.sound_set() == id and Sfx._alt.is_empty() and Sfx.length("guide") <= 0.26 and Sfx.length("boot") <= 2.0
				and str((Sfx._streams["select"] as AudioStream).resource_path).contains("/%s/" % id),
				"„%s“ gewählt: eigene Dateien, Guide %.2f s, Start %.2f s" % [id, Sfx.length("guide"), Sfx.length("boot")])
	# „Perle“: Fassungen, nie dieselbe zweimal hintereinander; eigene Klänge für die Einrichtung.
	Config.set_value("theme.sound_set", "perle")
	check((Sfx._fassungen.get("move", []) as Array).size() == 4 and (Sfx._fassungen.get("select", []) as Array).size() == 3
			and not Sfx._fassungen.has("guide"), "„Perle“: Bewegen in 4, Bestätigen in 3 Fassungen, Guide in einer")
	var vorige: AudioStream = null
	var verschieden := {}
	var nie_gleich := true
	for i in 40:
		var f: AudioStream = Sfx._fassung("move")
		nie_gleich = nie_gleich and f != vorige
		verschieden[f.resource_path] = true
		vorige = f
	check(nie_gleich and verschieden.size() == 4, "Bewegen: alle vier Fassungen, nie zweimal dieselbe hintereinander")
	check(Klang.EINRICHTUNG.all(func(n): return str((Sfx._streams[n] as AudioStream).resource_path).ends_with("/perle/%s.wav" % n)),
			"„Perle“: eigene Klänge für die Einrichtung")
	# Die vier weichen Sätze: Fassungen wie „Perle“, eigene Klänge für die Einrichtung.
	for id in ["samt", "kiesel", "pad", "haptik"]:
		Config.set_value("theme.sound_set", id)
		var mv: Array = Sfx._fassungen.get("move", [])
		var vor: AudioStream = null
		var gleich := false
		for i in 24:
			var f: AudioStream = Sfx._fassung("move")
			gleich = gleich or f == vor
			vor = f
		check(mv.size() == 4 and (Sfx._fassungen.get("select", []) as Array).size() == 3 and (Sfx._fassungen.get("tick", []) as Array).size() == 3
				and not gleich and Klang.EINRICHTUNG.all(func(n): return str((Sfx._streams[n] as AudioStream).resource_path).ends_with("/%s/%s.wav" % [id, n])),
				"„%s“: Bewegen in 4, Bestätigen und Raste in 3 Fassungen, nie zweimal dieselbe; eigene Klänge für die Einrichtung" % id)
	# „Handpan“: eigene Dateien mit Fassungen und eigene Klänge für die Einrichtung; klingt nach, Ausschalten kurz genug.
	Config.set_value("theme.sound_set", "handpan")
	check(Sfx.sound_set() == "handpan" and Sfx._alt.is_empty() and str((Sfx._streams["select"] as AudioStream).resource_path).contains("/handpan/")
			and (Sfx._fassungen.get("move", []) as Array).size() == 4 and (Sfx._fassungen.get("select", []) as Array).size() == 3
			and Klang.EINRICHTUNG.all(func(n): return str((Sfx._streams[n] as AudioStream).resource_path).ends_with("/handpan/%s.wav" % n))
			and Sfx.length("select") < 1.1 and Sfx.length("open") > 2.0 and Sfx.length("power_off") < 1.6,
			"„Handpan“ gewählt: eigene Dateien und Fassungen, Bestätigen %.1f s, Öffnen %.1f s, Ausschalten %.2f s"
			% [Sfx.length("select"), Sfx.length("open"), Sfx.length("power_off")])
	# Lange Nachklänge: Bewegen verstummt beim nächsten, ein verstummter Spieler gilt als frei – ein neuer Klang
	# nimmt ihn, bevor er einen hörbaren Nachklang abschneidet.
	for q in Sfx._players:
		q.stop()
	await get_tree().create_timer(0.12).timeout
	Sfx.play("open")
	var p_halt: AudioStreamPlayer = Sfx.last_player
	var belegt := 0
	for i in Sfx._players.size() + 2:
		await get_tree().create_timer(0.1).timeout
		Sfx.play("move")
		belegt = maxi(belegt, Sfx._players.filter(func(q): return q.playing).size())
	check(belegt == Sfx._players.size() and p_halt.playing and p_halt.volume_db > -79.0,
			"schnelles Blättern über einem Nachklang: alle Spieler belegt, der Nachklang von Öffnen läuft weiter")
	Config.set_value("theme.sound_set", "filzglas")
	check(Sfx._streams["setup_step"] == Sfx._streams["select"] and Sfx._streams["swell"] == Sfx._streams["open"]
			and Sfx._streams["setup_done"] == Sfx._streams["achievement"] and Sfx._fassungen.is_empty(),
			"„Filz & Glas“: Einrichtung mit Grundklängen desselben Satzes, keine Fassungen")
	Config.set_value("theme.sound_set", "tick")
	check(Sfx._streams["setup_found"] == Sfx._streams["toggle_on"], "„Tick“: Einrichtung mit Grundklängen")


## Neuer Standard: wer einen alten Standard hatte („Glas“ bis 0.11, „Filz & Glas“, „Perle“ bis 0.16, „Samt“ in 0.16),
## bekommt einmal „Handpan“; eigene Wahl bleibt.
func _satz_umbau() -> void:
	print("Klangsatz: einmal umstellen")
	var sp := Config.path("settings.json")
	var laden := func(rev: int, satz: String) -> String:
		Config.write_json(sp, { "uzai_version": Config.VERSION, "schema": Config.SETTINGS_VERSION, "theme": { "rev": rev, "sound_set": satz } })
		Config.load_settings()
		return str(Config.get_value("theme.sound_set", ""))
	check(laden.call(10, "glas") == "handpan" and int(Config.get_value("theme.rev", 0)) == 14, "alter Standard „Glas“: jetzt „Handpan“")
	check(laden.call(11, "filzglas") == "handpan" and int(Config.get_value("theme.rev", 0)) == 14, "Standard „Filz & Glas“: jetzt „Handpan“")
	check(laden.call(12, "perle") == "handpan" and int(Config.get_value("theme.rev", 0)) == 14, "Standard „Perle“: jetzt „Handpan“")
	check(laden.call(13, "samt") == "handpan" and int(Config.get_value("theme.rev", 0)) == 14, "bisheriger Standard „Samt“: jetzt „Handpan“")
	check(laden.call(14, "samt") == "samt", "danach „Samt“ gewählt: bleibt")
	check(laden.call(13, "perle") == "perle", "danach „Perle“ gewählt: bleibt")
	check(laden.call(12, "kiesel") == "kiesel" and laden.call(13, "filz") == "filz", "eigene Wahl („Kiesel“, „Filz“) bleibt")
	check(laden.call(10, "filz") == "filz", "eigene Wahl („Filz“) bleibt")
	check(laden.call(11, "glas") == "glas", "danach „Glas“ gewählt: bleibt")
	check(laden.call(11, "tick") == "tick", "„Tick“ gewählt: bleibt")
	check(laden.call(12, "filzglas") == "filzglas", "danach „Filz & Glas“ gewählt: bleibt")


func _musik_laeuft() -> void:
	print("Menümusik: Ablauf")
	var mm: Node = Sfx.musik
	await get_tree().process_frame
	check(not mm.call("spielt"), "Standard: spielt nicht")
	Config.set_value("theme.music", 0.6)
	var z: Dictionary = mm.call("zustand")
	check(bool(z.an) and bool(z.stueck), "eingeschaltet: Stück vom Theme da")
	mm.set("_ruhig_seit", 0.0)
	mm.call("_tick")
	check(mm.call("spielt"), "alles ruhig: spielt")
	Launcher.in_game = true
	check(not Klang.musik_soll(mm.call("zustand")), "Spiel läuft: soll nicht")
	mm.call("_tick")
	check(not mm.call("spielt"), "Spiel läuft: blendet aus")
	Launcher.in_game = false
	Video.active = true
	mm.set("_ruhig_seit", 0.0)
	mm.call("_tick")
	check(not mm.call("spielt"), "Video läuft: bleibt aus")
	Video.active = false
	mm.set("_ruhig_seit", 0.0)
	mm.call("_tick")
	check(mm.call("spielt"), "danach wieder an")
	Sfx.play("launch")
	check(not mm.call("spielt"), "Spielstart-Klang: sofort leiser")
	Leicht.active = true
	mm.set("_ruhig_seit", 0.0)
	mm.call("_tick")
	check(not mm.call("spielt"), "leichter Modus: still")
	Leicht.active = false
	Config.set_value("theme.music", 0.0)
	await get_tree().create_timer(0.1).timeout
	check(not mm.call("spielt"), "0 %: aus")

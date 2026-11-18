extends Node
## Einschalten und Ausschalten (boot.gd, power_off.gd) und scharfe Startanimationen je System
## (system_intro.gd, intro/*.gdshader): Takt zum Klang, keine Sprünge in einem Bild, ruhige
## Kurzfassung ohne Bewegung, Kanten in echten Bildpunkten, Bildzeiten im Protokoll, schwere
## Startarbeit nur in ruhigen Momenten.
## Aufruf: godot --headless --path . res://tests/logic_einschalten.tscn

const Boot := preload("res://src/ui/boot.gd")
const PowerOff := preload("res://src/ui/power_off.gd")
const SystemIntro := preload("res://src/ui/components/system_intro.gd")
const Bildzeiten := preload("res://src/ui/components/bildzeiten.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_start()
	_aus()
	_scharf()
	_messen()
	await _ruhig_arbeiten()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit()


func _start() -> void:
	print("Einschalten")
	var vor: Dictionary = Boot.phasen(Boot.LINIE_AB - 0.05)
	check(float(vor.linie) == 0.0 and float(vor.baender) == 0.0, "vor der Linie: dunkel")
	check(float(Boot.phasen(Boot.AKKORD).linie) == 1.0 and Boot.BAND_AB < Boot.AKKORD,
		"die Linie zieht sich in einem Zug, die Bänder setzen sich darum – bis zum Akkord")
	check(float(Boot.phasen(Boot.BAND_AB + Boot.BAND_S).baender) == 1.0, "dann steht das Zeichen")
	check(float(Boot.phasen(Boot.LINIE_AB).mass) == 1.0 and float(Boot.phasen(Boot.LINIE_AB + Boot.MASS_S).mass) == 0.0 and Boot.MASS_VON <= 1.08,
		"es setzt sich weich auf seine Größe (von %d %%)" % int(Boot.MASS_VON * 100))
	var glanz := 0
	var t := 0.0
	while t < Boot.LAENGE:
		if float(Boot.phasen(t).glanz) > -2.0:
			glanz += 1
		t += 0.05
	check(glanz > 5 and glanz < 30, "ein einziger, kurzer Lichtverlauf")
	# Kein Sprung in einem Bild (60 Hz): jede Größe ändert sich je Bild um höchstens 0,2 – ruhig.
	var schritt := 1.0 / 60.0
	var groesster := 0.0
	t = 0.0
	while t < Boot.LAENGE:
		var a: Dictionary = Boot.phasen(t)
		var b: Dictionary = Boot.phasen(t + schritt)
		for key in a:
			if key != "glanz":
				groesster = maxf(groesster, absf(float(b[key]) - float(a[key])))
		t += schritt
	check(groesster <= 0.2, "keine harten Schritte (größter je Bild %.2f)" % groesster)
	var n: Dictionary = Boot.phasen(Boot.NAME_AT + Boot.NAME_S)
	check(float(n.name) >= 0.999 and float(Boot.phasen(Boot.NAME_AT).name) == 0.0, "die Wortmarke kommt nach dem Zeichen")
	check(Boot.LAENGE >= 3.0 and Boot.LAENGE <= 4.0 and Boot.LAENGE_KURZ < Boot.LAENGE, "3–4 s (%.1f s), „kurz“ kürzer" % Boot.LAENGE)
	var klang := FileAccess.get_file_as_string("res://tools/synth_start.py")
	check(klang.contains("LINIE_AB = %.2f" % Boot.LINIE_AB) and klang.contains("AKKORD = %.2f" % Boot.AKKORD), "Startklang im Takt des Bilds (tools/synth_start.py)")
	check(ResourceLoader.exists("res://assets/sounds/start.wav"), "Startklang da")
	var quelle := FileAccess.get_file_as_string("res://src/ui/boot.gd")
	check(not quelle.contains("SubViewport") and not quelle.contains("Particles") and not quelle.contains("MultiMesh"), "schlicht: keine 3D-Szene, keine Partikel")
	# Ruhige Fassung: ohne Weg, blendet nur ein.
	var r0: Array = Boot.phasen_ruhig(0.1)
	var r1: Array = Boot.phasen_ruhig(Boot.R_NAME_AT + Boot.R_IN)
	check(float(r0[0]) == 0.0 and float(r1[0]) == 1.0 and float(r1[1]) == 1.0 and Boot.RUHIG_LAENGE < 2.5, "ruhig: Zeichen und Name blenden ein, kurz")
	# Lage: das U allein (ohne Text und Kachel), gut zwei Fünftel der Bildhöhe, mittig; in 4K doppelt so groß.
	var zr := Boot.zeichen_rect(Vector2(1920, 1080))
	check(zr.size.y >= 1080.0 * 0.35 and zr.size.y <= 1080.0 * 0.5 and zr.get_center().distance_to(Vector2(960, 540)) < 0.5, "Zeichen %.0f px hoch, mittig" % zr.size.y)
	var wr := Boot.wort_rect(Vector2(1920, 1080))
	var u_unten := zr.get_center().y + zr.size.y * Boot.Logo.KACHEL_U * 0.5
	check(wr.position.y > u_unten + 40.0 and wr.end.y < 1080.0 * 0.8 and absf(wr.get_center().x - 960.0) < 2.0, "Wortmarke mittig unter dem U")
	check(wr.size.y >= 18.0 and wr.size.y <= 32.0, "Wortmarke klein (%.0f px Versalhöhe)" % wr.size.y)
	check(float(Boot.phasen(Boot.NAME_AT - 0.01).name) == 0.0 and float(Boot.phasen(Boot.NAME_AT + Boot.NAME_S).name) == 1.0, "Wortmarke erst am Ende")
	var bsrc := FileAccess.get_file_as_string("res://src/ui/boot.gd")
	check(not bsrc.contains("_ready_text") and not bsrc.contains("draw_string"), "Intro ohne Begrüßung und Stand")
	check(Boot.zeichen_rect(Vector2(3840, 2160)).size.is_equal_approx(zr.size * 2.0), "mit der Auflösung skaliert (4K doppelt)")
	# Am Windows-PC hingen die ersten Bilder (Fenster, Shader) – die Uhr lief weiter und die
	# Animation war vorbei, bevor sie zu sehen war; die Starttaste beendete sie gleich.
	check(not Boot.anlaufen(2, 1.0) and Boot.anlaufen(Boot.RUHIG_BILDER, 0.2) and Boot.anlaufen(0, Boot.WARTE_MAX),
		"Uhr beginnt nach ruhigen Bildern (spätestens nach %.0f s)" % Boot.WARTE_MAX)
	var uhr := 0.0
	for bild_s in [2.5, 0.016, 3.0, 0.016]:
		uhr += Boot.uhr_schritt(bild_s)
	check(uhr <= 0.55 and is_equal_approx(Boot.uhr_schritt(0.016), 0.016), "ein Hänger frisst die Animation nicht (%.2f s nach zwei Hängern)" % uhr)
	check(not Boot.darf_beenden(false, 0.0) and not Boot.darf_beenden(true, 0.1) and Boot.darf_beenden(true, Boot.SPERRE),
		"die Starttaste beendet sie nicht gleich, A/B danach schon")
	var main_src := FileAccess.get_file_as_string("res://src/main.gd") + FileAccess.get_file_as_string("res://src/main_guide.gd")
	check(not main_src.contains("_boot.finish()") and main_src.contains("_boot.taste()"), "main beendet über taste() (mit Sperre)")


func _aus() -> void:
	print("Ausschalten")
	var z0: Dictionary = PowerOff.zustand(0.0, "voll")
	check(float(z0.zoom) == 1.0 and float(z0.sy) == 1.0 and float(z0.dunkel) == 0.0 and float(z0.phosphor) == 0.0,
			"erstes Bild: die Oberfläche unverändert (darin wird der Shader übersetzt)")
	var linie: Dictionary = PowerOff.zustand(PowerOff.SQUASH.y, "voll")
	check(float(linie.sy) <= 0.001 and float(linie.sx) > 1.0, "wie eine Röhre: das Bild fällt zu einer Linie zusammen")
	var punkt: Dictionary = PowerOff.zustand(PowerOff.TO_DOT.y, "voll")
	check(float(punkt.sx) == 0.0 and float(punkt.punkt) >= 0.999 and is_equal_approx(float(punkt.dicke), float(punkt.punkt_r)),
			"die Linie wird zum Uzai-Punkt im Akzent")
	check(float(PowerOff.zustand(PowerOff.GLOW_OUT.y, "voll").form_a) <= 0.001, "der Punkt verglimmt")
	# Kein heller Blitz: Helligkeit mal Fläche bleibt klein, bevor das Bild flach ist.
	var licht := 0.0
	var t := 0.0
	while t < PowerOff.LENGTH:
		var z: Dictionary = PowerOff.zustand(t, "voll")
		licht = maxf(licht, float(z.phosphor) * float(z.sy) * float(z.sx))
		t += 0.01
	check(licht < 0.5, "kein heller Blitz über den Schirm (Helligkeit × Fläche %.2f)" % licht)
	var ruhig := true
	t = 0.0
	while t < PowerOff.SHORT:
		var k: Dictionary = PowerOff.zustand(t, "kurz")
		if float(k.zoom) != 1.0 or float(k.sx) != 1.0 or float(k.sy) != 1.0:
			ruhig = false
		t += 0.02
	check(ruhig and float(PowerOff.zustand(0.25, "kurz").ruhe_punkt) > 0.5, "kurz: ohne Bewegung, der Punkt leuchtet kurz")


func _scharf() -> void:
	print("Scharf in der echten Auflösung")
	check(is_equal_approx(SystemIntro.bildpunkt(1080.0), 2.0 / 1080.0) and is_equal_approx(SystemIntro.bildpunkt(2160.0), 1.0 / 1080.0),
			"ein Bildpunkt in 4K ist halb so groß wie in 1080p")
	check(SystemIntro.logo_hoehe_px(1.0, 1.0) == 107 and SystemIntro.logo_hoehe_px(1.0, 2.0) == 213, "Logo in 4K doppelt so hoch vorbereitet")
	# Keine festen Kantenbreiten mehr in Anteilen des Schirms (früher 0,003 … 0,006).
	var fest: Array = []
	var dir := DirAccess.open("res://src/ui/components/intro")
	for f in dir.get_files():
		if not f.ends_with(".gdshader"):
			continue
		var src := FileAccess.get_file_as_string("res://src/ui/components/intro/" + f)
		var re := RegEx.create_from_string("smoothstep\\(0\\.00[0-9]+, -0\\.00")
		if re.search(src) != null:
			fest.append(f)
	check(fest.is_empty(), "Kanten in Bildpunkten, nicht in Anteilen des Schirms (%s)" % ", ".join(fest))
	var inc := FileAccess.get_file_as_string("res://src/ui/components/intro/intro.gdshaderinc")
	check(inc.contains("uniform float bildpunkt") and inc.contains("float kante(") and inc.contains("float strich("), "Hilfen für Kanten und Linien")
	for f in ["gc", "n64"]:
		var src := FileAccess.get_file_as_string("res://src/ui/components/intro/%s.gdshader" % f)
		check(src.contains("Hüllkugel") and src.contains("bildpunkt / 2.2"), "%s: Hüllkugel (4K ohne Einbruch) und geglättete Silhouette" % f)


func _messen() -> void:
	print("Bildzeiten")
	var m := Bildzeiten.new()
	m.bild(0.0, 1000000)
	m.bild(0.016, 1016000)
	m.bild(0.06, 1060000)
	m.bild(0.076, 1076000)
	check(m.bilder == 3 and roundi(m.laengstes_ms) == 44 and is_equal_approx(m.laengstes_bei, 0.06) and m.ruckler == 1,
			"längstes Bild und Ruckler gezählt")
	check(m.bericht("Startanimation") == "Startanimation: 3 Bilder, längstes 44 ms bei 0.06 s, 1 über 25 ms", m.bericht("Startanimation"))


func _ruhig_arbeiten() -> void:
	print("Ruhige Momente")
	var main_src := FileAccess.get_file_as_string("res://src/main.gd")
	var dienste := main_src.substr(main_src.find("func _boot_services"), 900)
	check(dienste.count("await _boot_ruhig()") >= 4 and not dienste.contains("create_timer"), "Dienste starten nur in ruhigen Momenten")
	var b: Control = Boot.new().setup("konsole")
	add_child(b)
	b.set_process(false)
	b.call("seek", 0.1)
	check(bool(b.call("calm")), "dunkel am Anfang: ruhig")
	b.call("seek", Boot.AKKORD)
	check(not bool(b.call("calm")), "Akkord: nicht ruhig")
	b.call("seek", Boot.NAME_AT + Boot.NAME_S + 0.2)
	check(bool(b.call("calm")), "Name steht: ruhig")
	b.free()
	await get_tree().process_frame

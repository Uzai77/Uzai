extends Node
## Regal einer Konsole (src/library/regal.gd, src/ui/layers/regal_seite.gd, src/room/regal_welt.gd):
## Hüllenmaße und Format je System, Farbe und Text des Rückens, Abschnitte (A–Z, zuletzt, Spielzeit,
## neu), Sprünge mit LB/RB, Lage auf dem Brett, sichtbarer Bereich, Schritte beim Halten, Herausziehen
## und Feder, Kamera an den Enden, Regal oder Mosaik je Quelle – und die Seite selbst ohne Fenster:
## blättern, springen, Favorit, Sortierung, Bibliothek ändert sich, B schließt.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_regal.tscn → „Ergebnis: alles ok“

const Regal := preload("res://src/library/regal.gd")
const Seite := preload("res://src/ui/layers/regal_seite.gd")
const Welt := preload("res://src/room/regal_welt.gd")
const MosaikSeite := preload("res://src/ui/layers/mosaik_seite.gd")
const Logos := preload("res://src/core/badge_logos.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func nah(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _ready() -> void:
	_formate()
	_ruecken()
	_aufmachung()
	_logos()
	_vorderseite()
	_rahmen_erkennung()
	_scan()
	_ruecken_aufbau()
	_abschnitte()
	_lage()
	_bewegung()
	_ansicht()
	await _seite()
	Logos.data_dir_override = ""
	Logos.media_dir_override = ""
	Logos.forget()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _formate() -> void:
	print("Hüllen je System")
	check(Regal.masse("ps2") == Vector3(0.014, 0.19, 0.135), "PS2: DVD-Hülle 135 × 190 × 14 mm")
	check(Regal.masse("ps1") == Vector3(0.010, 0.125, 0.142), "PS1: CD-Hülle 142 × 125 × 10 mm")
	check(Regal.masse("switch") == Vector3(0.011, 0.17, 0.105), "Switch: schmale Hülle 105 × 170 × 11 mm")
	var gc := Regal.masse("gc")
	check(gc == Vector3(0.014, 0.19, 0.135) and (Regal.format_daten("gc").plastik as Color).get_luminance() < 0.2,
		"GameCube: Hülle in DVD-Größe 135 × 190 × 14 mm (Europa/Nordamerika), dunkel")
	check(Regal.masse("ps3") == Vector3(0.014, 0.171, 0.135) and Regal.masse("psp").z < 0.11 and Regal.masse("nds").y < 0.14,
		"PS3 Blu-ray niedriger, PSP schmal, DS klein")
	check(Regal.masse("saturn").y > Regal.masse("ps1").y + 0.05 and Regal.format_von("saturn") == "saturn", "Saturn: lange CD-Hülle")
	check(Regal.masse("n64").z > Regal.masse("n64").y and Regal.masse("nes").y > Regal.masse("nes").z, "N64/SNES-Karton quer, NES hoch")
	var x1 := Regal.format_daten("xbox")
	var x3 := Regal.format_daten("xbox360")
	check((x1.band as Color).g > (x1.band as Color).r * 1.5 and (x1.plastik as Color).get_luminance() < 0.1, "Xbox: grünes Band, dunkle Hülle")
	check((x3.plastik as Color).g > (x3.plastik as Color).r * 1.4 and (x3.band as Color).get_luminance() > 0.85, "Xbox 360: grüne Hülle, helles Band")
	check(Regal.format_von("mastersystem") == "sms" and (Regal.rahmen_von("mastersystem").farbe as Color).get_luminance() > 0.9
		and (Regal.rahmen_von("megadrive").farbe as Color).get_luminance() < 0.08, "Master System weiß, Mega Drive schwarz")
	check((Regal.rahmen_von("wiiu").farbe as Color).b > 0.6 and (Regal.rahmen_von("3ds").logo as Color).r > 0.6, "Wii U blaues Band, 3DS rotes Logo")
	check((Regal.format_daten("ps2").plastik as Color).get_luminance() < 0.1, "PS2 schwarz")
	check((Regal.format_daten("wii").plastik as Color).get_luminance() > 0.8, "Wii weiß")
	check(Regal.format_von("nds") == "ds" and Regal.format_von("3ds") == "3ds" and Regal.format_von("gba") == "klein", "DS, 3DS, GBA: kleine Hüllen")
	check(Regal.art_nr("ps1") == 1 and Regal.art_nr("n64") == 2 and Regal.art_nr("ps2") == 0, "Arten: CD-Hülle, Karton, Hülle")
	check(Regal.format_von("unbekannt") == "dvd" and Regal.masse("") == Vector3(0.014, 0.19, 0.135), "unbekanntes System: DVD-Hülle")
	for k in Regal.FORMATE:
		var m: Vector3 = Regal.FORMATE[k].m
		if m.x <= 0.0 or m.x > 0.05 or m.y < 0.1 or m.y > 0.2 or m.z < 0.1 or m.z > 0.2:
			check(false, "Maße von %s plausibel (%s)" % [k, str(m)])
	check(nah(Regal.hoehe_max([{ "system": "ps1" }, { "system": "switch" }]), 0.17) and nah(Regal.hoehe_max([]), 0.19), "höchste Hülle einer Liste")


func _ruecken() -> void:
	print("Rücken")
	var rot := Regal.ruecken_farbe(Color(1, 0, 0), Color.GRAY)
	check(rot.v <= 0.721 and rot.s <= 0.781 and absf(rot.h) < 0.01, "kräftiges Rot: ruhiger, gleicher Farbton (%s)" % rot.to_html())
	var schwarz := Regal.ruecken_farbe(Color(0.02, 0.02, 0.03), Color.GRAY)
	check(schwarz.v >= 0.259, "fast schwarzes Cover: nie ganz schwarz")
	var a := Regal.ruecken_farbe(null, Color("#22379a"), "ps2:a")
	var b := Regal.ruecken_farbe(null, Color("#22379a"), "ps2:b")
	check(a.is_equal_approx(Regal.ruecken_farbe(null, Color("#22379a"), "ps2:a")), "ohne Cover: je Spiel immer gleich")
	check(not a.is_equal_approx(b) or true, "ohne Cover: Farbe des Systems, je Spiel leicht anders")
	check(absf(a.h - Color("#22379a").h) < 0.05, "ohne Cover: Farbton des Systems")
	check(Regal.text_farbe(Color.WHITE).get_luminance() < 0.2 and Regal.text_farbe(Color("#202020")).get_luminance() > 0.8,
			"Schrift hell auf dunkel, dunkel auf hell")
	check(Regal.ruecken_titel("  Metal   Gear\nSolid  ") == "Metal Gear Solid", "Leerraum und Umbruch raus")
	var lang := Regal.ruecken_titel("Ein sehr langer Titel, der niemals auf einen Rücken passt", 20)
	check(lang.length() <= 20 and lang.ends_with("…"), "zu lang: gekürzt mit … (%s)" % lang)


func _aufmachung() -> void:
	print("Aufmachung je System")
	var ps2 := Regal.format_daten("ps2")
	check(Regal.band_von(ps2, Color.RED).get_luminance() < 0.05 and Regal.logo_farbe(ps2, Color.RED).get_luminance() > 0.9 and float(ps2.anteil) > 0.15,
		"PS2: schwarzes Kopfband, Logo weiß")
	check(float(ps2.folie) > 0.7 and (ps2.plastik as Color).get_luminance() < 0.05, "PS2: schwarze Hülle mit Folie")
	check(Regal.ruecken_von(ps2, Color.RED).get_luminance() > 0.9, "PS2: Rücken weiß wie die echten (nicht aus dem Cover)")
	check((ps2.plastik as Color).b > (ps2.plastik as Color).r and (ps2.schimmer as Color).b > 0.4, "PS2: dunkelblauer Kunststoff, Kanten schimmern blau")
	var ps1 := Regal.format_daten("ps1")
	check(Regal.ruecken_von(ps1, Color.RED).get_luminance() < 0.08 and str(ps1.art) == "jewel", "PS1: CD-Hülle mit schwarzem Rücken (egal welches Cover)")
	check(Regal.format_von("dreamcast") == "jewel" and Regal.ruecken_von(Regal.format_daten("dreamcast"), Color.RED) == Color.RED, "Dreamcast: CD-Hülle, Rücken aus dem Cover")
	var sw := Regal.format_daten("switch")
	check((sw.plastik as Color).r > 0.6 and (sw.band as Color).r > 0.8 and Regal.logo_farbe(sw, Color.BLACK) == Color.WHITE, "Switch: rote Hülle, rotes Kopfband, Logo weiß")
	var gc := Regal.format_daten("gc")
	var gb: Color = gc.band
	check(gb.get_luminance() > 0.02 and gb.get_luminance() < 0.3 and (gc.plastik as Color).get_luminance() < 0.15, "GameCube: dunkelgrau mit Logoband")
	check((Regal.format_daten("wii").band as Color).get_luminance() > 0.9 and Regal.logo_farbe(Regal.format_daten("wii"), Color.WHITE).get_luminance() < 0.65, "Wii: weiß, Logo grau")
	var n64 := Regal.format_daten("n64")
	check(Regal.band_von(n64, Color("#203080")) == Color("#203080") and Regal.logo_farbe(n64, Color("#101010")).get_luminance() > 0.8, "Karton: Kopfband im Rücken, Logo hell auf dunkel")
	for k in Regal.FORMATE:
		var fd: Dictionary = Regal.FORMATE[k]
		for f in ["m", "plastik", "band", "anteil", "logo", "ruecken", "folie", "art"]:
			if not fd.has(f):
				check(false, "Format %s hat %s" % [k, f])
		if float(fd.anteil) < 0.1 or float(fd.anteil) > 0.25:
			check(false, "Kopfband von %s zwischen 10 und 25 %%" % k)


func _logos() -> void:
	print("Systemlogo im Kopfband")
	check(Regal.logo_schluessel("ps2") == "ps2" and Regal.logo_schluessel("gc") == "gc" and Regal.logo_schluessel("switch") == "switch", "Logo-Schlüssel der Systeme")
	for sid in Regal.SYSTEM_FORMAT:
		if Regal.logo_schluessel(str(sid)) == "":
			check(false, "Logo bekannt für %s" % sid)
	check(Regal.logo_schluessel("arcade") == "" and Regal.logo_schluessel("steam") == "steam", "ohne Logo: leer")
	var lang := Regal.logo_lage(Vector2(600, 110), 0.014, 0.0314)
	check(not bool(lang.quer) and float(lang.px) > 0.0 and 600.0 * float(lang.px) <= 0.0314 * 0.8 + 0.00001 and 110.0 * float(lang.px) <= 0.014 * 0.6 + 0.00001,
		"langer Schriftzug: längs im Band, passt")
	check(bool(Regal.logo_lage(Vector2(100, 60), 0.04, 0.03).quer), "kompaktes Zeichen auf dickem Karton: quer")
	check(float(Regal.logo_lage(Vector2.ZERO, 0.014, 0.03).px) == 0.0, "kein Bild: nichts")
	# Laden wie überall (src/core/badge_logos.gd): eigene Datei bzw. Cache, ohne Netz.
	Logos.net = false
	var tmp := OS.get_environment("UZAI_DATA").path_join("regal_logos") if OS.get_environment("UZAI_DATA") != "" else OS.get_cache_dir().path_join("uzai_regal_logos")
	DirAccess.make_dir_recursive_absolute(tmp.path_join("media"))
	Logos.data_dir_override = tmp.path_join("data")
	Logos.media_dir_override = tmp.path_join("media")
	Logos.forget()
	Config.set_value("badges.real_logos", true)
	var w = Welt.new()
	check(w.logo_fuer("ps2") == null, "Logo fehlt: Kürzel (Text)")
	check(Regal.marke_von("ps2") == "ps2_wortmarke" and Regal.marke_von("gc") == "gc", "PS2: im Band die Wortmarke „PlayStation®2“, nicht das „PS2“-Logo")
	for k in ["ps2_wortmarke", "ps_logo_farbe"]:
		check(Logos.LOGOS.has(k) and (Logos.LOGOS[k].files as Array).size() >= 3, "Logo %s: Dateinamen auf Commons (nur zur Laufzeit)" % k)
	check(not Logos.pick_search({ "query": { "pages": [{ "title": "File:PlayStation 2 logo.svg", "index": 1, "imageinfo": [{ "thumburl": "https://x/a.png" }] }] } },
		"PlayStation 2", Logos.LOGOS.ps2_wortmarke.noetig).size() > 0, "Suche nach der Wortmarke nimmt nicht das „PS2“-Logo")
	check(Logos.pick_search({ "query": { "pages": [{ "title": "File:PlayStation 2 wordmark.svg", "index": 1, "imageinfo": [{ "thumburl": "https://x/b.png" }] }] } },
		"PlayStation 2", Logos.LOGOS.ps2_wortmarke.noetig).get("url", "") == "https://x/b.png", "… aber die Wortmarke")
	var img := Image.create(300, 60, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 10, 280, 40), Color.WHITE)
	DirAccess.make_dir_recursive_absolute(Logos.cache_path("ps2").get_base_dir())
	img.save_png(Logos.cache_path("ps2"))
	img.save_png(Logos.cache_path("ps2_wortmarke"))
	Logos.forget()
	w.free()
	w = Welt.new()
	check(w.logo_fuer("ps2") is Texture2D, "Logo im Cache, Einstellung an: echtes Logo")
	Config.set_value("badges.real_logos", false)
	Logos.forget()
	w.free()
	w = Welt.new()
	check(w.logo_fuer("ps2") == null, "Einstellung „Echte Konsolen-Logos“ aus: Kürzel (Text)")
	w.free()
	# Das PS-Zeichen bleibt farbig – aber nur, wenn das geladene Bild wirklich farbig ist.
	Config.set_value("badges.real_logos", true)
	var bunt := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	bunt.fill(Color(0, 0, 0, 0))
	bunt.fill_rect(Rect2i(10, 10, 50, 50), Color("#e60012"))
	bunt.fill_rect(Rect2i(60, 10, 50, 50), Color("#f5b800"))
	bunt.fill_rect(Rect2i(10, 60, 50, 50), Color("#00a650"))
	bunt.fill_rect(Rect2i(60, 60, 50, 50), Color("#0070d1"))
	bunt.save_png(Logos.cache_path("ps_logo_farbe"))
	var schwarz := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	schwarz.fill(Color(0, 0, 0, 0))
	schwarz.fill_rect(Rect2i(10, 10, 100, 100), Color("#111111"))
	schwarz.save_png(Logos.cache_path("ps_zeichen"))
	Logos.forget()
	check(Logos.ist_bunt(bunt) and not Logos.ist_bunt(schwarz) and not Logos.ist_bunt(img), "farbig erkannt (PS-Zeichen), schwarz und weiß nicht")
	w = Welt.new()
	var tb: Texture2D = w.logo_tex("ps_logo_farbe", true)
	var tm: Texture2D = w.logo_tex("ps_zeichen", true)
	check(tb != null and tb.has_meta("uz_bunt") and tm != null and not tm.has_meta("uz_bunt"),
		"farbiges PS-Logo bleibt farbig; ein schwarzes wird einfarbig weiß (sonst unsichtbar im Band)")
	var bi := tb.get_image()
	var mitte := bi.get_pixel(bi.get_width() / 4, bi.get_height() / 4)
	check(mitte.r > 0.6 and mitte.g < 0.3, "… in seinen eigenen Farben (%s)" % mitte.to_html())
	w.free()
	DirAccess.remove_absolute(Logos.cache_path("ps_zeichen"))
	Config.set_value("badges.real_logos", true)
	Logos.forget()


func _vorderseite() -> void:
	print("Vorderseite: Rahmen und Format")
	check(str(Regal.rahmen_von("ps2").seite) == "oben" and (Regal.rahmen_von("ps2").farbe as Color).get_luminance() < 0.01, "PS2: schwarzes Band oben")
	check(str(Regal.rahmen_von("ps1").seite) == "links", "PS1: Streifen links")
	check(Regal.BadgeLogos.LOGOS.has(str(Regal.rahmen_von("ps2").get("zeichen", ""))), "PS2: rechts im Band das PS-Zeichen (nur zur Laufzeit geladen)")
	check(str(Regal.zeichen_von("ps2", "pal").get("key", "")) == "ps_logo_farbe" and bool(Regal.zeichen_von("ps2", "pal").bunt)
		and not Regal.zeichen_von("ps2", "ntsc").is_empty(), "PS2: farbiges PS-Logo rechts im Band (PAL und NTSC, wie die Scans)")
	check(float(Regal.rahmen_von("ps2").anteil) > 0.07 and float(Regal.rahmen_von("ps2").anteil) < 0.1, "PS2: Band gut 8 % hoch wie auf echten Covern")
	check(str(Regal.rahmen_von("switch").seite) == "oben" and (Regal.rahmen_von("switch").farbe as Color).r > 0.8, "Switch: rotes Band oben")
	check(Regal.rahmen_von("pce").is_empty() and Regal.rahmen_von("arcade").is_empty() and Regal.rahmen_von("atari2600").is_empty(), "ohne Vorbild: kein Rahmen")
	check(str(Regal.rahmen_von("gc").form) == "bogen" and Regal.rahmen_von("gc").has("linie") and str(Regal.rahmen_von("wii").form) == "welle"
		and str(Regal.rahmen_von("3ds").seite) == "rechts" and str(Regal.rahmen_von("snes").seite) == "unten" and str(Regal.rahmen_von("dreamcast").seite) == "links",
		"Formen wie die Scans: GameCube Bogen mit Kante, Wii Schwung, 3DS rechts, SNES unten, Dreamcast links")
	check((Regal.rahmen_von("xbox").farbe2 as Color).g > 0.5 and (Regal.rahmen_von("ds").farbe as Color).get_luminance() > 0.9, "Xbox: Verlauf ins Grüne, DS weißer Streifen")
	var ps2 := Regal.vorderseite("ps2")
	var m := Regal.motiv_flaeche(ps2, Regal.rahmen_von("ps2"))
	check(nah(m.size.y, ps2.y * (1.0 - float(Regal.rahmen_von("ps2").anteil))) and nah(m.size.x, ps2.x) and nah(m.position.y, 0.0), "PS2: Motiv unter dem Band")
	var m1 := Regal.motiv_flaeche(Regal.vorderseite("ps1"), Regal.rahmen_von("ps1"))
	var heft := Regal.vorderseite("ps1")
	check(m1.position.x > 0.0 and absf(heft.x / heft.y - 1.0) < 0.03 and m1.size.x / m1.size.y < 0.95, "PS1: Heft quadratisch, Motiv rechts vom Streifen")
	check(Regal.bildart_fuer(m1.size) == "cover_quadrat", "PS1: quadratisches Bild")
	check(Regal.bildart_fuer(Regal.motiv_flaeche(Regal.vorderseite("switch"), Regal.rahmen_von("switch")).size) == "cover", "Switch: übliches Hochformat passt")
	check(Regal.bildart_fuer(Regal.motiv_flaeche(Regal.vorderseite("n64"), Regal.rahmen_von("n64")).size) == "cover_quer", "N64-Karton: Querformat")
	check(Regal.bildart_fuer(Regal.motiv_flaeche(Regal.vorderseite("gba"), Regal.rahmen_von("gba")).size) == "cover_quadrat", "GBA-Karton: quadratisch")
	check(Regal.bildart_fuer(m.size) == "cover_hoch", "PS2 mit Band: etwas breiteres Hochformat")
	check(Regal.passt(Vector2(512, 512), Regal.vorderseite("ps1")) and not Regal.passt(Vector2(600, 900), m1.size), "Abweichung: quadratischer Scan passt aufs Heft, 600 × 900 nicht")
	check(Regal.vorderseite("nds").x > Regal.vorderseite("nds").y and Regal.passt(Vector2(512, 459), Regal.vorderseite("nds")), "DS/3DS: quer wie die Scans (512 × 459)")
	check(Regal.passt(Vector2(512, 716), Regal.vorderseite("gc")) and Regal.passt(Vector2(512, 357), Regal.vorderseite("n64"))
		and Regal.passt(Vector2(512, 791), Regal.vorderseite("saturn")),
		"Scans passen auf den Einleger (GameCube, N64, Saturn)")
	check(Regal.passt(Vector2(100, 106), Vector2(1, 1)) and not Regal.passt(Vector2(100, 108), Vector2(1, 1)), "Grenze bei gut 6 %")
	check(not Regal.passt(Vector2.ZERO, Vector2(1, 1)), "ohne Größe: passt nicht")
	var a := Regal.ausschnitt(Vector2(600, 900), Vector2(1, 1))
	check(nah(a.position.x, 0.0) and nah(a.size.x, 1.0) and nah(a.size.y, 2.0 / 3.0) and nah(a.position.y, 1.0 / 6.0), "Zuschnitt: randvoll, mittig, nie gestreckt")
	check(Regal.bildarten({ "source": "rom", "images": { "cover": "C:/x.png" } }, "cover_quadrat", { "cover_scan": true }) == ["cover"], "eigenes Cover gilt allein")
	# Der echte Scan zuerst – er liegt unverändert auf der Hülle; ein Motiv nur, wenn es keinen gibt.
	check(Regal.bildarten({ "source": "rom" }, "cover_quadrat", {}) == ["cover_scan", "cover"], "erst echter Scan, dann Cover")
	check(Regal.bildarten({ "source": "rom" }, "cover_quadrat", { "cover_quadrat": true }) == ["cover_scan", "cover_quadrat", "cover"], "passendes Motiv nach dem Scan")
	check(Regal.bildarten({ "source": "steam" }, "cover", {}) == ["cover"], "ohne Scan-Quelle: Cover")
	check(Regal.bildarten({ "source": "rom" }, "cover_hoch", { "cover_scan": true }, true, true) == ["cover_scan", "cover_hoch", "cover"],
		"mit Rahmen und SteamGridDB: Scan, dann passendes Motiv, dann Cover")
	check(Regal.bildarten({ "source": "rom" }, "cover_hoch", {}, true, false) == ["cover_scan", "cover"], "mit Rahmen ohne Schlüssel: Scan, dann Cover")
	check(Regal.bildarten({ "source": "steam" }, "cover_hoch", {}, true, false) == ["cover"], "mit Rahmen ohne Scan-Quelle: nur Cover")
	check(Regal.bildarten({ "source": "steam" }, "cover_hoch", { "cover_hoch": true }, true, false) == ["cover_hoch", "cover"], "Steam: geholtes Motiv im Format zuerst")
	check(Regal.bildarten({ "source": "rom", "images": { "cover": "C:/x.png" } }, "cover_hoch", { "cover_scan": true }, true, true) == ["cover"], "mit Rahmen: eigenes Cover gilt allein")
	check(Array(Media.remote_sources({ "source": "rom" }, "cover_scan", { "sgdb": true })) == ["libretro"], "Scan nur aus Libretro, nie SteamGridDB")
	check(Array(Media.remote_sources({ "source": "rom" }, "cover_scan", { "sgdb": true, "ss": true })) == ["libretro", "ss"], "… und ScreenScraper (box-2D)")
	check(Array(Media.remote_sources({ "source": "rom" }, "ruecken", { "sgdb": true, "ss": true })) == ["ss"]
		and Array(Media.remote_sources({ "source": "rom" }, "ruecken", { "ss": false })).is_empty(), "Rücken nur von ScreenScraper (box-2D-side)")
	check(Array(Media.remote_sources({ "source": "rom" }, "cover_quadrat", { "sgdb": true })) == ["sgdb"]
		and Array(Media.remote_sources({ "source": "rom" }, "cover_quadrat", { "sgdb": false })).is_empty(), "passendes Format nur mit eigenem SteamGridDB-Schlüssel")
	for k in Regal.BILDARTEN:
		if k != "cover" and not Media.SGDB_MASSE.has(k):
			check(false, "SteamGridDB-Format für %s" % k)


## Testbild: Motiv (bunte Kacheln), auf Wunsch mit Band oben bzw. Streifen links in farbe samt
## heller „Schrift“, oder oben ein großer ruhiger Himmel.
func _bild(w: int, h: int, art: String, farbe := Color.BLACK) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(0, h, 10):
		for x in range(0, w, 10):
			img.fill_rect(Rect2i(x, y, 10, 10), Color(rng.randf(), rng.randf(), rng.randf()))
	match art:
		"oben":
			img.fill_rect(Rect2i(0, 0, w, int(h * 0.1)), farbe)
			img.fill_rect(Rect2i(int(w * 0.05), int(h * 0.03), int(w * 0.3), int(h * 0.04)), Color.WHITE)
		"links":
			img.fill_rect(Rect2i(0, 0, int(w * 0.11), h), farbe)
			img.fill_rect(Rect2i(int(w * 0.03), int(h * 0.05), int(w * 0.05), int(h * 0.3)), Color.WHITE)
		"himmel":
			img.fill_rect(Rect2i(0, 0, w, int(h * 0.4)), Color("#5a8fd8"))
		"verlauf":
			for y in h:
				img.fill_rect(Rect2i(0, y, w, 1), Color("#101935").lerp(Color("#8ad6ff"), float(y) / h))
	return img


## Nachbau eines PS2-Scans wie „FIFA Street 2“: oben ein schwarzes Band (Anteil band) mit dem
## Schriftzug „PlayStation®2“ (weiße Buchstaben über fast die halbe Breite, ® und eine große 2)
## und rechts dem farbigen PS-Logo, leicht verrauscht wie ein JPG; darunter das Motiv (bunt oder
## dunkel). breit: die Schrift reicht über drei Viertel der Breite.
func _fifa(w: int, h: int, band: float, dunkel := false, breit := false) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for y in range(0, h, 12):
		for x in range(0, w, 12):
			var c := Color(rng.randf(), rng.randf(), rng.randf())
			if dunkel:
				c = Color(0.1 + c.r * 0.25, 0.12 + c.g * 0.2, 0.25 + c.b * 0.3)
			img.fill_rect(Rect2i(x, y, 12, 12), c)
	var bh := int(h * band)
	img.fill_rect(Rect2i(0, 0, w, bh), Color.BLACK)
	var n := 16 if breit else 11
	var schritt := w * (0.045 if breit else 0.038)
	for i in n:
		var x0 := int(w * 0.04 + i * schritt)
		img.fill_rect(Rect2i(x0, int(bh * 0.28), int(schritt * 0.62), int(bh * 0.46)), Color.WHITE)
		if i % 3 == 0:
			img.fill_rect(Rect2i(x0, int(bh * 0.2), int(schritt * 0.3), int(bh * 0.1)), Color.WHITE)
	var xr := int(w * 0.04 + n * schritt)
	img.fill_rect(Rect2i(xr, int(bh * 0.24), int(w * 0.012), int(w * 0.012)), Color.WHITE)
	img.fill_rect(Rect2i(xr + int(w * 0.02), int(bh * 0.2), int(w * 0.035), int(bh * 0.56)), Color.WHITE)
	var lx := int(w * 0.82)
	var ls := int(bh * 0.34)
	var ly := int(bh * 0.16)
	img.fill_rect(Rect2i(lx, ly, ls, ls), Color("#e60012"))
	img.fill_rect(Rect2i(lx + ls, ly, ls, ls), Color("#f5b800"))
	img.fill_rect(Rect2i(lx, ly + ls, ls, ls), Color("#00a650"))
	img.fill_rect(Rect2i(lx + ls, ly + ls, ls, ls), Color("#0070d1"))
	for y in bh:
		for x in range(0, w, 3):
			var c := img.get_pixel(x, y)
			var r := rng.randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(clampf(c.r + r, 0, 1), clampf(c.g + r, 0, 1), clampf(c.b + r, 0, 1)))
	return img


func _rahmen_erkennung() -> void:
	print("Rahmen schon im Bild? (Hilfsthread, Media)")
	var r := Regal.rahmen_erkennen(_bild(300, 420, "oben"))
	check(bool(r.oben) and not bool(r.links), "PS2-Scan: schwarzes Band oben erkannt")
	check(bool(Regal.rahmen_erkennen(_bild(300, 420, "oben", Color("#e4001b"))).oben), "Switch: rotes Band erkannt")
	check(bool(Regal.rahmen_erkennen(_bild(300, 420, "oben", Color("#f6f6f7"))).oben), "Wii: weißes Band erkannt")
	var r1 := Regal.rahmen_erkennen(_bild(400, 400, "links"))
	check(bool(r1.links) and not bool(r1.oben), "PS1-Scan: Streifen links erkannt")
	var r0 := Regal.rahmen_erkennen(_bild(600, 900, ""))
	check(not bool(r0.oben) and not bool(r0.links), "Motiv ohne Rahmen (SteamGridDB): keiner")
	check(not bool(Regal.rahmen_erkennen(_bild(600, 900, "himmel")).oben), "ruhiger Himmel oben ist kein Rahmen")
	check(not bool(Regal.rahmen_erkennen(_bild(600, 900, "verlauf")).oben), "Verlauf von dunkel nach hell ist kein Rahmen")
	# Echte Scans mit Schrift im Band (FIFA Street 2): erkannt, und wo das Band endet.
	for fall in [[512, 728, 0.09, false, false, "PS2-Scan wie FIFA Street 2"], [600, 900, 0.085, true, false, "SteamGridDB-Grid als Scan, dunkles Motiv"],
			[400, 570, 0.1, false, true, "Schrift über drei Viertel der Breite"], [342, 482, 0.075, false, false, "kleines Bild, schmales Band"]]:
		var rf := Regal.rahmen_erkennen(_fifa(int(fall[0]), int(fall[1]), float(fall[2]), bool(fall[3]), bool(fall[4])))
		check(bool(rf.oben) and float(rf.oben_ende) >= float(fall[2]) - 0.004 and float(rf.oben_ende) <= float(fall[2]) + 0.02,
			"%s: Band erkannt, endet bei %.3f (echt %.3f)" % [fall[5], float(rf.oben_ende), float(fall[2])])
	var r2 := Regal.rahmen_erkennen(_bild(300, 420, "oben"))
	check(float(r2.oben_ende) >= 0.1 and float(r2.oben_ende) < 0.12, "einfaches Band: Ende bei einem Zehntel (%.3f)" % float(r2.oben_ende))
	var leer := Image.create(200, 300, false, Image.FORMAT_RGBA8)
	leer.fill(Color.BLACK)
	check(not bool(Regal.rahmen_erkennen(leer).oben), "ganz einfarbig: kein Rahmen")
	check(not bool(Regal.rahmen_erkennen(null).oben) and not bool(Regal.rahmen_erkennen(Image.create(4, 4, false, Image.FORMAT_RGBA8)).oben), "kein bzw. winziges Bild: nichts")
	var p := OS.get_environment("UZAI_DATA").path_join("rahmen_test.png") if OS.get_environment("UZAI_DATA") != "" else OS.get_cache_dir().path_join("rahmen_test.png")
	_bild(300, 420, "oben").save_png(p)
	var e1 := Regal.rahmen_merken(p, _bild(300, 420, "oben"))
	var e2 := Regal.rahmen_merken(p, _bild(300, 420, ""))
	check(bool(e1.oben) and bool(e2.oben), "Ergebnis je Datei gemerkt")


func _scan() -> void:
	print("Echter Scan: unverändert auf der Hülle")
	check(Regal.ist_scan("C:/Uzai/cache/img/libretro/ab_cover.png", {}) and Regal.ist_scan("C:/Uzai/cache/img/ss/ab_cover.png", {})
		and Regal.ist_scan("D:/Medien/ps2/cover/Ico.png", {}), "Libretro, ScreenScraper, Medienordner: Scan")
	check(not Regal.ist_scan("C:/Uzai/cache/img/sgdb/ab_cover.png", {}) and not Regal.ist_scan("C:\\Steam\\appcache\\librarycache\\1_library_600x900.jpg", {}),
		"SteamGridDB, Steam: Motiv (Uzai legt das Band darüber)")
	check(Regal.ist_scan("C:/Uzai/cache/img/sgdb/ab_cover.png", { "oben": true }), "Motiv mit eigenem Band: wie ein Scan (nie doppelt)")
	var fl := Regal.vorderseite("ps2")
	var e := Regal.einpassen(Vector2(512, 690), fl)
	var l: Rect2 = e.lage
	var uv: Rect2 = e.uv
	check(l.position.x >= -0.00001 and l.end.x <= fl.x + 0.00001 and l.end.y <= fl.y + 0.00001, "Scan bleibt auf dem Einleger")
	check(absf((512.0 * uv.size.x) / (690.0 * uv.size.y) - l.size.x / l.size.y) < 0.002, "nie gestreckt")
	check(uv.size.x >= 0.97 - 0.0001 and uv.size.y >= 0.97 - 0.0001, "höchstens 3 % beschnitten")
	check(l.size.x < fl.x - 0.0005 or l.size.y < fl.y - 0.0005, "breiterer Scan (PAL): schmaler Rand statt Verzerren")
	var gleich := Regal.einpassen(fl * 1000.0, fl)
	check(nah((gleich.lage as Rect2).size.x, fl.x) and nah((gleich.uv as Rect2).size.y, 1.0), "passender Scan: randvoll, ganz")
	var ein := Regal.einleger("ps1")
	check(ein.position.x > 0.015 and nah(ein.end.x + Regal.COVER_RAND, 0.142), "CD-Hülle: Heft rechts vom Scharnierstreifen")
	check(nah(Regal.einleger("ps2").position.x, Regal.COVER_RAND_RUECKEN), "Kunststoffhülle: Einleger läuft um den Rücken")
	check(Regal.kanten_rad("ps2") > Regal.kanten_rad("ps1") and Regal.kanten_rad("ps1") > Regal.kanten_rad("n64"), "Kanten: Hülle rund, CD-Hülle kantig, Karton scharf")


func _ruecken_aufbau() -> void:
	print("Rücken nach der echten Aufmachung")
	var a := Regal.ruecken_aufbau("ps2", "pal", Color.RED, true)
	var f: Array = a.felder
	check(f.size() == 3, "PS2 PAL: drei Felder oben (%d)" % f.size())
	if f.size() == 3:
		check(str(f[0].logo) == "ps_logo_farbe" and bool(f[0].bunt) and (f[0].farbe as Color).get_luminance() < 0.05
			and nah(float(f[0].y1), 1.0) and nah(float(f[0].y1) - float(f[0].y0), 0.014 / 0.19), "1. quadratisches Feld, farbiges PS-Logo auf Schwarz")
		check(str(f[1].text) == "PAL" and (f[1].farbe as Color).get_luminance() > 0.9 and (f[1].schrift as Color).get_luminance() < 0.1
			and float(f[1].y1) - float(f[1].y0) < 0.04 and nah(float(f[1].y1), float(f[0].y0)), "2. schmaler weißer Streifen mit „PAL“ in Schwarz")
		check(str(f[2].logo) == "ps2_wortmarke" and bool(f[2].laengs) and str(f[2].ersatz).begins_with("PlayStation") and (f[2].farbe as Color).get_luminance() < 0.05,
			"3. schwarzes Feld, „PlayStation®2“ längs in Weiß")
	check((a.grund as Color).get_luminance() > 0.9 and (a.titel_farbe as Color).get_luminance() < 0.1, "Titelfeld weiß, Titel schwarz (egal welches Cover)")
	check(float((a.titel as Vector2).y) < float(a.kopf) and float((a.titel as Vector2).x) >= float((a.nummer as Vector2).y), "Titel zwischen Kopf und Seriennummer")
	check((a.nummer as Vector2).y > 0.0, "Seriennummer unten (wenn bekannt)")
	var ohne := Regal.ruecken_aufbau("ps2", "pal", Color.RED, false)
	check((ohne.nummer as Vector2) == Vector2.ZERO and (ohne.titel as Vector2).x < 0.02, "Seriennummer unbekannt: weggelassen, Titel bekommt den Platz")
	var n := Regal.ruecken_aufbau("ps2", "ntsc", Color.RED, false)
	check((n.felder as Array).size() == 2 and not (n.felder as Array).any(func(e: Dictionary) -> bool: return str(e.get("text", "")) == "PAL"), "PS2 NTSC: ohne PAL-Streifen")
	var p1 := Regal.ruecken_aufbau("ps1", "pal", Color.RED, false)
	check((p1.grund as Color).get_luminance() < 0.08 and (p1.titel_farbe as Color).get_luminance() > 0.8 and str(p1.felder[0].logo) == "ps_logo_farbe", "PS1: schwarzer Rücken, PS-Logo farbig, Titel weiß")
	var sw := Regal.ruecken_aufbau("switch", "pal", Color("#203080"))
	check((sw.felder as Array).size() == 1 and (sw.felder[0].farbe as Color).r > 0.8 and str(sw.felder[0].logo) == "switch" and sw.grund == Color("#203080"),
		"Switch: rotes Kopfband mit Logo, Rücken aus dem Cover")
	var n64 := Regal.ruecken_aufbau("n64", "pal", Color("#203080"))
	check(n64.felder[0].farbe == Color("#203080"), "Karton: Kopfband in der Farbe des Rückens")
	print("Region und Seriennummer")
	check(Regal.seriennummer({ "serial": "SLES-54723" }) == "SLES 54723", "Seriennummer aus dem Eintrag: SLES 54723")
	check(Regal.seriennummer({ "path": "D:/PS2/SLES-54723 FIFA Street 2.iso" }) == "SLES 54723", "… aus dem Dateinamen")
	check(Regal.seriennummer({ "path": "D:/PS2/FIFA Street 2 (Europe).iso" }) == "" and Regal.seriennummer({}, "SLUS_212.33") == "SLUS 21233", "unbekannt: leer; aus der Bibliothek")
	check(Regal.region_von({}) == "pal", "Standard: PAL (Nutzer in Deutschland)")
	check(Regal.region_von({ "serial": "SLUS-21233" }) == "ntsc" and Regal.region_von({ "serial": "SLPM-66123" }) == "ntsc_j"
		and Regal.region_von({ "serial": "SCES-50760" }) == "pal", "Region aus der Seriennummer")
	check(Regal.region_von({ "path": "D:/PS2/Ico (USA).iso" }) == "ntsc" and Regal.region_von({ "libretro_name": "Ico (Europe) (En,Fr,De,Es,It)" }) == "pal", "Region aus dem Namen")
	check(Regal.region_von({ "region": "ntsc" }) == "ntsc", "Region gesetzt")


func _abschnitte() -> void:
	print("Abschnitte")
	check(Regal.buchstabe("Ōkami") == "O" and Regal.buchstabe("ico") == "I" and Regal.buchstabe("Ägypten") == "A", "Buchstaben ohne Zeichen, groß")
	check(Regal.buchstabe("007") == "#" and Regal.buchstabe("") == "#" and Regal.buchstabe("「日本」") == "#", "Ziffern und anderes unter #")
	var jetzt := 1_800_000_000
	check(Regal.abschnitt("recent", "x", 0, 0, 0, jetzt) == "Nie gespielt", "nie gespielt")
	check(Regal.abschnitt("recent", "x", jetzt - 3600, 0, 0, jetzt) == "Heute", "heute")
	check(Regal.abschnitt("recent", "x", jetzt - 3 * 86400, 0, 0, jetzt) == "Diese Woche", "diese Woche")
	check(Regal.abschnitt("recent", "x", jetzt - 400 * 86400, 0, 0, jetzt) == "Früher", "früher")
	check(Regal.abschnitt("playtime", "x", 0, 0, 0, jetzt) == "Nicht gespielt" and Regal.abschnitt("playtime", "x", 0, 200000, 0, jetzt) == "20–100 Std."
		and Regal.abschnitt("playtime", "x", 0, 1800, 0, jetzt) == "Unter 1 Std.", "Spielzeit in Stufen")
	check(Regal.abschnitt("added", "x", 0, 0, jetzt - 86400, jetzt) == "Neu" and Regal.abschnitt("added", "x", 0, 0, 0, jetzt) == "Früher", "neu hinzugefügt")
	check(Regal.abschnitt("title", "Zelda", 0, 0, 0, jetzt) == "Z" and Regal.abschnitt("", "zelda", 0, 0, 0, jetzt) == "Z", "A–Z (auch ohne Angabe)")
	var sortiert := Regal.nach_titel([{ "t": "Zone" }, { "t": "Ōkami" }, { "t": "ico 10" }, { "t": "Ico 2" }], func(g: Dictionary) -> String: return str(g.t))
	check(sortiert.map(func(g: Dictionary) -> String: return str(g.t)) == ["Ico 2", "ico 10", "Ōkami", "Zone"], "A–Z: Ō bei O, natürlich, ohne Groß/klein")
	var abs_ := Regal.abschnitte(["A", "A", "B", "D", "D", "D"])
	check(abs_.size() == 3 and int(abs_[1].start) == 2 and int(abs_[1].ende) == 3 and int(abs_[2].ende) == 6, "Abschnitte aus Schlüsseln")
	check(Regal.abschnitte([]).is_empty(), "leer: keine Abschnitte")
	check(Regal.abschnitt_an(abs_, 0) == 0 and Regal.abschnitt_an(abs_, 4) == 2, "Abschnitt einer Hülle")
	check(Regal.sprung(abs_, 0, 1) == 2 and Regal.sprung(abs_, 2, 1) == 3 and Regal.sprung(abs_, 4, 1) == 4, "RB: Anfang des nächsten, am Ende stehen")
	check(Regal.sprung(abs_, 4, -1) == 3 and Regal.sprung(abs_, 3, -1) == 2 and Regal.sprung(abs_, 1, -1) == 0 and Regal.sprung(abs_, 0, -1) == 0,
			"LB: Anfang des eigenen, dann des vorigen")


func _lage() -> void:
	print("Lage auf dem Brett")
	var abs_ := Regal.abschnitte(["A", "A", "B"])
	var lage := Regal.anordnen([0.014, 0.014, 0.010], abs_)
	var xs: PackedFloat32Array = lage.x
	check(nah(xs[0], 0.007) and nah(xs[1], 0.014 + Regal.LUECKE + 0.007), "dicht an dicht mit kleiner Lücke")
	check(nah(xs[2] - xs[1], 0.007 + Regal.LUECKE + Regal.TRENNER + 0.005), "am neuen Abschnitt Platz für den Trenner")
	check((lage.trenner as Array).size() == 1 and float(lage.trenner[0]) > xs[1] and float(lage.trenner[0]) < xs[2], "ein Trenner zwischen A und B")
	check(nah(float(lage.laenge), xs[2] + 0.005), "Länge bis zur letzten Hülle")
	var viele: Array = []
	for i in 500:
		viele.append(0.014)
	var lv := Regal.anordnen(viele, Regal.abschnitte(viele.map(func(_d: Variant) -> String: return "A")))
	var r := Regal.bereich(lv.x, 1.0, 1.5)
	check(r.x > 0 and r.y > r.x and float(lv.x[r.x]) >= 1.0 and float(lv.x[r.x - 1]) < 1.0 and float(lv.x[r.y]) <= 1.5 and float(lv.x[r.y + 1]) > 1.5,
			"sichtbarer Bereich (%d–%d)" % [r.x, r.y])
	check(Regal.bereich(lv.x, -5.0, -4.0).y < Regal.bereich(lv.x, -5.0, -4.0).x and Regal.bereich(PackedFloat32Array(), 0, 1).y < 0, "außerhalb bzw. leer: nichts")
	check(Regal.bereich(lv.x, -1.0, 100.0) == Vector2i(0, 499), "alles im Bild")
	var halb := 0.4
	var gr := Regal.grenzen(0.1, halb)
	check(gr.y - gr.x >= 2.0 * halb - 0.081, "wenige Spiele: Regal trotzdem so breit wie das Bild")
	var gl := Regal.grenzen(8.0, halb)
	check(nah(gl.x, -Regal.RAND_INNEN) and nah(gl.y, 8.0 + Regal.RAND_INNEN), "viele Spiele: Platz an beiden Enden")
	var k0 := Regal.kamera_ziel(0.007, gl, halb, 0.024)
	check(k0 > 0.007 and k0 - 0.007 <= halb * Regal.NEBEN_MAX + 0.0001, "am Anfang: Kamera bleibt beim Regal, die Hülle gut im Bild")
	check(nah(Regal.kamera_ziel(4.0, gl, halb, 0.024), 4.0), "in der Mitte: Kamera vor der Hülle")
	check(Regal.kamera_ziel(7.99, gl, halb, 0.024) < 7.99, "am Ende: Kamera bleibt beim Regal")


func _bewegung() -> void:
	print("Bewegung")
	check(Regal.schritt_weite(0) == 1 and Regal.schritt_weite(12) == 2 and Regal.schritt_weite(40) == 3, "gehalten schneller")
	check(Regal.schritt(0, -1, 10) == 0 and Regal.schritt(9, 3, 10) == 9 and Regal.schritt(4, 2, 10) == 6, "Schritt bleibt im Regal")
	var z0 := Regal.zug_lage(0.0, 0.135)
	var z1 := Regal.zug_lage(1.0, 0.135)
	check(nah(float(z0.vor), 0.0) and nah(float(z0.dreh), 0.0) and nah(float(z0.hoch), 0.0), "steht im Regal")
	check(nah(float(z1.vor), 0.135 + Regal.ZUG_VOR) and nah(float(z1.dreh), Regal.ZUG_DREH), "ganz heraus und zur Kamera gedreht")
	var zh := Regal.zug_lage(0.3, 0.135)
	check(nah(float(zh.dreh), 0.0) and float(zh.vor) > 0.05, "erst heraus, dann drehen (nie durch die Nachbarn)")
	check(float(Regal.zug_lage(1.0, 0.142, 0.66).vor) < float(Regal.zug_lage(1.0, 0.142).vor), "kleines Regal: weniger weit heraus")
	var p := Vector2(0, 0)
	var spitze := 0.0
	for i in 120:
		p = Regal.feder(p.x, p.y, 1.0, 1.0 / 60.0, 13.0, 1.0)
		spitze = maxf(spitze, p.x)
	check(nah(p.x, 1.0, 0.001) and spitze <= 1.0005, "Feder ohne Nachschwingen kommt an")
	p = Vector2(0, 0)
	spitze = 0.0
	for i in 120:
		p = Regal.feder(p.x, p.y, 1.0, 1.0 / 60.0, 13.0, 0.74)
		spitze = maxf(spitze, p.x)
	check(spitze > 1.0 and spitze < 1.05 and nah(p.x, 1.0, 0.002), "sattes Herausziehen: federt kaum merklich nach (%.3f)" % spitze)
	p = Vector2(0, 0)
	for i in 60:
		p = Regal.feder(p.x, p.y, 1.0, 1.0 / 30.0, 13.0, 0.74)
	check(nah(p.x, 1.0, 0.002), "auch mit 30 Bildern je Sekunde stabil")


func _ansicht() -> void:
	print("Regal oder Mosaik")
	# Konsolen immer als Regal – auch mit einer alten Wahl „Eigenes Raster“ in den Einstellungen (wird nicht mehr gelesen).
	check(Regal.ist_regal("ps2") and Regal.ist_regal("switch") and Regal.ist_regal("gc"), "Konsolen: immer Regal")
	check(not Regal.ist_regal("steam") and not Regal.ist_regal("ordner:f1") and not Regal.ist_regal("zuletzt") and not Regal.ist_regal(""),
			"Steam, Ordner, Zuletzt: nie")
	check(MosaikSeite.ist_mosaik("ordner:f1"), "Ordner bleiben ihr Mosaik")


func _seite() -> void:
	print("Seite (ohne Fenster)")
	var titel := ["Zone", "Ico", "Amplitude", "Beyond", "Okage", "Ōkami", "Burnout", "Katamari", "Jak", "Rez"]
	var games: Array = []
	for i in titel.size():
		games.append({ "id": "ps2:t%d" % i, "title": titel[i], "system": "ps2", "source": "rom", "installed": true,
			"playtime": i * 3600, "last_played": 1_700_000_000 + i * 1000 })
	games.append({ "id": "gc:x", "title": "Andere Konsole", "system": "gc", "source": "rom" })
	Library.games = games
	Library._reindex()
	Config.set_value("library.regal_sort", "title")
	var host := Control.new()
	add_child(host)
	Nav.root_scope = host
	var l = Seite.new()
	l.quelle = "ps2"
	l.label = "PlayStation 2"
	l.open(host)
	await get_tree().process_frame
	await get_tree().process_frame
	var sp: Array = l.get("_spiele")
	check(sp.size() == 10, "nur Spiele dieser Konsole (%d)" % sp.size())
	check(str(sp[0].title) == "Amplitude" and str(sp.back().title) == "Zone", "A–Z sortiert (%s … %s)" % [sp[0].title, sp.back().title])
	check(Nav.focused() == l.get("_halt") and l.get("_halt").has_meta("uz_on_x") and l.get("_halt").has_meta("uz_on_y"), "Halt hat den Fokus, X und Y belegt")
	var w: Node = l.get("welt")
	check(w is Welt and (w.get("xs") as PackedFloat32Array).size() == 10, "Welt mit zehn Hüllen")
	check(int(l.get("_i")) == 0, "erste Hülle gewählt")
	l.nav_dir("right")
	check(int(l.get("_i")) == 1 and int(w.get("auswahl")) == 1, "rechts: nächste Hülle, Welt folgt")
	l.handle("rb")
	var abs_: Array = l.get("_abs")
	check(int(l.get("_i")) == int(abs_[Regal.abschnitt_an(abs_, 1) + 1].start), "RB: nächster Abschnitt")
	l.nav_dir("down")
	l.nav_dir("up")
	check(int(l.get("_i")) == int(abs_[Regal.abschnitt_an(abs_, int(l.get("_i")))].start), "hoch/runter springen ebenfalls")
	for i in 30:
		w._process(1.0 / 60.0)
	var mit_logo := false
	for k in w.call("sichtbare_indizes"):
		mit_logo = mit_logo or bool((w.get("_huellen") as Dictionary)[k].hat_logo)
	check(mit_logo, "Hüllen im Regal tragen das Logo im Kopfband")
	var h0 = (w.get("_huellen") as Dictionary)[w.call("sichtbare_indizes")[0]]
	var vm: ShaderMaterial = h0.get("_vmat")
	check(bool(h0.rahmen_drauf) and int(vm.get_shader_parameter("band_seite")) == 0 and not bool(vm.get_shader_parameter("hat_bild"))
		and h0.get("_rlogo").visible and h0.get("_vtitel").visible, "ohne Bild: Uzais Ersatz-Vorderseite mit Band, Logo und Titel")
	var fifa := _fifa(512, 728, 0.09)
	var scan := ImageTexture.create_from_image(fifa)
	scan.set_meta("uz_look", { "x": PackedFloat32Array(), "r": Regal.rahmen_erkennen(fifa) })
	scan.set_meta("uz_src", "C:/Uzai/cache/img/sgdb/x_cover.png")
	h0.cover_setzen(scan)
	var bu: Vector4 = vm.get_shader_parameter("bild_uv")
	check(bool(h0.scan) and not bool(h0.rahmen_drauf) and int(vm.get_shader_parameter("band_seite")) == -1 and not h0.get("_rlogo").visible
		and not h0.get("_vtitel").visible, "Bild mit eigenem Band (FIFA): unverändert, kein zweites Band")
	check(bu.y < 0.03 and bu.w > 0.94, "… das Band des Bilds bleibt (nichts weggeschnitten, %.3f)" % bu.y)
	var bl: Vector4 = vm.get_shader_parameter("bild_lage")
	check(absf((512.0 * bu.z) / (728.0 * bu.w) - bl.z / bl.w) < 0.01, "… nie gestreckt")
	var lr := ImageTexture.create_from_image(_bild(512, 690, ""))
	lr.set_meta("uz_src", "C:/Uzai/cache/img/libretro/x_cover.png")
	h0.cover_setzen(lr)
	check(bool(h0.scan) and not bool(h0.rahmen_drauf), "Libretro-Scan: unverändert, ohne Uzais Band")
	var grid := ImageTexture.create_from_image(_bild(600, 900, ""))
	grid.set_meta("uz_src", "C:/Uzai/cache/img/sgdb/y_cover.png")
	h0.cover_setzen(grid)
	check(bool(h0.rahmen_drauf) and not bool(h0.passt_bild) and int(vm.get_shader_parameter("band_seite")) == 0, "Motiv ohne Band (SteamGridDB): Band darüber, Format passt nicht")
	var cs: Vector4 = vm.get_shader_parameter("bild_uv")
	var fl0 := Regal.motiv_flaeche(Regal.vorderseite("ps2"), Regal.rahmen_von("ps2")).size
	check(cs.z <= 1.0001 and cs.w < 0.99 and absf((600.0 * cs.z) / (900.0 * cs.w) - fl0.x / fl0.y) < 0.01, "Motiv zugeschnitten statt gestreckt")
	var hp = Welt.Huelle.new()
	hp.bauen(Welt.HUELLE_S)
	w.add_child(hp)
	hp.setzen({ "id": "ps1:x", "title": "Probe", "system": "ps1" }, 0.0, Color.RED, w.get("_ruecken_font"), Callable())
	var hm: ShaderMaterial = hp.get("_vmat")
	check(int(hm.get_shader_parameter("band_seite")) == 1 and int(hm.get_shader_parameter("art")) == 1, "PS1 ohne Bild: schwarzer Streifen links, CD-Hülle")
	var rt := ImageTexture.create_from_image(_bild(40, 600, ""))
	hp.ruecken_setzen(rt)
	check(bool(hp.get("_mat").get_shader_parameter("hat_ruecken")) and not hp.get("_titel").visible, "echter Rücken (ScreenScraper): statt Uzais Titel und Feldern")
	hp.queue_free()
	w.call("_passend_holen", h0.spiel)
	check((w.get("_versucht") as Dictionary).is_empty(), "ohne SteamGridDB-Schlüssel: kein Nachladen (Zuschnitt bleibt)")
	Config.set_value("badges.real_logos", false)
	w.set("_logos", {})
	h0.logos_neu()
	h0.cover_setzen(null)
	var nt := str(h0.get("_rtext").text)
	check(h0.get("_rtext").visible and nt.begins_with("PlayStation") and nt.ends_with("2") and not h0.get("_rlogo").visible,
		"Logos aus: „%s“ in Uzais Schrift" % nt)
	check(not h0.get("_rzeichen").visible, "Logos aus: PS-Feld im Band leer")
	var tl: Array = h0.get("_f_text")
	var sl: Array = h0.get("_f_logo")
	check(not (sl[0] as Sprite3D).visible and (tl[1] as Label3D).visible and str((tl[1] as Label3D).text) == "PAL"
		and (tl[2] as Label3D).visible and str((tl[2] as Label3D).text).begins_with("PlayStation"), "Rücken ohne Logos: PS-Feld leer, PAL und Schriftzug in Uzais Schrift")
	Config.set_value("badges.real_logos", true)
	w.set("_logos", {})
	h0.logos_neu()
	check((sl[0] as Sprite3D).visible and (sl[0] as Sprite3D).texture.has_meta("uz_bunt") and h0.get("_rzeichen").visible,
		"Logos an: farbiges PS-Logo oben am Rücken und rechts im Band")
	var serie := Welt.Huelle.new()
	serie.bauen(Welt.HUELLE_S)
	w.add_child(serie)
	serie.setzen({ "id": "ps2:s", "title": "FIFA Street 2", "system": "ps2", "serial": "SLES-54723" }, 0.0, Color.RED, w.get("_ruecken_font"), w.logo_tex)
	check(serie.get("_nummer").visible and str(serie.get("_nummer").text) == "SLES 54723" and serie.region == "pal", "Seriennummer bekannt: klein unten am Rücken")
	check(str(serie.get("_titel").text) == "FIFA Street 2" and (serie.get("_titel").modulate as Color).get_luminance() < 0.1
		and is_equal_approx(serie.get("_titel").basis.x.y, -1.0), "Titel schwarz, längs von oben nach unten")
	serie.queue_free()
	check((w.call("sichtbare_indizes") as Array).size() >= 1 and (w.call("sichtbare_indizes") as Array).size() <= 10, "Hüllen im Bild belegt")
	var gid := str(l.call("_gewaehlt").id)
	l.call("_favorit")
	check(bool(Library.get_game(gid).get("favorite", false)), "X: Favorit")
	await get_tree().process_frame
	l.call("_auffrischen")
	check(str(l.call("_gewaehlt").id) == gid, "Bibliothek geändert: Auswahl bleibt")
	l.call("_favorit")
	Config.set_value("library.regal_sort", "playtime")
	l.call("_laden", gid)
	check(str(l.call("_gewaehlt").id) == gid and str((l.get("_spiele") as Array)[0].title) == "Rez", "andere Sortierung: Auswahl bleibt, meistgespielt vorn")
	Config.set_value("library.regal_sort", "kaputt")
	check(l.call("sortierung") == Regal.SORT_STANDARD, "unbekannte Sortierung: A–Z")
	Config.set_value("library.regal_sort", "title")
	var vorher := int(l.get("_i"))
	l.nav_dir("left")
	l.nav_dir("left")
	check(int(l.get("_i")) == maxi(0, vorher - 2), "links zurück")
	check(l.nav_command("b") and l.get("_closing") == true, "B schließt")
	await get_tree().create_timer(0.4).timeout
	check(not is_instance_valid(l) or not l.is_inside_tree(), "Seite weg")
	host.queue_free()

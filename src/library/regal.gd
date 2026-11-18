extends RefCounted
## Regal einer Konsole (A auf PS2 in der Quellen-Zeile): die Spiele als echte Hüllen auf einem
## Brett, Rücken nach vorn. Hier steht nur die Logik ohne Oberfläche (getestet in
## tests/logic_regal.gd): Hüllenformat und Maße je System, Farbe und Text des Rückens, Sortierung
## und Abschnitte (A–Z, zuletzt gespielt, Spielzeit, neu), Lage jeder Hülle auf dem Brett, welche
## Hüllen gerade zu sehen sind, Schritte beim Blättern und die Bewegung beim Herausziehen.
## Bild und Bedienung: src/ui/layers/regal_seite.gd mit der 3D-Welt src/room/regal_welt.gd.
##
## Maße in Metern, wie die echten Hüllen: x Dicke (der Rücken), y Höhe, z Tiefe (Breite des Covers).

## Formate nach der echten Aufmachung (nur Form, Farbe und Anordnung – keine fremde Grafik). Maße
## der europäischen bzw. nordamerikanischen Hüllen (Breite × Höhe × Dicke): DVD-Hülle 135 × 190 × 14
## (PS2, GameCube, Wii, Wii U, Xbox, Xbox 360), Blu-ray 135 × 171 (PS3), UMD 104 × 177 (PSP),
## Switch 105 × 170 × 11, DS/3DS 137 × 125 (quer, wie die Scans), CD-Hülle 142 × 125 × 10 (PS1,
## Dreamcast, PC Engine),
## Saturn lange CD-Hülle 142 × 200, Mega Drive/Master System Klappbox 135 × 190 × 24,
## Modul-Karton quer 178 × 127 (N64, SNES), NES 127 × 178, Atari 2600 146 × 197, Game Boy 120 × 120.
##   m        Maße (Dicke, Höhe, Tiefe)
##   plastik  Farbe der Hülle (Seiten, Ränder)
##   band     Kopfband oben am Rücken (null: in der Farbe des Rückens, wie bei Kartons)
##   anteil   Höhe des Kopfbands am Rücken
##   logo     Farbe des Systemlogos bzw. des Kürzels im Kopfband
##   ruecken  feste Farbe des Rückens (null: aus dem Cover) – PS1: schwarzer Rücken
##   folie    Folie über dem Rücken (Glanz), 0 … 1
##   art      huelle (Kunststoffhülle), jewel (CD-Hülle aus klarem Kunststoff), karton (bedruckt, matt)
##   schimmer Farbe, in der die Kanten oben und unten schimmern (PS2: dunkelblauer Kunststoff,
##            PS3: rauchschwarz mit blauem Schein); ohne: wie die Hülle
##   schale   CD-Hülle: Farbe der Schale unter dem klaren Kunststoff (PS1, Saturn schwarz)
##   klar     Kunststoff durchscheinend (DS, 3DS, PS3): heller Glanz, weicher Schein
## Das echte Systemlogo im Kopfband kommt nur zur Laufzeit (src/core/badge_logos.gd, R4); ohne
## Logo steht dort das Kürzel des Systems.
const FORMATE := {
	"dvd": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#121214"), "band": Color("#0c0c0e"), "anteil": 0.12,
		"logo": Color("#e6e6e9"), "ruecken": null, "folie": 0.4, "art": "huelle" },
	"ps2": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#080a14"), "band": Color("#050506"), "anteil": 0.165,
		"logo": Color("#f2f2f4"), "ruecken": Color("#f3f3f1"), "folie": 0.85, "art": "huelle", "schimmer": Color("#2b4790") },
	"gc": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#141417"), "band": Color("#0c0c0e"), "anteil": 0.15,
		"logo": Color("#e4e4e8"), "ruecken": null, "folie": 0.6, "art": "huelle" },
	"wii": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#ececef"), "band": Color("#f7f7f8"), "anteil": 0.13,
		"logo": Color("#8d9096"), "ruecken": null, "folie": 0.6, "art": "huelle" },
	"wiiu": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#2a8fbf"), "band": Color("#1b8fc6"), "anteil": 0.14,
		"logo": Color("#ffffff"), "ruecken": null, "folie": 0.6, "art": "huelle" },
	"xbox": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#121413"), "band": Color("#3f8f2a"), "anteil": 0.13,
		"logo": Color("#f2f7ee"), "ruecken": null, "folie": 0.5, "art": "huelle" },
	"xbox360": { "m": Vector3(0.014, 0.190, 0.135), "plastik": Color("#5aa12f"), "band": Color("#eceeea"), "anteil": 0.13,
		"logo": Color("#63675f"), "ruecken": null, "folie": 0.5, "art": "huelle", "schimmer": Color("#8fd45a") },
	"ps3": { "m": Vector3(0.014, 0.171, 0.135), "plastik": Color("#14161c"), "band": Color("#0b0b0d"), "anteil": 0.14,
		"logo": Color("#f0f0f2"), "ruecken": null, "folie": 0.7, "art": "huelle", "schimmer": Color("#34486e"), "klar": true },
	"psp": { "m": Vector3(0.014, 0.177, 0.104), "plastik": Color("#18191d"), "band": Color("#0f0f12"), "anteil": 0.14,
		"logo": Color("#ededf0"), "ruecken": null, "folie": 0.6, "art": "huelle" },
	"md": { "m": Vector3(0.024, 0.190, 0.135), "plastik": Color("#141415"), "band": Color("#0f0f10"), "anteil": 0.14,
		"logo": Color("#e9e9ea"), "ruecken": null, "folie": 0.4, "art": "huelle" },
	"sms": { "m": Vector3(0.024, 0.190, 0.135), "plastik": Color("#141415"), "band": Color("#f3f3f1"), "anteil": 0.14,
		"logo": Color("#1a1a1c"), "ruecken": null, "folie": 0.4, "art": "huelle" },
	"ps1": { "m": Vector3(0.010, 0.125, 0.142), "plastik": Color("#c9cdd3"), "band": Color("#050506"), "anteil": 0.2,
		"logo": Color("#f2f2f2"), "ruecken": Color("#0d0d0f"), "folie": 0.0, "art": "jewel", "schale": Color("#070708") },
	"jewel": { "m": Vector3(0.010, 0.125, 0.142), "plastik": Color("#c3c8cf"), "band": Color("#101012"), "anteil": 0.16,
		"logo": Color("#eeeeee"), "ruecken": null, "folie": 0.0, "art": "jewel", "schale": Color("#0c0c0e") },
	"saturn": { "m": Vector3(0.015, 0.199, 0.142), "plastik": Color("#c3c8cf"), "band": Color("#101012"), "anteil": 0.12,
		"logo": Color("#eeeeee"), "ruecken": null, "folie": 0.0, "art": "jewel", "schale": Color("#0a0a0b") },
	"switch": { "m": Vector3(0.011, 0.170, 0.105), "plastik": Color("#c8171f"), "band": Color("#e4001b"), "anteil": 0.15,
		"logo": Color("#ffffff"), "ruecken": null, "folie": 0.5, "art": "huelle" },
	"ds": { "m": Vector3(0.014, 0.125, 0.137), "plastik": Color("#d9dce1"), "band": Color("#f4f4f6"), "anteil": 0.14,
		"logo": Color("#6d7077"), "ruecken": null, "folie": 0.5, "art": "huelle", "klar": true },
	"3ds": { "m": Vector3(0.014, 0.125, 0.137), "plastik": Color("#eceef1"), "band": Color("#f7f7f8"), "anteil": 0.14,
		"logo": Color("#c4202e"), "ruecken": null, "folie": 0.5, "art": "huelle", "klar": true },
	"klein": { "m": Vector3(0.030, 0.120, 0.120), "plastik": Color("#d8d2c4"), "band": null, "anteil": 0.18,
		"logo": Color(0, 0, 0, 0), "ruecken": null, "folie": 0.0, "art": "karton" },
	"modul": { "m": Vector3(0.040, 0.127, 0.178), "plastik": Color("#d8d2c4"), "band": null, "anteil": 0.18,
		"logo": Color(0, 0, 0, 0), "ruecken": null, "folie": 0.0, "art": "karton" },
	"karton": { "m": Vector3(0.030, 0.178, 0.127), "plastik": Color("#d8d2c4"), "band": null, "anteil": 0.16,
		"logo": Color(0, 0, 0, 0), "ruecken": null, "folie": 0.0, "art": "karton" },
	"atari": { "m": Vector3(0.032, 0.197, 0.146), "plastik": Color("#d8d2c4"), "band": null, "anteil": 0.14,
		"logo": Color(0, 0, 0, 0), "ruecken": null, "folie": 0.0, "art": "karton" },
}

## System → Format (alles andere: DVD-Hülle).
const SYSTEM_FORMAT := {
	"ps2": "ps2", "gc": "gc", "wii": "wii", "wiiu": "wiiu", "xbox": "xbox", "xbox360": "xbox360", "ps3": "ps3",
	"psp": "psp", "megadrive": "md", "mastersystem": "sms",
	"ps1": "ps1", "dreamcast": "jewel", "saturn": "saturn", "pce": "jewel",
	"switch": "switch", "nds": "ds", "3ds": "3ds",
	"gba": "klein", "gb": "klein", "gbc": "klein", "gamegear": "klein",
	"n64": "modul", "snes": "modul",
	"nes": "karton", "atari2600": "atari",
}

const ARTEN := { "huelle": 0, "jewel": 1, "karton": 2 }
const BadgeLogos := preload("res://src/core/badge_logos.gd")
const DiscSerial := preload("res://src/library/disc_serial.gd")

## Sortierungen des Regals (Library.sorted versteht dieselben Kennungen).
const SORTEN := [["title", "A–Z"], ["recent", "Zuletzt gespielt"], ["playtime", "Spielzeit"], ["added", "Neu hinzugefügt"]]
const SORT_STANDARD := "title"

## Abstand zwischen zwei Hüllen und an einer Abschnittsgrenze (dort steht ein Trenner).
const LUECKE := 0.0016
const TRENNER := 0.014
## Platz zwischen Seitenwand und erster bzw. letzter Hülle (dort dreht sich die herausgezogene).
const RAND_INNEN := 0.085
const NEBEN_MAX := 0.4
## Herausziehen: so weit nach vorn (über die Tiefe der Hülle hinaus), so hoch und so weit gedreht.
const ZUG_VOR := 0.1
const ZUG_HOCH := 0.014
const ZUG_DREH := -78.0

## Buchstaben mit Zeichen → Grundbuchstabe (für die Abschnitte A–Z).
const GRUND := {
	"À": "A", "Á": "A", "Â": "A", "Ã": "A", "Ä": "A", "Å": "A", "Ā": "A", "Æ": "A",
	"Ç": "C", "Č": "C", "È": "E", "É": "E", "Ê": "E", "Ë": "E", "Ē": "E",
	"Ì": "I", "Í": "I", "Î": "I", "Ï": "I", "Ī": "I", "Ñ": "N",
	"Ò": "O", "Ó": "O", "Ô": "O", "Õ": "O", "Ö": "O", "Ō": "O", "Ø": "O", "Œ": "O",
	"Š": "S", "Ś": "S", "Ù": "U", "Ú": "U", "Û": "U", "Ü": "U", "Ū": "U", "Ý": "Y", "Ž": "Z", "Ż": "Z",
}


# --- Regal oder Mosaik -------------------------------------------------------------------------------

## Eine Konsole (System mit Daten, nicht Steam, Epic, EA oder PC, kein Ordner)?
static func ist_konsole(sub_id: String) -> bool:
	if sub_id == "" or sub_id.begins_with("ordner:") or sub_id in ["steam", "epic", "ea", "pc"]:
		return false
	return not Config.system(sub_id).is_empty()


## A console always opens as a shelf – the grid options „Eigenes Raster“ (mosaic) and „Als Liste“ no longer exist
## for consoles. Old settings (library.konsolen_ansicht, library.ansicht) are ignored. Folders keep their mosaic.
static func ist_regal(sub_id: String) -> bool:
	return ist_konsole(sub_id)


# --- Format ------------------------------------------------------------------------------------------

static func format_von(system_id: String) -> String:
	return str(SYSTEM_FORMAT.get(system_id, "dvd"))


static func format_daten(system_id: String) -> Dictionary:
	return FORMATE[format_von(system_id)]


## Maße der Hülle (Dicke, Höhe, Tiefe) in Metern.
static func masse(system_id: String) -> Vector3:
	return format_daten(system_id).m


## Rundung der Kanten (m): Kunststoffhülle weich gerundet, CD-Hülle kantig, Karton fast scharf.
static func kanten_rad(system_id: String) -> float:
	match str(format_daten(system_id).art):
		"jewel":
			return 0.0009
		"karton":
			return 0.0007
	return 0.0028


static func art_nr(system_id: String) -> int:
	return int(ARTEN.get(str(format_daten(system_id).art), 0))


## Die höchste Hülle einer Liste (Brett und Kamera richten sich danach).
static func hoehe_max(list: Array) -> float:
	var h := 0.0
	for g in list:
		h = maxf(h, masse(str((g as Dictionary).get("system", ""))).y)
	return h if h > 0.0 else 0.19


# --- Aufmachung -------------------------------------------------------------------------------------

## Farbe des Rückens: fest nach Format (PS1 schwarz), sonst die aus dem Cover.
static func ruecken_von(fd: Dictionary, aus_cover: Color) -> Color:
	var r: Variant = fd.get("ruecken")
	return r if r is Color else aus_cover


## Farbe des Kopfbands (Kartons: wie der Rücken, ohne Kante).
static func band_von(fd: Dictionary, ruecken: Color) -> Color:
	var b: Variant = fd.get("band")
	return b if b is Color else ruecken


## Farbe von Logo bzw. Kürzel im Kopfband (Kartons: hell oder dunkel nach dem Rücken).
static func logo_farbe(fd: Dictionary, ruecken: Color) -> Color:
	var c: Color = fd.get("logo", Color(0, 0, 0, 0))
	return c if c.a > 0.0 else text_farbe(ruecken)


## Logo-Schlüssel des Systems für src/core/badge_logos.gd ("" = keins, dann das Kürzel).
static func logo_schluessel(system_id: String) -> String:
	return BadgeLogos.source_key(system_id) if BadgeLogos.LOGOS.has(BadgeLogos.source_key(system_id)) else ""


## Lage des Logos im Kopfband (Bild bild_px groß, Rücken dicke breit, Band band_h hoch, alles in
## Metern bzw. Bildpunkten): längs gelesen wie der Titel (lange Schriftzüge wie „PlayStation 2“)
## oder quer (kompakte Zeichen auf dicken Rücken) – je nachdem, wo es größer wird.
## { quer, px (Meter je Bildpunkt) }; px 0: passt nicht.
static func logo_lage(bild_px: Vector2, dicke: float, band_h: float) -> Dictionary:
	if bild_px.x < 1.0 or bild_px.y < 1.0 or dicke <= 0.0 or band_h <= 0.0:
		return { "quer": false, "px": 0.0 }
	var laengs := minf(band_h * 0.8 / bild_px.x, dicke * 0.6 / bild_px.y)
	var quer := minf(dicke * 0.78 / bild_px.x, band_h * 0.62 / bild_px.y)
	return { "quer": quer > laengs * 1.15, "px": maxf(laengs, quer) }


## Rücken nach der echten Verpackung, von oben nach unten (nur Form, Farbe und Anordnung; die Logos
## kommen zur Laufzeit, badge_logos.gd). Je Feld: h (Anteil der Höhe, "quadrat": so hoch wie der
## Rücken dick ist), farbe, logo (Schlüssel), bunt (Logo in seinen eigenen Farben, sonst einfarbig in
## schrift), logo_ersatz (anderes Logo, wenn das erste fehlt), ersatz (Text in Uzais Schrift ohne
## Logo), text (fester Text, z. B. „PAL“), schrift (Farbe von Logo bzw. Text), laengs (längs
## gelesen, von oben nach unten), nur (nur in dieser Region). grund: Farbe des Titelfelds (null:
## aus dem Cover), titel: Farbe des Titels (null: nach dem Grund), nummer: Platz für die
## Seriennummer unten (nur wenn Uzai sie kennt).
## Ohne Eintrag: ein Kopfband nach FORMATE (anteil, band, logo) und der Rücken aus dem Cover.
##   PS2 PAL: oben ein quadratisches Feld mit dem farbigen PS-Logo auf Schwarz, ein weißer Streifen
##   mit „PAL“, ein schwarzes Feld mit „PlayStation®2“ längs in Weiß, darunter weiß mit dem Titel
##   schwarz und fett, ganz unten klein die Seriennummer (SLES 54723). NTSC ohne den PAL-Streifen.
##   PS1: schwarzer Rücken, oben das farbige PS-Logo, Titel weiß, unten die Seriennummer.
const RUECKEN := {
	"ps2": { "felder": [
		{ "h": "quadrat", "farbe": Color("#050506"), "logo": "ps_logo_farbe", "bunt": true, "logo_ersatz": "ps_zeichen", "schrift": Color("#ffffff") },
		{ "h": 0.027, "farbe": Color("#f3f3f1"), "text": "PAL", "schrift": Color("#0c0c0e"), "nur": "pal" },
		{ "h": 0.205, "farbe": Color("#050506"), "logo": "ps2_wortmarke", "ersatz": "PlayStation®2", "schrift": Color("#ffffff"), "laengs": true },
	], "grund": Color("#f3f3f1"), "titel": Color("#0c0c0e"), "nummer": true },
	"ps1": { "felder": [
		{ "h": "quadrat", "farbe": Color("#0d0d0f"), "logo": "ps_logo_farbe", "bunt": true, "logo_ersatz": "ps1", "schrift": Color("#ffffff") },
	], "grund": Color("#0d0d0f"), "titel": Color("#f3f2ef"), "nummer": true },
}
## Höhe des Felds für die Seriennummer unten (Anteil der Höhe).
const NUMMER_ANTEIL := 0.05


## Region eines Spiels für die Aufmachung: „pal“ (Standard, Europa), „ntsc“ (Nordamerika) oder
## „ntsc_j“ (Japan) – aus einer gesetzten Region, der Seriennummer (SLES/SCES … Europa, SLUS/SCUS
## Nordamerika, SLPS/SLPM/SCPS Japan) oder dem Namen („(Europe)“, „(USA)“, „(Japan)“).
static func region_von(g: Dictionary, serial := "") -> String:
	var r := str(g.get("region", "")).to_lower()
	if r in ["pal", "ntsc", "ntsc_j"]:
		return r
	var s := serial if serial != "" else seriennummer(g)
	if s.length() >= 4:
		var p := s.substr(0, 4).to_upper()
		if p in ["SLES", "SCES", "SLED", "SCED"]:
			return "pal"
		if p in ["SLUS", "SCUS", "SLUD", "SCUD"]:
			return "ntsc"
		if p in ["SLPS", "SLPM", "SCPS", "SCAJ", "SLKA", "SCKA"]:
			return "ntsc_j"
	var namen := "%s %s" % [str(g.get("libretro_name", "")), str(g.get("path", "")).replace("\\", "/").get_file()]
	var low := namen.to_lower()
	for k in ["(europe)", "(germany)", "(france)", "(uk)", "(spain)", "(italy)", "(netherlands)", "(sweden)", "(australia)", "(pal)", "(en,", "(de,"]:
		if low.contains(k):
			return "pal"
	if low.contains("(usa)") or low.contains("(us)") or low.contains("(canada)") or low.contains("ntsc-u"):
		return "ntsc"
	if low.contains("(japan)") or low.contains("(ja)") or low.contains("ntsc-j"):
		return "ntsc_j"
	return "pal"


## Seriennummer zum Aufdruck unten am Rücken („SLES 54723“), "" wenn Uzai sie nicht kennt: aus dem
## Eintrag (Disc-Spiele, Demo), bekannt (aus der Bibliothek: gelesen aus dem Abbild) oder aus dem
## Dateinamen („SLES-54723 FIFA Street 2.iso“).
static func seriennummer(g: Dictionary, bekannt := "") -> String:
	var s := DiscSerial.normalize(str(g.get("serial", "")))
	if s == "" and bekannt != "":
		s = DiscSerial.normalize(bekannt)
	if s == "":
		s = DiscSerial.from_name(str(g.get("path", "")))
	return s.replace("-", " ")


## Aufbau des Rückens (von unten 0 bis oben 1): { felder: [{ y0, y1, farbe, logo, bunt, logo_ersatz,
## ersatz, text, schrift, laengs, kurz }], grund, titel_farbe, titel: Vector2(von, bis), nummer:
## Vector2(von, bis) oder ZERO, kopf (Unterkante der Felder) }. aus_cover: Farbe aus dem Cover.
## mit_nummer: Seriennummer bekannt (sonst bekommt der Titel den Platz).
static func ruecken_aufbau(system_id: String, region := "pal", aus_cover := Color(0.3, 0.3, 0.32), mit_nummer := false) -> Dictionary:
	var fd := format_daten(system_id)
	var m: Vector3 = fd.m
	var r: Dictionary = RUECKEN.get(format_von(system_id), {})
	var roh: Array = []
	if r.is_empty():
		roh.append({ "h": float(fd.anteil), "farbe": band_von(fd, ruecken_von(fd, aus_cover)), "logo": logo_schluessel(system_id),
			"schrift": logo_farbe(fd, ruecken_von(fd, aus_cover)), "kurz": true })
	else:
		roh = r.felder
	var felder: Array = []
	var y := 1.0
	for f: Dictionary in roh:
		if str(f.get("nur", "")) != "" and str(f.nur) != region:
			continue
		var h := m.x / m.y if str(f.get("h", "")) == "quadrat" else float(f.h)
		var e := f.duplicate()
		e["y1"] = y
		e["y0"] = y - h
		y -= h
		felder.append(e)
	var grund: Variant = r.get("grund") if not r.is_empty() else null
	var gc: Color = grund if grund is Color else ruecken_von(fd, aus_cover)
	var tf: Variant = r.get("titel")
	var nummer := Vector2.ZERO
	if mit_nummer and bool(r.get("nummer", false)):
		nummer = Vector2(0.0, NUMMER_ANTEIL)
	return { "felder": felder, "grund": gc, "titel_farbe": tf if tf is Color else text_farbe(gc), "kopf": y,
		"titel": Vector2(nummer.y + 0.01, y - 0.012), "nummer": nummer }


# --- Vorderseite: Rahmen des Systems und Format des Bilds ---------------------------------------------

## Rahmen der Vorderseite nach der echten Verpackung (je System, sonst je Format) – nur für Uzais
## Ersatz-Vorderseite (kein Bild) und über einem Motiv ohne eigenes Band (SteamGridDB, Steam); ein
## echter Scan liegt immer unverändert auf der Hülle (ist_scan). seite: „oben“, „links“, „rechts“
## oder „unten“, anteil an Höhe bzw. Breite des Einlegers, farbe des Bands (farbe2: Verlauf zum
## Ende hin, Xbox), form „gerade“, „bogen“ (in der Mitte tiefer: GameCube, Wii U) oder „welle“
## (rechts breit, nach links auslaufend: Wii), linie: feine Kante unter dem Band (GameCube silbern,
## Xbox 360 grün), logo: Farbe des Schriftzugs, marke: Logo-Schlüssel des Schriftzugs (badge_logos.gd;
## ohne: das Systemlogo), marke_lage: „rechts“ (Wii) bzw. „mitte“ (Wii U), sonst links bzw. oben,
## name: Schriftzug in Uzais Schrift, wenn das Logo fehlt (ohne: Name des Systems), zeichen: Logo
## am anderen Ende (PS2, PS1: das farbige PS-Logo; bunt: in seinen Farben), zeichen_ersatz:
## einfarbiges Zeichen, wenn das farbige fehlt. Ohne Eintrag kein Rahmen (Atari, PC Engine).
## Vorbild sind die Scans der Libretro-Sammlung (Form, Lage, Farbe – keine fremde Grafik):
##   PS2 schwarzes Band, „PlayStation®2“ links, PS-Logo rechts; PS3/PSP schwarz; GameCube schwarzes
##   Band mit gebogener Unterkante und silberner Kante; Wii weißer Schwung, Logo rechts; Wii U blauer
##   Bogen, Logo mittig; Xbox schwarz-grüner Verlauf; Xbox 360 hell mit grüner Kante; Switch rot;
##   PS1, Dreamcast, Saturn, DS, GBA ein Streifen links (DS und Saturn weiß), 3DS weiß rechts; SNES
##   unten; N64, NES, Mega Drive schwarz oben, Master System weiß.
const RAHMEN := {
	"ps2": { "seite": "oben", "anteil": 0.085, "farbe": Color("#000000"), "logo": Color("#ffffff"), "marke": "ps2_wortmarke",
		"name": "PlayStation®2", "zeichen": "ps_logo_farbe", "bunt": true, "zeichen_ersatz": "ps_zeichen" },
	"ps3": { "seite": "oben", "anteil": 0.095, "farbe": Color("#050506"), "logo": Color("#ffffff") },
	"psp": { "seite": "oben", "anteil": 0.11, "farbe": Color("#030304"), "logo": Color("#ffffff"), "zeichen": "ps_logo_farbe", "bunt": true,
		"zeichen_ersatz": "ps_zeichen" },
	"gc": { "seite": "oben", "anteil": 0.1, "farbe": Color("#060607"), "logo": Color("#f0f0f2"), "form": "bogen", "linie": Color("#c9ccd2"),
		"marke_lage": "mitte" },
	"wii": { "seite": "oben", "anteil": 0.12, "farbe": Color("#f7f7f8"), "logo": Color("#8a8d93"), "form": "welle", "marke_lage": "rechts" },
	"wiiu": { "seite": "oben", "anteil": 0.11, "farbe": Color("#0a9ad6"), "logo": Color("#ffffff"), "form": "bogen", "marke_lage": "mitte" },
	"switch": { "seite": "oben", "anteil": 0.075, "farbe": Color("#e60012"), "logo": Color("#ffffff") },
	"ds": { "seite": "links", "anteil": 0.1, "farbe": Color("#f4f4f6"), "logo": Color("#6d7077") },
	"3ds": { "seite": "rechts", "anteil": 0.09, "farbe": Color("#f7f7f8"), "logo": Color("#c4202e") },
	"xbox": { "seite": "oben", "anteil": 0.1, "farbe": Color("#0b1208"), "farbe2": Color("#4f9a26"), "logo": Color("#c8e6a8") },
	"xbox360": { "seite": "oben", "anteil": 0.09, "farbe": Color("#eceeea"), "farbe2": Color("#cfd3cc"), "logo": Color("#5b9e2e"),
		"linie": Color("#5aa12f") },
	"md": { "seite": "oben", "anteil": 0.12, "farbe": Color("#0b0b0c"), "logo": Color("#ffffff"), "linie": Color("#3a3d44"), "marke_lage": "mitte" },
	"sms": { "seite": "oben", "anteil": 0.12, "farbe": Color("#f3f3f1"), "logo": Color("#1a1a1c") },
	"ps1": { "seite": "links", "anteil": 0.11, "farbe": Color("#050506"), "logo": Color("#ffffff"), "zeichen": "ps_logo_farbe", "bunt": true },
	"dreamcast": { "seite": "links", "anteil": 0.09, "farbe": Color("#0c0c0e"), "logo": Color("#ffffff") },
	"saturn": { "seite": "links", "anteil": 0.12, "farbe": Color("#f2f2f0"), "logo": Color("#1a1a1c") },
	"gba": { "seite": "links", "anteil": 0.1, "farbe": Color("#1d1a2e"), "logo": Color("#ffffff") },
	"klein": { "seite": "oben", "anteil": 0.12, "farbe": Color("#1e1d22"), "logo": Color("#ffffff") },
	"modul": { "seite": "oben", "anteil": 0.11, "farbe": Color("#0c0c0d"), "logo": Color("#ffffff") },
	"snes": { "seite": "unten", "anteil": 0.11, "farbe": Color("#0c0c0d"), "logo": Color("#e03a3e") },
	"karton": { "seite": "oben", "anteil": 0.11, "farbe": Color("#0c0c0d"), "logo": Color("#ffffff") },
}
const FORMEN := { "gerade": 0, "bogen": 1, "welle": 2 }
const SEITEN := { "oben": 0, "links": 1, "rechts": 2, "unten": 3 }

## So weit darf das Seitenverhältnis eines Bilds von der Fläche abweichen (log, ≈ 6 %), sonst wird
## ein passenderes geholt bzw. zugeschnitten – nie gestreckt.
const ABWEICHUNG := 0.06
## Ein Scan darf so viel (je Richtung) über den Einleger hinausragen, bevor Uzai Ränder lässt –
## er wird nie gestreckt und kaum beschnitten.
const SCAN_ZUGABE := 0.03
## Bildarten mit festem Format bei SteamGridDB (Media: cover_hoch, cover_quadrat, cover_quer) und
## ihr Seitenverhältnis (Breite / Höhe).
const BILDARTEN := { "cover": 600.0 / 900.0, "cover_hoch": 660.0 / 930.0, "cover_quadrat": 1.0, "cover_quer": 920.0 / 430.0 }
## Rand der Hülle um den Einleger (m): Kunststoffhülle schmal gefasst (am Rücken läuft der Einleger
## um die Kante), CD-Hülle mit dem gerippten Scharnierstreifen links, Karton bis an die Kante.
const COVER_RAND := 0.0025
const COVER_RAND_RUECKEN := 0.0006
const COVER_RAND_KARTON := 0.0006
const JEWEL_SCHARNIER := 0.12      ## Anteil der Breite: Scharnierstreifen der CD-Hülle
const SCHARNIER := 0.0095          ## Kunststoffhülle: Scharnierwulst so weit vom Rücken (m)
## Bilder aus diesen Ordnern (Media-Cache) sind Motive, keine Scans der Verpackung.
const MOTIV_ORDNER := ["/cache/img/sgdb/", "/cache/img/steam/", "/cache/img/art/", "/appcache/librarycache/", "/config/grid/"]


static func rahmen_von(system_id: String) -> Dictionary:
	if RAHMEN.has(system_id):
		return RAHMEN[system_id]
	return RAHMEN.get(format_von(system_id), {})


## Logo-Schlüssel des Schriftzugs im Band der Vorderseite (PS2: die Wortmarke „PlayStation®2“ wie
## auf den Covern, nicht das „PS2“-Logo der Startseite).
static func marke_von(system_id: String) -> String:
	var mk := str(rahmen_von(system_id).get("marke", ""))
	return mk if mk != "" else logo_schluessel(system_id)


## Zeichen am anderen Ende des Bands: { key, bunt, ersatz } oder {}.
static func zeichen_von(system_id: String, _region := "pal") -> Dictionary:
	var r := rahmen_von(system_id)
	var k := str(r.get("zeichen", ""))
	if k == "":
		return {}
	return { "key": k, "bunt": bool(r.get("bunt", false)), "ersatz": str(r.get("zeichen_ersatz", "")) }


## Ist ein Bild ein echter Scan der Verpackung (dann liegt es unverändert auf der Hülle)? Ja für
## Libretro, ScreenScraper, den Medienordner und eigene Bilder; ein Motiv (SteamGridDB, Steam) nur,
## wenn es selbst schon ein Band trägt (erkannt: rahmen_erkennen).
static func ist_scan(pfad: String, erkannt: Dictionary) -> bool:
	if bool(erkannt.get("oben", false)) or bool(erkannt.get("links", false)):
		return true
	var p := pfad.replace("\\", "/")
	for o in MOTIV_ORDNER:
		if p.contains(o):
			return false
	return true


## Vorderseite (Breite, Höhe) in Metern: der Einleger (einleger) ohne die Ränder der Hülle.
static func vorderseite(system_id: String) -> Vector2:
	return einleger(system_id).size


## Lage des Einlegers auf der Vorderseite (Meter, Ursprung unten links, links ist der Rücken):
## Kunststoffhülle schmal gefasst, am Rücken fast randlos; CD-Hülle rechts neben dem gerippten
## Scharnierstreifen; Karton randvoll.
static func einleger(system_id: String) -> Rect2:
	var fd := format_daten(system_id)
	var w := (fd.m as Vector3).z
	var h := (fd.m as Vector3).y
	match str(fd.art):
		"karton":
			return Rect2(COVER_RAND_KARTON, COVER_RAND_KARTON, w - COVER_RAND_KARTON * 2.0, h - COVER_RAND_KARTON * 2.0)
		"jewel":
			var s := w * JEWEL_SCHARNIER
			return Rect2(s, COVER_RAND, w - s - COVER_RAND, h - COVER_RAND * 2.0)
	return Rect2(COVER_RAND_RUECKEN, COVER_RAND, w - COVER_RAND_RUECKEN - COVER_RAND, h - COVER_RAND * 2.0)


## Fläche für das Motiv auf der Vorderseite (Rechteck, Ursprung unten links, Meter): mit Rahmen des
## Systems um das Band verkleinert, sonst die ganze Seite.
static func motiv_flaeche(seite: Vector2, rahmen: Dictionary) -> Rect2:
	var a := float(rahmen.get("anteil", 0.0))
	match str(rahmen.get("seite", "")):
		"oben":
			return Rect2(0, 0, seite.x, seite.y * (1.0 - a))
		"unten":
			return Rect2(0, seite.y * a, seite.x, seite.y * (1.0 - a))
		"links":
			return Rect2(seite.x * a, 0, seite.x * (1.0 - a), seite.y)
		"rechts":
			return Rect2(0, 0, seite.x * (1.0 - a), seite.y)
	return Rect2(Vector2.ZERO, seite)


## Ein Scan auf dem Einleger: unverändert, nie gestreckt. Weicht sein Format ab, ragt er höchstens
## SCAN_ZUGABE über (mittig beschnitten), sonst bleibt ein schmaler Rand. Rückgabe: { lage (Rect2
## auf der Fläche, Meter, Ursprung unten links), uv (Rect2 im Bild, Anteile, Ursprung oben links) }.
static func einpassen(bild: Vector2, flaeche: Vector2) -> Dictionary:
	if bild.x <= 0.0 or bild.y <= 0.0 or flaeche.x <= 0.0 or flaeche.y <= 0.0:
		return { "lage": Rect2(Vector2.ZERO, flaeche), "uv": Rect2(0, 0, 1, 1) }
	var klein := minf(flaeche.x / bild.x, flaeche.y / bild.y)
	var gross := maxf(flaeche.x / bild.x, flaeche.y / bild.y)
	var s := minf(gross, klein * (1.0 + SCAN_ZUGABE))
	var g := bild * s
	var sicht := Vector2(minf(g.x, flaeche.x), minf(g.y, flaeche.y))
	var uv_gr := sicht / g
	return { "lage": Rect2((flaeche - sicht) * 0.5, sicht), "uv": Rect2((Vector2.ONE - uv_gr) * 0.5, uv_gr) }


## Passt ein Bild (Größe) in eine Fläche (Größe), ohne merklich beschnitten zu werden?
static func passt(bild: Vector2, flaeche: Vector2) -> bool:
	if bild.x <= 0.0 or bild.y <= 0.0 or flaeche.x <= 0.0 or flaeche.y <= 0.0:
		return false
	return absf(log((bild.x / bild.y) / (flaeche.x / flaeche.y))) <= ABWEICHUNG


## Welche Bildart am besten auf eine Fläche passt (cover, cover_hoch, cover_quadrat, cover_quer).
static func bildart_fuer(flaeche: Vector2) -> String:
	var best := "cover"
	var bd := INF
	var ziel := flaeche.x / maxf(flaeche.y, 0.0001)
	for k in BILDARTEN:
		var d := absf(log(float(BILDARTEN[k]) / ziel))
		if d < bd - 0.0001:
			bd = d
			best = str(k)
	return best


## Welche Bildarten (Media) die Vorderseite der Reihe nach versucht. Ein eigenes Cover des Nutzers
## gilt immer allein. vorhanden: Bildart → liegt schon da; sgdb: eigener SteamGridDB-Schlüssel.
## Zuerst immer der echte Scan der Verpackung (Libretro, ScreenScraper) – er kommt unverändert auf
## die Hülle; dann, mit Rahmen des Systems (rahmen), ein Motiv im passenden Format für die Fläche
## unter Uzais Band (schon da oder von SteamGridDB), zuletzt das übliche Cover.
static func bildarten(g: Dictionary, gewuenscht: String, vorhanden: Dictionary, rahmen := false, sgdb := false) -> Array:
	var eigen: Variant = g.get("images", {})
	if eigen is Dictionary and str((eigen as Dictionary).get("cover", "")) != "":
		return ["cover"]
	var out: Array = []
	if str(g.get("source", "")) in ["rom", "disc"] or bool(vorhanden.get("cover_scan", false)):
		out.append("cover_scan")
	if gewuenscht != "cover" and (bool(vorhanden.get(gewuenscht, false)) or (rahmen and sgdb)):
		out.append(gewuenscht)
	out.append("cover")
	return out


## Ausschnitt (Anteile 0 … 1 des Bilds) für eine Fläche: randvoll, mittig, nie verzerrt.
static func ausschnitt(bild: Vector2, flaeche: Vector2) -> Rect2:
	if bild.x <= 0.0 or bild.y <= 0.0 or flaeche.x <= 0.0 or flaeche.y <= 0.0:
		return Rect2(0, 0, 1, 1)
	var s := maxf(flaeche.x / bild.x, flaeche.y / bild.y)
	var w := flaeche / s
	return Rect2((Vector2.ONE - w / bild) * 0.5, w / bild)

## Hat ein Bild schon den Rahmen eines Systems (echter Scan der Verpackung, auch manches Bild bei
## SteamGridDB)? Oben ein Band in einer Farbe (schwarz bei PS2, weiß bei Wii, rot bei Switch …),
## darin auch Schrift und Logos („PlayStation®2“, farbiges PS-Logo), das nach gut einem Zehntel
## scharf endet; bzw. links ein solcher Streifen (PS1). Läuft im Hilfsthread beim Dekodieren (Media).
## { oben, links, oben_ende, links_ende } – ende: bis wohin das Band reicht (Anteil, zum Wegschneiden).
static func rahmen_erkennen(src: Image) -> Dictionary:
	var aus := { "oben": false, "links": false, "oben_ende": 0.0, "links_ende": 0.0 }
	if src == null or src.is_empty() or src.get_width() < 8 or src.get_height() < 8:
		return aus
	var img := src.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return aus
	img.convert(Image.FORMAT_RGBA8)
	# Lange Seite 120 Punkte: fein genug, um das Band auf gut 1 % genau abzuschneiden.
	var lang_px := 120.0
	var w := clampi(roundi(lang_px * src.get_width() / maxf(src.get_width(), src.get_height())), 16, 120)
	var h := clampi(roundi(lang_px * src.get_height() / maxf(src.get_width(), src.get_height())), 16, 120)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var o := _band(img, true)
	var l := _band(img, false)
	aus.oben = o > 0.0
	aus.oben_ende = o
	aus.links = l > 0.0
	aus.links_ende = l
	return aus


## Ein Band am Rand: oben in einer vorherrschenden Farbe (in den Zeilen dazwischen darf helle
## Schrift oder ein farbiges Logo stehen – im Mittel trotzdem über 55 %, wenigstens eine Zeile fast
## rein), das nach 5–17 % scharf endet: davor eine fast reine Zeile, gleich dahinter deutlich andere
## Farben (nicht allmählich wie ein Verlauf oder Himmel), danach im Motiv (25–50 %) selten. Gibt
## es mehrere solche Kanten (Schrift im Band), zählt die unterste. Rückgabe: Ende des Bands
## (Anteil, eine Spur Rand dazu), 0 = kein Band.
static func _band(img: Image, oben: bool) -> float:
	var lang := img.get_height() if oben else img.get_width()
	var start := int(lang * 0.01)
	var band: Array = []
	for t in range(start, maxi(start + 1, ceili(lang * 0.05))):
		band.append_array(_reihe(img, oben, t))
	var dom := _vorherrschend(band)
	var bis := mini(lang - 4, ceili(lang * 0.17) + 1)
	var f := PackedFloat32Array()
	for t in range(0, bis + 4):
		f.append(_anteil_nah(_reihe(img, oben, t), dom))
	var ende := -1
	for t in range(maxi(3, roundi(lang * 0.05)), bis):
		if t < lang * 0.05 or t > lang * 0.17:
			continue
		if f[t] >= 0.4 or (f[t] + f[t + 1] + f[t + 2]) / 3.0 >= 0.35:
			continue
		if maxf(f[t - 1], maxf(f[t - 2], f[t - 3])) < 0.7:
			continue
		# Bis hierher muss es ein Band sein: im Mittel vorherrschend, nie ganz unterbrochen, eine
		# Zeile fast rein (Rand über bzw. unter der Schrift).
		var summe := 0.0
		var rein := 0.0
		var luecke := false
		for k in range(start, t):
			summe += f[k]
			rein = maxf(rein, f[k])
			luecke = luecke or f[k] < 0.25
		if luecke or summe / maxf(1.0, t - start) < 0.55 or rein < 0.85:
			continue
		if _abstand_mittel(_reihe(img, oben, t + 1), dom) < 0.2:
			continue
		ende = t
	if ende < 0:
		return 0.0
	var motiv: Array = []
	for t in range(int(lang * 0.25), maxi(int(lang * 0.25) + 1, ceili(lang * 0.5))):
		motiv.append_array(_reihe(img, oben, t))
	if _anteil_nah(motiv, dom) >= 0.5:
		return 0.0
	return minf(0.2, (ende + 0.6) / lang)


## Eine Zeile (oben) bzw. Spalte (links) des Bilds.
static func _reihe(img: Image, oben: bool, t: int) -> Array:
	var out: Array = []
	var quer := img.get_width() if oben else img.get_height()
	for q in quer:
		out.append(img.get_pixel(q, t) if oben else img.get_pixel(t, q))
	return out


static func _vorherrschend(px: Array) -> Color:
	var faecher := {}
	for c: Color in px:
		var k := (int(c.r * 7.99) << 6) | (int(c.g * 7.99) << 3) | int(c.b * 7.99)
		var e: Array = faecher.get(k, [0, Color(0, 0, 0, 0)])
		e[0] = int(e[0]) + 1
		e[1] = (e[1] as Color) + c
		faecher[k] = e
	var best: Array = [0, Color.BLACK]
	for k in faecher:
		if int(faecher[k][0]) > int(best[0]):
			best = faecher[k]
	var n := maxf(1.0, float(best[0]))
	var s: Color = best[1]
	return Color(s.r / n, s.g / n, s.b / n)


static func _abstand_mittel(px: Array, c: Color) -> float:
	if px.is_empty():
		return 0.0
	var sum := 0.0
	for p: Color in px:
		sum += maxf(absf(p.r - c.r), maxf(absf(p.g - c.g), absf(p.b - c.b)))
	return sum / px.size()


static func _anteil_nah(px: Array, c: Color) -> float:
	if px.is_empty():
		return 0.0
	var n := 0
	for p: Color in px:
		if maxf(absf(p.r - c.r), maxf(absf(p.g - c.g), absf(p.b - c.b))) < 0.14:
			n += 1
	return float(n) / px.size()


static var _rahmen_memo := {}
static var _rahmen_mx := Mutex.new()


## rahmen_erkennen je Datei gemerkt (Pfad und Änderungszeit; sicher aus dem Hilfsthread).
static func rahmen_merken(path: String, img: Image) -> Dictionary:
	var key := "%s|%d" % [path, FileAccess.get_modified_time(path)] if path != "" else ""
	if key != "":
		_rahmen_mx.lock()
		var hit: Variant = _rahmen_memo.get(key)
		_rahmen_mx.unlock()
		if hit is Dictionary:
			return hit
	var r := rahmen_erkennen(img)
	if key != "":
		_rahmen_mx.lock()
		if _rahmen_memo.size() > 2000:
			_rahmen_memo.clear()
		_rahmen_memo[key] = r
		_rahmen_mx.unlock()
	return r


# --- Rücken ------------------------------------------------------------------------------------------

## Farbe des Rückens: die prägende Farbe des Covers (Media.color_of), in ein ruhiges Band aus
## Sättigung und Helligkeit gelegt – nie grell, nie schwarz. Ohne Coverfarbe die Farbe des Systems,
## je Spiel (seed) leicht anders, damit ein Regal ohne Bilder nicht einfarbig wirkt.
static func ruecken_farbe(cover: Variant, system_farbe: Color, seed_ := "") -> Color:
	if cover is Color:
		var c: Color = cover
		return Color.from_hsv(c.h, clampf(c.s, 0.18, 0.78), clampf(c.v, 0.26, 0.72))
	var h := float(absi(seed_.hash()) % 1000) / 1000.0
	var b := system_farbe.lerp(system_farbe.lightened(0.2) if h > 0.5 else system_farbe.darkened(0.25), absf(h - 0.5) * 0.9)
	return Color.from_hsv(b.h, clampf(b.s, 0.0, 0.7), clampf(b.v, 0.2, 0.7))


## Schrift auf einem Grund: hell auf dunkel, dunkel auf hell.
static func text_farbe(grund: Color) -> Color:
	return Color("#16151a") if grund.get_luminance() > 0.55 else Color("#f3f2ef")


## Titel für den Rücken: Zeilenumbrüche raus, zu lange Titel mit „…“ gekürzt.
static func ruecken_titel(titel: String, max_zeichen := 40) -> String:
	var t := titel.replace("\n", " ").replace("\t", " ").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	if t.length() > max_zeichen:
		t = t.substr(0, maxi(1, max_zeichen - 1)).strip_edges() + "…"
	return t


# --- Abschnitte --------------------------------------------------------------------------------------

## Abschnitt A–Z: der erste Buchstabe (Zeichen weg: Ōkami → O), Ziffern und anderes unter „#“.
static func buchstabe(titel: String) -> String:
	var t := titel.strip_edges()
	if t == "":
		return "#"
	var c := t.substr(0, 1).to_upper()
	c = str(GRUND.get(c, c))
	var code := c.unicode_at(0)
	if code >= 65 and code <= 90:
		return c
	return "#"


## Schlüssel zum Sortieren nach Titel: groß, Zeichen weg (Ōkami steht bei O, nicht hinter Z).
static func titel_schluessel(titel: String) -> String:
	var t := titel.strip_edges().to_upper()
	# Nur ASCII (fast alle Titel): Da gibt es nichts zu ersetzen.
	if t.to_utf8_buffer().size() == t.length():
		return t
	var out := ""
	for i in t.length():
		var c := t.substr(i, 1)
		out += str(GRUND.get(c, c))
	return out


## A–Z wie die Abschnitte: nach titel_schluessel, natürlich (2 vor 10). titel: Callable(g) → Titel.
static func nach_titel(list: Array, titel: Callable) -> Array:
	# Den Schlüssel je Spiel einmal bilden, nicht bei jedem Vergleich neu (gemessen vorher: 70 ms bei 500 Spielen,
	# 0,53 s bei 3000 – bei jedem Öffnen des Regals). Gleiche Titel bleiben in der Reihenfolge der Liste.
	var paare: Array = []
	for i in list.size():
		paare.append([titel_schluessel(str(titel.call(list[i]))), i])
	paare.sort_custom(func(a: Array, b: Array) -> bool:
		var c := str(a[0]).naturalnocasecmp_to(str(b[0]))
		return c < 0 if c != 0 else int(a[1]) < int(b[1]))
	var out: Array = []
	for p: Array in paare:
		out.append(list[int(p[1])])
	return out


## Abschnitt eines Spiels in der Sortierung mode. Zeiten in Sekunden (Unix), jetzt: Uhr dazu.
static func abschnitt(mode: String, titel: String, zuletzt: int, spielzeit: int, neu: int, jetzt: int) -> String:
	match mode:
		"recent":
			if zuletzt <= 0:
				return "Nie gespielt"
			var tage := float(jetzt - zuletzt) / 86400.0
			if tage < 1.0:
				return "Heute"
			if tage < 7.0:
				return "Diese Woche"
			if tage < 31.0:
				return "Diesen Monat"
			if tage < 365.0:
				return "Dieses Jahr"
			return "Früher"
		"playtime":
			var h := float(spielzeit) / 3600.0
			if spielzeit <= 0:
				return "Nicht gespielt"
			if h >= 100.0:
				return "Über 100 Std."
			if h >= 20.0:
				return "20–100 Std."
			if h >= 5.0:
				return "5–20 Std."
			if h >= 1.0:
				return "1–5 Std."
			return "Unter 1 Std."
		"added":
			if neu <= 0:
				return "Früher"
			if jetzt - neu < 30 * 86400:
				return "Neu"
			return str(Time.get_datetime_dict_from_unix_time(neu).year)
	return buchstabe(titel)


## Abschnitte aus den Schlüsseln der (schon sortierten) Spiele: aufeinanderfolgende gleiche
## Schlüssel bilden einen Abschnitt { name, start, ende } (ende ausschließlich).
static func abschnitte(schluessel: Array) -> Array:
	var out: Array = []
	for i in schluessel.size():
		var k := str(schluessel[i])
		if out.is_empty() or str(out.back().name) != k:
			if not out.is_empty():
				out.back().ende = i
			out.append({ "name": k, "start": i, "ende": schluessel.size() })
	return out


## In welchem Abschnitt steht Hülle i?
static func abschnitt_an(abs_: Array, i: int) -> int:
	for a in abs_.size():
		if i >= int(abs_[a].start) and i < int(abs_[a].ende):
			return a
	return maxi(0, abs_.size() - 1)


## LB/RB: d = 1 an den Anfang des nächsten Abschnitts, d = −1 an den Anfang des eigenen (steht man
## schon dort: des vorigen). Am Ende bleibt es stehen.
static func sprung(abs_: Array, i: int, d: int) -> int:
	if abs_.is_empty():
		return i
	var a := abschnitt_an(abs_, i)
	if d > 0:
		return int(abs_[a + 1].start) if a + 1 < abs_.size() else i
	if i > int(abs_[a].start):
		return int(abs_[a].start)
	return int(abs_[a - 1].start) if a > 0 else i


# --- Lage auf dem Brett ------------------------------------------------------------------------------

## Mitte jeder Hülle entlang des Bretts (x), dicht an dicht; an jedem neuen Abschnitt (außer dem
## ersten) etwas Platz für einen Trenner. Rückgabe: { x: PackedFloat32Array, trenner: [x je
## Abschnitt ab dem zweiten], laenge }.
static func anordnen(dicken: Array, abs_: Array) -> Dictionary:
	var xs := PackedFloat32Array()
	xs.resize(dicken.size())
	var starts := {}
	for a in range(1, abs_.size()):
		starts[int(abs_[a].start)] = true
	var trenner: Array = []
	var x := 0.0
	for i in dicken.size():
		var d := float(dicken[i])
		if starts.has(i):
			trenner.append(x + TRENNER * 0.5 - LUECKE * 0.5)
			x += TRENNER
		xs[i] = x + d * 0.5
		x += d + LUECKE
	return { "x": xs, "trenner": trenner, "laenge": maxf(0.0, x - LUECKE) }


## Welche Hüllen liegen (mit ihrer Mitte) zwischen links und rechts? Vector2i(erste, letzte),
## leer: erste > letzte. xs ist aufsteigend (anordnen).
static func bereich(xs: PackedFloat32Array, links: float, rechts: float) -> Vector2i:
	if xs.is_empty() or rechts < links:
		return Vector2i(0, -1)
	var a := xs.bsearch(links, true)
	var b := xs.bsearch(rechts, false) - 1
	return Vector2i(clampi(a, 0, xs.size()), clampi(b, -1, xs.size() - 1))


## Innere Grenzen des Regals (x von … bis): an beiden Enden Platz für die herausgezogene Hülle,
## und nie schmaler als das Bild (halb: halbe Bildbreite in der Ebene der Rücken) – wenige Spiele
## stehen links, daneben ist das Brett frei.
static func grenzen(laenge: float, halb: float) -> Vector2:
	var a := -RAND_INNEN
	return Vector2(a, maxf(laenge + RAND_INNEN, a + 2.0 * halb - 0.08))


## Wohin die Kamera fährt: zur gewählten Hülle – an den Enden nur so weit, dass das Regal das Bild
## füllt (die Seitenwand der Stärke seite gerade noch zu sehen).
## Die gewählte Hülle bleibt dabei immer gut im Bild (höchstens NEBEN_MAX der halben Breite neben
## der Mitte – herausgezogen steht sie näher an der Kamera und wirkt weiter außen).
static func kamera_ziel(x: float, gr: Vector2, halb: float, seite: float) -> float:
	var lo := gr.x - seite - 0.02 + halb
	var hi := gr.y + seite + 0.02 - halb
	var c := (gr.x + gr.y) * 0.5 if lo > hi else clampf(x, lo, hi)
	return clampf(c, x - halb * NEBEN_MAX, x + halb * NEBEN_MAX)


## Schritt beim Blättern: gehalten wird es nach einer Weile schneller (zwei, dann drei auf einmal).
static func schritt_weite(wiederholungen: int) -> int:
	if wiederholungen >= 26:
		return 3
	if wiederholungen >= 10:
		return 2
	return 1


static func schritt(i: int, d: int, n: int) -> int:
	return clampi(i + d, 0, maxi(0, n - 1))


# --- Bewegung ----------------------------------------------------------------------------------------

## Lage einer Hülle beim Herausziehen, p 0 (steht im Regal) … 1 (vorn, zur Kamera gedreht):
## erst gerade nach vorn aus dem Regal (bis sie frei ist), dann hoch und zur Kamera gedreht.
## Rückgabe { vor (m, nach vorn), hoch (m), dreh (Grad um die Hochachse) }.
## massstab: Größe des Regals (Höhe der höchsten Hülle / 0,19 m) – kleine Hüllen kommen weniger weit.
static func zug_lage(p: float, tiefe: float, massstab := 1.0) -> Dictionary:
	var q := clampf(p, -0.2, 1.2)
	var raus := _glatt(clampf(q / 0.55, 0.0, 1.0)) + maxf(0.0, q - 1.0) * 0.4
	var dreh := _glatt(clampf((q - 0.3) / 0.7, 0.0, 1.0)) + maxf(0.0, q - 1.0) * 0.5
	return { "vor": raus * (tiefe + ZUG_VOR * massstab), "hoch": clampf(q, 0.0, 1.1) * ZUG_HOCH * massstab, "dreh": dreh * ZUG_DREH }


static func _glatt(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Feder mit Dämpfung zeta (1 = ohne Nachschwingen, darunter federt sie ein wenig nach), ein
## Schritt: [Lage, Tempo] → neue [Lage, Tempo]. In kleinen Teilschritten gerechnet, damit sie auch
## bei 30 Bildern je Sekunde stabil bleibt.
static func feder(pos: float, vel: float, ziel: float, dt: float, omega: float, zeta := 1.0) -> Vector2:
	var n := maxi(1, ceili(dt / 0.004))
	var h := dt / n
	for _i in n:
		var a := -omega * omega * (pos - ziel) - 2.0 * zeta * omega * vel
		vel += a * h
		pos += vel * h
	return Vector2(pos, vel)

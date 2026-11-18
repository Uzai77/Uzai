extends RefCounted
## Gestaltung des Zimmers als reine Daten (Punkt 131): Farben, Materialien, Muster, Wände, Boden,
## Decke, Fenster, Tür, Licht und Stimmungen, wie die Spiele ins Regal kommen und eigene Möbel aus
## dem Baukasten. Alles sind feste Kennungen aus den Listen hier, Zahlen in festen Bereichen und
## Farben als „#rrggbb“ – nichts davon wird ausgeführt oder als Ressource geladen. Was nicht passt,
## fällt auf den Standard zurück (pruefe_*). Gebaut wird daraus in raum.gd, moebel.gd und inhalt.gd.
##
## Felder eines Möbels (alle freiwillig, fehlt eins, gilt der Standard des Katalogs):
##   f, m, mu, mf   Farbe, Material, Muster, Musterfarbe des Hauptteils (Bezug, Korpus)
##   f2, m2         Farbe und Material des Gestells (Beine, Rahmen, Fuß)
##   s              Größe (Index in den Stufen des Katalogs)
##   be, gr         Beine und Griffe
##   l              Licht { k Farbtemperatur, c Farbe, h Helligkeit %, w Reichweite % }
##   rg             Regal { so Sortierung, fi Auswahl, da Darstellung, ab Abnutzung, de Deko, ma Reihe }
##                  Spieleregale stehen zuerst leer: Auswahl „eigene“ – im Regal steht genau, was du
##                  eingeräumt hast (ma: Spiel-IDs, nur aus der eigenen Bibliothek gezeigt).

const Fremd := preload("res://src/core/fremd.gd")

# --- Farben --------------------------------------------------------------------------------------

## Abgestimmte Palette: warm, gedeckt, ein paar kräftige Töne und Neon fürs Licht.
const PALETTE := [
	["#f3efe7", "Kreide"], ["#e8e0d1", "Creme"], ["#d9cbb3", "Sand"], ["#c7b299", "Hafer"],
	["#a89a8a", "Kiesel"], ["#7d7a76", "Basalt"], ["#4b4d52", "Graphit"], ["#26272b", "Nacht"],
	["#c4913c", "Senf"], ["#d9a441", "Honig"], ["#b0603c", "Terrakotta"], ["#c98c6b", "Lehm"],
	["#d6b0a6", "Altrosa"], ["#9c4a52", "Beere"], ["#7a3b2e", "Rost"], ["#5c3b2e", "Kakao"],
	["#87977a", "Salbei"], ["#5d7a5a", "Moos"], ["#3f5a4a", "Tanne"], ["#a9b49b", "Pistazie"],
	["#8fb3b0", "Eukalyptus"], ["#4f7f8f", "Petrol"], ["#34425e", "Nachtblau"], ["#6f86b5", "Taube"],
	["#8a6a8f", "Pflaume"], ["#b9a6c9", "Lavendel"], ["#e7c27d", "Uzai-Gold"], ["#f0e3a0", "Zitrone"],
	["#ff4fa3", "Neon-Pink"], ["#7a5cff", "Neon-Violett"], ["#2fd6ff", "Neon-Cyan"], ["#5dff9b", "Neon-Grün"],
]
const MAX_EIGENE_FARBEN := 16


## Farbe als „#rrggbb“ (klein geschrieben), "" wenn es keine ist.
static func farbe(v: Variant) -> String:
	if not (v is String):
		return ""
	var s := (v as String).strip_edges().to_lower()
	if s.length() != 7 or not s.begins_with("#"):
		return ""
	for ch in s.substr(1):
		if not (ch in "0123456789abcdef"):
			return ""
	return s


static func farbname(hex: String) -> String:
	for p in PALETTE:
		if str(p[0]) == hex:
			return str(p[1])
	return ""


# --- Materialien und Muster der Möbel -----------------------------------------------------------

## id → [Name, Art, Standardfarbe]. Art: holz, lack, metall, stoff, leder, stein, rattan.
const MATERIALIEN := {
	"eiche": ["Eiche", "holz", "#c9a173"], "walnuss": ["Walnuss", "holz", "#7d5538"],
	"kirsche": ["Kirsche", "holz", "#a8623f"], "esche": ["Esche", "holz", "#ddc7a4"],
	"raeuchereiche": ["Räuchereiche", "holz", "#5a4334"], "weiss": ["Weiß lackiert", "holz", "#efebe4"],
	"schwarz": ["Schwarz gebeizt", "holz", "#2e2b29"],
	"lack_matt": ["Lack, matt", "lack", "#e8e0d1"], "lack_glanz": ["Hochglanz", "lack", "#e8e0d1"],
	"metall": ["Metall, pulverbeschichtet", "metall", "#2b2c30"], "stahl": ["Edelstahl", "metall", "#a9abae"],
	"chrom": ["Chrom", "metall", "#d6d8db"], "messing": ["Messing", "metall", "#b8925a"],
	"kupfer": ["Kupfer", "metall", "#b8734f"],
	"stoff": ["Webstoff", "stoff", "#87977a"], "samt": ["Samt", "stoff", "#34425e"],
	"cord": ["Cord", "stoff", "#c4913c"], "boucle": ["Bouclé", "stoff", "#e8e0d1"],
	"leinen": ["Leinen", "stoff", "#d9cbb3"], "leder": ["Leder", "leder", "#7a4a2e"],
	"marmor": ["Marmor", "stein", "#ece8e1"], "beton": ["Beton", "stein", "#a3a19c"],
	"terrazzo": ["Terrazzo", "stein", "#e3ddd2"], "rattan": ["Rattan", "rattan", "#c9a476"],
}
const MATERIAL_REIHE := ["eiche", "walnuss", "kirsche", "esche", "raeuchereiche", "weiss", "schwarz",
	"lack_matt", "lack_glanz", "metall", "stahl", "chrom", "messing", "kupfer",
	"stoff", "samt", "cord", "boucle", "leinen", "leder", "marmor", "beton", "terrazzo", "rattan"]

## Muster für Stoffe (stoff.gdshader) und Tapeten (wand.gdshader).
const MUSTER := [["", "Uni"], ["streifen", "Streifen"], ["nadel", "Nadelstreifen"], ["karo", "Karo"],
	["punkte", "Punkte"], ["rauten", "Rauten"], ["fischgrat", "Fischgrät"], ["zickzack", "Zickzack"], ["ornament", "Ornament"]]

const BEINE := [["", "Holz, konisch"], ["haarnadel", "Haarnadel"], ["rund", "Metall, rund"], ["kufen", "Kufen"],
	["sockel", "Sockel"]]
const GRIFFE := [["", "Knopf"], ["buegel", "Bügel"], ["leiste", "Griffleiste"], ["keine", "Grifflos"]]


static func material_art(id: String) -> String:
	var m: Array = MATERIALIEN.get(id, [])
	return str(m[1]) if m.size() > 1 else ""


static func material_name(id: String) -> String:
	var m: Array = MATERIALIEN.get(id, [])
	return str(m[0]) if not m.is_empty() else ""


static func material_farbe(id: String) -> String:
	var m: Array = MATERIALIEN.get(id, [])
	return str(m[2]) if m.size() > 2 else "#c9a173"


static func muster_nr(id: String) -> int:
	for i in MUSTER.size():
		if str(MUSTER[i][0]) == id:
			return i
	return 0


# --- Raum -----------------------------------------------------------------------------------------

const SEITEN := ["hinten", "links", "vorn", "rechts"]
const SEITEN_NAMEN := { "hinten": "Hintere Wand", "links": "Linke Wand (Fenster)", "vorn": "Vordere Wand", "rechts": "Rechte Wand (Tür)" }
const WANDMATERIAL := [["anstrich", "Anstrich"], ["kalk", "Kalkputz"], ["tapete", "Tapete"], ["paneel", "Paneel, halbhoch"],
	["holz", "Holzverkleidung"], ["ziegel", "Ziegel"], ["beton", "Sichtbeton"], ["fliesen", "Fliesen"]]
const BODENARTEN := [["dielen", "Dielen"], ["landhaus", "Landhausdielen"], ["fischgrat", "Fischgrät-Parkett"],
	["fliesen", "Fliesen"], ["schachbrett", "Schachbrett"], ["terrazzo", "Terrazzo"], ["beton", "Beton"],
	["teppichboden", "Teppichboden"], ["marmor", "Marmor"]]
const SOCKEL := [["schmal", "Schmal"], ["hoch", "Hoch"], ["keine", "Ohne"]]
const DECKEN := [["glatt", "Glatt"], ["balken", "Holzbalken"], ["holz", "Holzdecke"], ["stuck", "Stuckrand"]]
const FENSTERARTEN := [["sprossen", "Sprossenfenster"], ["panorama", "Panorama"], ["fluegel", "Zwei Flügel"],
	["raster", "Kleine Sprossen"], ["keins", "Ohne Fenster"]]
const FENSTERGROESSEN := [["Schmal", 1.3], ["Mittel", 1.9], ["Breit", 2.6], ["Bodentief", 2.2]]
const VORHAENGE := [["lang", "Vorhänge"], ["gardine", "Gardine und Vorhang"], ["kurz", "Kurze Vorhänge"],
	["rollo", "Rollo"], ["keine", "Ohne"]]
const TUERARTEN := [["kassette", "Kassettentür"], ["glatt", "Glatte Tür"], ["glas", "Mit Glas"], ["landhaus", "Landhaus"]]
const TUERPLAETZE := [["vorn", "Vorn"], ["mitte", "Mitte"], ["hinten", "Hinten"]]
const GRIFF_FARBEN := [["messing", "Messing"], ["schwarz", "Schwarz"], ["chrom", "Chrom"]]

const ZEITEN := [["auto", "Wie draußen"], ["morgen", "Morgen"], ["tag", "Tag"], ["abend", "Abend"], ["nacht", "Nacht"]]
const WETTER := [["klar", "Klar"], ["wolkig", "Wolkig"], ["regen", "Regen"], ["schnee", "Schnee"], ["nebel", "Nebel"]]

## Form und Größe in Stufen → Felder (Breite × Tiefe, je 0,5 m).
const FORMEN := [["quadrat", "Quadratisch"], ["breit", "Breit"], ["tief", "Tief"]]
const GROESSEN := [["klein", "Klein"], ["mittel", "Mittel"], ["gross", "Groß"], ["riesig", "Sehr groß"]]
const RAUM_MASSE := {
	"quadrat": [[10, 10], [12, 12], [14, 14], [18, 18]],
	"breit": [[12, 8], [14, 10], [18, 12], [20, 14]],
	"tief": [[8, 12], [10, 14], [12, 18], [14, 20]],
}

## Wände aus Zimmer-Fassung 1 („wand“: eine Kennung für alle Wände).
const ALTE_WAENDE := {
	"creme": ["anstrich", "#e8e0d1"], "salbei": ["anstrich", "#a9b49b"], "terrakotta": ["anstrich", "#c98c6b"],
	"nachtblau": ["anstrich", "#3b4a63"], "altrosa": ["anstrich", "#d6b0a6"], "paneel": ["paneel", "#e8e0d1"],
}
const ALTE_BOEDEN := {
	"eiche": ["dielen", "#c29466"], "walnuss": ["dielen", "#7a5236"], "hell": ["dielen", "#dcc7a6"],
	"teppichboden": ["teppichboden", "#c2b3a0"], "fliesen": ["fliesen", "#c27a55"],
}
const BODEN_STD := { "dielen": "#c29466", "landhaus": "#b48a5f", "fischgrat": "#a87c52", "fliesen": "#c27a55",
	"schachbrett": "#e9e3d8", "terrazzo": "#e3ddd2", "beton": "#9a9893", "teppichboden": "#c2b3a0", "marmor": "#ece8e1" }
const BODEN_STD2 := { "schachbrett": "#2b2c30", "terrazzo": "#b0603c", "fliesen": "#d2c9bc", "marmor": "#8d8a86" }


static func wahl(v: Variant, liste: Array) -> String:
	if v is String:
		for p in liste:
			if str(p[0]) == v:
				return v
	return str(liste[0][0])


static func wahl_name(liste: Array, id: String) -> String:
	for p in liste:
		if str(p[0]) == id:
			return str(p[1])
	return ""


static func ganz(v: Variant, lo: int, hi: int, std: int) -> int:
	if v is int or (v is float and is_finite(v) and floorf(v) == v):
		return clampi(int(v), lo, hi)
	return std


static func std_wand() -> Dictionary:
	return { "m": "anstrich", "f": "#e8e0d1", "mu": "", "mf": "" }


static func std_licht() -> Dictionary:
	return { "z": "auto", "we": "klar", "st": "", "k": 2700, "h": 100, "lf": "", "fa": "#7a5cff" }


## Alles am Raum außer Möbeln und Größe, in Standardwerten.
static func std_raum() -> Dictionary:
	var w := {}
	for s in SEITEN:
		w[s] = std_wand()
	return {
		"waende": w,
		"boden": { "a": "dielen", "f": "#c29466", "f2": "" },
		"sockel": { "a": "schmal", "f": "#f1ede6" },
		"decke": { "a": "glatt", "f": "#efebe4" },
		"fenster": { "a": "sprossen", "g": 1, "v": "lang", "vf": "#e4d9c6", "rf": "#f3f0ea" },
		"tuer": { "a": "kassette", "f": "#efebe4", "p": "vorn", "gf": "messing" },
		"licht": std_licht(),
	}


static func pruefe_wand(v: Variant) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var std := std_wand()
	var f := farbe(d.get("f"))
	return { "m": wahl(d.get("m"), WANDMATERIAL), "f": f if f != "" else str(std.f), "mu": wahl(d.get("mu"), MUSTER), "mf": farbe(d.get("mf")) }


## Licht des Raums: Tageszeit, Wetter, gewählte Stimmung, Farbtemperatur und Helligkeit aller
## Lampen, eine gemeinsame Lampenfarbe (leer: jede Lampe ihre eigene) und die Farbe der LED-Leisten.
static func pruefe_licht(v: Variant) -> Dictionary:
	var std := std_licht()
	if v is String:
		return { "z": wahl(v, ZEITEN), "we": "klar", "st": "", "k": 2700, "h": 100, "lf": "", "fa": str(std.fa) }
	var d: Dictionary = v if v is Dictionary else {}
	var st: Variant = d.get("st", "")
	var fa := farbe(d.get("fa"))
	return {
		"z": wahl(d.get("z"), ZEITEN), "we": wahl(d.get("we"), WETTER),
		"st": st if st is String and (st == "" or kennung(st)) else "",
		"k": ganz(d.get("k"), 1800, 6500, 2700), "h": ganz(d.get("h"), 0, 200, 100),
		"lf": farbe(d.get("lf")), "fa": fa if fa != "" else str(std.fa),
	}


## Prüft die Gestaltung eines Raums (aus Fassung 2 oder umgerechnet aus Fassung 1) und gibt sie
## vollständig zurück; was fehlt oder falsch ist, steht auf Standard.
static func pruefe_raum_gestalt(d: Dictionary) -> Dictionary:
	var out := std_raum()
	# Wände: Fassung 1 hatte eine Kennung für alle, Fassung 2 je Wand.
	var wv: Variant = d.get("waende")
	if wv is Dictionary:
		for s in SEITEN:
			out.waende[s] = pruefe_wand((wv as Dictionary).get(s))
	elif d.get("wand") is String and ALTE_WAENDE.has(d.wand):
		var a: Array = ALTE_WAENDE[d.wand]
		for s in SEITEN:
			out.waende[s] = { "m": a[0], "f": a[1], "mu": "", "mf": "" }
	var bv: Variant = d.get("boden")
	if bv is String and ALTE_BOEDEN.has(bv):
		var b: Array = ALTE_BOEDEN[bv]
		out.boden = { "a": b[0], "f": b[1], "f2": "" }
	elif bv is Dictionary:
		var bd: Dictionary = bv
		var a2 := wahl(bd.get("a"), BODENARTEN)
		var f := farbe(bd.get("f"))
		out.boden = { "a": a2, "f": f if f != "" else str(BODEN_STD.get(a2, "#c29466")), "f2": farbe(bd.get("f2")) }
	var sv: Variant = d.get("sockel")
	if sv is Dictionary:
		var f2 := farbe((sv as Dictionary).get("f"))
		out.sockel = { "a": wahl((sv as Dictionary).get("a"), SOCKEL), "f": f2 if f2 != "" else "#f1ede6" }
	var dv: Variant = d.get("decke")
	if dv is Dictionary:
		var f3 := farbe((dv as Dictionary).get("f"))
		out.decke = { "a": wahl((dv as Dictionary).get("a"), DECKEN), "f": f3 if f3 != "" else "#efebe4" }
	var fv: Variant = d.get("fenster")
	if fv is Dictionary:
		var fd: Dictionary = fv
		var vf := farbe(fd.get("vf"))
		var rf := farbe(fd.get("rf"))
		out.fenster = { "a": wahl(fd.get("a"), FENSTERARTEN), "g": ganz(fd.get("g"), 0, FENSTERGROESSEN.size() - 1, 1),
			"v": wahl(fd.get("v"), VORHAENGE), "vf": vf if vf != "" else "#e4d9c6", "rf": rf if rf != "" else "#f3f0ea" }
	var tv: Variant = d.get("tuer")
	if tv is Dictionary:
		var td: Dictionary = tv
		var tf := farbe(td.get("f"))
		out.tuer = { "a": wahl(td.get("a"), TUERARTEN), "f": tf if tf != "" else "#efebe4", "p": wahl(td.get("p"), TUERPLAETZE),
			"gf": wahl(td.get("gf"), GRIFF_FARBEN) }
	out.licht = pruefe_licht(d.get("licht"))
	return out


# --- Licht der Lampen ----------------------------------------------------------------------------

## Stimmungen: setzen Tageszeit, Wetter, Farbtemperatur, Helligkeit, gemeinsame Lampenfarbe und
## LED-Farbe auf einmal. Eigene Stimmungen speichert das Zimmer als Kopie des Lichts.
const STIMMUNGEN := [
	["gemuetlich", "Gemütlich", { "z": "abend", "we": "klar", "k": 2400, "h": 95, "lf": "", "fa": "#e7c27d" }],
	["kino", "Kino", { "z": "nacht", "we": "klar", "k": 2200, "h": 16, "lf": "", "fa": "#34425e" }],
	["neon", "Neon-Nacht", { "z": "nacht", "we": "regen", "k": 2700, "h": 48, "lf": "#ff4fa3", "fa": "#2fd6ff" }],
	["morgen", "Morgen", { "z": "morgen", "we": "klar", "k": 4000, "h": 40, "lf": "", "fa": "#f0e3a0" }],
	["tag", "Heller Tag", { "z": "tag", "we": "wolkig", "k": 4500, "h": 60, "lf": "", "fa": "#e8e0d1" }],
	["winter", "Winterabend", { "z": "abend", "we": "schnee", "k": 2300, "h": 110, "lf": "", "fa": "#e7c27d" }],
]
const MAX_STIMMUNGEN := 12


static func stimmung(id: String) -> Dictionary:
	for s in STIMMUNGEN:
		if str(s[0]) == id:
			return s[2]
	return {}


## Lampe: Farbtemperatur in Kelvin → Lichtfarbe (Näherung nach Tanner Helland, ruhig gerundet).
static func kelvin_farbe(k: float) -> Color:
	var t := clampf(k, 1000.0, 12000.0) / 100.0
	var r := 1.0
	var g: float
	var b: float
	if t <= 66.0:
		g = clampf((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0)
	else:
		r = clampf(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0)
		g = clampf(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0)
	if t >= 66.0:
		b = 1.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = clampf((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0)
	return Color(r, g, b)


static func pruefe_lampe(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var out := {}
	var k := ganz(d.get("k"), 1800, 6500, 0)
	if k > 0:
		out["k"] = k
	var c := farbe(d.get("c"))
	if c != "":
		out["c"] = c
	if d.has("h"):
		out["h"] = ganz(d.get("h"), 0, 200, 100)
	if d.has("w"):
		out["w"] = ganz(d.get("w"), 50, 200, 100)
	return out


# --- Regale --------------------------------------------------------------------------------------

const SORTIERUNGEN := [["zuletzt", "Zuletzt gespielt"], ["titel", "Titel A–Z"], ["system", "System"], ["spielzeit", "Spielzeit"],
	["backlog", "Backlog-Status"], ["genre", "Genre"], ["neu", "Zuletzt hinzugefügt"], ["manuell", "Eigene Reihenfolge"]]
const DARSTELLUNGEN := [["gemischt", "Gemischt"], ["ruecken", "Nur Rücken"], ["cover", "Cover nach vorn"]]
const DEKO := [["wenig", "Etwas Deko"], ["viel", "Viel Deko"], ["keine", "Keine Deko"]]
const HUELLEN := [["auto", "Wie das System"], ["dvd", "DVD-Hülle"], ["jewel", "CD-Hülle"], ["klein", "Kleine Hülle"], ["modul", "Modul"]]
const POKAL_SORT := [["stufe", "Stufe"], ["anteil", "Fortschritt"], ["titel", "Titel A–Z"], ["spielzeit", "Spielzeit"]]
const POKAL_FILTER := [["alle", "Alle Pokale"], ["ab_gold", "Ab Gold"], ["platin", "Nur Platin"]]
const PLATTEN_SORT := [["quelle", "Wie die Quelle"], ["name", "Name"]]
const PLATTEN_DARST := [["kiste", "Hintereinander, Cover vorn"], ["ruecken", "Nebeneinander wie Bücher"]]
## Auswahl der Spiele: feste Arten, manche mit einem Wert (System, Ordner, Liste, Tag, Sammlung,
## Backlog-Status, Genre). Werte werden nur mit Bibliotheksdaten verglichen. „eigene“ (Standard): nur
## die eingeräumten Spiele (ma) – ein neues Regal ist leer, was nicht passt, fällt auf leer zurück.
const FILTER_ARTEN := ["eigene", "alle", "installiert", "favoriten", "ungespielt", "system", "systeme", "ordner", "liste", "tag", "sammlung", "status", "genre"]
const FILTER_STD := "eigene"
const FILTER_OHNE_WERT := ["eigene", "alle", "installiert", "favoriten", "ungespielt"]
const MAX_REIHE := 600
const MAX_WERT := 64
const MAX_SYSTEME := 12             ## so viele Systeme zugleich („systeme:a,b“)
const MAX_FACH := 31                ## Fach-Index von Hand (pl), -1: oben auf dem Regal
const LAGEN := ["liegend", "vorn"]  ## Lage von Hand (lg); ohne Eintrag: stehend


## Text aus fremden Daten (Namen eigener Möbel reisen in geteilten Zimmern mit): druckbar, gekürzt, ohne
## Steuerzeichen und ohne Zeichen, die die Schreibrichtung umdrehen (Fremd.sauber – derselbe Filter wie für
## alle fremden Namen; vorher fielen hier nur die Zeichen unter 32 und 127 weg).
static func text(v: Variant, laenge: int) -> String:
	if not (v is String):
		return ""
	var out := ""
	for ch in Fremd.sauber((v as String).strip_edges()):
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, laenge).strip_edges()


static func pruefe_filter(v: Variant) -> String:
	if not (v is String):
		return FILTER_STD
	var s: String = v
	var art := s.get_slice(":", 0)
	if not (art in FILTER_ARTEN):
		return FILTER_STD
	if art in FILTER_OHNE_WERT:
		return art
	if art == "systeme":
		# Mehrere Systeme: Kennungen, sortiert, ohne Doppelte; eins allein ist „system:a“.
		var ids: Array = []
		for x in s.substr(art.length() + 1).split(",", false):
			var k := x.strip_edges()
			if kennung(k) and not (k in ids) and ids.size() < MAX_SYSTEME:
				ids.append(k)
		ids.sort()
		if ids.is_empty():
			return FILTER_STD
		return "system:%s" % ids[0] if ids.size() == 1 else "systeme:%s" % ",".join(ids)
	var wert := text(s.substr(art.length() + 1), MAX_WERT)
	return "%s:%s" % [art, wert] if wert != "" else FILTER_STD


static func pruefe_regal(v: Variant, t: String) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var out := {}
	match t:
		"spieleregal":
			# Ohne Angabe: eingeräumt in deiner Reihenfolge (leer, bis du einräumst).
			out["so"] = wahl(d.get("so", "manuell"), SORTIERUNGEN)
			out["fi"] = pruefe_filter(d.get("fi"))
			out["da"] = wahl(d.get("da"), DARSTELLUNGEN)
			out["ab"] = d.get("ab") if d.get("ab") is bool else true
			out["de"] = wahl(d.get("de"), DEKO)
			var ma: Variant = d.get("ma")
			if ma is Array:
				var reihe: Array = []
				for g in (ma as Array).slice(0, MAX_REIHE):
					var gid := text(g, 96)
					if gid != "" and not (gid in reihe):
						reihe.append(gid)
				if not reihe.is_empty():
					out["ma"] = reihe
			# Von Hand umgestellt: Fach je Spiel (pl) und Lage (lg) – nur mit eigener Reihenfolge.
			if out.so == "manuell":
				var pl := pruefe_plaetze(d.get("pl"))
				if not pl.is_empty():
					out["pl"] = pl
					var lg := pruefe_lagen(d.get("lg"), pl)
					if not lg.is_empty():
						out["lg"] = lg
		"trophaeenschrank":
			out["so"] = wahl(d.get("so"), POKAL_SORT)
			out["fi"] = wahl(d.get("fi"), POKAL_FILTER)
		"plattenregal":
			out["so"] = wahl(d.get("so"), PLATTEN_SORT)
			out["da"] = wahl(d.get("da"), PLATTEN_DARST)
		_:
			return {}
	return out


## Fach je Spiel-ID (von Hand umgestellt): ganze Zahlen -1 (oben auf dem Regal) bis MAX_FACH.
static func pruefe_plaetze(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in (v as Dictionary).keys():
		if out.size() >= MAX_REIHE:
			break
		var gid := text(k, 96)
		var f: Variant = (v as Dictionary)[k]
		if gid != "" and (f is int or f is float) and int(f) >= -1 and int(f) <= MAX_FACH:
			out[gid] = int(f)
	return out


## Lage je Spiel-ID: „liegend“ oder „vorn“ (nur Spiele mit Fach).
static func pruefe_lagen(v: Variant, pl: Dictionary) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in (v as Dictionary).keys():
		var gid := text(k, 96)
		var l: Variant = (v as Dictionary)[k]
		if pl.has(gid) and l is String and l in LAGEN:
			out[gid] = l
	return out


static func std_regal(t: String) -> Dictionary:
	return pruefe_regal({}, t)


## Hüllen je System (gilt für alle Regale): System-Kennung → Hüllenart.
static func pruefe_huellen(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in (v as Dictionary).keys():
		if out.size() >= 64:
			break
		if k is String and kennung(k):
			var a := wahl((v as Dictionary)[k], HUELLEN)
			if a != "auto":
				out[k] = a
	return out


# --- Baukasten ------------------------------------------------------------------------------------

## Bauteile für eigene Möbel: alles eigene Formen, keine fremden Modelle. Maße in Zentimetern.
const BAUTEILE := [["platte", "Brett"], ["kasten", "Kasten"], ["kissen", "Kissen"], ["walze", "Zylinder"],
	["kugel", "Kugel"], ["bein", "Bein"], ["stange", "Stange"], ["schirm", "Lampenschirm"], ["leuchte", "Leuchtkugel"],
	["griff", "Griff"], ["bogen", "Bogen"]]
const BAUTEIL_STD := {
	"platte": [80, 3, 50], "kasten": [60, 40, 40], "kissen": [50, 14, 50], "walze": [30, 40, 30], "kugel": [24, 24, 24],
	"bein": [4, 40, 4], "stange": [2, 120, 2], "schirm": [36, 26, 36], "leuchte": [16, 16, 16], "griff": [12, 2, 2], "bogen": [60, 60, 4],
}
const MAX_EIGENE := 24
const MAX_TEILE := 48
const EBENEN_EIGEN := [["boden", "Steht auf dem Boden"], ["klein", "Steht auf Tischen"], ["wand", "Hängt an der Wand"]]
const EIGEN_PRAEFIX := "e_"


static func kennung(s: String) -> bool:
	if s.length() < 1 or s.length() > 24:
		return false
	for ch in s:
		if not (ch in "abcdefghijklmnopqrstuvwxyz0123456789_-"):
			return false
	return true


static func pruefe_teil(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var a := wahl(d.get("a"), BAUTEILE)
	if not (d.get("a") is String) or a != d.a:
		return {}
	var std: Array = BAUTEIL_STD[a]
	var out := {
		"a": a,
		"x": ganz(d.get("x"), -200, 200, 0), "y": ganz(d.get("y"), 0, 260, 0), "z": ganz(d.get("z"), -200, 200, 0),
		"b": ganz(d.get("b"), 1, 400, int(std[0])), "h": ganz(d.get("h"), 1, 260, int(std[1])), "t": ganz(d.get("t"), 1, 400, int(std[2])),
		"r": int(floorf(ganz(d.get("r"), 0, 345, 0) / 15.0)) * 15,
	}
	var f := farbe(d.get("f"))
	if f != "":
		out["f"] = f
	if d.get("m") is String and MATERIALIEN.has(d.m):
		out["m"] = d.m
	var mu := wahl(d.get("mu"), MUSTER)
	if mu != "":
		out["mu"] = mu
	return out


## Ein eigenes Möbel: Kennung „e_…“, Name, Ebene, Grundfläche in Feldern und seine Teile.
static func pruefe_eigenes(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var id: Variant = d.get("id")
	if not (id is String) or not kennung(id) or not (id as String).begins_with(EIGEN_PRAEFIX) or (id as String).length() < 3:
		return {}
	var teile: Array = []
	var tv: Variant = d.get("teile")
	if tv is Array:
		for t in (tv as Array).slice(0, MAX_TEILE):
			var teil := pruefe_teil(t)
			if not teil.is_empty():
				teile.append(teil)
	if teile.is_empty():
		return {}
	var name := text(d.get("name"), 40)
	return {
		"id": id, "name": name if name != "" else "Eigenes Möbel",
		"ebene": wahl(d.get("ebene"), EBENEN_EIGEN),
		"w": ganz(d.get("w"), 1, 8, 2), "d": ganz(d.get("d"), 1, 8, 2),
		"teile": teile,
	}


## Grundfläche in Feldern (0,5 m) aus den Teilen: was übersteht, bekommt ein Feld mehr.
static func eigen_masse(teile: Array) -> Vector2i:
	var x0 := 0.0
	var x1 := 0.0
	var z0 := 0.0
	var z1 := 0.0
	for t in teile:
		var r := deg_to_rad(float(t.r))
		var hb := float(t.b) * 0.5
		var ht := float(t.t) * 0.5
		var ex := absf(cos(r)) * hb + absf(sin(r)) * ht
		var ez := absf(sin(r)) * hb + absf(cos(r)) * ht
		x0 = minf(x0, float(t.x) - ex)
		x1 = maxf(x1, float(t.x) + ex)
		z0 = minf(z0, float(t.z) - ez)
		z1 = maxf(z1, float(t.z) + ez)
	var w := maxf(absf(x0), absf(x1)) * 2.0
	var d := maxf(absf(z0), absf(z1)) * 2.0
	return Vector2i(clampi(ceili((w - 2.0) / 50.0), 1, 8), clampi(ceili((d - 2.0) / 50.0), 1, 8))


static func pruefe_stimmung(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var id: Variant = d.get("id")
	if not (id is String) or not kennung(id):
		return {}
	var name := text(d.get("name"), 30)
	var l := pruefe_licht(d.get("licht"))
	l.st = ""
	return { "id": id, "name": name if name != "" else "Eigene Stimmung", "licht": l }

extends RefCounted
## Deine Figur und dein Haustier als reine Daten (Punkt 131 c): ein festes, kleines Schema aus
## lauter Kennungen der eingebauten Listen. Einziger Freitext ist der Name des Haustiers (höchstens
## MAX_NAME Zeichen, nur Buchstaben, Ziffern, Leerzeichen und - ' .). Nichts wird ausgeführt oder
## als Godot-Ressource geladen; Feld für Feld geprüft, Unbekanntes fällt weg, Ungültiges wird zum
## Standard.
##
## Gespeichert in zimmer/zimmer.json (Fassung 2, zimmer_daten.gd) neben den Räumen:
##   "figur": { <feld>: <kennung aus FIGUR_FELDER> … }
##   "tier":  { "art", "fell", "muster", "halsband": <kennung>, "name": "…" }
##   "gemeldet": [<meilenstein-id>, …]      ← nur lokal: welche Freischaltungen schon gemeldet sind
## Für Gäste (später) ein eigenes, kleines Paket (fuer_gaeste, pruefe): nur Figur und Haustier,
##   { "format": "uzai-figur", "version": 1, "figur": {…}, "tier": {…} } – ohne den Spielstand.
##
## Farben sind Kennungen aus festen Paletten (keine freien Farbwerte) – auch das hält das Schema
## klein und sicher. Ohne Fenster testbar (tests/logic_zfigur.gd).

const Fremd := preload("res://src/core/fremd.gd")

const FORMAT := "uzai-figur"
const VERSION := 1
const MAX_BYTES := 16 * 1024
const MAX_NAME := 16
const MAX_GEMELDET := 64

# --- Paletten --------------------------------------------------------------------------------------

const FELL := [
	["orange", "Orange", "#d88a49"], ["creme", "Creme", "#e8d3ad"], ["weiss", "Weiß", "#f2ede6"], ["grau", "Grau", "#8f8c89"],
	["schwarz", "Schwarz", "#2e2b2a"], ["braun", "Braun", "#86593b"], ["rotbraun", "Rotbraun", "#b2552b"], ["sand", "Sand", "#c9a879"],
	["mint", "Mint", "#8cc7ad"], ["lila", "Lila", "#9a86c4"], ["himmel", "Himmelblau", "#86aed6"],
]

# --- Auswahl je Feld -----------------------------------------------------------------------------------

## Die Menschen zur Wahl (figur_psx.gd, assets/figur/psx): [kennung, Name, Art w/m]. Die letzten
## sechs schalten Meilensteine frei (meilensteine.gd).
const PERSONEN := [
	["lea", "Lea", "w"], ["mia", "Mia", "w"], ["emma", "Emma", "w"], ["zoe", "Zoe", "w"], ["nora", "Nora", "w"], ["ida", "Ida", "w"],
	["lina", "Lina", "w"], ["mara", "Mara", "w"], ["ella", "Ella", "w"], ["ben", "Ben", "m"], ["noah", "Noah", "m"], ["elias", "Elias", "m"],
	["luis", "Luis", "m"], ["paul", "Paul", "m"], ["theo", "Theo", "m"], ["finn", "Finn", "m"], ["juna", "Juna", "w"], ["leon", "Leon", "m"],
	["max", "Max", "m"], ["sara", "Sara", "w"], ["jonas", "Jonas", "m"], ["nele", "Nele", "w"],
]

const TIER_ARTEN := [["katze", "Katze"], ["hund", "Hund"], ["fuchs", "Fuchs"], ["hase", "Hase"], ["drache", "Kleiner Drache"]]
const TIER_MUSTER := [["uni", "Einfarbig"], ["bauch", "Heller Bauch"], ["getigert", "Getigert"], ["gefleckt", "Gefleckt"], ["pfoten", "Weiße Pfoten"],
		["sterne", "Sternenfell"]]
const HALSBAND := [["keins", "Keins"], ["band", "Halsband mit Glöckchen"], ["tuch", "Halstuch"]]

## Felder der Figur: [feld, Überschrift, Typ, Optionen [[kennung, Name], …] bzw. Palette, Standard]
## in der Reihenfolge des Editors; Typ „p“ = Palette (Farbfelder), „o“ = Optionen. Was ein
## Meilenstein freischaltet, steht in meilensteine.gd.
const FIGUR_FELDER := [
	["person", "Figur", "o", PERSONEN, "lea"],
]
const TIER_FELDER := [
	["art", "Art", "o", TIER_ARTEN, "katze"],
	["fell", "Fell", "p", FELL, "orange"],
	["muster", "Muster", "o", TIER_MUSTER, "bauch"],
	["halsband", "Halsband", "o", HALSBAND, "band"],
]
const TIER_NAME := "Mochi"


# --- Standard und Gast-Paket ---------------------------------------------------------------------------

static func standard_figur() -> Dictionary:
	var f := {}
	for e in FIGUR_FELDER:
		f[str(e[0])] = str(e[4])
	return f


static func standard_tier() -> Dictionary:
	var t := { "name": TIER_NAME }
	for e in TIER_FELDER:
		t[str(e[0])] = str(e[4])
	return t


static func standard() -> Dictionary:
	return { "format": FORMAT, "version": VERSION, "figur": standard_figur(), "tier": standard_tier() }


## Text eines Gast-Pakets (JSON) → geprüft, {} wenn es keins ist.
static func aus_text(text: String) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {}
	return pruefe(Fremd.json_roh(text))


## Was Gäste später sehen dürfen: nur Figur und Haustier, ohne den eigenen Spielstand. daten:
## das Zimmer (zimmer_daten.gd) oder ein Paket.
static func fuer_gaeste(daten: Dictionary) -> Dictionary:
	return { "format": FORMAT, "version": VERSION, "figur": pruefe_figur(daten.get("figur")), "tier": pruefe_tier(daten.get("tier")) }


# --- Prüfen ----------------------------------------------------------------------------------------------

## Gast-Paket streng prüfen: nur bekannte Felder, nur Kennungen aus den Listen. {} wenn es keins ist.
static func pruefe(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	if not (d.get("format") is String) or str(d.format) != FORMAT:
		return {}
	var ver: Variant = d.get("version")
	if not ((ver is int or ver is float) and is_finite(float(ver)) and int(ver) >= 1 and int(ver) <= VERSION):
		return {}
	return { "format": FORMAT, "version": VERSION, "figur": pruefe_figur(d.get("figur")), "tier": pruefe_tier(d.get("tier")) }


## Schon gemeldete Meilensteine: nur Kennungen, ohne Doppelte, begrenzt.
static func pruefe_gemeldet(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e in (v as Array).slice(0, MAX_GEMELDET):
			if e is String and _kennung(e) and not (e in out):
				out.append(e)
	return out


static func pruefe_figur(v: Variant) -> Dictionary:
	return _felder(v, FIGUR_FELDER)


static func pruefe_tier(v: Variant) -> Dictionary:
	var t := _felder(v, TIER_FELDER)
	t["name"] = name_sauber((v as Dictionary).get("name") if v is Dictionary else null)
	return t


static func _felder(v: Variant, felder: Array) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	var out := {}
	for e in felder:
		var k := str(e[0])
		var w: Variant = d.get(k)
		out[k] = w if (w is String and gueltig(e[3], w)) else str(e[4])
	return out


static func gueltig(liste: Array, id: String) -> bool:
	for p in liste:
		if str(p[0]) == id:
			return true
	return false


## Name des Haustiers: nur Buchstaben (auch Umlaute und andere Schriften), Ziffern, Leerzeichen,
## Bindestrich, Apostroph und Punkt; keine Steuer- oder Formatzeichen; höchstens MAX_NAME Zeichen.
static func name_sauber(v: Variant) -> String:
	if not (v is String):
		return TIER_NAME
	var out := ""
	var leer := false
	for ch in (v as String).strip_edges():
		var c := ch.unicode_at(0)
		var ok := ch in " -'." or (c >= 48 and c <= 57) or _buchstabe(c)
		if not ok:
			continue
		if ch == " ":
			if leer or out == "":
				continue
			leer = true
		else:
			leer = false
		out += ch
		if out.length() >= MAX_NAME:
			break
	out = out.strip_edges()
	return out if out != "" else TIER_NAME


## Buchstabe: lateinisch (mit Akzenten), griechisch, kyrillisch, CJK, Hangul, Kana, Arabisch,
## Hebräisch, Devanagari, Thai. Keine Zeichen zur Schreibrichtung, keine Emojis, kein Unsichtbares.
static func _buchstabe(c: int) -> bool:
	if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
		return true
	if c >= 0xC0 and c <= 0x24F and c != 0xD7 and c != 0xF7:
		return true
	for b in [[0x370, 0x3FF], [0x400, 0x4FF], [0x5D0, 0x5EA], [0x620, 0x64A], [0x900, 0x97F], [0xE01, 0xE3A],
			[0x3041, 0x3096], [0x30A1, 0x30FA], [0x4E00, 0x9FFF], [0xAC00, 0xD7A3]]:
		if c >= int(b[0]) and c <= int(b[1]):
			return true
	return false


static func _kennung(s: String) -> bool:
	if s.length() < 1 or s.length() > 24:
		return false
	for ch in s:
		if not (ch in "abcdefghijklmnopqrstuvwxyz0123456789_"):
			return false
	return true


# --- Nachschlagen ------------------------------------------------------------------------------------

static func feld(felder: Array, k: String) -> Array:
	for e in felder:
		if str(e[0]) == k:
			return e
	return []


## Ein Wert eines Listeneintrags (Stelle stelle) nach Kennung, sonst standard.
static func feld_von(liste: Array, id: String, stelle: int, standard: Variant) -> Variant:
	for p in liste:
		if str(p[0]) == id and (p as Array).size() > stelle:
			return p[stelle]
	return standard


static func name_von(liste: Array, id: String) -> String:
	for p in liste:
		if str(p[0]) == id:
			return str(p[1]) if not str(p[1]).begins_with("#") else ""
	return ""


## Farbe einer Kennung aus einer Palette (an letzter Stelle des Eintrags).
static func farbe(liste: Array, id: String) -> Color:
	for p in liste:
		if str(p[0]) == id:
			return Color(str(p[p.size() - 1]))
	return Color(str(liste[0][liste[0].size() - 1]))

extends RefCounted
## Room templates (item 131): a few ready-made room setups to start with, plain data in the same
## schema as zimmer.json, strictly validated when applied (zimmer_daten.gd). A template fully replaces
## whatever is already set up in the room; Undo restores the previous state. Only bright rooms
## (the cinema corner and neon cave templates were removed).

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")

const LISTE := [
	["gemuetlich", "Gemütliches Wohnzimmer", "Warme Hölzer, Salbei und Senf, Lichterkette am Abend"],
	["skandi", "Hell und skandinavisch", "Esche, Kreideweiß, Bouclé und viel Grün"],
	["loft", "Loft", "Ziegel, Beton, Leder und schwarzes Metall"],
	["retro", "Retro-Kinderzimmer", "Röhrenfernseher, Tapete mit Punkten, bunte Lichter"],
]


static func name_of(id: String) -> String:
	for v in LISTE:
		if str(v[0]) == id:
			return str(v[1])
	return ""


static func _m(t: String, x: int, z: int, r := 0, v := "", extra := {}) -> Dictionary:
	var it := { "t": t, "x": x, "z": z, "r": r, "v": v if v != "" else Katalog.std_variante(t), "an": true }
	it.merge(extra, true)
	return it


static func _waende(f: String, m := "anstrich", mu := "", mf := "") -> Dictionary:
	var out := {}
	for s in G.SEITEN:
		out[s] = { "m": m, "f": f, "mu": mu, "mf": mf }
	return out


## Ein Raum der Vorlage (geprüft), leer bei unbekannter Kennung. id des Raums bleibt raum_id.
static func raum(id: String, raum_id := "zimmer", name := "Mein Zimmer") -> Dictionary:
	var r := roh(id)
	if r.is_empty():
		return {}
	r["id"] = raum_id
	r["name"] = name
	return Daten.pruefe_raum(r)


## Die Vorlage ungeprüft (für den Test: kein Möbel darf beim Prüfen wegfallen).
static func roh(id: String) -> Dictionary:
	var r := {}
	match id:
		"gemuetlich":
			r = Daten.standard_raum()
		"skandi":
			r = G.std_raum()
			r.merge({ "w": 12, "d": 10 }, true)
			r.waende = _waende("#f3efe7")
			r.waende.hinten = { "m": "paneel", "f": "#f3efe7", "mu": "", "mf": "#a9b49b" }
			r.boden = { "a": "landhaus", "f": "#dcc7a6", "f2": "" }
			r.sockel = { "a": "hoch", "f": "#f3efe7" }
			r.fenster = { "a": "raster", "g": 2, "v": "gardine", "vf": "#e8e0d1", "rf": "#f3efe7" }
			r.licht = { "z": "tag", "we": "klar", "st": "", "k": 3000, "h": 90, "lf": "", "fa": "#e8e0d1" }
			r.moebel = [
				_m("teppich", 3, 3, 0, "creme", { "m": "boucle", "f": "#e8e0d1" }),
				_m("spieleregal", 0, 0, 0, "weiss", { "m": "esche" }),
				_m("medienwand", 4, 0, 0, "flach", { "m": "esche", "be": "rund" }),
				_m("pflanze", 3, 0, 0, "olive", { "f2": "#d9cbb3" }),
				_m("pflanze", 8, 0, 0, "monstera", { "f2": "#f3efe7" }),
				_m("spieleregal", 9, 0, 0, "weiss", { "m": "esche" }),
				_m("plattenregal", 0, 4, 1, "weiss", { "m": "esche" }),
				_m("plattenspieler", 0, 4, 1, "weiss"),
				_m("sessel", 1, 7, 1, "creme", { "m": "boucle", "f": "#f3efe7", "be": "rund" }),
				_m("stehlampe", 0, 9, 0, "creme", { "f2": "#f3efe7", "m2": "lack_matt" }),
				_m("couchtisch", 5, 4, 0, "weiss", { "m": "esche", "be": "rund" }),
				_m("topfpflanze", 5, 4, 0, "kaktus", { "f2": "#f3efe7" }),
				_m("sofa", 4, 7, 2, "salbei", { "m": "leinen", "f": "#a9b49b", "be": "rund" }),
				_m("beistelltisch", 8, 8, 0, "weiss", { "m": "esche" }),
				_m("tischlampe", 8, 8, 2, "creme"),
				_m("trophaeenschrank", 11, 2, 3, "weiss", { "m": "esche" }),
				_m("schreibtisch", 10, 5, 3, "weiss", { "m": "esche", "gr": "leiste" }),
				_m("deckenlampe", 5, 4, 0, "creme"),
				_m("bild", 11, 5, 3, "wellen", { "f2": "#f3efe7", "m2": "lack_matt" }),
				_m("bild", 0, 7, 1, "punkte", { "f2": "#c9a173", "m2": "esche" }),
				_m("wanduhr", 9, 0, 0, "weiss"),
			]
		"loft":
			r = G.std_raum()
			r.merge({ "w": 14, "d": 10 }, true)
			r.waende = _waende("#d9cbb3", "kalk")
			r.waende.hinten = { "m": "ziegel", "f": "#9c5a40", "mu": "", "mf": "" }
			r.waende.rechts = { "m": "beton", "f": "#a3a19c", "mu": "", "mf": "" }
			r.boden = { "a": "beton", "f": "#8f8d88", "f2": "" }
			r.sockel = { "a": "keine", "f": "#2b2c30" }
			r.decke = { "a": "balken", "f": "#e8e0d1" }
			r.fenster = { "a": "raster", "g": 3, "v": "keine", "vf": "#4b4d52", "rf": "#26272b" }
			r.tuer = { "a": "landhaus", "f": "#3a3330", "p": "vorn", "gf": "schwarz" }
			r.licht = { "z": "abend", "we": "wolkig", "st": "", "k": 2500, "h": 100, "lf": "", "fa": "#e7c27d" }
			r.moebel = [
				_m("teppich", 4, 3, 0, "graphit", { "f": "#4b4d52", "mu": "fischgrat", "mf": "#7d7a76" }),
				_m("spieleregal", 0, 0, 0, "schwarz", { "m": "metall", "f": "#26272b", "s": 2 }),
				_m("lautsprecher", 5, 0, 0, "schwarz"),
				_m("medienwand", 6, 0, 0, "flach", { "m": "raeuchereiche", "be": "haarnadel" }),
				_m("lautsprecher", 10, 0, 0, "schwarz"),
				_m("pflanze", 11, 0, 0, "monstera", { "f2": "#26272b" }),
				_m("led_leiste", 4, 0, 0, "oben", { "s": 2 }),
				_m("plattenregal", 0, 5, 1, "schwarz", { "m": "metall", "f": "#26272b" }),
				_m("plattenspieler", 0, 5, 1, "schwarz"),
				_m("sessel", 1, 8, 1, "terrakotta", { "m": "leder", "f": "#7a4a2e", "be": "kufen" }),
				_m("stehlampe", 0, 4, 0, "graphit", { "f": "#26272b", "m2": "metall", "f2": "#26272b" }),
				_m("couchtisch", 5, 4, 0, "schwarz", { "m": "beton", "be": "haarnadel" }),
				_m("buecher", 6, 4, 0, "senf"),
				_m("sofa", 4, 7, 2, "terrakotta", { "m": "leder", "f": "#8a5233", "s": 2, "be": "kufen" }),
				_m("beistelltisch", 9, 8, 0, "schwarz", { "m": "marmor", "m2": "metall", "f2": "#26272b" }),
				_m("tischlampe", 9, 8, 2, "graphit", { "f": "#26272b", "f2": "#b8925a", "m2": "messing" }),
				_m("trophaeenschrank", 13, 2, 3, "schwarz", { "m": "metall", "f": "#26272b", "gr": "leiste" }),
				_m("schreibtisch", 12, 5, 3, "schwarz", { "m": "raeuchereiche", "be": "haarnadel", "gr": "keine" }),
				_m("deckenlampe", 6, 4, 0, "graphit", { "f": "#26272b" }),
				_m("bild", 13, 6, 3, "sonne", { "s": 1, "f2": "#26272b", "m2": "metall" }),
				_m("wanduhr", 2, 0, 0, "schwarz"),
			]
		"retro":
			r = G.std_raum()
			r.merge({ "w": 10, "d": 10 }, true)
			r.waende = _waende("#f0e3a0", "tapete", "punkte", "#e7c27d")
			r.waende.hinten = { "m": "tapete", "f": "#8fb3b0", "mu": "streifen", "mf": "#a9c9c6" }
			r.boden = { "a": "teppichboden", "f": "#4f7f8f", "f2": "" }
			r.sockel = { "a": "hoch", "f": "#f3efe7" }
			r.fenster = { "a": "sprossen", "g": 1, "v": "kurz", "vf": "#b0603c", "rf": "#f3efe7" }
			r.tuer = { "a": "kassette", "f": "#b0603c", "p": "vorn", "gf": "messing" }
			r.licht = { "z": "tag", "we": "klar", "st": "", "k": 3000, "h": 100, "lf": "", "fa": "#ff4fa3" }
			r.moebel = [
				_m("teppich_rund", 3, 3, 0, "senf", { "mu": "karo", "mf": "#b0603c" }),
				_m("medienwand", 3, 0, 0, "roehre", { "m": "kirsche", "be": "kufen" }),
				_m("spieleregal", 0, 0, 0, "weiss",
					{ "m": "lack_glanz", "f": "#b0603c", "rg": { "da": "gemischt", "ab": true, "de": "viel" } }),
				_m("sitzsack", 3, 6, 2, "terrakotta", { "mu": "punkte", "mf": "#f0e3a0" }),
				_m("sitzsack", 5, 6, 2, "nachtblau", { "f": "#4f7f8f", "mu": "streifen", "mf": "#f3efe7" }),
				_m("lichterkette", 3, 0, 0, "bunt"),
				_m("buecherregal", 8, 0, 0, "weiss", { "m": "lack_glanz", "f": "#f0e3a0", "s": 0 }),
				_m("hocker", 7, 4, 0, "senf", { "m": "cord", "f": "#c4913c" }),
				_m("plattenregal", 0, 3, 1, "weiss", { "m": "lack_glanz", "f": "#4f7f8f" }),
				_m("plattenspieler", 0, 3, 1, "kirsche"),
				_m("trophaeenschrank", 9, 4, 3, "kirsche"),
				_m("pflanze", 9, 9, 0, "kaktus", { "f2": "#b0603c" }),
				_m("deckenlampe", 4, 4, 0, "senf", { "f": "#e7c27d" }),
				_m("bild", 0, 7, 1, "punkte"),
				_m("stehlampe", 0, 9, 0, "terrakotta"),
			]
	if not r.is_empty():
		r["id"] = "zimmer"
	return r

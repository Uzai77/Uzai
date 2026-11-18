extends RefCounted
## „Dein Zimmer“ als reine Daten (Punkt 131): Räume, Wände, Boden, Licht und Möbel in einem festen
## JSON-Schema. Nichts davon wird ausgeführt oder als Godot-Ressource geladen – die Datei wird mit
## JSON.parse_string gelesen, auf Größe begrenzt und Feld für Feld geprüft (prüfe). Was nicht passt,
## fällt weg; ist die Datei als Ganzes kaputt, gilt das Standardzimmer. So kann ein Zimmer später
## gefahrlos geteilt werden (Stufe 3) – es enthält nur Kennungen aus dem eingebauten Katalog.
##
## Schema (Fassung 2; Fassung 1 wird weiter gelesen und umgerechnet):
##   { "format": "uzai-zimmer", "version": 2, "aktuell": "<raum-id>", "raeume": [raum, …],
##     "eigene": [eigenes Möbel], "stimmungen": [eigene Stimmung], "farben": ["#rrggbb"],
##     "huellen": { System: Hüllenart },
##     "figur": Figur, "tier": Haustier, "gemeldet": [Meilenstein-id],   (figur/figur_daten.gd)
##     "vorlagen": [{ "id": "v_…", "name": "…", "raum": raum }],   (eigene Vorlagen, z. B. aus einem
##                  geteilten Zimmer – zimmer_teilen.gd; jeder Raum mit demselben Prüfer)
##     "regale": "eigen" }   Spieleregale füllst du selbst (gestalt.gd, Auswahl „eigene“). Fehlt der
##                  Vermerk (Zimmer von früher, alte geteilte Zimmer), räumt der Prüfer einmal alle
##                  Spieleregale leer (regale_leeren) – sonst ändert sich an keinem Möbel etwas.
##   raum = { "id": "[a-z0-9_-]{1,24}", "name": "…" (≤ 40 Zeichen), "w": 8..20, "d": 8..20,
##            "waende": { hinten|links|vorn|rechts: Wand }, "boden", "sockel", "decke", "fenster",
##            "tuer", "licht" (alles in gestalt.gd),
##            "moebel": [{ "t": Katalog-ID, "x": int, "z": int, "r": 0..3, "v": Variante, "an": bool,
##                         dazu freiwillig die Felder aus gestalt.gd (f, m, mu, s, l, rg …) }] }
##   Fassung 1 hatte „wand“, „boden“ und „licht“ als einfache Kennungen.
## Mehrere Räume sind vorbereitet (Liste), gebraucht wird vorerst einer.
##
## Ohne Fenster testbar (tests/logic_zimmer.gd): Prüfen, Belegung, Setzen, Drehen, Rückgängig.

const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const Fremd := preload("res://src/core/fremd.gd")

const FORMAT := "uzai-zimmer"
const VERSION := 2
const DATEI := "zimmer/zimmer.json"
const MAX_BYTES := 512 * 1024     ## größere Dateien werden gar nicht erst gelesen
const MAX_RAEUME := 8
const MAX_MOEBEL := 300
const MAX_NAME := 40
const MIN_FELDER := 8
const MAX_FELDER := 20
const MAX_SCHRITTE := 60           ## so weit reicht Rückgängig zurück
const MAX_VORLAGEN := 8            ## eigene Vorlagen (gespeicherte geteilte Zimmer)
const VORLAGE_PRAEFIX := "v_"
const REGALE_EIGEN := "eigen"      ## Vermerk „regale“: die Regale sind schon auf „selbst einräumen“ umgestellt

const ZEITEN := G.ZEITEN           ## eine Liste (gestalt.gd) – auch der Stempel des Netz-Protokolls rechnet mit ihr


# --- Standard ------------------------------------------------------------------------------------

## Das Zimmer beim ersten Betreten: gemütlich eingerichtet, alles Wichtige schon da.
static func standard_raum() -> Dictionary:
	var m := func(t: String, x: int, z: int, r := 0, v := "") -> Dictionary:
		return { "t": t, "x": x, "z": z, "r": r, "v": v if v != "" else Katalog.std_variante(t), "an": true }
	var raum := G.std_raum()
	raum.merge({
		"id": "zimmer", "name": "Mein Zimmer", "w": 12, "d": 10,
		# With walkways, so the room is not too crowded to walk through: two rows free in front of the TV, an aisle
		# to the left and right of the sofa, and one behind the sofa across the full width. Desk and gaming chair
		# stand in the back right corner instead of across the room (previously chair, desk, sofa and armchair stood
		# edge to edge, and the front right corner was cut off entirely). tests/logic_zimmer.gd checks the aisles.
		"moebel": [
			m.call("teppich", 2, 3, 0, "creme"),
			m.call("spieleregal", 0, 0),
			m.call("pflanze", 2, 0),
			m.call("lautsprecher", 3, 0),
			m.call("medienwand", 4, 0),
			m.call("lautsprecher", 8, 0),
			m.call("schreibtisch", 9, 0, 0, "eiche"),
			m.call("topfpflanze", 11, 1, 0, "olive"),
			m.call("gamingstuhl", 9, 2, 2, "graphit"),
			m.call("trophaeenschrank", 0, 2, 1),
			m.call("plattenregal", 0, 4, 1),
			m.call("plattenspieler", 0, 4, 1),
			m.call("topfpflanze", 0, 5, 1, "kaktus"),
			m.call("couchtisch", 4, 3),
			m.call("buecher", 4, 3, 0, "terrakotta"),
			m.call("vase_blumen", 5, 3),
			m.call("tasse", 6, 4),
			m.call("sessel", 1, 6, 1, "senf"),
			m.call("beistelltisch", 3, 7),
			m.call("tischlampe", 3, 7, 2),
			m.call("sofa", 4, 6, 2, "salbei"),
			m.call("sitzsack", 10, 5, 3, "terrakotta"),
			m.call("spieleregal", 11, 7, 3),
			m.call("stehlampe", 0, 9),
			m.call("kissen", 1, 9, 0, "senf"),
			m.call("jackenstaender", 11, 9, 2, "eiche"),
			m.call("deckenlampe", 5, 4),
			m.call("bild", 11, 5, 3, "sonne"),
			m.call("bild", 0, 7, 1, "huegel"),
			m.call("wanduhr", 9, 0, 0, "schwarz"),
			m.call("lichterkette", 4, 0, 0, "warm"),
			m.call("poster", 11, 3, 3, "wellen"),
		],
	})
	return raum


static func standard() -> Dictionary:
	return { "format": FORMAT, "version": VERSION, "aktuell": "zimmer", "raeume": [standard_raum()],
		"eigene": [], "stimmungen": [], "farben": [], "huellen": {},
		"figur": FD.standard_figur(), "tier": FD.standard_tier(), "gemeldet": [], "vorlagen": [], "regale": REGALE_EIGEN }


# --- Laden und Speichern ---------------------------------------------------------------------------

static func pfad() -> String:
	return Config.path(DATEI)


## Liest das Zimmer von der Platte; fehlt es oder taugt es nicht, das Standardzimmer.
static func laden(datei := "") -> Dictionary:
	var p := datei if datei != "" else pfad()
	for kandidat in [p, p + ".bak"]:
		var d := lesen(kandidat)
		if not d.is_empty():
			return d
	return standard()


## Eine Datei lesen und prüfen. {} bei fehlender, zu großer oder ungültiger Datei.
static func lesen(datei: String) -> Dictionary:
	if not FileAccess.file_exists(datei):
		return {}
	var f := FileAccess.open(datei, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return {}
	var text := f.get_as_text()
	f.close()
	return aus_text(text)


## Text (JSON) → geprüftes Zimmer, {} wenn es kein Zimmer ist.
static func aus_text(text: String) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {}
	var v: Variant = Fremd.json_roh(text)
	return pruefe(v)


static func speichern(daten: Dictionary, datei := "") -> bool:
	var sauber := pruefe(daten)
	if sauber.is_empty():
		return false
	return Config.write_json(datei if datei != "" else pfad(), sauber, "\t")


# --- Prüfen ------------------------------------------------------------------------------------------

## Streng prüfen: nur bekannte Felder mit dem richtigen Typ und Bereich; unbekannte Felder und
## ungültige Möbel fallen weg. {} wenn es gar kein Zimmer dieses Formats ist.
static func pruefe(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	if str(d.get("format", "")) != FORMAT:
		return {}
	var ver: Variant = d.get("version")
	if not _ganz(ver) or int(ver) < 1 or int(ver) > VERSION:
		return {}
	var rl: Variant = d.get("raeume")
	if not (rl is Array) or (rl as Array).is_empty():
		return {}
	# Eigene Möbel zuerst: die Räume dürfen sie benutzen.
	var eigene: Array = []
	var eids := {}
	var ev: Variant = d.get("eigene")
	if ev is Array:
		for e in (ev as Array).slice(0, G.MAX_EIGENE):
			var eg := G.pruefe_eigenes(e)
			if not eg.is_empty() and not eids.has(eg.id):
				eids[eg.id] = true
				eigene.append(eg)
	Katalog.eigene_setzen(eigene)
	var raeume: Array = []
	var ids := {}
	for r in (rl as Array).slice(0, MAX_RAEUME):
		var raum := pruefe_raum(r)
		if raum.is_empty() or ids.has(raum.id):
			continue
		ids[raum.id] = true
		raeume.append(raum)
	if raeume.is_empty():
		return {}
	var akt := str(d.get("aktuell", "")) if d.get("aktuell") is String else ""
	if not ids.has(akt):
		akt = str(raeume[0].id)
	var stimmungen: Array = []
	var sids := {}
	var sv: Variant = d.get("stimmungen")
	if sv is Array:
		for st in (sv as Array).slice(0, G.MAX_STIMMUNGEN):
			var s := G.pruefe_stimmung(st)
			if not s.is_empty() and not sids.has(s.id):
				sids[s.id] = true
				stimmungen.append(s)
	var farben: Array = []
	var fv: Variant = d.get("farben")
	if fv is Array:
		for f in (fv as Array).slice(0, G.MAX_EIGENE_FARBEN):
			var c := G.farbe(f)
			if c != "" and not (c in farben):
				farben.append(c)
	var vorlagen: Array = []
	var vids := {}
	var vv: Variant = d.get("vorlagen")
	if vv is Array:
		for e in (vv as Array).slice(0, MAX_VORLAGEN):
			var vl := pruefe_vorlage(e)
			if not vl.is_empty() and not vids.has(vl.id):
				vids[vl.id] = true
				vorlagen.append(vl)
	# Einmal beim Umstieg: Regale, die sich früher von selbst gefüllt haben, stehen jetzt leer.
	if str(d.get("regale", "")) != REGALE_EIGEN:
		for r in raeume:
			regale_leeren(r)
		for vl in vorlagen:
			regale_leeren(vl.raum)
	return { "format": FORMAT, "version": VERSION, "aktuell": akt, "raeume": raeume, "vorlagen": vorlagen, "regale": REGALE_EIGEN,
		"eigene": eigene, "stimmungen": stimmungen, "farben": farben, "huellen": G.pruefe_huellen(d.get("huellen")),
		# Deine Figur und dein Haustier: dieselbe strenge Prüfung (nur Kennungen, Name begrenzt).
		"figur": FD.pruefe_figur(d.get("figur")), "tier": FD.pruefe_tier(d.get("tier")), "gemeldet": FD.pruefe_gemeldet(d.get("gemeldet")) }


## Spieleregale eines (schon geprüften) Raums leer räumen: Auswahl „eigene“ ohne Spiele, Sortierung
## nach deiner Reihenfolge. Darstellung, Abnutzung und Deko bleiben, alle anderen Möbel auch.
static func regale_leeren(raum: Dictionary) -> void:
	for m in raum.get("moebel", []):
		var it: Dictionary = m
		if str(it.get("t", "")) != "spieleregal":
			continue
		var rg: Dictionary = (it.rg as Dictionary).duplicate(true) if it.get("rg") is Dictionary else {}
		for k in ["fi", "so", "ma", "pl", "lg"]:
			rg.erase(k)
		rg = G.pruefe_regal(rg, "spieleregal")
		if rg == G.std_regal("spieleregal"):
			it.erase("rg")
		else:
			it["rg"] = rg


## Eigene Vorlage: Kennung „v_…“, Name (Text des Nutzers, gekürzt) und ein Raum, geprüft wie jeder
## Raum (seine Kennung ist immer „vorlage“). {} wenn etwas nicht passt.
static func pruefe_vorlage(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var id: Variant = d.get("id")
	if not (id is String) or not G.kennung(id) or not (id as String).begins_with(VORLAGE_PRAEFIX) or (id as String).length() < 3:
		return {}
	var rv: Variant = d.get("raum")
	if not (rv is Dictionary):
		return {}
	var r: Dictionary = (rv as Dictionary).duplicate()
	r["id"] = "vorlage"
	var raum := pruefe_raum(r)
	if raum.is_empty():
		return {}
	return { "id": id, "name": _name(d.get("name"), "Vorlage"), "raum": raum }


static func pruefe_raum(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var id: Variant = d.get("id")
	if not (id is String) or not G.kennung(id):
		return {}
	var w: Variant = d.get("w")
	var t: Variant = d.get("d")
	if not _ganz(w) or not _ganz(t) or int(w) < MIN_FELDER or int(w) > MAX_FELDER or int(t) < MIN_FELDER or int(t) > MAX_FELDER:
		return {}
	var raum := G.pruefe_raum_gestalt(d)
	raum.merge({ "id": id, "name": _name(d.get("name"), "Mein Zimmer"), "w": int(w), "d": int(t), "moebel": [] })
	var ml: Variant = d.get("moebel")
	if ml is Array:
		var belegt := {}
		var anzahl := {}
		for m in (ml as Array).slice(0, MAX_MOEBEL):
			var it := pruefe_moebel(m)
			if it.is_empty():
				continue
			var maxn := int(Katalog.info(it.t).get("max", 0))
			if maxn > 0 and int(anzahl.get(it.t, 0)) >= maxn:
				continue
			if not passt(raum, it, -1, belegt):
				# Ersetztes Möbel (Spiegel an der Wand → Jackenständer am Boden): ist das Feld davor belegt,
				# die nächste freie Stelle daneben, statt es fallen zu lassen.
				var frei: Variant = freie_stelle(raum, str(it.t), int(it.x), int(it.z), int(it.r)) if ersetzt(m) else null
				if not (frei is Dictionary):
					continue
				it.x = int(frei.x)
				it.z = int(frei.z)
			anzahl[it.t] = int(anzahl.get(it.t, 0)) + 1
			raum.moebel.append(it)
			_belege(belegt, raum, it, raum.moebel.size() - 1)
	return raum


static func pruefe_moebel(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var t: Variant = d.get("t")
	# Möbel, die es nicht mehr gibt: was an ihrer Stelle steht (Katalog.ERSETZT; Variante, Lage, Drehung bleiben).
	if t is String and Katalog.ERSETZT.has(t):
		t = str(Katalog.ERSETZT[t])
	if not (t is String) or not Katalog.has(t):
		return {}
	for k in ["x", "z"]:
		if not _ganz(d.get(k)):
			return {}
	var r: Variant = d.get("r", 0)
	if not _ganz(r) or int(r) < 0 or int(r) > 3:
		return {}
	var va: Variant = d.get("v", "")
	var vs: String = va if va is String else ""
	if not Katalog.variante_gueltig(t, vs):
		vs = Katalog.std_variante(t)
	var an: Variant = d.get("an", true)
	var out := { "t": t, "x": int(d.x), "z": int(d.z), "r": int(r), "v": vs, "an": an if an is bool else true }
	_anpassung(out, d)
	return out


## Kam das Möbel unter einer alten Kennung (Katalog.ERSETZT)?
static func ersetzt(v: Variant) -> bool:
	return v is Dictionary and (v as Dictionary).get("t") is String and Katalog.ERSETZT.has((v as Dictionary).get("t"))


## Freiwillige Felder der Gestaltung (gestalt.gd): nur, was gültig ist und zum Möbel passt.
static func _anpassung(out: Dictionary, d: Dictionary) -> void:
	var t := str(out.t)
	var info := Katalog.info(t)
	if Katalog.ist_eigen(t):
		return
	for k in ["f", "f2", "mf"]:
		var c := G.farbe(d.get(k))
		if c != "":
			out[k] = c
	for k in ["m", "m2"]:
		if d.get(k) is String and G.MATERIALIEN.has(d.get(k)):
			out[k] = d.get(k)
	var mu := G.wahl(d.get("mu"), G.MUSTER)
	if mu != "":
		out["mu"] = mu
	if not Katalog.stufen(t).is_empty() and d.get("s") != null:
		var s := G.ganz(d.get("s"), 0, Katalog.stufen(t).size() - 1, Katalog.std_stufe(t))
		if s != Katalog.std_stufe(t):
			out["s"] = s
	if bool(info.get("beine", false)):
		var be := G.wahl(d.get("be"), G.BEINE)
		if be != "":
			out["be"] = be
	if bool(info.get("griffe", false)):
		var gr := G.wahl(d.get("gr"), G.GRIFFE)
		if gr != "":
			out["gr"] = gr
	if Katalog.nutzen(t) == "lampe" or t == "trophaeenschrank":
		var l := G.pruefe_lampe(d.get("l"))
		if not l.is_empty():
			out["l"] = l
	var rg := G.pruefe_regal(d.get("rg"), t)
	if not rg.is_empty() and rg != G.std_regal(t):
		out["rg"] = rg


static func _ganz(v: Variant) -> bool:
	if v is int:
		return absi(v) < 100000
	if v is float:
		return is_finite(v) and absf(v) < 100000.0 and floorf(v) == v
	return false


## Name: derselbe Filter wie für jeden Text des Zimmers (gestalt.gd text), gekürzt.
static func _name(v: Variant, fallback: String) -> String:
	var out := G.text(v, MAX_NAME)
	return out if out != "" else fallback


static func wahl_name(liste: Array, id: String) -> String:
	for p in liste:
		if str(p[0]) == id:
			return str(p[1])
	return ""


# --- Raster und Belegung ----------------------------------------------------------------------

## Felder, die ein Möbel belegt (x, z = linke hintere Ecke).
static func felder(it: Dictionary) -> Array:
	var g := Katalog.groesse_it(it)
	var out: Array = []
	for i in g.x:
		for j in g.y:
			out.append(Vector2i(int(it.x) + i, int(it.z) + j))
	return out


## Wandmöbel hängen mit dem Rücken an der Wand, zu der ihre Drehung zeigt (0 hinten, 1 links,
## 2 vorn, 3 rechts) – dazu müssen sie an dieser Wand liegen.
static func an_wand(raum: Dictionary, it: Dictionary) -> bool:
	var g := Katalog.groesse_it(it)
	match int(it.r):
		0: return int(it.z) == 0
		1: return int(it.x) == 0
		2: return int(it.z) + g.y == int(raum.d)
		3: return int(it.x) + g.x == int(raum.w)
	return false


## Die passende Drehung für ein Wandmöbel an dieser Stelle (nächste Wand), -1 ohne Wand.
static func wand_drehung(raum: Dictionary, id: String, x: int, z: int, bisher := 0, s := -1) -> int:
	var probe := { "t": id, "x": x, "z": z, "r": bisher }
	if s >= 0:
		probe["s"] = s
	if an_wand(raum, probe):
		return bisher
	for r in [0, 1, 3, 2]:
		probe.r = r
		if an_wand(raum, probe):
			return r
	return -1


## Belegung aller Ebenen: "ebene:x,z" → Index des Möbels (ohne das Möbel ohne).
static func belegung(raum: Dictionary, ohne := -1) -> Dictionary:
	var b := {}
	var ml: Array = raum.moebel
	for i in ml.size():
		if i != ohne:
			_belege(b, raum, ml[i], i)
	return b


static func _belege(b: Dictionary, _raum: Dictionary, it: Dictionary, idx: int) -> void:
	var eb := Katalog.ebene(str(it.t))
	for f in felder(it):
		b["%s:%d,%d" % [eb, f.x, f.y]] = idx


## Darf das Möbel hier stehen? Im Raum, freie Felder auf seiner Ebene; Kleines steht auf dem Boden
## (wo kein Bodenmöbel ist) oder ganz auf der Fläche genau eines Bodenmöbels; Wandmöbel an ihrer Wand.
static func passt(raum: Dictionary, it: Dictionary, ohne := -1, b: Variant = null) -> bool:
	var g := Katalog.groesse_it(it)
	if int(it.x) < 0 or int(it.z) < 0 or int(it.x) + g.x > int(raum.w) or int(it.z) + g.y > int(raum.d):
		return false
	var bel: Dictionary = b if b is Dictionary else belegung(raum, ohne)
	var eb := Katalog.ebene(str(it.t))
	if eb == "wand" and not an_wand(raum, it):
		return false
	# Was auf dem bewegten Möbel steht, geht mit und ist kein Hindernis.
	var mit: Array = darauf(raum, ohne) if eb == "boden" and ohne >= 0 else []
	var traeger := -2
	for f in felder(it):
		var k := "%d,%d" % [f.x, f.y]
		if bel.has(eb + ":" + k):
			return false
		if eb == "boden" and bel.has("klein:" + k) and not (int(bel["klein:" + k]) in mit):
			# Unter Kleinem, das auf dem Boden steht, kann kein Möbel hineingeschoben werden.
			return false
		if eb == "klein":
			var unter := int(bel.get("boden:" + k, -1))
			if unter >= 0 and Katalog.flaeche_it(raum.moebel[unter]) <= 0.0:
				return false
			if traeger == -2:
				traeger = unter
			elif traeger != unter:
				return false
	return true


## Höhe, auf der ein Möbel steht: Kleines auf der Fläche darunter, Wandmöbel auf ihrer Höhe.
static func standhoehe(raum: Dictionary, it: Dictionary, ohne := -1) -> float:
	var eb := Katalog.ebene(str(it.t))
	if eb == "wand":
		# Eigene Wandmöbel geben ihre Höhe selbst an (Teile ab dem Boden gemessen).
		return 0.0 if Katalog.ist_eigen(str(it.t)) else float(Katalog.WAND_HOEHE.get(str(it.t), 1.3))
	if eb != "klein":
		return 0.0
	var bel := belegung(raum, ohne)
	var f: Vector2i = felder(it)[0]
	var unter := int(bel.get("boden:%d,%d" % [f.x, f.y], -1))
	return Katalog.flaeche_it(raum.moebel[unter]) if unter >= 0 else 0.0


## Welches Möbel liegt auf diesem Feld? Von oben nach unten: Kleines, Boden, Wand, Teppich, Decke.
static func an_feld(raum: Dictionary, x: int, z: int) -> int:
	var bel := belegung(raum)
	for eb in ["klein", "boden", "wand", "teppich", "decke"]:
		var k := "%s:%d,%d" % [eb, x, z]
		if bel.has(k):
			return int(bel[k])
	return -1


## Alles auf einem Feld, von oben nach unten (wie an_feld): Tasse, Tisch darunter, Bild an der Wand,
## Teppich, Deckenlampe – damit sich auch Verdecktes wählen lässt.
static func alle_an_feld(raum: Dictionary, x: int, z: int) -> Array:
	var bel := belegung(raum)
	var out: Array = []
	for eb in ["klein", "boden", "wand", "teppich", "decke"]:
		var k := "%s:%d,%d" % [eb, x, z]
		if bel.has(k):
			out.append(int(bel[k]))
	return out


## Das Wandmöbel, das an der Wand vor einem Feld außerhalb des Raums hängt (c: ein Schritt über den
## Rand, wie im Einrichten), sonst -1.
static func an_wandfeld(raum: Dictionary, c: Vector2i) -> int:
	var w := int(raum.w)
	var d := int(raum.d)
	var r := -1
	if c.y < 0:
		r = 0
	elif c.x < 0:
		r = 1
	elif c.y >= d:
		r = 2
	elif c.x >= w:
		r = 3
	if r < 0:
		return -1
	var innen := Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, d - 1))
	var ml: Array = raum.moebel
	for i in ml.size():
		var it: Dictionary = ml[i]
		if Katalog.ebene(str(it.t)) == "wand" and int(it.r) == r and innen in felder(it):
			return i
	return -1


## Was auf einem Bodenmöbel steht (Indizes), damit es beim Verschieben mitgeht.
static func darauf(raum: Dictionary, idx: int) -> Array:
	var out: Array = []
	if idx < 0 or idx >= (raum.moebel as Array).size():
		return out
	var unten: Dictionary = raum.moebel[idx]
	if Katalog.ebene(str(unten.t)) != "boden" or Katalog.flaeche_it(unten) <= 0.0:
		return out
	var meine := {}
	for f in felder(unten):
		meine[f] = true
	for i in (raum.moebel as Array).size():
		var m: Dictionary = raum.moebel[i]
		if i != idx and Katalog.ebene(str(m.t)) == "klein" and meine.has(felder(m)[0]):
			out.append(i)
	return out


## Nächste freie Stelle für ein neues Möbel ab (x, z): spiralförmig nach außen. null ohne Platz.
static func freie_stelle(raum: Dictionary, id: String, x: int, z: int, r := 0) -> Variant:
	var bel := belegung(raum)
	for rad in 24:
		for dx in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dz)) != rad:
					continue
				var rr := r
				if Katalog.ebene(id) == "wand":
					rr = wand_drehung(raum, id, x + dx, z + dz, r)
					if rr < 0:
						continue
				var it := { "t": id, "x": x + dx, "z": z + dz, "r": rr, "v": Katalog.std_variante(id), "an": true }
				if passt(raum, it, -1, bel):
					return it
	return null


## Wie viele Möbel dieser Art es noch geben darf (max im Katalog); -1 = beliebig viele.
static func noch_erlaubt(raum: Dictionary, id: String) -> int:
	var maxn := int(Katalog.info(id).get("max", 0))
	if maxn <= 0:
		return -1
	var n := 0
	for m in raum.moebel:
		if str(m.t) == id:
			n += 1
	return maxi(0, maxn - n)


# --- Rückgängig --------------------------------------------------------------------------------

## Stand eines Raums für Rückgängig (tiefe Kopie, ohne Verweise auf die Szene).
static func schnappschuss(raum: Dictionary) -> Dictionary:
	return raum.duplicate(true)


## Neuen Stand auf den Stapel (älteste fallen hinten weg).
static func merke(stapel: Array, raum: Dictionary) -> void:
	stapel.append(schnappschuss(raum))
	while stapel.size() > MAX_SCHRITTE:
		stapel.pop_front()

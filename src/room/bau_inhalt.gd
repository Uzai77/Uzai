extends RefCounted
## Inhalt des Bau-Menüs im Zimmer (katalog_ui.gd): die Bereiche der Leiste – erst der Raum (Wände,
## Böden, Decke, Fenster und Türen, Licht, Raumgröße, Vorlagen), dann die Möbel nach Zweck – und
## welche Kacheln darin stehen, was eine Kachel im Zimmer tut, welche Farbe sie trägt und wo ihre
## Feineinstellung liegt (Seiten aus anpassen.gd). Reine Daten aus den festen Listen in gestalt.gd,
## Aufrufe gehen an das Zimmer (zimmer_einrichten.gd) – nichts wird ausgeführt oder geladen.
##
## Eine Kachel: { id, art, wert, name, abschnitt, sofort, reihe, … }
##   art      wand, boden, decke, sockel, fenster, vorhang, tuer, stimmung, zeit, wetter (wirken sofort
##            als Probe im Zimmer, A übernimmt), form, vorlage (erst mit A), mehr (Seite „seite“);
##            regal, huelle aus regal_tafel.gd (Feld eines Regals, Hülle je System)
##   reihe    beginnt eine neue Reihe im Raster (ein neuer Abschnitt)
##   eigen    vom Nutzer (Name nie übersetzen, Y öffnet seine Seite)

const G := preload("res://src/room/gestalt.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const S := preload("res://src/room/stoffe.gd")

## Raum-Bereiche: [Kennung, Name, Zeichen (icons.gd)].
const RAUM := [
	["@waende", "Wände und Tapeten", "wand"], ["@boden", "Böden", "boden"], ["@decke", "Decke und Leisten", "decke"],
	["@fenster", "Fenster und Türen", "fenster"], ["@licht", "Licht und Stimmung", "stimmung"],
	["@groesse", "Raumgröße", "raumgroesse"], ["@vorlagen", "Vorlagen", "vorlage"],
]
## Zeichen der Möbel-Bereiche (Katalog.KATEGORIEN).
const MOEBEL_ZEICHEN := { "sitzen": "sitzen", "tische": "tisch", "regale": "regal", "technik": "technik", "licht": "lampe",
	"pflanzen": "pflanze", "deko": "deko", "eigene": "baukasten" }

## Wandflächen in Abschnitten (Tapete einmal je Muster).
const WAND_PUTZ := ["anstrich", "kalk", "beton"]
const WAND_VERKLEIDUNG := ["paneel", "holz", "ziegel", "fliesen"]
const BODEN_ABSCHNITTE := [["Holz", ["dielen", "landhaus", "fischgrat"]], ["Stein und Fliesen", ["fliesen", "schachbrett", "terrazzo", "marmor", "beton"]],
	["Weich", ["teppichboden"]]]

## Farbe einer Kachel: [Bereich im Raum, Feld, Zeile auf der Feinseite, Feinseite].
const FARBZIEL := {
	"wand": ["waende", "f", "Farbe", "wand"], "boden": ["boden", "f", "Farbe", "boden"], "decke": ["decke", "f", "Deckenfarbe", "decke"],
	"sockel": ["sockel", "f", "Leistenfarbe", "decke"], "fenster": ["fenster", "rf", "Rahmen", "fenster"],
	"vorhang": ["fenster", "vf", "Vorhangfarbe", "fenster"], "tuer": ["tuer", "f", "Farbe", "tuer"],
}
const SOFORT := ["wand", "boden", "decke", "sockel", "fenster", "vorhang", "tuer", "stimmung", "zeit", "wetter"]

## Farbtupfer der Möbel-Varianten, die keine Stoff- oder Holzfarbe sind.
const TUPFER := { "creme": "#e8e0d1", "schwarz": "#2e2b29", "weiss": "#efebe4", "mint": "#9fd3bd", "grau": "#8d8c88", "braun": "#6b4a32",
	"lila": "#8a6a8f", "orange": "#e58a3a", "rosa": "#ff8fc0", "blau": "#5aa0ff", "gold": "#d9a441", "warm": "#f2c27a", "gruen": "#5d7a5a",
	"rot": "#b0403c", "pastell": "#d6b0a6", "chips": "#e7c27d", "obst": "#c0503c", "suess": "#d6b0a6", "monstera": "#3f6b45",
	"olive": "#8a9a6a", "kaktus": "#5d8a5a", "huegel": "#87977a", "sonne": "#d9a441", "wellen": "#4f7f8f", "punkte": "#c98c6b",
	"roehre": "#4b4d52", "flach": "#26272b", "beamer": "#d6d8db", "oben": "#7a5cff", "hinten": "#2fd6ff", "bunt": "#ff4fa3" }


## Alle Bereiche der Leiste: [Kennung, Name, Zeichen] – Raum zuerst, dann die Möbel.
static func gruppen() -> Array:
	var out: Array = RAUM.duplicate()
	for k in Katalog.KATEGORIEN:
		out.append([str(k[0]), str(k[1]), str(MOEBEL_ZEICHEN.get(str(k[0]), "grid"))])
	return out


static func ist_raum(id: String) -> bool:
	return id.begins_with("@")


static func _k(id: String, art: String, wert: String, name: String, abschnitt: String, extra := {}) -> Dictionary:
	var d := { "id": id, "art": art, "wert": wert, "name": name, "abschnitt": abschnitt, "sofort": art in SOFORT }
	d.merge(extra, true)
	return d


static func _mehr(gruppe: String, seite: String, abschnitt: String, hinweis: String) -> Dictionary:
	return _k("%s:mehr:%s" % [gruppe, seite], "mehr", "", "Alle Einstellungen", abschnitt, { "seite": seite, "hinweis": hinweis })


## Die Kacheln eines Raum-Bereichs (daten: eigene Stimmungen und Vorlagen).
static func kacheln(gruppe: String, daten: Dictionary) -> Array:
	var out: Array = []
	match gruppe:
		"@waende":
			for m in WAND_PUTZ:
				out.append(_k("@waende:%s" % m, "wand", m, G.wahl_name(G.WANDMATERIAL, m), "Farbe und Putz"))
			for mu in G.MUSTER:
				out.append(_k("@waende:tapete:%s" % mu[0], "wand", "tapete", str(mu[1]), "Tapeten", { "mu": str(mu[0]) }))
			for m in WAND_VERKLEIDUNG:
				out.append(_k("@waende:%s" % m, "wand", m, G.wahl_name(G.WANDMATERIAL, m), "Verkleidung"))
			out.append(_mehr(gruppe, "wand", "Wände", "Jede Wand einzeln, Musterfarbe"))
		"@boden":
			for ab in BODEN_ABSCHNITTE:
				for a in ab[1]:
					out.append(_k("@boden:%s" % a, "boden", a, G.wahl_name(G.BODENARTEN, a), str(ab[0])))
			out.append(_mehr(gruppe, "boden", "Böden", "Zweite Farbe"))
		"@decke":
			for d in G.DECKEN:
				out.append(_k("@decke:%s" % d[0], "decke", str(d[0]), str(d[1]), "Decke"))
			for i in G.SOCKEL.size():
				out.append(_k("@decke:sockel:%s" % G.SOCKEL[i][0], "sockel", str(G.SOCKEL[i][0]), str(G.SOCKEL[i][1]), "Sockelleiste", { "reihe": i == 0 }))
		"@fenster":
			for f in G.FENSTERARTEN:
				out.append(_k("@fenster:%s" % f[0], "fenster", str(f[0]), str(f[1]), "Fenster"))
			out.append(_mehr(gruppe, "fenster", "Fenster", "Größe, Rahmen, Vorhang"))
			for i in G.VORHAENGE.size():
				out.append(_k("@fenster:vorhang:%s" % G.VORHAENGE[i][0], "vorhang", str(G.VORHAENGE[i][0]), str(G.VORHAENGE[i][1]), "Vorhänge",
					{ "reihe": i == 0 }))
			for i in G.TUERARTEN.size():
				out.append(_k("@fenster:tuer:%s" % G.TUERARTEN[i][0], "tuer", str(G.TUERARTEN[i][0]), str(G.TUERARTEN[i][1]), "Tür", { "reihe": i == 0 }))
			out.append(_mehr(gruppe, "tuer", "Tür", "Platz an der Wand, Griff"))
		"@licht":
			for s in G.STIMMUNGEN:
				out.append(_k("@licht:%s" % s[0], "stimmung", str(s[0]), str(s[1]), "Stimmungen"))
			for s in daten.get("stimmungen", []):
				out.append(_k("@licht:%s" % s.id, "stimmung", str(s.id), str(s.name), "Eigene Stimmungen", { "eigen": true }))
			for i in G.ZEITEN.size():
				out.append(_k("@licht:zeit:%s" % G.ZEITEN[i][0], "zeit", str(G.ZEITEN[i][0]), str(G.ZEITEN[i][1]), "Tageszeit", { "reihe": i == 0 }))
			for i in G.WETTER.size():
				out.append(_k("@licht:wetter:%s" % G.WETTER[i][0], "wetter", str(G.WETTER[i][0]), str(G.WETTER[i][1]), "Wetter", { "reihe": i == 0 }))
			out.append(_mehr(gruppe, "licht", "Licht", "Lampen, LED, eigene Stimmung"))
		"@groesse":
			for f in G.FORMEN:
				var stufen: Array = G.RAUM_MASSE[str(f[0])]
				for i in stufen.size():
					out.append(_k("@groesse:%s:%d" % [f[0], i], "form", str(f[0]), str(G.GROESSEN[i][1]), str(f[1]),
						{ "w": int(stufen[i][0]), "d": int(stufen[i][1]), "reihe": i == 0 }))
			out.append(_mehr(gruppe, "groesse", "Raumgröße", "Breite und Tiefe genau"))
		"@vorlagen":
			for v in Vorlagen.LISTE:
				out.append(_k("@vorlagen:%s" % v[0], "vorlage", str(v[0]), str(v[1]), "Vorlagen", { "hinweis": str(v[2]) }))
			for v in daten.get("vorlagen", []):
				out.append(_k("@vorlagen:%s" % v.id, "vorlage", str(v.id), str(v.name), "Deine Vorlagen", { "eigen": true }))
	return out


## Steht das im Zimmer (raum: Stand ohne Probe)? Wände ohne Ziel: alle vier gleich.
static func aktiv(k: Dictionary, raum: Dictionary, wand := "") -> bool:
	var w := str(k.get("wert", ""))
	match str(k.get("art", "")):
		"wand":
			for s in G.SEITEN:
				if wand != "" and s != wand:
					continue
				var wd: Dictionary = raum.waende[s]
				if str(wd.m) != w or (w == "tapete" and str(wd.get("mu", "")) != str(k.get("mu", ""))):
					return false
			return true
		"boden": return str(raum.boden.a) == w
		"decke": return str(raum.decke.a) == w
		"sockel": return str(raum.sockel.a) == w
		"fenster": return str(raum.fenster.a) == w
		"vorhang": return str(raum.fenster.v) == w
		"tuer": return str(raum.tuer.a) == w
		"stimmung": return str(raum.licht.get("st", "")) == w
		"zeit": return str(raum.licht.z) == w
		"wetter": return str(raum.licht.we) == w
		"form": return int(raum.w) == int(k.w) and int(raum.d) == int(k.d)
	return false


## Die Kachel im Zimmer zeigen bzw. übernehmen (z: das Zimmer; Wände: eine Seite oder alle).
static func anwenden(k: Dictionary, z: Object, wand := "") -> void:
	var w := str(k.get("wert", ""))
	match str(k.get("art", "")):
		"wand":
			var werte := { "m": w }
			if w == "tapete":
				werte["mu"] = str(k.get("mu", ""))
			z.call("wand_werte", wand, werte)
		"boden":
			# Jede Art mit ihrer eigenen Farbe (Holz bleibt Holz) – eine andere wählt Y.
			z.call("raum_werte", "boden", { "a": w, "f": str(G.BODEN_STD.get(w, "#c29466")), "f2": "" })
		"decke": z.call("raum_werte", "decke", { "a": w })
		"sockel": z.call("raum_werte", "sockel", { "a": w })
		"fenster": z.call("raum_werte", "fenster", { "a": w })
		"vorhang": z.call("raum_werte", "fenster", { "v": w })
		"tuer": z.call("raum_werte", "tuer", { "a": w })
		"stimmung": z.call("stimmung_anwenden", w, false)
		"zeit": z.call("licht_setzen", "z", w)
		"wetter": z.call("licht_setzen", "we", w)
		"form": z.call("groesse_setzen", int(k.w), int(k.d))
		"vorlage": z.call("vorlage_uebernehmen", w)
		# Regal einrichten (regal_tafel.gd): ein Feld des Regals bzw. die Hülle eines Systems.
		"regal": z.call("regal_setzen", int(k.moebel), str(k.feld), k.wert)
		"huelle": z.call("huelle_setzen", str(k.sid), w)


## Feld für Y (Farbe), sonst [].
static func farbziel(k: Dictionary) -> Array:
	return FARBZIEL.get(str(k.get("art", "")), [])


static func farbe(k: Dictionary, raum: Dictionary, wand := "") -> String:
	var fz := farbziel(k)
	if fz.is_empty():
		return ""
	if str(k.art) == "wand":
		return str(raum.waende["hinten" if wand == "" else wand].get("f", ""))
	return str(raum[fz[0]].get(fz[1], ""))


static func farbe_setzen(k: Dictionary, z: Object, hex: String, wand := "") -> void:
	var fz := farbziel(k)
	if fz.is_empty():
		return
	if str(k.art) == "wand":
		z.call("wand_werte", wand, { "f": hex })
	else:
		z.call("raum_werte", str(fz[0]), { str(fz[1]): hex })


## Feinseite zu einer Kachel (Kennung für Anpassen.seite_fuer): „mehr“, die eigene Stimmung bzw.
## Vorlage (Y) und die Seite mit dem Farbrad zu einer Farbe.
static func seite(k: Dictionary, wand := "", fuer_farbe := false) -> String:
	var art := str(k.get("art", ""))
	var s := ""
	if fuer_farbe:
		var fz := farbziel(k)
		s = str(fz[3]) if not fz.is_empty() else ""
	elif art == "mehr":
		s = str(k.get("seite", ""))
	elif bool(k.get("eigen", false)):
		s = ("stimmung:" if art == "stimmung" else "vorlage:") + str(k.wert)
	if s == "wand":
		# Mehr: alle Wände (je Wand einzeln, übertragen) bzw. die gewählte; Farbe: deren Seite.
		s = "waende" if wand == "" and not fuer_farbe else "wand:" + wand
	return s


## Farbe eines Tupfers unter einer Möbel-Kachel (Variante), transparent wenn unbekannt.
static func tupfer(v: String) -> Color:
	if S.STOFF_FARBEN.has(v):
		return S.STOFF_FARBEN[v]
	if S.HOLZ_FARBEN.has(v):
		return (S.HOLZ_FARBEN[v] as Array)[0]
	if TUPFER.has(v):
		return Color(str(TUPFER[v]))
	return Color(0, 0, 0, 0)

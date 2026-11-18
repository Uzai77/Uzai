extends Node
## Bau-Menü im Zimmer (katalog_ui.gd, bau_inhalt.gd): Bereiche geordnet mit eigenem Zeichen, jede
## Wahl der Seitenleiste als Kachel erreichbar (Wände, Muster, Böden, Decke, Leisten, Fenster,
## Vorhänge, Türen, Stimmungen, Tageszeit, Wetter, Raumgröße, Vorlagen), was eine Kachel im Zimmer
## tut, Farben und Feinseiten, Bedienung (Raster mit Abschnitten, Y Farbe/Variante, A übernehmen,
## B zurück) und die Tastenzeile (höchstens vier, B zuletzt). Dazu „Regal einrichten“ als Tafel
## (regal_tafel.gd): alles, was die Seite des Regals konnte, als Kachel.
## Aufruf: godot --headless --path . res://tests/logic_baumenue.tscn

const KatalogUi := preload("res://src/room/katalog_ui.gd")
const Inhalt := preload("res://src/room/bau_inhalt.gd")
const Bilder := preload("res://src/room/bau_bilder.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const Daten := preload("res://src/room/zimmer_daten.gd")
const Anpassen := preload("res://src/room/anpassen.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const IconsS := preload("res://src/core/icons.gd")
const RegalTafel := preload("res://src/room/regal_tafel.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Ein Zimmer ohne 3D: merkt sich, was das Bau-Menü aufruft, und ändert die Daten wie das echte.
class _Zimmer extends Control:
	var raum: Dictionary = {}
	var daten: Dictionary = {}
	var _rueck: Array = []
	var aufrufe: Array = []
	var offen := false
	var vorher := {}

	func wand_werte(seite: String, werte: Dictionary) -> void:
		aufrufe.append(["wand_werte", seite, werte])
		for s in G.SEITEN:
			if seite == "" or s == seite:
				for k in werte.keys():
					raum.waende[s][k] = str(werte[k])

	func raum_werte(bereich: String, werte: Dictionary) -> void:
		aufrufe.append(["raum_werte", bereich, werte])
		for k in werte.keys():
			raum[bereich][k] = werte[k]

	func stimmung_anwenden(id: String, merken := true) -> void:
		aufrufe.append(["stimmung_anwenden", id, merken])
		raum.licht.st = id

	func licht_setzen(k: String, v: Variant) -> void:
		aufrufe.append(["licht_setzen", k, v])
		raum.licht[k] = v

	func groesse_setzen(w: int, d: int) -> void:
		aufrufe.append(["groesse_setzen", w, d])

	func vorlage_uebernehmen(id: String) -> void:
		aufrufe.append(["vorlage_uebernehmen", id])

	func regal_setzen(i: int, k: String, v: Variant) -> void:
		aufrufe.append(["regal_setzen", i, k, v])
		var rg: Dictionary = raum.moebel[i].get("rg", G.std_regal(str(raum.moebel[i].t))).duplicate()
		rg[k] = v
		raum.moebel[i]["rg"] = rg

	func huelle_setzen(sid: String, art: String) -> void:
		aufrufe.append(["huelle_setzen", sid, art])

	func regal_einraeumen(i: int) -> void:
		aufrufe.append(["regal_einraeumen", i])

	func gesperrt(id: String) -> String:
		return "Meilenstein" if id == "lavalampe" else ""

	func noch_frei(_id: String) -> int:
		return -1

	func eigene_farben() -> Array:
		return ["#123456"]

	func bau_probe(k: Dictionary, farbe := "", wand := "") -> void:
		if not offen:
			vorher = raum.duplicate(true)
			_rueck.append(vorher)
		offen = true
		aufrufe.append(["bau_probe", str(k.get("id", "")), farbe])
		if farbe != "":
			Inhalt.farbe_setzen(k, self, farbe, wand)
		else:
			Inhalt.anwenden(k, self, wand)

	func bau_offen() -> bool:
		return offen

	func bau_stand() -> Dictionary:
		return vorher if offen else raum

	func bau_uebernehmen() -> void:
		aufrufe.append(["bau_uebernehmen"])
		offen = false

	func bau_verwerfen() -> void:
		if offen:
			aufrufe.append(["bau_verwerfen"])
			raum = vorher
			_rueck.pop_back()
		offen = false

	func bau_seite(kennung: String) -> void:
		aufrufe.append(["bau_seite", kennung])

	func bau_tun(k: Dictionary) -> void:
		Inhalt.anwenden(k, self)

	func letzter(name_: String) -> Array:
		for i in range(aufrufe.size() - 1, -1, -1):
			if str(aufrufe[i][0]) == name_:
				return aufrufe[i]
		return []


func _ready() -> void:
	print("Bereiche: geordnet, je ein eigenes Zeichen")
	var gr := Inhalt.gruppen()
	var ids: Array = gr.map(func(g: Array) -> String: return str(g[0]))
	check(ids.slice(0, 7) == ["@waende", "@boden", "@decke", "@fenster", "@licht", "@groesse", "@vorlagen"], "erst der Raum (%s)" % str(ids.slice(0, 7)))
	check(ids.slice(7) == ["sitzen", "tische", "regale", "technik", "licht", "pflanzen", "deko", "eigene"], "dann die Möbel nach Zweck (%s)" % str(ids.slice(7)))
	var zeichen: Array = gr.map(func(g: Array) -> String: return str(g[2]))
	var doppelt := false
	for z in zeichen:
		doppelt = doppelt or zeichen.count(z) > 1
	check(zeichen.all(func(z: String) -> bool: return IconsS.P.has(z)) and not doppelt, "jeder Bereich hat sein eigenes Zeichen im Symbolsatz")
	for z in ["sonne", "wolke", "regen", "schnee", "nebel"]:
		check(IconsS.P.has(z), "Wetter-Zeichen „%s“" % z)
	var kats: Array = Katalog.KATEGORIEN.map(func(k: Array) -> String: return str(k[0]))
	var alle_da := true
	for id in Katalog.MOEBEL.keys():
		alle_da = alle_da and str(Katalog.MOEBEL[id].kat) in kats
	check(alle_da, "jedes Möbel steht in einem Bereich")
	check(Katalog.in_kategorie("pflanzen").has("pflanze") and Katalog.in_kategorie("pflanzen").has("topfpflanze") and Katalog.in_kategorie("regale").has("kommode"),
			"Pflanzen eigen, Kommode bei Regalen und Stauraum")

	print("Jede Wahl der Seitenleiste als Kachel")
	var daten := Daten.standard()
	daten["stimmungen"] = [{ "id": "s_abc123", "name": "Meine", "licht": G.std_licht() }]
	daten["vorlagen"] = [{ "id": Daten.VORLAGE_PRAEFIX + "x1", "name": "Bei Tom", "raum": Daten.standard_raum() }]
	var werte := {}
	var alle_ids: Array = []
	for g in Inhalt.RAUM:
		for k in Inhalt.kacheln(str(g[0]), daten):
			alle_ids.append(str(k.id))
			var art := str(k.art)
			if not werte.has(art):
				werte[art] = []
			(werte[art] as Array).append(str(k.wert) + ("/" + str(k.mu) if k.has("mu") else ""))
	var eindeutig := true
	for i in alle_ids:
		eindeutig = eindeutig and alle_ids.count(i) == 1
	check(eindeutig and alle_ids.all(func(i: String) -> bool: return i.begins_with("@")), "Kennungen eindeutig, alle mit @ (%d Kacheln)" % alle_ids.size())
	var wandflaechen: Array = G.WANDMATERIAL.map(func(p: Array) -> String: return str(p[0]))
	var flaechen_da := true
	for m in wandflaechen:
		var da := false
		for w in werte.wand:
			da = da or str(w).begins_with(str(m))
		flaechen_da = flaechen_da and da
	check(flaechen_da, "alle Wandflächen")
	check(G.MUSTER.all(func(p: Array) -> bool: return ("tapete/" + str(p[0])) in werte.wand), "Tapete in jedem Muster")
	for paar in [["boden", G.BODENARTEN], ["decke", G.DECKEN], ["sockel", G.SOCKEL], ["fenster", G.FENSTERARTEN], ["vorhang", G.VORHAENGE],
			["tuer", G.TUERARTEN], ["zeit", G.ZEITEN], ["wetter", G.WETTER]]:
		var soll: Array = (paar[1] as Array).map(func(p: Array) -> String: return str(p[0]))
		check(soll.all(func(w: String) -> bool: return w in werte[paar[0]]), "alle Werte für %s" % paar[0])
	var stimmungen: Array = G.STIMMUNGEN.map(func(p: Array) -> String: return str(p[0]))
	check(stimmungen.all(func(w: String) -> bool: return w in werte.stimmung) and "s_abc123" in werte.stimmung, "Stimmungen, auch eigene")
	check((werte.form as Array).size() == G.FORMEN.size() * G.GROESSEN.size(), "jede Form in jeder Größe")
	var vl: Array = Vorlagen.LISTE.map(func(p: Array) -> String: return str(p[0]))
	check(vl.all(func(w: String) -> bool: return w in werte.vorlage) and (Daten.VORLAGE_PRAEFIX + "x1") in werte.vorlage, "Vorlagen, auch eigene")

	print("Seltenes eine Ebene tiefer: Feinseiten")
	var stub := _Zimmer.new()
	stub.daten = daten
	stub.raum = daten.raeume[0]
	add_child(stub)
	var seiten := Anpassen.new(stub)
	for g in Inhalt.RAUM:
		for k in Inhalt.kacheln(str(g[0]), daten):
			if str(k.art) == "mehr" or bool(k.get("eigen", false)):
				var s := Inhalt.seite(k)
				check(not (seiten.seite_fuer(s).get("zeilen", []) as Array).is_empty(), "%s öffnet „%s“" % [k.id, s])
			var fz := Inhalt.farbziel(k)
			if not fz.is_empty():
				var seite_f := seiten.seite_fuer(Inhalt.seite(k, "", true))
				var zeile := (seite_f.get("zeilen", []) as Array).filter(func(z: Dictionary) -> bool: return str(z.art) == "farbe" and str(z.text) == str(fz[2]))
				if not werte.has("_" + str(k.art)):
					check(zeile.size() == 1, "Farbrad für %s: Zeile „%s“" % [k.art, fz[2]])
				werte["_" + str(k.art)] = true
	check(seiten.seite_fuer("wand:links").titel == G.SEITEN_NAMEN.links and seiten.seite_fuer("wand:dach").is_empty() and seiten.seite_fuer("quatsch").is_empty(),
			"Feinseiten nur aus der festen Liste")
	var mehr_texte: Array = []
	for s in ["waende", "boden", "decke", "fenster", "tuer", "licht", "groesse"]:
		for z in seiten.seite_fuer(s).get("zeilen", []):
			mehr_texte.append(str(z.get("text", "")))
	for t in ["Alle Wände gleich", "Zweite Farbe", "Leistenfarbe", "Größe", "Vorhangfarbe", "Platz an der Wand", "Griff", "Farbtemperatur",
			"LED-Farbe", "Als eigene Stimmung speichern", "Breite", "Tiefe"]:
		check(t in mehr_texte, "Feinseite: „%s“" % t)

	print("Was eine Kachel im Zimmer tut")
	var raum: Dictionary = stub.raum
	check(Inhalt.aktiv(Inhalt.kacheln("@waende", daten)[0], raum) and Inhalt.aktiv(Inhalt.kacheln("@boden", daten)[0], raum), "Standard: Anstrich und Dielen stehen im Zimmer")
	var tapete: Dictionary = Inhalt.kacheln("@waende", daten).filter(func(k: Dictionary) -> bool: return str(k.id) == "@waende:tapete:streifen")[0]
	Inhalt.anwenden(tapete, stub, "links")
	check(stub.letzter("wand_werte") == ["wand_werte", "links", { "m": "tapete", "mu": "streifen" }], "Tapete mit Muster an eine Wand")
	check(Inhalt.aktiv(tapete, raum, "links") and not Inhalt.aktiv(tapete, raum), "Häkchen: an der linken Wand, nicht an allen")
	var marmor: Dictionary = Inhalt.kacheln("@boden", daten).filter(func(k: Dictionary) -> bool: return str(k.wert) == "marmor")[0]
	Inhalt.anwenden(marmor, stub)
	check(stub.letzter("raum_werte") == ["raum_werte", "boden", { "a": "marmor", "f": G.BODEN_STD.marmor, "f2": "" }], "Boden mit seiner eigenen Farbe")
	Inhalt.anwenden(Inhalt.kacheln("@licht", daten)[1], stub)
	check(stub.letzter("stimmung_anwenden") == ["stimmung_anwenden", str(G.STIMMUNGEN[1][0]), false], "Stimmung als Probe (ohne eigenen Schritt)")
	var form: Dictionary = Inhalt.kacheln("@groesse", daten)[5]
	Inhalt.anwenden(form, stub)
	check(stub.letzter("groesse_setzen") == ["groesse_setzen", int(form.w), int(form.d)] and not bool(form.sofort), "Raumgröße erst mit A")
	Inhalt.farbe_setzen(marmor, stub, "#26272b")
	check(Inhalt.farbe(marmor, stub.raum) == "#26272b", "Farbe des Bodens")

	print("Bedienung")
	stub.raum = Daten.standard()["raeume"][0]
	stub.aufrufe.clear()
	var ui := KatalogUi.new()
	ui.zimmer = stub
	add_child(ui)
	ui.dock(true)
	var bb: Node = ui._bilder
	check(bb._warte.is_empty() and not bb._laeuft and bb._buehne == null, "Leiste im Bauen (Menü zu): keine Bilder, keine Bühne")
	ui.oeffnen()
	check(ui.kategorie_id() == "sitzen" and str(ui.kachel().art) == "moebel", "öffnet bei Sitzen")
	check(bb._laeuft or not bb._warte.is_empty(), "Menü auf: die Bilder der sichtbaren Kacheln kommen")
	var sofa := ui.gewaehlt()
	var v0 := ui.variante(sofa)
	check(ui.taste("y") and ui.variante(sofa) != v0, "Y: nächste Farbe des Möbels (%s → %s)" % [v0, ui.variante(sofa)])
	var h := ui.hinweise()
	check(h.size() <= 4 and str(h.back()[0]) == "b" and h.has(["y", "Farbe"]) and h.has(["a", "Platzieren"]), "Tastenzeile Möbel: %s" % str(h))
	ui.bereich("@fenster")
	var reihen := {}
	for i in ui._pos.size():
		reihen[str(ui._kacheln[i].art)] = (ui._pos[i] as Vector2i).y
	check(int(reihen.fenster) == 0 and int(reihen.vorhang) == 1 and int(reihen.tuer) == 2, "Fenster, Vorhänge, Türen je eine Reihe (%s)" % str(reihen))
	check(str(ui.kachel().wert) == str(stub.raum.fenster.a), "Wahl steht auf dem, was im Zimmer ist")
	ui.schritt("down")
	check(str(ui.kachel().art) == "vorhang" and ui.angefasst(), "Steuerkreuz runter: in die nächste Reihe")
	ui.bereich("@waende", "hinten")
	check(ui.wand_ziel == "hinten" and str(ui.kachel().wert) == "anstrich" and not ui.angefasst(), "Wand gewählt: nur diese Wand, ohne Probe")
	ui.schritt("right")
	check(ui.angefasst() and str(ui.kachel().wert) == "kalk", "rechts: Kalkputz")
	stub.bau_probe(ui.kachel(), "", ui.wand_ziel)
	check(str(stub.raum.waende.hinten.m) == "kalk" and str(stub.raum.waende.links.m) == "anstrich", "Probe nur an der hinteren Wand")
	check(ui.hinweise().has(["a", "Übernehmen"]) and ui.hinweise().has(["y", "Farbe"]) and ui.hinweise().has(["x", "Rückgängig"]), "Tastenzeile Oberfläche: %s" % str(ui.hinweise()))
	ui.taste("y")
	check(ui._farben and ui.hinweise().size() == 2, "Y: Farbleiste")
	var vorher := str(stub.raum.waende.hinten.f)
	ui.schritt("right")
	check(str(stub.raum.waende.hinten.f) != vorher and str(stub.letzter("bau_probe")[2]) != "", "Farbe sofort an der Wand")
	ui.taste("b")
	check(str(stub.raum.waende.hinten.f) == vorher and not ui._farben, "B: Farbe von vorher, zurück im Raster")
	ui.taste("a")
	check(stub.letzter("bau_uebernehmen") == ["bau_uebernehmen"] and str(stub.raum.waende.hinten.m) == "kalk" and not stub.offen, "A übernimmt die Probe")
	ui.schritt("right")
	stub.bau_probe(ui.kachel(), "", ui.wand_ziel)
	ui.kategorie(1)
	check(str(stub.raum.waende.hinten.m) == "kalk" and stub.letzter("bau_verwerfen") == ["bau_verwerfen"] and ui.wand_ziel == "", "anderer Bereich: Probe zurück")
	ui.bereich("@waende")
	var ende := ui._kacheln.size() - 1
	ui._sel = ende
	check(str(ui.kachel().art) == "mehr" and ui.taste("a") and stub.letzter("bau_seite") == ["bau_seite", "waende"], "„Alle Einstellungen“ öffnet die Feinseite")
	ui.bereich("eigene")
	check(ui.gewaehlt() == KatalogUi.NEU and ui.hinweise()[0] == ["a", "Neu bauen"], "Eigene: vorn „Neu bauen“")
	ui.schliessen()
	check(not ui.ist_offen() and bb._warte.is_empty(), "zu: nichts wartet mehr auf ein Bild")
	ui.variante_merken("sofa", "senf")
	check(ui.variante("sofa") == "senf", "Farbe vom Platzieren gemerkt")

	print("Regal einrichten: Tafel statt Liste")
	for t in ["spieleregal", "trophaeenschrank", "plattenregal"]:
		var rg_gr := RegalTafel.gruppen_fuer(t)
		check(not rg_gr.is_empty() and rg_gr.all(func(g: Array) -> bool: return IconsS.P.has(str(g[2]))), "%s: Bereiche mit Zeichen" % t)
	var filter: Array = seiten.filter_gruppen()
	check(str(filter[0][0]) == "Auswahl" and (filter[0][1] as Array).size() == G.FILTER_OHNE_WERT.size(), "Auswahl: eingeräumt, alle, installiert …")
	var regal_felder := {}
	for t in ["spieleregal", "trophaeenschrank", "plattenregal"]:
		for g in RegalTafel.gruppen_fuer(t):
			for k in RegalTafel.kacheln(str(g[0]), 3, t, filter, [["ps2", "PlayStation 2"]]):
				var key := "%s|%s|%s" % [t, str(k.feld) if str(k.feld) != "" else str(k.art), str(k.wert)]
				regal_felder[key] = true
	var soll_regal: Array = ["spieleregal|aktion|einraeumen", "spieleregal|aktion|ausraeumen", "spieleregal|ab|true", "spieleregal|ab|false"]
	for fi in G.FILTER_OHNE_WERT:
		soll_regal.append("spieleregal|fi|" + str(fi))
	for liste in [["spieleregal", "so", G.SORTIERUNGEN], ["spieleregal", "da", G.DARSTELLUNGEN], ["spieleregal", "de", G.DEKO], ["spieleregal", "ps2", G.HUELLEN],
			["trophaeenschrank", "fi", G.POKAL_FILTER], ["trophaeenschrank", "so", G.POKAL_SORT], ["plattenregal", "so", G.PLATTEN_SORT],
			["plattenregal", "da", G.PLATTEN_DARST]]:
		for p in liste[2]:
			soll_regal.append("%s|%s|%s" % [liste[0], liste[1], str(p[0])])
	var fehlt: Array = soll_regal.filter(func(x: String) -> bool: return not regal_felder.has(x))
	check(fehlt.is_empty(), "alles von der Seite des Regals als Kachel (fehlt: %s)" % str(fehlt))
	stub.raum = Daten.standard()["raeume"][0]
	var ri := -1
	for j in (stub.raum.moebel as Array).size():
		if str(stub.raum.moebel[j].t) == "spieleregal":
			ri = j
	check(ri >= 0, "im Standardzimmer steht ein Spieleregal")
	var seite_r := seiten.seite_regal(ri)
	check(str(seite_r.get("tafel", "")) == "regal" and int(seite_r.moebel) == ri, "Seite des Regals ist eine Tafel")
	var so_kachel: Dictionary = RegalTafel.kacheln("ordnung", ri, "spieleregal", [], [])[1]
	Inhalt.anwenden(so_kachel, stub)
	check(stub.letzter("regal_setzen") == ["regal_setzen", ri, "so", str(so_kachel.wert)], "Sortierung als Probe im Regal")
	var hk: Dictionary = RegalTafel.kacheln("huellen", ri, "spieleregal", [], [["ps2", "PlayStation 2"]])[2]
	Inhalt.anwenden(hk, stub)
	check(stub.letzter("huelle_setzen") == ["huelle_setzen", "ps2", str(hk.wert)], "Hülle je System")
	var tafel := RegalTafel.new()
	add_child(tafel)
	seite_r["zimmer"] = stub
	tafel.zeigen(seite_r)
	check(tafel.ist_offen() and tafel.kategorie_id() == "spiele", "öffnet bei „Welche Spiele“")
	var ht: Array = tafel.hinweise("Fertig")
	check(ht.size() <= 4 and ht.back() == ["b", "Fertig"], "Tastenzeile: %s" % str(ht))
	tafel._sel = 0
	check(tafel.taste("a") and stub.letzter("regal_einraeumen") == ["regal_einraeumen", ri], "A auf „Selbst einräumen“: das Raster der Bibliothek")
	check(tafel.taste("rb") and tafel.kategorie_id() == "ordnung", "RB: Sortierung")
	tafel.schliessen()
	tafel.queue_free()

	print("Bilder: einmal gerendert, gemerkt")
	check(Bilder.moebel_schluessel("sofa", "senf") == "m|sofa|senf" and Bilder.wand_schluessel("tapete", "karo", "#ffffff", "") == "w|tapete|karo|#ffffff|",
			"Schlüssel je Möbel und Farbe bzw. Oberfläche")
	Bilder._merken("m|test|a", ImageTexture.new())
	check(Bilder.hat("m|test|a"), "gemerkt")
	Bilder.vergessen("m|test|")
	check(not Bilder.hat("m|test|a"), "eigenes Möbel geändert: vergessen")
	for i in Bilder.MAX + 5:
		Bilder._merken("x|%d" % i, ImageTexture.new())
	check(Bilder._bilder.size() <= Bilder.MAX and not Bilder.hat("x|0") and Bilder.hat("x|%d" % (Bilder.MAX + 4)), "höchstens MAX, das älteste fällt zuerst")
	Bilder.vergessen("x|")

	ui.queue_free()
	stub.queue_free()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

extends RefCounted
## Seiten der Seitenleiste „Anpassen“ (anpassen_ui.gd): was sich am Zimmer und an jedem Möbel
## einstellen lässt. Jede Zeile liest ihren Wert aus den Daten des Raums und ändert ihn über das
## Zimmer (zimmer.gd) – das merkt den Stand für Rückgängig, baut weich um und speichert.

const G := preload("res://src/room/gestalt.gd")
const Katalog := preload("res://src/room/katalog.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")
const Licht := preload("res://src/room/licht.gd")
const Leistung := preload("res://src/room/leistung.gd")
const Backlog := preload("res://src/library/backlog.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const GameFilter := preload("res://src/library/game_filter.gd")

const KELVIN := [[1800, "1800 K · Kerze"], [2200, "2200 K · Glut"], [2400, "2400 K"], [2700, "2700 K · Warmweiß"], [3000, "3000 K"],
	[3500, "3500 K"], [4000, "4000 K · Neutral"], [5000, "5000 K"], [6500, "6500 K · Tageslicht"]]

## Offen getypt (Control statt Zimmer): Tests betreiben das Menü mit einem nachgestellten Zimmer (logic_zimmerbau, logic_baumenue).
var z: Control                   ## das Zimmer


func _init(zimmer: Control) -> void:
	z = zimmer


# --- Bausteine ---------------------------------------------------------------------------------------

static func _wahl(text: String, optionen: Array, wert: Callable, setzen: Callable, extra := {}) -> Dictionary:
	var d := { "art": "wahl", "text": text, "optionen": optionen, "wert": wert, "setzen": setzen }
	d.merge(extra, true)
	return d


static func _stufe(text: String, optionen: Array, wert: Callable, setzen: Callable, extra := {}) -> Dictionary:
	var d := _wahl(text, optionen, wert, setzen, extra)
	d.art = "stufe"
	return d


static func _farbe(text: String, wert: Callable, setzen: Callable, leer := "", extra := {}) -> Dictionary:
	var d := { "art": "farbe", "text": text, "wert": wert, "setzen": setzen }
	if leer != "":
		d["leer"] = leer
		d["std"] = ""
	d.merge(extra, true)
	return d


static func _seite(text: String, oeffnen: Callable, wert := Callable()) -> Dictionary:
	var d := { "art": "seite", "text": text, "oeffnen": oeffnen }
	if wert.is_valid():
		d["wert"] = wert
	return d


static func _aktion(text: String, tun: Callable, extra := {}) -> Dictionary:
	var d := { "art": "aktion", "text": text, "tun": tun }
	d.merge(extra, true)
	return d


static func _abschnitt(text: String) -> Dictionary:
	return { "art": "abschnitt", "text": text }


static func _info(text: String) -> Dictionary:
	return { "art": "info", "text": text }


## Seite mit „neu“: nach Rückgängig liest die Leiste sie frisch (gleiche Bauanleitung).
static func _s(titel: String, kicker: String, zeilen: Array, neu: Callable) -> Dictionary:
	return { "titel": titel, "kicker": kicker, "zeilen": zeilen, "neu": neu }


func _r() -> Dictionary:
	return z.get("raum")


# --- Zimmer ------------------------------------------------------------------------------------------

## Das Zimmer-Menü (≡): nur noch, was nicht am Ort liegt – du (Figur, Haustier), Teilen und Online,
## „Mehr“. Leben, Bauen und Foto wechselt die Modus-Leiste oben; Wände, Boden, Decke, Fenster, Tür,
## Größe, Licht und Vorlagen stehen im Bauen in der Leiste des Bau-Menüs (katalog_ui.gd) – hier nur
## ihre Feinseiten (seite_fuer).
func seite_zimmer() -> Dictionary:
	var zl: Array = [
		_aktion("Deine Figur", func() -> void: z.call("figur_editor", "figur"), { "hinweis": "Aussehen, Kleidung, Emotes" }),
		_aktion("Dein Haustier", func() -> void: z.call("figur_editor", "tier"), { "hinweis": "Art, Fell, Name" }),
		_abschnitt("Teilen"),
		_aktion("Zimmer teilen", func() -> void: z.call("teilen"), { "hinweis": "Als Datei oder QR-Code – ohne Upload" }),
		_aktion("Zimmer-Datei einführen", func() -> void: z.call("einfuehren_datei"), { "hinweis": "Eine .uzaizimmer-Datei von diesem PC" }),
		_aktion("Zimmer-Code einführen", func() -> void: z.call("einfuehren_code"), { "hinweis": "Text aus der Zwischenablage (UZZ1:…)" }),
		_aktion("Online", func() -> void: z.call("online_oeffnen"), { "hinweis": "Freunde einladen, Gäste, Sperrliste" }),
		_abschnitt(""),
		_seite("Kamera und Bild", seite_kamera, func() -> String: return "%d°" % int(Config.get_value("room.fov", 70))),
		_seite("Mehr", seite_mehr, func() -> String: return "Grafik, Bildrate, Hüllen"),
	]
	return _s(str(_r().name), "Zimmer", zl, seite_zimmer).merged({ "roh": true })


## Ego-Kamera wie in einem PC-Spiel: Empfindlichkeit für Maus und Stick (1:1, ohne Glätten und
## Beschleunigung), Y-Achse, Sichtfeld, Tiefenschärfe (Standard aus). Wirkt sofort.
func seite_kamera() -> Dictionary:
	var prozent := func(k: String) -> int: return roundi(float(Config.get_value(k, 1.0)) * 100.0)
	return _s("Kamera und Bild", "Zimmer", [
		{ "art": "zahl", "text": "Empfindlichkeit Maus", "min": 20, "max": 400, "schritt": 10, "einheit": "%d %%",
			"wert": prozent.bind("room.maus"), "setzen": func(v: Variant) -> void: Config.set_value("room.maus", float(v) / 100.0) },
		{ "art": "zahl", "text": "Empfindlichkeit Stick", "min": 30, "max": 300, "schritt": 10, "einheit": "%d %%",
			"wert": prozent.bind("room.stick"), "setzen": func(v: Variant) -> void: Config.set_value("room.stick", float(v) / 100.0) },
		{ "art": "schalter", "text": "Y-Achse umkehren", "wert": func() -> bool: return bool(Config.get_value("room.y_umkehren", false)),
			"setzen": func(v: Variant) -> void: Config.set_value("room.y_umkehren", bool(v)) },
		{ "art": "zahl", "text": "Sichtfeld", "min": 55, "max": 100, "schritt": 5, "einheit": "%d°",
			"wert": func() -> int: return int(Config.get_value("room.fov", 70)), "setzen": func(v: Variant) -> void: Config.set_value("room.fov", int(v)) },
		{ "art": "schalter", "text": "Kopfwippen", "hinweis": "Beim Gehen in der Ich-Ansicht, dezent",
			"wert": func() -> bool: return bool(Config.get_value("room.wippen", true)),
			"setzen": func(v: Variant) -> void: Config.set_value("room.wippen", bool(v)) },
		{ "art": "schalter", "text": "Tiefenschärfe", "hinweis": "Nur beim Ansehen und im Fotomodus, dezent",
			"wert": func() -> bool: return bool(Config.get_value("room.tiefe", false)),
			"setzen": func(v: Variant) -> void: Config.set_value("room.tiefe", bool(v)) },
		{ "art": "schalter", "text": "Spielton aus dem Fernseher", "hinweis": "Beim Herumlaufen leiser und von der Seite",
			"wert": func() -> bool: return bool(Config.get_value("room.raumton", true)),
			"setzen": func(v: Variant) -> void: Config.set_value("room.raumton", bool(v)) },
	], seite_kamera)


## Bau-Menü (bau_inhalt.gd seite): Feinseite zu einer Kennung – „waende“, „wand:<seite>“ (leer: alle),
## „boden“, „decke“, „fenster“, „tuer“, „licht“, „groesse“, „stimmung:<id>“, „vorlage:<id>“,
## „eigenes:<id>“. Unbekannt: leer.
func seite_fuer(kennung: String) -> Dictionary:
	var art := kennung.get_slice(":", 0)
	var wert := kennung.substr(art.length() + 1)
	match art:
		"waende": return seite_waende()
		"wand": return seite_wand(wert) if wert == "" or wert in G.SEITEN else {}
		"boden": return seite_boden()
		"decke": return seite_decke()
		"fenster": return seite_fenster()
		"tuer": return seite_tuer()
		"licht": return seite_licht()
		"groesse": return seite_groesse()
		"stimmung": return seite_eigene_stimmung(wert)
		"vorlage": return seite_eigene_vorlage(wert)
		"eigenes": return seite_eigenes(wert) if Katalog.ist_eigen(wert) else {}
	return {}


## Bauen › Raum: die Feinseite eines Bereichs (bau_inhalt.gd RAUM).
func raum_seite(id: String) -> Dictionary:
	match id:
		"@waende": return seite_waende()
		"@boden": return seite_boden()
		"@decke": return seite_decke()
		"@fenster": return seite_fenster()
		"@tuer": return seite_tuer()
		"@groesse": return seite_groesse()
		"@licht": return seite_licht()
		"@vorlagen": return seite_vorlagen()
	return {}


## Selten gebraucht: eigene Möbel (Baukasten), Hüllen je System, Grafik und womit Uzai startet.
func seite_mehr() -> Dictionary:
	return _s("Mehr", "Zimmer gestalten", [
		_seite("Eigene Möbel", seite_eigene, func() -> String: return str((z.get("daten").get("eigene", []) as Array).size())),
		_seite("Hüllen je System", seite_huellen),
		_abschnitt("Einstellungen"),
		_wahl("Grafik", Licht.STUFEN,
			func() -> String: return str(Config.get_value("room.grafik", "auto")),
			func(v: Variant) -> void: z.call("grafik_setzen", str(v)),
			{ "hinweis": "Automatisch misst, was dein PC flüssig schafft" }),
		_wahl("Bildrate", Leistung.RATEN,
			func() -> String: return str(Config.get_value("room.fps", "bildschirm")),
			func(v: Variant) -> void: z.call("fps_setzen", str(v)),
			{ "hinweis": "Weniger Bilder je Sekunde: leiser, aber weniger flüssig" }),
		_wahl("Beim Einschalten", [["zimmer", "Dein Zimmer"], ["klassisch", "Klassische Startseite"]],
			func() -> String: return str(Config.get_value("room.start", "klassisch")),
			func(v: Variant) -> void: Config.set_value("room.start", str(v))),
	], seite_mehr)


static func _m(felder: int) -> String:
	var m := felder * 0.5
	return ("%d" % int(m)) if is_equal_approx(m, roundf(m)) else ("%.1f" % m).replace(".", ",")


func _stimmung_name() -> String:
	var st := str(_r().licht.get("st", ""))
	if st == "":
		return tr("Eigene Einstellung")
	var n := G.wahl_name(G.STIMMUNGEN, st)
	if n != "":
		return tr(n)
	for s in z.get("daten").get("stimmungen", []):
		if str(s.id) == st:
			return str(s.name)
	return ""


# --- Wände -----------------------------------------------------------------------------------------

func seite_waende() -> Dictionary:
	var zl: Array = [_seite("Alle Wände gleich", func() -> Dictionary: return seite_wand(""))]
	zl.append(_abschnitt("Jede Wand einzeln"))
	for s in G.SEITEN:
		var seite := str(s)
		zl.append(_seite(str(G.SEITEN_NAMEN[seite]), func() -> Dictionary: return seite_wand(seite),
			func() -> String: return G.wahl_name(G.WANDMATERIAL, str(_r().waende[seite].m))))
	return _s("Wände", "Zimmer gestalten", zl, seite_waende)


## Eine Wand (seite) oder alle zugleich (seite = „“: Werte der hinteren Wand gelten für alle).
func seite_wand(seite: String) -> Dictionary:
	var lesen := func(k: String) -> String: return str(_r().waende["hinten" if seite == "" else seite].get(k, ""))
	var setzen := func(v: Variant, k: String) -> void: z.call("wand_setzen", seite, k, v)
	var zl: Array = [
		_wahl("Material", G.WANDMATERIAL, lesen.bind("m"), setzen.bind("m")),
		_farbe("Farbe", lesen.bind("f"), setzen.bind("f")),
		_wahl("Tapetenmuster", G.MUSTER, lesen.bind("mu"), setzen.bind("mu"), { "hinweis": "Wirkt bei Material „Tapete“", "std": "" }),
		_farbe("Musterfarbe", lesen.bind("mf"), setzen.bind("mf"), "Passend", { "hinweis": "Muster der Tapete, Paneel unten" }),
	]
	if seite != "":
		zl.append(_aktion("Auf alle Wände übertragen", func() -> void: z.call("wand_uebertragen", seite)))
	var titel: String = "Alle Wände" if seite == "" else str(G.SEITEN_NAMEN[seite])
	return _s(titel, "Wände", zl, func() -> Dictionary: return seite_wand(seite))


func seite_boden() -> Dictionary:
	var lesen := func(k: String) -> String: return str(_r().boden.get(k, ""))
	var setzen := func(v: Variant, k: String) -> void: z.call("raum_setzen", "boden", k, v)
	return _s("Boden", "Zimmer gestalten", [
		_wahl("Art", G.BODENARTEN, lesen.bind("a"), setzen.bind("a")),
		_farbe("Farbe", lesen.bind("f"), setzen.bind("f")),
		_farbe("Zweite Farbe", lesen.bind("f2"), setzen.bind("f2"), "Passend", { "hinweis": "Fugen, Schachbrett, Splitter, Adern" }),
	], seite_boden)


func seite_decke() -> Dictionary:
	var dl := func(k: String) -> String: return str(_r().decke.get(k, ""))
	var ds := func(v: Variant, k: String) -> void: z.call("raum_setzen", "decke", k, v)
	var sl := func(k: String) -> String: return str(_r().sockel.get(k, ""))
	var ss := func(v: Variant, k: String) -> void: z.call("raum_setzen", "sockel", k, v)
	return _s("Decke und Leisten", "Zimmer gestalten", [
		_wahl("Decke", G.DECKEN, dl.bind("a"), ds.bind("a")),
		_farbe("Deckenfarbe", dl.bind("f"), ds.bind("f")),
		_abschnitt("Sockelleiste"),
		_wahl("Leiste", G.SOCKEL, sl.bind("a"), ss.bind("a")),
		_farbe("Leistenfarbe", sl.bind("f"), ss.bind("f")),
	], seite_decke)


func seite_fenster() -> Dictionary:
	var l := func(k: String) -> Variant: return _r().fenster.get(k, "")
	var s := func(v: Variant, k: String) -> void: z.call("raum_setzen", "fenster", k, v)
	var groessen: Array = []
	for i in G.FENSTERGROESSEN.size():
		groessen.append([i, str(G.FENSTERGROESSEN[i][0])])
	return _s("Fenster", "Zimmer gestalten", [
		_wahl("Art", G.FENSTERARTEN, l.bind("a"), s.bind("a")),
		_stufe("Größe", groessen, l.bind("g"), s.bind("g")),
		_farbe("Rahmen", l.bind("rf"), s.bind("rf")),
		_abschnitt("Vorhänge"),
		_wahl("Vorhang", G.VORHAENGE, l.bind("v"), s.bind("v")),
		_farbe("Vorhangfarbe", l.bind("vf"), s.bind("vf")),
	], seite_fenster)


func seite_tuer() -> Dictionary:
	var l := func(k: String) -> String: return str(_r().tuer.get(k, ""))
	var s := func(v: Variant, k: String) -> void: z.call("raum_setzen", "tuer", k, v)
	return _s("Tür", "Zimmer gestalten", [
		_wahl("Art", G.TUERARTEN, l.bind("a"), s.bind("a")),
		_stufe("Platz an der Wand", G.TUERPLAETZE, l.bind("p"), s.bind("p")),
		_farbe("Farbe", l.bind("f"), s.bind("f")),
		_wahl("Griff", G.GRIFF_FARBEN, l.bind("gf"), s.bind("gf")),
	], seite_tuer)


func seite_groesse() -> Dictionary:
	var masse: Array = []
	for n in range(8, 21, 2):
		masse.append([n, "%s m" % _m(n)])
	var groessen: Array = []
	for i in G.GROESSEN.size():
		groessen.append([i, str(G.GROESSEN[i][1])])
	return _s("Größe und Form", "Zimmer gestalten", [
		_wahl("Form", G.FORMEN, func() -> String: return _form()[0],
			func(v: Variant) -> void: _form_setzen(str(v), maxi(0, int(_form()[1])))),
		_stufe("Größe", groessen, func() -> int: return int(_form()[1]),
			func(v: Variant) -> void: _form_setzen(_form()[0] if _form()[0] != "" else "breit", int(v))),
		_abschnitt("Genau"),
		_stufe("Breite", masse, func() -> int: return int(_r().w), func(v: Variant) -> void: z.call("groesse_setzen", int(v), int(_r().d))),
		_stufe("Tiefe", masse, func() -> int: return int(_r().d), func(v: Variant) -> void: z.call("groesse_setzen", int(_r().w), int(v))),
		_info("Rückgängig mit X."),
	], seite_groesse)


## Form und Stufe des Raums, wenn seine Maße einer Stufe entsprechen (sonst „“ und -1).
func _form() -> Array:
	for f in G.RAUM_MASSE.keys():
		var stufen: Array = G.RAUM_MASSE[f]
		for i in stufen.size():
			if int(stufen[i][0]) == int(_r().w) and int(stufen[i][1]) == int(_r().d):
				return [f, i]
	return ["", -1]


func _form_setzen(form: String, stufe: int) -> void:
	var st: Array = G.RAUM_MASSE.get(form, G.RAUM_MASSE.breit)
	var m: Array = st[clampi(stufe, 0, st.size() - 1)]
	z.call("groesse_setzen", int(m[0]), int(m[1]))


# --- Licht -------------------------------------------------------------------------------------------

func _stimmung_optionen() -> Array:
	var out: Array = [["", "Eigene Einstellung"]]
	for s in G.STIMMUNGEN:
		out.append([s[0], s[1]])
	for s in z.get("daten").get("stimmungen", []):
		out.append([str(s.id), str(s.name), true])
	return out


func seite_licht() -> Dictionary:
	var l := func(k: String) -> Variant: return _r().licht.get(k, "")
	var s := func(v: Variant, k: String) -> void: z.call("licht_setzen", k, v)
	var hell: Array = []
	for p in range(0, 201, 10):
		hell.append([p, "Aus" if p == 0 else "%d %%" % p])
	var zl: Array = [
		_wahl("Stimmung", _stimmung_optionen(), l.bind("st"), func(v: Variant) -> void: z.call("stimmung_anwenden", str(v)),
			{ "hinweis": "Auch im Zimmer mit LT (Stimmungs-Rad)" }),
		_abschnitt("Draußen"),
		_wahl("Tageszeit", G.ZEITEN, l.bind("z"), s.bind("z")),
		_wahl("Wetter", G.WETTER, l.bind("we"), s.bind("we")),
		_abschnitt("Alle Lampen"),
		_stufe("Farbtemperatur", KELVIN, l.bind("k"), s.bind("k"), { "std": 2700, "einheit": "%d K" }),
		_stufe("Helligkeit", hell, l.bind("h"), s.bind("h"), { "std": 100 }),
		_farbe("Lampenfarbe", l.bind("lf"), s.bind("lf"), "Farbtemperatur", { "hinweis": "Eine Farbe für alle Lampen" }),
		_farbe("LED-Farbe", l.bind("fa"), s.bind("fa"), "", { "hinweis": "LED-Leisten im Zimmer" }),
		_abschnitt("Eigene Stimmungen"),
		_aktion("Als eigene Stimmung speichern", func() -> void: z.call("stimmung_speichern_fragen")),
	]
	for st in z.get("daten").get("stimmungen", []):
		var id := str(st.id)
		var zs := _seite(str(st.name), func() -> Dictionary: return seite_eigene_stimmung(id))
		zs["roh"] = true
		zl.append(zs)
	return _s("Licht und Stimmung", "Zimmer gestalten", zl, seite_licht)


func seite_eigene_stimmung(id: String) -> Dictionary:
	var name_ := ""
	for st in z.get("daten").get("stimmungen", []):
		if str(st.id) == id:
			name_ = str(st.name)
	return _s(name_, "Eigene Stimmung", [
		_aktion("Anwenden", func() -> void: z.call("stimmung_anwenden", id)),
		_aktion("Mit dem jetzigen Licht überschreiben", func() -> void: z.call("stimmung_ueberschreiben", id)),
		_aktion("Löschen", func() -> void: z.call("stimmung_loeschen", id), { "gefahr": true }),
	], func() -> Dictionary: return seite_eigene_stimmung(id)).merged({ "roh": true })


# --- Hüllen, Vorlagen, eigene Möbel --------------------------------------------------------------------

func seite_huellen() -> Dictionary:
	var systeme := {}
	for g in Library.visible_games():
		var sid := str(g.get("system", ""))
		if sid != "" and G.kennung(sid):
			systeme[sid] = true
	var ids: Array = systeme.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return _sys_name(a).naturalnocasecmp_to(_sys_name(b)) < 0)
	var zl: Array = [_info("Gilt für alle Regale.")]
	for sid in ids:
		var s := str(sid)
		zl.append(_wahl(_sys_name(s), G.HUELLEN, func() -> String: return str(z.get("daten").get("huellen", {}).get(s, "auto")),
			func(v: Variant) -> void: z.call("huelle_setzen", s, str(v)), { "std": "auto" }))
	return _s("Hüllen je System", "Regale", zl, seite_huellen)


static func _sys_name(sid: String) -> String:
	var n := str(Config.system(sid).get("name", ""))
	if n == "":
		n = Library.Stores.name_of(sid)
	return n if n != "" else sid


func seite_vorlagen() -> Dictionary:
	var zl: Array = [_info("Ersetzt das Zimmer. Rückgängig mit X.")]
	for v in Vorlagen.LISTE:
		var id := str(v[0])
		zl.append(_aktion(str(v[1]), func() -> void: z.call("vorlage_uebernehmen", id), { "hinweis": str(v[2]) }))
	# Eigene Vorlagen (geteilte Zimmer, „Als Vorlage speichern“): Name des Nutzers, nie übersetzt.
	var eigene: Array = z.get("daten").get("vorlagen", [])
	if not eigene.is_empty():
		zl.append(_abschnitt("Deine Vorlagen"))
	for v in eigene:
		var vid := str(v.id)
		var n := (v.raum.moebel as Array).size()
		var ze := _seite(str(v.name), func() -> Dictionary: return seite_eigene_vorlage(vid), func() -> String: return tr("%d Möbel") % n)
		ze["roh"] = true
		zl.append(ze)
	return _s("Vorlagen", "Zimmer gestalten", zl, seite_vorlagen)


func seite_eigene_vorlage(id: String) -> Dictionary:
	var name_ := ""
	for v in z.get("daten").get("vorlagen", []):
		if str(v.id) == id:
			name_ = str(v.name)
	return _s(name_, "Eigene Vorlage", [
		_info("Ersetzt das Zimmer. Rückgängig mit X."),
		_aktion("Übernehmen", func() -> void: z.call("vorlage_uebernehmen", id)),
		_aktion("Löschen", func() -> void: z.call("vorlage_loeschen", id), { "gefahr": true }),
	], func() -> Dictionary: return seite_eigene_vorlage(id)).merged({ "roh": true })


func seite_eigene() -> Dictionary:
	var zl: Array = [
		_aktion("Neues Möbel bauen", func() -> void: z.call("baukasten_oeffnen", ""), { "hinweis": "Aus Platten, Kästen, Beinen, Kissen, Schirmen …" }),
	]
	var liste: Array = z.get("daten").get("eigene", [])
	if not liste.is_empty():
		zl.append(_abschnitt("Deine Möbel"))
	for e in liste:
		var id := str(e.id)
		var ze := _seite(str(e.name), func() -> Dictionary: return seite_eigenes(id), func() -> String: return tr("%d Teile") % (e.teile as Array).size())
		ze["roh"] = true
		zl.append(ze)
	if liste.is_empty():
		zl.append(_info("Keine eigenen Möbel."))
	return _s("Eigene Möbel", "Baukasten", zl, seite_eigene)


func seite_eigenes(id: String) -> Dictionary:
	var e: Dictionary = Katalog.eigen(id)
	var zl: Array = [
		_aktion("Bearbeiten", func() -> void: z.call("baukasten_oeffnen", id)),
		_aktion("Ins Zimmer stellen", func() -> void: z.call("eigenes_hinstellen", id)),
		_aktion("Kopieren", func() -> void: z.call("eigenes_kopieren", id)),
		_aktion("Löschen", func() -> void: z.call("eigenes_loeschen", id), { "gefahr": true, "hinweis": "Auch aus dem Zimmer" }),
	]
	return _s(str(e.get("name", "")), "Eigenes Möbel", zl, func() -> Dictionary: return seite_eigenes(id)).merged({ "roh": true })


# --- Ein Möbel -----------------------------------------------------------------------------------------

func _it(i: int) -> Dictionary:
	var ml: Array = _r().moebel
	return ml[i] if i >= 0 and i < ml.size() else {}


## Bezeichnung der Katalog-Varianten je Möbel.
static func _varianten_name(t: String) -> String:
	var vs := Katalog.varianten(t)
	if vs == Katalog.STOFFE:
		return "Stoff"
	if vs == Katalog.HOELZER:
		return "Holz"
	return str({ "medienwand": "Fernseher", "bild": "Motiv", "pflanze": "Pflanze", "topfpflanze": "Pflanze",
		"lichterkette": "Lichter", "led_leiste": "Platz" }.get(t, "Art"))


func seite_moebel(i: int) -> Dictionary:
	var it := _it(i)
	if it.is_empty():
		return {}
	var t := str(it.t)
	var info := Katalog.info(t)
	var l := func(k: String) -> Variant: return _it(i).get(k, "")
	var s := func(v: Variant, k: String) -> void: z.call("moebel_setzen", i, k, v)
	var zl: Array = []
	if Katalog.ist_eigen(t):
		zl.append(_aktion("Im Baukasten bearbeiten", func() -> void: z.call("baukasten_oeffnen", t)))
	if Katalog.varianten(t).size() > 1:
		zl.append(_wahl(_varianten_name(t), Katalog.varianten(t), l.bind("v"), s.bind("v")))
	var st := Katalog.stufen(t)
	if not st.is_empty():
		var opt: Array = []
		for k in st.size():
			opt.append([k, str(st[k].name)])
		zl.append(_stufe("Größe", opt, func() -> int: return Katalog.stufe_von(_it(i)), s.bind("s")))
	if not Katalog.ist_eigen(t):
		var mats: Array = [["", "Wie im Katalog"]]
		for m in G.MATERIAL_REIHE:
			mats.append([m, G.material_name(str(m))])
		zl.append(_abschnitt("Oberfläche"))
		zl.append(_wahl("Material", mats, l.bind("m"), s.bind("m"), { "std": "" }))
		zl.append(_farbe("Farbe", l.bind("f"), s.bind("f"), "Natur"))
		zl.append(_wahl("Muster", G.MUSTER, l.bind("mu"), s.bind("mu"), { "hinweis": "Auf Stoffen und Teppichen", "std": "" }))
		zl.append(_farbe("Musterfarbe", l.bind("mf"), s.bind("mf"), "Passend"))
		if info.has("gestell"):
			zl.append(_abschnitt(str(info.gestell)))
			var mats2: Array = [["", "Wie im Katalog"]]
			for m in G.MATERIAL_REIHE:
				mats2.append([m, G.material_name(str(m))])
			zl.append(_wahl("Material", mats2, l.bind("m2"), s.bind("m2"), { "std": "" }))
			zl.append(_farbe("Farbe", l.bind("f2"), s.bind("f2"), "Natur"))
		if bool(info.get("beine", false)):
			zl.append(_wahl("Beine", G.BEINE, l.bind("be"), s.bind("be"), { "std": "" }))
		if bool(info.get("griffe", false)):
			zl.append(_wahl("Griffe", G.GRIFFE, l.bind("gr"), s.bind("gr"), { "std": "" }))
	if Katalog.nutzen(t) == "lampe" or t == "trophaeenschrank":
		zl.append(_abschnitt("Licht"))
		zl.append({ "art": "schalter", "text": "Eingeschaltet", "wert": func() -> bool: return bool(_it(i).get("an", true)),
			"setzen": func(v: Variant) -> void: z.call("moebel_setzen", i, "an", bool(v)) })
		zl.append(_seite("Licht einstellen", func() -> Dictionary: return seite_lampe(i)))
	match t:
		"spieleregal":
			zl.append(_abschnitt("Spiele im Regal"))
			zl.append(_seite("Regal einrichten", func() -> Dictionary: return seite_regal(i), func() -> String: return G.wahl_name(G.SORTIERUNGEN, str(_rg(i).so))))
		"trophaeenschrank", "plattenregal":
			zl.append(_abschnitt("Inhalt"))
			zl.append(_seite("Schrank einrichten" if t == "trophaeenschrank" else "Regal einrichten", func() -> Dictionary: return seite_regal(i)))
	zl.append(_abschnitt("Möbel"))
	if Katalog.ebene(t) != "wand":
		zl.append(_aktion("Drehen", func() -> void: z.call("moebel_drehen", i)))
	zl.append(_aktion("Alles auf Katalog zurücksetzen", func() -> void: z.call("moebel_zuruecksetzen", i)))
	zl.append(_aktion("Entfernen", func() -> void: z.call("moebel_entfernen", i), { "gefahr": true }))
	return _s(Katalog.name_of(t), "Möbel anpassen", zl, func() -> Dictionary: return seite_moebel(i)).merged({ "roh": Katalog.ist_eigen(t) })


func seite_lampe(i: int) -> Dictionary:
	var lget := func(k: String, std: Variant) -> Variant: return (_it(i).get("l", {}) as Dictionary).get(k, std)
	var lset := func(v: Variant, k: String) -> void: z.call("lampe_setzen", i, k, v)
	var temp: Array = [[0, "Wie das Zimmer"]]
	temp.append_array(KELVIN)
	var hell: Array = []
	for p in range(10, 201, 10):
		hell.append([p, "%d %%" % p])
	var weit: Array = []
	for p in range(50, 201, 25):
		weit.append([p, "%d %%" % p])
	return _s("Licht", Katalog.name_of(str(_it(i).get("t", ""))), [
		_stufe("Farbtemperatur", temp, lget.bind("k", 0), lset.bind("k"), { "std": 0, "einheit": "%d K" }),
		_farbe("Lichtfarbe", lget.bind("c", ""), lset.bind("c"), "Wie das Zimmer", { "hinweis": "Bunt statt weiß" }),
		_stufe("Helligkeit", hell, lget.bind("h", 100), lset.bind("h"), { "std": 100 }),
		_stufe("Reichweite", weit, lget.bind("w", 100), lset.bind("w"), { "std": 100 }),
	], func() -> Dictionary: return seite_lampe(i))


func _rg(i: int) -> Dictionary:
	var it := _it(i)
	return it.get("rg", G.std_regal(str(it.get("t", ""))))


## Regal, Pokalschrank, Plattenregal einrichten: keine Liste, sondern eine Tafel mit großen Kacheln
## (regal_tafel.gd) – welche Spiele (mit ihren Hüllen), Sortierung, Darstellung, Deko, Hüllen je
## System; die Seitenleiste zeigt sie statt ihrer Zeilen.
func seite_regal(i: int) -> Dictionary:
	var t := str(_it(i).get("t", ""))
	return { "tafel": "regal", "moebel": i, "zimmer": z, "seiten": self, "titel": "Einrichten", "kicker": Katalog.name_of(t), "zeilen": [] }


## Lesbarer Name einer Auswahl („system:snes“ → „System: Super Nintendo“).
func filter_name(fi: String) -> String:
	var art := fi.get_slice(":", 0)
	var wert := fi.substr(art.length() + 1)
	match art:
		"eigene": return tr("Selbst eingeräumt")
		"installiert": return tr("Installiert")
		"favoriten": return tr("Favoriten")
		"ungespielt": return tr("Noch nicht gespielt")
		"system": return _sys_name(wert)
		"systeme": return " + ".join(Array(wert.split(",", false)).map(func(s: String) -> String: return _sys_name(s)))
		"ordner": return str(Library.folder(wert).get("name", wert))
		"liste": return str(Library.list_by_id(wert).get("name", wert))
		"tag", "sammlung", "genre": return wert
		"status": return tr(Backlog.status_name(wert))
	return tr("Alle Spiele")


## Alle Auswahlen, die es in der Bibliothek gerade gibt, nach Art: [[Abschnitt, [[Auswahl, Name] …]] …]
## – erst die ohne Wert (eingeräumt, alle, installiert …), dann System, Ordner, Listen, Status,
## Sammlung, Tags, Genre (je höchstens 40, nach Namen).
func filter_gruppen() -> Array:
	var gruppen := { "system": {}, "ordner": {}, "liste": {}, "tag": {}, "sammlung": {}, "genre": {} }
	for g in Library.visible_games():
		var sid := str(g.get("system", ""))
		if sid != "":
			gruppen.system[sid] = true
		for tag in GameFields.tags_of(g):
			gruppen.tag[str(tag)] = true
		var c := GameFields.category_of(g)
		if c != "":
			gruppen.sammlung[c] = true
		for ge in GameFilter.genres_of(g):
			gruppen.genre[str(ge)] = true
	for f in Library.folders:
		gruppen.ordner[str(f.get("id", ""))] = true
	for li in Library.lists:
		gruppen.liste[str(li.get("id", ""))] = true
	var out: Array = [["Auswahl", G.FILTER_OHNE_WERT.map(func(fi: String) -> Array: return [fi, filter_name(fi)])]]
	var namen := { "system": "System", "ordner": "Ordner", "liste": "Listen", "tag": "Tags", "sammlung": "Sammlung", "genre": "Genre" }
	for art in ["system", "ordner", "liste", "status", "sammlung", "tag", "genre"]:
		var werte: Array = []
		if art == "status":
			for st in Backlog.STATUSES:
				werte.append(str(st[0]))
		else:
			werte = (gruppen[art] as Dictionary).keys()
		var opts: Array = []
		for w in werte:
			var fi2 := "%s:%s" % [art, str(w)]
			if G.pruefe_filter(fi2) == fi2:
				opts.append([fi2, filter_name(fi2)])
		if opts.is_empty():
			continue
		# Erst nach Namen, dann die ersten 40 (früher umgekehrt: bei mehr als 40 Tags oder Genres blieb eine
		# zufällige Auswahl, und was fehlte, hing an der Reihenfolge der Bibliothek).
		opts.sort_custom(func(a: Array, b: Array) -> bool: return str(a[1]).naturalnocasecmp_to(str(b[1])) < 0)
		out.append([str(namen.get(art, "Backlog")), opts.slice(0, 40)])
	return out

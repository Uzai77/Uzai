extends RefCounted
## Was in den Möbeln steht – dein Uzai im Zimmer (Punkt 131): Hüllen und Module deiner Spiele im
## Regal (viel Gespieltes leicht abgegriffen), Pokale im Schrank (Platin bei allen Erfolgen, sonst
## Gold, Silber, Bronze – mit eingraviertem Spielnamen) und Platten im Plattenregal (aus der
## gewählten Musikquelle). Dieselben Daten wie die 2D-Ansicht (Library, Achievements, Music),
## keine zweite Logik, kein Netz: Cover nur, wenn sie schon auf der Platte liegen, sonst das
## Ersatz-Cover von Uzai.
##
## Jeder Platz ist ein Eintrag { art, daten, fach, x, y, knoten | mm + index, basis, schild }, nach
## dem das Zimmer im Ansehen-Modus wählt (links/rechts im Fach, hoch/runter zwischen Fächern).
##
## Wie die Spiele ins Regal kommen, stellt jedes Regal selbst ein (gestalt.gd, „rg“): welche Spiele
## (zuerst keine – du räumst selbst ein, Auswahl „eigene“; oder System, Ordner, Liste, Tag, Sammlung,
## Backlog, Genre …), in welcher Reihenfolge
## (auch eine eigene), als Rücken, mit Cover nach vorn oder gemischt, Abnutzung und Deko. Die
## Hüllenart je System gilt für alle Regale. Pokalschrank und Plattenregal ebenso.

const SpotifyVerlauf := preload("res://src/core/spotify_verlauf.gd")
const F := preload("res://src/room/formen.gd")
const S := preload("res://src/room/stoffe.gd")
const CoverArt := preload("res://src/ui/components/cover_art.gd")
const PLATTE_S := preload("res://src/room/shaders/plattenhuelle.gdshader")
const LocalUi := preload("res://src/ui/local_music_ui.gd")
const G := preload("res://src/room/gestalt.gd")
const Backlog := preload("res://src/library/backlog.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const GameFilter := preload("res://src/library/game_filter.gd")
const Regal := preload("res://src/library/regal.gd")
const MM_S := preload("res://src/room/shaders/regal_huelle_mm.gdshader")
const REGAL_WELT := "res://src/room/regal_welt.gd"   ## Hülle wie im Regal des Hauptmenüs (zur Laufzeit geladen)

## Hüllen je System: [Dicke, Höhe, Tiefe] in Metern, Modul = schlichter Kunststoff ohne Band.
const HUELLEN := {
	"dvd": [0.0145, 0.19, 0.136], "jewel": [0.011, 0.125, 0.142], "klein": [0.011, 0.17, 0.106], "modul": [0.024, 0.112, 0.078],
}
const JEWEL := ["ps1", "dreamcast", "saturn", "pce"]
const KLEIN := ["switch", "3ds", "nds", "psp"]
const MODUL := ["gba", "gb", "gbc", "nes", "snes", "n64", "megadrive", "mastersystem", "gamegear", "atari2600", "arcade"]
const MAX_SCHILDER := 360          ## so viele Hüllen bekommen einen Titel auf dem Rücken
const MAX_COVER := 72              ## so viele Hüllen stehen höchstens mit dem Cover nach vorn
const AUGENHOEHE := 1.3
const STAPEL_MAX := 8              ## so viele Hüllen liegen höchstens aufeinander (von Hand)
const DECKEL := 0.028              ## Deckel des Spieleregals (moebel.gd _regal): oben drauf liegt darüber

const PLATIN := Color("#e9eef5")
const GOLD := Color("#d9b46a")
const SILBER := Color("#bfc3c8")
const BRONZE := Color("#b27a4e")


## Hülle je System wie im Regal des Hauptmenüs (src/library/regal.gd, FORMATE): PS2-DVD-Hülle,
## PS1-CD-Hülle, GameCube, Switch, PC/Steam als DVD-Hülle … Die Einstellung „Hüllen je System“
## (huellen) wählt eins der Formate dvd, jewel, psp (kleine Hülle) bzw. modul.
const UEBER := { "dvd": "dvd", "jewel": "jewel", "klein": "psp", "modul": "modul" }


static func format_von(g: Dictionary, huellen := {}) -> String:
	var sid := str(g.get("system", ""))
	if huellen.has(sid):
		return str(UEBER.get(str(huellen[sid]), "dvd"))
	return Regal.format_von(sid)


## Maße einer Hülle (Dicke, Höhe, Tiefe) in Metern, nach Format.
static func mass(fmt: String) -> Vector3:
	return (Regal.FORMATE.get(fmt, Regal.FORMATE.dvd) as Dictionary).m


static func mass_von(g: Dictionary, huellen := {}) -> Vector3:
	return mass(format_von(g, huellen))


## Ein System mit diesem Format (für Aufmachung und Rahmen, wenn die Einstellung das Format wählt).
static func system_fuer(fmt: String) -> String:
	if fmt == "dvd":
		return "pc"
	for k in Regal.SYSTEM_FORMAT:
		if str(Regal.SYSTEM_FORMAT[k]) == fmt:
			return str(k)
	return "pc"


## Hat ein Spiel im Zimmer genau die Hülle seines Systems (keine Einstellung dazwischen)?
static func wie_system(g: Dictionary, huellen := {}) -> bool:
	return not huellen.has(str(g.get("system", "")))


static func huellen_art(g: Dictionary, huellen := {}) -> String:
	var sid := str(g.get("system", ""))
	if huellen.has(sid):
		return str(huellen[sid])
	if sid in JEWEL:
		return "jewel"
	if sid in KLEIN:
		return "klein"
	if sid in MODUL:
		return "modul"
	return "dvd"


## Abnutzung 0..1 aus der Spielzeit: ab etwa 150 Stunden deutlich abgegriffen.
static func abnutzung(sekunden: int) -> float:
	var h := maxf(0.0, float(sekunden) / 3600.0)
	return clampf(log(1.0 + h) / log(151.0), 0.0, 1.0)


## Die Spiele fürs Regal: ausgewählt und sortiert nach den Einstellungen des Regals (ohne
## Einstellungen wie ein neues Regal: nur, was eingeräumt ist – zuerst nichts).
static func spiele(rg := {}) -> Array:
	if rg.is_empty():
		rg = G.std_regal("spieleregal")
	var fi := str(rg.get("fi", G.FILTER_STD))
	if fi == "eigene":
		return sortiert(eingeraeumt(rg.get("ma", [])), str(rg.get("so", "manuell")), rg.get("ma", []))
	var list: Array
	if fi.begins_with("liste:"):
		# Die Liste einmal nachschlagen, nicht je Spiel (passt_filter sucht sie jedes Mal neu durch).
		var drin := {}
		for id: Variant in Library.list_by_id(fi.substr(6)).get("games", []):
			drin[str(id)] = true
		list = Library.visible_games().filter(func(g: Dictionary) -> bool:
			return str(g.get("source", "")) != "disc" and drin.has(str(g.get("id", ""))))
	else:
		list = Library.visible_games().filter(func(g: Dictionary) -> bool:
			return str(g.get("source", "")) != "disc" and passt_filter(g, fi))
	return sortiert(list, str(rg.get("so", "zuletzt")), rg.get("ma", []))


## Eingeräumte Spiele (IDs in der gemerkten Reihenfolge) → Spiele der eigenen Bibliothek. Was es dort
## nicht (mehr) gibt oder versteckt ist, bleibt weg – fremde IDs zeigen nie etwas.
static func eingeraeumt(ids: Variant) -> Array:
	if not (ids is Array) or (ids as Array).is_empty():
		return []
	var nach_id := {}
	for g in Library.visible_games():
		if str(g.get("source", "")) != "disc":
			nach_id[str(g.get("id", ""))] = g
	var out: Array = []
	var schon := {}
	for id in (ids as Array).slice(0, G.MAX_REIHE):
		var k := str(id)
		if nach_id.has(k) and not schon.has(k):
			schon[k] = true
			out.append(nach_id[k])
	return out


## Passt ein Spiel zur Auswahl eines Regals (gestalt.gd, FILTER_ARTEN)? Nur Vergleiche mit Daten
## der Bibliothek.
static func passt_filter(g: Dictionary, fi: String) -> bool:
	var art := fi.get_slice(":", 0)
	var wert := fi.substr(art.length() + 1)
	match art:
		"installiert": return Library.is_installed(g)
		"favoriten": return bool(g.get("favorite", false))
		"ungespielt": return Library.playtime(g) <= 0 and Library.last_played(g) <= 0
		"system": return str(g.get("system", "")) == wert or str(g.get("source", "")) == wert
		"systeme":
			var ids := wert.split(",", false)
			return str(g.get("system", "")) in ids or str(g.get("source", "")) in ids
		"ordner": return Library.is_in_folder(g, wert)
		"liste": return str(g.get("id", "")) in Library.list_by_id(wert).get("games", [])
		"tag": return wert in GameFields.tags_of(g)
		"sammlung": return GameFields.category_of(g) == wert
		"status": return Backlog.status_of(g) == wert
		"genre": return wert in GameFilter.genres_of(g)
	return true


static func _titel(a: Dictionary, b: Dictionary) -> bool:
	return Library.display_title(a).naturalnocasecmp_to(Library.display_title(b)) < 0


## Sortieren mit vorab gerechneten Schlüsseln: je Spiel eine Zeile [Hauptschlüssel, −zuletzt gespielt, Titel,
## Spiel]. Früher fragte jeder Vergleich die Bibliothek neu (Spielzeit, zuletzt gespielt, Name des Systems,
## Backlog) – bei 2250 Spielen rund 25.000 Vergleiche, gemessen 80 bis 150 ms je Regal mit „alle Spiele“.
## Der Hauptschlüssel ist eine Zahl (kleiner zuerst) oder ein Text (natürlich, ohne Groß/Klein); bei
## Gleichstand zählt die zweite Zahl, dann der Titel.
static func _zeilen_vergleich(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return (a[0] as String).naturalnocasecmp_to(b[0]) < 0 if a[0] is String else a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return (a[2] as String).naturalnocasecmp_to(b[2]) < 0


static func sortiert(list: Array, so: String, reihe: Array = []) -> Array:
	if so == "neu":
		var neu := list.duplicate()
		neu.sort_custom(Library.newer)
		return neu
	var platz := {}
	var rang := {}
	if so == "manuell":
		# Eigene Reihenfolge: erst die gemerkte Reihe, Neues danach (zuletzt gespielt zuerst).
		for i in reihe.size():
			platz[str(reihe[i])] = i
	elif so == "backlog":
		for i in Backlog.STATUSES.size():
			rang[str(Backlog.STATUSES[i][0])] = i
	var zeilen: Array = []
	zeilen.resize(list.size())
	for i in list.size():
		var g: Dictionary = list[i]
		var haupt: Variant = 0
		var zuletzt := 0
		match so:
			"titel":
				pass
			"system":
				haupt = system_name(g)
			"spielzeit":
				haupt = -Library.playtime(g)
			"genre":
				var gs := GameFilter.genres_of(g)
				haupt = str(gs[0]) if not gs.is_empty() else "~"
			"backlog":
				haupt = int(rang.get(Backlog.status_of(g), 99))
				zuletzt = -Library.last_played(g)
			"manuell":
				haupt = int(platz.get(str(g.get("id", "")), 1 << 30))
				zuletzt = -Library.last_played(g)
			_:
				zuletzt = -Library.last_played(g)
		zeilen[i] = [haupt, zuletzt, Library.display_title(g), g]
	zeilen.sort_custom(_zeilen_vergleich)
	var out: Array = []
	out.resize(zeilen.size())
	for i in zeilen.size():
		out[i] = zeilen[i][3]
	return out


static func system_name(g: Dictionary) -> String:
	var sys := str(g.get("system", ""))
	var n := str(Config.system(sys).get("name", "")) if sys != "" else ""
	if n == "":
		n = Library.store_name(g, false, "PC")
	return n


## Fächer in der Reihenfolge, in der sie gefüllt werden: Augenhöhe zuerst.
static func _reihenfolge(faecher: Array, welt: Transform3D) -> Array:
	var idx: Array = range(faecher.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ya: float = (welt * (faecher[a].pos as Vector3)).y
		var yb: float = (welt * (faecher[b].pos as Vector3)).y
		return absf(ya + 0.12 - AUGENHOEHE) < absf(yb + 0.12 - AUGENHOEHE))
	return idx


## Ein Regal mit Spielen füllen; liefert die Plätze und wie viele Spiele es aufgenommen hat.
## pro_fach: höchstens so viele Spiele je Fach (die Bibliothek verteilt sich über alle Regale);
## was frei bleibt, bekommt etwas Deko (Pflanze, liegender Stapel, Controller).
## opt: Einstellungen des Regals (da Darstellung, ab Abnutzung, de Deko) und huellen je System.
static func regal_fuellen(regal: Node3D, list: Array, ab: int, pro_fach: int, schilder: Array, host: Node, opt := {}) -> Dictionary:
	if opt.get("pl") is Dictionary and not (opt.pl as Dictionary).is_empty() and str(opt.get("so", "")) == "manuell":
		return _hand_fuellen(regal, list, ab, schilder, host, opt)
	var faecher: Array = regal.get_meta("faecher", [])
	var plaetze: Array = []
	var n := ab
	var nach_art := {}           ## Hüllenart → [[Transform3D, Farbe, Abnutzung, Zufall], …]
	var reihe := _reihenfolge(faecher, regal.transform)
	var da := str(opt.get("da", "gemischt"))
	var deko := str(opt.get("de", "wenig"))
	var mit_abnutzung := bool(opt.get("ab", true))
	var huellen: Dictionary = opt.get("huellen", {})
	var cover := int(opt.get("cover_bisher", 0))
	for k in reihe.size():
		var fi: int = reihe[k]
		var f: Dictionary = faecher[fi]
		var x: float = -float(f.breite) * 0.5 + 0.004
		var ende: float = float(f.breite) * 0.5 - 0.004
		var pos: Vector3 = f.pos
		var hier := 0
		if deko == "viel" and float(f.breite) > 0.5:
			ende -= 0.21
		# Cover nach vorn: jede Hülle steht mit dem Bild zum Raum, leicht angelehnt.
		if da == "cover":
			while n < list.size() and hier < pro_fach and x + 0.148 <= ende and cover < MAX_COVER:
				var gc: Dictionary = list[n]
				var bc := mass_von(gc, huellen).z
				var vc := _cover_huelle(regal, gc, Vector3(pos.x + x + bc * 0.5 + 0.004, pos.y, pos.z), host, huellen)
				vc.rotation_degrees = Vector3(-9, [2.0, -3.0, 4.0, -1.5][(n + k) % 4], 0)
				plaetze.append({ "art": "spiel", "daten": gc, "fach": fi, "x": pos.x + x + bc * 0.5, "y": pos.y, "knoten": vc, "basis": vc.transform, "nr": n, "lage": "vorn" })
				x += bc + 0.012
				n += 1
				hier += 1
				cover += 1
			if deko != "keine" and ende - x > 0.12:
				_deko(regal, f, x + 0.012, ende + (0.21 if deko == "viel" else 0.0), fi + k)
			continue
		# Im ersten Fach steht ganz rechts ein Spiel mit dem Cover nach vorn.
		if da == "gemischt" and k == 0 and n < list.size():
			var g0: Dictionary = list[n]
			var vorn := _cover_huelle(regal, g0, Vector3(pos.x + ende - 0.07, pos.y, pos.z), host, huellen)
			plaetze.append({ "art": "spiel", "daten": g0, "fach": fi, "x": pos.x + ende - 0.07, "y": pos.y, "knoten": vorn, "basis": vorn.transform, "nr": n, "lage": "vorn" })
			ende -= 0.15
			n += 1
			hier += 1
		# Zweites Fach: links ebenfalls eines mit dem Cover nach vorn (lebendiger als nur Rücken).
		if da == "gemischt" and k == 1 and n < list.size():
			var g1: Dictionary = list[n]
			var vorn1 := _cover_huelle(regal, g1, Vector3(pos.x + x + 0.07, pos.y, pos.z), host, huellen)
			vorn1.rotation_degrees = Vector3(-8, 6, 0)
			plaetze.append({ "art": "spiel", "daten": g1, "fach": fi, "x": pos.x + x + 0.07, "y": pos.y, "knoten": vorn1, "basis": vorn1.transform, "nr": n, "lage": "vorn" })
			x += 0.15
			n += 1
			hier += 1
		while n < list.size() and hier < pro_fach:
			var g: Dictionary = list[n]
			var art := _gruppe(g, huellen)
			var m := mass_von(g, huellen)
			var dicke: float = m[0]
			if x + dicke > ende:
				break
			var hoehe: float = minf(float(m[1]), float(f.hoehe) - 0.012)
			var t := Transform3D(Basis(), Vector3(pos.x + x + dicke * 0.5, pos.y + hoehe * 0.5, pos.z + float(f.tiefe) * 0.5 - float(m[2]) * 0.5 - 0.01))
			if not nach_art.has(art):
				nach_art[art] = []
			var platz := { "art": "spiel", "daten": g, "fach": fi, "x": pos.x + x + dicke * 0.5, "y": pos.y, "hoehe": hoehe, "tiefe": float(m[2]), "nr": n }
			nach_art[art].append(
					[t, Color.WHITE, abnutzung(Library.playtime(g)) if mit_abnutzung else 0.0, float(absi(str(g.get("id", "")).hash()) % 997) / 997.0, platz])
			plaetze.append(platz)
			x += dicke + 0.0015
			n += 1
			hier += 1
		if deko != "keine" and ende + (0.21 if deko == "viel" and float(f.breite) > 0.5 else 0.0) - x > 0.12:
			_deko(regal, f, x + 0.012, ende + (0.21 if deko == "viel" and float(f.breite) > 0.5 else 0.0), fi + k)
	_huellen_bauen(regal, nach_art, schilder, huellen)
	return { "plaetze": plaetze, "bis": n, "cover": cover }


## Gruppe einer Hülle im MultiMesh: Format und Region (PS2 PAL mit dem weißen Streifen, NTSC ohne).
static func _gruppe(g: Dictionary, huellen := {}) -> String:
	var fmt := format_von(g, huellen)
	return "%s|%s" % [fmt, Regal.region_von(g) if Regal.RUECKEN.has(fmt) and wie_system(g, huellen) else "pal"]


## System, nach dem eine Hülle aussieht (eigenes bzw. eins mit dem eingestellten Format).
static func aussehen_system(g: Dictionary, huellen := {}) -> String:
	return str(g.get("system", "")) if wie_system(g, huellen) else system_fuer(format_von(g, huellen))


## Farbe des Titelfelds wie im Regal des Hauptmenüs, solange es das Cover nicht kennt (fest nach
## Format, PS2 weiß, PS1 schwarz; sonst aus der Farbe des Systems, je Spiel etwas anders).
static func ruecken_farbe(g: Dictionary, huellen := {}) -> Color:
	var sid := aussehen_system(g, huellen)
	var sys := Config.system(str(g.get("system", "")))
	var aus := Regal.ruecken_farbe(null, Color(str(sys.get("color", "#3a3a42"))), str(g.get("id", "")))
	return Regal.ruecken_aufbau(sid, "pal", aus).grund


## Gemerktes am Baum (nicht in static var: Materialien und Bilder überleben sonst das Beenden
## des RenderingServers).
static func merker(name: String) -> Dictionary:
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	if not root.has_meta(name):
		root.set_meta(name, {})
	return root.get_meta(name)


## Material je Gruppe (Werte des Formats und der Felder), einmal gebaut.
static func _mm_material(gruppe: String) -> ShaderMaterial:
	var mats := merker("uz_huellen_mats")
	if mats.has(gruppe):
		return mats[gruppe]
	var fmt := gruppe.get_slice("|", 0)
	var region := gruppe.get_slice("|", 1)
	var sid := system_fuer(fmt)
	var rw: Variant = load(REGAL_WELT)
	var mat := ShaderMaterial.new()
	mat.shader = MM_S
	rw.Huelle.format_setzen(mat, sid)
	var a := Regal.ruecken_aufbau(sid, region)
	# Kartons: das Kopfband hat die Farbe des Rückens (je Hülle) – also ohne eigenes Feld.
	if str(Regal.format_daten(sid).art) == "karton":
		a = { "felder": [], "kopf": a.kopf }
	rw.Huelle.felder_setzen(mat, a)
	mats[gruppe] = mat
	return mat


## Je Format ein MultiMesh (stehend oder liegend) mit dem Material der Hülle aus dem Hauptmenü, dazu
## die Titel auf den Rücken (Schrift, Größe und Lage wie dort, längs von oben nach unten).
static func _huellen_bauen(regal: Node3D, nach_art: Dictionary, schilder: Array, huellen := {}) -> void:
	var font: Font = UzTheme.display("bold")
	var rw: Variant = load(REGAL_WELT)
	for art in nach_art.keys():
		var fmt := str(art).get_slice("|", 0)
		var region := str(art).get_slice("|", 1)
		var m := mass(fmt)
		var eintraege: Array = nach_art[art]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var hoehe_mesh: float = m.y
		mm.mesh = F.kiste(m, Regal.kanten_rad(system_fuer(fmt)), false, 2)
		mm.instance_count = eintraege.size()
		for i in eintraege.size():
			var e: Array = eintraege[i]
			var t: Transform3D = e[0]
			var platz: Dictionary = e[4]
			var g: Dictionary = platz.daten
			var sid := aussehen_system(g, huellen)
			var grund := ruecken_farbe(g, huellen)
			# Niedrige Fächer: Hülle passend gestaucht (selten, nur bei sehr hohen Hüllen).
			var sy := float(platz.hoehe) / hoehe_mesh
			t = t.scaled_local(Vector3(1, sy, 1))
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, grund.srgb_to_linear())
			mm.set_instance_custom_data(i, Color(float(e[2]), 0.0, float(e[3]), 0.0))
			platz["mm"] = mm
			platz["index"] = i
			platz["basis"] = t
			platz["format"] = fmt
			if schilder.size() < MAX_SCHILDER:
				var nummer := Regal.seriennummer(g, Library.serial_of(g)) if Regal.RUECKEN.has(fmt) and wie_system(g, huellen) else ""
				var a := Regal.ruecken_aufbau(sid, region, grund, nummer != "")
				var tl: Dictionary = rw.Huelle.titel_lage(g, m, a, font)
				var l := Label3D.new()
				l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				l.font = font
				l.font_size = int(tl.gr)
				l.pixel_size = float(tl.px)
				l.text = str(tl.text)
				l.modulate = a.titel_farbe
				l.outline_size = 0
				l.shaded = true
				l.double_sided = false
				l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
				l.render_priority = 1
				# Ursprung des MultiMesh: Mitte der Hülle; der Titel sitzt wie im Hauptmenü (von unten gemessen).
				var unten := t.origin - t.basis * Vector3(0, m.y * 0.5, 0)
				l.transform = Transform3D(t.basis.orthonormalized() * Basis(Vector3.FORWARD, PI * 0.5), unten + t.basis * (tl.pos as Vector3))
				regal.add_child(l)
				platz["schild"] = l
				platz["schild_basis"] = l.transform
				schilder.append(l)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mm_material(str(art))
		regal.add_child(mmi)


# --- Von Hand umgestellt ----------------------------------------------------------------------------

## Oben auf dem Regal als Fach (Index -1): so breit wie die oberen Fächer zusammen, auf dem Deckel.
static func oben_fach(faecher: Array) -> Dictionary:
	if faecher.is_empty():
		return { "pos": Vector3(0, 1.0, 0), "breite": 0.4, "tiefe": 0.3, "hoehe": 0.3, "oben": true }
	var oben := -INF
	var z := 0.0
	var tiefe := 0.3
	for f in faecher:
		var top := float(f.pos.y) + float(f.hoehe)
		if top > oben + 0.001:
			oben = top
			z = float(f.pos.z)
			tiefe = float(f.tiefe)
	var l := INF
	var r := -INF
	for f in faecher:
		if absf(float(f.pos.y) + float(f.hoehe) - oben) < 0.01:
			l = minf(l, float(f.pos.x) - float(f.breite) * 0.5)
			r = maxf(r, float(f.pos.x) + float(f.breite) * 0.5)
	return { "pos": Vector3((l + r) * 0.5, oben + DECKEL, z), "breite": r - l, "tiefe": tiefe, "hoehe": 0.3, "oben": true }


## Ein Schritt nach rechts im Fach: wo die Hülle hinkommt ([Mitte ab links, Lage im Stapel]); st
## (x: belegt, art, n, h, sx: Stapel) wächst mit. Liegende derselben Art stapeln sich, bis das Fach
## voll ist (höchstens STAPEL_MAX).
static func lage_schritt(st: Dictionary, art: String, lage: String, hoehe: float) -> Array:
	var m := mass(art.get_slice("|", 0))
	var dicke := float(m[0])
	match lage:
		"liegend":
			if int(st.get("n", 0)) > 0 and str(st.get("art", "")) == art and int(st.n) < STAPEL_MAX and float(st.h) + dicke <= hoehe - 0.01:
				st.n = int(st.n) + 1
				st.h = float(st.h) + dicke
				return [float(st.sx), int(st.n) - 1]
			st.sx = float(st.get("x", 0.0)) + float(m[1]) * 0.5
			st.x = float(st.get("x", 0.0)) + float(m[1]) + 0.006
			st.n = 1
			st.h = dicke
			st.art = art
			return [float(st.sx), 0]
		"vorn":
			var c := float(st.get("x", 0.0)) + float(m[2]) * 0.5 + 0.004
			st.x = float(st.get("x", 0.0)) + float(m[2]) + 0.012
			st.n = 0
			return [c, 0]
	var c2 := float(st.get("x", 0.0)) + dicke * 0.5
	st.x = float(st.get("x", 0.0)) + dicke + 0.0015
	st.n = 0
	return [c2, 0]


## Breite einer Reihe [[Spiel, Lage] …] in einem Fach der Höhe hoehe.
static func reihe_breite(eintraege: Array, huellen: Dictionary, hoehe: float) -> float:
	var st := {}
	for e in eintraege:
		lage_schritt(st, format_von(e[0], huellen), str(e[1]), hoehe)
	return float(st.get("x", 0.0))


## Füllt ein Regal nach deiner Hand: jedes Spiel mit Fach (pl; -1 oben drauf) dort, in seiner Lage
## (lg), in der Reihenfolge der Liste. Neues und was nicht mehr passt, kommt stehend in die Lücken
## (Augenhöhe zuerst). Nur gebaut, wenn sich etwas ändert – wie das Füllen sonst.
static func _hand_fuellen(regal: Node3D, list: Array, ab: int, schilder: Array, host: Node, opt: Dictionary) -> Dictionary:
	var faecher: Array = regal.get_meta("faecher", [])
	var pl: Dictionary = opt.pl
	var lg: Dictionary = opt.get("lg", {}) if opt.get("lg") is Dictionary else {}
	var huellen: Dictionary = opt.get("huellen", {})
	var mit_abnutzung := bool(opt.get("ab", true))
	var deko := str(opt.get("de", "wenig"))
	var cover := int(opt.get("cover_bisher", 0))
	var oben := oben_fach(faecher)
	var inhalt := {}             ## Fach → [[Spiel, Lage, Nr] …]
	var stand := {}              ## Fach → Stand von lage_schritt (belegte Breite)
	var rest: Array = []
	for n in range(ab, list.size()):
		var g: Dictionary = list[n]
		var gid := str(g.get("id", ""))
		var fi := int(pl.get(gid, -9))
		if fi >= -1 and fi < faecher.size():
			var lage := str(lg.get(gid, "stehend"))
			var f: Dictionary = oben if fi == -1 else faecher[fi]
			var st: Dictionary = (stand.get(fi, {}) as Dictionary).duplicate()
			lage_schritt(st, format_von(g, huellen), lage, float(f.hoehe))
			if float(st.x) <= float(f.breite) - 0.008:
				stand[fi] = st
				if not inhalt.has(fi):
					inhalt[fi] = []
				inhalt[fi].append([g, lage, n])
				continue
		rest.append([g, "stehend", n])
	var reihe := _reihenfolge(faecher, regal.transform)
	var daneben := 0
	for e in rest:
		var drin := false
		for fi in reihe:
			var f: Dictionary = faecher[fi]
			var st: Dictionary = (stand.get(fi, {}) as Dictionary).duplicate()
			lage_schritt(st, format_von(e[0], huellen), "stehend", float(f.hoehe))
			if float(st.x) <= float(f.breite) - 0.008:
				stand[fi] = st
				if not inhalt.has(fi):
					inhalt[fi] = []
				inhalt[fi].append(e)
				drin = true
				break
		daneben = 0 if drin else daneben + 1
		if daneben >= 8:
			break
	var plaetze: Array = []
	var nach_art := {}
	var alle: Array = range(faecher.size())
	alle.append(-1)
	for fi in alle:
		var f: Dictionary = oben if fi == -1 else faecher[fi]
		var pos: Vector3 = f.pos
		var links := -float(f.breite) * 0.5 + 0.004
		var st := {}
		for e in inhalt.get(fi, []):
			var g: Dictionary = e[0]
			var lage := str(e[1])
			var n := int(e[2])
			var art := _gruppe(g, huellen)
			var m := mass_von(g, huellen)
			var lg2 := lage_schritt(st, format_von(g, huellen), lage, float(f.hoehe))
			var xc := pos.x + links + float(lg2[0])
			if lage == "vorn":
				var vc := _cover_huelle(regal, g, Vector3(xc, pos.y, pos.z), host, huellen)
				vc.rotation_degrees = Vector3(-9, [2.0, -3.0, 4.0, -1.5][n % 4], 0)
				plaetze.append({ "art": "spiel", "daten": g, "fach": fi, "x": xc, "y": pos.y, "knoten": vc, "basis": vc.transform, "nr": n, "lage": "vorn" })
				cover += 1
				continue
			var z := pos.z + float(f.tiefe) * 0.5 - float(m[2]) * 0.5 - 0.01
			var t: Transform3D
			var platz := { "art": "spiel", "daten": g, "fach": fi, "y": pos.y, "tiefe": float(m[2]), "nr": n, "lage": lage }
			if lage == "liegend":
				# Flach, Rücken nach vorn, leicht verdreht wie von Hand hingelegt.
				var k := int(lg2[1])
				var dreh := (float(absi(str(g.get("id", "")).hash()) % 7) - 3.0) * 0.012
				t = Transform3D(Basis(Vector3.UP, dreh) * Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(xc, pos.y + float(m[0]) * (0.5 + k), z))
				platz["hoehe"] = float(m[1])
				platz["dreh"] = dreh
				platz["x"] = xc + k * 0.0001
			else:
				var hoehe: float = minf(float(m[1]), float(f.hoehe) - 0.012)
				t = Transform3D(Basis(), Vector3(xc, pos.y + hoehe * 0.5, z))
				platz["hoehe"] = hoehe
				platz["x"] = xc
			if not nach_art.has(art):
				nach_art[art] = []
			var zufall := float(absi(str(g.get("id", "")).hash()) % 997) / 997.0
			nach_art[art].append([t, S.huellen_farbe(g), abnutzung(Library.playtime(g)) if mit_abnutzung else 0.0, zufall, platz])
			plaetze.append(platz)
		if fi >= 0 and deko != "keine" and float(f.breite) - 0.008 - float(st.get("x", 0.0)) > 0.14:
			_deko(regal, f, links + float(st.get("x", 0.0)) + 0.012, float(f.breite) * 0.5 - 0.004, fi)
	_huellen_bauen(regal, nach_art, schilder, huellen)
	return { "plaetze": plaetze, "bis": list.size(), "cover": cover }


## Etwas Leben im freien Rest eines Fachs: kleine Pflanze, liegender Stapel Hüllen oder ein
## Controller (eigene Form, kein Nachbau).
static func _deko(regal: Node3D, f: Dictionary, von: float, bis: float, art: int) -> void:
	var pos: Vector3 = f.pos
	var platz := bis - von
	var n := Node3D.new()
	regal.add_child(n)
	von += pos.x
	match art % 3:
		0:
			var x := von + minf(platz, 0.2) * 0.5
			n.position = Vector3(x, pos.y, pos.z)
			var u := PackedVector2Array([Vector2(0, 0), Vector2(0.045, 0), Vector2(0.055, 0.075), Vector2(0.058, 0.08), Vector2(0, 0.08)])
			_mesh(n, F.dreh(u, 24, [1, 2, 3], true), S.lack(Color("#c97b54"), 0.6, 0.3), Vector3.ZERO)
			var gruen := S.lack(Color("#56804c"), 0.5, 0.35)
			for i in 7:
				var a := float(i) / 7.0 * TAU
				var b := MeshInstance3D.new()
				b.mesh = F.walze(0.012, 0.09 + (i % 3) * 0.025, 0.011, 10)
				b.material_override = gruen
				b.position = Vector3(cos(a) * 0.018, 0.075, sin(a) * 0.018)
				b.rotation = Vector3(sin(a) * 0.45, 0, -cos(a) * 0.45)
				n.add_child(b)
		1:
			var x2 := von + minf(platz, 0.2) * 0.5
			n.position = Vector3(x2, pos.y, pos.z)
			var farben := [Color("#22379a"), Color("#1b2838"), Color("#c8323d"), Color("#4c3a8c")]
			for i in 3:
				var c := MeshInstance3D.new()
				c.mesh = F.kiste(Vector3(0.136, 0.0145, 0.19), 0.0022, false, 2)
				c.material_override = S.lack(farben[(i + art) % farben.size()], 0.35, 0.5)
				c.position = Vector3(0, 0.0075 + i * 0.0148, 0)
				c.rotation_degrees = Vector3(0, [4.0, -6.0, 9.0][i] + 90.0, 0)
				n.add_child(c)
		_:
			var x3 := von + minf(platz, 0.24) * 0.5
			n.position = Vector3(x3, pos.y, pos.z + 0.02)
			n.rotation_degrees = Vector3(0, -14, 0)
			var koerper := S.lack(Color("#2c2d31"), 0.42, 0.5)
			_mesh(n, F.kiste(Vector3(0.11, 0.03, 0.06), 0.014, true), koerper, Vector3(0, 0.017, 0))
			for s2: int in [-1, 1]:
				_mesh(n, F.kiste(Vector3(0.045, 0.032, 0.075), 0.016, true), koerper, Vector3(s2 * 0.055, 0.017, 0.012))
				_mesh(n, F.walze(0.009, 0.012, 0.004, 14), S.lack(Color("#17181a"), 0.6, 0.3), Vector3(s2 * 0.028, 0.03, -0.005))
			_mesh(n, F.walze(0.0045, 0.002, 0.001, 12), S.leuchte(Color("#e7c27d"), 2.0), Vector3(0, 0.0325, 0.012))


static func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Eine Hülle mit dem Cover nach vorn, leicht an die Rückwand gelehnt: dieselbe Hülle wie im Regal
## des Hauptmenüs (regal_welt.gd Huelle: Format, Rahmen des Systems mit Band und Logo, Rücken), nur
## gedreht. Das Cover kommt von der Platte (sonst Uzais Ersatz-Cover), kein Netz.
static func _cover_huelle(regal: Node3D, g: Dictionary, pos: Vector3, host: Node, huellen := {}) -> Node3D:
	var n := Node3D.new()
	n.position = pos + Vector3(0, 0, -0.04)
	n.rotation_degrees = Vector3(-9, 0, 0)
	regal.add_child(n)
	var h := huelle_neu(g, huellen)
	h.rotation = Vector3(0, -PI * 0.5, 0)     # Seite +x (Cover) zum Raum
	n.add_child(h)
	huellen_cover(host, g, h)
	n.set_meta("hoehe", float(h.get("masse").y))
	n.set_meta("huelle", h)
	return n


## Eine Hülle aus dem Regal des Hauptmenüs (regal_welt.gd Huelle), Ursprung unten in der Mitte,
## Rücken nach +z, Cover auf +x. Mit eingestelltem Format: wie ein System dieses Formats.
static func huelle_neu(g: Dictionary, huellen := {}) -> Node3D:
	var rw: Variant = load(REGAL_WELT)
	var h: Node3D = rw.Huelle.new()
	h.call("bauen", rw.HUELLE_S)
	var gg := g
	if not wie_system(g, huellen):
		gg = g.duplicate()
		gg["system"] = aussehen_system(g, huellen)
	h.call("setzen", gg, 0.0, ruecken_farbe(g, huellen), UzTheme.display("bold"), Callable(rw, "logo_statisch"))
	h.position = Vector3.ZERO
	return h


## Vorderseite einer Hülle (huelle_neu) wie im Regal des Hauptmenüs: dieselben Bildarten in derselben
## Reihenfolge (regal_welt.gd cover_arten – echter Scan zuerst, dann ein Motiv unter Uzais Band),
## aber nur, was schon auf der Platte liegt; sonst zeigt die Hülle Uzais Ersatz-Vorderseite. Dazu der
## echte Rücken, wenn er schon daliegt. Kein Netz.
static func huellen_cover(_host: Node, g: Dictionary, h: Node3D) -> void:
	var rw: Variant = load(REGAL_WELT)
	var rp := Media.local_path(g, "ruecken")
	if rp != "":
		Media.file_texture(rp, Media.max_width("ruecken"), func(t: Variant) -> void:
			if t is Texture2D and is_instance_valid(h):
				h.call("ruecken_setzen", t))
	for k in rw.cover_arten(g):
		var p := Media.local_path(g, str(k))
		if p != "":
			Media.file_texture(p, Media.max_width(str(k)), func(t: Variant) -> void:
				if t is Texture2D and is_instance_valid(h):
					h.call("cover_setzen", t))
			return


## Cover für das Zimmer: das Bild, das schon auf der Platte liegt; sonst Uzais Ersatz-Cover
## (einmal in ein Bild gezeichnet). Kein Netz.
static func cover_textur(host: Node, g: Dictionary, groesse: Vector2i, cb: Callable) -> void:
	var p := Media.local_path(g, "cover")
	if p != "":
		Media.file_texture(p, 360, func(t: Variant) -> void:
			if t is Texture2D:
				cb.call(t)
			elif is_instance_valid(host):
				_ersatz_cover(host, g, groesse, cb))
		return
	_ersatz_cover(host, g, groesse, cb)


static func _ersatz_cover(host: Node, g: Dictionary, groesse: Vector2i, cb: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = groesse
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var art = CoverArt.new()
	art.size = Vector2(groesse)
	art.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vp.add_child(art)
	art.setup(g)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or not is_instance_valid(host):
		return
	img.generate_mipmaps()
	cb.call(ImageTexture.create_from_image(img))


# --- Pokale ----------------------------------------------------------------------------------------

## Pokale aus den Erfolgen: Platin für alle Erfolge, sonst Gold (ab 75 %), Silber (ab 40 %) und
## Bronze. Platin zuerst, dann nach Anteil. Nur, was Uzai schon weiß (ohne Abfrage).
static func pokale(rg := {}) -> Array:
	var out: Array = []
	var fi := str(rg.get("fi", "alle"))
	for g in Library.visible_games():
		var k: Array = Achievements.known(g)
		if k.size() < 2 or int(k[1]) <= 0 or int(k[0]) <= 0:
			continue
		var anteil := float(k[0]) / float(k[1])
		var stufe := "platin" if int(k[0]) >= int(k[1]) else ("gold" if anteil >= 0.75 else ("silber" if anteil >= 0.4 else "bronze"))
		if (fi == "platin" and stufe != "platin") or (fi == "ab_gold" and not (stufe in ["platin", "gold"])):
			continue
		out.append({ "spiel": g, "stufe": stufe, "frei": int(k[0]), "gesamt": int(k[1]), "anteil": anteil })
	var rang := { "platin": 0, "gold": 1, "silber": 2, "bronze": 3 }
	match str(rg.get("so", "stufe")):
		"anteil":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.anteil) > float(b.anteil))
			return out
		"titel":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _titel(a.spiel, b.spiel))
			return out
		"spielzeit":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Library.playtime(a.spiel) > Library.playtime(b.spiel))
			return out
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.stufe != b.stufe:
			return int(rang[a.stufe]) < int(rang[b.stufe])
		if not is_equal_approx(float(a.anteil), float(b.anteil)):
			return float(a.anteil) > float(b.anteil)
		return Library.playtime(a.spiel) > Library.playtime(b.spiel))
	return out


static func schrank_fuellen(schrank: Node3D, list: Array, ab: int) -> Dictionary:
	var faecher: Array = schrank.get_meta("faecher", [])
	var plaetze: Array = []
	var n := ab
	var reihe := _reihenfolge(faecher, schrank.transform)
	for fi in reihe:
		var f: Dictionary = faecher[fi]
		var pos: Vector3 = f.pos
		for i in 3:
			if n >= list.size():
				break
			var e: Dictionary = list[n]
			var x := pos.x + (float(i) - 1.0) * float(f.breite) / 3.0
			var p := pokal(str(e.stufe), Library.display_title(e.spiel))
			p.position = Vector3(x, pos.y, pos.z)
			p.rotation_degrees = Vector3(0, [-8.0, 4.0, 10.0][i], 0)
			schrank.add_child(p)
			plaetze.append({ "art": "pokal", "daten": e, "fach": fi, "x": x, "y": pos.y, "knoten": p, "basis": p.transform, "nr": n })
			n += 1
	if plaetze.is_empty() and ab == 0:
		var l := Label3D.new()
		l.text = "Pokale kommen mit deinen Erfolgen"
		l.outline_size = 0
		l.font = UzTheme.font("ui")
		l.font_size = 30
		l.pixel_size = 0.0006
		l.modulate = Color("#e9e2d4")
		l.shaded = true
		var f0: Dictionary = faecher[reihe[0]] if not faecher.is_empty() else { "pos": Vector3(0, 1.2, 0) }
		l.position = (f0.pos as Vector3) + Vector3(0, 0.16, 0.08)
		schrank.add_child(l)
	return { "plaetze": plaetze, "bis": n }


## Ein Pokal: Sockel aus dunklem Stein, Pokal auf Fuß und Stiel mit zwei Henkeln, vorn ein
## Schild mit dem Spielnamen. Platin ist am größten.
static func pokal(stufe: String, titel: String) -> Node3D:
	var root := Node3D.new()
	var farbe: Color = { "platin": PLATIN, "gold": GOLD, "silber": SILBER, "bronze": BRONZE }.get(stufe, GOLD)
	var k := 1.0 if stufe == "platin" else 0.82
	var metall := S.pokal_metall(farbe, 0.16 if stufe == "platin" else 0.26)
	var sockel := MeshInstance3D.new()
	sockel.mesh = F.kiste(Vector3(0.13, 0.05, 0.1) * Vector3(k, 1, k), 0.008, true)
	sockel.material_override = S.lack(Color("#1d1c1e"), 0.22, 0.6)
	sockel.position = Vector3(0, 0.025, 0)
	root.add_child(sockel)
	var u := PackedVector2Array([
		Vector2(0, 0), Vector2(0.032, 0), Vector2(0.03, 0.008), Vector2(0.012, 0.02), Vector2(0.008, 0.06),
		Vector2(0.012, 0.075), Vector2(0.03, 0.09), Vector2(0.045, 0.12), Vector2(0.05, 0.155), Vector2(0.047, 0.158),
		Vector2(0.042, 0.125), Vector2(0.0, 0.112)])
	for i in u.size():
		u[i] = u[i] * k
	var kelch := MeshInstance3D.new()
	kelch.mesh = F.dreh(u, 40, [1, 2, 8, 9])
	kelch.material_override = metall
	kelch.position = Vector3(0, 0.05, 0)
	root.add_child(kelch)
	for s: int in [-1, 1]:
		var henkel := MeshInstance3D.new()
		henkel.mesh = F.ring(0.022 * k, 0.0035 * k, PI * 1.15)
		henkel.material_override = metall
		henkel.position = Vector3(s * 0.045 * k, 0.05 + 0.125 * k, 0)
		henkel.rotation = Vector3(0, 0, -PI * 0.57 if s > 0 else PI * 0.43)
		root.add_child(henkel)
	if stufe == "platin":
		# Platin: ein geschliffener Stein auf dem Rand und ein heller Ring um den Fuß.
		var stein := MeshInstance3D.new()
		var su := PackedVector2Array([Vector2(0, 0), Vector2(0.014, 0.012), Vector2(0.0, 0.03)])
		stein.mesh = F.dreh(su, 6, [0, 1, 2])
		stein.material_override = S.pokal_metall(Color("#f4f8ff"), 0.05)
		stein.position = Vector3(0, 0.05 + 0.158, 0)
		root.add_child(stein)
		var reif := MeshInstance3D.new()
		reif.mesh = F.walze(0.036, 0.006, 0.002, 32)
		reif.material_override = S.pokal_metall(Color("#f2f5f9"), 0.1)
		reif.position = Vector3(0, 0.05, 0)
		root.add_child(reif)
	var schild := MeshInstance3D.new()
	schild.mesh = F.kiste(Vector3(0.104 * k, 0.032, 0.003), 0.002, false)
	schild.material_override = S.metall(GOLD.lerp(farbe, 0.4), 0.3)
	schild.position = Vector3(0, 0.025, 0.05 * k + 0.0015)
	root.add_child(schild)
	var l := Label3D.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = titel if titel.length() <= 22 else titel.substr(0, 21).strip_edges() + "…"
	l.font = UzTheme.font("ui_bold")
	l.font_size = 24
	l.outline_size = 0
	l.pixel_size = 0.00019
	l.width = 0.098 * k / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color("#2a2418")
	l.shaded = true
	l.render_priority = 2
	l.position = Vector3(0, 0.025, 0.05 * k + 0.0033)
	root.add_child(l)
	return root


# --- Platten -----------------------------------------------------------------------------------------

## Platten aus der gewählten Musikquelle: eigene Alben (Musikdateien), Playlists und Mixe
## (Spotify), sonst eine Platte für „Musik über Windows“ (anhalten und weiter).
static func platten(rg := {}) -> Array:
	var out := _platten_quelle()
	if str(rg.get("so", "")) == "name":
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


static func _platten_quelle() -> Array:
	var out: Array = []
	if Music.lokal_da() and Music.local != null:
		for a in (Music.local.albums as Array).slice(0, 36):
			out.append({ "name": str(a.get("name", "")), "sub": str(a.get("artist", "")), "art": str(a.get("art", "")),
				"farbe": _farbe_fuer(str(a.get("name", ""))), "spielen": func() -> void: LocalUi.play(a) })
		if Music.mode() == "lokal" or out.size() >= 36:
			return out
	if Music.mode() == "spotify" or Music.demo():
		# Neben der eigenen Musik (beide Quellen) füllen die Playlists das Regal auf.
		for p in (Music.playlists + Music.spotify_mixes).slice(0, 36 - out.size()):
			if not (p is Dictionary):
				continue
			var uri := str(p.get("uri", ""))
			var tracks: Variant = p.get("tracks")
			var spielen := Callable()
			if uri != "":
				spielen = func() -> void: Music.play_context(uri)
			elif tracks is Array and not (tracks as Array).is_empty():
				spielen = func() -> void: Music.play_list(tracks, 0)
			else:
				continue
			out.append({ "name": str(p.get("name", "")), "sub": str(p.get("owner", p.get("sub", ""))), "art": "",
				"farbe": _farbe_fuer(str(p.get("id", p.get("name", "")))), "spielen": spielen })
		# Grundmodus (ohne Bibliothek von Spotify): Playlists und Alben aus dem eigenen Verlauf.
		if out.is_empty():
			for c in SpotifyVerlauf.contexts(Music.verlauf_list(), 36):
				var curi := str(c.uri)
				var art_s: String = { "album": "Album", "playlist": "Playlist", "artist": "Künstler", "show": "Podcast" }.get(str(c.kind), "")
				out.append({ "name": str(c.name) if str(c.name) != "" else str(c.last), "sub": str(TranslationServer.translate(art_s)) if art_s != "" else "",
					"art": "", "farbe": _farbe_fuer(curi), "spielen": func() -> void: Music.play_context(curi) })
		if not out.is_empty():
			return out
	# Übersetzt schon hier: Der Name steht auf der Hülle, und die ist von der Übersetzung ausgenommen (sonst Albumtitel).
	out.append({ "name": str(TranslationServer.translate("Musik über Windows")), "sub": str(TranslationServer.translate("Anhalten und weiter")),
		"art": "", "farbe": Color("#34425e"), "spielen": func() -> void: Music.play_pause() })
	return out


static func _farbe_fuer(s: String) -> Color:
	var h := float(absi(s.hash()) % 1000) / 1000.0
	return Color.from_hsv(h, 0.42, 0.62)


static func plattenregal_fuellen(regal: Node3D, list: Array, ab: int, rg := {}) -> Dictionary:
	var faecher: Array = regal.get_meta("faecher", [])
	var plaetze: Array = []
	var n := ab
	var ruecken := str(rg.get("da", "kiste")) == "ruecken"
	for fi in _reihenfolge(faecher, regal.transform):
		var f: Dictionary = faecher[fi]
		var pos: Vector3 = f.pos
		if ruecken:
			# Nebeneinander wie Bücher: Rücken nach vorn, leicht gegeneinander gelehnt.
			var anz := mini(int((float(f.breite) - 0.02) / 0.013), list.size() - n)
			for i in anz:
				var e2: Dictionary = list[n]
				var p2 := huelle_platte(e2, true)
				p2.position = Vector3(pos.x - float(f.breite) * 0.5 + 0.012 + i * 0.013, pos.y, pos.z + 0.01)
				p2.rotation_degrees = Vector3(0, -90, -1.5 if i % 5 == 4 else 0.0)
				regal.add_child(p2)
				plaetze.append({ "art": "platte", "daten": e2, "fach": fi, "x": p2.position.x, "y": pos.y, "knoten": p2, "basis": p2.transform, "nr": n, "ruecken": true })
				n += 1
			if n >= list.size():
				break
			continue
		var anzahl := mini(9, list.size() - n)
		for i in anzahl:
			var e: Dictionary = list[n]
			var p := huelle_platte(e)
			# Stehen hintereinander (wie in einer Kiste), leicht nach hinten gelehnt.
			var z := pos.z + float(f.tiefe) * 0.5 - 0.035 - i * 0.03
			p.position = Vector3(pos.x, pos.y, z)
			p.rotation_degrees = Vector3(-6.0 - i * 0.6, 0, 0)
			regal.add_child(p)
			plaetze.append({ "art": "platte", "daten": e, "fach": fi, "x": pos.x, "y": pos.y, "tief": i, "knoten": p, "basis": p.transform, "nr": n })
			n += 1
		if n >= list.size():
			break
	return { "plaetze": plaetze, "bis": n }


## Plattenhülle: quadratisch, mit eigener Grafik in der Farbe der Platte (plattenhuelle.gdshader)
## und dem Namen unten; mit dem echten Bild, wenn es eins auf der Platte gibt (eigene Musik).
static func huelle_platte(e: Dictionary, nur_ruecken := false) -> Node3D:
	var root := Node3D.new()
	var s := 0.3
	if nur_ruecken:
		# Im Rücken-Regal sieht man nur den Rand: schlichte Hülle in der Farbe der Platte.
		var r := MeshInstance3D.new()
		r.mesh = F.kiste(Vector3(s, s, 0.005), 0.0015, false, 2)
		r.material_override = S.lack((e.farbe as Color).darkened(0.1), 0.6, 0.3)
		r.position = Vector3(0, s * 0.5, 0)
		root.add_child(r)
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = F.kiste(Vector3(s, s, 0.005), 0.0015, false, 2)
	var mat := ShaderMaterial.new()
	mat.shader = PLATTE_S
	mat.set_shader_parameter("farbe", e.farbe)
	mat.set_shader_parameter("muster", absi(str(e.name).hash()) % 4)
	mi.material_override = mat
	mi.position = Vector3(0, s * 0.5, 0)
	root.add_child(mi)
	var art := str(e.get("art", ""))
	if art != "" and not art.begins_with("http") and FileAccess.file_exists(art):
		var bild := MeshInstance3D.new()
		bild.mesh = F.flaeche(s - 0.004, s - 0.004)
		var bm := StandardMaterial3D.new()
		bm.roughness = 0.65
		bild.material_override = bm
		bild.position = Vector3(0, s * 0.5, 0.0027)
		root.add_child(bild)
		Media.file_texture(art, 360, func(t: Variant) -> void:
			if t is Texture2D:
				bm.albedo_texture = t)
		return root
	var l := Label3D.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var name_ := str(e.name)
	l.text = name_ if name_.length() <= 22 else name_.substr(0, 21).strip_edges() + "…"
	l.font = UzTheme.font("ui_bold")
	l.font_size = 30
	l.outline_size = 0
	l.pixel_size = 0.00042
	l.modulate = Color("#f6f1e7") if (e.farbe as Color).get_luminance() < 0.6 else Color("#1b1916")
	l.shaded = true
	l.render_priority = 2
	l.position = Vector3(0, s * 0.075, 0.0031)
	root.add_child(l)
	return root

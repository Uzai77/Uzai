extends RefCounted
## Guide › Start, solange ein Spiel läuft – eine ruhige Liste unter dem Spielblock:
## - Block: Cover mit Glimmen, Titel, „System · Sitzung 0:12:40“, Erfolge als dünner Balken;
##   Weiterspielen (Hauptaktion) · Beenden · Optionen (leise).
## - Liste, kurz und passend zum Spiel: Bildschirmfoto (X), Clip sichern (halten: aufnehmen; ohne
##   FFmpeg „Aufnahme einrichten“), eigene Zeilen und was gerade läuft (Übertragung, offenes Overlay,
##   eingeschalteter Bildmodus), dazu, was die Lage nach vorn holt (Speichern und Laden im Emulator,
##   Übertragen im Sprachkanal) – start_rows.
## - Zuletzt eine Zeile „Weitere Aktionen“ – die Seitenleiste mit Gruppen (auch Bildmodus und
##   Steam-Overlay, solange sie nicht vorn stehen): passend zur Lage vorn, dann Spiel (Erfolge,
##   Aufnahmen – solange der Start sie nicht zeigt), Aufnehmen und teilen, Spielstand, Bild und
##   Leistung, Mehrspieler, Sprachkanal, Nebenbei. Mikro, Lautstärke und Controller stehen in der
##   Schnellleiste des Starts (guide_start.gd). Entfernt ist nichts: jede Handlung ist weiter mit
##   dem Controller erreichbar, die häufigen mit einem Druck, der Rest mit zwei oder drei.

const U := preload("res://src/ui/u.gd")
const Sheet := preload("res://src/ui/layers/sheet.gd")
const ListItem := preload("res://src/ui/components/list_item.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")
const GuidePip := preload("res://src/ui/components/guide_pip.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const Lang := preload("res://src/core/lang.gd")
const Walkthrough := preload("res://src/core/walkthrough.gd")
const WalkthroughSheet := preload("res://src/ui/layers/walkthrough_sheet.gd")
const GuideLeistung := preload("res://src/ui/components/guide_leistung.gd")
const AppSteuerung := preload("res://src/core/app_steuerung.gd")
const AppTastatur := preload("res://src/ui/app_tastatur.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const QuickResume := preload("res://src/core/quick_resume.gd")
const Spielstaende := preload("res://src/ui/layers/spielstaende.gd")
const Main := preload("res://src/main.gd")

## Eigene Zeilen im Reiter Start (Einstellungen → Kacheln im Guide) bzw. vorn unter „Mehr“.
const PRIMARY_MAX := 4
## Ab dieser Stufe nie in der ersten Reihe, nur unter „Mehr“.
const SHEET_ONLY := 50
## Darunter läuft etwas, das man beenden will (Aufnahme, Übertragung, offenes Overlay): immer vorn,
## auch vor eigenen Kacheln.
const URGENT := 5
## Eigene Kacheln (Einstellungen → Im Spiel → Kacheln im Guide, Punkt 20): [Kennung, Name, Symbol].
## „save“ steht für Speichern und Laden zusammen.
const CHOICES := [["shot", "Bildschirmfoto", "camera"], ["clip", "Clip speichern", "spark"], ["record", "Aufnehmen", "record"],
	["live", "Übertragen", "live"], ["lossless", "Bildrate ×2", "bolt"], ["save", "Speichern und Laden", "save"],
	["filter", "Bildfilter", "tv"], ["pip", "Bild in Bild", "pip"], ["help", "Lösungshilfe", "bulb"], ["perf", "Leistung", "speed"]]
## Gruppen unter „Mehr“, in dieser Reihenfolge.
const GROUPS := [["lage", "Passend zur Lage"], ["spiel", "Spiel"], ["teilen", "Aufnehmen und teilen"], ["spielstand", "Spielstand"],
	["leistung", "Bild und Leistung"], ["mehrspieler", "Mehrspieler"], ["sprache", "Sprachkanal"], ["nebenbei", "Nebenbei"]]
## Was im Reiter Start eigene Zeilen hat (kommt nie über start_rows; in „Weitere Aktionen“ nur,
## solange der Start es nicht zeigt – siehe open_more).
const FIXED := ["shot", "clip", "record", "filter", "overlay"]
## So viele Handlungen holt die Lage höchstens zusätzlich in den Start (ein Paar zählt zwei).
const LAGE_MAX := 2


# --- Was wohin gehört (öffentlich für die Tests) ----------------------------------------------

## Welche Handlungen in die erste Reihe kommen. items: [{ id, prio, pair? }] in Anzeigereihenfolge;
## prio klein = wichtig, ab SHEET_ONLY nur unter „Mehr“. Höchstens PRIMARY_MAX; ein Paar (Speichern
## und Laden) kommt nur zusammen nach vorn. pins: eigene Kacheln je Platz ("" = automatisch) – sie
## stehen an ihrem Platz, fehlt eine gerade, rückt dort die nächste wichtige nach; nur was gerade läuft
## (prio unter URGENT) verdrängt sie. { primary: [id], more: [id] } – primary nach Plätzen, sonst in
## der Reihenfolge von items, more in der von items, zusammen genau alle.
static func plan(items: Array, slots := PRIMARY_MAX, pins: Array = []) -> Dictionary:
	var by_id := {}
	for it in items:
		by_id[str(it.id)] = it
	var order := items.duplicate()
	order.sort_custom(func(a, b) -> bool:
		if int(a.prio) != int(b.prio):
			return int(a.prio) < int(b.prio)
		return items.find(a) < items.find(b))
	var picked := {}
	var pinned: Array = []         ## [Platz, Kennung] der eigenen Kacheln, die gerade gehen
	for i in mini(pins.size(), slots):
		var id := str(pins[i])
		if id == "" or picked.has(id) or not by_id.has(id):
			continue
		var mate := _mate(by_id, id)
		if picked.size() + (2 if mate != "" else 1) > slots:
			continue
		picked[id] = true
		if mate != "":
			picked[mate] = true
		pinned.append([i, id])
	for it in order:
		var id := str(it.id)
		if picked.has(id) or int(it.prio) >= SHEET_ONLY:
			continue
		var mate := _mate(by_id, id)
		var need := 2 if mate != "" else 1
		# Läuft etwas, verdrängt es die letzte eigene Kachel (samt Partner).
		while int(it.prio) < URGENT and picked.size() + need > slots and not pinned.is_empty():
			var last: Array = pinned.pop_back()
			picked.erase(last[1])
			picked.erase(_mate(by_id, str(last[1])))
		if picked.size() + need > slots:
			continue
		picked[id] = true
		if mate != "":
			picked[mate] = true
	# Plätze: eigene Kacheln dort, wo sie gewählt sind (ihr Partner gleich dahinter), der Rest der
	# Reihe nach in die freien Plätze.
	var pos: Array = []
	pos.resize(slots)
	pos.fill("")
	var placed := {}
	for pn in pinned:
		if not picked.has(pn[1]):
			continue
		for id in [str(pn[1]), _mate(by_id, str(pn[1]))]:
			if id == "" or placed.has(id):
				continue
			var at := int(pn[0]) if id == str(pn[1]) and pos[int(pn[0])] == "" else _free_after(pos, int(pn[0]))
			pos[at] = id
			placed[id] = true
	for it in items:
		var id := str(it.id)
		if picked.has(id) and not placed.has(id):
			pos[_free_after(pos, -1)] = id
			placed[id] = true
	var primary: Array = pos.filter(func(x): return str(x) != "")
	var more: Array = []
	for it in items:
		if not picked.has(str(it.id)):
			more.append(str(it.id))
	return { "primary": primary, "more": more }


## Partner eines Paars, wenn es ihn gerade gibt (sonst "").
static func _mate(by_id: Dictionary, id: String) -> String:
	var mate := str((by_id.get(id, {}) as Dictionary).get("pair", ""))
	return mate if by_id.has(mate) else ""


## Erster freier Platz hinter after, sonst der erste freie überhaupt.
static func _free_after(pos: Array, after: int) -> int:
	for i in range(after + 1, pos.size()):
		if str(pos[i]) == "":
			return i
	return pos.find("")


## Guide passend zur Lage (Punkt 102): was gerade zählt, rückt in der Reihe nach vorn – ruhig und
## vorhersehbar, nichts springt, solange der Guide offen ist (er baut nur beim Öffnen und bei neuen
## Daten neu). ctx: { emulator (Speichern/Laden geht), voice (im Sprachkanal), lossless, filter (an) }.
## Gibt neue Stufen zurück; die Liste selbst bleibt unverändert.
static func situate(items: Array, ctx: Dictionary) -> Array:
	var out: Array = []
	for it in items:
		var a: Dictionary = (it as Dictionary).duplicate()
		var id := str(a.id)
		var p := int(a.prio)
		# Was eingeschaltet ist, steht vorn – zum Ausschalten.
		if (id == "lossless" and bool(ctx.get("lossless", false))) or (id == "filter" and bool(ctx.get("filter", false))):
			p = mini(p, 9)
		# Emulator: Speichern und Laden sind das, wofür man den Guide meist öffnet.
		if id in ["save", "load"] and bool(ctx.get("emulator", false)):
			p = mini(p, 8)
		# Im Sprachkanal: „Übertragen“ vor Foto und Clip.
		if id == "live" and bool(ctx.get("voice", false)):
			p = mini(p, 7)
		a["prio"] = p
		out.append(a)
	return out


## Eigene Kacheln aus den Einstellungen: genau PRIMARY_MAX Plätze, "" = automatisch.
static func pins() -> Array:
	var raw: Variant = Config.get_value("system.guide_tiles", [])
	var out: Array = []
	for i in PRIMARY_MAX:
		var id := str(raw[i]) if raw is Array and i < (raw as Array).size() else ""
		out.append(id if CHOICES.any(func(c): return str(c[0]) == id) else "")
	return out


## Die Handlungen mit den Stufen der Lage (wenn „Guide passend zur Lage“ an ist).
static func situated_now(acts: Array) -> Array:
	if not bool(Config.get_value("system.guide_smart", true)):
		return acts
	return situate(acts, { "emulator": Launcher.has_hotkey("save") and Launcher.has_hotkey("load"),
		"voice": Voice.in_channel(),
		"lossless": Lossless.active, "filter": Launcher.filter_active() })


## Die Handlungen für Reihe und „Mehr“: mit Lage (wenn eingeschaltet) und eigenen Kacheln.
static func plan_now(acts: Array) -> Dictionary:
	return plan(situated_now(acts), PRIMARY_MAX, pins())


## Die neueste Aufnahme, bevorzugt vom laufenden Spiel (Capture.for_game: Spiel-ID, sonst Titel
## im Dateinamen), sonst die neueste überhaupt; {} ohne Aufnahmen.
static func newest(game: Dictionary) -> Dictionary:
	var mine: Array = Capture.for_game(game, 1) if not game.is_empty() else []
	if not mine.is_empty():
		return mine[0]
	var all: Array = Capture.latest(1)
	return all[0] if not all.is_empty() else {}


## Zeile unter „Aufnahmen“: „Neuester Clip · Vor 3 Min.“, „Bildschirmfoto · Gestern“.
static func capture_line(it: Dictionary) -> String:
	if it.is_empty():
		return "Noch keine Clips oder Fotos"
	var what := "Neuester Clip" if str(it.get("kind", "")) == "clip" else "Bildschirmfoto"
	var when := U.ago(int(it.get("mtime", 0)))
	return what + ("  ·  " + U.lower_first(when) if when != "" else "")


## „Mira spielt mit“, „Mira und Ole spielen mit“, „Mira und 2 weitere spielen mit“.
static func with_me_text(names: Array) -> String:
	match names.size():
		0:
			return ""
		1:
			return "%s spielt mit" % names[0]
		2:
			return "%s und %s spielen mit" % [names[0], names[1]]
	return "%s und %d weitere spielen mit" % [names[0], names.size() - 1]


# --- Aufbau -------------------------------------------------------------------------------------

## Alle Handlungen, die es gerade gibt: { id, prio, pair, group, title, icon, state, on, desc,
## hint, cb, close } – cb schließt bei Bedarf selbst den Guide. Reihenfolge = Anzeige.
static func actions(g: Control) -> Array:
	var main: Main = g.main
	var game: Dictionary = Launcher.current
	var out: Array = []
	var shot: bool = g._can_screenshot()
	if Launcher.rp_overlay_due() and (str(game.get("source", "")) == "steam" or RemotePlay.can_invite()):
		# Nach einer Remote-Play-Einladung lässt Steam das Overlay oft offen: dann ganz vorn.
		out.append({ "id": "overlay", "prio": 0, "group": "mehrspieler", "title": "Steam-Overlay", "icon": "steam",
			"state": "offen", "desc": "Steams Overlay schließen, ohne Tastatur", "hint": "Schließen", "prefer": true,
			"cb": func() -> void: main.steam_overlay() })
	if shot:
		out.append({ "id": "shot", "prio": 10, "group": "teilen", "title": "Bildschirmfoto", "icon": "camera", "state": "",
			"desc": "Auch von Vollbild-Spielen", "cb": func() -> void: main.take_screenshot() })
		# Uzais eigene Aufnahme: der Clip endet, als der Guide aufging. Unten der Zustand des Puffers.
		out.append({ "id": "clip", "prio": 11, "group": "teilen", "title": "Clip speichern", "icon": "spark",
			"state": Capture.clip_state_text(), "on": Capture.state == "puffer", "hint": "Clip speichern",
			"desc": "Die letzten %d Sekunden als Video" % Capture.length_s(), "cb": func() -> void: main.save_clip() })
		if Capture.via_uzai():
			var rec := Capture.recording
			# Kurze Titel: „Aufnahme starten“ brach in der Kachel zweizeilig um.
			out.append({ "id": "record", "prio": 1 if rec else 30, "group": "teilen", "title": "Aufnahme" if rec else "Aufnehmen",
				"icon": "record", "state": (Capture.record_text() + "  ·  beenden") if rec else "", "on": rec,
				"hint": "Beenden und speichern" if rec else "Aufnahme starten", "desc": "Längere Aufnahme, höchstens 10 Minuten",
				"cb": func() -> void: main.toggle_record() })
	# Im Sprachkanal (oder schon live): das Spiel mit einem Druck an Discord übertragen.
	if Voice.in_channel() or main.discord_live:
		var live: bool = main.discord_live
		out.append({ "id": "live", "prio": 2 if live else 12, "group": "teilen", "title": "Stream beenden" if live else "Übertragen",
			"icon": "live", "state": "live" if live else "", "on": live, "hint": "Beenden" if live else "Mein Spiel übertragen",
			"desc": "Dein Spiel im Sprachkanal zeigen (Go Live)", "cb": func() -> void: main.discord_go_live() })
	if Lossless.available():
		var lon := Lossless.active
		out.append({ "id": "lossless", "prio": 13, "group": "leistung", "title": "Bildrate ×2", "icon": "bolt", "state": "An" if lon else "",
			"on": lon, "hint": "Ausschalten" if lon else "Einschalten", "desc": "Lossless Scaling: mehr Bilder pro Sekunde",
			"cb": func() -> void:
				g.close()
				main.guide_lossless() })
	# Emulator mit Spielständen (src/core/quick_resume.gd): Sichern legt einen eigenen Stand mit Bild
	# in Uzais Ablage (der Platz im Emulator bleibt), Laden wählt aus allen. Sonst die Kürzel des
	# Emulators (sein eingestellter Platz).
	if main.rest != null and QuickResume.supported(game):
		var gid := str(game.get("id", ""))
		out.append({ "id": "save", "prio": 25, "pair": "load", "group": "spielstand", "title": "Sichern", "icon": "save",
			"state": "%d von %d" % [QuickResume.own_count(gid), QuickResume.OWN_MAX], "desc": "Eigener Stand mit Bild – das Spiel läuft weiter",
			"cb": func() -> void:
				g.close()
				main.rest.save_place() })
		if Launcher.has_hotkey("load"):
			var n := QuickResume.states(game).size()
			out.append({ "id": "load", "prio": 25, "pair": "save", "group": "spielstand", "title": "Laden", "icon": "load",
				"state": Lang.count(n, "Stand", "Stände") if n > 0 else "noch keiner", "desc": "Einen Stand wählen, mit Bild und Zeit",
				"hint": "Stand wählen",
				"cb": func() -> void:
					Spielstaende.open_for(main, game, "laden", func(rec: Dictionary) -> void:
						g.close()
						main.rest.load_place(rec)) })
	elif Launcher.has_hotkey("save"):
		out.append({ "id": "save", "prio": 25, "pair": "load", "group": "spielstand", "title": "Speichern", "icon": "save",
			"state": g._key_text("save"), "desc": "Schnellspeichern im Emulator",
			"cb": func() -> void: g._hotkey("save", "Spielstand gespeichert") })
	if Launcher.has_hotkey("load") and not (main.rest != null and QuickResume.supported(game)):
		out.append({ "id": "load", "prio": 25, "pair": "save", "group": "spielstand", "title": "Laden", "icon": "load",
			"state": g._key_text("load"), "desc": "Den schnell gespeicherten Stand laden",
			"cb": func() -> void: g._hotkey("load", "Spielstand geladen") })
	if Launcher.filter_possible():
		var fon := Launcher.filter_active()
		out.append({ "id": "filter", "prio": 26, "group": "leistung", "title": "Bildfilter", "icon": "tv", "state": "An" if fon else "",
			"on": fon, "desc": "Röhren- und Pixelfilter (ShaderGlass)",
			"cb": func() -> void:
				# Erst schließen: ShaderGlass startet ganz oben und würde den Guide verdecken.
				g.close()
				main.guide_filter() })
	# Nebenbei ein Video: aus „Weiterschauen“ gleich klein in der Ecke (src/core/pip.gd).
	if GuidePip.can_start():
		out.append({ "id": "pip", "prio": 31, "group": "nebenbei", "title": "Bild in Bild", "icon": "pip", "state": "",
			"hint": "Video auswählen", "desc": "Ein Video aus „Weiterschauen“ in der Ecke", "trail": "",
			"cb": func() -> void: GuidePip.open_picker(g) })
	# Lösungshilfe (Punkt 111): YouTube-Videos zum Spiel, gleich klein in der Ecke.
	if Walkthrough.available():
		out.append({ "id": "help", "prio": 32, "group": "nebenbei", "title": "Lösungshilfe", "icon": "bulb", "state": "",
			"hint": "Lösung suchen", "desc": "Videos zu diesem Spiel – Bosse, Fundorte, Komplettlösung – in der Ecke",
			"cb": func() -> void: WalkthroughSheet.open_for(g) })
	# Dein Zimmer über dem Spiel: Der Fernseher zeigt das Spiel live, A dort fährt zurück hinein.
	# (Ist das Zimmer schon offen, stehen oben eigene Zeilen dafür: zimmer_zeilen.)
	if main.room_layer() == null:
		out.append({ "id": "zimmer", "prio": 34, "group": "nebenbei", "title": "Dein Zimmer", "icon": "home", "state": "",
			"hint": "Zimmer betreten", "desc": "Dein Zimmer betreten – das Spiel läuft im Fernseher weiter",
			"cb": func() -> void: main.open_room() })
	# Emulator läuft: Controller den Spielern 1–4 zuordnen (src/ui/layers/spieler_controller.gd).
	if str(game.get("source", "rom")) == "rom" and not game.is_empty():
		out.append({ "id": "spieler", "prio": SHEET_ONLY, "group": "mehrspieler", "title": "Spieler & Controller", "icon": "controller",
			"state": "", "hint": "Zuordnen", "desc": "Welcher Controller Spieler 1–4 ist",
			"cb": func() -> void: load("res://src/ui/layers/spieler_controller.gd").open_for(main) })
	# Leistung (Roadmap 5): steht als Karte unten; als Kachel nur, wenn selbst gewählt.
	if perf_possible():
		var lp: Array = PerfLive.strip_parts(PerfLive.last)
		var lt := "Last und Speicher"
		for part in lp.slice(0, 2):
			if str(part[1]) != "–":
				lt = "%s %s" % [part[0], part[1]]
		out.append({ "id": "perf", "prio": SHEET_ONLY, "group": "leistung", "title": "Leistung", "icon": "speed",
			"state": lt, "hint": "Leistung ansehen",
			"desc": "Last, Speicher, Temperatur und Energieprofil", "cb": func() -> void: GuideLeistung.open(main) })
	return out


## Eigene Zeilen im Start: was in den Einstellungen gewählt ist und was gerade läuft (Übertragung)
## – ohne die festen Zeilen. acts in Anzeigereihenfolge; zurück die Kennungen.
static func start_extras(acts: Array, pinned: Array) -> Array:
	var out: Array = []
	for id in pinned:
		if str(id) != "" and not (str(id) in FIXED) and acts.any(func(x): return str(x.id) == str(id)) and not out.has(str(id)):
			out.append(str(id))
			# Speichern und Laden nur zusammen.
			var a: Dictionary = acts.filter(func(x): return str(x.id) == str(id))[0]
			var mate := str(a.get("pair", ""))
			if mate != "" and acts.any(func(x): return str(x.id) == mate) and not out.has(mate):
				out.append(mate)
	for a in acts:
		if int(a.prio) < URGENT and not (str(a.id) in FIXED) and not out.has(str(a.id)):
			out.append(str(a.id))
	return out


## Was im Start unter den festen Zeilen steht: eigene Zeilen und was gerade läuft (start_extras),
## dann bis zu LAGE_MAX Handlungen, die die Lage nach vorn holt (Stufe unter 10 nach situate:
## Speichern und Laden im Emulator, Übertragen im Sprachkanal, eingeschaltete Bildrate ×2). Ein
## Paar kommt nur zusammen. situated: acts mit den Stufen der Lage (gleiche Reihenfolge).
static func start_rows(acts: Array, pinned: Array, situated: Array) -> Array:
	var out := start_extras(acts, pinned)
	var by_id := {}
	for a in situated:
		by_id[str(a.id)] = a
	var took := 0
	for a in situated:
		var id := str(a.id)
		if int(a.prio) >= 10 or id in FIXED or out.has(id):
			continue
		var mate := _mate(by_id, id)
		var need := 2 if mate != "" and not out.has(mate) else 1
		if took + need > LAGE_MAX:
			continue
		out.append(id)
		took += 1
		if mate != "" and not out.has(mate):
			out.append(mate)
			took += 1
	return out


## Im Spiel: Block mit Aktionen, darunter die kurze Liste; der Rest klappt unter „Mehr …“ auf
## (guide.gd hängt es mit den Reglern an, g._start_more).
static func fill_running(g: Control, game: Dictionary) -> void:
	var main: Main = g.main
	var c: VBoxContainer = g._content
	var res := Achievements.cached(game)
	var has_ach := not res.is_empty() and int(res.get("total", 0)) > 0
	var frac := float(res.get("unlocked", 0)) / maxf(1.0, float(res.get("total", 1))) if has_ach else -1.0
	var go_on := ["Weiterspielen", "primary", "play", "g:art", g.close, "Weiterspielen"]
	var quit := ["Beenden", "flat", "close", "g:quit", g._ask_quit, "Beenden"]
	# No „Optionen“ pill here: a game's options belong to the game in the library (Y), not to the Guide.
	var pills := [go_on, quit]
	# Das Spiel antwortet nicht (Launcher.hung), Beenden läuft schon oder ging nicht: „Sofort beenden“
	# ist dann die Hauptaktion und gewählt.
	if Launcher.quit_sofort():
		quit[0] = "Sofort beenden"
		quit[5] = "Sofort beenden"
		quit[1] = "primary"
		go_on[1] = "flat"
		pills = [quit, go_on]
	# Der Balken zeigt den Stand; die Zahlen stehen in der Zeile „Erfolge“ weiter unten (guide_start.gd).
	# Unter dem Balken die Spielzeit: heute und insgesamt (läuft mit).
	var head: Control = g._head_row(game, Library.display_title(game), g.session_line(game), frac, pills)
	g._session_l = head.get_meta("uz_sub")
	var tl := str(g.time_line(game))
	if tl != "":
		var al := U.label(tl, "cap", "muted", "medium")
		al.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		(g._session_l as Label).get_parent().add_child(al)
		g._time_l = al
	c.add_child(g._rv(head))
	c.add_child(g._divider(18))
	var list: VBoxContainer = g._list()
	c.add_child(list)
	g._start_list = list
	for r in zimmer_zeilen(main):
		list.add_child(g._rv(r))
	var acts := actions(g)
	if g._can_screenshot():
		var shot = GuideRow.new().setup("Bildschirmfoto", "camera")
		shot.key_cmd = "x"
		shot.set_meta("uz_key", "q:shot")
		shot.activated.connect(func() -> void: main.take_screenshot())
		list.add_child(g._rv(shot))
		list.add_child(g._rv(clip_row(g)))
	if Launcher.filter_possible():
		var on := Launcher.filter_active()
		var flt := Config.filter(Launcher.active_filter_id(game))
		var fr = GuideRow.new().setup("Bildmodus", "tv", str(flt.get("name", "")) if on else TranslationServer.translate("aus"))
		fr.icon_color = "accent" if on else "muted"
		fr.chevron = true
		fr.set_meta("uz_key", "q:filter")
		fr.set_meta("uz_hint_a", "Ausschalten" if on else "Einschalten")
		fr.activated.connect(func() -> void:
			# Erst schließen: ShaderGlass startet ganz oben und würde den Guide verdecken.
			g.close()
			main.guide_filter())
		# Eingeschaltet steht er vorn (zum Ausschalten), sonst unter „Weitere Aktionen“.
		if on:
			list.add_child(g._rv(fr))
	# Steams Overlay ohne Tastatur auf- und zumachen: bei Steam-Spielen immer, sonst solange Steam es
	# nach einer Remote-Play-Einladung offen lässt (dann vorn und gewählt).
	var due := Launcher.rp_overlay_due() and (str(game.get("source", "")) == "steam" or RemotePlay.can_invite())
	if (str(game.get("source", "")) == "steam" and (Config.is_windows() or Library.demo)) or due:
		var ov = GuideRow.new().setup("Steam-Overlay", "steam", TranslationServer.translate("offen") if due else "")
		ov.chevron = true
		ov.set_meta("uz_key", "q:overlay")
		ov.set_meta("uz_hint_a", "Schließen" if due else "Öffnen")
		if due:
			ov.set_meta("uz_prefer", true)
		ov.activated.connect(func() -> void: main.steam_overlay())
		# Offen nach einer Einladung: vorn und gewählt; sonst unter „Weitere Aktionen“.
		if due:
			list.add_child(g._rv(ov))
	for id in start_rows(acts, pins(), situated_now(acts)):
		var a: Dictionary = acts.filter(func(x): return str(x.id) == str(id))[0]
		var r := _start_row(a)
		if bool(a.get("prefer", false)):
			r.set_meta("uz_prefer", true)
		list.add_child(g._rv(r))
	# Ganz unten, eine Zeile: alle weiteren Handlungen nach Gruppen (Seitenleiste) – keine Klappe davor.
	var more = GuideRow.new().setup("Weitere Aktionen", "more")
	more.chevron = true
	more.set_meta("uz_key", "q:more")
	more.set_meta("uz_hint_a", "Mehr anzeigen")
	more.set_meta("uz_fold_last", true)
	more.activated.connect(func() -> void: open_more(g))
	g._start_more.append(more)


## Guide beim Spiel im Fernseher (fernsehspiel.gd), ganz oben und klar benannt: im Zimmer „Zum Spiel“
## (die Kamera fährt in den Fernseher, das Spiel liegt dann vorn – wie A am Fernseher), über dem Spiel
## „Dein Zimmer“ (zurück an deinen Platz – wie die Guide-Taste im Spiel).
static func zimmer_zeilen(main: Main) -> Array:
	if main == null or main.room_layer() == null:
		return []
	match str(main.tv_zustand()):
		"zimmer":
			var spiel = GuideRow.new().setup("Zum Spiel", "fullscreen")
			spiel.set_meta("uz_key", "q:tv_spiel")
			spiel.set_meta("uz_hint_a", "Spielen")
			spiel.activated.connect(func() -> void: main.tv_vollbild())
			return [spiel]
		"vollbild":
			var zim = GuideRow.new().setup("Dein Zimmer", "home")
			zim.set_meta("uz_key", "q:tv_zimmer")
			zim.set_meta("uz_hint_a", "Zimmer betreten")
			zim.activated.connect(func() -> void: main.tv_aufstehen())
			return [zim]
	return []


## Eigene App läuft (Store-App, Programm – src/core/apps_extern.gd): Block mit Logo und Name, dann
## Weiter (zurück in die App) · Zurück zu Uzai (die App läuft weiter) · Schließen; darunter der
## Controller als Tasten (je App, src/core/app_steuerung.gd – aus bei Apps, die selbst Controller
## können), Tastatur (Text ins Textfeld der App, app_tastatur.gd), Steuerung (der Leitfaden mit der
## Belegung, app_leitfaden.gd) und die Maus mit dem Controller (aus, bis du sie einschaltest). Keine Spielzeit, keine
## Erfolge, kein Bildschirmfoto (geschützte Videos sind darauf ohnehin schwarz).
static func fill_app(g: Control, app: Dictionary) -> void:
	var main: Main = g.main
	var c: VBoxContainer = g._content
	var go_on := ["Weiter", "primary", "play", "g:art", g.close, "Weiter"]
	var home := ["Zurück zu Uzai", "flat", "home", "g:home", func() -> void:
		g.close()
		Launcher.leave_app(), "Zurück zu Uzai"]
	var quit := ["Schließen", "flat", "close", "g:quit", func() -> void:
		g.close()
		Launcher.quit_game(Launcher.quitting), "Schließen"]
	var pills := [go_on, home, quit]
	if Launcher.quit_sofort():
		quit[0] = "Sofort beenden"
		quit[5] = "Sofort beenden"
		quit[1] = "primary"
		go_on[1] = "flat"
		pills = [quit, go_on, home]
	var head: Control = g._head_row(app, str(app.get("title", "")), g.session_line(app), -1.0, pills)
	g._session_l = head.get_meta("uz_sub")
	c.add_child(g._rv(head))
	c.add_child(g._divider(18))
	var list: VBoxContainer = g._list()
	c.add_child(list)
	g._start_list = list
	var e: Dictionary = app.get("app", {})
	var pad = GuideRow.new().setup("Controller als Tasten", "controller")
	var pon := AppSteuerung.an(e)
	pad.switch_state = 1 if pon else 0
	pad.value = TranslationServer.translate("An" if pon else "Aus")
	pad.set_meta("uz_key", "q:apptasten")
	pad.set_meta("uz_hint_a", "Umschalten")
	var flip_pad := func(_d: int = 0) -> void:
		var now := not AppSteuerung.an(e)
		pad.set_switch(now)
		pad.set_value(TranslationServer.translate("An" if now else "Aus"))
		Launcher.app_steuerung_setzen(now)
	pad.activated.connect(flip_pad)
	pad.stepped.connect(flip_pad)
	list.add_child(g._rv(pad))
	# Text ins Textfeld der App (Uzais Tastatur über dem Guide) und die Belegung am Controller.
	var tast = GuideRow.new().setup("Tastatur", "keyboard")
	tast.set_meta("uz_key", "q:apptastatur")
	tast.set_meta("uz_hint_a", "Öffnen")
	tast.activated.connect(func() -> void: AppTastatur.ueber_guide(main, g))
	list.add_child(g._rv(tast))
	var leit = GuideRow.new().setup("Steuerung", "controller")
	leit.set_meta("uz_key", "q:appleitfaden")
	leit.set_meta("uz_hint_a", "Anzeigen")
	leit.activated.connect(func() -> void:
		g.close()
		# Erst wenn der Guide zu und die App wieder vorn ist.
		await main.get_tree().create_timer(0.9).timeout
		if is_instance_valid(main):
			main.app_leitfaden(true))
	list.add_child(g._rv(leit))
	var mouse = GuideRow.new().setup("Maus mit dem Controller", "controller")
	var on: bool = main.mouse_on
	mouse.switch_state = 1 if on else 0
	mouse.value = TranslationServer.translate("An" if on else "Aus")
	mouse.set_meta("uz_key", "q:mouse")
	var flip := func(_d: int = 0) -> void: main.set_mouse_mode(not main.mouse_on)
	mouse.activated.connect(flip)
	mouse.stepped.connect(flip)
	list.add_child(g._rv(mouse))


## Zeile „Aufnahme“: kurz A sichert die letzten Sekunden als Clip, gehalten startet bzw. beendet
## sie eine längere Aufnahme (nur mit Uzais eigener Aufnahme). Läuft eine, beendet A sie.
static func clip_row(g: Control) -> Control:
	var main: Main = g.main
	var r = GuideRow.new()
	r.icon_name = "record"
	r.set_meta("uz_key", "q:clip")
	if Capture.recording:
		r.title = "Aufnahme läuft"
		r.extra = Capture.record_text()
		r.value = TranslationServer.translate("beenden")
		r.icon_color = "accent"
		r.set_meta("uz_hint_a", "Beenden und speichern")
		r.activated.connect(func() -> void: main.toggle_record())
		return r
	# Ohne FFmpeg: eine klare Zeile zum Einrichten, ohne „halten“ (aufnehmen ginge noch nicht).
	if Capture.via_uzai() and Config.is_windows() and not Capture.has_ffmpeg():
		r.title = "Aufnahme einrichten"
		r.chevron = true
		r.set_meta("uz_hint_a", "Einrichten")
		r.activated.connect(func() -> void: main.save_clip())
		return r
	r.title = "Clip sichern"
	var st := Capture.clip_state_text()
	r.extra = TranslationServer.translate("letzte %d s sichern") % Capture.length_s() if st == "" or Capture.state == "puffer" else st
	if Capture.via_uzai():
		r.value = TranslationServer.translate("halten: aufnehmen")
		r.set_meta("uz_hint_a", "Sichern · halten: aufnehmen")
		r.hold_cb = func() -> void: main.toggle_record()
	else:
		r.set_meta("uz_hint_a", "Clip speichern")
	r.activated.connect(func() -> void: main.save_clip())
	return r


## Eine Handlung als Zeile im Start (eigene Zeile oder was gerade läuft).
static func _start_row(a: Dictionary) -> Control:
	var r = GuideRow.new().setup(str(a.title), str(a.icon), "", str(a.get("trail", a.get("state", ""))))
	r.icon_color = "accent" if bool(a.get("on", false)) else "muted"
	r.set_meta("uz_key", "q:" + str(a.id))
	if str(a.get("hint", "")) != "":
		r.set_meta("uz_hint_a", str(a.hint))
	r.activated.connect(a.cb)
	return r


## Leistung gibt es unter Windows (Helfer) und in der Demo.
static func perf_possible() -> bool:
	return Config.is_windows() or Library.demo


# --- „Mehr“ -------------------------------------------------------------------------------------

## Seitenleiste „Mehr …“: alles, was nicht fest im Start steht, nach Gruppen – vorn, was gerade
## passt (dieselbe Aufteilung wie früher die Kacheln: Lage und eigene Auswahl). focus_group: die
## Auswahl steht gleich in dieser Gruppe.
static func open_more(g: Control, focus_group := "") -> void:
	var main: Main = g.main
	var game: Dictionary = Launcher.current
	var s = Sheet.new()
	s.setup("Mehr", Library.display_title(game) if not game.is_empty() else "", 760)
	s.set_meta("uz_key", "guide:more")
	s.fill_func = func(sheet) -> void:
		var acts := actions(g)
		var p := plan_now(acts)
		var shown := start_rows(acts, pins(), situated_now(acts))
		# Fest im Start: Foto und Aufnahme immer, Bildfilter nur eingeschaltet, Overlay nur offen.
		var fest := ["shot", "clip", "record"]
		if Launcher.filter_active():
			fest.append("filter")
		if Launcher.rp_overlay_due():
			fest.append("overlay")
		var rows := {}
		for gr in GROUPS:
			rows[str(gr[0])] = []
		var used := {}
		for id in p.primary:
			if not (str(id) in fest) and not shown.has(str(id)):
				(rows.lage as Array).append(_action_row(acts.filter(func(x): return str(x.id) == str(id))[0]))
				used[str(id)] = true
		for a in acts:
			if not used.has(str(a.id)) and not (str(a.id) in fest) and not shown.has(str(a.id)):
				(rows[str(a.group)] as Array).append(_action_row(a))
		_extra_rows(g, sheet, game, rows)
		var gap := false
		for gr in GROUPS:
			var list: Array = rows[str(gr[0])]
			if list.is_empty():
				continue
			if gap:
				sheet.add_gap(18)
			gap = true
			var head := U.label(str(gr[1]), "s", "muted", "medium")
			head.clip_text = false
			var hm := U.margin(14, 0, 0, 2)
			hm.add_child(head)
			sheet.add_row(hm)
			if focus_group == str(gr[0]):
				(list[0] as Control).set_meta("uz_default", true)
			for r in list:
				sheet.add_row(r)
	main.open_layer(s)


## Eine Handlung als Zeile; die meisten schließen den Guide selbst.
static func _action_row(a: Dictionary) -> Control:
	var r = ListItem.new()
	r.setup(str(a.title), "", str(a.get("trail", a.get("state", ""))))
	r.icon_name = str(a.icon)
	r.set_meta("uz_key", "m:" + str(a.id))
	if str(a.get("hint", "")) != "":
		r.set_meta("uz_hint_a", str(a.hint))
	r.activated.connect(a.cb)
	return r


## Was nur unter „Mehr“ steht: Erfolge und Aufnahmen (Galerie) – nur, solange der Start sie nicht
## selbst zeigt (Erfolge, sobald bekannt; Aufnahmen, sobald es eine zu diesem Spiel gibt) –, Leute
## und Einladen, Mikro und Ton.
static func _extra_rows(g: Control, sheet: Sheet, game: Dictionary, rows: Dictionary) -> void:
	var main: Main = g.main
	var res := Achievements.cached(game)
	if (Achievements.has_ra() or Achievements.has_steam()) and int(res.get("total", 0)) <= 0:
		var ach = ListItem.new()
		ach.setup("Erfolge", "", "")
		ach.icon_name = "trophy"
		ach.set_meta("uz_key", "m:ach")
		ach.set_meta("uz_hint_a", "Alle Erfolge")
		ach.activated.connect(func() -> void: main.open_game_achievements(game))
		(rows.spiel as Array).append(ach)
	if Capture.for_game(game, 1).is_empty():
		var gal = ListItem.new()
		gal.setup("Aufnahmen", "", "")
		gal.icon_name = "video"
		gal.set_meta("uz_key", "m:captures")
		gal.activated.connect(func() -> void: main.open_captures())
		(rows.spiel as Array).append(gal)
	# Mehrspieler: wer mitspielt (A: Menü an der Person), Einladen, Call zu Remote Play, Overlay.
	var mp: Array = rows.mehrspieler
	for e in g._people_now().filter(func(x): return bool(x.same_game)):
		var fr: Control = g._friend_row(e, true)
		fr.custom_minimum_size.x = 0
		fr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mp.append(fr)
	if str(game.get("source", "")) == "steam" or RemotePlay.can_invite():
		var inv = ListItem.new()
		inv.setup("Freund einladen", "", "Steam" if str(game.get("source", "")) == "steam" else "Remote Play")
		inv.icon_name = "plus"
		inv.set_meta("uz_key", "m:invite")
		inv.activated.connect(func() -> void: g._invite_picker(game))
		mp.append(inv)
		var CallInvite = load("res://src/core/call_invite.gd")
		var av: Dictionary = CallInvite.availability()
		if bool(av.show):
			var ci = ListItem.new()
			ci.setup(str(av.label), "" if bool(av.ok) else str(av.why), "")
			ci.icon_name = "controller"
			ci.set_meta("uz_key", "m:callinvite")
			ci.activated.connect(func() -> void:
				if not bool(av.ok):
					Toasts.show_toast("Remote Play Together ist aus", str(av.why), "controller", { "ms": 8000 })
					return
				var l = load("res://src/ui/layers/call_invite.gd").new()
				l.main = main
				main.open_layer(l)
			)
			mp.append(ci)
		# Steams Overlay für Remote Play bei Nicht-Steam-Spielen (Steam-Spiele haben es im Start).
		if str(game.get("source", "")) != "steam" and (Config.is_windows() or Library.demo) and not Launcher.rp_overlay_due():
			var ov = ListItem.new()
			ov.setup("Steam-Overlay", "", "")
			ov.icon_name = "steam"
			ov.set_meta("uz_key", "m:overlay")
			ov.activated.connect(func() -> void: main.steam_overlay())
			mp.append(ov)
	# Sprachkanal: Mikro und Ton, ohne in den Reiter Discord zu wechseln.
	if Voice.ready_() and Voice.in_channel():
		var sp: Array = rows.sprache
		var mic = ListItem.new()
		mic.setup("Mikro", "", "Aus" if Mixer.mic_aus() else "An")
		mic.icon_name = "mic_off" if Mixer.mic_aus() else "mic"
		mic.set_meta("uz_key", "m:mic")
		mic.set_meta("uz_hint_a", "Mikro an" if Mixer.mic_aus() else "Mikro aus")
		mic.activated.connect(func() -> void:
			await Mixer.toggle_mic()
			if is_instance_valid(sheet) and sheet.is_inside_tree():
				sheet.refill()
		)
		sp.append(mic)
		var deaf = ListItem.new()
		deaf.setup("Ton", "", "Aus" if Voice.self_deaf else "An")
		deaf.icon_name = "headset_off" if Voice.self_deaf else "headset"
		deaf.set_meta("uz_key", "m:deaf")
		deaf.set_meta("uz_hint_a", "Ton an" if Voice.self_deaf else "Ton aus")
		deaf.activated.connect(func() -> void:
			Voice.set_self_deaf(not Voice.self_deaf)
			sheet.refill()
		)
		sp.append(deaf)

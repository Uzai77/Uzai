extends Node
## Guide-Taste kurz/gehalten (Punkt 21), eigene Kacheln (Punkt 20) und Guide passend zur Lage
## (Punkt 102). Aufruf: godot --headless --path . res://tests/logic_guidetasten.tscn

const GuideHold := preload("res://src/core/guide_hold.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")
const GuideTiles := preload("res://src/ui/layers/guide_tiles.gd")
const Rest := preload("res://src/core/rest.gd")
const Lang := preload("res://src/core/lang.gd")
const IconsS := preload("res://src/core/icons.gd")
const Quelle := preload("res://tests/quelle.gd")
const Fenster := preload("res://src/main_fenster.gd")
const Zustand := preload("res://src/core/zustand.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_press()
	_aufstehen()
	_plan()
	_situation()
	_tiles()
	_quick()
	_settings()
	_texts()
	_vollbild()
	_lage()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Wo Uzais Fenster neben dem Spiel liegt und wohin Eingaben gehen – aus den Schaltern berechnet und an
## src/core/zustand.gd gemeldet (Fehlerbericht), ohne etwas daran zu ändern.
func _lage() -> void:
	print("Lage im Spiel (Zustand.lage)")
	var f := Fenster.new()
	var lagen: Array = [f.fenster_lage()]
	f._parked = true
	lagen.append(f.fenster_lage())
	f._overlay_mode = true
	lagen.append(f.fenster_lage())
	f._overlay_deckend = true
	lagen.append(f.fenster_lage())
	f._spiel_minimiert = true
	lagen.append(f.fenster_lage())
	f._overlay_mode = false
	f._kulisse = true
	lagen.append(f.fenster_lage())
	check(lagen == ["vorn", "geparkt", "guide", "guide_deckend", "guide_minimiert", "kulisse"],
			"Fenster: vorn, geparkt, Guide (durchsichtig, deckend, Spiel minimiert), Kulisse – %s" % ", ".join(lagen))
	var ist := Zustand.lage().filter(func(e: Dictionary) -> bool: return str(e.name) == "spiel.fenster")
	check(ist.size() == 1 and str(ist[0].zustand) == "kulisse", "jeder Wechsel steht in Zustand.lage()")
	f.free()
	var vorher := [Nav.game_mode, Nav.passthrough, Nav.pad_unfocused]
	Nav.game_mode = false
	Nav.passthrough = false
	Nav.pad_unfocused = false
	var e: Array = [Nav.eingabe_lage()]
	Nav.game_mode = true
	e.append(Nav.eingabe_lage())
	Nav.pad_unfocused = true
	e.append(Nav.eingabe_lage())
	Nav.passthrough = true
	e.append(Nav.eingabe_lage())
	check(e == ["menue", "spiel", "spiel_ohne_fokus", "durchlass"], "Eingaben: Menü, Spiel, ohne Fokus, Durchlass – %s" % ", ".join(e))
	Nav.game_mode = vorher[0]
	Nav.passthrough = vorher[1]
	Nav.pad_unfocused = vorher[2]


## Spiel im Fernseher des Zimmers: Im Vollbild führt die Guide-Taste sofort zurück ins Zimmer – ohne
## Guide, ohne Halten, ohne Warten auf einen zweiten Druck; erst der nächste Druck öffnet den Guide.
func _aufstehen() -> void:
	print("Guide im Vollbild aus dem Fernseher: zurück ins Zimmer")
	check(not FileAccess.file_exists("res://src/core/guide_doppel.gd"), "kein Doppeldruck mehr (kein Warten, kein Flackern)")
	var mg := FileAccess.get_file_as_string("res://src/main_guide.gd")
	var tg := mg.substr(mg.find("func toggle_guide("), 6000)
	var block := tg.substr(tg.find("Fernsehspiel.guide_taste(_tv)") - 200, 400)
	check(block.contains("== \"aufstehen\"") and block.contains("tv_aufstehen()"), "im Vollbild: der Druck fährt zurück ins Zimmer")
	check(tg.find("tv_aufstehen()") < tg.find("_guide_gen += 1") and tg.find("tv_aufstehen()") < tg.find("_druck_merken("),
			"zurück, bevor der Guide auf- oder zugeht (kein Halten nötig)")
	check(block.contains("src != \"\" and src != \"menu\""), "öffnet Uzai den Guide selbst (Anruf) oder Start+Select, geht er auf wie immer")
	check(not mg.contains("_hold_los") and mg.substr(mg.find("func _guide_press_done("), 500).contains("toggle_guide(Guide.QUICK)"),
			"mit Halten im Zimmer: gehalten kommt das Schnellmenü wie überall")
	var gg := FileAccess.get_file_as_string("res://src/ui/components/guide_game.gd")
	var zz := gg.substr(gg.find("static func zimmer_zeilen"), 1200)
	check(zz.contains("main.tv_vollbild()") and zz.contains("main.tv_aufstehen()"), "Guide: im Zimmer „Zum Spiel“, über dem Spiel „Dein Zimmer“")
	var zb := FileAccess.get_file_as_string("res://src/room/zimmer_basis.gd")
	check(not zb.contains("[\"guide\", \"Aufstehen\"]") and not zb.contains("2× Aufstehen"), "keine Tastenzeile mehr für den alten Zustand vor dem Fernseher")


func _press() -> void:
	print("Guide-Taste: kurz oder gehalten")
	var h = GuideHold.new()
	check(not h.druck("combo", 0, "menu") and not h.druck("menu", 0, "menu") and not h.druck("", 0, "menu"),
			"View + Start, Start allein und Uzai selbst kennen kein Halten")
	check(not h.druck("pad", 0, "rest") and not h.druck("helper", 0, "aus"), "ohne Schnellmenü (Ruhemodus, aus) merkt sich die Klasse nichts")
	check(h.druck("pad", 1000, "menu") and h.waiting, "Guide-Taste mit Schnellmenü: der Druck läuft")
	check(h.tick(1100, true) == "" and h.waiting, "noch gedrückt, unter der Grenze: nichts zu tun")
	check(h.tick(1150, false) == "" and not h.waiting, "kurz losgelassen: nichts mehr – der Guide ist beim Drücken aufgegangen")
	h.druck("pad", 2000, "menu")
	check(h.tick(2000 + GuideHold.MENU_MS - 1, true) == "" and h.tick(2000 + GuideHold.MENU_MS, true) == "menu",
			"gehalten bis zur Grenze: Schnellmenü (nicht früher)")
	check(h.tick(2900, false) == "" and not h.waiting, "danach Loslassen: nichts mehr")
	h.druck("helper", 3000, "menu")
	check(h.tick(3600, false) == "" and h.waiting, "Helfer: Godots Sicht zählt nicht, seine Meldungen entscheiden")
	check(h.helper("guide-up") == "" and not h.waiting, "Helfer meldet Loslassen: der Guide bleibt")
	h.druck("helper", 4000, "menu")
	check(h.helper("guide-hold") == "menu" and h.helper("guide-up") == "", "Helfer meldet Halten: Schnellmenü, das Loslassen danach zählt nicht")
	h.druck("helper", 5000, "menu")
	check(h.tick(5000 + GuideHold.MENU_MS + GuideHold.GRACE_MS, true) == "" and not h.waiting, "Helfer schweigt (neu gestartet): der Druck ist vorbei")
	h.druck("pad", 6000, "menu")
	h.cancel()
	check(h.tick(6000 + GuideHold.MENU_MS, true) == "" and h.helper("guide-hold") == "", "Guide halten + X (Clip): kein Schnellmenü")
	check(h.helper("guide-hold") == "", "Halten ohne laufenden Druck (die Taste hat den Guide geschlossen): nichts")
	var mg2 := FileAccess.get_file_as_string("res://src/main_guide.gd")
	var tg2 := mg2.substr(mg2.find("func toggle_guide("), 9000)
	var dr := tg2.substr(tg2.find("_druck_merken(tab, src)"), 200)
	check(mg2.contains("_hold.druck(src, Time.get_ticks_msec())") and dr.contains("Launcher.guide_open = true")
			and not dr.get_slice("Launcher.guide_open = true", 0).contains("return"), "main: der Guide geht beim Drücken auf, ohne aufs Loslassen zu warten")
	var pd := mg2.substr(mg2.find("func _guide_press_done("), 500)
	check(pd.contains("_guide.close()") and pd.contains("toggle_guide(Guide.QUICK)") and pd.contains("_hold_menu = true"),
			"main: gehalten macht der Guide dem Schnellmenü Platz – auch wenn er im Spiel noch wartet")
	check(GuideHold.hold_ms("menu") == GuideHold.MENU_MS and GuideHold.hold_ms("rest") == 1000 and GuideHold.hold_ms("aus") == 0,
			"Haltezeit für den Helfer je Einstellung")
	check(GuideHold.MENU_MS >= 400 and GuideHold.MENU_MS <= 700, "Schwelle deutlich über einem normalen Druck (80–200 ms), aber nicht träge")
	var keep: Variant = Config.get_value("controller.guide_hold", "menu")
	Config.set_value("controller.guide_hold", "quatsch")
	check(GuideHold.mode() == "menu", "unbekannter Wert: Schnellmenü")
	Config.set_value("controller.guide_hold", "rest")
	check(Rest.hold_enabled() and GuideHold.mode() == "rest", "Einstellung Ruhemodus: Halten schläft direkt ein")
	Config.set_value("controller.guide_hold", "menu")
	check(not Rest.hold_enabled(), "Schnellmenü: der Ruhemodus wartet im Menü")
	Config.set_value("controller.guide_hold", keep)
	var helper_src := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(helper_src.contains("Emit(\"guide-up\", i)"), "Helfer meldet das Loslassen der Guide-Taste")
	var main_src := Quelle.lesen("res://src/main.gd")
	check(main_src.contains("_hold.cancel()") and main_src.contains("_hold.helper(kind)"), "main: Clip-Akkord bricht ab, Meldungen des Helfers entscheiden")


func _items() -> Array:
	return [{ "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "record", "prio": 30 },
		{ "id": "live", "prio": 12 }, { "id": "lossless", "prio": 13 }, { "id": "save", "prio": 25, "pair": "load" },
		{ "id": "load", "prio": 25, "pair": "save" }, { "id": "filter", "prio": 26 }, { "id": "pip", "prio": 31 }]


func _plan() -> void:
	print("Eigene Kacheln")
	var voll := _items()
	check(GuideGame.plan(voll).primary == GuideGame.plan(voll, 4, ["", "", "", ""]).primary, "alles automatisch: genau wie ohne Auswahl")
	var p := GuideGame.plan(voll, 4, ["pip", "", "", "filter"])
	check(p.primary == ["pip", "shot", "clip", "filter"], "gewählte Kacheln stehen auf ihrem Platz, dazwischen die wichtigsten (%s)" % str(p.primary))
	check(not (p.more as Array).has("pip") and (p.more as Array).has("live"), "was vorn steht, fehlt unter „Mehr“; Verdrängtes steht dort")
	var all_ids := voll.map(func(x): return str(x.id))
	check((p.primary + p.more).size() == all_ids.size() and all_ids.all(func(i): return (p.primary + p.more).has(i)), "nichts fällt weg")
	var ohne_emu := voll.filter(func(x): return not (str(x.id) in ["save", "load"]))
	check(GuideGame.plan(ohne_emu, 4, ["save", "", "", ""]).primary == GuideGame.plan(ohne_emu).primary,
			"gewählte Kachel gibt es gerade nicht (kein Emulator): Platz automatisch")
	var pair := GuideGame.plan(voll, 4, ["", "save", "", ""])
	check(pair.primary == ["shot", "save", "load", "clip"], "Speichern gewählt: Laden gleich dahinter (%s)" % str(pair.primary))
	check(GuideGame.plan(voll, 4, ["shot", "shot", "", ""]).primary.count("shot") == 1, "doppelt gewählt zählt einmal")
	var rec := voll.duplicate(true)
	rec[2]["prio"] = 1   # Aufnahme läuft
	var pr := GuideGame.plan(rec, 4, ["pip", "filter", "lossless", "clip"])
	check((pr.primary as Array).has("record") and pr.primary.size() == 4 and not (pr.primary as Array).has("clip"),
			"laufende Aufnahme verdrängt die letzte gewählte Kachel (%s)" % str(pr.primary))
	check(GuideGame.plan([{ "id": "x", "prio": 60 }, { "id": "shot", "prio": 10 }], 4, ["x"]).primary == ["x", "shot"],
			"selbst gewählt geht auch, was sonst nur unter „Mehr“ steht")
	check(GuideGame.plan([], 4, ["shot"]).primary.is_empty(), "ohne Werkzeuge: leer, auch mit Auswahl")


func _situation() -> void:
	print("Guide passend zur Lage")
	var voll := _items()
	var same: Array = GuideGame.plan(GuideGame.situate(voll, {})).primary
	check(same == GuideGame.plan(voll).primary, "ohne besondere Lage: wie immer")
	var emu: Array = GuideGame.plan(GuideGame.situate(voll, { "emulator": true })).primary
	check(emu.has("save") and emu.has("load"), "Emulator: Speichern und Laden vorn (%s)" % str(emu))
	var voice: Array = GuideGame.plan(GuideGame.situate(voll, { "voice": true, "emulator": true })).primary
	check(voice.has("live") and voice.has("save") and voice.has("load"), "im Sprachkanal: Übertragen vorn, Spielstand bleibt (%s)" % str(voice))
	var lon: Array = GuideGame.plan(GuideGame.situate(voll, { "emulator": true, "lossless": true })).primary
	check(lon.has("lossless"), "eingeschaltete Bildrate ×2 steht vorn, zum Ausschalten (%s)" % str(lon))
	var orig := _items()
	GuideGame.situate(orig, { "emulator": true, "voice": true })
	check(orig == _items(), "die Liste selbst bleibt unverändert")
	check(GuideGame.plan(GuideGame.situate(voll, { "emulator": true }), 4, ["pip", "", "", ""]).primary[0] == "pip", "eigene Kacheln gehen vor der Lage")
	var gs := FileAccess.get_file_as_string("res://src/ui/components/guide_game.gd")
	check(gs.count("plan_now(acts)") == 1 and gs.count("start_rows(acts, pins(), situated_now(acts))") == 2,
			"„Alle Aktionen“ ordnet nach Lage und eigener Auswahl, der Start zeigt dieselben Zeilen (ohne Dopplung)")
	check(gs.contains("for id in p.primary:"), "„Passend zur Lage“ steht in der Reihenfolge der Plätze (nicht der Handlungen)")
	var acts := [{ "id": "shot", "prio": 10 }, { "id": "live", "prio": 2 }, { "id": "save", "prio": 25, "pair": "load" }, { "id": "load", "prio": 25, "pair": "save" },
		{ "id": "pip", "prio": 31 }]
	check(GuideGame.start_extras(acts, ["", "", "", ""]) == ["live"], "Start ohne eigene Zeilen: nur was gerade läuft (Übertragung)")
	check(GuideGame.start_extras(acts, ["save", "shot", "", ""]) == ["save", "load", "live"], "eigene Zeile Speichern: Laden dahinter, feste Zeilen nicht doppelt")
	# Start kurz und passend: die Lage holt höchstens LAGE_MAX dazu (ein Paar zusammen).
	var emu_s := GuideGame.situate(acts, { "emulator": true })
	check(GuideGame.start_rows(acts, ["", "", "", ""], emu_s) == ["live", "save", "load"], "Emulator: Speichern und Laden direkt im Start")
	check(GuideGame.start_rows(acts, ["", "", "", ""], acts) == ["live"], "ohne Lage: nur was läuft")
	var many := [{ "id": "a", "prio": 7 }, { "id": "b", "prio": 8 }, { "id": "c", "prio": 9 }, { "id": "shot", "prio": 3 }]
	check(GuideGame.start_rows(many, ["", "", "", ""], many) == ["a", "b"], "höchstens zwei aus der Lage, feste Zeilen nie doppelt")


func _tiles() -> void:
	print("Kacheln auswählen")
	var keep: Variant = Config.get_value("system.guide_tiles", [])
	Config.set_value("system.guide_tiles", ["shot", "unbekannt", 7])
	var p := GuideGame.pins()
	check(p == ["shot", "", "", ""], "aus den Einstellungen: vier Plätze, Unbekanntes wird automatisch (%s)" % str(p))
	Config.set_value("system.guide_tiles", "kaputt")
	check(GuideGame.pins() == ["", "", "", ""], "kaputter Wert: alles automatisch")
	check(GuideTiles.set_slot(["shot", "", "", ""], 2, "shot") == ["", "", "shot", ""], "dieselbe Kachel auf einen anderen Platz: der alte wird frei")
	check(GuideTiles.set_slot([], 1, "clip") == ["", "clip", "", ""], "leere Liste: vier Plätze")
	check(GuideTiles.set_slot(["shot", "clip", "", ""], 1, "") == ["shot", "", "", ""], "Automatisch setzt den Platz zurück")
	check(GuideTiles.summary(["", "", "", ""]) == "Automatisch" and GuideTiles.summary(["shot", "", "save", ""]) == "Bildschirmfoto, Speichern und Laden",
			"Zusammenfassung für Einstellungen und „Mehr“")
	for c in GuideGame.CHOICES:
		check(IconsS.P.has(str(c[2])), "Kachel %s: Symbol „%s“ gibt es" % [c[1], c[2]])
	Config.set_value("system.guide_tiles", keep)


func _quick() -> void:
	print("Schnellmenü")
	var game := GuideQuick.ids({ "shot": true, "game": true, "voice": true })
	check(game == ["shot", "clip", "mic", "rest", "quit", "guide"], "im Spiel: Foto, Clip, Mikro, Ruhemodus, Beenden, Guide (%s)" % str(game))
	var win_mic := GuideQuick.ids({ "shot": true, "game": true, "mic": true })
	check(win_mic.has("mic"), "Mikro auch ohne Sprachkanal, wenn das Windows-Mikrofon schaltbar ist (%s)" % str(win_mic))
	check(GuideQuick.ids({ "shot": true, "game": true }) == ["shot", "clip", "rest", "quit", "guide"], "ohne Sprachkanal kein Mikro")
	check(GuideQuick.ids({ "shot": true, "game": true, "pip": true }) == ["shot", "clip", "pip", "rest", "quit", "guide"],
			"Bild in Bild läuft: „Bild verschieben“ im Schnellmenü")
	check(GuideQuick.ids({ "shot": true, "video": true }) == ["shot", "rest", "video_stop", "guide"], "Video: Foto, Ruhemodus, Video beenden, Guide (kein Clip)")
	check(GuideQuick.ids({}) == ["rest", "power", "guide"], "nichts läuft: Ruhemodus, Ausschalten, Guide")
	for ctx in [{ "shot": true, "game": true, "voice": true }, { "video": true }, {}]:
		check(GuideQuick.ids(ctx).size() <= 6, "höchstens sechs Kacheln (%s)" % str(ctx))
	for ic in ["camera", "spark", "mic", "mic_off", "moon", "close", "power", "grid"]:
		check(IconsS.P.has(ic), "Symbol „%s“ gibt es" % ic)
	var gs := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(gs.contains("if start_tab == QUICK:\n\t\tGuideQuick.build(self)") and gs.contains("return GuideQuick.handle(self, cmd)"),
			"der Guide baut sich als Schnellmenü klein auf")


func _settings() -> void:
	print("Einstellungen: alter Wert wird übernommen")
	var keep: Dictionary = Config.settings.duplicate(true)
	Config.settings["rest"]["hold_guide"] = false
	Config.settings["controller"]["guide_hold"] = "menu"
	Config._migrate(1)
	check(str(Config.settings.controller.guide_hold) == "aus" and not (Config.settings.rest as Dictionary).has("hold_guide"),
			"„Guide halten“ war aus: bleibt aus, alter Schlüssel weg")
	Config.settings["rest"]["hold_guide"] = true
	Config.settings["controller"]["guide_hold"] = "menu"
	Config._migrate(1)
	check(str(Config.settings.controller.guide_hold) == "menu" and not (Config.settings.rest as Dictionary).has("hold_guide"),
			"war an: jetzt das Schnellmenü (Ruhemodus darin)")
	check(int(Config.settings.schema) == Config.SETTINGS_VERSION and Config.SETTINGS_VERSION >= 2, "Aufbau-Version erhöht")
	check(str(Config.DEFAULTS.controller.guide_hold) == "menu" and Config.DEFAULTS.system.guide_tiles is Array and bool(Config.DEFAULTS.system.guide_smart),
			"Standard: Schnellmenü, Kacheln automatisch, passend zur Lage an")
	Config.settings = keep
	var sv := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	# Entschlackt: die Zeile steht nur noch einmal (Controller), nicht zusätzlich im Ruhemodus.
	check(sv.count("\"controller.guide_hold\"") == 1 and not sv.contains("rest.hold_guide"), "Einstellung an einer Stelle (Controller), die alte ist weg")
	# „Passend zur Lage“ wohnt in „Kacheln im Guide“ (guide_tiles.gd), die Einstellungen öffnen sie.
	var gt := Quelle.lesen("res://src/ui/layers/guide_tiles.gd")
	check(sv.contains("GuideTiles.open(main)") and gt.contains("\"system.guide_smart\""), "Im Spiel → Guide: Kacheln und Lage")


## Neue Texte, bevor sie in i18n/en.json stehen: UZAI_TEST_I18N zeigt auf die JSON-Datei mit ihnen.
func _texts() -> void:
	print("Englisch")
	var path := OS.get_environment("UZAI_TEST_I18N")
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		print("  (UZAI_TEST_I18N nicht gesetzt, übersprungen)")
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	check(d is Dictionary and (d as Dictionary).size() > 20, "Übersetzungen lesbar")
	if not (d is Dictionary):
		return
	var t = Lang.new()
	t.load_dict(d)
	check(t.translate("Schnellmenü") == "Quick menu" and t.translate("Platz 3") == "Slot 3", "Schnellmenü, Platz 3")
	check(t.translate("Kacheln im Guide") != "Kacheln im Guide" and t.translate("Guide passend zur Lage") != "Guide passend zur Lage", "Einstellungen übersetzt")
	for k in (d as Dictionary).keys():
		check(str(d[k]).strip_edges() != "", "„%s“ hat eine Übersetzung" % str(k).left(40))


## Guide über Vollbild-Spielen (Freund: „fullscreen games guide not working properly“) und Alt+Tab
## („lock up of screen when alt tabbing“): Erkennen, Spiel kurz minimieren, deckend, zurück; der
## schnelle Helfer wartet nie auf ein beschäftigtes Spiel; Uzai bleibt nach Alt+Tab nicht oben.
func _vollbild() -> void:
	print("Guide über exklusivem Vollbild, Alt+Tab")
	var d := Vector2i(2560, 1440)
	check(Fenster.vollbild_grund({ "fg_game": true, "quns": 3, "fg_full": true }, d, d) == "d3d", "Windows meldet D3D-Vollbild → Spiel kurz weg")
	check(Fenster.vollbild_grund({ "fg_game": true, "quns": 7, "fg_full": true }, d, Vector2i(1920, 1080)) == "aufloesung",
			"Spiel hat die Auflösung umgestellt (LWJGL 1920×1080 auf 2560×1440) → Spiel kurz weg")
	check(Fenster.vollbild_grund({ "fg_game": true, "quns": 2, "fg_full": true }, d, d) == "", "randloses Vollbild (QUNS 2): durchsichtig wie bisher")
	check(Fenster.vollbild_grund({ "fg_game": false, "quns": 3 }, d, d) == "", "anderes Programm vorn: nichts minimieren")
	check(Fenster.vollbild_grund({ "fg_game": false, "target_iconic": true }, d, d) == "minimiert", "Spiel liegt minimiert (Alt+Tab): Guide deckend")
	# Hat das Minimieren gewirkt? Sonst läge der Guide unsichtbar hinter dem Vollbild.
	check(Fenster.weg_urteil({ "target_iconic": true, "fg_game": true, "quns": 3 }, 100, false, 7) == "weg", "minimiert: aus dem Weg")
	# Alt+Tab aus dem Vollbild-Video: Nur ein fremdes Programm vorn lässt das Video zurücktreten.
	check(Fenster.video_soll_weichen({ "fg_hwnd": 50, "fg_pid": 400 }, 7, 90) and Fenster.video_soll_weichen({ "fg_hwnd": 50, "fg_pid": 400, "fg_shell": true }, 7, 0),
			"Video: anderes Programm oder Desktop vorn – weichen")
	check(not Fenster.video_soll_weichen({ "fg_hwnd": 50, "fg_pid": 7 }, 7, 90) and not Fenster.video_soll_weichen({ "fg_hwnd": 51, "fg_pid": 90 }, 7, 90),
			"Video: Uzai oder mpv vorn – bleibt")
	check(not Fenster.video_soll_weichen({ "fg_hwnd": 0, "fg_pid": 0 }, 7, 90) and not Fenster.video_soll_weichen({}, 7, 90), "Video: unbekannt, wer vorn liegt – bleibt")
	check(Fenster.weg_urteil({ "fg_pid": 7, "quns": 5, "fg_game": false }, 200, false, 7) == "weg", "Uzai vorn, kein D3D-Vollbild mehr: aus dem Weg")
	check(Fenster.weg_urteil({ "fg_pid": 7, "quns": 3, "fg_game": false }, 200, false, 7) == "warten", "Windows meldet noch D3D-Vollbild: warten")
	check(Fenster.weg_urteil({ "fg_game": true, "quns": 3, "fg_pid": 99 }, 200, false, 7) == "warten", "Spiel noch vorn, früh: warten")
	check(Fenster.weg_urteil({ "fg_game": true, "quns": 3, "fg_pid": 99 }, Fenster.WEG_NOCHMAL_MS, false, 7) == "nochmal", "nach 0,7 s: einmal neu bitten")
	check(Fenster.weg_urteil({ "fg_game": true, "quns": 3, "fg_pid": 99 }, Fenster.WEG_NOCHMAL_MS + 300, true, 7) == "warten", "nur einmal neu bitten")
	check(Fenster.weg_urteil({ "fg_game": true, "quns": 3, "fg_pid": 99 }, Fenster.WEG_MS, true, 7) == "aufgeben", "nach 1,6 s: aufgeben, Guide zu")
	check(Fenster.weg_urteil({}, Fenster.WEG_MS, true, 7) == "aufgeben" and Fenster.weg_urteil({}, 100, false, 7) == "warten", "ohne Antwort des Helfers: warten, am Ende aufgeben")
	# Starb das Spiel am Wechsel? Dann bleibt es künftig im Vollbild in Ruhe.
	check(Fenster.guide_tod(900, false) and Fenster.guide_tod(Fenster.TOD_MS, false), "Ende kurz nach dem Wechsel: lag am Guide")
	check(not Fenster.guide_tod(900, true), "über Uzai beendet: kein Absturz durch den Guide")
	check(not Fenster.guide_tod(Fenster.TOD_MS + 1, false) and not Fenster.guide_tod(-1, false), "lange danach oder ohne Wechsel: nicht")
	check(not Fenster.guide_vollbild_geht("d3d", "nie", 0) and not Fenster.guide_vollbild_geht("aufloesung", "", Fenster.WEG_FEHL_MAX),
			"gemerkt oder zweimal nicht minimiert: die Guide-Taste lässt das Spiel in Ruhe")
	check(Fenster.guide_vollbild_geht("d3d", "", 1) and Fenster.guide_vollbild_geht("minimiert", "nie", 5) and Fenster.guide_vollbild_geht("", "nie", 5),
			"sonst geht der Guide; liegt das Spiel schon minimiert oder im Fenster, immer")
	check(Fenster.vollbild_grund({ "fg_game": true, "quns": 0, "fg_full": true }, Vector2i.ZERO, Vector2i(1920, 1080)) == "", "ohne gemerkten Bildschirm keine Vermutung")
	var zeile: String = Fenster.vollbild_text("aufloesung", d, Vector2i(1920, 1080))
	check(Fenster.vollbild_text("d3d", d, d).begins_with("Guide über exklusivem Vollbild") and zeile.contains("1920×1080 statt 2560×1440"),
			"klare Zeilen in launch.log")
	var mg := FileAccess.get_file_as_string("res://src/main_guide.gd")
	var tg := mg.substr(mg.find("func toggle_guide("), 9000)
	check(tg.find("await _vollbild_pruefen()") >= 0 and tg.find("await _vollbild_pruefen()") < tg.find("_enter_overlay(true)")
			and tg.find("_spiel_kurz_weg(grund)") > tg.find("_enter_overlay(true)"), "Guide: erst prüfen, dann deckend, dann Spiel minimieren")
	var gc := mg.substr(mg.find("func _on_guide_closed("), 3000)
	check(gc.contains("_spiel_zurueck()") and gc.find("if _spiel_minimiert:") < gc.find("_leave_overlay()\n\t\tawait Launcher.hide_filter(false)"), "Guide zu: Spiel zurück nach vorn (vor dem Wegräumen)")
	var fe := FileAccess.get_file_as_string("res://src/main_fenster.gd")
	var fw := fe.substr(fe.find("func fokus_wechsel("), 1600)
	check(fw.contains("w.always_on_top = false") and fw.contains("_oben_abgegeben") and fw.contains("_alt_tab_zu_uzai()"),
			"Alt+Tab: Uzai gibt „immer oben“ ab, leeres Uzai öffnet den Guide")
	check(FileAccess.get_file_as_string("res://src/main.gd").contains("fokus_wechsel(what == NOTIFICATION_APPLICATION_FOCUS_IN)"), "main meldet jeden Fokuswechsel")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var fo := ps.substr(ps.find("    public static bool Focus(IntPtr h) {"), 1600)
	check(fo.contains("ShowWindowAsync(h, 9)") and not fo.contains("BringWindowToTop(h)") and fo.contains("Antwortet(fgw, 150)"),
			"Helfer: Fokus wartet nie auf ein beschäftigtes Spiel")
	check(ps.contains("[UzLive]::FocusBounded($h.ToInt64(), 1200)") and ps.contains("'spiel-minimieren' {") and ps.contains("quns = [UzWin]::Quns()"),
			"Helfer: Fokus mit Zeitgrenze, Minimieren nur des Spielfensters, Vollbild-Zustand")
	check(not ps.substr(ps.find("'spiel-minimieren' {"), 700).contains("keybd_event"), "Minimieren ohne Tastendruck")
	var ic := FileAccess.get_file_as_string("res://src/core/icons.gd")
	check(ic.contains("Arbeit.los(_rastern.bind(t, name, size), Arbeit.SOFORT)") and ic.contains("_fertig.call_deferred(t, img)"), "Symbole im Hintergrund gerastert (kein Ruckler beim Öffnen)")
	var gd := FileAccess.get_file_as_string("res://src/ui/layers/guide.gd")
	check(gd.contains("get_tree().process_frame.connect(_inhalt_bauen, CONNECT_ONE_SHOT)"), "Guide baut gestaffelt (Leiste, dann Inhalt)")

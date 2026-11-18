extends Node
## Einrichtung beim ersten Start (src/core/einrichtung.gd): wann sie kommt (neue Nutzer ja,
## bestehende nie), wo sie nach einem Neustart weitergeht, welche Schritte es gibt, „Später“ und
## „Zurück“, die Zusammenfassung und das Suchen nach Emulatoren und Spieleordnern. Aufruf:
##   godot --headless --path . res://tests/logic_einrichtung.tscn   → „Ergebnis: alles ok“

const E := preload("res://src/core/einrichtung.gd")
const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const Koppeln := preload("res://src/core/koppeln.gd")
const HelperScript := preload("res://src/core/helper.gd")
const Quelle := preload("res://tests/quelle.gd")
const Zustand := preload("res://src/core/zustand.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Bestehende Nutzer erkennen")
	var fresh := { "first_run": true, "accounts": Config.DEFAULTS.accounts.duplicate(true), "rom_dirs": {}, "pc_dirs": [], "last_game": "", "played": 0 }
	check(not E.is_existing_user(fresh), "frische Einstellungen: neu")
	check(not E.is_existing_user({}), "gar nichts bekannt: neu")
	check(E.is_existing_user({ "first_run": false }), "Willkommen kam schon einmal (first_run aus): bestehend")
	var acc := fresh.duplicate(true)
	acc.accounts["sgdb_key"] = "abc"
	check(E.is_existing_user(acc), "SteamGridDB-Schlüssel eingetragen: bestehend")
	var acc2 := fresh.duplicate(true)
	acc2.accounts["discord_servers"] = []
	acc2.accounts["epic_refresh"] = "  "
	check(not E.is_existing_user(acc2), "leere Liste und Leerzeichen zählen nicht")
	check(E.is_existing_user({ "first_run": true, "rom_dirs": { "ps2": "D:/ROMs/ps2" } }), "Spieleordner eingetragen: bestehend")
	check(not E.is_existing_user({ "first_run": true, "rom_dirs": { "ps2": "" } }), "leerer Spieleordner zählt nicht")
	check(E.is_existing_user({ "first_run": true, "pc_dirs": ["C:/Spiele"] }), "PC-Ordner: bestehend")
	check(E.is_existing_user({ "first_run": true, "last_game": "steam:570" }), "zuletzt gespielt: bestehend")
	check(E.is_existing_user({ "first_run": true, "played": 3 }), "Spielzeit in der Bibliothek: bestehend")
	check(E.is_existing_user({ "first_run": true, "nuvio": true }), "Nuvio angemeldet: bestehend")
	check(E.is_existing_user({ "first_run": true, "youtube_refresh": "x" }), "YouTube angemeldet: bestehend")

	print("Wann die Einrichtung kommt")
	check(E.start_mode({}, fresh) == "neu", "neuer Nutzer: von vorn")
	check(E.start_mode({ "done": true }, fresh) == "", "fertig: nicht noch einmal")
	check(E.start_mode({ "done": true }, { "first_run": false }) == "", "bestehender Nutzer, fertig oder abgebrochen: nie wieder")
	check(E.start_mode({ "done": true, "skipped": ["spiele", "konten"] }, { "first_run": false }) == "",
			"in einer älteren Fassung bewusst übersprungen: nie wieder")
	check(E.start_mode({ "step": "konten" }, fresh) == "weiter", "angefangen: weiter")
	check(E.start_mode({ "step": "konten" }, { "first_run": false }) == "weiter", "aus den Einstellungen neu gestartet und nicht fertig: weiter")
	check(E.start_mode({ "step": "konten", "done": true }, fresh) == "", "fertig schlägt den gespeicherten Schritt")
	check(E.start_mode({}, fresh, true) == "" and E.start_mode({ "step": "konten" }, fresh, true) == "", "Vorführmodus: nie")
	# Onboarding that was never completed must not silently disappear: an interrupted one continues,
	# otherwise it is offered again.
	check(E.start_mode({ "started": 1760000000 }, { "first_run": false }) == "weiter",
			"angefangen, nur der Beginn gespeichert (Absturz vor dem ersten Schritt): weiter")
	check(E.start_mode({}, { "first_run": false }) == "anbieten", "benutzt Uzai, nie abgeschlossen: angeboten (mit Abbrechen)")
	check(E.start_mode({}, acc) == "anbieten", "schon ein Konto, nie abgeschlossen: angeboten")
	check(E.existing_reason(fresh) == "" and E.existing_reason({ "first_run": false }) == "Uzai lief schon"
			and E.existing_reason(acc) == "Konto sgdb_key" and E.existing_reason({ "first_run": true, "played": 2 }) == "Spielzeit in Uzai",
			"Grund für „bestehend“ (fürs Protokoll, ohne Daten)")
	check(E.start_grund({}, fresh) == "Einrichtung neu (erster Start)", "Protokoll: neu")
	check(E.start_grund({ "step": "konten" }, fresh).contains("„konten“") and E.start_grund({ "started": 5 }, fresh).contains("weiter"), "Protokoll: weiter, wo")
	check(E.start_grund({}, acc).contains("angeboten") and E.start_grund({}, acc).contains("Konto sgdb_key") and not E.start_grund({}, acc).contains("abc"),
			"Protokoll: angeboten mit Grund, ohne den Schlüssel selbst")
	check(E.start_grund({ "done": true }, fresh) == "keine Einrichtung (fertig)" and E.start_grund({ "done": true, "skipped": ["x"] }, fresh).contains("übersprungen")
			and E.start_grund({}, fresh, true).contains("Vorführung"), "Protokoll: fertig, übersprungen, Vorführung")

	print("Schritte")
	var all := E.steps_for({ "extras": ["lossless"], "accounts": ["steam"] })
	check(all == E.STEPS, "alle Schritte (%s)" % str(all))
	check(not E.steps_for({ "extras": ["x"], "accounts": ["steam"], "show": ["guide"] }).has("zimmer"), "Szene, die es nicht gibt, fällt weg")
	var no_ex := E.steps_for({ "extras": [], "accounts": ["steam"] })
	check(not no_ex.has("extras") and no_ex.size() == E.STEPS.size() - 1, "ohne Zusatzfunktionen fällt „Extras“ weg")
	check(not E.steps_for({ "extras": ["x"], "accounts": [] }).has("konten"), "ohne Konten fällt „Konten“ weg")
	check(no_ex[0] == "willkommen" and no_ex[no_ex.size() - 1] == "fertig", "Willkommen vorn, Fertig hinten")
	check(E.extras_for({ "lossless": true, "clips": true, "ruhemodus": false }) == ["lossless", "clips"], "nur Zusatzfunktionen, die es gibt (Reihenfolge fest)")
	check(E.extras_for({}).is_empty(), "keine Zusatzfunktion: leer")

	print("Weitermachen nach einem Neustart")
	check(E.resume_index("", all) == 0, "nichts gespeichert: erster Schritt")
	check(E.resume_index("spiele", all) == all.find("spiele"), "gespeicherter Schritt")
	check(E.resume_index("extras", no_ex) == no_ex.find("fertig"), "Schritt gibt es nicht mehr: der nächste danach")
	check(E.resume_index("quatsch", all) == 0, "unbekannter Schritt: von vorn")
	check(E.resume_index("fertig", no_ex) == no_ex.size() - 1, "Fertig bleibt Fertig")
	# Gespeichert in einer älteren Einrichtung (bis 0.14): weiter beim nächsten Schritt, den es gibt.
	var kurz0 := E.steps_for({ "extras": ["lossless"], "accounts": ["steam"] }, false)
	check(E.resume_index("darstellung", kurz0) == kurz0.find("spiele"), "alt „Aussehen“ (jetzt freiwillig): weiter bei Spiele")
	check(E.resume_index("guide", kurz0) == kurz0.find("guide"), "Guide (war freiwillig): jetzt im Hauptweg")
	check(E.resume_index("zimmer", kurz0) == kurz0.find("zimmer"), "Zimmer (war freiwillig): jetzt in der Vorstellung")
	check(E.resume_index("darstellung", all) == all.find("darstellung"), "gespeicherte Schritte der neuen Folge")
	# Bis 0.16 gab es Controller, Freunde und Das kann Uzai als eigene Schritte (ERSATZ).
	check(E.resume_index("controller", kurz0) == kurz0.find("spiele") and E.resume_index("controller", all) == all.find("spiele"),
			"alt „Controller“ (jetzt still erkannt): weiter bei Spiele, auch mit den freiwilligen Schritten")
	check(E.resume_index("freunde", kurz0) == kurz0.find("konten") and E.resume_index("freunde", all) == all.find("konten"),
			"alt „Freunde“: weiter bei Konten (Steam und Discord stehen dort)")
	check(E.resume_index("besonders", kurz0) == kurz0.find("fertig") and E.resume_index("besonders", all) == all.find("darstellung"),
			"alt „Das kann Uzai“: weiter bei Bereit bzw. beim ersten freiwilligen Schritt")
	var ohne_konten := E.steps_for({ "extras": [], "accounts": [] }, false)
	check(E.resume_index("freunde", ohne_konten) == ohne_konten.find("zimmer"),
			"alt „Freunde“ ohne Konten: weiter mit der Vorstellung (Zimmer, %s)" % str(ohne_konten))
	check(E.resume_index("", kurz0) == 0 and E.resume_index("unbekannt_alt", kurz0) == 0, "leer oder unbekannt: von vorn")
	check(E.STEPS.all(func(x: String) -> bool: return E.FOLGE_ALT.has(x)), "FOLGE_ALT kennt jeden Schritt")
	check(E.ERSATZ.keys().all(func(x: String) -> bool: return not E.STEPS.has(x) and E.FOLGE_ALT.has(x)), "ERSATZ nur für Schritte, die es nicht mehr gibt")
	check(not E.STEPS.has("controller") and not E.STEPS.has("freunde") and not E.STEPS.has("besonders"),
			"kein Controller-Test, kein Freunde-Schritt, keine Kacheln „Das kann Uzai“")
	check(E.STEPS.all(func(x: String) -> bool: return E.TITLES.has(x)), "jeder Schritt hat einen Titel")

	print("Weiter und Zurück (kein Später, kein Überspringen)")
	var i_sp := all.find("spiele")
	var st := E.advance({ "skipped": [] }, all, i_sp, "weiter")
	check(int(st.index) == i_sp + 1 and str(st.step) == "emulatoren", "Weiter geht weiter (zu den Emulatoren)")
	check((st.skipped as Array).is_empty(), "und merkt sich nichts als übersprungen")
	var st_alt := E.advance({ "skipped": ["spiele"] }, all, i_sp, "weiter")
	check(not (st_alt.skipped as Array).has("spiele"), "aus einer älteren Fassung übersprungen: Weiter nimmt es heraus")
	var st3 := E.advance({ "skipped": ["spiele"] }, all, i_sp, "zurück")
	check(int(st3.index) == i_sp - 1 and (st3.skipped as Array) == ["spiele"], "Zurück ändert nichts")
	check(int(E.advance({}, all, 0, "zurück").index) == 0, "am Anfang bleibt Zurück stehen")
	check(int(E.advance({}, all, all.size() - 1, "weiter").index) == all.size() - 1, "am Ende bleibt Weiter stehen")
	var bau := Quelle.lesen("res://src/ui/layers/setup_wizard.gd")
	check(not bau.contains("_go(\"später\")") and not bau.contains("[\"y\", \"Später\"]") and not bau.contains("\"Überspringen\"")
			and not bau.contains("U.button(\"Später\"") and not bau.contains("su:spaeter") and not bau.contains("su:skip"),
			"in der ganzen Einrichtung kein „Später“ und kein „Überspringen“ (weder Knopf noch Y)")
	check(bau.contains("func _knopf(") and bau.contains("return U.button(text, icon_name, \"normal\")") and not bau.contains("\"primary\")")
			and not bau.contains(", \"flat\")"), "alle Knöpfe der Einrichtung im selben ruhigen Stil (gewählt hell, kein Hauptknopf im Akzent)")
	check(bau.contains("return \"Schließen\" if restart else \"—\""), "B im ersten Schritt: nur aus den Einstellungen schließt es, sonst nichts")

	print("Zusammenfassung")
	var sm := E.summary({ "pad": "Xbox Wireless Controller", "preset": "Tiefsee", "accent_own": true,
		"games": { "steam": 40, "epic": 2, "emu": 0 }, "accounts": ["Steam", "Discord"], "extras": ["Guide weckt Uzai"], "skipped": [] })
	check(sm.size() == 5, "fünf Zeilen")
	check(sm[0] == ["Controller", "Xbox Wireless Controller", true], "Controller mit Namen")
	check(str(sm[1][1]) == "Tiefsee mit eigener Akzentfarbe", "Darstellung mit eigenem Akzent")
	check(str(sm[1][0]) == "Aussehen" and str(sm[1][0]) == str(E.TITLES.darstellung), "Zeile heißt wie der Schritt: Aussehen")
	check(str(sm[2][1]) == "42 Spiele · Steam 40 · Epic 2" and bool(sm[2][2]), "Spiele gezählt, nur Quellen mit Spielen")
	check(str(sm[3][1]) == "Steam, Discord", "verbundene Konten")
	var sm2 := E.summary({ "pad": "", "games": {}, "accounts": [], "extras": [], "has_extras": false })
	check(sm2[0] == ["Controller", "Tastatur", false], "ohne Controller: Tastatur")
	check(str(sm2[2][1]) == "Noch keine gefunden" and not bool(sm2[2][2]), "keine Spiele: „Noch keine gefunden“")
	check(str(sm2[3][1]) == "Nicht verbunden" and not bool(sm2[3][2]), "keine Konten: „Nicht verbunden“ (kein „Übersprungen“)")
	check(sm2.size() == 4, "ohne Zusatzfunktionen keine Extras-Zeile")
	check(str(E.summary({ "games": { "steam": 1 } })[2][1]) == "1 Spiel · Steam 1", "Einzahl")

	print("Höhepunkt und Ende")
	check(E.bilanz({ "games": { "steam": 40, "epic": 2, "emu": 17 }, "pad": "Xbox Wireless Controller", "accounts": ["Steam", "Discord"] })
			== "59 Spiele · Xbox Wireless Controller · 2 Konten", "eine Zeile am Ende: Spiele, Controller, Konten")
	check(E.bilanz({ "games": { "pc": 1 }, "accounts": ["Steam"] }) == "1 Spiel · Steam", "Einzahl, ein Konto mit Namen, ohne Controller")
	check(E.bilanz({}) == "", "nichts bekannt: leer")
	check(E.bilanz({ "games": { "steam": 3 } }, func(x: String) -> String: return x.replace("Spiele", "games")) == "3 games", "Muster übersetzbar")
	check([0, 1, 2, 3, 4, 5].map(func(i: int) -> int: return E.regal_platz(i)) == [0, 1, -1, 2, -2, 3], "Regal füllt sich von der Mitte nach außen")
	var q := E.quellen([["steam", "Steam", 7], ["epic", "Epic", 0], ["pc", "PC", 1]], [["gba", "GBA", 3], ["ps2", "PS2", 12], ["snes", "SNES", 3]], 4)
	check(q.map(func(x: Dictionary) -> String: return str(x.id)) == ["steam", "pc", "ps2", "gba"],
			"Schilder: Launcher in ihrer Folge, dann Systeme nach Zahl, nur mit Spielen, höchstens 4 (%s)" % str(q))
	var z := Vector2.ZERO
	var bilder := 0
	var monoton := true
	while z.x < 59.0 and bilder < 600:
		var vor := z.x
		z = E.zaehlen(z.x, z.y, 59.0, 1.0 / 60.0)
		monoton = monoton and z.x >= vor and z.x <= 59.0
		bilder += 1
	check(monoton and z.x == 59.0, "Zähler läuft hoch, nie zurück, nie über das Ziel")
	check(bilder > 40 and bilder < 150, "und braucht dafür ein bis zwei Sekunden (%d Bilder)" % bilder)
	check(E.zaehlen(10.0, 0.0, 59.0, 5.0) == Vector2(59.0, 0.0), "großer Zeitsprung: genau am Ziel")

	print("Emulatoren suchen")
	var roots := E.emu_roots(["C:", "D:"],
			{ "USERPROFILE": "C:\\Users\\Ana", "ProgramFiles": "C:\\Program Files", "LOCALAPPDATA": "C:\\Users\\Ana\\AppData\\Local" })
	check(roots.has("C:/Emulatoren") and roots.has("D:/Emulators") and roots.has("C:/Users/Ana/Emulatoren"),
			"übliche Orte auf allen Laufwerken und im Benutzerordner")
	check(roots.has("C:/Program Files") and roots.has("C:/Users/Ana/AppData/Local/Programs"), "Programme-Ordner (mit Schrägstrichen)")
	check(roots.size() == E._unique(roots).size(), "keine Doppelten")
	var pcsx2 := { "id": "pcsx2", "name": "PCSX2", "exe_hint": "C:/Emulatoren/PCSX2/pcsx2-qt.exe" }
	var cands := E.emu_candidates(pcsx2, ["D:/Emulators"])
	check(cands[0] == "C:/Emulatoren/PCSX2/pcsx2-qt.exe", "zuerst exe_hint")
	check(cands.has("D:/Emulators/PCSX2/pcsx2-qtx64-avx2.exe"), "andere Programmnamen derselben Familie")
	var ra := E.emu_candidates({ "id": "retroarch", "name": "RetroArch", "exe_hint": "C:/RetroArch/retroarch.exe" }, [], ["E:/SteamLibrary"])
	check(ra.has("E:/SteamLibrary/steamapps/common/RetroArch/retroarch.exe"), "RetroArch aus der Steam-Bibliothek")
	check(E.emu_candidates({ "id": "x", "name": "", "exe_hint": "" }, ["C:/E"]).is_empty(), "ohne Namen und Hinweis: nichts raten")

	print("Spieleordner erkennen")
	var systems: Array = Config.systems()
	check(E.system_for_dir("ps2", systems) == "ps2", "ps2")
	check(E.system_for_dir("PS2", systems) == "ps2", "PS2 (Kurzname)")
	check(E.system_for_dir("PlayStation 2", systems) == "ps2", "PlayStation 2 (Name)")
	check(E.system_for_dir("psx", systems) == "ps1", "psx → PS1 (EmuDeck/RetroBat)")
	check(E.system_for_dir("gamecube", systems) == "gc", "gamecube → GC")
	check(E.system_for_dir("Genesis", systems) == "megadrive", "Genesis → Mega Drive")
	check(E.system_for_dir("Game Boy Advance", systems) == "gba", "Game Boy Advance")
	check(E.system_for_dir("Urlaubsfotos", systems) == "", "fremder Ordner: kein System")
	check(E.system_for_dir("", systems) == "", "leer: kein System")
	var tree := { "D:/ROMs": ["ps2", "gba", "Fotos", "PS2"], "E:/Emulation/roms": ["snes", "gba"] }
	var lister := func(p: String) -> Array: return tree.get(p, [])
	var found := E.find_rom_dirs(["D:/ROMs", "E:/Emulation/roms"], systems, lister)
	var by := {}
	for f in found:
		by[f.system] = f.dir
	check(by.size() == 3 and by.ps2 == "D:/ROMs/ps2" and by.gba == "D:/ROMs/gba" and by.snes == "E:/Emulation/roms/snes",
			"Unterordner pro System, jedes nur einmal (%s)" % str(by))
	var found2 := E.find_rom_dirs(["D:/ROMs"], systems, lister, { "ps2": true })
	check(found2.size() == 1 and found2[0].system == "gba", "schon eingetragene Systeme bleiben, wie sie sind")
	var cl := E.classify_folder("D:/ROMs", ["ps2", "gba"], systems, {})
	check(cl.kind == "unterordner" and (cl.list as Array).size() == 2, "gewählter Ordner mit Unterordnern: alle")
	var cl2 := E.classify_folder("D:/Spiele/GBA", [], systems, { "gba": 12, "gb": 3 })
	check(cl2.kind == "ein_system" and cl2.system == "gba" and int(cl2.count) == 12, "ein Ordner: System mit den meisten Dateien")
	check(E.classify_folder("D:/leer", [], systems, {}).system == "", "nichts Passendes: fragen ohne Vorschlag")

	print("Echte Dateien (Suche wie im Assistenten)")
	var base := OS.get_cache_dir().path_join("uzai-einrichtung-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base.path_join("Emulatoren/PCSX2"))
	DirAccess.make_dir_recursive_absolute(base.path_join("ROMs/ps2"))
	DirAccess.make_dir_recursive_absolute(base.path_join("ROMs/gba"))
	_touch(base.path_join("Emulatoren/PCSX2/pcsx2-qtx64-avx2.exe"))
	_touch(base.path_join("ROMs/ps2/Okami.iso"))
	_touch(base.path_join("ROMs/ps2/Ico.chd"))
	var emus: Array = []
	for e in Config.emulators():
		emus.append({ "id": str(e.id), "name": str(e.get("name", "")), "exe_hint": str(e.get("exe_hint", "")), "systems": e.get("systems", []) })
	var res: Dictionary = Wizard._find_all([base], {}, systems, emus, [], {})
	var emu_ids: Array = (res.emus as Array).map(func(x): return str(x.id))
	check(emu_ids == ["pcsx2"], "PCSX2 gefunden, sonst nichts (%s)" % str(emu_ids))
	check(str(res.emus[0].exe).ends_with("PCSX2/pcsx2-qtx64-avx2.exe") if not (res.emus as Array).is_empty() else false, "mit dem echten Programmnamen")
	check((res.dirs as Array).size() == 1 and str(res.dirs[0].system) == "ps2" and int(res.dirs[0].count) == 2, "nur Ordner mit Spielen (ps2 mit 2, gba leer)")
	var res2: Dictionary = Wizard._find_all([base.path_join("gibtsnicht")], {}, systems, emus, [], {})
	check((res2.emus as Array).is_empty() and (res2.dirs as Array).is_empty(), "Laufwerk ohne passende Ordner: nichts")

	print("Einstellungen und Einstieg")
	check(Wizard.start_mode() == "neu", "frischer Datenordner: Einrichtung kommt")
	Config.set_value("einrichtung.step", "darstellung")
	check(Wizard.start_mode() == "weiter", "angefangen: geht weiter")
	var steps := E.steps_for(Wizard.features())
	check(E.resume_index(str(Config.get_value("einrichtung.step", "")), steps) == steps.find("darstellung"), "an der gespeicherten Stelle")
	Config.set_value("einrichtung.done", true)
	check(Wizard.start_mode() == "", "fertig: nicht mehr")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.step", "")
	Config.set_value("einrichtung.started", 0)
	Config.set_value("system.first_run", false)
	check(Wizard.start_mode() == "anbieten", "bestehender Nutzer (first_run aus), nie abgeschlossen: angeboten")
	Config.set_value("einrichtung.started", 1760000000)
	check(Wizard.start_mode() == "weiter", "Beginn gespeichert, Schritt fehlt: weiter")
	Config.set_value("einrichtung.done", true)
	check(Wizard.start_mode() == "", "bestehender Nutzer, fertig: nie wieder")
	Wizard.start_protokoll()
	Wizard.protokoll("Schritt: konten")
	# Ende und Abbruch schreiben aus der Schicht darunter (setup_wizard_bausteine.gd) über call().
	var wz = Wizard.new()
	wz.call("protokoll", "Fertig")
	wz.free()
	var elog := FileAccess.get_file_as_string(Config.path("logs/einrichtung.log"))
	check(elog.contains("Start: keine Einrichtung (fertig)") and elog.contains("Schritt: konten") and elog.contains("Fertig"),
			"logs/einrichtung.log: Start mit Grund, Schritte, Ende")
	Config.set_value("einrichtung.done", false)
	Config.set_value("einrichtung.started", 0)
	var feats: Dictionary = Wizard.features()
	var has_rest := (Config.DEFAULTS.get("controller", {}) as Dictionary).has("guide_hold")
	check((feats.extras as Array).has("ruhemodus") == has_rest, "Ruhemodus nur, wenn es ihn gibt (%s)" % str(has_rest))
	check((feats.extras as Array).has("clips") == (Config.DEFAULTS.system.has("clip_keys") or Config.DEFAULTS.has("capture")), "Aufnahmen nur, wenn es sie gibt")
	check((feats.extras as Array).has("background_wake") and (feats.extras as Array).has("lossless"), "Lossless Scaling und Wecken über die Guide-Taste gibt es")
	var main_src := Quelle.lesen("res://src/main.gd")
	check(main_src.contains("SetupWizard.start_mode()") and main_src.contains("SetupWizard.open_for(self, setup == \"anbieten\")")
			and main_src.contains("SetupWizard.start_protokoll()"),
			"main startet die Einrichtung nach dem Einschalten (angeboten: mit Abbrechen), Grund ins Protokoll")
	var bs_src := Quelle.lesen("res://src/ui/layers/setup_wizard_bausteine.gd")
	check(bs_src.contains("call(\"protokoll\", \"Fertig\")") and Quelle.lesen("res://src/ui/layers/setup_wizard.gd").contains("Unterbrochen bei"),
			"Ende und Unterbrechung stehen im Protokoll")
	var set_src := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(set_src.contains("\"Einrichtung erneut starten\"") and set_src.contains("open_for(main, true)"), "Einstellungen → System → Einrichtung erneut starten")

	_kurz()
	_suche(base, systems, emus)
	_koppeln()
	_helfer()
	_schon()
	_szenen_inhalt()
	await _suche_ohne_seite(base, systems, emus)

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Szenen der Einrichtung nicht leer: echte Inhalte, sonst eigene Bilder; Logos nur zur Laufzeit.
func _szenen_inhalt() -> void:
	print("Szenen: Kacheln mit Bild, Emulatoren mit Zeichen")
	var Inhalt: GDScript = load("res://src/ui/components/einrichtung_inhalt.gd")
	var Logos: GDScript = load("res://src/core/badge_logos.gd")
	var liste: Array = Inhalt.emu_liste()
	check(liste.size() == Inhalt.MAX_SYSTEME and liste.all(func(e: Dictionary) -> bool: return str(e.emu_name) != "" and str(e.kurz) != ""),
			"Emulatoren: sechs Systeme, je mit Emulator und Kurznamen (eigene Sammlung zuerst, sonst die bekanntesten)")
	var emu_ids: Array = Config.emulators().map(func(e: Dictionary) -> String: return str(e.id))
	var keys: Array = Logos.LOGOS.keys().filter(func(k: String) -> bool: return k.begins_with("emu_"))
	check(keys.size() >= 10 and keys.all(func(k: String) -> bool: return emu_ids.has(k.substr(4))),
			"Emulator-Logos nur als Schlüssel für badge_logos (zur Laufzeit), jeder zu einem bekannten Emulator")
	var szene := Quelle.lesen("res://src/ui/components/einrichtung_szene.gd")
	var inhalt := Quelle.lesen("res://src/ui/components/einrichtung_inhalt.gd")
	check(szene.contains("Inhalt.bild(art)") and szene.contains("Inhalt.illu(") and inhalt.contains("\"game_texture\"")
			and inhalt.contains("\"shots_dir\"") and inhalt.contains("\"url_texture\""),
			"Medien-Kacheln: echte Inhalte (Cover, Bildschirmfoto, Albumcover, Poster), sonst eigene Bilder")
	check(szene.contains("Inhalt.silhouette(") and szene.contains("Inhalt.emu_zeichen(") and not szene.contains("_ico(\"disc\""),
			"Emulatoren: Logo oder eigene Silhouette statt leerer Karte, Zeichen je Emulator")
	check(not inhalt.contains("res://assets/") and not inhalt.contains("= load(") and not inhalt.contains("ResourceLoader"), "keine fremden Bilder im Projekt (alles gezeichnet oder zur Laufzeit)")
	# Emulators shown honestly: no staged loading, only the real state (otherwise it looked as if all emulators
	# were already being set up).
	var showsrc := Quelle.lesen("res://src/ui/layers/setup_wizard_show.gd")
	check(not szene.contains("EMU_LADE_AB") and not szene.contains("\"Eingerichtet\"") and not szene.contains("Offiziell geladen und geprüft")
			and szene.contains("func stand(liste: Array)") and szene.contains("\"angebot\": [\"Kann geladen werden\"")
			and showsrc.contains("sz.call(\"stand\", _emu_stand())") and showsrc.contains("_retro_offer(rows, retro)"),
			"Emulatoren: erkannt, angeboten oder ladend – nur echt, Laden erst nach Zustimmung (Retro einrichten)")
	var SzeneS: GDScript = load("res://src/ui/components/einrichtung_szene.gd")
	var sz0: Control = SzeneS.new().setup("emulatoren", Vector2.ZERO)
	check(not sz0.leer(), "vor dem ersten Stand: nicht leer (Beispiel-Systeme)")
	sz0.stand([])
	check(sz0.leer() and (sz0.get("_emus") as Array).is_empty() and (sz0.get("_emu_stand") as Array).is_empty(),
			"ohne Emulator-Spiele: leerer Zustand, keine Beispiel-Karten und keine erfundene Liste")
	check(szene.contains("func _emu_leer()") and szene.contains("\"Keine Retro-Spiele gefunden\"") and szene.contains("if leer():\n\t\t_emu_leer()"),
			"ohne Emulator-Spiele: ruhig „Keine Retro-Spiele gefunden“ statt eines leeren Felds")
	var emu_src := showsrc.substr(showsrc.find("func _szene_emulatoren()"), showsrc.find("func _retro_fehlt_lage()") - showsrc.find("func _szene_emulatoren()"))
	check(emu_src.contains("var leer := _emu_stand().is_empty()") and emu_src.contains("if leer:\n\t\t\t_folder_row(rows)")
			and emu_src.contains("_default = _fuss_mitte(col)"),
			"ohne Emulator-Spiele: „Ordner hinzufügen …“ (derselbe Weg wie bei den Spielen), „Weiter“ gewählt")
	var spsrc := Quelle.lesen("res://src/ui/layers/setup_wizard_spiele.gd")
	check(spsrc.contains("if p != \"\" and str(_find.get(\"state\", \"\")) == \"\":") and spsrc.contains("\"applied\": true }"),
			"Ordner hinzufügen geht auch ohne Suche in dieser Einrichtung (Funde gleich übernommen)")
	# Spiele ohne Funde: keine leere Reihe, keine leeren Schilder, eine ruhige Zeile.
	check(Wizard.spiele_leer(true, 0) and not Wizard.spiele_leer(false, 0) and not Wizard.spiele_leer(true, 3),
			"Spiele: leer nur, wenn die Suche fertig ist und nichts fand")
	check(spsrc.contains("_regal.visible = not leer") and spsrc.contains("_schilder.visible = not leer") and spsrc.contains("_leer_satz.visible = leer")
			and spsrc.contains("\"Uzai liest neue Spiele jederzeit ein.\""), "Spiele ohne Funde: Reihe und Schilder weg, ruhige Zeile")
	var fsrc := Quelle.lesen("res://src/ui/layers/setup_wizard.gd")
	check(fsrc.contains("if line == \"\":") and fsrc.contains("196 if not Library.visible_games().is_empty() else 0"),
			"Fertig ohne Spiele und Konten: keine leere Reihe, kein leerer Satz")
	sz0.stand([{ "sys": "ps2", "kurz": "PS2", "name": "PlayStation 2", "spiele": 3, "zustand": "angebot", "pct": 0.0, "emu": "pcsx2",
		"emu_name": "PCSX2", "farbe": Color.BLUE }])
	check((sz0.get("_emus") as Array).size() == 1 and str((sz0.get("_emus") as Array)[0].zustand) == "angebot",
			"mit Emulator-Spielen: nur die betroffenen Systeme, mit ihrem echten Zustand")
	sz0.free()
	var r := Rect2(0, 0, 200, 100)
	var pts: PackedVector2Array = Inhalt.rund(r, 20.0)
	check(pts.size() > 8 and Array(pts).all(func(p: Vector2) -> bool: return r.grow(0.01).has_point(p)), "gerundete Fläche bleibt im Rechteck")


func _touch(p: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("x")
	f.close()


# --- „In 2 Minuten fertig“ (Punkt 51) -----------------------------------------------------------

func _kurz() -> void:
	print("In 2 Minuten fertig: kurzer Weg, Freiwilliges am Ende")
	var feats := { "extras": ["lossless"], "accounts": ["steam"] }
	var kurz := E.steps_for(feats, false)
	check(kurz == ["willkommen", "du", "spiele", "emulatoren", "guide", "zimmer", "medien", "konten", "fertig"],
			"Hauptweg mit Vorstellung: Willkommen → Wer spielt? → Spiele → Emulatoren → Guide-Taste → Zimmer → Schauen & Hören → Konten → Bereit (%s)" % str(kurz))
	# „Wer spielt?“: Name und Farbe des Profils; „Fertig“ grüßt mit Namen, wenn einer gewählt ist.
	check(E.name_ist_standard("Spieler 1") and E.name_ist_standard("Player 2") and E.name_ist_standard("") and E.name_ist_standard("Spieler"),
			"„Spieler 1“, „Player 2“ und leer gelten als noch nicht benannt")
	check(not E.name_ist_standard("Robin") and not E.name_ist_standard("Spielerin Mia") and not E.name_ist_standard("Player One"),
			"ein eigener Name gilt, auch wenn er mit „Spieler“ beginnt")
	var gleich := func(t: String) -> String: return t
	check(E.fertig_titel("Robin", gleich) == "Alles bereit, Robin" and E.fertig_titel("Spieler 1", gleich) == "Alles bereit",
			"Fertig grüßt mit Namen, ohne eigenen Namen schlicht „Alles bereit“")
	check(E.fertig_titel("Ein sehr langer Name hier", gleich) == "Alles bereit", "langer Name: die große Zeile bleibt kurz")
	check(kurz.all(func(x: String) -> bool: return x not in E.MEHR) and E.SHOW.all(func(x: String) -> bool: return not E.MEHR.has(x)),
			"die Vorstellung steht im Hauptweg, freiwillig bleiben Aussehen und Extras")
	check(E.SHOW.all(func(x: String) -> bool: return kurz.find(x) > kurz.find("spiele") and kurz.find(x) < kurz.find("konten")),
			"Vorstellung nach den Spielen, vor den Konten")
	check(E.SHOW.all(func(id: String) -> bool: return E.TITLES.has(id)), "jede Szene hat einen Titel")
	check(str(E.TITLES.willkommen) == "Sprache" and str(E.TITLES.darstellung) == "Aussehen" and str(E.TITLES.spiele) == "Spiele",
			"Schritte heißen Sprache, Aussehen, Spiele")
	var lang := E.steps_for(feats, true)
	check(lang.find("darstellung") > lang.find("konten") and lang.find("extras") < lang.find("fertig") and lang[lang.size() - 1] == "fertig",
			"auf Wunsch: Aussehen, Szenen und Extras nach den Konten, vor Fertig eingereiht (%s)" % str(lang))
	check(E.resume_index("extras", kurz) == kurz.find("fertig"), "Extras gemerkt, aber nicht eingereiht: weiter bei Fertig")
	check(E.timed_text(1000, 1102) == "In 1 Min. 42 s eingerichtet", "Zeit am Ende: %s" % E.timed_text(1000, 1102))
	check(E.timed_text(1000, 1045) == "In 45 Sekunden eingerichtet", "unter einer Minute")
	check(E.timed_text(0, 50) == "" and E.timed_text(1000, 1000 + E.TIMED_MAX_S + 1) == "" and E.timed_text(2000, 1000) == "",
			"unbekannt, unterbrochen oder Uhr verstellt: keine Zeit")
	check(str(E.summary({ "preset": "Tiefsee", "games": {} })[1][1]) == "Tiefsee", "eigenes Farbschema: sein Name")
	check(str(E.summary({ "preset": "", "games": {} })[1][1]) == "Graphit", "ohne eigene Wahl: das Aussehen der Marke")
	# Mehrere Profile: die Einrichtung gilt einmal für den PC (gemeinsame Einstellungen).
	var Prof: GDScript = load("res://src/core/profiles.gd")
	var parts: Array = Prof.split_settings(
			{ "einrichtung": { "done": true, "mehr": true, "started": 5, "pad": "Xbox" }, "system": { "first_run": false, "doktor_hint": false } })
	check(bool((parts[0] as Dictionary).get("einrichtung", {}).get("mehr", false)) and int(parts[0].einrichtung.started) == 5
			and not (parts[1] as Dictionary).has("einrichtung"), "Einrichtung (auch „mehr“, Beginn, Controller) gemeinsam für alle Profile")
	check(not bool(parts[0].system.first_run) and (parts[1] as Dictionary).system.has("doktor_hint"), "erster Start gemeinsam, Doktor-Hinweis je Profil")
	var wsrc := Quelle.lesen("res://src/ui/layers/setup_wizard.gd")
	check(wsrc.contains("E.steps_for(features(), bool(Config.get_value(\"einrichtung.mehr\", false)))") and wsrc.contains("func _go_mehr("),
			"Assistent: kurzer Weg, Konten/Extras vom Ende aus")
	check(wsrc.contains("func _set_language(") and wsrc.contains("Lang.apply(code)") and wsrc.contains("AUTO_TRANSLATE_MODE_DISABLED"),
			"Sprache im ersten Schritt, wirkt sofort, Sprachnamen unübersetzt")
	check(wsrc.contains("\"guide\": _szene_guide()") and wsrc.contains("\"zimmer\": _szene_zimmer()") and wsrc.contains("Zimmerszene.new()"),
			"Vorstellung: Szenen Guide und Zimmer (echtes 3D-Zimmer mit Figuren)")
	check(wsrc.contains("_skeleton(\"marke\", \"Die Guide-Taste\"") and wsrc.contains("func _vorstellung(title: String, sub: String"),
			"Guide-Taste: oben das U-Zeichen; Vorstellung ohne Symbole vor dem Titel")
	check(wsrc.contains("class _Marke extends Control") and wsrc.contains("BootM.phasen(") and wsrc.contains("BootM.zeichen(") and wsrc.contains("BootM.wort_unter("),
			"Willkommen: das Zeichen wie im Intro (ohne Kachel, gesperrte Wortmarke)")
	check(wsrc.contains("_szene_guide_halten(rows)") and wsrc.contains("E.setup_accounts(_accounts())") and wsrc.contains("not bool(a.get(\"needs_id\", false))")
			, "Konten: nur QR-Code und App (keine App-IDs)")
	check(wsrc.contains("const KONTO_GRUPPEN") and wsrc.contains("const KONTO_GROSS := [\"Steam\", \"Discord\"]") and wsrc.contains("E.spalten_verteilen(hoehen)")
			and wsrc.contains("class _Konto extends Control") and not wsrc.contains("func _gruppe_klappen("),
			"Konten: Steam und Discord groß obenauf, der Rest kompakt nach Bereichen mit Überschriften (kein Aufklappen)")
	# The smaller accounts below are centered and balanced: two columns as wide as the big tiles (same gap),
	# the hint row and "Weiter" centered.
	var ksrc := wsrc.substr(wsrc.find("func _konten()"), wsrc.find("func _konto_kachel(") - wsrc.find("func _konten()"))
	check(ksrc.contains("var spalten := U.hbox(int(KONTO_LUECKE))") and ksrc.contains("var gross := U.hbox(int(KONTO_LUECKE))")
			and ksrc.contains("_aside_d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER")
			and ksrc.contains("(sk.go.get_parent() as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER"),
			"Konten: Spalten so breit wie die Kacheln darüber, Hinweis und „Weiter“ mittig")
	var kh := Wizard.KONTO_KOPF_H
	var zh := 66.0
	var std := [["spiele", kh + 2 * zh], ["retro", kh + zh], ["musik", kh + zh], ["videos", kh + 2 * zh], ["filme", kh + zh]]
	var vt: Array = E.spalten_verteilen(std)
	var hoehe := func(ids: Array, gr: Array) -> float:
		var hsum := 0.0
		for g in gr:
			if ids.has(str(g[0])):
				hsum += float(g[1])
		return hsum
	check(vt.size() == 2 and (vt[0] as Array).size() + (vt[1] as Array).size() == 5 and str(vt[0][0]) == "spiele",
			"Verteilung: zwei Spalten, jeder Bereich genau einmal, Spiele links (%s)" % str(vt))
	check(absf(float(hoehe.call(vt[0], std)) - float(hoehe.call(vt[1], std))) <= zh,
			"Verteilung: beide Spalten etwa gleich hoch (%s)" % str(vt))
	var mit_server := std.duplicate(true)
	mit_server[4] = ["filme", kh + 2 * zh]
	var vs: Array = E.spalten_verteilen(mit_server)
	check(vs == [["spiele", "retro", "musik"], ["videos", "filme"]], "gleich gut ausgewogen: vorn | hinten bleibt zusammen (%s)" % str(vs))
	check(E.spalten_verteilen([]) == [[], []] and E.spalten_verteilen([["spiele", 100.0]]) == [["spiele"], []], "Verteilung: leer und ein Bereich")
	var kc := Wizard.new()
	var konten_titel: Array = kc._accounts().map(func(a: Dictionary) -> String: return str(a.title))
	var kg: Array = Wizard.KONTO_GRUPPEN.map(func(g: Array) -> String: return str(g[0]))
	var kgr := {}
	for ka in kc._accounts():
		kgr[str(ka.title)] = str(ka.group)
	check(kc._accounts().all(func(a: Dictionary) -> bool: return str(a.title) in Wizard.KONTO_GROSS or kg.has(str(a.group)))
			and str(kgr.get("RetroAchievements", "")) == "spiele" and str(kgr.get("Spotify", "")) == "musik" and str(kgr.get("YouTube", "")) == "videos"
			and str(kgr.get("Nuvio", "")) == "filme" and str(kgr.get("Plex", "")) == "filme" and str(kgr.get("Stremio", "")) == "filme",
			"jeder Dienst in seinem Bereich, jeder Bereich in einer Spalte")
	check(Wizard._st(false, "")[0] == "Nicht verbunden" and str(Wizard._st(true, "Ana")[0]).ends_with(" · Ana") and bool(Wizard._st(true, "Ana")[2]), "Stand ruhig: „Verbunden“ oder „Nicht verbunden“")
	kc.free()
	check(konten_titel.slice(0, 2) == ["Steam", "Discord"], "Steam und Discord stehen unter Konten ganz oben (%s)" % str(konten_titel))
	check(not wsrc.contains("_freunde()") and not wsrc.contains("_besonders()") and not wsrc.contains("_controller()") and not wsrc.contains("_PadView")
			and not wsrc.contains("class _Kachel") and not ResourceLoader.exists("res://src/ui/layers/setup_wizard_freunde.gd"),
			"Controller-Test, Freunde-Schritt und Kacheln sind ganz weg (kein toter Code)")
	check(wsrc.contains("Sfx.play(\"setup_step\", Klang.stufe_ton(") and wsrc.contains("Sfx.play(\"setup_found\"") and wsrc.contains("Sfx.play(\"setup_done\")")
			and wsrc.contains("Sfx.play(\"swell\""), "Klänge der Einrichtung: Schritt (aufsteigend), gefunden, fertig, Licht an")
	check(wsrc.contains("if str(_steps[_idx]) == \"guide\":") and wsrc.contains("_guide_gedrueckt()") and wsrc.contains("return false")
			and wsrc.contains("U.glyph(\"guide\""), "Guide-Taste: die echte Taste öffnet den Guide und zählt als ausprobiert")
	check(wsrc.contains("_buehne.feiern(") and wsrc.contains("set_mode"), "Bühne hinter den Schritten, Lichtschein am Ende")
	check(wsrc.contains("_buehne.aufloesen(ziele)") and wsrc.contains("str(n.get_meta(\"uz_flug\")).substr(2)")
			and Quelle.lesen("res://src/ui/layers/setup_wizard_bausteine.gd").contains("await _ausklang()"),
			"Ende: Cover landen auf der Startseite (uz_flug), dann geht die Ebene")
	check(wsrc.contains("call(\"aufbauen\", true, ziele.keys())") and wsrc.contains("_buehne.aufloesen(ziele if flug else {}, abflug)")
			and wsrc.contains("await aufbau.bereit") and wsrc.contains("aufbau.call(\"gelandet\", id)"),
			"„Los“: Die Startseite baut sich auf, die Cover fliegen gestaffelt und übergeben beim Landen; die Ebene geht, wenn sie bereit ist")
	check(wsrc.contains("_default = sk.go") and wsrc.contains("_default = go"), "„Weiter“ ist gewählt: A geht durch die Einrichtung")
	check(not wsrc.contains("Alles geht auch später unter Einstellungen.") and not wsrc.contains("Schritt %d von %d"), "keine Erklärzeilen unter den Schritten")
	var bsrc := Quelle.lesen("res://src/ui/components/einrichtung_buehne.gd")
	check(bsrc.contains("U.spring_step(") and bsrc.contains("U.reduziert()") and not bsrc.contains("SCHNIPSEL"), "Bühne: Federn, ruhig ohne Flug, keine Schnipsel")
	check(bsrc.contains("material = U.entstuft()") and bsrc.contains("func _landen(") and bsrc.contains("call(\"glanz\")"),
			"Bühne: Lichter entstuft, Cover glänzen beim Landen")
	# Tiefe der Reihe: die Mitte groß, nach außen kleiner und nie überlappend; flach ohne Tiefe.
	var BuehneS: GDScript = load("res://src/ui/components/einrichtung_buehne.gd")
	var p0: Vector4 = BuehneS.buehne_platz(0, 140.0, 200.0, 20.0, BuehneS.TIEFE)
	var p1: Vector4 = BuehneS.buehne_platz(1, 140.0, 200.0, 20.0, BuehneS.TIEFE)
	var pm1: Vector4 = BuehneS.buehne_platz(-1, 140.0, 200.0, 20.0, BuehneS.TIEFE)
	var p2: Vector4 = BuehneS.buehne_platz(2, 140.0, 200.0, 20.0, BuehneS.TIEFE)
	var p9: Vector4 = BuehneS.buehne_platz(9, 140.0, 200.0, 20.0, BuehneS.TIEFE)
	check(p0 == Vector4(0, 0, 140, 200) and p1.z < p0.z and p2.z < p1.z and is_equal_approx(p1.x, -pm1.x), "Tiefe: zur Seite kleiner, symmetrisch")
	check(p1.x - p1.z * 0.5 >= p0.z * 0.5 + 1.0 and p2.x - p2.z * 0.5 >= p1.x + p1.z * 0.5 + 1.0, "Tiefe: Cover berühren sich nie")
	check(p9.z >= 140.0 * BuehneS.TIEFE_MIN - 0.01 and p2.y > 0.0 and p2.y < p2.w, "Tiefe: höchstens bis TIEFE_MIN, ferne leicht versetzt")
	check(BuehneS.buehne_platz(3, 140.0, 200.0, 20.0, 0.0) == Vector4(480, 0, 140, 200), "ohne Tiefe flach: gleiche Größe, gleiche Abstände")
	var usrc := Quelle.lesen("res://src/ui/u.gd")
	check(usrc.contains("render_mode blend_premul_alpha") and usrc.contains("uz_rauschen(FRAGCOORD.xy)"), "Entstufen: Rauschen nach dem Mischen (vormultipliziert)")
	check(bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding", false)), "Debanding im Projekt an (3D: Zimmer)")
	check(Quelle.lesen("res://src/ui/components/background.gd").contains("uz_rauschen(FRAGCOORD.xy)"), "Verläufe entstuft: background.gd")
	check(bsrc.contains("signal gelandet(") and bsrc.contains("_aufl_t < float(_abflug.get(") and bsrc.contains("node.modulate.a *= 1.0 - U.kurve(\"kreuzen\", (seit - U.NACH_WEG) / U.T_WEG)"),
			"Bühne: Cover warten auf ihren Abflug und kreuzen beim Landen mit dem echten Cover")
	# Startanimation: das U steht vor dem Namen; Lichtpunkte (Bühne der Einrichtung) fest gesät und nicht auf dem Zeichen.
	var Boot: GDScript = load("res://src/ui/boot.gd")
	check(float(Boot.phasen(Boot.BAND_AB + Boot.BAND_S).baender) == 1.0 and Boot.BAND_AB + Boot.BAND_S < Boot.NAME_AT, "U steht, bevor der Name kommt")
	var zr: Rect2 = Boot.zeichen_rect(Vector2(1920, 1080))
	check(zr.size.y >= 1080.0 * 0.35 and zr.size.y <= 1080.0 * 0.5, "Startbild: das U-Feld ist 35–50 %% der Bildhöhe (%.0f px)" % zr.size.y)
	check(absf(zr.get_center().y - 540.0) < 0.5 and zr.position.y > 0.0 and zr.end.y < 1080.0, "Startbild: U ohne Text mittig, passt ins Bild")
	var m1: Array = Boot.motes(20)
	check(m1 == Boot.motes(20) and m1.size() == 20 and Boot.motes(0).is_empty(), "Lichtpunkte: immer gleich, reduziert keine")
	check(m1.all(func(m: Array) -> bool: return absf(float(m[0]) - 0.5) >= 0.12 or absf(float(m[1]) - 0.47) >= 0.18), "Mitte bleibt frei")
	check(not wsrc.contains("OS.execute") and not wsrc.contains("shell_open"), "Assistent startet keine Programme")


func _suche(base: String, systems: Array, emus: Array) -> void:
	print("Suche mit Fortschritt")
	var p0 := E.search_progress({})
	check(float(p0.pct) == 0.0 and not bool(p0.done), "nichts begonnen: 0")
	var p1 := E.search_progress({ "launcher": "läuft", "state": "läuft", "emu_done": 50, "emu_total": 100, "dir_done": 0, "dir_total": 4 })
	check(is_equal_approx(float(p1.pct), (0.5 + 0.5 + 0.0) / 3.0), "Launcher läuft halb, Emulatoren zur Hälfte: %.2f" % float(p1.pct))
	var p2 := E.search_progress({ "launcher": "fertig", "state": "läuft", "emu_done": 100, "emu_total": 100, "dir_done": 4, "dir_total": 4 })
	check(float(p2.pct) < 1.0 and not bool(p2.done), "erst „fertig“, wenn der Faden fertig ist (nie 100 % vorher)")
	var p3 := E.search_progress({ "launcher": "läuft", "state": "fertig" })
	check(not bool(p3.done) and float(p3.emus) == 1.0, "Ordner fertig, Launcher lesen noch: nicht fertig")
	check(bool(E.search_progress({ "launcher": "fertig", "state": "fertig" }).done), "alles fertig")
	var box := { "emu_done": 0, "emu_total": 0, "dir_done": 0, "dir_total": 0, "where": "", "lock": Mutex.new() }
	var res: Dictionary = Wizard._find_all([base], {}, systems, emus, [], {}, box)
	check(int(box.emu_total) > 0 and int(box.emu_done) == int(box.emu_total), "Emulatoren: alle Orte gezählt (%d/%d)" % [int(box.emu_done), int(box.emu_total)])
	check(int(box.dir_total) > 0 and int(box.dir_done) == int(box.dir_total), "Spieleordner: alle Orte gezählt (%d/%d)" % [int(box.dir_done), int(box.dir_total)])
	check((res.dirs as Array).size() == 1 and (res.emus as Array).size() == 1, "mit Fortschritt dasselbe Ergebnis wie ohne")


## „Weiter“, bevor die Suche fertig ist: Sie schließt ohne den Schritt Spiele ab (_find_go) und übernimmt dann die
## Funde. Früher sah nur die Liste im Schritt Spiele das Ende: „läuft“ blieb für immer, die Funde kamen nie in die
## Einstellungen, und „Ordner hinzufügen …“ im Schritt Emulatoren tat nichts.
func _suche_ohne_seite(base: String, systems: Array, emus: Array) -> void:
	print("Suche schließt auch ohne den Schritt Spiele ab")
	var exe0 := str(Config.emulator("pcsx2").get("exe", ""))
	var dir0 := Config.rom_dir("ps2")
	var an0: Variant = Config.system("ps2").get("enabled", false)
	var box := { "state": "läuft", "emus": [], "dirs": [], "emu_done": 0, "emu_total": 0, "dir_done": 0, "dir_total": 0, "where": "",
		"weiter": false, "lock": Mutex.new() }
	Wizard._find = box
	Wizard._apply_found()
	check(bool(box.weiter) and not box.has("applied"), "Weiter während der Suche: gemerkt, noch nichts übernommen")
	await Wizard._find_go(self, box, [base], {}, systems, emus, [], {})
	check(str(box.state) == "fertig" and not box.has("task"), "Suche fertig, ohne dass eine Seite nachsieht")
	check(bool(box.get("applied", false)) and str(Config.emulator("pcsx2").get("exe", "")).ends_with("pcsx2-qtx64-avx2.exe")
			and Config.rom_dir("ps2").ends_with("ROMs/ps2"), "die Funde danach übernommen (PCSX2, Spieleordner PS2)")
	check(Zustand.lage().any(func(z: Dictionary) -> bool: return z.name == "einrichtung.suche" and z.zustand == "fertig"),
			"Stand für den Fehlerbericht: einrichtung.suche fertig")
	check(Quelle.lesen("res://src/ui/layers/setup_wizard_spiele.gd").contains("while tree != null and str(_find.get(\"state\", \"\")) == \"läuft\":"),
			"„Ordner hinzufügen …“ wartet, solange die Suche läuft")
	# Das Einlesen der übernommenen Funde abwarten, dann alles zurück.
	var bis := Time.get_ticks_msec() + 20000
	while Library.scanning and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	Config.set_emulator("pcsx2", "exe", exe0)
	Config.set_rom_dir("ps2", dir0)
	Config.set_system("ps2", "enabled", an0)
	Wizard._find = {}


# --- Controller koppeln (Punkt 133) -------------------------------------------------------------

func _koppeln() -> void:
	print("Controller koppeln: nur geprüfte Kennungen, nur Gamepads")
	var good := "Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b"
	var le := "BluetoothLE#BluetoothLEa4:c3:f0:11:22:33-C8:3F:26:4B:9E:01"
	check(Koppeln.valid_id(good) and Koppeln.valid_id(le), "Windows-Kennungen (klassisch und LE, Groß/klein)")
	for bad in [good + "\n", good + " ", " " + good, good + "; Remove-Item x", good.replace("-", "_"), "Bluetooth#Bluetooth00:1a:7d:da:71:13",
			"USB#VID_045E&PID_0B12",
			"BluetoothLE#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b:00", "Bluetooth#Bluetooth0g:1a:7d:da:71:13-e4:17:d8:2a:00:9b", "", "x".repeat(200)]:
		check(not Koppeln.valid_id(bad), "abgelehnt: „%s“" % bad.left(60).c_escape())
	for bad2 in [null, 42, [good], { "id": good }]:
		check(not Koppeln.valid_id(bad2), "abgelehnt: kein Text (%s)" % type_string(typeof(bad2)))
	check(Koppeln.is_gamepad({ "major": 5, "minor": 2 }) and Koppeln.is_gamepad({ "major": 5, "minor": 1 }), "Bluetooth: Peripherie mit Gamepad/Joystick")
	check(Koppeln.is_gamepad({ "appearance": 0x03C4 }) and Koppeln.is_gamepad({ "appearance": 0x03C3 }), "LE: Erscheinungsbild Gamepad/Joystick")
	for no in [{ "major": 5, "minor": 3 }, { "major": 4, "minor": 6 }, { "major": 5, "minor": 16 }, { "appearance": 0x03C1 }, { "appearance": 0x03C2 }, {}]:
		check(not Koppeln.is_gamepad(no), "kein Controller: %s" % str(no))
	var sc := Koppeln.parse_scan({ "code": "an", "devices": Koppeln.DEMO })
	var names: Array = (sc.devices as Array).map(func(d: Dictionary) -> String: return str(d.name))
	check(str(sc.state) == "an" and names == ["Xbox Wireless Controller", "DualSense Wireless Controller", "Pro Controller", "Wireless Controller", "Xbox Wireless Controller"],
			"Vorführung: drei neue Controller (stärkstes Signal zuerst), dann gekoppelt und verbunden; der Kopfhörer fehlt (%s)" % str(names))
	check((sc.devices as Array).map(func(d: Dictionary) -> String: return str(d.family)) == ["xbox", "ps", "nintendo", "ps", "xbox"], "Familien für Symbol und Anleitung")
	check(bool(sc.devices[0].le) and not bool(sc.devices[1].le), "LE erkannt")
	var dirty := Koppeln.parse_scan({ "devices": [
		{ "id": good, "name": "Pad\u202E\n\tX" + "y".repeat(100), "major": 5, "minor": 2, "signal": -40 },
		{ "id": good, "name": "doppelt", "major": 5, "minor": 2 },
		{ "id": "evil\nBluetooth#", "name": "x", "major": 5, "minor": 2 },
		"kein Eintrag", 7,
	] })
	check((dirty.devices as Array).size() == 1, "Doppeltes, Kaputtes und Fremdes fällt heraus")
	var nm := str(dirty.devices[0].name)
	check(not nm.contains("\n") and not nm.contains("\t") and not nm.contains("\u202E") and nm.length() <= Koppeln.NAME_MAX,
			"Name ohne Steuer- und Richtungszeichen, gekürzt: %s" % nm.left(30))
	var many: Array = []
	for i in 40:
		many.append({ "id": "Bluetooth#Bluetooth00:1a:7d:da:71:13-00:00:00:00:00:%02x" % i, "name": "P%d" % i, "major": 5, "minor": 2 })
	check((Koppeln.parse_scan({ "devices": many }).devices as Array).size() == Koppeln.LIST_MAX, "höchstens %d Geräte" % Koppeln.LIST_MAX)
	check(str(Koppeln.parse_scan({ "code": "aus" }).state) == "aus" and str(Koppeln.parse_scan({ "code": "quatsch" }).state) == "fehler"
			and str(Koppeln.parse_scan("x").state) == "fehler", "Zustand: aus / unbekannt / kaputt")
	check(Koppeln.pair_code({ "code": "gekoppelt" }) == "gekoppelt" and Koppeln.pair_code({ "code": "rm -rf" }) == "fehler"
			and Koppeln.pair_code(null) == "fehler", "Antwort aufs Koppeln: nur bekannte Schlüssel")
	check(Koppeln.bars(-50) == 3 and Koppeln.bars(-70) == 2 and Koppeln.bars(-80) == 1 and Koppeln.bars(-100) == 0, "Signal in Balken")
	var ok_status := true
	for k in Koppeln.STATUS.keys():
		var st: Array = Koppeln.STATUS[k]
		ok_status = ok_status and st.size() == 3 and str(st[0]) != "" and str(st[1]) != "" and str(st[2]) in ["ok", "warn", "faint"]
	check(ok_status, "jede Antwort mit Titel, Erklärung und Ton")
	check(" ".join(PackedStringArray(Koppeln.status("aus"))).contains("Bluetooth in Windows einschalten"), "Bluetooth aus: erklärt, schaltet nicht")
	check(" ".join(PackedStringArray(Koppeln.status("pin"))).contains("Windows"), "PIN nötig: ehrlich, kein Windows-Fenster aus Uzai")
	for fam in ["xbox", "ps", "nintendo", "other", "unbekannt"]:
		check(not Koppeln.steps(fam).is_empty(), "Anleitung für %s" % fam)
	var pp := FileAccess.get_file_as_string("res://src/ui/layers/pad_pair.gd")
	check(pp.contains("Koppeln.valid_id(id)") and pp.contains("Helper.run_once(\"bt-pair\"") and pp.contains("Helper.run_once(\"bt-scan\""),
			"Ebene: Kennung erst prüfen, Helfer als eigener Prozess")
	for bad in ["OS.execute", "OS.create_process", "shell_open", "Expression", "str_to_var"]:
		check(not pp.contains(bad), "Ebene ohne %s" % bad)
	var sv := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(sv.contains("_action(\"Controller koppeln\"") and sv.contains("pad_pair.gd\").open_for(main)"), "Einstellungen → Controller → Controller koppeln")
	check(FileAccess.get_file_as_string("res://src/ui/layers/pad_help.gd").contains("pad_pair.gd\").open_for(main)"),
			"Problemlöser „Wird nicht erkannt“ → Koppeln")


func _helfer() -> void:
	print("Helfer: Koppeln nur fest und geprüft")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(ps.contains("'bt-scan' { return (Bt-Scan $a) }") and ps.contains("'bt-pair' { return (Bt-Pair $a) }"), "zwei feste Befehle")
	var gd_re := Koppeln.ID_RE.replace("\\\\", "\\")
	check(ps.contains("$script:BtIdRe = '%s'" % gd_re), "dasselbe Muster für Kennungen wie in Uzai")
	var a := ps.find("function Bt-Scan(")
	var b := ps.find("function Invoke-Command-Json(")
	var bt := ps.substr(a, b - a)
	check(bt.contains("if (Test-BtAdmin) { return @{ code = 'admin'"), "nie mit Adminrechten")
	check(bt.find("if (-not (Test-BtId $id))") < bt.find("Use-Bt", bt.find("function Bt-Pair(")), "Kennung zuerst geprüft, dann erst WinRT")
	check(bt.contains("PairAsync([Windows.Devices.Enumeration.DevicePairingKinds]::ConfirmOnly)") and not bt.contains(".Pairing.PairAsync("),
			"nur „Bestätigen“ über eigene Kopplung, nie die Windows-Kopplung mit Fenster")
	check(bt.contains("if (-not (Test-BtGamepad $major $minor $look) -and -not ($major -eq 0 -and $look -eq 0 -and (Test-BtPadName ([string]$dev.Name)))) { return @{ code = 'klasse' } }"),
			"Klasse vor dem Koppeln noch einmal von Windows gelesen (Name nur, wenn Windows keine Klasse kennt)")
	for bad in ["SetStateAsync", "RequestAccessAsync", "Start-Process", "Invoke-Expression", "Set-ItemProperty", "New-ItemProperty", "Remove-Item",
			"-Verb RunAs"]:
		check(not bt.contains(bad), "Koppeln ohne %s" % bad)
	# Entkoppeln nur in Bt-Pair, nur nach „neu = 1“ (Neu koppeln, ausdrücklich gewünscht) und nur für genau dieses Gerät.
	var paar := bt.substr(bt.find("function Bt-Pair("))
	check(bt.count("UnpairAsync") == 1 and paar.find("UnpairAsync") > paar.find("if ($neu -ne 1) { return @{ code = 'schon'"),
			"Entkoppeln nur bei „Neu koppeln“ (neu = 1), sonst bleibt eine Kopplung, wie sie ist")
	check(paar.find("if ($neu -ne 0 -and $neu -ne 1) { return @{ code = 'kennung' } }") < paar.find("Use-Bt"), "„neu“ nur 0 oder 1, geprüft vor WinRT")
	var cs_a := ps.find("$script:BtSrc = @'")
	var cs := ps.substr(cs_a, ps.find("'@", cs_a) - cs_a)
	check(cs.contains("if (kind != 1) return;") and not cs.contains("DllImport"), "C#: nimmt nur „Bestätigen“ an, keine Windows-Aufrufe")
	if HelperScript._test_shell() == "":
		return
	print("Helfer unter PowerShell 7")
	var dir := OS.get_cache_dir().path_join("uzai-bt-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("uzai-helper.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string(ps)
	f.close()
	for job in [{ "cmd": "bt-pair", "args": { "id": "Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b; calc" }, "want": ["kennung"] },
			{ "cmd": "bt-pair", "args": { "id": ["x"] }, "want": ["kennung"] },
			{ "cmd": "bt-pair", "args": { "id": "Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b" }, "want": ["kein", "admin"] },
			{ "cmd": "bt-scan", "args": { "secs": 4 }, "want": ["kein", "admin"] }]:
		var out: Array = []
		OS.execute(HelperScript._test_shell(),
				PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Once",
				Marshalls.utf8_to_base64(JSON.stringify({ "id": 1, "cmd": job.cmd, "args": job.args }))]), out, true)
		var reply: Variant = null
		for line in str(out[0] if not out.is_empty() else "").split("\n"):
			var jp := JSON.new()
			if line.strip_edges().begins_with("{") and jp.parse(line.strip_edges()) == OK and jp.data is Dictionary and (jp.data as Dictionary).has("ok"):
				reply = jp.data
		var code := str((reply.result as Dictionary).get("code", "")) if reply is Dictionary and reply.result is Dictionary else ""
		check(reply is Dictionary and bool(reply.ok) and code in job.want,
				"%s %s → %s" % [job.cmd, str(job.args).left(50), code if code != "" else str(reply).left(160)])
	# Prüfregeln und C# (wie unter Windows PowerShell 5: C# 5, Warnungen als Fehler).
	var probe := dir.path_join("bt_probe.ps1")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	pf.store_string("""
$src = Get-Content -Raw $args[0]
$re = [regex]::Match($src, '(?m)^\\$script:BtIdRe = ''([^'']*)''').Groups[1].Value
"RE " + $re.Length
$script:BtIdRe = $re
foreach ($fn in 'Test-BtId', 'Test-BtGamepad', 'Get-BtPairCode') {
    $m = [regex]::Match($src, '(?s)\\n(function ' + $fn + '\\(.*?\\r?\\n\\})\\r?\\n')
    Invoke-Expression $m.Groups[1].Value
}
$good = 'Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b'
"ID-GUT " + (Test-BtId $good)
"ID-ZEILE " + (Test-BtId ($good + "`n"))
"ID-ANHANG " + (Test-BtId ($good + '; x'))
"ID-ZAHL " + (Test-BtId 42)
"PAD " + (Test-BtGamepad 5 2 0) + " " + (Test-BtGamepad 0 0 964) + " " + (Test-BtGamepad 4 6 0) + " " + (Test-BtGamepad 5 3 0)
"CODE " + (Get-BtPairCode 0) + " " + (Get-BtPairCode 3) + " " + (Get-BtPairCode 14) + " " + (Get-BtPairCode 99)
$cs = [regex]::Match($src, '(?s)\\$script:BtSrc = @''\\r?\\n(.*?)\\r?\\n''@').Groups[1].Value
"CSLEN " + $cs.Length
try { Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; "CS ok" } catch { "CS FEHLER " + $_.Exception.Message }
""")
	pf.close()
	var o2: Array = []
	OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, script]), o2, true)
	var txt := str(o2[0] if not o2.is_empty() else "")
	check(txt.contains("RE %d" % gd_re.length()) and not txt.contains("CSLEN 0") and txt.contains("CSLEN "), "Muster und C# aus dem Helfer gelesen")
	check(txt.contains("ID-GUT True") and txt.contains("ID-ZEILE False") and txt.contains("ID-ANHANG False") and txt.contains("ID-ZAHL False"),
			"Test-BtId wie in Uzai (auch kein Zeilenumbruch am Ende)")
	check(txt.contains("PAD True True False False"), "Test-BtGamepad wie in Uzai")
	check(txt.contains("CODE gekoppelt schon abgelehnt fehler"), "Ergebnis von Windows → Uzais Schlüssel")
	check(txt.contains("CS ok"), "C#-Teil übersetzt mit C# 5 (%s)" % txt.get_slice("CS", 1).strip_edges().left(200))


## Emulators that are already set up are listed above the scan results (otherwise the page said no
## emulators were found even though all of them were already set up).
func _schon() -> void:
	print("Schon eingerichtet")
	var Spiele: GDScript = load("res://src/ui/layers/setup_wizard_spiele.gd")
	var e0: Dictionary = Config.emulators()[0]
	var vorher := str(e0.get("exe", ""))
	Config.set_emulator(str(e0.id), "exe", OS.get_executable_path())
	var s: Dictionary = Spiele.schon_eingerichtet()
	check(str(s.get("text", "")).contains("Emulator") and str(s.get("names", "")).contains(str(e0.get("name", e0.id))),
			"Emulator mit Programmdatei zählt als eingerichtet")
	Config.set_emulator(str(e0.id), "exe", vorher)
	check(Quelle.lesen("res://src/ui/layers/setup_wizard_spiele.gd").contains("\"Alles eingerichtet\" if emus.is_empty() and dirs.is_empty()"),
			"nichts Neues gefunden, aber alles da: „Alles eingerichtet“ statt „Keine Emulatoren“")

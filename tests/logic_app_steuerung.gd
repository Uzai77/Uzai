extends Node
## Eigene Apps wie auf einer Konsole (src/core/app_steuerung.gd) ohne Windows: Profile je App (Netflix,
## Disney+, Prime Video, Crunchyroll, YouTube, Plex, Kodi …) und Standard, nur Tasten aus der
## Erlaubnisliste (dieselbe Spalte „app“ in tests/fixtures/tasten_kombis.json prüft der Helfer),
## an/aus je App, die Aufträge an den Helfer (app-vollbild, app-pad) nur mit geprüfter App und
## Fensternummer, die Tastenzeile, Text aus Uzais Tastatur (app-text), der Leitfaden (Belegung,
## Form des Controllers, die ersten Starts) und dass Uzai dabei nichts Globales drückt.
## Aufruf: godot --headless --path . res://tests/logic_app_steuerung.tscn

const S := preload("res://src/core/app_steuerung.gd")
const A := preload("res://src/core/apps_extern.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _store(aumid: String, name: String) -> Dictionary:
	return { "id": A.make_id("store", aumid), "kind": "store", "name": name, "aumid": aumid }


func _prog(path: String, name: String) -> Dictionary:
	return { "id": A.make_id("prog", A.norm_path(path)), "kind": "prog", "name": name, "path": A.norm_path(path), "args": [] }


func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p).replace("\r\n", "\n")


func _ready() -> void:
	var netflix := _store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	var disney := _store("Disney.37853FC22B2CE_6rarf9sa4v8jt!App", "Disney+")
	var prime := _store("AmazonVideo.PrimeVideo_pwbj9vvecjh7j!App", "Prime Video for Windows")
	var crunchy := _store("CrunchyrollLLC.Crunchyroll_aqn8yq3m9x1t2!App", "Crunchyroll")
	var plexhtpc := _prog("C:\\Program Files\\Plex\\Plex HTPC\\Plex HTPC.exe", "Plex HTPC")
	var plex := _store("CAF9E577.Plex_aam28m9va5cke!App", "Plex")
	var kodi := _prog("C:/Program Files/Kodi/kodi.exe", "Kodi")
	var moon := _prog("C:\\Program Files\\Moonlight Game Streaming\\Moonlight.exe", "Moonlight")
	var unbekannt := _store("Microsoft.ZuneVideo_8wekyb3d8bbwe!Microsoft.ZuneVideo", "Filme & TV")
	var yt := _prog("D:\\Apps\\TV\\youtube-tv.exe", "Fernsehen")
	for e in [netflix, disney, prime, crunchy, plexhtpc, plex, kodi, moon, unbekannt, yt]:
		check(A.entry_ok(e), "Testeintrag gültig: %s" % str(e.name))

	print("Profile")
	var want := { "netflix": netflix, "disney": disney, "prime": prime, "crunchyroll": crunchy, "plexhtpc": plexhtpc, "plex": plex,
		"kodi": kodi, "moonlight": moon, "standard": unbekannt, "youtube": yt }
	for id in want:
		check(str(S.profil(want[id]).id) == id, "%s → Profil %s" % [str(want[id].name), id])
	check(S.profil(netflix).tasten == S.STANDARD and str(S.profil(netflix).vollbild) == "F11", "Netflix: A Enter, B Esc, X Leertaste, Y F11, LB/RB Umschalt+Tab/Tab; Vollbild mit F11")
	check(str(S.profil(prime).tasten.b) == "BACKSPACE" and str(S.profil(prime).vollbild) == "", "Prime Video: B Backspace, gleich randlos")
	check(str(S.profil(plex).tasten.b) == "BACKSPACE" and str(S.profil(kodi).tasten.b) == "BACKSPACE", "Plex, Kodi: B Backspace")
	check(str(S.STANDARD.lb) == "SHIFT+TAB" and str(S.STANDARD.rb) == "TAB" and str(S.STANDARD.x) == "SPACE" and str(S.STANDARD.a) == "ENTER", "Standard: LB/RB Umschalt+Tab/Tab, X Play/Pause, A Enter")
	for p in S.PROFILE:
		var t := S.STANDARD.duplicate()
		t.merge(p.get("tasten", {}), true)
		check(S.tasten_ok(t) and (str(p.get("vollbild", "")) == "" or S.taste_ok(str(p.vollbild))), "Profil %s nur mit erlaubten Tasten" % str(p.id))
	check(S.tasten_ok(S.STANDARD), "Standard nur mit erlaubten Tasten")

	print("Erlaubnisliste (Spalte „app“ wie im Helfer)")
	var jp := JSON.new()
	check(jp.parse(_src("res://tests/fixtures/tasten_kombis.json")) == OK and jp.data is Dictionary, "Tabelle lesbar")
	var bad := PackedStringArray()
	var n := 0
	for c in (jp.data as Dictionary).get("faelle", []):
		if (c as Array).size() < 5:
			bad.append("„%s“ ohne Spalte app" % str(c[0]))
			continue
		n += 1
		if S.taste_ok(str(c[0])) != (str(c[4]) == "ok") and str(c[0]) == str(c[0]).to_upper():
			bad.append("„%s“" % str(c[0]).c_escape())
	check(n >= 50 and bad.is_empty(), "%d Kürzel wie im Helfer%s" % [n, (": " + "; ".join(bad)) if not bad.is_empty() else ""])
	for t in ["WIN+R", "ALT+F4", "ALT+TAB", "CTRL+ESC", "ALT+LEFT", "F4", "S", "CTRL+V", "SHIFT+F11", "WIN", "", "ENTER;calc"]:
		check(not S.taste_ok(t), "nie an eine App: „%s“" % t)
	check(not S.tasten_ok({ "a": "ENTER" }) and not S.tasten_ok(null), "unvollständige Belegung abgelehnt")
	var boese := S.STANDARD.duplicate()
	boese["y"] = "WIN+R"
	check(not S.tasten_ok(boese), "Belegung mit Win+R abgelehnt")
	var leer := S.STANDARD.duplicate()
	leer["y"] = ""
	check(S.tasten_ok(leer), "Knopf ohne Taste erlaubt")

	print("An/aus je App")
	Config.set_value(S.KEY, {})
	check(S.an(netflix) and S.an(unbekannt) and S.an(plex), "Netflix, Unbekannte, Plex: an")
	check(not S.an(kodi) and not S.an(moon) and not S.an(plexhtpc), "Kodi, Moonlight, Plex HTPC (können selbst Controller): aus")
	S.setzen(netflix, false)
	S.setzen(kodi, true)
	check(not S.an(netflix) and S.an(kodi) and S.an(disney), "umgestellt gilt je App")
	S.setzen(netflix, true)
	check(not (Config.get_value(S.KEY, {}) as Dictionary).has(netflix.id), "zurück auf Standard: nichts gespeichert")
	Config.set_value(S.KEY, { "boese": false, netflix.id: "nein", disney.id: false })
	check(S.an(netflix) and not S.an(disney), "fremde Werte in der Datei zählen nicht")
	Config.set_value(S.KEY, {})

	print("Aufträge an den Helfer")
	var v := S.vollbild_auftrag(netflix, 4242, true, "F11")
	check(v == { "hwnd": 4242, "kind": "store", "aumid": netflix.aumid, "an": true, "taste": "F11" }, "app-vollbild: Fenster, Kennung, F11")
	check(str(S.vollbild_auftrag(netflix, 4242, true, "WIN+R").taste) == "", "app-vollbild: Taste außerhalb der Liste fällt weg")
	check(str(S.vollbild_auftrag(netflix, 4242, false, "F11").taste) == "" and not bool(S.vollbild_auftrag(netflix, 4242, false).an), "app-vollbild zurück: ohne Taste")
	check(S.vollbild_auftrag(netflix, 0, true).is_empty() and S.vollbild_auftrag({ "kind": "store", "aumid": "x;calc" }, 5, true).is_empty(), "ohne Fenster oder mit falscher App: kein Auftrag")
	var kp := S.vollbild_auftrag(kodi, 77, true)
	check(str(kp.path) == "C:\\Program Files\\Kodi\\kodi.exe" and not kp.has("aumid"), "Programm: Pfad in Windows-Form")
	var p := S.pad_auftrag(prime, 99)
	check(bool(p.an) and int(p.hwnd) == 99 and S.tasten_ok(p.tasten) and str(p.tasten.b) == "BACKSPACE", "app-pad: Fenster und Tasten des Profils")
	check(S.pad_auftrag(prime, 0).is_empty() and S.pad_auftrag({}, 5).is_empty(), "app-pad: ohne Fenster oder App nichts")

	print("Tastenzeile")
	check(S.hinweis(netflix) == [["b", "Zurück"], ["guide", "Uzai"]], "„B Zurück · Guide Uzai“")
	check(S.hinweis(kodi) == [["guide", "Uzai"]], "ohne Übersetzung nur „Guide Uzai“")
	check(S.HINWEIS_MS == 2000, "zwei Sekunden")

	print("Textfeld: Uzais Tastatur (app-text)")
	check(S.text_ok("Stranger Things") and S.text_ok("Grüße – ½") and S.text_ok("a".repeat(500)), "Text: Buchstaben, Umlaute, Zeichen, bis 500")
	var schlecht := ["", "a".repeat(501), "a\nb", "a\tb", "x" + char(7), "a" + char(0x85), "a" + char(0x202E) + "b", char(0x200B), char(0xFEFF) + "a", 5, null]
	check(schlecht.filter(func(t: Variant) -> bool: return S.text_ok(t)).is_empty(), "kein Zeilenumbruch, Tab, Steuer-, Richtungs- oder unsichtbares Zeichen, nicht leer, nicht zu lang, nur Text")
	var tx := S.text_auftrag(netflix, 4242, "Dark")
	check(tx == { "hwnd": 4242, "kind": "store", "aumid": netflix.aumid, "text": "Dark" }, "app-text: Fenster, Kennung, Text")
	check(S.text_auftrag(netflix, 0, "Dark").is_empty() and S.text_auftrag(netflix, 5, "a\nb").is_empty() and S.text_auftrag({}, 5, "x").is_empty(), "app-text: ohne Fenster, mit falschem Text oder ohne App nichts")
	check(S.hinweis_textfeld() == [["y", "Tastatur"], ["guide", "Uzai"]], "Hinweis im Textfeld: „Y Tastatur · Guide Uzai“")
	var hs := _src("res://helper/uzai-helper.ps1")
	check(hs.contains("public const int AppTextMax = 500;") and S.TEXT_MAX == 500, "Grenze wie im Helfer (500 Zeichen)")

	print("Leitfaden")
	var bn := S.belegung(netflix)
	check(bn == { "guide": "Uzai", "a": "Auswählen", "b": "Zurück", "x": "Pause", "y": "Vollbild", "lb": "Vorheriges", "rb": "Nächstes",
			"dpad": "Bewegen", "rs": "Zeiger", "rt": "Klicken" }, "Netflix: Belegung aus dem Profil, kurz beschriftet")
	check(S.belegung(kodi) == { "guide": "Uzai" }, "ohne Übersetzung (Kodi kann selbst Controller): nur Guide")
	for t in S.NAMEN:
		check(S.ERLAUBT.has(t), "Beschriftung nur für erlaubte Tasten: " + str(t))
	Config.set_value(S.LEITFADEN_KEY, {})
	check(S.leitfaden_faellig(netflix), "erster Start: Leitfaden")
	for i in S.LEITFADEN_MAL:
		S.leitfaden_gezeigt(netflix)
	check(not S.leitfaden_faellig(netflix) and S.leitfaden_faellig(disney), "nach %d Starts nicht mehr von selbst, andere Apps schon" % S.LEITFADEN_MAL)
	Config.set_value(S.LEITFADEN_KEY, { "boese": 0, netflix.id: "x", disney.id: 1 })
	check(S.leitfaden_faellig(netflix) and S._leitfaden_zahlen().size() == 1, "kaputte Einträge zählen nicht")
	Config.set_value(S.LEITFADEN_KEY, {})
	check(S.familie("auto", "ps", true) == "ps" and S.familie("auto", "nintendo", true) == "nintendo" and S.familie("auto", "deck", true) == "xbox", "Form vom Controller (Handhelds wie Xbox)")
	check(S.familie("auto", "keys", true) == "xbox" and S.familie("ps", "xbox", false) == "ps" and S.familie("auto", "xbox", false) == "", "Tastensymbole fest gewählt gelten; ohne Controller kein Leitfaden")
	check(S.LEITFADEN_MS >= 3000 and S.LEITFADEN_MS <= 6000, "steht etwa vier Sekunden")

	print("Quelltext")
	var l := _src("res://src/core/launcher.gd")
	check(l.contains("AppSteuerung.vollbild_auftrag(e, _game_hwnd, true, str(prof.vollbild))") and l.contains("await app_steuerung(AppSteuerung.an(e))"), "Launcher: Vollbild, dann Controller (je App)")
	check(l.contains("_app_ende(g.get(\"app\", {}))"), "Launcher: beim Ende aus und zurück")
	var h := _src("res://src/core/helper.gd")
	check(h.contains("\"app-start\", \"app-window\", \"app-vollbild\"]") and not h.contains("\"app-pad\""), "app-vollbild schnell, app-pad im Hauptweg (dort liest der Controller-Wächter)")
	var me := _src("res://src/main_ebenen.gd")
	check(me.contains("if not Launcher.filter_active() and not app:") and me.contains("app_hinweis()"), "App: Kulisse statt Vorhang, Tastenzeile")
	var mf := _src("res://src/main_fenster.gd")
	check(mf.contains("_kulisse_zeigen()") and mf.contains("and not _kulisse\n"), "Uzai bleibt dahinter (keine Wache, kein Minimieren)")
	check(mf.contains("if hints.is_empty() and AppSteuerung.leitfaden_faellig(e) and app_leitfaden(false):"), "beim Start: erst der Leitfaden, sonst die Tastenzeile")
	var mg := _src("res://src/main_guide.gd")
	check(mg.contains("kind == \"app-tastatur\" or kind == \"app-textfeld\"") and mg.contains("AppTastatur.melden(self, kind)"), "Meldungen des Helfers öffnen Uzais Tastatur")
	var at := _src("res://src/ui/app_tastatur.gd")
	check(at.contains("AppSteuerung.text_auftrag(e, hwnd, text)") and at.contains("Helper.run(\"app-text\"") and not at.contains("\"keys\""), "Text nur über app-text (geprüftes Fenster), keine Tastenkürzel")
	var src := _src("res://src/core/app_steuerung.gd")
	check(not src.contains("Helper.run") and not src.contains("global"), "keine globalen Tasten aus Uzai")
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)

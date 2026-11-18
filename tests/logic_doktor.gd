extends Node
## Uzai-Doktor (Punkt 133, src/core/doktor.gd und doktor_lage.gd): welche Karte zu welcher Lage
## gehört, wichtig vor Hinweis, was „in Ordnung“ heißt, Speicher-, Uhr- und Netzgrenzen, die
## Kopfzeile „Date“, der Hinweis auf der Startseite (nie doppelt), die Vorführung, die echte Lage
## auf diesem PC, Uhr und Netz aus Net, Theme-Rückfall aus UzTheme, Helfer-Zustand und dass die
## Seite für jede Karte einen Weg kennt – ohne Shell, ohne fremde Programme.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_doktor.tscn → „Ergebnis: alles ok“

const Doktor := preload("res://src/core/doktor.gd")
const Lage := preload("res://src/core/doktor_lage.gd")
const IconsS := preload("res://src/core/icons.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func ids(list: Array) -> Array:
	return list.map(func(c: Dictionary) -> String: return str(c.id))


func _ready() -> void:
	print("Nichts bekannt: nichts behaupten")
	check(Doktor.cards({}).is_empty(), "leere Lage: keine Karte")
	check(Doktor.ok_checks({}, []).is_empty(), "leere Lage: nichts „in Ordnung“ (nicht geprüft ist nicht gut)")
	check(Doktor.summary([]).text == "Alles in Ordnung" and int(Doktor.summary([]).wichtig) == 0, "Zusammenfassung ohne Karten")

	print("Vorführ-Lage")
	var demo := Doktor.cards(Doktor.DEMO)
	var dids := ids(demo)
	for want in ["emu:dolphin", "ordner:gba", "konto:twitch", "launcher", "speicher", "pad_akku:DualSense"]:
		check(dids.has(want), "Karte %s" % want)
	var first_hint := -1
	var last_wichtig := -1
	for i in demo.size():
		if str(demo[i].sev) == "wichtig":
			last_wichtig = i
		elif first_hint < 0:
			first_hint = i
	check(first_hint < 0 or last_wichtig < first_hint, "wichtige Karten zuerst (%s)" % str(dids))
	var sm := Doktor.summary(demo)
	check(int(sm.wichtig) == 3 and int(sm.hinweis) == 3 and str(sm.text) == "3 Probleme · 3 Hinweise", "Zusammenfassung: %s" % str(sm.text))
	var seen := {}
	var all_ok := true
	for c in demo:
		for k in ["id", "check", "sev", "icon", "title", "text", "fix", "fix_label", "self", "how"]:
			if not (c as Dictionary).has(k):
				all_ok = false
		if seen.has(str(c.id)):
			all_ok = false
		seen[str(c.id)] = true
		if bool(c.self) and (str(c.fix) == "" or str(c.fix_label) == ""):
			all_ok = false
		if not bool(c.self) and (c.how as Array).is_empty():
			all_ok = false
		if not IconsS.P.has(str(c.icon)):
			all_ok = false
	check(all_ok, "jede Karte vollständig, Kennungen einmalig, „Beheben“ mit Weg, sonst Schritte zum Selbermachen, Symbol vorhanden")
	var oks := Doktor.ok_checks(Doktor.DEMO, demo)
	check(oks.has("Windows-Helfer") and oks.has("Uhrzeit") and oks.has("Internet") and not oks.has("Emulatoren") and not oks.has("Speicher"),
			"in Ordnung nur, was geprüft und ohne Karte ist: %s" % str(oks))

	print("Controller")
	check(str(Doktor.cards({ "pads": 0, "known_pad": true })[0].sev) == "wichtig", "Controller war schon da, jetzt keiner: wichtig")
	check(str(Doktor.cards({ "pads": 0 })[0].sev) == "hinweis", "nie einer gesehen (Tastatur): nur Hinweis")
	check(str(Doktor.cards({ "pads": 0 })[0].fix) == "koppeln", "Beheben: koppeln")
	check(Doktor.cards({ "pads": 2 }).is_empty(), "zwei Controller: nichts")
	check(str(Doktor.cards({ "pads": 1, "pad_dupes": ["steam"] })[0].fix) == "pad_help", "doppelte Eingaben → Problemlöser (pad_check.gd)")
	check(not bool(Doktor.cards({ "pad_low": ["Xbox Wireless Controller"] })[0].self), "Akku: nur erklären (laden kann Uzai nicht)")

	print("Launcher, Emulatoren, Ordner")
	var la := Doktor.cards({ "launchers_missing": [{ "id": "ea", "name": "EA app", "what": "deine EA-Spiele" }, { "id": "epic", "name": "Epic Games Launcher" }] })
	check(la.size() == 1 and str(la[0].title).contains("EA app, Epic Games Launcher"), "fehlende Launcher in einer Karte: %s" % str(la[0].title))
	var emus: Array = []
	for i in 5:
		emus.append({ "id": "e%d" % i, "name": "Emu %d" % i, "systems": ["X"], "games": i })
	var ec := Doktor.cards({ "emus_missing": emus })
	check(ec.size() == Doktor.EMU_CARDS + 1 and str(ec[ec.size() - 1].id) == "emu_mehr", "mehr als drei Emulatoren: drei Karten und eine Sammelkarte")
	check(str(ec[0].sev) == "wichtig" and str(ec[0].id) == "emu:e1", "mit Spielen wichtig und vorn (e1), ohne Spiele nur Hinweis")
	check(str(Doktor.cards({ "emus_missing": [{ "id": "x", "name": "X", "systems": ["GC"], "games": 1 }] })[0].text).begins_with("Ein Spiel für GC startet"),
			"Einzahl")
	var oc := Doktor.cards({ "romdirs_missing": [{ "system": "gba", "name": "Game Boy Advance", "dir": "E:\\ROMs\\gba" }] })
	check(str(oc[0].fix) == "ordner:gba" and str(oc[0].text).contains("E:\\ROMs\\gba"), "verschwundener Ordner: neu wählen, mit Pfad")
	check(str(Doktor.cards({ "games": 0 })[0].id) == "spiele", "leere Bibliothek: Hinweis")
	check(Doktor.cards({ "games": 0, "scanning": true }).is_empty(), "liest gerade ein: abwarten")

	print("Speicher, Helfer, Anmeldungen, Theme")
	check(Doktor.cards({ "space_free": 10 * Doktor.GB }).is_empty(), "10 GB frei: gut")
	check(str(Doktor.cards({ "space_free": 3 * Doktor.GB })[0].sev) == "hinweis", "3 GB: Hinweis")
	check(str(Doktor.cards({ "space_free": 500 * 1024 * 1024, "space_dir": "D:" })[0].sev) == "wichtig", "500 MB: wichtig")
	check(str(Doktor.cards({ "space_free": 500 * 1024 * 1024, "space_dir": "D:" })[0].text).contains("500 MB"), "Größe lesbar")
	check(Doktor.cards({ "space_free": -1 }).is_empty(), "unbekannt: nichts")
	check(str(Doktor.cards({ "helper": "blockiert" })[0].fix) == "helfer", "Helfer blockiert: neu starten")
	check(Doktor.cards({ "helper": "startet" }).is_empty() and Doktor.cards({ "helper": "ok" }).is_empty(), "Helfer startet noch oder läuft: nichts")
	var hc: Dictionary = Doktor.cards({ "helper": "blockiert" })[0]
	check(" ".join(PackedStringArray(hc.how)).contains("Ausnahme") and str(hc.text).contains("Virenscanner"),
			"Helfer: Virenscanner als Grund, Ausnahme selbst anlegen")
	check(str(Doktor.cards({ "logins_expired": [{ "id": "twitch", "name": "Twitch" }] })[0].fix) == "konto:twitch", "Anmeldung abgelaufen: neu anmelden")

	print("Uhr und Netz: nur erklären")
	check(Doktor.cards({ "clock_known": true, "clock_skew": 120 }).is_empty(), "2 Minuten daneben: geht noch")
	var uc := Doktor.cards({ "clock_known": true, "clock_skew": 3600 })
	check(uc.size() == 1 and str(uc[0].sev) == "wichtig" and not bool(uc[0].self) and str(uc[0].fix) == "", "eine Stunde: wichtig, Uzai stellt die Uhr nicht")
	check(str(uc[0].text).contains("eine Stunde nach"), "PC geht nach (Server später): %s" % str(uc[0].text))
	check(str(Doktor.cards({ "clock_known": true, "clock_skew": -2 * 86400 })[0].text).contains("2 Tage vor"), "PC geht vor")
	check(Doktor.cards({ "clock_known": false, "clock_skew": 99999 }).is_empty(), "Uhr unbekannt: nichts")
	check(Doktor.net_state(0, 0, 0) == "", "Netz: noch nichts gehört")
	check(Doktor.net_state(5000, 0, 0) == "ok", "Netz: Antwort da")
	check(Doktor.net_state(5000, 9000, 3) == "weg", "drei Fehlschläge nach der letzten Antwort: weg")
	check(Doktor.net_state(9500, 9000, 3) == "ok", "danach wieder eine Antwort: da")
	check(Doktor.net_state(5000, 9000, 2) == "ok", "zwei Fehlschläge: noch nicht")
	var nc := Doktor.cards({ "net": "weg" })
	check(nc.size() == 1 and not bool(nc[0].self) and " ".join(PackedStringArray(nc[0].how)).contains("Router"),
			"Netz weg: erklären, nichts umstellen")

	print("Kopfzeile Date")
	var t := Doktor.http_date("Sun, 06 Nov 1994 08:49:37 GMT")
	check(t == -1, "vor 2000: nicht glauben")
	var t2 := Doktor.http_date("Fri, 23 Oct 2026 10:15:00 GMT")
	check(t2 == Time.get_unix_time_from_datetime_dict({ "year": 2026, "month": 10, "day": 23, "hour": 10, "minute": 15, "second": 0 }),
			"RFC-7231-Datum → Unix-Zeit")
	for bad in ["", "gestern", "Fri, 23 Okt 2026 10:15:00 GMT", "Fri, 23 Oct 2026 25:15:00 GMT", "Fri, 23 Oct 2026 10:15:00 CET", "Fri, 99 Oct 2026 10:15:00 GMT",
			"Fri, 23 Oct 2026 10:15 GMT"]:
		check(Doktor.http_date(bad) == -1, "ungültig: „%s“" % bad)

	print("Hinweis auf der Startseite")
	check(Doktor.hint_sig(demo, false, "") == "", "abgeschaltet: nie")
	var sig := Doktor.hint_sig(demo, true, "")
	check(sig != "" and sig.contains("emu:dolphin") and not sig.contains("speicher"), "nur wichtige Karten zählen: %s" % sig)
	check(Doktor.hint_sig(demo, true, sig) == "", "dieselben Probleme: nicht noch einmal")
	check(Doktor.hint_sig(Doktor.cards({ "space_free": 3 * Doktor.GB }), true, "") == "", "nur Hinweise: kein Hinweis auf der Startseite")
	check(Doktor.hint_sig(Doktor.cards({ "net": "weg" }), true, sig) == "netz", "etwas Neues: wieder")

	print("Lage: Vorführung und dieser PC")
	var was_demo := Library.demo
	Library.demo = true
	Lage.demo_fixed.clear()
	check(Lage.gather() == Doktor.DEMO, "Vorführung: feste Lage")
	Lage.demo_fixed["emu:dolphin"] = true
	check(not ids(Doktor.cards(Lage.gather())).has("emu:dolphin"), "in der Vorführung behoben: Karte weg")
	Lage.demo_fixed.clear()
	Library.demo = false
	var f := Lage.gather()
	for k in ["windows", "pads", "pad_low", "pad_dupes", "emus_missing", "romdirs_missing", "games", "space_free", "logins_expired", "net",
			"crash"]:
		check(f.has(k), "Lage kennt „%s“" % k)
	check(not f.has("helper"), "ohne Windows (und ohne Test-Shell): Helfer nicht geprüft")
	check(int(f.space_free) > 0, "freier Speicher des Datenordners gelesen")
	var dirs: Dictionary = Config.get_value("library.rom_dirs", {}).duplicate()
	Config.set_rom_dir("gba", OS.get_cache_dir().path_join("uzai-gibts-nicht-%d" % Time.get_ticks_usec()))
	Config.set_system("gba", "enabled", true)
	var f2 := Lage.gather()
	check((f2.romdirs_missing as Array).any(func(d: Dictionary) -> bool: return str(d.system) == "gba"), "eingetragener Ordner, den es nicht gibt: gemeldet")
	check((f2.emus_missing as Array).any(func(e: Dictionary) -> bool: return (e.systems as Array).has(str(Config.system("gba").get("short", "")))),
			"dessen Emulator ohne Programmdatei: gemeldet")
	Config.set_value("library.rom_dirs", dirs)
	Library.demo = was_demo

	print("Uhr und Netz aus Net, Theme aus UzTheme, Helfer")
	var keep := [Net.last_ok_ms, Net.last_fail_ms, Net.fails, Net.clock_skew, Net.clock_known]
	var later := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + 3600)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var date := "Mon, %02d %s %d %02d:%02d:%02d GMT" % [later.day, months[later.month - 1], later.year, later.hour, later.minute, later.second]
	Net._note(HTTPRequest.RESULT_SUCCESS, PackedStringArray(["Content-Type: text/html", "Date: " + date]))
	check(Net.clock_known and absi(Net.clock_skew - 3600) <= 2, "Antwort mit Date eine Stunde später: Abweichung %d s" % Net.clock_skew)
	check(ids(Doktor.cards({ "clock_known": Net.clock_known, "clock_skew": Net.clock_skew })) == ["uhr"], "→ Karte Uhrzeit")
	for i in 3:
		Net._note(HTTPRequest.RESULT_CANT_CONNECT, PackedStringArray())
	check(Doktor.net_state(Net.last_ok_ms, Net.last_fail_ms, Net.fails) == "weg", "drei Mal keine Verbindung: Netz weg")
	Net._note(HTTPRequest.RESULT_SUCCESS, PackedStringArray())
	check(Doktor.net_state(Net.last_ok_ms, Net.last_fail_ms, Net.fails) == "ok", "wieder eine Antwort: Netz da")
	Net.last_ok_ms = keep[0]
	Net.last_fail_ms = keep[1]
	Net.fails = keep[2]
	Net.clock_skew = keep[3]
	Net.clock_known = keep[4]
	check(Helper.state() == "", "Helfer ohne Windows: kein Zustand")

	print("Seite, Einstellungen, Guide, Startseite")
	var page := FileAccess.get_file_as_string("res://src/ui/layers/doktor.gd")
	for fix in ["\"koppeln\":", "\"pad_help\":", "\"launcher\":", "\"speicher\":", "\"helfer\":", "\"suche\":", "\"absturz\":",
			"fix.begins_with(\"emu:\")", "fix.begins_with(\"ordner:\")", "fix.begins_with(\"konto:\")", "fix.begins_with(\"seite:\")"]:
		check(page.contains(fix), "Seite kennt %s" % fix)
	for bad in ["OS.execute", "OS.create_process", "OS.shell_open", "execute_with_pipe", "Expression", "str_to_var"]:
		check(not page.contains(bad), "Seite ohne %s" % bad)
	check(page.contains("const NET_PROBE := \"https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/\""),
			"einzige Anfrage ins Netz: Steams öffentliche Server-Zeit (https)")
	check(page.contains("open_file_browser("), "Ordner wählen mit Uzais eigener Dateiauswahl (kein Windows-Dialog)")
	var sv := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(sv.contains("_action(\"Uzai-Doktor\"") and sv.contains("main.open_doktor()") and sv.contains("\"system.doktor_hint\""),
			"Einstellungen → System: Doktor und Schalter für den Hinweis")
	var gd := Quelle.lesen("res://src/ui/layers/guide.gd")
	check(gd.contains("_act(\"Uzai-Doktor\"") and gd.contains("_doktor_dot()"), "Guide → System: Doktor und Punkt")
	var mn := Quelle.lesen("res://src/main.gd")
	check(mn.contains("func open_doktor()") and mn.contains("_doktor_hint.call_deferred()") and mn.contains("Doktor.hint_sig("), "Startseite: einmaliger Hinweis")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

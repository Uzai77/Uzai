extends Node
## Hilfe bei Problemen (Punkte 15, 113, 116): hängendes Spiel, Absturz und Fehlstart erkennen,
## Tipps je Quelle, Liste „Erste Hilfe“. Aufruf: godot --headless --path . res://tests/logic_hilfe.tscn

const Trouble := preload("res://src/core/trouble.gd")
const SettingsView := preload("res://src/ui/sections/settings_view.gd")
const IconsS := preload("res://src/core/icons.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_hung()
	_codes()
	_verdict()
	_texts()
	_tips()
	_first_aid()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _hung() -> void:
	print("Hängt das Spiel?")
	var since := Trouble.hung_since(0, true, 5000)
	check(since == 5000, "erste Meldung „hängt“ merkt sich die Zeit")
	check(Trouble.hung_since(since, true, 9000) == 5000, "hängt weiter: Zeit bleibt")
	check(not Trouble.is_hung(since, 5000 + Trouble.HUNG_MS - 1), "knapp unter der Grenze: noch nicht")
	check(Trouble.is_hung(since, 5000 + Trouble.HUNG_MS), "ab der Grenze: hängt")
	check(Trouble.hung_since(since, false, 20000) == 0, "antwortet wieder: von vorn")
	check(not Trouble.is_hung(0, 99999), "ohne Meldung nie hängend")
	check(Trouble.hung_since(0, true, 0) == 1, "Zeit 0 zählt trotzdem als „seit“")
	# Ladepause: kurz hängend, dann wieder da, dann wieder kurz – nie die volle Zeit am Stück.
	var s := 0
	var hit := false
	for t in [0, 3000, 6000, 9000, 12000, 15000, 18000]:
		s = Trouble.hung_since(s, t != 9000, t + 1)
		hit = hit or Trouble.is_hung(s, t + 1)
	check(not hit, "Unterbrechung setzt zurück (keine Meldung bei zwei kurzen Pausen)")


func _codes() -> void:
	print("Rückgabewerte")
	check(Trouble.code_kind(0) == "", "0: normal beendet")
	check(Trouble.code_kind(1) == "", "1: Fehler, aber kein Absturz")
	check(Trouble.code_kind(0xC0000005) == "absturz", "0xC0000005 (Zugriffsverletzung): Absturz")
	check(Trouble.code_kind(0xC0000409) == "absturz", "0xC0000409 (Puffer/abort): Absturz")
	check(Trouble.code_kind(0x80000003) == "absturz", "0x80000003 (Haltepunkt): Absturz")
	check(Trouble.code_kind(0xC000013A) == "", "0xC000013A (Konsole geschlossen): kein Absturz")
	check(Trouble.code_kind(0xFFFFFFFF) == "", "0xFFFFFFFF (hart beendet): kein Absturz")
	check(Trouble.code_kind(0xC0000135) == "laden", "0xC0000135 (DLL fehlt): nicht geladen")
	check(Trouble.code_kind(0xC000007B) == "laden", "0xC000007B (32/64 Bit): nicht geladen")
	check(Trouble.hex(0xC0000005) == "0xC0000005", "Schreibweise 0xC0000005")
	check(Trouble.wer_code("c0000005") == "0xC0000005", "Code aus dem Protokoll → 0xC0000005")
	check(Trouble.wer_code("0xc0000409") == "0xC0000409", "auch mit 0x davor")
	check(Trouble.wer_code("") == "", "leer bleibt leer")


func _verdict() -> void:
	print("Absturz oder nicht?")
	check(Trouble.verdict({ "quit": true, "code": 0xC0000005, "wer": { "found": true } }).is_empty(), "über Uzai beendet: nie ein Absturz")
	var w := Trouble.verdict(
			{ "kind": "steam", "secs": 900, "window": true, "steam_seen": true, "wer": { "found": true, "code": "c0000005", "module": "d3d11.dll" } })
	check(w.kind == "absturz" and w.code == "0xC0000005" and w.module == "d3d11.dll", "Absturzbericht von Windows (auch bei Steam)")
	var c := Trouble.verdict({ "kind": "rom", "secs": 600, "window": true, "code": 0xC0000005 })
	check(c.kind == "absturz" and c.code == "0xC0000005", "Rückgabewert einer Ausnahme")
	var l := Trouble.verdict({ "kind": "pc", "secs": 1, "window": false, "code": 0xC0000135 })
	check(l.kind == "start" and l.why == "laden", "DLL fehlt: nicht richtig gestartet")
	var s := Trouble.verdict({ "kind": "pc", "secs": 3, "window": false, "code": 1 })
	check(s.kind == "start" and s.why == "code" and int(s.secs) == 3, "kurz, ohne Fenster, Fehlercode: Fehlstart")
	check(Trouble.verdict({ "kind": "pc", "secs": 3, "window": true, "code": 1 }).is_empty(), "mit Fenster: kein Fehlstart")
	check(Trouble.verdict({ "kind": "pc", "secs": 3, "window": false, "code": 0 }).is_empty(), "Starter gibt mit 0 weiter: nichts")
	check(Trouble.verdict({ "kind": "pc", "secs": 3, "window": false }).is_empty(), "Rückgabewert unbekannt: nichts behaupten")
	check(Trouble.verdict({ "kind": "pc", "secs": 1800, "window": false, "code": 1 }).is_empty(), "lange gelaufen: kein Fehlstart")
	var st := Trouble.verdict({ "kind": "steam", "secs": 181, "window": false, "steam_seen": false })
	check(st.kind == "start" and st.why == "steam", "Steam hat das Spiel nie gestartet")
	check(Trouble.verdict({ "kind": "steam", "secs": 181, "window": true, "steam_seen": false }).is_empty(),
			"Steam zeigte ein Fenster (Update, Anmeldung): nichts")
	check(Trouble.verdict({ "kind": "steam", "secs": 4000, "window": true, "steam_seen": true }).is_empty(), "Steam-Spiel normal beendet: nichts")
	check(Trouble.verdict({ "kind": "epic", "secs": 5, "window": false, "wer": { "found": false } }).is_empty(), "Epic ohne Bericht: nichts")


func _texts() -> void:
	print("Texte der Karte")
	check(Trouble.headline("Okami", { "kind": "absturz" }) == "Okami ist abgestürzt", "Überschrift Absturz")
	check(Trouble.headline("Okami", { "kind": "start" }) == "Okami ist nicht richtig gestartet", "Überschrift Fehlstart")
	check(Trouble.what_happened({ "kind": "absturz", "why": "windows", "code": "0xC0000005", "module": "d3d11.dll" }).contains("d3d11.dll"),
			"nennt das Modul aus dem Bericht")
	check(Trouble.what_happened({ "kind": "absturz", "why": "code", "code": "0xC0000005", "module": "" }).contains("0xC0000005"), "nennt den Fehlercode")
	check(Trouble.what_happened({ "kind": "start", "why": "code", "code": "1", "secs": 3 }).contains("3 Sekunden"), "nennt die Laufzeit")
	check(Trouble.what_happened({ "kind": "start", "why": "steam" }) == "Steam hat das Spiel nicht gestartet.", "Steam ohne Start")


func _tips() -> void:
	print("Tipps je Quelle")
	var steam := Trouble.tips({ "source": "steam", "appid": 220 }, { "kind": "absturz" })
	check(_ids(steam) == ["validate"], "Steam: „Dateien prüfen“")
	check(" ".join(steam.lines).contains("Spieldateien"), "Steam: sagt vorher, was die Prüfung tut")
	var epic := Trouble.tips({ "source": "epic" }, { "kind": "absturz" })
	check(_ids(epic).is_empty() and " ".join(epic.lines).contains("Überprüfen"), "Epic: nur der Weg im Launcher, kein Knopf")
	var ps2 := Trouble.tips({ "source": "rom", "system": "ps2" }, { "kind": "absturz" })
	check(_ids(ps2) == ["emulator"], "Emulator: Knopf zu den Emulator-Einstellungen")
	check(" ".join(ps2.lines).contains("das BIOS deiner eigenen Konsole") and " ".join(ps2.lines).contains("Nicht enthalten"),
			"PS2: BIOS-Hinweis, ohne eins anzubieten")
	var snes := Trouble.tips({ "source": "rom", "system": "snes" }, { "kind": "absturz" })
	check(not " ".join(snes.lines).contains("BIOS"), "SNES: kein BIOS-Hinweis")
	var pc := Trouble.tips({ "source": "pc", "path": "C:/Spiele/a/a.exe" }, { "kind": "start", "why": "laden" })
	check(_ids(pc) == ["options"], "PC-Spiel: Knopf zu den Spieloptionen")
	check(" ".join(pc.lines).contains("Arbeitsordner") and " ".join(pc.lines).contains("_CommonRedist"),
			"PC-Spiel: Arbeitsordner, bei fehlender DLL die Laufzeitpakete")
	var link := Trouble.tips({ "source": "pc", "url": "goggalaxy://openGameView/1" }, { "kind": "absturz" })
	check(_ids(link).is_empty() and " ".join(link.lines).contains("Launcher"), "Verknüpfung: über den Launcher, keine Spieloptionen")
	for t in [steam, epic, ps2, snes, pc, link]:
		check((t.actions as Array).size() <= 1, "höchstens ein Knopf neben „Neu starten“ (%s)" % str(_ids(t)))


func _ids(t: Dictionary) -> Array:
	return (t.actions as Array).map(func(a: Array) -> String: return str(a[1]))


func _first_aid() -> void:
	print("Erste Hilfe")
	check(Trouble.FIRST_AID.size() == 10, "zehn Probleme")
	var cats := SettingsView.CATS.map(func(c: Array) -> String: return str(c[0]))
	var simple := ["pad_help", "pad_test", "audio", "scan", "tools", "safe"]
	var titles := {}
	for p in Trouble.FIRST_AID:
		var pd: Dictionary = p
		titles[str(pd.title)] = true
		var n := (pd.steps as Array).size()
		check(n >= 2 and n <= 4, "%s: %d kurze Schritte" % [pd.title, n])
		check((pd.actions as Array).size() >= 1 and (pd.actions as Array).size() <= 2, "%s: ein oder zwei Knöpfe" % pd.title)
		check(IconsS.P.has(str(pd.icon)), "%s: Symbol „%s“ gibt es" % [pd.title, pd.icon])
		check(str(pd.desc) != "", "%s: Kurzbeschreibung" % pd.title)
		for a in pd.actions:
			var id := str(a[1])
			var ok := simple.has(id) or (id.begins_with("seite:") and cats.has(id.trim_prefix("seite:").get_slice("/", 0).get_slice("#", 0)))
			check(ok, "%s: Knopf „%s“ führt zu etwas, das es gibt (%s)" % [pd.title, a[0], id])
	check(titles.size() == 10, "alle Titel verschieden")

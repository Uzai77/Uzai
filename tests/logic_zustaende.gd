extends Node
## Zustandsautomaten (src/core/zustand.gd): Tabellen-Regeln (gleich bleiben, "*", Endzustand),
## Verstöße werden nur festgehalten und ändern nichts, lage()/lage_text()/verlauf() für Fehlerbericht
## und Absturz-Markierung, ein Feld mit Setter wie in Uzai, und die echten Automaten von Uzai
## (docs/zustaende.json, erzeugt von tools/zustaende.py): jede Tabelle geschlossen, jeder Startzustand
## darin. Aufruf: godot --headless --path . res://tests/logic_zustaende.tscn

const Zustand := preload("res://src/core/zustand.gd")
const CrashGuard := preload("res://src/core/crash_guard.gd")

## Wie ein Automat in Uzai (Namen mit "probe." melden Verstöße nicht als Zeile – sie sind hier gewollt).
const ZUSTAENDE_PROBE := { "*": ["fehler"], "": ["laedt"], "laedt": ["ok", "fehler"], "ok": [], "fehler": ["laedt"] }


class Probe:
	extends RefCounted
	var stand := "":
		set(neu):
			Zustand.wechsel("probe.feld", ZUSTAENDE_PROBE, stand, neu)
			stand = neu


var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_regeln()
	_feld()
	_lage()
	_bericht()
	_uzai()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _regeln() -> void:
	var t := ZUSTAENDE_PROBE
	check(Zustand.erlaubt(t, "", "laedt") and Zustand.erlaubt(t, "laedt", "ok"), "erlaubte Wechsel laut Tabelle")
	check(Zustand.erlaubt(t, "ok", "ok"), "gleich bleiben ist immer erlaubt")
	check(Zustand.erlaubt(t, "ok", "fehler") and Zustand.erlaubt(t, "", "fehler"), "\"*\": von überall erreichbar")
	check(not Zustand.erlaubt(t, "ok", "laedt") and not Zustand.erlaubt(t, "", "ok"), "nicht in der Tabelle: nicht erlaubt")
	check(not Zustand.erlaubt(t, "", "gibtsnicht") and not Zustand.erlaubt({}, "a", "b"), "unbekannte Zustände und leere Tabelle")
	check(not Zustand.erlaubt({ "!": ["a"], "a": [], "b": [] }, "a", "b"), "\"!\" erlaubt nichts, es markiert nur Endzustände")


func _feld() -> void:
	Zustand.leeren()
	var p := Probe.new()
	p.stand = "laedt"
	p.stand = "ok"
	check(p.stand == "ok" and Zustand.verstoesse().is_empty(), "Setter: erlaubte Wechsel, keine Verstöße")
	p.stand = "laedt"
	check(p.stand == "laedt", "Verstoß ändert nichts: der Wert steht trotzdem da (wie vorher)")
	var v := Zustand.verstoesse()
	check(v.size() == 1 and v[0] == ["probe.feld", "ok", "laedt"], "Verstoß festgehalten: Name, alt, neu")
	p.stand = "ok"
	p.stand = "laedt"
	check(Zustand.verstoesse().size() == 2, "jeder Verstoß zählt (gemeldet wird jede Art nur einmal)")
	var vl := Zustand.verlauf()
	check(vl.size() == 5 and str(vl[0][3]) == "laedt" and not bool(vl[2][4]), "Verlauf: jeder Wechsel mit „erlaubt“")
	for i in Zustand.VERLAUF_MAX + 10:
		p.stand = "fehler" if i % 2 == 0 else "laedt"
	check(Zustand.verlauf().size() == Zustand.VERLAUF_MAX, "Verlauf bleibt klein (höchstens %d)" % Zustand.VERLAUF_MAX)


func _lage() -> void:
	Zustand.leeren()
	Zustand.wechsel("probe.a", ZUSTAENDE_PROBE, "", "laedt")
	Zustand.melden("probe.b", "bereit")
	Zustand.melden("probe.b", "bereit")
	Zustand.wechsel("probe.c", ZUSTAENDE_PROBE, "", "")
	var l := Zustand.lage()
	check(l.size() == 3 and str(l[0].name) == "probe.a" and str(l[0].zustand) == "laedt" and int(l[0].seit_s) == 0,
		"lage(): jeder Automat mit Stand und Dauer, nach Name")
	check(Zustand.verlauf().size() == 2, "melden(): nur echte Wechsel im Verlauf")
	var txt := Zustand.lage_text()
	check(txt.size() == 2 and txt[0].begins_with("probe.a: laedt") and txt[0].ends_with("(seit 0 s)"),
		"lage_text(): nur Automaten mit Stand, kurz; was gerade etwas tut, zuerst")
	check(txt[1].begins_with("probe.b: bereit"), "ruhige Stände (bereit, aus …) hinten")
	Zustand.vergessen("probe.a")
	check(Zustand.lage().size() == 2 and not Zustand.lage_text()[0].begins_with("probe.a"), "vergessen(): Ebene zu, kein alter Stand")
	check(Zustand._dauer(59) == "59 s" and Zustand._dauer(600) == "10 min" and Zustand._dauer(10800) == "3 h", "Dauer lesbar")
	Zustand.leeren()
	check(Zustand.lage().is_empty() and Zustand.verlauf().is_empty() and Zustand.verstoesse().is_empty(), "leeren()")


## Der Fehlerbericht nennt die Zustände (nur Namen, nie Daten) – auch für das letzte unerwartete Ende.
func _bericht() -> void:
	var info := { "version": "0.0.0", "os": "Linux", "godot": "4.5.1", "gpu": "GPU",
		"zustaende": PackedStringArray(["musik.playlists: laedt (seit 2 min)", "browser.modus: seite (seit 5 s)"]) }
	var r := CrashGuard.build(info, PackedStringArray(["ERROR: x"]))
	check(str(r.text).contains("**Zustände**") and str(r.text).contains("musik.playlists: laedt (seit 2 min)"),
		"Fehlerbericht: Abschnitt Zustände")
	var ohne := CrashGuard.build({ "version": "0.0.0" }, PackedStringArray())
	check(not str(ohne.text).contains("**Zustände**"), "ohne Zustände kein leerer Abschnitt")


## Die echten Automaten: die Übersicht (docs/zustaende.json) passt zu Uzai und jede Tabelle ist geschlossen.
func _uzai() -> void:
	var f := FileAccess.open("res://docs/zustaende.json", FileAccess.READ)
	check(f != null, "docs/zustaende.json da (python3 -I tools/zustaende.py)")
	if f == null:
		return
	var liste: Variant = JSON.parse_string(f.get_as_text())
	check(liste is Array and not (liste as Array).is_empty(), "mindestens ein Automat")
	if not (liste is Array):
		return
	var namen := {}
	for m in liste:
		var t: Dictionary = m.tabelle
		var schluessel := t.keys().filter(func(k: String) -> bool: return k != "*" and k != "!")
		var geschlossen := true
		for k in t:
			for w in t[k]:
				if not schluessel.has(w):
					geschlossen = false
		if not geschlossen or (m.start != null and not schluessel.has(str(m.start))) or namen.has(m.name):
			check(false, "%s: Tabelle geschlossen, Start darin, Name einmalig" % m.name)
		namen[m.name] = true
		check(ResourceLoader.exists("res://" + str(m.datei)), "%s: Datei %s da" % [m.name, m.datei])
	check(true, "%d Automaten geprüft" % (liste as Array).size())

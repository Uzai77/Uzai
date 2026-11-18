extends RefCounted
## Zustandsautomaten an einer Stelle (Übersicht: docs/ZUSTAENDE.md, erzeugt von tools/zustaende.py).
## Viele Teile von Uzai merken sich ihren Stand als Text („laedt“, „bereit“, „fehler“ …). Jeder
## solche Automat nennt seine erlaubten Wechsel als Tabelle direkt neben dem Feld und meldet jeden
## Wechsel hier:
##
##   ## Playlists: laden, da oder Fehler.
##   const ZUSTAENDE_PLAYLISTS := { "": ["laedt"], "laedt": ["ok", "fehler"], "ok": ["laedt"], "fehler": ["laedt"] }
##   var playlists_state := "":
##   	set(neu):
##   		Zustand.wechsel("musik.playlists", ZUSTAENDE_PLAYLISTS, playlists_state, neu)
##   		playlists_state = neu
##
## Tabelle: Schlüssel = Zustand, Wert = erlaubte Folgezustände (Endzustand: leere Liste). Der
## Schlüssel "*" nennt Zustände, die von überall erreichbar sind (Fehler, Aus, Zurücksetzen), "!"
## Zustände, die bewusst ohne Ausgang bleiben (z. B. ein Modus für die ganze Sitzung) – sonst warnt
## tools/zustaende.py bei einem Zustand ohne Ausgang (Spinner, der für immer bleibt).
## Gleich bleiben ist immer erlaubt. Tabellen heißen ZUSTAENDE oder ZUSTAENDE_…
##
## Zustand ändert NIE das Verhalten: Ein Wechsel außerhalb der Tabelle wird übernommen wie bisher
## und nur festgehalten – in Tests als Zeile „ZUSTAND-VERSTOSS …“ (tools/run_tests.sh zählt sie als
## Fehler), im fertigen Programm einmal je Art in logs/zustaende.log. lage() nennt alle Automaten
## mit Stand und Dauer (Fehlerbericht, Absturz-Markierung), verlauf() die letzten Wechsel – nur
## Namen von Zuständen, nie Daten. Ohne Godot prüft tools/zustaende.py (läuft im Lint mit) die
## Tabellen: jeder zugewiesene Zustand steht darin, jeder ist erreichbar, die Übersicht ist aktuell.
##
## Geprüft in tests/logic_zustaende.gd.

const Logdatei := preload("res://src/core/logdatei.gd")

const VERLAUF_MAX := 64
const VERSTOESSE_MAX := 200
const LOG := "logs/zustaende.log"
const LOG_MAX_BYTES := 200000
## Namen, die mit diesem Präfix beginnen, melden Verstöße nie als Zeile (Tests des Bausteins selbst).
const STILL := "probe."
## Zustände, die nur Ruhe bedeuten: Im Fehlerbericht stehen sie hinten, damit ein hängender Ablauf
## („laedt seit 10 min“) nicht hinter vielen ruhigen Automaten verschwindet.
const RUHE := ["", "aus", "ruhe", "menue", "zu", "fertig", "ok", "bereit", "done", "start", "home", "laufen", "keine"]

static var _jetzt := {}            ## Name → [Zustand, seit ms]
static var _verlauf: Array = []    ## [ms, Name, alt, neu, erlaubt]
static var _verstoesse: Array = [] ## [Name, alt, neu]
static var _gemeldet := {}         ## "Name|alt|neu" → true: jede Art nur einmal ins Protokoll


## Erlaubt die Tabelle den Wechsel? Gleich bleiben immer; "*" von überall.
static func erlaubt(tabelle: Dictionary, alt: String, neu: String) -> bool:
	if alt == neu:
		return true
	var ueberall: Variant = tabelle.get("*", [])
	if ueberall is Array and (ueberall as Array).has(neu):
		return true
	var ziele: Variant = tabelle.get(alt, [])
	return ziele is Array and (ziele as Array).has(neu)


## Ein Wechsel von alt nach neu. Gibt zurück, ob die Tabelle ihn erlaubt. Übernehmen muss ihn der
## Aufrufer selbst (immer, wie bisher) – Zustand hält nur fest.
static func wechsel(name: String, tabelle: Dictionary, alt: String, neu: String) -> bool:
	var ms := Time.get_ticks_msec()
	if alt == neu:
		if not _jetzt.has(name):
			_jetzt[name] = [neu, ms]
		return true
	var ok := erlaubt(tabelle, alt, neu)
	_jetzt[name] = [neu, ms]
	_verlauf.append([ms, name, alt, neu, ok])
	if _verlauf.size() > VERLAUF_MAX:
		_verlauf.pop_front()
	if not ok:
		_verstoss(name, alt, neu)
	return ok


## Ein Automat, dessen Stand nicht in einem Feld mit Setter liegt (Einstellung, Wörterbuch):
## nur den Stand melden, ohne Prüfung (für lage() und verlauf()).
static func melden(name: String, zustand: String) -> void:
	var alt: Variant = _jetzt.get(name)
	if alt is Array and str(alt[0]) == zustand:
		return
	var ms := Time.get_ticks_msec()
	_verlauf.append([ms, name, str(alt[0]) if alt is Array else "", zustand, true])
	if _verlauf.size() > VERLAUF_MAX:
		_verlauf.pop_front()
	_jetzt[name] = [zustand, ms]


## Ein Automat ist weg (Ebene geschlossen): aus lage() nehmen, damit kein alter Stand im
## Fehlerbericht steht. Der Verlauf bleibt.
static func vergessen(name: String) -> void:
	_jetzt.erase(name)


## Alle bekannten Automaten: [{ name, zustand, seit_s }], nach Name sortiert.
static func lage() -> Array:
	var out: Array = []
	var ms := Time.get_ticks_msec()
	var namen := _jetzt.keys()
	namen.sort()
	for n in namen:
		var e: Array = _jetzt[n]
		out.append({ "name": str(n), "zustand": str(e[0]), "seit_s": int((ms - int(e[1])) / 1000) })
	return out


## Kurz für Fehlerbericht und Absturz-Markierung: „name: zustand (seit 12 s)“ je Zeile, nur Automaten
## mit Stand (leer heißt: noch nichts passiert), höchstens n Zeilen. Zuerst, was gerade etwas tut
## (längster Stand zuerst: hängt etwas?), danach die ruhigen (RUHE), zuletzt gewechselte zuerst.
static func lage_text(n := 14) -> PackedStringArray:
	var l := lage().filter(func(e: Dictionary) -> bool: return str(e.zustand) != "")
	var aktiv := l.filter(func(e: Dictionary) -> bool: return not RUHE.has(str(e.zustand)))
	var ruhig := l.filter(func(e: Dictionary) -> bool: return RUHE.has(str(e.zustand)))
	aktiv.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.seit_s) > int(b.seit_s))
	ruhig.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.seit_s) < int(b.seit_s))
	var out := PackedStringArray()
	for e in (aktiv + ruhig).slice(0, n):
		out.append("%s: %s (seit %s)" % [e.name, e.zustand, _dauer(int(e.seit_s))])
	return out


## Die letzten Wechsel (älteste zuerst): [ms, Name, alt, neu, erlaubt].
static func verlauf() -> Array:
	return _verlauf.duplicate(true)


## Festgehaltene Verstöße dieses Laufs: [Name, alt, neu].
static func verstoesse() -> Array:
	return _verstoesse.duplicate(true)


## Alles vergessen (Tests).
static func leeren() -> void:
	_jetzt.clear()
	_verlauf.clear()
	_verstoesse.clear()
	_gemeldet.clear()


static func _verstoss(name: String, alt: String, neu: String) -> void:
	_verstoesse.append([name, alt, neu])
	if _verstoesse.size() > VERSTOESSE_MAX:
		_verstoesse.pop_front()
	var art := "%s|%s|%s" % [name, alt, neu]
	if _gemeldet.has(art):
		return
	_gemeldet[art] = true
	if name.begins_with(STILL):
		return
	var zeile := "ZUSTAND-VERSTOSS %s: \"%s\" -> \"%s\"" % [name, alt, neu]
	if OS.is_debug_build():
		printerr(zeile)
	_protokoll(zeile)


static func _protokoll(zeile: String) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or (ml as SceneTree).root == null:
		return
	var cfg: Node = (ml as SceneTree).root.get_node_or_null("Config")
	if cfg == null or not cfg.has_method("path"):
		return
	Logdatei.zeile(str(cfg.call("path", LOG)), zeile, LOG_MAX_BYTES)


static func _dauer(s: int) -> String:
	if s < 120:
		return "%d s" % s
	if s < 7200:
		return "%d min" % int(s / 60)
	return "%d h" % int(s / 3600)

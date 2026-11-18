extends Node
## Eingelegte PS1/PS2-Disc erkennen und das passende Spiel aus der Bibliothek nennen – oder die Disc
## direkt vom Laufwerk spielen.
##
## Unter Windows beobachtet der Helfer die optischen Laufwerke in einem eigenen Faden und liefert
## Name und SYSTEM.CNF der Disc; Uzai fragt diesen Stand alle 3 s ab (schneller Weg, wartet nie
## auf das Laufwerk). Die Seriennummer aus SYSTEM.CNF wird mit den Abbildern der Bibliothek
## abgeglichen (Library.game_for_serial: selbst zugeordnet, Nummer, sonst gleicher Titel laut
## Redump-Liste). Gibt es ein Abbild, startet es (schneller und leiser als das Laufwerk).
##
## Ohne Abbild spielt A die Disc direkt vom Laufwerk – ohne dass Uzai etwas anlegt: keine Kopie,
## keine .cue/.m3u, kein Eintrag in der Bibliothek. Das können die Emulatoren selbst (aus ihrem
## Quelltext geprüft, Stand Oktober 2026): DuckStation nimmt das Laufwerk als „\\.\E:“ statt
## einer Datei, PCSX2 mit „-disc E:\“. Für andere Emulatoren bleibt „Abbild zuordnen“.
##
## Abgefragt wird nur, wenn es PS1/PS2-Spiele in der Bibliothek gibt oder ein Emulator die Disc
## direkt spielen kann, und nicht im Spiel. Zum Testen ohne Laufwerk: UZAI_DISC_ROOT zeigt auf
## einen Ordner, der wie die Wurzel einer Disc gelesen wird.

const Fremd := preload("res://src/core/fremd.gd")

signal changed(inserted: bool)

const DiscSerial := preload("res://src/library/disc_serial.gd")
const RomScanner := preload("res://src/library/rom_scanner.gd")
const POLL_S := 3.0
## Der schnelle Helfer-Weg startet 4 s nach dem Helfer; erst danach abfragen, sonst liefe die
## Beobachtung auch im Hauptweg an.
const FIRST_S := 6.0

var serial := ""       ## Seriennummer der eingelegten PS-Disc ("" = keine)
var system := ""       ## "ps1" oder "ps2" laut SYSTEM.CNF
var drive := ""        ## Laufwerk („E:\“)
var game_id := ""      ## passendes Spiel ("" = kein Abbild in der Bibliothek)
var disc_name := ""    ## Name laut Redump-Liste („Ico (Europe) (En,Fr,De,Es,It)“, "" = unbekannt)
var polls := 0         ## Abfragen bisher (für Tests)
var _not_ready := 0    ## so oft hintereinander ohne Nummer im Laufwerk der Disc (dreht herunter oder an)
var _entry := {}       ## Eintrag der Disc ohne Abbild (bleibt derselbe, damit Bilder gemerkt bleiben)
var _busy := false
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(poll)
	add_child(_timer)
	get_tree().create_timer(FIRST_S).timeout.connect(func() -> void:
		_timer.start()
		poll()
	)
	Library.changed.connect(_rematch)
	# Die Bibliothek meldet neue Spiele schon vor den Seriennummern der Discs: am Ende des
	# Einlesens noch einmal zuordnen.
	Library.scan_state.connect(func(text: String) -> void:
		if text == "":
			_rematch()
	)


## Das Spiel zur eingelegten Disc ({} wenn keine Disc oder kein passendes Abbild).
func game() -> Dictionary:
	return Library.get_game(game_id) if game_id != "" else {}


func is_disc_game(g: Dictionary) -> bool:
	return game_id != "" and str(g.get("id", "")) == game_id


func poll() -> void:
	if _busy or Launcher.in_game or Library.demo:
		return
	if not Library.has_disc_games() and serial == "" and not direct_any():
		return
	var drives: Array = []
	var root := Config.probe_env("UZAI_DISC_ROOT")
	if root != "":
		drives = _folder_drive(root)
	elif Config.is_windows():
		_busy = true
		var r := await Helper.run("discs", {}, 5.0)
		_busy = false
		if not r.ok:
			return
		var parsed: Variant = Fremd.json_roh(str((r.result as Dictionary).get("json", "[]")) if r.result is Dictionary else "[]")
		drives = parsed if parsed is Array else []
	else:
		return
	polls += 1
	apply_drives(drives)


## Ordner als Disc-Wurzel lesen (Test ohne Laufwerk).
static func _folder_drive(root: String) -> Array:
	var cnf := root.path_join("SYSTEM.CNF")
	if not FileAccess.file_exists(cnf):
		return [{ "drive": root, "ready": false, "label": "", "cnf": "" }]
	return [{ "drive": root, "ready": true, "label": "", "cnf": FileAccess.get_file_as_string(cnf) }]


## Stand der Laufwerke übernehmen: die erste eingelegte PS-Disc zählt. Meldet das Laufwerk mit
## der Disc nur kurz „nicht bereit“ oder bereit ohne Nummer (sie dreht herunter, läuft an oder
## wird gerade gelesen), gilt sie erst beim zweiten Mal hintereinander als entfernt – sonst baute
## sich die Startseite immer wieder neu auf und alle Bilder luden neu. Eine Musik-CD beendet die
## Disc also beim zweiten Abfragen, ganz ohne Laufwerk sofort.
func apply_drives(drives: Array) -> void:
	var busy := false
	for d in drives:
		if not (d is Dictionary):
			continue
		if bool(d.get("ready", false)):
			var c := DiscSerial.from_cnf(str(d.get("cnf", "")))
			if str(c.serial) != "":
				_not_ready = 0
				set_disc(str(c.serial), str(c.system), str(d.get("drive", "")))
				return
		if serial != "" and str(d.get("drive", "")) == drive:
			busy = true
	if busy:
		_not_ready += 1
		if _not_ready < 2:
			return
	_not_ready = 0
	set_disc("", "", "")


## Disc setzen (auch für Demo und Tests). Meldet nur Änderungen. Findet Uzai kein Abbild, wird
## erst die Redump-Liste des Systems geladen (einmal, dann aus dem Cache): Sie nennt den Namen
## der Disc und findet das Abbild oft doch noch (anderer Dateiname, andere Region).
func set_disc(s: String, sys := "", drv := "") -> void:
	s = DiscSerial.normalize(s) if s != "" else ""
	if s == serial:
		return
	serial = s
	system = sys
	drive = drv
	disc_name = Library.disc_name(s, sys) if s != "" else ""
	var g := Library.game_for_serial(s, sys) if s != "" else {}
	game_id = str(g.get("id", ""))
	if s != "" and game_id == "" and sys != "" and not Library.disc_db_ready(sys):
		await Library.ensure_disc_db(sys)
		if serial != s:
			return
		disc_name = Library.disc_name(s, sys)
		game_id = str(Library.game_for_serial(s, sys).get("id", ""))
	changed.emit(s != "")


## Nach einem neuen Bibliotheks-Scan (oder einer Zuordnung) kann es zur Disc jetzt ein Abbild
## geben (oder keins mehr).
func _rematch() -> void:
	if serial == "":
		return
	disc_name = Library.disc_name(serial, system)
	var id := str(Library.game_for_serial(serial, system).get("id", ""))
	if id != game_id:
		game_id = id
		changed.emit(true)


## Kurzer Name der Disc („Ico“), sonst „PS2-Disc“.
func title() -> String:
	if disc_name != "":
		return RomScanner.clean_title(disc_name)
	return "%s-Disc" % str(Config.system(system).get("short", "PS"))


## Eingelegte Disc ohne Abbild als Eintrag für die Startseite ({} wenn keine oder mit Abbild).
## source „disc“: kein Spiel der Bibliothek, A ordnet ein Abbild zu.
func entry() -> Dictionary:
	if serial == "" or game_id != "":
		return {}
	if str(_entry.get("serial", "")) != serial:
		_entry = { "id": "disc:" + serial, "serial": serial }
	_entry["title"] = title()
	_entry["libretro_name"] = disc_name
	_entry["system"] = system
	_entry["source"] = "disc"
	return _entry


## Der Disc ein Abbild zuordnen (bleibt gespeichert). "" löst die eigene Zuordnung.
func link(gid: String) -> void:
	if serial == "":
		return
	Library.link_disc(serial, gid)
	_rematch()


## Zuordnungen wurden anderswo geändert (Spieloptionen): neu abgleichen.
func link_changed() -> void:
	_rematch()


# --- Direkt vom Laufwerk -------------------------------------------------------------------

## Emulatoren, die eine Disc direkt vom Laufwerk lesen (Kennung → System).
const DIRECT := { "duckstation": "ps1", "pcsx2": "ps2" }


## Laufwerksbuchstabe aus „E:\“ bzw. „E:“ (groß), "" bei allem anderen – nie ein Pfad.
static func drive_letter(drv: String) -> String:
	var re := RegEx.create_from_string("^([A-Za-z]):[\\\\/]?$")
	var m := re.search(drv.strip_edges())
	return m.get_string(1).to_upper() if m else ""


## Startparameter, mit denen der Emulator die Disc im Laufwerk spielt ("" wenn er es nicht kann).
## template: die Parameter des Emulators mit {rom}. DuckStation bekommt das Laufwerk an Stelle der
## Datei; PCSX2 nimmt „-disc“ – das „--“ davor (alles danach wäre ein Dateiname) fällt weg.
static func direct_args(emu_id: String, template: String, drv: String) -> String:
	var l := drive_letter(drv)
	if l == "":
		return ""
	match emu_id:
		"duckstation":
			if not template.contains("{rom}"):
				return ""
			return template.replace("\"{rom}\"", "\\\\.\\%s:" % l).replace("{rom}", "\\\\.\\%s:" % l)
		"pcsx2":
			if not template.contains("{rom}"):
				return ""
			var t := template.replace("\"{rom}\"", "{rom}")
			var parts: Array = []
			for w in t.split(" ", false):
				if w != "--":
					parts.append(w)
			return " ".join(parts).replace("{rom}", "-disc %s:\\" % l)
	return ""


## Emulator für ein System, wenn er die Disc direkt spielen kann und eingerichtet ist ("" sonst).
static func direct_emulator(sys_id: String) -> String:
	var sys := Config.system(sys_id)
	if not bool(sys.get("enabled", false)):
		return ""
	var emu_id := str(sys.get("emulator", ""))
	if str(DIRECT.get(emu_id, "")) != sys_id:
		return ""
	var exe := str(Config.emulator(emu_id).get("exe", ""))
	return emu_id if exe != "" and FileAccess.file_exists(exe) else ""


## Kann irgendein eingeschaltetes System eine Disc direkt spielen? (Dann lohnt das Abfragen.)
static func direct_any() -> bool:
	return direct_emulator("ps1") != "" or direct_emulator("ps2") != ""


## Spielt A die eingelegte Disc direkt? (Disc ohne Abbild, passender Emulator eingerichtet.)
func can_play() -> bool:
	return serial != "" and game_id == "" and drive_letter(drive) != "" and direct_emulator(system) != ""


## Die eingelegte Disc als Spiel zum Starten: nur für diesen Start, nie in der Bibliothek.
## {} wenn es nicht geht.
func direct_game() -> Dictionary:
	if not can_play():
		return {}
	var e := entry().duplicate()
	e["source"] = "rom"
	e["emulator"] = direct_emulator(system)
	e["path"] = ""
	e["_disc_drive"] = drive
	return e

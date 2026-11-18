extends Node
## Controller koppeln (src/core/koppeln.gd, src/ui/layers/pad_pair.gd) mit nachgebauten Antworten des Helfers
## (bt-scan, bt-pair), alles ohne Windows: gekoppelt/verbunden, Controller ohne Klasse nach dem Namen, Reihenfolge,
## „n von 4 verbunden“, Neu koppeln (Argumente streng), neue Antworten, kaputte und fremde Antworten.
## Aufruf: godot --headless --path . res://tests/logic_koppeln.tscn

const Koppeln := preload("res://src/core/koppeln.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_suche()
	_koppeln()
	_kaputt()
	_oberflaeche()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


const A := "Bluetooth#Bluetooth00:1a:7d:da:71:13-"
const LE := "BluetoothLE#BluetoothLE00:1a:7d:da:71:13-"


## Eine Antwort von bt-scan, wie der Helfer sie schickt (JSON: Zahlen kommen als float).
func _antwort() -> Variant:
	return JSON.parse_string(JSON.stringify({ "code": "an", "gesehen": 9, "devices": [
		{ "id": A + "58:10:31:7a:0c:42", "name": "DualSense Wireless Controller", "major": 5, "minor": 2, "appearance": 0, "signal": -61, "paired": false, "connected": false },
		{ "id": LE + "c8:3f:26:4b:9e:01", "name": "Xbox Wireless Controller", "major": 0, "minor": 0, "appearance": 964, "signal": -50, "paired": false, "connected": false },
		{ "id": A + "98:b6:e9:20:5d:17", "name": "Pro Controller", "major": 0, "minor": 0, "appearance": 0, "signal": -100, "paired": false, "connected": false },
		{ "id": A + "e8:47:3a:01:9c:5d", "name": "Wireless Controller", "major": 5, "minor": 2, "appearance": 0, "signal": -100, "paired": true, "connected": false },
		{ "id": A + "e8:47:3a:01:9c:5e", "name": "Wireless Controller", "major": 5, "minor": 2, "appearance": 0, "signal": -100, "paired": true, "connected": true },
		{ "id": A + "00:1b:66:aa:10:02", "name": "Kopfhörer Controller", "major": 0, "minor": 0, "appearance": 0, "signal": -40, "paired": false },
		{ "id": A + "00:1b:66:aa:10:03", "name": "Bluetooth Keyboard", "major": 5, "minor": 0x10, "appearance": 0, "signal": -40 },
	] }))


func _suche() -> void:
	print("Suche: neue, gekoppelte und verbundene Controller")
	var sc := Koppeln.parse_scan(_antwort())
	var d: Array = sc.devices
	var namen: Array = d.map(func(x: Dictionary) -> String: return str(x.name))
	check(str(sc.state) == "an" and d.size() == 5, "fünf Controller, Kopfhörer und Tastatur fallen heraus (%s)" % str(namen))
	check(namen.slice(0, 3) == ["Xbox Wireless Controller", "DualSense Wireless Controller", "Pro Controller"], "neue zuerst, stärkstes Signal oben")
	check(Koppeln.rang(d[3]) == 1 and Koppeln.rang(d[4]) == 2, "dann gekoppelt und nicht verbunden, dann verbunden")
	check(d[2].family == "nintendo" and Koppeln.is_gamepad({ "name": "Pro Controller" }), "ohne Klasse: nach dem Namen (Pro Controller)")
	check(not Koppeln.is_gamepad({ "name": "Kopfhörer Controller" }) and not Koppeln.is_gamepad({ "major": 4, "minor": 6, "name": "Controller" }),
		"Name zählt nur ohne Klasse und nie bei Kopfhörern")
	check(Koppeln.verbunden(d) == 1, "ein Controller verbunden")
	check(not bool(Koppeln.parse_scan({ "devices": [{ "id": A + "11:11:11:11:11:11", "major": 5, "minor": 2, "paired": false, "connected": true }] }).devices[0].connected),
		"verbunden nur, wenn auch gekoppelt")
	check(Koppeln.MAX_PADS == 4 and Koppeln.TIPP.contains("neu koppeln"), "bis zu vier Controller; Tipp für „wird nicht gefunden“")
	for fam in ["xbox", "ps", "nintendo", "other"]:
		var t := " ".join(PackedStringArray(Koppeln.steps(fam)))
		check(t.length() > 30 and not t.contains("®") and not t.contains("™"), "Anleitung %s ohne Markenzeichen" % fam)


func _koppeln() -> void:
	print("Koppeln und Neu koppeln")
	var id := A + "e8:47:3a:01:9c:5d"
	var a := Koppeln.pair_args(id, false)
	var b := Koppeln.pair_args(id, true)
	check(a.id == id and int(a.neu) == 0 and int(b.neu) == 1 and int(b.timeout) > int(a.timeout), "Argumente: Kennung, neu 0/1, Zeit für Entkoppeln + Koppeln")
	check(Koppeln.pair_args(id + "\n", true).is_empty() and Koppeln.pair_args(42, true).is_empty() and Koppeln.pair_args("x; y", false).is_empty(), "falsche Kennung: keine Argumente")
	for c in ["gekoppelt", "schon", "entkoppelt", "bereit", "zeit", "pin", "abgelehnt", "laeuft", "fehlt", "klasse"]:
		check(Koppeln.pair_code({ "code": c }) == c, "Antwort %s bekannt" % c)
	check(Koppeln.pair_code({ "code": "entkoppelt; x" }) == "fehler" and Koppeln.pair_code({ "code": 5 }) == "fehler", "Unbekanntes: fehler")
	check(str(Koppeln.status("entkoppelt")[1]).contains("Kopplungsmodus") and str(Koppeln.status("getrennt")[1]).contains("Neu koppeln"), "Erklärungen für Neu koppeln")


func _kaputt() -> void:
	print("Kaputte und fremde Antworten")
	var bad := Koppeln.parse_scan({ "code": "an", "devices": [
		{ "id": A + "22:22:22:22:22:22", "name": "Pad", "major": "5", "minor": "2" },
		{ "id": A + "22:22:22:22:22:23", "name": ["x"], "major": 5, "minor": 2, "signal": "laut", "paired": "true" },
		{ "id": A + "22:22:22:22:22:24", "name": "Gamepad", "major": 5, "minor": 2, "signal": 1e30, "paired": 1 },
		{ "id": A + "22:22:22:22:22:25", "name": "Controller", "appearance": NAN, "major": INF },
	] })
	var d: Array = bad.devices
	check(d.size() == 3, "Klasse als Text zählt nicht (Name „Pad“ allein reicht nicht); %d übrig" % d.size())
	check(d.all(func(x: Dictionary) -> bool: return not bool(x.paired) and int(x.signal) >= -127 and int(x.signal) <= 0), "gekoppelt nur als echtes Ja, Signal begrenzt")
	check(str(d[0].name) == "Controller" or d.any(func(x: Dictionary) -> bool: return str(x.name) == "Controller"), "Name kein Text: „Controller“")
	check(Koppeln.parse_scan({ "code": "an", "devices": "x" }).devices.is_empty() and Koppeln.parse_scan(null).state == "fehler", "Liste kein Array, Antwort kein Objekt: leer bzw. fehler")


## Die Ebene im Quelltext: Neu koppeln nur nach Rückfrage, Argumente nur über pair_args, Zähler „von 4“.
func _oberflaeche() -> void:
	print("Ebene")
	var pp := FileAccess.get_file_as_string("res://src/ui/layers/pad_pair.gd")
	check(pp.contains("func _neu_fragen(") and pp.contains("[\"Neu koppeln\", func() -> void: _pair(d, true)]"), "Neu koppeln nur nach Rückfrage")
	check(pp.contains("Koppeln.pair_args(id, neu)") and pp.contains("Helper.run_once(\"bt-pair\", args)"), "Helfer bekommt nur geprüfte Argumente")
	check(pp.contains("Verbunden: %d von %d") and pp.contains("Uzai sucht weiter"), "mehrere Controller nacheinander: Zähler, Suche läuft weiter")

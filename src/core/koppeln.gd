extends RefCounted
## Controller koppeln (Punkt 133) ohne Oberfläche: welche Geräte Uzai überhaupt zeigt (nur die
## Gamepad-Klasse), wie eine Gerätekennung aussehen muss, bevor sie an den Helfer geht, was eine
## Antwort des Helfers bedeutet und wie man einen Controller in den Kopplungsmodus bringt.
## Getestet in tests/logic_einrichtung.gd; die Ebene dazu: src/ui/layers/pad_pair.gd.
##
## Der Helfer („bt-scan“, „bt-pair“ in helper/uzai-helper.ps1) spricht nur mit der offiziellen
## Windows-Schnittstelle (Windows.Devices.Enumeration, Windows.Devices.Bluetooth): keine Treiber,
## keine Adminrechte, Bluetooth schaltet Uzai nie selbst ein oder aus. Er prüft Kennung und Klasse
## noch einmal selbst – was hier steht, ist die erste von zwei Sperren.

## Kennung eines Bluetooth-Geräts, wie Windows sie vergibt („Bluetooth#Bluetooth<Adapter>-<Gerät>“,
## bei Bluetooth LE mit „LE“). \A und \z statt ^ und $: ein angehängter Zeilenumbruch passt nie.
const ID_RE := "\\ABluetooth(LE)?#Bluetooth(LE)?([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}-([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\\z"
static var _RX_ID := RegEx.create_from_string(ID_RE)
const ID_MAX := 80
const NAME_MAX := 60
const LIST_MAX := 16             ## mehr Controller sind in der Nähe nie in einem Wohnzimmer

## Bluetooth-Geräteklasse (Class of Device): Hauptklasse 5 = Peripherie; in der Unterklasse (6 Bit)
## stehen in den unteren vier Bit 1 = Joystick, 2 = Gamepad.
const COD_PERIPHERAL := 5
const COD_PAD := [1, 2]
## Bluetooth LE: Erscheinungsbild Kategorie 15 (Eingabegerät), Unterkategorie 3 Joystick, 4 Gamepad.
const LE_PAD := [0x03C3, 0x03C4]

## Antworten des Helfers → [Titel, Satz, Ton]. Ton: ok, warn, faint.
const STATUS := {
	"gekoppelt": ["Gekoppelt", "Controller verbunden.", "ok"],
	"schon": ["Schon gekoppelt", "Bereits gekoppelt. Einschalten genügt.", "ok"],
	"bereit": ["Nicht im Kopplungsmodus",
		"Der Controller hat nicht geantwortet. Kopplungsmodus noch einmal starten (Licht blinkt schnell) und gleich danach koppeln.", "warn"],
	"zeit": ["Zeit abgelaufen", "Der Controller hat zu lange gebraucht. Kopplungsmodus neu starten und noch einmal versuchen.", "warn"],
	"pin": ["Braucht eine PIN", "PIN nötig. In Windows unter Bluetooth und Geräte koppeln.", "warn"],
	"abgelehnt": ["Abgelehnt", "Der Controller oder Windows hat das Koppeln abgelehnt. Kopplungsmodus neu starten und noch einmal versuchen.", "warn"],
	"fehlt": ["Nicht mehr da", "Controller nicht mehr sichtbar. Kopplungsmodus neu starten.", "warn"],
	"klasse": ["Kein Controller", "Kein Controller.", "warn"],
	"kennung": ["Ungültig", "Uzai hat die Kennung des Geräts nicht angenommen.", "warn"],
	"laeuft": ["Läuft schon", "Windows koppelt gerade schon ein Gerät. Kurz warten und noch einmal versuchen.", "warn"],
	"aus": ["Bluetooth ist aus",
		"Bluetooth in Windows einschalten (Windows + A).",
		"warn"],
	"kein": ["Kein Bluetooth", "Kein Bluetooth. USB-Kabel oder Funkadapter nutzen.",
		"warn"],
	"admin": ["Mit Adminrechten gestartet", "Uzai ohne Administratorrechte starten.", "warn"],
	"windows": ["Nur unter Windows", "Koppeln geht über Windows selbst – auf diesem System nicht.", "faint"],
	"helfer": ["Helfer antwortet nicht", "Windows-Helfer antwortet nicht. Erneut versuchen.",
		"warn"],
	"fehler": ["Ging nicht", "Windows hat das Koppeln nicht abgeschlossen. Kopplungsmodus neu starten und noch einmal versuchen.", "warn"],
	"entkoppelt": ["Alte Kopplung entfernt", "Jetzt den Kopplungsmodus starten und noch einmal A drücken.", "warn"],
	"verbunden": ["Verbunden", "Controller ist verbunden.", "ok"],
	"getrennt": ["Nicht verbunden", "Schon gekoppelt, verbindet sich aber nicht – oft nach einer Konsole. Neu koppeln hilft.", "warn"],
}

## So kommt ein Controller in den Kopplungsmodus (je Familie, wie in glyphs; Namen nur beschreibend, R4).
const STEPS := {
	"xbox": ["Mit der Xbox-Taste einschalten.",
		"Die kleine Verbindungstaste oben neben dem USB-Anschluss drei Sekunden halten, bis das Licht schnell blinkt."],
	"ps": ["Controller aus lassen.", "PS-Taste und Create (bzw. Share) zusammen halten, bis die Lichtleiste schnell doppelt blinkt."],
	"nintendo": ["Pro Controller: die kleine Sync-Taste oben halten, bis die Lichter hin und her laufen.", "Joy-Con: die Sync-Taste an der Schiene halten."],
	"other": ["Meist eine eigene Kopplungstaste drei Sekunden halten (manchmal Start + eine Taste), bis das Licht schnell blinkt.",
		"Mit Umschalter: vorher den Windows- bzw. X-Modus wählen."],
}
## Ein Satz unter der Anleitung: was bei „wird nicht gefunden“ meist hilft.
const TIPP := "War der Controller zuletzt an einer Konsole, unter „Gekoppelt“ neu koppeln."
const MAX_PADS := 4                ## so viele Spieler kennt Uzai

## Für die Vorführung (--demo) und die Proben: was eine Suche in einem Wohnzimmer findet.
const DEMO := [
	{ "id": "BluetoothLE#BluetoothLEa4:c3:f0:11:22:33-c8:3f:26:4b:9e:01", "name": "Xbox Wireless Controller", "major": 0, "minor": 0, "appearance": 0x03C4,
		"signal": -52 },
	{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-58:10:31:7a:0c:42", "name": "DualSense Wireless Controller", "major": 5, "minor": 2, "appearance": 0,
		"signal": -61 },
	{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-98:b6:e9:20:5d:17", "name": "Pro Controller", "major": 5, "minor": 2, "appearance": 0, "signal": -74 },
	{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-00:1b:66:aa:10:02", "name": "Kopfhörer", "major": 4, "minor": 6, "appearance": 0, "signal": -48 },
	{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-e8:47:3a:01:9c:5d", "name": "Wireless Controller", "major": 5, "minor": 2, "appearance": 0, "signal": -100,
		"paired": true, "connected": false },
	{ "id": "BluetoothLE#BluetoothLEa4:c3:f0:11:22:33-44:16:22:0d:7e:a1", "name": "Xbox Wireless Controller", "major": 0, "minor": 0, "appearance": 0x03C4,
		"signal": -58, "paired": true, "connected": true },
]


## Darf diese Kennung an den Helfer? Nur Text, nicht zu lang, genau im Windows-Format.
static func valid_id(id: Variant) -> bool:
	if not (id is String):
		return false
	var s := id as String
	if s.is_empty() or s.length() > ID_MAX:
		return false
	return _RX_ID.search(s) != null


## Gehört ein Gerät zur Gamepad-Klasse? d: { major, minor, appearance, name } wie vom Helfer. Kennt Windows die Klasse
## nicht (beides 0 – bei manchen Controllern erst nach dem Koppeln), zählt der Name (name_pad, wie im Helfer).
static func is_gamepad(d: Dictionary) -> bool:
	var major := _zahl(d.get("major", 0))
	var minor := _zahl(d.get("minor", 0))
	var look := _zahl(d.get("appearance", 0))
	if major == COD_PERIPHERAL and (minor & 0x0F) in COD_PAD:
		return true
	if look in LE_PAD:
		return true
	return major == 0 and look == 0 and name_pad(d.get("name", ""))


## Name eines Controllers (nur beschreibend, nur als Rückfall ohne Klasse) – dieselben Wörter wie UzBtSuche.NameIstPad.
const NAME_JA := ["controller", "gamepad", "joy-con", "dualsense", "dualshock", "8bitdo", "joystick"]
const NAME_NIE := ["keyboard", "tastatur", "mouse", "maus", "headset", "kopfhörer", "speaker", "lautsprecher", "buds", "watch", "tv", "remote control"]


static func name_pad(v: Variant) -> bool:
	if not (v is String) or (v as String).length() > 120:
		return false
	var n := (v as String).to_lower()
	for w in NAME_NIE:
		if n.contains(w):
			return false
	for w in NAME_JA:
		if n.contains(w):
			return true
	return false


## Zahl aus fremden Daten: nur int/float, sonst 0 (kein Text, kein Bool als Zahl).
static func _zahl(v: Variant) -> int:
	if v is int:
		return v
	if v is float and is_finite(v) and absf(v) < 1e9:
		return int(v)
	return 0


## Familie für Symbol und Anleitung: xbox, ps, nintendo oder other (nach dem Namen, den das Gerät
## von sich sagt – anders als bei den Tastensymbolen wird hier nichts angenommen).
static func family(name: String) -> String:
	var n := name.to_lower()
	if n.contains("xbox"):
		return "xbox"
	if n.contains("dualsense") or n.contains("dualshock") or n.contains("wireless controller") or n.contains("playstation"):
		return "ps"
	if n.contains("pro controller") or n.contains("joy-con") or n.contains("nintendo"):
		return "nintendo"
	return "other"


## Nur Druckbares, ohne Steuerzeichen und Zeilenumbrüche, gekürzt; leer → „Controller“.
static func clean_name(v: Variant) -> String:
	var out := ""
	for ch in (v as String if v is String else ""):
		var c := ch.unicode_at(0)
		if c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or c in [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]:
			continue
		out += ch
	out = out.strip_edges()
	if out.length() > NAME_MAX:
		out = out.left(NAME_MAX - 1).strip_edges() + "…"
	return out if out != "" else "Controller"


## Antwort auf „bt-scan“ → { state, devices: [{ id, name, family, le, signal }] }. state: „an“
## (Liste gilt), sonst ein Schlüssel aus STATUS. Kaputtes, Doppeltes, Fremdes und Geräte anderer
## Klassen fallen heraus; die stärksten Signale zuerst.
static func parse_scan(r: Variant) -> Dictionary:
	if not (r is Dictionary):
		return { "state": "fehler", "devices": [] }
	var d := r as Dictionary
	var state := str(d.get("code", "an"))
	if not STATUS.has(state) and state != "an":
		state = "fehler"
	var out: Array = []
	var seen := {}
	var list: Variant = d.get("devices", [])
	if list is Array:
		for e in list:
			if not (e is Dictionary) or out.size() >= LIST_MAX:
				continue
			var id: Variant = (e as Dictionary).get("id", "")
			if not valid_id(id) or seen.has(id) or not is_gamepad(e):
				continue
			seen[id] = true
			var nm := clean_name((e as Dictionary).get("name", ""))
			var gek: Variant = (e as Dictionary).get("paired", false)
			var ver: Variant = (e as Dictionary).get("connected", false)
			var paired: bool = gek is bool and gek
			out.append({ "id": str(id), "name": nm, "family": family(nm), "le": str(id).begins_with("BluetoothLE#"),
				"signal": clampi(_zahl((e as Dictionary).get("signal", -100)), -127, 0) if (e as Dictionary).has("signal") else -100,
				"paired": paired, "connected": paired and ver is bool and ver })
	# Neu gefundene zuerst (stärkstes Signal oben), dann gekoppelte, die nicht verbunden sind, dann verbundene.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := rang(a)
		var rb := rang(b)
		return ra < rb if ra != rb else int(a.signal) > int(b.signal))
	return { "state": state, "devices": out }


## Reihenfolge in der Liste: 0 neu, 1 gekoppelt und nicht verbunden, 2 verbunden.
static func rang(d: Dictionary) -> int:
	if not bool(d.get("paired", false)):
		return 0
	return 2 if bool(d.get("connected", false)) else 1


## Wie viele Controller schon verbunden sind (aus der Suche): für „2 von 4 verbunden“.
static func verbunden(devices: Array) -> int:
	return devices.filter(func(d: Dictionary) -> bool: return rang(d) == 2).size()


## Argumente für „bt-pair“: Kennung geprüft, neu nur 0/1. {} wenn die Kennung nicht passt.
static func pair_args(id: Variant, neu: bool) -> Dictionary:
	if not valid_id(id):
		return {}
	return { "id": str(id), "neu": 1 if neu else 0, "timeout": 100 if neu else 85 }


## Antwort auf „bt-pair“ → Schlüssel aus STATUS.
static func pair_code(r: Variant) -> String:
	if not (r is Dictionary):
		return "fehler"
	var code := str((r as Dictionary).get("code", ""))
	return code if STATUS.has(code) else "fehler"


## Signal in Balken (0–3) – nur zur Orientierung, welcher Controller der nahe ist.
static func bars(dbm: int) -> int:
	if dbm >= -60:
		return 3
	if dbm >= -72:
		return 2
	return 1 if dbm >= -85 else 0


static func status(code: String) -> Array:
	return STATUS.get(code, STATUS.fehler)


static func steps(fam: String) -> Array:
	return STEPS.get(fam, STEPS.other)

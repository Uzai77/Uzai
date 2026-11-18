extends Node
## Controller-Status wie im Xbox-Guide: welche Controller verbunden sind, Spieler-Nummer, Akku,
## Verbindung (Kabel, Funk, Bluetooth), eine kurze, leise Vibration bei Ereignissen und
## „Controller ausschalten“.
##
## Woher es kommt:
## - Xbox-/XInput-Controller (Windows): Der Controller-Wächter im Helfer liest Akku
##   (XInputGetBatteryInformation) und Verbindung (XInputGetCapabilities, kabellos-Flag; Bluetooth
##   an der Produktnummer) je Controller höchstens einmal pro Minute und sofort, wenn einer dazukommt.
##   Uzai fragt nur den letzten Stand ab ("pad-status", billig) – alle 30 s und wenn der Helfer
##   eine Änderung meldet.
## - Zweite Quelle für Xbox-Controller: Windows.Gaming.Input (Helfer, "wgi"). XInput meldet einen
##   Xbox-Controller über Bluetooth oft als „Kabel“ ohne Stand – dann (und bei unbekanntem Stand)
##   zählt diese Meldung, siehe apply_wgi.
## - PlayStation (DualSense, DualShock 4): Godot kennt keinen Akkustand. Der Helfer liest dafür
##   einmal pro Minute einen Eingabebericht über HID und schickt nur die Bytes, in denen der Akku
##   stehen kann; sony_battery wertet sie aus (wie der Linux-Treiber hid-playstation).
## - Alles andere (und ohne Windows): nur Name und Spieler aus Godot, Akku unbekannt.
##
## Für andere Teile von Uzai:
## - Pads.pads (Liste, siehe merge), Signal changed
## - Pads.pulse("achievement" | "clip" | "message" | "friend_online") – kurzer, leiser Impuls,
##   nur wenn die Einstellung es erlaubt (siehe pulse_allowed); true, wenn einer geschickt wurde
## - Pads.pulse("guide" | "auswahl" | "rand" | "fehler") – Haptik der Oberfläche (PULSES_UI), nur
##   mit „Vibration bei Haupthandlungen“ (controller.vibration) und nur, wenn Uzai vorn ist
## - Pads.power_off(pad), Pads.identify(pad), Pads.rumble(device, links, rechts, s)
## - Pads.benutzt_id(): der zuletzt benutzte Controller (für Spieler 1 im Emulator)
## - Controller-Test als Ebene: res://src/ui/layers/pad_test.gd (z. B. für die Ersteinrichtung)

signal changed

const POLL_S := 30.0
const PULSE_GAP_MS := 1200          ## zwei Ereignisse kurz hintereinander: nur ein Impuls
const SONY := 0x054C
const MICROSOFT := 0x045E
const SpielerS := preload("res://src/core/spieler.gd")
const Fremd := preload("res://src/core/fremd.gd")

## Kurze Impulse: [linker (tiefer) Motor, rechter (heller) Motor, ms]. Leise und nie über 150 ms.
const PULSES := {
	"clip": [0.0, 0.32, 90],
	"achievement": [0.16, 0.42, 140],
	"message": [0.0, 0.28, 70],
	"friend_online": [0.0, 0.2, 60],
	"test": [0.45, 0.45, 150],
}

## Haptik der Oberfläche (Plan „Gefühl“ 3.5): nur, wo etwas körperlich passiert, 25–60 ms. Der helle
## Motor steht für Klicks, der tiefe für Gewicht. [tief, hell, ms, zweiter Stoß nach ms (0: keiner)].
## Cursor, Reiter, Zurück und Schalter geben keinen Impuls.
const PULSES_UI := {
	"guide": [0.22, 0.0, 45, 0],        ## Guide auf, mit Punkt und Tick
	"auswahl": [0.0, 0.25, 35, 0],      ## Haupthandlungen: Spielen, Dialog bestätigen, Kaufen, Installieren
	"rand": [0.0, 0.12, 25, 0],         ## Rand, nur der erste Stoß je Halten
	"fehler": [0.2, 0.0, 30, 90],       ## Fehler: zweimal tief
}
const UI_MIN_MS := 25                   ## darunter spürt man Unwucht-Motoren kaum …
const UI_MAX_MS := 60                   ## … darüber wird es ein Brummen
const UI_GAP_MS := 150                  ## ein Druck: höchstens ein Impuls
const RAND_HALTEN_MS := 450             ## am Rand festgehalten: still, bis so lange kein Stoß mehr kam

const XBOX_NAMES := {
	0x028E: "Xbox 360 Controller", 0x0719: "Xbox 360 Wireless Controller",
	0x02D1: "Xbox One Controller", 0x02DD: "Xbox One Controller", 0x02EA: "Xbox One Controller",
	0x02E0: "Xbox One Controller", 0x02FD: "Xbox One Controller", 0x0B20: "Xbox One Controller",
	0x02E3: "Xbox Elite Controller", 0x0B00: "Xbox Elite Series 2", 0x0B05: "Xbox Elite Series 2",
	0x0B22: "Xbox Elite Series 2", 0x0B12: "Xbox Wireless Controller", 0x0B13: "Xbox Wireless Controller",
	0x0B0A: "Xbox Adaptive Controller", 0x0B21: "Xbox Adaptive Controller",
}
## Produktnummern der Xbox-Controller über Bluetooth (über den Funkadapter oder Kabel melden sie andere).
const XBOX_BT := [0x02E0, 0x02FD, 0x0B05, 0x0B13, 0x0B20, 0x0B21, 0x0B22]
const SONY_NAMES := { 0x0CE6: "DualSense", 0x0DF2: "DualSense Edge", 0x05C4: "DualShock 4", 0x09CC: "DualShock 4", 0x0BA0: "DualShock 4" }
## XINPUT_DEVSUBTYPE: was außer einem Gamepad noch an XInput hängt.
const SUBTYPES := { 2: "Lenkrad", 3: "Arcade-Stick", 4: "Flugstick", 5: "Tanzmatte", 6: "Gitarre", 7: "Gitarre", 8: "Schlagzeug", 11: "Bass", 19: "Arcade-Pad" }

## Für die Vorführung (--demo) und die Proben: ein Xbox-Controller über Funk, ein DualSense über Bluetooth.
const DEMO_RAW := {
	"xinput": [{ "pad": 0, "btype": 3, "blevel": 2, "sub": 1, "flags": 2, "vid": MICROSOFT, "pid": 0x0B12 }],
	"sony": [{ "vid": SONY, "pid": 0x0CE6, "bt": true, "read": true, "rid": 0x31, "n": 78, "st": [-1, -1, -1, 6] }],
	"wgi": [],
}

## Verbundene Controller nach Spieler sortiert, Felder siehe _entry.
var pads: Array = []
var raw: Dictionary = { "xinput": [], "sony": [], "wgi": [] }
var demo_raw: Dictionary = DEMO_RAW.duplicate(true)
var demo_warn := false              ## Proben: Akku-Warnungen auch in der Vorführung
var _warned := {}                   ## key -> niedrigste schon gemeldete Stufe (4 = keine)
var _last_pulse := -100000
var _last_ui := -100000
var _last_rand := -100000
var _last_device := -1
var _busy := false
var _again := false
var _sig := ""
var _friends := {}                  ## Steam-ID -> war online (für „Freund online“)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(func(_id: int, _on: bool) -> void:
		# XInput und HID melden einen neuen Controller etwas später als Godot.
		_rebuild()
		get_tree().create_timer(1.5).timeout.connect(refresh.bind(true))
	)
	Helper.pad_event.connect(func(kind: String) -> void:
		if kind == "pad-status":
			refresh()
	)
	Helper.helper_ready.connect(func() -> void: refresh(true))
	Social.updated.connect(_on_social)
	var t := Timer.new()
	t.wait_time = POLL_S
	t.autostart = true
	t.timeout.connect(refresh)
	add_child(t)
	refresh.call_deferred()


func _input(event: InputEvent) -> void:
	# Mit welchem Controller zuletzt bedient wurde: dorthin gehen die Impulse, und im Emulator ist er
	# Spieler 1 (benutzt_id, src/core/spieler_emus.gd).
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_last_device = event.device
	elif event is InputEventJoypadMotion and int(event.axis) <= JOY_AXIS_RIGHT_Y and absf(event.axis_value) > 0.6:
		_last_device = event.device   # mit dem Stick durch die Bibliothek


## Kennung („uz_id“, src/core/spieler.gd) des Controllers, mit dem zuletzt eine Taste gedrückt wurde –
## also der, mit dem gerade ein Spiel gestartet wird. "" ohne (nur Tastatur/Maus, nicht mehr verbunden).
func benutzt_id() -> String:
	return id_of_device(pads, _last_device)


static func id_of_device(list: Array, device: int) -> String:
	if device < 0:
		return ""
	for p in list:
		if int(p.get("device", -1)) == device:
			return str(p.get("uz_id", ""))
	return ""


## Neuen Stand holen. rescan: der Helfer liest gleich neu (sonst höchstens einmal pro Minute).
func refresh(rescan := false) -> void:
	if Library.demo:
		raw = demo_raw
		_rebuild()
		return
	if Helper.available and (Config.is_windows() or Helper._test_shell() != ""):
		if _busy:
			_again = true
			return
		_busy = true
		var r := await Helper.run("pad-status", { "rescan": rescan }, 4.0)
		_busy = false
		if r.ok and r.result is Dictionary:
			raw = parse_status(str((r.result as Dictionary).get("json", "")))
			raw.wgi = parse_wgi((r.result as Dictionary).get("wgi", []))
		if _again:
			_again = false
			refresh.call_deferred()
	_rebuild()


func _rebuild() -> void:
	var list := merge(raw.get("xinput", []), raw.get("sony", []), godot_joys(), raw.get("wgi", []))
	# Spieler & Controller (src/core/spieler.gd): neue Controller auf den nächsten freien Platz.
	SpielerS.sync(list)
	_check_low(list)
	var sig := JSON.stringify(list)
	pads = list
	if sig != _sig:
		_sig = sig
		changed.emit()


## Godots Sicht: { device, name, vid, pid, player } je verbundenem Controller. player ist SDLs
## Spieler-Nummer (bei XInput dieselbe wie der Anschluss); Godot nennt sie "xinput_index".
static func godot_joys() -> Array:
	var out: Array = []
	for id in Input.get_connected_joypads():
		var info := Input.get_joy_info(id)
		out.append({ "device": id, "name": Input.get_joy_name(id), "vid": _num(info.get("vendor_id", -1)),
			"pid": _num(info.get("product_id", -1)), "player": _num(info.get("xinput_index", -1)), "guid": Input.get_joy_guid(id) })
	return out


## Herstellernummer eines Godot-Geräts, -1 wenn unbekannt.
static func vid_of(device: int) -> int:
	return _num(Input.get_joy_info(device).get("vendor_id", -1))


static func _num(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	var s := str(v)
	return int(s) if s.is_valid_int() else -1


static func parse_status(text: String) -> Dictionary:
	var out := { "xinput": [], "sony": [] }
	# null heißt „fehlt“ (Fremd.json): Die Leser unten rechnen mit Ersatzwerten, int(null) bräche sie ab.
	var d: Variant = Fremd.json(text)
	if not (d is Dictionary):
		return out
	for k in ["xinput", "sony"]:
		if (d as Dictionary).get(k) is Array:
			out[k] = ((d as Dictionary)[k] as Array).filter(func(e): return e is Dictionary)
	return out


## Akkumeldungen aus Windows.Gaming.Input: { vid, pid, pct (-1 unbekannt), st } mit st wie
## BatteryStatus (0 nicht vorhanden, 1 entlädt, 2 ruht, 3 lädt). Fremdes wird verworfen.
static func parse_wgi(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for e in v:
		if not (e is Dictionary):
			continue
		var pct := _num(e.get("pct", -1))
		var st := _num(e.get("st", 0))
		if pct < 0 or pct > 100 or st < 1 or st > 3:
			continue
		out.append({ "vid": _num(e.get("vid", 0)), "pid": _num(e.get("pid", 0)), "pct": pct, "st": st })
	return out


# --- Zusammenführen --------------------------------------------------------------------------

static func _entry() -> Dictionary:
	## key, slot (Spieler), name, family (xbox/ps/nintendo/other), level (-1 unbekannt, 0 fast leer …
	## 3 voll), pct (-1 oder Prozent), power (wired/alkaline/nimh/battery/unknown), charging,
	## conn (Kabel/Funk/Bluetooth/""), xinput (-1 oder 0–3), device (Godot, -1), player (SDL, -1), can_off,
	## sdl_name (Name, wie SDL ihn meldet – für Dolphin „SDL/0/<Name>“; "" wenn Godot ihn nicht kennt)
	return { "key": "", "slot": 0, "name": "", "family": "other", "level": -1, "pct": -1, "power": "unknown",
		"charging": false, "conn": "", "xinput": -1, "device": -1, "player": -1, "can_off": false, "vid": 0, "pid": 0, "guid": "",
		"sdl_name": "" }


## Ein XInput-Anschluss aus dem Helfer: btype/blevel (XInputGetBatteryInformation), flags/sub
## (XInputGetCapabilities), vid/pid (XInputGetCapabilitiesEx, fehlt auf alten Windows-Versionen).
static func xinput_entry(x: Dictionary) -> Dictionary:
	var e := _entry()
	var idx := int(x.get("pad", 0))
	var bt := int(x.get("btype", 255))
	var bl := int(x.get("blevel", 0))
	var vid := int(x.get("vid", 0))
	var pid := int(x.get("pid", 0))
	var sub := int(x.get("sub", 1))
	# Über Bluetooth meldet XInput Xbox-Controller oft als „Kabel“ (ohne Stand): dort nicht glauben.
	var bt_pad := vid == MICROSOFT and pid in XBOX_BT
	var wired := bt == 1 and not bt_pad
	var wireless := not wired and ((int(x.get("flags", 0)) & 0x0002) != 0 or bt == 2 or bt == 3 or bt_pad)
	e.key = "x%d" % idx
	e.xinput = idx
	e.player = idx
	e.vid = vid
	e.pid = pid
	e.family = "xbox" if vid == MICROSOFT or vid == 0 else "other"
	e.power = "wired" if wired else { 2: "alkaline", 3: "nimh" }.get(bt, "unknown")
	e.level = clampi(bl, 0, 3) if bt == 2 or bt == 3 else -1
	e.conn = "Kabel" if wired else ("Bluetooth" if bt_pad else ("Funk" if wireless else ""))
	e.can_off = wireless
	if SUBTYPES.has(sub):
		e.name = str(SUBTYPES[sub])
	elif vid == MICROSOFT and XBOX_NAMES.has(pid):
		e.name = str(XBOX_NAMES[pid])
	else:
		e.name = "Xbox-Controller" if e.family == "xbox" else "Controller"
	return e


## Ein PlayStation-Controller aus dem HID-Teil des Helfers.
static func sony_entry(s: Dictionary, n: int) -> Dictionary:
	var e := _entry()
	var pid := int(s.get("pid", 0))
	var b := sony_battery(pid, int(s.get("rid", -1)), int(s.get("n", 0)), s.get("st", []) if s.get("st") is Array else [])
	e.key = "ps%x:%d" % [pid, n]
	e.vid = SONY
	e.pid = pid
	e.family = "ps"
	e.name = str(SONY_NAMES.get(pid, "PlayStation-Controller"))
	e.power = "battery"
	e.pct = int(b.pct)
	e.level = level_from_pct(int(b.pct))
	e.charging = bool(b.charging)
	e.conn = "Bluetooth" if bool(s.get("bt", false)) else ("Funk" if pid == 0x0BA0 else "Kabel")
	return e


## Akkustand aus einem Eingabebericht. st: die Bytes an Stelle 30, 32, 53, 54 (Berichtsnummer
## mitgezählt; -1 = Bericht zu kurz). DualShock 4: USB-Bericht 0x01 → 30, Bluetooth 0x11 → 32;
## untere 4 Bit Stand 0–10 (mit Kabel bis 11 = voll), Bit 4 Kabel. DualSense: USB 0x01 → 53,
## Bluetooth 0x31 → 54; untere 4 Bit Stand 0–10, obere: 0 entlädt, 1 lädt, 2 voll, sonst Fehler.
## Ein DualSense über Bluetooth schickt anfangs nur kurze Berichte (ohne Akku): dann pct = -1.
static func sony_battery(pid: int, rid: int, n: int, st: Array) -> Dictionary:
	var out := { "pct": -1, "charging": false }
	var ds5 := pid == 0x0CE6 or pid == 0x0DF2
	var at := -1
	if ds5:
		at = 2 if rid == 0x01 and n >= 64 else (3 if rid == 0x31 and n >= 78 else -1)
	else:
		at = 0 if rid == 0x01 and n >= 64 else (1 if rid == 0x11 and n >= 78 else -1)
	if at < 0 or at >= st.size() or int(st[at]) < 0:
		return out
	var v := int(st[at]) & 0xFF
	var lvl := v & 0x0F
	if ds5:
		match v >> 4:
			0:
				out.pct = mini(lvl * 10 + 5, 100)
			1:
				out.pct = mini(lvl * 10 + 5, 100)
				out.charging = true
			2:
				out.pct = 100
	else:
		if (v & 0x10) != 0:
			if lvl < 10:
				out.pct = lvl * 10 + 5
				out.charging = true
			elif lvl <= 11:
				out.pct = 100
				out.charging = lvl == 10
		else:
			out.pct = lvl * 10 + 5 if lvl < 10 else 100
	return out


## Prozent in die vier Stufen der Xbox (fast leer, schwach, mittel, voll).
static func level_from_pct(pct: int) -> int:
	if pct < 0:
		return -1
	if pct <= 10:
		return 0
	if pct <= 35:
		return 1
	if pct <= 70:
		return 2
	return 3


static func family_of(name: String, vid: int) -> String:
	var n := name.to_lower()
	if vid == SONY or n.contains("dualsense") or n.contains("dualshock") or n.contains("ps4") or n.contains("ps5") or n.contains("playstation"):
		return "ps"
	if n.contains("nintendo") or n.contains("pro controller") or n.contains("joy-con") or n.contains("switch"):
		return "nintendo"
	if vid == MICROSOFT or n.contains("xbox") or n.contains("xinput"):
		return "xbox"
	return "other"


## Helfer (XInput, PlayStation über HID) und Godot zu einer Liste: jeder Controller einmal, mit
## Spieler-Nummer. XInput-Controller finden ihr Godot-Gerät über die XInput-Nummer (sonst der
## Reihe nach), PlayStation-Controller über die Produktnummer. Was nur Godot kennt, steht ohne Akku da.
static func merge(xin: Array, sony: Array, joys: Array, wgi: Array = []) -> Array:
	var out: Array = []
	var used := {}
	var xs: Array = []
	for x in xin:
		if x is Dictionary:
			xs.append(xinput_entry(x))
	for e in xs:
		for j in joys:
			if not used.has(j.device) and int(j.vid) != SONY and int(j.player) == int(e.xinput):
				_take(e, j, used)
				break
	for e in xs:
		if int(e.device) >= 0:
			continue
		for j in joys:
			if not used.has(j.device) and int(j.vid) != SONY and int(j.player) < 0 and family_of(str(j.name), int(j.vid)) != "ps":
				_take(e, j, used)
				break
	out.append_array(xs)
	var k := 0
	for s in sony:
		if not (s is Dictionary):
			continue
		var e := sony_entry(s, k)
		k += 1
		for j in joys:
			if not used.has(j.device) and int(j.vid) == SONY and int(j.pid) == int(s.get("pid", 0)):
				_take(e, j, used)
				e.player = int(j.player)
				break
		out.append(e)
	for j in joys:
		if used.has(j.device):
			continue
		var e := _entry()
		e.key = "j%d" % int(j.device)
		e.device = int(j.device)
		e.guid = str(j.get("guid", ""))
		e.sdl_name = str(j.get("name", ""))
		e.vid = int(j.get("vid", 0))
		e.pid = int(j.get("pid", 0))
		e.name = str(j.name) if str(j.name) != "" else "Controller"
		e.family = family_of(e.name, int(j.vid))
		e.player = int(j.player)
		if e.family == "ps" and SONY_NAMES.has(int(j.pid)):
			e.name = str(SONY_NAMES[int(j.pid)])
		out.append(e)
	apply_wgi(out, wgi)
	assign_slots(out)
	out.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	return out


## Fehlt einem Controller der Stand (oder steht er fälschlich auf „Kabel“), nimmt Uzai die Meldung
## aus Windows.Gaming.Input: erst gleiche Hersteller- und Produktnummer, dann (Xbox ohne genaue
## Nummer, z. B. über den Funkadapter) irgendeine Microsoft-Meldung – bei gleichen Controllern in
## Reihenfolge. Am echten Kabel ohne Akku meldet Windows dort nichts: dann bleibt „Kabel“.
static func apply_wgi(list: Array, wgi: Array) -> void:
	var used := {}
	for exact in [true, false]:
		for e in list:
			if int(e.level) >= 0 and str(e.power) != "wired":
				continue
			# Ohne genaue Nummer nie einem Kabel-Controller eine fremde Meldung geben.
			if not exact and str(e.power) == "wired":
				continue
			var vid := int(e.get("vid", 0))
			if vid == 0 and str(e.family) == "xbox":
				vid = MICROSOFT
			for i in wgi.size():
				var w: Dictionary = wgi[i]
				if used.has(i) or int(w.vid) != vid or (exact and int(w.pid) != int(e.get("pid", 0))):
					continue
				used[i] = true
				e.pct = int(w.pct)
				e.level = level_from_pct(int(w.pct))
				e.charging = int(w.st) == 3
				if str(e.power) in ["wired", "unknown"]:
					e.power = "battery"
				break


static func _take(e: Dictionary, j: Dictionary, used: Dictionary) -> void:
	used[j.device] = true
	e.device = int(j.device)
	e.guid = str(j.get("guid", ""))
	e.sdl_name = str(j.get("name", ""))
	# Unbekannte Xbox-Produktnummer (z. B. über den Funkadapter): Godots Name ist genauer.
	if str(e.name) in ["Xbox-Controller", "Controller"] and str(j.name) != "":
		e.name = str(j.name)


## Spieler-Nummern: XInput-Controller nach ihrem Anschluss (wie der Leuchtring), andere nach
## SDLs Spieler-Nummer, sonst die kleinste freie.
static func assign_slots(list: Array) -> void:
	var taken := {}
	for e in list:
		e.slot = 0
		if int(e.xinput) >= 0 and not taken.has(int(e.xinput) + 1):
			e.slot = int(e.xinput) + 1
			taken[e.slot] = true
	for e in list:
		if int(e.slot) == 0 and int(e.player) >= 0 and not taken.has(int(e.player) + 1):
			e.slot = int(e.player) + 1
			taken[e.slot] = true
	for e in list:
		if int(e.slot) == 0:
			var s := 1
			while taken.has(s):
				s += 1
			e.slot = s
			taken[s] = true


# --- Texte -----------------------------------------------------------------------------------

## Rechts in der Zeile: „Voll“, „Mittel“, „Schwach“, „Fast leer“, bei PlayStation Prozent; „Kabel“
## bei Xbox-Controllern ohne Akku; leer, wenn unbekannt.
static func battery_text(p: Dictionary) -> String:
	if str(p.get("power", "")) == "wired":
		return "Kabel"
	var lvl := int(p.get("level", -1))
	if lvl < 0:
		return ""
	var t := ["Fast leer", "Schwach", "Mittel", "Voll"][clampi(lvl, 0, 3)] as String
	if int(p.get("pct", -1)) >= 0:
		t = "%d %%" % int(p.pct)
	if bool(p.get("charging", false)):
		t += " · lädt"
	return t


## Darunter: „Spieler 1 · Funk · Akku“. Am Kabel ohne Akku nur „Spieler 1“ (rechts steht „Kabel“).
static func detail_text(p: Dictionary) -> String:
	var parts := PackedStringArray(["Spieler %d" % int(p.get("slot", 1))])
	if str(p.get("conn", "")) != "" and str(p.get("power", "")) != "wired":
		parts.append(str(p.conn))
	var pw := { "alkaline": "Batterien", "nimh": "Akku", "battery": "Akku" }.get(str(p.get("power", "")), "") as String
	if pw != "" and str(p.get("conn", "")) != "Kabel":
		parts.append(pw)
	return " · ".join(parts)


# --- Akku schwach ----------------------------------------------------------------------------

## Einmal je Stufe nach unten (schwach, dann fast leer); lädt er oder ist wieder mittel/voll,
## darf es beim nächsten Mal wieder melden. Rückgabe [melden?, neue gemeldete Stufe].
static func warn_step(warned: int, level: int, charging: bool, power: String) -> Array:
	if level < 0 or power == "wired":
		return [false, warned]
	if charging or level >= 2:
		return [false, 4]
	if level < warned:
		return [true, level]
	return [false, warned]


func _check_low(list: Array) -> void:
	for p in list:
		var key := str(p.key)
		var step := warn_step(int(_warned.get(key, 4)), int(p.level), bool(p.charging), str(p.power))
		_warned[key] = int(step[1])
		if not bool(step[0]) or (Library.demo and not demo_warn):
			continue
		var what := "fast leer – bald aufladen" if int(p.level) == 0 else "noch wenig Akku"
		if str(p.power) == "alkaline":
			what = "Batterien fast leer" if int(p.level) == 0 else "Batterien werden schwach"
		Toasts.show_toast("Controller-Akku schwach", "%s · Spieler %d: %s" % [str(p.name), int(p.slot), what], "controller",
			{ "color": "warn", "overlay": true, "ms": 6000, "tag": "pad-battery:" + key })


# --- Vibration -------------------------------------------------------------------------------

func _cfg() -> Dictionary:
	return { "events": bool(Config.get_value("controller.rumble_events", true)),
		"friends": bool(Config.get_value("controller.rumble_friends", false)),
		"vibration": bool(Config.get_value("controller.vibration", true)) }


## Darf dieser Impuls sein? Nur die bekannten Ereignisse, nur mit „Vibration bei Bestätigungen“;
## „Freund online“ zusätzlich nur mit eigenem Schalter und nie im Spiel. Im Spiel sonst nur Clip,
## Erfolg und Nachricht – nie etwas anderes, solange gespielt wird.
static func pulse_allowed(kind: String, cfg: Dictionary, in_game: bool, vorn: bool) -> bool:
	if kind == "test":
		return true
	if PULSES_UI.has(kind):
		# Nur, wenn Uzai vorn ist (nie über den Helfer ins Spiel); der Guide auch über dem Spiel.
		return bool(cfg.get("vibration", true)) and vorn and (kind == "guide" or not in_game)
	if not PULSES.has(kind) or not bool(cfg.get("events", true)):
		return false
	if kind == "friend_online":
		return bool(cfg.get("friends", false)) and not in_game
	return true


## Kurzer, leiser Impuls für ein Ereignis. Ist Uzai vorn: über Godot an den zuletzt benutzten
## Controller (sonst alle). Liegt ein Spiel vorn: über den Helfer (XInputSetState, nur
## Xbox-/XInput-Controller). true, wenn ein Impuls unterwegs ist.
func pulse(kind: String) -> bool:
	var focused := _focused()
	var now := Time.get_ticks_msec()
	if kind == "rand":
		var frei := rand_frei(now - _last_rand)
		_last_rand = now
		if not frei:
			return false
	if not pulse_allowed(kind, _cfg(), Launcher.in_game and not Launcher.guide_open, focused):
		return false
	if PULSES_UI.has(kind):
		if now - _last_ui < UI_GAP_MS:
			return false
		_last_ui = now
		var plan := ui_plan(kind)
		for st in plan:
			if int(st[0]) == 0:
				_send(float(st[1]), float(st[2]), int(st[3]), _last_device, true)
			else:
				get_tree().create_timer(int(st[0]) / 1000.0).timeout.connect(func() -> void:
					if _focused():
						_send(float(st[1]), float(st[2]), int(st[3]), _last_device, true))
		return not plan.is_empty()
	if kind != "test" and now - _last_pulse < PULSE_GAP_MS:
		return false
	_last_pulse = now
	var p: Array = PULSES[kind]
	return _send(float(p[0]), float(p[1]), int(p[2]), _last_device, focused)


## Die Stöße eines Impulses der Oberfläche: [[nach ms, tief, hell, ms], …], Dauer immer
## UI_MIN_MS … UI_MAX_MS, Stärke 0 … 1 – nie dauerhaft. Leer für unbekannte Arten.
static func ui_plan(kind: String) -> Array:
	if not PULSES_UI.has(kind):
		return []
	var p: Array = PULSES_UI[kind]
	var ms := clampi(int(p[2]), UI_MIN_MS, UI_MAX_MS)
	var st := [[0, clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0), ms]]
	if int(p[3]) > 0:
		st.append([int(p[3]), st[0][1], st[0][2], ms])
	return st


## Rand: Impuls nur beim ersten Stoß je Halten. abstand: ms seit dem letzten Stoß (auch einem stillen).
static func rand_frei(abstand: int) -> bool:
	return abstand >= RAND_HALTEN_MS


## Einen Controller kurz vibrieren lassen (welcher ist welcher?).
func identify(pad: Dictionary) -> bool:
	var p: Array = PULSES["test"]
	return _send(float(p[0]), float(p[1]), int(p[2]), int(pad.get("device", -1)), _focused(), int(pad.get("xinput", -1)))


## Für den Controller-Test: links = tiefer Motor, rechts = heller Motor, Dauer in Sekunden.
func rumble(device: int, left: float, right: float, secs: float) -> void:
	if device >= 0:
		Input.start_joy_vibration(device, clampf(right, 0.0, 1.0), clampf(left, 0.0, 1.0), clampf(secs, 0.02, 0.6))


func _send(left: float, right: float, ms: int, device: int, focused: bool, xinput := -2) -> bool:
	ms = clampi(ms, 20, 150)
	if focused:
		var ids := Input.get_connected_joypads()
		if ids.is_empty():
			return false
		for id in ([device] if device in ids else ids):
			Input.start_joy_vibration(id, right, left, ms / 1000.0)
		return true
	if Config.is_windows() and Helper.available:
		var xi := xinput if xinput > -2 else _xinput_of(device)
		Helper.run("pad-pulse", { "pad": xi, "low": int(left * 65535.0), "high": int(right * 65535.0), "ms": ms }, 2.0)
		return true
	return false


func _xinput_of(device: int) -> int:
	for p in pads:
		if int(p.device) == device and device >= 0:
			return int(p.xinput)
	return -1


func _focused() -> bool:
	var w := get_tree().root if is_inside_tree() else null
	return w != null and w.has_focus() and w.mode != Window.MODE_MINIMIZED


## Freund kommt online (Steam): nur mit eigenem Schalter, siehe pulse_allowed.
func _on_social(_what: Variant = null) -> void:
	if not bool(Config.get_value("controller.rumble_friends", false)) or Library.demo:
		_friends.clear()
		return
	var now := {}
	var came := false
	for f in Social.steam_friends:
		var on := str(f.get("state", "offline")) != "offline"
		var id := str(f.get("id", ""))
		now[id] = on
		if on and _friends.has(id) and not bool(_friends[id]):
			came = true
	_friends = now
	if came:
		pulse("friend_online")


# --- Ausschalten -----------------------------------------------------------------------------

static func power_off_error(code: int) -> String:
	match code:
		0:
			return ""
		1167:
			return "Der Controller ist nicht mehr verbunden."
		-2:
			return "Diese Windows-Version kennt die Funktion nicht. Xbox-Taste 6 Sekunden halten."
	return "Windows hat abgelehnt (%d). Das geht nur über den Xbox-Funkadapter oder den Xbox-360-Empfänger; über Bluetooth: Xbox-Taste 6 Sekunden halten." % code


## Kabellosen Xbox-Controller ausschalten (XInputPowerOffController, Ordinal 103 von xinput1_4.dll –
## nicht dokumentiert, aber Standard seit Windows 8). { ok, error }.
func power_off(pad: Dictionary) -> Dictionary:
	if not bool(pad.get("can_off", false)) or int(pad.get("xinput", -1)) < 0:
		return { "ok": false, "error": "Ausschalten geht nur bei kabellosen Xbox-Controllern." }
	if Library.demo:
		demo_raw["xinput"] = (demo_raw.get("xinput", []) as Array).filter(func(x): return int(x.get("pad", -1)) != int(pad.xinput))
		refresh()
		return { "ok": true, "error": "" }
	var r := await Helper.run("pad-off", { "pad": int(pad.xinput) }, 3.0)
	var code := int((r.result as Dictionary).get("code", -9)) if r.ok and r.result is Dictionary else -9
	get_tree().create_timer(1.5).timeout.connect(refresh.bind(true))
	if code == -9:
		return { "ok": false, "error": "Der Windows-Helfer antwortet nicht." }
	return { "ok": code == 0, "error": power_off_error(code) }

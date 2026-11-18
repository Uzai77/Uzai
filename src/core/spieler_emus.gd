extends RefCounted
## Controllers in the emulators: set up before every start of an emulator game (Launcher) and on request
## in "Spieler & Controller". Two modes:
##
## 1. Controller in the emulator automatically (default on, Config "spieler.emu_fehlend"): player 1 is
##    the controller the game was started with (Pads.benutzt_id, spieler_start), even if the
##    emulator's mapping points to another connected controller. Custom buttons stay, only the device
##    changes; if a mapping is missing (empty or keyboard only, which is how PCSX2, DuckStation and
##    Dolphin ship), Uzai writes the one the emulator's own "automatic mapping" would write.
##    Players 2–4 follow the assignment (src/core/spieler.gd); if the user set player 1 manually and
##    several people play, that choice applies. Players 2–4 are set up automatically in the same way:
##    PCSX2 and DuckStation with three or four players via the multitap (plan_ps_multitap), Eden & Co.
##    with the mapping of the same controller model (plan_yuzu_start). Why "connected mapping stays"
##    (0.14–0.16) was dropped: Uzai cannot see whether "SDL-0" in the emulator is the controller in the
##    player's hand, because the emulator counts SDL devices itself (virtual controllers from Steam,
##    second devices …). With that rule a custom mapping on SDL-0 was kept while PCSX2 responded to no
##    input. Hence Xbox and all other XInput controllers go through their XInput port (which is
##    reliable), only other controllers through SDL, and every start is logged in launch.log with
##    device, GUID, XInput port and SDL number. The "missing only" rules (plan_*_fehlend) are still
##    used for RetroArch, PPSSPP and, for player 1, Eden & Co. (there the emulator counts devices
##    itself, or only the emulator knows the raw button numbers).
## 2. Always follow Uzai's assignment (default off, Config "spieler.emulatoren", the old switch
##    "Vor jedem Start einrichten", from two players up): players 1–4 exactly per the assignment in
##    src/core/spieler.gd; custom mappings keep their buttons, only the device changes.
##
## What Uzai may change (and what not):
## - Only the emulator's settings file in its own folder (next to the .exe, Documents, AppData), only
##   files with a known name, only files that already exist (the emulator creates them itself on first
##   start). Sole exception: Dolphin creates GCPadNew.ini/WiimoteNew.ini only once the controller
##   settings are opened, so Uzai creates them next to Dolphin.ini. No drivers, no virtual
##   controllers.
## - Only the players' mappings: sections [Pad1]–[Pad5] (plus [InputSources] SDL/XInput on and, from three
##   players, the multitap on port 1: [Pad] MultitapPort1 or [ControllerPorts] MultitapMode), [GCPad1–4],
##   [Wiimote1–4], in Dolphin.ini SIDevice0–3, in retroarch.cfg input_autodetect_enable and
##   input_playerN_joypad_index, in PPSSPP's controls.ini [ControlMapping], for Eden & Co. player_N_* in
##   [Controls]. Everything else stays line by line as it was (comments, order, CRLF).
## - Before the first write Uzai copies the original file into its storage (spieler/sicherung);
##   "Originale zurückholen" puts it back.
## - While the emulator is running Uzai does not write: none of these emulators re-reads its file
##   during a game (RetroArch would even overwrite it on exit). The change then applies on the next start.
##
## Devices and button names as the emulators call them (from their source code, as of 2026):
## - PCSX2, DuckStation: "XInput-<port>/A" for Xbox controllers (XInputSource; the port is known
##   reliably, the names are the same in all versions, Y up is "-LeftY" as with SDL),
##   otherwise "SDL-<n>/A" (n = SDL's player number). PCSX2 2.4 and later names the SDL buttons
##   FaceSouth/East/West/North but still reads A/B/X/Y; older PCSX2 and DuckStation only know A/B/X/Y.
## - Dolphin: "XInput/<port>/Gamepad", otherwise "SDL/<n>/<SDL name>"; button names as in XInput
##   ("Button A", "Left Y+" = up); Dolphin's SDL backend accepts them the same way since 2412.
## - RetroArch: maps controllers itself via autoconfig; Uzai only turns autoconfig on and sets the device number.
## - PPSSPP: has its own default controller mapping; Uzai only restores it when no controller is
##   mapped at all.
## - Eden, Citron, Sudachi, yuzu: "engine:sdl,port:<n>,guid:<SDL-GUID>,button:<raw>"; only the emulator
##   knows the raw button numbers, so Uzai only takes over a mapping it wrote itself.

const Ini := preload("res://src/core/remote_play_pads.gd")
const SpielerS := preload("res://src/core/spieler.gd")
const PadsS := preload("res://src/core/pads.gd")

const BACKUP_DIR := "spieler/sicherung"
const KEY_MULTITAP := "spieler.multitap"   ## Pfad → true: dort hat Uzai den Multitap eingeschaltet
## Multitap an Anschluss 1: Spieler → Abschnitt (beide Emulatoren zählen Pad1 = 1A, Pad2 = 2A, Pad3–5 =
## 1B–1D, Pad6–8 = 2B–2D; PCSX2 Pad::ConvertPortAndSlotToPad, DuckStation Controller::ConvertPadToPortAndSlot).
const MT_PADS := { 2: "Pad3", 3: "Pad4", 4: "Pad5" }
const MT_PLATZ := { 2: "1B", 3: "1C", 4: "1D" }
const KEY_BACKUPS := "spieler.sicherungen"   ## Name in der Ablage → Originalpfad
const KEY_ZURUECK := "spieler.originale_zurueck"   ## einmal nach 0.13.0 zurückgelegt
const KEY_ZURUECK2 := "spieler.originale_zurueck2" ## zweite Runde: auch wer den Schalter selbst ausgeschaltet hatte
const MAX_BYTES := 2 * 1024 * 1024
const Sicher := preload("res://src/core/sicher.gd")
const FILES := ["pcsx2.ini", "settings.ini", "gcpadnew.ini", "dolphin.ini", "wiimotenew.ini", "retroarch.cfg", "qt-config.ini", "controls.ini"]
## Darf Uzai neu anlegen (nur neben Dolphin.ini, siehe oben).
const NEU_OK := ["gcpadnew.ini", "wiimotenew.ini"]
const PS_KEYS := Ini.PS_KEYS
## PCSX2 (DualShock2) und DuckStation (AnalogController): Taste → Eingabe, wie GetGenericBindingMapping
## von SDLInputSource bzw. XInputSource sie liefert. Ohne „Analog“: Das läge auf der Guide-Taste, die
## Uzai für sich behält – DuckStation schaltete bei jedem Guide auf digital (Sticks tot).
const PS_STD := [["Up", "DPadUp"], ["Right", "DPadRight"], ["Down", "DPadDown"], ["Left", "DPadLeft"],
	["Triangle", "Y"], ["Circle", "B"], ["Cross", "A"], ["Square", "X"], ["Select", "Back"], ["Start", "Start"],
	["L1", "LeftShoulder"], ["R1", "RightShoulder"], ["L2", "+LeftTrigger"], ["R2", "+RightTrigger"],
	["L3", "LeftStick"], ["R3", "RightStick"], ["LUp", "-LeftY"], ["LRight", "+LeftX"], ["LDown", "+LeftY"],
	["LLeft", "-LeftX"], ["RUp", "-RightY"], ["RRight", "+RightX"], ["RDown", "+RightY"], ["RLeft", "-RightX"],
	["LargeMotor", "LargeMotor"], ["SmallMotor", "SmallMotor"]]
## SDL-Tastennamen ab PCSX2 2.4 (SDL3, positionsgleich): A/B/X/Y ↔ FaceSouth/East/West/North.
const PS_FACE := { "A": "FaceSouth", "B": "FaceEast", "X": "FaceWest", "Y": "FaceNorth" }
## Anschluss-Arten, für die PS_STD passt (andere wie Gitarre oder NeGcon: nur das Gerät tauschen).
const PS_TYPES := ["DualShock2", "AnalogController", "DigitalController", "AnalogJoystick"]
const PS_MOTOR := ["LargeMotor", "SmallMotor"]
## Dolphin GameCube: Tastennamen von Dolphins XInput-Teil; der SDL-Teil nimmt dieselben (seit 2412).
const GC_XINPUT := Ini.GC_XINPUT
## Dolphin Wii: emulierte Wiimote mit Nunchuk (Stick links, Zeiger rechts). Home auf R3 – die
## Guide-Taste gehört Uzai.
const WII_STD := [["Buttons/A", "Button A"], ["Buttons/B", "Trigger R"], ["Buttons/1", "Button X"], ["Buttons/2", "Button Y"],
	["Buttons/-", "Back"], ["Buttons/+", "Start"], ["Buttons/Home", "Thumb R"],
	["D-Pad/Up", "Pad N"], ["D-Pad/Down", "Pad S"], ["D-Pad/Left", "Pad W"], ["D-Pad/Right", "Pad E"],
	["IR/Up", "Right Y+"], ["IR/Down", "Right Y-"], ["IR/Left", "Right X-"], ["IR/Right", "Right X+"],
	["Shake/X", "Button B"], ["Shake/Y", "Button B"], ["Shake/Z", "Button B"],
	["Nunchuk/Buttons/C", "Shoulder L"], ["Nunchuk/Buttons/Z", "Trigger L"],
	["Nunchuk/Stick/Up", "Left Y+"], ["Nunchuk/Stick/Down", "Left Y-"], ["Nunchuk/Stick/Left", "Left X-"], ["Nunchuk/Stick/Right", "Left X+"],
	["Rumble/Motor", "Motor L"]]
const YUZU_KEY := "^player_[0-7]_(button_[a-z_]+|lstick|rstick|motion[a-z]*|vibration[a-z_]*)$"

## Muster, die je Taste einer Belegung gebraucht werden: einmal übersetzt (beim Laden gefüllt, danach nur gelesen).
static var _RX_PS := RegEx.create_from_string("^(SDL|XInput|DInput)-(\\d+)/(.+)$")
static var _RX_PS_WERT := RegEx.create_from_string("(^|& )(SDL|XInput|DInput)-\\d+/")
static var _RX_FACE := RegEx.create_from_string("SDL-\\d+/Face(South|East|West|North)\\b")
static var _RX_DEV := RegEx.create_from_string("^`?([A-Za-z]+)/(\\d+)/(.+?)`?$")
static var _RX_EIGENE := RegEx.create_from_string("(?m)^\\s*(UseGameSettingsForController\\s*=\\s*true|InputProfileName\\s*=\\s*\\S)")
## PCSX2: Ordner der Spiel-Einstellungen → [Änderungszeit, Zahl der Dateien, Ergebnis] (pcsx2_spiel_eigene).
## Nur im Hauptfaden benutzt (vor_start).
static var _eigene_merk := {}


# --- Was Uzai je Emulator tut -------------------------------------------------------------------

static func kind_of(emu_id: String, exe: String) -> String:
	var k := Ini.kind_of(emu_id, exe)
	return "ppsspp" if exe.get_file().to_lower().begins_with("ppsspp") else k


static func supported(kind: String) -> bool:
	return kind in ["pcsx2", "duckstation", "dolphin", "retroarch"] or Ini.YUZU_LIKE.has(kind)


## Kurz, für die Liste in „Spieler & Controller“.
static func describe(kind: String) -> String:
	match kind:
		"pcsx2", "duckstation":
			return "Spieler 1–4 (ab drei Spielern mit Multitap)"
		"dolphin":
			return "GameCube und Wii, Spieler 1–4"
		"retroarch":
			return "Spieler 1–4"
		"ppsspp":
			return "Ein Spieler – nimmt jeden Controller"
	if Ini.YUZU_LIKE.has(kind):
		return "Spieler 1–4"
	return "Im Emulator selbst einstellen"


# --- Bindungen ---------------------------------------------------------------------------------

## „SDL-0/A“, „XInput-1/A & Keyboard/X“: dasselbe auf ein anderes Gerät. Tastatur bleibt;
## DInput (eigene Tastennamen) geht nicht → "". FaceSouth & Co. (PCSX2 ab 2.4) werden für XInput und
## DuckStation zu A/B/X/Y – die kennen nur diese Namen.
static func retarget(value: String, prefix: String, kind := "") -> String:
	var re := _RX_PS
	var parts := PackedStringArray()
	var any := false
	var abxy := prefix.begins_with("XInput") or kind == "duckstation"
	for part in value.split(" & "):
		var t := part.strip_edges()
		var m := re.search(t)
		if m == null:
			parts.append(t)
			continue
		if m.get_string(1) == "DInput":
			return ""
		var name := m.get_string(3)
		if abxy and PS_FACE.values().has(name):
			name = str(PS_FACE.keys()[PS_FACE.values().find(name)])
		parts.append("%s/%s" % [prefix, name])
		any = true
	return " & ".join(parts) if any else ""


static func _is_pad_value(v: String) -> bool:
	return _RX_PS_WERT.search(v) != null


## DuckStation und PCSX2: [Pad1], [Pad2]. Rückgabe { text, done: [Spieler], note }.
static func plan_ps(text: String, default_type: String, players: Array, mt_uzai := false) -> Dictionary:
	var out := text
	var done: Array = []
	for n in [1, 2]:
		var p: Dictionary = players[n - 1] if n - 1 < players.size() else {}
		if p.is_empty():
			continue
		var sec := "Pad%d" % n
		var old: Variant = Ini.section_lines(out, sec)
		var prefix := ps_geraet(p)
		var kind := "pcsx2" if default_type == "DualShock2" else "duckstation"
		var new := ps_lines(old, kind, prefix, _face(out, kind))
		if old == null or not _same(old, new):
			out = Ini.set_section(out, sec, new)
		out = _quelle_an(out, prefix)
		done.append(n)
	var kind2 := "pcsx2" if default_type == "DualShock2" else "duckstation"
	var log: Array = []
	var mt := plan_ps_multitap(out, kind2, players, _face(out, kind2), mt_uzai, done, log)
	var note := "; ".join(PackedStringArray(log.filter(func(l): return str(l).contains("bitte"))))
	return { "text": str(mt.text), "done": done, "note": note, "mt": str(mt.mt) }


## Spieler 3 und 4 bei PS1/PS2: Ab drei Spielern schaltet Uzai den Multitap an Anschluss 1 ein und belegt
## 1B–1D – Spieler 2 zusätzlich zu [Pad2] (Anschluss 2) auch auf 1B: So geht es in Spielen mit Multitap
## (Spieler 1–4 = 1A–1D) und ohne (die sehen weiter nur 1A und 2A). Mit weniger Spielern schaltet Uzai
## ihn wieder aus – nur, wenn Uzai ihn eingeschaltet hat (mt_uzai). Steht er im Emulator nur an
## Anschluss 2, bleibt alles, wie es ist. Rückgabe { text, mt: "an" | "aus" | "" (nichts umgeschaltet) }.
static func plan_ps_multitap(text: String, kind: String, players: Array, face: bool, mt_uzai: bool, done: Array, log: Array) -> Dictionary:
	var mehr := false
	for i in [2, 3]:
		if i < players.size() and not (players[i] as Dictionary).is_empty():
			mehr = true
	var stand := mt_stand(text, kind)
	if not mehr:
		if mt_uzai and stand == "an":
			log.append("Multitap aus (nur noch bis zu zwei Spieler; Uzai hatte ihn eingeschaltet)")
			return { "text": _mt_set(text, kind, false), "mt": "aus" }
		return { "text": text, "mt": "" }
	if stand == "p2":
		log.append("Spieler 3 und 4: Der Multitap steht im Emulator an Anschluss 2 – bitte dort belegen")
		return { "text": text, "mt": "" }
	var out := text
	var mt := ""
	if stand == "aus":
		out = _mt_set(out, kind, true)
		mt = "an"
		log.append("Multitap an Anschluss 1 eingeschaltet (für Spieler 3 und 4)")
	for n in [2, 3, 4]:
		var p: Dictionary = players[n - 1] if n - 1 < players.size() else {}
		if p.is_empty():
			continue
		var sec: String = MT_PADS[n]
		var dev := ps_geraet(p)
		var old: Variant = Ini.section_lines(out, sec)
		var neu := ps_lines(old, kind, dev, face)
		var vorher := out
		if old == null or not _same(old, neu):
			out = Ini.set_section(out, sec, neu)
		out = _quelle_an(out, dev)
		if out == vorher:
			log.append("Spieler %d: %s am Multitap %s (stimmt schon)" % [n, dev, MT_PLATZ[n]])
			continue
		if not done.has(n):
			done.append(n)
		log.append("Spieler %d → %s am Multitap %s" % [n, dev, MT_PLATZ[n]])
	return { "text": out, "mt": mt }


## Multitap im Emulator: "an" (an Anschluss 1), "p2" (nur an Anschluss 2) oder "aus".
static func mt_stand(text: String, kind: String) -> String:
	if kind == "pcsx2":
		return "an" if _roh(Ini.ini_get(text, "Pad", "MultitapPort1")) == "true" else "aus"
	var m := _roh(Ini.ini_get(text, "ControllerPorts", "MultitapMode"))
	if m in ["port1only", "bothports"]:
		return "an"
	return "p2" if m == "port2only" else "aus"


static func _mt_set(text: String, kind: String, on: bool) -> String:
	if kind == "pcsx2":
		return Ini.ini_set(text, "Pad", "MultitapPort1", "true" if on else "false")
	return Ini.ini_set(text, "ControllerPorts", "MultitapMode", "Port1Only" if on else "Disabled")


## Hat Uzai in dieser Datei den Multitap eingeschaltet?
static func mt_von_uzai(path: String) -> bool:
	var d: Variant = Config.get_value(KEY_MULTITAP, {})
	return d is Dictionary and bool((d as Dictionary).get(path, false))


static func _mt_merken(path: String, mt: String) -> void:
	if mt == "":
		return
	var v: Variant = Config.get_value(KEY_MULTITAP, {})
	var d: Dictionary = (v as Dictionary).duplicate() if v is Dictionary else {}
	if mt == "an":
		d[path] = true
	else:
		d.erase(path)
	Config.set_value(KEY_MULTITAP, d)


## Gerät für PCSX2/DuckStation: Xbox-Controller über XInput (Anschluss sicher bekannt), sonst SDL.
static func ps_geraet(p: Dictionary) -> String:
	var xi := int(p.get("xinput", -1))
	return "XInput-%d" % xi if xi >= 0 and xi <= 3 else "SDL-%d" % int(p.get("sdl", 0))


## Nennt die Datei SDL-Tasten schon FaceSouth & Co.? Dann ist es PCSX2 ab 2.4 – neue Belegungen auch so.
static func _face(text: String, kind: String) -> bool:
	return kind == "pcsx2" and _RX_FACE.search(text) != null


## Neue Zeilen für [PadN]: eigene Controller-Belegungen auf das Gerät umgezogen (Tasten bleiben),
## Tastatur bleibt daneben, Typ „None“ wird zum normalen Controller, und jede Taste ohne Controller
## bekommt die übliche Belegung (PS_STD).
static func ps_lines(old: Variant, kind: String, prefix: String, face: bool) -> Array:
	var std_type := "DualShock2" if kind == "pcsx2" else "AnalogController"
	var typ := std_type
	var out: Array = []
	var bound := {}
	var has_type := false
	for l in (old if old is Array else []):
		var kv := Ini.kv(str(l))
		if kv.is_empty():
			out.append(l)
			continue
		var key := str(kv[0])
		var val := str(kv[1])
		if key == "Type":
			has_type = true
			typ = std_type if val in ["None", ""] else val
			out.append("Type = " + typ)
			continue
		if not _is_pad_value(val):
			out.append(l)
			continue
		var nv := retarget(val, prefix, kind)
		if nv == "":
			continue   # DInput: eigene Tastennamen – fällt weg, die übliche Belegung kommt unten dazu
		var line := "%s = %s" % [key, nv]
		if not out.has(line):
			out.append(line)
		bound[key] = true
	if not has_type:
		out.push_front("Type = " + typ)
	while not out.is_empty() and str(out[-1]).strip_edges() == "":
		out.pop_back()
	if typ in PS_TYPES:
		for k in PS_STD:
			if not bound.has(k[0]):
				var name := str(k[1])
				if face and prefix.begins_with("SDL") and PS_FACE.has(name):
					name = str(PS_FACE[name])
				out.append("%s = %s/%s" % [k[0], prefix, name])
	return out


## [InputSources]: die Quelle des Geräts einschalten, wenn sie aus ist (XInput ist von Haus aus aus).
static func _quelle_an(text: String, prefix: String) -> String:
	var src := prefix.get_slice("-", 0)
	if _an(text, src, src == "SDL"):
		return text
	return Ini.ini_set(text, "InputSources", src, "true")


static func _an(text: String, src: String, std: bool) -> bool:
	var v: Variant = Ini.ini_get(text, "InputSources", src)
	return std if v == null else str(v).strip_edges().to_lower() == "true"


static func _same(a: Variant, b: Variant) -> bool:
	if not (a is Array) or not (b is Array):
		return false
	var x: Array = (a as Array).map(func(l): return str(l).strip_edges())
	var y: Array = (b as Array).map(func(l): return str(l).strip_edges())
	return x == y


# --- Dolphin ---------------------------------------------------------------------------------

static func dolphin_device(p: Dictionary) -> String:
	if int(p.get("xinput", -1)) >= 0:
		return "XInput/%d/Gamepad" % int(p.xinput)
	var nm := str(p.get("sdl_name", ""))
	return "SDL/%d/%s" % [int(p.get("dolphin_n", 0)), nm if nm != "" else str(p.get("name", "Controller"))]


## „XInput/0/Gamepad“ → ["XInput", "Gamepad"] (Quelle und Name ohne Nummer); sonst [].
static func _dev_kind(dev: String) -> Array:
	var m := _RX_DEV.search(dev.strip_edges())
	return [] if m == null else [m.get_string(1), m.get_string(3)]


## Abschnitt mit Belegungen für dieses Gerät (gleiche Quelle und gleicher Name), sonst null.
static func _template(text: String, prefix: String, kind: Array) -> Variant:
	for i in range(1, 5):
		var lines: Variant = Ini.section_lines(text, "%s%d" % [prefix, i])
		if lines == null:
			continue
		var dev: Variant = Ini.lines_get(lines, "Device")
		if dev != null and _dev_kind(str(dev)) == kind and (lines as Array).size() > 2:
			return lines
	return null


static func _with_device(lines: Array, dev: String, extra := {}) -> Array:
	var out: Array = []
	var put := false
	for l in lines:
		var kv := Ini.kv(str(l))
		if kv.is_empty():
			continue
		if str(kv[0]) == "Device":
			out.append("Device = " + dev)
			put = true
		elif extra.has(str(kv[0])):
			continue
		else:
			out.append("%s = %s" % [kv[0], kv[1]])
	if not put:
		out.push_front("Device = " + dev)
	for k in extra:
		out.insert(0, "%s = %s" % [k, extra[k]])
	return out


## Übliche GameCube-Belegung für ein Gerät (XInput-Namen; Dolphins SDL-Teil nimmt sie genauso).
static func gc_std(dev: String) -> Array:
	var lines: Array = ["Device = " + dev]
	for k in GC_XINPUT:
		lines.append("%s = `%s`" % [k[0], k[1]])
	lines.append("Main Stick/Dead Zone = 10.0")
	lines.append("C-Stick/Dead Zone = 10.0")
	return lines


static func wii_std(dev: String) -> Array:
	var lines: Array = ["Source = 1", "Device = " + dev, "Extension = Nunchuk"]
	for k in WII_STD:
		lines.append("%s = `%s`" % [k[0], k[1]])
	return lines


## GCPadNew.ini [GCPad1–4]: eigene Belegung für dieses Gerät übernehmen (nur das Gerät tauschen),
## sonst die übliche Belegung für XInput bzw. SDL.
static func plan_gc(text: String, players: Array) -> Dictionary:
	var out := text
	var done: Array = []
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		var sec := "GCPad%d" % (i + 1)
		var dev := dolphin_device(p)
		var kind := _dev_kind(dev)
		var tpl: Variant = _template(out, "GCPad", kind)
		var lines: Array
		if tpl != null:
			lines = _with_device(tpl, dev)
		else:
			lines = gc_std(dev)
		var old: Variant = Ini.section_lines(out, sec)
		if old == null or not _same(old, lines):
			out = Ini.set_section(out, sec, lines)
		done.append(i + 1)
	return { "text": out, "done": done, "note": "" }


## Dolphin.ini: belegte Spieler stecken als normaler GameCube-Controller (6), wenn dort nichts steckt.
## Andere Geräte (Bongos, GBA-Link …) bleiben.
static func plan_dolphin_ini(text: String, players: Array) -> Dictionary:
	var out := text
	for i in mini(players.size(), 4):
		if (players[i] as Dictionary).is_empty():
			continue
		var v: Variant = Ini.ini_get(out, "Core", "SIDevice%d" % i)
		if v == null or str(v) == "0":
			out = Ini.ini_set(out, "Core", "SIDevice%d" % i, "6")
	return { "text": out, "done": [], "note": "" }


## WiimoteNew.ini [Wiimote1–4]: als emulierte Wiimote mit eigener Belegung für dieses Gerät.
## Echte Wiimotes bleiben; ohne Vorlage für das Gerät die übliche (Wiimote mit Nunchuk, WII_STD).
static func plan_wii(text: String, players: Array) -> Dictionary:
	var out := text
	var done: Array = []
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		var sec := "Wiimote%d" % (i + 1)
		var cur: Variant = Ini.section_lines(out, sec)
		if cur != null and str(Ini.lines_get(cur, "Source")) == "2":
			continue
		var dev := dolphin_device(p)
		var tpl: Variant = _template(out, "Wiimote", _dev_kind(dev))
		var lines: Array = _with_device(tpl, dev, { "Source": "1" }) if tpl != null else wii_std(dev)
		if cur == null or not _same(cur, lines):
			out = Ini.set_section(out, sec, lines)
		done.append(i + 1)
	return { "text": out, "done": done, "note": "" }


# --- RetroArch ---------------------------------------------------------------------------------

## retroarch.cfg: input_playerN_joypad_index. Ein freier Spieler, der auf dem Gerät eines belegten
## säße, bekommt eine unbenutzte Nummer (sonst steuerte ein Controller zwei Spieler).
static func plan_retroarch(text: String, players: Array, n_pads: int) -> Dictionary:
	var c := Ini.oeffnen(text, "")
	var done := _ra_spieler(c, players, n_pads)
	return { "text": Ini.fertig(c), "done": done, "note": "" }


## Die Arbeit von plan_retroarch an der geöffneten Datei (Ini.oeffnen). Gibt die belegten Spieler zurück.
static func _ra_spieler(c: Dictionary, players: Array, n_pads: int) -> Array:
	var drv := str(Ini.wert(c, "input_joypad_driver")).trim_prefix("\"").trim_suffix("\"")
	var done: Array = []
	var used := {}
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if not p.is_empty():
			used[int(p.sdl) if drv == "sdl2" else int(p.ra)] = true
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		var key := "input_player%d_joypad_index" % (i + 1)
		var cur: Variant = Ini.wert(c, key)
		var want := ""
		if not p.is_empty():
			want = str(int(p.sdl) if drv == "sdl2" else int(p.ra))
			done.append(i + 1)
		else:
			var now := int(str(cur).trim_prefix("\"").trim_suffix("\"")) if cur != null else i
			if not used.has(now):
				continue
			var spare := maxi(n_pads, 4)
			while used.has(spare):
				spare += 1
			want = str(mini(spare, 15))
		if cur == null or str(cur).trim_prefix("\"").trim_suffix("\"") != want:
			Ini.setzen(c, key, "\"%s\"" % want)
	return done


# --- Eden, Citron, Sudachi, yuzu -----------------------------------------------------------------

## qt-config.ini [Controls]: Belegungen von player_N auf GUID und port des Controllers. Hat ein
## Spieler noch nichts, kommt die Belegung eines anderen Spielers mit SDL-Controller dazu.
static func plan_yuzu(text: String, players: Array) -> Dictionary:
	var c := Ini.oeffnen(text, "Controls")
	if int(c.i) < 0:
		return { "text": text, "done": [], "note": "noch keine Steuerung eingestellt – den Emulator einmal starten und Spieler 1 belegen" }
	var ctl := Ini.zeilen(c)
	var re_key := RegEx.create_from_string(YUZU_KEY)
	var re_port := RegEx.create_from_string("port:\\d+")
	var re_guid := RegEx.create_from_string("guid:[0-9a-fA-F]+")
	# Vorlage: die Belegung des ersten Spielers mit SDL-Controller.
	var tpl := {}
	for k in range(0, 8):
		var keys := {}
		for l in ctl:
			var kv := Ini.kv(str(l))
			if kv.is_empty() or not str(kv[0]).begins_with("player_%d_" % k) or re_key.search(str(kv[0])) == null:
				continue
			if str(kv[1]).contains("engine:sdl"):
				keys[str(kv[0]).substr(9)] = str(kv[1])
		if not keys.is_empty():
			tpl = keys
			break
	var done: Array = []
	var notes := PackedStringArray()
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		if str(p.get("guid", "")) == "":
			notes.append("Spieler %d: Controller ohne Kennung" % (i + 1))
			continue
		var pre := "player_%d_" % i
		var mine := {}
		for l in Ini.zeilen(c):
			var kv := Ini.kv(str(l))
			if not kv.is_empty() and str(kv[0]).begins_with(pre) and re_key.search(str(kv[0])) != null and str(kv[1]).contains("engine:sdl"):
				mine[str(kv[0]).substr(9)] = str(kv[1])
		var src: Dictionary = mine if not mine.is_empty() else tpl
		if src.is_empty():
			notes.append("Spieler %d einmal im Emulator belegen" % (i + 1))
			continue
		for suffix in src:
			var v := str(src[suffix])
			v = re_port.sub(v, "port:%d" % int(p.port), true)
			v = re_guid.sub(v, "guid:" + str(p.guid), true)
			_yuzu_set(c, pre + str(suffix), v)
		_yuzu_set(c, pre + "connected", "true")
		if i > 0 and str(Ini.wert(c, pre + "type")) == "4":
			_yuzu_set(c, pre + "type", "0")   # Handheld geht nur für Spieler 1
		done.append(i + 1)
	return { "text": Ini.fertig(c), "done": done, "note": "; ".join(notes) }


## Einen Schlüssel in [Controls] setzen (c: Ini.oeffnen) und sein „\\default“ auf false, damit der Emulator
## den Wert nimmt.
static func _yuzu_set(c: Dictionary, key: String, v: String) -> void:
	if str(Ini.wert(c, key)) != v:
		Ini.setzen(c, key, v)
	var dk := key + "\\default"
	var d: Variant = Ini.wert(c, dk)
	if d != null and str(d) != "false":
		Ini.setzen(c, dk, "false")


# --- Fehlende Belegung (Standard): nur, wo nichts Brauchbares steht --------------------------------

## Was gerade angeschlossen ist. { n, xi: [XInput-Anschlüsse], xi_sicher (Anschlüsse vom Helfer
## bekannt), sdl: [SDL-Nummern, die ein Controller haben kann], familien: [xbox, ps …] }.
## SDL zählt jeder Emulator selbst – als angeschlossen gelten Uzais Zählung (SpielerS.sdl_numbers),
## SDLs Spieler-Nummern und die XInput-Anschlüsse (unter SDL dieselbe Nummer).
static func geraete(pads: Array) -> Dictionary:
	var xi: Array = []
	# No longer "every number up to the controller count": with that, "SDL-0" always counted as connected
	# as soon as any controller was plugged in, even when PCSX2 saw a different device under SDL-0,
	# so the custom mapping on SDL-0 was kept and the controller did not work.
	var sdl: Array = []
	var fam: Array = []
	var sicher := true
	for p in pads:
		var x := int(p.get("xinput", -1))
		if x >= 0:
			xi.append(x)
		elif str(p.get("family", "")) == "xbox":
			sicher = false
		for v in [x, int(p.get("player", -1))]:
			if v >= 0 and not sdl.has(v):
				sdl.append(v)
		if not fam.has(str(p.get("family", "other"))):
			fam.append(str(p.get("family", "other")))
	for n in SpielerS.sdl_numbers(pads):
		if not sdl.has(int(n)):
			sdl.append(int(n))
	sdl.sort()
	return { "n": pads.size(), "xi": xi, "xi_sicher": sicher, "sdl": sdl, "familien": fam }


## „SDL-3/+LeftX“ → ["SDL", 3, "+LeftX"], sonst [].
static func _ps_teil(t: String) -> Array:
	var m := _RX_PS.search(t.strip_edges())
	return [] if m == null else [m.get_string(1), int(m.get_string(2)), m.get_string(3)]


## Warum ein Teil einer Belegung nicht geht ("" = geht) – so, wie es ins launch.log kommt. an: Quelle → ist
## sie im Emulator eingeschaltet (der Aufrufer reicht ein leeres Wörterbuch durch: So wird die Datei je
## Quelle einmal befragt statt je Taste).
static func _ps_fehler(t: Array, kind: String, text: String, g: Dictionary, an: Dictionary) -> String:
	var src := str(t[0])
	var dev := "%s-%d" % [src, int(t[1])]
	if not an.has(src):
		an[src] = _an(text, src, src == "SDL")
	if not bool(an[src]):
		return "%s war im Emulator aus" % src
	if src == "SDL" and not (g.sdl as Array).has(int(t[1])):
		return "Belegung zeigte auf %s – nicht angeschlossen" % dev
	if src == "XInput" and bool(g.xi_sicher) and not (g.xi as Array).has(int(t[1])):
		return "Belegung zeigte auf %s – nicht angeschlossen" % dev
	if src == "SDL" and kind == "duckstation" and PS_FACE.values().has(str(t[2])):
		return "Tastennamen kennt DuckStation nicht (%s)" % str(t[2])
	return ""


## Wie es um [PadN] steht: { art: eigen | leer | tastatur | aus | kaputt, geraete: [die gehen],
## grund }. Eigen heißt: mindestens eine Taste zeigt auf einen Controller, den es gibt.
static func ps_zustand(text: String, n: int, kind: String, g: Dictionary) -> Dictionary:
	var lines: Variant = Ini.section_lines(text, "Pad%d" % n)
	var typ: Variant = Ini.lines_get(lines, "Type") if lines != null else null
	if (typ == null and n > 1) or str(typ) == "None":
		return { "art": "aus", "geraete": [], "grund": "Anschluss war leer" }
	if lines == null:
		return { "art": "leer", "geraete": [], "grund": "Belegung war leer" }
	var ok: Array = []
	var bad := ""
	var kbd := false
	var an := {}
	for l in lines:
		var kv := Ini.kv(str(l))
		if kv.is_empty() or str(kv[0]) == "Type" or PS_MOTOR.has(str(kv[0])):
			continue
		for part in str(kv[1]).split(" & "):
			var t := _ps_teil(part)
			if t.is_empty():
				kbd = kbd or part.strip_edges().begins_with("Keyboard/") or part.strip_edges().begins_with("Pointer")
				continue
			var why := _ps_fehler(t, kind, text, g, an)
			var dev := "%s-%d" % [t[0], t[1]]
			if why == "":
				if not ok.has(dev):
					ok.append(dev)
			elif bad == "":
				bad = why
	if not ok.is_empty():
		return { "art": "eigen", "geraete": ok, "grund": "" }
	if bad != "":
		return { "art": "kaputt", "geraete": [], "grund": bad }
	if kbd:
		return { "art": "tastatur", "geraete": [], "grund": "Belegung war nur Tastatur" }
	return { "art": "leer", "geraete": [], "grund": "Belegung war leer" }


## PCSX2 und DuckStation: [Pad1]/[Pad2] nur dort, wo nichts Brauchbares steht. Spieler 2 nur mit
## einem zweiten Controller, der nicht schon Spieler 1 steuert. { text, done, log }.
static func plan_ps_fehlend(text: String, kind: String, players: Array, g: Dictionary) -> Dictionary:
	var out := text
	var done: Array = []
	var log: Array = []
	if kind == "duckstation":
		out = ds_namen(text)
		if out != text:
			log.append("Tastennamen repariert (FaceSouth & Co. kennt DuckStation nicht → A/B/X/Y)")
	var face := _face(out, kind)
	var st: Array = [ps_zustand(out, 1, kind, g), ps_zustand(out, 2, kind, g)]
	var used := {}
	for z in st:
		for d in z.geraete:
			used[d] = true
	for n in [1, 2]:
		var p: Dictionary = players[n - 1] if n - 1 < players.size() else {}
		if p.is_empty():
			continue
		var z: Dictionary = st[n - 1]
		if z.art == "eigen":
			log.append("Spieler %d: eigene Belegung bleibt (%s)" % [n, ", ".join(PackedStringArray(z.geraete))])
			continue
		var dev := ps_geraet(p)
		if n > 1 and used.has(dev):
			continue
		var old: Variant = Ini.section_lines(out, "Pad%d" % n)
		out = Ini.set_section(out, "Pad%d" % n, ps_lines(old, kind, dev, face))
		out = _quelle_an(out, dev)
		used[dev] = true
		done.append(n)
		log.append("Spieler %d → %s (%s)" % [n, dev, z.grund])
	return { "text": out, "done": done, "log": log }


## DuckStation kennt bei SDL nur A/B/X/Y. Uzai bis 0.15 legte neuen DuckStations „SDL-0/FaceSouth“
## an (Name aus PCSX2 2.4) – Kreuz, Kreis, Quadrat und Dreieck gingen dort nie. Nur diese Namen.
static func ds_namen(text: String) -> String:
	var out := text
	for k in PS_FACE:
		out = RegEx.create_from_string("(SDL-\\d+/)%s\\b" % str(PS_FACE[k])).sub(out, "$1" + str(k), true)
	return out


## Dolphin: Zustand eines [GCPadN]/[WiimoteN]. Keine Taste belegt → leer; Tastatur → tastatur;
## XInput-Anschluss, der nicht steckt, oder ein Controller einer Bauart, die nicht angeschlossen ist
## (DualShock-Belegung, nur Xbox-Controller da) → kaputt. Sonst eigen (auch wenn Dolphin den Namen
## anders schreibt als Uzai – im Zweifel bleibt die Belegung).
static func gc_zustand(lines: Variant, g: Dictionary) -> Dictionary:
	if lines == null:
		return { "art": "leer", "geraete": [], "grund": "Belegung war leer" }
	var dev := str(Ini.lines_get(lines, "Device")) if Ini.lines_get(lines, "Device") != null else ""
	var n_bind := 0
	for l in lines:
		var kv := Ini.kv(str(l))
		if not kv.is_empty() and str(kv[0]).contains("/") and not str(kv[0]).ends_with("Dead Zone") and str(kv[1]).strip_edges() != "":
			n_bind += 1
	var m := RegEx.create_from_string("^`?([A-Za-z0-9]+)/(\\d+)/(.+?)`?$").search(dev.strip_edges())
	if dev.strip_edges() == "" or n_bind == 0:
		return { "art": "leer", "geraete": [], "grund": "Belegung war leer" }
	if m == null:
		return { "art": "eigen", "geraete": [dev], "grund": "" }
	if m.get_string(3).to_lower().contains("keyboard"):
		return { "art": "tastatur", "geraete": [], "grund": "Belegung war nur Tastatur" }
	if m.get_string(1) == "XInput":
		if bool(g.xi_sicher) and not (g.xi as Array).has(int(m.get_string(2))):
			return { "art": "kaputt", "geraete": [], "grund": "Belegung zeigte auf %s – nicht angeschlossen" % dev }
		return { "art": "eigen", "geraete": [dev], "grund": "" }
	var fam := PadsS.family_of(m.get_string(3), -1)
	if fam != "other" and not (g.familien as Array).has(fam):
		return { "art": "kaputt", "geraete": [], "grund": "Belegung zeigte auf %s – nicht angeschlossen" % dev }
	return { "art": "eigen", "geraete": [dev], "grund": "" }


## Dolphin GameCube (GCPadNew.ini). Kaputt mit gleicher Geräte-Art: Tasten bleiben, Gerät neu;
## sonst die übliche Belegung (Tastatur-Namen passen auf keinen Controller).
static func plan_gc_fehlend(text: String, players: Array, g: Dictionary) -> Dictionary:
	return _plan_dolphin_fehlend(text, players, g, "GCPad")


## Dolphin Wii (WiimoteNew.ini): emulierte Wiimote mit Nunchuk. Echte Wiimotes (Source = 2) bleiben.
static func plan_wii_fehlend(text: String, players: Array, g: Dictionary) -> Dictionary:
	return _plan_dolphin_fehlend(text, players, g, "Wiimote")


static func _plan_dolphin_fehlend(text: String, players: Array, g: Dictionary, prefix: String) -> Dictionary:
	var out := text
	var done: Array = []
	var log: Array = []
	var st: Array = []
	var used := {}
	for i in 4:
		var cur: Variant = Ini.section_lines(text, "%s%d" % [prefix, i + 1])
		var z := gc_zustand(cur, g)
		if prefix == "Wiimote":
			var src := str(Ini.lines_get(cur, "Source")) if cur != null and Ini.lines_get(cur, "Source") != null else ("1" if i == 0 else "0")
			if src == "2":
				z = { "art": "echt", "geraete": [], "grund": "" }
			elif src != "1" and i < players.size() and not (players[i] as Dictionary).is_empty():
				z = { "art": "aus", "geraete": [], "grund": "Anschluss war leer" }
		st.append(z)
		for d in z.geraete:
			used[str(d).replace("`", "").strip_edges()] = true
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		var z: Dictionary = st[i]
		if z.art == "echt":
			log.append("Spieler %d: echte Wiimote bleibt" % (i + 1))
			continue
		if z.art == "eigen":
			log.append("Spieler %d: eigene Belegung bleibt (%s)" % [i + 1, ", ".join(PackedStringArray(z.geraete))])
			continue
		var dev := dolphin_device(p)
		if i > 0 and used.has(dev):
			continue   # dieser Controller steuert schon einen anderen Spieler
		var sec := "%s%d" % [prefix, i + 1]
		var cur: Variant = Ini.section_lines(out, sec)
		var old_dev := str(Ini.lines_get(cur, "Device")) if cur != null and Ini.lines_get(cur, "Device") != null else ""
		var lines: Array
		var extra := { "Source": "1" } if prefix == "Wiimote" else {}
		if z.art == "kaputt" and _dev_kind(old_dev).size() == 2 and str(_dev_kind(old_dev)[0]) == str(_dev_kind(dev)[0]):
			lines = _with_device(cur, dev, extra)
		else:
			lines = wii_std(dev) if prefix == "Wiimote" else gc_std(dev)
		out = Ini.set_section(out, sec, lines)
		used[dev] = true
		done.append(i + 1)
		log.append("Spieler %d → %s (%s)" % [i + 1, dev, z.grund])
	return { "text": out, "done": done, "log": log }


## Dolphin.ini: Steckt im GameCube-Anschluss eines Spielers nichts (0), steckt Uzai einen normalen
## Controller (6) hinein. Fehlt der Schlüssel, gilt bei Anschluss 1 schon der Controller.
static func plan_dolphin_ini_fehlend(text: String, players: Array) -> Dictionary:
	var out := text
	var log: Array = []
	for i in mini(players.size(), 4):
		if (players[i] as Dictionary).is_empty():
			continue
		var v: Variant = Ini.ini_get(out, "Core", "SIDevice%d" % i)
		if (v == null and i > 0) or str(v) == "0":
			out = Ini.ini_set(out, "Core", "SIDevice%d" % i, "6")
			log.append("Spieler %d: GameCube-Anschluss war leer – Controller eingesteckt" % (i + 1))
	return { "text": out, "done": [], "log": log }


## RetroArch belegt Controller selbst (Autoconfig). Uzai sorgt nur dafür, dass Autoconfig an ist und
## Spieler 1 auf ein Gerät zeigt, das es gibt.
static func plan_ra_fehlend(text: String, players: Array, g: Dictionary) -> Dictionary:
	var c := Ini.oeffnen(text, "")
	var log: Array = []
	var done: Array = []
	_ra_autoconfig(c, log)
	var p: Dictionary = players[0] if not players.is_empty() else {}
	if p.is_empty():
		return { "text": Ini.fertig(c), "done": done, "log": log }
	var drv := _roh(Ini.wert(c, "input_joypad_driver"))
	var want := int(p.sdl) if drv == "sdl2" else int(p.ra)
	var cur: Variant = Ini.wert(c, "input_player1_joypad_index")
	var idx := int(_roh(cur)) if cur != null and _roh(cur).is_valid_int() else 0
	if cur == null or idx < int(g.n) or idx == want:
		log.append("Spieler 1: Gerät %d (Autoconfig von RetroArch)" % idx)
	else:
		Ini.setzen(c, "input_player1_joypad_index", "\"%d\"" % want)
		done.append(1)
		log.append("Spieler 1 → Gerät %d (Belegung zeigte auf Gerät %d – nicht angeschlossen)" % [want, idx])
	return { "text": Ini.fertig(c), "done": done, "log": log }


## Autoconfig einschalten, wenn es aus ist (c: Ini.oeffnen der retroarch.cfg).
static func _ra_autoconfig(c: Dictionary, log: Array) -> void:
	var auto: Variant = Ini.wert(c, "input_autodetect_enable")
	if auto != null and _roh(auto) == "false":
		Ini.setzen(c, "input_autodetect_enable", "\"true\"")
		log.append("Autoconfig war aus – jetzt an (RetroArch belegt den Controller selbst)")


static func _roh(v: Variant) -> String:
	return "" if v == null else str(v).strip_edges().trim_prefix("\"").trim_suffix("\"").to_lower()


## PPSSPP (controls.ini): Ohne [ControlMapping] gilt PPSSPPs Standard – mit Controller. Steht dort
## gar kein Controller (Geräte ab 10: Pads, 20–23 XInput), nimmt Uzai den Abschnitt heraus; PPSSPP
## setzt dann wie bei „Standard wiederherstellen“ seine Belegung ein.
static func plan_ppsspp_fehlend(text: String, g: Dictionary) -> Dictionary:
	var sec: Variant = Ini.section_lines(text, "ControlMapping")
	if sec == null:
		return { "text": text, "done": [], "log": ["Spieler 1: Standardbelegung von PPSSPP (mit Controller)"] }
	var pad := false
	for l in sec:
		var kv := Ini.kv(str(l))
		if kv.is_empty():
			continue
		for item in str(kv[1]).split(","):
			for m in item.split(":"):
				var d := m.strip_edges().get_slice("-", 0)
				if d.is_valid_int() and int(d) >= 10:
					pad = true
	if pad or int(g.n) == 0:
		return { "text": text, "done": [], "log": ["Spieler 1: eigene Belegung bleibt"] }
	return { "text": Ini.set_section(text, "ControlMapping", null), "done": [1],
		"log": ["Spieler 1 → Standardbelegung von PPSSPP (Belegung war nur Tastatur)"] }


## Eden & Co. (qt-config.ini): Spieler 1 mit SDL-Belegung bleibt. Hat nur ein anderer Spieler eine,
## bekommt Spieler 1 sie (die rohen Tastennummern stammen dann vom Emulator selbst). Sonst nur ein
## Hinweis – raten hieße hier: keine Eingabe.
static func plan_yuzu_fehlend(text: String, players: Array) -> Dictionary:
	if players.is_empty() or (players[0] as Dictionary).is_empty():
		return { "text": text, "done": [], "log": [] }
	var c := Ini.oeffnen(text, "Controls")
	if int(c.i) < 0:
		return { "text": text, "done": [], "log": ["noch keine Steuerung eingestellt – den Emulator einmal starten"] }
	var re_key := RegEx.create_from_string(YUZU_KEY)
	var by := {}
	for l in Ini.zeilen(c):
		var kv := Ini.kv(str(l))
		if kv.is_empty() or re_key.search(str(kv[0])) == null or not str(kv[1]).contains("engine:sdl"):
			continue
		var k := int(str(kv[0]).substr(7, 1))
		if not by.has(k):
			by[k] = {}
		by[k][str(kv[0]).substr(9)] = str(kv[1])
	if by.has(0):
		if str(Ini.wert(c, "player_0_connected")) == "false":
			_yuzu_set(c, "player_0_connected", "true")
			return { "text": Ini.fertig(c), "done": [1], "log": ["Spieler 1: eigene Belegung bleibt, war ausgesteckt – eingesteckt"] }
		return { "text": text, "done": [], "log": ["Spieler 1: eigene Belegung bleibt (SDL)"] }
	var ks: Array = by.keys()
	ks.sort()
	if ks.is_empty():
		return { "text": text, "done": [], "log": ["Spieler 1 hat nur Tastatur – im Emulator unter Steuerung einmal den Controller als Eingabegerät wählen"] }
	var src: Dictionary = by[ks[0]]
	for suffix in src:
		_yuzu_set(c, "player_0_" + str(suffix), str(src[suffix]))
	_yuzu_set(c, "player_0_connected", "true")
	return { "text": Ini.fertig(c), "done": [1], "log": ["Spieler 1 → Belegung von Spieler %d übernommen (Belegung war nur Tastatur)" % (int(ks[0]) + 1)] }


static func plan_fehlend(art: String, kind: String, text: String, players: Array, g: Dictionary) -> Dictionary:
	match art:
		"ps":
			return plan_ps_fehlend(text, kind, players, g)
		"gc":
			return plan_gc_fehlend(text, players, g)
		"core":
			return plan_dolphin_ini_fehlend(text, players)
		"wii":
			return plan_wii_fehlend(text, players, g)
		"ra":
			return plan_ra_fehlend(text, players, g)
		"pp":
			return plan_ppsspp_fehlend(text, g)
		"yuzu":
			return plan_yuzu_fehlend(text, players)
	return {}


## Spieler für „fehlende Belegung“: die Zuordnung; ist Platz 1 frei, aber ein Controller da (Automatik
## aus), gilt der erste Controller als Spieler 1.
static func spieler_fehlend(slots: Array, pads: Array) -> Array:
	var pl := SpielerS.players(slots, pads)
	if (pl[0] as Dictionary).is_empty() and not pads.is_empty():
		var ids := SpielerS.ids_for(pads)
		var s := SpielerS.norm_slots(slots)
		for i in pads.size():
			if not s.has(str(ids[i].id)):
				s[0] = str(ids[i].id)
				break
		pl = SpielerS.players(s, pads)
	return pl


## Belegungen schreiben – start: nach der Regel „Spieler 1 = benutzter Controller“ (plan_start), sonst
## nur Fehlendes (plan_fehlend). { files, done, log: [Zeilen fürs launch.log], found }.
static func fehlend(kind: String, exe: String, system: String, players: Array, g: Dictionary, env: Dictionary = {}, start := false) -> Dictionary:
	var res := { "files": [], "done": [], "log": [], "found": false }
	if exe == "" or not (supported(kind) or kind == "ppsspp"):
		res.log = ["richtet Uzai nicht ein – die Belegung kommt vom Emulator"]
		return res
	if int(g.get("n", 0)) == 0:
		res.log = ["kein Controller angeschlossen – nichts geändert"]
		return res
	if env.is_empty():
		env = env_now()
	var roots: Array = [exe.get_base_dir(), env.docs, env.appdata, env.localappdata].filter(func(r): return str(r) != "")
	var gesucht: Array = []
	for f in files_for(kind, exe, system, env):
		var path := str(f[0])
		var wo := str(f[2]) if (f as Array).size() > 2 else ""
		if not path_ok(path, roots, true):
			gesucht.append(path + (" (%s)" % wo if wo != "" else ""))
			continue
		res.found = true
		(res.log as Array).append("Datei %s%s" % [path, " (%s)" % wo if wo != "" else ""])
		var roh := Ini.lesen_treu(path)
		if not bool(roh.ok):
			(res.log as Array).append((Ini.FREMD_KODIERT % path.get_file()) + " – nichts geändert")
			continue
		var text := str(roh.text)
		var gp := g
		if str(f[1]) == "ps":
			gp = g.duplicate()
			gp["mt_uzai"] = mt_von_uzai(path)
		var plan := plan_start(str(f[1]), kind, text, players, gp) if start else plan_fehlend(str(f[1]), kind, text, players, g)
		if plan.is_empty():
			continue
		(res.log as Array).append_array(plan.get("log", []))
		if kind == "pcsx2" and start:
			var eigene := pcsx2_spiel_eigene(path)
			if eigene > 0:
				(res.log as Array).append(
						"%d Spiele haben in PCSX2 eigene Controller-Einstellungen (gamesettings) – dort gilt die Belegung des Spiels, nicht diese" % eigene)
		if str(plan.text) == text:
			continue
		if not backup(kind, path):
			(res.log as Array).append("%s ließ sich nicht sichern – nichts geändert" % path.get_file())
			continue
		if write_text(path, str(plan.text), bool(roh.bom)):
			(res.files as Array).append(path)
			_mt_merken(path, str(plan.get("mt", "")))
			for d in plan.get("done", []):
				if not (res.done as Array).has(d):
					(res.done as Array).append(d)
		else:
			(res.log as Array).append("%s ist schreibgeschützt – nichts geändert" % path.get_file())
	if not res.found:
		res.log = ["Einstellungen nicht gefunden – den Emulator einmal normal starten (dann richtet Uzai ihn ein)"]
		for p in gesucht:
			(res.log as Array).append("gesucht: " + str(p))
	return res


# --- Mit diesem Controller gestartet (Standard): Spieler 1 = der benutzte Controller ------------------

## Wer im Emulator welcher Spieler ist. Spieler 1 ist der Controller, mit dem das Spiel gestartet wurde
## (benutzt: seine Kennung aus Pads.benutzt_id, "" wenn keiner) – auch wenn die Zuordnung in Uzai einen
## anderen zeigt. Wer bisher Spieler 1 war, rückt auf den Platz des benutzten (Freunde behalten ihre
## Reihenfolge, Spieler 2–4 sonst nach src/core/spieler.gd). Ausnahme: Spielen mehrere und hat der
## Nutzer Spieler 1 selbst einem anderen angeschlossenen Controller gegeben (spieler.gemerkt), bleibt
## das. Mit nur einem Spieler ist Spieler 1 immer der benutzte. Ohne benutzten Controller (Start mit
## Maus/Tastatur) gilt die Zuordnung (spieler_fehlend). Rückgabe { players, slots, name, grund }.
static func spieler_start(slots: Array, pads: Array, mem: Dictionary, benutzt: String) -> Dictionary:
	var s := SpielerS.norm_slots(slots)
	var conn: Array = SpielerS.ids_for(pads).map(func(e): return str(e.id))
	if benutzt == "" or not conn.has(benutzt):
		var pl := spieler_fehlend(s, pads)
		var p0: Dictionary = pl[0]
		return { "players": pl, "slots": s, "name": str(p0.get("name", "")),
			"grund": "" if p0.is_empty() else "kein Controller beim Start benutzt – nach Uzais Zuordnung" }
	var belegt := s.filter(func(x): return x != "" and conn.has(x)).size()
	var holder: String = s[0]
	var grund := "mit diesem Controller gestartet"
	if holder != benutzt and holder != "" and conn.has(holder) and int(mem.get(holder, -1)) == 1 and belegt >= 2:
		grund = "selbst zugeordnet (Guide › Spieler & Controller)"
	elif holder != benutzt:
		var w := s.find(benutzt)
		s[0] = benutzt
		if w >= 0:
			s[w] = holder
		elif holder != "":
			var free := s.find("")
			if free >= 0:
				s[free] = holder
	var pl2 := SpielerS.players(s, pads)
	return { "players": pl2, "slots": s, "name": str((pl2[0] as Dictionary).get("name", "")), "grund": grund }


## Fürs launch.log: jeder Controller mit allem, woran man ihn im Emulator erkennt. Eine Zeile je Gerät.
static func geraete_log(pads: Array, benutzt: String) -> Array:
	var out: Array = []
	var sdl := SpielerS.sdl_numbers(pads)
	for i in pads.size():
		var p: Dictionary = pads[i]
		var xi := int(p.get("xinput", -1))
		var g := str(p.get("guid", ""))
		out.append("Gerät %d: %s · %s · GUID %s · XInput %s · SDL-%d (SDL-Spieler %d)%s" % [int(p.get("device", -1)), str(p.get("name", "Controller")),
			str(p.get("family", "other")), g if g != "" else "?", "Anschluss %d" % xi if xi >= 0 else "–", int(sdl[i]), int(p.get("player", -1)),
			" · damit gestartet" if benutzt != "" and str(p.get("uz_id", "")) == benutzt else ""])
	return out


## Warum ein Gerät so heißt (für die Zeile „Spieler 1 → …“).
## XInput-Anschlüsse kennt der Windows-Helfer sicher; SDL-Nummern vergibt der Emulator selbst beim
## Öffnen der Geräte – Uzai zählt sie wie er, sicher ist das nicht (darum steht es im Log).
static func _wie(dev: String, p: Dictionary) -> String:
	if dev.begins_with("XInput"):
		return "XInput-Anschluss %d vom Windows-Helfer" % int(p.get("xinput", 0))
	return "kein XInput-Gerät – SDL-Nummer wie in Uzai gezählt, %s" % str(p.get("name", "Controller"))


## PCSX2 und DuckStation beim Start: [Pad1]/[Pad2] auf die Geräte der Spieler – auch wenn eine Belegung
## auf ein anderes Gerät zeigt. Eigene Tasten bleiben (nur das Gerät wechselt, wie „Immer nach Uzais
## Zuordnung“), fehlende bekommen die übliche Belegung. Ohne Spieler 2 und zeigt [Pad2] auf das Gerät
## von Spieler 1, wandert [Pad2] auf eine freie Nummer (sonst steuerte ein Controller beide).
static func plan_ps_start(text: String, kind: String, players: Array, g: Dictionary) -> Dictionary:
	var out := text
	var done: Array = []
	var log: Array = []
	if kind == "duckstation":
		out = ds_namen(text)
		if out != text:
			log.append("Tastennamen repariert (FaceSouth & Co. kennt DuckStation nicht → A/B/X/Y)")
	var face := _face(out, kind)
	var devs := {}
	for n in [1, 2]:
		var p: Dictionary = players[n - 1] if n - 1 < players.size() else {}
		if not p.is_empty():
			devs[ps_geraet(p)] = n
	for n in [1, 2]:
		var p: Dictionary = players[n - 1] if n - 1 < players.size() else {}
		var sec := "Pad%d" % n
		var old: Variant = Ini.section_lines(out, sec)
		var z := ps_zustand(out, n, kind, g)
		if p.is_empty():
			if n == 2 and z.art == "eigen":
				out = _pad2_frei(out, kind, devs, g, face, log)
			continue
		var dev := ps_geraet(p)
		var neu := ps_lines(old, kind, dev, face)
		var vorher := out
		if old == null or not _same(old, neu):
			out = Ini.set_section(out, sec, neu)
		out = _quelle_an(out, dev)
		if out == vorher:
			log.append("Spieler %d: %s (stimmt schon; %s)" % [n, dev, _wie(dev, p)])
			continue
		var warum := str(z.grund)
		if z.art == "eigen":
			warum = "Belegung zeigte auf %s" % ", ".join(PackedStringArray(z.geraete))
			if (z.geraete as Array) == [dev]:
				warum = "fehlende Tasten ergänzt"
		done.append(n)
		log.append("Spieler %d → %s (%s; %s)" % [n, dev, warum, _wie(dev, p)])
	var mt := plan_ps_multitap(out, kind, players, face, bool(g.get("mt_uzai", false)), done, log)
	return { "text": str(mt.text), "done": done, "log": log, "mt": str(mt.mt) }


## [Pad2] ohne Spieler 2: Zeigt es auf ein Gerät eines Spielers, auf eine freie Nummer derselben Quelle.
static func _pad2_frei(text: String, kind: String, devs: Dictionary, g: Dictionary, face: bool, log: Array) -> String:
	var lines: Variant = Ini.section_lines(text, "Pad2")
	if lines == null:
		return text
	var hit := ""
	for l in lines:
		var kv := Ini.kv(str(l))
		if kv.is_empty():
			continue
		for part in str(kv[1]).split(" & "):
			var t := _ps_teil(part)
			if not t.is_empty() and devs.has("%s-%d" % [t[0], t[1]]):
				hit = "%s-%d" % [t[0], t[1]]
	if hit == "":
		return text
	var src := hit.get_slice("-", 0)
	var belegt: Array = (g.get("xi", []) as Array) if src == "XInput" else (g.get("sdl", []) as Array)
	var n := 0
	while belegt.has(n) or devs.has("%s-%d" % [src, n]):
		n += 1
	if src == "XInput" and n > 3:
		log.append("Spieler 2 hört auch auf %s – kein freier XInput-Anschluss, bleibt" % hit)
		return text
	var spare := "%s-%d" % [src, n]
	var neu: Array = []
	for l in lines:
		var kv := Ini.kv(str(l))
		if kv.is_empty() or not _is_pad_value(str(kv[1])):
			neu.append(l)
			continue
		var parts := PackedStringArray()
		for part in str(kv[1]).split(" & "):
			var t := _ps_teil(part)
			parts.append(retarget(part.strip_edges(), spare, kind) if not t.is_empty() and "%s-%d" % [t[0], t[1]] == hit else part.strip_edges())
		neu.append("%s = %s" % [kv[0], " & ".join(parts)])
	log.append("Spieler 2 zeigte auch auf %s (Gerät von Spieler 1) → %s, bis ein zweiter Controller da ist" % [hit, spare])
	return Ini.set_section(text, "Pad2", neu)


## Dolphin beim Start (GCPadNew.ini bzw. WiimoteNew.ini): jeder Spieler auf sein Gerät. Eigene Tasten
## für dieses Gerät bleiben (auch aus einem anderen Anschluss mit demselben Gerät), bei gleicher Quelle
## (XInput → XInput) nur das Gerät tauschen, sonst die übliche Belegung. Echte Wiimotes bleiben.
static func plan_dolphin_start(text: String, players: Array, g: Dictionary, prefix: String) -> Dictionary:
	var out := text
	var done: Array = []
	var log: Array = []
	for i in mini(players.size(), 4):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		var sec := "%s%d" % [prefix, i + 1]
		var cur: Variant = Ini.section_lines(out, sec)
		var src_v: Variant = Ini.lines_get(cur, "Source") if cur != null else null
		if prefix == "Wiimote" and src_v != null and str(src_v) == "2":
			log.append("Spieler %d: echte Wiimote bleibt" % (i + 1))
			continue
		var dev := dolphin_device(p)
		var z := gc_zustand(cur, g)
		var old_dev := str(Ini.lines_get(cur, "Device")).replace("`", "").strip_edges() if cur != null and Ini.lines_get(cur, "Device") != null else ""
		var extra := { "Source": "1" } if prefix == "Wiimote" else {}
		var lines: Array
		# Vorlage aus der Datei, wie sie vor dem Start war (ein getauschter Anschluss nimmt seine Tasten mit).
		var tpl: Variant = _template(text, prefix, _dev_kind(dev))
		if tpl == null:
			tpl = _template(out, prefix, _dev_kind(dev))
		if cur != null and z.art == "eigen" and _dev_kind(old_dev) == _dev_kind(dev):
			lines = _with_device(cur, dev, extra)
		elif tpl != null:
			lines = _with_device(tpl, dev, extra)
		elif cur != null and z.art in ["eigen", "kaputt"] and _dev_kind(old_dev).size() == 2 and str(_dev_kind(old_dev)[0]) == str(_dev_kind(dev)[0]):
			lines = _with_device(cur, dev, extra)
		else:
			lines = wii_std(dev) if prefix == "Wiimote" else gc_std(dev)
		if cur != null and _same(cur, lines):
			log.append("Spieler %d: %s (stimmt schon)" % [i + 1, dev])
			continue
		out = Ini.set_section(out, sec, lines)
		done.append(i + 1)
		var warum := str(z.grund) if z.art != "eigen" else "Belegung zeigte auf %s" % old_dev
		log.append("Spieler %d → %s (%s)" % [i + 1, dev, warum])
	return { "text": out, "done": done, "log": log }


## RetroArch beim Start: mit einem Controller wie bisher (nur Autoconfig und ein Gerät, das es gibt);
## mit mehreren je Spieler sein Gerät (Spieler 1 = benutzter Controller).
static func plan_ra_start(text: String, players: Array, g: Dictionary) -> Dictionary:
	if int(g.get("n", 0)) < 2:
		return plan_ra_fehlend(text, players, g)
	var c := Ini.oeffnen(text, "")
	var log: Array = []
	_ra_autoconfig(c, log)
	var vor := {}
	for n in range(1, 5):
		vor[n] = _roh(Ini.wert(c, "input_player%d_joypad_index" % n))
	var done := _ra_spieler(c, players, int(g.n))
	for d in done:
		var nach := _roh(Ini.wert(c, "input_player%d_joypad_index" % int(d)))
		var neu: bool = str(vor[int(d)]) != nach
		log.append("Spieler %d%s Gerät %s%s" % [int(d), " →" if neu else ":", nach, "" if neu else " (stimmt schon)"])
	return { "text": Ini.fertig(c), "done": done, "log": log }


static func plan_start(art: String, kind: String, text: String, players: Array, g: Dictionary) -> Dictionary:
	match art:
		"ps":
			return plan_ps_start(text, kind, players, g)
		"gc":
			return plan_dolphin_start(text, players, g, "GCPad")
		"wii":
			return plan_dolphin_start(text, players, g, "Wiimote")
		"ra":
			return plan_ra_start(text, players, g)
		"yuzu":
			return plan_yuzu_start(text, players)
	return plan_fehlend(art, kind, text, players, g)


## Eden & Co. beim Start: Spieler 1 wie bisher (plan_yuzu_fehlend). Spieler 2–4 bekommen eine
## SDL-Belegung desselben Controller-Modells (gleiche GUID, die Prüfsumme in der GUID zählt nicht) –
## die eigene oder die eines anderen Spielers –, mit ihrem Anschluss (port) und eingesteckt. Die GUID
## bleibt, wie der Emulator sie schrieb. Für ein anderes Modell: Hinweis, einmal im Emulator belegen
## (die rohen Tastennummern kennt nur der Emulator).
static func plan_yuzu_start(text: String, players: Array) -> Dictionary:
	var r := plan_yuzu_fehlend(text, players)
	if players.size() < 2:
		return r
	var c := Ini.oeffnen(str(r.text), "Controls")
	if int(c.i) < 0:
		return r
	var done: Array = (r.get("done", []) as Array).duplicate()
	var log: Array = (r.get("log", []) as Array).duplicate()
	var re_key := RegEx.create_from_string(YUZU_KEY)
	var re_port := RegEx.create_from_string("port:\\d+")
	var re_guid := RegEx.create_from_string("guid:([0-9a-fA-F]+)")
	var by := {}
	var modell := {}
	for l in Ini.zeilen(c):
		var kv := Ini.kv(str(l))
		if kv.is_empty() or re_key.search(str(kv[0])) == null or not str(kv[1]).contains("engine:sdl"):
			continue
		var k := int(str(kv[0]).substr(7, 1))
		if not by.has(k):
			by[k] = {}
		by[k][str(kv[0]).substr(9)] = str(kv[1])
		var m := re_guid.search(str(kv[1]))
		if m != null and not modell.has(k):
			modell[k] = _modell(m.get_string(1))
	var ks: Array = by.keys()
	ks.sort()
	for i in range(1, mini(players.size(), 4)):
		var p: Dictionary = players[i]
		if p.is_empty():
			continue
		var name := str(p.get("name", "Controller"))
		var mg := _modell(str(p.get("guid", "")))
		if mg == "":
			log.append("Spieler %d: %s ohne Kennung – im Emulator belegen" % [i + 1, name])
			continue
		var src := {}
		if by.has(i) and str(modell.get(i, "")) == mg:
			src = by[i]
		else:
			for k in ks:
				if str(modell.get(k, "")) == mg:
					src = by[k]
					break
		if src.is_empty():
			log.append("Spieler %d: %s einmal im Emulator belegen (für dieses Modell gibt es noch keine Belegung)" % [i + 1, name])
			continue
		var pre := "player_%d_" % i
		var vorher := Ini.geaendert(c)
		for suffix in src:
			_yuzu_set(c, pre + str(suffix), re_port.sub(str(src[suffix]), "port:%d" % int(p.get("port", 0)), true))
		if str(Ini.wert(c, pre + "connected")) != "true":
			_yuzu_set(c, pre + "connected", "true")
		if str(Ini.wert(c, pre + "type")) == "4":
			_yuzu_set(c, pre + "type", "0")   # Handheld geht nur für Spieler 1
		if Ini.geaendert(c) == vorher:
			log.append("Spieler %d: %s (stimmt schon)" % [i + 1, name])
			continue
		done.append(i + 1)
		log.append("Spieler %d → %s (Anschluss %d)" % [i + 1, name, int(p.get("port", 0))])
	return { "text": Ini.fertig(c), "done": done, "log": log }


## SDL-GUID ohne Prüfsumme (Zeichen 4–7: neuere SDL tragen dort eine CRC ein, ältere 0000).
static func _modell(guid: String) -> String:
	var g := guid.strip_edges().to_lower()
	if g.length() != 32:
		return ""
	return g.substr(0, 4) + "0000" + g.substr(8)


## PCSX2: Spiele mit eigenen Controller-Einstellungen (gamesettings\*.ini mit „UseGameSettingsForController“
## oder einem Eingabeprofil) – dort gilt die Belegung des Spiels, nicht [Pad1] aus PCSX2.ini. Nur lesen.
static func pcsx2_spiel_eigene(ini: String) -> int:
	var dir := ini.get_base_dir().get_base_dir().path_join("gamesettings")
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	# Bis zu 400 Dateien lesen, vor jedem Start, für eine Zeile im Protokoll: nur, wenn sich der Ordner geändert
	# hat. (Eine Änderung in einer bestehenden Datei fällt so erst nach dem Neustart von Uzai auf.)
	var dateien := DirAccess.get_files_at(dir)
	var stand := [FileAccess.get_modified_time(dir), dateien.size()]
	var merk: Variant = _eigene_merk.get(dir)
	if merk is Array and (merk as Array).slice(0, 2) == stand:
		return int(merk[2])
	var n := 0
	var seen := 0
	for f in dateien:
		if not f.to_lower().ends_with(".ini") or seen >= 400:
			continue
		seen += 1
		var p := dir.path_join(f)
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa == null or fa.get_length() > 256 * 1024:
			continue
		var t := fa.get_as_text()
		fa.close()
		if _RX_EIGENE.search(t) != null:
			n += 1
	_eigene_merk[dir] = [stand[0], stand[1], n]
	return n


# --- Dateien -----------------------------------------------------------------------------------

## Darf Uzai diese Datei schreiben? Bekannter Name, kein „..“, unter einem der Ordner des Emulators,
## vorhanden und nicht riesig. neu: GCPadNew.ini/WiimoteNew.ini dürfen fehlen (oder leer sein), wenn
## daneben Dolphin.ini liegt – Dolphin legt sie erst an, wenn man die Steuerung öffnet.
static func path_ok(path: String, roots: Array, neu := false) -> bool:
	var p := path.replace("\\", "/")
	if p == "" or p.contains("/../") or p.ends_with("/..") or p.contains("/./") or not p.get_file().to_lower() in FILES:
		return false
	if not (p.begins_with("/") or (p.length() > 2 and p[1] == ":")):
		return false
	var inside := false
	for r in roots:
		var rr := str(r).replace("\\", "/").trim_suffix("/")
		if rr.length() > 3 and p.to_lower().begins_with(rr.to_lower() + "/"):
			inside = true
	if not inside:
		return false
	var darf_neu := neu and p.get_file().to_lower() in NEU_OK and FileAccess.file_exists(p.get_base_dir().path_join("Dolphin.ini"))
	if not FileAccess.file_exists(p):
		return darf_neu
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return false
	var n := f.get_length()
	f.close()
	return (n > 0 or darf_neu) and n <= MAX_BYTES


## Welche Dateien zu einem Emulator gehören: [[Pfad, Art]] (Art: ps, gc, core, wii, ra, pp, yuzu).
## Dolphin: Fehlt GCPadNew.ini bzw. WiimoteNew.ini, steht der Pfad neben Dolphin.ini (path_ok mit neu).
static func files_for(kind: String, exe: String, system: String, env: Dictionary) -> Array:
	var dir := exe.get_base_dir()
	var out: Array = []
	if kind == "retroarch":
		var ra := Ini.newest([dir.path_join("retroarch.cfg"), str(env.appdata).path_join("RetroArch/retroarch.cfg")])
		return [[ra, "ra"]] if ra != "" else []
	if kind == "ppsspp":
		var pp := Ini.newest([dir.path_join("memstick/PSP/SYSTEM/controls.ini"), str(env.docs).path_join("PPSSPP/PSP/SYSTEM/controls.ini")])
		return [[pp, "pp"]] if pp != "" else []
	var c := Ini.candidates(kind, dir, str(env.docs), str(env.appdata), str(env.localappdata), Ini.is_portable(kind, dir))
	match kind:
		"pcsx2", "duckstation":
			var pi := ps_ini(kind, exe, env)
			out.append([str(pi[0]), "ps", str(pi[1]) + ("" if str(pi[0]) == "" or FileAccess.file_exists(str(pi[0])) else ", fehlt")])
		"dolphin":
			var core := Ini.newest(c.get("core", []))
			var pad := "wii" if system == "wii" else "gc"
			var f := Ini.newest(c.get(pad, []))
			if f == "" and core != "":
				f = core.get_base_dir().path_join("WiimoteNew.ini" if pad == "wii" else "GCPadNew.ini")
			out.append([f, pad])
			if pad == "gc":
				out.append([core, "core"])
		_:
			if Ini.YUZU_LIKE.has(kind):
				out.append([Ini.newest(c.get("ini", [])), "yuzu"])
	return out.filter(func(e): return str(e[0]) != "")


## PCSX2 und DuckStation: genau die Einstellungsdatei, die der Emulator liest, und warum – wie in
## ihren Quelltexten (Stand 2026):
## - PCSX2 (pcsx2/Pcsx2Config.cpp, EmuFolders::SetDataDirectory): portable.ini oder portable.txt neben
##   der exe → tragbar, Daten neben der exe (portable.txt darf einen Unterordner nennen); sonst
##   Dokumente\PCSX2 (auch umgeleitet, z. B. OneDrive – Godot fragt Windows wie PCSX2). Die Datei ist
##   immer inis\PCSX2.ini darunter. %APPDATA% nutzt PCSX2 unter Windows nicht.
## - DuckStation (src/core/core.cpp): portable.txt oder settings.ini neben der exe → dort; sonst
##   Dokumente\DuckStation, wenn es den Ordner gibt (alte Installationen); sonst %LOCALAPPDATA%\DuckStation.
## Von Uzai installiert (retro_auto.gd): PCSX2 mit portable.ini, DuckStation mit portable.txt.
## Rückgabe [Pfad, warum]; Pfad "" wenn Uzai ihn nicht anfassen darf.
static func ps_ini(kind: String, exe: String, env: Dictionary) -> Array:
	var dir := exe.get_base_dir()
	if kind == "pcsx2":
		var pt := dir.path_join("portable.txt")
		var pini := FileAccess.file_exists(dir.path_join("portable.ini"))
		if pini or FileAccess.file_exists(pt):
			var sub := FileAccess.get_file_as_string(pt).strip_edges().replace("\\", "/") if FileAccess.file_exists(pt) else ""
			if sub != "" and (sub.contains("..") or sub.begins_with("/") or sub.contains(":")):
				return ["", "portable.txt nennt einen Ordner außerhalb von PCSX2 – Uzai lässt ihn aus"]
			var root := dir.path_join(sub) if sub != "" else dir
			return [root.path_join("inis/PCSX2.ini"), "tragbar: %s neben %s" % ["portable.ini" if pini else "portable.txt", exe.get_file()]]
		if str(env.get("docs", "")) == "":
			return ["", "Dokumente-Ordner unbekannt"]
		return [str(env.docs).path_join("PCSX2/inis/PCSX2.ini"), "nicht tragbar: Dokumente\\PCSX2"]
	if FileAccess.file_exists(dir.path_join("portable.txt")) or FileAccess.file_exists(dir.path_join("settings.ini")):
		return [dir.path_join("settings.ini"), "tragbar: neben " + exe.get_file()]
	var docs := str(env.get("docs", ""))
	if docs != "" and DirAccess.dir_exists_absolute(docs.path_join("DuckStation")):
		return [docs.path_join("DuckStation/settings.ini"), "Dokumente\\DuckStation"]
	var la := str(env.get("localappdata", ""))
	return [la.path_join("DuckStation/settings.ini") if la != "" else "", "%LOCALAPPDATA%\\DuckStation"]


static func plan_for(art: String, kind: String, text: String, players: Array, n_pads: int, mt_uzai := false) -> Dictionary:
	match art:
		"ps":
			return plan_ps(text, "DualShock2" if kind == "pcsx2" else "AnalogController", players, mt_uzai)
		"gc":
			return plan_gc(text, players)
		"core":
			return plan_dolphin_ini(text, players)
		"wii":
			return plan_wii(text, players)
		"ra":
			return plan_retroarch(text, players, n_pads)
		"yuzu":
			return plan_yuzu(text, players)
	return {}


static func env_now() -> Dictionary:
	return { "docs": OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).replace("\\", "/"), "appdata": OS.get_environment("APPDATA").replace("\\", "/"),
		"localappdata": OS.get_environment("LOCALAPPDATA").replace("\\", "/") }


## Einrichten. Rückgabe { files: [geschriebene Pfade], done: [Spieler], note, found (Datei gefunden) }.
static func apply(kind: String, exe: String, system: String, players: Array, n_pads: int, env: Dictionary = {}) -> Dictionary:
	var res := { "files": [], "done": [], "note": "", "found": false }
	if not supported(kind) or exe == "":
		return res
	if env.is_empty():
		env = env_now()
	var roots: Array = [exe.get_base_dir(), env.docs, env.appdata, env.localappdata].filter(func(r): return str(r) != "")
	var notes := PackedStringArray()
	for f in files_for(kind, exe, system, env):
		var path := str(f[0])
		if not path_ok(path, roots, true):
			continue
		res.found = true
		var roh := Ini.lesen_treu(path)
		if not bool(roh.ok):
			notes.append(Ini.FREMD_KODIERT % path.get_file())
			continue
		var text := str(roh.text)
		var plan := plan_for(str(f[1]), kind, text, players, n_pads, mt_von_uzai(path))
		if plan.is_empty():
			continue
		if str(plan.get("note", "")) != "":
			notes.append(str(plan.note))
		for d in plan.get("done", []):
			if not (res.done as Array).has(d):
				(res.done as Array).append(d)
		if str(plan.text) == text:
			continue
		if not backup(kind, path):
			notes.append("%s ließ sich nicht sichern – Uzai lässt sie, wie sie ist" % path.get_file())
			continue
		if write_text(path, str(plan.text), bool(roh.bom)):
			(res.files as Array).append(path)
			_mt_merken(path, str(plan.get("mt", "")))
		else:
			notes.append("%s ist schreibgeschützt" % path.get_file())
	if not res.found:
		notes.append("Einstellungen nicht gefunden – den Emulator einmal normal starten")
	res.note = "; ".join(notes)
	return res


## Erst eine Kopie daneben, nachzählen, dann an ihre Stelle (Ini.write_text; bom wie Ini.lesen_treu es meldet).
static func write_text(path: String, text: String, bom := false) -> bool:
	return Ini.write_text(path, text, bom)


static func backup_name(kind: String, path: String) -> String:
	return "%s_%s_%s" % [kind.validate_filename(), path.to_lower().md5_text().left(10), path.get_file().validate_filename()]


## Originaldatei einmal in Uzais Ablage (nur vor dem ersten Schreiben).
static func backup(kind: String, path: String) -> bool:
	var dir := Config.path(BACKUP_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var name := backup_name(kind, path)
	var dst := dir.path_join(name)
	var list: Dictionary = _backups()
	if FileAccess.file_exists(dst) and list.has(name):
		return true
	if not FileAccess.file_exists(path):
		# Gab es noch nicht (Dolphin): „zurück“ heißt dann leer – Dolphin liest das wie keine Datei.
		var e := FileAccess.open(dst, FileAccess.WRITE)
		if e == null:
			return false
		e.close()
	elif DirAccess.copy_absolute(path, dst) != OK:
		return false
	list[name] = path
	Config.set_value(KEY_BACKUPS, list)
	Config.save_soon()
	return true


static func _backups() -> Dictionary:
	var v: Variant = Config.get_value(KEY_BACKUPS, {})
	var out := {}
	if v is Dictionary:
		for k in v:
			if k is String and v[k] is String and (k as String).validate_filename() == k:
				out[k] = v[k]
	return out


static func has_backups() -> bool:
	return not _backups().is_empty()


## Alle Originale zurücklegen (nur an die Stelle, von der sie kamen). Zahl der zurückgelegten Dateien.
static func restore_all() -> int:
	var n := 0
	var dir := Config.path(BACKUP_DIR)
	var bleibt := {}
	# Die Liste (spieler.sicherungen) liegt in den Einstellungen und kommt mit jeder Sicherung zurück: Ziele nur unter den
	# Ordnern eingerichteter Emulatoren oder Dokumente/AppData, lokal, nicht riesig – wie RemotePlayPads.rueck_ok.
	var env := env_now()
	var roots: Array = [env.get("docs", ""), env.get("appdata", ""), env.get("localappdata", "")]
	for emu in Config.emulators():
		if emu is Dictionary and str(emu.get("exe", "")) != "":
			roots.append(str(emu.exe).get_base_dir())
	for name in _backups():
		var src := dir.path_join(str(name))
		var dst := str(_backups()[name])
		if FileAccess.file_exists(src) and Sicher.datei_unter(dst, roots, FILES, 8 * MAX_BYTES):
			if DirAccess.copy_absolute(src, dst) == OK:
				n += 1
				DirAccess.remove_absolute(src)
			else:
				# Ging gerade nicht (Datei gesperrt): Das Original bleibt in der Ablage und in der Liste. Sonst nähme das
				# nächste Einrichten die schon geänderte Datei als „Original“.
				bleibt[name] = dst
	Config.set_value(KEY_BACKUPS, bleibt)
	Config.save_soon()
	return n


# --- Mit Uzai ------------------------------------------------------------------------------------

## Vor dem Start eines Emulator-Spiels (Launcher). Rückgabe { files, done, log: [Zeilen fürs
## launch.log], p1: { name, grund } }.
## - „Immer nach Uzais Zuordnung“ (an) und mindestens zwei Spieler: alles nach der Zuordnung.
## - sonst „Controller im Emulator automatisch“ (Standard an): Spieler 1 = der Controller, mit dem
##   gestartet wurde (siehe oben); 0.13.0 schrieb nach geschätzten SDL-Nummern um („SDL-3“) – jetzt
##   gehen Xbox-Controller über XInput, und das Log zeigt jede Nummer.
static func vor_start(emu_id: String, exe: String, system: String) -> Dictionary:
	if Library.demo:
		return {}
	einmal_zurueck()
	var kind := kind_of(emu_id, exe)
	var pl := SpielerS.players(SpielerS.slots_now(), Pads.pads)
	var belegt := pl.filter(func(p): return not (p as Dictionary).is_empty()).size()
	if bool(Config.get_value(SpielerS.KEY_EMUS, false)) and belegt >= 2 and supported(kind):
		var r := apply(kind, exe, system, pl, Pads.pads.size())
		var log: Array = geraete_log(Pads.pads, Pads.benutzt_id())
		for d in r.done:
			var p: Dictionary = pl[int(d) - 1]
			log.append("Spieler %d → %s (nach Uzais Zuordnung)" % [int(d), _geraet_text(kind, p)])
		if str(r.note) != "":
			log.append(str(r.note))
		r["log"] = log
		r["p1"] = { "name": str((pl[0] as Dictionary).get("name", "")), "grund": "nach Uzais Zuordnung" }
		return r
	if not bool(Config.get_value(SpielerS.KEY_FEHLEND, true)):
		return { "files": [], "done": [], "log": ["Controller automatisch einrichten ist aus – nichts geändert"] }
	var benutzt := Pads.benutzt_id()
	var wahl := spieler_start(SpielerS.slots_now(), Pads.pads, SpielerS.mem_now(), benutzt)
	var log: Array = geraete_log(Pads.pads, benutzt)
	if str(wahl.name) != "":
		log.append("Spieler 1 = %s (%s)" % [str(wahl.name), str(wahl.grund)])
	var r := fehlend(kind, exe, system, wahl.players, geraete(Pads.pads), {}, true)
	r["log"] = log + (r.log as Array)
	r["p1"] = { "name": str(wahl.name), "grund": str(wahl.grund) }
	return r


## Kommt während eines Emulator-Spiels ein Controller dazu, den es beim Start noch nicht gab:
## PCSX2, DuckStation, Dolphin und Eden lesen ihre Belegung nur beim Start (RetroArch nimmt neue
## Controller selbst der Reihe nach, PPSSPP hat nur einen Spieler). Rückgabe [{ slot, name }] für den
## Hinweis „gilt nach Neustart – Guide › Spieler & Controller“, je Controller nur einmal.
static func neu_im_spiel(kind: String, beim_start: Array, pads: Array, gemeldet: Dictionary) -> Array:
	var out: Array = []
	if not (kind in ["pcsx2", "duckstation", "dolphin"] or Ini.YUZU_LIKE.has(kind)):
		return out
	for p in pads:
		var id := str(p.get("uz_id", ""))
		var slot := int(p.get("spieler", 0))
		if id == "" or slot < 1 or beim_start.has(id) or gemeldet.has(id):
			continue
		out.append({ "slot": slot, "name": str(p.get("name", "Controller")), "id": id })
	return out


static func _geraet_text(kind: String, p: Dictionary) -> String:
	match kind:
		"pcsx2", "duckstation":
			return ps_geraet(p)
		"dolphin":
			return dolphin_device(p)
		"retroarch":
			return "Gerät %d" % int(p.get("ra", 0))
	return str(p.get("name", "Controller"))


## One-off after 0.13.0: there "Vor jedem Start einrichten" was on by default and rewrote the
## mappings. Anyone who did not turn it on themselves gets the originals back; the setup is now off
## by default. Runs only before a game start (no emulator open).
## Second round (0.15): the first one only applied if the switch had never been touched; anyone who
## turned it off later kept the rewritten mapping (PS2 games then had no working controls).
## Now the only condition is that the setup is not on.
static func einmal_zurueck() -> void:
	if bool(Config.get_value(KEY_ZURUECK, false)) and bool(Config.get_value(KEY_ZURUECK2, false)):
		return
	Config.set_value(KEY_ZURUECK, true)
	Config.set_value(KEY_ZURUECK2, true)
	if not bool(Config.get_value(SpielerS.KEY_EMUS, false)) and has_backups():
		var n := restore_all()
		Launcher.log_launch("Controller-Belegungen der Emulatoren wie vor Uzai zurückgelegt (%d Dateien)" % n)
	Config.save_soon()


## Läuft dieser Emulator gerade (dann nicht schreiben)?
static func running(emu_id: String) -> bool:
	if not Launcher.in_game or str(Launcher.current.get("source", "rom")) != "rom":
		return false
	var g: Dictionary = Launcher.current
	return str(g.get("emulator", Config.system(str(g.get("system", ""))).get("emulator", ""))) == emu_id


## Alle eingerichteten Emulatoren: [{ id, name, kind, text, ok }]. write: gleich einrichten (außer
## dem, der gerade läuft) – ab zwei Spielern nach der Zuordnung, mit einem nur, was fehlt (eine
## funktionierende eigene Belegung bleibt auch hier).
static func overview(write: bool) -> Array:
	var out: Array = []
	var pl := SpielerS.players(SpielerS.slots_now(), Pads.pads)
	var viele := pl.filter(func(p): return not (p as Dictionary).is_empty()).size() >= 2
	for e in Config.emulators():
		var exe := str(e.get("exe", ""))
		if exe == "" or not FileAccess.file_exists(exe):
			continue
		var id := str(e.get("id", ""))
		var kind := kind_of(id, exe)
		var row := { "id": id, "name": str(e.get("name", id)), "kind": kind, "text": describe(kind), "ok": false }
		if supported(kind):
			if running(id):
				row.text = "Läuft gerade – gilt nach Neustart des Spiels"
			elif write and Library.demo:
				row.ok = true
			elif write and not viele:
				var systems: Array = e.get("systems", [])
				var g := geraete(Pads.pads)
				var sp: Array = spieler_start(SpielerS.slots_now(), Pads.pads, SpielerS.mem_now(), Pads.benutzt_id()).players
				var r := fehlend(kind, exe, "", sp, g, {}, true)
				if kind == "dolphin" and systems.has("wii"):
					r.found = bool(r.found) and bool(fehlend(kind, exe, "wii", sp, g, {}, true).found)
				row.ok = bool(r.found) and int(g.n) > 0
				if not row.ok:
					var l: String = str(r.log[0]) if not (r.log as Array).is_empty() else "kein Controller angeschlossen"
					row.text = l.substr(0, 1).to_upper() + l.substr(1)
			elif write:
				var systems: Array = e.get("systems", [])
				var r := apply(kind, exe, "", pl, Pads.pads.size())
				if kind == "dolphin" and systems.has("wii"):
					var w := apply(kind, exe, "wii", pl, Pads.pads.size())
					r.note = "; ".join(PackedStringArray([str(r.note), str(w.note)].filter(func(x): return x != "")))
				row.ok = r.found and str(r.note) == ""
				if not row.ok:
					row.text = str(r.note).substr(0, 1).to_upper() + str(r.note).substr(1)
		out.append(row)
	return out

extends RefCounted
## Controller-Problemlöser (Punkt 114) ohne Oberfläche: welche Tasten ein Controller hat und wie
## sie heißen, Drift der Sticks in Ruhe und welche Totzone dagegen hilft, wie weit Sticks und
## Trigger kommen, doppelte Eingaben (ein zweites Gerät oder Tastatur/Maus im selben Augenblick) und
## welche Tastensymbole zu einem Controller passen. Die Ebene dazu: src/ui/layers/pad_help.gd.
## Ohne Zustand, darum testbar (tests/logic_padhilfe.gd).

const SONY := 0x054C
const MICROSOFT := 0x045E
const NINTENDO := 0x057E
const VALVE := 0x28DE
const X360 := 0x028E                ## Xbox-360-Controller – auch, was DS4Windows & Co. nachbilden

## Tasten, die jeder gängige Controller hat (Godot-/SDL-Nummern), in der Reihenfolge der Prüfung.
const BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_BACK, JOY_BUTTON_START,
	JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]

const NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menü",
	JOY_BUTTON_LEFT_STICK: "Linker Stick gedrückt", JOY_BUTTON_RIGHT_STICK: "Rechter Stick gedrückt",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "Steuerkreuz hoch", JOY_BUTTON_DPAD_DOWN: "Steuerkreuz runter",
	JOY_BUTTON_DPAD_LEFT: "Steuerkreuz links", JOY_BUTTON_DPAD_RIGHT: "Steuerkreuz rechts",
	JOY_BUTTON_MISC1: "Teilen", JOY_BUTTON_PADDLE1: "Paddel 1", JOY_BUTTON_PADDLE2: "Paddel 2",
	JOY_BUTTON_PADDLE3: "Paddel 3", JOY_BUTTON_PADDLE4: "Paddel 4", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const PS_NAMES := { JOY_BUTTON_A: "Kreuz", JOY_BUTTON_B: "Kreis", JOY_BUTTON_X: "Quadrat", JOY_BUTTON_Y: "Dreieck",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "Create", JOY_BUTTON_START: "Options",
	JOY_BUTTON_GUIDE: "PS-Taste", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3" }
## SDL zählt nach der Lage: unten ist A – auf einem Nintendo-Controller steht dort B.
const NINTENDO_NAMES := { JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
	JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_BACK: "−", JOY_BUTTON_START: "+",
	JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_MISC1: "Aufnahme" }

const DRIFT_OK := 0.08              ## darunter ruht ein Stick sauber
const DRIFT_SOME := 0.2             ## darunter leichte Drift, darüber deutliche
const DRIFT_MAX := 0.65             ## ab hier hilft keine Totzone mehr
const REACH_OK := 0.85              ## so weit nach außen soll ein Stick in jede Richtung kommen
const TRIGGER_FULL := 0.85
const TRIGGER_REST := 0.15
const DEADZONE_MIN := 0.2           ## wie der Regler unter Einstellungen → Controller
const DEADZONE_MAX := 0.8


## Name einer Taste, wie er auf dem Controller steht (family: xbox, ps, nintendo, other).
static func button_name(b: int, family: String) -> String:
	if family == "ps" and PS_NAMES.has(b):
		return str(PS_NAMES[b])
	if family == "nintendo" and NINTENDO_NAMES.has(b):
		return str(NINTENDO_NAMES[b])
	return str(NAMES.get(b, "Taste %d" % b))


## Welche der Pflicht-Tasten noch nicht angekommen sind (pressed: Taste → true).
static func missing(pressed: Dictionary) -> Array:
	return BUTTONS.filter(func(b: int) -> bool: return not pressed.has(b))


# --- Sticks ----------------------------------------------------------------------------------

## Wie weit ein Stick ohne Berührung aus der Mitte steht (Messwerte als Vector2). Ein einzelner
## Ausreißer zählt nicht: maßgeblich ist der Wert, unter dem 95 % der Messungen liegen.
static func drift(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var mags: Array = samples.map(func(v: Vector2) -> float: return v.length())
	mags.sort()
	return float(mags[mini(mags.size() - 1, int(floor(mags.size() * 0.95)))])


## „ruhig“, „leicht“ oder „stark“.
static func drift_level(d: float) -> String:
	if d < DRIFT_OK:
		return "ruhig"
	return "leicht" if d < DRIFT_SOME else "stark"


## Totzone, die gegen diese Drift hilft: mit Abstand darüber, auf 0,05 aufgerundet, im Bereich des
## Reglers. Reicht die eingestellte schon, bleibt es bei ihr; -1, wenn keine Totzone mehr hilft
## (der Stick steht schon in Ruhe weit draußen).
static func deadzone_for(drift_max: float, current: float) -> float:
	if drift_max >= DRIFT_MAX:
		return -1.0
	var need := clampf(ceilf((drift_max + 0.12) / 0.05 - 0.001) * 0.05, DEADZONE_MIN, DEADZONE_MAX)
	return current if current >= need - 0.001 else snappedf(need, 0.05)


## Größter Ausschlag je Achtel (8 Werte, im Uhrzeigersinn ab rechts) um v ergänzen.
static func reach_add(sectors: Array, v: Vector2) -> void:
	if v.length() < 0.3:
		return
	var i := posmod(int(round(v.angle() / (TAU / 8.0))), 8)
	sectors[i] = maxf(float(sectors[i]), minf(v.length(), 1.0))


## Die schwächste Richtung – ein gesunder Stick kommt überall fast bis 1.
static func reach_min(sectors: Array) -> float:
	var m := 1.0
	for s in sectors:
		m = minf(m, float(s))
	return m


# --- Trigger ---------------------------------------------------------------------------------

## „ok“, „haengt“ (steht in Ruhe nicht auf 0), „kurz“ (kommt nicht ganz durch) oder „fehlt“
## (es kam gar nichts an).
static func trigger_verdict(rest: float, peak: float) -> String:
	if peak <= 0.05:
		return "fehlt"
	if rest > TRIGGER_REST:
		return "haengt"
	return "ok" if peak >= TRIGGER_FULL else "kurz"


# --- Doppelte Eingaben -----------------------------------------------------------------------

## Ereignisse [{ t (ms), kind, device, button }] mit kind „pad“ (Controller-Taste), „key“ (Taste
## der Tastatur), „click“ (Maustaste) oder „move“ (Mausbewegung, während ein Stick bewegt wird).
## pads: dieselbe Taste fast gleichzeitig an zwei Geräten (Steam Input oder DS4Windows zeigen einen
## nachgebildeten Controller neben dem echten); keys/clicks: Tastatur bzw. Maus im selben Augenblick
## wie eine Controller-Taste (Steams Desktop-Belegung); moves: Mausbewegung mit dem Stick.
static func dupes(events: Array, window_ms := 90.0) -> Dictionary:
	var out := { "presses": 0, "pads": 0, "keys": 0, "clicks": 0, "moves": 0 }
	var pad: Array = events.filter(func(e: Dictionary) -> bool: return str(e.kind) == "pad")
	out.presses = pad.size()
	for i in pad.size():
		for j in range(i + 1, pad.size()):
			var a: Dictionary = pad[i]
			var b: Dictionary = pad[j]
			if int(a.device) != int(b.device) and int(a.button) == int(b.button) and absf(float(a.t) - float(b.t)) <= window_ms:
				out.pads = int(out.pads) + 1
	for e in events:
		match str(e.kind):
			"key", "click":
				if pad.any(func(p: Dictionary) -> bool: return absf(float(p.t) - float(e.t)) <= window_ms):
					var k := "keys" if str(e.kind) == "key" else "clicks"
					out[k] = int(out[k]) + 1
			"move":
				out.moves = int(out.moves) + 1
	return out


## Was davon zu halten ist: „pads“, „keys“ (Tastatur oder Maus), „mouse“ (Stick bewegt die Maus),
## „ok“ oder „wenig“ (zu wenige Tastendrücke, um etwas zu sagen). Erst ab zwei Treffern – ein
## einzelner kann Zufall sein.
static func dupe_verdict(d: Dictionary) -> String:
	if int(d.get("pads", 0)) >= 2:
		return "pads"
	if int(d.get("keys", 0)) + int(d.get("clicks", 0)) >= 2:
		return "keys"
	if int(d.get("moves", 0)) >= 10:
		return "mouse"
	return "wenig" if int(d.get("presses", 0)) < 4 else "ok"


## Auffälliges in der Geräteliste (Godot: { name, vid, pid }): „steam“ – Steams nachgebildeter
## Controller ist zu sehen; „nachbau“ – ein PlayStation-Controller und daneben ein Xbox-360-
## Controller (so meldet sich DS4Windows; kann aber auch wirklich ein zweiter Controller sein).
static func device_hints(joys: Array) -> Array:
	var out: Array = []
	var sony := false
	var x360 := false
	for j in joys:
		var vid := int(j.get("vid", 0))
		var name := str(j.get("name", "")).to_lower()
		if vid == VALVE or name.contains("steam virtual") or name.contains("steam controller"):
			if not out.has("steam"):
				out.append("steam")
		if vid == SONY:
			sony = true
		if vid == MICROSOFT and int(j.get("pid", 0)) == X360:
			x360 = true
	if sony and x360:
		out.append("nachbau")
	return out


# --- Tastensymbole ---------------------------------------------------------------------------

## Welche Tastensymbole zu einem Controller passen: erst nach Hersteller, dann nach dem Namen.
## „Wireless Controller“ heißt ein DualShock 4 unter Windows – „Xbox Wireless Controller“ ist aber
## ein Xbox-Controller (früher bekam der PlayStation-Symbole).
static func glyphs_for(name: String, vid: int) -> String:
	match vid:
		SONY:
			return "ps"
		NINTENDO:
			return "nintendo"
		MICROSOFT:
			return "xbox"
	var n := name.to_lower()
	if n.contains("xbox") or n.contains("xinput"):
		return "xbox"
	if n.contains("dualsense") or n.contains("dualshock") or n.contains("ps4") or n.contains("ps5") or n.contains("playstation") \
			or n.contains("wireless controller"):
		return "ps"
	if n.contains("nintendo") or n.contains("pro controller") or n.contains("joy-con"):
		return "nintendo"
	return "xbox"


## Was „Tastensymbole“ speichern soll, wenn auf dem Controller chosen steht: „auto“, solange die
## Erkennung ohnehin darauf kommt – sonst fest die gewählte Art.
static func glyph_setting(chosen: String, detected: String) -> String:
	return "auto" if chosen == detected else chosen

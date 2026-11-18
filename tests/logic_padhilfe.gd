extends Node
## Controller-Problemlöser (Punkt 114): Tastennamen, Drift und Totzonen-Vorschlag, Reichweite,
## Trigger, doppelte Eingaben, Tastensymbole (auch der alte Fehler „Xbox Wireless Controller“ →
## PlayStation) und ein Durchlauf der Ebene mit nachgestellten Eingaben. Aufruf:
##   godot --headless --path . res://tests/logic_padhilfe.tscn   → „Ergebnis: alles ok“

const C := preload("res://src/core/pad_check.gd")
const Trouble := preload("res://src/core/trouble.gd")
const PadHelp := preload("res://src/ui/layers/pad_help.gd")
const Quelle := preload("res://tests/quelle.gd")
const Zustand := preload("res://src/core/zustand.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_names()
	_sticks()
	_triggers()
	_dupes()
	_glyphs()
	_first_aid()
	await _flow()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _names() -> void:
	print("Tasten")
	check(C.button_name(JOY_BUTTON_A, "xbox") == "A" and C.button_name(JOY_BUTTON_A, "ps") == "Kreuz", "A heißt bei PlayStation Kreuz")
	check(C.button_name(JOY_BUTTON_A, "nintendo") == "B" and C.button_name(JOY_BUTTON_START, "nintendo") == "+", "Nintendo nach Lage: unten steht B, Start ist +")
	check(C.button_name(JOY_BUTTON_DPAD_LEFT, "ps") == "Steuerkreuz links", "ohne eigenen Namen der allgemeine")
	check(C.button_name(99, "xbox") == "Taste 99", "unbekannte Taste mit Nummer")
	check(C.missing({}).size() == 14 and not (JOY_BUTTON_GUIDE in C.BUTTONS), "14 Pflicht-Tasten, Guide zählt nicht")
	var all := {}
	for b in C.BUTTONS:
		all[b] = true
	check(C.missing(all).is_empty(), "alle gedrückt: nichts fehlt")
	all.erase(JOY_BUTTON_LEFT_SHOULDER)
	check(C.missing(all) == [JOY_BUTTON_LEFT_SHOULDER], "eine fehlt: genau die")


func _sticks() -> void:
	print("Sticks")
	var calm: Array = []
	for i in 100:
		calm.append(Vector2(0.02, -0.01) + Vector2(0.01, 0).rotated(i))
	check(C.drift(calm) < C.DRIFT_OK and C.drift_level(C.drift(calm)) == "ruhig", "ruhiger Stick (%.3f)" % C.drift(calm))
	var spike := calm.duplicate()
	spike[50] = Vector2(0.9, 0)
	check(C.drift(spike) < C.DRIFT_OK, "ein einzelner Ausreißer zählt nicht")
	var some: Array = []
	for i in 100:
		some.append(Vector2(0.15, 0.0))
	check(C.drift_level(C.drift(some)) == "leicht", "0,15 in Ruhe: leichte Drift")
	check(C.drift_level(0.3) == "stark" and C.drift([]) == 0.0, "0,3: deutlich; ohne Messung 0")
	check(is_equal_approx(C.deadzone_for(0.03, 0.5), 0.5), "kaum Drift: eingestellte Totzone reicht")
	check(is_equal_approx(C.deadzone_for(0.48, 0.5), 0.6), "Drift 0,48 → Totzone 0,60")
	check(is_equal_approx(C.deadzone_for(0.1, 0.2), 0.25), "Drift 0,10 bei 0,20 → 0,25")
	check(is_equal_approx(C.deadzone_for(0.18, 0.2), 0.3), "genau auf der Stufe: nicht eine zu hoch (0,30)")
	check(is_equal_approx(C.deadzone_for(0.64, 0.5), 0.8), "höchstens so viel, wie der Regler kann (0,80)")
	check(C.deadzone_for(0.7, 0.5) < 0.0, "zu viel Drift: keine Totzone hilft")
	var sec := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in 64:
		C.reach_add(sec, Vector2.RIGHT.rotated(i * TAU / 64.0) * 0.97)
	check(C.reach_min(sec) >= 0.95, "voller Kreis: überall bis außen")
	var half := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in 32:
		C.reach_add(half, Vector2.RIGHT.rotated(-PI * 0.5 + i * PI / 32.0))
	check(C.reach_min(half) == 0.0, "halber Kreis: andere Seite fehlt")
	var small := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	C.reach_add(small, Vector2(0.1, 0.0))
	check(C.reach_min(small) == 0.0, "kleine Bewegungen zählen nicht als Reichweite")


func _triggers() -> void:
	print("Trigger")
	check(C.trigger_verdict(0.0, 1.0) == "ok", "ganz durch, zurück auf null")
	check(C.trigger_verdict(0.22, 1.0) == "haengt", "Ruhewert 0,22: hängt")
	check(C.trigger_verdict(0.0, 0.7) == "kurz", "nur bis 70 %")
	check(C.trigger_verdict(0.0, 0.0) == "fehlt", "nichts angekommen")


func _dupes() -> void:
	print("Doppelte Eingaben")
	var ev: Array = []
	for i in 6:
		ev.append({ "t": i * 400, "kind": "pad", "device": 0, "button": i })
	check(C.dupe_verdict(C.dupes(ev)) == "ok", "sechs saubere Drücke: ok")
	var twin := ev.duplicate()
	for i in 3:
		twin.append({ "t": i * 400 + 12, "kind": "pad", "device": 1, "button": i })
	var d := C.dupes(twin)
	check(int(d.pads) == 3 and C.dupe_verdict(d) == "pads", "dieselbe Taste an zwei Geräten: doppelt (%d)" % int(d.pads))
	var other := ev.duplicate()
	other.append({ "t": 15, "kind": "pad", "device": 1, "button": 9 })
	check(int(C.dupes(other).pads) == 0, "andere Taste am zweiten Controller: kein Doppel")
	var keys := ev.duplicate()
	keys.append({ "t": 30, "kind": "key", "device": -1, "button": KEY_ENTER })
	keys.append({ "t": 400 - 20, "kind": "key", "device": -1, "button": KEY_ESCAPE })
	keys.append({ "t": 1000, "kind": "click", "device": -1, "button": 0 })
	d = C.dupes(keys)
	check(int(d.keys) == 2 and int(d.clicks) == 0 and C.dupe_verdict(d) == "keys", "Tastatur im selben Augenblick (auch knapp davor): Desktop-Belegung")
	var moves := ev.duplicate()
	for i in 12:
		moves.append({ "t": 3000 + i * 16, "kind": "move", "device": -1, "button": 0 })
	check(C.dupe_verdict(C.dupes(moves)) == "mouse", "Stick bewegt die Maus")
	check(C.dupe_verdict(C.dupes(ev.slice(0, 2))) == "wenig", "zwei Drücke: zu wenig, um etwas zu sagen")
	check(C.device_hints([{ "name": "Steam Virtual Gamepad", "vid": C.VALVE, "pid": 0x11FF }]) == ["steam"], "Steams nachgebildeter Controller")
	check(
			C.device_hints([{ "name": "PS4 Controller", "vid": C.SONY, "pid": 0x09CC },
			{ "name": "Xbox 360 Controller", "vid": C.MICROSOFT, "pid": C.X360 }]) == ["nachbau"], "PlayStation plus Xbox 360: wie DS4Windows")
	check(C.device_hints([{ "name": "PS5 Controller", "vid": C.SONY, "pid": 0x0CE6 }]).is_empty(), "ein PlayStation-Controller allein: nichts")


func _glyphs() -> void:
	print("Tastensymbole")
	check(C.glyphs_for("Xbox Wireless Controller", -1) == "xbox", "„Xbox Wireless Controller“ bekommt Xbox-Symbole (früher PlayStation)")
	check(C.glyphs_for("Wireless Controller", -1) == "ps", "„Wireless Controller“ (DualShock 4 unter Windows): PlayStation")
	check(C.glyphs_for("Controller", C.SONY) == "ps" and C.glyphs_for("Pro Controller", C.NINTENDO) == "nintendo", "nach Hersteller")
	check(C.glyphs_for("Generic USB Joystick", 0x0079) == "xbox", "Unbekanntes: Xbox wie bisher")
	check(C.glyph_setting("ps", "ps") == "auto" and C.glyph_setting("ps", "xbox") == "ps", "Wahl gleich Erkennung bleibt automatisch")
	var was := [Nav.device, Nav.pad_name, Nav.pad_vid, Config.get_value("controller.glyphs", "auto")]
	Config.set_value("controller.glyphs", "auto")
	Nav.device = "pad"
	Nav.pad_name = "Xbox Wireless Controller"
	Nav.pad_vid = -1
	check(Nav.glyph_set() == "xbox", "Nav nimmt dieselbe Erkennung")
	Nav.pad_name = "Wireless Controller"
	check(Nav.glyph_set() == "ps", "Nav: DualShock 4 am Namen")
	Nav.device = was[0]
	Nav.pad_name = was[1]
	Nav.pad_vid = was[2]
	Config.set_value("controller.glyphs", was[3])


func _first_aid() -> void:
	print("Erste Hilfe und Einstellungen")
	var pad: Dictionary = Trouble.FIRST_AID[0]
	check(str(pad.title).contains("Controller") and (pad.actions as Array).any(func(a: Array) -> bool: return str(a[1]) == "pad_help"),
			"Erste Hilfe → Controller führt zum Problemlöser")
	var sv := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(sv.contains("\"pad_help\":") and sv.contains("pad_help.gd\").open_for(main)"), "Einstellungen → Controller und Erste Hilfe öffnen ihn")
	check(Quelle.lesen("res://src/main.gd").contains("has_meta(\"uz_pad_owned\")"), "Guide-Taste des Helfers stört die Messschritte nicht")


## Ein Durchlauf mit nachgestellten Eingaben: Tasten, Sticks (ruhig, dann mit Drift), Trigger.
func _flow() -> void:
	print("Durchlauf")
	var host := Control.new()
	add_child(host)
	var l = PadHelp.new()
	l.sim = { "joys": [{ "device": 0, "name": "Xbox Wireless Controller", "vid": C.MICROSOFT, "pid": 0x0B12 }] }
	l.open(host)
	await _frames(3)
	check(l._id == "sieht" and l._cur == 0 and not l._capture, "erste Seite: was Uzai sieht, Gerät gewählt")
	l._show("tasten", 0)
	await _frames(2)
	check(l._capture and l.nav_dir("left") and l.nav_command("a"), "im Messschritt gehört alles dem Test")
	for b in C.BUTTONS:
		l._press(0, b, Time.get_ticks_msec())
	await _frames(2)
	check(str(l._res.get("tasten", [""])[0]) == "ok" and not l._capture, "alle Tasten: ok, Messung aus")
	await get_tree().create_timer(0.6).timeout
	check(l.nav_command("x") == false, "danach wieder normale Bedienung")

	l.sim_axes = [0.02, 0.01, -0.01, 0.02, 0.0, 0.0]
	l._show("sticks", 0)
	await get_tree().create_timer(PadHelp.REST_S + 0.4).timeout
	check(l._phase == "kreis", "nach der Ruhemessung: kreisen")
	for i in 80:
		var v := Vector2.RIGHT.rotated(i * TAU / 40.0) * 0.98
		l.sim_axes = [v.x, v.y, v.x, v.y, 0.0, 0.0]
		await get_tree().process_frame
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	await _frames(2)
	check(str(l._res.get("sticks", [""])[0]) == "ok", "ruhige Sticks, voller Kreis: ok")

	var dz_was: Variant = Config.get_value("controller.deadzone", 0.5)
	Config.set_value("controller.deadzone", 0.5)
	l.sim_axes = [0.44, 0.0, 0.0, 0.0, 0.0, 0.0]
	l._show("sticks", 0)
	await get_tree().create_timer(PadHelp.REST_S + 0.4).timeout
	l._skip()
	await _frames(2)
	check(str(l._res.get("sticks", [""])[0]) == "skip", "Kreisen übersprungen: Schritt übersprungen")
	await get_tree().create_timer(0.6).timeout
	check(l._id == "trigger", "übersprungen: gleich der nächste Schritt")
	l.sim_axes = [0.44, 0.0, 0.0, 0.0, 0.0, 0.0]
	l._show("sticks", 0)
	await get_tree().create_timer(PadHelp.REST_S + 0.4).timeout
	l._sticks_done()
	await get_tree().create_timer(0.6).timeout
	var txt := str(l._res.get("sticks", ["", ""])[1])
	check(str(l._res.sticks[0]) == "warn" and txt.contains("0,60"), "Drift links: Hinweis und Totzone 0,60 (%s)" % txt.replace("\n", " | "))
	l._apply_deadzone(0.6)
	await _frames(2)
	check(is_equal_approx(float(Config.get_value("controller.deadzone", 0.0)), 0.6) and str(l._res.sticks[0]) == "fix",
			"Totzone übernommen, Schritt gilt als behoben")
	Config.set_value("controller.deadzone", dz_was)

	await get_tree().create_timer(0.5).timeout
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	l._show("trigger", 0)
	await get_tree().create_timer(0.4).timeout
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 1.0, 0.72]
	await _frames(3)
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	await _frames(2)
	l._skip()
	await _frames(2)
	check(str(l._res.get("trigger", [""])[0]) == "skip", "Trigger übersprungen")
	await get_tree().create_timer(0.6).timeout
	l._show("trigger", 0)
	await get_tree().create_timer(0.4).timeout
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0]
	await _frames(3)
	l.sim_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	await _frames(3)
	check(str(l._res.get("trigger", [""])[0]) == "ok", "beide Trigger ganz durch und zurück: ok")
	check(Zustand.lage().any(func(z: Dictionary) -> bool: return z.name == "controller.hilfe" and z.zustand == "trigger"),
			"Stand für den Fehlerbericht: controller.hilfe trigger")
	l.close()
	# Die Mitteilung „Totzone …“ ausklingen lassen (sonst bleibt sie beim Beenden übrig).
	await get_tree().create_timer(3.6).timeout
	check(not Zustand.lage().any(func(z: Dictionary) -> bool: return str(z.name).begins_with("controller.")),
			"Ebene zu: ihr Stand ist aus lage() (kein alter Stand im Fehlerbericht)")
	host.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

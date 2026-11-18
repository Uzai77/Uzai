extends Node
## Controller-Status (src/core/pads.gd): XInput-Einträge, PlayStation-Akku aus HID-Berichten,
## Zusammenführen mit Godot, Spieler-Nummern, Texte, „Akku schwach“ einmal je Stufe, wann
## vibriert werden darf, Ausschalten-Fehler und der Helfer-Teil. Aufruf:
##   godot --headless --path . res://tests/logic_controller.tscn   → „Ergebnis: alles ok“
## Mit UZAI_HELPER_SHELL=<pwsh> fragt es den Helfer einmal unter PowerShell 7 (ohne XInput/HID:
## leere Listen, aber gültiges JSON).

const P := preload("res://src/core/pads.gd")
const HelperScript := preload("res://src/core/helper.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Xbox über XInput")
	var wired := P.xinput_entry({ "pad": 0, "btype": 1, "blevel": 0, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x0B12 })
	check(wired.conn == "Kabel" and wired.power == "wired" and int(wired.level) == -1, "Kabel: kein Akku, Verbindung Kabel")
	check(not bool(wired.can_off), "am Kabel nicht ausschaltbar")
	check(P.battery_text(wired) == "Kabel", "rechts steht „Kabel“")
	check(int(wired.slot) == 0 and int(wired.xinput) == 0 and str(wired.key) == "x0", "Anschluss 0, Schlüssel x0")
	var funk := P.xinput_entry({ "pad": 1, "btype": 3, "blevel": 1, "sub": 1, "flags": 2, "vid": 0x045E, "pid": 0x0B12 })
	check(funk.name == "Xbox Wireless Controller" and funk.family == "xbox", "Name aus der Produktnummer (%s)" % funk.name)
	check(funk.conn == "Funk" and bool(funk.can_off), "kabellos über Funk, ausschaltbar")
	check(P.battery_text(funk) == "Schwach", "Stufe 1 = Schwach (%s)" % P.battery_text(funk))
	var bt := P.xinput_entry({ "pad": 2, "btype": 2, "blevel": 3, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x0B13 })
	check(bt.conn == "Bluetooth" and bt.power == "alkaline" and P.battery_text(bt) == "Voll", "Bluetooth an der Produktnummer, Batterien voll")
	var old := P.xinput_entry({ "pad": 0, "btype": 2, "blevel": 0, "sub": 1, "flags": 2, "vid": 0, "pid": 0 })
	check(old.name == "Xbox-Controller" and old.family == "xbox" and old.conn == "Funk", "ohne Produktnummer (altes Windows): Xbox-Controller über Funk")
	check(P.battery_text(old) == "Fast leer", "Stufe 0 = Fast leer")
	var unk := P.xinput_entry({ "pad": 3, "btype": 255, "blevel": 2, "sub": 1, "flags": 0, "vid": 0x1234, "pid": 1 })
	check(int(unk.level) == -1 and unk.conn == "" and P.battery_text(unk) == "", "unbekannter Akku-Typ: kein Stand, keine Verbindung erfunden")
	check(unk.family == "other" and unk.name == "Controller", "fremder XInput-Controller")
	var wheel := P.xinput_entry({ "pad": 0, "btype": 1, "blevel": 0, "sub": 2, "flags": 0, "vid": 0x046D, "pid": 2 })
	check(wheel.name == "Lenkrad", "XInput-Lenkrad heißt so")
	check(P.xinput_entry({ "pad": 0, "btype": 0, "blevel": 0 }).power == "unknown", "„getrennt“ (0) gilt als unbekannt")

	print("Akku über Windows.Gaming.Input (Fehler 32: nur „lädt“ zu sehen)")
	var btw := P.xinput_entry({ "pad": 0, "btype": 1, "blevel": 3, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x0B13 })
	check(btw.conn == "Bluetooth" and btw.power == "unknown" and int(btw.level) == -1, "Bluetooth, aber XInput sagt „Kabel“: nicht geglaubt, Stand unbekannt")
	check(P.battery_text(btw) != "Kabel" and not bool(btw.charging), "kein „Kabel“-Blitz mehr, der wie Laden aussieht")
	var wgi := P.parse_wgi([{ "vid": 0x045E, "pid": 0x0B13, "pct": 63, "st": 1 }, { "vid": 1, "pid": 2, "pct": 140, "st": 1 },
		{ "vid": 1, "pid": 2, "pct": 50, "st": 0 }, "x", { "vid": 0x054C, "pid": 0x0CE6, "pct": 80, "st": 3 }])
	check(wgi.size() == 2, "Meldungen geprüft: über 100 %%, „kein Akku“ und Fremdes verworfen (%d)" % wgi.size())
	var mw := P.merge([{ "pad": 0, "btype": 1, "blevel": 3, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x0B13 }], [], [], wgi)
	check(mw.size() == 1 and int(mw[0].pct) == 63 and int(mw[0].level) == 2 and P.battery_text(mw[0]) == "63 %",
			"Bluetooth-Xbox: Stand aus Windows.Gaming.Input (%s)" % P.battery_text(mw[0]))
	var mc := P.merge([{ "pad": 0, "btype": 1, "blevel": 3, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x0B13 }], [], [],
			[{ "vid": 0x045E, "pid": 0x0B13, "pct": 41, "st": 3 }])
	check(P.battery_text(mc[0]) == "41 % · lädt" and bool(mc[0].charging), "lädt: Stand und „lädt“ (%s)" % P.battery_text(mc[0]))
	var mx := P.merge([{ "pad": 0, "btype": 1, "blevel": 0, "sub": 1, "flags": 0, "vid": 0x045E, "pid": 0x028E }], [], [],
			[{ "vid": 0x045E, "pid": 0x0B13, "pct": 63, "st": 1 }])
	check(P.battery_text(mx[0]) == "Kabel", "echtes Kabel ohne Akku bekommt keine fremde Meldung")
	var ma := P.merge([{ "pad": 0, "btype": 255, "blevel": 0, "sub": 1, "flags": 2, "vid": 0, "pid": 0 }], [], [],
			[{ "vid": 0x045E, "pid": 0x02EA, "pct": 90, "st": 2 }])
	check(int(ma[0].pct) == 90 and int(ma[0].level) == 3, "Funkadapter ohne Produktnummer: Microsoft-Meldung passt")
	var ms := P.merge([], [{ "vid": 0x054C, "pid": 0x0CE6, "bt": true, "read": true, "rid": 0x01, "n": 10, "st": [] }], [], wgi)
	check(int(ms[0].pct) == 80 and bool(ms[0].charging), "DualSense über Bluetooth (kurze Berichte): Stand aus Windows.Gaming.Input")
	var mo := P.merge([{ "pad": 1, "btype": 3, "blevel": 1, "sub": 1, "flags": 2, "vid": 0x045E, "pid": 0x0B12 }], [], [],
			[{ "vid": 0x045E, "pid": 0x0B12, "pct": 95, "st": 1 }])
	check(P.battery_text(mo[0]) == "Schwach", "XInput kennt den Stand schon: bleibt (keine doppelte Quelle)")

	print("PlayStation über HID")
	# DualSense USB: Bericht 0x01, 64 Bytes, Stelle 53. 0x13 = lädt, Stand 3.
	var r := P.sony_battery(0x0CE6, 0x01, 64, [-1, -1, 0x13, -1])
	check(int(r.pct) == 35 and bool(r.charging), "DualSense USB lädt, 35 %% (%s)" % str(r))
	r = P.sony_battery(0x0CE6, 0x31, 78, [-1, -1, -1, 0x08])
	check(int(r.pct) == 85 and not bool(r.charging), "DualSense Bluetooth (0x31, Stelle 54): 85 %")
	r = P.sony_battery(0x0CE6, 0x01, 10, [-1, -1, -1, -1])
	check(int(r.pct) == -1, "DualSense Bluetooth, kurzer Bericht: unbekannt")
	r = P.sony_battery(0x0DF2, 0x01, 64, [-1, -1, 0x2A, -1])
	check(int(r.pct) == 100 and not bool(r.charging), "DualSense Edge voll geladen")
	r = P.sony_battery(0x0CE6, 0x01, 64, [-1, -1, 0xA5, -1])
	check(int(r.pct) == -1, "Ladefehler/Temperatur: unbekannt statt falscher Zahl")
	r = P.sony_battery(0x0CE6, 0x01, 64, [-1, -1, 0x0A, -1])
	check(int(r.pct) == 100, "Stand 10 ohne Laden: höchstens 100 %")
	# DualShock 4: USB 0x01 Stelle 30, Bluetooth 0x11 Stelle 32; Bit 4 = Kabel.
	r = P.sony_battery(0x09CC, 0x01, 64, [0x1B, -1, -1, -1])
	check(int(r.pct) == 100 and not bool(r.charging), "DualShock 4 am Kabel, voll (11)")
	r = P.sony_battery(0x09CC, 0x01, 64, [0x15, -1, -1, -1])
	check(int(r.pct) == 55 and bool(r.charging), "DualShock 4 am Kabel lädt, 55 %")
	r = P.sony_battery(0x05C4, 0x11, 78, [-1, 0x03, -1, -1])
	check(int(r.pct) == 35 and not bool(r.charging), "DualShock 4 Bluetooth (0x11, Stelle 32): 35 %")
	r = P.sony_battery(0x05C4, 0x01, 10, [-1, -1, -1, -1])
	check(int(r.pct) == -1, "DualShock 4 Bluetooth im einfachen Modus: unbekannt")
	check(int(P.sony_battery(0x05C4, 0x11, 78, [-1, 0x0A, -1, -1]).pct) == 100, "DualShock 4 ohne Kabel, 10: 100 %")
	check(
			[P.level_from_pct(-1), P.level_from_pct(5), P.level_from_pct(10), P.level_from_pct(25), P.level_from_pct(55), P.level_from_pct(95)] == [-1, 0, 0, 1, 2, 3],
			"Prozent → vier Stufen")
	var ds := P.sony_entry({ "vid": 0x054C, "pid": 0x0CE6, "bt": true, "read": true, "rid": 0x31, "n": 78, "st": [-1, -1, -1, 0x12] }, 0)
	check(ds.name == "DualSense" and ds.conn == "Bluetooth" and ds.family == "ps", "DualSense über Bluetooth")
	check(int(ds.pct) == 25 and int(ds.level) == 1 and bool(ds.charging), "25 %, Stufe schwach, lädt")
	check(P.battery_text(ds) == "25 % · lädt", "Text „25 %% · lädt“ (%s)" % P.battery_text(ds))
	check(not bool(ds.can_off), "PlayStation: kein Ausschalten über XInput")
	var ds4u := P.sony_entry({ "vid": 0x054C, "pid": 0x09CC, "bt": false, "rid": 1, "n": 64, "st": [0x07, -1, -1, -1] }, 1)
	check(ds4u.conn == "Kabel" and ds4u.name == "DualShock 4" and str(ds4u.key) == "ps9cc:1", "DualShock 4 über USB")
	check(P.sony_entry({ "pid": 0x0BA0, "bt": false, "rid": -1, "n": 0, "st": "kaputt" }, 0).conn == "Funk",
			"DualShock-Funkadapter: Funk, kaputte Bytes stören nicht")

	print("Zusammenführen")
	var joys := [
		{ "device": 0, "name": "Xbox Series X Controller", "vid": 0x045E, "pid": 0x0B12, "player": 1 },
		{ "device": 1, "name": "PS5 Controller", "vid": 0x054C, "pid": 0x0CE6, "player": 0 },
		{ "device": 2, "name": "Nintendo Switch Pro Controller", "vid": 0x057E, "pid": 0x2009, "player": -1 },
	]
	var xin := [{ "pad": 1, "btype": 3, "blevel": 2, "sub": 1, "flags": 2, "vid": 0x045E, "pid": 0x0B12 }]
	var sony := [{ "vid": 0x054C, "pid": 0x0CE6, "bt": true, "rid": 0x31, "n": 78, "st": [-1, -1, -1, 0x06] }]
	var m := P.merge(xin, sony, joys)
	check(m.size() == 3, "jeder Controller einmal (%d)" % m.size())
	check(m[0].family == "ps" and int(m[0].slot) == 1 and int(m[0].device) == 1, "DualSense: Spieler 1 (SDL), Godot-Gerät 1")
	check(m[1].family == "xbox" and int(m[1].slot) == 2 and int(m[1].device) == 0 and int(m[1].level) == 2, "Xbox an XInput 1: Spieler 2, Gerät 0, Akku mittel")
	check(m[2].family == "nintendo" and int(m[2].slot) == 3 and int(m[2].level) == -1, "Switch-Controller nur aus Godot: Spieler 3, Akku unbekannt")
	# Godot liefert keine XInput-Nummer: der Reihe nach, nie den PlayStation-Controller.
	var joys2 := [{ "device": 0, "name": "PS4 Controller", "vid": 0x054C, "pid": 0x09CC, "player": -1 },
			{ "device": 1, "name": "Controller (Xbox One For Windows)", "vid": -1, "pid": -1, "player": -1 }]
	var m2 := P.merge([{ "pad": 0, "btype": 1, "vid": 0, "pid": 0, "sub": 1 }], [], joys2)
	var xb: Dictionary = m2.filter(func(e): return e.family == "xbox")[0]
	check(m2.size() == 2 and int(xb.device) == 1 and int(xb.slot) == 1, "ohne XInput-Nummer: das Xbox-Gerät der Reihe nach, Spieler 1")
	check(xb.name == "Controller (Xbox One For Windows)", "unbekannte Produktnummer: Godots Name")
	var ps4: Dictionary = m2.filter(func(e): return e.family == "ps")[0]
	check(ps4.name == "DualShock 4" and int(ps4.slot) == 2, "PlayStation nur aus Godot: Name aus der Produktnummer, Spieler 2")
	var m3 := P.merge([], [], [{ "device": 4, "name": "Xbox 360 Controller", "vid": 0x045E, "pid": 0x028E, "player": 0 }])
	check(m3.size() == 1 and int(m3[0].slot) == 1 and m3[0].family == "xbox" and str(m3[0].key) == "j4", "ohne Helfer (Linux): nur Godot")
	check(P.merge([], [], []).is_empty(), "nichts verbunden: leer")
	var dup := [{ "xinput": 0, "player": -1 }, { "xinput": -1, "player": 0 }, { "xinput": -1, "player": -1 }]
	P.assign_slots(dup)
	check(int(dup[0].slot) == 1 and int(dup[1].slot) == 2 and int(dup[2].slot) == 3, "gleiche Nummer zweimal: der zweite rückt auf")
	check(P.detail_text(m[1]) == "Spieler 2 · Funk · Akku", "Zeile darunter (%s)" % P.detail_text(m[1]))
	check(P.detail_text(m2.filter(func(e): return e.family == "xbox")[0]) == "Spieler 1" and P.detail_text(m3[0]) == "Spieler 1",
			"Kabel ohne Akku: nur Spieler (rechts steht „Kabel“), unbekannt nur Spieler")
	var st := P.parse_status('{"xinput":[{"pad":0}],"sony":[],"watch":true}')
	check((st.xinput as Array).size() == 1 and (st.sony as Array).is_empty(), "Helfer-Antwort lesen")
	check((P.parse_status("").xinput as Array).is_empty() and (P.parse_status("{kaputt").sony as Array).is_empty(), "leere oder kaputte Antwort: leere Listen")
	check((P.parse_status('{"xinput":[1,"x",{"pad":2}]}').xinput as Array).size() == 1, "nur Einträge, die Objekte sind")
	# null vom Helfer („unbekannt“) heißt „fehlt“: Der Controller steht mit Ersatzwerten da, nichts bricht ab.
	var mit_null := P.parse_status('{"xinput":[{"pad":1,"btype":null,"blevel":null,"vid":null,"pid":null,"sub":null,"flags":null}],"sony":[{"pid":3302,"rid":null,"n":null,"st":null,"bt":null}]}')
	var liste := P.merge(mit_null.xinput, mit_null.sony, [])
	var null_xbox: Array = liste.filter(func(e: Dictionary) -> bool: return int(e.xinput) == 1)
	var null_sony: Array = liste.filter(func(e: Dictionary) -> bool: return str(e.family) == "ps")
	check(liste.size() == 2 and null_xbox.size() == 1 and int(null_xbox[0].level) == -1 and null_sony.size() == 1 and int(null_sony[0].pct) == -1,
			"Helfer-Antwort mit null: Controller mit Ersatzwerten, kein Abbruch")

	print("Akku schwach: einmal je Stufe")
	var w := 4
	var seen: Array = []
	for step in [[3, false], [2, false], [1, false], [1, false], [1, false], [0, false], [0, false], [0, true], [1, false], [3, false], [1, false]]:
		var res := P.warn_step(w, int(step[0]), bool(step[1]), "nimh")
		w = int(res[1])
		seen.append(bool(res[0]))
	check(seen == [false, false, true, false, false, true, false, false, true, false, true],
			"voll → schwach meldet, nochmal schwach nicht, fast leer meldet, nach Laden wieder (%s)" % str(seen))
	check(not bool(P.warn_step(4, 0, false, "wired")[0]), "am Kabel (ohne Akku) nie")
	check(not bool(P.warn_step(4, -1, false, "battery")[0]), "unbekannter Stand nie")
	check(not bool(P.warn_step(4, 0, true, "battery")[0]), "lädt gerade: nicht melden")

	print("Vibration")
	var on := { "events": true, "friends": false }
	var off := { "events": false, "friends": true }
	check(P.pulse_allowed("achievement", on, false, true) and P.pulse_allowed("clip", on, true, false) and P.pulse_allowed("message", on, true, false),
			"Erfolg, Clip, Nachricht: auch im Spiel")
	check(not P.pulse_allowed("achievement", off, false, true) and not P.pulse_allowed("message", off, true, false), "Einstellung aus: nie")
	check(P.pulse_allowed("test", off, true, false), "Test (Controller-Test, Finden) geht immer")
	check(not P.pulse_allowed("friend_online", on, false, true), "Freund online: nur mit eigenem Schalter")
	check(P.pulse_allowed("friend_online", { "events": true, "friends": true }, false, true), "… mit Schalter außerhalb des Spiels: ja")
	check(not P.pulse_allowed("friend_online", { "events": true, "friends": true }, true, false), "… im Spiel nie")
	check(not P.pulse_allowed("confirm", on, false, true) and not P.pulse_allowed("", on, false, true), "unbekannte Ereignisse: nie")
	var soft := true
	for k in P.PULSES:
		var p: Array = P.PULSES[k]
		soft = soft and int(p[2]) <= 150 and float(p[0]) <= 0.5 and float(p[1]) <= 0.5
	check(soft, "alle Impulse kurz (≤ 150 ms) und leise (≤ 0,5)")
	check(Pads.pulse("nichts") == false, "Pads.pulse mit unbekannter Art: false")

	print("Ausschalten")
	check(P.power_off_error(0) == "", "0 = ausgeschaltet")
	check(P.power_off_error(1167).contains("nicht mehr verbunden"), "1167 = nicht verbunden")
	check(P.power_off_error(-2).contains("6 Sekunden"), "Funktion fehlt: Hinweis Xbox-Taste halten")
	check(P.power_off_error(5).contains("Funkadapter") and P.power_off_error(5).contains("Bluetooth"), "abgelehnt: nur über Funkadapter, sonst Taste halten")

	print("Vorführung (Pads als Dienst)")
	var was_demo: bool = Library.demo
	Library.demo = true
	Pads.demo_raw = P.DEMO_RAW.duplicate(true)
	await Pads.refresh()
	check(Pads.pads.size() == 2, "zwei Controller in der Vorführung (%d)" % Pads.pads.size())
	check(Pads.pads.size() == 2 and Pads.pads[0].family == "xbox" and int(Pads.pads[0].slot) == 1, "Xbox als Spieler 1")
	check(Pads.pads.size() == 2 and P.battery_text(Pads.pads[1]) == "65 %", "DualSense 65 %")
	var n0 := _low_toasts()
	Pads.demo_warn = true
	Pads.demo_raw.xinput[0]["blevel"] = 1
	await Pads.refresh()
	await Pads.refresh()
	check(_low_toasts() == n0 + 1, "Akku fällt auf schwach: genau eine Mitteilung (%d)" % (_low_toasts() - n0))
	Pads.demo_raw.xinput[0]["blevel"] = 0
	await Pads.refresh()
	check(_low_toasts() == n0 + 2, "fällt weiter auf fast leer: noch eine")
	var got_changed := [false]
	Pads.changed.connect(func() -> void: got_changed[0] = true, CONNECT_ONE_SHOT)
	var off_r: Dictionary = await Pads.power_off(Pads.pads[0])
	check(bool(off_r.ok) and Pads.pads.size() == 1 and bool(got_changed[0]), "Ausschalten nimmt ihn aus der Liste (changed kommt)")
	var ps_off: Dictionary = await Pads.power_off(Pads.pads[0])
	check(not bool(ps_off.ok) and str(ps_off.error).contains("kabellosen Xbox"), "DualSense lässt sich nicht ausschalten")
	Pads.demo_warn = false
	Pads.demo_raw = P.DEMO_RAW.duplicate(true)
	Library.demo = was_demo
	await Pads.refresh()

	print("Oberfläche")
	for path in ["res://src/ui/components/pad_battery.gd", "res://src/ui/components/guide_pads.gd", "res://src/ui/layers/pad_test.gd"]:
		var s: Variant = load(path)
		check(s is GDScript and (s as GDScript).can_instantiate(), "%s lädt" % path.get_file())
	var t: Node = load("res://src/ui/layers/pad_test.gd").new()
	check(t.has_method("rumble_test") and "sim" in t and "device" in t and "back_text" in t, "Controller-Test: device, back_text, sim, rumble_test")
	t.free()
	var box := HBoxContainer.new()
	load("res://src/ui/components/pad_battery.gd").fill(box, P.merge(xin, sony, joys))
	check(box.get_child_count() == 4, "Statuszeile: Controller-Symbol und drei Akkus (%d)" % box.get_child_count())
	load("res://src/ui/components/pad_battery.gd").fill(box, [])
	check(box.get_child_count() == 0, "ohne Controller leer")
	box.free()

	print("Einstellungen und Helfer")
	check(bool(Config.get_value("controller.rumble_events", true)), "„Vibration bei Bestätigungen“ standardmäßig an")
	check(not bool(Config.get_value("controller.rumble_friends", false)), "„Freunde online“ standardmäßig aus")
	var sv := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	check(sv.contains("\"controller.rumble_events\", \"Vibration bei Bestätigungen\"") and sv.contains("pad_test.gd"),
			"Einstellungen: Schalter und Controller-Test")
	check("pad-pulse" in HelperScript.FAST and "pad-off" in HelperScript.FAST and not ("pad-status" in HelperScript.FAST),
			"Impuls/Ausschalten über den schnellen Weg, Stand über den Hauptweg (dort läuft der Wächter)")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var at := ps.find("$script:PadsSrc = @'")
	check(at > 0, "eigener C#-Teil (einfache Anführungszeichen: nichts wird ersetzt)")
	var src := ps.substr(at, ps.find("'@", at) - at)
	check(src.contains("XInputGetBatteryInformation(i, 0,"), "Akku: BATTERY_DEVTYPE_GAMEPAD")
	check(src.contains("BATTERY_MS = 60000"), "höchstens einmal pro Minute je Controller")
	check(src.contains("EntryPoint = \"#103\")] static extern int XInputPowerOffController"), "Ausschalten: Ordinal 103")
	check(src.contains("EntryPoint = \"#108\")"), "Produktnummer: XInputGetCapabilitiesEx (Ordinal 108)")
	check(src.contains("XInputSetState") and src.contains("if (ms > 400) ms = 400;") and src.contains("var z = new Vibration(); XInputSetState"),
			"Impuls: kurz begrenzt, endet immer mit Stillstand")
	check(src.contains("00001124-0000-1000-8000-00805f9b34fb") and src.contains("0x054C"), "PlayStation: Bluetooth am Pfad, nur Sony")
	check(src.contains("hidWake.WaitOne(60000)"), "HID ebenfalls nur einmal pro Minute")
	check(ps.contains("public static volatile Action<int> OnPoll;") and ps.contains("if (poll != null) { try { poll(mask); } catch { } }"),
			"hängt am vorhandenen Controller-Wächter (kein zweiter Abfrage-Faden)")
	check(ps.contains("[UzPad]::OnPoll = [Delegate]::CreateDelegate([Action[int]], [UzPads].GetMethod('Tick'))"), "Use-Pads verbindet Tick mit dem Wächter")
	check(ps.contains("wgi = @(Get-WgiBatteries)") and ps.contains("[Windows.Gaming.Input.RawGameController]::RawGameControllers")
			and ps.contains("TryGetBatteryReport()"), "pad-status liefert auch Windows.Gaming.Input")
	for c in ["'pad-status' { Use-Pads;", "'pad-pulse' { Use-Pads;", "'pad-off' { Use-Pads;"]:
		check(ps.contains(c), "Befehl %s" % c.get_slice("'", 1))
	check(FileAccess.get_file_as_string("res://src/core/notify.gd").contains("Pads.pulse(\"message\")"), "Nachricht → Impuls")
	check(Quelle.lesen("res://src/main.gd").contains("Pads.pulse(\"clip\")"), "Clip → Impuls")

	if HelperScript._test_shell() != "":
		print("Helfer unter PowerShell 7")
		var dir := OS.get_cache_dir().path_join("uzai-pads-%d" % Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(dir)
		var script := dir.path_join("uzai-helper.ps1")
		var f := FileAccess.open(script, FileAccess.WRITE)
		f.store_string(ps)
		f.close()
		for job in [{ "id": 1, "cmd": "pad-status", "args": { "rescan": true } },
				{ "id": 1, "cmd": "pad-pulse", "args": { "pad": -1, "low": 1000, "high": 2000, "ms": 80 } }]:
			var out: Array = []
			OS.execute(HelperScript._test_shell(),
					PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Once", Marshalls.utf8_to_base64(JSON.stringify(job))]), out, true)
			var reply: Variant = null
			for line in str(out[0] if not out.is_empty() else "").split("\n"):
				var jp := JSON.new()
				var j: Variant = jp.data if line.strip_edges().begins_with("{") and jp.parse(line.strip_edges()) == OK else null
				if j is Dictionary and (j as Dictionary).has("ok"):
					reply = j
			check(reply is Dictionary and bool(reply.ok), "%s antwortet (%s)" % [job.cmd, str(reply).left(160)])
			if job.cmd == "pad-status" and reply is Dictionary:
				var parsed := P.parse_status(str((reply.result as Dictionary).get("json", "")))
				check((parsed.xinput as Array).is_empty() and (parsed.sony as Array).is_empty(), "ohne XInput/HID: leere Listen, gültiges JSON")
				check(P.parse_wgi((reply.result as Dictionary).get("wgi", [])).is_empty(), "ohne WinRT (PowerShell 7): keine Windows.Gaming.Input-Meldungen, kein Fehler")
			if job.cmd == "pad-pulse" and reply is Dictionary:
				check(int((reply.result as Dictionary).get("n", -1)) == 0, "ohne Controller: kein Impuls")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _low_toasts() -> int:
	return Toasts.history.filter(func(h): return str(h.get("title", "")) == "Controller-Akku schwach").size()

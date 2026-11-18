extends Node
## „Bild & Ton“ und Windows-Einstellungen mit dem Controller (Roadmap 4/16): Tonausgaben und Modi
## lesen, Rückfrage „Behalten?“ mit Frist (läuft ab → zurück), Prüfregeln für SSID, BSSID, Passwort,
## Gerätenamen und Energie-Werte – auch mit bösartigen Namen aus der Funkreichweite –, Doktor-Karten
## und die Helfer-Quellen (feste Befehle, Prüfung vor Windows, kein Passwort in Logs, powercfg nur
## mit fester Argumentliste). Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich: Prüffunktionen des Helfers
## unter PowerShell 7 und das C# mit C# 5 – nur Prüfpfade, nie ein echter Systemaufruf.
## Aufruf: godot --headless --path . res://tests/logic_bildton.tscn → „Ergebnis: alles ok“

const BildTon := preload("res://src/core/bild_ton.gd")
const WinEinst := preload("res://src/core/win_einst.gd")
const Doktor := preload("res://src/core/doktor.gd")
const GameProfile := preload("res://src/core/game_profile.gd")
const HelperScript := preload("res://src/core/helper.gd")

## SSIDs, die jemand in Funkreichweite seinem Netz geben könnte.
const BOESE := ["\"; Remove-Item C:\\ -Recurse #", "$(calc.exe)", "`whoami`", "a & b | c > d", "%TEMP%", "<script>x</script>",
	"[url=x]y[/url]", "' OR 1=1 --", "-Verb RunAs"]

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_ton()
	_bild()
	await _rueckfrage()
	_pending()
	_wlan()
	_bt()
	_energie()
	_doktor()
	_quellen()
	_pwsh()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# --- Ton -------------------------------------------------------------------------------------

func _ton() -> void:
	print("Tonausgabe")
	check(BildTon.audio_kind(9, "x") == "tv" and BildTon.audio_kind(3, "") == "kopfhoerer" and BildTon.audio_kind(5, "") == "kopfhoerer"
			and BildTon.audio_kind(1, "") == "lautsprecher", "Bauform von Windows")
	check(BildTon.audio_kind(-1, "Kopfhörer (USB)") == "kopfhoerer" and BildTon.audio_kind(-1, "LG TV (HDMI)") == "tv"
			and BildTon.audio_kind(-1, "Digitale Audioschnittstelle") == "anders", "ohne Bauform: nach dem Namen")
	check(BildTon.kind_icon("tv") == "tv" and BildTon.kind_icon("kopfhoerer") == "headset" and BildTon.kind_icon("anders") == "speaker", "Symbole")
	var good := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a001}"
	var devs: Array = [
		{ "id": good, "name": "LG TV\u202Egnp.exe", "ff": 9, "default": true },
		{ "id": good, "name": "doppelt", "ff": 1 },
		{ "id": good + "\n", "name": "Zeilenumbruch", "ff": 1 },
		{ "id": "{0.0.0}.{x}; calc", "name": "kaputt", "ff": 1 },
		{ "id": "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}", "name": "\n\t\u200B", "ff": 3 },
		"kein Wörterbuch",
	]
	for i in 30:
		devs.append({ "id": "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-0000000%05d}" % i, "name": "Gerät %d" % i, "ff": 1 })
	var a := BildTon.parse_audio({ "ok": true, "result": { "devices": devs } })
	var list: Array = a.devices
	check(str(list[0].name) == "LG TVgnp.exe" and str(a.current) == good, "Name ohne Richtungszeichen, aktives Gerät erkannt (%s)" % str(list[0].name))
	check(str(list[1].name) == "Tonausgabe" and str(list[1].kind) == "kopfhoerer", "leerer Name (nur Steuer- und unsichtbare Zeichen) → „Tonausgabe“")
	check(list.size() == BildTon.DEVICES_MAX, "doppelte, kaputte Kennungen und zu viele fallen weg (%d)" % list.size())
	check(BildTon.parse_audio({ "ok": false }).devices.is_empty() and BildTon.parse_audio({ "ok": true, "result": "x" }).devices.is_empty(),
			"ohne Helfer oder Unsinn: leer")


# --- Bild ------------------------------------------------------------------------------------

func _bild() -> void:
	print("Auflösung und Bildwiederholrate")
	var info := BildTon.demo_info([1920, 1080, 60])
	var res := BildTon.resolutions(info.modes)
	check(res.size() == 4 and int(res[0].w) == 3840 and int(res[3].w) == 1280, "Auflösungen ohne doppelte, größte zuerst")
	check(BildTon.rates(info.modes, 1920, 1080) == [120, 60, 50], "Raten einer Auflösung, höchste zuerst")
	check(BildTon.pick_rate(info.modes, 3840, 2160, 60) == 60, "gleiche Rate, wenn es sie gibt")
	check(BildTon.pick_rate(info.modes, 1280, 720, 120) == 60, "sonst die nächstkleinere – nie ungefragt mehr Hz")
	check(BildTon.pick_rate(info.modes, 1920, 1080, 30) == 50, "unter allem: die kleinste")
	check(BildTon.pick_rate(info.modes, 800, 600, 60) == 0, "Auflösung gibt es nicht: keine Rate")
	var sa := BildTon.set_args(info, 2560, 1440, 120)
	check(str(sa.device) == "\\\\.\\DISPLAY1" and int(sa.hz) == 120 and not sa.has("keep"), "Auftrag nur für einen Modus aus der Liste, vorübergehend")
	check(int(BildTon.set_args(info, 2560, 1440, 120, true).get("keep", 0)) == 1, "„Behalten“: mit keep")
	check(BildTon.set_args(info, 2560, 1440, 144).is_empty() and BildTon.set_args(info, 99999, 1, 60).is_empty(), "Modus nicht in der Liste: kein Auftrag")
	var bad := info.duplicate(true)
	bad.device = "\\\\.\\DISPLAY1; calc"
	check(BildTon.set_args(bad, 2560, 1440, 120).is_empty(), "fremdes Gerät: kein Auftrag")
	check(BildTon.res_text(3840, 2160) == "3840 × 2160" and BildTon.rate_text(120) == "120 Hz", "Texte")


# --- Rückfrage -------------------------------------------------------------------------------

func _rueckfrage() -> void:
	print("Rückfrage „Behalten?“")
	check(BildTon.KEEP_S == 15, "Frist 15 s wie Windows")
	check(BildTon.left_s(1000, 1000) == 15 and BildTon.left_s(1000, 1001) == 15 and BildTon.left_s(1000, 8500) == 8, "Sekunden aufgerundet")
	check(BildTon.left_s(1000, 16000) == 0 and BildTon.left_s(1000, 99000) == 0 and BildTon.left_s(5000, 1000) == 15, "nie unter 0, nie über 15")
	check(not BildTon.expired(0, 14999) and BildTon.expired(0, 15000), "abgelaufen genau nach 15 s")
	var was := Library.demo
	Library.demo = true
	BildTon.demo_mode = [3840, 2160, 60]
	var info := BildTon.demo_info(BildTon.demo_mode)
	var ends: Array = []
	var cb := func(kept: bool, timeout: bool) -> void: ends.append([kept, timeout])
	var r: Dictionary = await BildTon.change_mode(info, 3840, 2160, 60, cb)
	check(not bool(r.ok) and not BildTon.asking(), "gleicher Modus: nichts zu fragen")
	r = await BildTon.change_mode(info, 2560, 1440, 120, cb)
	check(bool(r.ok) and BildTon.asking() and BildTon.demo_mode == [2560, 1440, 120], "neuer Modus gilt, Frage offen")
	await BildTon.answer(true)
	check(not BildTon.asking() and BildTon.demo_mode == [2560, 1440, 120] and ends == [[true, false]], "Behalten: bleibt")
	info = BildTon.demo_info(BildTon.demo_mode)
	await BildTon.change_mode(info, 1920, 1080, 60, cb)
	await BildTon.answer(false)
	check(BildTon.demo_mode == [2560, 1440, 120] and ends[1] == [false, false], "Zurücksetzen: alter Modus")
	await BildTon.change_mode(info, 1920, 1080, 50, cb)
	await BildTon.change_mode(info, 1280, 720, 60, cb)
	check(BildTon.demo_mode == [1280, 720, 60] and ends[2] == [false, false], "neue Änderung während einer Frage: die alte geht erst zurück")
	print("  (wartet die Frist ab …)")
	await get_tree().create_timer(BildTon.KEEP_S + 0.6).timeout
	check(not BildTon.asking() and BildTon.demo_mode == [2560, 1440, 120] and ends.size() == 4 and ends[3] == [false, true],
			"Frist um ohne Antwort: von selbst zurück (%s)" % str(ends))
	check(await BildTon.answer(true) == "", "danach eine späte Antwort: tut nichts")
	Library.demo = was


func _pending() -> void:
	print("Nach einem Absturz mitten in der Frage")
	var p := OS.get_cache_dir().path_join("uzai-bildton-%d.json" % Time.get_ticks_usec())
	for c in [['{"display":"\\\\\\\\.\\\\DISPLAY2"}', "\\\\.\\DISPLAY2"], ['{"display":"\\\\\\\\.\\\\DISPLAY2 & calc"}', ""], ['{"display":7}', ""],
			['[1,2]', ""], ['kaputt', ""], ['{"display":"' + "x".repeat(2000) + '"}', ""]]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(str(c[0]))
		f.close()
		check(BildTon.read_pending(p) == str(c[1]), "gemerktes Gerät %s → „%s“" % [str(c[0]).left(40), str(c[1])])
	DirAccess.remove_absolute(p)
	check(BildTon.read_pending(p) == "", "ohne Datei: nichts")


# --- WLAN ------------------------------------------------------------------------------------

func _wlan() -> void:
	print("WLAN: Prüfregeln")
	for s in BOESE:
		check(WinEinst.ssid_ok(s), "bösartig klingende SSID bleibt reine Daten: %s" % s)
	check(WinEinst.ssid_ok("ä".repeat(16)) and not WinEinst.ssid_ok("ä".repeat(17)), "höchstens 32 Bytes (UTF-8, nicht Zeichen)")
	for s in ["", "a\nb", "a\u0001b", "x\u007f", "\r", 42, null, ["x"]]:
		check(not WinEinst.ssid_ok(s), "SSID abgelehnt: %s" % JSON.stringify(s))
	check(WinEinst.clean_text("Netz\u202Eexe.gpj\u200B") == "Netzexe.gpj" and WinEinst.clean_text("\u2066\u2069", "?") == "?",
			"Anzeige ohne Richtungs- und unsichtbare Zeichen")
	check(WinEinst.clean_text("x".repeat(100)).length() == WinEinst.NAME_MAX, "lange Namen gekürzt")
	check(WinEinst.bssid_ok("a4:2b:b0:11:20:01") and not WinEinst.bssid_ok("A4:2B:B0:11:20:01") and not WinEinst.bssid_ok("a4:2b:b0:11:20:01\n")
			and not WinEinst.bssid_ok("a4:2b:b0:11:20"), "BSSID genau im Format")
	check(WinEinst.key_problem("12345678") == "" and WinEinst.key_problem("x".repeat(63)) == "" and WinEinst.key_problem("Sommer 2026!") == "",
			"Passwort 8–63 druckbare Zeichen")
	check(WinEinst.key_problem("a1b2c3d4".repeat(8)) == "" and WinEinst.key_problem("g".repeat(64)) != "", "64 Zeichen nur als Hex-Schlüssel")
	check(WinEinst.key_problem("1234567") != "" and WinEinst.key_problem("x".repeat(65)) != "", "zu kurz, zu lang")
	check(WinEinst.key_problem("Grüße123") != "" and WinEinst.key_problem("abc\ndefgh") != "" and WinEinst.key_problem("abcdefg\u0000") != "",
			"Umlaute und Steuerzeichen nicht")

	print("WLAN: Antwort lesen")
	var nets: Array = []
	nets.append({ "ssid": "Zuhause", "bssid": "a4:2b:b0:11:20:02", "bars": 2, "kind": "psk", "known": true, "ghz": 2 })
	nets.append({ "ssid": "Zuhause", "bssid": "a4:2b:b0:11:20:01", "bars": 4, "kind": "psk", "known": true, "ghz": 5 })
	nets.append({ "ssid": BOESE[0], "bssid": "00:11:22:33:44:55", "bars": 9, "kind": "psk", "known": false, "ghz": 5 })
	nets.append({ "ssid": "Café", "bssid": "00:11:22:33:44:66", "bars": -3, "kind": "rm -rf", "known": false, "ghz": 9 })
	nets.append({ "ssid": "a\nb", "bssid": "00:11:22:33:44:77", "bars": 4, "kind": "psk" })
	nets.append({ "ssid": "ohne bssid", "bssid": "x", "bars": 4, "kind": "psk" })
	nets.append("Unsinn")
	for i in 70:
		nets.append({ "ssid": "Netz %02d" % i, "bssid": "10:00:00:00:00:%02x" % i, "bars": 1, "kind": "offen" })
	var w := WinEinst.parse_wlan({ "code": "ok", "radio": "an", "internet": "ok", "connected": "Zuhause", "networks": nets })
	var l: Array = w.networks
	check(str(l[0].ssid) == "Zuhause" and bool(l[0].connected) and str(l[0].bssid) == "a4:2b:b0:11:20:01", "je SSID der stärkste Zugangspunkt, verbunden zuerst")
	check(str(l[1].ssid) == BOESE[0] and int(l[1].bars) == 4, "fremder Name bleibt Daten, Balken begrenzt")
	var cafe: Array = WinEinst.parse_wlan({ "code": "ok", "networks": nets.slice(0, 4) }).networks.filter(
			func(n: Dictionary) -> bool: return str(n.ssid) == "Café")
	check(cafe.size() == 1 and str(cafe[0].kind) == "anders" and int(cafe[0].bars) == 0 and int(cafe[0].ghz) == 0, "unbekannte Art → „anders“, Unsinn begrenzt")
	check(l.filter(func(n: Dictionary) -> bool: return str(n.ssid) in ["a\nb", "ohne bssid"]).is_empty(), "Steuerzeichen oder kaputte BSSID: gar nicht gezeigt")
	check(l.size() == WinEinst.NET_MAX, "höchstens %d Netze" % WinEinst.NET_MAX)
	check(str(WinEinst.parse_wlan({ "code": "<b>", "radio": "x" }).state) == "fehler" and str(WinEinst.parse_wlan("x").state) == "fehler",
			"unbekannte Antwort: Fehler")
	check(str(WinEinst.parse_wlan({ "code": "ok", "connected": "a\nb" }).connected) == "", "verbunden mit kaputtem Namen: nicht übernommen")

	print("WLAN: Auftrag zum Verbinden")
	var known := { "ssid": "Zuhause", "bssid": "a4:2b:b0:11:20:01", "kind": "psk", "known": true }
	var fresh := { "ssid": BOESE[0], "bssid": "00:11:22:33:44:55", "kind": "psk", "known": false }
	var open := { "ssid": "Café", "bssid": "00:11:22:33:44:66", "kind": "offen", "known": false }
	var a1 := WinEinst.connect_args(known)
	check(not a1.is_empty() and not a1.has("password"), "bekanntes Netz: ohne Passwort (Windows-Profil)")
	check(WinEinst.connect_args(fresh).is_empty(), "neues WPA-Netz ohne Passwort: kein Auftrag")
	var a2 := WinEinst.connect_args(fresh, "Sommer2026!")
	check(str(a2.ssid) == BOESE[0] and str(a2.password) == "Sommer2026!", "SSID genau so, wie Windows sie meldete (nur Daten)")
	check(WinEinst.connect_args(fresh, "kurz").is_empty() and WinEinst.connect_args(fresh, "Grüße12345").is_empty(), "ungültiges Passwort: kein Auftrag")
	check(WinEinst.connect_args(open, "Sommer2026!").is_empty() and not WinEinst.connect_args(open).is_empty(), "offenes Netz nie mit Passwort")
	for k in ["firma", "wep", "anders"]:
		var n := known.duplicate()
		n.kind = k
		check(WinEinst.connect_args(n).is_empty() and WinEinst.connect_block(n) == k, "%s: Uzai verbindet nicht, erklärt" % k)
	var bad := known.duplicate()
	bad.bssid = "a4:2b:b0:11:20:01 /x"
	check(WinEinst.connect_args(bad).is_empty(), "kaputte BSSID: kein Auftrag")
	check(WinEinst.needs_key(fresh) and not WinEinst.needs_key(known) and not WinEinst.needs_key(open), "wann die Tastatur kommt")


# --- Bluetooth -------------------------------------------------------------------------------

func _bt() -> void:
	print("Bluetooth")
	var good := "Bluetooth#Bluetootha4:c3:f0:11:22:33-38:18:4c:d2:61:0f"
	var b := WinEinst.parse_bt({ "code": "an", "devices": [
		{ "id": good, "name": "WH-1000XM5\u202E", "connected": false, "major": 4, "minor": 6 },
		{ "id": good, "name": "doppelt" },
		{ "id": good + "; calc", "name": "kaputt" },
		{ "id": "BluetoothLE#BluetoothLEa4:c3:f0:11:22:33-c8:3f:26:4b:9e:01", "name": "Xbox Wireless Controller", "connected": true, "appearance": 0x03C4 },
		{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-f4:73:35:8a:02:c1", "name": "", "connected": false, "major": 5, "minor": 16 },
		7,
	] })
	var d: Array = b.devices
	check(str(b.state) == "an" and d.size() == 3, "doppelte und kaputte Kennungen fallen weg")
	check(str(d[0].name) == "Xbox Wireless Controller" and bool(d[0].connected) and str(d[0].kind) == "pad", "verbundene zuerst, Controller erkannt")
	check(str(d[1].name) == "Bluetooth-Gerät" and str(d[1].kind) == "tastatur", "leerer Name → „Bluetooth-Gerät“, Tastatur aus der Geräteklasse")
	check(str(d[2].name) == "WH-1000XM5" and str(d[2].kind) == "audio", "Kopfhörer, Name ohne Richtungszeichen")
	check(WinEinst.bt_kind({}, "Galaxy Buds") == "audio" and WinEinst.bt_icon("audio") == "headset" and WinEinst.bt_icon("anders") == "bluetooth",
			"Art nach Namen, Symbole")
	check(str(WinEinst.parse_bt({ "code": "kaputt" }).state) == "fehler", "unbekannter Zustand: Fehler")
	check(WinEinst.radio_args("bt", true) == { "kind": "bt", "on": 1 } and WinEinst.radio_args("wlan", false) == { "kind": "wlan", "on": 0 }
			and WinEinst.radio_args("bt; x", true).is_empty(), "Funk an/aus nur für wlan und bt")


# --- Energie ---------------------------------------------------------------------------------

func _energie() -> void:
	print("Energie")
	var p := WinEinst.parse_power(
			{ "ok": true, "ac": { "monitor": 600, "sleep": 0, "hibernate": -1 }, "dc": "x", "battery": true, "hibernate_ok": false, "can_set": true })
	check(bool(p.ok) and int(p.ac.monitor) == 10 and int(p.ac.sleep) == 0 and int(p.ac.hibernate) == -1, "Sekunden → Minuten, 0 = nie, unbekannt -1")
	check(int(p.dc.monitor) == -1 and bool(p.battery) and not bool(p.hibernate_ok), "kaputter Teil: unbekannt")
	check(not bool(WinEinst.parse_power(null).ok) and not bool(WinEinst.parse_power({ "ok": false }).ok), "ohne Antwort: nichts")
	check(WinEinst.power_args("monitor", "ac", 10) == { "what": "monitor", "src": "ac", "min": 10 }, "fester Auftrag")
	for bad in [["monitor; shutdown /s", "ac", 10], ["monitor", "ac /h off", 10], ["sleep", "dc", 7], ["sleep", "dc", -1], ["hibernate", "ac", 100000],
			["lock", "ac", 5]]:
		check(WinEinst.power_args(str(bad[0]), str(bad[1]), int(bad[2])).is_empty(), "abgelehnt: %s" % str(bad))
	check(WinEinst.minutes_text(0) == "Nie" and WinEinst.minutes_text(5) == "5 Min." and WinEinst.minutes_text(60) == "1 Stunde"
			and WinEinst.minutes_text(180) == "3 Stunden", "Texte")
	var o := WinEinst.power_options(7)
	check(int(o[0][0]) == 7 and o.size() == WinEinst.POWER_MINUTES.size() + 1, "abweichender Wert aus Windows wird gezeigt, wählbar bleibt die feste Liste")


# --- Doktor ----------------------------------------------------------------------------------

func _ids(list: Array) -> Array:
	return list.map(func(c: Dictionary) -> String: return str(c.id))


func _doktor() -> void:
	print("Uzai-Doktor")
	var c := Doktor.cards({ "wlan": { "radio": "an", "internet": "keins", "connected": "" } })
	check(c.size() == 1 and str(c[0].id) == "netz" and str(c[0].fix) == "wlan" and bool(c[0].self) and str(c[0].icon) == "wifi",
			"kein Netz, WLAN nicht verbunden: „WLAN-Liste“")
	check(str(Doktor.cards({ "wlan": { "radio": "aus", "internet": "keins", "connected": "" } })[0].text).begins_with("Das WLAN ist aus."), "WLAN aus: so gesagt")
	var w2 := Doktor.cards({ "net": "weg", "wlan": { "radio": "an", "internet": "lokal", "connected": "Zuhause" } })
	check(w2.size() == 1 and not bool(w2[0].self) and str(w2[0].fix) == "", "mit WLAN verbunden, aber kein Internet: nur erklären (Router)")
	check(Doktor.cards({ "wlan": { "radio": "an", "internet": "ok", "connected": "" } }).is_empty(), "Internet über Kabel: keine Karte")
	var b := Doktor.cards({ "bt": { "radio": "aus", "paired": 2 }, "pads": 1 })
	check(b.size() == 1 and str(b[0].id) == "bt_aus" and str(b[0].fix) == "bt_an" and str(b[0].sev) == "hinweis",
			"Bluetooth aus mit gekoppelten Geräten: „Einschalten“")
	check(_ids(Doktor.cards({ "bt": { "radio": "aus", "paired": 0 }, "pads": 0 })).has("bt_aus"), "Bluetooth aus und kein Controller: Hinweis")
	check(Doktor.cards({ "bt": { "radio": "aus", "paired": 0 }, "pads": 2 }).is_empty(), "Bluetooth bewusst aus, nichts gekoppelt: kein Hinweis")
	check(Doktor.cards({ "bt": { "radio": "an", "paired": 3 } }).is_empty(), "Bluetooth an: nichts")
	check(Doktor.ok_checks({ "bt": { "radio": "an", "paired": 1 } }, []).has("Bluetooth") and not Doktor.ok_checks({}, []).has("Bluetooth"),
			"„Bluetooth“ in Ordnung nur, wenn bekannt")
	check(
			WinEinst.lage_from(WinEinst.parse_wlan(WinEinst.DEMO_WLAN),
			WinEinst.parse_bt(WinEinst.DEMO_BT)) == { "wlan": { "radio": "an", "internet": "ok", "connected": "Zuhause" }, "bt": { "radio": "an", "paired": 3 } },
			"Lage aus den Antworten")
	check(WinEinst.lage_from(WinEinst.parse_wlan({ "code": "kein" }), WinEinst.parse_bt({ "code": "admin" })).is_empty(),
			"kein WLAN, Adminrechte: der Doktor weiß nichts (rät nicht)")


# --- Quellen ---------------------------------------------------------------------------------

func _fn(ps: String, name: String) -> String:
	var a := ps.find("function %s" % name)
	if a < 0:
		return ""
	var b := ps.find("\n}\n", a)
	return ps.substr(a, b - a + 2)


func _quellen() -> void:
	print("Helfer-Quellen")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1").replace("\r\n", "\n")
	for c in ["power-times", "power-time-set", "wlan-state", "wlan-connect", "wlan-poll", "wlan-disconnect", "radio-set", "bt-paired", "bt-unpair"]:
		check(ps.contains("        '%s' {" % c), "fester Befehl „%s“" % c)
	check(not ps.to_lower().contains("invoke-expression"), "kein Invoke-Expression")
	var con := _fn(ps, "Wlan-Connect(")
	check(con.find("Test-Ssid $ssid") < con.find("Use-Wlan") and con.find("Test-Bssid $bssid") < con.find("Use-Wlan")
			and con.find("Test-WlanKey $key") < con.find("Use-Wlan"), "WLAN: SSID, BSSID und Passwort geprüft, bevor Windows gefragt wird")
	check(con.contains("if ($null -ne $key) { $a.password = $null }") and con.contains("$key = $null") and con.contains("$cred = $null"),
			"Passwort nur kurz im Helfer, danach verworfen")
	check(con.contains("New-Object Windows.Security.Credentials.PasswordCredential") and con.contains("$ad.ConnectAsync($net, $how, $cred)"),
			"Passwort nur als PasswordCredential an Windows")
	check(con.contains("Find-WlanNetwork $ad $ssid $bssid") and _fn(ps, "Find-WlanNetwork(").contains("-ceq $bssid")
			and _fn(ps, "Find-WlanNetwork(").contains("-ceq $ssid"), "Netz nur durch Vergleich mit der Liste von Windows (keine Kommandozeile)")
	check(con.contains("if ($kind -cne 'offen' -and $kind -cne 'psk')"), "Firmen-WLAN und WEP lehnt der Helfer selbst ab")
	var wl_a := ps.find("# --- Windows-Einstellungen mit dem Controller")
	var wl := ps.substr(wl_a, ps.find("# --- Controller koppeln", wl_a) - wl_a)
	for badw in ["Write-Host", "Out-File", "Add-Content", "Set-Content", "netsh", "WlanSetProfile", "WlanConnect(", "Start-Process", "-Verb RunAs",
			"Set-ItemProperty", "LockWorkStation", "logoff", "shutdown"]:
		check(not wl.contains(badw), "Windows-Teil ohne %s" % badw)
	check(wl.count("$a.password") == 2 and not wl.contains("password = [string]") and not wl.contains("password)"),
			"Passwort taucht nur beim Lesen und Löschen auf")
	var pw := _fn(ps, "Power-TimeSet(")
	check(pw.contains("& $exe '/change' $switch ([string]$min)") and pw.find("$script:PowerMinutes -contains $min") < pw.find("& $exe"),
			"powercfg nur mit fester Argumentliste und Wert aus der Liste")
	check(ps.contains("$script:PowerMinutes = @(%s)" % ", ".join(PackedStringArray(WinEinst.POWER_MINUTES.map(func(m: int) -> String: return str(m))))),
			"dieselbe Minutenliste wie in Uzai")
	check(pw.contains("'System32\\powercfg.exe'") and pw.contains("Test-Path -LiteralPath $exe"), "powercfg mit vollem Pfad aus Windows")
	for f in ["Wlan-State(", "Wlan-Connect(", "Wlan-Disconnect", "Radio-Set(", "Bt-Paired", "Bt-Unpair(", "Power-TimeSet("]:
		check(_fn(ps, f).contains("if (Test-BtAdmin)"), "%s: nie mit Adminrechten" % f.trim_suffix("("))
	var un := _fn(ps, "Bt-Unpair(")
	check(un.find("Test-BtId $id") < un.find("Use-Bt") and un.contains("if (-not $dev.Pairing.IsPaired)"),
			"Entfernen: Kennung zuerst, Windows bestätigt „gekoppelt“")
	var rs := _fn(ps, "Radio-Set(")
	check(rs.contains("$kind -cne 'wlan' -and $kind -cne 'bt'") and rs.find("'daten'") < rs.find("SetStateAsync"), "Funk nur wlan/bt, geprüft vor dem Umschalten")
	var cs_a := ps.find("$script:WlanSrc = @'")
	var cs := ps.substr(cs_a, ps.find("'@", cs_a) - cs_a)
	check(cs.contains("WlanGetProfileList") and not cs.contains("WlanSetProfile") and not cs.contains("WlanConnect") and not cs.contains("WlanDeleteProfile"),
			"WLAN-C# liest nur Profilnamen")
	check(ps.contains("keep ? CDS_UPDATEREGISTRY | CDS_NORESET : CDS_FULLSCREEN") and ps.contains("((Get-Num $a.keep 1) -eq 1)"),
			"Auflösung: erst vorübergehend, „Behalten“ ohne neues Umschalten")
	check(ps.contains(",\\\"ff\\\":\" + ff + \"}\""), "Tonausgaben mit Bauform")
	# Uzai-Seite: kein Passwort in Protokollen, Tastatur ohne Handy-Eingabe.
	var wsrc := FileAccess.get_file_as_string("res://src/ui/layers/win_wlan.gd")
	check(wsrc.contains("kb.secret = true") and wsrc.contains("kb.phone_ok = false") and wsrc.contains("kb.text = \"\""),
			"Passwort verdeckt, ohne Handy, Tastatur danach leer")
	check(wsrc.contains("args.clear()") and not wsrc.contains("print(") and not wsrc.contains("log_line") and not wsrc.contains("hlog"),
			"Auftrag mit Passwort danach geleert, nichts protokolliert")
	var hsrc := FileAccess.get_file_as_string("res://src/core/helper.gd")
	var run_a := hsrc.find("func run(")
	var run_src := hsrc.substr(run_a, hsrc.find("\nfunc ", run_a + 5) - run_a)
	check(not run_src.contains("JSON.stringify(args)") and not run_src.contains("str(args)"), "Helper.run schreibt Aufträge nie ins Protokoll")
	check(not ("wlan-connect" in HelperScript.FAST) and not ("wlan-connect" in HelperScript.EITHER), "Verbinden über den Hauptweg (dort lebt der Adapter)")
	var kb := FileAccess.get_file_as_string("res://src/ui/layers/keyboard.gd")
	check(kb.contains("if phone_ok:"), "Bildschirmtastatur kann ohne Handy-Eingabe")


# --- PowerShell 7 ----------------------------------------------------------------------------

func _pwsh() -> void:
	if HelperScript._test_shell() == "":
		print("  (PowerShell-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")
		return
	print("Helfer unter PowerShell 7 (nur Prüfpfade)")
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var dir := OS.get_cache_dir().path_join("uzai-bildton-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("uzai-helper.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string(ps)
	f.close()
	# Jeder Auftrag scheitert an der Prüfung, bevor irgendetwas Windows berührt.
	for job in [
			{ "cmd": "wlan-connect", "args": { "ssid": "a\nb", "bssid": "00:11:22:33:44:55" }, "want": "daten" },
			{ "cmd": "wlan-connect", "args": { "ssid": "x".repeat(33), "bssid": "00:11:22:33:44:55" }, "want": "daten" },
			{ "cmd": "wlan-connect", "args": { "ssid": ["Zuhause"], "bssid": "00:11:22:33:44:55" }, "want": "daten" },
			{ "cmd": "wlan-connect", "args": { "ssid": "Zuhause", "bssid": "00:11:22:33:44:55; calc" }, "want": "daten" },
			{ "cmd": "wlan-connect", "args": { "ssid": BOESE[0], "bssid": "00:11:22:33:44:55", "password": "kurz" }, "want": "passwort" },
			{ "cmd": "wlan-connect", "args": { "ssid": "Zuhause", "bssid": "00:11:22:33:44:55", "password": "Grüße12345" }, "want": "passwort" },
			{ "cmd": "wlan-connect", "args": { "ssid": "Zuhause", "bssid": "00:11:22:33:44:55", "password": 12345678 }, "want": "passwort" },
			{ "cmd": "radio-set", "args": { "kind": "bt; calc", "on": 1 }, "want": "daten" },
			{ "cmd": "radio-set", "args": { "kind": "BT", "on": 1 }, "want": "daten" },
			{ "cmd": "radio-set", "args": { "kind": "bt", "on": "an" }, "want": "daten" },
			{ "cmd": "bt-unpair", "args": { "id": "Bluetooth#Bluetooth00:1a:7d:da:71:13-e4:17:d8:2a:00:9b\n" }, "want": "kennung" },
			{ "cmd": "power-time-set", "args": { "what": "monitor", "src": "ac", "min": 7 }, "want": "daten" },
			{ "cmd": "power-time-set", "args": { "what": "monitor; shutdown", "src": "ac", "min": 10 }, "want": "daten" },
			{ "cmd": "power-time-set", "args": { "what": "lock", "src": "ac", "min": 10 }, "want": "daten" },
			{ "cmd": "power-time-set", "args": { "what": ["monitor"], "src": "ac", "min": 10 }, "want": "daten" }]:
		var out: Array = []
		OS.execute(HelperScript._test_shell(),
				PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Once",
				Marshalls.utf8_to_base64(JSON.stringify({ "id": 1, "cmd": job.cmd, "args": job.args }))]), out, true)
		var code := ""
		for line in str(out[0] if not out.is_empty() else "").split("\n"):
			var jp := JSON.new()
			if line.strip_edges().begins_with("{") and jp.parse(line.strip_edges()) == OK and jp.data is Dictionary \
					and (jp.data as Dictionary).get("result") is Dictionary:
				code = str(jp.data.result.get("code", ""))
		check(code == str(job.want), "%s %s → %s" % [job.cmd, JSON.stringify(job.args).left(60), code])
	var probe := dir.path_join("probe.ps1")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	pf.store_string("""
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$defs = ''
foreach ($fn in 'Test-Ssid', 'Test-Bssid', 'Test-WlanKey', 'Get-WlanKind', 'Get-WlanResult') {
    $m = [regex]::Match($src, '(?s)\\n(function ' + $fn + '[\\s(].*?\\n\\})\\n')
    $defs += $m.Groups[1].Value + "`n"
}
$tmp = Join-Path $args[1] 'fns.ps1'
Set-Content -LiteralPath $tmp -Value $defs -Encoding UTF8
. $tmp
"SSID " + (Test-Ssid 'Zuhause') + " " + (Test-Ssid '"; Remove-Item C:\\ -Recurse #') + " " + (Test-Ssid ("a" + [char]10 + "b")) + " " + (Test-Ssid ('ä' * 17)) + " " + (Test-Ssid '') + " " + (Test-Ssid 42)
"BSSID " + (Test-Bssid 'a4:2b:b0:11:20:01') + " " + (Test-Bssid 'A4:2B:B0:11:20:01') + " " + (Test-Bssid ("a4:2b:b0:11:20:01" + [char]10))
"KEY " + (Test-WlanKey 'Sommer2026!') + " " + (Test-WlanKey 'kurz') + " " + (Test-WlanKey ('a1' * 32)) + " " + (Test-WlanKey ('g' * 64)) + " " + (Test-WlanKey 'Grüße12345') + " " + (Test-WlanKey 12345678)
"KIND " + (Get-WlanKind 2 0) + " " + (Get-WlanKind 2 2) + " " + (Get-WlanKind 8 6) + " " + (Get-WlanKind 11 6) + " " + (Get-WlanKind 7 6) + " " + (Get-WlanKind 12 6) + " " + (Get-WlanKind 1 0)
"RESULT " + (Get-WlanResult 1) + " " + (Get-WlanResult 3) + " " + (Get-WlanResult 99)
foreach ($n in 'DisplaySrc', 'AudioSrc', 'PerfSrc', 'WlanSrc') {
    $cs = [regex]::Match($src, '(?s)\\$script:' + $n + ' = @[''"]\\n(.*?)\\n[''"]@').Groups[1].Value
    try { Add-Type -TypeDefinition $cs -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop; "CS $n ok " + $cs.Length } catch { "CS $n FEHLER " + $_.Exception.Message }
}
$errs = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tok, [ref]$errs)
"PARSE " + $errs.Count
""")
	pf.close()
	var o2: Array = []
	OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, script, dir]), o2, true)
	var txt := str(o2[0] if not o2.is_empty() else "")
	check(txt.contains("SSID True True False False False False"), "Test-Ssid wie in Uzai (bösartiger Text ist Daten, Steuerzeichen und > 32 Bytes nicht)")
	check(txt.contains("BSSID True False False"), "Test-Bssid genau im Format")
	check(txt.contains("KEY True False True False False False"), "Test-WlanKey wie in Uzai")
	check(txt.contains("KIND offen wep psk psk firma offen anders"), "Get-WlanKind: offen, WEP, WPA2/WPA3-Personal, Enterprise, OWE")
	check(txt.contains("RESULT verbunden passwort fehler"), "Ergebnis von Windows → Uzais Schlüssel")
	for n in ["DisplaySrc", "AudioSrc", "PerfSrc", "WlanSrc"]:
		check(txt.contains("CS %s ok" % n), "C# %s übersetzt mit C# 5 (%s)" % [n, txt.get_slice("CS %s" % n, 1).get_slice("\n", 0).strip_edges().left(160)])
	check(txt.contains("PARSE 0"), "Helfer ohne Parse-Fehler")
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir)

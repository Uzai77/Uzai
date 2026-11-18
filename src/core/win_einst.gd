extends RefCounted
## Windows-Einstellungen mit dem Controller (Roadmap 4/16) ohne Oberfläche: WLAN, Bluetooth und
## Energie – was an den Helfer darf, was seine Antworten bedeuten, und der zuletzt gelesene Stand
## für den Uzai-Doktor. Die Seiten dazu: src/ui/layers/win_wlan.gd, win_bt.gd und win_energie.gd
## (Einstellungen → System → Windows). Getestet in tests/logic_bildton.gd.
##
## Sicherheit: Der Helfer („wlan-*“, „radio-set“, „bt-paired“, „bt-unpair“, „power-*“ in
## helper/uzai-helper.ps1) prüft alles noch einmal selbst – was hier steht, ist die erste von zwei
## Sperren. SSIDs und Gerätenamen sind fremde Daten (jeder in Funkreichweite kann sein Netz so
## nennen): Zurück an Windows gehen sie nur als Daten, auf dem Bildschirm ohne Steuer- und
## Richtungszeichen und nie übersetzt. Ein WLAN-Passwort lebt nur, bis es beim Helfer ist: Uzai
## speichert, protokolliert und zeigt es nicht, und die Handy-Eingabe (unverschlüsselt im Heimnetz)
## bleibt dafür zu. Windows merkt sich das Netz danach selbst, wie beim Verbinden über die Taskleiste.

const Koppeln := preload("res://src/core/koppeln.gd")

const SSID_MAX := 32               ## Bytes (UTF-8), wie im WLAN-Standard
const KEY_MIN := 8
const KEY_MAX := 63
const NAME_MAX := 60
const NET_MAX := 40                ## mehr Netze zeigt keine Konsole
const BT_MAX := 32
const BSSID_RE := "\\A([0-9a-f]{2}:){5}[0-9a-f]{2}\\z"
static var _RX_BSSID := RegEx.create_from_string(BSSID_RE)
static var _RX_HEX64 := RegEx.create_from_string("\\A[0-9A-Fa-f]{64}\\z")
## Minuten wie in den Windows-Einstellungen (0 = nie); dieselbe Liste steht im Helfer.
const POWER_MINUTES := [0, 1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 120, 180, 240, 300]
const POWER_WHAT := ["monitor", "sleep", "hibernate"]
const POWER_SRC := ["ac", "dc"]
const WLAN_KINDS := ["offen", "psk", "firma", "wep", "anders"]

## Antworten des Helfers → [Titel, Satz, Ton]. Ton: ok, warn, faint.
const STATUS := {
	"verbunden": ["Verbunden", "Windows hat die Verbindung hergestellt und merkt sich das Netz.", "ok"],
	"gestartet": ["Verbindet …", "Windows verbindet gerade.", "faint"],
	"laeuft": ["Verbindet schon", "Windows verbindet gerade schon. Kurz warten und dann noch einmal versuchen.", "faint"],
	"getrennt": ["Getrennt", "WLAN getrennt.", "ok"],
	"passwort": ["Passwort stimmt nicht", "Windows hat das Passwort nicht angenommen. Noch einmal eingeben – Groß- und Kleinschreibung zählen.", "warn"],
	"weg": ["Netz nicht mehr da", "Das Netz ist gerade nicht in Reichweite. Neu suchen und noch einmal wählen.", "warn"],
	"zeit": ["Zeit abgelaufen", "Der Router hat nicht rechtzeitig geantwortet. Näher heran oder noch einmal versuchen.", "warn"],
	"abgelehnt": ["Abgelehnt", "Windows oder das Gerät hat abgelehnt. Prüfen, ob es neue Verbindungen erlaubt, und noch einmal versuchen.", "warn"],
	"firma": ["Anmeldung mit Konto",
		"Dieses Netz braucht Benutzername oder Zertifikat (WPA-Enterprise). Das richtest du einmal in Windows ein: Einstellungen → Netzwerk und Internet → WLAN.",
		"warn"],
	"wep": ["Veraltete Verschlüsselung", "WEP wird nicht unterstützt. Router auf WPA2 oder WPA3 umstellen.",
		"warn"],
	"anders": ["Wird nicht unterstützt", "Nicht unterstützt. In Windows verbinden.", "warn"],
	"daten": ["Nicht angenommen", "Nicht übernommen. Neu suchen und erneut wählen.", "warn"],
	"kein": ["Nicht vorhanden", "Dieser PC hat das nicht (oder es ist im Geräte-Manager abgeschaltet). Ein Kabel geht immer.", "warn"],
	"aus": ["Ausgeschaltet", "Einschalten geht hier mit A – über Windows selbst.", "warn"],
	"zugriff": ["Windows erlaubt es nicht", "Ab Windows 11 braucht die WLAN-Suche den Standortzugriff für Desktop-Apps: Windows-Einstellungen → Datenschutz und Sicherheit → Standort → „Desktop-Apps den Zugriff erlauben“. Uzai ändert das nicht selbst.", "warn"],
	"admin": ["Mit Adminrechten gestartet",
		"Uzai ohne Administratorrechte starten.", "warn"],
	"entfernt": ["Entfernt", "Windows hat das Gerät vergessen. Zum Wiederverbinden neu koppeln.", "ok"],
	"schon": ["Schon entfernt", "Windows kennt dieses Gerät nicht mehr.", "ok"],
	"kennung": ["Nicht angenommen", "Uzai hat die Kennung des Geräts nicht angenommen. Liste neu laden und noch einmal versuchen.", "warn"],
	"fehlt": ["Nicht mehr da", "Windows findet das Gerät nicht mehr. Liste neu laden.", "warn"],
	"ok": ["Erledigt", "Windows hat es übernommen.", "ok"],
	"windows": ["Nur unter Windows", "Das geht über Windows selbst – auf diesem System nicht.", "faint"],
	"helfer": ["Helfer antwortet nicht", "Windows-Helfer antwortet nicht. Erneut versuchen.",
		"warn"],
	"fehler": ["Windows hat es nicht übernommen", "Windows hat es nicht abgeschlossen. Gleich noch einmal versuchen.", "warn"],
}

## Vorführung (--demo) und Proben: ein Wohnzimmer-PC mit WLAN und ein paar Bluetooth-Geräten.
const DEMO_WLAN := {
	"code": "ok", "radio": "an", "internet": "ok", "connected": "Zuhause", "busy": false, "networks": [
		{ "ssid": "Zuhause", "bssid": "a4:2b:b0:11:20:01", "bars": 4, "kind": "psk", "known": true, "ghz": 5 },
		{ "ssid": "Zuhause", "bssid": "a4:2b:b0:11:20:02", "bars": 3, "kind": "psk", "known": true, "ghz": 2 },
		{ "ssid": "FRITZ!Box 7590 KL", "bssid": "3c:a6:2f:40:8e:11", "bars": 3, "kind": "psk", "known": false, "ghz": 5 },
		{ "ssid": "Café am Markt", "bssid": "0e:18:d6:22:91:7a", "bars": 2, "kind": "offen", "known": false, "ghz": 2 },
		{ "ssid": "Büro", "bssid": "f0:9f:c2:10:00:3b", "bars": 1, "kind": "firma", "known": false, "ghz": 5 },
	] }
const DEMO_BT := {
	"code": "an", "devices": [
		{ "id": "BluetoothLE#BluetoothLEa4:c3:f0:11:22:33-c8:3f:26:4b:9e:01", "name": "Xbox Wireless Controller", "connected": true, "major": 0, "minor": 0,
			"appearance": 0x03C4 },
		{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-38:18:4c:d2:61:0f", "name": "WH-1000XM5", "connected": false, "major": 4, "minor": 6, "appearance": 0 },
		{ "id": "Bluetooth#Bluetootha4:c3:f0:11:22:33-f4:73:35:8a:02:c1", "name": "MX Keys", "connected": true, "major": 5, "minor": 16, "appearance": 0 },
	] }
const DEMO_POWER := { "ok": true, "ac": { "monitor": 600, "sleep": 1800, "hibernate": 0 }, "dc": { "monitor": 300, "sleep": 900, "hibernate": 0 },
	"battery": false, "hibernate_ok": true, "can_set": true }

## Zuletzt gelesener Stand für den Doktor: { wlan: { radio, internet, connected }, bt: { radio, paired } }.
static var lage := {}
static var _lage_ms := -1000000
const LAGE_MS := 30000


# --- Fremde Texte ----------------------------------------------------------------------------

## Name eines fremden Geräts oder Netzes für den Bildschirm: ohne Steuer-, Richtungs- und
## unsichtbare Zeichen (gegen vorgetäuschte Namen), gekürzt; leer → fallback.
static func clean_text(v: Variant, fallback := "", max_len := NAME_MAX) -> String:
	var out := ""
	for ch in str(v if v != null else ""):
		var c := ch.unicode_at(0)
		if c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) \
				or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF or c == 0xFFFD:
			continue
		out += ch
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.left(max_len - 1).strip_edges() + "…"
	return out if out != "" else fallback


## SSID, die an den Helfer darf: Text mit 1–32 Bytes, ohne Steuerzeichen (sonst gar nicht zeigen).
static func ssid_ok(v: Variant) -> bool:
	if not (v is String):
		return false
	var s := v as String
	if s.is_empty() or s.to_utf8_buffer().size() > SSID_MAX:
		return false
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 0x20 or c == 0x7F:
			return false
	return true


static func bssid_ok(v: Variant) -> bool:
	return v is String and _RX_BSSID.search(v) != null


## Was am Passwort nicht stimmt ("" = in Ordnung): WPA erlaubt 8–63 druckbare ASCII-Zeichen oder
## 64 Hex-Ziffern. Geprüft, bevor es überhaupt zum Helfer geht.
static func key_problem(k: String) -> String:
	if k.length() == 64:
		return "" if _RX_HEX64.search(k) != null else "Mit 64 Zeichen muss es ein Schlüssel aus 0–9 und A–F sein."
	if k.length() < KEY_MIN:
		return "Ein WLAN-Passwort hat mindestens 8 Zeichen."
	if k.length() > KEY_MAX:
		return "Ein WLAN-Passwort hat höchstens 63 Zeichen."
	for ch in k:
		var c := ch.unicode_at(0)
		if c < 0x20 or c > 0x7E:
			return "WLAN-Passwörter bestehen nur aus Buchstaben ohne Umlaute, Ziffern und Satzzeichen."
	return ""


static func status(code: String) -> Array:
	return STATUS.get(code, STATUS.fehler)


## Schlüssel einer Antwort ({ code } vom Helfer) – Unbekanntes wird „fehler“.
static func code_of(r: Dictionary) -> String:
	if not bool(r.get("ok", false)):
		return "helfer" if str(r.get("error", "")) != "nur unter Windows" else "windows"
	var res: Variant = r.get("result")
	var c := str((res as Dictionary).get("code", "")) if res is Dictionary else ""
	return c if STATUS.has(c) or c == "an" or c == "nichts" else "fehler"


# --- WLAN ------------------------------------------------------------------------------------

## Antwort auf „wlan-state“ → { state, radio, internet, connected, busy, networks: [{ ssid, name,
## bssid, bars, kind, known, connected, ghz }] }. Je SSID nur der stärkste Zugangspunkt (wie in der
## Taskleiste); verbunden zuerst, dann bekannte, dann nach Signal. Kaputtes und Doppeltes fällt weg.
static func parse_wlan(d: Variant) -> Dictionary:
	var out := { "state": "fehler", "radio": "", "internet": "", "connected": "", "busy": false, "networks": [] }
	if not (d is Dictionary):
		return out
	var r := d as Dictionary
	var st := str(r.get("code", ""))
	out.state = st if STATUS.has(st) else "fehler"
	out.radio = str(r.get("radio", "")) if str(r.get("radio", "")) in ["an", "aus", "kein"] else ""
	out.internet = str(r.get("internet", "")) if str(r.get("internet", "")) in ["ok", "lokal", "keins"] else ""
	var con: Variant = r.get("connected", "")
	out.connected = str(con) if ssid_ok(con) else ""
	out.busy = bool(r.get("busy", false))
	var best := {}
	var list: Variant = r.get("networks", [])
	if list is Array:
		for e in (list as Array).slice(0, 80):
			if not (e is Dictionary):
				continue
			var n := e as Dictionary
			var ssid: Variant = n.get("ssid", "")
			var bssid: Variant = n.get("bssid", "")
			if not ssid_ok(ssid) or not bssid_ok(bssid):
				continue
			var kind := str(n.get("kind", ""))
			var item := { "ssid": str(ssid), "name": clean_text(ssid, "?", SSID_MAX), "bssid": str(bssid),
				"bars": clampi(int(n.get("bars", 0)), 0, 4), "kind": kind if kind in WLAN_KINDS else "anders",
				"known": bool(n.get("known", false)), "connected": str(ssid) == out.connected and out.connected != "",
				"ghz": int(n.get("ghz", 0)) if int(n.get("ghz", 0)) in [2, 5, 6] else 0 }
			var old: Variant = best.get(item.ssid)
			if old == null or int(item.bars) > int((old as Dictionary).bars):
				best[item.ssid] = item
	var nets: Array = best.values()
	nets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.connected) != bool(b.connected):
			return bool(a.connected)
		if bool(a.known) != bool(b.known):
			return bool(a.known)
		if int(a.bars) != int(b.bars):
			return int(a.bars) > int(b.bars)
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	out.networks = nets.slice(0, NET_MAX)
	return out


## Braucht dieses Netz ein Passwort von dir? Nur WPA-Personal, das Windows noch nicht kennt.
static func needs_key(n: Dictionary) -> bool:
	return str(n.get("kind", "")) == "psk" and not bool(n.get("known", false))


## Kann Uzai überhaupt verbinden? Sonst der Schlüssel, der erklärt, warum nicht ("" = ja).
static func connect_block(n: Dictionary) -> String:
	var k := str(n.get("kind", ""))
	return "" if k in ["offen", "psk"] else (k if STATUS.has(k) else "anders")


## Auftrag für „wlan-connect“, {} wenn etwas nicht passt. Das Passwort steht nur hier drin und geht
## sofort an den Helfer; ohne Passwort verbindet Windows mit seinem gespeicherten Profil.
static func connect_args(n: Dictionary, key := "") -> Dictionary:
	if not ssid_ok(n.get("ssid")) or not bssid_ok(n.get("bssid")) or connect_block(n) != "":
		return {}
	var a := { "ssid": str(n.ssid), "bssid": str(n.bssid), "auto": 1 }
	if key != "":
		if str(n.kind) != "psk" or key_problem(key) != "":
			return {}
		a["password"] = key
	elif needs_key(n):
		return {}
	return a


## Zeile unter dem Netznamen: „Gespeichert · 5 GHz“, „Offen, ohne Passwort“ … („Verbunden“ steht
## rechts in der Zeile.)
static func net_line(n: Dictionary) -> String:
	var bits := PackedStringArray()
	if bool(n.get("known", false)) and not bool(n.get("connected", false)):
		bits.append(TranslationServer.translate("Gespeichert"))
	match str(n.get("kind", "")):
		"offen": bits.append(TranslationServer.translate("Offen, ohne Passwort"))
		"firma": bits.append(TranslationServer.translate("Anmeldung mit Konto"))
		"wep": bits.append(TranslationServer.translate("Veraltet (WEP)"))
		"anders": bits.append(TranslationServer.translate("Nicht unterstützt"))
	if int(n.get("ghz", 0)) > 0:
		bits.append("%d GHz" % int(n.ghz))
	return "  ·  ".join(bits)


# --- Bluetooth -------------------------------------------------------------------------------

## Art eines Geräts aus Geräteklasse (Class of Device) bzw. Erscheinungsbild (LE), sonst nach dem
## Namen: pad, audio, tastatur, maus, handy oder anders.
static func bt_kind(d: Dictionary, name: String) -> String:
	var major := int(d.get("major", 0))
	var minor := int(d.get("minor", 0))
	var look := int(d.get("appearance", 0))
	if Koppeln.is_gamepad(d):
		return "pad"
	if major == 4 or (look >> 6) == 0x25 or (look >> 6) == 0x21:
		return "audio"
	if (major == 5 and (minor & 0x10) != 0) or look == 0x03C1:
		return "tastatur"
	if (major == 5 and (minor & 0x20) != 0) or look == 0x03C2:
		return "maus"
	if major == 2:
		return "handy"
	var n := name.to_lower()
	for w in ["kopfhörer", "headphone", "headset", "buds", "airpods", "speaker", "lautsprecher", "soundbar", "wh-", "wf-"]:
		if n.contains(w):
			return "audio"
	if n.contains("controller") or n.contains("gamepad"):
		return "pad"
	return "anders"


static func bt_icon(kind: String) -> String:
	return { "pad": "controller", "audio": "headset", "tastatur": "keyboard", "handy": "phone" }.get(kind, "bluetooth")


## Antwort auf „bt-paired“ → { state, devices: [{ id, name, connected, kind }] }; verbundene zuerst.
static func parse_bt(d: Variant) -> Dictionary:
	var out := { "state": "fehler", "devices": [] }
	if not (d is Dictionary):
		return out
	var r := d as Dictionary
	var st := str(r.get("code", ""))
	out.state = st if st == "an" or STATUS.has(st) else "fehler"
	var seen := {}
	var devs: Array = []
	var list: Variant = r.get("devices", [])
	if list is Array:
		for e in list:
			if not (e is Dictionary) or devs.size() >= BT_MAX:
				continue
			var id: Variant = (e as Dictionary).get("id", "")
			if not Koppeln.valid_id(id) or seen.has(id):
				continue
			seen[id] = true
			var nm := clean_text((e as Dictionary).get("name", ""), "Bluetooth-Gerät")
			devs.append({ "id": str(id), "name": nm, "connected": bool((e as Dictionary).get("connected", false)),
				"kind": bt_kind(e, nm) })
	devs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.connected) != bool(b.connected):
			return bool(a.connected)
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	out.devices = devs
	return out


static func radio_args(kind: String, on: bool) -> Dictionary:
	return { "kind": kind, "on": 1 if on else 0 } if kind in ["wlan", "bt"] else {}


# --- Energie ---------------------------------------------------------------------------------

## Antwort auf „power-times“ → { ok, ac: { monitor, sleep, hibernate }, dc: {…}, battery,
## hibernate_ok, can_set } in Minuten (0 = nie, -1 = unbekannt).
static func parse_power(d: Variant) -> Dictionary:
	var out := { "ok": false, "ac": {}, "dc": {}, "battery": false, "hibernate_ok": false, "can_set": false }
	if not (d is Dictionary) or not bool((d as Dictionary).get("ok", false)):
		return out
	var r := d as Dictionary
	out.ok = true
	for src in POWER_SRC:
		var part: Dictionary = r.get(src) if r.get(src) is Dictionary else {}
		var vals := {}
		for w in POWER_WHAT:
			var s := int(part.get(w, -1))
			vals[w] = -1 if s < 0 else clampi(roundi(s / 60.0), 0, 100000)
		out[src] = vals
	out.battery = bool(r.get("battery", false))
	out.hibernate_ok = bool(r.get("hibernate_ok", false))
	out.can_set = bool(r.get("can_set", false))
	return out


## Auftrag für „power-time-set“, {} wenn etwas nicht aus den festen Listen stammt.
static func power_args(what: String, src: String, minutes: int) -> Dictionary:
	if not (what in POWER_WHAT) or not (src in POWER_SRC) or not (minutes in POWER_MINUTES):
		return {}
	return { "what": what, "src": src, "min": minutes }


static func minutes_text(m: int) -> String:
	if m < 0:
		return TranslationServer.translate("Unbekannt")
	if m == 0:
		return TranslationServer.translate("Nie")
	if m < 60:
		return TranslationServer.translate("%d Min.") % m
	if m == 60:
		return TranslationServer.translate("1 Stunde")
	if m % 60 == 0:
		return TranslationServer.translate("%d Stunden") % (m / 60)
	return TranslationServer.translate("%d Min.") % m


## Auswahl für eine Zeit: die feste Liste, dazu ein abweichender Wert aus Windows (nur zum Zeigen).
static func power_options(cur: int) -> Array:
	var opts: Array = []
	if cur > 0 and not (cur in POWER_MINUTES):
		opts.append([cur, minutes_text(cur)])
	for m in POWER_MINUTES:
		opts.append([m, minutes_text(m)])
	return opts


# --- Stand für den Doktor --------------------------------------------------------------------

## Aus den beiden Antworten: was der Doktor wissen muss (nur was sicher bekannt ist).
static func lage_from(wlan: Dictionary, bt: Dictionary) -> Dictionary:
	var out := {}
	if not wlan.is_empty() and str(wlan.get("state", "")) in ["ok", "aus", "zugriff"]:
		out["wlan"] = { "radio": str(wlan.radio), "internet": str(wlan.internet), "connected": str(wlan.connected) }
	if not bt.is_empty() and str(bt.get("state", "")) in ["an", "aus"]:
		out["bt"] = { "radio": str(bt.state), "paired": (bt.devices as Array).size() }
	return out


## WLAN und Bluetooth für den Doktor nachlesen (höchstens alle LAGE_MS, force: sofort). Nur lesen,
## ohne neue WLAN-Suche; in der Vorführung bleibt alles, wie es ist.
static func refresh_lage(force := false) -> void:
	if Library.demo or not Config.is_windows() or not Helper.available:
		return
	if not force and Time.get_ticks_msec() - _lage_ms < LAGE_MS:
		return
	_lage_ms = Time.get_ticks_msec()
	var w := await Helper.run("wlan-state", { "scan": 0 }, 10.0)
	var b := await Helper.run("bt-paired", {}, 12.0)
	lage = lage_from(parse_wlan(w.get("result")) if bool(w.get("ok", false)) else {},
		parse_bt(b.get("result")) if bool(b.get("ok", false)) else {})

extends RefCounted
## Dein Status in Steam am PC, gelesen aus Steams eigenen Dateien (nur lesend, nichts wird gemeldet).
##
## Ist Steam am PC angemeldet, gehört der Status der Steam-App. Uzais Sitzung am Chat-Server meldet
## bewusst keinen eigenen Status (sonst stand das ganze Konto offline, siehe SteamCM._send_status) –
## und so einer Sitzung nennt Steam den eigenen Status nicht verlässlich; auch die Web-API lehnt den
## Zugang der QR-Anmeldung ab. Folge beim Nutzer (0.16.0): „da steht immer noch offline“.
## Darum: Steam am PC angemeldet (Helfer: ActiveProcess\ActiveUser) → der Status, den die Steam-App
## gespeichert hat:
##   userdata/<Konto-ID>/config/localconfig.vdf
##     WebStorage → FriendStoreLocalPrefs_<Konto-ID> = {"ePersonaState":1,…} (JSON, neuer Client)
##     friends → PersonaStateDesired (älterer Client)
##   config/loginusers.vdf → <SteamID64> → WantsOfflineMode = 1: Steam läuft im Offline-Modus.
## Steht nirgends etwas, ist die Steam-App angemeldet und damit online.
## localconfig.vdf ist oft mehrere MB groß: Uzai sucht nur die zwei Schlüssel (vdf_value), statt die
## Datei zu zerlegen, und liest sie nur neu, wenn sie sich geändert hat.

const Fremd := preload("res://src/core/fremd.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

const STEAM64 := 76561197960265728
const LOCALCONFIG_MAX := 32 * 1024 * 1024
const LOGINUSERS_MAX := 1024 * 1024
const VALUE_MAX := 4096
const NAMES := { 0: "Offline", 1: "Online", 2: "Beschäftigt", 3: "Abwesend", 4: "Abwesend", 5: "Online", 6: "Online", 7: "Unsichtbar" }

static var _cache := {}         ## Pfad -> { mtime, state }


## Den Text-Wert nach "key" (ohne Groß/klein) in einer VDF-Datei ("" ohne oder bei einem Abschnitt).
## Versteht \" und \\ im Wert; höchstens VALUE_MAX Zeichen.
static func vdf_value(text: String, key: String) -> String:
	# Erst genau so, wie Steam den Schlüssel schreibt: Die Suche ohne Groß/klein ist in Godot ein Vielfaches
	# langsamer (gemessen 80 ms für 6 MB) und nur noch der Rückfall.
	var at := text.find("\"" + key + "\"")
	if at < 0:
		at = text.findn("\"" + key + "\"")
	if at < 0:
		return ""
	var i := at + key.length() + 2
	var n := text.length()
	while i < n and text[i] in [" ", "\t", "\r", "\n"]:
		i += 1
	if i >= n or text[i] != "\"":
		return ""
	i += 1
	var out := ""
	while i < n and text[i] != "\"":
		if text[i] == "\\" and i + 1 < n:
			out += text[i + 1]
			i += 2
		else:
			out += text[i]
			i += 1
		if out.length() > VALUE_MAX:
			return ""
	return out if i < n else ""


## Gespeicherter Status aus dem Text von localconfig.vdf (rein, getestet): EPersonaState 0–7,
## -1 = steht nicht drin.
static func persona_from_localconfig(text: String, acct: int) -> int:
	if acct > 0:
		var prefs := vdf_value(text, "FriendStoreLocalPrefs_%d" % acct)
		if prefs != "":
			var j: Variant = Fremd.json_roh(prefs)
			if j is Dictionary and ((j as Dictionary).get("ePersonaState") is float or (j as Dictionary).get("ePersonaState") is int):
				var st := int(j.ePersonaState)
				if st >= 0 and st <= 7:
					return st
	var desired := vdf_value(text, "PersonaStateDesired")
	if desired.is_valid_int() and int(desired) >= 0 and int(desired) <= 7:
		return int(desired)
	return -1


## Läuft Steam am PC für dieses Konto im Offline-Modus? Aus dem Text von loginusers.vdf (rein,
## getestet): im Abschnitt "<SteamID64>" { … "WantsOfflineMode" "1" … } – ohne die Datei zu zerlegen.
static func offline_mode(loginusers: String, sid64: String) -> bool:
	if not sid64.is_valid_int():
		return false
	var at := loginusers.find("\"" + sid64 + "\"")
	if at < 0:
		return false
	var open := loginusers.find("{", at)
	var close := loginusers.find("}", at)
	if open < 0 or close < open:
		return false
	return vdf_value(loginusers.substr(open, close - open), "WantsOfflineMode") == "1"


## Dein Status, wenn Steam am PC angemeldet ist: { state (EPersonaState), src (Quelle fürs Protokoll) }.
## root: Steam-Ordner, sid64: deine SteamID64. Mit await: Hat sich localconfig.vdf geändert, liest und durchsucht
## sie ein Hilfsfaden – die Datei ist oft mehrere MB groß (gemessen 170 ms bei 6 MB), Steam schreibt sie immer
## wieder neu, und Uzai sieht jede Minute nach. Im Hauptfaden stockte dabei das Menü.
static func pc_persona(root: String, sid64: String) -> Dictionary:
	var acct := 0
	if sid64.is_valid_int() and sid64.length() >= 16 and sid64.length() <= 20:
		acct = int(sid64) - STEAM64
	if root == "" or acct <= 0 or acct >= (1 << 32):
		return { "state": 1, "src": "Steam am PC angemeldet" }
	var lu := _read_text(root.path_join("config/loginusers.vdf"), LOGINUSERS_MAX)
	if lu != "" and offline_mode(lu, sid64):
		return { "state": 0, "src": "Steam am PC im Offline-Modus (loginusers.vdf)" }
	var path := root.path_join("userdata/%d/config/localconfig.vdf" % acct)
	var mt := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	var hit: Dictionary = _cache.get(path, {})
	var st := -1
	if mt > 0 and int(hit.get("mtime", -1)) == mt:
		st = int(hit.state)
	elif mt > 0:
		var v: Variant = await Arbeit.ergebnis(_status_aus_datei.bind(path, acct))
		st = int(v) if v is int else -1
		_cache[path] = { "mtime": mt, "state": st }
	if st >= 0:
		return { "state": st, "src": "Steam am PC, localconfig.vdf" }
	return { "state": 1, "src": "Steam am PC angemeldet" }


## Läuft im Hilfsfaden: rein, ohne Zustand.
static func _status_aus_datei(path: String, acct: int) -> int:
	return persona_from_localconfig(_read_text(path, LOCALCONFIG_MAX), acct)


static func name_of(st: int) -> String:
	return str(NAMES.get(st, "Status %d" % st))


static func _read_text(path: String, max_bytes: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_length()
	if n <= 0 or n > max_bytes:
		f.close()
		return ""
	var b := f.get_buffer(n)
	f.close()
	return b.get_string_from_utf8()

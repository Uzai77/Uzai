extends Node
## Lossless Scaling (Steam-App von THS): Bildverdopplung (Frame Generation) und Hochskalieren
## für jedes Spiel im Fenster- oder randlosen Modus. Uzai startet das Programm bei Bedarf,
## holt das Spiel nach vorn und drückt das Tastenkürzel von Lossless Scaling.
## Einschalten geht über den Guide oder automatisch beim Spielstart.

signal changed

const Logdatei := preload("res://src/core/logdatei.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const GameProfile := preload("res://src/core/game_profile.gd")
const HelperScript := preload("res://src/core/helper.gd")
const STEAM_REL := "steamapps/common/Lossless Scaling/LosslessScaling.exe"
const STEAM_APPID := "993090"
## Prozessname (ohne .exe). Danach sucht Uzai zuerst: Das geht ohne Rechte, auch wenn Lossless
## Scaling als Administrator läuft (dann ist sein Pfad für Uzai nicht lesbar).
const PROC_NAMES := ["LosslessScaling"]
## So lange wartet Uzai nach dem Start auf den Prozess: Lossless Scaling startet über Steam neu
## (Steam-Prüfung), beim ersten Mal nach einem Update dauert das gut 20 s.
const START_WAIT_S := 45.0
const HOTKEYS := [["CTRL+ALT+S", "Strg + Alt + S (Standard)"], ["ALT+S", "Alt + S"], ["CTRL+ALT+F", "Strg + Alt + F"], ["F12", "F12"],
		["SHIFT+F12", "Umschalt + F12"]]

static var _RX_KUERZEL := RegEx.create_from_string("<(?:Scale)?Hotkey>\\s*([^<]*?)\\s*</(?:Scale)?Hotkey>")
static var _RX_UMSCHALT := RegEx.create_from_string("<(?:Scale)?HotkeyModifier(?:Key)?s>\\s*([^<]*?)\\s*</(?:Scale)?HotkeyModifier(?:Key)?s>")
static var _RX_TRENNER := RegEx.create_from_string("[ ,|]+")
static var _RX_ZEICHEN := RegEx.create_from_string("^[A-Za-z0-9]$")
static var _RX_ZIFFER := RegEx.create_from_string("^D[0-9]$")
static var _RX_FTASTE := RegEx.create_from_string("^F([1-9]|1[0-9]|2[0-4])$")
static var _RX_NUMPAD := RegEx.create_from_string("^NumPad[0-9]$")

var active := false
var busy := false
var note := ""   ## Hinweis zum letzten Umschalten (nicht bestätigt), sonst leer
var _exe := ""
var _seen_overlay := false   ## das Bild von Lossless Scaling war schon einmal zu erkennen
var _t0 := 0   ## Beginn des laufenden Umschaltens (Zeiten im Protokoll)


func _ready() -> void:
	Launcher.started.connect(_on_game_started)
	Launcher.window_ready.connect(_on_game_window)
	Launcher.ended.connect(func(_g: Dictionary, _s: int) -> void:
		active = false
		changed.emit()
	)


func exe_path() -> String:
	var own := str(Config.get_value("lossless.exe", ""))
	if own != "" and FileAccess.file_exists(own):
		return own
	if _exe != "" and FileAccess.file_exists(_exe):
		return _exe
	var root := Library.steam_root()
	if root != "":
		for dir in SteamScanner.library_dirs(root):
			var p := str(dir).path_join(STEAM_REL)
			if FileAccess.file_exists(p):
				_exe = p
				return p
	return ""


func available() -> bool:
	return (Library.demo and Launcher.in_game) or (Config.is_windows() and exe_path() != "")


## Windows-Pfad ohne gemischte und doppelte Trenner. Uzai schickte früher
## „C:\\Program Files (x86)\…“ (aus „C:\/Program Files (x86)/…“) – das passte zu keinem
## Prozesspfad, Lossless Scaling galt deshalb immer als „läuft nicht“. UNC (\\server) bleibt.
static func win_path(p: String) -> String:
	var s := p.replace("/", "\\")
	var unc := s.begins_with("\\\\")
	while s.contains("\\\\"):
		s = s.replace("\\\\", "\\")
	if unc:
		s = "\\" + s
	return s


## Eingestelltes Kürzel (Einstellungen → Im Spiel → Bildrate ×2).
func hotkey() -> String:
	return str(Config.get_value("lossless.hotkey", "CTRL+ALT+S"))


## Das Kürzel, das Uzai drückt: das aus den Einstellungen von Lossless Scaling selbst, sonst das
## eingestellte. Zweiter Wert: woher es stammt (fürs Protokoll). Aus der fremden Datei nur ein
## Kürzel im engen Format, das der Helfer annimmt (Helper.global_keys_ok) – nie etwa Windows-Taste.
func effective_hotkey() -> Array:
	for p in settings_files():
		if FileAccess.file_exists(p):
			var k := parse_settings_hotkey(FileAccess.get_file_as_string(p))
			if k != "" and HelperScript.global_keys_ok(k):
				return [k, p]
	return [hotkey(), "Uzai-Einstellung"]


## Wo Lossless Scaling seine Einstellungen ablegt (%LOCALAPPDATA%\Lossless Scaling\Settings.xml,
## ältere Fassungen neben dem Programm).
func settings_files() -> PackedStringArray:
	var out := PackedStringArray()
	var la := OS.get_environment("LOCALAPPDATA")
	if la != "":
		out.append(la.replace("\\", "/").path_join("Lossless Scaling/Settings.xml"))
	var exe := exe_path()
	if exe != "":
		out.append(exe.replace("\\", "/").get_base_dir().path_join("Settings.xml"))
	return out


func hotkey_text() -> String:
	return key_text(str(effective_hotkey()[0]))


static func key_text(k: String) -> String:
	var names := { "CTRL": "Strg", "ALT": "Alt", "SHIFT": "Umschalt", "WIN": "Windows" }
	var parts := PackedStringArray()
	for p in k.split("+"):
		parts.append(str(names.get(p.strip_edges(), p.strip_edges())))
	return " + ".join(parts)


## Kürzel „Scale“ aus Settings.xml von Lossless Scaling (.NET-Serialisierung: <Hotkey>S</Hotkey>,
## <HotkeyModifierKeys>Alt Control</HotkeyModifierKeys>) in Uzais Schreibweise („CTRL+ALT+S“).
## "" = nicht gefunden oder unbekannte Taste (dann gilt die Uzai-Einstellung).
static func parse_settings_hotkey(xml: String) -> String:
	var m := _RX_KUERZEL.search(xml)
	if m == null:
		return ""
	var raw := m.get_string(1)
	var mods := PackedStringArray()
	var key := ""
	var tokens := PackedStringArray()
	if raw.contains("+"):
		tokens = raw.split("+", false)
		key = tokens[tokens.size() - 1].strip_edges()
		tokens.remove_at(tokens.size() - 1)
	else:
		key = raw
	var mm := _RX_UMSCHALT.search(xml)
	if mm == null and tokens.is_empty():
		return ""   # Umschalttasten unbekannt: lieber die Uzai-Einstellung als nur „S“
	if mm != null:
		for t in _RX_TRENNER.sub(mm.get_string(1), " ", true).split(" ", false):
			tokens.append(t)
	var seen := {}
	for t in tokens:
		var n := str(
				{ "control": "CTRL", "ctrl": "CTRL", "strg": "CTRL", "alt": "ALT", "shift": "SHIFT", "windows": "WIN", "win": "WIN" }.get(t.strip_edges().to_lower(), ""))
		if n == "" and t.strip_edges().to_lower() != "none":
			return ""
		if n != "":
			seen[n] = true
	for n in ["CTRL", "ALT", "SHIFT", "WIN"]:
		if seen.has(n):
			mods.append(n)
	var k := _wpf_key(key)
	if k == "":
		return ""
	mods.append(k)
	return "+".join(mods)


## WPF-Tastenname (System.Windows.Input.Key) → Uzais Name (Helfer: Parse-Keys).
static func _wpf_key(k: String) -> String:
	var s := k.strip_edges()
	if s.length() == 1 and _RX_ZEICHEN.search(s) != null:
		return s.to_upper()
	if _RX_ZIFFER.search(s) != null:
		return s.substr(1)
	if _RX_FTASTE.search(s) != null:
		return s
	if _RX_NUMPAD.search(s) != null:
		return "NUM" + s.substr(6)
	return str({ "Space": "SPACE", "Tab": "TAB", "Return": "ENTER", "Enter": "ENTER", "Escape": "ESC", "Insert": "INS", "Delete": "DEL",
		"Home": "HOME", "End": "END", "PageUp": "PGUP", "Prior": "PGUP", "PageDown": "PGDN", "Next": "PGDN", "Up": "UP", "Down": "DOWN",
		"Left": "LEFT", "Right": "RIGHT", "Pause": "PAUSE", "Scroll": "SCROLL", "Back": "BACKSPACE", "PrintScreen": "PRTSC", "Snapshot": "PRTSC" }.get(s, ""))


## Zustand von Lossless Scaling über den Helfer (Befehl „lossless“): { procs: [{pid, name, level,
## by, path}], windows: [...], self_level, ms } oder { error }. Prozesse nach Namen und nach Ordner.
func _ls_state() -> Dictionary:
	if not Helper.available:
		return { "error": "Helfer nicht bereit" }
	var exe := exe_path()
	var t := Time.get_ticks_msec()
	var r := await Helper.run("lossless", { "dir": win_path(exe.get_base_dir()) if exe != "" else "", "names": PROC_NAMES }, 8.0)
	var st: Dictionary = (r.result as Dictionary).duplicate() if r.ok and r.result is Dictionary else { "error": str(r.get("error", "keine Antwort")) }
	st["wait_ms"] = Time.get_ticks_msec() - t
	return st


static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return [v]
	return []


static func running(st: Dictionary) -> bool:
	return not _arr(st.get("procs", [])).is_empty()


## Rechte von Lossless Scaling: 1 = Administrator, 0 = nicht, -1 = unbekannt.
static func ls_level(st: Dictionary) -> int:
	var lv := -1
	for p in _arr(st.get("procs", [])):
		lv = maxi(lv, int((p as Dictionary).get("level", -1)))
	return lv


## Liegt das Bild von Lossless Scaling über dem Spiel? Ein Fenster deckt den ganzen Bildschirm
## und liegt immer oben oder ist durchklickbar (so zeichnet Lossless Scaling das skalierte Bild).
static func overlay_in(windows: Variant) -> bool:
	for w in _arr(windows):
		var d: Dictionary = w
		if bool(d.get("full", false)) and (bool(d.get("topmost", false)) or bool(d.get("clickthrough", false))) and int(d.get("w", 0)) > 0 and int(d.get("h", 0)) > 0:
			return true
	return false


## Eine Zeile fürs Protokoll: Prozesse (Nummer, Name, gefunden über, Admin) und Fenster.
static func state_text(st: Dictionary) -> String:
	if st.has("error"):
		return "Abfrage ging nicht (%s)" % str(st.error)
	var procs := _arr(st.get("procs", []))
	if procs.is_empty():
		return "läuft nicht (kein Prozess %s, auch nicht im Programmordner)" % "/".join(PROC_NAMES)
	var parts := PackedStringArray()
	for p in procs:
		var d: Dictionary = p
		parts.append(
				"%s %s über %s, Admin %s" % [str(d.get("name", "")), str(d.get("pid", "")), str(d.get("by", "")),
				{ 1: "ja", 0: "nein" }.get(int(d.get("level", -1)), "unbekannt")])
	var wins := _windows_text(st)
	return "läuft: %s; Fenster: %s%s; Uzai-Helfer Admin %s; Abfrage %s ms" % [", ".join(parts), wins, " (nur im Infobereich)" if wins == "keine" else "",
		{ 1: "ja", 0: "nein" }.get(int(st.get("self_level", -1)), "unbekannt"), str(st.get("ms", "?"))]


## Was am Startversuch nicht stimmt, als Satz ("" = gestartet, jetzt warten).
static func start_problem(r: Dictionary) -> String:
	if not bool(r.get("ok", false)):
		return "Uzai konnte Lossless Scaling nicht starten: " + HelperScript.klartext(str(r.get("error", "")), "Einmal von Hand starten – läuft es, übernimmt Uzai.")
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	if bool(res.get("missing", false)):
		return "Lossless Scaling wurde nicht gefunden. Unter Einstellungen → Im Spiel → Bildrate ×2 den Pfad wählen."
	if bool(res.get("elevation", false)):
		return "Lossless Scaling braucht Administratorrechte. Einmal von Hand starten."
	if not bool(res.get("started", false)):
		return "Lossless Scaling startet nicht. Einmal von Hand starten."
	return ""


## Ergebnis nach dem Tastendruck: { active, err, note, result }. Der Blick auf die Fenster ist
## nur ein Hinweis – nicht zu sehen heißt nicht „ging nicht“ (Lossless Scaling kann sein Bild
## anders zeigen). Deshalb beim Einschalten nie ein Fehler, nur ein Hinweis mit der
## wahrscheinlichsten Ursache. Sicher ist nur: Das Bild ist nach „aus“ noch da.
static func decide(want_on: bool, on_after: bool, seen_overlay: bool, level: int, self_level: int, key_txt: String) -> Dictionary:
	if on_after == want_on:
		return { "active": want_on, "err": "", "note": "", "result": "bestätigt" }
	if not want_on:
		return { "active": true, "err": "Lossless Scaling ist noch an – Kürzel %s kam nicht an. Im Guide nochmal versuchen." % key_txt, "note": "",
				"result": "noch an" }
	var n := ""
	if level == 1 and self_level != 1:
		n = "Kürzel %s gedrückt, aber das Bild von Lossless Scaling ist nicht zu sehen. Lossless Scaling läuft als Administrator, Uzai nicht – Windows kann Uzais Tastendruck dann verwerfen. Lossless Scaling ohne Administratorrechte starten oder Uzai auch als Administrator." % key_txt
	elif seen_overlay:
		n = "Kürzel %s gedrückt, das Bild von Lossless Scaling ist aber nicht zu sehen. Im Spiel bzw. Emulator Vollbild „randlos“ statt exklusiv wählen und in Lossless Scaling das Kürzel „Scale“ prüfen." % key_txt
	else:
		n = "Kürzel %s gedrückt. Bleibt das Bild gleich: im Spiel bzw. Emulator Vollbild „randlos“ wählen (exklusives Vollbild greift Lossless Scaling nicht ab) und in Lossless Scaling das Kürzel „Scale“ prüfen." % key_txt
	return { "active": true, "err": "", "note": n, "result": "nicht bestätigt" }


## Läuft Lossless Scaling? Sonst starten (nie ein zweites Mal) und bis zu START_WAIT_S warten.
## Gibt "" oder eine Fehlermeldung zurück.
func _ensure_running() -> String:
	var st := await _ls_state()
	_log("Prüfung: %s" % state_text(st))
	if st.has("error"):
		# Nicht wissen ist nicht „läuft nicht“: sonst startete Uzai ein zweites Mal.
		return "Uzai kann gerade nicht nachsehen, ob Lossless Scaling läuft (Helfer: %s). Im Guide nochmal versuchen." % str(st.error)
	if running(st):
		return ""
	var exe := exe_path()
	if exe == "":
		return "Lossless Scaling läuft nicht und wurde nicht gefunden. Unter Einstellungen → Im Spiel → Bildrate ×2 den Pfad wählen."
	_log("starte %s" % win_path(exe))
	var r := await Helper.run("lossless-start", { "exe": win_path(exe), "steam": STEAM_APPID if exe.to_lower().contains("steamapps") else "" }, 10.0)
	_log("Start: %s" % (JSON.stringify(r.result) if r.ok else "Helfer: " + str(r.get("error", ""))))
	var p := start_problem(r)
	if p != "":
		return p
	Toasts.show_toast("Lossless Scaling startet …", "Uzai wartet, bis es bereit ist (bis zu %d s)." % int(START_WAIT_S), "bolt",
			{ "tag": "lossless-start", "ms": START_WAIT_S * 1000.0, "overlay": true, "quiet": true })
	var t := Time.get_ticks_msec()
	var last_log := 0
	while Time.get_ticks_msec() - t < START_WAIT_S * 1000.0:
		await get_tree().create_timer(0.5).timeout
		st = await _ls_state()
		if running(st):
			_log("läuft nach %.1f s: %s" % [(Time.get_ticks_msec() - t) / 1000.0, state_text(st)])
			# Lossless Scaling braucht nach dem Start einen Moment, bis das Tastenkürzel greift.
			await get_tree().create_timer(3.0).timeout
			Toasts.dismiss("lossless-start")
			return ""
		if Time.get_ticks_msec() - last_log > 5000:
			last_log = Time.get_ticks_msec()
			_log("warte (%.1f s): %s" % [(Time.get_ticks_msec() - t) / 1000.0, state_text(st)])
	Toasts.dismiss("lossless-start")
	_log("nach %d s kein Prozess" % int(START_WAIT_S))
	return "Lossless Scaling nach %d s nicht bereit. Einmal von Hand starten." % int(START_WAIT_S)


## Läufe von toggle, die gerade unterwegs sind (siehe dort).
var _toggle_offen := 0


## Schaltet Lossless Scaling für das laufende Spiel um. Gibt "" oder eine Fehlermeldung zurück.
## Ablauf: Lossless Scaling starten (falls nötig), warten, bis Uzai aus dem Weg ist, das Spiel
## nach vorn holen und nur dann das Kürzel drücken, wenn das Spiel wirklich vorn liegt (Lossless
## Scaling skaliert das Vordergrundfenster – sonst traf es Uzai oder den Desktop). Danach nachsehen,
## ob Lossless Scaling sein Bild zeigt. Alles mit Zeiten in logs/lossless.log.
func toggle() -> String:
	_toggle_offen += 1
	var ergebnis: String = await _toggle_lauf()
	_toggle_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und toggle täte bis zum Neustart nichts mehr.
	if _toggle_offen == 0 and busy:
		busy = false
	return ergebnis


func _toggle_lauf() -> String:
	note = ""
	if busy:
		return "Einen Moment …"
	if Library.demo:
		active = not active
		changed.emit()
		return ""
	if not Launcher.in_game:
		return "Es läuft gerade kein Spiel."
	busy = true
	_t0 = Time.get_ticks_msec()
	var err := await _toggle()
	if err != "":
		_log("Ergebnis: Fehler – " + err)
	_t0 = 0
	busy = false
	changed.emit()
	return err


func _toggle() -> String:
	var want_on := not active
	var title := str(Launcher.current.get("title", ""))
	var hk := effective_hotkey()
	var key := str(hk[0])
	_log("— %s: %s (Kürzel %s aus %s)" % [title, "einschalten" if want_on else "ausschalten", key, str(hk[1])])
	if key != hotkey():
		_log("Hinweis: Uzai-Einstellung ist %s, Lossless Scaling selbst hat %s – Uzai nimmt %s" % [hotkey(), key, key])
	var err := await _ensure_running()
	if err != "":
		return err
	if want_on and Launcher.filter_active() and str(Config.get_value("lossless.filter", "aus")) == "aus":
		# Zwei Programme, die dasselbe Bild abgreifen, vertragen sich schlecht.
		await Launcher.toggle_filter()
		Toasts.show_toast("Bildfilter aus", "Lossless Scaling übernimmt das Bild.", "tv")
	await Launcher.wait_uzai_away()
	var before := await _ls_state()
	var on_before := overlay_in(before.get("windows", []))
	_log("vorher: Bild von Lossless Scaling %s; %s" % ["da" if on_before else "nicht da", state_text(before)])
	if on_before:
		_seen_overlay = true
	# Schon im gewünschten Zustand (z. B. von Hand umgeschaltet): nicht drücken, sonst wäre es danach falsch herum.
	if _seen_overlay and on_before == want_on:
		active = want_on
		_log("schon %s – nichts gedrückt" % ("an" if want_on else "aus"))
		return ""
	if not HelperScript.global_keys_ok(key):
		_log("nicht gedrückt: Kürzel %s ist nicht erlaubt" % key)
		return key_problem({ "ok": true, "result": { "sent": false, "reason": "nicht erlaubt" } }, key)
	var pids := await Launcher.game_pids()
	var args := { "pids": pids, "keys": key, "global": true, "require_focus": true }
	if Launcher.game_hwnd() != 0:
		args["hwnd"] = Launcher.game_hwnd()
	_log("Spiel: Prozesse %s, Fenster %s" % [str(pids), str(Launcher.game_hwnd())])
	if pids.is_empty() and Launcher.game_hwnd() == 0:
		return "Spielfenster nicht gefunden. Im Spiel „Randlos“ oder „Fenster“ wählen."
	var r := await Helper.run("keys", args, 8.0)
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	_log("Kürzel %s → Fenster „%s“ (Prozess %s, vorn geholt: %s), vorn: „%s“ (%s, Prozess %s, Admin %s/Uzai %s), angenommen %s von %s, danach vorn: „%s“" % [
		key, str(res.get("window", "")), str(res.get("target_pid", "")), str(res.get("focused", "")), str(res.get("foreground", "")),
			str(res.get("foreground_class", "")),
		str(res.get("foreground_pid", "")), str(res.get("foreground_elevated", "")), str(res.get("self_elevated", "")), str(res.get("accepted", "")),
			str(res.get("expected", "")), str(res.get("foreground_after", ""))])
	var problem := key_problem(r, key)
	if problem != "":
		_log("nicht gedrückt: " + problem)
		return problem
	await get_tree().create_timer(1.5).timeout
	var after := await _ls_state()
	var on_after := overlay_in(after.get("windows", []))
	_log("nachher: Bild von Lossless Scaling %s; %s" % ["da" if on_after else "nicht da", state_text(after)])
	if on_after:
		_seen_overlay = true
	var self_level := int(after.get("self_level", -1))
	if self_level < 0 and res.has("self_elevated"):
		self_level = 1 if bool(res.self_elevated) else 0
	var d := decide(want_on, on_after, _seen_overlay, ls_level(after), self_level, key_text(key))
	active = bool(d.active)
	note = str(d.note)
	_log("Ergebnis: %s%s" % [str(d.result), (" – " + note) if note != "" else ""])
	return str(d.err)


## Was am Ergebnis des Tastendrucks nicht stimmt, als Satz ("" = gedrückt).
static func key_problem(r: Dictionary, keys: String) -> String:
	if not bool(r.get("ok", false)):
		return "Das Tastenkürzel ließ sich nicht senden (%s)." % str(r.get("error", "keine Antwort"))
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	match str(res.get("reason", "")):
		"unbekannt":
			return "Uzai versteht „%s“ im Kürzel %s nicht." % [", ".join(PackedStringArray(res.get("unknown", []))), keys]
		"nicht vorn":
			if str(res.get("window", "")) == "":
				return "Kein Spielfenster gefunden."
			return "Windows hat das Spiel nicht nach vorn gelassen – das Kürzel hätte das falsche Fenster getroffen. Im Guide nochmal versuchen."
		"nicht erlaubt":
			return "Das Kürzel %s nimmt Uzai nicht: erlaubt sind Strg, Alt und Umschalt mit einer Taste A–Z, 0–9 oder F1–F24, ohne Windows-Taste. In den Einstellungen bei „Bildrate ×2“ ein anderes wählen." % keys
		"geschützt":
			return "Sicherheitsfenster von Windows im Vordergrund."
		"zu oft":
			return "Gerade erst gedrückt – einen Moment warten und nochmal versuchen."
	if bool(res.get("foreground_elevated", false)) and not bool(res.get("self_elevated", false)):
		return "Das Spiel läuft mit Administratorrechten. Tasten kommen nicht an."
	return ""


static func _windows_text(st: Dictionary) -> String:
	var parts := PackedStringArray()
	for w in _arr(st.get("windows", [])):
		var d: Dictionary = w
		parts.append(
				"%s „%s“ %sx%s%s%s%s" % [str(d.get("class", "")), str(d.get("title", "")), str(d.get("w", 0)), str(d.get("h", 0)), " oben" if bool(d.get("topmost", false))
				else "",
			" Vollbild" if bool(d.get("full", false)) else "", " durchklickbar" if bool(d.get("clickthrough", false)) else ""])
	return ", ".join(parts) if not parts.is_empty() else "keine"


func _wants_auto(g: Dictionary) -> bool:
	var own := str(g.get("lossless", ""))
	if own == "":
		# Vorlage des Systems (Spiel-Profile, z. B. alle PS2-Spiele)
		own = str(GameProfile.template_for(g).get("lossless", ""))
	if own != "":
		return own == "an"
	match str(Config.get_value("lossless.auto", "aus")):
		"alle": return true
		"pc": return str(g.get("source", "")) in ["steam", "epic", "ea", "pc"] or Library.Stores.is_extra(str(g.get("source", "")))
		"emu": return str(g.get("source", "")) == "rom"
	return false


func _on_game_started(_g: Dictionary) -> void:
	active = false
	changed.emit()


## Automatisch einschalten, wenn das Spielfenster vorn ist (Launcher.window_ready kommt erst, wenn
## das Spiel vorn liegt, meist schon im Vollbild) und die eingestellte Zeit um ist. Ist dann der
## Guide offen, wartet Uzai, bis er zu ist – das Kürzel muss das Spiel treffen.
func _on_game_window(g: Dictionary) -> void:
	if not Config.is_windows() or exe_path() == "" or not _wants_auto(g):
		return
	var gid := str(g.get("id", ""))
	await get_tree().create_timer(float(Config.get_value("lossless.delay", 8.0))).timeout
	var t0 := Time.get_ticks_msec()
	while Launcher.guide_open and Launcher.in_game and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().create_timer(0.5).timeout
	if Launcher.guide_open:
		return
	if Launcher.in_game and str(Launcher.current.get("id", "")) == gid and not active:
		var err := await toggle()
		if err == "" and not active:
			return
		Toasts.show_toast("Lossless Scaling " + ("an" if err == "" else "nicht aktiv"), err if err != "" else (note if note != "" else hotkey_text()), "bolt",
				{ "ms": 7000 if err != "" or note != "" else 3000 })


## Protokoll (logs/lossless.log): jeder Schritt, beim Umschalten mit Millisekunden seit Beginn.
func _log(text: String) -> void:
	var at := (" +%5d ms" % (Time.get_ticks_msec() - _t0)) if _t0 > 0 else ""
	Logdatei.zeile(Config.path("logs/lossless.log"), text, 200000, at)

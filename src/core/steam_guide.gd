extends RefCounted
## Turns off Steam's Guide button so that it opens only Uzai and not Big Picture as well, which would
## otherwise collide with Uzai. Steam stores "Guide button focuses Steam" per account in
##   userdata/<account-id>/config/localconfig.vdf → UserLocalConfigStore → "Controller_CheckGuideButton"
## ("0" means off; a missing entry means on).
##
## Uzai changes only this one value: the file is parsed (strings, escapes and braces respected), the
## key is looked up at the top level, and its value is replaced or the line is inserted right after the
## opening brace. Everything else stays byte-for-byte identical. If anything does not match the known
## structure (comments, unquoted words, duplicate key, not pure UTF-8), Uzai writes nothing.
## Steam rewrites the file when it exits, so this only works while Steam is closed. If Steam is running
## and a restart is allowed, Uzai shuts it down with Steam's own command (steam://exit) and then starts
## it again silently. Before the first change, a backup (.uzai-sicherung) is placed next to the file.

const KEY := "Controller_CheckGuideButton"
const ROOT := "UserLocalConfigStore"
const MAX_BYTES := 32 * 1024 * 1024
const SICHERUNG := ".uzai-sicherung"
const NEU := ".uzai-neu"
const EXIT_WAIT_MS := 45000
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

static var _busy := false


# --- Rein (getestet) -------------------------------------------------------------------------

## Wo der Wert steht: { ok, wert, von, bis, klammer }. ok: Aufbau verstanden. von/bis: Lage des Werts
## (ohne Anführungszeichen), -1 ohne Eintrag. klammer: Stelle direkt hinter "{" des Wurzelabschnitts.
static func lage(text: String) -> Dictionary:
	var out := { "ok": false, "wert": "", "von": -1, "bis": -1, "klammer": -1 }
	var n := text.length()
	var i := 0
	var depth := 0
	var want_key := true
	var key_von := -1
	var key_bis := -1
	var root_done := false
	while true:
		var q := text.find("\"", i)
		var seg := text.substr(i, (q if q >= 0 else n) - i)
		# Zwischen zwei Zeichenketten: nur Leerraum und Klammern – "}" beliebig oft oder ein "{".
		var opens := seg.count("{")
		var closes := seg.count("}")
		if opens > 1 or (opens == 1 and closes > 0):
			return out
		if opens + closes > 0 and not seg.replace("{", "").replace("}", "").strip_edges().is_empty():
			return out
		if opens + closes == 0 and not seg.strip_edges().is_empty():
			return out
		if opens == 1:
			if want_key:
				return out
			if depth == 0:
				if root_done or text.substr(key_von, key_bis - key_von).nocasecmp_to(ROOT) != 0:
					return out
				out.klammer = i + seg.find("{") + 1
			depth += 1
			want_key = true
		for _c in closes:
			if not want_key or depth == 0:
				return out
			depth -= 1
			if depth == 0:
				root_done = true
		if q < 0:
			break
		var e := _string_end(text, q)
		if e < 0:
			return out
		if want_key:
			if depth == 0 and root_done:
				return out
			key_von = q + 1
			key_bis = e
			want_key = false
		else:
			if depth == 0:
				return out
			if depth == 1 and text.substr(key_von, key_bis - key_von).nocasecmp_to(KEY) == 0:
				if out.von >= 0:
					return out
				out.von = q + 1
				out.bis = e
				out.wert = text.substr(q + 1, e - q - 1)
			want_key = true
		i = e + 1
	out.ok = root_done and depth == 0 and want_key
	return out


## Stelle des schließenden Anführungszeichens zur Zeichenkette ab q; -1 ohne. \" gehört zum Inhalt
## (davor eine ungerade Zahl Backslashes).
static func _string_end(text: String, q: int) -> int:
	var j := text.find("\"", q + 1)
	while j >= 0:
		var k := j - 1
		while k > q and text.unicode_at(k) == 92:
			k -= 1
		if (j - 1 - k) % 2 == 0:
			return j
		j = text.find("\"", j + 1)
	return -1


## Der Text mit KEY = wert ("0" oder "1"); unverändert, wenn es schon so ist (fehlt der Eintrag,
## gilt Steams Standard „an“). "" bei unbekanntem Aufbau.
static func mit_wert(text: String, wert: String) -> String:
	if not (wert in ["0", "1"]):
		return ""
	var l := lage(text)
	if not bool(l.ok):
		return ""
	if int(l.von) >= 0:
		if str(l.wert) == wert:
			return text
		return text.substr(0, int(l.von)) + wert + text.substr(int(l.bis))
	if wert == "1":
		return text
	var at := int(l.klammer)
	var nl := "\r\n" if text.substr(at, 2) == "\r\n" else "\n"
	return text.substr(0, at) + nl + "\t\"%s\"\t\t\"%s\"" % [KEY, wert] + text.substr(at)


## Ist die Guide-Taste in diesem Text für Steam aus? null: Aufbau unbekannt.
static func aus_in(text: String) -> Variant:
	# Schnell: so schreibt Steam die Zeile selbst (eine Ebene tief, Tabulatoren).
	if text.find("\n\t\"%s\"\t\t\"0\"" % KEY) >= 0:
		return true
	# Fehlt der Schlüssel ganz oder steht Steams eigene Zeile auf 1: an (ohne die Datei zu zerlegen).
	if text.findn("\"%s\"" % KEY) < 0 or text.find("\n\t\"%s\"\t\t\"1\"" % KEY) >= 0:
		return false
	var l := lage(text)
	if not bool(l.ok):
		return null
	return int(l.von) >= 0 and str(l.wert) == "0"


# --- Dateien ---------------------------------------------------------------------------------

## localconfig.vdf aller Konten auf diesem PC (Ordnernamen nur aus Ziffern).
static func dateien(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	if root == "":
		return out
	var ud := root.path_join("userdata")
	if not DirAccess.dir_exists_absolute(ud):
		return out
	for d in DirAccess.get_directories_at(ud):
		if d.length() > 10 or not d.is_valid_int() or str(int(d)) != d or int(d) <= 0:
			continue
		var p := ud.path_join(d).path_join("config/localconfig.vdf")
		if FileAccess.file_exists(p):
			out.append(p)
	return out


## Text einer Datei, nur wenn sie sich unverändert zurückschreiben ließe (reines UTF-8); sonst "".
static func _lesen(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var n := f.get_length()
	if n <= 0 or n > MAX_BYTES:
		f.close()
		return []
	var raw := f.get_buffer(n)
	f.close()
	if raw.size() != n:
		return []
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw:
		return []
	return [text, raw]


## Steht die Guide-Taste in dieser Datei schon auf aus? null: nicht lesbar oder Aufbau unbekannt.
static func datei_aus(path: String) -> Variant:
	var r := _lesen(path)
	return aus_in(str(r[0])) if not r.is_empty() else null


## Eine Datei auf wert stellen: "geändert", "schon", "fremd" (unbekannter Aufbau, nichts
## geschrieben) oder "fehler" (Lesen/Schreiben ging nicht, die Datei ist wie vorher).
static func datei_stellen(path: String, wert: String) -> String:
	var r := _lesen(path)
	if r.is_empty():
		return "fremd" if FileAccess.file_exists(path) else "fehler"
	var text: String = r[0]
	var raw: PackedByteArray = r[1]
	var neu := mit_wert(text, wert)
	if neu == "":
		return "fremd"
	if neu == text:
		return "schon"
	var bytes := neu.to_utf8_buffer()
	# Sicherung vom Stand vor Uzais erster Änderung (eine vorhandene bleibt).
	if not FileAccess.file_exists(path + SICHERUNG) and not _schreiben(path + SICHERUNG, raw):
		return "fehler"
	var tmp := path + NEU
	if not _schreiben(tmp, bytes):
		DirAccess.remove_absolute(tmp)
		return "fehler"
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		# Unter Windows ersetzt Godot per Löschen und Umbenennen: fehlt die Datei, alter Stand zurück.
		if not FileAccess.file_exists(path):
			_schreiben(path, raw)
		return "fehler"
	return "geändert"


## Schreiben und zurücklesen: steht genau das drin?
static func _schreiben(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	var ok := f.get_error() == OK
	f.close()
	return ok and FileAccess.get_file_as_bytes(path) == bytes


# --- Mit Steam -------------------------------------------------------------------------------

## Steam-Ordner: aus dem Einlesen der Bibliothek, sonst wie dort gesucht.
static func wurzel() -> String:
	if Library.steam_root() != "":
		return Library.steam_root()
	var reg := ""
	if Config.is_windows() and Helper.available:
		var r := await Helper.run("steam-path")
		if r.ok and r.result is Dictionary:
			reg = str(r.result.get("path", ""))
	return SteamScanner.find_root(str(Config.get_value("library.steam_dir", "")), reg)


## Steht die Guide-Taste in allen Konten auf aus? true, false oder null (kein Steam / unbekannt).
static func stand() -> Variant:
	var files := dateien(await wurzel())
	if files.is_empty():
		return null
	var alle := true
	for p in files:
		# localconfig.vdf ist oft mehrere MB groß. Gemessen bei 6 MB: Lesen und Prüfen 33 ms, die Suche nach dem
		# Schlüssel bis 80 ms, das Zerlegen (seltener Aufbau) 300 ms – im Hauptfaden stockte die Seite beim Öffnen.
		var a: Variant = await Arbeit.ergebnis(datei_aus.bind(p))
		if a == null:
			return null
		alle = alle and bool(a)
	return alle


## Warum es nicht ging, als kurzer Satz.
static func grund_text(grund: String) -> String:
	match grund:
		"kein_steam":
			return "Steam ist auf diesem PC nicht eingerichtet."
		"steam_laeuft":
			return "Steam hat sich nicht beendet. Später noch einmal versuchen."
		"spiel":
			return "Erst nach dem Spiel oder Download."
		"fremd":
			return "Steams Einstellungsdatei sieht anders aus. Nichts geändert."
	return "Steams Einstellungsdatei ließ sich nicht schreiben."


static func _steam_laeuft() -> bool:
	var r := await Helper.run("steam-state", {}, 4.0)
	return r.ok and r.result is Dictionary and bool(r.result.get("running", false))


## Für alle Konten stellen: aus = true heißt Guide-Taste nur für Uzai. neustart: läuft Steam, darf
## Uzai es kurz beenden und danach still neu starten. { ok, geaendert, grund } – grund: "kein_steam",
## "steam_laeuft", "spiel", "fremd", "fehler", "laeuft_schon".
static func stellen(tree: SceneTree, aus: bool, neustart: bool) -> Dictionary:
	if _busy:
		return { "ok": false, "geaendert": 0, "grund": "laeuft_schon" }
	if not Config.is_windows() or not Helper.available:
		return { "ok": false, "geaendert": 0, "grund": "kein_steam" }
	_busy = true
	var res := await _stellen(tree, "0" if aus else "1", neustart)
	_busy = false
	if int(res.geaendert) > 0 or str(res.grund) not in ["", "kein_steam"]:
		Launcher.log_launch("Steam: Guide-Taste %s – %d Datei(en) geändert%s" % ["aus" if aus else "an",
				int(res.geaendert), (", " + str(res.grund)) if str(res.grund) != "" else ""])
	return res


static func _stellen(tree: SceneTree, wert: String, neustart: bool) -> Dictionary:
	var files := dateien(await wurzel())
	if files.is_empty():
		return { "ok": false, "geaendert": 0, "grund": "kein_steam" }
	var offen := PackedStringArray()
	for p in files:
		var a: Variant = await Arbeit.ergebnis(datei_aus.bind(p))
		if a == null:
			return { "ok": false, "geaendert": 0, "grund": "fremd" }
		if bool(a) != (wert == "0"):
			offen.append(p)
	if offen.is_empty():
		return { "ok": true, "geaendert": 0, "grund": "" }
	var beendet := false
	var lief := await _steam_laeuft()
	if lief:
		if not neustart:
			return { "ok": false, "geaendert": 0, "grund": "steam_laeuft" }
		if Launcher.in_game or Installs.active_count() > 0:
			return { "ok": false, "geaendert": 0, "grund": "spiel" }
		OS.shell_open("steam://exit")
		var t0 := Time.get_ticks_msec()
		while lief and Time.get_ticks_msec() - t0 < EXIT_WAIT_MS:
			await tree.create_timer(1.0).timeout
			lief = await _steam_laeuft()
		if lief:
			return { "ok": false, "geaendert": 0, "grund": "steam_laeuft" }
		beendet = true
		# Steam schreibt beim Beenden zuletzt seine Dateien; kurz Luft lassen.
		await tree.create_timer(2.0).timeout
	var n := 0
	var grund := ""
	for p in offen:
		# Auch das Schreiben im Hilfsfaden (Zerlegen, Sicherung, Zurücklesen). Kommt nichts zurück: Fehler.
		var rv: Variant = await Arbeit.ergebnis(datei_stellen.bind(p, wert))
		var r := str(rv) if rv is String else "fehler"
		if r == "geändert":
			n += 1
		elif r != "schon" and grund == "":
			grund = r
	if beendet:
		await Helper.run("steam-silent", {}, 6.0)
	return { "ok": grund == "", "geaendert": n, "grund": grund }


## On startup: by default the Guide button belongs to Uzai, without having to turn anything on first. Once per
## installation Uzai turns Steam's handling off, even if Steam has to restart briefly for that,
## and remembers it (controller.steam_guide_standard). After that, whatever is set under Einstellungen › Controller
## applies: anyone who turns it back on there keeps it. If it did not work right now (a game or download is running,
## Steam does not exit), Uzai tries again on the next start.
## Before that, Uzai explains once what will happen, so users know the Steam button is switched off automatically.
## Otherwise Steam would quit without a word, and afterwards the button no longer opens Big Picture, even without
## Uzai. fragen(steam_laeuft) shows this (main._steam_guide_fragen) and returns "ja" (Verstanden), "nein" (Steam
## behalten) or "" (dismissed: ask again on the next start).
static func beim_start(tree: SceneTree, fragen := Callable()) -> void:
	if Library.demo or not Config.is_windows():
		return
	if bool(Config.get_value("controller.steam_guide_standard", false)):
		await nachziehen(tree)
		return
	var aus: Variant = await stand()
	if aus == null:
		return
	var wahl := "ja"
	if not bool(aus) and fragen.is_valid():
		wahl = str(await fragen.call(await _steam_laeuft()))
		# Inzwischen umgestellt (Einrichtung, Einstellungen)? Dann gilt das.
		aus = await stand()
		if aus == null:
			return
	match entscheidung(aus, wahl):
		"behalten":
			Config.set_value("controller.steam_guide_aus", false)
			Config.set_value("controller.steam_guide_standard", true)
			Launcher.log_launch("Steam: Guide-Taste bleibt bei Steam (beim Start so gewählt)")
			return
		"spaeter":
			return
	var res := { "ok": true, "geaendert": 0, "grund": "" }
	if not bool(aus):
		res = await stellen(tree, true, true)
	if bool(res.ok):
		Config.set_value("controller.steam_guide_aus", true)
		Config.set_value("controller.steam_guide_standard", true)
		if int(res.geaendert) > 0:
			Toasts.show_toast("Steams Guide-Taste ist aus", "Sie öffnet nur noch Uzai, auch ohne Uzai. Zurück: Einstellungen › Controller.", "controller")
	elif str(res.grund) in ["fremd", "fehler"]:
		# Steams Datei sieht anders aus oder lässt sich nicht schreiben: nicht bei jedem Start wieder versuchen.
		Config.set_value("controller.steam_guide_standard", true)


## Was beim Start zu tun ist: aus (Stand: true/false), wahl aus der Frage. "nichts" (steht schon aus – nur merken),
## "stellen", "behalten" (Steam behält die Taste, nie wieder fragen), "spaeter" (weggedrückt). Rein, getestet.
static func entscheidung(aus: Variant, wahl: String) -> String:
	if aus is bool and aus:
		return "nichts"
	match wahl:
		"ja":
			return "stellen"
		"nein":
			return "behalten"
	return "spaeter"


## Der Dialog vor dem Abschalten: Titel und Text (zwei ganze Sätze, damit sie sich übersetzen lassen).
const FRAGE_TITEL := "Die Guide-Taste gehört Uzai"
static func frage_text(steam_laeuft: bool) -> String:
	if steam_laeuft:
		return "Damit sie nicht zusätzlich Steam Big Picture öffnet, schaltet Uzai Steams Guide-Taste ab – Steam startet dafür kurz neu. Das gilt auch, wenn Uzai nicht läuft. Zurück: Einstellungen › Controller › Steam auf der Guide-Taste."
	return "Damit sie nicht zusätzlich Steam Big Picture öffnet, schaltet Uzai Steams Guide-Taste ab. Das gilt auch, wenn Uzai nicht läuft. Zurück: Einstellungen › Controller › Steam auf der Guide-Taste."


## Beim Start und bevor Uzai Steam selbst startet: hat Uzai die Guide-Taste abgeschaltet, neue
## Konten nachziehen – nur bei geschlossenem Steam, ohne Neustart.
static func nachziehen(tree: SceneTree) -> void:
	if not bool(Config.get_value("controller.steam_guide_aus", false)):
		return
	await stellen(tree, true, false)

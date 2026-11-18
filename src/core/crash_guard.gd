extends RefCounted
## Absturzschutz (Punkt 55). Das laufende Uzai legt laeuft.json in den Datenordner (Prozess,
## Startzeit, Bereich) und räumt sie beim sauberen Beenden weg (Config). Liegt sie beim nächsten
## Start noch da und ihr Prozess lebt nicht mehr, ging Uzai unerwartet zu: Absturz, Strom weg, im
## Task-Manager beendet. main fragt dann nach (Weiter, Fehlerbericht, Sicherer Modus). Ging es
## zweimal in Folge schon kurz nach dem Start zu, startet Uzai gleich im Sicheren Modus – sonst
## käme man nie bis zur Frage.
##
## Der Fehlerbericht ist eine vorausgefüllte GitHub-Meldung (QR fürs Handy): Version, Windows,
## Grafikkarte, wo es geschah und die letzten Fehlerzeilen aus Godots Protokoll – ohne Pfade mit
## Benutzernamen, Adressen, Kennungen und Schlüssel. Uzai schickt nichts; abschicken kann nur der
## Nutzer selbst, nachdem er alles gesehen hat (R6).

const MARKER := "laeuft.json"
const QUICK_S := 90               ## so lange nach dem Start gilt ein Ende als „beim Starten“
const LOOP := 2                   ## so viele Enden beim Starten in Folge → Sicherer Modus
const CALM_S := 600               ## so lange ohne Absturz: der Wächter darf wieder neu starten
const ISSUE_URL := "https://github.com/" + preload("res://src/core/config.gd").REPO + "/issues/new"
const MAX_URL := 1100             ## Adresse samt Bericht: der QR (Version 27) bleibt vom Sofa aus lesbar
const LOG_LINES := 14
const LINE_MAX := 150
const DROPPED := "…"

static var _re := {}


static func marker_path(data_dir: String) -> String:
	return data_dir.path_join(MARKER)


## Markierung des letzten Laufs ({} wenn keine). Unlesbar heißt: Uzai lief und schrieb gerade.
static func read(data_dir: String) -> Dictionary:
	var p := marker_path(data_dir)
	if not FileAccess.file_exists(p):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK or not (j.data is Dictionary):
		return { "pid": 0 }
	return j.data


## Ohne .bak/.tmp wie Config.write_json: eine liegengebliebene Vorfassung sähe sonst aus wie ein Absturz.
static func write(data_dir: String, m: Dictionary) -> void:
	var f := FileAccess.open(marker_path(data_dir), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m))
		f.close()


## Sauber beendet: nur die eigene Markierung wegräumen (ein zweites Uzai lässt die des ersten liegen).
static func clear(data_dir: String, own_pid: int) -> void:
	if int(read(data_dir).get("pid", -1)) == own_pid:
		DirAccess.remove_absolute(marker_path(data_dir))


## Wie ging das letzte Uzai zu? {} = sauber, oder es läuft noch (zweites Uzai, hängendes Uzai),
## oder Windows fuhr herunter („aus“). Sonst { at, where, version, quick, streak, zustaende }:
## quick = kurz nach dem Start, streak = so viele solche Enden in Folge, zustaende = zuletzt gemerkter
## Stand der Zustandsautomaten (Texte, höchstens 10).
static func verdict(m: Dictionary, own_pid: int, pid_running: bool) -> Dictionary:
	if m.is_empty():
		return {}
	var pid := int(m.get("pid", 0))
	if pid == own_pid or pid_running or str(m.get("where", "")) == "aus":
		return {}
	var quick := not bool(m.get("stable", false))
	return {
		"at": int(m.get("seen", m.get("started", 0))),
		"where": str(m.get("where", "")),
		"version": str(m.get("version", "")),
		"quick": quick,
		"streak": int(m.get("streak", 0)) + 1 if quick else 0,
		"zustaende": (m.get("zustaende") as Array).slice(0, 10).map(func(z: Variant) -> String: return str(z).left(120))
			if m.get("zustaende") is Array else [],
	}


## Sicherer Modus von selbst?
static func needs_safe(v: Dictionary) -> bool:
	return int(v.get("streak", 0)) >= LOOP


# --- Fehlerbericht ----------------------------------------------------------------------------

## Godots Protokoll des letzten Laufs: beim Start benennt Godot das alte godot.log mit Zeitstempel
## um, das neueste davon ist der letzte Lauf. current: das laufende Protokoll (ohne Absturz).
static func last_log(current := false) -> String:
	var base := ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
	if current:
		return base if FileAccess.file_exists(base) else ""
	var dir := base.get_base_dir()
	var stem := base.get_file().get_basename()
	var best := ""
	var best_t := -1
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(stem) and f.ends_with(".log") and f != base.get_file():
			var t := FileAccess.get_modified_time(dir.path_join(f))
			if t > best_t:
				best_t = t
				best = dir.path_join(f)
	return best


## Das Ende einer Protokolldatei (ein Lauf voller Meldungen kann groß werden).
static func tail_text(path: String, max_bytes := 262144) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_length()
	f.seek(maxi(0, n - max_bytes))
	var text := f.get_buffer(mini(n, max_bytes)).get_string_from_utf8()
	f.close()
	return text


## Die letzten Fehlerzeilen (Fehler, Warnungen, Absturz mit Rückverfolgung), bereinigt.
static func log_tail(text: String, homes: Array, n := LOG_LINES) -> PackedStringArray:
	var keep := PackedStringArray()
	var crash := false
	var noise := false
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.strip_edges() == "":
			continue
		var s := line.strip_edges()
		# Rauschen älterer Versionen: fehlende Suchordner (je Ordner zwei Zeilen) sind kein Fehler.
		if s.contains("Couldn't open directory at path"):
			noise = true
			continue
		if noise and s.begins_with("at:"):
			continue
		noise = false
		var low := s.to_lower()
		if low.contains("crash") or low.contains("backtrace"):
			crash = true
		var wanted := s.begins_with("ERROR") or s.begins_with("SCRIPT ERROR") or s.begins_with("WARNING") \
			or s.begins_with("at:") or s.begins_with("GDScript backtrace") or low.contains("crash") \
			or (crash and _rx("frame").search(s) != null)
		if not wanted:
			continue
		var c := clean(s, homes)
		if c.length() > LINE_MAX:
			c = c.left(LINE_MAX - 1) + DROPPED
		if keep.is_empty() or keep[keep.size() - 1] != c:
			keep.append(c)
	return keep.slice(maxi(0, keep.size() - n))


## Eine Zeile ohne Persönliches: Benutzerordner, Adressen, Kennungen, Schlüssel, E-Mail, IP.
static func clean(line: String, homes: Array) -> String:
	var s := line
	for h in homes:
		var home := str(h)
		if home.length() >= 4:
			for variant in [home, home.replace("\\", "/"), home.replace("/", "\\")]:
				s = s.replacen(variant, "~")
	s = _rx("users").sub(s, "$1" + DROPPED, true)
	s = _rx("unix_home").sub(s, "$1" + DROPPED, true)
	s = _rx("url").sub(s, "$1" + DROPPED, true)
	s = _rx("mail").sub(s, DROPPED, true)
	s = _rx("secret").sub(s, "$1=" + DROPPED, true)
	s = _rx("ip").sub(s, DROPPED, true)
	s = _rx("token").sub(s, DROPPED, true)
	s = _rx("digits").sub(s, DROPPED, true)
	return s


static func _rx(k: String) -> RegEx:
	if not _re.has(k):
		var pat := {
			"users": "(?i)([a-z]:[\\\\/]+(?:users|dokumente und einstellungen|documents and settings)[\\\\/]+)[^\\\\/\"'<>|\\n]+",
			"unix_home": "(/home/|/Users/)[^/\\s\"']+",
			"url": "(?i)\\b((?:https?|wss?)://[^/\\s\"'<>?#]+)[^\\s\"'<>]*",
			"mail": "[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\\.[A-Za-z0-9.-]+",
			"secret": "(?i)\\b(token|key|secret|password|passwort|refresh|cookie|code|auth[a-z_]*)\\s*[=:]\\s*[^\\s,;\"']+",
			"ip": "\\b\\d{1,3}(?:\\.\\d{1,3}){3}\\b",
			# Schlüssel und Kennungen: lang, mit Ziffern und Buchstaben (Funktionsnamen haben selten Ziffern).
			"token": "(?=[A-Za-z0-9_+=-]*\\d)(?=[A-Za-z0-9_+=-]*[A-Za-z])[A-Za-z0-9_+=-]{24,}",
			"digits": "\\d{9,}",
			"frame": "^\\[\\d+\\]",
		}
		var r := RegEx.new()
		r.compile(str(pat[k]))
		_re[k] = r
	return _re[k]


## Bericht als Markdown (so zeigt GitHub ihn) und die vorausgefüllte Meldung dazu. Passt die
## Adresse nicht, fallen die ältesten Protokollzeilen weg. info: version, os, gpu, godot, safe,
## crash (verdict oder {}), where (lesbarer Bereich), zustaende (Zustand.lage_text(): beim letzten Ende
## aus der Markierung, sonst der laufende Stand).
static func build(info: Dictionary, lines: PackedStringArray) -> Dictionary:
	var crash: Dictionary = info.get("crash", {})
	var title := ("Absturz in Uzai %s" if not crash.is_empty() else "Fehler in Uzai %s") % str(info.get("version", ""))
	var keep := lines.duplicate()
	var text := _text(info, crash, keep)
	while _url(title, text).to_utf8_buffer().size() > MAX_URL and not keep.is_empty():
		keep = keep.slice(1)
		text = _text(info, crash, keep)
	return { "title": title, "text": text, "url": _url(title, text), "lines": keep.size() }


static func _url(title: String, text: String) -> String:
	return ISSUE_URL + "?title=" + title.uri_encode() + "&body=" + text.uri_encode()


static func _text(info: Dictionary, crash: Dictionary, lines: PackedStringArray) -> String:
	var t := "**Was ist passiert?**\n(bitte kurz beschreiben)\n\n"
	t += "**Uzai** %s · %s · Godot %s\n" % [info.get("version", ""), info.get("os", ""), info.get("godot", "")]
	t += "**Grafik** %s\n" % str(info.get("gpu", ""))
	if not crash.is_empty():
		var where := str(info.get("where", ""))
		t += "**Ende** %s%s%s\n" % ["kurz nach dem Start" if bool(crash.get("quick", false)) else "unerwartet",
			(" · " + where) if where != "" else "",
			(" · %d× in Folge" % int(crash.streak)) if int(crash.get("streak", 0)) > 1 else ""]
	if bool(info.get("safe", false)):
		t += "**Sicherer Modus** an\n"
	# Stand der Zustandsautomaten (src/core/zustand.gd): nur Namen von Zuständen, nie Daten.
	var z: Variant = info.get("zustaende", PackedStringArray())
	if (z is PackedStringArray or z is Array) and not z.is_empty():
		t += "\n**Zustände**\n```\n" + "\n".join(PackedStringArray(z)) + "\n```\n"
	if not lines.is_empty():
		t += "\n**Protokoll** (gekürzt, ohne Namen, Pfade und Schlüssel)\n```\n" + "\n".join(lines) + "\n```\n"
	return t

extends RefCounted
## Gemeinsame, strenge Hilfen für die Launcher-Scanner (GOG, Ubisoft, Battle.net, Xbox, Amazon,
## itch.io, Riot). Alles, was diese Scanner lesen – Dateien der Launcher, Registry-Werte über den
## Helfer –, gilt als nicht vertrauenswürdig: Größen sind begrenzt, Pfade werden vereinheitlicht und
## geprüft, Kennungen nur nach festen Mustern übernommen. Nie str_to_var, Expression o. Ä.

const EpicScanner := preload("res://src/library/epic_scanner.gd")

## Höchstgröße kleiner Textdateien (Manifeste, JSON, YAML, XML).
const TEXT_MAX := 512 * 1024
## So lang darf ein Pfad höchstens sein (Windows mit langen Pfaden: 32767; mehr ist nie echt).
const PATH_MAX := 1024
## Ordner, die nie ein Spielordner sind: Uzai sucht dort sonst Spielprozesse (Spielende, „Spiel
## beenden“) und träfe Fremdes. Verglichen ohne Laufwerksbuchstaben, klein.
const BROAD_DIRS := ["", "program files", "program files (x86)", "programdata", "windows", "users",
	"xboxgames", "program files/windowsapps", "games", "spiele"]


## Datei als Text, höchstens max Bytes; größer, fehlend oder unlesbar: "".
static func read_text(path: String, max_bytes := TEXT_MAX) -> String:
	var b := read_bytes(path, max_bytes)
	if b.is_empty():
		return ""
	return b.get_string_from_utf8().trim_prefix("\ufeff")


static func read_bytes(path: String, max_bytes: int) -> PackedByteArray:
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var n := f.get_length()
	if n <= 0 or n > max_bytes:
		f.close()
		return PackedByteArray()
	var b := f.get_buffer(n)
	f.close()
	return b


## JSON ohne Fehlermeldung im Protokoll (eine kaputte Datei ist kein Programmfehler).
static func json(text: String) -> Variant:
	if text == "" or text.length() > TEXT_MAX:
		return null
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


## Steuerzeichen (auch Zeilenumbrüche und Tabulatoren)?
static func has_control(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xa0) or c == 0x2028 or c == 0x2029:
			return true
	return false


## Pfad vereinheitlicht („C:\Spiele\\X\“ → „C:/Spiele/X“); "" wenn er nicht taugt: leer, zu lang,
## mit Steuerzeichen, relativ, Netzwerkpfad (\\server – Uzai fragte sonst fremde Rechner an), mit
## „..“ oder „.“ als Teil, mit Zeichen, die Windows in Pfaden nicht erlaubt.
static func norm_path(p: String) -> String:
	var s := p.strip_edges()
	if s == "" or s.length() > PATH_MAX or has_control(s):
		return ""
	s = s.replace("\\", "/")
	if s.begins_with("//"):
		return ""
	var drive := ""
	if s.length() >= 2 and s[1] == ":" and _is_letter(s[0]):
		drive = s.substr(0, 2).to_upper()
		s = s.substr(2)
		if not s.begins_with("/"):
			return ""
	elif not s.begins_with("/"):
		return ""
	var parts := PackedStringArray()
	for part in s.split("/", false):
		if part == "." or part == "..":
			return ""
		for bad in ["<", ">", "\"", "|", "?", "*", ":"]:
			if part.contains(bad):
				return ""
		# Windows schneidet Punkte und Leerzeichen am Ende ab – „X .“ wäre ein anderer Ordner.
		if part.ends_with(" ") or part.ends_with("."):
			return ""
		parts.append(part)
	return drive + "/" + "/".join(parts)


static func _is_letter(c: String) -> bool:
	return (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")


## Spielordner, in dem Uzai nach Prozessen suchen darf: gültiger Pfad, mindestens zwei Ebenen
## unter dem Laufwerk („D:/Spiele/X“) bzw. kein bekannter Sammelordner. "" sonst.
static func game_dir(p: String) -> String:
	var d := norm_path(p)
	if d == "":
		return ""
	var rest := d.substr(2) if d.length() >= 2 and d[1] == ":" else d
	var parts := rest.trim_prefix("/").split("/", false)
	if parts.size() < 2 or rest.trim_prefix("/").to_lower() in BROAD_DIRS:
		return ""
	return d


## Datei relativ zu einem Ordner („bin\x64\spiel.exe“) – nur nach unten, nie absolut, nie „..“.
static func child(dir: String, rel: String) -> String:
	var r := rel.strip_edges().replace("\\", "/").trim_prefix("./")
	if dir == "" or r == "" or r.begins_with("/") or (r.length() > 1 and r[1] == ":"):
		return ""
	var full := norm_path(dir.path_join(r))
	return full if full != "" and full.to_lower().begins_with(dir.to_lower().trim_suffix("/") + "/") else ""


## Programmdatei, die Uzai selbst starten darf: gültiger Pfad, Endung .exe, vorhanden.
static func exe_ok(p: String) -> bool:
	var n := norm_path(p)
	return n != "" and n.get_extension().to_lower() == "exe" and FileAccess.file_exists(n)


## Titel säubern: ohne Markenzeichen, Steuerzeichen und doppelte Leerzeichen, höchstens 160 Zeichen.
static func title(t: String) -> String:
	var s := ""
	for i in mini(t.length(), 400):
		var c := t.unicode_at(i)
		s += " " if c < 32 or c == 127 or (c >= 0x80 and c < 0xa0) else t[i]
	return EpicScanner.clean_title(s).left(160).strip_edges()


## Kennung nach festem Muster (z. B. "^[0-9]{1,12}$"); "" wenn sie nicht passt.
static func id_ok(s: String, pattern: String) -> String:
	var v := s.strip_edges()
	if v == "" or v.length() > 200:
		return ""
	return v if RegEx.create_from_string(pattern).search(v) != null else ""


## Werte eines Helfer-Ergebnisses als Liste von Einträgen (ConvertTo-Json macht aus einer Liste mit
## einem Eintrag manchmal den Eintrag selbst). Höchstens max Einträge.
static func entries(v: Variant, max_n := 2000) -> Array:
	var out: Array = []
	var list: Array = v if v is Array else ([v] if v is Dictionary else [])
	for e in list:
		if e is Dictionary:
			out.append(e)
			if out.size() >= max_n:
				break
	return out


## Zeitstempel aus Launcher-Dateien („2024-05-01 18:20:11“, „2024-05-01T18:20:11.123Z“,
## „…+00:00“) → Unix-Zeit (UTC); 0 wenn nicht lesbar oder unplausibel.
static func unix_of(s: String) -> int:
	var t := s.strip_edges()
	if t.length() < 10 or t.length() > 40:
		return 0
	var m := RegEx.create_from_string("^(\\d{4})-(\\d{2})-(\\d{2})(?:[ T](\\d{2}):(\\d{2})(?::(\\d{2}))?)?").search(t)
	if m == null:
		return 0
	var d := { "year": int(m.get_string(1)), "month": int(m.get_string(2)), "day": int(m.get_string(3)),
		"hour": int(m.get_string(4)), "minute": int(m.get_string(5)), "second": int(m.get_string(6)) }
	if d.year < 2000 or d.year > 2100 or d.month < 1 or d.month > 12 or d.day < 1 or d.day > 31 or d.hour > 23 or d.minute > 59 or d.second > 60:
		return 0
	return Time.get_unix_time_from_datetime_dict(d)


## Teil-Wörterbuch eines Spiels (z. B. g.gog); {} wenn es fehlt oder kein Wörterbuch ist.
static func sub(g: Dictionary, key: String) -> Dictionary:
	var v: Variant = g.get(key)
	return v if v is Dictionary else {}

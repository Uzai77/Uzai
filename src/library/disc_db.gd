extends RefCounted
## Namen von PS1/PS2-Discs aus den Redump-Listen der libretro-database (Seriennummer → Name,
## Dateiname → Seriennummer). Damit nennt Uzai eine eingelegte Disc beim Namen und findet auch
## Abbilder ohne Nummer im Dateinamen (.chd, .cso mit Redump-Namen) oder mit anderer Region.
##
## Geladen wird nur, wenn es PS1/PS2-Spiele gibt: einmal aus dem Netz (je System etwa 4 MB),
## danach aus dem Cache (alle 90 Tage frisch). Gelesen wird stückweise auf dem Hauptthread
## (kein Hilfsthread, damit sich nichts mit anderen Abläufen in die Quere kommt).

const DiscSerial := preload("res://src/library/disc_serial.gd")
const RomScanner := preload("res://src/library/rom_scanner.gd")

const BASE := "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/redump/"
const FILES := { "ps1": "Sony%20-%20PlayStation.dat", "ps2": "Sony%20-%20PlayStation%202.dat" }
const MAX_AGE := 90 * 86400

static var _re_disc := RegEx.create_from_string("\\s*\\(Disc \\d+\\)")
static var _re_word := RegEx.create_from_string("[^a-z0-9]+")


static func url(sys: String) -> String:
	var base := Config.probe_env("UZAI_DISC_DB")
	return (base if base != "" else BASE) + str(FILES.get(sys, ""))


## DAT (clrmamepro) lesen → { serials: { "SCES-50760": "Ico (Europe) (En,Fr,De,Es,It)" },
## files: { "ico (europe) (en,fr,de,es,it)": "SCES-50760" } }. Bei mehreren Discs zählt der
## Name ohne „(Disc 1)“ ebenfalls (so heißen .m3u-Listen meist).
static func parse_dat(text: String) -> Dictionary:
	var st := new_state()
	var lines := text.split("\n")
	feed_dat(st, lines, 0, lines.size())
	return result(st)


## Zustand für stückweises Lesen (Library liest die Liste in Häppchen über mehrere Bilder,
## ohne Hilfsthread). pairs: jedes Paar „Nummer<Tab>Name“, das etwas beigetragen hat, in der
## Reihenfolge der Liste (daraus entsteht der Cache).
static func new_state() -> Dictionary:
	return { "serials": {}, "files": {}, "pairs": [], "name": "", "serial": "" }


static func result(st: Dictionary) -> Dictionary:
	return { "serials": st.serials, "files": st.files, "pairs": st.pairs }


## Zeilen from..to einer DAT verarbeiten.
static func feed_dat(st: Dictionary, lines: PackedStringArray, from: int, to: int) -> void:
	for i in range(from, to):
		var line := lines[i].strip_edges()
		if line.begins_with("game ("):
			st.name = ""
			st.serial = ""
		elif line.begins_with("name \""):
			st.name = _quoted(line)
		elif line.begins_with("serial \""):
			st.serial = DiscSerial.normalize(_quoted(line))
		elif line == ")":
			_add(st, str(st.name), str(st.serial))
			st.name = ""
			st.serial = ""


## Zeilen from..to des eigenen Caches („SLES-50330<Tab>Name“).
static func feed_tsv(st: Dictionary, lines: PackedStringArray, from: int, to: int) -> void:
	for i in range(from, to):
		var line := lines[i]
		var tab := line.find("\t")
		if tab > 0:
			_add(st, line.substr(tab + 1).strip_edges(), line.substr(0, tab))


static func _add(st: Dictionary, name: String, serial: String) -> void:
	name = name.strip_edges()
	if name == "" or serial == "":
		return
	var serials: Dictionary = st.serials
	var files: Dictionary = st.files
	var used := false
	if not serials.has(serial):
		serials[serial] = name
		used = true
	var k := file_key(name)
	if not files.has(k):
		files[k] = serial
		used = true
	var nd := file_key(strip_disc(name))
	if nd != k and name.contains("(Disc 1)") and not files.has(nd):
		files[nd] = serial
		used = true
	# Nur Paare merken, die etwas beigetragen haben: Der Cache ergibt in derselben Reihenfolge
	# wieder dieselben serials und files (erster Name je Nummer gewinnt).
	if used and st.has("pairs"):
		(st.pairs as Array).append("%s\t%s" % [serial, name])


## Kompakter Cache: eine Zeile je Paar Nummer–Name (auch Revisionen und Sprachfassungen mit
## derselben Nummer, sonst fänden sich deren Abbilder nach dem ersten Start nicht mehr).
static func to_tsv(db: Dictionary) -> String:
	var pairs: Array = db.get("pairs", [])
	if not pairs.is_empty():
		return "\n".join(PackedStringArray(pairs))
	# Ohne Paare (Liste von Hand gesetzt): nur Nummer → Name.
	var out := PackedStringArray()
	var serials: Dictionary = db.get("serials", {})
	for k in serials.keys():
		out.append("%s\t%s" % [k, serials[k]])
	return "\n".join(out)


static func _quoted(line: String) -> String:
	var a := line.find("\"")
	var b := line.find("\"", a + 1)
	return line.substr(a + 1, b - a - 1) if a >= 0 and b > a else ""


## Schlüssel für Dateinamen: Name ohne Endung, klein.
static func file_key(stem: String) -> String:
	return stem.strip_edges().to_lower()


static func strip_disc(name: String) -> String:
	return _re_disc.sub(name, "", true)


## Schlüssel für Titel: ohne Region und Zusätze, ohne Artikel „The“, nur Buchstaben und Ziffern.
## „Legend of Dragoon, The (USA) (Disc 1)“ und „The Legend of Dragoon“ ergeben dasselbe.
static func title_key(s: String) -> String:
	var t := _re_word.sub(RomScanner.clean_title(s).to_lower(), " ", true).strip_edges()
	if t.begins_with("the "):
		t = t.substr(4)
	return t


## Seriennummer zu einer Datei eines Spiels über ihren Namen ("" wenn unbekannt).
static func serial_for_file(db: Dictionary, path: String) -> String:
	var files: Dictionary = db.get("files", {})
	var stem := file_key(path.replace("\\", "/").get_file().get_basename())
	return str(files.get(stem, files.get(file_key(strip_disc(stem)), "")))

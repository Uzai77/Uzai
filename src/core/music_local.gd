extends Node
## Lokale Musik (Punkt 34): die eigenen Musikdateien aus einem gewählten Ordner, abgespielt über
## Uzais eigenen Ton – Alben, Interpreten, Titel, Warteschlange, Zufall und Wiederholen.
## Music (src/core/music.gd) hält diesen Knoten und leitet bei Musikquelle „lokal“ alles hierher;
## Guide, Kopfleiste, Ruhebildschirm und Discord-Status sehen dasselbe Music.now wie bei Spotify.
##
## Sicherheit: Uzai liest nur im gewählten Ordner, folgt dort keiner Verknüpfung (auch keiner
## Abzweigung unter Windows), nimmt nur MP3, Ogg Vorbis und WAV und öffnet die Dateien nur lesend
## (Angaben: music_tags.gd). Vor jedem Abspielen wird der Pfad noch einmal geprüft – auch die
## gemerkte Warteschlange im Datenordner könnte jemand verändert haben. Nichts geht ins Netz.
## Cover aus den Dateien landen als JPEG/PNG im Zwischenspeicher (cache/musik), damit sie wie jedes
## andere Bild geladen werden.

signal library_changed               ## nach dem Einlesen (Alben, Interpreten, Titel neu)
signal scan_progress(done: int, total: int)
signal state_changed                 ## Titel, Pause, Zufall, Wiederholen, Warteschlange, Lautstärke

const Arbeit := preload("res://src/core/arbeit.gd")
const Tags := preload("res://src/core/music_tags.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Fremd := preload("res://src/core/fremd.gd")
## Das gemerkte Verzeichnis liest und schreibt der Hintergrundlauf: über das Skript, nicht über den Knoten „Config“.
const ConfigS := preload("res://src/core/config.gd")

const FILES_MAX := 20000              ## mehr Dateien liest Uzai nicht ein
const DEPTH_MAX := 12                 ## so tief in Unterordner
const QUEUE_MAX := 2000               ## so viele Titel in der Warteschlange
const QUEUE_SAVE := 500               ## so viele davon merkt sich Uzai bis zum nächsten Start
const COVERS_MAX := 3000              ## so viele Albumbilder je Einlesen
const COVER_NAMES := ["cover", "folder", "front", "album", "albumart"]
const COVER_EXTS := ["jpg", "jpeg", "png"]
const INDEX_VERSION := 1
const PREV_RESTART_MS := 3000         ## „Zurück“ nach so viel Spielzeit: Titel von vorn
const UNKNOWN_ARTIST := "Unbekannter Interpret"
const VARIOUS := "Verschiedene Interpreten"
const NO_ALBUM := "Ohne Album"

var tracks: Array = []                ## Titel (wie Music.track_from, dazu path, track, disc, year, akey)
var albums: Array = []                ## { kind: "album", local: true, id, name, artist, art, year, date, tracks, count, uri: "" }
var artists: Array = []               ## { kind: "artist", local: true, id, name, art, albums, tracks, count }
var scanning := false
var scanned_root := ""                ## für welchen Ordner tracks gilt
var scan_error := ""

# --- Wiedergabe ---
var queue: Array = []                 ## Titel in Listenreihenfolge
var order: Array = []                 ## Reihenfolge des Abspielens (Indizes in queue; gemischt bei Zufall)
var pos := -1                         ## Stelle in order
var shuffle := false
var repeat := "off"                   ## off | context (ganze Liste) | track
var volume := 80                      ## 0..100, nur dieser Player (nie Windows)
var context := ""                     ## "lokal:<Albumschlüssel>" oder ""
var context_name := ""
var _player: AudioStreamPlayer
var _loaded := ""                     ## Pfad im Player
var _dur_ms := 0
var _load_gen := 0
var _paused := true
var _resume_ms := 0                   ## nach dem Start: an dieser Stelle weitermachen
var _pos_base := 0                    ## Stelle (ms) beim letzten Start, Sprung oder Anhalten …
var _pos_at := 0                      ## … und wann das war (Zeit seit Programmstart, ms)
static var _num_rx := RegEx.create_from_string("^\\s*\\d{1,3}\\s*[-.)]?\\s+")
var _save_timer: Timer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "LokaleMusik"
	add_child(_player)
	_player.finished.connect(_on_finished)
	volume = clampi(int(Config.get_value("music.local_volume", 80)), 0, 100)
	_apply_volume()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 2.0
	_save_timer.timeout.connect(_save_state)
	add_child(_save_timer)


static func root() -> String:
	return norm(str(Config.get_value("music.local_dir", "")))


## Vorschlag für den Musikordner: der von Windows bzw. dem System („Musik“).
static func suggested_root() -> String:
	return norm(OS.get_system_dir(OS.SYSTEM_DIR_MUSIC))


# --- Pfade prüfen ------------------------------------------------------------------------------

static func norm(p: String) -> String:
	var s := p.replace("\\", "/").strip_edges()
	while s.length() > 1 and s.ends_with("/") and not s.ends_with(":/"):
		s = s.left(-1)
	return s


## Liegt path wirklich im Ordner root (ohne „..“, ohne fremde Endung)? Nur die Form – ob eine
## Verknüpfung auf dem Weg liegt, prüft playable().
static func inside(path: String, root_dir: String) -> bool:
	var r := norm(root_dir)
	var p := norm(path)
	if r == "" or p == "" or not r.is_absolute_path() or not p.is_absolute_path() or p.contains("://") or r.contains("://"):
		return false
	for seg in p.split("/", false):
		if seg == ".." or seg == ".":
			return false
	var base := r if r.ends_with("/") else r + "/"
	return p.begins_with(base) and p.length() > base.length() and p.get_extension().to_lower() in Tags.EXTS


## Darf Uzai diese Datei abspielen? Im Ordner, richtige Endung, vorhanden, und weder die Datei noch
## ein Ordner auf dem Weg dorthin ist eine Verknüpfung oder Abzweigung.
static func playable(path: String, root_dir: String) -> bool:
	if not inside(path, root_dir) or not FileAccess.file_exists(path):
		return false
	var r := norm(root_dir)
	var walk := r
	for seg in norm(path).trim_prefix(r + "/").split("/", false):
		var da := DirAccess.open(walk)
		if da == null or da.is_link(seg):
			return false
		walk = walk.path_join(seg)
	return true


# --- Einlesen ----------------------------------------------------------------------------------

## Alle Musikdateien im Ordner: [[Pfad, Änderungszeit, Größe], …] – ohne Verknüpfungen, ohne
## versteckte Ordner, höchstens FILES_MAX, sortiert.
static func list_files(root_dir: String, max_files := FILES_MAX) -> Array:
	var out: Array = []
	var r := norm(root_dir)
	if r == "" or not DirAccess.dir_exists_absolute(r):
		return out
	var stack: Array = [[r, 0]]
	while not stack.is_empty() and out.size() < max_files:
		var item: Array = stack.pop_back()
		var d: String = item[0]
		var depth: int = item[1]
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.include_hidden = false
		for sub in da.get_directories():
			if depth < DEPTH_MAX and not sub.begins_with(".") and not da.is_link(sub):
				stack.append([d.path_join(sub), depth + 1])
		for f in da.get_files():
			if out.size() >= max_files:
				break
			if da.is_link(f) or not f.get_extension().to_lower() in Tags.EXTS:
				continue
			var p := d.path_join(f)
			out.append([p, FileAccess.get_modified_time(p), FileAccess.get_size(p)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).naturalnocasecmp_to(str(b[0])) < 0)
	return out


## Läufe von scan, die gerade unterwegs sind (siehe dort).
var _scan_offen := 0


## Einlesen im Hintergrund. Unveränderte Dateien (gleiche Zeit und Größe) nimmt Uzai aus dem
## gemerkten Verzeichnis (cache/musik/index.json), nur neue und geänderte werden gelesen.
func scan(force := false) -> void:
	_scan_offen += 1
	await _scan_lauf(force)
	_scan_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und scan täte bis zum Neustart nichts mehr.
	if _scan_offen == 0 and scanning:
		scanning = false


func _scan_lauf(force := false) -> void:
	if scanning:
		return
	var r := root()
	if r == "":
		_set_library([], "")
		return
	scanning = true
	scan_error = ""
	_stand_melden()
	scan_progress.emit(0, 0)
	var box := { "entries": [], "covers": {}, "files": 0, "done": 0, "lib": {}, "fertig": false }
	var cover_dir := Config.path("cache/musik/cover")
	var lauf := Arbeit.auftrag(_scan_worker.bind(r, force, index_path(), cover_dir, box), Arbeit.LANG)
	var last := -1
	while not lauf.fertig:
		await get_tree().process_frame
		if int(box.done) != last:
			last = int(box.done)
			scan_progress.emit(last, int(box.files))
	scanning = false
	if root() != r:
		scan()                        # Ordner während des Einlesens gewechselt
		return
	if not bool(box.fertig):
		return                        # der Lauf wurde abgebrochen (Uzai beendet sich): nichts übernehmen
	if (box.entries as Array).is_empty() and not DirAccess.dir_exists_absolute(r):
		scan_error = "Der Ordner ist nicht erreichbar."
	_set_library(box.lib, r)


## Arbeit im Hintergrund: gemerktes Verzeichnis lesen, Dateien finden, Angaben lesen (oder übernehmen), Albumbilder
## suchen, das Verzeichnis neu merken und die Bibliothek bauen. Lesen, Merken und Bauen liefen vorher im
## Hauptfaden: bei 6000 Titeln hielt das nach jedem Einlesen das Bild gut eine halbe Sekunde an (gemessen: 127 ms
## Schreiben, 402 ms Bauen).
static func _scan_worker(r: String, force: bool, index_file: String, cover_dir: String, box: Dictionary) -> void:
	var old := {} if force else load_index(index_file, r)
	var files := list_files(r)
	box.files = files.size()
	var entries: Array = []
	for f in files:
		if Arbeit.endet:
			return
		var p: String = f[0]
		var prev: Dictionary = old.get(p, {})
		var tags: Dictionary
		if not prev.is_empty() and int(prev.get("m", -1)) == int(f[1]) and int(prev.get("s", -1)) == int(f[2]):
			tags = prev.get("t", {})
		else:
			tags = Tags.read(p, false)
		box.done = int(box.done) + 1
		if bool(tags.get("unsupported", false)):
			continue
		entries.append({ "path": p, "m": int(f[1]), "s": int(f[2]), "t": tags })
	box.entries = entries
	box.covers = find_covers(entries, r, cover_dir)
	save_index(index_file, r, entries)
	box.lib = build_library(entries, r, box.covers)
	box.fertig = true


## Albumbild je Album: ein Bild im Ordner (cover.jpg, folder.jpg …), sonst das eingebettete
## Cover des ersten Titels (als Datei im Zwischenspeicher). { Albumschlüssel: Pfad }.
static func find_covers(entries: Array, r: String, cover_dir: String) -> Dictionary:
	var out := {}
	var first := {}                    # Albumschlüssel → Pfad des ersten Titels
	for e in entries:
		var k := album_key(e.t, str(e.path))
		if not first.has(k):
			first[k] = str(e.path)
	var n := 0
	for k in first:
		if n >= COVERS_MAX:
			break
		n += 1
		var p: String = first[k]
		var img := folder_image(p.get_base_dir())
		if img == "":
			img = embedded_cover(p, cover_dir, r)
		if img != "":
			out[k] = img
	return out


## Bild im Albumordner (cover/folder/front/album.jpg|png), keine Verknüpfung. "" = keins.
static func folder_image(dir: String) -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	var by_name := {}
	for f in da.get_files():
		by_name[f.to_lower()] = f
	for nm in COVER_NAMES:
		for ext in COVER_EXTS:
			var hit := str(by_name.get(nm + "." + ext, ""))
			if hit != "" and not da.is_link(hit) and FileAccess.get_size(dir.path_join(hit)) <= Tags.PIC_MAX:
				return dir.path_join(hit)
	return ""


## Eingebettetes Cover als Datei im Zwischenspeicher (gleiche Datei → gleicher Name). "" = keins.
static func embedded_cover(path: String, cover_dir: String, r: String) -> String:
	if not inside(path, r):
		return ""
	var t := Tags.read(path, true)
	var pic: Variant = t.get("pic")
	if not (pic is PackedByteArray) or (pic as PackedByteArray).is_empty():
		return ""
	var ext := Tags.image_ext(pic)
	if ext == "":
		return ""
	var dest := cover_dir.path_join("%s.%s" % [path.md5_text(), ext])
	if FileAccess.file_exists(dest) and FileAccess.get_size(dest) == (pic as PackedByteArray).size():
		return dest
	DirAccess.make_dir_recursive_absolute(cover_dir)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(pic)
	f.close()
	return dest


static func index_path() -> String:
	return Config.path("cache/musik/index.json")


## Gemerktes Verzeichnis lesen – nur Einträge im Ordner und mit sauberen Typen.
static func load_index(file: String, r: String) -> Dictionary:
	var d: Variant = ConfigS.read_json(file, {})
	var out := {}
	if not (d is Dictionary) or Fremd.zahl((d as Dictionary).get("version")) != INDEX_VERSION or norm(str(d.get("root", ""))) != norm(r):
		return out
	var files: Variant = d.get("files")
	if not (files is Dictionary):
		return out
	for p in files:
		var e: Variant = files[p]
		if not (e is Dictionary) or not inside(str(p), r) or not (e.get("t") is Dictionary):
			continue
		out[str(p)] = { "m": Fremd.zahl(e.get("m"), -1), "s": Fremd.zahl(e.get("s"), -1), "t": clean_tags(e.t) }
	return out


static func save_index(file: String, r: String, entries: Array) -> void:
	var files := {}
	for e in entries:
		files[str(e.path)] = { "m": e.m, "s": e.s, "t": clean_tags(e.t) }
	ConfigS.write_json(file, { "version": INDEX_VERSION, "root": r, "files": files })


## Nur die bekannten Felder mit passendem Typ (gemerkte oder gelesene Angaben).
static func clean_tags(t: Dictionary) -> Dictionary:
	var out := {}
	for k in ["title", "artist", "album", "album_artist"]:
		if t.get(k) is String and str(t[k]) != "":
			out[k] = Tags.clean(str(t[k]))
	for k in ["track", "disc", "year", "dur"]:
		var v: Variant = t.get(k)
		if (v is int or v is float) and int(v) > 0 and int(v) < 86400000:
			out[k] = int(v)
	return out


# --- Bibliothek --------------------------------------------------------------------------------

## Albumschlüssel: mit Album-Interpret nach ihm und Album, sonst nach Ordner und Album (eine
## Sammlung mit vielen Interpreten bleibt so ein Album).
static func album_key(t: Dictionary, path: String) -> String:
	var aa := str(t.get("album_artist", "")).to_lower()
	var al := str(t.get("album", "")).to_lower()
	if aa != "":
		return aa + "|" + al
	return path.get_base_dir().to_lower() + "|" + al


## Titel ohne Angaben aus dem Dateinamen: „03 - Mein Lied_live“ → „Mein Lied live“.
static func title_from_file(path: String) -> String:
	var s := path.get_file().get_basename().replace("_", " ")
	s = _num_rx.sub(s, "")
	return Tags.clean(s) if Tags.clean(s) != "" else path.get_file()


## Aus den gelesenen Einträgen Titel, Alben und Interpreten (ohne Datei-Zugriff, testbar).
## Interpret ohne Angabe in der Datei: der Ordner über dem Album (Musik/Interpret/Album/Titel) –
## so liegen die meisten Sammlungen. Liegt das Album direkt im Musikordner, bleibt er unbekannt.
static func artist_from_path(p: String, r: String) -> String:
	var wurzel := norm(r)
	var album_dir := norm(p.get_base_dir())
	var ueber := norm(album_dir.get_base_dir())
	var basis := wurzel if wurzel.ends_with("/") else wurzel + "/"
	if album_dir == wurzel or ueber == wurzel or not ueber.begins_with(basis):
		return UNKNOWN_ARTIST
	return ueber.get_file()


static func build_library(entries: Array, r: String, covers: Dictionary = {}) -> Dictionary:
	var by_album := {}
	var album_order: Array = []
	var all: Array = []
	for e in entries:
		var p := str(e.path)
		if not inside(p, r):
			continue
		var t: Dictionary = clean_tags(e.t if e.t is Dictionary else {})
		var k := album_key(t, p)
		var album_name := str(t.get("album", ""))
		if album_name == "":
			album_name = p.get_base_dir().get_file() if norm(p.get_base_dir()) != norm(r) else NO_ALBUM
		var tr := {
			"id": "lokal:" + p.md5_text().left(16), "uri": "lokal:" + p, "path": p,
			"title": str(t.get("title", title_from_file(p))), "artist": str(t.get("artist", t.get("album_artist", artist_from_path(p, r)))),
			"album": album_name, "art": str(covers.get(k, "")), "duration": int(t.get("dur", 0)),
			"track": int(t.get("track", 0)), "disc": int(t.get("disc", 0)), "year": int(t.get("year", 0)), "akey": k,
			"album_artist": str(t.get("album_artist", "")),
		}
		all.append(tr)
		if not by_album.has(k):
			by_album[k] = []
			album_order.append(k)
		by_album[k].append(tr)
	var album_list: Array = []
	for k in album_order:
		var list: Array = by_album[k]
		# Fehlt auch nur einem Titel die Nummer, gilt für das ganze Album der Dateiname (dort steht sie meist vorn).
		var mit_nummern := list.all(func(t: Dictionary) -> bool: return int(t.track) > 0)
		list.sort_custom(_track_less if mit_nummern else _datei_less)
		var first: Dictionary = list[0]
		var who := str(first.album_artist)
		if who == "":
			who = str(first.artist)
			for x in list:
				if str(x.artist) != who:
					who = VARIOUS
					break
		var year := 0
		for x in list:
			year = maxi(year, int(x.year))
		album_list.append({ "kind": "album", "local": true, "id": "lokal:" + str(k).md5_text().left(16), "akey": k,
			"name": str(first.album), "artist": who, "art": str(first.art), "year": year, "date": str(year) if year > 0 else "",
			"tracks": list, "count": list.size(), "uri": "" })
	album_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aa := _sort_name(str(a.artist))
		var bb := _sort_name(str(b.artist))
		if aa != bb:
			return aa.naturalnocasecmp_to(bb) < 0
		# Nach Jahr; Alben ohne Jahr stehen dahinter, nach Namen. Früher zählte das Jahr nur, wenn beide eins
		# hatten – paarweise entschieden und bei gemischten Angaben widersprüchlich (wie bei den Titelnummern).
		var ja := int(a.year) if int(a.year) > 0 else 99999
		var jb := int(b.year) if int(b.year) > 0 else 99999
		if ja != jb:
			return ja < jb
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	# Interpreten: nach Album-Interpret, Sammlungen („Verschiedene Interpreten“) zuletzt.
	var by_artist := {}
	var artist_order: Array = []
	for al in album_list:
		var nm := str(al.artist)
		var key := nm.to_lower()
		if not by_artist.has(key):
			by_artist[key] = { "kind": "artist", "local": true, "id": "lokal:a:" + key.md5_text().left(12), "name": nm,
				"art": "", "albums": [], "tracks": [], "count": 0 }
			artist_order.append(key)
		var a: Dictionary = by_artist[key]
		a.albums.append(al)
		a.tracks.append_array(al.tracks)
		a.count = (a.tracks as Array).size()
		if str(a.art) == "" and str(al.art) != "":
			a.art = al.art
	var artist_list: Array = []
	for key in artist_order:
		artist_list.append(by_artist[key])
	artist_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (str(a.name) == VARIOUS) != (str(b.name) == VARIOUS):
			return str(b.name) == VARIOUS
		return _sort_name(str(a.name)).naturalnocasecmp_to(_sort_name(str(b.name))) < 0)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	return { "tracks": all, "albums": album_list, "artists": artist_list }


## Reihenfolge im Album: CD, Nummer, Dateiname. Früher zählte die Nummer nur, wenn beide Titel eine hatten, sonst der
## Dateiname – paarweise entschieden. Bei Alben mit teils fehlenden Nummern widersprach sich das (A vor B, B vor C,
## C vor A): Die Reihenfolge war dann beliebig, und eine Sortierung mit so einem Vergleich ist nicht sicher.
static func _track_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.disc) != int(b.disc):
		return int(a.disc) < int(b.disc)
	if int(a.track) != int(b.track):
		return int(a.track) < int(b.track)
	return str(a.path).naturalnocasecmp_to(str(b.path)) < 0


static func _datei_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.disc) != int(b.disc):
		return int(a.disc) < int(b.disc)
	return str(a.path).naturalnocasecmp_to(str(b.path)) < 0


## Sortiername: „The Beatles“ unter B.
static func _sort_name(s: String) -> String:
	var l := s.to_lower()
	for art in ["the ", "die ", "der ", "das "]:
		if l.begins_with(art) and l.length() > art.length():
			return s.substr(art.length())
	return s


func _set_library(lib: Variant, r: String) -> void:
	var d: Dictionary = lib if lib is Dictionary else {}
	tracks = d.get("tracks", [])
	albums = d.get("albums", [])
	artists = d.get("artists", [])
	scanned_root = r
	_stand_melden()
	library_changed.emit()


## Stand der eigenen Musik wie LocalUi.state(): ordner (keiner gewählt) · laden · fehlt (Ordner nicht erreichbar) ·
## leer · bereit. Liegt in root(), scanning, scan_error und tracks (kein eigenes Feld): gemeldet, wo das Einlesen
## beginnt und endet – nur für Zustand.lage() und den Fehlerbericht („musik.lokal“).
func _stand_melden() -> void:
	var st := "bereit"
	if root() == "":
		st = "ordner"
	elif scanning:
		st = "laden"
	elif scan_error != "":
		st = "fehlt"
	elif tracks.is_empty():
		st = "leer"
	Zustand.melden("musik.lokal", st)


# --- Warteschlange (ohne Wiedergabe, testbar) --------------------------------------------------

## Reihenfolge für n Titel: 0..n-1, bei Zufall gemischt mit start vorn.
static func make_order(n: int, start: int, shuffled: bool, rng: RandomNumberGenerator = null) -> Array:
	var o: Array = range(n)
	if not shuffled or n <= 1:
		return o
	o.erase(start)
	var r := rng if rng != null else RandomNumberGenerator.new()
	for i in range(o.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = o[i]
		o[i] = o[j]
		o[j] = tmp
	o.push_front(start)
	return o


## Nächste Stelle in order: Titel wiederholen bleibt nur am Ende eines Titels (auto) stehen, Liste
## wiederholen springt ans Ende vorn hin. -1 = Schluss.
static func next_pos(p: int, n: int, rep: String, auto: bool) -> int:
	if n <= 0:
		return -1
	if auto and rep == "track":
		return p
	if p + 1 < n:
		return p + 1
	return 0 if rep == "context" else -1


## Vorige Stelle: am Anfang bei „Liste wiederholen“ ans Ende, sonst bleibt es beim ersten.
static func prev_pos(p: int, n: int, rep: String) -> int:
	if n <= 0:
		return -1
	if p > 0:
		return p - 1
	return n - 1 if rep == "context" else 0


## Die nächsten Titel nach der aktuellen Stelle (für „Als Nächstes“).
func upcoming(limit := 50) -> Array:
	var out: Array = []
	if pos < 0:
		return out
	var p := pos
	for i in limit:
		var nx := next_pos(p, order.size(), "context" if repeat == "context" else "off", false)
		if nx < 0 or nx == pos:
			break
		out.append(queue[order[nx]])
		p = nx
	return out


# --- Wiedergabe --------------------------------------------------------------------------------

## Ab welchem Platz einer Liste mit n Titeln die Warteschlange beginnt, damit der gewählte Titel idx hineinpasst:
## bei kurzen Listen vorn, sonst so, dass ein Viertel der Plätze davor liegt und der Rest danach.
static func fenster_ab(n: int, idx: int, platz := QUEUE_MAX) -> int:
	if n <= platz:
		return 0
	return clampi(idx - (platz >> 2), 0, n - platz)


## Titel ab idx abspielen (die Liste läuft danach weiter). ctx: Albumschlüssel für „aus …“.
func play_tracks(list: Array, idx: int, ctx := "", ctx_name := "") -> void:
	var r := root()
	var clean: Array = []
	var start := 0
	# Mehr Titel, als in die Warteschlange passen („Alle Titel“ einer großen Sammlung): das Stück rund um den
	# gewählten nehmen. Vorher zählte die Schleife immer von vorn, und ein Titel weiter hinten startete den ersten.
	for i in range(fenster_ab(list.size(), idx), list.size()):
		var t: Variant = list[i]
		if t is Dictionary and inside(str(t.get("path", "")), r):
			if i == idx:
				start = clean.size()
			clean.append(t)
		if clean.size() >= QUEUE_MAX:
			break
	if clean.is_empty():
		return
	queue = clean
	order = make_order(queue.size(), start, shuffle)
	pos = 0 if shuffle else start
	context = ctx
	context_name = ctx_name
	_paused = false
	_start_current(0)


## Titel als Nächstes einreihen (X auf einem Titel).
func enqueue(t: Dictionary) -> void:
	if not inside(str(t.get("path", "")), root()) or queue.size() >= QUEUE_MAX:
		return
	if queue.is_empty():
		play_tracks([t], 0)
		return
	queue.append(t)
	order.insert(pos + 1, queue.size() - 1)
	_changed()


func toggle() -> void:
	if current().is_empty():
		if not albums.is_empty():
			play_tracks(tracks, 0)
		return
	if _loaded == "":
		if not _paused:
			# Der nächste Titel lädt gerade: angehalten bleiben, sobald er da ist.
			_paused = true
			_changed()
			return
		_paused = false
		_start_current(_resume_ms)
		return
	_mark_pos()
	_paused = not _paused
	_player.stream_paused = _paused
	_changed()


func set_paused(on: bool) -> void:
	if on != _paused:
		toggle()


func next() -> void:
	_step(next_pos(pos, order.size(), repeat if repeat != "track" else "context", false))


func previous() -> void:
	if position_ms() > PREV_RESTART_MS:
		seek_to(0)
		return
	_step(prev_pos(pos, order.size(), repeat))


## An Stelle idx in „Als Nächstes“ springen (0 = der nächste Titel).
func skip_to(idx: int) -> void:
	var p := pos
	for i in idx + 1:
		var nx := next_pos(p, order.size(), "context" if repeat == "context" else "off", false)
		if nx < 0:
			return
		p = nx
	_step(p)


func _step(p: int, paused := false) -> void:
	if p < 0:
		# Ende der Liste: anhalten, der letzte Titel bleibt stehen.
		_paused = true
		_player.stop()
		_resume_ms = 0
		_loaded = ""
		_changed()
		return
	pos = p
	_paused = paused
	_start_current(0)


func set_shuffle(on: bool) -> void:
	shuffle = on
	if not queue.is_empty() and pos >= 0:
		var cur: int = order[pos]
		order = make_order(queue.size(), cur, on)
		pos = order.find(cur)
	_changed()


func cycle_repeat() -> void:
	repeat = { "off": "context", "context": "track", "track": "off" }.get(repeat, "off")
	_changed()


func seek_to(ms: int) -> void:
	if _loaded == "":
		_resume_ms = maxi(0, ms)
		_changed()
		return
	var d := duration_ms()
	ms = clampi(ms, 0, maxi(0, d - 500) if d > 0 else ms)
	_player.play(ms / 1000.0)
	_player.stream_paused = _paused
	_pos_base = ms
	_pos_at = Time.get_ticks_msec()
	_changed()


func set_volume(v: int) -> void:
	volume = clampi(v, 0, 100)
	Config.set_value("music.local_volume", volume)
	_apply_volume()
	_changed()


func _apply_volume() -> void:
	if _player:
		_player.volume_db = linear_to_db(volume / 100.0) if volume > 0 else -80.0


func current() -> Dictionary:
	if pos < 0 or pos >= order.size() or int(order[pos]) >= queue.size():
		return {}
	return queue[order[pos]]


func playing() -> bool:
	return _loaded != "" and not _paused


## Soll gerade etwas klingen (spielt oder lädt den Titel noch)? Neben Spotify: dann gilt diese Quelle.
func wants_play() -> bool:
	return not _paused and not current().is_empty()


## Stelle im Titel. Uzai rechnet selbst mit (wie bei Spotify): angehalten meldet der Player keine
## verlässliche Stelle.
func position_ms() -> int:
	if _loaded == "":
		return _resume_ms
	var p := _pos_base + (Time.get_ticks_msec() - _pos_at if not _paused else 0)
	var d := duration_ms()
	return mini(p, d) if d > 0 else p


func _mark_pos() -> void:
	_pos_base = position_ms()
	_pos_at = Time.get_ticks_msec()


func duration_ms() -> int:
	return _dur_ms if _dur_ms > 0 else int(current().get("duration", 0))


## Stand für Music.now (wie bei Spotify; source „lokal“).
func now_dict() -> Dictionary:
	var t := current()
	if t.is_empty():
		return {}
	return { "id": str(t.id), "uri": str(t.uri), "title": str(t.title), "artist": str(t.artist), "album": str(t.album),
		"art": str(t.get("art", "")), "duration": duration_ms(), "playing": playing(), "shuffle": shuffle, "repeat": repeat,
		"device": "", "volume": volume, "context": context, "liked": false, "source": "lokal" }


## Datei laden (im Hintergrund – ein großes WAV soll das Menü nicht anhalten) und abspielen.
func _start_current(from_ms: int) -> void:
	_load_gen += 1
	var gen := _load_gen
	var t := current()
	var p := str(t.get("path", ""))
	_player.stop()
	_loaded = ""
	_dur_ms = int(t.get("duration", 0))
	_resume_ms = from_ms
	_changed()
	if not playable(p, root()):
		_skip_broken(gen, "Datei fehlt oder liegt nicht im Musikordner")
		return
	var s := await Arbeit.ergebnis(load_stream.bind(p)) as AudioStream
	if gen != _load_gen:
		return
	if s == null:
		_skip_broken(gen, "Die Datei lässt sich nicht abspielen")
		return
	_player.stream = s
	_loaded = p
	var len_ms := int(s.get_length() * 1000.0)
	if len_ms > 0:
		_dur_ms = len_ms
	_player.play(from_ms / 1000.0)
	_player.stream_paused = _paused
	_pos_base = from_ms
	_pos_at = Time.get_ticks_msec()
	_changed()


## Datei als Klang (MP3, Ogg Vorbis, WAV). null = geht nicht.
static func load_stream(p: String) -> AudioStream:
	match p.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(p)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(p)
		"wav":
			return AudioStreamWAV.load_from_file(p)
	return null


## Kaputter oder verschwundener Titel: kurz melden und weiter (höchstens einmal je Liste rundherum).
var _broken_run := 0


func _skip_broken(gen: int, why: String) -> void:
	_broken_run += 1
	Toasts.show_toast("%s übersprungen" % str(current().get("title", "")), why, "warning", { "ms": 3000, "quiet": true })
	if _broken_run >= order.size():
		_broken_run = 0
		_paused = true
		_changed()
		return
	await get_tree().create_timer(0.3).timeout
	if gen != _load_gen:
		return
	_step(next_pos(pos, order.size(), "context" if repeat != "off" else "off", false))


func _on_finished() -> void:
	_broken_run = 0
	# Pause genau am Titelende (das Signal kam schon unterwegs): der nächste bleibt angehalten.
	_step(next_pos(pos, order.size(), repeat, true), _paused)


func _changed() -> void:
	state_changed.emit()
	if is_instance_valid(_save_timer):
		_save_timer.start()


# --- Merken bis zum nächsten Start ---------------------------------------------------------------

static func state_path() -> String:
	return Config.path("cache/musik/zuletzt.json")


func _save_state() -> void:
	if queue.is_empty():
		return
	var paths: Array = []
	var lo := maxi(0, pos - 250)
	var idx: Array = order.slice(lo, lo + QUEUE_SAVE)
	for i in idx:
		paths.append(str(queue[i].path))
	Config.write_json(state_path(), { "root": root(), "paths": paths, "pos": pos - lo, "ms": position_ms(),
		"shuffle": shuffle, "repeat": repeat, "context": context, "context_name": context_name })


## Nach dem Start: die letzte Warteschlange angehalten wiederherstellen (nichts spielt von selbst).
func restore() -> void:
	var d: Variant = Config.read_json(state_path(), {})
	if not (d is Dictionary) or norm(str(d.get("root", ""))) != root() or tracks.is_empty():
		return
	var by_path := {}
	for t in tracks:
		by_path[str(t.path)] = t
	var list: Array = []
	var paths := Fremd.liste(d.get("paths"))
	var gemerkt := Fremd.zahl(d.get("pos"))
	var start := 0
	var genau := false                # der zuletzt gehörte Titel selbst ist noch da
	for i in paths.size():
		# Fehlen inzwischen Titel davor, rückt die Stelle mit; fehlt der Titel selbst, steht hier der nächste.
		if i == gemerkt:
			start = list.size()
			genau = by_path.has(str(paths[i]))
		if by_path.has(str(paths[i])):
			list.append(by_path[str(paths[i])])
	if list.is_empty():
		return
	queue = list
	order = range(list.size())
	pos = clampi(start, 0, list.size() - 1)
	shuffle = Fremd.ja(d.get("shuffle"))
	repeat = str(d.get("repeat", "off")) if str(d.get("repeat", "off")) in ["off", "context", "track"] else "off"
	context = str(d.get("context", ""))
	context_name = str(d.get("context_name", ""))
	_paused = true
	_loaded = ""
	_resume_ms = maxi(0, Fremd.zahl(d.get("ms"))) if genau else 0
	_dur_ms = int(current().get("duration", 0))
	state_changed.emit()


## Musikquelle gewechselt: anhalten, nichts mehr abspielen.
func stop() -> void:
	_load_gen += 1
	if _loaded != "":
		_resume_ms = position_ms()
	_player.stop()
	_loaded = ""
	_paused = true
	_changed()

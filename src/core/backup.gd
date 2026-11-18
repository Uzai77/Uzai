extends RefCounted
## Uzai-Daten sichern und wiederherstellen (Punkt 140) und Einstellungen selbst reparieren (56/133).
##
## Eine Sicherung ist eine ZIP-Datei in <Datenordner>/backups mit allem, was man nicht neu laden
## kann: Einstellungen, Bibliothek, Spielzeit, Filme/YouTube/Aufnahmen-Listen (die *.json im
## Datenordner), eigene Bilder (media), eigene Klänge (sounds) und die Filme-Daten (movies, ohne
## die Laufzeit). Zwischenspeicher, Werkzeuge, Protokolle und Aufnahmen (Videos) bleiben draußen.
## Sie enthält auch Anmeldungen – sie bleibt im Datenordner und wird nirgends hingeschickt.
##
## Wiederherstellen geschieht beim nächsten Start, bevor irgendetwas geladen ist
## (apply_pending_restore aus Config._ready): Uzai merkt sich die Wahl und startet neu. Jede Datei
## aus der ZIP wird geprüft (nur bekannte Orte, keine Pfade nach draußen) – auch eine fremde oder
## veränderte Sicherung kann nichts außerhalb des Datenordners anlegen.
##
## Außerdem: einmal am Tag eine Kopie der Einstellungen (settings-JJJJ-MM-TT.json, die letzten 7).
## Ist settings.json samt .bak/.tmp unlesbar, nimmt Config die neueste Kopie. Mit Profilen (Roadmap
## 109) gilt das je Profil (profiles/<id>/backups) und für die gemeinsamen Einstellungen
## (gemeinsam-JJJJ-MM-TT.json). Die Daten der Profile (profiles/<id>/…, nur *.json, ohne
## Zwischenspeicher und Tresor-Schlüssel) kommen in jede Sicherung.

const Lang := preload("res://src/core/lang.gd")
const Profiles := preload("res://src/core/profiles.gd")
## Bestätigungen der eigenen Apps auf diesem PC (AppsExtern.OK_FILE) – fallen beim Wiederherstellen weg.
const APPS_OK := "cache/apps_ok.json"

const DIR := "backups"
const ROOT_EXT := ["json"]                 ## Dateien direkt im Datenordner
const DIRS := ["media", "sounds", "movies", "profiles"]  ## Ordner, die mitkommen
const SKIP_DIRS := ["movies/runtime"]
const MAX_FILE := 64 * 1024 * 1024         ## größere Einzeldateien bleiben draußen
const MAX_TOTAL := 512 * 1024 * 1024       ## darüber kommen nur noch die Daten-Dateien (*.json) mit
const RESTORE_MAX := 4 * MAX_TOTAL         ## entpackt mehr als das: keine Sicherung von Uzai, nicht zurückschreiben
const VERZEICHNIS_MAX := 64 * 1024 * 1024  ## größtes Inhaltsverzeichnis einer Sicherung, das Uzai liest
const KEEP_AUTO := 5                       ## automatische Sicherungen (vor Updates)
const KEEP_SNAPSHOTS := 7
const PENDING := "backups/wiederherstellen.json"


static func dir_of(data_dir: String) -> String:
	return data_dir.path_join(DIR)


## Darf dieser Pfad (relativ zum Datenordner, mit „/“) in einer Sicherung stehen bzw. aus ihr
## zurückgeschrieben werden? Nur bekannte Orte, nie nach oben oder absolut.
static func allowed(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.contains("\\") or rel.contains(":") or rel.to_utf8_buffer().has(0):
		return false
	var parts := rel.split("/")
	for p in parts:
		if p == "" or p == "." or p == "..":
			return false
	if parts.size() == 1:
		return rel.get_extension().to_lower() in ROOT_EXT and not rel.ends_with(".tmp")
	if not parts[0] in DIRS:
		return false
	if parts[0] == "profiles":
		# Nur Daten eines Profils mit gültiger Kennung, keine Zwischenspeicher, keine eigenen
		# Sicherungen und nie die Tresor-Schlüssel (die gehören zu diesem Windows-Konto).
		return parts.size() >= 3 and Profiles.valid_id(parts[1]) and not parts[2] in ["cache", "backups"] \
			and rel.get_extension().to_lower() == "json"
	for s in SKIP_DIRS:
		if rel.begins_with(s + "/"):
			return false
	return true


## Alle Dateien, die in eine Sicherung gehören (relativ, mit „/“).
static func collect(data_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(data_dir):
		if allowed(f):
			out.append(f)
	for d in DIRS:
		_walk(data_dir, d, out)
	return out


static func _walk(data_dir: String, rel: String, out: PackedStringArray) -> void:
	var abs_dir := data_dir.path_join(rel)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for f in DirAccess.get_files_at(abs_dir):
		var r := rel + "/" + f
		if allowed(r):
			out.append(r)
	for d in DirAccess.get_directories_at(abs_dir):
		var rd := rel + "/" + d
		if not rd in SKIP_DIRS:
			_walk(data_dir, rd, out)


## Neue Sicherung anlegen. reason: „hand“ (vom Nutzer) oder „update-<alt>-<neu>“. grenze: nur für Proben kleiner.
## { ok, path, files, bytes, skipped, error }
## Die Daten-Dateien (*.json: Einstellungen, Bibliothek, Profile, Spielzeit) kommen zuerst und immer mit; die
## Gesamtgrenze gilt nur für Bilder, Klänge und Filme. Vorher galt sie für alles mit „/“ im Pfad – war der
## Medienordner groß, fehlten still alle Profile (sie kamen als Letztes dran), und die Sicherung meldete „ok“.
static func create(data_dir: String, reason := "hand", now := -1, grenze := MAX_TOTAL) -> Dictionary:
	var dir := dir_of(data_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var t := int(Time.get_unix_time_from_system()) if now < 0 else now
	var stamp := Time.get_datetime_string_from_unix_time(t).replace(":", "").replace("T", "-")
	var name := "uzai-sicherung-%s-%s.zip" % [stamp, reason.validate_filename().replace(" ", "")]
	var zip_path := dir.path_join(name)
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		return { "ok": false, "error": "Die Sicherung ließ sich nicht anlegen." }
	var n := 0
	var bytes := 0
	var skipped := 0
	var ganz := true
	var alle := Array(collect(data_dir))
	var daten := alle.filter(func(r: String) -> bool: return r.get_extension().to_lower() == "json")
	var rest := alle.filter(func(r: String) -> bool: return r.get_extension().to_lower() != "json")
	for rel: String in daten + rest:
		var abs_path := data_dir.path_join(rel)
		var f := FileAccess.open(abs_path, FileAccess.READ)
		if f == null:
			continue
		if f.get_length() > MAX_FILE or (bytes + f.get_length() > grenze and rel.get_extension().to_lower() != "json"):
			skipped += 1
			continue
		var buf := f.get_buffer(f.get_length())
		f.close()
		if z.start_file(rel) != OK or z.write_file(buf) != OK or z.close_file() != OK:
			ganz = false
			break
		n += 1
		bytes += buf.size()
	if z.close() != OK:
		ganz = false
	# Eine halbe Sicherung ist keine: lieber keine Datei als eine, auf die man sich verlässt und die nicht aufgeht.
	if not ganz:
		DirAccess.remove_absolute(zip_path)
		return { "ok": false, "error": "Die Sicherung ließ sich nicht ganz schreiben (Platte voll?)." }
	if reason.begins_with("update"):
		prune(data_dir)
	return { "ok": true, "path": zip_path, "files": n, "bytes": bytes, "skipped": skipped, "error": "" }


## Sicherungen, neueste zuerst: [{ path, name, at (Unix), size, auto }]
static func list(data_dir: String) -> Array:
	var out: Array = []
	var dir := dir_of(data_dir)
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if not (f.begins_with("uzai-sicherung-") and f.ends_with(".zip")):
			continue
		var p := dir.path_join(f)
		var fa := FileAccess.open(p, FileAccess.READ)
		var size := fa.get_length() if fa else 0
		if fa:
			fa.close()
		out.append({ "path": p, "name": f, "at": FileAccess.get_modified_time(p), "size": size, "auto": f.contains("-update") })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) > int(b.at) or (int(a.at) == int(b.at) and str(a.name) > str(b.name)))
	return out


## Eine Sicherung löschen – nur eine echte Sicherungsdatei direkt im Ordner der Sicherungen, keine
## Verknüpfung, und der Ordner selbst keine Verknüpfung nach draußen. true, wenn sie weg ist.
static func remove(data_dir: String, path: String) -> bool:
	var dir := dir_of(data_dir).simplify_path()
	var f := path.get_file()
	if path.simplify_path() != dir.path_join(f) or not (f.begins_with("uzai-sicherung-") and f.ends_with(".zip")):
		return false
	var top := DirAccess.open(data_dir)
	var da := DirAccess.open(dir)
	if top == null or da == null or top.is_link(DIR) or da.is_link(f) or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## Automatische Sicherungen begrenzen (die eigenen bleiben alle).
static func prune(data_dir: String, keep := KEEP_AUTO) -> void:
	var autos := list(data_dir).filter(func(b: Dictionary) -> bool: return bool(b.auto))
	for i in range(keep, autos.size()):
		DirAccess.remove_absolute(str(autos[i].path))


## Wiederherstellen beim nächsten Start vormerken.
static func schedule_restore(data_dir: String, zip_path: String) -> bool:
	if not FileAccess.file_exists(zip_path) or not zip_path.get_base_dir().simplify_path() == dir_of(data_dir).simplify_path():
		return false
	return Config.write_json(data_dir.path_join(PENDING), { "zip": zip_path.get_file() })


## Vorgemerktes Wiederherstellen ausführen (vor dem Laden der Einstellungen). "" = nichts zu tun,
## sonst ein Satz für das Protokoll bzw. den Hinweis nach dem Start.
static func apply_pending_restore(data_dir: String) -> String:
	var marker := data_dir.path_join(PENDING)
	if not FileAccess.file_exists(marker):
		return ""
	var m: Variant = Config.read_json(marker, {})
	DirAccess.remove_absolute(marker)
	var name := str((m as Dictionary).get("zip", "")) if m is Dictionary else ""
	if name == "" or name.contains("/") or name.contains("\\") or name.contains(".."):
		return "Wiederherstellen abgebrochen: ungültige Angabe."
	return restore_now(data_dir, dir_of(data_dir).path_join(name))


## Größen aus dem Inhaltsverzeichnis einer ZIP-Datei, ohne etwas zu entpacken:
## { ok, groesste, gesamt, dateien }. Der Leser der Engine legt je Datei genau so viel Speicher an, wie dort steht –
## das ist also die Obergrenze. ok = false: kein ZIP, ZIP64 oder unsinnige Angaben (so etwas legt Uzai nicht an).
static func zip_groessen(zip_path: String) -> Dictionary:
	var nein := { "ok": false, "groesste": 0, "gesamt": 0, "dateien": 0 }
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return nein
	var n := f.get_length()
	if n < 22:
		return nein
	var ende := mini(n, 65536 + 22)
	f.seek(n - ende)
	var t := f.get_buffer(ende)
	var e := -1
	for i in range(t.size() - 22, -1, -1):
		if t[i] == 0x50 and t[i + 1] == 0x4b and t[i + 2] == 0x05 and t[i + 3] == 0x06:
			e = i
			break
	if e < 0:
		return nein
	# ZIP64: Der Leser der Engine (minizip) nimmt dann das ZIP64-Verzeichnis – eine präparierte Datei zeigte hier ein
	# harmloses klassisches Verzeichnis und ihm eines mit Dateien bis 4 GB. Uzai legt nie ZIP64 an: ablehnen.
	for i in range(0, t.size() - 3):
		if t[i] == 0x50 and t[i + 1] == 0x4b and t[i + 2] == 0x06 and (t[i + 3] == 0x06 or t[i + 3] == 0x07):
			return nein
	var anzahl := t.decode_u16(e + 10)
	var cd_groesse := t.decode_u32(e + 12)
	var cd_ab := t.decode_u32(e + 16)
	if anzahl == 0xFFFF or cd_ab == 0xFFFFFFFF or cd_groesse > VERZEICHNIS_MAX or cd_ab + cd_groesse > n:
		return nein
	f.seek(cd_ab)
	var cd := f.get_buffer(cd_groesse)
	var p := 0
	var out := { "ok": true, "groesste": 0, "gesamt": 0, "dateien": 0 }
	while int(out.dateien) < anzahl:
		if p + 46 > cd.size() or cd.decode_u32(p) != 0x02014b50:
			return nein
		var entpackt := cd.decode_u32(p + 24)
		if entpackt == 0xFFFFFFFF:
			return nein
		out.groesste = maxi(int(out.groesste), entpackt)
		out.gesamt = int(out.gesamt) + entpackt
		out.dateien = int(out.dateien) + 1
		p += 46 + cd.decode_u16(p + 28) + cd.decode_u16(p + 30) + cd.decode_u16(p + 32)
	return out


## ZIP in den Datenordner zurückschreiben (nur erlaubte Pfade). Vorher wird der jetzige Stand
## selbst gesichert („vor-wiederherstellen“), damit sich auch das rückgängig machen lässt.
static func restore_now(data_dir: String, zip_path: String) -> String:
	# Erst die Größen aus dem Inhaltsverzeichnis, ohne etwas zu entpacken: Eine präparierte Datei im
	# Sicherungsordner, die entpackt riesig wäre, füllte sonst den Arbeitsspeicher.
	var gr := zip_groessen(zip_path)
	if not bool(gr.ok):
		return "Die Sicherung ließ sich nicht öffnen."
	if int(gr.groesste) > MAX_FILE or int(gr.gesamt) > RESTORE_MAX:
		return "Die Sicherung ist größer, als Uzai sie anlegt – nichts zurückgeschrieben."
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return "Die Sicherung ließ sich nicht öffnen."
	var files := z.get_files()
	# Sieht der Leser der Engine ein anderes Verzeichnis als zip_groessen (mehr oder weniger Dateien), gelten die
	# geprüften Größen nicht: nichts lesen.
	if files.size() != int(gr.dateien):
		z.close()
		return "Die Sicherung ist größer, als Uzai sie anlegt – nichts zurückgeschrieben."
	var bad := 0
	for rel in files:
		if not allowed(rel):
			bad += 1
	if files.is_empty() or bad == files.size():
		z.close()
		return "Die Sicherung enthält nichts, was Uzai zurückschreiben darf."
	var vorher := create(data_dir, "vor-wiederherstellen")
	if not bool(vorher.ok):
		z.close()
		return "Wiederherstellen abgebrochen: Der jetzige Stand ließ sich vorher nicht sichern (Platte voll?)."
	var n := 0
	for rel in files:
		if not allowed(rel):
			continue
		var dest := data_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(z.read_file(rel))
		f.close()
		n += 1
	z.close()
	# Eigene Apps (Store-Apps, Programme) fragen danach vor dem nächsten Start wieder nach – die
	# Sicherung kann andere enthalten als die, die du hier bestätigt hast (src/core/apps_extern.gd).
	for suf: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(data_dir.path_join(APPS_OK) + suf):
			DirAccess.remove_absolute(data_dir.path_join(APPS_OK) + suf)
	return "Sicherung %s zurückgeholt (%d %s%s)." % [zip_path.get_file(), n, "Datei" if n == 1 else "Dateien", (", %d übersprungen" % bad) if bad > 0 else ""]


## Einmal am Tag die Einstellungen kopieren (die letzten KEEP_SNAPSHOTS bleiben). stem: Name der
## Datei ohne .json („settings“, die gemeinsamen „gemeinsam“).
static func snapshot_settings(data_dir: String, now := -1, stem := "settings") -> void:
	var src := data_dir.path_join(stem + ".json")
	if not FileAccess.file_exists(src) or Config.read_json(src, null) == null:
		return
	var dir := dir_of(data_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var t := int(Time.get_unix_time_from_system()) if now < 0 else now
	var day := Time.get_date_string_from_unix_time(t)
	var dest := dir.path_join("%s-%s.json" % [stem, day])
	if FileAccess.file_exists(dest):
		return
	if DirAccess.copy_absolute(src, dest) != OK:
		# Halbe Kopie (Platte voll): weg damit, sonst gälte sie als die Kopie dieses Tages.
		DirAccess.remove_absolute(dest)
		return
	var snaps := snapshots(data_dir, stem)
	for i in range(KEEP_SNAPSHOTS, snaps.size()):
		DirAccess.remove_absolute(dir.path_join(snaps[i]))


## Tägliche Kopien, neueste zuerst (Dateinamen).
static func snapshots(data_dir: String, stem := "settings") -> Array:
	var dir := dir_of(data_dir)
	if not DirAccess.dir_exists_absolute(dir):
		return []
	var out: Array = Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.begins_with(stem + "-") and f.ends_with(".json"))
	out.sort()
	out.reverse()
	return out


## Neueste lesbare Kopie der Einstellungen ({} wenn keine).
static func latest_settings(data_dir: String, stem := "settings") -> Dictionary:
	for f in snapshots(data_dir, stem):
		var v: Variant = Config.read_json(dir_of(data_dir).path_join(f), null)
		if v is Dictionary:
			return { "file": f, "data": v }
	return {}


## Größe lesbar („12,4 MB“).
static func size_text(b: int) -> String:
	if b >= 1048576:
		return Lang.dec("%.1f MB" % (b / 1048576.0))
	return "%d KB" % maxi(1, int(ceil(b / 1024.0)))

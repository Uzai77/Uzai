extends RefCounted
## Spielstände für Emulatoren – wie Quick Resume auf der Xbox, nur mit den Spielständen der
## Emulatoren. Beendet man ein Emulatorspiel über Uzai (Guide → Spiel beenden), merkt sich Uzai die
## Stelle: Es drückt das Speichern-Kürzel des Emulators, sucht die eben geschriebene Datei, legt eine
## Kopie in seiner eigenen Ablage ab (quickresume/) und stellt den Platz des Emulators so wieder her,
## wie er vorher war. Beim nächsten Start steht auf der Spielseite „Weiter, wo du warst“ vorn, daneben
## „Neu starten“: Uzai startet den Emulator dann mit dem Parameter, der einen Stand beim Start lädt.
##
## Mehrere Stände je Spiel: die letzten AUTO_MAX vom Beenden (der älteste geht, wenn ein neuer kommt)
## und bis zu OWN_MAX selbst gesicherte (Guide → Sichern; nie verdrängt). „Spielstände“ auf der
## Spielseite und „Laden“ im Guide zeigen alle mit Bild und Zeit. Uzai löscht dabei nur in seiner
## eigenen Ablage, nie Spielstände des Emulators.
##
## Nur für Emulatoren, die einen Spielstand beim Start per Kommandozeile laden (aus ihrem
## Quelltext geprüft, Stand Oktober 2026):
## - DuckStation  -statefile <datei>   (Speichern-Kürzel ab Werk F2)
## - PCSX2        -statefile <datei>   (F1)
## - PPSSPP       --state=<datei>      (F2)
## - Dolphin      -s <datei>           (Umschalt+F1)
## - RetroArch    -e <platz>           (F2). RetroArch lädt nur nach Platznummer: Uzai legt für den
##                Start eine Kopie als „<spiel>.state<N>.entry“ neben den Platz N, auf dem das Kürzel
##                speicherte (RetroArch zeigt sie nicht als Platz an), und räumt sie nach dem Spiel weg.
## Alle anderen (mGBA, Ryubing, Cemu, xemu …) können beim Start keinen Stand laden oder speichern
## nicht über ein Kürzel – dort bleibt es bei „Spielen“ und den Kürzeln des Emulators im Guide.

const DiscSerial := preload("res://src/library/disc_serial.gd")
const Lang := preload("res://src/core/lang.gd")

const DIR := "quickresume"
const INDEX := "quickresume/index.json"
const WAIT_MS := 9000        ## so lange auf die Datei des Emulators warten
const AUTO_MAX := 3          ## so viele Stände vom Beenden je Spiel
const OWN_MAX := 12          ## so viele selbst gesicherte Stände je Spiel
## "Continue where you left off" (remember the position on quit and offer it) is disabled: having both
## "Beenden" and "Nur beenden" was confusing. Own save states (save/load in the Guide) remain; the
## restart with a new controller assignment (spieler_controller.gd) still uses record(g, true).
const WEITER_ANBIETEN := false
const BACKUP_MAX := 24       ## höchstens so viele Dateien vorher sichern

## Ordner, in denen der Emulator seine Spielstände ablegt ({emudir} = Ordner der .exe; die
## anderen sind die Windows-Ordner Dokumente, AppData\Roaming und AppData\Local). Uzai sucht in
## allen, die es gibt, bis zwei Ebenen tief (RetroArch sortiert auf Wunsch nach Kern).
const PROFILES := {
	"duckstation": {
		"load": "-statefile \"{state}\"", "pattern": "\\.sav$",
		"dirs": ["{emudir}/savestates", "{localappdata}/DuckStation/savestates", "{documents}/DuckStation/savestates", "{appdata}/DuckStation/savestates"],
	},
	"pcsx2": {
		"load": "-statefile \"{state}\"", "pattern": "\\.p2s$",
		"dirs": ["{emudir}/sstates", "{documents}/PCSX2/sstates", "{appdata}/PCSX2/sstates", "{localappdata}/PCSX2/sstates"],
	},
	"ppsspp": {
		"load": "--state=\"{state}\"", "pattern": "\\.ppst$",
		"dirs": ["{emudir}/memstick/PSP/PPSSPP_STATE", "{documents}/PPSSPP/PSP/PPSSPP_STATE"],
	},
	"dolphin": {
		"load": "-s \"{state}\"", "pattern": "\\.s\\d\\d$",
		"dirs": ["{emudir}/User/StateSaves", "{appdata}/Dolphin Emulator/StateSaves", "{documents}/Dolphin Emulator/StateSaves"],
	},
	"retroarch": {
		"mode": "entry", "pattern": "\\.state\\d*$",
		"dirs": ["{emudir}/states", "{appdata}/RetroArch/states"],
	},
}


## Für die Einstellungen: wie es je Emulator geht.
const NOTES := {
	"duckstation": "Speichert über %s auf den gewählten Platz, Uzai legt eine Kopie ab und startet sie mit -statefile. Sucht in savestates neben der .exe (portabel), in AppData\\Local\\DuckStation und Dokumente\\DuckStation.",
	"pcsx2": "Speichert über %s, Uzai startet die Kopie mit -statefile. Sucht in sstates neben der .exe (portabel) und in Dokumente\\PCSX2.",
	"ppsspp": "Speichert über %s, Uzai startet die Kopie mit --state=. Sucht in memstick\\PSP\\PPSSPP_STATE neben der .exe und in Dokumente\\PPSSPP.",
	"dolphin": "Speichert über %s, Uzai startet die Kopie mit -s. Sucht in User\\StateSaves neben der .exe (portabel), in AppData\\Roaming und Dokumente unter „Dolphin Emulator“.",
	"retroarch": "Speichert über %s; RetroArch lädt beim Start nur nach Platznummer (-e). Uzai legt zum Start eine eigene Einstiegsdatei (.entry) neben diesen Platz und räumt sie danach weg, der Platz selbst bleibt. Sucht in states neben der .exe.",
}

# --- Welche Spiele -----------------------------------------------------------------------

## Emulator eines Spiels (eigene Wahl am Spiel, sonst der des Systems).
static func emulator_id(g: Dictionary) -> String:
	return str(g.get("emulator", Config.system(str(g.get("system", ""))).get("emulator", "")))


static func profile(emu_id: String) -> Dictionary:
	return PROFILES.get(emu_id, {})


static func describe(emu_id: String, key: String) -> String:
	var t := str(NOTES.get(emu_id, ""))
	if t == "":
		return ""
	return t % (key.to_upper() if key != "" else "das Speichern-Kürzel (unter Emulatoren eintragen)")


## Gehen Spielstände für dieses Spiel? (Emulator mit Profil und Speichern-Kürzel, Einstellung an)
static func supported(g: Dictionary) -> bool:
	if str(g.get("source", "rom")) != "rom" or not bool(Config.get_value("rest.quick_resume", true)):
		return false
	# Disc direkt vom Laufwerk (src/core/discs.gd): Sie hinterlässt nichts, auch keine Stände.
	if str(g.get("id", "")).begins_with("disc:"):
		return false
	var emu_id := emulator_id(g)
	if profile(emu_id).is_empty():
		return false
	var keys: Variant = Config.emulator(emu_id).get("keys", {})
	return keys is Dictionary and str((keys as Dictionary).get("save", "")).strip_edges() != ""


# --- Ordner und Dateien --------------------------------------------------------------------

## Windows-Ordner für die Platzhalter (leer, wo es sie nicht gibt).
static func env_dirs() -> Dictionary:
	return {
		"documents": OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		"appdata": OS.get_environment("APPDATA"),
		"localappdata": OS.get_environment("LOCALAPPDATA"),
	}


## Platzhalter in den Ordnern eines Profils ersetzen. Ordner mit unbekanntem oder leerem
## Platzhalter fallen weg; doppelte (gleich bis auf Groß/Klein und Trenner) nur einmal.
static func expand_dirs(prof: Dictionary, exe: String, env: Dictionary) -> Array:
	var vals := { "emudir": exe.get_base_dir() if exe != "" else "" }
	for k in env.keys():
		vals[str(k)] = str(env[k])
	var out: Array = []
	var seen := {}
	for d in prof.get("dirs", []):
		var s := str(d)
		var ok := true
		for k in vals.keys():
			var tag := "{%s}" % k
			if s.contains(tag):
				if str(vals[k]).strip_edges() == "":
					ok = false
					break
				s = s.replace(tag, str(vals[k]).trim_suffix("/").trim_suffix("\\"))
		if not ok or s.contains("{"):
			continue
		s = s.replace("\\", "/")
		var key := s.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(s)
	return out


## Spielstände in den Ordnern: Pfad → [Änderungszeit, Größe]. depth: Unterordner-Tiefe.
static func scan(dirs: Array, pattern: String, depth := 2) -> Dictionary:
	var re := RegEx.new()
	re.compile("(?i)" + pattern)
	var out := {}
	for d in dirs:
		_scan_dir(str(d), re, depth, out)
	return out


static func _scan_dir(dir: String, re: RegEx, depth: int, out: Dictionary) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if re.search(f) == null:
			continue
		var p := dir.path_join(f)
		out[p] = [FileAccess.get_modified_time(p), _size(p)]
		if out.size() > 4000:
			return
	if depth > 0:
		for sub in da.get_directories():
			_scan_dir(dir.path_join(sub), re, depth - 1, out)


static func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


## Die Datei, die zwischen zwei Blicken neu kam oder sich änderte (die jüngste, "" wenn keine).
static func changed_file(before: Dictionary, after: Dictionary) -> String:
	var best := ""
	var best_t := -1
	for p in after.keys():
		var a: Array = after[p]
		var changed: bool = not before.has(p) or int((before[p] as Array)[0]) != int(a[0]) or int((before[p] as Array)[1]) != int(a[1])
		if changed and int(a[1]) > 0 and int(a[0]) > best_t:
			best_t = int(a[0])
			best = str(p)
	return best


## Woran man die Spielstände dieses Spiels im Dateinamen erkennt: Name der Spieldatei (RetroArch,
## mGBA …) und die Seriennummer (DuckStation „SLES-50330_1.sav“, PCSX2 „SLES-50330 (…).01.p2s“).
static func name_tokens(g: Dictionary) -> Array:
	var out: Array = []
	var base := str(g.get("path", "")).get_file().get_basename().to_lower()
	if base.length() >= 4:
		out.append(base)
	var serial := str(g.get("serial", ""))
	if serial == "":
		serial = DiscSerial.from_name(str(g.get("path", "")))
	if serial != "":
		out.append(serial.to_lower())
		out.append(serial.to_lower().replace("-", "_"))
	return out


## Dateien, die Uzai vor dem Speichern sichert, damit der Platz des Emulators danach wieder so ist
## wie vorher: die Datei vom letzten Mal (known) und alle, die zum Spiel gehören.
static func backup_candidates(before: Dictionary, tokens: Array, known: String) -> Array:
	var out: Array = []
	if known != "" and before.has(known):
		out.append(known)
	for p in before.keys():
		if out.size() >= BACKUP_MAX:
			break
		var name := str(p).get_file().to_lower()
		for t in tokens:
			if str(t).length() >= 4 and name.contains(str(t)) and not out.has(p):
				out.append(p)
				break
	return out


## RetroArch: aus dem gespeicherten Platz („Spiel.state3“) die Einstiegsdatei und die Platznummer.
## { path: „Spiel.state3.entry“, slot: 3 } – {} wenn der Name nicht passt.
static func entry_for(state_file: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^(.*\\.state)(\\d*)$")
	var m := re.search(state_file)
	if m == null:
		return {}
	var slot := int(m.get_string(2)) if m.get_string(2) != "" else 0
	return { "path": "%s%d.entry" % [m.get_string(1), slot], "slot": slot }


# --- Gespeicherte Stände -------------------------------------------------------------------
# index.json: Spiel-ID → { states: [Stand …] (neuester vorn), stale: bool }. Ein Stand ist
# { id, kind: "auto" | "own", emulator, at, file, slot_file, slot?, shot?, title }. Dazu unter
# „_entries“ die Einstiegsdateien, die Uzai für RetroArch angelegt hat, und unter „_offen“ die
# Plätze des Emulators, die gerade vertreten werden (siehe journal_put/recover).
# Frühere Fassung: Spiel-ID → ein einzelner Stand – wird beim ersten Lesen übernommen.

static var _idx: Dictionary = {}
static var _idx_path := ""    ## für welche Datei _idx gilt (Tests wechseln den Datenordner)


## Alles aus index.json (übernommen aus der alten Form). Nur Uzai schreibt die Datei, darum genügt
## einmal lesen (die Startseite fragt bei jedem Cover).
static func index() -> Dictionary:
	var p := Config.path(INDEX)
	if p != _idx_path:
		var d: Variant = Config.read_json(p, {})
		_idx = d if d is Dictionary else {}
		_idx_path = p
		if migrate(_idx):
			_save_index(_idx)
	return _idx


## Alte Einträge (ein Stand je Spiel) in die Liste übernehmen. RetroArchs Einstiegsdatei lag
## früher selbst im Ordner des Emulators: Sie kommt als Kopie in Uzais Ordner und wird später
## (nach dem nächsten Spielende) aufgeräumt. true, wenn sich etwas geändert hat.
static func migrate(d: Dictionary) -> bool:
	var changed := false
	var entries: Array = d.get("_entries", []) if d.get("_entries") is Array else []
	for gid in d.keys():
		if str(gid).begins_with("_"):
			continue
		var v: Variant = d[gid]
		if not (v is Dictionary):
			d.erase(gid)
			changed = true
			continue
		if (v as Dictionary).has("states"):
			continue
		var rec: Dictionary = (v as Dictionary).duplicate()
		rec["kind"] = "auto"
		rec["id"] = new_id(int(rec.get("at", 0)))
		var f := str(rec.get("file", ""))
		if f.get_extension().to_lower() == "entry":
			entries.append(f)
			var copy := Config.path(DIR).path_join("%s_%s.%s" % [_safe(str(gid)), str(rec.id), str(rec.get("slot_file", "x.state")).get_extension()])
			if FileAccess.file_exists(f) and DirAccess.copy_absolute(f, copy) == OK:
				rec["file"] = copy
		d[gid] = { "states": [rec], "stale": false }
		changed = true
	if changed:
		d["_entries"] = entries
	return changed


static func _save_index(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(Config.path(DIR))
	_idx = d
	_idx_path = Config.path(INDEX)
	Config.write_json(Config.path(INDEX), d, "\t")


static func _safe(s: String) -> String:
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["-", "_"] else "_"
	return out if out != "" else "spiel"


## Kurze eindeutige Kennung eines Stands („1730000000a1b2“).
static func new_id(at: int) -> String:
	return "%d%04x" % [at, randi() % 65536]


static func _entry(gid: String) -> Dictionary:
	var e: Variant = index().get(gid, {})
	if not (e is Dictionary) or not (e as Dictionary).has("states"):
		return { "states": [], "stale": false }
	return e


## Alle Stände eines Spiels, die noch passen (gleicher Emulator, Datei da), neuester vorn.
## kind: "" alle, "auto" (beim Beenden gemerkt) oder "own" (selbst gesichert).
static func states(g: Dictionary, kind := "") -> Array:
	if g.is_empty() or not supported(g):
		return []
	var emu := emulator_id(g)
	var out: Array = []
	for r in _entry(str(g.get("id", ""))).states:
		if r is Dictionary and valid(r, emu) and (kind == "" or str(r.get("kind", "auto")) == kind):
			out.append(r)
	out.sort_custom(func(a, b): return int(a.get("at", 0)) > int(b.get("at", 0)))
	return out


## Der Stand für „Weiter, wo du warst“: der jüngste beim Beenden gemerkte – nur, wenn seither nicht
## anders weitergespielt wurde (stale). {} sonst.
static func record(g: Dictionary, intern := false) -> Dictionary:
	if not WEITER_ANBIETEN and not intern:
		return {}
	var autos := states(g, "auto")
	if autos.is_empty() or bool(_entry(str(g.get("id", ""))).get("stale", false)):
		return {}
	return autos[0]


static func valid(rec: Dictionary, emu_id: String) -> bool:
	return str(rec.get("emulator", "")) == emu_id and str(rec.get("file", "")) != "" and FileAccess.file_exists(str(rec.get("file", "")))


## Wie viele eigene Plätze das Spiel schon belegt (auch mit anderem Emulator angelegte zählen).
static func own_count(gid: String) -> int:
	var n := 0
	for r in _entry(gid).states:
		if r is Dictionary and str(r.get("kind", "")) == "own":
			n += 1
	return n


static func own_full(gid: String) -> bool:
	return own_count(gid) >= OWN_MAX


## Neuen Stand ablegen. Automatische: höchstens AUTO_MAX, der älteste geht (nur Uzais Kopie), und
## „Weiter, wo du warst“ gilt wieder. Eigene: nie verdrängt – voll ist voll (own_full).
## Gibt den abgelegten Stand zurück ({} wenn kein Platz war).
static func add(gid: String, rec: Dictionary, kind := "auto") -> Dictionary:
	var d := index()
	var e := _entry(gid).duplicate(true)
	if kind == "own" and own_full(gid):
		return {}
	var r := rec.duplicate()
	r["kind"] = kind
	if str(r.get("id", "")) == "":
		r["id"] = new_id(int(r.get("at", 0)))
	var list: Array = e.states
	list.push_front(r)
	if kind == "auto":
		e["stale"] = false
		var autos: Array = list.filter(func(x): return x is Dictionary and str(x.get("kind", "auto")) == "auto")
		autos.sort_custom(func(a, b): return int(a.get("at", 0)) > int(b.get("at", 0)))
		for old in autos.slice(AUTO_MAX):
			list.erase(old)
			_remove_files(old)
	e["states"] = list
	d[gid] = e
	_save_index(d)
	return r


## Einen Stand entfernen – nur Uzais eigene Kopie und ihr Bild, nie etwas im Ordner des Emulators.
static func remove(gid: String, sid: String) -> void:
	var d := index()
	var e := _entry(gid).duplicate(true)
	var list: Array = e.states
	for r in list.duplicate():
		if r is Dictionary and str(r.get("id", "")) == sid:
			list.erase(r)
			_remove_files(r)
	e["states"] = list
	d[gid] = e
	_save_index(d)


## Spiel anders weitergespielt (im Emulator beendet, „Nur beenden“, Absturz): Die gemerkte Stelle ist
## jetzt älter als der Fortschritt. Sie bleibt in der Liste, „Weiter, wo du warst“ steht aber nicht
## mehr vorn.
static func mark_stale(gid: String) -> void:
	var d := index()
	if not d.has(gid):
		return
	var e := _entry(gid).duplicate(true)
	if (e.states as Array).is_empty() or bool(e.stale):
		return
	e["stale"] = true
	d[gid] = e
	_save_index(d)


static func is_own_file(p: String) -> bool:
	var root := Config.path(DIR).simplify_path().to_lower() + "/"
	return p != "" and p.replace("\\", "/").simplify_path().to_lower().begins_with(root)


static func _remove_files(rec: Variant) -> void:
	if not (rec is Dictionary):
		return
	for k in ["file", "shot"]:
		var p := str((rec as Dictionary).get(k, ""))
		if is_own_file(p) and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Jüngster Stand für „Weiter, wo du warst“ aus der ganzen Bibliothek: { game, rec } oder {}.
static func latest() -> Dictionary:
	var best := {}
	var d := index()
	for gid in d.keys():
		if str(gid).begins_with("_"):
			continue
		var g: Dictionary = Library.get_game(str(gid))
		if g.is_empty():
			continue
		var rec := record(g)
		if rec.is_empty():
			continue
		if best.is_empty() or int(rec.get("at", 0)) > int((best.rec as Dictionary).get("at", 0)):
			best = { "game": g, "rec": rec }
	return best


# --- Plätze des Emulators vertreten ---------------------------------------------------------
# Beim Sichern und beim Laden im Spiel liegt kurz etwas anderes auf dem Platz des Emulators (beim
# Laden: Uzais Stand). Was dort vorher war, liegt so lange in quickresume/sicherung. Damit auch ein
# Absturz von Uzai nichts kostet, steht der Auftrag vorher in index.json („_offen“); recover() beim
# nächsten Start stellt den Platz wieder her.

## offen: [{ slot, backup ("" = vorher leer), ours (Größe der eingesetzten Datei, -1 = keine) }]
static func journal_put(offen: Array) -> void:
	var d := index()
	d["_offen"] = offen
	_save_index(d)


static func journal_clear() -> void:
	var d := index()
	if d.has("_offen"):
		d.erase("_offen")
		_save_index(d)


## Nach einem Absturz: Plätze des Emulators wieder so wie vorher. Eine von Uzai eingesetzte Datei
## (Laden) fliegt nur, wenn sie noch genau so groß ist wie eingesetzt – sonst hat der Emulator
## inzwischen selbst dorthin gespeichert, und das bleibt. Gibt die Zahl der Plätze zurück.
static func recover() -> int:
	var offen: Variant = index().get("_offen", [])
	var n := 0
	if offen is Array:
		for o in offen:
			if not (o is Dictionary):
				continue
			var slot := str(o.get("slot", ""))
			var backup := str(o.get("backup", ""))
			if slot == "" or is_own_file(slot):
				continue
			if backup != "" and is_own_file(backup) and FileAccess.file_exists(backup):
				# Mit „stand“ (der Platz ließ sich im Spiel nicht zurücklegen, Rest._spaeter_zurueck): nur, wenn der
				# Emulator seitdem nicht selbst dorthin gespeichert hat. Sonst bleibt sein neuerer Stand.
				if (o.get("stand") is int or o.get("stand") is float) and FileAccess.get_modified_time(slot) != int(o.stand):
					DirAccess.remove_absolute(backup)
					continue
				if DirAccess.copy_absolute(backup, slot) == OK:
					DirAccess.remove_absolute(backup)
					n += 1
			elif backup == "" and int(o.get("ours", -1)) >= 0 and FileAccess.file_exists(slot) and _size(slot) == int(o.ours):
				DirAccess.remove_absolute(slot)
				n += 1
	journal_clear()
	return n


# --- Starten mit einem Stand ----------------------------------------------------------------

## Parameter, die den Stand beim Start laden (kommen vor alle anderen, siehe Launcher._rom_command).
static func launch_args(rec: Dictionary) -> String:
	var prof := profile(str(rec.get("emulator", "")))
	if prof.is_empty():
		return ""
	if str(prof.get("mode", "file")) == "entry":
		return "-e %d" % int(rec.get("slot", 0))
	var file := str(rec.get("file", ""))
	if OS.get_name() == "Windows":
		file = file.replace("/", "\\")
	return str(prof.get("load", "")).replace("{state}", file)


## RetroArch lädt beim Start nur „<Spiel>.state<N>.entry“ neben seinen Plätzen: Uzai legt dort eine
## Kopie des gewählten Stands hin. Liegt dort schon eine fremde Datei, nicht anfassen (false).
static func prepare_entry(rec: Dictionary) -> bool:
	var e := entry_for(str(rec.get("slot_file", "")))
	if e.is_empty():
		return false
	var d := index()
	var entries: Array = d.get("_entries", []) if d.get("_entries") is Array else []
	var path := str(e.path)
	if FileAccess.file_exists(path) and not entries.has(path):
		return false
	if DirAccess.copy_absolute(str(rec.get("file", "")), path) != OK:
		return false
	if not entries.has(path):
		entries.append(path)
		d["_entries"] = entries
		_save_index(d)
	return true


## Nach dem Spiel: Uzais Einstiegsdateien bei RetroArch wieder weg (die Kopie bleibt in Uzais Ordner).
static func cleanup_entries() -> void:
	var d := index()
	var entries: Array = d.get("_entries", []) if d.get("_entries") is Array else []
	if entries.is_empty():
		return
	for p in entries:
		var s := str(p)
		if s.get_extension().to_lower() == "entry" and FileAccess.file_exists(s):
			DirAccess.remove_absolute(s)
	d.erase("_entries")
	_save_index(d)


## Spiel mit einem Stand starten: Kopie des Spiels mit den Ladeparametern ({} wenn es nicht geht).
static func resume_game(g: Dictionary, rec: Dictionary) -> Dictionary:
	if str(profile(str(rec.get("emulator", ""))).get("mode", "file")) == "entry" and str(rec.get("slot_file", "")) != "" \
			and not prepare_entry(rec):
		return {}
	var out := g.duplicate()
	out["_resume_args"] = launch_args(rec)
	return out


# --- Texte ---------------------------------------------------------------------------------

## „gerade eben“, „vor 12 Min.“, „vor 2 Std.“, „gestern“, „vor 3 Tagen“, „vor 2 Wochen“.
static func ago_short(secs: int) -> String:
	secs = maxi(secs, 0)
	if secs < 120:
		return "gerade eben"
	if secs < 3600:
		return "vor %d Min." % (secs / 60)
	if secs < 86400:
		return "vor %d Std." % (secs / 3600)
	var days := secs / 86400
	if days == 1:
		return "gestern"
	if days < 14:
		return "vor %d Tagen" % days
	return "vor %d Wochen" % (days / 7)


const RESUME_TEXT := "Weiter, wo du warst"


## Überschrift eines Stands in der Liste: „Heute, 14:32“, „Gestern, 20:10“, „3. Okt., 18:05“.
## bias_min: Abstand der Ortszeit zu UTC in Minuten.
static func when_text(at: int, now: int, bias_min: int) -> String:
	var la := at + bias_min * 60
	var ln := now + bias_min * 60
	var d := Time.get_datetime_dict_from_unix_time(la)
	var clock := "%02d:%02d" % [int(d.hour), int(d.minute)]
	var days := floori(ln / 86400.0) - floori(la / 86400.0)
	if days == 0:
		return "Heute, %s" % clock
	if days == 1:
		return "Gestern, %s" % clock
	return "%s, %s" % [Lang.date_text(int(d.day), int(d.month), 0, true), clock]


## Untertitel eines Stands in der Liste: „Beim Beenden · vor 2 Std.“, „Selbst gesichert · gestern“.
static func state_line(rec: Dictionary, now: int) -> String:
	var what := "Selbst gesichert" if str(rec.get("kind", "auto")) == "own" else "Beim Beenden"
	return "%s  ·  %s" % [what, ago_short(now - int(rec.get("at", now)))]


## Zeile auf der Startseite: „gemerkt vor 2 Std.“ ("" ohne gemerkte Stelle).
static func label_for(g: Dictionary) -> String:
	var rec := record(g)
	if rec.is_empty():
		return ""
	return "gemerkt %s" % ago_short(int(Time.get_unix_time_from_system()) - int(rec.get("at", 0)))


static func shot_texture(rec: Dictionary) -> Texture2D:
	var p := str(rec.get("shot", ""))
	if p == "" or not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null

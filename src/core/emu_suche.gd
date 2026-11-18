extends RefCounted
## Emulatoren finden (Einrichtung, Doktor): nicht nur unter „Programme“, sondern dort, wo sie
## wirklich liegen – eigene Ordner auf jedem Laufwerk (\Emulators, \Spiele, \Tools …), Desktop,
## Downloads, Dokumente, %LOCALAPPDATA%\Programs, Scoop, Chocolatey, WinGet, Steam (RetroArch),
## EmuDeck, RetroBat, LaunchBox; dazu die Ziele der Verknüpfungen im Startmenü und auf dem
## Desktop, Deinstallations-Einträge der Registry und laufende Programme (beides liefert der
## Helfer, nur gelesen: Befehl „emu-hints“, mit Versionsangaben der Programmdateien).
##
## Sicher und kurz: Es wird nur gelesen, nie etwas gestartet. Jeder Ort hat eine Tiefe, die ganze
## Suche höchstens MAX_DIRS Ordner und MAX_MS Millisekunden; Systemordner (Windows, Papierkorb …)
## bleiben außen vor. Erkannt wird über bekannte Programmnamen (pcsx2-qt.exe, Dolphin.exe …) und,
## bei Funden aus Registry und Prozessen, über die Versionsangaben (Produktname).
##
## Alles hier ist rein (Dateizugriffe über austauschbare Callables) und läuft in einem Faden.

const MAX_DIRS := 8000           ## so viele Ordner höchstens je Suche
const MAX_MS := 12000            ## … und so lange höchstens
const MAX_LNK := 1500            ## so viele Verknüpfungen höchstens
const LNK_MAX_BYTES := 65536     ## größere .lnk-Dateien sind keine echten Verknüpfungen

## Ordnernamen, in die die Suche nie hineinschaut (klein geschrieben).
const SKIP := ["windows", "$recycle.bin", "system volume information", "recovery", "perflogs", "$windows.~bt", "$windows.~ws",
	"$winreagent", "windowsapps", "winsxs", "node_modules", ".git", ".svn", "__pycache__", "temp", "tmp", "cache", "caches",
	"steamapps", "shadercache", "microsoft", "windows kits", "windows defender", "windows nt", "common files", "nvidia corporation",
	"nvidia", "intel", "amd", "packages", "crashdumps", "d3dscache", "google", "mozilla", "roms", "bios", "saves", "states",
	"screenshots", "shaders", "cores", "system", "assets", "resources", "translations", "locale", "lang", "plugins", "logs"]

## Programmnamen, die nie der Emulator selbst sind (Deinstallation, Updater, Absturzmelder …).
const NOT_EMU := ["unins", "uninstall", "update", "crash", "setup", "install", "vc_redist", "dxsetup", "elevate", "helper"]

## Zusätzliche Muster je Emulator (klein, * am Ende = beginnt mit). Exakte Namen aus exe_hint und
## Einrichtung.ALT_EXE kommen davor.
const MUSTER := {
	"pcsx2": ["pcsx2-qt*.exe", "pcsx2*.exe"],
	"duckstation": ["duckstation-qt*.exe", "duckstation*.exe"],
	"ppsspp": ["ppssppwindows*.exe"],
	"snes9x": ["snes9x*.exe"],
	"mesen": ["mesen*.exe"],
	"desmume": ["desmume*.exe"],
	"lime3ds": ["lime3ds*.exe"],
	"azahar": ["azahar*.exe"],
	"citra": ["citra-qt*.exe", "citra.exe"],
	"melonds": ["melonds*.exe"],
	"rpcs3": ["rpcs3*.exe"],
	"xemu": ["xemu*.exe"],
	"flycast": ["flycast*.exe"],
	"ryubing": ["ryujinx*.exe", "ryubing*.exe"],
	"retroarch": ["retroarch*.exe"],
	"dolphin": ["dolphin.exe"],
	"vbam": ["visualboyadvance-m*.exe", "vbam*.exe"],
	"simple64": ["simple64-gui*.exe"],
	"project64": ["project64*.exe"],
}

## Versionsangaben (Produktname, Beschreibung) → Emulator: nur für Funde aus Registry und
## Prozessen (dort ist der Programmname manchmal anders). Ganze Wörter, klein.
const PRODUKT := {
	"pcsx2": ["pcsx2"], "duckstation": ["duckstation"], "dolphin": ["dolphin emulator"], "retroarch": ["retroarch"],
	"ppsspp": ["ppsspp"], "cemu": ["cemu"], "rpcs3": ["rpcs3"], "ryubing": ["ryujinx", "ryubing"], "xemu": ["xemu"],
	"xenia": ["xenia canary"], "mgba": ["mgba"], "melonds": ["melonds"], "flycast": ["flycast"], "azahar": ["azahar"],
	"lime3ds": ["lime3ds"], "citra": ["citra"], "eden": ["eden"], "citron": ["citron"], "sudachi": ["sudachi"],
	"bizhawk": ["bizhawk", "emuhawk"], "ares": ["ares"], "mesen": ["mesen"], "snes9x": ["snes9x"], "project64": ["project64"],
	"simple64": ["simple64"], "redream": ["redream"], "desmume": ["desmume"], "cxbx": ["cxbx-reloaded", "cxbx"],
	"mednafen": ["mednafen"], "vbam": ["visualboyadvance-m"], "skyemu": ["skyemu"], "nanoboy": ["nanoboyadvance"],
}


# --- Erkennung über den Programmnamen --------------------------------------------------------

## Muster aller gesuchten Emulatoren: [[id, muster], …] – erst die genauen Namen aus exe_hint,
## dann die weiteren genauen (ALT_EXE), zuletzt die mit * (so gewinnt xenia.exe für „Xenia“, nicht
## für „Xenia Canary“, dessen Hinweis xenia_canary.exe ist).
static func patterns(emus: Array, alt_exe: Dictionary = {}) -> Array:
	var out: Array = []
	var seen := {}
	var add := func(id: String, m: String) -> void:
		var k := m.to_lower()
		if k == "" or seen.has(k):
			return
		seen[k] = true
		out.append([id, k])
	for e in emus:
		var hint := str(e.get("exe_hint", "")).replace("\\", "/").get_file()
		add.call(str(e.get("id", "")), hint)
	for e in emus:
		for a in alt_exe.get(str(e.get("id", "")), []):
			add.call(str(e.get("id", "")), str(a))
	for e in emus:
		for m in MUSTER.get(str(e.get("id", "")), []):
			add.call(str(e.get("id", "")), str(m))
	return out


static func is_helper_exe(file_name: String) -> bool:
	var n := file_name.to_lower()
	for w in NOT_EMU:
		if n.contains(w):
			return true
	return false


## Welcher Emulator gehört zu dieser Programmdatei? "" = keiner.
static func exe_id(file_name: String, pats: Array) -> String:
	var n := file_name.to_lower()
	if not n.ends_with(".exe") or is_helper_exe(n):
		return ""
	for p in pats:
		var m := str(p[1])
		if m.ends_with("*.exe"):
			if n.begins_with(m.trim_suffix("*.exe")):
				return str(p[0])
		elif n == m:
			return str(p[0])
	return ""


## Emulator nach Versionsangaben (Produktname oder Beschreibung), nur unter den gesuchten.
static func product_id(product: String, emus: Array) -> String:
	var text := " " + _words(product) + " "
	if text.strip_edges() == "":
		return ""
	for e in emus:
		var id := str(e.get("id", ""))
		for w in PRODUKT.get(id, []):
			if text.contains(" " + str(w) + " "):
				return id
	return ""


static func _words(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" else " "
	return " ".join(out.split(" ", false))


# --- Suchorte ------------------------------------------------------------------------------

## Suchorte mit Tiefe: [[pfad, tiefe], …], die wahrscheinlichsten zuerst (die Grenzen greifen
## hinten). drives: ["C:", "D:"], env: Umgebungsvariablen, steam_libs: Steam-Bibliotheken.
static func roots(drives: Array, env: Dictionary, steam_libs: Array = []) -> Array:
	var out: Array = []
	var home := _p(env.get("USERPROFILE", ""))
	var la := _p(env.get("LOCALAPPDATA", ""))
	var ad := _p(env.get("APPDATA", ""))
	var pd := _p(env.get("ProgramData", ""))
	# Eigene Emulator-Ordner und Sammlungen (EmuDeck, RetroBat, LaunchBox).
	for d in drives:
		var r := _p(d)
		for sub in ["Emulators", "Emulatoren", "Emulation", "Emulation/tools", "Emu", "Emus", "RetroBat/emulators", "LaunchBox/Emulators",
				"EmuDeck", "Games/Emulators", "Games/Emulatoren", "Spiele/Emulatoren", "Spiele/Emulators"]:
			out.append([r + "/" + sub, 3])
	if ad != "":
		out.append([ad + "/EmuDeck/Emulators", 3])
	if home != "":
		for sub in ["Emulators", "Emulatoren", "Emulation", "Desktop", "Downloads", "Documents", "OneDrive/Desktop", "OneDrive/Documents",
				"OneDrive/Dokumente", "Games", "Spiele", "Tools"]:
			out.append([home + "/" + sub, 3])
		# Scoop: <home>\scoop\apps\<app>\current\<exe>
		out.append([home + "/scoop/apps", 3])
	var scoop := _p(env.get("SCOOP", ""))
	if scoop != "":
		out.append([scoop + "/apps", 3])
	if pd != "":
		out.append([pd + "/scoop/apps", 3])
		# Chocolatey: lib\<paket>\tools\<ordner>\<exe>
		out.append([pd + "/chocolatey/lib", 4])
	if la != "":
		out.append([la + "/Programs", 3])
		# WinGet (portable Pakete): Packages\<Kennung>\<exe> oder eine Ebene tiefer.
		out.append([la + "/Microsoft/WinGet/Packages", 3])
		out.append([la, 2])
	for lib in steam_libs:
		out.append([_p(lib) + "/steamapps/common", 2])
	for k in ["ProgramFiles", "ProgramFiles(x86)"]:
		var p := _p(env.get(k, ""))
		if p != "":
			out.append([p, 2])
	# Allgemeine Ordner auf jedem Laufwerk, dann das Laufwerk selbst (flach).
	for d in drives:
		var r2 := _p(d)
		for sub in ["Games", "Spiele", "Tools", "Programme", "Programs", "Portable", "PortableApps", "Apps"]:
			out.append([r2 + "/" + sub, 3])
		# Laufwerk selbst: „C:/“ (ohne Schrägstrich hieße „C:“ der aktuelle Ordner dort).
		out.append([r2 + "/" if r2.length() == 2 and r2[1] == ":" else r2, 2])
	return _unique_roots(out)


## Startmenü und Desktop: hier liegen Verknüpfungen (.lnk).
static func lnk_roots(env: Dictionary) -> Array:
	var out: Array = []
	var ad := _p(env.get("APPDATA", ""))
	var pd := _p(env.get("ProgramData", ""))
	var home := _p(env.get("USERPROFILE", ""))
	var pub := _p(env.get("PUBLIC", ""))
	if ad != "":
		out.append([ad + "/Microsoft/Windows/Start Menu/Programs", 3])
	if pd != "":
		out.append([pd + "/Microsoft/Windows/Start Menu/Programs", 3])
	if home != "":
		out.append([home + "/Desktop", 1])
		out.append([home + "/OneDrive/Desktop", 1])
	if pub != "":
		out.append([pub + "/Desktop", 1])
	return _unique_roots(out)


static func _p(v: Variant) -> String:
	return str(v).replace("\\", "/").trim_suffix("/")


static func _join(dir: String, name: String) -> String:
	return dir + name if dir.ends_with("/") else dir + "/" + name


static func _unique_roots(list: Array) -> Array:
	var seen := {}
	var out: Array = []
	for r in list:
		var k := str(r[0]).to_lower()
		if str(r[0]) == "" or seen.has(k):
			continue
		seen[k] = true
		out.append(r)
	return out


## Unterordner bzw. Dateien eines Ordners – still: fehlt er oder ist er gesperrt (z. B. ein
## Systemordner ohne Leserecht), kommt eine leere Liste statt einer Fehlermeldung im Protokoll.
## DirAccess.get_*_at meldet jeden fehlenden Ordner als ERROR (landete im Fehlerbericht).
static func dirs_at(p: String) -> Array:
	var da := DirAccess.open(p) if p != "" else null
	return Array(da.get_directories()) if da != null else []


static func files_at(p: String) -> Array:
	var da := DirAccess.open(p) if p != "" else null
	return Array(da.get_files()) if da != null else []


# --- Suchen ----------------------------------------------------------------------------------

## Neues Budget für eine Suche (Ordner zählen, Zeit).
static func budget(max_dirs := MAX_DIRS, max_ms := MAX_MS) -> Dictionary:
	return { "dirs": 0, "max_dirs": max_dirs, "until": Time.get_ticks_msec() + max_ms, "seen": {} }


static func _over(b: Dictionary) -> bool:
	return int(b.dirs) >= int(b.max_dirs) or Time.get_ticks_msec() > int(b.until)


## Ordner durchgehen (Breite zuerst, mit Tiefe) und Programmdateien erkennen.
## list_dirs(pfad) / list_files(pfad) → Namen (zum Testen austauschbar). found: id → { exe, how }
## (der erste Fund je Emulator zählt). on_dir(pfad): Fortschritt (freiwillig).
static func walk(roots_: Array, pats: Array, list_dirs: Callable, list_files: Callable, b: Dictionary, found: Dictionary,
		how := "ordner", on_dir: Callable = Callable()) -> Dictionary:
	var want := {}
	for p in pats:
		want[str(p[0])] = true
	for r in roots_:
		var queue: Array = [[str(r[0]), int(r[1])]]
		while not queue.is_empty():
			if _over(b) or want.keys().all(func(id) -> bool: return found.has(id)):
				return found
			var cur: Array = queue.pop_front()
			var path := str(cur[0])
			var left := int(cur[1])
			var key := path.to_lower()
			# Schon mit mindestens so viel Tiefe besucht (Suchorte überlappen: D:\ und D:\Games).
			if int((b.seen as Dictionary).get(key, -1)) >= left:
				continue
			(b.seen as Dictionary)[key] = left
			b.dirs = int(b.dirs) + 1
			if on_dir.is_valid():
				on_dir.call(path)
			for f in list_files.call(path):
				var id := exe_id(str(f), pats)
				if id != "" and not found.has(id):
					found[id] = { "exe": _join(path, str(f)), "how": how }
			if left <= 0:
				continue
			for d in list_dirs.call(path):
				var dn := str(d)
				if dn.begins_with(".") or dn.begins_with("$") or SKIP.has(dn.to_lower()):
					continue
				queue.append([_join(path, dn), left - 1])
	return found


## Verknüpfungen unter den Startmenü-Orten: Pfade der .lnk-Dateien (begrenzt).
static func lnk_files(roots_: Array, list_dirs: Callable, list_files: Callable, b: Dictionary) -> Array:
	var out: Array = []
	for r in roots_:
		var queue: Array = [[str(r[0]), int(r[1])]]
		while not queue.is_empty() and out.size() < MAX_LNK and not _over(b):
			var cur: Array = queue.pop_front()
			b.dirs = int(b.dirs) + 1
			for f in list_files.call(str(cur[0])):
				if str(f).to_lower().ends_with(".lnk") and out.size() < MAX_LNK:
					out.append(_join(str(cur[0]), str(f)))
			if int(cur[1]) > 0:
				for d in list_dirs.call(str(cur[0])):
					queue.append([_join(str(cur[0]), str(d)), int(cur[1]) - 1])
	return out


## Ziel einer Windows-Verknüpfung (.lnk, „Shell Link“-Format) oder "" – nur der lokale Pfad aus
## LinkInfo (Unicode, sonst ANSI). Fremde Daten: jede Länge und jeder Versatz wird geprüft.
static func lnk_target(b: PackedByteArray) -> String:
	var n := b.size()
	if n < 0x4C or n > LNK_MAX_BYTES or b.decode_u32(0) != 0x4C:
		return ""
	# LinkCLSID 00021401-0000-0000-C000-000000000046
	if b.decode_u32(4) != 0x00021401 or b[12] != 0xC0 or b[19] != 0x46:
		return ""
	var flags := b.decode_u32(0x14)
	var pos := 0x4C
	if flags & 0x1:
		if pos + 2 > n:
			return ""
		pos += 2 + b.decode_u16(pos)
	if not (flags & 0x2) or pos + 28 > n:
		return ""
	var li_size := b.decode_u32(pos)
	var hdr := b.decode_u32(pos + 4)
	var li_flags := b.decode_u32(pos + 8)
	if li_size < 28 or pos + li_size > n or hdr < 28 or hdr > li_size or not (li_flags & 0x1):
		return ""
	var end := pos + li_size
	var out := ""
	if hdr >= 0x24:
		var uoff := b.decode_u32(pos + 28)
		if uoff >= hdr and uoff < li_size:
			out = _utf16z(b, pos + uoff, end)
	if out == "":
		var aoff := b.decode_u32(pos + 16)
		if aoff >= hdr and aoff < li_size:
			out = _asciiz(b, pos + aoff, end)
	return _clean_path(out)


static func _utf16z(b: PackedByteArray, from: int, end: int) -> String:
	var i := from
	while i + 1 < end and (b[i] != 0 or b[i + 1] != 0):
		i += 2
	return b.slice(from, i).get_string_from_utf16() if i + 1 < end and i - from <= 2048 else ""


static func _asciiz(b: PackedByteArray, from: int, end: int) -> String:
	var i := from
	while i < end and b[i] != 0:
		i += 1
	return b.slice(from, i).get_string_from_ascii() if i < end and i - from <= 1024 else ""


## Nur gewöhnliche lokale Pfade (C:\…\x.exe): keine Netzpfade, keine Steuerzeichen, kein „..“.
static func _clean_path(p: String) -> String:
	var s := p.strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
	if s.length() < 4 or s.length() > 400 or s[1] != ":" or s[2] != "/" or s.contains("/../") or s.contains("//"):
		return ""
	for ch in s:
		if ch.unicode_at(0) < 32 or ch in ["\"", "<", ">", "|", "*", "?"]:
			return ""
	return s


## Verknüpfungen auswerten: read(pfad) → Bytes, exists(pfad) → bool.
static func from_lnks(files: Array, pats: Array, read: Callable, exists: Callable, found: Dictionary) -> Dictionary:
	for f in files:
		var t := lnk_target(read.call(str(f)))
		if t == "":
			continue
		var id := exe_id(t.get_file(), pats)
		if id != "" and not found.has(id) and bool(exists.call(t)):
			found[id] = { "exe": t, "how": "verknuepfung" }
	return found


## Hinweise des Helfers („emu-hints“): Deinstallations-Einträge { name, dir, icon } und laufende
## Programme { path, product, desc }. Programmdatei nach Namen oder Versionsangaben; bei einem
## Eintrag mit passendem Namen ohne passende Datei wird sein Ordner flach durchsucht.
## Gibt zusätzliche Suchorte zurück ([[ordner, 2], …]) und füllt found.
static func from_hints(hints: Dictionary, emus: Array, pats: Array, exists: Callable, found: Dictionary) -> Array:
	var more: Array = []
	var procs: Variant = hints.get("procs", [])
	for pr in (procs if procs is Array else []):
		if not (pr is Dictionary):
			continue
		var path := _clean_path(str(pr.get("path", "")))
		if path == "" or not path.to_lower().ends_with(".exe") or is_helper_exe(path.get_file()):
			continue
		var id := exe_id(path.get_file(), pats)
		if id == "":
			id = product_id(str(pr.get("product", "")) + " " + str(pr.get("desc", "")), emus)
		if id != "" and not found.has(id) and bool(exists.call(path)):
			found[id] = { "exe": path, "how": "prozess" }
	var un: Variant = hints.get("uninstall", [])
	for u in (un if un is Array else []):
		if not (u is Dictionary):
			continue
		var icon := _clean_path(str(u.get("icon", "")).get_slice(",", 0))
		var id2 := exe_id(icon.get_file(), pats) if icon != "" else ""
		if id2 == "" and icon != "" and icon.to_lower().ends_with(".exe") and not is_helper_exe(icon.get_file()):
			id2 = product_id(str(u.get("product", "")), emus)
		if id2 != "" and not found.has(id2) and bool(exists.call(icon)):
			found[id2] = { "exe": icon, "how": "registry" }
			continue
		if product_id(str(u.get("name", "")), emus) != "":
			var dir := _clean_path(str(u.get("dir", "")))
			if dir == "" and icon != "":
				dir = icon.get_base_dir()
			if dir != "":
				more.append([dir.trim_suffix("/"), 2])
	return _unique_roots(more)


## Die ganze Suche (im Faden). emus: [{ id, name, exe_hint }], io: { list_dirs, list_files, read,
## exists } (freiwillig, sonst das Dateisystem), hints: Ergebnis von „emu-hints“ oder {}.
## Rückgabe: id → { exe, how }.
static func find(emus: Array, alt_exe: Dictionary, drives: Array, env: Dictionary, steam_libs: Array, hints: Dictionary,
		io: Dictionary = {}, on_dir: Callable = Callable(), b: Dictionary = {}) -> Dictionary:
	var bud := b if not b.is_empty() else budget()
	var ld: Callable = io.get("list_dirs", func(p: String) -> Array: return dirs_at(p))
	var lf: Callable = io.get("list_files", func(p: String) -> Array: return files_at(p))
	var rd: Callable = io.get("read", func(p: String) -> PackedByteArray:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null or f.get_length() > LNK_MAX_BYTES:
			return PackedByteArray()
		return f.get_buffer(f.get_length()))
	var ex: Callable = io.get("exists", func(p: String) -> bool: return FileAccess.file_exists(p))
	var pats := patterns(emus, alt_exe)
	var found := {}
	if pats.is_empty():
		return found
	# 1. Was der Helfer weiß (Registry, laufende Programme) – schnell und genau.
	var more := from_hints(hints, emus, pats, ex, found)
	walk(more, pats, ld, lf, bud, found, "registry", on_dir)
	# 2. Verknüpfungen im Startmenü und auf dem Desktop.
	from_lnks(lnk_files(lnk_roots(env), ld, lf, bud), pats, rd, ex, found)
	# 3. Die üblichen Ordner, mit Tiefe und Grenzen.
	walk(roots(drives, env, steam_libs), pats, ld, lf, bud, found, "ordner", on_dir)
	return found

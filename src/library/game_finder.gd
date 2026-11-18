extends RefCounted
## Eigene Spiele finden (Punkt 117): In einem Ordner die Programmdateien, die wahrscheinlich das
## Spiel starten – ohne Installer, Deinstaller, Laufzeit-Pakete und Hilfsprogramme. Uzai liest dabei
## nur Datei- und Ordnernamen und Dateigrößen; es startet und öffnet nichts. Dazu ein Namensvorschlag
## und die Prüfung von Startparametern, Arbeitsordner und Programmdatei, bevor Uzai sie speichert.
## Getestet in tests/logic_eigene_spiele.gd.

const PcScanner := preload("res://src/library/pc_scanner.gd")

const MAX_DEPTH := 4             ## so tief unter dem durchsuchten Ordner (Spiele/Spiel/Spiel/Binaries/Win64)
const MAX_ENTRIES := 20000       ## so viele Dateien und Ordner höchstens ansehen (ganze Laufwerke)
const MAX_OTHERS := 8            ## andere Programmdateien je Spiel zur Auswahl
const ARGS_MAX := 1024
const LAUNCH_EXTS := ["exe", "lnk", "url", "bat", "cmd"]

## Dateinamen (klein, ohne Endung), die nie das Spiel sind.
const SKIP_EXACT := ["setup", "install", "installer", "uninstall", "uninst", "dxsetup", "dxwebsetup", "crashreportclient",
	"crashpad_handler", "launcher_helper", "notification_helper", "cefsharp.browsersubprocess", "oalinst", "redist",
	"updater", "update", "beservice", "quicksfv", "7z", "7za", "unrar", "dowser", "touchup", "activation", "register"]
## Anfänge: unins000, vcredist_x64, dotNetFx40_Full_setup, DirectX…, EasyAntiCheat_EOS_Setup …
const SKIP_PREFIX := ["unins", "vcredist", "vc_redist", "dotnet", "ndp4", "directx", "dxsetup", "easyanticheat", "battleye",
	"be_service", "crashreport", "crashhandler", "unitycrashhandler", "ue4prereq", "ueprereq", "uecrashreport", "physx",
	"setup_", "setup-", "install_", "install-", "uninstall", "vulkan-runtime", "vulkanrt", "xnafx", "openal"]
## Ordner ohne Spiel darin (Laufzeit-Pakete, Unreal-Hilfsprogramme, Reste von Installern).
const SKIP_DIRS := ["_commonredist", "commonredist", "redist", "_redist", "redistributables", "directx", "vcredist",
	"dotnet", "__installer", "installer", "installers", "support", "engine", "easyanticheat", "battleye", "prereqs",
	"$recycle.bin", "system volume information", "windows", "__macosx"]
## Wörter, die eher ein Hilfsprogramm als das Spiel meinen (abwerten, nicht ausschließen:
## manches Spiel startet nur über seinen Launcher).
const WEAK_WORDS := ["launcher", "config", "settings", "server", "editor", "benchmark", "tool", "helper", "crash",
	"report", "debug", "test", "mod", "patch", "dedicated", "console"]
## Ordnernamen, die nichts über das Spiel sagen (dann zählt der Dateiname).
const GENERIC_DIRS := ["bin", "bin32", "bin64", "binaries", "win32", "win64", "x86", "x64", "game", "games", "app",
	"release", "retail", "build", "client", "program", "programs", "data", "root", "windows", "pc",
	"desktop", "downloads", "download", "documents", "dokumente", "programfiles", "programfilesx86", "programme"]
## Klammern mit diesen Wörtern sind Beiwerk („(GOG)“, „[Repack]“), keine Teile des Namens.
const TAG_WORDS := ["gog", "steam", "epic", "repack", "portable", "drm", "free", "x64", "x86", "win", "build", "multi",
	"eng", "deu", "ger", "update", "fitgirl", "dodi", "elamigos", "v"]


# --- Durchsuchen -----------------------------------------------------------------------------

## Spiele in einem Ordner: [{ folder, exe, title, others: [exe, …] }]. Liegen direkt im Ordner
## Programme, ist er selbst ein Spiel; sonst ist jeder Unterordner eines (D:\Spiele\Hades\…).
## known: Pfade, die Uzai schon kennt (klein geschrieben) – die fehlen im Ergebnis.
static func scan(root: String, known: Dictionary = {}) -> Array:
	var r := root.replace("\\", "/").trim_suffix("/")
	if r == "" or not DirAccess.dir_exists_absolute(r):
		return []
	var found: Array = []        # [{ path, depth, size, group }]
	var budget := [MAX_ENTRIES]
	_walk(r, r, 0, "", found, budget)
	var groups := {}
	var top := found.any(func(e: Dictionary) -> bool: return int(e.depth) == 0)
	for e in found:
		var key: String = r if top else r.path_join(str(e.group))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(e)
	var out: Array = []
	for key in groups:
		var folder_name := str(key).get_file()
		var list: Array = groups[key]
		# Die Wertung je Datei einmal rechnen, nicht bei jedem Vergleich der Sortierung neu.
		for e in list:
			e["wert"] = score(str(e.path), int(e.depth), int(e.size), folder_name)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.wert) > float(b.wert))
		var best := str(list[0].path)
		if known.has(best.to_lower()):
			continue
		var others: Array = []
		for e in list.slice(1, MAX_OTHERS + 1):
			others.append(str(e.path))
		out.append({ "folder": str(key), "exe": best, "title": suggest_name(best, folder_name), "others": others })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	return out


static func _walk(dir: String, root: String, depth: int, group: String, out: Array, budget: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	for f in da.get_files():
		budget[0] -= 1
		if int(budget[0]) <= 0:
			return
		if f.get_extension().to_lower() != "exe" or skip_exe(f):
			continue
		var full := dir.path_join(f)
		# Die Größe ohne Öffnen: Jedes geöffnete Programm prüft unter Windows der Virenschutz – bei Hunderten
		# Programmdateien dauerte die Suche dadurch unnötig lange.
		out.append({ "path": full, "depth": depth, "size": maxi(0, FileAccess.get_size(full)), "group": group })
	if depth >= MAX_DEPTH:
		return
	for sub in da.get_directories():
		budget[0] -= 1
		if int(budget[0]) <= 0:
			return
		if sub.begins_with(".") or skip_dir(sub):
			continue
		_walk(dir.path_join(sub), root, depth + 1, group if group != "" else sub, out, budget)


static func skip_exe(file: String) -> bool:
	var n := file.get_basename().to_lower()
	if n in SKIP_EXACT:
		return true
	for p in SKIP_PREFIX:
		if n.begins_with(p):
			return true
	return false


static func skip_dir(dir_name: String) -> bool:
	return dir_name.to_lower() in SKIP_DIRS


## Wie wahrscheinlich ist diese Datei das Spiel? Name wie der Ordner, weit oben, groß – und keine
## Wörter wie „Launcher“ oder „Server“ im Namen.
static func score(path: String, depth: int, size: int, folder_name: String) -> float:
	var n := _squash(path.get_file().get_basename())
	var f := _squash(folder_name)
	var s := 0.0
	if f != "" and n != "":
		if n == f:
			s += 6.0
		elif n.contains(f) or f.contains(n):
			s += 4.0
		elif _common_prefix(n, f) >= 4:
			s += 2.0
	for w in WEAK_WORDS:
		if path.get_file().to_lower().contains(w):
			s -= 3.0
			break
	if path.get_file().to_lower().contains("shipping"):
		s += 1.0
	s -= depth * 0.8
	if size > 0:
		s += clampf(log(float(size) / 1048576.0 + 1.0) / log(2.0), 0.0, 8.0) * 0.5
	return s


static func _common_prefix(a: String, b: String) -> int:
	var i := 0
	while i < mini(a.length(), b.length()) and a[i] == b[i]:
		i += 1
	return i


## Nur Buchstaben und Ziffern, klein: „Hollow_Knight“ = „hollowknight“.
static func _squash(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in "äöüß":
			out += ch
	return out


# --- Name ------------------------------------------------------------------------------------

## Vorschlag für den Namen: der Ordner des Spiels, wenn er etwas sagt, sonst die Programmdatei –
## ohne Beiwerk wie „(GOG)“, Versionsnummern, „-Win64-Shipping“, Unterstriche.
static func suggest_name(exe: String, folder_name := "") -> String:
	var raw := folder_name
	if raw == "" or _squash(raw) in GENERIC_DIRS or _squash(raw) == "":
		raw = exe.get_file().get_basename()
	return clean_title(raw)


## Name suggestion for a single picked file („Hinzufügen“ → program file): a shortcut already carries the name it was
## given ("Elden Ring.lnk"), and that name wins over the folder it sits in (otherwise the suggestion would be
## "Desktop"). For an .exe, the folder if it sounds like a game, otherwise the file name.
static func name_for_pick(path: String) -> String:
	if path.get_extension().to_lower() in ["lnk", "url", "bat", "cmd"]:
		var n := clean_title(PcScanner.clean_name(path.get_file().get_basename()))
		if n != "":
			return n
	return suggest_name(path, path.get_base_dir().get_file())


static func clean_title(s: String) -> String:
	var t := s
	for suffix in ["-Win64-Shipping", "-Win32-Shipping", "-WinGDK-Shipping", "-Shipping", "_x64", "_x86", "_Win64", "_Win32"]:
		if t.ends_with(suffix) and t.length() > suffix.length() + 2:
			t = t.trim_suffix(suffix)
	t = _rx("brackets").sub(t, "", true)
	for m in _rx("parens").search_all(t):
		var inner := m.get_string(1).to_lower()
		if TAG_WORDS.any(func(w: String) -> bool: return inner == w or inner.begins_with(w + " ") or inner.begins_with(w + ".") or inner.contains(" " + w)) \
				or _rx("version").search(inner) != null:
			t = t.replace(m.get_string(), "")
	t = t.replace("_", " ")
	# Punkte nur zwischen Wörtern (nicht in „3.0“ oder „Dr.“ am Wortende).
	t = _rx("dots").sub(t, " ", true)
	t = _rx("trail_version").sub(t, "", true)
	if not t.contains(" ") and t.length() > 4:
		t = _rx("camel").sub(t, "$1 $2", true)
		t = _rx("acronym").sub(t, "$1 $2", true)
	return _rx("spaces").sub(t, " ", true).strip_edges().trim_suffix("-").strip_edges()


## Beim Laden gefüllt, danach nur gelesen: scan() läuft im Hilfsfaden, der Namensvorschlag zugleich im Hauptfaden.
## (Vorher wurden die Muster beim ersten Aufruf angelegt – zwei Fäden schrieben dann in dasselbe Verzeichnis.)
static var _re := _muster()


static func _muster() -> Dictionary:
	var pat := {
		"brackets": "\\s*[\\[{][^\\]}]*[\\]}]",
		"parens": "\\s*\\(([^)]*)\\)",
		"version": "^v?\\d+(\\.\\d+)+[a-z]?$",
		"dots": "(?<=[A-Za-zÄÖÜäöü]{2})\\.(?=[A-Za-zÄÖÜäöü])",
		"trail_version": "(?i)\\s+(v\\d+(\\.\\d+)*[a-z]?|\\d+\\.\\d+(\\.\\d+)+|build\\s*\\d+)\\s*$",
		"camel": "([a-zäöü0-9])([A-ZÄÖÜ])",
		"acronym": "([A-ZÄÖÜ])([A-ZÄÖÜ][a-zäöü])",
		"spaces": "\\s{2,}",
	}
	var out := {}
	for k: String in pat:
		out[k] = RegEx.create_from_string(str(pat[k]))
	return out


static func _rx(k: String) -> RegEx:
	return _re[k]


# --- Prüfen ----------------------------------------------------------------------------------

## Programmdatei: absolut, vorhanden, startbare Art. "" = in Ordnung, sonst der Grund.
static func exe_problem(path: String) -> String:
	if path == "" or not path.is_absolute_path() or _has_control(path):
		return "Das ist kein gültiger Pfad."
	if not path.get_extension().to_lower() in LAUNCH_EXTS:
		return "Uzai startet nur Programme (.exe), Verknüpfungen (.lnk, .url) und Batch-Dateien (.bat, .cmd)."
	if not FileAccess.file_exists(path):
		return "Die Datei gibt es nicht (mehr)."
	# Internet-Verknüpfung: wie beim Einlesen (pc_scanner.gd) nur Start-Links von Launchern, keine Webseiten.
	if path.get_extension().to_lower() == "url":
		var url := PcScanner.read_url(path)
		if url == "" or _has_control(url):
			return "In der Verknüpfung steht keine Adresse."
		if url.to_lower().begins_with("http"):
			return "Das ist eine Verknüpfung zu einer Internetseite, nicht zu einem Spiel."
		if not PcScanner.url_ok(url):
			return "Diese Verknüpfung zeigt nicht auf einen Spiele-Starter (Steam, Epic, GOG, Battle.net …)."
	return ""


## Arbeitsordner: leer (= Ordner des Programms) oder ein vorhandener Ordner.
static func dir_problem(dir: String) -> String:
	if dir == "":
		return ""
	if not dir.is_absolute_path() or _has_control(dir):
		return "Das ist kein gültiger Ordner."
	if not DirAccess.dir_exists_absolute(dir):
		return "Den Ordner gibt es nicht (mehr)."
	return ""


## Startparameter gehen als Liste an das Programm (keine Shell). Nur Batch-Dateien laufen über
## cmd.exe – dort könnten &, |, <, >, ^ und % weitere Befehle anhängen, darum sind sie dort tabu.
static func args_problem(args: String, exe: String) -> String:
	if args.length() > ARGS_MAX:
		return "Das sind zu viele Startparameter (höchstens %d Zeichen)." % ARGS_MAX
	if _has_control(args):
		return "Startparameter dürfen keine Zeilenumbrüche oder Steuerzeichen enthalten."
	if args.count("\"") % 2 != 0:
		return "Ein Anführungszeichen ist nicht geschlossen."
	if exe.get_extension().to_lower() in ["bat", "cmd"]:
		for ch in ["&", "|", "<", ">", "^", "%", "!"]:
			if args.contains(ch):
				return "Bei Batch-Dateien sind &, |, <, >, ^, % und ! in Startparametern nicht erlaubt (sie würden weitere Befehle starten)."
	return ""


static func _has_control(s: String) -> bool:
	for ch in s:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
			return true
	return false

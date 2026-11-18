extends RefCounted
## Bausteine fürs Installieren über Uzai, ohne Zustand und ohne Windows (darum testbar):
## Steams appmanifest lesen und schreiben, Epics Pending-Manifest und Launcher-Protokoll lesen,
## Knöpfe und Fenster der Installationsdialoge erkennen, Antworten von Steams ClientComm-Dienst
## lesen, Größen, Tempo und Restzeit auf Deutsch.

const VDF := preload("res://src/library/vdf.gd")
const Lang := preload("res://src/core/lang.gd")
const Arbeit := preload("res://src/core/arbeit.gd")

## Steams EAppState-Bits (StateFlags im appmanifest).
const ST_UNINSTALLED := 1
const ST_UPDATE_REQUIRED := 2
const ST_FULLY_INSTALLED := 4
const ST_UPDATE_RUNNING := 256
const ST_UPDATE_PAUSED := 512
const ST_UPDATE_STARTED := 1024
const ST_VALIDATING := 131072
const ST_ADDING_FILES := 262144
const ST_PREALLOCATING := 524288
const ST_DOWNLOADING := 1048576
const ST_STAGING := 2097152
const ST_COMMITTING := 4194304
const ST_UPDATE_STOPPING := 8388608


# --- Steam: appmanifest_<appid>.acf -------------------------------------------------------------

## Stand aus dem AppState eines appmanifest: { phase, text, frac (-1 = unbekannt), got, total, done }.
## phase: done | paused | downloading | installing | queued | preparing.
static func steam_state(st: Dictionary) -> Dictionary:
	var flags := int(str(VDF.get_ci(st, "StateFlags", "0")))
	var total := float(str(VDF.get_ci(st, "BytesToDownload", "0")))
	var got := float(str(VDF.get_ci(st, "BytesDownloaded", "0")))
	var stage_total := float(str(VDF.get_ci(st, "BytesToStage", "0")))
	var staged := float(str(VDF.get_ci(st, "BytesStaged", "0")))
	if (flags & ST_FULLY_INSTALLED) != 0 and (flags & ST_UPDATE_REQUIRED) == 0:
		return { "phase": "done", "text": "Installiert – bereit zum Spielen", "frac": 1.0, "got": total, "total": total, "done": true }
	var paused := (flags & ST_UPDATE_PAUSED) != 0
	if total <= 0.0:
		var t := "Pausiert in Steam" if paused else "Steam bereitet den Download vor …"
		var ph := "paused" if paused else "preparing"
		if not paused and (flags & (ST_UPDATE_STARTED | ST_UPDATE_RUNNING | ST_DOWNLOADING | ST_PREALLOCATING)) == 0:
			t = "Wartet in Steams Warteschlange"
			ph = "queued"
		return { "phase": ph, "text": t, "frac": -1.0, "got": 0.0, "total": 0.0, "done": false }
	var frac := clampf(got / total, 0.0, 1.0)
	var phase := "paused" if paused else "downloading"
	var word := "Pausiert in Steam" if paused else "Wird geladen"
	# Alles geladen, Steam packt aus und schreibt die Dateien (Staging/Committing).
	if not paused and got >= total and (flags & (ST_STAGING | ST_COMMITTING | ST_VALIDATING | ST_ADDING_FILES)) != 0:
		phase = "installing"
		word = "Wird installiert"
		if stage_total > 0.0:
			frac = clampf(staged / stage_total, 0.0, 1.0)
	var text := "%s · %d %% · %s von %s" % [word, int(frac * 100.0), gb(got), gb(total)]
	if phase == "installing":
		text = "%s · %d %%" % [word, int(frac * 100.0)]
	return { "phase": phase, "text": text, "frac": frac, "got": got, "total": total, "done": false }


## Ein appmanifest, mit dem Steam beim nächsten Start ein Spiel in genau diesem Bibliotheksordner
## lädt (StateFlags 1026: „Aktualisierung nötig“ + „begonnen“, noch nichts auf der Platte).
## Nur für den Fall, dass Steam geschlossen ist und du einen bestimmten Ordner gewählt hast.
static func steam_manifest_text(appid: int, name: String, installdir: String, owner := "") -> String:
	var rows := [
		["appid", str(appid)], ["Universe", "1"], ["name", name], ["StateFlags", "1026"],
		["installdir", installdir], ["LastUpdated", "0"], ["SizeOnDisk", "0"], ["buildid", "0"],
		["BytesToDownload", "0"], ["BytesDownloaded", "0"], ["AutoUpdateBehavior", "0"],
		["AllowOtherDownloadsWhileRunning", "0"], ["ScheduledAutoUpdate", "0"],
	]
	if owner != "":
		rows.insert(8, ["LastOwner", owner])
	var out := "\"AppState\"\n{\n"
	for r in rows:
		out += "\t\"%s\"\t\t\"%s\"\n" % [r[0], _vdf_esc(str(r[1]))]
	return out + "}\n"


static func _vdf_esc(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"")


## Ordnername unter steamapps/common aus dem Spieltitel: ohne Zeichen, die Windows in Pfaden
## nicht erlaubt, ohne Punkt/Leerzeichen am Ende. "" wenn nichts übrig bleibt.
static func install_dir_name(title: String) -> String:
	var s := title
	for ch in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", "™", "®", "©"]:
		s = s.replace(ch, "")
	var clean := ""
	for i in s.length():
		if s.unicode_at(i) >= 32:
			clean += s[i]
	clean = clean.strip_edges()
	while clean.ends_with(".") or clean.ends_with(" "):
		clean = clean.substr(0, clean.length() - 1)
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "LPT1", "LPT2"]:
		return ""
	return clean


# --- Steam: ClientComm (Fern-Download, wie in der Steam-App am Handy) ----------------------------

## Die Steam-Sitzung dieses PCs aus GetAllClientLogonInfo ({ sessions: [{ client_instanceid,
## machine_name, os_name, … }] }). Gleicher Rechnername gewinnt; sonst nur, wenn es genau eine
## Sitzung gibt und Steam hier sicher läuft (local_running). "" = keine passende.
static func pick_session(sessions: Array, machine: String, local_running: bool) -> String:
	var want := machine.strip_edges().to_lower()
	var valid: Array = []
	for s in sessions:
		if not (s is Dictionary):
			continue
		var id := str(s.get("client_instanceid", ""))
		if id == "" or id == "0":
			continue
		# Uzais eigene kurze Sitzung bei Steams Chat-Servern heißt „Uzai“ – nie dorthin installieren.
		if str(s.get("machine_name", "")).strip_edges().to_lower() == "uzai":
			continue
		valid.append(s)
		if want != "" and str(s.get("machine_name", "")).strip_edges().to_lower() == want:
			return id
	if valid.size() == 1 and local_running:
		return str(valid[0].get("client_instanceid", ""))
	return ""


## CClientComm_GetAllClientLogonInfo_Response (protobuf über Steams Chat-Server): sessions (1) =
## { client_instanceid (1), protocol_version (2), os_name (3), machine_name (4), os_type (5) }.
## pb: SteamCM.Pb (decode/zahl/text).
static func sessions_from_pb(pb: Variant, body: PackedByteArray) -> Array:
	var out: Array = []
	var d: Dictionary = pb.decode(body)
	for raw in d.get(1, []):
		if not (raw is PackedByteArray):
			continue
		var s: Dictionary = pb.decode(raw)
		out.append({ "client_instanceid": u64_text(int(pb.zahl(s, 1, 0))), "os_name": pb.text(s, 3), "machine_name": pb.text(s, 4) })
	return out


## Dasselbe aus der Web-API (JSON): { response: { sessions: [...] } }.
static func sessions_from_json(data: Variant) -> Array:
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return []
	var list: Variant = data.response.get("sessions", [])
	if not (list is Array):
		return []
	var out: Array = []
	for s in list:
		if s is Dictionary:
			out.append(
					{ "client_instanceid": str(s.get("client_instanceid", "")), "os_name": str(s.get("os_name", "")), "machine_name": str(s.get("machine_name", "")) })
	return out


## Ein Spiel aus GetClientAppList (Web-API, JSON): { got, total, rate, eta (-1), paused, installed,
## queue } oder {}. Steam schickt 64-Bit-Zahlen als Text.
static func client_app(data: Variant, appid: int) -> Dictionary:
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return {}
	var apps: Variant = data.response.get("apps", [])
	if not (apps is Array):
		return {}
	for a in apps:
		if not (a is Dictionary) or int(str(a.get("appid", "0"))) != appid:
			continue
		var eta := float(str(a.get("estimated_seconds_remaining", "-1")))
		return {
			"got": float(str(a.get("bytes_downloaded", "0"))), "total": float(str(a.get("bytes_to_download", "0"))),
			"rate": float(str(a.get("bytes_download_rate", "0"))), "eta": eta if eta > 0.0 else -1.0,
			"paused": bool(a.get("download_paused", false)), "installed": bool(a.get("installed", false)),
			"queue": int(str(a.get("queue_position", "-1"))),
		}
	return {}


## 64-Bit ohne Vorzeichen als Text (GDScript-Zahlen haben eines).
static func u64_text(v: int) -> String:
	if v >= 0:
		return str(v)
	var half := (v >> 1) & 0x7FFFFFFFFFFFFFFF
	var low := (half % 5) * 2 + (v & 1)
	return str(half / 5 + low / 10) + str(low % 10)


## Zurück zur Zahl (für das protobuf-Feld); Werte über 2^63 werden negativ wie in Steam-Bits.
static func u64_parse(s: String) -> int:
	var t := s.strip_edges()
	if not t.is_valid_int():
		return 0
	var v := 0
	for i in t.length():
		v = v * 10 + (t.unicode_at(i) - 48)
	return v


# --- Epic: Manifests\Pending und Protokoll ---------------------------------------------------------

## Das Pending-Manifest zu einem App-Namen (Launcher lädt gerade): { app, location, size, title }
## oder {}. dir: Manifest-Ordner (Data\Manifests).
static func epic_pending(dir: String, app: String) -> Dictionary:
	var pdir := dir.path_join("Pending")
	if app == "" or not DirAccess.dir_exists_absolute(pdir):
		return {}
	for f in DirAccess.get_files_at(pdir):
		if not f.ends_with(".item"):
			continue
		var r := epic_pending_parse(FileAccess.get_file_as_string(pdir.path_join(f)))
		if str(r.get("app", "")) == app:
			return r
	return {}


static func epic_pending_parse(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return {}
	var d: Dictionary = j.data
	var size := 0.0
	for k in ["InstallSize", "DownloadSize", "AppSize"]:
		if float(str(d.get(k, "0"))) > 0.0:
			size = float(str(d.get(k, "0")))
			break
	return { "app": str(d.get("AppName", "")), "location": str(d.get("InstallLocation", "")).replace("\\", "/"),
		"size": size, "title": str(d.get("DisplayName", "")) }


const _UNITS := { "b": 1.0, "kb": 1000.0, "mb": 1000000.0, "gb": 1000000000.0, "tb": 1000000000000.0,
	"kib": 1024.0, "mib": 1048576.0, "gib": 1073741824.0, "tib": 1099511627776.0 }


## Fortschritt aus dem Ende von EpicGamesLauncher.log. Epic dokumentiert das Format nicht; Uzai
## sucht darum vorsichtig die letzte Zeile, die zum Spiel (App-Name) oder zum Laden gehört und
## eine Prozentzahl oder „x GB von/of y GB“ enthält, dazu ein Tempo „… MB/s“. {} = nichts Sicheres.
## Ergebnis: { frac (-1 unbekannt), got, total, speed } (Bytes, Bytes/s; 0 = unbekannt).
static func epic_log_progress(tail: String, app: String) -> Dictionary:
	var lines := tail.split("\n")
	var a := app.to_lower()
	# Zeilen mit dem App-Namen zuerst; nur ohne solche eine allgemeine Ladezeile.
	if a != "":
		for i in range(lines.size() - 1, -1, -1):
			var low := lines[i].to_lower()
			if low.contains(a) and not low.contains("uninstall") and not low.contains("verify"):
				var r := _log_line(lines[i])
				if not r.is_empty():
					return r
	for i in range(lines.size() - 1, -1, -1):
		var low := lines[i].to_lower()
		if low.contains("uninstall") or low.contains("verify") or low.contains("selfupdate") or low.contains("self update"):
			continue
		if low.contains("buildpatch") or low.contains("download") or low.contains("installprogress") or low.contains("install progress"):
			var r := _log_line(lines[i])
			if not r.is_empty():
				return r
	return {}


## Beim Laden gefüllt, danach nur gelesen (nie beim ersten Aufruf anlegen: Ein zweiter Faden sähe sie halb fertig).
static var _re_pct := RegEx.create_from_string("(?<![\\d.,])(\\d{1,3}(?:[.,]\\d+)?)\\s?%")
static var _re_pair := RegEx.create_from_string(
		"(?i)(\\d+(?:[.,]\\d+)?)\\s?(B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)\\s?(?:/|of|von)\\s?(\\d+(?:[.,]\\d+)?)\\s?(B|KB|MB|GB|TB|KiB|MiB|GiB|TiB)(?!/s)")
static var _re_speed := RegEx.create_from_string("(?i)(\\d+(?:[.,]\\d+)?)\\s?(KB|MB|GB|KiB|MiB|GiB)/s")


## Eine Zeile: { frac, got, total, speed } oder {}.
static func _log_line(raw: String) -> Dictionary:
	var ln := raw.strip_edges()
	if ln == "":
		return {}
	var out := { "frac": -1.0, "got": 0.0, "total": 0.0, "speed": 0.0 }
	var hit := false
	var mp := _re_pair.search(ln)
	if mp:
		var got := _num(mp.get_string(1)) * float(_UNITS.get(mp.get_string(2).to_lower(), 1.0))
		var total := _num(mp.get_string(3)) * float(_UNITS.get(mp.get_string(4).to_lower(), 1.0))
		if total > 0.0 and got <= total * 1.01:
			out.got = got
			out.total = total
			out.frac = clampf(got / total, 0.0, 1.0)
			hit = true
	if not hit:
		var m := _re_pct.search(ln)
		if m:
			var p := _num(m.get_string(1))
			if p >= 0.0 and p <= 100.0:
				out.frac = p / 100.0
				hit = true
	if not hit:
		return {}
	var ms := _re_speed.search(ln)
	if ms:
		out.speed = _num(ms.get_string(1)) * float(_UNITS.get(ms.get_string(2).to_lower(), 1.0))
	return out


## Belegte Bytes eines Ordners samt Unterordnern (Epic: wie weit der Launcher ist). Höchstens
## max_files Dateien, damit riesige Spiele den Hintergrund-Faden nicht lange binden.
static func dir_size(dir: String, max_files := 400000) -> int:
	var total := 0
	var n := 0
	var stack: Array = [dir]
	while not stack.is_empty() and n < max_files and not Arbeit.endet:
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.include_hidden = true
		for sub in da.get_directories():
			# Verknüpfungen und Abzweigungen nicht verfolgen: Was dahinter liegt, gehört nicht zum Spiel (und eine,
			# die nach oben zeigt, zählte denselben Ordner immer wieder).
			if not da.is_link(sub):
				stack.append(d.path_join(sub))
		for f in da.get_files():
			total += maxi(0, FileAccess.get_size(d.path_join(f)))
			n += 1
	return total


static func _num(s: String) -> float:
	return float(s.replace(",", "."))


## Standard-Speicherort des Launchers aus GameUserSettings.ini ([Launcher]
## DefaultAppInstallLocation=…). "" wenn nicht eingetragen.
static func epic_default_dir(ini_text: String) -> String:
	var in_launcher := false
	for raw in ini_text.split("\n"):
		var ln := raw.strip_edges()
		if ln.begins_with("["):
			in_launcher = ln.to_lower() == "[launcher]"
			continue
		if in_launcher and ln.to_lower().begins_with("defaultappinstalllocation="):
			return ln.substr(ln.find("=") + 1).strip_edges().replace("\\", "/")
	return ""


# --- Installationsdialoge (Knöpfe über UI Automation) ------------------------------------------

## Welche Art Knopf (nach Beschriftung, deutsch oder englisch): install, next, finish, agree
## (Lizenz – nur du entscheidest), cancel, window (Fensterknöpfe) oder "".
static func dialog_kind(name: String) -> String:
	var n := name.to_lower().strip_edges()
	for ch in ["<", ">", "&", "…", "...", "!"]:
		n = n.replace(ch, "")
	n = n.strip_edges()
	if n == "":
		return ""
	if n.contains("deinstall") or n.contains("uninstall"):
		return ""
	for w in ["minimieren", "maximieren", "wiederherstellen", "minimize", "maximize", "restore"]:
		if n == w or n.begins_with(w):
			return "window"
	if n in ["schließen", "close", "x"]:
		return "window"
	for w in ["abbrechen", "cancel", "nein", "no", "zurück", "back", "später", "later", "nicht jetzt", "not now"]:
		if n == w:
			return "cancel"
	for w in ["ich stimme zu", "i agree", "agree", "zustimmen", "akzeptieren", "accept", "annehmen"]:
		if n == w or n.begins_with(w):
			return "agree"
	if n in ["installieren", "install", "jetzt installieren", "install now", "herunterladen", "download"] \
		or n.begins_with("installieren ") or n.begins_with("install ") or n.ends_with(" installieren"):
		return "install"
	for w in ["weiter", "next", "fortfahren", "continue"]:
		if n == w:
			return "next"
	for w in ["fertig", "fertigstellen", "finish", "done", "ok"]:
		if n == w:
			return "finish"
	return ""


## Der Knopf, den Uzai selbst drücken darf: { i, name, kind } oder {}. Zuerst „Installieren“,
## dann „Weiter“, dann „Fertig“. Eindeutig muss er sein: Gibt es mehrere „Installieren“ (im
## Epic-Launcher stehen auch in der Bibliothek dahinter solche Knöpfe), drückt Uzai keinen –
## dann wählst du in Uzai. Lizenzen (agree) drückt Uzai nie selbst.
static func dialog_pick(buttons: Array) -> Dictionary:
	for want in ["install", "next", "finish"]:
		var found: Array = []
		for b in buttons:
			if not (b is Dictionary) or not bool(b.get("enabled", true)):
				continue
			if dialog_kind(str(b.get("name", ""))) == want:
				found.append(b)
		var on := found.filter(func(b): return not bool(b.get("offscreen", false)))
		if on.size() == 1 or (on.is_empty() and found.size() == 1):
			var b: Dictionary = on[0] if on.size() == 1 else found[0]
			return { "i": int(b.get("i", -1)), "name": str(b.get("name", "")), "kind": want }
		if found.size() > 1:
			return {}
	return {}


## Knöpfe für die Auswahl in Uzai (wenn Uzai nicht selbst drücken darf): alle bedienbaren außer
## Fensterknöpfen, Abbrechen zuletzt. [{ i, name, kind }].
static func dialog_choices(buttons: Array) -> Array:
	var out: Array = []
	var tail: Array = []
	var seen := {}
	for b in buttons:
		if not (b is Dictionary) or not bool(b.get("enabled", true)) or bool(b.get("offscreen", false)):
			continue
		var name := str(b.get("name", "")).strip_edges()
		var k := dialog_kind(name)
		if name == "" or k == "window" or seen.has(name.to_lower()):
			continue
		seen[name.to_lower()] = true
		var e := { "i": int(b.get("i", -1)), "name": name, "kind": k }
		if k == "cancel":
			tail.append(e)
		else:
			out.append(e)
	return out + tail


## Steams Installationsfenster unter den Fenstern von steamwebhelper/steam ([{ hwnd, title, w, h,
## min, fg }]): neu seit dem Schnappschuss (before = hwnds) oder mit „Install…“ im Titel, nicht
## das Hauptfenster oder die Freundesliste. {} = keins.
static func steam_dialog_pick(windows: Array, before: Array, game_title := "") -> Dictionary:
	var best := {}
	var best_score := 0
	var gt := game_title.to_lower().strip_edges()
	for w in windows:
		if not (w is Dictionary):
			continue
		var t := str(w.get("title", "")).strip_edges()
		var tl := t.to_lower()
		if tl in ["steam", "freunde", "friends", "freundesliste", "friends list", "steam big picture mode", "steam-big-picture-modus"]:
			continue
		if int(w.get("w", 0)) < 200 or int(w.get("h", 0)) < 120 or bool(w.get("min", false)):
			continue
		var score := 0
		if (tl.contains("install") and not tl.contains("uninstall") and not tl.contains("deinstall")):
			score += 4
		if gt != "" and tl.contains(gt):
			score += 2
		if not before.has(int(w.get("hwnd", 0))):
			score += 2
		if bool(w.get("fg", false)):
			score += 1
		if score >= 2 and score > best_score:
			best = w
			best_score = score
	return best


# --- Steam fragt vor dem Spielstart (Startoptionen, Cloud-Konflikt, Abfrage) ------------------------

const START_DIALOG_MS := 2500        ## so lange muss das Fenster stehen (das kurze „Wird gestartet“ nicht)
const START_DIALOG_BLIND_MS := 6000  ## ohne lesbare Knöpfe: erst dann zeigen, und nur mit dem Spielnamen im Titel
## Knöpfe, die ein Spiel starten (deutsch und englisch): Dann wartet Steam auf dich.
const START_KNOEPFE := ["spielen", "play", "starten", "start", "launch", "trotzdem spielen", "play anyway", "ja", "yes"]


## Steams Fenster, das beim Start eines Spiels neu aufgegangen ist und hinter Uzais Startbildschirm
## liegt – unter den Fenstern von steamwebhelper/steam ([{ hwnd, title, w, h, min }]): neu seit dem
## Schnappschuss vor dem Start (before = hwnds), sichtbar, in der Größe eines Dialogs, nicht das
## Hauptfenster, die Freundesliste oder Big Picture. Gibt es mehrere, das kleinste. {} = keins.
static func steam_start_dialog(windows: Array, before: Array) -> Dictionary:
	var best := {}
	var best_area := 0
	for w in windows:
		if not (w is Dictionary) or before.has(int(w.get("hwnd", 0))) or bool(w.get("min", false)):
			continue
		var tl := str(w.get("title", "")).strip_edges().to_lower()
		if tl in ["steam", "freunde", "friends", "freundesliste", "friends list", "steam big picture mode", "steam-big-picture-modus"]:
			continue
		var b := int(w.get("w", 0))
		var h := int(w.get("h", 0))
		if b < 300 or h < 140 or b > 1400 or h > 1000:
			continue
		if best.is_empty() or b * h < best_area:
			best = w
			best_area = b * h
	return best


## Was Uzai mit so einem Fenster tut: "zeigen" (Steam wartet auf deine Wahl: in Uzai bedienen),
## "lassen" (Steam arbeitet nur – Fortschritt, höchstens „Abbrechen“ oder „Überspringen“) oder
## "warten" (noch zu kurz da, noch unklar). buttons: Knöpfe über UI Automation ([{ name, enabled }]),
## titel_passt: im Fenstertitel steht der Name des Spiels, gesehen_ms: so lange steht es schon.
static func start_dialog_urteil(buttons: Array, titel_passt: bool, gesehen_ms: int) -> String:
	if gesehen_ms < START_DIALOG_MS:
		return "warten"
	var wahl := 0
	var andere := 0
	for b in buttons:
		if not (b is Dictionary) or not bool(b.get("enabled", true)) or bool(b.get("offscreen", false)):
			continue
		var name := str(b.get("name", "")).strip_edges()
		var k := dialog_kind(name)
		if name.to_lower() in START_KNOEPFE or k in ["next", "finish", "agree", "install"]:
			wahl += 1
		elif k == "" and name != "" and not name.to_lower() in ["überspringen", "skip"]:
			andere += 1
	# Ein Knopf zum Starten oder Bestätigen – oder mehrere eigene Knöpfe (Startarten als Knöpfe).
	if wahl > 0 or andere >= 2:
		return "zeigen"
	if not buttons.is_empty():
		return "lassen"
	# Nichts lesbar (Steams Fenster ist eine Webseite): nur zeigen, wenn es klar zum Spiel gehört.
	if gesehen_ms < START_DIALOG_BLIND_MS:
		return "warten"
	return "zeigen" if titel_passt else "lassen"


## Das Fenster des Epic Games Launchers (das größte sichtbare). {} = keins.
static func epic_window_pick(windows: Array) -> Dictionary:
	var best := {}
	var area := 0
	for w in windows:
		if not (w is Dictionary) or bool(w.get("min", false)):
			continue
		var a := int(w.get("w", 0)) * int(w.get("h", 0))
		if a > area and int(w.get("w", 0)) >= 400 and int(w.get("h", 0)) >= 300:
			best = w
			area = a
	return best


# --- Tempo, Restzeit, Größen ------------------------------------------------------------------------

## Tempo (Bytes/s) aus Messpunkten [[ms, bytes], …] der letzten window_ms; 0 = noch unbekannt.
static func speed_from(samples: Array, window_ms := 12000) -> float:
	if samples.size() < 2:
		return 0.0
	var last: Array = samples[samples.size() - 1]
	var first: Array = samples[0]
	for s in samples:
		if int(last[0]) - int(s[0]) <= window_ms:
			first = s
			break
	var dt := float(int(last[0]) - int(first[0])) / 1000.0
	if dt < 1.5:
		return 0.0
	return maxf(0.0, (float(last[1]) - float(first[1])) / dt)


static func gb(bytes: float) -> String:
	var g := bytes / 1073741824.0
	if g < 1.0:
		return "%d MB" % int(bytes / 1048576.0)
	return Lang.dec("%.1f GB" % g)


static func speed_text(bps: float) -> String:
	if bps <= 0.0:
		return ""
	var mb := bps / 1048576.0
	if mb < 1.0:
		return "%d KB/s" % maxi(1, int(bps / 1024.0))
	return Lang.dec("%.1f MB/s" % mb)


## „noch 7 Min.“, „noch 1 Std. 20 Min.“; "" ohne Tempo.
static func eta_text(remaining: float, bps: float) -> String:
	if bps <= 0.0 or remaining <= 0.0:
		return ""
	var s := int(remaining / bps)
	if s < 60:
		return "noch < 1 Min."
	var m := int(ceil(s / 60.0))
	if m < 60:
		return "noch %d Min." % m
	var h := m / 60
	m = m % 60
	return "noch %d Std. %d Min." % [h, m] if m > 0 else "noch %d Std." % h


## Eine Zeile wie in Steam: „Wird geladen · 38 % · 3,5 GB von 9,0 GB · 12,3 MB/s · noch 7 Min.“
static func line(word: String, frac: float, got: float, total: float, bps: float, approx := false) -> String:
	var parts := PackedStringArray([word])
	if frac >= 0.0:
		parts.append(("ca. " if approx else "") + "%d %%" % int(frac * 100.0))
	if total > 0.0:
		parts.append("%s von %s" % [gb(got), gb(total)])
	var sp := speed_text(bps)
	if sp != "":
		parts.append(sp)
	var eta := eta_text(total - got, bps) if total > 0.0 else ""
	if eta != "":
		parts.append(eta)
	return " · ".join(parts)

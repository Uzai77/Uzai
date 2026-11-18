extends RefCounted
## Die Lage für den Uzai-Doktor (src/core/doktor.gd): sammelt, was Uzai ohnehin weiß – nur lesen,
## nichts ändern, nichts ins Netz. Billig genug für den Guide (ein paar Dateiprüfungen). Was es auf
## diesem System nicht gibt (Helfer, Launcher außerhalb von Windows), bleibt weg und gilt damit als
## „nicht geprüft“ statt als Fehler. In der Vorführung kommt Doktor.DEMO.

const Doktor := preload("res://src/core/doktor.gd")
const PadCheck := preload("res://src/core/pad_check.gd")
const PadsS := preload("res://src/core/pads.gd")
const LauncherSites := preload("res://src/library/launcher_sites.gd")
const WinEinst := preload("res://src/core/win_einst.gd")
const RetroLaden := preload("res://src/core/retro_laden.gd")

## Vorführung: in Uzai „behobene“ Karten (Kennung → true), damit „Beheben“ sichtbar etwas tut.
static var demo_fixed := {}
## Vorführung: zusätzliche Lage (etwa WLAN getrennt, Bluetooth aus), damit die Probe diese Karten zeigt.
static var demo_extra := {}
## Zuletzt gesammelt (für Guide und Einstellungen, die oft neu bauen): Lage und Zeitpunkt.
static var _last := {}
static var _last_ms := -1000000
const CACHE_MS := 10000


## Wie gather(), aber höchstens alle CACHE_MS neu (der Guide fragt bei jeder neuen Nachricht).
static func cached() -> Dictionary:
	if _last.is_empty() or Time.get_ticks_msec() - _last_ms > CACHE_MS:
		return gather()
	return _last


static func gather() -> Dictionary:
	var f := _gather()
	_last = f
	_last_ms = Time.get_ticks_msec()
	return f


static func _gather() -> Dictionary:
	if Library.demo:
		return _demo()
	var f := {}
	f["windows"] = Config.is_windows()
	# Controller
	f["pads"] = Input.get_connected_joypads().size()
	var seen := str(Config.get_value("einrichtung.pad", ""))
	f["known_pad"] = seen != "" and seen != "Tastatur"
	var low: Array = []
	for p in Pads.pads:
		if int((p as Dictionary).get("level", -1)) == 0 and str(p.get("power", "")) != "wired" and not bool(p.get("charging", false)):
			low.append(str(p.get("name", "Controller")))
	f["pad_low"] = low
	f["pad_dupes"] = PadCheck.device_hints(PadsS.godot_joys())
	# Launcher (nur, was Uzai sicher weiß – siehe LauncherSites.missing)
	var enabled := {}
	for id in LauncherSites.ORDER:
		enabled[id] = bool(Config.get_value("library.%s_enabled" % id, true))
	if not Library.launchers.is_empty():
		f["launchers_missing"] = LauncherSites.missing(Library.launchers, enabled, Library.launcher_need).map(func(id: String) -> Dictionary:
			var s := LauncherSites.site(id)
			return { "id": id, "name": str(s.get("name", id)), "what": str(s.get("what", "")), "icon": str(s.get("icon", "games")) })
	# Emulatoren und Spieleordner
	var dirs: Dictionary = Config.get_value("library.rom_dirs", {})
	var games_by_sys := {}
	for g in Library.games:
		if str((g as Dictionary).get("source", "")) == "rom":
			var s := str(g.get("system", ""))
			games_by_sys[s] = int(games_by_sys.get(s, 0)) + 1
	var emus: Array = []
	var emu_seen := {}
	var gone: Array = []
	for s in Config.systems_enabled():
		var sid := str(s.get("id", ""))
		var dir := str(dirs.get(sid, "")).strip_edges()
		if dir == "" and int(games_by_sys.get(sid, 0)) == 0:
			continue
		if dir != "" and not DirAccess.dir_exists_absolute(dir):
			gone.append({ "system": sid, "name": str(s.get("name", sid)), "dir": dir.replace("/", "\\") if f.windows else dir })
		var eid := str(s.get("emulator", ""))
		if eid == "":
			continue
		var e := Config.emulator(eid)
		var exe := str(e.get("exe", ""))
		if exe != "" and FileAccess.file_exists(exe):
			continue
		if not emu_seen.has(eid):
			emu_seen[eid] = { "id": eid, "name": str(e.get("name", eid)), "systems": [], "games": 0 }
			emus.append(emu_seen[eid])
		(emu_seen[eid].systems as Array).append(str(s.get("short", sid)))
		emu_seen[eid].games = int(emu_seen[eid].games) + int(games_by_sys.get(sid, 0))
	# Was Uzai davon selbst von der offiziellen Quelle einrichten kann (Retro ohne Einrichtung).
	if not emus.is_empty():
		var ra: Array = RetroLaden.inst().lage()
		for e in emus:
			for r in ra:
				if str(r.emulator) == str(e.id) and str(r.angebot) != "":
					e["angebot"] = str(r.angebot)
	f["emus_missing"] = emus
	f["romdirs_missing"] = gone
	f["games"] = Library.visible_games().size()
	f["scanning"] = Library.scanning
	# Speicher dort, wo Uzai seine Daten hat (Bilder, Aufnahmen, Sicherungen)
	var da := DirAccess.open(Config.data_dir)
	f["space_free"] = int(da.get_space_left()) if da else -1
	f["space_dir"] = Config.data_dir.left(2) if f.windows else Config.data_dir
	# Helfer, Anmeldungen, Uhr, Netz
	if Helper.state() != "":
		f["helper"] = Helper.state()
	f["logins_expired"] = expired_logins()
	f["clock_known"] = Net.clock_known
	f["clock_skew"] = Net.clock_skew
	f["net"] = Doktor.net_state(Net.last_ok_ms, Net.last_fail_ms, Net.fails)
	f["crash"] = not Config.last_crash.is_empty()
	# WLAN und Bluetooth: nur, was der Helfer zuletzt gemeldet hat (WinEinst.refresh_lage).
	for k in WinEinst.lage:
		f[k] = WinEinst.lage[k]
	return f


## Dienste, deren Anmeldung Uzai gerade nicht mehr annimmt: [{ id, name }].
static func expired_logins() -> Array:
	var out: Array = []
	if str(Twitch.get("state")) == "abgelaufen":
		out.append({ "id": "twitch", "name": "Twitch" })
	var tv: Variant = YouTube.get("tv")
	if tv is Object and str((tv as Object).get("state")) == "abgelaufen":
		out.append({ "id": "youtube", "name": "YouTube" })
	var epic: Variant = Library.get("epic_account")
	if epic is Object and str((epic as Object).get("state")) == "abgelaufen":
		out.append({ "id": "epic", "name": "Epic Games" })
	if not NuvioSync.connected() and str(NuvioSync.last_error).contains("abgelaufen"):
		out.append({ "id": "nuvio", "name": "Nuvio" })
	return out


static func _demo() -> Dictionary:
	var f: Dictionary = Doktor.DEMO.duplicate(true)
	if demo_fixed.has("emu:dolphin"):
		f.emus_missing = []
	if demo_fixed.has("ordner:gba"):
		f.romdirs_missing = []
	if demo_fixed.has("konto:twitch"):
		f.logins_expired = []
	if demo_fixed.has("launcher"):
		f.launchers_missing = []
	if demo_fixed.has("speicher"):
		f.space_free = 14 * Doktor.GB
	for k in demo_extra:
		f[k] = demo_extra[k]
	return f

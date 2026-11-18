extends "res://src/library/library_kern.gd"
## Bibliothek, Schicht über library_kern.gd: weitere Launcher, Epic (installierte und gekaufte
## Spiele, Installation über den Launcher) und Discs (PS1/PS2: Seriennummern und Zuordnung).

signal changed
signal scan_state(text: String)

const SteamScanner := preload("res://src/library/steam_scanner.gd")
const EpicScanner := preload("res://src/library/epic_scanner.gd")
const EpicOnline := preload("res://src/library/epic_online.gd")
const EpicInstallS := preload("res://src/core/epic_install.gd")
const DiscSerial := preload("res://src/library/disc_serial.gd")
const DiscDb := preload("res://src/library/disc_db.gd")
const Zustand := preload("res://src/core/zustand.gd")

## Felder, die beim Einlesen nicht überschrieben werden.
const USER_FIELDS := ["favorite", "hidden", "collections", "images", "images_auto", "sgdb_id", "iidb", "last_played", "playtime", "plays",
	"filter", "emulator", "args", "work_dir", "ra_id", "title_custom", "added", "notes", "lossless", "folders",
	"tags", "category", "age", "region", "links", "image_urls", "presence_hidden",
	"status", "status_at", "done_at", "stars", "review", "diary", "profile", "launch_via"]

## Einlesen läuft (scan): ein Ja/Nein, nur gemeldet – „liest“ oder nichts (leer: ruht).
var scanning := false:
	set(neu):
		if neu != scanning:
			Zustand.melden("bibliothek.einlesen", "liest" if neu else "")
		scanning = neu
var _disc_cache := {}             ## Pfad → { serial, size, mtime } (disc_serials.json)
var _serials := {}                ## Seriennummer → Spiel-ID (PS1/PS2)
var _disc_links := {}             ## Seriennummer → Spiel-ID, selbst zugeordnet (disc_links.json)
var _disc_db := {}                ## System → { serials, files } aus den Redump-Listen
var _disc_db_busy := {}           ## System → true, solange geladen wird
var _disc_db_failed := {}         ## System → Zeitpunkt des letzten Fehlschlags (nicht dauernd neu laden)
signal disc_db_loaded(sys: String)

## Launcher auf diesem PC (Punkt 115), beim Einlesen ermittelt: { steam, epic, ea, gog, … } →
## true/false. Fehlt ein Eintrag, weiß Uzai es nicht – dann bietet es auch nichts an (LauncherSites).
var launchers := {}
## Weitere Launcher (stores.gd), von denen es Spiele gibt: { id: true } – nur dann bietet Uzai einen
## fehlenden an (sonst stünden sieben Launcher als „fehlt“ da, die niemand braucht).
var launcher_need := {}
## Programme der weiteren Launcher, über die Uzai startet: { galaxy, battlenet, riot }.
var store_clients := {}


# --- Weitere Launcher (stores.gd) -------------------------------------------------------------

## GOG, Ubisoft Connect, Battle.net, Xbox-App, Amazon Games, itch.io und Riot: Registry über den
## Helfer (feste Schlüssel, nur lesen), Xbox-Pakete in einem eigenen Helfer-Prozess (kann dauern,
## soll den Helfer nicht blockieren), alles andere aus den Dateien der Launcher im Hilfsthread.
## Gibt die Quellen zurück, deren Abfrage diesmal nicht klappte – ihre Spiele bleiben stehen.
func _scan_stores(found: Array) -> Array:
	scan_state.emit("Weitere Launcher werden gelesen …")
	var on := {}
	for id in Stores.EXTRA:
		on[id] = Stores.enabled(id)
	var keep: Array = []
	var reg := {}
	var r := await Helper.run("store-games", {}, 15.0)
	if r.ok and r.result is Dictionary:
		reg = r.result
	else:
		keep.append("ubisoft")
	var xb := {}
	if bool(on.xboxpc):
		var x := await Helper.run_once("xbox-games", { "timeout": 40 })
		if x.ok and x.result is Dictionary:
			xb = x.result
		else:
			keep.append("xboxpc")
	var taken: Array = []
	for g in found:
		if str(g.get("source", "")) in ["steam", "epic", "ea"] and is_installed(g) and str(g.get("install_dir", "")) != "":
			taken.append(str(g.install_dir))
	var ctx := _store_ctx(reg, xb, on, taken)
	var list := await _threaded(Stores.scan_extra.bind(ctx))
	if _scan_abbruch:
		keep.append_array(Stores.EXTRA)
	store_clients = Stores.clients(ctx)
	var pres := Stores.presence(ctx, store_clients)
	var counts := {}
	var need := {}
	for g in list:
		counts[str(g.source)] = int(counts.get(str(g.source), 0)) + 1
		if Stores.needs_client(g):
			need[str(g.source)] = true
	for id in Stores.EXTRA:
		if bool(on[id]) and not (id in keep) and not (id == "battlenet" and reg.is_empty()):
			launchers[id] = bool(pres.get(id, false))
		launcher_need[id] = bool(need.get(id, false))
	scan_log("Einlesen: weitere Launcher – %s" % JSON.stringify(counts))
	found.append_array(list)
	return keep


func _store_ctx(reg: Dictionary, xb: Dictionary, on: Dictionary, taken: Array) -> Dictionary:
	return { "reg": reg, "xbox": xb, "on": on, "skip": taken, "pd": EpicScanner.program_data(),
		"local": OS.get_environment("LOCALAPPDATA").replace("\\", "/"), "appdata": OS.get_environment("APPDATA").replace("\\", "/") }


## Programme der Launcher fürs Starten; vor dem ersten Einlesen schnell nachsehen.
func ensure_store_clients() -> Dictionary:
	if store_clients.is_empty() and Config.is_windows():
		var r := await Helper.run("store-games", {}, 10.0)
		store_clients = Stores.clients(_store_ctx(r.result if r.ok and r.result is Dictionary else {}, {}, {}, []))
	return store_clients


## Katalogdatei des Launchers gefunden? (Einstellungen zeigen sonst einen Hinweis.) -1 = noch
## nicht eingelesen.
var epic_catalog := -1
var _epic_wait := {}          ## Spiel-ID → Zeitpunkt, an dem die Installation angestoßen wurde
var _epic_sig := ""
var _epic_timer: Timer
var _epic_busy := false
var _epic_abbruch := false         ## das letzte Lesen der Epic-Dateien brach ab: bisherige Epic-Spiele bleiben stehen
var epic_account: Node             ## Epic-Konto (epic_account.gd)
var epic_online := -1              ## Spiele aus dem Epic-Konto beim letzten Einlesen (-1: keine Anmeldung)
const EPIC_WAIT_MAX := 6 * 3600   ## so lange schaut Uzai nach einer angestoßenen Installation


# --- Epic: installierte und gekaufte Spiele, Installation über den Launcher ----------------------

## Installierte Spiele (Manifeste) und gekaufte aus dem Katalog des Launchers (im Hilfsthread),
## dazu – mit Anmeldung – alle gekauften aus dem Epic-Konto (ohne Doppelte). Klappt das Konto
## nicht, bleibt es still bei Launcher-Dateien und der zuletzt geholten Liste.
func _scan_epic(force_online := false) -> Array:
	var box := { "r": {} }
	await _threaded(func() -> Array:
		box.r = EpicScanner.scan_all(true)
		return [])
	_epic_abbruch = _scan_abbruch
	var r: Dictionary = box.r
	var list: Array = r.get("games", [])
	epic_catalog = 1 if bool(r.get("catalog", false)) else 0
	var own := list.filter(func(g): return not is_installed(g)).size()
	scan_log("Einlesen: Epic – %d installiert, %d gekauft (Katalog %s)" % [list.size() - own, own, "gefunden" if epic_catalog == 1 else "fehlt"])
	epic_online = -1
	if epic_account != null and (epic_account.logged_in() or epic_account.state == "abgelaufen"):
		var online: Array = await epic_account.owned_games(force_online)
		var n := list.size()
		list = EpicOnline.combine(list, online)
		epic_online = online.size()
		scan_log("Einlesen: Epic-Konto – %d gekauft, %d davon neu" % [online.size(), list.size() - n])
	# Von Uzai selbst installierte Spiele (epic_install.gd): installiert, Start über die Programmdatei.
	var recs := EpicInstallS.records()
	if not recs.is_empty():
		list = EpicInstallS.apply_records(list, recs, str(Config.get_value("accounts.epic_account_id", "")))
	return list


## Installation eines gekauften Epic-Spiels anstoßen: Der Epic Games Launcher öffnet seinen
## Dialog. Danach schaut Uzai alle paar Sekunden (nur Dateizeiten im Manifest-Ordner) und beim
## Zurückkommen nach, ob das Spiel da ist. false: keine Katalog-IDs.
func start_epic_install(g: Dictionary) -> bool:
	var uri := EpicScanner.install_uri(g)
	if uri == "":
		return false
	scan_log("Epic: Installation angestoßen – %s" % str(g.get("title", "")))
	if not demo:
		OS.shell_open(uri)
	_epic_wait[str(g.id)] = int(Time.get_unix_time_from_system())
	_epic_sig = EpicScanner.manifest_sig() if not demo else ""
	if _epic_timer == null:
		_epic_timer = Timer.new()
		_epic_timer.wait_time = 5.0
		_epic_timer.timeout.connect(_epic_tick)
		add_child(_epic_timer)
	_epic_timer.start()
	return true


## Wartet Uzai gerade auf diese Installation (bzw. auf irgendeine, id = "")?
func epic_install_pending(id := "") -> bool:
	return _epic_wait.has(id) if id != "" else not _epic_wait.is_empty()


func _epic_tick() -> void:
	var now := int(Time.get_unix_time_from_system())
	for id in _epic_wait.keys():
		if now - int(_epic_wait[id]) > EPIC_WAIT_MAX or get_game(str(id)).is_empty():
			_epic_wait.erase(id)
	if _epic_wait.is_empty():
		_epic_timer.stop()
		return
	var sig := EpicScanner.manifest_sig()
	if sig != _epic_sig:
		_epic_sig = sig
		refresh_epic()


## Uzai ist wieder vorn (Guide-Taste, Alt+Tab): steht eine Installation aus, gleich nachsehen.
func on_focus_in() -> void:
	if not _epic_wait.is_empty():
		refresh_epic()


## Läufe von refresh_epic, die gerade unterwegs sind (siehe dort).
var _refresh_epic_offen := 0


## Nur Epic neu einlesen (ohne ROM-Ordner, Steam, EA). Fertige Installationen melden sich.
func refresh_epic(force_online := false) -> void:
	_refresh_epic_offen += 1
	await _refresh_epic_lauf(force_online)
	_refresh_epic_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_epic täte bis zum Neustart nichts mehr.
	if _refresh_epic_offen == 0 and _epic_busy:
		_epic_busy = false


func _refresh_epic_lauf(force_online := false) -> void:
	if demo or scanning or _epic_busy or not bool(Config.get_value("library.epic_enabled", true)) or not Config.is_windows():
		return
	_epic_busy = true
	var before := JSON.stringify(games.filter(func(g): return str(g.get("source", "")) == "epic")).md5_text()
	var eg := await _scan_epic(force_online)
	_merge(eg, ["epic"], ["epic"] if _epic_abbruch else [])
	_epic_busy = false
	for id in _epic_wait.keys():
		var g := get_game(str(id))
		if is_installed(g) and not bool(g.get("missing", false)):
			_epic_wait.erase(id)
			# Über Uzai angestoßen: Installs meldet es selbst (mit „Spielen“).
			if not Installs.busy(str(id)):
				Toasts.show_toast("Fertig installiert", "%s – jetzt spielbar." % display_title(g), "check", { "sound": "select" })
	if JSON.stringify(games.filter(func(g): return str(g.get("source", "")) == "epic")).md5_text() == before:
		return
	save()
	changed.emit()


## „Alle Steam-Spiele zeigen“ umgeschaltet: gleich sichtbar machen (früher erst beim nächsten
## Einlesen) und kurz sagen, was passiert ist.
func _on_steam_owned_changed() -> void:
	var on := bool(Config.get_value("library.steam_owned", false))
	var n := await refresh_steam_owned()
	if not on or demo:
		return
	if n < 0 and not Social.has_steam() and not SteamChat.changed.is_connected(_owned_after_login):
		# Nach der Anmeldung von selbst nachholen.
		SteamChat.changed.connect(_owned_after_login)
	if n < 0:
		Toasts.show_toast("Steam-Spiele nicht geladen", "Erst bei Steam anmelden: Einstellungen → Konten → Steam (QR-Code mit der Steam-App)."
				if not Social.has_steam()
			else "Steam hat die Liste gerade nicht geschickt. Später unter Einstellungen → Spiele „Jetzt neu einlesen“.", "steam", { "ms": 6000 })
	else:
		Toasts.show_toast("Alle Steam-Spiele sind da", ("%d nicht installierte unter Spiele → Steam, A installiert sie in Steam." % n) if n != 1
				else "1 nicht installiertes unter Spiele → Steam, A installiert es in Steam.", "steam", { "ms": 5000, "quiet": true })


func _owned_after_login() -> void:
	if not SteamChat.logged_in():
		return
	SteamChat.changed.disconnect(_owned_after_login)
	if bool(Config.get_value("library.steam_owned", false)):
		_on_steam_owned_changed()


## Nur die Steam-Liste nachziehen, ohne alle Ordner neu einzulesen. Ergebnis: Anzahl der nicht
## installierten Spiele, -1 = Steam hat nichts geliefert (oder keine Anmeldung).
func refresh_steam_owned() -> int:
	if demo or not bool(Config.get_value("library.steam_enabled", true)):
		return -1
	# Läuft gerade ein Einlesen, erst danach (es würde die Liste sonst wieder überschreiben).
	while scanning:
		await get_tree().process_frame
	var on := bool(Config.get_value("library.steam_owned", false))
	var owned: Array = []
	if on:
		if not Social.has_steam():
			return -1
		scan_state.emit("Steam-Spiele werden geholt …")
		owned = await Social.steam_owned_games()
		scan_state.emit("")
		if owned.is_empty():
			return -1
	var n := apply_owned(games, owned, on, int(Time.get_unix_time_from_system()))
	_reindex()
	save()
	changed.emit()
	return n


## Rein: gekaufte Steam-Spiele in die Liste übernehmen. Neue kommen als „nicht installiert“ dazu,
## deinstallierte bleiben (als nicht installiert) sichtbar; mit on = false verschwinden alle nicht
## installierten. Gibt die Zahl der nicht installierten zurück.
static func apply_owned(list: Array, owned: Array, on: bool, now: int) -> int:
	var by_app := {}
	for g in list:
		if str(g.get("source", "")) == "steam":
			by_app[int(g.get("appid", 0))] = g
	var want := {}
	var n := 0
	for o in owned:
		var appid := int(o.get("appid", 0))
		if appid <= 0 or SteamScanner.is_tool_app(appid, str(o.get("name", ""))):
			continue
		want[appid] = true
		var g: Dictionary = by_app.get(appid, {})
		if g.is_empty():
			list.append({ "id": "steam:%d" % appid, "title": str(o.get("name", "")), "system": "steam", "source": "steam",
				"appid": appid, "installed": false, "steam_minutes": int(o.get("playtime_forever", 0)),
				"steam_last": int(o.get("rtime_last_played", 0)), "added": now })
			n += 1
			continue
		g["steam_minutes"] = int(o.get("playtime_forever", 0))
		g["steam_last"] = maxi(int(g.get("steam_last", 0)), int(o.get("rtime_last_played", 0)))
		if bool(g.get("missing", false)) or not bool(g.get("installed", true)):
			g["installed"] = false
			g.erase("missing")
			n += 1
	for g in list:
		if str(g.get("source", "")) == "steam" and not bool(g.get("installed", true)) and not (on and want.has(int(g.get("appid", 0)))):
			g["missing"] = true
	return n


func _merge_owned(found: Array, owned: Array, add_missing := true) -> Array:
	var have := {}
	for g in found:
		if g.get("source") == "steam":
			have[int(g.appid)] = g
	for o in owned:
		var appid := int(o.get("appid", 0))
		if appid == 0 or SteamScanner.is_tool_app(appid, str(o.get("name", ""))):
			continue
		if have.has(appid):
			have[appid]["steam_minutes"] = int(o.get("playtime_forever", 0))
			have[appid]["steam_last"] = maxi(int(have[appid].get("steam_last", 0)), int(o.get("rtime_last_played", 0)))
		elif add_missing:
			found.append({
				"id": "steam:%d" % appid, "title": str(o.get("name", "")), "system": "steam", "source": "steam",
				"appid": appid, "installed": false, "steam_minutes": int(o.get("playtime_forever", 0)),
				"steam_last": int(o.get("rtime_last_played", 0)),
			})
	return found


## only: nur diese Quellen wurden eingelesen (z. B. ["epic"] beim Nachsehen nach einer
## Installation) – was anderen Quellen fehlt, bleibt dann unberührt.
## keep: Quellen, deren Einlesen diesmal nicht geklappt hat (z. B. Xbox-Abfrage zu langsam) – ihre
## Spiele bleiben, statt kurz zu verschwinden.
## rom_systems: Systeme, deren Spieleordner diesmal ganz durchsucht wurde. Ein Emulator-Spiel dieser
## Systeme, das dabei nicht mehr auftauchte, verschwindet – auch wenn seine Datei noch da ist (Ordner
## gewechselt, jetzt Teil einer .m3u, leer oder unvollständig). Früher blieb es dann stehen und
## galt beim Start als kaputt. Ausgeschaltete Systeme und nicht erreichbare Ordner bleiben unberührt.
## Gibt zurück, wie viele bisher sichtbare Spiele jetzt fehlen. Spielzeit und Bilder bleiben am
## Eintrag – taucht die Datei wieder auf, ist alles wieder da.
func _merge(found: Array, only: Array = [], keep: Array = [], rom_systems: Array = []) -> int:
	var now := int(Time.get_unix_time_from_system())
	var seen := {}
	var was := {}
	for g in games:
		if not bool(g.get("missing", false)):
			was[str(g.get("id", ""))] = true
	for f in found:
		var id := str(f.id)
		seen[id] = true
		var old: Dictionary = _by_id.get(id, {})
		if old.is_empty():
			f["added"] = now
			games.append(f)
			# Dieselbe neue Kennung zweimal in found (überlappende PC-Ordner) ergab sonst dauerhaft zwei Kacheln.
			_by_id[id] = f
			continue
		for k in f.keys():
			if k in USER_FIELDS:
				continue
			if k == "title" and old.get("title_custom", false):
				continue
			old[k] = f[k]
		# Aus einem Spiel mit mehreren Discs wurde eins mit einer: die alte Liste muss weg.
		if not f.has("discs"):
			old.erase("discs")
		old.erase("missing")
	# Was nicht mehr gefunden wurde, bleibt mit Spielzeit erhalten, wird aber ausgeblendet.
	var gone := 0
	for g in games:
		if not only.is_empty() and not (str(g.get("source", "")) in only):
			continue
		if g.get("scanned", false) and not seen.has(str(g.id)):
			g["missing"] = not FileAccess.file_exists(str(g.get("path", "")))
		if (g.get("source") in ["rom", "steam", "epic", "ea"] or Stores.is_extra(str(g.get("source", "")))) and not seen.has(str(g.id)) \
				and not (str(g.get("source", "")) in keep):
			if g.get("source") == "rom" and (rom_systems.has(str(g.get("system", ""))) or not FileAccess.file_exists(str(g.get("path", "")))):
				g["missing"] = true
			elif g.get("source") != "rom":
				g["missing"] = true
		if bool(g.get("missing", false)) and was.has(str(g.get("id", ""))):
			gone += 1
	relink()
	_reindex()
	return gone


# --- Discs (PS1/PS2) -----------------------------------------------------------

## Seriennummern der PS1/PS2-Abbilder ermitteln (im Hintergrund, nur neue oder geänderte Dateien)
## und in disc_serials.json merken. Damit geht der Abgleich beim Einlegen einer Disc sofort.
func _index_discs() -> void:
	var paths: Array = []
	for g in games:
		if DiscSerial.is_disc_game(g):
			paths.append_array(DiscSerial.files_of(g))
	scan_log("Discs: Seriennummern aus %d Dateien" % paths.size())
	var res := await _threaded(DiscSerial.index.bind(paths, _disc_cache))
	scan_log("Discs: Seriennummern gelesen")
	var fresh: Dictionary = res[0] if not res.is_empty() and res[0] is Dictionary else {}
	if JSON.stringify(fresh) != JSON.stringify(_disc_cache):
		_disc_cache = fresh
		Config.write_json(Config.path("disc_serials.json"), fresh)
	# Abbilder ohne Nummer (.chd, .cso …): die Redump-Liste ihres Systems kennt sie am Namen.
	var need := {}
	for g in games:
		if DiscSerial.is_disc_game(g) and not DiscSerial.files_of(g).any(func(p): return str((_disc_cache.get(str(p), {}) as Dictionary).get("serial", "")) != ""):
			need[str(g.system)] = true
	for sys in need.keys():
		await ensure_disc_db(str(sys))
	_rebuild_serials()


func _rebuild_serials() -> void:
	_serials.clear()
	for g in games:
		# Demo: Nummern stehen direkt im Datensatz (es gibt keine Abbilder zum Lesen).
		if str(g.get("serial", "")) != "" and not _serials.has(str(g.serial)):
			_serials[str(g.serial)] = str(g.id)
		if not DiscSerial.is_disc_game(g):
			continue
		var db: Dictionary = _disc_db.get(str(g.system), {})
		for p in DiscSerial.files_of(g):
			var e: Variant = _disc_cache.get(str(p))
			var s := str(e.get("serial", "")) if e is Dictionary else ""
			if s == "" and not db.is_empty():
				s = DiscDb.serial_for_file(db, str(p))
			if s != "" and not _serials.has(s):
				_serials[s] = str(g.id)
	# Selbst zugeordnet gilt vor allem anderen.
	for s in _disc_links.keys():
		if not get_game(str(_disc_links[s])).is_empty():
			_serials[str(s)] = str(_disc_links[s])


## Spiel zu einer Disc-Seriennummer („SLES-50330“), {} wenn es kein passendes Abbild gibt:
## selbst zugeordnet, Nummer im Abbild bzw. Dateinamen, sonst derselbe Titel (andere Region,
## z. B. Disc aus Europa, Abbild aus den USA).
func game_for_serial(serial: String, sys := "") -> Dictionary:
	var n := DiscSerial.normalize(serial)
	var g := get_game(str(_serials.get(n, "")))
	if g.is_empty():
		g = _game_by_disc_title(n, sys)
	return g if not g.is_empty() and is_visible(g) else {}


func _game_by_disc_title(serial: String, sys: String) -> Dictionary:
	var nm := disc_name(serial, sys)
	if nm == "":
		return {}
	var want := DiscDb.title_key(nm)
	if want == "":
		return {}
	var syss: Array = [sys] if sys != "" else DiscSerial.SYSTEMS
	for g in games:
		if not DiscSerial.is_disc_game(g) or not str(g.system) in syss or not is_visible(g):
			continue
		if DiscDb.title_key(str(g.get("title", ""))) == want or DiscDb.title_key(str(g.get("path", "")).get_file().get_basename()) == want:
			return g
	return {}


## Gibt es PS1/PS2-Spiele in der Bibliothek? Sonst fragt Uzai kein Laufwerk ab.
func has_disc_games() -> bool:
	return games.any(func(g): return DiscSerial.is_disc_game(g))


## Gibt es überhaupt PS1/PS2-Spiele mit bekannter Seriennummer?
func has_disc_serials() -> bool:
	return not _serials.is_empty()


## Seriennummer eines Spiels („SLES-54723“), wie sie gelesen wurde (Eintrag, Abbild bzw. Name),
## "" wenn unbekannt – für den Aufdruck am Rücken im Regal (src/library/regal.gd).
func serial_of(g: Dictionary) -> String:
	if str(g.get("serial", "")) != "":
		return str(g.serial)
	if not DiscSerial.is_disc_game(g):
		return ""
	for p in DiscSerial.files_of(g):
		var e: Variant = _disc_cache.get(str(p))
		if e is Dictionary and str((e as Dictionary).get("serial", "")) != "":
			return str(e.serial)
	return ""


## Name der Disc laut Redump-Liste („Ico (Europe) (En,Fr,De,Es,It)“), "" wenn unbekannt.
func disc_name(serial: String, sys := "") -> String:
	var n := DiscSerial.normalize(serial)
	for s in ([sys] if sys != "" else DiscSerial.SYSTEMS):
		var db: Dictionary = _disc_db.get(str(s), {})
		var nm := str((db.get("serials", {}) as Dictionary).get(n, ""))
		if nm != "":
			return nm
	return ""


func disc_db_ready(sys: String) -> bool:
	return _disc_db.has(sys)


## Redump-Liste eines Systems bereitstellen: aus dem Cache, sonst einmal herunterladen. Liest im
## Hintergrund-Thread; nach einem Fehlschlag frühestens nach 10 Minuten wieder.
func ensure_disc_db(sys: String) -> void:
	if _disc_db.has(sys) or demo or not DiscDb.FILES.has(sys):
		return
	if _disc_db_busy.has(sys):
		while _disc_db_busy.has(sys):
			await disc_db_loaded
		return
	if Time.get_unix_time_from_system() - float(_disc_db_failed.get(sys, 0)) < 600:
		return
	_disc_db_busy[sys] = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, geht es hier weiter. Sonst bliebe „lädt“ stehen,
	# und wer auf disc_db_loaded wartet, wartete für immer.
	await _disc_db_laden(sys)
	if not _disc_db.has(sys):
		_disc_db_failed[sys] = Time.get_unix_time_from_system()
	_disc_db_busy.erase(sys)
	disc_db_loaded.emit(sys)


func _disc_db_laden(sys: String) -> void:
	var dir := Config.path("cache/disc_db")
	DirAccess.make_dir_recursive_absolute(dir)
	var tsv := dir.path_join(sys + "-2.tsv")
	var dat := dir.path_join(sys + ".dat")
	# Caches der Vorversionen (JSON; TSV nur mit dem ersten Namen je Nummer) werden nicht mehr gebraucht.
	for o in [sys + ".json", sys + ".tsv"]:
		if FileAccess.file_exists(dir.path_join(o)):
			DirAccess.remove_absolute(dir.path_join(o))
	var old := not FileAccess.file_exists(tsv) or Time.get_unix_time_from_system() - FileAccess.get_modified_time(tsv) > DiscDb.MAX_AGE
	if old and not FileAccess.file_exists(dat):
		scan_log("Disc-Liste %s: Download" % sys)
		var ok := await Net.download_big(DiscDb.url(sys), dat)
		var fa: FileAccess = FileAccess.open(dat, FileAccess.READ) if ok else null
		var kb := int(fa.get_length() / 1024.0) if fa else 0
		if fa:
			fa.close()
		scan_log("Disc-Liste %s: Download %s (%d KB)" % [sys, "fertig" if ok else "fehlgeschlagen", kb])
		if not ok:
			DirAccess.remove_absolute(dat)
	var db := {}
	if FileAccess.file_exists(dat):
		scan_log("Disc-Liste %s: lesen (DAT)" % sys)
		db = await _read_disc_list(dat, false)
		if not (db.get("serials", {}) as Dictionary).is_empty():
			var f := FileAccess.open(tsv, FileAccess.WRITE)
			if f:
				f.store_string(DiscDb.to_tsv(db))
				f.close()
		DirAccess.remove_absolute(dat)
	if (db.get("serials", {}) as Dictionary).is_empty() and FileAccess.file_exists(tsv):
		scan_log("Disc-Liste %s: lesen (Cache)" % sys)
		db = await _read_disc_list(tsv, true)
	db.erase("pairs")  # nur für den Cache gebraucht
	if not (db.get("serials", {}) as Dictionary).is_empty():
		_disc_db[sys] = db
		_rebuild_serials()
		scan_log("Disc-Liste %s: %d Nummern" % [sys, (db.serials as Dictionary).size()])
	else:
		scan_log("Disc-Liste %s: nicht verfügbar" % sys)


## Redump-Liste bzw. eigenen Cache stückweise lesen (höchstens 1500 Zeilen je Bild), ohne
## Hilfsthread und ohne die Oberfläche spürbar anzuhalten.
func _read_disc_list(path: String, is_tsv: bool) -> Dictionary:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var st := DiscDb.new_state()
	var i := 0
	while i < lines.size():
		var to := mini(i + 1500, lines.size())
		if is_tsv:
			DiscDb.feed_tsv(st, lines, i, to)
		else:
			DiscDb.feed_dat(st, lines, i, to)
		i = to
		await get_tree().process_frame
	return DiscDb.result(st)


## Liste direkt setzen (Tests, Demo).
func set_disc_db(sys: String, db: Dictionary) -> void:
	_disc_db[sys] = db
	_rebuild_serials()


## Disc selbst einem Abbild zuordnen ("" löst die Zuordnung). Bleibt in disc_links.json.
func link_disc(serial: String, game_id: String) -> void:
	var n := DiscSerial.normalize(serial)
	if n == "":
		return
	if game_id == "":
		_disc_links.erase(n)
	else:
		_disc_links[n] = game_id
	if not demo:
		Config.write_json(Config.path("disc_links.json"), _disc_links)
	_rebuild_serials()


## Seriennummern, die selbst diesem Spiel zugeordnet sind.
func disc_links_for(game_id: String) -> Array:
	return _disc_links.keys().filter(func(s): return str(_disc_links[s]) == game_id)


## Vorschläge fürs Zuordnen: Spiele des Systems, die beste Übereinstimmung zuerst.
func disc_candidates(serial: String, sys: String) -> Array:
	var want := DiscDb.title_key(disc_name(serial, sys))
	var list: Array = games.filter(func(g): return DiscSerial.is_disc_game(g) and is_visible(g) and (sys == "" or str(g.system) == sys))
	var score := func(g: Dictionary) -> int:
		if want == "":
			return 0
		var k := DiscDb.title_key(str(g.get("title", "")))
		if k == want:
			return 3
		if k != "" and (want.begins_with(k) or k.begins_with(want)):
			return 2
		var words := want.split(" ")
		return 1 if words.size() > 0 and k.contains(words[0]) and words[0].length() > 3 else 0
	list.sort_custom(func(a, b):
		var sa: int = score.call(a)
		var sb: int = score.call(b)
		return sa > sb if sa != sb else str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)
	return list

extends "res://src/library/library_ordnung.gd"
## Die Spielesammlung: Emulator-Spiele aus den ROM-Ordnern, Steam, Epic, EA app, die weiteren
## Launcher (GOG, Ubisoft Connect, Battle.net, Xbox-App, Amazon Games, itch.io, Riot – stores.gd)
## und eigene Einträge.
## Gespeichert als library.json. Was der Nutzer an einem Spiel ändert (Titel, Bilder, Favorit,
## Bildfilter, Sammlungen), bleibt beim erneuten Einlesen erhalten.
##
## Hier stehen Laden, Abfragen nach Titel, Ändern und Einlesen; darunter liegen Schichten (jede erbt
## von der darunter): library_kern.gd, library_quellen.gd (Launcher, Epic, Discs), library_ordnung.gd.


const RomScanner := preload("res://src/library/rom_scanner.gd")
const EaScanner := preload("res://src/library/ea_scanner.gd")
const EpicAccount := preload("res://src/library/epic_account.gd")
const Lang := preload("res://src/core/lang.gd")


var collections: Array = []      # alt, wird beim Laden in Ordner umgewandelt
var _scan_again := ""             ## während des Einlesens noch einmal verlangt: "" nein, "ja", "online"
var _steam_root := ""
var _scan_report := false         ## „Spiele neu einlesen“: am Ende sagen, was sich getan hat
## Ergebnis des letzten Einlesens: { at, gone (jetzt fehlend), skipped (unbrauchbare Dateien), games }
var last_scan := {}


func _ready() -> void:
	# Suchmuster der Disc-Erkennung einmal hier anlegen (Hauptthread), nicht erst im Hilfsthread
	# des Einlesens.
	DiscSerial.normalize("")
	DiscDb.strip_disc("")
	DiscDb.title_key("")
	# Epic-Konto (inoffizielle Anmeldung wie Heroic/Legendary, nur wenn der Nutzer sich anmeldet).
	epic_account = EpicAccount.new()
	epic_account.name = "EpicAccount"
	add_child(epic_account)
	_save_timer = Timer.new()
	_save_timer.wait_time = 1.5
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_speichern_weich)
	add_child(_save_timer)
	changed.connect(forget_visible)
	Config.changed.connect(func(k: String) -> void:
		forget_visible()
		if k == "library.steam_owned":
			_on_steam_owned_changed()
		# Quelle aus- oder eingeschaltet: Doppelte neu verteilen (das Spiel steht dann bei der anderen).
		if k.begins_with("library.") and k.ends_with("_enabled"):
			relink()
	)
	if "--demo" in OS.get_cmdline_user_args():
		load_demo()
	else:
		load_library()


func load_library() -> void:
	var data: Variant = Config.read_json(Config.path("library.json"), {})
	var legacy := {}
	if data is Dictionary:
		var gs: Variant = data.get("games", [])
		var fs: Variant = data.get("folders", [])
		var cs: Variant = data.get("collections", [])
		# Nur Einträge, die wirklich Spiele/Ordner sind (kaputte Datei, andere Uzai-Version).
		games = (gs as Array).filter(func(g: Variant) -> bool: return g is Dictionary) if gs is Array else []
		folders = (fs as Array).filter(func(f: Variant) -> bool: return f is Dictionary and (f as Dictionary).has("id")) if fs is Array else []
		collections = cs if cs is Array else []
		# Stand vor den Profilen (Roadmap 109): Favoriten, Spielzeit, Backlog und Listen standen am
		# Spiel in library.json. Sie gehören dem ersten Profil und ziehen in dessen spieler.json.
		if not bool(data.get("profiles", false)) and not games.is_empty():
			legacy = { "games": Profiles.personal_of(games), "lists": data.get("lists", []), "goals": data.get("goals", {}) }
	_load_personal(legacy)
	_migrate_collections()
	for g in games:
		fix_numbers(g)
		GameFields.sanitize(g)
		Backlog.sanitize(g)
	relink()
	_reindex()
	var dc: Variant = Config.read_json(Config.path("disc_serials.json"), {})
	_disc_cache = dc if dc is Dictionary else {}
	var dl: Variant = Config.read_json(Config.path("disc_links.json"), {})
	_disc_links = dl if dl is Dictionary else {}
	_rebuild_serials()


## JSON kennt nur Kommazahlen: aus der Steam-ID 570 wird beim Laden 570.0, und str() macht
## daraus "570.0". Damit fand Uzai nach einem Neustart weder Cover noch Steam-Daten.
const INT_FIELDS := ["appid", "last_played", "playtime", "plays", "added", "steam_minutes", "steam_last", "ra_id", "size", "install_time",
	"store_minutes", "store_last"]


static func fix_numbers(g: Dictionary) -> void:
	for k in INT_FIELDS:
		if g.get(k) is float:
			g[k] = int(g[k])


## Frühere „Sammlungen“ werden zu Ordnern für alle Systeme.
func _migrate_collections() -> void:
	if collections.is_empty():
		return
	for c in collections:
		var fid := "f_" + str(c).md5_text().substr(0, 8)
		if folder(fid).is_empty():
			folders.append({ "id": fid, "name": str(c), "system": "" })
		for g in games:
			if str(c) in g.get("collections", []):
				var f: Array = g.get("folders", [])
				if not f.has(fid):
					f.append(fid)
				g["folders"] = f
	for g in games:
		g.erase("collections")
	collections = []


func load_demo() -> void:
	demo = true
	var data: Variant = Config.read_json("res://tests/demo_library.json", {})
	if data is Dictionary:
		games = data.get("games", [])
		collections = data.get("collections", [])
		folders = data.get("folders", [])
		lists = Backlog.clean_lists(data.get("lists", []))
		goals = Backlog.clean_goals(data.get("goals", {}))
		_migrate_collections()
		var now := int(Time.get_unix_time_from_system())
		if data.has("goal_this_year"):
			goals[str(Time.get_date_dict_from_system().year)] = int(data.goal_this_year)
		for g in games:
			# Zeitangaben im Demo-Datensatz sind relativ ("vor x Stunden").
			if g.has("last_played_hours_ago"):
				g["last_played"] = now - int(g.last_played_hours_ago * 3600)
			if g.has("added_hours_ago"):
				g["added"] = now - int(g.added_hours_ago * 3600)
			if g.has("done_days_ago"):
				g["done_at"] = now - int(g.done_days_ago * 86400)
				g["status_at"] = g.done_at
				g.erase("done_days_ago")
			if g.get("diary") is Array:
				for e in g.diary:
					if e is Dictionary and e.has("days_ago"):
						e["at"] = now - int(float(e.days_ago) * 86400)
						e.erase("days_ago")
			fix_numbers(g)
			Backlog.sanitize(g)
	relink()
	_reindex()
	_rebuild_serials()


## Persönliches des aktiven Profils an die Spiele setzen. legacy: Stand vor den Profilen aus
## library.json – gehört dem ersten Profil (wird in dessen spieler.json geschrieben).
func _load_personal(legacy: Dictionary) -> void:
	var owner := Config.legacy_owner()
	var per: Dictionary
	if not legacy.is_empty() and owner == Config.profile_id:
		per = Profiles.clean_personal(legacy)
	else:
		if not legacy.is_empty():
			var odir := Profiles.dir_of(Config.data_dir, owner)
			if odir != "":
				Config.write_json(odir.path_join("spieler.json"), legacy)
		per = Profiles.clean_personal(Config.read_json(Config.path("spieler.json"), {}))
	if not legacy.is_empty():
		_dirty = true
	Profiles.apply_personal(games, per)
	lists = Backlog.clean_lists(per.lists)
	goals = Backlog.clean_goals(per.goals)
	if _dirty and is_instance_valid(_save_timer):
		# Gleich getrennt speichern: library.json ohne Persönliches, spieler.json mit.
		_save_timer.start()


## Titel, den ein Freund gerade spielt, so wie er in der Bibliothek heißt: Steam meldet ihn in der
## Schreibweise des Herstellers („ELDEN RING“), daneben stand dann „Elden Ring“. Erst über die
## Steam-ID, sonst über den Titel ohne Groß/klein und Satzzeichen; sonst unverändert.
func friend_game_title(game: String, game_id := "") -> String:
	if game == "":
		return ""
	if game_id != "":
		var g := get_game("steam:" + game_id)
		if not g.is_empty():
			return display_title(g)
	if _title_idx.is_empty() or _title_idx_size != games.size():
		_title_idx.clear()
		for g2 in games:
			_title_idx[title_key(display_title(g2))] = display_title(g2)
		_title_idx_size = games.size()
	return str(_title_idx.get(title_key(game), game))


var _title_idx_size := -1


## Alles außer a–z, 0–9 und Zeichen jenseits von ASCII fällt weg (ein Lauf der Engine statt Zeichen für Zeichen).
static var _RX_TITEL := RegEx.create_from_string("[^a-z0-9\\x{80}-\\x{10FFFF}]+")


static func title_key(t: String) -> String:
	return _RX_TITEL.sub(t.to_lower(), "", true)


# --- Abfragen ----------------------------------------------------------------

func favorites() -> Array:
	return visible_games().filter(func(g): return g.get("favorite", false))


# --- Doppelte: ein Spiel in mehreren Launchern (stores.gd) ---------------------------------------

## Alle Einträge eines Spiels über die Launcher hinweg, der vordere zuerst; ohne Doppelte nur das
## Spiel selbst. Nur installierte, vorhandene.
func alternatives(g: Dictionary) -> Array:
	var out: Array = [g]
	for a in _alt_list(g):
		if is_installed(a) and not bool(a.get("missing", false)):
			out.append(a)
	return out


## Was beim Start wirklich startet: bei Doppelten der gewählte Launcher (launch_via), als Kopie mit
## ID und Titel des vorderen Eintrags – Spielzeit, Zuletzt und Profil bleiben so an einem Spiel.
## Felder mit „_“ vorn (Spielstände, Remote Play) gehen mit.
func launch_target(g: Dictionary) -> Dictionary:
	var via := str(g.get("launch_via", ""))
	if via == "" or via == str(g.get("source", "")):
		return g
	for a in alternatives(g).slice(1):
		if str(a.get("source", "")) == via:
			var run: Dictionary = (a as Dictionary).duplicate(true)
			run["id"] = str(g.get("id", ""))
			run["title"] = display_title(g)
			run["via_id"] = str(a.get("id", ""))
			for k in g.keys():
				if str(k).begins_with("_"):
					run[k] = g[k]
			return run
	return g


# --- Ändern ------------------------------------------------------------------

func set_field(id: String, key: String, value: Variant) -> void:
	var g := get_game(id)
	if g.is_empty():
		return
	if value == null or (value is String and value == ""):
		g.erase(key)
	else:
		g[key] = value
	if key == "title":
		g["title_custom"] = true
	if key == "images":
		Media.forget(g)
	mark_dirty()
	changed.emit()


## Eine Änderung an vielen Spielen auf einmal (GameFields.apply_op), danach einmal speichern und
## melden statt je Spiel. Gibt zurück, wie viele sich wirklich geändert haben.
func update_many(ids: Array, op: String, value: Variant) -> int:
	var known: Variant = []
	if op == "tag_add":
		known = GameFields.all_tags(games).keys()
	elif op == "category":
		known = GameFields.categories(games).keys()
	var n := 0
	var now := int(Time.get_unix_time_from_system())
	for id in ids:
		var g := get_game(str(id))
		if g.is_empty():
			continue
		if Backlog.apply_op(g, op, value, now) if op in Backlog.OPS else GameFields.apply_op(g, op, value, known):
			n += 1
	if n > 0:
		mark_dirty()
		changed.emit()
	return n


func toggle_favorite(id: String) -> bool:
	var g := get_game(id)
	var v := not bool(g.get("favorite", false))
	set_field(id, "favorite", v if v else null)
	return v


# --- Einlesen ----------------------------------------------------------------

func steam_root() -> String:
	return _steam_root


## „128 Spiele · 3 entfernt (Datei fehlt oder unvollständig)“
static func scan_text(r: Dictionary) -> String:
	var parts := PackedStringArray([Lang.count(int(r.get("games", 0)), "Spiel", "Spiele")])
	var gone := int(r.get("gone", 0))
	var skipped := int(r.get("skipped", 0))
	if gone > 0:
		parts.append("%d entfernt (Datei fehlt oder unvollständig)" % gone)
	elif skipped > 0:
		parts.append("%d unvollständige Dateien übersprungen" % skipped)
	else:
		parts.append("nichts kaputt")
	return "  ·  ".join(parts)


func launcher_missing(id: String) -> bool:
	if Stores.is_extra(id) and not bool(launcher_need.get(id, false)):
		return false
	return launchers.has(id) and not bool(launchers[id])


## force_online: die Liste aus dem Epic-Konto sofort neu holen („Jetzt neu einlesen“); sonst nur,
## wenn sie älter als ein paar Stunden ist. report: am Ende kurz sagen, was sich getan hat (von Hand
## angestoßen: „Spiele neu einlesen“).
func scan(force_online := false, report := false) -> void:
	if demo:
		return
	if report:
		_scan_report = true
	if scanning:
		# Ein neuer Spieleordner, während noch eingelesen wird (in der Einrichtung liest Uzai Steam
		# schon, wenn die gefundenen Ordner übernommen werden): gleich danach noch einmal, statt
		# den Wunsch zu verwerfen – sonst fehlten ihre Spiele bis zum nächsten Start.
		_scan_again = "online" if force_online or _scan_again == "online" else "ja"
		return
	scanning = true
	scan_state.emit("Bibliothek wird eingelesen …")
	scan_log("Einlesen: Start")
	# Das Einlesen selbst läuft in einer eigenen Funktion. Bricht sie mit einem Skriptfehler ab (eine Datei eines
	# Launchers in unerwarteter Form), geht es hier trotzdem weiter (gemessen: der Aufrufer läuft weiter, das
	# Ergebnis ist dann leer). Vorher blieb „scanning“ in so einem Fall für immer stehen: Die Meldung „Bibliothek
	# wird eingelesen …“ ging nie weg, und Uzai las bis zum Neustart nichts mehr ein.
	var ergebnis: Dictionary = await _einlesen(force_online)
	scanning = false
	if ergebnis.is_empty():
		scan_log("Einlesen: mit einem Fehler abgebrochen")
	else:
		scan_log("Einlesen: fertig")
		last_scan = ergebnis
	scan_state.emit("")
	if _scan_report and _scan_again == "":
		_scan_report = false
		if ergebnis.is_empty():
			Toasts.show_toast("Einlesen ging nicht ganz", "Was gefunden wurde, steht in der Bibliothek. Später noch einmal einlesen.", "warning", { "ms": 6000 })
		else:
			Toasts.show_toast("Neu eingelesen", scan_text(last_scan), "refresh", { "ms": 5000 })
	if _scan_again != "":
		var online := _scan_again == "online"
		_scan_again = ""
		scan(online)


## Alle Quellen lesen und zusammenführen. { at, gone, skipped, games } – leer nur, wenn es mit einem Fehler abbrach.
func _einlesen(force_online: bool) -> Dictionary:
	# Fand der Scan nichts Neues, weder speichern noch melden: Früher baute sich bei jedem Start
	# ein paar Sekunden nach dem Einschalten die Startseite neu auf (mitten in die erste Bedienung).
	var before := JSON.stringify([games, folders]).md5_text()
	var found: Array = []
	var rom_systems: Array = []
	var skipped: Array = []
	# Quellen, deren Einlesen diesmal nicht ging (Scan abgebrochen, Helfer ohne Antwort): Ihre Spiele bleiben stehen.
	# Vorher galten sie alle als verschwunden und fehlten bis zum nächsten gelungenen Einlesen.
	var bleibt: Array = []
	for sys in Config.systems_enabled():
		var dir := Config.rom_dir(str(sys.id))
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			scan_state.emit("%s wird durchsucht …" % sys.name)
			scan_log("Einlesen: %s in %s" % [sys.id, dir])
			var res := await _threaded(RomScanner.scan_full.bind(sys, dir))
			if _scan_abbruch or res.is_empty() or not (res[0] is Array):
				scan_log("Einlesen: %s – abgebrochen, die bisherigen Spiele bleiben" % sys.id)
				continue
			var got: Array = res[0]
			var skip: Array = res[1] if res.size() > 1 and res[1] is Array else []
			scan_log("Einlesen: %s – %d Spiele%s" % [sys.id, got.size(), (", %d Dateien übersprungen" % skip.size()) if not skip.is_empty() else ""])
			for k in skip:
				scan_log("Einlesen: übersprungen (%s): %s" % [str(k.why), str(k.path)])
			found.append_array(got)
			skipped.append_array(skip)
			rom_systems.append(str(sys.id))
	if Config.get_value("library.steam_enabled", true):
		var reg := ""
		var gefragt := not Config.is_windows()
		if Config.is_windows():
			var r := await Helper.run("steam-path")
			if r.ok:
				reg = str(r.result.get("path", ""))
				gefragt = true
		_steam_root = SteamScanner.find_root(str(Config.get_value("library.steam_dir", "")), reg)
		if Config.is_windows() and (gefragt or _steam_root != ""):
			launchers["steam"] = _steam_root != ""
		if _steam_root != "":
			scan_state.emit("Steam-Bibliothek wird gelesen …")
			found.append_array(await _threaded(SteamScanner.scan.bind(_steam_root)))
			if _scan_abbruch:
				bleibt.append("steam")
		elif not gefragt:
			# Der Helfer hat nicht geantwortet (er startet gerade): Wo Steam liegt, ist dann unbekannt – nicht „kein Steam“.
			scan_log("Einlesen: Steam – Ordner nicht ermittelt (Helfer ohne Antwort), die bisherigen Spiele bleiben")
			bleibt.append("steam")
		# Mit Steam-Schlüssel kommt die Spielzeit immer von Steam; nicht installierte Spiele nur auf Wunsch.
		if Social.has_steam():
			scan_state.emit("Spielzeit von Steam wird geholt …")
			var owned: Array = await Social.steam_owned_games()
			var mit_gekauften := bool(Config.get_value("library.steam_owned", false))
			if owned.is_empty() and mit_gekauften:
				# Ohne Netz (oder Steam antwortet nicht) ist die Liste leer – das heißt nicht „nichts gekauft“. Sonst
				# verschwänden alle nicht installierten Steam-Spiele bis zum nächsten gelungenen Einlesen.
				scan_log("Einlesen: Steam – gekaufte Spiele nicht erreichbar, die bisherigen bleiben")
				bleibt.append("steam")
			found = _merge_owned(found, owned, mit_gekauften)
	var epic_dirs: Array = []
	if Config.get_value("library.epic_enabled", true) and Config.is_windows():
		launchers["epic"] = EpicScanner.launcher_present()
		scan_state.emit("Epic-Spiele werden gelesen …")
		var eg := await _scan_epic(force_online)
		if _epic_abbruch:
			bleibt.append("epic")
		for g in eg:
			if is_installed(g):
				epic_dirs.append(str(g.get("install_dir", "")))
		found.append_array(eg)
	if Config.get_value("library.ea_enabled", true) and Config.is_windows():
		scan_state.emit("EA-Spiele werden gelesen …")
		# Spielordner und Start-Links aus der Registry liest der Helfer (nur lesen); den Rest Uzai.
		var r := await Helper.run("ea-games", {}, 15.0)
		var reg: Array = []
		var protos := {}
		if r.ok and r.result is Dictionary:
			var rg: Variant = r.result.get("games", [])
			reg = rg if rg is Array else ([rg] if rg is Dictionary else [])
			protos = { "origin2": bool(r.result.get("origin2", false)), "link2ea": bool(r.result.get("link2ea", false)) }
			# Die EA app (wie früher Origin) meldet ihre Start-Links bei Windows an.
			launchers["ea"] = bool(protos.origin2) or bool(protos.link2ea)
		var ea := await _threaded(EaScanner.scan.bind(reg, protos, epic_dirs))
		if _scan_abbruch or not r.ok:
			bleibt.append("ea")
		scan_log("Einlesen: EA – %d Spiele (%d Ordner aus der Registry)%s" % [ea.size(), reg.size(), "" if r.ok else ", Helfer ohne Antwort"])
		found.append_array(ea)
	var keep: Array = []
	if Config.is_windows() and Stores.EXTRA.any(func(id: String) -> bool: return Stores.enabled(id)):
		keep = await _scan_stores(found)
	keep.append_array(bleibt)
	var pc_dirs: Array = Config.get_value("library.pc_dirs", [])
	if not pc_dirs.is_empty():
		scan_state.emit("PC-Spiele werden gelesen …")
		var pcs := await _threaded(PcScanner.scan.bind(pc_dirs))
		for g in pcs:
			if str(g.path).get_extension().to_lower() == "lnk" and Config.is_windows():
				var r := await Helper.run("lnk", { "path": str(g.path).replace("/", "\\") })
				# Ziel auf eine Kommandozeile oder einen Skript-Host: nicht übernehmen – der Start prüft die .lnk dann selbst
				# und lehnt sie ab (Launcher.lnk_ziel_gesperrt).
				if r.ok and str(r.result.get("target", "")).to_lower().ends_with(".exe") and not Launcher.lnk_ziel_gesperrt(str(r.result.target)):
					g["target"] = str(r.result.target).replace("\\", "/")
					g["args"] = str(r.result.get("args", ""))
					var wd := str(r.result.get("dir", "")).replace("\\", "/")
					g["install_dir"] = wd if wd != "" else str(g.target).get_base_dir()
		found.append_array(pcs)
	scan_log("Einlesen: zusammenführen (%d)" % found.size())
	var gone := _merge(found, [], keep, rom_systems)
	# Gefundenes gleich zeigen, nicht erst nach den Seriennummern der Discs: Die lesen beim ersten
	# Einlesen jedes Abbild und laden Listen nach – so lange bliebe die Startseite sonst leer.
	if JSON.stringify([games, folders]).md5_text() != before:
		save()
		changed.emit()
	await _index_discs()
	return { "at": int(Time.get_unix_time_from_system()), "gone": gone, "skipped": skipped.size(), "games": visible_games().size() }

extends "res://src/library/library_quellen.gd"
## Bibliothek, Schicht über library_quellen.gd: Ordnung – Ordner, Backlog, Rückgängig und Genre
## und Jahr aus dem Steam-Shop.

const PcScanner := preload("res://src/library/pc_scanner.gd")
const GameFinder := preload("res://src/library/game_finder.gd")
const GameFilter := preload("res://src/library/game_filter.gd")
const GameFields := preload("res://src/library/game_fields.gd")
const Backlog := preload("res://src/library/backlog.gd")

## Backlog (src/library/backlog.gd): Listen und Jahresziele änderten sich – Spiele selbst melden
## wie immer changed.
signal backlog_changed


# --- Ordner -------------------------------------------------------------------

func folder(id: String) -> Dictionary:
	if id.begins_with("auto:"):
		var parts := id.split(":", true, 2)
		if parts.size() == 3:
			return { "id": id, "name": parts[2], "system": parts[1], "auto": true }
		return {}
	for f in folders:
		if str(f.id) == id:
			return f
	return {}


func global_folders() -> Array:
	return folders.filter(func(f): return str(f.get("system", "")) == "")


## Ordner, die im Reiter eines Systems als Kacheln erscheinen.
func folders_for(system_id: String) -> Array:
	var out: Array = folders.filter(func(f): return str(f.get("system", "")) == system_id)
	if Config.system(system_id).get("subfolders", true):
		var count := {}
		for g in by_system(system_id):
			var sd := str(g.get("subdir", ""))
			if sd != "":
				count[sd] = int(count.get(sd, 0)) + 1
		var names: Array = count.keys().filter(func(k): return int(count[k]) >= 2)
		names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
		for n in names:
			out.append({ "id": "auto:%s:%s" % [system_id, n], "name": n, "system": system_id, "auto": true })
	return out


func in_folder(id: String) -> Array:
	if id.begins_with("auto:"):
		var f := folder(id)
		return by_system(str(f.get("system", ""))).filter(func(g): return str(g.get("subdir", "")) == str(f.get("name", "")))
	return visible_games().filter(func(g): return id in g.get("folders", []))


func is_in_folder(g: Dictionary, id: String) -> bool:
	if id.begins_with("auto:"):
		var f := folder(id)
		return g.get("system") == f.get("system") and str(g.get("subdir", "")) == str(f.get("name", ""))
	return id in g.get("folders", [])


func create_folder(name: String, system_id := "") -> String:
	name = name.strip_edges()
	if name == "":
		return ""
	for f in folders:
		if str(f.name).to_lower() == name.to_lower() and str(f.get("system", "")) == system_id:
			return str(f.id)
	# Zwei Ordner im selben Augenblick (Sammelanlage) bekamen sonst dieselbe Kennung.
	var fid := "f_%d" % (Time.get_ticks_usec() % 100000000)
	while folders.any(func(f: Dictionary) -> bool: return str(f.get("id", "")) == fid):
		fid = "f_%d" % ((int(fid.trim_prefix("f_")) + 1) % 100000000)
	folders.append({ "id": fid, "name": name, "system": system_id })
	mark_dirty()
	changed.emit()
	return fid


func rename_folder(id: String, name: String) -> void:
	var f := folder(id)
	if f.is_empty() or f.get("auto", false) or name.strip_edges() == "":
		return
	f["name"] = name.strip_edges()
	mark_dirty()
	changed.emit()


func delete_folder(id: String) -> void:
	folders = folders.filter(func(f): return str(f.id) != id)
	for g in games:
		var fl: Array = g.get("folders", [])
		if fl.has(id):
			fl.erase(id)
			if fl.is_empty():
				g.erase("folders")
	mark_dirty()
	changed.emit()


func set_in_folder(gid: String, fid: String, on: bool) -> void:
	var g := get_game(gid)
	if g.is_empty() or fid.begins_with("auto:"):
		return
	var fl: Array = (g.get("folders", []) as Array).duplicate()
	if on and not fl.has(fid):
		fl.append(fid)
	elif not on:
		fl.erase(fid)
	if fl.is_empty():
		g.erase("folders")
	else:
		g["folders"] = fl
	mark_dirty()
	changed.emit()


## Ordner, in die ein Spiel passt (eigenes System und Ordner für alle).
func folders_for_game(g: Dictionary) -> Array:
	var sys := str(g.get("system", ""))
	return folders.filter(func(f): return str(f.get("system", "")) in ["", sys])


## Zuletzt gespielt, neueste zuerst; mit weniger als sechs gespielten kommen die neuesten ungespielten dazu. Wann
## ein Spiel zuletzt lief, fragt Uzai je Spiel einmal, nicht bei jedem Vergleich: gemessen bei 3000 Spielen 24 ms je
## Aufruf – und Startseite, „Für dich“ und Profil fragen alle. Gleich alte bleiben in der Reihenfolge der Liste.
func recent(limit := 24) -> Array:
	var gespielt: Array = []          # [zuletzt, Platz, Spiel]
	var frisch: Array = []
	for g: Dictionary in _sichtbar():
		if owned_only(g):
			continue
		var t := last_played(g)
		if t > 0:
			gespielt.append([t, gespielt.size(), g])
		else:
			frisch.append(g)
	gespielt.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) if int(a[0]) != int(b[0]) else int(a[1]) < int(b[1]))
	var out: Array = []
	for p: Array in gespielt.slice(0, limit):
		out.append(p[2])
	if gespielt.size() < 6:
		frisch.sort_custom(newer)
		out.append_array(frisch.slice(0, 12 - gespielt.size()))
	return out.slice(0, limit)


## Später dazugekommen? Zuerst der Tag, an dem Uzai das Spiel fand; am selben Tag – etwa alles
## vom ersten Einlesen – das, was der Launcher bzw. die Datei zuletzt installiert oder aktualisiert
## hat. Sonst stünden nach der Einrichtung alle Spiele in zufälliger Reihenfolge (gleiche Zeit).
static func newer(a: Dictionary, b: Dictionary) -> bool:
	var da := floori(int(a.get("added", 0)) / 86400.0)
	var db := floori(int(b.get("added", 0)) / 86400.0)
	if da != db:
		return da > db
	var ia := int(a.get("install_time", 0))
	var ib := int(b.get("install_time", 0))
	if ia != ib:
		return ia > ib
	return int(a.get("added", 0)) > int(b.get("added", 0))


## Die Schlüssel (Titel, Spielzeit, zuletzt gespielt) bildet Uzai je Spiel einmal, nicht bei jedem Vergleich neu:
## gemessen vorher bei 5000 Spielen 169 ms („zuletzt“), 114 ms (Spielzeit) und 73 ms (Titel) je Aufruf – und
## sortiert wird an vielen Stellen. Gleiche Schlüssel bleiben in der Reihenfolge der Liste.
func sorted(list: Array, mode := "") -> Array:
	var m := mode if mode != "" else str(Config.get_value("library.sort", "recent"))
	var out := list.duplicate()
	var paare: Array = []
	match m:
		"title":
			for i in list.size():
				paare.append([display_title(list[i]), i])
			paare.sort_custom(func(a: Array, b: Array) -> bool:
				var c := str(a[0]).naturalnocasecmp_to(str(b[0]))
				return c < 0 if c != 0 else int(a[1]) < int(b[1]))
		"playtime":
			for i in list.size():
				paare.append([playtime(list[i]), i])
			paare.sort_custom(func(a: Array, b: Array) -> bool:
				return int(a[0]) > int(b[0]) if int(a[0]) != int(b[0]) else int(a[1]) < int(b[1]))
		"added":
			out.sort_custom(newer)
		_:
			for i in list.size():
				paare.append([zuletzt_schluessel(list[i]), i, display_title(list[i])])
			paare.sort_custom(func(a: Array, b: Array) -> bool:
				if int(a[0]) != int(b[0]):
					return int(a[0]) > int(b[0])
				var c := str(a[2]).naturalnocasecmp_to(str(b[2]))
				return c < 0 if c != 0 else int(a[1]) < int(b[1]))
	if m != "added":
		out = []
		for p: Array in paare:
			out.append(list[int(p[1])])
	# Nicht installierte Epic-Spiele immer hinter den installierten (Reihenfolge sonst wie gewählt).
	if out.any(owned_only):
		out = out.filter(func(g): return not owned_only(g)) + out.filter(owned_only)
	return out


## Woher ein Spiel kommt, für Pillen und Zeilen: „Steam“, „Epic Games“, „EA app“, „PC“
## (short: „Epic“, „EA“). Emulator-Spiele: fallback (dann zählt der Name des Systems).
static func store_name(g: Dictionary, short := false, fallback := "") -> String:
	var n := Stores.name_of(str(g.get("source", "")), short)
	return n if n != "" else fallback


## Sort key for „Zuletzt“: last played. A game added by hand counts as just played from the moment it was added,
## so a new addition appears at the front and then moves back like the others.
func zuletzt_schluessel(g: Dictionary) -> int:
	var t := last_played(g)
	return maxi(t, int(g.get("added", 0))) if eigen(g) else t


func last_played(g: Dictionary) -> int:
	var t := last_in(g)
	for a in _alt_list(g):
		t = maxi(t, last_in(a))
	return t


## Spielzeit in Sekunden (eigene Messung oder die des Launchers – Steam, GOG Galaxy, itch –, je
## nachdem was größer ist). Mit Doppelten (dasselbe Spiel in mehreren Launchern) der größte Wert:
## Zusammengezählt würde eine Runde über GOG doppelt zählen (Uzai misst sie am vorderen Eintrag).
func playtime(g: Dictionary) -> int:
	var t := time_in(g)
	for a in _alt_list(g):
		t = maxi(t, time_in(a))
	return t


## Zuletzt gespielt bzw. Spielzeit (Sekunden) nur dieses einen Eintrags, ohne seine Doppelten.
static func last_in(g: Dictionary) -> int:
	return maxi(int(g.get("last_played", 0)), maxi(int(g.get("steam_last", 0)), int(g.get("store_last", 0))))


static func time_in(g: Dictionary) -> int:
	return maxi(int(g.get("playtime", 0)), maxi(int(g.get("steam_minutes", 0)), int(g.get("store_minutes", 0))) * 60)


func _alt_list(g: Dictionary) -> Array:
	var out: Array = []
	var a: Variant = g.get("alts")
	if a is Array:
		for id in a:
			var x := get_game(str(id))
			if not x.is_empty() and str(x.get("dupe_of", "")) == str(g.get("id", "")):
				out.append(x)
	return out


# --- Backlog (src/library/backlog.gd) -----------------------------------------------------------

## Eine Änderung am Backlog eines Spiels (f bekommt das Spiel und gibt true zurück, wenn sich etwas
## geändert hat): dann speichern und melden.
func backlog_edit(id: String, f: Callable) -> bool:
	var g := get_game(id)
	if g.is_empty() or not bool(f.call(g)):
		return false
	mark_dirty()
	changed.emit()
	return true


func set_status(id: String, s: String) -> bool:
	return backlog_edit(id, func(g: Dictionary) -> bool: return Backlog.set_status(g, s, int(Time.get_unix_time_from_system())))


func set_stars(id: String, half: int) -> bool:
	return backlog_edit(id, func(g: Dictionary) -> bool: return Backlog.set_stars(g, half))


func set_review(id: String, text: String) -> bool:
	return backlog_edit(id, func(g: Dictionary) -> bool: return Backlog.set_review(g, text))


func add_diary(id: String, at: int, secs: int, note: String) -> bool:
	return backlog_edit(id, func(g: Dictionary) -> bool: return Backlog.add_diary(g, at, secs, note))


func remove_diary(id: String, at: int) -> bool:
	return backlog_edit(id, func(g: Dictionary) -> bool: return Backlog.remove_diary(g, at))


func list_by_id(lid: String) -> Dictionary:
	return Backlog.list_by_id(lists, lid)


## Neue Liste (mit einem ersten Spiel, wenn gid gesetzt). Leer, wenn der Name leer ist oder es schon
## zu viele Listen gibt.
func new_list(name: String, gid := "") -> Dictionary:
	var l := Backlog.new_list(lists, name, int(Time.get_unix_time_from_system()))
	if l.is_empty():
		return l
	if gid != "":
		Backlog.list_toggle(l, gid, true)
	_lists_changed()
	return l


func rename_list(lid: String, name: String) -> void:
	var l := list_by_id(lid)
	var n := GameFields.clean_text(name, Backlog.LIST_NAME_MAX)
	if l.is_empty() or n == "" or n == str(l.name):
		return
	l["name"] = n
	_lists_changed()


## Liste löschen (die Spiele bleiben). Gibt Liste und Platz zurück, damit Rückgängig sie genau
## wieder einsetzen kann (put_list).
func delete_list(lid: String) -> Array:
	for i in lists.size():
		if str(lists[i].get("id", "")) == lid:
			var l: Dictionary = lists[i]
			lists.remove_at(i)
			_lists_changed()
			return [l.duplicate(true), i]
	return []


func put_list(l: Dictionary, at: int) -> void:
	if l.is_empty() or not list_by_id(str(l.get("id", ""))).is_empty():
		return
	lists.insert(clampi(at, 0, lists.size()), l.duplicate(true))
	_lists_changed()


func list_toggle(lid: String, gid: String, on: bool) -> bool:
	var l := list_by_id(lid)
	if l.is_empty() or not Backlog.list_toggle(l, gid, on):
		return false
	_lists_changed()
	return true


func list_move(lid: String, gid: String, dir: int) -> bool:
	var l := list_by_id(lid)
	if l.is_empty() or not Backlog.list_move(l, gid, dir):
		return false
	_lists_changed()
	return true


## Reihenfolge einer Liste ganz setzen (Rückgängig nach „Aus der Liste nehmen“).
func set_list_games(lid: String, gids: Array) -> void:
	var l := list_by_id(lid)
	if l.is_empty():
		return
	l["games"] = Backlog.clean_lists([{ "id": lid, "name": str(l.name), "games": gids }])[0].games
	_lists_changed()


## Spiele einer Liste in ihrer Reihenfolge (was es nicht mehr gibt oder ausgeblendet ist, fehlt).
func list_games(lid: String) -> Array:
	var out: Array = []
	for gid in list_by_id(lid).get("games", []):
		var g := get_game(str(gid))
		if not g.is_empty() and not bool(g.get("hidden", false)):
			out.append(g)
	return out


## Jahresziel setzen (0 nimmt es weg).
func set_goal(year: int, n: int) -> void:
	var k := str(year)
	var v := clampi(n, 0, Backlog.GOAL_MAX)
	if v == int(goals.get(k, 0)):
		return
	if v <= 0:
		goals.erase(k)
	else:
		goals[k] = v
	_lists_changed()


func _lists_changed() -> void:
	mark_dirty()
	backlog_changed.emit()


var sessions: Array = []     ## [{ id, at, secs }] für die Statistik (letzte 2000)
var _sessions_loaded := false


func load_sessions() -> Array:
	if not _sessions_loaded:
		_sessions_loaded = true
		if demo:
			var now := int(Time.get_unix_time_from_system())
			var vis := visible_games()
			for i in 40:
				if vis.is_empty():
					break
				var g: Dictionary = vis[(i * 7) % vis.size()]
				sessions.append({ "id": str(g.id), "at": now - i * 52000, "secs": 1200 + (i * 997) % 7200 })
		else:
			var d: Variant = Config.read_json(Config.path("sessions.json"), [])
			if d is Array:
				sessions = (d as Array).filter(func(e: Variant) -> bool: return e is Dictionary)
	return sessions


func record_session(id: String, seconds: int) -> void:
	var g := get_game(id)
	if g.is_empty():
		return
	load_sessions()
	if seconds >= 30:
		sessions.push_front({ "id": id, "at": int(Time.get_unix_time_from_system()), "secs": seconds })
		sessions = sessions.slice(0, 2000)
		if not demo:
			Config.write_json(Config.path("sessions.json"), sessions)
	g["last_played"] = int(Time.get_unix_time_from_system())
	g["playtime"] = int(g.get("playtime", 0)) + maxi(seconds, 0)
	g["plays"] = int(g.get("plays", 0)) + 1
	mark_dirty()
	changed.emit()


func touch(id: String) -> void:
	var g := get_game(id)
	if g.is_empty():
		return
	g["last_played"] = int(Time.get_unix_time_from_system())
	mark_dirty()


## Eigenes Spiel über seine Programmdatei (Punkt 117). {} wenn Datei oder Parameter nicht passen
## (GameFinder prüft). Schon bekannt: der vorhandene Eintrag.
func add_manual(title: String, exe: String, args := "", work_dir := "") -> Dictionary:
	if GameFinder.exe_problem(exe) != "" or GameFinder.args_problem(args, exe) != "" or GameFinder.dir_problem(work_dir) != "":
		return {}
	var g := {
		"id": "pc:%s" % exe.md5_text().substr(0, 14),
		"title": title.strip_edges() if title.strip_edges() != "" else GameFinder.suggest_name(exe, exe.get_base_dir().get_file()),
		"system": "pc",
		"source": "pc",
		"path": exe,
		"args": args,
		"install_dir": exe.get_base_dir(),
		"installed": true,
		"added": int(Time.get_unix_time_from_system()),
	}
	if work_dir != "":
		g["work_dir"] = work_dir
	if exe.get_extension().to_lower() == "url":
		g["url"] = PcScanner.read_url(exe)
	if _by_id.has(g.id):
		return _by_id[g.id]
	games.append(g)
	_reindex()
	mark_dirty()
	changed.emit()
	return g


func remove(id: String) -> void:
	games = games.filter(func(g): return g.get("id") != id)
	_reindex()
	mark_dirty()
	changed.emit()


# --- Rückgängig (src/core/undo.gd) -------------------------------------------------------------

## Stand dieser Spiele (tiefe Kopien samt Platz in der Liste) und auf Wunsch der Ordner – vor einer
## Änderung gemerkt, damit restore sie genau zurücknehmen kann.
func snapshot(ids: Array, with_folders := false) -> Dictionary:
	var want := {}
	for id in ids:
		want[str(id)] = true
	var gs := {}
	var at := {}
	for i in games.size():
		var id := str(games[i].get("id", ""))
		if want.has(id):
			gs[id] = (games[i] as Dictionary).duplicate(true)
			at[id] = i
	var snap := { "games": gs, "at": at }
	if with_folders:
		snap["folders"] = folders.duplicate(true)
	return snap


## Zurück auf den gemerkten Stand: geänderte Spiele bekommen ihre alten Felder (dasselbe Objekt,
## offene Seiten sehen es gleich), entfernte kommen an ihren alten Platz zurück.
func restore(snap: Dictionary) -> void:
	var gs: Dictionary = snap.get("games", {})
	var at: Dictionary = snap.get("at", {})
	var back: Array = []
	for id in gs:
		var g := get_game(str(id))
		if g.is_empty():
			back.append(str(id))
			continue
		var old: Dictionary = (gs[id] as Dictionary).duplicate(true)
		var pics: bool = g.get("images") != old.get("images")
		g.clear()
		g.merge(old)
		if pics:
			Media.forget(g)
	back.sort_custom(func(a: String, b: String) -> bool: return int(at.get(a, 0)) < int(at.get(b, 0)))
	for id in back:
		games.insert(clampi(int(at.get(id, games.size())), 0, games.size()), (gs[id] as Dictionary).duplicate(true))
	if snap.has("folders"):
		folders = (snap.folders as Array).duplicate(true)
	_reindex()
	if not back.is_empty():
		_rebuild_serials()
	mark_dirty()
	changed.emit()


signal meta_progress(done: int, total: int)

## Abstand zwischen zwei Abfragen: Steam drosselt den Shop ab etwa 200 Abfragen in 5 Minuten.
const META_GAP := 1.6

var meta_running := false
var _meta_stop := false


# --- Genre und Jahr aus dem Steam-Shop (Filter und Abschnitte im Raster) -----------------------

## Genre und Erscheinungsjahr aus den Shop-Angaben (Store.details) am Steam-Spiel merken. Leere
## Angaben (der Shop kennt das Spiel nicht mehr) zählen als nachgesehen, damit „Angaben holen“
## nicht immer wieder dieselben fragt. Ändert sich nichts, bleibt die Bibliothek unberührt.
func remember_store_meta(appid: int, d: Dictionary) -> void:
	var g := get_game("steam:%d" % appid)
	if g.is_empty():
		return
	var gen: Array = []
	for x in d.get("genres", PackedStringArray()):
		var s := str(x).strip_edges().left(60)
		if s != "" and not gen.has(s):
			gen.append(s)
	var year := 0 if bool(d.get("coming", false)) else GameFilter.year_of(str(d.get("release", "")))
	if g.get("genres") is Array and g.genres == gen and int(g.get("year", 0)) == year:
		return
	g["genres"] = gen
	if year > 0:
		g["year"] = year
	else:
		g.erase("year")
	mark_dirty()


## Steam-Spiele der Liste, bei denen Genre und Jahr noch nie nachgesehen wurden.
static func lacks_store_meta(list: Array) -> Array:
	return list.filter(func(g): return str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0 and not g.has("genres"))


## Läufe von fetch_store_meta, die gerade unterwegs sind (siehe dort).
var _fetch_store_meta_offen := 0


## Holt fehlende Angaben nacheinander mit Pause – nur auf Wunsch (Raster → Ordnen und filtern).
## Läuft weiter, wenn das Raster zugeht, wartet während eines Spiels und hört auf, wenn der Shop
## mehrmals hintereinander nicht antwortet (Netz weg, gedrosselt). meta_progress meldet den
## Stand, zum Schluss mit done = -1.
func fetch_store_meta(list: Array) -> void:
	_fetch_store_meta_offen += 1
	await _fetch_store_meta_lauf(list)
	_fetch_store_meta_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und fetch_store_meta täte bis zum Neustart nichts mehr.
	if _fetch_store_meta_offen == 0 and meta_running:
		meta_running = false
		meta_progress.emit(-1, 0)      # die Anzeige „Infos werden geladen“ schließt (wie am Ende eines ganzen Laufs)


func _fetch_store_meta_lauf(list: Array) -> void:
	if meta_running:
		return
	var todo := lacks_store_meta(list)
	if todo.is_empty():
		return
	meta_running = true
	_meta_stop = false
	var done := 0
	var misses := 0
	meta_progress.emit(0, todo.size())
	for g in todo:
		while Launcher.in_game and not _meta_stop:
			await get_tree().create_timer(5.0).timeout
		if _meta_stop:
			break
		await Store.details(int(g.appid))
		misses = 0 if g.has("genres") else misses + 1
		done += 1
		meta_progress.emit(done, todo.size())
		if misses >= 5:
			break
		await get_tree().create_timer(0.05 if demo else META_GAP).timeout
	meta_running = false
	meta_progress.emit(-1, todo.size())


func stop_store_meta() -> void:
	_meta_stop = true

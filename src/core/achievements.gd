extends Node
## Erfolge aus RetroAchievements (Emulator-Spiele) und Steam in einem gemeinsamen Format:
## { id, title, desc, icon, icon_locked, unlocked, date, points, rarity, hardcore }

signal updated(what: String)

const RA := "https://retroachievements.org/API/"
const RA_MEDIA := "https://media.retroachievements.org"
const STEAM := "https://api.steampowered.com/"
const SocialS := preload("res://src/core/social.gd")
const Lang := preload("res://src/core/lang.gd")
const FriendsS := preload("res://src/core/achievements_friends.gd")
const SE := preload("res://src/core/steam_erfolge.gd")
const Fremd := preload("res://src/core/fremd.gd")

var friends: Node               ## Erfolge von Freunden (achievements_friends.gd): Stand je Spiel, Feed, Rangliste
var ra_profile := {}            # Name, Punkte, Rang, Bild
var ra_progress: Array = []     # alle gespielten RA-Spiele mit Fortschritt
var recent_unlocks: Array = []  # zuletzt freigeschaltet, beide Quellen gemischt
var steam_progress: Array = []  # zuletzt gespielte Steam-Spiele mit Fortschritt
var loading := false
var last_error := ""
var updated_at := 0             ## wann die Übersicht zuletzt geladen wurde (Unix-Zeit)
var demo := false               ## --demo: Beispieldaten statt Netz
var _games := {}                # Spiel-ID -> Ergebnis
var _ra_lists := {}             # RA-Konsolen-ID -> Spieleliste
var _ra_norm := {}              # RA-Konsolen-ID -> [[angeglichener Titel, ID], …] in der Reihenfolge der Liste
var _ra_list_failed := false    # letzte Spieleliste kam nicht an (Netz)
var _seen_unlocks := {}
var _watch: Timer


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	_watch = Timer.new()
	_watch.wait_time = 60.0
	_watch.timeout.connect(_check_new_unlocks)
	add_child(_watch)
	friends = FriendsS.new()
	friends.name = "Friends"
	add_child(friends)
	Launcher.started.connect(_on_game_started)
	Launcher.ended.connect(_on_game_ended)


func _on_game_started(_g: Dictionary) -> void:
	_seen_unlocks.clear()
	# Neue RetroAchievements im Spiel erkennt und zeigt jetzt Unlocks (eigenes Erfolgs-Pop-up,
	# alle 12 s); es meldet sie über ra_unlocks_arrived hierher. Der alte Takt nur ohne Unlocks.
	if has_ra() and get_node_or_null("/root/Unlocks") == null:
		_watch.start()


func _on_game_ended(_g: Dictionary, _secs: int) -> void:
	_watch.stop()


func has_ra() -> bool:
	if demo:
		return true
	return str(Config.get_value("accounts.ra_user", "")) != "" and str(Config.get_value("accounts.ra_key", "")) != ""


func has_steam() -> bool:
	return Social.has_steam()


## Anmeldung prüfen, bevor Uzai sie speichert (Handy-Assistent, Punkt 49):
## { ok, name, points, error }. Der Schlüssel geht nur an retroachievements.org, nie ins Protokoll.
func check_ra(user: String, key: String) -> Dictionary:
	var err := ra_format_error(user, key)
	if err != "":
		return { "ok": false, "error": err }
	var r := await Net.get_json(RA + "API_GetUserProfile.php?" + Net.query({ "u": user, "y": key }))
	return ra_check_result(int(r.code), r.data)


## Sieht es überhaupt wie ein Name und ein Web-API-Schlüssel aus? (Sonst gar nicht erst fragen.)
static func ra_format_error(user: String, key: String) -> String:
	if user.length() < 2 or user.length() > 32 or not _only(user, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"):
		return "Das sieht nicht wie ein Benutzername von RetroAchievements aus."
	if key.length() < 16 or key.length() > 64 or not _only(key, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"):
		return "Das sieht nicht wie ein Web-API-Schlüssel aus. Er steht auf retroachievements.org unter Einstellungen → Keys (32 Zeichen, nur Buchstaben und Ziffern)."
	return ""


static func _only(s: String, allowed: String) -> bool:
	for ch in s:
		if not allowed.contains(ch):
			return false
	return true


## Antwort von API_GetUserProfile lesen. Falscher Schlüssel: 401; unbekannter Name: 404 oder leer.
static func ra_check_result(code: int, data: Variant) -> Dictionary:
	if code == 200 and data is Dictionary and (data as Dictionary).get("User") is String and str((data as Dictionary).User) != "":
		var d: Dictionary = data
		return { "ok": true, "name": str(d.User), "points": int(d.TotalPoints) if d.get("TotalPoints") != null else 0, "error": "" }
	if code == 401 or code == 403:
		return { "ok": false, "error": "Der Web-API-Schlüssel passt nicht. Auf retroachievements.org unter Einstellungen → Keys nachsehen und neu senden." }
	if code == 404 or code == 422 \
			or (code == 200 and (data == null or (data is Dictionary and (data as Dictionary).is_empty()) or (data is Array and (data as Array).is_empty()))):
		return { "ok": false, "error": "Diesen Benutzernamen kennt RetroAchievements nicht. Schreibweise prüfen und neu senden." }
	if code == 0 or code >= 500:
		return { "ok": false, "error": "RetroAchievements ist gerade nicht erreichbar. Gleich noch einmal versuchen." }
	return { "ok": false, "error": "RetroAchievements hat die Anmeldung abgelehnt. Benutzernamen und Schlüssel prüfen und neu senden." }


func _ra_url(endpoint: String, params: Dictionary) -> String:
	var p := params.duplicate()
	p["y"] = Config.get_value("accounts.ra_key", "")
	if not p.has("u"):
		p["u"] = Config.get_value("accounts.ra_user", "")
	return RA + endpoint + "?" + Net.query(p)


# --- Übersicht -----------------------------------------------------------------

## Läufe von refresh_overview, die gerade unterwegs sind (siehe dort).
var _refresh_overview_offen := 0


func refresh_overview() -> void:
	_refresh_overview_offen += 1
	await _refresh_overview_lauf()
	_refresh_overview_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_overview täte bis zum Neustart nichts mehr.
	if _refresh_overview_offen == 0 and loading:
		loading = false
		last_error = "Die Erfolge ließen sich gerade nicht laden."
		updated.emit("overview")


func _refresh_overview_lauf() -> void:
	if loading:
		return
	loading = true
	last_error = ""
	if demo:
		# Kurz „laden“, damit sich die Seite wie mit echter Verbindung aufbaut.
		await get_tree().create_timer(0.5).timeout
		_load_demo_overview()
		loading = false
		updated_at = int(Time.get_unix_time_from_system())
		updated.emit("overview")
		return
	var unlocks: Array = []
	if has_ra():
		var s := await Net.get_json(_ra_url("API_GetUserSummary.php", { "g": 10, "a": 12 }))
		if s.ok and s.data is Dictionary:
			var d: Dictionary = s.data
			ra_profile = {
				"name": d.get("User", Config.get_value("accounts.ra_user", "")),
				"points": int(d.get("TotalPoints", 0)),
				"true_points": int(d.get("TotalTruePoints", 0)),
				"rank": int(d.get("Rank", 0)) if d.get("Rank") != null else 0,
				"pic": RA_MEDIA + str(d.get("UserPic", "")),
				"softcore": int(d.get("TotalSoftcorePoints", 0)) if d.get("TotalSoftcorePoints") != null else 0,
				"member_since": _ra_date(str(d.get("MemberSince", "")) if d.get("MemberSince") != null else ""),
				"motto": str(d.get("Motto", "")) if d.get("Motto") != null else "",
				"presence": str(d.get("RichPresenceMsg", "")) if d.get("RichPresenceMsg") != null else "",
			}
			# Ohne Erfolge schickt RetroAchievements hier eine leere Liste statt eines Verzeichnisses.
			var rec := Fremd.verz(d.get("RecentAchievements"))
			for game_id in rec:
				var je_spiel := Fremd.verz(rec[game_id])
				for ach_id in je_spiel:
					var a := Fremd.verz(je_spiel[ach_id])
					unlocks.append({
						"source": "ra", "title": str(a.get("Title", "")), "desc": str(a.get("Description", "")),
						"game": str(a.get("GameTitle", "")), "icon": "%s/Badge/%s.png" % [RA_MEDIA, a.get("BadgeName", "")],
						"date": _ra_date(str(a.get("DateAwarded", ""))), "points": int(a.get("Points", 0)),
						"hardcore": int(a.get("HardcoreAchieved", 0)) == 1,
						"game_id": int(a.get("GameID", str(game_id).to_int())), "rarity": -1.0,
					})
		else:
			last_error = "RetroAchievements antwortet gerade nicht. Stimmen Benutzername und Web-API-Schlüssel?"
		var c := await Net.get_json(_ra_url("API_GetUserCompletionProgress.php", { "c": 500 }))
		if c.ok and c.data is Dictionary:
			ra_progress = []
			for r in Fremd.zeilen(c.data, "Results"):
				ra_progress.append({
					"source": "ra", "ra_id": int(r.get("GameID", 0)), "title": str(r.get("Title", "")),
					"console": int(r.get("ConsoleID", 0)), "console_name": str(r.get("ConsoleName", "")),
					"icon": RA_MEDIA + str(r.get("ImageIcon", "")), "total": int(r.get("MaxPossible", 0)),
					"unlocked": int(r.get("NumAwarded", 0)), "hardcore": int(r.get("NumAwardedHardcore", 0)),
					"award": str(r.get("HighestAwardKind", "") if r.get("HighestAwardKind") != null else ""),
					"date": _ra_date(str(r.get("MostRecentAwardedDate", ""))),
				})
	if has_steam():
		var steam_id := await Social.steam_id()
		var recent: Array = []
		var lists := {}
		var alt := not steam_web_ok()
		if not alt:
			var rp := await Net.get_json(STEAM + "IPlayerService/GetRecentlyPlayedGames/v1/?" + await Social.steam_query({ "steamid": steam_id, "count": 8 }))
			if rp.ok and rp.data is Dictionary:
				for gm in Fremd.zeilen(rp.data, "response/games"):
					recent.append([int(gm.get("appid", 0)), str(gm.get("name", ""))])
			elif _web_refused(int(rp.get("code", 0))):
				alt = true
			elif last_error == "":
				last_error = "Steam antwortet nicht."
		if alt:
			# Ohne Web-API: zuletzt gespielt aus Steams Chat-Server bzw. den Dateien am PC, die Listen
			# lokal oder in einer Sitzung am Chat-Server.
			recent = await _recent_alt(8)
			lists = await _alt_lists(recent, false)
		steam_progress = []
		var n_local := 0
		var n_cm := 0
		for gm in recent:
			var appid := int(gm[0])
			var res: Dictionary = lists.get(appid, {})
			if not alt:
				res = await steam_game(appid, str(gm[1]))
			if res.is_empty() or int(res.get("total", 0)) == 0:
				continue
			if str(res.get("via", "")) == "lokal":
				n_local += 1
			elif str(res.get("via", "")) == "Chat-Server":
				n_cm += 1
			steam_progress.append({ "source": "steam", "appid": appid, "title": res.title, "icon": res.icon,
				"total": res.total, "unlocked": res.unlocked, "date": res.get("last_unlock", 0) })
			for a in res.list:
				if a.unlocked:
					unlocks.append({ "source": "steam", "title": a.title, "desc": a.desc, "game": res.title, "icon": a.icon,
						"date": a.date, "points": 0, "rarity": a.rarity, "hardcore": false, "appid": appid })
		if alt:
			var achs: int = steam_progress.reduce(func(acc, g): return acc + int(g.total), 0)
			SteamChat.diag_log("erfolge", "zuletzt:%d:%d:%d" % [n_local, n_cm, achs], SE.log_text("(zuletzt gespielt)", n_local, n_cm, steam_progress.size(), achs))
			if steam_progress.is_empty() and not recent.is_empty() and last_error == "":
				last_error = "Steam zeigt deine Erfolge gerade nicht."
	unlocks.sort_custom(func(a, b): return int(a.date) > int(b.date))
	recent_unlocks = unlocks.slice(0, 30)
	loading = false
	if last_error == "":
		updated_at = int(Time.get_unix_time_from_system())
	updated.emit("overview")


## Aus der Mitteilungsliste: die Erfolge des Spiels, in dem sie freigeschaltet wurden.
func _open_achievements(g: Dictionary) -> void:
	var m: Node = get_tree().current_scene
	if m and m.has_method("open_game_achievements") and not g.is_empty():
		m.call("open_game_achievements", g)


static func _ra_date(s: String) -> int:
	if s == "" or s == "null":
		return 0
	return int(Time.get_unix_time_from_datetime_string(s.replace(" ", "T").substr(0, 19)))


# --- Ein Spiel -----------------------------------------------------------------

## Erfolge eines Spiels aus der Bibliothek. Ergebnis wird zwischengespeichert.
func for_game(g: Dictionary, force := false, user := false) -> Dictionary:
	var gid := str(g.get("id", ""))
	if not force and _games.has(gid):
		return _games[gid]
	var res := {}
	if demo:
		# Wie eine kurze Abfrage: erst einen Augenblick später, nie mitten im Aufbau.
		await get_tree().create_timer(0.2).timeout
		res = demo_game(gid)
	elif g.get("source") == "steam" and has_steam():
		res = await steam_game(int(g.get("appid", 0)), str(g.get("title", "")), user)
	elif g.get("source") == "rom" and has_ra():
		var ra_id := int(g.get("ra_id", 0))
		if ra_id == 0:
			_ra_list_failed = false
			ra_id = await match_ra(g)
			if ra_id == 0 and _ra_list_failed:
				res = _net_error("ra", "RetroAchievements ist gerade nicht erreichbar.")
		if ra_id > 0:
			res = await ra_game(ra_id)
	_games[gid] = res
	updated.emit("game:" + gid)
	return res


## Was eine gescheiterte Steam-Abfrage bedeutet, in einem Satz (HTTP-Code 0 = keine Antwort).
static func steam_problem(code: int) -> String:
	if code == 401 or code == 403:
		return "Steam lässt die Abfrage gerade nicht zu. Unter Einstellungen → Konten kannst du dich neu anmelden."
	if code >= 500:
		return "Steam hat gerade Probleme."
	return "Steam ist gerade nicht erreichbar."


## Ergebnis, wenn die Quelle nicht antwortet: wie „keine Erfolge“, aber mit Grund.
static func _net_error(source: String, text: String) -> Dictionary:
	return { "source": source, "total": 0, "unlocked": 0, "list": [], "error": text }


func cached(g: Dictionary) -> Dictionary:
	return _games.get(str(g.get("id", "")), {})


## Was Uzai über die Erfolge eines Spiels schon weiß, ohne zu fragen (Filter im Raster):
## [freigeschaltet, gesamt] oder [] ohne Angabe. Quellen: schon geladene Spiele und die Zählung
## der Steam-Bibliothek (Erfolge-Bereich).
func known(g: Dictionary) -> Array:
	var gid := str(g.get("id", ""))
	var r: Dictionary = _games.get(gid, {})
	if not r.is_empty() and not r.has("error"):
		return [int(r.get("unlocked", 0)), int(r.get("total", 0))]
	if demo and DEMO.has(gid):
		return [int(DEMO[gid].got), int(DEMO[gid].total)]
	if str(g.get("source", "")) == "steam":
		_load_counts()
		var c: Dictionary = _counts.get(str(g.get("appid", 0)), {})
		if not c.is_empty():
			return [int(c.get("u", 0)), int(c.get("t", 0))]
	return []


func ra_game(ra_id: int) -> Dictionary:
	if demo:
		await get_tree().create_timer(0.2).timeout
		for gid in DEMO.keys():
			if int(DEMO[gid].get("ra_id", 0)) == ra_id:
				return demo_game(str(gid))
		return {}
	var r := await Net.get_json(_ra_url("API_GetGameInfoAndUserProgress.php", { "g": ra_id }))
	if not r.ok or not (r.data is Dictionary):
		return _net_error("ra", "RetroAchievements ist gerade nicht erreichbar.")
	var d: Dictionary = r.data
	var players := maxi(int(d.get("NumDistinctPlayers", 0)), 1)
	var list: Array = []
	var achs := Fremd.verz(d.get("Achievements"))
	if not achs.is_empty():
		for k in achs:
			var a := Fremd.verz(achs[k])
			var badge := str(a.get("BadgeName", ""))
			var earned := str(a.get("DateEarnedHardcore", "") if a.get("DateEarnedHardcore") != null else "")
			var soft := str(a.get("DateEarned", "") if a.get("DateEarned") != null else "")
			list.append({
				"id": str(a.get("ID", k)), "title": str(a.get("Title", "")), "desc": str(a.get("Description", "")),
				"icon": "%s/Badge/%s.png" % [RA_MEDIA, badge], "icon_locked": "%s/Badge/%s_lock.png" % [RA_MEDIA, badge],
				"unlocked": earned != "" or soft != "", "hardcore": earned != "",
				"date": _ra_date(earned if earned != "" else soft), "points": int(a.get("Points", 0)),
				"rarity": 100.0 * float(a.get("NumAwarded", 0)) / players, "order": int(a.get("DisplayOrder", 0)),
			})
	list.sort_custom(_sort_achievements)
	var unlocked := list.filter(func(a): return a.unlocked).size()
	return {
		"source": "ra", "ra_id": ra_id, "title": str(d.get("Title", "")), "icon": RA_MEDIA + str(d.get("ImageIcon", "")),
		"console": str(d.get("ConsoleName", "")), "total": list.size(), "unlocked": unlocked,
		"shots": _ra_images(d),
		"points_total": list.reduce(func(acc, a): return acc + int(a.points), 0),
		"points": list.filter(func(a): return a.unlocked).reduce(func(acc, a): return acc + int(a.points), 0),
		"list": list,
	}


## Spielszene und Titelbild, die RetroAchievements zu jedem Spiel hat.
static func _ra_images(d: Dictionary) -> Array:
	var out: Array = []
	for k in ["ImageIngame", "ImageTitle"]:
		var v := str(d.get(k, "")) if d.get(k) != null else ""
		if v != "" and not v.ends_with("000002.png"):
			out.append(RA_MEDIA + v)
	return out


## Erfolge eines Steam-Spiels: über die Web-API, sonst (sie lehnt den Zugang der QR-Anmeldung ab)
## aus Steams Dateien am PC bzw. über Steams Chat-Server (siehe steam_erfolge.gd). user: auf
## Knopfdruck (Erfolge geöffnet) – darf neben Steam am PC kurz eine Sitzung öffnen.
func steam_game(appid: int, title := "", user := false) -> Dictionary:
	if appid <= 0 or not has_steam():
		return {}
	if demo:
		await get_tree().create_timer(0.2).timeout
		return demo_game("steam:%d" % appid)
	if not steam_web_ok():
		return await _steam_game_alt(appid, title, user)
	var sid := await Social.steam_id()
	var schema := await Net.get_json(STEAM + "ISteamUserStats/GetSchemaForGame/v2/?" + await Social.steam_query({ "appid": appid, "l": Lang.api("steam") }))
	var mine := await Net.get_json(
			STEAM + "ISteamUserStats/GetPlayerAchievements/v1/?" + await Social.steam_query({ "appid": appid, "steamid": sid, "l": Lang.api("steam") }))
	if not mine.ok and _web_refused(int(mine.get("code", 0))):
		var alt := await _steam_game_alt(appid, title, user)
		if not alt.has("error") or not schema.ok:
			return alt
	if not schema.ok and not mine.ok:
		# Beide Abfragen gescheitert: nicht als „keine Erfolge“ ausgeben, sondern sagen, woran es liegt.
		var why := steam_problem(int(schema.get("code", 0)))
		var e := _net_error("steam", why)
		e["appid"] = appid
		e["title"] = title
		return e
	var rare := await Net.get_json(STEAM + "ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?" + Net.query({ "gameid": appid }))
	var defs := {}
	if schema.ok and schema.data is Dictionary:
		for a in Fremd.zeilen(schema.data, "game/availableGameStats/achievements"):
			defs[str(a.get("name", ""))] = a
	var pct := {}
	if rare.ok and rare.data is Dictionary:
		for a in Fremd.zeilen(rare.data, "achievementpercentages/achievements"):
			pct[str(a.get("name", ""))] = float(a.get("percent", 0))
	var list: Array = []
	var last := 0
	var src: Array = []
	if mine.ok and mine.data is Dictionary:
		src = Fremd.zeilen(mine.data, "playerstats/achievements")
	if src.is_empty():
		for n in defs.keys():
			src.append({ "apiname": n, "achieved": 0, "unlocktime": 0 })
	for a in src:
		var n := str(a.get("apiname", ""))
		var dfn: Dictionary = defs.get(n, {})
		var got := int(a.get("achieved", 0)) == 1
		var when := int(a.get("unlocktime", 0))
		last = maxi(last, when)
		var hidden := int(dfn.get("hidden", 0)) == 1 and not got
		var real := str(dfn.get("description", a.get("description", "")))
		list.append({
			"id": n, "title": str(dfn.get("displayName", a.get("name", n))),
			"desc": "Geheimer Erfolg" if hidden else real, "secret": real if hidden else "",
			"icon": str(dfn.get("icon", "")), "icon_locked": str(dfn.get("icongray", dfn.get("icon", ""))),
			"unlocked": got, "date": when, "points": 0, "rarity": float(pct.get(n, -1.0)), "hardcore": false,
			"hidden": hidden,
		})
	list.sort_custom(_sort_achievements)
	var gname := title
	if gname == "" and schema.ok and schema.data is Dictionary:
		gname = str(Fremd.weg(schema.data, "game/gameName", ""))
	var out := {
		"source": "steam", "appid": appid, "title": gname,
		"icon": "https://shared.steamstatic.com/store_item_assets/steam/apps/%d/capsule_231x87.jpg" % appid,
		"total": list.size(), "unlocked": list.filter(func(a): return a.unlocked).size(), "last_unlock": last, "list": list,
	}
	if mine.ok:
		_steam_lists[appid] = out
	return out


# --- Steam without the Web API: local files and Steam's chat server ------------------------------
# The Web API rejects the access token from the QR login (HTTP 400). Friends, profile and games already
# went through the chat server, but achievements still queried only the Web API and so never loaded.
# Now: first Steam's own files (appcache/stats, no network and no session needed - a local Steam
# install usually has them), then the chat server (ClientGetUserStats, Player.GetAchievementsProgress#1).
# Rarity still comes from the Web API without a key.

## Nimmt die Web-API deinen Zugang? Mit eigenem Schlüssel immer; mit dem Zugang aus der QR-Anmeldung,
## solange Steam ihn nicht abgelehnt hat (SteamChat.web_ok, 6 Std. gemerkt).
func steam_web_ok() -> bool:
	if str(Config.get_value("accounts.steam_key", "")) != "":
		return true
	return not SteamChat.logged_in() or SteamChat.web_ok()


## Hat die Web-API den Zugang aus der Anmeldung eben abgelehnt? Dann merken (wie bei Freunden).
func _web_refused(code: int) -> bool:
	if str(Config.get_value("accounts.steam_key", "")) != "" or not SteamChat.logged_in() or not SteamChat.web_rejected(code):
		return false
	SteamChat.note_web(code, "Erfolge")
	return true


## Steams Ordner mit den Erfolgsdateien ("" ohne Steam am PC).
func _local_stats_dir() -> String:
	var root := Library.steam_root()
	var dir := root.path_join("appcache/stats") if root != "" else ""
	return dir if dir != "" and DirAccess.dir_exists_absolute(dir) else ""


func _steam_game_alt(appid: int, title: String, user: bool) -> Dictionary:
	var res: Dictionary = (await _alt_lists([[appid, title]], user)).get(appid, {})
	var key := "%d:%s:%d:%d" % [appid, str(res.get("via", "-")), int(res.get("total", 0)), int(res.get("unlocked", 0))]
	var gname := str(res.get("title", title))
	if res.has("error"):
		SteamChat.diag_log("erfolge-spiel", key, "Erfolge „%s“: Web-API abgelehnt → weder lokal noch Chat-Server" % gname)
	else:
		SteamChat.diag_log("erfolge-spiel", key, "Erfolge „%s“: Web-API abgelehnt → %s, %d Erfolge, %d frei" % [gname,
				"lokal (Steam-Ordner)" if str(res.via) == "lokal" else "Chat-Server", int(res.total), int(res.unlocked)])
	return res


## Erfolgslisten ohne Web-API für mehrere Spiele ([[App-ID, Titel]]): erst die Dateien am PC, für den
## Rest eine Sitzung am Chat-Server (eine Pforte für alle). App-ID -> Ergebnis wie steam_game, dazu
## via ("lokal" | "Chat-Server"); ohne Daten ein Fehlerergebnis.
func _alt_lists(games: Array, user: bool) -> Dictionary:
	var sid := await Social.steam_id()
	var acct := SE.account_id(sid)
	var dir := _local_stats_dir()
	var found := {}
	var ask: Array = []
	for g in games:
		var appid := int(g[0])
		var lg: Dictionary = SE.local_game(dir, acct, appid) if dir != "" else { "ok": false }
		if bool(lg.ok):
			found[appid] = { "bits": lg.bits, "got": lg.got, "known": lg.has_user, "title": lg.title, "via": "lokal" }
			await get_tree().process_frame
		if not bool(lg.ok) or not bool(lg.has_user):
			ask.append([appid, sid])
	if not ask.is_empty() and sid != "" and SteamChat.can_send():
		var r: Dictionary = await SteamCM.user_stats(str(Config.get_value("accounts.steam_chat_refresh", "")), ask, user)
		for p in ask:
			var body: Variant = (r.results as Dictionary).get("%d:%s" % [int(p[0]), sid])
			if not (body is PackedByteArray):
				continue
			var prev: Dictionary = found.get(int(p[0]), {})
			var us := SE.parse_user_stats(body, prev.get("bits", {}))
			if int(us.eresult) != 1 or (us.bits as Dictionary).is_empty():
				continue
			found[int(p[0])] = { "bits": us.bits, "got": us.got, "known": true,
				"title": str(us.title) if str(us.title) != "" else str(prev.get("title", "")), "via": "Chat-Server" }
	var out := {}
	for g in games:
		var appid := int(g[0])
		var title := str(g[1]) if (g as Array).size() > 1 else ""
		var f: Dictionary = found.get(appid, {})
		if f.is_empty():
			var e := _net_error("steam", "Steam zeigt diese Erfolge gerade nicht.")
			e["appid"] = appid
			e["title"] = title
			out[appid] = e
			continue
		var list := SE.build_list(appid, f.bits, f.got, await _global_pct(appid))
		list.sort_custom(_sort_achievements)
		var last := 0
		for a in list:
			last = maxi(last, int(a.date))
		if title == "":
			title = str(f.title) if str(f.title) != "" else Social._app_title(appid)
		var res := {
			"source": "steam", "appid": appid, "title": title,
			"icon": "https://shared.steamstatic.com/store_item_assets/steam/apps/%d/capsule_231x87.jpg" % appid,
			"total": list.size(), "unlocked": list.filter(func(a): return a.unlocked).size(), "last_unlock": last, "list": list,
			"via": str(f.via),
		}
		if bool(f.known):
			_steam_lists[appid] = res
		out[appid] = res
	return out


## Globale Anteile je Erfolg (ohne Schlüssel): api -> Prozent.
func _global_pct(appid: int) -> Dictionary:
	var pct := {}
	var rare := await Net.get_json(STEAM + "ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?" + Net.query({ "gameid": appid }))
	if rare.ok and rare.data is Dictionary:
		for a in Fremd.zeilen(rare.data, "achievementpercentages/achievements"):
			if a is Dictionary:
				pct[str(a.get("name", ""))] = float(a.get("percent", 0))
	return pct


## Zuletzt gespielte Spiele ohne Web-API: aus den gekauften Spielen vom Chat-Server (zuletzt
## gespielt), sonst die zuletzt geschriebenen Erfolgsdateien am PC. [[App-ID, Titel]]
func _recent_alt(n: int) -> Array:
	var out: Array = []
	var owned: Array = (await Social.steam_owned_games()).duplicate()
	owned = owned.filter(func(g): return g is Dictionary and int(g.get("rtime_last_played", 0)) > 0)
	owned.sort_custom(func(a, b): return int(a.rtime_last_played) > int(b.rtime_last_played))
	for g in owned.slice(0, n):
		out.append([int(g.appid), str(g.get("name", ""))])
	if out.is_empty():
		var sid := await Social.steam_id()
		for e in SE.local_apps(_local_stats_dir(), SE.account_id(sid)).slice(0, n):
			out.append([int(e.appid), Social._app_title(int(e.appid))])
	return out


static func _sort_achievements(a: Dictionary, b: Dictionary) -> bool:
	if a.unlocked != b.unlocked:
		return a.unlocked
	if a.unlocked:
		return int(a.date) > int(b.date)
	return float(a.rarity) > float(b.rarity)


# --- RetroAchievements: Spiel zuordnen -----------------------------------------

static var _RX_NORM := RegEx.create_from_string("[^a-z0-9]+")


static func norm(t: String) -> String:
	var s := t.to_lower()
	for art in [", the", ", die", ", der", ", das"]:
		s = s.replace(art, "")
	if s.begins_with("the "):
		s = s.substr(4)
	# Ein Lauf der Engine statt Zeichen für Zeichen im Skript: Diese Funktion läuft je Titel einer ganzen Konsole.
	return _RX_NORM.sub(s, "", true)


## Sucht die RetroAchievements-ID zu einem Emulator-Spiel über den Titel.
func match_ra(g: Dictionary) -> int:
	var sys := Config.system(str(g.get("system", "")))
	var console := int(sys.get("ra_console", 0))
	if console == 0:
		return 0
	var want := norm(str(g.get("title", "")))
	for p in ra_progress:
		if int(p.console) == console and norm(str(p.title)) == want:
			return int(p.ra_id)
	var list := await _ra_console_list(console)
	# Die angeglichenen Titel einer Konsole einmal je Sitzung rechnen (mehrere tausend Einträge): vorher lief das
	# für jedes Spiel neu, dessen Erfolge zum ersten Mal gefragt wurden.
	if not _ra_norm.has(console) or (_ra_norm[console] as Array).size() != list.size():
		var paare: Array = []
		for e in list:
			paare.append([norm(str(e.get("Title", ""))), Fremd.zahl(e.get("ID"))])
		_ra_norm[console] = paare
	var best := 0
	for p in _ra_norm[console]:
		var n: String = p[0]
		if n == want:
			return int(p[1])
		if best == 0 and want.length() > 5 and (n.begins_with(want) or want.begins_with(n)) and n.length() > 5:
			best = int(p[1])
	return best


func _ra_console_list(console: int) -> Array:
	if _ra_lists.has(console):
		return _ra_lists[console]
	var file := Config.path("cache/ra_games_%d.json" % console)
	var fresh := FileAccess.file_exists(file) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(file) < 7 * 86400
	var list: Variant = Config.read_json(file, null) if fresh else null
	if list is Array:
		list = Fremd.zeilen(list)
	else:
		var r := await Net.get_json(_ra_url("API_GetGameList.php", { "i": console, "f": 1 }))
		list = Fremd.zeilen(r.data) if r.ok else []
		if (list as Array).size() > 0:
			Config.write_json(file, list)
		elif not r.ok:
			# Kein Netz: nicht für die ganze Sitzung als „leer“ merken.
			_ra_list_failed = true
			return []
	_ra_lists[console] = list
	return list


func _check_new_unlocks() -> void:
	if demo or not has_ra() or not Launcher.in_game or not Config.get_value("accounts.ra_toasts", true):
		return
	var r := await Net.get_json(_ra_url("API_GetUserRecentAchievements.php", { "m": 3 }))
	if not r.ok or not (r.data is Array):
		return
	var fresh: Array = []
	for a in Fremd.zeilen(r.data):
		if not (a is Dictionary):
			continue
		var k := "%s:%s" % [a.get("AchievementID", ""), a.get("Date", "")]
		if _seen_unlocks.has(k):
			continue
		_seen_unlocks[k] = true
		# Der Erfolg selbst ist die Überschrift; darunter, was er bringt.
		var pts := int(a.get("Points", 0))
		var hc := int(a.get("HardcoreMode", 0)) == 1
		var sub := PackedStringArray(["Erfolg freigeschaltet"])
		if pts > 0:
			sub.append("%d Punkte" % pts)
		if hc:
			sub.append("Hardcore")
		var badge := "%s/Badge/%s.png" % [RA_MEDIA, a.get("BadgeName", "")]
		Toasts.show_toast(str(a.get("Title", "")), "  ·  ".join(sub), "trophy", { "image": badge, "sound": "achievement",
			"go": _open_achievements.bind(Launcher.current.duplicate()), "go_text": "Erfolge" })
		var gid := int(a.get("GameID", 0))
		fresh.append({ "source": "ra", "title": str(a.get("Title", "")), "desc": str(a.get("Description", "")),
			"game": str(a.get("GameTitle", "")), "icon": badge, "date": _ra_date(str(a.get("Date", ""))), "points": pts,
			"hardcore": hc, "game_id": gid, "rarity": -1.0 })
		# Der Stand dieses Spiels hat sich geändert: Zwischenspeicher weg, Zähler hoch.
		for key in _games.keys():
			if int((_games[key] as Dictionary).get("ra_id", 0)) == gid:
				_games.erase(key)
		for p in ra_progress:
			if int(p.get("ra_id", 0)) == gid:
				p["unlocked"] = mini(int(p.get("unlocked", 0)) + 1, int(p.get("total", 0)))
				p["date"] = int(Time.get_unix_time_from_system())
	if not fresh.is_empty():
		fresh.sort_custom(func(x, y): return int(x.date) > int(y.date))
		recent_unlocks = (fresh + recent_unlocks).slice(0, 30)
		updated.emit("overview")


## Neue RetroAchievements aus Unlocks (das Pop-up zeigt Unlocks selbst): Listen und Zähler
## nachziehen. list: Einträge aus Unlocks.parse_ra_recent.
func ra_unlocks_arrived(list: Array) -> void:
	var fresh: Array = []
	for a in list:
		var gid := int(a.get("game_id", 0))
		fresh.append({ "source": "ra", "title": str(a.get("title", "")), "desc": str(a.get("desc", "")),
			"game": str(a.get("game", "")), "icon": str(a.get("icon", "")), "date": int(a.get("at", 0)), "points": int(a.get("points", 0)),
			"hardcore": bool(a.get("hardcore", false)), "game_id": gid, "rarity": -1.0 })
		for key in _games.keys():
			if int((_games[key] as Dictionary).get("ra_id", 0)) == gid:
				_games.erase(key)
		for p in ra_progress:
			if int(p.get("ra_id", 0)) == gid:
				p["unlocked"] = mini(int(p.get("unlocked", 0)) + 1, int(p.get("total", 0)))
				p["date"] = int(Time.get_unix_time_from_system())
	if not fresh.is_empty():
		fresh.sort_custom(func(x, y): return int(x.date) > int(y.date))
		recent_unlocks = (fresh + recent_unlocks).slice(0, 30)
		updated.emit("overview")


# --- Seltenheit und Texte ------------------------------------------------------

const TIER_NAMES := ["Häufig", "Selten", "Sehr selten", "Ultra selten"]


## Seltenheit in Stufen: 3 ultra selten (unter 5 %), 2 sehr selten (unter 15 %),
## 1 selten (unter 35 %), 0 häufig; -1, wenn die Quelle keinen Anteil kennt.
static func rarity_tier(pct: float) -> int:
	if pct < 0.0:
		return -1
	if pct < 5.0:
		return 3
	if pct < 15.0:
		return 2
	if pct < 35.0:
		return 1
	return 0


static func rarity_name(tier: int) -> String:
	return str(TIER_NAMES[tier]) if tier >= 0 and tier < TIER_NAMES.size() else ""


## Anteil der Spieler mit deutschem Komma: „3,1 %“, „42 %“, „< 0,1 %“.
static func pct_text(p: float) -> String:
	if p < 0.0:
		return ""
	if p < 0.1:
		return "< 0,1 %"
	if p < 10.0:
		return Lang.dec("%.1f %%" % p)
	return "%d %%" % int(round(p))


## Höchste Auszeichnung eines Spiels bei RetroAchievements.
static func award_name(kind: String) -> String:
	match kind:
		"mastered":
			return "Gemeistert"
		"completed":
			return "Komplett"
		"beaten-hardcore":
			return "Durchgespielt · Hardcore"
		"beaten-softcore":
			return "Durchgespielt"
	return ""


## Alles zusammen über beide Quellen: freigeschaltet, möglich, Spiele, komplette Spiele.
## Steam zählt über die ganze Bibliothek (steam_stats), sobald gezählt ist – vorher nur die
## zuletzt gespielten Spiele. counting: Steam zählt gerade noch.
func totals() -> Dictionary:
	var got := 0
	var all := 0
	var done := 0
	var n := 0
	var full := int(steam_stats.get("counted", 0)) > 0
	var list: Array = ra_progress if full else ra_progress + steam_progress
	for g in list:
		var t := int(g.get("total", 0))
		if t <= 0:
			continue
		n += 1
		all += t
		got += int(g.get("unlocked", 0))
		if int(g.get("unlocked", 0)) >= t:
			done += 1
	if full:
		n += int(steam_stats.get("started", 0))
		all += int(steam_stats.get("total", 0))
		got += int(steam_stats.get("unlocked", 0))
		done += int(steam_stats.get("perfect_count", 0))
	return { "unlocked": got, "total": all, "games": n, "complete": done, "counting": bool(steam_stats.get("counting", false)) }


## Alle Steam-Spiele mit 100 %: aus der Zählung über die Bibliothek, sonst aus den zuletzt
## gespielten. Gleiches Format wie steam_progress.
func steam_perfect() -> Array:
	if int(steam_stats.get("counted", 0)) > 0:
		return steam_stats.get("perfect", [])
	return steam_progress.filter(func(g): return int(g.get("total", 0)) > 0 and int(g.get("unlocked", 0)) >= int(g.get("total", 0)))


# --- Profil: Steam über die ganze Bibliothek -------------------------------------
# Steam selbst zählt „perfekte Spiele“ über alle Spiele mit Erfolgen. Früher sah Uzai nur die
# 8 zuletzt gespielten (GetRecentlyPlayedGames) und kam so z. B. auf 1 statt 8. Jetzt: alle
# eigenen Spiele (GetOwnedGames mit Gratisspielen), Stand je Spiel per Sammelabfrage
# (IPlayerService/GetAchievementsProgress, bis zu BATCH Spiele je Abfrage); antwortet die nicht,
# einzeln über GetPlayerAchievements in kleinen Wellen. Ergebnisse liegen im Zwischenspeicher
# und werden nur neu geholt, wenn sich die Spielzeit geändert hat oder sie alt sind.

const COMMUNITY := "https://steamcommunity.com/profiles/"
const ITEM_IMG := "https://shared.fastly.steamstatic.com/community_assets/images/"
const COUNTS_FILE := "cache/steam_ach_counts.json"
const BATCH := 40               ## Spiele je Sammelabfrage
const WAVE := 6                 ## Einzelabfragen gleichzeitig (Steam drosselt bei Massen)
const COUNT_MAX_AGE := 21 * 86400
const COUNT_VERSION := 2        ## Stand der Zählung; „ohne Erfolge“ aus älteren wird neu gezählt
const EXTRA_TTL := 3600

signal _part_done

var steam_me := {}              ## eigenes Steam-Profil (siehe refresh_profile)
var steam_stats := {}           ## Zahlen über die Bibliothek (siehe steam_totals)
var steam_recent: Array = []    ## zuletzt gespielt: [{ appid, name, two_weeks, total }] (Minuten)
var profile_loading := false
var profile_error := ""
var _counts := {}               # App-ID (Text) -> { m: Minuten beim Zählen, u, t, at }
var _counts_loaded := false
var _batch_ok := true           # Sammelabfrage geht (sonst einzeln zählen)
var _counting := false
var _extra := {}                # Steam-ID -> { at, data }
var _steam_lists := {}          # App-ID -> geladene Erfolgsliste (für „Seltenste Erfolge“)


## Läufe von refresh_profile, die gerade unterwegs sind (siehe dort).
var _refresh_profile_offen := 0


## Lädt das eigene Steam-Profil und zählt danach im Hintergrund die Erfolge der Bibliothek.
## Meldet „profile“, sobald der Kopf steht, und noch einmal, wenn die Zählung fertig ist
## (zwischendurch „profile_count“). steam_me:
## { id, name, avatar, state, game, game_id, level, created, realname, country, background,
##   summary, headline, location, member_since, public, top: { appid, name, total } }
func refresh_profile(force := false) -> void:
	_refresh_profile_offen += 1
	await _refresh_profile_lauf(force)
	_refresh_profile_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_profile täte bis zum Neustart nichts mehr.
	if _refresh_profile_offen == 0 and profile_loading:
		profile_loading = false
		profile_error = "Das Profil ließ sich gerade nicht laden."
		updated.emit("profile")


func _refresh_profile_lauf(force := false) -> void:
	if profile_loading or _counting:
		return
	var now := int(Time.get_unix_time_from_system())
	if not force and not steam_me.is_empty() and now - int(steam_me.get("at", 0)) < 600:
		return
	profile_loading = true
	profile_error = ""
	if demo:
		# Wie mit Netz: erst der Kopf, die Zählung läuft noch einen Augenblick.
		await get_tree().create_timer(0.4).timeout
		_load_demo_profile()
		var full := steam_stats
		steam_stats = full.duplicate()
		steam_stats.merge({ "counting": true, "left": 57, "unlocked": 2310, "perfect_count": 5, "perfect": (full.perfect as Array).slice(0, 5) }, true)
		profile_loading = false
		_counting = true
		updated.emit("profile")
		await get_tree().create_timer(0.15).timeout
		steam_stats = full
		_counting = false
		updated.emit("profile")
		return
	if not has_steam():
		profile_loading = false
		updated.emit("profile")
		return
	var sid := await Social.steam_id()
	if sid == "":
		profile_error = "Steam-ID nicht gefunden."
		profile_loading = false
		updated.emit("profile")
		return
	var alt := not steam_web_ok()
	var box := {}
	if not alt:
		var q_sum := await Social.steam_query({ "steamids": sid })
		var q_id := await Social.steam_query({ "steamid": sid })
		var q_owned := await Social.steam_query({ "steamid": sid, "include_appinfo": 1, "include_played_free_games": 1 })
		var q_recent := await Social.steam_query({ "steamid": sid, "count": 12 })
		box = await _parts({
			"summary": STEAM + "ISteamUser/GetPlayerSummaries/v2/?" + q_sum,
			"level": STEAM + "IPlayerService/GetSteamLevel/v1/?" + q_id,
			"items": STEAM + "IPlayerService/GetProfileItemsEquipped/v1/?" + q_id,
			"owned": STEAM + "IPlayerService/GetOwnedGames/v1/?" + q_owned,
			"recent": STEAM + "IPlayerService/GetRecentlyPlayedGames/v1/?" + q_recent,
		})
		var sm: Dictionary = box.get("summary", {})
		alt = not bool(sm.get("ok", false)) and _web_refused(int(sm.get("code", 0)))
	var extra := await steam_profile_extra(sid, force)
	var me := {}
	var owned: Array = []
	if alt:
		# Web-API lehnt ab: Kopf aus Steams Chat-Server und der öffentlichen Profilseite, Spiele vom
		# Chat-Server; dein Status kommt auf der Seite aus MyStatus (Steam am PC).
		me = _me_alt(extra)
		var raw: Array = await Social.steam_owned_games()
		owned = parse_owned_games({ "response": { "games": raw } })
		steam_recent = SocialS.parse_recent(SocialS.recent_from_cm(raw)).games
		me["level"] = -1
		# Profilhintergrund über den Chat-Server (Player.GetProfileItemsEquipped), wie die Steam-App.
		me["background"] = ""
		if SteamChat.logged_in() and SteamChat.can_send() and not SteamChat.demo:
			var img: String = await SteamCM.profile_background(str(Config.get_value("accounts.steam_chat_refresh", "")), int(sid), force)
			if img != "":
				me["background"] = parse_items({ "response": { "profile_background": { "image_large": img } } })
	else:
		me = parse_me(_ok_data(box, "summary"))
		if me.is_empty() and box.get("summary", {}).get("ok", false) == false:
			profile_error = steam_problem(int(box.get("summary", {}).get("code", 0)))
		me["level"] = SocialS.parse_level(_ok_data(box, "level"))
		me["background"] = parse_items(_ok_data(box, "items"))
		owned = parse_owned_games(_ok_data(box, "owned"))
		steam_recent = SocialS.parse_recent(_ok_data(box, "recent")).games
	me["id"] = sid
	for k in ["summary", "headline", "location", "member_since"]:
		me[k] = extra.get(k, "" if k != "member_since" else 0)
	if str(me.get("realname", "")) == "":
		me["realname"] = str(extra.get("realname", ""))
	if int(me.get("created", 0)) <= 0:
		me["created"] = int(extra.get("member_since", 0))
	me["top"] = {}
	for g in owned:
		if int(g.minutes) > int(me.top.get("total", 0)):
			me["top"] = { "appid": int(g.appid), "name": str(g.name), "total": int(g.minutes) }
	me["games_private"] = not alt and _ok_data(box, "owned") != null and owned.is_empty() and not _owned_has_count(_ok_data(box, "owned"))
	me["at"] = now
	steam_me = me
	_load_counts()
	steam_stats = steam_totals(owned, _counts)
	profile_loading = false
	updated.emit("profile")
	if not owned.is_empty():
		await _count_steam(sid, owned)


## Dein Kopf ohne Web-API: Name und Bild vom Chat-Server (Social.me, SteamCM.own), sonst von der
## öffentlichen Profilseite. Ohne „state“ – den zeigt die Profilseite aus MyStatus.
func _me_alt(extra: Dictionary) -> Dictionary:
	var n := str(Social.me.get("name", ""))
	var a := str(Social.me.get("avatar", ""))
	if n == "":
		n = str(SteamCM.own.get("name", ""))
		a = str(SteamCM.own.get("avatar", ""))
	if n == "":
		n = str(extra.get("name", ""))
	if a == "":
		a = str(extra.get("avatar", ""))
	return { "name": n, "avatar": a, "public": bool(extra.get("public", true)), "realname": "", "country": "", "created": 0 }


static func _owned_has_count(data: Variant) -> bool:
	return data is Dictionary and data.get("response") is Dictionary and (data.response as Dictionary).has("game_count")


## Mehrere Abfragen gleichzeitig; Ergebnis: Name -> Antwort von Net.get_json.
func _parts(urls: Dictionary) -> Dictionary:
	var box := { "left": urls.size() }
	for k in urls.keys():
		_part(box, str(k), str(urls[k]))
	while int(box.left) > 0:
		await _part_done
	box.erase("left")
	return box


func _part(box: Dictionary, key: String, url: String) -> void:
	var r := await Net.get_json(url)
	box[key] = r
	box["left"] = int(box.left) - 1
	_part_done.emit()


static func _ok_data(box: Dictionary, key: String) -> Variant:
	var r: Variant = box.get(key)
	if r is Dictionary and bool(r.get("ok", false)):
		return r.get("data")
	return null


## Eigener Kopf aus GetPlayerSummaries (mehr Felder als Social.parse_summary).
static func parse_me(data: Variant) -> Dictionary:
	var sm: Dictionary = SocialS.parse_summary(data)
	if sm.is_empty():
		return {}
	var p: Dictionary = data.response.players[0]
	sm["realname"] = str(p.get("realname", ""))
	sm["country"] = str(p.get("loccountrycode", ""))
	sm["url"] = str(p.get("profileurl", ""))
	return sm


## Hintergrund des Steam-Profils aus GetProfileItemsEquipped ("" ohne Hintergrund).
static func parse_items(data: Variant) -> String:
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return ""
	var bg: Variant = data.response.get("profile_background")
	if not (bg is Dictionary):
		return ""
	var img := str(bg.get("image_large", ""))
	if img == "":
		return ""
	return img if img.begins_with("http") else ITEM_IMG + img.trim_prefix("/")


## Bibliothek mit Spielzeit: [{ appid, name, minutes, last }] (last: zuletzt gespielt, Unix).
static func parse_owned_games(data: Variant) -> Array:
	var out: Array = []
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return out
	for g in data.response.get("games", []):
		if g is Dictionary and int(g.get("appid", 0)) > 0:
			out.append({ "appid": int(g.appid), "name": str(g.get("name", "")), "minutes": int(g.get("playtime_forever", 0)),
				"last": int(g.get("rtime_last_played", 0)) })
	return out


## Antwort der Sammelabfrage: App-ID -> { u, t } (nur Spiele, die Steam nennt).
static func parse_progress(data: Variant) -> Dictionary:
	var out := {}
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return out
	for e in data.response.get("achievement_progress", []):
		if e is Dictionary and int(e.get("appid", 0)) > 0:
			var t := int(e.get("total", 0))
			var u := int(e.get("unlocked", 0))
			if bool(e.get("all_unlocked", false)) and t > 0:
				u = t
			out[int(e.appid)] = { "u": u, "t": t }
	return out


## Antwort von GetPlayerAchievements, nur gezählt: { state: ok | nostats | private | error, u, t }.
## „Requested app has no stats“ (HTTP 400) heißt: Spiel ohne Erfolge.
static func parse_player_ach(r: Dictionary) -> Dictionary:
	var data: Variant = r.get("data")
	var ps: Dictionary = data.playerstats if data is Dictionary and data.get("playerstats") is Dictionary else {}
	var code := int(r.get("code", 0))
	if bool(r.get("ok", false)) and bool(ps.get("success", true)) and not ps.is_empty():
		var list: Array = ps.get("achievements", []) if ps.get("achievements") is Array else []
		var u := list.filter(func(a): return a is Dictionary and int(a.get("achieved", 0)) == 1).size()
		return { "state": "ok" if not list.is_empty() else "nostats", "u": u, "t": list.size() }
	var err := str(ps.get("error", "")).to_lower()
	# 400 ohne Angabe von Steam heißt nicht „keine Erfolge“: So lehnt die Web-API auch den Zugang der
	# QR-Anmeldung ab – vorher galt dann jedes Spiel als „ohne Erfolge“.
	if err.contains("no stats") or (code == 400 and err != "" and not err.contains("not public")):
		return { "state": "nostats", "u": 0, "t": 0 }
	if code == 403 or err.contains("not public"):
		return { "state": "private", "u": 0, "t": 0 }
	return { "state": "error", "u": 0, "t": 0, "code": code }


## Zahlen über die Bibliothek aus dem gezählten Stand.
## { games, played, minutes, counted, with_ach, started, unlocked, total, perfect, perfect_count, avg }
## total zählt nur Spiele, die gespielt oder angefangen sind (wie die Quote bei Steam).
static func steam_totals(owned: Array, counts: Dictionary) -> Dictionary:
	var minutes := 0
	var played := 0
	var counted := 0
	var with_ach := 0
	var started := 0
	var unlocked := 0
	var total := 0
	var quote := 0.0
	var perfect: Array = []
	for g in owned:
		minutes += int(g.get("minutes", 0))
		if int(g.get("minutes", 0)) > 0:
			played += 1
		var c: Dictionary = counts.get(str(g.get("appid", 0)), {})
		if c.is_empty():
			continue
		counted += 1
		var t := int(c.get("t", 0))
		var u := mini(int(c.get("u", 0)), t)
		if t <= 0:
			continue
		with_ach += 1
		if u > 0:
			started += 1
			quote += float(u) / float(t)
		if u > 0 or int(g.get("minutes", 0)) > 0:
			total += t
			unlocked += u
		if u >= t:
			perfect.append({ "source": "steam", "appid": int(g.appid), "title": str(g.get("name", "")), "icon": "",
				"total": t, "unlocked": u, "date": int(g.get("last", 0)), "minutes": int(g.get("minutes", 0)) })
	perfect.sort_custom(func(a, b): return int(a.date) > int(b.date))
	return { "games": owned.size(), "played": played, "minutes": minutes, "counted": counted, "with_ach": with_ach,
		"started": started, "unlocked": unlocked, "total": total, "perfect": perfect, "perfect_count": perfect.size(),
		"avg": 100.0 * quote / float(started) if started > 0 else 0.0, "counting": false, "left": 0 }


func _load_counts() -> void:
	if _counts_loaded:
		return
	_counts_loaded = true
	# Nur Einträge in der erwarteten Form: Ein anderer Wert bräche jede Zählung und damit das ganze Profil ab.
	var d := Fremd.verz(Config.read_json(Config.path(COUNTS_FILE), {}))
	_counts = {}
	for k in d:
		if d[k] is Dictionary:
			_counts[str(k)] = d[k]


## Spiele, deren Stand fehlt oder veraltet ist. Mit Sammelabfrage alle, sonst nur gespielte
## (ohne Spielzeit gibt es kaum Erfolge – und so bleibt es bei wenigen Einzelabfragen).
static func count_todo(owned: Array, counts: Dictionary, now: int, all: bool) -> Array:
	var out: Array = []
	for g in owned:
		var m := int(g.get("minutes", 0))
		if m <= 0 and not all:
			continue
		var c: Dictionary = counts.get(str(g.get("appid", 0)), {})
		if c.is_empty() or int(c.get("m", -1)) != m or now - int(c.get("at", 0)) > COUNT_MAX_AGE:
			out.append(g)
		elif int(c.get("t", 0)) == 0 and int(c.get("v", 0)) < COUNT_VERSION:
			# „Ohne Erfolge“ aus älteren Fassungen: womöglich nur die abgelehnte Web-API (HTTP 400).
			out.append(g)
	return out


## Die Erfolge der Bibliothek zählen. Die Arbeit läuft in _count_steam_lauf: Bricht sie mit einem Fehler ab, wird
## „zählt“ hier trotzdem gelöst. Sonst lüde das Profil bis zum Neustart nicht mehr neu, und die Seite zeigte für
## immer „zählt noch“.
func _count_steam(sid: String, owned: Array) -> void:
	_counting = true
	await _count_steam_lauf(sid, owned)
	if _counting:
		_counting = false
		steam_stats["counting"] = false
		steam_stats["left"] = 0
		updated.emit("profile")


func _count_steam_lauf(sid: String, owned: Array) -> void:
	var now := int(Time.get_unix_time_from_system())
	var alt := not steam_web_ok()
	var todo := count_todo(owned, _counts, now, _batch_ok or alt)
	if todo.is_empty():
		_counting = false
		await _load_rarest()
		updated.emit("profile")
		return
	_set_counting(owned, todo.size())
	if not alt and _batch_ok:
		# Erste Sammelabfrage: lehnt die Web-API den Zugang ab, gleich ohne sie zählen.
		var q0 := { "steamid": sid, "language": Lang.api("steam"), "appids%5B0%5D": int(todo[0].appid) }
		var r0 := await Net.get_json(STEAM + "IPlayerService/GetAchievementsProgress/v1/?" + await Social.steam_query(q0))
		alt = not r0.ok and _web_refused(int(r0.get("code", 0)))
	if alt:
		await _count_alt(sid, owned, todo, now)
		Config.write_json(Config.path(COUNTS_FILE), _counts)
		steam_stats = steam_totals(owned, _counts)
		_counting = false
		await _load_rarest()
		updated.emit("profile")
		return
	if _batch_ok:
		var i := 0
		while i < todo.size():
			var chunk := todo.slice(i, i + BATCH)
			var q := { "steamid": sid, "language": Lang.api("steam") }
			for j in chunk.size():
				q["appids%%5B%d%%5D" % j] = int(chunk[j].appid)
			var r := await Net.get_json(STEAM + "IPlayerService/GetAchievementsProgress/v1/?" + await Social.steam_query(q))
			var got := parse_progress(r.data if r.ok else null)
			if got.is_empty() and i == 0:
				_batch_ok = false
				break
			for g in chunk:
				if got.has(int(g.appid)):
					_counts[str(g.appid)] = { "m": int(g.minutes), "u": int(got[int(g.appid)].u), "t": int(got[int(g.appid)].t), "at": now, "v": COUNT_VERSION }
			i += BATCH
			_set_counting(owned, maxi(0, todo.size() - i))
		todo = count_todo(owned, _counts, now, false)
	# Einzeln: in kleinen Wellen, mit Pause; bei Drosselung (429) oder privat aufhören.
	var k := 0
	var waves := 0
	var stop := false
	while k < todo.size() and not stop:
		var urls := {}
		for g in todo.slice(k, k + WAVE):
			urls[str(g.appid)] = STEAM + "ISteamUserStats/GetPlayerAchievements/v1/?" + await Social.steam_query({ "appid": int(g.appid), "steamid": sid })
		var box := await _parts(urls)
		var n_priv := 0
		for g in todo.slice(k, k + WAVE):
			var pa := parse_player_ach(box.get(str(g.appid), {}))
			match str(pa.state):
				"ok", "nostats":
					_counts[str(g.appid)] = { "m": int(g.minutes), "u": int(pa.u), "t": int(pa.t), "at": now, "v": COUNT_VERSION }
				"private":
					n_priv += 1
				_:
					if int(pa.get("code", 0)) == 429:
						stop = true
		if n_priv > 0 and n_priv == urls.size() and k == 0:
			profile_error = "Steam zeigt deine Erfolge nur, wenn die Spieldetails im Profil öffentlich sind."
			stop = true
		k += WAVE
		waves += 1
		_set_counting(owned, maxi(0, todo.size() - k))
		if waves % 8 == 0:
			Config.write_json(Config.path(COUNTS_FILE), _counts)
		await get_tree().create_timer(0.15).timeout
	Config.write_json(Config.path(COUNTS_FILE), _counts)
	steam_stats = steam_totals(owned, _counts)
	_counting = false
	await _load_rarest()
	updated.emit("profile")


## Zählung ohne Web-API: erst Steams Dateien am PC (ohne Netz), den Rest in einer Sitzung am
## Chat-Server (Player.GetAchievementsProgress#1). Eine Zeile im Protokoll mit dem Ergebnis.
func _count_alt(sid: String, owned: Array, todo: Array, now: int) -> void:
	var dir := _local_stats_dir()
	var acct := SE.account_id(sid)
	var n_local := 0
	var rest: Array = []
	for i in todo.size():
		var g: Dictionary = todo[i]
		var c: Dictionary = SE.local_count(dir, acct, int(g.appid)) if dir != "" else {}
		if c.is_empty():
			rest.append(g)
			continue
		_counts[str(g.appid)] = { "m": int(g.minutes), "u": int(c.u), "t": int(c.t), "at": now, "v": COUNT_VERSION, "src": "lokal" }
		n_local += 1
		# Je gelesenem Schema ein Bild Pause (große Dateien), Anzeige alle paar Spiele.
		if n_local % 4 == 0:
			_set_counting(owned, todo.size() - i)
		await get_tree().process_frame
	var n_cm := 0
	var why := ""
	if not rest.is_empty() and SteamChat.can_send():
		var ids: Array = rest.map(func(g): return int(g.appid))
		var r: Dictionary = await SteamCM.achievements_progress(str(Config.get_value("accounts.steam_chat_refresh", "")), int(sid), ids, Lang.api("steam"))
		var got: Dictionary = r.counts
		for g in rest:
			var e: Variant = got.get(int(g.appid))
			if e is Dictionary:
				_counts[str(g.appid)] = { "m": int(g.minutes), "u": int(e.u), "t": int(e.t), "at": now, "v": COUNT_VERSION, "src": "cm" }
				n_cm += 1
		if not bool(r.ok):
			why = " (Chat-Server: %s)" % ("gerade nicht – Steam am PC angemeldet, später" if SteamCM.pc_maybe() else "keine Antwort")
	var achs := 0
	var games := 0
	for g in owned:
		var c2: Dictionary = _counts.get(str(g.appid), {})
		if int(c2.get("t", 0)) > 0:
			games += 1
			achs += int(c2.t)
	SteamChat.diag_log("erfolge", "zahl:%d:%d:%d" % [n_local, n_cm, achs], SE.log_text("", n_local, n_cm, games, achs) + why)


func _set_counting(owned: Array, left: int) -> void:
	steam_stats = steam_totals(owned, _counts)
	steam_stats["counting"] = left > 0
	steam_stats["left"] = left
	updated.emit("profile_count")


## Für „Seltenste Erfolge“: Listen der perfekten Spiele laden (höchstens 6 – deren seltenster
## Erfolg ist sicher freigeschaltet); dazu kommt, was schon geladen ist.
func _load_rarest() -> void:
	var n := 0
	for g in steam_perfect():
		if n >= 6:
			break
		if not _steam_lists.has(int(g.appid)):
			await steam_game(int(g.appid), str(g.title))
		n += 1


## Die seltensten freigeschalteten Steam-Erfolge aus allen geladenen Listen (Format wie
## recent_unlocks, seltenste zuerst; höchstens per_game je Spiel, damit die Reihe gemischt ist).
func steam_rarest(limit := 10, per_game := 2) -> Array:
	return rarest_of(_steam_lists.values(), limit, per_game)


static func rarest_of(lists: Array, limit: int, per_game: int) -> Array:
	var all: Array = []
	for res in lists:
		for a in res.get("list", []):
			if a.unlocked and float(a.rarity) >= 0.0:
				all.append({ "source": "steam", "title": a.title, "desc": a.desc, "game": res.title, "icon": a.icon,
					"date": a.date, "points": 0, "rarity": float(a.rarity), "hardcore": false, "appid": int(res.get("appid", 0)) })
	all.sort_custom(func(x, y): return float(x.rarity) < float(y.rarity))
	var out: Array = []
	var per := {}
	for a in all:
		var n := int(per.get(a.appid, 0))
		if n >= per_game:
			continue
		per[a.appid] = n + 1
		out.append(a)
		if out.size() >= limit:
			break
	return out


## Alle Erfolgslisten, die Uzai gerade kennt, ohne zu fragen (zuletzt gespielte Steam-Spiele aus
## der Übersicht, geöffnete Spiele beider Quellen).
func known_lists() -> Array:
	var out: Array = []
	var seen := {}
	for res in _steam_lists.values():
		seen["steam:%d" % int(res.get("appid", 0))] = true
		out.append(res)
	for res in _games.values():
		if not (res is Dictionary) or res.is_empty() or res.has("error") or not res.has("list"):
			continue
		var k := "%s:%d" % [res.get("source", ""), int(res.get("ra_id", res.get("appid", 0)))]
		if not seen.has(k):
			seen[k] = true
			out.append(res)
	return out


## Als Nächstes greifbar: offene Erfolge, die viele Spieler haben, über alle bekannten Listen
## (achievements_friends.gd › reachable).
func reachable(limit := 8) -> Array:
	return FriendsS.reachable(known_lists(), limit)


## RetroAchievements in Zahlen: { mastered, mastered_hc, beaten, games, unlocked, total }.
func ra_stats() -> Dictionary:
	var mastered := 0
	var mastered_hc := 0
	var beaten := 0
	var got := 0
	var all := 0
	for g in ra_progress:
		var aw := str(g.get("award", ""))
		if aw == "mastered" or aw == "completed":
			mastered += 1
			if aw == "mastered":
				mastered_hc += 1
		if aw != "":
			beaten += 1
		got += int(g.get("unlocked", 0))
		all += int(g.get("total", 0))
	return { "mastered": mastered, "mastered_hc": mastered_hc, "beaten": beaten, "games": ra_progress.size(), "unlocked": got, "total": all }


# --- Öffentliche Profilseite (XML) ----------------------------------------------

## Was die öffentliche Steam-Profilseite (steamcommunity.com/profiles/<id>/?xml=1) zusätzlich zur
## Web-API verrät. Nur bei öffentlichen Profilen; 1 Std. zwischengespeichert, auch für Freunde.
## { ok, public, summary (Info-Text ohne HTML), headline, realname, location,
##   member_since (Unix, 0: unbekannt), member_since_text, avatar, error }
func steam_profile_extra(steamid: String, force := false) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var hit: Dictionary = _extra.get(steamid, {})
	if not force and not hit.is_empty() and now - int(hit.get("at", 0)) < EXTRA_TTL:
		return hit.data
	var out: Dictionary
	if demo:
		out = demo_extra(steamid)
	elif not steamid.is_valid_int():
		out = parse_profile_xml("")
	else:
		var r := await Net.request(COMMUNITY + steamid + "/?xml=1")
		out = parse_profile_xml((r.body as PackedByteArray).get_string_from_utf8() if r.ok else "")
		if not r.ok:
			out["error"] = "Steam-Profil gerade nicht erreichbar."
	if str(out.get("error", "")) == "" or bool(out.get("ok", false)):
		_extra[steamid] = { "at": now, "data": out }
		Config.cap(_extra, 300)
	return out


## Profil-XML auslesen (ohne Netz, auch für die Tests).
static func parse_profile_xml(text: String) -> Dictionary:
	var out := { "ok": false, "public": false, "summary": "", "headline": "", "realname": "", "location": "",
		"member_since": 0, "member_since_text": "", "avatar": "", "name": "", "error": "" }
	if text.strip_edges() == "":
		out.error = "Keine Antwort."
		return out
	var err := _xml_tag(text, "error")
	if err != "" and not text.contains("<profile>"):
		out.error = err
		return out
	# Nur der Kopf: weiter unten haben Gruppen eigene <summary>/<headline>.
	var head := text
	for cut in ["<mostPlayedGames>", "<groups>", "<inGameInfo>"]:
		var at := head.find(cut)
		if at > 0:
			head = head.substr(0, at)
	out.ok = head.contains("<steamID64>")
	out.public = _xml_tag(head, "privacyState") == "public"
	out.avatar = _xml_tag(head, "avatarFull")
	out.name = strip_html(_xml_tag(head, "steamID")).left(64)
	if not out.public:
		return out
	var summ := strip_html(_xml_tag(head, "summary"))
	if summ.to_lower() in ["no information given.", "keine informationen angegeben."]:
		summ = ""
	out.summary = summ
	out.headline = strip_html(_xml_tag(head, "headline"))
	out.realname = strip_html(_xml_tag(head, "realname"))
	out.location = strip_html(_xml_tag(head, "location"))
	out.member_since_text = _xml_tag(head, "memberSince")
	out.member_since = parse_member_since(str(out.member_since_text))
	return out


static func _xml_tag(text: String, tag: String) -> String:
	var open := "<%s>" % tag
	var a := text.find(open)
	if a < 0:
		return ""
	a += open.length()
	var b := text.find("</%s>" % tag, a)
	if b < 0:
		return ""
	var v := text.substr(a, b - a).strip_edges()
	if v.begins_with("<![CDATA[") and v.ends_with("]]>"):
		v = v.substr(9, v.length() - 12)
	return v.strip_edges()


static var _HTML_UMBRUCH := RegEx.create_from_string("(?i)<br\\s*/?>|</p>|</div>")
static var _HTML_MARKE := RegEx.create_from_string("<[^>]*>")
static var _HTML_NUMMER := RegEx.create_from_string("&#(\\d{1,7});")


## HTML aus Steam-Texten entfernen: Zeilenumbrüche bleiben, Zeichen werden lesbar.
static func strip_html(s: String) -> String:
	var t := _HTML_MARKE.sub(_HTML_UMBRUCH.sub(s, "\n", true), "", true)
	for e in [["&nbsp;", " "], ["&quot;", "\""], ["&#39;", "'"], ["&apos;", "'"], ["&lt;", "<"], ["&gt;", ">"]]:
		t = t.replace(str(e[0]), str(e[1]))
	for m in _HTML_NUMMER.search_all(t):
		# Den Text schreibt ein Fremder in sein Steam-Profil: keine Steuerzeichen, keine umgedrehte Schreibrichtung.
		t = t.replace(m.get_string(0), Fremd.zeichen(m.get_string(1).to_int()))
	t = t.replace("&amp;", "&").replace("\r", "")
	var lines := PackedStringArray()
	for l in t.split("\n"):
		lines.append(l.strip_edges())
	t = "\n".join(lines)
	while t.contains("\n\n\n"):
		t = t.replace("\n\n\n", "\n\n")
	return Fremd.sauber(t).strip_edges()


const EN_MONTHS := ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
const DE_MONTHS := ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]


## „October 12, 2003“ oder „12. Oktober 2003“ -> Unix-Zeit (Mittag UTC), 0 wenn unlesbar.
static func parse_member_since(s: String) -> int:
	var t := s.to_lower().replace(",", " ").replace(".", " ")
	var month := 0
	var day := 0
	var year := 0
	for w in t.split(" ", false):
		var i := EN_MONTHS.find(w)
		if i < 0:
			i = DE_MONTHS.find(w)
		if i >= 0:
			month = i + 1
		elif w.is_valid_int():
			if w.length() == 4:
				year = w.to_int()
			elif day == 0:
				day = w.to_int()
	if year < 2003 or month == 0:
		return 0
	return int(
			Time.get_unix_time_from_datetime_dict({ "year": year, "month": month, "day": clampi(day, 1, 31), "hour": 12, "minute": 0, "second": 0 }))


# --- Beispieldaten (--demo) ----------------------------------------------------

## Spiele der Demo-Bibliothek mit Erfolgen: Anzahl, davon frei, letzte Freischaltung vor
## so vielen Stunden, Namensliste; Emulator-Spiele mit RetroAchievements-ID und Konsole.
const DEMO := {
	"steam:1245620": { "total": 42, "got": 29, "hours": 2, "names": "elden" },
	"steam:1145360": { "total": 49, "got": 41, "hours": 50, "names": "hades" },
	"steam:367520": { "total": 63, "got": 33, "hours": 290, "names": "hollow" },
	"steam:413150": { "total": 40, "got": 40, "hours": 700, "names": "" },
	"steam:2379780": { "total": 34, "got": 18, "hours": 98, "names": "" },
	"steam:1091500": { "total": 57, "got": 0, "hours": 0, "names": "" },
	"steam:1086940": { "total": 54, "got": 0, "hours": 0, "names": "" },
	"ps2:30fa359a43774f": { "total": 52, "got": 44, "hours": 1, "names": "okami", "ra_id": 2771, "console": 21 },
	"ps2:74a8e64542ec02": { "total": 26, "got": 26, "hours": 75, "names": "colossus", "ra_id": 2803, "console": 21, "award": "mastered" },
	"ps2:47af91016b6b94": { "total": 95, "got": 61, "hours": 140, "names": "", "ra_id": 2817, "console": 21 },
	"ps2:5e1005d21bcb60": { "total": 48, "got": 12, "hours": 400, "names": "", "ra_id": 2903, "console": 21 },
	"ps1:307c10cd219504": { "total": 47, "got": 38, "hours": 220, "names": "", "ra_id": 11240, "console": 12, "award": "beaten-hardcore" },
	"ps1:a3bff46916509e": { "total": 51, "got": 22, "hours": 26, "names": "", "ra_id": 11255, "console": 12 },
	"gc:5afbe7cb37a915": { "total": 64, "got": 9, "hours": 960, "names": "", "ra_id": 16312, "console": 16 },
	"gba:99397f66953f91": { "total": 40, "got": 12, "hours": 480, "names": "", "ra_id": 3510, "console": 5 },
}

const DEMO_NAMES := {
	"elden": [["Godrick der Verpflanzte", "Besiege Godrick den Verpflanzten."], ["Rotwolf von Radagon", "Besiege den Rotwolf von Radagon."],
		["Rennala, Königin des Vollmonds", "Besiege Rennala, Königin des Vollmonds."], ["Sternengeißel Radahn", "Besiege Sternengeißel Radahn."],
		["Königshauptstadt Leyndell", "Erreiche die Königshauptstadt Leyndell."], ["Morgott, der Omen-König", "Besiege Morgott, den Omen-König."],
		["Rykard, Herr der Lästerung", "Besiege Rykard, Herrn der Lästerung."], ["Feuerriese", "Besiege den Feuerriesen."],
		["Mohg, Herr des Blutes", "Besiege Mohg, Herrn des Blutes."], ["Malenia, Klinge Miquellas", "Besiege Malenia, Klinge Miquellas."],
		["Eldenfürst", "Erreiche das Ende „Zeitalter der Gebrochenheit“."], ["Legendäre Bewaffnungen", "Erhalte alle legendären Bewaffnungen."],
		["Legendäre Zauber", "Erhalte alle legendären Zauber."], ["Zeitalter der Sterne", "Erreiche das Ende „Zeitalter der Sterne“."],
		["Herr der rasenden Flamme", "Erreiche das Ende „Herr der rasenden Flamme“."], ["Drachenbaumwächter", "Besiege jeden Drachenbaumwächter."]],
	"hades": [["Erste Flucht", "Entkomme zum ersten Mal aus der Unterwelt."], ["Der Hund des Hades", "Freunde dich mit Kerberos an."],
		["Waffenkammer", "Schalte alle unterweltlichen Waffen frei."], ["Lieblingsgott", "Erhalte von jedem Olympier eine Gabe."],
		["Familiengeheimnis", "Erfahre die Wahrheit über deine Mutter."], ["Hitze des Gefechts", "Entkomme mit 8 Hitze."],
		["Hirte des Hades", "Entkomme mit jeder Waffe."], ["Pakt der Strafe", "Entkomme mit 16 Hitze."],
		["Alle Prophezeiungen", "Erfülle jede Prophezeiung."], ["Ende gut", "Sieh den Epilog."]],
	"hollow": [["Falscher Ritter", "Besiege den Falschen Ritter."], ["Hornet", "Besiege Hornet im Grünpfad."],
		["Seelenmeister", "Besiege den Seelenmeister."], ["Stadt der Tränen", "Erreiche die Stadt der Tränen."],
		["Tiefes Nest", "Durchquere das Tiefe Nest."], ["Wächterin", "Besiege einen der Träumer."],
		["Maskenschmied", "Finde alle Maskenscherben."], ["Hüter der Weisheit", "Erhalte alle Zauber."],
		["Der Abgrund", "Steig in den Abgrund hinab."], ["Gottsucher", "Besiege alle Götter im Pantheon."]],
	"okami": [["Kirschblüte", "Lass den Wächterbaum erblühen."], ["Pinselgott", "Erlerne zehn Pinseltechniken."],
		["Sonnenaufgang", "Bring die Sonne zurück."], ["Wolkenwanderer", "Erreiche den Gipfel über Kamiki."],
		["Orochi bezwungen", "Besiege die achtköpfige Schlange."], ["Himmelszeichen", "Finde alle Sternbilder."],
		["Gute Taten", "Füttere alle Tiere."], ["Fischerin", "Fange jeden Fisch."], ["Mondsichel", "Erlerne die Mondsichel."],
		["Hüterin der Bäume", "Rette alle Wächterbäume."], ["Wandernde Künstlerin", "Male hundertmal."], ["Sonnengöttin", "Erreiche das Ende."]],
	"colossus": [["Erster Koloss", "Bezwinge Valus."], ["Reiter", "Bezwinge einen Koloss vom Pferd aus."],
		["Wüstensturm", "Bezwinge Phalanx."], ["Schwimmer", "Bezwinge Hydrus."], ["Unermüdlich", "Halte dich zwei Minuten fest."],
		["Hoch hinaus", "Erklimme den Schrein."], ["Agro", "Reite durch das ganze Land."], ["Zeitprobe", "Bestehe alle Zeitprüfungen."],
		["Der letzte Koloss", "Bezwinge Malus."], ["Wiedergeburt", "Sieh das Ende."]],
}

const DEMO_GENERIC := [["Erste Schritte", "Schließe das erste Kapitel ab."], ["Entdecker", "Entdecke zehn verborgene Orte."],
	["Sammler", "Sammle 50 Gegenstände."], ["Schatzsucher", "Öffne 25 Truhen."], ["Gut gerüstet", "Verbessere deine Ausrüstung vollständig."],
	["Ohne Kratzer", "Besiege einen Endgegner, ohne getroffen zu werden."], ["Schnell wie der Wind", "Beende einen Abschnitt in unter fünf Minuten."],
	["Kenner", "Lies alle Einträge im Kompendium."], ["Durchhalter", "Spiele zehn Stunden."], ["Glückspilz", "Finde einen seltenen Gegenstand."],
	["Meisterstück", "Erreiche die höchste Wertung."], ["Weltenbummler", "Besuche jede Region."], ["Nachteule", "Spiele nach Mitternacht."],
	["Unaufhaltsam", "Gewinne zehn Kämpfe in Folge."], ["Perfektionist", "Erfülle alle Nebenaufgaben."], ["Bis zum Schluss", "Sieh dir den Abspann an."],
	["Ohne Hilfe", "Beende das Spiel ohne Hilfsmittel."], ["Feinschliff", "Erreiche 100 % in einem Kapitel."]]

const ROMAN := ["", " II", " III", " IV", " V", " VI"]

var _demo_cache := {}


## Erfolge eines Spiels der Demo-Bibliothek (gleiches Format wie ra_game/steam_game).
func demo_game(gid: String) -> Dictionary:
	if _demo_cache.has(gid):
		return _demo_cache[gid]
	var d: Dictionary = DEMO.get(gid, {})
	if d.is_empty():
		return {}
	var g := Library.get_game(gid)
	var total := int(d.total)
	var got := int(d.got)
	var ra := not gid.begins_with("steam:")
	var now := int(Time.get_unix_time_from_system())
	var last := now - int(d.hours) * 3600 - 420
	var flavor: Array = DEMO_NAMES.get(str(d.names), [])
	# Die besonderen Namen liegen um die Grenze frei/offen: oben in der Liste und als Nächstes.
	var start := clampi(got - int(flavor.size() * 0.6), 0, maxi(0, total - flavor.size()))
	var gen := 0
	var list: Array = []
	for i in total:
		var nm: Array
		if i >= start and i - start < flavor.size():
			nm = flavor[i - start]
		else:
			nm = DEMO_GENERIC[gen % DEMO_GENERIC.size()].duplicate()
			nm[0] = str(nm[0]) + str(ROMAN[mini(floori(float(gen) / DEMO_GENERIC.size()), ROMAN.size() - 1)])
			gen += 1
		# Früh Freigeschaltetes ist häufig, Spätes selten; dazu etwas Streuung pro Spiel.
		var f := float(i) / maxf(1.0, float(total - 1))
		var wobble := float(absi(("%s#%d" % [gid, i]).hash()) % 1000) / 1000.0
		var pct := clampf(86.0 * pow(1.0 - f, 1.6) + (wobble - 0.5) * 7.0, 0.7, 91.0)
		var on := i < got
		var hidden := not on and i == total - 2
		list.append({
			"id": "%s#%d" % [gid, i], "title": str(nm[0]), "desc": "Geheimer Erfolg" if hidden else str(nm[1]),
			"secret": str(nm[1]) if hidden else "",
			"icon": "", "icon_locked": "", "unlocked": on, "hardcore": ra and on and i % 5 != 4,
			"date": last - (got - 1 - i) * (4200 + int(wobble * 26000)) if on else 0,
			"points": [5, 10, 10, 25, 50][mini(4, int(f * 5.0))] if ra else 0,
			"rarity": pct, "order": i, "hidden": hidden,
		})
	list.sort_custom(_sort_achievements)
	var title := Library.display_title(g) if not g.is_empty() else gid
	var res := { "source": "ra" if ra else "steam", "title": title, "total": total, "unlocked": got,
		"last_unlock": last if got > 0 else 0, "list": list, "icon": "" }
	if ra:
		var sys := Config.system(str(g.get("system", "")))
		res["ra_id"] = int(d.get("ra_id", 0))
		res["console"] = str(sys.get("name", ""))
		res["points_total"] = list.reduce(func(acc, a): return acc + int(a.points), 0)
		res["points"] = list.filter(func(a): return a.unlocked).reduce(func(acc, a): return acc + int(a.points), 0)
		res["shots"] = []
	else:
		res["appid"] = gid.get_slice(":", 1).to_int()
	_demo_cache[gid] = res
	return res


func _load_demo_overview() -> void:
	ra_profile = { "name": "Spieler 1", "points": 12340, "true_points": 30210, "rank": 4512, "pic": "" }
	ra_progress = []
	steam_progress = []
	var unlocks: Array = []
	for gid in DEMO.keys():
		var d: Dictionary = DEMO[gid]
		if int(d.got) <= 0:
			continue
		var res := demo_game(str(gid))
		if res.is_empty():
			continue
		# Wie nach einem Besuch der Spielseite: die Listen sind bekannt („Als Nächstes greifbar“).
		_games[str(gid)] = res
		if res.source == "ra":
			ra_progress.append({ "source": "ra", "ra_id": int(res.ra_id), "title": str(res.title), "console": int(d.get("console", 0)),
				"console_name": str(res.console), "icon": "", "total": int(res.total), "unlocked": int(res.unlocked),
				"hardcore": (res.list as Array).filter(func(a): return a.hardcore).size(), "award": str(d.get("award", "")),
				"date": int(res.last_unlock) })
		else:
			steam_progress.append({ "source": "steam", "appid": int(res.appid), "title": str(res.title), "icon": "",
				"total": int(res.total), "unlocked": int(res.unlocked), "date": int(res.last_unlock) })
		for a in res.list:
			if a.unlocked:
				# Wie bei der echten Abfrage: RetroAchievements nennt bei neuen Erfolgen keinen Anteil.
				unlocks.append({ "source": res.source, "title": a.title, "desc": a.desc, "game": res.title, "icon": "",
					"date": a.date, "points": a.points, "rarity": -1.0 if res.source == "ra" else float(a.rarity),
					"hardcore": a.hardcore, "game_id": int(res.get("ra_id", 0)), "appid": int(res.get("appid", 0)) })
	ra_progress.sort_custom(func(a, b): return int(a.date) > int(b.date))
	steam_progress.sort_custom(func(a, b): return int(a.date) > int(b.date))
	unlocks.sort_custom(func(a, b): return int(a.date) > int(b.date))
	recent_unlocks = unlocks.slice(0, 30)


## Beispiel-Profil (--demo): Kopf, Bibliothek mit 8 perfekten Spielen, Zuletzt gespielt.
const DEMO_PERFECT := [[413150, "Stardew Valley", 40, 9], [504230, "Celeste", 32, 30], [620, "Portal 2", 51, 75],
	[261570, "Ori and the Blind Forest", 35, 120], [304430, "INSIDE", 14, 160], [48000, "LIMBO", 12, 210],
	[837470, "Untitled Goose Game", 21, 300], [379720, "DOOM", 54, 420]]
const DEMO_ME := "76561190000000000"


func _load_demo_profile() -> void:
	var now := int(Time.get_unix_time_from_system())
	var ex := demo_extra(DEMO_ME)
	steam_me = { "id": DEMO_ME, "name": "Spieler 1", "avatar": "", "state": "online", "game": "", "game_id": "",
		"level": 87, "created": int(ex.member_since), "realname": str(ex.realname), "country": "DE", "background": "",
		"summary": str(ex.summary), "headline": str(ex.headline), "location": str(ex.location), "member_since": int(ex.member_since),
		"public": true, "top": { "appid": 1245620, "name": "ELDEN RING", "total": 24120 }, "games_private": false, "at": now }
	steam_recent = [{ "appid": 1245620, "name": "ELDEN RING", "two_weeks": 1110, "total": 24120 },
		{ "appid": 1145360, "name": "Hades", "two_weeks": 420, "total": 6900 },
		{ "appid": 2379780, "name": "Balatro", "two_weeks": 260, "total": 3100 },
		{ "appid": 367520, "name": "Hollow Knight", "two_weeks": 95, "total": 5200 }]
	var perfect: Array = []
	for p in DEMO_PERFECT:
		perfect.append({ "source": "steam", "appid": int(p[0]), "title": str(p[1]), "icon": "", "total": int(p[2]),
			"unlocked": int(p[2]), "date": now - int(p[3]) * 86400, "minutes": 1800 + int(p[3]) * 40 })
	steam_stats = { "games": 214, "played": 131, "minutes": 412380, "counted": 214, "with_ach": 158, "started": 97,
		"unlocked": 2847, "total": 6120, "perfect": perfect, "perfect_count": perfect.size(), "avg": 41.3,
		"counting": false, "left": 0 }
	for gid in DEMO.keys():
		if str(gid).begins_with("steam:") and int(DEMO[gid].got) > 0:
			var res := demo_game(str(gid))
			_steam_lists[int(res.appid)] = res
	if ra_profile.is_empty():
		ra_profile = { "name": "Spieler 1", "points": 12340, "true_points": 30210, "rank": 4512, "pic": "" }
	ra_profile["softcore"] = 1830
	ra_profile["member_since"] = int(Time.get_unix_time_from_datetime_string("2016-03-04T12:00:00"))
	ra_profile["motto"] = "Hardcore oder gar nicht."


## Beispiel für steam_profile_extra: das eigene Profil und die Demo-Freunde.
static func demo_extra(steamid: String) -> Dictionary:
	var out := parse_profile_xml("")
	out.error = ""
	out.ok = true
	out.public = steamid != "76561190000000007"
	if steamid == DEMO_ME:
		out.summary = "Retro-Sammler, Couch-Koop-Fan und Erfolgsjäger.\nGerade: Elden Ring NG+3 und jede Menge PS2-Klassiker im Hardcore-Modus."
		out.headline = "Immer für eine Runde zu haben"
		out.location = "Hamburg, Deutschland"
		out.member_since_text = "4. September 2009"
		out.member_since = parse_member_since(str(out.member_since_text))
		return out
	if not out.public:
		return out
	var texts := ["Meist abends online. Schreib einfach!", "Soulslikes, Metroidvanias und zu viel Kaffee.",
		"Speedruns am Wochenende – frag nach Routen.", "Koop > alles. Stardew-Farm sucht Mitbewohner.",
		"Sammle Erfolge wie andere Briefmarken. 100 % oder gar nicht."]
	var places := ["Berlin", "Köln", "Wien", "Zürich", "München", "Leipzig"]
	var h := absi(steamid.hash())
	out.summary = str(texts[h % texts.size()])
	out.location = str(places[h % places.size()])
	out.member_since = int(Time.get_unix_time_from_datetime_string("%d-0%d-15T12:00:00" % [2010 + h % 12, 1 + h % 9]))
	return out

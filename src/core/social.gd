extends Node
## Freunde: Steam über die offizielle Web-API, Discord über das Server-Widget
## (in den Servereinstellungen unter "Widget" einschalten). Keine Anmeldedaten von Discord nötig.
## Profile von Steam-Freunden (Level, zuletzt gespielt, gemeinsame Spiele, befreundet seit)
## holt Uzai ebenfalls über die Web-API und zeigt sie selbst an – ohne die Steam-Seite zu öffnen.
##
## Wer online kommt: Mit der Anmeldung als Steam-App meldet Steams Chat-Server den Status der
## Freunde sofort (SteamCM.persona) – Uzai trägt ihn gleich ein und fragt ihn regelmäßig neu ab.
## Die Web-API läuft daneben (im Menü alle 45 s, im Spiel alle 3 Min.; mit Chat-Server seltener)
## und liefert Lobby, Server und Namen. Ein frischer Status vom Chat-Server geht vor: die Web-API
## hinkt oft hinterher und zeigt private Profile immer „offline“.
##
## Freundschaftsanfragen (Punkt 11) von Steam und Discord stehen zusammen in requests; neue an dich
## meldet Uzai einmal ruhig. Annehmen und Ablehnen nur auf Knopfdruck (answer_request).

signal updated(what: String)
signal _part_done
signal _steam_done

const Lang := preload("res://src/core/lang.gd")
const FR := preload("res://src/core/friend_requests.gd")
const Sicher := preload("res://src/core/sicher.gd")
const Fremd := preload("res://src/core/fremd.gd")
const STEAM := "https://api.steampowered.com/"
const STATES := { 0: "offline", 1: "online", 2: "busy", 3: "away", 4: "away", 5: "online", 6: "online" }
const PROFILE_TTL := 600          ## Sekunden, die ein geladenes Profil gilt
const TICK := 15.0                ## Takt, in dem Uzai prüft, ob eine Abfrage fällig ist (Sekunden)
const CM_KEEP_MS := 150000        ## so lange geht ein Status vom Chat-Server der Web-API vor
const GAME_UNKNOWN := "Steam-Spiel"   ## Spiel laut Chat-Server, Name kommt aus dem Shop (App-Name) oder der Web-API
## Name eines Spiels, das man selbst nicht besitzt: der Shop kennt jede App-ID (ohne Anmeldung).
const APP_NAME := "https://store.steampowered.com/api/appdetails?appids=%d&filters=basic&l=%s"
const APP_NAMEN_MAX := 400        ## gemerkte App-Namen (danach fängt die Liste von vorn an)
const ORDER := { "game": 0, "online": 1, "busy": 2, "away": 3, "offline": 4 }

var steam_friends: Array = []     # { id, name, avatar, state, game, game_id, last, lobby, server, since }
var discord: Dictionary = {}      # Server-ID -> { name, invite, online, channels, members, error }
var steam_error := ""
var me: Dictionary = {}           ## eigenes Steam-Profil { name, avatar }
var demo := false
var _sid := ""
var _timer: Timer
var _profiles := {}               # Steam-ID -> { at, data }
var _since := {}                  # Steam-ID -> befreundet seit (Unix-Zeit)
var _mine := {}                   # eigene Spiele: App-ID -> Minuten gespielt
var _owned: Array = []            # gekaufte Steam-Spiele (zuletzt geholt)
var _owned_at := 0
const OWNED_KEEP_S := 1800
var _mine_at := 0


var _steam_sig := ""
var _discord_sig := ""
var _web_at := -10000000          ## Zeitpunkt (ms) der letzten Web-Abfrage der Freunde
var _cm_req_at := -10000000       ## … der letzten Abfrage über den Chat-Server
var _cm := {}                     ## Steam-ID -> { at, state, game, game_id, server, lobby } vom Chat-Server
var _hidden := {}                 ## Steam-ID -> true: privates Profil, die Web-API kennt den Status nicht
var _busy_steam := false
var _busy_discord := false
var _emit_due := false
var _names_due := false
var _app_namen := {}              # App-ID -> Name aus dem Shop ("" = der Shop kennt sie nicht)
var _app_laden := {}              # App-IDs, deren Name gerade geladen wird
var requests: Array = []          ## Freundschaftsanfragen beider Dienste (friend_requests.gd)
var _req_people := {}             ## Steam-ID -> { name, avatar } für Anfragen (Web-API)
var _req_sig := ""
var _req_names_busy := false
var _demo_rels := {}              ## Vorführung: Steam-Anfragen wie SteamCM.requests


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK
	_timer.timeout.connect(_tick)
	add_child(_timer)
	# Status der Freunde in Echtzeit über Steams Chat-Server (nur mit Anmeldung als Steam-App).
	SteamCM.persona.connect(_on_persona)
	SteamCM.live_changed.connect(func(on: bool) -> void:
		if on and not demo:
			_request_cm.call_deferred(true)
	)
	# Neue Steam-Nachrichten: Freunde-Bereich und Guide frischen ihre Zähler auf. Die Weiterleitung
	# lag früher im Freunde-Bereich und blieb nach jedem Neuaufbau der Oberfläche hängen (je Thema-
	# Wechsel eine Meldung mehr).
	SteamChat.changed.connect(func() -> void: updated.emit("chat"))
	SteamCM.requests_changed.connect(_on_steam_requests)
	SteamCM.friends_list.connect(_on_cm_list)
	DiscordChat.changed.connect(_rebuild_requests)
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("accounts.steam"):
			_sid = ""
		# Gerade per QR bei Steam angemeldet: Freunde und Spielzeit gleich holen.
		if k == "accounts.steam_chat_refresh" and str(Config.get_value(k, "")) != "" and not _login_refresh:
			_login_refresh = true
			_after_login.call_deferred()
	)


var _login_refresh := false


## Steam hat die Freundesliste geschickt (eine Sitzung steht gerade, etwa für gekaufte Spiele oder
## das Spiel): Ist Uzais Liste noch leer und läuft Freunde über den Chat-Server, gleich diese Sitzung
## mitnutzen – sonst stand nach einem Aussetzer bis zur nächsten erlaubten Sitzung „(0)“ da.
func _on_cm_list(_ids: Array, incremental: bool) -> void:
	if demo or incremental or not steam_friends.is_empty() or _busy_steam or _cm_busy or not SteamChat.can_send() or SteamChat.web_ok():
		return
	refresh_steam.call_deferred()


var _cm_busy := false             ## _refresh_steam_cm fragt gerade (die Liste kommt dann ohnehin)


func _after_login() -> void:
	await get_tree().create_timer(1.0).timeout
	_login_refresh = false
	await refresh()
	Library.scan()


func start() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		demo = true
		_load_demo()
		return
	refresh()
	_timer.start()


## Erfundene Freunde für Rundgang und Bildschirmfotos.
func _load_demo() -> void:
	demo = true
	me = { "name": "Spieler 1", "avatar": "" }
	var now := int(Time.get_unix_time_from_system())
	steam_friends = [
		{ "id": "76561190000000001", "name": "Mira", "avatar": "", "state": "game", "game": "ELDEN RING", "game_id": "1245620", "last": 0,
			"lobby": "109775241000000001", "server": "", "since": _day("2019-03-14") },
		{ "id": "76561190000000002", "name": "Jonas K.", "avatar": "", "state": "game", "game": "Hollow Knight", "game_id": "367520", "last": 0, "lobby": "",
			"server": "", "since": _day("2021-11-02") },
		{ "id": "76561190000000003", "name": "Lea", "avatar": "", "state": "online", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "",
			"since": _day("2017-07-21") },
		{ "id": "76561190000000004", "name": "Deniz", "avatar": "", "state": "away", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "",
			"since": _day("2023-01-09") },
		{ "id": "76561190000000005", "name": "Tom", "avatar": "", "state": "offline", "game": "", "game_id": "", "last": now - 7200, "lobby": "", "server": "",
			"since": _day("2015-12-24") },
		{ "id": "76561190000000006", "name": "Noor", "avatar": "", "state": "game", "game": "Hades", "game_id": "1145360", "last": 0, "lobby": "109775241000000006",
			"server": "", "since": _day("2022-05-30") },
		{ "id": "76561190000000007", "name": "Kai", "avatar": "", "state": "online", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "",
			"since": _day("2020-02-11") },
		{ "id": "76561190000000008", "name": "Yuki", "avatar": "", "state": "busy", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "",
			"since": _day("2018-09-03") },
		{ "id": "76561190000000009", "name": "Ben", "avatar": "", "state": "offline", "game": "", "game_id": "", "last": now - 3 * 86400 - 5000, "lobby": "",
			"server": "", "since": _day("2016-04-17") },
	]
	var dm: Array = [
		{ "name": "pixelpaul", "avatar": "", "state": "online", "game": "Ōkami", "channel": "9", "muted": false },
		{ "name": "Sana", "avatar": "", "state": "idle", "game": "Balatro", "channel": "9", "muted": false },
		{ "name": "kaito", "avatar": "", "state": "dnd", "game": "", "channel": "", "muted": false },
	]
	discord = { "1": { "name": "Retro-Runde", "invite": "", "online": 3, "error": "",
		"channels": [{ "id": "9", "name": "Zocken", "members": dm.filter(func(m): return m.channel == "9") }],
		"members": dm } }
	_demo_rels = { "76561190000000021": 2, "76561190000000022": 4 }
	_req_people = { "76561190000000021": { "name": "Marlene", "avatar": "" }, "76561190000000022": { "name": "Ole", "avatar": "" } }
	updated.emit("steam")
	updated.emit("discord")
	_rebuild_requests()


static func _day(iso: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(iso + "T12:00:00"))


func refresh() -> void:
	await refresh_steam()
	await refresh_discord()


## Beim Öffnen von Freunde-Bereich oder Guide: frisch abfragen, wenn die letzte Abfrage älter ist.
func refresh_stale(secs := 20.0) -> void:
	if demo:
		return
	if Time.get_ticks_msec() - _cm_req_at > 10000:
		_request_cm(true)
	if Time.get_ticks_msec() - _web_at > int(secs * 1000.0):
		refresh()


## Abstand der Web-Abfrage (Sekunden): im Menü oft, im Spiel sparsam. Kommt der Status schon
## vom Chat-Server, dient die Web-API nur noch zum Abgleich (Lobby, Server, Namen).
static func web_secs(in_game: bool, cm_live: bool) -> float:
	if cm_live:
		return 300.0 if in_game else 120.0
	return 180.0 if in_game else 45.0


## Abstand, in dem Uzai den Status beim Chat-Server neu abfragt – auch falls Steam Änderungen
## nicht von selbst schickt (etwa wenn du offline/unsichtbar bist).
static func cm_secs(in_game: bool) -> float:
	return 180.0 if in_game else 60.0


## Kommt der Status der Freunde gerade über den Chat-Server?
func cm_live() -> bool:
	return SteamCM.state == "angemeldet" and SteamCM.persona_at > 0 and Time.get_ticks_msec() - SteamCM.persona_at < 300000


func _tick() -> void:
	if demo:
		return
	var now := Time.get_ticks_msec()
	if SteamCM.state == "angemeldet" and now - _cm_req_at >= int(cm_secs(Launcher.in_game) * 1000.0):
		_request_cm(true)
	if now - _web_at >= int(web_secs(Launcher.in_game, cm_live()) * 1000.0) - 500:
		refresh()


## Status aller bekannten Freunde beim Chat-Server abfragen (eine Nachricht je 100 Freunde).
func _request_cm(force := false) -> void:
	if demo or SteamCM.state != "angemeldet":
		return
	var ids: Array = steam_friends.map(func(f): return str(f.get("id", "")))
	for k in SteamCM.friend_ids.keys():
		if not ids.has(str(k)):
			ids.append(str(k))
	if force:
		_cm_req_at = Time.get_ticks_msec()
	SteamCM.request_friend_data(ids, force)


## Neue Steam-Freundesdaten melden – höchstens einmal je Bild und nur, wenn sich etwas geändert hat.
func _emit_steam_soon() -> void:
	if _emit_due:
		return
	_emit_due = true
	_emit_steam.call_deferred()


func _emit_steam() -> void:
	_emit_due = false
	var sig := JSON.stringify([steam_friends, me, steam_error])
	if sig == _steam_sig:
		return
	_steam_sig = sig
	updated.emit("steam")
	_app_namen_holen()


## Sortierung der Liste: wer spielt, online, beschäftigt, abwesend, offline; sonst nach Namen.
static func sort_friends(list: Array) -> void:
	list.sort_custom(func(a, b):
		if a.state != b.state:
			return ORDER.get(a.state, 9) < ORDER.get(b.state, 9)
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)


## Status vom Chat-Server in einen Freund einrechnen (rein, für Tests). f: bisheriger Eintrag
## ({} = neu), p: aus SteamCM.parse_persona_state, title_of: App-ID -> Spielname ("" = unbekannt).
static func merge_persona(f: Dictionary, p: Dictionary, now: int, title_of: Callable) -> Dictionary:
	var out := f.duplicate()
	for k in ["name", "avatar", "game", "game_id", "lobby", "server"]:
		if not out.has(k):
			out[k] = ""
	for k in ["last", "since"]:
		if not out.has(k):
			out[k] = 0
	out["id"] = str(p.get("id", out.get("id", "")))
	if not out.has("state"):
		out["state"] = "offline"
	if str(p.get("name", "")) != "":
		out["name"] = str(p.name)
	if p.has("avatar") and str(p.avatar) != "":
		out["avatar"] = str(p.avatar)
	if int(p.get("last_logoff", 0)) > 0:
		out["last"] = int(p.last_logoff)
	if not bool(p.get("status", false)):
		return out
	var st: String = STATES.get(int(p.get("state", 0)), "offline")
	var was_on := str(out.state) != "offline"
	if st == "offline":
		out["state"] = "offline"
		out["game"] = ""
		out["game_id"] = ""
		out["lobby"] = ""
		out["server"] = ""
		if was_on and int(p.get("last_logoff", 0)) <= 0:
			out["last"] = now
		return out
	var gid := str(p.get("game_id", ""))
	var gname := str(p.get("game_name", ""))
	if gid == "" and gname == "":
		out["game"] = ""
		out["game_id"] = ""
		out["lobby"] = ""
		out["server"] = ""
	else:
		if gid != str(f.get("game_id", "")) or str(f.get("game", "")) == "":
			# Anderes Spiel: Lobby gilt nicht mehr; Name aus der Meldung, der Bibliothek oder später.
			out["lobby"] = ""
			var t := gname
			if t == "" and int(p.get("app_id", 0)) > 0 and title_of.is_valid():
				t = str(title_of.call(int(p.app_id)))
			out["game"] = t if t != "" else GAME_UNKNOWN
		elif gname != "":
			out["game"] = gname
		out["game_id"] = gid
		out["server"] = str(p.get("server", ""))
	out["state"] = "game" if str(out.game) != "" else st
	return out


## Antwort der Web-API mit dem Chat-Server abgleichen (rein, für Tests): Ein Status vom Chat-
## Server, der höchstens CM_KEEP_MS alt ist, geht vor – bei privaten Profilen (hidden) immer,
## denn dort meldet die Web-API stets „offline“. Gleiches Spiel: Name, Lobby, Server aus dem Web.
static func merge_web(web: Array, cm: Dictionary, hidden: Dictionary, now_ms: int) -> Array:
	for f in web:
		var id := str(f.get("id", ""))
		var c: Dictionary = cm.get(id, {})
		if c.is_empty() or (now_ms - int(c.get("at", 0)) > CM_KEEP_MS and not hidden.has(id)):
			continue
		if str(c.game_id) != "" and str(c.game_id) == str(f.get("game_id", "")) and str(f.get("game", "")) != "":
			f["state"] = "game"
			continue
		if str(c.state) == str(f.get("state", "")) and str(c.game_id) == str(f.get("game_id", "")):
			continue
		for k in ["state", "game", "game_id", "server", "lobby"]:
			f[k] = c.get(k, "")
	return web


## Steams Chat-Server meldet Status, Spiel oder Namen von Freunden.
func _on_persona(list: Array) -> void:
	if demo:
		return
	var now_ms := Time.get_ticks_msec()
	var now := int(Time.get_unix_time_from_system())
	var mine := SteamChat.my_id() if _sid == "" else _sid
	var idx := {}
	for i in steam_friends.size():
		idx[str(steam_friends[i].get("id", ""))] = i
	var changed := false
	for p in list:
		var id := str(p.get("id", ""))
		if id == "" or id == mine:
			continue
		var known := idx.has(id)
		# Nur Freunde (laut Liste aus Web-API oder Chat-Server), keine Leute aus Gruppenchats.
		if not known and not SteamCM.friend_ids.has(id):
			continue
		var old: Dictionary = steam_friends[idx[id]] if known else {}
		var nf := merge_persona(old, p, now, _app_title)
		if not known:
			if str(nf.name) == "":
				continue
			nf["since"] = int(_since.get(id, 0))
		if bool(p.get("status", false)):
			_cm[id] = { "at": now_ms, "state": nf.state, "game": nf.game, "game_id": nf.game_id, "server": nf.server, "lobby": nf.lobby }
			if str(nf.game) == GAME_UNKNOWN:
				_names_due = true
		if known and nf == old:
			continue
		if known:
			steam_friends[idx[id]] = nf
		else:
			steam_friends.append(nf)
			idx[id] = steam_friends.size() - 1
		changed = true
	if changed:
		sort_friends(steam_friends)
		_emit_steam_soon()
	if _names_due:
		_names_soon()


## Spielname zur App-ID aus der eigenen Bibliothek oder, für fremde Spiele, aus dem Shop ("" wenn unbekannt).
func _app_title(appid: int) -> String:
	var g := Library.get_game("steam:%d" % appid)
	return Library.display_title(g) if not g.is_empty() else str(_app_namen.get(appid, ""))


## Name aus der Antwort von appdetails?filters=basic (rein, getestet): nur ein kurzer, druckbarer
## Text, sonst "". Fremde Daten – Steuerzeichen raus, Länge begrenzt.
static func app_name_aus(data: Variant, appid: int) -> String:
	if not (data is Dictionary):
		return ""
	var e: Variant = (data as Dictionary).get(str(appid))
	if not (e is Dictionary) or not bool((e as Dictionary).get("success", false)):
		return ""
	var d: Variant = (e as Dictionary).get("data")
	if not (d is Dictionary):
		return ""
	var roh := str((d as Dictionary).get("name", ""))
	var out := ""
	for ch in roh:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges()
	return out.left(120) if out.length() <= 120 else out.left(119) + "…"


## Freunde, bei denen nur „Steam-Spiel“ steht (ein Spiel, das man selbst nicht hat): Namen im Shop
## nachsehen, je App-ID einmal, und gleich eintragen.
func _app_namen_holen() -> void:
	if demo or not is_inside_tree():
		return
	for f in steam_friends:
		if str(f.get("game", "")) != GAME_UNKNOWN:
			continue
		var gid := str(f.get("game_id", ""))
		if not gid.is_valid_int() or int(gid) <= 0 or int(gid) >= (1 << 24):
			continue
		var appid := int(gid)
		if _app_namen.has(appid) or _app_laden.has(appid):
			continue
		_app_name_laden(appid)


func _app_name_laden(appid: int) -> void:
	_app_laden[appid] = true
	var r := await Net.get_json(APP_NAME % [appid, Lang.api("steam")])
	_app_laden.erase(appid)
	if not r.ok:
		return
	if _app_namen.size() >= APP_NAMEN_MAX:
		_app_namen.clear()
	var name := app_name_aus(r.data, appid)
	_app_namen[appid] = name
	if name == "":
		return
	var changed := false
	for f in steam_friends:
		if str(f.get("game_id", "")) == str(appid) and str(f.get("game", "")) == GAME_UNKNOWN:
			f["game"] = name
			changed = true
	for id in _cm:
		var c: Dictionary = _cm[id]
		if str(c.get("game_id", "")) == str(appid) and str(c.get("game", "")) == GAME_UNKNOWN:
			c["game"] = name
	if changed:
		_emit_steam_soon()


## Ein Freund spielt etwas, dessen Namen Uzai nicht kennt: bald die Web-API fragen.
func _names_soon() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(4.0).timeout
	if _names_due and not _busy_steam:
		_names_due = false
		refresh_steam()


## Steam-Freunde, die gerade dieses Spiel spielen.
func playing(appid: int) -> Array:
	if appid <= 0:
		return []
	return steam_friends.filter(func(f): return str(f.get("game_id", "")) == str(appid))


# --- Steam ---------------------------------------------------------------------

func has_steam() -> bool:
	if not steam_friends.is_empty() and "--demo" in OS.get_cmdline_user_args():
		return true
	if SteamChat.logged_in() and not SteamChat.demo:
		return true
	return str(Config.get_value("accounts.steam_key", "")) != "" and str(Config.get_value("accounts.steam_id", "")) != ""


## Zugang für die Steam-Schnittstelle: eigener API-Schlüssel, sonst die Anmeldung per QR-Code
## (die Steam-App gibt Uzai dabei einen Zugang, der dieselben Abfragen erlaubt).
func steam_auth() -> Dictionary:
	var key := str(Config.get_value("accounts.steam_key", ""))
	if key != "":
		return { "key": key }
	if SteamChat.logged_in() and not SteamChat.demo:
		var tok := await SteamChat._token()
		if tok != "":
			return { "access_token": tok }
	return {}


## Weg für Freunde, Profil und Verlauf (rein, getestet): "key" (eigener Web-API-Schlüssel), "web"
## (Zugang aus der QR-Anmeldung), "cm" (Steams Chat-Server, nur mit Anmeldung als Steam-App) oder
## "" (kein Weg). Lehnt die Web-API den Zugang ab (web_bad) oder fehlt er, gehen Anmeldungen als
## Steam-App über den Chat-Server – vorher scheiterte dann alles still, und die Liste blieb leer.
static func steam_route(has_key: bool, can_cm: bool, web_bad: bool, has_token: bool) -> String:
	if has_key:
		return "key"
	if can_cm and (web_bad or not has_token):
		return "cm"
	if has_token:
		return "web"
	return ""


## Den Weg jetzt bestimmen: { route, auth }. Den Web-Zugang holt Uzai nur, wenn er gebraucht wird
## (beim Erneuern öffnet das neben Steam am PC sonst eine kurze Sitzung umsonst).
func _route() -> Dictionary:
	var key := str(Config.get_value("accounts.steam_key", ""))
	if key != "":
		return { "route": "key", "auth": { "key": key } }
	if not SteamChat.logged_in() or SteamChat.demo:
		return { "route": "", "auth": {} }
	var can_cm := SteamChat.can_send()
	var bad := not SteamChat.web_ok()
	var tok := ""
	if not (can_cm and bad):
		tok = await SteamChat._token()
	var r := steam_route(false, can_cm, bad, tok != "")
	return { "route": r, "auth": { "access_token": tok } if r == "web" else {} }


## Ein Konto aus SteamCM.parse_link_details in der Form von GetPlayerSummaries (rein, getestet) –
## so gelten parse_player, parse_summary und build_profile für beide Wege.
## title_of: App-ID -> Spielname ("" = unbekannt); fehlt er, steht GAME_UNKNOWN da.
static func link_to_player(a: Dictionary, title_of: Callable) -> Dictionary:
	var priv := bool(a.get("has_private", false))
	var st := int(a.get("state", 0)) if priv else 0
	var gid := str(a.get("game_id", "")) if st > 0 else ""
	var game := str(a.get("game", "")) if gid != "" else ""
	if gid != "" and game == "":
		if gid.is_valid_int() and int(gid) > 0 and int(gid) < (1 << 24) and title_of.is_valid():
			game = str(title_of.call(int(gid)))
		if game == "":
			game = GAME_UNKNOWN
	return { "steamid": str(a.get("id", "")), "personaname": str(a.get("name", "")), "avatarfull": str(a.get("avatar", "")),
		"personastate": st, "gameextrainfo": game, "gameid": gid,
		# Ohne private Angaben (privates Profil) kennt Uzai den Status nicht: wie „privat“ behandeln.
		"communityvisibilitystate": int(a.get("visibility", 0)) if priv else 1,
		"timecreated": int(a.get("created", 0)), "lastlogoff": int(a.get("last", 0)),
		"lobbysteamid": str(a.get("lobby", "")) if gid != "" else "", "gameserverip": str(a.get("server", "")) if gid != "" else "" }


## Abfrage mit Zugang: steam_query({ steamid: … }) → Teil der Adresse.
func steam_query(params: Dictionary) -> String:
	var q := (await steam_auth()).duplicate()
	q.merge(params, true)
	return Net.query(q)


## SteamID64. Akzeptiert auch den Profilnamen aus der Profil-URL und löst ihn auf.
func steam_id() -> String:
	if _sid != "":
		return _sid
	var raw := str(Config.get_value("accounts.steam_id", "")).strip_edges()
	if raw == "" and SteamChat.logged_in() and SteamChat.my_id() != "":
		_sid = SteamChat.my_id()
		return _sid
	raw = raw.trim_suffix("/").get_file() if raw.contains("steamcommunity.com") else raw
	if raw.is_valid_int() and raw.length() >= 16:
		_sid = raw
		return _sid
	var key := str(Config.get_value("accounts.steam_key", ""))
	if raw == "" or key == "":
		return ""
	var r := await Net.get_json(STEAM + "ISteamUser/ResolveVanityURL/v1/?" + Net.query({ "key": key, "vanityurl": raw }))
	var antwort := Fremd.verz(r.data, "response") if r.ok else {}
	if int(antwort.get("success", 0)) == 1:
		_sid = str(antwort.get("steamid", ""))
	return _sid


func refresh_steam() -> void:
	# Läuft schon eine Abfrage (Takt, Guide, Freunde-Bereich), auf deren Ergebnis warten statt
	# eine zweite daneben zu starten – die ältere Antwort überschrieb sonst die neuere.
	if _busy_steam:
		await _steam_done
		return
	_busy_steam = true
	_web_at = Time.get_ticks_msec()
	await _refresh_steam()
	_busy_steam = false
	_steam_done.emit()


func _refresh_steam() -> void:
	if not has_steam():
		steam_friends = []
		return
	var sid := await steam_id()
	if sid == "":
		steam_error = "Steam-ID nicht gefunden."
		_emit_steam_soon()
		return
	var rt := await _route()
	if rt.route == "cm":
		await _refresh_steam_cm(sid)
		return
	if rt.route == "":
		# Vorher fragte Uzai dann ohne Zugang – Steam lehnte ab, und nichts stand im Protokoll.
		SteamChat.diag_log("freunde", "kein", "Freunde: kein Zugang (kein Web-Zugang, Anmeldung darf nur lesen) – Liste bleibt")
		if steam_friends.is_empty():
			steam_error = "Steam hat gerade keinen Zugang gegeben. Gleich nochmal versuchen."
		_emit_steam_soon()
		return
	var how := "Schlüssel" if rt.route == "key" else "Zugang aus der Anmeldung"
	var fl := await _steam_get("ISteamUser/GetFriendList/v1/", { "steamid": sid, "relationship": "friend" })
	if not fl.ok:
		SteamChat.diag_log("freunde", "web%d" % int(fl.code), "Freunde: Web-API (%s) HTTP %d" % [how, int(fl.code)])
		if rt.route == "web" and SteamChat.can_send() and SteamChat.web_rejected(int(fl.code)):
			await _refresh_steam_cm(sid)
			return
		# Die Liste bleibt stehen; kommt der Status über den Chat-Server, bleibt sie trotzdem aktuell.
		steam_error = "Freundesliste nicht lesbar. Ist sie im Steam-Profil auf öffentlich gestellt?" if fl.code == 401 else "Steam antwortet nicht."
		_emit_steam_soon()
		return
	var ids: Array = []
	for f in Fremd.zeilen(fl.data, "friendslist/friends"):
		ids.append(str(f.get("steamid", "")))
	_since.merge(parse_since(fl.data), true)
	var mine := await _steam_get("ISteamUser/GetPlayerSummaries/v2/", { "steamids": sid })
	if mine.ok:
		for p in Fremd.zeilen(mine.data, "response/players"):
			me = { "name": str(p.get("personaname", "")), "avatar": str(p.get("avatarfull", "")), "personastate": int(p.get("personastate", 0)) }
			SteamCM.set_persona(int(p.get("personastate", 0)))
	var out: Array = []
	var hidden := {}
	for i in range(0, ids.size(), 100):
		var chunk := ids.slice(i, i + 100)
		var ps := await _steam_get("ISteamUser/GetPlayerSummaries/v2/", { "steamids": ",".join(PackedStringArray(chunk)) })
		if ps.ok:
			for p in Fremd.zeilen(ps.data, "response/players"):
				var e := parse_player(p)
				if int(p.get("communityvisibilitystate", 3)) != 3 and int(p.get("personastate", 0)) == 0:
					hidden[str(e.id)] = true
				out.append(e)
	if keep_old_list(out.size(), ids.size(), steam_friends.size()):
		# Alle Abfragen der Namen gescheitert: die bekannte Liste nicht durch eine leere ersetzen.
		SteamChat.diag_log("freunde", "web-leer", "Freunde: Web-API ohne Namen (Liste %d) – die letzte bleibt (%d)" % [ids.size(), steam_friends.size()])
		return
	_hidden = hidden
	out = merge_web(out, _cm, _hidden, Time.get_ticks_msec())
	sort_friends(out)
	# Nur melden, wenn sich etwas geändert hat: jede Meldung rechnete „Für dich“, Freunde und
	# Guide neu – auch versteckt und im Spiel.
	steam_friends = out
	steam_error = ""
	SteamChat.diag_log("freunde", "web200:%d" % out.size(), "Freunde: Web-API (%s) ok, %d Freunde, %d online" % [how, out.size(), _online(out)])
	_emit_steam_soon()
	# Neue Freunde (oder nach dem Wiederverbinden): ihren Status gleich beim Chat-Server erfragen.
	_request_cm(false)


## Die alte Liste behalten statt sie mit 0 zu überschreiben? (rein, getestet) Nur wenn Steam Freunde
## nennt, aber zu keinem Angaben kamen, und Uzai schon welche kennt.
static func keep_old_list(new_size: int, listed: int, old_size: int) -> bool:
	return new_size == 0 and listed > 0 and old_size > 0


static func _online(list: Array) -> int:
	return list.filter(func(f): return str(f.get("state", "offline")) != "offline").size()


## Freunde über Steams Chat-Server: die Liste (ClientFriendsList, kommt mit der Anmeldung) und je
## Freund Name, Bild, Status und Spiel (Player.GetPlayerLinkDetails#1). Neben Steam am PC öffnet
## das höchstens alle SteamCM.FRIENDS_GAP_S Sekunden eine kurze Sitzung (ohne eigenen Status);
## dazwischen bleibt die letzte Liste stehen, statt leer zu werden.
func _refresh_steam_cm(sid: String) -> void:
	if not SteamCM.may_open(SteamCM.LINK_DETAILS):
		SteamChat.diag_log("freunde", "warte",
				"Freunde: Steam am PC angemeldet – über Steams Chat-Server höchstens alle %d s (kurze Sitzung), dazwischen die letzte Liste (%d)" % [
					SteamCM.FRIENDS_GAP_S, steam_friends.size()])
		return
	_cm_busy = true
	var d: Dictionary = await SteamCM.player_details(str(Config.get_value("accounts.steam_chat_refresh", "")), [sid], true)
	_cm_busy = false
	if not bool(d.ok):
		SteamChat.diag_log("freunde", "cm%d%s" % [int(d.eresult), str(d.error)],
				"Freunde: Chat-Server EResult %d %s (Liste: %d Freunde)" % [int(d.eresult), str(d.error), int(d.friends)])
		if steam_friends.is_empty():
			steam_error = "Steam antwortet nicht."
			_emit_steam_soon()
		return
	var old := {}
	for f in steam_friends:
		old[str(f.get("id", ""))] = f
	var out: Array = []
	var hidden := {}
	var seen := {}
	for a in d.accounts:
		var id := str(a.get("id", ""))
		if id == sid:
			if bool(a.get("has_private", false)):
				me = { "name": str(a.get("name", "")), "avatar": str(a.get("avatar", "")), "personastate": int(a.get("state", 0)) }
				SteamCM.set_persona(int(a.get("state", 0)))
			continue
		if seen.has(id) or not (SteamCM.friend_ids.has(id) or old.has(id)):
			continue
		seen[id] = true
		var p := link_to_player(a, _app_title)
		var e := parse_player(p)
		if str(e.name) == "" and old.has(id):
			e["name"] = str(old[id].get("name", ""))
		if int(p.communityvisibilitystate) != 3 and int(p.personastate) == 0:
			hidden[id] = true
		out.append(e)
	# Wen Steam diesmal nicht beschrieben hat, der bleibt mit dem letzten Stand in der Liste.
	for id in SteamCM.friend_ids.keys():
		if not seen.has(str(id)) and old.has(str(id)):
			out.append(old[str(id)])
	if out.is_empty() and not old.is_empty():
		# Keine Freundesliste in dieser Sitzung (kam nicht rechtzeitig): die alte nicht verwerfen.
		SteamChat.diag_log("freunde", "cm-leer", "Freunde: Chat-Server ohne Freundesliste (Liste %d) – die letzte bleibt (%d)" % [int(d.friends), old.size()])
		return
	_hidden = hidden
	# Die Antwort ist so frisch wie eine Meldung des Chat-Servers; nur bei privaten Profilen (dort
	# fehlt der Status) gilt eine ClientPersonaState-Meldung, wie bei der Web-API.
	var cm_hidden := {}
	for id in hidden:
		if _cm.has(id):
			cm_hidden[id] = _cm[id]
	out = merge_web(out, cm_hidden, _hidden, Time.get_ticks_msec())
	sort_friends(out)
	steam_friends = out
	steam_error = ""
	var named := out.filter(func(f): return str(f.get("name", "")) != "").size()
	SteamChat.diag_log("freunde", "cm1:%d:%d" % [out.size(), named],
			"Freunde: Chat-Server ok, %d Freunde (Liste %d), %d mit Namen, %d online" % [out.size(), int(d.friends), named, _online(out)])
	_emit_steam_soon()
	_request_cm(false)


## Ein Freund aus GetPlayerSummaries in der Form von steam_friends.
func parse_player(p: Dictionary) -> Dictionary:
	var st: String = STATES.get(int(p.get("personastate", 0)), "offline")
	var game := str(p.get("gameextrainfo", ""))
	return {
		"id": str(p.get("steamid", "")), "name": str(p.get("personaname", "?")),
		# Klarname, wenn der Freund ihn öffentlich zeigt (für die Zuordnung Discord ↔ Steam).
		"real": str(p.get("realname", "")),
		"avatar": str(p.get("avatarfull", p.get("avatarmedium", ""))),
		"state": "game" if game != "" else st, "game": game, "game_id": str(p.get("gameid", "")),
		"last": int(p.get("lastlogoff", 0)),
		# Nur gesetzt, wenn das Spiel des Freundes Beitreten erlaubt (wie im Steam-Menü).
		"lobby": str(p.get("lobbysteamid", "")), "server": str(p.get("gameserverip", "")),
		"since": int(_since.get(str(p.get("steamid", "")), 0)),
	}


## Web-API-Abfrage mit Zugang. Lehnt Steam den Zugang aus der Anmeldung ab (abgelaufen, ehe Uzai
## es merkt), holt Uzai einmal einen frischen und fragt nochmal – sonst blieb die Liste bis zum
## Neustart auf dem alten Stand stehen.
func _steam_get(path: String, params: Dictionary) -> Dictionary:
	var auth := await steam_auth()
	var q := auth.duplicate()
	q.merge(params, true)
	var r := await Net.get_json(STEAM + path + "?" + Net.query(q))
	if not r.ok and int(r.code) in [401, 403] and auth.has("access_token"):
		SteamChat.drop_access()
		var auth2 := await steam_auth()
		if auth2.has("access_token") and str(auth2.access_token) != str(auth.access_token):
			var q2 := auth2.duplicate()
			q2.merge(params, true)
			r = await Net.get_json(STEAM + path + "?" + Net.query(q2))
	if not r.ok and auth.has("access_token"):
		SteamChat.note_web(int(r.code), path.get_slice("/", 1))
	return r


## Alle gekauften Spiele (auch nicht installierte): [{ appid, name, playtime_forever, … }].
## Mit QR-Anmeldung als Steam-App direkt über Steams Chat-Server (Player.GetOwnedGames, ohne
## Web-API-Schlüssel); sonst – oder wenn das nichts liefert – über die Web-API (Schlüssel oder
## der Zugang aus der Anmeldung).
func steam_owned_games() -> Array:
	if not has_steam():
		return []
	var now := int(Time.get_unix_time_from_system())
	if not _owned.is_empty() and now - _owned_at < OWNED_KEEP_S:
		return _owned
	var sid := await steam_id()
	if sid == "":
		return []
	if str(Config.get_value("accounts.steam_key", "")) == "" and SteamChat.logged_in() and SteamChat.can_send() and not SteamChat.demo:
		var cm: Array = await SteamCM.owned_games(str(Config.get_value("accounts.steam_chat_refresh", "")), int(sid))
		if not cm.is_empty():
			return _keep_owned(cm)
		# Die Web-API nimmt den Zugang gerade nicht an: nicht noch einmal fragen.
		if not SteamChat.web_ok():
			return _owned
	var r := await Net.get_json(STEAM + "IPlayerService/GetOwnedGames/v1/?" + await steam_query({
		"steamid": sid, "include_appinfo": 1, "include_played_free_games": 1 }))
	if not r.ok or not (r.data is Dictionary) or not (r.data.get("response") is Dictionary):
		SteamChat._log("Gekaufte Spiele über die Web-API: HTTP %d" % int(r.get("code", 0)))
		return _owned
	var raw: Variant = r.data.response.get("games", [])
	var games: Array = raw if raw is Array else []
	SteamChat._log("Gekaufte Spiele über die Web-API: %d" % games.size())
	return _keep_owned(games)


func _keep_owned(games: Array) -> Array:
	if not games.is_empty():
		_owned = games
		_owned_at = int(Time.get_unix_time_from_system())
	return games


## Neue Anmeldung: gemerkte gekaufte Spiele gelten nicht mehr.
func forget_owned() -> void:
	_owned = []
	_owned_at = 0
	_mine = {}
	_mine_at = 0


# --- Profile ---------------------------------------------------------------------

## Ein Steam-Freund aus der Liste ({} wenn unbekannt).
func steam_friend(friend_id: String) -> Dictionary:
	for f in steam_friends:
		if str(f.get("id", "")) == friend_id:
			return f
	return {}


## Profil eines Steam-Freundes für die Profilseite in Uzai (Web-API: GetPlayerSummaries,
## GetSteamLevel, GetRecentlyPlayedGames, GetOwnedGames, GetFriendList). Die Abfragen laufen
## gleichzeitig; was privat ist oder nicht antwortet, bleibt leer und ist markiert.
## { ok, id, name, avatar, state, game, game_id, lobby, server, last, level (-1: unbekannt),
##   since, created, public, recent: [{ appid, name, two_weeks, total }], recent_private,
##   shared: [{ appid, name, mine, theirs }], games_private, games_count, error }
## Spielzeiten in Minuten.
func steam_profile(friend_id: String, force := false) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var hit: Dictionary = _profiles.get(friend_id, {})
	if not force and not hit.is_empty() and now - int(hit.get("at", 0)) < PROFILE_TTL:
		return hit.data
	if demo:
		var d := demo_profile(friend_id, steam_friend(friend_id), _library_minutes())
		_profiles[friend_id] = { "at": now, "data": d }
		Config.cap(_profiles, 500)
		return d
	if not has_steam():
		return { "ok": false, "id": friend_id, "error": "Steam ist nicht verbunden. Unter Einstellungen → Konten anmelden." }
	var rt := await _route()
	if rt.route == "cm":
		return await _steam_profile_cm(friend_id, now)
	if rt.route == "":
		SteamChat.diag_log("profil", "kein", "Profil: kein Zugang (kein Web-Zugang, Anmeldung darf nur lesen)")
		return build_profile(friend_id, steam_friend(friend_id), null, null, null, null, {}, 0)
	var box := { "left": 4 }
	_part(box, "summary", STEAM + "ISteamUser/GetPlayerSummaries/v2/?" + await steam_query({ "steamids": friend_id }))
	_part(box, "level", STEAM + "IPlayerService/GetSteamLevel/v1/?" + await steam_query({ "steamid": friend_id }))
	_part(box, "recent", STEAM + "IPlayerService/GetRecentlyPlayedGames/v1/?" + await steam_query({ "steamid": friend_id, "count": 10 }))
	_part(box, "owned", STEAM + "IPlayerService/GetOwnedGames/v1/?" + await steam_query({
		"steamid": friend_id, "include_appinfo": 1, "include_played_free_games": 1 }))
	var mine := await my_game_minutes()
	var since := await friend_since(friend_id)
	while int(box.left) > 0:
		await _part_done
	var codes := PackedStringArray()
	for k in ["summary", "level", "recent", "owned"]:
		codes.append(str(int((box.get(k, {}) as Dictionary).get("code", 0))))
	SteamChat.diag_log("profil", "web" + "/".join(codes), "Profil %s: Web-API (%s) HTTP %s (Kopf/Level/Zuletzt/Spiele)" % [friend_id,
			"Schlüssel" if rt.route == "key" else "Zugang aus der Anmeldung", "/".join(codes)])
	var head_code := int((box.get("summary", {}) as Dictionary).get("code", 0))
	if rt.route == "web" and SteamChat.can_send() and SteamChat.web_rejected(head_code):
		SteamChat.note_web(head_code, "Profil")
		return await _steam_profile_cm(friend_id, now)
	var out := build_profile(friend_id, steam_friend(friend_id), _data(box, "summary"), _data(box, "level"),
		_data(box, "recent"), _data(box, "owned"), mine, since)
	if str(out.error) == "":
		_profiles[friend_id] = { "at": now, "data": out }
		Config.cap(_profiles, 500)
	return out


## Profil über Steams Chat-Server (die Web-API nimmt den Zugang nicht an): Kopf aus
## Player.GetPlayerLinkDetails#1, Bibliothek und „zuletzt gespielt“ (zwei Wochen) aus
## Player.GetOwnedGames#1 des Freundes. Das Level gibt es so nicht (bleibt „unbekannt“).
## Geöffnet auf Knopfdruck: darf wie ein Chat kurz eine Sitzung neben Steam am PC öffnen.
func _steam_profile_cm(friend_id: String, now: int) -> Dictionary:
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var d: Dictionary = await SteamCM.player_details(refresh, [friend_id], false, true)
	var summary: Variant = null
	for a in d.accounts:
		if str(a.get("id", "")) == friend_id:
			summary = { "response": { "players": [link_to_player(a, _app_title)] } }
	var g: Dictionary = await SteamCM.games_of(refresh, int(friend_id), true)
	var owned: Variant = owned_from_cm(g.games) if bool(g.ok) else null
	var recent: Variant = recent_from_cm(g.games) if bool(g.ok) else null
	SteamChat.diag_log("profil", "cm%d/%d" % [int(d.eresult), int(g.eresult)], "Profil %s: Chat-Server EResult %d (%s), Spiele EResult %d (%d)" % [friend_id,
			int(d.eresult), "Kopf da" if summary != null else "kein Kopf", int(g.eresult), (g.games as Array).size()])
	var mine := await my_game_minutes()
	var since := await friend_since(friend_id)
	var out := build_profile(friend_id, steam_friend(friend_id), summary, null, recent, owned, mine, since)
	if str(out.error) == "":
		_profiles[friend_id] = { "at": now, "data": out }
		Config.cap(_profiles, 500)
	return out


## Spiele eines Freundes vom Chat-Server in der Form von GetOwnedGames (rein, getestet). Leer
## heißt dort „privat“ (Steam schickt einer privaten Bibliothek nichts).
static func owned_from_cm(games: Array) -> Dictionary:
	if games.is_empty():
		return { "response": {} }
	return { "response": { "game_count": games.size(), "games": games } }


## … und „zuletzt gespielt“ daraus (Spielzeit der letzten zwei Wochen) wie GetRecentlyPlayedGames.
static func recent_from_cm(games: Array) -> Dictionary:
	if games.is_empty():
		return { "response": {} }
	var recent: Array = games.filter(func(g): return g is Dictionary and int(g.get("playtime_2weeks", 0)) > 0)
	return { "response": { "total_count": recent.size(), "games": recent } }


## Eine Abfrage für steam_profile im Hintergrund; meldet sich über _part_done.
func _part(box: Dictionary, key: String, url: String) -> void:
	var r := await Net.get_json(url)
	box[key] = r
	box["left"] = int(box.left) - 1
	_part_done.emit()


static func _data(box: Dictionary, key: String) -> Variant:
	var r: Variant = box.get(key)
	if r is Dictionary and bool(r.get("ok", false)):
		return r.get("data")
	return null


## Profil aus den Antworten der Web-API zusammensetzen (ohne Netz, auch für die Tests).
static func build_profile(friend_id: String, known: Dictionary, summary: Variant, level: Variant, recent: Variant,
		owned: Variant, mine: Dictionary, since: int) -> Dictionary:
	var sm := parse_summary(summary)
	var rc := parse_recent(recent)
	var ow := parse_owned(owned)
	var lv := parse_level(level)
	var got_any := not sm.is_empty() or recent != null or owned != null or lv >= 0
	var out := {
		"ok": got_any or not known.is_empty(), "id": friend_id,
		"name": str(sm.get("name", known.get("name", "Freund"))),
		"avatar": str(sm.get("avatar", known.get("avatar", ""))),
		"state": str(sm.get("state", known.get("state", "offline"))),
		"game": str(sm.get("game", known.get("game", ""))),
		"game_id": str(sm.get("game_id", known.get("game_id", ""))),
		"lobby": str(sm.get("lobby", known.get("lobby", ""))),
		"server": str(sm.get("server", known.get("server", ""))),
		"last": int(sm.get("last", known.get("last", 0))),
		"created": int(sm.get("created", 0)),
		"public": bool(sm.get("public", false)),
		"level": lv, "since": since if since > 0 else int(known.get("since", 0)),
		"recent": rc.games, "recent_private": recent != null and bool(rc.private),
		"games_private": owned != null and bool(ow.private), "games_count": (ow.games as Array).size(),
		"shared": shared_games(ow.games, mine), "top": top_game(ow.games), "error": "",
		"minutes": total_minutes(ow.games),
	}
	if not got_any:
		out["error"] = "Steam antwortet gerade nicht. Später nochmal versuchen."
	return out


## Kopf des Profils aus GetPlayerSummaries ({} wenn nichts da ist).
static func parse_summary(data: Variant) -> Dictionary:
	if not (data is Dictionary) or not (data.get("response") is Dictionary):
		return {}
	var players: Variant = data.response.get("players")
	if not (players is Array) or (players as Array).is_empty() or not (players[0] is Dictionary):
		return {}
	var p: Dictionary = players[0]
	var game := str(p.get("gameextrainfo", ""))
	var st: String = STATES.get(int(p.get("personastate", 0)), "offline")
	return {
		"id": str(p.get("steamid", "")), "name": str(p.get("personaname", "")),
		"avatar": str(p.get("avatarfull", p.get("avatarmedium", ""))),
		"state": "game" if game != "" else st, "game": game, "game_id": str(p.get("gameid", "")),
		"lobby": str(p.get("lobbysteamid", "")), "server": str(p.get("gameserverip", "")),
		"last": int(p.get("lastlogoff", 0)), "created": int(p.get("timecreated", 0)),
		"public": int(p.get("communityvisibilitystate", 1)) == 3,
	}


## Steam-Level (-1, wenn privat oder unbekannt).
static func parse_level(data: Variant) -> int:
	if data is Dictionary and data.get("response") is Dictionary and (data.response as Dictionary).has("player_level"):
		return int(data.response.player_level)
	return -1


## Zuletzt gespielt (zwei Wochen). Privat: Steam schickt eine leere Antwort ohne total_count.
static func parse_recent(data: Variant) -> Dictionary:
	var resp: Dictionary = data.response if data is Dictionary and data.get("response") is Dictionary else {}
	if not resp.has("games") and not resp.has("total_count"):
		return { "private": true, "games": [] }
	var games: Array = []
	for g in resp.get("games", []):
		if g is Dictionary and int(g.get("appid", 0)) > 0:
			games.append({ "appid": int(g.appid), "name": str(g.get("name", "")),
				"two_weeks": int(g.get("playtime_2weeks", 0)), "total": int(g.get("playtime_forever", 0)) })
	games.sort_custom(func(a, b): return int(a.two_weeks) > int(b.two_weeks))
	return { "private": false, "games": games }


## Bibliothek (GetOwnedGames). Privat: leere Antwort ohne game_count.
static func parse_owned(data: Variant) -> Dictionary:
	var resp: Dictionary = data.response if data is Dictionary and data.get("response") is Dictionary else {}
	if not resp.has("games") and not resp.has("game_count"):
		return { "private": true, "games": [] }
	var games: Array = []
	for g in resp.get("games", []):
		if g is Dictionary and int(g.get("appid", 0)) > 0:
			games.append({ "appid": int(g.appid), "name": str(g.get("name", "")), "total": int(g.get("playtime_forever", 0)) })
	return { "private": false, "games": games }


## Das meistgespielte Spiel einer Bibliothek ({} wenn leer oder nichts gespielt).
## Gesamtspielzeit aller Spiele (Minuten).
static func total_minutes(games: Array) -> int:
	var n := 0
	for g in games:
		if g is Dictionary:
			n += int(g.get("total", 0))
	return n


static func top_game(games: Array) -> Dictionary:
	var top: Dictionary = {}
	for g in games:
		if g is Dictionary and int(g.get("total", 0)) > int(top.get("total", 0)):
			top = g
	return top


## Spiele, die beide haben, die meistgespielten zuerst. mine: App-ID -> eigene Minuten.
static func shared_games(theirs: Array, mine: Dictionary) -> Array:
	var out: Array = []
	for g in theirs:
		var id := int(g.get("appid", 0))
		if id > 0 and mine.has(id):
			out.append({ "appid": id, "name": str(g.get("name", "")), "theirs": int(g.get("total", 0)), "mine": int(mine[id]) })
	out.sort_custom(func(a, b):
		var sa := int(a.mine) + int(a.theirs)
		var sb := int(b.mine) + int(b.theirs)
		return sa > sb if sa != sb else str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return out


## Aus GetFriendList: Steam-ID -> befreundet seit (Unix-Zeit).
static func parse_since(data: Variant) -> Dictionary:
	var out := {}
	if not (data is Dictionary) or not (data.get("friendslist") is Dictionary):
		return out
	for f in data.friendslist.get("friends", []):
		if f is Dictionary and int(f.get("friend_since", 0)) > 0:
			out[str(f.get("steamid", ""))] = int(f.friend_since)
	return out


## Seit wann ihr befreundet seid (0: unbekannt). Kommt meist schon aus der Freundesliste.
func friend_since(friend_id: String) -> int:
	if _since.has(friend_id):
		return int(_since[friend_id])
	var known := int(steam_friend(friend_id).get("since", 0))
	if known > 0 or demo or not has_steam():
		return known
	# Die Web-API nimmt den Zugang gerade nicht an (der Chat-Server kennt „befreundet seit“ nicht).
	if not SteamChat.web_ok() and str(Config.get_value("accounts.steam_key", "")) == "":
		return known
	var sid := await steam_id()
	if sid == "":
		return 0
	var fl := await Net.get_json(STEAM + "ISteamUser/GetFriendList/v1/?" + await steam_query({ "steamid": sid, "relationship": "friend" }))
	if fl.ok:
		_since.merge(parse_since(fl.data), true)
	return int(_since.get(friend_id, 0))


## Eigene Steam-Spiele mit Spielzeit (App-ID -> Minuten), für „gemeinsame Spiele“. Aus der
## Web-API; geht das nicht, aus der Bibliothek in Uzai.
func my_game_minutes() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	if not _mine.is_empty() and now - _mine_at < 1800:
		return _mine
	var out := {}
	if not demo and has_steam():
		for g in await steam_owned_games():
			if g is Dictionary and int(g.get("appid", 0)) > 0:
				out[int(g.appid)] = int(g.get("playtime_forever", 0))
	if out.is_empty():
		out = _library_minutes()
	_mine = out
	_mine_at = now
	return out


func _library_minutes() -> Dictionary:
	var out := {}
	for g in Library.games:
		if str(g.get("source", "")) == "steam" and int(g.get("appid", 0)) > 0:
			out[int(g.appid)] = Library.playtime(g) / 60
	return out


## „März 2019“
static func month_year(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_date_dict_from_unix_time(unix)
	return Lang.month_year(int(d.month), int(d.year))


## Spielzeit in Minuten, kurz: „45 Min.“, „3,5 Std.“, „212 Std.“
static func hours(minutes: int) -> String:
	if minutes <= 0:
		return "–"
	if minutes < 60:
		return "%d Min." % minutes
	var h := float(minutes) / 60.0
	if h < 10.0:
		return Lang.dec(("%.1f" % h).trim_suffix(".0")) + " Std."
	return "%d Std." % int(round(h))


## Beispielprofile für den Rundgang (ohne Netz): Level, Zuletzt gespielt, Bibliothek.
const DEMO_PROFILES := {
	"76561190000000001": { "level": 42, "created": "2012-06-02",
		"recent": [[1245620, "ELDEN RING", 1110, 12720], [1086940, "Baldur's Gate 3", 360, 8400], [1145360, "Hades", 72, 3060]],
		"owned": [[1245620, "ELDEN RING", 12720], [1086940, "Baldur's Gate 3", 8400], [1145360, "Hades", 3060], [367520, "Hollow Knight", 2220],
			[413150, "Stardew Valley", 5100], [570, "Dota 2", 41000], [892970, "Valheim", 1900]] },
	"76561190000000002": { "level": 17, "created": "2016-01-20",
		"recent": [[367520, "Hollow Knight", 540, 4100], [504230, "Celeste", 200, 1500]], "owned": null },
	"76561190000000003": { "level": 63, "created": "2010-11-30",
		"recent": [[413150, "Stardew Valley", 900, 9000], [2379780, "Balatro", 260, 2200]],
		"owned": [[413150, "Stardew Valley", 9000], [2379780, "Balatro", 2200], [1145360, "Hades", 1300], [105600, "Terraria", 6100]] },
	"76561190000000004": { "level": 8, "created": "2020-03-15",
		"recent": [[1091500, "Cyberpunk 2077", 420, 3600]], "owned": [[1091500, "Cyberpunk 2077", 3600], [1245620, "ELDEN RING", 900]] },
	"76561190000000005": { "level": 25, "created": "2011-08-08",
		"recent": [], "owned": [[570, "Dota 2", 52000], [730, "Counter-Strike 2", 30100], [1245620, "ELDEN RING", 4400]] },
	"76561190000000006": { "level": 31, "created": "2014-02-14",
		"recent": [[1145360, "Hades", 600, 4200], [2379780, "Balatro", 120, 800]],
			"owned": [[1145360, "Hades", 4200], [2379780, "Balatro", 800], [1086940, "Baldur's Gate 3", 6000]] },
	"76561190000000007": { "level": -1, "created": "", "recent": null, "owned": null },
	"76561190000000008": { "level": 54, "created": "2013-05-05",
		"recent": [[1086940, "Baldur's Gate 3", 840, 10200]], "owned": [[1086940, "Baldur's Gate 3", 10200], [413150, "Stardew Valley", 700]] },
	"76561190000000009": { "level": 5, "created": "2021-07-01", "recent": [], "owned": [[413150, "Stardew Valley", 300]] },
	# Freundschaftsanfrage in der Vorführung (Marlene)
	"76561190000000021": { "level": 18, "created": "2020-06-12",
		"recent": [[1145360, "Hades", 300, 2400], [413150, "Stardew Valley", 120, 3000]],
			"owned": [[1145360, "Hades", 2400], [413150, "Stardew Valley", 3000], [367520, "Hollow Knight", 1900]] },
}


## Ein Beispielprofil in derselben Form wie steam_profile (über build_profile).
static func demo_profile(friend_id: String, known: Dictionary, mine: Dictionary) -> Dictionary:
	var d: Dictionary = DEMO_PROFILES.get(friend_id, { "level": 12, "created": "", "recent": [], "owned": [] })
	var recent: Variant = null
	if d.recent != null:
		var games: Array = []
		for g in d.recent:
			games.append({ "appid": g[0], "name": g[1], "playtime_2weeks": g[2], "playtime_forever": g[3] })
		recent = { "response": { "total_count": games.size(), "games": games } }
	else:
		recent = { "response": {} }
	var owned: Variant = null
	if d.owned != null:
		var og: Array = []
		for g in d.owned:
			og.append({ "appid": g[0], "name": g[1], "playtime_forever": g[2] })
		owned = { "response": { "game_count": og.size(), "games": og } }
	else:
		owned = { "response": {} }
	var level: Variant = { "response": { "player_level": int(d.level) } } if int(d.level) >= 0 else { "response": {} }
	var p := build_profile(friend_id, known, null, level, recent, owned, mine, int(known.get("since", 0)))
	if str(d.created) != "":
		p["created"] = _day(str(d.created))
	p["public"] = d.owned != null
	return p


## Beitreten-Link, falls der Freund in einer offenen Lobby oder auf einem Server spielt. Lobby und
## Server setzt das Spiel des Freundes selbst: nur, was Sicher.steam_join_ok durchlässt.
static func join_url(f: Dictionary) -> String:
	var app := str(f.get("game_id", ""))
	var url := ""
	if str(f.get("lobby", "")) != "" and app != "":
		url = "steam://joinlobby/%s/%s/%s" % [app, f.lobby, f.id]
	elif str(f.get("server", "")) != "" and str(f.server) != "0.0.0.0:0":
		url = "steam://connect/" + str(f.server)
	return url if Sicher.steam_join_ok(url) else ""


## Freund direkt zum laufenden Steam-Spiel einladen – ohne Overlay. Uzai nutzt dafür die
## Steamworks-Bibliothek des Spiels (wie das Overlay: Rich Presence „connect“ oder Lobby).
## Geht das nicht, schickt Uzai einen Beitreten-Link in den Chat, falls das Spiel eine offene
## Lobby meldet. Rückgabe: { ok, how, text }
func invite_to_game(f: Dictionary, g: Dictionary) -> Dictionary:
	var appid := str(g.get("appid", ""))
	if not Config.is_windows() or appid == "":
		return { "ok": false, "text": "Einladen geht nur bei Steam-Spielen unter Windows." }
	var dll := Launcher.find_steam_api(g)
	var why := ""
	if dll != "":
		var ps := ""
		if dll.get_file().to_lower() == "steam_api.dll":
			ps = Helper.ps32_exe()
		var r := await Helper.run_once("steam-invite", { "dll": dll.replace("/", "\\"), "appid": appid, "friend": str(f.get("id", "")) }, ps)
		if r.ok and r.result is Dictionary and r.result.get("ok", false):
			return { "ok": true, "how": "steam", "text": "Einladung zu %s geschickt." % g.get("title", "deinem Spiel") }
		if r.ok and r.result is Dictionary and str(r.result.get("method", "")) != "none":
			why = str(r.result.get("reason", ""))
	# Rückfall: offene Lobby aus dem eigenen Steam-Profil als Link in den Chat (über Uzais
	# eigenen Steam-Chat; ohne Anmeldung dort geht das nicht).
	var lobby := ""
	if SteamChat.logged_in():
		lobby = await my_lobby()
	var link := "steam://joinlobby/%s/%s/%s" % [appid, lobby, await steam_id()] if lobby != "" else ""
	# Die Lobby nennt Steam; in den Chat geht nur ein Link in der bekannten Form aus Ziffern.
	if link != "" and Sicher.steam_join_ok(link):
		var err := await SteamChat.send(str(f.get("id", "")), "Komm in meine Lobby: " + link)
		if err == "":
			return { "ok": true, "how": "link", "text": "Beitreten-Link in den Chat geschickt." }
	if why != "":
		return { "ok": false, "text": why + "." }
	return { "ok": false, "text": "%s bietet gerade keine Einladung an. Öffne im Spiel eine Gruppe oder Lobby, dann klappt es." % g.get("title", "Das Spiel") }


## Eigene offene Lobby laut Steam-Profil ("" wenn keine).
func my_lobby() -> String:
	if not has_steam():
		return ""
	var r := await Net.get_json(STEAM + "ISteamUser/GetPlayerSummaries/v2/?" + await steam_query({ "steamids": await steam_id() }))
	if r.ok:
		for p in Fremd.zeilen(r.data, "response/players"):
			return str(p.get("lobbysteamid", ""))
	return ""


## Nachricht an einen Steam-Freund – immer über Uzais eigenen Steam-Chat, nie über das
## Steam-Fenster. Ohne Anmeldung öffnet Uzai den Chat mit der Anmeldung per QR-Code; die
## Nachricht geht raus, sobald die Anmeldung bestätigt ist. Rückgabe: "" oder ein Hinweis.
func send_steam(friend_id: String, text: String) -> String:
	if SteamChat.logged_in():
		return await SteamChat.send(friend_id, text)
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	if m == null or not m.has_method("open_layer"):
		return "Nicht bei Steam angemeldet."
	var f := steam_friend(friend_id)
	if f.is_empty():
		f = { "id": friend_id, "name": "Freund" }
	# Wie main.open_chat, nur mit der wartenden Nachricht (geht nach der Anmeldung raus).
	var chat = load("res://src/ui/layers/chat_view.gd").new()
	chat.friend = f
	chat.pending = text
	m.call("open_layer", chat)
	return "Erst kurz bei Steam anmelden (QR-Code). Danach schickt Uzai die Nachricht ab."


# --- Discord -------------------------------------------------------------------

## Alle Sprachkanäle aus den eingetragenen Servern, in denen gerade jemand ist.
func voice_channels() -> Array:
	var out: Array = []
	for sid in discord.keys():
		var d: Dictionary = discord[sid]
		for c in d.get("channels", []):
			if not c.get("members", []).is_empty():
				out.append({ "server": str(sid), "server_name": str(d.get("name", "")), "id": str(c.id), "name": str(c.name), "members": c.members })
	return out


## Link, der einen Kanal in der Discord-App öffnet (nur noch für ältere Aufrufer; Uzai selbst
## betritt Kanäle über Voice.join).
static func channel_url(server_id: String, channel_id: String) -> String:
	return "discord://-/channels/%s/%s" % [server_id, channel_id]


func servers() -> Array:
	var out: Array = []
	for s in Config.get_value("accounts.discord_servers", []):
		var id := str(s).strip_edges()
		if id != "":
			out.append(id)
	# Rundgang: der Beispielserver gilt als eingetragen.
	if out.is_empty() and demo:
		for k in discord.keys():
			out.append(str(k))
	return out


## Läufe von refresh_discord, die gerade unterwegs sind (siehe dort).
var _refresh_discord_offen := 0


func refresh_discord() -> void:
	_refresh_discord_offen += 1
	await _refresh_discord_lauf()
	_refresh_discord_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_discord täte bis zum Neustart nichts mehr.
	if _refresh_discord_offen == 0 and _busy_discord:
		_busy_discord = false


func _refresh_discord_lauf() -> void:
	if _busy_discord:
		return
	_busy_discord = true
	await _refresh_discord()
	_busy_discord = false


func _refresh_discord() -> void:
	for id in servers():
		var r := await Net.get_json("https://discord.com/api/guilds/%s/widget.json" % id)
		if not r.ok or not (r.data is Dictionary):
			discord[id] = { "name": "Server %s" % id, "error": "Widget ist aus. In Discord: Servereinstellungen → Widget → „Server-Widget aktivieren“.", "members": [],
					"channels": [], "online": 0 }
			continue
		var d: Dictionary = r.data
		var members: Array = []
		for m in Fremd.zeilen(d.get("members")):
			var act := ""
			if m.get("game") is Dictionary:
				act = str(m.game.get("name", ""))
			elif m.get("activity") is Dictionary:
				act = str(m.activity.get("name", ""))
			members.append({
				"name": str(m.get("username", "?")), "avatar": str(m.get("avatar_url", "")), "state": str(m.get("status", "online")),
				"game": act, "channel": str(m.get("channel_id", "")) if m.get("channel_id") != null else "",
				"muted": bool(m.get("self_mute", false) or m.get("mute", false)),
			})
		var channels: Array = []
		for c in Fremd.zeilen(d.get("channels")):
			var cid := str(c.get("id", ""))
			channels.append({ "id": cid, "name": str(c.get("name", "")), "members": members.filter(func(m): return m.channel == cid) })
		channels.sort_custom(func(a, b): return a.members.size() > b.members.size())
		discord[id] = {
			"name": str(d.get("name", "Discord")), "invite": str(d.get("instant_invite", "")) if d.get("instant_invite") != null else "",
			"online": int(d.get("presence_count", members.size())), "members": members, "channels": channels, "error": "",
		}
	var dsig := JSON.stringify(discord)
	if dsig == _discord_sig:
		return
	_discord_sig = dsig
	updated.emit("discord")


# --- Freundschaftsanfragen ----------------------------------------------------------------------

## Läufe von _on_steam_requests, die gerade unterwegs sind (siehe dort).
var _on_steam_requests_offen := 0


## Steams Anfragen haben sich geändert: Namen und Bilder Unbekannter über die Web-API holen
## (eine Abfrage für alle), dann die Liste neu zusammenstellen.
func _on_steam_requests() -> void:
	_on_steam_requests_offen += 1
	await _on_steam_requests_lauf()
	_on_steam_requests_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _on_steam_requests täte bis zum Neustart nichts mehr.
	if _on_steam_requests_offen == 0 and _req_names_busy:
		_req_names_busy = false


func _on_steam_requests_lauf() -> void:
	_rebuild_requests()
	if demo or _req_names_busy:
		return
	var missing: Array = SteamCM.requests.keys().filter(func(k): return not _req_people.has(str(k)))
	if missing.is_empty() or not has_steam():
		return
	_req_names_busy = true
	if str(Config.get_value("accounts.steam_key", "")) == "" and SteamChat.can_send() and not SteamChat.web_ok():
		# Über die Sitzung, mit der die Anfragen gerade kamen – nie eine eigene dafür.
		if SteamCM.state == "angemeldet":
			var d: Dictionary = await SteamCM.player_details(str(Config.get_value("accounts.steam_chat_refresh", "")), missing.slice(0, 100))
			for a in d.accounts:
				_req_people[str(a.id)] = { "name": str(a.name), "avatar": str(a.avatar) }
		_req_names_busy = false
		_rebuild_requests()
		return
	var ps := await _steam_get("ISteamUser/GetPlayerSummaries/v2/", { "steamids": ",".join(PackedStringArray(missing.slice(0, 100).map(func(k): return str(k)))) })
	_req_names_busy = false
	if ps.ok and ps.data is Dictionary:
		for p in Fremd.zeilen(ps.data, "response/players"):
			var e := parse_player(p)
			_req_people[str(e.id)] = { "name": str(e.name), "avatar": str(e.avatar) }
	_rebuild_requests()


func _steam_rels() -> Dictionary:
	return _demo_rels if demo else SteamCM.requests


## Beide Dienste zu einer Liste; nur bei Änderungen melden und neue Anfragen an dich ansagen.
func _rebuild_requests() -> void:
	var list := FR.sorted(FR.from_steam(_steam_rels(), _req_people) + FR.from_discord(DiscordChat.requests_in, DiscordChat.requests_out))
	var sig := JSON.stringify(list)
	if sig == _req_sig:
		return
	_req_sig = sig
	requests = list
	updated.emit("requests")
	_announce(list)


## Neue Anfragen an dich einmal als ruhige Mitteilung (ohne Pop-up über dem Spiel), mit dem Weg in
## den Freunde-Bereich. Was schon gemeldet war, kommt nie wieder – auch nicht nach einem Neustart.
func _announce(list: Array) -> void:
	# Vorführung: Die Beispiel-Anfragen sind „alt“ (DiscordChat lädt seine vor Social.start).
	if demo or "--demo" in OS.get_cmdline_user_args():
		return
	var seen: Array = Config.get_value("notify.requests_seen", [])
	var fresh := FR.to_announce(list, seen)
	if fresh.is_empty():
		return
	Config.set_value("notify.requests_seen", FR.remember(seen, fresh.map(func(r): return str(r.key))))
	for r in fresh.slice(0, 3):
		if bool(Config.get_value("notify.steam" if str(r.source) == "steam" else "notify.discord", true)):
			toast_request(r)


func toast_request(r: Dictionary) -> void:
	var src := str(r.get("source", ""))
	Toasts.show_toast(str(r.get("name", "")), TranslationServer.translate("möchte mit dir befreundet sein") + "  ·  " + ("Steam" if src == "steam" else "Discord"), "friends",
		{ "image": str(r.get("avatar", "")), "ms": 6500, "go": _open_requests.bind(src), "go_text": "Ansehen", "stoert": true })


func _open_requests(src: String) -> void:
	var m: Node = get_tree().current_scene
	if m != null and m.has_method("goto"):
		m.call("goto", "friends", "steam" if src == "steam" else "discord")


## Anfrage an dich annehmen oder ablehnen – nur aus einem Knopfdruck heraus. "" oder warum nicht.
func answer_request(r: Dictionary, accept: bool) -> String:
	if str(r.get("dir", "")) != FR.IN:
		return "Gesendete Anfragen beantwortet die andere Person."
	var id := str(r.get("id", ""))
	var why := ""
	if str(r.get("source", "")) == "discord":
		why = await DiscordChat.answer_request(id, accept)
	elif demo:
		if not _demo_rels.has(id):
			return "Diese Anfrage gibt es nicht mehr."
		_demo_rels.erase(id)
		if accept:
			var p: Dictionary = _req_people.get(id, {})
			steam_friends.append({ "id": id, "name": str(p.get("name", "Steam-Nutzer")), "avatar": "", "state": "online", "game": "", "game_id": "",
				"last": 0, "lobby": "", "server": "", "since": int(Time.get_unix_time_from_system()) })
			sort_friends(steam_friends)
			updated.emit("steam")
	else:
		why = await SteamCM.answer_request(str(Config.get_value("accounts.steam_chat_refresh", "")), id, accept)
		if why == "" and accept:
			refresh_steam()
	_rebuild_requests()
	return why

extends Node
## Netz-Probe für Twitch (Bereich Streams): spricht mit einem nachgebauten Twitch
## (tests/fake_twitch.py) – beliebte Streams ohne Anmeldung (TV-Kennung, Rückfall Web-Kennung),
## Geräte-Anmeldung mit Warten und „langsamer“, Konto, Gefolgt (user, Rückfall currentUser),
## abgelaufener Zugang mit Erneuern, Suche, Kanal, Kategorie, Störung, Ablauf, Abmelden,
## Anmeldung ohne Erneuerung (wie die Twitch-Apps) und mit eigener Client-ID (Helix), Protokoll.
## Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_twitch.py 18792 &
##   UZAI_DATA=<ordner> UZAI_TWITCH_API=http://127.0.0.1:18792 godot --headless --path . res://tests/net_twitch.tscn

const P := preload("res://src/core/twitch_parse.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")

var fails := 0
var base := ""
var tw: Node
var events: Array = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_TWITCH_API")
	if base == "":
		print("UZAI_TWITCH_API fehlt")
		get_tree().quit(1)
		return
	tw = Twitch
	tw.changed.connect(func(w: String) -> void: events.append(w))
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST)
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _fake(q: String) -> void:
	await Net.get_json(base + "/__set?" + q)


func _clear_log() -> void:
	# Nur das Protokoll leeren, den Zustand (Anmeldungen) behalten: neu setzen geht nicht, also
	# merken, wie viele Einträge es schon gibt.
	_skip = (await _log()).size()


var _skip := 0


func _new_log() -> Array:
	return (await _log()).slice(_skip)


## Gefolgt neu holen (eine Abfrage, die nach dem Anmelden noch läuft, erst abwarten).
func _followed() -> void:
	for i in 400:
		if not tw.followed_loading:
			break
		await get_tree().process_frame
	tw._followed_try = 0
	await tw.refresh_followed(true)


func _file(rel: String) -> String:
	var p := Config.path(rel)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func _gql(rl: Array) -> Array:
	return rl.filter(func(e): return str(e.p) == "/gql")


## Anmelden wie die Anmelde-Ebene: Code holen, dann im Abstand fragen, bis es klappt.
func _login() -> Dictionary:
	var info: Dictionary = await tw.login_start()
	if not bool(info.get("ok", false)):
		return { "info": info, "states": [] }
	var flow := GeraeteCode.neu(info, Time.get_unix_time_from_system())
	var states: Array = []
	for i in 6:
		var st: String = await tw.login_poll(str(info.device_code), str(info.get("client", "")))
		states.append(st)
		flow = P.flow_step(flow, st, Time.get_unix_time_from_system(), str(tw.last_error))
		if flow.phase != "code":
			break
	return { "info": info, "states": states, "flow": flow }


func _run() -> void:
	print("Ohne Anmeldung")
	tw.refresh_followed(true)
	await get_tree().process_frame
	check(not tw.logged_in() and (await _log()).is_empty(), "nicht angemeldet: Gefolgt fragt Twitch gar nicht")
	await tw.refresh_top(true)
	var rl := _gql(await _log())
	check(rl.size() == 2 and str(rl[0].cid) == P.TV_CLIENT and str(rl[0].auth) == "" and str(rl[0].ua).contains("Smart Box"),
			"beliebte Streams: GQL mit der TV-Kennung, ohne Anmeldung, wie die TV-App")
	check(str(rl[0].body.query).contains("broadcasterLanguages") and rl[0].body.variables.langs == ["DE"] and str(rl[0].dev).length() == 32,
			"erst in deiner Sprache (DE), mit Geräte-Kennung")
	check(tw.top.size() == 3 and str(tw.top[0].id) == "tw:live:pixelbude" and tw.top_error == "", "drei deutsche Streams")
	check(tw.top_all.size() == 1 and str(tw.top_all[0].id) == "tw:live:bigstreamer", "weltweit ohne die schon gezeigten")
	check("top" in events and "top_loading" in events, "Streams bekommt Bescheid")
	await tw.refresh_games(true)
	check(tw.games.size() == 3 and str(tw.games[0].title) == "Just Chatting", "Kategorien")

	print("TV-Kennung gesperrt: Web-Kennung")
	await _fake("tv_blocked=1")
	await _clear_log()
	await tw.refresh_top(true)
	rl = _gql(await _new_log())
	check(rl.size() == 3 and str(rl[0].cid) == P.TV_CLIENT and str(rl[1].cid) == P.WEB_CLIENT and str(rl[2].cid) == P.WEB_CLIENT,
			"erst TV, dann Web – danach gleich Web (%s)" % str(rl.map(func(e): return str(e.cid).left(4))))
	check(tw.top.size() == 3 and tw.top_error == "", "trotzdem da")
	await _fake("tv_blocked=0")
	var tlog := _file("logs/twitch.log")
	check(tlog.contains("TV-Kennung – Fehler") and tlog.contains("failed integrity check") and tlog.contains("Web-Kennung – klappt"),
			"Protokoll: welcher Weg klappte, welcher nicht")

	print("Anmelden wie die Twitch-App am Fernseher")
	await _clear_log()
	var lg := await _login()
	var info: Dictionary = lg.info
	check(bool(info.ok) and str(info.user_code) == "ABCDEFGH" and str(info.url).contains("device-code=ABCDEFGH"), "Code und Adresse für den QR-Code")
	check(lg.states == ["pending", "slow", "ok"] and str(lg.flow.phase) == "done", "erst warten, dann langsamer, dann angemeldet (%s)" % str(lg.states))
	rl = await _new_log()
	var dev: Array = rl.filter(func(e): return str(e.p) == "/oauth2/device")
	check(dev.size() == 1 and str(dev[0].body.client_id) == P.TV_CLIENT and str(dev[0].body.scopes) == P.SCOPES, "Code-Anfrage mit TV-Kennung (Formular)")
	var tok: Array = rl.filter(func(e): return str(e.p) == "/oauth2/token")
	check(tok.size() == 3 and str(tok[0].body.grant_type) == P.GRANT_DEVICE and not tok[0].body.has("client_secret"), "Abfragen mit Geräte-Code, ohne Schlüssel")
	check(rl.any(func(e): return str(e.p) == "/oauth2/validate" and str(e.auth) == "OAuth a1"), "Zugang bei Twitch geprüft")
	check(tw.logged_in() and tw.account_name() == "Testkonto" and tw.account_login() == "testkonto"
			and str(Config.get_value("accounts.twitch_user_id", "")) == "4242", "angemeldet als „Testkonto“ (4242)")
	check(tw.state == "bereit" and tw.status_text() == "Angemeldet: Testkonto" and str(Config.get_value("accounts.twitch_token_client", "")) == P.TV_CLIENT,
			"bereit, Anmeldung gehört zur TV-Kennung")
	check(str(Config.get_value("accounts.twitch_refresh", "")) == "r1" and str(Config.get_value("accounts.twitch_access", "")) == "a1"
			and int(Config.get_value("accounts.twitch_access_until", 0)) > 0, "gespeichert: Erneuerung und Zugang mit Ablauf")
	Config.save_settings()
	check(str(preload("res://tests/saved.gd").secret("accounts.twitch_refresh")) == "r1" and not _file("settings.json").contains("\"r1\""),
			"Anmeldung in settings.json, verschlüsselt")
	check("account" in events, "Streams und Einstellungen bekommen Bescheid")

	print("Gefolgt")
	await _followed()
	check(tw.followed.size() == 2 and str(tw.followed[0].id) == "tw:live:pixelbude" and str(tw.followed[1].channel) == "Speedwurm",
			"zwei gefolgte Kanäle live, meiste Zuschauer zuerst")
	rl = _gql(await _new_log())
	var fq: Array = rl.filter(func(e): return str(e.body.get("query", "")).contains("follows(first"))
	check(not fq.is_empty() and str(fq[-1].auth) == "OAuth a1" and str(fq[-1].cid) == P.TV_CLIENT, "GQL mit Anmeldung und passender Kennung")
	check(_file("cache/twitch.json").contains("pixelbude") and not _file("cache/twitch.json").contains("\"a1\"")
			and not _file("cache/twitch.json").contains("\"r1\""), "Zwischenspeicher ohne Anmeldung")
	await _fake("no_user_self=1")
	await _clear_log()
	await _followed()
	rl = _gql(await _new_log())
	check(rl.size() == 1 and str(rl[0].body.query).contains("currentUser") and tw.followed.size() == 2, "Gefolgt über currentUser („user“ ohne Angabe gibt null)")
	await _fake("no_user_self=0")

	print("Gefolgt: Wege wie im echten Protokoll")
	await _fake("nolive=1")
	await _fake("follow_pages=1")
	tw.followed = []
	tw._followed_try = 0
	await _clear_log()
	await _followed()
	rl = _gql(await _new_log())
	check(tw.followed.size() == 2 and tw.followed_error == "" and rl.size() == 2 and str(rl[0].body.query).contains("follows(first")
			and rl[1].body.variables.has("after"), "follows über zwei Seiten (followedLiveUsers: service error)")
	await _fake("nofollows=1")
	tw.followed = []
	tw._followed_try = 0
	tw._followed_way = ""
	await _clear_log()
	await _followed()
	rl = _gql(await _new_log())
	var pq: Array = rl.filter(func(e): return str(e.body.get("operationName", "")) == "ChannelFollows")
	var ul: Array = rl.filter(func(e): return str(e.body.get("query", "")).contains("users(logins:"))
	check(tw.followed.size() == 2 and pq.size() == 2 and ul.size() == 1 and str(pq[0].auth) == "OAuth a1" and str(ul[0].auth) == "",
			"follows fehlt: ChannelFollows (gespeichert) und Live-Stand je 100 Namen")
	check(_file("logs/twitch.log").contains("Weg „miner“ klappt"), "Protokoll nennt den Weg, der klappt")
	tw._followed_try = 0
	await _clear_log()
	await _followed()
	rl = _gql(await _new_log())
	check(not rl.is_empty() and str(rl[0].body.get("operationName", "")) == "ChannelFollows", "der Weg, der klappte, kommt beim nächsten Mal zuerst")
	await _fake("nopersist=1")
	await _fake("nolive=0")
	tw._followed_try = 0
	tw.followed = []
	await _followed()
	check(tw.followed.size() == 2 and tw._followed_way == "live", "follows und ChannelFollows weg: followedLiveUsers als letzter Weg")
	var t0 := Time.get_ticks_msec()
	await _clear_log()
	await tw.refresh_followed(true)
	check((await _new_log()).is_empty() and Time.get_ticks_msec() - t0 < 2000, "auf Wunsch nicht öfter als alle 5 s")
	await _fake("nofollows=0")
	await _fake("nopersist=0")
	await _fake("follow_pages=0")
	tw._followed_way = ""
	tw._followed_try = 0

	print("Neustart: gespeicherter Zugang, Erneuern abgelehnt")
	tw._access = ""
	tw._access_until = 0
	await _fake("revoked=1")
	await _followed()
	check(tw.logged_in() and tw.state == "bereit" and tw.followed.size() == 2, "Neustart: gespeicherter Zugang gilt, kein „abgelaufen“")
	tw._access = ""
	tw._access_until = 0
	Config.set_value("accounts.twitch_access_until", 1)
	await _clear_log()
	await _followed()
	rl = await _new_log()
	check(tw.logged_in() and tw.state == "bereit" and tw.followed.size() == 2 and not rl.any(func(e): return str(e.p) == "/oauth2/token"),
			"TV-Kennung: Ablaufzeit nur Richtwert, kein Erneuern (Twitch: „missing client secret“)")
	await _fake("revoked=0")

	print("Zugang abgelehnt (TV-Kennung erneuert nicht)")
	await _fake("stale=1")
	await _clear_log()
	await _followed()
	rl = await _new_log()
	var paths: Array = rl.map(func(e): return str(e.p))
	check(not paths.has("/oauth2/token") and paths.has("/oauth2/validate"), "401 → Zugang geprüft, kein Erneuern (%s)" % str(paths))
	check(not tw.logged_in() and tw.state == "abgelaufen" and tw.status_text().contains("Abgelaufen"), "Zugang weg: neu per QR anmelden")
	lg = await _login()
	await _followed()
	check(str(lg.flow.phase) == "done" and tw.logged_in() and tw.followed.size() == 2, "neu angemeldet, Gefolgt wieder da")

	print("Suche, Kanal, Kategorie (ohne Anmeldung)")
	await _clear_log()
	var se: Dictionary = await tw.search("retro")
	check((se.channels as Array).size() == 2 and (se.games as Array).size() == 1 and (se.streams as Array).size() == 1 and str(se.error) == "",
			"Kanäle, Kategorien, Streams")
	rl = _gql(await _new_log())
	check(str(rl[0].body.variables.q) == "retro" and str(rl[0].auth) == "", "Suche ohne Anmeldung")
	var ch: Dictionary = await tw.channel("Pixelbude")
	check(bool(ch.ok) and str(ch.user.name) == "Pixelbude" and not (ch.live as Dictionary).is_empty() and (ch.videos as Array).size() == 3
			and (ch.clips as Array).size() == 2, "Kanalseite mit Live, Übertragungen, Clips")
	var n_before := (await _log()).size()
	await tw.channel("pixelbude")
	check((await _log()).size() == n_before, "Kanalseite kurz gemerkt (keine zweite Anfrage)")
	var off: Dictionary = await tw.channel("retroraum")
	check(bool(off.ok) and (off.live as Dictionary).is_empty(), "Kanal offline")
	var none: Dictionary = await tw.channel("gibtsnicht")
	check(not bool(none.ok) and str(none.error) != "", "unbekannter Kanal: Meldung")
	var gs: Dictionary = await tw.game_streams(tw.games[1])
	check(str(gs.game.title) == "Retro" and (gs.items as Array).size() == 2, "Kategorie mit ihren Streams")

	print("Störung")
	await _fake("down=1")
	await tw.refresh_top(true)
	check(tw.top.size() == 3 and tw.top_error != "", "Twitch weg: Liste bleibt, Hinweis")
	await _followed()
	check(tw.followed.size() == 2 and tw.followed_error != "" and tw.logged_in(), "Gefolgt bleibt, angemeldet bleibt")
	check(_file("logs/twitch.log").contains("Gefolgt (Helix-Rückfall): Helix mit TV-Kennung – Fehler 401"),
			"GQL weg: Helix mit derselben Anmeldung versucht (ohne Abmelden)")
	await _fake("helix_tv=1")
	tw.followed = []
	await _followed()
	check(tw.followed.size() == 2 and tw.followed_error == "", "nimmt Helix die Anmeldung an: Gefolgt kommt trotzdem")
	await _fake("helix_tv=0")
	await _fake("down=0")

	print("Erneuerung widerrufen")
	await _fake("revoked=1")
	await _fake("stale=1")
	events.clear()
	await _followed()
	check(not tw.logged_in() and tw.state == "abgelaufen" and tw.account_name() == "Testkonto" and tw.status_text().contains("Abgelaufen"),
			"abgelaufen: neu anmelden, Name bleibt für den Hinweis")
	check(str(Config.get_value("accounts.twitch_refresh", "")) == "" and "account" in events and tw.followed.is_empty(), "Anmeldung vergessen, Gefolgt leer")
	await _fake("revoked=0")

	print("Wie die Twitch-Apps: ohne Erneuerung")
	await _fake("norefresh=1")
	lg = await _login()
	check(str(lg.flow.phase) == "done" and str(Config.get_value("accounts.twitch_access", "")) != ""
			and str(Config.get_value("accounts.twitch_refresh", "")) == "", "lange gültiger Zugang gespeichert (es gibt keine Erneuerung)")
	await _followed()
	check(tw.followed.size() == 2, "Gefolgt damit")
	await _fake("norefresh=0")

	print("Abmelden")
	var acc := str(Config.get_value("accounts.twitch_access", ""))
	await _clear_log()
	tw.logout()
	for i in 60:
		await get_tree().process_frame
	rl = await _new_log()
	var rv: Array = rl.filter(func(e): return str(e.p) == "/oauth2/revoke")
	check(rv.size() == 1 and str(rv[0].body.token) == acc and str(rv[0].body.client_id) == P.TV_CLIENT, "Twitch bekommt Bescheid")
	check(not tw.logged_in() and tw.account_name() == "" and tw.state == "aus" and tw.followed.is_empty(), "alles vergessen")

	print("Eigene Client-ID (offiziell, Helix)")
	Config.set_value("accounts.twitch_client_id", "ownclient123")
	Config.set_value("accounts.twitch_mode", "eigen")
	await _clear_log()
	lg = await _login()
	check(str(lg.flow.phase) == "done" and tw.helix_mode() and str(Config.get_value("accounts.twitch_token_client", "")) == "ownclient123",
			"angemeldet mit eigener Client-ID")
	check(tw.account_name() == "Testkonto", "Name über Helix /users")
	await _followed()
	rl = await _new_log()
	var hf: Array = rl.filter(func(e): return str(e.p).begins_with("/helix/streams/followed"))
	check(not hf.is_empty() and str(hf[-1].p).contains("user_id=4242") and str(hf[-1].auth).begins_with("Bearer ") and str(hf[-1].cid) == "ownclient123",
			"Gefolgt über Helix mit Bearer und eigener Client-ID")
	check(tw.followed.size() == 2 and str(tw.followed[0].id) == "tw:live:pixelbude", "gleiche Karten wie über GQL")
	tw.logout()
	Config.set_value("accounts.twitch_client_id", "")
	Config.set_value("accounts.twitch_mode", "")

	print("Protokoll")
	tlog = _file("logs/twitch.log")
	check(tlog.contains("Anmeldung: angemeldet mit TV-Kennung") and tlog.contains("Helix mit eigener Client-ID – klappt") and tlog.contains("abgelaufen"),
			"Anmeldung, Helix, Ablauf stehen drin")
	var leak := false
	for t in ["a1", "a2", "r1", "r2", "dev-ue6666"]:
		if tlog.contains(" " + t) or tlog.contains("\"" + t):
			leak = true
	check(not leak, "keine Anmeldedaten im Protokoll")

extends Node
## Netz-Probe für YouTube wie auf dem Fernseher (inoffiziell, SmartTube-Weg): spricht mit einem
## nachgebauten YouTube (tests/fake_youtube_tv.py) – Kennung aus der TV-Seite, Geräte-Anmeldung
## mit Warten und „langsamer“, Startseite mit Weiterblättern, Abos (Kanäle und Feed, youtube.log), Empfohlen hinter dem letzten Video,
## Erneuern der Anmeldung, Gesehenes melden, Rückfall bei Störung, Ablauf, Abmelden.
## Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_youtube_tv.py 18793 &
##   UZAI_DATA=<ordner> UZAI_YT_TV_API=http://127.0.0.1:18793 godot --headless --path . res://tests/net_youtube_tv.tscn

const P := preload("res://src/core/youtube_tv_parse.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")

var fails := 0
var base := ""
var tv: Node
var events: Array = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_YT_TV_API")
	if base == "":
		print("UZAI_YT_TV_API fehlt")
		get_tree().quit(1)
		return
	tv = YouTube.tv
	YouTube.changed.connect(func(w: String) -> void: events.append(w))
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


func _file(rel: String) -> String:
	var p := Config.path(rel)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func _wait_home() -> void:
	for i in 400:
		if not tv.home_loading:
			return
		await get_tree().process_frame


## Anmelden wie die Anmelde-Ebene: Code holen, dann im Abstand fragen, bis es klappt.
func _login() -> Dictionary:
	var info: Dictionary = await tv.login_start()
	if not bool(info.get("ok", false)):
		return { "info": info, "states": [] }
	var flow := GeraeteCode.neu(info, Time.get_unix_time_from_system())
	var states: Array = []
	for i in 6:
		var st: String = await tv.login_poll(str(info.device_code))
		states.append(st)
		flow = P.flow_step(flow, st, Time.get_unix_time_from_system(), str(tv.last_error))
		if flow.phase != "code":
			break
	return { "info": info, "states": states, "flow": flow }


func _run() -> void:
	print("Ohne Anmeldung")
	tv.refresh_home(true)
	await get_tree().process_frame
	check(not tv.logged_in() and not tv.home_loading and (await _log()).is_empty(), "nichts angemeldet: keine Anfrage an YouTube")

	print("Anmelden wie auf dem Fernseher")
	var lg := await _login()
	var info: Dictionary = lg.info
	check(bool(info.ok) and str(info.user_code) == "ABCD-EFGH" and str(info.url) == "https://www.google.com/device", "Code und Adresse fürs Handy")
	check(lg.states == ["pending", "slow", "ok"] and str(lg.flow.phase) == "done", "erst warten, dann langsamer, dann angemeldet (%s)" % str(lg.states))
	check(float(P.flow_step(GeraeteCode.neu(info, 0.0), "slow", 1.0).wait) == float(info.interval) + 5.0, "„langsamer“ verlängert den Abstand")
	var log := await _log()
	var paths: Array = log.map(func(e): return str(e.p))
	check(paths.slice(0, 2) == ["/tv", "/s/_/kabuki/_/js/k=kabuki.base.de.abc123/am=AAAE/base.js"], "Kennung wie SmartTube aus der TV-Seite geholt")
	check(str(log[0].ua).contains("Cobalt"), "als Fernseher-Browser (Cobalt)")
	var dev: Array = log.filter(func(e): return str(e.p) == "/o/oauth2/device/code")
	check(dev.size() == 1 and str(dev[0].body.client_id) == "111111111111-fakeclient.apps.googleusercontent.com" and str(dev[0].body.scope) == P.SCOPE
			and str(dev[0].body.device_model) == "ytlr::", "Code-Anfrage mit der Kennung aus der TV-Seite")
	var tok: Array = log.filter(func(e): return str(e.p) == "/o/oauth2/token")
	check(tok.size() == 3 and str(tok[0].body.grant_type) == P.GRANT_DEVICE and str(tok[0].body.client_secret) == "fakesecret123",
			"Abfragen mit Geräte-Code und Schlüssel")
	check(tv.logged_in() and tv.account_name() == "Testkonto" and tv.state == "bereit" and tv.status_text() == "Angemeldet: Testkonto",
			"angemeldet als „Testkonto“ (aus accounts_list)")
	check(str(Config.get_value("accounts.youtube_tv_refresh", "")) == "r1", "gespeichert: nur die Erneuerungs-Anmeldung")
	Config.save_settings()
	var settings := _file("settings.json")
	check(str(preload("res://tests/saved.gd").secret("accounts.youtube_tv_refresh")) == "r1" and not settings.contains("\"r1\"")
			and not settings.contains("\"a1\""), "nur die Erneuerung in settings.json, verschlüsselt")
	check("account" in events, "Videos und Einstellungen bekommen Bescheid")

	print("Startseite")
	await _wait_home()
	check(tv.active() and tv.shelves.size() == 2, "Startseite geladen: zwei Reihen (%d)" % tv.shelves.size())
	check(str(tv.shelves[0].title) == "Für dich" and str(tv.shelves[1].title) == "Gaming", "„Für dich“, „Gaming“ (Shorts ausgeblendet)")
	check(tv.has_more() and tv.home_error == "", "es gibt mehr Reihen, kein Fehler")
	log = await _log()
	var br: Array = log.filter(func(e): return str(e.p).begins_with("/youtubei/v1/browse") and str(e.body.get("browseId", "")) == "FEwhat_to_watch")
	check(br.size() == 1 and str(br[0].body.browseId) == "FEwhat_to_watch" and str(br[0].auth) == "Bearer a1"
			and str(br[0].body.context.client.clientName) == "TVHTML5" and str(br[0].cname) == "7", "browse FEwhat_to_watch mit Fernseher-Client und Anmeldung")
	check(str(br[0].p).contains("prettyPrint=false") and str(br[0].body.context.client.hl) == "de", "kompakt und auf Deutsch")
	check(_file("cache/youtube-tv-home.json").contains("Video Eins") and not _file("cache/youtube-tv-home.json").contains("\"a1\""),
			"Zwischenspeicher ohne Anmeldung")
	check("tvhome" in events, "Meldung „tvhome“")

	print("Abos wie auf dem Fernseher")
	for i in 400:
		if not tv.subs_loading and tv.subs_at > 0:
			break
		await get_tree().process_frame
	var tvsubs: Array = (YouTube.data.subs as Array).filter(func(s): return str(s.get("source", "")) == "tv")
	check(tvsubs.map(func(s): return str(s.title)) == ["Alpha Kanal", "Beta Kanal"] and tv.subs_error == "",
			"nach der Anmeldung: Kanäle aus FEsubscriptions übernommen (%s)" % str(tvsubs.map(func(s): return str(s.title))))
	check((tv.sub_videos as Array).size() == 2 and "subs" in events and "tvsubs" in events, "Feed der Abos da, Videos bekommen Bescheid")
	log = await _log()
	var sbr: Array = log.filter(func(e): return e.get("body") is Dictionary and str(e.body.get("browseId", "")) == "FEsubscriptions")
	check(sbr.size() == 1 and str(sbr[0].auth).begins_with("Bearer a") and str(sbr[0].body.context.client.clientName) == "TVHTML5",
			"browse FEsubscriptions mit Fernseher-Client, nach der Startseite")
	var ylog := _file("logs/youtube.log")
	check(ylog.contains("browse FEsubscriptions: HTTP 200") and ylog.contains("Abos gelesen (FEsubscriptions): 2 Kanäle, 2 Videos")
			and ylog.contains("browse FEwhat_to_watch: HTTP 200") and ylog.contains("Startseite gelesen"), "youtube.log: Anfragen, Codes, Anzahl")
	check(not ylog.contains("a1") and not ylog.contains("r1") and not ylog.contains("dev1") and not ylog.contains("fakesecret"),
			"youtube.log ohne Anmeldung, Codes und Schlüssel")
	events.clear()
	await tv.more_home()
	check(tv.shelves.size() == 3 and str(tv.shelves[2].title) == "Musik" and tv.added.size() == 1 and "tvhome_more" in events,
			"weiterblättern: Reihe „Musik“ kommt dazu")
	await tv.more_home()
	check(tv.shelves.size() == 4 and str(tv.shelves[3].title) == "Nachrichten" and not tv.has_more(), "letzte Seite: „Nachrichten“, danach nichts mehr")
	await tv.more_home()
	check(tv.shelves.size() == 4, "ohne Marke: keine weitere Anfrage")
	tv.refresh_home()
	await get_tree().process_frame
	check(not tv.home_loading, "gerade geladen: nicht gleich wieder")

	print("Empfohlen hinter dem letzten Video")
	var rel: Array = await tv.related("aaaaaaaaaa1")
	check(rel.map(func(v): return str(v.id)) == ["rrrrrrrrr01", "rrrrrrrrr02", "rrrrrrrrr03"], "next: empfohlene Videos ohne das laufende")
	var v1: Dictionary = tv.shelves[0].items[0]
	Video.queue = [v1]
	Video.index = 0
	Video.video = v1
	await tv._on_video_started(v1)
	check(Video.queue.size() == 4 and Video.has_next() and str(Video.queue[1].id) == "rrrrrrrrr01",
			"am Ende der Liste: YouTubes Empfehlungen dahinter (Abspann, automatisch weiter)")
	var before := (await _log()).size()
	Video.queue = [v1, tv.shelves[0].items[1]]
	await tv._on_video_started(v1)
	check(Video.queue.size() == 2 and (await _log()).size() == before, "mitten in einer Reihe: Reihe bleibt, keine Anfrage")
	Video.queue = []
	Video.video = {}

	print("Anmeldung erneuern")
	tv._access_until = 0
	await tv.related("ggggggggg01")
	log = await _log()
	var rf: Array = log.filter(func(e): return str(e.p) == "/o/oauth2/token" and str(e.body.get("grant_type", "")) == "refresh_token")
	check(rf.size() == 1 and str(rf[0].body.refresh_token) == "r1", "abgelaufen: von selbst erneuert")
	check(str(log[log.size() - 1].auth) == "Bearer a2", "danach mit dem neuen Zugang")
	await _fake("stale=1")
	tv.refresh_home(true)
	await _wait_home()
	log = await _log()
	var last3: Array = log.slice(log.size() - 3).map(func(e): return str(e.p))
	check(tv.home_error == "" and last3[0].begins_with("/youtubei/v1/browse") and last3[1] == "/o/oauth2/token" and last3[2].begins_with("/youtubei/v1/browse"),
			"401 mitten drin: einmal erneuern, nochmal fragen (%s)" % str(last3))
	check(tv.shelves.size() == 2, "neu geladen: wieder die erste Seite")

	print("Gesehenes melden (nur auf Wunsch)")
	before = (await _log()).size()
	Video.queue = [v1, v1]
	await tv._on_video_started(v1)
	check((await _log()).size() == before, "Standard aus: nichts gemeldet")
	Config.set_value("youtube.tv_history", true)
	check(await tv.mark_watched("aaaaaaaaaa1"), "gemeldet")
	log = await _log()
	var st: Dictionary = log[log.size() - 1]
	check(str(st.p).begins_with("/api/stats/playback?") and str(st.p).contains("docid=aaaaaaaaaa1") and str(st.p).contains("&ver=2&cpn=")
			and str(st.auth).begins_with("Bearer a"), "über die Adresse aus dem Player, mit ver=2 und cpn")
	Config.set_value("youtube.tv_history", false)
	Video.queue = []

	print("Störung: still zurück auf die Abos")
	await _fake("broken=1")
	tv.refresh_home(true)
	await _wait_home()
	check(tv.home_error == P.ERR_CHANGED and tv.active(), "unbekannter Aufbau: Hinweis, Stand von vorhin bleibt (selber Tag)")
	tv.home_at -= 2 * 86400
	tv.refresh_home(true)
	await _wait_home()
	check(not tv.active() and tv.shelves.is_empty() and tv.logged_in(), "älterer Stand: Startseite leer, Videos zeigt Abos und eigene Mischung")
	await _fake("broken=0&down=1")
	tv.refresh_home(true)
	await _wait_home()
	check(tv.home_error != "" and not tv.home_error.contains("500") and not tv.active(), "Server-Fehler: deutsche Meldung ohne Code (%s)" % tv.home_error)
	await _fake("down=0")
	tv.refresh_home(true)
	await _wait_home()
	check(tv.active() and tv.home_error == "", "wieder da: Startseite zurück")

	print("Anmeldung abgelaufen")
	await _fake("revoked=1")
	tv._access = ""
	tv.refresh_home(true)
	await _wait_home()
	check(not tv.logged_in() and tv.state == "abgelaufen" and tv.status_text() == "Abgelaufen – neu anmelden", "widerrufen: abgemeldet, Hinweis „neu anmelden“")
	check(not tv.active() and tv.account_name() == "Testkonto" and str(Config.get_value("accounts.youtube_tv_refresh", "x")) == "",
			"Startseite weg, Name bleibt für den Hinweis")
	check(_file("cache/youtube-tv-home.json") == "" and _file("cache/youtube-tv-home.json.bak") == "", "Zwischenspeicher gelöscht (auch die Sicherung)")

	print("Bekannte Kennung, wenn die TV-Seite nichts hergibt")
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST)
	await _fake("nobasejs=1")
	tv._client = {}
	DirAccess.remove_absolute(Config.path("cache/youtube-tv-client.json"))
	lg = await _login()
	log = await _log()
	dev = log.filter(func(e): return str(e.p) == "/o/oauth2/device/code")
	check(dev.size() == 1 and str(dev[0].body.client_id) == tv.FALLBACK_CLIENT.id and lg.states.back() == "ok" and tv.logged_in(),
			"öffentliche TV-Kennung genommen, Anmeldung klappt")
	await _wait_home()

	print("Abmelden")
	events.clear()
	tv.logout()
	for i in 30:
		await get_tree().process_frame
	log = await _log()
	var rv: Array = log.filter(func(e): return str(e.p) == "/revoke")
	check(rv.size() == 1 and str(rv[0].body.get("_form", {}).get("token", [""])[0]) == "r1", "Google bekommt Bescheid (Widerruf)")
	check(not tv.logged_in() and tv.account_name() == "" and tv.state == "aus" and tv.shelves.is_empty() and "account" in events,
			"Uzai vergisst Anmeldung, Name und Startseite")
	check((YouTube.data.subs as Array).filter(func(s): return str(s.get("source", "")) == "tv").is_empty() and tv.sub_videos.is_empty(),
			"übernommene Abos der Fernseher-Anmeldung gehen mit")
	Config.save_settings()
	check(str(preload("res://tests/saved.gd").secret("accounts.youtube_tv_refresh")) == "", "settings.json ohne Anmeldung")

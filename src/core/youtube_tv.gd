extends Node
## YouTube wie auf dem Fernseher (SmartTube-Weg) – auf Wunsch, nicht offiziell von Google
## unterstützt. Die offizielle Schnittstelle (Data API v3) gibt die persönliche Startseite nicht
## heraus. Darum meldet sich Uzai hier an wie die YouTube-App auf Fernsehern: Code am Handy auf
## youtube.com/activate eingeben, Uzai wartet auf die Bestätigung. Danach holt es die echte
## Startseite („Für dich“ und YouTubes Themenreihen) und die empfohlenen Videos zum Video über
## YouTubes interne Schnittstelle (InnerTube) mit dem Fernseher-Client.
##
## Hängt als Kind an YouTube (YouTube.tv) und meldet sich über YouTube.changed:
## "tvhome", "tvhome_loading", "tvhome_more", "tvsubs", "account". Die Abos (browse FEsubscriptions: Kanäle
## und ihr Feed) gibt es an YouTube weiter (YouTube.tv_abos), das sie wie die Google-Abos führt.
##
## Protokoll: logs/youtube.log im Datenordner – Anmeldung, jede Anfrage mit ihrer Art, HTTP-Code,
## Anzahl gelesener Einträge und Leser-Fehler (mit dem Aufbau der Antwort, ohne Werte). Nie
## Anmeldungen, Codes oder Cookies.
##
## Gespeichert wird nur die Erneuerungs-Anmeldung (accounts.youtube_tv_refresh) und der Kontoname.
## Die kurzlebige Zugangs-Anmeldung bleibt im Speicher; nichts davon kommt ins Protokoll.
## Ändert YouTube etwas oder ist es nicht erreichbar, bleibt die Seite still bei den Abos und
## Uzais eigener Mischung – mit einem kleinen Hinweis (home_error).

const Arbeit := preload("res://src/core/arbeit.gd")
const Logdatei := preload("res://src/core/logdatei.gd")
const P := preload("res://src/core/youtube_tv_parse.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const WEB := "https://www.youtube.com"
const REVOKE := "https://oauth2.googleapis.com/revoke"
## Fernseher-Browser von YouTube (Cobalt): so sieht die TV-Seite das Gerät als Fernseher.
const UA := "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
## Öffentliche Kennung der YouTube-TV-App, falls sie sich nicht aus der TV-Seite lesen lässt
## (dieselbe, die SmartTube und yt-dlp dokumentieren).
const FALLBACK_CLIENT := { "id": "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com", "secret": "SboVhoG9s0rNafixCSGGKXAT" }
const HOME_EVERY := 1200
const CLIENT_CACHE := "cache/youtube-tv-client.json"
const HOME_CACHE := "cache/youtube-tv-home.json"
const SUBS_CACHE := "cache/youtube-tv-subs.json"
const SUBS_EVERY := 1200
const SUBS_LEER := { "channels": [], "videos": [], "continuation": "" }

## Anmeldung wie am Fernseher: aus | bereit | abgelaufen | fehler (Tabelle gemeinsam mit Twitch und Epic in konten.gd).
var state := "aus":
	set(neu):
		Zustand.wechsel("konto.youtube_tv", Konten.ZUSTAENDE_KONTO, state, neu)
		state = neu
var last_error := ""
var shelves: Array = []          ## [{ title, items: [Video] }] – die Startseite
var home_at := 0
var home_loading := false
var home_error := ""             ## letzter Fehler der Startseite ("" wenn sie kam)
var added: Array = []            ## die zuletzt durch Weiterblättern dazugekommenen Reihen
var sub_videos: Array = []       ## neue Videos der Abos, wie YouTube sie schickt (Feed „Abos“)
var subs_at := 0
var subs_loading := false
var subs_error := ""             ## letzter Fehler der Abos ("" wenn sie kamen)
var _subs_try := 0
const ERR_SUBS := "Deine Abos kamen von YouTube in einer unbekannten Form – vermutlich hat YouTube etwas geändert."
var demo := false
var _cont := ""
var _more_loading := false
var _related := {}               ## Video-ID → empfohlene Videos (nur in dieser Sitzung)
var _access := ""
var _access_until := 0
var _refreshing := false
var _client: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _hooked := false
signal _token_ready


func _ready() -> void:
	_rng.randomize()
	demo = "--demo" in OS.get_cmdline_user_args()
	if demo:
		return
	if logged_in():
		state = "bereit"
		var c: Variant = Config.read_json(Config.path(HOME_CACHE), {})
		if c is Dictionary and c.get("shelves") is Array:
			shelves = c.shelves
			home_at = int(c.get("at", 0))
			_cont = str(c.get("cont", ""))
		var sc: Variant = Config.read_json(Config.path(SUBS_CACHE), {})
		if sc is Dictionary and sc.get("videos") is Array:
			sub_videos = (sc.videos as Array).filter(func(e: Variant) -> bool: return e is Dictionary and str(e.get("id", "")).length() == 11)
			subs_at = int(sc.get("at", 0))
	elif account_name() != "":
		state = "abgelaufen"


## Adresse der YouTube-Dienste; UZAI_YT_TV_API lenkt alles (TV-Seite, Anmeldung, InnerTube,
## Widerruf) für Netz-Proben auf einen nachgebauten Server um.
static func base() -> String:
	var t := Config.probe_env("UZAI_YT_TV_API").trim_suffix("/")
	return t if t != "" else WEB


static func revoke_url() -> String:
	var t := Config.probe_env("UZAI_YT_TV_API").trim_suffix("/")
	return t + "/revoke" if t != "" else REVOKE


func logged_in() -> bool:
	return str(Config.get_value("accounts.youtube_tv_refresh", "")) != ""


func account_name() -> String:
	return str(Config.get_value("accounts.youtube_tv_name", ""))


## Zeigt Videos → Startseite die Reihen von YouTube?
func active() -> bool:
	return logged_in() and not shelves.is_empty()


func status_text() -> String:
	match state:
		"bereit": return "Angemeldet: " + account_name() if account_name() != "" else "Angemeldet"
		"fehler": return "Gerade gestört"
		"abgelaufen": return "Abgelaufen – neu anmelden"
	return "Nicht angemeldet"


## Beim Start von Uzai (YouTube.start): Startseite holen, Player-Haken setzen.
func start() -> void:
	_hook_player()
	if demo or not logged_in():
		return
	yt_log("Start: angemeldet wie ein Fernseher")
	await refresh_home()
	refresh_subs()


func _hook_player() -> void:
	if _hooked or not has_node("/root/Video"):
		return
	_hooked = true
	get_node("/root/Video").started.connect(_on_video_started)


func _emit(what: String) -> void:
	var yt := get_parent()
	if yt and yt.has_signal("changed"):
		yt.emit_signal("changed", what)


func _log(text: String) -> void:
	print("Uzai: YouTube (Fernseher-Anmeldung): ", P.log_sicher(text))
	yt_log(text)


var _last_yt_log := ""


## Eine Zeile in logs/youtube.log (ohne Zugangsdaten, siehe P.log_sicher). Auch für YouTube selbst.
func yt_log(text: String) -> void:
	var t := P.log_sicher(text)
	if demo or t == _last_yt_log:
		return
	_last_yt_log = t
	Logdatei.zeile(Config.path("logs/youtube.log"), t, 300000)


## Art einer InnerTube-Anfrage fürs Protokoll: Endpunkt und Seite, ohne Video- oder Kanal-Kennung.
static func art_von(endpoint: String, payload: Dictionary) -> String:
	var bid := str(payload.get("browseId", ""))
	if bid.begins_with("FE"):
		return "%s %s" % [endpoint, bid]
	if bid.begins_with("UC"):
		return endpoint + " Kanal"
	if payload.has("continuation"):
		return endpoint + " Fortsetzung"
	return endpoint


# --- Netz -------------------------------------------------------------------------------------

## { ok, code, data, text } – eigene Anfrage, damit die Kopfzeilen (Fernseher-Browser) stimmen.
func _http(url: String, headers: PackedStringArray, method := HTTPClient.METHOD_GET, payload: Variant = null, timeout := 15.0) -> Dictionary:
	var h := headers.duplicate()
	h.append("User-Agent: " + UA)
	var body := ""
	if payload != null:
		body = JSON.stringify(payload)
		h.append("Content-Type: application/json")
	# Eigene Plätze („yt“), damit YouTube nie hinter Shop und Bildern wartet.
	var r := await Net.request(url, h, method, body, timeout, "yt")
	var out := { "ok": false, "code": 0, "data": null, "text": "" }
	if int(r.result) == HTTPRequest.RESULT_SUCCESS:
		out.code = int(r.code)
		var bytes: PackedByteArray = r.body
		# Die Startseite ist oft 1–2 MB JSON: groß im Hintergrund lesen (Net.parse_json).
		out.data = await Net.parse_json(bytes)
		out.text = "" if out.data != null and bytes.size() >= Net.JSON_OFF_BYTES else bytes.get_string_from_utf8()
		out.ok = int(out.code) >= 200 and int(out.code) < 300
		out["bytes"] = bytes.size()
		out["kein_json"] = not bytes.is_empty() and out.data == null
	return out


## Fernseher-Kennung: wie SmartTube aus dem Skript der TV-Seite, sonst die bekannte öffentliche.
func _get_client() -> Dictionary:
	if not _client.is_empty():
		return _client
	var c: Variant = Config.read_json(Config.path(CLIENT_CACHE), {})
	if c is Dictionary and str(c.get("id", "")) != "" and Time.get_unix_time_from_system() - float(c.get("at", 0)) < 7 * 86400:
		_client = { "id": str(c.id), "secret": str(c.get("secret", "")) }
		return _client
	var page := await _http(base() + "/tv", PackedStringArray(["Accept: text/html"]))
	var src := P.base_js_url(str(page.text)) if page.ok else ""
	if src != "":
		if src.begins_with("//"):
			src = "https:" + src
		elif src.begins_with("/"):
			src = base() + src
		var js := await _http(src, PackedStringArray())
		if js.ok:
			_client = P.client_from_js(str(js.text))
	if _client.is_empty():
		_client = FALLBACK_CLIENT.duplicate()
		_log("Kennung aus der TV-Seite nicht lesbar, nehme die bekannte")
	else:
		var keep := _client.duplicate()
		keep["at"] = int(Time.get_unix_time_from_system())
		Config.write_json(Config.path(CLIENT_CACHE), keep)
	return _client


# --- Anmelden, erneuern, abmelden ---------------------------------------------------------------

## { ok, device_code, user_code, url, interval, expires } oder { ok: false, error }
func login_start() -> Dictionary:
	if demo:
		return { "ok": true, "device_code": "demo", "user_code": "ABC-DEF-GHI", "url": P.ACTIVATE_URL, "interval": 5, "expires": 1800 }
	var c := await _get_client()
	var dev := "%08x%08x%08x%08x" % [_rng.randi(), _rng.randi(), _rng.randi(), _rng.randi()]
	var r := await _http(base() + "/o/oauth2/device/code", PackedStringArray(), HTTPClient.METHOD_POST, P.device_request(str(c.id), dev))
	var out := P.parse_device_code(int(r.code), r.data)
	if not bool(out.ok):
		_log("Anmeldung: kein Code (HTTP %d)" % int(r.code))
	else:
		yt_log("Anmeldung: Code geholt (HTTP %d), warte auf Bestätigung am Handy" % int(r.code))
	return out


## Einmal nachfragen, ob der Code bestätigt ist: "pending", "slow", "ok", "denied", "expired",
## "error" (dann steht der Grund in last_error).
func login_poll(device_code: String) -> String:
	var c := await _get_client()
	var r := await _http(base() + "/o/oauth2/token", PackedStringArray(), HTTPClient.METHOD_POST, {
		"client_id": str(c.id), "client_secret": str(c.secret), "code": device_code, "grant_type": P.GRANT_DEVICE,
	})
	var t := P.parse_token(int(r.code), r.data, _now())
	if not bool(t.ok):
		last_error = str(t.error)
		if not str(t.state) in ["pending", "slow"]:
			yt_log("Anmeldung: %s (HTTP %d)" % [str(t.state), int(r.code)])
		return "expired" if str(t.state) == "revoked" else str(t.state)
	_access = str(t.access)
	_access_until = int(t.expires_at)
	if str(t.refresh) == "":
		last_error = "Google hat keine dauerhafte Anmeldung geschickt."
		return "error"
	Config.set_value("accounts.youtube_tv_refresh", str(t.refresh))
	var who := await _fetch_name()
	Config.set_value("accounts.youtube_tv_name", who if who != "" else "YouTube-Konto")
	state = "bereit"
	last_error = ""
	_log("angemeldet")
	_emit("account")
	_nach_anmeldung()
	return "ok"


## Gleich nach der Anmeldung: erst die Startseite, dann die Abos (nacheinander, nicht zugleich).
func _nach_anmeldung() -> void:
	await refresh_home(true)
	refresh_subs(true)


func _fetch_name() -> String:
	var r := await innertube("account/accounts_list", {})
	var n := P.parse_account_name(r.data) if r.ok else ""
	if r.ok and n == "":
		yt_log("Kontoname nicht gefunden – Aufbau: " + P.shape(r.data))
	return n


## Abmelden: Google bekommt Bescheid (falls erreichbar), Uzai vergisst Anmeldung und Startseite.
func logout() -> void:
	var tok := str(Config.get_value("accounts.youtube_tv_refresh", ""))
	Config.set_value("accounts.youtube_tv_refresh", "")
	Config.set_value("accounts.youtube_tv_name", "")
	_access = ""
	_access_until = 0
	_forget_home()
	_forget_subs(true)
	state = "aus"
	last_error = ""
	_log("abgemeldet")
	_emit("account")
	if tok != "":
		Net.post_form(revoke_url(), { "token": tok })


func _forget_home() -> void:
	shelves = []
	home_at = 0
	home_error = ""
	_cont = ""
	_related.clear()
	# Auch die Sicherungen (write_json behält .bak; read_json nähme sie sonst wieder).
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Config.path(HOME_CACHE) + suffix):
			DirAccess.remove_absolute(Config.path(HOME_CACHE) + suffix)


## Gültige Zugangs-Anmeldung, bei Bedarf erneuert ("" wenn das nicht ging).
func _token() -> String:
	if _access != "" and _access_until - 60 > _now():
		return _access
	var rt := str(Config.get_value("accounts.youtube_tv_refresh", ""))
	if rt == "":
		return ""
	if _refreshing:
		await _token_ready
		return _access
	_refreshing = true
	# Das Erneuern läuft in einer eigenen Funktion: Bricht es mit einem Fehler ab, wird hier trotzdem gelöst und
	# gemeldet. Sonst warteten alle späteren Abrufe für immer auf _token_ready.
	await _erneuern(rt)
	_refreshing = false
	_token_ready.emit()
	return _access


## Holt mit dem Erneuerungsschlüssel einen neuen Zugang (nur aus _token, siehe dort).
func _erneuern(rt: String) -> void:
	var c := await _get_client()
	var r := await _http(base() + "/o/oauth2/token", PackedStringArray(), HTTPClient.METHOD_POST, {
		"client_id": str(c.id), "client_secret": str(c.secret), "refresh_token": rt, "grant_type": "refresh_token",
	})
	var t := P.parse_token(int(r.code), r.data, _now())
	yt_log("Anmeldung erneuern: HTTP %d, %s" % [int(r.code), "ok" if bool(t.ok) else str(t.state)])
	if bool(t.ok):
		_access = str(t.access)
		_access_until = int(t.expires_at)
		if str(t.refresh) != "" and str(t.refresh) != rt:
			Config.set_value("accounts.youtube_tv_refresh", str(t.refresh))
		if state != "bereit":
			state = "bereit"
			_emit("account")
	else:
		_access = ""
		last_error = str(t.error)
		if str(t.state) == "revoked":
			# Abgelaufen oder widerrufen: neu anmelden; der Name bleibt für den Hinweis.
			Config.set_value("accounts.youtube_tv_refresh", "")
			_forget_home()
			_forget_subs()
			state = "abgelaufen"
			_log("Anmeldung abgelaufen")
			_emit("account")
		else:
			state = "fehler"


## Anfrage an YouTubes interne Schnittstelle mit dem Fernseher-Client. { ok, code, data }
func innertube(endpoint: String, payload: Dictionary) -> Dictionary:
	var art := art_von(endpoint, payload)
	var tok := await _token()
	if tok == "":
		yt_log("%s: keine gültige Anmeldung, nicht gefragt" % art)
		return { "ok": false, "code": 401, "data": null }
	var b := P.body(payload, "de", str(Config.get_value("youtube.region", "DE")))
	var t0 := Time.get_ticks_msec()
	var url := base() + "/youtubei/v1/%s?prettyPrint=false" % endpoint
	var r := {}
	for attempt in 2:
		r = await _http(url, PackedStringArray([
			"Authorization: Bearer " + tok, "X-YouTube-Client-Name: " + P.CLIENT_NUM,
			"X-YouTube-Client-Version: " + P.CLIENT_VERSION, "Origin: " + WEB,
		]), HTTPClient.METHOD_POST, b, 20.0)
		if int(r.code) != 401 or attempt == 1:
			break
		# Zugang abgelaufen (etwa nach dem Ruhezustand): einmal erneuern und nochmal.
		_access = ""
		tok = await _token()
		if tok == "":
			break
	yt_log("%s: HTTP %d, %d KB, %d ms%s" % [art, int(r.get("code", 0)), int(r.get("bytes", 0)) / 1024, Time.get_ticks_msec() - t0,
		", Antwort kein JSON" if bool(r.get("kein_json", false)) else ""])
	return r


## Eine Antwort übersetzen (fn: einer der Leser aus P, fertig gebunden). Der Leser sieht sich jede Kachel einzeln
## an – gemessen 55 ms für eine Startseite mit 670 Videos, 90 ms für die Abos. Große Antworten darum im Hintergrund,
## wie schon ihr JSON (Net.parse_json); sonst stockt das Menü genau dann, wenn der Bereich aufgeht. Die Leser sind
## rein: kein Zustand, nichts aus dem Baum der Oberfläche. leer: das Ergebnis ohne Antwort oder nach einem Abbruch.
func _lesen(r: Dictionary, fn: Callable, leer: Variant) -> Variant:
	if not bool(r.get("ok", false)):
		return leer
	if int(r.get("bytes", 0)) < Net.JSON_OFF_BYTES:
		return fn.call()
	var v: Variant = await Arbeit.ergebnis(fn)
	return v if typeof(v) == typeof(leer) else leer


# --- Startseite ----------------------------------------------------------------------------------

func _hide_shorts() -> bool:
	return bool(Config.get_value("youtube.hide_shorts", true))


## Läufe von refresh_home, die gerade unterwegs sind (siehe dort).
var _refresh_home_offen := 0


## Startseite neu holen (höchstens alle HOME_EVERY Sekunden, force: sofort).
func refresh_home(force := false) -> void:
	_refresh_home_offen += 1
	await _refresh_home_lauf(force)
	_refresh_home_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_home täte bis zum Neustart nichts mehr.
	if _refresh_home_offen == 0 and home_loading:
		home_loading = false


func _refresh_home_lauf(force := false) -> void:
	if demo or home_loading or not logged_in():
		return
	var now := _now()
	if not force and now - home_at < HOME_EVERY and not shelves.is_empty() and home_error == "":
		return
	home_loading = true
	_emit("tvhome_loading")
	var before := _key(shelves)
	var t0 := Time.get_ticks_msec()
	var r := await innertube("browse", { "browseId": "FEwhat_to_watch" })
	var p: Dictionary = await _lesen(r, P.parse_browse.bind(r.data, now, _hide_shorts()), { "shelves": [], "continuation": "" })
	Media.log_line("leistung", "Videos: YouTube-Startseite in %d ms (%d Reihen)" % [Time.get_ticks_msec() - t0, (p.shelves as Array).size()])
	if not logged_in():
		home_loading = false
		_emit("tvhome")
		return
	if not (p.shelves as Array).is_empty():
		var n := 0
		for s in p.shelves:
			n += (s.items as Array).size()
		yt_log("Startseite gelesen: %d Reihen, %d Videos" % [(p.shelves as Array).size(), n])
		shelves = p.shelves
		_cont = str(p.continuation)
		home_at = now
		home_error = ""
		if state != "bereit" and logged_in():
			state = "bereit"
		Config.write_json(Config.path(HOME_CACHE), { "at": home_at, "shelves": shelves, "cont": _cont })
	else:
		home_error = P.explain(int(r.code)) if not r.ok else P.ERR_CHANGED
		if r.ok:
			_log("Startseite ohne Reihen – Aufbau unbekannt: " + P.shape(r.data))
		else:
			_log("Startseite nicht geladen (%d)" % int(r.code))
		# Ein Zwischenstand vom selben Tag bleibt stehen, ältere Reihen nicht.
		if now - home_at > 86400:
			shelves = []
			_cont = ""
	home_loading = false
	_emit("tvhome" if _key(shelves) != before or not home_error.is_empty() else "tvhome_loading")


func has_more() -> bool:
	return _cont != "" and not demo


## Läufe von more_home, die gerade unterwegs sind (siehe dort).
var _more_home_offen := 0


## Weitere Reihen der Startseite (beim Blättern nach unten). Neue Reihen stehen dann in added.
func more_home() -> void:
	_more_home_offen += 1
	await _more_home_lauf()
	_more_home_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und more_home täte bis zum Neustart nichts mehr.
	if _more_home_offen == 0 and _more_loading:
		_more_loading = false


func _more_home_lauf() -> void:
	if _more_loading or _cont == "" or not logged_in():
		return
	_more_loading = true
	var r := await innertube("browse", { "continuation": _cont })
	if not r.ok:
		_more_loading = false
		return
	# Die Marke bleibt bis nach dem Lesen stehen: Sonst holte ein zweiter Aufruf dieselbe Fortsetzung noch einmal.
	var p: Dictionary = await _lesen(r, P.parse_browse.bind(r.data, _now(), _hide_shorts(), "Mehr für dich"), { "shelves": [], "continuation": "" })
	_more_loading = false
	yt_log("Startseite weiter: %d Reihen" % (p.shelves as Array).size())
	_cont = str(p.continuation)
	var known := {}
	for s in shelves:
		known[str(s.title) + "|" + _key([s])] = true
	added = []
	for s in p.shelves:
		if not known.has(str(s.title) + "|" + _key([s])):
			added.append(s)
	if added.is_empty():
		return
	shelves.append_array(added)
	_emit("tvhome_more")


static func _key(list: Array) -> String:
	var ids := PackedStringArray()
	for s in list:
		ids.append(str(s.get("title", "")))
		for v in s.get("items", []):
			ids.append(str(v.get("id", "")))
	return ",".join(ids)


# --- Abos ----------------------------------------------------------------------------------------

## Läufe von refresh_subs, die gerade unterwegs sind (siehe dort).
var _refresh_subs_offen := 0


## Abos wie auf dem Fernseher holen (höchstens alle SUBS_EVERY Sekunden, force: sofort): die Seite
## „Abos“ (FEsubscriptions) mit den Kanälen und ihren neuen Videos. Schickt YouTube dort keine
## Kanalliste, fragt Uzai die Kanalseite (FEchannels); fehlt sie auch, nimmt es die Kanäle aus den
## Videos. Ist dagegen der Feed leer und die Kanäle da, zeigt Uzai wenigstens die Kanäle (ihre
## neuen Videos kommen dann über RSS). Weitergegeben an YouTube.tv_abos.
func refresh_subs(force := false) -> void:
	_refresh_subs_offen += 1
	await _refresh_subs_lauf(force)
	_refresh_subs_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_subs täte bis zum Neustart nichts mehr.
	if _refresh_subs_offen == 0 and subs_loading:
		subs_loading = false


func _refresh_subs_lauf(force := false) -> void:
	if demo or subs_loading or not logged_in():
		return
	var now := _now()
	if not force and (now - subs_at < SUBS_EVERY and subs_error == "" or now - _subs_try < 60):
		return
	_subs_try = now
	subs_loading = true
	var r := await innertube("browse", { "browseId": "FEsubscriptions" })
	var p: Dictionary = await _lesen(r, P.parse_subs.bind(r.data, now, _hide_shorts()), SUBS_LEER.duplicate(true))
	var channels: Array = p.channels
	var videos: Array = p.videos
	yt_log("Abos gelesen (FEsubscriptions): %d Kanäle, %d Videos" % [channels.size(), videos.size()] if r.ok else "Abos nicht geladen (HTTP %d)" % int(r.code))
	if r.ok and channels.is_empty():
		if videos.is_empty():
			yt_log("Abos: nichts gefunden – Aufbau: " + P.shape(r.data))
		var r2 := await innertube("browse", { "browseId": "FEchannels" })
		if r2.ok:
			var p2: Dictionary = await _lesen(r2, P.parse_subs.bind(r2.data, now, _hide_shorts()), SUBS_LEER.duplicate(true))
			channels = p2.channels
			yt_log("Kanalliste (FEchannels): %d Kanäle" % channels.size())
			if channels.is_empty():
				yt_log("Kanalliste: nichts gefunden – Aufbau: " + P.shape(r2.data))
		if channels.is_empty() and not videos.is_empty():
			channels = P.channels_from_videos(videos)
			yt_log("Kanäle aus den Videos des Feeds: %d" % channels.size())
	subs_loading = false
	if not logged_in():
		return
	if not r.ok or channels.is_empty() and videos.is_empty():
		subs_error = P.explain(int(r.code)) if not r.ok else ERR_SUBS
		_emit("tvsubs")
		return
	subs_error = ""
	subs_at = now
	sub_videos = videos
	Config.write_json(Config.path(SUBS_CACHE), { "at": subs_at, "videos": sub_videos })
	var yt := get_parent()
	if yt and yt.has_method("tv_abos"):
		yt.call("tv_abos", channels)
	_emit("tvsubs")


## abos_auch: auch die übernommenen Kanäle (Abmelden). Läuft die Anmeldung nur ab, bleiben sie –
## ihre neuen Videos kommen weiter über RSS, ohne Anmeldung.
func _forget_subs(abos_auch := false) -> void:
	sub_videos = []
	subs_at = 0
	subs_error = ""
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Config.path(SUBS_CACHE) + suffix):
			DirAccess.remove_absolute(Config.path(SUBS_CACHE) + suffix)
	var yt := get_parent()
	if abos_auch and yt and yt.has_method("tv_abos_vergessen"):
		yt.call("tv_abos_vergessen")


# --- Empfohlen zum Video, Verlauf -------------------------------------------------------------

## Empfohlene Videos zu einem Video (InnerTube „next“), [] ohne Anmeldung oder bei Fehlern.
func related(video_id: String) -> Array:
	if demo or not logged_in() or video_id.length() != 11:
		return []
	if _related.has(video_id):
		return _related[video_id]
	var r := await innertube("next", { "videoId": video_id })
	var list: Array = await _lesen(r, P.parse_next.bind(r.data, video_id, _now(), _hide_shorts()), [])
	if not list.is_empty():
		_related[video_id] = list
		while _related.size() > 30:
			_related.erase(_related.keys()[0])
	return list


## Läuft ein YouTube-Video am Ende der Liste, kommen YouTubes Empfehlungen dahinter – dann
## zeigen Abspann und „Automatisch weiter“ das, was YouTube als Nächstes vorschlägt.
func _on_video_started(v: Dictionary) -> void:
	if not logged_in() or v.has("movies") or str(v.get("url", "")) != "":
		return
	var id := str(v.get("id", ""))
	if id.length() != 11:
		return
	if bool(Config.get_value("youtube.tv_history", false)):
		mark_watched(id)
	var vid: Node = get_node_or_null("/root/Video")
	if vid == null or int(vid.index) < (vid.queue as Array).size() - 1:
		return
	var list := await related(id)
	if list.is_empty() or str(vid.video.get("id", "")) != id or int(vid.index) < (vid.queue as Array).size() - 1:
		return
	var have := {}
	for q in vid.queue:
		have[str(q.get("id", ""))] = true
	var extra: Array = list.filter(func(e: Dictionary) -> bool: return not have.has(str(e.id))).slice(0, 20)
	(vid.queue as Array).append_array(extra)


## Gesehenes an YouTube melden (nur mit „youtube.tv_history“, Standard aus).
func mark_watched(video_id: String) -> bool:
	var r := await innertube("player", { "videoId": video_id })
	var url := P.tracking_url(r.data) if r.ok else ""
	if url == "" or not P.token_host_ok(url, Config.probe_env("UZAI_YT_TV_API")):
		return false
	url += ("&" if url.contains("?") else "?") + "ver=2&cpn=" + P.cpn(_rng)
	var tok := await _token()
	if tok == "":
		return false
	var res := await _http(url, PackedStringArray(["Authorization: Bearer " + tok]))
	return bool(res.ok)


func _now() -> int:
	return int(Time.get_unix_time_from_system())

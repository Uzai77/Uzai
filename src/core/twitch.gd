extends Node
## Twitch in Uzai (Bereich Streams): gefolgte Kanäle, die gerade live sind, beliebte Streams,
## Kategorien, Suche und Kanalseiten. Abgespielt wird wie YouTube über mpv und yt-dlp (Video) –
## Uzai bleibt vorn, nichts öffnet sich im Browser.
##
## Anmelden (auf Wunsch, inoffiziell): wie die Twitch-App auf dem Fernseher – Code auf
## twitch.tv/activate eingeben (QR-Code), Uzai wartet auf die Bestätigung. Dafür nimmt Uzai die
## öffentliche Kennung der Twitch-App für Android-TV (wie Twitch-Channel-Points-Miner und Xtra) und
## fragt Twitchs interne Schnittstelle (GQL) – ohne eigene Entwickler-App. Wer das nicht will,
## trägt eine eigene Client-ID ein (dev.twitch.tv, Typ „Öffentlich“): Dann läuft die Anmeldung
## offiziell, „Gefolgt“ kommt über die offizielle Schnittstelle (Helix).
## Ohne Anmeldung gehen beliebte Streams, Kategorien, Suche und Kanalseiten trotzdem (GQL ohne
## Anmeldung, wie streamlink und yt-dlp).
##
## Gespeichert wird nur die Anmeldung (accounts.twitch_*), nie ein Passwort; nichts davon kommt ins
## Protokoll. Welcher Weg klappte und welcher nicht, steht in logs/twitch.log.
## Meldungen über changed: "account", "followed", "top", "games", "resume" und "*_loading".

signal changed(what: String)
signal _token_ready

const P := preload("res://src/core/twitch_parse.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Fremd := preload("res://src/core/fremd.gd")
const ID := "https://id.twitch.tv"
const GQL := "https://gql.twitch.tv/gql"
const HELIX := "https://api.twitch.tv/helix"
const CACHE := "cache/twitch.json"
const EVERY := 120            ## Live-Listen höchstens alle 2 Minuten neu
const GAMES_EVERY := 1800
const SHOW_OLD := 12 * 3600   ## so alt darf der gemerkte Stand der Live-Listen beim Start sein

var demo := false
## Twitch-Konto: aus | bereit | abgelaufen | fehler (Tabelle gemeinsam mit YouTube und Epic in konten.gd).
var state := "aus":
	set(neu):
		Zustand.wechsel("konto.twitch", Konten.ZUSTAENDE_KONTO, state, neu)
		state = neu
var last_error := ""
var followed: Array = []      ## gefolgte Kanäle, die gerade live sind (Videos)
var followed_at := 0
var followed_loading := false
var followed_error := ""
var _followed_try := 0          ## letzter Abruf von Gefolgt (gegen Abfragen im Sekundentakt)
var _followed_way := ""         ## Weg, der zuletzt klappte (follows | miner | live)
var top: Array = []           ## beliebt in deiner Sprache
var top_all: Array = []       ## beliebt weltweit (ohne die aus top)
var top_at := 0
var top_loading := false
var top_error := ""
var games: Array = []         ## Kategorien, meiste Zuschauer zuerst
var games_at := 0
var games_loading := false
var resume := {}              ## Übertragung (tw:v:…) → { pos, dur, item, at }
var _access := ""
var _access_until := 0
var _refreshing := false
var _device_id := ""
var _gql_first := P.TV_CLIENT ## ohne Anmeldung: die Kennung, die zuletzt klappte, zuerst
var _logged := {}             ## Anfrage → zuletzt protokollierter Weg (nicht jede Wiederholung)
var _channels := {}           ## Kanal → { at, data } (nur in dieser Sitzung)
var _demo_on := true


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	var c: Variant = Config.read_json(Config.path(CACHE), {})
	if not (c is Dictionary):
		c = {}
	_device_id = str(c.get("device", ""))
	if _device_id.length() != 32:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_device_id = ""
		for i in 32:
			_device_id += "abcdefghijklmnopqrstuvwxyz0123456789"[rng.randi() % 36]
	resume = stellen_lesen(c.get("resume"))
	var vid := get_node_or_null("/root/Video")
	if vid:
		vid.stopped.connect(_on_video_stopped)
	if demo:
		_load_demo()
		return
	if logged_in():
		state = "bereit"
	elif account_name() != "":
		state = "abgelaufen"
	# Letzter Stand gleich zeigen, beim Öffnen kommt ohnehin der frische (Live-Listen bis SHOW_OLD,
	# Kategorien einen Tag). Früher galten Live-Listen nur 30 Minuten: nach jedem längeren Aus stand
	# Streams beim ersten Öffnen leer, bis Twitch geantwortet hatte.
	var now := _now()
	if now - Fremd.zahl(c.get("at")) < SHOW_OLD:
		top = Fremd.zeilen(c.get("top"))
		top_all = Fremd.zeilen(c.get("top_all"))
		if logged_in():
			followed = Fremd.zeilen(c.get("followed"))
	if now - Fremd.zahl(c.get("games_at")) < 86400:
		games = Fremd.zeilen(c.get("games"))


## Gemerkte Stellen aus der Zwischenspeicher-Datei: nur Einträge der erwarteten Form. Ein Eintrag anderer Art bräche
## continue_list und resume_pos ab, und „Weiterschauen“ bliebe leer.
static func stellen_lesen(v: Variant) -> Dictionary:
	var out := {}
	var d := Fremd.verz(v)
	for k in d:
		var e: Variant = d[k]
		if e is Dictionary and e.get("item") is Dictionary:
			out[str(k)] = { "pos": maxf(0.0, Fremd.komma(e.get("pos"))), "dur": maxf(0.0, Fremd.komma(e.get("dur"))),
				"at": Fremd.zahl(e.get("at")), "item": e.item }
	return out


## Adresse der Twitch-Dienste; UZAI_TWITCH_API lenkt alles (Anmeldung, GQL, Helix) für
## Netz-Proben auf einen nachgebauten Server um.
static func base() -> String:
	return Config.probe_env("UZAI_TWITCH_API").trim_suffix("/")


static func id_url(p: String) -> String:
	return (base() if base() != "" else ID) + p


static func gql_url() -> String:
	return base() + "/gql" if base() != "" else GQL


static func helix_url(p: String) -> String:
	return (base() + "/helix" if base() != "" else HELIX) + p


# --- Konto ---------------------------------------------------------------------------------------

func logged_in() -> bool:
	if demo:
		return _demo_on
	return str(Config.get_value("accounts.twitch_refresh", "")) != "" or str(Config.get_value("accounts.twitch_access", "")) != ""


func account_name() -> String:
	if demo:
		return "Demo-Konto" if _demo_on else ""
	return str(Config.get_value("accounts.twitch_name", ""))


func account_login() -> String:
	return str(Config.get_value("accounts.twitch_login", ""))


## Eigene Client-ID (dev.twitch.tv) – nur wenn eingetragen und gewählt.
func own_client() -> String:
	return str(Config.get_value("accounts.twitch_client_id", "")).strip_edges()


## Kennung für die nächste Anmeldung: eigene (offiziell) oder die der Twitch-App am Fernseher.
func login_client() -> String:
	if str(Config.get_value("accounts.twitch_mode", "")) == "eigen" and own_client() != "":
		return own_client()
	return P.TV_CLIENT


## Kennung, zu der die gespeicherte Anmeldung gehört (Twitch prüft, dass beide zusammenpassen).
func token_client() -> String:
	var c := str(Config.get_value("accounts.twitch_token_client", ""))
	return c if c != "" else P.TV_CLIENT


## Angemeldet mit eigener Client-ID: „Gefolgt“ über Helix (offiziell), sonst über GQL.
func helix_mode() -> bool:
	return logged_in() and not demo and token_client() != P.TV_CLIENT and token_client() != P.WEB_CLIENT


func status_text() -> String:
	match state:
		"bereit": return "Angemeldet: " + account_name() if account_name() != "" else "Angemeldet"
		"fehler": return "Gerade gestört"
		"abgelaufen": return "Abgelaufen – neu anmelden"
	return "Nicht angemeldet"


## Beim Start von Uzai (main): Gefolgte und Beliebte holen.
func start() -> void:
	if demo:
		return
	if logged_in():
		refresh_followed()


func _emit(what: String) -> void:
	changed.emit(what)


## Protokoll ohne Anmeldedaten (logs/twitch.log): welcher Weg klappte, welcher nicht.
func _log(text: String) -> void:
	if demo:
		return
	Media.log_line("twitch", text)


## Einen Weg nur protokollieren, wenn er sich ändert (sonst stünde jede Aktualisierung da).
func _log_path(what: String, how: String) -> void:
	if str(_logged.get(what, "")) == how:
		return
	_logged[what] = how
	_log("%s: %s" % [what, how])


static func client_tag(c: String) -> String:
	match c:
		P.TV_CLIENT: return "TV-Kennung"
		P.WEB_CLIENT: return "Web-Kennung"
	return "eigener Client-ID"


# --- Netz ----------------------------------------------------------------------------------------

## { ok, code, data, text } – eigene Anfrage, damit die Kopfzeilen (Twitch-App am Fernseher) stimmen.
func _http(url: String, headers: PackedStringArray, method := HTTPClient.METHOD_GET, body := "", timeout := 15.0) -> Dictionary:
	var h := headers.duplicate()
	h.append("User-Agent: " + P.UA)
	var r := await Net.request(url, h, method, body, timeout)
	var out := { "ok": false, "code": 0, "data": null, "text": "" }
	if int(r.result) == HTTPRequest.RESULT_SUCCESS:
		out.code = int(r.code)
		out.text = (r.body as PackedByteArray).get_string_from_utf8()
		out.data = Fremd.json(out.text)
		out.ok = int(out.code) >= 200 and int(out.code) < 300
	return out


func _form(url: String, fields: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for k in fields.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(fields[k]).uri_encode()])
	return await _http(url, PackedStringArray(["Content-Type: application/x-www-form-urlencoded", "Accept: application/json"]), HTTPClient.METHOD_POST,
			"&".join(parts))


## GQL-Anfrage. auth: mit der Anmeldung (dann mit deren Kennung), sonst ohne – erst mit der
## Kennung, die zuletzt klappte, dann mit der anderen. { ok, code, data, error, client }
func gql(query: String, vars: Dictionary, auth: bool, what: String, raw: Dictionary = {}) -> Dictionary:
	var body := JSON.stringify(raw if not raw.is_empty() else P.gql_body(query, vars))
	var tok := ""
	var clients: Array = []
	if auth:
		tok = await _token()
		if tok == "":
			return { "ok": false, "code": 401, "data": null, "error": "keine Anmeldung", "client": "" }
		clients = [token_client()]
	else:
		clients = [_gql_first, P.WEB_CLIENT if _gql_first == P.TV_CLIENT else P.TV_CLIENT]
	var last := { "ok": false, "code": 0, "data": null, "error": "", "client": "" }
	for c in clients:
		for attempt in 2:
			var h := PackedStringArray(["Client-Id: " + str(c), "X-Device-Id: " + _device_id, "Content-Type: application/json", "Accept: application/json"])
			if auth:
				h.append("Authorization: OAuth " + tok)
			var r := await _http(gql_url(), h, HTTPClient.METHOD_POST, body, 20.0)
			var data := P.gql_data(r.data)
			var err := P.gql_error(r.data)
			if r.ok and not data.is_empty() and not data.values().all(func(x: Variant) -> bool: return x == null):
				if not auth:
					_gql_first = str(c)
				_log_path(what,
						"GQL mit %s%s – klappt%s" % [client_tag(str(c)), " und Anmeldung" if auth else "", (" (Teilfehler: %s)" % err.left(100)) if err != "" else ""])
				return { "ok": true, "code": int(r.code), "data": r.data, "error": err, "client": str(c) }
			last = { "ok": false, "code": int(r.code), "data": r.data, "error": err, "client": str(c) }
			if auth and int(r.code) == 401 and attempt == 0:
				# Zugang abgelaufen (etwa nach dem Ruhezustand): einmal erneuern und nochmal.
				tok = await _token(true)
				if tok == "":
					break
				continue
			break
		_log_path(what,
				"GQL mit %s%s – Fehler %d%s" % [client_tag(str(c)), " und Anmeldung" if auth else "", int(last.code), (": " + str(last.error).left(140))
				if str(last.error) != "" else ""])
	return last


## Helix (offiziell) mit eigener Client-ID und Anmeldung. { ok, code, data }
## any_client: auch mit der Kennung der Twitch-App versuchen (Rückfall, wenn GQL nicht geht) –
## dann ohne Erneuern bei 401 (das hieße dort nur: Helix nimmt diese Kennung nicht).
func helix(p: String, what: String, any_client := false) -> Dictionary:
	var tok := await _token()
	if tok == "" or not (helix_mode() or any_client):
		return { "ok": false, "code": 401, "data": null }
	var r := {}
	for attempt in 2:
		r = await _http(helix_url(p), PackedStringArray(["Client-Id: " + token_client(), "Authorization: Bearer " + tok, "Accept: application/json"]))
		if int(r.code) != 401 or attempt == 1 or any_client:
			break
		tok = await _token(true)
		if tok == "":
			break
	_log_path(what, "Helix mit %s – " % client_tag(token_client()) + ("klappt" if r.ok else "Fehler %d" % int(r.code)))
	return r


# --- Anmelden, erneuern, abmelden -----------------------------------------------------------------

## { ok, device_code, user_code, url, short, interval, expires } oder { ok: false, error }
func login_start() -> Dictionary:
	if demo:
		return { "ok": true, "device_code": "demo", "user_code": "ABCDEFGH", "url": P.ACTIVATE_URL + "?device-code=ABCDEFGH", "short": "twitch.tv/activate",
				"interval": 5, "expires": 1800 }
	var c := login_client()
	var r := await _form(id_url("/oauth2/device"), P.device_request(c))
	var out := P.parse_device_code(int(r.code), r.data)
	_log("Anmeldung: Code angefordert mit %s – %s" % [client_tag(c), "klappt" if bool(out.ok) else "Fehler %d %s" % [int(r.code), P._err_word(r.data)]])
	if bool(out.ok):
		out["client"] = c
	return out


## Einmal nachfragen, ob der Code bestätigt ist: "pending", "slow", "ok", "denied", "expired",
## "error" (dann steht der Grund in last_error).
func login_poll(device_code: String, client := "") -> String:
	var c := client if client != "" else login_client()
	var r := await _form(id_url("/oauth2/token"), P.poll_request(c, device_code))
	var t := P.parse_token(int(r.code), r.data, _now())
	if not bool(t.ok):
		last_error = str(t.error)
		if not (str(t.state) in ["pending", "slow"]):
			_log("Anmeldung: Abfrage – %s (%d)" % [str(t.state), int(r.code)])
		return "expired" if str(t.state) == "revoked" else str(t.state)
	_access = str(t.access)
	_access_until = int(t.expires_at)
	Config.set_value("accounts.twitch_token_client", c)
	_store(str(t.refresh), _access)
	var v := await _validate(_access)
	if bool(v.ok) and int(v.expires_in) > 0:
		_access_until = _now() + int(v.expires_in)
		Config.set_value("accounts.twitch_access_until", _access_until)
	Config.set_value("accounts.twitch_login", str(v.get("login", "")))
	Config.set_value("accounts.twitch_user_id", str(v.get("user_id", "")))
	var who := await _fetch_name()
	Config.set_value("accounts.twitch_name", who if who != "" else (str(v.get("login", "")) if str(v.get("login", "")) != "" else "Twitch-Konto"))
	state = "bereit"
	last_error = ""
	_log(
			"Anmeldung: angemeldet mit %s (%s, %s)" % [client_tag(c), "mit Erneuerung" if str(t.refresh) != "" else "ohne Erneuerung", "geprüft" if bool(v.ok)
			else "nicht geprüft"])
	_emit("account")
	_followed_try = 0
	refresh_followed(true)
	return "ok"


## Erneuerung und Zugang speichern. Der Zugang bleibt auch mit Erneuerung gespeichert: Mit der
## Kennung der Twitch-App lehnt Twitch das Erneuern teils ab, der Zugang selbst gilt aber lange.
func _store(refresh: String, access: String) -> void:
	Config.set_value("accounts.twitch_refresh", refresh)
	Config.set_value("accounts.twitch_access", access)
	Config.set_value("accounts.twitch_access_until", _access_until)


## /oauth2/validate: Konto und Kennung zum Zugang (Twitch verlangt das regelmäßig).
func _validate(tok: String) -> Dictionary:
	var r := await _http(id_url("/oauth2/validate"), PackedStringArray(["Authorization: OAuth " + tok]))
	var v := P.parse_validate(int(r.code), r.data)
	if bool(v.ok) and str(v.client_id) != "" and str(v.client_id) != token_client():
		_log("Anmeldung: Zugang gehört zu einer anderen Kennung (%s)" % client_tag(str(v.client_id)))
	return v


func _fetch_name() -> String:
	if helix_mode():
		var r := await helix("/users", "Konto")
		return str(P.parse_helix_user(r.data).get("name", "")) if r.ok else ""
	var g := await gql(P.Q_ME, {}, true, "Konto")
	var d := P.gql_data(g.data)
	return str(P.user_brief(d.get("currentUser") if d.get("currentUser") is Dictionary else d.get("user")).get("name", "")) if g.ok else ""


## Abmelden: Twitch bekommt Bescheid (falls erreichbar), Uzai vergisst Anmeldung und Gefolgtes.
func logout() -> void:
	var tok := _access if _access != "" else str(Config.get_value("accounts.twitch_access", ""))
	var c := token_client()
	for k in ["twitch_refresh", "twitch_access", "twitch_access_until", "twitch_name", "twitch_login", "twitch_user_id", "twitch_token_client"]:
		Config.set_value("accounts." + k, "")
	_access = ""
	_access_until = 0
	followed = []
	followed_at = 0
	followed_error = ""
	state = "aus"
	last_error = ""
	_log("abgemeldet")
	_emit("account")
	_emit("followed")
	if tok != "" and not demo:
		_form(id_url("/oauth2/revoke"), { "client_id": c, "token": tok })


## Gültige Zugangs-Anmeldung, bei Bedarf erneuert ("" wenn das nicht ging). force: neu holen
## (nach 401).
func _token(force := false) -> String:
	if demo:
		return ""
	# Die Kennung der Twitch-App kann nicht erneuern (Twitch: „missing client secret“): Ihr Zugang
	# gilt, bis Twitch ihn ablehnt – die Ablaufzeit ist dort nur ein Richtwert. Erst bei 401 (force)
	# wird geprüft und ggf. neu angemeldet.
	var no_refresh := token_client() == P.TV_CLIENT or token_client() == P.WEB_CLIENT
	if not force and _access != "" and (_access_until == 0 or _access_until - 60 > _now() or no_refresh):
		return _access
	# Nach dem Neustart: gespeicherten Zugang nehmen, solange er gilt.
	var saved := str(Config.get_value("accounts.twitch_access", ""))
	var saved_until := int(Config.get_value("accounts.twitch_access_until", 0))
	if not force and _access == "" and saved != "" and (saved_until == 0 or saved_until - 60 > _now() or no_refresh):
		_access = saved
		_access_until = saved_until
		return _access
	if no_refresh and force and saved != "":
		var vv := await _validate(saved)
		if bool(vv.ok):
			# Twitch kennt den Zugang noch: die 401 kam von etwas anderem (nicht neu anmelden).
			_access = saved
			return _access
		_expire("Zugang abgelaufen (die Twitch-App-Kennung kann nicht erneuern) – einmal neu per QR anmelden")
		return ""
	var rt := str(Config.get_value("accounts.twitch_refresh", ""))
	if rt == "":
		var keep := str(Config.get_value("accounts.twitch_access", ""))
		if keep != "" and not force:
			_access = keep
			_access_until = 0
			return _access
		if keep != "" and force:
			# Ein Zugang ohne Erneuerung wurde abgelehnt: neu anmelden.
			_expire("Zugang ohne Erneuerung abgelehnt")
		return ""
	if _refreshing:
		await _token_ready
		return _access
	_refreshing = true
	# Das Erneuern läuft in einer eigenen Funktion: Bricht es mit einem Fehler ab, wird hier trotzdem gelöst und
	# gemeldet. Sonst warteten alle späteren Abrufe für immer auf _token_ready.
	await _erneuern(rt, saved)
	_refreshing = false
	_token_ready.emit()
	return _access


## Holt mit dem Erneuerungsschlüssel einen neuen Zugang (nur aus _token, siehe dort).
func _erneuern(rt: String, saved: String) -> void:
	var r := await _form(id_url("/oauth2/token"), P.refresh_request(token_client(), rt))
	var t := P.parse_token(int(r.code), r.data, _now())
	if bool(t.ok):
		_access = str(t.access)
		_access_until = int(t.expires_at)
		if str(t.refresh) != "" and str(t.refresh) != rt:
			Config.set_value("accounts.twitch_refresh", str(t.refresh))
		Config.set_value("accounts.twitch_access", _access)
		Config.set_value("accounts.twitch_access_until", _access_until)
		_log_path("Erneuern", "klappt mit " + client_tag(token_client()))
		if state != "bereit":
			state = "bereit"
			_emit("account")
	else:
		_access = ""
		last_error = str(t.error)
		_log_path("Erneuern", "Fehler %d %s" % [int(r.code), P._err_word(r.data)])
		# Erneuern abgelehnt: Gilt der gespeicherte Zugang laut Twitch noch, damit weitermachen.
		var v := { "ok": false, "expires_in": 0 }
		if saved != "":
			v = await _validate(saved)
		if bool(v.ok):
			_access = saved
			_access_until = _now() + int(v.expires_in) if int(v.expires_in) > 0 else 0
			Config.set_value("accounts.twitch_access_until", _access_until)
			_log("Anmeldung: Erneuern abgelehnt, gespeicherter Zugang gilt noch")
			if state != "bereit":
				state = "bereit"
				_emit("account")
		elif str(t.state) == "revoked" or (saved != "" and str(t.state) == "error" and int(r.code) >= 400 and int(r.code) < 500):
			_expire("Erneuern abgelehnt (%d)" % int(r.code))
		else:
			state = "fehler"
			_log_path("Erneuern", "Fehler %d" % int(r.code))


## Abgelaufen oder widerrufen: neu anmelden; der Name bleibt für den Hinweis.
func _expire(why: String) -> void:
	Config.set_value("accounts.twitch_refresh", "")
	Config.set_value("accounts.twitch_access", "")
	Config.set_value("accounts.twitch_access_until", 0)
	_access = ""
	followed = []
	state = "abgelaufen"
	_log("Anmeldung abgelaufen: " + why)
	_emit("account")


# --- Listen --------------------------------------------------------------------------------------

## Sprache der Reihe „Beliebt auf …“ (GQL: DE, Helix: de).
func lang() -> String:
	return str(Config.get_value("twitch.lang", "DE")).to_upper()


static func lang_name(code: String) -> String:
	match code.to_upper():
		"DE": return "Deutsch"
		"EN": return "Englisch"
		"FR": return "Französisch"
		"ES": return "Spanisch"
		"IT": return "Italienisch"
	return code


## Läufe von refresh_followed, die gerade unterwegs sind (siehe dort).
var _refresh_followed_offen := 0


## Gefolgte Kanäle, die gerade live sind (höchstens alle EVERY Sekunden, force: sofort).
func refresh_followed(force := false) -> void:
	_refresh_followed_offen += 1
	await _refresh_followed_lauf(force)
	_refresh_followed_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_followed täte bis zum Neustart nichts mehr.
	if _refresh_followed_offen == 0 and followed_loading:
		followed_loading = false


func _refresh_followed_lauf(force := false) -> void:
	if demo or followed_loading or not logged_in():
		return
	var now := _now()
	if not force and now - followed_at < EVERY and followed_error == "":
		return
	# Auch auf Wunsch nicht öfter als alle 5 s, nach einem Fehler höchstens alle 30 s (das Protokoll
	# zeigte sonst Abfragen im Sekundentakt).
	if now - _followed_try < (30 if followed_error != "" else 5):
		return
	_followed_try = now
	followed_loading = true
	_emit("followed_loading")
	var items: Array = []
	var ok := false
	var code := 0
	if helix_mode():
		var uid := str(Config.get_value("accounts.twitch_user_id", ""))
		var r := await helix("/streams/followed?first=100&user_id=" + uid.uri_encode(), "Gefolgt")
		ok = r.ok
		code = int(r.code)
		items = P.parse_helix_streams(r.data, now) if ok else []
	else:
		# Mehrere Wege; der zuletzt erfolgreiche zuerst (Twitch: followedLiveUsers gibt mit der
		# Anmeldung der Twitch-App nur „service error“).
		var g := { "ok": false, "code": 0, "data": null }
		var p := { "ok": false }
		var ways: Array = ["follows", "miner", "live"]
		if _followed_way in ways:
			ways.erase(_followed_way)
			ways.push_front(_followed_way)
		for w in ways:
			var res: Dictionary = await _followed_via(str(w), now)
			g = res.g
			p = res.p
			if bool(p.ok):
				if _followed_way != str(w):
					_log("Gefolgt: Weg „%s“ klappt" % str(w))
				_followed_way = str(w)
				break
			if int(g.code) == 401:
				break
		ok = bool(p.ok)
		code = int(g.code)
		if ok:
			items = p.items
			var me: Dictionary = p.me
			if str(me.get("name", "")) != "" and str(me.name) != account_name():
				Config.set_value("accounts.twitch_name", str(me.name))
		elif code != 401 and logged_in() and str(Config.get_value("accounts.twitch_user_id", "")) != "":
			# GQL geht gerade nicht (Twitch verlangt z. B. eine Integritätsprüfung): Helix mit
			# derselben Anmeldung versuchen. Ob Twitch das zulässt, steht danach im Protokoll.
			var hx := await helix("/streams/followed?first=100&user_id=" + str(Config.get_value("accounts.twitch_user_id", "")).uri_encode(), "Gefolgt (Helix-Rückfall)",
					true)
			if hx.ok:
				ok = true
				items = P.parse_helix_streams(hx.data, now)
	followed_loading = false
	if not logged_in():
		_emit("followed")
		return
	if ok:
		followed = items
		followed_at = now
		followed_error = ""
		_save()
	else:
		followed_error = P.explain(code)
		if now - followed_at > 1800:
			followed = []
	_emit("followed")


## Ein Weg zu den gefolgten Kanälen, die live sind: { g (letzte Antwort), p ({ ok, items, me }) }.
func _followed_via(way: String, now: int) -> Dictionary:
	var g := {}
	match way:
		"follows":
			var live: Array = []
			var after: Variant = null
			var me := {}
			for page in 6:
				g = await gql(P.Q_FOLLOWS, { "first": 100, "after": after }, true, "Gefolgt (follows)")
				var f := P.parse_follows(g.data, now) if g.ok else { "ok": false }
				if not bool(f.ok):
					if g.ok:
						_log_path("Gefolgt (follows)", "Liste fehlt%s" % ((": " + str(g.error).left(160)) if str(g.error) != "" else ""))
					return { "g": g, "p": { "ok": false } }
				live.append_array(f.items)
				me = f.me
				if not bool(f.more):
					break
				after = str(f.after)
			return { "g": g, "p": { "ok": true, "items": P.sort_live(live), "me": me } }
		"miner":
			var logins: Array = []
			var cursor := ""
			for page in 6:
				var vars := { "limit": 100, "order": "ASC" }
				if cursor != "":
					vars["cursor"] = cursor
				g = await gql("", vars, true, "Gefolgt (ChannelFollows)", P.persisted_body(P.PQ_FOLLOWS, P.PQ_FOLLOWS_HASH, vars))
				var f := P.parse_follows(g.data, now) if g.ok else { "ok": false }
				if not bool(f.ok):
					if g.ok:
						_log_path("Gefolgt (ChannelFollows)", "Liste fehlt%s" % ((": " + str(g.error).left(160)) if str(g.error) != "" else ""))
					return { "g": g, "p": { "ok": false } }
				logins.append_array(f.logins)
				if not bool(f.more):
					break
				cursor = str(f.after)
			var live: Array = []
			for i in range(0, logins.size(), 100):
				var u := await gql(P.Q_USERS_LIVE, { "logins": logins.slice(i, i + 100) }, false, "Gefolgt (Live-Stand)")
				var pu := P.parse_users_live(u.data, now) if u.ok else { "ok": false }
				if not bool(pu.ok):
					return { "g": u, "p": { "ok": false } }
				live.append_array(pu.items)
			return { "g": g, "p": { "ok": true, "items": P.sort_live(live), "me": {} } }
	# "live": followedLiveUsers (30 voll, dann schlank).
	for v in [[P.Q_FOLLOWED, "Gefolgt"], [P.Q_FOLLOWED_LEAN, "Gefolgt (schlank)"]]:
		g = await gql(str(v[0]), { "first": 30 }, true, str(v[1]))
		var pf := P.parse_followed(g.data, now) if g.ok else { "ok": false }
		if bool(pf.ok) or int(g.code) == 401:
			return { "g": g, "p": pf }
		if g.ok:
			_log_path(str(v[1]), "Liste fehlt%s" % ((": " + str(g.error).left(160)) if str(g.error) != "" else ""))
	return { "g": g, "p": { "ok": false } }


## Läufe von refresh_top, die gerade unterwegs sind (siehe dort).
var _refresh_top_offen := 0


## Beliebte Streams: in deiner Sprache und weltweit.
func refresh_top(force := false) -> void:
	_refresh_top_offen += 1
	await _refresh_top_lauf(force)
	_refresh_top_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_top täte bis zum Neustart nichts mehr.
	if _refresh_top_offen == 0 and top_loading:
		top_loading = false


func _refresh_top_lauf(force := false) -> void:
	if demo or top_loading:
		return
	var now := _now()
	if not force and now - top_at < EVERY and not top.is_empty():
		return
	top_loading = true
	_emit("top_loading")
	var mine: Array = []
	var all: Array = []
	var t0 := Time.get_ticks_msec()
	# Nacheinander mit Absicht: Die erste Antwort zeigt, welche Kennung (TV oder Web) gerade geht,
	# die zweite nimmt dann gleich die richtige. Bis dahin steht der gemerkte Stand (SHOW_OLD).
	var g := await gql(P.Q_TOP_LANG, { "first": 30, "langs": [lang()] }, false, "Beliebt (%s)" % lang())
	if g.ok:
		mine = P.parse_streams(P.gql_data(g.data).get("streams"), now)
	var g2 := await gql(P.Q_TOP, { "first": 30 }, false, "Beliebt (weltweit)")
	if g2.ok:
		all = P.parse_streams(P.gql_data(g2.data).get("streams"), now)
	if not g.ok and not g2.ok and helix_mode():
		var h := await helix("/streams?first=30&language=" + lang().to_lower(), "Beliebt (Helix)")
		mine = P.parse_helix_streams(h.data, now) if h.ok else []
		var h2 := await helix("/streams?first=40", "Beliebt weltweit (Helix)")
		all = P.parse_helix_streams(h2.data, now) if h2.ok else []
	top_loading = false
	if not demo:
		Media.log_line("leistung", "Streams: Beliebt in %d ms" % (Time.get_ticks_msec() - t0))
	if mine.is_empty() and all.is_empty():
		top_error = P.explain(int(g2.code), str(g2.error))
	else:
		var have := {}
		for it in mine:
			have[str(it.id)] = true
		top = mine
		top_all = all.filter(func(it: Dictionary) -> bool: return not have.has(str(it.id)))
		top_at = now
		top_error = ""
		_save()
	_emit("top")


## Läufe von refresh_games, die gerade unterwegs sind (siehe dort).
var _refresh_games_offen := 0


## Kategorien mit den meisten Zuschauern.
func refresh_games(force := false) -> void:
	_refresh_games_offen += 1
	await _refresh_games_lauf(force)
	_refresh_games_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_games täte bis zum Neustart nichts mehr.
	if _refresh_games_offen == 0 and games_loading:
		games_loading = false


func _refresh_games_lauf(force := false) -> void:
	if demo or games_loading:
		return
	var now := _now()
	if not force and now - games_at < GAMES_EVERY and not games.is_empty():
		return
	games_loading = true
	_emit("games_loading")
	var g := await gql(P.Q_GAMES, { "first": 40 }, false, "Kategorien")
	var list: Array = P.parse_games(P.gql_data(g.data).get("games")) if g.ok else []
	if list.is_empty() and helix_mode():
		var h := await helix("/games/top?first=40", "Kategorien (Helix)")
		list = P.parse_helix_games(h.data) if h.ok else []
	games_loading = false
	if not list.is_empty():
		games = list
		games_at = now
		_save()
	_emit("games")


## Streams einer Kategorie: { game, items }.
func game_streams(game: Dictionary) -> Dictionary:
	if demo:
		return { "game": game, "items": _demo_streams(12, str(game.get("title", ""))) }
	var vars := { "first": 40 }
	if str(game.get("slug", "")) != "":
		vars["slug"] = str(game.slug)
	else:
		vars["id"] = str(game.get("game_id", ""))
	var g := await gql(P.Q_GAME, vars, false, "Kategorie")
	var p := P.parse_game(g.data, _now()) if g.ok else { "game": {}, "items": [] }
	if (p.items as Array).is_empty() and helix_mode() and str(game.get("game_id", "")) != "":
		var h := await helix("/streams?first=40&game_id=" + str(game.game_id).uri_encode(), "Kategorie (Helix)")
		p = { "game": {}, "items": P.parse_helix_streams(h.data, _now()) if h.ok else [] }
	if (p.game as Dictionary).is_empty():
		p.game = game
	return p


## Suche: { channels, games, streams, error }.
func search(q: String) -> Dictionary:
	if demo:
		return { "channels": _demo_channels(), "games": _demo_games().slice(0, 4), "streams": _demo_streams(4, ""), "error": "" }
	var g := await gql(P.Q_SEARCH, { "q": q, "first": 12 }, false, "Suche")
	var p := P.parse_search(g.data, _now()) if g.ok else { "channels": [], "games": [], "streams": [] }
	if (p.channels as Array).is_empty() and (p.games as Array).is_empty() and helix_mode():
		var h := await helix("/search/channels?first=12&query=" + q.uri_encode(), "Suche (Helix)")
		var h2 := await helix("/search/categories?first=12&query=" + q.uri_encode(), "Suche Kategorien (Helix)")
		p = { "channels": P.parse_helix_channels(h.data) if h.ok else [], "games": P.parse_helix_games(h2.data) if h2.ok else [], "streams": [] }
	p["error"] = "" if g.ok else P.explain(int(g.code), str(g.error))
	return p


## Kanalseite (höchstens alle 2 Minuten neu): { ok, user, live, videos, clips, error }.
func channel(login: String) -> Dictionary:
	login = login.to_lower()
	if demo:
		return _demo_channel(login)
	var c: Variant = _channels.get(login)
	if c is Dictionary and _now() - int(c.at) < EVERY:
		return c.data
	var g := await gql(P.Q_CHANNEL, { "login": login }, false, "Kanalseite")
	var p := P.parse_channel(g.data, _now()) if g.ok else { "ok": false, "user": {}, "live": {}, "videos": [], "clips": [] }
	p["error"] = "" if bool(p.ok) else P.explain(int(g.code), str(g.error))
	if bool(p.ok):
		_channels[login] = { "at": _now(), "data": p }
		while _channels.size() > 20:
			_channels.erase(_channels.keys()[0])
	return p


# --- Weiterschauen (Übertragungen) ---------------------------------------------------------------

## Stelle einer Übertragung, an der man aufgehört hat (0: von vorn).
func resume_pos(id: String) -> float:
	var r: Variant = resume.get(id)
	return float(r.pos) if r is Dictionary else 0.0


## Angefangene Übertragungen, zuletzt gesehen zuerst.
func continue_list() -> Array:
	var keys: Array = resume.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(resume[a].get("at", 0)) > int(resume[b].get("at", 0)))
	var out: Array = []
	for k in keys.slice(0, 20):
		var it: Variant = resume[k].get("item")
		if it is Dictionary:
			out.append(it)
	return out


## Fortschritt 0…1 (für den Balken auf der Karte).
func progress_of(id: String) -> float:
	var r: Variant = resume.get(id)
	if not (r is Dictionary) or float(r.get("dur", 0)) <= 0:
		return 0.0
	return clampf(float(r.pos) / float(r.dur), 0.0, 1.0)


func _on_video_stopped() -> void:
	var v: Dictionary = Video.video
	var tw: Variant = v.get("twitch")
	if not (tw is Dictionary) or str(tw.get("kind", "")) != "vod":
		return
	var id := str(v.get("id", ""))
	var pos := float(Video.pos)
	var dur := float(Video.duration)
	if pos > 30.0 and (dur <= 0.0 or pos < dur - 60.0):
		resume[id] = { "pos": pos, "dur": dur, "at": _now(), "item": v.duplicate(true) }
	else:
		resume.erase(id)
	while resume.size() > 40:
		resume.erase(_oldest_resume())
	_save()
	_emit("resume")


func _oldest_resume() -> String:
	var oldest := ""
	var at := 1 << 62
	for k in resume.keys():
		if int(resume[k].get("at", 0)) < at:
			at = int(resume[k].get("at", 0))
			oldest = str(k)
	return oldest


func forget_resume(id: String) -> void:
	resume.erase(id)
	_save()
	_emit("resume")


func _save() -> void:
	if demo:
		return
	Config.write_json(Config.path(CACHE), {
		"device": _device_id, "resume": resume, "at": top_at, "top": top, "top_all": top_all,
		"followed": followed, "games_at": games_at, "games": games,
	})


func _now() -> int:
	return int(Time.get_unix_time_from_system())


# --- Demo (--demo, Rundgang und Proben) ----------------------------------------------------------

const _DEMO_CH := [["Pixelbude", "Retro-Sonntag: alle Zelda-Teile am Stück"], ["NordlichtTV", "Ranked bis Diamant – heute klappt’s"],
	["Kaffeekasse", "Just Chatting & Frühstück"], ["Speedwurm", "Any% Weltrekordversuche"], ["Bergfunk", "Gemütlich bauen mit Zuschauern"],
	["Lofi Lounge", "Musik zum Arbeiten und Lernen"], ["Taktikbrett", "Turnier-Analyse live"], ["Hafenkran", "Erstes Durchspielen, keine Spoiler"]]
const _DEMO_GAMES := ["Just Chatting", "The Legend of Zelda", "Counter-Strike", "Minecraft", "Music", "League of Legends", "Elden Ring", "Retro"]


func _load_demo() -> void:
	state = "bereit"
	var now := _now()
	followed = _demo_streams(5, "")
	top = _demo_streams(8, "", 3)
	top_all = _demo_streams(8, "", 1)
	games = _demo_games()
	followed_at = now
	top_at = now
	games_at = now


func _demo_streams(n: int, game: String, shift := 0) -> Array:
	var out: Array = []
	var now := _now()
	for i in n:
		var ch: Array = _DEMO_CH[(i + shift) % _DEMO_CH.size()]
		var g := game if game != "" else str(_DEMO_GAMES[(i + shift) % _DEMO_GAMES.size()])
		var login := str(ch[0]).to_lower().replace(" ", "_")
		var it := P.stream_item(
				{ "id": str(i), "title": ch[1], "viewersCount": floori(18400.0 / (i + 1 + shift)) + 37 * i, "game": { "id": str(i), "displayName": g },
			"createdAt": Time.get_datetime_string_from_unix_time(now - 3600 * (i + 1) - 900), "broadcaster": { "login": login, "displayName": ch[0] } }, {}, now)
		it.thumb = ""
		out.append(it)
	return out


func _demo_games() -> Array:
	var out: Array = []
	for i in _DEMO_GAMES.size():
		out.append({ "id": "tw:g:%d" % i, "game_id": str(i), "slug": "", "title": _DEMO_GAMES[i], "channel": _DEMO_GAMES[i], "thumb": "",
			"viewers": floori(240000.0 / (i + 1)), "channels": floori(4200.0 / (i + 1)) })
	return out


func _demo_channels() -> Array:
	var out: Array = []
	for i in 5:
		var ch: Array = _DEMO_CH[i]
		out.append(
				{ "id": str(ch[0]).to_lower(), "login": str(ch[0]).to_lower(), "title": ch[0], "thumb": "", "live": i < 2, "viewers": 0, "followers": 1000 * (i + 3) })
	return out


func _demo_channel(login: String) -> Dictionary:
	var ch_name := login.capitalize()
	for ch in _DEMO_CH:
		if str(ch[0]).to_lower().replace(" ", "_") == login:
			ch_name = str(ch[0])
	var me := { "id": "1", "login": login, "name": ch_name, "avatar": "", "banner": "", "about": "Retro, Speedruns und gemütliche Abende – jeden Sonntag live.",
			"followers": 48200 }
	var live := _demo_streams(1, "Retro")[0] as Dictionary
	live.channel = ch_name
	live.twitch.name = ch_name
	live.twitch.login = login
	var vids: Array = []
	var clips: Array = []
	var now := _now()
	for i in 6:
		vids.append(
				{ "id": "tw:v:%d" % (100 + i), "url": P.WEB + "/videos/%d" % (100 + i), "title": "Übertragung vom %d. Oktober" % (16 - i), "channel": ch_name, "thumb": "",
			"duration": 7200 + 900 * i, "published": now - 86400 * (i + 1), "views": 3200 - 300 * i,
				"twitch": { "kind": "vod", "login": login, "name": ch_name, "game": "Retro", "avatar": "" } })
		clips.append(
				{ "id": "tw:c:clip%d" % i, "url": "https://clips.twitch.tv/clip%d" % i, "title": "Unglaublicher Sprung #%d" % (i + 1), "channel": ch_name, "thumb": "",
			"duration": 22 + 4 * i, "published": now - 3600 * (i + 5), "views": 9000 - 1000 * i,
				"twitch": { "kind": "clip", "login": login, "name": ch_name, "game": "Retro", "avatar": "" } })
	return { "ok": true, "user": me, "live": live, "videos": vids, "clips": clips, "error": "" }

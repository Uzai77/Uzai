extends "res://src/core/music_daten.gd"
## Musik, Schicht über music_daten.gd: der Weg zu Spotify. Zwei Anmeldungen:
##   "app"   „Mit Spotify anmelden“ (Standard, ohne Einrichtung): einmal die echte Anmeldeseite im Uzai-Browser,
##           danach holt die Spotify-Sitzung (spotify_web.gd) den Schlüssel aus den Anfragen des Webplayers im
##           Browser-Kern. Alle Abrufe dieser Anmeldung (pathfinder, spclient, Web-API) laufen IN der unsichtbaren,
##           angemeldeten Seite (_netz → spotify_web.gd abfrage) – für Spotify wie vom Webplayer; nichts wird
##           nachgerechnet. Geht das nicht, Grundmodus (siehe grundmodus()).
##   "eigen" eigene Client-ID (Web-API, im Browser am PC bestätigt) – der zweite Weg für alle, die eine eigene
##           Spotify-App haben.
## Dazu Anfragen an die Web-API und an die internen Wege mit Kontingent und Bremse, Fehlerbilder („problem“) und
## Spotify Connect (Dealer-Websocket und connect-state).
## Die Signale und der gemeinsame Zustand des Autoloads Music stehen hier, weil schon diese
## Schicht sie braucht.

signal updated
signal lists_changed(what: String)     ## queue, liked, recent, playlists, fuerdich

const API := "https://api.spotify.com/v1"
const ACCOUNTS := "https://accounts.spotify.com"
const SCOPES := "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read user-library-modify user-read-recently-played user-top-read user-follow-read"
## Diese Freigaben fehlen Anmeldungen aus Uzai 0.6 und älter: ohne sie keine Top-Titel und Künstler.
const FOR_YOU_SCOPES := ["user-top-read", "user-follow-read"]
const SEARCH_LIMIT := 10          ## Höchstwert für eigene Apps seit 2026
const APP_SEARCH_LIMIT := 20
const SPCLIENT := "https://spclient.wg.spotify.com"    ## interne Schnittstelle der Spotify-Apps
## Dieselben Wege wie der Webplayer: api-partner (pathfinder, GraphQL) für Bibliothek, Suche und die Startseite
## „Für dich“ (deine echten Mixe), dazu der Client-Token, den die Seite selbst mitschickt.
const PARTNER := "https://api-partner.spotify.com/pathfinder/v2/query"
const SPOTIFY_CLIENT_VERSION := "1.2.63.394"    ## nur, wenn die Seite keine Fassung mitschickt
## Obergrenze je 30 s für die eigene App (Spotify misst in einem gleitenden 30-s-Fenster; zu viel
## führt zu 429 und im schlimmsten Fall zu „QUOTA_EXCEEDED“ für 24 Stunden). Steuern hat Vorrang.
const BUDGET_WINDOW_MS := 30000
const BUDGET_READ := 24
const BUDGET_ALL := 36

const Logdatei := preload("res://src/core/logdatei.gd")
const Intern := preload("res://src/core/spotify_intern.gd")
const Web := preload("res://src/core/spotify_web.gd")
const BP := preload("res://src/core/browser_protokoll.gd")
const Zustand := preload("res://src/core/zustand.gd")   ## Zustandsautomaten (auch für die Schichten darüber)
const Fremd := preload("res://src/core/fremd.gd")
## Spotify Connect wie die Spotify-Apps: Dealer-Websocket (liefert die Connection-Id und meldet
## Änderungen), Zustand und Befehle über spclient/connect-state. So steuert Uzai die Spotify-App
## auf diesem PC ohne api.spotify.com und ohne sie nach vorn zu holen.
const DEALER := "wss://dealer.spotify.com"


# Gemeinsamer Zustand, den alle Schichten und die Oberfläche lesen.
var spotify_mixes: Array = []   ## Mix der Woche, Release Radar, Daily Mix (wie die Spotify-App echt, sonst über die Suche)
var need_login := false         ## Anmeldung zu alt: Top-Titel und Künstler fehlen die Freigaben
var error := ""                 ## Fehler beim Steuern (zeigt „Läuft gerade“)
var connecting := false
## Spotify lässt Uzai gerade gar nicht rein: "nutzer" (Konto nicht in der App eingetragen),
## "premium" (Besitzer der App ohne Premium), "abgelaufen" (Anmeldung ungültig), "gesperrt" (Spotify
## lehnt das Konto ohne lesbaren Grund ab), "app" (Spotify nimmt die Anmeldung gerade nicht an:
## Grundmodus). "" = alles gut. Jede Antwort von Spotify kann jeden Grund bringen.
const ZUSTAENDE_PROBLEM := { "*": ["", "nutzer", "premium", "abgelaufen", "gesperrt", "app"], "": [], "nutzer": [], "premium": [],
	"abgelaufen": [], "gesperrt": [], "app": [] }
var problem := "":
	set(neu):
		Zustand.wechsel("musik.problem", ZUSTAENDE_PROBLEM, problem, neu)
		problem = neu
var app_note := ""                  ## ruhiger Hinweis, warum gerade die eigene Client-ID dran ist
var web: Web                        ## Spotify-Sitzung im Browser-Kern („Mit Spotify anmelden“), siehe web_sitzung()
var _fy_at := 0                     ## „Für dich“ zuletzt geladen (Unix-Zeit; 0 = beim nächsten Mal neu)

# Anmeldung, Schlüssel und Grenzen der Anfragen.
var _token := ""
var _token_until := 0
var _scopes := ""
## Zu welcher Anmeldung _token gehört: "" (keine) · app (mit Spotify angemeldet) · eigen (eigene Spotify-App).
## Folgt login_mode(); ein Wechsel der Anmeldung (Einstellungen, Abmelden) setzt zurück.
const ZUSTAENDE_ZUGANG := { "*": [""], "": ["app", "eigen"], "app": ["eigen"], "eigen": ["app"] }
var _tok_mode := "":
	set(neu):
		Zustand.wechsel("musik.zugang", ZUSTAENDE_ZUGANG, _tok_mode, neu)
		_tok_mode = neu
var _verifier := ""
var _oauth_state := ""             ## Zufallswert der laufenden Browser-Anmeldung (state)
var _server: TCPServer
var _quiet_mode := false            ## Anmeldung setzt accounts.spotify_mode selbst (kein _mode_changed)
var _api_base := API                ## für Tests umlenkbar (UZAI_SPOTIFY_API)
var _accounts := ACCOUNTS           ## für Tests umlenkbar (UZAI_SPOTIFY_ACCOUNTS)
var _spclient := SPCLIENT           ## für Tests umlenkbar (UZAI_SPOTIFY_SPCLIENT)
var _partner := PARTNER             ## für Tests umlenkbar (UZAI_SPOTIFY_PARTNER)
var _client_token := ""             ## Client-Token der Seite (kommt mit dem Schlüssel; nie gespeichert)
var _web_version := ""              ## Fassung des Webplayers (aus seinen Anfragen)
var _web_geprueft := ""             ## dieser Schlüssel gehört sicher zu einem Konto (nur im Speicher)
var _web_me := {}                   ## Konto aus der letzten Prüfung { id, name }
var _web_aus_bis := 0               ## die Sitzung gab keinen Schlüssel: bis dahin nicht neu fragen (Unix-Zeit)
var _token_ms := -100000            ## wann _token geholt wurde (ms): ein frischer läuft nicht ab
const FRESH_MS := 60000             ## so lange gilt ein Schlüssel als frisch (401 dann: Ablehnung)
var _pf_seen := {}                  ## pathfinder-Abfrage -> schon einmal geklappt (Protokoll nur beim ersten Mal)
var _track_cache := {}              ## Titel-URI -> Titel (pathfinder getTrack), spart Abfragen
var _album_cache := {}              ## Titel-URI -> Album-URI (pathfinder getTrack), für Weg d beim Abspielen
var _alt_token := ""                ## eigene Client-ID, solange Spotify die App-Anmeldung bremst
var _alt_until := 0
var _app_429 := 0                   ## 429 in Folge mit der App-Anmeldung
var _app_401 := 0                   ## 401 in Folge trotz frischer App-Anmeldung
var _app_slow_until := 0            ## bis dahin allgemeine Abrufe über die eigene Client-ID
var _app_off_until := 0             ## bis dahin App-Anmeldung aus (Spotify nimmt sie nicht an)
var _rate_until := { "app": 0, "eigen": 0 }   ## Spotify bremst (429): bis dahin gar nicht fragen
var _rate_strikes := { "app": 0, "eigen": 0 } ## 429 in Folge je Anmeldung: jede weitere verdoppelt die Pause
var _pf_off := ""                   ## pathfinder hat abgelehnt (403): für diese Anmeldung aus, mit Grund
var _inflight := {}                 ## laufende Leseabfrage -> { done, r } (dieselbe Anfrage nur einmal)
var _fail_cache := {}               ## abgelehnte Leseabfrage -> { until, r }
var _api_busy := 0                  ## gerade laufende Abfragen an Spotify
const API_SLOTS := 3
var _budget: Array = []             ## Zeitpunkte (ms) der letzten Anfragen an die Web-API
var _budget_logged := 0
var _budget_scale := 1              ## Netz-Tests gegen den Nachbau: viel höher (UZAI_SPOTIFY_API)

# Erneuern nur einmal gleichzeitig (Spotify dreht die Erneuerung bei jedem Erneuern).
var _refresh_busy := {}             ## Anmeldung ("app" | "eigen") -> läuft gerade
var _refresh_last := {}             ## Anmeldung -> letzte Antwort (für alle, die gewartet haben)
signal _refreshed(which: String)

# Spotify Connect.
var _dealer_url := DEALER           ## für Tests umlenkbar (UZAI_SPOTIFY_DEALER)
var _ws: WebSocketPeer = null
var _conn_id := ""                  ## Spotify-Connection-Id vom Dealer
var _dealer_backoff := 0            ## Sekunden bis zum nächsten Versuch nach einem Fehler
var _dealer_retry_at := 0
var _dealer_used_ms := 0            ## zuletzt gebraucht (zum Schließen, wenn niemand ihn braucht)
var _ping_ms := 0
var _connect_dev := ""              ## Uzais eigene, versteckte Kennung bei Spotify Connect
var _target_dev := ""               ## gewähltes Gerät, solange keins aktiv ist
var _gewollt_dev := ""              ## fremdes Gerät, das der Nutzer in „Abspielen auf …“ gewählt hat (bis es nicht mehr spielt)
var _gewollt_ms := 0                ## wann gewählt (das Gerät braucht ein paar Sekunden, bis es als laufend gilt)
var _cluster_raw := {}
var _cluster_at := -100000          ## wann zuletzt gelesen (ms)
var _cluster_dirty := true          ## der Dealer hat eine Änderung gemeldet
var _cluster_sig := ""              ## letzter Stand im Protokoll (nur bei Änderung neu)
var _cluster_fail_ms := -100000     ## Zustand zuletzt abgelehnt: 30 s Pause (keine Anfrage-Flut)
var _befehl_nr := 0                 ## zählt die Steuerbefehle: Ein neuer Befehl beendet das Nachsehen des vorigen
var _warte_faktor := 1.0            ## Tests verkürzen damit das Nachsehen nach dem Abspielen

# Grundmodus (siehe grundmodus()).
const GRUND_MERKEN_S := 12 * 3600   ## so lange merkt sich Uzai, dass Spotify den Weg nicht zulässt
const PLAY_WARTEN_MS := 5000        ## so lange darf die Spotify-App brauchen, bis das Gewünschte läuft (erster Weg)
const PLAY_WEITER_MS := 4000        ## … und bei jedem weiteren Weg
const PLAY_ANSTOSS_MS := 2500       ## … und nach dem Anstoßen, wenn es geladen war, aber stand
const PLAY_NACHLESEN_MS := 1200     ## spätestens so oft liest Uzai dabei selbst nach
const CODE_STUMM := -2              ## Spotify hat den Abspielbefehl angenommen, das Gerät hat nichts gestartet
var demo_grund := false             ## Vorführung und Proben: Grundmodus mit Beispieldaten
var _pf_probe := false              ## Probe-Anfrage läuft (die übrigen warten auf sie)
var _cluster_busy := false          ## Zustand von Spotify Connect wird gerade gelesen


static func demo() -> bool:
	return "--demo" in OS.get_cmdline_user_args()


func has_spotify() -> bool:
	if demo():
		return true
	return login_mode() != ""


## Mit Spotify angemeldet (Spotify-Sitzung im Browser-Kern)? Gespeichert ist nur, DASS angemeldet ist – die
## Anmeldung selbst liegt im Ordner der Sitzung (spotify_web.gd).
func app_ready() -> bool:
	return Config.get_value("accounts.spotify_web", false) == true


## Die Spotify-Sitzung (ein Knoten unter Music, bei Bedarf angelegt).
func web_sitzung() -> Web:
	if web == null:
		web = Web.new()
		web.name = "SpotifySitzung"
		web.log_fn = _log
		add_child(web)
	return web


## Anmeldung mit eigener Client-ID vorhanden?
func own_ready() -> bool:
	return str(Config.get_value("accounts.spotify_client_id", "")) != "" and str(Config.get_value("accounts.spotify_refresh", "")) != ""


## Welche Anmeldung gerade gilt: "app", "eigen" oder "" (keine). Gewählt in accounts.spotify_mode;
## sonst die App-Anmeldung vor der eigenen. Nimmt Spotify die App-Anmeldung gerade nicht an
## (_app_off_until), gilt die eigene, falls es sie gibt.
func login_mode() -> String:
	var m := str(Config.get_value("accounts.spotify_mode", ""))
	var app_ok := app_ready() and (Time.get_unix_time_from_system() >= _app_off_until or not own_ready())
	# Spotify sperrt die Anmeldung wie die Spotify-App (Web-API 429, intern 403): Gibt es die eigene
	# App, gilt sie – die App-Anmeldung nur, wenn ausdrücklich gewählt.
	if app_ok and (m == "app" or not own_ready()):
		return "app"
	if own_ready():
		return "eigen"
	return "app" if app_ok else ""


func app_mode() -> bool:
	return not demo() and login_mode() == "app"


## Mixe von Spotify mit Titelliste? Nur wie die Spotify-App (und in der Vorführung).
func mix_titles() -> bool:
	return demo() or app_mode()


## Grundmodus: mit Spotify angemeldet, keine eigene Spotify-App, und Spotify gibt
## Bibliothek, Mixe und Suche auf diesem Weg nicht heraus (pathfinder 403, Web-API 429). Uzai ist
## dann die Fernbedienung: Läuft gerade, Steuern und Geräte über Spotify Connect, Titel und Cover
## notfalls aus der Mediensitzung von Windows, dazu der eigene Verlauf. Abfragen von Bibliothek,
## Mixen und Suche ruhen ganz (keine Anfrage-Flut, ruhiges Protokoll).
func grundmodus() -> bool:
	if demo():
		return demo_grund
	return app_mode() and not own_ready() and (_pf_off != "" or problem == "app")


## Ruhen die Abrufe von Bibliothek und Konto gerade? Im Grundmodus ja. Hat Spotify die Anmeldung
## nur abgelehnt (problem "app", etwa 401) und ist die halbe Stunde Pause um, darf der nächste Abruf
## einzeln fragen, ob es wieder geht – sonst bliebe der Grundmodus bis zum Neustart (die Oberfläche
## bleibt dabei im Grundmodus, bis Spotify wirklich wieder antwortet).
func _grund_ruht() -> bool:
	if not grundmodus():
		return false
	return not (_pf_off == "" and problem == "app" and Time.get_unix_time_from_system() >= _app_off_until)


## Beim Start: Hat Spotify den Weg in den letzten Stunden nicht zugelassen, gleich im Grundmodus
## bleiben, statt erst wieder alle Abfragen zu schicken (im Protokoll des Nutzers ~40 Ablehnungen
## bei jedem Start). Danach fragt eine einzelne Anfrage, ob es wieder geht.
func _grund_restore() -> void:
	var at := int(Config.get_value("accounts.spotify_app_blocked", 0))
	if at <= 0 or demo() or not app_ready() or own_ready():
		return
	if int(Time.get_unix_time_from_system()) - at < GRUND_MERKEN_S:
		_pf_off = "gemerkt"
		_log("Grundmodus (gemerkt): Bibliothek, Mixe und Suche ruhen, Läuft gerade und Steuern über Spotify Connect")


## Ablehnung merken (on) bzw. vergessen. Gemerkt wird die Zeit der letzten Ablehnung (höchstens
## stündlich neu geschrieben), damit der Grundmodus nach einem Neustart ohne neue Anfrage gilt.
func _grund_merken(on: bool) -> void:
	var have := int(Config.get_value("accounts.spotify_app_blocked", 0))
	var now_s := int(Time.get_unix_time_from_system())
	if on and (have <= 0 or now_s - have > 3600):
		Config.set_value("accounts.spotify_app_blocked", now_s)
	elif not on and have > 0:
		Config.set_value("accounts.spotify_app_blocked", 0)


func search_limit() -> int:
	return APP_SEARCH_LIMIT if app_mode() else SEARCH_LIMIT


# --- Interne Schnittstelle (wie die Spotify-App) -------------------------------------------------

## Client-Token für api-partner/spclient: der, den die Seite zusammen mit dem Schlüssel schickt (leer, wenn sie
## keinen schickt – dann fragt Uzai ohne). Nie selbst geholt: Schlüssel und Client-Token stammen von derselben Seite.
func _client_token_get() -> String:
	return _client_token if _tok_mode == "app" else ""


## Fassung des Webplayers für die Kopfzeile „spotify-app-version“.
func _app_version() -> String:
	return _web_version if _web_version != "" else SPOTIFY_CLIENT_VERSION


## Ist ein Schlüssel (geholt zu at_ms) älter als eine Minute? Nur dann kann eine 401 heißen, dass er
## unterwegs abgelaufen ist; bei einem frischen lehnt Spotify die Anmeldung ab, und Erneuern hilft nicht.
static func _stale(at_ms: int) -> bool:
	return Time.get_ticks_msec() - at_ms > FRESH_MS


## 401 trotz frischem Schlüssel (Web-API oder pathfinder): Beim zweiten Mal in Folge nimmt Spotify
## die App-Anmeldung nicht an – dann ruhen alle Wege eine halbe Stunde (_app_reject), statt jede
## Abfrage samt Erneuerung und Client-Token zu wiederholen. true: jetzt gilt ein anderer Schlüssel.
func _app_401_hit(why: String) -> bool:
	if problem == "app" and Time.get_unix_time_from_system() < _app_off_until:
		return false
	_app_401 += 1
	if _app_401 < 2:
		return false
	_app_401 = 0
	# Nicht über einen Neustart merken: Eine 401 betrifft den Schlüssel, nicht den Weg (das sind 403 und 429). Am PC
	# (13.11.) hielt eine abgelaufene Anmeldung so Bibliothek und Lieblingssongs zwölf Stunden im Grundmodus.
	return await _app_reject(why, false, 1800, false)


## Eine pathfinder-Anfrage (api-partner, GraphQL mit Persisted Query). Nur mit der App-Anmeldung
## sinnvoll. { ok, code, data }.
func _pathfinder(op: String, hash: String, vars: Dictionary) -> Dictionary:
	# Solange noch keine Anfrage geklappt hat (oder Spotify die Anmeldung zuletzt abgelehnt hat), geht
	# nur eine hinaus; die übrigen warten auf ihre Antwort. Lehnt Spotify ab, kommt so eine Ablehnung
	# statt zwanzig gleichzeitiger.
	if (_pf_seen.is_empty() or problem == "app") and _pf_off == "":
		while _pf_probe:
			await get_tree().process_frame
		if (_pf_seen.is_empty() or problem == "app") and _pf_off == "":
			_pf_probe = true
			var r0 := await _pathfinder_do(op, hash, vars)
			_pf_probe = false
			return r0
	return await _pathfinder_do(op, hash, vars)


func _pathfinder_do(op: String, hash: String, vars: Dictionary) -> Dictionary:
	# Lehnt Spotify die App-Anmeldung gerade ab (problem "app"): bis zum nächsten Versuch nicht fragen.
	if problem == "app" and Time.get_unix_time_from_system() < _app_off_until:
		return { "ok": false, "code": 0, "data": null }
	# Schutzschalter: Hat pathfinder einmal abgelehnt (403 „Client/request not allowed“), fragt Uzai
	# für diese Anmeldung nicht mehr – im Protokoll kam sonst jede Sekunde dieselbe Ablehnung.
	if _pf_off != "":
		return { "ok": false, "code": 403, "data": null, "why": "app" }
	if not await _ensure_token() or _tok_mode != "app":
		return { "ok": false, "code": 0, "data": null }
	# api-partner ist ein eigener Dienst – die Bremse der Web-API (api.spotify.com) gilt hier nicht.
	var ct := _client_token_get()
	# Während des Wartens kann ein anderer Abruf den Schlüssel verworfen haben: nie ohne schicken.
	if _token == "" and (not await _ensure_token() or _tok_mode != "app"):
		return { "ok": false, "code": 0, "data": null }
	var payload := { "operationName": op, "variables": vars, "extensions": { "persistedQuery": { "version": 1, "sha256Hash": hash } } }
	var r := await _netz(HTTPClient.METHOD_POST, _partner, payload, _pf_headers(ct), true)
	_text_as_error(r)
	if int(r.code) == 401:
		# Schlüssel unterwegs abgelaufen: einmal frisch von der Seite (mit neuem Client-Token) und nochmal. Ist er
		# frisch, lehnt Spotify die Anmeldung ab – nochmal fragen hilft nicht (keine Anfrage-Flut).
		var retry := false
		if _stale(_token_ms):
			# Der Seite sagen, dass dieser abgelehnt ist – sonst gibt sie denselben abgelaufenen noch einmal heraus.
			web_sitzung().schluessel_verwerfen(_token)
			_token = ""
			_client_token = ""
			retry = true
		if retry and await _ensure_token() and _tok_mode == "app":
			ct = _client_token_get()
			r = await _netz(HTTPClient.METHOD_POST, _partner, payload, _pf_headers(ct), true)
			_text_as_error(r)
		if int(r.code) == 401 and ct != "" and _tok_mode == "app":
			await _app_401_hit("pathfinder lehnt den Schlüssel ab (401)")
	r["ok"] = r.ok and r.data is Dictionary and (r.data as Dictionary).get("data") != null
	if r.ok:
		_app_401 = 0
	# Protokoll: jeder Weg einmal, wenn er klappt, und jedes Mal, wenn nicht (ohne Zugangsdaten).
	if r.ok and problem == "app":
		_set_problem("")          # Spotify nimmt die App-Anmeldung wieder an
	if r.ok:
		_grund_merken(false)
	if r.ok and not _pf_seen.has(op):
		_pf_seen[op] = true
		_log("Intern %s (pathfinder): ok" % op)
	elif not r.ok:
		var errs: Variant = (r.data as Dictionary).get("errors") if r.data is Dictionary else null
		var msg := _brief(r.get("data"))
		if msg == "" and errs is Array and not (errs as Array).is_empty() and errs[0] is Dictionary:
			msg = str((errs[0] as Dictionary).get("message", "")).left(120)
		_log("Intern %s (pathfinder): HTTP %d %s" % [op, int(r.code), msg])
		if int(r.code) == 403 and _pf_off == "":
			_pf_off = msg if msg != "" else "HTTP 403"
			_log("pathfinder für diese Anmeldung aus (Spotify lässt den Weg nicht zu)")
			if not own_ready():
				# Grundmodus: die Oberfläche stellt auf Fernbedienung und Verlauf um.
				_grund_merken(true)
				updated.emit()
				lists_changed.emit("problem")
			await _app_blocked_check()
	return r


func _pf_headers(ct: String) -> PackedStringArray:
	var h := PackedStringArray(["Authorization: Bearer " + _token, "Accept: application/json",
		"app-platform: WebPlayer", "spotify-app-version: " + _app_version(), "Origin: https://open.spotify.com"])
	if ct != "":
		h.append("client-token: " + ct)
	return h


## Neue Anmeldung mit Spotify: Schutzschalter und Bremse zurück auf Anfang.
func _app_fresh() -> void:
	_pf_off = ""
	_app_401 = 0
	_grund_merken(false)
	_rate_strikes["app"] = 0
	_rate_until["app"] = 0
	_app_429 = 0
	_app_off_until = 0
	_fail_cache.clear()


## pathfinder-Abfrage mit dem bekannten Hash (spotify_intern.gd).
func _pf(op: String, vars: Dictionary) -> Dictionary:
	return await _pathfinder(op, str(Intern.HASHES.get(op, "")), vars)


## Variablen für libraryV3 (Playlists, Alben oder Künstler deiner Bibliothek), wie der Web-Client.
static func _lib_vars(filter: String, limit: int, offset: int) -> Dictionary:
	return { "filters": [filter], "order": null, "textFilter": "", "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "EVENTS"],
		"limit": limit, "offset": offset, "flatten": true, "expandedFolders": [], "folderUri": null, "includeFoldersWhenFlattening": false }


## Ein Titel über pathfinder (getTrack), in Uzais Form; gemerkt für die Sitzung.
func _track_meta(uri: String) -> Dictionary:
	if _track_cache.has(uri):
		return _track_cache[uri]
	var r := await _pf("getTrack", { "uri": uri })
	var t := track_from(Intern.track(Intern.dig(r.data, "data/trackUnion"))) if r.ok else {}
	if not t.is_empty():
		if _track_cache.size() > 500:
			_track_cache.clear()
		_track_cache[uri] = t
	return t


## Das Album eines Titels (pathfinder getTrack) für Weg d beim Abspielen; gemerkt für die Sitzung. "" wenn unbekannt.
func _album_von(titel: String) -> String:
	if not titel.begins_with("spotify:track:"):
		return ""
	if _album_cache.has(titel):
		return str(_album_cache[titel])
	var r := await _pf("getTrack", { "uri": titel })
	var a := Intern.s(Intern.dig(r.data, "data/trackUnion/albumOfTrack/uri")) if r.ok else ""
	if a != "":
		if _album_cache.size() > 500:
			_album_cache.clear()
		_album_cache[titel] = a
	return a


## Anfrage an spclient mit der App-Anmeldung und Client-Token (wie die Spotify-Apps). path ohne Host.
func _spc(method: int, path: String, payload: Variant = null, extra := PackedStringArray()) -> Dictionary:
	var fkey := "S|" + path
	var cached: Variant = _fail_cache.get(fkey) if method == HTTPClient.METHOD_GET else null
	if cached is Dictionary and int(Time.get_unix_time_from_system()) < int((cached as Dictionary).until):
		return ((cached as Dictionary).r as Dictionary).duplicate()
	if not await _ensure_token() or _tok_mode != "app":
		return { "ok": false, "code": 0, "data": null }
	var r: Dictionary = await _spc_do(method, path, payload, extra)
	if method == HTTPClient.METHOD_GET and fail_hold(int(r.get("code", 0)), true) > 0:
		_fail_cache[fkey] = { "until": int(Time.get_unix_time_from_system()) + fail_hold(int(r.code), true), "r": r }
	return r


func _spc_do(method: int, path: String, payload: Variant, extra: PackedStringArray) -> Dictionary:
	var r: Dictionary = {}
	for attempt in 2:
		if _token == "" and (not await _ensure_token() or _tok_mode != "app"):
			return { "ok": false, "code": 0, "data": null }
		var ct := _client_token_get()
		var h := PackedStringArray(["Authorization: Bearer " + _token, "Accept: application/json", "app-platform: WebPlayer",
			"spotify-app-version: " + _app_version()])
		if ct != "":
			h.append("client-token: " + ct)
		h.append_array(extra)
		r = await _netz(method, _spclient + path, payload, h, true)
		if method != HTTPClient.METHOD_GET:
			r["ok"] = int(r.code) >= 200 and int(r.code) < 300
		_text_as_error(r)
		if int(r.code) != 401 or attempt == 1:
			break
		# Nur nochmal, wenn ein Schlüssel unterwegs abgelaufen sein kann (nicht frisch). Lehnt spclient
		# frische Schlüssel ab, gilt die Anmeldung trotzdem (andere Wege gehen weiter).
		var retry := false
		if _stale(_token_ms):
			if _tok_mode == "app":
				web_sitzung().schluessel_verwerfen(_token)
			_token = ""
			_client_token = ""
			retry = true
		if not retry or not await _ensure_token():
			break
	return r


# --- Spotify Connect (Dealer + connect-state) ----------------------------------------------------

func _dealer_message(text: String) -> void:
	var d: Variant = Fremd.json(text)
	if not (d is Dictionary):
		return
	var h := Intern.dict((d as Dictionary).get("headers"))
	var cid := Intern.s(h.get("Spotify-Connection-Id", h.get("spotify-connection-id")))
	if cid != "" and cid != _conn_id:
		_conn_id = cid
		_dealer_backoff = 0
		_dealer_retry_at = 0
		_log("Dealer: verbunden (Connection-Id erhalten)")
	if Intern.s((d as Dictionary).get("uri")).begins_with("hm://connect-state/v1/"):
		_cluster_dirty = true


## Dealer verbunden und Connection-Id da? Verbindet bei Bedarf (wartet höchstens 6 s je Versuch).
##
## Der Dealer nimmt nur einen aktuellen Schlüssel. Im Protokoll vom PC (13.11.) kam die Verbindung jedes Mal
## zustande, wenn der Schlüssel eben geholt war, und wurde mit einem älteren sofort getrennt – danach wartete Uzai
## bis zu fünf Minuten mit demselben Schlüssel, Abspielen wich auf die Web-API aus, und die bremste (429): „Lieder
## spielen nicht ab“. Darum: Lehnt der Dealer einen Schlüssel ab, der nicht frisch war, holt Uzai sofort einen
## neuen von der Seite und versucht es in demselben Aufruf noch einmal.
func _dealer_ensure() -> bool:
	_dealer_used_ms = Time.get_ticks_msec()
	for versuch in 2:
		if _ws != null and _conn_id != "" and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		var alt := false
		if _ws == null:
			if Time.get_unix_time_from_system() < _dealer_retry_at:
				return false
			if not await _ensure_token() or _tok_mode != "app":
				return false
			alt = _stale(_token_ms)
			_ws = WebSocketPeer.new()
			_conn_id = ""
			# Der Schlüssel steht in der Adresse (wie bei den Spotify-Apps) – die Adresse nie ins Protokoll.
			var err := _ws.connect_to_url(_dealer_url + "/?access_token=" + _token.uri_encode())
			if err != OK:
				_ws = null
				_dealer_fail("Verbindung nicht möglich (Fehler %d)" % err)
				return false
			_ping_ms = Time.get_ticks_msec()
			set_process(true)
			_log("Dealer: verbinde …")
		var t0 := Time.get_ticks_msec()
		while _conn_id == "" and _ws != null and Time.get_ticks_msec() - t0 < 6000:
			await get_tree().create_timer(0.1).timeout
		if _conn_id != "":
			return true
		if _ws != null:
			_ws.close()
			_ws = null
			set_process(false)
			_dealer_fail("keine Connection-Id nach 6 s")
		if not dealer_nochmal(versuch, alt, _tok_mode):
			return false
		_schluessel_frisch()
	return false


## Nach einem abgelehnten Versuch gleich noch einmal? Nur einmal, nur mit der Spotify-Sitzung, und nur wenn der
## Schlüssel nicht frisch war (ein frischer wird nicht besser).
static func dealer_nochmal(versuch: int, schluessel_alt: bool, modus: String) -> bool:
	return versuch == 0 and schluessel_alt and modus == "app"


## Der Schlüssel taugt nicht mehr: verwerfen, damit der nächste Abruf einen neuen von der Seite holt – und der
## Dealer es damit sofort wieder versuchen darf.
func _schluessel_frisch() -> void:
	_log("Dealer: Schlüssel abgelehnt – hole einen neuen")
	web_sitzung().schluessel_verwerfen(_token)
	_token = ""
	_dealer_backoff = 0
	_dealer_retry_at = 0
	_cluster_fail_ms = -100000


func _dealer_fail(why: String) -> void:
	_dealer_backoff = clampi(maxi(2, _dealer_backoff * 2), 2, 300)
	_dealer_retry_at = int(Time.get_unix_time_from_system()) + _dealer_backoff
	_log("Dealer: %s – nächster Versuch frühestens in %d s" % [why, _dealer_backoff])


## Dealer schließen (wird bei Bedarf wieder verbunden).
func dealer_close(why := "") -> void:
	if _ws == null:
		return
	_ws.close()
	_ws = null
	_conn_id = ""
	_cluster_dirty = true
	set_process(false)
	_log("Dealer: geschlossen%s" % ((" (" + why + ")") if why != "" else ""))


## Zustand von Spotify Connect (roh). Zwischengespeichert, bis der Dealer eine Änderung meldet
## (höchstens 15 s); force: jetzt neu lesen. {} wenn Spotify Connect nicht erreichbar ist.
func _cluster_read(force := false) -> Dictionary:
	if not app_mode():
		return {}
	_dealer_used_ms = Time.get_ticks_msec()
	if not force and not _cluster_dirty and not _cluster_raw.is_empty() and Time.get_ticks_msec() - _cluster_at < 15000 and _ws != null:
		return _cluster_raw
	if not force and Time.get_ticks_msec() - _cluster_fail_ms < 30000:
		return {}
	# Liest schon jemand (Abfrage, Lautstärke, Warteschlange gleichzeitig): dessen Antwort nehmen,
	# statt das versteckte Gerät ein zweites Mal anzumelden.
	if _cluster_busy:
		while _cluster_busy:
			await get_tree().process_frame
		return _cluster_raw if Time.get_ticks_msec() - _cluster_at < 2000 else {}
	_cluster_busy = true
	var out := await _cluster_fetch()
	_cluster_busy = false
	return out


func _cluster_fetch() -> Dictionary:
	if not await _dealer_ensure():
		return {}
	var body := { "member_type": "CONNECT_STATE",
			"device": { "device_info": { "capabilities": { "can_be_player": false, "hidden": true, "needs_full_player_state": true } } } }
	var r := await _spc(HTTPClient.METHOD_PUT, "/connect-state/v1/devices/" + _connect_dev, body, PackedStringArray(["X-Spotify-Connection-Id: " + _conn_id]))
	if not r.ok or not (r.data is Dictionary):
		_cluster_fail_ms = Time.get_ticks_msec()
		_log("Connect: Zustand lesen → HTTP %d %s – 30 s Pause" % [int(r.get("code", 0)), _brief(r.get("data"))])
		return {}
	_cluster_raw = r.data
	_cluster_at = Time.get_ticks_msec()
	_cluster_dirty = false
	var info := Intern.cluster(_cluster_raw, _connect_dev, _now_ms())
	if str(info.active) != "" and str(info.active) != last_device() and device_id_ok(str(info.active)):
		Config.set_value("music.spotify_last_device", str(info.active))
	var active_name := ""
	for d in info.devices:
		if bool(d.active):
			active_name = str(d.name)
	var sig := "%d|%s" % [(info.devices as Array).size(), active_name]
	if sig != _cluster_sig:
		_cluster_sig = sig
		_log("Connect: %d Gerät(e), aktiv: %s" % [(info.devices as Array).size(), active_name if active_name != "" else "keins"])
	return _cluster_raw


## Gerät, auf dem zuletzt etwas lief (Kennung von Spotify Connect, nur auf diesem PC gemerkt).
func last_device() -> String:
	var v := str(Config.get_value("music.spotify_last_device", ""))
	return v if device_id_ok(v) else ""


static func device_id_ok(v: String) -> bool:
	if v.length() < 8 or v.length() > 64:
		return false
	for ch in v:
		if not (ch.is_valid_identifier() or ch == "-" or (ch >= "0" and ch <= "9")):
			return false
	return true


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Befehle an ein Gerät schicken. Gibt den HTTP-Code des letzten zurück (0: nicht geschickt).
## von: Absender in der Adresse ("" = Uzais unsichtbares Gerät). wozu: Zusatz fürs Protokoll.
func _connect_send(cmds: Array, target: String, von := "", wozu := "") -> int:
	var code := 0
	var ab := von if von != "" else _connect_dev
	for c in cmds:
		var r := await _spc(HTTPClient.METHOD_POST, "/connect-state/v1/player/command/from/%s/to/%s" % [ab, target], { "command": c })
		code = int(r.get("code", 0))
		_log("Connect: %s%s → %s: HTTP %d%s" % [str((c as Dictionary).get("endpoint", "")), wozu, _dev_name(target), code,
				("" if r.ok else " " + _brief(r.get("data")))])
		if not r.ok:
			break
	_cluster_dirty = true
	return code


func _dev_name(id: String) -> String:
	for d in Intern.cluster(_cluster_raw, _connect_dev, 0).devices:
		if str(d.id) == id:
			return str(d.name)
	return "Gerät"


## Steuerbefehl der Web-API über Spotify Connect. { handled, ok, code }: handled false, wenn es keine
## Entsprechung gibt oder Spotify Connect nicht erreichbar ist (dann geht es weiter wie bisher).
func _connect_control(method: int, path: String, payload: Variant) -> Dictionary:
	var cmds := Intern.commands_for(method, path, payload, _hex(32))
	if cmds.is_empty():
		return { "handled": false }
	var raw := await _cluster_read()
	if raw.is_empty():
		return { "handled": false }
	var info := Intern.cluster(raw, _connect_dev, _now_ms())
	var ort := spotify_ort()
	_gewollt_pruefen(info)
	var target := Intern.pick_target(info, OS.get_environment("COMPUTERNAME"), ort, _gewollt_dev)
	var da := func(id: String) -> bool: return id != "" and (info.devices as Array).any(func(d): return str(d.id) == id)
	if ort == "pc":
		# Dieser PC ist nicht dabei: Der Aufrufer startet Spotify hier (404 → ensure_device) und kommt mit dem
		# Gerät wieder, das dann gilt – nie von selbst der Fernseher, auf dem zuletzt etwas lief.
		if target == "" and da.call(_target_dev):
			target = _target_dev
	elif str(info.active) == "" and da.call(_target_dev):
		target = _target_dev
	elif str(info.active) == "" and _target_dev == "":
		# „Weiter hören“: dort fortsetzen, wo zuletzt etwas lief (SHIELD, Echo …), wenn es noch da ist.
		var last := last_device()
		if da.call(last):
			target = last
	if target == "":
		return { "handled": true, "ok": false, "code": 404 }
	var was := str((cmds[0] as Dictionary).get("endpoint", ""))
	if was in ["play", "resume", "pause", "skip_next", "skip_prev"]:
		_befehl_nr += 1
	if was == "play" and not Intern.play_wunsch(payload).is_empty():
		return await _connect_play(payload, target, info)
	var code := await _connect_send(cmds, target)
	return { "handled": true, "ok": code >= 200 and code < 300, "code": code }


## Abspielen mit Nachsehen. Spotify nimmt den Befehl an (HTTP 200), auch wenn die Spotify-App ihn dann nicht ausführt:
## Im Protokoll vom PC (13.11., 0.16.61) stand dreimal „play → HTTP 200“, die App wurde aktives Gerät, und es lief
## nichts – ohne jede Meldung. Darum zählt erst, was das Gerät danach meldet (Intern.play_stand). Läuft nach
## PLAY_WARTEN_MS nichts, nimmt Uzai den nächsten Weg (Intern.play_wege) und merkt sich den, der zum Laufen führte –
## getrennt für lose Titellisten und für Playlists/Alben. Führt keiner dazu: Code CODE_STUMM (connect_error).
func _connect_play(payload: Variant, target: String, vorher: Dictionary) -> Dictionary:
	var nr := _befehl_nr
	var key := "music.spotify_weg_" + ("liste" if bool(Intern.play_wunsch(payload).lose) else "kontext")
	var vor_titel := Intern.s(Intern.dig(vorher, "track/uri"))
	var wege := Intern.play_wege(str(Config.get_value(key, "a")), payload)
	for i in wege.size():
		var weg := str(wege[i])
		var p: Variant = Intern.play_einzeln(payload) if weg == "c" else payload
		if weg == "d":
			p = Intern.play_album(payload, await _album_von(Intern.s(Intern.play_wunsch(payload).get("titel"))))
			if (p as Dictionary).is_empty():
				_log("Connect: Weg d – kein Album zum Titel")
				continue
		var wunsch := Intern.play_wunsch(p)
		var cmds := Intern.commands_for(HTTPClient.METHOD_PUT, "/me/player/play", p, _hex(32))
		var code := await _connect_send(cmds, target, "" if weg in ["a", "d"] else target, " (%s, Weg %s)" % [Intern.play_art(p), weg])
		if code < 200 or code >= 300:
			return { "handled": true, "ok": false, "code": code }
		var t0 := Time.get_ticks_msec()
		var stand := await _play_warten(target, vor_titel, wunsch, int((PLAY_WARTEN_MS if i == 0 else PLAY_WEITER_MS) * _warte_faktor), nr)
		if stand == "pausiert":
			# Geladen, aber es steht: einmal anstoßen.
			await _connect_send(Intern.commands_for(HTTPClient.METHOD_PUT, "/me/player/play", null, _hex(32)), target)
			stand = await _play_warten(target, vor_titel, wunsch, int(PLAY_ANSTOSS_MS * _warte_faktor), nr)
		if stand == "anders":
			return { "handled": true, "ok": true, "code": code }
		var sek := (Time.get_ticks_msec() - t0) / 1000.0
		if stand == "ja":
			_log("Connect: läuft nach %.1f s" % sek)
			if str(Config.get_value(key, "a")) != weg:
				Config.set_value(key, weg)
			return { "handled": true, "ok": true, "code": code }
		var bild := Intern.play_bild(Intern.cluster(_cluster_raw, _connect_dev, _now_ms()), target)
		if i + 1 < wege.size():
			_log("Connect: nach %.1f s läuft nichts (%s) – versuche den nächsten Weg" % [sek, bild])
		else:
			_log("Connect: nach %.1f s läuft nichts (%s) – alle Wege versucht" % [sek, bild])
	return { "handled": true, "ok": false, "code": CODE_STUMM }


## Wartet, bis das Zielgerät das Gewünschte meldet: "ja", "pausiert", "nein" (Zeit um) oder "anders" (inzwischen kam
## ein neuer Befehl – der gilt). Der Dealer meldet Änderungen; zur Sicherheit liest Uzai auch selbst nach.
func _play_warten(target: String, vor_titel: String, wunsch: Dictionary, ms: int, nr: int) -> String:
	var t0 := Time.get_ticks_msec()
	var gelesen := -100000
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().create_timer(0.3 * _warte_faktor).timeout
		if nr != _befehl_nr:
			return "anders"
		var selbst := Time.get_ticks_msec() - gelesen > PLAY_NACHLESEN_MS
		var raw := await _cluster_read(selbst)
		if selbst:
			gelesen = Time.get_ticks_msec()
		if raw.is_empty():
			continue
		var stand := Intern.play_stand(Intern.cluster(raw, _connect_dev, _now_ms()), target, vor_titel, wunsch)
		if stand != "nein":
			return stand
	return "nein"


## Wo Spotify spielt: "pc" (immer auf diesem PC, Voreinstellung) oder "aktiv" (auf dem Gerät, das gerade läuft).
static func spotify_ort() -> String:
	var v := str(Config.get_value("system.spotify_ort", "pc"))
	return v if v in ["pc", "aktiv"] else "pc"


## Das selbst gewählte fremde Gerät gilt nur, solange es spielt: Läuft inzwischen etwas anderes (oder nichts mehr),
## gehen Befehle wieder an diesen PC.
func _gewollt_pruefen(info: Dictionary) -> void:
	if _gewollt_dev != "" and str(info.get("active", "")) != _gewollt_dev and Time.get_ticks_msec() - _gewollt_ms > 8000:
		_gewollt_dev = ""


static func connect_error(code: int) -> String:
	if code == CODE_STUMM:
		return "Spotify hat den Titel nicht gestartet. In Spotify einmal etwas abspielen, dann erneut versuchen."
	if code == 404:
		return "Spotify ist nicht bereit. Spotify einmal öffnen."
	if code == 429:
		return "Spotify bremst gerade (zu viele Anfragen). Gleich nochmal versuchen."
	if code == 0:
		return "Spotify ist gerade nicht erreichbar."
	return "Spotify hat den Befehl nicht angenommen. Gleich noch einmal versuchen."


# --- Spotify-Anmeldung (einmalig) ----------------------------------------------
# Eigene Client-ID: Spotify lässt eigene Apps nur über eine Adresse auf diesem PC (127.0.0.1)
# anmelden und kennt dafür keine Anmeldung per Code auf dem Handy. Darum öffnet sich einmal der
# Browser; danach holt sich Uzai selbst wieder nach vorn.
# „Mit Spotify anmelden“ (Standard): die echte Anmeldeseite im Uzai-Browser, danach die Spotify-Sitzung
# (spotify_web.gd, src/ui/layers/spotify_anmelden.gd, music.gd web_angemeldet).

## Freigabe im Browser am PC (PKCE): öffnet die Seite von Spotify, wartet auf den Rücksprung und
## tauscht den Code. { ok, code, data } oder { ok: false, err } (Port belegt, nichts erhalten).
func _browser_login(cid: String, ports: Array, path: String, scopes: String) -> Dictionary:
	# Vor dem Öffnen des Ports: Sonst bliebe er im Kinderprofil belegt, obwohl gar keine Anmeldung läuft.
	if Config.kid_stop("browser"):
		return { "ok": false, "err": "Im Kinderprofil öffnet Uzai keine Webseiten." }
	_server = TCPServer.new()
	var port := 0
	for p in ports:
		if _server.listen(int(p), "127.0.0.1") == OK:
			port = int(p)
			break
	if port == 0:
		return { "ok": false, "err": "Port %d ist belegt. Bitte das andere Programm schließen." % int(ports[0]) }
	var redirect := "http://127.0.0.1:%d%s" % [port, path]
	connecting = true
	OS.shell_open(authorize_url(cid, redirect, scopes))
	var code := await _wait_for_code(180.0)
	_server.stop()
	connecting = false
	# Zurück zu Uzai: der Browser hat seinen Dienst getan.
	Helper.run("focus", { "pid": OS.get_process_id() })
	if code == "":
		return { "ok": false, "err": "Keine Anmeldung erhalten." }
	return await _exchange_code(cid, code, redirect)


## Adresse der Freigabe-Seite (PKCE mit S256); merkt sich den Prüfwert für _exchange_code und
## einen Zufallswert (state), ohne den Uzai keinen Rücksprung annimmt.
func authorize_url(cid: String, redirect: String, scopes: String) -> String:
	_verifier = _random(64)
	_oauth_state = _random(32)
	var challenge := Marshalls.raw_to_base64(_verifier.sha256_buffer()).replace("+", "-").replace("/", "_").replace("=", "")
	return _accounts + "/authorize?" + Net.query({
		"client_id": cid, "response_type": "code", "redirect_uri": redirect, "code_challenge_method": "S256",
		"code_challenge": challenge, "scope": scopes, "state": _oauth_state })


## Code aus dem Rücksprung, nur mit dem passenden Zufallswert (state); sonst "".
static func callback_code(request_line: String, state: String) -> String:
	var q := request_line.get_slice(" ", 1).get_slice("?", 1)
	var code := ""
	var got_state := ""
	for part in q.split("&"):
		if part.begins_with("code="):
			code = part.substr(5).uri_decode()
		elif part.begins_with("state="):
			got_state = part.substr(6).uri_decode()
	return code if state != "" and got_state == state else ""


## Code aus dem Rücksprung gegen die Anmeldung tauschen (mit dem Prüfwert von authorize_url).
func _exchange_code(cid: String, code: String, redirect: String) -> Dictionary:
	var r := await Net.post_form(_accounts + "/api/token", {
		"grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "client_id": cid, "code_verifier": _verifier })
	_text_as_error(r)
	return r


## Fehlen der Anmeldung Freigaben für „Für dich“ (alte Anmeldung)? Leer, wenn alles da ist
## oder Spotify die Freigaben nicht genannt hat.
func missing_scopes() -> Array:
	if _scopes == "" or _tok_mode == "app":
		return []
	var have := _scopes.split(" ")
	return FOR_YOU_SCOPES.filter(func(s): return not have.has(s))


func _wait_for_code(timeout: float) -> String:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame
		if not _server.is_connection_available():
			continue
		var peer := _server.take_connection()
		var req := ""
		var t1 := Time.get_ticks_msec()
		# Nur der Kopf der Anfrage, höchstens 8 KB (auf 127.0.0.1 kann jedes Programm anklopfen).
		while Time.get_ticks_msec() - t1 < 2000 and not req.contains("\r\n\r\n") and req.length() < 8192:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				req += peer.get_utf8_string(mini(n, 8192))
			await get_tree().process_frame
		var code := callback_code(req.get_slice("\r\n", 0), _oauth_state)
		# Ohne passenden Zufallswert (fremde Seite, alter Tab): nichts annehmen, weiter warten.
		var html := "<html><meta charset='utf-8'><body style='background:#0d0e10;color:#f3f1ec;font-family:sans-serif;padding:60px'><h1>Uzai ist mit Spotify verbunden.</h1><p>Uzai ist wieder vorn – dieses Fenster kann zu.</p><script>setTimeout(function(){window.close()},800)</script></body></html>" if code != "" \
			else "<html><meta charset='utf-8'><body style='background:#0d0e10;color:#f3f1ec;font-family:sans-serif;padding:60px'><h1>Diese Anmeldung gehört nicht zu Uzai.</h1><p>Bitte in Uzai neu starten.</p></body></html>"
		var body := html.to_utf8_buffer()
		peer.put_data(("HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\nConnection: close\r\n\r\n" % ["200 OK" if code != "" else "400 Bad Request", body.size()]).to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()
		if code != "":
			return code
	return ""


# --- Schlüssel speichern und erneuern ------------------------------------------------------------

func _store_token(d: Variant, which := "") -> void:
	var w := which if which != "" else _tok_mode
	if d is Dictionary:
		# Ein neuer Schlüssel: Der Dealer darf sofort wieder (seine Pause galt dem alten).
		if str(d.get("access_token", "")) != _token:
			_dealer_backoff = 0
			_dealer_retry_at = 0
		_token = str(d.get("access_token", ""))
		_token_ms = Time.get_ticks_msec()
		_token_until = int(Time.get_unix_time_from_system()) + gilt_s(d.get("expires_in")) - 60
		if d.get("scope") is String and str(d.scope) != "":
			_scopes = str(d.scope)
			need_login = w != "app" and not missing_scopes().is_empty() and relogin_helps()
		# Spotify schickt bei der Erneuerung nicht immer eine neue mit: dann gilt die alte weiter.
		if str(d.get("refresh_token", "")) != "" and w != "app":
			Config.set_value("accounts.spotify_refresh", str(d.refresh_token))


## Wie lange ein Schlüssel laut Antwort gilt (Sekunden). Fehlt die Angabe oder ist sie Unsinn, eine Stunde; nie unter
## zwei Minuten: Mit 0 gälte jeder Schlüssel sofort als abgelaufen, und jede Anfrage erneuerte die Anmeldung erst
## einmal (Spotify dreht dabei die Erneuerung und bremst).
static func gilt_s(v: Variant) -> int:
	return clampi(Fremd.zahl(v, 3600), 120, 86400)


## Anmeldung erneuern (für die gegebene Anmeldung): Antwort von /api/token.
## Immer nur eine Erneuerung je Anmeldung gleichzeitig: Spotify dreht die Erneuerung bei jedem
## Erneuern (die alte gilt danach nicht mehr). Schickten mehrere Abrufe gleichzeitig dieselbe alte
## Erneuerung, lehnte Spotify alle bis auf eine ab – im echten Protokoll stand dann viermal in
## derselben Sekunde „Refresh token revoked“, und die Anmeldung galt als beendet. Wer kommt,
## während eine Erneuerung läuft, wartet auf sie und bekommt dieselbe Antwort.
func _refresh(which: String) -> Dictionary:
	if bool(_refresh_busy.get(which, false)):
		while bool(_refresh_busy.get(which, false)):
			await _refreshed
		return _refresh_last.get(which, { "ok": false, "code": 0, "data": null })
	_refresh_busy[which] = true
	var r := await _refresh_now(which)
	_refresh_last[which] = r
	_refresh_busy[which] = false
	_refreshed.emit(which)
	return r


func _refresh_now(which: String) -> Dictionary:
	if which == "app":
		return await _web_refresh()
	var key := "accounts.spotify_refresh"
	var refresh := str(Config.get_value(key, ""))
	if refresh == "":
		return { "ok": false, "code": 0, "data": null, "none": true }
	var cid := str(Config.get_value("accounts.spotify_client_id", ""))
	var r := await Net.post_form(_accounts + "/api/token", { "grant_type": "refresh_token", "refresh_token": refresh, "client_id": cid })
	_text_as_error(r)
	if not r.ok and int(r.code) == 400 and classify(400, r.get("data")) == "abgelaufen":
		# Hat inzwischen etwas anderes die Erneuerung gedreht (gespeicherte ist neuer als die
		# geschickte), einmal mit der neuesten versuchen, bevor die Anmeldung als beendet gilt.
		var latest := str(Config.get_value(key, ""))
		if latest != "" and latest != refresh:
			_log("Anmeldung erneuern: abgelehnt, gespeicherte Erneuerung ist neuer – nochmal damit")
			r = await Net.post_form(_accounts + "/api/token", { "grant_type": "refresh_token", "refresh_token": latest, "client_id": cid })
			_text_as_error(r)
	if r.ok and r.data is Dictionary and str((r.data as Dictionary).get("refresh_token", "")) != "":
		# Die neue Erneuerung sofort sichern (nicht erst später): die alte gilt schon nicht mehr.
		Config.set_value(key, str((r.data as Dictionary).refresh_token))
		Config.save_settings()
	return r


## Mit Spotify angemeldet: ein frischer Schlüssel von der Seite (spotify_web.gd) in der Form einer Antwort von
## /api/token. Jeder neue Schlüssel wird einmal geprüft (profileAttributes): Ein Schlüssel ohne Konto heißt, die
## Seite ist abgemeldet (Spotify hat die Sitzung beendet) – das gilt wie eine abgelaufene Anmeldung.
## "web" in der Antwort: "" (gut), "abgemeldet", "kern", "zeit", "anmeldung" (siehe Web.holen).
func _web_refresh() -> Dictionary:
	if not app_ready():
		return { "ok": false, "code": 0, "data": null, "none": true }
	var w: Dictionary = await web_sitzung().holen()
	if not bool(w.get("ok", false)):
		var why := str(w.get("why", "zeit"))
		if why == "abgemeldet":
			return { "ok": false, "code": 401, "data": { "error": "invalid_grant", "error_description": "Spotify-Sitzung abgemeldet" }, "web": why }
		return { "ok": false, "code": 0, "data": null, "web": why }
	var tok := str(w.get("token", ""))
	if tok != _web_geprueft:
		var konto := await _web_konto(tok, str(w.get("client", "")), str(w.get("version", "")))
		if konto == "nein":
			return { "ok": false, "code": 401, "data": { "error": "invalid_grant", "error_description": "Seite ohne Anmeldung" }, "web": "abgemeldet" }
		if konto == "ja":
			_web_geprueft = tok
	_client_token = str(w.get("client", ""))
	_web_version = str(w.get("version", ""))
	return { "ok": true, "code": 200, "data": { "access_token": tok, "token_type": "Bearer", "expires_in": Web.GILT_S + 60 }, "web": "" }


## Gehört der Schlüssel zu einem Konto? "ja" (Name und Kennung stehen dann in _web_me), "nein" (Spotify sagt: kein
## Konto bzw. abgelehnt) oder "?" (keine Antwort – der Schlüssel gilt dann vorerst).
func _web_konto(tok: String, ct: String, version: String) -> String:
	var h := PackedStringArray(["Authorization: Bearer " + tok, "Accept: application/json", "app-platform: WebPlayer",
		"spotify-app-version: " + (version if version != "" else SPOTIFY_CLIENT_VERSION), "Origin: https://open.spotify.com"])
	if ct != "":
		h.append("client-token: " + ct)
	var payload := { "operationName": "profileAttributes", "variables": {},
		"extensions": { "persistedQuery": { "version": 1, "sha256Hash": str(Intern.HASHES.profileAttributes) } } }
	var r := await _netz(HTTPClient.METHOD_POST, _partner, payload, h, true)
	var urteil := web_konto_urteil(int(r.get("code", 0)), r.get("data"))
	if urteil == "ja":
		var prof := Intern.dict(Intern.dig(r.data, "data/me/profile"))
		_web_me = { "id": Intern.s(prof.get("username")), "name": Intern.s(prof.get("name")) }
		if _pf_off == "gemerkt":
			# pathfinder hat eben geantwortet: Die gemerkte Ablehnung entscheidet nicht mehr allein. Die nächste Anfrage
			# geht einzeln hinaus (_pathfinder) – lehnt Spotify ab, gilt der Grundmodus wieder; sonst ist er vergessen.
			_pf_off = ""
			_log("Grundmodus (gemerkt): Spotify antwortet – die nächste Anfrage prüft einzeln")
	elif urteil == "?":
		# pathfinder sagt nichts Klares (Hash veraltet, gebremst): die Web-API fragen (/me: 200 mit Kennung oder 401).
		var r2 := await _netz(HTTPClient.METHOD_GET, _api_base + "/me", null, PackedStringArray(["Authorization: Bearer " + tok, "Accept: application/json"]), true)
		var d2: Dictionary = r2.data if r2.get("data") is Dictionary else {}
		if int(r2.get("code", 0)) == 200 and str(d2.get("id", "")) != "":
			urteil = "ja"
			_web_me = { "id": str(d2.get("id", "")), "name": str(d2.get("display_name", "")) if d2.get("display_name") != null else "" }
		elif int(r2.get("code", 0)) == 401:
			urteil = "nein"
	_log("Spotify-Sitzung: Konto %s (HTTP %d)" % [urteil, int(r.get("code", 0))])
	return urteil


## Antwort auf profileAttributes → "ja" (Konto mit Kennung), "nein" (401 oder ausdrücklich ohne Konto), "?" (sonst).
static func web_konto_urteil(code: int, data: Variant) -> String:
	if code == 401:
		return "nein"
	if code != 200 or not (data is Dictionary):
		return "?"
	var prof: Variant = Intern.dig(data, "data/me/profile")
	if prof is Dictionary and Intern.s((prof as Dictionary).get("username")) != "":
		return "ja"
	var me_v: Variant = Intern.dig(data, "data/me")
	if (data as Dictionary).has("data") and (me_v == null or (me_v is Dictionary and (me_v as Dictionary).get("profile") == null)):
		return "nein"
	return "?"


func _ensure_token() -> bool:
	var m := login_mode()
	if m != _tok_mode:
		_token = ""
		_tok_mode = m
	if _token != "" and Time.get_unix_time_from_system() < _token_until:
		return true
	if m == "":
		return false
	# Die Spotify-Sitzung gab eben keinen Schlüssel: bis zum nächsten Versuch nicht wieder den Kern starten.
	if m == "app" and Time.get_unix_time_from_system() < _web_aus_bis:
		return false
	var r := await _refresh(m)
	if r.get("none", false):
		return false
	if not r.ok:
		if m == "app" and not app_ready() and login_mode() != "":
			# Ein anderer Abruf, der auf dieselbe Erneuerung gewartet hat, hat schon aufgeräumt.
			return await _ensure_token()
		if m == "app" and str(r.get("web", "")) == "anmeldung":
			return false
		if m == "app" and int(r.code) == 0:
			# Kein Schlüssel von der Seite (Kern startet nicht, Seite geändert, kein Netz): Grundmodus, kurz.
			_web_aus_bis = int(Time.get_unix_time_from_system()) + 600
			return await _app_reject("Spotify-Sitzung ohne Schlüssel (%s)" % str(r.get("web", "?")), false, 600, false)
		_log("Anmeldung erneuern%s: HTTP %d %s" % [" (Spotify-Sitzung)" if m == "app" else "", int(r.code), _brief(r.get("data"))])
		if int(r.code) in [400, 401]:
			if m == "app":
				# Die Seite ist abgemeldet (Spotify hat die Sitzung beendet): neu anmelden nötig.
				Config.set_value("accounts.spotify_web", false)
				return await _app_reject("Sitzung beendet (%s)" % _brief(r.get("data")), true)
			# Seit Juli 2026 beendet Spotify Anmeldungen nach sechs Monaten (invalid_grant).
			_set_problem("abgelaufen")
			error = problem_text("abgelaufen")
		else:
			error = "Spotify ist gerade nicht erreichbar."
		return false
	_store_token(r.data, m)
	error = ""
	if problem == "abgelaufen":
		_set_problem("")
	return true


## Die Anmeldung mit Spotify geht gerade nicht (mehr): mit eigener Client-ID weiter, sonst Grundmodus bzw. ein
## ruhiger Hinweis, sich neu anzumelden. Höchstens einmal je pause Sekunden, ohne Meldungs-Flut.
## dead: die Sitzung ist weg (neu anmelden nötig). merken: den Grundmodus über einen Neustart merken (Spotify
## lässt den Weg nicht zu) – nicht bei einem Ausfall der Sitzung. Gibt zurück, ob jetzt ein Schlüssel da ist.
func _app_reject(why: String, dead := false, pause := 1800, merken := true) -> bool:
	_log("Mit Spotify angemeldet: " + why)
	_token = ""
	_app_off_until = int(Time.get_unix_time_from_system()) + pause
	if own_ready():
		var first := app_note == ""
		app_note = "Spotify-Anmeldung gerade nicht nutzbar. Eigene Spotify-App wird genutzt."
		if dead:
			_quiet_mode = true
			Config.set_value("accounts.spotify_mode", "eigen")
			_quiet_mode = false
			app_note = "Spotify-Anmeldung abgelaufen. Neu anmelden unter Einstellungen → Konten."
		_log("Weiter mit der eigenen Client-ID")
		if first:
			Toasts.show_toast("Spotify: eigene App übernimmt", app_note, "music", { "ms": 5000, "quiet": true })
		spotify_mixes = []
		_fy_at = 0
		updated.emit()
		return await _ensure_token()
	var first2 := app_note == ""
	if dead:
		app_note = "Spotify-Anmeldung abgelaufen. Neu anmelden."
		if first2:
			Toasts.show_toast("Spotify-Anmeldung abgelaufen", "Einstellungen → Konten → Spotify: Mit Spotify anmelden.", "music", { "ms": 5000, "quiet": true })
	else:
		# Kein Fehler, sondern der Grundmodus: Läuft gerade, Steuern und Verlauf gehen weiter.
		app_note = ""
		if merken:
			_grund_merken(true)
		elif problem != "app":
			Toasts.show_toast("Spotify im Grundmodus", "Läuft gerade und Steuern über die Spotify-App am PC.", "music", { "ms": 4000, "quiet": true })
	_set_problem("abgelaufen" if dead else "app")
	error = problem_text(problem) if dead else ""
	return false


## Schlüssel der eigenen Client-ID, solange die App-Anmeldung gilt (Ausweg, wenn Spotify sie bremst).
func _alt_ensure() -> bool:
	if _alt_token != "" and Time.get_unix_time_from_system() < _alt_until:
		return true
	if _tok_mode == "eigen" and _token != "" and Time.get_unix_time_from_system() < _token_until:
		# Der eigene Schlüssel ist schon da: kein zweites Erneuern derselben Anmeldung.
		_alt_token = _token
		_alt_until = _token_until
		return true
	var r := await _refresh("eigen")
	if not r.ok or not (r.data is Dictionary):
		return false
	_alt_token = str(r.data.get("access_token", ""))
	_alt_until = int(Time.get_unix_time_from_system()) + gilt_s(r.data.get("expires_in")) - 60
	if str(r.data.get("refresh_token", "")) != "":
		Config.set_value("accounts.spotify_refresh", str(r.data.refresh_token))
	return _alt_token != ""


# --- Anfragen an die Web-API ---------------------------------------------------------------------

## Abruf bei Spotify. path: Pfad der Web-API oder volle Adresse (spclient). only_app: nur mit der
## App-Anmeldung sinnvoll (Mixe, interne Wege) – kein Ausweichen auf die eigene Client-ID.
## Lesen läuft gebündelt (Spotify-Protokoll vom Nutzer: dieselben ~20 Abfragen jede Sekunde trotz
## 429): Dieselbe Anfrage läuft nur einmal, alle Wartenden bekommen dasselbe Ergebnis; höchstens
## API_SLOTS gleichzeitig, und erst mit freiem Platz wird die gemeinsame Sperrzeit geprüft – so
## gehen nach einem 429 keine schon eingereihten Abfragen mehr hinaus. Eine abgelehnte interne
## Abfrage (spclient 403/404) kommt eine Weile aus dem Gedächtnis, statt jedes Mal neu zu fragen.
func _api(method: int, path: String, payload: Variant = null, only_app := false) -> Dictionary:
	if method != HTTPClient.METHOD_GET:
		return await _api_do(method, path, payload, only_app)
	var key := ("A|" if only_app else "|") + path
	var now_s := int(Time.get_unix_time_from_system())
	var cached: Variant = _fail_cache.get(key)
	if cached is Dictionary and now_s < int((cached as Dictionary).until):
		return ((cached as Dictionary).r as Dictionary).duplicate()
	if _inflight.has(key):
		var box: Dictionary = _inflight[key]
		while not bool(box.done):
			await get_tree().process_frame
		return (box.r as Dictionary).duplicate()
	var mine := { "done": false, "r": {} }
	_inflight[key] = mine
	while _api_busy >= API_SLOTS:
		await get_tree().process_frame
	_api_busy += 1
	var r: Dictionary = {}
	r = await _api_do(method, path, payload, only_app)
	_api_busy -= 1
	# Erst die Wartenden bedienen, dann auswerten: Bräche die Auswertung ab, warteten sie für immer, und diese
	# Abfrage käme bis zum Neustart nie wieder zustande.
	mine.r = r
	mine.done = true
	_inflight.erase(key)
	var hold := fail_hold(Fremd.zahl(r.get("code")), path.begins_with("http"), Fremd.ja(r.get("local")))
	if hold > 0:
		_fail_cache[key] = { "until": int(Time.get_unix_time_from_system()) + hold, "r": r }
	elif Fremd.ja(r.get("ok")):
		_fail_cache.erase(key)
	return r


## Wie lange eine abgelehnte Leseabfrage aus dem Gedächtnis kommt (Sekunden, 0 = gar nicht).
## Nur spclient 403/404: Den Weg gibt Spotify so nicht her (im Protokoll recently-played 404 bei
## jedem Neuaufbau). 429 hält die gemeinsame Sperrzeit (_rate_until) auf, ganz ohne Netz.
static func fail_hold(code: int, internal: bool, local := false) -> int:
	if local or not internal:
		return 0
	return 600 if code in [403, 404] else 0


func _api_do(method: int, path: String, payload: Variant = null, only_app := false) -> Dictionary:
	# Grundmodus: Die Web-API bremst diese Anmeldung ohnehin (429) – gar nicht erst fragen, auch
	# nicht ins Protokoll schreiben. Steuern läuft über Spotify Connect (spclient).
	if _grund_ruht():
		return { "ok": false, "code": 0, "data": null, "why": "app", "local": true }
	# Nimmt Spotify die App-Anmeldung gerade nicht an (und es gibt keine eigene Client-ID): bis zum
	# nächsten Versuch nicht weiter fragen – keine Anfrage-Flut. Danach fragt eine Anfrage allein
	# (wie die erste an pathfinder), die übrigen warten auf ihre Antwort.
	if problem == "app" and login_mode() == "app":
		while _pf_probe:
			await get_tree().process_frame
		if problem == "app" and Time.get_unix_time_from_system() < _app_off_until:
			return { "ok": false, "code": 0, "data": null, "why": "app" }
		if problem == "app":
			_pf_probe = true
			var rp := await _api_send(method, path, payload, only_app)
			_pf_probe = false
			return rp
	return await _api_send(method, path, payload, only_app)


func _api_send(method: int, path: String, payload: Variant, only_app: bool) -> Dictionary:
	if not await _ensure_token():
		return { "ok": false, "code": 0, "data": null, "why": problem if problem != "" else "netz" }
	var app := _tok_mode == "app"
	var t_now := int(Time.get_unix_time_from_system())
	# Spotify hat diesen Schlüssel gebremst (429): bis Retry-After gar nicht wieder damit fragen.
	# Gilt für den eigenen Schlüssel immer und für die App-Anmeldung, wenn es keinen Ausweg gibt –
	# so hört die Anfrage-Flut auf (im echten Protokoll fragte Uzai sonst jede Sekunde weiter).
	# Nur für die Web-API: spclient (volle Adresse) ist ein eigener Dienst und bleibt erreichbar –
	# so kommen die Titel eines Mixes über context-resolve auch, wenn api.spotify.com bremst.
	if t_now < int(_rate_until.get(_tok_mode, 0)) and not path.begins_with("http"):
		return { "ok": false, "code": 429, "data": null, "why": "bremse" }
	# Eigene Obergrenze (gleitend 30 s), bevor Spotify bremst: Lesen wartet, Steuern geht vor.
	if not path.begins_with("http") and not budget_ok(method == HTTPClient.METHOD_GET):
		return { "ok": false, "code": 429, "data": null, "why": "bremse", "local": true }
	# Bremst die Web-API die App-Anmeldung dauerhaft (_app_slow_until), gehen allgemeine Abrufe über
	# die eigene Client-ID – die Anmeldung wie die Spotify-App bleibt gültig.
	if app and not only_app and t_now < _app_slow_until and not path.begins_with("http") and t_now >= int(_rate_until.eigen) and await _alt_ensure():
		var ra := await _send(method, path, payload, _alt_token)
		_text_as_error(ra)
		if ra.ok or int(ra.code) == 204:
			return ra
		if int(ra.code) == 429:
			_rate_hit("eigen", ra)
	var r := await _send(method, path, payload)
	if int(r.code) == 401 and not path.begins_with("http"):
		# Schlüssel unterwegs abgelaufen: einmal erneuern und nochmal – nur, wenn er nicht gerade erst
		# geholt wurde (dann lehnt Spotify die Anmeldung ab, und Erneuern hilft nicht).
		if _stale(_token_ms):
			# Mit Spotify angemeldet: der Seite sagen, dass dieser abgelehnt ist – sonst gibt sie denselben
			# abgelaufenen noch einmal heraus, die zweite 401 folgt, und Uzai hält die Anmeldung für abgelehnt (PC, 13.11.).
			if _tok_mode == "app":
				web_sitzung().schluessel_verwerfen(_token)
			_token = ""
			if await _ensure_token():
				r = await _send(method, path, payload)
		if app and int(r.code) == 401 and _tok_mode == "app":
			if await _app_401_hit("Web-API lehnt den Schlüssel ab (401)") and _tok_mode == "eigen":
				r = await _send(method, path, payload)
	elif int(r.code) == 429 and not path.begins_with("http"):
		_rate_hit(_tok_mode, r)
	if app and int(r.code) == 429 and not path.begins_with("http"):
		_app_429 += 1
		if _app_429 >= 3 and t_now >= _app_slow_until:
			_app_slow_until = t_now + 600
			_log(
					"Spotify-Sitzung: Web-API bremst (429, Retry-After %s) – allgemeine Abrufe 10 Min. über die eigene Client-ID%s" % [Net.header(r, "Retry-After"), ""
					if own_ready() else " (keine eingerichtet)"])
		if not only_app and not path.begins_with("http") and own_ready() and t_now >= int(_rate_until.eigen) and await _alt_ensure():
			var rb := await _send(method, path, payload, _alt_token)
			if rb.ok or int(rb.code) == 204:
				return rb
			if int(rb.code) == 429:
				_rate_hit("eigen", rb)
	if (r.ok or int(r.code) == 204) and not path.begins_with("http"):
		_rate_strikes[_tok_mode] = 0
	if app and (r.ok or int(r.code) == 204):
		_app_401 = 0
		_app_429 = 0
	elif app and int(r.code) == 429 and _pf_off != "":
		await _app_blocked_check()
	_text_as_error(r)
	if not r.ok and int(r.code) != 204:
		var why := classify(int(r.code), r.get("data"))
		# Selbst das eigene Konto (/me) abgelehnt, ohne erkennbaren Grund: dann liegt es am Konto
		# oder an der App im Spotify-Dashboard, nicht an einzelnen Listen.
		if why == "" and int(r.code) == 403 and path.get_slice("?", 0) == "/me":
			why = "gesperrt"
		# Wie die Spotify-App gibt es kein Dashboard: Ablehnungen des Kontos heißen dann „app“, ebenso
		# eine 401 trotz frisch erneuerter Anmeldung (abgelaufen ist sie dann nicht).
		if _tok_mode == "app" and (why in ["nutzer", "premium", "gesperrt"] or (int(r.code) == 401 and not path.begins_with("http"))):
			why = "app"
		r["why"] = why
		_log("%s %s → HTTP %d %s" % [_method_name(method), path.get_slice("?", 0).replace(_spclient, "spclient"), int(r.code), _brief(r.get("data"))])
		# Lehnt Spotify das Lesen grundsätzlich ab, ist es kein einzelner Fehler, sondern das Konto.
		# (Nicht bei den inoffiziellen Wegen: lehnt etwa spclient ab, gilt die Anmeldung trotzdem.)
		if method == HTTPClient.METHOD_GET and not only_app and why in ["nutzer", "premium", "abgelaufen", "gesperrt"]:
			_set_problem(why)
		elif method == HTTPClient.METHOD_GET and why == "app" and int(r.code) == 403 and not only_app and path.get_slice("?", 0) == "/me":
			await _app_reject("Konto abgelehnt (HTTP %d)" % int(r.code))
	elif r.ok and method == HTTPClient.METHOD_GET and problem != "" and not only_app:
		_set_problem("")
	return r


## Spotify bremst (429): bis Retry-After nicht wieder mit demselben Schlüssel fragen – jede weitere
## Anfrage verlängert die Sperre, bei der eigenen Client-ID bis zu „QUOTA_EXCEEDED“ für Stunden.
## Die Pause gilt für den eigenen Schlüssel immer (sein Kontingent ist knapp) und für die
## App-Anmeldung nur, wenn es keine eigene Client-ID als Ausweg gibt (sonst übernimmt die, und die
## Anmeldung wie die Spotify-App bleibt – siehe _app_slow_until). Mindestens 10 s, höchstens 1 h.
func _rate_hit(kind: String, r: Dictionary) -> void:
	var now_s := int(Time.get_unix_time_from_system())
	var ra := int(Net.header(r, "Retry-After")) if Net.header(r, "Retry-After").is_valid_int() else 30
	if not (kind == "eigen" or (kind == "app" and not own_ready())):
		return
	if now_s >= int(_rate_until.get(kind, 0)):
		_rate_strikes[kind] = int(_rate_strikes.get(kind, 0)) + 1
		var wait := rate_wait(ra, int(_rate_strikes[kind]))
		_rate_until[kind] = now_s + wait
		_log(
				"Spotify bremst (%s): %d s Pause%s" % ["Spotify-Sitzung" if kind == "app" else "eigene App", wait, " – " + _brief(r.get("data"))
				if r.get("data") != null else ""])
	if kind == "app" and not own_ready() and problem != "app":
		app_note = "Spotify bremst gerade. Bibliothek und Suche kommen etwas später."


## Pause nach einem 429: Retry-After (mindestens 10 s), ab dem zweiten 429 in Folge jedes Mal
## doppelt so lang, höchstens 15 Minuten. Nach dem Ende der Pause fragte Uzai sonst sofort wieder
## alles ab und lief gleich in die nächste Bremse (so im Protokoll des Nutzers).
static func rate_wait(retry_after: int, strikes: int) -> int:
	var base := clampi(retry_after, 10, 3600)
	return mini(base * int(pow(2, clampi(strikes - 1, 0, 6))), maxi(base, 900))


## Wie die Spotify-App: pathfinder lehnt ab (403) und die Web-API bremst (429) – dann ist der
## inoffizielle Weg für Bibliothek und Mixe gerade zu. Einmal ehrlich sagen und die Abfragen ruhen
## lassen (problem "app"); Spotify Connect und die Mediensitzung von Windows laufen weiter.
func _app_blocked_check() -> void:
	if _tok_mode != "app" or _pf_off == "" or problem == "app":
		return
	if int(_rate_strikes.get("app", 0)) > 0 or _app_429 > 0 or int(Time.get_unix_time_from_system()) < int(_rate_until.get("app", 0)):
		await _app_reject("Spotify lässt den Weg des Webplayers nicht zu (pathfinder 403: %s) und bremst die Web-API (429)" % _pf_off)


# --- Was Spotify gerade nicht lässt (problem) ----------------------------------------------------

## Warum Spotify ablehnt (aus Code und Fehlertext): "freigabe" (der Anmeldung fehlt eine
## Freigabe), "nutzer" (Konto steht nicht unter „User Management“ der eigenen App), "premium"
## (Besitzer der App ohne Premium), "abgelaufen" (Anmeldung ungültig), "bremse" (zu viele
## Anfragen), "netz" (keine Antwort) oder "" (etwas anderes, etwa eine fremde Playlist).
static func classify(code: int, data: Variant) -> String:
	if code == 0:
		return "netz"
	if code == 429:
		return "bremse"
	var msg := ""
	if data is Dictionary:
		var e: Variant = (data as Dictionary).get("error")
		if e is Dictionary:
			msg = str((e as Dictionary).get("message", ""))
		elif e is String:
			msg = str(e) + " " + str((data as Dictionary).get("error_description", ""))
	msg = msg.to_lower()
	if msg.contains("scope"):
		return "freigabe"
	if msg.contains("not be registered") or msg.contains("not registered") or msg.contains("user management") or msg.contains("developer.spotify.com/dashboard"):
		return "nutzer"
	if code == 403 and msg.contains("premium"):
		return "premium"
	if code == 401 or msg.contains("invalid_grant") or msg.contains("revoked"):
		return "abgelaufen"
	return ""


## Ein Satz zum Grund, mit dem man etwas anfangen kann.
static func problem_text(why: String) -> String:
	match why:
		"nutzer":
			return "Spotify lässt dein Konto nicht in deine Spotify-App. Auf developer.spotify.com → Dashboard → deine App → „User Management“ dich mit Namen und der E-Mail deines Spotify-Kontos eintragen. Danach geht es sofort."
		"premium":
			return "Spotify sperrt deine Spotify-App: Seit 2026 braucht ihr Besitzer (dein Konto auf developer.spotify.com) ein aktives Premium-Abo. Nach dem Abschluss kann es bis zu einer Stunde dauern."
		"gesperrt":
			return "Spotify lehnt dein Konto ab (Fehler 403), ohne Grund zu nennen. Auf developer.spotify.com → Dashboard → deine App prüfen: 1. Unter „User Management“ steht dein Konto mit genau der E-Mail, mit der du dich in Uzai angemeldet hast. 2. Das Konto, dem die App gehört, hat Premium (nach Abschluss bis zu einer Stunde warten). 3. Unter „Settings“ ist „Web API“ angehakt. Danach hier „Nochmal prüfen“."
		"abgelaufen":
			return "Die Anmeldung bei Spotify ist abgelaufen (Spotify beendet sie nach sechs Monaten). Einmal neu verbinden."
		"app":
			return "Bibliothek und Suche gerade nicht erreichbar. Läuft gerade und Steuern gehen weiter."
		"freigabe":
			return "Dafür fehlt Uzai eine Freigabe von Spotify."
		"bremse":
			return "Spotify bremst gerade (zu viele Anfragen). Gleich nochmal versuchen."
		"netz":
			return "Spotify ist gerade nicht erreichbar."
	return ""


## Grund einer abgelehnten Antwort als Satz; sonst der Ersatztext (den Code nennt das Protokoll).
func why_text(r: Dictionary, fallback: String) -> String:
	var t := problem_text(str(r.get("why", "")))
	if t != "":
		return t
	return tr(fallback) + " " + tr("Gleich noch einmal versuchen.")


## Hilft eine neue Anmeldung? Nur wenn die letzte Anmeldung weniger Freigaben angefragt hat als
## Uzai heute. Hat Spotify trotz Anfrage etwas nicht freigegeben, ändert Neu-Anmelden nichts.
func relogin_helps() -> bool:
	if _tok_mode == "app":
		return false
	var asked := str(Config.get_value("accounts.spotify_scopes_asked", ""))
	if asked != "":
		return asked != SCOPES
	# Anmeldungen vor 0.7.1 haben das nicht notiert: Uzai 0.7 hat schon alles angefragt, und
	# eine solche Anmeldung erkennt man an einer der neuen Freigaben.
	var have := _scopes.split(" ")
	return not (have.has("user-top-read") or have.has("user-follow-read"))


func _set_problem(kind: String) -> void:
	if kind == problem:
		return
	problem = kind
	_log("Zustand: " + (kind if kind != "" else "ok"))
	updated.emit()
	lists_changed.emit("problem")


# --- Protokoll und kleine Hilfen -----------------------------------------------------------------

## Kurzfassung einer Fehlerantwort für Protokoll und Hinweise (ohne Zugangsdaten).
## Hat Spotify die Ablehnung als reinen Text geschickt (etwa „the user may not be registered“),
## wird daraus ein Fehler wie sonst auch – damit Uzai den Grund erkennt und anzeigt.
static func _text_as_error(r: Dictionary) -> void:
	if r.get("data") == null and str(r.get("text", "")) != "" and int(r.get("code", 0)) >= 400:
		r["data"] = { "error": { "status": int(r.code), "message": str(r.text) } }


static func _brief(data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	var d: Dictionary = data
	var e: Variant = d.get("error")
	var out := ""
	if e is Dictionary:
		out = str((e as Dictionary).get("message", ""))
		if (e as Dictionary).get("reason") != null:
			out += " [%s]" % str((e as Dictionary).reason)
	elif e is String:
		out = str(e)
		if d.get("error_description") != null:
			out += ": " + str(d.error_description)
	return out.strip_edges().left(180)


static func _method_name(m: int) -> String:
	return { HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_DELETE: "DELETE" }.get(m, "?")


## Protokoll (logs/spotify.log im Datenordner), ohne Zugangsdaten: was Spotify abgelehnt hat.
var _last_log := ""


func _log(text: String) -> void:
	if demo() or text == _last_log:
		return
	_last_log = text
	Logdatei.zeile(Config.path("logs/spotify.log"), text, 300000)


## Passt noch eine Anfrage an die Web-API in die Obergrenze? read: nur lesend (die knappere Grenze).
func budget_ok(read: bool) -> bool:
	var now_ms := Time.get_ticks_msec()
	while not _budget.is_empty() and now_ms - int(_budget[0]) > BUDGET_WINDOW_MS:
		_budget.pop_front()
	var ok := _budget.size() < (BUDGET_READ if read else BUDGET_ALL) * _budget_scale
	if not ok and now_ms - _budget_logged > 60000:
		_budget_logged = now_ms
		_log("Obergrenze erreicht (%d Anfragen in 30 s) – Uzai wartet kurz, damit Spotify nicht bremst" % _budget.size())
	return ok


func _send(method: int, path: String, payload: Variant, tok := "") -> Dictionary:
	if not path.begins_with("http"):
		_budget.append(Time.get_ticks_msec())
	var h := PackedStringArray(["Authorization: Bearer " + (tok if tok != "" else _token)])
	var url := path if path.begins_with("http") else _api_base + path
	if path.begins_with("http"):
		h.append("Accept: application/json")
	# Der Schlüssel der Seite geht über die Seite; der eigene (tok, eigene Client-ID) direkt.
	return await _netz(method, url, payload, h, tok == "" and _tok_mode == "app")


# --- Ein Weg für alle Anfragen ---------------------------------------------------------------------

## Alle Anfragen an Spotify laufen hier durch. seite: die Anfrage trägt den Schlüssel der Spotify-Sitzung – dann
## fragt der Kern IN der angemeldeten Webplayer-Seite (spotify_web.gd abfrage), mit den Kopfzeilen der Seite, statt
## Uzais eigener HTTP-Client (den lehnte pathfinder am PC des Nutzers mit 403 ab: anderer Client-Fingerabdruck).
## Was die Regeln der Brücke nicht zulassen (PUT der Web-API, fremde Dienste) und die eigene Client-ID gehen direkt.
## Antwort wie Net.get_json/send_json: { ok, code, data, text, headers }.
func _netz(method: int, url: String, payload: Variant, headers: PackedStringArray, seite: bool) -> Dictionary:
	var weg := _seite_weg(method, url) if seite else {}
	if not weg.is_empty():
		var inhalt := "" if payload == null else JSON.stringify(payload)
		var verbindung := Net.header({ "headers": headers }, "X-Spotify-Connection-Id")
		if BP.spotify_abfrage_grund(weg.ziel, weg.methode, weg.pfad, inhalt, verbindung) == "":
			var a: Dictionary = await web_sitzung().abfrage(weg.ziel, weg.methode, weg.pfad, inhalt, verbindung)
			return await _seite_antwort(method, a)
	if method == HTTPClient.METHOD_GET:
		return await Net.get_json(url, headers)
	return await Net.send_json(url, method, payload, headers)


## Geht diese Adresse über die Seite? { ziel, methode, pfad } oder {} (direkt). Nur, wenn die Brücke da ist.
func _seite_weg(method: int, url: String) -> Dictionary:
	if demo() or not web_sitzung().bruecke():
		return {}
	var m: String = { HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_PUT: "PUT" }.get(method, "")
	if m == "":
		return {}
	if url == _partner:
		return { "ziel": "pathfinder", "methode": m, "pfad": BP.PATHFINDER_PFAD }
	if url.begins_with(_spclient + "/"):
		return { "ziel": "spclient", "methode": m, "pfad": url.substr(_spclient.length()) }
	if url.begins_with(_api_base + "/"):
		return { "ziel": "webapi", "methode": m, "pfad": "/v1" + url.substr(_api_base.length()) }
	return {}


## Antwort der Seite in der Form von Net.get_json/send_json. Der Text wird nur als JSON gelesen (nie ausgeführt);
## eine gekürzte Antwort zählt als nicht lesbar.
func _seite_antwort(method: int, a: Dictionary) -> Dictionary:
	var code := int(a.get("code", 0))
	var text := str(a.get("text", ""))
	var data: Variant = null
	if text != "" and not bool(a.get("gekuerzt", false)):
		data = await Net.parse_json(text.to_utf8_buffer())
	var ok := code >= 200 and code < 300
	if method == HTTPClient.METHOD_GET:
		ok = ok and data != null
	var h := PackedStringArray()
	if int(a.get("warte", 0)) > 0:
		h.append("Retry-After: %d" % int(a.warte))
	return { "ok": ok, "code": code, "data": data, "text": "" if data != null else text.strip_edges().left(400), "headers": h,
		"seite": str(a.get("grund", "")) }


## Zufall für Kennungen und Prüfwerte aus dem sicheren Zufall des Betriebssystems (nie randi()).
static func _hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(ceili(n / 2.0)).hex_encode().left(n)


static func _random(n: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var s := ""
	var crypto := Crypto.new()
	while s.length() < n:
		for b in crypto.generate_random_bytes(n * 2):
			# 248 = 4 × 62: darüber verwerfen, sonst kämen manche Zeichen öfter vor.
			if b < 248 and s.length() < n:
				s += chars[b % 62]
	return s

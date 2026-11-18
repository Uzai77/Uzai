extends Node
## Discord-Direktnachrichten und die persönliche Discord-Freundesliste – über das offizielle
## Discord Social SDK (discord_partner_sdk.dll). Uzai holt dafür nie die Discord-App nach vorn:
## Der Windows-Helfer spricht das SDK direkt an (helper/uzai-helper.ps1, UzDsdk), hier liegt
## alles Übrige. Nach außen dieselbe Form wie SteamChat (history, send, messages …), damit die
## Chat-Ansicht beide bedienen kann.
##
## Einrichtung: dieselbe Discord-App wie für den Sprachkanal (App-ID + Client-Secret), dazu im
## Entwicklerportal der App das Social SDK einschalten; discord_partner_sdk.dll liegt im Windows-Paket
## neben Uzai.exe (sonst einmal aus dem SDK-Download dorthin legen). Der Helfer lädt sie nur mit
## gültiger Signatur von Discord Inc. (UzDsdk.SignedByDiscord). Der Zugang kommt aus der Freigabe des Sprachkanals,
## erweitert um die Rechte für Nachrichten (Voice.extra_scopes) – Discord fragt einmal neu.
## Klappt das über die Discord-App nicht, gibt es die Freigabe des SDK selbst (Browser, einmal).
##
## Wer online kommt oder ein Spiel startet, meldet das SDK als Ereignis (UserUpdated → „user“):
## Uzai holt die Freundesliste dann kurz danach neu – viele Meldungen auf einmal (beim Verbinden
## kommt eine je Freund) ergeben eine Abfrage. Zur Sicherheit fragt Uzai zusätzlich im Menü jede
## Minute nach, im Spiel alle drei Minuten.
## Offene Freundschaftsanfragen (requests_in/requests_out) kommen mit derselben Liste;
## answer_request nimmt eine an oder lehnt sie ab – nur auf Knopfdruck.

signal changed                                       ## Zustand, Freunde oder Ungelesenes
signal messages(friend_id: String)                   ## neue Nachricht in diesem Gespräch
signal typing_changed(friend_id: String, on: bool)   ## meldet das SDK nicht; nur der Form halber

const Logdatei := preload("res://src/core/logdatei.gd")
const DcActivity := preload("res://src/core/discord_activity.gd")
const Zustand := preload("res://src/core/zustand.gd")
const DLL := "discord_partner_sdk.dll"
const BASE_SCOPES := "openid sdk.social_layer"
const TOKEN_URL := "https://discord.com/api/oauth2/token"
const SDK_REDIRECT := "http://127.0.0.1/callback"
const FRIENDS_SECS := 60.0        ## Nachfragen im Menü (im Spiel jedes dritte Mal)
const FRIENDS_DEBOUNCE := 0.4     ## Meldungen des SDK so lange sammeln
## So lange darf „verbinde“ nach angenommenem Zugang dauern, bis das SDK „bereit“ meldet. Danach „fehler“ (in den
## Einstellungen mit „Neu verbinden“) statt für immer „Verbindet …“; ein spätes „bereit“ gilt trotzdem.
var verbinde_secs := 45.0

## Nachrichten über das Social SDK: aus · keine_dll (Bibliothek fehlt) · freigabe (Discord muss Nachrichten einmal
## erlauben) · verbinde · bereit · fehler. Neu verbinden (restart) führt über „aus“; „bereit“ meldet das SDK selbst.
const ZUSTAENDE := { "*": ["aus"], "aus": ["verbinde", "keine_dll", "bereit"], "keine_dll": ["verbinde"],
	"verbinde": ["freigabe", "bereit", "fehler"], "freigabe": ["verbinde", "bereit", "fehler"], "bereit": ["fehler"],
	"fehler": ["verbinde", "freigabe", "keine_dll", "bereit"] }
var state := "aus":
	set(neu):
		Zustand.wechsel("discord.nachrichten", ZUSTAENDE, state, neu)
		state = neu
var error := ""
var friends: Array = []          ## [{ id, name, username, avatar, state, streaming, game, details, music, artist, since }]
var requests_in: Array = []      ## Freundschaftsanfragen an dich (wie friends, aus dem SDK)
var requests_out: Array = []     ## von dir gesendete Anfragen
var me_id := ""
var unread := {}                 ## Freund-ID -> Anzahl
var scopes := BASE_SCOPES        ## laut SDK (GetDefaultCommunicationScopes)
var version := ""
var demo := false
## Gespräch, das gerade offen ist (keine Meldung, kein Ungelesen). Stand „chat.discord“ für Zustand.lage() und den
## Fehlerbericht: zu · offen · zu_sehen bzw. verdeckt (so stand es bei der letzten Nachricht, siehe chat_in_view).
var open_chat := "":
	set(neu):
		if neu != open_chat:
			Zustand.melden("chat.discord", "zu" if neu == "" else "offen")
		open_chat = neu
var open_view: WeakRef = null    ## dessen Ansicht (chat_view); zählt nur, solange sie zu sehen ist
var last_at := {}                ## Freund-ID -> Zeit (Unix) seiner letzten Nachricht (Guide: Neue oben)

var _hist := {}                  ## Freund-ID -> [{ id, me, text, at, ordinal }] (älteste zuerst)
var _loaded := {}                ## Freund-ID -> Verlauf schon von Discord geholt
var _started := false
var _browser_auth := false       ## Freigabe über das SDK läuft gerade
var _browser_auth_ms := 0        ## … seit wann (ms)
## So lange gilt ein zweiter Druck auf „Freigeben“ als derselbe; danach darf man es noch einmal versuchen.
const FREIGABE_NEU_MS := 30000
var _demo_reply_n := 0
## Zum Testen austauschbar: (Befehl, Argumente, Wartezeit) -> { ok, result, error }.
var runner: Callable
var friends_calls := 0           ## Abfragen der Freundesliste (für Tests)
var _friends_busy := false
var _friends_again := false
var _friends_queued := false
var _friends_sig := ""
var _friends_tick := 0
var _friends_timer: Timer
var _stand_nr := 0               ## zählt jeden Wechsel über _state_to (eine Frist gilt nur für ihren Stand)


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	runner = Helper.run
	Helper.dsdk_event.connect(_on_event)
	Voice.channel_messages.connect(_on_channel_messages)
	Voice.token_changed.connect(func() -> void:
		if _started and state in ["freigabe", "fehler", "verbinde"]:
			_connect_token()
	)
	Config.changed.connect(func(k: String) -> void:
		if k == "accounts.discord_dm":
			restart()
	)
	_friends_timer = Timer.new()
	_friends_timer.wait_time = FRIENDS_SECS
	_friends_timer.timeout.connect(_friends_poll)
	add_child(_friends_timer)
	_friends_timer.start()
	start.call_deferred()


# --- Einrichtung ---------------------------------------------------------------------------

## Will der Nutzer Discord-Nachrichten (an, sobald die Bibliothek da ist)?
func wanted() -> bool:
	# Ohne Client-Secret geht es mit PKCE (Public Client, so auch Uzais eingebaute App).
	return bool(Config.get_value("accounts.discord_dm", true)) and Voice.client_id() != ""


## Wo die Bibliothek liegt ("" wenn nirgends): neben Uzai.exe, im Datenordner, oder aus einem
## SDK-Download (DiscordSocialSdk-….zip) neben Uzai.exe, den Uzai dann einmal auspackt.
func dll_path() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	for p in [exe_dir.path_join(DLL), Config.path("discord").path_join(DLL)]:
		if FileAccess.file_exists(p):
			return p
	var zip := _find_zip(exe_dir)
	if zip != "":
		return _unpack(zip)
	return ""


static func _find_zip(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		if f.to_lower().begins_with("discordsocialsdk") and f.to_lower().ends_with(".zip"):
			return dir.path_join(f)
	return ""


## Die Windows-Bibliothek aus dem SDK-Download holen (lib/release/discord_partner_sdk.dll).
func _unpack(zip: String) -> String:
	var z := ZIPReader.new()
	if z.open(zip) != OK:
		return ""
	var want := ""
	for f in z.get_files():
		var low := f.to_lower()
		if low.ends_with("/" + DLL) and low.contains("release") and not low.contains("debug"):
			want = f
			break
	if want == "":
		for f in z.get_files():
			if f.to_lower().ends_with("/" + DLL):
				want = f
				break
	if want == "":
		z.close()
		return ""
	var out := Config.path("discord").path_join(DLL)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var fa := FileAccess.open(out, FileAccess.WRITE)
	if fa:
		fa.store_buffer(z.read_file(want))
		fa.close()
	z.close()
	log_line("Bibliothek aus %s ausgepackt" % zip.get_file())
	return out


## Hat der Zugang die Rechte für Nachrichten?
func has_scopes(granted: String) -> bool:
	var have := granted.split(" ", false)
	for s in scopes.split(" ", false):
		if not have.has(s):
			return false
	return true


func logged_in() -> bool:
	return demo or state == "bereit"


func can_send() -> bool:
	return logged_in()


func account_name() -> String:
	return "Discord"


## Was in den Einstellungen steht (kurz).
func status_text() -> String:
	match state:
		"bereit":
			return "Verbunden"
		"keine_dll":
			return "Bibliothek fehlt"
		"freigabe":
			return "Einmal freigeben"
		"verbinde":
			return "Verbindet …"
		"fehler":
			return "Fehler"
	return "Aus"


# --- Start und Zugang -------------------------------------------------------------------------

func restart() -> void:
	if _started and not demo:
		await runner.call("dsdk-stop", {}, 3.0)
	_started = false
	_browser_auth = false
	_stand_nr += 1
	state = "aus"
	friends = []
	_friends_sig = ""
	await start()


func start() -> void:
	if demo:
		_load_demo()
		return
	if not Config.is_windows() and Config.probe_env("UZAI_HELPER_SHELL") == "":
		return
	if not wanted():
		_state_to("aus", "")
		_want_scopes(false)
		return
	var dll := dll_path()
	if dll == "":
		_state_to("keine_dll", "Für Discord-Nachrichten fehlt die Datei %s neben Uzai.exe (aus dem Discord Social SDK)." % DLL)
		_want_scopes(false)
		return
	_state_to("verbinde", "")
	var r: Dictionary = await runner.call("dsdk-start", { "dll": dll.replace("/", "\\") if Config.is_windows() else dll, "app_id": Voice.client_id() }, 20.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if not r.get("ok", false) or not bool(res.get("ok", false)):
		_state_to("fehler", "Das Discord-SDK ließ sich nicht starten: %s" % str(res.get("error", r.get("error", "?"))))
		return
	_started = true
	version = str(res.get("version", ""))
	if str(res.get("scopes", "")) != "":
		scopes = str(res.scopes)
	_want_scopes(true)
	log_line("SDK %s gestartet, Rechte: %s" % [version, scopes])
	await _connect_token()


## Zugang ans SDK geben: der eigene aus der SDK-Freigabe, sonst der des Sprachkanals – wenn er
## die Rechte für Nachrichten hat. Sonst muss einmal freigegeben werden.
func _connect_token() -> void:
	var tok := await _usable_token()
	if tok == "":
		_state_to("freigabe", "Discord muss Uzai einmal Nachrichten erlauben.")
		return
	_state_to("verbinde", "")
	var r: Dictionary = await runner.call("dsdk-token", { "token": tok }, 20.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if not bool(res.get("ok", false)):
		var why := str(res.get("error", r.get("error", "")))
		log_line("Zugang abgelehnt: %s (HTTP %s)" % [why, str(res.get("status", ""))])
		if int(res.get("status", 0)) in [401, 403]:
			_forget_own()
			_state_to("freigabe", "Discord hat den Zugang für Nachrichten nicht angenommen. Bitte einmal neu freigeben.")
		else:
			_state_to("fehler", "Discord-Nachrichten: %s" % (why if why != "" else "keine Verbindung"))
		return
	# Weiter mit dem Ereignis „bereit“ vom SDK – bleibt es aus, nach verbinde_secs „fehler“.
	_bereit_frist()


## Meldet das SDK nach dem Zugang nie „bereit“ (Status 0 zählt nur aus „bereit“ heraus), stünde sonst für immer
## „Verbindet …“ da. Jeder andere Wechsel in der Zeit (bereit, Fehler, Neu verbinden) hebt die Frist auf.
func _bereit_frist() -> void:
	var nr := _stand_nr
	await get_tree().create_timer(verbinde_secs).timeout
	if nr == _stand_nr and state == "verbinde":
		log_line("Kein „bereit“ vom SDK nach %d s" % int(verbinde_secs))
		_state_to("fehler", "Discord hat nicht geantwortet.")


## Ein gültiger Zugang mit Nachrichten-Rechten, wenn nötig vorher erneuert ("" wenn keiner).
func _usable_token() -> String:
	var now := int(Time.get_unix_time_from_system())
	# 1. Eigener Zugang (aus der Freigabe über das SDK).
	if str(Config.get_value("accounts.discord_dm_refresh", "")) != "" or str(Config.get_value("accounts.discord_dm_token", "")) != "":
		if int(Config.get_value("accounts.discord_dm_expires", 0)) < now + 3600:
			await _refresh_own()
		var own := str(Config.get_value("accounts.discord_dm_token", ""))
		if own != "":
			return own
	# 2. Zugang des Sprachkanals, wenn Discord dabei Nachrichten erlaubt hat.
	if has_scopes(str(Config.get_value("accounts.discord_scope", ""))):
		if int(Config.get_value("accounts.discord_expires", 0)) < now + 3600:
			await Voice.refresh_access()
		return str(Config.get_value("accounts.discord_token", ""))
	return ""


## Einmal freigeben: über die Discord-App (wie beim Sprachkanal, mit den Nachrichten-Rechten).
## Lehnt die Discord-App das ab, nimmt Uzai die Freigabe des SDK (Browser).
func authorize() -> void:
	if demo:
		return
	if not _started:
		await start()
	_want_scopes(true)
	if Voice.extra_rejected:
		authorize_browser()
		return
	Voice.authorize()


## Freigabe über das SDK selbst: Discord-Overlay oder Browser. Das Ergebnis kommt als Ereignis.
func authorize_browser() -> void:
	# Meldet das SDK die Freigabe nie zurück (Fenster geschlossen, ohne zu bestätigen), bliebe „läuft“ sonst stehen,
	# und der Knopf täte bis zum Neustart nichts mehr.
	if not _started or (_browser_auth and Time.get_ticks_msec() - _browser_auth_ms < FREIGABE_NEU_MS):
		return
	_browser_auth = true
	_browser_auth_ms = Time.get_ticks_msec()
	_state_to("freigabe", "Bitte im Fenster von Discord bestätigen. Danach geht es hier weiter.")
	var r: Dictionary = await runner.call("dsdk-authorize", { "app_id": Voice.client_id(), "scopes": scopes }, 8.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if not bool(res.get("ok", false)):
		_browser_auth = false
		_state_to("fehler", "Die Freigabe ließ sich nicht öffnen: %s" % str(res.get("error", r.get("error", ""))))


func _on_authorized(res: Dictionary) -> void:
	_browser_auth = false
	# Nach der Freigabe liegt der Browser bzw. Discord vorn: Uzai holt sich den Platz zurück
	# (wie nach der Sprachkanal-Freigabe und der Spotify-Anmeldung).
	if Config.is_windows() and Helper.available and not Launcher.in_game:
		Helper.run("focus", { "pid": OS.get_process_id() })
	if not bool(res.get("ok", false)) or str(res.get("code", "")) == "":
		_state_to("freigabe", "Freigabe abgebrochen (%s)." % str(res.get("error", "")))
		return
	var fields := Voice.token_fields(Voice.client_id(), Voice.client_secret(), str(res.code), str(res.get("verifier", "")),
			str(res.get("redirect", SDK_REDIRECT)))
	var r := await Net.post_form(TOKEN_URL, fields)
	if not r.ok or not (r.data is Dictionary) or str(r.data.get("access_token", "")) == "":
		var why := Voice.token_error(r)
		log_line("Zugang aus der SDK-Freigabe abgelehnt: " + why)
		_state_to("fehler", Voice.explain_token_error(why).replace("http://localhost", SDK_REDIRECT))
		return
	_store_own(r.data)
	_connect_token()


func _refresh_own() -> void:
	var ref := str(Config.get_value("accounts.discord_dm_refresh", ""))
	if ref == "":
		return
	var r := await Net.post_form(TOKEN_URL, Voice.refresh_fields(Voice.client_id(), Voice.client_secret(), ref))
	if r.ok and r.data is Dictionary and str(r.data.get("access_token", "")) != "":
		_store_own(r.data)
	elif int(r.code) in [400, 401]:
		_forget_own()


func _store_own(d: Dictionary) -> void:
	Config.set_value("accounts.discord_dm_token", str(d.get("access_token", "")))
	if str(d.get("refresh_token", "")) != "":
		Config.set_value("accounts.discord_dm_refresh", str(d.refresh_token))
	Config.set_value("accounts.discord_dm_expires", int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 604800)))


func _forget_own() -> void:
	Config.set_value("accounts.discord_dm_token", "")
	Config.set_value("accounts.discord_dm_refresh", "")
	Config.set_value("accounts.discord_dm_expires", 0)


## Die Nachrichten-Rechte bei der Freigabe des Sprachkanals mit anfragen (oder nicht mehr).
## Nur die eigenen ein- bzw. austragen: Mitteilungen (Notify) hängen dort auch ihr Recht an.
func _want_scopes(on: bool) -> void:
	for x in scopes.split(" ", false):
		if on and not Voice.extra_scopes.has(x):
			Voice.extra_scopes.append(x)
		elif not on:
			Voice.extra_scopes.erase(x)


func _state_to(s: String, why: String) -> void:
	_stand_nr += 1
	state = s
	error = why
	changed.emit()


# --- Ereignisse vom SDK -------------------------------------------------------------------------

func _on_event(msg: Variant) -> void:
	if not (msg is Dictionary):
		return
	var m: Dictionary = msg
	match str(m.get("type", "")):
		"status":
			var st := int(m.get("status", 0))
			if st == 3:
				_ready_now()
			elif st == 0 and state == "bereit":
				_state_to("fehler", "Verbindung zu Discord getrennt (%d)." % int(m.get("error", 0)))
		"message":
			if m.get("message") is Dictionary:
				_on_message(m.message)
		"friends", "user":
			refresh_friends_soon()
		"authorized":
			_on_authorized(m.get("result", {}) if m.get("result") is Dictionary else {})
		"log":
			log_line("SDK: " + str(m.get("text", "")))


func _ready_now() -> void:
	var me: Dictionary = await runner.call("dsdk-me", {}, 6.0)
	var res: Dictionary = me.get("result", {}) if me.get("result") is Dictionary else {}
	if res.get("me") is Dictionary:
		me_id = str(res.me.get("id", ""))
	_state_to("bereit", "")
	# Ohne die Konto-Kennung: discord.log teilen Nutzer bei Fehlern.
	log_line("Verbunden" + (" (Konto bekannt)" if me_id != "" else " (Konto unbekannt)"))
	await refresh_friends()


func refresh_friends() -> void:
	if demo or not _started:
		return
	# Läuft schon eine Abfrage: danach genau eine weitere (mit dem neuesten Stand) – nie zwei
	# gleichzeitig, deren ältere Antwort die neuere überschreiben könnte.
	if _friends_busy:
		_friends_again = true
		return
	_friends_busy = true
	friends_calls += 1
	var r: Dictionary = await runner.call("dsdk-friends", {}, 8.0)
	_friends_busy = false
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if bool(res.get("ok", false)):
		var app := Voice.client_id()
		var list := parse_friends(res.get("friends", []), app)
		var rin := parse_friends(res.get("incoming", []), app)
		var rout := parse_friends(res.get("outgoing", []), app)
		# Nur melden, wenn sich etwas geändert hat (Status, Spiel, Name …): Freunde-Bereich,
		# Guide und Zähler oben bauen sonst bei jeder Meldung des SDK neu.
		var sig := JSON.stringify([list, rin, rout])
		if sig != _friends_sig:
			_friends_sig = sig
			friends = list
			requests_in = rin
			requests_out = rout
			changed.emit()
		_prefetch_channels()
	if _friends_again:
		_friends_again = false
		await refresh_friends()


## Eine Meldung des SDK (jemand kommt online, spielt …): kurz sammeln, dann einmal abfragen.
func refresh_friends_soon() -> void:
	if demo or not _started or _friends_queued:
		return
	_friends_queued = true
	await get_tree().create_timer(FRIENDS_DEBOUNCE).timeout
	_friends_queued = false
	await refresh_friends()


## Regelmäßig nachfragen, falls eine Meldung des SDK fehlt; im Spiel sparsam.
func _friends_poll() -> void:
	_friends_tick += 1
	if state != "bereit" or demo:
		return
	if Launcher.in_game and _friends_tick % 3 != 0:
		return
	refresh_friends()


## Freunde aus dem SDK: wer spielt, steht vorn, dann online, abwesend, offline; sonst nach Namen.
## Die Aktivität kommt in Uzais Form (discord_activity.gd): Spieltitel, Zusatz, Musik, seit wann.
## own_app: Uzais Discord-App-ID (erkennt Uzais eigenen Status bei Freunden).
static func parse_friends(list: Variant, own_app := "") -> Array:
	var out: Array = []
	if not (list is Array):
		return out
	for f in list:
		if not (f is Dictionary) or str(f.get("id", "")) == "":
			continue
		var e := { "id": str(f.id), "name": str(f.get("name", f.get("username", "?"))), "username": str(f.get("username", "")),
			"avatar": str(f.get("avatar", "")), "state": str(f.get("state", "offline")), "streaming": bool(f.get("streaming", false)), "dm": true }
		e.merge(DcActivity.normalize(f, own_app))
		out.append(e)
	out.sort_custom(func(a, b) -> bool:
		var ra := _order(a)
		var rb := _order(b)
		return ra < rb if ra != rb else str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return out


static func _order(f: Dictionary) -> int:
	if str(f.state) == "offline":
		return 3
	if str(f.game) != "":
		return 0
	return 1 if str(f.state) == "online" else 2


func friend(id: String) -> Dictionary:
	for f in friends:
		if str(f.id) == id:
			return f
	return {}


## Freundschaftsanfrage an dich annehmen oder ablehnen (Social SDK) – nur auf Knopfdruck.
## "" oder warum nicht. Danach meldet das SDK die geänderte Liste von selbst.
func answer_request(id: String, accept: bool) -> String:
	if not requests_in.any(func(f): return str(f.id) == id):
		return "Diese Anfrage gibt es nicht mehr."
	if demo:
		var f: Dictionary = requests_in.filter(func(x): return str(x.id) == id)[0]
		requests_in = requests_in.filter(func(x): return str(x.id) != id)
		if accept:
			var nf := f.duplicate()
			nf["state"] = "online"
			friends.append(nf)
		changed.emit()
		return ""
	if state != "bereit":
		return "Discord ist gerade nicht verbunden."
	var r: Dictionary = await runner.call("dsdk-accept" if accept else "dsdk-reject", { "id": id }, 12.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if not bool(r.get("ok", false)):
		return "Der Windows-Helfer hat nicht geantwortet."
	if bool(res.get("ok", false)):
		log_line("Anfrage %s %s" % [id, "angenommen" if accept else "abgelehnt"])
		refresh_friends_soon()
		return ""
	var err := str(res.get("error", ""))
	log_line("Anfrage %s: %s" % [id, err])
	if err == "unsupported":
		return "Diese Fassung des Discord Social SDK kann das noch nicht. Eine neuere discord_partner_sdk.dll neben Uzai.exe hilft."
	return "Discord hat abgelehnt (%s)." % err if err != "" else "Discord hat abgelehnt."


## Kanal der Direktnachricht je Freund (aus den Nachrichten des SDK) – zum Anrufen.
var dm_channels := {}


func _note_channel(peer: String, raw: Dictionary) -> void:
	var ch := str(raw.get("channel", ""))
	if ch != "" and ch != "0" and peer != "":
		dm_channels[peer] = ch
		# Eingehende Anrufe in dieser Direktnachricht erkennen (über die Discord-App).
		Voice.watch_dm(ch, peer)


var _prefetched := false


func rewatch() -> void:
	for fid in dm_channels.keys():
		Voice.watch_dm(str(dm_channels[fid]), str(fid))
	# Frisch angemeldet (etwa gerade „Bilder anzeigen“ freigegeben): die Bilder des offenen Gesprächs gleich holen.
	if open_chat != "":
		_medien_ms.erase(open_chat)
		medien_holen(open_chat)
	if not _prefetched:
		_prefetch_channels()


## Einmal nach dem Verbinden: die Gespräche der Freunde kennen (je eine Nachricht), damit Uzai
## Anrufe von ihnen erkennt und anrufen kann. Höchstens 25, die online sind zuerst; still im Hintergrund.
func _prefetch_channels() -> void:
	if _prefetched or demo or state != "bereit" or not Voice.ready_():
		return
	_prefetched = true
	var n := 0
	for f in friends:
		if n >= 25:
			break
		var fid := str(f.id)
		if dm_channels.has(fid):
			Voice.watch_dm(str(dm_channels[fid]), fid)
			continue
		n += 1
		var r: Dictionary = await runner.call("dsdk-history", { "with": fid, "limit": 1 }, 8.0)
		var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
		for raw in res.get("messages", []):
			if raw is Dictionary:
				_note_channel(fid, raw)
		await get_tree().create_timer(0.15).timeout


func _on_message(raw: Dictionary) -> void:
	var m := to_message(raw, me_id)
	var peer := str(raw.get("recipient", "")) if bool(m.me) else str(raw.get("author", ""))
	if peer == "" or peer == "0":
		return
	_note_channel(peer, raw)
	if not _add(peer, m):
		return
	if not bool(m.me):
		last_at[peer] = int(m.at) if int(m.at) > 0 else int(Time.get_unix_time_from_system())
	var zu_sehen := chat_in_view(peer)
	if not bool(m.me) and not zu_sehen:
		unread[peer] = int(unread.get(peer, 0)) + 1
		changed.emit()
	messages.emit(peer)
	if not bool(m.me) and not zu_sehen:
		var f := friend(peer)
		if f.is_empty():
			f = { "id": peer, "name": "Discord", "avatar": "", "dm": true }
		# Mit Anhang: kurz die Adresse über die Discord-App holen – dann steht das Bild klein im Pop-up, nicht „Datei“.
		var bild := ""
		if m.has("anhang") and Voice.granted.has(Voice.MSG_SCOPE):
			bild = await _bild_von(peer, str(m.id))
		Notify.discord_dm(f, nachricht_zeile(m, bild != ""), str(m.id), bild)
	elif m.has("anhang") and zu_sehen:
		# Bild oder Video in der offenen Unterhaltung: kurz warten (Discord braucht einen Moment), dann die Adresse holen.
		await get_tree().create_timer(1.5).timeout
		_medien_ms.erase(peer)
		medien_holen(peer)


## Adresse des ersten Bilds dieser Nachricht über die Discord-App (höchstens gut 3 s warten) – "" ohne.
func _bild_von(peer: String, msg_id: String) -> String:
	await get_tree().create_timer(1.0).timeout
	_medien_ms.erase(peer)
	medien_holen(peer)
	for i in 12:
		if medien.has(msg_id):
			break
		await get_tree().create_timer(0.2).timeout
	for it in medien.get(msg_id, []):
		if str(it.get("art", "")) == "bild":
			return str(it.url)
	return ""


## Zeile fürs Pop-up: der Text; ohne Text, was dran hängt – „Bild“, nie ein nichtssagendes „Datei“.
static func nachricht_zeile(m: Dictionary, hat_bild: bool) -> String:
	if str(m.get("text", "")) != "":
		return str(m.text)
	if hat_bild:
		return tr_static("Bild")
	if m.get("anhang") is Dictionary:
		var a: Dictionary = m.anhang
		return anhang_text(a) if str(a.get("art", "")) != "datei" or str(a.get("titel", "")) != "" else tr_static("Anhang")
	return ""


## Nachricht aus dem SDK in die Form der Chat-Ansicht (Zeit in Sekunden).
static func to_message(raw: Dictionary, my_id: String) -> Dictionary:
	var out := { "id": str(raw.get("id", "")), "me": str(raw.get("author", "")) == my_id and my_id != "",
		"text": str(raw.get("text", "")), "at": int(float(raw.get("sent", 0)) / 1000.0), "ordinal": 0 }
	var an := anhang(raw.get("anhang"))
	if not an.is_empty():
		out["anhang"] = an
	return out


## Attachment of a Discord message (from the helper: kind, title, count). The SDK gives no URL, so Uzai shows a card
## with the kind and file name instead of nothing. {} when there is no attachment. art: bild, video, datei, sprache,
## sticker, umfrage, einbettung, thread.
const Fremd := preload("res://src/core/fremd.gd")
const ANHANG_ARTEN :={ 1: "datei", 2: "umfrage", 3: "sprache", 4: "thread", 5: "einbettung", 6: "sticker" }


static func anhang(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var a := v as Dictionary
	var art := str(ANHANG_ARTEN.get(Fremd.zahl(a.get("art"), 0), ""))
	if art == "":
		return {}
	var titel := Fremd.text(a.get("titel"), "", 120)
	if art == "datei":
		var e := titel.get_extension().to_lower()
		art = "bild" if e in ["png", "jpg", "jpeg", "webp", "gif", "bmp"] else ("video" if e in ["mp4", "webm", "mov", "m4v", "mkv"] else "datei")
		# Bildschirmfotos und eingefügte Bilder kommen oft ohne Namen: nicht „Datei“ nennen, sondern „Anhang“.
		if art == "datei" and titel == "":
			art = "anhang"
	return { "art": art, "titel": titel, "anzahl": clampi(Fremd.zahl(a.get("anzahl"), 1), 1, 99) }


## Bilder und Videos mit Adresse, über die Discord-App (Voice.nachrichten_holen, Recht messages.read): Nachricht → Liste
## [{ url, art (bild|video), name }]. Nur Adressen von Discord selbst (cdn.discordapp.com, media.discordapp.net), nur https.
var medien := {}
const MEDIEN_HOSTS := ["cdn.discordapp.com", "media.discordapp.net"]
var _medien_ms := {}           ## Freund -> wann zuletzt gefragt (Ticks), höchstens alle 20 s
var _medien_fertig := {}       ## Freund -> true: Bilder des Verlaufs in dieser Sitzung schon geholt


## Anhänge der offenen Unterhaltung holen (die Chat-Ansicht ruft das beim Öffnen und bei neuen Nachrichten mit Anhang).
func medien_holen(fid: String) -> void:
	var ch := str(dm_channels.get(fid, ""))
	if ch == "" or Time.get_ticks_msec() - int(_medien_ms.get(fid, -60000)) < 20000:
		return
	if Voice.nachrichten_holen(ch):
		_medien_ms[fid] = Time.get_ticks_msec()


func _on_channel_messages(channel_id: String, list: Array) -> void:
	var fid := ""
	for k in dm_channels.keys():
		if str(dm_channels[k]) == channel_id:
			fid = str(k)
	if fid == "":
		return
	_medien_fertig[fid] = true
	var neu := medien_aus(list)
	var anders := false
	for id in neu.keys():
		if not medien.has(id):
			anders = true
		medien[id] = neu[id]
	Config.cap(medien, 600)
	if anders:
		for m in _hist.get(fid, []):
			if medien.has(str(m.get("id", ""))):
				m["medien"] = medien[str(m.id)]
		messages.emit(fid)


## Rein: Bilder und Videos aus Nachrichten der Discord-App (Anhänge und Einbettungen wie GIFs), geprüft – die Daten
## kommen von anderen Leuten. { Nachrichten-ID: [{ url, art, name }] }.
static func medien_aus(list: Array) -> Dictionary:
	var out := {}
	for msg in list.slice(0, 100):
		if not (msg is Dictionary):
			continue
		var id := Fremd.text(msg.get("id"), "", 24)
		if id == "" or not id.is_valid_int():
			continue
		var items: Array = []
		var anh: Variant = msg.get("attachments", [])
		for a in (anh as Array if anh is Array else []).slice(0, 10):
			if not (a is Dictionary):
				continue
			var url := Fremd.text(a.get("url"), "", 2048)
			var name := Fremd.text(a.get("filename"), "", 120)
			var typ := Fremd.text(a.get("content_type"), "", 80).to_lower()
			var e := name.get_extension().to_lower()
			var art := ""
			if typ.begins_with("image/") or e in ["png", "jpg", "jpeg", "webp", "gif"]:
				art = "bild"
			elif typ.begins_with("video/") or e in ["mp4", "webm", "mov"]:
				art = "video"
			if art != "" and _medien_url_ok(url):
				# GIFs zeigt Godot nicht: Discords Vorschau als PNG (media.discordapp.net rechnet sie um).
				if e == "gif" or typ == "image/gif":
					var prox := Fremd.text(a.get("proxy_url"), "", 2048)
					url = (prox + ("&" if prox.contains("?") else "?") + "format=png") if _medien_url_ok(prox) else ""
				if url != "":
					items.append({ "url": url, "art": art, "name": name })
		var emb: Variant = msg.get("embeds", [])
		for em in (emb as Array if emb is Array else []).slice(0, 5):
			if not (em is Dictionary):
				continue
			var typ2 := Fremd.text(em.get("type"), "", 20)
			if not typ2 in ["image", "gifv", "video"]:
				continue
			var bild: Variant = em.get("thumbnail") if em.get("thumbnail") is Dictionary else em.get("image")
			if bild is Dictionary:
				var u := Fremd.text((bild as Dictionary).get("proxy_url"), "", 2048)
				if _medien_url_ok(u):
					items.append({ "url": u, "art": "bild", "name": "" })
		if not items.is_empty():
			out[id] = items
	return out


static func _medien_url_ok(url: String) -> bool:
	return url.to_lower().begins_with("https://") and not ChatLinkS.mehrdeutig(url) and ChatLinkS.host_of(url) in MEDIEN_HOSTS


const ChatLinkS := preload("res://src/ui/layers/chat_link.gd")


## Kurz in Worten (Mitteilung, Liste der Gespräche): „Bild“, „2 Bilder“, „Video“ …
static func anhang_text(a: Dictionary) -> String:
	var n := int(a.get("anzahl", 1))
	match str(a.get("art", "")):
		"bild": return tr_static("Bild") if n <= 1 else "%d %s" % [n, tr_static("Bilder")]
		"video": return tr_static("Video") if n <= 1 else "%d %s" % [n, tr_static("Videos")]
		"sprache": return tr_static("Sprachnachricht")
		"sticker": return tr_static("Sticker")
		"umfrage": return tr_static("Umfrage")
		"einbettung": return tr_static("Vorschau")
		"thread": return tr_static("Thread")
		"anhang": return tr_static("Anhang") if n <= 1 else "%d %s" % [n, tr_static("Anhänge")]
	return tr_static("Datei") if n <= 1 else "%d %s" % [n, tr_static("Dateien")]


static func tr_static(t: String) -> String:
	return TranslationServer.translate(t)


func _add(peer: String, m: Dictionary) -> bool:
	if medien.has(str(m.get("id", ""))):
		m["medien"] = medien[str(m.id)]
	var list: Array = _hist.get(peer, [])
	for x in list:
		if str(x.id) == str(m.id) and str(m.id) != "":
			return false
	list.append(m)
	list.sort_custom(func(a, b) -> bool: return int(a.at) < int(b.at) or (int(a.at) == int(b.at) and str(a.id) < str(b.id)))
	# Zuletzt benutzte Unterhaltung ans Ende: die Grenze wirft die am längsten ruhenden raus,
	# nie die gerade aktive.
	_hist.erase(peer)
	_hist[peer] = list
	Config.cap(_hist, 100)
	return true


# --- Wie SteamChat ---------------------------------------------------------------------------

func history(friend_id: String, _count := 80, mark_read := true) -> Array:
	if mark_read and unread.has(friend_id):
		unread.erase(friend_id)
		changed.emit()
	if demo:
		return _demo_history(friend_id).duplicate()
	if not _loaded.get(friend_id, false) and state == "bereit":
		var r: Dictionary = await runner.call("dsdk-history", { "with": friend_id, "limit": 100 }, 12.0)
		var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
		if bool(res.get("ok", false)):
			_loaded[friend_id] = true
			for raw in res.get("messages", []):
				if raw is Dictionary:
					_note_channel(friend_id, raw)
					_add(friend_id, to_message(raw, me_id))
			error = ""
		elif int(res.get("status", 0)) == 404:
			# Noch kein Gespräch über eine App: leer ist dann richtig.
			_loaded[friend_id] = true
		else:
			error = "Der Verlauf ließ sich gerade nicht laden."
	var liste: Array = _hist.get(friend_id, [])
	# Fetch the history's images once via the Discord app (they come with messages()), not only when the SDK reports
	# an attachment: for older messages it reports none, so all older images were missing after startup. If the
	# Discord app is not ready yet, the next look at the history (every few seconds) tries again.
	if not _medien_fertig.has(friend_id):
		medien_holen(friend_id)
	return liste.duplicate()


## Discord-Freund anrufen, ohne Discord nach vorn zu holen: Uzai lässt die Discord-App dem
## Sprachanruf der Direktnachricht beitreten (offizielle lokale Schnittstelle, SELECT_VOICE_CHANNEL
## geht laut Discord auch für Direktnachrichten) – das klingelt beim Freund. "" oder Fehlertext.
func call_friend(friend_id: String) -> String:
	if demo:
		return ""
	if not Voice.ready_():
		return "Für Anrufe muss Uzai mit der Discord-App verbunden sein (Einstellungen → Konten → Discord)."
	if not dm_channels.has(friend_id) and state == "bereit":
		_loaded.erase(friend_id)
		await history(friend_id, 20, false)
	if not dm_channels.has(friend_id):
		return "Erst eine Nachricht schreiben, dann anrufen."
	Voice.join(str(dm_channels[friend_id]))
	return ""


func send(friend_id: String, text: String) -> String:
	if demo:
		_add(friend_id, { "id": "d%d" % Time.get_ticks_usec(), "me": true, "text": text, "at": int(Time.get_unix_time_from_system()), "ordinal": 0 })
		messages.emit(friend_id)
		_demo_reply(friend_id)
		return ""
	if state != "bereit":
		return error if error != "" else "Discord-Nachrichten sind noch nicht verbunden (Einstellungen → Konten)."
	var r: Dictionary = await runner.call("dsdk-send", { "to": friend_id, "text": text.left(2000) }, 12.0)
	var res: Dictionary = r.get("result", {}) if r.get("result") is Dictionary else {}
	if bool(res.get("ok", false)):
		return ""
	var why := send_error(int(res.get("status", 0)), str(res.get("error", r.get("error", ""))))
	log_line("Senden fehlgeschlagen: HTTP %s %s" % [str(res.get("status", "")), str(res.get("error", "")).left(120)])
	return why


static func send_error(status: int, text: String) -> String:
	match status:
		403, 50007:
			return "Discord lässt die Nachricht nicht zu: Ihr müsst auf Discord befreundet sein (oder hat die Person Nachrichten blockiert?)."
		429:
			return "Discord bremst: Apps im Testbetrieb dürfen 100 Nachrichten in 2 Stunden schicken. Später nochmal."
		401:
			return "Discord hat den Zugang nicht mehr angenommen. Unter Einstellungen → Konten neu freigeben."
		0:
			return "Discord antwortet gerade nicht." if text == "" else "Discord: " + text
	return "Discord hat die Nachricht nicht angenommen (%d%s)." % [status, (", " + text) if text != "" else ""]


func send_typing(_friend_id: String) -> void:
	pass


func is_typing(_friend_id: String) -> bool:
	return false


## Ist das Gespräch offen und wirklich zu sehen (Notify.chat_seen)? Für das offene Gespräch steht das Ergebnis als
## „chat.discord“ in Zustand.lage(): zu_sehen (gilt als gelesen, kein Pop-up) oder verdeckt (Pop-up).
func chat_in_view(fid: String) -> bool:
	var seen := Notify.chat_seen(open_chat, fid, open_view != null, Notify.view_seen(open_view) if open_view != null else false, true)
	if fid != "" and fid == open_chat:
		Zustand.melden("chat.discord", "zu_sehen" if seen else "verdeckt")
	return seen


## Die Chat-Ansicht ist offen (Discord spielt dann keine doppelten Töne in der App).
func set_open(friend_id: String) -> void:
	open_chat = friend_id
	if not demo and state == "bereit":
		runner.call("dsdk-showing", { "on": friend_id != "" }, 3.0)


func total_unread() -> int:
	var n := 0
	for k in unread:
		n += int(unread[k])
	return n


func log_line(text: String) -> void:
	if demo:
		return
	Logdatei.zeile(Config.path("logs/discord.log"), "Nachrichten: %s" % text, 400000)


# --- Vorführung ---------------------------------------------------------------------------------

func _load_demo() -> void:
	me_id = "999"
	friends = parse_friends([
		{ "id": "1001", "name": "Sana", "username": "sana", "avatar": "", "state": "online", "game": "Uzai", "details": "Shadow of the Colossus",
			"activity_state": "PlayStation 2 · Uzai", "start": (int(Time.get_unix_time_from_system()) - 2580) * 1000 },
		{ "id": "1002", "name": "Kai", "username": "kai", "avatar": "", "state": "online", "game": "Uzai", "type": 2, "details": "To Zanarkand",
			"activity_state": "von Nobuo Uematsu", "start": (int(Time.get_unix_time_from_system()) - 95) * 1000 },
		{ "id": "1003", "name": "Noor", "username": "noor", "avatar": "", "state": "away", "game": "" },
		{ "id": "1004", "name": "Lena", "username": "lena", "avatar": "", "state": "offline", "game": "" },
	])
	unread = { "1002": 1 }
	requests_in = parse_friends([{ "id": "1005", "name": "Tarik", "username": "tarik", "avatar": "", "state": "offline", "game": "" }])
	requests_out = parse_friends([{ "id": "1006", "name": "Pia", "username": "pia_spielt", "avatar": "", "state": "offline", "game": "" }])
	state = "bereit"
	changed.emit()


func _demo_history(friend_id: String) -> Array:
	if not _hist.has(friend_id):
		var now := int(Time.get_unix_time_from_system())
		_hist[friend_id] = [
			{ "id": "h1", "me": false, "text": "Bist du heute Abend dabei?", "at": now - 3600, "ordinal": 0 },
			{ "id": "h2", "me": true, "text": "Klar, ab 20 Uhr", "at": now - 3500, "ordinal": 0 },
		]
		Config.cap(_hist, 100)
		if friend_id == "1002":
			(_hist[friend_id] as Array).append({ "id": "h3", "me": false, "text": "Hab Mario Kart mitgebracht 🏁", "at": now - 120, "ordinal": 0 })
	return _hist[friend_id]


func _demo_reply(friend_id: String) -> void:
	_demo_reply_n += 1
	var n := _demo_reply_n
	await get_tree().create_timer(2.5).timeout
	_add(friend_id, { "id": "r%d" % n, "me": false, "text": ["Nice!", "Bin gleich da", "😄"][n % 3], "at": int(Time.get_unix_time_from_system()), "ordinal": 0 })
	if open_chat != friend_id:
		unread[friend_id] = int(unread.get(friend_id, 0)) + 1
		changed.emit()
	messages.emit(friend_id)

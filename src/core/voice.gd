extends Node
## Discord-Sprachkanal über die offizielle lokale Schnittstelle der Discord-App (RPC).
##
## Damit zeigt der Guide, wer mit dir im Kanal ist und wer gerade spricht, und du kannst
## Leute für dich stummschalten, ihre Lautstärke ändern, dein Mikro und deinen Ton schalten,
## den Kanal wechseln oder verlassen. Dafür nimmt Uzai seine eingebaute Discord-App (APP_ID,
## Freigabe per PKCE ohne Secret) oder eine eigene (App-ID, freiwillig mit Client-Secret). Beim
## ersten Mal fragt Discord einmal in der Discord-App, ob Uzai das darf.
##
## Der Windows-Helfer reicht nur die Rahmen der Pipe discord-ipc-N durch; das Protokoll steckt
## hier (und ist deshalb auch ohne Windows testbar, siehe tests/test_logic.gd).

## Ein Freund ruft dich in eurer Direktnachricht an: { user_id, channel_id, name, avatar }.
signal incoming_call(info: Dictionary)
## Der Anruf ist vorbei, bevor du angenommen hast (Freund hat aufgelegt).
signal call_ended(channel_id: String)
signal changed                  ## Kanal, Personen, eigener Ton oder Zustand haben sich geändert
signal speaking_changed(user_id: String, on: bool)
signal token_changed            ## neuer Zugang (z. B. nach der Freigabe) – für DiscordChat
## Discord-Benachrichtigung (RPC-Ereignis NOTIFICATION_CREATE: Direktnachricht, Erwähnung):
## { channel_id, message: { id, content, author: { id, username, avatar } }, icon_url, title, body }
signal discord_notice(data: Dictionary)

const SCOPES := ["rpc", "rpc.voice.read", "rpc.voice.write"]
const Logdatei := preload("res://src/core/logdatei.gd")
const Zustand := preload("res://src/core/zustand.gd")
## Uzais eigene Discord-App (öffentliche App-ID, kein Geheimnis; Discord erlaubt sie in Apps).
## Angelegt vom Projektinhaber auf discord.com/developers (OAuth2 → „Public Client“ an, Redirects
## http://localhost und http://127.0.0.1/callback). Damit gehen Status
## „Spielt … auf Uzai“ ohne jede Anmeldung, Freigaben per PKCE ohne Client-Secret. Ein
## Client-Secret liefert Uzai nie mit. Eine eigene App-ID (Einstellungen → Konten → Discord → Mehr)
## hat Vorrang.
const APP_ID := "1559947744263540788"
## Kleines Bild im Status, nur mit Uzais App (dort als Art-Asset „uzai“ hinterlegt).
const PRESENCE_SMALL := "uzai"
const TOKEN_URL := "https://discord.com/api/oauth2/token"
const CDN := "https://cdn.discordapp.com/avatars/%s/%s.png?size=128"
const MAX_OTHERS := 10   # der Guide zeigt vier und „N weitere“
## So lange nach dem Verlassen eines Kanals zählst du in keiner Kanal-Liste mit (Discord nennt dich
## in der ersten Antwort manchmal noch), und so oft höchstens holt der Guide die Listen neu.
const WEG_MS := 15000
const LISTEN_MS := 5000

## aus: nicht eingerichtet · verbinde · anmelden (Discord fragt gerade) · getrennt (Anmeldung
## nötig) · bereit · fehler (nach einem Abriss neuer Versuch in 20 s). Ausschalten führt von überall zu „aus“.
const ZUSTAENDE := { "*": ["aus"], "aus": ["verbinde", "fehler", "bereit"], "verbinde": ["anmelden", "getrennt", "bereit", "fehler"],
	"anmelden": ["getrennt", "bereit", "fehler"], "getrennt": ["anmelden", "bereit", "fehler"],
	"bereit": ["anmelden", "getrennt", "fehler"], "fehler": ["verbinde"] }
var state := "aus":
	set(neu):
		Zustand.wechsel("discord.sprache", ZUSTAENDE, state, neu)
		state = neu
var error := ""
## Schritt der Freigabe (für die Anzeige beim Verbinden): "" | freigabe (in Discord bestätigen) |
## tausch (Zugang bei discord.com holen) | anmelden (Discord-App nimmt den Zugang an) | fertig.
## Neu freigeben beginnt von jedem Schritt aus (auch nach einem Fehler).
const ZUSTAENDE_SCHRITT := { "*": ["freigabe"], "": ["fertig"], "freigabe": ["tausch", "fertig"], "tausch": ["anmelden"],
	"anmelden": ["fertig"], "fertig": [] }
var step := "":
	set(neu):
		Zustand.wechsel("discord.sprache_schritt", ZUSTAENDE_SCHRITT, step, neu)
		step = neu
var me_id := ""
var channel: Dictionary = {}    ## { id, name, guild_id, guild }  leer: in keinem Kanal
var members: Array = []         ## [{ id, name, avatar, self_mute, self_deaf, mute, deaf, volume, local_mute, speaking, me }]
var others: Array = []          ## andere Sprachkanäle im Server: [{ id, name, members: [{ id, name, avatar }] }]
var guilds: Array = []          ## deine Server: [{ id, name, icon }]
var browse_guild := ""          ## Server, dessen Sprachkanäle gerade zur Wahl stehen
var others_guild := ""          ## Server, aus dem die Kanäle in others stammen (bleibt nach „Verlassen“)
var browse: Array = []          ## dessen Sprachkanäle: [{ id, name, members }]
var _chan_queue: Array = []     ## Server-IDs offener GET_CHANNELS-Anfragen (Antworten in Reihenfolge)
var guilds_error := ""          ## Discord hat Server oder Kanäle abgelehnt (Grund)
var self_mute := false
var self_deaf := false
var demo := false
## Zusätzliche Rechte bei der Freigabe (Discord-Nachrichten über das Social SDK, siehe DiscordChat).
var extra_scopes: Array = []
## Die Discord-App hat die Freigabe mit diesen Rechten abgelehnt (dann nur noch ohne).
var extra_rejected := false
## Die Freigabe scheiterte mit Uzais App (nicht freigeschaltet): Guide, Einstellungen und Verbinden bieten dann
## „Volle Discord-Steuerung einrichten“ an (eigene App, src/ui/layers/discord_eigen.gd).
var tester_fehlt := false
## Recht für Benachrichtigungen (siehe Notify). Ist es nicht freigegeben, hilft einmal neu verbinden.
const NOTIFY_SCOPE := "rpc.notifications.read"
## Read direct-message messages via the Discord app (GET_CHANNEL then returns "messages" including attachments with
## URLs). Used only to show images and videos in the chat, because the Social SDK gives no URL.
const MSG_SCOPE := "messages.read"
var _msg_rejected := false     ## Discord lehnte die Freigabe mit messages.read ab: ohne es weiter
signal channel_messages(channel_id: String, messages: Array)
var _msg_wait := {}            ## Kanal -> true, solange Uzai dessen Nachrichten (für Anhänge) abfragt
## Benachrichtigungen gewünscht (Notify setzt das aus den Einstellungen).
var want_notices := false
## "" (aus) | an (abonniert) | fehlt (Recht nicht freigegeben) | abgelehnt (Discord lehnt ab). Abbestellen und
## Trennen führen von überall zu "".
const ZUSTAENDE_MITTEILUNGEN := { "*": [""], "": ["an", "fehlt", "abgelehnt"], "an": [], "fehlt": ["an", "abgelehnt"],
	"abgelehnt": ["an", "fehlt"] }
var notices := "":
	set(neu):
		Zustand.wechsel("discord.mitteilungen", ZUSTAENDE_MITTEILUNGEN, notices, neu)
		notices = neu
var granted: Array = []         ## Rechte laut AUTHENTICATE
var _notice_nonce := ""

## Zum Testen austauschbar: bekommt den fertigen JSON-Text eines Befehls.
var transport: Callable
var _nonce := 0
var _subscribed := ""           ## Kanal, für den Ereignisse abonniert sind
var _authorizing := false
var _retry: Timer
var _channel_names := {}        ## Kanal-ID -> Name (aus GET_CHANNELS)
var _weg_ms := -WEG_MS          ## wann du zuletzt einen Kanal verlassen hast (Ticks)
var _listen_ms := -LISTEN_MS    ## wann die Kanal-Listen zuletzt neu geholt wurden (Ticks)
var _guild_channels := {}       ## Server-ID -> alle Kanäle aus GET_CHANNELS (für „In Discord senden“)
var _demo_timer: Timer


func _ready() -> void:
	transport = _send_helper
	Helper.rpc_event.connect(_on_helper_event)
	_retry = Timer.new()
	_retry.one_shot = true
	_retry.wait_time = 20.0
	_retry.timeout.connect(start)
	add_child(_retry)
	Config.changed.connect(func(k: String) -> void:
		if k in ["accounts.discord_client_id", "accounts.discord_client_secret", "accounts.discord_voice"]:
			stop()
			start()
	)


# --- Einrichtung -------------------------------------------------------------------------

## Die App-ID, mit der Uzai spricht: die eigene, sonst Uzais eingebaute (APP_ID).
func client_id() -> String:
	return pick_app_id(own_id(), APP_ID)


## Eigene App-ID (freiwillig, unter „Mehr“).
func own_id() -> String:
	return str(Config.get_value("accounts.discord_client_id", "")).strip_edges()


## Eigene App-ID vor der eingebauten; nur Ziffern zählen.
static func pick_app_id(own: String, builtin: String) -> String:
	if own != "":
		return own
	return builtin if builtin.is_valid_int() else ""


## Was dasteht, wenn die Discord-App die Freigabe nicht erteilt (AUTHORIZE-Fehler).
## Mit Uzais eingebauter App und ohne eigenes „Nein“ (5000) nennt Uzai den häufigsten Grund gleich mit: Die
## Schnittstelle für den Sprachkanal (RPC) gibt Discord nur freigegebenen Apps und sonst nur den Testern, die der
## Inhaber der App im Entwicklerportal einträgt – neue Apps nimmt Discord dafür nicht mehr auf. Wer kein Tester ist,
## kommt mit einer eigenen App-ID weiter (dort ist er selbst der Inhaber).
static func freigabe_fehler(code: int, text: String, eingebaut: bool) -> String:
	if code == 5000:
		return "In Discord abgelehnt."
	var roh := ("Discord: " + text) if text != "" else "Freigabe hat nicht geklappt."
	if not eingebaut:
		return roh
	return TESTER_TEXT


## Mit Uzais App und ohne Freischaltung (siehe freigabe_fehler): Was der Nutzer sieht – ohne Fachwörter, mit dem Weg.
const TESTER_TEXT := "Den Sprachkanal gibt Discord für Uzais App nur freigeschalteten Konten. Mit einer eigenen Discord-App geht alles – einmal einrichten, etwa 3 Minuten mit dem Handy."


## Eine eigene App-ID übernehmen (Tutorial „Volle Discord-Steuerung“): prüfen, eintragen, den Zugang der bisherigen App
## vergessen (er gilt nur für sie) und neu verbinden. "" = übernommen, sonst was nicht stimmt.
func eigene_app_setzen(id: String) -> String:
	var v := id.strip_edges()
	if not app_id_ok(v):
		return "Das ist keine App-ID. Sie hat 17 bis 20 Ziffern („Application ID“ unter General Information)."
	Config.set_value("accounts.discord_client_id", v)
	Config.set_value("accounts.discord_client_secret", "")
	_forget_token()
	tester_fehlt = false
	error = ""
	log_line("Eigene Discord-App eingetragen")
	stop()
	return ""


## App-IDs von Discord sind Snowflakes: 17 bis 20 Ziffern.
static func app_id_ok(v: String) -> bool:
	return RegEx.create_from_string("^[0-9]{17,20}$").search(v) != null


## Läuft Uzai mit seiner eingebauten Discord-App?
func builtin() -> bool:
	return own_id() == "" and client_id() != ""


## Mit Uzais eingebauter App gleich verbinden? Discord gibt den Sprachkanal (RPC) für sie nur freigeschalteten Konten
## (Tester im Entwicklerportal). Neue Nutzer bekommen darum gleich den Weg zur eigenen App (discord_connect.gd); direkt
## geht es nur, wenn Uzais App für dieses Konto schon einmal ging (accounts.discord_uzai_app, gesetzt in _store_token)
## oder noch ein Zugang da ist. Freigeschaltete ohne beides: langes A auf „Mit Discord verbinden“ (settings_konten.gd).
static func direkt_ok(eingebaut: bool, merker: bool, refresh: String) -> bool:
	return not eingebaut or merker or refresh != ""


func uzai_app_direkt() -> bool:
	return direkt_ok(builtin(), bool(Config.get_value("accounts.discord_uzai_app", false)),
			str(Config.get_value("accounts.discord_refresh", "")))


## Client-Secret nur zur eigenen App (mit Uzais App nie – sie ist ein „Public Client“).
func client_secret() -> String:
	if own_id() == "":
		return ""
	return str(Config.get_value("accounts.discord_client_secret", "")).strip_edges()


## Ohne Client-Secret: Freigabe per PKCE (Public Client), Prüfwert statt Geheimnis.
func public_flow() -> bool:
	return client_secret() == ""


## Eingerichtet heißt: eine App-ID ist da (eingebaut oder eigen) und die Funktion ist an.
func configured() -> bool:
	return demo or (bool(Config.get_value("accounts.discord_voice", true)) and client_id() != "")


## Fehlt etwas, das der Nutzer nicht selbst hat? Ein Satz dazu ("" = alles da).
func missing_text() -> String:
	if client_id() != "":
		return ""
	return "Uzais Discord-App ist in dieser Version noch nicht eingetragen. Bis dahin geht es nur mit einer eigenen App-ID (Mehr)."


## Felder für den Tausch Code → Zugang: mit Secret (eigene App) oder mit Prüfwert (PKCE).
static func token_fields(cid: String, secret: String, code: String, verifier: String, redirect: String) -> Dictionary:
	var f := { "client_id": cid, "grant_type": "authorization_code", "code": code }
	if secret != "":
		f["client_secret"] = secret
	if verifier != "":
		f["code_verifier"] = verifier
	if redirect != "":
		f["redirect_uri"] = redirect
	return f


## Felder zum Erneuern (ohne Secret bei Public Clients).
static func refresh_fields(cid: String, secret: String, refresh: String) -> Dictionary:
	var f := { "client_id": cid, "grant_type": "refresh_token", "refresh_token": refresh }
	if secret != "":
		f["client_secret"] = secret
	return f


## PKCE (RFC 7636): Prüfwert (43–128 Zeichen) und Herausforderung = base64url(SHA-256(Prüfwert)).
static func pkce_challenge(verifier: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(verifier.to_ascii_buffer())
	return Marshalls.raw_to_base64(h.finish()).replace("+", "-").replace("/", "_").replace("=", "")


static func pkce_verifier() -> String:
	var raw := Crypto.new().generate_random_bytes(48)
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").replace("=", "")


var _verifier := ""


## Argumente für AUTHORIZE; ohne Secret mit PKCE-Herausforderung (neuer Prüfwert je Freigabe).
func _authorize_args() -> Dictionary:
	var a := { "client_id": client_id(), "scopes": scopes() }
	_verifier = ""
	if public_flow():
		_verifier = pkce_verifier()
		a["code_challenge"] = pkce_challenge(_verifier)
		a["code_challenge_method"] = "S256"
	return a


## Häufige Verwechslungen beim Eintragen erkennen, bevor Discord gefragt wird.
func setup_problem() -> String:
	return check_ids(client_id(), client_secret())


static func check_ids(cid: String, secret: String) -> String:
	if cid != "" and not cid.is_valid_int():
		return "Die App-ID besteht nur aus Ziffern (Application ID unter General Information)."
	if secret.count(".") >= 2 or secret.length() > 40:
		return "Im Feld Client-Secret steht ein Bot-Token. Uzai braucht das Client-Secret unter OAuth2 (32 Zeichen), keinen Bot."
	if secret != "" and secret.length() < 20:
		return "Das Client-Secret ist zu kurz. Unter OAuth2 → Client Secret → Reset Secret neu erzeugen und ganz kopieren."
	return ""


func ready_() -> bool:
	return state == "bereit"


func in_channel() -> bool:
	return ready_() and not channel.is_empty()


func start() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		_load_demo()
		return
	if not configured() or not Config.is_windows():
		_set_state("aus")
		return
	if state in ["verbinde", "bereit", "anmelden"]:
		return
	var problem := setup_problem()
	if problem != "":
		error = problem
		_set_state_keep("fehler")
		return
	_set_state("verbinde")
	_watch("verbinde", 12.0, "Discord antwortet nicht. Läuft die Discord-App (nicht nur im Browser)?")
	var r := await Helper.run("rpc-open", { "client_id": client_id() }, 6.0)
	if not r.ok or not (r.result is Dictionary) or not r.result.get("ok", false):
		var why := str(r.result.get("reason", "")) if r.result is Dictionary else str(r.get("error", ""))
		_fail(why if why != "" else "Discord antwortet nicht.")
		return
	# Weiter geht es mit dem READY-Ereignis aus der Pipe.


func stop() -> void:
	if demo:
		return
	if Config.is_windows() and Helper.available:
		Helper.run("rpc-close", {}, 2.0)
	_reset()
	_set_state("aus")


## Einmalige Freigabe: Discord zeigt in der App ein Fenster „Uzai möchte …“.
func authorize() -> void:
	if demo or not configured():
		return
	_authorizing = true
	if state in ["aus", "fehler"]:
		start()        # READY → _after_ready fragt dann nach der Freigabe
		return
	if state in ["getrennt", "bereit"]:
		step = "freigabe"
		_set_state("anmelden")
		_watch("anmelden", 120.0, "Keine Freigabe von Discord erhalten. Nochmal verbinden und in der Discord-App auf „Autorisieren“ klicken.")
		_cmd("AUTHORIZE", _authorize_args())


## Rechte für die Freigabe: Sprachkanal, dazu (wenn gewünscht) die für Discord-Nachrichten.
func scopes() -> Array:
	var out: Array = SCOPES.duplicate()
	if not extra_rejected:
		for x in extra_scopes:
			if not out.has(x) and not (x == MSG_SCOPE and _msg_rejected):
				out.append(x)
		# Bilder im Chat: einmal gewünscht (Knopf im Chat), dann bei jeder Freigabe mit dabei.
		if bool(Config.get_value("discord.chat_bilder", false)) and not _msg_rejected and not out.has(MSG_SCOPE):
			out.append(MSG_SCOPE)
	return out


## Hat Discord das Lesen der Nachrichten freigegeben (laut Anmeldung oder Zugang)?
func has_msg_scope() -> bool:
	return granted.has(MSG_SCOPE) or Array(str(Config.get_value("accounts.discord_scope", "")).split(" ")).has(MSG_SCOPE)


## Die Nachrichten einer Direktnachricht abfragen (nur für ihre Anhänge, channel_messages). false: geht gerade nicht.
func nachrichten_holen(channel_id: String) -> bool:
	if demo or channel_id == "" or not ready_() or not granted.has(MSG_SCOPE):
		return false
	_msg_wait[channel_id] = true
	_cmd("GET_CHANNEL", { "channel_id": channel_id })
	return true


## Ask for the permission once (button in the chat). On a connection that is already authenticated, Discord rejects
## every authorization with "Already authenticated" and no window appears. So: briefly close and reopen the connection
## to the Discord app, then AUTHORIZE instead of AUTHENTICATE (_after_ready). If the user declines in Discord, Uzai
## signs in with the old token; voice channel, chat and calls keep working as before.
var _msg_flow := false


func msg_scope_anfragen() -> void:
	if demo or not configured():
		return
	Config.set_value("discord.chat_bilder", true)
	_msg_rejected = false
	_msg_flow = true
	_authorizing = true
	if state in ["bereit", "anmelden", "verbinde"]:
		log_line("Bilder im Chat: Verbindung neu für die Freigabe mit messages.read")
		if Config.is_windows() and Helper.available:
			await Helper.run("rpc-close", {}, 2.0)
		_reset()
		_set_state("aus")
		_authorizing = true
	start()


func _fail(why: String) -> void:
	error = why
	_reset()
	_set_state("fehler")
	if configured() and not demo:
		_retry.start()


func _reset() -> void:
	channel = {}
	members = []
	others = []
	_subscribed = ""
	_authorizing = false
	notices = ""
	_notice_nonce = ""


func _set_state(s: String) -> void:
	state = s
	if s != "fehler":
		error = ""
	log_line("Zustand: " + s)
	changed.emit()


## Zustand setzen, ohne den Fehlertext zu löschen.
func _set_state_keep(s: String) -> void:
	state = s
	log_line("Zustand: %s (%s)" % [s, error])
	changed.emit()


## Hängt Uzai in einem Zwischenzustand, wird daraus nach einer Weile ein sichtbarer Fehler.
func _watch(s: String, secs: float, why: String) -> void:
	var stamp := Time.get_ticks_msec()
	_watch_stamp = stamp
	await get_tree().create_timer(secs).timeout
	if state == s and _watch_stamp == stamp:
		# Freigabe für Bilder im Chat liegen gelassen: mit dem alten Zugang weiter, nichts steht als getrennt da.
		if s == "anmelden" and _msg_flow and str(Config.get_value("accounts.discord_token", "")) != "":
			_msg_flow = false
			Config.set_value("discord.chat_bilder", false)
			log_line("Freigabe mit messages.read nicht beantwortet – weiter mit der alten Anmeldung")
			step = "anmelden"
			_cmd("AUTHENTICATE", { "access_token": str(Config.get_value("accounts.discord_token", "")) })
			_watch_auth()
			return
		error = why
		if s == "anmelden":
			_authorizing = false
			_set_state_keep("getrennt")
		else:
			_reset()
			_set_state_keep("fehler")


var _watch_stamp := 0


## Protokoll der Verbindung (discord.log im Datenordner), ohne Zugangsdaten. Hilft, wenn
## etwas nicht klappt: die Datei zeigt, was Discord geantwortet hat.
func log_line(text: String) -> void:
	if demo:
		return
	Logdatei.zeile(Config.path("logs/discord.log"), text, 400000)


## Eine Nachricht von Discord fürs Protokoll: Befehl, Ereignis, bei Fehlern Code und Text, sonst nur die Namen der
## Felder. Der Inhalt bleibt draußen: Dort stehen Nachrichten, Namen und Server anderer Leute (Mitteilungen,
## Personen im Kanal, Serverliste), und das Protokoll geht zur Fehlersuche auch an Dritte.
static func log_form(msg: Dictionary) -> String:
	var evt := str(msg.get("evt", "")) if msg.get("evt") != null else ""
	var out := str(msg.get("cmd", "")) + (" " + evt if evt != "" else "")
	var data: Variant = msg.get("data")
	if not (data is Dictionary):
		return out
	if evt == "ERROR":
		return "%s: %s %s" % [out, str(data.get("code", "")), str(data.get("message", "")).left(200)]
	var felder := PackedStringArray()
	for k in (data as Dictionary).keys().slice(0, 12):
		felder.append(str(k).left(32))
	return "%s {%s}" % [out, ", ".join(felder)]


# --- Befehle -----------------------------------------------------------------------------

## Lautstärke einer Person nur für dich (0–200 %).
func set_volume(user_id: String, volume: int) -> void:
	volume = clampi(volume, 0, 200)
	var m := member(user_id)
	if m.is_empty():
		return
	m["volume"] = volume
	changed.emit()
	if not demo:
		_cmd("SET_USER_VOICE_SETTINGS", { "user_id": user_id, "volume": volume })


## Eine Person nur für dich stummschalten.
func set_local_mute(user_id: String, on: bool) -> void:
	var m := member(user_id)
	if m.is_empty():
		return
	m["local_mute"] = on
	changed.emit()
	if not demo:
		_cmd("SET_USER_VOICE_SETTINGS", { "user_id": user_id, "mute": on })


func toggle_local_mute(user_id: String) -> bool:
	var on := not bool(member(user_id).get("local_mute", false))
	set_local_mute(user_id, on)
	return on


func set_self_mute(on: bool) -> void:
	self_mute = on
	_mirror_me()
	changed.emit()
	if not demo:
		_cmd("SET_VOICE_SETTINGS", { "mute": on })


func set_self_deaf(on: bool) -> void:
	self_deaf = on
	_mirror_me()
	changed.emit()
	if not demo:
		_cmd("SET_VOICE_SETTINGS", { "deaf": on })


## In einen Sprachkanal wechseln (force: auch wenn du schon in einem anderen bist).
func join(channel_id: String) -> void:
	# Kinderprofil mit „Chats und Sprachkanäle“ aus (src/core/profiles.gd).
	if Config.kid_stop("chats"):
		return
	if demo:
		_demo_join(channel_id)
		return
	_cmd("SELECT_VOICE_CHANNEL", { "channel_id": channel_id, "force": true })


func leave() -> void:
	if demo:
		# Der verlassene Kanal steht wieder bei den anderen – ohne dich.
		if not channel.is_empty():
			others.insert(0, { "id": channel.get("id", ""), "name": channel.get("name", ""),
					"members": members.filter(func(m): return not m.get("me", false)).map(func(m): return { "id": m.id, "name": m.name, "avatar": m.avatar }) })
		channel = {}
		members = []
		changed.emit()
		return
	_cmd("SELECT_VOICE_CHANNEL", { "channel_id": null })


## Andere Kanäle neu holen (z. B. wenn der Guide aufgeht). Bist du in keinem Kanal, kommt von
## Discord dazu nichts von selbst: dann holt Uzai neu, wer in den gezeigten Kanälen sitzt.
func refresh() -> void:
	if demo or not ready_():
		return
	_cmd("GET_SELECTED_VOICE_CHANNEL", {})
	if not in_channel():
		_listen_neu()


## Wer in den Kanälen der Listen sitzt (others, browse), neu holen – höchstens alle LISTEN_MS.
func _listen_neu() -> void:
	var jetzt := Time.get_ticks_msec()
	if jetzt - _listen_ms < LISTEN_MS:
		return
	_listen_ms = jetzt
	for id in listen_ids(others, browse):
		_cmd("GET_CHANNEL", { "channel_id": id })


## Die Kanäle beider Listen, jeder einmal (browse höchstens die ersten 16, wie beim Laden).
static func listen_ids(andere: Array, wahl: Array) -> Array:
	var ids: Array = []
	for o in andere + wahl.slice(0, 16):
		var id := str((o as Dictionary).get("id", "")) if o is Dictionary else ""
		if id != "" and not ids.has(id):
			ids.append(id)
	return ids


## Eine Kanal-Liste ohne diese Person (nach dem Verlassen: du selbst). Die Liste wird geändert.
static func ohne_person(liste: Array, uid: String) -> void:
	for o in liste:
		if o is Dictionary and (o as Dictionary).get("members") is Array:
			o["members"] = ((o as Dictionary).members as Array).filter(func(p): return not (p is Dictionary) or str((p as Dictionary).get("id", "")) != uid)


func member(user_id: String) -> Dictionary:
	for m in members:
		if str(m.id) == user_id:
			return m
	return {}


## Was die Person gerade spielt: aus Discord (Demo) oder aus dem Server-Widget, falls eingetragen.
func activity(m: Dictionary) -> String:
	if str(m.get("game", "")) != "":
		return str(m.game)
	var n := str(m.get("name", "")).to_lower()
	for s in Social.discord.values():
		for w in s.get("members", []):
			if str(w.get("name", "")).to_lower() == n and str(w.get("game", "")) != "":
				return str(w.game)
	return ""


## Kurzer Zustand für die Anzeige unter dem Namen.
func status_text(m: Dictionary) -> String:
	if m.get("me", false):
		if self_deaf:
			return "Ton aus"
		return "Mikro aus" if self_mute else "du"
	if m.get("local_mute", false):
		return "für dich stumm"
	if m.get("self_deaf", false) or m.get("deaf", false):
		return "hört nichts"
	if m.get("self_mute", false) or m.get("mute", false):
		return "Mikro aus"
	if m.get("speaking", false):
		return "spricht"
	var act := activity(m)
	return ("spielt " + act) if act != "" else "im Kanal"


func speaking_count() -> int:
	return members.filter(func(m): return m.get("speaking", false)).size()


func _cmd(cmd: String, args: Dictionary, evt := "") -> void:
	_nonce += 1
	var payload := { "cmd": cmd, "args": args, "nonce": "uz%d" % _nonce }
	if evt != "":
		payload["evt"] = evt
	var text := JSON.stringify(payload)
	if cmd != "SUBSCRIBE" and cmd != "UNSUBSCRIBE":
		# Ausgehend wie eingehend (log_form): nur Befehl und Feldnamen – Kanal-, Server- und Nutzer-Kennungen bleiben
		# draußen, das Protokoll geht zur Fehlersuche auch an Dritte.
		log_line("→ " + log_form({ "cmd": cmd, "evt": evt, "data": args }))
	transport.call(text)


func _send_helper(json: String) -> void:
	var r := await Helper.run("rpc-send", { "json": json }, 4.0)
	if not r.ok or not (r.result is Dictionary) or not r.result.get("ok", false):
		if state != "aus":
			_fail("Verbindung zu Discord verloren.")


# --- Antworten und Ereignisse ------------------------------------------------------------

func _on_helper_event(kind: String, msg: Variant) -> void:
	if kind == "discord-closed":
		if not (state in ["aus", "fehler"]):
			_fail("Discord wurde geschlossen.")
		return
	if msg is Dictionary:
		handle(msg)


## Eine Nachricht von Discord verarbeiten (öffentlich für die Tests).
func handle(msg: Dictionary) -> void:
	var cmd := str(msg.get("cmd", ""))
	var evt := str(msg.get("evt", "")) if msg.get("evt") != null else ""
	if not (evt in ["SPEAKING_START", "SPEAKING_STOP", "VOICE_STATE_UPDATE"]) and cmd != "SUBSCRIBE":
		log_line("← " + log_form(msg))
	var data: Variant = msg.get("data", null)
	if evt == "ERROR":
		_on_error(cmd, data if data is Dictionary else {}, str(msg.get("nonce", "")) if msg.get("nonce") != null else "")
		return
	if cmd == "DISPATCH":
		_on_event(evt, data if data is Dictionary else {})
		return
	match cmd:
		"AUTHORIZE":
			_authorizing = false
			if data is Dictionary and str(data.get("code", "")) != "":
				_exchange(str(data.code))
		"AUTHENTICATE":
			if data is Dictionary:
				var user: Variant = data.get("user", {})
				if user is Dictionary:
					me_id = str(user.get("id", ""))
				granted = data.get("scopes", []) if data.get("scopes") is Array else []
			if _msg_flow:
				_msg_flow = false
				log_line("Bilder im Chat: Freigabe mit messages.read %s" % ("erteilt" if granted.has(MSG_SCOPE) else "nicht in der Anmeldung"))
			var interactive := step in ["freigabe", "tausch", "anmelden"]
			step = "fertig"
			_auth_retried = false
			_set_state("bereit")
			# Nach dem Klick in Discord liegt Discord vorn: Uzai holt sich den Platz zurück.
			if interactive and Config.is_windows() and Helper.available:
				Helper.run("focus", { "pid": OS.get_process_id() })
			_cmd("SUBSCRIBE", {}, "VOICE_CHANNEL_SELECT")
			_cmd("SUBSCRIBE", {}, "VOICE_SETTINGS_UPDATE")
			_cmd("GET_VOICE_SETTINGS", {})
			_cmd("GET_SELECTED_VOICE_CHANNEL", {})
			load_guilds()
			update_notices()
			# Neue Verbindung: die Direktnachrichten wieder auf Anrufe beobachten.
			_dm_watch = {}
			DiscordChat.rewatch()
		"SUBSCRIBE":
			if data is Dictionary and str(data.get("evt", "")) == "NOTIFICATION_CREATE":
				_notice_nonce = ""
				notices = "an"
				log_line("Benachrichtigungen abonniert")
				changed.emit()
		"GET_GUILDS":
			_on_guilds(data if data is Dictionary else {})
		"GET_VOICE_SETTINGS":
			if data is Dictionary:
				self_mute = bool(data.get("mute", false))
				self_deaf = bool(data.get("deaf", false))
				_mirror_me()
				changed.emit()
		"GET_SELECTED_VOICE_CHANNEL", "SELECT_VOICE_CHANNEL":
			_set_channel(data if data is Dictionary else {})
		"GET_GUILD":
			if data is Dictionary and str(data.get("id", "")) == str(channel.get("guild_id", "")):
				channel["guild"] = str(data.get("name", ""))
				changed.emit()
		"GET_CHANNELS":
			var gid := str(_chan_queue.pop_front()) if not _chan_queue.is_empty() else ""
			var d: Dictionary = data if data is Dictionary else {}
			if gid != "" and d.get("channels") is Array:
				_guild_channels[gid] = d.channels
			if gid != "" and gid == browse_guild:
				_on_browse_channels(d)
			# Auch ohne Kanal: die Liste des Servers, aus dem die „anderen Kanäle“ stammen (nach
			# dem Verlassen neu geholt, _set_channel).
			if gid == "" or gid == str(channel.get("guild_id", "")) or (channel.is_empty() and gid == others_guild):
				_on_channels(d, gid)
		"GET_CHANNEL":
			var gd: Dictionary = data if data is Dictionary else {}
			var gcid := str(gd.get("id", ""))
			if _msg_wait.has(gcid):
				_msg_wait.erase(gcid)
				channel_messages.emit(gcid, gd.get("messages", []) if gd.get("messages") is Array else [])
				if not _call_check.has(gcid):
					return
			if _call_check.has(gcid):
				var fid := str(_call_check[gcid])
				_call_check.erase(gcid)
				var vss: Array = gd.get("voice_states", []) if gd.get("voice_states") is Array else []
				if not is_ringing(vss, fid, me_id):
					_abgelehnt.erase(gcid)          # kein Anruf mehr: der nächste darf wieder klingeln
				elif not ringing.has(gcid) and not _abgelehnt.has(gcid):
					var who := {}
					for p in _people(gd):
						if str(p.id) == fid:
							who = p
					var info := { "user_id": fid, "channel_id": gcid, "name": str(who.get("name", "")), "avatar": str(who.get("avatar", "")) }
					ringing[gcid] = info
					log_line("Eingehender Anruf")
					incoming_call.emit(info)
				return
			_on_other_channel(gd)
		"SET_USER_VOICE_SETTINGS":
			if data is Dictionary:
				var m := member(str(data.get("user_id", "")))
				if not m.is_empty():
					if data.has("volume"):
						m["volume"] = int(round(float(data.volume)))
					if data.has("mute"):
						m["local_mute"] = bool(data.mute)
					changed.emit()
		"SET_VOICE_SETTINGS":
			if data is Dictionary:
				self_mute = bool(data.get("mute", self_mute))
				self_deaf = bool(data.get("deaf", self_deaf))
				_mirror_me()
				changed.emit()


# --- Eingehende Anrufe (Direktnachrichten) ---------------------------------------------------
# Die lokale Schnittstelle meldet kein „klingelt“. Ruft ein Freund an, tritt er aber dem
# Sprachkanal eurer Direktnachricht bei – Uzai beobachtet diese Kanäle (VOICE_STATE_CREATE/
# DELETE) und prüft mit GET_CHANNEL nach, ob er wirklich dort ist und du noch nicht.

var _dm_watch := {}        ## Kanal der Direktnachricht -> Nutzer-ID des Freundes
var _call_check := {}      ## Kanal -> Nutzer-ID, Nachfrage läuft
var ringing := {}          ## Kanal -> Info, solange es klingelt
const DM_WATCH_MAX := 30


## Direktnachricht eines Freundes auf Anrufe beobachten (DiscordChat ruft das auf).
func watch_dm(channel_id: String, user_id: String) -> void:
	if channel_id == "" or user_id == "" or _dm_watch.has(channel_id) or _dm_watch.size() >= DM_WATCH_MAX or not ready_():
		return
	_dm_watch[channel_id] = user_id
	for e in ["VOICE_STATE_CREATE", "VOICE_STATE_DELETE"]:
		_cmd("SUBSCRIBE", { "channel_id": channel_id }, e)


func _dm_channel_of(uid: String) -> String:
	for cid in _dm_watch.keys():
		if str(_dm_watch[cid]) == uid:
			return str(cid)
	return ""


## Rein: Ist das ein Anruf an dich? (Freund im Kanal der Direktnachricht, du nicht.)
static func is_ringing(voice_states: Array, friend_id: String, my_id: String) -> bool:
	var friend_in := false
	for vs in voice_states:
		if not (vs is Dictionary):
			continue
		var uid := _uid(vs)
		if uid == my_id and my_id != "":
			return false
		if uid == friend_id:
			friend_in = true
	return friend_in


## Annehmen: dem Anruf in der Direktnachricht beitreten.
func accept_call(channel_id: String) -> void:
	ringing.erase(channel_id)
	join(channel_id)


func dismiss_call(channel_id: String) -> void:
	ringing.erase(channel_id)


## Ablehnen: Uzai klingelt für diesen Anruf nicht noch einmal, bis er endet (der Freund legt auf). Die lokale
## Schnittstelle der Discord-App kennt kein „Ablehnen“ beim Anrufer – Discord selbst klingelt dort weiter.
var _abgelehnt := {}       ## Kanal der Direktnachricht -> true, bis der Anruf endet


func decline_call(channel_id: String) -> void:
	ringing.erase(channel_id)
	if channel_id != "":
		_abgelehnt[channel_id] = true


func _on_event(evt: String, data: Dictionary) -> void:
	# Ereignisse aus beobachteten Direktnachrichten nicht in die Mitglieder deines Kanals mischen.
	if evt in ["VOICE_STATE_CREATE", "VOICE_STATE_DELETE"] and not _dm_watch.is_empty():
		var u := _uid(data)
		var dm := _dm_channel_of(u)
		if dm != "" and dm != str(channel.get("id", "")):
			if evt == "VOICE_STATE_CREATE":
				_call_check[dm] = u
				_cmd("GET_CHANNEL", { "channel_id": dm })
			elif ringing.has(dm):
				ringing.erase(dm)
				call_ended.emit(dm)
			if evt == "VOICE_STATE_DELETE":
				_abgelehnt.erase(dm)              # aufgelegt: der nächste Anruf klingelt wieder
			# Ist der Freund vielleicht (auch) in deinem Kanal: die Liste dort frisch holen.
			if in_channel():
				_cmd("GET_SELECTED_VOICE_CHANNEL", {})
			return
	match evt:
		"READY":
			_after_ready()
		"VOICE_CHANNEL_SELECT":
			if data.get("channel_id") == null or str(data.get("channel_id", "")) == "":
				_set_channel({})
			else:
				_cmd("GET_SELECTED_VOICE_CHANNEL", {})
		"VOICE_STATE_CREATE", "VOICE_STATE_UPDATE":
			_upsert(data)
			changed.emit()
		"VOICE_STATE_DELETE":
			var uid := _uid(data)
			members = members.filter(func(m): return str(m.id) != uid)
			changed.emit()
		"SPEAKING_START", "SPEAKING_STOP":
			var uid2 := str(data.get("user_id", ""))
			var on := evt == "SPEAKING_START"
			var m := member(uid2)
			if not m.is_empty() and bool(m.get("speaking", false)) != on:
				m["speaking"] = on
				speaking_changed.emit(uid2, on)
		"VOICE_SETTINGS_UPDATE":
			self_mute = bool(data.get("mute", self_mute))
			self_deaf = bool(data.get("deaf", self_deaf))
			_mirror_me()
			changed.emit()
		"NOTIFICATION_CREATE":
			if want_notices:
				discord_notice.emit(data)


func _on_error(cmd: String, data: Dictionary, nonce := "") -> void:
	var code := int(data.get("code", 0))
	var text := str(data.get("message", ""))
	match cmd:
		"SUBSCRIBE":
			# Abo der Benachrichtigungen abgelehnt (meist fehlt das Recht): sichtbar machen.
			if nonce != "" and nonce == _notice_nonce:
				_notice_nonce = ""
				notices = "fehlt" if code in [4000, 4002, 4006] or text.to_lower().contains("scope") else "abgelehnt"
				log_line("Benachrichtigungen nicht abonniert: %d %s" % [code, text])
				changed.emit()
		"AUTHORIZE":
			_authorizing = false
			# Schon angemeldet: Das ist keine Ablehnung der Rechte – nichts zurückstufen (früher fiel Uzai hier bis auf
			# „Uzais App nicht freigeschaltet“ zurück, und der Sprachkanal stand als getrennt da).
			if text.to_lower().contains("already authenticated"):
				log_line("Freigabe auf angemeldeter Verbindung nicht möglich – Verbindung bleibt")
				if me_id != "":
					step = "fertig"
					_set_state("bereit")
				return
			# Freigabe für Bilder im Chat abgelehnt (in Discord abgebrochen oder Recht nicht erlaubt): mit dem alten Zugang
			# anmelden, als wäre nichts gewesen; ohne Zugang den gewohnten Weg.
			if _msg_flow:
				_msg_flow = false
				_msg_rejected = true
				Config.set_value("discord.chat_bilder", false)
				log_line("Freigabe mit messages.read nicht erteilt (%d %s) – weiter mit der alten Anmeldung" % [code, text])
				var alt := str(Config.get_value("accounts.discord_token", ""))
				if alt != "":
					step = "anmelden"
					_cmd("AUTHENTICATE", { "access_token": alt })
					_watch_auth()
				else:
					_after_ready()
				return
			# Erst nur messages.read weglassen (Bilder im Chat): Daran soll nie die übrige Freigabe scheitern.
			if code != 5000 and not _msg_rejected and scopes().has(MSG_SCOPE):
				_msg_rejected = true
				log_line("Freigabe mit messages.read abgelehnt (%d %s) – frage ohne es" % [code, text])
				if state == "anmelden":
					state = "getrennt"
				authorize()
				return
			# Mit den Rechten für Nachrichten abgelehnt (Social SDK in der App nicht an): einmal
			# ohne sie neu fragen, damit wenigstens der Sprachkanal geht. DiscordChat nimmt dann
			# die Freigabe über das SDK.
			if code != 5000 and not extra_rejected and scopes().size() > SCOPES.size():
				extra_rejected = true
				log_line("Freigabe mit zusätzlichen Rechten abgelehnt (%d %s) – frage ohne sie" % [code, text])
				# authorize() fragt nur aus „getrennt“ neu (sonst bliebe es bei „anmelden“ hängen).
				if state == "anmelden":
					state = "getrennt"
				authorize()
				token_changed.emit()
				return
			# 5000: abgelehnt, 4002/4000: falsche App-ID usw.
			error = freigabe_fehler(code, text, builtin())
			tester_fehlt = builtin() and code != 5000
			if tester_fehlt:
				log_line("Freigabe mit Uzais App abgelehnt (%d %s): nicht freigeschaltet" % [code, text])
			if text.to_lower().contains("redirect"):
				error = explain_token_error("redirect")
			_set_state_keep("getrennt")
		"AUTHENTICATE":
			# Schon angemeldet (doppeltes AUTHENTICATE): kein Fehler, die Verbindung läuft weiter.
			if text.to_lower().contains("already authenticated"):
				log_line("Discord: schon angemeldet – Verbindung bleibt")
				if state != "bereit" and me_id != "":
					step = "fertig"
					_set_state("bereit")
				return
			# Zugang abgelaufen oder widerrufen: einmal erneuern, sonst neu freigeben lassen.
			# Nur ein Versuch: lehnt Discord auch den neuen Zugang ab, liefe es sonst im Kreis.
			if str(Config.get_value("accounts.discord_refresh", "")) != "" and not _refreshing and not _auth_retried:
				_auth_retried = true
				_refresh_token()
			else:
				_auth_retried = false
				_forget_token()
				error = "Discord hat den Zugang nicht angenommen%s. Bitte nochmal verbinden." % ((" (" + text + ")") if text != "" else "")
				_set_state_keep("getrennt")
		"SET_USER_VOICE_SETTINGS", "SET_VOICE_SETTINGS", "SELECT_VOICE_CHANNEL":
			Toasts.show_toast("Discord hat abgelehnt", text, "discord", { "sound": "error" })
		"GET_GUILDS", "GET_CHANNELS":
			# Sichtbar machen statt still leer: Discord gibt die Liste nicht frei.
			guilds_error = "Discord gibt die %s nicht frei%s." % ["Serverliste" if cmd == "GET_GUILDS" else "Kanäle", (" (" + text + ")") if text != "" else ""]
			if cmd == "GET_CHANNELS" and not _chan_queue.is_empty():
				_chan_queue.pop_front()
			changed.emit()
		"CLOSE":
			# 4000: App-ID unbekannt – dann hilft auch Neuverbinden nichts.
			_reset()
			error = "Discord kennt diese App-ID nicht." if code == 4000 else ("Discord hat getrennt: " + text if text != "" else "Discord hat getrennt.")
			state = "fehler"
			changed.emit()
			if code != 4000 and configured():
				_retry.start()
		_:
			pass


func _after_ready() -> void:
	var token := str(Config.get_value("accounts.discord_token", ""))
	var expires := int(Config.get_value("accounts.discord_expires", 0))
	var now := int(Time.get_unix_time_from_system())
	# Neue Freigabe gewünscht (Bilder im Chat): erst fragen, die alte Anmeldung bleibt der Rückweg.
	if _msg_flow:
		step = "freigabe"
		_set_state("anmelden")
		_watch("anmelden", 120.0, "Keine Freigabe von Discord erhalten. Nochmal „Bilder anzeigen“ und in der Discord-App auf „Autorisieren“ klicken.")
		_cmd("AUTHORIZE", _authorize_args())
		return
	if token != "" and expires > now + 60:
		_cmd("AUTHENTICATE", { "access_token": token })
	elif str(Config.get_value("accounts.discord_refresh", "")) != "":
		_refresh_token()
	elif _authorizing:
		step = "freigabe"
		_set_state("anmelden")
		_watch("anmelden", 120.0, "Keine Freigabe von Discord erhalten. Nochmal verbinden und in der Discord-App auf „Autorisieren“ klicken.")
		_cmd("AUTHORIZE", _authorize_args())
	else:
		_set_state("getrennt")


# --- Zugang (OAuth2) ---------------------------------------------------------------------

var _refreshing := false


## Weiterleitungsadressen, die Discord beim Tausch Code → Zugang akzeptieren könnte. Zuerst die,
## die Uzai unter OAuth2 → Redirects einzutragen empfiehlt: Ein Code gilt nur einmal, und ein
## gescheiterter erster Versuch kann ihn schon verbrauchen.
const REDIRECTS := ["http://localhost", "", "http://localhost/", "http://127.0.0.1", "https://localhost", "http://127.0.0.1:8888/callback"]


func _exchange(code: String) -> void:
	step = "tausch"
	_set_state("anmelden")
	log_line("Freigabe erhalten, hole Zugang …")
	var r := {}
	var last := ""
	for uri in REDIRECTS:
		var fields := token_fields(client_id(), client_secret(), code, _verifier, uri)
		r = await Net.post_form(TOKEN_URL, fields)
		if r.ok and r.data is Dictionary and str(r.data.get("access_token", "")) != "":
			break
		last = token_error(r)
		log_line("Zugang abgelehnt (%s): %s" % [uri if uri != "" else "ohne Adresse", last])
		# Falsches Secret oder verbrauchter Code: weitere Adressen helfen nicht.
		if last.contains("invalid_client") or (last.contains("invalid_grant") and not last.to_lower().contains("redirect")):
			break
	if not r.ok or not (r.data is Dictionary) or str(r.data.get("access_token", "")) == "":
		# Bilder im Chat: Discord stellt den Zugang mit messages.read nicht aus – zurück zur alten Anmeldung.
		if _msg_flow and str(Config.get_value("accounts.discord_token", "")) != "":
			_msg_flow = false
			_msg_rejected = true
			Config.set_value("discord.chat_bilder", false)
			log_line("Zugang mit messages.read nicht ausgestellt (%s) – weiter mit der alten Anmeldung" % last)
			step = "anmelden"
			_cmd("AUTHENTICATE", { "access_token": str(Config.get_value("accounts.discord_token", "")) })
			_watch_auth()
			return
		# Zusätzliche Rechte (Benachrichtigungen, Nachrichten) nicht erlaubt: ohne sie neu fragen.
		if last.contains("invalid_scope") and not extra_rejected and scopes().size() > SCOPES.size():
			extra_rejected = true
			log_line("Zusätzliche Rechte beim Tausch abgelehnt (%s) – frage ohne sie" % last)
			step = "freigabe"
			_set_state("anmelden")
			_cmd("AUTHORIZE", _authorize_args())
			token_changed.emit()
			return
		error = explain_token_error(last)
		_set_state_keep("getrennt")
		return
	_store_token(r.data)
	step = "anmelden"
	changed.emit()
	_cmd("AUTHENTICATE", { "access_token": str(r.data.get("access_token", "")) })
	_watch_auth()


## Antwortet die Discord-App nicht auf AUTHENTICATE, wird daraus nach 15 s ein sichtbarer Fehler.
func _watch_auth() -> void:
	var stamp := Time.get_ticks_msec()
	_auth_stamp = stamp
	await get_tree().create_timer(15.0).timeout
	if _auth_stamp == stamp and state == "anmelden" and step == "anmelden":
		error = "Die Discord-App hat die Anmeldung nicht bestätigt. Discord einmal ganz beenden (Taskleiste → Beenden), neu starten und nochmal verbinden."
		_set_state_keep("getrennt")


var _auth_stamp := 0
var _auth_retried := false


static func token_error(r: Dictionary) -> String:
	var d: Variant = r.get("data")
	if d is Dictionary:
		return ("%s: %s" % [str(d.get("error", "")), str(d.get("error_description", d.get("message", "")))]).strip_edges()
	return "HTTP %d" % int(r.get("code", 0))


## Die Antwort von Discord in einen Satz übersetzen, mit dem man etwas anfangen kann.
static func explain_token_error(e: String) -> String:
	if e.contains("HTTP 403") or e.contains("HTTP 429") or e.contains("1010") or e.contains("1015"):
		return "discord.com hat die Anfrage gerade blockiert. In ein paar Minuten nochmal verbinden."
	if e.contains("invalid_client") and e.to_lower().contains("secret"):
		return "Discord kennt dieses Client-Secret nicht. Unter OAuth2 → Reset Secret ein neues erzeugen und eintragen (nicht den Bot-Token)."
	if e.contains("invalid_client"):
		return "Discord nimmt die Freigabe ohne Client-Secret nicht an: In der Discord-App unter OAuth2 „Public Client“ einschalten – oder das Client-Secret der eigenen App eintragen."
	if e.to_lower().contains("redirect"):
		return "Discord verlangt eine Weiterleitungsadresse: in der App unter OAuth2 → Redirects http://localhost eintragen, speichern und neu verbinden."
	if e.contains("invalid_grant"):
		return "Die Freigabe war schon abgelaufen. Bitte nochmal verbinden."
	if e.begins_with("HTTP 0"):
		return "Keine Verbindung zu discord.com."
	return "Discord hat den Zugang nicht ausgestellt. Gleich noch einmal verbinden."


func _refresh_token() -> void:
	_refreshing = true
	var r := await Net.post_form(TOKEN_URL, refresh_fields(client_id(), client_secret(), str(Config.get_value("accounts.discord_refresh", ""))))
	_refreshing = false
	if not r.ok or not (r.data is Dictionary) or str(r.data.get("access_token", "")) == "":
		_forget_token()
		_set_state("getrennt")
		return
	_store_token(r.data)
	_cmd("AUTHENTICATE", { "access_token": str(r.data.access_token) })


## Zugang erneuern, ohne die Discord-App zu fragen (für DiscordChat). true = erneuert.
func refresh_access() -> bool:
	if str(Config.get_value("accounts.discord_refresh", "")) == "":
		return false
	var r := await Net.post_form(TOKEN_URL, refresh_fields(client_id(), client_secret(), str(Config.get_value("accounts.discord_refresh", ""))))
	if not r.ok or not (r.data is Dictionary) or str(r.data.get("access_token", "")) == "":
		return false
	_store_token(r.data)
	# Die laufende Verbindung bleibt angemeldet: ein zweites AUTHENTICATE lehnt Discord mit
	# „Already authenticated“ ab (das hat früher die Verbindung samt Guide-Reiter getrennt).
	# Der neue Zugang gilt ab der nächsten Verbindung.
	return true


## Benachrichtigungen abonnieren oder abbestellen (nach der Anmeldung und wenn sich die
## Einstellung ändert). Ohne freigegebenes Recht nur vermerken: einmal neu verbinden hilft.
func update_notices() -> void:
	if demo:
		notices = "an" if want_notices else ""
		return
	if not want_notices or not ready_():
		if notices == "an" and ready_():
			_cmd("UNSUBSCRIBE", {}, "NOTIFICATION_CREATE")
		notices = ""
		return
	if notices == "an" or _notice_nonce != "":
		return
	if not has_notice_scope():
		notices = "fehlt"
		changed.emit()
		return
	_cmd("SUBSCRIBE", {}, "NOTIFICATION_CREATE")
	_notice_nonce = "uz%d" % _nonce


## Hat Discord das Recht für Benachrichtigungen freigegeben? (Laut Anmeldung oder Zugang.)
func has_notice_scope() -> bool:
	if granted.has(NOTIFY_SCOPE):
		return true
	return Array(str(Config.get_value("accounts.discord_scope", "")).split(" ")).has(NOTIFY_SCOPE)


func _store_token(d: Dictionary) -> void:
	Config.set_value("accounts.discord_token", str(d.get("access_token", "")))
	Config.set_value("accounts.discord_scope", str(d.get("scope", "")))
	if str(d.get("refresh_token", "")) != "":
		Config.set_value("accounts.discord_refresh", str(d.refresh_token))
	Config.set_value("accounts.discord_expires", int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 604800)))
	if builtin():
		Config.set_value("accounts.discord_uzai_app", true)
	token_changed.emit.call_deferred()


func _forget_token() -> void:
	Config.set_value("accounts.discord_token", "")
	Config.set_value("accounts.discord_refresh", "")
	Config.set_value("accounts.discord_expires", 0)


# --- Kanal und Personen ------------------------------------------------------------------

func _set_channel(data: Dictionary) -> void:
	var cid := str(data.get("id", "")) if data.get("id") != null else ""
	if cid == "":
		if _subscribed != "":
			_unsubscribe(_subscribed)
		var alt_guild := str(channel.get("guild_id", ""))
		var war_drin := not channel.is_empty()
		channel = {}
		members = []
		# Just left: the channel lists still date from the time in the channel - you were still listed
		# there as a member, and the channel itself was missing among the others, so it looked as if you
		# were still in it. Remove yourself right away, then fetch fresh lists.
		if war_drin:
			_weg_ms = Time.get_ticks_msec()
			ohne_person(others, me_id)
			ohne_person(browse, me_id)
			_listen_ms = _weg_ms
			if alt_guild != "":
				_chan_queue.append(alt_guild)
				_cmd("GET_CHANNELS", { "guild_id": alt_guild })
			if browse_guild != alt_guild:
				for id in listen_ids([], browse):
					_cmd("GET_CHANNEL", { "channel_id": id })
		changed.emit()
		return
	var guild := str(data.get("guild_id", "")) if data.get("guild_id") != null else ""
	var keep_guild := str(channel.get("guild", "")) if str(channel.get("guild_id", "")) == guild else ""
	channel = { "id": cid, "name": str(data.get("name", "")), "guild_id": guild, "guild": keep_guild }
	if channel.name == "":
		channel["name"] = "Anruf" if guild == "" else "Sprachkanal"
	var old := {}
	for m in members:
		old[str(m.id)] = m
	members = []
	for vs in data.get("voice_states", []):
		if vs is Dictionary:
			var m := _upsert(vs)
			if old.has(str(m.id)):
				m["speaking"] = bool(old[str(m.id)].get("speaking", false))
	if _subscribed != cid:
		if _subscribed != "":
			_unsubscribe(_subscribed)
		for e in ["VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"]:
			_cmd("SUBSCRIBE", { "channel_id": cid }, e)
		_subscribed = cid
	if guild != "":
		if keep_guild == "":
			_cmd("GET_GUILD", { "guild_id": guild })
		_chan_queue.append(guild)
		_cmd("GET_CHANNELS", { "guild_id": guild })
	else:
		others = []
	changed.emit()


func _unsubscribe(cid: String) -> void:
	for e in ["VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"]:
		_cmd("UNSUBSCRIBE", { "channel_id": cid }, e)
	_subscribed = ""


static func _uid(vs: Dictionary) -> String:
	var user: Variant = vs.get("user", {})
	if user is Dictionary:
		return str(user.get("id", ""))
	return str(vs.get("user_id", ""))


## Sprachzustand von Discord in einen Eintrag übernehmen (neu oder vorhanden).
func _upsert(vs: Dictionary) -> Dictionary:
	var uid := _uid(vs)
	var m := member(uid)
	if m.is_empty():
		m = { "id": uid, "speaking": false }
		members.append(m)
	var user: Dictionary = vs.get("user", {}) if vs.get("user") is Dictionary else {}
	var nick := str(vs.get("nick", "")) if vs.get("nick") != null else ""
	var uname := str(user.get("global_name", "")) if user.get("global_name") != null else ""
	if uname == "":
		uname = str(user.get("username", m.get("name", "?")))
	m["name"] = nick if nick != "" else uname
	# Für die Zuordnung zu Steam-Freunden (call_invite.gd): alle Namen, unter denen man jemanden kennt.
	if str(user.get("username", "")) != "":
		m["username"] = str(user.username)
	if user.get("global_name") != null and str(user.global_name) != "":
		m["global_name"] = str(user.global_name)
	var av := str(user.get("avatar", "")) if user.get("avatar") != null else ""
	m["avatar"] = CDN % [uid, av] if av != "" else ""
	var st: Dictionary = vs.get("voice_state", {}) if vs.get("voice_state") is Dictionary else {}
	m["self_mute"] = bool(st.get("self_mute", false))
	m["self_deaf"] = bool(st.get("self_deaf", false))
	m["mute"] = bool(st.get("mute", false)) or bool(st.get("suppress", false))
	m["deaf"] = bool(st.get("deaf", false))
	if vs.has("volume"):
		m["volume"] = int(round(float(vs.volume)))
	elif not m.has("volume"):
		m["volume"] = 100
	if vs.has("mute"):
		m["local_mute"] = bool(vs.mute)
	elif not m.has("local_mute"):
		m["local_mute"] = false
	m["bot"] = bool(user.get("bot", false))
	m["me"] = uid == me_id and me_id != ""
	if m.me:
		m["self_mute"] = m.self_mute or self_mute
		m["self_deaf"] = m.self_deaf or self_deaf
	# Du stehst immer vorn, danach wie in Discord nach Namen.
	members.sort_custom(func(a, b):
		if a.get("me", false) != b.get("me", false):
			return a.get("me", false)
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	return m


func _mirror_me() -> void:
	for m in members:
		if m.get("me", false):
			m["self_mute"] = self_mute
			m["self_deaf"] = self_deaf


func _on_channels(data: Dictionary, gid := "") -> void:
	var list: Array = data.get("channels", []) if data.get("channels") is Array else []
	var want: Array = []
	_channel_names.clear()
	for c in list:
		if c is Dictionary and int(c.get("type", -1)) in [2, 13]:
			_channel_names[str(c.id)] = str(c.get("name", ""))
			if str(c.id) != str(channel.get("id", "")):
				want.append(str(c.id))
	others_guild = str(channel.get("guild_id", "")) if not channel.is_empty() or gid == "" else gid
	# Reihenfolge wie in Discord, Inhalte kommen mit GET_CHANNEL nach.
	var keep := {}
	for o in others:
		keep[str(o.id)] = o
	others = []
	for id in want.slice(0, MAX_OTHERS):
		var o: Dictionary = keep.get(id, { "id": id, "name": _channel_names[id], "members": [] })
		o["name"] = _channel_names[id]
		others.append(o)
		_cmd("GET_CHANNEL", { "channel_id": id })
	changed.emit()


## Server und ihre Sprachkanäle zum Beitreten (offizielle RPC-Befehle GET_GUILDS / GET_CHANNELS).
func load_guilds() -> void:
	if demo:
		guilds = [{ "id": "1", "name": "Retro-Runde", "icon": "" }, { "id": "2", "name": "Zockerbude", "icon": "" }, { "id": "3", "name": "Speedrun DE", "icon": "" }]
		changed.emit()
		return
	if ready_():
		_cmd("GET_GUILDS", {})


func browse_server(guild_id: String) -> void:
	browse_guild = guild_id
	browse = []
	Config.set_value("accounts.discord_last_guild", guild_id)
	if demo:
		if guild_id == "1":
			browse = others.duplicate(true)
			browse.push_front(
					{ "id": str(channel.get("id", "9")), "name": str(channel.get("name", "Zocken")),
					"members": members.map(func(m): return { "id": m.id, "name": m.name, "avatar": m.avatar }) })
		else:
			browse = [{ "id": "3%s1" % guild_id, "name": "Allgemein", "members": [{ "id": "31", "name": "Jonas", "avatar": "" }] },
				{ "id": "3%s2" % guild_id, "name": "Couch-Koop", "members": [] }]
		changed.emit()
		return
	_chan_queue.append(guild_id)
	_cmd("GET_CHANNELS", { "guild_id": guild_id })
	changed.emit()


## Bis Discord die Serverliste geschickt hat (höchstens timeout Sekunden).
func wait_guilds(timeout := 4.0) -> void:
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while guilds.is_empty() and guilds_error == "" and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.1).timeout


## Alle Kanäle eines Servers (wie GET_CHANNELS sie liefert: { id, name, type, position }), auch
## Sprachkanäle – capture_logic.discord_text_channels sucht die Textkanäle heraus. Einmal geholt,
## bleiben sie für diese Sitzung gemerkt. [] wenn Discord nicht antwortet.
func text_channels(guild_id: String, timeout := 5.0) -> Array:
	if demo:
		return [{ "id": "7%s1" % guild_id, "name": "allgemein", "type": 0, "position": 0 }, { "id": "7%s2" % guild_id, "name": "clips", "type": 0, "position": 1 },
			{ "id": "7%s3" % guild_id, "name": "Zocken", "type": 2, "position": 2 }, { "id": "7%s4" % guild_id, "name": "ankündigungen", "type": 5, "position": 3 }]
	if _guild_channels.has(guild_id):
		return _guild_channels[guild_id]
	if not ready_():
		return []
	_chan_queue.append(guild_id)
	_cmd("GET_CHANNELS", { "guild_id": guild_id })
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not _guild_channels.has(guild_id) and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.1).timeout
	return _guild_channels.get(guild_id, [])


func guild_name(guild_id: String) -> String:
	for g in guilds:
		if str(g.id) == guild_id:
			return str(g.name)
	return ""


func _on_guilds(data: Dictionary) -> void:
	guilds_error = ""
	guilds = []
	for g in data.get("guilds", []):
		if g is Dictionary:
			guilds.append({ "id": str(g.get("id", "")), "name": str(g.get("name", "")), "icon": str(g.get("icon_url", "")) if g.get("icon_url") != null else "" })
	changed.emit()
	# Zuletzt gewählten Server gleich öffnen (sonst den, in dem du gerade bist, sonst den ersten).
	if browse_guild == "" and not guilds.is_empty():
		var last := str(Config.get_value("accounts.discord_last_guild", ""))
		var pick := str(channel.get("guild_id", "")) if not channel.is_empty() else last
		if guild_name(pick) == "":
			pick = str(guilds[0].id)
		browse_server(pick)


func _on_browse_channels(data: Dictionary) -> void:
	# Was schon bekannt war, bleibt stehen, bis die neue Antwort da ist (kein leeres Aufblitzen).
	var keep := {}
	for b in browse:
		keep[str(b.id)] = b.get("members", [])
	browse = []
	for c in data.get("channels", []):
		if c is Dictionary and int(c.get("type", -1)) in [2, 13]:
			browse.append({ "id": str(c.id), "name": str(c.get("name", "")), "members": keep.get(str(c.id), []) })
	for b in browse.slice(0, 16):
		_cmd("GET_CHANNEL", { "channel_id": str(b.id) })
	changed.emit()


func _on_other_channel(data: Dictionary) -> void:
	var cid := str(data.get("id", ""))
	var leute := [{ "members": _people(data) }]
	# Kurz nach dem Verlassen nennt Discord dich manchmal noch im alten Kanal.
	if channel.is_empty() and Time.get_ticks_msec() - _weg_ms < WEG_MS:
		ohne_person(leute, me_id)
	for b in browse:
		if str(b.id) == cid:
			b["members"] = (leute[0].members as Array).duplicate()
			changed.emit()
	for o in others:
		if str(o.id) == cid:
			o["members"] = leute[0].members
			changed.emit()
			return


static func _people(data: Dictionary) -> Array:
	var ppl: Array = []
	for vs in data.get("voice_states", []):
		if vs is Dictionary:
			var user: Dictionary = vs.get("user", {}) if vs.get("user") is Dictionary else {}
			var uid := _uid(vs)
			var nick := str(vs.get("nick", "")) if vs.get("nick") != null else ""
			var av := str(user.get("avatar", "")) if user.get("avatar") != null else ""
			var gname: Variant = user.get("global_name")
			ppl.append(
					{ "id": uid, "name": nick if nick != "" else (str(gname) if gname != null else str(user.get("username", "?"))), "avatar": CDN % [uid, av] if av != ""
					else "" })
	return ppl


# --- Demo ----------------------------------------------------------------------------------

## Erfundener Kanal für Rundgang und Bildschirmfotos; Befehle wirken nur hier drin.
func _load_demo() -> void:
	demo = true
	me_id = "4"
	state = "bereit"
	self_mute = false
	self_deaf = false
	channel = { "id": "9", "name": "Zocken", "guild_id": "1", "guild": "Retro-Runde" }
	others_guild = "1"
	members = [
		{ "id": "4", "name": str(Config.get_value("system.player_name", "Spieler 1")), "avatar": "", "self_mute": false, "self_deaf": false, "mute": false,
			"deaf": false, "volume": 100, "local_mute": false, "speaking": false, "me": true },
		{ "id": "1", "name": "pixelpaul", "avatar": "", "self_mute": false, "self_deaf": false, "mute": false, "deaf": false, "volume": 100, "local_mute": false,
			"speaking": true, "me": false, "streaming": true, "game": "The Wind Waker" },
		{ "id": "2", "name": "Sana", "avatar": "", "self_mute": false, "self_deaf": false, "mute": false, "deaf": false, "volume": 80, "local_mute": false,
			"speaking": false, "me": false, "game": "Balatro" },
		{ "id": "3", "name": "Mira", "avatar": "", "self_mute": true, "self_deaf": false, "mute": false, "deaf": false, "volume": 100, "local_mute": false,
			"speaking": false, "me": false, "game": "Elden Ring" },
	]
	others = [
		{ "id": "11", "name": "Speedrun-Ecke", "members": [{ "id": "21", "name": "Kai", "avatar": "" }, { "id": "22", "name": "Noor", "avatar": "" }] },
		{ "id": "12", "name": "Kino", "members": [{ "id": "23", "name": "Lea", "avatar": "" }] },
		{ "id": "13", "name": "Ruhe", "members": [] },
	]
	if _demo_timer == null and not Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--uzai-") and str(a) != "--uzai-reel"):
		# Etwas Leben: abwechselnd spricht jemand.
		_demo_timer = Timer.new()
		_demo_timer.wait_time = 1.6
		_demo_timer.autostart = true
		_demo_timer.timeout.connect(func() -> void:
			for m in members:
				if m.get("me", false) or m.get("self_mute", false):
					continue
				var on := randf() < (0.55 if str(m.id) == "1" else 0.25)
				if bool(m.get("speaking", false)) != on:
					m["speaking"] = on
					speaking_changed.emit(str(m.id), on)
		)
		add_child(_demo_timer)
	update_notices()
	changed.emit()


func _demo_join(channel_id: String) -> void:
	for o in others:
		if str(o.id) == channel_id:
			var old := { "id": channel.get("id", ""), "name": channel.get("name", ""),
					"members": members.filter(func(m): return not m.get("me", false)).map(func(m): return { "id": m.id, "name": m.name, "avatar": m.avatar }) }
			var me: Array = members.filter(func(m): return m.get("me", false))
			channel = { "id": o.id, "name": o.name, "guild_id": "1", "guild": "Retro-Runde" }
			members = me.duplicate()
			for p in o.members:
				members.append(
						{ "id": p.id, "name": p.name, "avatar": p.avatar, "self_mute": false, "self_deaf": false, "mute": false, "deaf": false, "volume": 100,
						"local_mute": false, "speaking": false, "me": false })
			others.erase(o)
			if str(old.id) != "":
				others.insert(0, old)
			changed.emit()
			return

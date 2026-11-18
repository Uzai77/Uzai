extends Node
## Verbindung zu Steams Chat-Servern (CM) wie die Steam-App selbst: WebSocket, Nachrichten im
## protobuf-Format. Darüber laufen die QR-Anmeldung als „Steam-App“ und das Senden von
## Chat-Nachrichten – Steam bietet das Senden nicht über normale Web-Anfragen an (404).
## Uzai erscheint dabei nicht als zusätzlich „online“ (kein Statuswechsel), es schickt nur –
## außer während eines Emulator-/PC-Spiels bei geschlossenem Steam (siehe _send_games).
## Aufbau nach SteamKit/steam-session: [EMsg | Protobuf-Bit][Kopflänge][Kopf][Inhalt].
##
## Für Benachrichtigungen in Echtzeit hält keep_online() die Verbindung dauerhaft (Herzschlag,
## Wiederverbinden mit wachsender Pause) und meldet Steams Dienst-Benachrichtigungen
## (EMsg ServiceMethod, z. B. FriendMessagesClient.IncomingMessage#1) über notice.
## Läuft ein Emulator- oder PC-Spiel, meldet set_games_played() es Freunden als Nicht-Steam-Spiel.
## owned_games() holt alle gekauften Spiele (Player.GetOwnedGames) – ohne Web-API-Schlüssel.
## Über dieselbe Verbindung kommt der Status der Freunde sofort (ClientPersonaState, EMsg 766):
## wer online kommt, spielt oder geht. request_friend_data() fragt ihn gezielt ab (wie die
## Steam-App beim Öffnen der Freundesliste); Social führt ihn mit der Web-API zusammen. Das gilt
## nur für eine Sitzung mit eigenem sichtbaren Status (sees_presence).
## Mit der Freundesliste kommen auch Freundschaftsanfragen (requests); answer_request nimmt eine an
## oder lehnt sie ab – nur auf Knopfdruck.

signal notice(method: String, body: PackedByteArray)   ## Dienst-Benachrichtigung von Steam
signal live_changed(on: bool)                          ## Dauerverbindung steht / ist weg
signal persona(friends: Array)                         ## Status von Freunden (parse_persona_state)
signal friends_list(ids: Array, incremental: bool)     ## Freundesliste laut Steam (ClientFriendsList)
signal requests_changed                                ## Freundschaftsanfragen (requests) geändert
signal own_changed                                     ## dein Status, wie Freunde ihn sehen (own)

const Logdatei := preload("res://src/core/logdatei.gd")
const FriendRequests := preload("res://src/core/friend_requests.gd")
const InstallParse := preload("res://src/core/install_parse.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Fremd := preload("res://src/core/fremd.gd")
const PROTO_MASK := 0x80000000
const PROTOCOL_VERSION := 65580
const EMSG_MULTI := 1
const EMSG_SERVICE_METHOD := 146         ## Steam → Uzai: Benachrichtigung (target_job_name im Kopf)
const EMSG_SERVICE_RESPONSE := 147
const EMSG_SERVICE_CALL := 151
const EMSG_SERVICE_TO_CLIENT := 152      ## Steam → Uzai: Aufruf an den Client (wie 146 behandelt)
const EMSG_HEARTBEAT := 703
const EMSG_CHANGE_STATUS := 716
const EMSG_LOGON_RESPONSE := 751
const EMSG_LOGGED_OFF := 757
const EMSG_PERSONA_STATE := 766         ## Steam → Uzai: CMsgClientPersonaState (Status von Freunden)
const EMSG_FRIENDS_LIST := 767          ## Steam → Uzai: CMsgClientFriendsList (nach der Anmeldung)
const EMSG_REQUEST_FRIEND_DATA := 815   ## Uzai → Steam: CMsgClientRequestFriendData
const EMSG_GET_USER_STATS := 818        ## Uzai → Steam: CMsgClientGetUserStats (Erfolge eines Spiels)
const EMSG_GET_USER_STATS_RESPONSE := 819
const EMSG_GAMES_PLAYED := 5410         ## ClientGamesPlayedWithDataBlob: „Spielt …“
const EMSG_LOGON := 5514
const EMSG_PLAYING_STATE := 9600         ## Steam → Uzai: ClientPlayingSessionState (anderswo im Spiel?)
const EMSG_NONAUTHED := 9804
const EMSG_HELLO := 9805
const STEAM64 := 76561197960265728
const CM_LIST := "https://api.steampowered.com/ISteamDirectory/GetCMListForConnect/v1/?cellid=0&format=json"
const IDLE_CLOSE := 120.0         ## nach so vielen Sekunden ohne Aufgabe wieder trennen
const IDLE_CLOSE_PC := 5.0        ## … wenn Steam am PC angemeldet ist
const EMSG_LOGOFF := 706          ## ClientLogOff
const EMSG_REMOVE_FRIEND := 714   ## Uzai → Steam: CMsgClientRemoveFriend (Anfrage ablehnen)
const EMSG_ADD_FRIEND := 791      ## Uzai → Steam: CMsgClientAddFriend (Anfrage annehmen)
const EMSG_ADD_FRIEND_RESPONSE := 792
## Was Uzai über Freunde wissen will (EClientPersonaStateFlag): Status, Name, Query-Port, Quelle,
## Anwesenheit, zuletzt online, Spiel (Name und Daten), Rich Presence – wie die Steam-App.
const PERSONA_FLAGS := 1 | 2 | 4 | 8 | 16 | 64 | 256 | 512 | 4096
const AVATAR_URL := "https://avatars.steamstatic.com/%s_full.jpg"
const NO_AVATAR := "0000000000000000000000000000000000000000"
## Steam schickt Chat-Nachrichten nur an Sitzungen, die einen Online-Status gesetzt haben
## (steam-user: „friendMessage … as long as we're online“). „Unsichtbar“ (7) bekommt Nachrichten,
## zeigt Freunden aber „offline“. Ohne high_priority und nicht „vom Nutzer gewählt“, damit der
## Status der Steam-App am PC (falls sie läuft) maßgeblich bleibt.
const PERSONA_INVISIBLE := 7
const PERSONA_OFFLINE := 0
const PERSONA_ONLINE := 1
## Dein Steam-Status laut Steam (Social: GetPlayerSummaries.personastate), -1 = unbekannt.
## Uzai meldet der Dauerverbindung genau diesen Status – so ändert sich für Freunde nichts.
## „unsichtbar“ setzen war gefährlich: Steam übernimmt den Status kontoweit.
var persona_state := -1
var status_set := false
var user_pick := -1                ## im Guide gewählter Status (choose_status), -1 = keiner
var _pick_until := 0               ## bis dahin (ms) gilt die Wahl vor der Web-API
## „Spielt Nicht-Steam-Spiel: …“ wie steam-user gamesPlayed("Name"): Spiel-ID einer Verknüpfung,
## 15190414816125648896 = 0xD2CF31CB_02000000. GDScript-Zahlen sind vorzeichenbehaftet, darum in
## zwei Hälften (fixed64, little-endian: erst LO, dann HI).
const NONSTEAM_HI := 0xD2CF31CB
const NONSTEAM_LO := 0x02000000
const OS_TYPE := 20                ## Windows 11, wie bei der Anmeldung (steam-user nimmt denselben Wert)
var games_name := ""               ## gewünschter Spielname für Freunde ("" = kein Spiel)
var _games_sent := ""              ## in dieser Sitzung an Steam gemeldet
var playing_blocked := false       ## ein anderes Gerät spielt gerade (dann nichts melden)
var playing_app := 0               ## was dort läuft (App-ID, 0 = unbekannt oder Nicht-Steam-Spiel)
## Ein Spiel sehen Freunde nur bei sichtbarem Status (steam-user: erst setPersona(Online), dann
## gamesPlayed). Ist Steam am PC zu, ist niemand „online“: dann meldet Uzai für die Dauer des
## Spiels selbst „online“ (nicht vom Nutzer gewählt) und danach wieder „offline“.
var pc_signed_in := false          ## Steam am PC ist angemeldet (SteamChat fragt das jede Minute)
var _pc_noted := false
var pc_known := false              ## schon nachgesehen, ob Steam am PC läuft
var _raised := false               ## Uzai hat für das Spiel „online“ gemeldet
var _mit_pc := false               ## Uzai hat für das Spiel den Status von Steam am PC mitgemeldet (status_mit_pc)
var _persona_quiet_until := 0      ## bis dahin (ms) zeigt die Web-API noch Uzais eigenes „online“
const RECONNECT_MIN := 5.0
const RECONNECT_MAX := 300.0

## Sitzung beim Chat-Server: zu · verbinde (Serverliste, WebSocket) · offen (Hallo gesagt) · anmelden (Logon
## unterwegs) · angemeldet. Steam meldet ab: zurück zu „offen“; Trennen, Abriss oder Fehler: von überall „zu“.
const ZUSTAENDE := { "*": ["zu"], "zu": ["verbinde"], "verbinde": ["offen"], "offen": ["anmelden", "verbinde"],
	"anmelden": ["angemeldet", "offen"], "angemeldet": ["offen"] }
var state := "zu":
	set(neu):
		Zustand.wechsel("steam.verbindung", ZUSTAENDE, state, neu)
		state = neu
var last_error := ""
var _ws: WebSocketPeer
var _jobs := {}                    ## Job-ID -> { done, eresult, error, body }
var _job_next := 1
var _session := 0
var _steamid := 0
var _logon_result := -1
var _hb_every := 0.0
var _hb := 0.0
var _idle := 0.0
var _logged_for := ""              ## für welches Token angemeldet
var _own_state_logged := -1        ## zuletzt protokollierter eigener Status
var keep := ""                     ## Dauerverbindung mit diesem Zugang ("" = aus)
var live := false                  ## Dauerverbindung angemeldet und Status gesetzt
var keep_error := ""               ## warum die Dauerverbindung aufgegeben wurde
var reconnects := 0                ## Wiederverbindungen seit dem Start (für Tests und Protokoll)
var _backoff := RECONNECT_MIN
var _retry_at := 0                 ## Zeitpunkt (ms) des nächsten Verbindungsversuchs
var _keeping := false              ## ein Versuch läuft gerade
var friend_ids := {}               ## Steam-ID -> true: Freunde laut ClientFriendsList
var requests := {}                 ## Steam-ID -> 2 (Anfrage an dich) | 4 (von dir gesendet), laut ClientFriendsList
var persona_at := 0                ## Zeitpunkt (ms) der letzten Status-Meldung über diese Verbindung
var persona_count := 0             ## Status-Meldungen seit dem Start (für Tests und Protokoll)
var _requested := {}               ## in dieser Sitzung schon abgefragte Freunde
var _list_seen := false            ## in dieser Sitzung kam die Freundesliste schon (ClientFriendsList)
var _skip_logged := {}             ## Methode -> true: „übersprungen“ steht schon im Protokoll
## Nur eine Anmeldung zur Zeit (logon): Liefen zwei gleichzeitig, ging der zweite Logon auf dieselbe
## Verbindung, und Steam antwortete keinem (Protokoll des Nutzers: zweimal EResult -1).
var _logon_busy := false
var _logon_token := ""             ## Zugang der laufenden Anmeldung
var _holds := 0                    ## so viele Abfragen brauchen die Sitzung gerade (nicht schließen)
## Dein Status und Spiel, wie Steam sie Freunden zeigt (Player.GetPlayerLinkDetails#1 für dich):
## { at (Unix), state, game, game_id, name, avatar } – {} = noch nie abgefragt. Die Web-API lehnt den
## Zugang der QR-Anmeldung ab (HTTP 400), und ClientPersonaState gilt nur mit eigenem Status.
var own := {}
var _own_logged := ""
var _own_busy := false
var games_at := 0                  ## Zeitpunkt (Unix) der letzten Spielmeldung an Steam
## Dein Status in Steam am PC (aus Steams Dateien, SteamAmPc.pc_persona; SteamChat._check_pc setzt
## ihn jede Minute): EPersonaState, -1 = Steam am PC nicht angemeldet oder unbekannt. Nur gelesen –
## Uzai meldet deshalb nichts an Steam.
var pc_persona := -1
var pc_persona_src := ""
var _stats_wait := {}              ## App-ID -> Job-ID: ClientGetUserStats wartet auf Antwort
var _stats_busy := false
const RARE_RETRY_S := 30           ## kurze Sitzung gescheitert (keine Antwort): so bald neu versuchen


func _ready() -> void:
	_job_next = (randi() & 0xFFFFFF) << 16


func _process(dt: float) -> void:
	if _ws == null:
		if keep != "" and not _keeping and _retry_at > 0 and Time.get_ticks_msec() >= _retry_at:
			_retry_at = 0
			_keep_connect()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		if state != "zu":
			_log("Verbindung zu Steam getrennt (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()])
		_reset()
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	while _ws.get_available_packet_count() > 0:
		_handle(_ws.get_packet())
	_idle += dt
	if state == "angemeldet" and _hb_every > 0.0:
		_hb += dt
		if _hb >= _hb_every:
			_hb = 0.0
			_send(EMSG_HEARTBEAT, _header(), PackedByteArray())
	# Steam am PC angemeldet: Uzais Sitzung nur so kurz wie nötig (senden, Verlauf holen).
	if _idle > (IDLE_CLOSE_PC if pc_maybe() else IDLE_CLOSE) and _jobs.is_empty() and keep == "" and not in_use():
		close()


## Steam am PC angemeldet – oder (unter Windows) noch nicht nachgesehen: dann vorsichtshalber ja.
## OS.get_name statt OS.has_feature("windows"): Godot stürzte unter Linux (Tests, Proben) dreimal
## beim Start genau in dieser Zeile ab (Signal 11 in has_feature, etwa jeder fünfzigste Lauf). Die
## Ursache im Inneren ist nicht gefunden; ein Dauerlauf mit vielen Fäden stellte es nicht nach.
## get_name fragt dasselbe ohne diesen Weg – wie Config.is_windows() –, darum fragt im ganzen
## Programm niemand mehr has_feature("windows"). Kommt der Absturz woanders wieder, lag es nicht daran.
func pc_maybe() -> bool:
	return pc_signed_in or (OS.get_name() == "Windows" and not pc_known)


## Sieht diese Sitzung den Status der Freunde? Nur mit eigenem sichtbaren Status (wie in Steam
## gemeldet, im Guide gewählt oder für ein Spiel). Einer Sitzung ohne Status – etwa dem kurzen
## Chat-Zugang neben Steam am PC – meldet Steam die Freunde nicht verlässlich: Beim Nutzer standen
## so kurz nach dem Schreiben alle auf „offline“ (Fehler 36).
func sees_presence() -> bool:
	return state == "angemeldet" and (status_set or _raised)


## Sofort trennen, sobald nichts mehr läuft (Steam am PC wurde gerade angemeldet).
func close_when_idle() -> void:
	if keep == "" and _jobs.is_empty() and _ws != null and not in_use():
		close()


## Braucht gerade jemand die Sitzung (Anmeldung läuft, Abfrage dazwischen)? Dann nicht schließen:
## Die erste kurze Sitzung schloss sonst unter der zweiten weg (beide scheiterten).
func in_use() -> bool:
	return _logon_busy or _holds > 0


func close() -> void:
	if _ws:
		# Sauber abmelden (CMsgClientLogOff), statt die Sitzung bei Steam auslaufen zu lassen.
		if state == "angemeldet":
			_send(EMSG_LOGOFF, _header(), PackedByteArray())
		_ws.close()
	_reset()


func _reset() -> void:
	_ws = null
	state = "zu"
	# Eine neue Sitzung hat keinen Status, bis Uzai ihn meldet. Blieb das stehen (Dauerverbindung
	# vorher, dann Steam am PC an), galt die kurze Sitzung danach als „mit Status“ – und Uzai nahm
	# ihre Meldungen ernst, bei denen alle Freunde offline stehen (Fehler 36).
	status_set = false
	_set_live(false)
	if keep != "" and not _keeping and _retry_at == 0:
		_schedule_retry()
	_session = 0
	_logged_for = ""
	_hb_every = 0.0
	_games_sent = ""
	playing_blocked = false
	playing_app = 0
	_raised = false
	persona_at = 0
	_list_seen = false
	_requested.clear()
	for id in _jobs.keys():
		var j: Dictionary = _jobs[id]
		if not j.done:
			j["done"] = true
			j["eresult"] = 3
			j["error"] = "Verbindung getrennt"


# --- Verbindung -----------------------------------------------------------------------------

func _connect() -> bool:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and state != "zu":
		return true
	if state == "verbinde":
		# Ein anderer Aufruf verbindet gerade (holt etwa noch die Serverliste): auf ihn warten. Vorher
		# brach _wait_open ohne Verbindung sofort ab und setzte den laufenden Aufbau zurück.
		var wait_until := Time.get_ticks_msec() + 35000
		while state == "verbinde" and Time.get_ticks_msec() < wait_until:
			await get_tree().process_frame
		return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and state != "zu"
	state = "verbinde"
	# In einer eigenen Funktion: Bricht der Aufbau mit einem Fehler ab, bliebe „verbinde“ sonst für immer stehen, und
	# jeder spätere Aufruf wartete oben 35 s, um dann aufzugeben – kein Chat, keine Freunde bis zum Neustart.
	var ok := await _verbinden()
	if not ok and state == "verbinde":
		state = "zu"
	return ok


## Adresse eines Chat-Servers aus Steams Liste: nur Name und Port („ext1-fra1.steamserver.net:27019“). Alles andere
## (Pfad, Zugangsdaten, Leerzeichen) käme sonst mitten in die Adresse der Verbindung.
static var _ENDPUNKT := RegEx.create_from_string("^[A-Za-z0-9.-]{1,80}(:[0-9]{1,5})?$")


static func endpunkt_ok(e: String) -> bool:
	return _ENDPUNKT.search(e) != null


## Serverliste holen, bis zu drei Server versuchen, Hallo sagen (für _connect; erwartet den Stand „verbinde“).
func _verbinden() -> bool:
	var url := Config.probe_env("UZAI_STEAM_CM")
	if url == "":
		var r := await Net.get_json(CM_LIST)
		var list: Array = []
		for s in (Fremd.zeilen(r.get("data"), "response/serverlist") if Fremd.ja(r.get("ok")) else []):
			if str(s.get("type", "")) == "websockets" and str(s.get("realm", "steamglobal")) == "steamglobal" and endpunkt_ok(Fremd.text(s.get("endpoint"))):
				list.append(str(s.endpoint))
		if list.is_empty():
			state = "zu"
			last_error = "Steam-Server nicht gefunden. Ist das Internet da?"
			_log("%s (HTTP %d)" % [last_error, Fremd.zahl(r.get("code"))])
			return false
		# Bis zu drei verschiedene Server versuchen: Ein einzelner nicht erreichbarer Server ließ
		# sonst die ganze Anmeldung scheitern (dann gab es nur die Browser-Anmeldung, die nicht
		# senden darf – und nach dem Neustart wieder den QR-Code).
		list = list.slice(0, mini(8, list.size()))
		list.shuffle()
		for i in mini(3, list.size()):
			if await _open("wss://%s/cmsocket/" % list[i]):
				return _hello()
			state = "verbinde"
		state = "zu"
		return false
	if not await _open(url):
		return false
	return _hello()


## Eine WebSocket-Verbindung zu einem Server öffnen (false: nicht erreichbar).
func _open(url: String) -> bool:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 22
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(url)
	if err != OK:
		_reset()
		last_error = "Verbindung zu Steam ließ sich nicht öffnen."
		_log(last_error + " " + url)
		return false
	if not await _wait_open():
		_log("… Server war " + url)
		return false
	return true


func _hello() -> bool:
	state = "offen"
	_idle = 0.0
	_send(EMSG_HELLO, _header(0, 0), Pb.f_varint(1, PROTOCOL_VERSION))
	return true


func _wait_open() -> bool:
	var until := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < until:
		if _ws == null:
			break
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			return true
		if st == WebSocketPeer.STATE_CLOSED:
			break
		await get_tree().process_frame
	last_error = "Steam ist gerade nicht erreichbar."
	_log("Verbindung kam nicht zustande")
	_reset()
	return false


## Läufe von logon, die gerade unterwegs sind (siehe dort).
var _logon_offen := 0


## Anmelden mit einem Token der Steam-App (Zielgruppe „client“). "" = angemeldet, sonst der Grund.
## Immer nur eine Anmeldung zur Zeit; wer dazukommt, wartet auf sie und nutzt dieselbe Sitzung.
func logon(refresh_token: String) -> String:
	_logon_offen += 1
	var ergebnis: String = await _logon_lauf(refresh_token)
	_logon_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und logon täte bis zum Neustart nichts mehr.
	if _logon_offen == 0 and _logon_busy:
		_logon_busy = false
	# "" heißt „angemeldet“ – und ist zugleich das, was nach einem abgebrochenen Lauf zurückkommt. Ohne stehende
	# Sitzung ist es keine Anmeldung (auch nicht, wenn Steam im selben Augenblick getrennt hat).
	if ergebnis == "" and state != "angemeldet":
		ergebnis = "Steam hat nicht geantwortet. Gleich noch einmal versuchen."
	return ergebnis


func _logon_lauf(refresh_token: String) -> String:
	if _same_login(refresh_token):
		return ""
	var wait_until := Time.get_ticks_msec() + 30000
	while _logon_busy and Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame
	if _same_login(refresh_token):
		return ""
	if _logon_busy:
		return "Steam hat nicht geantwortet. Gleich noch einmal versuchen."
	_logon_busy = true
	var why := await _logon_now(refresh_token)
	_logon_busy = false
	return why


## Steht die Sitzung schon für dieses Konto? Hat Steam den Zugang erneuert (neues Token, gleiches
## Konto), gilt sie weiter – eine zweite Anmeldung auf derselben Verbindung nähme Steam nicht an.
func _same_login(refresh_token: String) -> bool:
	if state != "angemeldet" or _logged_for == "":
		return false
	if _logged_for == refresh_token:
		return true
	if str(SteamChat.jwt_claims(_logged_for).get("sub", "")) == str(SteamChat.jwt_claims(refresh_token).get("sub", "-")):
		_logged_for = refresh_token
		return true
	return false


func _logon_now(refresh_token: String) -> String:
	# Angemeldet, aber als anderes Konto: erst trennen (zweiter Logon auf derselben Verbindung geht nicht).
	if state == "angemeldet":
		close()
	if not await _connect():
		return last_error
	var claims := SteamChat.jwt_claims(refresh_token)
	if not Fremd.liste(claims.get("aud")).has("client"):
		return "Für das Senden braucht Uzai eine Anmeldung als Steam-App. Bitte einmal neu mit dem QR-Code anmelden."
	# Wie steam-user/SteamKit: Bei der Anmeldung mit Zugang steht die eigene Steam-ID im Kopf
	# (aus dem Zugang), nicht die allgemeine – sonst lehnt Steam ab.
	var sid := str(claims.get("sub", ""))
	var my_id := int(sid) if sid.is_valid_int() else 0
	if my_id <= STEAM64:
		return "Die Steam-Anmeldung enthält keine Steam-ID. Bitte einmal neu mit dem QR-Code anmelden."
	state = "anmelden"
	_logon_result = -1
	var body := PackedByteArray()
	body.append_array(Pb.f_varint(1, PROTOCOL_VERSION))
	body.append_array(Pb.f_varint(5, 1771))        # client_package_version (wie steam-user)
	body.append_array(Pb.f_string(6, "english"))
	body.append_array(Pb.f_varint(7, OS_TYPE))     # Windows 11
	body.append_array(Pb.f_varint(8, 1))           # Anmeldung merken
	# Eigene „Sitzungsnummer“, damit die laufende Steam-App am PC nicht abgemeldet wird.
	body.append_array(Pb.f_msg(11, Pb.f_fixed32(1, randi() & 0x7FFFFFFF)))
	body.append_array(Pb.f_varint(21, 2))          # qos_level
	body.append_array(Pb.f_varint(33, 2))          # neuer Chat
	body.append_array(Pb.f_string(96, "Uzai"))
	body.append_array(Pb.f_varint(102, 1))         # supports_rate_limit_response
	body.append_array(Pb.f_string(108, refresh_token))
	_logon_token = refresh_token
	_send(EMSG_LOGON, _header(my_id, 0), body)
	_log("Anmeldung als %s …" % sid)
	var until := Time.get_ticks_msec() + 12000
	while _logon_result < 0 and Time.get_ticks_msec() < until and state != "zu":
		await get_tree().process_frame
	if _logon_result == 1:
		_logged_for = refresh_token
		return ""
	var why := "Steam hat die Anmeldung abgelehnt. Unter Einstellungen → Konten den Steam-Chat neu verbinden." if _logon_result >= 0 else "Steam hat nicht geantwortet. Gleich noch einmal versuchen."
	_log("Anmeldung: %s (EResult %d)" % [why, _logon_result])
	close()
	return why


# --- Dauerverbindung für Benachrichtigungen ------------------------------------------------

## Verbindung halten, solange Uzai läuft: Steam schickt neue Nachrichten und „schreibt gerade“
## sofort (notice). Trennt Steam, verbindet Uzai nach 5 s, 10 s, 20 s … (höchstens 5 Min.) neu.
func keep_online(refresh_token: String) -> void:
	if refresh_token == "":
		stop_keep()
		return
	if keep == refresh_token and (live or _keeping or _retry_at > 0):
		return
	keep = refresh_token
	keep_error = ""
	_backoff = RECONNECT_MIN
	_retry_at = 0
	_keep_connect()


## Dauerverbindung beenden. Die Verbindung selbst trennt sich nach IDLE_CLOSE von allein
## (laufende Sendungen dürfen fertig werden).
func stop_keep(why := "") -> void:
	var was := keep != ""
	keep = ""
	_retry_at = 0
	_set_live(false)
	_send_games("Dauerverbindung beendet")
	# Steht im Protokoll, damit klar ist: kein Abriss, Uzai hat die Sitzung selbst geschlossen.
	if was and why != "":
		_log("Dauerverbindung beendet (%s)" % why)


func _keep_connect() -> void:
	if keep == "" or _keeping:
		return
	_keeping = true
	var tok := keep
	var why := await logon(tok)
	_keeping = false
	if keep != tok:
		# Inzwischen aus- oder mit neuem Zugang eingeschaltet.
		if keep != "" and not live:
			_keep_connect()
		return
	if why == "" and state == "angemeldet":
		_backoff = RECONNECT_MIN
		status_set = false
		_send_status()
		_idle = 0.0
		_set_live(true)
		_send_games()
		_log(
				"Dauerverbindung steht (%s)" % ("Status wie in Steam, Nachrichten kommen sofort" if status_set else "Status unbekannt oder offline – unverändert gelassen"))
		# Was Freunde jetzt von dir sehen (auch ohne Web-API und ohne eigenen Status der Sitzung).
		refresh_own()
		return
	# Zugang abgelehnt (5 falsches Passwort/Token, 15 Zugriff verweigert): Neuversuche helfen nicht.
	if _logon_result in [5, 15]:
		keep_error = why
		keep = ""
		_log("Dauerverbindung aufgegeben: " + why)
		_set_live(false)
		return
	_schedule_retry()


## Deinen Steam-Status setzen (aus Social). Steht die Dauerverbindung schon, gleich melden.
## Solange Uzai selbst „online“ gemeldet hat (und kurz danach), zeigt die Web-API dieses
## „online“ – das zählt nicht als dein Status, sonst hielte Uzai dich nach dem Spiel weiter online.
func set_persona(st: int) -> void:
	if st == PERSONA_ONLINE and (_raised or Time.get_ticks_msec() < _persona_quiet_until):
		return
	# Im Guide gewählt (choose_status): kurz gilt die Wahl (die Web-API hinkt nach). Danach zählt
	# Steam – nur „unsichtbar“ meldet Steam als 0 und bleibt deshalb stehen.
	if user_pick >= 0:
		if Time.get_ticks_msec() < _pick_until:
			return
		if st > 0:
			user_pick = -1
		elif user_pick == PERSONA_INVISIBLE:
			st = PERSONA_INVISIBLE
	persona_state = st
	if live and not status_set:
		_send_status()
	_send_games()


## Steam liefert Nachrichten nur an Sitzungen mit Status. Gemeldet wird nur ein bekannter,
## sichtbarer Status (online, abwesend …) – genau der, den du schon hast. Bei offline/unsichtbar
## (Steam meldet beides als 0) bleibt alles, wie es ist; dann fragt Uzai regelmäßig nach.
func _send_status() -> void:
	if persona_state <= 0 or persona_state == PERSONA_INVISIBLE or state != "angemeldet":
		return
	# Steam am PC ist angemeldet: Dein Status gehört der Steam-App. Meldete Uzai ihn auch, galt
	# Uzais Sitzung als Quelle – riss sie ab, stand das ganze Konto auf offline (alle Freunde
	# offline, in Uzai und in Steam am PC; so beim Nutzer). Nachrichten holt Uzai dann per Abfrage.
	# Erst wissen, ob Steam am PC läuft (SteamChat fragt das gleich nach dem Start).
	if not pc_known:
		return
	if pc_signed_in:
		if not _pc_noted:
			_pc_noted = true
			_log("Steam am PC ist angemeldet – Uzai meldet keinen eigenen Status")
		return
	_send(EMSG_CHANGE_STATUS, _header(), status_body(persona_state))
	_log("Status gemeldet: %d (wie in Steam)" % persona_state)
	# Dein echter Status gilt jetzt (Steam am PC ist da): nach dem Spiel nicht „offline“ melden.
	_raised = false
	var was := status_set
	status_set = true
	if not was:
		live_changed.emit(live)


## Status melden, falls noch nicht geschehen (nachdem feststeht, ob Steam am PC läuft).
func send_status_if_needed() -> void:
	if live and not status_set:
		_send_status()


## Status, den du im Guide gewählt hast (my_status.gd), über Uzais eigene Sitzung setzen – nur,
## wenn Steam am PC nicht angemeldet ist; sonst ändert Uzai ihn über die Steam-App selbst
## (steam://friends/status/…). Rückgabe: "" oder warum nicht.
func choose_status(refresh_token: String, st: int) -> String:
	if pc_maybe():
		return "Steam am PC ist angemeldet – der Status gehört dort der Steam-App."
	if refresh_token == "":
		return "Nicht bei Steam angemeldet."
	var why := await logon(refresh_token)
	if why != "":
		return why
	_send(EMSG_CHANGE_STATUS, _header(), user_status_body(st))
	_log("Status im Guide gewählt: %d" % st)
	user_pick = st
	_pick_until = Time.get_ticks_msec() + 180000
	persona_state = st
	_raised = false
	_idle = 0.0
	var was := status_set
	status_set = st > 0 and st != PERSONA_INVISIBLE
	if was != status_set:
		live_changed.emit(live)
	return ""


## ClientChangeStatus für eine Wahl des Nutzers: Status und persona_set_by_user (5).
static func user_status_body(st: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(Pb.f_varint(1, st))
	b.append_array(Pb.f_varint(5, 1))
	return b


## Inhalt von ClientChangeStatus: der Status, ohne Vorrang, nicht vom Nutzer gewählt.
static func status_body(st: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(Pb.f_varint(1, st))
	b.append_array(Pb.f_varint(4, 0))
	b.append_array(Pb.f_varint(5, 0))
	return b


func _schedule_retry() -> void:
	if keep == "":
		return
	_retry_at = Time.get_ticks_msec() + int(_backoff * 1000.0)
	_log("Neuer Versuch in %d s" % int(_backoff))
	_backoff = minf(_backoff * 2.0, RECONNECT_MAX)
	reconnects += 1


func _set_live(on: bool) -> void:
	if live == on:
		return
	live = on
	live_changed.emit(on)


## Freunden „Spielt Nicht-Steam-Spiel: <Titel>“ zeigen ("" = Spiel beendet). Nur über die
## Dauerverbindung; steht sie noch nicht, wird es gemeldet, sobald sie steht (auch nach dem
## Wiederverbinden). Ohne Steam-Anmeldung in Uzai passiert nichts.
## why: warum das Spiel endet (fürs Protokoll, etwa „Spielprozess beendet nach 33 s“).
func set_games_played(title: String, why := "") -> void:
	games_name = title.strip_edges()
	_send_games(why)


## Was Uzai Steam als Spiel meldet (rein, getestet): nur mit stehender Dauerverbindung und solange
## nicht Steam am PC (oder ein anderes Gerät) selbst spielt; sonst nichts.
static func games_want(title: String, is_live: bool, blocked: bool) -> String:
	return title if is_live and not blocked else ""


func _send_games(why := "") -> void:
	if state != "angemeldet":
		return
	var want := games_want(games_name, live, playing_blocked)
	# Steam on the PC is signed in: without a status, Steam shows a game from this session to nobody, so friends
	# would not see emulator and non-Steam games. For the duration of the game Uzai reports exactly the status that
	# Steam on the PC already shows (online, away …), never offline or invisible, and nothing afterwards: the session
	# logs off cleanly (close: ClientLogOff) and Steam on the PC remains the source.
	var mit_pc := status_mit_pc(want != "", status_set, persona_state, pc_signed_in and pc_known, user_pick)
	if mit_pc > 0 and not _mit_pc:
		_send(EMSG_CHANGE_STATUS, _header(), status_body(mit_pc))
		_mit_pc = true
		_games_sent = ""          # Steam nahm das Spiel ohne Status nicht an: gleich noch einmal melden
		_log("Status für das Spiel: %d wie Steam am PC (sonst sähen Freunde das Spiel nicht)" % mit_pc)
	elif want == "" and _mit_pc:
		_mit_pc = false
	# Unbekannt, ob Steam am PC läuft (Helfer antwortet nicht): wie „läuft“ behandeln – lieber kein
	# Status als ein Status, der Steam am PC alle Freunde offline zeigen lässt.
	if want != "" and not _raised and user_pick != PERSONA_OFFLINE and needs_raise(status_set, persona_state, pc_signed_in or not pc_known):
		_send(EMSG_CHANGE_STATUS, _header(), status_body(PERSONA_ONLINE))
		_raised = true
		_log("Status für das Spiel: online (Steam am PC ist zu, sonst sähen Freunde nichts)")
	if want != _games_sent:
		_send(EMSG_GAMES_PLAYED, _header(), games_played_body(want))
		_games_sent = want
		games_at = int(Time.get_unix_time_from_system())
		_log("Spielt: " + (want if want != "" else "nichts") + (" (%s)" % why if want == "" and why != "" else ""))
		# Kurz danach nachsehen, was Steam Freunden wirklich zeigt (eine Zeile im Protokoll).
		if want != "":
			_confirm_own.call_deferred()
	# Spiel vorbei: wieder „offline“ wie vorher. Spielt die Steam-App am PC gerade, ist sie online –
	# dann nichts melden (sonst stünde das ganze Konto auf „offline“).
	if want == "" and _raised and not playing_blocked:
		_send(EMSG_CHANGE_STATUS, _header(), status_body(PERSONA_OFFLINE))
		_raised = false
		_persona_quiet_until = Time.get_ticks_msec() + 180000
		_log("Status nach dem Spiel: wieder offline")


## Rein: Muss Uzai für das Spiel „online“ melden? Nur wenn kein sichtbarer Status gesetzt ist,
## Steam am PC nicht angemeldet ist (dann wäre offline/unsichtbar dort deine Wahl) und du nicht
## ausdrücklich unsichtbar bist.
static func needs_raise(status_is_set: bool, persona: int, pc_on: bool) -> bool:
	return not status_is_set and not pc_on and persona != PERSONA_INVISIBLE


## Rein: Welchen Status Uzai für ein laufendes Nicht-Steam-Spiel neben Steam am PC meldet (0 = keinen). Nur bei
## angemeldetem Steam am PC, noch ohne eigenen Status der Sitzung, und nur einen sichtbaren, bekannten Status – nie
## offline oder unsichtbar, auch nicht, wenn du im Guide offline gewählt hast.
static func status_mit_pc(spielt: bool, status_is_set: bool, persona: int, pc_on: bool, pick: int) -> int:
	if not spielt or status_is_set or not pc_on or pick == PERSONA_OFFLINE or pick == PERSONA_INVISIBLE:
		return 0
	if persona <= 0 or persona == PERSONA_INVISIBLE:
		return 0
	return persona


## Was Freunde gerade sehen ("" = nichts).
func showing() -> String:
	return _games_sent


## Inhalt von CMsgClientGamesPlayed: games_played (1) = { game_id (2, fixed64),
## game_extra_info (7) } – leer heißt „spielt nichts“ –, dazu client_os_type (2).
static func games_played_body(title: String) -> PackedByteArray:
	var b := PackedByteArray()
	if title != "":
		var id := PackedByteArray()
		id.resize(8)
		id.encode_u32(0, NONSTEAM_LO)
		id.encode_u32(4, NONSTEAM_HI)
		var g := Pb.key(2, 1)
		g.append_array(id)
		g.append_array(Pb.f_string(7, title))
		b.append_array(Pb.f_msg(1, g))
	b.append_array(Pb.f_varint(2, OS_TYPE))
	return b


# --- Status der Freunde ----------------------------------------------------------------------

## Status, Name und Spiel dieser Freunde bei Steam abfragen (CMsgClientRequestFriendData:
## persona_state_requested (1), friends (2, fixed64 je Freund)). Die Antworten kommen als
## ClientPersonaState (persona). force = false: nur, wer in dieser Sitzung noch nicht dran war.
## Rückgabe: Anzahl abgefragter Freunde (0 ohne Anmeldung am Chat-Server oder ohne eigenen
## Status – siehe sees_presence; gefragt wird dann, sobald der Status steht).
func request_friend_data(ids: Array, force := false) -> int:
	if not sees_presence():
		return 0
	var want: Array = []
	for raw in ids:
		var id := str(raw)
		if id.is_valid_int() and int(id) > STEAM64 and (force or not _requested.has(id)) and not want.has(id):
			want.append(id)
	for i in range(0, want.size(), 100):
		var b := Pb.f_varint(1, PERSONA_FLAGS)
		for id in want.slice(i, i + 100):
			b.append_array(Pb.f_fixed64(2, int(id)))
			_requested[id] = true
		_send(EMSG_REQUEST_FRIEND_DATA, _header(), b)
	return want.size()


## CMsgClientPersonaState: status_flags (1), friends (2) = { friendid (1, fixed64),
## persona_state (2), game_played_app_id (3), game_server_ip (4), game_server_port (5),
## player_name (15), avatar_hash (31), last_logoff (45), game_name (55), gameid (56, fixed64) }.
## Steam schickt nur, was sich geändert hat: status = true heißt, Status und Spiel stehen drin
## (fehlt das Spiel, spielt der Freund nichts). [{ id, status, state, app_id, game_id, game_name,
## server, name?, avatar?, last_logoff? }]
static func parse_persona_state(body: PackedByteArray) -> Array:
	var d := Pb.decode(body)
	var flags := Pb.zahl(d, 1, 0)
	var out: Array = []
	for raw in d.get(2, []):
		if not (raw is PackedByteArray):
			continue
		var f := Pb.decode(raw)
		var id := Pb.zahl(f, 1, 0)
		if id <= STEAM64:
			continue
		var p := { "id": str(id), "status": (flags & 1) != 0 or f.has(2) }
		if bool(p.status):
			var app := Pb.zahl(f, 3, 0)
			var gid := Pb.zahl(f, 56, 0)
			p["state"] = Pb.zahl(f, 2, 0)
			p["app_id"] = app
			p["game_id"] = str(app) if app > 0 else (InstallParse.u64_text(gid) if gid != 0 else "")
			p["game_name"] = Pb.text(f, 55)
			var ip := Pb.zahl(f, 4, 0)
			p["server"] = "%d.%d.%d.%d:%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255, Pb.zahl(f, 5, 0)] if ip != 0 else ""
		if f.has(15):
			p["name"] = Pb.text(f, 15)
		if f.has(31):
			p["avatar"] = avatar_url(Pb.first(f, 31, PackedByteArray()))
		if f.has(45):
			p["last_logoff"] = Pb.zahl(f, 45, 0)
		out.append(p)
	return out


## Meldungen ohne Status und Spiel (für eine Sitzung, die den Status nicht verlässlich sieht).
static func without_status(list: Array) -> Array:
	var out: Array = []
	for p in list:
		var q: Dictionary = (p as Dictionary).duplicate()
		for k in ["state", "app_id", "game_id", "game_name", "server"]:
			q.erase(k)
		q["status"] = false
		out.append(q)
	return out


## CMsgClientFriendsList: bincremental (1), friends (2) = { ulfriendid (1, fixed64),
## efriendrelationship (2; 3 = befreundet, 2 = Anfrage an dich, 4 = von dir gesendet, 0 = nicht
## mehr) }. Nur Personen, keine Gruppen.
## { incremental, add: [Steam-ID], remove: [Steam-ID], requests: { Steam-ID: 2|4 } }
static func parse_friends_list(body: PackedByteArray) -> Dictionary:
	var d := Pb.decode(body)
	var add: Array = []
	var remove: Array = []
	var req := {}
	for raw in d.get(2, []):
		if not (raw is PackedByteArray):
			continue
		var f := Pb.decode(raw)
		var id := Pb.zahl(f, 1, 0)
		if id <= STEAM64 or id >= STEAM64 + (1 << 32):
			continue
		var rel := Pb.zahl(f, 2, 0)
		if rel == 3:
			add.append(str(id))
		else:
			remove.append(str(id))
			if rel == 2 or rel == 4:
				req[str(id)] = rel
	return { "incremental": Pb.zahl(d, 1, 0) != 0, "add": add, "remove": remove, "requests": req }


## Anfragen nach einer Freundesliste von Steam: Die erste (nicht schrittweise) ersetzt alles,
## danach ändert jede Meldung nur die genannten Personen. true, wenn sich etwas geändert hat.
static func apply_requests(cur: Dictionary, fl: Dictionary) -> bool:
	var before := cur.duplicate()
	if not bool(fl.get("incremental", false)):
		cur.clear()
	for id in fl.get("add", []) + fl.get("remove", []):
		cur.erase(str(id))
	var req: Dictionary = fl.get("requests", {})
	for id in req:
		cur[str(id)] = int(req[id])
	return cur != before


# --- Freundschaftsanfragen -------------------------------------------------------------------

## Eine Anfrage an dich annehmen (ClientAddFriend, wie „Annehmen“ in der Steam-App) oder ablehnen
## (ClientRemoveFriend, wie „Ignorieren“). Nur auf Knopfdruck – darum darf das wie das Senden
## einer Nachricht kurz eine Sitzung öffnen, auch wenn Steam am PC läuft. "" oder warum nicht.
func answer_request(refresh_token: String, id: String, accept: bool) -> String:
	if refresh_token == "":
		return "Nicht bei Steam angemeldet."
	if int(requests.get(id, 0)) != 2:
		return "Diese Anfrage gibt es nicht mehr."
	var why := await logon(refresh_token)
	if why != "":
		return why
	_idle = 0.0
	if accept:
		var r := await _job(EMSG_ADD_FRIEND, Pb.f_fixed64(1, int(id)))
		if bool(r.done):
			var res := parse_add_response(r.body)
			_log("Anfrage %s angenommen: EResult %d" % [id, int(res.eresult)])
			if int(res.eresult) != 1:
				return FriendRequests.steam_error(int(res.eresult))
			requests.erase(id)
			friend_ids[id] = true
			requests_changed.emit()
			return ""
	else:
		_send(EMSG_REMOVE_FRIEND, _header(), Pb.f_fixed64(1, int(id)))
		_log("Anfrage %s abgelehnt" % id)
	# Ohne direkte Antwort: Steam schickt die geänderte Freundesliste – darauf kurz warten.
	var until := Time.get_ticks_msec() + 8000
	while requests.has(id) and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.2).timeout
	return "" if not requests.has(id) else "Steam hat nicht geantwortet."


## CMsgClientAddFriendResponse: eresult (1, sonst 2 = Fehler), steam_id_added (2, fixed64),
## persona_name_added (3).
static func parse_add_response(body: PackedByteArray) -> Dictionary:
	var d := Pb.decode(body)
	var id := Pb.zahl(d, 2, 0)
	return { "eresult": Pb.zahl(d, 1, 2), "id": str(id) if id > STEAM64 else "", "name": Pb.text(d, 3) }


## Nachricht mit Auftragsnummer (jobid_source) schicken und auf die Antwort mit derselben Nummer
## warten (höchstens 10 s). { done, body }
func _job(emsg: int, body: PackedByteArray) -> Dictionary:
	var id := _job_next
	_job_next += 1
	_jobs[id] = { "done": false, "eresult": 2, "error": "", "body": PackedByteArray() }
	var h := _header()
	h.append_array(Pb.f_fixed64(10, id))
	_send(emsg, h, body)
	var until := Time.get_ticks_msec() + 10000
	while not bool(_jobs[id].done) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	var j: Dictionary = _jobs[id]
	_jobs.erase(id)
	return { "done": bool(j.done), "body": j.body }


## Adresse des Profilbilds aus dem Hash ("" = Standardbild).
static func avatar_url(hash_bytes: Variant) -> String:
	if not (hash_bytes is PackedByteArray) or (hash_bytes as PackedByteArray).is_empty():
		return ""
	var hx := (hash_bytes as PackedByteArray).hex_encode()
	return "" if hx == NO_AVATAR else AVATAR_URL % hx


# --- Gekaufte Spiele --------------------------------------------------------------------------

## Alle Spiele des Kontos über Steams Chat-Server (Player.GetOwnedGames#1, wie die Steam-App).
## Braucht nur die QR-Anmeldung als Steam-App, keinen Web-API-Schlüssel. Ergebnis im Format der
## Web-API: [{ appid, name, playtime_forever, rtime_last_played }]; [] wenn es nicht ging.
func owned_games(refresh_token: String, steamid: int) -> Array:
	var r := await games_of(refresh_token, steamid)
	if not bool(r.ok):
		return []
	_log("Gekaufte Spiele über Steam: %d" % (r.games as Array).size())
	return r.games


## Spiele eines Kontos (deines oder eines Freundes, für die Profilseite) über Player.GetOwnedGames#1.
## user = true: auf Knopfdruck (Profil geöffnet) – darf wie das Senden kurz eine Sitzung öffnen.
## { ok, eresult, games } – ok mit leerer Liste heißt bei Freunden meist „Bibliothek privat“.
func games_of(refresh_token: String, steamid: int, user := false) -> Dictionary:
	var req := PackedByteArray()
	req.append_array(Pb.f_varint(1, steamid))
	req.append_array(Pb.f_varint(2, 1))          # include_appinfo (Namen)
	req.append_array(Pb.f_varint(3, 1))          # include_played_free_games
	var r := await call_authed(refresh_token, "Player.GetOwnedGames#1", req, user)
	return { "ok": bool(r.ok), "eresult": int(r.eresult), "games": parse_owned_games(r.body) if bool(r.ok) else [] }


## CPlayer_GetOwnedGames_Response: games (2) = { appid (1), name (2), playtime_2weeks (3),
## playtime_forever (4), rtime_last_played (11) }.
static func parse_owned_games(body: PackedByteArray) -> Array:
	var out: Array = []
	var d := Pb.decode(body)
	for raw in d.get(2, []):
		if not (raw is PackedByteArray):
			continue
		var g := Pb.decode(raw)
		var appid := Pb.zahl(g, 1, 0)
		if appid <= 0:
			continue
		out.append({ "appid": appid, "name": Pb.text(g, 2).left(200), "playtime_forever": Pb.zahl(g, 4, 0),
			"playtime_2weeks": Pb.zahl(g, 3, 0), "rtime_last_played": Pb.zahl(g, 11, 0) })
	return out


# --- Profilhintergrund ohne Web-API ----------------------------------------------------------

## Hintergrund des Steam-Profils über Player.GetProfileItemsEquipped#1 (wie die Steam-App), wenn die
## Web-API ablehnt. Pfad unter den Community-Bildern („items/…“), "" ohne Hintergrund oder Antwort.
func profile_background(refresh_token: String, steamid: int, user := false) -> String:
	var req := PackedByteArray()
	req.append_array(Pb.f_fixed64(1, steamid))
	var r := await call_authed(refresh_token, ITEMS, req, user)
	return parse_profile_background(r.body) if bool(r.ok) else ""


## CPlayer_GetProfileItemsEquipped_Response: profile_background (1) = ProfileItem { image_large (3) }.
## Nur ein relativer Pfad zählt (keine fremde Adresse, kein „..“) – die Adresse setzt der Aufrufer.
static func parse_profile_background(body: PackedByteArray) -> String:
	var raw: Variant = Pb.first(Pb.decode(body), 1, null)
	if not (raw is PackedByteArray):
		return ""
	var img := Pb.text(Pb.decode(raw), 3).strip_edges().trim_prefix("/").left(300)
	if img == "" or img.contains("://") or img.contains("..") or img.contains("\\"):
		return ""
	return img


# --- Erfolge ohne Web-API ---------------------------------------------------------------------

## Erfolge über Steams Chat-Server (ClientGetUserStats, wie die Steam-App für ein Spiel und für den
## Vergleich mit Freunden). pairs: [[App-ID, SteamID64]]; alle in einer Sitzung (eine Pforte, wie
## player_details). Die Antworten (CMsgClientGetUserStatsResponse) liest SteamErfolge.parse_user_stats.
## { ok, error, asked, results: { "<App-ID>:<SteamID64>": Antwort (Bytes) } }
func user_stats(refresh_token: String, pairs: Array, user := false) -> Dictionary:
	var out := { "ok": false, "error": "", "asked": 0, "results": {} }
	var want: Array = []
	for p in pairs:
		if p is Array and (p as Array).size() >= 2 and int(p[0]) > 0 and str(p[1]).is_valid_int() and int(str(p[1])) > STEAM64:
			want.append([int(p[0]), int(str(p[1]))])
	if want.is_empty():
		out.ok = true
		return out
	var gate := _session_gate(USER_STATS, user)
	if not bool(gate.ok):
		out.error = "Steam am PC ist angemeldet"
		return out
	# Die Fragen laufen in einer eigenen Funktion: Bricht sie ab, wird _holds hier trotzdem zurückgezählt. Sonst gälte
	# die Sitzung für immer als gebraucht und schlösse neben Steam am PC nie wieder (dort stehen dann alle Freunde
	# auf „offline“).
	_holds += 1
	var why := await logon(refresh_token)
	out.error = why
	if why == "":
		await _user_stats_fragen(want, out)
	_holds -= 1
	out.ok = not (out.results as Dictionary).is_empty()
	if not bool(out.ok):
		if out.error == "":
			out.error = "Steam hat nicht geantwortet."
		_rare_failed(USER_STATS, bool(gate.brief))
	_log("Erfolge über den Chat-Server (ClientGetUserStats): %d von %d beantwortet" % [(out.results as Dictionary).size(), int(out.asked)])
	if bool(gate.brief):
		close_when_idle()
	return out


func _user_stats_fragen(want: Array, out: Dictionary) -> void:
	var misses := 0
	for p in want.slice(0, 40):
		out.asked += 1
		var r := await _stats_job(int(p[0]), int(p[1]))
		if not bool(r.done):
			misses += 1
			# Zweimal keine Antwort: Steam kennt die Abfrage hier nicht – nicht alle abwarten.
			if misses >= 2 and (out.results as Dictionary).is_empty():
				break
			continue
		out.results["%d:%d" % [int(p[0]), int(p[1])]] = r.body


## Eine Frage ClientGetUserStats: Antwort über die Auftragsnummer oder die App-ID (siehe _handle). Immer nur eine zur
## Zeit; die Frage selbst läuft in _stats_frage, damit die Marke auch nach einem Abbruch gelöst wird (sonst warteten
## alle späteren oben für immer).
func _stats_job(appid: int, steamid: int) -> Dictionary:
	while _stats_busy:
		await get_tree().process_frame
	_stats_busy = true
	var r := await _stats_frage(appid, steamid)
	_stats_busy = false
	return r if r.has("done") else { "done": false, "body": PackedByteArray() }


func _stats_frage(appid: int, steamid: int) -> Dictionary:
	_idle = 0.0
	var id := _job_next
	_job_next += 1
	_jobs[id] = { "done": false, "eresult": 2, "error": "", "body": PackedByteArray() }
	_stats_wait[appid] = id
	var h := _header()
	h.append_array(Pb.f_fixed64(10, id))
	_send(EMSG_GET_USER_STATS, h, user_stats_request(appid, steamid))
	var until := Time.get_ticks_msec() + 10000
	while not bool(_jobs[id].done) and Time.get_ticks_msec() < until and state == "angemeldet":
		await get_tree().process_frame
	var j: Dictionary = _jobs[id]
	_jobs.erase(id)
	_stats_wait.erase(appid)
	return { "done": bool(j.done), "body": j.body }


## Stand deiner Erfolge je Spiel (Player.GetAchievementsProgress#1, wie die Bibliothek der Steam-App)
## in Gruppen zu 50, alles in einer Sitzung. { ok, eresult, counts: { App-ID: { u, t } } }
func achievements_progress(refresh_token: String, steamid: int, appids: Array, lang := "german") -> Dictionary:
	var out := { "ok": false, "eresult": 0, "counts": {} }
	if appids.is_empty():
		out.ok = true
		return out
	var gate := _session_gate(PROGRESS)
	if not bool(gate.ok):
		return out
	_holds += 1
	var why := await logon(refresh_token)
	if why == "":
		await _progress_fragen(steamid, appids, lang, out)
	_holds -= 1
	out.ok = not (out.counts as Dictionary).is_empty()
	if not bool(out.ok) and int(out.eresult) == 0:
		_rare_failed(PROGRESS, bool(gate.brief))
	if bool(gate.brief):
		close_when_idle()
	return out


## Die Fragen von achievements_progress (eigene Funktion, siehe user_stats).
func _progress_fragen(steamid: int, appids: Array, lang: String, out: Dictionary) -> void:
	for i in range(0, mini(appids.size(), 2000), 50):
		var r := await _call(EMSG_SERVICE_CALL, PROGRESS, progress_request(steamid, appids.slice(i, i + 50), lang))
		out.eresult = int(r.eresult)
		if not bool(r.ok):
			break
		(out.counts as Dictionary).merge(parse_progress(r.body), true)


## CMsgClientGetUserStats: game_id (1, fixed64), crc_stats (2), schema_local_version (3; -1: kein
## Schema da, bitte mitschicken), steam_id_for_user (4, fixed64; du oder ein Freund).
static func user_stats_request(appid: int, steamid: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(Pb.f_fixed64(1, appid))
	b.append_array(Pb.f_varint(2, 0))
	b.append_array(Pb.f_varint(3, -1))
	b.append_array(Pb.f_fixed64(4, steamid))
	return b


## CPlayer_GetAchievementsProgress_Request: steamid (1), language (2), appids (3, je Spiel ein Eintrag).
static func progress_request(steamid: int, appids: Array, lang: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(Pb.f_varint(1, steamid))
	b.append_array(Pb.f_string(2, lang))
	for a in appids:
		if int(a) > 0:
			b.append_array(Pb.f_varint(3, int(a)))
	return b


## CPlayer_GetAchievementsProgress_Response: achievement_progress (1) = { appid (1), unlocked (2),
## total (3), percentage (4, float), all_unlocked (5) } → { App-ID: { u, t } } (wie die Web-API).
static func parse_progress(body: PackedByteArray) -> Dictionary:
	var out := {}
	for raw in Pb.decode(body).get(1, []):
		if not (raw is PackedByteArray):
			continue
		var e := Pb.decode(raw)
		var appid := Pb.zahl(e, 1, 0)
		if appid <= 0 or appid >= (1 << 24):
			continue
		var t := clampi(Pb.zahl(e, 3, 0), 0, 10000)
		var u := clampi(Pb.zahl(e, 2, 0), 0, t)
		if Pb.zahl(e, 5, 0) != 0 and t > 0:
			u = t
		out[appid] = { "u": u, "t": t }
	return out


# --- Freunde und Profile ohne Web-API ---------------------------------------------------------

## Name, Bild, Status und Spiel von Konten über Steams Chat-Server (Player.GetPlayerLinkDetails#1,
## dieselbe Abfrage wie Steams eigene Profil-Vorschau). Die Web-API lehnt den Zugang aus der
## QR-Anmeldung als Steam-App ab (im Protokoll des Nutzers: GetPlayerSummaries HTTP 400) – dann
## kamen weder Freunde noch Profile, obwohl die Sitzung die 77 Freunde schon kannte.
## Anders als ClientPersonaState hängt die Antwort nicht am eigenen Status der Sitzung: Sie gilt
## auch in der kurzen Sitzung neben Steam am PC, die keinen Status meldet (siehe sees_presence).
## with_friends: dazu alle Freunde laut ClientFriendsList (kommt gleich nach der Anmeldung).
## { ok, eresult, error, accounts: parse_link_details, friends: Anzahl laut Liste }
func player_details(refresh_token: String, ids: Array, with_friends := false, user := false) -> Dictionary:
	var gate := _session_gate(LINK_DETAILS, user)
	if not bool(gate.ok):
		return { "ok": false, "eresult": 0, "error": "Steam am PC ist angemeldet", "accounts": [], "friends": friend_ids.size() }
	_holds += 1
	var r := await _player_details(refresh_token, ids, with_friends)
	_holds -= 1
	if not bool(r.ok) and int(r.eresult) == 0:
		_rare_failed(LINK_DETAILS, bool(gate.brief))
	if bool(gate.brief):
		close_when_idle()
	return r


func _player_details(refresh_token: String, ids: Array, with_friends: bool) -> Dictionary:
	var why := await logon(refresh_token)
	if why != "":
		return { "ok": false, "eresult": 0, "error": why, "accounts": [], "friends": friend_ids.size() }
	if with_friends:
		# Die Liste schickt Steam von selbst nach der Anmeldung; kurz darauf warten.
		var until := Time.get_ticks_msec() + 3000
		while not _list_seen and state == "angemeldet" and Time.get_ticks_msec() < until:
			await get_tree().process_frame
	var want: Array = []
	for raw in (friend_ids.keys() if with_friends else []) + ids:
		var id := str(raw)
		if id.is_valid_int() and int(id) > STEAM64 and not want.has(id):
			want.append(id)
	var accounts: Array = []
	var res := 1
	var err := ""
	for i in range(0, want.size(), 100):
		var r := await _call(EMSG_SERVICE_CALL, LINK_DETAILS, link_request(want.slice(i, i + 100)))
		if not bool(r.ok):
			res = int(r.eresult)
			err = str(r.error)
			continue
		accounts.append_array(parse_link_details(r.body))
	var me := str(SteamChat.jwt_claims(refresh_token).get("sub", ""))
	for a in accounts:
		if str(a.id) == me and bool(a.has_private):
			note_own(a)
	return { "ok": not accounts.is_empty() or (res == 1 and want.is_empty()), "eresult": res, "error": err, "accounts": accounts,
		"friends": friend_ids.size() }


## CPlayer_GetPlayerLinkDetails_Request: steamids (1, je Konto ein Eintrag).
static func link_request(ids: Array) -> PackedByteArray:
	var b := PackedByteArray()
	for id in ids:
		if str(id).is_valid_int() and int(str(id)) > STEAM64:
			b.append_array(Pb.f_varint(1, int(str(id))))
	return b


## CPlayer_GetPlayerLinkDetails_Response: accounts (1) = { public_data (1) = { steamid (1, fixed64),
## visibility_state (2), sha_digest_avatar (9), persona_name (10) }, private_data (2) =
## { persona_state (1), time_created (3), game_id (4, fixed64), game_server_ip_address (6),
## game_server_port (7), game_extra_info (8), lobby_steam_id (10, fixed64), last_logoff_time (17) } }.
## private_data gibt es nur für Freunde und dich. Fremde Daten: Steam-ID geprüft, Texte gekürzt.
## [{ id, name, avatar, visibility, has_private, state, game_id, game, server, lobby, last, created }]
static func parse_link_details(body: PackedByteArray) -> Array:
	var out: Array = []
	for raw in Pb.decode(body).get(1, []):
		if not (raw is PackedByteArray):
			continue
		var acc := Pb.decode(raw)
		var pub_raw: Variant = Pb.first(acc, 1, null)
		if not (pub_raw is PackedByteArray):
			continue
		var pub := Pb.decode(pub_raw)
		var id := Pb.zahl(pub, 1, 0)
		if id <= STEAM64 or id >= STEAM64 + (1 << 32):
			continue
		var e := { "id": str(id), "name": Pb.text(pub, 10).left(128), "visibility": Pb.zahl(pub, 2, 0),
			"avatar": avatar_url(Pb.first(pub, 9, PackedByteArray())), "has_private": false, "state": 0, "game_id": "",
			"game": "", "server": "", "lobby": "", "last": 0, "created": 0 }
		var priv_raw: Variant = Pb.first(acc, 2, null)
		if priv_raw is PackedByteArray:
			var pr := Pb.decode(priv_raw)
			e["has_private"] = true
			e["state"] = clampi(Pb.zahl(pr, 1, 0), 0, 7)
			var gid := Pb.zahl(pr, 4, 0)
			# Steam-Spiel: die App-ID steht in den unteren 24 Bit (Typ 0); sonst Verknüpfung o. ä.
			e["game_id"] = str(gid) if gid > 0 and gid < (1 << 24) else (InstallParse.u64_text(gid) if gid != 0 else "")
			e["game"] = Pb.text(pr, 8).left(128)
			var ip := Pb.zahl(pr, 6, 0)
			e["server"] = "%d.%d.%d.%d:%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255, Pb.zahl(pr, 7, 0)] if ip != 0 else ""
			var lobby := Pb.zahl(pr, 10, 0)
			e["lobby"] = InstallParse.u64_text(lobby) if lobby != 0 else ""
			e["last"] = Pb.zahl(pr, 17, 0)
			e["created"] = Pb.zahl(pr, 3, 0)
		out.append(e)
	return out


# --- Wie Freunde dich sehen --------------------------------------------------------------------

## Deine Steam-ID aus der laufenden Anmeldung ("" ohne).
func my_sid() -> String:
	return str(SteamChat.jwt_claims(_logged_for).get("sub", "")) if _logged_for != "" else ""


## Eigene Angaben aus parse_link_details übernehmen (Status, Spiel, Name, Bild) – eine Zeile im
## Protokoll, wenn sich ändert, was Freunde sehen.
func note_own(a: Dictionary) -> void:
	var spiel := str(a.get("game", ""))
	var spiel_id := str(a.get("game_id", ""))
	if spiel == "" and spiel_id != "":
		# Steam-Spiele kommen nur als Nummer: der Name aus deiner Bibliothek (sonst bleibt die Nummer).
		var g := Library.get_game("steam:" + spiel_id)
		spiel = Library.display_title(g) if not g.is_empty() else ""
	own = { "at": int(Time.get_unix_time_from_system()), "state": int(a.get("state", 0)), "game": spiel,
		"game_id": str(a.get("game_id", "")), "name": str(a.get("name", "")), "avatar": str(a.get("avatar", "")) }
	var line := own_text(int(own.state), str(own.game), str(own.game_id))
	if line != _own_logged:
		_own_logged = line
		_log("Freunde sehen dich: " + line)
	own_changed.emit()


## Protokoll-Text für deinen Status laut Steam (rein, getestet).
static func own_text(st: int, game: String, game_id: String) -> String:
	var names := { 0: "offline", 1: "online", 2: "beschäftigt", 3: "abwesend", 4: "abwesend (Schlummern)", 5: "online", 6: "online", 7: "unsichtbar" }
	var t := str(names.get(st, "Status %d" % st))
	if st == 0 or game_id == "":
		return t + (" (Steam zeigt kein Spiel)" if st == 0 else ", kein Spiel")
	var steam_app := game_id.is_valid_int() and game_id.length() < 9
	return t + ", spielt „%s“%s" % [game if game != "" else game_id, " (Steam-Spiel)" if steam_app else " (Nicht-Steam-Spiel)"]


## Dein Status und Spiel bei Steam (Player.GetPlayerLinkDetails#1 für dich) – nur über eine schon
## stehende Sitzung, nie eine eigene dafür. So weiß Uzai, was Freunde wirklich sehen, auch wenn die
## Web-API den Zugang ablehnt (HTTP 400) und die Sitzung keinen eigenen Status hat.
func refresh_own() -> void:
	if _own_busy:
		while _own_busy:
			await get_tree().process_frame
		return
	var me := my_sid()
	if state != "angemeldet" or me == "":
		return
	_own_busy = true
	_holds += 1
	var r := await _call(EMSG_SERVICE_CALL, LINK_DETAILS, link_request([me]))
	_holds -= 1
	_own_busy = false
	if not bool(r.ok):
		return
	for a in parse_link_details(r.body):
		if str(a.id) == me and bool(a.has_private):
			note_own(a)
			if persona_state < 0:
				set_persona(int(a.state))


## Nach einer Spielmeldung: kurz warten (Steam braucht einen Moment) und nachsehen, ob Freunde das
## Spiel sehen. Steht im Protokoll als „Freunde sehen dich: …“.
func _confirm_own() -> void:
	var sent_at := games_at
	await get_tree().create_timer(4.0).timeout
	if sent_at == games_at and _games_sent != "":
		refresh_own()


# --- Dienstaufrufe ----------------------------------------------------------------------------

## Aufruf ohne Anmeldung (QR-Anmeldung, Zugang erneuern). { ok, eresult, error, body }
func call_nonauthed(method: String, body: PackedByteArray) -> Dictionary:
	if not await _connect():
		return { "ok": false, "eresult": 0, "error": last_error, "body": PackedByteArray() }
	return await _call(EMSG_NONAUTHED, method, body)


## Calls made as the signed-in user (e.g. FriendMessages.SendMessage#1).
## Actions the user triggers (sending a message, opening a chat) may briefly open a session even
## while Steam is running on the PC. Automatic ones (owned games, unread messages …) may not: every
## extra session made Steam on the PC show all friends as offline.
## Also „Installieren“ via Uzai (Installs: Steam's remote download, ClientComm), only when no web
## access is available; Uzai then reads the progress from Steam's files, without a session.
const USER_METHODS := ["FriendMessages.SendMessage#1", "FriendMessages.GetRecentMessages#1",
	"ClientComm.GetAllClientLogonInfo#1", "ClientComm.InstallClientApp#1", "ClientComm.SetClientAppUpdateState#1",
	"ClientComm.UninstallClientApp#1"]


## Rarely needed, but without them nothing loads (for example after a fresh install with a QR sign-in):
## the web access for friends, achievements and playtime (valid for about a day) and the owned games.
## For these Uzai may briefly open a session even next to Steam on the PC, at most once every
## RARE_GAP_S seconds per method; it closes again right away (close_when_idle).
## Also friends with status and game (Player.GetPlayerLinkDetails#1, only when the web API refuses
## access): every FRIENDS_GAP_S seconds, otherwise the list stayed empty next to Steam on the PC.
## Also the achievements when the web API refuses access (steam_erfolge.gd): per-game state for the
## count (PROGRESS) and lists (USER_STATS); only rarely when automatic, on a button press when opened.
const LINK_DETAILS := "Player.GetPlayerLinkDetails#1"
const PROGRESS := "Player.GetAchievementsProgress#1"
const USER_STATS := "ClientGetUserStats"
const ITEMS := "Player.GetProfileItemsEquipped#1"
const RARE_METHODS := ["Authentication.GenerateAccessTokenForApp#1", "Player.GetOwnedGames#1", LINK_DETAILS, PROGRESS, USER_STATS, ITEMS]
const RARE_GAP_S := 600
const FRIENDS_GAP_S := 300
var _rare_at := {}                  ## Methode -> Unix-Zeit der letzten eigenen Sitzung dafür


## Neue Anmeldung (QR): Die Sperrzeit gilt der alten; gleich wieder laden dürfen.
func reset_rare() -> void:
	_rare_at.clear()


## Mindestabstand der kurzen Sitzungen je Methode (Sekunden).
static func rare_gap(method: String) -> int:
	return FRIENDS_GAP_S if method == LINK_DETAILS else RARE_GAP_S


## Darf method neben Steam am PC eine eigene Sitzung öffnen? (rein, getestet) user = true: auf
## Knopfdruck (Profil geöffnet, Nachricht gesendet) – wie die USER_METHODS immer.
static func session_allowed(method: String, last_at: int, now_s: int, user := false) -> bool:
	if user or method in USER_METHODS:
		return true
	return method in RARE_METHODS and (last_at <= 0 or now_s - last_at >= rare_gap(method))


## Ginge method jetzt (Sitzung steht, Steam am PC aus oder die Pause ist um)? Ohne Nebenwirkung.
func may_open(method: String) -> bool:
	return state == "angemeldet" or not pc_maybe() or session_allowed(method, int(_rare_at.get(method, 0)), int(Time.get_unix_time_from_system()))


## Vor einer Abfrage ohne bestehende Sitzung: darf sie neben Steam am PC eine öffnen?
## { ok, brief } – brief: nach der Abfrage gleich wieder schließen.
func _session_gate(method: String, user := false) -> Dictionary:
	if state == "angemeldet" or not pc_maybe():
		if state != "angemeldet":
			_log("Sitzung für %s" % method)
		return { "ok": true, "brief": false }
	var now_s := int(Time.get_unix_time_from_system())
	if not session_allowed(method, int(_rare_at.get(method, 0)), now_s, user):
		# Nur einmal je Methode ins Protokoll (sonst bei jeder Abfrage dieselbe Zeile).
		if not _skip_logged.has(method):
			_skip_logged[method] = true
			_log("Steam am PC angemeldet – %s ohne eigene Sitzung übersprungen" % method)
		return { "ok": false, "brief": false }
	_skip_logged.erase(method)
	var brief := method in RARE_METHODS and not user
	if brief:
		_rare_at[method] = now_s
	_log("Steam am PC angemeldet – kurze eigene Sitzung für %s%s" % [method, "" if brief else " (auf Knopfdruck)"])
	_log("Sitzung für %s" % method)
	return { "ok": true, "brief": brief }


func call_authed(refresh_token: String, method: String, body: PackedByteArray, user := false) -> Dictionary:
	var gate := _session_gate(method, user)
	if not bool(gate.ok):
		return { "ok": false, "eresult": 0, "error": "Steam am PC ist angemeldet", "body": PackedByteArray() }
	_holds += 1
	var why := await logon(refresh_token)
	var res := { "ok": false, "eresult": 0, "error": why, "body": PackedByteArray() }
	if why == "":
		res = await _call(EMSG_SERVICE_CALL, method, body)
	_holds -= 1
	if not bool(res.ok) and int(res.eresult) == 0:
		_rare_failed(method, bool(gate.brief))
	if bool(gate.brief):
		close_when_idle()
	return res


## Eine kurze Sitzung kam nicht zustande oder Steam antwortete nicht: Die Sperrzeit gilt dann nicht
## (sonst stand die Freundesliste nach einem Aussetzer gleich nach der QR-Anmeldung 5 Min. leer).
## In RARE_RETRY_S Sekunden darf es noch einmal.
func _rare_failed(method: String, brief: bool) -> void:
	# Zugang abgelehnt (5, 15): ein neuer Versuch hilft nicht.
	if not brief or not _rare_at.has(method) or _logon_result in [5, 15]:
		return
	_rare_at[method] = int(Time.get_unix_time_from_system()) - rare_gap(method) + RARE_RETRY_S
	_log("%s ohne Antwort – neuer Versuch frühestens in %d s" % [method, RARE_RETRY_S])


## Benachrichtigung an Steam ohne Antwort (z. B. FriendMessages.AckMessage#1): nur, wenn die
## Anmeldung schon steht – kein Warten auf eine Antwort, die nie kommt.
func notify_authed(method: String, body: PackedByteArray) -> void:
	if state != "angemeldet":
		return
	_idle = 0.0
	var h := _header()
	h.append_array(Pb.f_string(12, method))
	_send(EMSG_SERVICE_CALL, h, body)


func _call(emsg: int, method: String, body: PackedByteArray) -> Dictionary:
	_idle = 0.0
	var id := _job_next
	_job_next += 1
	_jobs[id] = { "done": false, "eresult": 2, "error": "", "body": PackedByteArray() }
	var h := PackedByteArray()
	if emsg == EMSG_NONAUTHED:
		h = _header(0, 0)
	else:
		h = _header()
	h.append_array(Pb.f_fixed64(10, id))
	h.append_array(Pb.f_string(12, method))
	h.append_array(Pb.f_varint(32, 1))
	_send(emsg, h, body)
	var until := Time.get_ticks_msec() + 12000
	while not bool(_jobs[id].done) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	var j: Dictionary = _jobs[id]
	_jobs.erase(id)
	if not bool(j.done):
		_log("%s: keine Antwort" % method)
		return { "ok": false, "eresult": 0, "error": "Steam hat nicht geantwortet.", "body": PackedByteArray() }
	var res := int(j.eresult)
	if res != 1:
		_log("%s: EResult %d %s" % [method, res, str(j.error)])
	return { "ok": res == 1, "eresult": res, "error": str(j.error), "body": j.body }


func _header(steamid := -1, session := -1) -> PackedByteArray:
	var h := PackedByteArray()
	h.append_array(Pb.f_fixed64(1, _steamid if steamid < 0 else steamid))
	h.append_array(Pb.f_varint(2, _session if session < 0 else session))
	return h


func _send(emsg: int, header: PackedByteArray, body: PackedByteArray) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, (emsg | PROTO_MASK) & 0xFFFFFFFF)
	out.encode_u32(4, header.size())
	out.append_array(header)
	out.append_array(body)
	_ws.send(out, WebSocketPeer.WRITE_MODE_BINARY)


## So viel darf eine gepackte Sammelnachricht entpackt höchstens ergeben (ohne Grenze füllte eine kleine Nachricht den
## ganzen Speicher), und so tief dürfen Sammelnachrichten ineinander stecken.
const MULTI_MAX := 64 * 1024 * 1024
const MULTI_TIEFE := 2


func _handle(msg: PackedByteArray, tiefe := 0) -> void:
	if msg.size() < 8:
		return
	var raw := int(msg.decode_u32(0))
	if (raw & PROTO_MASK) == 0:
		return
	var emsg := raw & ~PROTO_MASK & 0xFFFFFFFF
	var hlen := int(msg.decode_u32(4))
	if 8 + hlen > msg.size():
		return
	var head := Pb.decode(msg.slice(8, 8 + hlen))
	var body := msg.slice(8 + hlen)
	var sess := Pb.zahl(head, 2, 0)
	if sess != 0:
		_session = sess
	if emsg == EMSG_MULTI:
		if tiefe < MULTI_TIEFE:
			_multi(body, tiefe + 1)
		return
	var target := Pb.zahl(head, 11, -1)
	if target != -1 and _jobs.has(target):
		var j: Dictionary = _jobs[target]
		j["done"] = true
		j["eresult"] = Pb.zahl(head, 13, 2)
		var em: Variant = Pb.first(head, 14, PackedByteArray())
		j["error"] = (em as PackedByteArray).get_string_from_utf8() if em is PackedByteArray else ""
		j["body"] = body
		return
	if emsg == EMSG_GET_USER_STATS_RESPONSE:
		# Ohne Auftragsnummer in der Antwort: über die App-ID zuordnen (je App nur eine Frage zur Zeit).
		var gid := Pb.zahl(Pb.decode(body), 1, 0) & 0xFFFFFF
		var jid := int(_stats_wait.get(gid, -1))
		if _jobs.has(jid):
			var js: Dictionary = _jobs[jid]
			js["done"] = true
			js["body"] = body
		return
	if emsg == EMSG_SERVICE_METHOD or emsg == EMSG_SERVICE_TO_CLIENT:
		var method := Pb.text(head, 12)
		if method != "":
			notice.emit(method, body)
		return
	match emsg:
		EMSG_LOGON_RESPONSE:
			var b := Pb.decode(body)
			_logon_result = Pb.zahl(b, 1, 2)
			if _logon_result == 1:
				_steamid = Pb.zahl(head, 1, 0)
				_hb_every = clampf(float(Pb.zahl(b, 3, 9)), 10.0, 120.0)
				_hb = 0.0
				state = "angemeldet"
				# Gleich hier merken, für welchen Zugang: Wer im selben Bild dazukommt, nutzt die Sitzung.
				_logged_for = _logon_token
				_log("Angemeldet bei Steam (Herzschlag alle %d s)" % int(_hb_every))
		EMSG_PLAYING_STATE:
			# Spielt das Konto anderswo (Steam am PC), nichts melden – sonst würde Steam dort
			# das Spiel beenden. Ist es frei, den Namen (falls gewünscht) wieder melden.
			# CMsgClientPlayingSessionState: playing_blocked (2), playing_app (3). Läuft die
			# Steam-App am PC nur (ohne Spiel), ist nichts blockiert.
			var b3 := Pb.decode(body)
			var was := playing_blocked
			playing_blocked = Pb.zahl(b3, 2, 0) != 0
			playing_app = Pb.zahl(b3, 3, 0) if playing_blocked else 0
			if playing_blocked != was:
				_log("Steam am PC spielt %s" % (("gerade (App %d) – Uzai meldet nichts" % playing_app) if playing_blocked else "nichts mehr"))
			if playing_blocked:
				_games_sent = ""
			_send_games()
		EMSG_PERSONA_STATE:
			var list := parse_persona_state(body)
			# Eigenen Status protokollieren (Fehlersuche „Steam am PC geht offline“).
			var me := str(SteamChat.jwt_claims(_logged_for).get("sub", ""))
			for p in list:
				if me != "" and str(p.get("id", "")) == me and p.has("state") and int(p.state) != _own_state_logged:
					_own_state_logged = int(p.state)
					_log("Eigener Status bei Steam jetzt: %d (0 offline, 1 online, 3 abwesend, 7 unsichtbar)" % _own_state_logged)
			# Ohne eigenen Status zählen nur Name, Bild und „zuletzt online“ (siehe sees_presence).
			var trusted := sees_presence()
			if not trusted:
				list = without_status(list)
			if not list.is_empty():
				if trusted:
					persona_at = Time.get_ticks_msec()
				persona_count += 1
				persona.emit(list)
		EMSG_FRIENDS_LIST:
			var fl := parse_friends_list(body)
			if not bool(fl.incremental):
				friend_ids.clear()
			for id in fl.add:
				friend_ids[id] = true
			for id in fl.remove:
				friend_ids.erase(id)
			if not bool(fl.incremental):
				_list_seen = true
				_log("Freundesliste von Steam: %d Freunde, %d Anfragen" % [friend_ids.size(), (fl.requests as Dictionary).size()])
			friends_list.emit(fl.add, bool(fl.incremental))
			if apply_requests(requests, fl):
				requests_changed.emit()
			# Wie die Steam-App: zu den Freunden gleich Status, Namen und Spiel abfragen.
			request_friend_data(fl.add)
		EMSG_LOGGED_OFF:
			var b2 := Pb.decode(body)
			var why_off := Pb.zahl(b2, 1, 0)
			_log("Steam hat abgemeldet (EResult %d)" % why_off)
			# 6 = anderswo angemeldet/gespielt: den Spielnamen nicht erneut durchsetzen.
			if why_off == 6:
				games_name = ""
			_logged_for = ""
			_games_sent = ""
			state = "offen"
			_set_live(false)
			# Dauerverbindung: sauber neu verbinden (nach der Pause), nicht mitten im Lesen.
			if keep != "":
				close.call_deferred()


func _multi(body: PackedByteArray, tiefe := 1) -> void:
	var m := Pb.decode(body)
	var payload: Variant = Pb.first(m, 2, PackedByteArray())
	if not (payload is PackedByteArray):
		return
	var data: PackedByteArray = payload
	if Pb.zahl(m, 1, 0) > 0:
		data = data.decompress_dynamic(MULTI_MAX, FileAccess.COMPRESSION_GZIP)
	var pos := 0
	while pos + 4 <= data.size():
		var n := int(data.decode_u32(pos))
		if pos + 4 + n > data.size():
			break
		_handle(data.slice(pos + 4, pos + 4 + n), tiefe)
		pos += 4 + n


# --- Hilfen -------------------------------------------------------------------------------------


func log_line(text: String) -> void:
	_log(text)


func _log(text: String) -> void:
	Logdatei.zeile(Config.path("logs/steam.log"), "CM: %s" % text, 300000)


## Kleiner protobuf-Baukasten: Felder schreiben und eine Nachricht in { Feld: [Werte] } lesen.
class Pb:
	static func varint(v: int) -> PackedByteArray:
		var out := PackedByteArray()
		var x := v
		for i in 10:
			var b := x & 0x7F
			x = (x >> 7) & 0x01FFFFFFFFFFFFFF
			if x == 0:
				out.append(b)
				return out
			out.append(b | 0x80)
		return out

	static func key(field: int, wire: int) -> PackedByteArray:
		return varint((field << 3) | wire)

	static func f_varint(field: int, v: int) -> PackedByteArray:
		var out := key(field, 0)
		out.append_array(varint(v))
		return out

	static func f_fixed64(field: int, v: int) -> PackedByteArray:
		var out := key(field, 1)
		var b := PackedByteArray()
		b.resize(8)
		b.encode_s64(0, v)
		out.append_array(b)
		return out

	static func f_fixed32(field: int, v: int) -> PackedByteArray:
		var out := key(field, 5)
		var b := PackedByteArray()
		b.resize(4)
		b.encode_u32(0, v & 0xFFFFFFFF)
		out.append_array(b)
		return out

	static func f_bytes(field: int, v: PackedByteArray) -> PackedByteArray:
		var out := key(field, 2)
		out.append_array(varint(v.size()))
		out.append_array(v)
		return out

	static func f_string(field: int, s: String) -> PackedByteArray:
		return f_bytes(field, s.to_utf8_buffer())

	static func f_msg(field: int, inner: PackedByteArray) -> PackedByteArray:
		return f_bytes(field, inner)

	## { Feldnummer: [Werte] } – Zahlen als int, Längenfelder als PackedByteArray,
	## 32-Bit-Felder als int (Gleitkomma: decode_float auf die Bytes).
	static func decode(data: PackedByteArray) -> Dictionary:
		var out := {}
		var pos := 0
		var n := data.size()
		while pos < n:
			var r := _read_varint(data, pos)
			if r[1] < 0:
				break
			var k: int = r[0]
			pos = r[1]
			var field := k >> 3
			var wire := k & 7
			var val: Variant = null
			match wire:
				0:
					var v := _read_varint(data, pos)
					if v[1] < 0:
						return out
					val = v[0]
					pos = v[1]
				1:
					if pos + 8 > n:
						return out
					val = data.decode_s64(pos)
					pos += 8
				2:
					var l := _read_varint(data, pos)
					if l[1] < 0 or l[1] + int(l[0]) > n:
						return out
					val = data.slice(l[1], l[1] + int(l[0]))
					pos = l[1] + int(l[0])
				5:
					if pos + 4 > n:
						return out
					val = int(data.decode_u32(pos))
					pos += 4
				_:
					return out
			if not out.has(field):
				out[field] = []
			(out[field] as Array).append(val)
		return out

	static func _read_varint(data: PackedByteArray, pos: int) -> Array:
		var v := 0
		var shift := 0
		while pos < data.size() and shift < 70:
			var b := data[pos]
			pos += 1
			v |= (b & 0x7F) << shift
			if (b & 0x80) == 0:
				return [v, pos]
			shift += 7
		return [0, -1]

	static func first(d: Dictionary, field: int, def: Variant) -> Variant:
		var a: Variant = d.get(field)
		return (a as Array)[0] if a is Array and not (a as Array).is_empty() else def

	## Erste Zahl eines Felds. Fehlt das Feld oder kommt es in anderer Art (als Bytes statt als Zahl), der Ersatzwert:
	## int() auf Bytes bricht die ganze Funktion ab (gemessen), und eine Nachricht bliebe ungelesen liegen.
	static func zahl(d: Dictionary, field: int, def := 0) -> int:
		var v: Variant = first(d, field, def)
		return v if v is int else def

	## Text eines Felds (Namen, Nachrichten, Spieltitel – alles von Fremden geschrieben): ohne Steuerzeichen und ohne
	## umgedrehte Schreibrichtung (Fremd.sauber).
	static func text(d: Dictionary, field: int) -> String:
		var v: Variant = first(d, field, PackedByteArray())
		return Fremd.sauber((v as PackedByteArray).get_string_from_utf8()) if v is PackedByteArray else ""

extends Node
## Steam-Chat direkt über die Steam-Schnittstelle (dieselbe, die der Steam-Webchat benutzt):
## kompletter Verlauf mit einem Freund, neue Nachrichten, senden – ohne dass Steam nach vorn
## kommt. Dafür meldest du dich einmal an: QR-Code mit der Steam-App auf dem Handy scannen und
## bestätigen. Uzai bekommt so einen Zugang für dein Konto (kein Passwort) und erneuert ihn selbst.

signal changed                  ## Anmeldung oder ungelesene Nachrichten haben sich geändert
signal messages(friend_id: String)
signal typing_changed(friend_id: String, on: bool)   ## der Freund schreibt gerade (nur wo bekannt)
## Neue Nachricht eines Freundes (sofort über die Dauerverbindung oder aus der Abfrage):
## { friend, kind, text, at, ordinal, echo, from_poll } – Notify entscheidet über das Pop-up.
signal incoming(msg: Dictionary)

const Logdatei := preload("res://src/core/logdatei.gd")
const RemotePlay := preload("res://src/core/remote_play.gd")
const SteamAmPc := preload("res://src/core/steam_am_pc.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Fremd := preload("res://src/core/fremd.gd")
const Sicher := preload("res://src/core/sicher.gd")
const API := "https://api.steampowered.com/"
const STEAM64 := 76561197960265728
const TYPING_SECS := 8.0        ## so lange gilt „schreibt gerade“ ohne neues Zeichen von Steam
const CHAT_POLL := 4.0          ## offener Chat: so oft nach neuen Nachrichten sehen (Sekunden)
const CHAT_POLL_PC := 20.0      ## … wenn das eine eigene Sitzung neben Steam am PC bräuchte
const DEMO_REPLIES := ["Bin dabei!", "Perfekt, bis gleich", "Haha, ja", "Klingt gut", "Gib mir fünf Minuten"]

var unread := {}                ## Steam-ID des Freundes -> Anzahl ungelesen
var typing := {}                ## Steam-ID des Freundes -> true, solange er schreibt
var error := ""
var demo := false
var _access := ""
var _access_exp := 0
var _finalize_denied := false   ## Steam hat die gespeicherte Anmeldung ausdrücklich abgelehnt
var _demo_chats := {}
var _demo_n := 0
var _demo_busy := {}
var _typing_sent := {}
var _demo_read := false
var _poll: Timer
## Steam-ID des gerade offenen Chats (chat_view setzt das). Stand „chat.steam“ für Zustand.lage() und den
## Fehlerbericht: zu · offen · zu_sehen bzw. verdeckt (so stand es bei der letzten Nachricht, siehe chat_in_view).
var open_chat := "":
	set(neu):
		if neu != open_chat:
			Zustand.melden("chat.steam", "zu" if neu == "" else "offen")
		open_chat = neu
var open_view: WeakRef = null   ## dessen Ansicht (chat_view); zählt nur, solange sie zu sehen ist
var last_at := {}               ## Steam-ID -> Zeit (Unix) der letzten Nachricht des Freundes (Guide: Neue oben)
var _typing_at := {}            ## Steam-ID -> Zeit (ms) des letzten „schreibt“
## Die Web-API hat den Zugang aus der Anmeldung abgelehnt (HTTP 400/401/403): bis dahin (Unix)
## laufen Freunde, Profile und Verlauf über Steams Chat-Server. Beim Nutzer kam mit dem Zugang
## einer QR-Anmeldung als Steam-App HTTP 400 – und alles blieb leer, ohne Zeile im Protokoll.
var _web_bad_until := 0
const WEB_BAD_S := 6 * 3600
## Dasselbe nur für den Chat (Ungelesenes, Verlauf: IFriendMessagesService). Getrennt, weil Steam den Zugang je
## Schnittstelle verschieden behandelt: Beim Freund (Test 0.16.51) lehnte GetFriendList ihn ab (HTTP 400), Ungelesenes
## ging. Ein gemeinsamer Merker schaltete damit die Abfrage ab – neben Steam am PC kam dann keine Nachricht mehr an.
var _chat_web_bad_until := 0
## Welche Abrufe zum Chat gehören (note_web).
const CHAT_WEB := ["Ungelesen", "Verlauf"]
var _diag_last := {}            ## Art -> zuletzt protokollierter Schlüssel (keine doppelten Zeilen)


func _ready() -> void:
	demo = "--demo" in OS.get_cmdline_user_args()
	_poll = Timer.new()
	_poll.wait_time = 30.0
	_poll.timeout.connect(refresh_unread)
	add_child(_poll)
	SteamCM.notice.connect(_on_notice)
	SteamCM.live_changed.connect(func(_on: bool) -> void:
		_update_poll()
		_note_weg()
	)
	SteamCM.friends_list.connect(_on_cm_list)
	Config.changed.connect(func(k: String) -> void:
		# Auch wenn Steam den Zugang erneuert hat: die Dauerverbindung nimmt den neuen.
		if k == "notify.steam" or (k == "accounts.steam_chat_refresh" and SteamCM.keep != ""):
			update_live()
	)
	# Ob Steam am PC angemeldet ist (dann meldet Uzai keinen eigenen Status), gleich und jede Minute.
	var pc := Timer.new()
	pc.wait_time = 60.0
	pc.timeout.connect(_check_pc)
	add_child(pc)
	pc.start()
	_first_pc_check()
	if logged_in():
		_poll.start()
		update_live.call_deferred()
		# Für die Fehlersuche („muss mich jedes Mal neu anmelden“): Art und Ablauf der Anmeldung.
		var cl := jwt_claims(str(Config.get_value("accounts.steam_chat_refresh", "")))
		_log(
				"Start: angemeldet, Art %s, gültig bis %s, senden %s" % [str(cl.get("aud", [])), Time.get_datetime_string_from_unix_time(int(cl.get("exp", 0))), "ja"
				if can_send() else "nein"])
	elif not demo:
		_log("Start: nicht angemeldet")
		_note_weg()


# --- Echtzeit ------------------------------------------------------------------------------

## Mit einer Anmeldung als Steam-App hält Uzai die Verbindung zu Steams Chat-Servern offen und
## bekommt neue Nachrichten sofort. Sonst fragt Uzai öfter nach (alle 15 s statt 30 s).
func update_live() -> void:
	if live_wanted():
		SteamCM.keep_online(str(Config.get_value("accounts.steam_chat_refresh", "")))
		if SteamCM.persona_state < 0:
			_fetch_persona()
	else:
		SteamCM.stop_keep(keep_off_reason())
	_update_poll()
	_note_weg()


## Wie neue Nachrichten zu Uzai kommen – die Grundlage der Pop-ups (rein, getestet):
## "aus" (Einstellung), "keiner" (in Uzai nicht bei Steam angemeldet), "sofort" (eigene Verbindung),
## "abfrage" (alle 15 s über die Web-API bzw. eine eigene Sitzung), "selten" (Steam am PC angemeldet und die
## Web-API lehnt den Chat ab: nur, wenn Uzai ohnehin kurz bei Steam ist – eine eigene Sitzung nur für
## Ungelesenes ließe Steam am PC die Freunde offline zeigen, Fehler 36). Beim Freund (Test 0.16.51) stand
## „Alle 15 Sekunden“ in den Einstellungen, abgefragt wurde aber gar nicht.
static func nachrichten_weg(logged: bool, on: bool, is_live: bool, chat_web: bool, client: bool, pc: bool) -> String:
	if not on:
		return "aus"
	if not logged:
		return "keiner"
	if is_live:
		return "sofort"
	if chat_web or not client or not pc:
		return "abfrage"
	return "selten"


## Kurz für Einstellungen → Mitteilungen (unter „Steam-Nachrichten“).
const WEG_TEXT := { "keiner": "Nicht angemeldet – Konten → Steam", "aus": "", "sofort": "Kommen sofort", "abfrage": "Alle 15 Sekunden",
	"selten": "Verzögert – Steam am PC ist angemeldet" }
## Fürs Protokoll (steam.log), eine Zeile, wenn sich der Weg ändert.
const WEG_LOG := { "keiner": "keine – in Uzai nicht bei Steam angemeldet (Konten → Steam)", "aus": "aus (Einstellungen → Mitteilungen)",
	"sofort": "kommen sofort (eigene Verbindung)", "abfrage": "per Abfrage alle 15 s",
	"selten": "nur, wenn Uzai ohnehin kurz bei Steam ist (Steam am PC angemeldet, Web-API lehnt den Chat ab)" }


func weg() -> String:
	return nachrichten_weg(logged_in(), bool(Config.get_value("notify.steam", true)), live(), chat_web_ok(), can_send(), SteamCM.pc_maybe())


## Stand „steam.nachrichten“ (aus mehreren Schaltern, nur gemeldet: Fehlerbericht, Zustand.lage()) und eine Zeile
## in steam.log, wenn er sich ändert.
func _note_weg() -> void:
	var w := weg()
	Zustand.melden("steam.nachrichten", w)
	diag_log("weg", w, "Steam-Nachrichten als Pop-up: " + str(WEG_LOG.get(w, w)))


## Eine kurze Sitzung bei Steams Chat-Servern steht gerade (nach jeder Anmeldung kommt die Freundesliste):
## Neben Steam am PC gleich nach Ungelesenem fragen – ohne Web-API (weg() == "selten") ist das der einzige
## Weg, und eine eigene Sitzung nur dafür gibt es nicht.
func _on_cm_list(_ids: Array, incremental: bool) -> void:
	if not incremental and not demo and SteamCM.pc_maybe() and weg() in ["abfrage", "selten"]:
		refresh_unread()


## Warum Uzai keine Dauerverbindung hält (fürs Protokoll beim Schließen).
func keep_off_reason() -> String:
	if not logged_in():
		return "abgemeldet"
	if SteamCM.pc_maybe() and SteamCM.games_name == "":
		return "kein Nicht-Steam-Spiel, Steam am PC angemeldet"
	return "Steam-Mitteilungen aus"


## Beim Start: warten, bis der Helfer bereit ist (höchstens 10 s), dann nachsehen; erst danach
## meldet Uzai (falls Steam am PC nicht läuft) einen Status.
func _first_pc_check() -> void:
	var until := Time.get_ticks_msec() + 10000
	while not demo and Config.is_windows() and not Helper.available and Time.get_ticks_msec() < until:
		await get_tree().create_timer(0.5).timeout
	# Nur wenn der Helfer wirklich nachsehen konnte, gilt es als bekannt. Vorher galt es nach 10 s
	# auch ohne Antwort als „Steam am PC aus“ – lief der Helfer nicht, meldete Uzai dann doch einen
	# Status, und Steam am PC zeigte alle Freunde offline (so beim Nutzer, Helfer ging nicht).
	await _check_pc()
	# Erst jetzt entscheiden, ob Uzai eine eigene Sitzung offen hält (Steam am PC?).
	if logged_in():
		update_live()
	SteamCM.send_status_if_needed()


func _check_pc() -> void:
	if demo or not Config.is_windows() or not Helper.available or not logged_in():
		return
	var r := await Helper.run("steam-state", {}, 4.0)
	if not r.ok or not (r.result is Dictionary):
		return
	var on := bool(r.result.get("running", false)) and int(r.result.get("user", 0)) != 0
	SteamCM.pc_known = true
	if on != SteamCM.pc_signed_in:
		SteamCM.pc_signed_in = on
		_log("Steam am PC: %s" % ("angemeldet" if on else "nicht angemeldet"))
		update_live()
		if on:
			SteamCM.close_when_idle()
	await _note_pc_persona(on, int(r.result.get("user", 0)))


## Your status in Steam on the PC (read-only, from Steam's files): if the Steam app is signed in with your
## account, its status applies, so you are not shown as "offline" just because Uzai's own session reports
## no status. Writes one log line when it changes.
func _note_pc_persona(on: bool, active_user: int) -> void:
	var st := -1
	var src := ""
	var mine := SteamAmPc.STEAM64 + active_user
	if on and (my_id() == "" or str(mine) == my_id()):
		var p: Dictionary = await SteamAmPc.pc_persona(Library.steam_root(), my_id())
		st = int(p.state)
		src = str(p.src)
	elif on:
		src = "Steam am PC mit einem anderen Konto angemeldet"
	else:
		src = "Steam am PC nicht angemeldet"
	diag_log("eigen-pc", "%d|%s" % [st, src], "Eigener Status: %s (%s)" % [SteamAmPc.name_of(st) if st >= 0 else "unbekannt", src])
	if st != SteamCM.pc_persona:
		SteamCM.pc_persona = st
		SteamCM.pc_persona_src = src
		SteamCM.own_changed.emit()


## Läufe von _fetch_persona, die gerade unterwegs sind (siehe dort).
var _fetch_persona_offen := 0


## Steam liefert Nachrichten sofort nur an Sitzungen mit Status. Den kennt Uzai sonst aus der
## Freundesliste (Web-API-Schlüssel); fehlt der, holt Uzai den eigenen Status mit der Anmeldung.
func _fetch_persona() -> void:
	_fetch_persona_offen += 1
	await _fetch_persona_lauf()
	_fetch_persona_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _fetch_persona täte bis zum Neustart nichts mehr.
	if _fetch_persona_offen == 0 and _persona_busy:
		_persona_busy = false


func _fetch_persona_lauf() -> void:
	if my_id() == "" or _persona_busy:
		return
	_persona_busy = true
	await _fetch_persona_now()
	_persona_busy = false


var _persona_busy := false


func _fetch_persona_now() -> void:
	var st := -1
	var tok := ""
	if web_ok():
		tok = await _token()
	if tok != "":
		var r := await Net.get_json(API + "ISteamUser/GetPlayerSummaries/v2/?" + Net.query({ "access_token": tok, "steamids": my_id() }))
		var players := Fremd.zeilen(r.data, "response/players") if r.ok else []
		if not players.is_empty():
			st = Fremd.zahl(players[0].get("personastate"))
		else:
			note_web(int(r.code), "Eigener Status")
	if st < 0 and can_send():
		# Baut Uzai gerade die Dauerverbindung auf: auf sie warten und über sie fragen. Vorher fragte
		# Uzai daneben nach einer eigenen kurzen Sitzung – neben Steam am PC „übersprungen“, und der
		# eigene Status blieb unbekannt (Protokoll des Nutzers: „Chat-Server EResult 0“).
		var until := Time.get_ticks_msec() + 15000
		while SteamCM.keep != "" and SteamCM.state != "angemeldet" and Time.get_ticks_msec() < until:
			await get_tree().create_timer(0.25).timeout
		if SteamCM.state == "angemeldet":
			await SteamCM.refresh_own()
			if not SteamCM.own.is_empty() and int(Time.get_unix_time_from_system()) - int(SteamCM.own.at) < 60:
				st = int(SteamCM.own.state)
		if st < 0:
			# Wie Freunde und Profil: über Steams Chat-Server (Player.GetPlayerLinkDetails#1).
			var d: Dictionary = await SteamCM.player_details(str(Config.get_value("accounts.steam_chat_refresh", "")), [my_id()])
			for a in d.accounts:
				if str(a.id) == my_id() and bool(a.has_private):
					st = int(a.state)
			if st < 0:
				diag_log("eigen", "cm%d" % int(d.eresult),
						"CM: Eigener Status nicht abrufbar (Chat-Server EResult %d) – Pop-ups kommen per Abfrage alle 15 s" % int(d.eresult))
				return
	if st < 0:
		diag_log("eigen", "kein", "CM: Eigener Status nicht abrufbar (kein Zugang) – Pop-ups kommen per Abfrage alle 15 s")
		return
	diag_log("eigen", "st%d" % st,
			"CM: Eigener Status laut Steam: %d%s" % [st, " (offline/unsichtbar: keine Sofort-Nachrichten, Abfrage alle 15 s)" if st == 0 else ""])
	if SteamCM.persona_state < 0:
		SteamCM.set_persona(st)


## Auch ohne Steam-Pop-ups, solange Freunde „Spielt Nicht-Steam-Spiel: …“ sehen sollen.
## Ist Steam am PC angemeldet, hält Uzai keine eigene Sitzung offen (nur solange ein Nicht-Steam-
## Spiel läuft, für den Status): Schon eine zweite Sitzung ohne Statusmeldung ließ Steam am PC alle
## Freunde offline zeigen, bis Uzai zu war (Protokoll des Nutzers). Nachrichten zeigt dann Steam am PC.
func live_wanted() -> bool:
	if SteamCM.pc_maybe() and SteamCM.games_name == "":
		return false
	return not demo and logged_in() and can_send() and (bool(Config.get_value("notify.steam", true)) or SteamCM.games_name != "")


func live() -> bool:
	return SteamCM.live and SteamCM.status_set


## Sehen Steam-Freunde dein Emulator- oder PC-Spiel? Für Einstellungen → Steam und den Hinweis
## beim Start: { ok, short, text, login } – login: es fehlt die Steam-Anmeldung in Uzai.
func game_status() -> Dictionary:
	if not bool(Config.get_value("steam.status_nonsteam", true)):
		return { "ok": false, "short": "Aus", "text": "Freunde sehen bei Emulator- und PC-Spielen nichts.", "login": false }
	if not demo and not logged_in():
		return { "ok": false, "short": "Nicht aktiv", "login": true,
			"text": "Erst bei Steam anmelden (QR-Code oben)." }
	if not can_send():
		return { "ok": false, "short": "Nicht aktiv", "login": true,
			"text": "Deine Steam-Anmeldung darf nur lesen. Einmal neu per QR-Code anmelden („Senden freischalten“)." }
	if SteamCM.keep_error != "":
		return { "ok": false, "short": "Nicht aktiv", "login": true,
				"text": "Steam hat die Anmeldung abgelehnt (%s). Bitte neu per QR-Code anmelden." % SteamCM.keep_error }
	if Launcher.in_game and Launcher.remote_play:
		return { "ok": false, "short": "Remote Play", "login": false,
			"text": "Gerade über Remote Play gestartet: Steam zeigt den Spender (%s), nicht das Spiel. Normal gestartet zeigt Steam den Namen." % RemotePlay.donor_title() }
	if SteamCM.playing_blocked:
		return { "ok": false, "short": "Pausiert", "login": false,
			"text": "Steam am PC zeigt gerade ein eigenes Spiel." }
	if SteamCM.pc_signed_in and SteamCM.persona_state == 0 and not SteamCM.status_set:
		return { "ok": false, "short": "Unsichtbar", "login": false,
			"text": "In Steam am PC bist du offline oder unsichtbar – dann zeigt Steam Freunden kein Spiel. Status in Steam auf „Online“ stellen." }
	var showing := SteamCM.showing()
	if showing != "":
		return { "ok": true, "short": "Aktiv", "login": false, "text": "Freunde sehen jetzt „Spielt Nicht-Steam-Spiel: %s“." % showing }
	if Launcher.in_game and SteamCM.games_name != "":
		return { "ok": false, "short": "Verbindet …", "login": false, "text": "Anmeldung bei Steam läuft." }
	return { "ok": true, "short": "Bereit", "login": false,
		"text": "Freunde sehen „Spielt Nicht-Steam-Spiel: <Name>“." }


## Abstand der Abfrage ungelesener Nachrichten (Sekunden).
static func poll_secs(is_live: bool, notify_on: bool) -> float:
	if is_live:
		return 60.0
	return 15.0 if notify_on else 30.0


func _update_poll() -> void:
	var secs := poll_secs(live(), bool(Config.get_value("notify.steam", true)))
	if absf(_poll.wait_time - secs) > 0.1:
		_poll.wait_time = secs
		if not _poll.is_stopped():
			_poll.start()


## Dienst-Benachrichtigungen von Steams Chat-Server.
func _on_notice(method: String, body: PackedByteArray) -> void:
	match method:
		"FriendMessagesClient.IncomingMessage#1":
			# Die Zeile dazu (woher, ob und warum ein Pop-up) schreibt Notify – ohne Inhalt, Name und Steam-ID.
			on_incoming(parse_incoming(body))
		"FriendMessagesClient.NotifyAckMessageEcho#1":
			# Auf einem anderen Gerät gelesen: hier auch nicht mehr ungelesen.
			var d := SteamCM.Pb.decode(body)
			var fid := str(SteamCM.Pb.zahl(d, 1, 0))
			if unread.has(fid):
				unread.erase(fid)
				changed.emit()


## FriendMessagesClient.IncomingMessage (CFriendMessages_IncomingMessage_Notification):
## 1 steamid_friend (fixed64), 2 chat_entry_type (1 Nachricht, 2 schreibt, 6 hat verlassen),
## 4 message (BB-Code), 5 rtime32_server_timestamp (fixed32), 6 ordinal, 7 local_echo
## (eigene Nachricht von einem anderen Gerät), 8 message_no_bbcode, 9 low_priority.
static func parse_incoming(body: PackedByteArray) -> Dictionary:
	var d := SteamCM.Pb.decode(body)
	var plain := SteamCM.Pb.text(d, 8)
	return { "friend": str(SteamCM.Pb.zahl(d, 1, 0)), "kind": SteamCM.Pb.zahl(d, 2, 0),
		"text": clean(plain if plain != "" else SteamCM.Pb.text(d, 4)), "at": SteamCM.Pb.zahl(d, 5, 0),
		"ordinal": SteamCM.Pb.zahl(d, 6, 0), "echo": SteamCM.Pb.zahl(d, 7, 0) != 0,
		"low": SteamCM.Pb.zahl(d, 9, 0) != 0 }


## Eine eingehende Nachricht oder „schreibt“ verarbeiten (öffentlich für Tests und Rundgang).
func on_incoming(m: Dictionary) -> void:
	var fid := str(m.get("friend", ""))
	if fid == "" or fid == "0":
		return
	match int(m.get("kind", 0)):
		2:
			if bool(m.get("echo", false)):
				return
			_typing_at[fid] = Time.get_ticks_msec()
			if not typing.has(fid):
				typing[fid] = true
				typing_changed.emit(fid, true)
			_typing_off(fid)
		1:
			_typing_at.erase(fid)
			if typing.erase(fid):
				typing_changed.emit(fid, false)
			if demo:
				_demo_history(fid).append(
						{ "me": bool(m.get("echo", false)), "text": str(m.get("text", "")), "at": int(m.get("at", 0)), "ordinal": int(m.get("ordinal", 0)) })
			if not bool(m.get("echo", false)):
				last_at[fid] = int(m.get("at", 0)) if int(m.get("at", 0)) > 0 else int(Time.get_unix_time_from_system())
				if not chat_in_view(fid):
					unread[fid] = int(unread.get(fid, 0)) + 1
				changed.emit()
			messages.emit(fid)
			incoming.emit(m)
		6:
			_typing_at.erase(fid)
			if typing.erase(fid):
				typing_changed.emit(fid, false)


## „Schreibt“ endet von selbst, wenn Steam eine Weile nichts mehr meldet.
func _typing_off(fid: String) -> void:
	var stamp := int(_typing_at.get(fid, 0))
	await get_tree().create_timer(TYPING_SECS).timeout
	if int(_typing_at.get(fid, -1)) == stamp and typing.erase(fid):
		_typing_at.erase(fid)
		typing_changed.emit(fid, false)


func logged_in() -> bool:
	return demo or str(Config.get_value("accounts.steam_chat_refresh", "")) != ""


func my_id() -> String:
	return "76561198000000001" if demo else str(Config.get_value("accounts.steam_chat_id", ""))


func account_name() -> String:
	return "demo" if demo else str(Config.get_value("accounts.steam_chat_name", ""))


static func account_id(steam64: String) -> int:
	return int(steam64) - STEAM64 if steam64.is_valid_int() else 0


# --- Anmeldung per QR ------------------------------------------------------------------

## { ok, url, client_id, request_id, interval } oder { ok: false, error }
## Anmeldung als „Steam-App“ über Steams Chat-Server: nur so darf Uzai später auch senden
## (Steam lässt Nachrichten nur von Steam-App-Anmeldungen zu, nicht von Browser-Anmeldungen).
func login_start() -> Dictionary:
	var dd := PackedByteArray()
	dd.append_array(SteamCM.Pb.f_string(1, "Uzai"))
	dd.append_array(SteamCM.Pb.f_varint(2, 1))      # Steam-App
	dd.append_array(SteamCM.Pb.f_varint(3, 20))     # Windows 11
	dd.append_array(SteamCM.Pb.f_varint(4, 1))      # Desktop-PC
	var req := SteamCM.Pb.f_msg(3, dd)
	var r: Dictionary = await SteamCM.call_nonauthed("Authentication.BeginAuthSessionViaQR#1", req)
	if not r.ok:
		# Einmal neu versuchen (anderer Server), bevor es nur die Browser-Anmeldung gibt.
		_log("QR-Anmeldung (Steam-App): EResult %d %s – zweiter Versuch" % [int(r.eresult), str(r.error)])
		r = await SteamCM.call_nonauthed("Authentication.BeginAuthSessionViaQR#1", req)
	if not r.ok:
		_log("QR-Anmeldung (Steam-App) ging nicht: EResult %d %s – nehme die Browser-Anmeldung (nur lesen)" % [int(r.eresult), str(r.error)])
		var web := await _login_start_web()
		if bool(web.get("ok", false)):
			# Sichtbar machen: mit dieser Anmeldung kann Uzai nur lesen, nicht senden.
			web["warning"] = "Chat-Server antwortet nicht. Nur Lesen möglich. Später „Neuer QR-Code“."
		return web
	var d := SteamCM.Pb.decode(r.body)
	var url := SteamCM.Pb.text(d, 2)
	if url == "":
		return { "ok": false, "error": "Steam hat keinen QR-Code geschickt." }
	var iv := 5.0
	var raw: Variant = SteamCM.Pb.first(d, 4, null)
	if raw is int:
		var fb := PackedByteArray()
		fb.resize(4)
		fb.encode_u32(0, int(raw) & 0xFFFFFFFF)
		var f := fb.decode_float(0)
		iv = clampf(f, 1.0, 10.0) if is_finite(f) else 5.0
	# Die Kennung der Anfrage geht beim Abfragen als Bytes zurück: In anderer Art wäre es kein QR-Code von Steam.
	var rid: Variant = SteamCM.Pb.first(d, 3, PackedByteArray())
	if not (rid is PackedByteArray):
		return { "ok": false, "error": "Steam hat keinen QR-Code geschickt." }
	return { "ok": true, "cm": true, "url": url, "client_id": SteamCM.Pb.zahl(d, 1, 0), "request_id": rid, "interval": iv }


## Rückfall: Browser-Anmeldung über die Web-Schnittstelle (damit lässt sich nur lesen).
func _login_start_web() -> Dictionary:
	var r := await Net.post_form(API + "IAuthenticationService/BeginAuthSessionViaQR/v1/", {
		"device_friendly_name": "Uzai (%s)" % OS.get_name(), "platform_type": 2 })
	if not r.ok or not (r.data is Dictionary) or not (r.data.get("response") is Dictionary):
		return { "ok": false, "error": "Steam ist gerade nicht erreichbar. Ist der PC online?" if int(r.code) == 0
				else "Steam hat gerade keinen QR-Code geschickt. Gleich nochmal versuchen." }
	var d: Dictionary = r.data.response
	if str(d.get("challenge_url", "")) == "":
		return { "ok": false, "error": "Steam hat keinen QR-Code geschickt." }
	return { "ok": true, "url": str(d.challenge_url), "client_id": str(d.get("client_id", "")),
		"request_id": str(d.get("request_id", "")), "interval": clampf(Fremd.komma(d.get("interval"), 5.0), 1.0, 10.0) }


## "pending", "ok", "expired" oder "error". info bekommt bei neuem QR-Code die neue url.
func login_poll(info: Dictionary) -> String:
	if bool(info.get("cm", false)):
		return await _login_poll_cm(info)
	var r := await Net.post_form(API + "IAuthenticationService/PollAuthSessionStatus/v1/", {
		"client_id": str(info.client_id), "request_id": str(info.request_id) })
	if int(r.code) in [400, 401, 403] or (r.ok and not (r.data is Dictionary)):
		return "expired"
	if not r.ok:
		return "error"
	var d: Dictionary = r.data.get("response", {}) if r.data.get("response") is Dictionary else {}
	if str(d.get("new_challenge_url", "")) != "":
		info["url"] = str(d.new_challenge_url)
	if str(d.get("new_client_id", "")) != "":
		info["client_id"] = str(d.new_client_id)
	var refresh := str(d.get("refresh_token", ""))
	if refresh == "":
		return "pending"
	_logged_in(refresh, str(d.get("access_token", "")), str(d.get("account_name", "")))
	return "ok"


func _login_poll_cm(info: Dictionary) -> String:
	var req := PackedByteArray()
	req.append_array(SteamCM.Pb.f_varint(1, int(info.client_id)))
	req.append_array(SteamCM.Pb.f_bytes(2, info.request_id))
	var r: Dictionary = await SteamCM.call_nonauthed("Authentication.PollAuthSessionStatus#1", req)
	if not r.ok:
		var st := "error" if int(r.eresult) in [0, 3, 20] else "expired"
		_log("QR-Anmeldung: %s (EResult %d %s)" % ["abgelaufen" if st == "expired" else "keine Antwort", int(r.eresult), str(r.error)])
		return st
	var d := SteamCM.Pb.decode(r.body)
	var nurl := SteamCM.Pb.text(d, 2)
	if nurl != "":
		info["url"] = nurl
	var ncid := SteamCM.Pb.zahl(d, 1, 0)
	if ncid != 0:
		info["client_id"] = ncid
	var refresh := SteamCM.Pb.text(d, 3)
	if refresh == "":
		return "pending"
	_logged_in(refresh, SteamCM.Pb.text(d, 4), SteamCM.Pb.text(d, 6))
	return "ok"


func _logged_in(refresh: String, access: String, account: String) -> void:
	var sid := str(jwt_claims(refresh).get("sub", ""))
	Config.set_value("accounts.steam_chat_refresh", refresh)
	Config.set_value("accounts.steam_chat_id", sid)
	Config.set_value("accounts.steam_chat_name", account)
	# Sofort sichern (im Tresor): Wird Uzai gleich nach der Einrichtung beendet, war die Anmeldung
	# sonst weg, und beim nächsten Start hieß es „nicht angemeldet“.
	Config.save_settings()
	var cl := jwt_claims(refresh)
	_log("QR-Anmeldung ok: Art %s, Zugang %s, senden %s" % [str(cl.get("aud", [])), "ja" if access != "" else "nein", "ja" if darf_senden(refresh) else "nein"])
	_renew_block_until = 0
	_web_bad_until = 0
	_chat_web_bad_until = 0
	_diag_last.clear()
	SteamCM.reset_rare()
	Social.forget_owned()
	_set_access(access)
	error = ""
	_poll.start()
	changed.emit()
	refresh_unread()
	update_live()


## Kann Uzai mit dieser Anmeldung senden? (Nur Anmeldungen als Steam-App.)
func can_send() -> bool:
	return demo or darf_senden(str(Config.get_value("accounts.steam_chat_refresh", "")))


## Ist dieser Zugang eine Anmeldung als Steam-App (Zielgruppe „client“)? Steht dort keine Liste, nein.
static func darf_senden(token: String) -> bool:
	return Fremd.liste(jwt_claims(token).get("aud")).has("client")


func logout(why := "vom Nutzer") -> void:
	_log("Abgemeldet: " + why)
	Config.set_value("accounts.steam_chat_refresh", "")
	Config.set_value("accounts.steam_chat_id", "")
	Config.set_value("accounts.steam_chat_name", "")
	Config.set_value("accounts.steam_chat_access", "")
	_renew_block_until = 0
	_web_bad_until = 0
	_chat_web_bad_until = 0
	_access = ""
	_access_exp = 0
	unread = {}
	_poll.stop()
	SteamCM.own = {}
	SteamCM.stop_keep("abgemeldet")
	changed.emit()


## Die Angaben im Mittelteil eines Steam-Zugangs (JWT): sub = Steam-ID, exp = Ablauf.
static func jwt_claims(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() < 2:
		return {}
	var b := parts[1].replace("-", "+").replace("_", "/")
	while b.length() % 4 != 0:
		b += "="
	var d: Variant = Fremd.json(Marshalls.base64_to_utf8(b))
	return d if d is Dictionary else {}


## Gespeicherte Anmeldung aufgeben? Abgelaufen (exp vorbei) immer. Als Steam-App sonst nie:
## Steam verweigert solchen Anmeldungen das Erneuern des Web-Zugangs (EResult 15) auch dann, wenn
## die Anmeldung bei den Chat-Servern bestens funktioniert (so im Protokoll eines Nutzers) – das
## Abmelden deswegen brachte nach jedem Neustart den QR-Code. Als Browser-Anmeldung, wenn die
## Web-Übergabe sie ablehnt. (cm_denied bleibt für das Protokoll.)
static func should_logout(refresh: String, finalize_denied: bool, _cm_denied: bool, client: bool, now: int) -> bool:
	var exp := int(jwt_claims(refresh).get("exp", 0))
	if exp > 0 and now > exp:
		return true
	return false if client else finalize_denied


## Steam hat den Zugang abgelehnt (vor seinem Ablauf): beim nächsten Mal einen neuen holen.
func drop_access() -> void:
	_access = ""
	_access_exp = 0
	Config.set_value("accounts.steam_chat_access", "")


func _set_access(tok: String) -> void:
	_access = tok
	_access_exp = int(jwt_claims(tok).get("exp", 0))
	# Merken: nach einem Neustart gilt der Zugang weiter, solange er nicht abgelaufen ist.
	if tok != "" and str(Config.get_value("accounts.steam_chat_access", "")) != tok:
		Config.set_value("accounts.steam_chat_access", tok)


var _renew_block_until := 0     ## bis dahin (Unix) kein neuer Versuch, den Zugang zu erneuern


## Nimmt die Web-API den Zugang aus der Anmeldung gerade an (oder ist es noch offen)?
func web_ok() -> bool:
	return int(Time.get_unix_time_from_system()) >= _web_bad_until


## Dasselbe für den Chat (Ungelesenes, Verlauf) – unabhängig von Freunden, Erfolgen und Profil.
func chat_web_ok() -> bool:
	return int(Time.get_unix_time_from_system()) >= _chat_web_bad_until


## Hat die Web-API den Zugang abgelehnt? 400 (beim Nutzer: Zugang der Steam-App), 401, 403.
## (rein, getestet)
static func web_rejected(code: int) -> bool:
	return code in [400, 401, 403]


## Antwort der Web-API mit dem Zugang aus der Anmeldung (nicht mit eigenem Schlüssel) melden.
## Abgelehnt und als Steam-App angemeldet: WEB_BAD_S lang alles über Steams Chat-Server.
## Für den Chat (CHAT_WEB) gilt ein eigener Merker (chat_web_ok).
func note_web(code: int, what: String) -> void:
	if not web_rejected(code) or not can_send():
		return
	var now := int(Time.get_unix_time_from_system())
	if what in CHAT_WEB:
		if not chat_web_ok():
			return
		_chat_web_bad_until = now + WEB_BAD_S
		_log("Web-API lehnt den Zugang für den Chat ab (%s: HTTP %d) – Ungelesenes und Verlauf %d Std. über Steams Chat-Server" % [what, code, WEB_BAD_S / 3600])
		return
	if not web_ok():
		return
	_web_bad_until = now + WEB_BAD_S
	_log("Web-API lehnt den Zugang ab (%s: HTTP %d) – Freunde, Profil und Erfolge %d Std. über Steams Chat-Server" % [what, code, WEB_BAD_S / 3600])


## Eine Zeile Fehlersuche für Freunde, Profil und Chat (Weg, HTTP-Code bzw. EResult, Anzahl) –
## nur, wenn sich key für diese Art geändert hat. Nie Zugangsdaten.
func diag_log(kind: String, key: String, text: String) -> void:
	if str(_diag_last.get(kind, "")) == key:
		return
	_diag_last[kind] = key
	_log(text)


func _token() -> String:
	var now := int(Time.get_unix_time_from_system())
	if _access == "":
		# Zugang aus der letzten Sitzung (Steam gibt Anmeldungen als Steam-App oft keinen neuen).
		var saved := str(Config.get_value("accounts.steam_chat_access", ""))
		if saved != "" and str(jwt_claims(saved).get("sub", "")) == my_id():
			_set_access(saved)
	if _access != "" and now < _access_exp - 120:
		return _access
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	if refresh == "":
		return ""
	# Gerade erst vergeblich versucht: nicht bei jeder Abfrage erneut (das ging sonst mehrmals
	# je Sekunde an Steam). Alles Wichtige läuft ohnehin über die Verbindung zu Steams Chat-Servern.
	if now < _renew_block_until:
		return ""
	var cm_denied := false
	if can_send():
		var req := PackedByteArray()
		req.append_array(SteamCM.Pb.f_string(1, refresh))
		req.append_array(SteamCM.Pb.f_fixed64(2, int(my_id())))
		req.append_array(SteamCM.Pb.f_varint(3, 0))
		# Steht die Anmeldung bei Steams Chat-Servern, fragt Uzai als angemeldeter Nutzer.
		# Nur über die bestehende Anmeldung fragen. Ohne Anmeldung (nicht angemeldete Anfrage auf
		# frischer Verbindung) verweigert Steam es Anmeldungen als Steam-App ohnehin (EResult 15),
		# und die Anmeldung gleich danach auf derselben Verbindung scheiterte oft („getrennt 1000“).
		# Steht noch keine Sitzung (etwa weil Steam am PC läuft und Uzai keine eigene offen hält),
		# meldet call_authed sich kurz an – vorher kam dann gar kein Zugang, und Freunde, Erfolge und
		# Spielzeit blieben leer, obwohl die QR-Anmeldung gültig war (SteamCM.RARE_METHODS).
		var cr: Dictionary = await SteamCM.call_authed(refresh, "Authentication.GenerateAccessTokenForApp#1", req)
		if cr.ok:
			var cd := SteamCM.Pb.decode(cr.body)
			var acc := SteamCM.Pb.text(cd, 1)
			if acc != "":
				var nref := SteamCM.Pb.text(cd, 2)
				if nref != "":
					Config.set_value("accounts.steam_chat_refresh", nref)
				_set_access(acc)
				return _access
		# Nur diese Antworten heißen „Anmeldung ungültig“; alles andere (Verbindung, Zeitlimit,
		# Steam beschäftigt) ist vorübergehend.
		cm_denied = int(cr.eresult) in [5, 15, 26, 27]
		# Web-Schnittstelle und Web-Übergabe lehnen Anmeldungen als Steam-App immer ab (EResult
		# 15/63, finalizelogin 15 – so im Protokoll): gar nicht erst versuchen. Alles läuft über die
		# Chat-Server; in 10 Minuten wieder fragen.
		_log("Web-Zugang über Steam: EResult %d – Chat läuft über die Chat-Server" % int(cr.eresult))
		_renew_block_until = int(Time.get_unix_time_from_system()) + 600
		return ""
	var r := await Net.post_form(API + "IAuthenticationService/GenerateAccessTokenForApp/v1/", {
		"refresh_token": refresh, "steamid": my_id(), "renewal_type": 0 })
	var d: Variant = r.data.get("response") if r.ok and r.data is Dictionary else null
	if d is Dictionary and str(d.get("access_token", "")) != "":
		if str(d.get("refresh_token", "")) != "":
			Config.set_value("accounts.steam_chat_refresh", str(d.refresh_token))
		_set_access(str(d.access_token))
		return _access
	# Für Anmeldungen per QR (Browser-Art) gibt Steam hier oft nichts zurück – das hieß bisher
	# „abgelaufen“, und nach jedem Neustart musste man sich neu anmelden. Stattdessen wie der
	# Browser: mit der Anmeldung bei steamcommunity.com anmelden und den Webchat-Zugang holen.
	_log("Zugang erneuern: HTTP %d, EResult %s, kein Zugang – versuche steamcommunity.com" % [int(r.code), Net.header(r, "x-eresult")])
	if int(r.code) == 0:
		error = "Steam ist gerade nicht erreichbar."
		return ""
	_finalize_denied = false
	var cookie := await _finalize_cookie()
	if cookie != "":
		var t := await _async_config(cookie)
		if t != "":
			_set_access(t)
			error = ""
			return _access
	# Anmeldungen als Steam-App gelten für die Web-Übergabe nicht – dort abgelehnt zu werden, heißt
	# also nichts. Abgemeldet wird nur, wenn die Anmeldung wirklich abgelaufen ist oder Steams
	# Chat-Server sie ausdrücklich ablehnt (früher genügte ein kurzer Aussetzer beim Start, und
	# nach dem Neustart kam wieder der QR-Code).
	_renew_block_until = int(Time.get_unix_time_from_system()) + 600
	if should_logout(refresh, _finalize_denied, cm_denied, can_send(), int(Time.get_unix_time_from_system())):
		# Steam lehnt die Anmeldung selbst ab: dann ist sie wirklich abgelaufen.
		error = "Die Steam-Anmeldung ist abgelaufen. Bitte neu anmelden."
		logout(
				"Steam lehnt die gespeicherte Anmeldung ab (Web-Übergabe %s, Chat-Server %s)" % ["abgelehnt" if _finalize_denied else "ok", "abgelehnt" if cm_denied
				else "ok"])
	else:
		error = "Steam hat gerade keinen Zugang gegeben. Gleich nochmal versuchen."
	return ""


# --- Nachrichten -----------------------------------------------------------------------

## Wie oft der offene Chat nachsieht (Sekunden). Bräuchte jede Abfrage eine eigene Sitzung bei
## Steams Chat-Servern, während Steam am PC angemeldet ist, seltener: Alle 4 s hielt die Abfrage
## diese zweite Sitzung dauerhaft offen, und kurz danach standen alle Freunde auf „offline“
## (Fehler 36). So schließt sie zwischen zwei Abfragen (SteamCM.IDLE_CLOSE_PC).
static func chat_poll_secs(needs_session: bool, pc_on: bool) -> float:
	return CHAT_POLL_PC if needs_session and pc_on else CHAT_POLL


func chat_poll() -> float:
	return chat_poll_secs(history_needs_session(), SteamCM.pc_maybe())


## Geht der Verlauf über eine eigene Sitzung bei Steams Chat-Servern? Nicht, wenn die
## Dauerverbindung ohnehin steht oder ein Web-Zugang da ist.
func history_needs_session() -> bool:
	if demo or SteamCM.live:
		return false
	return not chat_web_ok() or not (_access != "" and int(Time.get_unix_time_from_system()) < _access_exp - 120)


## Verlauf mit einem Freund, älteste zuerst: [{ me: bool, text, at }]
## mark_read = false: nur nachsehen (Vorschau), ohne die Nachrichten als gelesen zu melden.
func history(friend_id: String, count := 80, mark_read := true) -> Array:
	if demo:
		if mark_read and unread.has(friend_id):
			unread.erase(friend_id)
			_demo_read = true
			changed.emit()
		return _demo_history(friend_id).duplicate()
	var tok := ""
	if chat_web_ok() or not can_send():
		tok = await _token()
	if tok == "":
		# Ohne Web-Zugang (Steam erneuert ihn Anmeldungen als Steam-App nicht) oder wenn die
		# Web-API ihn ablehnt: über die Chat-Server, bei denen Uzai angemeldet ist.
		if can_send():
			return await _history_cm(friend_id, count, mark_read)
		diag_log("verlauf", "kein", "Verlauf: kein Zugang (Web-Zugang fehlt, Anmeldung darf nur lesen)")
		return []
	var r := await Net.get_json(API + "IFriendMessagesService/GetRecentMessages/v1/?" + Net.query({
		"access_token": tok, "steamid1": my_id(), "steamid2": friend_id, "count": count,
		"most_recent_conversation": "false", "rtime32_start_time": 0, "bbcode_format": "false", "ordinal": 0 }))
	if not r.ok or not (r.data is Dictionary):
		diag_log("verlauf", "web%d" % int(r.code), "Verlauf: Web-API HTTP %d" % int(r.code))
		if web_rejected(int(r.code)) and can_send():
			note_web(int(r.code), "Verlauf")
			return await _history_cm(friend_id, count, mark_read)
		error = "Der Verlauf ließ sich gerade nicht laden." if int(r.code) > 0 else "Steam ist gerade nicht erreichbar. Ist der PC online?"
		return []
	error = ""
	var out := parse_messages(r.data, account_id(my_id()))
	diag_log("verlauf", "web200", "Verlauf: Web-API ok, %d Nachrichten" % out.size())
	if mark_read and unread.has(friend_id):
		unread.erase(friend_id)
		_mark_read(friend_id, tok)
		changed.emit()
	return out


## Verlauf über Steams Chat-Server (FriendMessages.GetRecentMessages#1).
func _history_cm(friend_id: String, count: int, mark_read: bool) -> Array:
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var req := PackedByteArray()
	req.append_array(SteamCM.Pb.f_fixed64(1, int(my_id())))
	req.append_array(SteamCM.Pb.f_fixed64(2, int(friend_id)))
	req.append_array(SteamCM.Pb.f_varint(3, count))
	req.append_array(SteamCM.Pb.f_varint(4, 0))
	req.append_array(SteamCM.Pb.f_varint(6, 0))
	var r: Dictionary = await SteamCM.call_authed(refresh, "FriendMessages.GetRecentMessages#1", req)
	if not r.ok:
		error = "Der Verlauf ließ sich gerade nicht laden." if int(r.eresult) != 0 else "Steam ist gerade nicht erreichbar. Ist der PC online?"
		diag_log("verlauf", "cm%d%s" % [int(r.eresult), str(r.error)], "Verlauf: Chat-Server EResult %d %s" % [int(r.eresult), str(r.error)])
		return []
	error = ""
	var out := parse_messages(messages_from_pb(r.body), account_id(my_id()))
	diag_log("verlauf", "cm1", "Verlauf: Chat-Server ok, %d Nachrichten" % out.size())
	if mark_read and unread.has(friend_id):
		unread.erase(friend_id)
		_mark_read(friend_id, "")
		changed.emit()
	return out


## Antwort von GetRecentMessages (Protobuf) in die Form der Web-API bringen.
static func messages_from_pb(body: PackedByteArray) -> Dictionary:
	var Pb = SteamCM.Pb
	var list: Array = []
	for raw in (Pb.decode(body).get(1, []) as Array):
		if not (raw is PackedByteArray):
			continue
		var m: Dictionary = Pb.decode(raw)
		list.append({ "accountid": Pb.zahl(m, 1, 0), "timestamp": Pb.zahl(m, 2, 0),
			"message": Pb.text(m, 3), "ordinal": Pb.zahl(m, 4, 0) })
	return { "response": { "messages": list } }


## Ungelesenes über Steams Chat-Server (FriendMessages.GetActiveMessageSessions#1):
## { Steam-ID: Anzahl }, null wenn es nicht ging.
func _unread_cm() -> Variant:
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var req := PackedByteArray()
	req.append_array(SteamCM.Pb.f_varint(1, 0))
	req.append_array(SteamCM.Pb.f_varint(2, 1))
	var r: Dictionary = await SteamCM.call_authed(refresh, "FriendMessages.GetActiveMessageSessions#1", req)
	if not r.ok:
		return null
	return unread_from_pb(r.body)


static func unread_from_pb(body: PackedByteArray) -> Dictionary:
	var Pb = SteamCM.Pb
	var u := {}
	for raw in (Pb.decode(body).get(1, []) as Array):
		if raw is PackedByteArray:
			var s: Dictionary = Pb.decode(raw)
			var n: int = Pb.zahl(s, 4, 0)
			if n > 0:
				u[str(int(Pb.zahl(s, 1, 0)) + STEAM64)] = n
	return u


static func parse_messages(data: Dictionary, my_account: int) -> Array:
	var out: Array = []
	for m in Fremd.zeilen(data, "response/messages"):
		out.append({ "me": Fremd.zahl(m.get("accountid")) == my_account, "text": clean(Fremd.text(m.get("message"))),
			"at": Fremd.zahl(m.get("timestamp")), "ordinal": Fremd.zahl(m.get("ordinal")) })
	out.sort_custom(func(a, b): return int(a.at) < int(b.at) or (int(a.at) == int(b.at) and int(a.ordinal) < int(b.ordinal)))
	return out


## Steam schickt Sticker, Emoticons und Links als BB-Code: lesbar machen. Die beiden Muster werden einmal übersetzt
## (früher zweimal je Nachricht – bei jedem Blick in einen offenen Chat für jede der 80 Nachrichten).
static var _BB_BILD := RegEx.create_from_string("\\[(emoticon|sticker)[^\\]]*\\]([^\\[]*)\\[/\\1\\]")
static var _BB_MARKE := RegEx.create_from_string("\\[/?[a-z]+[^\\]]*\\]")
## Steam also sends images, videos and links as BB code, with the URL inside the tag. Removing the tag must not
## drop the URL, otherwise nothing of an image would remain in the chat. The URL stays as text; the chat view
## turns it into an image or a card (chat_link.gd).
static var _BB_LINK := RegEx.create_from_string("\\[url=\"?([^\\]\"\\s]+)\"?\\]([^\\[]*)\\[/url\\]")
static var _BB_QUELLE := RegEx.create_from_string("\\[(?:img|video|og|embed)\\b[^\\]]*?\\b(?:src|url)=\"([^\"]+)\"[^\\]]*\\]")
static var _BB_IMG := RegEx.create_from_string("\\[img\\]([^\\[\\s]+)\\[/img\\]")


static func clean(text: String) -> String:
	var t := _BB_BILD.sub(text, ":$2:", true)
	for m in _BB_LINK.search_all(t):
		var ziel := m.get_string(1)
		var wort := m.get_string(2).strip_edges()
		t = t.replace(m.get_string(), ziel if wort == "" or wort == ziel else "%s %s" % [wort, ziel])
	t = _BB_QUELLE.sub(t, " $1 ", true)
	t = _BB_IMG.sub(t, " $1 ", true)
	return _BB_MARKE.sub(t, "", true).strip_edges()


func send(friend_id: String, text: String) -> String:
	if demo:
		var list: Array = _demo_history(friend_id)
		list.append({ "me": true, "text": text, "at": int(Time.get_unix_time_from_system()), "ordinal": 0 })
		_demo_chats[friend_id] = list
		messages.emit(friend_id)
		_demo_reply(friend_id)
		return ""
	# Senden geht nur über Steams Chat-Server, angemeldet als Steam-App (über HTTP: 404).
	# Uzai wechselt dafür nie in ein anderes Programm.
	if not can_send():
		return "Zum Senden neu per QR-Code anmelden."
	return await _send_cm(friend_id, text, 1)


## Über Steams Chat-Server senden (FriendMessages.SendMessage#1). "" = angekommen.
func _send_cm(friend_id: String, text: String, kind: int) -> String:
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var req := PackedByteArray()
	req.append_array(SteamCM.Pb.f_fixed64(1, int(friend_id)))
	req.append_array(SteamCM.Pb.f_varint(2, kind))
	if text != "":
		req.append_array(SteamCM.Pb.f_string(3, text))
	req.append_array(SteamCM.Pb.f_varint(4, 0))
	var r: Dictionary = await SteamCM.call_authed(refresh, "FriendMessages.SendMessage#1", req)
	if r.ok:
		if kind == 1:
			diag_log("senden", "cm1", "Senden: Chat-Server ok")
			messages.emit(friend_id)
		return ""
	if kind == 1:
		diag_log("senden", "cm%d" % int(r.eresult), "Senden: Chat-Server EResult %d" % int(r.eresult))
	var res := int(r.eresult)
	if kind == 1:
		_log("Senden an %s über Steam: EResult %d %s" % [log_tag(friend_id), res, str(r.error)])
	if res == 0:
		return str(r.error) if str(r.error) != "" else "Steam ist gerade nicht erreichbar."
	return send_error(200, str(res))


func _async_config(cookie: String) -> String:
	var r := await Net.get_json("https://steamcommunity.com/pointssummary/ajaxgetasyncconfig", PackedStringArray(["Cookie: " + cookie]))
	if r.ok and r.data is Dictionary and (r.data as Dictionary).get("data") is Dictionary:
		return str(((r.data as Dictionary).data as Dictionary).get("webapi_token", ""))
	_log("ajaxgetasyncconfig: HTTP %d" % int(r.code))
	return ""


## Steams Anmelde-Übergabe (wie im Browser nach dem Login): liefert das Cookie für steamcommunity.com.
func _finalize_cookie() -> String:
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	if refresh == "":
		return ""
	var sid := Remote.secure_token(12)
	var h := PackedStringArray(["Origin: https://steamcommunity.com", "Referer: https://steamcommunity.com/", "Cookie: sessionid=" + sid])
	var r := await Net.post_form("https://login.steampowered.com/jwt/finalizelogin", {
		"nonce": refresh, "sessionid": sid, "redir": "https://steamcommunity.com/login/home/?goto=" }, h)
	if not r.ok or not (r.data is Dictionary):
		_log("finalizelogin: HTTP %d %s" % [int(r.code), str(r.get("text", "")).left(120)])
		_finalize_denied = int(r.code) in [401, 403]
		return ""
	if (r.data as Dictionary).has("error") and Fremd.zahl((r.data as Dictionary).get("error"), 1) != 0:
		_log("finalizelogin: abgelehnt, Fehler %s" % str((r.data as Dictionary).error))
		_finalize_denied = true
		return ""
	for ti in Fremd.zeilen(r.data, "transfer_info"):
		# Nur an steamcommunity.com selbst, verschlüsselt: „enthält den Namen“ träfe auch eine fremde Adresse, die ihn
		# nur im Pfad oder als Anfang ihres eigenen Namens führt – und die bekäme die Übergabe der Anmeldung.
		if not uebergabe_ok(Fremd.text(ti.get("url"))):
			continue
		var params: Dictionary = ti.get("params", {}) if ti.get("params") is Dictionary else {}
		var f := { "steamID": my_id() }
		for k in params.keys():
			f[k] = str(params[k])
		var raw := await Net.request(str(ti.url), PackedStringArray(["Content-Type: application/x-www-form-urlencoded", "Cookie: sessionid=" + sid]),
				HTTPClient.METHOD_POST, Net.query(f))
		for line in raw.get("headers", PackedStringArray()):
			var l := str(line)
			if l.to_lower().begins_with("set-cookie:") and l.contains("steamLoginSecure="):
				var v := l.substr(l.find("steamLoginSecure=")).get_slice(";", 0)
				if not v.ends_with("=deleted"):
					return v
		_log("settoken: HTTP %d, kein Cookie" % int(raw.get("code", 0)))
	return ""


static func uebergabe_ok(url: String) -> bool:
	var p := Sicher.url_parts(url)
	return not p.is_empty() and str(p.scheme) == "https" and str(p.host) == "steamcommunity.com" and str(p.port) in ["", "443"]


## "1" = angenommen. Steam meldet das Ergebnis im Kopf „x-eresult“, oft auch bei HTTP 200;
## ohne diesen Kopf zählt der HTTP-Code. "" = keine Antwort.
static func send_result(r: Dictionary) -> String:
	if int(r.get("code", 0)) == 0:
		return ""
	var er := Net.header(r, "x-eresult")
	if er != "":
		return er
	var c := int(r.code)
	return "1" if c >= 200 and c < 300 else str(c)


## Ein Satz zum Grund, warum Steam die Nachricht nicht angenommen hat.
static func send_error(code: int, res: String) -> String:
	if code == 0 or res == "":
		return "Steam ist gerade nicht erreichbar."
	match res:
		"15":
			return "Steam lässt die Nachricht nicht zu (Zugriff verweigert) – seid ihr noch befreundet, oder hat er Nachrichten blockiert?"
		"84":
			return "Zu viele Nachrichten. Steam bremst kurz."
		"8":
			return "Steam hat die Anmeldung nicht angenommen. Bitte unter Einstellungen → Konten den Steam-Chat neu verbinden."
		"17":
			return "Steam hat die Nachricht abgelehnt (gesperrt oder blockiert)."
		"20", "3":
			return "Steam ist gerade nicht erreichbar."
	return "Steam hat die Nachricht nicht angenommen. Gleich noch einmal senden."


var _last_log := ""
var _log_names := {}            ## Steam-ID -> „Freund 1“ … (nur fürs Protokoll, je Lauf)


## Kürzel eines Freundes fürs Protokoll: „Freund 1“, „Freund 2“ … in der Reihenfolge, in der er in diesem
## Lauf auftaucht. So lassen sich Zeilen zuordnen, ohne Name oder Steam-ID im Klartext.
func log_tag(fid: String) -> String:
	if fid == "" or fid == "0":
		return "unbekannt"
	if not _log_names.has(fid):
		_log_names[fid] = "Freund %d" % (_log_names.size() + 1)
	return str(_log_names[fid])


## Eine Zeile ins Protokoll, auch wenn sie der vorigen gleicht (je eingehender Nachricht eine).
func log_line(text: String) -> void:
	_log(text, true)


## Protokoll (logs/steam.log im Datenordner), ohne Zugangsdaten. Gleiche Zeilen hintereinander nur einmal
## (außer immer).
func _log(text: String, immer := false) -> void:
	if demo or (text == _last_log and not immer):
		return
	_last_log = text
	Logdatei.zeile(Config.path("logs/steam.log"), text, 300000)


## Dem Freund in Steam zeigen, dass du schreibst („… schreibt“). Nur ein Hinweis: klappt es
## nicht, passiert nichts. Höchstens alle zehn Sekunden.
func send_typing(friend_id: String) -> void:
	if demo or friend_id == "" or not logged_in() or not can_send():
		return
	var now := Time.get_ticks_msec()
	if now - int(_typing_sent.get(friend_id, -100000)) < 10000:
		return
	_typing_sent[friend_id] = now
	# Nur wenn die Verbindung zu Steam ohnehin steht (fürs Tippen nicht extra verbinden).
	if SteamCM.state == "angemeldet":
		_send_cm(friend_id, "", 2)


func is_typing(friend_id: String) -> bool:
	return typing.has(friend_id)


## Rundgang: der Freund tippt kurz und antwortet.
func _demo_reply(friend_id: String) -> void:
	if _demo_busy.has(friend_id):
		return
	_demo_busy[friend_id] = true
	await get_tree().create_timer(0.8).timeout
	typing[friend_id] = true
	typing_changed.emit(friend_id, true)
	await get_tree().create_timer(2.4).timeout
	typing.erase(friend_id)
	typing_changed.emit(friend_id, false)
	var list: Array = _demo_history(friend_id)
	list.append({ "me": false, "text": DEMO_REPLIES[_demo_n % DEMO_REPLIES.size()], "at": int(Time.get_unix_time_from_system()), "ordinal": 0 })
	_demo_n += 1
	_demo_chats[friend_id] = list
	_demo_busy.erase(friend_id)
	messages.emit(friend_id)


## Wer dir geschrieben hat und was du noch nicht gelesen hast.
func refresh_unread() -> void:
	if demo:
		if unread.is_empty() and not _demo_read:
			unread = { "76561190000000001": 2 }
			changed.emit()
		return
	if not logged_in():
		return
	_note_weg()
	var tok := ""
	if chat_web_ok() or not can_send():
		tok = await _token()
	var u := {}
	if tok == "":
		if not can_send():
			diag_log("ungelesen", "kein", "Ungelesen: kein Zugang (Web-Zugang fehlt, Anmeldung darf nur lesen)")
			return
		# Steam am PC angemeldet: keine eigene Sitzung nur für Ungelesenes (siehe live_wanted, Fehler 36).
		# Steht gerade eine kurze Sitzung (Freunde, Verlauf, Senden …), fragt Uzai in ihr mit (_on_cm_list).
		if SteamCM.pc_maybe() and not SteamCM.live and SteamCM.state != "angemeldet":
			diag_log("ungelesen-pc", "pc", "Ungelesen: Steam am PC angemeldet, keine Web-API – nur in Uzais kurzen Sitzungen")
			return
		var got: Variant = await _unread_cm()
		if not (got is Dictionary):
			diag_log("ungelesen", "cm0", "Ungelesen: Chat-Server ohne Antwort")
			return
		diag_log("ungelesen", "cm1", "Ungelesen: Chat-Server ok")
		u = got
	else:
		var r := await Net.get_json(
				API + "IFriendMessagesService/GetActiveMessageSessions/v1/?" + Net.query({ "access_token": tok, "only_sessions_with_messages": "true" }))
		if not r.ok or not (r.data is Dictionary):
			diag_log("ungelesen", "web%d" % int(r.code), "Ungelesen: Web-API HTTP %d" % int(r.code))
			note_web(int(r.code), "Ungelesen")
			return
		diag_log("ungelesen", "web200", "Ungelesen: Web-API ok")
		for s in Fremd.zeilen(r.data, "response/message_sessions"):
			var n := Fremd.zahl(s.get("unread_message_count"))
			if n > 0:
				u[str(Fremd.zahl(s.get("accountid_friend")) + STEAM64)] = n
	if JSON.stringify(u) != JSON.stringify(unread):
		var more := new_unread(unread, u)
		if not more.is_empty():
			log_line("Abfrage: neu ungelesen bei %s" % ", ".join(PackedStringArray(more.map(func(f: Variant) -> String: return log_tag(str(f))))))
		unread = u
		changed.emit()
		# Neu Ungelesenes: die letzte Nachricht holen (ohne sie als gelesen zu melden) und als
		# Pop-up zeigen. Kam sie schon über die Dauerverbindung, verwirft Notify sie als doppelt.
		for fid in more:
			if not last_at.has(fid):
				last_at[fid] = int(Time.get_unix_time_from_system())
			if not chat_in_view(fid):
				_popup_from_poll(fid)


## Ist der Chat mit diesem Freund offen und wirklich zu sehen (Notify.chat_seen)? Für den offenen Chat steht das
## Ergebnis als „chat.steam“ in Zustand.lage(): zu_sehen (gilt als gelesen, kein Pop-up) oder verdeckt (Pop-up).
func chat_in_view(fid: String) -> bool:
	var seen := Notify.chat_seen(open_chat, fid, open_view != null, Notify.view_seen(open_view) if open_view != null else false, true)
	if fid != "" and fid == open_chat:
		Zustand.melden("chat.steam", "zu_sehen" if seen else "verdeckt")
	return seen


## Freunde, bei denen seit der letzten Abfrage mehr ungelesen ist.
static func new_unread(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for k in after.keys():
		if int(after[k]) > int(before.get(k, 0)):
			out.append(str(k))
	return out


func _popup_from_poll(fid: String) -> void:
	var list := await history(fid, 6, false)
	var last := last_from_friend(list)
	if last.is_empty():
		return
	incoming.emit(
			{ "friend": fid, "kind": 1, "text": str(last.text), "at": int(last.at), "ordinal": int(last.get("ordinal", 0)), "echo": false, "from_poll": true })


## Die letzte Nachricht des Freundes (nicht deine) aus einem Verlauf, {} wenn keine.
static func last_from_friend(list: Array) -> Dictionary:
	for i in range(list.size() - 1, -1, -1):
		var m: Dictionary = list[i]
		if not bool(m.get("me", false)) and str(m.get("text", "")) != "":
			return m
	return {}


func _mark_read(friend_id: String, tok: String) -> void:
	if tok == "":
		var req := PackedByteArray()
		req.append_array(SteamCM.Pb.f_fixed64(1, int(friend_id)))
		req.append_array(SteamCM.Pb.f_varint(2, int(Time.get_unix_time_from_system())))
		SteamCM.notify_authed("FriendMessages.AckMessage#1", req)
		return
	Net.post_form(API + "IFriendMessagesService/AckMessage/v1/", { "access_token": tok, "steamid_partner": friend_id,
		"timestamp": int(Time.get_unix_time_from_system()) })


func _demo_history(friend_id: String) -> Array:
	if _demo_chats.has(friend_id):
		return _demo_chats[friend_id]
	var now := int(Time.get_unix_time_from_system())
	var lines := [[false, "Hast du am Wochenende Zeit für eine Runde?", 3 * 86400 + 4000], [true, "Samstag ginge", 3 * 86400 + 3700],
		[false, "Bist du heute Abend online?", 26000], [true, "Ja, so ab acht", 25800], [false, "Nice, dann Dota?", 25700],
		[true, "Klar. Bring Pauli mit", 25600], [false, "GG gestern übrigens", 5400], [true, "Haha, der letzte Teamfight war wild", 5300],
		[false, "Schau mal, der neue Trailer: https://www.youtube.com/watch?v=E3Huy2cdih0", 4000],
		[false, "Ich bin gleich im Sprachkanal", 300], [false, "Kommst du?", 120]]
	var out: Array = []
	for l in lines:
		out.append({ "me": l[0], "text": l[1], "at": now - int(l[2]), "ordinal": 0 })
	_demo_chats[friend_id] = out
	return out

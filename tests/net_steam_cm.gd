extends Node
## Netz-Probe für Steams Chat-Server (CM): ein nachgebauter CM-Server im selben Prozess
## (WebSocket, protobuf, Multi mit gzip) – so wie ihn die Steam-App sieht. Geprüft werden die
## QR-Anmeldung als Steam-App, die Anmeldung am Chat-Server und das Senden einer Nachricht –
## ohne dass Uzai irgendein anderes Programm nach vorn holt. Dazu die Dauerverbindung für
## Mitteilungen: Status wie in Steam (nie „unsichtbar“), eingehende Nachrichten und „schreibt“ (der Server schickt
## FriendMessagesClient.IncomingMessage#1), Pop-ups ohne Doppelte, Wiederverbinden.
## Status der Freunde in Echtzeit: Freundesliste nach der Anmeldung (ClientFriendsList), Abfrage
## (ClientRequestFriendData) und Meldungen (ClientPersonaState) – wer online kommt, spielt, geht.
## Aufruf (eigener Datenordner, die Probe trägt Test-Zugangsdaten ein):
##   UZAI_DATA=<ordner> godot --headless --path . res://tests/net_steam_cm.tscn

const CM := preload("res://src/core/steam_cm.gd")
const InstallParse := preload("res://src/core/install_parse.gd")
const SE_ := preload("res://src/core/steam_erfolge.gd")
const PORT := 18766
const FRIEND := "76561197960267728"
const ME := 76561198000000001
const FRIEND2 := "76561198000000777"
const CLAN := "103582791429521412"

var fails := 0
var srv := TCPServer.new()
var peers: Array[WebSocketPeer] = []
var seen: Array = []                ## { emsg, head, body, name }
var polls := 0
var logon_result := 1
var push_friends := false           ## nach der Anmeldung die Freundesliste schicken (wie Steam)
var personas := {}                  ## Steam-ID -> Status, den der Server auf Anfrage meldet
## Steam-ID -> { name, state, game_id, game } für Player.GetPlayerLinkDetails#1
var links := {}


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	if srv.listen(PORT, "127.0.0.1") != OK:
		print("Port %d belegt" % PORT)
		get_tree().quit(1)
		return
	OS.set_environment("UZAI_STEAM_CM", "ws://127.0.0.1:%d/cmsocket/" % PORT)
	# Erst ohne Dauerverbindung (Senden wie bisher), am Ende mit.
	Config.set_value("notify.steam", false)
	SteamChat.logout()
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


# --- Nachgebauter Chat-Server ------------------------------------------------------------------

func _process(_dt: float) -> void:
	while srv.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(srv.take_connection())
		peers.append(ws)
	for ws in peers:
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			_on_msg(ws, ws.get_packet())


func _frame(emsg: int, head: PackedByteArray, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, (emsg | CM.PROTO_MASK) & 0xFFFFFFFF)
	out.encode_u32(4, head.size())
	out.append_array(head)
	out.append_array(body)
	return out


func _on_msg(ws: WebSocketPeer, msg: PackedByteArray) -> void:
	var emsg := int(msg.decode_u32(0)) & ~CM.PROTO_MASK & 0xFFFFFFFF
	var hlen := int(msg.decode_u32(4))
	var head := CM.Pb.decode(msg.slice(8, 8 + hlen))
	var body := CM.Pb.decode(msg.slice(8 + hlen))
	var name := CM.Pb.text(head, 12)
	seen.append({ "emsg": emsg, "head": head, "body": body, "name": name })
	match emsg:
		CM.EMSG_LOGON:
			# Wie Steam: mit Zugang angemeldet wird unter der eigenen Steam-ID (aus dem Zugang).
			var claimed := int(CM.Pb.first(head, 1, 0))
			var token_sub := str(SteamChat.jwt_claims(CM.Pb.text(body, 108)).get("sub", ""))
			var res_l := logon_result if str(claimed) == token_sub else 5
			var rb := PackedByteArray()
			rb.append_array(CM.Pb.f_varint(1, res_l))
			rb.append_array(CM.Pb.f_varint(3, 9))
			var h := PackedByteArray()
			h.append_array(CM.Pb.f_fixed64(1, ME if res_l == 1 else 0))
			h.append_array(CM.Pb.f_varint(2, 1234))
			# Wie Steam: die Antwort steckt gepackt in einer Sammelnachricht (Multi, gzip).
			var inner := _frame(CM.EMSG_LOGON_RESPONSE, h, rb)
			var data := PackedByteArray()
			data.resize(4)
			data.encode_u32(0, inner.size())
			data.append_array(inner)
			var multi := PackedByteArray()
			multi.append_array(CM.Pb.f_varint(1, data.size()))
			multi.append_array(CM.Pb.f_bytes(2, data.compress(FileAccess.COMPRESSION_GZIP)))
			ws.send(_frame(CM.EMSG_MULTI, CM.Pb.f_fixed64(1, 0), multi), WebSocketPeer.WRITE_MODE_BINARY)
			if res_l == 1 and push_friends:
				var fl := CM.Pb.f_varint(1, 0)
				for id in [FRIEND, FRIEND2, CLAN]:
					var fb := CM.Pb.f_fixed64(1, int(id))
					fb.append_array(CM.Pb.f_varint(2, 3))
					fl.append_array(CM.Pb.f_msg(2, fb))
				ws.send(_frame(CM.EMSG_FRIENDS_LIST, h, fl), WebSocketPeer.WRITE_MODE_BINARY)
		CM.EMSG_REQUEST_FRIEND_DATA:
			# Wie Steam: zu jedem erfragten Freund eine Status-Meldung (nur, wen der Server kennt).
			var list: Array = []
			for id in body.get(2, []):
				if personas.has(str(id)):
					var pd: Dictionary = (personas[str(id)] as Dictionary).duplicate()
					pd["id"] = str(id)
					list.append(pd)
			if not list.is_empty():
				var hp := CM.Pb.f_fixed64(1, ME)
				hp.append_array(CM.Pb.f_varint(2, 1234))
				ws.send(_frame(CM.EMSG_PERSONA_STATE, hp, _persona_body(list, int(CM.Pb.first(body, 1, 0)))), WebSocketPeer.WRITE_MODE_BINARY)
		CM.EMSG_GET_USER_STATS:
			# Wie Steam: Antwort mit Schema (binäre KeyValues) und Freischaltzeiten – hier ohne
			# Auftragsnummer im Kopf (Uzai ordnet über die App-ID zu). FRIEND2 ist privat.
			var who := str(CM.Pb.first(body, 4, 0))
			var ub := CM.Pb.f_fixed64(1, int(CM.Pb.first(body, 1, 0)))
			ub.append_array(CM.Pb.f_varint(2, 15 if who == FRIEND2 else 1))
			if who != FRIEND2:
				if int(CM.Pb.first(body, 3, 0)) == -1:
					ub.append_array(CM.Pb.f_bytes(4, FileAccess.get_file_as_bytes("res://tests/fixtures/steam_pc/appcache/stats/UserGameStatsSchema_480.bin")))
				var blk := CM.Pb.f_varint(1, 1)
				for t in ([1760000000, 0, 1761000000] if who == str(ME) else [0, 1762000000, 0]):
					blk.append_array(CM.Pb.f_fixed32(2, t))
				ub.append_array(CM.Pb.f_msg(6, blk))
			var hu := CM.Pb.f_fixed64(1, ME)
			hu.append_array(CM.Pb.f_varint(2, 1234))
			ws.send(_frame(CM.EMSG_GET_USER_STATS_RESPONSE, hu, ub), WebSocketPeer.WRITE_MODE_BINARY)
		CM.EMSG_NONAUTHED, CM.EMSG_SERVICE_CALL:
			var res := 1
			var out := PackedByteArray()
			match name:
				"Authentication.BeginAuthSessionViaQR#1":
					out.append_array(CM.Pb.f_varint(1, 4242))
					out.append_array(CM.Pb.f_string(2, "https://s.team/q/1/4242"))
					out.append_array(CM.Pb.f_bytes(3, PackedByteArray([1, 2, 3])))
					var fb := PackedByteArray()
					fb.resize(4)
					fb.encode_float(0, 2.5)
					out.append_array(CM.Pb.f_fixed32(4, fb.decode_u32(0)))
				"Authentication.PollAuthSessionStatus#1":
					polls += 1
					if polls >= 2:
						out.append_array(CM.Pb.f_string(3, _jwt(["client", "web", "renew", "derive"])))
						out.append_array(CM.Pb.f_string(4, _jwt(["web"], 600)))
						out.append_array(CM.Pb.f_string(6, "tester"))
				"Authentication.GenerateAccessTokenForApp#1":
					out.append_array(CM.Pb.f_string(1, _jwt(["web"], 3600)))
				"Player.GetOwnedGames#1":
					for g in [[367520, "Hollow Knight", 2220, 1700000000], [1245620, "ELDEN RING", 12720, 0]]:
						var gb := CM.Pb.f_varint(1, g[0])
						gb.append_array(CM.Pb.f_string(2, g[1]))
						gb.append_array(CM.Pb.f_varint(4, g[2]))
						if int(g[3]) > 0:
							gb.append_array(CM.Pb.f_varint(11, g[3]))
						out.append_array(CM.Pb.f_msg(2, gb))
					out.append_array(CM.Pb.f_varint(1, 2))
				"Player.GetAchievementsProgress#1":
					for raw_app in body.get(3, []):
						var pe := CM.Pb.f_varint(1, int(raw_app))
						pe.append_array(CM.Pb.f_varint(2, 5 if int(raw_app) == 367520 else 0))
						pe.append_array(CM.Pb.f_varint(3, 10 if int(raw_app) == 367520 else 42))
						pe.append_array(CM.Pb.f_varint(5, 1 if int(raw_app) == 1245620 else 0))
						out.append_array(CM.Pb.f_msg(1, pe))
				"Player.GetPlayerLinkDetails#1":
					for raw_id in body.get(1, []):
						var l: Dictionary = links.get(str(raw_id), {})
						if l.is_empty():
							continue
						var pub := CM.Pb.f_fixed64(1, int(raw_id))
						pub.append_array(CM.Pb.f_varint(2, 3))
						pub.append_array(CM.Pb.f_string(10, str(l.name)))
						var pr := CM.Pb.f_varint(1, int(l.state))
						if int(l.get("game_id", 0)) > 0:
							pr.append_array(CM.Pb.f_fixed64(4, int(l.game_id)))
							pr.append_array(CM.Pb.f_string(8, str(l.get("game", ""))))
						var acc := CM.Pb.f_msg(1, pub)
						acc.append_array(CM.Pb.f_msg(2, pr))
						out.append_array(CM.Pb.f_msg(1, acc))
				"FriendMessages.GetRecentMessages#1":
					var mb := CM.Pb.f_varint(1, int(CM.Pb.first(body, 2, 0)) - CM.STEAM64)
					mb.append_array(CM.Pb.f_varint(2, 1760000100))
					mb.append_array(CM.Pb.f_string(3, "Über den Chat-Server"))
					out.append_array(CM.Pb.f_msg(1, mb))
				"FriendMessages.SendMessage#1":
					if CM.Pb.text(body, 3) == "zu schnell":
						res = 84
					else:
						out.append_array(CM.Pb.f_string(1, "Hallo"))
						out.append_array(CM.Pb.f_varint(2, int(Time.get_unix_time_from_system())))
				_:
					res = 9
			var h2 := PackedByteArray()
			h2.append_array(CM.Pb.f_fixed64(11, int(CM.Pb.first(head, 10, 0))))
			h2.append_array(CM.Pb.f_varint(13, res))
			ws.send(_frame(CM.EMSG_SERVICE_RESPONSE, h2, out), WebSocketPeer.WRITE_MODE_BINARY)


func _jwt(aud: Array, ttl := 86400 * 180) -> String:
	var claims := { "iss": "steam", "sub": str(ME), "aud": aud, "exp": int(Time.get_unix_time_from_system()) + ttl }
	var mid := Marshalls.utf8_to_base64(JSON.stringify(claims)).replace("+", "-").replace("/", "_").replace("=", "")
	return "eyJhbGciOiJFZERTQSJ9." + mid + ".c2ln"


func _sent(emsg: int, name := "") -> Array:
	return seen.filter(func(m): return int(m.emsg) == emsg and (name == "" or str(m.name) == name))


## Wie Steam: eine Dienst-Benachrichtigung an den Client (EMsg ServiceMethod, Name im Kopf),
## auf Wunsch gepackt in einer Sammelnachricht (Multi, gzip).
func _push(method: String, body: PackedByteArray, multi := false) -> void:
	var h := PackedByteArray()
	h.append_array(CM.Pb.f_fixed64(1, ME))
	h.append_array(CM.Pb.f_varint(2, 1234))
	h.append_array(CM.Pb.f_string(12, method))
	var frame := _frame(CM.EMSG_SERVICE_METHOD, h, body)
	if multi:
		var data := PackedByteArray()
		data.resize(4)
		data.encode_u32(0, frame.size())
		data.append_array(frame)
		var mb := PackedByteArray()
		mb.append_array(CM.Pb.f_varint(1, data.size()))
		mb.append_array(CM.Pb.f_bytes(2, data.compress(FileAccess.COMPRESSION_GZIP)))
		frame = _frame(CM.EMSG_MULTI, CM.Pb.f_fixed64(1, 0), mb)
	for i in range(peers.size() - 1, -1, -1):
		if peers[i].get_ready_state() == WebSocketPeer.STATE_OPEN:
			peers[i].send(frame, WebSocketPeer.WRITE_MODE_BINARY)
			return


## CFriendMessages_IncomingMessage_Notification
func _incoming(kind: int, text: String, at: int, ordinal: int, echo := false) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(CM.Pb.f_fixed64(1, int(FRIEND)))
	b.append_array(CM.Pb.f_varint(2, kind))
	if text != "":
		b.append_array(CM.Pb.f_string(4, text))
	if at > 0:
		b.append_array(CM.Pb.f_fixed32(5, at))
	b.append_array(CM.Pb.f_varint(6, ordinal))
	if echo:
		b.append_array(CM.Pb.f_varint(7, 1))
	if text != "":
		b.append_array(CM.Pb.f_string(8, text))
	return b


## CMsgClientPersonaState wie von Steam: status_flags, je Freund nur die Felder, die es gibt.
func _persona_body(list: Array, flags := CM.PERSONA_FLAGS) -> PackedByteArray:
	var b := CM.Pb.f_varint(1, flags)
	for p in list:
		var f := CM.Pb.f_fixed64(1, int(p.id))
		if p.has("state"):
			f.append_array(CM.Pb.f_varint(2, int(p.state)))
		if int(p.get("app", 0)) > 0:
			f.append_array(CM.Pb.f_varint(3, int(p.app)))
		if p.has("ip"):
			f.append_array(CM.Pb.f_varint(4, int(p.ip)))
			f.append_array(CM.Pb.f_varint(5, int(p.port)))
		if p.has("name"):
			f.append_array(CM.Pb.f_string(15, str(p.name)))
		if p.has("avatar"):
			f.append_array(CM.Pb.f_bytes(31, p.avatar))
		if p.has("last"):
			f.append_array(CM.Pb.f_varint(45, int(p.last)))
		if p.has("game_name"):
			f.append_array(CM.Pb.f_string(55, str(p.game_name)))
		if p.has("gameid"):
			f.append_array(CM.Pb.f_fixed64(56, int(p.gameid)))
		elif int(p.get("app", 0)) > 0:
			f.append_array(CM.Pb.f_fixed64(56, int(p.app)))
		b.append_array(CM.Pb.f_msg(2, f))
	return b


## Name des gemeldeten Spiels aus einer ClientGamesPlayed-Nachricht ("" = keins).
func _game_of(m: Dictionary) -> String:
	var g: Variant = CM.Pb.first(m.body, 1, PackedByteArray())
	if not (g is PackedByteArray) or (g as PackedByteArray).is_empty():
		return ""
	return CM.Pb.text(CM.Pb.decode(g), 7)


## Eine beliebige Nachricht von Steam an Uzai (ohne Dienstnamen).
func _push_emsg(emsg: int, body: PackedByteArray) -> void:
	var h := PackedByteArray()
	h.append_array(CM.Pb.f_fixed64(1, ME))
	h.append_array(CM.Pb.f_varint(2, 1234))
	for i in range(peers.size() - 1, -1, -1):
		if peers[i].get_ready_state() == WebSocketPeer.STATE_OPEN:
			peers[i].send(_frame(emsg, h, body), WebSocketPeer.WRITE_MODE_BINARY)
			return


func _until(cond: Callable, ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while not bool(cond.call()) and Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Ablauf --------------------------------------------------------------------------------------

func _run() -> void:
	print("Protobuf-Baukasten")
	var big := CM.Pb.f_fixed64(1, int(FRIEND))
	big.append_array(CM.Pb.f_varint(2, 300))
	big.append_array(CM.Pb.f_varint(3, 1 << 40))
	big.append_array(CM.Pb.f_string(4, "Grüße 🎮"))
	big.append_array(CM.Pb.f_msg(5, CM.Pb.f_fixed32(1, 0xDEADBEEF)))
	var d := CM.Pb.decode(big)
	check(int(CM.Pb.first(d, 1, 0)) == int(FRIEND), "Steam-ID als fixed64 hin und zurück")
	check(int(CM.Pb.first(d, 2, 0)) == 300 and int(CM.Pb.first(d, 3, 0)) == 1 << 40, "varint klein und groß")
	check(CM.Pb.text(d, 4) == "Grüße 🎮", "Text mit Umlauten und Emoji")
	check(int(CM.Pb.first(CM.Pb.decode(CM.Pb.first(d, 5, PackedByteArray())), 1, 0)) == 0xDEADBEEF, "eingebettete Nachricht mit fixed32")
	check(CM.Pb.varint(150) == PackedByteArray([0x96, 0x01]), "varint 150 = 96 01 (wie protobuf)")
	check(CM.Pb.decode(PackedByteArray([0x08, 0xFF])).is_empty() or true, "abgeschnittene Nachricht stürzt nicht ab")

	print("„Spielt Nicht-Steam-Spiel“ (ClientGamesPlayed)")
	var gp := CM.games_played_body("Zelda")
	var gp_want := PackedByteArray([0x0A, 0x10, 0x11, 0x00, 0x00, 0x00, 0x02, 0xCB, 0x31, 0xCF, 0xD2, 0x3A, 0x05])
	gp_want.append_array("Zelda".to_utf8_buffer())
	gp_want.append_array(PackedByteArray([0x10, 0x14]))
	check(gp == gp_want,
			"Bytes: games_played{game_id fixed64 = 15190414816125648896, game_extra_info}, client_os_type 20 wie bei der Anmeldung (%s)" % gp.hex_encode())
	var gd := CM.Pb.decode(CM.Pb.first(CM.Pb.decode(gp), 1, PackedByteArray()))
	var gid := PackedByteArray()
	gid.resize(8)
	gid.encode_s64(0, int(CM.Pb.first(gd, 2, 0)))
	check(gid.decode_u32(4) == 0xD2CF31CB and gid.decode_u32(0) == 0x02000000 and CM.Pb.text(gd, 7) == "Zelda",
			"Spiel-ID wie steam-user (0xD2CF31CB_02000000) und Name")
	check(CM.games_played_body("") == PackedByteArray([0x10, 0x14]), "leer: keine Spiele, nur client_os_type (spielt nichts)")
	check(CM.needs_raise(false, 0, false) and CM.needs_raise(false, -1, false), "Status offline/unbekannt, Steam am PC zu: für das Spiel „online“ melden")
	check(not CM.needs_raise(true, 1, false) and not CM.needs_raise(false, 0, true) and not CM.needs_raise(false, 7, false),
			"nicht bei sichtbarem Status, nicht wenn Steam am PC angemeldet ist, nie bei „unsichtbar“")

	print("Hinweis zum Spielstatus")
	Config.set_value("steam.status_nonsteam", true)
	var gs0: Dictionary = SteamChat.game_status()
	check(not bool(gs0.ok) and bool(gs0.login) and str(gs0.short) == "Nicht aktiv" and str(gs0.text).contains("anmelden"),
			"ohne Steam-Anmeldung: „Nicht aktiv: erst in Uzai bei Steam anmelden“")
	Launcher._steam_hint_shown = false
	Launcher.current = { "id": "t-ygo", "source": "rom", "title": "Yu-Gi-Oh! Forbidden Memories" }
	Launcher._steam_status(true)
	check(Launcher._steam_hint_shown and SteamCM.games_name == "Yu-Gi-Oh! Forbidden Memories", "Spielstart ohne Anmeldung: einmal ein leiser Hinweis")
	Launcher._steam_status(false)
	Launcher.current = {}
	Config.set_value("steam.status_nonsteam", false)
	check(str(SteamChat.game_status().short) == "Aus", "Einstellung aus: „Aus“")
	Config.set_value("steam.status_nonsteam", true)

	print("QR-Anmeldung als Steam-App")
	var info: Dictionary = await SteamChat.login_start()
	check(bool(info.get("ok", false)) and bool(info.get("cm", false)), "QR-Code kommt über den Chat-Server (%s)" % str(info.get("error", "")))
	check(str(info.get("url", "")) == "https://s.team/q/1/4242", "QR-Adresse übernommen")
	check(int(info.get("client_id", 0)) == 4242 and info.get("request_id") == PackedByteArray([1, 2, 3]), "client_id und request_id")
	check(absf(float(info.get("interval", 0.0)) - 2.5) < 0.01, "Abfrage-Takt aus dem float-Feld (%s)" % str(info.get("interval")))
	var hello := _sent(CM.EMSG_HELLO)
	check(hello.size() == 1 and int(CM.Pb.first(hello[0].body, 1, 0)) == CM.PROTOCOL_VERSION, "erst Hallo mit Protokollversion")
	var qr := _sent(CM.EMSG_NONAUTHED, "Authentication.BeginAuthSessionViaQR#1")
	if not qr.is_empty():
		var dd := CM.Pb.decode(CM.Pb.first(qr[0].body, 3, PackedByteArray()))
		check(int(CM.Pb.first(dd, 2, 0)) == 1, "Gerät meldet sich als Steam-App (platform_type 1)")
		check(CM.Pb.text(dd, 1) == "Uzai", "Gerätename Uzai")
		check(int(CM.Pb.first(qr[0].head, 32, 0)) == 1 and int(CM.Pb.first(qr[0].head, 1, -1)) == 0, "Kopf: realm 1, ohne Steam-ID")
	if bool(info.get("ok", false)):
		check(await SteamChat.login_poll(info) == "pending", "erste Abfrage: wartet auf Bestätigung")
		check(await SteamChat.login_poll(info) == "ok", "zweite Abfrage: angemeldet")
	check(SteamChat.can_send(), "Anmeldung darf senden (Zielgruppe client)")
	check(str(Config.get_value("accounts.steam_chat_name", "")) == "tester", "Kontoname gemerkt")

	print("Nachricht senden")
	var err: String = await SteamChat.send(FRIEND, "Hallo über den Chat-Server")
	check(err == "", "Nachricht angekommen (%s)" % err)
	var logons := _sent(CM.EMSG_LOGON)
	check(logons.size() == 1, "genau eine Anmeldung am Chat-Server (%d)" % logons.size())
	if not logons.is_empty():
		var lb: Dictionary = logons[0].body
		check(CM.Pb.text(lb, 108) == str(Config.get_value("accounts.steam_chat_refresh", "")), "Anmeldung mit dem Zugang der QR-Anmeldung")
		check(int(CM.Pb.first(lb, 1, 0)) == CM.PROTOCOL_VERSION and CM.Pb.text(lb, 96) == "Uzai", "Protokollversion und Gerätename")
		check(lb.has(11), "eigene Sitzungsnummer (die Steam-App am PC bleibt angemeldet)")
		check(int(CM.Pb.first(logons[0].head, 1, 0)) == ME, "Kopf: eigene Steam-ID aus dem Zugang (sonst lehnt Steam ab)")
		check(int(CM.Pb.first(lb, 5, 0)) == 1771 and int(CM.Pb.first(lb, 21, 0)) == 2, "Paketversion und QoS wie steam-user")
	var sends := _sent(CM.EMSG_SERVICE_CALL, "FriendMessages.SendMessage#1")
	check(sends.size() == 1, "eine Sende-Anfrage")
	if not sends.is_empty():
		var sb: Dictionary = sends[0].body
		check(str(int(CM.Pb.first(sb, 1, 0))) == FRIEND, "an den richtigen Freund")
		check(int(CM.Pb.first(sb, 2, 0)) == 1 and CM.Pb.text(sb, 3) == "Hallo über den Chat-Server", "Text als normale Nachricht")
		check(int(CM.Pb.first(sends[0].head, 1, 0)) == ME and int(CM.Pb.first(sends[0].head, 2, 0)) == 1234,
				"Kopf: eigene Steam-ID und Sitzung aus der Anmeldung (über Multi/gzip)")
	check(SteamCM.state == "angemeldet", "Verbindung bleibt offen")

	var err2: String = await SteamChat.send(FRIEND, "Noch eine")
	check(err2 == "" and _sent(CM.EMSG_LOGON).size() == 1, "zweite Nachricht ohne neue Anmeldung")
	var errs: Array = []
	var a := func() -> void: errs.append(await SteamChat.send(FRIEND, "parallel 1"))
	var b := func() -> void: errs.append(await SteamChat.send(FRIEND, "parallel 2"))
	a.call()
	b.call()
	var until := Time.get_ticks_msec() + 5000
	while errs.size() < 2 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(errs == ["", ""], "zwei Nachrichten gleichzeitig kommen beide an")

	var err3: String = await SteamChat.send(FRIEND, "zu schnell")
	check(err3.contains("Zu viele"), "Steam bremst (84): verständlicher Hinweis (%s)" % err3)

	print("Verbindung weg, Anmeldung abgelehnt, alte Anmeldung")
	for ws in peers:
		ws.close()
	until = Time.get_ticks_msec() + 3000
	while SteamCM.state != "zu" and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(SteamCM.state == "zu", "Trennung bemerkt")
	var err4: String = await SteamChat.send(FRIEND, "nach der Trennung")
	check(err4 == "" and _sent(CM.EMSG_LOGON).size() == 2, "baut die Verbindung von selbst neu auf und meldet sich wieder an")
	SteamCM.close()
	logon_result = 5
	var err5: String = await SteamChat.send(FRIEND, "abgelehnt")
	check(err5.contains("abgelehnt"), "abgelehnte Anmeldung wird erklärt (%s)" % err5)
	logon_result = 1
	var n_before := seen.size()
	Config.set_value("accounts.steam_chat_refresh", _jwt(["web", "renew"]))
	var err6: String = await SteamChat.send(FRIEND, "Browser-Anmeldung")
	check(err6.contains("QR-Code") and seen.size() == n_before, "Browser-Anmeldung: Hinweis auf neue QR-Anmeldung, nichts gesendet")
	await _live()
	await _presence()
	await _link()
	await _erfolge()
	SteamChat.logout()


## QR login as a Steam app while Steam is running on the PC and the Web API rejects access (HTTP 400):
## friends, profile and history still arrive, through a short session without a status.
func _link() -> void:
	print("Freunde, Profil und Verlauf ohne Web-API (Steam am PC angemeldet)")
	SteamCM.stop_keep()
	SteamCM.close()
	push_friends = true
	links = { FRIEND: { "name": "Mira", "state": 1, "game_id": 1245620, "game": "ELDEN RING" }, FRIEND2: { "name": "Noor", "state": 0 },
		str(ME): { "name": "tester", "state": 1 } }
	SteamChat._web_bad_until = int(Time.get_unix_time_from_system()) + 3600
	# Der Chat hat einen eigenen Merker (chat_web_ok): Verlauf hier ebenfalls ohne Web-API.
	SteamChat._chat_web_bad_until = int(Time.get_unix_time_from_system()) + 3600
	SteamCM.pc_known = true
	SteamCM.pc_signed_in = true
	SteamCM.reset_rare()
	Social.steam_friends = []
	var n_logon := _sent(CM.EMSG_LOGON).size()
	var n_status := _sent(CM.EMSG_CHANGE_STATUS).size()
	var n_fd := _sent(CM.EMSG_REQUEST_FRIEND_DATA).size()
	await Social._refresh_steam()
	await _frames(3)
	check(_sent(CM.EMSG_LOGON).size() == n_logon + 1 and SteamCM.state == "zu", "eine kurze Sitzung, gleich wieder zu")
	check(_sent(CM.EMSG_CHANGE_STATUS).size() == n_status and _sent(CM.EMSG_REQUEST_FRIEND_DATA).size() == n_fd,
			"kein eigener Status, keine Status-Abfrage (Steam am PC bleibt unberührt)")
	var m := _friend(FRIEND)
	check(str(m.get("name", "")) == "Mira" and str(m.get("state", "")) == "game" and str(m.get("game", "")) == "ELDEN RING",
			"Freundesliste mit Status und Spiel (%s)" % str(m))
	check(str(_friend(FRIEND2).get("state", "")) == "offline" and Social.steam_friends.size() == 2, "zwei Freunde, keine Gruppe, nicht du selbst")
	await Social._refresh_steam()
	check(_sent(CM.EMSG_LOGON).size() == n_logon + 1 and Social.steam_friends.size() == 2, "gleich danach: keine neue Sitzung, die Liste bleibt")
	var pr: Dictionary = await Social.steam_profile(FRIEND, true)
	check(bool(pr.ok) and str(pr.error) == "" and str(pr.name) == "Mira" and int(pr.games_count) == 2 and str(pr.game) == "ELDEN RING",
			"Profil auf Knopfdruck über den Chat-Server (%s)" % str(pr.get("error", "")))
	var hist: Array = await SteamChat.history(FRIEND)
	check(hist.size() == 1 and str(hist[0].text) == "Über den Chat-Server" and not bool(hist[0].me), "Verlauf über den Chat-Server")
	var log := FileAccess.get_file_as_string(Config.path("logs/steam.log"))
	check(log.contains("Freunde: Chat-Server ok, 2 Freunde") and log.contains("Profil %s: Chat-Server EResult 1" % FRIEND)
			and log.contains("Verlauf: Chat-Server ok, 1 Nachrichten"), "steam.log: Weg, EResult und Anzahl je Abruf")
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	check(refresh != "" and not log.contains(refresh) and not log.contains(refresh.get_slice(".", 1)), "keine Zugangsdaten im Protokoll")
	# Shortly after the QR login two short sessions can run at once (friends and owned games). Two logons on
	# one connection got no answer at all (EResult -1), so both requests must share a single logon.
	SteamCM.close()
	SteamCM.reset_rare()
	SteamCM.own = {}
	var n2 := _sent(CM.EMSG_LOGON).size()
	var res := {}
	var fa := func() -> void: res["a"] = await SteamCM.player_details(refresh, [str(ME)], true)
	var fb := func() -> void: res["b"] = await SteamCM.owned_games(refresh, ME)
	fa.call()
	fb.call()
	await _until(func() -> bool: return res.size() == 2, 15000)
	check(_sent(CM.EMSG_LOGON).size() == n2 + 1, "zwei kurze Sitzungen gleichzeitig: eine Anmeldung (%d)" % (_sent(CM.EMSG_LOGON).size() - n2))
	check(res.size() == 2 and bool(res.a.ok) and (res.b as Array).size() == 2, "beide Abfragen kommen an")
	await _frames(3)
	check(SteamCM.state == "zu", "danach gleich wieder zu")
	check(int(SteamCM.own.get("state", -1)) == 1
			and FileAccess.get_file_as_string(Config.path("logs/steam.log")).contains("Freunde sehen dich: online, kein Spiel"),
			"dein Status laut Steam (ohne Web-API): online, im Protokoll")
	SteamCM.close()
	SteamCM.pc_signed_in = false
	SteamChat._web_bad_until = 0
	SteamChat._chat_web_bad_until = 0
	push_friends = false
	links = {}


## Achievements still come from Steam when the Web API rejects access and Steam is signed in on the PC:
## read locally or through the chat server (ClientGetUserStats, GetAchievementsProgress).
func _erfolge() -> void:
	print("Erfolge ohne Web-API (Steam am PC angemeldet)")
	SteamCM.close()
	SteamChat._web_bad_until = int(Time.get_unix_time_from_system()) + 3600
	SteamCM.pc_known = true
	SteamCM.pc_signed_in = true
	SteamCM.reset_rare()
	# Steams Ordner wie am PC (nur das Schema von Spacewar, keine Datei für dieses Konto);
	# api.steampowered.com (Seltenheit) zeigt ins Leere.
	var keep_root: String = Library._steam_root
	Library._steam_root = ProjectSettings.globalize_path("res://tests/fixtures/steam_pc")
	OS.set_environment("UZAI_STEAM_API", "https://127.0.0.1:9")
	var refresh := str(Config.get_value("accounts.steam_chat_refresh", ""))
	check(not Achievements.steam_web_ok(), "Web-API abgelehnt: Erfolge ohne sie")
	var n_logon := _sent(CM.EMSG_LOGON).size()
	var res: Dictionary = await Achievements.steam_game(480, "Spacewar", true)
	check(not res.has("error") and int(res.get("total", 0)) == 4 and int(res.get("unlocked", 0)) == 2 and str(res.get("via", "")) == "Chat-Server",
			"Liste eines Spiels: Schema lokal, Stand vom Chat-Server (%s)" % str(res.get("error", res.get("unlocked", ""))))
	check(_sent(CM.EMSG_GET_USER_STATS).size() >= 1 and _sent(CM.EMSG_LOGON).size() == n_logon + 1, "eine Sitzung auf Knopfdruck")
	var titles: Array = (res.get("list", []) as Array).filter(func(a): return bool(a.unlocked)).map(func(a): return str(a.title))
	check("Sieger" in titles and "Weit gereist" in titles, "deutsche Namen (%s)" % str(titles))
	var r2: Dictionary = await SteamCM.user_stats(refresh, [[480, FRIEND], [480, FRIEND2]], true)
	check((r2.results as Dictionary).size() == 2, "Freunde: je eine Antwort")
	var f1 := SE_.friend_result(SE_.parse_user_stats(r2.results["480:%s" % FRIEND]))
	var f2 := SE_.friend_result(SE_.parse_user_stats(r2.results["480:%s" % FRIEND2]))
	check(bool(f1.ok) and f1.got.has("ACH_WIN_100_GAMES") and str(f2.reason) == "Profil privat", "Vergleich: Mira 1 frei, Noor privat")
	SteamCM.close()
	SteamCM.reset_rare()
	var pg: Dictionary = await SteamCM.achievements_progress(refresh, ME, [367520, 1245620])
	check(bool(pg.ok) and pg.counts[367520] == { "u": 5, "t": 10 } and pg.counts[1245620] == { "u": 42, "t": 42 }, "Stand je Spiel über den Chat-Server")
	await _frames(3)
	check(SteamCM.state == "zu", "kurze Sitzung, gleich wieder zu")
	var again: Dictionary = await SteamCM.achievements_progress(refresh, ME, [367520])
	check(not bool(again.ok) and _sent(CM.EMSG_LOGON).size() == n_logon + 2, "automatisch gleich danach: keine neue Sitzung")
	var log := FileAccess.get_file_as_string(Config.path("logs/steam.log"))
	check(log.contains("Erfolge „Spacewar“: Web-API abgelehnt → Chat-Server, 4 Erfolge, 2 frei")
			and log.contains("ClientGetUserStats): 2 von 2 beantwortet"), "steam.log: Weg und Anzahl")
	OS.set_environment("UZAI_STEAM_API", "")
	Library._steam_root = keep_root
	SteamCM.close()
	SteamCM.pc_signed_in = false
	SteamChat._web_bad_until = 0


func _friend(id: String) -> Dictionary:
	return Social.steam_friend(id)


func _presence() -> void:
	print("Status der Freunde über den Chat-Server (ClientPersonaState)")
	var sc := PackedByteArray()
	sc.resize(8)
	sc.encode_u32(0, CM.NONSTEAM_LO)
	sc.encode_u32(4, CM.NONSTEAM_HI)
	check(InstallParse.u64_text(sc.decode_s64(0)) == "15190414816125648896" and InstallParse.u64_text(-1) == "18446744073709551615"
			and InstallParse.u64_text(570) == "570",
			"Spiel-IDs ohne Vorzeichen (Verknüpfung 0xD2CF31CB_02000000)")
	check(CM.avatar_url(PackedByteArray()) == "" and CM.avatar_url(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == "",
			"ohne Profilbild: Standardbild")
	check(Social.web_secs(false, false) <= 60.0 and Social.web_secs(false, false) >= 30.0 and Social.web_secs(true, false) >= 120.0,
			"Web-API im Menü alle 30–60 s, im Spiel sparsam (%d s / %d s)" % [int(Social.web_secs(false, false)), int(Social.web_secs(true, false))])
	check(Social.web_secs(false, true) > Social.web_secs(false, false) and Social.cm_secs(false) <= 60.0 and Social.cm_secs(true) > Social.cm_secs(false),
			"mit Chat-Server: Web-API seltener, Status-Abfrage im Menü jede Minute")
	Social.steam_friends = [
			{ "id": FRIEND, "name": "Mira", "avatar": "", "state": "offline", "game": "", "game_id": "", "last": 100, "lobby": "", "server": "", "since": 0 }]
	Social._cm.clear()
	Social._steam_sig = ""
	var ups: Array = []
	var on_up := func(w: String) -> void: ups.append(w)
	Social.updated.connect(on_up)
	var hash := PackedByteArray()
	for i in 20:
		hash.append(0xAB)
	personas = {
		FRIEND: { "state": 1, "name": "Mira", "avatar": hash },
		FRIEND2: { "state": 1, "name": "Noor", "app": 1145360 },
		CLAN: { "state": 1, "name": "Gruppe" },
	}
	push_friends = true
	logon_result = 1
	Config.set_value("notify.steam", true)
	await _until(func() -> bool: return SteamCM.live, 6000)
	# Neu anmelden: Steam schickt dabei die Freundesliste.
	var n_req := _sent(CM.EMSG_REQUEST_FRIEND_DATA).size()
	for ws in peers:
		ws.close()
	await _until(func() -> bool: return not SteamCM.live, 3000)
	SteamCM._retry_at = Time.get_ticks_msec()
	# Großzügig warten: unter Last (mehrere Tests gleichzeitig) dauert die Neuanmeldung länger.
	await _until(func() -> bool: return SteamCM.live and SteamCM.friend_ids.has(FRIEND2), 12000)
	await _until(func() -> bool: return str(_friend(FRIEND).get("state", "")) == "online" and not _friend(FRIEND2).is_empty(), 8000)
	check(SteamCM.live and SteamCM.friend_ids.has(FRIEND) and SteamCM.friend_ids.has(FRIEND2) and not SteamCM.friend_ids.has(CLAN),
			"Freundesliste von Steam nach der Anmeldung (ohne Gruppen)")
	var reqs := _sent(CM.EMSG_REQUEST_FRIEND_DATA).slice(n_req)
	var asked := {}
	for r in reqs:
		for id in r.body.get(2, []):
			asked[str(id)] = true
	check(not reqs.is_empty() and int(CM.Pb.first(reqs[0].body, 1, 0)) == CM.PERSONA_FLAGS and asked.has(FRIEND) and asked.has(FRIEND2) and not asked.has(CLAN),
			"Status, Name und Spiel der Freunde abgefragt (ClientRequestFriendData, %d Anfragen)" % reqs.size())
	if not reqs.is_empty():
		check(int(CM.Pb.first(reqs[0].head, 1, 0)) == ME and int(CM.Pb.first(reqs[0].head, 2, 0)) == 1234, "Kopf mit eigener Steam-ID und Sitzung")
	var mira := _friend(FRIEND)
	check(str(mira.get("state", "")) == "online", "Mira war laut Web-API offline, ist online: sofort „online“ (%s)" % str(mira.get("state", "")))
	check(str(mira.get("avatar", "")) == "https://avatars.steamstatic.com/%s_full.jpg" % "ab".repeat(20), "Profilbild aus dem Hash")
	var noor := _friend(FRIEND2)
	check(str(noor.get("name", "")) == "Noor" and str(noor.get("state", "")) == "game" and str(noor.get("game_id", "")) == "1145360",
			"neue Freundin aus der Freundesliste, spielt (App 1145360)")
	check(str(noor.get("game", "")) != "", "Spielname aus der Bibliothek oder vorläufig „%s“ (%s)" % [Social.GAME_UNKNOWN, str(noor.get("game", ""))])
	Social._names_due = false
	check(str(Social.steam_friends[0].get("id", "")) == FRIEND2, "wer spielt, steht oben")
	check(ups.has("steam"), "Freunde-Bereich, Guide und Zähler werden benachrichtigt")
	check(Social.cm_live(), "Status kommt jetzt über den Chat-Server")

	# Steam meldet von selbst: Mira startet ein Spiel, dann geht sie.
	ups.clear()
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "state": 1, "app": 570, "game_name": "Dota 2", "ip": 0x0A000001, "port": 27015 }]))
	await _until(func() -> bool: return str(_friend(FRIEND).get("state", "")) == "game", 3000)
	mira = _friend(FRIEND)
	check(str(mira.get("game", "")) == "Dota 2" and str(mira.get("game_id", "")) == "570" and str(mira.get("server", "")) == "10.0.0.1:27015",
			"Mira spielt Dota 2 (sofort, mit Server)")
	await _frames(2)
	check(ups.size() == 1, "eine Meldung je Änderung (%d)" % ups.size())
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "state": 1, "app": 570, "game_name": "Dota 2", "ip": 0x0A000001, "port": 27015 }]))
	await _frames(6)
	check(ups.size() == 1, "dieselbe Meldung nochmal: nichts neu aufgebaut")
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "name": "Mira K." }], 2))
	await _until(func() -> bool: return str(_friend(FRIEND).get("name", "")) == "Mira K.", 3000)
	check(str(_friend(FRIEND).get("name", "")) == "Mira K." and str(_friend(FRIEND).get("state", "")) == "game", "nur der Name geändert: Status und Spiel bleiben")
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "state": 0, "last": 1760000100 }]))
	await _until(func() -> bool: return str(_friend(FRIEND).get("state", "")) == "offline", 3000)
	mira = _friend(FRIEND)
	check(str(mira.get("state", "")) == "offline" and str(mira.get("game", "")) == "" and int(mira.get("last", 0)) == 1760000100,
			"Mira geht: offline, kein Spiel, zuletzt online")
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "state": 3 }]))
	await _until(func() -> bool: return str(_friend(FRIEND).get("state", "")) == "away", 3000)
	check(str(_friend(FRIEND).get("state", "")) == "away", "kommt wieder (abwesend)")
	var n_f := Social.steam_friends.size()
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": "76561198000099999", "state": 1, "name": "Fremd" }, { "id": str(ME), "state": 1, "name": "Ich" }]))
	await _frames(8)
	check(Social.steam_friends.size() == n_f, "Leute ohne Freundschaft und du selbst kommen nicht in die Liste")

	# Die Web-API hinkt hinterher: frischer Status vom Chat-Server geht vor.
	var web := [{ "id": FRIEND, "name": "Mira K.", "avatar": "", "state": "offline", "game": "", "game_id": "", "last": 0, "lobby": "", "server": "", "since": 0 },
		{ "id": FRIEND2, "name": "Noor", "avatar": "", "state": "game", "game": "Hades", "game_id": "1145360", "last": 0, "lobby": "1097", "server": "", "since": 0 }]
	var merged := Social.merge_web(web, Social._cm, {}, Time.get_ticks_msec())
	check(str(merged[0].state) == "away", "Web-API sagt noch „offline“, Chat-Server „abwesend“: abwesend")
	check(str(merged[1].game) == "Hades" and str(merged[1].lobby) == "1097" and str(merged[1].state) == "game", "gleiches Spiel: Name und Lobby aus der Web-API")
	var old := [{ "id": FRIEND, "state": "offline", "game": "", "game_id": "" }]
	check(str(Social.merge_web(old, Social._cm, {}, Time.get_ticks_msec() + Social.CM_KEEP_MS + 1000)[0].state) == "offline",
			"älter als %d s: die Web-API gilt" % int(Social.CM_KEEP_MS / 1000.0))
	old = [{ "id": FRIEND, "state": "offline", "game": "", "game_id": "" }]
	check(str(Social.merge_web(old, Social._cm, { FRIEND: true }, Time.get_ticks_msec() + Social.CM_KEEP_MS + 1000)[0].state) == "away",
			"privates Profil (Web-API immer „offline“): der Chat-Server gilt")

	# Regelmäßig neu abfragen (falls Steam Änderungen nicht von selbst schickt).
	n_req = _sent(CM.EMSG_REQUEST_FRIEND_DATA).size()
	personas[FRIEND] = { "state": 1, "name": "Mira K." }
	Social._cm_req_at = Time.get_ticks_msec() - 61000
	Social._web_at = Time.get_ticks_msec()
	Social._tick()
	await _until(func() -> bool: return str(_friend(FRIEND).get("state", "")) == "online", 3000)
	check(_sent(CM.EMSG_REQUEST_FRIEND_DATA).size() == n_req + 1 and str(_friend(FRIEND).get("state", "")) == "online",
			"nach einer Minute: Status neu abgefragt, Mira online")
	Social._tick()
	await _frames(4)
	check(_sent(CM.EMSG_REQUEST_FRIEND_DATA).size() == n_req + 1, "nicht öfter als nötig")

	# Fehler 36: Neben Steam am PC hat Uzais Sitzung keinen eigenen Status (nur kurz zum Schreiben
	# offen). Was Steam ihr über Freunde meldet, stimmt nicht – beim Nutzer kurz danach alle offline.
	print("Sitzung ohne eigenen Status (Steam am PC angemeldet, Fehler 36)")
	var keep_set := SteamCM.status_set
	check(SteamCM.sees_presence(), "mit eigenem Status sieht die Sitzung den Status der Freunde")
	SteamCM.status_set = false
	check(not SteamCM.sees_presence(), "ohne eigenen Status nicht")
	n_req = _sent(CM.EMSG_REQUEST_FRIEND_DATA).size()
	check(SteamCM.request_friend_data([FRIEND, FRIEND2], true) == 0, "keine Status-Abfrage über diese Sitzung")
	Social._cm_req_at = Time.get_ticks_msec() - 61000
	Social._web_at = Time.get_ticks_msec()
	Social._tick()
	await _frames(4)
	check(_sent(CM.EMSG_REQUEST_FRIEND_DATA).size() == n_req, "auch nicht nach einer Minute (Social)")
	var pa := SteamCM.persona_at
	var cm_at := int((Social._cm.get(FRIEND, {}) as Dictionary).get("at", 0))
	_push_emsg(CM.EMSG_PERSONA_STATE, _persona_body([{ "id": FRIEND, "state": 0, "name": "Mira Neu" }, { "id": FRIEND2, "state": 0 }]))
	await _until(func() -> bool: return str(_friend(FRIEND).get("name", "")) == "Mira Neu", 3000)
	check(str(_friend(FRIEND).get("name", "")) == "Mira Neu", "Name wird trotzdem übernommen")
	check(str(_friend(FRIEND).get("state", "")) == "online" and str(_friend(FRIEND2).get("state", "")) == "game",
			"Steam meldet alle „offline“: Status bleibt, wie er war")
	check(SteamCM.persona_at == pa and int((Social._cm.get(FRIEND, {}) as Dictionary).get("at", 0)) == cm_at,
			"zählt nicht als frischer Status (die Web-API bleibt maßgeblich)")
	var stripped: Array = CM.without_status(
			[{ "id": FRIEND, "status": true, "state": 0, "app_id": 570, "game_id": "570", "game_name": "Dota 2", "server": "1.2.3.4:5", "name": "Mira",
			"last_logoff": 7 }])
	check(stripped.size() == 1 and not bool(stripped[0].status) and not stripped[0].has("state") and not stripped[0].has("game_id")
			and str(stripped[0].name) == "Mira" and int(stripped[0].last_logoff) == 7, "ohne Status: nur Name, Bild und „zuletzt online“")
	SteamCM.status_set = keep_set
	check(SteamChat.chat_poll_secs(true, true) > float(CM.IDLE_CLOSE_PC) * 2.0,
			"offener Chat neben Steam am PC: seltener nachsehen, die Sitzung schließt dazwischen (%d s)" % int(SteamChat.chat_poll_secs(true, true)))
	check(SteamChat.chat_poll_secs(false, true) <= 5.0 and SteamChat.chat_poll_secs(true, false) <= 5.0,
			"mit Dauerverbindung oder ohne Steam am PC: weiter alle 4 s")
	check(not SteamChat.history_needs_session() and SteamChat.chat_poll() <= 5.0, "Dauerverbindung steht: Chat fragt im alten Takt")
	Social.updated.disconnect(on_up)
	push_friends = false
	personas = {}
	Config.set_value("notify.steam", false)


func _live() -> void:
	print("Dauerverbindung für Mitteilungen")
	SteamCM.close()
	logon_result = 1
	Config.set_value("accounts.steam_chat_refresh", _jwt(["client", "web", "renew", "derive"]))
	Config.set_value("accounts.steam_chat_id", str(ME))
	Social.steam_friends = [{ "id": FRIEND, "name": "Mira", "avatar": "" }]
	var n_logon := _sent(CM.EMSG_LOGON).size()
	SteamCM.persona_state = 0
	SteamCM.pc_signed_in = false
	# Helfer hat (noch) nicht geantwortet: unbekannt heißt „kein Status von Uzai“.
	check(not CM.needs_raise(false, 0, SteamCM.pc_signed_in or not false), "Steam am PC unbekannt: Uzai meldet keinen Status")
	SteamCM.pc_known = true
	SteamCM.set_games_played("Super Mario 64")
	check(_sent(CM.EMSG_GAMES_PLAYED).is_empty(), "Spielname ohne Dauerverbindung: wartet, nichts gesendet")
	Config.set_value("notify.steam", true)
	await _until(func() -> bool: return SteamCM.live, 6000)
	check(SteamCM.live and _sent(CM.EMSG_LOGON).size() == n_logon + 1, "mit Steam-App-Anmeldung: Verbindung steht dauerhaft")
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() >= 1, 2000)
	var gps := _sent(CM.EMSG_GAMES_PLAYED)
	check(gps.size() == 1 and _game_of(gps[0]) == "Super Mario 64", "sobald die Verbindung steht: „Spielt Super Mario 64“ gemeldet (EMsg 5410)")
	if not gps.is_empty():
		check(int(CM.Pb.first(gps[0].head, 1, 0)) == ME and int(CM.Pb.first(gps[0].body, 2, 0)) == CM.OS_TYPE, "Kopf mit eigener Steam-ID, client_os_type 20")
	# Steam am PC zu, Status offline: ohne sichtbaren Status sähen Freunde nichts (steam-user:
	# erst setPersona(Online), dann gamesPlayed).
	var cs := _sent(CM.EMSG_CHANGE_STATUS)
	check(cs.size() == 1 and int(CM.Pb.first(cs[0].body, 1, -1)) == CM.PERSONA_ONLINE and int(CM.Pb.first(cs[0].body, 5, -1)) == 0,
			"Steam am PC zu: für das Spiel „online“ gemeldet (nicht vom Nutzer gewählt)")
	check(seen.find(cs[0] if not cs.is_empty() else {}) < seen.find(gps[0] if not gps.is_empty() else {}), "erst der Status, dann das Spiel")
	check(str(SteamChat.game_status().short) == "Aktiv" and str(SteamChat.game_status().text).contains("Super Mario 64"),
			"Einstellungen: „Aktiv: Freunde sehen … Super Mario 64“")
	SteamCM.set_persona(1)
	check(SteamCM.persona_state == 0, "das eigene „online“ aus der Web-API zählt nicht als dein Status")
	SteamCM.set_games_played("")
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() >= 2, 2000)
	gps = _sent(CM.EMSG_GAMES_PLAYED)
	check(gps.size() == 2 and _game_of(gps[1]) == "" and not (gps[1].body as Dictionary).has(1), "Spiel beendet: leere Liste gesendet")
	cs = _sent(CM.EMSG_CHANGE_STATUS)
	check(cs.size() == 2 and int(CM.Pb.first(cs[1].body, 1, -1)) == CM.PERSONA_OFFLINE, "Spiel beendet: wieder „offline“ wie vorher")
	SteamCM.set_games_played("")
	await _frames(4)
	check(_sent(CM.EMSG_GAMES_PLAYED).size() == 2 and _sent(CM.EMSG_CHANGE_STATUS).size() == 2, "nichts Neues: nicht nochmal gesendet")
	SteamCM.set_persona(1)
	check(SteamCM.persona_state == 0, "kurz nach dem Spiel zeigt die Web-API noch Uzais „online“: bleibt unbeachtet")
	SteamCM.pc_signed_in = true
	SteamCM.set_games_played("Tetris")
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() >= 3, 2000)
	check(_sent(CM.EMSG_CHANGE_STATUS).size() == 2, "Steam am PC angemeldet und dort offline/unsichtbar: Uzai ändert den Status nicht")
	check(str(SteamChat.game_status().short) == "Unsichtbar", "Einstellungen erklären es („Unsichtbar“)")
	SteamCM.set_games_played("")
	SteamCM.pc_signed_in = false
	await get_tree().create_timer(0.5).timeout
	check(_sent(CM.EMSG_CHANGE_STATUS).size() == 2 and not SteamChat.live(), "ohne Spiel und bei offline/unbekannt: kein Status (Uzai fragt dann regelmäßig nach)")
	SteamCM.set_persona(3)
	await _until(func() -> bool: return _sent(CM.EMSG_CHANGE_STATUS).size() >= 3, 2000)
	var st := _sent(CM.EMSG_CHANGE_STATUS).slice(2)
	check(st.size() == 1 and int(CM.Pb.first(st[0].body, 1, 0)) == 3 and SteamChat.live(), "Status wie in Steam (hier „abwesend“) gemeldet – nie „unsichtbar“")
	if not st.is_empty():
		check(int(CM.Pb.first(st[0].body, 4, -1)) == 0 and int(CM.Pb.first(st[0].body, 5, -1)) == 0,
				"ohne Vorrang und nicht „vom Nutzer gewählt“ (Status der Steam-App bleibt)")
		check(int(CM.Pb.first(st[0].head, 1, 0)) == ME and int(CM.Pb.first(st[0].head, 2, 0)) == 1234, "Kopf mit eigener Steam-ID und Sitzung")
	check(str(SteamChat.game_status().short) == "Bereit", "Einstellungen: „Bereit“")
	check(absf(SteamChat._poll.wait_time - 60.0) < 0.1, "mit Echtzeit fragt Uzai nur noch selten nach (60 s)")
	SteamCM._idle = SteamCM.IDLE_CLOSE + 1.0
	await _frames(6)
	check(SteamCM.state == "angemeldet", "trennt nicht nach 120 s Leerlauf")

	var msgs: Array = []
	var on_msg := func(fid: String) -> void: msgs.append(fid)
	SteamChat.messages.connect(on_msg)
	_push("FriendMessagesClient.IncomingMessage#1", _incoming(2, "", 0, 0))
	await _until(func() -> bool: return SteamChat.is_typing(FRIEND), 3000)
	check(SteamChat.is_typing(FRIEND), "„schreibt gerade“ kommt sofort")
	var shown0 := Notify.shown
	_push("FriendMessagesClient.IncomingMessage#1", _incoming(1, "Bist du da?", 1760000000, 0), true)
	await _until(func() -> bool: return int(SteamChat.unread.get(FRIEND, 0)) == 1, 3000)
	check(int(SteamChat.unread.get(FRIEND, 0)) == 1 and msgs.has(FRIEND), "neue Nachricht (in Multi/gzip): ungelesen +1, Signal messages")
	check(not SteamChat.is_typing(FRIEND), "„schreibt“ endet mit der Nachricht")
	check(Notify.shown == shown0 + 1, "ein Pop-up")
	if not Toasts.history.is_empty():
		var h: Dictionary = Toasts.history[0]
		check(str(h.title) == "Mira" and str(h.sub) == "Bist du da?" and str(h.icon) == "chat", "Pop-up mit Name und Text (%s / %s)" % [str(h.title), str(h.sub)])
	check(str(Notify.last.get("kind", "")) == "steam" and str((Notify.last.get("target", {}) as Dictionary).get("id", "")) == FRIEND,
			"zuletzt: Chat mit Mira (View oder Guide öffnet ihn)")
	SteamChat.incoming.emit({ "friend": FRIEND, "kind": 1, "text": "Bist du da?", "at": 1760000000, "ordinal": 0, "echo": false, "from_poll": true })
	check(Notify.shown == shown0 + 1, "dieselbe Nachricht nochmal aus der Abfrage: kein zweites Pop-up")
	msgs.clear()
	_push("FriendMessagesClient.IncomingMessage#1", _incoming(1, "Ja, gleich", 1760000005, 1, true))
	await _until(func() -> bool: return not msgs.is_empty(), 3000)
	check(not msgs.is_empty() and Notify.shown == shown0 + 1 and int(SteamChat.unread.get(FRIEND, 0)) == 1,
			"eigene Nachricht von einem anderen Gerät (Echo): Verlauf frisch, kein Pop-up")
	msgs.clear()
	SteamChat.open_chat = FRIEND
	_push("FriendMessagesClient.IncomingMessage#1", _incoming(1, "Hallo?", 1760000010, 0))
	await _until(func() -> bool: return not msgs.is_empty(), 3000)
	check(not msgs.is_empty() and Notify.shown == shown0 + 1 and int(SteamChat.unread.get(FRIEND, 0)) == 1, "Chat ist offen: kein Pop-up, nicht ungelesen")
	SteamChat.open_chat = ""
	var ack := CM.Pb.f_fixed64(1, int(FRIEND))
	ack.append_array(CM.Pb.f_fixed32(2, 1760000011))
	_push("FriendMessagesClient.NotifyAckMessageEcho#1", ack)
	await _until(func() -> bool: return not SteamChat.unread.has(FRIEND), 3000)
	check(not SteamChat.unread.has(FRIEND), "auf einem anderen Gerät gelesen: nicht mehr ungelesen")
	SteamChat.messages.disconnect(on_msg)

	print("Gekaufte Spiele ohne API-Schlüssel")
	var owned: Array = await SteamCM.owned_games(str(Config.get_value("accounts.steam_chat_refresh", "")), ME)
	check(owned.size() == 2 and int(owned[0].appid) == 367520 and str(owned[0].name) == "Hollow Knight" and int(owned[0].playtime_forever) == 2220
			and int(owned[0].rtime_last_played) == 1700000000, "Player.GetOwnedGames über den Chat-Server: App-ID, Name, Spielzeit, zuletzt (Format der Web-API)")
	var og := _sent(CM.EMSG_SERVICE_CALL, "Player.GetOwnedGames#1")
	if not og.is_empty():
		check(int(CM.Pb.first(og[-1].body, 1, 0)) == ME and int(CM.Pb.first(og[-1].body, 2, 0)) == 1 and int(CM.Pb.first(og[-1].body, 3, 0)) == 1,
				"Anfrage: eigene Steam-ID, mit Namen und gespielten Gratisspielen")
	Config.set_value("accounts.steam_key", "")
	var via_social: Array = await Social.steam_owned_games()
	check(via_social.size() == 2 and str(via_social[1].name) == "ELDEN RING", "Social nimmt mit QR-Anmeldung den Chat-Server (kein Web-API-Schlüssel nötig)")

	print("Spielstatus aus dem Launcher")
	var n_gp := _sent(CM.EMSG_GAMES_PLAYED).size()
	Launcher.current = { "id": "t-zelda", "source": "rom", "title": "Zelda" }
	Launcher.remote_play = false
	Launcher._steam_status(true)
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() > n_gp, 2000)
	gps = _sent(CM.EMSG_GAMES_PLAYED)
	check(SteamCM.games_name == "Zelda" and gps.size() == n_gp + 1 and _game_of(gps[-1]) == "Zelda", "Emulator-Spiel: „Spielt Nicht-Steam-Spiel: Zelda“")
	Launcher._steam_status(false)
	check(SteamCM.games_name == "", "Spielende: Status zurück")
	# Epic- und EA-Spiele laufen genauso durch (Titel wie in der Bibliothek).
	await _frames(4)
	for store_g in [{ "id": "epic:Kinglet", "source": "epic", "system": "epic", "title": "Alan Wake 2" },
			{ "id": "ea:1014052", "source": "ea", "system": "ea", "title": "Die Sims 4" }]:
		var n_st := _sent(CM.EMSG_GAMES_PLAYED).size()
		Launcher.current = store_g
		Launcher._steam_status(true)
		await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() > n_st, 2000)
		var gps_st := _sent(CM.EMSG_GAMES_PLAYED)
		check(SteamCM.games_name == str(store_g.title) and gps_st.size() > n_st and _game_of(gps_st[-1]) == str(store_g.title),
				"%s-Spiel: „Spielt Nicht-Steam-Spiel: %s“" % [str(store_g.source).to_upper(), str(store_g.title)])
		var n_end := gps_st.size()
		Launcher._steam_status(false)
		await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() > n_end, 2000)
		gps_st = _sent(CM.EMSG_GAMES_PLAYED)
		check(SteamCM.games_name == "" and _game_of(gps_st[-1]) == "", "%s-Spiel beendet: Status zurück" % str(store_g.source).to_upper())
	Launcher.current = { "id": "t-steam", "source": "steam", "title": "Portal" }
	Launcher._steam_status(true)
	check(SteamCM.games_name == "", "Steam-Spiel: Uzai meldet nichts (macht Steam selbst)")
	Launcher.current = { "id": "t-rp", "source": "rom", "title": "Zelda" }
	Launcher.remote_play = true
	Launcher._steam_status(true)
	check(SteamCM.games_name == "", "über den Remote-Play-Spender: nichts (Steam zeigt den Spender)")
	Launcher.remote_play = false
	Config.set_value("steam.status_nonsteam", false)
	Launcher._steam_status(true)
	check(SteamCM.games_name == "", "Einstellung aus: nichts")
	Config.set_value("steam.status_nonsteam", true)
	Launcher.current = {}
	await _frames(4)
	gps = _sent(CM.EMSG_GAMES_PLAYED)
	check(_game_of(gps[-1]) == "", "zuletzt gemeldet: spielt nichts")

	print("Anderswo im Spiel (ClientPlayingSessionState)")
	n_gp = _sent(CM.EMSG_GAMES_PLAYED).size()
	var blocked := CM.Pb.f_varint(2, 1)
	blocked.append_array(CM.Pb.f_varint(3, 1145360))
	_push_emsg(CM.EMSG_PLAYING_STATE, blocked)
	await _until(func() -> bool: return SteamCM.playing_blocked, 2000)
	SteamCM.set_games_played("Metroid")
	await _frames(6)
	check(SteamCM.playing_blocked and _sent(CM.EMSG_GAMES_PLAYED).size() == n_gp, "die Steam-App spielt: Uzai meldet nichts (sonst endet das Spiel dort)")
	check(SteamCM.playing_app == 1145360 and str(SteamChat.game_status().short) == "Pausiert", "Einstellungen: „Pausiert“ (Steam am PC spielt App 1145360)")
	# Steam am PC läuft, spielt aber nichts: Steam schickt playing_blocked = false (oder lässt es weg).
	_push_emsg(CM.EMSG_PLAYING_STATE, PackedByteArray())
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() > n_gp, 2000)
	gps = _sent(CM.EMSG_GAMES_PLAYED)
	check(not SteamCM.playing_blocked and gps.size() == n_gp + 1 and _game_of(gps[-1]) == "Metroid", "wieder frei: Spielname gemeldet")

	print("Wiederverbinden")
	n_gp = _sent(CM.EMSG_GAMES_PLAYED).size()
	var n_cs := _sent(CM.EMSG_CHANGE_STATUS).size()
	for ws in peers:
		ws.close()
	await _until(func() -> bool: return not SteamCM.live, 3000)
	var wait_ms := SteamCM._retry_at - Time.get_ticks_msec()
	check(not SteamCM.live and SteamCM.keep != "" and wait_ms > 3000 and wait_ms <= 5100, "Verbindung weg: neuer Versuch nach 5 s (%d ms)" % wait_ms)
	check(absf(SteamCM._backoff - 10.0) < 0.1, "nächste Pause wäre länger (10 s)")
	SteamCM._retry_at = Time.get_ticks_msec()
	await _until(func() -> bool: return SteamCM.live, 6000)
	await _until(func() -> bool: return _sent(CM.EMSG_CHANGE_STATUS).size() > n_cs, 2000)
	check(SteamCM.live and _sent(CM.EMSG_CHANGE_STATUS).size() == n_cs + 1, "verbindet von selbst neu, Status wieder wie in Steam")
	await _until(func() -> bool: return _sent(CM.EMSG_GAMES_PLAYED).size() > n_gp, 2000)
	gps = _sent(CM.EMSG_GAMES_PLAYED)
	check(gps.size() == n_gp + 1 and _game_of(gps[-1]) == "Metroid", "nach dem Wiederverbinden: Spielname erneut gemeldet")
	SteamCM.set_games_played("")
	check(absf(SteamCM._backoff - SteamCM.RECONNECT_MIN) < 0.1, "nach Erfolg wieder kurze Pause")
	_push("FriendMessagesClient.IncomingMessage#1", _incoming(1, "Wieder da", 1760000020, 0))
	await _until(func() -> bool: return Notify.shown == shown0 + 2, 3000)
	check(Notify.shown == shown0 + 2, "nach dem Wiederverbinden kommen Nachrichten wieder an")
	logon_result = 5
	for ws in peers:
		ws.close()
	await _until(func() -> bool: return not SteamCM.live, 3000)
	SteamCM._retry_at = Time.get_ticks_msec()
	await _until(func() -> bool: return SteamCM.keep == "", 6000)
	check(SteamCM.keep == "" and SteamCM.keep_error.contains("abgelehnt") and absf(SteamChat._poll.wait_time - 15.0) < 0.1,
			"Steam lehnt die Anmeldung ab: aufgeben, alle 15 s nachfragen")
	logon_result = 1
	Config.set_value("notify.steam", false)
	check(SteamCM.keep == "" and absf(SteamChat._poll.wait_time - 30.0) < 0.1, "Steam-Nachrichten aus: keine Dauerverbindung")

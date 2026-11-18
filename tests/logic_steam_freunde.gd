extends Node
## Steam-Freunde, Profil und Chat mit der QR-Anmeldung als Steam-App (ohne Netz): Welcher Weg gilt
## (Schlüssel, Web-Zugang, Steams Chat-Server), wann neben Steam am PC eine kurze Sitzung erlaubt
## ist, wie Player.GetPlayerLinkDetails#1 gelesen wird, und dass steam.log je Abruf genau eine
## Zeile ohne Zugangsdaten bekommt.
## Aufruf: godot --headless --path . res://tests/logic_steam_freunde.tscn

const CM := preload("res://src/core/steam_cm.gd")
const Chat := preload("res://src/core/steam_chat.gd")
const Soc := preload("res://src/core/social.gd")
const Quelle := preload("res://tests/quelle.gd")
const FRIEND := 76561197960267728
const ME := 76561197960266728

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_wege()
	_sitzungen()
	_link_details()
	_profil()
	_protokoll()
	_falsche_form()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _wege() -> void:
	print("Weg für Freunde, Profil und Verlauf")
	check(Soc.steam_route(true, true, true, false) == "key", "eigener Schlüssel geht immer vor")
	check(Soc.steam_route(false, true, false, true) == "web", "Steam-App mit Web-Zugang: erst die Web-API")
	check(Soc.steam_route(false, true, true, true) == "cm", "Web-API lehnt ab (HTTP 400 im Protokoll): Chat-Server")
	check(Soc.steam_route(false, true, false, false) == "cm", "kein Web-Zugang (Steam erneuert ihn nicht): Chat-Server")
	check(Soc.steam_route(false, false, true, true) == "web" and Soc.steam_route(false, false, false, false) == "",
			"Browser-Anmeldung: nur die Web-API, ohne Zugang kein Weg")
	check(Chat.web_rejected(400) and Chat.web_rejected(401) and Chat.web_rejected(403), "400/401/403 heißen „Zugang abgelehnt“")
	check(not Chat.web_rejected(0) and not Chat.web_rejected(200) and not Chat.web_rejected(500) and not Chat.web_rejected(429),
			"keine Antwort, Serverfehler, Bremse: nur vorübergehend")


func _sitzungen() -> void:
	print("Kurze Sitzung neben Steam am PC")
	var L := CM.LINK_DETAILS
	check(L in CM.RARE_METHODS and not (L in CM.USER_METHODS), "Freunde: selten, nicht ständig")
	check(CM.session_allowed(L, 0, 1000), "Freunde: erste kurze Sitzung erlaubt (Start, neue Anmeldung)")
	check(not CM.session_allowed(L, 1000, 1000 + CM.FRIENDS_GAP_S - 1) and CM.session_allowed(L, 1000, 1000 + CM.FRIENDS_GAP_S),
			"Freunde höchstens alle %d s" % CM.FRIENDS_GAP_S)
	check(CM.FRIENDS_GAP_S >= 120, "nie öfter als alle zwei Minuten (Fehler 36: Sitzung alle 4 s)")
	check(not CM.session_allowed("Player.GetOwnedGames#1", 1000, 1000 + CM.RARE_GAP_S - 1), "gekaufte Spiele weiter höchstens alle zehn Minuten")
	check(CM.session_allowed("Player.GetOwnedGames#1", 1000, 1001, true) and CM.session_allowed(L, 1000, 1001, true),
			"Profil auf Knopfdruck: wie das Senden immer erlaubt")
	check(not CM.session_allowed("FriendMessages.GetActiveMessageSessions#1", 0, 1000), "Ungelesenes nie automatisch neben Steam am PC")
	var cm_src := Quelle.lesen("res://src/core/steam_cm.gd")
	check(cm_src.contains("var brief := method in RARE_METHODS and not user") and cm_src.contains("if bool(gate.brief):\n\t\tclose_when_idle()"),
			"kurze Sitzung schließt gleich nach der Abfrage")
	# Uzai setzt beim Anmelden keinen Status: kein persona_state im Anmelde-Inhalt, Statusmeldungen
	# nur mit Sperre für Steam am PC.
	var logon := cm_src.substr(cm_src.find("func logon("), cm_src.find("# --- Dauerverbindung") - cm_src.find("func logon("))
	check(not logon.contains("EMSG_CHANGE_STATUS") and not logon.contains("persona"), "Anmeldung setzt keinen Status")
	check(cm_src.contains("\tif pc_signed_in:\n\t\tif not _pc_noted:"), "neben Steam am PC kein eigener Status")


func _pb_account(id: int, name: String, vis: int, priv: PackedByteArray) -> PackedByteArray:
	var Pb = CM.Pb
	var pub := PackedByteArray()
	pub.append_array(Pb.f_fixed64(1, id))
	pub.append_array(Pb.f_varint(2, vis))
	var hash := PackedByteArray()
	hash.resize(20)
	hash.fill(0xAB)
	pub.append_array(Pb.f_bytes(9, hash))
	pub.append_array(Pb.f_string(10, name))
	var acc := Pb.f_msg(1, pub)
	if not priv.is_empty():
		acc.append_array(Pb.f_msg(2, priv))
	return Pb.f_msg(1, acc)


func _link_details() -> void:
	print("Player.GetPlayerLinkDetails#1")
	var Pb = CM.Pb
	var req := CM.link_request([str(FRIEND), "kaputt", "12", str(ME)])
	var rd: Dictionary = Pb.decode(req)
	check((rd.get(1, []) as Array).size() == 2 and int(rd[1][0]) == FRIEND and int(rd[1][1]) == ME, "Anfrage: nur gültige Steam-IDs")
	var priv := PackedByteArray()
	priv.append_array(Pb.f_varint(1, 1))
	priv.append_array(Pb.f_varint(3, 1338595200))
	priv.append_array(Pb.f_fixed64(4, 1245620))
	priv.append_array(Pb.f_varint(6, (10 << 24) | (0 << 16) | (0 << 8) | 7))
	priv.append_array(Pb.f_varint(7, 27015))
	priv.append_array(Pb.f_fixed64(10, 109775241000000000))
	priv.append_array(Pb.f_varint(17, 1700000000))
	var body := _pb_account(FRIEND, "Mira", 3, priv)
	body.append_array(_pb_account(76561198000000777, "Privat", 1, PackedByteArray()))
	body.append_array(_pb_account(42, "Kaputt", 3, PackedByteArray()))
	var off := PackedByteArray()
	off.append_array(Pb.f_varint(1, 0))
	off.append_array(Pb.f_varint(17, 1690000000))
	body.append_array(_pb_account(76561198000000888, "Weg", 3, off))
	var list := CM.parse_link_details(body)
	check(list.size() == 3, "ungültige Steam-ID verworfen")
	var m: Dictionary = list[0]
	check(m.id == str(FRIEND) and m.name == "Mira" and int(m.visibility) == 3 and str(m.avatar).ends_with("abababababababababababababababababababab_full.jpg"),
			"Name, Sichtbarkeit, Bild")
	check(bool(m.has_private) and int(m.state) == 1 and m.game_id == "1245620" and m.server == "10.0.0.7:27015" and m.lobby == "109775241000000000",
			"Status, Spiel, Server und Lobby")
	check(int(m.last) == 1700000000 and int(m.created) == 1338595200, "zuletzt online, Konto erstellt")
	check(not bool(list[1].has_private) and int(list[1].state) == 0, "privates Profil: kein Status")
	var titles := func(appid: int) -> String: return "ELDEN RING" if appid == 1245620 else ""
	var p := Soc.link_to_player(m, titles)
	check(p.personastate == 1 and p.gameextrainfo == "ELDEN RING" and p.gameid == "1245620" and p.lobbysteamid == "109775241000000000",
			"wie GetPlayerSummaries: Spielname aus der Bibliothek")
	var sm := Soc.parse_summary({ "response": { "players": [p] } })
	check(sm.state == "game" and sm.game == "ELDEN RING" and bool(sm.public) and int(sm.created) == 1338595200, "Profilkopf über den Chat-Server")
	var p2 := Soc.link_to_player(m, Callable())
	check(p2.gameextrainfo == Soc.GAME_UNKNOWN, "unbekanntes Spiel: „Steam-Spiel“ statt leer")
	var pp := Soc.link_to_player(list[1], titles)
	check(pp.personastate == 0 and int(pp.communityvisibilitystate) != 3 and pp.gameextrainfo == "", "privat: offline und als privat markiert")
	var po := Soc.link_to_player(list[2], titles)
	check(po.personastate == 0 and po.gameid == "" and int(po.lastlogoff) == 1690000000, "offline mit „zuletzt online“")
	var fr: Dictionary = Social.parse_player(p)
	check(fr.state == "game" and fr.name == "Mira" and fr.game == "ELDEN RING" and fr.server == "10.0.0.7:27015", "Eintrag der Freundesliste mit Status und Spiel")
	check(CM.parse_link_details(PackedByteArray([0xFF, 0x01, 0x02])).is_empty(), "kaputte Antwort: nichts")
	# Gekaufte Spiele mit Spielzeit der letzten zwei Wochen (für „zuletzt gespielt“).
	var g := PackedByteArray()
	g.append_array(Pb.f_varint(1, 570))
	g.append_array(Pb.f_string(2, "Dota 2"))
	g.append_array(Pb.f_varint(3, 90))
	g.append_array(Pb.f_varint(4, 41000))
	var og := CM.parse_owned_games(Pb.f_msg(2, g))
	check(og.size() == 1 and int(og[0].playtime_2weeks) == 90 and int(og[0].playtime_forever) == 41000, "GetOwnedGames: zwei Wochen und gesamt")
	# Profilhintergrund (GetProfileItemsEquipped): nur relative Pfade, nie fremde Adressen.
	var it := Pb.f_string(3, "items/570/abc.jpg")
	check(CM.parse_profile_background(Pb.f_msg(1, it)) == "items/570/abc.jpg", "Profilhintergrund: Pfad aus image_large")
	check(CM.parse_profile_background(Pb.f_msg(1, Pb.f_string(3, "https://boese.example/x.jpg"))) == "", "Profilhintergrund: fremde Adresse abgelehnt")
	check(CM.parse_profile_background(Pb.f_msg(1, Pb.f_string(3, "items/../x.jpg"))) == "", "Profilhintergrund: „..“ abgelehnt")
	check(CM.parse_profile_background(PackedByteArray()) == "", "Profilhintergrund: leere Antwort")


func _profil() -> void:
	print("Profil über den Chat-Server")
	var games := [{ "appid": 570, "name": "Dota 2", "playtime_2weeks": 90, "playtime_forever": 41000 },
		{ "appid": 10, "name": "Alt", "playtime_2weeks": 0, "playtime_forever": 300 }]
	var ow := Soc.parse_owned(Soc.owned_from_cm(games))
	var rc := Soc.parse_recent(Soc.recent_from_cm(games))
	check(not bool(ow.private) and (ow.games as Array).size() == 2, "Bibliothek")
	check(not bool(rc.private) and (rc.games as Array).size() == 1 and int(rc.games[0].two_weeks) == 90, "zuletzt gespielt aus den zwei Wochen")
	check(bool(Soc.parse_owned(Soc.owned_from_cm([])).private) and bool(Soc.parse_recent(Soc.recent_from_cm([])).private), "nichts bekommen: privat")
	var head := { "response": { "players": [{ "steamid": str(FRIEND), "personaname": "Mira", "personastate": 1, "communityvisibilitystate": 3 }] } }
	var pr := Soc.build_profile(str(FRIEND), {}, head, null, Soc.recent_from_cm(games), Soc.owned_from_cm(games), { 570: 60 }, 0)
	check(bool(pr.ok) and str(pr.error) == "" and pr.name == "Mira" and int(pr.level) == -1 and (pr.shared as Array).size() == 1,
			"Profilseite ohne Web-API: Kopf, gemeinsame Spiele, Level unbekannt")


func _rahmen(emsg: int, head: PackedByteArray, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, (emsg | CM.PROTO_MASK) & 0xFFFFFFFF)
	out.encode_u32(4, head.size())
	out.append_array(head)
	out.append_array(body)
	return out


## Sammelnachricht (EMsg Multi) um eine Nachricht; gepackt: mit GZIP wie von Steam.
func _sammel(inhalt: PackedByteArray, gepackt := false) -> PackedByteArray:
	var l := PackedByteArray()
	l.resize(4)
	l.encode_u32(0, inhalt.size())
	l.append_array(inhalt)
	var body := PackedByteArray()
	if gepackt:
		body.append_array(CM.Pb.f_varint(1, l.size()))
		l = l.compress(FileAccess.COMPRESSION_GZIP)
	body.append_array(CM.Pb.f_bytes(2, l))
	return _rahmen(CM.EMSG_MULTI, PackedByteArray(), body)


func _jwt(claims: Dictionary) -> String:
	return "k." + Marshalls.utf8_to_base64(JSON.stringify(claims)).replace("+", "-").replace("/", "_").replace("=", "") + ".s"


## Antworten, die nicht aussehen wie erwartet: Nichts bricht ab, nichts geht an eine fremde Adresse.
func _falsche_form() -> void:
	print("Antworten in falscher Form")
	var P := CM.Pb
	check(P.zahl(P.decode(P.f_varint(3, 5)), 3, 7) == 5 and P.zahl(P.decode(P.f_string(3, "abc")), 3, 7) == 7 and P.zahl({}, 3, 7) == 7,
			"Pb.zahl: Zahl, sonst der Ersatzwert (auch wenn das Feld als Bytes kommt)")
	# Status (2) als Bytes statt als Zahl: Die Meldung wird trotzdem gelesen.
	var f := P.f_fixed64(1, FRIEND)
	f.append_array(P.f_string(2, "x"))
	f.append_array(P.f_string(15, "Mira"))
	var body := P.f_varint(1, 1)
	body.append_array(P.f_msg(2, f))
	var list := CM.parse_persona_state(body)
	check(list.size() == 1 and int(list[0].get("state", -1)) == 0 and str(list[0].get("name", "")) == "Mira",
			"Freundes-Status mit einem Feld in falscher Art: gelesen, der Status zählt als 0")
	check(P.text(P.decode(P.f_string(15, "Mi" + String.chr(0x202E) + "ra" + String.chr(7))), 15) == "Mira",
			"Namen und Nachrichten aus dem Chat-Server: ohne Steuerzeichen und umgedrehte Schreibrichtung")
	check(CM.endpunkt_ok("ext1-fra1.steamserver.net:27019") and CM.endpunkt_ok("cmp2-fra1.steamserver.net"), "Chat-Server: Name mit und ohne Port")
	check(not CM.endpunkt_ok("") and not CM.endpunkt_ok("fremd.example/x") and not CM.endpunkt_ok("a@fremd.example:1") and not CM.endpunkt_ok("h:1?x=1")
			and not CM.endpunkt_ok("h :1"), "Chat-Server: nichts mit Pfad, Zugangsdaten, Anfrage oder Leerzeichen")
	# Sammelnachrichten: gepackt und ungepackt, aber nicht beliebig tief ineinander.
	var cm := CM.new()
	var da: Array = []
	cm.notice.connect(func(m: String, _b: PackedByteArray) -> void: da.append(m))
	var notiz := _rahmen(CM.EMSG_SERVICE_METHOD, P.f_string(12, "Test.Meldung#1"), PackedByteArray())
	cm._handle(_sammel(notiz))
	cm._handle(_sammel(notiz, true))
	cm._handle(_sammel(_sammel(notiz)))
	check(da.size() == 3, "Sammelnachricht: ungepackt, gepackt und einmal verschachtelt kommen an (%d von 3)" % da.size())
	cm._handle(_sammel(_sammel(_sammel(notiz))))
	check(da.size() == 3, "Sammelnachricht in Sammelnachricht in Sammelnachricht: nicht weiter ausgepackt")
	cm.free()
	var cm_src := Quelle.lesen("res://src/core/steam_cm.gd")
	check(not cm_src.contains("decompress_dynamic(-1") and cm_src.contains("decompress_dynamic(MULTI_MAX"), "Entpacken nur mit Obergrenze")
	check(not cm_src.contains("int(Pb.first(") and not Quelle.lesen("res://src/core/steam_chat.gd").contains("int(SteamCM.Pb.first(")
			and not Quelle.lesen("res://src/core/steam_erfolge.gd").contains("int(CM.Pb.first("), "Zahlen aus Nachrichten nur über Pb.zahl")
	# Übergabe der Anmeldung an steamcommunity.com: nur dorthin.
	check(Chat.uebergabe_ok("https://steamcommunity.com/login/settoken") and Chat.uebergabe_ok("https://steamcommunity.com:443/login/settoken"),
			"Übergabe: steamcommunity.com")
	var fremd := PackedStringArray()
	for u in ["https://fremd.example/steamcommunity.com", "https://steamcommunity.com.fremd.example/login/settoken", "http://steamcommunity.com/login/settoken",
			"https://fremd.example/?x=steamcommunity.com", "https://steamcommunity.com@fremd.example/x", "https://steamcommunity.com:8443/x", "steamcommunity.com", ""]:
		if Chat.uebergabe_ok(u):
			fremd.append(u)
	check(fremd.is_empty(), "Übergabe: keine Adresse, die den Namen nur enthält %s" % str(fremd))
	check(Chat.darf_senden(_jwt({ "aud": ["web", "client"], "sub": str(ME) })) and not Chat.darf_senden(_jwt({ "aud": ["web"] }))
			and not Chat.darf_senden(_jwt({ "aud": "client" })) and not Chat.darf_senden(_jwt({})) and not Chat.darf_senden("kein-zugang"),
			"Senden nur mit „client“ in der Liste der Zielgruppen; andere Formen brechen nicht ab")
	check(Chat.parse_messages({ "response": { "messages": null } }, 1).is_empty() and Chat.parse_messages({ "response": null }, 1).is_empty(),
			"Verlauf ohne Liste: leer")
	var ml := Chat.parse_messages({ "response": { "messages": [null, "x", { "accountid": null, "message": null, "timestamp": "5", "ordinal": 2.0 },
		{ "accountid": 1, "message": "[b]hi[/b] [emoticon]steamhappy[/emoticon]", "timestamp": 4 }] } }, 1)
	check(ml.size() == 2 and bool(ml[0].me) and str(ml[0].text) == "hi :steamhappy:" and int(ml[1].at) == 5 and int(ml[1].ordinal) == 2 and not bool(ml[1].me),
			"Verlauf mit Lücken und leeren Feldern: gelesen, nach Zeit geordnet")


func _protokoll() -> void:
	print("steam.log")
	var p := Config.path("logs/steam.log")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	SteamChat.diag_log("freunde", "web400", "Freunde: Web-API HTTP 400")
	SteamChat.diag_log("freunde", "web400", "Freunde: Web-API HTTP 400")
	SteamChat.diag_log("verlauf", "cm1", "Verlauf: Chat-Server ok, 3 Nachrichten")
	SteamChat.diag_log("freunde", "cm1:77", "Freunde: Chat-Server ok, 77 Freunde")
	SteamChat.diag_log("freunde", "cm1:77", "Freunde: Chat-Server ok, 77 Freunde")
	var log := FileAccess.get_file_as_string(p)
	check(log.count("Freunde: Web-API HTTP 400") == 1 and log.count("77 Freunde") == 1 and log.count("Verlauf:") == 1,
			"je Abruf eine Zeile, Doppeltes nicht wiederholt")
	# Diagnose-Zeilen nennen nie Zugang, Token oder Cookie.
	var bad := RegEx.create_from_string(
			"(_log|diag|log_line)\\(.*(% ?tok\\b|, tok\\b|\\[tok\\b|refresh_token\\]|% ?cookie|, cookie\\b|access_token\\b|_access\\b|_web_token)")
	var hits := PackedStringArray()
	for f in ["steam_chat.gd", "steam_cm.gd", "social.gd"]:
		for line in Quelle.lesen("res://src/core/" + f).split("\n"):
			if bad.search(line) != null:
				hits.append(f + ": " + line.strip_edges())
	check(hits.is_empty(), "keine Zugangsdaten in Protokollzeilen %s" % str(hits))
	var chat_src := Quelle.lesen("res://src/core/steam_chat.gd")
	check(chat_src.contains("if web_rejected(int(r.code)) and can_send():\n\t\t\tnote_web(int(r.code), \"Verlauf\")\n\t\t\treturn await _history_cm(friend_id, count, mark_read)"),
			"Verlauf: abgelehnte Web-API → gleich über den Chat-Server")
	var soc_src := Quelle.lesen("res://src/core/social.gd")
	check(soc_src.contains("if rt.route == \"web\" and SteamChat.can_send() and SteamChat.web_rejected(int(fl.code)):\n\t\t\tawait _refresh_steam_cm(sid)"),
			"Freunde: abgelehnte Web-API → gleich über den Chat-Server")
	check(soc_src.contains("# Wen Steam diesmal nicht beschrieben hat, der bleibt mit dem letzten Stand in der Liste."), "Liste wird nicht verworfen")

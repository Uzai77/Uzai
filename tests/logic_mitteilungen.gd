extends Node
## Logik der Mitteilungen ohne Netz: wann eine Steam-Nachricht ein Pop-up bekommt (keine
## doppelten, keine eigenen, nicht für den offenen Chat), Discord-Benachrichtigungen über die
## RPC-Schnittstelle (Fake-Leitung über Voice.transport), Öffnen mit View, Abfrage-Takt.
## Aufruf: UZAI_DATA=<leerer ordner> godot --headless --path . res://tests/logic_mitteilungen.tscn

const CM := preload("res://src/core/steam_cm.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Quelle := preload("res://tests/quelle.gd")
const MainD := preload("res://src/main_discord.gd")
const FRIEND := "76561197960267728"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_steam_rules()
	_steam_weg()
	_steam_protokoll()
	_chat_stand()
	_steam_incoming()
	await _discord()
	await _open_and_keys()
	_discord_dm()
	_history_targets()
	_incoming_call()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _steam_rules() -> void:
	print("Steam: wann ein Pop-up erscheint")
	var m := { "friend": FRIEND, "kind": 1, "text": "Bist du da?", "at": 1760000000, "ordinal": 0, "echo": false }
	check(Notify.steam_reason(m, "", {}, true) == "", "neue Nachricht: Pop-up")
	check(Notify.steam_reason(m, "", {}, false) == "aus", "Steam-Nachrichten aus: kein Pop-up")
	check(Notify.steam_reason(m, FRIEND, {}, true) == "offen", "Chat mit ihm ist offen: kein Pop-up")
	# Offen allein reicht nicht: nur ein Chat, der zu sehen ist, schluckt das Pop-up (Freund-Test 0.16.51).
	check(Notify.chat_seen(FRIEND, FRIEND, true, true, true), "Chat offen, sichtbar, Uzai vorn: gesehen")
	check(not Notify.chat_seen(FRIEND, FRIEND, true, true, false), "Chat offen, aber Uzai hinter dem Spiel: Pop-up")
	check(not Notify.chat_seen(FRIEND, FRIEND, true, false, true), "Chat-Ansicht verdeckt/geschlossen: Pop-up")
	check(not Notify.chat_seen("", FRIEND, false, false, false) and not Notify.chat_seen("77", FRIEND, true, true, true), "anderer Chat offen: Pop-up")
	check(Notify.chat_seen(FRIEND, FRIEND, false, false, false), "ohne Ansicht (Tests, Rundgang): offen wie bisher")
	check(not Notify.vorn(true, false, false, true), "Spiel läuft, Guide zu: Uzai nicht vorn")
	check(Notify.vorn(true, true, false, true), "Guide über dem Spiel: Uzai vorn")
	check(not Notify.vorn(false, false, true, true) and not Notify.vorn(false, false, false, false), "minimiert oder ohne Fokus: nicht vorn")
	check(Notify.vorn(false, false, false, true), "Uzai vorn")
	var echo := m.duplicate()
	echo["echo"] = true
	check(Notify.steam_reason(echo, "", {}, true) == "eigene", "eigene Nachricht (von einem anderen Gerät): kein Pop-up")
	var typ := m.duplicate()
	typ["kind"] = 2
	typ["text"] = ""
	check(Notify.steam_reason(typ, "", {}, true) != "", "„schreibt gerade“: kein Pop-up")
	var seen := { Notify.steam_key(m): true }
	var from_poll := { "friend": FRIEND, "kind": 1, "text": "Bist du da? :steamhappy:", "at": 1760000000, "ordinal": 0, "echo": false, "from_poll": true }
	check(Notify.steam_reason(from_poll, "", seen, true) == "doppelt", "dieselbe Nachricht aus der Abfrage (anderer Text-Stil): doppelt")
	var later := m.duplicate()
	later["ordinal"] = 1
	check(Notify.steam_reason(later, "", seen, true) == "", "zweite Nachricht in derselben Sekunde (ordinal) zählt neu")
	var empty := m.duplicate()
	empty["text"] = "  "
	check(Notify.steam_reason(empty, "", {}, true) == "leer", "leere Nachricht: kein Pop-up")
	check(Notify.steam_key({ "friend": "1", "text": "a" }) != Notify.steam_key({ "friend": "1", "text": "b" }), "ohne Zeitangabe: Text unterscheidet")

	print("Steam: Abfrage")
	check(SteamChat.new_unread({ "a": 1 }, { "a": 2, "b": 1, "c": 0 }) == ["a", "b"], "mehr Ungelesenes erkannt (nur Zuwachs)")
	check(SteamChat.new_unread({ "a": 3 }, { "a": 1 }).is_empty(), "weniger Ungelesenes: nichts Neues")
	check(SteamChat.poll_secs(false, true) == 15.0 and SteamChat.poll_secs(true, true) == 60.0 and SteamChat.poll_secs(false, false) == 30.0,
			"Abfrage alle 15 s ohne Echtzeit, 60 s mit, 30 s wenn aus")
	var hist := [{ "me": false, "text": "Hi", "at": 1 }, { "me": false, "text": "Kommst du?", "at": 2 }, { "me": true, "text": "Gleich", "at": 3 }]
	check(str(SteamChat.last_from_friend(hist).get("text", "")) == "Kommst du?", "letzte Nachricht des Freundes (nicht deine)")
	check(SteamChat.last_from_friend([{ "me": true, "text": "x", "at": 1 }]).is_empty(), "nur eigene: nichts")


## Freund-Test 0.16.53 („notifications still do not work“): Steam am PC angemeldet, also keine eigene Verbindung.
## Die Web-API lehnte GetFriendList ab (HTTP 400) – das schaltete auch die Abfrage ungelesener Nachrichten ab,
## obwohl sie ging („Ungelesen: Web-API ok“). Es kam nichts mehr an, und die Einstellungen sagten „Alle 15 Sekunden“.
func _steam_weg() -> void:
	print("Steam: wie Nachrichten ankommen")
	check(SteamChat.nachrichten_weg(false, true, false, true, true, true) == "keiner", "nicht angemeldet: kein Weg")
	check(SteamChat.nachrichten_weg(false, false, false, true, true, true) == "aus" and SteamChat.nachrichten_weg(true, false, true, true, true, false) == "aus",
			"Steam-Nachrichten aus: aus")
	check(SteamChat.nachrichten_weg(true, true, true, false, true, true) == "sofort", "eigene Verbindung: sofort")
	check(SteamChat.nachrichten_weg(true, true, false, true, true, true) == "abfrage", "Steam am PC, Web-API nimmt den Chat an: Abfrage")
	check(SteamChat.nachrichten_weg(true, true, false, false, true, false) == "abfrage", "ohne Steam am PC: Abfrage über eine eigene Sitzung")
	check(SteamChat.nachrichten_weg(true, true, false, false, true, true) == "selten", "Steam am PC und Web-API lehnt den Chat ab: nur nebenbei")
	check(SteamChat.nachrichten_weg(true, true, false, true, false, true) == "abfrage", "Browser-Anmeldung: Web-API")
	for w in ["keiner", "aus", "sofort", "abfrage", "selten"]:
		check(SteamChat.WEG_LOG.has(w) and SteamChat.WEG_TEXT.has(w), "Text und Protokoll für „%s“" % w)
	check(str(SteamChat.WEG_TEXT.selten) != str(SteamChat.WEG_TEXT.abfrage), "neben Steam am PC ohne Web-API steht nicht „Alle 15 Sekunden“")

	print("Steam: Web-API je Schnittstelle")
	var keep_ref := str(Config.get_value("accounts.steam_chat_refresh", ""))
	var keep_demo: bool = SteamChat.demo
	SteamChat.demo = false
	Config.set_value("accounts.steam_chat_refresh", _jwt(["client", "web", "renew", "derive"]))
	SteamChat._web_bad_until = 0
	SteamChat._chat_web_bad_until = 0
	SteamChat.note_web(400, "GetFriendList")
	check(not SteamChat.web_ok() and SteamChat.chat_web_ok(), "GetFriendList HTTP 400: Freunde über den Chat-Server, Ungelesenes weiter über die Web-API")
	SteamChat.note_web(400, "Erfolge")
	check(SteamChat.chat_web_ok(), "abgelehnte Erfolge berühren den Chat nicht")
	SteamChat.note_web(500, "Ungelesen")
	check(SteamChat.chat_web_ok(), "Serverfehler: nur vorübergehend")
	SteamChat.note_web(400, "Ungelesen")
	check(not SteamChat.chat_web_ok(), "Ungelesen HTTP 400: Chat über den Chat-Server")
	var src := Quelle.lesen("res://src/core/steam_chat.gd")
	var ru := src.substr(src.find("func refresh_unread()"), src.find("func chat_in_view(") - src.find("func refresh_unread()"))
	check(ru.contains("if chat_web_ok() or not can_send():") and not ru.contains("if web_ok()"), "Abfrage fragt nur nach dem Chat-Merker")
	check(ru.contains("SteamCM.state != \"angemeldet\"") and src.contains("SteamCM.friends_list.connect(_on_cm_list)"),
			"neben Steam am PC ohne Web-API: in Uzais kurzen Sitzungen mitfragen, keine eigene")
	var hi := src.substr(src.find("func history(friend_id"), src.find("func _history_cm(") - src.find("func history(friend_id"))
	check(hi.contains("if chat_web_ok() or not can_send():"), "Verlauf (auch fürs Pop-up aus der Abfrage) ebenso")
	SteamChat._web_bad_until = 0
	SteamChat._chat_web_bad_until = 0
	Config.set_value("accounts.steam_chat_refresh", keep_ref)
	SteamChat.demo = keep_demo


## Je eingehender Nachricht eine Zeile in steam.log: ob und warum (nicht) gemeldet – ohne Text, Name, Steam-ID.
func _steam_protokoll() -> void:
	print("Steam: Protokoll je Nachricht")
	var z := Notify.steam_zeile("Freund 1", "", { "abfrage": false, "ueber_spiel": true })
	check(z == "Nachricht sofort von Freund 1: Pop-up über dem Spiel", "gezeigt über dem Spiel (%s)" % z)
	check(Notify.steam_zeile("Freund 2", "", { "abfrage": true, "vorn": true }) == "Nachricht aus der Abfrage von Freund 2: Pop-up in Uzai",
			"aus der Abfrage, in Uzai")
	check(Notify.steam_zeile("Freund 1", "offen", {}).ends_with("kein Pop-up – Chat ist offen und zu sehen (gilt als gelesen)"),
			"offen und zu sehen: Grund in Worten")
	check(Notify.steam_zeile("Freund 1", "aus", {}).contains("in den Einstellungen aus"), "aus: Grund in Worten")
	check(Notify.steam_zeile("Freund 1", "", { "ruhig": true }).contains("Nicht stören"), "Nicht stören: still")
	var hinten := Notify.steam_zeile("Freund 1", "", { "vorn": false, "im_spiel_aus": true })
	check(hinten.contains("Uzai liegt nicht vorn") and hinten.contains("Pop-ups im Spiel"), "Pop-up hinter dem Spiel: steht da (%s)" % hinten)
	check(Notify.steam_zeile("Freund 1", "", { "verdeckt": true, "vorn": true }).ends_with("(Chat offen, aber nicht zu sehen)"),
			"Chat offen, verdeckt: Pop-up mit Vermerk")
	for why in ["aus", "eigene", "unbekannt", "offen", "leer", "doppelt", "keine Nachricht"]:
		check(Notify.GRUND.has(why), "Grund „%s“ in Worten" % why)
	var t1 := SteamChat.log_tag(FRIEND)
	var t2 := SteamChat.log_tag("76561190000000077")
	check(t1.begins_with("Freund ") and t1 == SteamChat.log_tag(FRIEND) and t1 != t2 and not t1.contains(FRIEND),
			"Kürzel je Freund: gleich bleibend, ohne Steam-ID")
	check(SteamChat.log_tag("") == "unbekannt", "ohne Absender: unbekannt")
	# Echt durchlaufen: eine Nachricht → genau eine Zeile, ohne Text und ID.
	var p := Config.path("logs/steam.log")
	var vorher := FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	var keep_seen := Notify.seen.duplicate()
	var m := { "friend": FRIEND, "kind": 1, "text": "Geheimer Text 123", "at": 1760000999, "ordinal": 4, "echo": false }
	Notify._on_steam(m)
	Notify._on_steam(m)
	var neu := (FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else "").substr(vorher.length())
	check(neu.count("Nachricht sofort von " + t1) == 2, "zwei Nachrichten, zwei Zeilen (%s)" % neu.strip_edges())
	check(neu.contains("kein Pop-up – schon gemeldet"), "die zweite: schon gemeldet")
	check(not neu.contains("Geheimer") and not neu.contains(FRIEND), "kein Text, keine Steam-ID im Protokoll")
	Notify.seen = keep_seen
	Toasts.clear_history()
	var chat_src := Quelle.lesen("res://src/core/steam_chat.gd")
	check(not chat_src.contains("Nachricht sofort erhalten von %s") and not Quelle.lesen("res://src/core/notify.gd").contains("\"Pop-up %s: %s\""),
			"keine Zeilen mehr mit der Steam-ID des Freundes")
	print("Mitteilungen: Hinweis ohne Steam-Anmeldung")
	check(MainD.steam_hint_due("keiner", true, false), "nicht angemeldet, Steam auf dem PC: Hinweis mit Anmelden")
	check(not MainD.steam_hint_due("keiner", false, false) and not MainD.steam_hint_due("aus", true, false)
			and not MainD.steam_hint_due("abfrage", true, false) and not MainD.steam_hint_due("keiner", true, true),
			"ohne Steam, Pop-ups aus, angemeldet oder Vorführung: kein Hinweis")
	var med := Quelle.lesen("res://src/ui/sections/settings_medien.gd")
	check(med.contains("SteamChat.WEG_TEXT.get(weg") and med.contains("if steam_an and weg == \"keiner\":"), "Einstellungen: echter Weg und „Mit Steam anmelden“")


func _jwt(aud: Array) -> String:
	var body := Marshalls.utf8_to_base64(JSON.stringify({ "sub": "76561198000000002", "aud": aud, "exp": 4102444800 })).replace("+", "-").replace("/",
			"_").replace("=", "")
	return "eyJhbGciOiJFZERTQSJ9." + body + ".c2ln"


## Wann ein Chat offen bzw. zu sehen ist, steht nachvollziehbar in Zustand.lage() („chat.steam“, „chat.discord“;
## Fehlerbericht): zu · offen · zu_sehen (kein Pop-up) · verdeckt (Pop-up). Das Verhalten bleibt wie in _steam_rules.
func _chat_stand() -> void:
	print("Chat offen und zu sehen: Stand im Zustand")
	var hidden := Control.new()
	hidden.visible = false
	add_child(hidden)
	for be in [SteamChat, DiscordChat]:
		var n := "chat.steam" if be == SteamChat else "chat.discord"
		var keep_chat: String = be.open_chat
		var keep_view: WeakRef = be.open_view
		be.open_chat = ""
		be.open_view = null
		be.open_chat = FRIEND
		check(_stand(n) == "offen", "%s: Gespräch geöffnet – offen" % n)
		check(be.chat_in_view(FRIEND) and _stand(n) == "zu_sehen", "%s: ohne eigene Ansicht (angeheftet, Tests) – zu sehen" % n)
		be.open_view = weakref(hidden)
		check(not be.chat_in_view(FRIEND) and _stand(n) == "verdeckt", "%s: Ansicht nicht zu sehen – verdeckt, das Pop-up kommt" % n)
		check(not be.chat_in_view("77") and _stand(n) == "verdeckt", "%s: Nachricht eines anderen Freundes ändert den Stand nicht" % n)
		be.open_chat = ""
		check(_stand(n) == "zu", "%s: geschlossen – zu" % n)
		be.open_view = keep_view
		be.open_chat = keep_chat
	hidden.queue_free()


func _stand(name: String) -> String:
	for e in Zustand.lage():
		if str(e.name) == name:
			return str(e.zustand)
	return "?"


func _incoming_body(kind: int, text: String, at: int, ordinal: int, echo := false) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(CM.Pb.f_fixed64(1, int(FRIEND)))
	b.append_array(CM.Pb.f_varint(2, kind))
	if text != "":
		b.append_array(CM.Pb.f_string(4, "[b]" + text + "[/b]"))
	b.append_array(CM.Pb.f_fixed32(5, at))
	b.append_array(CM.Pb.f_varint(6, ordinal))
	if echo:
		b.append_array(CM.Pb.f_varint(7, 1))
	if text != "":
		b.append_array(CM.Pb.f_string(8, text))
	return b


func _steam_incoming() -> void:
	print("Steam: eingehende Meldung (protobuf)")
	var p := SteamChat.parse_incoming(_incoming_body(1, "Grüße 🎮", 1760000123, 2))
	check(str(p.friend) == FRIEND and int(p.kind) == 1 and str(p.text) == "Grüße 🎮", "Freund, Art und Text (ohne BB-Code)")
	check(int(p.at) == 1760000123 and int(p.ordinal) == 2 and not bool(p.echo), "Serverzeit (fixed32), laufende Nummer, kein Echo")
	check(bool(SteamChat.parse_incoming(_incoming_body(1, "x", 1, 0, true)).echo), "local_echo erkannt")
	var bb := CM.Pb.f_fixed64(1, int(FRIEND))
	bb.append_array(CM.Pb.f_varint(2, 1))
	bb.append_array(CM.Pb.f_string(4, "[emoticon]steamhappy[/emoticon] hallo"))
	check(str(SteamChat.parse_incoming(bb).text) == ":steamhappy: hallo", "ohne message_no_bbcode: BB-Code lesbar gemacht")


func _discord() -> void:
	print("Discord: Benachrichtigungen (NOTIFICATION_CREATE)")
	var sample := { "channel_id": "199737254929760256", "message": { "id": "1001", "content": "test message",
		"author": { "id": "155607406007681024", "username": "test_user", "avatar": "8ab5" } },
		"icon_url": "https://cdn.discordapp.com/avatars/155607406007681024/8ab559bd94f1c3cd3f1a41a5e3ff9f28.webp?size=128",
		"title": "test_user (#general)", "body": "test message" }
	var pp := Notify.discord_popup(sample, "4")
	check(str(pp.title) == "test_user (#general)" and str(pp.sub) == "test message", "Titel und Text aus Discord")
	check(str(pp.image).ends_with(".png?size=128") and str(pp.key) == "d:1001", "Profilbild als PNG, Schlüssel aus der Nachrichten-ID")
	check(Notify.discord_popup(sample, "155607406007681024").is_empty(), "eigene Nachricht: kein Pop-up")
	check(Notify.discord_popup({ "title": null, "body": null }, "4").is_empty(), "leere Benachrichtigung: nichts")
	var dm := Notify.discord_popup(
			{ "channel_id": "5", "message": { "id": "7", "content": "hey", "author": { "id": "9", "username": "sana", "global_name": "Sana" } }, "icon_url": null,
			"title": "", "body": "" }, "4")
	check(str(dm.title) == "Sana" and str(dm.sub) == "hey" and str(dm.image) == "", "ohne Titel/Text: Name und Inhalt aus der Nachricht")

	var sent: Array = []
	var keep_transport: Callable = Voice.transport
	Voice.transport = func(j: String) -> void: sent.append(JSON.parse_string(j))
	Voice.demo = false
	Voice.state = "verbinde"
	Config.set_value("notify.discord", true)
	check(Voice.want_notices and Voice.scopes().has("rpc.notifications.read"), "Freigabe fragt das Recht für Benachrichtigungen mit an")
	Config.set_value("accounts.discord_client_id", "123456789012345678")
	Config.set_value("accounts.discord_client_secret", "abcdefghijklmnopqrstuvwxyz012345")
	Config.set_value("accounts.discord_token", "tok")
	Config.set_value("accounts.discord_scope", "rpc rpc.voice.read rpc.voice.write")
	Config.set_value("accounts.discord_expires", int(Time.get_unix_time_from_system()) + 3600)
	# Alte Freigabe ohne das Recht: nicht abonnieren, sondern „neu verbinden“ anzeigen.
	Voice.handle({ "cmd": "AUTHENTICATE", "data": { "user": { "id": "4", "username": "ich" }, "scopes": ["rpc", "rpc.voice.read", "rpc.voice.write"] } })
	check(Voice.notices == "fehlt" and not sent.any(func(x): return str(x.get("evt", "")) == "NOTIFICATION_CREATE"),
			"Recht fehlt: kein Abo, Hinweis „neu verbinden“")
	# Neu verbinden wie in Uzai: erst aus, dann verbinden (discord.sprache, src/core/voice.gd).
	Voice.state = "aus"
	Voice.state = "verbinde"
	sent.clear()
	Voice.handle(
			{ "cmd": "AUTHENTICATE",
			"data": { "user": { "id": "4", "username": "ich" }, "scopes": ["rpc", "rpc.voice.read", "rpc.voice.write", "rpc.notifications.read"] } })
	var sub: Array = sent.filter(func(x): return x.cmd == "SUBSCRIBE" and str(x.get("evt", "")) == "NOTIFICATION_CREATE")
	check(sub.size() == 1 and (sub[0].args as Dictionary).is_empty(), "mit Recht: NOTIFICATION_CREATE abonniert (ohne Argumente)")
	Voice.handle({ "cmd": "SUBSCRIBE", "data": { "evt": "NOTIFICATION_CREATE" }, "nonce": str(sub[0].nonce) if not sub.is_empty() else "" })
	check(Voice.notices == "an", "Abo bestätigt")
	var n0 := Notify.shown
	var h0 := Toasts.history.size()
	Voice.handle({ "cmd": "DISPATCH", "evt": "NOTIFICATION_CREATE", "data": sample })
	check(Notify.shown == n0 + 1 and Toasts.history.size() == h0 + 1, "Benachrichtigung: ein Pop-up")
	check(str(Toasts.history[0].title) == "test_user (#general)" and str(Toasts.history[0].sub) == "test message" and str(Toasts.history[0].icon) == "discord",
			"Pop-up mit Titel, Text und Discord-Symbol")
	check(str(Toasts.history[0].image).begins_with("https://cdn.discordapp.com/avatars/"), "Pop-up mit Profilbild")
	Voice.handle({ "cmd": "DISPATCH", "evt": "NOTIFICATION_CREATE", "data": sample })
	check(Notify.shown == n0 + 1, "dieselbe Benachrichtigung zweimal: ein Pop-up")
	var own := sample.duplicate(true)
	own.message.id = "1002"
	own.message.author.id = "4"
	Voice.handle({ "cmd": "DISPATCH", "evt": "NOTIFICATION_CREATE", "data": own })
	check(Notify.shown == n0 + 1, "eigene Nachricht: kein Pop-up")
	check(str(Notify.last.get("kind", "")) == "discord", "zuletzt: Discord (Guide öffnet die Mitteilungen)")
	Config.set_value("notify.discord", false)
	check(not Voice.scopes().has("rpc.notifications.read") and sent.back().cmd == "UNSUBSCRIBE", "ausgeschaltet: Abo beendet, Recht nicht mehr erfragt")
	var other := sample.duplicate(true)
	other.message.id = "1003"
	Voice.handle({ "cmd": "DISPATCH", "evt": "NOTIFICATION_CREATE", "data": other })
	check(Notify.shown == n0 + 1, "ausgeschaltet: kein Pop-up")
	Config.set_value("notify.discord", true)
	var sub2: Array = sent.filter(func(x): return x.cmd == "SUBSCRIBE" and str(x.get("evt", "")) == "NOTIFICATION_CREATE")
	check(sub2.size() == 2, "wieder an: neu abonniert")
	# Discord lehnt das Abo ab (Recht widerrufen): sichtbar statt still.
	Voice.handle({ "cmd": "SUBSCRIBE", "evt": "ERROR", "data": { "code": 4006, "message": "Not authenticated or invalid scope" }, "nonce": str(sub2[1].nonce) })
	check(Voice.notices == "fehlt", "abgelehntes Abo: „neu verbinden“")
	# Freigabe mit dem Recht abgelehnt: einmal ohne neu fragen (Sprachkanal geht weiter).
	Voice.state = "getrennt"
	Voice.extra_rejected = false
	# Unabhängig von „Bilder im Chat“ (discord.chat_bilder, messages.read) in den Einstellungen dieses PCs.
	Voice.set("_msg_rejected", true)
	sent.clear()
	Voice.authorize()
	check(sent.back().cmd == "AUTHORIZE" and (sent.back().args.scopes as Array).has("rpc.notifications.read"), "Freigabe mit Benachrichtigungen")
	Voice.handle({ "cmd": "AUTHORIZE", "evt": "ERROR", "data": { "code": 4002, "message": "Invalid scope" } })
	check(Voice.extra_rejected and sent.back().cmd == "AUTHORIZE" and not (sent.back().args.scopes as Array).has("rpc.notifications.read"),
			"abgelehnt: nochmal ohne das Recht")
	Voice.extra_rejected = false
	Voice.set("_msg_rejected", false)
	Voice.transport = keep_transport
	Voice.state = "aus"
	Voice.notices = ""
	Config.set_value("accounts.discord_token", "")
	Config.set_value("accounts.discord_client_id", "")
	Config.set_value("accounts.discord_client_secret", "")
	await get_tree().process_frame


func _open_and_keys() -> void:
	print("Öffnen und Tasten")
	var opened: Array = []
	Toasts.show_toast("Mira", "Kommst du?", "chat", { "open": func() -> void: opened.append(1), "open_text": "Chat öffnen" })
	await get_tree().process_frame
	check(Toasts.open_latest() and opened.size() == 1, "View öffnet das Pop-up")
	check(not Toasts.open_latest() and opened.size() == 1, "danach nichts mehr offen")
	Toasts.show_toast("Bildschirmfoto gespeichert", "", "camera")
	check(not Toasts.open_latest(), "Pop-up ohne Öffnen: View tut nichts")
	check(not Toasts.use_overlay(), "ohne Spiel und unter Linux: Pop-ups in Uzai selbst")
	var keep := Notify.last
	Notify.last = { "kind": "steam", "target": { "id": FRIEND }, "at": Time.get_ticks_msec() - Notify.OPEN_MS - 10, "over": true }
	check(Notify.take_pending().is_empty(), "altes Pop-up: Guide-Taste öffnet normal")
	Notify.last = { "kind": "steam", "target": { "id": FRIEND }, "at": Time.get_ticks_msec(), "over": false }
	check(Notify.take_pending().is_empty(), "Pop-up war nicht über dem Spiel zu sehen (aus): Guide öffnet normal")
	Notify.last = { "kind": "steam", "target": { "id": FRIEND }, "at": Time.get_ticks_msec(), "over": true }
	var pend := Notify.take_pending()
	check(str(pend.get("kind", "")) == "steam" and Notify.last.is_empty(), "frisches Pop-up: Guide-Taste öffnet den Chat (einmal)")
	Notify.last = keep

	# View kurz allein: Befehl „view“. View + Start (Guide): beim Loslassen kein „view“.
	var cmds: Array = []
	var cb := func(c: String) -> void: cmds.append(c)
	Nav.command.connect(cb)
	Nav._input(_key(KEY_V, true))
	Nav._input(_key(KEY_V, false))
	check(cmds.has("view"), "View kurz gedrückt: öffnen")
	cmds.clear()
	Nav._input(_key(KEY_V, true))
	Nav._input(_key(KEY_M, true))
	Nav._input(_key(KEY_M, false))
	Nav._input(_key(KEY_V, false))
	check(cmds.has("guide") and not cmds.has("view"), "View + Start: nur der Guide")
	Nav.command.disconnect(cb)


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	return e


func _discord_dm() -> void:
	print("Discord-Direktnachricht → Chat")
	var now := Time.get_ticks_msec()
	var e := { "kind": "discord_dm", "target": { "id": "42" }, "at": now, "over": false }
	check(not Notify.fresh(e, now), "über dem Spiel nötig: Pop-up in Uzai zählt nicht")
	check(Notify.fresh(e, now, false), "außerhalb des Spiels zählt auch das Pop-up in Uzai")
	check(not Notify.fresh(e, now + 40000, false), "nach 30 s nicht mehr")
	Notify.last = {}
	Notify.discord_dm({ "id": "42", "name": "Mia", "avatar": "" }, "Hey, zockst du?", "m777")
	check(str(Notify.last.get("kind", "")) == "discord_dm" and str((Notify.last.target as Dictionary).get("id", "")) == "42", "Pop-up merkt sich den Chat mit Mia")
	var shown := Notify.shown
	Notify.discord_dm({ "id": "42", "name": "Mia" }, "Hey, zockst du?", "m777")
	check(Notify.shown == shown, "dieselbe Nachricht (gleiche ID) nur einmal")
	var p := Notify.take_pending(false)
	check(str(p.get("kind", "")) == "discord_dm", "Guide-Taste außerhalb des Spiels: führt in den Chat")
	check(Notify.take_pending(false).is_empty(), "danach erledigt")


func _history_targets() -> void:
	print("Mitteilungsliste: Einträge führen zum Ziel")
	Notify.discord_dm({ "id": "43", "name": "Lea", "avatar": "" }, "Gleich online?", "m778")
	var h: Dictionary = Toasts.history[0]
	check((h.get("go", Callable()) as Callable).is_valid() and str(h.get("go_text", "")) == "Chat öffnen", "Direktnachricht: führt in den Chat")
	Notify.last = {}
	Notify.pop("discord", "test_user (#general)", "hallo", "discord", "", { "channel": "c1" })
	check(not (Toasts.history[0].get("go", Callable()) as Callable).is_valid(), "Server-Nachricht: kein Ziel in Uzai (A zeigt die Liste)")
	Notify.last = {}
	var hit: Array = []
	Toasts.show_toast("Disc eingelegt", "Ico", "disc", { "go": func() -> void: hit.append(1), "go_text": "Zum Spiel" })
	var main_like := { "go": Toasts.history[0].go }
	(main_like.go as Callable).call()
	check(hit.size() == 1 and str(Toasts.history[0].go_text) == "Zum Spiel", "Ziel bleibt in der Liste und lässt sich später öffnen")
	Toasts.show_toast("Gespeichert", "", "check")
	check(not (Toasts.history[0].get("go", Callable()) as Callable).is_valid(), "Hinweis ohne Ziel: kein Sprung")


func _incoming_call() -> void:
	print("Eingehender Discord-Anruf")
	var me := "1"
	check(Voice.is_ringing([{ "user": { "id": "42" } }], "42", me), "Freund im Anruf der Direktnachricht, du nicht: klingelt")
	check(not Voice.is_ringing([{ "user": { "id": "42" } }, { "user": { "id": "1" } }], "42", me), "du bist schon drin: klingelt nicht")
	check(not Voice.is_ringing([], "42", me), "leerer Kanal: nichts")
	var sent: Array = []
	var keep_transport: Callable = Voice.transport
	Voice.transport = func(j: String) -> void: sent.append(JSON.parse_string(j))
	Voice.demo = false
	Voice.state = "bereit"
	Voice.me_id = me
	Voice.channel = {}
	Voice.members = []
	var got: Array = []
	var cb := func(info: Dictionary) -> void: got.append(info)
	Voice.incoming_call.connect(cb)
	Voice.watch_dm("dm1", "42")
	check(sent.filter(func(m): return str(m.cmd) == "SUBSCRIBE" and str(m.args.get("channel_id", "")) == "dm1").size() == 2,
			"Direktnachricht beobachtet (Beitreten und Verlassen)")
	sent.clear()
	Voice.handle({ "cmd": "DISPATCH", "evt": "VOICE_STATE_CREATE", "data": { "user": { "id": "42", "username": "mia" } } })
	check(sent.any(func(m): return str(m.cmd) == "GET_CHANNEL" and str(m.args.channel_id) == "dm1"), "Freund tritt bei: Uzai fragt nach")
	check(Voice.members.is_empty(), "taucht nicht in deinem Sprachkanal auf")
	Voice.handle({ "cmd": "GET_CHANNEL", "data": { "id": "dm1", "voice_states": [{ "user": { "id": "42", "username": "mia", "global_name": "Mia" } }] } })
	check(got.size() == 1 and str(got[0].channel_id) == "dm1" and str(got[0].name) == "Mia", "Anruf erkannt: Mia ruft an")
	var ended: Array = []
	var cb2 := func(cid: String) -> void: ended.append(cid)
	Voice.call_ended.connect(cb2)
	Voice.handle({ "cmd": "DISPATCH", "evt": "VOICE_STATE_DELETE", "data": { "user": { "id": "42" } } })
	check(ended == ["dm1"] and not Voice.ringing.has("dm1"), "aufgelegt, bevor du annimmst: Karte geht zu")
	Voice.handle({ "cmd": "DISPATCH", "evt": "VOICE_STATE_CREATE", "data": { "user": { "id": "42" } } })
	Voice.handle({ "cmd": "GET_CHANNEL", "data": { "id": "dm1", "voice_states": [{ "user": { "id": "42" } }] } })
	sent.clear()
	Voice.accept_call("dm1")
	check(sent.any(func(m): return str(m.cmd) == "SELECT_VOICE_CHANNEL" and str(m.args.channel_id) == "dm1"), "Annehmen: Discord tritt dem Anruf bei")
	Voice.incoming_call.disconnect(cb)
	Voice.call_ended.disconnect(cb2)
	Voice._dm_watch = {}
	Voice.transport = keep_transport
	Voice.state = "aus"
	Voice.demo = true

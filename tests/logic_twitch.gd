extends Node
## Twitch (Bereich Streams) ohne Netz: Geräte-Anmeldung (Antworten und Ablauf), Erneuern,
## GQL-Antworten aus eigenen Beispielen (tests/fixtures/twitch/) als Live-Karten, Übertragungen,
## Clips, Kategorien, Suche und Kanalseite, Helix-Antworten, Bildgrößen, Zahlen und Zeiten,
## Format für yt-dlp, Live im Player, Karten-Zeilen, Hinweise auf der Startseite.
## Aufruf: godot --headless --path . res://tests/logic_twitch.tscn

const LeisteOben := preload("res://src/core/leiste_oben.gd")
const P := preload("res://src/core/twitch_parse.gd")
const StreamCard := preload("res://src/ui/components/stream_card.gd")
const StreamsView := preload("res://src/ui/sections/streams_view.gd")
const VideoScript := preload("res://src/core/video.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")
const FIX := "res://tests/fixtures/twitch/"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _fix(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + file).replace("{BASE}", "http://t"))


func _ids(list: Array) -> Array:
	return list.map(func(v): return str(v.id))


func _ready() -> void:
	var now := int(Time.get_unix_time_from_datetime_string("2026-10-17T12:00:00"))

	print("Geräte-Anmeldung")
	var dr := P.device_request(P.TV_CLIENT)
	check(dr.client_id == "ue6666qo983tsx6so1t0vnawi233wa" and str(dr.scopes).contains("user_read") and not str(dr.scopes).contains("edit"),
			"Code-Anfrage mit der Kennung der Twitch-App am Fernseher, nur lesende Rechte")
	var pr := P.poll_request(P.TV_CLIENT, "dev")
	check(pr.grant_type == "urn:ietf:params:oauth:grant-type:device_code" and pr.device_code == "dev" and pr.has("scopes"), "Abfrage mit Geräte-Code (RFC 8628)")
	check(P.refresh_request("c", "r").grant_type == "refresh_token" and not P.refresh_request("c", "r").has("client_secret"),
			"Erneuern ohne Schlüssel (öffentliche Kennung)")
	var dc := P.parse_device_code(200,
			{ "device_code": "D", "user_code": "ABCDEFGH", "interval": 5, "expires_in": 1800,
			"verification_uri": "https://www.twitch.tv/activate?public=true&device-code=ABCDEFGH" })
	check(dc.ok and dc.user_code == "ABCDEFGH" and str(dc.url).contains("device-code=ABCDEFGH") and dc.short == "twitch.tv/activate",
			"QR-Code mit Code in der Adresse, kurze Adresse zum Eintippen")
	var dc2 := P.parse_device_code(200, { "device_code": "D", "user_code": "XYZ", "verification_uri": "javascript:alert(1)" })
	check(dc2.ok and str(dc2.url).begins_with("https://www.twitch.tv/activate?device-code=XYZ"), "nur https-Adressen von Twitch, sonst die eigene")
	check(not P.parse_device_code(400, { "status": 400, "message": "invalid client" }).ok
			and P.parse_device_code(400, { "status": 400, "message": "invalid client" }).error == P.ERR_CLIENT, "fremde Kennung abgelehnt: Hinweis auf eigene Client-ID")
	check(P.parse_device_code(0, null).error == P.ERR_OFFLINE, "kein Netz")

	print("Anmeldung und Erneuerung")
	var tk := P.parse_token(200, { "access_token": "a", "refresh_token": "r", "expires_in": 14400 }, now)
	check(tk.ok and tk.access == "a" and tk.refresh == "r" and int(tk.expires_at) == now + 14400, "Zugang, Erneuerung, Ablauf")
	var tk2 := P.parse_token(200, { "access_token": "a" }, now)
	check(tk2.ok and tk2.refresh == "" and int(tk2.expires_at) == 0, "wie die Twitch-Apps: ohne Erneuerung und ohne Ablauf")
	check(P.parse_token(400, { "status": 400, "message": "authorization_pending" }, now).state == "pending", "Twitch schickt { status, message }: warten")
	check(P.parse_token(400, { "error": "slow_down" }, now).state == "slow", "auch { error }: langsamer")
	check(P.parse_token(400, { "status": 400, "message": "invalid device code" }, now).state == "expired", "Code abgelaufen")
	check(P.parse_token(400, { "status": 400, "message": "Invalid refresh token" }, now).state == "revoked"
			and P.parse_token(400, { "message": "Invalid refresh token" }, now).error == P.ERR_EXPIRED, "Erneuerung ungültig: neu anmelden")
	check(P.parse_token(400, { "message": "access_denied" }, now).state == "denied" and P.parse_token(0, null, now).state == "error", "abgelehnt, kein Netz")
	check(not P.parse_token(500, {}, now).error.contains("500") and P.parse_token(500, {}, now).error.contains("noch einmal"),
			"unbekannter Fehler: Rat statt Nummer")
	check(P.parse_validate(200, { "login": "x", "user_id": "1", "client_id": "c" }).ok and not P.parse_validate(401, {}).ok, "validate: Konto und Kennung")

	print("Ablauf der Anmelde-Ebene")
	var flow := GeraeteCode.neu({ "interval": 1, "expires": 60 }, 0.0)
	check(flow.phase == "code" and float(flow.wait) == 1.0, "Start: warten im Abstand von Twitch")
	check(float(P.flow_step(flow, "slow", 1.0).wait) == 6.0 and P.flow_step(flow, "ok", 1.0).phase == "done", "langsamer, fertig")
	check(P.flow_step(flow, "pending", 61.0).phase == "error" and P.flow_step(flow, "denied", 1.0).msg.contains("abgelehnt"), "abgelaufen, abgelehnt")
	var f2 := flow
	for i in 3:
		f2 = P.flow_step(f2, "error", 1.0)
	check(f2.phase == "code" and P.flow_step(f2, "error", 1.0).phase == "error", "drei Störungen still, die vierte meldet sich")
	check(P.flow_step(flow, "error", 1.0, P.ERR_CLIENT).phase == "error", "Kennung abgelehnt: sofort Bescheid")

	print("GQL")
	var body := P.gql_body(P.Q_TOP, { "first": 3 })
	check(not body.has("operationName") and str(body.query).begins_with("query($first: Int)") and body.variables.first == 3, "freie Abfrage ohne Namen (wie Xtra)")
	check(P.Q_FOLLOWED.contains("currentUser {") and P.Q_FOLLOWED_ALT.contains("user { id login") and P.Q_FOLLOWED.contains("followedLiveUsers")
			and P.Q_ME.contains("currentUser"), "Gefolgt und Konto: currentUser, Rückfall user")
	check(P.gql_error({ "errors": [{ "message": "failed integrity check" }] }) == "failed integrity check" and P.gql_error({ "data": {} }) == "",
			"Fehlermeldung fürs Protokoll")
	check(P.gql_data({ "data": null, "errors": [] }).is_empty() and P.gql_data({ "data": { "x": 1 } }).x == 1, "Daten nur, wenn welche kamen")

	print("Beliebte Streams")
	var de := P.parse_streams(P.gql_data(_fix("streams_de.json")).streams, now)
	check(_ids(de) == ["tw:live:pixelbude", "tw:live:nordlichttv", "tw:live:kaffeekasse"], "drei Streams, leerer Knoten fällt weg (%s)" % str(_ids(de)))
	var s1: Dictionary = de[0]
	check(s1.url == "https://www.twitch.tv/pixelbude" and s1.channel == "Pixelbude" and bool(s1.live) and s1.twitch.kind == "live",
			"Adresse für yt-dlp, Kanal, LIVE")
	check(int(s1.twitch.viewers) == 18400 and s1.twitch.game == "Retro" and s1.info == "Retro  ·  18 Tsd. Zuschauer", "Kategorie und Zuschauer")
	check(int(s1.twitch.started) == now - 7200 and str(s1.twitch.avatar).contains("avatar_pixelbude"), "seit wann live, Profilbild")
	check(str(s1.thumb).contains("-800x450.png?t=") and not str(s1.thumb).contains("{width}"), "Vorschaubild groß genug für 4K, mit Zusatz gegen alte Bilder")
	check(de[1].title == "Ranked bis Diamant" and int(de[1].twitch.started) == now - 1788, "Titel aus broadcastSettings, Zeit mit Bruchteilen")
	check(de[2].title == "Kaffeekasse ist live", "ohne Titel: „… ist live“")
	var world := P.parse_streams(P.gql_data(_fix("streams_world.json")).streams, now)
	check(_ids(world) == ["tw:live:bigstreamer", "tw:live:pixelbude"], "kaputter Eintrag ohne Kanal fällt weg")

	print("Gefolgt")
	var fo := P.parse_followed(_fix("followed.json"), now)
	check(fo.ok and _ids(fo.items) == ["tw:live:pixelbude", "tw:live:speedwurm"], "nur Live-Kanäle, meiste Zuschauer zuerst (%s)" % str(_ids(fo.items)))
	check(fo.items[1].channel == "Speedwurm" and fo.items[1].twitch.login == "speedwurm" and fo.items[1].twitch.game == "Minecraft",
			"Kanal vom gefolgten Konto, wenn der Stream keinen mitbringt")
	check(fo.me.name == "Testkonto" and fo.me.login == "testkonto", "eigenes Konto")
	var alt := P.parse_followed({ "data": { "currentUser": _fix("followed.json").data.user } }, now)
	check(alt.ok and (alt.items as Array).size() == 2, "Rückfall currentUser")
	check(not P.parse_followed({ "data": { "user": null } }, now).ok, "ohne Konto: nicht ok")

	print("Kategorien, Suche, Kanal")
	var games := P.parse_games(P.gql_data(_fix("games.json")).games)
	check(_ids(games) == ["tw:g:509658", "tw:g:27284", "tw:g:32399"], "Kategorien, ohne ID fällt weg")
	check(str(games[0].thumb).ends_with("box_509658-540x720.png") and str(games[1].thumb).ends_with("-540x720.png"), "Spielhülle groß (feste Größe und Vorlage)")
	check(int(games[0].viewers) == 312000 and int(games[0].channels) == 4210 and games[0].title == "Just Chatting", "Zuschauer und Kanäle")
	var gp := P.parse_game(_fix("game.json"), now)
	check(gp.game.title == "Retro" and _ids(gp.items) == ["tw:live:pixelbude", "tw:live:modulhaus"], "Kategorie mit ihren Streams")
	var se := P.parse_search(_fix("search.json"), now)
	check((se.channels as Array).size() == 2 and se.channels[0].login == "pixelbude" and bool(se.channels[0].live) and not bool(se.channels[1].live),
			"Kanäle (klein geschrieben), live oder nicht")
	check((se.games as Array).size() == 1 and (se.streams as Array).size() == 1, "Kategorien und Streams in der Suche")
	var ch := P.parse_channel(_fix("channel.json"), now)
	check(ch.ok and ch.user.name == "Pixelbude" and int(ch.user.followers) == 48200 and str(ch.user.banner).contains("banner"),
			"Kanalseite: Name, Follower, Banner")
	check(ch.live.id == "tw:live:pixelbude" and (ch.videos as Array).size() == 3 and (ch.clips as Array).size() == 2, "live, drei Übertragungen, zwei Clips")
	var v0: Dictionary = ch.videos[0]
	check(v0.id == "tw:v:22000" and v0.url == "https://www.twitch.tv/videos/22000" and int(v0.duration) == 7200 and v0.twitch.kind == "vod"
			and str(v0.thumb).ends_with("-800x450.png"), "Übertragung: Adresse, Länge, Bild (%{width}-Vorlage)")
	var c0: Dictionary = ch.clips[0]
	check(c0.url == "https://clips.twitch.tv/SchnellerSprung0" and int(c0.duration) == 24 and str(c0.thumb).ends_with("clip_0-800x450.png"),
			"Clip: Adresse, Länge, Bild in Größe")
	var off := P.parse_channel(_fix("channel_offline.json"), now)
	check(off.ok and (off.live as Dictionary).is_empty() and off.user.banner == "" and off.user.about == "", "offline: kein Live, leere Felder statt „<null>“")
	check(not P.parse_channel({ "data": { "user": null } }, now).ok, "Kanal gibt es nicht")

	print("Helix (eigene Client-ID)")
	var hs := P.parse_helix_streams(_fix("helix_followed.json"), now)
	check(_ids(hs) == ["tw:live:pixelbude", "tw:live:speedwurm"] and hs[0].title == "Pixelbude ist live" and hs[1].info == "Minecraft  ·  4.711 Zuschauer",
			"Gefolgt über Helix, gleich wie GQL")
	check(P.parse_helix_user({ "data": [{ "id": "1", "login": "x", "display_name": "X" }] }).name == "X" and P.parse_helix_user({}).is_empty(),
			"eigenes Konto über Helix")
	check(
			P.parse_helix_games({ "data": [{ "id": "1", "name": "Retro", "box_art_url": "https://a/b-{width}x{height}.jpg" }] })[0].thumb == "https://a/b-540x720.jpg",
			"Kategorien über Helix")
	check(P.parse_helix_channels({ "data": [{ "broadcaster_login": "AB", "display_name": "Ab", "is_live": true }] })[0].login == "ab", "Kanalsuche über Helix")

	print("Bilder, Zahlen, Zeiten")
	check(P.sized("https://x/y-52x72.jpg", Vector2i(10, 20)) == "https://x/y-10x20.jpg"
			and P.sized("https://x/y-%{width}x%{height}.png", Vector2i(3, 4)) == "https://x/y-3x4.png", "Größe in festen Adressen und Vorlagen")
	check(P.sized("<null>", Vector2i(1, 1)) == ""
			and P.live_thumb("", "abc", 1200).begins_with("https://static-cdn.jtvnw.net/previews-ttv/live_user_abc-800x450.jpg?t=2"),
			"ohne Bild: Twitchs Vorschau-Adresse")
	check(P.bigger("https://x/y-800x450.png?t=1") == "https://x/y-1280x720.png?t=1", "großes Bild für oben")
	check(P.viewers_text(0) == "" and P.viewers_text(843) == "843 Zuschauer" and P.viewers_text(9237) == "9.237 Zuschauer"
			and P.viewers_text(45600) == "45 Tsd. Zuschauer" and P.viewers_text(1240000) == "1,2 Mio. Zuschauer", "Zuschauer auf Deutsch")
	check(P.count_text(4200) == "4.200" and P.count_text(1234567) == "1.234.567" and P.count_text(12) == "12", "Tausenderpunkt")
	check(P.uptime_text(now - 7500, now) == "Live seit 2 Std. 5 Min." and P.uptime_text(now - 600, now) == "Live seit 10 Min."
			and P.uptime_text(now - 7200, now) == "Live seit 2 Std." and P.uptime_text(0, now) == "", "wie lange schon live")
	check(P.iso_time("2026-10-17T12:00:00Z") == now and P.iso_time("") == 0 and P.iso_time("kaputt") == 0, "ISO-Zeit")
	check(P.explain(0) == P.ERR_OFFLINE and P.explain(401) == P.ERR_EXPIRED and P.explain(200, "x") == P.ERR_CHANGED and P.explain(503).contains("noch einmal")
			and not P.explain(503).contains("503"), "Meldungen auf Deutsch, ohne rohen Code")
	check(P.token_host_ok("https://gql.twitch.tv/gql") and not P.token_host_ok("https://gql.twitch.tv.evil.example/gql")
			and not P.token_host_ok("http://gql.twitch.tv/gql"), "Anmeldung nur an Twitch selbst")

	print("Abspielen")
	check(VideoScript.ytdl_format(s1, "1080", false) == "b[height<=1080]/b" and VideoScript.ytdl_format(s1, "ton", true) == "audio_only/ba/b",
			"Twitch: Bild und Ton zusammen (HLS), „Nur Ton“ = audio_only")
	check(VideoScript.ytdl_format({ "id": "abcdefghijk" }, "720", false) == VideoScript.QUALITY["720"], "YouTube unverändert")
	check(VideoScript.live_item(s1) and not VideoScript.live_item(v0) and not VideoScript.live_item({}), "Live nur bei Live-Streams (kein Spulen)")
	check(VideoScript.is_direct(s1) and VideoScript.url(v0) == "https://www.twitch.tv/videos/22000", "direkte Adresse an mpv/yt-dlp")
	check(load("res://src/ui/layers/video_qr.gd").link_for(c0) == "https://clips.twitch.tv/SchnellerSprung0", "Link aufs Handy: Twitch-Adresse")

	print("Karten und Startseite")
	var line := StreamCard.line_for(s1, 2000.0)
	check(line == "Pixelbude  ·  18 Tsd. Zuschauer  ·  Retro", "Zeile unter dem Titel: Kanal · Zuschauer · Kategorie (%s)" % line)
	var narrow := StreamCard.line_for(s1, 300.0)
	check(narrow.begins_with("Pixelbude") and not narrow.contains("Retro"), "zu schmal: Kategorie fällt zuerst weg (%s)" % narrow)
	check(StreamCard.line_for(games[0], 300.0) == "312 Tsd. Zuschauer", "Kategorie: Zuschauer")
	check(StreamCard.line_for(v0, 2000.0).begins_with("Pixelbude  ·  3.200 Aufrufe"), "Übertragung: Aufrufe und Alter")
	check(StreamsView.followed_hint(2, "") == "2 Kanäle live" and StreamsView.followed_hint(1, "x").contains("vorhin"), "Hinweis neben „Live – Gefolgt“")
	check(StreamsView.top_hint("") == "" and StreamsView.top_hint("x").contains("vorhin"), "Hinweis bei Störung")

	print("Ohne Anmeldung")
	check(Twitch != null and not Twitch.logged_in() and Twitch.status_text() == "Nicht angemeldet" and not Twitch.helix_mode(), "Twitch da, nicht angemeldet")
	check(Twitch.login_client() == P.TV_CLIENT and Twitch.token_client() == P.TV_CLIENT, "Standard: Kennung der Twitch-App am Fernseher")
	Config.set_value("accounts.twitch_client_id", "eigen123")
	check(Twitch.login_client() == P.TV_CLIENT, "eigene Client-ID nur, wenn gewählt")
	Config.set_value("accounts.twitch_mode", "eigen")
	check(Twitch.login_client() == "eigen123", "eigene Client-ID gewählt")
	Config.set_value("accounts.twitch_mode", "")
	Config.set_value("accounts.twitch_client_id", "")
	check(Twitch.resume_pos("tw:v:1") == 0.0 and Twitch.continue_list().is_empty() and Twitch.lang() == "DE" and Twitch.lang_name("en") == "Englisch",
			"Weiterschauen leer, Sprache Deutsch")
	check((Config.DEFAULTS.theme.sections as Array).has("apps") and LeisteOben.KIDS.has("streams"), "Streams als App oben in der Leiste")
	# Gemerkte Stellen von der Platte: nur Einträge der erwarteten Form, Zahlen in jeder Schreibweise.
	var st: Dictionary = Twitch.stellen_lesen({ "tw:v:1": { "pos": 120.5, "dur": "3600", "at": 5, "item": { "id": "tw:v:1" } }, "tw:v:2": 7,
		"tw:v:3": { "pos": 4 }, "tw:v:4": { "pos": [1], "dur": null, "at": "x", "item": { "id": "tw:v:4" } } })
	check(st.size() == 2 and float(st["tw:v:1"].pos) == 120.5 and float(st["tw:v:1"].dur) == 3600.0 and float(st["tw:v:4"].pos) == 0.0
			and int(st["tw:v:4"].at) == 0, "gemerkte Stellen: nur Einträge der erwarteten Form")
	check(Twitch.stellen_lesen(null).is_empty() and Twitch.stellen_lesen([1, 2]).is_empty(), "gemerkte Stellen: andere Art ergibt nichts")
	var alt_stellen: Dictionary = Twitch.resume
	Twitch.resume = st
	check(Twitch.continue_list().size() == 2 and Twitch.resume_pos("tw:v:1") == 120.5 and Twitch.progress_of("tw:v:4") == 0.0, "Weiterschauen liest sie ohne Abbruch")
	Twitch.resume = alt_stellen

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

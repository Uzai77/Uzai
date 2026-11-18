extends Node
## YouTube wie auf dem Fernseher (inoffiziell, SmartTube-Weg) ohne Netz: Startseite, Fortsetzung,
## Empfohlen und Browser-Aufbau aus eigenen Beispiel-Antworten (tests/fixtures/youtube_tv/),
## Abos (Kanäle und Feed in mehreren Varianten), Protokoll ohne Zugangsdaten,
## Zahlen und Alter aus deutschen und englischen Texten, Kennung aus der TV-Seite, Ablauf der
## Geräte-Anmeldung, Erneuern der Anmeldung, Hinweis bei Störung.
## Aufruf: godot --headless --path . res://tests/logic_youtube_tv.tscn

const P := preload("res://src/core/youtube_tv_parse.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const VideosView := preload("res://src/ui/sections/videos_view.gd")
const GeraeteCode := preload("res://src/core/geraete_code.gd")
const FIX := "res://tests/fixtures/youtube_tv/"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _fix(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + name))


func _ids(list: Array) -> Array:
	return list.map(func(v): return str(v.id))


func _ready() -> void:
	var now := 1_760_000_000

	print("Startseite (Fernseher-Antwort)")
	var p := P.parse_browse(_fix("home.json"), now, true)
	var sh: Array = p.shelves
	check(sh.size() == 2, "zwei Reihen: Shorts-Reihe fällt bei „Shorts ausblenden“ weg (%d)" % sh.size())
	check(str(sh[0].title) == "Für dich" and str(sh[1].title) == "Gaming",
			"erste Reihe ohne Titel heißt „Für dich“, dann „Gaming“ (%s)" % str(sh.map(func(s): return s.title)))
	check(str(p.continuation) == "HOMEPAGE2", "Weiterblättern-Marke der Seite, nicht die der Reihe (%s)" % str(p.continuation))
	var f: Array = sh[0].items
	check(_ids(f) == ["aaaaaaaaaa1", "aaaaaaaaaa2", "aaaaaaaaaa3"], "Für dich: Videos ohne Playlist und Short (%s)" % str(_ids(f)))
	var v1: Dictionary = f[0]
	check(v1.title == "Video Eins" and v1.channel == "Pixelbude" and v1.channel_id == "UCpixelbude00000000000a",
			"Titel, Kanal, Kanal-ID aus den Zeilen (nicht aus dem Menü)")
	check(int(v1.duration) == 754 and int(v1.views) == 1200000 and int(v1.published) == now - 3 * 86400, "Länge 12:34, 1,2 Mio. Aufrufe, vor 3 Tagen")
	check(str(v1.thumb).contains("hqdefault") and not bool(v1.live) and not bool(v1.short) and str(v1.src) == "tv", "größtes Vorschaubild, Herkunft „tv“")
	var v2: Dictionary = f[1]
	check(bool(v2.live) and int(v2.duration) == 0 and int(v2.views) == 1234, "Live-Kachel: LIVE-Abzeichen, Zuschauer als Zahl")
	var v3: Dictionary = f[2]
	check(int(v3.duration) == 3723 and int(v3.views) == 1500000 and int(v3.published) == now - 14 * 86400, "englisch: 1:02:03, 1.5M views, 2 weeks ago")
	var g: Array = sh[1].items
	check(_ids(g) == ["ggggggggg01", "ggggggggg02"], "doppelte Kachel in einer Reihe nur einmal")
	check(int(g[1].views) == 0 and int(g[1].published) == now - 60, "„Keine Aufrufe“, „vor 1 Minute“")
	var with_shorts := P.parse_browse(_fix("home.json"), now, false)
	check((with_shorts.shelves as Array).size() == 3 and str(with_shorts.shelves[2].title) == "Shorts" and bool(with_shorts.shelves[2].items[0].short),
			"mit Shorts: eigene Reihe, als Short markiert")
	check((with_shorts.shelves[0].items as Array).size() == 4, "Short in „Für dich“ nur ohne Ausblenden")

	print("Weiterblättern")
	var m := P.parse_browse(_fix("home_more.json"), now, true, "Mehr für dich")
	check((m.shelves as Array).size() == 1 and str(m.shelves[0].title) == "Musik" and str(m.continuation) == "HOMEPAGE3",
			"Fortsetzung: Reihe „Musik“, nächste Marke")
	check(int(m.shelves[0].items[0].views) == 3000000000 and int(m.shelves[0].items[0].published) == now - 365 * 86400, "3 Mrd. Aufrufe, vor 1 Jahr")
	var m2 := P.parse_browse(_fix("home_more2.json"), now, true)
	check(str(m2.continuation) == "" and int(m2.shelves[0].items[0].views) == 50000, "letzte Seite ohne Marke, 50 Tsd. Aufrufe")

	print("Empfohlen zum Video (next)")
	var rel := P.parse_next(_fix("next.json"), "aaaaaaaaaa1", now, true)
	check(_ids(rel) == ["rrrrrrrrr01", "rrrrrrrrr02", "rrrrrrrrr03"], "alle Reihen flach, ohne das Video selbst und ohne Doppelte (%s)" % str(_ids(rel)))
	check(int(rel[1].views) == 1, "„1 Aufruf“")

	print("Browser-Aufbau und neue View Models (falls YouTube umbaut)")
	var w := P.parse_browse(_fix("web.json"), now, true)
	check((w.shelves as Array).size() == 1 and str(w.shelves[0].title) == "Für dich", "lose Videos landen in „Für dich“, Shorts-Reihe fällt weg")
	check(_ids(w.shelves[0].items) == ["llllllllll1", "vvvvvvvvvv1"], "lockupViewModel und videoRenderer, Mix-Playlist nicht (%s)" % str(_ids(w.shelves[0].items)))
	var lk: Dictionary = w.shelves[0].items[0]
	check(lk.title == "Lockup Video" and lk.channel == "Kanal Neu" and lk.channel_id == "UClockup000000000000000a" and int(lk.duration) == 485
			and int(lk.views) == 45678 and int(lk.published) == now - 7200, "lockupViewModel: Titel, Kanal, Länge, Aufrufe, Alter")
	var vr: Dictionary = w.shelves[0].items[1]
	check(vr.channel == "Alter Kanal" and int(vr.duration) == 201 and int(vr.views) == 7890 and int(vr.published) == now - 86400,
			"videoRenderer: Kanal, 3:21, 7.890 Aufrufe, vor 1 Tag")
	check(str(w.continuation) == "WEBNEXT", "Marke aus continuationItemRenderer")
	var ws := P.parse_browse(_fix("web.json"), now, false)
	check((ws.shelves as Array).size() == 2 and str(ws.shelves[1].items[0].id) == "sssssssssh3", "Web-Short mit Shorts sichtbar")

	print("Unbekannte oder kaputte Antworten")
	check((P.parse_browse({ "contents": { "somethingNew": { "x": 1 } } }, now).shelves as Array).is_empty(),
			"unbekannter Aufbau: keine Reihen (dann Rückfall auf die Abos)")
	check((P.parse_browse(null, now).shelves as Array).is_empty() and (P.parse_browse("text", now).shelves as Array).is_empty(),
			"null und Text: leer statt Absturz")
	check(P.video_from("tileRenderer", { "contentId": "kurz" }, now).is_empty(), "Kachel ohne gültige ID oder Titel: kein Video")
	check(P.parse_next({}, "x", now).is_empty(), "next ohne Inhalt: leer")

	print("Zahlen und Alter")
	check(P.parse_views("1,2 Mio. Aufrufe") == 1200000 and P.parse_views("12.345 Aufrufe") == 12345 and P.parse_views("345K views") == 345000,
			"Aufrufe: Mio., Tausenderpunkt, K")
	check(P.parse_views("1,234 views") == 1234 and P.parse_views("2 Mrd. Aufrufe") == 2000000000 and P.parse_views("vor 3 Tagen") == -1,
			"Komma als Tausender (englisch), Mrd., kein Aufruf-Text")
	check(P.parse_views("12 Tsd. Aufrufe") == 12000 and P.parse_views("No views") == 0, "Tsd., No views")
	check(P.parse_age("Gestreamt vor 2 Stunden", now) == now - 7200 and P.parse_age("Streamed 5 days ago", now) == now - 5 * 86400, "gestreamt / streamed")
	check(P.parse_age("vor 2 Monaten", now) == now - 60 * 86400 and P.parse_age("Pixelbude", now) == 0 and P.parse_age("3 Tage", now) == 0,
			"Monate; ohne „vor“/„ago“ kein Alter")
	check(P.parse_clock("1:02:03") == 3723 and P.parse_clock("0:59") == 59 and P.parse_clock("LIVE") == 0 and P.parse_clock("12") == 0,
			"Länge aus der Uhrzeit-Schreibweise")
	check(P.text_of({ "runs": [{ "text": "a" }, { "text": "b" }] }) == "ab" and P.text_of({ "simpleText": "x" }) == "x" and P.text_of({ "content": "y" }) == "y"
			and P.text_of(null) == "", "Texte aus runs, simpleText, content")

	print("Fernseher-Kennung (wie SmartTube aus der TV-Seite)")
	var html := FileAccess.get_file_as_string(FIX + "tv.html")
	check(P.base_js_url(html) == "/s/_/kabuki/_/js/k=kabuki.base.de.abc123/am=AAAE/base.js", "Skript-Adresse aus der TV-Seite")
	var c := P.client_from_js(FileAccess.get_file_as_string(FIX + "base.js"))
	check(str(c.get("id", "")) == "111111111111-fakeclient.apps.googleusercontent.com" and str(c.get("secret", "")) == "fakesecret123",
			"Client-ID und Schlüssel aus dem Skript (auch über einen Zeilenumbruch)")
	check(P.client_from_js("var x = 1;").is_empty() and P.base_js_url("<html></html>") == "", "nichts gefunden: leer (dann die bekannte öffentliche Kennung)")

	print("Geräte-Anmeldung: Antworten")
	var dc := P.parse_device_code(200,
			{ "device_code": "d", "user_code": "ABCD-EFGH", "verification_url": "https://www.google.com/device", "expires_in": 1800, "interval": 5 })
	check(bool(dc.ok) and dc.user_code == "ABCD-EFGH" and dc.url == "https://www.google.com/device" and int(dc.interval) == 5, "Code, Adresse, Abstand")
	check(P.parse_device_code(200, { "device_code": "d", "user_code": "U" }).url == P.ACTIVATE_URL, "ohne Adresse: youtube.com/activate")
	check(not bool(P.parse_device_code(0, null).ok) and str(P.parse_device_code(0, null).error) == P.ERR_OFFLINE, "kein Netz: deutsche Meldung")
	check(str(P.parse_device_code(401, { "error": "invalid_client" }).error) == P.ERR_CLIENT, "Kennung abgelehnt: Hinweis auf Rückfall")
	var req := P.device_request("cid", "dev")
	check(req.scope == P.SCOPE and req.device_model == "ytlr::" and req.client_id == "cid", "Anfrage wie die TV-App (Bereich, Gerätemodell)")

	print("Geräte-Anmeldung: Ablauf")
	var fl := GeraeteCode.neu({ "interval": 5, "expires": 300 }, 1000.0)
	check(fl.phase == "code" and float(fl.wait) == 5.0, "Start: warten, alle 5 s fragen")
	fl = P.flow_step(fl, "pending", 1005.0)
	check(fl.phase == "code" and float(fl.wait) == 5.0, "noch nicht bestätigt: weiter warten")
	fl = P.flow_step(fl, "slow", 1010.0)
	check(fl.phase == "code" and float(fl.wait) == 10.0, "„langsamer“: 5 s mehr Abstand")
	var fe := fl
	for i in 3:
		fe = P.flow_step(fe, "error", 1015.0 + i)
	check(fe.phase == "code" and int(fe.misses) == 3, "drei Netzfehler: still weiter warten")
	fe = P.flow_step(fe, "error", 1020.0, P.ERR_OFFLINE)
	check(fe.phase == "error" and str(fe.msg) == P.ERR_OFFLINE, "beim vierten: Meldung")
	check(P.flow_step(fl, "error", 1012.0, P.ERR_CLIENT).phase == "error", "Kennung abgelehnt: sofort Meldung")
	check(P.flow_step(fl, "denied", 1012.0).msg.contains("abgelehnt"), "am Handy abgelehnt")
	check(P.flow_step(fl, "pending", 1301.0).msg.contains("abgelaufen"), "Zeit um: abgelaufen")
	var done := P.flow_step(fl, "ok", 1012.0)
	check(done.phase == "done" and P.flow_step(done, "error", 1013.0).phase == "done", "bestätigt: fertig (bleibt fertig)")

	print("Anmeldung und Erneuern")
	var tk := P.parse_token(200, { "access_token": "a", "refresh_token": "r", "expires_in": 3600 }, now)
	check(bool(tk.ok) and tk.access == "a" and tk.refresh == "r" and int(tk.expires_at) == now + 3600, "Anmeldung: Zugang, Erneuerung, Ablauf")
	var rf := P.parse_token(200, { "access_token": "b", "expires_in": 3599 }, now)
	check(bool(rf.ok) and rf.refresh == "", "Erneuern: neue Zugangs-Anmeldung, die alte Erneuerung bleibt")
	check(P.parse_token(428, { "error": "authorization_pending" }, now).state == "pending" and P.parse_token(403, { "error": "slow_down" }, now).state == "slow",
			"warten, langsamer")
	check(P.parse_token(400, { "error": "invalid_grant" }, now).state == "revoked"
			and str(P.parse_token(400, { "error": "invalid_grant" }, now).error) == P.ERR_EXPIRED, "widerrufen/abgelaufen: neu anmelden")
	check(P.parse_token(0, null, now).state == "error" and P.parse_token(400, { "error": "expired_token" }, now).state == "expired", "kein Netz, Code abgelaufen")

	print("Anfragen, Meldungen, Sicherheit")
	var b := P.body({ "browseId": "FEwhat_to_watch" }, "de", "DE")
	check(b.browseId == "FEwhat_to_watch" and b.context.client.clientName == "TVHTML5" and b.context.client.hl == "de" and b.context.client.gl == "DE",
			"browse mit Fernseher-Client, Sprache und Land")
	check(P.explain(0) == P.ERR_OFFLINE and P.explain(400) == P.ERR_CHANGED and P.explain(403).contains("abgelehnt") and P.explain(500).contains("noch einmal")
			and not P.explain(500).contains("500"), "Meldungen auf Deutsch, ohne rohen Code")
	check(P.token_host_ok("https://s.youtube.com/api/stats/playback?x") and P.token_host_ok("https://www.youtube.com/youtubei/v1/browse"),
			"Anmeldung nur an YouTube selbst")
	check(not P.token_host_ok("https://example.com/api/stats") and not P.token_host_ok("https://youtube.com.evil.example/x")
			and not P.token_host_ok("http://s.youtube.com/x"), "nicht an fremde Adressen oder ohne https")
	check(P.token_host_ok("http://127.0.0.1:1/x", "http://127.0.0.1:1"), "Testserver nur, wenn ausdrücklich gesetzt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	check(P.cpn(rng).length() == 16, "Wiedergabe-Kennung mit 16 Zeichen")
	check(P.parse_account_name(_fix("accounts.json")) == "Testkonto" and P.parse_account_name({}) == "", "Kontoname aus accounts_list")
	check(P.tracking_url(_fix("player.json")).begins_with("{BASE}/api/stats/playback") and P.tracking_url({}) == "", "Adresse fürs Melden aus dem Player")

	print("Hinweis bei Störung (Videos → Startseite)")
	check(VideosView.tv_hint_text(false, false, "x") == "" and VideosView.tv_hint_text(true, true, "") == "", "ohne Anmeldung oder ohne Fehler: kein Hinweis")
	check(VideosView.tv_hint_text(true, false, P.ERR_CHANGED).contains("Abos") and VideosView.tv_hint_text(true, true, P.ERR_OFFLINE).contains("vorhin"),
			"Rückfall auf Abos bzw. Stand von vorhin")

	print("Ohne Anmeldung")
	var tv: Node = YouTube.tv
	check(tv != null and not tv.logged_in() and not tv.active() and tv.status_text() == "Nicht angemeldet", "YouTube.tv da, nicht angemeldet")
	check(not tv.has_more() and (await tv.related("aaaaaaaaaa1")).is_empty(), "ohne Anmeldung: keine Empfehlungen, keine Anfrage")
	check(bool(Config.get_value("youtube.tv_history", true)) == false, "Gesehenes melden: Standard aus")

	print("Abos (FEsubscriptions, Fernseher)")
	var sb := P.parse_subs(_fix("subs.json"), now, true)
	check((sb.channels as Array).map(func(c): return str(c.id)) == ["UCaaaaaaaaaaaaaaaaaaaaaa", "UCbbbbbbbbbbbbbbbbbbbbbb"],
			"Kanäle aus den Reitern links, „Alle“ und kaputte Kennung nicht (%s)" % str(sb.channels))
	check(str(sb.channels[0].title) == "Alpha Kanal" and str(sb.channels[1].title) == "Beta Kanal", "Namen aus simpleText und runs")
	check(str(sb.channels[0].thumb) == "https://yt3.ggpht.com/alpha=s176" and str(sb.channels[1].thumb) == "https://yt3.ggpht.com/beta=s88",
			"größtes Kanalbild, // ergänzt")
	check(_ids(sb.videos) == ["sssssssss01", "sssssssss02"], "Feed der Abos: jedes Video einmal (%s)" % str(_ids(sb.videos)))
	check(str(sb.videos[0].channel) == "Alpha Kanal" and str(sb.videos[0].channel_id) == "UCaaaaaaaaaaaaaaaaaaaaaa" and int(sb.videos[0].published) == now - 7200,
			"Video mit Kanal, Kennung und Alter")
	check(str(sb.continuation) == "SUBS2", "Weiterblättern-Marke")
	var chs := P.parse_subs(_fix("channels.json"), now, true)
	check((chs.channels as Array).map(func(c): return str(c.title)) == ["Gamma Kanal", "Alpha Kanal", "Beta Kanal"] and (chs.videos as Array).is_empty(),
			"Kanalliste als Kachel, lockupViewModel und gridChannelRenderer (%s)" % str(chs.channels))
	check(str(chs.channels[1].thumb) == "https://yt3.ggpht.com/alpha2" and str(chs.channels[0].id) == "UCcccccccccccccccccccccc", "Bild aus sources, Kennung aus dem Verweis")
	var only := P.parse_subs(_fix("subs_videos_only.json"), now, true)
	check((only.channels as Array).is_empty() and (only.videos as Array).size() == 2, "nur Feed: keine Kanäle aus Videos-Verweisen")
	var abgeleitet := P.channels_from_videos(only.videos)
	check(abgeleitet.size() == 1 and str(abgeleitet[0].id) == "UCdddddddddddddddddddddd" and str(abgeleitet[0].title) == "Delta Kanal",
			"Kanäle aus dem Feed abgeleitet, je Kanal einmal")
	var leer := P.parse_subs({ "contents": { "tvBrowseRendererV9": { "neu": [1, 2] } } }, now, true)
	check((leer.channels as Array).is_empty() and (leer.videos as Array).is_empty() and P.parse_subs(null, now).channels.is_empty(), "Unbekanntes: leer, kein Absturz")
	check(P.channel_id_ok("UCaaaaaaaaaaaaaaaaaaaaaa") and not P.channel_id_ok("UC../../x") and not P.channel_id_ok("FEsubscriptions")
			and not P.channel_id_ok("UC" + "a".repeat(40)), "Kanal-Kennung streng geprüft")
	var mix := YouTube.feed_mischen([{ "id": "rrrrrrrrr01", "published": 100 }, { "id": "sssssssss01", "published": 50 }],
			[{ "id": "sssssssss01", "published": 60 }, { "id": "sssssssss02", "published": 200 }, { "id": "kaputt", "published": 999 }])
	check(_ids(mix) == ["sssssssss02", "rrrrrrrrr01", "sssssssss01"], "RSS und Abo-Feed gemischt: jedes einmal, neueste zuerst (%s)" % str(_ids(mix)))
	# Livestreams haben kein Alter (published 0): Sie standen ganz hinten und waren in der Reihe nie zu sehen.
	var mix_live := YouTube.feed_mischen([{ "id": "rrrrrrrrr01", "published": 100 }, { "id": "lllllllll01", "published": 90 }],
			[{ "id": "lllllllll01", "published": 0, "live": true }, { "id": "sssssssss02", "published": 200 }, { "id": "lllllllll02", "published": 0, "live": true }])
	var ids_live := _ids(mix_live)
	check(ids_live.size() == 4 and ids_live.slice(0, 2).has("lllllllll01") and ids_live.slice(0, 2).has("lllllllll02")
			and ids_live.slice(2) == ["sssssssss02", "rrrrrrrrr01"], "Livestreams zuerst, dann neueste zuerst (%s)" % str(ids_live))
	check(YouTube.nur_live(mix_live).size() == 2, "Live-Stand aus dem Abo-Feed gewinnt gegen RSS (dort ein normales Video)")
	var tv_now := int(Time.get_unix_time_from_system())
	check(VideosView.neu_gruppe({ "live": true, "published": 0 }, tv_now, 0) == 0 and VideosView.neu_gruppe({ "published": tv_now }, tv_now, 0) == 1
			and VideosView.neu_gruppe({ "published": 0 }, tv_now, 0) == 4, "Reiter Neu: „Gerade live“ ganz oben, sonst nach Tag")

	print("Suche: Livestreams")
	var lu := YouTube.live_search_url("  Worlds Finale & mehr ")
	check(lu == "https://www.youtube.com/results?search_query=Worlds%20Finale%20%26%20mehr&sp=EgJAAQ%253D%253D",
			"Adresse mit Filter „Live“, Suchwort kodiert (%s)" % lu)
	# So liefert yt-dlp die Suche mit Filter „Live“: kein Kanalname, keine Kennung – nur Adressen.
	var lj := '{"_type":"playlist","id":"worlds finale","title":"worlds finale","entries":[' + \
		'{"id":"lZuPs7-uGy4","title":"Finals","live_status":"is_live","channel_url":"https://www.youtube.com/channel/UCusFj6v3_2lrM1VyvzaJ_BA","uploader_url":"https://www.youtube.com/@Pixel%C3%9Cbude"},' + \
		'{"id":"GF6X9zOHW-M","title":"Vorher","live_status":"was_live","channel_url":"https://www.youtube.com/channel/../../x","uploader_url":null},' + \
		'{"id":"Ysbbich_sTE","title":"Ohne Adressen","live_status":"is_live"}]}'
	var ll := YouTube.parse_ytdlp(lj, true)
	check(ll.size() == 3 and ll[0].live and not ll[1].live, "Live-Stand aus live_status")
	if ll.size() == 3:
		check(ll[0].channel_id == "UCusFj6v3_2lrM1VyvzaJ_BA" and ll[0].channel == "@PixelÜbude", "Kanal aus den Adressen (%s, %s)" % [ll[0].channel_id, ll[0].channel])
		check(ll[1].channel_id == "" and ll[1].channel == "", "Kaputte Kanal-Adresse: keine Kennung (%s)" % ll[1].channel_id)
		check(ll[2].channel == "" and ll[2].channel_id == "", "Ohne Adressen: leer")
	var normal := YouTube.from_ytdlp({ "id": "aaaaaaaaaaa", "title": "x", "channel": "Echt", "channel_id": "UCecht", "uploader_url": "https://www.youtube.com/@anders" })
	check(normal.channel == "Echt" and normal.channel_id == "UCecht", "Normale Suche: Kanalname und Kennung bleiben")

	print("Protokoll ohne Zugangsdaten")
	var form := P.shape({ "responseContext": { "a": 1 }, "contents": { "tvBrowseRendererV9": { "neu": [{ "x": "geheim" }] } } })
	check(form == "contents{tvBrowseRendererV9{neu{[1]x}}}" and not form.contains("geheim"), "Aufbau nur aus Schlüsseln (%s)" % form)
	var ls := P.log_sicher("Bearer ya29.abcDEF refresh_token=1//0gXYZ code: 4/0Abc device_code\":\"dev1 ok")
	check(not ls.contains("abcDEF") and not ls.contains("0gXYZ") and not ls.contains("4/0Abc") and not ls.contains("dev1") and ls.contains("ok"),
			"Marken und Codes unkenntlich (%s)" % ls)
	check(YouTube.tv.art_von("browse", { "browseId": "FEsubscriptions" }) == "browse FEsubscriptions"
			and YouTube.tv.art_von("browse", { "browseId": "UCaaaaaaaaaaaaaaaaaaaaaa" }) == "browse Kanal"
			and YouTube.tv.art_von("browse", { "continuation": "geheim" }) == "browse Fortsetzung" and YouTube.tv.art_von("next", { "videoId": "x" }) == "next",
			"Art der Anfrage ohne Kennungen")
	check(VideosView.abos_kopf(false, "", true, 3).begins_with("Angemeldet") and VideosView.abos_kopf(false, "", true, 3).ends_with("3 Abos"),
			"Abos-Kopf: Fernseher-Anmeldung kurz, ohne Hinweis (der steht bei der Anmeldung)")
	check(VideosView.abos_leer_text(true, true, "") == "Deine Abos werden von YouTube geholt …" and VideosView.abos_leer_text(true, false, P.ERR_OFFLINE) == P.ERR_OFFLINE,
			"leere Abos: lädt bzw. sagt, warum")

	print("Große Antworten im Hintergrund lesen")
	var heim: Variant = _fix("home.json")
	var direkt := P.parse_browse(heim, now, true)
	var leer_p := { "shelves": [], "continuation": "" }
	var klein: Dictionary = await YouTube.tv._lesen({ "ok": true, "bytes": 2000, "data": heim }, P.parse_browse.bind(heim, now, true), leer_p)
	var vor := Time.get_ticks_msec()
	var gross: Dictionary = await YouTube.tv._lesen({ "ok": true, "bytes": 2_000_000, "data": heim }, P.parse_browse.bind(heim, now, true), leer_p)
	check(JSON.stringify(klein) == JSON.stringify(direkt) and JSON.stringify(gross) == JSON.stringify(direkt) and not (direkt.shelves as Array).is_empty(),
			"klein gleich, groß im Hilfsfaden: beide wie der direkte Aufruf (%d ms)" % (Time.get_ticks_msec() - vor))
	var ohne: Dictionary = await YouTube.tv._lesen({ "ok": false, "code": 500, "data": null }, P.parse_browse.bind(heim, now, true), leer_p)
	check((ohne.shelves as Array).is_empty(), "ohne Antwort: das leere Ergebnis, der Leser läuft nicht")
	var bruch: Variant = await YouTube.tv._lesen({ "ok": true, "bytes": 2_000_000 }, func() -> Variant: return null, [])
	check(bruch is Array and (bruch as Array).is_empty(), "liefert der Hilfsfaden nichts Passendes, kommt das leere Ergebnis")
	var neben: Array = []
	for i in 4:
		neben.append(Arbeit.auftrag(P.parse_subs.bind(_fix("subs.json"), now, true)))
	var haupt := P.parse_subs(_fix("subs.json"), now, true)
	for a in neben:
		if not a.fertig:
			await a.erledigt
	check(neben.all(func(a) -> bool: return JSON.stringify(a.wert) == JSON.stringify(haupt)) and not (haupt.videos as Array).is_empty(),
			"vier Hilfsfäden und der Hauptfaden lesen zugleich dasselbe (Muster und Tabellen nur gelesen)")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

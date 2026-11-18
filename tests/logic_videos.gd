extends Node
## Logik des Bereichs Videos ohne Oberfläche: Zeile unter den Karten, Farbfelder, Kanal-Angaben
## aus yt-dlp, Tage im Reiter „Neu“, Link aufs Handy, Endzeit im Player.
## Aufruf: godot --headless --path . res://tests/logic_videos.tscn

const VideoCard := preload("res://src/ui/components/video_card.gd")
const VideosView := preload("res://src/ui/sections/videos_view.gd")
const VideoQr := preload("res://src/ui/layers/video_qr.gd")
const VideoPlayer := preload("res://src/ui/layers/video_player.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Zeile unter den Karten")
	var font := UzTheme.font("regular")
	var fs := UzTheme.size("s")
	var parts := [["Speedrun Deutschland", 0], ["1,2 Mio. Aufrufe", 2], ["Vor 5 Tagen", 1]]
	var wide := VideoCard.fit_parts(parts, 2000.0, font, fs)
	check(wide == "Speedrun Deutschland  ·  1,2 Mio. Aufrufe  ·  Vor 5 Tagen", "passt alles: Kanal, Aufrufe, Alter (%s)" % wide)
	var full_w := font.get_string_size(wide, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := VideoCard.fit_parts(parts, full_w - 4.0, font, fs)
	check(mid == "Speedrun Deutschland  ·  Vor 5 Tagen", "zu eng: zuerst fallen die Aufrufe weg (%s)" % mid)
	var two_w := font.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var narrow := VideoCard.fit_parts(parts, two_w - 4.0, font, fs)
	check(narrow == "Speedrun Deutschland", "noch enger: nur der Kanal (%s)" % narrow)
	check(not narrow.ends_with("·") and not mid.contains("…"), "nie ein abgeschnittenes „· …“")
	check(VideoCard.fit_parts([["Nur ein Kanal mit sehr langem Namen", 0]], 10.0, font, fs) == "Nur ein Kanal mit sehr langem Namen",
			"der Kanal selbst bleibt (kürzt dann das Label)")
	var v := { "id": "zzTestVid01", "channel": "Pixelbude", "views": 47000, "published": int(Time.get_unix_time_from_system()) - 3 * 86400 }
	var m1 := VideoCard.meta_text(v, true, 2000.0)
	check(m1.begins_with("Pixelbude  ·  47 Tsd. Aufrufe  ·  "), "Kanal, Aufrufe, Alter für ein Video (%s)" % m1)
	check(not VideoCard.meta_text(v, false, 2000.0).contains("Pixelbude"), "ohne Kanal auf der Kanalseite")
	check(VideoCard.left_text(3120) == "noch 52 Min." and VideoCard.left_text(4320) == "noch 1 Std. 12 Min." and VideoCard.left_text(3600) == "noch 1 Std."
			and VideoCard.left_text(20) == "noch 1 Min.", "Restzeit kurz und deutsch")

	print("Farbfelder statt Bild")
	var p1 := VideoCard.poster_for("Pixelbude")
	var p2 := VideoCard.poster_for("Pixelbude")
	check(p1 != null and p1 == p2, "gleicher Kanal, gleiche Farbe (zwischengespeichert)")
	check(VideoCard.poster_texture({ "channel": "Pixelbude", "title": "x" }) == p1, "Farbe kommt vom Kanal, nicht vom Titel")
	var img := p1.get_image()
	check(img.get_width() == 64 and img.get_height() == 36, "klein gerechnet (64×36), weich vergrößert")
	var tl := img.get_pixel(4, 3)
	var br := img.get_pixel(60, 33)
	check(tl.get_luminance() > br.get_luminance(), "oben links heller als unten rechts")

	print("Kanal-Angaben aus yt-dlp")
	var j := '{"id":"UCx","channel":"Pixelbude","channel_follower_count":212000,"thumbnails":[' + \
		'{"url":"https://yt3.example/banner-1060","width":1060,"height":175,"id":"0"},' + \
		'{"url":"https://yt3.example/banner-2120","width":2120,"height":351,"id":"1"},' + \
		'{"url":"https://yt3.example/avatar-900","width":900,"height":900,"id":"7"},' + \
		'{"url":"https://yt3.example/banner-full","id":"banner_uncropped"},' + \
		'{"url":"https://yt3.example/avatar-full","id":"avatar_uncropped"}],"entries":[]}'
	var meta := YouTube.parse_channel_meta(j)
	check(str(meta.get("banner", "")) == "https://yt3.example/banner-2120", "breitestes Banner (%s)" % str(meta.get("banner", "")))
	check(str(meta.get("avatar", "")) == "https://yt3.example/avatar-full", "Profilbild in voller Größe")
	check(int(meta.get("followers", 0)) == 212000, "Abonnenten")
	var meta2 := YouTube.parse_channel_meta('{"thumbnails":[{"url":"https://yt3.example/b","id":"banner_uncropped"},{"url":"https://yt3.example/a","width":176,"height":176}],"channel_follower_count":null}')
	check(str(meta2.get("banner", "")) == "https://yt3.example/b" and str(meta2.get("avatar", "")) == "https://yt3.example/a" and not meta2.has("followers"),
			"ohne breites Banner: das ungeschnittene; fehlende Zahl ist kein Fehler")
	check(YouTube.parse_channel_meta("kein json").is_empty() and YouTube.parse_channel_meta('{"thumbnails":"x"}').is_empty(),
			"kaputte Antwort: leer statt Absturz")
	check(YouTube.followers_text(212000) == "212 Tsd. Abonnenten" and YouTube.followers_text(1240000) == "1,2 Mio. Abonnenten"
			and YouTube.followers_text(1500) == "1.500 Abonnenten" and YouTube.followers_text(1) == "1 Abonnent" and YouTube.followers_text(0) == "",
			"Abonnenten als Text")

	print("Neu: nach Tagen")
	var bias := 0
	var now := 1_760_000_000 - (1_760_000_000 % 86400) + 15 * 3600     # 15 Uhr
	check(VideosView.day_group(now - 3600, now, bias) == 0, "vor einer Stunde: heute")
	check(VideosView.day_group(now - 16 * 3600, now, bias) == 1, "gestern Abend: gestern")
	check(VideosView.day_group(now - 4 * 86400, now, bias) == 2, "vor vier Tagen: diese Woche")
	check(VideosView.day_group(now - 9 * 86400, now, bias) == 3, "vor neun Tagen: älter")
	var feed := [{ "published": now - 600 }, { "published": now - 7200 }, { "published": now - 20 * 3600 }, { "published": 0 }]
	check(VideosView.fresh_count(feed, now, bias) == 2, "Zahl am Reiter: nur was heute kam")
	check(VideosView.region_name("de") == "Deutschland" and VideosView.region_name("CH") == "der Schweiz" and VideosView.region_name("FR") == "FR",
			"Region als Wort")

	print("Link aufs Handy und Player")
	check(VideoQr.link_for({ "id": "ihA_2O76UMF" }) == "https://youtu.be/ihA_2O76UMF", "kurzer Link zum Video")
	check(VideoQr.link_for({ "id": "kaputt" }) == "https://www.youtube.com/", "ohne gültige ID: Startseite statt kaputtem Link")
	check(VideoPlayer.ends_text(600.0, 1.0, true) == "Pausiert", "pausiert: keine Endzeit")
	check(VideoPlayer.ends_text(600.0, 2.0, false).begins_with("Endet um "), "Endzeit mit Geschwindigkeit")
	var QR := load("res://src/core/qr.gd")
	var rows: Array = QR.encode("https://youtu.be/ihA_2O76UMF", "M")
	check(rows.size() >= 25, "QR-Code für den Link (%d Module)" % rows.size())

	print("Laden ohne Ruckeln")
	var rss := ('<?xml version="1.0"?><feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">'
		+ '<entry><yt:videoId>ihA_2O76UMF</yt:videoId><yt:channelId>UC1</yt:channelId><title>Tom &amp; Jerry</title><link rel="alternate" href="https://www.youtube.com/watch?v=ihA_2O76UMF"/>'
		+ '<author><name>Kanal</name></author><published>2026-10-10T12:00:00+00:00</published><media:group><media:title>x</media:title><media:description>Text &#39;mit&#39; &amp; Zeichen</media:description></media:group></entry></feed>').to_utf8_buffer()
	var off: Array = await YouTube._parse_off(rss)
	check(off.size() == 1 and str(off[0].title) == "Tom & Jerry" and off == YouTube.parse_rss(rss), "RSS im Hilfsthread gelesen, gleiches Ergebnis")
	# Kennungen und Titel aus Feeds und von yt-dlp: nur in der bekannten Form.
	check(YouTube._unescape("A&#0;B&#x202E;C&#228;&amp;lt;") == "ABCä&lt;", "Titel: Zeichen-Nummern ohne Steuerzeichen – " + YouTube._unescape("A&#0;B&#x202E;C&#228;&amp;lt;").c_escape())
	check(YouTube.from_ytdlp({ "id": "abcDEF123-_", "title": "x" }).size() > 0 and YouTube.from_ytdlp({ "id": "../../../x?", "title": "x" }).is_empty()
			and YouTube.from_api({ "id": "a/b?c=d&e=f" }).is_empty(), "Video-Kennung: nur Buchstaben, Ziffern, - und _")
	check(YouTube.kanal_ok("UCabcdefghijklmnopqrstuv") and not YouTube.kanal_ok("") and not YouTube.kanal_ok("UC../../watch?v=x") and not YouTube.kanal_ok("UC ab"),
			"Kanal-Kennung: nichts mit Pfad, Anfrage oder Leerzeichen")
	check((await YouTube.channel_videos("x/../y")).is_empty(), "Kanal mit fremder Kennung: gar nicht erst gefragt")
	var cookies_alt: Variant = Config.get_value("youtube.cookies", "")
	Config.set_value("youtube.cookies", "firefox:/fremd/profil")
	check(YouTube.cookie_args().is_empty(), "Cookies: nur ein Browser aus der Auswahl")
	Config.set_value("youtube.cookies", "firefox")
	check(YouTube.cookie_args() == PackedStringArray(["--cookies-from-browser", "firefox"]), "Cookies: Firefox aus der Auswahl geht")
	Config.set_value("youtube.cookies", cookies_alt)
	check(YouTube.ids_key([{ "id": "a" }, { "id": "b" }]) == "a,b" and YouTube.ids_key([]) == "", "Vergleich nach Videos")
	var vv = VideosView.new()
	vv.sub = "fuerdich"
	var keep_recs: Array = YouTube.recs
	YouTube.recs = [{ "id": "a" }]
	check(not vv._wants_rebuild("feed_loading") and not vv._wants_rebuild("recs_loading"), "Für dich: Laden allein baut nicht neu")
	check(vv._wants_rebuild("feed") and vv._wants_rebuild("recs"), "Für dich: neue Videos bauen neu")
	vv.sub = "start"
	check(vv._wants_rebuild("feed_loading"), "Neu: „wird aktualisiert …“ erscheint")
	YouTube.recs = keep_recs
	vv.free()

	print("Lautstärke im Player (YouTube und Filme)")
	var keep_vol: Variant = Config.get_value("youtube.volume", 100)
	check(Video.volume_clamp(140) == 130 and Video.volume_clamp(-5) == 0 and Video.volume_clamp("85") == 85 and Video.volume_clamp(null) == 100
			and Video.volume_clamp(72.6) == 72, "Stufe 0…130, kaputte Werte → 100")
	check(Video.volume_cmds(85, true) == [["set_property", "volume", 85], ["script-message-to", "uzai_osd", "volume", "85"]],
			"mpv: Wert setzen und in Uzais Leiste anzeigen (Video vorn)")
	check(Video.volume_cmds(40, false) == [["set_property", "volume", 40]], "Uzai darüber: nur der Wert (Uzai zeigt den Pegel selbst)")
	var heard: Array = []
	var on_vol := func(l: int) -> void: heard.append(l)
	Video.volume_changed.connect(on_vol)
	Config.set_value("youtube.volume", 100)
	check(Video.volume(Video.VOLUME_STEP) == 105 and int(Config.get_value("youtube.volume", 0)) == 105, "hoch: +5, gespeichert für das nächste Video")
	Video.set_volume(128)
	check(Video.volume(5) == 130 and Video.volume(5) == 130, "über 130 nicht hinaus (mpv volume-max)")
	Video.set_volume(3)
	check(Video.volume(-5) == 0 and Video.volume(-5) == 0, "unter 0 nicht hinab")
	check(heard.size() == 7 and heard[-1] == 0, "jede Änderung meldet sich (Pegel im Player, Guide): %s" % str(heard))
	Video.volume_changed.disconnect(on_vol)
	check(Video.osd_hints().any(func(h): return h[0] == "ud" and h[1] == "Lautstärke"), "Leiste in mpv nennt ↕ Lautstärke")
	var Guide := load("res://src/ui/layers/guide.gd")
	check(Guide.volume_target("spiel", false, true, {}, false) == "video" and Guide.volume_level_text("video", 115, false) == "Video 115 %",
			"Guide, Reiter Spiel über einem Video: LT/RT = Video-Lautstärke mit echtem Pegel")
	var Glyph := load("res://src/ui/components/glyph.gd")
	var g = Glyph.new()
	g.cmd = "ud"
	g.px = 27
	g._resize()
	check(g.custom_minimum_size == Vector2(27, 27), "Tastenzeichen ↕ (Steuerkreuz hoch/runter) in der Hinweisleiste")
	g.free()
	# Richtungen gehen an eine Ebene mit nav_dir, auch ohne Fokus (vorher schluckte der erste Druck
	# nach einem Fokusverlust das Zurückholen des Fokus).
	var fl := DirLayer.new()
	Nav.layers.append(fl)
	get_viewport().gui_release_focus()
	Nav._fire("up")
	Nav._fire("down")
	Nav._fire("left")
	Nav.layers.erase(fl)
	check(fl.got == ["up", "down", "left"], "hoch/runter/links ohne Fokus erreichen den Player: %s" % str(fl.got))
	fl.free()
	Config.set_value("youtube.volume", keep_vol)

	print("Sicherheit: fremde Adressen und Texte an mpv (Punkt 73)")
	check(Video.safe_url("https://cdn.example/film x\"a.mkv") == "https://cdn.example/film%20x%22a.mkv", "Leerzeichen und Anführungszeichen als %-Code")
	check(Video.safe_url("HTTP://cdn.example/a\\b") == "HTTP://cdn.example/a%5Cb" and Video.safe_url("https://a/b\nc") == "https://a/bc",
			"Rückstrich als %-Code, Steuerzeichen raus")
	var bad_urls := ["file:///C:/Windows/win.ini", "\\\\server\\share\\a.mkv", "C:\\Filme\\a.mkv", "edl://a.mkv,0,10", "memory://x", "av://lavfi:testsrc",
			"javascript:alert(1)", "ytdl://x", ""]
	check(bad_urls.all(func(u: String) -> bool: return Video.safe_url(u) == ""), "nur http(s): keine Dateien, Freigaben oder mpv-Sonderadressen")
	check(Video.url({ "url": "file:///C:/x.mkv", "movies": { "id": "tt1" } }) == "" and Video.url({ "url": "https://a/b.mkv", "movies": {} }) == "https://a/b.mkv",
			"Addon-Stream: nur http(s)")
	check(Video.url({ "id": "dQw4w9WgXcQ" }) == "https://www.youtube.com/watch?v=dQw4w9WgXcQ" and Video.url({ "id": "abc\" --script=x" }) == "",
			"YouTube-Kennung geprüft")
	check(Video.arg_text("Film \"X\"\n\\") == "Film 'X'", "Titel: ohne Anführungszeichen, Steuerzeichen und Rückstrich am Ende")
	var sa := Video.stream_args(
			{ "headers": { "User-Agent": "UA\" --script=\\\\h\\s.lua", "X-Evil\" --x": "1", "Referer": "https://r/", "Origin": "https://o" }, "media_title": "T\"itel",
			"movies": {} })
	check(not Array(sa).any(func(x: String) -> bool: return x.contains("\"")), "keine Anführungszeichen in den mpv-Argumenten: " + str(sa))
	check(not Array(sa).any(func(x: String) -> bool: return x.contains("X-Evil")) and Array(sa).has("--http-header-fields-append=Origin: https://o"),
			"ungültiger Kopfzeilen-Name verworfen, gültiger bleibt")
	var wa := Helper.win_args(PackedStringArray(["a\"b", "C:\\x y\\", "plain\\", "x\ny", "--opt=ok"]), true)
	check(wa == PackedStringArray(["a'b", "C:\\x y\\\\", "plain\\", "xy", "--opt=ok"]),
			"Windows-Argumente: „\"“ wird „'“, Rückstrich am Ende in Anführungszeichen verdoppelt (%s)" % str(wa))
	check(Helper.win_args(PackedStringArray(["a\"b"]), false) == PackedStringArray(["a\"b"]), "unter Linux unverändert")

	print("Tonspur und Untertitel im Filme-Player (Fehler 33)")
	var raw := [{ "id": 1, "type": "video", "lang": "" }, { "id": 1, "type": "audio", "lang": "ger", "selected": true, "demux-channel-count": 6 },
		{ "id": 2, "type": "audio", "lang": "eng", "title": "Original", "demux-channel-count": 2 },
			{ "id": 3, "type": "audio", "lang": "ger", "demux-channel-count": 6 },
		{ "id": 1, "type": "sub", "lang": "eng", "title": "English" }, { "id": 2, "type": "sub", "lang": "und", "external": true },
		{ "id": "x", "type": "audio" }, "kaputt", { "id": 9, "type": "sub", "lang": "x".repeat(40), "title": "y".repeat(200) }]
	var tr := Video.parse_tracks(raw)
	check(tr.size() == 6 and tr.all(func(t): return str(t.type) in ["audio", "sub"]), "nur Ton und Untertitel, kaputte Einträge verworfen (%d)" % tr.size())
	check(str(tr[5].lang).length() <= 16 and str(tr[5].title).length() <= 80, "fremde Texte gekürzt")
	check(Video.track_label(tr[0]) == "Deutsch  ·  5.1" and Video.track_label(tr[1]) == "Englisch  ·  Original  ·  Stereo",
			"Namen: Sprache, Titel, Kanäle (%s | %s)" % [Video.track_label(tr[0]), Video.track_label(tr[1])])
	check(Video.track_label(tr[3]) == "Englisch", "Titel, der nur die Sprache wiederholt, fällt weg (%s)" % Video.track_label(tr[3]))
	check(Video.track_label(tr[4]) == "Spur 2", "unbekannte Sprache: Spur-Nummer")
	var ao := Video.track_options(tr, "audio")
	check(ao.size() == 3 and str(ao[2][1]) == "Deutsch  ·  5.1 (2)", "gleiche Namen bekommen eine Nummer (%s)" % str(ao))
	var so := Video.track_options(tr, "sub")
	check(so[0] == ["no", "Aus"] and so.size() == 4, "Untertitel: „Aus“ zuerst, dann die Spuren")
	check(Video.selected_track(tr, "audio") == 1 and str(Video.selected_track(tr, "sub")) == "no", "gewählte Spur: Ton 1, Untertitel aus")
	var keep_lang: Variant = Config.get_value("video.audio_lang", "")
	Video.tracks = tr
	Video.set_track("audio", 2)
	check(Video.selected_track(Video.tracks, "audio") == 2 and str(Config.get_value("video.audio_lang", "")) == "eng", "Tonspur gewählt: Sprache gemerkt")
	Video.set_track("sub", 1)
	check(Video.subs and Video.selected_track(Video.tracks, "sub") == 1, "Untertitel-Spur gewählt: Untertitel an")
	Video.set_track("sub", "no")
	check(not Video.subs and str(Video.selected_track(Video.tracks, "sub")) == "no", "„Aus“: Untertitel aus")
	check(Video.audio_langs("eng") == "en,eng,english" and Video.audio_langs("deu") == "de,ger,deu,german,deutsch" and Video.audio_langs("") == ""
			and Video.audio_langs("ja,x") == "jax", "--alang mit allen Schreibweisen, Fremdes ohne Komma")
	Config.set_value("video.audio_lang", keep_lang)
	Video.tracks = []
	check(Video.DEMO_TRACKS.size() == 6 and Video.track_options(Video.parse_tracks(Video.DEMO_TRACKS), "audio").size() == 3, "Vorführung: Film mit drei Tonspuren")

	print("Player-Protokoll und Fehlstart (Freund-Test 0.16.51: „MPV not loading“)")
	var PL := preload("res://src/core/player_log.gd")
	var env := { "USERPROFILE": "C:\\Users\\Dwz", "APPDATA": "C:\\Users\\Dwz\\AppData\\Roaming", "LOCALAPPDATA": "", "USERNAME": "Dwz" }
	var an: String = PL.anonym("Ordner C:/Users/Dwz/AppData/Roaming/Uzai/tools und D:\\Users\\Dwz\\x, C:\\Users\\Dwz", env)
	check(not an.contains("Dwz") and an.contains("%APPDATA%/Uzai/tools"), "ohne Benutzernamen und Pfade: " + an)
	check(PL.anonym("a\nb\tc", {}) == "abc", "ohne Steuerzeichen")
	var ml := "[   0.010][v][cplayer] Command line options\n[   1.2][e][ytdl_hook] ERROR: [youtube] abc: Sign in to confirm you’re not a bot\n[   1.3][e][cplayer] Exiting"
	check(str(PL.mpv_grund(ml).text).begins_with("YouTube verlangt"), "Bot-Prüfung erkannt")
	check(str(PL.mpv_grund("[0.1][w][ytdl_hook] youtube-dl failed: not found or not enough permissions").text).begins_with("yt-dlp startet nicht"),
			"yt-dlp fehlt oder gesperrt (Virenschutz)")
	check(str(PL.mpv_grund("[0.1][e][ytdl_hook] ERROR: [youtube] x: HTTP Error 403: Forbidden").text).contains("HTTP 403"), "HTTP 403")
	check(str(PL.mpv_grund("[0.1][e][ffmpeg] Failed to open https://x/y.mkv.").text) == "Die Quelle ließ sich nicht öffnen.", "Quelle kaputt")
	check(str(PL.mpv_grund("Error parsing option foo (option not found)").text).begins_with("mpv kennt eine Option"), "unbekannte Option")
	check(str(PL.mpv_grund("").text) == "mpv hat sich gleich wieder beendet." and str(PL.mpv_grund("").zeile) == "", "ohne Protokoll: allgemeiner Satz")
	var two := "[1][e][ytdl_hook] ERROR: Video unavailable\n[9][e][ytdl_hook] ERROR: HTTP Error 429: Too Many Requests"
	check(str(PL.mpv_grund(two).text).contains("429"), "das jüngste Video zählt (von hinten)")
	var rel := { "assets": [{ "name": "mpv-x86_64-v3-20251101-git-abc1234.7z", "browser_download_url": "https://github.com/x/v3.7z", "digest": "sha256:" + "a".repeat(64) },
		{ "name": "mpv-x86_64-20251101-git-abc1234.7z", "browser_download_url": "https://github.com/x/mpv.7z", "digest": "sha256:" + "b".repeat(64) },
		{ "name": "7zr.exe", "browser_download_url": "https://evil.example/7zr.exe", "digest": "sha256:" + "c".repeat(64) }] }
	var pick: Dictionary = YouTube.release_asset(rel, "^mpv-x86_64-[0-9]{8}-git-[0-9a-f]+\\.7z$")
	check(str(pick.get("url", "")) == "https://github.com/x/mpv.7z" and str(pick.get("sha", "")) == "b".repeat(64), "mpv-Paket mit GitHub-Prüfsumme")
	check(YouTube.release_asset(rel, "^7zr\\.exe$").is_empty(), "nur Downloads von github.com")
	var vsrc := FileAccess.get_file_as_string("res://src/core/video.gd")
	check(vsrc.contains("--log-file=") and vsrc.contains("_fail_start(") and vsrc.contains("Erneut versuchen"), "Fehlstart: Grund aus mpvs Protokoll, Meldung mit „Erneut versuchen“")
	var ysrc := FileAccess.get_file_as_string("res://src/core/youtube.gd")
	check(ysrc.contains("_unpack_7z(") and ysrc.contains("SEVENZ_RELEASES"), "Windows 10: .7z notfalls mit 7-Zip entpacken (tar.exe ohne LZMA)")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


class DirLayer extends Control:
	var got: Array = []

	func nav_dir(d: String) -> bool:
		got.append(d)
		return true

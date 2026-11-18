extends Node
## YouTube-Zusätze ohne Netz: SponsorBlock (Hash-Präfix, strenge Prüfung der Antwort, Sprung und
## „zurück“), Ton im Hintergrund (Zustände, Ende der Liste, Kopfleiste, Guide-Reiter) und Shorts
## (Quelle, Zusammenführen, Blättern, Qualität nach der Breite).
## Aufruf: godot --headless --path . res://tests/logic_youtube_extra.tscn

const VideoPlayer := preload("res://src/ui/layers/video_player.gd")
const GuideTon := preload("res://src/ui/components/guide_ton.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Main := preload("res://src/main.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_sponsorblock()
	_background()
	await _shorts()
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _sponsorblock() -> void:
	print("SponsorBlock: was das Netz sieht")
	check(YouTube.sb_prefix("dQw4w9WgXcQ") == "5f6b" and YouTube.sb_prefix("PtYgjmUhBel") == "3a2a", "Präfix: die ersten vier Zeichen des SHA-256")
	var url := YouTube.sb_url("dQw4w9WgXcQ", ["sponsor"])
	check(url.begins_with("https://sponsor.ajay.app/api/skipSegments/5f6b?categories="), "nur https, nur das Präfix im Pfad (%s)" % url)
	check(not url.contains("dQw4w9WgXcQ"), "die Video-ID selbst geht nie raus")
	check(YouTube.valid_id("dQw4w9WgXcQ") and YouTube.valid_id("a-b_c-d_e-f"), "echte IDs")
	check(not YouTube.valid_id("dQw4w9WgXc") and not YouTube.valid_id("dQw4w9WgXcQQ") and not YouTube.valid_id("../../etc/p")
			and not YouTube.valid_id("dQw4w9WgXc?") and not YouTube.valid_id("dQw4w9WgXcä"), "Fremdes (zu kurz, zu lang, Pfad, Sonderzeichen) fragt nie")
	check(YouTube.sb_categories(["intro", "evil\",\"x", "sponsor", "sponsor"]) == ["sponsor", "intro"],
			"nur bekannte Kategorien, feste Reihenfolge, keine doppelt")
	check(YouTube.sb_categories("sponsor").is_empty() and YouTube.sb_categories(null).is_empty(), "kaputte Einstellung: keine Kategorie")
	check(Config.DEFAULTS.youtube.sponsorblock == ["sponsor"], "Standard: nur Sponsoren überspringen")

	print("SponsorBlock: Antwort streng lesen")
	var id := "dQw4w9WgXcQ"
	var good := [{ "videoID": id, "videoDuration": 600.0, "segments": [
		{ "segment": [120.0, 150.5], "category": "sponsor", "actionType": "skip" },
		{ "segment": [10, 20], "category": "intro", "actionType": "skip" },
	] }]
	var segs := YouTube.parse_segments(good, id, ["sponsor", "intro"])
	check(segs.size() == 2 and segs[0].start == 10.0 and segs[1].end == 150.5, "gültige Abschnitte, sortiert")
	check(YouTube.parse_segments(good, id, ["sponsor"]).size() == 1, "nur die gewählten Kategorien")
	check(YouTube.parse_segments(good, "anderesVid1", ["sponsor"]).is_empty(), "nur dieses Video (die Antwort enthält viele)")
	var bad := [{ "videoID": id, "videoDuration": 300, "segments": [
		{ "segment": [-5, 20], "category": "sponsor" },
		{ "segment": [50, 40], "category": "sponsor" },
		{ "segment": [60, 60.4], "category": "sponsor" },
		{ "segment": [10, 90000], "category": "sponsor" },
		{ "segment": ["10", "20"], "category": "sponsor" },
		{ "segment": [10, INF], "category": "sponsor" },
		{ "segment": [NAN, 20], "category": "sponsor" },
		{ "segment": [10, 20, 30], "category": "sponsor" },
		{ "segment": "10-20", "category": "sponsor" },
		{ "segment": [10, 20], "category": "werbung" },
		{ "segment": [10, 20], "category": "sponsor", "actionType": "mute" },
		{ "segment": [10, 20], "category": "sponsor", "actionType": "full" },
		{ "segment": [400, 420], "category": "sponsor" },
		"kein Abschnitt",
		[10, 20],
	] }]
	check(YouTube.parse_segments(bad, id, ["sponsor"]).is_empty(),
			"kaputte Zahlen, Texte, Unendlich, falsche Längen, fremde Kategorien und Aktionen, nach dem Ende: alles fällt weg")
	check(YouTube.parse_segments({ "videoID": id }, id).is_empty() and YouTube.parse_segments("[]", id).is_empty() and YouTube.parse_segments(null, id).is_empty(),
			"keine Liste: nichts")
	check(YouTube.parse_segments([{ "videoID": id, "segments": "viel" }], id).is_empty(), "Abschnitte als Text: nichts")
	var many: Array = []
	for i in 200:
		many.append({ "segment": [i * 10.0, i * 10.0 + 5.0], "category": "sponsor" })
	check(YouTube.parse_segments([{ "videoID": id, "segments": many }], id).size() == YouTube.SB_MAX, "höchstens %d Abschnitte" % YouTube.SB_MAX)
	Config.set_value("youtube.sponsorblock", [])
	check((await YouTube.segments(id)).is_empty(), "alle Kategorien aus: SponsorBlock fragt gar nicht")
	Config.set_value("youtube.sponsorblock", ["sponsor"])
	check((await YouTube.segments("../x")).is_empty(), "ungültige ID: keine Anfrage, keine Abschnitte")

	print("Überspringen und zurück")
	var s2 := [{ "start": 30.0, "end": 52.0, "category": "sponsor" }, { "start": 100.0, "end": 110.0, "category": "intro" }]
	check(Video.skip_index(s2, 10.0, {}) == -1, "vor dem Abschnitt: nichts")
	check(Video.skip_index(s2, 30.0, {}) == 0 and Video.skip_index(s2, 45.0, {}) == 0, "im Abschnitt: überspringen")
	check(Video.skip_index(s2, 51.5, {}) == -1, "kurz vor dem Ende: kein Sprung mehr")
	check(Video.skip_index(s2, 45.0, { 0: true }) == -1 and Video.skip_index(s2, 105.0, { 0: true }) == 1, "jeder Abschnitt nur einmal")
	check(Video.skip_index(["kaputt", s2[1]], 105.0, {}) == 1, "Fremdes in der Liste stört nicht")
	var last := { "i": 0, "start": 30.0, "at": 1000 }
	check(Video.undo_open(last, 1000 + Video.UNDO_MS) and not Video.undo_open(last, 1001 + Video.UNDO_MS) and not Video.undo_open({}, 1000),
			"„zurück“ nur kurz nach dem Sprung")
	Video.active = true
	Video.sim = true
	Video.duration = 600.0
	Video.pos = 52.0
	Video.last_skip = { "i": 0, "start": 30.0, "at": Time.get_ticks_msec() }
	check(Video.undo_skip() and is_equal_approx(Video.pos, 30.0) and Video.last_skip.is_empty(), "links nach dem Sprung: zurück an den Anfang des Abschnitts")
	check(not Video.undo_skip(), "nur einmal")
	Video.active = false

	print("Hinweise")
	var tr_s := VideoPlayer.hints_for(true, false, false)
	check(str(tr_s[0][1]) == "Blättern" and str(tr_s[2][0]) == "rt", "Shorts: hoch/runter blättern, LT/RT Lautstärke")
	check(str(VideoPlayer.hints_for(false, true, false)[1][1]) == "Im Hintergrund" and str(VideoPlayer.hints_for(false, true, true)[1][1]) == "Bild in Bild",
			"Nur Ton: ≡ in den Hintergrund (Filme nicht)")
	check(str(Video.osd_hints(true)[1][1]) == "Blättern" and str(Video.osd_hints(false)[1][1]) == "Lautstärke", "Leiste in mpv: dieselben Tasten")


func _background() -> void:
	print("Ton im Hintergrund")
	Config.set_value("youtube.sponsorblock", [])
	Config.set_value("youtube.autoplay", true)
	var list := [
		{ "id": "bgTestVid01", "title": "Eins", "channel": "Kanal", "duration": 2 },
		{ "id": "bgTestVid02", "title": "Zwei", "channel": "Kanal", "duration": 2 },
	]
	Video.play(list, 0, { "audio": true, "background": true })
	check(Video.active and Video.sim and Video.audio_only and Video.background, "startet als Ton im Hintergrund")
	check(not Video.watching(), "kein Player: zählt nicht als „schaut gerade“ (Guide pausiert es nicht)")
	var np := Main.now_playing({ "title": "Song", "artist": "Band", "playing": true })
	check(str(np.title) == "Eins" and str(np.artist) == "Kanal" and bool(np.playing), "oben steht das Video statt der Musik")
	var tabs := GuideTon.tabs([["spiel", "Spiel"], ["musik", "Musik"]])
	check(tabs.size() == 3 and str(tabs[1][0]) == "ton", "Guide: Reiter „Video-Ton“ gleich nach „Spiel“")
	check(Guide.volume_target("ton", false, false, {}, false) == "video", "LT/RT im Reiter: die Lautstärke des Videos")
	check(GuideTon.status_text().begins_with("Nur Ton"), "Stand: „Nur Ton …“ (%s)" % GuideTon.status_text())
	Video._sim_step(0.7)
	Video._sim_step(3.0)
	check(Video.active and Video.index == 1 and str(Video.video.id) == "bgTestVid02", "am Ende: das nächste Video der Liste")
	Video._sim_step(0.7)
	Video._sim_step(3.0)
	check(not Video.active and not Video.background, "Liste zu Ende: Schluss, nichts bleibt hängen")
	check(GuideTon.tabs([["spiel", "Spiel"]]).size() == 1, "danach kein Reiter mehr")
	check(Main.now_playing({ "title": "Song" }).title == "Song", "oben wieder die Musik")
	Video.play(list, 0, { "audio": true })
	check(Video.active and not Video.background and Video.watching(), "Nur Ton im Player: noch nicht im Hintergrund")
	check(Video.to_background() and Video.background and not Video.watching(), "≡: in den Hintergrund")
	Video.play(list, 1)
	check(not Video.background and not Video.audio_only, "neues Video aus Uzai: wieder mit Bild im Player")
	Video.stop()
	Video.play([{ "id": "film1", "title": "Film", "movies": { "x": 1 }, "url": "https://example.org/f.mkv", "duration": 5 }], 0, { "audio": true })
	check(not Video.to_background() and not Video.background, "Filme bleiben im Player")
	Video.stop()
	Video.play(list, 0, { "background": true })
	check(not Video.background, "Hintergrund nur mit „Nur Ton“")
	Video.stop()
	Config.set_value("youtube.sponsorblock", ["sponsor"])


func _shorts() -> void:
	print("Shorts")
	check(YouTube.shorts_feed_url("UC_x5XG1OV2P6uZZ5FSM9Ttw") == YouTube.RSS + "playlist_id=UUSH_x5XG1OV2P6uZZ5FSM9Ttw",
			"Quelle: die öffentliche RSS-Liste der Shorts eines Kanals")
	check(YouTube.shorts_feed_url("UC_x5XG1OV2P6uZZ5FSM9&tw") == "" and YouTube.shorts_feed_url("UC_x5XG1OV2P6uZZ5FSM9T/w") == "",
			"fremde Zeichen in der Kanal-ID kommen nie in die Adresse")
	check(YouTube.shorts_feed_url("@pixelbude") == "" and YouTube.shorts_feed_url("UCzukurz") == "", "andere Kennungen: keine Anfrage")
	var a := [{ "id": "aaaaaaaaaa1", "published": 100 }, { "id": "aaaaaaaaaa2", "published": 300 }]
	var b := [{ "id": "aaaaaaaaaa1", "published": 100 }, { "id": "aaaaaaaaaa3", "published": 200 }, "kaputt"]
	var m := YouTube.merge_shorts([a, b])
	check(m.size() == 3 and str(m[0].id) == "aaaaaaaaaa2" and str(m[2].id) == "aaaaaaaaaa1", "jeder Short einmal, neueste zuerst")
	check(m.all(func(v: Dictionary) -> bool: return bool(v.short)), "alle als Short markiert")
	var big: Array = []
	for i in 300:
		big.append({ "id": "s%010d" % i, "published": i })
	check(YouTube.merge_shorts([big]).size() == YouTube.SHORTS_MAX, "höchstens %d" % YouTube.SHORTS_MAX)
	check(Video.ytdl_format({ "short": true }, "1080", false).contains("width<=1080") and not Video.ytdl_format({}, "1080", false).contains("width"),
			"Qualität bei Shorts nach der Breite")
	check(Video.ytdl_format({ "short": true }, "1080", true) == Video.QUALITY["ton"], "Nur Ton bleibt nur Ton")
	# VRR-Fernseher: SDR zuerst, mpv mit fester Bildrate und ohne eigenes Umschalten auf HDR.
	check(Video.ytdl_format({}, "1080", false).begins_with("bv*[height<=1080][dynamic_range=?SDR]+ba/"), "SDR-Fassung zuerst")
	check(Video.RUHIG_CONF.contains("video-sync=display-resample") and Video.RUHIG_CONF.contains("target-colorspace-hint=no"),
			"mpv: feste Bildrate, kein HDR-Umschalten")
	Config.set_value("youtube.sponsorblock", [])
	var list := [
		{ "id": "shTestVid01", "title": "S1", "duration": 30, "short": true },
		{ "id": "shTestVid02", "title": "S2", "duration": 30, "short": true },
		{ "id": "shTestVid03", "title": "S3", "duration": 30, "short": true },
	]
	Video.play(list, 1, { "shorts": true })
	check(Video.shorts and Video.pos == 0.0, "Shorts: von vorn")
	Video._sim_step(0.7)
	Video._sim_step(12.0)
	Video.prev()
	check(Video.index == 0, "hoch: gleich das davor (nicht erst an den Anfang)")
	Video.next()
	Video.next()
	check(Video.index == 2 and Video.pos == 0.0, "runter: das nächste, wieder von vorn")
	Video.stop()
	Video.play(list, 0)
	check(not Video.shorts, "normales Video: kein Shorts-Modus")
	Video.stop()
	Config.set_value("youtube.sponsorblock", ["sponsor"])
	await _shorts_flott(list)


## Shorts lagged while flipping through them because mpv started yt-dlp for every Short; now Uzai
## resolves the neighbors in advance and loads them directly while flipping. Each step also snaps
## into place instead of a held stick racing through, and the old Short slides out.
func _shorts_flott(list: Array) -> void:
	print("Shorts: vorab auflösen und einrasten")
	var gv := "https://rr3---sn-x.googlevideo.com/videoplayback?expire=1&itag=%d&sig=AB"
	var dash := JSON.stringify({ "id": "shTestVid02", "http_headers": { "User-Agent": "Mozilla/5.0 Test" },
		"requested_formats": [{ "url": gv % 248, "vcodec": "vp9", "acodec": "none" }, { "url": gv % 251, "vcodec": "none", "acodec": "opus" }] })
	var r := Video.parse_resolved(dash)
	check(str(r.get("v", "")) == gv % 248 and str(r.get("a", "")) == gv % 251 and str(r.get("ua", "")) == "Mozilla/5.0 Test",
			"yt-dlp-Antwort: Bild, Ton und User-Agent (%s)" % str(r))
	var one := Video.parse_resolved(JSON.stringify({ "url": gv % 18, "http_headers": {} }))
	check(str(one.get("v", "")) == gv % 18 and str(one.get("a", "")) == "", "ein Format mit beidem: nur eine Adresse")
	check(Video.parse_resolved("kein json").is_empty() and Video.parse_resolved("[]").is_empty(), "kaputte Antwort: nichts")
	check(Video.parse_resolved(JSON.stringify({ "url": "http://unsicher.example/v" })).is_empty()
		and Video.parse_resolved(JSON.stringify({ "requested_formats": [{ "url": "file:///C:/x", "vcodec": "h264" }] })).is_empty(),
			"nur https – kein http, keine Datei")
	var quote := Video.parse_resolved(JSON.stringify({ "url": "https://a.googlevideo.com/v?x=\" --script=b\"" }))
	check(not str(quote.get("v", "")).contains("\"") and not str(quote.get("v", "")).contains(" "), "Anführungszeichen und Leerzeichen maskiert")
	check(Video.parse_resolved("x".repeat(Video.PRE_MAX_BYTES + 1)).is_empty(), "zu große Antwort wird nicht gelesen")
	var cmds := Video.load_cmds(r, "https://www.youtube.com/watch?v=shTestVid02")
	check(cmds[0] == ["change-list", "audio-files", "clr", ""] and cmds.has(["change-list", "audio-files", "append", gv % 251])
		and cmds.back() == ["loadfile", gv % 248], "aufgelöst: mpv lädt Bild und Ton direkt (ohne yt-dlp)")
	var plain := Video.load_cmds({}, "https://www.youtube.com/watch?v=shTestVid02")
	check(plain == [["change-list", "audio-files", "clr", ""], ["loadfile", "https://www.youtube.com/watch?v=shTestVid02"]],
			"nicht aufgelöst: wie bisher über yt-dlp, ohne Tonspur des vorigen Shorts")
	check(Video.pre_key({ "id": "shTestVid02" }, "f") == "shTestVid02|f" and Video.pre_key({ "id": "a b" }, "f") == "", "nur echte Kennungen")
	# Zwischenspeicher: frisch nehmen, alt verwerfen.
	Video.quality = "1080"
	var v2: Dictionary = list[1]
	var key := Video.pre_key(v2, Video.ytdl_format(v2, "1080", false))
	Video._pre[key] = { "v": gv % 248, "a": "", "ua": "", "at": Time.get_ticks_msec() }
	check(str(Video._pre_take(v2).get("v", "")) == gv % 248, "frisch aufgelöst: wird genommen")
	Video._pre[key] = { "v": gv % 248, "a": "", "ua": "", "at": Time.get_ticks_msec() - Video.PRE_AGE_MS - 1 }
	check(Video._pre_take(v2).is_empty() and not Video._pre.has(key), "zu alt: verworfen, dann wieder über yt-dlp")
	# Gleiten in mpv: die Richtung geht mit dem Laden mit.
	Video.play(list, 1, { "shorts": true })
	Video.next()
	check(Video._swipe == 0, "Richtung nur für genau ein Laden")
	var lua := FileAccess.get_file_as_string("res://assets/mpv/uzai_osd.lua")
	check(lua.contains("register_script_message(\"swipe\"") and lua.contains("playback-restart"), "mpv-Leiste: Einrasten bis das neue Short läuft")
	var src := FileAccess.get_file_as_string("res://src/core/video.gd")
	check(src.contains("\"swipe\", str(swipe)") and src.contains("_cmd(c, shorts)"), "Gleiten im selben Paket wie das Laden, über den freien Helfer-Weg")
	# Player: ein Schritt rastet ein, ein gehaltener Stick rast nicht durch.
	Video.stop()
	Video.play(list, 0, { "shorts": true })
	var host := Control.new()
	add_child(host)
	var p = VideoPlayer.new()
	p.open(host)
	await get_tree().process_frame
	p._short_at = 0
	p._short_step(1)
	check(Video.index == 1, "runter: ein Short weiter")
	p._short_step(1)
	check(Video.index == 1, "gleich danach (Stick gehalten): bleibt eingerastet")
	while Time.get_ticks_msec() - p._short_at <= VideoPlayer.SHORT_GAP_MS:
		await get_tree().process_frame
	p._short_step(1)
	check(Video.index == 2, "nach dem Einrasten: der nächste Schritt zählt (%d)" % Video.index)
	check(p._short_ghost.visible or not p._short_frame.visible, "Vorführung: das alte Short gleitet als zweiter Rahmen hinaus")
	Video.stop()
	if is_instance_valid(p):
		p.close()
	await get_tree().create_timer(0.4).timeout
	host.queue_free()

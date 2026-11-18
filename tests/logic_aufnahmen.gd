extends Node
## Logik von Uzais eigener Aufnahme (src/core/capture_logic.gd): Stücke des Rollpuffers, Clipwahl,
## Dateinamen, FFmpeg-Befehlszeilen, Kürzen, Speicherplatz, FFmpeg-Paket, wann der Puffer läuft,
## Teilen ans Handy, Bildrate messen, Discord (Freund oder Server-Kanal), Aufnahmen eines Spiels.
## Mit FFmpeg (UZAI_TEST_FFMPEG oder im PATH) zusätzlich ein echter Probelauf der Befehlszeile:
## eine künstliche Quelle wie ddagrab (ungleichmäßige Zeitstempel, fehlende Bilder) durch Puffer und
## „Clip speichern“ – der Clip muss genau die eingestellte Bildrate haben. Aufruf:
##   godot --headless --path . res://tests/logic_aufnahmen.tscn   → „Ergebnis: alles ok“

const L := preload("res://src/core/capture_logic.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await _run()


func _run() -> void:
	print("Rollpuffer")
	_buffer()
	print("Clip aus Stücken")
	_pick()
	print("Dateinamen")
	_names()
	print("Befehlszeilen")
	_args()
	print("Kürzen")
	_trim()
	print("Discord und Speicher")
	_limits()
	print("FFmpeg laden")
	_build()
	print("Wann läuft der Puffer")
	_block()
	print("Ans Handy")
	_share()
	print("Bildrate messen")
	_fps()
	print("Discord: Freund oder Server-Kanal")
	_discord()
	print("Aufnahmen eines Spiels")
	_belongs()
	print("Probelauf mit FFmpeg (feste Bildrate)")
	await _synthetic()
	print("Einstellungen")
	for k in L.DEFAULTS.keys():
		check(Config.DEFAULTS.capture.has(k) and typeof(Config.DEFAULTS.capture[k]) == typeof(L.DEFAULTS[k]) and Config.DEFAULTS.capture[k] == L.DEFAULTS[k],
				"Standard „%s“ gleich in Config und capture_logic" % k)
	check(str(Config.get_value("capture.via")) == "uzai" and str(Config.get_value("capture.length")) == "30" and not bool(Config.get_value("capture.mic")),
			"Standard: eigene Aufnahme, 30 s, Mikrofon aus")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _buffer() -> void:
	check(L.seg_keep(30) == 17 and L.seg_wrap(30) == 21, "30 s: 17 Stücke in der Liste, 21 im Kreis")
	check(L.seg_keep(15) == 10 and L.seg_keep(120) == 62 and L.seg_keep(0) == 3, "15 s, 120 s und 0 s")
	check(L.seg_wrap(120) < 1000, "Kreis passt zu seg%03d")
	var csv := "seg006.ts,12.121333,14.121333\nseg007.ts,14.121333,16.121333\n\n\"seg008.ts\",16.121333,18.121333\nkaputt\nseg009.ts,x,1\n"
	var segs := L.parse_seg_list(csv)
	check(segs.size() == 3 and str(segs[2].file) == "seg008.ts" and is_equal_approx(float(segs[0].start), 12.121333),
			"Liste des Segment-Muxers lesen (Anführungszeichen, kaputte Zeilen weg)")
	var live := L.live_segment(segs, 21)
	check(str(live.file) == "seg009.ts" and is_equal_approx(float(live.start), 18.121333), "gerade wachsendes Stück: das nächste")
	var wrapped := L.live_segment([{ "file": "seg020.ts", "start": 40.0, "end": 42.0 }], 21)
	check(str(wrapped.file) == "seg000.ts", "… im Kreis nach seg020 wieder seg000")
	check(str(L.live_segment([], 21).file) == "seg000.ts", "noch nichts fertig: seg000 wächst")


func _pick() -> void:
	var segs: Array = []
	for i in 17:
		segs.append({ "file": L.seg_file(i), "start": 10.0 + i * 2.0, "end": 12.0 + i * 2.0 })
	# fertig bis 44, live ab 44
	var live := { "file": "seg017.ts", "start": 44.0 }
	var p := L.pick_segments(segs, live, 45.3, 30.0)
	check(not p.is_empty() and str(p.files[0]) == "seg002.ts" and str(p.files[p.files.size() - 1]) == "seg017.ts",
			"30 s bis 45,3: ab dem Stück vor 15,3 bis zum wachsenden")
	check(is_equal_approx(float(p.start), 14.0) and is_equal_approx(float(p.duration), 31.3) and not bool(p.short),
			"Anfang an der Stückgrenze (bis 2 s länger), Ende genau beim Druck")
	var p2 := L.pick_segments(segs, live, 30.0, 30.0)
	check(str(p2.files[0]) == "seg000.ts" and str(p2.files[p2.files.size() - 1]) == "seg009.ts" and bool(p2.short),
			"Ende mitten im Puffer (Druck auf die Guide-Taste): nur Stücke davor, zu kurz gemeldet")
	check(not p2.files.has("seg010.ts"), "Stück, das erst beim Ende beginnt, fällt weg")
	var p3 := L.pick_segments([], { "file": "seg000.ts", "start": 0.3 }, 5.0, 30.0)
	check(p3.files == ["seg000.ts"] and is_equal_approx(float(p3.duration), 4.7), "gleich nach dem Start: nur das wachsende Stück")
	check(L.pick_segments([], {}, 5.0, 30.0).is_empty() and L.pick_segments([], { "file": "seg000.ts", "start": 5.0 }, 5.0, 30.0).is_empty(),
			"nichts vor dem Ende: kein Clip")
	check(is_equal_approx(L.stream_time(1000.5, 990.25), 10.25), "Stückzeit = Unix-Zeit − T0")
	var txt := L.concat_text(["C:/Users/a/AppData/Uzai/capture/puffer/seg001.ts", "D:\\Spiele\\It's.ts"])
	check(txt.begins_with("ffconcat version 1.0\n") and txt.contains("file 'C:/Users/a/AppData/Uzai/capture/puffer/seg001.ts'\n")
			and txt.contains("file 'D:\\Spiele\\It'\\''s.ts'"), "concat-Liste: Pfade wörtlich, ' maskiert")


func _names() -> void:
	var when := { "year": 2026, "month": 10, "day": 17, "hour": 8, "minute": 5, "second": 9 }
	check(L.stamp(when) == "2026-10-17 08-05-09", "Zeitstempel wie die Bildschirmfotos")
	check(L.capture_name("ELDEN RING", when, "mp4") == "ELDEN RING 2026-10-17 08-05-09.mp4", "Clipname: Spiel + Zeit")
	check(L.capture_name("Halo: Reach / MCC?", when, "png") == "Halo Reach MCC 2026-10-17 08-05-09.png", "verbotene Zeichen fallen weg")
	check(L.safe_title("  ...  ") == "Uzai" and L.safe_title("con") == "con_" and L.safe_title("A\tB\nC") == "A B C" and L.safe_title("Spiel.") == "Spiel",
			"leer → Uzai, CON, Steuerzeichen, Punkt am Ende")
	check(L.safe_title("x".repeat(100)).length() == 60, "höchstens 60 Zeichen")
	check(L.unique_name(["a.mp4", "a (2).mp4"], "a.mp4") == "a (3).mp4" and L.unique_name([], "a.mp4") == "a.mp4", "gleicher Name: (2), (3) …")
	var n := L.parse_name("C:/Videos/Uzai/Hollow Knight 2026-10-17 18-30-05 (gekürzt).mp4")
	check(str(n.title) == "Hollow Knight" and str(n.stamp) == "2026-10-17 18:30:05" and str(n.sort) == "20261017183005" and str(n.extra) == "gekürzt",
			"Name zurück: Titel, Zeit, Zusatz")
	var o := L.parse_name("Okami_2026-10-15_10-41.png")
	check(str(o.title).begins_with("Okami") and str(o.stamp) == "2026-10-15 10:41:00", "ältere Form ohne Sekunden")
	check(str(L.parse_name("Mein Video.mp4").title) == "Mein Video" and str(L.parse_name("Mein Video.mp4").stamp) == "", "fremde Namen bleiben")
	check(L.renamed("Hollow Knight 2026-10-17 18-30-05.mp4", "Boss: geschafft") == "Boss geschafft 2026-10-17 18-30-05.mp4", "Umbenennen: Zeit bleibt")
	check(L.renamed("Mein Video.mp4", "Neu") == "Neu.mp4", "Umbenennen ohne Zeit")
	check(L.kind_of("a.MP4") == "clip" and L.kind_of("b.png") == "shot" and L.kind_of("c.txt") == "", "Art aus der Endung")
	check(L.mime_for("a.mp4") == "video/mp4" and L.mime_for("b.PNG") == "image/png", "MIME-Typ fürs Handy")
	var groups := L.group_by_title([{ "title": "A", "mtime": 5 }, { "title": "B", "mtime": 9 }, { "title": "A", "mtime": 7 }])
	check(groups.size() == 2 and str(groups[0].title) == "B" and int((groups[1]["items"] as Array)[0].mtime) == 7,
			"Galerie: nach Spielen, zuletzt aufgenommen zuerst")
	check(L.mmss(0.4) == "0:00" and L.mmss(32.6) == "0:33" and L.mmss(600) == "10:00", "Länge als m:ss")
	check(L.size_text(37_400_000) == "37,4 MB" and L.size_text(2_500_000_000) == "2,5 GB" and L.size_text(10) == "1 KB", "Größe mit Komma")


func _args() -> void:
	check(L.fit_size(Vector2i(2560, 1440), "1080") == Vector2i(1920, 1080), "1440p → 1080p")
	check(L.fit_size(Vector2i(3440, 1440), "720") == Vector2i(1720, 720), "Ultrabreit behält das Seitenverhältnis")
	check(L.fit_size(Vector2i(1366, 768), "1080") == Vector2i(1366, 768), "nie hochskaliert")
	check(L.fit_size(Vector2i(1365, 767), "native") == Vector2i(1364, 766), "gerade Werte (NV12)")
	check(L.bitrate_kbps(Vector2i(1920, 1080), 60) == 15000 and L.bitrate_kbps(Vector2i(1280, 720), 30) < L.bitrate_kbps(Vector2i(1280, 720), 60),
			"Bitrate: 1080p60 15 Mbit/s, 30 Bilder/s weniger")
	check(L.bitrate_kbps(Vector2i(3840, 2160), 60) <= 60000 and L.bitrate_kbps(Vector2i(320, 200), 30) == 2500, "Bitrate begrenzt")
	var nv := L.enc_args("nvenc", 15000, 60)
	check(nv.has("h264_nvenc") and nv.has("15000k") and nv.has("22500k") and nv[nv.find("-g") + 1] == "120" and nv[nv.find("-bf") + 1] == "0",
			"NVENC: Bitrate, Spitze ×1,5, Schlüsselbild alle 2 s, keine B-Frames")
	check(L.enc_args("x264", 5000, 30).has("ultrafast") and L.enc_args("amf", 5000, 30).has("h264_amf") and L.enc_args("qsv", 5000, 30).has("h264_qsv"),
			"x264 ultrafast, AMF, Quick Sync")
	check(L.enc_args("nvenc", 1, 60).has("expr:gte(t,n_forced*2)"), "Schlüsselbilder genau auf den Stückgrenzen")
	var gpu := L.video_chain({ "kind": "dda", "output": 1 }, Vector2i(1920, 1080), 60, "nvenc", true, "{T0}")
	check(gpu.begins_with("ddagrab=output_idx=1:framerate=60:draw_mouse=0,setpts=") and gpu.contains("scale_d3d11=width=1920:height=1080:format=nv12")
			and gpu.ends_with("[v]") and not gpu.contains("hwdownload"), "Grafikkarte: ddagrab → setpts → scale_d3d11 (kein Umweg über den Arbeitsspeicher)")
	check(L.video_chain({ "kind": "dda" }, Vector2i(1920, 1080), 60, "qsv", true, "{T0}").contains("hwmap=derive_device=qsv,format=qsv"),
			"Quick Sync: auf QSV-Bilder abbilden")
	var cpu := L.video_chain({ "kind": "dda" }, Vector2i(1280, 720), 30, "x264", false, "{T0}")
	check(cpu.contains("hwdownload,format=bgra,setpts=") and cpu.contains("scale=1280:720") and cpu.ends_with("format=yuv420p[v]"),
			"x264 über den Arbeitsspeicher: BGRA holen, skalieren, yuv420p")
	var xg := L.video_chain({ "kind": "dda" }, Vector2i(1280, 720), 30, "x264", true, "{T0}")
	check(xg.ends_with("scale_d3d11=width=1280:height=720:format=nv12,hwdownload,format=nv12[v]") and not xg.contains("bgra"),
			"x264 schneller: Grafikkarte skaliert, nur NV12 in Zielgröße herunterladen")
	var gfx := L.video_chain({ "kind": "gfx_win" }, Vector2i(1280, 720), 60, "amf", true, "{T0}")
	check(gfx.begins_with("gfxcapture=hwnd={HWND}:max_framerate=60:capture_cursor=0:width=1280:height=720:resize_mode=scale_aspect") and not gfx.contains("fps=")
			and gfx.contains("scale_d3d11=format=nv12"), "Spielfenster: Windows.Graphics.Capture (feste Bildrate macht -fps_mode cfr)")
	check(L.video_chain({ "kind": "gfx_mon" }, Vector2i(1280, 720), 60, "nvenc", false, "{T0}").begins_with("gfxcapture=hmonitor={HMON}"),
			"Bildschirm über Windows.Graphics.Capture")
	check(L.setpts_filter("{T0}") == "setpts='if(eq(N,0),st(0,time(0)-{T0}-PTS*TB));PTS+ld(0)/TB'", "Bild auf die Uhr des Tons (T0)")
	var o := { "src": { "kind": "dda" }, "size": Vector2i(1920, 1080), "fps": 60, "enc": "nvenc", "gpu": true, "kbps": 15000,
		"sys": true, "mic": true, "pipe_sys": "\\\\.\\pipe\\uzai-cap-sys-1", "pipe_mic": "\\\\.\\pipe\\uzai-cap-mic-1", "dir": "C:/U/capture/puffer", "length": 30 }
	var a := L.record_args(o)
	check(a.find("-i") < a.find("-filter_complex") and a[a.find("-i") + 1] == "\\\\.\\pipe\\uzai-cap-sys-1" and a.has("{SYS_RATE}") and a.has("{MIC_RATE}"),
			"Ton zuerst (Eingang 0 und 1), Rate setzt der Helfer ein")
	var fc := a[a.find("-filter_complex") + 1]
	check(fc.contains("{T0}") and fc.ends_with(";[0:a][1:a]amix=inputs=2:duration=longest:normalize=0[a]") and a[a.find("-map", a.find("[v]")) + 1] == "[a]",
			"Spiel und Mikrofon gemischt (ohne Halbieren)")
	check(a[a.find("-segment_wrap") + 1] == "21" and a[a.find("-segment_list_size") + 1] == "17" and a[a.size() - 1] == "C:/U/capture/puffer/seg%03d.ts"
			and a.has("C:/U/capture/puffer/list.csv"), "Segment-Muxer: Kreis, Liste, Ordner")
	check(a.has("aac") and a[a.find("-segment_time") + 1] == "2" and a.has("mpegts"), "AAC, 2-s-Stücke als .ts")
	check(a[a.find("-fps_mode") + 1] == "cfr" and a[a.find("-r") + 1] == "60" and not a.has("vfr"),
			"feste Bildrate (cfr, 60) statt vfr: Lücken werden aufgefüllt und gezählt")
	check(a[a.find("-progress") + 1] == "C:/U/capture/puffer/progress.txt" and a[a.find("-stats_period") + 1] == "5"
			and a.find("-progress") < a.find("-f", a.find("-progress")), "Zähler alle 5 s nach progress.txt (vor dem Ausgang)")
	o.mic = false
	var a1 := L.record_args(o)
	check(not a1.has("{MIC_RATE}") and not a1[a1.find("-filter_complex") + 1].contains("amix") and a1[a1.find("-map", a1.find("[v]")) + 1] == "0:a",
			"nur Spielton: direkt 0:a")
	o.sys = false
	var a0 := L.record_args(o)
	check(not a0.has("-c:a") and not a0.has("f32le"), "ohne Ton: kein Audio")
	var c := L.concat_args("C:/l.txt", "C:/out.mp4", 33.3)
	check(c[c.find("-t") + 1] == "33.300" and c.has("copy") and c.has("+faststart") and c[c.size() - 1] == "C:/out.mp4" and c.has("concat"),
			"Clip: nur aneinanderhängen, bei 33,3 s abschneiden")
	var th := L.thumb_args("a.mp4", "a.jpg", 1.0)
	check(th.has("scale=480:-2") and th[th.find("-loglevel") + 1] == "info", "Vorschaubild 480 breit, mit Längenangabe")
	check(is_equal_approx(L.parse_duration("  Duration: 00:01:31.52, start: 1.4"), 91.52) and L.parse_duration("nichts") < 0.0, "Länge aus der Ausgabe von FFmpeg")
	var sh := L.shot_args({ "kind": "dda" }, "C:/b.png")
	check(sh[sh.find("-filter_complex") + 1] == "ddagrab=output_idx=0:framerate=10:draw_mouse=0,hwdownload,format=bgra[v]" and sh.has("-update"),
			"Bildschirmfoto: ein Bild in voller Größe")
	var att := L.attempts(false, "")
	check(att[0] == "dda|nvenc|gpu" and att.find("dda|x264|gpu") == att.find("dda|x264|cpu") - 1 and att[att.size() - 1] == "gfx_mon|x264|cpu",
			"Versuche: zuerst Grafikkarte, x264 erst mit Skalieren auf der Grafikkarte, zuletzt Windows.Graphics.Capture")
	check(L.attempts(false, "dda|amf|gpu")[0] == "dda|amf|gpu" and L.attempts(true, "")[0] == "gfx_win|nvenc|gpu",
			"was zuletzt lief, zuerst; Spielfenster zuerst, wenn gewählt")
	var sticky := L.attempts(false, "dda|amf|cpu")
	check(sticky[0] == "dda|amf|gpu" and sticky[1] == "dda|amf|cpu" and sticky.size() == att.size(),
			"lief zuletzt nur der langsame Weg: Grafikkarte desselben Kodierers trotzdem zuerst")
	var ap := L.attempt_parts("gfx_mon|qsv|gpu")
	check(str(ap.kind) == "gfx_mon" and str(ap.enc) == "qsv" and bool(ap.gpu), "Versuch zerlegen")


func _fps() -> void:
	var txt := "frame=600\nfps=60.0\nout_time_us=10000000\ndup_frames=0\ndrop_frames=0\nspeed=1.00x\nprogress=continue\n" \
		+ "frame=900\nout_time_ms=15000000\ndup_frames=60\ndrop_frames=0\nspeed=0.99x\nprogress=continue\n" \
		+ "frame=1800\nout_time_us=30000000\ndup_frames=330\ndrop_frames=12\nspeed=1x\nprogress=continue\nframe=19"
	var b := L.parse_progress(txt)
	check(b.size() == 3 and int(b[2].frame) == 1800 and int(b[2].dup) == 330 and is_equal_approx(float(b[1].t), 15.0) and is_equal_approx(float(b[1].speed), 0.99),
			"progress.txt lesen (out_time_us/_ms, Tempo, halber Block am Ende fällt weg)")
	var m := L.progress_fps(b, 20.0)
	check(is_equal_approx(float(m.out), 60.0) and is_equal_approx(float(m.src), (1200.0 - 330.0 + 12.0) / 20.0) and is_equal_approx(float(m.span), 20.0),
			"über 20 s: Datei 60 Bilder/s, Quelle nur 44,1 (aufgefüllte abgezogen, verworfene dazu)")
	check(L.fps_low(m, 60) and not L.fps_low({ "src": 58.0 }, 60) and not L.fps_low({}, 60), "unter 90 % der Zielrate: zu wenig")
	var line := L.fps_text(m, 60, "dda|nvenc|gpu")
	check(line.contains("44,1 von 60") and line.contains("dda|nvenc|gpu") and line.contains("zu wenig Bilder") and line.contains("Grafikkarte"),
			"Protokollzeile: Weg, Quelle von Ziel, Hinweis")
	check(L.fps_hint("dda|x264|cpu").contains("Arbeitsspeicher") and L.fps_hint("gfx_win|amf|gpu").contains("Windows.Graphics.Capture"), "Hinweis je Weg")
	check(L.progress_fps(b.slice(0, 1)).is_empty() and L.progress_fps([]).is_empty(), "eine Messung reicht nicht")
	var ma := L.measure_args("C:/a.mp4")
	check(ma.has("copy") and ma.has("null") and ma[ma.find("-progress") + 1] == "pipe:1" and ma[ma.find("-i") + 1] == "C:/a.mp4",
			"Clip zählen ohne Dekodieren (FFmpeg, kein ffprobe nötig)")
	var c := L.measured_clip("frame=1800\nout_time_us=29990000\nprogress=end\n", 30.0)
	check(int(c.frames) == 1800 and is_equal_approx(float(c.fps), 60.0), "Clip: 1800 Bilder in 30 s = 60 Bilder/s")
	check(L.measured_clip("", 30.0).is_empty(), "keine Ausgabe: keine Messung")


func _discord() -> void:
	check(L.discord_channel_url("111", "222") == "discord://-/channels/111/222" and L.discord_channel_url("", "2") == "discord://-/channels/@me",
			"Server-Kanal öffnen (Deep Link)")
	var raw := [{ "id": "1", "name": "allgemein", "type": 0, "position": 0 }, { "id": "2", "name": "Zocken", "type": 2, "position": 1 },
		{ "id": "3", "name": "clips", "type": 0, "position": 4 }, { "id": "4", "name": "Kategorie", "type": 4, "position": 2 },
		{ "id": "5", "name": "news", "type": 5, "position": 3 }, { "id": "6", "name": "Bühne", "type": 13, "position": 5 },
			{ "id": "7", "name": "forum", "type": 15, "position": 6 }, "kaputt"]
	var tc := L.discord_text_channels(raw)
	check(tc.map(func(x) -> String: return str(x.id)) == ["1", "5", "3"], "nur Text- und Ankündigungskanäle, Reihenfolge wie in Discord")
	var tr := L.discord_text_channels(raw, ["3", "99"])
	check(tr.map(func(x) -> String: return str(x.id)) == ["3", "1", "5"], "zuletzt benutzte zuerst")
	var r1 := L.remember_channel([], { "guild_id": "g", "guild": "Zockerbude", "channel_id": "3", "channel": "clips" })
	var r2 := L.remember_channel(r1, { "guild_id": "h", "guild": "Retro", "channel_id": "8", "channel": "allgemein" })
	var r3 := L.remember_channel(r2, { "guild_id": "g", "guild": "Zockerbude", "channel_id": "3", "channel": "clips" })
	check(r3.size() == 2 and str(r3[0].channel_id) == "3" and str(r3[1].channel_id) == "8", "zuletzt benutzt: neueste vorn, ohne Doppelte")
	var many: Array = []
	for i in 10:
		many = L.remember_channel(many, { "guild_id": "g", "channel_id": str(i) })
	check(many.size() == 6 and str(many[0].channel_id) == "9", "höchstens 6 gemerkt")
	var gs := L.sort_guilds([{ "id": "a", "name": "A" }, { "id": "b", "name": "B" }, { "id": "c", "name": "C" }], [{ "guild_id": "c" }, { "guild_id": "b" }])
	check(gs.map(func(x) -> String: return str(x.id)) == ["c", "b", "a"], "Server mit zuletzt benutzten Kanälen zuerst")
	var t0 := L.discord_targets({})
	check(t0.size() == 2 and str(t0[0][0]) == "friend" and str(t0[0][1]) == "Freund" and str(t0[1][0]) == "server" and str(t0[1][1]) == "Server-Kanal",
			"„An wen?“: Freund oder Server-Kanal")
	var t1 := L.discord_targets(r3[0])
	check(t1.size() == 3 and str(t1[0][0]) == "last" and str(t1[0][1]) == "Zuletzt: #clips in Zockerbude", "schnelle Wahl: „Zuletzt: #clips in Zockerbude“")
	check(L.discord_targets({ "channel_id": "3" }).size() == 2, "unvollständiger Eintrag: keine schnelle Wahl")


func _belongs() -> void:
	var tagged := { "title": "Anderer Name", "game_id": "steam:42" }
	check(L.belongs_to(tagged, "steam:42", "Hollow Knight") and not L.belongs_to(tagged, "steam:7", "Anderer Name"),
			"neue Clips: über die Spiel-ID (auch umbenannt)")
	check(L.belongs_to({ "title": "Halo Reach MCC", "game_id": "" }, "x", "Halo: Reach / MCC?"), "ältere: über den Titel im Dateinamen")
	check(not L.belongs_to({ "title": "Uzai", "game_id": "" }, "x", "") and L.belongs_to({ "title": "con", "game_id": "" }, "x", "CON"),
			"ohne Titel nichts, reservierte Namen")


## Echter Lauf: die Befehlszeile des Puffers (x264, über den Arbeitsspeicher) mit einer künstlichen
## Quelle statt ddagrab – Zeitstempel um bis zu 12 ms verschoben wie bei der Desktop-Duplizierung,
## jedes fünfte Bild fehlt (Grafikkarte ausgelastet). Erwartet: Clip mit genau 60 Bildern/s und
## gleichem Abstand; die Zähler melden, dass die Quelle nur rund 48 lieferte.
func _synthetic() -> void:
	var ff := OS.get_environment("UZAI_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		var w: Array = []
		OS.execute("sh", ["-c", "command -v ffmpeg"], w)
		ff = str(w[0]).strip_edges() if not w.is_empty() else ""
	if ff == "" or not FileAccess.file_exists(ff):
		print("  –    kein FFmpeg zum Probelauf (UZAI_TEST_FFMPEG), übersprungen")
		return
	var dir := Config.path("probelauf")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var o := { "src": { "kind": "dda" }, "size": Vector2i(320, 180), "fps": 60, "enc": "x264", "gpu": false, "kbps": 2500,
		"sys": false, "mic": false, "dir": dir, "length": 15 }
	var args := L.record_args(o)
	var fc := args[args.find("-filter_complex") + 1]
	var real_src := "ddagrab=output_idx=0:framerate=60:draw_mouse=0,hwdownload,format=bgra"
	check(fc.begins_with(real_src), "Probelauf ersetzt genau die Quelle")
	var fake := "testsrc2=size=640x360:rate=60:d=7,realtime,settb=1/1000000,setpts='PTS+random(0)*0.012/TB',select='lt(random(1),0.8)',format=bgra"
	args[args.find("-filter_complex") + 1] = fc.replace(real_src, fake).replace("{T0}", "%.6f" % (Time.get_unix_time_from_system() - 0.4))
	args[args.find("-stats_period") + 1] = "1"
	args[args.find("-loglevel") + 1] = "error"
	var out: Array = []
	var code := OS.execute(ff, args, out, true)
	check(code == 0, "Puffer-Befehlszeile läuft mit FFmpeg %s" % (str(out[0]).left(300) if code != 0 and not out.is_empty() else ""))
	var segs := L.parse_seg_list(FileAccess.get_file_as_string(dir.path_join("list.csv")))
	check(segs.size() >= 3, "Stücke im Puffer (%d)" % segs.size())
	if segs.size() < 3:
		return
	var cut := float(segs[segs.size() - 1].end) - 0.2
	var pick := L.pick_segments(segs, {}, cut, 4.0)
	var paths: Array = (pick.files as Array).map(func(f) -> String: return dir.path_join(str(f)))
	var list := dir.path_join("clip.ffconcat")
	var fl := FileAccess.open(list, FileAccess.WRITE)
	fl.store_string(L.concat_text(paths))
	fl.close()
	var clip := dir.path_join("clip.mp4")
	out = []
	code = OS.execute(ff, L.concat_args(list, clip, float(pick.duration)), out, true)
	check(code == 0 and FileAccess.file_exists(clip), "Clip zusammengefügt (-c copy)")
	out = []
	OS.execute(ff, L.measure_args(clip), out, true)
	var c := L.measured_clip("\n".join(PackedStringArray(out)), float(pick.duration))
	print("       Clip: %s Bilder in %.2f s = %.2f Bilder/s" % [str(c.get("frames", "?")), float(c.get("seconds", 0.0)), float(c.get("fps", 0.0))])
	check(not c.is_empty() and absf(float(c.fps) - 60.0) < 0.6, "Clip hat 60 Bilder/s, obwohl die Quelle Bilder verlor")
	var probe := ff.get_base_dir().path_join("ffprobe")
	if FileAccess.file_exists(probe):
		out = []
		OS.execute(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time", "-of", "csv=p=0", clip], out, true)
		var ts: Array = []
		for l in "\n".join(PackedStringArray(out)).split("\n"):
			if l.strip_edges().is_valid_float():
				ts.append(float(l))
		ts.sort()
		var bad := 0
		for i in range(1, ts.size()):
			if absf(float(ts[i]) - float(ts[i - 1]) - 1.0 / 60.0) > 0.0015:
				bad += 1
		check(ts.size() > 100 and bad == 0, "jeder Bildabstand genau 1/60 s (%d Bilder, %d abweichend)" % [ts.size(), bad])
	var pm := L.progress_fps(L.parse_progress(FileAccess.get_file_as_string(dir.path_join(L.PROGRESS_FILE))), 20.0)
	print("       Zähler: " + L.fps_text(pm, 60, "probe|x264|cpu"))
	check(not pm.is_empty() and absf(float(pm.out) - 60.0) < 2.0 and float(pm.src) > 40.0 and float(pm.src) < 54.0 and L.fps_low(pm, 60),
			"Zähler zeigen: Datei 60, Quelle nur rund 48 (fehlende Bilder sichtbar im Protokoll)")


func _trim() -> void:
	check(L.clamp_trim(-3.0, 50.0, 30.0) == Vector2(0.0, 30.0), "Griffe bleiben im Clip")
	check(L.clamp_trim(29.8, 29.0, 30.0) == Vector2(28.0, 29.0), "Anfang mindestens 1 s vor dem Ende")
	check(L.clamp_trim(0.0, 0.2, 30.0) == Vector2(0.0, 1.0), "Ende nicht vor 1 s")
	check(L.trim_step(0) == 0.5 and L.trim_step(6) == 1.0 and L.trim_step(20) == 5.0, "Halten wird schneller")
	check(L.snap_keyframe(5.3) == 4.0 and L.snap_keyframe(-1.0) == 0.0, "an das Schlüsselbild davor")
	check(L.trim_mode(0.0, 60.0) == "encode" and L.trim_mode(0.0, 400.0) == "copy", "kurz genau, lang an Schlüsselbildern")
	var t := L.trim_args("in.mp4", "out.mp4", 3.5, 12.0, "nvenc", 15000)
	check(t[t.find("-ss") + 1] == "3.500" and t[t.find("-t") + 1] == "8.500" and t.has("h264_nvenc") and not t.has("-g") and t.has("0:a?"),
			"genau: neu kodiert ab 3,5 s, 8,5 s lang, Ton wenn da")
	var tx := L.trim_args("in.mp4", "out.mp4", 1.0, 5.0, "x264", 5000)
	check(tx.has("veryfast") and not tx.has("ultrafast"), "x264 beim Kürzen „veryfast“ (Qualität statt Echtzeit)")
	var tc := L.trim_args("in.mp4", "out.mp4", 5.3, 400.0, "nvenc", 15000)
	check(tc[tc.find("-ss") + 1] == "4.000" and tc.has("copy") and tc[tc.find("-t") + 1] == "396.000", "lang: -c copy ab dem Schlüsselbild")


func _limits() -> void:
	check(L.discord_kbps(30.0, 10) == 2357, "30 s unter 10 MB: 2,36 Mbit/s Bild")
	check(L.discord_kbps(600.0, 10) == 250 and L.discord_kbps(1.0, 500) == 20000, "Bitrate begrenzt")
	check(L.needs_shrink(10_500_000, 10) and not L.needs_shrink(9_000_000, 10), "über 10 MB verkleinern")
	var s := L.shrink_args("a.mp4", "b.mp4", 30.0, 10, "x264")
	check(s.has("2357k") and s.has("veryfast") and s.has(str(int(10 * 1000 * 1000 * 0.98))) and s[s.find("-vf") + 1] == "scale=-2:'min(720,ih)',fps=30",
			"Verkleinern: 720p, 30 Bilder/s, harte Grenze -fs")
	check(L.discord_dm_url("123") == "discord://-/channels/@me/123" and L.discord_dm_url("") == "discord://-/channels/@me", "Direktnachricht öffnen")
	check(L.cap_bytes("25") == 25_000_000_000 and L.cap_bytes("0") == 0 and L.cap_bytes("x") == 25_000_000_000, "Grenze in Bytes")
	check(L.over_cap(24_990_000_000, 20_000_000, L.cap_bytes("25")) and not L.over_cap(1, 1, 0), "voll: kein neuer Clip; 0 = unbegrenzt")
	check(L.estimate_bytes(15000, 32.0) == 60_640_000, "Clipgröße grob geschätzt")


func _build() -> void:
	var sums := """17010962dfdf94221276428e9444869c15071cc44c901f5b59108a1e6eb534d2  ffmpeg-n8.1-latest-win64-gpl-8.1.zip
efcb630d9d7ffe72248c2d0628e5536f66e167f0e281bd8f7683a5c598f1b7c7  ffmpeg-n8.1-latest-win64-gpl-shared-8.1.zip
d1a329dc97e8e97c1624fcaded533945ad9e5e35ca1f7cc6bfbd6a9fc475ad7f  ffmpeg-n8.1-latest-win64-lgpl-8.1.zip
177bec2e8c3397c5e9739901993dadc1cad0954de97d2604a2704c8531a59e32  ffmpeg-n9.0-latest-win64-gpl-9.0.zip
85b40fefa33eae181732b20aec977b5748a2bae462c23dfcca33a12bd30e69a4  ffmpeg-master-latest-win64-gpl.zip
d99dafe91825139d6fd8ad237c9217cff290277585899a95d1e69a009aaa275d  ffmpeg-n9.0-latest-winarm64-gpl-9.0.zip
"""
	var p := L.pick_build(sums)
	check(str(p.file) == "ffmpeg-n9.0-latest-win64-gpl-9.0.zip" and str(p.sha) == "177bec2e8c3397c5e9739901993dadc1cad0954de97d2604a2704c8531a59e32",
			"neuestes Release, win64, GPL, statisch (nicht shared, nicht ARM)")
	check(str(p.url) == "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n9.0-latest-win64-gpl-9.0.zip", "Adresse beim BtbN-Release")
	var m := L.pick_build("85b40fefa33eae181732b20aec977b5748a2bae462c23dfcca33a12bd30e69a4  ffmpeg-master-latest-win64-gpl.zip\n")
	check(str(m.file) == "ffmpeg-master-latest-win64-gpl.zip" and str(m.version) == "master", "ohne Release: Hauptzweig")
	check(L.pick_build("kaputt").is_empty() and L.pick_build("").is_empty(), "nichts Passendes: nichts laden")


func _block() -> void:
	var s := { "via": "uzai", "buffer": true, "ffmpeg": true, "helper": true, "in_game": true, "video": false, "videos": false,
		"uzai_front_s": 0.0, "on_battery": false, "battery": false, "disk_free_mb": 50000, "recording": false }
	check(L.buffer_block(s) == "", "Spiel vorn: Puffer läuft")
	var cases := [["via", "gamebar", "via"], ["ffmpeg", false, "ffmpeg"], ["helper", false, "helper"], ["buffer", false, "aus"], ["in_game", false, "kein_spiel"],
		["uzai_front_s", 61.0, "uzai_vorn"], ["on_battery", true, "akku"], ["disk_free_mb", 1000, "platz"]]
	for c in cases:
		var x := s.duplicate()
		x[c[0]] = c[1]
		check(L.buffer_block(x) == str(c[2]) and L.block_text(str(c[2])) != "", "%s → %s" % [str(c[0]), str(c[2])])
	var v := s.duplicate()
	v.in_game = false
	v.video = true
	check(L.buffer_block(v) == "kein_spiel", "Video: nur, wenn gewünscht")
	v.videos = true
	check(L.buffer_block(v) == "", "… dann auch bei Videos")
	var bat := s.duplicate()
	bat.on_battery = true
	bat.battery = true
	check(L.buffer_block(bat) == "", "Akku erlaubt")
	var rec := s.duplicate()
	rec.in_game = false
	rec.buffer = false
	rec.recording = true
	check(L.buffer_block(rec) == "", "lange Aufnahme läuft auch ohne Spiel und ohne Puffer")
	rec.ffmpeg = false
	check(L.buffer_block(rec) == "ffmpeg", "… aber nie ohne FFmpeg")


func _share() -> void:
	check(L.parse_range("bytes=100-", 1000) == [100, 999] and L.parse_range("bytes=0-99", 1000) == [0, 99], "Range: ab, von–bis")
	check(L.parse_range("bytes=-200", 1000) == [800, 999] and L.parse_range("bytes=900-5000", 1000) == [900, 999], "Range: letzte Bytes, Ende gekappt")
	check(L.parse_range("bytes=1000-", 1000) == [-1] and L.parse_range("bytes=5-2", 1000) == [-1], "nicht erfüllbar → 416")
	check(L.parse_range("", 1000).is_empty() and L.parse_range("bytes=0-1,5-6", 1000).is_empty() and L.parse_range("items=0-1", 1000).is_empty(),
			"sonst ganze Datei")
	var page := L.share_page(
			[{ "name": "Boss <1>.mp4", "url": "/c/abc/0", "kind": "clip", "size": 37_400_000 },
			{ "name": "Bild.png", "url": "/c/abc/1", "kind": "shot", "size": 900_000 }])
	check(page.contains("<video src='/c/abc/0' controls playsinline") and page.contains("<img src='/c/abc/1'") and page.contains("/c/abc/0?dl=1"),
			"Seite: Vorschau und Herunterladen")
	check(page.contains("Boss &lt;1&gt;.mp4") and not page.contains("Boss <1>") and page.contains("37,4 MB") and page.contains("width:100%"),
			"Namen maskiert, Größe, CSS intakt")

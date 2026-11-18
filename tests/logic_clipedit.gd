extends Node
## Clip bearbeiten (Punkt 137, src/core/clip_edit.gd): Bereiche und Zeitlupe, Text säubern und
## maskieren, Filtergraph und Befehlszeilen, Namen, Fortschritt. Mit FFmpeg (UZAI_TEST_FFMPEG oder
## im PATH) zusätzlich echte Probeläufe in einem Ordner mit Sonderzeichen im Namen: Bearbeiten mit
## Zeitlupe, Text und Ton, ohne Ton, Vorschau (Theora, von Godot lesbar), Bildstreifen, Abbrechen.
## Aufruf: godot --headless --path . res://tests/logic_clipedit.tscn   → „Ergebnis: alles ok“

const E := preload("res://src/core/clip_edit.gd")
const L := preload("res://src/core/capture_logic.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Bereiche")
	_ranges()
	print("Text")
	_text()
	print("Befehlszeilen")
	_args()
	print("Namen und Fortschritt")
	_names()
	print("Probelauf mit FFmpeg")
	await _real()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _ranges() -> void:
	var p := E.plan(30.0)
	check(p.a == 0.0 and p.b == 30.0 and is_equal_approx(float(p.sa), 10.0) and is_equal_approx(float(p.sb), 20.0) and p.speed == 1.0,
			"Anfangsplan: ganzer Clip, Zeitlupe im mittleren Drittel")
	check(not E.is_changed(p, 30.0), "unverändert: nichts zu speichern")
	var q := E.clamp_plan({ "a": 29.8, "b": 40.0, "sa": -3.0, "sb": 99.0, "speed": 0.5 }, 30.0)
	check(float(q.b) == 30.0 and float(q.b) - float(q.a) >= E.MIN_LEN - 0.001, "Ende im Clip, mindestens 1 s lang (%s–%s)" % [q.a, q.b])
	check(float(q.sa) >= float(q.a) and float(q.sb) <= float(q.b), "Zeitlupe bleibt in Anfang–Ende")
	var r := E.clamp_plan({ "a": 2.0, "b": 12.0, "sa": 6.0, "sb": 6.1, "speed": 0.25 }, 30.0)
	check(float(r.sb) - float(r.sa) >= E.SLOW_MIN - 0.001, "Zeitlupe mindestens 0,5 s")
	check(E.clamp_plan({ "a": 0.0, "b": 5.0, "speed": 0.3 }, 5.0).speed == 1.0, "unbekanntes Tempo: keine Zeitlupe")
	var s := { "a": 2.0, "b": 12.0, "sa": 4.0, "sb": 6.0, "speed": 0.5, "top": "", "bottom": "", "mute": false }
	var segs := E.segments(s)
	check(segs.size() == 3 and is_equal_approx(float(segs[1][0]), 2.0) and is_equal_approx(float(segs[1][1]), 4.0) and float(segs[1][2]) == 0.5,
			"drei Stücke ab Anfang, das mittlere in Zeitlupe")
	check(is_equal_approx(E.out_length(s), 12.0), "Länge: 10 s, davon 2 s halb so schnell → 12 s")
	check(is_equal_approx(E.src_at(s, 1.0), 3.0) and is_equal_approx(E.src_at(s, 4.0), 5.0) and is_equal_approx(E.src_at(s, 7.0), 7.0)
			and E.src_at(s, 99.0) == 12.0, "Abspielmarke zurück ins Original gerechnet")
	var edge := { "a": 0.0, "b": 4.0, "sa": 0.0, "sb": 4.0, "speed": 0.25, "top": "", "bottom": "", "mute": false }
	check(E.segments(edge).size() == 1 and is_equal_approx(E.out_length(edge), 16.0), "Zeitlupe über den ganzen Clip: ein Stück")
	check(E.only_cut({ "a": 1.0, "b": 3.0, "sa": 1.0, "sb": 2.0, "speed": 1.0, "top": "", "bottom": "", "mute": false }), "nur geschnitten erkannt")
	check(not E.only_cut(s) and E.is_changed(s, 30.0), "mit Zeitlupe: neu kodieren")
	check(E.time_text(72.46) == "1:12,5" and E.time_text(0.0) == "0:00,0", "Zeit mit Zehnteln")
	check(E.summary(s).contains("0:10,0 → 0:12,0") and E.summary(s).contains("Zeitlupe 0,5×"), "Zeile: Länge vorher → nachher, Zeitlupe")


func _text() -> void:
	check(E.clean_text("  Hallo\nWelt\t!\u0001\u2028x ") == "Hallo Welt ! x", "Steuerzeichen und Umbrüche werden ein Leerzeichen")
	check(E.clean_text("x".repeat(200)).length() == E.TEXT_MAX, "höchstens 60 Zeichen")
	check(E.font_key("Grüße & Spaß") == "hanken" and E.font_key("Привет") == "atkinson", "Uzais Schrift, sonst eine mit mehr Zeichen")
	# Beispiel aus FFmpegs Doku („Quoting and escaping“).
	check(E.filter_value("this is a 'string': may contain one, or more, special characters") == "this is a \\\\\\'string\\\\\\'\\\\: may contain one\\, or more\\, special characters", "Maskierung wie in FFmpegs Doku")
	check(E.filter_path("C:\\Users\\O'Neil\\AppData\\Uzai\\top.txt") == "C\\\\:/Users/O\\\\\\'Neil/AppData/Uzai/top.txt",
			"Windows-Pfad: Schrägstriche, Laufwerk und Apostroph maskiert")


func _args() -> void:
	var evil := "Boss'],drawtext=text=%{localtime};x"
	var p := E.clamp_plan({ "a": 1.0, "b": 9.0, "sa": 3.0, "sb": 5.0, "speed": 0.25, "top": evil, "bottom": "GG", "mute": false }, 10.0)
	var o := { "audio": true, "top_file": "/d/a b/top.txt", "top_font": "/d/f.woff2", "bottom_file": "/d/bottom.txt", "bottom_font": "/d/f.woff2" }
	var g := E.graph(p, o)
	var gr := str(g.graph)
	check(gr.contains("[0:v]split=3") and gr.contains("[0:a]asplit=3") and gr.contains("concat=n=3:v=1:a=1[vc][ac]") and str(g.audio_map) == "[ac]",
			"Zeitlupe: teilen, Stücke, zusammensetzen – mit Ton")
	check(gr.contains("setpts=4.0*(PTS-STARTPTS)") and gr.contains("atempo=0.5,atempo=0.5"), "0,25×: Bild viermal so lang, Ton zweimal halbiert")
	check(gr.contains("textfile=/d/a b/top.txt") and gr.contains("expansion=none"), "Text aus Datei, ohne %-Ersetzung")
	var args := E.export_args("/c/in.mp4", "/c/out.mp4", p, o, "x264", 8000)
	var joined := " ".join(args)
	check(not joined.contains("Boss") and not joined.contains("localtime"), "eigener Text steht nirgends in der Befehlszeile")
	check(args[args.size() - 1] == "/c/out.mp4" and args.has("-progress") and args[args.find("-progress") + 1] == "pipe:1",
			"Fortschritt auf die Standardausgabe, Ziel zuletzt")
	check(args[args.find("-ss") + 1] == "1.000" and args[args.find("-t") + 1] == "8.000" and args.find("-ss") < args.find("-i"),
			"Eingabe ab Anfang, auf die Länge begrenzt")
	check(args.has("veryfast") and not args.has("ultrafast") and args.has("aac"), "x264 „veryfast“, Ton AAC")
	var mute := p.duplicate()
	mute.mute = true
	var am := E.export_args("/c/in.mp4", "/c/out.mp4", mute, o, "nvenc", 8000)
	check(am.has("-an") and not " ".join(am).contains("asplit") and am.has("h264_nvenc"), "ohne Ton: keine Tonspur, Grafikkarte wie beim Aufnehmen")
	var plain := E.clamp_plan({ "a": 0.0, "b": 10.0, "speed": 1.0, "top": "", "bottom": "", "mute": false }, 10.0)
	var gp := E.graph(plain, { "audio": true })
	check(str(gp.graph) == "[0:v]format=yuv420p[vout]" and str(gp.audio_map) == "0:a:0", "nichts zu tun: kein Teilen, Ton direkt")
	var pv := E.preview_args("/c/in.mp4", "/c/v.ogv", p, o)
	check(pv.has("libtheora") and pv.has("libvorbis") and " ".join(pv).contains("scale=640:-2,fps=30"), "Vorschau: klein, Theora/Vorbis für Godot")
	var cut := E.cut_args("/c/in.mp4", "/c/out.mp4", plain, "x264", 8000)
	check(cut.find("-progress") == cut.find("-y") + 2 and cut[cut.size() - 1] == "/c/out.mp4", "Nur schneiden: Kürzen mit Fortschritt")
	var st := E.strip_args("/c/in.mp4", "/c/s.jpg", 24.0)
	check(st.count("-i") == E.STRIP_N and str(st[st.find("-ss") + 1]) == "1.000" and " ".join(st).contains("hstack=inputs=12"),
			"Bildstreifen: 12 Stellen, nebeneinander")


func _names() -> void:
	var f := "/v/Elden Ring 2026-10-22 18-30-00.mp4"
	check(E.edited_name([], f) == "Elden Ring 2026-10-22 18-30-00 (bearbeitet).mp4", "neuer Name neben dem Original")
	check(E.edited_name([], "/v/Elden Ring 2026-10-22 18-30-00 (gekürzt).mp4") == "Elden Ring 2026-10-22 18-30-00 (bearbeitet).mp4", "alter Zusatz wird ersetzt")
	check(E.edited_name(["Elden Ring 2026-10-22 18-30-00 (bearbeitet).mp4"], f) == "Elden Ring 2026-10-22 18-30-00 (bearbeitet) (2).mp4", "gleicher Name: „(2)“")
	check(E.edited_name([], f, true).ends_with("(gekürzt).mp4"), "nur geschnitten: „gekürzt“")
	check(is_equal_approx(E.parse_out_time("frame=10\nout_time_us=1500000\nprogress=continue\nout_time_us=2250000\n"), 2.25)
			and E.parse_out_time("frame=1\n") < 0.0, "Fortschritt: letzte Zeit")
	var info := E.probe_info("  Duration: 00:00:04.02, start: 0.000000\n  Stream #0:0[0x1](und): Video: h264\n  Stream #0:1[0x2](und): Audio: aac (LC)\n")
	check(is_equal_approx(float(info.duration), 4.02) and bool(info.audio), "Länge und Ton aus FFmpegs Ausgabe")
	check(not bool(E.probe_info("Duration: 00:00:04.00\n Stream #0:0: Video: h264\n").audio), "ohne Tonspur erkannt")


func _real() -> void:
	var ff := OS.get_environment("UZAI_TEST_FFMPEG")
	if ff == "" or not FileAccess.file_exists(ff):
		var w: Array = []
		OS.execute("sh", ["-c", "command -v ffmpeg"], w)
		ff = str(w[0]).strip_edges() if not w.is_empty() else ""
	if ff == "" or not FileAccess.file_exists(ff):
		print("  –    kein FFmpeg zum Probelauf (UZAI_TEST_FFMPEG), übersprungen")
		return
	# Clip-Ordner mit allem, was im Filtergraphen etwas bedeutet: Apostroph, Komma, Klammern, Semikolon.
	var dir := Config.path("probelauf/O'Neil, [Clips]; ä")
	DirAccess.make_dir_recursive_absolute(dir)
	Config.set_value("capture.folder", dir)
	DirAccess.make_dir_recursive_absolute(Config.path("tools/ffmpeg"))
	OS.execute("ln", ["-sf", ff, Config.path("tools/ffmpeg/ffmpeg.exe")])
	check(Capture.has_ffmpeg(), "FFmpeg für Capture bereit")
	var src := dir.path_join("Elden Ring 2026-10-22 18-30-00.mp4")
	var code := OS.execute(ff, ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=60:d=6",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=6", "-c:v", "libx264", "-g", "120", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", src], [], true)
	check(code == 0 and FileAccess.file_exists(src), "Testclip angelegt (6 s, mit Ton)")
	var font := Capture._font_file("hanken")
	check(font != "" and FileAccess.get_file_as_bytes(font).size() > 10000, "Uzais Schrift als Datei für FFmpeg (aus der Ressource)")
	var info := await Capture.probe(src)
	check(absf(float(info.duration) - 6.0) < 0.2 and bool(info.audio), "Länge und Ton erkannt")

	# Bearbeiten über Capture: 0,5–4,5 s, 1 s davon halb so schnell, Text oben und unten.
	var p := E.clamp_plan(
			{ "a": 0.5, "b": 4.5, "sa": 2.0, "sb": 3.0, "speed": 0.5, "top": "Boss' 100% [geschafft], %{localtime}", "bottom": "GG\\n;", "mute": false }, 6.0)
	var out := await Capture.edit_clip(src, p)
	check(out != "" and FileAccess.file_exists(out) and out.get_base_dir() == dir and out.get_file().ends_with("(bearbeitet).mp4"),
			"neue Datei neben dem Original: %s" % out.get_file())
	check(FileAccess.file_exists(src), "Original bleibt")
	if out != "":
		var o2: Array = []
		OS.execute(ff, ["-hide_banner", "-i", out], o2, true)
		var pi := E.probe_info(str(o2[0]) if not o2.is_empty() else "")
		check(absf(float(pi.duration) - 5.0) < 0.25 and bool(pi.audio), "Länge 4 s + 1 s Zeitlupe = 5 s, mit Ton (%.2f s)" % float(pi.duration))
		_check_text(ff, out)
	check(Capture.edit_job.is_empty(), "Arbeit beendet, nichts hängt")

	# Ohne Ton und nur geschnitten.
	var m := E.clamp_plan({ "a": 1.0, "b": 3.0, "speed": 1.0, "top": "", "bottom": "", "mute": true }, 6.0)
	var out2 := await Capture.edit_clip(src, m)
	if out2 != "":
		var o3: Array = []
		OS.execute(ff, ["-hide_banner", "-i", out2], o3, true)
		var pm := E.probe_info(str(o3[0]) if not o3.is_empty() else "")
		check(not bool(pm.audio) and absf(float(pm.duration) - 2.0) < 0.2, "ohne Ton: keine Tonspur, 2 s")
	else:
		check(false, "ohne Ton gespeichert")
	var c := E.clamp_plan({ "a": 2.0, "b": 4.0, "speed": 1.0, "top": "", "bottom": "", "mute": false }, 6.0)
	var out3 := await Capture.edit_clip(src, c)
	check(out3.ends_with("(gekürzt).mp4") and FileAccess.file_exists(out3), "nur geschnitten: „gekürzt“")

	# Vorschau zum Abspielen in Uzai.
	var job := { "cancel": false, "frac": 0.0 }
	var pv := await Capture.edit_preview(src, p, job)
	check(pv.ends_with(".ogv") and FileAccess.file_exists(pv) and float(job.frac) == 1.0, "Vorschau gebaut, Fortschritt bis 100 %")
	if pv != "":
		var vs := VideoStreamTheora.new()
		vs.file = pv
		var vp := VideoStreamPlayer.new()
		vp.stream = vs
		vp.volume = 0.0
		add_child(vp)
		vp.play()
		await get_tree().create_timer(0.6).timeout
		check(vp.get_stream_length() > 4.0 and vp.stream_position > 0.0, "Godot spielt die Vorschau ab (%.1f s lang)" % vp.get_stream_length())
		vp.stop()
		vp.queue_free()

	# Bildstreifen.
	var sp := await Capture.strip(src)
	var img := Image.load_from_file(sp) if sp != "" else null
	check(img != null and img.get_width() == E.STRIP_W * E.STRIP_N and img.get_height() == E.STRIP_H, "Bildstreifen 12 × 192 × 108")

	# Abbrechen: längerer Clip, nach kurzer Zeit abbrechen – keine halbe Datei bleibt.
	var long := dir.path_join("Lang 2026-10-22 19-00-00.mp4")
	OS.execute(ff,
			["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60:d=40", "-c:v", "libx264", "-preset", "ultrafast", "-g",
			"120", "-pix_fmt", "yuv420p", long], [], true)
	var before := Array(DirAccess.get_files_at(dir))
	var lp := E.clamp_plan({ "a": 0.0, "b": 40.0, "sa": 5.0, "sb": 35.0, "speed": 0.25, "top": "x", "bottom": "", "mute": false }, 40.0)
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if not Capture.edit_job.is_empty():
			Capture.edit_job["cancel"] = true)
	var t0 := Time.get_ticks_msec()
	var out4 := await Capture.edit_clip(long, lp)
	check(out4 == "" and Time.get_ticks_msec() - t0 < 10000, "abgebrochen, schnell zurück")
	check(Array(DirAccess.get_files_at(dir)) == before, "keine halbe Datei übrig")
	check(Capture.edit_job.is_empty(), "nach dem Abbruch frei für die nächste Arbeit")

	# Fremde Dateien (nicht im Clip-Ordner) werden nicht bearbeitet.
	var other := Config.path("probelauf/anderswo.mp4")
	DirAccess.copy_absolute(src, other)
	check(await Capture.edit_clip(other, p) == "", "Datei außerhalb des Clip-Ordners: nichts")


## Im fertigen Clip steht oben Text: die oberen Zeilen sind nicht mehr nur das Testbild.
func _check_text(ff: String, out: String) -> void:
	var png := Config.path("probelauf/frame.png")
	OS.execute(ff, ["-hide_banner", "-loglevel", "error", "-y", "-ss", "0.2", "-i", out, "-frames:v", "1", png], [], true)
	var img := Image.load_from_file(png)
	if img == null:
		check(false, "Bild aus dem fertigen Clip")
		return
	var white := 0
	for x in range(0, img.get_width(), 2):
		for y in range(int(img.get_height() * 0.06), int(img.get_height() * 0.06 + img.get_height() / 13.0)):
			var c := img.get_pixel(x, y)
			if c.r > 0.95 and c.g > 0.95 and c.b > 0.95:
				white += 1
	check(white > 150, "Text oben im Bild (%d weiße Punkte)" % white)

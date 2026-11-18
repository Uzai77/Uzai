extends RefCounted
## Reine Logik von Uzais eigener Aufnahme (Clips, längere Aufnahmen, Bildschirmfotos) – ohne
## Windows und ohne Zustand, darum in tests/logic_aufnahmen.gd geprüft: welche Stücke des
## Rollpuffers ein Clip braucht, Dateinamen, die Befehlszeilen für FFmpeg, Kürzen, Speicherplatz,
## welches FFmpeg-Paket geladen wird und wann der Puffer läuft.
##
## So nimmt Uzai auf (wie „Aufzeichnen, was passiert ist“ bei Xbox und PS5):
## FFmpeg greift das Bild über die Desktop-Duplizierung von Windows ab (ddagrab, bzw.
## Windows.Graphics.Capture für „nur das Spielfenster“), kodiert es auf der Grafikkarte (NVENC,
## AMF, Quick Sync; sonst x264 „ultrafast“) und schreibt es in 2-Sekunden-Stücke (.ts) in einen
## Ordner, der sich im Kreis überschreibt. „Clip speichern“ hängt die letzten Stücke nur aneinander
## (-c copy) – sofort fertig, ohne neu zu kodieren. Den Ton (was das Spiel ausgibt, auf Wunsch das
## Mikrofon) nimmt der Windows-Helfer über WASAPI-Loopback ab und reicht ihn über eine benannte
## Leitung an FFmpeg weiter: FFmpeg selbst kann unter Windows keinen Loopback-Ton aufnehmen.
##
## Bild und Ton auf einer Uhr: Der Helfer startet den Ton zum Zeitpunkt T0 (Unix-Sekunden) und
## füllt Lücken mit Stille, sodass Probe n immer zu T0 + n/Rate gehört. Das Bild bekommt beim
## ersten Frame denselben Bezug (setpts mit time(0) − T0). Ein Clip, der beim Druck der Guide-Taste
## enden soll, endet deshalb genau dort: Stückzeit = Unix-Zeit − T0.

const Lang := preload("res://src/core/lang.gd")

static var _RX_DAUER := RegEx.create_from_string("Duration: (\\d+):(\\d\\d):(\\d\\d(?:\\.\\d+)?)")
## Dateiname einer Aufnahme: Titel, Datum, Uhrzeit, Zusatz in Klammern (parse_name läuft je Datei der Galerie).
static var _RX_NAME := RegEx.create_from_string("^(.*?) ?(\\d{4})-(\\d\\d)-(\\d\\d)[ _](\\d\\d)-(\\d\\d)(?:-(\\d\\d))?(?: \\((.*)\\))?$")

const SEG_S := 2                    ## Länge eines Stücks im Rollpuffer (= Abstand der Schlüsselbilder)
const LENGTHS := ["15", "30", "60", "120"]
const RECORD_MAX_S := 600           ## längere Aufnahmen höchstens 10 Minuten
const BUILDS := "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/"
const SUMS := "checksums.sha256"
const FALLBACK_BUILD := "ffmpeg-master-latest-win64-gpl.zip"
const ENCODERS := ["nvenc", "amf", "qsv", "x264"]
const PROGRESS_FILE := "progress.txt"   ## Zähler von FFmpeg im Puffer-Ordner (-progress)
const MIN_FREE_MB := 2048           ## weniger frei auf dem Laufwerk des Puffers: kein Puffer
const UZAI_FRONT_S := 60.0          ## so lange Uzai im Spiel vorn (ohne Guide): Puffer aus

## Einstellungen (Config.DEFAULTS.capture hat dieselben Werte).
const DEFAULTS := {
	"via": "uzai",            # uzai | gamebar (Windows Game Bar) | nvidia (ShadowPlay) – über Tastenkürzel
	"buffer": true,           # Clip-Puffer im Spiel
	"length": "30",           # Sekunden
	"quality": "1080",        # 720 | 1080 | native
	"fps": "60",              # 30 | 60
	"source": "screen",       # screen (ganzer Bildschirm) | window (nur Spielfenster)
	"audio": true,            # Ton des Spiels (alles, was Windows ausgibt)
	"mic": false,             # Mikrofon dazu
	"folder": "",             # leer: Videos\Uzai
	"cap_gb": "25",           # Speicherplatz für Aufnahmen (0 = unbegrenzt)
	"battery": false,         # auch im Akkubetrieb
	"videos": false,          # auch während Videos (YouTube, Filme)
	"discord_mb": "10",       # Größenlimit beim Senden an Discord (10 ohne Nitro)
	"hotkey": true,           # Guide halten + X speichert einen Clip
}


# --- Rollpuffer ----------------------------------------------------------------------------

## So viele fertige Stücke führt FFmpeg in der Liste (Cliplänge plus Reserve).
static func seg_keep(length_s: int) -> int:
	return int(ceil(float(maxi(1, length_s)) / float(SEG_S))) + 2


## So viele Dateien gibt es im Kreis: etwas mehr als die Liste, damit ein Stück, das gerade
## zusammengefügt wird, nicht schon wieder überschrieben wird (mindestens 8 s Luft).
static func seg_wrap(length_s: int) -> int:
	return seg_keep(length_s) + 4


static func seg_file(i: int) -> String:
	return "seg%03d.ts" % i


## Die Liste des Segment-Muxers (csv: „seg003.ts,12.000000,14.000000“), älteste zuerst.
static func parse_seg_list(text: String) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		var p := line.split(",")
		if p.size() < 3:
			continue
		var name := p[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
		var a := p[p.size() - 2].strip_edges()
		var b := p[p.size() - 1].strip_edges()
		if name == "" or not a.is_valid_float() or not b.is_valid_float():
			continue
		out.append({ "file": name, "start": float(a), "end": float(b) })
	return out


## Das Stück, das FFmpeg gerade schreibt: das nach dem letzten fertigen (im Kreis).
static func live_segment(segs: Array, wrap: int) -> Dictionary:
	if segs.is_empty():
		return { "file": seg_file(0), "start": 0.0 }
	var last: Dictionary = segs[segs.size() - 1]
	var n := str(last.file).get_basename().trim_prefix("seg")
	var i := (int(n) + 1) % maxi(1, wrap) if n.is_valid_int() else 0
	return { "file": seg_file(i), "start": float(last.end) }


## Welche Stücke ein Clip braucht, der bei cut_t (Stückzeit) endet und length_s lang sein soll.
## Anfang immer an einer Stückgrenze (Schlüsselbild, -c copy): lieber bis 2 s länger als kürzer.
## live: das gerade wachsende Stück ({} wenn keins). Ergebnis { files, start, duration, short }
## oder {} (nichts im Puffer vor cut_t).
static func pick_segments(segs: Array, live: Dictionary, cut_t: float, length_s: float) -> Dictionary:
	var all: Array = segs.duplicate()
	if not live.is_empty():
		all.append({ "file": str(live.file), "start": float(live.start), "end": INF })
	var usable: Array = all.filter(func(s) -> bool: return float(s.start) < cut_t - 0.05)
	if usable.is_empty():
		return {}
	var want := cut_t - length_s
	var first := 0
	for i in usable.size():
		if float(usable[i].start) <= want + 0.01:
			first = i
	var chosen: Array = usable.slice(first)
	var start := float(chosen[0].start)
	return { "files": chosen.map(func(s) -> String: return str(s.file)), "start": start,
		"duration": cut_t - start, "short": cut_t - start < length_s - 0.5 }


## Stückzeit eines Augenblicks (Unix-Sekunden) bei Zeitbasis t0.
static func stream_time(unix: float, t0: float) -> float:
	return unix - t0


## Liste für FFmpegs concat-Demuxer. In einfachen Anführungszeichen gilt alles wörtlich (auch \),
## nur ' selbst muss als '\'' geschrieben werden.
static func concat_text(paths: Array) -> String:
	var t := "ffconcat version 1.0\n"
	for p in paths:
		t += "file '%s'\n" % str(p).replace("'", "'\\''")
	return t


# --- Bild, Kodierer, Befehlszeilen ---------------------------------------------------------

static func _even(v: int) -> int:
	return maxi(2, v - v % 2)


## Zielgröße: höchstens 720 bzw. 1080 Zeilen, Seitenverhältnis bleibt, nie hochskaliert, gerade Werte.
static func fit_size(src: Vector2i, quality: String) -> Vector2i:
	var s := Vector2i(maxi(2, src.x), maxi(2, src.y))
	var max_h := 720 if quality == "720" else (1080 if quality == "1080" else 0)
	if max_h == 0 or s.y <= max_h:
		return Vector2i(_even(s.x), _even(s.y))
	var w := int(round(float(s.x) * float(max_h) / float(s.y)))
	return Vector2i(_even(w), _even(max_h))


## Bitrate in kbit/s: 1080p60 15 Mbit/s, weniger Bildpunkte oder 30 Bilder/s entsprechend weniger.
static func bitrate_kbps(size: Vector2i, fps: int) -> int:
	var k := float(size.x * size.y) / (1920.0 * 1080.0)
	var f := 1.0 if fps >= 50 else 0.65
	return clampi(int(round(15000.0 * pow(k, 0.85) * f)), 2500, 60000)


## Kodierer-Einstellungen. Schlüsselbild genau alle SEG_S Sekunden (der Segment-Muxer schneidet nur
## dort), keine B-Frames (Stücke lassen sich so sauber aneinanderhängen und kürzen).
static func enc_args(enc: String, kbps: int, fps: int) -> PackedStringArray:
	var a := PackedStringArray()
	var br := "%dk" % kbps
	var mx := "%dk" % int(kbps * 1.5)
	var buf := "%dk" % (kbps * 2)
	match enc:
		"nvenc":
			a.append_array(["-c:v", "h264_nvenc", "-preset", "p4", "-tune", "ll", "-rc", "vbr", "-b:v", br, "-maxrate", mx, "-bufsize", buf, "-forced-idr", "1"])
		"amf":
			a.append_array(["-c:v", "h264_amf", "-usage", "lowlatency", "-quality", "speed", "-rc", "vbr_peak", "-b:v", br, "-maxrate", mx, "-bufsize", buf])
		"qsv":
			a.append_array(["-c:v", "h264_qsv", "-preset", "veryfast", "-b:v", br, "-maxrate", mx, "-bufsize", buf])
		_:
			a.append_array(["-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-b:v", br, "-maxrate", mx, "-bufsize", buf])
	a.append_array(["-g", str(fps * SEG_S), "-bf", "0", "-force_key_frames", "expr:gte(t,n_forced*%d)" % SEG_S])
	return a


## Bildquelle. src: { kind: dda | gfx_win | gfx_mon, output, hwnd, hmonitor }. hwnd/hmonitor
## dürfen Platzhalter sein ({HWND}, {HMON}); der Helfer setzt das Vordergrundfenster ein.
static func source_filter(src: Dictionary, size: Vector2i, fps: int, shot := false) -> String:
	match str(src.get("kind", "dda")):
		"gfx_win", "gfx_mon":
			var target := ("hwnd=%s" % str(src.get("hwnd", "{HWND}"))) if str(src.kind) == "gfx_win" else ("hmonitor=%s" % str(src.get("hmonitor", "{HMON}")))
			var f := "gfxcapture=%s:max_framerate=%d:capture_cursor=0" % [target, fps]
			if not shot and size.x > 0:
				f += ":width=%d:height=%d:resize_mode=scale_aspect" % [size.x, size.y]
			return f
	return "ddagrab=output_idx=%d:framerate=%d:draw_mouse=0" % [int(src.get("output", 0)), fps]


## Bild auf die gemeinsame Uhr: beim ersten Frame Abstand zu T0 merken (time(0) ist die Unix-Zeit),
## danach nur noch die genauen eigenen Zeitstempel der Quelle plus diesen Abstand.
static func setpts_filter(t0_token: String) -> String:
	return "setpts='if(eq(N,0),st(0,time(0)-%s-PTS*TB));PTS+ld(0)/TB'" % t0_token


## Ganze Bildkette bis [v]. gpu: Bild bleibt auf der Grafikkarte (Skalieren und Umwandeln mit
## scale_d3d11), sonst holt hwdownload es in den Arbeitsspeicher (geht immer, kostet etwas CPU).
## x264 kodiert immer im Arbeitsspeicher; mit gpu skaliert und wandelt die Grafikkarte vorher
## (NV12 in Zielgröße herunterladen statt BGRA in voller Größe – ein Viertel der Daten, kein
## Umrechnen auf dem Prozessor). Eine feste Bildrate macht nicht der Graph, sondern -fps_mode cfr
## beim Kodieren (record_args): Dann zählt FFmpeg mit, wie viele Bilder es auffüllen musste.
static func video_chain(src: Dictionary, size: Vector2i, fps: int, enc: String, gpu: bool, t0_token: String) -> String:
	var kind := str(src.get("kind", "dda"))
	var gfx := kind.begins_with("gfx")
	var f := PackedStringArray([source_filter(src, size, fps)])
	if not gpu:
		f.append("hwdownload")
		f.append("format=bgra")
	f.append(setpts_filter(t0_token))
	if gpu:
		f.append(("scale_d3d11=format=nv12") if gfx else ("scale_d3d11=width=%d:height=%d:format=nv12" % [size.x, size.y]))
		if enc == "qsv":
			f.append("hwmap=derive_device=qsv")
			f.append("format=qsv")
		elif enc == "x264":
			f.append("hwdownload")
			f.append("format=nv12")
	else:
		if not gfx:
			f.append("scale=%d:%d:flags=bilinear" % [size.x, size.y])
		f.append("format=" + ("yuv420p" if enc == "x264" else "nv12"))
	return ",".join(f) + "[v]"


## Befehlszeile für den Rollpuffer. o: { src, size, fps, enc, gpu, kbps, sys, mic, pipe_sys,
## pipe_mic, dir, length }. Platzhalter für den Helfer: {T0}, {SYS_RATE}, {MIC_RATE}, {HWND}, {HMON}.
static func record_args(o: Dictionary) -> PackedStringArray:
	var a := PackedStringArray(["-hide_banner", "-loglevel", "warning", "-nostats"])
	var n_audio := 0
	if bool(o.get("sys", false)):
		a.append_array(["-thread_queue_size", "2048", "-f", "f32le", "-ar", "{SYS_RATE}", "-ac", "2", "-i", str(o.pipe_sys)])
		n_audio += 1
	if bool(o.get("mic", false)):
		a.append_array(["-thread_queue_size", "2048", "-f", "f32le", "-ar", "{MIC_RATE}", "-ac", "2", "-i", str(o.pipe_mic)])
		n_audio += 1
	var fps := int(o.get("fps", 60))
	var enc := str(o.get("enc", "x264"))
	var fc := video_chain(o.get("src", {}), o.get("size", Vector2i(1920, 1080)), fps, enc, bool(o.get("gpu", true)), "{T0}")
	if n_audio == 2:
		fc += ";[0:a][1:a]amix=inputs=2:duration=longest:normalize=0[a]"
	a.append_array(["-filter_complex", fc, "-map", "[v]"])
	if n_audio == 2:
		a.append_array(["-map", "[a]"])
	elif n_audio == 1:
		a.append_array(["-map", "0:a"])
	# Feste Bildrate (60 bzw. 30): Fehlt der Quelle ein Bild (Spiel ruckelt, Grafikkarte voll,
	# Windows.Graphics.Capture liefert nur bei Änderungen), wiederholt FFmpeg das letzte und zählt
	# es (dup_frames in progress.txt, siehe progress_fps). Früher „vfr“: Lücken blieben Lücken, die
	# Datei behauptete trotzdem 60 Bilder/s – manche Player (Handy, Discord, Windows) ruckeln dabei.
	a.append_array(["-fps_mode", "cfr", "-r", str(fps)])
	a.append_array(enc_args(enc, int(o.get("kbps", 10000)), fps))
	if n_audio > 0:
		a.append_array(["-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2"])
	var dir := str(o.get("dir", "."))
	var length := int(o.get("length", 30))
	# Alle 5 s Zähler (Bilder, aufgefüllte, verworfene, Tempo) in eine Datei: Uzai schreibt daraus
	# ins Protokoll, wie viele Bilder die Quelle wirklich liefert.
	a.append_array(["-stats_period", "5", "-progress", dir.path_join(PROGRESS_FILE)])
	a.append_array(["-max_muxing_queue_size", "1024", "-f", "segment", "-segment_time", str(SEG_S), "-segment_format", "mpegts",
		"-segment_wrap", str(seg_wrap(length)), "-segment_list", dir.path_join("list.csv"), "-segment_list_type", "csv",
		"-segment_list_size", str(seg_keep(length)), "-reset_timestamps", "0", dir.path_join("seg%03d.ts")])
	return a


## Clip aus Stücken: nur aneinanderhängen, am Ende genau bei duration abschneiden.
static func concat_args(list_path: String, out_path: String, duration: float) -> PackedStringArray:
	return PackedStringArray(["-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", list_path,
		"-map", "0", "-c", "copy", "-t", "%.3f" % maxf(0.5, duration), "-movflags", "+faststart", out_path])


## Vorschaubild (480 breit) – mit „-loglevel info“, damit die Länge des Clips mitkommt (parse_duration).
static func thumb_args(src: String, dst: String, at := 1.0) -> PackedStringArray:
	return PackedStringArray(["-hide_banner", "-loglevel", "info", "-y", "-ss", "%.2f" % maxf(0.0, at), "-i", src,
		"-frames:v", "1", "-vf", "scale=480:-2", "-q:v", "4", dst])


## „Duration: 00:00:31.52“ aus der Ausgabe von FFmpeg; -1, wenn nicht da.
static func parse_duration(text: String) -> float:
	var m := _RX_DAUER.search(text)
	if m == null:
		return -1.0
	return float(m.get_string(1)) * 3600.0 + float(m.get_string(2)) * 60.0 + float(m.get_string(3))


# --- Bildrate messen (für das Protokoll) ---------------------------------------------------

## Blöcke aus FFmpegs -progress-Ausgabe („frame=…“ … „progress=continue“), älteste zuerst:
## { frame, dup, drop, t (Sekunden Ausgabezeit), speed }. Unvollständige Blöcke fallen weg.
static func parse_progress(text: String) -> Array:
	var out: Array = []
	var cur := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		var eq := line.find("=")
		if eq <= 0:
			continue
		var k := line.substr(0, eq)
		var v := line.substr(eq + 1).strip_edges()
		match k:
			"frame":
				cur["frame"] = int(v) if v.is_valid_int() else -1
			"dup_frames":
				cur["dup"] = int(v) if v.is_valid_int() else 0
			"drop_frames":
				cur["drop"] = int(v) if v.is_valid_int() else 0
			"out_time_us", "out_time_ms":
				# Beide Schlüssel sind Mikrosekunden („_ms“ ist ein alter Name in FFmpeg).
				if v.is_valid_int():
					cur["t"] = float(v) / 1000000.0
			"speed":
				var sp := v.trim_suffix("x").strip_edges()
				cur["speed"] = float(sp) if sp.is_valid_float() else -1.0
			"progress":
				if int(cur.get("frame", -1)) >= 0 and cur.has("t"):
					out.append({ "frame": int(cur.frame), "dup": int(cur.get("dup", 0)), "drop": int(cur.get("drop", 0)),
						"t": float(cur.t), "speed": float(cur.get("speed", -1.0)) })
				cur = {}
	return out


## Bildrate über die letzten window_s Sekunden: out (was in der Datei landet, mit cfr immer die
## Zielrate), src (was die Quelle wirklich geliefert hat: Bilder ohne die aufgefüllten), dup
## (Anteil aufgefüllt, 0–1), speed, span (gemessene Sekunden). {} wenn zu wenig da ist.
static func progress_fps(blocks: Array, window_s := 20.0) -> Dictionary:
	if blocks.size() < 2:
		return {}
	var b: Dictionary = blocks[blocks.size() - 1]
	var a: Dictionary = blocks[0]
	for i in range(blocks.size() - 2, -1, -1):
		a = blocks[i]
		if float(b.t) - float(a.t) >= window_s:
			break
	var span := float(b.t) - float(a.t)
	var frames := int(b.frame) - int(a.frame)
	if span < 1.0 or frames <= 0:
		return {}
	var dups := int(b.dup) - int(a.dup)
	var drops := int(b.drop) - int(a.drop)
	var src := float(frames - dups + drops) / span
	return { "out": float(frames) / span, "src": maxf(0.0, src), "dup": clampf(float(dups) / float(frames), 0.0, 1.0),
		"speed": float(b.get("speed", -1.0)), "span": span }


## Liefert die Quelle spürbar weniger, als sie soll (unter 90 %)?
static func fps_low(m: Dictionary, target: int) -> bool:
	return not m.is_empty() and float(m.src) < float(target) * 0.9


## Protokollzeile zur Bildrate des Puffers.
static func fps_text(m: Dictionary, target: int, path: String) -> String:
	if m.is_empty():
		return "Bildrate: noch keine Messung (%s)" % path
	var t := "Bildrate %s: Quelle liefert %s von %d Bildern/s, %d %% aufgefüllt, Tempo %s (über %d s)" % [path,
		_de1(float(m.src)), target, int(round(float(m.dup) * 100.0)), (_de1(float(m.speed)) + "x") if float(m.speed) >= 0.0 else "?", int(m.span)]
	if fps_low(m, target):
		t += " – zu wenig Bilder: " + fps_hint(path)
	return t


## Woran es liegt, wenn die Quelle zu wenig Bilder liefert (für Protokoll und Einstellungen).
static func fps_hint(path: String) -> String:
	var p := attempt_parts(path)
	if not bool(p.gpu):
		return "Aufnahme über den Arbeitsspeicher (langsamer). Die Grafikkarte ließ sich nicht nutzen."
	if str(p.kind).begins_with("gfx"):
		return "Windows.Graphics.Capture liefert nur, wenn sich das Bild ändert, oder das Spiel selbst läuft langsamer."
	return "Die Grafikkarte ist vermutlich vom Spiel ausgelastet (Bildrate im Spiel begrenzen hilft) oder das Spiel läuft selbst so langsam."


## Bilder und Länge eines fertigen Clips zählen, ohne zu dekodieren (FFmpeg statt ffprobe, das
## Uzai nicht mitlädt). Ausgabe über -progress nach stdout (parse_progress).
static func measure_args(file: String) -> PackedStringArray:
	return PackedStringArray(["-hide_banner", "-nostats", "-loglevel", "error", "-i", file, "-map", "0:v:0", "-c", "copy",
		"-f", "null", "-", "-progress", "pipe:1"])


## Aus der Messung: { frames, seconds, fps } oder {}.
static func measured_clip(text: String, duration: float) -> Dictionary:
	var blocks := parse_progress(text)
	if blocks.is_empty():
		return {}
	var b: Dictionary = blocks[blocks.size() - 1]
	var secs := duration if duration > 0.0 else float(b.t)
	if secs <= 0.0 or int(b.frame) <= 0:
		return {}
	return { "frames": int(b.frame), "seconds": secs, "fps": float(b.frame) / secs }


static func _de1(v: float) -> String:
	return Lang.dec("%.1f" % v)


## Bildschirmfoto als PNG in voller Größe (das dritte Bild: das erste ist manchmal noch leer).
static func shot_args(src: Dictionary, out_png: String) -> PackedStringArray:
	var f := source_filter(src, Vector2i.ZERO, 10, true) + ",hwdownload,format=bgra[v]"
	return PackedStringArray(["-hide_banner", "-loglevel", "error", "-y", "-filter_complex", f, "-map", "[v]",
		"-frames:v", "3", "-update", "1", out_png])


## Kürzen: Kurze Stücke werden genau geschnitten (neu kodiert), lange (über 3 Minuten) nur an
## Schlüsselbildern (-c copy, Anfang bis zu 2 s früher) – das geht sofort.
static func trim_mode(a: float, b: float) -> String:
	return "copy" if b - a > 180.0 else "encode"


static func trim_args(src: String, dst: String, a: float, b: float, enc: String, kbps: int) -> PackedStringArray:
	var x := PackedStringArray(["-hide_banner", "-loglevel", "error", "-y"])
	if trim_mode(a, b) == "copy":
		x.append_array(["-ss", "%.3f" % snap_keyframe(a), "-i", src, "-t", "%.3f" % (b - snap_keyframe(a)), "-map", "0", "-c", "copy",
			"-avoid_negative_ts", "make_zero", "-movflags", "+faststart", dst])
		return x
	x.append_array(["-ss", "%.3f" % a, "-i", src, "-t", "%.3f" % (b - a), "-map", "0:v:0", "-map", "0:a?"])
	var e := enc_args(enc, kbps, 60)
	# Beim Kürzen keine festen Schlüsselbild-Abstände nötig: nur Kodierer und Bitrate übernehmen.
	x.append_array(e.slice(0, e.find("-g")))
	if enc == "x264":
		x[x.find("ultrafast")] = "veryfast"
	x.append_array(["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", dst])
	return x


## Anfang an das Schlüsselbild davor (Uzais Clips: alle SEG_S Sekunden eins).
static func snap_keyframe(t: float) -> float:
	return floorf(maxf(0.0, t) / float(SEG_S)) * float(SEG_S)


## Start und Ende im Clip halten: 0 ≤ a < b ≤ dur, mindestens min_len lang.
static func clamp_trim(a: float, b: float, dur: float, min_len := 1.0) -> Vector2:
	var d := maxf(min_len, dur)
	var bb := clampf(b, min_len, d)
	var aa := clampf(a, 0.0, bb - min_len)
	return Vector2(aa, bb)


## Schrittweite beim Halten von links/rechts: erst 0,5 s, nach 6 Wiederholungen 1 s, nach 16 5 s.
static func trim_step(repeats: int) -> float:
	if repeats >= 16:
		return 5.0
	if repeats >= 6:
		return 1.0
	return 0.5


# --- Discord ---------------------------------------------------------------------------------

## Bitrate (kbit/s), damit ein Clip unter das Discord-Limit passt (ohne Nitro 10 MB): 92 % des
## Limits für Bild und Ton, 96 kbit/s Ton.
static func discord_kbps(duration: float, limit_mb: int) -> int:
	var total := float(limit_mb) * 8000.0 * 0.92 / maxf(1.0, duration)
	return clampi(int(total) - 96, 250, 20000)


static func needs_shrink(size_bytes: int, limit_mb: int) -> bool:
	return size_bytes > limit_mb * 1000 * 1000


## Verkleinern für Discord: höchstens 720p, unter 2,5 Mbit/s auch 30 Bilder/s; -fs als harte Grenze.
static func shrink_args(src: String, dst: String, duration: float, limit_mb: int, enc: String) -> PackedStringArray:
	var k := discord_kbps(duration, limit_mb)
	var vf := "scale=-2:'min(720,ih)'"
	if k < 2500:
		vf += ",fps=30"
	var x := PackedStringArray(["-hide_banner", "-loglevel", "error", "-y", "-i", src, "-map", "0:v:0", "-map", "0:a?", "-vf", vf])
	var e := enc_args(enc, k, 30)
	x.append_array(e.slice(0, e.find("-g")))
	if enc == "x264":
		x[x.find("ultrafast")] = "veryfast"
	x.append_array(["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k", "-fs", str(int(limit_mb * 1000 * 1000 * 0.98)), "-movflags", "+faststart", dst])
	return x


static func discord_dm_url(channel_id: String) -> String:
	return "discord://-/channels/@me/%s" % channel_id if channel_id != "" else "discord://-/channels/@me"


## Textkanal eines Servers in der Discord-App öffnen.
static func discord_channel_url(guild_id: String, channel_id: String) -> String:
	if guild_id == "" or channel_id == "":
		return "discord://-/channels/@me"
	return "discord://-/channels/%s/%s" % [guild_id, channel_id]


## Nur Kanäle, in die man Dateien schreiben kann: Text (0) und Ankündigungen (5) – keine Sprach-
## und Bühnenkanäle, Kategorien, Foren. Zuletzt benutzte zuerst (in ihrer Reihenfolge), sonst
## wie in Discord (position). channels: Antwort von GET_CHANNELS; recent_ids: Kanal-IDs.
static func discord_text_channels(channels: Array, recent_ids: Array = []) -> Array:
	var out: Array = []
	for c in channels:
		if c is Dictionary and int(c.get("type", -1)) in [0, 5] and str(c.get("id", "")) != "":
			out.append({ "id": str(c.id), "name": str(c.get("name", "")), "position": int(c.get("position", 0)) })
	out.sort_custom(func(a, b) -> bool:
		var ra := recent_ids.find(str(a.id))
		var rb := recent_ids.find(str(b.id))
		if ra != rb:
			if ra < 0:
				return false
			if rb < 0:
				return true
			return ra < rb
		return int(a.position) < int(b.position)
	)
	return out


## Zuletzt benutzte Server-Kanäle (neueste zuerst, höchstens max_n, ohne Doppelte).
## entry: { guild_id, guild, channel_id, channel }
static func remember_channel(recent: Array, entry: Dictionary, max_n := 6) -> Array:
	var out: Array = [entry.duplicate()]
	for r in recent:
		if r is Dictionary and str(r.get("channel_id", "")) != str(entry.get("channel_id", "")) and str(r.get("channel_id", "")) != "":
			out.append(r)
	return out.slice(0, max_n)


## Server, in denen zuletzt gesendet wurde, zuerst; sonst wie Discord sie liefert.
static func sort_guilds(guilds: Array, recent: Array) -> Array:
	var order: Array = []
	for r in recent:
		if r is Dictionary and not str(r.get("guild_id", "")) in order:
			order.append(str(r.get("guild_id", "")))
	var out := guilds.duplicate()
	var idx := {}
	for i in out.size():
		idx[str(out[i].get("id", ""))] = i
	out.sort_custom(func(a, b) -> bool:
		var ra := order.find(str(a.get("id", "")))
		var rb := order.find(str(b.get("id", "")))
		if ra != rb:
			if ra < 0:
				return false
			if rb < 0:
				return true
			return ra < rb
		return int(idx[str(a.get("id", ""))]) < int(idx[str(b.get("id", ""))])
	)
	return out


## „An wen?“: zuletzt benutzter Kanal (wenn es einen gibt), Freund, Server-Kanal.
## Werte: "last", "friend", "server" (für main.open_choice: [wert, Text, Zusatz]).
static func discord_targets(last: Dictionary) -> Array:
	var out: Array = []
	if str(last.get("channel_id", "")) != "" and str(last.get("guild_id", "")) != "":
		out.append(["last", "Zuletzt: #%s in %s" % [str(last.get("channel", "Kanal")), str(last.get("guild", "Server"))], "Gleich wieder dorthin"])
	out.append(["friend", "Freund", "Als Direktnachricht"])
	out.append(["server", "Server-Kanal", "In einen Textkanal eines deiner Server"])
	return out


# --- Dateinamen ------------------------------------------------------------------------------

const _RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]


## Für Windows-Dateinamen: ohne \/:*?"<>| und Steuerzeichen, ohne Punkt am Ende, höchstens 60 Zeichen.
static func safe_title(t: String) -> String:
	var out := ""
	for ch in t:
		var c := ch.unicode_at(0)
		if c < 32 or ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
			out += " "
		else:
			out += ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	out = out.strip_edges().left(60).strip_edges()
	while out.ends_with(".") or out.ends_with(" "):
		out = out.left(out.length() - 1)
	if out == "":
		return "Uzai"
	if out.to_upper() in _RESERVED:
		out += "_"
	return out


## „2026-10-17 18-30-05“ aus Time.get_datetime_dict_from_system().
static func stamp(d: Dictionary) -> String:
	return "%04d-%02d-%02d %02d-%02d-%02d" % [int(d.get("year", 2000)), int(d.get("month", 1)), int(d.get("day", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0)), int(d.get("second", 0))]


static func capture_name(title: String, when: Dictionary, ext: String, suffix := "") -> String:
	return "%s %s%s.%s" % [safe_title(title), stamp(when), (" " + suffix) if suffix != "" else "", ext]


## Gibt es den Namen schon, „ (2)“, „ (3)“ … anhängen.
static func unique_name(existing: Array, name: String) -> String:
	if not name in existing:
		return name
	var base := name.get_basename()
	var ext := name.get_extension()
	for i in range(2, 1000):
		var n := "%s (%d).%s" % [base, i, ext]
		if not n in existing:
			return n
	return name


## Zurück aus dem Dateinamen: Titel (Spiel), Zeitpunkt und Sortierschlüssel. Fremde Namen bleiben
## als Titel stehen (Zeitpunkt leer).
static func parse_name(file: String) -> Dictionary:
	var base := file.get_file().get_basename()
	var m := _RX_NAME.search(base)
	if m == null:
		return { "title": base, "stamp": "", "sort": "", "extra": "" }
	var sec := m.get_string(7) if m.get_string(7) != "" else "00"
	var title := m.get_string(1).strip_edges()
	return { "title": title if title != "" else "Uzai",
			"stamp": "%s-%s-%s %s:%s:%s" % [m.get_string(2), m.get_string(3), m.get_string(4), m.get_string(5), m.get_string(6), sec],
		"sort": m.get_string(2) + m.get_string(3) + m.get_string(4) + m.get_string(5) + m.get_string(6) + sec, "extra": m.get_string(8) }


## Neuer Name beim Umbenennen: eigener Titel, Zeitpunkt und Endung bleiben.
static func renamed(file: String, new_title: String) -> String:
	var p := parse_name(file)
	var ext := file.get_extension()
	if str(p.stamp) == "":
		return "%s.%s" % [safe_title(new_title), ext]
	return "%s %s.%s" % [safe_title(new_title), str(p.stamp).replace(":", "-"), ext]


static func kind_of(file: String) -> String:
	match file.get_extension().to_lower():
		"mp4", "mkv", "mov", "webm", "ts":
			return "clip"
		"png", "jpg", "jpeg", "webp", "bmp":
			return "shot"
	return ""


static func mime_for(file: String) -> String:
	match file.get_extension().to_lower():
		"mp4":
			return "video/mp4"
		"mkv":
			return "video/x-matroska"
		"webm":
			return "video/webm"
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"webp":
			return "image/webp"
	return "application/octet-stream"


## Gehört eine Aufnahme zu diesem Spiel? Neue Clips tragen die Spiel-ID (captures.json); ältere
## Clips und Bildschirmfotos nur den Titel im Dateinamen (wie safe_title ihn schrieb).
static func belongs_to(item: Dictionary, game_id: String, title: String) -> bool:
	var gid := str(item.get("game_id", ""))
	if gid != "" and game_id != "":
		return gid == game_id
	if title == "":
		return false
	return str(item.get("title", "")).to_lower() == safe_title(title).trim_suffix("_").strip_edges().to_lower()


## Nach Spielen gruppieren (Reihenfolge: zuletzt aufgenommen zuerst). items: { title, mtime, … }
static func group_by_title(items: Array) -> Array:
	var sorted: Array = items.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return int(a.get("mtime", 0)) > int(b.get("mtime", 0)))
	var order: Array = []
	var by := {}
	for it in sorted:
		var t := str(it.get("title", ""))
		if not by.has(t):
			by[t] = []
			order.append(t)
		(by[t] as Array).append(it)
	return order.map(func(t) -> Dictionary: return { "title": t, "items": by[t] })


# --- Speicherplatz ---------------------------------------------------------------------------

static func cap_bytes(choice: String) -> int:
	var gb := int(choice) if choice.is_valid_int() else 25
	return 0 if gb <= 0 else gb * 1000 * 1000 * 1000


## Passt ein neuer Clip (geschätzte Größe) noch unter die Grenze? cap 0 = unbegrenzt.
static func over_cap(used: int, incoming: int, cap: int) -> bool:
	return cap > 0 and used + incoming > cap


## Grob geschätzte Größe eines Clips (Bild + Ton) in Bytes.
static func estimate_bytes(kbps: int, seconds: float) -> int:
	return int(float(kbps + 160) * 1000.0 / 8.0 * seconds)


static func size_text(bytes: int) -> String:
	if bytes >= 1000 * 1000 * 1000:
		return Lang.dec("%.1f GB" % (bytes / 1.0e9))
	if bytes >= 1000 * 1000:
		return Lang.dec("%.1f MB" % (bytes / 1.0e6))
	return "%d KB" % maxi(1, int(bytes / 1000.0))


static func mmss(sec: float) -> String:
	var s := int(round(maxf(0.0, sec)))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


# --- FFmpeg laden ----------------------------------------------------------------------------

## Aus der Prüfsummenliste von BtbN das neueste Release-Paket (win64, GPL, statisch – nicht
## „shared“) wählen; ohne Release-Paket das aktuelle aus dem Hauptzweig. { file, sha, url } oder {}.
static func pick_build(sums: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^([0-9a-f]{64})\\s+\\*?(ffmpeg-n(\\d+)\\.(\\d+)-latest-win64-gpl-(\\d+)\\.(\\d+)\\.zip)$")
	var best := {}
	var best_v := -1
	var fallback := {}
	for raw in sums.split("\n"):
		var line := raw.strip_edges()
		var m := re.search(line)
		if m:
			var v := int(m.get_string(3)) * 1000 + int(m.get_string(4))
			if v > best_v:
				best_v = v
				best = { "file": m.get_string(2), "sha": m.get_string(1), "version": "%s.%s" % [m.get_string(3), m.get_string(4)] }
		else:
			var parts := line.split(" ", false)
			if parts.size() == 2 and parts[1].trim_prefix("*") == FALLBACK_BUILD and parts[0].length() == 64:
				fallback = { "file": FALLBACK_BUILD, "sha": parts[0], "version": "master" }
	var pick := best if not best.is_empty() else fallback
	if pick.is_empty():
		return {}
	pick["url"] = BUILDS + str(pick.file)
	return pick


# --- Wann läuft der Puffer? ------------------------------------------------------------------

## "" = Puffer soll laufen, sonst der Grund dagegen (für die Einstellungen und das Protokoll).
## s: { via, buffer, ffmpeg, helper, in_game, video, videos, uzai_front_s, on_battery, battery,
## disk_free_mb, recording }
static func buffer_block(s: Dictionary) -> String:
	if str(s.get("via", "uzai")) != "uzai":
		return "via"
	if not bool(s.get("ffmpeg", false)):
		return "ffmpeg"
	if not bool(s.get("helper", false)):
		return "helper"
	if bool(s.get("recording", false)):
		return ""
	if not bool(s.get("buffer", true)):
		return "aus"
	var playing := bool(s.get("in_game", false)) or (bool(s.get("video", false)) and bool(s.get("videos", false)))
	if not playing:
		return "kein_spiel"
	if float(s.get("uzai_front_s", 0.0)) > UZAI_FRONT_S:
		return "uzai_vorn"
	if bool(s.get("on_battery", false)) and not bool(s.get("battery", false)):
		return "akku"
	if int(s.get("disk_free_mb", 1 << 30)) < MIN_FREE_MB:
		return "platz"
	return ""


static func block_text(why: String) -> String:
	match why:
		"via":
			return "Aufnahme läuft über Windows Game Bar oder NVIDIA (Einstellungen → Aufnahmen)."
		"ffmpeg":
			return "FFmpeg fehlt noch – Uzai lädt es beim ersten Mal (Einstellungen → Aufnahmen)."
		"helper":
			return "Der Windows-Helfer läuft nicht."
		"aus":
			return "Der Clip-Puffer ist ausgeschaltet (Einstellungen → Aufnahmen)."
		"kein_spiel":
			return "Der Clip-Puffer läuft, sobald ein Spiel vorn ist."
		"uzai_vorn":
			return "Uzai ist seit einer Weile vorn – der Puffer ruht, bis das Spiel wieder vorn ist."
		"akku":
			return "Im Akkubetrieb ruht der Puffer (Einstellungen → Aufnahmen)."
		"platz":
			return "Zu wenig freier Speicher für den Puffer (unter 2 GB)."
	return ""


## Versuche in dieser Reihenfolge: Bildquelle × Kodierer × (Grafikkarte, Arbeitsspeicher). Was
## zuletzt lief (working, z. B. "dda|nvenc|gpu"), kommt zuerst. window: nur das Spielfenster.
## Der langsame Weg über den Arbeitsspeicher (…|cpu) bleibt nie für immer vorn: Lief zuletzt nur
## er, kommt der Grafikkarten-Weg desselben Kodierers trotzdem zuerst dran (scheitert der, merkt
## man das sofort; ein einmal hakender Treiber soll nicht dauerhaft weniger Bilder bedeuten).
static func attempts(window: bool, working := "") -> Array:
	var srcs := ["gfx_win", "dda", "gfx_mon"] if window else ["dda", "gfx_mon"]
	var out: Array = []
	for s in srcs:
		for e in ENCODERS:
			for g in ["gpu", "cpu"]:
				out.append("%s|%s|%s" % [s, e, g])
	if working != "" and working in out:
		out.erase(working)
		out.push_front(working)
		if working.ends_with("|cpu"):
			var fast := working.trim_suffix("|cpu") + "|gpu"
			out.erase(fast)
			out.push_front(fast)
	return out


static func attempt_parts(a: String) -> Dictionary:
	var p := a.split("|")
	return { "kind": p[0] if p.size() > 0 else "dda", "enc": p[1] if p.size() > 1 else "x264", "gpu": p.size() > 2 and p[2] == "gpu" }


# --- Ans Handy (Heimnetz) --------------------------------------------------------------------

## „Range: bytes=a-b“ → [a, b] (b einschließlich); [] = ganze Datei; [-1] = nicht erfüllbar (416).
static func parse_range(header: String, size: int) -> Array:
	var h := header.strip_edges().to_lower()
	if not h.begins_with("bytes=") or h.contains(","):
		return []
	var spec := h.substr(6).strip_edges()
	var dash := spec.find("-")
	if dash < 0:
		return []
	var a_s := spec.substr(0, dash).strip_edges()
	var b_s := spec.substr(dash + 1).strip_edges()
	if a_s == "" and b_s == "":
		return []
	if a_s == "":
		if not b_s.is_valid_int():
			return []
		var n := mini(int(b_s), size)
		return [size - n, size - 1] if n > 0 else [-1]
	if not a_s.is_valid_int() or (b_s != "" and not b_s.is_valid_int()):
		return []
	var a := int(a_s)
	var b := int(b_s) if b_s != "" else size - 1
	if a >= size or a > b:
		return [-1]
	return [a, mini(b, size - 1)]


## Seite fürs Handy: Vorschau, „Herunterladen“, dann über das Teilen-Menü des Handys weiter.
## items: { name, url, kind (clip|shot), size }
static func share_page(items: Array) -> String:
	var rows := ""
	for it in items:
		var n := _esc(str(it.get("name", "")))
		var u := _esc(str(it.get("url", "")))
		var media := ("<video src='%s' controls playsinline preload='metadata'></video>" % u) if str(it.get("kind", "")) == "clip" else ("<img src='%s' alt=''>" % u)
		rows += "<div class='it'>%s<p class='n'>%s<span>%s</span></p><a class='dl' href='%s?dl=1' download='%s'>Herunterladen</a></div>" % [media, n,
				_esc(size_text(int(it.get("size", 0)))), u, n]
	return """<!doctype html><html lang='de'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Uzai · Aufnahmen</title>
<style>body{margin:0;background:#110e0c;color:#f7efe7;font:17px/1.45 system-ui,sans-serif;padding:28px 20px}h1{font-size:28px;margin:0 0 6px;font-weight:900}h1 b{color:#ff8a57}
.hint{color:#bcaa9b;font-size:15px;margin:0 0 20px}.it{margin:0 0 28px}video,img{width:100%%;border-radius:14px;background:#000;display:block}
.n{margin:10px 2px;font-weight:700}.n span{display:block;font-weight:400;color:#806f63;font-size:14px}
.dl{display:block;text-align:center;padding:16px;border-radius:12px;background:#f7efe7;color:#110e0c;font-weight:800;text-decoration:none}</style></head>
<body><h1>uzai<b>.</b></h1><p class='hint'>Herunterladen, dann in der Fotos- oder Dateien-App über „Teilen“ an Discord, WhatsApp, Steam & Co. schicken. Der Link gilt nur im Heimnetz und läuft nach 30 Minuten ab.</p>%s</body></html>""" % rows


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;").replace("\"", "&quot;")

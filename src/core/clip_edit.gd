extends RefCounted
## Clip bearbeiten (Punkt 137): Anfang und Ende, Zeitlupe für einen Bereich, ein Text oben und
## unten, auf Wunsch ohne Ton. Hier nur die Logik ohne Oberfläche – Bereiche, Namen, die
## Befehlszeilen für FFmpeg und der Fortschritt (tests/logic_clipedit.gd). Ausführen:
## Capture.edit_clip, Oberfläche: src/ui/layers/capture_edit.gd. Das Original bleibt immer.
##
## Sicherheit: FFmpeg bekommt ein Argument-Array, keine Shell. Eigener Text kommt nie in den
## Filtergraphen, sondern steht in einer Textdatei in Uzais Datenordner (drawtext mit textfile=,
## expansion=none: kein %{…}). Die Pfade zu Text und Schrift werden nach FFmpegs zwei Stufen
## maskiert (filter_value), damit auch „C:\Users\O'Neil, Max\…“ nichts am Graphen ändert.
##
## Ein Plan: { a, b (Anfang/Ende im Clip), sa, sb (Zeitlupe von/bis), speed (1 = keine Zeitlupe),
## top, bottom (Text), mute (ohne Ton) } – alle Zeiten in Sekunden im Original.

const L := preload("res://src/core/capture_logic.gd")
const Lang := preload("res://src/core/lang.gd")

static var _RX_TON := RegEx.create_from_string("Stream #\\d+:\\d+[^\\n]*: Audio:")

const SPEEDS := [[1.0, "Aus"], [0.5, "0,5×"], [0.25, "0,25×"]]
const MIN_LEN := 1.0              ## kürzer wird ein Clip nicht
const SLOW_MIN := 0.5             ## Zeitlupe mindestens so lang
const SEG_MIN := 0.05             ## kürzere Stücke fallen beim Zusammensetzen weg
const TEXT_MAX := 60
const FINE_S := 0.1               ## LT/RT: so fein verschiebt ein Druck
const STRIP_N := 12               ## Bilder im Bildstreifen der Zeitleiste
const STRIP_W := 192
const STRIP_H := 108
const PREVIEW_W := 640            ## Vorschau: klein und mit 30 Bildern/s, damit sie schnell da ist
const PREVIEW_FPS := 30
## Uzais Schrift; Zeichen außerhalb von Latin-1 (etwa Kyrillisch) kann sie nicht – dann Atkinson.
const FONTS := { "hanken": "res://assets/fonts/HankenGrotesk-latin.woff2", "atkinson": "res://assets/fonts/AtkinsonHyperlegibleNext-VF.ttf" }
## Text im Bild: so groß wie ein Dreizehntel der Bildhöhe, weiß mit weichem Rand und Schatten.
const TEXT_SIZE := 13.0
const TEXT_TOP := 0.06            ## Abstand oben, Anteil der Bildhöhe
const TEXT_BOTTOM := 0.08


# --- Plan und Bereiche ------------------------------------------------------------------------

## Anfangsplan: ganzer Clip, Zeitlupe (noch aus) im mittleren Drittel.
static func plan(dur: float) -> Dictionary:
	var d := maxf(MIN_LEN, dur)
	return { "a": 0.0, "b": d, "sa": d / 3.0, "sb": d * 2.0 / 3.0, "speed": 1.0, "top": "", "bottom": "", "mute": false }


## Alles im Clip halten: 0 ≤ a < b ≤ dur (mindestens MIN_LEN), Zeitlupe innerhalb von a…b und
## mindestens SLOW_MIN lang (ist der Clip kürzer: der ganze Clip). Gibt einen neuen Plan zurück.
static func clamp_plan(p: Dictionary, dur: float) -> Dictionary:
	var q := p.duplicate()
	var ab := L.clamp_trim(float(p.get("a", 0.0)), float(p.get("b", dur)), dur, MIN_LEN)
	q.a = ab.x
	q.b = ab.y
	var span := ab.y - ab.x
	if span <= SLOW_MIN:
		q.sa = ab.x
		q.sb = ab.y
	else:
		var sb := clampf(float(p.get("sb", ab.y)), ab.x + SLOW_MIN, ab.y)
		q.sa = clampf(float(p.get("sa", ab.x)), ab.x, sb - SLOW_MIN)
		q.sb = sb
	var sp := float(p.get("speed", 1.0))
	q.speed = sp if _speed_ok(sp) else 1.0
	q.top = clean_text(str(p.get("top", "")))
	q.bottom = clean_text(str(p.get("bottom", "")))
	q.mute = bool(p.get("mute", false))
	return q


static func _speed_ok(sp: float) -> bool:
	for s in SPEEDS:
		if is_equal_approx(float(s[0]), sp):
			return true
	return false


static func has_slow(p: Dictionary) -> bool:
	return float(p.get("speed", 1.0)) < 1.0 and float(p.sb) - float(p.sa) >= SEG_MIN


## Stücke ab Anfang a: [[von, bis, Tempo], …] in Sekunden ab a. Zu kurze Stücke fallen weg.
static func segments(p: Dictionary) -> Array:
	var a := float(p.a)
	var d := float(p.b) - a
	if not has_slow(p):
		return [[0.0, d, 1.0]]
	var out: Array = []
	for s in [[0.0, float(p.sa) - a, 1.0], [float(p.sa) - a, float(p.sb) - a, float(p.speed)], [float(p.sb) - a, d, 1.0]]:
		if float(s[1]) - float(s[0]) >= SEG_MIN:
			out.append(s)
	return out


## Länge des fertigen Clips (Zeitlupe dehnt ihren Bereich).
static func out_length(p: Dictionary) -> float:
	var n := 0.0
	for s in segments(p):
		n += (float(s[1]) - float(s[0])) / float(s[2])
	return n


## Stelle im Original zu einer Zeit im fertigen Clip (Abspielmarke der Vorschau).
static func src_at(p: Dictionary, t_out: float) -> float:
	var t := maxf(0.0, t_out)
	for s in segments(p):
		var len_out := (float(s[1]) - float(s[0])) / float(s[2])
		if t <= len_out:
			return float(p.a) + float(s[0]) + t * float(s[2])
		t -= len_out
	return float(p.b)


## Ist überhaupt etwas zu tun? (Sonst bleibt „Speichern“ aus.)
static func is_changed(p: Dictionary, dur: float) -> bool:
	return float(p.a) > 0.05 or float(p.b) < dur - 0.05 or has_slow(p) or str(p.top) != "" or str(p.bottom) != "" or bool(p.mute)


## Nur geschnitten (kein Text, keine Zeitlupe, Ton bleibt): dann reicht Kürzen (oft ohne neu zu
## kodieren, siehe capture_logic.trim_mode).
static func only_cut(p: Dictionary) -> bool:
	return not has_slow(p) and str(p.top) == "" and str(p.bottom) == "" and not bool(p.mute)


# --- Text ------------------------------------------------------------------------------------

## Eine Zeile, höchstens TEXT_MAX Zeichen: Steuerzeichen und Zeilenumbrüche werden Leerzeichen,
## mehrere Leerzeichen eins.
static func clean_text(s: String) -> String:
	var out := ""
	var space := false
	for ch in s:
		var c := ch.unicode_at(0)
		var blank := c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or c == 0x2028 or c == 0x2029 or ch == " " or c == 0xA0
		if blank:
			space = out != ""
			continue
		if space:
			out += " "
			space = false
		out += ch
	return out.left(TEXT_MAX)


## Welche Schrift: Uzais Hanken Grotesk, außer der Text braucht Zeichen jenseits von Latin-1.
static func font_key(text: String) -> String:
	for ch in text:
		if ch.unicode_at(0) > 0xFF:
			return "atkinson"
	return "hanken"


## Wert für eine Filter-Option, zweimal maskiert wie in FFmpegs Doku („Quoting and escaping“):
## erst innerhalb der Option (\ ' :), dann für den Filtergraphen (\ ' [ ] , ;).
static func filter_value(s: String) -> String:
	var one := ""
	for ch in s:
		if ch in ["\\", "'", ":"]:
			one += "\\"
		one += ch
	var two := ""
	for ch in one:
		if ch in ["\\", "'", "[", "]", ",", ";"]:
			two += "\\"
		two += ch
	return two


## Pfad für FFmpeg: Schrägstriche (unter Windows nimmt FFmpeg beide), dann maskiert.
static func filter_path(p: String) -> String:
	return filter_value(p.replace("\\", "/"))


static func drawtext(font_file: String, text_file: String, top: bool) -> String:
	var y := ("h*%s" % str(TEXT_TOP)) if top else ("h-text_h-h*%s" % str(TEXT_BOTTOM))
	return "drawtext=fontfile=%s:textfile=%s:expansion=none:fontsize=h/%s:fontcolor=white:borderw=2:bordercolor=black@0.55:shadowcolor=black@0.4:shadowx=2:shadowy=3:x=(w-text_w)/2:y=%s" % [
		filter_path(font_file), filter_path(text_file), str(TEXT_SIZE), y]


# --- FFmpeg ----------------------------------------------------------------------------------

static func _num(v: float) -> String:
	return "%.3f" % maxf(0.0, v)


static func _tempo(speed: float) -> String:
	# atempo kann je Filter höchstens auf die Hälfte bremsen: 0,25× sind zwei hintereinander.
	var out := PackedStringArray()
	var left := speed
	while left < 0.999:
		var f := maxf(0.5, left)
		out.append("atempo=%s" % str(f))
		left /= f
	return ",".join(out)


## Der Filtergraph. o: { audio (Quelle hat Ton), top_file, top_font, bottom_file, bottom_font,
## preview (klein, 30 Bilder/s) }. Rückgabe: { graph, audio_map ("[aout]", "0:a:0" oder "") }.
## Die Eingabe ist schon ab a gestartet und auf b - a begrenzt (-ss/-t vor -i): alle Zeiten
## im Graphen zählen ab a.
static func graph(p: Dictionary, o: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	var segs := segments(p)
	var want_audio := bool(o.get("audio", false)) and not bool(p.get("mute", false))
	var v := "[0:v]"
	var amap := "0:a:0" if want_audio else ""
	var chain := PackedStringArray()
	if segs.size() > 1:
		var n := segs.size()
		var vs := ""
		var as_ := ""
		for i in n:
			vs += "[v%d]" % i
			as_ += "[a%d]" % i
		parts.append("[0:v]split=%d%s" % [n, vs])
		if want_audio:
			parts.append("[0:a]asplit=%d%s" % [n, as_])
		var cat := ""
		for i in n:
			var s: Array = segs[i]
			parts.append("[v%d]trim=start=%s:end=%s,setpts=%s*(PTS-STARTPTS)[v%do]" % [i, _num(s[0]), _num(s[1]), str(1.0 / float(s[2])), i])
			cat += "[v%do]" % i
			if want_audio:
				var t := _tempo(float(s[2]))
				parts.append("[a%d]atrim=start=%s:end=%s,asetpts=PTS-STARTPTS%s[a%do]" % [i, _num(s[0]), _num(s[1]), ("," + t) if t != "" else "", i])
				cat += "[a%do]" % i
		parts.append("%sconcat=n=%d:v=1:a=%d[vc]%s" % [cat, n, 1 if want_audio else 0, "[ac]" if want_audio else ""])
		v = "[vc]"
		if want_audio:
			amap = "[ac]"
	elif not segs.is_empty() and float(segs[0][2]) < 1.0:
		# Der ganze Clip in Zeitlupe: ohne Teilen.
		chain.append("setpts=%s*PTS" % str(1.0 / float(segs[0][2])))
		if want_audio:
			parts.append("[0:a]%s[aout]" % _tempo(float(segs[0][2])))
			amap = "[aout]"
	if str(p.get("top", "")) != "" and str(o.get("top_file", "")) != "":
		chain.append(drawtext(str(o.top_font), str(o.top_file), true))
	if str(p.get("bottom", "")) != "" and str(o.get("bottom_file", "")) != "":
		chain.append(drawtext(str(o.bottom_font), str(o.bottom_file), false))
	if bool(o.get("preview", false)):
		chain.append("scale=%d:-2" % PREVIEW_W)
		chain.append("fps=%d" % PREVIEW_FPS)
	chain.append("format=yuv420p")
	parts.append("%s%s[vout]" % [v, ",".join(chain)])
	return { "graph": ";".join(parts), "audio_map": amap }


## Gemeinsamer Anfang: Fortschritt auf die Standardausgabe (Capture liest ihn mit), Eingabe ab a.
static func _head(src: String, p: Dictionary, g: Dictionary) -> PackedStringArray:
	var x := PackedStringArray(["-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y",
		"-ss", _num(float(p.a)), "-t", _num(float(p.b) - float(p.a)), "-i", src, "-filter_complex", str(g.graph), "-map", "[vout]"])
	if str(g.audio_map) != "":
		x.append_array(["-map", str(g.audio_map)])
	return x


## Fertiger Clip als MP4 neben dem Original. enc/kbps wie beim Aufnehmen (Grafikkarte, sonst x264).
static func export_args(src: String, dst: String, p: Dictionary, o: Dictionary, enc: String, kbps: int) -> PackedStringArray:
	var g := graph(p, o)
	var x := _head(src, p, g)
	var e := L.enc_args(enc, kbps, 60)
	x.append_array(e.slice(0, e.find("-g")))
	if enc == "x264":
		x[x.find("ultrafast")] = "veryfast"
	x.append_array(["-pix_fmt", "yuv420p"])
	if str(g.audio_map) != "":
		x.append_array(["-c:a", "aac", "-b:a", "160k"])
	else:
		x.append("-an")
	x.append_array(["-movflags", "+faststart", dst])
	return x


## Vorschau zum Abspielen in Uzai (Godot spielt Theora/Vorbis in Ogg): klein, schnell, mit allem.
static func preview_args(src: String, dst: String, p: Dictionary, o: Dictionary) -> PackedStringArray:
	var q := o.duplicate()
	q["preview"] = true
	var g := graph(p, q)
	var x := _head(src, p, g)
	x.append_array(["-c:v", "libtheora", "-q:v", "6"])
	if str(g.audio_map) != "":
		x.append_array(["-c:a", "libvorbis", "-q:a", "3", "-ac", "2", "-ar", "48000"])
	else:
		x.append("-an")
	x.append(dst)
	return x


## Nur schneiden, mit Fortschritt: capture_logic.trim_args, dazu die Fortschrittsausgabe.
static func cut_args(src: String, dst: String, p: Dictionary, enc: String, kbps: int) -> PackedStringArray:
	var x := L.trim_args(src, dst, float(p.a), float(p.b), enc, kbps)
	var at := x.find("-y")
	for i in 3:
		x.insert(at + 1 + i, ["-nostats", "-progress", "pipe:1"][i])
	return x


## Bildstreifen der Zeitleiste: STRIP_N Bilder gleichmäßig über den Clip, nebeneinander in einem
## JPG. Jede Stelle wird einzeln angesprungen (schnell, auch bei seltenen Schlüsselbildern).
static func strip_args(src: String, dst: String, dur: float) -> PackedStringArray:
	var x := PackedStringArray(["-hide_banner", "-loglevel", "error", "-y"])
	var fc := PackedStringArray()
	var st := ""
	for i in STRIP_N:
		x.append_array(["-ss", "%.3f" % (maxf(0.1, dur) * (float(i) + 0.5) / float(STRIP_N)), "-i", src])
		fc.append("[%d:v]scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,setsar=1[s%d]" % [i, STRIP_W, STRIP_H, STRIP_W, STRIP_H, i])
		st += "[s%d]" % i
	fc.append("%shstack=inputs=%d[out]" % [st, STRIP_N])
	x.append_array(["-filter_complex", ";".join(fc), "-map", "[out]", "-frames:v", "1", "-q:v", "5", dst])
	return x


## Was im Clip steckt (Ausgabe von „ffmpeg -i …“): { duration, audio }.
static func probe_info(text: String) -> Dictionary:
	return { "duration": L.parse_duration(text), "audio": _RX_TON.search(text) != null }


static func probe_args(src: String) -> PackedStringArray:
	return PackedStringArray(["-hide_banner", "-i", src])


## Sekunden, die FFmpeg schon geschrieben hat (letzte „out_time_us=“ aus -progress), sonst -1.
static func parse_out_time(text: String) -> float:
	var at := text.rfind("out_time_us=")
	if at < 0:
		return -1.0
	var end := text.find("\n", at)
	var v := text.substr(at + 12, (end - at - 12) if end > 0 else -1).strip_edges()
	return float(v) / 1000000.0 if v.is_valid_int() else -1.0


# --- Namen und Anzeige -----------------------------------------------------------------------

## „Elden Ring 2026-10-22 18-30-00 (bearbeitet).mp4“ neben dem Original; ein schon vorhandener
## Zusatz („gekürzt“) wird ersetzt, gleiche Namen bekommen „ (2)“. cut: nur geschnitten.
static func edited_name(existing: Array, file: String, cut := false) -> String:
	var base := file.get_file().get_basename()
	var extra := str(L.parse_name(file).extra)
	if extra != "" and base.ends_with(" (%s)" % extra):
		base = base.trim_suffix(" (%s)" % extra)
	return L.unique_name(existing, "%s (%s).mp4" % [base, "gekürzt" if cut else "bearbeitet"])


## „0:12,4“ – Minuten, Sekunden und Zehntel (zum Feinjustieren), Komma je nach Sprache.
static func time_text(t: float) -> String:
	var d := int(roundf(maxf(0.0, t) * 10.0))
	return Lang.dec("%d:%02d.%d" % [d / 600, (d / 10) % 60, d % 10])


static func speed_text(speed: float) -> String:
	for s in SPEEDS:
		if is_equal_approx(float(s[0]), speed):
			return str(s[1])
	return "Aus"


## Eine Zeile unter der Zeitleiste: Länge vorher → nachher und was sonst passiert.
## t übersetzt die Muster (tr der Oberfläche), ohne bleibt der Text deutsch. Die Zeile ändert sich mit jedem Schritt
## an der Zeitleiste: Als Ganzes wäre sie für die Übersetzung jedes Mal ein neuer Text.
static func summary(p: Dictionary, t := Callable()) -> String:
	var u := func(s: String) -> String: return str(t.call(s)) if t.is_valid() else s
	var bits := PackedStringArray()
	var len_in := float(p.b) - float(p.a)
	var len_out := out_length(p)
	if absf(len_out - len_in) > 0.05:
		bits.append(str(u.call("Länge %s → %s")) % [time_text(len_in), time_text(len_out)])
	else:
		bits.append(str(u.call("Länge %s")) % time_text(len_in))
	if has_slow(p):
		bits.append(str(u.call("Zeitlupe %s von %s bis %s")) % [speed_text(float(p.speed)), time_text(float(p.sa)), time_text(float(p.sb))])
	if bool(p.mute):
		bits.append(str(u.call("ohne Ton")))
	return "  ·  ".join(bits)

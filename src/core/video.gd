extends Node
## Spielt YouTube-Videos über mpv ab. mpv holt den Videostrom über yt-dlp, deshalb gibt es
## keine Werbung. Uzai liegt als durchsichtiges Fenster darüber, zeichnet die eigene Leiste
## und steuert mpv über dessen Steuerkanal (Pipe). SponsorBlock-Abschnitte werden übersprungen,
## der Fortschritt wird laufend gemerkt.
##
## Ohne Windows oder ohne mpv (Demo, Tests) läuft eine Simulation mit derselben Logik.
##
## Ton- und Untertitelspuren (Filme mit mehreren Sprachen): load_tracks liest mpvs „track-list“,
## set_track wählt um. Die gewählte Tonsprache merkt sich Uzai (video.audio_lang) für den nächsten Film.
##
## Im Hintergrund (background): „Nur Ton“ läuft wie Musik weiter, während du in Uzai woanders bist –
## ohne Player, gesteuert im Guide (Reiter „Video-Ton“). Am Ende geht es mit dem nächsten Video der
## Liste weiter (wie „Automatisch weiter“), ein Spielstart beendet es.
##
## Shorts (shorts): Hochkant-Videos nacheinander; im Player blättern hoch/runter, am Ende kommt
## gleich das nächste. Die Qualität gilt dort für die Breite (ein 1080p-Short ist 1080 breit).

signal changed
signal started(video: Dictionary)
signal reached_end
signal stopped
signal skipped(text: String)
signal volume_changed(level: int)

const Leicht := preload("res://src/core/leicht.gd")
const PlayerLog := preload("res://src/core/player_log.gd")
const Fremd := preload("res://src/core/fremd.gd")
## Antwortet mpv so lange nach dem Start nicht über den Steuerkanal, steht es im Protokoll.
const IPC_WARN_MS := 15000
## Steuerkanal zu mpv: je Start ein zufälliger Name. Mit einem festen Namen hätte ein anderes Konto die Leitung vorher
## anlegen und die Stream-Adressen (bei Addons oft mit Schlüssel) mitlesen können.
const PIPE_VORSILBE := "uzai-mpv-"
var _pipe := PIPE_VORSILBE + "0"
## Lautstärke des Videos in mpv (0…130 %, über 100 verstärkt mpv). Eine Stufe für YouTube, Trailer
## und Filme, gespeichert in youtube.volume. Nie die Gesamtlautstärke von Windows.
const VOLUME_MAX := 130
const VOLUME_STEP := 5
## SDR first (dynamic_range=?SDR: also when yt-dlp does not know the range): HDR versions made mpv switch
## the display to HDR, and the TV renegotiated the signal (VRR dropouts). If only HDR exists, it is still
## used – mpv then maps it to SDR (RUHIG_CONF).
const QUALITY := {
	"720": "bv*[height<=720][dynamic_range=?SDR]+ba/bv*[height<=720]+ba/b[height<=720]/b",
	"1080": "bv*[height<=1080][dynamic_range=?SDR]+ba/bv*[height<=1080]+ba/b[height<=1080]/b",
	"1440": "bv*[height<=1440][dynamic_range=?SDR]+ba/bv*[height<=1440]+ba/b[height<=1440]/b",
	"2160": "bv*[height<=2160][dynamic_range=?SDR]+ba/bv*[height<=2160]+ba/b[height<=2160]/b",
	"ton": "ba/b",
}

## Ruhig für Fernseher mit VRR (HDMI 2.1): mpv gibt Bilder in der Rate des Bildschirms aus statt in
## der des Videos (24/30 fps lagen unter dem VRR-Bereich vieler Fernseher) und schaltet nie selbst
## auf HDR um (kein neues Aushandeln des Signals). Als eigene Datei per --include: Eine Option, die
## ein altes mpv nicht kennt, meldet es dort nur, statt gar nicht zu starten.
const RUHIG_CONF := "# Uzai: feste Bildrate, kein Umschalten auf HDR (Fernseher mit VRR)\nvideo-sync=display-resample\ntarget-colorspace-hint=no\n"

## Für die Vorführung und Proben: so sieht ein Film mit zwei Sprachen und Untertiteln aus.
const DEMO_TRACKS := [
	{ "id": 1, "type": "audio", "lang": "ger", "title": "", "selected": true, "demux-channel-count": 6 },
	{ "id": 2, "type": "audio", "lang": "eng", "title": "", "selected": false, "demux-channel-count": 6 },
	{ "id": 3, "type": "audio", "lang": "eng", "title": "Kommentar", "selected": false, "demux-channel-count": 2 },
	{ "id": 1, "type": "sub", "lang": "ger", "title": "", "selected": false },
	{ "id": 2, "type": "sub", "lang": "ger", "title": "Forced", "selected": false },
	{ "id": 3, "type": "sub", "lang": "eng", "title": "", "selected": false, "external": true },
]

var active := false
var video: Dictionary = {}
var queue: Array = []
var index := 0
var pos := 0.0
var duration := 0.0
var paused := false
var loading := true
var at_end := false
var speed := 1.0
var audio_only := false
var subs := false
var quality := "1080"
var segments: Array = []
var tracks: Array = []      ## Ton und Untertitel des laufenden Videos (parse_tracks), nach load_tracks
var sim_tracks: Array = []  ## Simulation: Spuren, die load_tracks liefert (leer: Vorführung bei Filmen)
var error := ""
var sim := false
## Bild in Bild (src/core/pip.gd): mpv liegt klein in einer Ecke statt im Vollbild.
var pip := false
var background := false     ## nur Ton, ohne Player (siehe oben)
var shorts := false         ## Shorts nacheinander (siehe oben)
## Zuletzt übersprungener Abschnitt: { i, start, at (ms) }. Kurz danach führt „links“ zurück.
var last_skip := {}
const UNDO_MS := 6000

var _pid := 0
var _pid_endet := 0         ## mpv, das stop() gerade beendet (wartet noch auf „quit“)
var _gen := 0              ## zählt jedes Öffnen: stop() erkennt so ein neues Video in seiner Wartezeit
var _pip_geom := ""         ## Größe und Lage für einen Start gleich als Bild in Bild
var _rid := 0
var _poll_t := 0.0
var _save_t := 0.0
var _skipped := {}
var _polling := false
var _pending_seek := -1.0
var _sim_load := 0.0
var _gone := 0
var _meta_sent := false
var _subs_sent := 0
var _vol_busy := false      ## ein Lautstärke-Befehl ist unterwegs zu mpv
var _vol_dirty := false     ## währenddessen weiter gedrückt: danach den neuesten Stand schicken
var _mpv_audio := false     ## mpv läuft gerade ohne Bild (beim Start bzw. letzten Umschalten)
var _swipe := 0             ## Shorts: Blätterrichtung des nächsten Ladens (für das Gleiten in mpv)
var _t_open := -1           ## Start bis Bild messen (logs/leistung.log): ms beim Öffnen, -1 = gemeldet
var _t_weg := ""            ## wie geladen: „vorab aufgelöst“ oder „über yt-dlp“
var _t_laden := false       ## seit dem Öffnen schon „lädt“ gesehen (sonst meldet mpv noch das alte Video)
var _lief := false          ## seit dem Öffnen schon eine Stelle gesehen (sonst ist ein Ende von mpv ein Fehlstart)
var _ipc_ok := false        ## mpv hat seit dem Start schon einmal geantwortet
var _ipc_warned := false
var _t_launch := 0          ## ms beim Start von mpv
static var _osd_ready := false
static var _ruhig_ready := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Liste abspielen, ab Eintrag idx. opts: { start: Sekunden, audio: bool, pip: gleich als Bild in
## Bild, pip_geometry: „BxH+X+Y“ dafür }. Läuft schon Bild in Bild (nächste Folge), bleibt es dabei.
func play(list: Array, idx := 0, opts := {}) -> void:
	if list.is_empty():
		return
	if opts.has("pip"):
		pip = bool(opts.pip)
	_pip_geom = str(opts.get("pip_geometry", _pip_geom))
	queue = list.duplicate()
	index = clampi(idx, 0, list.size() - 1)
	audio_only = bool(opts.get("audio", false))
	background = audio_only and bool(opts.get("background", false))
	shorts = bool(opts.get("shorts", false))
	quality = str(Config.get_value("youtube.quality", "1080"))
	subs = bool(Config.get_value("youtube.subtitles", false))
	speed = 1.0
	var v: Dictionary = queue[index]
	var start := float(opts.get("start", 0.0 if is_direct(v) or shorts else YouTube.resume_pos(str(v.id))))
	_open(v, start)


func _open(v: Dictionary, start: float) -> void:
	_gen += 1
	var prev := video
	var swipe := _swipe
	_swipe = 0
	video = v
	pos = start
	duration = float(v.get("duration", 0))
	paused = false
	loading = true
	at_end = false
	error = ""
	segments = []
	_skipped = {}
	last_skip = {}
	_pending_seek = -1.0
	_sim_load = 0.0
	_gone = 0
	_subs_sent = 0
	tracks = []
	_t_open = Time.get_ticks_msec()
	_t_weg = ""
	_t_laden = false
	_lief = false
	# Direkte Adressen (Trailer aus dem Shop) braucht nur mpv, kein yt-dlp.
	var direct := is_direct(v)
	# Twitch (Streams) hat eine direkte Adresse, braucht aber yt-dlp wie YouTube.
	var tools_ok := YouTube.has_mpv() if direct and not v.has("twitch") else YouTube.tools_ready()
	sim = not Config.is_windows() or YouTube.demo or not tools_ok
	if Config.is_windows() and not YouTube.demo and not tools_ok:
		# Unter Windows nie still eine Vorführung abspielen: Das sah aus wie ein Video, das nicht lädt.
		sim = false
		active = true
		_fail_start("Der Player ist noch nicht eingerichtet.", "mpv %s, yt-dlp %s" % [_da(YouTube.has_mpv()), _da(YouTube.has_ytdlp())], true)
		return
	var was_active := active
	active = true
	_meta_sent = false
	if not sim and url(v) == "":
		# Adresse aus fremder Quelle, die kein http(s) ist (Addon): gar nicht erst an mpv.
		error = "Diese Quelle lässt Uzai nicht zu (nur Adressen mit http oder https)."
		_finish()
		return
	if not sim:
		# Filme (Addon-Streams) bringen eigene Kopfzeilen und Untertitel mit: dafür mpv neu starten,
		# damit nichts davon an einem YouTube-Video hängen bleibt (und umgekehrt).
		var fresh := v.has("movies") or prev.has("movies")
		if was_active and _pid > 0 and OS.is_process_running(_pid) and not fresh:
			# Format ausdrücklich (ein Short nach einem breiten Video wählt nach der Breite). Lief eben
			# „Nur Ton“ (Hintergrund) und jetzt kommt ein Video mit Bild: Bild und Fenster wieder an.
			var c: Array = [["set_property", "ytdl-format", ytdl_format(v, quality, audio_only)]]
			if audio_only != _mpv_audio:
				c.append(["set_property", "vid", "no" if audio_only else "auto"])
				if front_mode() and not pip:
					c.append_array([["set_property", "window-minimized", audio_only], ["set_property", "ontop", not audio_only]])
				_mpv_audio = audio_only
			# Shorts blättern, mpv vorn: Uzais Leiste deckt den Wechsel mit einem Gleiten ab – im
			# selben Paket wie das Laden, damit es sicher davor ankommt (uzai_osd.lua, „swipe“).
			if swipe != 0 and front_mode() and not pip:
				c.insert(0, ["script-message-to", "uzai_osd", "swipe", str(swipe)])
			c.append_array([["set_property", "start", str(int(start))], ["set_property", "pause", false]])
			# Schon aufgelöste Adressen (Shorts: prefetch_shorts, sonst vorab()) – kein yt-dlp beim Wechsel.
			var pre := _pre_take(v) if pre_ok(v, subs, audio_only) else {}
			_t_weg = "vorab aufgelöst" if not pre.is_empty() else "über yt-dlp"
			_pre_ms = int(pre.get("ms", 0))
			c.append_array(load_cmds(pre, url(v)))
			# Beim Blättern über den freien Helfer-Weg: hinter einer laufenden Abfrage wartete der
			# Wechsel sonst mit.
			_cmd(c, shorts)
			osd_meta()
		else:
			if _pid > 0 and OS.is_process_running(_pid):
				OS.kill(_pid)
			# Frisch gestartet: es gibt kein altes Video, dessen Stand mpv noch melden könnte.
			_t_laden = true
			_launch(start)
	if not direct:
		YouTube.record(v, start, duration)
	started.emit(v)
	changed.emit()
	if not direct:
		_load_segments(str(v.id))
	if shorts and not sim:
		# Erst wenn das gewählte Short läuft (sein eigenes yt-dlp ist dann durch): die Nachbarn holen.
		# Kam es schon aufgelöst, rechnet kein yt-dlp mehr – dann gleich.
		var at := index
		get_tree().create_timer(PRE_DELAY if _t_weg != "vorab aufgelöst" else 0.2).timeout.connect(func() -> void:
			if active and shorts and index == at:
				prefetch_shorts()
		)


## Video vorn (Standard): mpv liegt obenauf und zeichnet Uzais Leiste selbst (assets/mpv/uzai_osd.lua).
## Sonst liegt Uzai als durchsichtiges Fenster darüber – das bleibt auf manchen PCs schwarz.
func front_mode() -> bool:
	return str(Config.get_value("youtube.display", "mpv")) != "overlay"


## Nachricht an Uzais Leiste in mpv (nur wenn mpv vorn liegt).
func osd(cmd: String, args: Array = []) -> void:
	if sim or not active or not front_mode():
		return
	var c: Array = ["script-message-to", "uzai_osd", cmd]
	for a in args:
		c.append(str(a))
	_cmd([c])


## Was die Leiste in mpv nicht selbst weiß: Titel, Kanal, Als Nächstes, SponsorBlock, Tasten und
## ihre festen Texte – alles schon in der Sprache der Oberfläche (das Skript übersetzt nichts).
func osd_meta() -> void:
	if sim or not active or not front_mode():
		return
	_meta_sent = true
	osd("meta", [JSON.stringify(meta_for_osd())])


func meta_for_osd() -> Dictionary:
	var v := video
	var info := PackedStringArray()
	var vt := YouTube.views_text(int(v.get("views", 0)))
	if vt != "":
		info.append(TranslationServer.translate(vt))
	if int(v.get("published", 0)) > 0:
		info.append(TranslationServer.translate(preload("res://src/ui/u.gd").ago(int(v.published))))
	var segs: Array = []
	for sg in segments:
		segs.append([float((sg as Dictionary).get("start", 0)), float((sg as Dictionary).get("end", 0))])
	var ch := str(v.get("channel", ""))
	# Filme bringen ihre Zeile selbst mit (Staffel · Folge · Qualität) und die nächste Folge.
	if str(v.get("info", "")) != "":
		info = PackedStringArray([str(v.info)])
	return {
		"title": str(v.get("title", "")), "channel": ch, "info": "  ·  ".join(info),
		"hue": fposmod(float(ch.hash() % 1000) / 1000.0, 1.0),
		"next": str((queue[index + 1] as Dictionary).get("title", "")) if has_next() else str(v.get("next_title", "")),
		"segments": segs, "accent": UzTheme.col("accent").to_html(false).to_upper(),
		"clock24": bool(Config.get_value("theme.clock_24h", true)), "live": is_live(),
		"hints": osd_hints(shorts).map(func(h: Array) -> Array: return [h[0], TranslationServer.translate(str(h[1]))]), "pip": pip,
		"txt": osd_texts(),
	}


## Feste Texte der Leiste in mpv (assets/mpv/uzai_osd.lua), übersetzt. Fehlt einer, nimmt das
## Skript den deutschen. %s bzw. %d setzt das Skript ein (Uhrzeit, Sekunden).
static func osd_texts() -> Dictionary:
	var t := func(s: String) -> String: return TranslationServer.translate(s)
	return {
		"next": t.call("Als Nächstes").to_upper(), "ended": t.call("Video zu Ende").to_upper(), "paused": t.call("Pausiert"),
		"live": t.call("Live"), "ends": t.call("Endet um %s"), "volume": t.call("Lautstärke"),
		"countdown": t.call("Startet in %d s  ·  A jetzt  ·  B abbrechen"), "play": t.call("A abspielen  ·  B beenden"),
		"again": t.call("A nochmal  ·  B beenden"),
	}


## Tastenhinweise für die Leiste, mit den Zeichen des gewählten Controllers.
static func osd_hints(short := false) -> Array:
	var gset := Nav.glyph_set()
	var Glyph := preload("res://src/ui/components/glyph.gd")
	var names: Dictionary = Glyph.KEYS if gset == "keys" else (Glyph.PS if gset == "ps"
			else (Glyph.NINTENDO if gset == "nintendo" else (Glyph.DECK if gset == "deck" else Glyph.XBOX)))
	var face := { "a": "✕", "b": "○", "x": "□", "y": "△" } if gset == "ps" else {}
	var key := func(c: String) -> String: return str(face.get(c, names.get(c, c.to_upper())))
	# „ud“ zeichnet das Skript als Steuerkreuz hoch/runter (die Schrift hat keine Pfeile).
	# „mn“: Start-/Options-Taste als drei Striche (≡ fehlt in der Schrift); Tastatur: M.
	if short:
		return [[key.call("a"), "Pause"], ["ud", "Blättern"], [key.call("lt") + " " + key.call("rt"), "Lautstärke"], [key.call("y"), "Optionen"],
			[key.call("b"), "Beenden"]]
	return [[key.call("a"), "Pause"], ["ud", "Lautstärke"], [key.call("x"), "Untertitel"], [key.call("y"), "Optionen"],
		["M" if gset == "keys" else "mn", "Bild in Bild"], [key.call("b"), "Beenden"], [key.call("lb"), "Voriges"], [key.call("rb"), "Nächstes"]]


## Läuft ein Video groß (Player), nicht als Bild in Bild und nicht nur als Ton im Hintergrund?
func watching() -> bool:
	return active and not pip and not background


## Nur Ton im Hintergrund: Bild aus (falls noch an), der Player geht zu, der Ton läuft weiter.
## Filme bleiben im Player (dort gehört der Ton zum Bild).
func to_background() -> bool:
	if not active or pip or video.has("movies"):
		return false
	set_audio_only(true)
	background = true
	changed.emit()
	return true


## Prozess von mpv (0: läuft nicht) – „Übertragen“ drückt Discords Taste, während es vorn liegt.
func mpv_pid() -> int:
	return _pid if active and not sim else 0


## Bild in Bild an/aus: mpv verlässt das Vollbild (bzw. kehrt zurück), passt beim nächsten Video
## die Größe nicht mehr selbst an, die Leiste wird klein, die eigene Lautstärke gilt. Größe, Lage
## und Art des Fensters setzt der Helfer (src/core/pip.gd).
func set_pip(on: bool) -> void:
	if pip == on:
		return
	pip = on
	if active and not sim:
		await _cmd(pip_cmds(on))
		if on:
			# mpv braucht einen Augenblick, bis das Fenster aus dem Vollbild ist.
			await get_tree().create_timer(0.06).timeout
	osd_meta()
	if active:
		_push_volume()
	volume_changed.emit(volume_level())
	changed.emit()


## Befehle an mpv beim Wechsel. Eigenschaften, die ein älteres mpv nicht kennt
## (auto-window-resize), antworten nur mit einem Fehler – anders als Startoptionen.
static func pip_cmds(on: bool) -> Array:
	if on:
		return [["set_property", "fullscreen", false], ["set_property", "auto-window-resize", false],
			["set_property", "cursor-autohide", "1000"], ["set_property", "ontop", true]]
	return [["set_property", "cursor-autohide", "always"], ["set_property", "fullscreen", true], ["set_property", "ontop", true]]


## mpv obenauf oder hinter Uzai (für Menüs über dem Video: Optionen, Guide).
func set_ontop(on: bool) -> void:
	if sim or not active:
		return
	_cmd([["set_property", "ontop", on]])


## Ein anderes Programm liegt vorn (Alt+Tab aus dem Vollbild-Video): mpv tritt zurück – minimiert
## und nicht mehr „immer oben“, der Ton läuft weiter – bzw. kommt wieder (obenauf: wie vorher).
## Nicht bei Bild in Bild (eigene Regeln, src/core/pip.gd) und „Nur Ton“ (mpv ist schon klein).
func zuruecktreten(weg: bool, obenauf := true) -> void:
	if sim or not active or pip or audio_only:
		return
	_cmd([["set_property", "window-minimized", weg], ["set_property", "ontop", not weg and obenauf]])


## Skript und Schrift der Leiste in den Datenordner legen (mpv liest sie als Dateien).
## Gibt den mpv-Ordner zurück (--config-dir; Schriften in fonts/).
static func prepare_osd() -> String:
	var dir := Config.path("mpv")
	if _osd_ready:
		return dir
	DirAccess.make_dir_recursive_absolute(dir.path_join("fonts"))
	var files := {
		"res://assets/mpv/uzai_osd.lua": dir.path_join("uzai_osd.lua"),
		"res://assets/mpv/fonts/UzaiSans-Regular.ttf": dir.path_join("fonts/UzaiSans-Regular.ttf"),
		"res://assets/mpv/fonts/UzaiSans-Medium.ttf": dir.path_join("fonts/UzaiSans-Medium.ttf"),
		"res://assets/mpv/fonts/UzaiSans-Bold.ttf": dir.path_join("fonts/UzaiSans-Bold.ttf"),
		"res://assets/mpv/fonts/UzaiSans-Black.ttf": dir.path_join("fonts/UzaiSans-Black.ttf"),
		"res://assets/mpv/fonts/OFL.txt": dir.path_join("fonts/OFL.txt"),
	}
	for src in files.keys():
		var data := FileAccess.get_file_as_bytes(str(src))
		if data.is_empty():
			continue
		var dest := str(files[src])
		if FileAccess.file_exists(dest) and FileAccess.get_file_as_bytes(dest) == data:
			continue
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
	_osd_ready = true
	return dir


## RUHIG_CONF in Uzais mpv-Ordner schreiben (einmal je Sitzung); Pfad oder "" wenn es nicht ging.
static func ruhig_conf() -> String:
	var p := Config.path("mpv").path_join("uzai_ruhig.conf")
	if _ruhig_ready:
		return p
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	if not (FileAccess.file_exists(p) and FileAccess.get_file_as_string(p) == RUHIG_CONF):
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return ""
		f.store_string(RUHIG_CONF)
		f.close()
	_ruhig_ready = true
	return p


## Direkte Adresse statt YouTube (Trailer aus dem Steam-Shop): mpv spielt sie selbst, und sie
## gehört nicht in Verlauf, Merkliste oder SponsorBlock.
static func is_direct(v: Dictionary) -> bool:
	return str(v.get("url", "")) != ""


static func url(v: Dictionary) -> String:
	if is_direct(v):
		# Eigene Aufnahmen (Galerie) sind Dateien auf diesem PC; alles andere kommt von außen.
		if str(v.get("id", "")).begins_with("cap:") and FileAccess.file_exists(str(v.url).replace("\\", "/")):
			return str(v.url)
		return safe_url(str(v.url))
	var id := str(v.get("id", ""))
	return "https://www.youtube.com/watch?v=" + id if YT_ID.search(id) != null else ""


## YouTube-Kennung: nur Buchstaben, Ziffern, - und _.
static var YT_ID := RegEx.create_from_string("^[A-Za-z0-9_-]{6,32}$")


## Adresse aus fremder Quelle (Addon, Shop, Twitch) für mpv: nur http(s), ohne Steuerzeichen,
## Anführungszeichen, Leer- und Rückstriche als %-Code. Godot setzt Argumente unter Windows nur in
## Anführungszeichen und maskiert darin keine – ein „"“ hätte sonst eigene mpv-Optionen (bis hin
## zu einem fremden Skript) einschleusen können. "" = nicht erlaubt.
static func safe_url(u: String) -> String:
	var s := u.strip_edges()
	var low := s.to_lower()
	if not (low.begins_with("https://") or low.begins_with("http://")) or s.length() > 8192:
		return ""
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 0x20 or c == 0x7F:
			continue
		match ch:
			"\"": out += "%22"
			" ": out += "%20"
			"\\": out += "%5C"
			_: out += ch
	return out


## Text aus fremder Quelle als Teil eines mpv-Arguments (Titel, Kopfzeilen): ohne Steuerzeichen,
## ohne „"“ und ohne Rückstrich am Ende (aus demselben Grund wie bei safe_url).
static func arg_text(t: String, max_len := 512) -> String:
	var out := ""
	for ch in t:
		var c := ch.unicode_at(0)
		if c < 0x20 or c == 0x7F:
			continue
		out += "'" if ch == "\"" else ch
	out = out.strip_edges()
	while out.ends_with("\\"):
		out = out.left(-1)
	return out.left(max_len)


## Format für yt-dlp. Twitch liefert Bild und Ton zusammen (HLS): die beste Stufe bis zur
## gewählten Höhe, „Nur Ton“ heißt dort audio_only.
static func ytdl_format(v: Dictionary, q: String, audio: bool) -> String:
	if v.has("twitch"):
		if audio:
			return "audio_only/ba/b"
		return ("b[height<=%s]/b" % q) if q.is_valid_int() else "b"
	var f := str(QUALITY.get("ton" if audio else q, QUALITY["1080"]))
	# Shorts stehen hochkant: „1080p“ meint dort die Breite (sonst käme nur 608×1080).
	return f.replace("height", "width") if bool(v.get("short", false)) else f


## Läuft gerade ein Live-Stream (Twitch)? Dann gibt es kein Spulen und kein Ende-Datum.
func is_live() -> bool:
	return active and live_item(video)


static func live_item(v: Dictionary) -> bool:
	var tw: Variant = v.get("twitch")
	return tw is Dictionary and str((tw as Dictionary).get("kind", "")) == "live"


func _launch(start: float) -> void:
	var small := pip and not audio_only
	_mpv_audio = audio_only
	_pipe = PIPE_VORSILBE + Crypto.new().generate_random_bytes(12).hex_encode()
	var a := PackedStringArray([
		"--force-window=" + ("no" if audio_only else "immediate"), "--keep-open=yes", "--idle=no",
		"--osc=no", "--no-input-default-bindings", "--input-vo-keyboard=no",
		"--cursor-autohide=always", "--title=Uzai Video", "--hwdec=auto-safe",
		"--input-ipc-server=\\\\.\\pipe\\" + _pipe,
		"--script-opts=ytdl_hook-ytdl_path=" + YouTube.ytdlp_path().replace("/", "\\"),
		"--ytdl-format=" + ytdl_format(video, quality, audio_only),
		"--slang=" + str(Config.get_value("youtube.sub_langs", "de,en")),
		"--sid=" + ("auto" if subs else "no"),
		"--alang=" + audio_langs(str(Config.get_value("video.audio_lang", ""))),
		# Obergrenze ausdrücklich: Eine eigene mpv.conf mit kleinerer volume-max ließ sonst jedes
		# „lauter“ über dieser Grenze mit einem Fehler abprallen.
		"--volume=" + str(volume_level()), "--volume-max=" + str(VOLUME_MAX),
		"--start=" + str(int(start)),
	])
	if not small:
		a.insert(0, "--fullscreen")
	var scr := DisplayServer.window_get_current_screen()
	if front_mode():
		# mpv obenauf, Uzais Leiste zeichnet ein eigenes Skript; mpvs eigene Anzeige bleibt stumm.
		# Bei „Nur Ton“ liegt Uzai vorn (mpv hat dann kein Bild zu zeigen).
		var dir := prepare_osd()
		if not audio_only:
			a.append_array(window_args(small, scr, _pip_geom))
		a.append_array(PackedStringArray(["--osd-level=1", "--osd-on-seek=no", "--no-osd-bar",
			"--osd-playing-msg=", "--config-dir=" + dir.replace("/", "\\"),
			"--script=" + dir.path_join("uzai_osd.lua").replace("/", "\\")]))
	else:
		a.append_array(PackedStringArray(["--osd-level=0", "--no-osd-bar"]))
		if small:
			a.append_array(window_args(true, scr, _pip_geom))
	if audio_only:
		a.append("--vid=no")
	var ruhig := ruhig_conf()
	if ruhig != "":
		a.append("--include=" + ruhig.replace("/", "\\"))
	var langs := str(Config.get_value("youtube.sub_langs", "de,en")).replace(" ", "").split(",")
	var sl := PackedStringArray()
	for l in langs:
		if l != "":
			sl.append(l + ".*")
	a.append("--ytdl-raw-options-append=sub-langs=" + ",".join(sl))
	a.append("--ytdl-raw-options-append=write-subs=")
	a.append("--ytdl-raw-options-append=write-auto-subs=")
	if YouTube.has_deno():
		a.append("--ytdl-raw-options-append=js-runtimes=deno:" + YouTube.deno_path().replace("/", "\\"))
	a.append_array(stream_args(video))
	# Schon aufgelöst (vorab()): mpv bekommt gleich Bild und Ton, sein yt-dlp (Python und die
	# JS-Prüfung über Deno, gut 2–5 s) fällt beim Start weg.
	var pre := _pre_take(video) if pre_ok(video, subs, audio_only) else {}
	a.append_array(pre_args(pre, url(video)))
	_t_weg = "vorab aufgelöst" if not pre.is_empty() else ("über yt-dlp" if not is_direct(video) and not video.has("movies") else "direkt")
	_pre_ms = int(pre.get("ms", 0))
	# mpvs eigenes Protokoll (mpv legt es bei jedem Start neu an): daraus kommt der Grund, wenn es gleich endet.
	var mlog := mpv_log_path()
	DirAccess.make_dir_recursive_absolute(mlog.get_base_dir())
	if FileAccess.file_exists(mlog):
		DirAccess.remove_absolute(mlog)
	a.append("--log-file=" + mlog.replace("/", "\\"))
	_ipc_ok = false
	_ipc_warned = false
	_t_launch = Time.get_ticks_msec()
	_pid = OS.create_process(YouTube.mpv_path(), Helper.win_args(a))
	PlayerLog.zeile("Start %s (%s): mpv %s, yt-dlp %s, Deno %s, %s%s → %s" % [_art(video), _t_weg, _da(YouTube.has_mpv()), _da(YouTube.has_ytdlp()),
		_da(YouTube.has_deno()), "vorn" if front_mode() else "Overlay", ", Bild in Bild" if small else "", ("Prozess %d" % _pid) if _pid > 0 else "startet nicht"])
	if _pid <= 0:
		_fail_start("mpv startet nicht. Virenschutz prüfen oder mpv unter Einstellungen → Videos neu laden.", "create_process %d" % _pid)


## Fenster von mpv: im Vollbild ohne Rahmen und gleich so groß wie der Bildschirm, auf dem Uzai
## liegt (sonst blitzt kurz ein normales Windows-Fenster auf, bevor mpv auf Vollbild schaltet).
## Bild in Bild: klein, ohne Rahmen, obenauf, der Mauszeiger bleibt zum Ziehen sichtbar; Art und
## genaue Lage gibt danach der Helfer (src/core/pip.gd). Nur Optionen, die jedes mpv kennt –
## eine unbekannte ließe mpv gar nicht erst starten.
static func window_args(in_pip: bool, scr: int, geom := "") -> PackedStringArray:
	if in_pip:
		var a := PackedStringArray(["--ontop", "--border=no", "--cursor-autohide=1000"])
		if geom != "":
			a.append("--geometry=" + geom)
		return a
	return PackedStringArray(["--ontop", "--border=no", "--geometry=100%x100%+0+0", "--screen=%d" % scr, "--fs-screen=%d" % scr])


## Zusätzliche mpv-Argumente für fremde Stream-Adressen (Filme): Kopfzeilen der Addons
## (behaviorHints.proxyHeaders), Titel fürs Fenster, kein yt-dlp für direkte Dateien.
static var HEADER_NAME := RegEx.create_from_string("^[A-Za-z0-9-]{1,64}$")


static func stream_args(v: Dictionary) -> PackedStringArray:
	var a := PackedStringArray()
	var hdr: Variant = v.get("headers", {})
	if hdr is Dictionary:
		for k in (hdr as Dictionary).keys():
			var key := str(k).strip_edges()
			var val := arg_text(str(hdr[k]), 2048)
			# Kopfzeilen-Namen nur aus Buchstaben, Ziffern und „-“ (wie im HTTP-Standard üblich).
			if key == "" or val == "" or HEADER_NAME.search(key) == null:
				continue
			match key.to_lower():
				"user-agent":
					a.append("--user-agent=" + val)
				"referer", "referrer":
					a.append("--referrer=" + val)
				_:
					a.append("--http-header-fields-append=%s: %s" % [key, val])
	if arg_text(str(v.get("media_title", ""))) != "":
		a.append("--force-media-title=" + arg_text(str(v.media_title)))
	if v.has("movies"):
		a.append("--ytdl=no")
	return a


## Untertitel als Spuren nachreichen (Addon-Untertitel). Bevorzugte Sprache zuerst; ist
## „Untertitel“ an, wird die erste passende gleich gewählt.
func add_subtitles(list: Array) -> void:
	if not active or list.is_empty():
		return
	var have := sichere_untertitel(video.get("subtitles"))
	var urls := {}
	for s in have:
		urls[str(s.url)] = true
	for s in sichere_untertitel(list):
		if not urls.has(str(s.url)):
			urls[str(s.url)] = true
			have.append(s)
	video["subtitles"] = sort_subtitles(have, str(Config.get_value("youtube.sub_langs", "de,en")))
	if _meta_sent:
		_send_subs()
	changed.emit()


## Untertitel aus fremder Quelle (Addon, Plugin, Medienserver): nur Einträge mit einer Adresse über http(s), die
## Adresse bereinigt (safe_url). Alles andere ließe mpv auf dem PC öffnen – eine Datei, oder eine Netzwerkfreigabe,
## bei der Windows die Anmeldung des Nutzers an den fremden Rechner schickt. Gilt für jede Liste, die an mpv geht:
## die mit dem Stream gelieferte genauso wie später nachgereichte.
static func sichere_untertitel(list: Variant) -> Array:
	var out: Array = []
	for s in Fremd.zeilen(list):
		var su := safe_url(str(s.get("url", "")))
		if su == "":
			continue
		var sd: Dictionary = (s as Dictionary).duplicate()
		sd["url"] = su
		out.append(sd)
	return out


## Bevorzugte Sprachen nach vorn, höchstens 16 Spuren (Untertitel-Addons liefern oft Dutzende).
static func sort_subtitles(list: Array, langs: String) -> Array:
	var want: Array = []
	for l in langs.replace(" ", "").split(","):
		if l != "":
			want.append(l.to_lower())
	var rank := func(s: Dictionary) -> int:
		var lang := str(s.get("lang", "")).to_lower()
		for i in want.size():
			var aliases: Array = Movies.LANG_ALIASES.get(want[i], [want[i]])
			if lang in aliases or lang.begins_with(str(want[i]) + "-"):
				return i
		return 99
	var out := list.duplicate()
	var keyed: Array = []
	for i in out.size():
		keyed.append([rank.call(out[i]), i, out[i]])
	keyed.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var res: Array = []
	for k in keyed.slice(0, 16):
		res.append(k[2])
	return res


func _send_subs() -> void:
	# Auch die mit dem Stream gelieferte Liste prüfen (früher nur die nachgereichte, siehe sichere_untertitel).
	var list := sichere_untertitel(video.get("subtitles"))
	if _subs_sent == 0:
		list = sort_subtitles(list, str(Config.get_value("youtube.sub_langs", "de,en")))
	video["subtitles"] = list
	if sim or _subs_sent >= list.size():
		return
	var want := str(Config.get_value("youtube.sub_langs", "de,en")).replace(" ", "").split(",")[0].to_lower()
	var cmds: Array = []
	for i in range(_subs_sent, list.size()):
		var s: Dictionary = list[i]
		var lang := str(s.get("lang", ""))
		var aliases: Array = Movies.LANG_ALIASES.get(want, [want])
		var pick := subs and _subs_sent == 0 and i == 0 and lang.to_lower() in aliases
		cmds.append(["sub-add", str(s.url), "select" if pick else "auto", str(s.get("label", lang)), lang])
	_subs_sent = list.size()
	_cmd(cmds)


func _load_segments(vid: String) -> void:
	var segs := await YouTube.segments(vid)
	if str(video.get("id", "")) == vid:
		segments = segs
		changed.emit()
		if _meta_sent:
			osd_meta()


# --- Steuern ------------------------------------------------------------------------------

func toggle_pause() -> void:
	set_pause(not paused)


func set_pause(on: bool) -> void:
	if not active:
		return
	paused = on
	if not sim:
		_cmd([["set_property", "pause", on]])
	changed.emit()


func seek(delta: float) -> void:
	if not active:
		return
	seek_to(pos + delta)


func seek_to(t: float) -> void:
	if not active or is_live():
		return
	var top := duration - 1.0 if duration > 0 else t
	pos = clampf(t, 0.0, maxf(0.0, top))
	at_end = false
	if not sim:
		_cmd([["seek", pos, "absolute"]])
	changed.emit()


func has_next() -> bool:
	return index < queue.size() - 1


func has_prev() -> bool:
	return index > 0


func next() -> void:
	if has_next():
		_save()
		index += 1
		var v: Dictionary = queue[index]
		_swipe = 1 if shorts else 0
		# Shorts immer von vorn (sie sind kurz, man blättert durch).
		_open(v, 0.0 if shorts else YouTube.resume_pos(str(v.id)))


func prev() -> void:
	# Wie bei Playern üblich: erst an den Anfang, dann zum vorigen Video (live und Shorts: gleich
	# zum vorigen – bei Shorts heißt hoch „das davor“).
	if (pos > 8.0 and not is_live() and not shorts) or not has_prev():
		seek_to(0.0)
		return
	_save()
	index -= 1
	var v: Dictionary = queue[index]
	_swipe = -1 if shorts else 0
	_open(v, 0.0)


# --- Shorts: das nächste und das vorige vorab auflösen ------------------------------------------
# Beim Blättern bekam mpv „loadfile https://www.youtube.com/watch?v=…“, und sein ytdl_hook startete
# für jedes Short yt-dlp (Python, dazu die JS-Prüfung über Deno): gut 1,5 bis 4 s schwarzes Bild je
# Schritt, egal wie flüssig Uzai selbst lief (dort kostet ein Schritt gemessen um 2 ms). Jetzt fragt
# Uzai yt-dlp für die Nachbarn schon vorher (eigener Faden, YouTube.exec) und gibt mpv beim
# Blättern gleich die Adressen von Bild und Ton.

const PRE_KEEP := 8                       ## so viele aufgelöste Shorts merken
const PRE_AGE_MS := 20 * 60 * 1000        ## Adressen von YouTube gelten Stunden; 20 Minuten reichen
const PRE_MAX_BYTES := 4_000_000          ## Antwort von yt-dlp höchstens so groß
const PRE_DELAY := 1.2                    ## Sekunden nach dem Start, bevor die Nachbarn kommen
var _pre := {}                            ## Kennung|Format -> { v, a, ua, at }
var _pre_busy := {}
var _pre_ms := 0                          ## wie lange das Auflösen des laufenden Videos dauerte (Protokoll)


static func pre_key(v: Dictionary, fmt: String) -> String:
	var id := str(v.get("id", ""))
	return "%s|%s" % [id, fmt] if YT_ID.search(id) != null else ""


## Antwort von `yt-dlp -J -f …` für ein Video: Adresse des Bildes, des Tons (leer, wenn ein Format
## beides hat) und der User-Agent, mit dem yt-dlp sie holte. Nur https; {} wenn unbrauchbar.
static func parse_resolved(text: String) -> Dictionary:
	if text.length() > PRE_MAX_BYTES:
		return {}
	var d := Fremd.verz(Fremd.json(text))
	if d.is_empty():
		return {}
	var vu := ""
	var au := ""
	var rf: Variant = d.get("requested_formats")
	if rf is Array and not (rf as Array).is_empty():
		for f in rf:
			if not (f is Dictionary):
				return {}
			var u := safe_url(str((f as Dictionary).get("url", "")))
			if not u.to_lower().begins_with("https://"):
				return {}
			if str((f as Dictionary).get("vcodec", "none")) != "none":
				vu = u if vu == "" else vu
			elif au == "":
				au = u
	else:
		vu = safe_url(str(d.get("url", "")))
	if not vu.to_lower().begins_with("https://"):
		return {}
	var hh: Variant = d.get("http_headers")
	var ua := arg_text(str((hh as Dictionary).get("User-Agent", "")), 512) if hh is Dictionary else ""
	return { "v": vu, "a": au, "ua": ua }


## mpv-Befehle, um ein Video zu laden: mit aufgelösten Adressen (pre) direkt, sonst über yt-dlp.
## Die Tonspur eines vorigen Shorts fliegt immer raus.
static func load_cmds(pre: Dictionary, fallback: String) -> Array:
	var c: Array = [["change-list", "audio-files", "clr", ""]]
	if pre.is_empty():
		c.append(["loadfile", fallback])
		return c
	if str(pre.get("a", "")) != "":
		c.append(["change-list", "audio-files", "append", str(pre.a)])
	if str(pre.get("ua", "")) != "":
		c.append(["set_property", "user-agent", str(pre.ua)])
	c.append(["loadfile", str(pre.v)])
	return c


## mpv-Argumente fürs Starten: mit aufgelösten Adressen (pre) Bild, Ton und User-Agent direkt,
## sonst die Adresse für yt-dlp.
static func pre_args(pre: Dictionary, fallback: String) -> PackedStringArray:
	if pre.is_empty():
		return PackedStringArray([fallback])
	var a := PackedStringArray()
	if str(pre.get("a", "")) != "":
		# „-append“ nimmt genau eine Adresse (ohne Trennzeichen-Auslegung der Pfadliste).
		a.append("--audio-files-append=" + str(pre.a))
	if str(pre.get("ua", "")) != "":
		a.append("--user-agent=" + str(pre.ua))
	a.append(str(pre.v))
	return a


## Dürfen für v vorab aufgelöste Adressen gelten? Nur YouTube-Videos (keine Filme, kein Twitch,
## keine direkten Adressen, nichts Live), ohne Untertitel (die holt sonst yt-dlp in mpv) und mit Bild.
static func pre_ok(v: Dictionary, with_subs: bool, audio: bool) -> bool:
	return not with_subs and not audio and not is_direct(v) and not v.has("movies") and not v.has("twitch") \
		and not bool(v.get("live", false)) and YT_ID.search(str(v.get("id", ""))) != null


## Aufgelöste Adressen für v (noch frisch), sonst {}.
func _pre_take(v: Dictionary) -> Dictionary:
	var key := pre_key(v, ytdl_format(v, quality, false))
	var got: Dictionary = _pre.get(key, {})
	if got.is_empty() or Time.get_ticks_msec() - int(got.get("at", 0)) > PRE_AGE_MS:
		_pre.erase(key)
		return {}
	return got


## Die nächsten beiden und das vorige Short vorab auflösen (nacheinander, damit yt-dlp nicht
## doppelt rechnet). Früher nur eins voraus: wer schnell blätterte, war vor yt-dlp beim nächsten.
func prefetch_shorts() -> void:
	if sim or not shorts or subs or audio_only or not YouTube.tools_ready():
		return
	var at := index
	for i in shorts_order(index, queue.size()):
		# Weitergeblättert: das neue Short holt seine eigenen Nachbarn.
		if not active or not shorts or index != at:
			return
		if queue[i] is Dictionary:
			await _prefetch(queue[i])


## Reihenfolge fürs Vorab-Auflösen der Shorts: zwei voraus, dann eins zurück.
static func shorts_order(at: int, n: int) -> Array:
	var out: Array = []
	for i in [at + 1, at + 2, at - 1]:
		if i >= 0 and i < n:
			out.append(i)
	return out


## Ein Video vorab auflösen, während die Auswahl darauf ruht (Karte in Videos, Short im Raster):
## Startet man es, spielt mpv sofort. Immer nur eins zur Zeit; kommt währenddessen ein anderes,
## wird nur das zuletzt gewählte noch geholt. Nicht im leichten Modus und nicht, wenn es ohnehin
## über yt-dlp in mpv liefe (Untertitel an).
var _vorab_next: Dictionary = {}
var _vorab_busy := false


## Läufe von vorab, die gerade unterwegs sind (siehe dort).
var _vorab_offen := 0


func vorab(v: Dictionary) -> void:
	_vorab_offen += 1
	await _vorab_lauf(v)
	_vorab_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und vorab täte bis zum Neustart nichts mehr.
	if _vorab_offen == 0 and _vorab_busy:
		_vorab_busy = false


func _vorab_lauf(v: Dictionary) -> void:
	if not Config.is_windows() or YouTube.demo or Leicht.active or not YouTube.tools_ready():
		return
	if not pre_ok(v, bool(Config.get_value("youtube.subtitles", false)), false):
		return
	_vorab_next = v
	if _vorab_busy:
		return
	_vorab_busy = true
	while not _vorab_next.is_empty():
		var it := _vorab_next
		_vorab_next = {}
		await _prefetch(it, str(Config.get_value("youtube.quality", "1080")))
	_vorab_busy = false


func _prefetch(v: Dictionary, q := "") -> void:
	var fmt := ytdl_format(v, q if q != "" else quality, false)
	var key := pre_key(v, fmt)
	if key == "" or _pre_busy.has(key) or not _pre_take(v).is_empty():
		return
	_pre_busy[key] = true
	var a := PackedStringArray(["--encoding", "utf-8", "--no-warnings", "--ignore-config", "--no-playlist", "-J", "-f", fmt])
	if YouTube.has_deno():
		a.append_array(PackedStringArray(["--js-runtimes", "deno:" + YouTube.deno_path().replace("/", "\\")]))
	a.append(url(v))
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await YouTube.exec(YouTube.ytdlp_path(), a, 30.0)
	_pre_busy.erase(key)
	var got := parse_resolved(str(r.get("text", ""))) if bool(r.get("ok", false)) else {}
	if got.is_empty():
		return
	got["at"] = Time.get_ticks_msec()
	got["ms"] = Time.get_ticks_msec() - t0
	_pre[key] = got
	while _pre.size() > PRE_KEEP:
		_pre.erase(_pre.keys()[0])


func set_speed(s: float) -> void:
	speed = s
	if not sim:
		_cmd([["set_property", "speed", s]])
	changed.emit()


func set_subs(on: bool) -> void:
	subs = on
	if not sim:
		_cmd([["set_property", "sid", "auto" if on else "no"]])
	changed.emit()


## Spuren aus mpv holen: [{ id, type ("audio"/"sub"), lang, title, selected, channels, external }].
func load_tracks() -> Array:
	if sim:
		var demo: Array = sim_tracks if not sim_tracks.is_empty() else (DEMO_TRACKS if video.has("movies") else [])
		tracks = parse_tracks(demo.duplicate(true))
		return tracks
	var res := await _cmd([["get_property", "track-list"]])
	var r: Variant = res[0] if not res.is_empty() else null
	tracks = parse_tracks(r.get("data") if r is Dictionary and str(r.get("error", "")) == "success" else null)
	return tracks


## Nur Ton- und Untertitelspuren, Werte geprüft (mpv-Antwort ist fremd).
static func parse_tracks(d: Variant) -> Array:
	var out: Array = []
	if not (d is Array):
		return out
	for t in d:
		if not (t is Dictionary):
			continue
		var kind := str(t.get("type", ""))
		var id: Variant = t.get("id")
		if not (kind in ["audio", "sub"]) or not (id is int or id is float):
			continue
		var ch: Variant = t.get("demux-channel-count", t.get("audio-channels", 0))
		out.append({ "id": int(id), "type": kind, "lang": str(t.get("lang", "")).left(16), "title": str(t.get("title", "")).left(80),
			"selected": bool(t.get("selected", false)), "channels": int(ch) if ch is int or ch is float else 0,
			"external": bool(t.get("external", false)) })
	return out


## Name einer Spur: Sprache, dann Titel (wenn er mehr sagt) und bei Ton die Kanäle.
static func track_label(t: Dictionary) -> String:
	var parts := PackedStringArray()
	var lang := str(t.get("lang", ""))
	parts.append(Movies.lang_label(lang) if lang != "" and lang.to_lower() != "und" else "Spur %d" % int(t.get("id", 0)))
	var title := str(t.get("title", "")).strip_edges()
	# Titel weglassen, wenn er nur die Sprache nennt („English“, „Deutsch“).
	var tl := title.to_lower()
	if title != "" and not parts[0].to_lower().contains(tl) and str(Movies.LANG_NAMES.get(tl, "")) != parts[0]:
		parts.append(title)
	if str(t.get("type", "")) == "audio":
		var ch := int(t.get("channels", 0))
		if ch >= 8:
			parts.append("7.1")
		elif ch >= 6:
			parts.append("5.1")
		elif ch == 2:
			parts.append("Stereo")
	return "  ·  ".join(parts)


## Auswahl für den Player: [[id, Name]]; bei Untertiteln vorn „Aus“. Gleiche Namen bekommen eine Nummer.
static func track_options(list: Array, kind: String) -> Array:
	var out: Array = [["no", "Aus"]] if kind == "sub" else []
	var seen := {}
	for t in list:
		if str(t.get("type", "")) != kind:
			continue
		var label := track_label(t)
		seen[label] = int(seen.get(label, 0)) + 1
		if int(seen[label]) > 1:
			label += " (%d)" % int(seen[label])
		out.append([int(t.id), label])
	return out


## Gerade gewählte Spur (bei Untertiteln „no“, wenn keine läuft; bei Ton -1, wenn unbekannt).
static func selected_track(list: Array, kind: String) -> Variant:
	for t in list:
		if str(t.get("type", "")) == kind and bool(t.get("selected", false)):
			return int(t.id)
	return "no" if kind == "sub" else -1


## Spur wählen. Ton: die Sprache gilt ab jetzt als bevorzugt (video.audio_lang).
func set_track(kind: String, id: Variant) -> void:
	if kind == "sub":
		subs = str(id) != "no"
	for t in tracks:
		if str(t.type) == kind:
			t.selected = str(id) != "no" and int(t.id) == int(id)
			if kind == "audio" and bool(t.selected) and str(t.lang) != "":
				Config.set_value("video.audio_lang", str(t.lang).to_lower())
	if not sim:
		_cmd([["set_property", "aid" if kind == "audio" else "sid", id if str(id) == "no" else int(id)]])
	changed.emit()


## --alang für mpv: die gemerkte Sprache mit ihren Schreibweisen (ger, deu, de …).
static func audio_langs(lang: String) -> String:
	var l := lang.to_lower().strip_edges()
	if l == "":
		return ""
	for k in Movies.LANG_ALIASES.keys():
		if l == str(k) or l in (Movies.LANG_ALIASES[k] as Array):
			return ",".join(PackedStringArray(Movies.LANG_ALIASES[k]))
	return l.replace(",", "")


func set_quality(q: String) -> void:
	if q == quality and not audio_only:
		return
	quality = q
	audio_only = false
	_reload()


func set_audio_only(on: bool) -> void:
	if on == audio_only:
		return
	audio_only = on
	_reload()


func _reload() -> void:
	if sim or not active:
		changed.emit()
		return
	var keep := pos
	loading = true
	_mpv_audio = audio_only
	_cmd([
		["set_property", "ytdl-format", ytdl_format(video, quality, audio_only)],
		["set_property", "vid", "no" if audio_only else "auto"],
		["set_property", "start", str(int(keep))],
		["loadfile", url(video)],
	])
	# Video vorn: bei „Nur Ton“ tritt mpv zurück (Uzai zeigt Bild und Pegel), sonst wieder obenauf.
	if front_mode():
		_cmd([["set_property", "window-minimized", audio_only], ["set_property", "ontop", not audio_only]])
	changed.emit()


## Stored volume (0…130). Picture-in-picture is as loud as the video in fullscreen – shrinking the video
## must not make it quieter. To hear it at a different level next to the game, turn on the separate level
## under Settings › Videos › More (pip.own_volume, off by default); it is stored in pip.volume and starts
## at the fullscreen level.
func volume_level() -> int:
	var key := volume_key()
	var fallback: Variant = Config.get_value("youtube.volume", 100) if key != "youtube.volume" else 100
	return volume_clamp(Config.get_value(key, fallback))


func volume_key() -> String:
	return "pip.volume" if pip and own_pip_volume() else "youtube.volume"


## Eigene Lautstärke für Bild in Bild (Einstellung, Standard aus: gleich laut wie im Vollbild).
static func own_pip_volume() -> bool:
	return Config.get_value("pip.own_volume", false) == true


static func volume_clamp(v: Variant) -> int:
	var n := 100
	if v is int or v is float:
		n = int(v)
	elif v is String and (v as String).is_valid_float():
		n = int(float(v))
	return clampi(n, 0, VOLUME_MAX)


## Lauter/leiser um delta Prozentpunkte. Gibt die neue Stufe zurück.
func volume(delta: int) -> int:
	return set_volume(volume_level() + delta)


## Stufe setzen, merken und an mpv schicken (samt Anzeige in Uzais Leiste in mpv).
func set_volume(level: int) -> int:
	var v := volume_clamp(level)
	if v != volume_level():
		Config.set_value(volume_key(), v)
	volume_changed.emit(v)
	_push_volume()
	return v


## Befehle für mpv: Lautstärke setzen und (Video vorn) kurz anzeigen.
static func volume_cmds(level: int, front: bool) -> Array:
	var c: Array = [["set_property", "volume", level]]
	if front:
		c.append(["script-message-to", "uzai_osd", "volume", str(level)])
	return c


## Höchstens ein Lautstärke-Befehl auf einmal; was währenddessen dazukam, folgt als ein Befehl
## mit dem neuesten Stand. Früher ging jeder Druck einzeln (zweimal: Wert und Anzeige) hinter die
## Abfrage alle 0,25 s in denselben Helfer-Weg; hing der an etwas anderem, kam lange nichts an.
func _push_volume() -> void:
	if sim or not active:
		return
	if _vol_busy:
		_vol_dirty = true
		return
	_vol_busy = true
	while true:
		_vol_dirty = false
		await _cmd(volume_cmds(volume_level(), front_mode()), true)
		if not _vol_dirty or not active:
			break
	_vol_busy = false


## Beenden. Kommt in der Wartezeit ein neues Video (Bild in Bild läuft, ein anderer Stream wird
## gewählt), startet das in einem eigenen mpv und läuft weiter: Das Beenden nimmt nur sein altes
## mpv mit. Vorher lud das neue Video ins gerade endende mpv, und das Ende schloss danach beide.
func stop() -> void:
	if not active:
		return
	_save()
	var gen := _gen
	var pid := _pid
	if not sim and pid > 0:
		_pid = 0
		_pid_endet = pid
		await _cmd([["quit"]])
		await get_tree().create_timer(0.3).timeout
		if OS.is_process_running(pid):
			OS.kill(pid)
		if _pid_endet == pid:
			_pid_endet = 0
	if gen == _gen and active:
		_finish()


## Uzai schließt (Alt+F4, Ausschalten, Neustart, Profilwechsel): Keiner dieser Wege rief stop(), und dessen höfliches
## „quit“ wartet bis 3 s auf die Leitung – länger, als Uzai beim Beenden noch lebt. mpv lief dann ohne Uzai weiter (Ton
## oder Bild), mit dem Controller nicht zu stoppen, und ein neues Uzai kannte es nicht. Darum hier synchron beenden.
func _exit_tree() -> void:
	if active and is_instance_valid(YouTube):
		_save()
	if sim:
		return
	for p in [_pid, _pid_endet]:
		if int(p) > 0 and OS.is_process_running(int(p)):
			OS.kill(int(p))


func _finish() -> void:
	active = false
	pip = false
	background = false
	_pid = 0
	# mpvs Protokoll nennt in der Befehlszeile Kopfzeilen und Stream-Adressen (X-Plex-Token, Addon-Schlüssel): nach
	# dem Ende weg. Hält mpv es noch offen, entfernt es der nächste Start.
	if FileAccess.file_exists(mpv_log_path()):
		DirAccess.remove_absolute(mpv_log_path())
	stopped.emit()
	changed.emit()


func _save(periodic := false) -> void:
	if active and not video.is_empty() and not is_direct(video):
		YouTube.record(video, pos, duration, periodic)


# --- Zustand abfragen ------------------------------------------------------------------------

func _process(dt: float) -> void:
	if not active:
		return
	if sim:
		_sim_step(dt)
	else:
		_poll_t += dt
		if _poll_t >= 0.25 and not _polling:
			_poll_t = 0.0
			_poll()
	_save_t += dt
	if _save_t >= 5.0:
		_save_t = 0.0
		_save(true)


func _sim_step(dt: float) -> void:
	if loading:
		_sim_load += dt
		if _sim_load > 0.6:
			loading = false
			if duration <= 0:
				duration = 600.0
	elif not paused and not at_end:
		pos += dt * speed
		if pos >= duration:
			pos = duration
			at_end = true
			_save()
			reached_end.emit()
			_end_in_background()
	_check_segments()
	changed.emit()


func _poll() -> void:
	_polling = true
	var props := ["time-pos", "duration", "pause", "eof-reached", "paused-for-cache", "seeking"]
	var cmds: Array = []
	for p in props:
		cmds.append(["get_property", p])
	var res := await _cmd(cmds)
	_polling = false
	if not active:
		return
	if res.is_empty():
		if _pid > 0 and not OS.is_process_running(_pid):
			_gone += 1
			if _gone >= 2:
				var code := OS.get_process_exit_code(_pid)
				var g := PlayerLog.mpv_grund(_read_mpv_log()) if not _lief else {}
				# Ende, bevor etwas lief: ein Fehlstart (yt-dlp, Quelle, Option) – mit Grund statt still
				# zu. Code 0 ohne Fehler im Protokoll: selbst geschlossen (Alt+F4), kein Fehler.
				if not _lief and not (code == 0 and str(g.zeile) == ""):
					PlayerLog.zeile("mpv-Ende mit Code %d nach %d ms, %s; %s" % [code, Time.get_ticks_msec() - _t_launch,
						"Steuerkanal ok" if _ipc_ok else "Steuerkanal nie erreicht", str(g.zeile) if str(g.zeile) != "" else "kein Fehler im mpv-Protokoll"])
					_fail_start(str(g.text))
					return
				# mpv wurde geschlossen (zum Beispiel über Alt+F4).
				PlayerLog.zeile("mpv beendet (Code %d)" % code)
				_save()
				_finish()
		elif _pid > 0 and not _ipc_ok and not _ipc_warned and Time.get_ticks_msec() - _t_launch > IPC_WARN_MS:
			_ipc_warned = true
			PlayerLog.zeile("Steuerkanal antwortet nach %d s nicht (Helfer %s)" % [int(IPC_WARN_MS / 1000.0), "da" if Helper.available else "fehlt"])
		return
	_gone = 0
	if not _ipc_ok:
		_ipc_ok = true
		PlayerLog.zeile("Steuerkanal ok nach %d ms" % (Time.get_ticks_msec() - _t_launch))
	# mpv antwortet: jetzt ist auch das Skript der Leiste geladen.
	if not _meta_sent:
		osd_meta()
		_send_subs()
		# Gemerkte Stufe noch einmal setzen: auch wenn mpv weiterlief (nächstes Video) oder eine
		# Änderung beim Start noch ins Leere ging, weil die Pipe noch nicht offen war.
		_push_volume()
	var val := {}
	for i in mini(props.size(), res.size()):
		var r: Variant = res[i]
		# Ohne Wert (null) gilt eine Eigenschaft als nicht gemeldet: bool(null) bräche die Abfrage sonst jedes Mal ab.
		if r is Dictionary and str(r.get("error", "")) == "success" and r.get("data") != null:
			val[props[i]] = r.get("data")
	if val.has("time-pos"):
		pos = Fremd.komma(val["time-pos"], pos)
	if val.has("duration"):
		duration = Fremd.komma(val["duration"], duration)
	if val.has("pause"):
		paused = Fremd.ja(val["pause"])
	loading = not val.has("time-pos") or Fremd.ja(val.get("paused-for-cache"))
	if loading:
		_t_laden = true
	elif _t_open >= 0 and _t_laden:
		Media.log_line("leistung", start_text(video, shorts, Time.get_ticks_msec() - _t_open, _t_weg, _pre_ms))
		PlayerLog.zeile(start_text(video, shorts, Time.get_ticks_msec() - _t_open, _t_weg, _pre_ms))
		_t_open = -1
	if not loading and _t_laden:
		_lief = true
	var eof := Fremd.ja(val.get("eof-reached"))
	if eof and not at_end:
		at_end = true
		_save()
		reached_end.emit()
		_end_in_background()
	elif not eof:
		at_end = false
	_check_segments()
	changed.emit()


## Video ließ sich nicht starten: Grund ins Protokoll, Meldung mit „Erneut versuchen“, Player zu.
## setup: es fehlt noch etwas – dann führt die Meldung zum Einrichten statt zum erneuten Start.
func _fail_start(text: String, detail := "", setup := false) -> void:
	error = text
	PlayerLog.zeile("Abbruch %s: %s%s" % [_art(video), text, (" – " + detail) if detail != "" else ""])
	var list := queue.duplicate()
	var at := index
	var opts := { "audio": audio_only, "shorts": shorts, "pip": pip, "start": pos }
	var again := func() -> void:
		var m: Node = get_tree().current_scene
		if setup:
			if m != null and m.has_method("goto"):
				m.call("goto", "videos", "fuerdich")
			if not YouTube.setting_up:
				YouTube.setup_tools()
		elif m != null and m.has_method("open_video") and not list.is_empty():
			m.call("open_video", list, at, opts)
	var go_text := "Einrichten" if setup else "Erneut versuchen"
	Toasts.show_toast("Player wird eingerichtet" if setup else "Video startet nicht", text, "video" if setup else "warning",
		{ "ms": 9000, "open": again, "open_text": go_text, "go": again, "go_text": go_text, "tag": "player:fehler" })
	if setup and not YouTube.setting_up:
		YouTube.setup_tools()
	_finish()


static func _da(on: bool) -> String:
	return "da" if on else "fehlt"


static func _art(v: Dictionary) -> String:
	return "Film" if v.has("movies") else ("Stream" if v.has("twitch") else ("Datei" if is_direct(v) else "Video"))


## mpvs eigenes Protokoll (nicht unter logs/: es enthält Pfade). Wird bei jedem Start neu angelegt.
static func mpv_log_path() -> String:
	return Config.path("cache/mpv_letzter_start.log")


func _read_mpv_log() -> String:
	var f := FileAccess.open(mpv_log_path(), FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_length()
	f.seek(maxi(0, n - 64 * 1024))
	var t := f.get_buffer(mini(n, 64 * 1024)).get_string_from_utf8()
	f.close()
	return t


## Zeile fürs Protokoll: wie lange vom Start bis zum ersten Bild (Abfrage alle 250 ms, so genau
## ist auch die Zahl).
static func start_text(v: Dictionary, is_short: bool, ms: int, weg: String, aufloesen_ms := 0) -> String:
	var art := "Shorts" if is_short else ("Film" if v.has("movies") else ("Stream" if v.has("twitch") else "Video"))
	var extra := ""
	if weg == "vorab aufgelöst" and aufloesen_ms > 0:
		extra = ", Auflösen vorher %d ms" % aufloesen_ms
	return "%s: Start bis Bild %d ms (%s%s)" % [art, ms, weg if weg != "" else "unbekannt", extra]


## Ende im Hintergrund (ohne Player, der sonst die Endkarte zeigt): wie „Automatisch weiter“ das
## nächste Video der Liste, sonst ist Schluss und die Kopfleiste wird wieder still.
func _end_in_background() -> void:
	if not background:
		return
	if has_next() and bool(Config.get_value("youtube.autoplay", true)):
		next()
	else:
		stop()


func _check_segments() -> void:
	if loading:
		return
	var i := skip_index(segments, pos, _skipped)
	if i < 0:
		return
	var s: Dictionary = segments[i]
	_skipped[i] = true
	last_skip = { "i": i, "start": float(s.start), "at": Time.get_ticks_msec() }
	skipped.emit(YouTube.category_name(str(s.category)))
	seek_to(float(s.end))


## Welcher Abschnitt ist jetzt zu überspringen? -1: keiner. Jeder nur einmal (done), und nicht in
## den letzten 0,6 s (dort wäre der Sprung kaum zu merken und mpv springt ohnehin gleich weiter).
static func skip_index(segs: Array, at: float, done: Dictionary) -> int:
	for i in segs.size():
		var s: Variant = segs[i]
		if not (s is Dictionary):
			continue
		if at >= float(s.get("start", 0.0)) and at < float(s.get("end", 0.0)) - 0.6 and not done.has(i):
			return i
	return -1


## Kurz nach einem Sprung: führt „zurück“ an den Anfang des Abschnitts?
static func undo_open(last: Dictionary, now_ms: int) -> bool:
	return not last.is_empty() and now_ms - int(last.get("at", 0)) <= UNDO_MS


func can_undo_skip() -> bool:
	return active and undo_open(last_skip, Time.get_ticks_msec())


## Zurück an den Anfang des eben übersprungenen Abschnitts; er bleibt dann (kein zweiter Sprung).
func undo_skip() -> bool:
	if not can_undo_skip():
		return false
	var t := float(last_skip.start)
	last_skip = {}
	seek_to(t)
	return true


## Befehle an mpv schicken. Gibt die Antworten zurück ({ error, data } je Befehl).
## quick: darf den gerade freieren Helfer-Weg nehmen (nur für Befehle, deren Reihenfolge zu den
## übrigen egal ist, z. B. die Lautstärke als fester Wert).
func _cmd(cmds: Array, quick := false) -> Array:
	if sim or not Helper.available:
		return []
	var lines: Array = []
	for c in cmds:
		_rid += 1
		lines.append(JSON.stringify({ "command": c, "request_id": _rid }))
	var args := { "pipe": _pipe, "cmds": lines }
	if quick:
		args["either"] = true
	var r := await Helper.run("mpv", args, 3.0)
	if not r.ok or not (r.result is Dictionary):
		return []
	var out: Array = []
	var raw: Variant = r.result.get("results", [])
	if raw is String:
		raw = [raw]
	for line in raw:
		out.append(Fremd.json(str(line)) if str(line) != "" else {})
	return out

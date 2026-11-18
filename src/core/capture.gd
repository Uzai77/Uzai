extends Node
## Uzai's own capture, like the capture feature on PS5 and Xbox: during a game a rolling buffer
## of the last seconds runs silently, and „Clip speichern“ (Guide, or hold Guide + X, Share
## button) turns it into an MP4 under Videos\Uzai right away. Also longer recordings (up to
## 10 minutes), screenshots including fullscreen games, and a gallery with editing (trim, slow
## motion, text), renaming, deleting and sharing.
##
## The logic (which segments, command lines, names, limits) lives in capture_logic.gd. This file holds the
## state, loads FFmpeg, starts and stops the buffer in the helper, joins clips and runs the gallery.
## Windows only; elsewhere everything stays off (the gallery then shows what is in the folder).
##
## Dependency FFmpeg (GPL, BtbN build from GitHub, linked from ffmpeg.org): downloaded only on
## request, once, into the data folder (tools\ffmpeg) and verified against the site's checksum
## list; it is not bundled with Uzai. Without FFmpeg there is no free way on Windows to encode
## screen and audio on the GPU.

signal changed(what: String)
signal progress(text: String, frac: float)
## Bearbeiten fertig (src/core/clip_edit.gd): neuer Pfad, "" bei Fehler oder Abbruch.
signal edit_done(path: String)

const L := preload("res://src/core/capture_logic.gd")
const E := preload("res://src/core/clip_edit.gd")
const Zustand := preload("res://src/core/zustand.gd")

const PIPE_SYS := "uzai-cap-sys"
const PIPE_MIC := "uzai-cap-mic"
const START_GRACE_S := 12.0       ## so lange darf der Start dauern, bis das erste Stück da ist
const STATUS_EVERY_S := 5.0
const FPS_LOG_S := 60.0           ## so oft steht die gemessene Bildrate im Protokoll

## Rollpuffer im Spiel: startet, läuft (puffer) oder aus – auch nach einem Fehler (Grund in why).
const ZUSTAENDE := { "aus": ["startet"], "startet": ["puffer", "aus"], "puffer": ["aus"] }
var state := "aus":               ## aus | startet | puffer
	set(neu):
		Zustand.wechsel("aufnahme.puffer", ZUSTAENDE, state, neu)
		state = neu
var why := ""                     ## warum der Puffer nicht läuft (capture_logic.block_text)
var last_error := ""
var installing := false
var recording := false
var rec_start_unix := 0.0
var t0 := 0.0                     ## Zeitbasis des laufenden Puffers (Unix-Sekunden)
var saving := false

var _attempts: Array = []
var _attempt := 0
var _cur_attempt := ""
var _audio_off := false           ## Ton ließ sich nicht öffnen: ohne Ton weiter
var _started_ms := 0
var _tick_t := 0.0
var _status_t := 0.0
var _front_s := 0.0
var _on_battery := false
var _guide_unix := 0.0
var _guide_open_unix := 0.0
var _last_hotkey_ms := -100000
var _rec_segments: Array = []     ## kopierte Stücke der langen Aufnahme { file, start, end }
var _rec_seen := {}
var _busy := false                ## Start/Stopp unterwegs
var _thumb_queue: Array = []
var _thumb_running := false
var _index := {}                  ## Dateipfad -> { game_id, duration, fps, path }
var _fps_t := 0.0                 ## Sekunden bis zur nächsten Bildraten-Zeile im Protokoll
var _fps_last: Dictionary = {}    ## letzte Messung des Puffers (capture_logic.progress_fps)
var _fps_warned := false
var _session_new: Array = []      ## in diesem Spiel gespeicherte Clips (Mitteilung am Ende)
var _items_cache: Array = []      ## list_items, kurz gemerkt (Startseite fragt bei jedem Aufbau)
var _items_ms := -100000
const INDEX_PRUEF_MS := 60000   ## so oft höchstens prüft _save_index, ob es die Dateien noch gibt
var _index_geprueft_ms := -1000000
var _items_gen := 0               ## Stand von Undo.gen beim Merken (vorgemerkte Löschungen)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Erst prüfen, dann zuweisen: Stand in der Datei kein Verzeichnis, brach die Zuweisung _ready ab – und mit ihm die
	# ganze Aufnahme (keine der Verbindungen unten kam zustande).
	var gemerkt: Variant = Config.read_json(Config.path("captures.json"), {}) if FileAccess.file_exists(Config.path("captures.json")) else {}
	_index = gemerkt if gemerkt is Dictionary else {}
	changed.connect(func(what: String) -> void:
		if what == "files":
			_items_ms = -100000
	)
	Config.changed.connect(func(k: String) -> void:
		if k == "capture.folder":
			_items_ms = -100000
	)
	if not active_platform():
		set_process(false)
		return
	_clean_dir(buffer_dir())
	Helper.pad_event.connect(func(kind: String) -> void:
		if kind == "guide":
			_note_guide()
	)
	Nav.command.connect(func(cmd: String) -> void:
		if cmd == "guide":
			_note_guide()
	)
	Launcher.ended.connect(func(g: Dictionary, _secs: int) -> void: _after_game(g))
	# Andere Einstellung (Qualität, Ton, Quelle …): mit den neuen Werten von vorn.
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("capture.") and not k in ["capture.working", "capture.ffmpeg_build"]:
			_attempts = []
			_attempt = 0
			_audio_off = false
			if why == "fehler":
				why = ""
				_busy = false
			if state != "aus" and not recording and not saving and not _busy:
				_stop()
	)


static func active_platform() -> bool:
	return OS.get_name() == "Windows"


# --- Einstellungen und Orte ------------------------------------------------------------------

func opt(key: String) -> Variant:
	return Config.get_value("capture." + key, L.DEFAULTS.get(key))


func via_uzai() -> bool:
	return str(opt("via")) == "uzai"


func length_s() -> int:
	var v := str(opt("length"))
	return int(v) if v in L.LENGTHS else 30


func fps() -> int:
	return 30 if str(opt("fps")) == "30" else 60


func ffmpeg_path() -> String:
	return Config.path("tools/ffmpeg/ffmpeg.exe")


func has_ffmpeg() -> bool:
	return FileAccess.file_exists(ffmpeg_path())


func buffer_dir() -> String:
	return Config.path("capture/puffer")


func rec_dir() -> String:
	return Config.path("capture/aufnahme")


func thumbs_dir() -> String:
	return Config.path("cache/captures")


## Clips: Einstellung, sonst Videos\Uzai. Bildschirmfotos legt der Helfer seit jeher in Bilder\Uzai.
func clips_dir() -> String:
	var own := str(opt("folder"))
	if own != "":
		return own
	var v := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if v == "":
		v = Config.path("aufnahmen")
	return v.path_join("Uzai")


func shots_dir() -> String:
	var p := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if p == "":
		p = Config.path("aufnahmen")
	return p.path_join("Uzai")


static func win(p: String) -> String:
	return p.replace("/", "\\") if OS.get_name() == "Windows" else p


func screen_size() -> Vector2i:
	var scr := DisplayServer.window_get_current_screen()
	var s := DisplayServer.screen_get_size(scr)
	return s if s.x > 0 else Vector2i(1920, 1080)


func _game_title() -> String:
	if Launcher.in_game and not Launcher.current.is_empty():
		return Library.display_title(Launcher.current)
	if Video.active:
		return str(Video.video.get("title", "Video"))
	return "Uzai"


# --- FFmpeg laden ----------------------------------------------------------------------------

## Lädt FFmpeg (einmalig, mit Fortschritt) und prüft die Prüfsumme. "" oder Fehlertext.
func install() -> String:
	if installing:
		return "Läuft schon."
	if not active_platform():
		return "Das geht nur unter Windows."
	installing = true
	changed.emit("install")
	var err := await _install()
	installing = false
	progress.emit("Fertig" if err == "" else err, 1.0)
	changed.emit("install")
	return err


func _install() -> String:
	var dir := Config.path("tools/ffmpeg")
	DirAccess.make_dir_recursive_absolute(dir)
	progress.emit("Prüfsummen werden geladen …", 0.0)
	var sums := dir.path_join(L.SUMS)
	if not await Net.download_big(L.BUILDS + L.SUMS, sums):
		return "Die Liste von FFmpeg ließ sich nicht laden (GitHub erreichbar?)."
	var pick := L.pick_build(FileAccess.get_file_as_string(sums))
	DirAccess.remove_absolute(sums)
	if pick.is_empty():
		return "Kein passendes FFmpeg-Paket gefunden."
	var zip := dir.path_join("ffmpeg.zip")
	var ok := await Net.download_big(str(pick.url), zip, func(got: int, total: int) -> void:
		progress.emit("FFmpeg wird geladen … %d von %d MB" % [got / 1000000, maxi(1, total / 1000000)], float(got) / float(total) if total > 0 else 0.0)
	)
	if not ok:
		return "FFmpeg ließ sich nicht laden."
	progress.emit("Prüfsumme wird geprüft …", 1.0)
	var sha := await Net.sha256_datei(zip)
	if sha != str(pick.sha).to_lower():
		DirAccess.remove_absolute(zip)
		return "Die Prüfsumme des Downloads stimmt nicht – nichts installiert. Bitte später noch einmal."
	progress.emit("FFmpeg wird entpackt …", 1.0)
	var tmp := dir.path_join("entpackt")
	_clean_dir(tmp)
	DirAccess.make_dir_recursive_absolute(tmp)
	# tar.exe mit vollem Pfad (siehe YouTube.windows_tar).
	var tar: String = YouTube.windows_tar()
	var res: Dictionary = { "error": "tar.exe fehlt in Windows" }
	if tar != "":
		res = await YouTube.exec(tar, PackedStringArray(["-xf", win(zip), "-C", win(tmp)]), 300.0)
	DirAccess.remove_absolute(zip)
	var exe := _find_file(tmp, "ffmpeg.exe")
	if exe == "":
		_clean_dir(tmp)
		return "FFmpeg ließ sich nicht entpacken (%s)." % str(res.get("error", "")).strip_edges().left(80)
	if FileAccess.file_exists(ffmpeg_path()):
		DirAccess.remove_absolute(ffmpeg_path())
	DirAccess.rename_absolute(exe, ffmpeg_path())
	var lic := _find_file(tmp, "LICENSE.txt")
	if lic != "":
		if FileAccess.file_exists(dir.path_join("LICENSE.txt")):
			DirAccess.remove_absolute(dir.path_join("LICENSE.txt"))
		DirAccess.rename_absolute(lic, dir.path_join("LICENSE.txt"))
	_clean_dir(tmp)
	var v := await YouTube.exec(ffmpeg_path(), PackedStringArray(["-hide_banner", "-version"]), 30.0)
	if not bool(v.get("ok", false)):
		return "FFmpeg startet nicht."
	Config.set_value("capture.ffmpeg_build", str(pick.file))
	Config.set_value("capture.working", "")
	return ""


func _find_file(dir: String, name: String) -> String:
	var stack := [dir]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.to_lower() == name.to_lower():
				return d.path_join(f)
		for sub in da.get_directories():
			stack.append(d.path_join(sub))
	return ""


func _clean_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		# Nie durch eine Verknüpfung hindurch löschen (nur die Verknüpfung selbst).
		if not da.is_link(sub):
			_clean_dir(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))


# --- Puffer an und aus -----------------------------------------------------------------------

func _process(dt: float) -> void:
	_tick_t += dt
	if Launcher.in_game and get_window().has_focus() and not Launcher.guide_open:
		_front_s += dt
	else:
		_front_s = 0.0
	if _tick_t < 1.0:
		return
	_tick_t = 0.0
	_tick()


func block_reason() -> String:
	var free_mb := 1 << 30
	var da := DirAccess.open(Config.path(""))
	if da:
		free_mb = int(da.get_space_left() / 1000000)
	return L.buffer_block({ "via": str(opt("via")), "buffer": bool(opt("buffer")), "ffmpeg": has_ffmpeg(), "helper": Helper.available,
		"in_game": Launcher.in_game, "video": Video.active, "videos": bool(opt("videos")), "uzai_front_s": _front_s,
		"on_battery": _on_battery, "battery": bool(opt("battery")), "disk_free_mb": free_mb, "recording": recording })


func _tick() -> void:
	if _busy or installing:
		return
	why = block_reason()
	if why == "" and state == "aus":
		_start()
		return
	if why != "" and state != "aus" and not recording and not saving:
		_stop()
		return
	if state == "startet" and Time.get_ticks_msec() - _started_ms > int(START_GRACE_S * 1000.0):
		if _segments().is_empty():
			await _failed("Kein Bild nach %d s" % int(START_GRACE_S))
			return
	if state == "startet" and not _segments().is_empty():
		state = "puffer"
		_fps_t = 25.0
		_fps_warned = false
		Config.set_value("capture.working", _cur_attempt)
		Helper.hlog("Aufnahme: Puffer läuft (%s)" % _cur_attempt)
		changed.emit("state")
	if state != "aus":
		_status_t += 1.0
		if _status_t >= STATUS_EVERY_S:
			_status_t = 0.0
			_check_status()
		if state == "puffer":
			_fps_t -= 1.0
			if _fps_t <= 0.0:
				_fps_t = FPS_LOG_S
				_log_fps()
	elif why in ["akku", ""]:
		_status_t += 1.0
		if _status_t >= 30.0:
			_status_t = 0.0
			_check_status()
	if recording:
		_collect_rec()
		if Time.get_unix_time_from_system() - rec_start_unix >= float(L.RECORD_MAX_S):
			Toasts.show_toast("Aufnahme nach 10 Minuten beendet", "Wird gespeichert …", "video", { "overlay": true })
			stop_record()


func _check_status() -> void:
	var r := await Helper.run("cap-status", {}, 6.0)
	if not bool(r.get("ok", false)) or not (r.get("result") is Dictionary):
		return
	var st: Dictionary = r.result
	_on_battery = bool(st.get("on_battery", false))
	if state != "aus" and not _busy and not bool(st.get("running", false)) and int(st.get("pid", 0)) > 0:
		var up := int(st.get("uptime", 0))
		var err := str(st.get("err", ""))
		Helper.hlog("Aufnahme: FFmpeg beendet (Code %s, %d s): %s" % [str(st.get("code", "?")), up, err.left(600)])
		if up > 30:
			# Lief schon eine Weile (Auflösung gewechselt, Grafiktreiber): einfach neu starten.
			state = "aus"
			changed.emit("state")
		else:
			await _failed(err)


func _segments() -> Array:
	var p := buffer_dir().path_join("list.csv")
	if not FileAccess.file_exists(p):
		return []
	return L.parse_seg_list(FileAccess.get_file_as_string(p))


func _start() -> void:
	if not Config.is_windows():
		return
	_busy = true
	state = "startet"
	changed.emit("state")
	if _attempts.is_empty():
		_attempts = L.attempts(str(opt("source")) == "window", str(Config.get_value("capture.working", "")))
		_attempt = 0
	_cur_attempt = str(_attempts[mini(_attempt, _attempts.size() - 1)])
	await Helper.run("cap-stop", {}, 8.0)
	_clean_dir(buffer_dir())
	DirAccess.make_dir_recursive_absolute(buffer_dir())
	var parts := L.attempt_parts(_cur_attempt)
	var size := L.fit_size(screen_size(), str(opt("quality")))
	var f := fps()
	var sys := bool(opt("audio")) and not _audio_off
	var mic := bool(opt("mic")) and not _audio_off
	# Zufälliger Name je Aufnahme (früher die Prozessnummer): Niemand kann ihn vorher belegen. Der Helfer legt die
	# Leitung nur für dieses Konto an und gibt den Ton nur dem FFmpeg, das er selbst gestartet hat.
	var tag := Crypto.new().generate_random_bytes(16).hex_encode()
	var o := { "src": { "kind": parts.kind, "output": 0 }, "size": size, "fps": f, "enc": parts.enc, "gpu": parts.gpu,
		"kbps": L.bitrate_kbps(size, f), "sys": sys, "mic": mic, "pipe_sys": "\\\\.\\pipe\\%s-%s" % [PIPE_SYS, tag],
		"pipe_mic": "\\\\.\\pipe\\%s-%s" % [PIPE_MIC, tag], "dir": buffer_dir(), "length": length_s() }
	var args := L.record_args(o)
	var r := await Helper.run("cap-start", { "ffmpeg": win(ffmpeg_path()), "args": Array(args),
		"sys_pipe": ("%s-%s" % [PIPE_SYS, tag]) if sys else "", "mic_pipe": ("%s-%s" % [PIPE_MIC, tag]) if mic else "",
		"dir": win(buffer_dir()), "skip_pid": OS.get_process_id() }, 20.0)
	_busy = false
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	if not bool(r.get("ok", false)) or not bool(res.get("ok", false)):
		var e := str(res.get("error", r.get("error", "")))
		if bool(res.get("audio_failed", false)):
			# Ohne Ton weiter (Gerät belegt, kein Ausgabegerät) – Bild ist wichtiger als nichts.
			_audio_off = true
			last_error = e
			Helper.hlog("Aufnahme: ohne Ton weiter: " + e)
			state = "aus"
			return
		await _failed(e)
		return
	t0 = float(str(res.get("t0", "0")))
	_started_ms = Time.get_ticks_msec()
	if str(res.get("audio_error", "")) != "":
		last_error = str(res.audio_error)
	Helper.hlog("Aufnahme: gestartet (Weg %s: Quelle %s, Kodierer %s, %s; %dx%d, feste %d Bilder/s, %d kbit/s, Ton %s; Vorrang %s)" % [_cur_attempt,
		parts.kind, parts.enc, "Grafikkarte" if parts.gpu else "über den Arbeitsspeicher",
		size.x, size.y, f, int(o.kbps), "an" if sys else "aus", str(res.get("prio", "?"))])


## Ein Versuch ging nicht: den nächsten (andere Quelle, anderer Kodierer). Nach dem letzten: aus,
## bis sich etwas ändert (Einstellung, neues Spiel).
func _failed(err: String) -> void:
	last_error = err.strip_edges().left(300)
	Helper.hlog("Aufnahme: Versuch %s ging nicht: %s" % [_cur_attempt, last_error])
	await Helper.run("cap-stop", {}, 8.0)
	_attempt += 1
	if _attempt >= _attempts.size():
		state = "aus"
		why = "fehler"
		_attempts = []
		_attempt = 0
		# Erst beim nächsten Spiel wieder probieren.
		_busy = true
		Toasts.show_toast("Aufnahme geht gerade nicht", "Uzai hat alle Wege probiert. Beim nächsten Spiel versucht es Uzai von selbst noch einmal.", "warning",
				{ "quiet": true })
		await Launcher.ended
		_busy = false
	else:
		state = "aus"
	changed.emit("state")


func _stop() -> void:
	_busy = true
	await Helper.run("cap-stop", {}, 8.0)
	_busy = false
	state = "aus"
	_audio_off = false
	changed.emit("state")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# FFmpeg endet mit dem Helfer (Job-Objekt); was im Puffer liegt, braucht niemand mehr.
		if active_platform() and is_inside_tree():
			_clean_dir(buffer_dir())


func _note_guide() -> void:
	var now := Time.get_unix_time_from_system()
	if now - _guide_unix > 1.0:
		_guide_unix = now
	if not Launcher.guide_open:
		_guide_open_unix = now


## Kurztext für den Guide: was „Clip speichern“ gerade kann.
func clip_state_text() -> String:
	if not via_uzai():
		return "über " + ("NVIDIA" if str(opt("via")) == "nvidia" else "Game Bar")
	if state == "puffer":
		return "letzte %d s" % length_s()
	if state == "startet":
		return "startet …"
	if not has_ffmpeg():
		return "einrichten"
	return "aus"


# --- Bildrate (Protokoll) --------------------------------------------------------------------

## Was die Quelle in den letzten 20 s geliefert hat (aus FFmpegs progress.txt im Puffer).
func measure_buffer() -> Dictionary:
	var p := buffer_dir().path_join(L.PROGRESS_FILE)
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	# Nur das Ende lesen: Die Datei wächst, solange der Puffer läuft (gut 200 KB pro Stunde).
	var n := f.get_length()
	f.seek(maxi(0, n - 6000))
	var text := f.get_buffer(mini(n, 6000)).get_string_from_utf8()
	f.close()
	return L.progress_fps(L.parse_progress(text), 20.0)


func _log_fps() -> void:
	var m := measure_buffer()
	if m.is_empty():
		return
	_fps_last = m
	# Ruhig im Protokoll: jede Minute eine Zeile (mit Hinweis, wenn die Quelle zu wenig liefert).
	Helper.hlog("Aufnahme: " + L.fps_text(m, fps(), _cur_attempt))
	if L.fps_low(m, fps()) and not _fps_warned:
		_fps_warned = true
		last_error = "Quelle liefert nur %s Bilder/s" % ("%.0f" % float(m.src))


## Bilder und Länge des gespeicherten Clips zählen und ins Protokoll schreiben (läuft neben der
## Mitteilung her, „Clip speichern“ wartet nicht darauf).
func _log_clip(file: String) -> void:
	var dur := duration_of(file)
	var r := await YouTube.exec(ffmpeg_path(), L.measure_args(file), 30.0)
	var c := L.measured_clip(str(r.get("text", "")), dur)
	var src := measure_buffer()
	if not src.is_empty():
		_fps_last = src
	var line := "Aufnahme: Clip „%s“ (Weg %s): " % [file.get_file(), _cur_attempt]
	if c.is_empty():
		line += "Bildrate ließ sich nicht messen " + str(r.get("error", "")).strip_edges().left(200)
	else:
		line += "%d Bilder in %s s = %s Bilder/s in der Datei (Ziel %d)" % [int(c.frames), L._de1(float(c.seconds)), L._de1(float(c.fps)), fps()]
		var ix: Dictionary = _index.get(file, {}) if _index.get(file) is Dictionary else {}
		ix["fps"] = snappedf(float(c.fps), 0.1)
		ix["path"] = _cur_attempt
		if not _fps_last.is_empty():
			ix["src_fps"] = snappedf(float(_fps_last.src), 0.1)
		_index[file] = ix
		_save_index()
	if not _fps_last.is_empty():
		line += "; " + L.fps_text(_fps_last, fps(), _cur_attempt)
	Helper.hlog(line)


# --- Clip speichern --------------------------------------------------------------------------

## Vom Controller ohne Guide (Guide halten + X, Share-Taste): Ende beim Druck der Guide-Taste,
## damit der Guide, der dabei kurz aufgeht, nicht im Clip landet.
func hotkey(source := "") -> void:
	if Time.get_ticks_msec() - _last_hotkey_ms < 1500:
		return
	_last_hotkey_ms = Time.get_ticks_msec()
	var now := Time.get_unix_time_from_system()
	var cut := _guide_unix if source == "chord" and now - _guide_unix < 4.0 else now
	save_clip(cut)


## Aus dem Guide: Der Clip endet, als der Guide aufging (das Spielgeschehen davor), wenn das
## höchstens 8 s her ist – sonst jetzt.
func save_from_guide() -> void:
	var now := Time.get_unix_time_from_system()
	save_clip(_guide_open_unix if now - _guide_open_unix < 8.0 else now)


func save_clip(cut_unix := 0.0) -> void:
	if saving:
		return
	if state != "puffer":
		var t := L.block_text(why) if why != "" else ("Der Puffer startet gerade." if state == "startet" else "")
		if why == "fehler":
			t = "Die Aufnahme ging bei diesem Spiel nicht: " + last_error.left(120)
		Toasts.show_toast("Kein Clip", t, "warning", { "overlay": true })
		return
	saving = true
	var now := Time.get_unix_time_from_system()
	var cut := cut_unix if cut_unix > 0.0 and cut_unix <= now else now
	# Das Stück mit dem Ende muss geschrieben sein (FFmpeg hinkt ein paar Bilder hinterher).
	var wait := cut + 0.5 - now
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	var file := await _assemble(L.stream_time(cut, t0), float(length_s()), _game_title(), "")
	saving = false
	if file != "":
		_announce(file, "Clip gespeichert")


## Stücke zusammenfügen; "" bei Fehler (mit Mitteilung).
func _assemble(cut_t: float, len_s: float, title: String, suffix: String, extra_first: Array = []) -> String:
	var segs := _segments()
	var live := L.live_segment(segs, L.seg_wrap(length_s()))
	var pick: Dictionary
	if extra_first.is_empty():
		pick = L.pick_segments(segs, live, cut_t, len_s)
	else:
		# Lange Aufnahme: kopierte Stücke, dann was noch im Puffer liegt.
		var seen := {}
		var all: Array = []
		for s in extra_first:
			all.append(s)
			seen[str(s.start)] = true
		for s in segs:
			if not seen.has(str(s.start)) and float(s.start) > float(all[all.size() - 1].start if not all.is_empty() else -1.0):
				all.append({ "file": buffer_dir().path_join(str(s.file)), "start": s.start, "end": s.end })
		var lv := { "file": buffer_dir().path_join(str(live.get("file", ""))), "start": live.get("start", 0.0) }
		pick = L.pick_segments(all, lv, cut_t, len_s)
	if pick.is_empty():
		Toasts.show_toast("Clip ging nicht", "Im Puffer ist noch nichts – gleich noch einmal.", "warning", { "overlay": true })
		return ""
	var used := folder_bytes(clips_dir())
	var est := L.estimate_bytes(L.bitrate_kbps(L.fit_size(screen_size(), str(opt("quality"))), fps()), float(pick.duration))
	if L.over_cap(used, est, L.cap_bytes(str(opt("cap_gb")))):
		Toasts.show_toast("Speicher für Aufnahmen voll", "Unter Aufnahmen alte Clips löschen oder die Grenze in den Einstellungen erhöhen.", "warning",
				{ "overlay": true })
		return ""
	var paths: Array = []
	for f in pick.files:
		var p := str(f)
		paths.append(p if p.contains("/") or p.contains("\\") else buffer_dir().path_join(p))
	DirAccess.make_dir_recursive_absolute(clips_dir())
	var name := L.unique_name(Array(DirAccess.get_files_at(clips_dir())), L.capture_name(title, Time.get_datetime_dict_from_system(), "mp4", suffix))
	var out := clips_dir().path_join(name)
	var list := Config.path("capture/clip.ffconcat")
	var fl := FileAccess.open(list, FileAccess.WRITE)
	if fl == null:
		return ""
	fl.store_string(L.concat_text(paths))
	fl.close()
	var r := await YouTube.exec(ffmpeg_path(), L.concat_args(list, out, float(pick.duration)), 90.0)
	if not bool(r.get("ok", false)) or not FileAccess.file_exists(out):
		Helper.hlog("Aufnahme: Zusammenfügen ging nicht: " + str(r.get("error", "")).left(600))
		Toasts.show_toast("Clip ging nicht", "FFmpeg konnte die Teile nicht zusammenfügen. Gleich noch einmal versuchen.", "warning", { "overlay": true })
		return ""
	_index[out] = { "game_id": str(Launcher.current.get("id", "")) if Launcher.in_game else "", "duration": snappedf(float(pick.duration), 0.01) }
	_save_index()
	if Launcher.in_game:
		_session_new.append(out)
	_log_clip(out)
	return out


## Mitteilung „Clip gespeichert“ mit „Ansehen“: außerhalb eines Spiels öffnet View den Clip gleich
## im Player; im Spiel (dort spielt Uzai keine Videos) führt „Ansehen“ aus den Mitteilungen im
## Guide in die Galerie, der Clip gewählt – und nach dem Spiel kommt eine Erinnerung (_after_game).
func _announce(file: String, head: String) -> void:
	var dur := duration_of(file)
	var sub := str(L.parse_name(file).title) + ("  ·  " + L.mmss(dur) if dur > 0.0 else "")
	var thumb := await thumb_now(file)
	var opts := { "image": thumb, "sound": "shutter", "force": true, "overlay": true,
		"go": func() -> void: open_file(file), "go_text": "Ansehen" }
	if not Launcher.in_game:
		opts["open"] = func() -> void: open_file(file)
		opts["open_text"] = "Ansehen"
	Toasts.show_toast(head, sub, "video", opts)
	changed.emit("files")


func _open_gallery(focus := "") -> void:
	var m: Node = get_tree().current_scene
	if m and m.has_method("open_captures"):
		m.open_captures(focus)


## Spiel zu Ende, in dem Clips entstanden: eine Mitteilung, mit View gleich den neuesten ansehen.
func _after_game(g: Dictionary) -> void:
	var files: Array = _session_new.filter(func(f) -> bool: return FileAccess.file_exists(str(f)))
	_session_new = []
	if files.is_empty():
		return
	# Nach der Mitteilung „Diesmal … gespielt“ (main), nicht gleichzeitig.
	await get_tree().create_timer(2.5).timeout
	var newest := str(files[files.size() - 1])
	var title := Library.display_title(g) if not g.is_empty() else str(L.parse_name(newest).title)
	var head := ("Neuer Clip aus %s" % title) if files.size() == 1 else ("%d neue Clips aus %s" % [files.size(), title])
	var th := thumb_path(newest)
	Toasts.show_toast(head, "Im Guide unter System und auf der Spielseite", "video", { "image": th if FileAccess.file_exists(th) else "", "ms": 7000,
		"open": func() -> void: open_file(newest), "open_text": "Ansehen", "go": func() -> void: open_file(newest), "go_text": "Ansehen" })


# --- Für Galerie, Startseite, Spielseite und Guide ---------------------------------------------

## Die neuesten Aufnahmen (Clips und Bildschirmfotos), neueste zuerst; n = 0: alle.
## Einträge wie list_items: { path, kind (clip|shot), title, stamp, mtime, size, duration, game_id }
func latest(n := 12) -> Array:
	var all := list_items()
	return all if n <= 0 else all.slice(0, n)


## Aufnahmen eines Spiels (Spiel-Eintrag oder Spiel-ID), neueste zuerst; n = 0: alle. Neue Clips
## tragen die Spiel-ID, ältere und Bildschirmfotos zählen über den Titel im Dateinamen.
func for_game(game: Variant, n := 0) -> Array:
	var g: Dictionary = game if game is Dictionary else Library.get_game(str(game))
	var gid := str(g.get("id", "")) if not g.is_empty() else str(game)
	var title := Library.display_title(g) if not g.is_empty() else ""
	var out: Array = list_items().filter(func(it) -> bool: return L.belongs_to(it, gid, title))
	return out if n <= 0 else out.slice(0, n)


## Eine Aufnahme ansehen: Clip im Player (außerhalb eines Spiels), Bildschirmfoto groß. Im Spiel
## die Galerie mit dieser Aufnahme gewählt (Clips laufen erst nach dem Spiel).
func open_file(path: String) -> void:
	var m: Node = get_tree().current_scene
	if m == null or not FileAccess.file_exists(path):
		_open_gallery()
		return
	if Launcher.in_game and L.kind_of(path) == "clip":
		_open_gallery(path)
		return
	load("res://src/ui/layers/captures.gd").view(m, path)


# --- Längere Aufnahme ------------------------------------------------------------------------

func toggle_record() -> void:
	if recording:
		stop_record()
	else:
		start_record()


func start_record() -> void:
	if not via_uzai() or not has_ffmpeg() or not Config.is_windows():
		Toasts.show_toast("Aufnahme geht gerade nicht", L.block_text("ffmpeg" if not has_ffmpeg() else "via"), "warning", { "overlay": true })
		return
	recording = true
	rec_start_unix = Time.get_unix_time_from_system()
	_rec_segments = []
	_rec_seen = {}
	_clean_dir(rec_dir())
	DirAccess.make_dir_recursive_absolute(rec_dir())
	changed.emit("record")
	if state == "aus":
		_tick()
	Toasts.show_toast("Aufnahme läuft", "Höchstens 10 Minuten. Im Guide „Aufnahme beenden“.", "video", { "overlay": true, "sound": "select" })


## Fertige Stücke der langen Aufnahme aus dem Puffer retten, bevor er sie überschreibt.
func _collect_rec() -> void:
	if t0 <= 0.0:
		return
	var from := L.stream_time(rec_start_unix, t0) - float(L.SEG_S)
	for s in _segments():
		var key := "%.3f" % float(s.start)
		if _rec_seen.has(key) or float(s.end) < from:
			continue
		_rec_seen[key] = true
		var dst := rec_dir().path_join("rec%04d.ts" % _rec_segments.size())
		if DirAccess.copy_absolute(buffer_dir().path_join(str(s.file)), dst) == OK:
			_rec_segments.append({ "file": dst, "start": float(s.start), "end": float(s.end) })


func stop_record() -> void:
	if not recording:
		return
	_collect_rec()
	var now := Time.get_unix_time_from_system()
	var len_s := now - rec_start_unix
	saving = true
	var file := ""
	if state == "puffer" and t0 > 0.0:
		await get_tree().create_timer(0.5).timeout
		file = await _assemble(L.stream_time(now, t0), len_s, _game_title(), "", _rec_segments if not _rec_segments.is_empty() else [])
	recording = false
	saving = false
	_clean_dir(rec_dir())
	changed.emit("record")
	if file != "":
		_announce(file, "Aufnahme gespeichert")
	elif state != "puffer":
		Toasts.show_toast("Aufnahme ging nicht", L.block_text(why), "warning", { "overlay": true })


func record_seconds() -> int:
	return int(Time.get_unix_time_from_system() - rec_start_unix) if recording else 0


func record_text() -> String:
	return L.mmss(record_seconds())


# --- Bildschirmfoto --------------------------------------------------------------------------

## Mit FFmpeg (Desktop-Duplizierung: auch Vollbild-Spiele, die der alte Weg schwarz fotografierte).
## Gibt die Datei zurück oder "" (dann nimmt main den bisherigen Weg über den Helfer).
func screenshot(title: String) -> String:
	if not has_ffmpeg() or not Config.is_windows():
		return ""
	DirAccess.make_dir_recursive_absolute(shots_dir())
	var name := L.unique_name(Array(DirAccess.get_files_at(shots_dir())), L.capture_name(title, Time.get_datetime_dict_from_system(), "png"))
	var out := shots_dir().path_join(name)
	var r := await YouTube.exec(ffmpeg_path(), L.shot_args({ "kind": "dda", "output": 0 }, out), 12.0)
	if bool(r.get("ok", false)) and FileAccess.file_exists(out):
		changed.emit("files")
		return out
	Helper.hlog("Bildschirmfoto über FFmpeg ging nicht: " + str(r.get("error", "")).left(300))
	return ""


# --- Galerie ---------------------------------------------------------------------------------

## Alle Aufnahmen: { path, kind (clip|shot), title, stamp, mtime, size, duration }, neueste zuerst.
func list_items() -> Array:
	# Kurz gemerkt (Startseite, Spielseite und Guide fragen oft); Änderungen durch Uzai leeren das
	# sofort, im Explorer gelöschte Dateien verschwinden nach spätestens 3 s.
	if Time.get_ticks_msec() - _items_ms < 3000 and _items_gen == Undo.gen:
		return _items_cache.duplicate()
	_items_gen = Undo.gen
	var out: Array = []
	for d in [clips_dir(), shots_dir()]:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			var kind := L.kind_of(f)
			if kind == "" or f.begins_with("."):
				continue
			var p := str(d).path_join(f)
			# Zum Löschen vorgemerkt (Rückgängig läuft noch): schon nicht mehr zeigen.
			if Undo.hides(p):
				continue
			var info := L.parse_name(f)
			var ix: Dictionary = _index.get(p, {}) if _index.get(p) is Dictionary else {}
			out.append({ "path": p, "kind": kind, "title": str(info.title).trim_suffix("_").strip_edges(), "stamp": info.stamp,
				"mtime": FileAccess.get_modified_time(p), "size": _file_size(p), "duration": float(ix.get("duration", 0.0)),
				"game_id": str(ix.get("game_id", "")) })
	out.sort_custom(func(a, b) -> bool: return int(a.mtime) > int(b.mtime))
	_items_cache = out
	_items_ms = Time.get_ticks_msec()
	return out.duplicate()


## Nur die Anzahl der Aufnahmen (Abzeichen): die Ordner auflisten, keine Datei anfassen. list_items fragt je Datei
## Größe und Änderungszeit ab – gemessen 20-mal so teuer.
func count_items() -> int:
	if Time.get_ticks_msec() - _items_ms < 3000 and _items_gen == Undo.gen:
		return _items_cache.size()
	var n := 0
	for d in [clips_dir(), shots_dir()]:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if L.kind_of(f) != "" and not f.begins_with(".") and not Undo.hides(str(d).path_join(f)):
				n += 1
	return n


func folder_bytes(dir: String) -> int:
	var n := 0
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if L.kind_of(f) == "clip":
				n += _file_size(dir.path_join(f))
	return n


## Größe, ohne die Datei zu öffnen (0, wenn es sie nicht gibt). Gemessen bei 600 Aufnahmen: 4 statt 8 ms; unter
## Windows kommt dazu, dass ein geöffnetes Video den Virenschutz weckt.
static func _file_size(p: String) -> int:
	return maxi(0, FileAccess.get_size(p))


func thumb_path(file: String) -> String:
	if L.kind_of(file) == "shot":
		return file
	return thumbs_dir().path_join("%s.jpg" % ("%s|%d" % [file, FileAccess.get_modified_time(file)]).md5_text())


## Vorschaubild sofort (wartet auf FFmpeg); "" ohne FFmpeg.
func thumb_now(file: String) -> String:
	var t := thumb_path(file)
	if FileAccess.file_exists(t):
		return t
	if not has_ffmpeg():
		return ""
	DirAccess.make_dir_recursive_absolute(thumbs_dir())
	var dur := float((_index.get(file, {}) as Dictionary).get("duration", 0.0)) if _index.get(file) is Dictionary else 0.0
	var r := await YouTube.exec(ffmpeg_path(), L.thumb_args(file, t, minf(1.0, dur * 0.5) if dur > 0.0 else 1.0), 30.0)
	var d := L.parse_duration(str(r.get("error", "")) + str(r.get("text", "")))
	if d > 0.0:
		var ix: Dictionary = _index.get(file, {}) if _index.get(file) is Dictionary else {}
		ix["duration"] = snappedf(d, 0.01)
		_index[file] = ix
		_save_index()
	return t if FileAccess.file_exists(t) else ""


## Läufe von thumb, die gerade unterwegs sind (siehe dort).
var _thumb_offen := 0


## Vorschaubild im Hintergrund (eins nach dem anderen); cb(pfad) – "" wenn es keins gibt.
func thumb(file: String, cb: Callable) -> void:
	_thumb_offen += 1
	await _thumb_lauf(file, cb)
	_thumb_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und thumb täte bis zum Neustart nichts mehr.
	if _thumb_offen == 0 and _thumb_running:
		_thumb_running = false


func _thumb_lauf(file: String, cb: Callable) -> void:
	var t := thumb_path(file)
	if FileAccess.file_exists(t):
		cb.call(t)
		return
	_thumb_queue.append([file, cb])
	if _thumb_running:
		return
	_thumb_running = true
	while not _thumb_queue.is_empty():
		var job: Array = _thumb_queue.pop_front()
		var got := await thumb_now(str(job[0]))
		var c: Callable = job[1]
		if c.is_valid():
			c.call(got)
	_thumb_running = false


func duration_of(file: String) -> float:
	return float((_index.get(file, {}) as Dictionary).get("duration", 0.0)) if _index.get(file) is Dictionary else 0.0


func _save_index() -> void:
	# Nur Einträge zu Dateien, die es noch gibt – nachgesehen höchstens alle INDEX_PRUEF_MS. Vorher lief das bei jedem
	# Aufruf über alle Aufnahmen, also beim ersten Öffnen der Galerie einmal je Vorschaubild (bei 300 Aufnahmen
	# 90.000 Blicke auf die Platte). Was Uzai selbst löscht oder verschiebt, nimmt es ohnehin gleich heraus.
	if Time.get_ticks_msec() - _index_geprueft_ms > INDEX_PRUEF_MS:
		_index_geprueft_ms = Time.get_ticks_msec()
		for k in _index.keys():
			if not FileAccess.file_exists(str(k)):
				_index.erase(k)
	Config.write_json(Config.path("captures.json"), _index)
	_items_ms = -100000


## Eine Aufnahme von Uzai: Clip oder Bildschirmfoto direkt im Clip- bzw. Bilder-Ordner, selbst
## keine Verknüpfung. Nur solche Dateien löscht Rückgängig am Ende (src/core/undo.gd).
func is_own_file(file: String) -> bool:
	var p := file.replace("\\", "/").simplify_path()
	var name := p.get_file()
	if name == "" or name.begins_with(".") or L.kind_of(name) == "":
		return false
	for d in [clips_dir(), shots_dir()]:
		var dir := str(d).replace("\\", "/").simplify_path()
		if p == dir.path_join(name):
			var da := DirAccess.open(dir)
			return da != null and not da.is_link(name) and FileAccess.file_exists(p)
	return false


## In den Papierkorb (nicht endgültig löschen). Geht der Papierkorb nicht (Laufwerk ohne Papierkorb, Datei offen),
## bleibt die Datei: Früher wurde sie dann endgültig gelöscht, und die Meldung sagte trotzdem „In den Papierkorb gelegt“.
func remove(file: String) -> bool:
	var ok := OS.move_to_trash(ProjectSettings.globalize_path(file)) == OK
	if ok:
		var t := thumb_path(file)
		if t != file and FileAccess.file_exists(t):
			DirAccess.remove_absolute(t)
		_index.erase(file)
		_save_index()
		changed.emit("files")
	return ok


## Neuer Titel, Zeitpunkt bleibt. Gibt den neuen Pfad zurück ("" bei Fehler).
func rename(file: String, title: String) -> String:
	var dir := file.get_base_dir()
	var name := L.unique_name(Array(DirAccess.get_files_at(dir)), L.renamed(file.get_file(), title))
	var dst := dir.path_join(name)
	if DirAccess.rename_absolute(file, dst) != OK:
		return ""
	if _index.has(file):
		_index[dst] = _index[file]
		_index.erase(file)
		_save_index()
	changed.emit("files")
	return dst


# --- Bearbeiten (src/core/clip_edit.gd, Ebene capture_edit.gd) ---------------------------------

## Laufendes Bearbeiten: { file, frac, cancel, why } – leer, wenn nichts läuft. Die Ebene darf
## zugehen; die Arbeit läuft weiter und meldet sich am Ende mit einer Mitteilung.
var edit_job := {}


## Was im Clip steckt: { duration, audio }. Fragt FFmpeg einmal und merkt es sich.
func probe(file: String) -> Dictionary:
	var ix: Dictionary = _index.get(file, {}) if _index.get(file) is Dictionary else {}
	if ix.has("audio") and float(ix.get("duration", 0.0)) > 0.0:
		return { "duration": float(ix.duration), "audio": bool(ix.audio) }
	if not has_ffmpeg():
		return { "duration": duration_of(file), "audio": true }
	var r := await YouTube.exec(ffmpeg_path(), E.probe_args(file), 20.0)
	var info := E.probe_info(str(r.get("error", "")) + str(r.get("text", "")))
	if float(info.duration) > 0.0:
		ix["duration"] = snappedf(float(info.duration), 0.01)
	ix["audio"] = bool(info.audio)
	_index[file] = ix
	_save_index()
	return { "duration": float(ix.get("duration", 0.0)), "audio": bool(info.audio) }


## Bildstreifen für die Zeitleiste (zwischengespeichert); "" ohne FFmpeg oder bei Fehlern.
func strip(file: String) -> String:
	var dst := thumbs_dir().path_join("strip_%s.jpg" % ("%s|%d" % [file, FileAccess.get_modified_time(file)]).md5_text())
	if FileAccess.file_exists(dst):
		return dst
	if not has_ffmpeg():
		return ""
	DirAccess.make_dir_recursive_absolute(thumbs_dir())
	var info := await probe(file)
	var r := await YouTube.exec(ffmpeg_path(), E.strip_args(file, dst, float(info.duration)), 60.0)
	return dst if bool(r.get("ok", false)) and FileAccess.file_exists(dst) else ""


## Text und Schrift für drawtext: in Uzais Datenordner, nie im Filtergraphen (clip_edit.gd).
func _edit_files(p: Dictionary) -> Dictionary:
	var dir := Config.path("cache/clipedit")
	DirAccess.make_dir_recursive_absolute(dir)
	var o := {}
	for k in ["top", "bottom"]:
		var t := E.clean_text(str(p.get(k, "")))
		if t == "":
			continue
		var f := dir.path_join(k + ".txt")
		var fa := FileAccess.open(f, FileAccess.WRITE)
		if fa == null:
			continue
		fa.store_string(t)
		fa.close()
		var font := _font_file(E.font_key(t))
		if font == "":
			continue
		o[k + "_file"] = f
		o[k + "_font"] = font
	return o


## Uzais Schrift als Datei für FFmpeg (im Programm steckt sie nur als Ressource).
func _font_file(key: String) -> String:
	var src := str(E.FONTS.get(key, ""))
	var dst := Config.path("cache/clipedit").path_join(src.get_file())
	if FileAccess.file_exists(dst):
		return dst
	var ff := load(src) as FontFile
	if ff == null or ff.data.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var fa := FileAccess.open(dst, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_buffer(ff.data)
	fa.close()
	return dst


## Bearbeiten und als neue Datei neben dem Original speichern (das bleibt). Nur Clips direkt im
## Clip-Ordner (is_own_file), nie während eines Spiels; startet eins, wird abgebrochen. Meldet
## sich am Ende selbst (mit „Teilen“). Gibt den neuen Pfad zurück, "" bei Fehler oder Abbruch.
func edit_clip(file: String, p: Dictionary) -> String:
	if not edit_job.is_empty() or L.kind_of(file) != "clip" or not is_own_file(file) or not has_ffmpeg():
		return ""
	if Launcher.in_game:
		Toasts.show_toast("Erst das Spiel beenden", "Bearbeiten braucht Grafikkarte und Prozessor – das macht Uzai nicht neben einem Spiel.", "video")
		return ""
	var info := await probe(file)
	var q := E.clamp_plan(p, float(info.duration) if float(info.duration) > 0.0 else float(p.b))
	var cut := E.only_cut(q)
	var dir := file.get_base_dir()
	var dst := dir.path_join(E.edited_name(Array(DirAccess.get_files_at(dir)), file, cut))
	var enc := str(L.attempt_parts(str(Config.get_value("capture.working", "dda|x264|cpu"))).enc)
	var kbps := L.bitrate_kbps(L.fit_size(screen_size(), str(opt("quality"))), fps())
	var o := _edit_files(q)
	o["audio"] = bool(info.audio)
	edit_job = { "file": file, "frac": 0.0, "cancel": false, "why": "" }
	var total := E.out_length(q)
	var args := E.cut_args(file, dst, q, enc, kbps) if cut else E.export_args(file, dst, q, o, enc, kbps)
	var r := await ffmpeg_job(args, total, edit_job)
	if not bool(r.ok) and not bool(r.cancelled) and enc != "x264":
		DirAccess.remove_absolute(dst)
		args = E.cut_args(file, dst, q, "x264", kbps) if cut else E.export_args(file, dst, q, o, "x264", kbps)
		r = await ffmpeg_job(args, total, edit_job)
	var why := str(edit_job.get("why", ""))
	edit_job = {}
	if not bool(r.ok) or not FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
		if bool(r.cancelled):
			Toasts.show_toast("Bearbeiten abgebrochen", "Ein Spiel startet – später noch einmal." if why == "spiel" else "Der Clip bleibt, wie er war.", "video",
					{ "quiet": why != "spiel" })
		else:
			Helper.hlog("Aufnahme: Bearbeiten ging nicht: " + str(r.get("error", "")).left(400))
			Toasts.show_toast("Bearbeiten ging nicht", "Der Clip bleibt, wie er war. Gleich noch einmal versuchen.", "warning")
		edit_done.emit("")
		return ""
	var old: Dictionary = _index.get(file, {}) if _index.get(file) is Dictionary else {}
	_index[dst] = { "duration": snappedf(total, 0.01), "game_id": str(old.get("game_id", "")), "audio": not bool(q.mute) and bool(info.audio) }
	_save_index()
	changed.emit("files")
	edit_done.emit(dst)
	var thumb := await thumb_now(dst)
	var share := func() -> void:
		var m: Node = get_tree().current_scene
		if m:
			load("res://src/ui/layers/captures.gd").open_share(m, dst)
	Toasts.show_toast("Gekürzt gespeichert" if cut else "Bearbeitet gespeichert", "%s  ·  %s" % [str(L.parse_name(dst).title), L.mmss(total)], "check",
		{ "image": thumb, "sound": "select", "go": share, "go_text": "Teilen" })
	return dst


## Vorschau zum Abspielen in Uzai (klein, Theora in Ogg) in cache/clipedit; "" bei Fehler.
## job wie edit_job (eigenes Wörterbuch der Ebene, cancel bricht ab).
func edit_preview(file: String, p: Dictionary, job: Dictionary) -> String:
	if not has_ffmpeg() or not is_own_file(file):
		return ""
	var info := await probe(file)
	var q := E.clamp_plan(p, float(info.duration) if float(info.duration) > 0.0 else float(p.b))
	var o := _edit_files(q)
	o["audio"] = bool(info.audio)
	_preview_n = (_preview_n + 1) % 2
	var dst := Config.path("cache/clipedit/vorschau_%d.ogv" % _preview_n)
	var r := await ffmpeg_job(E.preview_args(file, dst, q, o), E.out_length(q), job)
	return dst if bool(r.ok) and FileAccess.file_exists(dst) else ""


var _preview_n := 0


## FFmpeg mit Fortschritt (-progress pipe:1 in den Argumenten): job.frac läuft von 0 bis 1,
## job.cancel = true bricht ab, ein Spielstart auch (job.why = "spiel"). { ok, cancelled, error }
func ffmpeg_job(args: PackedStringArray, total_s: float, job: Dictionary, timeout := 1800.0) -> Dictionary:
	var box := { "done": false, "err": "", "code": -1, "frac": 0.0, "cancel": false, "killed": false, "mx": Mutex.new() }
	var t := Thread.new()
	t.start(_job_worker.bind(ffmpeg_path(), args, total_s, timeout, box))
	var fertig := false
	while not fertig:
		await get_tree().process_frame
		if Launcher.in_game and not bool(job.get("cancel", false)):
			job["cancel"] = true
			job["why"] = "spiel"
		# Der Faden schreibt in box: gelesen wird nur unter seiner Sperre (auch „fertig“).
		box.mx.lock()
		job["frac"] = float(box.frac)
		box.cancel = bool(job.get("cancel", false))
		fertig = bool(box.done)
		box.mx.unlock()
	t.wait_to_finish()
	job["frac"] = 1.0 if int(box.code) == 0 else float(job.get("frac", 0.0))
	return { "ok": int(box.code) == 0 and not bool(box.killed), "cancelled": bool(box.killed), "error": str(box.err) }


func _job_worker(exe: String, args: PackedStringArray, total_s: float, timeout: float, box: Dictionary) -> void:
	var info := OS.execute_with_pipe(exe, Helper.win_args(args), false)
	if info.is_empty():
		box.mx.lock()
		box.err = "startet nicht"
		box.done = true
		box.mx.unlock()
		return
	var io: FileAccess = info.get("stdio")
	var er: FileAccess = info.get("stderr")
	var pid := int(info.get("pid", 0))
	var t0 := Time.get_ticks_msec()
	var tail := ""
	var err := PackedByteArray()
	while true:
		var a := io.get_buffer(65536)
		var b := er.get_buffer(65536) if er else PackedByteArray()
		if not a.is_empty():
			tail = (tail + a.get_string_from_utf8()).right(4096)
			var done_s := E.parse_out_time(tail)
			if done_s >= 0.0:
				box.mx.lock()
				box.frac = clampf(done_s / maxf(0.1, total_s), 0.0, 1.0)
				box.mx.unlock()
		if not b.is_empty() and err.size() < 65536:
			err.append_array(b)
		box.mx.lock()
		var stop := bool(box.cancel)
		box.mx.unlock()
		if stop or Time.get_ticks_msec() - t0 > timeout * 1000.0:
			OS.kill(pid)
			box.mx.lock()
			box.killed = true
			box.mx.unlock()
			break
		if a.is_empty() and b.is_empty():
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(30)
	var code := -1 if bool(box.killed) else OS.get_process_exit_code(pid)
	box.mx.lock()
	box.err = err.get_string_from_utf8()
	box.code = code
	box.done = true
	box.mx.unlock()


## Für Discord: passt der Clip nicht unter das Limit, eine kleinere Fassung (Cache) bauen.
func discord_version(file: String) -> String:
	var limit := int(str(opt("discord_mb"))) if str(opt("discord_mb")).is_valid_int() else 10
	if L.kind_of(file) != "clip" or not L.needs_shrink(_file_size(file), limit):
		return file
	if not has_ffmpeg():
		return ""
	var dur := duration_of(file)
	if dur <= 0.0:
		await thumb_now(file)
		dur = duration_of(file)
	var dst := Config.path("cache/captures/discord").path_join(file.get_file())
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(file):
		return dst
	var enc := str(L.attempt_parts(str(Config.get_value("capture.working", "dda|x264|cpu"))).enc)
	var r := await YouTube.exec(ffmpeg_path(), L.shrink_args(file, dst, maxf(1.0, dur), limit, enc), 600.0)
	if (not bool(r.get("ok", false)) or not FileAccess.file_exists(dst)) and enc != "x264":
		r = await YouTube.exec(ffmpeg_path(), L.shrink_args(file, dst, maxf(1.0, dur), limit, "x264"), 900.0)
	return dst if bool(r.get("ok", false)) and FileAccess.file_exists(dst) else ""


# --- Ans Handy (Remote.gd liefert aus) ---------------------------------------------------------

var _shares := {}                 ## token -> { files: [pfade], until: Unix-Zeit }
var _sends: Array = []            ## laufende Downloads { peer, file, pos, end, last }


## Link fürs Handy (Heimnetz, 30 Minuten gültig); "" ohne Netz.
func share_link(files: Array) -> String:
	var token := Remote.secure_token()
	_shares[token] = { "files": files.duplicate(), "until": Time.get_unix_time_from_system() + 1800.0 }
	return Remote.share_begin(token)


func share_active() -> bool:
	var now := Time.get_unix_time_from_system()
	for k in _shares.keys():
		if float(_shares[k].until) < now:
			_shares.erase(k)
	return not _shares.is_empty()


## Anfrage /c/<token>[/<n>] vom Handy. headers: Kopfzeilen in Kleinbuchstaben.
func serve(peer: StreamPeerTCP, path: String, headers: Dictionary) -> void:
	var parts := path.split("?")[0].trim_prefix("/c/").split("/")
	var token := parts[0] if parts.size() > 0 else ""
	share_active()
	var sh: Dictionary = _shares.get(token, {})
	if sh.is_empty():
		_reply(peer, "404 Not Found", "text/html; charset=utf-8", "<p>Abgelaufen – in Uzai neu teilen.</p>".to_utf8_buffer())
		return
	var files: Array = sh.files
	if parts.size() < 2 or not parts[1].is_valid_int():
		var items: Array = []
		for i in files.size():
			var f := str(files[i])
			items.append({ "name": f.get_file(), "url": "/c/%s/%d" % [token, i], "kind": L.kind_of(f), "size": _file_size(f) })
		_reply(peer, "200 OK", "text/html; charset=utf-8", L.share_page(items).to_utf8_buffer())
		return
	var idx := int(parts[1])
	if idx < 0 or idx >= files.size() or not FileAccess.file_exists(str(files[idx])):
		_reply(peer, "404 Not Found", "text/plain", "weg".to_utf8_buffer())
		return
	var file := str(files[idx])
	var size := _file_size(file)
	var rg := L.parse_range(str(headers.get("range", "")), size)
	if rg.size() == 1:
		peer.put_data(("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */%d\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % size).to_utf8_buffer())
		peer.disconnect_from_host()
		return
	var a := 0 if rg.is_empty() else int(rg[0])
	var b := size - 1 if rg.is_empty() else int(rg[1])
	var head := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccept-Ranges: bytes\r\nCache-Control: no-store\r\n%sConnection: close\r\n" % [
		"200 OK" if rg.is_empty() else "206 Partial Content", L.mime_for(file), b - a + 1, Remote.SECURE_HEADERS]
	if not rg.is_empty():
		head += "Content-Range: bytes %d-%d/%d\r\n" % [a, b, size]
	if path.contains("dl=1"):
		head += "Content-Disposition: attachment; filename=\"%s\"\r\n" % file.get_file().replace("\"", "")
	peer.put_data((head + "\r\n").to_utf8_buffer())
	_sends.append(
			{ "peer": peer, "file": FileAccess.open(file, FileAccess.READ), "pos": a, "end": b + 1, "last": Time.get_ticks_msec(), "buf": PackedByteArray() })


func _reply(peer: StreamPeerTCP, status: String, ctype: String, body: PackedByteArray) -> void:
	peer.put_data(
			("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n%sConnection: close\r\n\r\n" % [status, ctype, body.size(),
			Remote.SECURE_HEADERS]).to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


## Große Dateien stückweise und ohne Warten senden (put_partial_data), damit Uzai flüssig bleibt –
## auch im Spiel, wo es nur wenige Bilder pro Sekunde zeichnet.
func _pump_sends() -> void:
	for s in _sends.duplicate():
		var peer: StreamPeerTCP = s.peer
		var f: FileAccess = s.file
		peer.poll()
		var done := f == null or int(s.pos) >= int(s.end) or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
		var budget := 8 << 20
		while not done and budget > 0:
			if (s.buf as PackedByteArray).is_empty():
				f.seek(int(s.pos))
				s.buf = f.get_buffer(mini(256 * 1024, int(s.end) - int(s.pos)))
				if (s.buf as PackedByteArray).is_empty():
					done = true
					break
			var res: Array = peer.put_partial_data(s.buf)
			var sent := int(res[1]) if res.size() > 1 else 0
			if int(res[0]) != OK:
				done = true
				break
			if sent <= 0:
				break
			s.last = Time.get_ticks_msec()
			s.pos = int(s.pos) + sent
			budget -= sent
			s.buf = (s.buf as PackedByteArray).slice(sent)
			if int(s.pos) >= int(s.end):
				done = true
		if Time.get_ticks_msec() - int(s.last) > 60000:
			done = true
		if done:
			if f:
				f.close()
			peer.disconnect_from_host()
			_sends.erase(s)


func _physics_process(_dt: float) -> void:
	if not _sends.is_empty():
		_pump_sends()

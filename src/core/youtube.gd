extends Node
## YouTube in Uzai, ohne Werbung. Abos, neue Videos, Suche, Verlauf und Merkliste liegen
## in Uzai selbst. Neue Videos kommen über die RSS-Feeds der Kanäle, Suche und Kanalseiten
## über yt-dlp. Mit Google-Anmeldung (QR-Code am Fernseher) kommen deine Abos, Playlists,
## „Mag ich“ und die Trends dazu. Abgespielt wird über mpv (siehe Video).

const Arbeit := preload("res://src/core/arbeit.gd")
const Lang := preload("res://src/core/lang.gd")

signal changed(what: String)            # subs, feed, history, later, account, tools, lists
signal tools_progress(text: String, frac: float)

const RSS := "https://www.youtube.com/feeds/videos.xml?"
const SB_API := "https://sponsor.ajay.app/api/skipSegments/%s?categories=%s"
const DEVICE_URL := "https://oauth2.googleapis.com/device/code"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const API := "https://www.googleapis.com/youtube/v3/"
const SCOPE := "https://www.googleapis.com/auth/youtube.readonly"
const YTDLP_URL := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
const YTDLP_SUMS := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"
const DENO_URL := "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
const DENO_SUM := DENO_URL + ".sha256sum"
const MPV_RELEASES := "https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest"
## 7-Zip (nur .7z, eine Datei) vom offiziellen Repository: Das tar.exe von Windows 10 entpackt
## mpvs .7z nicht (ohne LZMA) – erst Windows 11 kann das. Geprüft über GitHubs SHA-256 (Punkt 74).
const SEVENZ_RELEASES := "https://api.github.com/repos/ip7z/7zip/releases/latest"
const PlayerLog := preload("res://src/core/player_log.gd")
const Fremd := preload("res://src/core/fremd.gd")

const SB_CATEGORIES := [
	["sponsor", "Sponsoren"], ["selfpromo", "Eigenwerbung"], ["interaction", "Abo-Erinnerungen"],
	["intro", "Intros"], ["outro", "Abspann"], ["preview", "Vorschauen"], ["music_offtopic", "Musik: Nicht-Musik-Teile"],
]

var data := { "subs": [], "history": [], "later": [], "searches": [], "help": [] }   ## help: Lösungshilfe (walkthrough.gd)
var feed: Array = []
var feed_loading := false
var feed_at := 0
var _feed_again := false
var shorts: Array = []                   ## Shorts der Abos (Reiter „Shorts“, erst beim Öffnen geholt)
var shorts_loading := false
var shorts_at := 0
var trending: Array = []
var recs: Array = []                     ## „Für dich“
var recs_source := ""                    ## youtube (echte Empfehlungen) oder mix (eigene Mischung)
var recs_loading := false
var recs_at := 0
var recs_error := ""
var playlists: Array = []
var liked: Array = []
var channels := {}                      ## Kanal-ID → { avatar, banner, followers } (aus yt-dlp)
var account := ""
var error := ""
var demo := false
var setting_up := false
var _access := ""
var _access_until := 0.0
var _refreshing := false
var _save_timer: Timer
## Startseite wie auf dem Fernseher (inoffiziell, auf Wunsch): siehe youtube_tv.gd.
var tv: Node
signal _token_ready


func _ready() -> void:
	tv = preload("res://src/core/youtube_tv.gd").new()
	tv.name = "TV"
	add_child(tv)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.0
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	if "--demo" in OS.get_cmdline_user_args():
		_load_demo()
		return
	Config.changed.connect(func(k: String) -> void:
		if k in ["youtube.cookies", "youtube.cookies_file"]:
			refresh_recs(true)
	)
	var saved: Variant = Config.read_json(Config.path("youtube.json"), {})
	if saved is Dictionary:
		for k in data.keys():
			if saved.get(k) is Array:
				# Suchen sind Texte, alles andere Einträge (Wörterbücher); Fremdes fällt raus.
				var want_text: bool = k == "searches"
				data[k] = (saved[k] as Array).filter(func(e: Variant) -> bool: return e is String if want_text else e is Dictionary)
	var cached: Variant = Config.read_json(Config.path("cache/youtube-feed.json"), {})
	if cached is Dictionary and cached.get("feed") is Array:
		feed = cached.feed
		feed_at = int(cached.get("at", 0))
	# Shorts aus dem Zwischenspeicher: gleich da, wenn der Reiter aufgeht (frisch geholt wird dann).
	var cs: Variant = Config.read_json(Config.path("cache/youtube-shorts.json"), {})
	if cs is Dictionary and cs.get("shorts") is Array:
		shorts = (cs.shorts as Array).filter(func(e: Variant) -> bool: return e is Dictionary and valid_id(str(e.get("id", ""))))
	account = str(Config.get_value("youtube.account", ""))
	var rc: Variant = Config.read_json(Config.path("cache/youtube-recs.json"), {})
	if rc is Dictionary and rc.get("recs") is Array:
		recs = rc.recs
		recs_at = int(rc.get("at", 0))
		recs_source = str(rc.get("source", ""))
	var chs: Variant = Config.read_json(Config.path("cache/youtube-channels.json"), {})
	if chs is Dictionary:
		channels = chs


func _load_demo() -> void:
	demo = true
	var d: Variant = Config.read_json("res://tests/demo_youtube.json", {})
	if d is Dictionary:
		for k in data.keys():
			data[k] = d.get(k, [])
		feed = d.get("feed", [])
		shorts = d.get("shorts", [])
		trending = d.get("trending", [])
		playlists = d.get("playlists", [])
		account = str(d.get("account", ""))
	# Alter in den Demodaten ist relativ zu jetzt angegeben.
	var now := int(Time.get_unix_time_from_system())
	for list in [feed, shorts, trending, data.later, data.history]:
		for v in list:
			if v.has("age"):
				v["published"] = now - int(v.age)
			if v.has("at_age"):
				v["at"] = now - int(v.at_age)
			if str(v.get("thumb", "")) == "":
				v["thumb"] = thumb_for(str(v.id))
	feed_at = now
	recs = rank_mix(feed + trending, data.history, data.later, data.subs, now, 1)
	recs_source = "mix"
	recs_at = now


## Beim Start: Feed auffrischen, Google-Abos abgleichen, yt-dlp aktuell halten.
func start() -> void:
	tv.start()
	if demo:
		return
	if logged_in():
		await import_subscriptions()
		load_trending()
	refresh_feed()
	refresh_recs()
	_maybe_update_ytdlp()


func save() -> void:
	if demo:
		return
	Config.write_json(Config.path("youtube.json"), data)


func _dirty() -> void:
	_save_timer.start()


# --- Werkzeuge: yt-dlp, Deno, mpv ---------------------------------------------------------

func tools_dir() -> String:
	return Config.path("tools")


func ytdlp_path() -> String:
	var own := str(Config.get_value("youtube.ytdlp", ""))
	if own != "" and FileAccess.file_exists(own):
		return own
	return tools_dir().path_join("yt-dlp.exe")


func deno_path() -> String:
	return tools_dir().path_join("deno.exe")


func mpv_path() -> String:
	var own := str(Config.get_value("youtube.mpv", ""))
	if own != "" and FileAccess.file_exists(own):
		return own
	var cands := [tools_dir().path_join("mpv/mpv.exe")]
	var env := OS.get_environment("ProgramFiles")
	if env != "":
		cands.append(env.path_join("mpv/mpv.exe"))
	var home := OS.get_environment("USERPROFILE")
	if home != "":
		cands.append(home.path_join("scoop/apps/mpv/current/mpv.exe"))
	var local := OS.get_environment("LOCALAPPDATA")
	if local != "":
		cands.append(local.path_join("Programs/mpv/mpv.exe"))
	for c in cands:
		if FileAccess.file_exists(c):
			return c
	return cands[0]


func has_ytdlp() -> bool:
	return FileAccess.file_exists(ytdlp_path())


func has_mpv() -> bool:
	return FileAccess.file_exists(mpv_path())


func has_deno() -> bool:
	return FileAccess.file_exists(deno_path())


func tools_ready() -> bool:
	return demo or (has_ytdlp() and has_mpv())


## Lädt fehlende Werkzeuge herunter. Gibt "" zurück oder eine Fehlermeldung.
func setup_tools() -> String:
	if setting_up:
		return "Läuft schon."
	if not Config.is_windows():
		return "Das Einrichten geht nur unter Windows."
	setting_up = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird „läuft“ hier trotzdem gelöst (sonst hieße es bis
	# zum Neustart „Läuft schon.“), und ein leeres Ergebnis ohne Werkzeuge gilt nicht als gelungen.
	var err: String = await _werkzeuge_holen()
	if err == "" and not (has_ytdlp() and has_mpv()):
		err = "Das Einrichten brach ab. Bitte noch einmal versuchen."
	setting_up = false
	tools_progress.emit("Fertig" if err == "" else err, 1.0)
	changed.emit("tools")
	return err


func _werkzeuge_holen() -> String:
	var err := ""
	var t0 := Time.get_ticks_msec()
	PlayerLog.zeile("Einrichten: yt-dlp %s, Deno %s, mpv %s (Ordner %s)" % [_da(has_ytdlp()), _da(has_deno()), _da(has_mpv()), tools_dir()])
	DirAccess.make_dir_recursive_absolute(tools_dir())
	# Jedes Programm nur mit passender Prüfsumme des Herausgebers (Punkt 74).
	if not has_ytdlp():
		tools_progress.emit("yt-dlp wird geladen …", 0.0)
		var sums := await Net.get_text(YTDLP_SUMS)
		var sha := Net.sha_for(sums, "yt-dlp.exe")
		PlayerLog.zeile("yt-dlp: Prüfsummen %s" % ("da" if sha != "" else "fehlen (%d Zeichen)" % sums.length()))
		var why := await Net.download_verified(YTDLP_URL, tools_dir().path_join("yt-dlp.exe"), sha, _progress.bind("yt-dlp"))
		PlayerLog.zeile("yt-dlp: " + ("geladen und geprüft" if why == "" else why))
		if why == "":
			why = await _still_there(ytdlp_path(), "yt-dlp")
		if why != "":
			err = "yt-dlp ließ sich nicht laden. " + why
	if err == "" and not has_deno():
		tools_progress.emit("Deno wird geladen …", 0.0)
		var zip := tools_dir().path_join("deno.zip")
		if await Net.download_verified(DENO_URL, zip, Net.first_sha(await Net.get_text(DENO_SUM)), _progress.bind("Deno")) == "":
			var z := ZIPReader.new()
			if z.open(zip) == OK:
				var bytes := z.read_file("deno.exe")
				z.close()
				var f := FileAccess.open(deno_path(), FileAccess.WRITE)
				if f and bytes.size() > 0:
					f.store_buffer(bytes)
					f.close()
			DirAccess.remove_absolute(zip)
		PlayerLog.zeile("Deno: " + ("bereit" if has_deno() else "fehlt (Laden oder Entpacken ging nicht)"))
		if not has_deno():
			err = "Deno fehlt. Videos teils nur in niedriger Qualität."
	if not has_mpv():
		var e2 := await _setup_mpv()
		if e2 != "":
			err = e2
	PlayerLog.zeile("Einrichten fertig nach %d s: %s" % [int((Time.get_ticks_msec() - t0) / 1000.0), "ok" if err == "" else err])
	return err


## tar.exe von Windows mit vollem Pfad (System32); "" wenn es das dort nicht gibt. Nur mit dem Namen gestartet, nähme
## Windows ein gleichnamiges Programm aus Uzais Ordner oder dem Arbeitsordner zuerst – und das liefe dann mit dem
## frisch geladenen Paket als Eingabe.
static func windows_tar() -> String:
	var root := OS.get_environment("SystemRoot")
	if root == "":
		root = OS.get_environment("WINDIR")
	var p := root.path_join("System32/tar.exe") if root != "" else ""
	return p if p != "" and FileAccess.file_exists(p) else ""


func _progress(got: int, total: int, what: String) -> void:
	var frac := float(got) / float(total) if total > 0 else 0.0
	tools_progress.emit("%s wird geladen … %d MB" % [what, got / 1048576], frac)


func _setup_mpv() -> String:
	tools_progress.emit("mpv wird gesucht …", 0.0)
	var r := await Net.get_json(MPV_RELEASES)
	if not r.ok or not (r.data is Dictionary):
		PlayerLog.zeile("mpv: Liste der Versionen fehlt (HTTP %d)" % int(r.code))
		return "mpv ließ sich nicht finden. Bitte von mpv.io laden und unter Einstellungen → Videos den Pfad wählen."
	var pick := release_asset(r.data, "^mpv-x86_64-[0-9]{8}-git-[0-9a-f]+\\.7z$")
	var url := str(pick.get("url", ""))
	var sha := str(pick.get("sha", ""))
	PlayerLog.zeile("mpv: Paket %s, Prüfsumme %s" % [str(pick.get("name", "keins")), "da" if sha != "" else "fehlt"])
	if url == "":
		return "Keine passende mpv-Version gefunden. Bitte von mpv.io laden und unter Einstellungen → Videos den Pfad wählen."
	var archive := tools_dir().path_join("mpv.7z")
	var why := await Net.download_verified(url, archive, sha, _progress.bind("mpv"))
	PlayerLog.zeile("mpv: " + ("geladen und geprüft" if why == "" else why))
	if why != "":
		return "mpv ließ sich nicht laden. %s Sonst von mpv.io laden und unter Einstellungen → Videos den Pfad wählen." % why
	tools_progress.emit("mpv wird entpackt …", 1.0)
	var dest := tools_dir().path_join("mpv")
	DirAccess.make_dir_recursive_absolute(dest)
	var tar := windows_tar()
	var res: Dictionary = { "error": "tar.exe fehlt in Windows" }
	if tar != "":
		res = await exec(tar, PackedStringArray(["-xf", archive.replace("/", "\\"), "-C", dest.replace("/", "\\")]), 180.0)
	var tar_err := str(res.get("error", "")).strip_edges().left(160)
	PlayerLog.zeile("mpv: Entpacken mit tar.exe %s" % ("ok" if FileAccess.file_exists(dest.path_join("mpv.exe")) else "ging nicht: " + tar_err))
	if not FileAccess.file_exists(dest.path_join("mpv.exe")):
		# Windows 10: tar.exe kennt kein LZMA. Dann mit 7-Zip (7zr.exe, geprüft).
		var e7 := await _unpack_7z(archive, dest)
		PlayerLog.zeile("mpv: Entpacken mit 7-Zip " + ("ok" if e7 == "" else "ging nicht: " + e7))
	DirAccess.remove_absolute(archive)
	if not FileAccess.file_exists(dest.path_join("mpv.exe")):
		return "mpv ließ sich nicht entpacken (%s). Bitte von mpv.io laden und den Pfad wählen." % tar_err.left(80)
	return await _still_there(dest.path_join("mpv.exe"), "mpv")


## Paket aus einer GitHub-Release-Antwort: { name, url, sha } (sha laut GitHub, "" wenn keine) oder {}.
static func release_asset(release: Dictionary, pattern: String) -> Dictionary:
	var re := RegEx.create_from_string(pattern)
	for a in release.get("assets", []):
		if a is Dictionary and re.search(str(a.get("name", ""))):
			var u := str(a.get("browser_download_url", ""))
			if not u.begins_with("https://github.com/"):
				continue
			return { "name": str(a.name), "url": u, "sha": Net.github_digest(a) }
	return {}


## .7z mit 7zr.exe entpacken; 7zr kommt geprüft von GitHub (ip7z/7zip). "" = ok, sonst der Grund.
func _unpack_7z(archive: String, dest: String) -> String:
	var exe := tools_dir().path_join("7zr.exe")
	if not FileAccess.file_exists(exe):
		tools_progress.emit("7-Zip wird geladen …", 0.0)
		var r := await Net.get_json(SEVENZ_RELEASES)
		var pick := release_asset(r.data, "^7zr\\.exe$") if r.data is Dictionary else {}
		if pick.is_empty():
			PlayerLog.zeile("7-Zip: Liste der Versionen fehlt (HTTP %d)" % int(r.code))
			return "7-Zip nicht gefunden"
		var why := await Net.download_verified(str(pick.url), exe, str(pick.sha), _progress.bind("7-Zip"))
		if why != "":
			return why
	tools_progress.emit("mpv wird entpackt …", 1.0)
	var res := await exec(exe, PackedStringArray(["x", "-y", "-o" + dest.replace("/", "\\"), archive.replace("/", "\\")]), 180.0)
	if not FileAccess.file_exists(dest.path_join("mpv.exe")):
		var e := str(res.get("error", "")).strip_edges()
		return (e if e != "" else str(res.get("text", "")).strip_edges().right(160)).left(160)
	return ""


## Gleich nach dem Laden noch da? Ein Virenschutz nimmt .exe-Dateien manchmal sofort weg.
func _still_there(path: String, what: String) -> String:
	await get_tree().create_timer(1.5).timeout
	if FileAccess.file_exists(path):
		return ""
	PlayerLog.zeile("%s: Datei gleich nach dem Laden verschwunden – Virenschutz?" % what)
	return TranslationServer.translate("%s wurde nach dem Laden entfernt – wohl vom Virenschutz. Dort Uzais Ordner „tools“ zulassen.") % what


static func _da(on: bool) -> String:
	return "da" if on else "fehlt"


func _maybe_update_ytdlp() -> void:
	if not Config.is_windows() or not has_ytdlp():
		return
	var last := int(Config.get_value("youtube.updated", 0))
	if Time.get_unix_time_from_system() - last < 3 * 86400:
		return
	Config.set_value("youtube.updated", int(Time.get_unix_time_from_system()))
	await exec(ytdlp_path(), PackedStringArray(["-U"]), 120.0)


const EXEC_OUT_MAX := 64 * 1024 * 1024     ## so viel Ausgabe eines Programms höchstens sammeln
const EXEC_ERR_MAX := 4 * 1024 * 1024


## Programm im Hintergrund ausführen und die Ausgabe als UTF-8 lesen. stop["stop"] = true beendet
## es vorzeitig (Abbrechen in der Oberfläche).
func exec(exe: String, args: PackedStringArray, timeout := 60.0, stop: Dictionary = {}) -> Dictionary:
	var box := { "done": false, "out": PackedByteArray(), "err": PackedByteArray(), "code": -1, "stop": stop, "mx": Mutex.new() }
	var t := Thread.new()
	t.start(_exec_worker.bind(exe, args, timeout, box))
	var fertig := false
	while not fertig:
		await get_tree().process_frame
		# Der Faden schreibt in box: gelesen wird nur unter seiner Sperre.
		box.mx.lock()
		fertig = bool(box.done)
		box.mx.unlock()
	t.wait_to_finish()
	var out: PackedByteArray = box.out
	var er: PackedByteArray = box.err
	return { "ok": int(box.code) == 0, "text": out.get_string_from_utf8(), "error": er.get_string_from_utf8() }


func _exec_worker(exe: String, args: PackedStringArray, timeout: float, box: Dictionary) -> void:
	var info := OS.execute_with_pipe(exe, Helper.win_args(args), false)
	var io: FileAccess = info.get("stdio") if not info.is_empty() else null
	if io == null:
		box.mx.lock()
		box.err = "startet nicht".to_utf8_buffer()
		box.done = true
		box.mx.unlock()
		return
	var er: FileAccess = info.get("stderr")
	var pid := int(info.get("pid", 0))
	var t0 := Time.get_ticks_msec()
	var out := PackedByteArray()
	var err := PackedByteArray()
	while true:
		var a := io.get_buffer(65536)
		var b := er.get_buffer(65536) if er else PackedByteArray()
		# Begrenzt sammeln: Ein Programm, das ohne Ende schreibt, füllte sonst den Arbeitsspeicher.
		if out.size() < EXEC_OUT_MAX:
			out.append_array(a)
		if err.size() < EXEC_ERR_MAX:
			err.append_array(b)
		# Zeitgrenze und Abbruch bei jedem Durchgang prüfen – früher nur, wenn gerade nichts kam: Ein Programm, das
		# ununterbrochen schreibt, lief dann ohne Grenze weiter.
		if Time.get_ticks_msec() - t0 > timeout * 1000.0 or bool((box.stop as Dictionary).get("stop", false)):
			OS.kill(pid)
			break
		if a.is_empty() and b.is_empty():
			if not OS.is_process_running(pid):
				if out.size() < EXEC_OUT_MAX:
					out.append_array(io.get_buffer(1 << 22))
				break
			OS.delay_msec(15)
	var code := OS.get_process_exit_code(pid)
	box.mx.lock()
	box.out = out
	box.err = err
	box.code = code
	box.done = true
	box.mx.unlock()


func _ytdlp_args(extra: Array) -> PackedStringArray:
	var a := PackedStringArray(["--encoding", "utf-8", "--no-warnings", "--ignore-config", "--flat-playlist", "-J"])
	for e in extra:
		a.append(str(e))
	return a


# --- Videos aus verschiedenen Quellen --------------------------------------------------------

static func thumb_for(id: String, big := false) -> String:
	return "https://i.ytimg.com/vi/%s/%s.jpg" % [id, "hqdefault" if big else "mqdefault"]


static func _num(v: Variant) -> int:
	if v == null:
		return 0
	if v is String:
		return int(v) if (v as String).is_valid_int() else 0
	return int(v)


## Ein Eintrag aus `yt-dlp --flat-playlist -J`.
static func from_ytdlp(e: Dictionary) -> Dictionary:
	var vid := str(e.get("id", ""))
	if not valid_id(vid):
		return {}
	var url := str(e.get("url", ""))
	var ch: Variant = e.get("channel")
	if ch == null:
		ch = e.get("uploader")
	var cid := str(e.get("channel_id", "")) if e.get("channel_id") != null else ""
	# Die Suche mit dem Filter „Live“ (eine Adresse statt ytsearch) liefert vom Kanal nur Adressen: die Kennung aus
	# …/channel/UC…, als Name das @-Kürzel.
	if cid == "":
		cid = _adress_teil(e.get("channel_url"), "/channel/")
		if not kanal_ok(cid):
			cid = ""
	if ch == null or str(ch) == "":
		var h := _adress_teil(e.get("uploader_url"), "/@")
		ch = "@" + h if h != "" else null
	return {
		"id": vid,
		"title": str(e.get("title", "")),
		"channel": str(ch) if ch != null else "",
		"channel_id": cid,
		"duration": _num(e.get("duration")),
		"views": _num(e.get("view_count")),
		"thumb": thumb_for(vid),
		"short": url.contains("/shorts/"),
		"live": str(e.get("live_status", "")) == "is_live",
	}


## Das Stück einer Adresse nach `marke` bis zum nächsten / oder ? ("" ohne Marke oder wenn es zu lang ist).
static func _adress_teil(url: Variant, marke: String) -> String:
	if not (url is String):
		return ""
	var i := (url as String).find(marke)
	if i < 0:
		return ""
	var s := (url as String).substr(i + marke.length()).get_slice("?", 0).get_slice("/", 0).uri_decode()
	s = Fremd.sauber(s).strip_edges()
	return s if s.length() <= 100 else ""


## Antwort von yt-dlp (Suche oder Kanal) in eine Liste von Videos.
static func parse_ytdlp(text: String, hide_shorts := true) -> Array:
	var d: Variant = Fremd.json(text)
	var out: Array = []
	if not (d is Dictionary):
		return out
	var owner := str(d.get("channel", ""))
	var owner_id := str(d.get("channel_id", ""))
	for e in Fremd.zeilen(d.get("entries")):
		var v := from_ytdlp(e)
		if v.is_empty() or (hide_shorts and v.short):
			continue
		if v.channel == "" or v.channel == "<null>":
			v.channel = owner
		if v.channel_id == "":
			v.channel_id = owner_id
		out.append(v)
	return out


## RSS-Feed eines Kanals.
static func parse_rss(bytes: PackedByteArray) -> Array:
	var p := XMLParser.new()
	var out: Array = []
	if bytes.is_empty() or p.open_buffer(bytes) != OK:
		return out
	var cur := {}
	var in_entry := false
	var in_author := false
	var in_group := false
	var tag := ""
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				if n == "entry":
					in_entry = true
					cur = {}
				elif in_entry:
					tag = n
					match n:
						"author": in_author = true
						"media:group": in_group = true
						"media:thumbnail": cur["thumb"] = p.get_named_attribute_value_safe("url")
						"media:statistics": cur["views"] = int(p.get_named_attribute_value_safe("views"))
						"link":
							if p.get_named_attribute_value_safe("rel") == "alternate":
								cur["link"] = p.get_named_attribute_value_safe("href")
					if p.is_empty():
						tag = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not in_entry or tag == "":
					continue
				var t := Fremd.sauber(_unescape(p.get_node_data().strip_edges()))
				if t == "":
					continue
				match tag:
					"yt:videoId": cur["id"] = t
					"yt:channelId": cur["channel_id"] = t
					"title":
						if not in_group:
							cur["title"] = t
					"name":
						if in_author:
							cur["channel"] = t
					"published": cur["published"] = int(Time.get_unix_time_from_datetime_string(t.substr(0, 19)))
			XMLParser.NODE_ELEMENT_END:
				var n2 := p.get_node_name()
				if n2 == "entry":
					in_entry = false
					var vid := str(cur.get("id", ""))
					if valid_id(vid):
						out.append({
							"id": vid, "title": str(cur.get("title", "")), "channel": str(cur.get("channel", "")),
							"channel_id": str(cur.get("channel_id", "")), "duration": 0, "views": int(cur.get("views", 0)),
							"thumb": thumb_for(vid), "published": int(cur.get("published", 0)),
							"short": str(cur.get("link", "")).contains("/shorts/"), "live": false,
						})
				elif n2 == "author":
					in_author = false
				elif n2 == "media:group":
					in_group = false
				tag = ""
	return out


static var _ZEICHEN_NR := RegEx.create_from_string("&#(x?)([0-9a-fA-F]{1,8});")
static var _DAUER := RegEx.create_from_string("P(?:(\\d+)D)?T?(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?")


## Zeichen-Kürzel in Titeln aus dem Feed auflösen. Den Titel schreibt, wer das Video hochlädt: Nummern ergeben keine
## Steuerzeichen und keine umgedrehte Schreibrichtung (Fremd.zeichen).
static func _unescape(s: String) -> String:
	if not s.contains("&"):
		return s
	var out := s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&apos;", "'")
	for m in _ZEICHEN_NR.search_all(out):
		var code := m.get_string(2).hex_to_int() if m.get_string(1) == "x" else int(m.get_string(2))
		out = out.replace(m.get_string(0), Fremd.zeichen(code))
	return out.replace("&amp;", "&")


## "PT1H2M3S" → 3723
static func parse_iso_duration(s: String) -> int:
	var m := _DAUER.search(s)
	if m == null:
		return 0
	return int(m.get_string(1)) * 86400 + int(m.get_string(2)) * 3600 + int(m.get_string(3)) * 60 + int(m.get_string(4))


## Ein Video aus der YouTube-Data-API (videos, playlistItems).
static func from_api(it: Dictionary) -> Dictionary:
	var sn := Fremd.verz(it.get("snippet"))
	var cd := Fremd.verz(it.get("contentDetails"))
	var vid := ""
	if it.get("id") is String:
		vid = str(it.id)
	elif cd.has("videoId"):
		vid = str(cd.videoId)
	else:
		vid = str(Fremd.weg(sn, "resourceId/videoId", ""))
	if not valid_id(vid):
		return {}
	var title := str(sn.get("title", ""))
	if title in ["Deleted video", "Private video", "Gelöschtes Video", "Privates Video"]:
		return {}
	var thumb := str(Fremd.weg(sn, "thumbnails/medium/url", thumb_for(vid)))
	return {
		"id": vid, "title": title,
		"channel": str(sn.get("videoOwnerChannelTitle", sn.get("channelTitle", ""))),
		"channel_id": str(sn.get("videoOwnerChannelId", sn.get("channelId", ""))),
		"duration": parse_iso_duration(str(cd.get("duration", ""))),
		"views": _num(Fremd.weg(it, "statistics/viewCount")),
		"thumb": thumb,
		"published": int(Time.get_unix_time_from_datetime_string(str(sn.get("publishedAt", "")).substr(0, 19))) if sn.has("publishedAt") else 0,
		"short": false, "live": str(sn.get("liveBroadcastContent", "none")) == "live",
	}


# --- Suche und Kanäle ------------------------------------------------------------------------

## remember: in „Zuletzt gesucht“ der Videos aufnehmen (nicht bei Suchen, die Uzai selbst baut).
func search(q: String, remember := true) -> Array:
	q = q.strip_edges()
	if q == "":
		return []
	if remember:
		var s: Array = data.searches
		s.erase(q)
		s.push_front(q)
		data.searches = s.slice(0, 12)
		_dirty()
	if demo:
		var all: Array = feed + trending
		return all.filter(func(v): return str(v.title).to_lower().contains(q.to_lower()) or str(v.channel).to_lower().contains(q.to_lower()))
	if not has_ytdlp():
		error = "yt-dlp fehlt. Unter Videos → Für dich „Jetzt einrichten“ wählen."
		return []
	var r := await exec(ytdlp_path(), _ytdlp_args(["ytsearch40:" + q]), 45.0)
	if not r.ok:
		error = "Suche fehlgeschlagen: " + str(r.error).strip_edges().get_slice("\n", 0).left(120)
		return []
	error = ""
	return parse_ytdlp(r.text, Config.get_value("youtube.hide_shorts", true))


## YouTube-Filter „Live“, so wie er in YouTubes eigener Adresse steht (doppelt kodiert).
const LIVE_FILTER := "EgJAAQ%253D%253D"
const LIVE_SUCHE_MAX := 8


static func live_search_url(q: String) -> String:
	return "https://www.youtube.com/results?search_query=%s&sp=%s" % [q.strip_edges().uri_encode(), LIVE_FILTER]


## Was zum Suchwort gerade live ist. Die normale Suche stellt Livestreams fast nie nach vorn (bei „league of
## legends“ unter 40 Treffern keiner, obwohl Hunderte liefen) – nur der Filter „Live“ findet sie.
func search_live(q: String) -> Array:
	q = q.strip_edges()
	if q == "":
		return []
	if demo:
		var all: Array = feed + trending
		return all.filter(func(v): return bool(v.get("live", false)) and str(v.title).to_lower().contains(q.to_lower()))
	if not has_ytdlp():
		return []
	var r := await exec(ytdlp_path(), _ytdlp_args(["--playlist-end", str(LIVE_SUCHE_MAX), live_search_url(q)]), 45.0)
	if not r.ok:
		return []
	return parse_ytdlp(r.text, true).filter(func(v): return bool(v.live))


## Suche und bis zu live_max Livestreams dazu, beide gleichzeitig: {"videos": […], "live": […]}. Was live gezeigt
## wird, fehlt unter den Videos (sonst stünde es zweimal da).
func search_mit_live(q: String, live_max := LIVE_SUCHE_MAX) -> Dictionary:
	var box := { "done": false, "list": [] }
	_live_in(q, box)
	var videos: Array = await search(q)
	while not bool(box.done):
		await get_tree().process_frame
	var live: Array = (box.list as Array).slice(0, live_max)
	var ids := {}
	for v in live:
		ids[str(v.id)] = true
	return { "videos": videos.filter(func(v): return not ids.has(str(v.id))), "live": live }


func _live_in(q: String, box: Dictionary) -> void:
	box.list = await search_live(q)
	box.done = true


## Videos eines Kanals (neueste zuerst, mit Länge und Aufrufen).
func channel_videos(channel_id: String) -> Array:
	if demo:
		return feed.filter(func(v): return v.channel_id == channel_id)
	if not kanal_ok(channel_id):
		return []
	if has_ytdlp():
		var r := await exec(ytdlp_path(), _ytdlp_args(["--playlist-end", "60", "https://www.youtube.com/channel/%s/videos" % channel_id]), 45.0)
		if r.ok:
			_remember_channel(channel_id, parse_channel_meta(r.text))
			return parse_ytdlp(r.text, true)
	return await _rss(channel_id)


## Was Uzai über einen Kanal weiß: Profilbild, Banner, Abonnenten (leer, wenn nichts bekannt).
func channel_info(channel_id: String) -> Dictionary:
	var out: Dictionary = {}
	var known: Variant = channels.get(channel_id)
	if known is Dictionary:
		out = (known as Dictionary).duplicate()
	for s in data.subs:
		if str(s.get("id", "")) == channel_id:
			if str(out.get("avatar", "")) == "" and str(s.get("thumb", "")) != "":
				out["avatar"] = str(s.thumb)
			if not out.has("followers") and int(s.get("followers", 0)) > 0:
				out["followers"] = int(s.followers)
	return out


func _remember_channel(channel_id: String, meta: Dictionary) -> void:
	if channel_id == "" or meta.is_empty():
		return
	channels[channel_id] = meta
	while channels.size() > 400:
		channels.erase(channels.keys()[0])
	Config.write_json(Config.path("cache/youtube-channels.json"), channels)
	var av := str(meta.get("avatar", ""))
	if av == "":
		return
	for s in data.subs:
		if str(s.get("id", "")) == channel_id and str(s.get("thumb", "")) == "":
			s["thumb"] = av
			_dirty()


## Kanal-Angaben aus `yt-dlp --flat-playlist -J <Kanal>/videos`: Profilbild (quadratisch oder
## „avatar_uncropped“), Banner (das breiteste, sonst „banner_uncropped“), Abonnenten.
static func parse_channel_meta(text: String) -> Dictionary:
	var d: Variant = Fremd.json(text)
	if not (d is Dictionary):
		return {}
	var out := {}
	var avatar := ""
	var avatar_w := 0
	var banner := ""
	var banner_w := 0
	var uncropped := ""
	var thumbs: Variant = d.get("thumbnails")
	if thumbs is Array:
		for t in thumbs:
			if not (t is Dictionary):
				continue
			var url := str(t.get("url", ""))
			if not url.begins_with("http"):
				continue
			var tid := str(t.get("id", ""))
			var w := _num(t.get("width"))
			var h := _num(t.get("height"))
			if tid == "avatar_uncropped":
				avatar = url
				avatar_w = 1 << 20
			elif tid == "banner_uncropped":
				uncropped = url
			elif w > 0 and h > 0 and w >= h * 3 and w > banner_w:
				banner = url
				banner_w = w
			elif w > 0 and w == h and w > avatar_w:
				avatar = url
				avatar_w = w
	if banner == "":
		banner = uncropped
	if avatar != "":
		out["avatar"] = avatar
	if banner != "":
		out["banner"] = banner
	var f := _num(d.get("channel_follower_count"))
	if f > 0:
		out["followers"] = f
	return out


## Kennung eines Kanals, wie sie in eine Adresse darf: nur die Zeichen von YouTube-Kennungen. Die Kennung kommt aus
## Feeds und von yt-dlp – nichts davon geht ungeprüft in eine Adresse oder an yt-dlp.
static func kanal_ok(id: String) -> bool:
	return id != "" and id.length() <= 64 and _id_chars(id)


func _rss(channel_id: String) -> Array:
	var list: Array = []
	if not kanal_ok(channel_id):
		return list
	if channel_id.begins_with("UC") and Config.get_value("youtube.hide_shorts", true):
		# UULF… ist die Liste nur mit normalen Videos (ohne Shorts und Livestreams).
		var r := await _rss_get(RSS + "playlist_id=UULF" + channel_id.substr(2))
		if r.ok:
			list = await _parse_off(r.body)
	if list.is_empty():
		var r2 := await _rss_get(RSS + "channel_id=" + channel_id)
		if r2.ok:
			list = await _parse_off(r2.body)
	if Config.get_value("youtube.hide_shorts", true):
		list = list.filter(func(v): return not v.short)
	return list


## Feeds über die eigene Spur „yt“ (Net.MAX_PARALLEL): Hunderte Abos bremsen so weder Filme-
## Kataloge noch Twitch. Ein Feed, der nach RSS_TIMEOUT nicht da ist, fehlt diesmal.
const RSS_TIMEOUT := 10.0


func _rss_get(url: String) -> Dictionary:
	return await Net.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", RSS_TIMEOUT, "yt")


## RSS auf einem Hilfsthread lesen: Bei vielen Abos kämen sonst Dutzende Feeds kurz nacheinander
## auf den Hauptthread (je einige ms) und das Menü ruckelte, gerade kurz nach dem Wechsel zu Videos.
func _parse_off(body: PackedByteArray) -> Array:
	var r: Variant = await Arbeit.ergebnis(parse_rss.bind(body))
	return r if r is Array else []


## Liste nur nach ihren Videos (für „hat sich etwas geändert?“).
static func ids_key(list: Array) -> String:
	var ids := PackedStringArray()
	for v in list:
		ids.append(str((v as Dictionary).get("id", "")) if v is Dictionary else "")
	return ",".join(ids)


## Neue Videos aller Abos zusammen, neueste zuerst.
## Signale: „feed_loading“ nur für den Ladezustand (die Seiten bauen dafür kaum neu), „feed“ erst,
## wenn wirklich andere Videos da sind.
func refresh_feed(force := false) -> void:
	if demo:
		return
	if feed_loading:
		# Kamen währenddessen neue Abos (etwa von der Fernseher-Anmeldung): danach gleich noch einmal.
		_feed_again = _feed_again or force
		return
	if not force and Time.get_unix_time_from_system() - feed_at < 1200 and not feed.is_empty():
		return
	var subs: Array = data.subs
	if subs.is_empty():
		# Ohne Kanäle: wenigstens der Abo-Feed der Fernseher-Anmeldung (inoffiziell), falls da.
		feed = feed_mischen([], tv.sub_videos)
		changed.emit("feed")
		return
	feed_loading = true
	changed.emit("feed_loading")
	var before := ids_key(feed)
	var leer := feed.is_empty()
	var t0 := Time.get_ticks_msec()
	var all: Array = []
	var box := { "left": subs.size() }
	for s in subs:
		_feed_one(Fremd.text(Fremd.verz(s).get("id")), all, box)
	# Ohne gemerkten Stand (erster Start): was schon da ist, gleich zeigen statt auf alle Kanäle zu
	# warten – höchstens alle TEIL_MS einmal, damit die Seite nicht dauernd neu baut.
	var shown_n := 0
	var shown_at := t0
	while int(box.left) > 0:
		await get_tree().process_frame
		if teil_zeigen(leer, all.size() - shown_n, Time.get_ticks_msec() - shown_at):
			shown_n = all.size()
			shown_at = Time.get_ticks_msec()
			feed = feed_mischen(einmal(all), tv.sub_videos)
			changed.emit("feed")
	feed = feed_mischen(einmal(all), tv.sub_videos)
	if logged_in():
		await fill_durations(feed.slice(0, 50))
	feed_at = int(Time.get_unix_time_from_system())
	feed_loading = false
	Config.write_json(Config.path("cache/youtube-feed.json"), { "at": feed_at, "feed": feed })
	Media.log_line("leistung", "Videos: Abo-Feeds (%d Kanäle) in %d ms, %d Videos" % [subs.size(), Time.get_ticks_msec() - t0, feed.size()])
	changed.emit("feed" if ids_key(feed) != before else "feed_loading")
	if _feed_again:
		_feed_again = false
		refresh_feed(true)


## Zwischenstand zeigen? Nur ohne gemerkten Stand (leer), wenn Neues kam und seit dem letzten
## Zeigen TEIL_MS vergangen sind.
const TEIL_MS := 1200


static func teil_zeigen(leer: bool, neu: int, seit_ms: int) -> bool:
	return leer and neu > 0 and seit_ms >= TEIL_MS


## Jedes Video einmal (erstes Vorkommen gewinnt).
static func einmal(list: Array) -> Array:
	var seen := {}
	var out: Array = []
	for v in list:
		if not (v is Dictionary) or seen.has(str(v.get("id", ""))):
			continue
		seen[str(v.get("id", ""))] = true
		out.append(v)
	return out


## RSS-Videos der Abos und der Abo-Feed der Fernseher-Anmeldung zusammen: jedes Video einmal,
## was gerade live ist zuerst, dann neueste zuerst (das Alter aus „vor 3 Tagen“ ist ungefähr),
## höchstens limit. Livestreams haben kein Alter („1.234 Zuschauer“ statt „vor 2 Stunden“): Nach
## dem Alter allein standen sie ganz hinten – in der Reihe, die nur die ersten zeigt, nie zu sehen,
## und bei vielen Abos fielen sie hinter limit ganz weg.
static func feed_mischen(rss: Array, tv_list: Array, limit := 200) -> Array:
	var at := {}
	var out: Array = []
	for list in [rss, tv_list]:
		for v in list:
			if not (v is Dictionary) or not valid_id(str(v.get("id", ""))):
				continue
			var id := str(v.id)
			if not at.has(id):
				at[id] = out.size()
				out.append(v)
			elif bool(v.get("live", false)):
				# Dass ein Video gerade live ist, weiß nur der Abo-Feed der Anmeldung (RSS führt den
				# Stream wie ein normales Video).
				out[int(at[id])] = v
	out.sort_custom(func(a, b):
		var la := bool(a.get("live", false))
		if la != bool(b.get("live", false)):
			return la
		return int(a.get("published", 0)) > int(b.get("published", 0)))
	return out.slice(0, limit)


## Was davon gerade live ist (Reihe bzw. Gruppe „Gerade live“).
static func nur_live(list: Array) -> Array:
	return list.filter(func(v: Variant) -> bool: return v is Dictionary and bool(v.get("live", false)))


## Abos von der Fernseher-Anmeldung (youtube_tv.gd, inoffiziell) übernehmen – wie die Google-Abos:
## eigene Abos bleiben, Kanäle, die schon da sind, auch. Ändert sich die Liste, kommt der Feed neu.
func tv_abos(channels: Array) -> void:
	var before := ids_key(data.subs)
	var keep: Array = (data.subs as Array).filter(func(s): return s.get("source") != "tv")
	var ids := {}
	for s in keep:
		ids[str(s.get("id", ""))] = true
	for c in channels:
		if c is Dictionary and str(c.get("id", "")).begins_with("UC") and not ids.has(str(c.id)):
			ids[str(c.id)] = true
			keep.append({ "id": str(c.id), "title": str(c.get("title", "")), "thumb": str(c.get("thumb", "")), "source": "tv" })
	keep.sort_custom(func(a, b): return str(a.title).to_lower() < str(b.title).to_lower())
	data.subs = keep
	if ids_key(keep) != before:
		_dirty()
		changed.emit("subs")
		refresh_feed(true)
	else:
		# Dieselben Kanäle: der Feed der Anmeldung neu – seine alten Videos gehen (ein beendeter
		# Livestream stünde sonst weiter als „live“ da), die aus RSS bleiben.
		var neu := feed_mischen(feed.filter(func(v: Variant) -> bool: return v is Dictionary and str(v.get("src", "")) != "tv"), tv.sub_videos)
		if ids_key(neu) != ids_key(feed):
			feed = neu
			changed.emit("feed")


## Abgemeldet (Fernseher-Anmeldung): die von dort übernommenen Kanäle gehen.
func tv_abos_vergessen() -> void:
	var n := (data.subs as Array).size()
	data.subs = (data.subs as Array).filter(func(s): return s.get("source") != "tv")
	if (data.subs as Array).size() != n:
		_dirty()
		changed.emit("subs")
		refresh_feed(true)


func _feed_one(cid: String, into: Array, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _feed_one_arbeit(cid, into, box)
	box.left = int(box.left) - 1


func _feed_one_arbeit(cid: String, into: Array, box: Dictionary) -> void:
	var list := await _rss(cid)
	into.append_array(list)


# --- Shorts ------------------------------------------------------------------------------------
# Hochkant-Videos deiner Abos, im eigenen Reiter (in den Reihen bleiben sie mit „Shorts ausblenden“
# draußen). Quelle ist derselbe öffentliche RSS-Weg wie bei den neuen Videos: Jeder Kanal hat eine
# Liste nur mit seinen Shorts (UUSH… statt UULF…). Geholt wird erst, wenn du den Reiter öffnest.

const SHORTS_MAX := 120


## Adresse der Shorts-Liste eines Kanals ("" für Kanäle ohne UC-Kennung).
static func shorts_feed_url(channel_id: String) -> String:
	if not channel_id.begins_with("UC") or channel_id.length() != 24 or not _id_chars(channel_id):
		return ""
	return RSS + "playlist_id=UUSH" + channel_id.substr(2)


## Nur Zeichen, die in YouTube-Kennungen vorkommen (A–Z, a–z, 0–9, „-“, „_“) – nichts davon
## landet sonst ungeprüft in einer Adresse.
static func _id_chars(id: String) -> bool:
	for ch in id:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_"):
			return false
	return true


## Shorts mehrerer Kanäle zusammen: jedes nur einmal, neueste zuerst, höchstens SHORTS_MAX.
static func merge_shorts(lists: Array) -> Array:
	var seen := {}
	var out: Array = []
	for l in lists:
		for v in l:
			if not (v is Dictionary) or seen.has(str(v.get("id", ""))):
				continue
			seen[str(v.id)] = true
			var sv: Dictionary = (v as Dictionary).duplicate()
			sv["short"] = true
			out.append(sv)
	out.sort_custom(func(a, b): return int(a.get("published", 0)) > int(b.get("published", 0)))
	return out.slice(0, SHORTS_MAX)


## Holt der Reiter „Shorts“ beim Öffnen gleich frische (seit 20 Minuten nicht geholt)?
func shorts_due() -> bool:
	return not demo and Time.get_unix_time_from_system() - shorts_at >= 1200 and not (data.subs as Array).is_empty()


## Läufe von refresh_shorts, die gerade unterwegs sind (siehe dort).
var _refresh_shorts_offen := 0


func refresh_shorts(force := false) -> void:
	_refresh_shorts_offen += 1
	await _refresh_shorts_lauf(force)
	_refresh_shorts_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_shorts täte bis zum Neustart nichts mehr.
	if _refresh_shorts_offen == 0 and shorts_loading:
		shorts_loading = false


func _refresh_shorts_lauf(force := false) -> void:
	if shorts_loading:
		return
	if not force and Time.get_unix_time_from_system() - shorts_at < 1200 and not shorts.is_empty():
		return
	if demo:
		return
	var subs: Array = data.subs
	shorts_loading = true
	changed.emit("shorts_loading")
	var before := ids_key(shorts)
	var leer := shorts.is_empty()
	var t0 := Time.get_ticks_msec()
	var lists: Array = []
	var box := { "left": 0 }
	for s in subs:
		var u := shorts_feed_url(str(s.get("id", "")))
		if u != "":
			box.left = int(box.left) + 1
			_shorts_one(u, lists, box)
	# Erster Start ohne gemerkte Shorts: die ersten Kanäle gleich zeigen (wie beim Feed).
	var shown_n := 0
	var shown_at := t0
	while int(box.left) > 0:
		await get_tree().process_frame
		if teil_zeigen(leer, lists.size() - shown_n, Time.get_ticks_msec() - shown_at):
			shown_n = lists.size()
			shown_at = Time.get_ticks_msec()
			shorts = merge_shorts(lists)
			changed.emit("shorts")
	shorts = merge_shorts(lists)
	shorts_at = int(Time.get_unix_time_from_system())
	shorts_loading = false
	Config.write_json(Config.path("cache/youtube-shorts.json"), { "at": shorts_at, "shorts": shorts })
	Media.log_line("leistung", "Videos: Shorts-Feeds (%d Kanäle) in %d ms, %d Shorts" % [subs.size(), Time.get_ticks_msec() - t0, shorts.size()])
	changed.emit("shorts" if ids_key(shorts) != before else "shorts_loading")


func _shorts_one(url: String, into: Array, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _shorts_one_arbeit(url, into, box)
	box.left = int(box.left) - 1


func _shorts_one_arbeit(url: String, into: Array, box: Dictionary) -> void:
	var r := await _rss_get(url)
	if r.ok:
		into.append(await _parse_off(r.body))


# --- Für dich ----------------------------------------------------------------------------------
# Echte Empfehlungen von YouTube gibt es nur mit Anmeldung im Browser: yt-dlp liest dann die
# Startseite („:ytrec“) mit den Cookies des Browsers. Ohne das mischt Uzai selbst: neue Videos
# der Kanäle, die du am meisten schaust (auch ohne Abo), dazu Neues aus den Abos und Angesagtes.

const BROWSERS := [["", "Aus (eigene Mischung)"], ["firefox", "Firefox"], ["edge", "Edge"], ["chrome", "Chrome"], ["brave", "Brave"], ["opera", "Opera"],
		["datei", "cookies.txt-Datei"]]


func cookie_args() -> PackedStringArray:
	var c := str(Config.get_value("youtube.cookies", ""))
	if c == "":
		return PackedStringArray()
	if c == "datei":
		var f := str(Config.get_value("youtube.cookies_file", ""))
		return PackedStringArray(["--cookies", f]) if f != "" and FileAccess.file_exists(f) else PackedStringArray()
	# Nur ein Browser aus der Auswahl: yt-dlp läse hinter dem Namen sonst auch Profil und Schlüsselbund aus dem Text.
	if not BROWSERS.any(func(b: Array) -> bool: return str(b[0]) == c):
		return PackedStringArray()
	return PackedStringArray(["--cookies-from-browser", c])


## Läufe von refresh_recs, die gerade unterwegs sind (siehe dort).
var _refresh_recs_offen := 0


func refresh_recs(force := false) -> void:
	_refresh_recs_offen += 1
	await _refresh_recs_lauf(force)
	_refresh_recs_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und refresh_recs täte bis zum Neustart nichts mehr.
	if _refresh_recs_offen == 0 and recs_loading:
		recs_loading = false


func _refresh_recs_lauf(force := false) -> void:
	if demo or recs_loading:
		return
	var now := int(Time.get_unix_time_from_system())
	if not force and now - recs_at < 1800 and not recs.is_empty():
		return
	recs_loading = true
	changed.emit("recs_loading")
	var t0 := Time.get_ticks_msec()
	var before := ids_key(recs)
	var got: Array = []
	recs_error = ""
	var ck := cookie_args()
	if not ck.is_empty() and has_ytdlp():
		var args: Array = Array(ck)
		args.append_array(["--playlist-end", "60", ":ytrec"])
		var r := await exec(ytdlp_path(), _ytdlp_args(args), 60.0)
		if r.ok:
			got = _unseen(parse_ytdlp(r.text, Config.get_value("youtube.hide_shorts", true)))
		else:
			recs_error = explain_cookie_error(str(r.error))
	if got.size() >= 6:
		recs_source = "youtube"
	else:
		got = await _mix(now)
		recs_source = "mix"
	recs = got.slice(0, 60)
	recs_at = now
	recs_loading = false
	Config.write_json(Config.path("cache/youtube-recs.json"), { "at": recs_at, "source": recs_source, "recs": recs })
	Media.log_line("leistung", "Videos: Empfehlungen (%s) in %d ms" % ["YouTube" if recs_source == "youtube" else "Mischung", Time.get_ticks_msec() - t0])
	changed.emit("recs" if ids_key(recs) != before else "recs_loading")


## Was yt-dlp beim Lesen der Browser-Cookies meldet, in einen verständlichen Satz.
static func explain_cookie_error(err: String) -> String:
	var e := err.to_lower()
	if e.contains("could not copy") or e.contains("database is locked") or e.contains("permission"):
		return "Der Browser hält seine Cookies gesperrt. Browser schließen oder Firefox nehmen."
	if e.contains("decrypt") or e.contains("app-bound") or e.contains("dpapi"):
		return "Chrome- und Edge-Cookies sind nicht lesbar. Firefox oder cookies.txt nehmen."
	if e.contains("could not find") or e.contains("not find"):
		return "Diesen Browser hat Uzai auf dem PC nicht gefunden."
	if e.contains("sign in") or e.contains("login"):
		return "Im Browser ist niemand bei YouTube angemeldet."
	return "YouTube-Empfehlungen konnten nicht geladen werden."


func _unseen(list: Array) -> Array:
	var seen := {}
	for h in data.history:
		if h.get("done", false) or int(h.get("pos", 0)) > 20:
			seen[str(h.id)] = true
	return list.filter(func(v): return not seen.has(str(v.id)))


## Eigene Mischung: Kanäle aus deinem Verlauf und der Merkliste, die du nicht abonniert hast,
## liefern ihre neuesten Videos dazu.
func _mix(now: int) -> Array:
	var weights := channel_weights(data.history, data.later)
	var extra: Array = []
	var picked := 0
	var box := { "left": 0 }
	var ids: Array = weights.keys()
	ids.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	for cid in ids:
		if picked >= 8:
			break
		if str(cid) == "" or is_subscribed(str(cid)):
			continue
		picked += 1
		box.left = int(box.left) + 1
		_feed_one(str(cid), extra, box)
	while int(box.left) > 0:
		await get_tree().process_frame
	var cands: Array = feed + extra + trending
	if cands.size() < 12 and has_ytdlp():
		# Ganz ohne Verlauf und Abos: die Startseite, die YouTube ohne Anmeldung zeigt.
		var r := await exec(ytdlp_path(), _ytdlp_args(["--playlist-end", "40", ":ytrec"]), 45.0)
		if r.ok:
			cands += parse_ytdlp(r.text, Config.get_value("youtube.hide_shorts", true))
	var day := int(now / 86400)
	return rank_mix(cands, data.history, data.later, data.subs, now, day)


## Wie stark dich ein Kanal interessiert: angesehene Videos (fertig zählt mehr), Merkliste.
static func channel_weights(history: Array, later: Array) -> Dictionary:
	var w := {}
	for h in history:
		var cid := str(h.get("channel_id", ""))
		if cid == "":
			continue
		w[cid] = float(w.get(cid, 0.0)) + (1.5 if h.get("done", false) else 1.0)
	for l in later:
		var cid2 := str(l.get("channel_id", ""))
		if cid2 != "":
			w[cid2] = float(w.get(cid2, 0.0)) + 0.8
	return w


## Kandidaten sortieren: Kanal-Interesse, Abo, wie neu, wie beliebt. Gesehenes fällt raus,
## höchstens drei Videos pro Kanal, damit die Seite gemischt bleibt. seed ändert sich täglich.
static func rank_mix(cands: Array, history: Array, later: Array, subs: Array, now: int, seed: int) -> Array:
	var weights := channel_weights(history, later)
	var seen := {}
	for h in history:
		if h.get("done", false) or int(h.get("pos", 0)) > 20:
			seen[str(h.id)] = true
	var subbed := {}
	for s in subs:
		subbed[str(s.get("id", ""))] = true
	var scored: Array = []
	var dup := {}
	for v in cands:
		var id := str(v.get("id", ""))
		if id == "" or seen.has(id) or dup.has(id) or v.get("short", false):
			continue
		dup[id] = true
		var cid := str(v.get("channel_id", ""))
		var score := minf(float(weights.get(cid, 0.0)), 6.0) * 1.2
		if subbed.has(cid):
			score += 1.5
		var pub := int(v.get("published", 0))
		if pub > 0:
			var days := float(now - pub) / 86400.0
			score += 3.0 if days < 2 else (2.0 if days < 7 else (0.8 if days < 30 else 0.0))
		var views := int(v.get("views", 0))
		if views > 0:
			score += clampf(log(float(views)) / log(10.0) - 3.0, 0.0, 4.0) * 0.5
		# kleine, tägliche Würze, damit die Seite nicht jeden Tag gleich aussieht
		score += float(abs(hash(id + str(seed))) % 1000) / 1000.0 * 1.2
		scored.append([score, v])
	scored.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	var per := {}
	var rest: Array = []
	for sv in scored:
		var cid2 := str(sv[1].get("channel_id", ""))
		if int(per.get(cid2, 0)) >= 3:
			rest.append(sv[1])
			continue
		per[cid2] = int(per.get(cid2, 0)) + 1
		out.append(sv[1])
	out.append_array(rest)
	return out


## Fehlende Längen über die API nachtragen (1 Einheit pro 50 Videos).
func fill_durations(list: Array) -> void:
	var ids := PackedStringArray()
	for v in list:
		if int(v.get("duration", 0)) == 0:
			ids.append(str(v.id))
	if ids.is_empty():
		return
	var r := await api("videos", { "part": "contentDetails,statistics", "id": ",".join(ids.slice(0, 50)), "maxResults": 50 })
	if not r.ok:
		return
	var by := {}
	for it in Fremd.zeilen(r.data, "items"):
		by[str(it.get("id", ""))] = it
	for v in list:
		var it: Dictionary = by.get(str(v.id), {})
		if not it.is_empty():
			v["duration"] = parse_iso_duration(str(Fremd.weg(it, "contentDetails/duration", "")))
			v["views"] = _num(Fremd.weg(it, "statistics/viewCount"))


# --- Abos, Verlauf, Merkliste ----------------------------------------------------------------

func is_subscribed(channel_id: String) -> bool:
	for s in data.subs:
		if str(s.id) == channel_id:
			return true
	return false


func subscribe(channel_id: String, title: String, thumb := "") -> void:
	if channel_id == "" or is_subscribed(channel_id):
		return
	data.subs.append({ "id": channel_id, "title": title, "thumb": thumb, "source": "uzai" })
	data.subs.sort_custom(func(a, b): return str(a.title).to_lower() < str(b.title).to_lower())
	_dirty()
	changed.emit("subs")
	refresh_feed(true)


func unsubscribe(channel_id: String) -> void:
	data.subs = (data.subs as Array).filter(func(s): return str(s.id) != channel_id)
	feed = feed.filter(func(v): return str(v.channel_id) != channel_id)
	_dirty()
	changed.emit("subs")
	changed.emit("feed")


## Fortschritt merken. Ab 92 % gilt ein Video als gesehen.
## periodic: Zwischenstand während der Wiedergabe (alle 5 s). Der kommt nur in den Speicher; auf
## die Platte und als Meldung höchstens jede Minute – Pause, Stopp und Ende speichern sofort.
var _periodic_at := 0


func record(v: Dictionary, pos: float, dur: float, periodic := false) -> void:
	if v.is_empty():
		return
	var h: Array = data.history
	var entry := {}
	for e in h:
		if str(e.id) == str(v.id):
			entry = e
			break
	if entry.is_empty():
		entry = v.duplicate()
	else:
		h.erase(entry)
	for k in ["title", "channel", "channel_id", "thumb"]:
		if str(v.get(k, "")) != "":
			entry[k] = v[k]
	if dur > 0:
		entry["duration"] = int(dur)
	var done := dur > 0 and pos >= dur * 0.92
	entry["pos"] = 0 if done else int(pos)
	entry["done"] = done
	entry["at"] = int(Time.get_unix_time_from_system())
	h.push_front(entry)
	data.history = h.slice(0, 400)
	if periodic and Time.get_ticks_msec() - _periodic_at < 60000:
		return
	_periodic_at = Time.get_ticks_msec()
	_dirty()
	changed.emit("history")


func resume_pos(id: String) -> int:
	for e in data.history:
		if str(e.id) == id:
			return int(e.get("pos", 0))
	return 0


func progress_of(id: String) -> float:
	for e in data.history:
		if str(e.id) == id:
			if e.get("done", false):
				return 1.0
			var d := float(e.get("duration", 0))
			return clampf(float(e.get("pos", 0)) / d, 0.0, 1.0) if d > 0 else 0.0
	return 0.0


func continue_list() -> Array:
	return (data.history as Array).filter(func(e): return int(e.get("pos", 0)) > 20 and not e.get("done", false)).slice(0, 20)


func remove_history(id: String) -> void:
	data.history = (data.history as Array).filter(func(e): return str(e.id) != id)
	_dirty()
	changed.emit("history")


func clear_history() -> void:
	data.history = []
	_dirty()
	changed.emit("history")


## Den Verlauf von vorher zurück (Rückgängig nach „Verlauf löschen“).
func restore_history(list: Array) -> void:
	data.history = list.duplicate(true)
	_dirty()
	changed.emit("history")


func in_later(id: String) -> bool:
	for e in data.later:
		if str(e.id) == id:
			return true
	return false


func toggle_later(v: Dictionary) -> bool:
	if in_later(str(v.id)):
		data.later = (data.later as Array).filter(func(e): return str(e.id) != str(v.id))
		_dirty()
		changed.emit("later")
		return false
	var e := v.duplicate()
	data.later.push_front(e)
	_dirty()
	changed.emit("later")
	return true


# --- SponsorBlock ------------------------------------------------------------------------------
# Abschnitte (Sponsor, Intro …) aus der freien Datenbank sponsor.ajay.app (CC BY-NC-SA 4.0). Uzai
# fragt nur mit den ersten vier Zeichen des SHA-256 der Video-ID (die Antwort enthält viele Videos,
# niemand sieht, welches du schaust), meldet nie selbst Abschnitte und schickt nichts über dich.

const SB_TIMEOUT := 6.0          ## kurz: lieber ohne Überspringen als ein wartender Player
const SB_TTL := 6 * 3600         ## so lange gelten gemerkte Abschnitte
const SB_MAX := 64               ## mehr Abschnitte hat kein echtes Video
const SB_LONGEST := 86400.0      ## Zeiten über einem Tag sind kaputt
const SB_SHORTEST := 1.0         ## kürzere Abschnitte lohnen keinen Sprung

var _sb_cache := {}              ## "Video-ID|Kategorien" → { at, segs }


func segments(video_id: String) -> Array:
	var cats := sb_categories(Config.get_value("youtube.sponsorblock", ["sponsor"]))
	if cats.is_empty():
		return []
	if demo:
		return [{ "start": 30.0, "end": 52.0, "category": "sponsor" }]
	if not valid_id(video_id):
		return []
	var key := video_id + "|" + ",".join(cats)
	var now := int(Time.get_unix_time_from_system())
	var hit: Dictionary = _sb_cache.get(key, {})
	if not hit.is_empty() and now - int(hit.at) < SB_TTL:
		return hit.segs
	var r := await Net.request(sb_url(video_id, cats), PackedStringArray(), HTTPClient.METHOD_GET, "", SB_TIMEOUT)
	var segs: Array = []
	if r.ok and (r.body as PackedByteArray).size() > 2_000_000:
		return []
	if r.ok:
		segs = parse_segments(Fremd.json_roh((r.body as PackedByteArray).get_string_from_utf8()), video_id, cats)
	elif int(r.code) != 404:
		# Netz weg oder Dienst gestört: nichts merken, beim nächsten Mal neu fragen.
		return []
	# 404 heißt bei SponsorBlock: zu diesem Präfix gibt es keine Abschnitte.
	_sb_cache[key] = { "at": now, "segs": segs }
	Config.cap(_sb_cache, 300)
	return segs


## YouTube-ID: genau 11 Zeichen aus Buchstaben, Ziffern, - und _ (nur so eine geht ins Netz).
static func valid_id(id: String) -> bool:
	if id.length() != 11:
		return false
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_"):
			return false
	return true


## Die ersten vier Zeichen des SHA-256 der Video-ID – mehr verlässt den PC nicht.
static func sb_prefix(video_id: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(video_id.to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 4)


## Gewählte Kategorien, nur bekannte, in fester Reihenfolge (so kommt nichts Fremdes in die Adresse).
static func sb_categories(want: Variant) -> Array:
	var out: Array = []
	if not (want is Array):
		return out
	for c in SB_CATEGORIES:
		if (want as Array).has(c[0]):
			out.append(c[0])
	return out


static func sb_url(video_id: String, cats: Array) -> String:
	return SB_API % [sb_prefix(video_id), JSON.stringify(cats).uri_encode()]


## Antwort streng lesen: nur dieses Video, nur „überspringen“, nur gewählte (ohne Wahl: bekannte)
## Kategorien, nur echte Zahlen mit 0 ≤ Anfang < Ende ≤ ein Tag und höchstens SB_MAX Abschnitte.
## Alles andere fällt still weg – aus der Antwort wird nie etwas ausgeführt.
static func parse_segments(d: Variant, video_id: String, cats: Array = []) -> Array:
	var out: Array = []
	if not (d is Array):
		return out
	var allowed: Array = cats if not cats.is_empty() else SB_CATEGORIES.map(func(c: Array) -> String: return str(c[0]))
	for item in d:
		if not (item is Dictionary) or str(item.get("videoID", "")) != video_id or not (item.get("segments") is Array):
			continue
		var dur := _sb_num(item.get("videoDuration"))
		for s in item.segments:
			if out.size() >= SB_MAX:
				break
			if not (s is Dictionary) or not (s.get("segment") is Array) or (s.segment as Array).size() != 2:
				continue
			if str(s.get("actionType", "skip")) != "skip" or not allowed.has(str(s.get("category", ""))):
				continue
			var a := _sb_num(s.segment[0])
			var b := _sb_num(s.segment[1])
			if a < 0.0 or b - a < SB_SHORTEST or b > SB_LONGEST or (dur > 0.0 and a >= dur):
				continue
			out.append({ "start": a, "end": b, "category": str(s.category) })
	out.sort_custom(func(x, y): return x.start < y.start)
	return out


## Zahl aus der Antwort, sonst -1 (Text, null, unendlich, NaN).
static func _sb_num(v: Variant) -> float:
	if not (v is int or v is float):
		return -1.0
	var f := float(v)
	return f if is_finite(f) else -1.0


static func category_name(cat: String) -> String:
	for c in SB_CATEGORIES:
		if c[0] == cat:
			return c[1]
	return cat


# --- Google-Anmeldung (Geräte-Anmeldung wie bei Fernsehern) -----------------------------------

func client_id() -> String:
	return str(Config.get_value("youtube.client_id", ""))


func has_client() -> bool:
	return client_id() != "" and str(Config.get_value("youtube.client_secret", "")) != ""


func logged_in() -> bool:
	return demo and account != "" or str(Config.get_value("youtube.refresh", "")) != ""


## Liest die JSON-Datei, die Google beim Anlegen des OAuth-Clients anbietet.
func load_client_file(path: String) -> String:
	var d: Variant = Config.read_json(path, null)
	if not (d is Dictionary):
		return "Die Datei ist kein gültiges JSON."
	var inner: Dictionary = d
	for k in ["installed", "web", "tv"]:
		if d.get(k) is Dictionary:
			inner = d[k]
	if str(inner.get("client_id", "")) == "" or str(inner.get("client_secret", "")) == "":
		return "In der Datei stehen keine client_id und client_secret."
	Config.set_value("youtube.client_id", str(inner.client_id))
	Config.set_value("youtube.client_secret", str(inner.client_secret))
	changed.emit("account")
	return ""


## { ok, device_code, user_code, url, interval, expires } oder { ok: false, error }
func login_start() -> Dictionary:
	if not has_client():
		return { "ok": false, "error": "Es fehlt noch der Google-Zugang (Client-ID). Siehe Einstellungen → Videos." }
	var r := await Net.post_form(DEVICE_URL, { "client_id": client_id(), "scope": SCOPE })
	var d: Dictionary = r.data if r.data is Dictionary else {}
	if not d.has("device_code"):
		return { "ok": false, "error": str(d.get("error_description", d.get("error", "Google antwortet nicht."))) }
	return {
		"ok": true, "device_code": str(d.device_code), "user_code": str(d.get("user_code", "")),
		"url": str(d.get("verification_url", d.get("verification_uri", "https://www.google.com/device"))),
		"interval": int(d.get("interval", 5)), "expires": int(d.get("expires_in", 1800)),
	}


## "pending", "slow", "ok", "denied", "expired" oder "error"
func login_poll(device_code: String) -> String:
	var r := await Net.post_form(TOKEN_URL, {
		"client_id": client_id(), "client_secret": str(Config.get_value("youtube.client_secret", "")),
		"device_code": device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
	})
	var d: Dictionary = r.data if r.data is Dictionary else {}
	if d.has("access_token"):
		_access = str(d.access_token)
		_access_until = Time.get_unix_time_from_system() + Fremd.komma(d.get("expires_in"), 3600.0)
		if str(d.get("refresh_token", "")) != "":
			Config.set_value("youtube.refresh", str(d.refresh_token))
		var me := await api("channels", { "part": "snippet", "mine": "true" })
		account = str(Fremd.weg(me.data, "items/0/snippet/title", "Google-Konto")) if me.ok else "Google-Konto"
		Config.set_value("youtube.account", account)
		changed.emit("account")
		await import_subscriptions()
		load_trending()
		return "ok"
	match str(d.get("error", "")):
		"authorization_pending": return "pending"
		"slow_down": return "slow"
		"access_denied": return "denied"
		"expired_token": return "expired"
	return "error"


func logout() -> void:
	var tok := str(Config.get_value("youtube.refresh", ""))
	if tok != "":
		Net.post_form("https://oauth2.googleapis.com/revoke", { "token": tok })
	Config.set_value("youtube.refresh", "")
	Config.set_value("youtube.account", "")
	_access = ""
	account = ""
	trending = []
	playlists = []
	liked = []
	data.subs = (data.subs as Array).filter(func(s): return s.get("source") != "google")
	_dirty()
	changed.emit("account")
	changed.emit("subs")


func _token() -> String:
	if _access != "" and Time.get_unix_time_from_system() < _access_until - 60:
		return _access
	var rt := str(Config.get_value("youtube.refresh", ""))
	if rt == "":
		return ""
	if _refreshing:
		await _token_ready
		return _access
	_refreshing = true
	# Das Erneuern läuft in einer eigenen Funktion: Bricht es mit einem Fehler ab, wird hier trotzdem gelöst und
	# gemeldet. Sonst warteten alle späteren Abrufe für immer auf _token_ready.
	await _erneuern(rt)
	_refreshing = false
	_token_ready.emit()
	return _access


## Holt mit dem Erneuerungsschlüssel einen neuen Zugang (nur aus _token, siehe dort).
func _erneuern(rt: String) -> void:
	var r := await Net.post_form(TOKEN_URL, {
		"client_id": client_id(), "client_secret": str(Config.get_value("youtube.client_secret", "")),
		"refresh_token": rt, "grant_type": "refresh_token",
	})
	var d: Dictionary = r.data if r.data is Dictionary else {}
	if d.has("access_token"):
		_access = str(d.access_token)
		_access_until = Time.get_unix_time_from_system() + Fremd.komma(d.get("expires_in"), 3600.0)
	elif str(d.get("error", "")) == "invalid_grant":
		_access = ""
		error = "Die Google-Anmeldung ist abgelaufen. Bitte neu anmelden."
		Config.set_value("youtube.refresh", "")
		changed.emit("account")


func api(path: String, params: Dictionary) -> Dictionary:
	var tok := await _token()
	if tok == "":
		return { "ok": false, "data": null }
	var r := await Net.get_json(API + path + "?" + Net.query(params), PackedStringArray(["Authorization: Bearer " + tok]))
	if r.ok and r.data is Dictionary:
		return r
	return { "ok": false, "data": r.data }


## Abos aus dem Google-Konto übernehmen (eigene Uzai-Abos bleiben).
func import_subscriptions() -> void:
	var found: Array = []
	var page := ""
	for i in 20:
		var params := { "part": "snippet", "mine": "true", "maxResults": 50, "order": "alphabetical" }
		if page != "":
			params["pageToken"] = page
		var r := await api("subscriptions", params)
		if not r.ok:
			tv.yt_log("Google-Abos (offizielle Schnittstelle): Abfrage ging nicht, Seite %d" % (i + 1))
			return
		for it in Fremd.zeilen(r.data, "items"):
			var sn := Fremd.verz(it.get("snippet"))
			var cid := str(Fremd.weg(sn, "resourceId/channelId", ""))
			if cid != "":
				found.append({ "id": cid, "title": str(sn.get("title", "")), "thumb": str(Fremd.weg(sn, "thumbnails/default/url", "")), "source": "google" })
		page = str(Fremd.weg(r.data, "nextPageToken", ""))
		if page == "":
			break
	var keep: Array = (data.subs as Array).filter(func(s): return s.get("source") != "google")
	var ids := {}
	for s in keep:
		ids[str(s.id)] = true
	for s in found:
		if not ids.has(str(s.id)):
			keep.append(s)
	keep.sort_custom(func(a, b): return str(a.title).to_lower() < str(b.title).to_lower())
	data.subs = keep
	tv.yt_log("Google-Abos (offizielle Schnittstelle): %d Kanäle" % found.size())
	_dirty()
	changed.emit("subs")
	refresh_feed(true)


func load_trending() -> void:
	if demo:
		return
	var r := await api("videos", { "part": "snippet,contentDetails,statistics", "chart": "mostPopular",
		"regionCode": str(Config.get_value("youtube.region", "DE")), "maxResults": 40 })
	if not r.ok:
		return
	trending = []
	for it in Fremd.zeilen(r.data, "items"):
		var v := from_api(it)
		if not v.is_empty():
			trending.append(v)
	changed.emit("lists")


func load_playlists() -> void:
	if demo:
		return
	var r := await api("playlists", { "part": "snippet,contentDetails", "mine": "true", "maxResults": 50 })
	if not r.ok:
		return
	playlists = []
	for it in Fremd.zeilen(r.data, "items"):
		var sn := Fremd.verz(it.get("snippet"))
		playlists.append({ "id": str(it.get("id", "")), "title": str(sn.get("title", "")),
			"count": Fremd.zahl(Fremd.weg(it, "contentDetails/itemCount")),
			"thumb": str(Fremd.weg(sn, "thumbnails/medium/url", "")) })
	changed.emit("lists")


func playlist_videos(pid: String) -> Array:
	if demo:
		return feed.slice(0, 8)
	var out: Array = []
	if pid == "liked":
		var r0 := await api("videos", { "part": "snippet,contentDetails,statistics", "myRating": "like", "maxResults": 50 })
		if r0.ok:
			for it in Fremd.zeilen(r0.data, "items"):
				var v0 := from_api(it)
				if not v0.is_empty():
					out.append(v0)
		return out
	var r := await api("playlistItems", { "part": "snippet,contentDetails", "playlistId": pid, "maxResults": 50 })
	if not r.ok:
		return out
	for it in Fremd.zeilen(r.data, "items"):
		var v := from_api(it)
		if not v.is_empty():
			out.append(v)
	await fill_durations(out)
	return out


# --- Texte -------------------------------------------------------------------------------------

static func views_text(n: int) -> String:
	if n <= 0:
		return ""
	if n >= 1000000:
		return Lang.dec(("%.1f" % (n / 1000000.0)).trim_suffix(".0")) + " Mio. Aufrufe"
	if n >= 1000:
		return "%d.%03d Aufrufe" % [n / 1000, n % 1000] if n < 10000 else "%d Tsd. Aufrufe" % (n / 1000)
	return "%d Aufrufe" % n


static func followers_text(n: int) -> String:
	if n <= 0:
		return ""
	if n == 1:
		return "1 Abonnent"
	if n >= 1000000:
		return Lang.dec(("%.1f" % (n / 1000000.0)).trim_suffix(".0")) + " Mio. Abonnenten"
	if n >= 10000:
		return "%d Tsd. Abonnenten" % floori(n / 1000.0)
	if n >= 1000:
		return "%d.%03d Abonnenten" % [floori(n / 1000.0), n % 1000]
	return "%d Abonnenten" % n


static func time_text(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

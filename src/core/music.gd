extends "res://src/core/music_fuer_dich.gd"
## Musik im Guide und im Bereich Musik. Zwei Wege:
## "spotify": Spotify (Titel, Cover, Playlists, Für dich, Suche). Zwei Anmeldungen:
##            „Mit Spotify anmelden“ (Standard, ohne Einrichtung): die echte Anmeldeseite einmal im
##            Uzai-Browser, danach dieselben Wege wie der Webplayer (spotify_web.gd, music_spotify.gd);
##            Abspielen über Spotify Connect an die Spotify-App am PC. Zweiter Weg: eine eigene Client-ID
##            (Web-API, spotify_eigen.gd).
## "tasten":  Windows-Mediensitzung. Steuert Spotify (auch ohne Premium) und Musik-Player, zeigt Titel
##            und Cover – nur Musik-Apps (MUSIC_APPS), nie YouTube im Browser, Videos oder Spiele.
##            Auf Wunsch (music.browser) zählen Browser mit, etwa für Musik im Browser.
## "lokal":   eigene Musikdateien aus einem Ordner, abgespielt über Uzai (src/core/music_local.gd).
## Mit „spotify“ und einem Musikordner gibt es beide Quellen zugleich (beide()): Was zuletzt
## startet, spielt (aktiv), die andere hält an; Läuft gerade, Steuerung und Status folgen ihr.
## Apple Music ohne Umweg (MusicKit) braucht einen eigenen Apple-Entwickler-Schlüssel, den Uzai nicht
## hat; die Apple-Music-App erscheint über die Windows-Mediensitzung.
##
## Stand der Spotify-Schnittstelle (eigene App im „Development Mode“, 2026):
## - Playlists von Spotify selbst (Mix der Woche, Release Radar, Daily Mix) geben keine Titel heraus;
##   Uzai findet sie über die Suche und spielt sie direkt ab.
## - Titel gibt es nur für Playlists, die dir gehören oder an denen du mitarbeitest.
## - Suche höchstens 10 Treffer je Art; Playlist-Einträge heißen „item“ statt „track“, die Anzahl
##   steht unter „items“ statt „tracks“, der Pfad heißt /playlists/{id}/items.
## - Speichern und Entfernen laufen über /me/library mit Spotify-URIs (alte Wege als Rückfall).
## Mit Spotify angemeldet gelten diese Grenzen nicht (Mixe mit Titeln, fremde Playlists, Suche bis 20).
## Ändert Spotify etwas, fällt Uzai auf die eigene Client-ID bzw. den Grundmodus zurück (siehe _app_reject).
##
## Der Autoload besteht aus Schichten; jede erbt von der darunter und kennt nur diese:
##   music_daten.gd     Antworten von Spotify lesen, Daten der Vorführung (nur statisch)
##   music_spotify.gd   Anmeldung, Schlüssel, Anfragen, Spotify Connect; Signale und Zustand
##   music_listen.gd    Konto, Playlists, Warteschlange, Lieblingssongs, Suche, Künstler, Bibliothek
##   music_fuer_dich.gd „Für dich“ und die Mixe
##   music.gd (hier)    Start, Steuerung, Lautstärke, Abfragen, Windows-Mediensitzung, Zusammen hören


const REDIRECT := "http://127.0.0.1:8888/callback"
const POLL_SEEN := 4.0            ## „Läuft gerade“ abfragen, solange Musik zu sehen ist (Sekunden)
const POLL_HIDDEN := 20.0         ## sonst seltener

const LocalMusic := preload("res://src/core/music_local.gd")
const SpotifyPc := preload("res://src/core/spotify_pc.gd")

signal quelle_changed           ## Spotify und eigene Musik: die spielende Quelle hat gewechselt

var starting := false           ## Spotify startet gerade im Hintergrund
var local: Node                 ## lokale Musik (Musikquelle „lokal“), siehe music_local.gd
## Beide Quellen (Spotify mit Musikordner): welche gerade gilt – die zuletzt gestartete.
const ZUSTAENDE_AKTIV := { "spotify": ["lokal"], "lokal": ["spotify"] }
var aktiv := "spotify":
	set(neu):
		Zustand.wechsel("musik.aktiv", ZUSTAENDE_AKTIV, aktiv, neu)
		aktiv = neu
var _spotify_now := {}          ## beide Quellen: Stand von Spotify, während die eigene Musik spielt
var _spotify_queue: Array = []
var _poll_timer: Timer
var _progress_base := 0
var _progress_at := 0


func _ready() -> void:
	# Nur für die Netz-Probe (tests/net_musik.gd): eine nachgebaute Spotify-Schnittstelle.
	if Config.probe_env("UZAI_SPOTIFY_API") != "":
		_api_base = Config.probe_env("UZAI_SPOTIFY_API")
	if Config.probe_env("UZAI_SPOTIFY_ACCOUNTS") != "":
		_accounts = Config.probe_env("UZAI_SPOTIFY_ACCOUNTS")
	if Config.probe_env("UZAI_SPOTIFY_SPCLIENT") != "":
		_spclient = Config.probe_env("UZAI_SPOTIFY_SPCLIENT")
	if Config.probe_env("UZAI_SPOTIFY_PARTNER") != "":
		_partner = Config.probe_env("UZAI_SPOTIFY_PARTNER")
	if Config.probe_env("UZAI_SPOTIFY_DEALER") != "":
		_dealer_url = Config.probe_env("UZAI_SPOTIFY_DEALER")
	_connect_dev = "hobs_" + _hex(40)
	if Config.probe_env("UZAI_SPOTIFY_API") != "":
		_budget_scale = 100
	set_process(false)
	local = LocalMusic.new()
	local.name = "Lokal"
	add_child(local)
	local.state_changed.connect(_on_local)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 4.0
	_poll_timer.timeout.connect(poll)
	add_child(_poll_timer)
	_start_together()
	_qr_weg_vergessen()
	_grund_restore()
	_standard_lokal()
	_modi_melden()
	Config.changed.connect(func(k: String) -> void:
		if k in ["system.music_mode", "accounts.spotify_mode"]:
			_modi_melden()
		if k == "system.music_mode":
			_poll_timer.stop()
			# Läuft die eigene Musik weiter (etwa Spotify gerade verbunden), bleibt sie die Quelle.
			aktiv = "lokal" if local.wants_play() else "spotify"
			_spotify_now = {}
			_spotify_queue = []
			if not local_on():
				local.stop()
			now = {}
			queue_list = []
			updated.emit()
			quelle_changed.emit()
			start()
		elif k == "music.local_dir" and mode() == "tasten" and LocalMusic.root() != "":
			# Musik-Apps über Windows und jetzt ein Musikordner gewählt (Reiter „Eigene Musik“): ab jetzt
			# der eigene Player – das ist der Standard ohne Spotify.
			Config.set_value("system.music_mode", "lokal")
		elif k == "music.local_dir" and mode() in ["lokal", "spotify"]:
			var war := str(now.get("source", "")) == "lokal"
			local.stop()
			aktiv = "spotify"
			if war:
				now = _spotify_now if not local_on() else {}
				queue_list = _spotify_queue if not local_on() else []
				updated.emit()
				quelle_changed.emit()
			start()
		elif k == "accounts.spotify_mode" and not _quiet_mode:
			_mode_changed()
	)


## Musikquelle (system.music_mode: aus · tasten · lokal · spotify) und gewählte Anmeldung (accounts.spotify_mode:
## "" · app · eigen) stehen in den Einstellungen, ohne eigenes Feld: ihr Stand geht beim Start und bei jeder Änderung
## an Zustand.lage() und den Fehlerbericht („musik.quelle“, „musik.anmeldeart“). Welche Anmeldung wirklich gilt,
## zeigt „musik.zugang“ (_tok_mode).
func _modi_melden() -> void:
	Zustand.melden("musik.quelle", mode())
	Zustand.melden("musik.anmeldeart", str(Config.get_value("accounts.spotify_mode", "")))


## Die frühere Anmeldung per QR-Code (Kennung der Desktop-App) gibt es nicht mehr – „Mit Spotify anmelden“ ersetzt
## sie. Ihre gespeicherte Erneuerung wird einmal gelöscht (nichts Geheimes bleibt liegen); die Oberfläche bietet die
## neue Anmeldung an.
func _qr_weg_vergessen() -> void:
	if str(Config.get_value("accounts.spotify_app_refresh", "")) == "":
		return
	Config.set_value("accounts.spotify_app_refresh", "")
	_log("Frühere Anmeldung per QR-Code entfernt – neu: Mit Spotify anmelden")


## Without Spotify, music is a built-in player for the music folder. Switch once away from the old
## default "tasten" (music apps via Windows) when no Spotify account is connected; anyone who picks
## a mode afterwards keeps that choice.
func _standard_lokal() -> void:
	if bool(Config.get_value("music.lokal_standard", false)) or demo():
		return
	Config.set_value("music.lokal_standard", true)
	if mode() == "tasten" and not has_spotify():
		Config.set_value("system.music_mode", "lokal")


func start() -> void:
	if mode() == "lokal":
		_poll_timer.stop()
		# Noch kein Ordner gewählt: der Windows-Ordner „Musik“, wenn es ihn gibt (nur lesen, nur
		# dort; wählbar unter Einstellungen → Musik). Das Setzen startet neu (Config.changed).
		if LocalMusic.root() == "":
			var vorschlag := LocalMusic.suggested_root()
			if vorschlag != "" and DirAccess.dir_exists_absolute(vorschlag):
				Config.set_value("music.local_dir", vorschlag)
				return
		await lokal_laden()
		return
	if beide():
		lokal_laden()           # im Hintergrund, Spotify läuft daneben
	if demo():
		now = { "id": "demo0", "title": "To Zanarkand", "artist": "Nobuo Uematsu", "album": "Final Fantasy X", "art": "",
			"duration": 186000, "playing": true, "shuffle": false, "device": "Wohnzimmer-PC", "liked": true }
		now["uri"] = "spotify:track:demo0"
		now["repeat"] = "off"
		now["volume"] = 62
		now["context"] = "spotify:playlist:demo"
		_progress_base = 64000
		_progress_at = Time.get_ticks_msec()
		queue_list = demo_tracks().slice(1, 8)
		if Config.probe_env("UZAI_DEMO_GRUND") == "1":
			demo_grund = true
		if demo_grund:
			# Vorführung des Grundmodus: nur Läuft gerade und der eigene Verlauf.
			queue_list = []
			now["context"] = ""
			now["device"] = "SHIELD"
			now["device_type"] = "TV"
			verlauf = _demo_verlauf()
			_verlauf_loaded = true
			# Bibliothek aus dem Spotify-Fenster am PC (wie der Helfer sie liefert).
			var pcl := [["lib", "Lieblingssongs", "Playlist • 512 Titel", "spotify:user:du:collection"], ["lib", "Zum Zocken", "Playlist • Du", "playlist"],
				["lib", "Retro Abende", "Playlist • Lena", "playlist"], ["lib", "Spieleklassiker", "Playlist • Du", "playlist"],
				["lib", "Lo-Fi zum Lernen", "Playlist • Spotify", "playlist"], ["lib", "Nobuo Uematsu", "Künstler", "artist"],
				["lib", "Lena Raine", "Künstler", "artist"], ["lib", "Koji Kondo", "Künstler", "artist"], ["lib", "Yoko Shimomura", "Künstler", "artist"],
				["lib", "Final Fantasy X", "Album • Nobuo Uematsu", "album"], ["lib", "Celeste", "Album • Lena Raine", "album"],
				["lib", "Ocarina of Time", "Album • Koji Kondo", "album"], ["recent", "Dein Mix der Woche", "Playlist • Spotify", "playlist"],
				["recent", "Chill Beats", "Playlist • Lena", "playlist"], ["recent", "Kingdom Hearts", "Album • Yoko Shimomura", "album"]]
			var pci: Array = []
			for k in pcl.size():
				var u := str(pcl[k][3]) if str(pcl[k][3]).begins_with("spotify:") else "spotify:%s:%s" % [pcl[k][3], ("Demo%d" % k).rpad(22, "x")]
				pci.append({ "i": k, "sec": pcl[k][0], "name": pcl[k][1], "sub": pcl[k][2], "kind": "", "uri": u })
			pc_lib = pc_lib_from({ "ok": true, "items": pci }, verlauf)
			pc_state = "ok"
			recent_list = Verlauf.recent(verlauf, 50)
			updated.emit()
			return
		me = { "id": "du", "name": "Du" }
		playlists = [
				{ "id": "demo", "name": "Spieleklassiker", "uri": "spotify:playlist:demo", "count": 10, "art": "", "owner": "Du", "owner_id": "du", "mine": true },
			{ "id": "demo2", "name": "Zum Zocken", "uri": "spotify:playlist:demo2", "count": 48, "art": "", "owner": "Du", "owner_id": "du", "mine": true },
			{ "id": "demo3", "name": "Chill Beats", "uri": "spotify:playlist:demo3", "count": 112, "art": "", "owner": "Lena", "owner_id": "lena", "mine": false }]
		_demo_for_you()
		if local_on():
			_spotify_now = now.duplicate()
			_spotify_now["playing"] = false
			_spotify_queue = queue_list
			_on_local()
		updated.emit()
		return
	if mode() == "spotify" and has_spotify():
		poll()
		_poll_timer.start()
	elif use_windows():
		_poll_timer.wait_time = 2.0
		poll()
		_poll_timer.start()


## Ist Musik gerade zu sehen (Reiter Musik vorn oder Guide offen)? Sonst fragt Uzai seltener.
func music_seen() -> bool:
	if Launcher.guide_open:
		return true
	var m := get_tree().current_scene if is_inside_tree() else null
	return m != null and str(m.get("current")) == "music" and get_window().has_focus()


## Ohne Spotify-Anmeldung zeigt Uzai, was Spotify oder ein Musik-Player über Windows abspielt
## (mit Cover; nur Musik-Apps, siehe MUSIC_APPS).
func use_windows() -> bool:
	return Config.is_windows() and (mode() == "tasten" or (mode() == "spotify" and not has_spotify()))


## Albumbild laden: aus dem Netz (Spotify) oder als Datei (Windows-Mediensitzung).
static func load_art(url: String, w: int, cb: Callable) -> void:
	if url == "":
		cb.call(null)
	elif url.begins_with("http"):
		Media.url_texture(url, w, cb)
	else:
		Media.file_texture(url, w, cb)


func mode() -> String:
	return str(Config.get_value("system.music_mode", "lokal"))


## Spotify und eigene Musik zugleich: Quelle Spotify mit einem Musikordner.
func beide() -> bool:
	return mode() == "spotify" and LocalMusic.root() != ""


## Ist die eigene Sammlung zu sehen (allein oder neben Spotify)?
func lokal_da() -> bool:
	return mode() == "lokal" or beide()


## Spielt die eigene Musik (Steuerung, Läuft gerade, Warteschlange, Status folgen ihr)? Neben
## Spotify die zuletzt gestartete Quelle; ohne Spotify-Anmeldung immer.
func local_on() -> bool:
	return mode() == "lokal" or (beide() and (aktiv == "lokal" or not has_spotify()))


## Eigene Musik einlesen (falls nötig) und die letzte Warteschlange angehalten zurückholen.
func lokal_laden() -> void:
	if local.scanned_root != LocalMusic.root() or local.tracks.is_empty():
		await local.scan()
		if lokal_da() and local.current().is_empty():
			local.restore()
	_on_local()


## Die eigene Musik spielt (gleich, von wo gestartet): neben Spotify wird sie die Quelle, Spotify hält an.
func _zu_lokal() -> void:
	if aktiv == "lokal":
		return
	var war := now.duplicate()
	aktiv = "lokal"
	if str(war.get("source", "")) != "lokal":
		_spotify_now = war
		_spotify_now["playing"] = false
		_spotify_queue = queue_list
	quelle_changed.emit()
	if bool(war.get("playing", false)) and str(war.get("source", "")) != "lokal" and has_spotify() and not demo():
		if str(war.get("source", "")) == "windows":
			media_key("playpause", false)
		elif app_mode():
			await _connect_control(HTTPClient.METHOD_PUT, "/me/player/pause", null)
		else:
			await _api(HTTPClient.METHOD_PUT, "/me/player/pause")


## Spotify startet etwas aus Uzai: die eigene Musik hält an, Läuft gerade folgt Spotify.
func _zu_spotify() -> void:
	if not beide() or aktiv == "spotify" or not has_spotify():
		return
	aktiv = "spotify"
	local.set_paused(true)
	now = _spotify_now
	queue_list = _spotify_queue
	_progress_at = Time.get_ticks_msec()
	updated.emit()
	lists_changed.emit("queue")
	quelle_changed.emit()
	if is_instance_valid(_poll_timer) and _poll_timer.is_stopped() and not demo():
		_poll_timer.start()


## Lokale Musik hat sich geändert (Titel, Pause, Warteschlange): wie ein neuer Stand von Spotify.
func _on_local() -> void:
	if beide() and aktiv != "lokal" and local.wants_play():
		_zu_lokal()
	if not local_on():
		return
	var n: Dictionary = local.now_dict()
	var q: Array = local.upcoming()
	var queue_new := q != queue_list
	now = n
	queue_list = q
	updated.emit()
	if queue_new:
		lists_changed.emit("queue")


## Andere Anmeldung gewählt (Einstellungen): neuer Schlüssel, Listen neu.
func _mode_changed() -> void:
	_token = ""
	_tok_mode = ""
	_client_token = ""
	_rate_until = { "app": 0, "eigen": 0 }
	dealer_close("Anmeldung gewechselt")
	_cluster_raw = {}
	_target_dev = ""
	_gewollt_dev = ""
	me = {}
	_fy_at = 0
	spotify_mixes = []
	mix_ways = ""
	_catalogs.clear()
	need_login = false
	if problem != "":
		_set_problem("")
	updated.emit()
	if has_spotify() and not demo():
		load_playlists()


func progress_ms() -> int:
	if local_on():
		return local.position_ms()
	if now.is_empty():
		return 0
	if not now.get("playing", false):
		return _progress_base
	var p := _progress_base + Time.get_ticks_msec() - _progress_at
	var dur := int(now.get("duration", 0))
	if demo() and dur > 0:
		return p % dur          # Vorführung: der Titel läuft immer weiter, statt bei 0:00 zu stehen
	return mini(p, dur)


# --- Steuerung -----------------------------------------------------------------

## Medientasten statt Spotify: ohne Spotify, oder wenn das, was läuft, von Windows kommt.
func _keys_only() -> bool:
	return mode() == "tasten" or (not local_on() and not has_spotify()) or str(now.get("source", "")) == "windows"


## Medientaste an die Musik-App (nur sie): Der Helfer sucht die Mediensitzung einer Musik-App
## (MUSIC_APPS) und schaltet dort; läuft gerade nur ein Browser-Video o. Ä., passiert nichts.
## Früher ging die Taste an Windows – das schaltete, was zuletzt Ton hatte (z. B. YouTube).
## by_user: du hast gerade selbst gedrückt. Nur dann darf der Helfer, wenn gar keine Sitzung
## steuerbar ist, die Medientaste an Windows schicken (Ruhemodus und Spiel-Profile nie).
func media_key(action: String, by_user := true) -> void:
	var a := media_filter()
	a["action"] = action
	a["user"] = by_user
	if str(now.get("source", "")) == "windows":
		a["app"] = str(now.get("app", ""))
	Helper.run("media", a)


## by_user = false: Uzai hält von sich aus an oder setzt fort (Ruhemodus, Spiel-Profil).
func play_pause(by_user := true) -> void:
	if local_on():
		local.toggle()
		return
	if _keys_only():
		media_key("playpause", by_user)
		_later_poll()
		return
	var playing := bool(now.get("playing", false))
	if not now.is_empty():
		now["playing"] = not playing
		_progress_base = progress_ms()
		_progress_at = Time.get_ticks_msec()
		updated.emit()
	if not await _control(HTTPClient.METHOD_PUT, "/me/player/" + ("pause" if playing else "play")):
		media_key("playpause", by_user)
	_later_poll()


func next() -> void:
	if local_on():
		local.next()
		return
	if _keys_only():
		media_key("next")
		_later_poll()
		return
	if not await _control(HTTPClient.METHOD_POST, "/me/player/next"):
		media_key("next")
	_later_poll(true)


func previous() -> void:
	if local_on():
		local.previous()
		return
	if _keys_only():
		media_key("prev")
		_later_poll()
		return
	if not await _control(HTTPClient.METHOD_POST, "/me/player/previous"):
		media_key("prev")
	_later_poll(true)


func set_shuffle(on: bool) -> void:
	if local_on():
		local.set_shuffle(on)
		return
	now["shuffle"] = on
	updated.emit()
	await _control(HTTPClient.METHOD_PUT, "/me/player/shuffle?state=%s" % ("true" if on else "false"))
	_later_poll(true)


## Wiederholen: aus → Playlist → Titel → aus
func cycle_repeat() -> void:
	if local_on():
		local.cycle_repeat()
		return
	var nxt := { "off": "context", "context": "track", "track": "off" }.get(str(now.get("repeat", "off")), "off") as String
	now["repeat"] = nxt
	updated.emit()
	await _control(HTTPClient.METHOD_PUT, "/me/player/repeat?state=" + nxt)


func seek_to(ms: int) -> void:
	if local_on():
		local.seek_to(ms)
		return
	ms = clampi(ms, 0, maxi(0, int(now.get("duration", 0)) - 1000))
	_progress_base = ms
	_progress_at = Time.get_ticks_msec()
	updated.emit()
	await _control(HTTPClient.METHOD_PUT, "/me/player/seek?position_ms=%d" % ms)


func seek(delta_ms: int) -> void:
	seek_to(progress_ms() + delta_ms)


## Lieblingssong an/aus (ohne ID: der laufende Titel). Speichert über /me/library.
func toggle_like(track_id := "") -> void:
	var id := track_id if track_id != "" else str(now.get("id", ""))
	if id == "" or not has_spotify() or id.begins_with("lokal:"):
		return
	var is_now := id == str(now.get("id", ""))
	var liked := bool(now.get("liked", false)) if is_now else is_liked(id)
	# Für die Rücknahme: der entfernte Eintrag und sein Platz.
	var alt := {}
	var platz := 0
	if is_now:
		now["liked"] = not liked
	if liked:
		for i in liked_list.size():
			if str(liked_list[i].id) == id:
				alt = liked_list[i]
				platz = i
				break
		liked_list = liked_list.filter(func(t): return str(t.id) != id)
	else:
		var t := find_track(id)
		if not t.is_empty() and not is_liked(id):
			liked_list.push_front(t)
	updated.emit()
	lists_changed.emit("liked")
	var ok := await library_set(["spotify:track:" + id], not liked)
	if not ok:
		# Zurück auf den alten Stand, damit Uzai nichts anzeigt, was Spotify nicht hat. Der entfernte Eintrag kommt
		# an seinen Platz zurück: Neu zusammengesucht (find_track) fehlte ein Titel, der nur unter den Lieblingssongs
		# stand, bis zum nächsten Laden – und jeder andere stand danach ganz oben.
		if is_now and str(now.get("id", "")) == id:
			now["liked"] = liked
		if liked:
			var t2: Dictionary = alt if not alt.is_empty() else find_track(id)
			if not t2.is_empty() and not is_liked(id):
				liked_list.insert(clampi(platz, 0, liked_list.size()), t2)
		else:
			liked_list = liked_list.filter(func(t): return str(t.id) != id)
		error = "Spotify hat den Lieblingssong nicht gespeichert. Gleich nochmal versuchen."
		updated.emit()
		lists_changed.emit("liked")


## Einen bekannten Titel nach ID finden (laufend, Warteschlange, Listen).
func find_track(id: String) -> Dictionary:
	if str(now.get("id", "")) == id and str(now.get("uri", "")) != "":
		var t := {}
		for k in ["id", "uri", "title", "artist", "album", "art", "duration"]:
			t[k] = now.get(k, "")
		t["art_big"] = str(now.get("art", ""))
		t["explicit"] = false
		t["added"] = 0
		return t
	for list in [queue_list, recent_list, top_tracks, top_long, liked_list]:
		for t in list:
			if t is Dictionary and str(t.get("id", "")) == id:
				return t
	return {}


func play_playlist(uri: String) -> void:
	if uri == "" or mode() == "lokal":
		return
	_zu_spotify()
	await _control(HTTPClient.METHOD_PUT, "/me/player/play", { "context_uri": uri })
	_later_poll(true)


## Album oder Playlist von vorn abspielen (wie play_playlist; liefert, ob Spotify es angenommen hat).
func play_context(uri: String) -> bool:
	if uri == "" or mode() == "lokal":
		return false
	_zu_spotify()
	var ok := await _control(HTTPClient.METHOD_PUT, "/me/player/play", { "context_uri": uri })
	_later_poll(true)
	return ok


## Einen Titel in seiner Playlist oder seinem Album starten (danach läuft die Liste weiter).
func play_in(context_uri: String, track_uri: String) -> void:
	_zu_spotify()
	await _control(HTTPClient.METHOD_PUT, "/me/player/play", { "context_uri": context_uri, "offset": { "uri": track_uri } })
	_later_poll(true)


## Eine lose Liste von Titeln ab Position idx (Lieblingssongs, Zuletzt gehört, Suche, Mixe).
## Eigene Titel spielen über den eigenen Player (wird so die Quelle), alle anderen über Spotify.
func play_list(tracks: Array, idx: int) -> void:
	var first: Variant = tracks[idx] if idx >= 0 and idx < tracks.size() else null
	if mode() == "lokal" or (first is Dictionary and str(first.get("uri", "")).begins_with("lokal:")):
		# Ein ganzes Album: „aus <Album>“ unter „Als Nächstes“.
		var ak := str(tracks[idx].get("akey", "")) if first is Dictionary else ""
		var whole := ak != "" and tracks.all(func(t: Variant) -> bool: return t is Dictionary and str(t.get("akey", "")) == ak)
		local.play_tracks(tracks, idx, ak if whole else "", str(tracks[idx].get("album", "")) if whole else "")
		return
	_zu_spotify()
	var uris: Array = []
	for t in tracks.slice(idx, idx + 100):
		if t is Dictionary and str(t.get("uri", "")) != "":
			uris.append(str(t.uri))
	if uris.is_empty():
		return
	await _control(HTTPClient.METHOD_PUT, "/me/player/play", { "uris": uris })
	_later_poll(true)


func enqueue(uri: String) -> void:
	if uri.begins_with("lokal:"):
		if lokal_da():
			for t in local.tracks:
				if str(t.uri) == uri:
					local.enqueue(t)
					break
		return
	await _control(HTTPClient.METHOD_POST, "/me/player/queue?uri=" + uri.uri_encode())
	_later_poll(true)


## Lautstärke des Spotify-Players (Web-API). false, wenn Spotify ablehnt (kein Premium, Gerät
## ohne eigene Lautstärke, kein aktives Gerät) – dann steht der alte Wert wieder da. Ohne den
## Umweg über _control: Für die Lautstärke wird nie ein Gerät gewechselt oder Spotify gestartet.
func set_volume_percent(v: int) -> bool:
	v = clampi(v, 0, 100)
	if local_on():
		local.set_volume(v)
		return true
	var old := int(now.get("volume", -1))
	now["volume"] = v
	updated.emit()
	if demo():
		return true
	if app_mode():
		# Gebündelt: Der Regler zeigt jeden Schritt sofort, an Spotify geht nur der letzte Wert,
		# höchstens alle 300 ms (früher eine Anfrage je Schritt samt Zustandsabfrage – Spotify bremste
		# mit 429). Nach einer Bremse ruht die Lautstärke über Spotify 30 s; dann regelt Uzai die
		# Spotify-App auf diesem PC wie im Lautstärkemixer (change_volume).
		if Time.get_ticks_msec() < _vol_hold_ms:
			now["volume"] = old
			updated.emit()
			return false
		_vol_want = v
		if _vol_old < 0:
			_vol_old = old
		if not _vol_busy:
			_vol_send()
		return true
	var r := await _api(HTTPClient.METHOD_PUT, "/me/player/volume?volume_percent=%d" % v)
	if r.ok:
		return true
	_log("Lautstärke abgelehnt: HTTP %d %s" % [int(r.code), error_reason(r)])
	if int(now.get("volume", -1)) == v:
		now["volume"] = old
		updated.emit()
	return false


var _vol_want := -1                 ## noch zu sendende Lautstärke (Spotify Connect), -1: keine
var _vol_old := -1                  ## Wert vor dem ersten Schritt (falls Spotify ablehnt)
var _vol_busy := false
var _vol_last_ms := -100000         ## zuletzt gesendet
var _vol_hold_ms := 0               ## Spotify bremst: bis dahin keine Lautstärke über Connect
var _vol_target := ""               ## Gerät der letzten Lautstärke (spart die Zustandsabfrage)
var _vol_target_ms := -100000


## Sendet den jeweils letzten gewünschten Wert, höchstens alle 300 ms, bis nichts mehr wartet.
func _vol_send() -> void:
	_vol_busy = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird _vol_busy hier trotzdem gelöst. Sonst ließe sich
	# die Lautstärke bis zum Neustart nicht mehr stellen.
	await _vol_senden()
	_vol_busy = false


func _vol_senden() -> void:
	while _vol_want >= 0:
		var wait := SpotifyPc.vol_wait_ms(Time.get_ticks_msec(), _vol_last_ms)
		if wait > 0:
			await get_tree().create_timer(wait / 1000.0).timeout
		var v := _vol_want
		_vol_want = -1
		var target := _vol_target if Time.get_ticks_msec() - _vol_target_ms < 20000 else ""
		if target == "":
			var raw := await _cluster_read()
			target = Intern.pick_target(Intern.cluster(raw, _connect_dev, _now_ms()), OS.get_environment("COMPUTERNAME"), spotify_ort(),
					_gewollt_dev) if not raw.is_empty() else ""
		if target == "":
			_vol_fail(v, "kein Gerät")
			continue
		_vol_last_ms = Time.get_ticks_msec()
		var rv := await _spc(HTTPClient.METHOD_PUT, "/connect-state/v1/connect/volume/from/%s/to/%s" % [_connect_dev, target],
				{ "volume": roundi(v / 100.0 * 65535.0) })
		var code := int(rv.get("code", 0))
		if rv.ok:
			_vol_target = target
			_vol_target_ms = Time.get_ticks_msec()
			if _vol_want < 0:
				_log("Connect: Lautstärke %d %% → %s: HTTP %d" % [v, _dev_name(target), code])
				_vol_old = -1
			continue
		_vol_target = ""
		if code == 429:
			_vol_hold_ms = Time.get_ticks_msec() + 30000
			_vol_want = -1
		_vol_fail(v, "HTTP %d" % code)


func _vol_fail(v: int, why: String) -> void:
	_log("Connect: Lautstärke %d %% abgelehnt (%s)" % [v, why])
	if int(now.get("volume", -1)) == v and _vol_want < 0 and _vol_old >= 0:
		now["volume"] = _vol_old
		updated.emit()
	_vol_old = -1


## Pegel der Musik-App bzw. der Spotify-App auf diesem PC (ihre Audiositzung), -1: unbekannt.
## Zeigt der Lautstärke-Regler, wenn Spotify selbst keinen Wert meldet oder Windows die Quelle ist.
var app_level := -1
var _app_level_key := ""


## Lautstärke der Musik ändern (Musik-Bereich „Läuft gerade“ und Guide): nur der Musik-Player,
## nie die Gesamtlautstärke von Windows.
## - Spotify-Konto, Player meldet eine Lautstärke: über die Web-API (wie am Handy).
## - Lehnt Spotify ab (kein Premium, Gerät ohne Lautstärke) und spielt es auf diesem PC: die
##   Audiositzung der Spotify-App wie im Lautstärkemixer.
## - Musik-App über Windows (Quelle „windows“): deren Audiositzung.
## Rückgabe { ok, level, mute, via ("spotify" | "app"), why ("" | "keine_musik" | "kein_ton" |
## "spotify_fest" | "fehler") }.
func change_volume(delta: int) -> Dictionary:
	var out := { "ok": false, "level": -1, "mute": false, "via": "", "why": "" }
	if local_on():
		if now.is_empty():
			out.why = "keine_musik"
			return out
		local.set_volume(int(local.volume) + delta)
		return { "ok": true, "level": int(local.volume), "mute": int(local.volume) == 0, "via": "lokal", "why": "" }
	var plan := volume_plan(now, has_spotify(), Config.is_windows())
	if plan == "":
		out.why = "keine_musik"
		return out
	if plan == "spotify":
		var nv := clampi(int(now.get("volume", 0)) + delta, 0, 100)
		if await set_volume_percent(nv):
			return { "ok": true, "level": nv, "mute": false, "via": "spotify", "why": "" }
		plan = "spotify_app" if Config.is_windows() and _here(now) else "spotify_fest"
	if plan == "spotify_fest":
		out.why = "spotify_fest"
		return out
	var r: Dictionary
	if demo() and not Config.is_windows():
		app_level = clampi((app_level if app_level >= 0 else 70) + delta, 0, 100)
		r = { "found": true, "level": app_level, "mute": false, "error": false }
	elif plan == "spotify_app":
		r = await Helper.app_volume({ "keys": ["spotify"] }, delta)
	else:
		r = await app_volume(delta)
	if bool(r.get("found", false)):
		app_level = int(r.level)
		_app_level_key = level_key(now)
		updated.emit()
		return { "ok": true, "level": int(r.level), "mute": bool(r.get("mute", false)), "via": "app", "why": "" }
	if bool(r.get("error", false)):
		out.why = "fehler"
	else:
		out.why = "spotify_fest" if plan == "spotify_app" else "kein_ton"
	return out


## Spielt der Spotify-Player auf einem PC (dann vielleicht diesem; die Audiositzung findet der
## Helfer nur, wenn die Spotify-App hier Ton macht)?
static func _here(n: Dictionary) -> bool:
	return str(n.get("device_type", "")) in ["Computer", ""]


## Wie die Lautstärke der laufenden Musik geändert wird: "spotify" (Web-API), "spotify_app"
## (Spotify-App auf diesem PC, Spotify meldet keine Lautstärke), "spotify_fest" (Gerät woanders
## ohne Lautstärke), "app" (Musik-App über Windows) oder "" (nichts läuft).
static func volume_plan(n: Dictionary, spotify: bool, windows: bool) -> String:
	if n.is_empty() or str(n.get("title", "")) == "":
		return ""
	if str(n.get("source", "")) == "windows":
		return "app"
	if not spotify:
		return ""
	if int(n.get("volume", -1)) >= 0:
		return "spotify"
	return "spotify_app" if windows and _here(n) else "spotify_fest"


static func level_key(n: Dictionary) -> String:
	return str(n.get("app", "")) + "|" + str(n.get("device", ""))


## Pegel für den Regler: Spotify-Wert, sonst der zuletzt gelesene der App (-1: unbekannt).
func shown_volume() -> int:
	if str(now.get("source", "")) != "windows" and int(now.get("volume", -1)) >= 0:
		return int(now.volume)
	if app_level >= 0 and _app_level_key == level_key(now):
		return app_level
	return -1


## Pegel der Musik-App einmal lesen (ohne ihn zu ändern), damit der Regler gleich etwas zeigt.
func read_app_level() -> void:
	if local_on():
		return
	var plan := volume_plan(now, has_spotify(), Config.is_windows())
	if not Config.is_windows() or not plan in ["app", "spotify_app"]:
		return
	var key := level_key(now)
	var r: Dictionary
	if plan == "spotify_app":
		r = await Helper.app_volume({ "keys": ["spotify"] }, 0)
	else:
		r = await app_volume(0)
	if bool(r.get("found", false)) and key == level_key(now):
		app_level = int(r.level)
		_app_level_key = key
		updated.emit()


## Steuerbefehl an Spotify. Kein aktives Gerät: auf diesen PC wechseln (Spotify startet dafür
## notfalls unsichtbar im Hintergrund) und nochmal. false, wenn Spotify nicht will – dann
## greifen beim Abspielen und Weiterschalten die Medientasten.
func _control(method: int, path: String, payload: Variant = null) -> bool:
	if demo():
		_demo_control(path, payload)
		return true
	if app_mode():
		# Wie die Spotify-App: über Spotify Connect an die Spotify-App (am liebsten auf diesem PC).
		var cr := await _connect_control(method, path, payload)
		if bool(cr.handled):
			if bool(cr.ok):
				error = ""
				return true
			if int(cr.code) == 404:
				# Kein Gerät bereit: eins wählen bzw. Spotify unsichtbar im Hintergrund starten (ohne Fokus).
				var dev := await ensure_device()
				if dev == "":
					updated.emit()
					return false
				_target_dev = dev
				cr = await _connect_control(method, path, payload)
				if bool(cr.ok):
					error = ""
					return true
			# Lässt Spotify gezieltes Starten nicht zu (etwa ohne Premium): in der Spotify-App öffnen.
			if int(cr.get("code", 0)) in [400, 403] and await _in_app_oeffnen(payload):
				error = ""
				return true
			error = connect_error(int(cr.get("code", 0)))
			updated.emit()
			if int(cr.get("code", 0)) == CODE_STUMM:
				_stumm_melden(error)
			return false
		if grundmodus() and _token == "" and await _in_app_oeffnen(payload):
			# Grundmodus ohne Schlüssel: kein Spotify Connect – Titel bzw. Liste in der Spotify-App öffnen.
			error = ""
			return true
	var r := await _api(method, path, payload)
	if r.ok:
		error = ""
		return true
	var code := int(r.code)
	if code == 404:
		# 404 heißt meist: kein aktives Gerät. Läuft eins, ist es die Sache selbst (gesperrte Playlist).
		var devs := await devices()
		if devs.filter(func(d): return bool(d.active)).is_empty():
			var dev := await ensure_device(devs)
			if dev == "":
				# Kein Gerät zu finden oder zu starten: der Hinweis dazu steht schon in error.
				updated.emit()
				return false
			await _api(HTTPClient.METHOD_PUT, "/me/player", { "device_ids": [dev], "play": false })
			await get_tree().create_timer(0.5).timeout
			r = await _api(method, path, payload)
			if r.ok:
				error = ""
				return true
			code = int(r.code)
	error = control_error(code, error_reason(r), payload is Dictionary and (payload as Dictionary).has("context_uri"), error)
	updated.emit()
	return false


## „Angenommen, aber nicht gestartet“ blieb bisher ohne jede Meldung, wo die aufrufende Stelle selbst nichts zeigt
## (eine Titelzeile in einer Playlist): hier einmal zentral – außer die Stelle hat es gerade selbst gemeldet.
func _stumm_melden(text: String) -> void:
	await get_tree().create_timer(0.3).timeout
	if not Toasts.eben_gezeigt(text):
		Toasts.show_toast("Spotify spielt nicht", text, "warning", { "ms": 6000 })


## Titel bzw. Liste per spotify:-Adresse in der Spotify-App am PC öffnen (wenn Spotify Connect gezieltes Starten
## nicht zulässt). Pause und Weiter laufen danach über die Mediensitzung von Windows. true, wenn geöffnet.
func _in_app_oeffnen(payload: Variant) -> bool:
	var uri := app_uri(payload)
	if uri == "" or demo() or not Config.is_windows():
		return false
	OS.shell_open(uri)
	_log("Abspielen: in der Spotify-App geöffnet (%s)" % uri.get_slice(":", 1))
	Toasts.show_toast("In Spotify geöffnet", "Abspielen in der Spotify-App.", "music", { "ms": 3000, "quiet": true })
	_later_poll(true)
	# Spotify kommt dabei nach vorn: Uzai gleich zurückholen.
	await get_tree().create_timer(1.5).timeout
	if not Launcher.in_game and Helper.available:
		Helper.run("focus", { "pid": OS.get_process_id() })
	return true


## spotify:-Adresse für „in der Spotify-App öffnen“ aus einem Abspielbefehl der Web-API: die Liste (Playlist,
## Album, Künstler), sonst der erste Titel. Nur geprüfte Formen, sonst "".
static func app_uri(payload: Variant) -> String:
	if not (payload is Dictionary):
		return ""
	var ctx := str((payload as Dictionary).get("context_uri", ""))
	if SpotifyPc.uri_ok(ctx) or Verlauf.uri_ok(ctx, ["track"]):
		return ctx
	var uris: Variant = (payload as Dictionary).get("uris")
	if uris is Array and not (uris as Array).is_empty() and Verlauf.uri_ok(uris[0], ["track"]):
		return str(uris[0])
	return ""


## Verständlicher Hinweis zu einem abgelehnten Steuerbefehl.
static func control_error(code: int, reason: String, with_context: bool, current := "") -> String:
	if reason == "PREMIUM_REQUIRED":
		return "Steuern geht nur mit Spotify Premium."
	if code == 429:
		return "Spotify bremst gerade (zu viele Anfragen). Gleich nochmal versuchen."
	if code in [403, 404] and with_context:
		return "Diese Liste lässt Spotify über eigene Apps nicht abspielen."
	if code == 403:
		return "Spotify hat das abgelehnt. Steuern geht nur mit Premium."
	if code == 0:
		return current if current != "" else "Spotify ist gerade nicht erreichbar."
	return current if current != "" else "Spotify hat nicht reagiert. Gleich nochmal versuchen."


## Grund aus einer Fehlerantwort von Spotify ({ error: { status, message, reason } }).
static func error_reason(r: Dictionary) -> String:
	var d: Variant = r.get("data")
	if d is Dictionary and (d as Dictionary).get("error") is Dictionary:
		var e: Dictionary = (d as Dictionary).error
		return str(e.get("reason", "")) if e.get("reason") != null else ""
	return ""


## Geräte, auf denen Spotify spielen kann (PC, Handy, Fernseher, Lautsprecher).
func devices() -> Array:
	if demo():
		return [{ "id": "pc", "name": "Wohnzimmer-PC", "type": "Computer", "active": str(now.get("device", "")) == "Wohnzimmer-PC" },
			{ "id": "handy", "name": "Handy", "type": "Smartphone", "active": str(now.get("device", "")) == "Handy" },
			{ "id": "kueche", "name": "Küche", "type": "Speaker", "active": str(now.get("device", "")) == "Küche" }]
	if app_mode():
		var raw := await _cluster_read(true)
		if not raw.is_empty():
			return Intern.cluster(raw, _connect_dev, _now_ms()).devices
	var r := await _api(HTTPClient.METHOD_GET, "/me/player/devices")
	var out: Array = []
	if r.ok and r.data is Dictionary:
		for d in Fremd.zeilen(r.data, "devices"):
			if d is Dictionary and str(d.get("id", "")) != "" and d.get("id") != null:
				out.append({ "id": str(d.get("id", "")), "name": Fremd.text(d.get("name")), "type": Fremd.text(d.get("type")), "active": Fremd.ja(d.get("is_active")),
					"restricted": Fremd.ja(d.get("is_restricted")) })
	return out


## Bestes Gerät aus der Liste: das laufende, sonst dieser PC (gleicher Name), sonst ein PC.
static func pick_device(devs: Array, pc_name := "") -> String:
	for d in devs:
		if bool(d.get("active", false)):
			return str(d.id)
	var pc := pc_name.to_lower()
	for d in devs:
		if str(d.get("type", "")) == "Computer" and pc != "" and str(d.get("name", "")).to_lower() == pc:
			return str(d.id)
	for d in devs:
		if str(d.get("type", "")) == "Computer":
			return str(d.id)
	return ""


## Ein Gerät, auf dem Spotify jetzt spielen kann. Ist keins offen, startet Uzai Spotify auf diesem
## PC im Hintergrund (Windows) und wartet, bis es sich meldet – ohne Fensterwechsel.
func ensure_device(devs: Array = []) -> String:
	if demo():
		return "pc"
	if devs.is_empty():
		devs = await devices()
	# „Auf diesem PC“ (Voreinstellung): nur die Spotify-App hier zählt – ist sie nicht offen, startet Uzai sie,
	# statt das Gerät zu nehmen, das gerade oder zuletzt lief. Sonst wie früher das laufende zuerst.
	var pc := OS.get_environment("COMPUTERNAME")
	var pick := Intern.dieser_pc(devs, pc) if spotify_ort() == "pc" else pick_device(devs, pc)
	if pick != "":
		return pick
	pick = await start_here()
	if pick != "":
		return pick
	# Kein PC (Spotify ist hier nicht installiert oder meldet sich nicht): ein anderes offenes Gerät
	# (Handy, Lautsprecher) nehmen – sonst ginge gar nichts.
	if not devs.is_empty():
		return str(devs[0].id)
	if error == "":
		error = "Spotify ist auf keinem Gerät offen. Spotify auf diesem PC einmal öffnen – dann steuert Uzai es von hier."
	return ""


## Nur PCs: der mit dem Namen dieses Rechners, sonst der erste.
## Ist dieser PC (Spotify-App am PC) unter den Geräten? Andere Computer (Laptop, Webplayer) zählen nicht.
static func pc_dabei(devs: Array, pc_name := "") -> bool:
	var pc := pc_name.to_lower()
	for d in devs:
		if str(d.get("type", "")) == "Computer" and (pc == "" or str(d.get("name", "")).to_lower() == pc):
			return true
	return false


static func pick_pc(devs: Array, pc_name := "") -> String:
	var pc := pc_name.to_lower()
	var any := ""
	for d in devs:
		if str(d.get("type", "")) != "Computer":
			continue
		if pc != "" and str(d.get("name", "")).to_lower() == pc:
			return str(d.id)
		if any == "":
			any = str(d.id)
	return any


## Spotify auf diesem PC minimiert im Hintergrund starten (Helfer) und warten, bis es sich bei
## Spotify als Gerät meldet. Gibt die Geräte-ID zurück ("" wenn es nicht klappt).
func start_here() -> String:
	if demo():
		return "pc"
	var name := OS.get_environment("COMPUTERNAME")
	var have := pick_pc(await devices(), name)
	if have != "":
		return have
	if not (Config.is_windows() and Helper.available):
		if error == "":
			error = "Spotify ist auf keinem Gerät offen. Spotify auf diesem PC einmal öffnen – dann steuert Uzai es von hier."
		return ""
	if starting:
		while starting:
			await get_tree().create_timer(0.3).timeout
		return pick_pc(await devices(), name)
	starting = true
	updated.emit()
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird „starting“ hier trotzdem gelöst. Sonst warteten
	# alle späteren Aufrufe in der Schleife oben für immer.
	var pick := await _spotify_starten(name)
	starting = false
	updated.emit()
	return pick


## Startet Spotify auf diesem PC und wartet, bis es sich als Gerät meldet. Gibt die Gerätekennung zurück ("" = nicht da).
func _spotify_starten(name: String) -> String:
	Toasts.show_toast("Spotify startet im Hintergrund", "Einen Moment, dann geht es los.", "music", { "ms": 3000, "quiet": true })
	var r := await Helper.run_once("spotify-start", { "wait": 10, "hide": false, "uzai_pid": OS.get_process_id() })
	var res: Dictionary = r.result if r.get("result") is Dictionary else {}
	var pick := ""
	if r.ok and bool(res.get("ok", false)):
		var t0 := Time.get_ticks_msec()
		var lost := 0
		while Time.get_ticks_msec() - t0 < 20000 and pick == "":
			# Springt Spotify beim Anmelden doch nach vorn, gleich zurückholen – nicht erst nach
			# bis zu 20 s (so lange reagierte der Controller früher nicht). Nur wenn Uzai den Fokus
			# wirklich verloren hat und höchstens dreimal: Das Zurückholen (Alt-Notlösung) blitzt kurz.
			if not get_window().has_focus() and not Launcher.in_game and lost < 3:
				lost += 1
				Helper.run("focus", { "pid": OS.get_process_id() })
			await get_tree().create_timer(1.2).timeout
			pick = pick_pc(await devices(), name)
		if not Launcher.in_game and not get_window().has_focus():
			Helper.run("focus", { "pid": OS.get_process_id() })
		if pick == "":
			error = "Spotify ist gestartet, meldet sich aber nicht. Ist Spotify auf diesem PC angemeldet?"
	else:
		error = "Spotify ist auf diesem PC nicht installiert. Auf dem Handy öffnen, dann erscheint es hier."
	return pick


## Wiedergabe auf ein anderes Gerät legen. "" = gewechselt (Spotify meldet das Gerät als
## laufend), sonst der Grund. Spotify braucht dafür ein, zwei Sekunden; schläft das Gerät
## (Lautsprecher, Handy im Hintergrund), wird es einmal geweckt und nochmal versucht.
func transfer(device_id: String) -> String:
	_zu_spotify()
	if demo():
		var devs := await devices()
		for d in devs:
			if str(d.id) == device_id:
				now["device"] = str(d.name)
		updated.emit()
		return ""
	var target := ""
	for d in await devices():
		if str(d.id) == device_id:
			target = str(d.name)
			if bool(d.get("restricted", false)):
				return "%s lässt sich nicht von anderen Apps steuern (Spotify sperrt das bei diesem Gerät)." % target
	if app_mode() and not _cluster_raw.is_empty():
		# Wie die Spotify-App: Wiedergabe über Spotify Connect hinüberlegen.
		var rt := await _spc(HTTPClient.METHOD_POST, "/connect-state/v1/connect/transfer/from/%s/to/%s" % [_connect_dev, device_id],
				{ "transfer_options": { "restore_paused": "restore" } })
		_log("Connect: Gerät wechseln → %s: HTTP %d" % [target, int(rt.get("code", 0))])
		_target_dev = device_id
		# Selbst gewählt: Ein fremdes Gerät gilt, solange es spielt; dieser PC hebt die Wahl auf.
		_gewollt_dev = "" if device_id == Intern.dieser_pc(Intern.cluster(_cluster_raw, _connect_dev, 0).devices, OS.get_environment("COMPUTERNAME")) else device_id
		_gewollt_ms = Time.get_ticks_msec()
		if not rt.ok:
			return transfer_error(int(rt.get("code", 0)), "", target)
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 6000:
			for d in await devices():
				if str(d.id) == device_id and bool(d.active):
					await poll()
					return ""
			await get_tree().create_timer(0.8).timeout
		await poll()
		return "%s hat die Wiedergabe nicht übernommen. Ist Spotify dort offen und angemeldet?" % (target if target != "" else "Das Gerät")
	var r := await _api(HTTPClient.METHOD_PUT, "/me/player", { "device_ids": [device_id], "play": true })
	if not r.ok and int(r.code) in [404, 502, 503]:
		# Gerät schläft oder war kurz weg: einmal ohne Abspielen wecken, dann nochmal.
		await _api(HTTPClient.METHOD_PUT, "/me/player", { "device_ids": [device_id], "play": false })
		await get_tree().create_timer(1.0).timeout
		r = await _api(HTTPClient.METHOD_PUT, "/me/player", { "device_ids": [device_id], "play": true })
	if not r.ok:
		var why := transfer_error(int(r.code), error_reason(r), target)
		_log("Gerät wechseln auf %s: HTTP %d %s" % [target, int(r.code), error_reason(r)])
		return why
	# Bestätigen: warten, bis Spotify das neue Gerät als laufend meldet (bis 6 s).
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().create_timer(0.8).timeout
		for d in await devices():
			if str(d.id) == device_id and bool(d.active):
				await poll()
				return ""
	await poll()
	return "%s hat die Wiedergabe nicht übernommen. Ist Spotify dort offen und angemeldet?" % (target if target != "" else "Das Gerät")


## Gerät wechseln mit Rückmeldung (für alle „Abspielen auf …“-Auswahlen).
func switch_to(device_id: String) -> void:
	Toasts.show_toast("Wechsle Gerät …", "", "speaker", { "ms": 1500, "quiet": true })
	var err := await transfer(device_id)
	if err == "":
		Toasts.show_toast("Läuft jetzt auf " + str(now.get("device", "dem Gerät")), "", "speaker", { "sound": "select" })
	else:
		Toasts.show_toast("Gerät nicht gewechselt", err, "warning", { "ms": 6000 })


static func transfer_error(code: int, reason: String, target: String) -> String:
	var dev := target if target != "" else "Das Gerät"
	if reason == "PREMIUM_REQUIRED" or code == 403:
		return "Spotify erlaubt das Wechseln des Geräts nur mit Premium."
	if code == 404:
		return "%s ist für Spotify gerade nicht erreichbar. Spotify dort einmal öffnen, dann nochmal." % dev
	if code == 429:
		return "Spotify bremst gerade. Gleich nochmal versuchen."
	if code == 0:
		return "Spotify ist gerade nicht erreichbar."
	return "Spotify hat den Wechsel abgelehnt. Gleich noch einmal versuchen."


## Link zum laufenden Titel (zum Verschicken an Freunde und als QR-Code fürs Handy).
func share_link() -> String:
	var id := str(now.get("id", ""))
	var uri := str(now.get("uri", ""))
	if id == "" or not uri.begins_with("spotify:track:"):
		return ""
	return "https://open.spotify.com/track/" + uri.get_slice(":", 2)


## Lautstärke der Musik-App, deren Titel Windows meldet (Quelle „windows“), über ihre eigene
## Audiositzung wie im Lautstärkemixer – nie die Gesamtlautstärke von Windows (früher änderten
## Guide und Musik-Bereich ohne Spotify-Konto den Ton von allem). delta in Prozentpunkten.
## Rückgabe { found, level, mute } (siehe Helper.app_volume).
func app_volume(delta: int) -> Dictionary:
	var keys := audio_keys(str(now.get("app", "")))
	if keys.is_empty() or str(now.get("source", "")) != "windows":
		return { "found": false, "level": -1, "mute": false, "error": false }
	return await Helper.app_volume({ "keys": keys }, delta)


func _later_poll(with_queue := false) -> void:
	await get_tree().create_timer(0.6).timeout
	await poll()
	if with_queue:
		load_queue()


# --- Abfragen ------------------------------------------------------------------

## Im Spiel (Guide zu) nur alle 15 s nachsehen: Die Abfrage alle 2–4 s lief sonst das ganze
## Spiel über weiter (Windows-Mediensitzung über den Helfer bzw. Spotify-Netz). Der Guide fragt
## beim Öffnen ohnehin sofort; der Status „Hört …“ bei Discord folgt so mit kurzer Verzögerung.
var _last_poll_ms := -100000


func poll() -> void:
	if demo() or local_on():
		return
	await _poll_spotify()
	if local_on():
		_on_local()             # unterwegs zur eigenen Musik gewechselt: deren Stand gilt


## Warteschlange von Spotify, nur solange Spotify die Quelle ist.
func load_queue() -> void:
	if local_on():
		return
	await super()
	if local_on():
		_on_local()


## Abfrage bei Spotify bzw. der Windows-Mediensitzung (ohne die Weiche in poll).
func _poll_spotify() -> void:
	if Launcher.in_game and not Launcher.guide_open and Time.get_ticks_msec() - _last_poll_ms < 15000:
		return
	_last_poll_ms = Time.get_ticks_msec()
	# Seltener fragen, wenn niemand hinsieht (spart das Kontingent der eigenen App).
	if is_instance_valid(_poll_timer) and not use_windows():
		var want := POLL_SEEN if music_seen() else POLL_HIDDEN
		if not is_equal_approx(_poll_timer.wait_time, want):
			_poll_timer.wait_time = want
	if use_windows():
		await _poll_windows()
		return
	if not has_spotify():
		return
	if grundmodus() and music_seen():
		pc_lib_refresh()
	if app_mode():
		# Wie die Spotify-App: Spotify Connect. Im Spiel ohne Guide reicht die Mediensitzung von
		# Windows (ganz ohne Netz); der Dealer schließt dann von selbst.
		if not (Launcher.in_game and not Launcher.guide_open) and await _poll_connect():
			return
		if Config.is_windows() and Helper.available:
			await _poll_windows()
		elif not now.is_empty():
			now = {}
			updated.emit()
		return
	var r := await _api(HTTPClient.METHOD_GET, "/me/player?additional_types=track")
	if r.code == 204 or not r.ok or not (r.data is Dictionary):
		# Spotify meldet nichts (kein aktives Gerät) oder lehnt ab: dann zeigt Uzai, was Windows
		# gerade abspielt. Auch die Spotify-App am PC meldet sich dort.
		if Config.is_windows() and Helper.available:
			await _poll_windows()
		elif not now.is_empty() and (r.code == 204 or r.ok):
			now = {}
			updated.emit()
		return
	var d: Dictionary = r.data
	var item: Variant = d.get("item")
	if not (item is Dictionary):
		now = {}
		updated.emit()
		return
	var t := track_from(item, 0)
	var id := str(t.get("id", ""))
	var changed_track := id != str(now.get("id", ""))
	var before := now.duplicate()
	var ctx: Variant = d.get("context")
	var dev: Dictionary = d.get("device", {}) if d.get("device") is Dictionary else {}
	now = {
		"id": id, "uri": str(t.get("uri", "")), "title": str(t.get("title", "")), "artist": str(t.get("artist", "")), "album": str(t.get("album", "")),
		"art": Intern.erstes(t, ["art_big", "art"]), "duration": int(t.get("duration", 0)), "playing": Fremd.ja(d.get("is_playing")),
		"artist_id": str(t.get("artist_id", "")), "artists": t.get("artists", []),
		"shuffle": Fremd.ja(d.get("shuffle_state")), "repeat": Fremd.text(d.get("repeat_state"), "off"),
		"device": Fremd.text(dev.get("name")), "device_type": Fremd.text(dev.get("type")), "volume": Fremd.zahl(dev.get("volume_percent"), -1),
		"context": str((ctx as Dictionary).get("uri", "")) if ctx is Dictionary and (ctx as Dictionary).get("uri") != null else "",
		"liked": now.get("liked", false) if not changed_track else is_liked(id),
	}
	_progress_base = Fremd.zahl(d.get("progress_ms"))
	_progress_at = Time.get_ticks_msec()
	verlauf_note(Verlauf.from_now(now, int(Time.get_unix_time_from_system())))
	if changed_track and id != "":
		var lr := await library_contains(["spotify:track:" + id])
		if not lr.is_empty() and str(now.get("id", "")) == id:
			now["liked"] = bool(lr[0])
	# Nur melden, wenn sich etwas geändert hat (die Stelle im Titel rechnet jeder selbst nach).
	if now != before or changed_track:
		updated.emit()
	if changed_track:
		load_queue()


func _poll_windows() -> void:
	var r := await Helper.run("media-info", media_filter(), 6.0)
	# Nur Musik-Apps (siehe MUSIC_APPS): Der Helfer wählt schon so; geprüft wird hier trotzdem –
	# ein älterer Helfer schickte einfach die aktuelle Sitzung (auch YouTube im Browser).
	var ok: bool = r.ok and r.result is Dictionary and bool(r.result.get("active", false)) \
		and is_music_app(str(r.result.get("app", "")), int(r.result.get("type", PT_UNKNOWN)), bool(Config.get_value("music.browser", false)))
	if not ok:
		if not now.is_empty():
			now = {}
			updated.emit()
		return
	var d: Dictionary = r.result
	var title := str(d.get("title", ""))
	var before := now.duplicate()
	now = {
		"id": str((title + str(d.get("artist", ""))).hash()), "uri": "", "title": title, "artist": str(d.get("artist", "")),
		"album": str(d.get("album", "")), "art": str(d.get("art", "")), "duration": int(d.get("duration", 0)),
		"playing": bool(d.get("playing", false)), "shuffle": false, "repeat": "off",
		"device": app_name(str(d.get("app", ""))), "volume": -1, "context": "", "liked": false, "source": "windows",
		"app": str(d.get("app", "")),
	}
	_progress_base = int(d.get("position", 0))
	_progress_at = Time.get_ticks_msec()
	if now != before:
		updated.emit()


# --- Nur Musik-Apps ------------------------------------------------------------------------------
# Der Musik-Bereich (und alles, was „läuft gerade“ nutzt: Guide, Discord-/Steam-Status „Hört …“,
# Song schicken, Zusammen hören) ist nur für Spotify und Musik-Player. Windows meldet in seinen
# Mediensitzungen aber alles, was Ton macht – YouTube im Browser, Videos, Discord, Spiele. Früher
# nahm Uzai einfach die Sitzung, die Windows für die aktuelle hielt; dann stand ein YouTube-Video
# als „Läuft gerade“ da und die Medientasten schalteten es.

## Musik-Apps (Teil der App-Kennung von Windows, klein geschrieben): Spotify (Programm und
## Store-App), Musik-Player für eigene Dateien und reine Musik-Dienste mit eigener App.
const MUSIC_APPS := ["spotify", "foobar2000", "musicbee", "aimp", "winamp", "wacup", "mediamonkey",
	"dopamine", "strawberry", "clementine", "itunes", "applemusic", "apple music", "cider", "tidal",
	"deezer", "amazon music", "amazonmusic", "qobuz", "plexamp", "audirvana", "roon", "musique"]
## Player für Musik und Video: nur, solange Windows die Sitzung als Musik meldet (nicht bei Videos).
const MUSIC_IF_AUDIO := ["zunemusic", "wmplayer", "vlc", "mediaplayer"]
## Nie Musik im Sinne von Uzai, auch wenn ein Name oben passt: Browser (auch Web-Apps, die als
## Browser-Fenster laufen), YouTube, Video-Apps, Discord, Steam und Uzai selbst.
const NOT_MUSIC := ["chrome", "msedge", "microsoftedge", "firefox", "308046b0af4a39cb", "opera",
	"brave", "vivaldi", "chromium", "iexplore", "librewolf", "waterfox", "thebrowsercompany", "yandex",
	"youtube", "zunevideo", "netflix", "primevideo", "disney", "twitch", "discord", "steam", "uzai", "mpv"]
## Browser (Teil von NOT_MUSIC). Auf Wunsch (Einstellung music.browser) zählen sie als Musik-App –
## dann auch ein Video im Browser, denn Browser melden Windows alles als Musik.
const BROWSERS := ["chrome", "msedge", "microsoftedge", "firefox", "308046b0af4a39cb", "opera",
	"brave", "vivaldi", "chromium", "iexplore", "librewolf", "waterfox", "thebrowsercompany", "yandex"]
## Mediensitzung: Art laut Windows (MediaPlaybackType). Für Player, die auch Videos zeigen
## (MUSIC_IF_AUDIO), zählt nur Musik.
const PT_UNKNOWN := 0
const PT_MUSIC := 1
const PT_VIDEO := 2
const PT_IMAGE := 3


## Ist das eine Musik-App? aumid: Kennung der Mediensitzung (Programm, Pfad oder Store-App),
## ptype: Art der Sitzung laut Windows (PT_*).
static func is_music_app(aumid: String, ptype := PT_UNKNOWN, browsers := false) -> bool:
	var a := aumid.strip_edges().to_lower()
	if a == "":
		return false
	var f := filter_for(browsers)
	for k in f.deny:
		if a.contains(k):
			return false
	# Reine Musik-Apps immer (ein Video-Podcast in Spotify ist trotzdem Spotify).
	for k in f.allow:
		if a.contains(k):
			return true
	for k in MUSIC_IF_AUDIO:
		if a.contains(k):
			return ptype == PT_MUSIC
	return false


## Welche Sitzung zeigt Uzai? sessions: [{ app, playing, type }], current: Kennung der Sitzung,
## die Windows für die aktuelle hält. Nur Musik-Apps; eine, die gerade spielt, vor der aktuellen,
## sonst die erste. -1: keine. (Der Helfer wählt in Find-MusicSession genauso.)
static func pick_session(sessions: Array, current := "", browsers := false) -> int:
	var best := -1
	var best_score := -1
	for i in sessions.size():
		var s: Dictionary = sessions[i] if sessions[i] is Dictionary else {}
		var app := str(s.get("app", ""))
		if not is_music_app(app, int(s.get("type", PT_UNKNOWN)), browsers):
			continue
		var score := (2 if bool(s.get("playing", false)) else 0) + (1 if current != "" and app == current else 0)
		if score > best_score:
			best = i
			best_score = score
	return best


## Für den Helfer (media-info, media): dieselben Listen, damit er nur Musik-Apps nimmt.
static func media_filter() -> Dictionary:
	return filter_for(bool(Config.get_value("music.browser", false)))


## Listen mit oder ohne Browser.
static func filter_for(browsers: bool) -> Dictionary:
	if not browsers:
		return { "allow": MUSIC_APPS, "audio": MUSIC_IF_AUDIO, "deny": NOT_MUSIC }
	return { "allow": MUSIC_APPS + BROWSERS, "audio": MUSIC_IF_AUDIO,
		"deny": NOT_MUSIC.filter(func(k: String) -> bool: return not k in BROWSERS) }


## Aus der App-Kennung von Windows ein lesbarer Name.
static func app_name(aumid: String) -> String:
	var a := aumid.to_lower()
	for k in [["spotify", "Spotify"], ["chrome", "Chrome"], ["msedge", "Edge"], ["firefox", "Firefox"], ["applemusic", "Apple Music"], ["itunes", "iTunes"],
			["tidal", "Tidal"], ["deezer", "Deezer"], ["amazon", "Amazon Music"], ["vlc", "VLC"], ["foobar", "foobar2000"], ["zune", "Windows Media Player"],
			["mediaplayer", "Windows Media Player"],
			["wmplayer", "Windows Media Player"], ["musicbee", "MusicBee"], ["aimp", "AIMP"], ["winamp", "Winamp"], ["wacup", "WACUP"], ["mediamonkey", "MediaMonkey"],
				["dopamine", "Dopamine"], ["qobuz", "Qobuz"], ["plexamp", "Plexamp"], ["audirvana", "Audirvana"], ["cider", "Cider"]]:
		if a.contains(k[0]):
			return k[1]
	return aumid.get_file().get_basename() if aumid != "" else "Windows"


## Woran der Helfer die Audiositzung der Musik-App erkennt (app-volume, keys): Programmname ohne
## .exe bzw. bei Store-Apps der Paketname (steht im Sitzungsnamen von Windows). Leer: unbekannt.
static func audio_keys(aumid: String) -> Array:
	var a := aumid.strip_edges().to_lower()
	if a == "":
		return []
	# Firefox meldet sich mit einer Prüfsumme seines Ordners statt mit seinem Namen.
	if a.contains("308046b0af4a39cb") or a.contains("firefox"):
		return ["firefox"]
	var k := a.replace("\\", "/").get_slice("!", 0).get_file()
	if k.ends_with(".exe"):
		k = k.left(-4)
	# Store-App (Paket!App): Paketname vor der Herausgeber-Kennung (SpotifyAB.SpotifyMusic_zpdnekdrzrea0).
	if a.contains("!"):
		k = k.get_slice("_", 0)
	if k.length() < 3:
		return []
	var out := [k]
	if k == "spotifyab.spotifymusic":
		out.append("spotify")
	return out


# --- Künstler ------------------------------------------------------------------
# Offizielle Wege der Web-API: /artists/{id}, /artists/{id}/top-tracks, /artists/{id}/albums und
# /search. Seit den Änderungen 2026 geben eigene Apps im „Development Mode“ nicht mehr alles heraus
# (Top-Titel fehlen bei manchen Apps, Bilder, Follower und Genres können leer sein). Dann nimmt
# Uzai die beliebtesten Treffer der Suche nach dem Künstler und zeigt, was da ist.


## Ganzen Künstler abspielen (Spotify mischt seine beliebtesten Titel); in der Vorführung die Top-Titel.
func play_artist(page: Dictionary) -> bool:
	var uri := str((page.get("artist", {}) as Dictionary).get("uri", ""))
	if demo() or uri == "" or uri.contains(":demo"):
		var top: Array = page.get("top", [])
		if top.is_empty():
			return false
		await play_list(top, 0)
		return true
	return await play_context(uri)


# --- Zusammen hören -------------------------------------------------------------
# Spotify Jam (gemeinsames Hören) hat in der Web-API keine Schnittstelle: eigene Apps können keine
# Jam starten, niemanden hineinholen und nicht sehen, wer drin ist. Uzai lädt darum über den Chat ein
# (Steam oder Discord, beides in Uzai) – mit Titel, Stelle und Link; liegt ein Jam-Link in der
# Zwischenablage (in Spotify „Jam starten“ → „Link teilen“), geht der mit. Ob jemand mithört, sieht
# Uzai nur am Status der Freunde: Das Discord Social SDK meldet von einem Freund nur die Aktivität
# derselben Discord-App – also Uzais Musikstatus „Hört …“, wenn der Freund Uzai mit derselben App-ID
# nutzt. Zeigt der denselben Titel, meldet Uzai „X hört jetzt mit“ und zeigt es im Guide. Spotifys
# eigenen Discord-Status anderer gibt das SDK nicht heraus; „Mithören“ (Listen Along) in Discord
# lässt sich von außen nicht starten. Steam kennt Spotify nur als Nicht-Steam-Spiel („hört Spotify“).

signal together_changed

const TOGETHER_KEEP := 3 * 3600     ## so lange gilt eine Einladung (Sekunden)
const TOGETHER_SECS := 5.0          ## so oft schaut Uzai nach, wer mithört
const TOGETHER_QUIET := 600         ## so lange meldet Uzai denselben Mithörer nicht nochmal (Sekunden)

var invited := {}                   ## "steam:ID"/"discord:ID" -> { kind, id, name, avatar, at, title }
var listeners: Array = []           ## [{ key, kind, id, name, avatar, how ("gleich"|"spotify"), invited }]
var _demo_joined := {}              ## Vorführung: Schlüssel -> Eintrag (steigt nach ein paar Sekunden ein)
var _together_timer: Timer
var _together_seen := {}            ## Schlüssel -> zuletzt beim Mithören gesehen (gegen Meldungs-Flut)


func _start_together() -> void:
	_together_timer = Timer.new()
	_together_timer.wait_time = TOGETHER_SECS
	_together_timer.timeout.connect(check_together)
	add_child(_together_timer)
	# Nur nachsehen, solange etwas läuft (oder jemand noch als Mithörer steht); kein Netz, nur
	# die Freundeslisten, die Steam und Discord ohnehin aktuell halten.
	updated.connect(_wake_together)


func _wake_together() -> void:
	if not now.is_empty() and _together_timer.is_stopped():
		_together_timer.start()


static func together_key(kind: String, f: Dictionary) -> String:
	return "%s:%s" % [kind, str(f.get("id", f.get("name", "")))]


## Ein Jam- bzw. Spotify-Link aus der Zwischenablage ("" wenn keiner).
static func jam_link(clip: String) -> String:
	var t := clip.strip_edges()
	if t.length() > 300 or t.contains(" ") or t.contains("\n"):
		return ""
	if t.begins_with("https://open.spotify.com/socialsession/") or t.begins_with("https://spotify.link/"):
		return t
	return ""


## Text der Einladung. Mit Jam-Link: in die Jam; sonst Titel, Stelle und Link zum Titel.
static func together_text(song: Dictionary, link: String, jam: String, at_ms: int) -> String:
	var what := "„%s“ von %s" % [str(song.get("title", "")), str(song.get("artist", ""))] if str(song.get("artist", "")) != "" else "„%s“" % str(
			song.get("title", ""))
	# Nur socialsession-Links sind sicher eine Jam; ein Kurzlink (spotify.link) kann auch ein alter
	# Titel- oder Playlist-Link sein – dann ohne das Versprechen „Jam offen“.
	if jam.begins_with("https://open.spotify.com/socialsession/"):
		return "Hörst du mit? Ich hab eine Spotify-Jam offen, gerade läuft %s: %s" % [what, jam]
	if jam != "":
		return "Hörst du mit? Gerade läuft %s – komm dazu: %s" % [what, jam]
	var s := int(at_ms / 1000.0)
	return "Lass uns zusammen hören: %s – ich bin bei %d:%02d. %s" % [what, int(s / 60.0), s % 60, link]


## Einladung merken (für „X hört jetzt mit“) und den Text dafür liefern. Verschickt wird über den Chat.
func invite_together(kind: String, f: Dictionary) -> String:
	var key := together_key(kind, f)
	invited[key] = { "kind": kind, "id": str(f.get("id", "")), "name": str(f.get("name", "")), "avatar": str(f.get("avatar", "")),
		"at": int(Time.get_unix_time_from_system()), "title": str(now.get("title", "")) }
	together_changed.emit()
	if demo():
		_demo_join_later(key)
	return together_text(now, share_link(), jam_link(DisplayServer.clipboard_get()), progress_ms())


func _demo_join_later(key: String) -> void:
	await get_tree().create_timer(4.0).timeout
	if invited.has(key):
		var inv: Dictionary = invited[key]
		_demo_joined[key] = { "key": key, "kind": str(inv.kind), "id": str(inv.id), "name": str(inv.name), "avatar": str(inv.avatar), "how": "gleich" }
		check_together()


## Hört der Freund laut Status dasselbe? "gleich" (gleicher Titel), "spotify" (Spotify läuft, Titel
## unbekannt) oder "". Öffentlich für die Tests.
static func hears(song: Dictionary, game: String, details: String, act_state: String) -> String:
	var title := str(song.get("title", "")).to_lower().strip_edges()
	if title != "" and details.to_lower().strip_edges() == title:
		var artist := str(song.get("artist", "")).get_slice(",", 0).to_lower().strip_edges()
		if act_state == "" or artist == "" or act_state.to_lower().contains(artist):
			return "gleich"
	if game.to_lower().strip_edges() == "spotify":
		return "spotify"
	return ""


## Wer gerade mithört: Discord-Freunde (Status mit Titel), Steam-Freunde mit Spotify als Spiel.
## Wer dasselbe hört, steht vorn. invited: Schlüssel der Einladungen (auch per Name erkannt).
static func listening(song: Dictionary, discord: Array, steam: Array, invited_: Dictionary = {}) -> Array:
	if song.is_empty() or str(song.get("title", "")) == "":
		return []
	var names := {}
	for k in invited_:
		names[str((invited_[k] as Dictionary).get("name", "")).to_lower()] = true
	var out: Array = []
	var seen := {}
	for f in discord:
		if not (f is Dictionary) or str(f.get("state", "offline")) == "offline":
			continue
		var how := hears(song, str(f.get("game", "")), str(f.get("details", "")), str(f.get("activity_state", "")))
		if how == "":
			continue
		var key := together_key("discord", f)
		seen[str(f.get("name", "")).to_lower()] = true
		out.append({ "key": key, "kind": "discord", "id": str(f.get("id", "")), "name": str(f.get("name", "")), "avatar": str(f.get("avatar", "")), "how": how,
			"invited": invited_.has(key) or names.has(str(f.get("name", "")).to_lower()) })
	for f in steam:
		if not (f is Dictionary) or str(f.get("state", "offline")) == "offline" or seen.has(str(f.get("name", "")).to_lower()):
			continue
		if str(f.get("game", "")).to_lower().strip_edges() != "spotify":
			continue
		var key2 := together_key("steam", f)
		out.append({ "key": key2, "kind": "steam", "id": str(f.get("id", "")), "name": str(f.get("name", "")), "avatar": str(f.get("avatar", "")), "how": "spotify",
			"invited": invited_.has(key2) or names.has(str(f.get("name", "")).to_lower()) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.how) != str(b.how):
			return str(a.how) == "gleich"
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return out


## Eingeladen, aber noch nicht dabei (für den Guide): [{ name, avatar, at }].
func waiting() -> Array:
	var out: Array = []
	for k in invited:
		if not listeners.any(func(l): return str(l.key) == str(k) or (str(l.name).to_lower() == str(invited[k].name).to_lower() and str(l.how) == "gleich")):
			out.append(invited[k])
	return out


## Eine Zeile für Guide und „Läuft gerade“: wer mithört, sonst wer eingeladen ist ("" = nichts).
## Öffentlich für die Tests.
static func together_line(lst: Array, wait: Array) -> String:
	var same: Array = lst.filter(func(l): return str(l.get("how", "")) == "gleich").map(func(l): return str(l.get("name", "")))
	if not same.is_empty():
		return _names(same) + (" hört mit" if same.size() == 1 else " hören mit")
	if not wait.is_empty():
		var w: Array = wait.map(func(x): return str(x.get("name", "")))
		return _names(w) + " eingeladen – noch nicht dabei"
	var sp: Array = lst.filter(func(l): return str(l.get("how", "")) == "spotify").map(func(l): return str(l.get("name", "")))
	if not sp.is_empty():
		return _names(sp) + (" hört auch Spotify" if sp.size() == 1 else " hören auch Spotify")
	return ""


static func _names(n: Array) -> String:
	if n.size() == 1:
		return str(n[0])
	if n.size() == 2:
		return TranslationServer.translate("%s und %s") % [n[0], n[1]]
	return TranslationServer.translate("%s, %s und %d weitere") % [n[0], n[1], n.size() - 2]


## Nachsehen, wer mithört; wer neu dasselbe hört, wird gemeldet („X hört jetzt mit“).
func check_together() -> void:
	var t := int(Time.get_unix_time_from_system())
	for k in invited.keys():
		if t - int(invited[k].get("at", 0)) > TOGETHER_KEEP:
			invited.erase(k)
	var list: Array = []
	if not now.is_empty():
		list = listening(now, DiscordChat.friends, Social.steam_friends, invited)
		for k in _demo_joined:
			if not list.any(func(l): return str(l.key) == str(k)):
				var e: Dictionary = (_demo_joined[k] as Dictionary).duplicate()
				e["invited"] = invited.has(k)
				list.push_front(e)
	var before := {}
	for l in listeners:
		before[str(l.key)] = str(l.how)
	for l in list:
		if str(l.how) != "gleich":
			continue
		# Beim Titelwechsel hinkt der Status des Freundes ein paar Sekunden nach – dann fällt er kurz
		# heraus und kommt wieder. Gemeldet wird nur, wer länger nicht mitgehört hat.
		var last := int(_together_seen.get(str(l.key), 0))
		_together_seen[str(l.key)] = t
		if str(before.get(str(l.key), "")) != "gleich" and t - last > TOGETHER_QUIET:
			Toasts.show_toast(("%s hört jetzt mit" if bool(l.invited) else "%s hört gerade dasselbe") % str(l.name),
				"„%s“ · %s" % [str(now.get("title", "")), str(now.get("artist", ""))], "music",
				{ "image": str(l.avatar), "overlay": true, "tag": "together:" + str(l.key) })
	if JSON.stringify(list) != JSON.stringify(listeners):
		listeners = list
		together_changed.emit()
	if now.is_empty() and listeners.is_empty() and is_instance_valid(_together_timer):
		_together_timer.stop()          # nichts läuft: ruhen, bis wieder etwas läuft (_wake_together)


# --- Spotify Connect (Dealer + connect-state) ---------------------------------------------------
# Wie die Spotify-Apps: Ein Websocket zum Dealer liefert die Spotify-Connection-Id und meldet, wenn
# sich etwas ändert. Mit der Id meldet sich Uzai als verstecktes Gerät bei connect-state an und
# bekommt dafür den ganzen Zustand (Geräte, aktives Gerät, laufender Titel, Warteschlange). Befehle
# (Abspielen mit Kontext, Pause, Weiter …) gehen an das Gerät – am liebsten die Spotify-App auf
# diesem PC. Nichts davon holt Spotify nach vorn. Der Dealer wird erst bei Bedarf verbunden, nach
# Fehlern mit wachsender Pause neu versucht und geschlossen, wenn ihn niemand braucht.

func _process(_delta: float) -> void:
	if _ws == null:
		set_process(false)
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	var now_ms := Time.get_ticks_msec()
	if st == WebSocketPeer.STATE_OPEN:
		while _ws != null and _ws.get_available_packet_count() > 0:
			_dealer_message(_ws.get_packet().get_string_from_utf8())
		if _ws != null and now_ms - _ping_ms > 30000:
			_ping_ms = now_ms
			_ws.send_text("{\"type\":\"ping\"}")
		# Niemand braucht ihn: im Spiel ohne Guide nach einer Minute, sonst nach drei Minuten zu.
		var idle := now_ms - _dealer_used_ms
		if idle > 180000 or (Launcher.in_game and not Launcher.guide_open and idle > 60000):
			dealer_close("nicht gebraucht")
	elif st == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		_conn_id = ""
		set_process(false)
		_dealer_fail("Verbindung getrennt (%d)" % code)


## Läuft gerade, laut Spotify Connect. true: erledigt (now gesetzt oder geleert), false: Spotify
## Connect ist nicht erreichbar.
func _poll_connect() -> bool:
	var raw := await _cluster_read()
	if raw.is_empty():
		return false
	var info := Intern.cluster(raw, _connect_dev, _now_ms())
	var tr: Dictionary = info.track
	if str(info.active) == "" or str(tr.uri) == "":
		return false
	# „Auf diesem PC“: Was auf einem fremden Gerät läuft (Fernseher, Handy), zeigt und steuert Uzai nicht – dann
	# gilt, was Windows auf diesem PC meldet (poll). Ein hier gewähltes Gerät zählt nicht als fremd.
	_gewollt_pruefen(info)
	if spotify_ort() == "pc" and Intern.fremd_aktiv(info, OS.get_environment("COMPUTERNAME"), _gewollt_dev):
		return false
	var extra := {}
	if str(tr.title) == "":
		var meta := await _track_meta(str(tr.uri))
		if not meta.is_empty():
			tr = { "id": meta.id, "uri": meta.uri, "title": meta.title, "artist": meta.artist, "artist_id": meta.artist_id, "album": meta.album,
					"art": Intern.erstes(meta, ["art_big", "art"]) }
		elif Config.is_windows() and Helper.available:
			# Grundmodus: Spotify Connect nennt nur die Kennung des Titels, und pathfinder (Name, Cover)
			# lässt Spotify gerade nicht zu. Spielt die Spotify-App auf diesem PC, kommen Titel und
			# Cover aus ihrer Mediensitzung bei Windows – gesteuert wird weiter über Spotify Connect
			# (Zufall, Wiederholen, Geräte). Sonst zeigt Uzai die Mediensitzung allein.
			extra = await _windows_title_for(info)
			if extra.is_empty():
				return false
			tr = { "id": tr.id, "uri": tr.uri, "title": extra.title, "artist": extra.artist, "artist_id": tr.artist_id, "album": extra.album,
					"art": str(tr.art) if str(tr.art) != "" else str(extra.art) }
	elif str(tr.art) == "" and Config.is_windows() and Helper.available:
		# Titel da, Cover nicht (Connect schickt die Bildfelder manchmal leer): das Cover aus der
		# Mediensitzung der Spotify-App, wenn sie denselben Titel spielt. Sonst stand im Guide nur der Name.
		extra = await _windows_title_for(info)
		if not extra.is_empty() and str(extra.title).to_lower() == str(tr.title).to_lower() and str(extra.art) != "":
			tr = tr.duplicate()
			tr["art"] = str(extra.art)
	var dev := {}
	for d in info.devices:
		if bool(d.active):
			dev = d
	var id := str(tr.id)
	var changed_track := id != str(now.get("id", ""))
	var before := now.duplicate()
	now = {
		"id": id, "uri": str(tr.uri), "title": str(tr.title), "artist": str(tr.artist), "album": str(tr.album), "art": str(tr.art),
		"duration": int(info.duration), "playing": bool(info.playing), "artist_id": str(tr.artist_id), "artists": [],
		"shuffle": bool(info.shuffle), "repeat": str(info.repeat), "device": str(dev.get("name", "")), "device_type": str(dev.get("type", "")),
		"volume": int(dev.get("volume", -1)), "context": str(info.context), "liked": now.get("liked", false) if not changed_track else is_liked(id),
	}
	_progress_base = int(info.progress)
	_progress_at = Time.get_ticks_msec()
	verlauf_note(Verlauf.from_cluster(raw, int(Time.get_unix_time_from_system()), extra))
	if changed_track and id != "":
		var lr := await library_contains(["spotify:track:" + id])
		if not lr.is_empty() and str(now.get("id", "")) == id:
			now["liked"] = bool(lr[0])
	if now != before or changed_track:
		updated.emit()
	if changed_track:
		load_queue()
	return true


## Titel aus der Mediensitzung der Spotify-App auf diesem PC, wenn Spotify Connect sie als laufendes
## Gerät meldet (Computer mit dem Namen dieses PCs bzw. der einzige Computer) und Wiedergabe und
## Pause übereinstimmen. {} sonst – dann spielt etwas anderes, und Uzai rät nicht.
func _windows_title_for(info: Dictionary) -> Dictionary:
	var dev := {}
	var pcs := 0
	for d in info.devices:
		if str(d.type) == "Computer":
			pcs += 1
		if bool(d.active):
			dev = d
	if dev.is_empty() or str(dev.type) != "Computer":
		return {}
	var pc := OS.get_environment("COMPUTERNAME").to_lower()
	if pcs > 1 and str(dev.name).to_lower() != pc:
		return {}
	var r := await Helper.run("media-info", media_filter(), 6.0)
	if not r.ok or not (r.result is Dictionary) or not bool(r.result.get("active", false)):
		return {}
	var d: Dictionary = r.result
	if not str(d.get("app", "")).to_lower().contains("spotify") or bool(d.get("playing", false)) != bool(info.playing):
		return {}
	var title := Verlauf.clean(d.get("title"))
	if title == "":
		return {}
	return { "title": title, "artist": Verlauf.clean(d.get("artist")), "album": Verlauf.clean(d.get("album")), "art": str(d.get("art", "")) }


# --- Spotify am PC (Bedienhilfe von Windows) -----------------------------------------------------
# Im Grundmodus liest Uzai, was das Fenster der Spotify-App auf diesem PC zeigt – „Deine Bibliothek“
# ganz (der Helfer blättert die virtuelle Liste ohne Fokus durch) und „Zuletzt gespielt“ der
# Startseite –, über die Bedienhilfe von Windows wie ein Bildschirmleser (Helfer „spotify-fenster“,
# Regeln in spotify_pc.gd). Gelesen wird selten (alle 6 Stunden, nach dem Start von Spotify oder auf
# Wunsch) und gemerkt (spotify_pc.json). Abspielen geht über Spotify Connect mit der Adresse aus dem
# Fenster (kein Fenster kommt nach vorn); nur ohne Adresse „ruft“ Uzai den Abspiel-Knopf im Fenster auf.
# Cover kommen über Spotifys öffentliche oEmbed-Schnittstelle (ohne Anmeldung, gemerkt).

var pc_lib := {}                    ## { playlists, artists, albums, recent }: Kacheln { i, id, name, sub, pkind, uri, art }
## Spotify-Fenster am PC lesen: "" (noch nicht versucht) · ok · zu (Spotify läuft nicht) · leer (nichts erkannt) · aus
## (Helfer ging nicht). Jeder Leseversuch kann jedes Ergebnis bringen.
const ZUSTAENDE_PC := { "*": ["ok", "zu", "leer", "aus"], "": [], "ok": [], "zu": [], "leer": [], "aus": [] }
var pc_state := "":
	set(neu):
		Zustand.wechsel("musik.pc", ZUSTAENDE_PC, pc_state, neu)
		pc_state = neu
var pc_reading := false             ## liest gerade (auf Wunsch)
var _pc_items: Array = []           ## geprüfte Einträge (Helfer bzw. Datei)
var _pc_arts := {}                  ## Adresse -> { u: Cover-Adresse oder "", t: wann gefragt }
var _pc_read_s := 0                 ## zuletzt vollständig gelesen (Unix-Zeit)
var _pc_loaded := false
var _pc_at := -100000               ## zuletzt versucht (ms)
var _pc_busy := false
var _pc_sig := ""                   ## letzter Stand im Protokoll (nur bei Änderung neu)
var _pc_cover_busy := false
var _pc_cover_hold := 0             ## oEmbed bremst: bis dahin keine Cover (Unix-Zeit)


func _pc_path() -> String:
	return Config.path("spotify_pc.json")


func _pc_load() -> void:
	if _pc_loaded:
		return
	_pc_loaded = true
	if demo():
		return
	var d := SpotifyPc.load_file(Config.read_json(_pc_path(), {}))
	_pc_items = d.items
	_pc_arts = d.arts
	_pc_read_s = int(d.at)
	_pc_apply()


func _pc_save() -> void:
	if not demo():
		Config.write_json(_pc_path(), SpotifyPc.to_file(_pc_items, _pc_arts, _pc_read_s))


func _pc_apply() -> void:
	var nxt := SpotifyPc.rows_from(_pc_items, verlauf_list(), _pc_arts)
	if nxt != pc_lib:
		pc_lib = nxt
		lists_changed.emit("pc")


## Gibt es Reihen aus Spotify am PC (gelesen oder gemerkt)?
func pc_has() -> bool:
	_pc_load()
	return not SpotifyPc.empty(pc_lib)


## Läufe von pc_lib_refresh, die gerade unterwegs sind (siehe dort).
var _pc_lib_refresh_offen := 0


## Das Spotify-Fenster lesen, wenn es Zeit ist: nie gelesen, älter als 6 Stunden, Spotify gerade
## gestartet, oder auf Wunsch (force). Höchstens alle 45 s ein Versuch, nach „nichts erkannt“ erst nach
## 10 Minuten; im Spiel nie von selbst.
func pc_lib_refresh(force := false) -> void:
	_pc_lib_refresh_offen += 1
	await _pc_lib_refresh_lauf(force)
	_pc_lib_refresh_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und pc_lib_refresh täte bis zum Neustart nichts mehr.
	if _pc_lib_refresh_offen == 0 and _pc_busy:
		_pc_busy = false


func _pc_lib_refresh_lauf(force := false) -> void:
	if demo() or not grundmodus():
		return
	_pc_load()
	if _pc_busy or not (Config.is_windows() and Helper.available):
		return
	# Im Spiel nie von selbst (auch nicht im Guide: das Fenster würde über dem Spiel bereitgelegt).
	if Launcher.in_game and not force:
		return
	var now_s := int(Time.get_unix_time_from_system())
	if not force:
		var since := Time.get_ticks_msec() - _pc_at
		if since < SpotifyPc.ZU_MS or (pc_state in ["leer", "aus"] and since < SpotifyPc.LEER_MS):
			return
		if pc_state == "ok" and now_s - _pc_read_s < SpotifyPc.VOLL_S and not _pc_items.is_empty():
			return
	_pc_busy = true
	_pc_at = Time.get_ticks_msec()
	if force:
		pc_reading = true
		lists_changed.emit("pc")
	var r := await Helper.run("spotify-fenster", { "voll": true, "uzai_pid": OS.get_process_id() }, 30.0)
	_pc_busy = false
	pc_reading = false
	var res: Dictionary = r.result if r.ok and r.get("result") is Dictionary else {}
	var neu := SpotifyPc.items_from(res)
	var sig := ""
	if bool(res.get("ok", false)):
		pc_state = "ok" if not neu.is_empty() else "leer"
		if not neu.is_empty():
			_pc_items = SpotifyPc.merge(neu, _pc_items, bool(res.get("ende", false)) and not bool(res.get("cut", false)))
			_pc_read_s = now_s
			_pc_save()
		var rows := SpotifyPc.rows_from(neu, [], {})
		sig = "%d Einträge (%s), Fenster %s, %s Schritte%s, %s Knoten, ohne Knopf %s, %s ms%s" % [neu.size(), SpotifyPc.summary(rows, neu),
			Verlauf.clean(res.get("lage"), 40), str(res.get("steps", 0)), " bis zum Ende" if bool(res.get("ende", false)) else "", str(res.get("nodes", 0)),
			str(res.get("nobutton", 0)), str(res.get("ms", 0)), " (Grenze erreicht)" if bool(res.get("cut", false)) else ""]
		if bool(res.get("aufgeraeumt", false)):
			_log("Spotify am PC: Fenster von einem abgebrochenen Lesen zurückgelegt")
	elif res.get("why") is String:
		pc_state = "zu" if str(res.why) == "läuft nicht" else "aus"
		sig = "aus (%s)" % Verlauf.clean(res.why, 40)
	else:
		pc_state = "aus"
		sig = "aus (Helfer: %s)" % Verlauf.clean(str(r.get("error", "")), 60)
	if sig.get_slice(",", 0) != _pc_sig.get_slice(",", 0) or force:
		_log("Spotify am PC: " + sig)
	_pc_sig = sig
	_pc_apply()
	lists_changed.emit("pc")
	_pc_covers()


## Spotify am PC starten (minimiert, ohne dass ein Fenster nach vorn kommt) und danach lesen.
func pc_start() -> void:
	if demo() or starting:
		return
	var dev := await start_here()
	if dev == "" and error != "":
		lists_changed.emit("pc")
		return
	# Spotify baut sein Fenster nach dem Start erst auf.
	await get_tree().create_timer(6.0).timeout
	pc_lib_refresh(true)


## Läufe von _pc_covers, die gerade unterwegs sind (siehe dort).
var _pc_covers_offen := 0


## Cover über oEmbed nachladen (nacheinander, höchstens 80 je Durchgang, gemerkt). Bremst Spotify
## (429), ruht es 10 Minuten.
func _pc_covers() -> void:
	_pc_covers_offen += 1
	await _pc_covers_lauf()
	_pc_covers_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _pc_covers täte bis zum Neustart nichts mehr.
	if _pc_covers_offen == 0 and _pc_cover_busy:
		_pc_cover_busy = false


func _pc_covers_lauf() -> void:
	if _pc_cover_busy or demo():
		return
	_pc_cover_busy = true
	var now_s := int(Time.get_unix_time_from_system())
	var tried := 0
	var got := 0
	var why := ""
	for it in _pc_items.duplicate():
		if tried >= 80 or now_s < _pc_cover_hold:
			break
		var uri := str(it.uri)
		if not SpotifyPc.cover_due(_pc_arts, uri, now_s):
			continue
		tried += 1
		var r := await Net.get_json(SpotifyPc.oembed_url(uri))
		var code := int(r.get("code", 0))
		if code == 429:
			_pc_cover_hold = now_s + 600
			why = ", Spotify bremst (10 Min. Pause)"
			break
		var art := SpotifyPc.oembed_art(r.get("data")) if bool(r.get("ok", false)) else ""
		if art == "" and why == "" and code != 200:
			why = ", HTTP %d" % code
		_pc_arts[uri] = { "u": art, "t": now_s }
		got += 1 if art != "" else 0
		if tried % 12 == 0:
			_pc_apply()
		await get_tree().create_timer(0.15).timeout
	if tried > 0:
		_log("Spotify am PC: Cover %d von %d (oEmbed)%s" % [got, tried, why])
		_pc_save()
		_pc_apply()
	_pc_cover_busy = false


## Antwort des Helfers → Reihen (jeder Wert geprüft). Cover nur, wo der eigene Verlauf eins für
## dieselbe Adresse bzw. denselben Namen kennt (sonst kommen sie später über oEmbed).
static func pc_lib_from(res: Dictionary, hist: Array) -> Dictionary:
	return SpotifyPc.rows_from(SpotifyPc.items_from(res), hist, {})


## Einen Eintrag abspielen. Mit Adresse über Spotify Connect (wie jede Playlist; ist kein Gerät
## bereit, startet Spotify minimiert auf diesem PC) – kein Fenster kommt nach vorn. Ohne Adresse (oder
## lehnt Spotify ab) den Abspiel-Knopf im Spotify-Fenster „aufrufen“; springt Spotify dabei nach vorn,
## minimiert der Helfer es sofort wieder. true, wenn es läuft.
func pc_play(it: Dictionary) -> bool:
	var uri := str(it.get("uri", ""))
	_zu_spotify()
	if SpotifyPc.uri_ok(uri):
		var ok := await play_context(uri)
		if ok or int(it.get("i", -1)) < 0 or not (Config.is_windows() and Helper.available):
			if not ok:
				_log("Spotify am PC: Abspielen über Spotify Connect abgelehnt (%s)" % Verlauf.clean(error, 80))
			return ok
		_log("Spotify am PC: Spotify Connect lehnt ab, versuche das Fenster")
	if not (Config.is_windows() and Helper.available) or int(it.get("i", -1)) < 0:
		return false
	var r := await Helper.run("spotify-fenster-spielen", { "i": int(it.get("i", -1)), "name": str(it.get("name", "")) }, 8.0)
	var res: Dictionary = r.result if r.ok and r.get("result") is Dictionary else {}
	var how := str(res.get("result", "")) if res.get("result") is String else "Helfer"
	if bool(res.get("vorn", false)):
		if bool(res.get("zurueck", false)):
			_log("Spotify am PC: kam beim Abspielen nach vorn – sofort minimiert, Uzai wieder vorn")
		else:
			_log("Spotify am PC: kam beim Abspielen nach vorn – Uzai zurückgeholt")
			if not Launcher.in_game:
				Helper.run("focus", { "pid": OS.get_process_id() })
	if how != "ok":
		_log("Spotify am PC: Abspielen → " + Verlauf.clean(how, 40))
		if how in ["weg", "anders"]:
			pc_lib_refresh(true)
		return false
	error = ""
	_cluster_dirty = true
	_later_poll(true)
	return true


# --- Vorführung (--demo) ----------------------------------------------------------

## Verlauf der Vorführung (Grundmodus): Titel aus den Beispieldaten, einige mehrfach gehört,
## aus zwei Playlists und einem Album.
func _demo_verlauf() -> Array:
	var all := demo_tracks() + _demo_extra_tracks()
	var ctx := [["spotify:playlist:" + "Spieleklassiker".rpad(22, "0"), "Spieleklassiker"], ["spotify:playlist:" + "ZumZocken".rpad(22, "0"), "Zum Zocken"],
		["spotify:album:" + "FinalFantasyX".rpad(22, "0"), "Final Fantasy X"], ["spotify:playlist:" + "ChillBeats".rpad(22, "0"), "Chill Beats"]]
	var order := [0, 7, 3, 0, 11, 5, 0, 7, 13, 2, 9, 3, 15, 0, 8, 1, 7, 12, 4, 6, 10, 14, 3]
	var out: Array = []
	var ts := int(Time.get_unix_time_from_system()) - 900
	for i in order.size():
		var t: Dictionary = all[int(order[i]) % all.size()]
		var c: Array = ctx[i % ctx.size()]
		var e := Verlauf.entry({ "u": "spotify:track:" + str(t.id).rpad(22, "0"), "t": t.title, "a": t.artist, "al": t.album,
			"c": c[0], "cn": c[1], "ts": ts - i * 1300 })
		out.append(e)
	return out


## Vorführung ohne Spotify: Befehle wirken auf die Beispieldaten.
func _demo_control(path: String, payload: Variant) -> void:
	var pick: Dictionary = {}
	var list: Array = demo_tracks()
	if path.ends_with("/next"):
		if queue_list.is_empty():
			return
		pick = queue_list.pop_front()
		list = [pick] + queue_list
	elif payload is Dictionary and (payload as Dictionary).has("context_uri"):
		var ctx := str(payload.context_uri)
		if ctx.begins_with("spotify:album:"):
			for a in demo_albums() + _demo_saved_albums():
				if str(a.uri) == ctx:
					list = demo_album_tracks(a)
		var want := str((payload.offset as Dictionary).get("uri", "")) if payload.get("offset") is Dictionary else ""
		for t in list:
			if want == "" or t.uri == want:
				pick = t
				break
		now["context"] = ctx
	elif payload is Dictionary and payload.get("uris") is Array:
		var known := _demo_known()
		list = []
		for u in payload.uris:
			if known.has(str(u)):
				list.append(known[str(u)])
		if not list.is_empty():
			pick = list[0]
	if pick.is_empty():
		return
	for k in ["id", "uri", "title", "artist", "album", "art", "duration"]:
		now[k] = pick[k]
	now["playing"] = true
	now["liked"] = is_liked(str(pick.id))
	_progress_base = 0
	_progress_at = Time.get_ticks_msec()
	var idx := 0
	for i in list.size():
		if list[i].uri == pick.uri:
			idx = i
	queue_list = (list.slice(idx + 1) + list.slice(0, maxi(0, idx))).slice(0, 30)
	updated.emit()
	lists_changed.emit("queue")


# --- Spotify-Anmeldung (einmalig) ----------------------------------------------
# Die Wege selbst (Browser am PC, Code fürs Handy) stehen in music_spotify.gd.

func connect_spotify() -> String:
	var cid := str(Config.get_value("accounts.spotify_client_id", ""))
	if cid == "":
		return "Zuerst die Client-ID eintragen."
	var r := await _browser_login(cid, [8888], "/callback", SCOPES)
	if str(r.get("err", "")) != "":
		return str(r.err)
	# Auch eine Antwort „200“ ohne lesbaren Inhalt ist keine Anmeldung (sonst bräche das Speichern unten ab, und die
	# Oberfläche meldete „verbunden“, ohne dass es einen Schlüssel gibt).
	if not r.ok or not (r.get("data") is Dictionary):
		_log("Anmeldung: HTTP %d %s" % [int(r.code), _brief(r.get("data"))])
		var desc := _brief(r.get("data"))
		return "Spotify hat die Anmeldung abgelehnt" + ((" (" + desc + ")") if desc != "" else "") + "."
	Config.set_value("accounts.spotify_scopes_asked", SCOPES)
	_rate_strikes["eigen"] = 0
	_rate_until["eigen"] = 0
	_fail_cache.clear()
	if login_mode() == "app":
		# Wer die eigene App eigens neu verbindet, will sie auch benutzen.
		_quiet_mode = true
		Config.set_value("accounts.spotify_mode", "eigen")
		_quiet_mode = false
	_tok_mode = "eigen"
	_store_token(r.data, "eigen")
	Config.set_value("accounts.spotify_refresh", str(r.data.get("refresh_token", "")))
	need_login = false
	problem = ""
	_log("Angemeldet. Freigaben: " + _scopes)
	_fy_at = 0
	start()
	load_playlists()
	return ""


## „Mit Spotify anmelden“: Ereignis „spotify“ des Kerns, während die Anmeldeseite offen ist (browser.gd im
## Spotify-Modus). Gehört der Schlüssel zu einem Konto, gilt die Anmeldung: merken, DASS angemeldet ist, diesen
## Schlüssel gleich benutzen, Listen neu. true, wenn angemeldet (die Anmeldeseite schließt dann).
## seite_ok: die Seite steht nicht (mehr) auf der Anmeldung. Bleibt die Kontoprüfung dann ohne klares Ergebnis
## (Hash veraltet, abgelehnt, keine Antwort), gilt die Anmeldung trotzdem – nur ein klares „kein Konto“ hält sie auf.
func web_angemeldet(e: Dictionary, seite_ok := false) -> bool:
	var w := Web.aus_ereignis(e)
	if w.is_empty():
		return false
	if demo():
		Config.set_value("system.music_mode", "spotify")
		return true
	web_sitzung().kopf_melden(w)
	var konto := await _web_konto(str(w.token), str(w.client), str(w.version))
	if konto == "?" and seite_ok:
		_log("Spotify-Sitzung: Konto ungeprüft, die Seite ist angemeldet – Anmeldung gilt")
		_web_me = {}
		konto = "ja"
	if konto != "ja":
		return false
	Config.set_value("accounts.spotify_web", true)
	Config.set_value("system.music_mode", "spotify")
	_quiet_mode = true
	Config.set_value("accounts.spotify_mode", "app")
	_quiet_mode = false
	_app_off_until = 0
	_app_slow_until = 0
	_web_aus_bis = 0
	_app_401 = 0
	_app_429 = 0
	_rate_until = { "app": 0, "eigen": 0 }
	_app_fresh()
	_home_warned = false
	app_note = ""
	_tok_mode = "app"
	_client_token = str(w.client)
	_web_version = str(w.version)
	_web_geprueft = str(w.token)
	_store_token({ "access_token": str(w.token), "expires_in": Web.GILT_S + 60 }, "app")
	me = _web_me.duplicate()
	need_login = false
	problem = ""
	spotify_mixes = []
	_catalogs.clear()
	_log("Mit Spotify angemeldet (Anmeldeseite im Uzai-Browser)")
	_fy_at = 0
	start()
	load_playlists()
	updated.emit()
	return true


## Abmelden: which "app", "eigen" oder "" (die gerade benutzte). Gibt es die andere Anmeldung noch,
## geht es mit ihr weiter.
func disconnect_spotify(which := "") -> void:
	var w := which if which != "" else login_mode()
	# Nur die genannte Anmeldung vergessen – die andere bleibt. Die eigene Client-ID (spotify_refresh)
	# löscht Uzai nur hier und nur auf ausdrücklichen Wunsch („Eigene App trennen“); keine 429, keine
	# abgelehnte App-Anmeldung und kein Moduswechsel fasst sie von selbst an.
	_log("Abmelden: %s" % ("Spotify-Sitzung" if w == "app" else "eigene Client-ID"))
	if w == "app":
		# Kern beenden, Ordner der Sitzung (Cookies, Speicher) ganz löschen, Schlüssel vergessen.
		Config.set_value("accounts.spotify_web", false)
		Config.set_value("accounts.spotify_app_refresh", "")
		_web_geprueft = ""
		_web_version = ""
		_web_aus_bis = 0
		if not demo():
			web_sitzung().abmelden()
	else:
		Config.set_value("accounts.spotify_refresh", "")
	if not app_ready() and not own_ready():
		# Keine Anmeldung mehr: auch das zuletzt benutzte Gerät dieses Kontos vergessen.
		Config.set_value("music.spotify_last_device", "")
	_token = ""
	_tok_mode = ""
	_alt_token = ""
	_scopes = ""
	_client_token = ""
	_rate_until = { "app": 0, "eigen": 0 }
	_app_slow_until = 0
	_app_429 = 0
	_app_401 = 0
	_app_off_until = 0
	dealer_close("abgemeldet")
	_cluster_raw = {}
	_target_dev = ""
	_gewollt_dev = ""
	app_note = ""
	now = {}
	me = {}
	playlists = []
	top_tracks = []
	top_long = []
	saved_albums = []
	new_releases = []
	spotify_mixes = []
	for_you_parts = {}
	_catalogs.clear()
	_fy_at = 0
	problem = ""
	playlists_state = ""
	need_login = false
	if FileAccess.file_exists(_fy_cache_path()):
		DirAccess.remove_absolute(_fy_cache_path())
	_poll_timer.stop()
	updated.emit()
	if has_spotify():
		start()
		load_playlists()


## Verbindung Schritt für Schritt prüfen (Einstellungen → Konten). Je Schritt { name, ok, text }.
func diagnose() -> Array:
	var out: Array = []
	if demo():
		return [{ "name": "Anmeldung", "ok": true, "text": "Vorführung" }]
	_log("Verbindung prüfen …")
	if str(Config.get_value("accounts.spotify_client_id", "")) == "" and not app_ready():
		return [
				{ "name": "Anmeldung", "ok": false,
				"text": "Nicht angemeldet. Einstellungen → Konten → Spotify." }]
	if not has_spotify():
		return [{ "name": "Anmeldung", "ok": false, "text": "Noch nicht mit Spotify verbunden." }]
	# Wer selbst prüft, will es jetzt wissen: auch die gerade ruhende App-Anmeldung nochmal fragen.
	if problem == "app" or _app_off_until > 0:
		_app_off_until = 0
		_web_aus_bis = 0
		_set_problem("")
	# Auch der Grundmodus: eine echte Anfrage an pathfinder entscheidet neu.
	_pf_off = ""
	_pf_seen.clear()
	_grund_merken(false)
	_token = ""
	var tok := await _ensure_token()
	var how_t := "Mit Spotify angemeldet" if _tok_mode == "app" else "Freigaben: " + str(_scopes.split(" ").size())
	out.append({ "name": "Anmeldung", "ok": tok, "text": how_t if tok else (error if error != "" else problem_text(problem)) })
	if not tok:
		return out
	var steps := [
		["Konto", "/me"],
		["Läuft gerade", "/me/player?additional_types=track"],
		["Geräte", "/me/player/devices"],
		["Playlists", "/me/playlists?limit=50"],
		["Lieblingssongs", "/me/tracks?limit=1"],
		["Zuletzt gehört", "/me/player/recently-played?limit=1"],
		["Top-Titel", "/me/top/tracks?limit=1"],
		["Gefolgte Künstler", "/me/following?type=artist&limit=1"],
	]
	if _tok_mode == "app":
		# Der neue Hauptweg für die Mixe: die Startseite über api-partner (pathfinder). Er geht auch,
		# wenn die Web-API (api.spotify.com) die Kennung der Desktop-App bremst.
		var home := await _mixes_via_home()
		var home_ok := not home.is_empty()
		out.append({ "name": "Mixe (Startseite)", "ok": home_ok,
			"text": ("%d Listen über api-partner" % home.size()) if home_ok else "Keine über die Startseite – Uzai nimmt die alten Wege (Kategorie, made-for-x)" })
		_log("Prüfen Mixe (Startseite): %s" % ("%d Listen" % home.size() if home_ok else "keine"))
		# Bibliothek und Abspielen wie die Spotify-App (ohne api.spotify.com).
		var lib := await _pf("libraryV3", _lib_vars("Playlists", 50, 0))
		var lib_n := Intern.library_items(lib.data).size() if lib.ok else -1
		out.append(
				{ "name": "Bibliothek (intern)", "ok": lib.ok, "text": ("%d Einträge über api-partner" % lib_n) if lib.ok
				else "Abgelehnt (HTTP %d) – Uzai nimmt die Web-API bzw. die eigene App" % int(lib.get("code", 0)) })
		_log("Prüfen Bibliothek (intern): %s" % (("%d" % lib_n) if lib.ok else "HTTP %d" % int(lib.get("code", 0))))
		var raw := await _cluster_read(true)
		var con_text := ""
		if raw.is_empty():
			con_text = "Nicht erreichbar (Dealer: %s) – Abspielen/Pause gehen dann über die Medientasten von Windows" % ("keine Verbindung" if _conn_id == ""
					else "verbunden, Zustand abgelehnt")
		else:
			var info := Intern.cluster(raw, _connect_dev, _now_ms())
			var names := PackedStringArray()
			for d in info.devices:
				names.append(str(d.name) + (" (aktiv)" if bool(d.active) else ""))
			con_text = (
					"%d Gerät(e): %s" % [names.size(), ", ".join(names)]) if not names.is_empty() else "Verbunden, aber kein Gerät – Spotify auf diesem PC einmal öffnen"
		out.append({ "name": "Spotify Connect", "ok": not raw.is_empty(), "text": con_text })
		_log("Prüfen Spotify Connect: " + con_text)
		steps.append(["Mixe für dich", "/browse/categories/%s/playlists?limit=50&locale=%s" % [MADE_FOR_YOU, Lang.api("spotify")]])
		if grundmodus():
			# Grundmodus: Die Web-API bremst diese Anmeldung (429) – die acht Abfragen sparen; was
			# geht, steht oben (Spotify Connect), was nicht, in einer ruhigen Zeile.
			out = out.filter(func(st: Dictionary) -> bool: return not str(st.name) in ["Mixe (Startseite)", "Bibliothek (intern)"])
			out.append({ "name": "Bibliothek, Mixe und Suche", "ok": true, "text": "Gerade nicht erreichbar. Läuft gerade und Steuern gehen weiter." })
			_log("Prüfen: Grundmodus – Web-API-Abfragen ausgelassen")
			return out
	for st in steps:
		var r := await _api(HTTPClient.METHOD_GET, str(st[1]))
		var ok := bool(r.ok) or int(r.code) == 204
		var text := ""
		if ok:
			text = _diag_ok(str(st[0]), r)
		else:
			text = why_text(r, "Abgelehnt")
		out.append({ "name": str(st[0]), "ok": ok, "text": text })
		_log("Prüfen %s: %s" % [str(st[0]), text])
	return out


static func _diag_ok(name: String, r: Dictionary) -> String:
	var d: Dictionary = r.data if r.get("data") is Dictionary else {}
	match name:
		"Konto":
			return "Angemeldet als " + (str(d.get("display_name", "")) if d.get("display_name") != null else str(d.get("id", "")))
		"Läuft gerade":
			if int(r.code) == 204 or d.is_empty():
				return "Gerade läuft nichts (kein aktives Spotify-Gerät)"
			var it: Variant = d.get("item")
			var dev: Variant = d.get("device")
			return "%s%s" % [str((it as Dictionary).get("name", "")) if it is Dictionary else "Etwas", (" auf " + str((dev as Dictionary).get("name", "")))
					if dev is Dictionary else ""]
		"Geräte":
			var n := (d.get("devices", []) as Array).size() if d.get("devices") is Array else 0
			return "%d gefunden" % n if n > 0 else "Keins offen (Spotify am PC oder Handy starten)"
		"Playlists", "Lieblingssongs", "Zuletzt gehört", "Top-Titel":
			if d.get("total") != null:
				return "%d" % Fremd.zahl(d.get("total"))
			return "%d" % ((d.get("items", []) as Array).size() if d.get("items") is Array else 0)
		"Mixe für dich":
			var n2 := pick_spotify_mixes(collect_playlists(d).map(func(p): return playlist_from(p).merged({ "mfy": true }))).size()
			return "%d Mixe von Spotify" % n2 if n2 > 0 else "Keine in „Für dich gemacht“ (Uzai versucht weitere Wege)"
		"Gefolgte Künstler":
			var a: Variant = d.get("artists")
			return "%d" % Fremd.zahl((a as Dictionary).get("total")) if a is Dictionary and (a as Dictionary).get("total") != null else "ok"
	return "ok"

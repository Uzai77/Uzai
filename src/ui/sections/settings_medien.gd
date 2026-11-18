extends "res://src/ui/sections/settings_konten.gd"
## Einstellungen, Schicht über settings_konten.gd: die Kategorien Klang, Medien, Mitteilungen,
## Im Spiel, Aufnahmen und Controller.

const RemotePlay := preload("res://src/core/remote_play.gd")
const MovieManage := preload("res://src/ui/components/movie_manage.gd")
const CapturesLayer := preload("res://src/ui/layers/captures.gd")
const CapLogic := preload("res://src/core/capture_logic.gd")

const Handheld := preload("res://src/core/handheld.gd")
const GuideTiles := preload("res://src/ui/layers/guide_tiles.gd")
const GuideQuick := preload("res://src/ui/components/guide_quick.gd")
const NachtTon := preload("res://src/core/nacht_ton.gd")
const FxSound := preload("res://src/core/fxsound.gd")
const FxSheet := preload("res://src/ui/layers/fxsound_sheet.gd")


# --- Klang -------------------------------------------------------------------------------

## Alles Hörbare an einem Ort: Menüklänge, Musik (auch die Quelle der Musik-App), Töne der
## Mitteilungen, Tonausgabe von Windows.
func _klang() -> void:
	_head("Menü")
	_sound_row()
	_choice("theme.sound_set", "Klangsatz", "", Klang.SAETZE)
	_toggle_def("theme.sound_space", "Räumlicher Klang", "", true)
	_head("Musik")
	_slider("theme.music", "Menümusik", "", 0.0, 1.0, 0.1).set_meta("uz_such", "Lautstärke Hintergrundmusik")
	var tracks: Array = [["theme", "Standard"]]
	for id in Klang.MUSIK.keys():
		tracks.append([id, Klang.MUSIK[id]])
	_choice("theme.music_track", "Musikstück", "", tracks)
	_choice("system.music_mode", "Musikquelle", "Spotify: Anmeldung unter Konten. Mit Musikordner beides.",
		[["lokal", "Eigene Musikdateien"], ["spotify", "Spotify und eigene Musik"], ["tasten", "Musik-Apps über Windows"], ["aus", "Aus"]]).set_meta("uz_such",
			"Spotify Musik Player")
	var music_mode := str(Config.get_value("system.music_mode", "lokal"))
	if music_mode == "spotify":
		_choice("system.spotify_ort", "Spotify spielt auf", "Dieser PC: Uzai startet Spotify hier, statt ein anderes Gerät zu steuern.",
			[["pc", "Diesem PC"], ["aktiv", "Dem Gerät, das gerade läuft"]]).set_meta("uz_such", "Spotify Connect Gerät Fernseher Handy Lautsprecher")
	if music_mode in ["lokal", "spotify"]:
		# Neben Spotify freiwillig: ohne Ordner nur Spotify; mit Ordner spielt, was zuletzt startet.
		_path("music.local_dir", "Musikordner", "MP3, OGG und WAV." if music_mode == "lokal" else "Freiwillig. Dann steht deine Musik neben Spotify.", true)
	if Music.lokal_da():
		var lm: Node = Music.local
		var st := "Liest ein …" if lm.scanning else (
				U.plural((lm.albums as Array).size(), "Album", "Alben") + " · " + U.plural((lm.tracks as Array).size(), "Titel", "Titel"))
		_action("Musik neu einlesen", "", st,
				func() -> void:
			if str(Config.get_value("music.local_dir", "")) == "":
				Toasts.show_toast("Erst einen Musikordner wählen", "", "folder", { "ms": 2400 })
				return
			Toasts.show_toast("Musik wird eingelesen", "Das läuft im Hintergrund.", "music", { "ms": 2400, "quiet": true })
			await lm.scan(true)
			_rebuild_keep()
		, "refresh")
	elif music_mode == "tasten":
		_toggle_def("music.browser", "Auch Musik im Browser", "Dann zählt auch ein Video im Browser als Musik.", false)
	if music_mode != "aus":
		_toggle_def("music.lrclib", "Liedtexte (LRCLIB)", "Von lrclib.net. Sendet Titel, Künstler, Album und Länge.",
				true).set_meta("uz_such", "Songtext Lyrics")
	_head("Mitteilungen")
	_toggle("system.notifications", "Ton bei Mitteilungen", "")
	_toggle_def("notify.unlock_sound", "Ton beim Erfolg", "", true)
	if Config.is_windows() or Library.demo:
		_head("Ausgabe")
		_action("Tonausgabe", "Fernseher, Monitor oder Headset.", "", func() -> void: main.open_audio_devices(), "speaker").set_meta("uz_such",
				"Lautsprecher HDMI Audio Ausgabegerät")
		# Festes Gerät und FxSound (src/core/tonwahl.gd): Die Zeilen zeigen den Stand; nach der Wahl baut die Seite neu.
		var tw := Mixer.tonwahl
		_action("Immer dieses Gerät", "Uzai stellt zurück darauf, sobald es wieder da ist – etwa wenn der Fernseher aus war.",
				(tw.fest_name() if tw.fest_name() != "" else "An") if tw.fest_an() else "Aus", func() -> void:
			var l: Control = await main.open_ton_fest()
			if l:
				l.closed.connect(_rebuild_keep), "lock").set_meta("uz_such", "Standardgerät festes Gerät bevorzugt Fernseher aus HDMI Ton weg umstellen")
		if bool(Config.get_value("ton.fxsound_da", false)) or Library.demo:
			var fxr = _action("FxSound", "Klangverbesserung an und aus, Klangprofil – ohne Uzai zu verlassen.", FxSound.kurz(tw.fx), func() -> void:
				FxSheet.open_for(main).closed.connect(_rebuild_keep), "pulse")
			fxr.set_meta("uz_such", "Equalizer Klang Bass Sound Enhancer")
			# Den Stand frisch nachlesen (FxSound kann inzwischen von Hand umgestellt sein) und die Zeile nachführen.
			tw.changed.connect(func() -> void:
				if is_instance_valid(fxr):
					fxr.set_value_text(FxSound.kurz(tw.fx)), CONNECT_ONE_SHOT)
			tw.fx_lesen()
		# Nachts leiser (src/core/nacht_ton.gd): Windows-Lautstärke im Zeitfenster höchstens so laut.
		var nacht = _choice("system.nacht_laut", "Nachts leiser", "Windows-Lautstärke höchstens so laut.", NachtTon.STUFEN)
		nacht.set_meta("uz_such", "Lautstärke Grenze Nacht Nachtmodus")
		nacht.changed.connect(func(_v: Variant) -> void: _rebuild_keep.call_deferred())
		if str(Config.get_value("system.nacht_laut", "aus")) != "aus":
			_choice("system.nacht_von", "Nachts ab", "", NachtTon.VON)
			_choice("system.nacht_bis", "Nachts bis", "", NachtTon.BIS)


# --- Medien -------------------------------------------------------------------------------

func _medien() -> void:
	_head("Videos")
	_choice("youtube.quality", "Qualität", "4K braucht eine schnelle Leitung.",
		[["720", "720p"], ["1080", "1080p"], ["1440", "1440p"], ["2160", "4K"]])
	_toggle("youtube.autoplay", "Automatisch weiter", "")
	_toggle("youtube.subtitles", "Untertitel", "Im Video schaltet X sie um.")
	_toggle("youtube.hide_shorts", "Shorts ausblenden", "Dann nur im Reiter „Shorts“.")
	_toggle("youtube.shorts_tab", "Reiter „Shorts“", "")
	var cats: Array = Config.get_value("youtube.sponsorblock", [])
	_more("Abschnitte überspringen", "",
		"%d von %d" % [cats.size(), YouTube.SB_CATEGORIES.size()] if not cats.is_empty() else "Aus", "skip", _sponsorblock)
	_more("Mehr zu Videos", "", "", "settings", _videos_mehr)
	_head("Filme und Serien")
	_choice("movies.quality", "Qualität der Streams", "", [["auto", "Beste"], ["2160", "4K"], ["1080", "1080p"], ["720", "720p"]])
	_choice("movies.lang_first", "Sprache zuerst", "Quellen in dieser Sprache stehen oben.", [["auto", "Wie die Oberfläche"], ["de", "Deutsch"],
		["en", "Englisch"], ["fr", "Französisch"], ["es", "Spanisch"], ["it", "Italienisch"], ["tr", "Türkisch"], ["aus", "Egal"]])
	_toggle_def("movies.autoplay_next", "Nächste Folge automatisch", "", true)
	_toggle_def("movies.no_p2p", "Kein P2P", "Torrent-Quellen ausblenden.", true)
	_action("Filme-Quellen", "Addons und eigene Medienserver wie Plex oder Jellyfin.",
		", ".join(PackedStringArray(Quellen.order().map(func(k: String) -> String: return str(Quellen.NAMES.get(k, k))))),
			func() -> void: main.open_movie_sources(), "drive")
	_more("Addons und Plugins", "",
		U.plural(Movies.addons.size(), "Addon", "Addons"), "grid", func() -> void:
			_action("Addon hinzufügen", "Adresse, die auf manifest.json endet.", "", func() -> void: MovieManage.ask_install(main), "plus")
			_action("Addons verwalten", "", U.plural(Movies.addons.size(), "Addon", "Addons"), func() -> void: main.goto("movies", "addons"), "grid")
			_action("Plugins verwalten", "", "An" if Movies.plugins_enabled() else "Aus", func() -> void: main.goto("movies", "plugins"), "chip")
			_head("Freiwillig")
			_text("movies.tmdb_key", "TMDB-Schlüssel", "Bessere Bilder und deutsche Beschreibungen.", true)
	)


func _sponsorblock() -> void:
	var cats: Array = Config.get_value("youtube.sponsorblock", [])
	for c in YouTube.SB_CATEGORIES:
		var row = SettingRow.new()
		row.setup("toggle", "%s überspringen" % c[1], "", cats.has(c[0]))
		row.set_meta("uz_path", "youtube.sponsorblock")
		var cat: String = c[0]
		row.changed.connect(func(v: Variant) -> void:
			var cur: Array = (Config.get_value("youtube.sponsorblock", []) as Array).duplicate()
			cur.erase(cat)
			if v:
				cur.append(cat)
			Config.set_value("youtube.sponsorblock", cur)
		)
		_add(row, "SponsorBlock: von Zuschauern markiert. Links springt zurück.")


func _videos_mehr() -> void:
	_choice("youtube.display", "Anzeige", "„Uzai darüber“ bleibt auf manchen PCs schwarz.",
		[["mpv", "Video vorn"], ["overlay", "Uzai darüber"]])
	# Standard: Bild in Bild so laut wie das Video im Vollbild (src/core/video.gd volume_level).
	var pv := _toggle_def("pip.own_volume", "Eigene Lautstärke für Bild in Bild", "", false)
	pv.connect("changed", func(_v: Variant) -> void: Video.set_volume(Video.volume_level()))
	_choice("youtube.cookies", "Empfehlungen von YouTube", "Liest die Anmeldung aus dem Browser, am besten Firefox.", YouTube.BROWSERS)
	if str(Config.get_value("youtube.cookies", "")) == "datei":
		_path("youtube.cookies_file", "cookies.txt", "Im Netscape-Format.", false, ["txt"])
	_choice("youtube.region", "Land für „Angesagt“", "",
			[["DE", "Deutschland"], ["AT", "Österreich"], ["CH", "Schweiz"], ["US", "USA"], ["GB", "Großbritannien"]])
	var langs := str(Config.get_value("youtube.sub_langs", "de,en"))
	var r = _text("youtube.sub_langs", "Untertitel-Sprachen", "Kürzel mit Komma, z. B. de,en")
	if langs != "":
		r.set_value_text(_lang_names(langs))
	_head("Programme")
	_action("yt-dlp", "", "Bereit" if YouTube.has_ytdlp() else "Fehlt", _setup_tools, "download", "ok" if YouTube.has_ytdlp() else "warn")
	_action("Deno", "", "Bereit" if YouTube.has_deno() else "Fehlt", _setup_tools, "download", "ok" if YouTube.has_deno() else "warn")
	_path("youtube.mpv", "mpv", "Leer: Uzai nimmt den mitgeladenen.", false, ["exe"], Callable(),
		"Gefunden: " + (YouTube.mpv_path() if YouTube.has_mpv() else "keiner"))
	_action("Fehlendes laden", "Etwa 150 MB.", "", _setup_tools, "download")
	_head("Daten")
	_action("Verlauf löschen", "",
			U.plural((YouTube.data.history as Array).size(), "Video", "Videos"), func() -> void:
		main.open_dialog("Verlauf löschen?", "Verlauf und Fortschritt werden gelöscht. Abos und Playlists bleiben.", [
			["Löschen", func() -> void:
				var old: Array = (YouTube.data.history as Array).duplicate(true)
				YouTube.clear_history()
				_rebuild_keep()
				Undo.offer_calls("Verlauf gelöscht", U.plural(old.size(), "Video", "Videos"), "history", [YouTube.restore_history.bind(old)], _rebuild_keep), "danger"],
			["Behalten", func() -> void: pass],
		])
	, "trash")


# --- Mitteilungen ---------------------------------------------------------------------------

## Nachrichten von Freunden als Pop-up (Steam, Discord), auch im Spiel. Der Zustand („kommen
## sofort“, „alle 15 Sekunden“, „von Discord abgelehnt“) steht leise unter dem Schalter; die Töne
## stehen unter Klang. Ohne Steam-Anmeldung in Uzai kommt keine Steam-Nachricht an: dann gleich
## „Mit Steam anmelden“ darunter (wie bei Discord).
func _mitteilungen() -> void:
	var st = _toggle("notify.steam", "Steam-Nachrichten", ("Zuletzt: " + SteamCM.keep_error) if SteamCM.keep_error != "" else "")
	# Der echte Weg (SteamChat.weg): vorher stand „Alle 15 Sekunden“ auch dann, wenn neben Steam am PC
	# gar nicht abgefragt wurde.
	var weg := SteamChat.weg()
	var steam_an := bool(Config.get_value("notify.steam", true))
	st.subtitle = str(SteamChat.WEG_TEXT.get(weg, "")) if steam_an else ""
	if steam_an and weg == "keiner":
		_action("Mit Steam anmelden", "", "QR-Code", func() -> void: main.open_chat({ "id": "", "name": "Steam" }, true), "steam", "warn")
	var dt = _toggle("notify.discord", "Discord-Benachrichtigungen", "")
	var d_v := "Discord nicht verbunden – Konten → Discord"
	var fix := ""
	if Voice.extra_rejected or Voice.notices == "abgelehnt":
		d_v = "Von Discord abgelehnt (der Sprachkanal geht trotzdem)"
	elif Voice.notices == "an":
		d_v = "Aktiv"
	elif Voice.notices == "fehlt":
		d_v = "Freigabe fehlt noch"
		fix = "fehlt"
	elif not Voice.ready_():
		fix = "verbinden"
	dt.subtitle = d_v if bool(Config.get_value("notify.discord", true)) else ""
	if bool(Config.get_value("notify.discord", true)) and fix != "":
		_action("Discord neu fragen" if fix == "fehlt" else "Discord verbinden", "", "", func() -> void:
			if Voice.ready_() and Voice.notices == "fehlt":
				Voice.authorize()
			else:
				_show_cat("konten")
				open_more("Discord")
		, "discord", "warn" if fix == "fehlt" else "")
	_toggle("notify.in_game", "Pop-ups im Spiel", "Nicht im exklusiven Vollbild: im Spiel „Randloses Fenster“ wählen.")
	# Steams eigene Pop-ups am Bildschirmrand (steam_still.gd); das Pop-up, das Steams Overlay im Spiel zeichnet, bleibt.
	if Config.is_windows() or Library.demo:
		_toggle_def("notify.steam_still", "Steams Pop-ups ausblenden", "Solange Uzai läuft; danach zeigt Steam sie wieder.", true).set_meta("uz_such",
				"Steam Mitteilungen Benachrichtigungen Toast Erfolge verstecken")
	_toggle_def("notify.ruhe_film", "Nicht stören bei Filmen", "Nachrichten kommen still in die Mitteilungen.", true).set_meta("uz_such",
			"Ruhe Pop-ups stumm Film")
	_head("Shop")
	_toggle_def("notify.wish_sales", "Angebote auf der Wunschliste", "Braucht die Steam-Anmeldung.", true)
	_head("Erfolge")
	_toggle_def("notify.unlock_popups", "Erfolgs-Pop-ups", "Steams Pop-up im Spiel: in Steam abschalten.", true)
	_mehr(_erfolge_popups)


## Mitteilungen › Mehr: Feinheiten der Erfolgs-Pop-ups und eine Vorschau.
func _erfolge_popups() -> void:
	_choice("notify.unlock_pos", "Position", "", [["unten", "Unten in der Mitte"], ["oben", "Oben in der Mitte"]])
	_toggle_def("notify.unlock_rare", "Seltene hervorheben", "Unter 10 % Gold, unter 1 % Platin.", true)
	_toggle_def("accounts.ra_toasts", "RetroAchievements im Spiel", "Braucht Konten → RetroAchievements.", true)
	_action("Test-Pop-up zeigen", "", "", func() -> void:
		main.open_choice("Test-Pop-up", [["normal", "Normal"], ["rare", "Selten"], ["retro", "Retro"], ["komplett", "Alle Erfolge (100 %)"]], "",
				func(v: Variant) -> void:
			Unlocks.test_popup(str(v)))
	, "trophy")


# --- Im Spiel -------------------------------------------------------------------------------

func _im_spiel() -> void:
	_head("Spielstart")
	_toggle_def("system.launch_card", "Spielstart-Karte", "Aus: der schlichte Ladebildschirm.", true)
	_head("Guide")
	_toggle("system.pause_on_guide", "Spiel anhalten, solange der Guide offen ist", "Nur Emulatoren, Steam-Spiele nie.")
	_action("Kacheln im Guide", "", GuideTiles.summary(), func() -> void:
		var s: Control = GuideTiles.open(main)
		s.closed.connect(_rebuild_keep)
	, "grid")
	# Das Schnellmenü selbst geht zum Anpassen auf (wie Menü-Taste im Schnellmenü); B kommt hierher zurück.
	_action("Kacheln im Schnellmenü", "Guide-Taste halten.", GuideQuick.zusammenfassung(), func() -> void:
		var g: Control = GuideQuick.oeffnen_zum_anpassen(main)
		if g:
			g.closed.connect(_rebuild_keep)
	, "edit")
	if Config.is_windows() or Library.demo:
		_toggle_def("system.perf_corner", "Leistung in der Ecke", "Über dem Spiel und im Zimmer. Nicht in Aufnahmen.", false)
	_head("Erweitert")
	var auto := str(Config.get_value("lossless.auto", "aus"))
	_more("Bildrate ×2", "Lossless Scaling.",
		str({ "aus": "Von Hand", "pc": "Bei PC-Spielen", "emu": "Bei Emulator-Spielen", "alle": "Bei allen Spielen" }.get(auto, "")), "bolt", _lossless)
	_more("Remote Play Together", "Freunde per Steam mitspielen lassen.",
		RemotePlay.donor_title() if RemotePlay.configured() else "Einrichten", "steam", _remote_play, "" if RemotePlay.configured() else "accent")


## Aufnahmen › Übertragen: Discord-Übertragung (Taste, Weg, Prüfen).
func _uebertragen() -> void:
	_text("system.stream_keys", "Taste für Discord-Übertragung", "Dieselbe Taste wie in Discord unter „Toggle Screen Share“.")
	_choice("system.live_method", "Übertragen über", "Automatisch: erst die Taste, sonst die Discord-App.",
		[["auto", "Automatisch"], ["keys", "Nur Taste"], ["discord", "Discord-App"]])
	_action("Übertragung prüfen", "", "", func() -> void: main.test_stream_keys(), "discord")


## Aufnahmen: Uzais eigene Aufnahme (Rollpuffer mit FFmpeg, siehe capture.gd) oder über das
## Tastenkürzel der Game Bar bzw. von NVIDIA; dazu die Discord-Übertragung.
func _aufnahmen() -> void:
	var via := str(Config.get_value("capture.via", "uzai"))
	_head("Aufnahme")
	var vr := _choice("capture.via", "Aufnahme über", "Game Bar und NVIDIA über deren Kürzel.",
		[["uzai", "Uzai (eigen)"], ["gamebar", "Windows Game Bar"], ["nvidia", "NVIDIA ShadowPlay"]])
	vr.connect("changed", func(_v: Variant) -> void: _rebuild_keep.call_deferred())
	if via != "uzai":
		_text("system.clip_keys", "Tastenkürzel für Clips", "Game Bar: WIN+ALT+G. NVIDIA: ALT+F10. AMD: CTRL+SHIFT+S.")
	else:
		var ready := Capture.has_ffmpeg()
		_action("FFmpeg", "Freie Software, etwa 190 MB.",
			"Bereit" if ready else ("Wird geladen …" if Capture.installing else "Einrichten"), func() -> void:
				if not Capture.has_ffmpeg() and not Capture.installing:
					CapturesLayer.ask_install(main)
		, "download", "" if ready else "accent")
		# Der Zustand des Puffers steht leise unter dem Schalter.
		var st := "Läuft (letzte %d s)" % Capture.length_s() if Capture.state == "puffer" else ("Startet …" if Capture.state == "startet" else "Ruht")
		var why_t := CapLogic.block_text(Capture.why) if Capture.why not in ["", "fehler"] else ("Letzter Fehler: " + Capture.last_error if Capture.why == "fehler"
				else "")
		var buf := _toggle("capture.buffer", "Clip-Puffer im Spiel", why_t)
		buf.set("subtitle", st)
		_choice("capture.length", "Cliplänge", "", [["15", "15 Sekunden"], ["30", "30 Sekunden"], ["60", "1 Minute"], ["120", "2 Minuten"]])
		_choice("capture.quality", "Qualität", "", [["720", "720p"], ["1080", "1080p"], ["native", "Volle Auflösung"]])
		_toggle("capture.audio", "Ton des Spiels", "")
		_toggle("capture.mic", "Mikrofon", "")
		_toggle("capture.hotkey", "Guide halten + X: Clip speichern", "Die Share-Taste geht auch.")
	_head("Übertragen")
	_uebertragen()
	if via == "uzai":
		_mehr(_aufnahmen_mehr)


## Aufnahmen › Mehr: Bildrate, Bildquelle, Ordner und Grenzen.
func _aufnahmen_mehr() -> void:
	_choice("capture.fps", "Bildrate", "", [["60", "60 Bilder/s"], ["30", "30 Bilder/s"]])
	_choice("capture.source", "Bild", "Bei schwarzem Spielfenster: ganzer Bildschirm.",
		[["screen", "Ganzer Bildschirm"], ["window", "Nur das Spielfenster"]])
	_head("Speicher")
	_path("capture.folder", "Ordner für Clips", "", true, [], Callable(), "Standard: " + Capture.clips_dir())
	_choice("capture.cap_gb", "Speicherplatz für Clips", "Uzai löscht nie selbst.",
		[["10", "10 GB"], ["25", "25 GB"], ["50", "50 GB"], ["100", "100 GB"], ["0", "Unbegrenzt"]])
	_toggle("capture.battery", "Auch im Akkubetrieb", "")
	_toggle("capture.videos", "Auch während Videos", "")
	_choice("capture.discord_mb", "Grenze für Discord", "Größere Clips werden verkleinert.",
		[["10", "10 MB (ohne Nitro)"], ["50", "50 MB (Nitro Basic)"], ["500", "500 MB (Nitro)"]])


func _lossless() -> void:
	var ls := Lossless.exe_path()
	_path("lossless.exe", "Programm", "Lossless Scaling aus deiner Steam-Bibliothek.", false, ["exe"], Callable(),
		"Gefunden: " + (ls if ls != "" else "nicht installiert"))
	var keys := Lossless.HOTKEYS.duplicate()
	if not keys.any(func(k): return k[0] == Lossless.hotkey()):
		keys.append([Lossless.hotkey(), Lossless.key_text(Lossless.hotkey())])
	var hk := Lossless.effective_hotkey()
	var from_ls := str(hk[1]) != "Uzai-Einstellung"
	_choice("lossless.hotkey", "Tastenkürzel", ("Wie „Scale“ in Lossless Scaling, gerade %s." % Lossless.key_text(str(hk[0]))) if from_ls
			else "Wie „Scale“ in Lossless Scaling.", keys)
	_choice("lossless.auto", "Automatisch einschalten", "Pro Spiel unter Optionen änderbar.",
		[["aus", "Nie"], ["pc", "Bei PC-Spielen"], ["emu", "Bei Emulator-Spielen"], ["alle", "Bei allen Spielen"]])
	_slider("lossless.delay", "Warten nach Spielstart", "", 3.0, 30.0, 1.0, "%d s", 1.0)
	_choice("lossless.filter", "Zusammen mit Bildfilter", "", [["aus", "Bildfilter ausschalten"], ["beide", "Beides laufen lassen"]])


## Remote Play Together für jedes Spiel: Spender wählen, Zustand, Emulator-Spiele, rückgängig.
func _remote_play() -> void:
	var on := RemotePlay.configured()
	var st: Array = RemotePlay.status_text()
	var dr := _action("Spender-Spiel", "Steam-Spiel als Startrampe, z. B. RetroArch.",
		RemotePlay.donor_title() if on else "Wählen", func() -> void:
			RemotePlay.choose_donor(main, _rebuild_keep)
	, "steam", "" if on else "accent")
	if not on:
		return
	# Der Zustand des Starters steht leise unter der Zeile.
	dr.set("subtitle", str(st[0]))
	_toggle("remoteplay.emulators", "Emulator-Spiele immer Remote-Play-bereit starten", "")
	_toggle("remoteplay.pc", "PC-Spiele immer Remote-Play-bereit starten", "Epic-Spiele: pro Spiel unter Optionen.")
	_toggle_def("remoteplay.player2", "Spieler 2 automatisch einrichten", "Danach stellt Uzai alles zurück.", true)
	_action("Rückgängig machen", "Legt die Original-Programmdatei zurück.", "", func() -> void:
		var err := RemotePlay.uninstall()
		if err == "":
			Toasts.show_toast("Remote Play Together entfernt", "Das Original ist wieder da.", "check", { "sound": "select" })
		else:
			Toasts.show_toast("Rückgängig ging nicht", err, "warning", { "ms": 7000 })
		_rebuild_keep()
	, "refresh")


# --- Controller ------------------------------------------------------------------------------

func _controller() -> void:
	_head("Tasten")
	var gl := _choice("controller.glyphs", "Tastensymbole", "",
		[["auto", "Automatisch"], ["xbox", "Xbox"], ["ps", "PlayStation"], ["nintendo", "Nintendo"], ["deck", "Steam Deck"], ["handheld", "Handheld"],
			["keys", "Tastatur"]])
	gl.set_meta("uz_such", "Xbox PlayStation Gamepad Glyphen")
	# Was Uzai erkannt hat, steht leise unter der Zeile.
	var seen := str(Handheld.aktiv.name) if not Handheld.aktiv.is_empty() else Nav.pad_name
	if seen != "":
		gl.set("subtitle", tr("Erkannt: %s") % seen)
	_toggle("controller.swap_ab", "A und B tauschen", "Wie bei Nintendo.")
	_choice("controller.guide_hold", "Guide-Taste halten", "Kurz drücken öffnet den Guide. Spiel im Fernseher des Zimmers: zweimal kurz steht auf.",
		[["menu", "Schnellmenü"], ["rest", "Ruhemodus"], ["aus", "Nichts"]])
	_quick_key_row()
	_head("Controller")
	# Rechts steht ein Wert oder nichts: „Zuordnen“, „Öffnen“, „Suchen“ sagten nur, was der Pfeil sagt.
	_action("Spieler & Controller", "Wer Spieler 1–4 ist, auch in Emulatoren.", "", func() -> void:
		load("res://src/ui/layers/spieler_controller.gd").open_for(main)
	, "controller")
	_action("Controller testen", "Start halten testet die Vibration.",
			U.plural(Pads.pads.size(), "Controller", "Controller") + " verbunden" if not Pads.pads.is_empty() else "", func() -> void:
		main.open_layer(load("res://src/ui/layers/pad_test.gd").new())
	, "controller")
	_action("Problemlöser", "Tasten, Drift, Vibration, doppelte Eingaben.", "", func() -> void:
		load("res://src/ui/layers/pad_help.gd").open_for(main)
	, "controller")
	_action("Controller koppeln", "Über Bluetooth.", "", func() -> void:
		load("res://src/ui/layers/pad_pair.gd").open_for(main)
	, "bluetooth")
	# Volle Titel: als Treffer der Suche stehen sie ohne die Überschrift da.
	_head("Gefühl")
	_toggle("controller.vibration", "Vibration bei Haupthandlungen", "Guide, Spielen, Bestätigen, Rand, Fehler.")
	_toggle_def("controller.rumble_events", "Vibration bei Bestätigungen", "Clip gespeichert, Erfolg, Nachricht.", true)
	_mehr(_controller_mehr)


## Controller › Mehr: Seltenes – zweiter Weg zum Guide, Feineinstellung, Windows.
func _controller_mehr() -> void:
	_toggle("controller.guide_combo", "Guide auch mit View + Start", "Ohne Guide-Taste, oder wenn Steam sie belegt.")
	_toggle_def("controller.rumble_friends", "Vibration, wenn Freunde online kommen", "Nur zusammen mit „Vibration bei Bestätigungen“.", false)
	_toggle("controller.hide_mouse", "Mauszeiger ausblenden", "")
	_head("Feineinstellung")
	_slider("controller.deadzone", "Stick-Totzone", "", 0.2, 0.8, 0.05)
	_slider("controller.repeat_delay", "Wiederholen nach", "", 0.15, 0.6, 0.01, "%d ms", 1000.0)
	_slider("controller.repeat_rate", "Tempo beim Halten", "Kleiner ist schneller.", 0.06, 0.22, 0.005, "%d ms", 1000.0)
	_head("Windows")
	_gamebar_row()
	_steam_guide_row()


## Schnellmenü-Taste: eine Zusatztaste am Handheld (oder irgendeine freie Taste) öffnet das
## Schnellmenü wie Guide halten. Belegen: A, dann die Taste drücken; X entfernt die Belegung.
func _quick_key_row() -> void:
	var b := Handheld.belegung(Config.get_value("controller.quick_key", {}))
	var val := Handheld.belegung_text(b)
	if b.is_empty() and not Handheld.aktiv.is_empty():
		val = "F13 bis F24"
	var r := _action("Schnellmenü-Taste", "Für Zusatztasten am Handheld: A, dann die Taste.", val, _quick_learn, "controller")
	r.set_meta("uz_path", "controller.quick_key")
	if not b.is_empty():
		r.set_meta("uz_hint_x", "Entfernen")
		r.set_meta("uz_on_x", func() -> void:
			Config.set_value("controller.quick_key", {})
			_rebuild_keep())


func _quick_learn() -> void:
	Toasts.show_toast("Taste drücken", "Taste drücken. Esc oder B bricht ab.", "controller",
			{ "ms": 8000, "quiet": true })
	Nav.lernen(func(b: Dictionary, grund: String) -> void:
		match grund:
			"":
				Config.set_value("controller.quick_key", b)
				Toasts.show_toast("Schnellmenü-Taste belegt", Handheld.belegung_text(b), "check", { "ms": 3000 })
			"belegt":
				Toasts.show_toast("Diese Taste braucht Uzai schon", "Andere Taste wählen.",
						"warning", { "ms": 6000 })
			"zeit":
				Toasts.show_toast("Keine Taste angekommen",
						"Taste nicht erkannt. Software des Herstellers nutzen oder erneut versuchen.", "warning",
						{ "ms": 7000 })
		_rebuild_keep())

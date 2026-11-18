extends Node
## Logik des Guides ohne Oberfläche: Freunde zusammenführen und sortieren, eigene Zeile im
## Sprachkanal, Spielzeit der Woche. Aufruf: godot --headless --path . res://tests/logic_guide.tscn

const People := preload("res://src/ui/components/guide_people.gd")
const Guide := preload("res://src/ui/layers/guide.gd")
const Main := preload("res://src/main.gd")
const MusicS := preload("res://src/core/music.gd")
const HelperS := preload("res://src/core/helper.gd")
const MyStatus := preload("res://src/core/my_status.gd")
const GuideGame := preload("res://src/ui/components/guide_game.gd")
const Quelle := preload("res://tests/quelle.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Keeps the Game tab uncluttered: at most four quick actions up front, the rest behind „Mehr“;
## nothing is lost, and save and load only appear together.
func _spiel_tests() -> void:
	print("Guide: Reiter Spiel – vorn und hinter „Mehr“")
	var voll := [{ "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "record", "prio": 30 },
		{ "id": "live", "prio": 12 }, { "id": "lossless", "prio": 13 }, { "id": "save", "prio": 25, "pair": "load" },
		{ "id": "load", "prio": 25, "pair": "save" }, { "id": "filter", "prio": 26 }, { "id": "pip", "prio": 31 }]
	var p := GuideGame.plan(voll)
	check(p.primary == ["shot", "clip", "live", "lossless"], "alles eingerichtet: Foto, Clip, Übertragen, Bildrate vorn (%s)" % str(p.primary))
	check(p.more == ["record", "save", "load", "filter", "pip"], "der Rest unter „Mehr“, in fester Reihenfolge")
	var all_ids := voll.map(func(x): return str(x.id))
	check((p.primary + p.more).size() == all_ids.size() and all_ids.all(func(i): return (p.primary + p.more).has(i)), "nichts fällt weg")
	var emu := [{ "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "save", "prio": 25, "pair": "load" },
		{ "id": "load", "prio": 25, "pair": "save" }, { "id": "filter", "prio": 26 }]
	check(GuideGame.plan(emu).primary == ["shot", "clip", "save", "load"], "Emulator: Speichern und Laden zusammen vorn")
	var eng := [{ "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "lossless", "prio": 13 },
		{ "id": "save", "prio": 25, "pair": "load" }, { "id": "load", "prio": 25, "pair": "save" }, { "id": "filter", "prio": 26 }]
	var pe := GuideGame.plan(eng)
	check(pe.primary == ["shot", "clip", "lossless", "filter"] and pe.more == ["save", "load"], "nur ein Platz frei: das Paar bleibt zusammen unter „Mehr“")
	var rec := [{ "id": "overlay", "prio": 0 }, { "id": "shot", "prio": 10 }, { "id": "clip", "prio": 11 }, { "id": "record", "prio": 1 },
		{ "id": "live", "prio": 12 }, { "id": "lossless", "prio": 13 }]
	check(GuideGame.plan(rec).primary == ["overlay", "shot", "clip", "record"], "laufende Aufnahme und offenes Steam-Overlay stehen vorn")
	check(GuideGame.plan([{ "id": "pip", "prio": 31 }, { "id": "x", "prio": 60 }]).primary == ["pip"], "nur unter „Mehr“ (ab Stufe 50) nie vorn")
	check(GuideGame.plan([]).primary.is_empty() and GuideGame.plan([]).more.is_empty(), "ohne Werkzeuge: leer")
	check(GuideGame.capture_line({}) == "Noch keine Clips oder Fotos", "ohne Aufnahmen: klarer Hinweis")
	check(GuideGame.capture_line({ "kind": "clip", "mtime": 0 }) == "Neuester Clip" and GuideGame.capture_line({ "kind": "shot", "mtime": 0 }) == "Bildschirmfoto",
			"Zeile: was es ist")
	check(GuideGame.with_me_text(["Mira"]) == "Mira spielt mit" and GuideGame.with_me_text(["Mira", "Ole"]) == "Mira und Ole spielen mit"
		and GuideGame.with_me_text(["Mira", "Ole", "Ina"]) == "Mira und 2 weitere spielen mit" and GuideGame.with_me_text([]) == "", "Mehrspieler: wer mitspielt")


## Own profile in the Guide (Friends tab): change the status on Steam and Discord. While Steam runs
## on the PC, never via Uzai's own session (that made all friends appear offline there).
func _my_status_tests() -> void:
	print("Guide: dein Status bei Steam und Discord")
	check(MyStatus.steam_route(true, true, true, true, true, false) == "client", "Steam am PC angemeldet: über die Steam-App")
	check(MyStatus.steam_route(true, true, true, true, false, true) == "client", "… auch ohne Steam-Anmeldung in Uzai")
	check(MyStatus.steam_route(true, true, true, false, true, false) == "cm", "Steam läuft, aber niemand angemeldet: Uzais Verbindung")
	check(MyStatus.steam_route(true, true, false, false, true, false) == "cm", "Steam am PC aus: Uzais Verbindung")
	check(MyStatus.steam_route(true, true, false, false, false, false) == "login", "Steam aus und Uzai nicht angemeldet: Hinweis statt Knopf")
	check(MyStatus.steam_route(true, false, false, false, true, true) == "unknown", "Helfer weg (unbekannt, ob Steam läuft): keine eigene Sitzung riskieren")
	check(MyStatus.steam_route(true, true, false, false, true, true) == "unknown", "noch nicht nachgesehen (pc_maybe): nichts senden")
	check(MyStatus.steam_route(false, false, false, false, true, false) == "cm", "ohne Windows: Uzais Verbindung")
	check(MyStatus.steam_url("invisible") == "steam://friends/status/invisible" and MyStatus.steam_url("away") == "steam://friends/status/away"
		and MyStatus.steam_url("online") == "steam://friends/status/online" and MyStatus.steam_url("offline") == "steam://friends/status/offline",
			"offizielle Steam-Links")
	check(MyStatus.steam_url("busy") == "" and MyStatus.steam_url("x\" & calc") == "", "unbekannter Status: kein Link")
	check(MyStatus.steam_exe("c:/program files (x86)/steam") == "c:\\program files (x86)\\steam\\steam.exe" and MyStatus.steam_exe(" ") == "",
			"steam.exe aus dem Registry-Pfad")
	var ids := MyStatus.STEAM_OPTS.map(func(o): return str(o[0]))
	check(ids == ["online", "away", "invisible", "offline"], "Steam: Online, Abwesend, Unsichtbar, Offline")
	var cm_ok := true
	for i in ids:
		cm_ok = cm_ok and MyStatus.steam_from_persona(int(MyStatus.STEAM_CM[i])) == i
	check(cm_ok, "EPersonaState hin und zurück")
	check(MyStatus.steam_from_persona(4) == "away" and MyStatus.steam_from_persona(6) == "online" and MyStatus.steam_from_persona(-1) == "",
			"Schlummern = abwesend, unbekannt = leer")
	var dids := MyStatus.DISCORD_OPTS.map(func(o): return str(o[0]))
	check(dids == ["online", "idle", "dnd", "invisible"] and MyStatus.DISCORD_SDK.dnd == 4 and MyStatus.DISCORD_SDK.invisible == 5
			and MyStatus.DISCORD_SDK.idle == 3, "Discord: Online, Abwesend, Bitte nicht stören, Unsichtbar (StatusType)")
	check(MyStatus.discord_from_sdk("away", 3) == "idle" and MyStatus.discord_from_sdk("offline", 5) == "invisible" and MyStatus.discord_from_sdk("busy") == "dnd"
			and MyStatus.discord_from_sdk("", 6) == "online", "Discord-Status vom SDK")
	print("Status anzeigen: deine Wahl vor veralteten Abfragen")
	check(MyStatus.steam_shown(1, "away", 10) == "away", "gerade gewählt: Wahl gilt, auch wenn Steam noch online meldet")
	check(MyStatus.steam_shown(1, "away", 600) == "online", "später: Steam zählt (anderswo geändert)")
	check(MyStatus.steam_shown(0, "invisible", 600) == "invisible", "unsichtbar meldet Steam als offline: bleibt unsichtbar")
	check(MyStatus.steam_shown(0, "", 0) == "offline" and MyStatus.steam_shown(-1, "", 0) == "", "ohne Wahl: wie Steam")
	check(MyStatus.discord_shown("offline", "invisible", 900) == "invisible" and MyStatus.discord_shown("online", "dnd", 5) == "dnd", "Discord ebenso")
	check(MyStatus.overall("away", "online", false) == "online" and MyStatus.overall("invisible", "", false) == "offline"
			and MyStatus.overall("online", "", true) == "game", "Punkt am Profilbild: wie dich Freunde sehen")
	check(MyStatus.card_line("online", "dnd", true, true, "") == "Steam Online  ·  Discord Bitte nicht stören"
			and MyStatus.card_line("", "", true, false, "") == "Steam –", "Zeile auf der Karte")
	check(MyStatus.card_line("online", "", true, true, "Spielt Hades") == "Spielt Hades", "im Spiel: was läuft")
	check(MyStatus.dot("idle") == "away" and MyStatus.dot("dnd") == "busy" and MyStatus.dot("invisible") == "offline", "Statusfarben")
	check(MyStatus.route_note("login").contains("Einstellungen → Konten") and MyStatus.route_note("client").contains("Steam am PC"), "Hinweise zum Weg")
	check(MyStatus.discord_error("unsupported").contains("Discord-App")
			and MyStatus.discord_error("Unable to find an entry point named 'Discord_Client_SetOnlineStatus'").contains("Discord-App"),
			"alte Discord-Bibliothek: klarer Satz statt Fehlercode")
	print("Ein Fenster nach dem Steam-Link")
	var wins := [{ "hwnd": 50 }, { "hwnd": 60 }]
	check(MyStatus.steam_window_to_close({ "fg_hwnd": 60, "fg_pid": 7 }, [1, 2], wins, 99) == 60, "neues Steam-Fenster vorn: schließen")
	check(MyStatus.steam_window_to_close({ "fg_hwnd": 60, "fg_pid": 7 }, [60], wins, 99) == 0, "war schon offen (Steam-Bibliothek des Nutzers): bleibt")
	check(MyStatus.steam_window_to_close({ "fg_hwnd": 70, "fg_pid": 7 }, [], wins, 99) == 0, "fremdes Fenster (Spiel): nie schließen")
	check(MyStatus.steam_window_to_close({ "fg_hwnd": 60, "fg_pid": 99 }, [], wins, 99) == 0, "Uzai selbst: nichts")
	print("Steam-Sitzung von Uzai: Wahl im Guide")
	var body := SteamCM.user_status_body(7)
	check(body == PackedByteArray([8, 7, 40, 1]), "ClientChangeStatus: Status und „vom Nutzer gewählt“")
	var keep_pc := SteamCM.pc_signed_in
	var keep_known := SteamCM.pc_known
	SteamCM.pc_signed_in = true
	SteamCM.pc_known = true
	var why: String = await SteamCM.choose_status("x", 7)
	check(why.contains("Steam am PC") and SteamCM.state == "zu", "Steam am PC angemeldet: keine eigene Sitzung, nichts gesendet")
	SteamCM.pc_signed_in = keep_pc
	SteamCM.pc_known = keep_known
	var keep_pick := SteamCM.user_pick
	var keep_ps := SteamCM.persona_state
	var keep_until := SteamCM._pick_until
	SteamCM.user_pick = 7
	SteamCM._pick_until = Time.get_ticks_msec() + 60000
	SteamCM.persona_state = 7
	SteamCM.set_persona(1)
	check(SteamCM.persona_state == 7, "kurz nach der Wahl: alte Web-Abfrage ändert nichts")
	SteamCM._pick_until = 0
	SteamCM.set_persona(0)
	check(SteamCM.persona_state == 7 and SteamCM.user_pick == 7, "danach meldet Steam 0: bleibt unsichtbar (kein „online“ fürs Spiel)")
	SteamCM.set_persona(3)
	check(SteamCM.persona_state == 3 and SteamCM.user_pick == -1, "anderswo auf abwesend gestellt: Wahl vergessen")
	SteamCM.user_pick = keep_pick
	SteamCM.persona_state = keep_ps
	SteamCM._pick_until = keep_until


## LT/RT in the Guide only act in the Game tab (on the game) and the Music tab (on the music), nowhere
## else, and never on the Windows master volume.
func _volume_tests() -> void:
	print("Guide: Lautstärke nur bei Spiel und Musik")
	var spot := { "title": "Song", "source": "spotify", "volume": 40 }
	var win := { "title": "Song", "source": "windows", "app": "Spotify.exe", "device": "Spotify" }
	check(Guide.volume_target("spiel", true, false, spot, true) == "spiel", "Spiel: im Spiel nur das Spiel (auch wenn Spotify läuft)")
	check(Guide.volume_target("spiel", true, true, spot, true) == "video", "Spiel: Video läuft → das Video")
	check(Guide.volume_target("spiel", false, false, spot, true) == "kein_spiel", "Spiel ohne Spiel: nur Hinweis")
	check(Guide.volume_target("musik", true, false, spot, true) == "spotify", "Musik mit Spotify: Spotify-Player")
	check(Guide.volume_target("musik", false, false, { "title": "Song", "source": "spotify", "volume": -1 }, true) == "spotify_fest",
			"Spotify-Gerät ohne Lautstärke: Hinweis")
	check(Guide.volume_target("musik", false, false, win, true) == "app", "Musik aus einer Windows-App: diese App")
	check(Guide.volume_target("musik", false, false, {}, true) == "keine_musik", "keine Musik: Hinweis")
	check(Guide.volume_target("musik", false, false, spot, false) == "keine_musik", "ohne Spotify-Konto und ohne Windows-Quelle: nichts")
	var others := true
	for t in ["discord", "freunde", "system", ""]:
		others = others and Guide.volume_target(t, true, true, spot, true) == ""
	check(others, "Discord, Freunde, System: keine Lautstärke")
	check(Guide.volume_hint("spiel") == "Spiel-Lautstärke" and Guide.volume_hint("video") == "Video-Lautstärke"
		and Guide.volume_hint("spotify") == "Spotify-Lautstärke" and Guide.volume_hint("app") == "Musik-Lautstärke", "Hinweisleiste nennt, was LT/RT ändern")
	check(Guide.volume_hint("") == "" and Guide.volume_hint("kein_spiel") == "" and Guide.volume_hint("keine_musik") == "",
			"ohne Ziel: kein LT/RT in der Hinweisleiste")
	check(Guide.volume_level_text("spiel", 45, false) == "Spiel 45 %" and Guide.volume_level_text("app", 30, false, "Chrome") == "Chrome 30 %",
			"Anzeige mit echtem Pegel")
	check(Guide.volume_level_text("video", 0, true) == "Video stumm" and Guide.volume_level_text("spiel", -1, false, "", 1) == "Spiel lauter",
			"stumm bzw. noch ohne Pegel")
	var none_ok := true
	for t in ["kein_spiel", "spiel", "video", "app", "spotify_fest", "keine_musik"]:
		none_ok = none_ok and Guide.volume_none_text(t, "Chrome") != ""
	check(none_ok and Guide.volume_none_text("kein_spiel").contains("Kein Spiel"), "klarer Hinweis, wenn nichts zu steuern ist")
	var ga := Mixer.game_args(4242, "C:/Spiele/Hades", 77)
	check(ga.pids == [4242] and str(ga.dir) == "C:\\Spiele\\Hades" and int(ga.hwnd) == 77, "Spiel: Prozess, Spielordner, Fenster")
	check(Mixer.game_args(0, " ", 0).is_empty(), "nichts bekannt: kein Befehl")
	check(not Mixer.game_args(0, "D:/Steam/steamapps/common/Hades", 0).has("pids"), "Steam-Spiel ohne eigenen Prozess: über den Ordner")
	print("Musik-App erkennen (Audiositzung)")
	check(MusicS.audio_keys("Spotify.exe") == ["spotify"], "Spotify.exe → spotify")
	check(MusicS.audio_keys("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify") == ["spotifyab.spotifymusic", "spotify"], "Store-Spotify: Paketname und Programm")
	check(MusicS.audio_keys("308046B0AF4A39CB") == ["firefox"], "Firefox an seiner Kennung")
	check(MusicS.audio_keys("Chrome") == ["chrome"] and MusicS.audio_keys("MSEdge") == ["msedge"], "Browser")
	check(MusicS.audio_keys("C:\\Program Files\\VideoLAN\\VLC\\vlc.exe") == ["vlc"], "Pfad → Programmname")
	check(MusicS.audio_keys("my_player.exe") == ["my_player"], "Unterstrich im Programmnamen bleibt")
	check(MusicS.audio_keys("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic") == ["microsoft.zunemusic"], "Store-App: Paketname")
	check(MusicS.audio_keys("") == [] and MusicS.audio_keys("ab") == [], "unbekannt: nichts")
	print("Helfer-Antwort app-volume")
	check(
			HelperS.parse_app_volume({ "ok": true, "result": { "json": "{\"found\":true,\"level\":55,\"mute\":false,\"sessions\":2}" } }) == { "found": true,
			"level": 55, "mute": false, "error": false }, "gefunden: Pegel")
	var nf := HelperS.parse_app_volume({ "ok": true, "result": { "json": "{\"found\":false,\"procs\":3}" } })
	check(not bool(nf.found) and not bool(nf.error), "kein Ton gefunden (kein Fehler)")
	var to := HelperS.parse_app_volume({ "ok": true, "result": { "json": "{\"found\":false,\"timeout\":true}" } })
	check(not bool(to.found) and bool(to.error), "Zeitgrenze im Helfer: Fehler, nicht „kein Ton“")
	var nh := HelperS.parse_app_volume({ "ok": false, "error": "nur unter Windows" })
	check(not bool(nh.found) and bool(nh.error), "ohne Helfer: nicht erreichbar")
	check(not bool(HelperS.parse_app_volume({ "ok": true, "result": { "json": "" } }).found), "leere Antwort")
	print("Nirgends mehr die Gesamtlautstärke")
	var master := []
	for f in ["res://src/ui/layers/guide.gd", "res://src/ui/layers/person_menu.gd", "res://src/ui/sections/music_view.gd", "res://src/core/music.gd",
			"res://src/main.gd"]:
		var src := Quelle.lesen(f)
		if src.contains("Helper.run(\"volume\"") or src.contains("Music.volume(") or src.contains("\"volup\"") or src.contains("\"voldown\""):
			master.append(f.get_file())
	check(master.is_empty(), "kein Weg zur Windows-Lautstärke (%s)" % ", ".join(master))
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(ps.contains("'app-volume'") and ps.contains("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F") and ps.contains("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")
		and ps.contains("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d") and ps.contains("87CE5498-68D6-44E5-9215-6DA47EF883D8"),
			"Helfer: app-volume mit den Core-Audio-Schnittstellen")
	check("app-volume" in HelperS.FAST, "app-volume über den schnellen Helfer-Weg")


## Closing and reopening the Guide lost the cover of the current song. A new track arrived without
## an image (Spotify reports the cover to Windows only shortly afterwards), the old cover stayed and
## hid that, and the newly opened Guide then showed no cover at all.
func _cover_tests() -> void:
	print("Guide: Cover nach Schließen und Wiederöffnen")
	var dir := Config.path("test_cover")
	DirAccess.make_dir_recursive_absolute(dir)
	var paths: Array = []
	for i in 2:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2 + 0.6 * i, 0.3, 0.5))
		var p := dir.path_join("cover%d.png" % i)
		img.save_png(p)
		paths.append(p)
	var now_a := { "title": "Lied A", "artist": "Band", "art": paths[0] }
	var g1 = _guide_art()
	g1._refresh_art(now_a)
	await _until(func() -> bool: return g1._music_art.texture != null)
	check(g1._music_art.texture != null and g1._mini_art.texture != null, "erster Guide: Cover groß und klein")
	# Neuer Titel, das Bild fehlt noch: nicht das alte Cover stehen lassen.
	var now_b := { "title": "Lied B", "artist": "Band", "art": "" }
	g1._refresh_art(now_b)
	check(g1._music_art.texture == null and g1._mini_art.texture == null, "neuer Titel ohne Bild: altes Cover weg")
	now_b["art"] = paths[1]
	g1._refresh_art(now_b)
	await _until(func() -> bool: return g1._music_art.texture != null)
	check(g1._music_art.texture != null and str(g1._music_art.texture.get_meta("uz_src", "")) == paths[1], "Bild kommt nach: neues Cover")
	# Gleicher Titel meldet kurz kein Bild (Wechsel Spotify Connect ↔ Windows): Cover bleibt.
	g1._refresh_art({ "title": "Lied B", "artist": "Band", "art": "" })
	check(g1._music_art.texture != null, "derselbe Titel kurz ohne Bild: Cover bleibt")
	# Guide zu und wieder auf: neue Instanz, dasselbe Lied – Cover sofort aus dem Zwischenspeicher.
	_free_guide_art(g1)
	var g2 = _guide_art()
	g2._refresh_art(now_b)
	await _until(func() -> bool: return g2._music_art.texture != null)
	check(g2._music_art.texture != null and g2._mini_art.texture != null, "wieder geöffnet: Cover des laufenden Lieds da")
	# Reiter neu aufgebaut (anderer Reiter und zurück): neues Bildfeld, gleiche Adresse.
	g2._music_art.free()
	g2._music_art = TextureRect.new()
	add_child(g2._music_art)
	g2._refresh_art(now_b)
	await _until(func() -> bool: return g2._music_art.texture != null)
	check(g2._music_art.texture != null, "Reiter neu aufgebaut: Cover wieder da")
	# Spät fertiges Bild eines älteren Titels überschreibt das aktuelle nicht.
	for k in Media._tex.keys():
		Media._drop_tex(str(k))
	g2._art_url = ""
	g2._refresh_art(now_a)
	g2._refresh_art(now_b)
	await _until(func() -> bool: return str(g2._music_art.texture.get_meta("uz_src", "")) == paths[1] and Media._pending.is_empty())
	await get_tree().create_timer(0.3).timeout
	check(str(g2._music_art.texture.get_meta("uz_src", "")) == paths[1], "spätes Bild des alten Titels bleibt draußen")
	_free_guide_art(g2)
	var ps := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(ps.contains("$script:MediaArtTries -lt 8") and ps.contains("throw 'kein Bild'"), "Helfer: fehlendes Cover wird beim nächsten Abfragen erneut gelesen")


func _guide_art():
	var g = Guide.new()
	g._music_art = TextureRect.new()
	g._mini_art = TextureRect.new()
	add_child(g._music_art)
	add_child(g._mini_art)
	return g


func _free_guide_art(g) -> void:
	g._music_art.queue_free()
	g._mini_art.queue_free()
	g.free()


func _until(cond: Callable, sec := 3.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < sec * 1000.0:
		await get_tree().process_frame


func _names(list: Array) -> Array:
	return list.map(func(e): return str(e.name))


func _ready() -> void:
	print("Namen")
	check(People.name_key("Jonas K.") == People.name_key("jonas_k"), "Satzzeichen und Groß/klein egal")
	check(People.name_key("Mira") != People.name_key("Mirai"), "verschiedene Namen bleiben verschieden")
	check(People.title_key("ELDEN RING") == People.title_key("Elden Ring"), "Spieltitel ohne Schreibweise")

	print("Freunde: Steam und Discord getrennt")
	var steam := [
		{ "id": "1", "name": "Mira", "avatar": "", "state": "game", "game": "ELDEN RING", "game_id": "1245620", "lobby": "777", "server": "" },
		{ "id": "2", "name": "Jonas K.", "avatar": "", "state": "game", "game": "Hollow Knight", "game_id": "367520", "lobby": "", "server": "" },
		{ "id": "3", "name": "Lea", "avatar": "", "state": "online", "game": "", "game_id": "", "lobby": "", "server": "" },
		{ "id": "4", "name": "Deniz", "avatar": "", "state": "away", "game": "", "game_id": "", "lobby": "", "server": "" },
		{ "id": "5", "name": "Tom", "avatar": "", "state": "offline", "game": "", "game_id": "", "lobby": "", "server": "" },
		{ "id": "6", "name": "Ute", "avatar": "", "state": "offline", "game": "", "game_id": "", "lobby": "", "server": "" },
	]
	var discord := { "s1": { "name": "Retro-Runde", "channels": [{ "id": "9", "name": "Zocken" }, { "id": "10", "name": "Kino" }],
		"members": [
			{ "name": "lea", "avatar": "http://x/lea.png", "state": "online", "game": "", "channel": "10" },
			{ "name": "kaito", "avatar": "", "state": "dnd", "game": "", "channel": "" },
			{ "name": "geist", "avatar": "", "state": "offline", "game": "", "channel": "" },
			{ "name": "Sana", "avatar": "", "state": "idle", "game": "Balatro", "channel": "9" },
			{ "name": "Noor", "avatar": "", "state": "online", "game": "", "channel": "" },
		] } }
	var voice := [
		{ "id": "a", "name": "Ich", "me": true },
		{ "id": "b", "name": "Mira", "game": "Elden Ring", "me": false },
		{ "id": "c", "name": "pixelpaul", "game": "", "me": false },
	]
	var list := People.build(steam, discord, voice, "9", { "6": 2 })
	var names := _names(list)
	check(names.count("Mira") == 2 and names.has("Lea") and names.has("lea"), "Steam und Discord getrennt, auch bei gleichem Namen")
	check(not names.has("geist") and not names.has("Tom"), "Discord-Offline und Steam-Offline fehlen")
	check(names.has("Ute") and names.back() == "Ute", "offline mit ungelesener Nachricht bleibt, ganz hinten")
	check(names[0] == "Mira", "beitretbar spielend vor anderen Spielenden (%s)" % str(names))
	var lea: Dictionary = list.filter(func(e): return str(e.name) == "lea")[0]
	check(int(lea.rank) == People.RANK_JOIN and str(lea.voice) == "Kino", "Lea ist in einem anderen Kanal: beitretbar")
	check(str(lea.avatar) == "http://x/lea.png", "Bild aus Discord ergänzt")
	var mira_s: Dictionary = list.filter(func(e): return str(e.name) == "Mira" and not (e.steam as Dictionary).is_empty())[0]
	var mira_d: Dictionary = list.filter(func(e): return str(e.name) == "Mira" and (e.steam as Dictionary).is_empty())[0]
	check(bool(mira_d.with_me) and not bool(mira_s.with_me), "Mira bei Discord mit dir im Kanal, der Steam-Eintrag bleibt eigener")
	check(str(mira_s.join_url).begins_with("steam://joinlobby/1245620/777/"), "Lobby-Link für Mira")
	var ranks := list.map(func(e): return int(e.rank))
	var sorted_ranks := ranks.duplicate()
	sorted_ranks.sort()
	check(ranks == sorted_ranks, "erst Spiel, dann beitretbar, dann online, dann abwesend")
	check(names.find("Sana") < names.find("Lea") and names.find("Lea") < names.find("Noor") and names.find("Noor") < names.find("Deniz"),
			"Reihenfolge der Stufen stimmt (%s)" % str(names))
	var px: Dictionary = list[names.find("pixelpaul")]
	check(int(px.rank) == People.RANK_ONLINE and str(People.doing(px)) == "Mit dir im Sprachkanal", "nur im Sprachkanal: online, mit dir")
	check(People.count_online(list) == list.size() - 1, "online gezählt ohne die Offline-Person")

	print("Im Spiel")
	var playing := People.build(steam, discord, voice, "9", {}, "1245620", "Elden Ring")
	var same := playing.filter(func(e): return bool(e.same_game))
	check(same.size() == 2 and same.all(func(e): return str(e.name) == "Mira"), "wer dasselbe Spiel spielt (Steam über die App-ID, Discord über den Titel)")
	var by_title := People.build([], { "s": { "name": "S", "channels": [], "members": [{ "name": "Kai", "state": "online", "game": "Balatro", "channel": "" }] } },
			[], "", {}, "", "Balatro")
	check(bool(by_title[0].same_game), "dasselbe Spiel auch über den Titel (Discord)")
	check(People.better_state("offline", "online") == "online" and People.better_state("game", "away") == "game", "bessere Erreichbarkeit gewinnt")

	print("Eigene Kachel")
	check(People.me_status(false, false, false, false, "", false) == "Mikro an", "ohne alles: Mikro an statt „du“")
	check(People.me_status(false, false, false, false, "Elden Ring", false) == "spielt Elden Ring", "im Spiel")
	check(People.me_status(false, false, false, true, "Elden Ring", false) == "überträgt Elden Ring", "beim Übertragen")
	check(People.me_status(false, true, true, false, "Elden Ring", false) == "Ton aus", "Ton aus geht vor")

	print("Spielzeit")
	check(People.dur(59) == "1 Min." and People.dur(5400) == "1,5 Std." and People.dur(3600) == "1 Std." and People.dur(432000) == "120 Std.", "kurze Dauer")
	var now := 1_700_000_000
	var sessions := [{ "id": "g", "at": now - 60, "secs": 600 }, { "id": "g", "at": now - 86400, "secs": 1200 },
		{ "id": "x", "at": now - 60, "secs": 999 }, { "id": "g", "at": now - 8 * 86400, "secs": 50 }]
	var w := People.week(sessions, "g", now, 0)
	check(w.size() == 7 and int(w[6]) == 600 and int(w[5]) == 1200 and People.sum(w) == 1800, "Woche: heute rechts, älter fällt weg")
	check(People.sum(People.week(sessions, "", now, 0)) == 2799, "alle Spiele zusammen")
	var labels := People.week_labels(now, 0)
	check(labels.size() == 7 and str(labels[6]) == "Di", "Wochentage passend (%s)" % str(labels))

	print("Nach Lage getrennt (Quelle nur bei gemischter Liste)")
	var mix := [
		{ "name": "A", "steam": { "id": "1" }, "discord": {}, "dm": {}, "state": "online", "game": "Elden Ring", "rank": People.RANK_GAME },
		{ "name": "B", "steam": {}, "discord": { "name": "B" }, "dm": {}, "state": "online", "game": "", "rank": People.RANK_ONLINE },
		{ "name": "C", "steam": { "id": "3" }, "discord": { "name": "C" }, "dm": {}, "state": "away", "game": "", "rank": People.RANK_AWAY },
		{ "name": "D", "steam": {}, "discord": {}, "dm": { "id": "9" }, "state": "online", "game": "Valorant", "rank": People.RANK_GAME },
	]
	var gs := People.sections(mix)
	check(gs.size() == 3 and str(gs[0].id) == "spiel" and str(gs[1].id) == "online" and str(gs[2].id) == "abwesend",
			"drei Abschnitte: im Spiel, online, abwesend")
	check((gs[0].items as Array).map(func(e): return str(e.name)) == ["A", "D"], "im Spiel: Steam und Discord zusammen")
	check((gs[1].items as Array).map(func(e): return str(e.name)) == ["B"] and (gs[2].items as Array).map(func(e): return str(e.name)) == ["C"],
			"abwesend steht für sich, nicht unter online")
	check(People.mixed(mix) and not People.mixed(mix.slice(0, 1)), "Quelle nur, wenn Steam und Discord gemischt sind")
	# Reihenfolge wie gewünscht: dein Spiel, offene Lobby, andere Spiele, dann anderer Sprachkanal, online.
	var order := People.build([
		{ "id": "1", "name": "Yan", "state": "online", "game": "Hades", "game_id": "5" },
		{ "id": "2", "name": "Zed", "state": "online", "game": "Tetris", "game_id": "7", "lobby": "109775241234" },
		{ "id": "3", "name": "Xia", "state": "online", "game": "Elden Ring", "game_id": "1245620" },
		{ "id": "4", "name": "Abe", "state": "online" },
		{ "id": "5", "name": "Bob", "state": "away" },
	], {}, [], "", {}, "1245620", "Elden Ring")
	var fnames := order.map(func(e): return str(e.name))
	check(fnames == ["Xia", "Zed", "Yan", "Abe", "Bob"],
			"dein Spiel zuerst, dann Lobby, dann andere Spiele, online, abwesend (%s)" % str(fnames))
	var pm := Quelle.lesen("res://src/ui/layers/person_menu.gd")
	check(not pm.contains("_item(\"Profil\", \"user\", \"Discord\""), "kein Discord-Profil im Menü an der Person (zeigte dasselbe Menü)")
	check(People.sections(mix.slice(0, 1)).size() == 1 and People.sections([]).is_empty(), "leere Abschnitte fallen weg")
	print("Neue Nachrichten ganz oben (Wunsch aus dem Freund-Test 0.16.51)")
	var msgs := People.build([
		{ "id": "1", "name": "Abe", "state": "online", "game": "Hades", "game_id": "5" },
		{ "id": "2", "name": "Bea", "state": "online" },
		{ "id": "3", "name": "Cid", "state": "offline" },
		{ "id": "4", "name": "Dan", "state": "online" },
		{ "id": "5", "name": "Eli", "state": "offline" },
	], {}, [], "", { "2": 1, "3": 4 }, "", "", [{ "id": "d7", "name": "Fay", "state": "online" }, { "id": "d8", "name": "Gus", "state": "offline" }],
			{ "d8": 2 }, { "2": 1000, "3": 3000 }, { "d8": 2000 })
	var ms := People.sections(msgs)
	check(str(ms[0].id) == "neu" and str(ms[0].title) == "Neue Nachrichten", "erster Abschnitt: Neue Nachrichten")
	check((ms[0].items as Array).map(func(e): return str(e.name)) == ["Cid", "Gus", "Bea"],
			"neueste Nachricht zuerst, Steam und Discord gemischt, auch offline (%s)" % str((ms[0].items as Array).map(func(e): return str(e.name))))
	check(int((ms[0].items as Array)[0].unread) == 4, "Zähler bleibt am Eintrag (Pille)")
	var rest_ids := ms.slice(1).map(func(x): return str(x.id))
	check(rest_ids == ["spiel", "online"], "danach im Spiel und online; ohne Ungelesenes kein Offline (%s)" % str(rest_ids))
	var on_names: Array = (ms[2].items as Array).map(func(e): return str(e.name))
	check(not on_names.has("Bea") and on_names.has("Dan") and on_names.has("Fay"), "wer oben steht, kommt unten nicht noch einmal")
	var ohne_zeit := People.sections(People.build([{ "id": "1", "name": "Zoe", "state": "online" }, { "id": "2", "name": "Al", "state": "offline" }],
			{}, [], "", { "1": 1, "2": 1 }))
	check((ohne_zeit[0].items as Array).map(func(e): return str(e.name)) == ["Zoe", "Al"], "ohne Zeit: online vor offline")
	# Erster Reiter heißt „Start“ (auch im Spiel) bzw. „Video“, solange eins läuft.
	var was_in := Launcher.in_game
	var was_v := Video.active
	Launcher.in_game = false
	Video.active = false
	check(Guide.game_tab_label() == "Start", "ohne Spiel: Reiter „Start“")
	Launcher.in_game = true
	check(Guide.game_tab_label() == "Start", "im Spiel: auch „Start“ (das Spiel steht oben im Reiter)")
	Video.active = true
	check(Guide.game_tab_label() == "Video", "Video läuft: Reiter „Video“")
	Launcher.in_game = was_in
	Video.active = was_v
	print("Discord-Streams: Kanal-Link")
	check(Guide.discord_channel_url({ "id": "9", "name": "Zocken", "guild_id": "1" }) == "discord://-/channels/1/9", "Serverkanal: Server/Kanal")
	check(Guide.discord_channel_url({ "id": "42", "name": "Anruf", "guild_id": "" }) == "discord://-/channels/@me/42", "Anruf ohne Server: @me")
	check(Guide.discord_channel_url({}) == "", "in keinem Kanal: kein Link")
	print("Guide-Taste: doppelte Meldungen")
	var m: Control = Main.new()
	check(not m._guide_dup("pad") and m._guide_dup("helper"), "Godot und Helfer melden denselben Druck: nur einmal")
	OS.delay_msec(120)
	check(not m._guide_dup("pad"), "zweiter Druck kurz danach (Guide wieder zu): zählt")
	check(m._guide_dup("helper"), "… und auch dessen Helfer-Meldung nur einmal")
	OS.delay_msec(120)
	check(not m._guide_dup("helper") and m._guide_dup("pad"), "Helfer zuerst, Godot hinterher: einmal")
	OS.delay_msec(120)
	check(not m._guide_dup("menu") and m._guide_dup("combo") and m._guide_dup("helper"), "Start, dann View + Start: eine Geste")
	OS.delay_msec(500)
	check(not m._guide_dup("menu") and not m._guide_dup("pad"), "Start und Guide-Taste sind zwei Drücke")
	check(not m._guide_dup("") and not m._guide_dup(""), "Uzai selbst (Anruf, Probe): jeder Aufruf zählt")
	m.free()
	print("Übertragen und Freunde online")
	var was_in2 := Launcher.in_game
	var was_v2 := Video.active
	var mm: Control = Main.new()
	Launcher.in_game = false
	Video.active = false
	check(mm.live_source() == "", "nichts läuft: kein Übertragen")
	Video.active = true
	check(mm.live_source() == "video", "Video läuft: Video übertragen")
	Launcher.in_game = true
	check(mm.live_source() == "spiel", "im Spiel: das Spiel")
	var ok_r := { "ok": true, "result": { "sent": true, "accepted": 6, "expected": 6, "discord": [{ "name": "Discord" }] } }
	check(Main.live_problem(ok_r, "CTRL+SHIFT+F9", true) == "", "Übertragen: Taste angekommen, kein Fehler")
	check(
			Main.live_problem({ "ok": true, "result": { "sent": false, "reason": "unbekannt", "unknown": ["UMSCHALTT"] } }, "STRG+UMSCHALTT+F9",
			true).contains("UMSCHALTT"), "Übertragen: Tippfehler in der Taste wird genannt")
	check(
			Main.live_problem({ "ok": true, "result": { "sent": true, "accepted": 6, "expected": 6, "discord": [] } }, "CTRL+SHIFT+F9",
			true).contains("Discord-App läuft nicht"), "Übertragen: Discord läuft nicht")
	check(
			Main.live_problem({ "ok": true,
			"result": { "sent": true, "foreground": "Spiel", "foreground_elevated": true, "self_elevated": false, "discord": [{ "name": "Discord" }] } },
			"CTRL+SHIFT+F9", true).contains("Administratorrechten"), "Übertragen: Spiel mit Adminrechten")
	check(Main.live_problem({ "ok": false, "error": "x" }, "CTRL+SHIFT+F9", false) == "", "Übertragen: ohne Windows keine Meldung")
	var rep: String = Main.live_report(ok_r, ["Ctrl (links)", "Shift (links)", "F9"], "CTRL+SHIFT+F9", 0, "")
	check(rep.contains("Ctrl (links) + Shift (links) + F9") and rep.contains("keiner") and rep.contains("Toggle Screen Share"),
			"Übertragung prüfen: was ankam, Sprachkanal, wo eintragen")
	# Timeout on a real PC: fall back to the Discord app
	var to_r := { "ok": false, "error": "Zeitüberschreitung", "timeout": true, "ahead": 1 }
	check(Main.live_problem_kind(to_r, true) == "timeout" and Main.live_problem(to_r, "CTRL+SHIFT+F9", true).contains("beschäftigt")
			and Main.live_fallback_ok("timeout"), "Übertragen: Zeitüberschreitung → klare Meldung, weiter in der Discord-App")
	check(Main.live_problem_kind({ "ok": false, "error": "Helfer antwortet nicht" }, true) == "helper"
			and Main.live_problem({ "ok": false, "error": "x" }, "K", true).contains("helper.log"), "Übertragen: Helfer läuft nicht → Hinweis auf helper.log")
	check(not Main.live_fallback_ok("no_discord") and not Main.live_fallback_ok(""), "ohne Discord-App kein Weg über die App, ohne Fehler auch nicht")
	var unk_elev := { "ok": true,
			"result": { "sent": true, "accepted": 6, "expected": 6, "foreground_elevated": false, "foreground_elev": null,
			"discord": [{ "name": "Discord", "elevated": null }] } }
	check(Main.live_problem(unk_elev, "K", true) == "", "Rechte unbekannt (Spielschutz) zählt nicht als Admin")
	check(
			Main.live_problem_kind({ "ok": true, "result": { "sent": true, "accepted": 6, "expected": 6, "discord": [{ "name": "Discord", "elevated": true }] } },
			true) == "discord_elevated", "Discord mit Adminrechten wird erkannt")
	check(
			Main.live_problem_kind({ "ok": true,
			"result": { "sent": true, "accepted": 6, "expected": 6, "self_elevated": true, "discord": [{ "name": "Discord", "elevated": true }] } }, true) == "",
			"Uzai und Discord beide mit Adminrechten: kein Problem")
	check(
			Main.live_problem_kind({ "ok": true, "result": { "done": false, "stage": "drücke", "accepted": 2, "expected": 6, "discord": [{ "name": "Discord" }] } },
			true) == "stuck", "Druck nicht fertig in der Zeitgrenze: stuck")
	check(
			Main.live_problem_kind({ "ok": true, "result": { "done": true, "accepted": 6, "fallback": 6, "expected": 6, "discord": [{ "name": "Discord" }] } },
			true) == "", "Ersatzweg (keybd_event) zählt als angenommen")
	var rep2: String = Main.live_report(ok_r, [], "K", 1, "Zocken", { "helper": { "available": false } })
	check(rep2.contains("Windows-Helfer: läuft nicht") and rep2.contains("In Discord übertragen") and rep2.contains("„Zocken“"),
			"Übertragung prüfen: Helfer-Zustand und Weg über die App")
	var rep3: String = Main.live_report(
			{ "ok": true, "result": { "accepted": 6, "expected": 6, "fallback": 6, "self_elevated": false, "discord": [{ "name": "Discord", "elevated": true }] } },
			["F9"], "F9", 1, "x", { "helper": { "available": true, "fast": { "ready": true } }, "game": [{ "name": "game.exe", "elevated": true }] })
	check(rep3.contains("Windows-Helfer: läuft.") and rep3.contains("6 davon über den Ersatzweg") and rep3.contains("Discord normal starten")
			and rep3.contains("„game.exe“ mit"), "Übertragung prüfen: Zählung, Ersatzweg, Rechte von Discord und Spiel")
	print("In Discord übertragen: Knöpfe finden")
	check(Main.share_kind("Share Your Screen") == "share" and Main.share_kind("Bildschirm teilen") == "share", "Bildschirm teilen (en/de)")
	check(Main.share_kind("Stream Elden Ring") == "stream" and Main.share_kind("Elden Ring streamen") == "stream", "Spiel streamen (en/de)")
	check(Main.share_kind("Go Live") == "golive" and Main.share_kind("Live gehen") == "golive", "Live gehen (en/de)")
	check(Main.share_kind("Stop Streaming") == "stop" and Main.share_kind("Stream beenden") == "stop", "Stream beenden (en/de)")
	check(Main.share_kind("Streamer-Modus") == "" and Main.share_kind("Stream ansehen") == "" and Main.share_kind("Watch Stream") == ""
			and Main.share_kind("Stream-Einstellungen") == "", "Zuschauen, Streamer-Modus und Einstellungen sind keine Treffer")
	var btns := [{ "i": 0, "name": "Mikrofon stummschalten", "enabled": true }, { "i": 1, "name": "Bildschirm teilen", "enabled": true },
		{ "i": 2, "name": "Stream Hades", "enabled": true }, { "i": 3, "name": "Stream ELDEN RING", "enabled": true }]
	check(int(Main.share_pick(btns, "Elden Ring", true).i) == 3, "eigenes Spiel streamen vor anderem Spiel und vor Bildschirm teilen")
	check(int(Main.share_pick(btns.slice(0, 2), "Elden Ring", true).i) == 1, "ohne Spiel-Knopf: Bildschirm teilen")
	check(Main.share_pick(btns, "Elden Ring", true, true).is_empty(), "Fenster schon offen: nur noch Live gehen")
	var modal := [{ "i": 0, "name": "Go Live", "enabled": false }, { "i": 1, "name": "Abbrechen", "enabled": true }]
	check(Main.share_pick(modal, "x", true, true).is_empty(), "Live gehen ausgegraut (nichts gewählt): nicht drücken, du wählst")
	modal[0].enabled = true
	check(str(Main.share_pick(modal, "x", true, true).kind) == "golive", "Live gehen an: drücken")
	var live_btns := [{ "i": 0, "name": "Stop Streaming", "enabled": true }, { "i": 1, "name": "Bildschirm teilen", "enabled": true }]
	check(Main.live_now(live_btns) and not Main.live_now(btns), "läuft schon (Stream-beenden-Knopf) erkannt")
	check(str(Main.share_pick(live_btns, "x", false).kind) == "stop" and Main.share_pick(btns, "x", false).is_empty(), "beenden: nur der Stopp-Knopf")
	check(Main.live_hint(true, "Hades").contains("„Hades streamen“") and Main.live_hint(true, "").contains("Guide-Taste"), "Hinweis-Karte nennt Knopf und Rückweg")
	print("Helfer-Weg für den Tastendruck")
	check(Helper.pick_lane({ "ready": true, "n": 0, "ms": 0 }, { "ready": true, "n": 0, "ms": 0 }) == "fast", "schneller Weg frei: schneller Weg")
	check(Helper.pick_lane({ "ready": true, "n": 1, "ms": 5000 }, { "ready": true, "n": 0, "ms": 0 }) == "main", "schneller Weg hängt, Hauptweg frei: Hauptweg")
	check(Helper.pick_lane({ "ready": true, "n": 1, "ms": 5000 }, { "ready": true, "n": 2, "ms": 9000 }) == "fast", "beide beschäftigt: der kürzer beschäftigte")
	check(Helper.pick_lane({ "ready": false }, { "ready": true, "n": 3, "ms": 100 }) == "main", "schneller Weg nicht bereit: Hauptweg")
	check(Helper.pick_lane({ "ready": true, "n": 1, "ms": 300 }, { "ready": true, "n": 0, "ms": 0 }) == "fast",
			"kurz beschäftigt (< 1 s): bleibt beim schnellen Weg")
	print("Startbildschirm vorn halten")
	check(not Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 77 }, 77), "Uzai vorn: Startbildschirm bleibt")
	check(not Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 9, "fg_full": true }, 77), "Vollbildfenster vorn: bleibt (gleich kommt das Spiel)")
	check(not Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 9, "fg_shell": true }, 77), "Taskleiste vorn: bleibt")
	check(not Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 9, "fg_game": true, "fg_w": 1280, "fg_h": 720 }, 77),
			"großes Spielfenster: bleibt (der Start wartet darauf)")
	check(Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 9, "fg_game": true, "fg_w": 420, "fg_h": 180 }, 77),
			"Fehlermeldung des Emulators: gibt den Vorrang ab")
	check(Main.cover_should_yield({ "fg_hwnd": 5, "fg_pid": 9, "fg_w": 600, "fg_h": 300 }, 77), "Steam-Dialog: gibt den Vorrang ab")
	Launcher.in_game = was_in2
	Video.active = was_v2
	mm.free()
	var keep_s := Social.steam_friends
	var keep_d := DiscordChat.friends
	var keep_demo := DiscordChat.demo
	Social.steam_friends = [{ "id": "1", "state": "online" }, { "id": "2", "state": "offline" }, { "id": "3", "state": "game" }]
	DiscordChat.friends = [{ "id": "a", "state": "online" }, { "id": "b", "state": "offline" }]
	DiscordChat.demo = true
	check(Main.online_friends() == 3, "Freunde online: Steam und Discord, ohne Offline")
	DiscordChat.demo = false
	DiscordChat.friends = []
	check(Main.online_friends() == 2, "ohne Discord-Anmeldung nur Steam")
	Social.steam_friends = keep_s
	DiscordChat.friends = keep_d
	DiscordChat.demo = keep_demo
	print("Guide: Neuaufbau nur bei Änderungen")
	var p1 := People.build([{ "id": "1", "name": "Mira", "avatar": "", "state": "online" }, { "id": "2", "name": "Tom", "avatar": "", "state": "offline" }], {},
			[], "", {})
	var p2 := People.build([{ "id": "1", "name": "Mira", "avatar": "", "state": "online" }, { "id": "2", "name": "Tom", "avatar": "", "state": "offline" }], {},
			[], "", {})
	var p3 := People.build([{ "id": "1", "name": "Mira", "avatar": "", "state": "online" }, { "id": "2", "name": "Tom", "avatar": "", "state": "online" }], {}, [],
			"", {})
	var p4 := People.build([{ "id": "1", "name": "Mira", "avatar": "", "state": "game", "game": "Hades", "game_id": "1145360" }], {}, [], "", {})
	check(Guide._people_key(p1) == Guide._people_key(p2), "gleiche Leute, gleicher Stand: kein Neuaufbau")
	check(Guide._people_key(p1) != Guide._people_key(p3), "Tom kommt online: neu")
	check(Guide._people_key(p1) != Guide._people_key(p4), "Mira startet ein Spiel: neu")
	_volume_tests()
	_spiel_tests()
	await _my_status_tests()
	await _cover_tests()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

extends Node
## Spotify im Grundmodus (ohne eigene Spotify-App): eigener Verlauf aus dem Zustand von Spotify
## Connect (strenge Prüfung von URIs, Texten und Covern), Begrenzung, Reihen „Zuletzt“, „Oft“ und
## „Playlists & Alben zuletzt“, Reihen aus dem Spotify-Fenster am PC (Antwort des Helfers), Befehle zum Abspielen daraus (connect-state, nicht die Web-API) und
## Ruhe im Netz, sobald Spotify den Weg nicht zulässt. Ohne Netz.
## Aufruf: godot --headless --path . res://tests/logic_spotify_verlauf.tscn

const Verlauf := preload("res://src/core/spotify_verlauf.gd")
const Intern := preload("res://src/core/spotify_intern.gd")
const SpotifyPc := preload("res://src/core/spotify_pc.gd")

const T1 := "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
const T2 := "spotify:track:7ouMYWpwJ422jRcDASZB7P"
const T3 := "spotify:track:0VjIjW4GlUZAMYd2vXMi3b"
const PL := "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
const AL := "spotify:album:6dVIqQ8qmQ5GBnJ9shOYGE"
const IMG := "ab67616d0000b273e8b066f70c206551210d902b"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_uris()
	_texte()
	_cluster()
	_reihen()
	_datei()
	_befehle()
	_pc()
	await _ruhe()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _uris() -> void:
	print("URIs und Cover")
	check(Verlauf.uri_ok(T1) and Verlauf.uri_ok(PL) and Verlauf.uri_ok(AL), "gültige URIs")
	check(Verlauf.uri_ok("spotify:show:5CfCWKI5pZ28U0uOzXkDHe") and Verlauf.uri_ok("spotify:artist:0OdUWJ0sBjDrqHygGUXeCF"), "Show und Künstler")
	check(not Verlauf.uri_ok("spotify:track:4uLU6hMCjMI75M1A2tKUQ"), "21 Zeichen: nein")
	check(not Verlauf.uri_ok("spotify:track:4uLU6hMCjMI75M1A2tKUQCx"), "23 Zeichen: nein")
	check(not Verlauf.uri_ok("spotify:user:abc:collection") and not Verlauf.uri_ok("spotify:local:a:b:c:1"), "andere Arten: nein")
	check(not Verlauf.uri_ok("spotify:track:4uLU6hMCjMI75M1A2tKU/C") and not Verlauf.uri_ok("spotify:track:4uLU6hMCjMI75M1A2tKUQC\n"), "Sonderzeichen: nein")
	check(not Verlauf.uri_ok(12345) and not Verlauf.uri_ok(null) and not Verlauf.uri_ok(["x"]), "kein Text: nein")
	check(Verlauf.uri_ok(PL, ["album", "playlist"]) and not Verlauf.uri_ok(T1, ["album", "playlist"]), "Arten einschränken")
	check(Verlauf.art_url("spotify:image:" + IMG) == "https://i.scdn.co/image/" + IMG, "Bild aus Spotify Connect → i.scdn.co")
	check(Verlauf.art_url("https://i.scdn.co/image/" + IMG) != "", "i.scdn.co erlaubt")
	check(Verlauf.art_url("https://mosaic.scdn.co/640/ab67616d0000b273") != "", "mosaic.scdn.co erlaubt")
	check(Verlauf.art_url("https://evil.example/image/" + IMG) == "", "fremder Host: nein")
	check(Verlauf.art_url("https://i.scdn.co.evil.example/image/x") == "", "Host als Vorsilbe: nein")
	check(Verlauf.art_url("http://i.scdn.co/image/" + IMG) == "", "ohne https: nein")
	check(Verlauf.art_url("https://i.scdn.co/../etc/passwd") == "", "Pfad mit ..: nein")
	check(Verlauf.art_url("https://i.scdn.co/image/a?x=1") == "" and Verlauf.art_url("https://user@i.scdn.co/image/a") == "", "Abfrage oder Anmeldung in der Adresse: nein")
	check(Verlauf.art_url("spotify:image:zz") == "" and Verlauf.art_url("C:/Windows/x.png") == "" and Verlauf.art_url(5) == "", "kaputte Bilder: leer")


func _texte() -> void:
	print("Texte")
	check(Verlauf.clean("To\u0001 Zanarkand\u202E\u200B") == "To Zanarkand", "Steuer- und Richtungszeichen weg")
	check(Verlauf.clean("a\n\nb\tc") == "a b c", "Umbrüche als Leerzeichen")
	check(Verlauf.clean("x".repeat(5000)).length() == Verlauf.TEXT_MAX, "auf Länge gekürzt")
	check(Verlauf.clean(42) == "" and Verlauf.clean({ "a": 1 }) == "", "kein Text: leer")
	check(Verlauf.clean("Ünïcödé – 東京") == "Ünïcödé – 東京", "Umlaute und Schriftzeichen bleiben")


static func _cl(uri: Variant, title: Variant, ctx: Variant, playing := true, desc: Variant = "") -> Dictionary:
	return { "active_device_id": "abc", "player_state": {
		"is_playing": playing, "is_paused": false, "context_uri": ctx, "context_metadata": { "context_description": desc },
		"track": { "uri": uri, "metadata": { "title": title, "artist_name": "Nobuo Uematsu", "album_title": "Final Fantasy X",
			"album_uri": AL, "artist_uri": "spotify:artist:3V79CTgRnsDdJSTqKitROv", "image_large_url": "spotify:image:" + IMG } } } }


func _cluster() -> void:
	print("Verlauf aus dem Zustand von Spotify Connect")
	var e := Verlauf.from_cluster(_cl(T1, "To Zanarkand", PL, true, "Spieleklassiker"), 1000)
	check(str(e.get("u", "")) == T1 and str(e.t) == "To Zanarkand" and str(e.a) == "Nobuo Uematsu", "Titel, Künstler")
	check(str(e.c) == PL and str(e.cn) == "Spieleklassiker", "Playlist als Kontext mit Namen")
	check(str(e.art) == "https://i.scdn.co/image/" + IMG and str(e.alu) == AL, "Cover und Album")
	var ea := Verlauf.from_cluster(_cl(T1, "To Zanarkand", AL), 1000)
	check(str(ea.cn) == "Final Fantasy X", "Album als Kontext: Name aus dem Album")
	check(Verlauf.from_cluster(_cl(T1, "To Zanarkand", PL, false), 1000).is_empty(), "pausiert: kein Eintrag")
	check(Verlauf.from_cluster(_cl("spotify:track:kaputt", "X", PL), 1000).is_empty(), "kaputte Titel-URI: kein Eintrag")
	check(Verlauf.from_cluster(_cl(T1, 12345, PL), 1000).is_empty(), "Titel als Zahl: kein Eintrag")
	check(Verlauf.from_cluster(_cl(T1, "", PL), 1000).is_empty(), "ohne Titel: kein Eintrag")
	var ex := Verlauf.from_cluster(_cl(T1, "", PL), 1000, { "title": "Aus Windows", "artist": "B", "album": "C" })
	check(str(ex.get("t", "")) == "Aus Windows" and str(ex.c) == PL, "Titel aus der Mediensitzung, Kontext aus Spotify Connect")
	var eu := Verlauf.from_cluster(_cl(T1, "X", "spotify:user:jemand:collection"), 1000)
	check(str(eu.c) == "" and str(eu.cn) == "", "Kontext außerhalb des Musters: weggelassen")
	var ej := Verlauf.from_cluster(_cl(T1, "X", ["spotify:playlist:" + "a".repeat(22)], true, { "x": 1 }), 1000)
	check(str(ej.c) == "" and str(ej.cn) == "", "Kontext als Liste: weggelassen")
	check(Verlauf.from_cluster("kein json", 1) == {} and Verlauf.from_cluster({ "player_state": [] }, 1) == {}, "falsche Typen: nichts")
	var big := _cl(T1, "T", PL)
	big.player_state.track.metadata["image_large_url"] = "https://evil.example/x.jpg"
	check(str(Verlauf.from_cluster(big, 1).art) == "", "fremdes Cover: leer")
	var n := Verlauf.from_now({ "uri": T2, "title": "Gerudo Valley", "artist": "Koji Kondo", "playing": true, "context": PL }, 5)
	check(str(n.u) == T2 and str(n.c) == PL, "aus Läuft gerade (eigene Spotify-App)")
	check(Verlauf.from_now({ "uri": T2, "title": "x", "playing": true, "source": "windows" }, 5).is_empty(), "Windows-Quelle: kein Eintrag")


func _reihen() -> void:
	print("Begrenzung und Reihen")
	var list: Array = []
	var e1 := Verlauf.from_cluster(_cl(T1, "Eins", PL, true, "Spieleklassiker"), 1000)
	list = Verlauf.add(list, e1)
	list = Verlauf.add(list, Verlauf.from_cluster(_cl(T1, "Eins", PL, true, "Spieleklassiker"), 1100))
	check(list.size() == 1, "derselbe Titel kurz danach: ein Eintrag")
	list = Verlauf.add(list, Verlauf.from_cluster(_cl(T2, "Zwei", AL), 1300))
	list = Verlauf.add(list, Verlauf.from_cluster(_cl(T1, "Eins", PL, true, "Spieleklassiker"), 1500))
	list = Verlauf.add(list, Verlauf.from_cluster(_cl(T3, "Drei", PL, true, "Spieleklassiker"), 1700))
	list = Verlauf.add(list, Verlauf.from_cluster(_cl(T1, "Eins", AL), 1700 + Verlauf.SAME_PLAY_S + 1))
	check(list.size() == 5 and str(list[0].u) == T1, "neueste zuerst, wiederholt nach Pause zählt neu")
	var rec := Verlauf.recent(list)
	check(rec.size() == 3 and str(rec[0].uri) == T1 and str(rec[1].uri) == T3 and str(rec[2].uri) == T2, "Zuletzt gehört: jeder einmal")
	check(str(rec[0].title) == "Eins" and str(rec[0].id) == T1.get_slice(":", 2), "als Titel in Uzais Form")
	var oft := Verlauf.frequent(list)
	check(oft.size() == 1 and str(oft[0].uri) == T1 and int(oft[0].plays) == 3, "Oft gehört: nur mehrfach Gehörtes, mit Anzahl")
	var ctx := Verlauf.contexts(list)
	check(ctx.size() == 2 and str(ctx[0].uri) == AL and str(ctx[1].uri) == PL, "Playlists & Alben zuletzt: jede einmal")
	check(str(ctx[0].kind) == "album" and str(ctx[1].kind) == "playlist" and str(ctx[1].name) == "Spieleklassiker", "Art und Name")
	var many: Array = []
	for i in 620:
		var u := "spotify:track:" + ("%022d" % i)
		many = Verlauf.add(many, Verlauf.entry({ "u": u, "t": "T%d" % i, "ts": 10000 + i * 1000 }))
	check(many.size() == Verlauf.MAX and str(many[0].t) == "T619", "höchstens 500 Einträge, älteste fallen weg")
	check(Verlauf.last([]).is_empty() and str(Verlauf.last(list).u) == T1, "zuletzt gehörter Eintrag")


func _datei() -> void:
	print("Datei")
	var good := Verlauf.entry({ "u": T1, "t": "Eins", "ts": 5 })
	var bad := [good, "text", 42, { "u": "spotify:track:kurz", "t": "x" }, { "u": T2, "t": "<b>ok</b>", "art": "https://evil.example/a.jpg", "c": "javascript:alert(1)" }]
	var got := Verlauf.load_list({ "v": 1, "items": bad })
	check(got.size() == 2 and str(got[1].art) == "" and str(got[1].c) == "", "Datei: Unsinn fällt weg, Rest geprüft")
	check(Verlauf.load_list("kaputt").is_empty() and Verlauf.load_list({ "items": "x" }).is_empty(), "kaputte Datei: leer")
	var big: Array = []
	for i in 900:
		big.append(good)
	check(Verlauf.load_list({ "items": big }).size() == Verlauf.MAX, "auch aus der Datei höchstens 500")


func _befehle() -> void:
	print("Abspielen aus dem Verlauf über Spotify Connect")
	var c := Intern.commands_for(HTTPClient.METHOD_PUT, "/me/player/play", { "context_uri": PL, "offset": { "uri": T1 } }, "id1")
	check(c.size() == 1 and str(c[0].endpoint) == "play" and str(c[0].context.uri) == PL and str(c[0].options.skip_to.track_uri) == T1,
		"Titel in seiner Playlist: Befehl play mit Kontext")
	var c2 := Intern.commands_for(HTTPClient.METHOD_PUT, "/me/player/play", { "uris": [T1, T2] }, "id2")
	check(c2.size() == 1 and (c2[0].context.pages[0].tracks as Array).size() == 2, "lose Titel: play mit eigener Seite")
	var c3 := Intern.commands_for(HTTPClient.METHOD_PUT, "/me/player/play", null, "id3")
	check(c3.size() == 1 and str(c3[0].endpoint) == "resume", "Weiter hören: resume")


func _ruhe() -> void:
	print("Ruhe im Grundmodus")
	var log_p := Config.path("logs/spotify.log")
	Config.set_value("accounts.spotify_client_id", "")
	Config.set_value("accounts.spotify_refresh", "")
	Config.set_value("accounts.spotify_web", true)
	Config.set_value("accounts.spotify_mode", "")
	Config.set_value("system.music_mode", "spotify")
	check(Music.app_mode() and not Music.own_ready(), "wie die Spotify-App, ohne eigene App")
	Music._pf_off = ""
	Music.problem = ""
	check(not Music.grundmodus(), "ohne Ablehnung kein Grundmodus")
	# Gemerkt von vorhin: gleich im Grundmodus, ohne erst alle Abfragen zu schicken.
	Config.set_value("accounts.spotify_app_blocked", int(Time.get_unix_time_from_system()) - 60)
	Music._grund_restore()
	check(Music.grundmodus() and Music._pf_off != "", "gemerkte Ablehnung: Grundmodus ab Start")
	Music._pf_off = ""
	Config.set_value("accounts.spotify_app_blocked", int(Time.get_unix_time_from_system()) - Music.GRUND_MERKEN_S - 5)
	Music._grund_restore()
	check(not Music.grundmodus(), "alt gemerkt: wieder einmal fragen")
	Music._pf_off = "Client/request not allowed"
	check(Music.grundmodus(), "pathfinder lehnt ab: Grundmodus")
	var before := FileAccess.get_file_as_string(log_p) if FileAccess.file_exists(log_p) else ""
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await Music._api(HTTPClient.METHOD_GET, "/me/tracks?limit=50")
	check(not bool(r.ok) and int(r.code) == 0 and bool(r.get("local", false)), "Web-API: gar nicht gefragt")
	var pf: Dictionary = await Music._pf("libraryV3", {})
	check(int(pf.code) == 403 and not bool(pf.ok), "pathfinder: Ablehnung aus dem Gedächtnis")
	await Music.load_for_you(true)
	check(not Music.for_you_loading() and Music.spotify_mixes.is_empty(), "keine Mixe-Abrufe")
	Music.playlists_state = ""
	await Music.load_playlists()
	await Music.load_liked()
	check(Music.playlists_state == "", "keine Bibliotheks-Abrufe")
	var sr: Dictionary = await Music.search("zanarkand")
	check(str(sr.get("error", "")).contains("Läuft gerade"), "Suche: ruhige Zeile statt Fehler")
	check((await Music.library_contains([T1])).is_empty(), "Lieblingssong prüfen: nicht gefragt")
	check(Time.get_ticks_msec() - t0 < 3000, "alles sofort (nichts wartet aufs Netz)")
	var after := FileAccess.get_file_as_string(log_p) if FileAccess.file_exists(log_p) else ""
	check(after == before, "Protokoll bleibt ruhig")
	check(Music.problem_text("app").find("blockiert") < 0 and Music.problem_text("app").find("gesperrt") < 0, "kein „blockiert“ im Text")
	# Verlauf schreiben, lesen, löschen.
	Music.verlauf_clear()
	Music.verlauf_note(Verlauf.from_cluster(_cl(T1, "Eins", PL, true, "Spieleklassiker"), int(Time.get_unix_time_from_system())))
	check(Music.verlauf_list().size() == 1 and FileAccess.file_exists(Music._verlauf_path()), "Verlauf gespeichert (Profil-Ordner)")
	await Music.load_recent()
	check(Music.recent_list.size() == 1 and str(Music.recent_list[0].uri) == T1, "Zuletzt gehört aus dem eigenen Verlauf")
	Config.set_value("music.verlauf", false)
	Music.verlauf_note(Verlauf.from_cluster(_cl(T2, "Zwei", PL), int(Time.get_unix_time_from_system())))
	check(Music.verlauf_list().size() == 1, "Verlauf aus: nichts dazu")
	Config.set_value("music.verlauf", true)
	Music.verlauf_clear()
	Music._verlauf_loaded = false
	check(Music.verlauf_list().is_empty() and not FileAccess.file_exists(Music._verlauf_path()), "Verlauf gelöscht")
	Music._pf_off = ""
	Config.set_value("accounts.spotify_web", false)
	Config.set_value("accounts.spotify_app_blocked", 0)


func _pc() -> void:
	print("Spotify am PC (Antwort des Helfers)")
	var hist := [Verlauf.entry({ "u": T1, "t": "Eins", "c": PL, "cn": "Zum Zocken", "art": "spotify:image:" + IMG, "ts": 5 })]
	var res := { "ok": true, "items": [
		{ "i": 0, "sec": "lib", "name": "Zum Zocken", "sub": "Playlist • Du", "kind": "playlist" },
		{ "i": 1, "sec": "lib", "name": "Final Fantasy X", "sub": "Album", "kind": "album" },
		{ "i": 2, "sec": "recent", "name": "Mix der Woche", "sub": "", "kind": "" },
		{ "i": 3, "sec": "lib", "name": "Koji Kondo", "sub": "Künstler", "kind": "artist" },
		{ "i": 4, "sec": "evil", "name": "x", "kind": "playlist" }, { "i": "1", "sec": "lib", "name": "y" }, { "i": 999, "sec": "lib", "name": "z" },
		{ "i": 5, "sec": "lib", "name": 42 }, { "i": 6, "sec": "lib", "name": "Zum Zocken", "kind": "playlist" }, "kaputt",
		{ "i": 7, "sec": "lib", "name": "Böse\u202EListe", "kind": "javascript" }] }
	var pc := Music.pc_lib_from(res, hist)
	check((pc.playlists as Array).size() == 1 and (pc.albums as Array).size() == 1 and (pc.recent as Array).size() == 1 and (pc.artists as Array).size() == 1,
		"Playlists, Künstler, Alben, Zuletzt gespielt; Unsinn fällt weg")
	check(str(pc.playlists[0].art) == "https://i.scdn.co/image/" + IMG, "Cover nur aus dem eigenen Verlauf (gleicher Name)")
	check(str(pc.albums[0].art) == "" and int(pc.recent[0].i) == 2, "sonst ohne Cover, Nummer bleibt")
	check(Music.pc_lib_from({ "ok": false, "why": "minimiert" }, hist).playlists.is_empty(), "minimiert: leer")
	check(Music.pc_lib_from({}, []).recent.is_empty(), "keine Antwort: leer")
	_pc_voll(hist)


## Bibliothek ganz (mit Adressen), Zusammenführen, Datei, Cover über oEmbed, Lautstärke gebündelt.
func _pc_voll(hist: Array) -> void:
	print("Spotify am PC (ganze Bibliothek, Datei, Cover)")
	const LIKED := "spotify:user:robin:collection"
	const AR := "spotify:artist:0OdUWJ0sBjDrqHygGUXeCF"
	check(SpotifyPc.uri_ok(PL) and SpotifyPc.uri_ok(AR) and SpotifyPc.uri_ok(LIKED) and SpotifyPc.uri_ok("spotify:show:5CfCWKI5pZ28U0uOzXkDHe"), "Adressen: Playlist, Künstler, Lieblingssongs, Podcast")
	check(not SpotifyPc.uri_ok(T1) and not SpotifyPc.uri_ok("spotify:user:a b:collection") and not SpotifyPc.uri_ok("spotify:user:x:collection\n") and not SpotifyPc.uri_ok(7),
		"Titel, Leerzeichen, Zeilenumbruch, Zahl: nein")
	var res := { "ok": true, "ende": true, "items": [
		{ "i": 0, "sec": "lib", "name": "Lieblingssongs", "sub": "Playlist • 512 Titel", "kind": "playlist", "uri": LIKED },
		{ "i": 1, "sec": "lib", "name": "Zum Zocken", "sub": "Playlist • Du", "kind": "playlist", "uri": PL },
		{ "i": 2, "sec": "lib", "name": "Koji Kondo", "sub": "Künstler", "kind": "", "uri": AR },
		{ "i": 3, "sec": "lib", "name": "Final Fantasy X", "sub": "Album", "kind": "playlist", "uri": AL },
		{ "i": 4, "sec": "lib", "name": "Böse", "kind": "playlist", "uri": "spotify:playlist:x\"<script>" },
		{ "i": 5, "sec": "recent", "name": "Zum Zocken", "kind": "playlist", "uri": PL }] }
	var its := SpotifyPc.items_from(res)
	check(its.size() == 6 and str(its[2].kind) == "artist" and str(its[3].kind) == "album", "Art aus der Adresse statt aus der Zeile")
	check(str(its[4].uri) == "" and str(its[4].kind) == "playlist", "kaputte Adresse fällt weg, der Eintrag bleibt (Abspielen im Fenster)")
	var rows := SpotifyPc.rows_from(its, hist, { AL: { "u": "https://i.scdn.co/image/" + IMG, "t": 1 } })
	check((rows.artists as Array).size() == 1 and (rows.albums as Array).size() == 1 and (rows.playlists as Array).size() == 3
		and (rows.recent as Array).size() == 1, "Reihen je Art")
	check(str(rows.playlists[0].uri) == LIKED and str(rows.playlists[0].id) == LIKED, "Lieblingssongs vorn")
	check(str(rows.albums[0].art) == "https://i.scdn.co/image/" + IMG and str(rows.playlists[1].art) == "https://i.scdn.co/image/" + IMG, "Cover aus oEmbed bzw. aus dem eigenen Verlauf (gleiche Adresse)")
	check(str(rows.playlists[2].id) == "pc:Böse", "ohne Adresse: Kennung aus dem Namen")
	# Zusammenführen
	var alt := SpotifyPc.items_from({ "ok": true, "items": [{ "i": 0, "sec": "lib", "name": "Alt", "kind": "playlist", "uri": "spotify:playlist:" + "A".repeat(22) },
		{ "i": 1, "sec": "recent", "name": "Alt zuletzt", "kind": "album", "uri": AL }, { "i": 2, "sec": "lib", "name": "Zum Zocken", "kind": "playlist", "uri": PL }] })
	var teil := SpotifyPc.merge(its.slice(0, 2), alt, false)
	check(teil.size() == 4 and str(teil[2].name) == "Alt" and int(teil[2].i) == -1 and str(teil[3].name) == "Alt zuletzt", "nicht bis zum Ende gelesen: Gemerktes bleibt (ohne Nummer im Fenster)")
	var ganz := SpotifyPc.merge(its, alt, true)
	check(ganz.size() == its.size(), "bis zum Ende gelesen: nur das Neue (Gelöschtes verschwindet, Zuletzt neu)")
	# Datei
	var arts := { PL: { "u": "https://image-cdn-ak.spotifycdn.com/image/ab67706c0000da84abc", "t": 5 }, AL: { "u": "", "t": 6 } }
	var f := SpotifyPc.to_file(its, arts, 1700000000)
	var back := SpotifyPc.load_file(JSON.parse_string(JSON.stringify(f)))
	check((back.items as Array).size() == its.size() and int(back.at) == 1700000000 and int(back.items[0].i) == -1 and str(back.items[2].uri) == AR, "Datei: hin und zurück")
	check(SpotifyPc.cover(back.arts, PL) != "" and (back.arts as Dictionary).has(AL), "Datei: Cover und Fehlversuche gemerkt")
	var evil := SpotifyPc.load_file({ "at": "x",
		"items": [{ "sec": "lib", "name": "a\u202Eb", "kind": "playlist", "uri": "spotify:playlist:" + "B".repeat(22) }, { "sec": "lib", "name": "" }, 5],
		"arts": { "spotify:track:" + "C".repeat(22): { "u": "", "t": 1 }, PL: { "u": "https://evil.example/x.jpg", "t": 1 }, AL: { "u": "https://i.scdn.co/image/a", "t": "1" } } })
	check((evil.items as Array).size() == 1 and str(evil.items[0].name) == "ab" and int(evil.at) == 0 and (evil.arts as Dictionary).is_empty(), "Datei: alles geprüft")
	check(SpotifyPc.load_file("kaputt").items.is_empty() and SpotifyPc.load_file(null).arts.is_empty(), "kaputte Datei: leer")
	# Cover über oEmbed
	check(SpotifyPc.oembed_url(PL) == "https://open.spotify.com/oembed?url=https%3A%2F%2Fopen.spotify.com%2Fplaylist%2F37i9dQZF1DXcBWIGoYBM5M", "oEmbed-Adresse")
	check(SpotifyPc.oembed_url(LIKED) == "" and SpotifyPc.oembed_url(T1) == "" and SpotifyPc.oembed_url("x") == "", "Lieblingssongs, Titel, Unsinn: keine Abfrage")
	check(SpotifyPc.oembed_art({ "thumbnail_url": "https://i.scdn.co/image/" + IMG }) == "https://i.scdn.co/image/" + IMG
		and SpotifyPc.oembed_art({ "thumbnail_url": "https://pickasso.spotifycdn.com/image/ab67c0de0000deef/dt/v1/img/daily/2/ab6761610000e5eb/en" }) != "", "oEmbed: Cover von Spotifys Bilder-Servern")
	check(SpotifyPc.oembed_art({ "thumbnail_url": "https://evil.example/a.jpg" }) == "" and SpotifyPc.oembed_art([1]) == ""
		and SpotifyPc.oembed_art({ "thumbnail_url": 3 }) == "", "fremder Server, Unsinn: kein Cover")
	check(not SpotifyPc.cover_due(arts, PL, 10) and not SpotifyPc.cover_due(arts, AL, 6 + 3600) and SpotifyPc.cover_due(arts, AL, 6 + SpotifyPc.COVER_RETRY_S + 1)
		and SpotifyPc.cover_due({}, AR, 1) and not SpotifyPc.cover_due({}, LIKED, 1), "Cover nur einmal fragen, Fehlversuch nach einem Tag wieder")
	check(SpotifyPc.vol_wait_ms(1000, 900) == 200 and SpotifyPc.vol_wait_ms(5000, 900) == 0 and SpotifyPc.vol_wait_ms(1000, 1000) == 300, "Lautstärke: höchstens alle 300 ms")
	check(SpotifyPc.empty({}) and not SpotifyPc.empty(rows), "leer erkannt")

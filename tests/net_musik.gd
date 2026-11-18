extends Node
## Netz-Probe für Musik: spricht mit einer nachgebauten Spotify-Schnittstelle (tests/fake_spotify.py),
## die sich wie eine eigene App im „Development Mode“ nach den Änderungen 2026 verhält – und wie die
## Anmeldung „Mit Spotify anmelden“: die Seite (Spotify-Sitzung im Browser-Kern) ist hier ein Callable
## (Web.quelle), das den Schlüssel des Webplayers liefert; alles danach geht übers Netz zum Nachbau.
## Aufruf (eigener Datenordner, die Probe trägt Test-Zugangsdaten ein):
##   python3 tests/fake_spotify.py 18765 &
##   UZAI_DATA=<ordner> UZAI_SPOTIFY_API=http://127.0.0.1:18765/v1 UZAI_SPOTIFY_ACCOUNTS=http://127.0.0.1:18765 \
##     godot --headless --path . res://tests/net_musik.tscn

const Catalog := preload("res://src/core/artist_catalog.gd")
const TrackList := preload("res://src/ui/layers/track_list.gd")

var fails := 0
var base := ""
## Die nachgebaute Seite: "ok" (Schlüssel), "abgemeldet", "zeit" (kein Schlüssel); seite_n zählt die Abrufe.
var seite := "ok"
var seite_n := 0
const APPTOK := "apptokWebplayer0123456789"
const CT := "clienttokWebplayer0123456789"
const DESKTOP_ID := "65b708073fc0480ea92a077233ca87bd"   ## nur für die PKCE-Probe des Nachbaus


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_SPOTIFY_ACCOUNTS")
	if base == "":
		print("UZAI_SPOTIFY_ACCOUNTS fehlt")
		get_tree().quit(1)
		return
	Config.set_value("accounts.spotify_client_id", "test")
	Config.set_value("accounts.spotify_refresh", "r1")
	Config.set_value("system.music_mode", "spotify")
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _seite() -> Dictionary:
	seite_n += 1
	await get_tree().create_timer(0.05).timeout
	if seite == "ok":
		return { "ok": true, "token": APPTOK, "client": CT, "version": "1.2.63.394" }
	return { "ok": false, "why": seite }


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


static func _has(log: Array, m: String, p: String, q := "") -> bool:
	for e in log:
		if str(e.m) == m and str(e.p) == p and (q == "" or str(e.q).contains(q)):
			return true
	return false


## Eine pathfinder-Abfrage (operationName) nach der Marke, optional mit Text im Inhalt.
static func _pf_op(log: Array, from: int, op: String, contains := "") -> bool:
	for i in range(from, log.size()):
		var e: Dictionary = log[i]
		if str(e.p) == "/pathfinder/v2/query" and str(e.b).contains("\"operationName\":\"%s\"" % op) and (contains == "" or str(e.b).contains(contains)):
			return true
	return false


## Wie _has, aber nur Anfragen nach der Marke (Länge des Protokolls vorher) und mit diesem Schlüssel.
static func _has_tok(log: Array, from: int, m: String, p: String, tok: String, q := "") -> bool:
	for i in range(from, log.size()):
		var e: Dictionary = log[i]
		if str(e.m) == m and str(e.p) == p and str(e.get("t", "")) == tok and (q == "" or str(e.q).contains(q)):
			return true
	return false


func _run() -> void:
	print("Playlists (neue Form)")
	await Music.load_playlists()
	check(Music.playlists.size() == 2, "zwei Playlists, leerer Eintrag übersprungen (%d)" % Music.playlists.size())
	if Music.playlists.size() == 2:
		check(int(Music.playlists[0].count) == 3 and bool(Music.playlists[0].mine) and not bool(Music.playlists[1].mine),
				"Anzahl aus items.total, eigene und fremde erkannt")
		check(str(Music.playlists[0].desc) == "Mit Fett & Spaß", "Beschreibung als Text")
	var own := await Music.playlist_tracks("eigen")
	var log := await _log()
	check(own.size() == 2 and str(own[0].title) == "Titel 1", "Titel über /items mit „item“ (%d)" % own.size())
	check(_has(log, "GET", "/v1/playlists/eigen/items") and not _has(log, "GET", "/v1/playlists/eigen/tracks"),
			"erst der neue Weg /items, der alte wird nicht gebraucht")
	var foreign := await Music.playlist_tracks("fremd")
	check(foreign.is_empty() and Music.list_error.contains("gehören"), "fremde Playlist: ehrlicher Hinweis statt Fehler")

	print("Lieblingssongs über /me/library")
	Music.liked_list = []
	await Music.toggle_like("t9")
	log = await _log()
	check(_has(log, "PUT", "/v1/me/library", "uris=spotify%3Atrack%3At9"), "Speichern mit URI in der Adresse")
	var cont := await Music.library_contains(["spotify:track:t9", "spotify:track:t1"])
	check(cont == [true, false], "Prüfen über /me/library/contains: " + str(cont))
	Music.liked_list = [{ "id": "t9", "uri": "spotify:track:t9", "title": "x" }]
	await Music.toggle_like("t9")
	log = await _log()
	check(_has(log, "DELETE", "/v1/me/library", "uris=spotify%3Atrack%3At9") and Music.liked_list.is_empty(), "Entfernen über DELETE /me/library")
	# Spotify nimmt das Entfernen nicht an: Der Titel steht wieder an seinem Platz – auch einer, den Uzai nur aus dieser
	# Liste kennt (früher blieb er bis zum nächsten Laden weg, und ein bekannter rutschte nach ganz oben).
	await Net.get_json(base + "/__set?libfail=1")
	Music.liked_list = [{ "id": "t7", "uri": "spotify:track:t7", "title": "a" }, { "id": "t9", "uri": "spotify:track:t9", "title": "nur hier" },
		{ "id": "t8", "uri": "spotify:track:t8", "title": "c" }]
	await Music.toggle_like("t9")
	check(Music.liked_list.map(func(t: Dictionary) -> String: return str(t.id)) == ["t7", "t9", "t8"] and Music.error != "",
			"Entfernen abgelehnt: die Liste steht wie vorher – " + str(Music.liked_list.map(func(t: Dictionary) -> String: return str(t.id))))
	Music.liked_list = [{ "id": "t7", "uri": "spotify:track:t7", "title": "a" }]
	Music.recent_list = [{ "id": "t6", "uri": "spotify:track:t6", "title": "neu" }]
	await Music.toggle_like("t6")
	check(Music.liked_list.map(func(t: Dictionary) -> String: return str(t.id)) == ["t7"], "Speichern abgelehnt: der Titel steht nicht unter den Lieblingssongs")
	Music.error = ""
	await Net.get_json(base + "/__set")

	print("Für dich")
	await Music.load_for_you(true)
	log = await _log()
	check(Music.top_tracks.size() == 3 and Music.top_long.size() == 7, "Top-Titel: letzte Wochen und über Jahre")
	check(Music.saved_albums.size() == 1 and str(Music.saved_albums[0].name) == "Gespeichert", "gespeicherte Alben")
	var rel: Array = Music.new_releases.map(func(a): return str(a.id))
	rel.sort()
	check(rel == ["a1-neu", "a2-neu"], "Neu von deinen Künstlern: nur Neues, aus Top und Gefolgten: " + str(rel))
	var mix: Array = Music.spotify_mixes.map(func(m): return str(m.id))
	check(mix == ["dw", "rr"], "Mixe von Spotify über die Suche, Kopien von Fans raus: " + str(mix))
	var too_big := false
	for e in log:
		if str(e.p) == "/v1/search" or str(e.p).begins_with("/v1/artists/"):
			for part in str(e.q).split("&"):
				if part.begins_with("limit=") and int(part.substr(6)) > 10:
					too_big = true
	check(not too_big, "Suche und Künstler-Alben mit höchstens 10 Treffern")
	check(not Music.need_login and not Music.for_you_loading(), "alle Teile geladen, keine neue Anmeldung nötig")
	var own_ids: Array = Music.own_mixes().map(func(m): return str(m.id))
	check(own_ids == ["mix:top", "mix:neu", "mix:lange", "mix:zuletzt"], "eigene Mixe: " + str(own_ids))
	var nt := await Music.mix_tracks("mix:neu")
	check(nt.size() == 2 and str(nt[0].album).begins_with("Neu") and str(nt[0].art) != "", "Neuheiten-Mix: erste Titel je Album, mit Albumbild")

	print("Suche")
	var res := await Music.search("abc")
	check((res.tracks as Array).size() == 1 and (res.albums as Array).size() == 1 and (res.playlists as Array).is_empty(),
			"Titel und Alben, leere Playlist-Treffer übersprungen")
	check((res.artists as Array).size() == 1 and str(res.artists[0].name) == "Künstler" and str(res.get("error", "")) == "", "Künstler in den Treffern")
	log = await _log()
	check(_has(log, "GET", "/v1/search", "type=track%2Cartist%2Calbum%2Cplaylist") or _has(log, "GET", "/v1/search", "type=track,artist,album,playlist"),
			"eine Suche für alle Arten")

	print("Künstlerseite")
	var page := await Music.artist_page({ "id": "a1", "name": "Künstler" })
	check(bool(page.ok) and str(page.artist.name) == "Künstler" and int(page.artist.followers) == 51234 and str(page.artist.art) != "",
			"Künstler mit Bild und Followern")
	check(str(page.top_from) == "top" and (page.top as Array).map(func(t): return str(t.id)) == ["t40", "t41"], "beliebte Titel über /top-tracks")
	check((page.albums as Array).size() == 3 and (page.singles as Array).is_empty(),
			"Alben aus zwei Seiten, doppelte nur einmal (%d)" % (page.albums as Array).size())
	log = await _log()
	check(_has(log, "GET", "/v1/artists/a1/albums", "offset=10") and _has(log, "GET", "/v1/artists/a1"), "Künstler und Alben über die offiziellen Wege")
	var page2 := await Music.artist_page({ "id": "weg", "name": "Weg" })
	check(bool(page2.ok) and str(page2.top_from) == "suche" and (page2.top as Array).map(func(t): return str(t.id)) == ["t50"],
			"keine Top-Titel (403): Suchtreffer des Künstlers statt dessen")
	check(int(page2.artist.followers) == -1 and str(page2.artist.art) == "", "ohne Bild und Follower: bleibt leer statt Fehler")
	log = await _log()
	check(_has(log, "GET", "/v1/search", "artist%3A%22Weg%22"), "Ersatz-Suche mit artist:\"Weg\"")
	var page3 := await Music.artist_page({ "id": "", "name": "Künstler" })
	check(bool(page3.ok) and str(page3.artist.id) == "a1", "ohne ID (Windows-Titel): Künstler über die Suche gefunden")
	await _alle_titel()

	print("Abspielen und Geräte")
	var ok: bool = await Music.play_context("spotify:playlist:dw")
	check(not ok and Music.error.contains("keinem Gerät"), "kein Gerät (und kein Windows): klarer Hinweis – " + Music.error)
	await Net.get_json(base + "/__set?devices=1")
	ok = await Music.play_context("spotify:playlist:dw")
	log = await _log()
	check(ok and _has(log, "PUT", "/v1/me/player"), "Gerät gewählt, Wiedergabe übertragen, Mix läuft")
	ok = await Music.play_context("spotify:playlist:gesperrt")
	check(not ok and Music.error.contains("nicht abspielen"), "gesperrte Liste: kein Geräte-Hinweis, sondern der wahre Grund")
	await Music.poll()
	check(str(Music.now.get("title", "")) == "Titel 1" and str(Music.now.get("device", "")) == "WOHNZIMMER", "laufender Titel und Gerät gelesen")

	print("Lautstärke der Musik (Läuft gerade, Guide)")
	check(int(Music.now.get("volume", -1)) == 50 and str(Music.now.get("device_type", "")) == "Computer", "Lautstärke und Art des Geräts gelesen")
	var vr: Dictionary = await Music.change_volume(10)
	log = await _log()
	check(bool(vr.ok) and str(vr.via) == "spotify" and int(vr.level) == 60 and _has(log, "PUT", "/v1/me/player/volume", "volume_percent=60"),
			"Spotify-Player über die Web-API: 60 %")
	await Net.get_json(base + "/__set?novolume=1")
	vr = await Music.change_volume(10)
	check(not bool(vr.ok) and str(vr.why) == "spotify_fest" and int(Music.now.get("volume", -1)) == 60,
			"Spotify lehnt ab (kein Premium), ohne Windows-Mixer: alter Wert bleibt, ehrlicher Grund")
	await Net.get_json(base + "/__set")

	print("Gerät wechseln")
	await Net.get_json(base + "/__set?devices=2")
	var err: String = await Music.transfer("handy")
	check(err == "" and str(Music.now.get("device", "")) == "Handy", "aufs Handy gewechselt und bestätigt (%s)" % err)
	err = await Music.transfer("schlaf")
	log = await _log()
	check(err == "" and str(Music.now.get("device", "")) == "Küche", "schlafender Lautsprecher: geweckt und gewechselt (%s)" % err)
	err = await Music.transfer("box")
	check(err.contains("nicht von anderen Apps"), "gesperrtes Gerät: ehrlicher Hinweis, kein „gewechselt“ (%s)" % err)
	var devs := await Music.devices()
	check(devs.any(func(d): return str(d.id) == "box" and bool(d.restricted)), "gesperrtes Gerät in der Liste erkennbar")
	err = await Music.transfer("stur")
	check(err.contains("nicht übernommen"), "Gerät übernimmt nicht: wird gemeldet statt still falsch (%s)" % err)
	check(Music.transfer_error(403, "PREMIUM_REQUIRED", "X").contains("Premium") and Music.transfer_error(404, "", "Box").contains("Box"), "Gründe verständlich")
	await Net.get_json(base + "/__set?devices=1")

	print("Ältere Schnittstelle ohne /me/library")
	await Net.get_json(base + "/__set?oldlib=1")
	var saved: bool = await Music.library_set(["spotify:track:t4"], true)
	log = await _log()
	check(saved and _has(log, "PUT", "/v1/me/tracks", "ids=t4"), "Rückfall auf PUT /me/tracks?ids=")
	var cont2 := await Music.library_contains(["spotify:track:t4"])
	check(cont2 == [true], "Rückfall beim Prüfen: /me/tracks/contains")

	print("Alte Anmeldung ohne neue Freigaben")
	await Net.get_json(base + "/__set?oldscope=1")
	Music._token = ""
	Music.need_login = false
	Music.top_tracks = []
	Music.new_releases = []
	await Music.load_for_you(true)
	check(Music.need_login, "fehlende Freigaben erkannt: „Neu anmelden“ wird angeboten")
	check(Music.missing_scopes() == ["user-top-read", "user-follow-read"], "welche fehlen: " + str(Music.missing_scopes()))
	check(Music.top_tracks.is_empty() and not Music.saved_albums.is_empty() and not Music.spotify_mixes.is_empty(), "der Rest von „Für dich“ kommt trotzdem")

	print("Neue Anmeldung, aber Spotify gibt eine Freigabe nicht frei")
	await Net.get_json(base + "/__set?nofollow=1")
	Music._token = ""
	Music.need_login = false
	await Music.load_for_you(true)
	check(not Music.need_login, "kein „Neu anmelden“, wenn Neu-Anmelden nichts ändern würde")
	check(not Music.top_tracks.is_empty() and not Music.new_releases.is_empty(), "Top-Titel und Neues kommen trotzdem (aus den Top-Künstlern)")
	await Net.get_json(base + "/__set?oldscope=1")
	Config.set_value("accounts.spotify_scopes_asked", Music.SCOPES)
	Music._token = ""
	Music.need_login = false
	await Music.load_for_you(true)
	check(not Music.need_login and str(Music.for_you_parts.get("top", "")) == "fehlt", "mit allem angefragt, trotzdem verweigert: kein Neu-Anmelden im Kreis")
	Config.set_value("accounts.spotify_scopes_asked", "")

	print("Konto nicht in der eigenen App eingetragen (User Management)")
	await Net.get_json(base + "/__set?unregistered=1")
	Music._token = ""
	Music.playlists = []
	await Music.load_playlists()
	check(Music.problem == "nutzer", "Grund erkannt: " + Music.problem)
	check(Music.playlists_state == "fehler" and Music.list_error.contains("User Management"), "Playlists sagen, was zu tun ist – keine Platzhalter für immer")
	Music.need_login = false
	await Music.load_for_you(true)
	check(not Music.need_login, "kein irreführendes „Neu anmelden“")
	var rows: Array = await Music.diagnose()
	var konto: Dictionary = rows[1] if rows.size() > 1 else {}
	check(rows.size() == 9 and bool(rows[0].ok) and not bool(konto.get("ok", true)) and str(konto.get("text", "")).contains("User Management"),
			"Verbindung prüfen: Anmeldung ok, Konto abgelehnt mit Grund")
	await Net.get_json(base + "/__set")
	await Music.load_playlists()
	check(Music.problem == "" and Music.playlists_state == "ok", "eingetragen: alles wieder gut, ohne Neustart")

	print("Abgelehnt ohne Grund (leere 403)")
	await Net.get_json(base + "/__set?bare403=1")
	Music._token = ""
	var rows2: Array = await Music.diagnose()
	check(Music.problem == "gesperrt", "leere 403 auf /me: Konto abgelehnt erkannt: " + Music.problem)
	var konto2: Dictionary = rows2[1] if rows2.size() > 1 else {}
	check(str(konto2.get("text", "")).contains("Web API") and str(konto2.get("text", "")).contains("User Management"), "sagt, was im Dashboard zu prüfen ist")
	await Net.get_json(base + "/__set")
	await Music.load_playlists()
	check(Music.problem == "", "danach wieder gut")

	print("Anmeldung abgelaufen (nach sechs Monaten)")
	await Net.get_json(base + "/__set?expired=1")
	Music._token = ""
	await Music.load_playlists()
	check(Music.problem == "abgelaufen" and Music.list_error.contains("abgelaufen"), "abgelaufen erkannt: " + Music.list_error)
	await Net.get_json(base + "/__set")
	Music._token = ""
	await Music.load_playlists()
	check(Music.problem == "", "nach neuer Anmeldung wieder gut")
	await _wie_die_app()


## Mit Spotify angemeldet: Anmeldung über den Schlüssel der Seite, PKCE (eigene App), echte Mixe mit Titeln,
## Weg über context-resolve, Erneuern über die Seite, Bremse (429) und Rückfall auf die eigene Client-ID.
func _wie_die_app() -> void:
	print("Mit Spotify anmelden: Schlüssel der Seite")
	Music.set("_spclient", base + "/spclient")
	Music.set("_partner", base + "/pathfinder/v2/query")
	Music.set("_dealer_url", base.replace("http://", "ws://") + "/dealer")
	Music.web_sitzung().set("quelle", _seite)
	check(Music.login_mode() == "eigen" and not Music.mix_titles(), "vorher: eigene Client-ID, Mixe ohne Titel")
	check(not await Music.web_angemeldet({ "t": "spotify", "token": "kurz", "client": "", "version": "" }) and not Music.app_ready(), "kaputter Schlüssel: keine Anmeldung")
	var ok: bool = await Music.web_angemeldet({ "t": "spotify", "token": APPTOK, "client": CT, "version": "1.2.63.394" })
	var log := await _log()
	check(ok and Music.app_ready() and str(Config.get_value("accounts.spotify_mode", "")) == "app" and _pf_op(log, 0, "profileAttributes"),
			"Schlüssel gehört zu einem Konto (profileAttributes): angemeldet")
	check(Music.login_mode() == "app" and Music.app_mode() and Music.has_spotify() and Music.mix_titles(), "jetzt mit Spotify angemeldet")
	check(str(Config.get_value("accounts.spotify_refresh", "")) == "r1", "eigene Client-ID bleibt als Rückfall")
	var disk0 := FileAccess.get_file_as_string(Config.path("settings.json"))
	Config.save_settings()
	disk0 = FileAccess.get_file_as_string(Config.path("settings.json"))
	check(not disk0.contains(APPTOK) and not disk0.contains(CT), "Schlüssel und Client-Token nie in settings.json")

	print("Eigene App: Freigabe im Browser (PKCE)")
	var url := Music.authorize_url(DESKTOP_ID, "http://127.0.0.1:8898/login", Music.SCOPES)
	check(url.contains("client_id=" + DESKTOP_ID) and url.contains("code_challenge_method=S256") and url.contains("127.0.0.1%3A8898%2Flogin"),
			"Freigabe-Adresse mit S256 und Rücksprung")
	var st_val := str(Music.get("_oauth_state"))
	check(st_val.length() == 32 and url.contains("state=" + st_val), "mit Zufallswert (state)")
	check(Music.callback_code("GET /login?code=abc&state=%s HTTP/1.1" % st_val, st_val) == "abc", "Rücksprung mit passendem Zufallswert: Code angenommen")
	check(Music.callback_code("GET /login?code=abc&state=fremd HTTP/1.1", st_val) == "" and Music.callback_code("GET /login?code=abc HTTP/1.1", st_val) == ""
			and Music.callback_code("GET /login?code=abc&state= HTTP/1.1", "") == "", "fremder oder fehlender Zufallswert: nichts angenommen")
	var v1 := Music._random(64)
	check(v1.length() == 64 and v1 != Music._random(64) and Music._hex(40).length() == 40 and Music._hex(40).is_valid_hex_number(),
			"Prüfwerte aus sicherem Zufall, richtige Länge")
	var page := await Net.get_json(url)
	var ex: Dictionary = await Music._exchange_code(DESKTOP_ID, str(page.data.get("code", "")) if page.data is Dictionary else "",
			"http://127.0.0.1:8898/login")
	check(bool(ex.ok), "Code gegen Anmeldung getauscht, Prüfwert passt")
	Music.set("_verifier", "falsch")
	var bad: Dictionary = await Music._exchange_code(DESKTOP_ID, "c1", "http://127.0.0.1:8898/login")
	check(not bool(bad.ok) and int(bad.code) == 400, "falscher Prüfwert: abgelehnt")

	print("Wie die Spotify-App: Für dich über die Startseite (pathfinder)")
	var mark := (await _log()).size()
	await Music.load_for_you(true)
	log = await _log()
	var ids: Array = Music.spotify_mixes.map(func(m): return str(m.id))
	check(ids == ["37i9dQZEVXcDW", "37i9dQZEVXbRR", "37i9dQZF1EpRep", "37i9dQZF1E3d1", "37i9dQZF1E3d2", "37i9dQZF1EcCap", "37i9dQZF1EIchill"],
			"echte Mixe aus „Für dich“ und „Top-Mixe“, Nicht-Playlist raus: " + str(ids))
	check(str(Music.mix_ways) == "Startseite" and _has_tok(log, mark, "POST", "/pathfinder/v2/query", "apptokWebplayer0123456789"),
			"Weg: Startseite (api-partner), mit der App-Anmeldung")
	check(not _has(log, "POST", "/clienttoken/v1/clienttoken"), "Client-Token der Seite, kein eigener")
	var used_webapi := false
	for i in range(mark, log.size()):
		var pp := str(log[i].p)
		if pp == "/v1/search" or pp.contains("/browse/categories/") or pp == "/v1/views/made-for-x":
			used_webapi = true
	check(not used_webapi, "keine Suche, keine Kategorie, kein made-for-x nötig (api.spotify.com gespart)")
	check(str(Music.spotify_mixes[6].mix) == "mehr" and str(Music.spotify_mixes[0].sub) == "Jeden Montag neu", "„Chill Mix“ zählt (aus Für dich gemacht)")
	var own_ids: Array = Music.own_mixes().map(func(m): return str(m.id))
	check(not own_ids.has("mix:neu") and not Music.new_releases.is_empty(), "echtes Release Radar: kein eigenes doppelt, Reihe „Neu von deinen Künstlern“ bleibt")
	var dw: Dictionary = Music.spotify_mixes[0]
	check(TrackList.loader_for(dw).is_valid() and not bool(TrackList.info_for(dw).get("restricted", false)),
			"Mix öffnet wie eine Playlist (Titelliste, nicht gesperrt)")
	mark = (await _log()).size()
	var tl: Array = await TrackList.loader_for(dw).call()
	log = await _log()
	check(tl.size() == 3 and str(tl[0].title) == "Titel 70" and _pf_op(log, mark, "fetchPlaylist")
			and not _has_tok(log, mark, "GET", "/v1/playlists/37i9dQZEVXcDW/items", "apptokWebplayer0123456789"),
			"Titel des Mixes über pathfinder (fetchPlaylist), ohne api.spotify.com (%d)" % tl.size())
	var fr := await Music.playlist_tracks("fremd")
	check(fr.size() == 3 and Music.list_error == "", "fremde Playlist: auch mit Titeln")

	print("Wie die Spotify-App: Mixe trotz 429 der Web-API")
	await Net.get_json(base + "/__set?webquota=1")
	Music.me = {}
	mark = (await _log()).size()
	await Music.load_for_you(true)
	log = await _log()
	ids = Music.spotify_mixes.map(func(m): return str(m.id))
	check(ids.has("37i9dQZEVXcDW") and str(Music.mix_ways) == "Startseite", "api.spotify.com bremst (429), die Startseite liefert die Mixe trotzdem: " + str(ids))
	check(str(Music.me.get("name", "")) != "", "Kontoname kommt trotzdem (eigene Client-ID als Ausweg oder pathfinder)")
	check(Music.login_mode() == "app" and Music.problem == "", "Anmeldung bleibt wie die Spotify-App, kein Fehlerzustand")
	# Ohne eigene Client-ID als Ausweg kommt der Name wie bei der echten App über pathfinder.
	Config.set_value("accounts.spotify_refresh", "")
	Music.me = {}
	Music._token = ""
	Music.set("_app_slow_until", 0)
	await Music.ensure_me()
	check(str(Music.me.get("name", "")) == "Ich (App)",
			"Kontoname über pathfinder (profileAttributes), wenn /me bremst und keine eigene App: " + str(Music.me.get("name", "")))
	# Wie im echten Protokoll: nur die App-Anmeldung, Web-API pausiert. Die Titel eines Mixes kommen
	# trotzdem über spclient (context-resolve) – die Bremse von api.spotify.com gilt dort nicht.
	mark = (await _log()).size()
	var only := await Music.playlist_tracks("nurintern")
	log = await _log()
	check(only.map(func(t): return str(t.title)).has("Nur Name")
			and _has_tok(log, mark, "GET", "/spclient/context-resolve/v1/spotify:playlist:nurintern", "apptokWebplayer0123456789"),
			"Titel über context-resolve trotz 429 der Web-API: " + str(only.map(func(t): return str(t.title))))
	check(int(Music.get("_rate_until").app) > int(Time.get_unix_time_from_system()), "Web-API für die App-Anmeldung pausiert (Retry-After)")
	mark = (await _log()).size()
	only = await Music.playlist_tracks("nurintern")
	log = await _log()
	var web_during := 0
	for i in range(mark, log.size()):
		if str(log[i].p).begins_with("/v1/"):
			web_during += 1
	check(not only.is_empty() and web_during == 0, "nochmal: in der Pause keine einzige Anfrage an api.spotify.com (%d)" % web_during)
	Config.set_value("accounts.spotify_refresh", "r1")
	Music._token = ""
	Music.set("_rate_until", { "app": 0, "eigen": 0 })
	Music.set("_app_slow_until", 0)
	await Net.get_json(base + "/__set")

	print("Wie die Spotify-App: Weg über context-resolve")
	mark = (await _log()).size()
	var inner := await Music.playlist_tracks("nurintern")
	log = await _log()
	var it: Array = inner.map(func(t): return str(t.title))
	check(it == ["Titel 60", "Titel 61", "Nur Name"], "zwei Seiten, Angaben über /tracks?ids=, sonst der Name aus der Liste: " + str(it))
	check(_has_tok(log, mark, "GET", "/spclient/context-resolve/v1/spotify:playlist:nurintern", "apptokWebplayer0123456789")
			and _has_tok(log, mark, "GET", "/v1/tracks", "apptokWebplayer0123456789", "ids=t60"), "context-resolve mit der App-Anmeldung")
	await Net.get_json(base + "/__set?spcno=1")
	var none := await Music.playlist_tracks("nurintern")
	check(none.is_empty() and Music.list_error.contains("Weg der Spotify-App") and Music.problem == "" and Music.login_mode() == "app",
			"lehnt auch spclient ab: ehrlicher Hinweis, Anmeldung bleibt gültig")
	await Net.get_json(base + "/__set")

	print("Wie die Spotify-App: Suche bis 20")
	Music.set("_app_slow_until", 0)
	Music.set("_app_429", 0)
	mark = (await _log()).size()
	await Music.search("abc")
	log = await _log()
	check(_pf_op(log, mark, "searchDesktop", "\"limit\":20") and not _has(log.slice(mark), "GET", "/v1/search"),
			"Suche über pathfinder (searchDesktop) mit 20 Treffern je Art")

	print("Wie die Spotify-App: Rückfall auf Kategorie, wenn die Startseite nicht geht")
	await Net.get_json(base + "/__set?pfno=1")
	mark = (await _log()).size()
	await Music.load_for_you(true)
	log = await _log()
	ids = Music.spotify_mixes.map(func(m): return str(m.id))
	check(str(Music.mix_ways) == "Kategorie" and ids.has("37i9dQZEVXcDW")
			and _has_tok(log, mark, "GET", "/v1/browse/categories/0JQ5DAqbMKFHOzuVTgTizF/playlists", "apptokWebplayer0123456789"),
			"Startseite gebremst: zurück auf die Kategorie „Für dich gemacht“ – " + str(Music.mix_ways))

	print("Wie die Spotify-App: ohne Startseite und ohne Kategorie: made-for-x")
	await Net.get_json(base + "/__set?pfno=1&nocat=1")
	await Music.load_for_you(true)
	ids = Music.spotify_mixes.map(func(m): return str(m.id))
	check(str(Music.mix_ways).begins_with("made-for-x") and ids.has("37i9dQZF1EpRep") and ids.has("37i9dQZF1EcCap") and ids.has("37i9dQZF1E3d3"),
			"made-for-x (verschachtelt) – " + str(Music.mix_ways) + " " + str(ids))
	check(ids.has("37i9dQZEVXbRR"), "dazu gefolgte Mixe aus /me/playlists")
	await Net.get_json(base + "/__set")
	var spf := FileAccess.get_file_as_string(Config.path("logs/spotify.log"))
	check(spf.contains("Mixe über Startseite") and spf.contains("Mixe über Kategorie") and spf.contains("Mixe über made-for-x") and spf.contains("Mixe: "),
			"Protokoll sagt, welcher Weg die Mixe gefunden hat")

	print("Mit Spotify angemeldet: Erneuern über die Seite")
	Music._token = ""
	var n0 := seite_n
	await Music.load_playlists()
	check(seite_n == n0 + 1 and Music.playlists_state == "ok" and Music._token == APPTOK, "neuer Schlüssel von der Seite, kein /api/token")
	await _einmal_erneuern()
	await _bibliothek_intern()
	await _connect()

	print("Wie die Spotify-App: Spotify bremst (429)")
	# pathfinder ebenfalls gesperrt, damit der Weg über die Web-API geprüft wird.
	await Net.get_json(base + "/__set?app429=1&pfno=1")
	mark = (await _log()).size()
	Music.playlists = []
	await Music.load_playlists()
	await Music.load_playlists()
	await Music.load_playlists()
	log = await _log()
	check(Music.playlists.size() == 2 and _has_tok(log, mark, "GET", "/v1/me/playlists", "tok"), "429: Playlists über die eigene Client-ID")
	check(int(Music.get("_app_slow_until")) > int(Time.get_unix_time_from_system()) and Music.login_mode() == "app",
			"nach drei Mal: allgemeine Abrufe eine Weile über die eigene App, Anmeldung bleibt")
	await Net.get_json(base + "/__set")
	Music.set("_app_slow_until", 0)

	print("Mit Spotify angemeldet: Seite abgemeldet → eigene Client-ID")
	seite = "abgemeldet"
	Music._token = ""
	Music.playlists = []
	await Music.load_playlists()
	seite = "ok"
	check(not Music.app_ready() and Music.login_mode() == "eigen", "beendete Sitzung vergessen, eigene Client-ID übernimmt")
	check(Music.playlists_state == "ok" and Music.playlists.size() == 2 and Music.problem == "" and Music.app_note != "",
			"ohne Fehler weiter, ruhiger Hinweis: " + Music.app_note)
	check(not Music.mix_titles(), "Mixe wieder ohne Titel (offizieller Weg)")
	await Net.get_json(base + "/__set")

	print("Mit Spotify angemeldet, ohne eigene Client-ID: Web-API lehnt ab (401)")
	check(await Music.web_angemeldet({ "t": "spotify", "token": APPTOK, "client": CT, "version": "" }) and Music.login_mode() == "app", "wieder angemeldet")
	Config.set_value("accounts.spotify_refresh", "")
	await Net.get_json(base + "/__set?app401=1")
	mark = (await _log()).size()
	Music.playlists = []
	await Music.load_playlists()
	await Music.load_playlists()
	await Music.load_playlists()
	log = await _log()
	check(Music.problem == "app" and Music.has_spotify() and Music.problem_text("app") != "", "ruhiger Hinweis statt Absturz: " + Music.problem)
	# Früher ~30 (Erneuerung, Client-Token und pathfinder je Abfrage doppelt); jetzt eine Ablehnung je Weg.
	check(log.size() - mark <= 8, "keine Anfrage-Flut (%d Anfragen)" % (log.size() - mark))
	await Net.get_json(base + "/__set")
	Music.set("_app_off_until", 0)
	Music._token = ""
	await Music.load_playlists()
	check(Music.problem == "" and Music.playlists_state == "ok", "Spotify nimmt sie wieder: alles gut")

	print("Mit Spotify angemeldet: kein Schlüssel von der Seite → Grundmodus")
	Config.set_value("accounts.spotify_refresh", "")
	seite = "zeit"
	Music._token = ""
	mark = (await _log()).size()
	await Music.load_playlists()
	await Music.load_playlists()
	log = await _log()
	check(Music.grundmodus() and Music.problem == "app" and Music.app_ready() and log.size() - mark <= 1, "Grundmodus, Anmeldung bleibt, keine Anfrage-Flut (%d)" % (log.size() - mark))
	seite = "ok"
	Music.set("_web_aus_bis", 0)
	Music.set("_app_off_until", 0)
	Music._token = ""
	await Music.load_playlists()
	check(Music.problem == "" and Music.playlists_state == "ok", "Seite gibt wieder einen Schlüssel: alles gut")

	print("Abmelden (Spotify-Sitzung)")
	Config.set_value("accounts.spotify_refresh", "r1")
	Music.disconnect_spotify("app")
	check(not Music.app_ready() and Music.login_mode() == "eigen" and Music.has_spotify() and Music._token != APPTOK, "eigene Client-ID bleibt verbunden, Schlüssel der Seite weg")


## „Alle Titel“ eines Künstlers: alle Seiten der Veröffentlichungen, Titel je Album (oder gebündelt),
## 429 mit Retry-After, Zwischenspeicher, Ausweich-Suche bei 403.
func _alle_titel() -> void:
	print("Alle Titel (Alben je Album, /albums?ids= gesperrt)")
	Catalog.several_ok = true
	var cat = Music.artist_catalog({ "id": "viel", "name": "Viele" })
	var t0 := Time.get_ticks_msec()
	await cat.more()
	var log := await _log()
	check(_has(log, "GET", "/v1/artists/viel/albums", "offset=20") and _has(log, "GET", "/v1/artists/viel/albums", "offset=10"),
			"alle drei Seiten der Veröffentlichungen geholt")
	var too_big := false
	for e in log:
		if str(e.p) == "/v1/artists/viel/albums" and not str(e.q).contains("limit=10"):
			too_big = true
	check(not too_big, "je Seite höchstens 10 (eigene Apps seit 2026)")
	check((cat.releases as Array).size() == 22 and int(cat.total) == 22,
			"22 Veröffentlichungen, doppelte Fassung nur einmal (%d)" % (cat.releases as Array).size())
	check(_has(log, "GET", "/v1/albums", "ids=") and not Catalog.several_ok, "/albums?ids= abgelehnt (403): ab jetzt je Album")
	var titles: Array = (cat.tracks as Array).map(func(t): return str(t.title))
	check((cat.tracks as Array).size() == 68 and not bool(cat.done),
			"erste Runde: sechs Veröffentlichungen, 68 Titel, Rest später (%d)" % (cat.tracks as Array).size())
	check(titles.slice(0, 8) == ["Neu", "Lied 1", "Lied 2", "Lied 3", "Lied 4", "Hit", "Zwei 2", "Zwei 3"],
			"neueste zuerst, Remaster durch das Original ersetzt: " + str(titles.slice(0, 8)))
	var hit: Dictionary = cat.tracks[5]
	check(str(hit.album_uri) == "spotify:album:viel-a2" and str(hit.album_line) == "Zweites Album · 2020",
			"Hit aus dem Album (nicht Single, nicht Remaster), mit Album und Jahr")
	check(titles.count("Hit") == 1 and not titles.any(func(x): return str(x).contains("Remaster")), "jeder Titel einmal")
	var big_calls := 0
	for e in log:
		if str(e.p) == "/v1/albums/viel-big/tracks" and str(e.q).contains("offset=0"):
			big_calls += 1
	check(big_calls == 2 and Time.get_ticks_msec() - t0 >= 1000, "429 mit Retry-After: 1 s gewartet und nochmal (%d Abrufe)" % big_calls)
	check(_has(log, "GET", "/v1/albums/viel-big/tracks", "offset=50") and titles.has("Groß 59"), "großes Album über zwei Seiten (60 Titel)")
	while not bool(cat.done):
		await cat.more()
	check((cat.tracks as Array).size() == 84 and str(cat.tracks[-1].title) == "Füller 0" and int(cat.loaded) == 22,
			"nach allen Runden 84 Titel, ältester zuletzt (%d)" % (cat.tracks as Array).size())
	check(Music.artist_catalog({ "id": "viel", "name": "Viele" }) == cat, "für die Sitzung gemerkt (dieselbe Liste)")

	print("Alle Titel mit Gastauftritten (/albums?ids= erlaubt)")
	await Net.get_json(base + "/__set?several=1")
	Catalog.several_ok = true
	var cg = Music.artist_catalog({ "id": "viel", "name": "Viele" }, true)
	check(cg != cat, "mit Gastauftritten eine eigene Liste")
	while not bool(cg.done):
		await cg.more()
	log = await _log()
	var gt: Array = (cg.tracks as Array).map(func(t): return str(t.title))
	check(_has(log, "GET", "/v1/albums", "ids=viel-s2") and Catalog.several_ok, "Titel gebündelt über /albums?ids=")
	check(_has(log, "GET", "/v1/artists/viel/albums", "appears_on"), "Gastauftritte angefragt (include_groups=…,appears_on)")
	check(gt.has("Gast") and not gt.has("Fremd") and gt.size() == 85, "vom Sampler nur der Titel mit dem Künstler (%d)" % gt.size())
	check(gt.has("Groß 59"), "großes Album: Rest über /albums/{id}/tracks nachgeholt")

	print("Alle Titel ohne Alben (403): Suche")
	var cs = Music.artist_catalog({ "id": "gesperrt", "name": "Gesperrt" })
	await cs.more()
	log = await _log()
	var st: Array = (cs.tracks as Array).map(func(t): return str(t.id))
	check(str(cs.mode) == "suche" and str(cs.note).contains("artist:\"Gesperrt\"") and not str(cs.note).contains("403"),
			"sagt, dass es aus der Suche kommt: " + str(cs.note))
	check(_has(log, "GET", "/v1/search", "offset=20") and bool(cs.done), "Suche über alle Seiten geblättert (je 10)")
	check(st.size() == 21 and not st.has("gs-5") and not st.has("gs-17") and not st.has("gs-12"), "nur Treffer des Künstlers, Doppelung einmal (%d)" % st.size())
	check(str(cs.tracks[0].album_uri) == "spotify:album:ga0" and str(cs.tracks[0].album_line) == "Platte 0 · 2010",
			"Album aus dem Suchtreffer (zum Abspielen im Album)")


## Erneuern nur einmal gleichzeitig: fünf Abrufe ohne Schlüssel fragen die Seite einmal.
func _einmal_erneuern() -> void:
	print("Mit Spotify angemeldet: fünf Abrufe gleichzeitig, die Seite einmal gefragt")
	Music._token = ""
	var n0 := seite_n
	var box := { "ok": 0 }
	var calls: Array = []
	for i in 5:
		calls.append(func() -> void:
			var r: Dictionary = await Music._api(HTTPClient.METHOD_GET, "/me")
			if r.ok:
				box.ok = int(box.ok) + 1)
	await Music._parallel(calls)
	check(seite_n == n0 + 1, "genau ein Abruf bei der Seite für fünf gleichzeitige Abrufe (%d)" % (seite_n - n0))
	check(int(box.ok) == 5 and Music.login_mode() == "app" and Music.app_ready(), "alle fünf bekommen den Schlüssel, Anmeldung bleibt (%d ok)" % int(box.ok))
	var spf := FileAccess.get_file_as_string(Config.path("logs/spotify.log"))
	check(not spf.contains(APPTOK) and not spf.contains(CT), "kein Schlüssel im Protokoll")


## Bibliothek wie die Spotify-App über pathfinder, während api.spotify.com bremst (429).
func _bibliothek_intern() -> void:
	print("Wie die Spotify-App: Bibliothek über pathfinder trotz 429 der Web-API")
	await Net.get_json(base + "/__set?webquota=1")
	var mark := (await _log()).size()
	Music.playlists = []
	await Music.load_playlists()
	await Music.load_liked()
	var res := await Music.search("abc")
	await Music.load_recent()
	var pt := await Music.playlist_tracks("37i9dQZEVXcDW")
	var at := await Music.album_tracks({ "id": "al20", "name": "Album", "art": "x" })
	var page := await Music.artist_page({ "id": "a1", "name": "Künstler" })
	Music.saved_albums = []
	Music.top_tracks = []
	Music.set("_new_at", 0)
	Music.new_releases = []
	await Music._fy_top()
	await Music._fy_albums()
	await Music._fy_new()
	var log := await _log()
	check(Music.playlists.size() == 2 and bool(Music.playlists[0].mine) and not bool(Music.playlists[1].mine)
			and str(Music.playlists[0].desc) == "Mit Fett & Spaß", "Playlists über libraryV3 (Ordner übersprungen, eigene/fremde erkannt): %d" % Music.playlists.size())
	check(Music.liked_list.map(func(t): return str(t.id)) == ["t5"], "Lieblingssongs über fetchLibraryTracks (Adresse neben den Daten)")
	check((res.tracks as Array).size() == 1 and (res.artists as Array).size() == 1 and (res.albums as Array).size() == 1 and str(res.albums[0].name) == "Gefunden",
			"Suche über searchDesktop")
	check(Music.recent_list.map(func(t): return str(t.id)) == ["t6", "t7"] and str(Music.recent_list[0].title) == "Titel 6",
			"Zuletzt gehört über spclient, Angaben über getTrack, doppelte einmal")
	check(pt.size() == 3 and str(pt[0].art) == "http://127.0.0.1:9/mid.jpg", "Titel eines Mixes über fetchPlaylist, mittleres Albumbild")
	check(at.size() == 1 and str(at[0].title) == "Titel 20" and str(at[0].album) == "Album", "Albumtitel über getAlbum")
	check(bool(page.ok) and int(page.artist.followers) == 51234 and (page.top as Array).map(func(t): return str(t.id)) == ["t40", "t41"]
			and (page.albums as Array).size() == 2, "Künstlerseite über queryArtistOverview")
	check(Music.top_tracks.map(func(t): return str(t.id)) == ["t1", "t2", "t3"] and Music.saved_albums.size() == 1
			and str(Music.saved_albums[0].name) == "Gespeichert", "Top-Titel (userTopContent) und gespeicherte Alben (libraryV3)")
	var rel: Array = Music.new_releases.map(func(a): return str(a.id))
	rel.sort()
	check(rel == ["a1-neu", "a2-neu"], "Neu von deinen Künstlern: Top- und gefolgte Künstler, Veröffentlichungen über pathfinder: " + str(rel))
	var web := PackedStringArray()
	for i in range(mark, log.size()):
		var pp := str(log[i].p)
		if pp.begins_with("/v1/") and str(log[i].t) == "apptokWebplayer0123456789" and not pp.begins_with("/v1/me/top/tracks"):
			web.append(pp)
	check(web.is_empty(), "dafür keine Anfrage mit der App-Anmeldung an api.spotify.com: " + str(web))
	Music.liked_list = []
	var saved: bool = await Music.library_set(["spotify:track:t9"], true)
	var c1 := await Music.library_contains(["spotify:track:t9", "spotify:track:t1"])
	var gone: bool = await Music.library_set(["spotify:track:t9"], false)
	var c2 := await Music.library_contains(["spotify:track:t9"])
	check(saved and gone and c1 == [true, false] and c2 == [false], "Speichern/Entfernen und Prüfen über pathfinder: %s %s" % [str(c1), str(c2)])
	var spf := FileAccess.get_file_as_string(Config.path("logs/spotify.log"))
	check(spf.contains("Intern libraryV3 (pathfinder): ok") and spf.contains("Intern searchDesktop (pathfinder): ok")
			and spf.contains("Zuletzt gehört (spclient)"), "Protokoll nennt jeden Weg")
	await Net.get_json(base + "/__set")
	Music.set("_rate_until", { "app": 0, "eigen": 0 })
	Music.set("_app_slow_until", 0)
	Music.set("_app_429", 0)


## Abspielen ohne eigene Spotify-App: Dealer (Websocket) für die Connection-Id, Zustand und
## Befehle über spotify Connect (connect-state) – an die Spotify-App auf diesem PC.
func _connect() -> void:
	print("Wie die Spotify-App: Abspielen über Spotify Connect")
	Music.set("_dealer_retry_at", 0)
	Music.set("_dealer_backoff", 0)
	Music.set("_cluster_dirty", true)
	await Net.get_json(base + "/__set?webquota=1&devices=0")
	var mark := (await _log()).size()
	var ok: bool = await Music.play_context("spotify:playlist:37i9dQZEVXcDW")
	var log := await _log()
	check(not ok and Music.error.contains("einmal öffnen"), "kein Gerät: ruhiger Hinweis – " + Music.error)
	var ws_ok := false
	var put_ok := false
	for i in range(0, log.size()):
		if str(log[i].p).begins_with("/dealer") and str(log[i].q).contains("access_token="):
			ws_ok = true
	for i in range(mark, log.size()):
		if str(log[i].m) == "PUT" and str(log[i].p).begins_with("/spclient/connect-state/v1/devices/hobs_") and str(log[i].c).begins_with("conn"):
			put_ok = true
	check(ws_ok and put_ok, "Dealer verbunden, als verstecktes Gerät mit Connection-Id angemeldet")
	await Net.get_json(base + "/__set?webquota=1&devices=1")
	Music.set("_cluster_dirty", true)
	mark = (await _log()).size()
	ok = await Music.play_context("spotify:playlist:37i9dQZEVXcDW")
	await Music.play_in("spotify:playlist:eigen", "spotify:track:t2")
	await Music.play_list([{ "uri": "spotify:track:t5" }, { "uri": "spotify:track:t6" }], 0)
	log = await _log()
	var cmds := _commands(log, mark)
	check(ok and cmds.size() == 3 and str(cmds[0].to) == "pc1", "drei Befehle an den PC (%d)" % cmds.size())
	if cmds.size() == 3:
		check(str(cmds[0].c.endpoint) == "play" and str(cmds[0].c.context.uri) == "spotify:playlist:37i9dQZEVXcDW", "Mix abspielen: play mit Kontext")
		check(str(cmds[1].c.options.skip_to.track_uri) == "spotify:track:t2", "Titel in der Playlist: skip_to")
		check((cmds[2].c.context.pages[0].tracks as Array).size() == 2 and not (cmds[2].c.context as Dictionary).has("uri"), "lose Liste: Kontext mit eigenen Seiten")
	await Music.poll()
	check(str(Music.now.get("title", "")) == "Titel 5" and str(Music.now.get("device", "")) == "WOHNZIMMER"
			and str(Music.now.get("art", "")) == "https://i.scdn.co/image/ab67",
			"Läuft gerade aus Spotify Connect: %s auf %s" % [str(Music.now.get("title", "")), str(Music.now.get("device", ""))])
	check(int(Music.now.get("volume", -1)) == 50 and bool(Music.now.get("playing", false)), "Lautstärke und Zustand gelesen")
	await Music.load_queue()
	check(Music.queue_list.map(func(t): return str(t.title)) == ["Titel 2", "Titel 3"],
			"Als Nächstes aus Spotify Connect, fehlende Angaben über getTrack: " + str(Music.queue_list.map(func(t): return str(t.title))))
	mark = (await _log()).size()
	await Music.play_pause()
	await Music.next()
	await Music.previous()
	await Music.seek_to(30000)
	await Music.set_shuffle(true)
	await Music.cycle_repeat()
	await Music.enqueue("spotify:track:t9")
	var vr: Dictionary = await Music.change_volume(10)
	# Die Lautstärke geht gebündelt hinaus (höchstens alle 300 ms, nur der letzte Wert): warten, bis sie raus ist.
	await _vol_done()
	log = await _log()
	var eps: Array = _commands(log, mark).map(func(x): return str(x.c.endpoint))
	check(eps == ["pause", "skip_next", "skip_prev", "seek_to", "set_shuffling_context", "set_repeating_context", "set_repeating_track", "add_to_queue"],
			"Pause, Weiter, Zurück, Spulen, Zufall, Wiederholen, Warteschlange: " + str(eps))
	var vol_ok := false
	for i in range(mark, log.size()):
		if str(log[i].p).begins_with("/spclient/connect-state/v1/connect/volume/") and str(log[i].b).contains("\"volume\":39321"):
			vol_ok = true
	check(bool(vr.ok) and vol_ok, "Lautstärke über Spotify Connect (60 %)")
	# Schnell hintereinander (Regler gehalten): Anzeige folgt jedem Schritt, an Spotify geht nur der letzte Wert.
	var vmark := (await _log()).size()
	for i in 3:
		await Music.change_volume(5)
	var shown := int(Music.now.get("volume", -1))
	await _vol_done()
	var vlog := await _log()
	var vols: Array = []
	for i in range(vmark, vlog.size()):
		if str(vlog[i].p).begins_with("/spclient/connect-state/v1/connect/volume/"):
			vols.append(str(vlog[i].b))
	check(shown == 75 and vols.size() >= 1 and vols.size() <= 2 and str(vols[-1]).contains("\"volume\":49151"),
			"Regler gehalten: Anzeige sofort 75 %%, an Spotify gebündelt nur der letzte Wert (%d Anfragen)" % vols.size())
	var web := 0
	for i in range(mark, log.size()):
		if str(log[i].p).begins_with("/v1/me/player"):
			web += 1
	check(web == 0, "keine Anfrage an api.spotify.com fürs Steuern (%d)" % web)
	var devs := await Music.devices()
	check(devs.size() == 1 and str(devs[0].name) == "WOHNZIMMER" and str(devs[0].type) == "Computer",
			"Geräte aus Spotify Connect, Uzais verstecktes Gerät nicht dabei")
	Music.set("_cluster_dirty", false)
	await Net.get_json(base + "/__push")
	var t0 := Time.get_ticks_msec()
	while not bool(Music.get("_cluster_dirty")) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(bool(Music.get("_cluster_dirty")), "Dealer meldet eine Änderung: Zustand wird neu gelesen")
	Music.dealer_close("Test")
	check(Music.get("_ws") == null, "Dealer lässt sich schließen")
	mark = (await _log()).size()
	await Music.poll()
	log = await _log()
	var again := false
	for i in range(mark, log.size()):
		if str(log[i].p).begins_with("/dealer"):
			again = true
	check(again and str(Music.now.get("title", "")) == "Titel 5", "bei Bedarf wieder verbunden")
	await _connect_nachsehen()
	var spf := FileAccess.get_file_as_string(Config.path("logs/spotify.log"))
	check(spf.contains("Dealer: verbunden") and spf.contains("Connect: play (playlist, Weg a) → WOHNZIMMER: HTTP 200") and spf.contains("Connect: läuft nach ")
			and not spf.contains("apptokWebplayer0123456789") and not spf.contains("access_token") and not spf.contains("37i9dQZEVXcDW"),
			"Protokoll ohne Zugangsdaten und Kennungen nennt Dealer, Befehle und ob es läuft")
	check(spf.contains("läuft nichts (Gerät aktiv: ja, Titel geladen: nein, läuft: nein) – versuche den nächsten Weg") and spf.contains("– alle Wege versucht"),
			"Protokoll sagt, was das Gerät nach dem Befehl zeigte")
	Music.dealer_close("Test")
	await Net.get_json(base + "/__set?devices=1")
	Music.set("_rate_until", { "app": 0, "eigen": 0 })
	Music.set("_app_slow_until", 0)
	Music.set("_app_429", 0)


## Spotify can accept the play command while the app on the PC starts nothing. Uzai therefore checks what the
## device reports, otherwise tries the next route, and finally reports that nothing is playing.
func _connect_nachsehen() -> void:
	print("Abspielen mit Nachsehen")
	Music.set("_warte_faktor", 0.2)
	var frisch := func(schalter: String) -> int:
		await Net.get_json(base + "/__set?webquota=1&devices=1" + schalter)
		Music.set("_cluster_dirty", true)
		Config.set_value("music.spotify_weg_liste", "a")
		Config.set_value("music.spotify_weg_kontext", "a")
		return (await _log()).size()
	var wege := func(mark: int) -> Array:
		var out: Array = []
		for e in await _log():
			mark -= 1
			if mark < 0 and str(e.m) == "POST" and str(e.p).begins_with("/spclient/connect-state/v1/player/command/from/"):
				var c: Variant = JSON.parse_string(str(e.b))
				var von := str(e.p).get_slice("/from/", 1).get_slice("/", 0)
				out.append({ "selbst": von == "pc1", "c": (c as Dictionary).command if c is Dictionary else {} })
		return out
	# Das Gerät führt nur die vollständige Form aus: Die schickt Uzai von Anfang an.
	var mark: int = await frisch.call("&streng=1")
	await Music.play_list([{ "uri": "spotify:track:t7" }, { "uri": "spotify:track:t8" }], 0)
	var w: Array = await wege.call(mark)
	await Music.poll()
	check(Music.error == "" and w.size() == 1 and str(Music.now.get("title", "")) == "Titel 7", "strenge App: ein Befehl reicht, der Titel läuft (%d)" % w.size())
	# Das Gerät führt nur aus, was von ihm selbst kommt: zweiter Weg, und der gilt ab dann zuerst.
	mark = await frisch.call("&nurziel=1")
	await Music.play_in("spotify:playlist:eigen", "spotify:track:t3")
	w = await wege.call(mark)
	check(Music.error == "" and w.size() == 2 and not bool(w[0].selbst) and bool(w[1].selbst) and str(Config.get_value("music.spotify_weg_kontext", "")) == "b",
			"erster Weg greift nicht: zweiter Weg (Zielgerät als Absender), gemerkt")
	mark = (await _log()).size()
	var ok: bool = await Music.play_context("spotify:album:a1")
	w = await wege.call(mark)
	check(ok and w.size() == 1 and bool(w[0].selbst), "der gemerkte Weg zuerst: wieder ein Befehl")
	# Das Gerät spielt nur einzelne Titel: dritter Weg – der Titel läuft, die Liste nicht.
	mark = await frisch.call("&nurtitel=1")
	await Music.play_list([{ "uri": "spotify:track:t8" }, { "uri": "spotify:track:t9" }], 0)
	w = await wege.call(mark)
	await Music.poll()
	check(Music.error == "" and w.size() == 3 and str(w[2].c.get("context", {}).get("uri", "")) == "spotify:track:t8" and str(Music.now.get("title", "")) == "Titel 8"
			and str(Config.get_value("music.spotify_weg_liste", "")) == "c", "lose Liste greift nicht: der Titel allein (%d Befehle)" % w.size())
	# Geladen, aber es steht: einmal anstoßen.
	mark = await frisch.call("&haengt=1")
	await Music.play_in("spotify:playlist:eigen", "spotify:track:t4")
	w = await wege.call(mark)
	check(Music.error == "" and w.map(func(x): return str(x.c.get("endpoint", ""))) == ["play", "resume"], "geladen, steht: einmal anstoßen")
	# Wie am PC: angenommen, Gerät aktiv, nichts geladen – auf keinem Weg. Dann sagt Uzai es.
	mark = await frisch.call("&stumm=1")
	var t0 := Time.get_ticks_msec()
	ok = await Music.play_context("spotify:playlist:eigen")
	w = await wege.call(mark)
	check(not ok and w.size() == 2 and Music.error.contains("nicht gestartet"), "nichts startet: beide Wege versucht, klare Meldung – " + Music.error)
	check(Time.get_ticks_msec() - t0 < 6000, "… und das in begrenzter Zeit")
	await get_tree().create_timer(0.5).timeout
	check(Toasts.eben_gezeigt(Music.error, 5000), "… auch als Pop-up, wo die Stelle selbst nichts zeigt")
	mark = await frisch.call("&stumm=1")
	await Music.play_list([{ "uri": "spotify:track:t8" }], 0)
	w = await wege.call(mark)
	check(Music.error != "" and w.size() == 3, "lose Liste, nichts startet: alle drei Wege (%d)" % w.size())
	await frisch.call("")
	Music.set("_warte_faktor", 1.0)
	ok = await Music.play_context("spotify:playlist:eigen")
	await Music.play_list([{ "uri": "spotify:track:t5" }], 0)
	await Music.poll()
	check(ok and Music.error == "" and str(Music.now.get("title", "")) == "Titel 5", "danach wieder wie gewohnt")


## Wartet, bis die gebündelte Lautstärke an Spotify Connect gegangen ist (höchstens 3 s).
func _vol_done() -> void:
	var t0 := Time.get_ticks_msec()
	while bool(Music.get("_vol_busy")) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame


## Befehle an Spotify Connect nach der Marke: [{ to, c }].
static func _commands(log: Array, from: int) -> Array:
	var out: Array = []
	for i in range(from, log.size()):
		var e: Dictionary = log[i]
		if str(e.m) == "POST" and str(e.p).begins_with("/spclient/connect-state/v1/player/command/from/"):
			var d: Variant = JSON.parse_string(str(e.b))
			if d is Dictionary and (d as Dictionary).get("command") is Dictionary:
				out.append({ "to": str(e.p).get_slice("/", str(e.p).get_slice_count("/") - 1), "c": d.command })
	return out

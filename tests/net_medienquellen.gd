extends Node
## Netz-Probe für die Filme-Quellen (Roadmap 35): spricht mit nachgebauten Diensten
## (tests/fake_medienquellen.py) – plex.tv und ein Plex-Server, ein Jellyfin-Server samt
## Heimnetz-Suche per UDP, link.stremio.com und api.strem.io. Prüft Anmeldung (PIN, Quick Connect,
## Passwort, Code), dass Schlüssel nur im Tresor und nur beim richtigen Server landen, Reihen,
## Details, Dateien, Fortschritt zurück, feindliche Antworten (Umleitung, zu groß, fremde Geräte)
## und das Abmelden. Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_medienquellen.py 18791 &
##   F=http://127.0.0.1:18791
##   UZAI_DATA=<ordner> UZAI_FAKE=$F UZAI_PLEX_TV=$F/plextv UZAI_STREMIO_LINK=$F/link UZAI_STREMIO_API=$F/stremio \
##     UZAI_JF_DISCOVERY=127.0.0.1:18791 godot --headless --path . res://tests/net_medienquellen.tscn

const Vault := preload("res://src/core/vault.gd")

var fails := 0
var base := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	# Die nachgebauten Server laufen auf 127.0.0.1 – im Betrieb gilt das nicht als Heimnetz.
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	base = OS.get_environment("UZAI_FAKE")
	if base == "" or OS.get_environment("UZAI_PLEX_TV") == "":
		print("UZAI_FAKE oder UZAI_PLEX_TV fehlt")
		get_tree().quit(1)
		return
	# Nur die Quellen dieser Probe (die Addon-Kataloge fragen sonst das Netz).
	Config.set_value("movies.sources", [])
	await get_tree().process_frame
	await _plex()
	await _jellyfin()
	await _stremio()
	await _hostile()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _clear() -> void:
	await Net.get_json(base + "/__clear")


static func _find(reqs: Array, m: String, p: String) -> Array:
	return reqs.filter(func(e): return str(e.m) == m and str(e.p).begins_with(p))


## Steht der Wert im Klartext in einer gespeicherten Datei des Profils?
func _in_files(text: String) -> bool:
	Config.save_settings()
	await get_tree().process_frame
	for f in [Config.path("settings.json"), Config.shared_path("gemeinsam.json")]:
		if FileAccess.file_exists(f) and FileAccess.get_file_as_string(f).contains(text):
			return true
	return false


# --- Plex --------------------------------------------------------------------------------------

func _plex() -> void:
	print("Plex")
	await _clear()
	var pin: Dictionary = await Quellen.plex_pin_start()
	check(bool(pin.ok) and str(pin.code) == "K7QZ" and str(pin.url) == "https://plex.tv/link", "PIN geholt, QR-Code führt zu plex.tv/link")
	check(await Quellen.plex_pin_poll(int(pin.id)) == "wait", "noch nicht bestätigt")
	check(await Quellen.plex_pin_poll(int(pin.id)) == "ok" and str(Config.get_value("plex.token", "")) == "plexAuthToken123", "bestätigt: Schlüssel gespeichert")
	check(not await _in_files("plexAuthToken123"), "Schlüssel nie im Klartext in den Einstellungen")
	var sv: Dictionary = await Quellen.plex_servers()
	check(bool(sv.ok) and (sv.servers as Array).size() == 1 and str(sv.servers[0].name) == "Testserver", "nur Server aus der Liste")
	var srv: Dictionary = sv.servers[0]
	var r1: Dictionary = await Quellen.plex_pick(srv, false)
	check(not bool(r1.ok) and bool(r1.get("http_needed", false)), "nur http erreichbar: Uzai fragt erst")
	var r2: Dictionary = await Quellen.plex_pick(srv, true)
	check(bool(r2.ok) and Quellen.connected("plex") and Quellen.is_on("plex"), "Server gewählt, Quelle eingeschaltet")
	var log1 := await _log()
	var ident := _find(log1, "GET", "/identity")
	check(not ident.is_empty() and ident.all(func(e): return not (e.h as Dictionary).has("x-plex-token")),
			"/identity ohne Schlüssel (erst prüfen, dann vertrauen)")
	check(Net.media_origins.has(base) and str(Net.media_origins[base]).contains("plexAuthToken123"), "Bilder des Servers freigegeben, mit Schlüssel als Kopfzeile")
	var rows: Array = await Movies.call("home_rows", true)
	var keys: Array = rows.map(func(r): return str(r.get("key", "")))
	check(keys.has("quelle:plex/neu/1") and keys.has("quelle:plex/bibliotheken") and keys.has("quelle:plex/sammlungen"),
			"Reihen: Neu in, Bibliotheken, Sammlungen %s" % str(keys))
	var cw := Movies.continue_watching()
	check(cw.any(func(c): return str(c.id) == "plex:200" and str(c.video_id) == "plex:302") and cw.any(func(c): return str(c.id) == "plex:123"),
			"Weiterschauen vom Server")
	var neu: Dictionary = rows[keys.find("quelle:plex/neu/1")]
	var poster := str(neu.items[0].poster)
	await _clear()
	var got := await Net.download(poster, Config.path("cache/test-plex.png"))
	var plog := await _log()
	check(got != "" and not poster.contains("plexAuthToken")
			and _find(plog, "GET", "/photo/:/transcode").any(func(e): return str(e.h.get("x-plex-token", "")) == "plexAuthToken123"),
			"Bild geladen: Schlüssel nur als Kopfzeile, nie in der Adresse")
	var m: Dictionary = await Movies.call("meta", "movie", "plex:123")
	check(str(m.get("name", "")) == "Matrix" and str(m.get("imdb_id", "")) == "tt0133093", "Details vom Server")
	check(is_equal_approx(float(Movies.progress("plex:123", "plex:123").position), 1200.0), "Stand des Servers übernommen")
	var series: Dictionary = await Movies.call("meta", "series", "plex:200")
	check((series.get("videos", []) as Array).size() == 3 and bool(Movies.watched("plex:200", "plex:301")), "Serie mit Folgen und „gesehen“")
	var list: Array = await Movies.call("streams", "movie", "plex:123")
	check(list.size() == 2 and str(list[0].url) == base + "/library/parts/11/1700000000/file.mkv" and str(list[0].headers["X-Plex-Token"]) == "plexAuthToken123",
			"Datei direkt vom Server mit Schlüssel als Kopfzeile")
	check((await Movies.call("subtitles", "movie", "plex:123") as Array).is_empty() and (list[0].subtitles as Array).size() == 1,
			"nur Untertitel des Servers (nie fremde Untertitel-Addons)")
	var page: Array = await Movies.call("catalog_page", "quelle:plex", "movie", "lib:1", 0, { "sort": "neu" })
	check(page.size() == 2, "Bibliothek seitenweise (Filme ohne Serie)")
	await _clear()
	Quellen.playback_started("plex:123", list[0])
	await get_tree().create_timer(0.4).timeout
	Quellen._session.last = -100000
	Quellen.playback_progress("plex:123", 600.0, 6000.0, true)
	await get_tree().create_timer(0.4).timeout
	await Quellen.playback_stopped("plex:123", 5800.0, 6000.0)
	var tl := _find(await _log(), "GET", "/:/timeline")
	var states: Array = tl.map(func(e): return str(e.p).get_slice("state=", 1).get_slice("&", 0))
	check(states == ["playing", "paused", "stopped"], "Fortschritt an Plex: playing, paused, stopped %s" % str(states))
	check(not _find(await _log(), "GET", "/:/scrobble").is_empty(), "ab 90 %: als gesehen gemeldet")
	await _clear()
	Movies.set_watched("plex:200", "plex:303", true)
	await get_tree().create_timer(0.5).timeout
	check(_find(await _log(), "GET", "/:/scrobble").any(func(e): return str(e.p).ends_with("key=303")), "„Gesehen“ aus Uzai geht an Plex")


# --- Jellyfin ----------------------------------------------------------------------------------

func _jellyfin() -> void:
	print("Jellyfin")
	var found: Array = await Quellen.discover("jellyfin")
	check(found.size() == 1 and str(found[0].address) == base + "/jf", "Heimnetz-Suche: nur die echte Antwort (fremdes Gerät und Riesen-Antwort verworfen)")
	var bad: Dictionary = await Quellen.server_check("jellyfin", "http://8.8.8.8:8096")
	check(not bool(bad.ok) and str(bad.error).contains("Heimnetz"), "http ins Internet abgelehnt")
	var srv: Dictionary = await Quellen.server_check("jellyfin", str(found[0].address))
	check(bool(srv.ok) and bool(srv.http) and str(srv.name) == "Keller", "Server geprüft (unverschlüsselt im Heimnetz)")
	check(not bool((await Quellen.server_check("emby", str(found[0].address))).ok), "Jellyfin als Emby gewählt: Hinweis statt Verbindung")
	check(await Quellen.quick_available("jellyfin", srv), "Quick Connect angeboten")
	var q: Dictionary = await Quellen.quick_start("jellyfin", srv)
	check(bool(q.ok) and str(q.code) == "482913", "Quick-Connect-Code")
	check(await Quellen.quick_poll("jellyfin", srv, str(q.secret)) == "wait", "noch nicht bestätigt")
	check(await Quellen.quick_poll("jellyfin", srv, str(q.secret)) == "ok" and Quellen.connected("jellyfin"), "bestätigt und angemeldet")
	check(not await _in_files("a1b2c3d4e5f60718293a4b5c6d7e8f90") and Vault.is_sealed(Config._sealed_settings().get("jellyfin", {}).get("token", "")),
			"Zugangsschlüssel nur verschlüsselt")
	var rows: Array = await Movies.call("home_rows", true)
	var keys: Array = rows.map(func(r): return str(r.get("key", "")))
	check(keys.has("quelle:jellyfin/neu/f1") and keys.has("quelle:jellyfin/sammlungen") and not keys.any(func(k): return str(k).contains("f9")),
			"Reihen von Jellyfin, ohne Musik")
	var jid := "jf:" + "01".repeat(16)
	check(Movies.continue_watching().any(func(c): return str(c.id) == jid), "Weiterschauen von Jellyfin")
	var list: Array = await Movies.call("streams", "movie", jid)
	check(list.size() == 1 and str(list[0].url).begins_with(base + "/jf/Videos/") and str(list[0].headers.Authorization).contains("Token=a1b2c3d4"),
			"Datei vom Server, Schlüssel als Kopfzeile")
	await _clear()
	Quellen.playback_started(jid, list[0])
	await get_tree().create_timer(0.4).timeout
	Quellen._session.last = -100000
	Quellen.playback_progress(jid, 300.0, 6000.0, false)
	await get_tree().create_timer(0.4).timeout
	await Quellen.playback_stopped(jid, 320.0, 6000.0)
	var lg := await _log()
	var paths: Array = lg.filter(func(e): return str(e.p).begins_with("/jf/Sessions/")).map(func(e): return str(e.p).substr(3))
	check(paths == ["/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"], "Fortschritt an Jellyfin %s" % str(paths))
	var stop := _find(lg, "POST", "/jf/Sessions/Playing/Stopped")
	check(not stop.is_empty() and int(JSON.parse_string(str(stop[0].b)).PositionTicks) == 3200000000, "Stelle in Ticks")
	check(await Quellen.login_password("jellyfin", srv, "Robin", "falsch") == "Name oder Passwort stimmt nicht.", "falsches Passwort")
	check(await Quellen.login_password("jellyfin", srv, "Robin", "richtig") == "" and not await _in_files("richtig"),
			"Anmeldung mit Passwort, das Passwort wird nicht gespeichert")
	await _clear()
	var origin := Net.origin(base + "/jf")
	await Quellen.sign_out("jellyfin")
	check(not _find(await _log(), "POST", "/jf/Sessions/Logout").is_empty() and not Quellen.connected("jellyfin")
			and str(Config.get_value("jellyfin.token", "")) == "", "Abmelden gibt den Zugang zurück und vergisst ihn")
	check(Net.media_origins.has(origin) == Quellen.connected("plex"), "nach dem Abmelden: nur noch Bilder verbundener Server")


# --- Stremio -------------------------------------------------------------------------------------

func _stremio() -> void:
	print("Stremio-Konto")
	var l: Dictionary = await Quellen.stremio_link_start()
	check(bool(l.ok) and str(l.code) == "XU4K2" and str(l.url).begins_with("https://link.stremio.com"), "Anmelde-Code für link.stremio.com")
	check(await Quellen.stremio_link_poll(str(l.code)) == "wait", "noch nicht bestätigt")
	check(await Quellen.stremio_link_poll(str(l.code)) == "ok" and Quellen.connected("stremio") and not await _in_files("stremio_auth_key_0123456789"),
			"angemeldet, Schlüssel verschlüsselt")
	var rows: Array = await Movies.call("home_rows", true)
	check(rows.any(func(r): return str(r.get("key", "")) == "quelle:stremio/bibliothek" and (r.items as Array).size() == 2), "Bibliothek aus Stremio")
	check(Movies.continue_watching().any(func(c): return str(c.id) == "tt0133093" and is_equal_approx(float(c.position), 1800.0)), "Weiterschauen aus Stremio")
	var ad: Dictionary = await Quellen.stremio_addons()
	check(bool(ad.ok) and (ad.addons as Array).size() == 1 and str(ad.addons[0].url) == "https://addon.example/abc/manifest.json",
			"eigene Addons: nur https, nichts wird von selbst installiert")
	await _clear()
	Movies.local_change.emit("progress",
			{ "meta_id": "tt0133093", "video_id": "tt0133093", "entry": { "position": 2400.0, "duration": 8160.0, "watched": false } })
	await get_tree().create_timer(0.6).timeout
	var put := _find(await _log(), "POST", "/stremio/datastorePut")
	var ch: Dictionary = JSON.parse_string(str(put[0].b)).changes[0] if not put.is_empty() else {}
	check(not ch.is_empty() and int(ch.state.timeOffset) == 2400000 and int(ch.state.overallTimeWatched) == 5,
			"Fortschritt zurück an Stremio, übrige Felder unverändert")


# --- Feindliches ---------------------------------------------------------------------------------

func _hostile() -> void:
	print("Feindliche Antworten")
	await _clear()
	var page: Array = await Movies.call("catalog_page", "quelle:plex", "movie", "lib:2", 0, {})
	check(page.is_empty() and Movies.error != "", "Umleitung auf fremden Host: nicht gefolgt")
	var rows: Array = await Quellen.search("gross")
	check(rows.filter(func(r): return str(r.get("source", "")) == "plex").is_empty(), "zu große Antwort: verworfen")
	Config.set_value("plex.token", "")
	Config.set_value("plex.server_token", "")
	Quellen.forgotten("plex")
	check(not Quellen.connected("plex") and Net.media_origins.is_empty(), "abgemeldet: keine Bilder mehr von dort")

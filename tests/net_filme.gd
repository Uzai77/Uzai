extends Node
## Netz-Probe für Filme: spricht mit nachgebauten Stremio-Addons und einem Plugin-Repository
## (tests/fake_addons.py). Die JavaScript-Scraper laufen über den echten Runner – hier mit Node 22
## statt Deno. Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_addons.py 18766 &
##   F=http://127.0.0.1:18766
##   UZAI_DATA=<ordner> UZAI_FAKE=$F UZAI_CINEMETA=$F/cinemeta/manifest.json UZAI_TMDB_API=$F/tmdb/3 \
##     UZAI_JS_RUNTIME=/opt/node22/bin/node godot --headless --path . res://tests/net_filme.tscn
## Mit Deno geht das nicht: Uzai sperrt Plugins den Zugriff auf 127.0.0.1, also auch auf den
## nachgebauten Server. Die Deno-Rechte prüft tests/logic_plugin_rechte.gd.

var fails := 0
var base := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	# Bilder kommen hier vom nachgebauten Server auf 127.0.0.1 – im Betrieb gesperrt (Net.download_allowed).
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	base = OS.get_environment("UZAI_FAKE")
	if base == "" or OS.get_environment("UZAI_CINEMETA") == "":
		print("UZAI_FAKE oder UZAI_CINEMETA fehlt")
		get_tree().quit(1)
		return
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _clear() -> void:
	await Net.get_json(base + "/__clear")


static func _find(reqs: Array, m: String, p: String) -> Dictionary:
	for e in reqs:
		if str(e.m) == m and str(e.p) == p:
			return e
	return {}


func _wait(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > secs * 1000.0:
			return false
		await get_tree().process_frame
	return true


func _addon_id(name: String) -> String:
	for a in Movies.addons:
		if str(a.name) == name:
			return str(a.id)
	return ""


func _run() -> void:
	print("Addons")
	check(Movies.addons.size() == 1 and str(Movies.addons[0].url) == base + "/cinemeta/manifest.json", "Cinemeta ist vorinstalliert")
	var err: String = await Movies.refresh_addons()
	check(err == "" and str(Movies.addons[0].name) == "Cinemeta Test" and (Movies.addons[0].catalogs as Array).size() == 5, "Manifest geladen (%s)" % err)
	err = await Movies.install_addon(base + "/streams")
	check(err == "" and str(Movies.addons[1].id) == "org.test.streams" and str(Movies.addons[1].url) == base + "/streams/manifest.json",
			"Stream-Addon über die Basis-Adresse installiert (%s)" % err)
	check(bool(Movies.addons[1].configurable) and Movies.configure_url("org.test.streams") == base + "/streams/configure", "einrichtbar, Seite zum Einrichten")
	for path in ["/kaputt/manifest.json", "/zweit/manifest.json", "/subs/manifest.json"]:
		err = await Movies.install_addon(base + path)
		check(err == "", "installiert: " + path)
	err = await Movies.install_addon(base + "/einrichten/manifest.json")
	check(err.contains("eingerichtet") and err.contains("/einrichten/configure"), "muss eingerichtet werden: " + err)
	err = await Movies.install_addon(base + "/keinaddon/manifest.json")
	check(err.contains("nicht gefunden") and not err.contains("404"), "kein Addon: verständlich, ohne Code: " + err)
	err = await Movies.install_addon(base + "/streams/manifest.json")
	check(err.contains("schon"), "doppelt: " + err)
	check(Movies.addons.map(func(a): return str(a.name)) == ["Cinemeta Test", "Stream-Test", "Kaputt", "Zweit", "Untertitel-Test"], "Reihenfolge wie eingetragen")
	Movies.move_addon("org.test.subs", -10)
	check(str(Movies.addons[0].id) == "org.test.subs", "nach oben geschoben")
	Movies.move_addon("org.test.subs", 10)
	check(str(Movies.addons[4].id) == "org.test.subs", "wieder nach unten")
	check((Config.get_value("movies.addons", []) as Array).size() == 5, "in den Einstellungen gespeichert")

	print("Startseite")
	await _clear()
	var rows: Array = await Movies.home_rows()
	var titles: Array = rows.map(func(r): return str(r.title))
	check(titles == ["Beliebt – Filme", "Beliebt – Serien"], "Kataloge ohne Pflicht-Zusätze, leere weg: " + str(titles))
	var reqs := await _log()
	check(_find(reqs, "GET", "/cinemeta/catalog/movie/year.json").is_empty() and not _find(reqs, "GET", "/cinemeta/catalog/movie/leer.json").is_empty(),
			"Pflicht-Genre nicht gefragt, leerer Katalog schon")
	if rows.size() == 2:
		var it: Dictionary = rows[0].items[0]
		check(str(it.name) == "Matrix" and str(it.year) == "1999" and str(it.logo).ends_with("/img/l1.png") and str(it.type) == "movie",
				"Vorschau mit Jahr, Logo und Typ")
		check(str(rows[1].items[0].id) == "tt100" and rows[1].items[0].genres == ["Drama"], "Serie in der zweiten Reihe")
	var hero := Movies.hero_items()
	check(hero.size() == 4 and str(hero[hero.size() - 1].id) == "tt003", "großes Bild: mit Schriftzug zuerst, ohne danach (%d)" % hero.size())
	# Auffrischen ohne Netz: die gemerkten Reihen (Speicher und Platte) bleiben samt Zeitpunkt.
	var hc: Dictionary = Movies._home_cache
	var keep_rows: Array = (hc.get("rows", []) as Array).duplicate(true)
	var keep_at := float(hc.get("at", -1.0))
	var disk_before: Variant = Config.read_json(Config.path("cache/nuvio_home.json"), {})
	var urls: Array = []
	for a in Movies.addons:
		urls.append(a.url)
		a.url = "http://127.0.0.1:9/weg/manifest.json"
	var announced := [0]
	var on_ready := func() -> void: announced[0] += 1
	Movies.home_ready.connect(on_ready)
	await Movies._refresh_home(str(hc.get("sig", "")))
	Movies.home_ready.disconnect(on_ready)
	for i in urls.size():
		Movies.addons[i].url = urls[i]
	check(Movies._home_cache.get("rows", []) == keep_rows and is_equal_approx(float(Movies._home_cache.get("at", 0.0)), keep_at) and int(announced[0]) == 0,
			"offline aufgefrischt: alte Reihen bleiben, nicht als frisch gemerkt")
	check(Config.read_json(Config.path("cache/nuvio_home.json"), {}) == disk_before and (disk_before as Dictionary).has("rows"), "Platte unverändert")
	rows = await Movies.home_rows()
	check(rows == keep_rows, "Startseite zeigt weiter die alten Reihen")
	await _clear()
	var page: Array = await Movies.catalog_page("com.linvo.cinemeta", "movie", "top", 100, { "genre": "Science Fiction" })
	reqs = await _log()
	check(not _find(reqs, "GET", "/cinemeta/catalog/movie/top/genre=Science%20Fiction&skip=100.json").is_empty(), "Katalog-Adresse mit Genre und skip wie Stremio")
	check(page.is_empty(), "keine Treffer für das Genre")
	page = await Movies.catalog_page("com.linvo.cinemeta", "movie", "top", 0, { "genre": "Drama" })
	check(page.size() == 2, "Genre Drama: zwei Filme")
	check(Movies.genres("movie") == ["Action", "Drama", "Sci-Fi", "Science Fiction"], "Genres aus dem Manifest")
	var found: Array = await Movies.search("matr")
	check(found.size() == 1 and str(found[0].title) == "Filme" and str(found[0].items[0].id) == "tt001", "Suche: nur Reihen mit Treffern")

	print("Details")
	var sm: Dictionary = await Movies.meta("series", "tt100")
	check(sm.seasons == [1, 2, 0] and str(sm.videos[0].id) == "tt100:1:1" and str(sm.videos[4].id) == "tt100:0:1", "Staffeln und Folgen, Specials hinten")
	check(sm.cast == ["Ada Muster"] and sm.director == ["Bo Regie"] and str(sm.trailers[0].yt_id) == "abc123" and str(sm.logo).ends_with("/img/sl.png"),
			"Besetzung, Trailer, Logo")
	check(not bool(sm.videos[3].available), "künftige Folge nicht verfügbar")
	var mm: Dictionary = await Movies.meta("movie", "tt001")
	check(str(mm.tmdb_id) == "603" and str(mm.runtime) == "136 min", "Film mit TMDB-ID und Laufzeit")

	print("Besetzung mit Bildern")
	var mp: Dictionary = mm.get("people", {})
	check(mm.cast == ["Keanu R.", "Carrie-Anne M.", "Laurence F."], "Besetzung aus cast und credits_cast: " + str(mm.cast))
	check(str(mp.get("keanu r.", {}).get("photo", "")) == base + "/img/person-keanu.png" and str(mp["keanu r."].character) == "Neo",
			"app_extras.cast: Bild und Figur")
	check(str(mp.get("carrie-anne m.", {}).get("photo", "")) == "https://image.tmdb.org/t/p/w185/carrie.jpg" and str(mp["laurence f."].photo) == "",
			"credits_cast mit TMDB-Bildadresse, ohne Bild leer")
	var keep_mm := mm.duplicate(true)
	var direct: Dictionary = await Movies.cast_photos("movie", mm)
	check(direct == mp, "Bilder schon da: keine weitere Anfrage")
	var got_tex: Array = []
	Media.url_texture(str(mp["keanu r."].photo), 120, func(t: Texture2D) -> void: got_tex.append(t))
	await _wait(func() -> bool: return not got_tex.is_empty(), 5.0)
	check(not got_tex.is_empty() and got_tex[0] != null and (got_tex[0] as Texture2D).get_height() > (got_tex[0] as Texture2D).get_width(),
			"Porträt geladen (Hochformat)")
	check(FileAccess.file_exists(Config.path("cache/img/web/%s.png" % str(mp["keanu r."].photo).md5_text())), "Personenbild im Datei-Cache")
	# Cinemeta liefert die Serie nur mit Namen: Bilder aus dem nächsten Addon mit Details (Zweit).
	check(not Movies.has_photos(sm.get("people")), "Serie: nur Namen")
	await _clear()
	var sp: Dictionary = await Movies.cast_photos("series", sm)
	reqs = await _log()
	check(str(sp.get("ada muster", {}).get("photo", "")) == "https://image.tmdb.org/t/p/w185/ada.jpg" and str(sp["ada muster"].character) == "Kommissarin",
			"Serie: Bild aus anderem Addon (%s)" % str(sp))
	check(not _find(reqs, "GET", "/zweit/meta/series/tt100.json").is_empty() and _find(reqs, "GET", "/cinemeta/meta/series/tt100.json").is_empty(),
			"nur das andere Addon gefragt")
	var sm2: Dictionary = await Movies.meta("series", "tt100")
	check(Movies.has_photos(sm2.get("people")), "nachgeladene Bilder im Meta-Cache")
	await _clear()
	var sp2: Dictionary = await Movies.cast_photos("series", sm)
	check(sp2 == sp and (await _log()).filter(func(q): return str(q.p).contains("/meta/")).is_empty(), "je Titel nur einmal nachgeladen")
	var nm: Dictionary = await Movies.cast_photos("movie",
			Movies.parse_meta({ "id": "tt002", "name": "Zweiter Film", "cast": ["Keanu R."] }, "com.linvo.cinemeta", "movie"))
	check(nm.is_empty(), "ohne Schlüssel und ohne anderes Addon: keine Bilder (Initialen)")
	mm = keep_mm
	var none: Dictionary = await Movies.meta("movie", "tt999")
	check(none.is_empty() and Movies.error != "", "unbekannt: leer mit Grund (%s)" % Movies.error)

	print("Streams")
	var partial: Array = []
	var list: Array = await Movies.streams("movie", "tt001", func(l: Array) -> void: partial.append(l.size()))
	check(partial.size() >= 2 and partial[partial.size() - 1] == list.size(), "Teilergebnisse nach jeder Quelle: " + str(partial))
	check(list.size() == 3, "nur direkte Adressen, P2P und ytId weg (%d)" % list.size())
	if list.size() == 3:
		check(bool(list[0].cached) and int(list[0].quality) == 720, "gecacht zuerst")
		check(int(list[1].quality) == 2160 and str(list[1].hdr) == "DV" and int(list[2].quality) == 1080, "dann nach Qualität")
		check(str(list[1].headers.Referer) == base + "/" and str(list[1].headers["User-Agent"]) == "TestUA/1", "proxyHeaders als Kopfzeilen")
		check(str(list[2].size_text) == "8,5 GB" and (list[2].subtitles as Array).size() == 1, "Größe aus description, Untertitel am Stream")
	var st := Movies.stream_sources_status()
	var states := {}
	for s in st:
		states[str(s.name)] = "%s/%d" % [s.state, int(s.count)]
	check(states.get("Stream-Test", "") == "fertig/3" and str(states.get("Kaputt", "")).begins_with("fehler") and not states.has("Zweit"),
			"Quellen: " + str(states))
	Config.set_value("movies.no_p2p", false)
	list = await Movies.streams("movie", "tt001")
	check(list.size() == 5 and bool(list[3].is_p2p) and bool(list[4].is_p2p) and str(list[3].url) == "", "P2P erlaubt: hinten, ohne Adresse")
	Config.set_value("movies.no_p2p", true)
	list = await Movies.streams("series", "tt100:1:1")
	var names: Array = list.map(func(s): return str(s.addon_name))
	check("Zweit" in names and list.size() == 4, "Serie: Zweit-Addon liefert Streams aus seinen Details (inline): " + str(names))
	var subs: Array = await Movies.subtitles("movie", "tt001")
	check(subs.size() == 2 and str(subs[0].lang) == "ger" and str(subs[0].label).begins_with("Deutsch"), "Untertitel, doppelte Adresse nur einmal")

	print("Plugins")
	err = await Movies.add_plugin_repo(base + "/plugins")
	check(err == "" and Movies.plugin_repos.size() == 1 and Movies.error.contains("1 von 5"), "Repository mit Scrapern geladen (%s / %s)" % [err, Movies.error])
	var scs: Array = Movies.plugin_repos[0].scrapers if not Movies.plugin_repos.is_empty() else []
	check(scs.size() == 4 and not bool(scs[3].enabled) and bool(scs[0].enabled), "vier Scraper, „Aus“ ist laut Manifest aus")
	err = await Movies.add_plugin_repo(base + "/cloudstream/repo.json")
	check(err.contains("CloudStream"), "CloudStream abgelehnt: " + err)
	var kind := str(Movies.plugin_runtime().get("kind", ""))
	check(kind in ["node", "deno"], "Laufzeit für den Test: " + kind)
	await _clear()
	partial = []
	list = await Movies.streams("movie", "tt001", func(l: Array) -> void: partial.append(l.size()))
	var by_src := {}
	for s in list:
		by_src[str(s.addon_name)] = int(by_src.get(str(s.addon_name), 0)) + 1
	check(by_src.get("Alpha", 0) == 2 and by_src.get("Beta", 0) == 1 and not by_src.has("Aus"), "Plugin-Streams dabei: " + str(by_src))
	var alpha := {}
	var beta := {}
	for s in list:
		if str(s.addon_name) == "Alpha" and int(s.quality) == 1080:
			alpha = s
		if str(s.addon_name) == "Beta":
			beta = s
	check(str(alpha.get("url", "")) == base + "/v/603-1080.m3u8" and str(alpha.get("headers", {}).get("Referer", "")) == base + "/site/",
			"cheerio: Link, Qualität und Kopfzeilen")
	check(str(alpha.get("title", "")).begins_with("Film 603 & mehr (") and str(alpha.get("size_text", "")) == "2,1 GB"
			and str(alpha.get("name", "")) == "Alpha - 1080p", "Text mit Entities, SCRAPER_ID, Größe")
	check(str(beta.get("name", "")) == "Beta ok - 4K" and int(beta.get("quality", 0)) == 2160, "CryptoJS (HMAC, Base64, AES) und POST")
	st = Movies.stream_sources_status()
	var ps := {}
	for s in st:
		if str(s.kind) == "plugin":
			ps[str(s.name)] = "%s:%s" % [s.state, s.error]
	check(str(ps.get("Fehler", "")).contains("Absichtlich kaputt") and str(ps.get("Alpha", "")).begins_with("fertig") and not ps.has("Aus"),
			"Fehler pro Scraper: " + str(ps))
	reqs = await _log()
	var hit := _find(reqs, "GET", "/site/film/603")
	var hdr: Dictionary = hit.get("h", {})
	check(str(hdr.get("x-test", "")) == "ja" and str(hdr.get("user-agent", "")).begins_with("Mozilla/5.0")
			and not str(hdr.get("accept-encoding", "")).contains("x-uzai-test"), "fetch mit Kopfzeilen, Standard-User-Agent, ohne Accept-Encoding")
	var post := _find(reqs, "POST", "/site/api")
	check(str(post.get("b", "")) == "{\"id\":\"603\",\"typ\":\"movie\"}", "POST-Körper als Text, TMDB-ID aus Cinemeta")
	check(FileAccess.file_exists(Config.path("logs/plugins.log"))
			and FileAccess.get_file_as_string(Config.path("logs/plugins.log")).contains("Absichtlich kaputt"), "Meldungen der Scraper im Log")
	var alpha_id := str(scs[0].id) if not scs.is_empty() else ""
	Movies.set_scraper_enabled(alpha_id, false)
	list = await Movies.streams("movie", "tt001")
	check(not list.any(func(s): return str(s.addon_name) == "Alpha"), "Scraper einzeln abgeschaltet")
	Movies.set_scraper_enabled(alpha_id, true)
	list = await Movies.streams("series", "tt100:2:1")
	var ser: Array = list.filter(func(s): return str(s.addon_name) == "Alpha")
	check(ser.size() == 2 and str(ser[0].url).contains("1399-2-1"), "Serie: getStreams(tmdbId, 'tv', 2, 1)")
	Movies.set_plugins_enabled(false)
	list = await Movies.streams("movie", "tt001")
	check(not Movies.stream_sources_status().any(func(s): return str(s.kind) == "plugin") and list.size() == 3, "Plugins ganz aus")
	Movies.set_plugins_enabled(true)

	print("TMDB (eigener Schlüssel, optional)")
	Config.set_value("movies.tmdb_key", "testkey")
	Movies._meta_cache = {}
	var de: Dictionary = await Movies.meta("movie", "tt001")
	check(str(de.name) == "Matrix (deutsch)" and str(de.description) == "Deutsche Beschreibung." and str(de.name_original) == "Matrix", "deutscher Titel und Text")
	var de2: Dictionary = await Movies.meta("movie", "tt002")
	check(str(de2.name) == "Zweiter Film DE" and str(de2.description) == "Beschreibung 2" and str(de2.tmdb_id) == "702",
			"leerer Text bleibt englisch, TMDB-ID ergänzt")
	Movies._people_cache = {}
	await _clear()
	var tp: Dictionary = await Movies.cast_photos("movie", de2)
	reqs = await _log()
	check(str(tp.get("keanu r.", {}).get("photo", "")) == "https://image.tmdb.org/t/p/w185/keanu-tmdb.jpg" and str(tp["keanu r."].character) == "Neo"
			and str(tp.get("wachowski", {}).get("photo", "")).ends_with("/wachowski.jpg"), "TMDB /movie/702/credits: Besetzung und Regie mit Bild")
	check(str(_find(reqs, "GET", "/tmdb/3/movie/702/credits").get("q", "")).contains("api_key=testkey"), "mit eigenem Schlüssel")
	var tsp: Dictionary = await Movies.cast_photos("series", await Movies.meta("series", "tt100"))
	check(str(tsp.get("ada muster", {}).get("photo", "")).ends_with("/ada-tmdb.jpg") and str(tsp["ada muster"].character) == "Kapitänin",
			"Serie: TMDB aggregate_credits zuerst")
	Movies._people_cache = {}
	Config.set_value("movies.tmdb_key", "")
	Movies._meta_cache = {}

	print("Abspielen und Fortschritt")
	var ended_args: Array = []
	Movies.ended.connect(func(m: Dictionary, vid: String, nxt: Dictionary) -> void: ended_args.append([str(m.id), vid, str(nxt.get("id", ""))]))
	sm = await Movies.meta("series", "tt100")
	list = await Movies.streams("series", "tt100:1:1")
	err = Movies.play(sm, "tt100:1:1", list[0])
	check(err == "" and Video.active and str(Video.video.movies.meta_id) == "tt100", "läuft (%s)" % err)
	check(str(Video.video.info).begins_with("Staffel 1 · Folge 1  ·  Anfang  ·  720p") and str(Video.video.next_title) == "Folge 2: Mitte"
			and str(Video.video.media_title) == "Testserie – S01E01", "Leiste: Folge, Titel, Als Nächstes")
	var got_subs := await _wait(func() -> bool: return (Video.video.get("subtitles", []) as Array).any(func(s): return str(s.url).ends_with("/sub/de.srt")), 5.0)
	check(got_subs, "Addon-Untertitel als Spuren nachgereicht")
	await _wait(func() -> bool: return not Video.loading, 3.0)
	Video.seek_to(400.0)
	await get_tree().create_timer(0.2).timeout
	await Video.stop()
	var pr := Movies.progress("tt100", "tt100:1:1")
	check(float(pr.position) >= 400.0 and float(pr.position) < 405.0 and not bool(pr.watched), "Fortschritt beim Beenden gespeichert (%.1f)" % float(pr.position))
	var cw := Movies.continue_watching()
	check(cw.size() == 1 and str(cw[0].id) == "tt100" and not bool(cw[0].next_up) and str(cw[0].name) == "Testserie", "Weiterschauen: angefangene Folge")
	err = Movies.play(sm, "tt100:1:1", list[0])
	check(err == "" and absf(Video.pos - (float(pr.position) - 3.0)) < 1.0, "geht an der Stelle weiter (%.1f)" % Video.pos)
	await _wait(func() -> bool: return not Video.loading, 3.0)
	Video.seek_to(Video.duration - 0.5)
	var ended_ok := await _wait(func() -> bool: return not ended_args.is_empty(), 4.0)
	check(ended_ok and ended_args[0] == ["tt100", "tt100:1:1", "tt100:1:2"], "zu Ende: nächste Folge angeboten " + str(ended_args))
	check(Movies.watched("tt100", "tt100:1:1") and Movies.autoplay_left() > 0.0, "ab 90 % gesehen, nächste Folge startet gleich")
	err = await Movies.play_next()
	check(err == "" and str(Video.video.movies.video_id) == "tt100:1:2" and str(Video.video.url).contains("tt100-1-2-720rd") and Movies.autoplay_left() < 0.0,
			"nächste Folge mit Stream aus derselben Gruppe (%s)" % err)
	await Video.stop()
	cw = Movies.continue_watching()
	check(cw.size() == 1 and bool(cw[0].next_up) and str(cw[0].video_id) == "tt100:1:2", "Als Nächstes: Folge 2")
	Movies.set_watched("tt100", "tt100:1:2", true)
	cw = Movies.continue_watching()
	check(cw.size() == 1 and str(cw[0].video_id) == "tt100:2:1", "über den Staffelwechsel")
	Movies.set_watched("tt100", "tt100:2:1", true)
	check(Movies.continue_watching().is_empty(), "nächste Folge noch nicht ausgestrahlt: nichts")
	Movies.set_watched("tt100", "tt100:2:1", false)
	check(not Movies.watched("tt100", "tt100:2:1") and Movies.continue_watching().size() == 1, "gesehen zurückgenommen")
	await get_tree().create_timer(1.1).timeout
	mm = await Movies.meta("movie", "tt001")
	list = await Movies.streams("movie", "tt001")
	Movies.play(mm, "tt001", list[0])
	await _wait(func() -> bool: return not Video.loading, 3.0)
	Video.seek_to(120.0)
	await Video.stop()
	cw = Movies.continue_watching()
	check(cw.size() == 2 and str(cw[0].id) == "tt001", "Film zuerst (neuester)")
	Movies.remove_continue("tt001")
	check(Movies.continue_watching().size() == 1 and Movies.progress("tt001", "tt001").position > 100.0, "aus Weiterschauen genommen, Stelle bleibt")
	err = Movies.play(mm, "tt001", { "url": "", "is_p2p": true })
	check(err.contains("P2P"), "P2P wird nicht abgespielt")

	print("Bibliothek")
	check(Movies.toggle_library(mm) and Movies.in_library("tt001") and Movies.library_items().size() == 1, "gemerkt")
	check(not (Movies.library_items()[0] as Dictionary).has("videos") and str(Movies.library_items()[0].name) != "", "nur die Vorschau gespeichert")
	check(not Movies.toggle_library(mm) and not Movies.in_library("tt001"), "wieder entfernt")
	Movies.save()
	var saved: Variant = Config.read_json(Config.path("movies.json"), {})
	check(saved is Dictionary and (saved.progress as Dictionary).has("tt100") and (saved.items as Dictionary).has("tt100"), "movies.json im Datenordner")

	print("Aufräumen")
	var rid := str(Movies.plugin_repos[0].id) if not Movies.plugin_repos.is_empty() else ""
	var script_file := Movies._script_path(alpha_id)
	check(FileAccess.file_exists(script_file), "Skript liegt im Datenordner")
	Movies.remove_plugin_repo(rid)
	check(Movies.plugin_repos.is_empty() and not FileAccess.file_exists(script_file), "Repository entfernt, Skripte gelöscht")
	Movies.remove_addon("org.test.kaputt")
	Movies.set_addon_enabled("org.test.streams", false)
	list = await Movies.streams("movie", "tt001")
	check(list.is_empty() and Movies.error.contains("Kein Addon"), "ohne Stream-Addon: klarer Hinweis (%s)" % Movies.error)
	check(Movies.addons.size() == 4 and _addon_id("Kaputt") == "", "Addon entfernt")

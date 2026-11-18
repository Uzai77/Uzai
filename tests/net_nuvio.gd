extends Node
## Netz-Probe fürs Nuvio-Konto gegen die nachgebaute API (tests/fake_nuvio.py): QR-Anmeldung,
## E-Mail/Passwort, Abgleich (Profile, Addons, Plugins, Bibliothek, Weiterschauen, Gesehen,
## Layout, Sammlungen, Titelbild), Zurückschreiben und Abmelden. Aufruf (leerer Datenordner):
##   python3 tests/fake_nuvio.py 18767 &
##   F=http://127.0.0.1:18767
##   UZAI_DATA=<ordner> UZAI_NUVIO_API=$F UZAI_FAKE=$F UZAI_CINEMETA=$F/addon/keins/manifest.json \
##     UZAI_JS_RUNTIME=/opt/node22/bin/node godot --headless --path . res://tests/net_nuvio.tscn

var fails := 0
var base := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_FAKE")
	if base == "" or OS.get_environment("UZAI_NUVIO_API") == "":
		print("UZAI_FAKE oder UZAI_NUVIO_API fehlt")
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


static func _calls(reqs: Array, rpc_name: String) -> Array:
	return reqs.filter(func(e): return str(e.p) == "/rest/v1/rpc/" + rpc_name)


func _settle(secs := 1.5) -> void:
	await get_tree().create_timer(secs).timeout


func _run() -> void:
	await _clear()
	print("Anmelden per QR-Code")
	check(not NuvioSync.connected(), "am Anfang nicht angemeldet")
	var st := await NuvioSync.login_start()
	check(bool(st.ok) and str(st.url) == "https://nuvio.tv/link?code=ABCD-EFGH" and str(st.user_code) == "ABCD-EFGH", "Code und Adresse für den QR-Code")
	var reqs := await _log()
	var start := _calls(reqs, "start_device_login_session")
	check(not start.is_empty() and str(start[0].body.p_redirect_base_url) == "https://nuvio.tv/link" and str(start[0].body.p_device_type) == "tv"
			and str(start[0].body.p_device_nonce).length() >= 30, "wie Nuvio TV: Weiterleitung nuvio.tv/link, Gerät „tv“, zufällige Nonce")
	check(not start.is_empty() and str(start[0].auth) == "", "ohne Anmeldung (nur öffentlicher Schlüssel)")
	var res := ""
	for i in 6:
		res = await NuvioSync.login_poll(str(st.code), str(st.nonce))
		if res != "pending":
			break
	check(res == "ok", "nach zweimal „wartet“ bestätigt und angemeldet")
	check(NuvioSync.connected() and NuvioSync.email() == "lea@example.com", "Konto gemerkt (E-Mail)")
	check(str(Config.get_value("nuvio.user_id", "")) == "user-uuid-1", "Nutzer-ID aus dem Token")
	# _after_login startet den Abgleich; warten, bis er fertig ist.
	if NuvioSync.busy:
		await NuvioSync.synced
	check(NuvioSync.last_error == "", "Abgleich ohne Fehler (%s)" % NuvioSync.last_error)

	print("Übernommen")
	check(NuvioSync.profiles().size() == 2 and NuvioSync.profile_name() == "Lea", "Profile, erstes aktiv")
	var urls: Array = Movies.addons.map(func(a): return str(a.url))
	check(urls == [base + "/addon/a1/manifest.json", base + "/addon/a2/manifest.json"], "Addons wie im Konto, in Nuvios Reihenfolge (Cinemeta weg wie bei Nuvio)")
	check(Movies.addons.size() == 2 and str(Movies.addons[0].name) == "Eins" and (Movies.addons[0].catalogs as Array).size() == 3, "Manifeste geladen")
	check(Movies.plugin_repos.size() == 1 and str(Movies.plugin_repos[0].url) == base + "/repo/manifest.json",
			"Plugin-Verzeichnis übernommen, CloudStream weggelassen")
	var lib := Movies.library_items()
	check(lib.size() == 2 and str(lib[0].id) == "tt001" and str(lib[0].year) == "2001" and str(lib[0].imdb_rating) == "7.5", "Bibliothek mit Jahr und Bewertung")
	var cw := Movies.continue_watching()
	var ids: Array = cw.map(func(c): return str(c.id))
	check("tt002" in ids and "tt050" in ids, "Weiterschauen: Film und Serie")
	var s50: Dictionary = {}
	for c in cw:
		if str(c.id) == "tt050":
			s50 = c
	check(not s50.is_empty() and str(s50.video_id) == "tt050:1:2" and is_equal_approx(float(s50.position), 600.0) and str(s50.name) == "Serie 50",
			"Serie: Folge 1×2 bei 10:00, Name aus der Bibliothek")
	var t2: Dictionary = {}
	for c in cw:
		if str(c.id) == "tt002":
			t2 = c
	check(str(t2.get("name", "")) == "Titel 2", "Name für Weiterschauen über das Addon nachgeladen")
	check(Movies.watched("tt050", "tt050:1:1") and Movies.watched("tt003", "tt003"), "Gesehen aus dem Verlauf")

	print("Layout der Startseite")
	var rows: Array = await Movies.home_rows(true)
	var titles: Array = rows.map(func(r): return str(r.title))
	print("      Reihen: ", titles)
	check(titles.size() >= 3 and titles[0] == "Meine Liebsten", "eigener Titel, erste Reihe wie in Nuvio")
	check(titles.size() >= 3 and titles[1] == "Wochenende" and str(titles[2]).begins_with("Top Serien"), "Sammlung „Wochenende“ an ihrem Platz, dann Top Serien")
	if rows.size() >= 2:
		var coll: Dictionary = rows[1]
		var fo: Array = coll.get("folders", []) if coll.get("folders") is Array else []
		check(str(coll.get("kind", "")) == "folders" and fo.size() == 1 and str(fo[0].title) == "Spannung", "als Reihe mit Ordner-Kachel „Spannung“")
		check(fo.size() == 1 and (fo[0].sources as Array).any(func(s): return str(s.catalog_id) == "neu" and str(s.addon_id) == "org.test.eins"),
				"Ordner zeigt auf Katalog „neu“ von Eins")
	check(not titles.any(func(t): return str(t).begins_with("Top Filme")), "ausgeschalteter Katalog fehlt")
	check(str(titles[-1]).begins_with("Neu"), "Katalog, den das Layout nicht kennt, kommt hinten dran")
	var hero := Movies.hero_items()
	check(not hero.is_empty() and hero.all(func(h): return str(h.type) == "series"), "Titelbild aus dem gewählten Katalog (Top Serien)")
	check(NuvioSync.hero_enabled() and NuvioSync.continue_enabled(), "Titelbild und Weiterschauen laut Einstellungen an")

	print("Zurückschreiben")
	await _clear()
	Movies.record("tt002", "tt002", 2400.0, 6000.0)
	await _settle(7.5)
	reqs = await _log()
	var pw := _calls(reqs, "sync_push_watch_progress")
	check(not pw.is_empty() and int(pw[0].body.p_profile_id) == 1, "Fortschritt geht zurück (gesammelt)")
	if not pw.is_empty():
		var e: Dictionary = pw[0].body.p_entries[0]
		check(str(e.content_id) == "tt002" and int(e.position) == 2400000 and int(e.duration) == 6000000 and str(e.content_type) == "movie",
				"in Millisekunden, als Film")
	await _clear()
	Movies.toggle_library({ "id": "tt099", "type": "movie", "name": "Neu gemerkt", "poster": "" })
	await _settle()
	Movies.toggle_library({ "id": "tt001", "type": "movie" })
	await _settle()
	reqs = await _log()
	var up := _calls(reqs, "sync_push_library_items")
	var de := _calls(reqs, "sync_delete_library_items")
	check(not up.is_empty() and str(up[0].body.p_items[0].content_id) == "tt099" and str(up[0].body.p_origin_client_id).begins_with("uzai-"),
			"gemerkt → im Konto (mit Uzais Kennung)")
	check(not de.is_empty() and str(de[0].body.p_keys[0].content_id) == "tt001", "entfernt → aus dem Konto")
	await _clear()
	Movies.set_watched("tt050", "tt050:1:3", true, {})
	await _settle()
	reqs = await _log()
	var wi := _calls(reqs, "sync_push_watched_items")
	check(not wi.is_empty() and int(wi[0].body.p_items[0].season) == 1 and int(wi[0].body.p_items[0].episode) == 3, "Folge gesehen → Verlauf im Konto")
	await _clear()
	Movies.set_addon_enabled(str(Movies.addons[1].id), false)
	await _settle()
	reqs = await _log()
	var pa := _calls(reqs, "sync_push_addons")
	check(not pa.is_empty() and (pa[0].body.p_addons as Array).size() == 2, "Addon ausgeschaltet → ganze Liste ins Konto")
	if not pa.is_empty():
		check(str(pa[0].body.p_addons[0].url) == base + "/addon/a1" and not bool(pa[0].body.p_addons[1].enabled),
				"mit Nuvios ursprünglichen Adressen, Schalter übernommen")
	check(NuvioSync.pending_count() == 0, "nichts bleibt liegen")
	# Kaputte Einträge in der gemerkten Schlange (Datei von Hand geändert, halb geschrieben) verstopften sie früher für
	# immer: Der erste brach das Senden mit einem Fehler ab, und _flushing blieb bis zum Neustart stehen.
	NuvioSync.sput("pending", ["kaputt", { "rpc": "" }, 7])
	await NuvioSync.flush_pending()
	check(NuvioSync.pending_count() == 0 and not NuvioSync._flushing, "kaputte Einträge in der Schlange fliegen raus, die Schlange bleibt benutzbar")

	print("Erneut abgleichen (nur Änderungen)")
	await _clear()
	var t0 := Time.get_ticks_msec()
	var err := await NuvioSync.sync(true)
	check(err == "", "zweiter Abgleich ok (%d ms)" % (Time.get_ticks_msec() - t0))
	check(Movies.addons.size() == 2 and bool(Movies.addons[1].enabled), "Addons wieder wie im Konto (Konto gewinnt)")
	check(Movies.watched("tt050", "tt050:1:3"), "eigene „Gesehen“-Markierung bleibt (das Neuere gewinnt)")
	reqs = await _log()
	check(_calls(reqs, "sync_push_library_items").is_empty(), "beim zweiten Mal nichts doppelt hochgeladen")
	check(_calls(reqs, "sync_pull_library").is_empty() and _calls(reqs, "sync_pull_watched_items").is_empty(),
			"keine ganzen Listen mehr: weder Bibliothek noch Verlauf komplett")
	check(not _calls(reqs, "sync_pull_library_delta").is_empty() and int(_calls(reqs, "sync_pull_library_delta")[0].body.p_since_event_id) == 100,
			"nur Änderungen seit dem Cursor")
	# Auf einem anderen Gerät: Titel gemerkt, aus Weiterschauen entfernt, Folge gesehen.
	await Net.get_json(
			base + "/__event?kind=lib&json=" + JSON.stringify({ "operation": "upsert", "content_id": "tt077", "content_type": "movie", "name": "Neu im Konto",
			"added_at": 1800000200000 }).uri_encode())
	await Net.get_json(
			base + "/__event?kind=progress&json=" + JSON.stringify({ "operation": "delete", "content_id": "tt002", "content_type": "movie", "video_id": "tt002",
			"season": null, "episode": null, "position": 0, "duration": 0, "last_watched": 1900000000000 }).uri_encode())
	await Net.get_json(
			base + "/__event?kind=watched&json=" + JSON.stringify({ "operation": "upsert", "content_id": "tt050", "content_type": "series", "title": "S1E2", "season": 1,
			"episode": 2, "watched_at": 1900000000000 }).uri_encode())
	await _clear()
	err = await NuvioSync.sync(true)
	check(err == "", "Abgleich mit Änderungen ok")
	check(Movies.in_library("tt077"), "neu gemerkter Titel ist da")
	check(not Movies.continue_watching().any(func(c): return str(c.id) == "tt002" and not bool(c.get("next_up", false))),
			"in Nuvio aus Weiterschauen entfernt: hier auch weg")
	check(Movies.watched("tt050", "tt050:1:2"), "auf anderem Gerät gesehene Folge: gesehen")
	reqs = await _log()
	check(int(_calls(reqs, "sync_pull_library_delta")[0].body.p_since_event_id) == 100, "Cursor danach weitergezählt")
	await _clear()
	await NuvioSync.sync(true)
	reqs = await _log()
	check(int(_calls(reqs, "sync_pull_library_delta")[0].body.p_since_event_id) == 101, "nächster Abgleich ab dem neuen Cursor")

	print("Profil wechseln")
	await _clear()
	NuvioSync.set_profile(2)
	await NuvioSync.synced
	reqs = await _log()
	var ag: Array = reqs.filter(func(e): return str(e.p) == "/rest/v1/addons")
	check(not ag.is_empty() and str(ag[0].q).contains("profile_id=eq.1"), "Profil 2 teilt die Addons von Profil 1")
	var lp := _calls(reqs, "sync_pull_library")
	check(not lp.is_empty() and int(lp[0].body.p_profile_id) == 2, "Bibliothek von Profil 2")
	NuvioSync.set_profile(1)
	await NuvioSync.synced

	print("Abmelden, E-Mail/Passwort")
	await NuvioSync.logout()
	check(not NuvioSync.connected() and NuvioSync.layout().is_empty(), "abgemeldet, Layout aus")
	check(Movies.library_items().size() >= 1, "Daten bleiben in Uzai")
	var bad := await NuvioSync.login_password("lea@example.com", "falsch")
	check(bad == "E-Mail oder Passwort stimmt nicht.", "falsches Passwort: verständliche Meldung")
	var good := await NuvioSync.login_password("lea@example.com", "geheim")
	check(good == "" and NuvioSync.connected(), "mit E-Mail und Passwort angemeldet")
	if NuvioSync.busy:
		await NuvioSync.synced
	print("Erster Abgleich, das Hochladen scheitert")
	# Beim ersten Abgleich schreibt Uzai seine Bibliothek ins Konto und übernimmt danach, was im Konto steht. Scheiterte
	# das Hochladen, wurde trotzdem übernommen – was nur in Uzai stand, war weg.
	(Movies.data.library as Array).push_front({ "id": "tt777", "type": "movie", "name": "Nur in Uzai", "added": 1 })
	NuvioSync.sput("first_sync", true)
	await Net.get_json(base + "/__stoer?rpc=sync_push_library_items&code=503")
	await _clear()
	var fe := await NuvioSync.sync(true)
	reqs = await _log()
	check(fe != "" and Movies.in_library("tt777"), "Hochladen scheitert: Fehler gemeldet, der Eintrag aus Uzai bleibt (%s)" % fe)
	check(_calls(reqs, "sync_pull_library").is_empty() and bool(NuvioSync.sget("first_sync", false)),
			"nichts aus dem Konto übernommen, der erste Abgleich steht weiter aus")
	await Net.get_json(base + "/__stoer")
	NuvioSync.sput("first_sync", false)
	Movies.data.library = (Movies.data.library as Array).filter(func(e): return str(e.id) != "tt777")
	print("Token erneuern")
	Config.set_value("nuvio.expires", 0)
	await _clear()
	var ok := await NuvioSync.sync(true)
	reqs = await _log()
	check(ok == "" and reqs.any(func(e): return str(e.p) == "/auth/v1/token" and str(e.q) == "grant_type=refresh_token"),
			"abgelaufenes Token wird vorher erneuert")

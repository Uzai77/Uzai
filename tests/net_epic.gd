extends Node
## Netz-Probe für das Epic-Konto (inoffizielle Anmeldung wie Heroic/Legendary): spricht mit
## nachgebauten Epic-Diensten (tests/fake_epic.py) – Code tauschen, erneuern, Bibliothek mit
## Seiten, Katalog, Zwischenspeicher, Störung, abgelaufene Anmeldung, Abmelden.
## Aufruf (eigener, leerer Datenordner):
##   python3 tests/fake_epic.py 18794 &
##   UZAI_DATA=<ordner> UZAI_EPIC_API=http://127.0.0.1:18794 godot --headless --path . res://tests/net_epic.tscn

const EpicScanner := preload("res://src/library/epic_scanner.gd")
const EpicOnline := preload("res://src/library/epic_online.gd")
const GOOD := "0123456789abcdef0123456789abcdef"

var fails := 0
var base := ""
var acc: Node


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_EPIC_API")
	if base == "":
		print("UZAI_EPIC_API fehlt")
		get_tree().quit(1)
		return
	acc = Library.epic_account
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _fake(q: String) -> void:
	await Net.get_json(base + "/__set?" + q)


func _count(log: Array, m: String, prefix: String) -> int:
	return log.filter(func(e): return str(e.m) == m and str(e.p).begins_with(prefix)).size()


func _file(rel: String) -> String:
	var p := Config.path(rel)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func _run() -> void:
	print("Anmelden mit dem Code")
	check(not acc.logged_in() and acc.status_text() == "Nicht angemeldet", "ohne Anmeldung: „Nicht angemeldet“")
	check((await acc.owned_games(true)).is_empty(), "ohne Anmeldung keine Online-Spiele und keine Anfrage")
	var r: Dictionary = await acc.login_with_code("hallo")
	check(not bool(r.ok) and str(r.error).contains("authorizationCode") and (await _log()).is_empty(), "Unsinn: Hinweis, keine Anfrage an Epic")
	r = await acc.login_with_code('{"redirectUrl":"https://localhost/launcher/authorized?code=fedcba9876543210fedcba9876543210","authorizationCode":"fedcba9876543210fedcba9876543210","exchangeCode":null,"sid":null}')
	check(not bool(r.ok) and str(r.error).contains("abgelaufen") and not acc.logged_in(), "abgelaufener Code: deutsche Meldung („%s“)" % str(r.error).left(60))
	var page := '{"warning":"Do not share this code with any 3rd party service. It allows full access to your Epic account.","redirectUrl":"https://localhost/launcher/authorized?code=%s","authorizationCode":"%s","exchangeCode":null,"sid":null,"ssoV2Enabled":true}' % [GOOD, GOOD]
	r = await acc.login_with_code(page)
	check(bool(r.ok) and acc.logged_in() and acc.account_name() == "Spieler" and str(acc.state) == "bereit",
			"ganze JSON-Seite eingefügt: angemeldet als „Spieler“")
	check(str(Config.get_value("accounts.epic_refresh", "")) == "r1" and str(Config.get_value("accounts.epic_account_id", "")) == "acc1",
			"gespeichert: nur Erneuerungs-Anmeldung und Konto-ID")
	var log := await _log()
	var tok: Array = log.filter(func(e): return str(e.p) == "/account/account/api/oauth/token")
	check(tok.size() == 2 and str(tok[1].grant) == "authorization_code" and str(tok[1].token_type) == "eg1",
			"POST oauth/token mit grant_type=authorization_code, token_type=eg1")
	check(str(tok[1].auth) == "Basic " + Marshalls.utf8_to_base64("34a02cf8f4414e29b15921876da36f9a:daafbccc737745039dffe53d94fc76cf"),
			"Basic mit der öffentlichen Client-ID des Launchers")
	var settings := _file("settings.json")
	check(not settings.contains("\"a1\""), "Zugangs-Anmeldung nicht in settings.json")

	print("Bibliothek und Katalog")
	var games: Array = await acc.owned_games(true)
	log = await _log()
	var apps: Array = games.map(func(g): return str(g.epic.app))
	apps.sort()
	check(apps == ["Apex", "Kinglet", "NoAppGame"],
			"nur Spiele: ohne Zusatzinhalt, Engine (ue), Werkzeug, Mac-Spiel, leere ID (%s)" % ", ".join(PackedStringArray(apps)))
	check(_count(log, "GET", "/library/library/api/public/items") == 2 and log.any(func(e): return str(e.q).contains("cursor=c2")), "zwei Seiten über nextCursor")
	check(log.filter(func(e): return str(e.p).begins_with("/library") and str(e.auth) == "Bearer a1").size() == 2,
			"Bibliothek mit Bearer (ohne Erneuern, Anmeldung noch frisch)")
	check(not log.any(func(e): return str(e.p).contains("/namespace/ue/")), "Engine-Namespace „ue“ wird gar nicht erst abgefragt")
	var apex_q: Array = log.filter(func(e): return str(e.p).contains("/namespace/ns-apex/bulk/items"))
	check(apex_q.size() == 1 and str(apex_q[0].q).contains("id=item-apex&id=item-apex-dlc") and str(apex_q[0].q).contains("locale=de"),
			"Katalog gebündelt je Namespace (%d Anfrage)" % apex_q.size())
	var by := {}
	for g in games:
		by[str(g.epic.app)] = g
	var apex: Dictionary = by.get("Apex", {})
	check(str(apex.get("id", "")) == "epic:Apex" and str(apex.get("title", "")) == "Apex Legends" and not bool(apex.get("installed", true)),
			"Titel ohne ™, ID epic:<App>, nicht installiert")
	check(str(apex.epic.namespace) == "ns-apex" and str(apex.epic.item) == "item-apex"
			and EpicScanner.install_uri(apex).ends_with("ns-apex%3Aitem-apex%3AApex?action=install"), "Installieren über den Launcher-Link")
	check(str((apex.get("art", {}) as Dictionary).get("cover", "")).begins_with("https://cdn1.epicgames.com/apex/tall.jpg"), "Cover aus dem Katalog")
	check(str((by.get("NoAppGame", {}) as Dictionary).get("title", "")) == "Ohne App-Namen", "App-Name aus der Bibliothek, wenn der Katalog keinen hat")
	var cache := _file("epic_konto.json")
	check(cache.contains("item-apex") and not cache.contains("Screenshot") and not cache.contains("lang lang"),
			"Zwischenspeicher schlank (nur nötige Bilder, kein Text)")
	check(not cache.contains("\"a1\"") and not cache.contains("\"r1\""), "keine Anmeldedaten im Zwischenspeicher")
	check(acc.owned_count() == 3 and acc.status_text() == "Spieler · 3 Spiele", "Zustand für die Einstellungen: „%s“" % acc.status_text())

	print("Zwischenspeicher und Erneuern")
	var n := (await _log()).size()
	games = await acc.owned_games(false)
	check(games.size() == 3 and (await _log()).size() == n, "frisch: aus dem Zwischenspeicher, keine Anfrage")
	acc._access_until = 0
	var ok: bool = await acc.sync()
	log = await _log()
	var last: Array = log.slice(n)
	check(ok and last.any(func(e): return str(e.grant) == "refresh_token") and str(Config.get_value("accounts.epic_refresh", "")) == "r2",
			"abgelaufene Zugangs-Anmeldung: von selbst erneuert, neue Erneuerungs-Anmeldung gespeichert")
	check(not last.any(func(e): return str(e.p).contains("/bulk/items") and not str(e.p).contains("/unbekannt/")),
			"Katalog nur für Neues (bekannte Einträge nicht noch mal)")
	check(last.filter(func(e): return str(e.p).begins_with("/library")).all(func(e): return str(e.auth) == "Bearer a2"), "danach mit der neuen Zugangs-Anmeldung")

	print("Zusammenführen in der Bibliothek")
	var inst := { "id": "epic:Kinglet", "title": "Alan Wake 2", "system": "epic", "source": "epic", "installed": true,
		"install_dir": "C:/Games/AW2", "path": "C:/Games/AW2/aw2.exe", "epic": { "namespace": "ns-kinglet", "item": "item-kinglet", "app": "Kinglet" } }
	var catcache := { "id": "epic:Apex", "title": "Apex Legends", "system": "epic", "source": "epic", "installed": false,
		"install_dir": "", "path": "", "epic": { "namespace": "ns-apex", "item": "item-apex", "app": "Apex" } }
	var all := EpicOnline.combine([inst, catcache], games)
	var ids: Array = all.map(func(g): return str(g.id))
	check(ids == ["epic:Kinglet", "epic:Apex", "epic:NoAppGame"], "installiert + Katalogdatei + Konto ohne Doppelte (%s)" % ", ".join(PackedStringArray(ids)))
	check(str((all[0].get("art", {}) as Dictionary).get("cover", "")).contains("aw2/tall.jpg")
			and str((all[1].get("art", {}) as Dictionary).get("cover", "")).contains("apex/tall.jpg"), "Bilder aus dem Konto für installierte und Katalogdatei-Spiele")
	var list: Array = await Library._scan_epic(false)
	Library._merge(list, ["epic"])
	check(Library.epic_online == 3 and not Library.get_game("epic:Apex").is_empty() and Library.owned_only(Library.get_game("epic:Apex")),
			"Einlesen: Konto-Spiele kommen als gekauft in die Bibliothek")
	check(Library.is_visible(Library.get_game("epic:NoAppGame")), "… und sind sichtbar")
	var blog := _file("logs/bibliothek.log")
	check(blog.contains("Epic-Konto") and not blog.contains("r1") and not blog.contains("r2") and not blog.contains("a2") and not blog.contains(GOOD),
			"Protokoll ohne Codes und Anmeldedaten")

	print("Epic gestört: still weiter mit dem Bekannten")
	await _fake("down=1")
	ok = await acc.sync()
	games = await acc.owned_games(true)
	check(not ok and games.size() == 3 and str(acc.state) == "fehler" and str(acc.last_error).contains("Störung"),
			"503: letzte Liste bleibt, Meldung „%s“" % str(acc.last_error).left(50))
	list = await Library._scan_epic(true)
	check(list.size() == 3, "Einlesen klappt trotzdem (%d)" % list.size())
	await _fake("down=0")
	ok = await acc.sync()
	check(ok and str(acc.state) == "bereit" and str(acc.last_error) == "", "wieder erreichbar: wieder bereit")

	print("Zwei Abrufe zugleich")
	n = (await _log()).size()
	acc._access_until = 0
	var paar := ["", ""]
	var holen := func(i: int) -> void: paar[i] = await acc.access_token()
	holen.call(0)
	holen.call(1)
	for i in 100:
		if paar[0] != "" and paar[1] != "":
			break
		await get_tree().create_timer(0.05).timeout
	log = (await _log()).slice(n)
	check(paar[0] == "a3" and paar[1] == "a3" and log.filter(func(e): return str(e.grant) == "refresh_token").size() == 1
			and str(Config.get_value("accounts.epic_refresh", "")) == "r3",
			"abgelaufener Zugang, zwei Abrufe zugleich: nur ein Erneuern, beide bekommen den neuen Zugang (%s, %s)" % [paar[0], paar[1]])

	print("Anmeldung abgelaufen")
	await _fake("dead=1")
	acc._access_until = 0
	ok = await acc.sync()
	check(not ok and str(acc.state) == "abgelaufen" and not acc.logged_in() and acc.account_name() == "Spieler",
			"Erneuern abgelehnt: abgelaufen, Name bleibt für den Hinweis")
	check(str(acc.last_error).contains("neu anmelden") and acc.status_text().contains("Abgelaufen"), "Hinweis: neu anmelden")
	check((await acc.owned_games(false)).size() == 3, "zuletzt bekannte Spiele bleiben sichtbar")
	await _fake("dead=0")

	print("Abmelden")
	r = await acc.login_with_code(GOOD)
	check(bool(r.ok) and acc.logged_in(), "nur der Code (32 Zeichen): wieder angemeldet")
	n = (await _log()).size()
	acc.logout()
	await get_tree().create_timer(0.5).timeout
	log = (await _log()).slice(n)
	check(log.any(func(e): return str(e.m) == "DELETE" and str(e.p) == "/account/account/api/oauth/sessions/kill/a1"), "Epic bekommt Bescheid (Sitzung beendet)")
	check(not acc.logged_in() and acc.account_name() == "" and str(Config.get_value("accounts.epic_account_id", "")) == "" and str(acc.state) == "aus",
			"Anmeldung vergessen")
	check(not FileAccess.file_exists(Config.path("epic_konto.json")) and (await acc.owned_games(true)).is_empty(), "Liste vergessen")
	list = await Library._scan_epic(false)
	Library._merge(list, ["epic"])
	check(Library.epic_online == -1 and bool(Library.get_game("epic:Apex").get("missing", false)), "nach dem Abmelden verschwinden die Konto-Spiele")

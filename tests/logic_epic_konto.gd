extends Node
## Epic-Konto (inoffizielle Anmeldung wie Heroic/Legendary) ohne Netz: Code aus dem Eingefügten,
## Antworten des Anmelde-, Bibliotheks- und Katalogdienstes, deutsche Fehler, Zusammenführen mit
## installierten und catcache-Spielen, Handy-Seite mit dem Link zu Epic.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_epic_konto.tscn → „Ergebnis: alles ok“
## Den Ablauf mit Netz prüft tests/net_epic.gd gegen tests/fake_epic.py.

const Epic := preload("res://src/library/epic_scanner.gd")
const On := preload("res://src/library/epic_online.gd")
const CODE := "0123456789abcdef0123456789abcdef"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Code aus dem Eingefügten")
	_code()
	print("Anmeldung lesen")
	_token()
	print("Fehler auf Deutsch")
	_errors()
	print("Bibliothek (Seiten)")
	_library()
	print("Katalog (bulk)")
	_bulk()
	print("Gekaufte Spiele und Zusammenführen")
	_games()
	print("Anmeldeseite und Handy-Eingabe")
	_login_page()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _code() -> void:
	check(str(On.extract_code(CODE).code) == CODE, "nur der Code (32 Hex-Zeichen)")
	check(str(On.extract_code("  " + CODE.to_upper() + "\n").code) == CODE, "mit Leerzeichen, groß geschrieben")
	var page := '{"warning":"Do not share this code with any 3rd party service.","redirectUrl":"https://localhost/launcher/authorized?code=%s","authorizationCode":"%s","exchangeCode":null,"sid":null,"ssoV2Enabled":true}' % [CODE, CODE]
	check(str(On.extract_code(page).code) == CODE, "ganze JSON-Seite von Epic")
	check(str(On.extract_code("Kopiert: " + page + " …").code) == CODE, "JSON mit Text drumherum (Handy kopiert mehr mit)")
	var nul := On.extract_code('{"redirectUrl":"https://www.epicgames.com/id/login","authorizationCode":null,"exchangeCode":null,"sid":null}')
	check(str(nul.code) == "" and str(nul.error).contains("null"), "noch nicht angemeldet (authorizationCode: null): Hinweis")
	check(str(On.extract_code("https://localhost/launcher/authorized?code=" + CODE).code) == CODE, "Adresse mit code=…")
	check(str(On.extract_code(On.LOGIN_URL).code) == "", "die Client-ID in der Anmeldeadresse ist kein Code")
	check(str(On.extract_code(On.LOGIN_URL + " " + CODE).code) == CODE, "… daneben der echte Code wird gefunden")
	check(str(On.extract_code(CODE + "0").code) == "" and str(On.extract_code("123").code) == "", "zu lang oder zu kurz: kein Code")
	check(str(On.extract_code("").error) != "" and str(On.extract_code("hallo").error).contains("authorizationCode"), "Unsinn: deutscher Hinweis")


func _token() -> void:
	var t := On.parse_token(200, { "access_token": "acc", "expires_in": 28800, "refresh_token": "ref", "refresh_expires": 1987200,
		"account_id": "id1", "displayName": "Spieler", "token_type": "bearer" }, 1000)
	check(bool(t.ok) and str(t.access) == "acc" and str(t.refresh) == "ref" and int(t.expires_at) == 29800 and int(t.refresh_expires_at) == 1988200,
			"Zugang, Erneuerung, Ablaufzeiten")
	check(str(t.account_id) == "id1" and str(t.name) == "Spieler", "Konto-ID und Anzeigename")
	check(not bool(On.parse_token(200, { "access_token": "acc" }, 0).ok), "ohne Erneuerungs-Anmeldung: nicht ok")
	check(not bool(On.parse_token(200, null, 0).ok) and not bool(On.parse_token(200, [], 0).ok), "kaputte Antwort: nicht ok")
	var bad := On.parse_token(400, { "errorCode": "errors.com.epicgames.account.auth_token.invalid_refresh_token" }, 0)
	check(not bool(bad.ok) and bool(bad.expired) and str(bad.error).contains("neu anmelden"), "ungültige Erneuerung: abgelaufen")
	var used := On.parse_token(400, { "errorCode": "errors.com.epicgames.account.oauth.authorization_code_not_found" }, 0)
	check(not bool(used.expired) and str(used.error).contains("abgelaufen oder wurde schon benutzt"), "Code schon benutzt")
	check(On.basic_auth() == "Authorization: Basic " + Marshalls.utf8_to_base64("34a02cf8f4414e29b15921876da36f9a:daafbccc737745039dffe53d94fc76cf"),
			"Basic mit der öffentlichen Launcher-Client-ID")


func _errors() -> void:
	check(str(On.error_info(0, null).error).contains("nicht erreichbar"), "kein Netz")
	check(str(On.error_info(429, null).error).contains("bremst"), "429: zu viele Anfragen")
	check(str(On.error_info(503, null).error).contains("Störung"), "5xx: Störung")
	check(bool(On.error_info(401, null).expired), "401: neu anmelden")
	var e := On.error_info(403, { "errorCode": "errors.com.epicgames.common.missing_permission" })
	check(not str(e.error).contains("403") and not str(e.error).contains("missing_permission") and str(e.error).contains("Launcher")
			and str(e.epic_code).contains("missing_permission"), "anderes: Hinweis auf den Rückfall, Code nur fürs Protokoll („%s“)" % str(e.error).left(50))
	check(str(On.error_info(400, { "errorCode": "errors.com.epicgames.oauth.corrective_action_required" }).error).contains("bestätigst"),
			"Epic will eine Bestätigung im Browser")


func _library() -> void:
	var p := On.parse_library_page({ "responseMetadata": { "nextCursor": "abc", "stateToken": "s" }, "records": [
		{ "namespace": "ns1", "catalogItemId": "i1", "appName": "A1", "recordType": "APPLICATION" },
		{ "namespace": "ue", "catalogItemId": "i2", "appName": "UE_5" },
		{ "namespace": "ns3", "catalogItemId": "", "appName": "Leer" },
		{ "namespace": "ns4", "catalogItemId": "i4", "appName": null },
		"kaputt",
	] })
	check(bool(p.ok) and str(p.cursor) == "abc", "Seite mit nächstem Cursor")
	check((p.records as Array).size() == 2 and str(p.records[0].app) == "A1" and str(p.records[1].app) == "",
			"ohne Engine (ue), ohne leere ID, App-Name null → leer")
	check(str(On.parse_library_page({ "responseMetadata": {}, "records": [] }).cursor) == "", "letzte Seite: kein Cursor")
	check(str(On.parse_library_page({ "responseMetadata": { "nextCursor": null }, "records": [] }).cursor) == "", "nextCursor null: letzte Seite")
	check(not bool(On.parse_library_page({ "items": [] }).ok) and not bool(On.parse_library_page(null).ok), "andere Form (Epic hat etwas geändert): nicht ok")
	var miss := On.missing_items(
			[{ "namespace": "a", "item": "1" }, { "namespace": "a", "item": "2" }, { "namespace": "b", "item": "3" }, { "namespace": "a", "item": "1" }], { "2": {} })
	check(miss == { "a": ["1"], "b": ["3"] }, "fehlender Katalog je Namespace, ohne Doppelte: " + str(miss))
	var u := On.bulk_url("https://h", "n s", ["x", "y"])
	check(u == "https://h/catalog/api/shared/namespace/n%20s/bulk/items?id=x&id=y&includeDLCDetails=true&includeMainGameDetails=true&country=DE&locale=de",
			"Katalog-Adresse: " + u)


func _bulk() -> void:
	var data := {
		"g1": { "id": "g1", "namespace": "ns1", "title": "Spiel", "description": "lang", "categories": [{ "path": "games" }, { "path": "applications" }],
			"releaseInfo": [{ "id": "r", "appId": "App1", "platform": ["Windows", "Mac"], "dateAdded": "x" }],
			"keyImages": [{ "type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/t.jpg", "md5": "m" },
				{ "type": "Screenshot", "url": "https://cdn1.epicgames.com/s.jpg" }] },
		"d1": { "id": "d1", "namespace": "ns1", "title": "DLC", "categories": [{ "path": "addons" }],
			"mainGameItem": { "id": "g1", "namespace": "ns1", "title": "Spiel" } },
		"x": "kaputt",
	}
	var items := On.parse_bulk(data)
	check(items.size() == 2, "Einträge gelesen, kaputte übersprungen")
	var g: Dictionary = items.filter(func(i): return str(i.id) == "g1")[0]
	check(not g.has("description") and (g.keyImages as Array).size() == 1 and str(g.releaseInfo[0].appId) == "App1", "schlank: nur nötige Bilder und Felder")
	var d: Dictionary = items.filter(func(i): return str(i.id) == "d1")[0]
	check(str(d.mainGameItem.id) == "g1" and not d.mainGameItem.has("title"), "Zusatzinhalt behält seinen Verweis aufs Hauptspiel")
	check(On.parse_bulk(null).is_empty() and On.parse_bulk([]).is_empty(), "keine Antwort: leer")


func _cat() -> Dictionary:
	var c := {}
	for it in [
		{ "id": "i-apex", "namespace": "ns-apex", "title": "Apex Legends™", "categories": [{ "path": "games" }],
			"releaseInfo": [{ "appId": "Apex", "platform": ["Windows"] }],
				"keyImages": [{ "type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/apex.jpg" }] },
		{ "id": "i-dlc", "namespace": "ns-apex", "title": "Paket", "categories": [{ "path": "addons" }], "mainGameItem": { "id": "i-apex" },
			"releaseInfo": [{ "appId": "ApexDlc" }], "keyImages": [] },
		{ "id": "i-ue", "namespace": "ns-ue", "title": "Unreal Engine", "categories": [{ "path": "engines" }], "releaseInfo": [{ "appId": "UE_5" }],
			"keyImages": [] },
		{ "id": "i-plugin", "namespace": "ns-p", "title": "Plugin", "categories": [{ "path": "plugins" }], "releaseInfo": [{ "appId": "Plug" }], "keyImages": [] },
		{ "id": "i-aw2", "namespace": "ns-aw2", "title": "Alan Wake 2", "categories": [{ "path": "games" }], "releaseInfo": [{ "appId": "Kinglet" }],
			"keyImages": [{ "type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/aw2.jpg" }] },
		{ "id": "i-noapp", "namespace": "", "title": "Ohne App", "categories": [{ "path": "games" }], "releaseInfo": [], "keyImages": [] },
		{ "id": "i-ctrl", "namespace": "ns-ctrl", "title": "Control", "categories": [{ "path": "games" }], "releaseInfo": [{ "appId": "Control" }], "keyImages": [] },
	]:
		c[str(it.id)] = it
	return c


func _games() -> void:
	var recs := [
		{ "namespace": "ns-apex", "item": "i-apex", "app": "Apex" }, { "namespace": "ns-apex", "item": "i-dlc", "app": "ApexDlc" },
		{ "namespace": "ns-ue", "item": "i-ue", "app": "UE_5" }, { "namespace": "ns-p", "item": "i-plugin", "app": "Plug" },
		{ "namespace": "ns-aw2", "item": "i-aw2", "app": "Kinglet" }, { "namespace": "ns-noapp", "item": "i-noapp", "app": "NoApp" },
		{ "namespace": "ns-x", "item": "i-fehlt", "app": "Fehlt" }, { "namespace": "ns-ctrl", "item": "i-ctrl", "app": "Control" },
	]
	var games := On.owned_games(recs, _cat())
	var apps: Array = games.map(func(g): return str(g.epic.app))
	check(apps == ["Apex", "Kinglet", "NoApp", "Control"], "ohne DLC, Engine, Plugins und ohne Katalog (%s)" % ", ".join(PackedStringArray(apps)))
	var no: Dictionary = games[2]
	check(str(no.epic.namespace) == "ns-noapp" and str(no.id) == "epic:NoApp", "Namespace und App-Name aus der Bibliothek, wenn der Katalog sie nicht hat")
	check(str(games[0].title) == "Apex Legends" and not bool(games[0].installed) and str(games[0].source) == "epic", "gleiche Form wie aus catcache.bin")
	# Installiert: Alan Wake 2 (App-Name). Aus catcache.bin: Control mit anderem App-Namen, gleicher Katalog-ID.
	var inst := { "id": "epic:Kinglet", "title": "Alan Wake 2", "installed": true, "source": "epic",
			"epic": { "namespace": "ns-aw2", "item": "i-aw2", "app": "Kinglet" } }
	var cc := { "id": "epic:ControlAlt", "title": "Control", "installed": false, "source": "epic", "art": { "cover": "https://eigen" },
			"epic": { "namespace": "ns-ctrl", "item": "i-ctrl", "app": "ControlAlt" } }
	var all := On.combine([inst, cc], games)
	var ids: Array = all.map(func(g): return str(g.id))
	check(ids == ["epic:Kinglet", "epic:ControlAlt", "epic:Apex", "epic:NoApp"],
			"ohne Doppelte nach App-Name und Katalog-ID, lokale zuerst (%s)" % ", ".join(PackedStringArray(ids)))
	check(str(all[0].art.cover).contains("aw2.jpg") and str(all[1].art.cover) == "https://eigen",
			"installiertes bekommt das Cover aus dem Konto, vorhandene Bilder bleiben")
	check(On.combine([inst], []).size() == 1 and On.combine([], games).size() == 4, "ohne Konto bzw. ohne lokale Spiele")
	# In der Bibliothek: wie gekaufte aus catcache.bin (Installieren, Schalter, hinten im Reiter).
	Library.games = []
	Library._reindex()
	Library._merge(all, ["epic"])
	var apex := Library.get_game("epic:Apex")
	check(Library.owned_only(apex) and Epic.install_uri(apex).ends_with("ns-apex%3Ai-apex%3AApex?action=install"),
			"nicht installiert, „Installieren“ über den Launcher")
	Config.set_value("library.epic_owned", false)
	check(not Library.is_visible(apex) and Library.is_visible(Library.get_game("epic:Kinglet")), "Schalter „Nicht installierte Epic-Spiele“ gilt auch fürs Konto")
	Config.set_value("library.epic_owned", true)


func _login_page() -> void:
	check(On.LOGIN_URL == "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode", "Epics Anmeldeseite mit Weiterleitung auf die Code-Seite")
	check(not load("res://src/core/qr.gd").encode(On.LOGIN_URL, "M").is_empty(), "passt in einen QR-Code")
	var url := Remote.phone_begin("epic_test", "Code von der Epic-Seite", "Hinweis", false, On.LOGIN_URL, "192.168.1.2", "Bei Epic anmelden", "Öffnet Epic.")
	check(url.begins_with("http://192.168.1.2:"), "Handy-Eingabe gestartet")
	var token := url.get_slice("/t/", 1)
	var info: Dictionary = Remote._phone_req.get(token, {})
	check(str(info.get("link_label", "")) == "Bei Epic anmelden" and str(info.get("link", "")) == On.LOGIN_URL, "Handy-Seite mit eigenem Link „Bei Epic anmelden“")
	Remote.phone_end("epic_test")
	check(not Remote._phone_req.has(token), "Handy-Eingabe beendet")
	var acc = Library.epic_account
	check(acc != null and not acc.logged_in() and acc.status_text() == "Nicht angemeldet" and acc.owned_count() == -1,
			"Bibliothek hat das Epic-Konto, ohne Anmeldung")
	check(acc.host("account") == On.ACCOUNT_HOST or OS.get_environment("UZAI_EPIC_API") != "", "echte Epic-Adressen ohne Testumleitung")

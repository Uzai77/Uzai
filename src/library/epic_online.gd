extends RefCounted
## Epic account, pure parts (no network, no files): extract the code from the pasted text, read
## responses from Epic's login, library and catalog services, produce errors in German, and merge
## purchased games with installed ones and those from catcache.bin.
##
## Unofficial: Uzai signs in the same way as the free launchers Heroic, Legendary and Playnite -
## via Epic's own login page and with the public client ID of the Epic Games Launcher. Epic does
## not officially support this and can change it at any time; Uzai then quietly keeps showing
## installed games and those from the launcher's catalog file.
## Uzai never sees the password: you sign in on epicgames.com, then Epic shows a one-time code
## (authorizationCode) that Uzai exchanges for a session.

const EpicScanner := preload("res://src/library/epic_scanner.gd")
const Lang := preload("res://src/core/lang.gd")

## Öffentliche Zugangsdaten des Epic Games Launchers (so auch bei Legendary dokumentiert).
const CLIENT_ID := "34a02cf8f4414e29b15921876da36f9a"
const CLIENT_SECRET := "daafbccc737745039dffe53d94fc76cf"
const ACCOUNT_HOST := "https://account-public-service-prod03.ol.epicgames.com"
const LIBRARY_HOST := "https://library-service.live.use1a.on.epicgames.com"
const CATALOG_HOST := "https://catalog-public-service-prod06.ol.epicgames.com"
## Epics Anmeldeseite. Nach der Anmeldung leitet sie auf eine Seite, die den Code als JSON zeigt.
const LOGIN_URL := "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D" + CLIENT_ID + "%26responseType%3Dcode"
## Einmal-Code für den Spielstart: erlaubte Länge und größte Antwort des Dienstes.
const EXCHANGE_MIN := 16
const EXCHANGE_MAX := 64
const EXCHANGE_MAX_BYTES := 4096
## So viele Katalog-IDs fragt Uzai je Anfrage ab (eine Anfrage je Namespace).
const BULK_CHUNK := 40
## Bildarten, die Uzai aus dem Katalog behält (der Rest wäre nur Ballast im Zwischenspeicher).
const KEEP_IMAGES := ["DieselGameBoxTall", "OfferImageTall", "Thumbnail", "CodeRedemption_340x440",
	"DieselGameBox", "OfferImageWide", "DieselStoreFrontWide", "DieselGameBoxLogo"]


## Kopfzeile für die Anmeldung beim Anmeldedienst (Basic mit Client-ID und -Geheimnis).
static func basic_auth() -> String:
	return "Authorization: Basic " + Marshalls.utf8_to_base64(CLIENT_ID + ":" + CLIENT_SECRET)


## Rein: Code aus dem, was der Nutzer eingefügt hat. Erlaubt: nur der Code (32 Hex-Zeichen), die
## ganze JSON-Antwort der Epic-Seite oder eine Adresse mit „code=…“.
## Ergebnis: { code } oder { code: "", error }.
static func extract_code(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return { "code": "", "error": "Nichts angekommen. Den Code von der Epic-Seite einfügen." }
	if t.contains("{"):
		var j := JSON.new()
		var s := t.substr(t.find("{"), t.rfind("}") - t.find("{") + 1) if t.rfind("}") > t.find("{") else t
		if j.parse(s) == OK and j.data is Dictionary:
			var d: Dictionary = j.data
			if d.has("authorizationCode"):
				var c: Variant = d.get("authorizationCode")
				if c == null or str(c) == "" or str(c) == "null":
					return { "code": "",
							"error": "Auf der Epic-Seite stand noch kein Code („authorizationCode“: null). Erst bei Epic anmelden, dann die Seite neu laden und den Code kopieren." }
				if _is_code(str(c)):
					return { "code": str(c).to_lower() }
	var rx := RegEx.create_from_string("(?i)(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])")
	for m in rx.search_all(t):
		var c2 := m.get_string().to_lower()
		# Die Client-ID steht in der Adresse der Anmeldeseite – sie ist kein Code.
		if c2 != CLIENT_ID:
			return { "code": c2 }
	return { "code": "", "error": "Das sieht nicht nach einem Epic-Code aus. Gesucht ist der Wert hinter „authorizationCode“ (32 Zeichen aus Ziffern und a–f)." }


static func _is_code(s: String) -> bool:
	return RegEx.create_from_string("^[0-9a-fA-F]{32}$").search(s) != null


## Rein: Antwort von …/oauth/exchange → der Einmal-Code für den Spielstart (wie Legendary ihn als
## -AUTH_PASSWORD übergibt) oder "" bei allem, was nicht genau so aussieht. Der Code landet in der
## Befehlszeile des Spiels – darum nur Ziffern und a–f in begrenzter Länge (Epic schickt 32), nie
## Leerzeichen, Anführungszeichen, Zeilenumbrüche oder Zeichen, die eine Shell deuten könnte.
static func parse_exchange(code: int, data: Variant) -> String:
	if code < 200 or code >= 300 or not (data is Dictionary):
		return ""
	var c: Variant = (data as Dictionary).get("code")
	if not (c is String) or not exchange_ok(c):
		return ""
	return c


## Rein: sieht das wie ein Einmal-Code aus? Zeichen für Zeichen geprüft (ein regulärer Ausdruck
## mit „$“ ließe einen Zeilenumbruch am Ende durch).
static func exchange_ok(s: String) -> bool:
	if s.length() < EXCHANGE_MIN or s.length() > EXCHANGE_MAX:
		return false
	for ch in s:
		if not ch in "0123456789abcdef":
			return false
	return true


## Rein: Antwort des Anmeldedienstes (Code oder Erneuerung) → { ok, access, refresh, expires_at,
## refresh_expires_at, account_id, name } bzw. { ok: false, error, expired }.
static func parse_token(code: int, data: Variant, now: int) -> Dictionary:
	if code >= 200 and code < 300 and data is Dictionary and str(data.get("access_token", "")) != "" and str(data.get("refresh_token", "")) != "":
		var d: Dictionary = data
		return {
			"ok": true,
			"access": str(d.access_token),
			"refresh": str(d.refresh_token),
			"expires_at": now + int(d.get("expires_in", 7200)),
			"refresh_expires_at": now + int(d.get("refresh_expires", 0)) if int(d.get("refresh_expires", 0)) > 0 else 0,
			"account_id": str(d.get("account_id", "")),
			"name": str(d.get("displayName", "")),
		}
	var e := error_info(code, data)
	e["ok"] = false
	return e


## Rein: Fehler einer Epic-Antwort → { error (Deutsch), expired (Anmeldung nicht mehr gültig),
## epic_code (Epics Fehlername, fürs Protokoll) }.
static func error_info(code: int, data: Variant) -> Dictionary:
	var ec := ""
	if data is Dictionary:
		ec = str((data as Dictionary).get("errorCode", (data as Dictionary).get("error", "")))
	var out := { "error": "", "expired": false, "epic_code": ec }
	if code == 0:
		out.error = "Epic ist gerade nicht erreichbar. Internetverbindung prüfen und nochmal versuchen."
	elif ec.ends_with("authorization_code_not_found") or ec.ends_with("invalid_authorization_code") or ec.ends_with("authorization_code_expired"):
		out.error = "Der Code ist abgelaufen oder wurde schon benutzt (er gilt nur ein paar Minuten). Die Epic-Seite neu laden und den neuen Code nehmen."
	elif ec.ends_with("invalid_refresh_token") or ec.ends_with("refresh_token_expired") or ec == "invalid_grant":
		out.error = "Die Anmeldung bei Epic ist abgelaufen. Bitte neu anmelden (Einstellungen → Konten → Epic Games)."
		out.expired = true
	elif ec.contains("corrective_action_required"):
		out.error = "Epic möchte, dass du erst im Browser etwas bestätigst (z. B. neue Nutzungsbedingungen). Einmal auf epicgames.com anmelden, dann nochmal versuchen."
	elif ec.contains("account_not_active") or ec.contains("account.banned") or ec.contains("account_locked"):
		out.error = "Epic meldet das Konto als gesperrt oder nicht aktiv."
	elif code == 401:
		out.error = "Epic hat die Anmeldung nicht angenommen. Bitte neu anmelden."
		out.expired = true
	elif code == 429:
		out.error = "Epic bremst gerade (zu viele Anfragen). In ein paar Minuten nochmal versuchen."
	elif code >= 500:
		out.error = "Epic hat gerade eine Störung. Später nochmal versuchen."
	else:
		out.error = "Epic hat die Anfrage abgelehnt. Die Spiele aus dem Launcher bleiben."
	return out


## Rein: eine Seite der Bibliothek (library/api/public/items) → { ok, records, cursor }.
## records: [{ namespace, item, app }] – ohne Unreal-Engine-Inhalte (Namespace „ue“) und ohne
## Einträge ohne Katalog-ID. cursor: "" auf der letzten Seite.
static func parse_library_page(data: Variant) -> Dictionary:
	if not (data is Dictionary) or not ((data as Dictionary).get("records") is Array):
		return { "ok": false, "records": [], "cursor": "" }
	var out: Array = []
	for r in data.records:
		if not (r is Dictionary):
			continue
		var ns := str(r.get("namespace", ""))
		var item := str(r.get("catalogItemId", ""))
		if ns == "" or item == "" or ns == "ue":
			continue
		out.append({ "namespace": ns, "item": item, "app": str(r.get("appName", "")) if r.get("appName") != null else "" })
	var cursor := ""
	var meta: Variant = data.get("responseMetadata")
	if meta is Dictionary and meta.get("nextCursor") != null:
		cursor = str(meta.get("nextCursor", ""))
	return { "ok": true, "records": out, "cursor": cursor }


## Rein: Antwort von …/bulk/items (Katalog-ID → Eintrag) → Liste schlanker Einträge.
static func parse_bulk(data: Variant) -> Array:
	var out: Array = []
	if not (data is Dictionary):
		return out
	for k in data.keys():
		var it: Variant = data[k]
		if it is Dictionary and str(it.get("id", "")) != "":
			out.append(slim_item(it))
	return out


## Rein: Katalogeintrag auf das kürzen, was Uzai braucht (gleiche Form wie in catcache.bin).
static func slim_item(it: Dictionary) -> Dictionary:
	var cats: Array = []
	var cv: Variant = it.get("categories", [])
	if cv is Array:
		for c in cv:
			if c is Dictionary:
				cats.append({ "path": str(c.get("path", "")) })
			elif c is String:
				cats.append({ "path": c })
	var rel: Array = []
	var rv: Variant = it.get("releaseInfo", [])
	if rv is Array:
		for r in rv:
			if r is Dictionary and str(r.get("appId", "")) != "":
				var pf: Variant = r.get("platform", [])
				rel.append({ "appId": str(r.appId), "platform": pf if pf is Array else [] })
	var imgs: Array = []
	var iv: Variant = it.get("keyImages", [])
	if iv is Array:
		for k in iv:
			if k is Dictionary and str(k.get("type", "")) in KEEP_IMAGES:
				imgs.append({ "type": str(k.type), "url": str(k.get("url", "")) })
	var out := { "id": str(it.get("id", "")), "namespace": str(it.get("namespace", "")), "title": str(it.get("title", "")),
		"categories": cats, "releaseInfo": rel, "keyImages": imgs }
	var mg: Variant = it.get("mainGameItem")
	if mg is Dictionary and str(mg.get("id", "")) != "":
		out["mainGameItem"] = { "id": str(mg.id) }
	var mgl: Variant = it.get("mainGameItemList")
	if mgl is Array and not (mgl as Array).is_empty():
		out["mainGameItemList"] = [{}]
	return out


## Rein: Bibliothekseinträge, zu denen der Katalog noch fehlt → { Namespace: [Katalog-IDs] }.
static func missing_items(records: Array, catalog: Dictionary) -> Dictionary:
	var out := {}
	for r in records:
		var id := str(r.get("item", ""))
		if id == "" or catalog.has(id):
			continue
		var ns := str(r.get("namespace", ""))
		if not out.has(ns):
			out[ns] = []
		if not (id in out[ns]):
			(out[ns] as Array).append(id)
	return out


## Adresse für den Katalog: bis zu BULK_CHUNK IDs aus einem Namespace.
static func bulk_url(host: String, ns: String, ids: Array) -> String:
	var q := PackedStringArray()
	for id in ids:
		q.append("id=" + str(id).uri_encode())
	return "%s/catalog/api/shared/namespace/%s/bulk/items?%s&includeDLCDetails=true&includeMainGameDetails=true&country=%s&locale=%s" % [
		host, ns.uri_encode(), "&".join(q), Config.land(), Lang.api("epic")]


## Rein: gekaufte Einträge + Katalog → Spiele (nicht installiert), gefiltert wie bei catcache.bin
## (ohne Zusatzinhalte, Engine, Werkzeuge, Programme). Fehlt im Katalog der App-Name, nimmt Uzai
## den aus der Bibliothek.
static func owned_games(records: Array, catalog: Dictionary) -> Array:
	var items: Array = []
	for r in records:
		var it: Variant = catalog.get(str(r.get("item", "")))
		if not (it is Dictionary):
			continue
		var c: Dictionary = (it as Dictionary).duplicate(true)
		if str(c.get("namespace", "")) == "":
			c["namespace"] = str(r.get("namespace", ""))
		var rel: Variant = c.get("releaseInfo", [])
		if (not (rel is Array) or (rel as Array).is_empty()) and str(r.get("app", "")) != "":
			c["releaseInfo"] = [{ "appId": str(r.app) }]
		items.append(c)
	return EpicScanner.parse_catalog(items)


## Rein: lokal gefundene (installierte und aus catcache.bin) + online gekaufte → eine Liste ohne
## Doppelte (gleicher App-Name oder gleiche Katalog-ID). Installierte bleiben vorn; fehlen ihnen
## Bilder, kommen sie aus dem Konto.
static func combine(local: Array, online: Array) -> Array:
	return local + EpicScanner.dedupe(local, online)

extends Node
## Filme-Quellen (Roadmap 35): Woher Filme und Serien kommen – Addons (wie bisher, mit Nuvio-Konto),
## der eigene Plex-, Jellyfin- oder Emby-Server und das Stremio-Konto. Mehrere gleichzeitig:
## Jede Quelle bringt eigene Reihen auf die Startseite, Weiterschauen wird gemischt. Die
## Oberfläche bleibt dieselbe – Movies fragt hier nach, sobald eine Kennung einer Quelle gehört
## („plex:…“, „jf:…“, „emby:…“) oder ein Katalog „quelle:…“ heißt.
##
## Anmeldungen gehören dem Uzai-Profil (settings.json im Profilordner) und liegen im Tresor
## (Vault.SECRETS): nur Zugangsschlüssel, nie Passwörter, nie in Logs. Bedrohungen und Abwehr:
## - feindliche Antworten: strenges JSON mit Größengrenze, jeder Wert geprüft (medienquellen_*.gd)
## - Schlüssel bei Fremden: Anfragen mit Schlüssel folgen keiner Weiterleitung; Bilder und
##   Dateien nur vom gewählten Server (Plex: dazu *.plex.tv), Adressen selbst gebaut
## - unverschlüsselt: http nur zu privaten Adressen im Heimnetz und nach deinem Ja
## - Heimnetz-Suche: nur auf Wunsch, ein ausgehender Rundruf, 2,5 s, Antworten streng geprüft
## - keine eigenen Server, keine offenen Ports, keine Telemetrie (R6)

const B := preload("res://src/core/medienquellen_basis.gd")
const Plex := preload("res://src/core/medienquellen_plex.gd")
const Jf := preload("res://src/core/medienquellen_jellyfin.gd")
const St := preload("res://src/core/medienquellen_stremio.gd")
const DemoData := preload("res://src/core/medienquellen_demo.gd")
const MoviesScript := preload("res://src/core/movies.gd")
const Konten := preload("res://src/core/konten.gd")
const Sicher := preload("res://src/core/sicher.gd")

const KINDS := ["addons", "plex", "jellyfin", "emby", "stremio"]
const NAMES := { "addons": "Addons", "plex": "Plex", "jellyfin": "Jellyfin", "emby": "Emby", "stremio": "Stremio-Konto" }
const MAX_AGE := 600.0             ## so lange gelten geladene Reihen
const WAIT := 4.0                  ## so lange wartet die Startseite beim ersten Mal
const TIMEOUT := 12.0
const REPORT_EVERY := 10000        ## Fortschritt höchstens alle 10 s an den Server
const DISCOVERY_MS := 2500
const LIBS_MAX := 8

## Verbindung, Auswahl oder Daten einer Quelle haben sich geändert.
signal changed
## Reihen einer Quelle sind (neu) da – die Startseite holt sie.
signal rows_ready

var demo := false
var _slots := {}                   ## Art → { at, rows, cw, libs, err, loading, gen, genres }
var _session := {}                 ## laufende Wiedergabe von einem Server
var _st_raw := {}                  ## Stremio: Eintrag wie geschickt, je Kennung (zum Zurückschreiben)
var _demo := {}


func _ready() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		demo = true
		_demo = DemoData.build(int(Time.get_unix_time_from_system()))
		DemoData.paint_art()
		return
	_register_origins()
	Movies.local_change.connect(_on_local_change)


# --- Auswahl ---------------------------------------------------------------------------------

## Eingeschaltete Quellen in ihrer Reihenfolge (Reihen auf der Startseite in dieser Folge).
func order() -> Array:
	var raw: Variant = Config.get_value("movies.sources", ["addons"])
	var out: Array = []
	if raw is Array:
		for k in raw:
			if str(k) in KINDS and not out.has(str(k)):
				out.append(str(k))
	return out


func is_on(kind: String) -> bool:
	return order().has(kind)


func set_on(kind: String, on: bool) -> void:
	var o := order()
	if on == o.has(kind) or not (kind in KINDS):
		return
	if on:
		o.append(kind)
	else:
		o.erase(kind)
	Config.set_value("movies.sources", o)
	changed.emit()
	rows_ready.emit()


func move(kind: String, d: int) -> void:
	var o := order()
	var i := o.find(kind)
	var j := clampi(i + d, 0, o.size() - 1)
	if i < 0 or i == j:
		return
	o.remove_at(i)
	o.insert(j, kind)
	Config.set_value("movies.sources", o)
	changed.emit()
	rows_ready.emit()


## Addons (Kataloge auf der Startseite und in der Suche) eingeschaltet? Quellen zum Abspielen
## fragen die Addons immer – auch für Titel aus dem Stremio-Konto.
func addons_on() -> bool:
	return is_on("addons")


## Beim ersten Öffnen von „Filme“ fragen, woher Filme kommen sollen (nicht im Kinderprofil).
func needs_choice() -> bool:
	return not demo and not bool(Config.get_value("movies.sources_chosen", false)) and not Config.is_kid()


func mark_chosen() -> void:
	if not demo:
		Config.set_value("movies.sources_chosen", true)


func connected(kind: String) -> bool:
	if demo:
		return kind in ["addons", "plex", "jellyfin"] or (kind == "stremio" and bool(_demo.get("stremio_on", false)))
	match kind:
		"addons":
			return true
		"plex":
			return _tok("plex.token") != "" and not _server("plex").is_empty()
		"jellyfin", "emby":
			return _tok(kind + ".token") != "" and not _server(kind).is_empty() and Jf.id_ok(_user(kind).get("id", "")) != ""
		"stremio":
			return _tok("stremio.auth") != ""
	return false


## Eingeschaltet und verbunden: bringt Reihen.
func active(kind: String) -> bool:
	return is_on(kind) and connected(kind)


func active_kinds() -> Array:
	return order().filter(func(k: String) -> bool: return k != "addons" and connected(k))


## „Plex · Wohnzimmer“ – Name der Quelle mit Server.
func label(kind: String) -> String:
	var srv := _server(kind)
	var n := str(srv.get("name", "")) if not srv.is_empty() else ""
	return str(NAMES.get(kind, kind)) + ("  ·  " + n if n != "" else "")


## Kurzer Stand für Einstellungen und die Quellen-Seite.
func status_text(kind: String) -> String:
	if kind == "addons":
		var n := Movies.addons.size()
		return "%d %s" % [n, "Addon" if n == 1 else "Addons"]
	if not connected(kind):
		return "Nicht verbunden"
	var srv := _server(kind)
	match kind:
		"plex":
			return "Verbunden  ·  " + str(srv.get("name", "Server"))
		"jellyfin", "emby":
			var who := str(_user(kind).get("name", ""))
			return "Verbunden  ·  " + str(srv.get("name", "Server")) + (" als " + who if who != "" else "")
		"stremio":
			var mail := str(Config.get_value("stremio.email", "")) if not demo else "demo@example.invalid"
			return "Verbunden" + ("  ·  " + mail if mail != "" else "")
	return ""


## Unverschlüsselt (http) verbunden? Die Oberfläche sagt es dann dazu.
func plain_http(kind: String) -> bool:
	return bool(_server(kind).get("http", false))


## Welcher Quelle gehört diese Kennung bzw. dieser Katalog? (siehe medienquellen_basis.gd)
static func owner_of(id: String) -> String:
	return B.owner_of(id)


static func owner_of_addon(addon_id: String) -> String:
	return B.owner_of_addon(addon_id)


static func _strip(id: String) -> String:
	return id.substr(id.find(":") + 1)


# --- Gespeichertes -----------------------------------------------------------------------------

func _tok(key: String) -> String:
	var v: Variant = Config.get_value(key, "")
	return str(v) if v is String else ""


func _server(kind: String) -> Dictionary:
	if demo:
		return (_demo.servers as Dictionary).get(kind, {})
	var v: Variant = Config.get_value(kind + ".server", {})
	return v if v is Dictionary else {}


## Gewählter Server einer Quelle ({ id, name, … } ohne Schlüssel).
func server_info(kind: String) -> Dictionary:
	return _server(kind).duplicate()


## Angemeldeter Benutzername (Jellyfin, Emby) – zum Vorschlagen beim neuen Anmelden.
func server_user(kind: String) -> String:
	return str(_user(kind).get("name", ""))


func _user(kind: String) -> Dictionary:
	var v: Variant = Config.get_value(kind + ".user", {})
	return v if v is Dictionary else {}


## Kennung dieses Geräts beim Dienst (je Profil, zufällig, ohne Bezug zur Person).
func _device(kind: String) -> String:
	var key := ("plex.client_id" if kind == "plex" else kind + ".device_id")
	var v := str(Config.get_value(key, ""))
	if B.ident(v, "hex", 32, 32) == "":
		v = B.random_id()
		Config.set_value(key, v)
	return v


func _slot(kind: String) -> Dictionary:
	if not _slots.has(kind):
		_slots[kind] = { "at": 0.0, "rows": [], "cw": [], "cw_at": 0, "libs": {}, "err": "", "loading": false, "gen": 0, "genres": {}, "items": [] }
	return _slots[kind]


## Alles Geladene einer Quelle vergessen (Abmelden, anderer Server).
func _reset(kind: String) -> void:
	var gen := int(_slot(kind).gen) + 1
	_slots.erase(kind)
	_slot(kind).gen = gen
	if kind == "stremio":
		_st_raw = {}


## Bilder der verbundenen Server freigeben (Net.media_origins): Plex mit Schlüssel, die anderen
## ohne (ihre Bilder brauchen keinen).
func _register_origins() -> void:
	Net.media_origins.clear()
	if demo:
		return
	if connected("plex"):
		var o := Net.origin(str(_server("plex").get("uri", "")))
		if o != "":
			Net.media_origins[o] = PackedStringArray(["X-Plex-Token: " + _plex_token()])
	for k in ["jellyfin", "emby"]:
		if connected(k):
			var o2 := Net.origin(str(_server(k).get("base", "")))
			if o2 != "":
				Net.media_origins[o2] = PackedStringArray()


# --- Netz --------------------------------------------------------------------------------------

## Anfrage mit Größengrenze, ohne Weiterleitungen; Antwort { ok, code, data }.
func _req(url: String, headers: PackedStringArray, method := HTTPClient.METHOD_GET, body := "", max_bytes := B.MAX_JSON, timeout := TIMEOUT) -> Dictionary:
	var h := headers.duplicate()
	if body != "":
		h.append("Content-Type: application/json")
	var r: Dictionary = await Net.request(url, h, method, body, timeout, "api", max_bytes, false)
	var raw: PackedByteArray = r.get("body", PackedByteArray())
	return { "ok": bool(r.ok), "code": int(r.code), "data": B.json(raw, max_bytes) if not raw.is_empty() else null }


## Viele Anfragen gleichzeitig; jede bekommt ihr Ergebnis unter „res“.
func _all(jobs: Array) -> void:
	var box := { "left": jobs.size() }
	for j in jobs:
		_one(j, box)
	while int(box.left) > 0:
		await get_tree().process_frame


func _one(j: Dictionary, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt
	# (sonst wartete _all für immer), und der Auftrag hat ein Ergebnis.
	j["res"] = { "ok": false, "code": 0, "data": null }
	await _one_arbeit(j)
	box.left = int(box.left) - 1


func _one_arbeit(j: Dictionary) -> void:
	j["res"] = await _req(str(j.url), j.headers, int(j.get("method", HTTPClient.METHOD_GET)), str(j.get("body", "")), int(j.get("max", B.MAX_JSON)))


## Nimmt der Dienst die Anmeldung nicht mehr an (401/403)? Dann hilft nur neu anmelden – bei Netzfehlern und
## stummen Servern reicht es, nur das Laden zu wiederholen (Anmelde-Ebenen: „Nochmal versuchen“).
static func abgelaufen(r: Dictionary) -> bool:
	return int(r.get("code", 0)) in [401, 403]


static func _reason(r: Dictionary, what: String) -> String:
	var code := int(r.get("code", 0))
	if code == 0:
		return "%s: keine Verbindung oder Zeitüberschreitung." % what
	if code == 401 or code == 403:
		return "%s: Anmeldung abgelaufen oder ohne Zugriff. Bitte neu anmelden." % what
	if code >= 200 and code < 300:
		return "%s: unerwartete Antwort." % what
	return "%s: Der Server antwortet gerade nicht. Gleich noch einmal versuchen." % what


func _plex_token() -> String:
	var t := _tok("plex.server_token")
	return t if t != "" else _tok("plex.token")


func _plex_job(path: String, max_bytes := B.MAX_JSON) -> Dictionary:
	return { "url": str(_server("plex").get("uri", "")) + path, "headers": Plex.headers(_device("plex"), Config.VERSION, _plex_token()), "max": max_bytes }


func _plex(path: String, max_bytes := B.MAX_JSON) -> Dictionary:
	var j := _plex_job(path, max_bytes)
	return await _req(str(j.url), j.headers, HTTPClient.METHOD_GET, "", max_bytes)


func _jf_job(kind: String, path: String, max_bytes := B.MAX_JSON) -> Dictionary:
	return { "url": str(_server(kind).get("base", "")) + path, "headers": Jf.headers(kind, _device(kind), Config.VERSION, _tok(kind + ".token")),
			"max": max_bytes }


func _jf(kind: String, path: String, method := HTTPClient.METHOD_GET, payload: Variant = null, max_bytes := B.MAX_JSON) -> Dictionary:
	var j := _jf_job(kind, path, max_bytes)
	return await _req(str(j.url), j.headers, method, JSON.stringify(payload) if payload != null else "", max_bytes)


func _st_post(path: String, payload: Dictionary, max_bytes := B.MAX_JSON) -> Dictionary:
	return await _req(St.api_base() + path, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload), max_bytes)


# --- Plex: Anmeldung und Server ----------------------------------------------------------------

## PIN bei plex.tv holen: { ok, id, code, url, expires, error }. Der Nutzer gibt den Code unter
## plex.tv/link ein (QR-Code führt dorthin).
func plex_pin_start() -> Dictionary:
	if demo:
		return { "ok": true, "id": 1, "code": "K7QZ", "url": Plex.LINK, "expires": 900 }
	var r := await _req(Plex.tv_base() + "/api/v2/pins?strong=false", Plex.headers(_device("plex"), Config.VERSION), HTTPClient.METHOD_POST, "", 64 * 1024)
	var p := Plex.parse_pin(r.data) if r.ok else {}
	if p.is_empty():
		return { "ok": false, "error": _reason(r, "plex.tv") }
	return { "ok": true, "id": int(p.id), "code": str(p.code), "url": Plex.LINK, "expires": int(p.expires) }


## PIN abfragen: „wait“, „ok“ (Schlüssel gespeichert), „expired“ oder „error“.
func plex_pin_poll(pin_id: int) -> String:
	if demo:
		return "wait"
	var r := await _req(Plex.tv_base() + "/api/v2/pins/%d" % pin_id, Plex.headers(_device("plex"), Config.VERSION), HTTPClient.METHOD_GET, "", 64 * 1024)
	if int(r.code) == 404:
		return "expired"
	if not r.ok:
		return "error"
	var p := Plex.parse_pin(r.data)
	if p.is_empty():
		return "error"
	if str(p.token) == "":
		return "wait"
	Config.set_value("plex.token", str(p.token))
	var u := await _req(Plex.tv_base() + "/api/v2/user", Plex.headers(_device("plex"), Config.VERSION, str(p.token)), HTTPClient.METHOD_GET, "", 256 * 1024)
	if u.ok:
		Config.set_value("plex.user", B.text(B.dict(u.data).get("username", B.dict(u.data).get("title", "")), 60))
	return "ok"


## Server des Kontos (eigene und geteilte): [{ id, name, owned, online, token, conns }]. Fehler: error und anmelden
## (abgelaufen(): neu anmelden statt nur neu laden).
func plex_servers() -> Dictionary:
	if demo:
		return { "ok": true, "servers": (_demo.plex_servers as Array).duplicate(true) }
	var r := await _req(Plex.tv_base(true) + "/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1",
		Plex.headers(_device("plex"), Config.VERSION, _tok("plex.token")), HTTPClient.METHOD_GET, "", 2 * 1024 * 1024)
	if not r.ok:
		return { "ok": false, "servers": [], "error": _reason(r, "plex.tv"), "anmelden": abgelaufen(r) }
	return { "ok": true, "servers": Plex.parse_servers(r.data) }


## Server wählen: Verbindungen der Reihe nach prüfen (/identity muss diesen Server nennen –
## erst dann bekommt die Adresse den Schlüssel). { ok, http_needed, error }.
func plex_pick(server: Dictionary, allow_http := false) -> Dictionary:
	if demo:
		return { "ok": true }
	var http_needed := false
	for c in server.get("conns", []):
		if bool(c.http) and not allow_http:
			http_needed = true
			continue
		var r := await _req(str(c.uri) + "/identity", PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "", 64 * 1024, 6.0)
		if r.ok and Plex.parse_identity(r.data) == str(server.id):
			_reset("plex")
			Config.set_value("plex.server", { "id": str(server.id), "name": str(server.name), "uri": str(c.uri), "owned": bool(server.owned),
				"http": bool(c.http), "local": bool(c.local) })
			Config.set_value("plex.server_token", str(server.get("token", "")))
			_connected("plex")
			return { "ok": true }
	if http_needed:
		return { "ok": false, "http_needed": true, "error": "" }
	return { "ok": false,
			"error": "„%s“ ist gerade nicht erreichbar. Läuft der Server, und ist der PC im selben Netz oder der Fernzugriff an?" % str(server.name) }


func _connected(kind: String) -> void:
	if not is_on(kind):
		var o := order()
		o.insert(0, kind)
		Config.set_value("movies.sources", o)
	_register_origins()
	Config.save_settings()
	changed.emit()
	_load(kind)


# --- Jellyfin und Emby: Server und Anmeldung ----------------------------------------------------

## Adresse prüfen: { ok, base, name, id, version, http, error }. Ohne Schema und Port nimmt Uzai im
## Heimnetz http://…:8096 an, sonst https. Unverschlüsselt nur zu privaten Adressen.
func server_check(kind: String, address: String) -> Dictionary:
	var a := address.strip_edges()
	var p := B.parse_server(a)
	# „192.168.1.20“ ohne Schema und Port: der übliche Port von Jellyfin und Emby.
	if not p.is_empty() and not a.contains("://") and not a.get_slice("/", 0).contains(":") and B.is_private_ip(str(p.host)):
		p = B.parse_server(a, 8096)
	if p.is_empty():
		return { "ok": false, "error": "Diese Adresse versteht Uzai nicht. Beispiel: 192.168.1.20:8096 oder https://medien.example.de" }
	if demo:
		return { "ok": true, "base": str(p.base), "name": "Demo-Server", "id": "demo", "version": "10.10", "http": str(p.scheme) == "http" }
	var http := str(p.scheme) == "http"
	if http and not await _private_host(str(p.host)):
		return { "ok": false,
				"error": "Ohne Verschlüsselung (http) verbindet sich Uzai nur mit Servern im Heimnetz. Für Server im Internet bitte die https-Adresse eingeben." }
	var r := await _req(str(p.base) + "/System/Info/Public", PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "", 64 * 1024, 8.0)
	var info := Jf.parse_public_info(r.data) if r.ok else {}
	if info.is_empty():
		return { "ok": false, "error": "Unter %s antwortet kein %s-Server." % [str(p.base), Jf.source_name(kind)] if int(r.code) != 0
				else "%s ist nicht erreichbar. Adresse und Netz prüfen." % str(p.base) }
	if str(info.kind) != kind:
		return { "ok": false, "error": "Das ist ein %s-Server – bitte oben „%s“ wählen." % [Jf.source_name(str(info.kind)), Jf.source_name(str(info.kind))] }
	return { "ok": true, "base": str(p.base), "name": str(info.name), "id": str(info.id), "version": str(info.version), "http": http }


## Liegt ein Name oder eine Adresse im Heimnetz? Namen müssen ganz auf private Adressen zeigen.
func _private_host(host: String) -> bool:
	if host.is_valid_ip_address():
		return B.is_private_ip(host)
	var ips := await Sicher.adressen_von(host)
	if ips.is_empty():
		return false
	for ip in ips:
		if not B.is_private_ip(str(ip)):
			return false
	return true


## Server im Heimnetz finden (nur auf Wunsch): ein Rundruf an UDP 7359, 2,5 Sekunden lang
## Antworten sammeln, jede streng geprüft. [{ name, id, address }].
func discover(kind: String) -> Array:
	if demo:
		await get_tree().create_timer(0.6).timeout
		return (_demo.discovered as Array).duplicate(true)
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var target := Config.probe_env("UZAI_JF_DISCOVERY")
	var host := "255.255.255.255"
	var port := Jf.DISCOVERY_PORT
	if target != "" and target.contains(":"):
		host = target.get_slice(":", 0)
		port = int(target.get_slice(":", 1))
	if udp.set_dest_address(host, port) != OK:
		return []
	udp.put_packet(("who is EmbyServer?" if kind == "emby" else "who is JellyfinServer?").to_utf8_buffer())
	var out: Array = []
	var seen := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < DISCOVERY_MS and out.size() < 16:
		await get_tree().create_timer(0.05).timeout
		var n := 0
		while udp.get_available_packet_count() > 0 and n < 64:
			n += 1
			var pkt := udp.get_packet()
			var s := Jf.parse_discovery(pkt, udp.get_packet_ip())
			if s.is_empty() or seen.has(str(s.id)):
				continue
			seen[str(s.id)] = true
			out.append(s)
	udp.close()
	return out


## Bietet der Server Quick Connect an (nur Jellyfin)?
func quick_available(kind: String, server: Dictionary) -> bool:
	if kind != "jellyfin":
		return false
	if demo:
		return true
	var r := await _req(str(server.base) + "/QuickConnect/Enabled", Jf.headers(kind, _device(kind), Config.VERSION), HTTPClient.METHOD_GET, "", 4096, 8.0)
	return r.ok and r.data is bool and bool(r.data)


## Quick Connect beginnen: { ok, code, secret, error }. Den Code bestätigst du in Jellyfin
## (Benutzermenü → Quick Connect) auf einem Gerät, auf dem du schon angemeldet bist.
func quick_start(kind: String, server: Dictionary) -> Dictionary:
	if demo:
		return { "ok": true, "code": "482913", "secret": "demo" }
	var h := Jf.headers(kind, _device(kind), Config.VERSION)
	var r := await _req(str(server.base) + "/QuickConnect/Initiate", h, HTTPClient.METHOD_POST, "", 64 * 1024, 8.0)
	if int(r.code) in [404, 405]:
		r = await _req(str(server.base) + "/QuickConnect/Initiate", h, HTTPClient.METHOD_GET, "", 64 * 1024, 8.0)
	var q := Jf.parse_quick(r.data) if r.ok else {}
	if q.is_empty() or str(q.code) == "":
		return { "ok": false, "error": "Quick Connect ist auf diesem Server aus. Name und Passwort gehen immer." if int(r.code) in [401, 403]
				else _reason(r, str(server.get("name", "Server"))) }
	return { "ok": true, "code": str(q.code), "secret": str(q.secret) }


## Quick Connect abfragen: „wait“, „ok“ (angemeldet und gespeichert) oder „error“.
func quick_poll(kind: String, server: Dictionary, secret: String) -> String:
	if demo:
		return "wait"
	var h := Jf.headers(kind, _device(kind), Config.VERSION)
	var r := await _req(str(server.base) + "/QuickConnect/Connect?Secret=" + secret.uri_encode(), h, HTTPClient.METHOD_GET, "", 64 * 1024, 8.0)
	if not r.ok:
		return "error" if int(r.code) in [401, 403, 404] else "wait"
	var q := Jf.parse_quick(r.data)
	if q.is_empty() or not bool(q.ok):
		return "wait"
	var a := await _req(str(server.base) + "/Users/AuthenticateWithQuickConnect", h, HTTPClient.METHOD_POST, JSON.stringify({ "Secret": secret }), 256 * 1024,
			10.0)
	var auth := Jf.parse_auth(a.data) if a.ok else {}
	if auth.is_empty():
		return "error"
	_save_login(kind, server, auth)
	return "ok"


## Mit Name und Passwort anmelden. Das Passwort geht nur an den Server und wird nicht gespeichert.
## "" oder ein Satz zum Grund.
func login_password(kind: String, server: Dictionary, user: String, password: String) -> String:
	if demo:
		return "Im Demo-Modus meldet sich Uzai nicht an."
	var r := await _req(str(server.base) + "/Users/AuthenticateByName", Jf.headers(kind, _device(kind), Config.VERSION), HTTPClient.METHOD_POST,
		JSON.stringify({ "Username": user.strip_edges(), "Pw": password }), 256 * 1024, 12.0)
	if int(r.code) == 401:
		return "Name oder Passwort stimmt nicht."
	var auth := Jf.parse_auth(r.data) if r.ok else {}
	if auth.is_empty():
		return _reason(r, str(server.get("name", "Server")))
	_save_login(kind, server, auth)
	return ""


func _save_login(kind: String, server: Dictionary, auth: Dictionary) -> void:
	_reset(kind)
	Config.set_value(kind + ".server", { "base": str(server.base), "name": str(server.name), "id": str(server.id), "http": bool(server.http) })
	Config.set_value(kind + ".token", str(auth.token))
	Config.set_value(kind + ".user", { "id": str(auth.user_id), "name": str(auth.user_name) })
	_connected(kind)


# --- Stremio-Konto -----------------------------------------------------------------------------

## Code für link.stremio.com holen: { ok, code, url, error }.
func stremio_link_start() -> Dictionary:
	if demo:
		return { "ok": true, "code": "XU4K2", "url": St.LINK_PAGE }
	var r := await _req(St.link_base() + "/create?type=Create", PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "", 64 * 1024)
	var l := St.parse_link(r.data) if r.ok else {}
	if l.is_empty():
		return { "ok": false, "error": _reason(r, "Stremio") }
	return { "ok": true, "code": str(l.code), "url": str(l.link) }


## Code abfragen: „wait“ oder „ok“ (angemeldet).
func stremio_link_poll(code: String) -> String:
	if demo:
		return "wait"
	var r := await _req(St.link_base() + "/read?type=Read&code=" + code.uri_encode(), PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "",
			64 * 1024)
	var key := St.parse_auth_key(r.data) if r.ok else ""
	if key == "":
		return "wait"
	_reset("stremio")
	Config.set_value("stremio.auth", key)
	var u := await _st_post("/getUser", { "type": "GetUser", "authKey": key }, 256 * 1024)
	Config.set_value("stremio.email", St.parse_email(u.data) if u.ok else "")
	_connected("stremio")
	return "ok"


## Die Addons, die du selbst in Stremio installiert hast: [{ url, name, have }]. Fehler: error und anmelden (wie bei
## plex_servers).
func stremio_addons() -> Dictionary:
	if demo:
		return { "ok": true, "addons": (_demo.stremio_addons as Array).duplicate(true) }
	var r := await _st_post("/addonCollectionGet", { "type": "AddonCollectionGet", "authKey": _tok("stremio.auth"), "update": true }, 2 * 1024 * 1024)
	if not r.ok:
		return { "ok": false, "addons": [], "error": _reason(r, "Stremio"), "anmelden": abgelaufen(r) }
	var have := {}
	for a in Movies.addons:
		have[MoviesScript.normalize_manifest_url(str(a.get("url", "")))] = true
	var list := St.parse_addons(r.data)
	for a in list:
		a["have"] = have.has(str(a.url))
	return { "ok": true, "addons": list }


## Ausgewählte eigene Addons in Uzai installieren (nur auf Wunsch). { added, failed }
func stremio_import(list: Array) -> Dictionary:
	var added := 0
	var failed: Array = []
	for a in list:
		if bool(a.get("have", false)):
			continue
		var err: Variant = await Movies.install_addon(str(a.url))
		if str(err) == "":
			added += 1
		else:
			failed.append(str(a.get("name", "")))
	return { "added": added, "failed": failed }


## Fortschritt aus Uzai zurück ins Stremio-Konto (nur Titel, die dort in der Bibliothek liegen).
func _on_local_change(kind: String, info: Dictionary) -> void:
	if kind != "progress" or not active("stremio") or not bool(Config.get_value("stremio.write_back", true)):
		return
	var mid := str(info.get("meta_id", ""))
	if not _st_raw.has(mid):
		return
	var e: Dictionary = info.get("entry", {})
	var dur := float(e.get("duration", 0.0))
	var change := St.put_change(_st_raw[mid], float(e.get("position", 0.0)), dur, str(info.get("video_id", "")), bool(e.get("watched", false)),
			int(Time.get_unix_time_from_system()))
	_st_raw[mid] = change
	await _st_post("/datastorePut", { "authKey": _tok("stremio.auth"), "collection": "libraryItem", "changes": [change] }, 64 * 1024)


# --- Laden -------------------------------------------------------------------------------------

## Reihen und Weiterschauen einer Quelle laden (im Hintergrund; meldet rows_ready).
func _load(kind: String) -> void:
	var d := _slot(kind)
	if bool(d.loading):
		return
	d.loading = true
	var gen := int(d.gen)
	var fresh := { "rows": [], "cw": [], "libs": {}, "err": "", "items": [] }
	if demo:
		await get_tree().create_timer(0.3).timeout
		fresh = DemoData.slot(_demo, kind)
	else:
		match kind:
			"plex": await _load_plex(fresh)
			"jellyfin", "emby": await _load_jf(kind, fresh)
			"stremio": await _load_stremio(fresh)
	if int(_slot(kind).gen) != gen:
		return
	d = _slot(kind)
	d.loading = false
	d.at = Time.get_unix_time_from_system()
	d.err = str(fresh.err)
	# Ohne Netz bleibt der letzte Stand stehen.
	if str(fresh.err) == "" or (d.rows as Array).is_empty():
		d.rows = fresh.rows
		d.cw = fresh.cw
		d.cw_at = int(Time.get_unix_time_from_system())
		d.libs = fresh.libs
		d.items = fresh.items
	rows_ready.emit()


func _load_plex(out: Dictionary) -> void:
	var srv := _server("plex")
	var origin := str(srv.get("uri", ""))
	var lr := await _plex("/library/sections")
	if not lr.ok:
		out.err = _reason(lr, label("plex"))
		return
	var libs := Plex.parse_sections(lr.data).slice(0, LIBS_MAX)
	var jobs: Array = [_plex_job("/hubs/continueWatching/items?X-Plex-Container-Size=24")]
	for l in libs:
		jobs.append(_plex_job(Plex.items_path(str(l.key), str(l.type), 0, 24, "addedAt:desc")))
		jobs.append(_plex_job("/library/sections/%s/collections?X-Plex-Container-Size=40" % str(l.key)))
	await _all(jobs)
	var by_key := {}
	for l in libs:
		by_key[str(l.key)] = l
	out.libs = by_key
	var cw_res: Dictionary = jobs[0].res
	if not cw_res.ok:
		cw_res = await _plex("/library/onDeck?X-Plex-Container-Size=24")
	out.cw = Plex.parse_continue(cw_res.data, origin, by_key) if cw_res.ok else []
	var recent: Array = []
	var colls: Array = []
	for i in libs.size():
		var l: Dictionary = libs[i]
		var rr: Dictionary = jobs[1 + i * 2].res
		recent.append(Plex.parse_list(rr.data, origin, l) if rr.ok else [])
		var cr: Dictionary = jobs[2 + i * 2].res
		for c in (Plex.parse_collections(cr.data, origin) if cr.ok else []):
			c["lib"] = l
			colls.append(c)
	out.rows = _build_rows("plex",
			libs.map(func(l: Dictionary) -> Dictionary: return { "id": str(l.key), "title": str(l.title), "type": str(l.type), "family": bool(l.family) }), recent,
			colls)


func _load_jf(kind: String, out: Dictionary) -> void:
	var base := str(_server(kind).get("base", ""))
	var uid := str(_user(kind).get("id", ""))
	var vr := await _jf(kind, "/Users/%s/Views" % uid)
	if not vr.ok:
		out.err = _reason(vr, label(kind))
		return
	var views := Jf.parse_views(vr.data)
	var libs: Array = views.filter(func(v: Dictionary) -> bool: return str(v.type) in ["movies", "tvshows", "mixed", "homevideos"]).slice(0, LIBS_MAX)
	var jobs: Array = [
		_jf_job(kind, "/Users/%s/Items/Resume?Limit=24&MediaTypes=Video&Fields=%s&EnableUserData=true" % [uid, Jf.FIELDS]),
		_jf_job(kind, "/Shows/NextUp?UserId=%s&Limit=24&Fields=%s&EnableUserData=true" % [uid, Jf.FIELDS]),
		_jf_job(kind, "/Users/%s/Items?IncludeItemTypes=BoxSet&Recursive=true&SortBy=SortName&Limit=40&Fields=ChildCount" % uid),
	]
	for l in libs:
		jobs.append(_jf_job(kind, "/Users/%s/Items/Latest?ParentId=%s&Limit=24&Fields=%s&EnableUserData=true" % [uid, str(l.id), Jf.FIELDS]))
	await _all(jobs)
	var by_id := {}
	for l in libs:
		by_id[str(l.id)] = l
	out.libs = by_id
	out.cw = Jf.parse_continue(jobs[0].res.data if jobs[0].res.ok else {}, jobs[1].res.data if jobs[1].res.ok else {}, base, kind, by_id)
	var recent: Array = []
	for i in libs.size():
		var rr: Dictionary = jobs[3 + i].res
		recent.append(Jf.parse_list(rr.data, base, kind, libs[i]) if rr.ok else [])
	var colls := Jf.parse_collections(jobs[2].res.data, base) if jobs[2].res.ok else []
	out.rows = _build_rows(kind, libs.map(func(l: Dictionary) -> Dictionary: return { "id": str(l.id), "title": str(l.name),
		"type": "series" if str(l.type) == "tvshows" else "movie", "family": bool(l.family) }), recent, colls)


func _load_stremio(out: Dictionary) -> void:
	var r := await _st_post("/datastoreGet", { "authKey": _tok("stremio.auth"), "collection": "libraryItem", "ids": [], "all": true }, B.MAX_JSON_BIG)
	if not r.ok:
		out.err = _reason(r, "Stremio")
		return
	var items := St.parse_library(r.data)
	_st_raw = {}
	for e in items:
		_st_raw[str(e.id)] = e.raw
	out.items = St.library(items)
	out.cw = St.continue_items(items)
	if not (out.items as Array).is_empty():
		out.rows = [{ "key": "quelle:stremio/bibliothek", "title": "Deine Stremio-Bibliothek", "type": "movie", "addon_id": St.ADDON,
			"catalog_id": "bibliothek", "extra": {}, "items": (out.items as Array).slice(0, 30), "see_all": (out.items as Array).size() > 30,
			"source": "stremio", "source_label": label("stremio") }]


## Reihen einer Server-Quelle: je Bibliothek „Neu in …“, dann die Bibliotheken und Sammlungen
## als Ordner (A öffnet sie mit allen Titeln).
func _build_rows(kind: String, libs: Array, recent: Array, colls: Array) -> Array:
	var aid := "quelle:" + kind
	var lab := label(kind)
	var rows: Array = []
	var folders: Array = []
	for i in libs.size():
		var l: Dictionary = libs[i]
		var items: Array = recent[i] if i < recent.size() else []
		var src := { "addon_id": aid, "type": str(l.type), "catalog_id": "lib:" + str(l.id), "genre": "", "name": str(l.title) }
		if not items.is_empty():
			rows.append({ "key": "%s/neu/%s" % [aid, str(l.id)], "title": "Neu in „%s“" % str(l.title), "type": str(l.type), "addon_id": aid,
				"catalog_id": "lib:" + str(l.id), "extra": { "sort": "neu" }, "items": items, "see_all": true, "source": kind, "source_label": lab })
		var cover := ""
		for it in items:
			if str(it.get("background", "")) != "":
				cover = str(it.background)
				break
		folders.append({ "id": "lib:" + str(l.id), "title": str(l.title), "backdrop": cover, "cover": cover, "emoji": "", "shape": "LANDSCAPE",
			"hide_title": false, "collection": lab, "sources": [src], "family": bool(l.family), "label": "Bibliothek",
			"description": "Alle %s dieser Bibliothek, mit Genres zum Filtern." % ("Serien" if str(l.type) == "series" else "Filme") })
	if folders.size() > 0:
		rows.append({ "key": aid + "/bibliotheken", "title": "Bibliotheken", "kind": "folders", "show_all": false, "items": [], "folders": folders,
			"source": kind, "source_label": lab })
	var cf: Array = []
	for c in colls.slice(0, 30):
		var lib: Dictionary = c.get("lib", {})
		cf.append({ "id": "coll:" + str(c.id), "title": str(c.title), "backdrop": str(c.background) if str(c.background) != "" else str(c.poster),
			"cover": str(c.poster), "emoji": "", "shape": "POSTER", "hide_title": false, "collection": lab, "label": "Sammlung",
			"description": ("%d Titel" % int(c.count)) if int(c.get("count", 0)) > 0 else "",
			"sources": [{ "addon_id": aid, "type": str(lib.get("type", "movie")), "catalog_id": "coll:" + str(c.id), "genre": "", "name": str(c.title) }] })
	if not cf.is_empty():
		rows.append({ "key": aid + "/sammlungen", "title": "Sammlungen", "kind": "folders", "show_all": false, "items": [], "folders": cf,
			"source": kind, "source_label": lab })
	return rows


# --- Für Movies ----------------------------------------------------------------------------------

## Reihen aller eingeschalteten, verbundenen Quellen: { Art: [Reihen] }. Wartet beim ersten Mal
## höchstens WAIT Sekunden; was später kommt, meldet rows_ready.
func home_rows(force := false) -> Dictionary:
	var kinds := active_kinds()
	kick(force)
	var t0 := Time.get_ticks_msec()
	while kinds.any(func(k: String) -> bool: return float(_slot(k).at) == 0.0 and bool(_slot(k).loading)) and Time.get_ticks_msec() - t0 < WAIT * 1000.0:
		await get_tree().create_timer(0.1).timeout
	var out := {}
	for k in kinds:
		out[k] = (_slot(k).rows as Array).duplicate(true)
	return out


## Laden der Quellen anstoßen, ohne zu warten: Movies.home_rows ruft das vor den Addon-Katalogen,
## damit beides gleichzeitig läuft (früher erst die Kataloge, danach die Quellen – bis zu zweimal
## WAIT Sekunden Platzhalter).
func kick(force := false) -> void:
	var now := Time.get_unix_time_from_system()
	for k in active_kinds():
		var d := _slot(k)
		if (force or now - float(d.at) > MAX_AGE) and not bool(d.loading):
			_load(k)


## Lädt gerade eine Quelle?
func loading_any() -> bool:
	return active_kinds().any(func(k: String) -> bool: return bool(_slot(k).loading))


## Fehler beim letzten Laden je Quelle (für die leere Startseite).
func errors() -> Array:
	var out: Array = []
	for k in active_kinds():
		if str(_slot(k).err) != "":
			out.append(str(_slot(k).err))
	return out


## Weiterschauen aller aktiven Quellen (schon geladen, ohne Netz).
func continue_items() -> Array:
	var out: Array = []
	for k in active_kinds():
		for it in _slot(k).cw:
			var c: Dictionary = (it as Dictionary).duplicate()
			c["cw_at"] = int(_slot(k).cw_at)
			out.append(c)
	return out


## Titel mit Bild für den Kopf der Startseite: aus „Neu in …“ einer aktiven Quelle.
func hero_items(kind: String) -> Array:
	var out: Array = []
	var seen := {}
	if not active(kind):
		return out
	for r in _slot(kind).rows:
		for it in r.get("items", []):
			if out.size() >= 8:
				return out
			if str(it.get("background", "")) != "" and not seen.has(str(it.id)):
				seen[str(it.id)] = true
				out.append(it)
	return out


## Eine Seite eines Katalogs einer Quelle (Bibliothek „lib:…“, Sammlung „coll:…“, Stremio
## „bibliothek“). extra: sort = „neu“, genre = Name.
func catalog_page(kind: String, type: String, catalog_id: String, skip := 0, extra := {}) -> Dictionary:
	if not connected(kind):
		return { "ok": false, "items": [], "error": "%s ist nicht verbunden." % str(NAMES.get(kind, kind)) }
	var neu := str(extra.get("sort", "")) == "neu"
	var genre := str(extra.get("genre", ""))
	if demo:
		await get_tree().process_frame
		return { "ok": true, "items": DemoData.catalog(_demo, kind, catalog_id, skip, genre) }
	match kind:
		"stremio":
			var items: Array = _slot("stremio").items
			if (items as Array).is_empty() and float(_slot("stremio").at) == 0.0:
				await _load_wait("stremio")
				items = _slot("stremio").items
			return { "ok": true, "items": (items as Array).slice(skip, skip + Plex.PAGE) }
		"plex":
			var origin := str(_server("plex").get("uri", ""))
			var path := ""
			var lib := {}
			if catalog_id.begins_with("lib:"):
				var key := B.ident(catalog_id.substr(4), "digits", 1, 9)
				lib = _slot("plex").libs.get(key, {})
				var gkey := ""
				if genre != "":
					for g in await _genres("plex", catalog_id):
						if str(g.title) == genre:
							gkey = str(g.key)
				path = Plex.items_path(key, type, skip, Plex.PAGE, "addedAt:desc" if neu else "titleSort", gkey)
			elif catalog_id.begins_with("coll:"):
				path = Plex.collection_path(B.ident(catalog_id.substr(5), "digits", 1, 12), skip, Plex.PAGE)
			if path == "":
				return { "ok": false, "items": [] }
			var r := await _plex(path)
			return { "ok": r.ok, "items": Plex.parse_list(r.data, origin, lib) if r.ok else [], "error": "" if r.ok else _reason(r, label("plex")) }
		"jellyfin", "emby":
			var base := str(_server(kind).get("base", ""))
			var uid := str(_user(kind).get("id", ""))
			var pid := Jf.id_ok(catalog_id.get_slice(":", 1))
			if pid == "":
				return { "ok": false, "items": [] }
			var lib2: Dictionary = _slot(kind).libs.get(pid, {})
			var path2 := Jf.items_path(uid, pid, skip, Jf.PAGE, "DateCreated" if neu else "SortName", genre, catalog_id.begins_with("lib:"))
			var r2 := await _jf(kind, path2)
			return { "ok": r2.ok, "items": Jf.parse_list(r2.data, base, kind, lib2) if r2.ok else [], "error": "" if r2.ok else _reason(r2, label(kind)) }
	return { "ok": false, "items": [] }


func _load_wait(kind: String) -> void:
	_load(kind)
	var t0 := Time.get_ticks_msec()
	while bool(_slot(kind).loading) and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().create_timer(0.1).timeout


## Genres einer Bibliothek (für „Alle anzeigen“): [{ key, title }], gemerkt je Bibliothek.
func _genres(kind: String, catalog_id: String) -> Array:
	var d := _slot(kind)
	if (d.genres as Dictionary).has(catalog_id):
		return d.genres[catalog_id]
	var list: Array = []
	if demo:
		list = DemoData.genres(_demo, kind)
	elif kind == "plex" and catalog_id.begins_with("lib:"):
		var r := await _plex("/library/sections/%s/genre" % B.ident(catalog_id.substr(4), "digits", 1, 9))
		list = Plex.parse_genres(r.data) if r.ok else []
	elif kind in ["jellyfin", "emby"] and catalog_id.begins_with("lib:"):
		var r2 := await _jf(kind, "/Genres?ParentId=%s&UserId=%s&SortBy=SortName" % [Jf.id_ok(catalog_id.substr(4)), str(_user(kind).get("id", ""))])
		list = Jf.parse_genres(r2.data) if r2.ok else []
	d.genres[catalog_id] = list
	return list


func genre_names(kind: String, catalog_id: String) -> Array:
	if not catalog_id.begins_with("lib:") or not connected(kind):
		return []
	return (await _genres(kind, catalog_id)).map(func(g: Dictionary) -> String: return str(g.title))


## Suche in allen aktiven Quellen: Reihen wie Movies.search.
func search(q: String) -> Array:
	var rows: Array = []
	for k in active_kinds():
		var items: Array = []
		if demo:
			items = DemoData.search(_demo, k, q)
		else:
			match k:
				"plex":
					var r := await _plex("/hubs/search?query=%s&limit=20" % q.uri_encode())
					items = Plex.parse_search(r.data, str(_server("plex").get("uri", ""))) if r.ok else []
				"jellyfin", "emby":
					var r2 := await _jf(k,
							"/Users/%s/Items?SearchTerm=%s&IncludeItemTypes=Movie,Series&Recursive=true&Limit=40&Fields=%s&EnableUserData=true" % [str(_user(k).get("id", "")),
							q.uri_encode(), Jf.FIELDS])
					items = Jf.parse_list(r2.data, str(_server(k).get("base", "")), k) if r2.ok else []
				"stremio":
					var lq := q.to_lower()
					items = (_slot("stremio").items as Array).filter(func(it: Dictionary) -> bool: return str(it.name).to_lower().contains(lq))
		for t in ["movie", "series"]:
			var part := items.filter(func(it: Dictionary) -> bool: return str(it.type) == t)
			if not part.is_empty():
				rows.append({ "key": "search/quelle:%s/%s" % [k, t], "title": "%s  ·  %s" % ["Filme" if t == "movie" else "Serien", NAMES[k]],
					"type": t, "addon_id": "quelle:" + k, "catalog_id": "suche", "extra": { "search": q }, "items": part, "see_all": false, "source": k })
	return rows


## Volle Angaben eines Titels vom Server ({} mit error bei Fehler).
func meta(type: String, id: String) -> Dictionary:
	var kind := owner_of(id)
	if kind == "" or not connected(kind):
		return { "error": "%s ist nicht verbunden." % str(NAMES.get(kind, "Die Quelle")) }
	var key := _strip(id)
	if demo:
		await get_tree().process_frame
		var dm: Dictionary = (_demo.metas as Dictionary).get(id, {})
		return dm.duplicate(true) if not dm.is_empty() else { "error": "Nicht gefunden." }
	match kind:
		"plex":
			var rk := B.ident(key, "digits", 1, 12)
			var jobs: Array = [_plex_job("/library/metadata/" + rk)]
			if type == "series":
				jobs.append(_plex_job("/library/metadata/%s/allLeaves" % rk, B.MAX_JSON_BIG))
			await _all(jobs)
			var r: Dictionary = jobs[0].res
			if not r.ok:
				return { "error": _reason(r, label("plex")) }
			var first := B.arr(B.dict(B.dict(r.data).get("MediaContainer", {})).get("Metadata", []), 1)
			var sec := B.ident(B.dict(first[0] if not first.is_empty() else {}).get("librarySectionID", ""), "digits", 1, 9)
			var m := Plex.parse_meta(r.data, str(_server("plex").get("uri", "")), jobs[1].res.data if jobs.size() > 1 and jobs[1].res.ok else null,
					_slot("plex").libs.get(sec, {}))
			return m if not m.is_empty() else { "error": "Der Server kennt diesen Titel nicht (mehr)." }
		"jellyfin", "emby":
			var jid := Jf.id_ok(key)
			var uid := str(_user(kind).get("id", ""))
			var jobs2: Array = [_jf_job(kind, "/Users/%s/Items/%s" % [uid, jid])]
			if type == "series":
				jobs2.append(_jf_job(kind, "/Shows/%s/Episodes?UserId=%s&Fields=Overview&EnableUserData=true" % [jid, uid], B.MAX_JSON_BIG))
			await _all(jobs2)
			var r2: Dictionary = jobs2[0].res
			if not r2.ok:
				return { "error": _reason(r2, label(kind)) }
			var m2 := Jf.parse_meta(r2.data, str(_server(kind).get("base", "")), kind, jobs2[1].res.data if jobs2.size() > 1 and jobs2[1].res.ok else null)
			return m2 if not m2.is_empty() else { "error": "Der Server kennt diesen Titel nicht (mehr)." }
	return { "error": "Unbekannte Quelle." }


## Dateien zum Abspielen: { streams, status: { name, state, count, error } }.
func streams(video_id: String) -> Dictionary:
	var kind := owner_of(video_id)
	var st := { "name": label(kind), "state": "fertig", "count": 0, "kind": "server", "id": "quelle:" + kind, "error": "" }
	if kind == "" or not connected(kind):
		st.state = "fehler"
		st.error = "nicht verbunden"
		return { "streams": [], "status": st }
	var list: Array = []
	if demo:
		await get_tree().create_timer(0.3).timeout
		list = DemoData.streams(_demo, kind, video_id)
	else:
		match kind:
			"plex":
				var r := await _plex("/library/metadata/" + B.ident(_strip(video_id), "digits", 1, 12))
				if r.ok:
					list = Plex.parse_streams(r.data, str(_server("plex").get("uri", "")), _plex_token(), _device("plex"), str(_server("plex").get("name", "Plex")))
				else:
					st.error = _reason(r, label("plex"))
			"jellyfin", "emby":
				var r2 := await _jf(kind, "/Users/%s/Items/%s" % [str(_user(kind).get("id", "")), Jf.id_ok(_strip(video_id))])
				if r2.ok:
					list = Jf.parse_streams(r2.data, str(_server(kind).get("base", "")), kind, Jf.play_headers(kind, _device(kind), Config.VERSION, _tok(kind + ".token")),
							str(_server(kind).get("name", NAMES[kind])))
				else:
					st.error = _reason(r2, label(kind))
	st.count = list.size()
	if st.error != "":
		st.state = "fehler"
	return { "streams": list, "status": st }


# --- Wiedergabe zurückmelden ---------------------------------------------------------------------

## Abspielen beginnt (Movies.play): Plex timeline „playing“, Jellyfin /Sessions/Playing.
func playback_started(video_id: String, stream: Dictionary) -> void:
	var kind := owner_of(video_id)
	_session = {}
	if kind == "" or demo or not connected(kind):
		return
	_session = { "kind": kind, "vid": video_id, "key": _strip(video_id), "msid": str(stream.get("media_source", "")), "play": B.random_id(),
			"last": Time.get_ticks_msec() }
	_report("playing", 0.0, 0.0, false)


## Zwischenstand (alle paar Sekunden von Movies); geht höchstens alle 10 s an den Server.
func playback_progress(video_id: String, pos: float, dur: float, paused: bool) -> void:
	if _session.is_empty() or str(_session.vid) != video_id or Time.get_ticks_msec() - int(_session.last) < REPORT_EVERY:
		return
	_session.last = Time.get_ticks_msec()
	_report("paused" if paused else "playing", pos, dur, paused)


## Ende der Wiedergabe: Plex „stopped“ (und ab 90 % als gesehen), Jellyfin /Sessions/Playing/Stopped.
## Danach lädt die Quelle Weiterschauen neu.
func playback_stopped(video_id: String, pos: float, dur: float) -> void:
	if _session.is_empty() or str(_session.vid) != video_id:
		return
	var s := _session
	_session = {}
	await _report("stopped", pos, dur, false, s)
	if str(s.kind) == "plex" and dur > 0.0 and pos >= dur * 0.9:
		await _plex(Plex.scrobble_path(B.ident(str(s.key), "digits", 1, 12), true), 64 * 1024)
	_load(str(s.kind))


func _report(state: String, pos: float, dur: float, paused: bool, s := {}) -> void:
	var ses: Dictionary = s if not s.is_empty() else _session
	if ses.is_empty():
		return
	match str(ses.kind):
		"plex":
			await _plex(Plex.timeline_path(B.ident(str(ses.key), "digits", 1, 12), state, int(pos * 1000.0), int(dur * 1000.0)), 64 * 1024)
		"jellyfin", "emby":
			var path: String = { "playing": "/Sessions/Playing", "paused": "/Sessions/Playing/Progress", "stopped": "/Sessions/Playing/Stopped" }.get(state,
					"/Sessions/Playing")
			if state == "playing" and pos > 0.0:
				path = "/Sessions/Playing/Progress"
			await _jf(str(ses.kind), str(path), HTTPClient.METHOD_POST, Jf.progress_body(Jf.id_ok(str(ses.key)), str(ses.msid), str(ses.play), pos, paused), 64 * 1024)


## „Gesehen“ an den Server (Movies.set_watched): Plex scrobble/unscrobble, Jellyfin PlayedItems.
func mark_watched(video_ids: Array, on: bool) -> void:
	for vid in video_ids.slice(0, 200):
		var kind := owner_of(str(vid))
		if kind == "" or demo or not connected(kind):
			continue
		var r: Dictionary
		if kind == "plex":
			r = await _plex(Plex.scrobble_path(B.ident(_strip(str(vid)), "digits", 1, 12), on), 64 * 1024)
		else:
			r = await _jf(kind, "/Users/%s/PlayedItems/%s" % [str(_user(kind).get("id", "")), Jf.id_ok(_strip(str(vid)))], HTTPClient.METHOD_POST if on
					else HTTPClient.METHOD_DELETE, null, 64 * 1024)
		# Server nicht erreichbar: aufhören, statt für jede Folge einer Serie noch einmal bis zur Zeitgrenze zu warten.
		if int(r.get("code", 0)) == 0:
			break


# --- Abmelden ------------------------------------------------------------------------------------

## Beim Dienst abmelden, wo er das anbietet (Jellyfin/Emby: Zugang zurückgeben, Stremio: logout).
## Die gespeicherten Einträge leert danach Konten.forget (Einstellungen → Konten).
func logout(kind: String) -> void:
	if demo or not connected(kind):
		_reset(kind)
		return
	match kind:
		"jellyfin", "emby":
			await _jf(kind, "/Sessions/Logout", HTTPClient.METHOD_POST, null, 4096)
		"stremio":
			await _st_post("/logout", { "type": "Logout", "authKey": _tok("stremio.auth") }, 4096)
	_reset(kind)


## Abmelden und alles zur Anmeldung vergessen (Quellen-Seite).
func sign_out(kind: String) -> void:
	await logout(kind)
	Konten.forget(kind, Config.set_value)
	forgotten(kind)
	Config.save_settings()


## Nach Konten.forget: Bilder des Servers sperren, Startseite neu.
func forgotten(kind: String) -> void:
	_reset(kind)
	_register_origins()
	changed.emit()
	rows_ready.emit()

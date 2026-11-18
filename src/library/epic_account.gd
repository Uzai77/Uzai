extends Node
## Epic-Konto: Anmeldung wie Heroic/Legendary (inoffiziell, von Epic nicht unterstützt) und die
## Liste aller gekauften Spiele aus Epics Bibliotheksdienst. Hängt als Kind an der Bibliothek
## (Library.epic_account). Die reinen Teile (Parser, Fehlertexte, Zusammenführen) stehen in
## epic_online.gd.
##
## Gespeichert wird nur die Erneuerungs-Anmeldung (accounts.epic_refresh) wie bei Spotify, dazu
## Name und Konto-ID. Die kurzlebige Zugangs-Anmeldung bleibt im Speicher. Nichts davon landet im
## Protokoll. Die Spieleliste liegt als Zwischenspeicher in epic_konto.json und wird höchstens
## alle SYNC_EVERY Sekunden neu geholt (sofort mit „Jetzt neu einlesen“). Klappt etwas nicht,
## nimmt Uzai still den Zwischenspeicher bzw. nur installierte und Katalogdatei-Spiele.

signal changed

const EpicOnline := preload("res://src/library/epic_online.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const SYNC_EVERY := 6 * 3600
const CACHE_FILE := "epic_konto.json"
const BULK_PARALLEL := 4

## Epic-Konto: aus | bereit | abgelaufen | fehler (Tabelle gemeinsam mit Twitch und YouTube in konten.gd).
var state := "aus":
	set(neu):
		Zustand.wechsel("konto.epic", Konten.ZUSTAENDE_KONTO, state, neu)
		state = neu
var last_error := ""            ## letzter Fehler (Deutsch), "" wenn alles klappte
var _access := ""
var _access_until := 0
var _busy := false
var _cache: Dictionary = {}
var _cache_loaded := false
var _timer: Timer
signal _sync_done
var _erneuert := false          ## ein Erneuern der Anmeldung läuft: weitere Aufrufer warten darauf
signal _token_fertig


func _ready() -> void:
	if logged_in():
		state = "bereit"
	elif account_name() != "":
		state = "abgelaufen"
	_timer = Timer.new()
	_timer.wait_time = 1800.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


## Adressen der Epic-Dienste; UZAI_EPIC_API lenkt alle drei für Netz-Proben auf einen
## nachgebauten Server um (…/account, …/library, …/catalog).
static func host(kind: String) -> String:
	var t := Config.probe_env("UZAI_EPIC_API").trim_suffix("/")
	if t != "":
		return t + "/" + kind
	match kind:
		"account": return EpicOnline.ACCOUNT_HOST
		"library": return EpicOnline.LIBRARY_HOST
	return EpicOnline.CATALOG_HOST


func logged_in() -> bool:
	return str(Config.get_value("accounts.epic_refresh", "")) != ""


func account_name() -> String:
	return str(Config.get_value("accounts.epic_name", ""))


## Kurzer Zustand für die Einstellungen.
func status_text() -> String:
	match state:
		"bereit":
			var n := owned_count()
			return ("Angemeldet: " + account_name()) if n < 0 else "%s · %s" % [account_name(), _plural(n, "Spiel", "Spiele")]
		"fehler": return "Gerade gestört"
		"abgelaufen": return "Abgelaufen – neu anmelden"
	return "Nicht angemeldet"


## Spiele aus dem Konto laut Zwischenspeicher (-1: noch nie geholt).
func owned_count() -> int:
	_load_cache()
	if not _cache.has("games"):
		return -1
	return (_cache.games as Array).size()


func last_sync() -> int:
	_load_cache()
	return int(_cache.get("time", 0))


# --- Anmelden und Abmelden ------------------------------------------------------------------

## Code (oder die ganze JSON-Antwort der Epic-Seite) gegen eine Anmeldung tauschen.
## Ergebnis: { ok, error }.
func login_with_code(text: String) -> Dictionary:
	var c := EpicOnline.extract_code(text)
	if str(c.code) == "":
		return { "ok": false, "error": str(c.error) }
	var r := await Net.post_form(host("account") + "/account/api/oauth/token",
		{ "grant_type": "authorization_code", "code": str(c.code), "token_type": "eg1" },
		PackedStringArray([EpicOnline.basic_auth()]))
	var t := EpicOnline.parse_token(int(r.code), r.data, _now())
	if not bool(t.ok):
		_log("Anmeldung abgelehnt (%d %s)" % [int(r.code), str(t.get("epic_code", ""))])
		return { "ok": false, "error": str(t.error) }
	var before := str(Config.get_value("accounts.epic_account_id", ""))
	if before != "" and before != str(t.account_id):
		_drop_cache()
	_take(t)
	Config.set_value("accounts.epic_name", str(t.name) if str(t.name) != "" else "Epic-Konto")
	Config.set_value("accounts.epic_account_id", str(t.account_id))
	state = "bereit"
	last_error = ""
	_log("angemeldet")
	changed.emit()
	return { "ok": true, "error": "" }


## Abmelden: Epic bekommt Bescheid (falls erreichbar), Uzai vergisst Anmeldung und Liste.
func logout() -> void:
	var tok := _access
	_access = ""
	_access_until = 0
	Config.set_value("accounts.epic_refresh", "")
	Config.set_value("accounts.epic_name", "")
	Config.set_value("accounts.epic_account_id", "")
	_drop_cache()
	state = "aus"
	last_error = ""
	_log("abgemeldet")
	changed.emit()
	if tok != "":
		Net.request(host("account") + "/account/api/oauth/sessions/kill/" + tok.uri_encode(),
			PackedStringArray(["Authorization: Bearer " + tok]), HTTPClient.METHOD_DELETE, "", 8.0)


func _take(t: Dictionary) -> void:
	_access = str(t.access)
	_access_until = int(t.expires_at)
	Config.set_value("accounts.epic_refresh", str(t.refresh))


## Zugangs-Anmeldung für Uzais eigenen Installer (epic_install.gd): nur für Epics Kopfzeile, nie
## ins Protokoll oder in eine Kommandozeile. "" ohne gültige Anmeldung.
func access_token() -> String:
	return await _token()


## Einmal-Code für die Epic-Anmeldung im Spiel (Exchange-Code, wie Legendary und Heroic ihn
## übergeben): für jeden Start frisch bei Epic geholt, nie gespeichert, nie im Protokoll, nur für
## die Befehlszeile genau des Spiels, das gleich startet (epic_install.gd, start_argv). Lehnt Epic
## die Zugangs-Anmeldung ab, erneuert Uzai sie einmal auf dem üblichen Weg. "" wenn es nicht ging –
## dann startet das Spiel ohne.
func exchange_code() -> String:
	if not logged_in():
		return ""
	for attempt in 2:
		var tok := await _token()
		if tok == "":
			return ""
		var r := await Net.request(exchange_url(), PackedStringArray(["Authorization: Bearer " + tok]), HTTPClient.METHOD_GET, "",
			8.0, "api", EpicOnline.EXCHANGE_MAX_BYTES, false)
		var code := EpicOnline.parse_exchange(int(r.code), Net._decode(r).data)
		if code != "":
			return code
		if int(r.code) == 401 and attempt == 0:
			# Zugang abgelaufen oder widerrufen: einmal erneuern, dann nochmal fragen.
			_access = ""
			_access_until = 0
			continue
		# Nur der HTTP-Code ins Protokoll – nie die Antwort (sie könnte den Code enthalten).
		_log("Einmal-Code für den Spielstart nicht bekommen (%d)" % int(r.code))
		return ""
	return ""


## Adresse für den Einmal-Code: nur Epics Anmeldedienst über https. Für Netz-Proben lenkt
## UZAI_EPIC_API sie um – aber nur zusammen mit UZAI_TEST_LOOPBACK=1 und nur auf 127.0.0.1.
static func exchange_url() -> String:
	var t := Config.probe_env("UZAI_EPIC_API").trim_suffix("/")
	if t.begins_with("http://127.0.0.1:") and Config.probe_env("UZAI_TEST_LOOPBACK") == "1":
		return t + "/account/account/api/oauth/exchange"
	return EpicOnline.ACCOUNT_HOST + "/account/api/oauth/exchange"


## Gültige Zugangs-Anmeldung, bei Bedarf erneuert ("" wenn das nicht ging).
func _token() -> String:
	if _access != "" and _access_until - 120 > _now():
		return _access
	# Nur ein Erneuern zugleich: Epic tauscht dabei auch die gespeicherte Anmeldung aus. Ein zweiter Abruf mit der
	# alten (ein Spielstart, während die Liste aufgefrischt wird) würde abgelehnt – und Uzai hielte die Anmeldung
	# für abgelaufen.
	if _erneuert:
		await _token_fertig
		return _access if _access_until - 120 > _now() else ""
	var refresh := str(Config.get_value("accounts.epic_refresh", ""))
	if refresh == "":
		return ""
	_erneuert = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem gelöst und gemeldet. Sonst
	# warteten alle späteren Abrufe für immer.
	await _erneuern(refresh)
	_erneuert = false
	_token_fertig.emit()
	return _access if _access_until - 120 > _now() else ""


## Holt mit der gespeicherten Anmeldung einen neuen Zugang (nur aus _token, siehe dort).
func _erneuern(refresh: String) -> void:
	var r := await Net.post_form(host("account") + "/account/api/oauth/token",
		{ "grant_type": "refresh_token", "refresh_token": refresh, "token_type": "eg1" },
		PackedStringArray([EpicOnline.basic_auth()]))
	var t := EpicOnline.parse_token(int(r.code), r.data, _now())
	if not bool(t.ok):
		last_error = str(t.error)
		_log("Erneuern abgelehnt (%d %s)" % [int(r.code), str(t.get("epic_code", ""))])
		if bool(t.expired):
			# Die gespeicherte Anmeldung ist nichts mehr wert; der Name bleibt für den Hinweis.
			Config.set_value("accounts.epic_refresh", "")
			state = "abgelaufen"
		else:
			state = "fehler"
		return
	_take(t)
	if str(t.name) != "" and str(t.name) != account_name():
		Config.set_value("accounts.epic_name", str(t.name))


# --- Gekaufte Spiele ------------------------------------------------------------------------

## Gekaufte Spiele aus dem Konto (nicht installiert, Form wie aus catcache.bin). force: sofort neu
## holen, sonst nur, wenn der Zwischenspeicher älter als SYNC_EVERY ist. Ohne Anmeldung [];
## klappt das Holen nicht, die letzte bekannte Liste.
func owned_games(force := false) -> Array:
	if not logged_in():
		_load_cache()
		# Abgelaufen: die zuletzt bekannte Liste bleibt sichtbar (gekauft ist gekauft).
		return (_cache.get("games", []) as Array).duplicate(true) if state == "abgelaufen" else []
	_load_cache()
	if force or _now() - int(_cache.get("time", 0)) >= SYNC_EVERY or not _cache.has("games"):
		await sync()
	return (_cache.get("games", []) as Array).duplicate(true)


## Liste neu holen: alle Seiten der Bibliothek, dann der Katalog für neue Einträge. true = geklappt.
func sync() -> bool:
	if _busy:
		await _sync_done
		return last_error == ""
	_busy = true
	var ok := await _sync()
	_busy = false
	_sync_done.emit()
	changed.emit()
	return ok


func _sync() -> bool:
	var tok := await _token()
	if tok == "":
		if last_error == "":
			last_error = "Nicht bei Epic angemeldet."
		return false
	var auth := PackedStringArray(["Authorization: Bearer " + tok])
	var records: Array = []
	var cursor := ""
	var seen_cursor := {}
	for page in 200:
		var url := host("library") + "/library/api/public/items?includeMetadata=true"
		if cursor != "":
			url += "&cursor=" + cursor.uri_encode()
		var r := await Net.get_json(url, auth)
		var p := EpicOnline.parse_library_page(r.data)
		if not r.ok or not bool(p.ok):
			return _fail(int(r.code), r.data, "Bibliothek")
		records.append_array(p.records)
		cursor = str(p.cursor)
		if cursor == "" or seen_cursor.has(cursor):
			break
		seen_cursor[cursor] = true
	var catalog: Dictionary = (_cache.get("catalog", {}) as Dictionary).duplicate()
	var want := EpicOnline.missing_items(records, catalog)
	var jobs: Array = []
	for ns in want.keys():
		var ids: Array = want[ns]
		for i in range(0, ids.size(), EpicOnline.BULK_CHUNK):
			jobs.append([str(ns), ids.slice(i, i + EpicOnline.BULK_CHUNK)])
	# Höchstens BULK_PARALLEL Anfragen gleichzeitig (andere Dienste sollen nicht warten).
	var box := { "next": 0, "left": jobs.size(), "fail": [] }
	for w in mini(BULK_PARALLEL, jobs.size()):
		_bulk_worker(jobs, box, auth, catalog)
	while int(box.left) > 0 and (box.fail as Array).is_empty():
		await get_tree().process_frame
	if not (box.fail as Array).is_empty():
		return _fail(int(box.fail[0]), box.fail[1], "Katalog")
	var asked := jobs.size()
	var games := EpicOnline.owned_games(records, catalog)
	_cache = { "v": 1, "account": str(Config.get_value("accounts.epic_account_id", "")), "time": _now(),
		"records": records, "catalog": catalog, "games": games }
	Config.write_json(Config.path(CACHE_FILE), _cache)
	state = "bereit"
	last_error = ""
	_log("%d Einträge, %d Katalog-Anfragen, %s" % [records.size(), asked, _plural(games.size(), "Spiel", "Spiele")])
	return true


func _bulk_worker(jobs: Array, box: Dictionary, auth: PackedStringArray, catalog: Dictionary) -> void:
	while int(box.next) < jobs.size() and (box.fail as Array).is_empty():
		var job: Array = jobs[int(box.next)]
		box.next = int(box.next) + 1
		# Je Anfrage eine eigene Funktion: Bricht sie mit einem Fehler ab, zählt dieser Läufer trotzdem herunter und
		# nimmt die nächste. Sonst wartete sync() für immer auf Anfragen, die niemand mehr stellt.
		await _bulk_eine(job, box, auth, catalog)
		box.left = int(box.left) - 1


func _bulk_eine(job: Array, box: Dictionary, auth: PackedStringArray, catalog: Dictionary) -> void:
	var r := await Net.get_json(EpicOnline.bulk_url(host("catalog"), str(job[0]), job[1]), auth)
	if not r.ok:
		# Ein einzelner Namespace, den der Katalog nicht kennt, ist kein Grund aufzugeben;
		# kein Netz, abgelaufene Anmeldung, Bremse oder Störung schon.
		if int(r.code) in [0, 401, 429] or int(r.code) >= 500:
			box.fail = [int(r.code), r.data]
		return
	for it in EpicOnline.parse_bulk(r.data):
		catalog[str(it.id)] = it


func _fail(code: int, data: Variant, what: String) -> bool:
	var e := EpicOnline.error_info(code, data)
	last_error = str(e.error)
	if bool(e.expired):
		_access = ""
		_access_until = 0
	state = "fehler"
	_log("%s: Fehler %d %s" % [what, code, str(e.epic_code)])
	return false


func _load_cache() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	var d: Variant = Config.read_json(Config.path(CACHE_FILE), {})
	_cache = d if d is Dictionary else {}
	# Liste eines anderen Kontos (neu angemeldet) gilt nicht.
	var acc := str(Config.get_value("accounts.epic_account_id", ""))
	if acc != "" and str(_cache.get("account", acc)) != acc:
		_cache = {}
	for k in ["games", "records"]:
		if _cache.has(k) and not (_cache[k] is Array):
			_cache.erase(k)
	if _cache.has("catalog") and not (_cache.catalog is Dictionary):
		_cache.erase("catalog")


func _drop_cache() -> void:
	_cache = {}
	_cache_loaded = true
	var p := Config.path(CACHE_FILE)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## Läuft Uzai lange am Stück: alle paar Stunden die Liste auffrischen.
func _tick() -> void:
	if not logged_in() or _busy:
		return
	_load_cache()
	if _now() - int(_cache.get("time", 0)) >= SYNC_EVERY and get_parent().has_method("refresh_epic"):
		get_parent().refresh_epic()


static func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Protokoll ohne Anmeldedaten (logs/bibliothek.log).
func _log(text: String) -> void:
	if get_parent() and get_parent().has_method("scan_log"):
		get_parent().scan_log("Epic-Konto: " + text)

extends Node
## Netz-Probe für den Einmal-Code beim Start von Epic-Spielen, die Uzai installiert hat (wie
## Legendary: GET …/account/api/oauth/exchange mit der vorhandenen Anmeldung): gegen den
## nachgebauten Dienst tests/fake_epic.py – jeder Start ein frischer Code, böse Antworten,
## abgelaufener Zugang (einmal erneuern), abgelaufene Anmeldung, nichts davon in Dateien.
## Aufruf (eigener, leerer Datenordner, freier Port):
##   python3 tests/fake_epic.py 18821 &
##   UZAI_DATA=<ordner> UZAI_TEST_LOOPBACK=1 UZAI_EPIC_API=http://127.0.0.1:18821 godot --headless --path . res://tests/net_epic_spielcode.tscn

const EI := preload("res://src/core/epic_install.gd")
const EpicOnline := preload("res://src/library/epic_online.gd")
const GOOD := "0123456789abcdef0123456789abcdef"

var fails := 0
var base := ""
var acc: Node
var codes: Array = []


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	base = OS.get_environment("UZAI_EPIC_API")
	if base == "" or OS.get_environment("UZAI_TEST_LOOPBACK") != "1":
		print("UZAI_EPIC_API oder UZAI_TEST_LOOPBACK=1 fehlt")
		get_tree().quit(1)
		return
	acc = Library.epic_account
	await _run()
	# Die ruhige Mitteilung („Ohne Epic-Anmeldung gestartet“) erst ausklingen lassen.
	await get_tree().create_timer(8.0).timeout
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _log() -> Array:
	var r := await Net.get_json(base + "/__log")
	return r.data if r.data is Array else []


func _fake(q: String) -> void:
	await Net.get_json(base + "/__set?" + q)


func _hits(log: Array, path: String) -> Array:
	return log.filter(func(e): return str(e.p) == path)


func _run() -> void:
	print("Ohne Anmeldung")
	check(await acc.exchange_code() == "" and (await _log()).is_empty(), "nicht verbunden: kein Code, keine Anfrage")
	var g := { "id": "epic:Kinglet", "source": "epic", "epic_uzai": true, "epic": { "app": "Kinglet", "namespace": "ns-kinglet" } }
	var r: Dictionary = await acc.login_with_code(GOOD)
	check(bool(r.ok) and acc.logged_in(), "angemeldet (Probe-Konto)")
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST)

	print("Einmal-Code holen")
	var c1: String = await acc.exchange_code()
	var c2: String = await acc.exchange_code()
	codes.append_array([c1, c2])
	check(EpicOnline.exchange_ok(c1) and EpicOnline.exchange_ok(c2) and c1 != c2, "jeder Start ein frischer Code (%d Zeichen)" % c1.length())
	var log := await _log()
	var ex := _hits(log, "/account/account/api/oauth/exchange")
	check(ex.size() == 2 and ex.all(func(e): return str(e.m) == "GET" and str(e.auth) == "Bearer a1"), "GET oauth/exchange mit der Zugangs-Anmeldung")
	check(_hits(log, "/account/account/api/oauth/token").is_empty(), "gültiger Zugang: keine Erneuerung nötig")
	var argv := EI.launch_argv(g, c1)
	check(argv.has("-AUTH_PASSWORD=" + c1) and argv.has("-AUTH_TYPE=exchangecode") and argv.has("-AUTH_LOGIN=unused")
		and argv.has("-epicapp=Kinglet") and argv.has("-epicuserid=acc1") and argv.has("-epicusername=Spieler"), "Startparameter mit Code und Konto")

	print("Böse Antworten")
	for x in ["space", "quote", "amp", "nl", "long", "num", "list", "html", "big", "500"]:
		await _fake("x=" + x)
		var c: String = await acc.exchange_code()
		check(c == "", "%s: kein Code, Spiel startet ohne" % x)
	await _fake("x=ok")

	print("Zugang abgelaufen: einmal erneuern")
	acc._access = "abgelaufen"
	acc._access_until = int(Time.get_unix_time_from_system()) + 3600
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST)
	var c3: String = await acc.exchange_code()
	codes.append(c3)
	log = await _log()
	var tok := _hits(log, "/account/account/api/oauth/token")
	check(EpicOnline.exchange_ok(c3) and tok.size() == 1 and str(tok[0].grant) == "refresh_token", "401 → Erneuerung über den üblichen Weg → Code")
	check(_hits(log, "/account/account/api/oauth/exchange").size() == 2 and str(_hits(log, "/account/account/api/oauth/exchange")[1].auth) == "Bearer a2",
		"zweite Anfrage mit dem neuen Zugang")

	print("Anmeldung abgelaufen")
	acc._access = "abgelaufen"
	await _fake("dead=1")
	var c4: String = await acc.exchange_code()
	check(c4 == "" and str(acc.state) == "abgelaufen" and not acc.logged_in(), "Erneuern abgelehnt: kein Code, Zustand „abgelaufen“")
	await Net.request(base + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST)
	check(await acc.exchange_code() == "" and _hits(await _log(), "/account/account/api/oauth/exchange").is_empty(), "danach keine Anfrage mehr")
	var a2: PackedStringArray = await EI.start_argv(g, "D:/Spiele/Kinglet/Kinglet.exe")
	check(not "|".join(a2).contains("AUTH") and a2.has("-epicapp=Kinglet"), "Start trotzdem, nur ohne Code")
	await _fake("dead=0")

	print("Adresse nur mit Probe-Schalter umgelenkt")
	OS.set_environment("UZAI_TEST_LOOPBACK", "0")
	check(acc.exchange_url() == EpicOnline.ACCOUNT_HOST + "/account/api/oauth/exchange", "ohne UZAI_TEST_LOOPBACK=1: Epics https-Adresse")
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	OS.set_environment("UZAI_EPIC_API", "http://example.com:1")
	check(acc.exchange_url() == EpicOnline.ACCOUNT_HOST + "/account/api/oauth/exchange", "fremder Host in UZAI_EPIC_API: Epics https-Adresse")
	OS.set_environment("UZAI_EPIC_API", base)

	print("Nichts gespeichert, nichts protokolliert")
	var found := _scan(OS.get_environment("UZAI_DATA"))
	check(found == "", "kein Code in irgendeiner Datei im Datenordner%s" % ("" if found == "" else " (" + found + ")"))
	var blog := Config.path("logs/bibliothek.log")
	var bl := FileAccess.get_file_as_string(blog) if FileAccess.file_exists(blog) else ""
	check(bl.contains("Einmal-Code für den Spielstart nicht bekommen (500)") and not bl.contains("Bearer"), "Protokoll: nur der HTTP-Code")


## Sucht die geholten Codes in allen Dateien unter dir; gibt den ersten Fundort zurück.
func _scan(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		var p := dir.path_join(f)
		var t := FileAccess.get_file_as_bytes(p).get_string_from_ascii()
		for c in codes:
			if str(c) != "" and t.contains(str(c)):
				return p
	for sd in d.get_directories():
		var r := _scan(dir.path_join(sd))
		if r != "":
			return r
	return ""

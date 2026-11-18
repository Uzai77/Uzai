extends Node
## Netz-Probe für den Netzfaden (src/core/abruf.gd) und Net.request darüber: jede Art Antwort gegen den nachgebauten
## Server tests/fake_netz.py (nur 127.0.0.1), mit und ohne TLS. Vor allem: Ein Server, der schweigt, führt zu einer
## Zeitüberschreitung – und der Hauptfaden läuft dabei weiter (mit Godots HTTPRequest fror Uzai dort ein).
## Aufruf: UZAI_DATA=<ordner> godot --headless --path . res://tests/net_abruf.tscn

const Abruf := preload("res://src/core/abruf.gd")
const Fremd := preload("res://src/core/fremd.gd")

const PORT := 18831
const PORT_TLS := 18832

var fails := 0
var _srv: Array[int] = []
var _bilder := 0      ## zählt Bilder des Hauptfadens: steht er, steht auch das


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _process(_dt: float) -> void:
	_bilder += 1


func _ready() -> void:
	await _run()
	for p in _srv:
		OS.kill(p)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	# Beenden mit einem Abruf, der noch eine Minute warten würde: Uzai muss trotzdem sofort gehen (der Aufrufer der
	# Probe sähe sonst eine Zeitüberschreitung statt des Ergebnisses).
	var offen := Abruf.Auftrag.new()
	offen.url = "http://127.0.0.1:%d/still" % PORT
	offen.frist_ms = 60000
	Abruf.starten(offen)
	get_tree().quit(1 if fails > 0 else 0)


func _hole(pfad: String, frist := 5.0, grenze := 0, folgen := true, kopf := PackedStringArray(), methode := HTTPClient.METHOD_GET, inhalt := "",
		port := PORT, tls := false) -> Dictionary:
	var a := Abruf.Auftrag.new()
	a.url = "%s://%s:%d%s" % ["https" if tls else "http", "localhost" if tls else "127.0.0.1", port, pfad]
	a.frist_ms = int(frist * 1000.0)
	a.grenze = grenze
	a.folgen = folgen
	a.kopf = kopf
	a.methode = methode
	a.inhalt = inhalt
	return await Abruf.holen(a)


func _text(r: Dictionary) -> String:
	return (r.body as PackedByteArray).get_string_from_utf8()


func _run() -> void:
	_adressen()
	_srv.append(OS.create_process("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/fake_netz.py"), str(PORT)])))
	await get_tree().create_timer(1.5).timeout
	await _antworten()
	await _senden()
	await _umleitungen()
	await _grenzen()
	await _schweigen()
	await _viele()
	await _plaetze()
	await _dateien()
	await _tls()


func _adressen() -> void:
	print("Adressen zerlegen")
	var z := Abruf.adresse("https://api.example.com/v1/x?a=1&b=2#stelle")
	check(z.tls == true and z.host == "api.example.com" and z.port == 443 and z.pfad == "/v1/x?a=1&b=2",
			"https: Host, Anschluss 443, Pfad mit Abfrage, ohne Anker")
	z = Abruf.adresse("http://127.0.0.1:8080")
	check(z.tls == false and z.host == "127.0.0.1" and z.port == 8080 and z.pfad == "/", "http mit Anschluss, leerer Pfad wird /")
	check(Abruf.adresse("http://Example.com?x=1").pfad == "/?x=1" and Abruf.adresse("https://[::1]:9/a").host == "::1"
			and Abruf.adresse("https://u:p@h.de/x").host == "h.de",
			"Abfrage ohne Pfad, IPv6, Name und Passwort vor dem Host fallen weg")
	check(Abruf.adresse("ftp://x/y").is_empty() and Abruf.adresse("kein link").is_empty() and Abruf.adresse("https://").is_empty()
			and Abruf.adresse("file:///C:/x").is_empty(),
			"nur http und https, nur mit Host")


func _antworten() -> void:
	print("Gewöhnliche Antworten")
	var r := await _hole("/json")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 200 and Fremd.verz(Fremd.json(_text(r))).get("titel") == "Uzai",
			"JSON mit Längenangabe")
	check(Array(r.headers).any(func(h: String) -> bool: return h.to_lower().begins_with("content-type: application/json")), "Kopfzeilen der Antwort kommen mit")
	r = await _hole("/gzip")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and Fremd.verz(Fremd.json(_text(r))).get("zahl") == 7.0, "gepackt (gzip): entpackt")
	r = await _hole("/deflate")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and Fremd.verz(Fremd.json(_text(r))).get("zahl") == 7.0, "gepackt (deflate): entpackt")
	r = await _hole("/stuecke")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and Fremd.verz(Fremd.json(_text(r))).get("titel") == "Uzai", "in Stücken (chunked): ganz zusammengesetzt")
	r = await _hole("/ohne-laenge")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and Fremd.verz(Fremd.json(_text(r))).get("titel") == "Uzai", "ohne Längenangabe: bis der Server schließt")
	r = await _hole("/leer")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 204 and (r.body as PackedByteArray).is_empty(), "204 ohne Inhalt")
	r = await _hole("/404")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 404 and _text(r).contains("gibt es nicht"),
			"404: Code und Text des Dienstes kommen an")
	r = await _hole("/json", 5.0, 0, true, PackedStringArray(), HTTPClient.METHOD_HEAD)
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 200 and (r.body as PackedByteArray).is_empty(), "HEAD: nur der Kopf")


func _senden() -> void:
	print("Senden")
	var r: Dictionary
	r = await _hole("/echo", 5.0, 0, true, PackedStringArray(["X-Probe: ja", "Content-Type: application/json", "User-Agent: Probe/1"]), HTTPClient.METHOD_POST,
			"{\"gruß\": \"hallo\"}")
	var e := Fremd.verz(Fremd.json(_text(r)))
	check(e.get("methode") == "POST" and e.get("inhalt") == "{\"gruß\": \"hallo\"}" and e.get("probe") == "ja" and e.get("typ") == "application/json",
			"POST: Inhalt (UTF-8) und Kopfzeilen kommen an")
	check(e.get("agent") == "Probe/1" and str(e.get("packen", "")).contains("gzip") and e.get("host") == "127.0.0.1:%d" % PORT,
			"eigener User-Agent bleibt, Packen wird angeboten, Host stimmt")
	r = await _hole("/echo", 5.0, 0, true, PackedStringArray(), HTTPClient.METHOD_PUT, "abc")
	check(Fremd.verz(Fremd.json(_text(r))).get("methode") == "PUT" and Fremd.verz(Fremd.json(_text(r))).get("laenge") == "3", "PUT mit Längenangabe")
	var n := await Net.request("http://127.0.0.1:%d/echo" % PORT, PackedStringArray(), HTTPClient.METHOD_POST, "")
	e = Fremd.verz(Fremd.json((n.body as PackedByteArray).get_string_from_utf8()))
	check(bool(n.ok) and e.get("laenge") == "0" and str(e.get("agent", "")).begins_with("Uzai/"), "Net.request: leeres POST mit Länge 0 und Uzais User-Agent")
	var j := await Net.get_json("http://127.0.0.1:%d/gzip" % PORT)
	check(bool(j.ok) and j.data is Dictionary and not j.data.has("leer") and j.data.liste[2] == {}, "Net.get_json: gepackt, gelesen, null heißt fehlt")


func _umleitungen() -> void:
	print("Umleitungen")
	var r: Dictionary
	r = await _hole("/um/1")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 200 and Fremd.verz(Fremd.json(_text(r))).get("titel") == "Uzai",
			"302 → 301 (Ziel neben der Seite) → 302 (volle Adresse): am Ende die Antwort")
	r = await _hole("/um/1", 5.0, 0, false)
	check(int(r.result) == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and int(r.code) == 302 and Abruf._wert(r.headers, "location") == "/um/2",
			"ohne Folgen: endet an der Umleitung, Code und Ziel stehen im Ergebnis")
	r = await _hole("/um/schleife")
	check(int(r.result) == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, "Schleife: nach %d Umleitungen Schluss" % Abruf.UMLEITUNGEN_MAX)
	r = await _hole("/um/ohne-ziel")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 302 and _text(r).contains("ohne Ziel"), "302 ohne Ziel: gewöhnliche Antwort")
	r = await _hole("/307")
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and int(r.code) == 307, "307 folgt Uzai nicht von selbst (wie bisher): Code kommt an")
	# Zugangsdaten gehen bei einer Umleitung nie an einen anderen Ursprung (anderer Host, anderer Anschluss).
	var mit := PackedStringArray(["Authorization: Bearer geheim", "X-API-Key: auch-geheim", "X-Probe: ja", "User-Agent: Uzai-Probe", "Accept: application/json"])
	r = await _hole("/um/gleich", 5.0, 0, true, mit)
	var e1 := Fremd.verz(Fremd.json(_text(r)))
	check(str(e1.get("zugang", "")) == "Bearer geheim" and str(e1.get("schluessel", "")) == "auch-geheim" and str(e1.get("probe", "")) == "ja",
			"Umleitung am selben Ursprung: die Kopfzeilen gehen mit")
	r = await _hole("/um/fremd", 5.0, 0, true, mit)
	var e2 := Fremd.verz(Fremd.json(_text(r)))
	check(int(r.code) == 200 and str(e2.get("host", "")).begins_with("localhost") and not e2.has("zugang") and not e2.has("schluessel") and not e2.has("probe")
			and str(e2.get("agent", "")) == "Uzai-Probe", "Umleitung zu einem anderen Ursprung: ohne Zugang und Schlüssel, nur das Harmlose (%s)" % str(e2))
	r = await _hole("/um/fremd", 5.0, 0, true, mit, HTTPClient.METHOD_POST, "refresh_token=geheim")
	check(int(r.result) == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and int(r.code) == 302,
			"Formular (POST) an einen anderen Ursprung weitergeleitet: Uzai folgt nicht")
	check(Abruf.harmlos(mit) == PackedStringArray(["User-Agent: Uzai-Probe", "Accept: application/json"]), "harmlos: nur Agent und Accept bleiben")


func _grenzen() -> void:
	print("Grenzen")
	var r: Dictionary
	r = await _hole("/gross?n=300000", 5.0, 100000)
	check(int(r.result) == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED and (r.body as PackedByteArray).is_empty(),
			"zu groß laut Längenangabe: gar nicht erst gelesen")
	r = await _hole("/gross?n=300000", 5.0, 300000)
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and (r.body as PackedByteArray).size() == 300000 and r.body[257] == 1,
			"genau an der Grenze: ganz und unverändert")
	r = await _hole("/bombe", 10.0, 2 * 1024 * 1024)
	check(int(r.result) == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "kleine Antwort, die sich zu 40 MB entpackt: bei 2 MB Schluss")
	r = await _hole("/kaputt-gepackt")
	check(int(r.result) == HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED, "als gepackt gemeldet, ist es aber nicht: Fehler statt Datenmüll")


func _schweigen() -> void:
	print("Server schweigt")
	var r: Dictionary
	var bilder := _bilder
	var t0 := Time.get_ticks_msec()
	r = await _hole("/still", 1.5)
	var dauer := Time.get_ticks_msec() - t0
	check(int(r.result) == HTTPRequest.RESULT_TIMEOUT and dauer >= 1500 and dauer < 4000,
			"nimmt an und antwortet nie: Zeitüberschreitung nach der Frist (%d ms)" % dauer)
	check(_bilder - bilder > 20, "der Hauptfaden lief dabei weiter (%d Bilder; mit HTTPRequest stand er hier für immer)" % (_bilder - bilder))
	t0 = Time.get_ticks_msec()
	r = await _hole("/halb", 1.5)
	check(int(r.result) == HTTPRequest.RESULT_TIMEOUT and Time.get_ticks_msec() - t0 < 4000, "bricht mitten in der Antwort ab zu senden: Zeitüberschreitung")
	t0 = Time.get_ticks_msec()
	r = await _hole("/langsam", 1.5)
	check(int(r.result) == HTTPRequest.RESULT_TIMEOUT and Time.get_ticks_msec() - t0 < 4000, "tropft länger als die Frist: die Frist gilt für das Ganze")
	r = await _hole("/abriss")
	check(int(r.result) != HTTPRequest.RESULT_SUCCESS, "Server schließt mitten in der Antwort: kein Erfolg mit halbem Inhalt")
	var zu := Abruf.Auftrag.new()
	zu.url = "http://127.0.0.1:%d/json" % (PORT + 7)
	zu.frist_ms = 4000
	var rz := await Abruf.holen(zu)
	check(int(rz.result) in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TIMEOUT],
			"niemand lauscht: Fehler statt Warten ohne Ende")
	var falsch := Abruf.Auftrag.new()
	falsch.url = "kein link"
	check(int((await Abruf.holen(falsch)).result) == Abruf.NICHT_GESENDET, "keine Adresse: gar nicht erst gesendet")
	var net_still := await Net.request("http://127.0.0.1:%d/still" % PORT, PackedStringArray(), HTTPClient.METHOD_GET, "", 1.0)
	check(not bool(net_still.ok) and int(net_still.code) == 0 and int(net_still.result) == HTTPRequest.RESULT_TIMEOUT and Net.fails > 0,
			"Net.request: nicht ok, Code 0, zählt als Netzausfall")


func _viele() -> void:
	print("Viele zugleich")
	var t0 := 0
	var box := { "fertig": 0, "gut": 0 }
	t0 = Time.get_ticks_msec()
	for i in 24:
		_einer(box, "/gross?n=%d" % (20000 + i * 1000), 20000 + i * 1000)
	_einer_still(box)
	while int(box.fertig) < 25 and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	check(int(box.fertig) == 25 and int(box.gut) == 25, "24 Abrufe und ein schweigender Server zugleich: alle richtig (%d von 25)" % int(box.gut))


## Mehr Abrufe als Plätze auf einer Spur (Net.request): nie mehr zugleich als erlaubt, alle kommen an, am Ende ist
## die Spur frei. Wer wartet, bekommt seinen Platz gezielt übergeben – früher weckte jeder beendete Abruf alle
## wartenden. Und: Wer dasselbe Ziel lädt (Net.download), wartet auf den einen Download und bekommt dessen Ergebnis.
func _plaetze() -> void:
	print("Plätze je Spur und doppelte Downloads")
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	var grenze := int(Net.MAX_PARALLEL["img"])
	var box := { "fertig": 0, "gut": 0, "hoch": 0, "wartend": 0 }
	for i in 60:
		_platz_einer(box, i)
	box.wartend = (Net._schlange["img"] as Array).size()
	var t0 := Time.get_ticks_msec()
	while int(box.fertig) < 60 and Time.get_ticks_msec() - t0 < 20000:
		box.hoch = maxi(int(box.hoch), int(Net._running["img"]))
		await get_tree().process_frame
	check(int(box.gut) == 60, "60 Abrufe auf einer Spur mit %d Plätzen: alle richtig (%d von 60)" % [grenze, int(box.gut)])
	check(int(box.wartend) == 60 - grenze and int(box.hoch) == grenze, "die übrigen %d stellen sich an, nie laufen mehr als %d (höchstens %d gesehen)"
			% [int(box.wartend), grenze, int(box.hoch)])
	check(int(Net._running["img"]) == 0 and (Net._schlange["img"] as Array).is_empty(), "danach ist die Spur frei und niemand wartet mehr")
	# Reihenfolge, ohne Netz: Drei stellen sich an; jeder frei werdende Platz geht an den, der am längsten wartet,
	# und der Zähler bleibt dabei belegt. Erst wenn niemand mehr wartet, wird ein Platz frei.
	var warten_klasse: GDScript = load("res://src/core/net.gd").get("_Warten")
	var reihe: Array = []
	var voll := int(Net.MAX_PARALLEL["yt"])
	Net._running["yt"] = voll
	for i in 3:
		var w: RefCounted = warten_klasse.new()
		w.connect("dran", func() -> void: reihe.append(i))
		(Net._schlange["yt"] as Array).append(w)
	Net._platz_frei("yt")
	Net._platz_frei("yt")
	check(reihe == [0, 1] and int(Net._running["yt"]) == voll, "ein freier Platz geht an den, der am längsten wartet; der Zähler bleibt belegt")
	Net._platz_frei("yt")
	Net._platz_frei("yt")
	check(reihe == [0, 1, 2] and int(Net._running["yt"]) == voll - 1 and (Net._schlange["yt"] as Array).is_empty(),
			"wartet niemand mehr, wird der Platz frei")
	Net._running["yt"] = 0
	var ziel := Config.path("abruf/doppelt.bin")
	DirAccess.make_dir_recursive_absolute(ziel.get_base_dir())
	var erg: Array = []
	for i in 5:
		_lade(erg, "http://127.0.0.1:%d/gross?n=50000" % PORT, ziel)
	t0 = Time.get_ticks_msec()
	while erg.size() < 5 and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	check(erg.size() == 5 and erg.all(func(p: String) -> bool: return p == ziel) and FileAccess.get_file_as_bytes(ziel).size() == 50000,
			"fünfmal dasselbe Ziel: ein Download, alle fünf bekommen die Datei")
	var fehlt := Config.path("abruf/fehlt.bin")
	erg = []
	for i in 3:
		_lade(erg, "http://127.0.0.1:%d/404" % PORT, fehlt)
	t0 = Time.get_ticks_msec()
	while erg.size() < 3 and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	check(erg.size() == 3 and erg.all(func(p: String) -> bool: return p == "") and not FileAccess.file_exists(fehlt),
			"scheitert der Download, erfahren es auch die Wartenden; nichts bleibt liegen")
	check(Net._inflight.is_empty(), "danach wartet niemand mehr auf einen Download")


func _platz_einer(box: Dictionary, i: int) -> void:
	var r := await Net.request("http://127.0.0.1:%d/gross?n=%d" % [PORT, 3000 + i], PackedStringArray(), HTTPClient.METHOD_GET, "", 10.0, "img")
	box.fertig = int(box.fertig) + 1
	if bool(r.ok) and (r.body as PackedByteArray).size() == 3000 + i:
		box.gut = int(box.gut) + 1


func _lade(erg: Array, url: String, ziel: String) -> void:
	erg.append(await Net.download(url, ziel))


func _dateien() -> void:
	print("Abbrechen und in eine Datei laden")
	var t0 := 0
	var dauer := 0
	var ziel := Config.path("abruf/gross.bin")
	DirAccess.make_dir_recursive_absolute(ziel.get_base_dir())
	OS.set_environment("UZAI_TEST_LOOPBACK", "1")
	var stand := { "letzter": 0, "gesamt": 0 }
	var gut: bool = await Net.download_big("http://127.0.0.1:%d/gross?n=3000000" % PORT, ziel, func(got: int, total: int) -> void:
		stand.letzter = got
		stand.gesamt = total)
	check(gut and FileAccess.file_exists(ziel) and FileAccess.get_file_as_bytes(ziel).size() == 3000000 and not FileAccess.file_exists(ziel + ".part"),
			"große Datei: ganz da, kein Rest")
	check(FileAccess.get_file_as_bytes(ziel)[65537] == 1, "Inhalt unverändert")
	var stop := { "stop": false }
	get_tree().create_timer(0.6).timeout.connect(func() -> void: stop.stop = true)
	t0 = Time.get_ticks_msec()
	gut = await Net.download_big("http://127.0.0.1:%d/still" % PORT, Config.path("abruf/weg.bin"), Callable(), 0, true, stop)
	check(not gut and Time.get_ticks_msec() - t0 < 3000 and not FileAccess.file_exists(Config.path("abruf/weg.bin"))
			and not FileAccess.file_exists(Config.path("abruf/weg.bin.part")),
			"Abbruch auf Wunsch bei schweigendem Server: sofort, nichts bleibt liegen")
	Net.still_ms = 1200
	t0 = Time.get_ticks_msec()
	gut = await Net.download_big("http://127.0.0.1:%d/halb" % PORT, Config.path("abruf/halb.bin"))
	dauer = Time.get_ticks_msec() - t0
	Net.still_ms = Net.STILL_MS
	check(not gut and dauer >= 1200 and dauer < 5000 and not FileAccess.file_exists(Config.path("abruf/halb.bin.part")),
			"Download bleibt mittendrin stehen: Schluss nach der Stillstands-Grenze (%d ms), nichts bleibt liegen" % dauer)
	check(not await Net.download_big("http://127.0.0.1:%d/gross?n=500000" % PORT, Config.path("abruf/zu_gross.bin"), Callable(), 100000),
			"größer als erlaubt: abgelehnt")
	check(Net.STILL_MS >= 60000, "im Betrieb großzügig: mindestens eine Minute ohne ein Byte")


func _tls() -> void:
	print("Verschlüsselt (TLS)")
	var r: Dictionary
	var t0 := 0
	var bilder := 0
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, "CN=localhost,O=Uzai Probe,C=DE")
	var kp := Config.path("abruf/probe.key")
	var cp := Config.path("abruf/probe.crt")
	key.save(kp)
	cert.save(cp)
	_srv.append(OS.create_process("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/fake_netz.py"), str(PORT_TLS),
		ProjectSettings.globalize_path(cp), ProjectSettings.globalize_path(kp)])))
	await get_tree().create_timer(1.5).timeout
	r = await _hole("/json", 5.0, 0, true, PackedStringArray(), HTTPClient.METHOD_GET, "", PORT_TLS, true)
	check(int(r.result) == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, "fremdes Zertifikat: abgelehnt")
	Abruf.probe_tls = TLSOptions.client(cert)
	r = await _hole("/json", 5.0, 0, true, PackedStringArray(), HTTPClient.METHOD_GET, "", PORT_TLS, true)
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and Fremd.verz(Fremd.json(_text(r))).get("titel") == "Uzai",
			"mit dem Zertifikat der Probe: Antwort über TLS")
	r = await _hole("/gross?n=1500000", 10.0, 0, true, PackedStringArray(), HTTPClient.METHOD_GET, "", PORT_TLS, true)
	check(int(r.result) == HTTPRequest.RESULT_SUCCESS and (r.body as PackedByteArray).size() == 1500000 and r.body[513] == 1,
			"große Antwort über TLS: ganz und unverändert")
	bilder = _bilder
	t0 = Time.get_ticks_msec()
	r = await _hole("/still", 1.5, 0, true, PackedStringArray(), HTTPClient.METHOD_GET, "", PORT_TLS, true)
	check(int(r.result) == HTTPRequest.RESULT_TIMEOUT and Time.get_ticks_msec() - t0 < 4000 and _bilder - bilder > 20,
			"schweigender Server über TLS: Zeitüberschreitung, Hauptfaden läuft")
	Abruf.probe_tls = null


func _einer(box: Dictionary, pfad: String, soll: int) -> void:
	var r := await _hole(pfad, 10.0)
	box.fertig = int(box.fertig) + 1
	if int(r.result) == HTTPRequest.RESULT_SUCCESS and (r.body as PackedByteArray).size() == soll:
		box.gut = int(box.gut) + 1


func _einer_still(box: Dictionary) -> void:
	var r := await _hole("/still", 2.0)
	box.fertig = int(box.fertig) + 1
	if int(r.result) == HTTPRequest.RESULT_TIMEOUT:
		box.gut = int(box.gut) + 1

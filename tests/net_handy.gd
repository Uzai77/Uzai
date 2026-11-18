extends Node
## Netz-Probe für die Handy-Seite und den Steuer-Anschluss (Punkt 72): sichere Zufallscodes,
## nur Heimnetz, Ablauf, Größen- und Methodenbegrenzung, Sicherheits-Kopfzeilen, Schlüssel am
## Steuer-Anschluss. Spricht die Handy-Seite über 127.0.0.1 an.
## Aufruf: UZAI_DATA=<ordner> godot --headless --path . res://tests/net_handy.tscn

const R := preload("res://src/core/remote.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await _run()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Eine Anfrage an die Handy-Seite: { code, head, body } (code 0 = keine Antwort).
func _http(method: String, path: String, body := "", length := -1, host := "127.0.0.1:%d" % R.PHONE_PORT) -> Dictionary:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", R.PHONE_PORT) != OK:
		return { "code": 0, "head": "", "body": "" }
	var t0 := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 3000:
		peer.poll()
		await get_tree().process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return { "code": 0, "head": "", "body": "" }
	var n := body.to_utf8_buffer().size() if length < 0 else length
	peer.put_data(("%s %s HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n\r\n%s" % [method, path, host, n, body]).to_utf8_buffer())
	var raw := PackedByteArray()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var a := peer.get_available_bytes()
		if a > 0:
			raw.append_array(peer.get_data(a)[1])
		await get_tree().process_frame
	var txt := raw.get_string_from_utf8()
	var cut := txt.find("\r\n\r\n")
	return { "code": int(txt.get_slice(" ", 1)) if txt != "" else 0, "head": txt.substr(0, cut) if cut >= 0 else txt, "body": txt.substr(cut + 4) if cut >= 0
			else "" }


func _run() -> void:
	print("Zufallscodes und Steuer-Anschluss")
	var t1 := R.secure_token()
	var t2 := R.secure_token()
	check(t1.length() == 32 and t1.is_valid_hex_number() and t1 != t2, "128 Bit aus sicherem Zufall, jedes Mal neu (%s)" % t1)
	var key := R.secure_token()
	check(R.parse_control(R.control_line(key, "launch rom:zelda"), key) == "launch rom:zelda", "Auftrag mit richtigem Schlüssel")
	check(R.parse_control(R.control_line(R.secure_token(), "show"), key) == "" and R.parse_control("show", key) == "" and R.parse_control("launch x", key) == "",
			"falscher oder fehlender Schlüssel: nichts")
	check(R.parse_control(" show", "") == "" and R.parse_control("abc show", "abc") == "", "ohne echten Schlüssel nimmt der Anschluss nichts an")

	print("Nur Heimnetz")
	for a in ["192.168.1.5", "10.0.0.7", "172.20.1.1", "127.0.0.1", "169.254.3.4", "::1", "fe80::1", "fd12:3456::1", "::ffff:192.168.0.9",
			"0:0:0:0:0:0:0:1", "fe80:0:0:0:1:2:3:4", "fd00:0:0:0:0:0:0:1"]:
		check(R.is_home_address(a), "%s gehört zum Heimnetz" % a)
	for a in ["8.8.8.8", "172.32.0.1", "100.64.0.1", "2001:db8::1", "2a02:8070::5", "", "kein.host", "fc:0:0:0:0:0:0:1", "fd::1", "0:0:0:0:0:0:1:1"]:
		check(not R.is_home_address(a), "%s kommt von außen" % (a if a != "" else "(leer)"))

	print("Handy-Seite")
	var got: Array = []
	var on_text := func(id: String, v: String) -> void: got.append([id, v])
	Remote.phone_text.connect(on_text)
	var url := Remote.phone_begin("t_net", "Testschlüssel", "Hinweis", true, "https://www.steamgriddb.com/profile/preferences/api", "127.0.0.1")
	var token := url.get_slice("/t/", 1)
	check(url.begins_with("http://127.0.0.1:%d/t/" % R.PHONE_PORT) and token.length() == 32, "Adresse mit 128-Bit-Code")
	check(Remote._phone_ip == "127.0.0.1", "lauscht nur an dieser Adresse, nie an allen")
	var r := await _http("GET", "/t/" + token)
	check(int(r.code) == 200 and str(r.body).contains("<form method='post'>"), "Formular kommt")
	var head := str(r.head)
	check(head.contains("Referrer-Policy: no-referrer") and head.contains("X-Frame-Options: DENY") and head.contains("X-Content-Type-Options: nosniff"),
			"Kopfzeilen: kein Referer, nicht einbettbar, kein Raten des Typs")
	check(head.contains("Content-Security-Policy: default-src 'none'") and not head.contains("script-src"), "keine Skripte, keine fremden Inhalte")
	check(str(r.body).contains("rel='noopener noreferrer'"), "Link zum Anbieter ohne Referer")
	r = await _http("GET", "/t/" + R.secure_token())
	check(int(r.code) == 404, "falscher Code: abgelaufen")
	for h in ["evil.example:%d" % R.PHONE_PORT, "localhost", ""]:
		r = await _http("GET", "/t/" + token, "", -1, h)
		check(int(r.code) == 403, "Host „%s“ (DNS-Rebinding): abgelehnt" % h)
	r = await _http("PUT", "/t/" + token, "v=x")
	check(int(r.code) == 405 and got.is_empty(), "andere Methoden: abgelehnt")
	r = await _http("POST", "/t/" + token, "v=x", 200000)
	check(int(r.code) == 413 and got.is_empty(), "zu große Anfrage: abgelehnt, ohne zu lesen")
	r = await _http("POST", "/t/" + token, "v=Hallo+Welt%21")
	check(int(r.code) == 200 and got.size() == 1 and got[0] == ["t_net", "Hallo Welt!"], "Text kommt an (%s)" % str(got))
	check(not Remote._phone_req.has(token), "Einmal-Code: danach ungültig")
	check(Remote._phone == null, "nichts mehr offen: die Handy-Seite schließt")
	r = await _http("POST", "/t/" + token, "v=nochmal")
	check(int(r.code) == 0 and got.size() == 1, "danach lauscht nichts mehr")

	print("Ablauf")
	url = Remote.phone_begin("t_alt", "Alt", "", false, "", "127.0.0.1")
	token = url.get_slice("/t/", 1)
	check(float(Remote._phone_req[token].until) - Time.get_unix_time_from_system() > R.PHONE_TTL - 5, "gilt %d Minuten" % int(R.PHONE_TTL / 60.0))
	Remote._phone_req[token].until = Time.get_unix_time_from_system() - 1.0
	r = await _http("POST", "/t/" + token, "v=spaet")
	check(int(r.code) == 404 and got.size() == 1 and not Remote._phone_req.has(token), "abgelaufen: abgelehnt und vergessen")
	Remote._sweep()
	check(Remote._phone == null, "aufgeräumt: Handy-Seite zu")

	print("Adresse ohne passenden Anschluss (nur Proben)")
	url = Remote.phone_begin("t_probe", "Probe", "", false, "", "192.168.250.250")
	check(url.begins_with("http://192.168.250.250:") and Remote._phone_ip == "127.0.0.1", "lauscht dann nur auf 127.0.0.1")
	Remote.phone_end("t_probe")
	check(Remote._phone == null and Remote._phone_req.is_empty(), "beendet: zu")
	Remote.phone_text.disconnect(on_text)

	print("Bild vom Handy (Mosaik): Datei hochladen")
	var bilder: Array = []
	var on_file := func(id: String, data: PackedByteArray) -> void: bilder.append([id, data])
	Remote.phone_file.connect(on_file)
	url = Remote.phone_upload_begin("t_bild", "Bild für „Abenteuer“", "Hinweis", "https://www.google.com/search?tbm=isch&q=Abenteuer", "Bilder suchen", "Öffnet die Bildersuche.", "127.0.0.1")
	token = url.get_slice("/t/", 1)
	r = await _http("GET", "/t/" + token)
	check(int(r.code) == 200 and str(r.body).contains("enctype='multipart/form-data'") and str(r.body).contains("type='file'")
			and str(r.body).contains("accept='image/png,image/jpeg,image/webp'"), "Seite mit Dateifeld")
	check(str(r.body).contains("google.com/search?tbm=isch") and not str(r.head).contains("script-src"), "nur ein Link zur Bildersuche, keine Skripte")
	var img := Image.create(40, 30, false, Image.FORMAT_RGB8)
	img.fill(Color(0.7, 0.6, 0.9))
	var png := img.save_png_to_buffer()
	r = await _upload(token, "kein bild".to_utf8_buffer())
	check(int(r.code) == 200 and bilder.is_empty() and Remote._phone_req.has(token), "kein Bild (falscher Kopf): abgelehnt, Eingabe bleibt offen")
	var big := PackedByteArray()
	big.resize(R.UPLOAD_MAX + 70000)
	r = await _upload(token, big, true)
	check(int(r.code) == 413 and bilder.is_empty(), "zu groß angekündigt: abgelehnt, ohne zu lesen")
	r = await _upload(token, png)
	check(int(r.code) == 200 and bilder.size() == 1 and bilder[0][0] == "t_bild" and (bilder[0][1] as PackedByteArray) == png, "Bild kommt unverändert als Bytes an")
	check(not Remote._phone_req.has(token), "Einmal-Code: danach ungültig")
	Remote.phone_file.disconnect(on_file)
	Remote._sweep()


## Bild als Formular hochladen (multipart/form-data, Feld „f“). nur_kopf: nur ankündigen.
func _upload(token: String, data: PackedByteArray, nur_kopf := false) -> Dictionary:
	var grenze := "----uzaiTest42"
	var body := ("--%s\r\nContent-Disposition: form-data; name=\"f\"; filename=\"../../x.png\"\r\nContent-Type: image/png\r\n\r\n" % grenze).to_utf8_buffer()
	body.append_array(data)
	body.append_array(("\r\n--%s--\r\n" % grenze).to_utf8_buffer())
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", R.PHONE_PORT) != OK:
		return { "code": 0 }
	var t0 := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 3000:
		peer.poll()
		await get_tree().process_frame
	peer.put_data(("POST /t/%s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: multipart/form-data; boundary=%s\r\nContent-Length: %d\r\n\r\n" % [
		token, R.PHONE_PORT, grenze, body.size()]).to_utf8_buffer())
	if not nur_kopf:
		peer.put_data(body)
	var raw := PackedByteArray()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var a := peer.get_available_bytes()
		if a > 0:
			raw.append_array(peer.get_data(a)[1])
		await get_tree().process_frame
	var txt := raw.get_string_from_utf8()
	return { "code": int(txt.get_slice(" ", 1)) if txt != "" else 0, "body": txt }

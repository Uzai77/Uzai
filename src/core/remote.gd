extends Node
## Uzai von außen ansprechen:
## 1) Nur ein Uzai gleichzeitig. Startet ein zweites (zum Beispiel über eine Desktop-Verknüpfung
##    mit --launch=<Spiel>), gibt es den Auftrag an das laufende weiter und beendet sich.
## 2) Eingabe per Handy: Uzai zeigt einen QR-Code, das Handy öffnet eine kleine Seite im
##    Heimnetz, und was dort eingetippt oder eingefügt wird, landet direkt in Uzai.
##
## Sicherheit (Punkt 72): Der Steuer-Anschluss lauscht nur auf diesem PC (127.0.0.1) und nimmt
## Aufträge nur mit dem Sitzungsschlüssel aus dem Datenordner an. Die Handy-Seite lauscht nur an
## der Heimnetz-Adresse (nie an allen Anschlüssen), antwortet nur Geräten aus dem Heimnetz, läuft
## nur, solange eine Eingabe oder ein Teilen offen ist, und jede Eingabe hat einen eigenen
## Zufallscode (128 Bit, sicherer Zufall) mit Ablauf. Anfragen sind in Größe und Anzahl begrenzt,
## die Seite verbietet fremde Skripte, Einbetten und das Weitergeben der Adresse (Referer).

const Sicher := preload("res://src/core/sicher.gd")
const Bildschirm := preload("res://src/core/bildschirm.gd")

signal launch_requested(game_id: String)
signal show_requested
signal phone_text(request_id: String, text: String)
signal phone_form(request_id: String, values: Dictionary)
## Bild vom Handy (phone_upload_begin): nur Größe und Dateikopf sind geprüft – dekodieren und neu
## speichern macht, wer es bekommt (Mosaik.bild_aus_bytes, nie die Originaldatei).
signal phone_file(request_id: String, data: PackedByteArray)

const CONTROL_PORT := 47811
const PHONE_PORT := 47812
const PID_FILE := "uzai.pid"   ## Prozessnummer des Uzai, das den Anschluss hält (2. Zeile: Sitzungsschlüssel)
const REPLY_MS := 2500         ## so lange auf „ok“ vom laufenden Uzai warten (im Spiel 12 Bilder/s)
const PHONE_TTL := 600         ## Sekunden, die eine Handy-Eingabe offen bleibt
const MAX_REQUEST := 65536     ## größte Anfrage ans Handy-Formular (Bytes)
const KOPF_MAX := 8192         ## längster Kopf einer Anfrage (ein Handy-Browser schickt weit weniger)
const MAX_SERVING := 8         ## so viele Anfragen gleichzeitig, weitere werden verworfen
const FIELD_MAX := 512         ## längster Wert eines Formularfelds (Name, Schlüssel)
const UPLOAD_MAX := 15 * 1024 * 1024  ## größtes Bild vom Handy (nur bei einer Bild-Eingabe)
const UPLOAD_MS := 60000       ## so lange darf das Hochladen eines Bildes dauern
const CONTROL_MAX := 4096      ## längste Zeile an den Steuer-Anschluss (Bytes)
## Kopfzeilen jeder Handy-Seite: keine fremden Inhalte oder Skripte, nicht einbettbar, die Adresse
## (mit dem Code) geht nie als Referer an andere Seiten.
const SECURE_HEADERS := "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\n" + \
	"Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; media-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'\r\n"

var startup_launch := ""
var is_second := false         ## dieses Uzai gibt nur weiter und beendet sich gleich
## Ein altes Uzai hält den Anschluss, antwortet aber nicht (hängt nach einem Absturz in einem
## blockierenden Faden). Dieses startet trotzdem; main fragt, ob das alte beendet werden soll.
var hung_pid := 0
var _control: TCPServer
var _phone: TCPServer
var _phone_ip := ""            ## Adresse, an der die Handy-Seite lauscht
var _phone_req := {}           # token -> { id, title, hint, secret, until } (Formular: fields statt secret)
var _serving := 0              ## Anfragen ans Handy-Formular, die gerade gelesen werden
var _key := ""                 ## Sitzungsschlüssel des Steuer-Anschlusses
var _sweep_at := 0


## Mehrere Bildschirme unter Windows: Uzai startet sich einmal selbst neu, damit es auf jedem in dessen
## echten Bildpunkten rechnet (bildschirm.gd – sonst zieht Windows das Bild auf dem zweiten groß). Nur das
## Uzai, das auch das laufende würde (der Anschluss ist frei); ein zweites gibt wie immer nur weiter.
## Dieses hier baut nichts auf (is_second) und endet gleich; das neue wartet darauf (--nach-neustart)
## und öffnet sein Fenster gleich auf dem gewählten Bildschirm (--screen).
func _scharf_neu_starten() -> bool:
	var flaechen: Array = []
	for i in DisplayServer.get_screen_count():
		flaechen.append(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))
	var an := bool(Config.get_value("display.dpi_eigen", true)) and not Config.safe_mode
	if not Bildschirm.neustart_noetig(Config.is_windows(), flaechen.size(), an, Array(OS.get_cmdline_user_args()),
			str(Config.get_value("display.dpi_gleich", "")), Bildschirm.anordnung(flaechen)):
		return false
	var probe := TCPServer.new()
	var frei := probe.listen(CONTROL_PORT, "127.0.0.1") == OK
	probe.stop()
	if not frei:
		return false
	var args := Bildschirm.mit_schirm(Array(OS.get_cmdline_args()), Config.get_value("display.screen", Bildschirm.AUTO), flaechen.size())
	args.append("--")
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--nach-neustart="):
			args.append(a)
	args.append("--nach-neustart=%d" % OS.get_process_id())
	Bildschirm.vor_neustart(true)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(args))
	Bildschirm.nach_neustart()
	if pid <= 0:
		return false
	is_second = true
	get_tree().quit()
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--launch="):
			startup_launch = a.substr(9)
	# Desktop-Verknüpfungen starten Uzai ohne Fenster (--headless): Läuft Uzai schon, blitzte
	# sonst kurz ein zweites Vollbildfenster auf. Ohne Fenster nur weitergeben – oder, wenn kein
	# Uzai läuft (bzw. das alte hängt), sich selbst mit Fenster neu starten.
	if DisplayServer.get_name() == "headless" and startup_launch != "" and not "--demo" in OS.get_cmdline_user_args():
		is_second = true
		var probe := TCPServer.new()
		var busy := probe.listen(CONTROL_PORT, "127.0.0.1") != OK
		probe.stop()
		if not (busy and _forward()):
			var args: Array = []
			for a in OS.get_cmdline_args():
				if a != "--headless":
					args.append(a)
			args.append("--")
			args.append_array(OS.get_cmdline_user_args())
			OS.create_process(OS.get_executable_path(), PackedStringArray(args))
		get_tree().quit()
		return
	if DisplayServer.get_name() == "headless" or "--demo" in OS.get_cmdline_user_args():
		return
	if _scharf_neu_starten():
		return
	_control = TCPServer.new()
	if _control.listen(CONTROL_PORT, "127.0.0.1") == OK:
		_write_pid()
		return
	_control = null
	# Ein Uzai läuft schon: Auftrag weitergeben und dieses beenden – aber nur, wenn es quittiert.
	# Früher beendete sich das neue immer, und nach einem Absturz mit hängendem Prozess startete
	# Uzai gar nicht mehr.
	if _forward():
		is_second = true
		get_tree().quit()
		return
	hung_pid = _read_pid()
	push_warning("Uzai: Anschluss %d belegt, aber keine Antwort (alter Prozess %d)" % [CONTROL_PORT, hung_pid])


## Auftrag an das laufende Uzai; true, wenn es mit „ok“ antwortet.
func _forward() -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", CONTROL_PORT) != OK:
		return false
	var t0 := Time.get_ticks_msec()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 1500:
		peer.poll()
		OS.delay_msec(10)
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var msg := ("launch " + startup_launch) if startup_launch != "" else "show"
	peer.put_data((control_line(_read_key(), msg) + "\n").to_utf8_buffer())
	var got := ""
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < REPLY_MS:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			got += peer.get_utf8_string(n)
			if got.contains("ok"):
				return true
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return false
		OS.delay_msec(10)
	return false


func _write_pid() -> void:
	_key = secure_token()
	var f := FileAccess.open(Config.path(PID_FILE), FileAccess.WRITE)
	if f:
		f.store_string("%d\n%s" % [OS.get_process_id(), _key])


func _read_pid() -> int:
	var p := int(FileAccess.get_file_as_string(Config.path(PID_FILE)).get_slice("\n", 0).strip_edges())
	return p if p > 0 and p != OS.get_process_id() else 0


func _read_key() -> String:
	return FileAccess.get_file_as_string(Config.path(PID_FILE)).get_slice("\n", 1).strip_edges()


## Zufallscode aus sicherem Zufall (Betriebssystem), als Hex-Text: 16 Bytes = 128 Bit.
static func secure_token(n_bytes := 16) -> String:
	return Crypto.new().generate_random_bytes(n_bytes).hex_encode()


## Zeile an den Steuer-Anschluss: Schlüssel, dann der Auftrag.
static func control_line(key: String, cmd: String) -> String:
	return key + " " + cmd


## Auftrag aus einer Zeile des Steuer-Anschlusses ("" bei falschem oder fehlendem Schlüssel).
## Der Schlüssel wird in fester Zeit verglichen (die Dauer verrät keine richtigen Anfangszeichen).
static func parse_control(line: String, key: String) -> String:
	var l := line.strip_edges()
	var sp := l.find(" ")
	if key.length() < 32 or sp <= 0 or not Sicher.same_secret(l.left(sp), key):
		return ""
	return l.substr(sp + 1).strip_edges()


## Ist hung_pid wirklich ein Uzai (dieselbe Programmdatei)? Die Nummer kann nach einem Absturz
## längst an ein anderes Programm vergeben sein – das darf Uzai nie beenden.
func hung_is_uzai() -> bool:
	if hung_pid <= 0:
		return false
	var exe := OS.get_executable_path()
	if Config.is_windows():
		var r := await Helper.run("find-process", { "dir": exe.get_base_dir().replace("/", "\\") }, 20.0)
		if not r.ok or not (r.result is Dictionary):
			return false
		for p in r.result.get("pids", []):
			if int(p) == hung_pid:
				return true
		return false
	var f := FileAccess.open("/proc/%d/cmdline" % hung_pid, FileAccess.READ)
	if f == null:
		return false
	var b := f.get_buffer(4096)
	for i in b.size():
		if b[i] == 0:
			b[i] = 32
	return b.get_string_from_utf8().contains(exe.get_file())


## Das hängende Uzai beenden und den Anschluss übernehmen. true, wenn es beendet wurde.
func end_hung() -> bool:
	if not await hung_is_uzai():
		hung_pid = 0
		return false
	OS.kill(hung_pid)
	hung_pid = 0
	# Der Anschluss wird frei, sobald der Prozess weg ist.
	for i in 40:
		await get_tree().create_timer(0.1).timeout
		var srv := TCPServer.new()
		if srv.listen(CONTROL_PORT, "127.0.0.1") == OK:
			_control = srv
			_write_pid()
			break
	return true


func _process(_dt: float) -> void:
	if _control and _control.is_connection_available():
		var p := _control.take_connection()
		_read_control(p)
	if _phone and _phone.is_connection_available():
		var p2 := _phone.take_connection()
		# Nur Geräte aus dem Heimnetz, und nicht beliebig viele auf einmal.
		if _serving >= MAX_SERVING or not is_home_address(p2.get_connected_host()):
			p2.disconnect_from_host()
		else:
			_serve_phone(p2)
	# Abgelaufene Eingaben aufräumen; ist nichts mehr offen, schließt die Handy-Seite.
	var now := Time.get_ticks_msec()
	if _phone and now >= _sweep_at:
		_sweep_at = now + 5000
		_sweep()


func _read_control(peer: StreamPeerTCP) -> void:
	var text := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000 and not text.contains("\n") and text.length() < CONTROL_MAX:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			text += peer.get_utf8_string(mini(n, CONTROL_MAX))
		else:
			await get_tree().process_frame
	# Ohne den Schlüssel aus dem Datenordner kein Auftrag (andere Programme oder Nutzer am PC).
	var line := parse_control(text.get_slice("\n", 0), _key)
	if line == "":
		peer.put_data("nein\n".to_utf8_buffer())
		peer.disconnect_from_host()
		return
	# Quittieren: Bleibt das aus, hält das neue Uzai dieses für hängend.
	peer.put_data("ok\n".to_utf8_buffer())
	peer.disconnect_from_host()
	if line.begins_with("launch "):
		launch_requested.emit(line.substr(7).strip_edges())
	elif line == "show":
		show_requested.emit()


# --- Eingabe per Handy ---------------------------------------------------------------------

## Gehört die Adresse zum Heimnetz (oder zu diesem PC)? IPv4 privat, Loopback, Link-local;
## IPv6 Loopback, Link-local (fe80::/10) und ULA (fc00::/7). Alles andere kommt von außen.
static func is_home_address(addr: String) -> bool:
	var a := addr.strip_edges().to_lower()
	if a.begins_with("::ffff:"):
		a = a.substr(7)
	if a.is_valid_ip_address() and not a.contains(":"):
		var p := a.split(".")
		var b0 := int(p[0])
		var b1 := int(p[1])
		return b0 == 10 or b0 == 127 or (b0 == 192 and b1 == 168) or (b0 == 172 and b1 >= 16 and b1 <= 31) or (b0 == 169 and b1 == 254)
	if a.is_valid_ip_address():
		# An den Zahlen, nicht am Text: Dieselbe Adresse lässt sich verschieden schreiben (::1 und 0:0:0:0:0:0:0:1).
		var g := Sicher._ipv6_groups(a)
		if g.size() != 8:
			return false
		var loopback := g[7] == 1 and g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0 and g[4] == 0 and g[5] == 0 and g[6] == 0
		return loopback or (g[0] & 0xfe00) == 0xfc00 or (g[0] & 0xffc0) == 0xfe80
	return false


## Adresse im Heimnetz (192.168.x.x, 10.x.x.x oder 172.16–31.x.x).
static func lan_ip() -> String:
	for ip in IP.get_local_addresses():
		var s := str(ip)
		if s.begins_with("192.168.") or s.begins_with("10."):
			return s
		if s.begins_with("172."):
			var second := int(s.get_slice(".", 1))
			if second >= 16 and second <= 31:
				return s
	return ""


## Startet eine Eingabe übers Handy. Gibt die Adresse für den QR-Code zurück ("" ohne Netz).
## link_label/link_hint: eigene Beschriftung für den Link oben (sonst „Schlüssel holen“).
func phone_begin(request_id: String, title: String, hint := "", secret := false, link := "", ip_override := "", link_label := "", link_hint := "") -> String:
	var ip := ip_override if ip_override != "" else lan_ip()
	if ip == "" or not _open_phone(ip):
		return ""
	var token := secure_token()
	_phone_req[token] = { "id": request_id, "title": title, "hint": hint, "secret": secret, "link": link, "link_label": link_label, "link_hint": link_hint,
		"until": Time.get_unix_time_from_system() + PHONE_TTL }
	return "http://%s:%d/t/%s" % [ip, PHONE_PORT, token]


## Wie phone_begin, aber mit mehreren Feldern auf einer Seite (Benutzername und Schlüssel).
## fields: [{ name, label, secret }] – name nur aus Kleinbuchstaben. Das Ergebnis kommt als
## phone_form(request_id, { name: Wert }), nur mit diesen Feldern.
## steps: eine kurze Anleitung über den Feldern, je Schritt { text, copy: [Texte zum Kopieren] } (z. B. Adressen, die
## man auf einer Entwicklerseite eintragen muss). Ein Feld darf ein Muster haben (pattern, nur Ziffern und [0-9]{a,b},
## inputmode "numeric"): Das Handy schickt dann nur, was passt – ohne Skript auf der Seite.
func phone_form_begin(request_id: String, title: String, fields: Array, hint := "", link := "", link_label := "", link_hint := "", ip_override := "",
		steps: Array = []) -> String:
	for f in fields:
		if not (f is Dictionary) or not _field_name_ok(str(f.get("name", ""))):
			return ""
	var ip := ip_override if ip_override != "" else lan_ip()
	if ip == "" or not _open_phone(ip):
		return ""
	var token := secure_token()
	_phone_req[token] = { "id": request_id, "title": title, "hint": hint, "fields": fields.duplicate(true), "link": link,
		"link_label": link_label, "link_hint": link_hint, "steps": steps.duplicate(true), "until": Time.get_unix_time_from_system() + PHONE_TTL }
	return "http://%s:%d/t/%s" % [ip, PHONE_PORT, token]


## Bild übers Handy: Die Seite hat ein Dateifeld (PNG, JPEG, WebP), link öffnet auf dem Handy z. B.
## die Bildersuche (nur ein Link, Uzai fragt selbst nichts ab). Das Bild kommt als phone_file.
func phone_upload_begin(request_id: String, title: String, hint := "", link := "", link_label := "", link_hint := "", ip_override := "") -> String:
	var ip := ip_override if ip_override != "" else lan_ip()
	if ip == "" or not _open_phone(ip):
		return ""
	var token := secure_token()
	_phone_req[token] = { "id": request_id, "title": title, "hint": hint, "upload": true, "link": link, "link_label": link_label,
		"link_hint": link_hint, "until": Time.get_unix_time_from_system() + PHONE_TTL }
	return "http://%s:%d/t/%s" % [ip, PHONE_PORT, token]


static func _field_name_ok(n: String) -> bool:
	if n == "" or n.length() > 16:
		return false
	for ch in n:
		if not (ch >= "a" and ch <= "z"):
			return false
	return true


## Formular-Inhalt (application/x-www-form-urlencoded) → { Name: Wert }. Nur die erlaubten Namen,
## jeder Wert gekürzt auf FIELD_MAX; ein doppelter Name zählt beim ersten Mal.
static func form_values(body: String, names: Array) -> Dictionary:
	var out := {}
	for part in body.split("&"):
		var eq := part.find("=")
		if eq <= 0:
			continue
		var k := part.substr(0, eq)
		if not names.has(k) or out.has(k):
			continue
		out[k] = part.substr(eq + 1).replace("+", " ").uri_decode().left(FIELD_MAX)
	return out


## Handy-Seite öffnen – nur an der Heimnetz-Adresse dieses PCs, nie an allen Anschlüssen. Eine
## Adresse, die dieser PC nicht hat (nur Proben), lauscht nur auf 127.0.0.1.
func _open_phone(ip: String) -> bool:
	var bind := ip if (IP.get_local_addresses() as Array).has(ip) else "127.0.0.1"
	if _phone != null and _phone_ip == bind:
		return true
	if _phone != null:
		_phone.stop()
	_phone = TCPServer.new()
	_phone_ip = bind
	if _phone.listen(PHONE_PORT, bind) != OK:
		_phone = null
		_phone_ip = ""
		return false
	return true


## Abgelaufene Eingaben vergessen; ist nichts mehr offen (auch kein Teilen), die Seite schließen.
func _sweep() -> void:
	var now := Time.get_unix_time_from_system()
	for k in _phone_req.keys():
		if float(_phone_req[k].get("until", 0.0)) < now:
			_phone_req.erase(k)
	if _phone_req.is_empty() and _phone and not Capture.share_active():
		_phone.stop()
		_phone = null
		_phone_ip = ""


## Aufnahmen ans Handy (Capture.share_link): dieselbe kleine Seite im Heimnetz, Pfad /c/<token>.
## Gibt die Adresse für den QR-Code zurück ("" ohne Netz).
func share_begin(token: String) -> String:
	var ip := lan_ip()
	if ip == "" or not _open_phone(ip):
		return ""
	return "http://%s:%d/c/%s" % [ip, PHONE_PORT, token]


func phone_end(request_id: String) -> void:
	for k in _phone_req.keys():
		if _phone_req[k].id == request_id:
			_phone_req.erase(k)
	_sweep()


func _serve_phone(peer: StreamPeerTCP) -> void:
	_serving += 1
	await _serve_phone_inner(peer)
	_serving -= 1


func _serve_phone_inner(peer: StreamPeerTCP) -> void:
	var raw := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	var header_end := -1
	var need := -1
	# Grenzen: 64 KB und 4 s; nur ein Bild an eine offene Bild-Eingabe darf größer sein und länger
	# dauern (das steht erst nach dem Kopf fest – der Kopf selbst bleibt unter 64 KB).
	var limit := MAX_REQUEST
	var dauer := 4000
	var bild := false
	# Bis hier ist das Kopfende schon gesucht: jedes neue Stück nur ab dort. Sonst kostete ein Gerät im WLAN mit 64 KB
	# aus „\r“ je Bild eine Schleife über alles im Hauptfaden.
	var gesucht := 0
	while Time.get_ticks_msec() - t0 < dauer:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			raw.append_array(peer.get_data(mini(n, limit + 1 - raw.size()))[1])
			if header_end < 0:
				header_end = _bytes_find(raw, "\r\n\r\n".to_ascii_buffer(), maxi(0, gesucht - 3), mini(raw.size(), KOPF_MAX))
				gesucht = raw.size()
				if header_end < 0 and raw.size() >= KOPF_MAX:
					_reply(peer, 431, _page(_t("Zu groß"), "<p>%s</p>" % _esc(_t("Nicht erlaubt."))))
					return
				if header_end >= 0:
					var txt := raw.slice(0, header_end).get_string_from_utf8()
					var cl := 0
					for line in txt.split("\r\n"):
						if line.to_lower().begins_with("content-length:"):
							cl = int(line.substr(15).strip_edges())
					need = header_end + 4 + cl
					var first_line := txt.get_slice("\r\n", 0)
					var tok := first_line.get_slice(" ", 1).get_slice("/t/", 1).get_slice("?", 0) if first_line.get_slice(" ", 1).begins_with("/t/") else ""
					if first_line.begins_with("POST ") and bool(_phone_req.get(tok, {}).get("upload", false)):
						bild = true
						limit = UPLOAD_MAX + MAX_REQUEST
						dauer = UPLOAD_MS
			# Zu groß (Kopf oder angekündigter Inhalt): gar nicht erst weiterlesen.
			if raw.size() > limit or need > limit:
				var zu := _t("Das Bild ist zu groß (höchstens 15 MB).") if bild else _t("Das ist zu viel Text für Uzai.")
				_reply(peer, 413, _page(_t("Zu groß"), "<p>%s</p>" % _esc(zu)))
				return
			if need >= 0 and raw.size() >= need:
				break
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		else:
			await get_tree().process_frame
	if header_end < 0:
		_reply(peer, 405, _page("Uzai", "<p>%s</p>" % _esc(_t("Nicht erlaubt."))))
		return
	# Nur der Kopf wird Text; ein hochgeladenes Bild bleibt Bytes.
	var req := raw.slice(0, header_end + 4).get_string_from_utf8() + ("" if bild else raw.slice(header_end + 4).get_string_from_utf8())
	var first := req.get_slice("\r\n", 0)
	var method := first.get_slice(" ", 0)
	var path := first.get_slice(" ", 1)
	if method != "GET" and method != "POST":
		_reply(peer, 405, _page("Uzai", "<p>%s</p>" % _esc(_t("Nicht erlaubt."))))
		return
	var hdrs := {}
	for line in req.substr(0, maxi(0, req.find("\r\n\r\n"))).split("\r\n").slice(1):
		var c := line.find(":")
		if c > 0:
			hdrs[line.substr(0, c).strip_edges().to_lower()] = line.substr(c + 1).strip_edges()
	# Nur Aufrufe über die Adresse aus dem QR-Code (eine IP): Eine fremde Webseite, deren Name
	# plötzlich auf diesen PC zeigt (DNS-Rebinding), schickt ihren eigenen Namen mit.
	if not host_header_ok(str(hdrs.get("host", ""))):
		_reply(peer, 403, _page("Uzai", "<p>%s</p>" % _esc(_t("Nicht erlaubt."))))
		return
	if path.begins_with("/c/"):
		Capture.serve(peer, path, hdrs)
		return
	var token := path.get_slice("/t/", 1).get_slice("?", 0) if path.begins_with("/t/") else ""
	var info: Dictionary = _phone_req.get(token, {})
	if not info.is_empty() and float(info.get("until", 0.0)) < Time.get_unix_time_from_system():
		_phone_req.erase(token)
		info = {}
	if info.is_empty():
		_reply(peer, 404, _page(_t("Abgelaufen"), "<p>%s</p>" % _esc(_t("Diese Eingabe ist nicht mehr offen. Bitte in Uzai neu starten."))))
		return
	if method == "POST" and info.has("upload"):
		var data := upload_bytes(raw.slice(header_end + 4), str(hdrs.get("content-type", "")))
		if data.is_empty():
			# Kein brauchbares Bild: die Eingabe bleibt offen, ein anderes Bild geht.
			_reply(peer, 200, _page(_t("Nicht angekommen"), "<p>%s</p>%s" % [_esc(_t("Nur PNG, JPEG oder WebP bis 15 MB. Bitte ein anderes Bild wählen.")),
					form_html(info)]))
			return
		_phone_req.erase(token)
		phone_file.emit(str(info.id), data)
		_reply(peer, 200, _page(_t("Angekommen"), "<p class='ok'>✓ %s</p>" % _esc(_t("In Uzai angekommen."))))
		_sweep()
		return
	if method == "POST" and info.has("fields"):
		var names: Array = (info.fields as Array).map(func(f: Dictionary) -> String: return str(f.name))
		var vals := form_values(req.substr(req.find("\r\n\r\n") + 4), names)
		_phone_req.erase(token)
		phone_form.emit(str(info.id), vals)
		_reply(peer, 200, _page(_t("Angekommen"), "<p class='ok'>✓ %s</p>" % _esc(_t("In Uzai angekommen."))))
		_sweep()
		return
	if method == "POST":
		var body := req.substr(req.find("\r\n\r\n") + 4)
		var value := ""
		for part in body.split("&"):
			if part.begins_with("v="):
				value = part.substr(2).replace("+", " ").uri_decode()
		_phone_req.erase(token)
		phone_text.emit(str(info.id), value)
		_reply(peer, 200, _page(_t("Angekommen"), "<p class='ok'>✓ %s</p>" % _esc(_t("In Uzai angekommen."))))
		_sweep()
		return
	_reply(peer, 200, _page("Uzai", form_html(info)))


## Erstes Vorkommen von muster in b zwischen von und bis (-1: keins).
static func _bytes_find(b: PackedByteArray, muster: PackedByteArray, von: int, bis: int) -> int:
	var m := muster.size()
	if m == 0:
		return -1
	var erstes := muster[0]
	var i := maxi(0, von)
	while i <= mini(bis, b.size()) - m:
		i = b.find(erstes, i)
		if i < 0 or i > mini(bis, b.size()) - m:
			return -1
		if b.slice(i, i + m) == muster:
			return i
		i += 1
	return -1


## Das Bild aus dem Formular (multipart/form-data, Feld „f“): nur das erste Teil, Grenze aus dem
## Content-Type, Ende über die Schlussgrenze. Ergebnis nur, wenn es nach dem Dateikopf ein PNG, JPEG
## oder WebP ist und höchstens UPLOAD_MAX groß – Name, Typ und Pfad vom Handy zählen nie.
static func upload_bytes(body: PackedByteArray, content_type: String) -> PackedByteArray:
	var leer := PackedByteArray()
	var ct := content_type.strip_edges()
	if not ct.to_lower().begins_with("multipart/form-data"):
		return leer
	var bi := ct.to_lower().find("boundary=")
	if bi < 0:
		return leer
	var grenze := ct.substr(bi + 9).get_slice(";", 0).strip_edges().trim_prefix("\"").trim_suffix("\"")
	if grenze == "" or grenze.length() > 70:
		return leer
	var anfang := ("--" + grenze).to_ascii_buffer()
	if body.size() < anfang.size() + 8 or body.slice(0, anfang.size()) != anfang:
		return leer
	var kopf_ende := _bytes_find(body, "\r\n\r\n".to_ascii_buffer(), anfang.size(), mini(body.size(), 4096))
	if kopf_ende < 0:
		return leer
	var kopf := body.slice(anfang.size(), kopf_ende).get_string_from_utf8().to_lower()
	if not kopf.contains("name=\"f\""):
		return leer
	var start := kopf_ende + 4
	# Die Schlussgrenze steht am Ende (höchstens ein paar Bytes danach): rückwärts im letzten Stück.
	var schluss := ("\r\n--" + grenze).to_ascii_buffer()
	var ende := -1
	var such_ab := maxi(start, body.size() - 512)
	var i := such_ab
	while true:
		var j := _bytes_find(body, schluss, i, body.size())
		if j < 0:
			break
		ende = j
		i = j + 1
	if ende < start:
		return leer
	var data := body.slice(start, ende)
	if data.size() > UPLOAD_MAX or not bild_kopf_ok(data):
		return leer
	return data


## PNG, JPEG oder WebP nach den ersten Bytes.
static func bild_kopf_ok(b: PackedByteArray) -> bool:
	if b.size() < 16:
		return false
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		return true
	if b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return true
	return b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP"


## Kopfzeile „Host“ einer Anfrage an die Handy-Seite: nur eine IP-Adresse (mit Anschluss), kein Name.
static func host_header_ok(host: String) -> bool:
	var h := host.strip_edges()
	if h.begins_with("["):
		var close := h.find("]")
		return close > 0 and h.substr(1, close - 1).is_valid_ip_address() and (close == h.length() - 1 or h.substr(close + 1).trim_prefix(":").is_valid_int())
	if h.count(":") == 1:
		if not h.get_slice(":", 1).is_valid_int():
			return false
		h = h.get_slice(":", 0)
	return h.is_valid_ip_address() and not h.contains(":")


## Inhalt der Handy-Seite: oben der Link zum Anbieter (nur https), darunter ein Textfeld – oder
## bei einem Formular je Feld eine Zeile. Alles Angezeigte ist maskiert.
static func form_html(info: Dictionary) -> String:
	var link := str(info.get("link", ""))
	var ll := str(info.get("link_label", ""))
	var lh := str(info.get("link_hint", ""))
	var link_html := "<a class='get' href='%s' target='_blank' rel='noopener noreferrer'>%s ↗</a><p class='hint'>%s</p>" % [_esc(link),
			_esc(_t(ll if ll != "" else "Schlüssel holen")),
		_esc(_t(lh if lh != "" else "Öffnet die Seite des Anbieters. Schlüssel kopieren, zurück zu diesem Tab, unten einfügen."))] if link.begins_with(
			"https://") else ""
	if info.has("upload"):
		return "%s<form method='post' enctype='multipart/form-data'><label>%s</label><input type='file' name='f' accept='image/png,image/jpeg,image/webp' required><button>%s</button></form><p class='hint'>%s</p>" % [
			link_html, _esc(_t(str(info.title))), _esc(_t("An Uzai senden")), _esc(_t(str(info.hint)))]
	if info.has("fields"):
		var inputs := ""
		var first := true
		var steps: Array = info.get("steps", []) if info.get("steps") is Array else []
		for f in info.fields:
			inputs += "<label>%s</label><input name='%s' type='%s' maxlength='%d'%s%s autocomplete='off' autocapitalize='off' spellcheck='false'>" % [
				_esc(_t(str(f.get("label", "")))), str(f.name), "password" if bool(f.get("secret", false)) else "text", FIELD_MAX,
				" autofocus" if first and steps.is_empty() else "", _field_extra(f)]
			first = false
		return "%s<h2>%s</h2>%s<form method='post'>%s<button>%s</button></form><p class='hint'>%s</p>" % [link_html, _esc(_t(str(info.title))),
				steps_html(steps), inputs, _esc(_t("An Uzai senden")), _esc(_t(str(info.hint)))]
	var kind := "password" if info.get("secret", false) else "text"
	return "%s<form method='post'><label>%s</label><textarea name='v' rows='4' autofocus autocomplete='off' autocapitalize='off' spellcheck='false'%s></textarea><button>%s</button></form><p class='hint'>%s</p>" % [
		link_html, _esc(_t(str(info.title))), " class='secret'" if kind == "password" else "", _esc(_t("An Uzai senden")), _esc(_t(str(info.hint)))]


## Muster und Tastatur eines Felds – nur eng geprüfte Formen (Ziffern-Muster wie [0-9]{17,20}, „numeric“), sonst nichts.
static func _field_extra(f: Dictionary) -> String:
	var out := ""
	var pat := str(f.get("pattern", ""))
	if RegEx.create_from_string("^\\[0-9\\]\\{[0-9]{1,2},[0-9]{1,2}\\}$").search(pat) != null:
		out += " pattern='%s' required" % pat
	if str(f.get("inputmode", "")) == "numeric":
		out += " inputmode='numeric'"
	return out


## Die Anleitung über den Feldern: nummerierte Schritte, darunter je Schritt Texte zum Kopieren (schreibgeschützte Felder –
## antippen, alles markieren, kopieren; die Seite hat kein Skript). Alles maskiert, höchstens 8 Schritte und je 3 Texte.
static func steps_html(steps: Array) -> String:
	if steps.is_empty():
		return ""
	var out := "<ol class='steps'>"
	for s in steps.slice(0, 8):
		if not (s is Dictionary):
			continue
		out += "<li>" + _esc(_t(str(s.get("text", ""))))
		var copy: Array = s.get("copy", []) if s.get("copy") is Array else []
		for c in copy.slice(0, 3):
			out += "<input class='copy' readonly value='%s'>" % _esc(str(c))
		out += "</li>"
	return out + "</ol>"


const STATUS := { 200: "200 OK", 403: "403 Forbidden", 404: "404 Not Found", 405: "405 Method Not Allowed", 413: "413 Content Too Large",
	431: "431 Request Header Fields Too Large" }


func _reply(peer: StreamPeerTCP, code: int, html: String) -> void:
	var body := html.to_utf8_buffer()
	var status: String = STATUS.get(code, "404 Not Found")
	peer.put_data(
			("HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\n%sConnection: close\r\n\r\n" % [status,
			body.size(), SECURE_HEADERS]).to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;")


## Texte der Handy-Seite in der Sprache von Uzai (läuft im Hauptfaden, wie der Rest des Servers).
static func _t(text: String) -> String:
	return TranslationServer.translate(text) if text != "" else ""


static func _page(title: String, inner: String) -> String:
	return """<!doctype html><html lang='""" + TranslationServer.get_locale().left(2).validate_filename() + """'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>%s</title>
<style>body{margin:0;background:#110e0c;color:#f7efe7;font:17px/1.45 system-ui,sans-serif;padding:28px 20px}
h1{font-size:28px;margin:0 0 18px;font-weight:900;letter-spacing:-.5px}h1 b{color:#ff8a57}
label{display:block;color:#bcaa9b;margin-bottom:8px}textarea{width:100%%;box-sizing:border-box;background:#1c1714;color:#f7efe7;border:2px solid #3a302a;border-radius:12px;padding:14px;font:16px ui-monospace,monospace}
textarea:focus,input:focus{outline:none;border-color:#ff8a57}.secret{-webkit-text-security:disc}
input{width:100%%;box-sizing:border-box;background:#1c1714;color:#f7efe7;border:2px solid #3a302a;border-radius:12px;padding:14px;font:16px ui-monospace,monospace;margin-bottom:16px}
h2{font-size:20px;margin:22px 0 12px}
button{margin-top:16px;width:100%%;padding:16px;border:0;border-radius:12px;background:#f7efe7;color:#110e0c;font-weight:800;font-size:17px}
.hint{color:#806f63;font-size:14px}.steps{padding-left:22px;margin:0 0 22px}.steps li{margin-bottom:14px}
.copy{margin:8px 0 0;color:#ff8a57}.get{display:block;text-align:center;padding:14px;border:2px solid #ff8a57;border-radius:12px;color:#ff8a57;text-decoration:none;font-weight:800;margin-bottom:6px}.ok{font-size:20px;color:#5fd39b}</style></head>
<body><h1>uzai<b>.</b></h1>%s</body></html>""" % [title, inner]

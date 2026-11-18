extends Node
## Zimmer online über den Treffpunkt (Punkt 131; docs/PLAN_ZIMMER_ONLINE.md Phase 3) mit zwei
## kopflosen Uzai-Instanzen: dieser Lauf ist der Gastgeber, ein zweiter Godot-Prozess der Gast. Jede
## Instanz hat ihre echte Sandbox-Schleife (PowerShell 7, tests/zimmer_netz_stdio.ps1, ohne
## AppContainer). Dazwischen ein nachgebautes Nostr-Relay nur auf 127.0.0.1 (zufälliger Port, nichts
## nach außen offen) und ein „böser Gast“ bzw. „böses Relay“: Unsinn, falscher Schlüssel,
## Wiederholung, Flut, zu große und binäre Nachrichten. Geprüft: nur Eingeladene klopfen an, erst
## nach der Annahme die Sitzung, Adressen nie lesbar beim Relay, nichts Böses erreicht Uzai, die
## Sandbox hält stand, Rauswerfen erreicht den Gast.
## Liegt die Linux-Fassung der Netz-Bibliotheken vor (tools/bau_netzlibs.sh --linux → build/netzlibs-linux), laden
## beide Sandboxen sie: echte BIP-340-Signaturen (das böse Relay mit falschen Signaturen fliegt raus) und ein echter
## WebRTC-Datenkanal über 127.0.0.1 (Nachrichten hin und zurück durch beide Prüfmauern), dazu der Verbindungstest der
## Oberfläche (src/room/verbindungstest.gd) mit zwei Sandboxen in dieser Instanz.
## Freundestest (src/room/freundestest.gd, mit den Bibliotheken): Einladung als Code → zweite Instanz liest ihn →
## anklopfen → annehmen → beide Figuren da, Lage, Emote und Schnellsatz hin und zurück, der Gast bekommt das Zimmer →
## rauswerfen → derselbe Code klopft vergeblich → ein böser Gast flutet (fliegt raus, der Gastgeber läuft weiter);
## in beiden Protokollen kein Code, kein Name, keine Adresse.
## Braucht UZAI_PWSH. Aufruf: godot --headless --path . res://tests/net_zimmer_treff.tscn

const ZN := preload("res://src/room/zimmer_netz.gd")
const TP := preload("res://src/room/treffpunkt.gd")
const VT := preload("res://src/room/verbindungstest.gd")
const FT := preload("res://src/room/freundestest.gd")
const Einladung := preload("res://src/room/einladung.gd")

var fails := 0
var server := TCPServer.new()
var port := 0
var peers: Array = []           ## [{ ws, subs: { abo: [z …] } }]
var texte: Array = []           ## alles, was beim Relay ankam (für die Adress-Prüfung)
var ereignisse: Array = []      ## rohe Ereignisse (für die Wiederholung)
var libs := false               ## Netz-Bibliotheken (Linux-Fassung) geladen: echte Signatur, echter Datenkanal


## UZAI_NETZLIB_TEST für die Sandboxen setzen (Ordner|SHA secp|SHA rtc), wenn die Linux-Fassung gebaut ist.
func _netzlibs() -> bool:
	var d := ProjectSettings.globalize_path("res://build/netzlibs-linux")
	var a := d.path_join("libuzai-secp256k1.so")
	var b := d.path_join("libuzai-datachannel.so")
	if not FileAccess.file_exists(a) or not FileAccess.file_exists(b):
		return false
	OS.set_environment("UZAI_NETZLIB_TEST", "%s|%s|%s" % [d, FileAccess.get_sha256(a), FileAccess.get_sha256(b)])
	return true


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() == 5 and a[0] == "--freund":
		await _freund_gast(int(a[1]), a[2], a[3], a[4])
		return
	if a.size() == 4 and a[0] == "--gast":
		await _gast(int(a[1]), a[2], a[3])
		return
	await _gastgeber()
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _sandbox(rolle: String) -> ZN.Sitzung:
	var pwsh := OS.get_environment("UZAI_PWSH")
	if pwsh == "" or not FileAccess.file_exists(pwsh):
		return null
	return ZN.starten(pwsh, PackedStringArray(["-NoProfile", "-NonInteractive", "-File", ProjectSettings.globalize_path("res://tests/zimmer_netz_stdio.ps1"),
			ProjectSettings.globalize_path("res://helper/uzai-helper.ps1"), rolle]), rolle)


func _jetzt() -> int:
	return int(Time.get_unix_time_from_system())


# --- Das nachgebaute Relay (nur 127.0.0.1) --------------------------------------------------------

func _process(_d: float) -> void:
	if port == 0:
		return
	while server.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 20
		ws.max_queued_packets = 8192
		ws.accept_stream(server.take_connection())
		peers.append({ "ws": ws, "subs": {} })
	for p in peers:
		var ws: WebSocketPeer = p.ws
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			_nachricht(p, ws.get_packet().get_string_from_utf8())
	peers = peers.filter(func(p: Dictionary) -> bool: return (p.ws as WebSocketPeer).get_ready_state() != WebSocketPeer.STATE_CLOSED)


## Nur im Test: ein Relay liest JSON (wie ein echtes) und prüft die Kennung nach.
func _nachricht(p: Dictionary, t: String) -> void:
	texte.append(t)
	var v: Variant = JSON.parse_string(t)
	if not (v is Array) or (v as Array).is_empty():
		return
	match str(v[0]):
		"REQ":
			if v.size() == 3 and v[2] is Dictionary:
				p.subs[str(v[1])] = (v[2].get("#z", []) as Array).map(func(x: Variant) -> String: return str(x))
		"CLOSE":
			p.subs.erase(str(v[1]))
		"EVENT":
			if v.size() != 2 or not (v[1] is Dictionary):
				return
			var ev: Dictionary = v[1]
			var ok := _id(ev) == str(ev.get("id", "")) and str(ev.get("sig", "")).length() == 128
			(p.ws as WebSocketPeer).send_text(JSON.stringify(["OK", str(ev.get("id", "")), ok, ""]))
			if ok:
				var roh := t.substr(9, t.length() - 10)
				ereignisse.append(roh)
				_verteilen(roh, str(ev.tags[0][1]))


func _id(ev: Dictionary) -> String:
	if not (ev.get("tags") is Array) or ev.tags.size() != 1 or ev.tags[0].size() != 2:
		return ""
	var s := "[0,\"%s\",%d,%d,[[\"z\",\"%s\"]],\"%s\"]" % [str(ev.pubkey), int(ev.created_at), int(ev.kind), str(ev.tags[0][1]), str(ev.content)]
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.to_utf8_buffer())
	return h.finish().hex_encode()


func _verteilen(roh: String, z: String) -> void:
	for p in peers:
		for abo in p.subs.keys():
			if z in p.subs[abo]:
				(p.ws as WebSocketPeer).send_text("[\"EVENT\",\"%s\",%s]" % [abo, roh])


## Das „böse Relay“: schickt jedem Abonnenten, was es will.
func _an_alle(t: String, binaer := false) -> void:
	for p in peers:
		for abo in p.subs.keys():
			var x := t.replace("%ABO%", abo)
			if binaer:
				(p.ws as WebSocketPeer).send(x.to_utf8_buffer(), WebSocketPeer.WRITE_MODE_BINARY)
			else:
				(p.ws as WebSocketPeer).send_text(x)


func _ereignis(z: String, inhalt: String, zeit: int) -> String:
	var pub := Crypto.new().generate_random_bytes(32).hex_encode()
	var ev := { "pubkey": pub, "created_at": zeit, "kind": 20777, "tags": [["z", z]], "content": inhalt }
	return "{\"id\":\"%s\",\"pubkey\":\"%s\",\"created_at\":%d,\"kind\":20777,\"tags\":[[\"z\",\"%s\"]],\"content\":\"%s\",\"sig\":\"%s\"}" % [
			_id(ev), pub, zeit, z, inhalt, "0".repeat(128)]


# --- Gastgeber --------------------------------------------------------------------------------------

func _warte(tp: TP, bis: Callable, sek: float, gesehen: Array) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sek * 1000.0):
		gesehen.append_array(tp.pumpen(_jetzt()))
		if bis.call():
			return true
		await get_tree().process_frame
	return false


func _gastgeber() -> void:
	print("Zwei Uzai-Instanzen, ein Relay auf 127.0.0.1")
	if OS.get_environment("UZAI_PWSH") == "":
		print("  (UZAI_PWSH fehlt – übersprungen)")
		return
	libs = _netzlibs()
	print("  mit Netz-Bibliotheken (echte Signatur, echter Datenkanal)" if libs else "  (ohne Netz-Bibliotheken: Test-Angebot statt Datenkanal)")
	check(server.listen(0, "127.0.0.1") == OK, "Test-Relay lauscht nur auf 127.0.0.1")
	port = server.get_local_port()
	var s := _sandbox("gastgeber")
	check(s != null and s.laeuft(), "Sandbox des Gastgebers gestartet")
	var tp := TP.new("gastgeber", s)
	check(tp.starten(port), "Treffpunkt gestartet (Test-Relay)")
	var ev: Array = []
	check(await _warte(tp, func() -> bool: return tp.relays == Vector2i(1, 1), 90.0, ev), "Gastgeber mit dem Relay verbunden")
	var link := tp.einladen(_jetzt(), 60, "Mila", "discord")
	check(link.begins_with("uzai://zimmer#z1."), "Einladung an Mila (Link mit Schlüssel hinter #)")
	# Der Gast: eine zweite kopflose Instanz mit eigener Sandbox.
	var daten := OS.get_environment("UZAI_DATA")
	var gast_daten := daten.path_join("gast")
	DirAccess.make_dir_recursive_absolute(gast_daten)
	var datei := gast_daten.path_join("ergebnis.txt")
	OS.set_environment("UZAI_DATA", gast_daten)
	var gpid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/net_zimmer_treff.tscn", "--", "--gast", str(port), link, datei]))
	OS.set_environment("UZAI_DATA", daten)
	check(gpid > 0, "zweite Instanz (Gast) gestartet")
	var klopft := {}
	var hat_klopft := func() -> bool:
		for e in ev:
			if e.art == "klopft":
				klopft.merge(e)
				return true
		return false
	check(await _warte(tp, hat_klopft, 120.0, ev), "Mila klopft an")
	check(str(klopft.get("name", "")) == "Mila" and str(klopft.get("quelle", "")) == "discord" and tp.online.wartend.size() == 1,
			"angezeigt wird der Name aus der Einladung (der Gast schickt keinen)")
	check(not ("203.0.113" in "".join(texte)), "vor der Annahme: keine Adresse unterwegs")
	check(tp.annehmen(str(klopft.id), _jetzt()) == "ok" and tp.plaetze.get(str(klopft.id)) == 0, "hereingelassen: Platz 0")
	var verbunden := func() -> bool:
		for e in ev:
			if e.art == "stand" and e.was == "verbunden":
				return true
		return false
	check(await _warte(tp, verbunden, 60.0, ev), "Verbindungsangebote über den Sitzungsschlüssel: verbunden")
	if libs:
		# Über den echten Datenkanal: „hallo“ zum Gast, der antwortet mit seiner Position (beide Prüfmauern je Seite).
		s.schicken(s.leitung.senden(0, "hallo", { "geraet": "uzai" }))
		var antwort := func() -> bool:
			for e in ev:
				if e.art == "nachricht" and int(e.platz) == 0 and str(e.m.a) == "pos":
					return true
			return false
		check(await _warte(tp, antwort, 30.0, ev), "Datenkanal: „hallo“ zum Gast, seine Position kommt zurück (geprüft)")
	# Die Antwort des Gastgebers soll den Gast erreichen, bevor das böse Relay flutet (eine Flut auf
	# einem Relay bremst es ganz – darum mehrere Relays als Rückfall).
	await get_tree().create_timer(3.0).timeout
	# Böser Gast und böses Relay.
	print("Böser Gast, böses Relay")
	var z := ""
	for t in texte:
		if t.begins_with("[\"REQ\""):
			z = (JSON.parse_string(t)[2]["#z"] as Array)[0]
	var st := { "vor": ev.size() }     # Lambdas sehen Variablen nur als Kopie – darum im Wörterbuch
	var unsinn := ["kein json", "[\"EVENT\",\"%ABO%\",{}]", "[\"EVENT\",\"%ABO%\"," + "[".repeat(50) + "]", "[\"EVENT\",\"fremd\",{\"id\":1}]", "{\"a\":1}",
			"[\"EVENT\",\"%ABO%\",{\"id\":\"x\",\"id\":\"y\"}]", "[1.5e300]", "[\"\\u0000\"]", "[\"EVENT\",\"%ABO%\",\"" + "A".repeat(9000) + "\"]"]
	for t in unsinn:
		_an_alle(t)
	for i in 20:
		_an_alle("[\"EVENT\",\"%ABO%\"," + _ereignis(z, Marshalls.raw_to_base64(PackedByteArray([1, 1]) + Crypto.new().generate_random_bytes(100)), _jetzt()) + "]")
	_an_alle("[\"EVENT\",\"%ABO%\"," + ereignisse[0] + "]")       # Wiederholung des echten Anklopfens
	for i in 300:
		_an_alle("[\"EVENT\",\"%ABO%\"," + _ereignis(z, Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(60)), _jetzt()) + "]")
	await get_tree().create_timer(1.5).timeout
	_an_alle("[\"" + "x".repeat(20000) + "\"]")                    # zu groß: Verbindung zu, neu
	var neu := func() -> bool:
		var weg := false
		for e in ev.slice(int(st.vor)):
			if e.art == "stand" and e.was == "relays":
				weg = weg or int(e.a) == 0
				if weg and int(e.a) == 1:
					return true
		return false
	check(await _warte(tp, neu, 30.0, ev), "zu große Nachricht: Verbindung zum Relay zu, danach neu")
	st.vor = ev.size()
	await get_tree().create_timer(1.0).timeout                    # neues Abo erst beim Relay
	_an_alle("binär", true)
	check(await _warte(tp, neu, 30.0, ev), "Binär-Rahmen: Verbindung zu, danach neu")
	tp.zaehler_anfordern()
	check(await _warte(tp, func() -> bool: return not tp.zaehler.is_empty(), 20.0, ev), "Zähler der Sandbox")
	var zz := tp.zaehler
	print("    ", zz)
	var klopft_n := 0
	for e in ev:
		if e.art == "klopft":
			klopft_n += 1
	check(klopft_n == 1 and tp.online.wartend.is_empty() and tp.online.gaeste.size() == 1, "nichts davon erreicht Uzai: kein weiteres Anklopfen")
	check(int(zz.get("unsinn", 0)) >= unsinn.size() - 1 and int(zz.get("gedrosselt", 0)) >= 100 and int(zz.get("relay", 0)) >= 2,
			"Unsinn verworfen, Flut gebremst, Relay-Fehler gezählt")
	check(int(zz.get("krypto", 0)) + int(zz.get("gedrosselt", 0)) + int(zz.get("unsinn", 0)) >= 20 and int(zz.get("wiederholt", 0)) >= 1,
			"falscher Schlüssel ungelesen verworfen, Wiederholung erkannt")
	check(s.laeuft() and s.leitung.kaputt == "", "Sandbox des Gastgebers hält stand, Leitung in Ordnung")
	# Rauswerfen: der Gast erfährt es, seine Instanz endet.
	check(tp.rauswerfen(str(klopft.id)) and tp.online.gaeste.is_empty() and tp.plaetze.is_empty(), "rausgeworfen")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and OS.is_process_running(gpid):
		tp.pumpen(_jetzt())
		await get_tree().process_frame
	var g := FileAccess.get_file_as_string(datei)
	print("    Gast: ", g)
	check(g.contains("angenommen=1") and g.contains("verbunden=1"), "Gast: angenommen und verbunden")
	if libs:
		check(g.contains("hallo=1"), "Gast: „hallo“ kam über den Datenkanal an")
	check(g.contains("zu=1") and g.contains("kaputt=-"), "Gast: Rauswurf kam an, seine Leitung blieb in Ordnung")
	var alle := "".join(texte)
	check(not alle.contains("203.0.113") and not alle.contains("192.168") and not alle.contains(link.get_slice(".", 2)), "beim Relay: keine Adresse, kein Schlüssel – nur versiegelte Kisten")
	tp.offline()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and s.laeuft():
		await get_tree().process_frame
	check(not s.laeuft(), "„Zimmer offline“: Sandbox beendet")
	if OS.is_process_running(gpid):
		OS.kill(gpid)
	if libs:
		print("Verbindungstest der Oberfläche (zwei Sandboxen, Test-Relay)")
		var v: Dictionary = await VT.laufen(get_tree(), 90.0, _sandbox, port)
		print("    ", v)
		check(bool(v.ok) and bool(v.klopft) and bool(v.verbunden) and int(v.relays) == 1, "anklopfen, verbinden, Nachricht hin und zurück")
		await _freundestest()
	server.stop()


# --- Gast (zweite Instanz) -------------------------------------------------------------------------

func _gast(p: int, link: String, datei: String) -> void:
	var s := _sandbox("gast")
	var r := { "angenommen": 0, "verbunden": 0, "zu": 0, "hallo": 0 }
	if s != null:
		var tp := TP.new("gast", s)
		tp.starten(p)
		tp.besuchen(link)
		var t0 := Time.get_ticks_msec()
		var staende: Array = []
		var schreiben := func() -> void:
			var f := FileAccess.open(datei, FileAccess.WRITE)
			f.store_string("angenommen=%d verbunden=%d zu=%d hallo=%d kaputt=%s staende=%s" % [r.angenommen, r.verbunden, r.zu, r.hallo,
					s.leitung.kaputt if s.leitung.kaputt != "" else "-", ",".join(staende)] + " zaehler=" + str(tp.zaehler))
			f.close()
		schreiben.call()
		var takt := 0
		while Time.get_ticks_msec() - t0 < 150000 and r.zu == 0 and s.leitung.kaputt == "":
			takt += 1
			if takt % 120 == 0:
				tp.zaehler_anfordern()
			for e in tp.pumpen(_jetzt()):
				if e.art == "treff_zaehler":
					schreiben.call()
				if e.art == "nachricht" and str(e.m.a) == "hallo" and r.hallo == 0:
					r.hallo = 1
					s.schicken(s.leitung.senden(0, "pos", { "x": 120, "y": 0, "z": 340, "yaw": 0, "pitch": 0 }))
					schreiben.call()
				if e.art == "stand":
					staende.append("%s:%d/%d" % [e.was, e.a, e.b])
					if r.has(str(e.was)):
						r[str(e.was)] = 1
					schreiben.call()
			await get_tree().process_frame
		s.beenden()
		schreiben.call()
	get_tree().quit(0)


# --- Freundestest mit zwei Instanzen ---------------------------------------------------------------------

func _bis(bed: Callable, sek: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sek * 1000.0):
		if bed.call():
			return true
		await get_tree().process_frame
	return false


func _freundestest() -> void:
	print("Freundestest (zwei Instanzen, Code, echter Datenkanal)")
	var ft: Node = FT.gastgeber_starten(get_tree(), _sandbox, port, false)
	check(await _bis(func() -> bool: return ft.bereit(), 60.0), "Gastgeber bereit (Relay verbunden)")
	var e: Dictionary = ft.einladen("Mila", 15)
	var code := Einladung.code_anzeige(str(e.get("code", "")))
	check(code.length() == 46 and ft.einladung_rest() > 14 * 60, "Einladung als Code (%s…), 15 Min. gültig" % code.substr(0, 7))
	var daten := OS.get_environment("UZAI_DATA")
	var gd := daten.path_join("freund")
	DirAccess.make_dir_recursive_absolute(gd)
	var datei := gd.path_join("ergebnis.txt")
	var cdatei := gd.path_join("code2.txt")
	OS.set_environment("UZAI_DATA", gd)
	var gpid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/net_zimmer_treff.tscn", "--", "--freund", str(port), code, datei, cdatei]))
	OS.set_environment("UZAI_DATA", daten)
	check(gpid > 0, "zweite Instanz (Freund) gestartet")
	var g := func() -> String: return FileAccess.get_file_as_string(datei)
	check(await _bis(func() -> bool: return not (ft.anklopfer as Array).is_empty(), 90.0), "Code gelesen, Freund klopft an")
	check(ft.anklopfer.size() == 1 and str(ft.anklopfer[0].name) == "Mila", "„Mila möchte rein“ (Name aus der Einladung)")
	check(ft.annehmen(str(ft.anklopfer[0].id)) == "ok", "angenommen")
	var da := func() -> bool: return ft.figuren().has("p0")
	check(await _bis(da, 60.0), "verbunden, „hallo“ beider Seiten: Mila ist im Zimmer")
	ft.ich_setzen(Vector3(2.0, 0, 2.5), 0.7, 0.0)
	ft.emote_senden("winken")
	ft.satz_senden("hallo")
	var vom_gast := func() -> bool:
		var f: Dictionary = ft.figuren().get("p0", {})
		return not f.is_empty() and (f.p as Vector3).is_equal_approx(Vector3(1.2, 0, 3.4)) and str(f.emote) == "tanzen" and str(f.satz) == "gg"
	check(await _bis(vom_gast, 30.0), "vom Freund: Lage, Blick, Emote „tanzen“, Satz „Gut gespielt!“")
	var beim_gast := func() -> bool:
		var t: String = g.call()
		return t.contains("raum=1") and t.contains("wirt_pos=1") and t.contains("wirt_emote=1") and t.contains("wirt_satz=1")
	check(await _bis(beim_gast, 30.0), "beim Freund: das Zimmer (geprüft), Lage, Emote und Satz des Gastgebers")
	var f0: Dictionary = ft.figuren().get("p0", {})
	check(not f0.is_empty() and absf(float(f0.yaw) - 1.571) < 0.002, "Blickrichtung kommt an")
	ft.rauswerfen(0)
	check(await _bis(func() -> bool: return g.call().contains("zu=1"), 30.0), "rausgeworfen: beim Freund „Verbindung beendet“")
	check(await _bis(func() -> bool: return g.call().contains("zweiter=klopft"), 30.0), "Freund versucht es mit demselben Code noch einmal")
	await get_tree().create_timer(32.0).timeout
	check(ft.anklopfer.is_empty() and ft.gaeste.is_empty() and g.call().contains("zweiter=klopft"), "derselbe Code: niemand klopft beim Gastgeber an (einmalig)")
	# Böser Gast: eine neue Einladung, dann Flut und Unsinn.
	var e2: Dictionary = ft.einladen("Ben", 15)
	var f := FileAccess.open(cdatei, FileAccess.WRITE)
	f.store_string(Einladung.code_anzeige(str(e2.code)))
	f.close()
	check(await _bis(func() -> bool: return not (ft.anklopfer as Array).is_empty(), 90.0), "böser Gast klopft mit neuer Einladung an")
	ft.annehmen(str(ft.anklopfer[0].id))
	check(await _bis(da, 60.0), "böser Gast verbunden")
	var raus := func() -> bool: return ft.gaeste.is_empty() and g.call().contains("boese=") and not g.call().contains("boese=-")
	check(await _bis(raus, 60.0), "Flut: der böse Gast fliegt raus (%s)" % g.call().get_slice("boese=", 1).get_slice(" ", 0))
	check(ft.zustand == "bereit" and ft.tp.sitzung.leitung.kaputt == "" and ft.tp.sitzung.laeuft(), "Gastgeber läuft weiter, Leitung in Ordnung")
	check(g.call().contains("unsinn_verworfen=2"), "Unsinn des Gastes verlässt seinen PC nicht (seine Sandbox verwirft beide)")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and OS.is_process_running(gpid):
		await get_tree().process_frame
	print("    Freund: ", g.call())
	ft.beenden("offline")
	await get_tree().create_timer(1.0).timeout
	var geheim := [code, code.replace("-", ""), str(e.code), str(e2.code), "Mila", "Ben", "127.0.0.1", (e.schluessel as PackedByteArray).hex_encode()]
	var sauber := true
	for l in [Config.path(FT.LOG), gd.path_join(FT.LOG)]:
		var t := FileAccess.get_file_as_string(l)
		sauber = sauber and t.length() > 300
		for x in geheim:
			if t.contains(str(x)):
				sauber = false
				print("    im Protokoll: ", str(x).substr(0, 6), "… (", l.get_file(), ")")
	check(sauber, "logs/zimmer_online.log beider Seiten: Schritte und Gründe, kein Code, Name oder Adresse")
	if OS.is_process_running(gpid):
		OS.kill(gpid)


func _freund_gast(p: int, code: String, datei: String, cdatei: String) -> void:
	var r := { "verbunden": 0, "raum": 0, "wirt_pos": 0, "wirt_emote": 0, "wirt_satz": 0, "zu": 0, "grund1": "-", "zweiter": "-", "boese": "-", "unsinn_verworfen": -1 }
	var schreiben := func() -> void:
		var f := FileAccess.open(datei, FileAccess.WRITE)
		var teile: PackedStringArray = []
		for k in r:
			teile.append("%s=%s" % [k, str(r[k])])
		f.store_string(" ".join(teile))
		f.close()
	var ft: Node = FT.gast_starten(get_tree(), code, _sandbox, p, false)
	var gesendet := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 150000 and ft.zustand != "ende":
		if ft.zustand == "verbunden":
			r.verbunden = 1
			r.raum = 1 if not (ft.gast_raum as Dictionary).is_empty() else 0
			var w: Dictionary = ft.figuren().get(FT.WIRT, {})
			if not w.is_empty():
				r.wirt_pos = 1 if (w.p as Vector3).is_equal_approx(Vector3(2.0, 0, 2.5)) else 0
				r.wirt_emote = 1 if str(w.emote) == "winken" else r.wirt_emote
				r.wirt_satz = 1 if str(w.satz) == "hallo" else r.wirt_satz
			if not gesendet and r.raum == 1:
				gesendet = true
				ft.ich_setzen(Vector3(1.2, 0, 3.4), 1.571, 0.0)
				ft.emote_senden("tanzen")
				ft.satz_senden("gg")
		schreiben.call()
		await get_tree().process_frame
	r.zu = 1 if ft.grund == "zu" else 0
	r.grund1 = ft.grund
	schreiben.call()
	await get_tree().create_timer(1.0).timeout
	# Derselbe Code noch einmal: das Postfach ist zu.
	ft = FT.gast_starten(get_tree(), code, _sandbox, p, false)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not FileAccess.file_exists(cdatei):
		r.zweiter = ft.zustand
		schreiben.call()
		await get_tree().process_frame
	ft.beenden()
	await get_tree().create_timer(1.0).timeout
	# Böser Gast: neue Einladung, dann Unsinn und Flut.
	ft = FT.gast_starten(get_tree(), FileAccess.get_file_as_string(cdatei), _sandbox, p, false)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000 and ft.zustand != "verbunden" and ft.zustand != "ende":
		await get_tree().process_frame
	if ft.zustand == "verbunden":
		var s: ZN.Sitzung = ft.tp.sitzung
		s.schicken(ZN.rahmen(ZN.SENDEN, PackedByteArray([0]) + "{\"a\":\"chat\",\"d\":{\"text\":\"<script>\"}}".to_utf8_buffer()))
		s.schicken(ZN.rahmen(ZN.SENDEN, PackedByteArray([0, 0x55, 2, 3, 99])))
		s.schicken(ZN.rahmen(ZN.ZAEHLER))
		for i in 300:
			s.schicken(s.leitung.senden(0, "pos", { "x": 100 + i % 50, "y": 0, "z": 100, "yaw": 0, "pitch": 0 }))
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 60000 and ft.zustand != "ende":
			await get_tree().process_frame
	r.boese = ft.grund if ft.zustand == "ende" else "noch_da"
	r.unsinn_verworfen = int(ft.leitung_zaehler.get("aus_verworfen", -1))
	schreiben.call()
	get_tree().quit(0)

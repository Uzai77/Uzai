extends RefCounted
## HTTP-Abrufe in einem eigenen Faden. Net (src/core/net.gd) reicht jede Anfrage und jeden großen Download
## hierher; geprüft in tests/net_abruf.gd (nachgebauter Server tests/fake_netz.py).
##
## Warum nicht Godots HTTPRequest (so lief es bis 0.16): Mit use_threads liest sein Faden die Antwort
## blockierend. Nimmt ein Server die Verbindung an und schickt dann nichts mehr (WLAN-Wechsel, Standby mit
## offenen Verbindungen, hängender Dienst), dreht der Faden für immer – und läuft das Zeitlimit ab, wartet
## der Hauptfaden in cancel_request() auf ihn: Uzai steht, statt eine Zeitüberschreitung zu melden. Gemessen
## in Godot 4.5.1: Ohne Fäden kommt nach dem Limit sauber RESULT_TIMEOUT, mit Fäden lebt der Hauptfaden
## danach nicht mehr. Ohne Fäden liefe dafür jede Verschlüsselung im Hauptfaden (jede Verbindung einige
## Millisekunden, zehn Bilder zugleich: das Menü stockt).
##
## Darum ein Faden für alle Abrufe: HTTPClient ohne Blockieren, reihum einen Schritt je Abruf. Fristen und
## Abbruch prüft jeder Schritt, nichts wartet je auf einen Server. Das Ergebnis kommt im Hauptfaden an.
##
## Verhalten wie vorher mit HTTPRequest, damit sich für die Aufrufer nichts ändert:
##   - Ergebnis-Codes sind die von HTTPRequest (RESULT_SUCCESS, RESULT_TIMEOUT, …), dazu ABGEBROCHEN.
##   - Gefolgt wird nur 301 und 302, mit derselben Methode, höchstens UMLEITUNGEN_MAX-mal. Ohne Folgen
##     endet der Abruf dort mit RESULT_REDIRECT_LIMIT_REACHED, Code und Kopfzeilen stehen im Ergebnis.
##   - Antworten kommen gepackt (gzip, deflate) und werden hier entpackt; Dateien lädt Uzai ungepackt.

const Arbeit := preload("res://src/core/arbeit.gd")
const Sicher := preload("res://src/core/sicher.gd")

const UMLEITUNGEN_MAX := 8
## So viel liest ein Schritt höchstens aus einer Antwort (danach ist der nächste Abruf dran).
const STUECK := 262144
## Abbruch auf Wunsch (Auftrag.stop) und „gar nicht erst gesendet“ (keine gültige Adresse): keine Codes von HTTPRequest.
const ABGEBROCHEN := -2
const NICHT_GESENDET := -1

const _WARTET := 0
const _BEWEGT := 1
const _FERTIG := 2

const _VERBINDEN := 0
const _ANTWORT := 1
const _INHALT := 2

static var _schloss := Mutex.new()
static var _wecker := Semaphore.new()
static var _neu: Array = []
static var _laeuft := false
## Nur für Proben: ein eigenes Zertifikat, dem der Netzfaden vertraut (nachgebauter Server mit TLS). Im Betrieb
## bleibt es leer, und es gelten die Zertifikate, denen Godot vertraut.
static var probe_tls: TLSOptions = null


## Ein Abruf. Felder oben setzt der Aufrufer vor starten(); ergebnis und fertig ändern sich nur im Hauptfaden.
class Auftrag extends RefCounted:
	## Im Hauptfaden, sobald fertig wahr ist.
	signal erledigt
	var url := ""
	var methode := HTTPClient.METHOD_GET
	var kopf := PackedStringArray()
	var inhalt := ""
	var frist_ms := 0            ## für den ganzen Abruf (0 = keine)
	var still_ms := 0            ## so lange ohne ein neues Byte (0 = keine Grenze)
	var grenze := 0              ## größte Antwort in Bytes (0 = keine)
	var folgen := true
	var datei := ""              ## Antwort in diese Datei statt in den Speicher
	var stop := false            ## vom Hauptfaden gesetzt: abbrechen
	## Fortschritt (der Hauptfaden liest nur)
	var geladen := 0
	var gesamt := -1
	## { result, code, headers, body } wie request_completed von HTTPRequest
	var ergebnis := {}
	var fertig := false
	# Ab hier nur der Netzfaden.
	var _client: HTTPClient
	var _phase := 0
	var _umleitungen := 0
	var _beginn_ms := 0
	var _bewegt_ms := 0
	var _stand := -1
	var _code := 0
	var _antwort_kopf := PackedStringArray()
	var _daten := PackedByteArray()
	var _f: FileAccess
	var _laenge := -1
	var _gepackt := ""


## Adresse zerlegen: { tls, host, port, pfad } oder {} (kein http/https, kein Host).
static func adresse(url: String) -> Dictionary:
	var p := Sicher.url_parts(url)
	if p.is_empty() or not (p.scheme == "http" or p.scheme == "https"):
		return {}
	var u := url.strip_edges()
	var rest := u.substr(u.find("://") + 3)
	var cut := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < cut:
			cut = i
	var pfad := rest.substr(cut).get_slice("#", 0)
	if not pfad.begins_with("/"):
		pfad = "/" + pfad
	var tls: bool = p.scheme == "https"
	return { "tls": tls, "host": str(p.host), "port": int(p.port) if str(p.port) != "" else (443 if tls else 80), "pfad": pfad }


## Abruf starten (Hauptfaden). Danach auf a.erledigt warten, wenn a.fertig noch nicht wahr ist.
static func starten(a: Auftrag) -> void:
	_schloss.lock()
	var faden_fehlt := not _laeuft
	if faden_fehlt:
		_laeuft = true
	_neu.append(a)
	_schloss.unlock()
	if faden_fehlt and not Arbeit.dauerfaden(_schleife, _wecker.post):
		# Uzai beendet sich: Es gibt keinen Faden mehr, der Abruf endet sofort.
		_schloss.lock()
		_neu.erase(a)
		_laeuft = false
		_schloss.unlock()
		_melden(a, { "result": ABGEBROCHEN, "code": 0, "headers": PackedStringArray(), "body": PackedByteArray() })
		return
	_wecker.post()


## Abruf starten und auf das Ergebnis warten (Hauptfaden).
static func holen(a: Auftrag) -> Dictionary:
	starten(a)
	if not a.fertig:
		await a.erledigt
	return a.ergebnis


static func _schleife() -> void:
	var aktiv: Array = []
	while not Arbeit.endet:
		_schloss.lock()
		aktiv.append_array(_neu)
		_neu.clear()
		_schloss.unlock()
		if aktiv.is_empty():
			_wecker.wait()
			continue
		var bewegt := false
		var bleibt: Array = []
		for a: Auftrag in aktiv:
			var e := _schritt(a)
			if e != _FERTIG:
				bleibt.append(a)
			if e != _WARTET:
				bewegt = true
		aktiv = bleibt
		if not bewegt:
			OS.delay_usec(1500)
	for a: Auftrag in aktiv:
		_schliessen(a)
	_schloss.lock()
	_laeuft = false
	_schloss.unlock()


## Ein Schritt eines Abrufs, ohne zu warten.
static func _schritt(a: Auftrag) -> int:
	var jetzt := Time.get_ticks_msec()
	if a._beginn_ms == 0:
		a._beginn_ms = jetzt
		a._bewegt_ms = jetzt
	if a.stop:
		return _ende(a, ABGEBROCHEN)
	if (a.frist_ms > 0 and jetzt - a._beginn_ms > a.frist_ms) or (a.still_ms > 0 and jetzt - a._bewegt_ms > a.still_ms):
		return _ende(a, HTTPRequest.RESULT_TIMEOUT)
	if a._client == null:
		return _verbinden(a)
	a._client.poll()
	var st := a._client.get_status()
	var e := _WARTET
	if st != a._stand:
		# Jeder Schritt weiter (Name aufgelöst, verbunden, Anfrage raus) zählt als Bewegung.
		a._stand = st
		a._bewegt_ms = jetzt
		e = _BEWEGT
	match st:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			return e
		HTTPClient.STATUS_CANT_RESOLVE:
			return _ende(a, HTTPRequest.RESULT_CANT_RESOLVE)
		HTTPClient.STATUS_CANT_CONNECT:
			return _ende(a, HTTPRequest.RESULT_CANT_CONNECT)
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return _ende(a, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR)
		HTTPClient.STATUS_CONNECTED:
			if a._phase == _VERBINDEN:
				return _anfragen(a)
			if a._phase == _ANTWORT:
				# Antwort ohne Inhalt (204, HEAD, Umleitung ohne Text).
				var u := _kopf_lesen(a)
				return u if u != _WARTET else _ende(a, HTTPRequest.RESULT_SUCCESS)
			# Inhalt ganz gelesen (mit Längenangabe: nur, wenn sie stimmt).
			return _ende(a, HTTPRequest.RESULT_SUCCESS if a._laenge < 0 or a.geladen == a._laenge else HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH)
		HTTPClient.STATUS_BODY:
			if a._phase == _ANTWORT:
				var u := _kopf_lesen(a)
				if u != _WARTET:
					return u
				var v := _inhalt_beginnen(a)
				if v != _WARTET:
					return v
			return _inhalt_lesen(a, jetzt)
	# Getrennt oder Verbindungsfehler. Ohne Längenangabe heißt „getrennt“ nach dem Kopf: Die Antwort ist zu Ende.
	if st == HTTPClient.STATUS_DISCONNECTED and a._phase == _INHALT and a._laenge < 0:
		return _ende(a, HTTPRequest.RESULT_SUCCESS)
	return _ende(a, HTTPRequest.RESULT_CONNECTION_ERROR)


static func _verbinden(a: Auftrag) -> int:
	var ziel := adresse(a.url)
	if ziel.is_empty():
		return _ende(a, NICHT_GESENDET)
	a._client = HTTPClient.new()
	a._client.read_chunk_size = STUECK
	a._phase = _VERBINDEN
	a._stand = -1
	var tls: TLSOptions = null
	if bool(ziel.tls):
		tls = probe_tls if probe_tls != null else TLSOptions.client()
	if a._client.connect_to_host(str(ziel.host), int(ziel.port), tls) != OK:
		return _ende(a, NICHT_GESENDET)
	return _BEWEGT


static func _anfragen(a: Auftrag) -> int:
	var kopf := a.kopf.duplicate()
	# Gepackte Antworten annehmen (JSON schrumpft auf ein Fünftel); Dateien kommen, wie sie sind.
	if a.datei == "" and not _hat(kopf, "accept-encoding"):
		kopf.append("Accept-Encoding: gzip, deflate")
	if a._client.request(a.methode, str(adresse(a.url).pfad), kopf, a.inhalt) != OK:
		return _ende(a, HTTPRequest.RESULT_CONNECTION_ERROR)
	a._phase = _ANTWORT
	return _BEWEGT


## Code und Kopfzeilen der Antwort; folgt einer Umleitung. _WARTET heißt hier: weiter mit dem Inhalt.
static func _kopf_lesen(a: Auftrag) -> int:
	a._code = a._client.get_response_code()
	a._antwort_kopf = a._client.get_response_headers()
	if a._code != 301 and a._code != 302:
		return _WARTET
	if not a.folgen or a._umleitungen >= UMLEITUNGEN_MAX:
		return _ende(a, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED)
	var ziel := Sicher.redirect_target(a.url, _wert(a._antwort_kopf, "location"))
	if ziel == "" or adresse(ziel).is_empty():
		return _WARTET
	if not Sicher.same_origin(a.url, ziel):
		# Zu einem anderen Ursprung nie mit Zugangsdaten: Ein Schlüssel in den Kopfzeilen oder ein Formular mit einer
		# Anmeldung landete sonst bei einem fremden Host. Nur Lesen folgt, mit den harmlosen Kopfzeilen; alles
		# andere (POST, PUT …) und der Schritt von https zurück zu http enden hier.
		if not (a.methode in [HTTPClient.METHOD_GET, HTTPClient.METHOD_HEAD]) or (bool(adresse(a.url).tls) and not bool(adresse(ziel).tls)):
			return _ende(a, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED)
		a.kopf = harmlos(a.kopf)
		a.inhalt = ""
	_schliessen(a)
	a.url = ziel
	a._umleitungen += 1
	a._code = 0
	a._antwort_kopf = PackedStringArray()
	return _BEWEGT


static func _inhalt_beginnen(a: Auftrag) -> int:
	a._phase = _INHALT
	a._laenge = -1 if a._client.is_response_chunked() else a._client.get_response_body_length()
	a.gesamt = a._laenge
	if a._laenge == 0:
		return _ende(a, HTTPRequest.RESULT_SUCCESS)
	if a.grenze > 0 and a._laenge > a.grenze:
		return _ende(a, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
	var packung := _wert(a._antwort_kopf, "content-encoding").to_lower()
	a._gepackt = packung if a.datei == "" and packung in ["gzip", "deflate"] else ""
	if a.datei != "":
		a._f = FileAccess.open(a.datei, FileAccess.WRITE)
		if a._f == null:
			return _ende(a, HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN)
	return _WARTET


static func _inhalt_lesen(a: Auftrag, jetzt: int) -> int:
	var stueck := a._client.read_response_body_chunk()
	if stueck.is_empty():
		return _WARTET
	a._bewegt_ms = jetzt
	a.geladen += stueck.size()
	if a.grenze > 0 and a.geladen > a.grenze:
		return _ende(a, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
	if a._f != null:
		a._f.store_buffer(stueck)
		if a._f.get_error() != OK:
			return _ende(a, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR)
	else:
		a._daten.append_array(stueck)
	if a._laenge >= 0 and a.geladen >= a._laenge:
		return _ende(a, HTTPRequest.RESULT_SUCCESS)
	return _BEWEGT


static func _ende(a: Auftrag, ergebnis: int) -> int:
	_schliessen(a)
	var daten := a._daten
	a._daten = PackedByteArray()
	if ergebnis == HTTPRequest.RESULT_SUCCESS and a._gepackt != "" and not daten.is_empty():
		# Höchstens bis zur Grenze entpacken (eine kleine Antwort darf nicht zu Gigabytes werden).
		var hoechstens := a.grenze if a.grenze > 0 else -1
		daten = daten.decompress_dynamic(hoechstens, FileAccess.COMPRESSION_GZIP if a._gepackt == "gzip" else FileAccess.COMPRESSION_DEFLATE)
		if daten.is_empty():
			ergebnis = HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED if a.grenze > 0 else HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED
	_melden.call_deferred(a, { "result": ergebnis, "code": a._code, "headers": a._antwort_kopf, "body": daten })
	return _FERTIG


static func _schliessen(a: Auftrag) -> void:
	if a._client != null:
		a._client.close()
		a._client = null
	if a._f != null:
		a._f.close()
		a._f = null


## Im Hauptfaden.
static func _melden(a: Auftrag, ergebnis: Dictionary) -> void:
	a.ergebnis = ergebnis
	a.fertig = true
	if not Arbeit.endet:
		a.erledigt.emit()


## Kopfzeilen, die auch ein fremder Host sehen darf (nach einer Umleitung zu einem anderen Ursprung): alles andere
## kann ein Zugang sein (Authorization, X-API-Key, X-Plex-Token, Cookie, Client-Id …) und bleibt zurück.
const HARMLOS := ["user-agent", "accept", "accept-language", "range"]


static func harmlos(kopf: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for h in kopf:
		if h.get_slice(":", 0).strip_edges().to_lower() in HARMLOS:
			out.append(h)
	return out


static func _hat(kopf: PackedStringArray, name: String) -> bool:
	for h in kopf:
		if h.to_lower().begins_with(name + ":"):
			return true
	return false


static func _wert(kopf: PackedStringArray, name: String) -> String:
	for h in kopf:
		if h.to_lower().begins_with(name + ":"):
			return h.substr(name.length() + 1).strip_edges()
	return ""

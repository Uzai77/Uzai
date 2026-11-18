extends Node
## HTTP für Bilder und Web-Schnittstellen (Steam, RetroAchievements, Spotify, Discord-Widget).
## Zwei getrennte Spuren: Daten (Shop-Listen, Spotify, Steam) und Bilder. Früher teilten sich
## alle sechs Plätze – lud der Shop Dutzende Bilder, warteten Spotify und Shop-Daten dahinter.

## Nuvio hat eigene Plätze: ein Abgleich soll Bilder und Kataloge nie ausbremsen. Die Feeds der
## YouTube-Abos (je Kanal eine Anfrage, bei vielen Abos Hunderte) auch: Sie liefen früher über
## „api“ und Filme-Kataloge, Twitch-Bilder und Shop warteten beim Start dahinter.
const MAX_PARALLEL := { "api": 8, "img": 10, "nuvio": 3, "yt": 8 }
const Arbeit := preload("res://src/core/arbeit.gd")
const Abruf := preload("res://src/core/abruf.gd")
const Doktor := preload("res://src/core/doktor.gd")
const Fremd := preload("res://src/core/fremd.gd")
## Fassung und Repository aus Config (früher fest „Uzai/0.1“).
const UA := "Uzai/" + preload("res://src/core/config.gd").VERSION + " (+https://github.com/" + preload("res://src/core/config.gd").REPO + ")"
## Größter Bild-Download: Steam- und SteamGridDB-Hintergründe in 4K haben einige MB. Was größer
## ist, ist kein Spielbild – abbrechen, statt es in den Speicher zu laden.
const IMG_MAX_BYTES := 32 * 1024 * 1024
## Größte Antwort einer Schnittstelle (JSON, Kataloge, Skripte). Die größten echten (Bibliotheken,
## Kataloge) haben wenige MB; ohne Grenze hätte ein fremder Server Uzai den Speicher füllen können.
const API_MAX_BYTES := 64 * 1024 * 1024

var _running := { "api": 0, "img": 0, "nuvio": 0, "yt": 0 }
## Für den Uzai-Doktor (src/core/doktor.gd), aus Antworten, die ohnehin kommen (nur beim Öffnen
## des Doktors fragt er einmal Steams öffentliche Server-Zeit): wann zuletzt etwas ankam, wie oft
## danach keine Verbindung zustande kam, und wie weit die Uhr dieses PCs von der Zeit der Server
## (Kopfzeile „Date“) abweicht.
var last_ok_ms := 0
var last_fail_ms := 0
var fails := 0                   ## Fehlschläge ohne Verbindung seit der letzten Antwort
var clock_skew := 0              ## Sekunden: Server minus PC
var clock_known := false
var _inflight := {}             ## Ziel-Datei -> wer außer dem laufenden Download noch darauf wartet (gleiche Bilder nur einmal laden)
var _schlange := { "api": [], "img": [], "nuvio": [], "yt": [] }   ## je Spur: wer auf einen Platz wartet, der Reihe nach


## Ein wartender Abruf. Er bekommt seinen Platz gezielt (dran) bzw. das Ergebnis des Downloads, auf den er wartet
## (fertig). Vorher gab es je ein Signal für alle: Jeder beendete Abruf weckte jeden wartenden, und bis auf einen
## legten sich alle wieder hin. Gemessen im Raster der Bibliothek mit rund 500 wartenden Bildern: 2,5 ms je
## beendetem Abruf, über 50.000 Weckrufe in einem Bild, 0,25 bis 0,35 s Stillstand, sobald viele Antworten
## zusammen kamen (ohne Netz bei jedem Blättern).
class _Warten extends RefCounted:
	signal dran
	signal fertig(ok: bool)

## Nur für Netz-Proben: Steams Adressen auf einen nachgebauten Server umlenken
## (UZAI_STEAM_API für api.steampowered.com, UZAI_STEAM_CDN für die Bildserver).
const TEST_HOSTS := {
	"UZAI_STEAM_API": ["https://api.steampowered.com"],
	"UZAI_STEAM_CDN": ["https://shared.steamstatic.com", "https://shared.akamai.steamstatic.com"],
}


## Adresse nach den Umleitungen für Netz-Proben (ohne Umgebungsvariablen: unverändert).
static func redirected(url: String) -> String:
	for env in TEST_HOSTS.keys():
		var to := Config.probe_env(str(env))
		if to == "":
			continue
		for host in TEST_HOSTS[env]:
			if url.begins_with(str(host) + "/"):
				return to.trim_suffix("/") + url.substr(str(host).length())
	return url


## Antwort: { ok: bool, code: int, body: PackedByteArray, headers: PackedStringArray }
## max_bytes: größte Antwort (0 = Standard: Bilder IMG_MAX_BYTES, sonst API_MAX_BYTES). follow:
## Weiterleitungen folgen – aus für Server mit Zugangsschlüssel, damit er nie bei einem anderen
## Host landet, und für Adressen aus fremden Daten (Sicher.redirect_target prüft jedes Ziel).
func request(url: String, headers: PackedStringArray = PackedStringArray(), method := HTTPClient.METHOD_GET, body := "", timeout := 15.0, lane := "api",
		max_bytes := 0, follow := true) -> Dictionary:
	if int(_running[lane]) >= int(MAX_PARALLEL[lane]):
		# Hinten anstellen. Der Platz wird übergeben (_platz_frei): Der Zähler bleibt dabei, wie er ist.
		var w := _Warten.new()
		(_schlange[lane] as Array).append(w)
		await w.dran
	else:
		_running[lane] = int(_running[lane]) + 1
	# Der Abruf selbst läuft im Netzfaden (src/core/abruf.gd, dort steht auch, warum nicht HTTPRequest).
	var a := Abruf.Auftrag.new()
	a.url = redirected(url)
	a.methode = method
	a.inhalt = body
	a.frist_ms = int(timeout * 1000.0)
	a.still_ms = 0 if timeout > 0.0 else still_ms
	a.grenze = max_bytes if max_bytes > 0 else (IMG_MAX_BYTES if lane == "img" else API_MAX_BYTES)
	a.folgen = follow
	var h := headers.duplicate()
	# Eigener User-Agent eines Dienstes (LRCLIB bittet um Name und Fassung) geht vor.
	if not Array(h).any(func(x: String) -> bool: return x.to_lower().begins_with("user-agent:")):
		h.append("User-Agent: " + UA)
	# Godot schickt bei leerem Körper keine Länge mit. Viele Dienste (Spotify: „Weiter“,
	# „Pause“) lehnen POST/PUT ohne Content-Length ab (411).
	if body == "" and method in [HTTPClient.METHOD_POST, HTTPClient.METHOD_PUT, HTTPClient.METHOD_PATCH, HTTPClient.METHOD_DELETE]:
		h.append("Content-Length: 0")
	a.kopf = h
	# result: wie bei HTTPRequest (RESULT_*) – für Protokolle („Name nicht auflösbar“ statt nur „kein Code“).
	var r := await Abruf.holen(a)
	# Erst den Platz weitergeben, dann auswerten. Über diesen Zähler läuft jeder Abruf: Bräche die Auswertung einmal
	# ab, bliebe der Platz für immer belegt, und nach wenigen solchen Fällen käme auf dieser Spur nichts mehr durch.
	_platz_frei(lane)
	var res := Fremd.zahl(r.get("result"), Abruf.NICHT_GESENDET)
	var code := Fremd.zahl(r.get("code"))
	var kopf: Variant = r.get("headers")
	var inhalt: Variant = r.get("body")
	var result := { "ok": res == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, "code": code,
		"body": inhalt if inhalt is PackedByteArray else PackedByteArray(), "headers": kopf if kopf is PackedStringArray else PackedStringArray(),
		"result": res }
	_note(res, result.headers)
	return result


## Ein Abruf ist zu Ende: Sein Platz geht an den, der am längsten wartet – sonst wird er frei.
func _platz_frei(lane: String) -> void:
	var schlange: Array = _schlange[lane]
	if schlange.is_empty():
		_running[lane] = int(_running[lane]) - 1
	else:
		(schlange.pop_front() as _Warten).dran.emit()


## Verbindung und Uhr mitschreiben (siehe last_ok_ms). Antwort mit Kopfzeilen: Netz da; keine
## Verbindung, keine Namensauflösung oder TLS-Fehler: ein Fehlschlag (TLS scheitert auch bei
## falscher Uhr – das sieht der Doktor dann an der Abweichung).
func _note(res: int, headers: Variant) -> void:
	var now := Time.get_ticks_msec()
	if res == HTTPRequest.RESULT_SUCCESS:
		last_ok_ms = now
		fails = 0
		if headers is PackedStringArray:
			var d := header({ "headers": headers }, "date")
			var t := Doktor.http_date(d) if d != "" else -1
			if t > 0:
				clock_skew = t - int(Time.get_unix_time_from_system())
				clock_known = true
	elif res in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
			HTTPRequest.RESULT_TIMEOUT]:
		last_fail_ms = now
		fails += 1


## Antwort: { ok, code, data, text, headers } – data ist das geparste JSON oder null; text ist der
## Rohtext, wenn die Antwort kein JSON war (Spotify und Steam schicken Ablehnungen oft als reinen
## Text – ohne ihn sähe man nur den HTTP-Code).
func get_json(url: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var r := await request(url, headers)
	var out := _decode(r) if (r.body as PackedByteArray).size() < JSON_OFF_BYTES else await _decode_off(r)
	out["ok"] = r.ok and out.data != null
	return out


## Ab dieser Größe liest ein Hilfsthread das JSON (Kataloge, YouTube-Startseite: oft 0,5–2 MB,
## im Hauptthread je 10–50 ms – genau beim Öffnen eines Bereichs, das Menü stockte). Gemessen: 49 KB
## brauchen 4,7 ms zum Lesen und 2,7 ms zum Säubern (Fremd.ohne_null); darum 64 statt früher 96 KB.
const JSON_OFF_BYTES := 64 * 1024


## JSON aus einer Antwort lesen: klein gleich, groß im Hintergrund. null, wenn es kein JSON ist.
func parse_json(bytes: PackedByteArray) -> Variant:
	if bytes.size() < JSON_OFF_BYTES:
		return parse_json_now(bytes)
	return await Arbeit.ergebnis(parse_json_now.bind(bytes))


static func parse_json_now(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	return Fremd.json(bytes.get_string_from_utf8())


## Wie _decode, das JSON aber im Hintergrund gelesen (große Antworten).
func _decode_off(r: Dictionary) -> Dictionary:
	var data: Variant = await parse_json(r.body)
	var text := "" if data != null else (r.body as PackedByteArray).get_string_from_utf8().strip_edges().left(400)
	return { "ok": r.ok, "code": r.code, "data": data, "text": text, "headers": r.get("headers", PackedStringArray()) }


static func _decode(r: Dictionary) -> Dictionary:
	var data: Variant = null
	var text := ""
	if r.body.size() > 0:
		text = (r.body as PackedByteArray).get_string_from_utf8()
		data = Fremd.json(text)
		text = "" if data != null else text.strip_edges().left(400)
	return { "ok": r.ok, "code": r.code, "data": data, "text": text, "headers": r.get("headers", PackedStringArray()) }


## Wert einer Kopfzeile der Antwort ("" wenn es sie nicht gibt), z. B. x-eresult bei Steam.
static func header(r: Dictionary, name: String) -> String:
	var want := name.to_lower() + ":"
	for h in r.get("headers", PackedStringArray()):
		if str(h).to_lower().begins_with(want):
			return str(h).substr(want.length()).strip_edges()
	return ""


func send_json(url: String, method: int, payload: Variant, headers: PackedStringArray = PackedStringArray(), lane := "api") -> Dictionary:
	var h := headers.duplicate()
	h.append("Content-Type: application/json")
	var body := "" if payload == null else JSON.stringify(payload)
	var r := await request(url, h, method, body, 15.0, lane)
	return _decode(r)


func post_form(url: String, fields: Dictionary, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var parts := PackedStringArray()
	for k in fields.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(fields[k]).uri_encode()])
	var h := headers.duplicate()
	h.append("Content-Type: application/x-www-form-urlencoded")
	var r := await request(url, h, HTTPClient.METHOD_POST, "&".join(parts))
	var out := _decode(r)
	out["ok"] = r.ok and out.data != null
	return out


## Lädt eine Datei in den Cache-Ordner und gibt den lokalen Pfad zurück ("" bei Fehler).
func download(url: String, dest: String) -> String:
	if FileAccess.file_exists(dest):
		return dest
	# Dasselbe Bild wird schon geladen (zwei Kacheln mit demselben Spiel): darauf warten.
	if _inflight.has(dest):
		var w := _Warten.new()
		(_inflight[dest] as Array).append(w)
		var da: bool = await w.fertig
		return dest if da else ""
	_inflight[dest] = []
	var out := await _download(url, dest)
	var mit: Array = _inflight[dest]
	_inflight.erase(dest)
	for w: _Warten in mit:
		w.fertig.emit(out != "")
	return out


func _download(url: String, dest: String) -> String:
	# Bildadressen kommen teils aus fremden Antworten (SteamGridDB, Wikipedia, Epic-Katalog): nur https.
	if not download_allowed(url):
		return ""
	# Bilder eines eigenen Medienservers: mit seiner Kopfzeile (Plex), ohne Weiterleitungen – aber nur für die
	# Bildpfade, die Uzai selbst baut. Ein Addon könnte sonst eine andere Adresse desselben Servers als „Poster“
	# nennen (/:/scrobble …, Bibliothek neu einlesen), und Uzai riefe sie mit deinem Schlüssel auf.
	var media: Variant = media_origins.get(origin(url)) if media_bildpfad(url) else null
	# Große Bilder (SteamGridDB-Hintergründe: mehrere MB) brauchen bei vielen gleichzeitigen
	# Downloads Zeit – 25 s waren zu knapp.
	var r := await request(url, media if media is PackedStringArray else PackedStringArray(), HTTPClient.METHOD_GET, "", 90.0, "img", IMG_MAX_BYTES, media == null)
	if not r.ok or r.body.size() < 64:
		return ""
	# Nur echte Bilder speichern: eine Fehler- oder Anmeldeseite mit Status 200 (WLAN-Portal,
	# Proxy, Verweis-Datei) würde sonst für immer als kaputtes Cover im Cache liegen.
	# BMP aus dem Netz nie: Godots eigener BMP-Lader ist der am wenigsten erprobte Dekoder (eine Adresse „x.bmp“ eines
	# Fremden landete sonst dort).
	if dest.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "gif", "bmp"] and not looks_like_image(r.body):
		return ""
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(r.body)
	f.close()
	return dest


## Bildpfad, den Uzai für einen Medienserver baut: Plex /photo/:/transcode?…, Jellyfin/Emby …/Items/<id>/Images/<Art>.
static var _RX_MEDIA_BILD := RegEx.create_from_string(
		"^(?:/photo/:/transcode\\?|(?:/[A-Za-z0-9._-]{1,40}){0,2}/Items/[0-9A-Za-z-]{1,64}/Images/[A-Za-z]{1,32}(?:\\?|$))")


static func media_bildpfad(url: String) -> bool:
	var o := origin(url)
	var u := url.strip_edges()
	if o == "" or not u.to_lower().begins_with(o):
		return false
	var p := u.substr(o.length())
	return not p.contains("..") and _RX_MEDIA_BILD.search(p) != null


static func looks_like_image(b: PackedByteArray) -> bool:
	if b.size() < 12:
		return false
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		return true                                  # PNG
	if b[0] == 0xFF and b[1] == 0xD8:
		return true                                  # JPEG
	if b[0] == 0x52 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x46:
		return true                                  # WEBP (RIFF)
	return b[0] == 0x47 and b[1] == 0x49 and b[2] == 0x46  # GIF


static func query(params: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in params.keys():
		parts.append("%s=%s" % [str(k), str(params[k]).uri_encode()])
	return "&".join(parts)


## Programme, Pakete und Bilder nur verschlüsselt laden (Punkte 74, 47). Bildadressen kommen teils
## aus fremden Antworten – http zu diesem PC selbst gibt es darum nur in Proben mit nachgebauten
## Servern (UZAI_TEST_LOOPBACK=1), nie im Betrieb.
static func download_allowed(url: String) -> bool:
	var u := url.strip_edges().to_lower()
	if u.begins_with("https://") or media_origins.has(origin(url)):
		return true
	return Config.probe_env("UZAI_TEST_LOOPBACK") == "1" and (u.begins_with("http://127.0.0.1:") or u.begins_with("http://localhost:"))


## Eigene Medienserver der Filme-Quellen (src/core/medienquellen.gd): Ursprung → Kopfzeilen für
## Bilder. Nur verbundene Server stehen hier; unverschlüsselt (http) nur, wenn er im Heimnetz
## liegt und du das bestätigt hast. Beim Abmelden fliegt er wieder raus.
static var media_origins := {}


## „https://host:port“ einer Adresse (kleingeschrieben, ohne Pfad), "" wenn keine.
static func origin(url: String) -> String:
	var u := url.strip_edges()
	var se := u.find("://")
	if se <= 0:
		return ""
	var rest := u.substr(se + 3)
	var cut := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < cut:
			cut = i
	var host := rest.substr(0, cut).to_lower()
	return "" if host == "" or host.contains("@") else u.substr(0, se).to_lower() + "://" + host


## SHA-256 zu einer Datei aus einer Prüfsummen-Liste („<hash>  <datei>“ je Zeile, wie sha256sum;
## ein „*“ vor dem Namen zählt nicht). "" wenn die Datei nicht drinsteht.
static func sha_for(sums: String, file: String) -> String:
	for line in sums.split("\n"):
		var l := line.strip_edges()
		var cut := l.find(" ")
		if cut != 64:
			continue
		var name := l.substr(cut).strip_edges().trim_prefix("*")
		if name == file and l.left(64).is_valid_hex_number():
			return l.left(64).to_lower()
	return ""


## Erste SHA-256 in einem Text (Prüfsummen-Dateien in verschiedenen Formaten, z. B. von
## PowerShells Get-FileHash). "" wenn keine drinsteht.
static func first_sha(text: String) -> String:
	var m := RegEx.create_from_string("(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])").search(text)
	return m.get_string().to_lower() if m != null else ""


## Prüfsumme eines Release-Pakets laut GitHub („digest“: „sha256:…“). "" wenn GitHub keine nennt.
static func github_digest(asset: Dictionary) -> String:
	var d := str(asset.get("digest", "")).strip_edges()
	if not d.to_lower().begins_with("sha256:"):
		return ""
	var h := d.substr(7)
	return h.to_lower() if h.length() == 64 and h.is_valid_hex_number() else ""


## Wie download_big, aber nur mit passender SHA-256: Erst danach liegt die Datei unter dest, sonst
## bleibt nichts liegen. "" = geladen und geprüft, sonst ein Satz zum Grund.
func download_verified(url: String, dest: String, sha256: String, progress: Callable = Callable()) -> String:
	if sha256.length() != 64 or not sha256.is_valid_hex_number():
		return "Keine Prüfsumme bekommen – aus Sicherheitsgründen nichts installiert."
	var tmp := dest + ".pruefen"
	if not await download_big(url, tmp, progress):
		return "Der Download ging nicht."
	if await sha256_datei(tmp) != sha256.to_lower():
		DirAccess.remove_absolute(tmp)
		return "Die Prüfsumme des Downloads stimmt nicht – nichts installiert. Bitte später noch einmal."
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	return "" if DirAccess.rename_absolute(tmp, dest) == OK else "Die Datei ließ sich nicht speichern."


## SHA-256 einer Datei (klein geschrieben), im Hilfsfaden gerechnet: Bei großen Downloads hielte das Rechnen Uzai
## sonst spürbar an (gemessen: 180 MB in rund 0,65 s). "" wenn sie sich nicht lesen ließ.
func sha256_datei(pfad: String) -> String:
	var v: Variant = await Arbeit.ergebnis(_sha256_von.bind(pfad), Arbeit.LANG)
	return str(v) if v is String else ""


static func _sha256_von(pfad: String) -> String:
	return FileAccess.get_sha256(pfad).to_lower()


## Kurzer Text von einer Adresse (Prüfsummen-Listen). "" wenn es nicht ging.
func get_text(url: String) -> String:
	if not download_allowed(url):
		return ""
	var r := await request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0)
	return (r.body as PackedByteArray).get_string_from_utf8() if bool(r.ok) else ""


## So lange darf ein großer Download ohne ein einziges neues Byte bleiben (auch beim Verbinden). Vorher gab es
## dafür keine Grenze: Riss die Verbindung still ab (WLAN weg, Router schläft), hing der Download für immer
## und mit ihm das Einrichten von Browser-Kern, FFmpeg oder einem Emulator-Kern.
const STILL_MS := 120000
var still_ms := STILL_MS         ## Proben stellen es kürzer


## Große Dateien direkt auf die Platte laden: ohne Zeitlimit für das Ganze, aber nie länger als STILL_MS ohne
## Fortschritt. progress(geladen, gesamt).
## Nur über https (download_allowed). max_bytes: größer bricht ab (0 = ohne Grenze); follow = false:
## keiner Weiterleitung folgen (wer sie prüfen will, löst sie vorher selbst auf); stop["stop"] = true
## bricht ab – dann bleibt nichts liegen.
func download_big(url: String, dest: String, progress: Callable = Callable(), max_bytes := 0, follow := true, stop: Dictionary = {}) -> bool:
	if not download_allowed(url):
		return false
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var tmp := dest + ".part"
	var a := Abruf.Auftrag.new()
	a.url = url
	a.kopf = PackedStringArray(["User-Agent: " + UA])
	a.datei = tmp
	a.still_ms = still_ms
	a.grenze = max_bytes
	a.folgen = follow
	Abruf.starten(a)
	while not a.fertig:
		await get_tree().create_timer(0.25).timeout
		if bool(stop.get("stop", false)):
			a.stop = true
		if progress.is_valid() and not a.fertig:
			progress.call(a.geladen, a.gesamt)
	var ok: bool = int(a.ergebnis.result) == HTTPRequest.RESULT_SUCCESS and int(a.ergebnis.code) >= 200 and int(a.ergebnis.code) < 300
	if not ok:
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	return DirAccess.rename_absolute(tmp, dest) == OK

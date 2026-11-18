extends RefCounted
## Liedtexte von LRCLIB (lrclib.net): freie Datenbank ohne Schlüssel, mit zeitgenauen Zeilen (LRC).
## Spotify gibt seine Songtexte über die offizielle Schnittstelle nicht heraus.
##
## Was rausgeht: nur Titel, Künstler, Album und Länge des laufenden Titels – nur per https an
## lrclib.net, ohne Weiterleitungen, mit eigenem User-Agent (Name und Fassung von Uzai, wie LRCLIB
## es erbittet), ohne Kennung, ohne Telemetrie. Abschaltbar: Einstellungen → Klang → Musik →
## „Liedtexte (LRCLIB)“ (music.lrclib, Standard an).
## Was reinkommt, wird streng geprüft (Typen, Längen, Zeitstempel) und lokal zwischengespeichert
## (cache/lyrics.json, Schlüssel nur als SHA-256, höchstens CACHE_MAX Titel und CACHE_BYTES).

const Fremd := preload("res://src/core/fremd.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
## Lesen und Schreiben der Datei laufen im Hintergrund: über das Skript, nicht über den Knoten „Config“.
const ConfigS := preload("res://src/core/config.gd")

const HOST := "https://lrclib.net"
const GET := HOST + "/api/get?"
const SEARCH := HOST + "/api/search?"
const MAX_BYTES := 768 * 1024      ## größte Antwort (die Suche liefert bis zu 20 Treffer samt Text)
const TEXT_MAX := 64 * 1024        ## größter Liedtext je Art (Zeichen)
const LINE_MAX := 300              ## längste Zeile (Zeichen), länger wird gekürzt
const LINES_MAX := 1200            ## so viele Zeilen höchstens
const MS_MAX := 3 * 3600 * 1000    ## späteste Zeitmarke (3 h)
const FIELD_MAX := 200             ## Titel, Künstler, Album: so lang höchstens in der Anfrage
const NAME_MAX := 1000             ## Namen in der Antwort (nur geprüft, nicht verwendet)
const HITS_MAX := 20
const DUR_TOL := 4.0               ## Sekunden, die ein Suchtreffer von der Länge abweichen darf
const CACHE_FILE := "cache/lyrics.json"
const CACHE_MAX := 300             ## Titel im Zwischenspeicher auf der Platte
const CACHE_BYTES := 3 * 1024 * 1024
const NONE_TTL := 3 * 86400        ## „kein Liedtext“ nach drei Tagen neu fragen
const FAIL_PAUSE_MS := 60000       ## nach einem Fehler eine Minute nicht neu fragen
const MEM_MAX := 200

static var _cache := {}            ## Schlüssel (key_of) -> Ergebnis
static var _disk := {}             ## SHA-256 des Schlüssels -> { t, s, y, p, i }
static var _disk_loaded := false
static var _busy := {}             ## Schlüssel -> true, solange gefragt wird
static var _failed := {}           ## Schlüssel -> Zeitpunkt des letzten Fehlers (ms)
static var _disk_laedt := false    ## die Datei wird gerade im Hintergrund gelesen
static var _schreibt := false      ## ein Schreiber läuft im Hintergrund
static var _schreib_stand: Variant = null   ## neuester Stand, der noch auf die Platte muss (null: keiner)
static var _gewichte := {}         ## SHA-256 des Schlüssels -> [t, Größe als Text] (für trim, je Eintrag einmal gerechnet)
## Zeichen, die clean_text herausnimmt oder ersetzt (zum schnellen Nachsehen, ob überhaupt etwas zu tun ist).
static var _RX_UNSICHTBAR := RegEx.create_from_string("[\\x{00}-\\x{1F}\\x{7F}-\\x{9F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}\\x{FEFF}]")


## { state: "ok"|"keine"|"fehler"|"aus", synced: [[ms, Zeile]], plain: PackedStringArray, instrumental: bool }
static func fetch(title: String, artist: String, album: String, duration_ms: int) -> Dictionary:
	var key := key_of(title, artist)
	if _cache.has(key):
		return _cache[key]
	if not enabled():
		return result("aus")
	var t := clean_field(title)
	var a := clean_field(artist)
	if t == "":
		return result("keine")
	var hk := key.sha256_text()
	await _disk_laden()
	if _cache.has(key):
		return _cache[key]
	var d := _disk_get(hk)
	if not d.is_empty():
		_remember(key, d)
		return d
	# Dieselbe Frage läuft schon (Guide-Streifen, Großansicht, Läuft gerade): auf sie warten.
	var loop := Engine.get_main_loop() as SceneTree
	while _busy.has(key) and loop:
		await loop.process_frame
	if _cache.has(key):
		return _cache[key]
	if Time.get_ticks_msec() - int(_failed.get(key, -FAIL_PAUSE_MS - 1)) < FAIL_PAUSE_MS:
		return result("fehler")
	_busy[key] = true
	var out := await _ask(t, a, clean_field(album), duration_ms)
	_busy.erase(key)
	if str(out.get("state", "fehler")) in ["ok", "keine"]:
		_failed.erase(key)
		_remember(key, out)
		_disk_put(hk, out)
	else:
		_failed[key] = Time.get_ticks_msec()
	return out


## Liedtexte von LRCLIB an?
static func enabled() -> bool:
	return bool(Config.get_value("music.lrclib", true))


## Schlüssel eines Titels im Zwischenspeicher (öffentlich für Proben).
static func key_of(title: String, artist: String) -> String:
	return ("%s|%s" % [title, artist]).to_lower()


static func result(state: String, synced: Array = [], plain := PackedStringArray(), instrumental := false) -> Dictionary:
	return { "state": state, "synced": synced, "plain": plain, "instrumental": instrumental }


## Wie LRCLIB es erbittet: Name, Fassung, Adresse des Projekts.
static func user_agent() -> String:
	return "Uzai v%s (https://github.com/%s)" % [Config.VERSION, Config.REPO]


static func _remember(key: String, r: Dictionary) -> void:
	if _cache.size() >= MEM_MAX:
		_cache.clear()
	_cache[key] = r


# --- Anfrage -------------------------------------------------------------------------------------

## Erst genau (/api/get mit Album und Länge), sonst suchen (/api/search, nur Titel und Künstler)
## und den passenden Treffer nehmen.
static func _ask(title: String, artist: String, album: String, duration_ms: int) -> Dictionary:
	var dur_s := duration_ms / 1000.0 if duration_ms > 0 else 0.0
	var q := { "track_name": title, "artist_name": artist }
	if album != "":
		q["album_name"] = album
	if duration_ms > 0:
		q["duration"] = int(round(dur_s))
	var r := await _abfrage(GET + Net.query(q))
	if int(r.code) == 200:
		var hit := check_hit(r.data)
		if not hit.is_empty():
			return from_hit(hit)
	elif int(r.code) != 404:
		return result("fehler")
	var s := await _abfrage(SEARCH + Net.query({ "track_name": title, "artist_name": artist }))
	if int(s.code) != 200 or not (s.data is Array):
		return result("fehler" if int(s.code) != 200 else "keine")
	var best := best_hit(check_hits(s.data), dur_s)
	return from_hit(best) if not best.is_empty() else result("keine")


## GET mit eigenem User-Agent, Größengrenze und ohne Weiterleitungen. { code, data }
static func _abfrage(url: String) -> Dictionary:
	if not url_ok(url):
		return { "code": 0, "data": null }
	var h := PackedStringArray(["User-Agent: " + user_agent(), "Accept: application/json"])
	var r: Dictionary = await Net.request(url, h, HTTPClient.METHOD_GET, "", 10.0, "api", MAX_BYTES, false)
	var data: Variant = null
	var body: PackedByteArray = r.get("body", PackedByteArray())
	if bool(r.get("ok", false)) and body.size() > 0 and body.size() <= MAX_BYTES:
		data = Fremd.json(body.get_string_from_utf8())
	var code := int(r.get("code", 0))
	if code == 200 and data == null:
		code = 0             # kaputte Antwort zählt wie keine
	return { "code": code, "data": data }


# --- Prüfen (öffentlich für die Tests) -----------------------------------------------------------

## Nur https an lrclib.net, nur die beiden Wege der Schnittstelle.
static func url_ok(url: String) -> bool:
	return url.begins_with(GET) or url.begins_with(SEARCH)


## Titel, Künstler, Album für die Anfrage: ohne Steuerzeichen, gekürzt.
static func clean_field(s: String) -> String:
	return clean_text(s).left(FIELD_MAX).strip_edges()


## Ein Treffer von LRCLIB, streng geprüft. {} = unbrauchbar. Sonst { synced, plain, instrumental,
## duration } (Texte noch roh, parse() liest sie).
static func check_hit(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	if d.has("id") and not (d.id is int or d.id is float):
		return {}
	for k in ["trackName", "artistName", "albumName", "name"]:
		var x: Variant = d.get(k)
		if x != null and not (x is String and (x as String).length() <= NAME_MAX):
			return {}
	var dur: Variant = d.get("duration")
	if dur != null and not ((dur is int or dur is float) and float(dur) >= 0.0 and float(dur) <= MS_MAX / 1000.0):
		return {}
	var ins: Variant = d.get("instrumental")
	if ins != null and not (ins is bool):
		return {}
	var out := { "synced": "", "plain": "", "instrumental": ins == true, "duration": float(dur) if dur != null else 0.0 }
	for k in [["syncedLyrics", "synced"], ["plainLyrics", "plain"]]:
		var x: Variant = d.get(k[0])
		if x == null:
			continue
		if not (x is String) or (x as String).length() > TEXT_MAX:
			return {}
		out[k[1]] = x
	return out


## Liste der Suche: höchstens HITS_MAX, nur gültige Treffer.
static func check_hits(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for it in (v as Array).slice(0, HITS_MAX):
		var h := check_hit(it)
		if not h.is_empty():
			out.append(h)
	return out


## Der passende Treffer: Länge innerhalb DUR_TOL (sonst liefe der Text versetzt), mit Zeitangaben
## vor ohne. Passt keine Länge, reicht einfacher Text (er läuft nicht mit). {} = keiner.
static func best_hit(hits: Array, dur_s: float) -> Dictionary:
	var plain_any := {}
	var plain_fit := {}
	for h in hits:
		var has_sync := str(h.synced).strip_edges() != ""
		var has_plain := str(h.plain).strip_edges() != ""
		if not has_sync and not has_plain:
			continue
		var fits := dur_s <= 0.0 or float(h.duration) <= 0.0 or absf(float(h.duration) - dur_s) <= DUR_TOL
		if fits and has_sync:
			return h
		if fits and plain_fit.is_empty():
			plain_fit = h
		if plain_any.is_empty() and has_plain:
			plain_any = { "synced": "", "plain": h.plain, "instrumental": false, "duration": h.duration }
	return plain_fit if not plain_fit.is_empty() else plain_any


static func from_hit(h: Dictionary) -> Dictionary:
	var r := parse(str(h.get("synced", "")), str(h.get("plain", "")))
	r["instrumental"] = bool(h.get("instrumental", false)) and str(r.state) != "ok"
	return r


## Text ohne Steuerzeichen und Richtungs-Umschalter (nur Zeichen, die man sieht).
static func clean_text(s: String) -> String:
	# Fast immer ist nichts zu tun: ein Suchlauf der Engine statt Zeichen für Zeichen im Skript. Beim Prüfen eines
	# vollen Zwischenspeichers (2 MB Text) sind das 19 statt 573 ms (gemessen).
	if _RX_UNSICHTBAR.search(s) == null:
		return s
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or (c >= 0x7F and c <= 0x9F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			out += " " if c in [9, 10, 13] else ""
			continue
		out += s[i]
	return out


## Beim Laden gefüllt, danach nur gelesen (nie beim ersten Aufruf anlegen: Ein zweiter Faden sähe sie halb fertig).
static var _re_tag := RegEx.create_from_string("^\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
static var _re_word := RegEx.create_from_string("<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>")
static var _re_off := RegEx.create_from_string("^\\[offset:\\s*([+-]?\\d{1,6})\\]$")


## LRC lesen: Zeilen „[mm:ss.xx] Text“ (auch mehrere Zeitmarken je Zeile, [mm:ss], [mm:ss:xx],
## Wort-Zeiten <mm:ss.xx> werden entfernt, [offset:±ms] gilt). Zeilen ohne gültige Zeitmarke fallen
## weg. Ergebnis { state, synced: [[ms, Text]] nach Zeit, plain } – öffentlich für die Tests.
static func parse(synced: String, plain: String) -> Dictionary:
	var lines: Array = []
	var offset := 0
	var n := 0
	for raw in synced.left(TEXT_MAX).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var line := (raw as String).strip_edges()
		if line == "" or lines.size() >= LINES_MAX:
			continue
		var om := _re_off.search(line.to_lower())
		if om:
			offset = int(om.get_string(1))
			continue
		var stamps: Array = []
		var m := _re_tag.search(line)
		while m and stamps.size() < 16:
			var sec := int(m.get_string(2))
			if sec >= 60:
				stamps.clear()
				break
			var frac := m.get_string(3)
			var ms := int(m.get_string(1)) * 60000 + sec * 1000 + (int(("0." + frac).to_float() * 1000.0 + 0.5) if frac != "" else 0)
			stamps.append(ms)
			line = line.substr(m.get_end())
			m = _re_tag.search(line)
		if stamps.is_empty():
			continue
		var text := clean_text(_re_word.sub(line, "", true)).strip_edges().left(LINE_MAX)
		for ms in stamps:
			var at := int(ms) - offset
			if at < 0 or at > MS_MAX or lines.size() >= LINES_MAX:
				continue
			lines.append([at, text, n])
			n += 1
	# Nach Zeit, bei gleicher Zeit in der Reihenfolge der Datei.
	lines.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[2] < y[2]))
	var out_sync: Array = []
	var any_text := false
	for l in lines:
		out_sync.append([l[0], l[1]])
		any_text = any_text or str(l[1]) != ""
	if not any_text:
		out_sync = []
	var pl := PackedStringArray()
	for l in plain.left(TEXT_MAX).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		if pl.size() >= LINES_MAX:
			break
		pl.append(clean_text(l).strip_edges().left(LINE_MAX))
	while not pl.is_empty() and pl[0] == "":
		pl.remove_at(0)
	while not pl.is_empty() and pl[pl.size() - 1] == "":
		pl.remove_at(pl.size() - 1)
	var ok := not out_sync.is_empty() or not pl.is_empty()
	return result("ok" if ok else "keine", out_sync, pl)


## Index der Zeile, die gerade läuft (-1 vor der ersten). Halbierend gesucht (läuft je Bild).
static func line_at(synced: Array, ms: int) -> int:
	var lo := 0
	var hi := synced.size() - 1
	var idx := -1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if int(synced[mid][0]) <= ms:
			idx = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return idx


# --- Zwischenspeicher auf der Platte -------------------------------------------------------------

static func _disk_path() -> String:
	return Config.path(CACHE_FILE)


## Die Datei lesen und prüfen (ohne Zustand, läuft auch im Hintergrund).
static func _disk_lesen(pfad: String) -> Dictionary:
	# Viel größer als erlaubt: nicht erst einlesen (die Datei kann jeder unter deinem Konto ändern).
	var f := FileAccess.open(pfad, FileAccess.READ)
	var big := f != null and f.get_length() > CACHE_BYTES * 2
	f = null
	return {} if big else check_disk(ConfigS.read_json(pfad, {}))


## Den gemerkten Stand einmal je Sitzung im Hintergrund holen (bei vollem Speicher 2 bis 3 MB lesen und prüfen –
## im Hauptfaden stand dafür beim ersten Liedtext das Bild).
static func _disk_laden() -> void:
	if _disk_loaded:
		return
	var loop := Engine.get_main_loop() as SceneTree
	if _disk_laedt:
		while _disk_laedt and loop:
			await loop.process_frame
		return
	_disk_laedt = true
	var stand: Variant = await Arbeit.ergebnis(_disk_lesen.bind(_disk_path()), Arbeit.KURZ)
	if not _disk_loaded:
		_disk = stand if stand is Dictionary else {}
		_disk_loaded = true
	_disk_laedt = false


static func _disk_get(hk: String) -> Dictionary:
	if not _disk_loaded:
		_disk_loaded = true
		_disk = _disk_lesen(_disk_path())
	var e: Variant = _disk.get(hk)
	if not (e is Dictionary):
		return {}
	if str(e.s) == "keine" and int(Time.get_unix_time_from_system()) - int(e.t) > NONE_TTL:
		return {}
	var pl := PackedStringArray()
	for l in e.p:
		pl.append(str(l))
	return result(str(e.s), (e.y as Array).duplicate(true), pl, bool(e.i))


static func _disk_put(hk: String, r: Dictionary) -> void:
	if not _disk_loaded:
		_disk_get("")
	# Auf einer Kopie der Liste: Den Stand davor liest vielleicht gerade noch der Schreiber im Hintergrund. Die
	# Einträge selbst ändert niemand mehr.
	var neu := _disk.duplicate()
	neu[hk] = { "t": int(Time.get_unix_time_from_system()), "s": str(r.state), "y": r.synced, "p": Array(r.plain), "i": bool(r.get("instrumental", false)) }
	_disk = trim(neu, CACHE_MAX, CACHE_BYTES)
	_schreib_stand = _disk
	_schreiben(_disk_path())


## Den neuesten Stand im Hintergrund auf die Platte bringen: immer nur ein Schreiber, und kommt währenddessen ein
## neuerer Stand, schreibt er danach den. Im Hauptfaden kostete das bei vollem Speicher je neuem Lied rund 68 ms
## (gemessen: 29 ms Begrenzen, 32 ms Text bauen, 7 ms Schreiben).
static func _schreiben(pfad: String) -> void:
	if _schreibt:
		return
	_schreibt = true
	while _schreib_stand != null:
		var stand: Dictionary = _schreib_stand
		_schreib_stand = null
		await Arbeit.ergebnis(_datei_schreiben.bind(pfad, stand), Arbeit.KURZ)
	_schreibt = false


static func _datei_schreiben(pfad: String, stand: Dictionary) -> bool:
	return ConfigS.write_json(pfad, { "v": 1, "e": stand })


## Zwischenspeicher aus der Datei, geprüft wie eine fremde Antwort (die Datei kann jeder unter
## deinem Konto ändern): nur gültige Einträge, alles andere fällt weg. Öffentlich für die Tests.
static func check_disk(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary) or int(v.get("v", 0)) != 1 or not (v.get("e") is Dictionary):
		return out
	for hk in v.e:
		if out.size() >= CACHE_MAX:
			break
		var e: Variant = v.e[hk]
		if not (hk is String and (hk as String).length() == 64 and (hk as String).is_valid_hex_number()):
			continue
		if not (e is Dictionary and (e.get("t") is float or e.get("t") is int) and str(e.get("s")) in ["ok", "keine"]
				and e.get("y") is Array and e.get("p") is Array and e.get("i") is bool):
			continue
		var y: Array = []
		var good := (e.y as Array).size() <= LINES_MAX and (e.p as Array).size() <= LINES_MAX
		var last := -1
		for l in (e.y as Array) if good else []:
			if not (l is Array and l.size() == 2 and (l[0] is float or l[0] is int) and l[1] is String) or int(l[0]) < last or int(l[0]) > MS_MAX:
				good = false
				break
			last = int(l[0])
			y.append([int(l[0]), clean_text(str(l[1])).left(LINE_MAX)])
		var p: Array = []
		for l in (e.p as Array) if good else []:
			if not (l is String):
				good = false
				break
			p.append(clean_text(l).left(LINE_MAX))
		if good:
			out[hk] = { "t": int(e.t), "s": str(e.s), "y": y, "p": p, "i": bool(e.i) }
	return out


## Zwischenspeicher begrenzen: höchstens max_n Einträge und etwa max_bytes, die ältesten gehen
## zuerst. Öffentlich für die Tests.
static func trim(entries: Dictionary, max_n: int, max_bytes: int) -> Dictionary:
	var keys: Array = entries.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(entries[a].t) > int(entries[b].t))
	var out := {}
	var bytes := 0
	if _gewichte.size() > 8 * CACHE_MAX:
		_gewichte.clear()
	for k in keys:
		# Größe je Eintrag einmal rechnen (ein Eintrag ändert sich nicht mehr; t gehört zum Schlüssel dazu).
		var e: Dictionary = entries[k]
		var g: Variant = _gewichte.get(k)
		if not (g is Array) or int(g[0]) != int(e.t):
			g = [int(e.t), JSON.stringify(e).length() + 72]
			_gewichte[k] = g
		var sz := int(g[1])
		if out.size() >= max_n or bytes + sz > max_bytes:
			break
		bytes += sz
		out[k] = entries[k]
	return out

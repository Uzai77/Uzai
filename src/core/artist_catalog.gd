extends RefCounted
## „Alle Titel“ eines Künstlers: alle Alben und Singles/EPs (auf Wunsch auch Gastauftritte), daraus
## jeder Titel einmal, neueste Veröffentlichung zuerst. Lädt in Runden (more()), damit die Liste
## schnell etwas zeigt und erst beim Weiterblättern nachlädt. Music.artist_catalog() hält je
## Künstler eine Instanz für die ganze Sitzung (Zwischenspeicher).
##
## Nur offizielle Wege der Web-API:
## 1. /artists/{id}/albums?include_groups=album,single – alle Seiten (eigene Apps: höchstens 10 je
##    Seite), danach nach Datum sortiert.
## 2. Titel je Runde: /albums?ids=… (bis 20 Alben auf einmal). Lehnt Spotify das ab (eigene Apps
##    seit 2026 oft 403), für den Rest der Sitzung /albums/{id}/tracks je Album.
## 3. Gibt Spotify die Alben des Künstlers gar nicht heraus (403), sucht Uzai artist:"Name" und
##    behält nur Treffer mit diesem Künstler – und sagt das dazu.
## Antwortet Spotify mit 429, wartet Uzai so lange, wie Retry-After sagt (bis 30 s), und versucht es
## nochmal; sonst bleibt die Runde offen und lässt sich wiederholen.
##
## Doppelte Titel (gleicher Name ohne „Remastered …“, Länge bis 2 s gleich) zählen einmal. Behalten
## wird die ursprüngliche Fassung: Album vor Single, normale Ausgabe vor Remaster/Deluxe/Best of
## und Samplern, bei Gleichstand die ältere.

signal changed
signal _finished

const PAGE := 10              ## /artists/{id}/albums: höchstens 10 je Seite (eigene Apps seit 2026)
const MAX_PAGES := 60         ## höchstens 600 Veröffentlichungen
const BATCH := 20             ## /albums?ids=: höchstens 20 Alben je Abruf
const FIRST := 6              ## erste Runde: wenige Veröffentlichungen, damit schnell etwas steht
const STEP := 12              ## jede weitere Runde
const SEARCH_LIMIT := 10      ## Suche: höchstens 10 Treffer je Seite (eigene Apps seit 2026)
const SEARCH_PAGES := 3       ## Ausweich-Suche: Seiten je Runde
const SEARCH_MAX := 1000      ## weiter blättert Spotify in der Suche nicht
const SAME_MS := 2000         ## so nah müssen die Längen doppelter Titel beieinander liegen
const WAIT_MAX := 30          ## länger sagt Retry-After: nicht warten, die Runde bleibt offen
const TRIES := 4
const Zustand := preload("res://src/core/zustand.gd")
const Fremd := preload("res://src/core/fremd.gd")
## Weg zu den Titeln: einmal je Künstler gewählt (Alben, sonst Suche; Vorführung) und dann für die Sitzung fest.
const ZUSTAENDE_WEG := { "!": ["alben", "suche", "demo"], "": ["alben", "suche", "demo"], "alben": [], "suche": [], "demo": [] }

## Lehnt Spotify /albums?ids= ab, nimmt Uzai für den Rest der Sitzung den Weg je Album.
static var several_ok := true
static var _re_reissue := RegEx.create_from_string(
		"\\b(remaster(ed)?|deluxe|anniversary|expanded|edition|best of|greatest hits|the collection|essentials?|anthology|jubiläum)\\b")
static var _re_suffix := RegEx.create_from_string("(?i)\\s*(\\s[-–]\\s|\\(|\\[)[^()\\[\\]]*remaster[^()\\[\\]]*[)\\]]?\\s*$")

var artist: Dictionary = {}   ## { id, name, uri? }
var guest := false            ## auch Gastauftritte (appears_on)
var tracks: Array = []        ## sichtbare Liste: jeder Titel einmal, neueste Veröffentlichung zuerst
var releases: Array = []      ## alle Veröffentlichungen (album_from + group), neueste zuerst
var total := -1               ## so viele Veröffentlichungen meldet Spotify (-1: noch unbekannt)
var loaded := 0               ## so viele davon sind eingelesen
var mode := "":               ## "" (noch nichts) | "alben" | "suche" | "demo"
	set(neu):
		Zustand.wechsel("musik.alle_titel", ZUSTAENDE_WEG, mode, neu)
		mode = neu
var note := ""                ## bleibender Hinweis (etwa: aus der Suche)
var waiting := ""             ## gerade: Spotify bremst, Uzai wartet
var error := ""               ## letzte Runde ging nicht (more() versucht es nochmal)
var done := false
var loading := false
var _search_at := 0


func setup(a: Dictionary, with_guest := false) -> RefCounted:
	artist = a.duplicate()
	guest = with_guest
	return self


## Nächste Runde laden. Läuft schon eine, wartet der Aufruf auf deren Ende.
func more() -> void:
	if done:
		return
	if loading:
		await _finished
		return
	loading = true
	error = ""
	changed.emit()
	if Music.demo():
		await _more_demo()
	elif not Music.has_spotify():
		error = "„Alle Titel“ braucht Spotify (Einstellungen → Konten)."
	elif mode == "":
		await _start()
	elif mode == "suche":
		await _search_round()
	else:
		await _release_round(STEP)
	loading = false
	waiting = ""
	changed.emit()
	_finished.emit()


## Wie viele Veröffentlichungen noch fehlen (Suche: unbekannt, -1).
func left() -> int:
	if mode == "suche" or total < 0:
		return -1
	return maxi(0, releases.size() - loaded)


# --- Ablauf ---------------------------------------------------------------------

func _start() -> void:
	var aid := str(artist.get("id", ""))
	var nm := str(artist.get("name", ""))
	if aid == "" and nm != "":
		# Titel von Windows: Künstler erst über den Namen finden (wie die Künstlerseite).
		var s := await _fetch("/search?type=artist&limit=5&q=%s" % nm.uri_encode())
		for c in Music.parse_search(s.data if s.ok else {}).artists:
			if str(c.name).to_lower() == nm.to_lower():
				aid = str(c.id)
				artist["id"] = aid
				break
	if aid == "":
		_to_search("Spotify kennt zu diesem Titel keine Künstler-ID.")
		await _search_round()
		return
	var groups := "album,single" + (",appears_on" if guest else "")
	var base := "/artists/%s/albums?include_groups=%s&limit=%d" % [aid, groups, PAGE]
	var first := await _fetch(base + "&offset=0")
	if not first.ok:
		if int(first.code) in [403, 404]:
			_to_search("Spotify gibt die Alben dieses Künstlers eigenen Apps nicht heraus.")
			await _search_round()
		else:
			error = Music.why_text(first, "Spotify hat die Veröffentlichungen nicht geschickt.")
		return
	var d: Dictionary = first.data if first.data is Dictionary else {}
	var items: Array = (d.get("items", []) as Array).duplicate() if d.get("items") is Array else []
	var n := int(d.get("total", items.size())) if d.get("total") != null else items.size()
	var pages := mini(ceili(n / float(PAGE)), MAX_PAGES)
	if pages > 1:
		# Die übrigen Seiten gleichzeitig (Net lässt höchstens sechs parallel laufen).
		var box := {}
		var calls: Array = []
		for p in range(1, pages):
			var off := p * PAGE
			calls.append(func() -> void: box[off] = await _fetch(base + "&offset=%d" % off))
		await Music._parallel(calls)
		var missing := 0
		for p in range(1, pages):
			var r: Dictionary = box.get(p * PAGE, {})
			if r.get("ok", false) and r.data is Dictionary and (r.data as Dictionary).get("items") is Array:
				items.append_array(r.data.items)
			else:
				missing += 1
		if missing > 0:
			note = "%d von %d Seiten mit Veröffentlichungen kamen nicht an." % [missing, pages]
	releases = parse_releases(items)
	total = releases.size()
	mode = "alben"
	if releases.is_empty():
		done = true
		return
	await _release_round(FIRST)


func _to_search(why: String) -> void:
	mode = "suche"
	note = why + " Uzai sucht stattdessen nach artist:\"%s\" – Reihenfolge wie in der Suche, nicht nach Datum." % str(artist.get("name", ""))


## Titel der nächsten n Veröffentlichungen holen und einsortieren.
func _release_round(n: int) -> void:
	var chunk: Array = releases.slice(loaded, loaded + n)
	if chunk.is_empty():
		done = true
		return
	var got := {}           # Album-ID -> rohe Titel
	var failed := false
	if several_ok:
		for b in range(0, chunk.size(), BATCH):
			var part: Array = chunk.slice(b, b + BATCH)
			var r := await _fetch("/albums?ids=" + ",".join(PackedStringArray(part.map(func(a): return str(a.id)))))
			if r.ok and r.data is Dictionary:
				for a in Fremd.zeilen(r.data, "albums"):
					if a is Dictionary and str(a.get("id", "")) != "":
						var tr: Dictionary = a.get("tracks", {}) if a.get("tracks") is Dictionary else {}
						var its: Array = (tr.get("items", []) as Array).duplicate() if tr.get("items") is Array else []
						var nxt: Variant = tr.get("next")
						if nxt is String and str(nxt) != "":
							its.append_array(await _album_items(str(a.id), its.size()))
						got[str(a.id)] = its
			elif int(r.code) in [400, 403, 404]:
				# Für eigene Apps gesperrt: ab jetzt je Album.
				several_ok = false
				break
			else:
				failed = true
				error = Music.why_text(r, "Spotify hat die Titel nicht geschickt.")
				break
	if not failed:
		var calls: Array = []
		var box := {}
		for al in chunk:
			var id := str(al.id)
			if not got.has(id):
				calls.append(func() -> void: box[id] = await _album_items(id, 0, true))
		if not calls.is_empty():
			await Music._parallel(calls)
		for id in box:
			var v: Variant = box[id]
			if v is Dictionary:
				failed = true
				error = Music.why_text(v, "Spotify hat die Titel nicht geschickt.")
			else:
				got[id] = v
	if failed:
		return          # Runde bleibt offen: more() versucht dieselben Alben nochmal
	var aid := str(artist.get("id", ""))
	var incoming: Array = []
	for al in chunk:
		incoming.append_array(release_tracks(got.get(str(al.id), []), al, aid if str(al.get("group", "")) == "appears_on" else ""))
	merge(tracks, incoming)
	loaded += chunk.size()
	done = loaded >= releases.size()


## Rohe Titel eines Albums ab Position from (je Seite 50). strict: Fehler als Dictionary zurück.
func _album_items(id: String, from := 0, strict := false) -> Variant:
	var out: Array = []
	var off := from
	for i in 20:
		var r := await _fetch("/albums/%s/tracks?limit=50&offset=%d" % [id, off])
		if not r.ok or not (r.data is Dictionary):
			if strict and out.is_empty():
				return r
			break
		var its: Array = Fremd.liste(r.data, "items")
		out.append_array(its)
		off += its.size()
		var nxt: Variant = (r.data as Dictionary).get("next")
		if its.is_empty() or not (nxt is String) or str(nxt) == "":
			break
	return out


## Ausweich-Weg: Suche artist:"Name", nur Treffer mit diesem Künstler.
func _search_round() -> void:
	var nm := str(artist.get("name", ""))
	if nm == "":
		done = true
		return
	var q := ("artist:\"%s\"" % nm).uri_encode()
	var box := {}
	var calls: Array = []
	var offs: Array = []
	for i in SEARCH_PAGES:
		var off := _search_at + i * SEARCH_LIMIT
		if off >= SEARCH_MAX:
			break
		offs.append(off)
		calls.append(func() -> void: box[off] = await _fetch("/search?type=track&limit=%d&offset=%d&q=%s" % [SEARCH_LIMIT, off, q]))
	if calls.is_empty():
		done = true
		return
	await Music._parallel(calls)
	var incoming: Array = []
	var ended := false
	for off in offs:
		var r: Dictionary = box.get(off, {})
		if not r.get("ok", false):
			if incoming.is_empty() and not ended:
				error = Music.why_text(r, "Die Suche kam nicht an.")
				return
			break
		var d: Dictionary = r.data if r.data is Dictionary else {}
		var tr: Dictionary = d.get("tracks", {}) if d.get("tracks") is Dictionary else {}
		var its: Array = tr.get("items", []) if tr.get("items") is Array else []
		incoming.append_array(search_tracks(its, str(artist.get("id", "")), nm))
		_search_at = int(off) + SEARCH_LIMIT
		var tot := int(tr.get("total", -1)) if tr.get("total") != null else -1
		if its.size() < SEARCH_LIMIT or (tot >= 0 and _search_at >= tot):
			ended = true
			break
	merge(tracks, incoming, true)
	done = ended or _search_at >= SEARCH_MAX


## GET mit Geduld: bei 429 so lange warten, wie Spotify sagt (Retry-After), dann nochmal.
func _fetch(path: String) -> Dictionary:
	var r: Dictionary = {}
	for attempt in TRIES:
		r = await Music._api(HTTPClient.METHOD_GET, path)
		if int(r.get("code", 0)) != 429:
			return r
		var secs := wait_secs(Net.header(r, "Retry-After"), attempt)
		if secs > WAIT_MAX or attempt == TRIES - 1:
			break
		waiting = "Spotify bremst – Uzai wartet %d s und macht dann weiter." % secs
		changed.emit()
		await Music.get_tree().create_timer(secs).timeout
		waiting = ""
		changed.emit()
	return r


## Wartezeit aus Retry-After (Sekunden); fehlt sie, 2, 4, 6 … Sekunden.
static func wait_secs(header: String, attempt: int) -> int:
	var s := header.strip_edges()
	if s.is_valid_int() and int(s) >= 0:
		return maxi(1, int(s))
	return 2 * (attempt + 1)


func _more_demo() -> void:
	await Music.get_tree().create_timer(0.35 if mode == "" else 0.25).timeout
	if mode == "":
		mode = "demo"
		releases = Music.demo_artist_releases(str(artist.get("name", "")), guest)
		total = releases.size()
	var chunk: Array = releases.slice(loaded, loaded + (FIRST if loaded == 0 else STEP))
	var incoming: Array = []
	for al in chunk:
		incoming.append_array(release_tracks(Music.demo_release_items(al, str(artist.get("name", ""))), al,
			str(artist.get("id", "")) if str(al.get("group", "")) == "appears_on" else ""))
	merge(tracks, incoming)
	for t in incoming:
		Music.demo_remember(t)
	loaded += chunk.size()
	done = loaded >= releases.size()


# --- Auswerten (öffentlich für die Tests) ------------------------------------------

## Veröffentlichungen aus /artists/{id}/albums: jede einmal (gleiche Fassung unter gleichem Namen
## nur einmal), neueste zuerst, bei gleichem Datum Alben vor Singles und Spotifys Reihenfolge.
static func parse_releases(items: Array) -> Array:
	var out: Array = []
	var seen := {}
	for it in items:
		var al: Dictionary = it if it is Dictionary and str((it as Dictionary).get("kind", "")) == "album" else Music.album_from(it)
		if al.is_empty() or str(al.get("id", "")) == "":
			continue
		al = al.duplicate()
		if it is Dictionary and (it as Dictionary).get("album_group") != null:
			al["group"] = str(it.album_group)
		var key := str(al.get("type", "")) + ":" + str(al.get("name", "")).to_lower().strip_edges()
		if seen.has(key) or seen.has("id:" + str(al.id)):
			continue
		seen[key] = true
		seen["id:" + str(al.id)] = true
		al["_i"] = out.size()
		out.append(al)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := str(a.get("date", ""))
		var db := str(b.get("date", ""))
		if da != db:
			return da > db
		var sa := 1 if str(a.get("type", "")) == "single" else 0
		var sb := 1 if str(b.get("type", "")) == "single" else 0
		if sa != sb:
			return sa < sb
		return int(a._i) < int(b._i)
	)
	for al in out:
		al.erase("_i")
	return out


## Titel einer Veröffentlichung (rohe Titel ohne Album, wie /albums/{id}/tracks) in Uzais Form,
## mit Album, Datum und Rang. only_artist: nur Titel, an denen dieser Künstler beteiligt ist.
static func release_tracks(items: Array, al: Dictionary, only_artist := "") -> Array:
	var out: Array = []
	var fake_album := { "name": str(al.get("name", "")), "images": [{ "url": str(al.get("art_big", al.get("art", ""))) }, { "url": str(al.get("art", "")) }] }
	for it in items:
		if not (it is Dictionary):
			continue
		var t: Dictionary
		if (it as Dictionary).has("title") and not (it as Dictionary).has("name"):
			t = (it as Dictionary).duplicate()     # schon in Uzais Form (Vorführung)
		else:
			var c: Dictionary = (it as Dictionary).duplicate()
			c["album"] = fake_album
			t = Music.track_from(c)
		if t.is_empty():
			continue
		if only_artist != "" and Music.tracks_of_artist([t], only_artist, "").is_empty():
			continue
		out.append(decorate(t, al))
	return out


## Suchtreffer (volle Titel mit Album) in Uzais Form, nur mit diesem Künstler.
static func search_tracks(items: Array, artist_id: String, artist_name: String) -> Array:
	var out: Array = []
	for it in items:
		var t := Music.track_from(it)
		if t.is_empty():
			continue
		var al := Music.album_from((it as Dictionary).get("album"))
		out.append(decorate(t, al))
	return Music.tracks_of_artist(out, artist_id, artist_name)


## Album, Datum und Rang an den Titel hängen.
static func decorate(t: Dictionary, al: Dictionary) -> Dictionary:
	t["album_uri"] = str(al.get("uri", ""))
	t["album_id"] = str(al.get("id", ""))
	t["album"] = str(al.get("name", t.get("album", "")))
	t["date"] = str(al.get("date", ""))
	t["album_type"] = str(al.get("type", ""))
	t["rank"] = release_rank(al, str(t.get("title", "")))
	t["album_line"] = album_line(al)
	if str(t.get("art", "")) == "":
		t["art"] = str(al.get("art", ""))
	return t


## „Album · 2019“ für die Spalte rechts in der Zeile.
static func album_line(al: Dictionary) -> String:
	var year := str(al.get("date", "")).get_slice("-", 0)
	var nm := str(al.get("name", ""))
	return nm + ((" · " + year) if year != "" else "")


## Wie „ursprünglich“ eine Fassung ist (kleiner ist besser): Remaster, Deluxe, Best of und
## Sampler +2, Single +1.
static func release_rank(al: Dictionary, title := "") -> int:
	var r := 0
	var nm := str(al.get("name", "")).to_lower()
	if _reissue().search(nm) != null or _reissue().search(title.to_lower()) != null:
		r += 2
	if str(al.get("type", "")) == "compilation" or str(al.get("group", "")) == "appears_on":
		r += 2
	if str(al.get("type", "")) == "single":
		r += 1
	return r


## Name für den Vergleich: klein, ohne „- Remastered 2011“, „(2009 Remaster)“ und Leerraum.
static func norm_title(s: String) -> String:
	var t := _re_suffix.sub(s, "")
	return " ".join(t.to_lower().split(" ", false)).strip_edges()


static func _reissue() -> RegEx:
	return _re_reissue


## Dieselbe Aufnahme? Gleicher Name (ohne Remaster-Zusatz), Länge bis SAME_MS gleich.
static func same_track(a: Dictionary, b: Dictionary) -> bool:
	return norm_title(str(a.get("title", ""))) == norm_title(str(b.get("title", ""))) \
		and absi(int(a.get("duration", 0)) - int(b.get("duration", 0))) <= SAME_MS


## Ist n die ursprünglichere Fassung als o? Erst der Rang, dann das ältere Datum.
static func better(n: Dictionary, o: Dictionary) -> bool:
	var rn := int(n.get("rank", 0))
	var ro := int(o.get("rank", 0))
	if rn != ro:
		return rn < ro
	var dn := str(n.get("date", ""))
	var dd := str(o.get("date", ""))
	return dn != "" and dd != "" and dn < dd


## Neue Titel einsortieren, jeden nur einmal. Ist ein neuer die bessere Fassung eines schon
## gelisteten, ersetzt er ihn: in_place an derselben Stelle (Suche), sonst rückt er ans Ende
## (die Runden kommen nach Datum, der neue ist der ältere). Liefert, ob Gelistetes sich änderte.
static func merge(list: Array, incoming: Array, in_place := false) -> bool:
	var by_name := {}
	for t in list:
		var k := norm_title(str(t.get("title", "")))
		if not by_name.has(k):
			by_name[k] = []
		(by_name[k] as Array).append(t)
	var changed_ := false
	for t in incoming:
		if not (t is Dictionary) or str((t as Dictionary).get("uri", "")) == "":
			continue
		var k := norm_title(str(t.get("title", "")))
		var same: Dictionary = {}
		for o in by_name.get(k, []):
			if same_track(o, t):
				same = o
				break
		if same.is_empty():
			list.append(t)
			if not by_name.has(k):
				by_name[k] = []
			(by_name[k] as Array).append(t)
			continue
		if not better(t, same):
			continue
		var idx := -1
		for i in list.size():
			if is_same(list[i], same):
				idx = i
				break
		(by_name[k] as Array).erase(same)
		(by_name[k] as Array).append(t)
		changed_ = true
		if idx >= 0 and in_place:
			list[idx] = t
		else:
			if idx >= 0:
				list.remove_at(idx)
			list.append(t)
	return changed_

extends RefCounted
## Spotify am PC (Grundmodus, ohne eigene Spotify-App): Was Uzai über die Bedienhilfe von Windows aus
## dem Fenster der Spotify-App liest (Helfer „spotify-fenster“) – „Deine Bibliothek“ ganz, dazu
## „Zuletzt gespielt“ der Startseite – als Reihen für den Musik-Bereich: Playlists, Künstler, Alben,
## Zuletzt gespielt. Dazu der Zwischenspeicher (spotify_pc.json im Ordner des Profils, nur auf diesem
## PC) und die Cover über Spotifys öffentliche oEmbed-Schnittstelle (dieselbe, mit der Webseiten
## Spotify-Links einbetten; ohne Anmeldung). Alles statisch, ohne Netz und ohne Fenster prüfbar
## (tests/logic_spotify_verlauf.gd).
##
## Fremde Daten (Texte aus dem Spotify-Fenster, die eigene Datei, Antworten von oEmbed) werden streng
## geprüft: nur Wörterbücher und Texte, Längen begrenzt, Steuer- und Richtungszeichen entfernt,
## Adressen nur im Muster spotify:(playlist|album|artist|show):<22 Zeichen> bzw.
## spotify:user:<name>:collection (Lieblingssongs), Cover nur von Spotifys Bilder-Servern.

const Verlauf := preload("res://src/core/spotify_verlauf.gd")

const MAX := 600                       ## höchstens so viele Einträge (wie der Helfer)
const ROWS := ["playlists", "artists", "albums", "recent"]
const VOLL_S := 6 * 3600               ## so lange gilt die gelesene Bibliothek, dann liest Uzai neu
const LEER_MS := 600000                ## Fenster da, aber nichts erkannt: erst nach 10 Minuten wieder
const ZU_MS := 45000                   ## Spotify läuft nicht: so oft schaut Uzai nach
const COVER_RETRY_S := 24 * 3600       ## Cover nicht bekommen: frühestens nach einem Tag wieder fragen
const COVER_MAX := 2000
const OEMBED := "https://open.spotify.com/oembed?url="

static var _re_coll := RegEx.create_from_string("^spotify:user:[A-Za-z0-9._-]{1,64}:collection\\z")


## Adresse eines Eintrags: Playlist, Album, Künstler, Podcast oder Lieblingssongs.
static func uri_ok(v: Variant) -> bool:
	if Verlauf.uri_ok(v, ["playlist", "album", "artist", "show"]):
		return true
	if not (v is String) or (v as String).length() > 90:
		return false
	return _re_coll.search(v) != null


static func is_liked(uri: String) -> bool:
	return uri.ends_with(":collection") and uri_ok(uri)


## Reihe eines Eintrags ("" = keine: Suchergebnisse, Podcasts).
static func row_of(sec: String, kind: String) -> String:
	if sec == "recent":
		return "recent"
	if sec != "lib":
		return ""
	match kind:
		"album": return "albums"
		"artist": return "artists"
		"", "playlist": return "playlists"
	return ""


## Ein Eintrag streng geprüft, {} wenn er nicht taugt. live: aus der Antwort des Helfers (mit Nummer i
## in seiner letzten Liste, für das Abspielen im Fenster); sonst aus der Datei (i = -1).
static func item(v: Variant, live: bool) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var i := -1
	if live:
		if not (d.get("i") is int or d.get("i") is float):
			return {}
		i = int(d.i)
		if i < 0 or i >= MAX:
			return {}
	var nm := Verlauf.clean(d.get("name"), Verlauf.NAME_MAX)
	var sec := str(d.sec) if d.get("sec") is String else ""
	var kind := str(d.kind) if d.get("kind") is String else ""
	if nm == "" or not sec in ["lib", "recent", "search"] or not kind in ["", "playlist", "album", "artist", "show"]:
		return {}
	var uri := str(d.uri) if uri_ok(d.get("uri")) else ""
	if uri != "":
		# Die Art steht in der Adresse sicherer als in der Zeile daneben.
		kind = "playlist" if uri.ends_with(":collection") else uri.get_slice(":", 1)
	return { "i": i, "sec": sec, "name": nm, "sub": Verlauf.clean(d.get("sub"), 80), "kind": kind, "uri": uri }


static func _key(it: Dictionary) -> String:
	return str(it.sec) + "|" + (str(it.uri) if str(it.uri) != "" else str(it.name))


## Einträge aus der Antwort des Helfers (jeder geprüft, keiner doppelt).
static func items_from(res: Dictionary) -> Array:
	var out: Array = []
	if not bool(res.get("ok", false)) or not (res.get("items") is Array):
		return out
	var seen := {}
	for v in (res.items as Array).slice(0, MAX):
		var it := item(v, true)
		if it.is_empty() or seen.has(_key(it)):
			continue
		seen[_key(it)] = true
		out.append(it)
	return out


## Neue Einträge mit den gemerkten zusammenführen. ganz: der Helfer hat die Bibliothek bis zum Ende
## gelesen – dann gilt nur das Neue (Gelöschtes verschwindet). Sonst kommen gemerkte Einträge, die
## diesmal fehlen, hinten dazu (sie sind nur gerade nicht zu sehen). „Zuletzt gespielt“: das Neue,
## wenn es welches gibt, sonst das Gemerkte.
static func merge(neu: Array, alt: Array, ganz: bool) -> Array:
	var out: Array = []
	var seen := {}
	var neu_recent := neu.any(func(it: Dictionary) -> bool: return str(it.sec) == "recent")
	for it in neu:
		seen[_key(it)] = true
		out.append(it)
	for it in alt:
		if seen.has(_key(it)) or out.size() >= MAX:
			continue
		var sec := str(it.sec)
		if (sec == "recent" and neu_recent) or (sec != "recent" and ganz) or sec == "search":
			continue
		seen[_key(it)] = true
		var o: Dictionary = (it as Dictionary).duplicate()
		o["i"] = -1
		out.append(o)
	return out


## Reihen für den Musik-Bereich: { playlists, artists, albums, recent }, jede Kachel
## { i, id, name, sub, pkind, uri, art }. arts: Cover je Adresse (oEmbed); sonst ein Cover aus dem
## eigenen Verlauf (gleiche Adresse oder gleicher Name). Lieblingssongs stehen vorn.
static func rows_from(items: Array, hist: Array, arts: Dictionary) -> Dictionary:
	var out := { "playlists": [], "artists": [], "albums": [], "recent": [] }
	var by_uri := {}
	var by_name := {}
	for c in Verlauf.contexts(hist, 60):
		if str(c.art) == "":
			continue
		if not by_uri.has(str(c.uri)):
			by_uri[str(c.uri)] = str(c.art)
		if not by_name.has(str(c.name)):
			by_name[str(c.name)] = str(c.art)
	var seen := {}
	for it in items:
		if not (it is Dictionary):
			continue
		var row := row_of(str(it.get("sec", "")), str(it.get("kind", "")))
		if row == "":
			continue
		var uri := str(it.get("uri", ""))
		var key := row + "|" + (uri if uri != "" else str(it.name))
		if seen.has(key):
			continue
		seen[key] = true
		var art := cover(arts, uri)
		if art == "":
			art = str(by_uri.get(uri, by_name.get(str(it.name), ""))) if uri != "" else str(by_name.get(str(it.name), ""))
		var tile := { "i": int(it.get("i", -1)), "id": uri if uri != "" else "pc:" + str(it.name), "name": str(it.name), "sub": str(it.get("sub", "")),
			"pkind": str(it.get("kind", "")), "uri": uri, "art": art }
		if is_liked(uri) and row == "playlists":
			(out[row] as Array).push_front(tile)
		else:
			(out[row] as Array).append(tile)
	return out


static func empty(rows: Dictionary) -> bool:
	for r in ROWS:
		if not (rows.get(r, []) as Array).is_empty():
			return false
	return true


# --- Cover (oEmbed) -------------------------------------------------------------------------------

## Adresse der oEmbed-Abfrage für eine Playlist, ein Album, einen Künstler oder Podcast ("" für
## Lieblingssongs und alles andere).
static func oembed_url(uri: String) -> String:
	if not Verlauf.uri_ok(uri, ["playlist", "album", "artist", "show"]):
		return ""
	return OEMBED + ("https://open.spotify.com/%s/%s" % [uri.get_slice(":", 1), uri.get_slice(":", 2)]).uri_encode()


## Cover aus der Antwort von oEmbed (thumbnail_url, nur Spotifys Bilder-Server), sonst "".
static func oembed_art(data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	return Verlauf.art_url((data as Dictionary).get("thumbnail_url"))


## Gemerktes Cover einer Adresse ("" = keins).
static func cover(arts: Dictionary, uri: String) -> String:
	var a: Variant = arts.get(uri)
	return str((a as Dictionary).get("u", "")) if a is Dictionary else ""


## Jetzt nach dem Cover fragen? Nie gefragt, oder ohne Antwort und lange her.
static func cover_due(arts: Dictionary, uri: String, now_s: int) -> bool:
	if oembed_url(uri) == "":
		return false
	var a: Variant = arts.get(uri)
	if not (a is Dictionary):
		return true
	return str((a as Dictionary).get("u", "")) == "" and now_s - int((a as Dictionary).get("t", 0)) > COVER_RETRY_S


# --- Datei ------------------------------------------------------------------------------------------

static func to_file(items: Array, arts: Dictionary, at: int) -> Dictionary:
	var its: Array = []
	for it in items.slice(0, MAX):
		its.append({ "sec": it.sec, "name": it.name, "sub": it.sub, "kind": it.kind, "uri": it.uri })
	return { "v": 1, "at": at, "items": its, "arts": arts }


## Gemerkte Bibliothek (Inhalt schon als JSON gelesen), jeder Wert geprüft:
## { items, arts, at } – Einträge ohne Nummer im Fenster (i = -1).
static func load_file(v: Variant) -> Dictionary:
	var out := { "items": [], "arts": {}, "at": 0 }
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	var at: Variant = d.get("at")
	out.at = int(at) if (at is int or at is float) and float(at) > 0.0 and float(at) < 4.0e9 else 0
	var seen := {}
	if d.get("items") is Array:
		for raw in (d.items as Array).slice(0, MAX):
			var it := item(raw, false)
			if it.is_empty() or seen.has(_key(it)):
				continue
			seen[_key(it)] = true
			(out.items as Array).append(it)
	if d.get("arts") is Dictionary:
		var n := 0
		for k in (d.arts as Dictionary).keys():
			if n >= COVER_MAX:
				break
			var a: Variant = d.arts[k]
			if not uri_ok(k) or not (a is Dictionary):
				continue
			var u: Variant = (a as Dictionary).get("u")
			var t: Variant = (a as Dictionary).get("t")
			if not (u is String) or (u != "" and Verlauf.art_url(u) != u) or not (t is int or t is float):
				continue
			out.arts[k] = { "u": u, "t": int(t) }
			n += 1
	return out


## Zeile fürs Protokoll: wie viel je Reihe, wie viele mit Adresse.
static func summary(rows: Dictionary, items: Array) -> String:
	var with_uri := items.filter(func(it: Dictionary) -> bool: return str(it.uri) != "").size()
	return "Playlists %d, Künstler %d, Alben %d, Zuletzt %d, mit Adresse %d" % [(rows.playlists as Array).size(), (rows.artists as Array).size(),
		(rows.albums as Array).size(), (rows.recent as Array).size(), with_uri]


## Lautstärke über Spotify Connect gebündelt: so lange warten, bis seit dem letzten Senden gap ms
## vergangen sind (0 = gleich senden).
static func vol_wait_ms(now_ms: int, last_ms: int, gap := 300) -> int:
	return maxi(0, gap - (now_ms - last_ms))

extends RefCounted
## iiDB, die Datenbank von iiSU, als Bild- und Klangquelle (Auftrag docs/auftraege/iidb.md, Überblick
## docs/IIDB.md). Hier stehen nur Regeln ohne Netz: Anfragen bauen, Antworten streng lesen, Fehler
## deuten, Dateinamen bilden. Das Netz macht src/core/iidb_dienst.gd. Getestet in tests/logic_iidb.gd.
##
## Sicherheit: Der Schlüssel steht nur in der Kopfzeile X-API-Key (kopf), nie in einer Adresse und
## nie im Protokoll. Antworten sind fremde Daten: jeder Wert wird nach Typ und Bereich geprüft, was
## nicht passt, fällt weg. Dateinamen entstehen nur aus geprüften Zahlen und einer Prüfsumme.

const API := "https://iidb-api.iisu.network/api/v1"
const API_HOST := "iidb-api.iisu.network"
## Dort legt jeder seinen eigenen Schlüssel an (der QR-Code der Anmeldeseite öffnet nur diese Seite).
const KONTO_SEITE := "https://accounts.iisu.network/"
const KEY_PATH := "accounts.iidb_key"

const BATCH_MAX := 25                 ## Zeilen je Sammelanfrage
const KAND_MAX := 12                  ## Kandidaten, die Uzai bei „Welches Spiel?“ zeigt
const GALERIE_SEITE := 24             ## Bilder je Seite der Bildwahl
const SUCHE_MAX := 12
const ANTWORT_MAX := 4 * 1024 * 1024  ## größte Antwort der Schnittstelle
const ID_MAX := 2147483647
const TITEL_MAX := 500
const CURSOR_MAX := 512
const ADRESSE_MAX := 2048
const RETRY_MIN_S := 1.0
const RETRY_MAX_S := 120.0            ## länger wartet Uzai nie auf iiDB (dann: Limit erreicht)
const RPS_MAX := 20                   ## schneller fragt Uzai nie, auch wenn die Stufe mehr erlaubt
const SERVER_VERSUCHE := 2            ## Wiederholungen bei 5xx
const FEHLT_TAGE := 14                ## nicht gefunden: erst nach zwei Wochen neu fragen
const ALT_TAGE := 30                  ## Gemerktes (Klang) nach so vielen Tagen neu prüfen

## Klang der Spielseite: iiDB lässt höchstens 10 s zu; großzügig begrenzt, nie unbegrenzt.
const KLANG_MAX_MS := 30000
const KLANG_MAX_BYTES := 6 * 1024 * 1024

## Slots der Abfragen zu einem Spiel und die Asset-Arten der Galerie (background ist nur ein Slot).
const SLOTS := ["icon", "boxart", "iisu_boxart", "background", "banner", "hero", "logo", "screenshot", "soundbite"]
const ARTEN := ["boxart", "iisu_boxart", "icon", "logo", "banner", "hero", "screenshot", "soundbite"]
## Uzais Bildart → Slot beim automatischen Zuordnen (Hintergrund: erst Banner, dann Hero).
const SLOT_FUER := { "cover": "boxart", "hero": "background", "logo": "logo", "icon": "icon" }
## Bildwahl je Spiel: [Asset-Art, Name des Reiters, Uzais Bildart]. Banner (16:9) und Hero (breit)
## getrennt – beide werden Uzais Hintergrund.
const WAHL := [["boxart", "Cover", "cover"], ["iisu_boxart", "iiSU-Cover", "cover"], ["banner", "Banner", "hero"],
	["hero", "Hero", "hero"], ["logo", "Logo", "logo"], ["icon", "Symbol", "icon"]]

const HASH_LAENGE := { "md5": 32, "sha1": 40, "crc32": 8 }
const KENNUNGEN := ["game_code", "product_code", "disc_serial", "title_id", "content_id", "media_id", "executable_id",
	"catalog_number", "part_number", "database_id", "internal_name", "publisher_code"]
## Kennungen, die Uzai schon hat: Seriennummer der Disc (PS1, PS2) und der Automatenname.
const SERIEN_RAUM := { "ps1": "playstation.disc-serial", "ps2": "playstation-2.disc-serial" }
const ARCADE_RAUM := "mame.machine-name"
const REGION_FUER := { "pal": "Europe", "ntsc": "USA", "ntsc_j": "Japan" }

const BILD_ENDUNG := { "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/webp": "webp" }
const KLANG_ENDUNG := { "audio/ogg": "ogg", "application/ogg": "ogg", "audio/vorbis": "ogg", "audio/mpeg": "mp3",
	"audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/opus": "opus",
	"audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac", "audio/flac": "flac", "audio/webm": "webm" }
## Was Godot selbst abspielt; alles andere wandelt FFmpeg um (falls da) oder Uzai überspringt es.
const KLANG_NATIV := ["ogg", "mp3", "wav"]
## Was FFmpeg umwandeln darf (klang_art → Eingabeformat für FFmpeg). Nur am Anfang der Datei erkannte
## Tonformate und mit festem Format: Was sich bloß als Klang ausgibt (eine Wiedergabeliste etwa, die
## FFmpeg andere Dateien oder Adressen öffnen ließe), kommt nie bei FFmpeg an.
const KLANG_WANDELBAR := { "opus": "ogg", "flac": "flac", "m4a": "mov", "aac": "aac", "webm": "matroska" }


# --- Schlüssel ---------------------------------------------------------------------------------

## Kann dieser Text ein Schlüssel sein? "" = ja. Die Form legt iiDB fest und nennt sie nicht; Uzai
## prüft nur, was in eine Kopfzeile darf (druckbare Zeichen ohne Leerraum – nie ein Zeilenumbruch).
static func schluessel_fehler(key: String) -> String:
	var k := key.strip_edges()
	if k == "":
		return "Kein Schlüssel angekommen. Auf accounts.iisu.network kopieren und nochmal senden."
	if k.length() < 8 or k.length() > 512:
		return "Das sieht nicht wie ein iiDB-Schlüssel aus. Auf accounts.iisu.network ganz kopieren und nochmal senden."
	for i in k.length():
		var c := k.unicode_at(i)
		if c < 0x21 or c > 0x7E:
			return "Im Schlüssel steht ein fremdes Zeichen. Auf accounts.iisu.network ganz kopieren und nochmal senden."
	return ""


## Kopfzeilen einer Anfrage an die Schnittstelle. Nur dorthin, nie an den Bildserver.
static func kopf(key: String) -> PackedStringArray:
	return PackedStringArray(["X-API-Key: " + key.strip_edges(), "Accept: application/json"])


# --- Anfragen ----------------------------------------------------------------------------------
# Eine Anfrage ist { methode, pfad, query, koerper }. Unbekannte Felder lehnt iiDB mit 422 ab, darum
# gibt es hier nur die dokumentierten.

static func anfrage_zugang() -> Dictionary:
	return { "methode": "GET", "pfad": "/me/access", "query": {}, "koerper": null }


## Sammelanfrage, die Spiele findet (Titel, Kennung) und gleich ihre Bilder mitbringt.
static func anfrage_aufloesen(zeilen: Array) -> Dictionary:
	return { "methode": "POST", "pfad": "/resolve/batch", "query": {}, "koerper": { "lookups": zeilen.slice(0, BATCH_MAX) } }


## Sammelanfrage für Spiele, deren Kennung bei iiDB (parent_id) Uzai schon kennt.
static func anfrage_bilder(zeilen: Array) -> Dictionary:
	return { "methode": "POST", "pfad": "/assets/batch", "query": {}, "koerper": { "lookups": zeilen.slice(0, BATCH_MAX) } }


## Bilder eines Spiels (slots, bis sechs je Slot), z. B. Klang und Screenshots für die Spielseite.
static func anfrage_spiel(parent_id: int, slots: Array, je_slot := 1) -> Dictionary:
	if not id_ok(parent_id) or slots_pruefen(slots).is_empty():
		return {}
	var q := { "slots": ",".join(PackedStringArray(slots_pruefen(slots))) }
	if je_slot > 1:
		q["candidates_per_slot"] = clampi(je_slot, 1, 6)
	return { "methode": "GET", "pfad": "/assets/parents/%d" % parent_id, "query": q, "koerper": null }


## Eine Seite der Galerie (Bildwahl). cursor: next_cursor der Seite davor, "" für die erste.
static func anfrage_galerie(parent_id: int, art: String, cursor := "") -> Dictionary:
	if not id_ok(parent_id) or not art in ARTEN or cursor.length() > CURSOR_MAX:
		return {}
	var q := { "asset_type": art, "limit": GALERIE_SEITE }
	if art != "soundbite":
		q["animated"] = "false"       # Uzai zeigt stehende Bilder
	if cursor != "":
		q["cursor"] = cursor
	return { "methode": "GET", "pfad": "/assets/parents/%d/gallery" % parent_id, "query": q, "koerper": null }


static func anfrage_suche(wort: String) -> Dictionary:
	var w := wort.strip_edges().left(200)
	if w == "":
		return {}
	return { "methode": "GET", "pfad": "/search/parents", "query": { "q": w, "limit": SUCHE_MAX }, "koerper": null }


## Volle Adresse einer Anfrage. Der Schlüssel steht nie darin.
static func adresse(a: Dictionary) -> String:
	var q: Dictionary = a.get("query", {}) if a.get("query") is Dictionary else {}
	var teile := PackedStringArray()
	for k in q.keys():
		teile.append("%s=%s" % [str(k), str(q[k]).uri_encode()])
	return API + str(a.get("pfad", "")) + ("" if teile.is_empty() else "?" + "&".join(teile))


static func id_ok(v: int) -> bool:
	return v > 0 and v <= ID_MAX


## Nur bekannte Slots, jeder höchstens einmal.
static func slots_pruefen(slots: Array) -> Array:
	var out: Array = []
	for s in slots:
		if s is String and s in SLOTS and not s in out:
			out.append(s)
	return out


## Titel für die Suche bei iiDB ("" wenn keiner taugt).
static func titel_fuer(game: Dictionary) -> String:
	return str(game.get("title", "")).strip_edges().left(TITEL_MAX)


## Kennung prüfen: { kind, value[, namespace] } oder {}. Prüfsummen ohne Namespace und nur hex.
static func kennung_pruefen(k: Dictionary) -> Dictionary:
	var kind := str(k.get("kind", ""))
	var value := str(k.get("value", "")).strip_edges()
	var raum := str(k.get("namespace", ""))
	if value == "" or value.length() > 255 or raum.length() > 64:
		return {}
	if HASH_LAENGE.has(kind):
		value = value.to_lower()
		if value.length() != int(HASH_LAENGE[kind]) or not value.is_valid_hex_number():
			return {}
		return { "kind": kind, "value": value }
	if not kind in KENNUNGEN:
		return {}
	return { "kind": kind, "value": value, "namespace": raum } if raum != "" else { "kind": kind, "value": value }


## Kennung, die Uzai für dieses Spiel schon hat (ohne die Datei zu lesen): Seriennummer der Disc
## (PS1, PS2) oder der Name des Automaten-Spiels (Dateiname ohne Endung). {} wenn keine.
static func kennung_fuer(game: Dictionary, serial := "") -> Dictionary:
	var sys := str(game.get("system", ""))
	if SERIEN_RAUM.has(sys) and serial != "":
		return kennung_pruefen({ "kind": "disc_serial", "value": serial, "namespace": SERIEN_RAUM[sys] })
	if sys == "arcade":
		var name := str(game.get("path", "")).replace("\\", "/").get_file().get_basename().to_lower()
		if name != "" and name.length() <= 32 and _nur(name, "abcdefghijklmnopqrstuvwxyz0123456789_"):
			return kennung_pruefen({ "kind": "database_id", "value": name, "namespace": ARCADE_RAUM })
	return {}


static func _nur(text: String, erlaubt: String) -> bool:
	for ch in text:
		if not ch in erlaubt:
			return false
	return true


## Zeile für anfrage_aufloesen: Kennung (wenn da) und Titel, mit empfohlenen Bildern für slots.
## region: "pal" | "ntsc" | "ntsc_j" (Regal.region_von) – bevorzugt nur, schließt nichts aus.
static func zeile_aufloesen(game: Dictionary, kennung: Dictionary, slots: Array, region := "") -> Dictionary:
	var z := {}
	var k := kennung_pruefen(kennung)
	var titel := titel_fuer(game)
	if not k.is_empty():
		z["identity"] = k
	if titel != "":
		z["title"] = titel
	if z.is_empty():
		return {}
	z["max_candidates"] = KAND_MAX
	_bilder_wunsch(z, slots, region, true)
	return z


## Zeile für anfrage_bilder: ein bekanntes Spiel (parent_id) und die Slots.
static func zeile_bilder(parent_id: int, slots: Array, region := "") -> Dictionary:
	if not id_ok(parent_id):
		return {}
	var z := { "parent_id": parent_id }
	_bilder_wunsch(z, slots, region, false)
	return z


static func _bilder_wunsch(z: Dictionary, slots: Array, region: String, aufloesen: bool) -> void:
	var s := slots_pruefen(slots)
	if s.is_empty():
		return
	if aufloesen:
		z["artwork"] = "recommended"
	z["slots"] = s
	if REGION_FUER.has(region):
		z["preferred_region"] = REGION_FUER[region]


# --- Antworten lesen ---------------------------------------------------------------------------

## Antwort der Schnittstelle als JSON; null, wenn sie leer, zu groß oder kein JSON ist. Nur der
## JSON-Leser, nichts, was aus fremdem Text Werte oder Objekte baut.
static func json_lesen(body: PackedByteArray) -> Variant:
	if body.is_empty() or body.size() > ANTWORT_MAX:
		return null
	var js := JSON.new()
	return js.data if js.parse(body.get_string_from_utf8()) == OK else null


## Kurzer fremder Text fürs Protokoll: höchstens max_len Zeichen, ohne Steuerzeichen.
static func klar(v: Variant, max_len: int) -> String:
	if not (v is String):
		return ""
	var out := ""
	for ch in (v as String).left(max_len):
		out += ch if ch.unicode_at(0) >= 0x20 else " "
	return out

## Ganze Zahl aus JSON (dort sind alle Zahlen Kommazahlen): nur ganze Werte im Bereich, sonst fehlt.
static func _zahl(v: Variant, lo: int, hi: int, fehlt := -1) -> int:
	if v is int:
		return int(v) if int(v) >= lo and int(v) <= hi else fehlt
	if v is float and is_finite(v) and v == floorf(v) and v >= float(lo) and v <= float(hi):
		return int(v)
	return fehlt


## Ja/Nein aus JSON: nur ein echtes true zählt (ein Text „true“ oder eine Zahl nicht – und ein Vergleich
## mit == würde bei einem anderen Typ mit einem Skriptfehler abbrechen).
static func _ja(v: Variant) -> bool:
	return v is bool and bool(v)


## Kurzer Text aus JSON ohne Steuerzeichen ("" wenn es keiner ist oder er zu lang ist).
static func _text(v: Variant, max_len: int) -> String:
	if not (v is String) or (v as String).length() > max_len:
		return ""
	var t := (v as String).strip_edges()
	for i in t.length():
		if t.unicode_at(i) < 0x20:
			return ""
	return t


## Adresse eines Bilds oder Klangs: nur https, ein Rechnername ohne Zugangsdaten und Port, keine
## Leer- oder Steuerzeichen. Geladen wird sie immer ohne Schlüssel (Net.download).
static func adresse_ok(url: Variant) -> bool:
	if not (url is String) or (url as String).length() > ADRESSE_MAX or not (url as String).begins_with("https://"):
		return false
	var u := url as String
	for i in u.length():
		var c := u.unicode_at(i)
		if c <= 0x20 or c == 0x7F or c in [0x22, 0x27, 0x3C, 0x3E, 0x5C, 0x60]:
			return false
	var rest := u.substr(8)
	var cut := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < cut:
			cut = i
	var host := rest.substr(0, cut).to_lower()
	if host == "" or host.contains("@") or host.contains(":") or not host.contains(".") or host.begins_with(".") or host.ends_with("."):
		return false
	# Nie zurück an die Schnittstelle: Dort gälte der Schlüssel, und ein Bild liegt dort nicht.
	return host != API_HOST


## /me/access: { ok, stufe, api_tier, rps, name, nutzung, grenze, ueber }. Die E-Mail-Adresse und die
## Kontonummern liest Uzai gar nicht erst aus; der Name ist nur zum Anzeigen.
static func zugang_lesen(d: Variant) -> Dictionary:
	if not (d is Dictionary) or not ((d as Dictionary).get("tier") is Dictionary):
		return { "ok": false }
	var t: Dictionary = d.tier
	var rps := _zahl(t.get("requests_per_second"), 1, 100000)
	if rps < 1:
		return { "ok": false }
	var u: Dictionary = d.get("usage") if d.get("usage") is Dictionary else {}
	return { "ok": true, "stufe": _text(t.get("code"), 40), "api_tier": _zahl(t.get("api_tier"), 0, 1000, 0),
		"rps": rps, "name": _text(d.get("username"), 60),
		"nutzung": _zahl(u.get("monthly_usage"), 0, 2000000000, 0), "grenze": _zahl(u.get("monthly_soft_limit"), 0, 2000000000, 0),
		"ueber": _ja(u.get("monthly_soft_limit_exceeded")) }


## Abstand zwischen zwei Anfragen in ms für eine Stufe (Anfragen je Sekunde), mit etwas Luft.
static func takt_ms(rps: int) -> int:
	return int(ceil(1000.0 / float(clampi(rps, 1, RPS_MAX)))) + 40


## Ein Asset (Bild oder Klang) aus einer Antwort, geprüft; {} wenn etwas nicht stimmt.
## { id, art, url, rev, mime, bytes, ms, vorschau, region, name, animiert } – bytes und ms -1,
## wenn iiDB sie nicht nennt.
static func asset_lesen(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var id := _zahl(v.get("id"), 1, ID_MAX)
	var art := _text(v.get("type"), 40)
	if id < 1 or not art in ARTEN or not adresse_ok(v.get("url")):
		return {}
	var rev: Variant = v.get("revision", "")
	if not (rev is String) or (rev as String).length() > 200:
		return {}
	var vorschau: Variant = v.get("thumbnail_url")
	return { "id": id, "art": art, "url": str(v.url), "rev": str(rev), "mime": _text(v.get("mime_type"), 100).to_lower(),
		"bytes": _zahl(v.get("file_size_bytes"), 0, 2000000000), "ms": _zahl(v.get("duration_ms"), 0, 86400000),
		"vorschau": str(vorschau) if adresse_ok(vorschau) else "", "region": _text(v.get("region"), 64),
		"name": _text(v.get("display_name"), 120), "animiert": _ja(v.get("is_animated")) }


## „artwork“ einer Antwort: Slot → Liste geprüfter Assets, beste zuerst. Nur bekannte Slots, je Slot
## höchstens sechs; ein Asset im falschen Slot fällt weg (background trägt Banner und Heroes).
static func bilder_lesen(artwork: Variant) -> Dictionary:
	var out := {}
	if not (artwork is Dictionary):
		return out
	for slot in SLOTS:
		var liste: Variant = artwork.get(slot)
		if not (liste is Array):
			continue
		var gut: Array = []
		for it in (liste as Array).slice(0, 6):
			var a := asset_lesen(it)
			if a.is_empty():
				continue
			if str(a.art) == slot or (slot == "background" and str(a.art) in ["banner", "hero"]):
				gut.append(a)
		out[slot] = gut
	return out


static func _kandidaten(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for it in (v as Array).slice(0, KAND_MAX):
		if not (it is Dictionary):
			continue
		var id := _zahl(it.get("id"), 1, ID_MAX)
		var name := _text(it.get("name"), TITEL_MAX)
		if id < 1 or name == "":
			continue
		out.append({ "id": id, "name": name, "jahr": _zahl(it.get("year"), 1950, 2200, 0),
			"plattform": _text(it.get("primary_platform"), 80) })
	return out


## Eine Zeile aus /resolve oder /resolve/batch.
## { status: "matched" | "needs_choice" | "not_found" | "fehler", id, name, jahr, bilder, bild_stand,
##   kandidaten, zusatz } – needs_choice ist eine offene Wahl, kein Fehltreffer.
static func treffer_lesen(v: Variant) -> Dictionary:
	var leer := { "status": "fehler", "id": 0, "name": "", "jahr": 0, "bilder": {}, "bild_stand": "", "kandidaten": [], "zusatz": false }
	if not (v is Dictionary) or not ((v as Dictionary).get("match") is Dictionary):
		return leer
	var m: Dictionary = v.match
	var status := _text(m.get("status"), 20)
	if not status in ["matched", "needs_choice", "not_found"]:
		return leer
	var out := leer.duplicate(true)
	out.status = status
	out.bild_stand = _text(v.get("artwork_status"), 20)
	out.zusatz = _text(v.get("content_role"), 20) == "supplemental" or str(out.bild_stand) == "blocked"
	if status == "matched":
		var p: Variant = m.get("parent")
		var id := _zahl(p.get("id"), 1, ID_MAX) if p is Dictionary else -1
		if id < 1:
			return leer
		out.id = id
		out.name = _text(p.get("name"), TITEL_MAX)
		out.jahr = _zahl(p.get("year"), 1950, 2200, 0)
		out.bilder = bilder_lesen(v.get("artwork"))
	elif status == "needs_choice":
		out.kandidaten = _kandidaten(v.get("candidates"))
	return out


## Eine Zeile aus /assets/batch (Spiel schon bekannt): { status: "matched" | "fehler", id, bilder, … }.
static func bilder_zeile_lesen(v: Variant) -> Dictionary:
	var out := { "status": "fehler", "id": 0, "name": "", "jahr": 0, "bilder": {}, "bild_stand": "", "kandidaten": [], "zusatz": false }
	if not (v is Dictionary) or (v as Dictionary).has("errors"):
		return out
	var id := _zahl(v.get("parent_id"), 1, ID_MAX)
	var stand := _text(v.get("artwork_status"), 20)
	if id < 1 or stand == "":
		return out
	out.status = "matched"
	out.id = id
	out.name = _text(v.get("name"), TITEL_MAX)
	out.bild_stand = stand
	out.zusatz = stand == "blocked"
	out.bilder = bilder_lesen(v.get("artwork"))
	return out


## Antwort einer Sammelanfrage: genau so viele Zeilen wie gefragt, in derselben Reihenfolge – sonst
## gilt die ganze Antwort nicht (leere Liste), damit nie ein Bild beim falschen Spiel landet.
static func batch_lesen(d: Variant, erwartet: int, bilder := false) -> Array:
	if not (d is Dictionary) or not ((d as Dictionary).get("results") is Array) or (d.results as Array).size() != erwartet:
		return []
	var out: Array = []
	for z in d.results:
		out.append(bilder_zeile_lesen(z) if bilder else treffer_lesen(z))
	return out


## Antwort von /assets/parents/{id}: die Bilder des Spiels (Form wie eine Zeile aus /resolve).
static func spiel_lesen(d: Variant) -> Dictionary:
	if d is Dictionary and (d as Dictionary).get("artwork") is Dictionary:
		return bilder_lesen(d.artwork)
	return {}


## Eine Seite der Galerie: { ok, items, weiter, mehr, gesamt }. weiter ist der Cursor der nächsten
## Seite; mehr ohne brauchbaren Cursor gilt als Ende (sonst bliebe „Mehr laden“ ewig stehen).
static func galerie_lesen(d: Variant, art: String) -> Dictionary:
	var out := { "ok": false, "items": [], "weiter": "", "mehr": false, "gesamt": 0 }
	if not (d is Dictionary) or not ((d as Dictionary).get("page") is Dictionary):
		return out
	var liste: Variant = d.get("items", [])
	if not (liste is Array):
		return out
	for it in (liste as Array).slice(0, 100):
		var a := asset_lesen(it)
		if not a.is_empty() and str(a.art) == art:
			(out.items as Array).append(a)
	var p: Dictionary = d.page
	var cur: Variant = p.get("next_cursor")
	if cur is String and (cur as String) != "" and (cur as String).length() <= CURSOR_MAX and _text(cur, CURSOR_MAX) != "":
		out.weiter = cur
	out.mehr = _ja(p.get("has_more")) and str(out.weiter) != ""
	out.gesamt = _zahl(p.get("total"), 0, 100000000, 0)
	out.ok = true
	return out


## Treffer der Suche („Anderes Spiel“): [{ id, name, jahr, plattform }].
static func suche_lesen(d: Variant) -> Array:
	var out: Array = []
	if not (d is Dictionary) or not ((d as Dictionary).get("results") is Array):
		return out
	for it in (d.results as Array).slice(0, SUCHE_MAX):
		if not (it is Dictionary):
			continue
		var id := _zahl(it.get("parent_id"), 1, ID_MAX)
		var name := _text(it.get("name"), TITEL_MAX)
		if id >= 1 and name != "":
			out.append({ "id": id, "name": name, "jahr": _zahl(it.get("initial_release_year"), 1950, 2200, 0),
				"plattform": _text(it.get("primary_platform"), 80) })
	return out


## Zeile für eine Auswahlliste: „Name (Jahr) · Plattform“.
static func kandidat_text(k: Dictionary) -> String:
	var t := str(k.get("name", ""))
	if int(k.get("jahr", 0)) > 0:
		t += " (%d)" % int(k.jahr)
	if str(k.get("plattform", "")) != "":
		t += " · " + str(k.plattform)
	return t


# --- Fehler ------------------------------------------------------------------------------------

## Wartezeit aus Retry-After (Sekunden als Zahl; ein Datum zählt wie „unbekannt“), begrenzt.
static func retry_after(kopfzeilen: Variant) -> float:
	if kopfzeilen is PackedStringArray or kopfzeilen is Array:
		for h in kopfzeilen:
			var z := str(h)
			if z.to_lower().begins_with("retry-after:"):
				var w := z.substr(12).strip_edges()
				if w.is_valid_int() or w.is_valid_float():
					return clampf(float(w), RETRY_MIN_S, RETRY_MAX_S)
	return 2.0


## Antwort deuten: { grund, warte_s, nochmal, request_id }.
## grund: "" (gut) · "zugang" (401: neuer Schlüssel, nie wiederholen) · "verboten" (403) · "fehlt" (404)
## · "anfrage" (400/422: Fehler in Uzais Anfrage) · "kontingent" (429: warte_s abwarten) · "server"
## (5xx: wenige Wiederholungen) · "netz" (keine Antwort) · "form" (200, aber kein brauchbares JSON).
static func fehler_lesen(code: int, d: Variant, kopfzeilen: Variant = null) -> Dictionary:
	var out := { "grund": "", "warte_s": 0.0, "nochmal": false, "request_id": "" }
	var rid: Variant = d.get("request_id") if d is Dictionary else null
	if not (rid is String) or (rid as String) == "":
		rid = _kopf(kopfzeilen, "x-request-id")
	if rid is String and (rid as String).length() <= 64 and _nur((rid as String).to_lower(), "abcdefghijklmnopqrstuvwxyz0123456789-_"):
		out.request_id = rid
	if code >= 200 and code < 300:
		out.grund = "" if d is Dictionary else "form"
	elif code == 401:
		out.grund = "zugang"
	elif code == 403:
		out.grund = "verboten"
	elif code == 404:
		out.grund = "fehlt"
	elif code in [400, 422]:
		out.grund = "anfrage"
	elif code == 429:
		out.grund = "kontingent"
		out.warte_s = retry_after(kopfzeilen)
	elif code >= 500 and code < 600:
		out.grund = "server"
		out.nochmal = true
	else:
		out.grund = "netz"
	return out


static func _kopf(kopfzeilen: Variant, name: String) -> String:
	if kopfzeilen is PackedStringArray or kopfzeilen is Array:
		for h in kopfzeilen:
			if str(h).to_lower().begins_with(name + ":"):
				return str(h).substr(name.length() + 1).strip_edges()
	return ""


## Darf Uzai dieses Ergebnis merken („nicht gefunden“ für zwei Wochen)? Netzfehler, 429 und
## Serverfehler sind nie ein Ergebnis – die Anfrage kam nicht an.
static func merkbar(grund: String) -> bool:
	return grund in ["", "fehlt"]


## Satz für den Nutzer, wenn iiDB nichts liefert.
static func grund_text(grund: String) -> String:
	match grund:
		"zugang": return "iiDB: Schlüssel abgelehnt. Neu verbinden."
		"verboten": return "iiDB erlaubt das mit diesem Schlüssel nicht."
		"kontingent": return "iiDB: Limit erreicht. Gleich nochmal versuchen."
		"wahl": return "iiDB kennt mehrere Spiele mit diesem Namen. „Anderes Spiel“ wählen."
		"fehlt": return "Spiel nicht gefunden. „Anderes Spiel“ wählen."
		"anfrage", "form": return "iiDB hat die Anfrage nicht verstanden. Details: logs/iidb.log"
	return "iiDB nicht erreichbar."


# --- Dateien und Merken ------------------------------------------------------------------------

## Dateiname eines geladenen Assets: nur aus der geprüften Nummer und einer Prüfsumme der Revision.
## Ein geändertes Bild (neue Revision) bekommt so einen neuen Namen.
static func datei_name(a: Dictionary, kind: String, ext: String) -> String:
	return "iidb_%d_%s_%s.%s" % [int(a.get("id", 0)), str(a.get("rev", "")).md5_text().substr(0, 10), kind, ext]


## Anfang des Dateinamens eines Assets (Haken in der Bildwahl: Dieses Bild gilt gerade).
static func datei_anfang(a: Dictionary) -> String:
	return "iidb_%d_" % int(a.get("id", 0))


## Dateiendung eines Bilds: aus dem Typ, sonst aus der Adresse, sonst png.
static func bild_endung(a: Dictionary) -> String:
	var m := str(a.get("mime", ""))
	if BILD_ENDUNG.has(m):
		return BILD_ENDUNG[m]
	var e := str(a.get("url", "")).get_slice("?", 0).get_extension().to_lower()
	return e if e in ["png", "jpg", "jpeg", "webp"] else "png"


## Dateiendung eines Klangs ("" = unbekanntes Format, überspringen).
static func klang_endung(a: Dictionary) -> String:
	var m := str(a.get("mime", ""))
	if KLANG_ENDUNG.has(m):
		return KLANG_ENDUNG[m]
	var e := str(a.get("url", "")).get_slice("?", 0).get_extension().to_lower()
	return e if e in KLANG_ENDUNG.values() else ""


## Taugt dieses Asset als Klang der Spielseite? "" = ja, sonst "art", "lang", "gross" oder "format".
## Nennt iiDB Dauer oder Größe nicht, begrenzt erst das Laden (KLANG_MAX_BYTES).
static func klang_grund(a: Dictionary) -> String:
	if str(a.get("art", "")) != "soundbite":
		return "art"
	if int(a.get("ms", -1)) > KLANG_MAX_MS:
		return "lang"
	if int(a.get("bytes", -1)) > KLANG_MAX_BYTES:
		return "gross"
	return "" if klang_endung(a) != "" else "format"


## Hat ein Download (Net.request: result, code) etwas über den Klang gesagt – oder kam er nur nicht an
## (kein Netz, Zeitlimit, 408, 429, 5xx)? Nur eine Antwort darf Uzai merken.
static func download_ist_antwort(ergebnis: int, code: int) -> bool:
	if ergebnis == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return true
	return ergebnis == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 500 and not code in [408, 429]


## Der erste taugliche Klang aus einer Liste ({} wenn keiner).
static func klang_wahl(liste: Variant) -> Dictionary:
	if liste is Array:
		for a in liste:
			if a is Dictionary and klang_grund(a) == "":
				return a
	return {}


## Was Uzai je Spiel merkt (Feld „iidb“ im Eintrag): { id, name, t } nach einem Treffer, { wahl: t }
## solange der Nutzer wählen muss, { fehlt: t } wenn iiDB das Spiel nicht kennt. Geprüft gelesen,
## weil der Eintrag aus einer Datei kommt.
static func gemerkt(game: Dictionary) -> Dictionary:
	var v: Variant = game.get("iidb")
	if not (v is Dictionary):
		return {}
	var out := {}
	var id := _zahl(v.get("id"), 1, ID_MAX)
	if id >= 1:
		out["id"] = id
		out["name"] = _text(v.get("name"), TITEL_MAX)
	for k in ["t", "wahl", "fehlt"]:
		var z := _zahl(v.get(k), 1, 9000000000)
		if z > 0:
			out[k] = z
	var kl: Variant = v.get("klang")
	if kl is Dictionary and _zahl(kl.get("id"), 1, ID_MAX) >= 1 and _text(kl.get("datei"), 120) != "" \
			and _nur(str(kl.datei), "abcdefghijklmnopqrstuvwxyz0123456789_."):
		out["klang"] = { "id": _zahl(kl.get("id"), 1, ID_MAX), "datei": str(kl.datei), "t": _zahl(kl.get("t"), 0, 9000000000, 0) }
		if kl.get("eigen") is bool and bool(kl.eigen):
			out.klang["eigen"] = true     # selbst gewählt (Bildwahl, Reiter „Klang“): nie von allein ersetzt
	elif kl is Dictionary and _zahl(kl.get("fehlt"), 1, 9000000000) > 0:
		out["klang"] = { "fehlt": _zahl(kl.get("fehlt"), 1, 9000000000) }
	return out


## Kennung des Spiels bei iiDB (0 = noch nicht zugeordnet).
static func parent_id(game: Dictionary) -> int:
	return int(gemerkt(game).get("id", 0))


## Soll Uzai für dieses Spiel (noch einmal) bei iiDB nach dem Spiel fragen? Nicht, wenn es schon
## zugeordnet ist, der Nutzer erst wählen muss oder iiDB es vor Kurzem nicht kannte. neu: Alles
## ersetzen – „nicht gefunden“ trotzdem neu fragen.
static func soll_suchen(game: Dictionary, jetzt: int, neu := false) -> bool:
	var g := gemerkt(game)
	if g.has("id"):
		return false
	if neu:
		return true
	if g.has("wahl"):
		return false
	return jetzt - int(g.get("fehlt", 0)) >= FEHLT_TAGE * 86400


## Neuer Merk-Eintrag nach einer Antwort (treffer_lesen). Der alte bleibt, wenn die Antwort kein
## Ergebnis ist ("fehler").
static func merken(alt: Dictionary, t: Dictionary, jetzt: int) -> Dictionary:
	match str(t.get("status", "")):
		"matched":
			var gleich := int(alt.get("id", 0)) == int(t.id)
			var neu := { "id": int(t.id), "name": str(t.get("name", "")), "t": jetzt }
			if str(neu.name) == "" and gleich:
				neu.name = str(alt.get("name", ""))
			if alt.get("klang") is Dictionary and gleich:
				neu["klang"] = alt.klang
			return neu
		"needs_choice":
			return { "wahl": jetzt }
		"not_found":
			return { "fehlt": jetzt }
	return alt


# --- Klang abspielen ---------------------------------------------------------------------------

## Klang aus dem Cache als Schleife laden (OGG Vorbis, MP3, WAV – am Anfang der Datei erkannt, nicht
## an der Endung). null, wenn die Datei kein solcher Klang ist, leer oder länger als KLANG_MAX_MS.
static func klang_strom(pfad: String) -> AudioStream:
	var b := FileAccess.get_file_as_bytes(pfad)
	if b.size() < 64 or b.size() > KLANG_MAX_BYTES:
		return null
	var s: AudioStream = null
	match klang_art(b):
		"ogg":
			var o := AudioStreamOggVorbis.load_from_buffer(b)
			if o:
				o.loop = true
			s = o
		"wav":
			var w := AudioStreamWAV.load_from_buffer(b)
			if w:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_end = int(w.get_length() * float(w.mix_rate))
			s = w
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = b
			m.loop = true
			s = m
	if s == null or not (s.get_length() > 0.2) or s.get_length() * 1000.0 > float(KLANG_MAX_MS):
		return null
	return s


## Ist das OGG Vorbis? (Im selben Behälter steckt oft Opus; das spielt Godot nicht.) Das erste Paket
## beginnt hinter dem Seitenkopf mit 0x01 „vorbis“.
static func ogg_vorbis(b: PackedByteArray) -> bool:
	if b.size() < 64 or b.slice(0, 4).get_string_from_ascii() != "OggS":
		return false
	var anfang := 27 + int(b[26])
	return b.size() > anfang + 7 and b[anfang] == 1 and b.slice(anfang + 1, anfang + 7).get_string_from_ascii() == "vorbis"


## Tonformat, am Anfang der Daten erkannt (nie an der Endung oder am Typ aus der Antwort): "ogg"
## (Vorbis), "mp3", "wav" spielt Godot selbst; "opus" (im OGG-Behälter), "flac", "m4a", "aac", "webm"
## wandelt FFmpeg; "" kennt Uzai nicht.
static func klang_art(b: PackedByteArray) -> String:
	if b.size() < 64:
		return ""
	var kopf4 := b.slice(0, 4).get_string_from_ascii()
	if kopf4 == "OggS":
		if ogg_vorbis(b):
			return "ogg"
		var anfang := 27 + int(b[26])
		return "opus" if b.size() >= anfang + 8 and b.slice(anfang, anfang + 8).get_string_from_ascii() == "OpusHead" else ""
	if kopf4 == "RIFF":
		return "wav" if b.slice(8, 12).get_string_from_ascii() == "WAVE" else ""
	if kopf4 == "fLaC":
		return "flac"
	if b.slice(4, 8).get_string_from_ascii() == "ftyp":
		return "m4a"
	if b[0] == 0x1A and b[1] == 0x45 and b[2] == 0xDF and b[3] == 0xA3:
		return "webm"
	if kopf4.begins_with("ID3"):
		return "mp3"
	if b[0] == 0xFF:
		# AAC (ADTS) und MP3 beginnen fast gleich: Bei AAC sind zwölf Bits gesetzt und die Schicht ist 0,
		# bei MP3 elf Bits und die Schicht nie 0.
		if (b[1] & 0xF6) == 0xF0:
			return "aac"
		if (b[1] & 0xE0) == 0xE0 and (b[1] & 0x06) != 0:
			return "mp3"
	return ""


## Spielt Godot diese Daten selbst (OGG Vorbis, MP3, WAV)? Sonst muss FFmpeg umwandeln.
static func klang_nativ(b: PackedByteArray) -> bool:
	return klang_art(b) in KLANG_NATIV


## Einen Klang mit FFmpeg nach OGG Vorbis wandeln (Formate, die Godot nicht abspielt). Läuft im
## Hintergrund (Arbeit); Argumente nur als Liste, höchstens KLANG_MAX_MS lang. true, wenn es ging.
## FFmpeg rät das Format nicht selbst und öffnet nur diese eine Datei (KLANG_WANDELBAR).
static func klang_umwandeln(ffmpeg: String, quelle: String, ziel: String) -> bool:
	if ffmpeg == "" or not FileAccess.file_exists(ffmpeg):
		return false
	var f := FileAccess.open(quelle, FileAccess.READ)
	if f == null:
		return false
	var art := klang_art(f.get_buffer(64))
	f.close()
	if not KLANG_WANDELBAR.has(art):
		return false
	var args := PackedStringArray(["-nostdin", "-y", "-v", "error", "-protocol_whitelist", "file", "-f", str(KLANG_WANDELBAR[art]),
		"-i", quelle, "-vn", "-t", "%.1f" % (KLANG_MAX_MS / 1000.0), "-c:a", "libvorbis", "-q:a", "4", ziel])
	var code := OS.execute(ffmpeg, args, [], true)
	return code == 0 and FileAccess.file_exists(ziel)

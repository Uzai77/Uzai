extends Node
## iiDB als Bild- und Klangquelle (docs/IIDB.md): Anfragen, strenges Lesen der Antworten, Fehlerregeln,
## Merken je Spiel – gegen nachgebaute Antworten in der Form der Entwickler-Doku, ohne Netz.
## Aufruf: godot --headless --path . res://tests/logic_iidb.tscn

const I := preload("res://src/core/iidb.gd")
const Quelle := preload("res://tests/quelle.gd")

const KEY := "iidb_test_SCHLUESSEL_0123456789"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _asset(id: int, art: String, mehr := {}) -> Dictionary:
	var a := { "id": float(id), "type": art, "url": "https://assets.iisu.network/a/%d.png" % id, "revision": "r%d" % id }
	a.merge(mehr, true)
	return a


func _treffer(id: int, name: String, artwork := {}) -> Dictionary:
	return { "match": { "status": "matched", "parent": { "id": float(id), "name": name, "year": 2005.0 } },
		"artwork_status": "partial", "artwork": artwork, "missing_artwork": {} }


func _ready() -> void:
	_schluessel()
	_anfragen()
	_lesen()
	_fehler()
	_klang()
	_merken()
	await _dienst()
	_quelltext()
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _schluessel() -> void:
	print("Schlüssel")
	check(I.schluessel_fehler(KEY) == "" and I.schluessel_fehler("  " + KEY + "\n") == "", "brauchbarer Schlüssel, Leerraum am Rand zählt nicht")
	check(I.schluessel_fehler("") != "" and I.schluessel_fehler("kurz") != "", "leer oder zu kurz: abgelehnt")
	check(I.schluessel_fehler("abc def ghi jkl") != "" and I.schluessel_fehler("abcdefgh\r\nX-Injected: 1") != ""
			and I.schluessel_fehler("schlüssel-mit-umlaut") != "", "Leerzeichen, Zeilenumbruch, fremde Zeichen: abgelehnt (nichts schmuggelt eine Kopfzeile ein)")
	var k := I.kopf(" " + KEY + " ")
	check(k.size() == 2 and k[0] == "X-API-Key: " + KEY, "Schlüssel nur in der Kopfzeile X-API-Key")


func _anfragen() -> void:
	print("Anfragen")
	var alle := [I.anfrage_zugang(), I.anfrage_spiel(46185, ["soundbite", "screenshot"], 3), I.anfrage_galerie(46185, "banner", "abc=="),
		I.anfrage_suche("Ape Escape 3"), I.anfrage_aufloesen([{ "title": "x" }]), I.anfrage_bilder([{ "parent_id": 1 }])]
	check(alle.all(func(a: Dictionary) -> bool: return I.adresse(a).begins_with("https://iidb-api.iisu.network/api/v1/") and not I.adresse(a).contains(KEY)),
			"alle Adressen gehen an die Schnittstelle, keine trägt einen Schlüssel")
	check(I.adresse(I.anfrage_spiel(46185, ["soundbite", "screenshot"],
			3)) == "https://iidb-api.iisu.network/api/v1/assets/parents/46185?slots=soundbite%2Cscreenshot&candidates_per_slot=3",
			"Bilder eines Spiels: slots und candidates_per_slot")
	var gal := I.anfrage_galerie(46185, "banner", "abc==")
	check(str(gal.pfad) == "/assets/parents/46185/gallery" and (gal.query as Dictionary).keys() == ["asset_type", "limit", "animated", "cursor"],
			"Galerie: nur dokumentierte Parameter (asset_type, limit, animated, cursor)")
	check(I.anfrage_galerie(46185, "background").is_empty() and I.anfrage_galerie(0, "banner").is_empty() and I.anfrage_galerie(1, "hero",
			"x".repeat(600)).is_empty(),
			"Galerie: background ist kein Typ, Nummer und Cursor geprüft")
	check(I.anfrage_spiel(5, ["frei_erfunden"]).is_empty() and I.slots_pruefen(["boxart", "boxart", "x", 3, "logo"]) == ["boxart", "logo"],
			"unbekannte oder doppelte Slots gehen nie raus (422)")
	check(I.anfrage_suche("   ").is_empty(), "leere Suche: keine Anfrage")
	var viele: Array = []
	for i in 40:
		viele.append({ "title": "Spiel %d" % i })
	check((I.anfrage_aufloesen(viele).koerper.lookups as Array).size() == 25, "höchstens 25 Zeilen je Sammelanfrage")

	print("Kennungen und Zeilen")
	var ps2 := { "id": "rom:ico", "title": "Ico", "system": "ps2", "source": "rom", "path": "D:/Spiele/Ico.iso" }
	check(I.kennung_fuer(ps2, "SCES-50760") == { "kind": "disc_serial", "value": "SCES-50760", "namespace": "playstation-2.disc-serial" },
			"PS2: Seriennummer mit Namespace")
	check(I.kennung_fuer(ps2, "").is_empty() and I.kennung_fuer({ "system": "gba", "path": "x.gba" }, "ABCD").is_empty(),
			"ohne bekannte Kennung: keine (nichts geraten)")
	check(I.kennung_fuer({ "system": "arcade", "path": "D:/Arcade/sf2.zip" }) == { "kind": "database_id", "value": "sf2", "namespace": "mame.machine-name" },
			"Automat: Name des Spiels als database_id")
	check(I.kennung_fuer({ "system": "arcade", "path": "D:/Arcade/Street Fighter II.zip" }).is_empty(), "Automat mit freiem Dateinamen: keine Kennung")
	check(I.kennung_pruefen({ "kind": "md5", "value": "D41D8CD98F00B204E9800998ECF8427E", "namespace": "x" }) == { "kind": "md5",
			"value": "d41d8cd98f00b204e9800998ecf8427e" },
			"Prüfsumme: klein geschrieben, ohne Namespace")
	check(I.kennung_pruefen({ "kind": "md5", "value": "zz1d8cd98f00b204e9800998ecf8427e" }).is_empty() and I.kennung_pruefen({ "kind": "crc32",
			"value": "123" }).is_empty()
			and I.kennung_pruefen({ "kind": "erfunden", "value": "1" }).is_empty(), "falsche Länge, kein Hex, unbekannte Art: verworfen")
	var z := I.zeile_aufloesen(ps2, I.kennung_fuer(ps2, "SCES-50760"), ["boxart", "background"], "pal")
	check(z.keys() == ["identity", "title", "max_candidates", "artwork", "slots", "preferred_region"] and str(z.artwork) == "recommended"
			and str(z.preferred_region) == "Europe" and z.slots == ["boxart",
					"background"], "Zeile zum Finden: Kennung, Titel, Bilder empfohlen, Region bevorzugt")
	var ohne := I.zeile_aufloesen({ "title": "Ico" }, {}, [])
	check(ohne.keys() == ["title", "max_candidates"], "ohne Bilder: keine Bild-Optionen (sonst 422)")
	check(I.zeile_aufloesen({ "title": "  " }, {}, ["boxart"]).is_empty(), "ohne Titel und Kennung: keine Zeile")
	check(I.zeile_bilder(46185, ["boxart"], "ntsc_j") == { "parent_id": 46185, "slots": ["boxart"], "preferred_region": "Japan" } and I.zeile_bilder(0,
			["boxart"]).is_empty(),
			"Zeile für ein bekanntes Spiel: nur parent_id und Slots")


func _lesen() -> void:
	print("Zugang")
	var zug := I.zugang_lesen({ "user_id": 7.0, "username": "spieler", "email": "geheim@example.org", "iisu_user_id": "u-1", "user_type": "user",
		"tier": { "code": "supporter", "api_tier": 2.0, "requests_per_second": 5.0 }, "usage": { "monthly_usage": 120.0, "monthly_soft_limit": 10000.0 },
		"api_key": {} })
	check(bool(zug.ok) and str(zug.stufe) == "supporter" and int(zug.rps) == 5 and str(zug.name) == "spieler" and int(zug.nutzung) == 120,
			"Stufe, Anfragen je Sekunde, Name gelesen")
	check(not zug.has("email") and not zug.has("user_id") and not JSON.stringify(zug).contains("geheim"), "E-Mail-Adresse und Kontonummern werden verworfen")
	check(not bool(I.zugang_lesen({ "tier": { "requests_per_second": 0.0 } }).ok) and not bool(I.zugang_lesen("x").ok)
			and not bool(I.zugang_lesen({ "tier": [] }).ok),
			"ohne brauchbare Stufe: nicht verbunden")
	check(I.takt_ms(1) >= 1000 and I.takt_ms(5) >= 200 and I.takt_ms(5) < 300 and I.takt_ms(100000) == I.takt_ms(I.RPS_MAX) and I.takt_ms(0) == I.takt_ms(1),
			"Takt aus der Stufe, nach oben und unten begrenzt")

	print("Assets")
	var a := I.asset_lesen(_asset(456, "boxart", { "mime_type": "image/PNG", "file_size_bytes": 2048.0,
			"thumbnail_url": "https://assets.iisu.network/t/456.webp" }))
	check(int(a.id) == 456 and str(a.art) == "boxart" and str(a.mime) == "image/png" and int(a.bytes) == 2048 and int(a.ms) == -1
			and str(a.vorschau).ends_with("456.webp"),
			"Asset gelesen; fehlende Dauer ist -1")
	var schlecht := [_asset(1, "boxart", { "url": "http://assets.iisu.network/a.png" }), _asset(2, "boxart",
			{ "url": "https://user:pw@assets.iisu.network/a.png" }),
		_asset(3, "boxart", { "url": "https://assets.iisu.network:8443/a.png" }), _asset(4, "boxart",
				{ "url": "https://iidb-api.iisu.network/api/v1/me/access" }),
		_asset(5, "boxart", { "url": "https://assets.iisu.network/a b.png" }), _asset(6, "erfunden"), _asset(0, "boxart"), _asset(7, "boxart", { "id": 7.5 }),
		_asset(8, "boxart", { "id": "8" }), _asset(9, "boxart", { "revision": 12.0 }), _asset(10, "boxart",
				{ "url": "file:///C:/Windows/win.ini" }), "kein Wörterbuch", null]
	check(schlecht.all(func(v: Variant) -> bool: return I.asset_lesen(v).is_empty()),
			"verworfen: http, Zugangsdaten, Port, Adresse der Schnittstelle, Leerzeichen, fremde Art, Nummer 0/Komma/Text, Revision als Zahl, file://")
	check(str(I.asset_lesen(_asset(11, "logo", { "thumbnail_url": "javascript:alert(1)" })).vorschau) == "",
			"unbrauchbare Vorschau fällt weg, das Asset bleibt")
	var b := I.bilder_lesen({ "boxart": [_asset(1, "boxart"), _asset(2, "logo")], "background": [_asset(3, "banner"), _asset(4, "hero"), _asset(5, "icon")],
		"logo": [], "erfunden": [_asset(6, "boxart")], "icon": "kaputt" })
	check((b.boxart as Array).size() == 1 and (b.background as Array).map(func(x: Dictionary) -> int: return int(x.id)) == [3, 4]
			and (b.logo as Array).is_empty()
			and not b.has("erfunden") and not b.has("icon"), "Slots: nur bekannte, jedes Asset in seinem Slot, background trägt Banner und Hero")

	# Falsche Typen bei Ja/Nein-Feldern: kein Skriptfehler, sie zählen als „nein“.
	var schief := I.asset_lesen(_asset(12, "logo", { "is_animated": "ja" }))
	var seite_schief := I.galerie_lesen({ "items": [], "page": { "has_more": "true", "next_cursor": "c", "total": "viele" } }, "logo")
	var zugang_schief := I.zugang_lesen({ "tier": { "code": "x", "requests_per_second": 1.0 }, "usage": { "monthly_soft_limit_exceeded": 1.0 } })
	check(not schief.is_empty() and not bool(schief.animiert) and bool(seite_schief.ok) and not bool(seite_schief.mehr) and bool(zugang_schief.ok)
			and not bool(zugang_schief.ueber),
			"Ja/Nein als Text oder Zahl: zählt als nein, ohne Fehler")
	print("Treffer")
	var t := I.treffer_lesen(_treffer(46185, "Ape Escape 3", { "boxart": [_asset(456, "boxart")], "background": [] }))
	check(str(t.status) == "matched" and int(t.id) == 46185 and str(t.name) == "Ape Escape 3" and int(t.jahr) == 2005
			and (t.bilder.boxart as Array).size() == 1, "matched: Spiel und Bilder")
	var wahl := I.treffer_lesen({ "match": { "status": "needs_choice", "parent": null }, "artwork_status": "not_resolved", "artwork": {},
		"candidates": [{ "id": 11.0, "name": "Doom", "year": 1993.0, "primary_platform": "DOS", "reason": "name_exact" }, { "id": 12.0, "name": "Doom",
				"year": 2016.0 },
			{ "id": -3.0, "name": "kaputt" }, { "id": 13.0, "name": "" }, "x"], "candidate_count": 5.0 })
	check(str(wahl.status) == "needs_choice" and (wahl.kandidaten as Array).size() == 2 and int(wahl.id) == 0,
			"needs_choice: eine Wahl mit geprüften Kandidaten, kein Fehltreffer")
	check(I.kandidat_text(wahl.kandidaten[0]) == "Doom (1993) · DOS" and I.kandidat_text(wahl.kandidaten[1]) == "Doom (2016)",
			"Zeile der Auswahl: Name, Jahr, Plattform")
	check(str(I.treffer_lesen({ "match": { "status": "not_found", "parent": null }, "artwork_status": "not_resolved" }).status) == "not_found",
			"not_found gelesen")
	check(str(I.treffer_lesen({ "status": "invalid_request", "errors": [{ "loc": ["title"], "type": "x", "msg": "y" }] }).status) == "fehler"
			and str(I.treffer_lesen({ "match": { "status": "matched", "parent": null } }).status) == "fehler"
			and str(I.treffer_lesen({ "match": { "status": "vielleicht" } }).status) == "fehler" and str(I.treffer_lesen([1, 2]).status) == "fehler",
			"Fehlerzeile, Treffer ohne Spiel, unbekannter Status, falsche Form: kein Ergebnis")
	check(bool(I.treffer_lesen({ "match": { "status": "matched", "parent": { "id": 5.0, "name": "DLC" } }, "artwork_status": "blocked",
			"content_role": "supplemental" }).zusatz),
			"Zusatzinhalt erkannt (trägt keine Bilder)")

	print("Sammelantwort")
	var antwort := { "results": [_treffer(1, "Eins", { "boxart": [_asset(101, "boxart")] }), { "match": { "status": "not_found", "parent": null },
			"artwork_status": "not_resolved" },
		{ "status": "invalid_request", "errors": [] }, _treffer(4, "Vier", { "boxart": [_asset(104, "boxart")] })] }
	var r := I.batch_lesen(antwort, 4)
	check(r.size() == 4 and int(r[0].id) == 1 and str(r[1].status) == "not_found" and str(r[2].status) == "fehler" and int(r[3].id) == 4
			and int(r[3].bilder.boxart[0].id) == 104, "Reihenfolge bleibt: Zeile n der Antwort gehört zu Zeile n der Anfrage")
	check(I.batch_lesen(antwort, 5).is_empty() and I.batch_lesen(antwort, 3).is_empty() and I.batch_lesen({ "results": "x" }, 1).is_empty()
			and I.batch_lesen(null, 1).is_empty(),
			"andere Zeilenzahl oder falsche Form: die ganze Antwort gilt nicht")
	var bb := I.batch_lesen({ "results": [{ "parent_id": 9.0, "name": "Neun", "artwork_status": "available", "artwork": { "logo": [_asset(900, "logo")] } },
		{ "status": "invalid_request", "errors": [{ "loc": ["parent_id"], "type": "t", "msg": "m" }] }] }, 2, true)
	check(bb.size() == 2 and str(bb[0].status) == "matched" and int(bb[0].id) == 9 and int(bb[0].bilder.logo[0].id) == 900 and str(bb[1].status) == "fehler",
			"/assets/batch: Bilder bekannter Spiele, Fehlerzeile bleibt an ihrem Platz")

	print("Galerie und Suche")
	var g1 := I.galerie_lesen({ "parent_id": 1.0, "name": "x", "type": "banner", "items": [_asset(1, "banner"), _asset(2, "hero"), _asset(3, "banner")],
		"page": { "limit": 24.0, "total": 40.0, "next_cursor": "c2", "has_more": true } }, "banner")
	check(bool(g1.ok) and (g1.items as Array).size() == 2 and str(g1.weiter) == "c2" and bool(g1.mehr) and int(g1.gesamt) == 40,
			"Seite gelesen, fremde Art fällt raus, Cursor für die nächste Seite")
	var g2 := I.galerie_lesen({ "items": [], "page": { "limit": 24.0, "total": 40.0, "next_cursor": null, "has_more": true } }, "banner")
	check(bool(g2.ok) and not bool(g2.mehr) and str(g2.weiter) == "", "„mehr“ ohne Cursor zählt als Ende (kein ewiges Weiterblättern)")
	check(not bool(I.galerie_lesen({ "items": [] }, "banner").ok) and not bool(I.galerie_lesen({ "items": "x", "page": {} }, "banner").ok),
			"ohne Seitenangabe oder mit falscher Liste: ungültig")
	check(not bool(I.galerie_lesen({ "items": [], "page": { "next_cursor": "x".repeat(600), "has_more": true } }, "banner").mehr),
			"überlanger Cursor wird nicht übernommen")
	var s := I.suche_lesen({ "query": "ape", "normalized_query": "ape", "results": [{ "parent_id": 46185.0, "name": "Ape Escape 3",
			"initial_release_year": 2005.0,
		"primary_platform": "PlayStation 2" }, { "parent_id": "x", "name": "kaputt" }, { "name": "ohne Nummer" }] })
	check(s.size() == 1 and int(s[0].id) == 46185 and int(s[0].jahr) == 2005, "Suche: nur Treffer mit Nummer und Name")

	print("JSON")
	check(I.json_lesen("{\"a\": [1, 2".to_utf8_buffer()) == null and I.json_lesen(PackedByteArray()) == null
			and I.json_lesen("<html>".to_utf8_buffer()) == null,
			"kaputtes oder leeres JSON: nichts")
	var gross := PackedByteArray()
	gross.resize(I.ANTWORT_MAX + 1)
	gross.fill(0x20)
	check(I.json_lesen(gross) == null, "zu große Antwort wird nicht gelesen")
	check(I.json_lesen("{\"results\": []}".to_utf8_buffer()) is Dictionary, "gültiges JSON gelesen")


func _fehler() -> void:
	print("Fehler")
	var e401 := I.fehler_lesen(401, { "status": 401.0, "error": "Invalid API key", "error_code": "UNAUTHORIZED",
			"request_id": "681d0e3fa9cc4622a2fb3540114a4627" })
	check(str(e401.grund) == "zugang" and not bool(e401.nochmal) and str(e401.request_id) == "681d0e3fa9cc4622a2fb3540114a4627",
			"401: neuer Schlüssel nötig, nie wiederholen, request_id bleibt")
	check(str(I.fehler_lesen(422, { "status": 422.0, "error_code": "VALIDATION", "fields": [] }).grund) == "anfrage" and str(I.fehler_lesen(400,
			{}).grund) == "anfrage",
			"422 und 400: Fehler in der Anfrage")
	var e429 := I.fehler_lesen(429, { "status": 429.0 }, PackedStringArray(["Content-Type: application/json", "Retry-After: 7", "X-Request-ID: abc-123"]))
	check(str(e429.grund) == "kontingent" and is_equal_approx(float(e429.warte_s), 7.0) and str(e429.request_id) == "abc-123",
			"429: Retry-After abwarten; request_id aus der Kopfzeile")
	check(is_equal_approx(I.retry_after(PackedStringArray(["retry-after: 99999"])), I.RETRY_MAX_S)
			and is_equal_approx(I.retry_after(PackedStringArray(["Retry-After: 0"])), I.RETRY_MIN_S)
			and is_equal_approx(I.retry_after(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:28:00 GMT"])),
					2.0) and is_equal_approx(I.retry_after(null), 2.0),
			"Retry-After begrenzt; Datum oder nichts: kurze Vorgabe")
	check(bool(I.fehler_lesen(503, null).nochmal) and str(I.fehler_lesen(500, null).grund) == "server" and str(I.fehler_lesen(0, null).grund) == "netz",
			"5xx: wenige Wiederholungen; keine Antwort: Netz")
	check(str(I.fehler_lesen(200, null).grund) == "form" and str(I.fehler_lesen(200, {}).grund) == "", "200 ohne JSON ist kein Ergebnis")
	check(str(I.fehler_lesen(401, { "request_id": "böse\nzeile" }).request_id) == "", "request_id mit fremden Zeichen kommt nicht ins Protokoll")
	check(I.merkbar("") and I.merkbar("fehlt") and not I.merkbar("netz") and not I.merkbar("kontingent") and not I.merkbar("server") and not I.merkbar("form"),
			"Netzfehler, 429 und Serverfehler sind nie ein Ergebnis")
	check(I.klar("ok\u0007\ntext", 40) == "ok  text" and I.klar(12, 40) == "" and I.klar("x".repeat(100), 10).length() == 10,
			"fremder Text fürs Protokoll: gekürzt, ohne Steuerzeichen")


func _klang() -> void:
	print("Klang")
	var gut := I.asset_lesen(_asset(70, "soundbite", { "url": "https://assets.iisu.network/s/70.ogg", "mime_type": "audio/ogg", "duration_ms": 7000.0,
			"file_size_bytes": 90000.0 }))
	check(I.klang_grund(gut) == "" and I.klang_endung(gut) == "ogg", "Klang mit 7 s: geht")
	var lang := I.asset_lesen(_asset(71, "soundbite", { "mime_type": "audio/mpeg", "duration_ms": 95000.0 }))
	var gross := I.asset_lesen(_asset(72, "soundbite", { "mime_type": "audio/mpeg", "file_size_bytes": 50000000.0 }))
	var fremd := I.asset_lesen(_asset(73, "soundbite", { "url": "https://assets.iisu.network/s/73.xyz", "mime_type": "application/x-unbekannt" }))
	check(I.klang_grund(lang) == "lang" and I.klang_grund(gross) == "gross" and I.klang_grund(fremd) == "format",
			"zu lang, zu groß, unbekanntes Format: nicht laden")
	check(I.klang_grund(I.asset_lesen(_asset(74, "boxart"))) == "art", "ein Bild ist kein Klang")
	var ohne := I.asset_lesen(_asset(75, "soundbite", { "url": "https://assets.iisu.network/s/75.mp3" }))
	check(I.klang_grund(ohne) == "" and I.klang_endung(ohne) == "mp3", "ohne Angaben: Endung aus der Adresse, die Größe begrenzt dann das Laden")
	check(int(I.klang_wahl([lang, gross, gut, ohne]).id) == 70 and I.klang_wahl([lang, fremd]).is_empty() and I.klang_wahl(null).is_empty(),
			"der erste taugliche Klang gewinnt")
	check(I.klang_endung(I.asset_lesen(_asset(76, "soundbite", { "mime_type": "audio/opus" }))) == "opus" and not "opus" in I.KLANG_NATIV,
			"Opus: nur über FFmpeg")
	check(I.datei_name(gut, "klang", "ogg") == "iidb_70_%s_klang.ogg" % "r70".md5_text().substr(0, 10) and I.datei_anfang(gut) == "iidb_70_",
			"Dateiname nur aus Nummer und Prüfsumme der Revision")
	var boese := I.asset_lesen(_asset(77, "boxart", { "revision": "../../autostart.bat" }))
	check(not I.datei_name(boese, "cover", "png").contains("..") and not I.datei_name(boese, "cover", "png").contains("/"),
			"eine Revision mit Pfadzeichen kommt nie in den Dateinamen")
	check(I.bild_endung(I.asset_lesen(_asset(78, "boxart", { "mime_type": "image/webp" }))) == "webp" and I.bild_endung(I.asset_lesen(_asset(79,
			"boxart", { "url": "https://assets.iisu.network/x.exe" }))) == "png",
			"Bildendung aus dem Typ, sonst png")
	check(I.klang_strom("res://icon.svg") == null and I.klang_strom("res://gibt/es/nicht.ogg") == null, "kein Klang in der Datei: nichts abspielen")
	var wav := _wav(0.5)
	var p := OS.get_user_data_dir().path_join("iidb_test.wav")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(wav)
	f.close()
	var strom := I.klang_strom(p)
	check(strom is AudioStreamWAV and (strom as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD and strom.get_length() > 0.4,
			"WAV aus dem Cache: als Schleife geladen")
	DirAccess.remove_absolute(p)
	# Seitenkopf von OGG: 27 Bytes, Byte 26 zählt die Einträge der Segmenttabelle, danach das erste Paket.
	var opus := "OggS".to_ascii_buffer()
	opus.resize(28)
	opus[26] = 1
	opus.append_array("OpusHead".to_ascii_buffer())
	opus.resize(96)
	var vorbis := "OggS".to_ascii_buffer()
	vorbis.resize(28)
	vorbis[26] = 1
	vorbis.append(1)
	vorbis.append_array("vorbis".to_ascii_buffer())
	vorbis.resize(96)
	check(I.klang_nativ(wav) and I.klang_nativ(vorbis) and not I.klang_nativ(opus) and not I.klang_nativ("ftypM4A ".to_ascii_buffer()),
			"Godot spielt WAV und OGG Vorbis selbst; Opus im OGG-Behälter und anderes gehen über FFmpeg")
	check(I.klang_art(wav) == "wav" and I.klang_art(vorbis) == "ogg" and I.klang_art(opus) == "opus", "Tonformat am Anfang der Daten erkannt")
	var arten := { "mp3": [0xFF, 0xFB, 0x90, 0x64], "aac": [0xFF, 0xF1, 0x50, 0x80], "flac": [0x66, 0x4C, 0x61, 0x43], "webm": [0x1A, 0x45, 0xDF, 0xA3],
		"m4a": [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20] }
	for art: String in arten:
		var daten := PackedByteArray(arten[art])
		daten.resize(96)
		check(I.klang_art(daten) == art and I.klang_nativ(daten) == (art == "mp3") and I.KLANG_WANDELBAR.has(art) == (art != "mp3"),
				"%s erkannt (AAC ist kein MP3, auch wenn beide mit FF beginnen)" % art)
	# Eine Wiedergabeliste, die sich als Klang ausgibt: FFmpeg bekäme sie nie (es öffnete sonst, was darin steht).
	var liste := "#EXTM3U\n#EXTINF:10,\nfile:///C:/Users/x/geheim.txt\n".to_utf8_buffer()
	liste.resize(200)
	var lp := OS.get_user_data_dir().path_join("iidb_test.opus")
	f = FileAccess.open(lp, FileAccess.WRITE)
	f.store_buffer(liste)
	f.close()
	check(I.klang_art(liste) == "" and not I.klang_umwandeln(OS.get_executable_path(), lp, lp + ".ogg") and not FileAccess.file_exists(lp + ".ogg"),
			"unbekannte Daten: kein Klang, und FFmpeg wird dafür gar nicht erst gerufen")
	DirAccess.remove_absolute(lp)
	check(I.download_ist_antwort(HTTPRequest.RESULT_SUCCESS, 404) and I.download_ist_antwort(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, 200)
			and not I.download_ist_antwort(HTTPRequest.RESULT_TIMEOUT, 0) and not I.download_ist_antwort(HTTPRequest.RESULT_SUCCESS, 503)
			and not I.download_ist_antwort(HTTPRequest.RESULT_SUCCESS, 429) and not I.download_ist_antwort(-1, 0),
			"Download: 404 und „zu groß“ sind eine Antwort; kein Netz, Zeitlimit, 429 und 5xx nicht")


## Kleine WAV-Datei (Stille, 8 kHz, 16 Bit, mono).
func _wav(sek: float) -> PackedByteArray:
	var n := int(8000.0 * sek) * 2
	var b := StreamPeerBuffer.new()
	b.put_data("RIFF".to_ascii_buffer())
	b.put_u32(36 + n)
	b.put_data("WAVEfmt ".to_ascii_buffer())
	b.put_u32(16)
	b.put_u16(1)
	b.put_u16(1)
	b.put_u32(8000)
	b.put_u32(16000)
	b.put_u16(2)
	b.put_u16(16)
	b.put_data("data".to_ascii_buffer())
	b.put_u32(n)
	var leer := PackedByteArray()
	leer.resize(n)
	b.put_data(leer)
	return b.data_array


func _merken() -> void:
	print("Merken je Spiel")
	var jetzt := 1800000000
	check(I.soll_suchen({}, jetzt) and not I.soll_suchen({ "iidb": { "id": 5.0, "name": "x", "t": 1.0 } }, jetzt),
			"neues Spiel: fragen; zugeordnet: nicht mehr")
	check(not I.soll_suchen({ "iidb": { "wahl": float(jetzt - 86400 * 90) } }, jetzt) and I.soll_suchen({ "iidb": { "wahl": float(jetzt) } }, jetzt, true),
			"offene Wahl: nicht von selbst neu fragen, nur bei „Alles ersetzen“")
	check(not I.soll_suchen({ "iidb": { "fehlt": float(jetzt - 86400 * 3) } }, jetzt)
			and I.soll_suchen({ "iidb": { "fehlt": float(jetzt - 86400 * 15) } }, jetzt),
			"nicht gefunden: nach zwei Wochen neu fragen")
	var m := I.merken({}, { "status": "matched", "id": 46185, "name": "Ape Escape 3" }, jetzt)
	check(m == { "id": 46185, "name": "Ape Escape 3", "t": jetzt }, "Treffer: Nummer und Name gemerkt")
	check(I.merken(m, { "status": "needs_choice" }, jetzt) == { "wahl": jetzt } and I.merken({}, { "status": "not_found" }, jetzt) == { "fehlt": jetzt },
			"Wahl und „nicht gefunden“ getrennt gemerkt")
	check(I.merken(m, { "status": "fehler" }, jetzt) == m, "kein Ergebnis: das Gemerkte bleibt")
	var mit := m.duplicate()
	mit["klang"] = { "id": 70, "datei": "iidb_70_abc_klang.ogg", "t": jetzt }
	check(I.merken(mit, { "status": "matched", "id": 46185, "name": "" }, jetzt + 5).get("klang") == mit.klang and str(I.merken(mit,
			{ "status": "matched", "id": 46185, "name": "" }, jetzt).name) == "Ape Escape 3",
			"dasselbe Spiel: Klang und Name bleiben")
	check(not I.merken(mit, { "status": "matched", "id": 999, "name": "Anderes" }, jetzt).has("klang"), "anderes Spiel: der alte Klang gilt nicht mehr")
	check(I.gemerkt({ "iidb": "kaputt" }).is_empty() and I.gemerkt({ "iidb": { "id": -4.0 } }).is_empty()
			and I.parent_id({ "iidb": { "id": 1e12 } }) == 0, "kaputter Eintrag aus der Datei: wie leer")
	check(not I.gemerkt({ "iidb": { "id": 5.0, "klang": { "id": 1.0, "datei": "../../boese.ogg", "t": 1.0 } } }).has("klang"),
			"gemerkter Dateiname mit Pfadzeichen wird verworfen")
	# Selbst gewählter Klang (Bildwahl, Reiter „Klang“): bleibt als eigen gemerkt, auch nach neuer Zuordnung zum selben Spiel.
	var eigen := { "iidb": { "id": 5.0, "klang": { "id": 7.0, "datei": "klang_7.ogg", "t": 1.0, "eigen": true } } }
	check(bool((I.gemerkt(eigen).klang as Dictionary).get("eigen", false))
			and not (I.gemerkt({ "iidb": { "id": 5.0, "klang": { "id": 7.0, "datei": "klang_7.ogg", "t": 1.0, "eigen": "ja" } } }).klang as Dictionary).has("eigen"),
			"selbst gewählter Klang bleibt gemerkt (nur echtes true)")
	check(bool((I.merken(I.gemerkt(eigen), { "status": "matched", "id": 5, "name": "X" }, jetzt).klang as Dictionary).get("eigen", false)),
			"neu zugeordnet, dasselbe Spiel: der gewählte Klang bleibt")


func _dienst() -> void:
	print("Dienst: Regeln im Ablauf")
	var d: Node = Media.iidb
	var alt_key: Variant = Config.get_value(I.KEY_PATH, "")
	Config.set_value(I.KEY_PATH, KEY)
	var gesendet: Array = []
	var box := { "antworten": [] }      # im Wörterbuch, damit die Funktion unten die neue Liste sieht
	d.test = func(a: Dictionary) -> Dictionary:
		gesendet.append(a)
		return (box.antworten as Array).pop_front() if not (box.antworten as Array).is_empty() else { "code": 0, "data": null, "headers": PackedStringArray() }
	d.zugang = { "ok": true, "rps": 5 }

	box.antworten = [{ "code": 429, "data": { "status": 429.0 }, "headers": PackedStringArray(["Retry-After: 3"]) }, { "code": 200,
			"data": { "results": [] }, "headers": PackedStringArray() }]
	var r: Dictionary = await d.fragen(I.anfrage_suche("x"))
	check(bool(r.ok) and gesendet.size() == 2, "429: nach der Wartezeit dieselbe Anfrage noch einmal")
	gesendet.clear()
	box.antworten = [{ "code": 503, "data": null, "headers": PackedStringArray() }, { "code": 502, "data": null, "headers": PackedStringArray() },
			{ "code": 500, "data": null, "headers": PackedStringArray() },
		{ "code": 200, "data": {}, "headers": PackedStringArray() }]
	r = await d.fragen(I.anfrage_suche("x"))
	check(not bool(r.ok) and str(r.grund) == "server" and gesendet.size() == 1 + I.SERVER_VERSUCHE, "5xx: wenige Wiederholungen, dann Schluss")
	gesendet.clear()
	box.antworten = [{ "code": 422, "data": { "status": 422.0, "error_code": "VALIDATION", "request_id": "r422" }, "headers": PackedStringArray() }]
	r = await d.fragen(I.anfrage_suche("x"))
	check(not bool(r.ok) and str(r.grund) == "anfrage" and gesendet.size() == 1 and str(r.request_id) == "r422", "422: nicht wiederholen, request_id zurück")

	# Zuordnen: Reihenfolge, Wahl, nicht gefunden – und 429 wird nie gemerkt.
	var spiele: Array = []
	for i in 3:
		spiele.append({ "id": "test:iidb%d" % i, "title": "Spiel %d" % i, "system": "gba", "source": "rom" })
	gesendet.clear()
	box.antworten = [{ "code": 200, "headers": PackedStringArray(), "data": { "results": [
		_treffer(100, "Spiel 0", { "boxart": [_asset(1000, "boxart")], "background": [_asset(1001, "banner")], "logo": [], "icon": [] }),
		{ "match": { "status": "needs_choice", "parent": null }, "artwork_status": "not_resolved", "artwork": {}, "candidates": [{ "id": 7.0,
				"name": "Spiel 1" }, { "id": 8.0, "name": "Spiel 1 II" }] },
		{ "match": { "status": "not_found", "parent": null }, "artwork_status": "not_resolved", "artwork": {} }] } }]
	var grund: String = await d.zuordnen(spiele)
	check(grund == "" and gesendet.size() == 1 and str(gesendet[0].pfad) == "/resolve/batch" and (gesendet[0].koerper.lookups as Array).size() == 3,
			"drei Spiele: eine Sammelanfrage")
	check(I.parent_id(spiele[0]) == 100 and I.gemerkt(spiele[1]).has("wahl") and I.gemerkt(spiele[2]).has("fehlt"),
			"Treffer, offene Wahl und „nicht gefunden“ je Spiel gemerkt")
	var info := {}
	var b: Dictionary = await d.bilder_von(spiele[0], info)
	check(int(b.boxart[0].id) == 1000 and int(b.background[0].id) == 1001 and gesendet.size() == 1,
			"Bilder des ersten Spiels aus der Sammelantwort, ohne neue Anfrage")
	info = {}
	check((await d.bilder_von(spiele[1], info) as Dictionary).is_empty() and str(info.grund) == "wahl" and gesendet.size() == 1,
			"offene Wahl: kein Bild, Grund „wahl“, keine neue Anfrage")
	info = { "neu": true }
	check((await d.bilder_von(spiele[2], info) as Dictionary).is_empty() and str(info.grund) == "fehlt" and gesendet.size() == 1,
			"„Alles ersetzen“ gleich nach dem Zuordnen: dasselbe Spiel wird nicht je Bildart noch einmal gefragt")

	var neu := { "id": "test:iidb9", "title": "Neues Spiel", "system": "gba", "source": "rom" }
	gesendet.clear()
	box.antworten = [{ "code": 429, "data": {}, "headers": PackedStringArray(["Retry-After: 100"]) }, { "code": 429, "data": {},
			"headers": PackedStringArray(["Retry-After: 100"]) }]
	grund = await d.zuordnen([neu])
	check(grund == "kontingent" and not neu.has("iidb"), "429: nichts gemerkt (die Anfrage kam nicht an)")
	check(gesendet.size() == 2, "429 mit langer Wartezeit: einmal gewartet, dann aufgegeben (nie länger als die Grenze)")
	info = {}
	gesendet.clear()
	check((await d.bilder_von(neu, info) as Dictionary).is_empty() and str(info.grund) == "kontingent" and gesendet.is_empty(),
			"danach eine Weile keine Anfragen von selbst")
	d.pause_aus()

	gesendet.clear()
	box.antworten = [{ "code": 200, "headers": PackedStringArray(), "data": { "results": [_treffer(1, "A"), _treffer(2, "B")] } }]
	grund = await d.zuordnen([neu])
	check(grund == "form" and not neu.has("iidb"), "Antwort mit anderer Zeilenzahl: nichts übernommen")
	d.pause_aus()

	# Screenshots der Spielseite: nur für zugeordnete Spiele, eine Anfrage je Sitzung.
	gesendet.clear()
	box.antworten = [{ "code": 200, "headers": PackedStringArray(), "data": { "artwork": { "screenshot": [_asset(501, "screenshot"), _asset(502,
			"screenshot", { "is_animated": true })] } } }]
	var shots: Array = await d.screenshots(spiele[0])
	var nochmal: Array = await d.screenshots(spiele[0])
	check(shots.size() == 1 and str(shots[0]).ends_with("/501.png") and nochmal == shots and gesendet.size() == 1
			and str(gesendet[0].pfad) == "/assets/parents/100",
			"Screenshots: stehende Bilder des zugeordneten Spiels, beim zweiten Mal ohne Anfrage")
	check((await d.screenshots(spiele[2]) as Array).is_empty() and gesendet.size() == 1, "Screenshots ohne Zuordnung: keine Anfrage")

	# Klang: Was im Cache liegt, spielt sofort – auch wenn iiDB beim Auffrischen nicht antwortet.
	var kdir := Config.path(d.KLANG_DIR)
	DirAccess.make_dir_recursive_absolute(kdir)
	var kf := FileAccess.open(kdir.path_join("iidb_70_test_klang.wav"), FileAccess.WRITE)
	kf.store_buffer(_wav(0.5))
	kf.close()
	var mit_klang: Dictionary = (spiele[0] as Dictionary).duplicate(true)
	mit_klang["iidb"] = { "id": 100, "name": "Spiel 0", "t": 1, "klang": { "id": 70, "datei": "iidb_70_test_klang.wav", "t": 1 } }
	gesendet.clear()
	box.antworten = []
	var kp: String = await d.klang_datei(mit_klang)
	check(kp.ends_with("iidb_70_test_klang.wav") and gesendet.is_empty(), "gemerkter Klang: sofort aus dem Cache, ohne auf iiDB zu warten")
	for i in 20:
		await get_tree().process_frame
	check(gesendet.size() == 1 and str(gesendet[0].pfad) == "/assets/parents/100" and FileAccess.file_exists(kp),
			"alter Klang: nebenher neu gefragt; kommt keine Antwort, bleibt er")
	gesendet.clear()
	check(str(await d.klang_datei(mit_klang)) == kp and gesendet.is_empty(), "iiDB antwortet gerade nicht: der Klang spielt trotzdem")
	var ohne_klang: Dictionary = (spiele[0] as Dictionary).duplicate(true)
	check(str(await d.klang_datei(ohne_klang)) == "" and gesendet.is_empty(), "ohne gemerkten Klang und ohne iiDB: keiner, keine Anfrage")
	d.pause_aus()
	DirAccess.remove_absolute(kp)

	# 401 sperrt, bis ein neuer Schlüssel kommt.
	var abgelehnt := [0]
	var merker := func() -> void: abgelehnt[0] += 1
	d.abgelehnt.connect(merker)
	gesendet.clear()
	box.antworten = [{ "code": 401, "data": { "status": 401.0, "error_code": "UNAUTHORIZED", "request_id": "r401" }, "headers": PackedStringArray() }]
	r = await d.fragen(I.anfrage_suche("x"))
	var r2: Dictionary = await d.fragen(I.anfrage_suche("y"))
	check(not bool(r.ok) and str(r.grund) == "zugang" and str(r2.grund) == "zugang" and gesendet.size() == 1 and abgelehnt[0] == 1,
			"401: einmal gefragt, nie wiederholt, danach gesperrt")
	Config.set_value(I.KEY_PATH, KEY + "neu")
	box.antworten = [{ "code": 200, "data": { "results": [] }, "headers": PackedStringArray() }]
	r = await d.fragen(I.anfrage_suche("x"))
	check(bool(r.ok), "neuer Schlüssel: wieder frei")
	d.abgelehnt.disconnect(merker)

	# Schlüssel prüfen: nur ein geprüfter landet in den Einstellungen.
	Config.set_value(I.KEY_PATH, "")
	box.antworten = [{ "code": 401, "data": { "status": 401.0 }, "headers": PackedStringArray() }]
	var p: Dictionary = await d.pruefen_und_speichern(KEY)
	check(not bool(p.ok) and str(Config.get_value(I.KEY_PATH, "")) == "", "abgelehnter Schlüssel wird nicht gespeichert")
	box.antworten = [{ "code": 200, "headers": PackedStringArray(), "data": { "user_id": 1.0, "username": "u", "email": "e@example.org", "user_type": "user",
		"tier": { "code": "free", "api_tier": 0.0, "requests_per_second": 2.0 }, "api_key": {} } }]
	p = await d.pruefen_und_speichern(" " + KEY + " ")
	check(bool(p.ok) and str(Config.get_value(I.KEY_PATH, "")) == KEY and int(d.zugang.rps) == 2 and not JSON.stringify(d.zugang).contains("example.org"),
			"geprüfter Schlüssel gespeichert, Stufe gemerkt, keine E-Mail-Adresse")
	gesendet.clear()
	p = await d.pruefen_und_speichern("zeile1\r\nzeile2-lang-genug")
	check(not bool(p.ok) and gesendet.is_empty(), "Schlüssel mit Zeilenumbruch geht gar nicht erst raus")

	d.test = Callable()
	d.zugang = {}
	Config.set_value(I.KEY_PATH, alt_key)


func _quelltext() -> void:
	print("Regeln im Quelltext")
	var kern := Quelle.lesen("res://src/core/iidb.gd")
	var dienst := Quelle.lesen("res://src/core/iidb_dienst.gd")
	for verboten in ["str_to_var", "bytes_to_var", "Expression.new", "ResourceLoader"]:
		check(not kern.contains(verboten) and not dienst.contains(verboten), "kein %s auf fremden Daten" % verboten)
	check(RegEx.create_from_string("(?<![a-z_])load\\(").search(kern + dienst) == null, "kein load() auf fremden Daten")
	check(dienst.contains("ANFRAGE_S, \"api\", Iidb.ANTWORT_MAX, false)"), "Anfragen mit Schlüssel folgen keiner Weiterleitung und sind in der Größe begrenzt")
	check(dienst.count("Iidb.kopf(") == 1 and not dienst.contains("log_line(\"iidb\", key") and not kern.contains("log_line"),
			"der Schlüssel steht an genau einer Stelle (Kopfzeile), nie im Protokoll")
	check(dienst.contains("Net.request(str(a.url), PackedStringArray()") and dienst.contains("Net.download(str(a.url)"),
			"Bilder und Klänge laden ohne Kopfzeilen")
	var lang := RegEx.create_from_string("\"[A-Za-z0-9_\\-]{32,}\"").search_all(kern + dienst)
	check(lang.all(func(m: RegExMatch) -> bool: return m.get_string().begins_with("\"abcdefghijklmnopqrstuvwxyz0123456789")),
			"kein Schlüssel im Code mitgeliefert")
	check(I.KONTO_SEITE == "https://accounts.iisu.network/", "der QR-Code der Anmeldung öffnet nur die Kontoseite von iiSU")
	check("accounts.iidb_key" in preload("res://src/core/vault.gd").SECRETS, "der Schlüssel liegt im Tresor")

extends Node
## iiDB im Netz (Regeln und Formen: src/core/iidb.gd, Überblick: docs/IIDB.md). Hängt an Media
## (Media.iidb). Eine Anfrage nach der anderen, im Takt der Stufe des Nutzers; 429 wartet Retry-After
## ab, 5xx wird wenige Male wiederholt, 401 sperrt, bis ein neuer Schlüssel kommt. Der Schlüssel geht
## nur an die Schnittstelle (ohne Weiterleitungen), Bilder und Klänge lädt Uzai ohne ihn.

const Iidb := preload("res://src/core/iidb.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const Regal := preload("res://src/library/regal.gd")
const Screenscraper := preload("res://src/core/screenscraper.gd")
const Sicher := preload("res://src/core/sicher.gd")

## Slots beim automatischen Zuordnen (Cover, Hintergrund, Schriftzug, Symbol).
const AUTO_SLOTS := ["boxart", "background", "logo", "icon"]
const SAMMEL_S := 0.25               ## so lange sammelt Uzai einzelne Spiele zu einer Sammelanfrage
const ANFRAGE_S := 20.0              ## Zeitlimit einer Anfrage
const NOCHMAL_MS := 10 * 60 * 1000   ## ein Spiel ohne Treffer fragt Uzai so lange nicht von selbst noch einmal
const PAUSE_MS := 60 * 1000          ## nach Netz- oder Serverfehlern so lange nicht von selbst fragen
const PAUSE_LIMIT_MS := 5 * 60 * 1000  ## nach „Limit erreicht“
const SHOTS_WARTE_MS := 2500         ## so lange wartet die Spielseite höchstens auf Screenshots von iiDB
const KLANG_DIR := "cache/klang"
const BILD_DIR := "cache/img/iidb"

## Abruf bei iiDB: ruht, fragt (höchstens ANFRAGE_S), wartet nach 429 oder 5xx (höchstens
## Iidb.RETRY_MAX_S) oder ist gesperrt, bis ein neuer Schlüssel kommt (401).
const ZUSTAENDE := { "ruht": ["fragt"], "fragt": ["ruht", "wartet", "gesperrt"], "wartet": ["fragt"], "gesperrt": ["ruht"] }
var _zustand := "ruht":
	set(neu):
		Zustand.wechsel("bilder.iidb", ZUSTAENDE, _zustand, neu)
		_zustand = neu

## iiDB hat den Schlüssel abgelehnt (401): Die Oberfläche bittet um einen neuen.
signal abgelehnt
signal _frei
signal _gesammelt(runde: int, grund: String)

var test := Callable()       ## nur für Tests: Anfrage (Iidb.anfrage_*) → { code, data, headers } statt Netz
var zugang := {}             ## Stufe des Nutzers (Iidb.zugang_lesen), aus /me/access
var _dran := false
var _letzte_ms := -100000
var _bilder := {}            ## Spiel-ID → { Slot: [Assets] } (Sitzung, aus den Sammelanfragen)
var _spiel := {}             ## "parent_id:slots" → { Slot: [Assets] } (Sitzung: Klang, Screenshots)
var _sammel: Array = []      ## Spiele, die auf die nächste Sammelanfrage warten
var _runde := 0              ## Nummer der Sammelrunde, die gerade Spiele annimmt
var _md5 := {}               ## Pfad → Prüfsumme (Sitzung)
var _gefragt := {}           ## Spiel-ID → Zeitpunkt (ms): eben erst gefragt, nicht für jede Bildart nochmal
var _pause_grund := ""       ## iiDB antwortet gerade nicht (Limit, Netz): eine Weile nicht von selbst fragen
var _pause_bis := 0
var _klang_laeuft := {}      ## Spiel-ID → true, solange der Klang geholt wird


func _ready() -> void:
	# Neuer oder gelöschter Schlüssel (Anmeldeseite, Einstellungen, Abmelden): Gemerktes der Sitzung weg.
	Config.changed.connect(func(k: String) -> void:
		if k == Iidb.KEY_PATH:
			vergessen()
	)


func schluessel() -> String:
	return str(Config.get_value(Iidb.KEY_PATH, "")).strip_edges()


func verbunden() -> bool:
	return schluessel() != ""


## Eine Anfrage an iiDB. { ok, data, grund, request_id } – grund wie Iidb.fehler_lesen.
func fragen(a: Dictionary, wofuer := "") -> Dictionary:
	if a.is_empty():
		return { "ok": false, "data": null, "grund": "anfrage", "request_id": "" }
	while _dran:
		await _frei
	var key := schluessel()
	if key == "" or _zustand == "gesperrt":
		return { "ok": false, "data": null, "grund": "zugang", "request_id": "" }
	_dran = true
	var out := await _eine(a, key, wofuer)
	_dran = false
	_frei.emit()
	# Brach die Anfrage mit einem Fehler ab, ist das Ergebnis leer: Die Aufrufer brauchen trotzdem ihre Felder.
	return out if not out.is_empty() else { "ok": false, "data": null, "grund": "fehler", "request_id": "" }


func _eine(a: Dictionary, key: String, wofuer: String) -> Dictionary:
	var versuch := 0
	var gewartet := 0.0
	while true:
		var rest := Iidb.takt_ms(int(zugang.get("rps", 1))) - (Time.get_ticks_msec() - _letzte_ms)
		if rest > 0 and not test.is_valid():
			await get_tree().create_timer(rest / 1000.0).timeout
		_zustand = "fragt"
		var r: Dictionary = await _senden(a, key)
		_letzte_ms = Time.get_ticks_msec()
		var f := Iidb.fehler_lesen(int(r.get("code", 0)), r.get("data"), r.get("headers"))
		var grund := str(f.grund)
		if grund == "":
			_zustand = "ruht"
			return { "ok": true, "data": r.data, "grund": "", "request_id": f.request_id }
		_protokoll(a, int(r.get("code", 0)), grund, str(f.request_id), r.get("data"), wofuer)
		if grund == "zugang":
			_zustand = "gesperrt"
			abgelehnt.emit()
			return { "ok": false, "data": null, "grund": grund, "request_id": f.request_id }
		var pause := 0.0
		if grund == "kontingent" and versuch < 2 and gewartet + float(f.warte_s) <= Iidb.RETRY_MAX_S:
			pause = float(f.warte_s)
		elif grund == "server" and versuch < Iidb.SERVER_VERSUCHE:
			pause = 1.5 * float(versuch + 1)
		if pause <= 0.0:
			_zustand = "ruht"
			return { "ok": false, "data": null, "grund": grund, "request_id": f.request_id }
		_zustand = "wartet"
		versuch += 1
		gewartet += pause
		if not test.is_valid():
			await get_tree().create_timer(pause).timeout
	return {}


## { code, data, headers }. Ohne Weiterleitungen: Der Schlüssel landet nie bei einem anderen Rechner.
func _senden(a: Dictionary, key: String) -> Dictionary:
	if test.is_valid():
		return await test.call(a)
	var h := Iidb.kopf(key)
	var body := ""
	if a.get("koerper") != null:
		h.append("Content-Type: application/json")
		body = JSON.stringify(a.koerper)
	var methode := HTTPClient.METHOD_POST if str(a.get("methode", "GET")) == "POST" else HTTPClient.METHOD_GET
	var r: Dictionary = await Net.request(Iidb.adresse(a), h, methode, body, ANFRAGE_S, "api", Iidb.ANTWORT_MAX, false)
	var bytes: PackedByteArray = r.body
	var data: Variant = null
	if bytes.size() < Net.JSON_OFF_BYTES:
		data = Iidb.json_lesen(bytes)
	else:
		data = await Arbeit.ergebnis(Iidb.json_lesen.bind(bytes))
	return { "code": int(r.code), "data": data, "headers": r.headers }


## Ins Protokoll (logs/iidb.log): Weg, Status, Grund und die request_id für Rückfragen bei iiDB.
## Nie der Schlüssel, nie Kopfzeilen der Anfrage.
func _protokoll(a: Dictionary, code: int, grund: String, rid: String, data: Variant, wofuer: String) -> void:
	var mehr := ""
	if data is Dictionary:
		mehr = " " + Iidb.klar(data.get("error_code"), 40)
		if (data as Dictionary).get("fields") is Array and not (data.fields as Array).is_empty() and data.fields[0] is Dictionary:
			mehr += " (%s)" % Iidb.klar(data.fields[0].get("msg"), 120)
	Media.log_line("iidb", "%s %s → HTTP %d %s%s · request_id %s%s" % [str(a.get("methode", "")), str(a.get("pfad", "")), code, grund,
			mehr, rid if rid != "" else "–", (" · " + wofuer.left(60)) if wofuer != "" else ""])


## Schlüssel prüfen (GET /me/access, zählt bei iiDB nicht mit) und nur dann speichern.
## { ok, error, zugang } – ein falscher Schlüssel landet nie in den Einstellungen.
func pruefen_und_speichern(key: String) -> Dictionary:
	var k := key.strip_edges()
	var fe := Iidb.schluessel_fehler(k)
	if fe != "":
		return { "ok": false, "error": fe }
	var r: Dictionary = await _senden(Iidb.anfrage_zugang(), k)
	var f := Iidb.fehler_lesen(int(r.get("code", 0)), r.get("data"), r.get("headers"))
	if str(f.grund) in ["zugang", "verboten"]:
		return { "ok": false, "error": "iiDB kennt diesen Schlüssel nicht. Auf accounts.iisu.network ganz kopieren und nochmal senden." }
	var z := Iidb.zugang_lesen(r.get("data")) if str(f.grund) == "" else { "ok": false }
	if not bool(z.ok):
		_protokoll(Iidb.anfrage_zugang(), int(r.get("code", 0)), str(f.grund) if str(f.grund) != "" else "form", str(f.request_id), null, "")
		if str(f.grund) == "netz":
			return { "ok": false, "error": "iiDB ist gerade nicht erreichbar. Ist der PC online? Gleich nochmal versuchen." }
		return { "ok": false, "error": "iiDB hat gerade nicht geantwortet. Gleich nochmal versuchen." }
	Config.set_value(Iidb.KEY_PATH, k)
	Config.save_settings()
	zugang = z
	_entsperren()
	return { "ok": true, "error": "", "zugang": z }


## Stufe auffrischen (für den Takt und die Anzeige unter Konten). {} wenn es nicht ging.
func zugang_holen() -> Dictionary:
	_entsperren()
	var r := await fragen(Iidb.anfrage_zugang())
	if not bool(r.ok):
		return {}
	var z := Iidb.zugang_lesen(r.data)
	if bool(z.ok):
		zugang = z
		return z
	return {}


## Abmelden: Schlüssel vergessen (die Einstellungen leeren ihn selbst), alles Gemerkte der Sitzung auch.
func vergessen() -> void:
	zugang = {}
	_bilder.clear()
	_spiel.clear()
	_gefragt.clear()
	_entsperren()


func _entsperren() -> void:
	pause_aus()
	if _zustand == "gesperrt":
		_zustand = "ruht"


## Nach einer Störung fragt Uzai eine Weile nicht von selbst (Kacheln, Spielseite): sonst stünde bei
## jedem Bild wieder eine Anfrage an. „Spiele scrapen“ und die Bildwahl fragen trotzdem (pause_aus).
func _pause(grund: String) -> void:
	if grund in ["", "anfrage"]:
		return
	_pause_grund = grund
	_pause_bis = Time.get_ticks_msec() + (PAUSE_LIMIT_MS if grund == "kontingent" else PAUSE_MS)


func pause_aus() -> void:
	_pause_grund = ""
	_pause_bis = 0


func _pausiert() -> String:
	return _pause_grund if _pause_grund != "" and Time.get_ticks_msec() < _pause_bis else ""


# --- Zuordnen und Bilder -----------------------------------------------------------------------

## Spiele bei iiDB zuordnen und ihre empfohlenen Bilder holen: Sammelanfragen mit bis zu 25 Spielen.
## Bekannte Spiele (parent_id gemerkt) über /assets/batch, alle anderen über /resolve/batch – erst
## mit Titel und der Kennung, die Uzai schon hat, danach für die übrigen kleinen Dateien mit der
## Prüfsumme. Das Ergebnis steht danach je Spiel in der Sitzung (bilder_von) und im Eintrag (Feld
## „iidb“). neu: „nicht gefunden“ trotzdem neu fragen. stop: Callable → true bricht ab.
## Ergebnis: "" oder der Grund, warum iiDB gerade nicht antwortet (dann ist nichts gemerkt).
func zuordnen(games: Array, slots: Array = AUTO_SLOTS, neu := false, stop := Callable()) -> String:
	if not verbunden():
		return "zugang"
	if zugang.is_empty() and not test.is_valid():
		await zugang_holen()
	var jetzt := int(Time.get_unix_time_from_system())
	var bekannt: Array = []
	var suchen: Array = []
	for g in games:
		var gid := str(g.get("id", ""))
		if gid == "" or (not neu and _hat_slots(gid, slots)):
			continue
		if Iidb.parent_id(g) > 0:
			bekannt.append(g)
		elif Iidb.soll_suchen(g, jetzt, neu):
			suchen.append(g)
	var offen: Array = []
	var grund := await _in_gruppen(suchen, slots, "suche", stop, func(g: Dictionary) -> Dictionary:
		return Iidb.zeile_aufloesen(g, Iidb.kennung_fuer(g, Library.serial_of(g)), slots, Regal.region_von(g))
	, offen)
	if grund != "":
		_pause(grund)
		return grund
	# Zweiter Anlauf über die Prüfsumme der Datei – nur, wo Titel und Kennung nicht reichten.
	var mit_summe: Array = []
	var summen := {}
	for g in offen:
		var md5 := await _md5_von(g)
		if md5 != "":
			summen[str(g.id)] = md5
			mit_summe.append(g)
		if stop.is_valid() and stop.call():
			return ""
	grund = await _in_gruppen(mit_summe, slots, "summe", stop, func(g: Dictionary) -> Dictionary:
		return Iidb.zeile_aufloesen(g, { "kind": "md5", "value": summen[str(g.id)] }, slots, Regal.region_von(g))
	, [])
	if grund != "":
		_pause(grund)
		return grund
	grund = await _in_gruppen(bekannt, slots, "bekannt", stop, func(g: Dictionary) -> Dictionary:
		return Iidb.zeile_bilder(Iidb.parent_id(g), slots, Regal.region_von(g))
	, [])
	_pause(grund)
	return grund


func _hat_slots(gid: String, slots: Array) -> bool:
	if not _bilder.has(gid):
		return false
	for s in slots:
		if not (_bilder[gid] as Dictionary).has(s):
			return false
	return true


## games in Gruppen zu 25 fragen. art: "suche" (Titel und Kennung), "summe" (Prüfsumme: zählt nur
## bei einem Treffer, sonst bleibt das Ergebnis der Suche) oder "bekannt" (parent_id gemerkt).
## zeile: Spiel → Zeile der Anfrage ({} = auslassen). offen bekommt die Spiele ohne Treffer.
func _in_gruppen(games: Array, slots: Array, art: String, stop: Callable, zeile: Callable, offen: Array) -> String:
	var bilder := art == "bekannt"
	var i := 0
	while i < games.size():
		if stop.is_valid() and stop.call():
			return ""
		var gruppe: Array = []
		var zeilen: Array = []
		while i < games.size() and zeilen.size() < Iidb.BATCH_MAX:
			var z: Dictionary = zeile.call(games[i])
			if not z.is_empty():
				gruppe.append(games[i])
				zeilen.append(z)
			i += 1
		if zeilen.is_empty():
			continue
		var a := Iidb.anfrage_bilder(zeilen) if bilder else Iidb.anfrage_aufloesen(zeilen)
		var r := await fragen(a, "%d Spiele" % zeilen.size())
		if not bool(r.ok):
			return str(r.grund)
		var antworten := Iidb.batch_lesen(r.data, zeilen.size(), bilder)
		if antworten.is_empty():
			Media.log_line("iidb", "%s: Antwort passt nicht zur Anfrage (%d Zeilen erwartet) · request_id %s" % [str(a.pfad), zeilen.size(),
					str(r.request_id) if str(r.request_id) != "" else "–"])
			return "form"
		var jetzt := int(Time.get_unix_time_from_system())
		for k in gruppe.size():
			_gefragt[str(gruppe[k].get("id", ""))] = Time.get_ticks_msec()
			if art != "summe" or str(antworten[k].status) == "matched":
				_uebernehmen(gruppe[k], antworten[k], slots, jetzt, offen)
		Library.mark_dirty()
	return ""


func _uebernehmen(g: Dictionary, t: Dictionary, slots: Array, jetzt: int, offen: Array) -> void:
	var gid := str(g.get("id", ""))
	var status := str(t.get("status", ""))
	if status == "fehler":
		return
	if status == "matched":
		var b: Dictionary = (_bilder.get(gid, {}) as Dictionary).duplicate()
		for s in slots:
			b[s] = (t.bilder as Dictionary).get(s, [])
		_bilder[gid] = b
	else:
		offen.append(g)
	var eintrag := Iidb.merken(Iidb.gemerkt(g), t, jetzt)
	# Der Eintrag der Bibliothek zählt (g kann eine Kopie sein).
	for ziel in [g, Library.get_game(gid)]:
		if not (ziel as Dictionary).is_empty():
			ziel["iidb"] = eintrag


## Prüfsumme der Spieldatei, wenn sie klein genug ist (wie bei ScreenScraper), sonst "".
func _md5_von(g: Dictionary) -> String:
	if not str(g.get("source", "")) in ["rom", "disc"]:
		return ""
	var p := str(g.get("path", ""))
	if p == "" or not Sicher.local_path_ok(p) or not FileAccess.file_exists(p):
		return ""
	if _md5.has(p):
		return _md5[p]
	if not Screenscraper.md5_sinnvoll(p, FileAccess.get_size(p)):
		return ""
	var md5: String = await Media.md5_datei(p)
	_md5[p] = md5
	return md5


## Empfohlene Bilder eines Spiels: { Slot: [Assets] }. Einzelne Spiele (Kacheln, die gerade
## sichtbar werden) sammelt Uzai kurz und fragt sie zusammen. info.grund sagt, warum nichts kam.
func bilder_von(game: Dictionary, info: Dictionary = {}) -> Dictionary:
	var gid := str(game.get("id", ""))
	if not verbunden() or gid == "":
		info["grund"] = "zugang"
		return {}
	var neu := bool(info.get("neu", false))
	if not _hat_slots(gid, AUTO_SLOTS):
		if _pausiert() != "":
			info["grund"] = _pausiert()
			return {}
		var g := Iidb.gemerkt(game)
		var eben := _gefragt.has(gid) and Time.get_ticks_msec() - int(_gefragt[gid]) < NOCHMAL_MS
		if not g.has("id") and (eben or not Iidb.soll_suchen(game, int(Time.get_unix_time_from_system()), neu)):
			info["grund"] = "wahl" if g.has("wahl") else "fehlt"
			return {}
		if not _sammel.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == gid):
			_sammel.append(game)
		if _sammel.size() == 1:
			_sammeln.call_deferred()
		var meine := _runde
		while true:
			var fertig: Array = await _gesammelt
			if int(fertig[0]) != meine:
				continue
			if str(fertig[1]) != "":
				info["grund"] = str(fertig[1])
				return {}
			break
	if not _bilder.has(gid):
		info["grund"] = "wahl" if Iidb.gemerkt(Library.get_game(gid)).has("wahl") else "fehlt"
		return {}
	return _bilder[gid]


func _sammeln() -> void:
	if not test.is_valid():
		await get_tree().create_timer(SAMMEL_S).timeout
	var runde := _runde
	_runde += 1
	var gruppe := _sammel.duplicate()
	_sammel.clear()
	var grund := await zuordnen(gruppe, AUTO_SLOTS, true)
	if grund == "":
		# Auch ohne Zeile (kein Titel) oder mit Fehlerzeile gilt das Spiel als gefragt.
		for g in gruppe:
			_gefragt[str(g.get("id", ""))] = Time.get_ticks_msec()
	_gesammelt.emit(runde, grund)


## Ein Bild für eine Bildart laden (cover, hero, logo, icon): die empfohlenen der Reihe nach, bis
## eins kommt. Pfad oder "" (info.grund: "fehlt", "wahl", "zugang", "kontingent", "netz" …).
func bild(game: Dictionary, kind: String, info: Dictionary = {}) -> String:
	if not Iidb.SLOT_FUER.has(kind):
		info["grund"] = "fehlt"
		return ""
	var b := await bilder_von(game, info)
	var liste: Array = b.get(Iidb.SLOT_FUER[kind], []) if b.get(Iidb.SLOT_FUER[kind]) is Array else []
	if liste.is_empty():
		if not info.has("grund"):
			info["grund"] = "fehlt"
		return ""
	for a in liste:
		var got := await asset_laden(a, game, kind)
		if got != "":
			Media.note_url(game, got, str(a.url))
			return got
	info["grund"] = "netz"
	return ""


## Ein Asset als Bilddatei in den Cache (ohne Schlüssel). ordner: eigenes Ziel (Bildwahl: der
## Medienordner). "" wenn es nicht kam oder zu groß ist.
func asset_laden(a: Dictionary, game: Dictionary, kind: String, ordner := "") -> String:
	if int(a.get("bytes", -1)) > Net.IMG_MAX_BYTES or bool(a.get("animiert", false)):
		return ""
	var name := "%s_%s" % [str(game.get("id", "x")).md5_text().substr(0, 12), Iidb.datei_name(a, kind, Iidb.bild_endung(a))]
	if ordner != "":
		return await Net.download(str(a.url), ordner.path_join(Iidb.datei_anfang(a) + name))
	return await Net.download(str(a.url), Config.path(BILD_DIR).path_join(name))


# --- Bildwahl ----------------------------------------------------------------------------------

## Das Spiel bei iiDB für die Bildwahl: { status, id, name, kandidaten, grund }. Schon zugeordnet:
## ohne Anfrage. Sonst eine Suche nach Titel und Kennung (ohne Bilder).
func spiel_finden(game: Dictionary) -> Dictionary:
	var g := Iidb.gemerkt(game)
	if g.has("id"):
		return { "status": "matched", "id": int(g.id), "name": str(g.get("name", "")), "kandidaten": [], "grund": "" }
	var z := Iidb.zeile_aufloesen(game, Iidb.kennung_fuer(game, Library.serial_of(game)), [])
	if z.is_empty():
		return { "status": "not_found", "id": 0, "name": "", "kandidaten": [], "grund": "fehlt" }
	var r := await fragen(Iidb.anfrage_aufloesen([z]), str(game.get("title", "")))
	if not bool(r.ok):
		return { "status": "fehler", "id": 0, "name": "", "kandidaten": [], "grund": r.grund }
	var antworten := Iidb.batch_lesen(r.data, 1)
	if antworten.is_empty() or str(antworten[0].status) == "fehler":
		return { "status": "fehler", "id": 0, "name": "", "kandidaten": [], "grund": "form" }
	var t: Dictionary = antworten[0]
	_uebernehmen(game, t, [], int(Time.get_unix_time_from_system()), [])
	Library.mark_dirty()
	t["grund"] = ""
	return t


## Der Nutzer hat das Spiel gewählt („Welches Spiel?“, „Anderes Spiel“): merken, Altes der Sitzung weg.
func zuweisen(game: Dictionary, id: int, name: String) -> void:
	if not Iidb.id_ok(id):
		return
	var gid := str(game.get("id", ""))
	_bilder.erase(gid)
	_gefragt.erase(gid)
	var eintrag := { "id": id, "name": name.left(Iidb.TITEL_MAX), "t": int(Time.get_unix_time_from_system()) }
	game["iidb"] = eintrag
	if not Library.get_game(gid).is_empty():
		Library.set_field(gid, "iidb", eintrag)


## Eine Seite der Galerie einer Bildart. { ok, items, weiter, mehr, gesamt, grund }.
func galerie(parent_id: int, art: String, cursor := "") -> Dictionary:
	var r := await fragen(Iidb.anfrage_galerie(parent_id, art, cursor), art)
	if not bool(r.ok):
		return { "ok": false, "items": [], "weiter": "", "mehr": false, "gesamt": 0, "grund": r.grund }
	var g := Iidb.galerie_lesen(r.data, art)
	g["grund"] = "" if bool(g.ok) else "form"
	return g


## Spiele suchen („Anderes Spiel“). { ok, liste, grund }.
func suche(wort: String) -> Dictionary:
	var r := await fragen(Iidb.anfrage_suche(wort), wort)
	if not bool(r.ok):
		return { "ok": false, "liste": [], "grund": r.grund }
	return { "ok": true, "liste": Iidb.suche_lesen(r.data), "grund": "" }


## Bilder eines zugeordneten Spiels für bestimmte Slots (Klang, Screenshots), je Sitzung gemerkt.
## { ok, bilder: { Slot: [Assets] }, grund }.
func spiel_bilder(parent_id: int, slots: Array, je_slot := 1) -> Dictionary:
	var key := "%d:%s:%d" % [parent_id, ",".join(PackedStringArray(Iidb.slots_pruefen(slots))), je_slot]
	if _spiel.has(key):
		return { "ok": true, "bilder": _spiel[key], "grund": "" }
	if _pausiert() != "":
		return { "ok": false, "bilder": {}, "grund": _pausiert() }
	var r := await fragen(Iidb.anfrage_spiel(parent_id, slots, je_slot), "Spiel %d" % parent_id)
	if not bool(r.ok):
		_pause(str(r.grund))
		return { "ok": false, "bilder": {}, "grund": r.grund }
	_spiel[key] = Iidb.spiel_lesen(r.data)
	return { "ok": true, "bilder": _spiel[key], "grund": "" }


## Adressen der Screenshots eines Spiels (Spielseite), höchstens sechs. Nur für zugeordnete Spiele.
## Die Spielseite wartet darauf höchstens SHOTS_WARTE_MS: Antwortet iiDB langsam, kommen die Bilder
## der anderen Quellen sofort, und die von iiDB stehen beim nächsten Öffnen da.
func screenshots(game: Dictionary) -> Array:
	var id := Iidb.parent_id(game)
	if not verbunden() or id <= 0 or _pausiert() != "":
		return []
	var box := { "fertig": false, "liste": [] }
	_shots_holen(id, box)
	var bis := Time.get_ticks_msec() + SHOTS_WARTE_MS
	while not bool(box.fertig) and Time.get_ticks_msec() < bis:
		await get_tree().process_frame
	return box.liste


func _shots_holen(id: int, box: Dictionary) -> void:
	var r := await spiel_bilder(id, ["screenshot"], 6)
	for a in (r.bilder as Dictionary).get("screenshot", []):
		if not bool(a.get("animiert", false)):
			(box.liste as Array).append(str(a.url))
	box.fertig = true


# --- Klang der Spielseite ----------------------------------------------------------------------

## Datei mit dem Klang eines Spiels (Soundbite von iiDB), bereit zum Abspielen – oder "" (keiner,
## zu lang, zu groß, Format geht nicht, iiDB nicht erreichbar). Liegt danach im Cache und spielt von
## dort sofort, auch ohne Netz. Nach Iidb.ALT_TAGE fragt Uzai nebenher neu (anderer Klang, neue
## Revision); was dabei kommt, gilt ab dem nächsten Öffnen.
func klang_datei(game: Dictionary) -> String:
	var gid := str(game.get("id", ""))
	if not verbunden() or gid == "":
		return ""
	var jetzt := int(Time.get_unix_time_from_system())
	var g := Iidb.gemerkt(game)
	var kl: Dictionary = g.get("klang", {})
	var da := Config.path(KLANG_DIR).path_join(str(kl.datei)) if kl.has("datei") else ""
	if da != "" and FileAccess.file_exists(da):
		if not bool(kl.get("eigen", false)) and jetzt - int(kl.get("t", 0)) >= Iidb.ALT_TAGE * 86400 and _pausiert() == "" \
				and not _klang_laeuft.has(gid):
			_klang_frisch.call_deferred(game, g, jetzt)
		return da
	if _klang_laeuft.has(gid) or _pausiert() != "" or jetzt - int(kl.get("fehlt", 0)) < Iidb.FEHLT_TAGE * 86400:
		return ""
	return await _klang_frisch(game, g, jetzt)


func _klang_frisch(game: Dictionary, g: Dictionary, jetzt: int) -> String:
	var gid := str(game.get("id", ""))
	_klang_laeuft[gid] = true
	var pfad := await _klang_holen(game, g, jetzt)
	_klang_laeuft.erase(gid)
	return pfad


func _klang_holen(game: Dictionary, g: Dictionary, jetzt: int) -> String:
	var gid := str(game.get("id", ""))
	var alt := str((g.get("klang", {}) as Dictionary).get("datei", ""))
	if not g.has("id"):
		# Noch nicht zugeordnet: einmal fragen (mit den Bildern, damit es bei einer Anfrage bleibt).
		if not Iidb.soll_suchen(game, jetzt) or await zuordnen([game]) != "":
			return ""
		g = Iidb.gemerkt(Library.get_game(gid) if not Library.get_game(gid).is_empty() else game)
		if not g.has("id"):
			return ""
	var r := await spiel_bilder(int(g.id), ["soundbite"], 3)
	if not bool(r.ok):
		return ""                       # keine Antwort: nichts merken, beim nächsten Mal neu fragen
	var a := Iidb.klang_wahl((r.bilder as Dictionary).get("soundbite", []))
	var datei := ""
	if not a.is_empty():
		var info := {}
		datei = await _klang_laden(a, info)
		if datei == "" and bool(info.get("netz", false)):
			# Der Klang kam nicht an (Netz, Zeitlimit, 5xx): auch das ist kein Ergebnis – nichts merken.
			Media.log_line("iidb", "Klang %d nicht geladen (Netz)" % int(a.id))
			return ""
		if datei == "":
			Media.log_line("iidb", "Klang %d nicht abspielbar (%s)" % [int(a.id), str(a.mime)])
	var merk: Dictionary = g.duplicate()
	merk["klang"] = { "id": int(a.id), "datei": datei, "t": jetzt } if datei != "" else { "fehlt": jetzt }
	if not Library.get_game(gid).is_empty():
		Library.set_field(gid, "iidb", merk)
		if alt != "" and alt != datei:
			DirAccess.remove_absolute(Config.path(KLANG_DIR).path_join(alt))    # der abgelöste Klang
	return Config.path(KLANG_DIR).path_join(datei) if datei != "" else ""


## Picks a sound by hand (iiDB image picker, tab „Klang“): download, check and assign it to the game. It stays until
## another one is picked (own choice: no replacement after Iidb.ALT_TAGE). Returns the path to play, or "".
func klang_waehlen(game: Dictionary, a: Dictionary) -> String:
	var gid := str(game.get("id", ""))
	if gid == "" or Iidb.klang_grund(a) != "":
		return ""
	var datei := await _klang_laden(a)
	if datei == "" or Library.get_game(gid).is_empty():
		return ""
	var g := Iidb.gemerkt(Library.get_game(gid))
	var alt := str((g.get("klang", {}) as Dictionary).get("datei", ""))
	g["klang"] = { "id": int(a.id), "datei": datei, "t": int(Time.get_unix_time_from_system()), "eigen": true }
	Library.set_field(gid, "iidb", g)
	if alt != "" and alt != datei:
		DirAccess.remove_absolute(Config.path(KLANG_DIR).path_join(alt))
	return Config.path(KLANG_DIR).path_join(datei)


## Einen Klang laden (ohne Schlüssel, begrenzt) und, wenn Godot das Format nicht abspielt, mit FFmpeg
## nach OGG wandeln. Dateiname im Cache oder "" – info.netz, wenn er nur nicht ankam.
func _klang_laden(a: Dictionary, info: Dictionary = {}) -> String:
	var ext := Iidb.klang_endung(a)
	var dir := Config.path(KLANG_DIR)
	var roh := Iidb.datei_name(a, "klang", ext)
	var gewandelt := Iidb.datei_name(a, "klangum", "ogg")
	for da in [roh, gewandelt]:
		if FileAccess.file_exists(dir.path_join(da)):
			return da
	if not Net.download_allowed(str(a.url)):
		return ""
	var r: Dictionary = await Net.request(str(a.url), PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "img", Iidb.KLANG_MAX_BYTES)
	var bytes: PackedByteArray = r.body
	if not bool(r.ok):
		info["netz"] = not Iidb.download_ist_antwort(int(r.get("result", -1)), int(r.get("code", 0)))
		return ""
	if bytes.size() < 64 or bytes.size() > Iidb.KLANG_MAX_BYTES:
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(roh), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	var fertig := roh
	if not Iidb.klang_nativ(bytes):
		# Opus, AAC, FLAC …: mit FFmpeg nach OGG Vorbis, wenn es da ist; sonst gibt es keinen Klang.
		fertig = gewandelt
		var ok: Variant = await Arbeit.ergebnis(Iidb.klang_umwandeln.bind(Capture.ffmpeg_path(), dir.path_join(roh), dir.path_join(fertig)), Arbeit.LANG)
		DirAccess.remove_absolute(dir.path_join(roh))
		if ok != true:
			return ""
	if Iidb.klang_strom(dir.path_join(fertig)) == null:
		DirAccess.remove_absolute(dir.path_join(fertig))
		return ""
	return fertig

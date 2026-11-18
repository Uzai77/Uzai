extends "res://src/core/movies_daten.gd"
## Filme und Serien wie in Nuvio TV: Uzai ist nur der Client für das Stremio-Addon-Ökosystem.
## Kataloge, Details, Streams und Untertitel kommen aus Addons, die der Nutzer selbst einträgt
## (Cinemeta für Kataloge und Details ist vorinstalliert, braucht keinen Schlüssel). Dazu kommen
## optional Plugin-Scraper (JavaScript wie bei Nuvio), die über Deno auf dem PC des Nutzers laufen.
## Uzai baut keine Quellen ein und schlägt keine vor.
##
## Kein P2P: Streams mit infoHash (Torrent) fallen bei „movies.no_p2p“ (Standard) weg, abgespielt
## werden nur direkte Adressen über mpv (siehe Video). CloudStream-Plugins sind Android-Code (DEX)
## und laufen unter Windows nicht – Uzai bietet sie deshalb nicht an.
##
## Bibliothek, Fortschritt, „gesehen“ und Weiterschauen (mit „Als Nächstes“ wie bei Nuvio) liegen
## lokal in movies.json im Datenordner. Mit --demo läuft alles aus eingebauten Daten ohne Netz.
##
## Weitere Quellen (Roadmap 35, src/core/medienquellen.gd): Plex, Jellyfin, Emby und das
## Stremio-Konto. Titel eines Servers tragen Kennungen wie „plex:123“, ihre Kataloge „quelle:plex“ –
## dann fragt Movies dort statt bei den Addons. Im Kinderprofil filtert Movies alles nach Freigabe.
##
## Reine Funktionen (Adressen, Metadaten, Streams, Als Nächstes) stehen in movies_daten.gd, von
## dem dieser Autoload erbt.

const QB := preload("res://src/core/medienquellen_basis.gd")
const Sicher := preload("res://src/core/sicher.gd")

signal changed
signal progress_changed(meta_id: String)
## Film oder Folge zu Ende geschaut. next ist die nächste Folge (Video) oder leer.
signal ended(meta: Dictionary, video_id: String, next: Dictionary)
signal _stream_step
## Änderung in Uzai, die ins Nuvio-Konto soll (NuvioSync): kind = progress, watched,
## continue_removed, library_add, library_remove, addons, plugins.
signal local_change(kind: String, info: Dictionary)

const CINEMETA_URL := "https://v3-cinemeta.strem.io/manifest.json"
const TMDB_API := "https://api.themoviedb.org/3"
const WATCHED_AT := 0.9
const STREAM_TIMEOUT := 25.0
## Höchstens so viele Quellen aus einer Antwort (Addons sind fremd: eine Liste ohne Ende hielte Uzai sonst an), und
## so viele davon je Bild lesen (gemessen: rund 0,25 ms je Quelle für Sprachen, Ton und Herkunft aus ihren Texten).
const STREAMS_JE_QUELLE := 400
const STREAMS_JE_BILD := 20
const PLUGIN_TIMEOUT_MS := 60000
## Plugins sind fremder Code. Deno lässt sie nur ins Internet und nur ihre eigenen Dateien lesen:
## kein Schreiben, keine Programme, keine Umgebungsvariablen, kein Nachladen von Code. Gesperrt
## sind Uzais eigene Server, Router und Geräte im Heimnetz – auch über Namen, die dorthin zeigen
## (Deno prüft die aufgelöste Adresse). IPv6 nimmt Deno nur als einzelne Adressen.
const PLUGIN_DENY_NET := "127.0.0.0/8,0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16,198.18.0.0/15,224.0.0.0/4,240.0.0.0/4,[::1],[::],localhost"
const PLUGIN_HEAP_MB := 512
const PLUGIN_ZEILE_MAX := 8 * 1024 * 1024   ## eine Zeile der Plugin-Ausgabe höchstens so lang
const PLUGIN_ZEILEN_MAX := 20000            ## so viele Zeilen je Lauf (Ergebnisse, Protokoll)
const MAX_SCRIPT_BYTES := 5 * 1024 * 1024
const AUTOPLAY_DELAY := 8.0

## Eingebautes Cinemeta-Manifest: die Startseite steht auch vor dem ersten Abgleich mit dem Netz.
const CINEMETA_MANIFEST := {
	"id": "com.linvo.cinemeta", "version": "3.0.13", "name": "Cinemeta",
	"description": "Die offiziellen Metadaten von Stremio: Filme und Serien mit Bildern, Besetzung und Folgen.",
	"logo": "", "types": ["movie", "series"], "idPrefixes": ["tt"],
	"resources": ["catalog", { "name": "meta", "types": ["movie", "series"], "idPrefixes": ["tt"] }],
	"catalogs": [
		{ "type": "movie", "id": "top", "name": "Popular",
			"extra": [{ "name": "genre",
			"options": ["Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Mystery",
			"Romance", "Sci-Fi", "Sport", "Thriller", "War", "Western"] }, { "name": "search" }, { "name": "skip" }] },
		{ "type": "series", "id": "top", "name": "Popular",
			"extra": [{ "name": "genre",
			"options": ["Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Mystery",
			"Romance", "Sci-Fi", "Sport", "Thriller", "War", "Western", "Reality-TV", "Talk-Show", "Game-Show"] }, { "name": "search" }, { "name": "skip" }] },
		{ "type": "movie", "id": "imdbRating", "name": "Featured",
			"extra": [{ "name": "genre", "options": ["Action", "Comedy", "Drama", "Horror", "Sci-Fi", "Thriller"] }, { "name": "skip" }] },
		{ "type": "series", "id": "imdbRating", "name": "Featured",
			"extra": [{ "name": "genre", "options": ["Action", "Comedy", "Drama", "Horror", "Sci-Fi", "Thriller"] }, { "name": "skip" }] },
	],
}

## ISO-639-1 zu den Kürzeln, die Untertitel-Addons nutzen (OpenSubtitles: ger, eng …).
const LANG_ALIASES := {
	"de": ["de", "ger", "deu", "german", "deutsch"], "en": ["en", "eng", "english"], "fr": ["fr", "fre", "fra", "french"],
	"es": ["es", "spa", "spanish"], "it": ["it", "ita", "italian"], "nl": ["nl", "dut", "nld", "dutch"],
	"pl": ["pl", "pol", "polish"], "pt": ["pt", "por", "pob", "portuguese"], "tr": ["tr", "tur", "turkish"],
}

var demo := false
var error := ""
var addons: Array = []              ## Addon (Stremio-Manifest, movies_daten.gd) in der Reihenfolge des Nutzers
var plugin_repos: Array = []        ## PluginRepo
var data := { "library": [], "progress": {}, "items": {}, "hidden": {}, "dismissed": [] }

var _entries: Array = []            ## gespeicherte Addons: { url, enabled, manifest }
var _meta_cache := {}               ## "type:id" -> Meta
var _people_cache := {}             ## "type:id" -> nachgeladene Personen mit Bildern (cast_photos)
var _home_cache := {}               ## { at, sig, rows }
var _home_gen := 0                  ## zählt hoch, wenn die gemerkte Startseite ungültig wird
var _home_disk_read := false        ## cache/nuvio_home.json nur einmal je Start lesen
var _home_run := {}                 ## laufendes Laden der Startseite (höchstens eins), siehe _start_home
var _home_fail := {}                ## { sig, ms, rows, error }: letzte Runde ohne einen Katalog
var _status: Array = []             ## Quellen der letzten Stream-Suche
var _job_id := 0
var _now := {}                      ## gerade laufend: { meta, video_id, stream, item_id }
var _save_t := 0.0
var _autoplay_at := 0.0
var _autoplay_next := {}
var _writing := false
var _save_timer: Timer
var _demo: Dictionary = {}
var _applying := false              ## gerade kommen Daten aus dem Nuvio-Konto (nichts zurückmelden)


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.0
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	Video.started.connect(_on_video_started)
	Video.stopped.connect(_on_video_stopped)
	Video.reached_end.connect(_on_video_end)
	# Quellen (Plex, Jellyfin …): neue Reihen melden wie spät antwortende Kataloge.
	Quellen.rows_ready.connect(func() -> void:
		_cw_valid = false
		home_ready.emit()
	)
	Quellen.changed.connect(func() -> void: changed.emit())
	if "--demo" in OS.get_cmdline_user_args():
		_load_demo()
		return
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("movies.") and not _writing:
			if k in ["movies.addons", "movies.plugin_repos"]:
				_load_config()
			changed.emit()
	)
	_load_config()
	get_tree().create_timer(6.0).timeout.connect(_auto_refresh)
	var saved: Variant = Config.read_json(Config.path("movies.json"), {})
	if saved is Dictionary:
		data = daten_pruefen(saved)
	_cw_valid = false


## movies.json nach dem Lesen: Die Funktionen darunter nehmen die innere Form als gegeben (`var e: Dictionary = …`,
## `e.id`). Was nicht passt – etwa nach einer Änderung von Hand –, fällt weg, statt später mitten in der Arbeit
## eine Funktion abbrechen zu lassen.
static func daten_pruefen(saved: Dictionary) -> Dictionary:
	var out := { "library": [], "progress": {}, "items": {}, "hidden": Fremd.verz(saved.get("hidden")), "dismissed": [] }
	for e in Fremd.zeilen(saved.get("library")):
		if str(e.get("id", "")) != "":
			(out.library as Array).append(e)
	var progress := Fremd.verz(saved.get("progress"))
	for id in progress:
		if not (progress[id] is Dictionary):
			continue
		var videos := {}
		for vid in progress[id]:
			if progress[id][vid] is Dictionary:
				videos[str(vid)] = progress[id][vid]
		out.progress[str(id)] = videos
	var items := Fremd.verz(saved.get("items"))
	for id in items:
		if items[id] is Dictionary:
			out.items[str(id)] = items[id]
	for s in Fremd.liste(saved.get("dismissed")):
		if s is String:
			(out.dismissed as Array).append(s)
	return out


func _load_demo() -> void:
	demo = true
	_demo = preload("res://src/core/movies_demo.gd").build(int(Time.get_unix_time_from_system()))
	# Hintergrundbilder der Demo-Ordner im Hintergrund malen (fehlen sie, steht das Farbfeld da).
	preload("res://src/core/movies_demo.gd").paint_art()
	_entries = []
	addons = []
	for m in _demo.addons:
		var a := parse_manifest(m, "demo://%s/manifest.json" % str(m.id))
		a["enabled"] = true
		addons.append(a)
	plugin_repos = (_demo.plugin_repos as Array).duplicate(true)
	data = (_demo.data as Dictionary).duplicate(true)
	_cw_valid = false


func save() -> void:
	if demo:
		return
	Config.write_json(Config.path("movies.json"), data)


func _dirty() -> void:
	_cw_valid = false
	if _save_timer:
		_save_timer.start()


## Bereich „Filme“ an (Einstellungen).
func enabled() -> bool:
	return bool(Config.get_value("movies.enabled", true))


func no_p2p() -> bool:
	return bool(Config.get_value("movies.no_p2p", true))


func _set_cfg(key: String, value: Variant) -> void:
	_writing = true
	Config.set_value(key, value)
	_writing = false


# --- Addons ----------------------------------------------------------------------------------

## Cinemeta ist beim ersten Start da. Für Tests lässt sich die Adresse umbiegen (UZAI_CINEMETA).
static func cinemeta_url() -> String:
	var env := Config.probe_env("UZAI_CINEMETA")
	return env if env != "" else CINEMETA_URL


func _load_config() -> void:
	# Nur Verzeichnisse: _entries und addons laufen Platz für Platz nebeneinander (_entry_index). Ein anderer Eintrag
	# in der Datei verschöbe die Plätze, und „Entfernen“ träfe das falsche Addon.
	_entries = Fremd.zeilen(Config.get_value("movies.addons", [])).duplicate(true)
	if not bool(Config.get_value("movies.addons_init", false)):
		if not _entries.any(func(e): return str((e as Dictionary).get("url", "")) == cinemeta_url()):
			var cm := CINEMETA_MANIFEST.duplicate(true)
			if cinemeta_url() != CINEMETA_URL:
				cm = {}
			_entries.push_front({ "url": cinemeta_url(), "enabled": true, "manifest": cm })
		_writing = true
		Config.set_value("movies.addons", _entries)
		Config.set_value("movies.addons_init", true)
		_writing = false
	_rebuild_addons()
	var pr: Variant = Config.get_value("movies.plugin_repos", [])
	plugin_repos = (pr as Array).duplicate(true) if pr is Array else []


func _rebuild_addons() -> void:
	addons = []
	for e in _entries:
		if not (e is Dictionary):
			continue
		var man: Variant = e.get("manifest", {})
		var a := parse_manifest(man if man is Dictionary else {}, str(e.get("url", "")))
		if a.is_empty():
			# Noch nie geladen (Cinemeta in Tests): als leerer Platzhalter, bis refresh_addons() ihn holt.
			a = { "id": str(e.get("url", "")), "name": str(e.get("url", "")).get_base_dir().get_file(), "version": "", "description": "",
				"logo": "", "background": "", "url": str(e.get("url", "")), "types": [], "resources": [], "resource_info": [],
				"id_prefixes": [], "catalogs": [], "configurable": false, "config_required": false, "loaded": false }
		a["enabled"] = bool(e.get("enabled", true))
		addons.append(a)
	# Die gemerkte Startseite gilt nicht mehr (ihre Kennung passt nicht), bleibt aber stehen: Sie
	# liefert die Einträge der Kataloge, die es noch gibt, bis die neuen da sind (old in
	# _start_home) – sonst stand nach jeder Änderung an den Addons (auch beim Nuvio-Abgleich)
	# HOME_WAIT Sekunden lang nur ein Platzhalter da.
	_home_gen += 1


func _save_entries() -> void:
	_set_cfg("movies.addons", _entries.duplicate(true))
	_rebuild_addons()
	changed.emit()


func _tell(kind: String, info := {}) -> void:
	if not _applying and not demo:
		local_change.emit(kind, info)


func addon(id: String) -> Dictionary:
	for a in addons:
		if str(a.id) == id:
			return a
	return {}


func _entry_index(id: String) -> int:
	for i in addons.size():
		if str(addons[i].id) == id:
			return i
	return -1


## Addon über die Adresse seines manifest.json installieren (auch stremio://…). "" oder Fehlertext.
## Ein Addon mit derselben ID (z. B. neu eingerichtet) ersetzt das alte an seinem Platz.
func install_addon(url: String) -> String:
	error = ""
	var u := normalize_manifest_url(url)
	if u == "":
		return _fail("Bitte die Adresse des Addons eingeben (endet meist auf manifest.json).")
	if demo:
		return _fail("Im Demo-Modus werden keine Addons installiert.")
	for e in _entries:
		if str(e.get("url", "")) == u:
			return _fail("Dieses Addon ist schon installiert.")
	var r := await _fetch(u, 20.0)
	if not r.ok:
		return _fail(_http_reason(r, "Addon nicht erreichbar"))
	if not (r.data is Dictionary):
		return _fail("Unter dieser Adresse liegt kein Stremio-Addon.")
	var a := parse_manifest(r.data, u)
	if a.is_empty():
		return _fail("Unter dieser Adresse liegt kein Stremio-Addon (manifest.json ohne id oder resources).")
	if bool(a.config_required):
		return _fail("„%s“ muss erst eingerichtet werden: %s öffnen und die fertige Adresse eintragen." % [a.name, configure_url_for(u)])
	var entry := { "url": u, "enabled": true, "manifest": r.data }
	var idx := _entry_index(str(a.id))
	if idx >= 0:
		entry.enabled = bool(_entries[idx].get("enabled", true))
		_entries[idx] = entry
	else:
		_entries.append(entry)
	_save_entries()
	_tell("addons")
	return ""


func remove_addon(id: String) -> void:
	var i := _entry_index(id)
	if i < 0:
		return
	if demo:
		addons.remove_at(i)
		changed.emit()
		return
	_entries.remove_at(i)
	_save_entries()
	_tell("addons")


func set_addon_enabled(id: String, on: bool) -> void:
	var i := _entry_index(id)
	if i < 0:
		return
	if demo:
		addons[i].enabled = on
		changed.emit()
		return
	_entries[i]["enabled"] = on
	_save_entries()
	_tell("addons")


## Reihenfolge wie bei Nuvio/Stremio: weiter oben = Kataloge zuerst, Details zuerst gefragt.
func move_addon(id: String, delta: int) -> void:
	var i := _entry_index(id)
	if i < 0:
		return
	var j := clampi(i + delta, 0, addons.size() - 1)
	if j == i:
		return
	if demo:
		var a: Dictionary = addons[i]
		addons.remove_at(i)
		addons.insert(j, a)
		changed.emit()
		return
	var e: Dictionary = _entries[i]
	_entries.remove_at(i)
	_entries.insert(j, e)
	_save_entries()
	_tell("addons")


## Alle Manifeste neu laden (neue Kataloge, geänderte Namen). Gibt "" oder eine Fehlerzeile zurück.
func refresh_addons() -> String:
	if demo:
		return ""
	var box := { "left": _entries.size(), "bad": [] }
	for i in _entries.size():
		_refresh_one(i, box)
	while int(box.left) > 0:
		await _stream_step
	var bad: Array = box.bad
	# Ohne Netz nicht als erledigt merken – beim nächsten Start wird es wieder versucht.
	if bad.size() < _entries.size():
		_set_cfg("movies.refreshed", int(Time.get_unix_time_from_system()))
	_save_entries()
	return "" if bad.is_empty() else "Nicht erreichbar: " + ", ".join(bad)


## Einmal am Tag die Manifeste auffrischen (neue Kataloge), still im Hintergrund.
func _auto_refresh() -> void:
	if demo or not enabled():
		return
	if Time.get_unix_time_from_system() - float(Config.get_value("movies.refreshed", 0)) < 86400.0:
		return
	await refresh_addons()


func _refresh_one(i: int, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _refresh_one_arbeit(i, box)
	box.left = int(box.left) - 1
	_stream_step.emit()


func _refresh_one_arbeit(i: int, box: Dictionary) -> void:
	var url := str(_entries[i].get("url", ""))
	var r := await _fetch(url, 20.0)
	if r.ok and r.data is Dictionary and not parse_manifest(r.data, url).is_empty() and i < _entries.size() and str(_entries[i].get("url", "")) == url:
		_entries[i]["manifest"] = r.data
	else:
		var m: Variant = _entries[i].get("manifest", {}) if i < _entries.size() else {}
		(box.bad as Array).append(str((m as Dictionary).get("name", url)) if m is Dictionary and not (m as Dictionary).is_empty() else url)


## Seite zum Einrichten eines Addons (Stremio: …/configure), z. B. als QR-Code fürs Handy.
func configure_url(id: String) -> String:
	var a := addon(id)
	return configure_url_for(str(a.get("url", ""))) if not a.is_empty() else ""


static func configure_url_for(manifest_url: String) -> String:
	var b := split_base(manifest_url)
	return str(b.path) + "/configure" + str(b.query)


# --- Netz -----------------------------------------------------------------------------------

func _fail(msg: String) -> String:
	error = msg
	return msg


func _fetch(url: String, timeout := 20.0, headers := PackedStringArray()) -> Dictionary:
	var h := headers.duplicate()
	h.append("Accept: application/json")
	var r: Dictionary = await Net.request(url, h, HTTPClient.METHOD_GET, "", timeout)
	# Kataloge sind oft einige 100 KB: groß im Hintergrund lesen (Net.parse_json).
	var body: PackedByteArray = r.get("body", PackedByteArray())
	var parsed: Variant = await Net.parse_json(body)
	return { "ok": bool(r.ok) and parsed != null, "code": int(r.code), "data": parsed, "result": int(r.get("result", -1)),
		"bytes": body.size(), "ctype": Net.header(r, "content-type") }


static func _http_reason(r: Dictionary, what: String) -> String:
	var code := int(r.get("code", 0))
	if code == 0:
		return "%s (keine Verbindung oder Zeitüberschreitung)." % what
	if code == 404:
		return "%s (nicht gefunden)." % what
	if code >= 200 and code < 300:
		return "%s (unerwartete Antwort)." % what
	if code == 401 or code == 403:
		return "%s (kein Zugriff)." % what
	return "%s (antwortet gerade nicht)." % what


# --- Startseite, Kataloge, Suche ------------------------------------------------------------

## Format der gemerkten Startseite (v1 hatte Sammlungen als Titel-Reihen).
const HOME_FORMAT := "v2"


## Kennung der Addons für den Zwischenspeicher: Adresse, Version, an/aus und welche Kataloge.
func _addons_sig() -> String:
	var parts := PackedStringArray()
	for a in addons:
		var cats := PackedStringArray()
		for c in a.catalogs:
			cats.append("%s/%s" % [c.get("type", ""), c.get("id", "")])
		parts.append("%s:%s:%d:%s:%d" % [a.id, a.get("version", ""), int(bool(a.enabled)), a.get("url", ""), ",".join(cats).hash()])
	return HOME_FORMAT + "|" + ",".join(parts)


## Reihen der Startseite: alle Kataloge ohne Pflicht-Zusätze, in Addon-Reihenfolge, parallel geladen.
## Leere oder fehlerhafte Kataloge fallen weg. Weiterschauen kommt über continue_watching().
## Schnell statt vollständig: Gemerkte Reihen (auch vom letzten Start, von der Platte) kommen
## sofort, aufgefrischt wird im Hintergrund. Beim ersten Laden wartet die Seite höchstens
## HOME_WAIT Sekunden; was danach kommt, meldet home_ready. Läuft schon ein Laden, wartet ein
## zweiter Aufruf auf dessen Ergebnis statt alles noch einmal zu holen.
func home_rows(force := false) -> Array:
	# Eigene Medienserver gleichzeitig mit den Katalogen anstoßen (nicht erst danach).
	Quellen.kick(force)
	var rows: Array = await _addon_home_rows(force) if Quellen.addons_on() else []
	var by_kind: Dictionary = await Quellen.home_rows(force)
	var out: Array = []
	for k in Quellen.order():
		if k == "addons":
			out.append_array(rows)
		elif by_kind.has(k):
			out.append_array(by_kind[k])
	if not Quellen.addons_on():
		error = "" if not out.is_empty() else ("; ".join(PackedStringArray(Quellen.errors())) if not Quellen.errors().is_empty()
				else "Keine Quelle eingeschaltet. Unter „Filme-Quellen“ wählen, woher Filme kommen.")
	elif not out.is_empty():
		error = ""
	return QB.kid_rows(out, kid_rules())


## Kinderprofil: die Regeln (Altersstufe, „ohne Angabe“); leer = kein Kinderprofil.
func kid_rules() -> Dictionary:
	return Config.kid_rules() if Config.is_kid() else {}


## Darf das aktive Profil diesen Titel sehen? (Kinderprofil: Freigabe oder Familie.)
func kid_ok(item: Dictionary) -> bool:
	var r := kid_rules()
	return r.is_empty() or QB.kid_allows(item, r)


func _addon_home_rows(force := false) -> Array:
	error = ""
	if demo:
		await get_tree().process_frame
		return (_demo.rows as Array).duplicate(true)
	var sig := _addons_sig() + "|" + NuvioSync.layout_sig()
	if not _home_disk_read:
		_home_disk_read = true
		# Auch ein Stand mit anderer Kennung (Addon aktualisiert, Nuvio-Layout geändert) wird gelesen:
		# Er gilt nicht, liefert aber die Einträge der Kataloge, die es noch gibt (old in _start_home)
		# – die Seite steht dann sofort, statt HOME_WAIT Sekunden Platzhalter zu zeigen.
		var disk: Variant = Config.read_json(Config.path("cache/nuvio_home.json"), {})
		if _home_cache.is_empty() and disk is Dictionary and disk.get("rows") is Array and disk.has("at"):
			# Nur Reihen in bekannter Form (die Datei liegt auf der Platte): sonst bräche diese Funktion bei jedem
			# Öffnen von „Filme“ ab.
			_home_cache = { "at": Fremd.komma(disk.get("at")), "sig": Fremd.text(disk.get("sig")), "rows": Fremd.zeilen(disk.get("rows")) }
	if not force and not _home_cache.is_empty() and str(_home_cache.get("sig", "")) == sig:
		if Time.get_unix_time_from_system() - Fremd.komma(_home_cache.get("at")) >= HOME_MAX_AGE and _home_run.is_empty():
			_refresh_home(sig)
		return Fremd.liste(_home_cache.get("rows")).duplicate(true)
	# Eben kam aus keinem Katalog etwas: nicht bei jedem Öffnen alles neu anfragen (das hielt eine
	# Sperre des Servers nur aufrecht), sondern HOME_FAIL_PAUSE lang den Stand mit Grund zeigen.
	# „Erneut versuchen“ (retry_home) fragt sofort.
	if not force and str(_home_fail.get("sig", "")) == sig and Time.get_ticks_msec() - int(_home_fail.get("ms", 0)) < int(HOME_FAIL_PAUSE * 1000.0):
		error = str(_home_fail.get("error", ""))
		return (_home_fail.get("rows", []) as Array).duplicate(true)
	var run: Dictionary = _home_run
	if run.is_empty() or str(run.sig) != sig or int(run.gen) != _home_gen:
		run = _start_home(sig)
	var jobs: Array = run.jobs
	var has_old := not (run.old as Dictionary).is_empty()
	while not bool(run.done):
		if home_wait_over(jobs, Time.get_ticks_msec() - int(run.t0), has_old):
			break
		await get_tree().create_timer(0.05).timeout
	if bool(run.done):
		return (run.rows as Array).duplicate(true)
	# Teilergebnis: der Rest lädt weiter und meldet sich mit home_ready.
	run.announce = true
	var rows := _assemble_home(jobs, run.coll, run.old)
	if int(run.gen) == _home_gen and jobs.any(func(j): return bool(j.ok)):
		_home_cache = { "at": 0.0, "sig": sig, "rows": rows }
	return rows.duplicate(true)


const HOME_WAIT := 4.0
const HOME_WAIT_OLD := 0.6           ## mit gemerkten Einträgen (anderer Stand) nur so kurz warten
const HOME_TOP := 3                  ## sind die obersten Reihen da, steht die Seite schon …
const HOME_TOP_MS := 250             ## … (kommt alles schneller, dann alles auf einmal)
const HOME_TEIL_MS := 1000           ## Zwischenstände (weitere Reihen) höchstens so oft melden
const HOME_MAX_AGE := 600.0
const CATALOG_TIMEOUT := 8.0
const HOME_FAIL_PAUSE := 45.0        ## nach „kein Katalog antwortet“ so lange nicht von selbst neu fragen
signal home_ready


## „Erneut versuchen“: die Pause nach Fehlschlägen aufheben, beim nächsten home_rows() frisch fragen.
func retry_home() -> void:
	_home_fail = {}


## Genug gewartet auf die Kataloge? Ja, wenn die obersten HOME_TOP Reihen geantwortet haben (der
## Rest kommt mit home_ready nach – oben zuerst; frühestens nach HOME_TOP_MS), mit gemerkten Einträgen nach HOME_WAIT_OLD,
## sonst nach HOME_WAIT, sofern überhaupt einer geantwortet hat.
static func home_wait_over(jobs: Array, elapsed_ms: int, has_old: bool) -> bool:
	if jobs.is_empty():
		return true
	var top := true
	var any := false
	for i in jobs.size():
		var d := bool((jobs[i] as Dictionary).get("done", false))
		any = any or d
		if i < HOME_TOP and not d:
			top = false
	if top and elapsed_ms >= HOME_TOP_MS:
		return true
	if has_old and elapsed_ms >= int(HOME_WAIT_OLD * 1000.0):
		return true
	return any and elapsed_ms > int(HOME_WAIT * 1000.0)


## Läuft gerade ein Laden der Startseite (Kataloge oder eigene Medienserver)?
func home_busy() -> bool:
	return not _home_run.is_empty() or Quellen.loading_any()


## Im Hintergrund auffrischen; kommt etwas Neues, meldet es home_ready. Fertig, wenn alles da ist.
func _refresh_home(sig: String) -> void:
	var run := _start_home(sig, true)
	while not bool(run.done):
		await get_tree().create_timer(0.1).timeout


## Alle Kataloge gleichzeitig laden (in Nuvio ausgeblendete gar nicht erst). Nuvio-Sammlungen
## sind Ordner: die Kacheln brauchen nichts aus dem Netz, ihre Kataloge lädt erst die Ordnerseite.
## old: Einträge der bisher gemerkten Reihen, für Kataloge, die diesmal nicht antworten.
func _start_home(sig: String, announce := false) -> Dictionary:
	var jobs: Array = []
	var off: Dictionary = NuvioSync.disabled_keys()
	for a in addons:
		if not bool(a.enabled):
			continue
		for c in a.catalogs:
			if catalog_needs(c, []) or off.has("%s/%s/%s" % [a.id, c.type, c.id]):
				continue
			jobs.append({ "addon": a, "cat": c, "items": [], "ok": false, "done": false, "ms": 0, "why": "" })
	var old := {}
	for r in _home_cache.get("rows", []):
		if r is Dictionary and str(r.get("kind", "")) != "folders" and r.get("items") is Array and not (r.items as Array).is_empty():
			old[str(r.get("key", ""))] = r.items
	var run := { "sig": sig, "gen": _home_gen, "jobs": jobs, "coll": NuvioSync.collection_folder_rows(), "old": old,
		"box": { "left": jobs.size() }, "t0": Time.get_ticks_msec(), "done": false, "rows": [], "announce": announce }
	_home_run = run
	for j in jobs:
		_load_row(j, run.box)
	_finish_home(run)
	return run


## Warten, bis alle Kataloge geantwortet haben, dann merken (Speicher und Platte). Kam gar nichts
## (offline), bleibt der alte Stand samt Zeitpunkt; inzwischen ungültig gewordenes wird verworfen.
func _finish_home(run: Dictionary) -> void:
	var box: Dictionary = run.box
	var jobs: Array = run.jobs
	var shown_left := jobs.size()
	var shown_at := Time.get_ticks_msec()
	while int(box.left) > 0:
		await get_tree().create_timer(0.1).timeout
		# Wer schon etwas zeigt (announce), bekommt weitere Reihen, sobald sie da sind – nicht erst,
		# wenn auch der langsamste Katalog geantwortet hat.
		if bool(run.announce) and int(run.gen) == _home_gen and int(box.left) > 0 and int(box.left) < shown_left \
				and Time.get_ticks_msec() - shown_at >= HOME_TEIL_MS and jobs.any(func(j): return bool(j.ok)):
			shown_left = int(box.left)
			shown_at = Time.get_ticks_msec()
			var same := str(_home_cache.get("sig", "")) == str(run.sig)
			_home_cache = { "at": float(_home_cache.get("at", 0.0)) if same else 0.0, "sig": str(run.sig), "rows": _assemble_home(jobs, run.coll, run.old) }
			home_ready.emit()
	if is_same(_home_run, run):
		_home_run = {}
	run.rows = _assemble_home(jobs, run.coll, run.old)
	run.done = true
	_log_home(jobs, Time.get_ticks_msec() - int(run.t0))
	if int(run.gen) != _home_gen:
		return
	if not jobs.is_empty() and not jobs.any(func(j): return bool(j.ok)):
		_home_fail = { "sig": str(run.sig), "ms": Time.get_ticks_msec(), "rows": run.rows, "error": error }
		return
	_home_fail = {}
	_home_cache = { "at": Time.get_unix_time_from_system(), "sig": str(run.sig), "rows": run.rows }
	Config.write_json(Config.path("cache/nuvio_home.json"), _home_cache)
	if bool(run.announce):
		home_ready.emit()


## Für logs/leistung.log: wie lange die Kataloge brauchten und welcher am längsten (Name des Addons
## und des Katalogs – nie die Adresse, sie kann Schlüssel enthalten).
func _log_home(jobs: Array, ms: int) -> void:
	if jobs.is_empty() or demo:
		return
	var ok := 0
	var slow: Dictionary = jobs[0]
	for j in jobs:
		ok += 1 if bool(j.ok) else 0
		if int(j.get("ms", 0)) > int(slow.get("ms", 0)):
			slow = j
	Media.log_line("leistung", "Filme: %d von %d Katalogen in %d ms, langsamster %s · %s (%d ms)" % [ok, jobs.size(), ms,
		str((slow.addon as Dictionary).get("name", "?")).left(40), catalog_title(slow.cat).left(40), int(slow.get("ms", 0))])
	# Je Katalog, der nichts brachte, der Grund (HTTP-Code, kein JSON, ohne „metas“ …) – in
	# logs/filme.log. Vorher stand bei „0 von 4“ nirgends, warum (Freund-Test 0.16.51).
	for j in jobs:
		if str(j.get("why", "")) != "":
			Media.log_line("filme", "Katalog %s · %s: %s (%d ms)" % [str((j.addon as Dictionary).get("name", "?")).left(40),
				catalog_title(j.cat).left(40), str(j.why), int(j.get("ms", 0))])


## Reihen aus den Katalog-Aufträgen; ein Katalog ohne Antwort zeigt seinen Stand aus old (Schlüssel → Einträge).
func _assemble_home(jobs: Array, coll: Dictionary, old := {}) -> Array:
	var rows: Array = []
	for j in jobs:
		var c: Dictionary = j.cat
		var a: Dictionary = j.addon
		var key := "%s/%s/%s" % [a.id, c.type, c.id]
		var items: Array = j.items
		if not bool(j.ok) and old.has(key):
			items = old[key]
		if items.is_empty():
			continue
		rows.append({ "key": key, "title": catalog_title(c), "type": str(c.type), "addon_id": str(a.id),
			"catalog_id": str(c.id), "extra": {}, "items": items, "see_all": true })
	# Nuvio-Konto: Sammlungen (Ordner-Reihen) wie in der Nuvio-App anordnen.
	rows = NuvioSync.arrange(rows, coll)
	if rows.is_empty() and not jobs.is_empty():
		var why := catalog_summary(jobs)
		error = "Keine Kataloge erreichbar. Netz prüfen oder unter Einstellungen → Filme die Addons ansehen." if why == "" \
				else TranslationServer.translate("Keine Kataloge erreichbar (%s).") % TranslationServer.translate(why)
	elif jobs.is_empty() and coll.is_empty():
		error = "Kein Addon liefert Kataloge. Unter Einstellungen → Filme ein Addon eintragen (z. B. Cinemeta)."
	return rows


func _load_row(j: Dictionary, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _load_row_arbeit(j, box)
	box.left = int(box.left) - 1
	_stream_step.emit()


func _load_row_arbeit(j: Dictionary, box: Dictionary) -> void:
	var a: Dictionary = j.addon
	var c: Dictionary = j.cat
	var t0 := Time.get_ticks_msec()
	var r := await _fetch(catalog_url(str(a.url), str(c.type), str(c.id)), CATALOG_TIMEOUT)
	var list := catalog_metas(r.get("data"))
	j.why = catalog_reason(r, Time.get_ticks_msec() - t0, CATALOG_TIMEOUT)
	if j.why == "" or j.why == "leer":
		j.items = _previews(list, str(a.id), str(c.type))
		j.ok = true
	j.ms = Time.get_ticks_msec() - t0
	j.done = true


func _previews(list: Array, addon_id: String, type: String) -> Array:
	var out: Array = []
	var seen := {}
	for m in list:
		if m is Dictionary and _s(m.get("id", "")) != "" and not seen.has(_s(m.id)):
			seen[_s(m.id)] = true
			out.append(parse_meta_preview(m, addon_id, type))
	return out


## Großes Bild oben: Titel mit Hintergrund (und am liebsten Schriftzug) aus den ersten Reihen.
func hero_items() -> Array:
	var list: Array = []
	for k in Quellen.order():
		list.append_array(_addon_hero_items() if k == "addons" else Quellen.hero_items(k))
	return QB.kid_filter(list, kid_rules()).slice(0, 8)


func _addon_hero_items() -> Array:
	if demo:
		return (_demo.hero as Array).duplicate(true)
	# Nur Reihen eingeschalteter Addons (die gemerkte Startseite kann noch von vorher sein).
	var rows: Array = (_home_cache.get("rows", []) as Array).filter(func(r): return str(r.get("kind", "")) != "folders" \
			and bool(addon(str(r.get("addon_id", ""))).get("enabled", false)))
	# Nuvio: die Kataloge, die im Konto fürs Titelbild gewählt sind.
	var picked: Array = NuvioSync.hero_rows(rows)
	if not picked.is_empty():
		rows = picked
	var out: Array = []
	var seen := {}
	for pass_n in 2:
		for i in 12:
			for r in rows.slice(0, 3):
				var items := Fremd.zeilen(r.get("items"))
				if i >= items.size():
					continue
				var it: Dictionary = items[i]
				if seen.has(str(it.get("id", ""))) or str(it.get("background", "")) == "" or (pass_n == 0 and str(it.get("logo", "")) == ""):
					continue
				seen[str(it.get("id", ""))] = true
				out.append(it)
				if out.size() >= 8:
					return out
	return out


## Eine Seite eines Katalogs (skip = Anzahl schon geladener Einträge; extra z. B. { genre = "Drama" }).
func catalog_page(addon_id: String, type: String, catalog_id: String, skip := 0, extra := {}, timeout := 20.0) -> Array:
	error = ""
	var own := QB.owner_of_addon(addon_id)
	if own != "":
		var got: Dictionary = await Quellen.catalog_page(own, type, catalog_id, skip, extra)
		if str(got.get("error", "")) != "":
			_fail(str(got.error))
		return QB.kid_filter(got.get("items", []), kid_rules())
	return QB.kid_filter(await _addon_catalog_page(addon_id, type, catalog_id, skip, extra, timeout), kid_rules())


## Genres zum Filtern einer Reihe („Alle anzeigen“): bei Quellen die ihrer Bibliothek.
func row_genres(row: Dictionary) -> Array:
	var own := QB.owner_of_addon(str(row.get("addon_id", "")))
	if own != "":
		return await Quellen.genre_names(own, str(row.get("catalog_id", "")))
	return genres(str(row.get("type", "movie")))


func _addon_catalog_page(addon_id: String, type: String, catalog_id: String, skip := 0, extra := {}, timeout := 20.0) -> Array:
	if demo:
		await get_tree().process_frame
		return _demo_catalog(type, catalog_id, skip, extra)
	var a := addon(addon_id)
	if a.is_empty():
		_fail("Addon nicht mehr installiert.")
		return []
	var r := await _fetch(catalog_url(str(a.url), type, catalog_id, skip, extra), timeout)
	var why := catalog_reason(r)
	if why != "" and why != "leer":
		Media.log_line("filme", "Katalogseite %s · %s: %s" % [str(a.get("name", "?")).left(40), catalog_id.left(40), why])
	if not r.ok or not (r.data is Dictionary or r.data is Array):
		_fail(_http_reason(r, "Katalog nicht geladen"))
		return []
	return _previews(catalog_metas(r.data), addon_id, type)


## Genres für einen Typ aus den Katalogen der Addons (erste Liste mit Auswahl gewinnt).
func genres(type: String) -> Array:
	for c in discover_catalogs(type):
		if not (c.genres as Array).is_empty():
			return (c.genres as Array).duplicate()
	return []


## Kataloge eines Typs zum Stöbern (mit Genre-Liste), in Addon-Reihenfolge.
func discover_catalogs(type: String) -> Array:
	var out: Array = []
	for a in addons:
		if not bool(a.enabled):
			continue
		for c in a.catalogs:
			if str(c.type) != type or catalog_needs(c, ["genre"]):
				continue
			var g: Array = []
			for e in c.extra:
				if str(e.name) == "genre":
					g = e.options
			out.append({ "addon_id": str(a.id), "addon_name": str(a.name), "catalog_id": str(c.id), "type": type,
				"name": catalog_title(c), "genres": g, "genre_required": catalog_needs(c, []) })
	return out


## Suche in allen Addons mit Such-Katalog (nur „search“ als Pflicht), parallel. Reihen wie home_rows().
func search(query: String) -> Array:
	error = ""
	var q := query.strip_edges()
	if q == "":
		return []
	var own: Array = await Quellen.search(q)
	var rows: Array = await _addon_search(q) if Quellen.addons_on() else []
	if not own.is_empty():
		error = ""
	var out: Array = []
	for k in Quellen.order():
		out.append_array(rows if k == "addons" else own.filter(func(r: Dictionary) -> bool: return str(r.get("source", "")) == k))
	return QB.kid_rows(out, kid_rules())


func _addon_search(q: String) -> Array:
	if demo:
		await get_tree().process_frame
		return _demo_search(q)
	var jobs: Array = []
	var by_addon := {}
	for a in addons:
		if not bool(a.enabled):
			continue
		for c in a.catalogs:
			if catalog_has(c, "search") and not catalog_needs(c, ["search"]):
				jobs.append({ "addon": a, "cat": c, "items": [] })
				by_addon[str(a.id)] = true
	var box := { "left": jobs.size() }
	for j in jobs:
		_search_one(j, q, box)
	while int(box.left) > 0:
		await _stream_step
	var rows: Array = []
	for j in jobs:
		if (j.items as Array).is_empty():
			continue
		var c: Dictionary = j.cat
		var a: Dictionary = j.addon
		var title := type_label(str(c.type))
		if by_addon.size() > 1:
			title += "  ·  " + str(a.name)
		rows.append({ "key": "search/%s/%s/%s" % [a.id, c.type, c.id], "title": title, "type": str(c.type), "addon_id": str(a.id),
			"catalog_id": str(c.id), "extra": { "search": q }, "items": j.items, "see_all": false })
	if jobs.is_empty():
		error = "Kein Addon kann suchen."
	return rows


func _search_one(j: Dictionary, q: String, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _search_one_arbeit(j, q, box)
	box.left = int(box.left) - 1
	_stream_step.emit()


func _search_one_arbeit(j: Dictionary, q: String, box: Dictionary) -> void:
	var a: Dictionary = j.addon
	var c: Dictionary = j.cat
	var r := await _fetch(catalog_url(str(a.url), str(c.type), str(c.id), 0, { "search": q }))
	if r.ok:
		j.items = _previews(catalog_metas(r.data), str(a.id), str(c.type))


# --- Details ------------------------------------------------------------------------------------

## Details zu einem Film oder einer Serie (leer bei Fehler, Grund in error).
func meta(type: String, id: String) -> Dictionary:
	var m := await _meta_any(type, id)
	if not m.is_empty() and not kid_ok(m):
		_fail("In diesem Profil nicht freigegeben.")
		return {}
	return m


func _meta_any(type: String, id: String) -> Dictionary:
	error = ""
	var key := type + ":" + id
	if _meta_cache.has(key):
		return (_meta_cache[key] as Dictionary).duplicate(true)
	if QB.owner_of(id) != "":
		var sm: Dictionary = await Quellen.meta(type, id)
		if sm.has("error"):
			_fail(str(sm.error))
			return {}
		_apply_server_progress(id, sm)
		_meta_cache[key] = sm
		Config.cap(_meta_cache, 300)
		return sm.duplicate(true)
	if demo:
		await get_tree().process_frame
		var dm: Dictionary = (_demo.metas as Dictionary).get(id, {})
		if dm.is_empty():
			_fail("Nicht gefunden.")
			return {}
		_meta_cache[key] = dm
		Config.cap(_meta_cache, 300)
		return dm.duplicate(true)
	var cands := meta_candidates(addons, type, id)
	if cands.is_empty():
		_fail("Kein Addon liefert Details für diesen Titel.")
		return {}
	var reasons := PackedStringArray()
	for a in cands:
		var r := await _fetch(resource_url(str(a.url), "meta", type, id))
		if r.ok and r.data is Dictionary and r.data.get("meta") is Dictionary and not (r.data.meta as Dictionary).is_empty():
			var m := parse_meta(r.data.meta, str(a.id), type)
			if str(m.id) == "":
				m.id = id
			await _tmdb_enrich(m, type)
			_meta_cache[key] = m
			Config.cap(_meta_cache, 300)
			return m.duplicate(true)
		var why := "nicht gefunden" if r.ok else _http_reason(r, "keine Details").trim_suffix(".")
		reasons.append("%s: %s" % [a.name, why])
	_fail("Details nicht geladen – " + "; ".join(reasons))
	return {}


func _tmdb_base() -> String:
	var env := Config.probe_env("UZAI_TMDB_API")
	return env if env != "" else TMDB_API


## IMDb-Kennung aus fremden Angaben (Addon): nur „tt“ und Ziffern. Sie steht im Pfad der Anfrage an TMDB, die den
## eigenen Schlüssel trägt – alles andere („tt1/../…“) könnte die Anfrage auf einen anderen Weg lenken.
static func imdb_ok(id: String) -> bool:
	return id.length() >= 3 and id.length() <= 14 and id.begins_with("tt") and id.substr(2).is_valid_int() and not id.contains("-") and not id.contains("+")


func tmdb_key() -> String:
	return str(Config.get_value("movies.tmdb_key", "")).strip_edges()


## Mit eigenem TMDB-Schlüssel (optional): deutscher Titel und Beschreibung, TMDB-ID für Plugins.
func _tmdb_enrich(m: Dictionary, type: String) -> void:
	var imdb := str(m.get("imdb_id", ""))
	if tmdb_key() == "" or not imdb_ok(imdb):
		return
	var r := await _fetch("%s/find/%s?api_key=%s&external_source=imdb_id&language=%s" % [_tmdb_base(), imdb, tmdb_key().uri_encode(), Lang.api("tmdb")], 10.0)
	if not r.ok or not (r.data is Dictionary):
		return
	var list: Variant = r.data.get("tv_results" if type == "series" else "movie_results", [])
	if not (list is Array) or (list as Array).is_empty() or not (list[0] is Dictionary):
		return
	var t: Dictionary = list[0]
	if str(m.get("tmdb_id", "")) == "" and t.get("id") != null:
		m["tmdb_id"] = _s(t.id)
	var de_title := _s(t.get("name" if type == "series" else "title", ""))
	var de_text := _s(t.get("overview", ""))
	if de_title != "":
		m["name_original"] = str(m.name)
		m["name"] = de_title
	if de_text != "":
		m["description"] = de_text


## Bilder der Besetzung nachladen, wenn das Addon der Details nur Namen lieferte: mit eigenem
## TMDB-Schlüssel aus TMDB (/credits, bei Serien /aggregate_credits), sonst aus einem anderen
## Addon mit Details (etwa Cinemeta, das app_extras/credits_cast mit Bildern liefert). Ergebnis
## { schlüssel: { name, photo, character } }, leer, wenn es keine Bilder gibt; je Titel einmal.
func cast_photos(type: String, m: Dictionary) -> Dictionary:
	var id := str(m.get("id", ""))
	if has_photos(m.get("people")):
		return m.people
	var key := type + ":" + id
	if _people_cache.has(key):
		return _people_cache[key]
	if demo or id == "":
		return {}
	var got := {}
	var tmdb := str(m.get("tmdb_id", ""))
	if tmdb == "" and id.begins_with("tmdb:"):
		tmdb = id.substr(5).get_slice(":", 0)
	if tmdb_key() != "" and tmdb.is_valid_int():
		var kind := "tv/%s/aggregate_credits" if type == "series" else "movie/%s/credits"
		var r := await _fetch("%s/%s?api_key=%s&language=%s" % [_tmdb_base(), kind % tmdb, tmdb_key().uri_encode(), Lang.api("tmdb")], 10.0)
		if r.ok and r.data is Dictionary:
			got = parse_people({ "credits_cast": r.data.get("cast", []), "credits_crew": r.data.get("crew", []) })
	if not has_photos(got):
		var tries := 0
		for a in meta_candidates(addons, type, id):
			if str(a.id) == str(m.get("addon_id", "")) or tries >= 2:
				continue
			tries += 1
			var r2 := await _fetch(resource_url(str(a.url), "meta", type, id), 10.0)
			if r2.ok and r2.data is Dictionary and r2.data.get("meta") is Dictionary:
				var p2 := parse_people(r2.data.meta)
				if has_photos(p2):
					got = p2
					break
	if not has_photos(got):
		got = {}
	_people_cache[key] = got
	Config.cap(_people_cache, 300)
	if not got.is_empty() and _meta_cache.has(key):
		var cm: Dictionary = _meta_cache[key]
		cm["people"] = merge_people(cm.get("people", {}) if cm.get("people") is Dictionary else {}, got)
	return got


## Fehlende Bilder und Rollen aus src ergänzen (vorhandene bleiben); neue Personen kommen dazu.
static func merge_people(dst: Dictionary, src: Dictionary) -> Dictionary:
	for k in src:
		var e: Dictionary = src[k]
		if not dst.has(k):
			dst[k] = e.duplicate()
			continue
		var have: Dictionary = dst[k]
		if str(have.get("photo", "")) == "" and str(e.get("photo", "")) != "":
			have["photo"] = e.photo
		if str(have.get("character", "")) == "" and str(e.get("character", "")) != "":
			have["character"] = e.character
	return dst


## TMDB-ID für Plugin-Scraper: aus Cinemeta (moviedb_id), sonst über TMDB (eigener Schlüssel).
func _tmdb_id(type: String, meta_id: String) -> String:
	if meta_id.begins_with("tmdb:"):
		return meta_id.substr(5).get_slice(":", 0)
	if meta_id.is_valid_int():
		return meta_id
	if meta_id.begins_with("kitsu:") or meta_id.begins_with("mal:") or meta_id.begins_with("anilist:"):
		return meta_id
	if not imdb_ok(meta_id):
		return ""
	var item: Dictionary = (data.items as Dictionary).get(meta_id, {})
	if str(item.get("tmdb_id", "")) != "":
		return str(item.tmdb_id)
	var m := await meta(type, meta_id)
	if str(m.get("tmdb_id", "")) != "":
		return str(m.tmdb_id)
	if tmdb_key() != "":
		var r := await _fetch("%s/find/%s?api_key=%s&external_source=imdb_id" % [_tmdb_base(), meta_id, tmdb_key().uri_encode()], 10.0)
		if r.ok and r.data is Dictionary:
			for k in ["movie_results", "tv_results"]:
				var l: Variant = r.data.get(k, [])
				if l is Array and not (l as Array).is_empty() and l[0] is Dictionary and l[0].get("id") != null:
					return _s(l[0].id)
	return ""


# --- Streams -----------------------------------------------------------------------------------

## Streams aller passenden Addons und Plugins, parallel. on_partial(liste) bekommt nach jeder
## Antwort das bisherige, sortierte Ergebnis. P2P fällt bei „movies.no_p2p“ weg.
func streams(type: String, video_id: String, on_partial: Callable = Callable()) -> Array:
	error = ""
	_job_id += 1
	# Zwischenstände gehen an die Quellen-Seite; ist die schon zu, nie mehr aufrufen (siehe Media.guard).
	var job := { "id": _job_id, "all": [], "keys": {}, "pending": 0, "cb": Media.guard(on_partial), "sorted": [], "p2p_hidden": 0, "fails": [], "order": 0 }
	_status = []
	if QB.owner_of(video_id) != "":
		_status = [{ "name": Quellen.label(QB.owner_of(video_id)), "state": "lädt", "count": 0, "kind": "server", "id": "quelle", "error": "" }]
		var got: Dictionary = await Quellen.streams(video_id)
		if int(job.id) == _job_id:
			_status = [got.status]
		for st in got.streams:
			if st is Dictionary:
				Q.enrich(st)
		var list: Array = sort_streams(got.streams, pref_quality(), pref_lang())
		if list.is_empty():
			_fail("Der Server hat keine Datei zum Abspielen geliefert." if str(got.status.error) == "" else str(got.status.error))
		var cb: Callable = job.cb
		if cb.is_valid() and int(job.id) == _job_id:
			cb.call(list.duplicate(true))
		return list
	if demo:
		return await _demo_streams(job, type, video_id)
	var sv := split_video_id(video_id)
	var list: Array = []
	for a in addons:
		if bool(a.enabled) and supports(a, "stream", type, video_id):
			list.append(a)
	var scrapers := _active_scrapers(type)
	for i in list.size():
		var a: Dictionary = list[i]
		_status.append({ "name": str(a.name), "state": "lädt", "count": 0, "kind": "addon", "id": str(a.id), "error": "" })
		job.pending = int(job.pending) + 1
		_addon_streams(job, a, type, video_id, i)
	if not scrapers.is_empty():
		for sc in scrapers:
			_status.append({ "name": str(sc.name), "state": "lädt", "count": 0, "kind": "plugin", "id": "plugin:" + str(sc.id), "error": "" })
		job.pending = int(job.pending) + 1
		_plugin_streams(job, scrapers, type, str(sv.meta_id), int(sv.season), int(sv.episode))
	if list.is_empty() and scrapers.is_empty():
		_fail("Kein Addon liefert Streams für %s. Unter Einstellungen → Filme ein Stream-Addon eintragen." % type_label(type))
		return []
	while int(job.pending) > 0:
		await _stream_step
	var result: Array = job.sorted
	if result.is_empty():
		var fails: Array = job.fails
		if not fails.is_empty():
			_fail("Keine Streams gefunden. " + "; ".join(PackedStringArray(fails.slice(0, 3))))
		elif int(job.p2p_hidden) > 0:
			_fail("Nur P2P-Streams gefunden (%d) – die spielt Uzai nicht ab." % int(job.p2p_hidden))
		else:
			_fail("Keine Streams gefunden.")
	return result.duplicate(true)


## Stand der Quellen der laufenden bzw. letzten Stream-Suche: [{ name, state, count, kind, error }].
func stream_sources_status() -> Array:
	return _status.duplicate(true)


func _set_status(job: Dictionary, id: String, state: String, count: int, err := "") -> void:
	if int(job.id) != _job_id:
		return
	for s in _status:
		if str(s.id) == id:
			s.state = state
			s.count = count
			s.error = err


func _merge(job: Dictionary, found: Array) -> void:
	var hide := no_p2p()
	var all: Array = job.all
	for s in found:
		if bool(s.is_p2p) and hide:
			job.p2p_hidden = int(job.p2p_hidden) + 1
			continue
		var k := stream_key(s)
		if (job.keys as Dictionary).has(k):
			continue
		job.keys[k] = true
		all.append(s)
	job.sorted = sort_streams(all, pref_quality(), pref_lang())
	var cb: Callable = job.cb
	if cb.is_valid() and int(job.id) == _job_id:
		cb.call((job.sorted as Array).duplicate(true))


func _addon_streams(job: Dictionary, a: Dictionary, type: String, video_id: String, order: int) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _addon_streams_arbeit(job, a, type, video_id, order)
	job.pending = int(job.pending) - 1
	_stream_step.emit()


func _addon_streams_arbeit(job: Dictionary, a: Dictionary, type: String, video_id: String, order: int) -> void:
	var r := await _fetch(resource_url(str(a.url), "stream", type, video_id), STREAM_TIMEOUT)
	var found: Array = []
	var err := ""
	if r.ok and r.data is Dictionary:
		var raw: Variant = r.data.get("streams", [])
		if raw is Array:
			found = await _streams_lesen(job, raw, func(s: Dictionary, i: int) -> Dictionary: return parse_stream(s, a, order * 1000 + i))
		if found.is_empty() and supports(a, "meta", type, split_video_id(video_id).meta_id):
			found = await _inline_streams(job, a, type, video_id, order)
	else:
		err = _http_reason(r, "Fehler").trim_suffix(".")
		(job.fails as Array).append("%s: %s" % [a.name, err])
	_set_status(job, str(a.id), "fehler" if err != "" else "fertig", found.filter(func(s): return not (bool(s.is_p2p) and no_p2p())).size(), err)
	_merge(job, found)


## Die Quellen einer Antwort lesen (lesen: Callable(Eintrag, Nummer) -> Quelle oder {}), über mehrere Bilder
## verteilt und höchstens STREAMS_JE_QUELLE. Früher alle auf einmal: 200 Quellen eines Addons hielten das Menü
## gemessen 100 ms an. Ist die Suche inzwischen eine andere, hört der Lauf auf.
func _streams_lesen(job: Dictionary, raw: Array, lesen: Callable) -> Array:
	var found: Array = []
	for i in mini(raw.size(), STREAMS_JE_QUELLE):
		if i > 0 and i % STREAMS_JE_BILD == 0:
			await get_tree().process_frame
			if int(job.id) != _job_id:
				break
		if raw[i] is Dictionary:
			var st: Dictionary = lesen.call(raw[i], i)
			if not st.is_empty():
				found.append(st)
	return found


## Nuvio: liefert ein Addon keine Streams, stehen sie manchmal direkt in den Folgen seiner Details.
func _inline_streams(job: Dictionary, a: Dictionary, type: String, video_id: String, order: int) -> Array:
	var meta_id := str(split_video_id(video_id).meta_id)
	var r := await _fetch(resource_url(str(a.url), "meta", type, meta_id), STREAM_TIMEOUT)
	var out: Array = []
	if not r.ok or not (r.data is Dictionary) or not (r.data.get("meta") is Dictionary):
		return out
	var vids: Variant = r.data.meta.get("videos", [])
	if not (vids is Array):
		return out
	for v in vids:
		if v is Dictionary and _s(v.get("id", "")) == video_id and v.get("streams") is Array:
			out.append_array(await _streams_lesen(job, v.streams, func(s: Dictionary, i: int) -> Dictionary: return parse_stream(s, a, order * 1000 + i)))
			if out.size() >= STREAMS_JE_QUELLE:
				break
	return out


## Untertitel aller Addons mit „subtitles“ für diesen Titel, parallel.
func subtitles(type: String, video_id: String) -> Array:
	# Titel eines eigenen Servers: nur seine Untertitel (mpv schickt dessen Schlüssel mit – nie an Fremde).
	if QB.owner_of(video_id) != "":
		return []
	if demo:
		await get_tree().process_frame
		return [
			{ "id": "demo-de", "url": "demo://untertitel/de.srt", "lang": "ger", "label": "Deutsch  ·  Demo-Untertitel" },
			{ "id": "demo-en", "url": "demo://untertitel/en.srt", "lang": "eng", "label": "Englisch  ·  Demo-Untertitel" },
		]
	var list: Array = []
	for a in addons:
		if bool(a.enabled) and supports(a, "subtitles", type, video_id):
			list.append({ "addon": a, "subs": [] })
	var box := { "left": list.size() }
	for j in list:
		_subs_one(j, type, video_id, box)
	while int(box.left) > 0:
		await _stream_step
	var out: Array = []
	var seen := {}
	for j in list:
		for s in j.subs:
			if not seen.has(str(s.url)):
				seen[str(s.url)] = true
				out.append(s)
	return out


func _subs_one(j: Dictionary, type: String, video_id: String, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _subs_one_arbeit(j, type, video_id, box)
	box.left = int(box.left) - 1
	_stream_step.emit()


func _subs_one_arbeit(j: Dictionary, type: String, video_id: String, box: Dictionary) -> void:
	var a: Dictionary = j.addon
	var r := await _fetch(resource_url(str(a.url), "subtitles", type, video_id), 15.0)
	if r.ok and r.data is Dictionary:
		j.subs = _parse_subs(r.data.get("subtitles", []), str(a.name))


# --- Plugins (JavaScript-Scraper wie Nuvio) ----------------------------------------------------

func plugins_enabled() -> bool:
	return bool(Config.get_value("movies.plugins_on", true))


func set_plugins_enabled(on: bool) -> void:
	if demo:
		return
	_set_cfg("movies.plugins_on", on)
	changed.emit()


func _save_repos() -> void:
	if demo:
		changed.emit()
		return
	_set_cfg("movies.plugin_repos", plugin_repos.duplicate(true))
	changed.emit()


## Repo-Adresse wie Nuvio: fremdes Schema → https, ohne „/“ am Ende, sonst …/manifest.json.
static func normalize_repo_url(url: String) -> String:
	var u := url.strip_edges()
	if u == "":
		return ""
	var se := u.find("://")
	if se > 0:
		if u.substr(0, se).to_lower() not in ["http", "https"]:
			u = "https://" + u.substr(se + 3)
	else:
		u = "https://" + u
	u = u.rstrip("/")
	if not u.get_file().to_lower().ends_with(".json"):
		u += "/manifest.json"
	return u


static func _safe_name(id: String) -> String:
	var out := ""
	for ch in id:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["-", "_", "."] else "_"
	return out


func _script_path(scraper_id: String) -> String:
	return Config.path("movies/plugins/%s.js" % _safe_name(scraper_id))


## Plugin-Repository hinzufügen (manifest.json mit „scrapers“), Skripte laden. "" oder Fehlertext.
func add_plugin_repo(url: String) -> String:
	error = ""
	var u := normalize_repo_url(url)
	if u == "":
		return _fail("Bitte die Adresse des Repositorys eingeben.")
	if demo:
		return _fail("Im Demo-Modus werden keine Plugins geladen.")
	for r in plugin_repos:
		if str(r.url).to_lower() == u.to_lower():
			return _fail("Dieses Repository ist schon eingetragen.")
	var res := await _fetch(u, 20.0)
	if not res.ok or not (res.data is Dictionary):
		return _fail(_http_reason(res, "Repository nicht erreichbar"))
	var man: Dictionary = res.data
	if man.has("pluginLists") and not man.has("scrapers"):
		return _fail("Das ist ein CloudStream-Repository (Android-Plugins). Die laufen unter Windows nicht.")
	if not (man.get("scrapers") is Array):
		return _fail("Unter dieser Adresse liegt kein Plugin-Repository (manifest.json ohne „scrapers“).")
	var repo := { "id": "r" + u.md5_text().substr(0, 10), "name": _s(man.get("name", u.get_base_dir().get_file())), "url": u,
		"enabled": true, "version": _s(man.get("version", "")), "description": _s(man.get("description", "")), "scrapers": [] }
	var missing := await _download_scrapers(repo, man.scrapers)
	plugin_repos.append(repo)
	_save_repos()
	_tell("plugins")
	if missing > 0:
		error = "%d von %d Scrapern ließen sich nicht laden." % [missing, (man.scrapers as Array).size()]
	return ""


func _download_scrapers(repo: Dictionary, infos: Array) -> int:
	var base := str(repo.url).get_base_dir()
	var old := {}
	for sc in repo.get("scrapers", []):
		old[str(sc.id)] = sc
	var list: Array = []
	var missing := 0
	for info in infos:
		if not (info is Dictionary) or _s(info.get("id", "")) == "" or _s(info.get("filename", "")) == "":
			missing += 1
			continue
		var fname := _s(info.filename)
		var code_url := fname if fname.begins_with("http") else base + "/" + fname.trim_prefix("/")
		var sid := "%s:%s" % [repo.id, _s(info.id)]
		var r: Dictionary = await _fetch_script(code_url, str(repo.url))
		var body: PackedByteArray = r.get("body", PackedByteArray())
		if not bool(r.ok) or body.is_empty() or body.size() > MAX_SCRIPT_BYTES:
			missing += 1
			if old.has(sid):
				list.append(old[sid])
			continue
		DirAccess.make_dir_recursive_absolute(_script_path(sid).get_base_dir())
		var f := FileAccess.open(_script_path(sid), FileAccess.WRITE)
		if f == null:
			missing += 1
			continue
		f.store_buffer(body)
		f.close()
		var types := _str_array(info.get("supportedTypes", ["movie", "tv"]))
		if types.is_empty():
			types = ["movie", "tv"]
		var manifest_on := bool(info.get("enabled", true))
		list.append({ "id": sid, "name": _s(info.get("name", info.id)), "version": _s(info.get("version", "")),
			"description": _s(info.get("description", "")), "types": types, "logo": _s(info.get("logo", "")),
			"enabled": bool((old[sid] as Dictionary).get("enabled", manifest_on)) if old.has(sid) else manifest_on,
			"formats": _str_array(info.get("formats", [])), "languages": _str_array(info.get("contentLanguage", [])),
			"settings": (old[sid] as Dictionary).get("settings", {}) if old.has(sid) else {} })
	repo.scrapers = list
	return missing


## Skript eines Scrapers laden. Die Adresse steht im fremden Manifest: nur vom Server des
## Repositorys selbst oder per https aus dem Internet – nie von diesem PC oder aus dem Heimnetz,
## auch nicht über eine Weiterleitung. Sonst holte Uzai (ohne Sandbox) etwa die Seite des Routers
## in den Plugin-Ordner, wo jedes Plugin sie lesen und ins Internet schicken könnte.
func _fetch_script(url: String, repo_url: String) -> Dictionary:
	var target := url
	for hop in Sicher.MAX_HOPS + 1:
		if not (Sicher.same_origin(target, repo_url) or await Sicher.public_url_async(target, true)):
			return { "ok": false, "code": 0, "body": PackedByteArray() }
		var r: Dictionary = await Net.request(target, PackedStringArray(), HTTPClient.METHOD_GET, "", 30.0, "api", MAX_SCRIPT_BYTES + 1, false)
		var code := int(r.get("code", 0))
		if code < 300 or code >= 400:
			return r
		target = Sicher.redirect_target(target, Net.header(r, "location"))
	return { "ok": false, "code": 0, "body": PackedByteArray() }


func remove_plugin_repo(id: String) -> void:
	for i in plugin_repos.size():
		if str(plugin_repos[i].id) == id:
			if not demo:
				for sc in plugin_repos[i].get("scrapers", []):
					DirAccess.remove_absolute(_script_path(str(sc.id)))
			plugin_repos.remove_at(i)
			_save_repos()
			_tell("plugins")
			return


func set_scraper_enabled(id: String, on: bool) -> void:
	for repo in plugin_repos:
		for sc in repo.get("scrapers", []):
			if str(sc.id) == id:
				sc.enabled = on
				_save_repos()
				return


func _active_scrapers(type: String) -> Array:
	var out: Array = []
	if not plugins_enabled():
		return out
	for repo in plugin_repos:
		if not bool(repo.get("enabled", true)):
			continue
		for sc in repo.get("scrapers", []):
			if bool(sc.get("enabled", true)) and scraper_supports(sc, type):
				out.append(sc)
	return out


## JavaScript-Laufzeit für die Scraper: Deno aus Uzais Werkzeugen (wie für YouTube).
## Zum Testen lässt sich eine andere angeben (UZAI_JS_RUNTIME, z. B. Node 22).
func plugin_runtime() -> Dictionary:
	var env := Config.probe_env("UZAI_JS_RUNTIME")
	if env != "":
		return { "exe": env, "kind": "node" if env.get_file().to_lower().begins_with("node") else "deno" }
	if YouTube.has_deno():
		return { "exe": YouTube.deno_path(), "kind": "deno" }
	return {}


## Runner und crypto-js in den Datenordner legen (Deno liest echte Dateien).
static func prepare_runtime() -> String:
	var dir := Config.path("movies/runtime")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["runner.js", "crypto-js.js"]:
		var src := FileAccess.get_file_as_bytes("res://assets/plugins/" + f)
		var dest := dir.path_join(f)
		if src.is_empty() or (FileAccess.file_exists(dest) and FileAccess.get_file_as_bytes(dest) == src):
			continue
		var fa := FileAccess.open(dest, FileAccess.WRITE)
		if fa:
			fa.store_buffer(src)
			fa.close()
	return dir


func _plugin_streams(job: Dictionary, scrapers: Array, type: String, meta_id: String, season: int, episode: int) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _plugin_streams_arbeit(job, scrapers, type, meta_id, season, episode)
	job.pending = int(job.pending) - 1
	_stream_step.emit()


func _plugin_streams_arbeit(job: Dictionary, scrapers: Array, type: String, meta_id: String, season: int, episode: int) -> void:
	var rt := plugin_runtime()
	var fail_all := func(msg: String) -> void:
		for sc in scrapers:
			_set_status(job, "plugin:" + str(sc.id), "fehler", 0, msg)
		(job.fails as Array).append("Plugins: " + msg)
	if rt.is_empty():
		fail_all.call("Deno fehlt (unter Videos „Jetzt einrichten“)")
	else:
		var tmdb := await _tmdb_id(type, meta_id)
		if tmdb == "":
			fail_all.call("keine TMDB-ID für diesen Titel")
		else:
			await _run_plugins(job, rt, scrapers, tmdb, type, season, episode)


func _run_plugins(job: Dictionary, rt: Dictionary, scrapers: Array, tmdb: String, type: String, season: int, episode: int) -> void:
	var dir := prepare_runtime()
	var list: Array = []
	var by_id := {}
	for sc in scrapers:
		var file := _script_path(str(sc.id))
		if not FileAccess.file_exists(file):
			_set_status(job, "plugin:" + str(sc.id), "fehler", 0, "Skript fehlt – Repository neu laden")
			continue
		by_id[str(sc.id)] = sc
		list.append({ "id": str(sc.id), "name": str(sc.name), "file": ProjectSettings.globalize_path(file),
			"settings": sc.get("settings", {}), "mediaType": plugin_media_type(type, sc.get("types", []), season, episode) })
	if list.is_empty():
		return
	var job_file := dir.path_join("auftrag-%d.json" % Time.get_ticks_usec())
	var spec := {
		"tmdbId": tmdb, "mediaType": plugin_media_type(type, [], season, episode), "season": null, "episode": null,
		"tmdbKey": tmdb_key(), "timeoutMs": PLUGIN_TIMEOUT_MS, "cryptoJs": ProjectSettings.globalize_path(dir.path_join("crypto-js.js")),
		"scrapers": list,
	}
	if season > 0 and episode > 0:
		spec.season = season
		spec.episode = episode
	Config.write_json(job_file, spec)
	var args := PackedStringArray()
	var runner := ProjectSettings.globalize_path(dir.path_join("runner.js"))
	if str(rt.kind) == "deno":
		var read := PackedStringArray([ProjectSettings.globalize_path(dir), ProjectSettings.globalize_path(Config.path("movies/plugins"))])
		args = deno_args(runner, ProjectSettings.globalize_path(job_file), read, own_addresses())
		if args.is_empty():
			DirAccess.remove_absolute(job_file)
			for sid in by_id:
				_set_status(job, "plugin:" + str(sid), "fehler", 0, "Der Pfad zum Datenordner enthält ein Komma – Plugins laufen dort nicht abgesichert")
			return
		# Deno legt seinen Zwischenspeicher sonst in AppData ab; so bleibt alles im Datenordner.
		OS.set_environment("DENO_DIR", ProjectSettings.globalize_path(Config.path("tools/deno-cache")))
	else:
		args = PackedStringArray([runner, ProjectSettings.globalize_path(job_file)])
	var box := { "lines": [], "done": false, "err": PackedByteArray(), "cancel": false, "started": false }
	var mutex := Mutex.new()
	var t := Thread.new()
	t.start(_plugin_worker.bind(str(rt.exe), args, box, mutex, float(PLUGIN_TIMEOUT_MS) / 1000.0 + 20.0))
	var pending := by_id.duplicate()
	var order := 0
	while true:
		mutex.lock()
		var lines: Array = (box.lines as Array).duplicate()
		(box.lines as Array).clear()
		var done := bool(box.done)
		mutex.unlock()
		for line in lines:
			var msg: Variant = Fremd.json(str(line))
			if not (msg is Dictionary):
				continue
			if str(msg.get("event", "")) == "fatal":
				for sid in pending.keys():
					_set_status(job, "plugin:" + str(sid), "fehler", 0, str(msg.get("error", "Laufzeit-Fehler")))
				pending.clear()
			elif str(msg.get("event", "")) == "result":
				var sid := str(msg.get("id", ""))
				var sc: Dictionary = by_id.get(sid, {})
				pending.erase(sid)
				if sc.is_empty():
					continue
				if not bool(msg.get("ok", false)):
					_set_status(job, "plugin:" + sid, "fehler", 0, str(msg.get("error", "")))
					(job.fails as Array).append("%s: %s" % [sc.name, msg.get("error", "")])
					continue
				var found: Array = []
				var raw: Variant = msg.get("streams", [])
				if raw is Array:
					var ab := order
					found = await _streams_lesen(job, raw, func(it: Dictionary, i: int) -> Dictionary: return parse_plugin_result(it, sc, 500000 + ab + i))
					order += mini((raw as Array).size(), STREAMS_JE_QUELLE)
				_set_status(job, "plugin:" + sid, "fertig", found.filter(func(s): return not (bool(s.is_p2p) and no_p2p())).size())
				_merge(job, found)
		if done:
			break
		await get_tree().process_frame
	t.wait_to_finish()
	for sid in pending.keys():
		_set_status(job, "plugin:" + str(sid), "fehler", 0, "keine Antwort (Zeitlimit)")
	var err: PackedByteArray = box.err
	var logf := FileAccess.open(Config.path("logs/plugins.log"), FileAccess.WRITE)
	if logf:
		logf.store_buffer(err)
		logf.close()
	DirAccess.remove_absolute(job_file)


## Aufruf für Deno mit den Rechten oben. Leer, wenn ein Pfad ein Komma enthält: Deno trennt die
## erlaubten Ordner mit Kommas, ein solcher Pfad ließe sich nicht genau freigeben. own: die
## Adressen dieses PCs (own_addresses) – Deno kennt keine IPv6-Bereiche, so sind wenigstens der PC
## selbst und das Lauschen an seinen IPv6-Adressen gesperrt (siehe docs/SECURITY.md).
static func deno_args(runner: String, job_file: String, read_dirs: PackedStringArray, own: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	for p in read_dirs:
		if p.contains(","):
			return PackedStringArray()
	var deny := PLUGIN_DENY_NET
	for a in own:
		if a.is_valid_ip_address():
			deny += ",[%s]" % a if a.contains(":") else "," + a
	return PackedStringArray(["run", "--quiet", "--no-prompt", "--no-config", "--no-remote", "--no-npm",
		"--v8-flags=--max-old-space-size=%d" % PLUGIN_HEAP_MB, "--allow-net", "--deny-net=" + deny,
		"--allow-read=" + ",".join(read_dirs), runner, job_file])


## Alle Adressen dieses PCs ohne Zonenangabe (fe80::1%12 → fe80::1).
static func own_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		var a := str(ip).get_slice("%", 0)
		if a.is_valid_ip_address() and not out.has(a):
			out.append(a)
	return out


## Läuft im Hintergrund: Laufzeit ohne Fenster starten, stdout zeilenweise weiterreichen.
func _plugin_worker(exe: String, args: PackedStringArray, box: Dictionary, mutex: Mutex, timeout: float) -> void:
	var info := OS.execute_with_pipe(exe, Helper.win_args(args), false)
	if info.is_empty():
		mutex.lock()
		box.lines.append(JSON.stringify({ "event": "fatal", "error": "JavaScript-Laufzeit startet nicht" }))
		box.done = true
		mutex.unlock()
		return
	var io: FileAccess = info.get("stdio")
	var er: FileAccess = info.get("stderr")
	var pid := int(info.get("pid", 0))
	var t0 := Time.get_ticks_msec()
	var buf := PackedByteArray()
	var errbuf := PackedByteArray()
	var gesamt := 0
	while true:
		var a := io.get_buffer(65536)
		var b := er.get_buffer(65536) if er else PackedByteArray()
		if errbuf.size() < 2000000:
			errbuf.append_array(b)
		if not a.is_empty():
			buf.append_array(a)
			var got: Array = []
			while true:
				var nl := buf.find(10)
				if nl < 0:
					break
				got.append(buf.slice(0, nl).get_string_from_utf8())
				buf = buf.slice(nl + 1)
			# Ein fremdes Plugin, das ohne Zeilenende oder endlos Zeilen schreibt, füllte sonst den Speicher (und find()
			# lief jedes Mal über alles): Grenze für die offene Zeile und alle Zeilen eines Laufs, dann beenden.
			gesamt += got.size()
			var zu_viel := buf.size() > PLUGIN_ZEILE_MAX or gesamt > PLUGIN_ZEILEN_MAX
			if not got.is_empty() and not zu_viel:
				mutex.lock()
				(box.lines as Array).append_array(got)
				mutex.unlock()
			if zu_viel:
				OS.kill(pid)
				mutex.lock()
				box.lines.append(JSON.stringify({ "event": "fatal", "error": "Plugin schreibt zu viel" }))
				mutex.unlock()
				break
		if a.is_empty() and b.is_empty():
			if not OS.is_process_running(pid):
				var rest := io.get_buffer(1 << 22)
				buf.append_array(rest)
				var tail := buf.get_string_from_utf8()
				mutex.lock()
				for l in tail.split("\n"):
					if l.strip_edges() != "":
						(box.lines as Array).append(l)
				mutex.unlock()
				break
			if Time.get_ticks_msec() - t0 > timeout * 1000.0:
				OS.kill(pid)
				break
			OS.delay_msec(15)
	mutex.lock()
	box.err = errbuf
	box.done = true
	mutex.unlock()


# --- Bibliothek ---------------------------------------------------------------------------------

func in_library(id: String) -> bool:
	for e in data.library:
		if str(e.id) == id:
			return true
	return false


## Merken oder entfernen. Gibt zurück, ob der Titel jetzt in der Bibliothek ist.
func toggle_library(meta_preview: Dictionary) -> bool:
	var id := str(meta_preview.get("id", ""))
	if id == "":
		return false
	if in_library(id):
		data.library = (data.library as Array).filter(func(e): return str(e.id) != id)
		_dirty()
		changed.emit()
		_tell("library_remove", { "id": id, "type": str(meta_preview.get("type", "movie")) })
		return false
	var e := _preview_only(meta_preview)
	e["added"] = int(Time.get_unix_time_from_system())
	(data.library as Array).push_front(e)
	_dirty()
	changed.emit()
	_tell("library_add", { "entry": e })
	return true


func library_items() -> Array:
	return QB.kid_filter((data.library as Array).duplicate(true), kid_rules())


static func _preview_only(m: Dictionary) -> Dictionary:
	var out := {}
	for k in ["id", "type", "name", "poster", "background", "logo", "description", "year", "imdb_rating", "genres", "addon_id", "release_info", "tmdb_id", "age",
			"content_rating", "family"]:
		if m.has(k):
			out[k] = m[k] if not (m[k] is Array) else (m[k] as Array).duplicate()
	return out


# --- Fortschritt, gesehen, Weiterschauen ----------------------------------------------------------

var _cw_cache: Array = []
var _cw_valid := false


## Zwischengespeichert, bis sich Fortschritt, Titel oder Ausblendungen ändern (_dirty).
func continue_watching() -> Array:
	if not _cw_valid:
		_cw_cache = merge_continue(build_continue(data), Quellen.continue_items(), Quellen.active_kinds())
		_cw_valid = true
	return QB.kid_filter(_cw_cache.duplicate(), kid_rules())


## Weiterschauen aus Uzai und von den Quellen zusammen: je Titel der neuere Stand. Ein Titel eines
## Servers, den Uzai zuletzt abgespielt hat, bleibt nur, solange der Server ihn nicht inzwischen
## (nach diesem Stand) aus seinem Weiterschauen genommen hat; abgemeldete Server fallen weg.
static func merge_continue(local: Array, remote: Array, kinds: Array) -> Array:
	var by_id := {}
	var fetched := {}
	for it in remote:
		var k := str(it.get("source", ""))
		fetched[k] = maxi(int(fetched.get(k, 0)), int(it.get("cw_at", 0)))
	var out: Array = []
	for it in local:
		var owner := QB.owner_of(str(it.get("id", "")))
		if owner != "" and not (owner in kinds):
			continue
		if owner != "" and int(fetched.get(owner, 0)) > int(it.get("updated", 0)) + 60 and not remote.any(func(r): return str(r.id) == str(it.id)):
			continue
		by_id[str(it.id)] = out.size()
		out.append(it)
	for it in remote:
		var i: int = by_id.get(str(it.id), -1)
		if i < 0:
			by_id[str(it.id)] = out.size()
			out.append(it)
		elif int(it.get("updated", 0)) > int(out[i].get("updated", 0)):
			out[i] = it
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("updated", 0)) > int(b.get("updated", 0)))
	return out.slice(0, 40)


## Stand vom Server (Plex, Jellyfin) übernehmen, wenn er neuer ist als der in Uzai – so setzt
## „Fortsetzen“ auch dort an, wo du auf einem anderen Gerät aufgehört hast.
func _apply_server_progress(meta_id: String, m: Dictionary) -> void:
	var sp: Variant = m.get("server_progress", {})
	if not (sp is Dictionary) or (sp as Dictionary).is_empty():
		return
	var touched := false
	for vid in sp:
		var e: Dictionary = sp[vid]
		var have: Dictionary = (data.progress as Dictionary).get(meta_id, {}).get(vid, {})
		if not have.is_empty() and int(have.get("updated", 0)) >= int(e.get("updated", 0)):
			continue
		if not data.progress.has(meta_id):
			data.progress[meta_id] = {}
		var v := _video_info({ "videos": m.get("videos", []) }, str(vid))
		data.progress[meta_id][vid] = { "position": float(e.position), "duration": float(e.duration), "watched": bool(e.watched),
			"updated": int(e.updated) if int(e.updated) > 0 else int(have.get("updated", 0)), "season": int(v.get("season", 0)),
			"episode": int(v.get("episode", 0)), "title": str(v.get("title", "")), "thumbnail": str(v.get("thumbnail", "")) }
		touched = true
	if touched:
		_remember_item(m)
		_dirty()


## Aus Weiterschauen nehmen (kommt wieder, sobald weitergeschaut wird). „Als Nächstes“ wie Nuvio
## dauerhaft für diese Folge ausblenden.
func remove_continue(id: String) -> void:
	for it in build_continue(data):
		if str(it.id) == id and bool(it.next_up):
			var entries: Dictionary = data.progress.get(id, {})
			var best := { "s": 0, "e": 0 }
			for vid in entries.keys():
				var e: Dictionary = entries[vid]
				if bool(e.get("watched", false)) \
						and (int(e.get("season", 0)) > int(best.s) or int(e.get("season", 0)) == int(best.s) and int(e.get("episode", 0)) > int(best.e)):
					best = { "s": int(e.get("season", 0)), "e": int(e.get("episode", 0)) }
			(data.dismissed as Array).append("%s:%d:%d" % [id, int(best.s), int(best.e)])
	# Angefangene Folgen/Filme dieses Titels auch im Nuvio-Konto aus Weiterschauen nehmen.
	var keys: Array = []
	for vid in (data.progress.get(id, {}) as Dictionary).keys():
		var pe: Dictionary = data.progress[id][vid]
		if not bool(pe.get("watched", false)) and float(pe.get("position", 0)) > 0.0:
			keys.append(id if int(pe.get("season", 0)) <= 0 and int(pe.get("episode", 0)) <= 0
					else "%s_s%de%d" % [id, int(pe.get("season", 0)), int(pe.get("episode", 0))])
	if not keys.is_empty():
		_tell("continue_removed", { "keys": keys })
	data.hidden[id] = int(Time.get_unix_time_from_system())
	_dirty()
	changed.emit()


func progress(meta_id: String, video_id: String) -> Dictionary:
	var e: Dictionary = (data.progress as Dictionary).get(meta_id, {}).get(video_id, {})
	var dur := float(e.get("duration", 0.0))
	return { "position": float(e.get("position", 0.0)), "duration": dur, "watched": bool(e.get("watched", false)),
		"updated": int(e.get("updated", 0)), "fraction": clampf(float(e.get("position", 0.0)) / dur, 0.0, 1.0) if dur > 0 else 0.0 }


func watched(meta_id: String, video_id: String) -> bool:
	return bool((data.progress as Dictionary).get(meta_id, {}).get(video_id, {}).get("watched", false))


## Gesehen setzen oder aufheben. Bei einer Serie mit video_id == meta_id alle ausgestrahlten Folgen.
## meta (optional) merkt Name, Bild und Folgenliste für Weiterschauen.
func set_watched(meta_id: String, video_id: String, on: bool, meta_info := {}) -> void:
	if not meta_info.is_empty():
		_remember_item(meta_info)
	var item: Dictionary = data.items.get(meta_id, {})
	var targets: Array = []
	if video_id == meta_id and str(item.get("type", "")) == "series" and not (item.get("videos", []) as Array).is_empty():
		for v in item.videos:
			if int(v.season) > 0 and bool(v.get("available", true)):
				targets.append(v)
	else:
		targets.append(_video_info(item, video_id))
	var now := int(Time.get_unix_time_from_system())
	if not data.progress.has(meta_id):
		data.progress[meta_id] = {}
	var entries: Dictionary = data.progress[meta_id]
	var kind := str(item.get("type", "series" if video_id != meta_id else "movie"))
	for v in targets:
		var vid := str(v.id)
		if on:
			var e: Dictionary = entries.get(vid, {})
			e.merge({ "position": 0.0, "duration": float(e.get("duration", 0.0)), "watched": true, "updated": now,
				"season": int(v.get("season", 0)), "episode": int(v.get("episode", 0)), "title": str(v.get("title", "")), "thumbnail": str(v.get("thumbnail", "")) }, true)
			e.position = 0.0
			e.watched = true
			e.updated = now
			entries[vid] = e
			_tell("watched", { "meta_id": meta_id, "video_id": vid, "type": kind, "on": true, "entry": e.duplicate() })
		else:
			var gone: Dictionary = entries.get(vid, { "season": int(v.get("season", 0)), "episode": int(v.get("episode", 0)) })
			entries.erase(vid)
			_tell("watched", { "meta_id": meta_id, "video_id": vid, "type": kind, "on": false, "entry": gone })
	if entries.is_empty():
		data.progress.erase(meta_id)
	if QB.owner_of(meta_id) != "":
		Quellen.mark_watched(targets.map(func(v): return str(v.id)), on)
	_dirty()
	progress_changed.emit(meta_id)
	changed.emit()


func _video_info(item: Dictionary, video_id: String) -> Dictionary:
	for v in item.get("videos", []):
		if str(v.id) == video_id:
			return v
	var sv := split_video_id(video_id)
	return { "id": video_id, "season": int(sv.season), "episode": int(sv.episode), "title": "", "thumbnail": "" }


## Name, Bilder und Folgenliste merken (für Weiterschauen ohne Netz).
func _remember_item(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	if id == "":
		return
	var it := _preview_only(m)
	var old: Dictionary = data.items.get(id, {})
	var vids: Array = []
	for v in m.get("videos", []):
		vids.append({ "id": str(v.id), "season": int(v.season), "episode": int(v.episode), "title": str(v.get("title", "")),
			"released": str(v.get("released", "")), "thumbnail": str(v.get("thumbnail", "")), "available": bool(v.get("available", true)) })
	it["videos"] = vids if not vids.is_empty() else old.get("videos", [])
	data.items[id] = it
	_cw_valid = false


func remember(m: Dictionary) -> void:
	_remember_item(m)


# --- Nuvio-Konto (NuvioSync) -------------------------------------------------------------------

## Startseite beim nächsten Mal neu aufbauen (Layout aus Nuvio geändert).
func invalidate_home() -> void:
	_home_cache = {}
	_home_gen += 1
	_home_disk_read = true
	changed.emit()


## Addons genau wie im Nuvio-Konto: bekannte behalten ihr Manifest, neue werden gleichzeitig
## geladen. true, wenn sich etwas geändert hat (nur dann baut die Startseite neu).
func apply_remote_addons(list: Array) -> bool:
	if demo:
		return false
	var known := {}
	for e in _entries:
		known[str(e.get("url", ""))] = e
	var out: Array = []
	var box := { "left": 0 }
	for r in list:
		var u := str(r.url)
		var e: Dictionary = (known[u] as Dictionary).duplicate(true) if known.has(u) else { "url": u, "manifest": {} }
		e["enabled"] = bool(r.get("enabled", true))
		out.append(e)
		if (e.get("manifest", {}) as Dictionary).is_empty():
			box.left = int(box.left) + 1
			_fetch_manifest_into(e, box)
	while int(box.left) > 0:
		await _stream_step
	# Nur Adresse, Schalter und Manifest-Version vergleichen – nicht ganze Manifeste.
	var sig := func(list_: Array) -> String:
		return ",".join(
				PackedStringArray(list_.map(func(x): return "%s|%s|%s" % [str(x.get("url", "")), str(x.get("enabled", true)),
				str((x.get("manifest", {}) as Dictionary).get("version", "")) if x.get("manifest") is Dictionary else ""])))
	if sig.call(out) == sig.call(_entries):
		return false
	_entries = out
	_applying = true
	_save_entries()
	_applying = false
	return true


func _fetch_manifest_into(e: Dictionary, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _fetch_manifest_into_arbeit(e, box)
	box.left = int(box.left) - 1
	_stream_step.emit()


func _fetch_manifest_into_arbeit(e: Dictionary, box: Dictionary) -> void:
	var u := str(e.url)
	var res := await _fetch(u, 15.0)
	if res.ok and res.data is Dictionary and not parse_manifest(res.data, u).is_empty():
		e["manifest"] = res.data


## Plugin-Repositorys wie im Nuvio-Konto: fehlende laden, übrige entfernen, an/aus übernehmen.
func apply_remote_plugins(list: Array) -> void:
	if demo:
		return
	_applying = true
	var want := {}
	for r in list:
		want[str(r.url).to_lower()] = r
	for repo in plugin_repos.duplicate():
		if not want.has(str(repo.url).to_lower()):
			remove_plugin_repo(str(repo.id))
	for r in list:
		var have := false
		for repo in plugin_repos:
			if str(repo.url).to_lower() == str(r.url).to_lower():
				have = true
				if bool(repo.get("enabled", true)) != bool(r.get("enabled", true)):
					repo.enabled = bool(r.get("enabled", true))
					_save_repos()
		if not have:
			await add_plugin_repo(str(r.url))
			for repo in plugin_repos:
				if str(repo.url).to_lower() == str(r.url).to_lower() and not bool(r.get("enabled", true)):
					repo.enabled = false
					_save_repos()
	_applying = false


## Bibliothek (genau wie im Konto) und Fortschritt/Gesehen (schon zusammengeführt) aus Nuvio übernehmen.
func apply_remote_data(lib: Array, merged_progress: Dictionary) -> void:
	if demo:
		return
	var old := {}
	for e in data.library:
		old[str(e.id)] = e
	var newlib: Array = []
	for e in lib:
		var m: Dictionary = e.duplicate(true)
		if old.has(str(m.id)):
			for k in ["logo", "addon_id", "tmdb_id"]:
				if str((old[str(m.id)] as Dictionary).get(k, "")) != "" and str(m.get(k, "")) == "":
					m[k] = old[str(m.id)][k]
		newlib.append(m)
	var same: bool = JSON.stringify(newlib) == JSON.stringify(data.library) and JSON.stringify(merged_progress) == JSON.stringify(data.progress)
	if same:
		return
	data.library = newlib
	for e in lib:
		if not (data.items as Dictionary).has(str(e.id)):
			data.items[str(e.id)] = _preview_only(e)
	data.progress = merged_progress
	_dirty()
	changed.emit()


func notify_changed() -> void:
	_cw_valid = false
	changed.emit()


## Fortschritt speichern; ab 90 % gilt es als gesehen.
## periodic: Zwischenstand während der Wiedergabe (alle 5 s). movies.json (bei großen Konten
## mehrere MB) wurde früher jedes Mal ganz neu geschrieben; jetzt höchstens jede Minute, dazu
## sofort bei Stopp, Ende und Wechsel.
var _periodic_at := 0


func record(meta_id: String, video_id: String, pos: float, dur: float, periodic := false) -> void:
	if meta_id == "" or video_id == "":
		return
	var item: Dictionary = data.items.get(meta_id, {})
	var v := _video_info(item, video_id)
	if not data.progress.has(meta_id):
		data.progress[meta_id] = {}
	var entries: Dictionary = data.progress[meta_id]
	var e: Dictionary = entries.get(video_id, {})
	var done := dur > 0.0 and pos >= dur * WATCHED_AT
	e.merge({ "season": int(v.get("season", 0)), "episode": int(v.get("episode", 0)), "title": str(v.get("title", "")), "thumbnail": str(v.get("thumbnail", "")) },
			true)
	e["position"] = 0.0 if done else pos
	e["duration"] = dur if dur > 0.0 else float(e.get("duration", 0.0))
	e["watched"] = done or (bool(e.get("watched", false)) and pos < 10.0)
	e["updated"] = int(Time.get_unix_time_from_system())
	entries[video_id] = e
	if periodic and Time.get_ticks_msec() - _periodic_at < 60000:
		_cw_valid = false
		return
	_periodic_at = Time.get_ticks_msec()
	_dirty()
	progress_changed.emit(meta_id)
	_tell("progress", { "meta_id": meta_id, "video_id": video_id, "entry": e.duplicate(),
		"type": str(item.get("type", "series" if video_id != meta_id else "movie")) })


## Nächste Folge nach video_id in den Folgen dieser Meta (Video oder leer).
func next_episode(meta_d: Dictionary, video_id: String) -> Dictionary:
	var vids: Array = meta_d.get("videos", [])
	var cur := {}
	for v in vids:
		if str(v.id) == video_id:
			cur = v
	if cur.is_empty():
		var sv := split_video_id(video_id)
		cur = { "season": int(sv.season), "episode": int(sv.episode) }
	return next_video(vids, int(cur.get("season", 0)), int(cur.get("episode", 0)), video_id)


# --- Abspielen -------------------------------------------------------------------------------

## Eintrag für Video (mpv): Adresse, Kopfzeilen, Titel für die Uzai-Leiste, Bezug zum Titel.
func video_item(meta_d: Dictionary, video_id: String, stream: Dictionary, opts := {}) -> Dictionary:
	var is_series := str(meta_d.get("type", "")) == "series" and video_id != str(meta_d.get("id", ""))
	var v := {}
	for x in meta_d.get("videos", []):
		if str(x.id) == video_id:
			v = x
	var title := str(meta_d.get("name", ""))
	var info := PackedStringArray()
	if is_series:
		if int(v.get("season", 0)) > 0:
			info.append("Staffel %d · Folge %d" % [int(v.season), int(v.episode)])
		if str(v.get("title", "")) != "":
			info.append(str(v.title))
	elif str(meta_d.get("year", "")) != "":
		info.append(str(meta_d.year))
	var q := int(stream.get("quality", 0))
	if q > 0:
		info.append("%dp" % q if q != 2160 else "4K")
	if str(stream.get("hdr", "")) != "":
		info.append(str(stream.hdr))
	var nxt := next_episode(meta_d, video_id) if is_series else {}
	var media_title := title
	if is_series and int(v.get("season", 0)) > 0:
		media_title = "%s – S%02dE%02d" % [title, int(v.season), int(v.episode)]
	return {
		"id": "film:" + video_id, "url": str(stream.get("url", "")), "title": str(opts.get("title", title)),
		"channel": str(stream.get("addon_name", "")), "info": "  ·  ".join(info), "media_title": media_title,
		"thumb": str(v.get("thumbnail", "")) if str(v.get("thumbnail", "")) != "" else str(meta_d.get("background", "")),
		"duration": 0, "headers": (stream.get("headers", {}) as Dictionary).duplicate(),
		"subtitles": (stream.get("subtitles", []) as Array).duplicate(true),
		"next_title": ("Folge %d: %s" % [int(nxt.episode), str(nxt.title)]) if not nxt.is_empty() else "",
		"movies": { "meta_id": str(meta_d.get("id", "")), "video_id": video_id, "type": str(meta_d.get("type", "")) },
	}


## Abspielen über mpv. "" = läuft, sonst Fehlertext. opts: resume (Standard true), start (Sekunden),
## title (für die Leiste), subtitles (zusätzliche Untertitel). Addon-Untertitel kommen von selbst dazu.
func play(meta_d: Dictionary, video_id: String, stream: Dictionary, opts := {}) -> String:
	error = ""
	if bool(stream.get("is_p2p", false)):
		return _fail("P2P-Streams spielt Uzai nicht ab.")
	if str(stream.get("url", "")) == "":
		return _fail("Dieser Stream hat keine Adresse.")
	if not demo and Config.is_windows() and not YouTube.has_mpv():
		return _fail("mpv fehlt – unter Videos „Jetzt einrichten“ wählen.")
	var meta_id := str(meta_d.get("id", ""))
	_remember_item(meta_d)
	var start := 0.0
	if opts.has("start"):
		start = float(opts.start)
	elif bool(opts.get("resume", true)):
		var p := progress(meta_id, video_id)
		if not bool(p.watched) and float(p.position) > 10.0 and (float(p.duration) <= 0.0 or float(p.position) < float(p.duration) * 0.95):
			start = maxf(0.0, float(p.position) - 3.0)
	var item := video_item(meta_d, video_id, stream, opts)
	var extra: Array = opts.get("subtitles", [])
	(item.subtitles as Array).append_array(extra)
	cancel_autoplay()
	# Läuft schon etwas aus „Filme“ (anderer Stream, andere Folge): dessen Stelle zuerst merken.
	if not _now.is_empty() and Video.active:
		_record_now()
	_now = { "meta": meta_d.duplicate(true), "video_id": video_id, "stream": stream.duplicate(true), "item_id": str(item.id) }
	_save_t = 0.0
	Video.play([item], 0, { "start": start })
	_attach_addon_subs(str(meta_d.get("type", "")), video_id, str(item.id))
	Quellen.playback_started(video_id, stream)
	return ""


func _attach_addon_subs(type: String, video_id: String, item_id: String) -> void:
	var subs := await subtitles(type, video_id)
	if subs.is_empty() or not Video.active or str(Video.video.get("id", "")) != item_id:
		return
	Video.add_subtitles(subs)


## Läuft gerade ein Titel aus „Filme“? (für Leiste und Player)
func now_playing() -> Dictionary:
	return _now.duplicate(true) if not _now.is_empty() else {}


func _on_video_started(v: Dictionary) -> void:
	if not v.has("movies") or _now.is_empty() or str(v.get("id", "")) != str(_now.item_id):
		_now = {}


func _on_video_stopped() -> void:
	if _now.is_empty():
		return
	_record_now()
	var dur := Video.duration
	Quellen.playback_stopped(str(_now.video_id), dur if Video.at_end and dur > 0.0 else Video.pos, dur)
	_now = {}
	changed.emit()


func _record_now(periodic := false) -> void:
	if _now.is_empty() or not (Video.video.has("movies")) or str(Video.video.get("id", "")) != str(_now.item_id):
		return
	var dur := Video.duration
	var pos := Video.pos
	if Video.at_end and dur > 0.0:
		pos = dur
	record(str(_now.meta.id), str(_now.video_id), pos, dur, periodic)
	if periodic:
		Quellen.playback_progress(str(_now.video_id), pos, dur, Video.paused)


func _on_video_end() -> void:
	if _now.is_empty():
		return
	_record_now()
	var m: Dictionary = _now.meta
	var nxt := next_episode(m, str(_now.video_id)) if str(m.get("type", "")) == "series" else {}
	ended.emit(m.duplicate(true), str(_now.video_id), nxt)
	changed.emit()
	if not nxt.is_empty() and bool(Config.get_value("movies.autoplay_next", true)):
		_autoplay_next = nxt
		_autoplay_at = Time.get_ticks_msec() / 1000.0 + AUTOPLAY_DELAY


## Sekunden bis die nächste Folge von selbst startet (-1 = nichts geplant).
func autoplay_left() -> float:
	if _autoplay_at <= 0.0:
		return -1.0
	return maxf(0.0, _autoplay_at - Time.get_ticks_msec() / 1000.0)


func cancel_autoplay() -> void:
	_autoplay_at = 0.0
	_autoplay_next = {}


## Nächste Folge abspielen: Stream aus derselben Gruppe (bingeGroup) wie zuletzt, sonst der beste.
func play_next() -> String:
	cancel_autoplay()
	if _now.is_empty():
		return _fail("Es läuft nichts.")
	var m: Dictionary = _now.meta
	var nxt := next_episode(m, str(_now.video_id))
	if nxt.is_empty():
		return _fail("Keine weitere Folge.")
	var last: Dictionary = _now.stream
	var list := await streams(str(m.get("type", "series")), str(nxt.id))
	if list.is_empty():
		return _fail("Für die nächste Folge gibt es keinen Stream." if error == "" else error)
	var pick := pick_next_stream(list, last)
	return play(m, str(nxt.id), pick, { "resume": false })


## Wie Stremio/Nuvio: gleiche bingeGroup und gleiches Addon bevorzugen, sonst den ersten.
static func pick_next_stream(list: Array, last: Dictionary) -> Dictionary:
	var bg := str(last.get("binge_group", ""))
	if bg != "":
		for s in list:
			if str(s.get("binge_group", "")) == bg and str(s.addon_id) == str(last.get("addon_id", "")):
				return s
	for s in list:
		if str(s.addon_id) == str(last.get("addon_id", "")) and int(s.quality) == int(last.get("quality", 0)):
			return s
	return list[0]


func _process(dt: float) -> void:
	if _now.is_empty():
		return
	if Video.active and Video.video.has("movies") and str(Video.video.get("id", "")) == str(_now.item_id):
		_save_t += dt
		if _save_t >= 5.0:
			_save_t = 0.0
			if not Video.loading and Video.pos > 1.0:
				_record_now(true)
	if _autoplay_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _autoplay_at:
		_autoplay_at = 0.0
		play_next()


# --- Demo ----------------------------------------------------------------------------------

func _demo_catalog(type: String, catalog_id: String, skip: int, extra: Dictionary) -> Array:
	var out: Array = []
	for r in _demo.rows:
		if str(r.get("type", "")) == type and str(r.get("catalog_id", "")) == catalog_id:
			out = (r.items as Array).duplicate(true)
	if extra.has("genre"):
		out = out.filter(func(it): return str(extra.genre) in it.genres)
	return out.slice(skip) if skip < out.size() else []


func _demo_search(q: String) -> Array:
	var lq := q.to_lower()
	var by_type := {}
	for id in _demo.metas.keys():
		var m: Dictionary = _demo.metas[id]
		if str(m.name).to_lower().contains(lq) or lq in (m.genres as Array).map(func(g): return str(g).to_lower()):
			if not by_type.has(str(m.type)):
				by_type[str(m.type)] = []
			(by_type[str(m.type)] as Array).append(_preview_only(m))
	var rows: Array = []
	for t in ["movie", "series"]:
		if by_type.has(t):
			rows.append({ "key": "search/demo/" + t, "title": type_label(t), "type": t, "addon_id": "demo.cinemeta", "catalog_id": "top",
				"extra": { "search": q }, "items": by_type[t], "see_all": false })
	return rows


func _demo_streams(job: Dictionary, _type: String, video_id: String) -> Array:
	var sources: Array = _demo.stream_sources
	for src in sources:
		_status.append({ "name": str(src.name), "state": "lädt", "count": 0, "kind": str(src.kind), "id": str(src.id), "error": "" })
	var i := 0
	for src in sources:
		await get_tree().create_timer(0.25 + 0.2 * i).timeout
		i += 1
		if int(job.id) != _job_id:
			break
		if str(src.get("error", "")) != "":
			_set_status(job, str(src.id), "fehler", 0, str(src.error))
			continue
		var found: Array = []
		var k := 0
		for raw in src.streams:
			var s := (raw as Dictionary).duplicate(true)
			if s.has("url"):
				s.url = str(s.url).replace("{id}", video_id)
			var a := { "id": str(src.id), "name": str(src.name) }
			var st := parse_stream(s, a, i * 1000 + k) if str(src.kind) == "addon" else parse_plugin_result(s, { "id": str(src.id), "name": str(src.name) },
					i * 1000 + k)
			k += 1
			if not st.is_empty():
				found.append(st)
		_set_status(job, str(src.id), "fertig", found.filter(func(s): return not (bool(s.is_p2p) and no_p2p())).size())
		_merge(job, found)
	return (job.sorted as Array).duplicate(true)

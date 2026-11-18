extends "res://src/core/media_daten.gd"
## Bilder für Spiele: Cover (cover), großes Hintergrundbild (hero) und Schriftzug (logo).
## Reihenfolge: eigenes Bild des Nutzers → Medienordner → Steam-Cache → aus dem Netz, ohne
## Schlüssel (remote_sources: Steam-Server, Epic-Katalog, Steam-Bilder für EA-/PC-Spiele mit
## gleichem Namen, Libretro für Emulator-Spiele) – SteamGridDB nur mit eigenem API-Schlüssel.
## Alles wird im Hintergrund geladen und zwischengespeichert.
##
## Reine Funktionen (Bilder sicher lesen, Adressen, Zuordnung, Zuschnitt, Farbe) stehen in
## media_daten.gd, von dem dieser Autoload erbt.

const Logdatei := preload("res://src/core/logdatei.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const Lang := preload("res://src/core/lang.gd")
const GamePresence := preload("res://src/core/game_presence.gd")
const Regal := preload("res://src/library/regal.gd")
const Screenscraper := preload("res://src/core/screenscraper.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Iidb := preload("res://src/core/iidb.gd")
const IidbDienst := preload("res://src/core/iidb_dienst.gd")

const EXTS := ["png", "jpg", "jpeg", "webp"]
const MAX_TEX := 320
## Höchstens so viel Grafikspeicher für zwischengespeicherte Bilder (RGBA, geschätzt). Nur die
## Anzahl zu begrenzen reichte nicht: 320 große Hintergründe sind über ein Gigabyte.
const MAX_TEX_BYTES := 360 * 1024 * 1024
const STEAM_CDN := "https://shared.steamstatic.com/store_item_assets/steam/apps/%s/%s"
## Spiele von EA, Epic, den weiteren Launchern und eigene PC-Spiele gibt es oft auch bei Steam – mit
## den offiziellen Bildern.
const STEAM_SEARCH := "https://store.steampowered.com/api/storesearch/?term=%s&l=english&cc=%s"
const STEAM_MATCH_RETRY := 14 * 86400    ## kein Spiel mit diesem Namen bei Steam: in zwei Wochen neu fragen

var _tex := {}            # Pfad@Breite -> Texture2D
var _tex_bytes := {}      # Pfad@Breite -> geschätzte Größe
var _tex_total := 0
var _pending := {}        # Pfad@Breite -> Array[Callable]
var _missing := {}        # Spiel-ID:Art -> true (nichts gefunden, nicht nochmal suchen)
var _resolving := {}      # Spiel-ID:Art -> Array[Callable]
var _local := {}          # Spiel-ID:Art -> [Pfad, Zeitpunkt] (local_path, Medienordner und Steam-Cache)
var iidb: Node            ## iiDB im Netz (iidb_dienst.gd): Bilder, Bildwahl, Klang der Spielseite


func max_width(kind: String) -> int:
	match kind:
		"hero": return 1920
		"logo": return 900
		"wide": return 920
		"icon": return 256
		"shot": return 1280
		"ruecken": return 900
	# Cover: angezeigt höchstens ~250 px breit (gewählt 1,15×). 480 px kosteten das Vierfache an
	# Grafikspeicher (240 Cover im Raster über 300 MB); in 4K rechnet px_scale hoch.
	return 360


## Ruft cb(Texture2D oder null) auf, sobald das Bild da ist.
func game_texture(game: Dictionary, kind: String, cb: Callable) -> void:
	cb = guard(cb)
	var mw := max_width(kind)
	game_file(game, kind, func(path: String) -> void:
		if path != "":
			file_texture(path, mw, cb)
		elif cb.is_valid():
			cb.call(null)
	)


## Ruft cb(Dateipfad oder "") auf: das Bild auf der Platte, wenn nötig erst heruntergeladen.
func game_file(game: Dictionary, kind: String, cb: Callable) -> void:
	cb = guard(cb)
	var key := "%s:%s" % [game.get("id", ""), kind]
	if _missing.has(key):
		if cb.is_valid():
			cb.call("")
		return
	var local := local_path(game, kind)
	if local != "":
		if cb.is_valid():
			cb.call(local)
		return
	# Eigene Apps (Netflix, Kodi …): nie Bilder aus dem Netz suchen – nur ihr eigenes Logo.
	if str(game.get("source", "")) == "app":
		if cb.is_valid():
			cb.call("")
		return
	if _resolving.has(key):
		_resolving[key].append(cb)
		return
	_resolving[key] = [cb]
	var found := await _fetch_remote(game, kind)
	var waiting: Array = _resolving.get(key, [])
	_resolving.erase(key)
	if found == "":
		_missing[key] = true
	for w in waiting:
		if (w as Callable).is_valid():
			w.call(found)


## Bildpfad aus der Bibliothek: lokal, oder auf einem Rechner, den du selbst als Ordner eingetragen hast (ROMs, PC-Spiele
## oder Medienordner auf dem NAS). Ein anderer Rechner nie.
func _bild_pfad_ok(p: String) -> bool:
	if Sicher.local_path_ok(p):
		return true
	var h := Sicher.freigabe_host(p)
	if h == "":
		return false
	var eigene: Array = [str(Config.get_value("library.media_dir", ""))]
	var roms: Variant = Config.get_value("library.rom_dirs", {})
	if roms is Dictionary:
		eigene.append_array((roms as Dictionary).values())
	var pcs: Variant = Config.get_value("library.pc_dirs", [])
	if pcs is Array:
		eigene.append_array(pcs)
	return eigene.any(func(d: Variant) -> bool: return Sicher.freigabe_host(str(d)) == h)


## Bild, das ohne Internet sofort da ist (eigenes Bild, Medienordner, Steam-Cache, Download-Cache).
func local_path(game: Dictionary, kind: String) -> String:
	var imgs: Variant = game.get("images", {})
	var custom := str((imgs as Dictionary).get(kind, "")) if imgs is Dictionary else ""
	# Pfade aus library.json (auch aus einer zurückgeholten Sicherung): nie ein fremder Rechner – schon file_exists schickte
	# sonst die Windows-Anmeldung dorthin (_bild_pfad_ok).
	if custom != "" and _bild_pfad_ok(custom) and FileAccess.file_exists(custom):
		return custom
	var imgs_auto: Variant = game.get("images_auto", {})
	var auto := str((imgs_auto as Dictionary).get(kind, "")) if imgs_auto is Dictionary else ""
	if auto != "" and _bild_pfad_ok(auto) and FileAccess.file_exists(auto):
		return auto
	# Medienordner und Steam-Cache: bis zu zwei Dutzend Dateiprüfungen und eine Ordnersuche –
	# beim Bau jeder Karte und bei jedem Fokuswechsel. Gefundenes gilt eine Minute (solange die
	# Datei da ist), „nichts gefunden“ 10 s – ein neues Bild im Medienordner zählt also bald.
	var gid := str(game.get("id", ""))
	if gid == "":
		# Ohne ID (Shop-Einträge, Spiele von Freunden): nichts merken, sonst teilten sie sich Bilder.
		var direct := _from_media_dir(game, kind)
		if direct == "" and game.get("source") == "steam":
			direct = _steam_local(str(game.get("appid", "")), kind)
		return direct
	var key := "%s:%s" % [gid, kind]
	var now := Time.get_ticks_msec()
	var hit: Variant = _local.get(key)
	if hit is Array:
		var hp := str(hit[0])
		var age := now - int(hit[1])
		if hp != "" and age < 60000 and FileAccess.file_exists(hp):
			return hp
		if hp == "" and age < 10000:
			return ""
	var found := _from_media_dir(game, kind)
	if found == "" and game.get("source") == "steam":
		found = _steam_local(str(game.get("appid", "")), kind)
	_local[key] = [found, now]
	Config.cap(_local, 6000)
	return found


func _from_media_dir(game: Dictionary, kind: String) -> String:
	var root := Config.media_dir()
	var sys := str(game.get("system", ""))
	var names := PackedStringArray()
	var p := str(game.get("path", ""))
	if p != "":
		names.append(p.get_file().get_basename())
	names.append(str(game.get("title", "")))
	names.append(safe_name(str(game.get("title", ""))))
	var dirs := PackedStringArray()
	if kind == "cover":
		dirs.append(root.path_join(sys))
		dirs.append(root.path_join(sys).path_join("cover"))
	else:
		dirs.append(root.path_join(sys).path_join(kind))
	for d in dirs:
		var da := _ordner_dateien(d)
		if da.is_empty():
			continue
		for n in names:
			if n == "":
				continue
			for e in EXTS:
				var echt: Variant = da.get(("%s.%s" % [n, e]).to_lower())
				if echt == null:
					continue
				var f := d.path_join(str(echt))
				if FileAccess.file_exists(f):
					return f
	return ""


## Die Dateien eines Ordners im Medienordner (klein geschrieben → wie sie heißen), gemerkt für ORDNER_MS. Vorher
## fragte die Suche je Spiel bis zu 24 Dateinamen einzeln bei der Platte an. „Wie viele Spiele sind ohne Cover?“
## (Einstellungen › Spiele, „Für dich“, Scrapen) fragt für die ganze Bibliothek: bei 1800 Emulator-Spielen ohne
## Cover 0,4 s Stillstand (gemessen, schnelle Platte) – und nach 10 s wieder, weil „nichts gefunden“ nur so lange
## gilt. Jetzt liest Uzai je Ordner einmal das Verzeichnis. Groß- und Kleinschreibung zählt nicht (wie unter
## Windows ohnehin).
const ORDNER_MS := 8000
var _ordner := {}                ## Ordner → [{ name klein → Name }, wann gelesen (ms)]


func _ordner_dateien(d: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	var hit: Variant = _ordner.get(d)
	if hit is Array and now - int(hit[1]) < ORDNER_MS:
		return hit[0]
	var namen := {}
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			namen[f.to_lower()] = f
	_ordner[d] = [namen, now]
	Config.cap(_ordner, 400)
	return namen


## Steam-Bilder ohne Internet: eigene Steam-Artworks (userdata/*/config/grid), dann der
## Bibliotheks-Cache von Steam (alte und neue Ordnerstruktur), dann Uzais Download-Cache.
func _steam_local(appid: String, kind: String) -> String:
	if not appid.is_valid_int() or int(appid) <= 0 or not STEAM_FILES.has(kind):
		return ""
	var steam := Library.steam_root()
	if steam != "":
		var grid := _steam_grid(steam, appid, kind)
		if grid != "":
			return grid
		var base := steam.path_join("appcache/librarycache")
		for name in STEAM_CACHE_NAMES.get(kind, []):
			for f in [base.path_join(appid).path_join(name), base.path_join("%s_%s" % [appid, name])]:
				if FileAccess.file_exists(f):
					return f
		# Neuere Steam-Versionen legen die Bilder in Unterordner mit Prüfsummen-Namen.
		var deep := _find_in(base.path_join(appid), STEAM_CACHE_NAMES.get(kind, []), 2)
		if deep != "":
			return deep
	for ext in ["jpg", "png"]:
		var dl := Config.path("cache/img/steam/%s_%s.%s" % [appid, kind, ext])
		if FileAccess.file_exists(dl):
			return dl
	var old := Config.path("cache/img/steam/%s_%s" % [appid, STEAM_FILES[kind]])
	return old if FileAccess.file_exists(old) else ""


const STEAM_CACHE_NAMES := {
	"cover": ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule.jpg"],
	"hero": ["library_hero_2x.jpg", "library_hero.jpg"],
	"logo": ["logo_2x.png", "logo.png"],
	"wide": ["header_2x.jpg", "header.jpg"],
	"icon": ["icon.jpg", "icon.png"],
}
const STEAM_GRID_NAMES := { "cover": "%sp", "hero": "%s_hero", "logo": "%s_logo", "wide": "%s", "icon": "%s_icon" }
var _grid_dirs: Array = []


## Bilder, die du in Steam selbst gesetzt hast (auch über Steam ROM Manager oder SteamGridDB).
func _steam_grid(steam: String, appid: String, kind: String) -> String:
	if _grid_dirs.is_empty():
		var ud := DirAccess.open(steam.path_join("userdata"))
		if ud:
			for d in ud.get_directories():
				var g := steam.path_join("userdata").path_join(d).path_join("config/grid")
				if DirAccess.dir_exists_absolute(g):
					_grid_dirs.append(g)
		if _grid_dirs.is_empty():
			_grid_dirs.append("")
	for g in _grid_dirs:
		if str(g) == "":
			continue
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var f := str(g).path_join((STEAM_GRID_NAMES[kind] % appid) + "." + ext)
			if FileAccess.file_exists(f):
				return f
	return ""


# --- Steam-Store: Bildpfade neuer Spiele ---------------------------------------------------
# Neue Spiele haben Bildadressen mit Prüfsummen im Pfad (…/apps/{appid}/{hash}/library_600x900.jpg),
# die alten festen Adressen gibt es dort nicht. Die Store-Schnittstelle (IStoreBrowseService/
# GetItems) kennt die echten Namen. Uzai fragt bis zu 50 Spiele auf einmal, merkt sich die Antwort
# in cache/steam_assets.json und fragt nach einer Woche neu (Steam hängt „?t=…“ an die Adressen:
# so kommen auch neue Bilder eines Spiels an). Bibliothek und Shop teilen sich diesen Speicher.

const STORE_ITEMS := "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json="
const ASSETS_FILE := "cache/steam_assets.json"
const ASSETS_RETRY := 300              ## keine Antwort (kein Netz): erst nach fünf Minuten neu fragen
const ASSETS_KEEP := 30 * 86400        ## noch ältere Einträge fliegen beim Laden raus

var _assets := {}            # appid -> { asset_url_format, main_capsule, …, _t: Zeitpunkt der Antwort }
var _assets_loaded := false
var _asset_queue: Array = []
var _asset_waiting := {}     # appid -> true (Anfrage steht an oder läuft)
var _asset_failed := {}      # appid -> Zeitpunkt der letzten Anfrage ohne Antwort
var _asset_cbs := {}         # appid -> Array[Callable] (with_steam_assets wartet darauf)
var _asset_flush := false
signal _assets_arrived


func _load_assets() -> void:
	if _assets_loaded:
		return
	_assets_loaded = true
	var cached: Variant = Config.read_json(Config.path(ASSETS_FILE), {})
	if not (cached is Dictionary):
		return
	var now := int(Time.get_unix_time_from_system())
	for k in cached.keys():
		var a: Variant = cached[k]
		if a is Dictionary and now - int(a.get("_t", 0)) < ASSETS_KEEP:
			_assets[str(k)] = a


## Muss Uzai Steam (wieder) fragen? Nicht, solange die Angaben frisch sind oder die letzte
## Anfrage ohne Antwort erst kurz her ist (ohne Netz sonst bei jedem Aufbau der Seite).
func _needs_fetch(k: String, now: int) -> bool:
	if k == "0" or assets_fresh(_assets.get(k, {}), now):
		return false
	return now - int(_asset_failed.get(k, -ASSETS_RETRY)) >= ASSETS_RETRY


## Was Uzai zu einem Spiel schon weiß, ohne zu warten ({} wenn nichts). Auch ältere Angaben:
## Bildnamen ändern sich selten, aufgefrischt wird dann im Hintergrund.
func cached_steam_assets(appid: Variant) -> Dictionary:
	_load_assets()
	return _assets.get(_akey(appid), {})


## Angaben für viele Spiele vorab holen (gebündelt). Der Shop ruft das, sobald er seine Listen
## kennt – die Karten finden die richtigen Adressen dann schon vor.
func prefetch_steam_assets(ids: Array) -> void:
	_load_assets()
	var now := int(Time.get_unix_time_from_system())
	for id in ids:
		var k := _akey(id)
		if _needs_fetch(k, now):
			_queue_asset(k)


## Angaben, die Uzai schon anders bekommen hat (Shop: GetItems mit Preisen), mit merken.
func remember_steam_assets(appid: Variant, a: Dictionary) -> void:
	if a.is_empty() or _akey(appid) == "0":
		return
	_load_assets()
	var e := a.duplicate()
	e["_t"] = int(Time.get_unix_time_from_system())
	_assets[_akey(appid)] = e
	_save_assets()


func _queue_asset(k: String) -> void:
	if _asset_waiting.has(k):
		return
	_asset_waiting[k] = true
	_asset_queue.append(k)
	if not _asset_flush:
		_asset_flush = true
		_flush_assets.call_deferred()


## Angaben zu einem Spiel; wartet auf Steam, wenn noch nichts da ist ({} ohne Antwort).
func steam_assets(appid: Variant) -> Dictionary:
	var k := _akey(appid)
	var have := cached_steam_assets(k)
	var now := int(Time.get_unix_time_from_system())
	if not have.is_empty() or not _needs_fetch(k, now):
		prefetch_steam_assets([k])
		return have
	_queue_asset(k)
	while _asset_waiting.has(k):
		await _assets_arrived
	return cached_steam_assets(k)


## Wie steam_assets, aber mit Rückruf und Zeitgrenze (für Karten, die gerade entstehen): Antwortet
## Steam nicht rechtzeitig, kommt cb({}) und die Karte nimmt die alten Adressen, statt leer zu
## bleiben. Die Antwort landet trotzdem im Speicher – beim nächsten Aufbau ist sie da.
func with_steam_assets(appid: Variant, cb: Callable, max_wait := 3.0) -> void:
	cb = guard(cb)
	var k := _akey(appid)
	var have := cached_steam_assets(k)
	var now := int(Time.get_unix_time_from_system())
	if not have.is_empty() or not _needs_fetch(k, now):
		prefetch_steam_assets([k])
		if cb.is_valid():
			cb.call(have)
		return
	_queue_asset(k)
	if not _asset_cbs.has(k):
		_asset_cbs[k] = []
	(_asset_cbs[k] as Array).append(cb)
	get_tree().create_timer(max_wait).timeout.connect(func() -> void:
		var list: Array = _asset_cbs.get(k, [])
		var i := list.find(cb)
		if i >= 0:
			list.remove_at(i)
			if cb.is_valid():
				cb.call({})
	)


func steam_asset_url(appid: String, kind: String) -> String:
	return asset_url_from(await steam_assets(appid), kind, appid)


func _flush_assets() -> void:
	await get_tree().create_timer(0.05).timeout
	_asset_flush = false
	var batch := _asset_queue.slice(0, 50)
	_asset_queue = _asset_queue.slice(50)
	if not _asset_queue.is_empty():
		_asset_flush = true
		_flush_assets.call_deferred()
	if batch.is_empty():
		return
	var ids: Array = []
	for id in batch:
		ids.append({ "appid": int(id) })
	var q := JSON.stringify(
			{ "ids": ids, "context": { "language": Lang.api("steam"), "country_code": Config.land() }, "data_request": { "include_assets": true } })
	var r := await Net.get_json(STORE_ITEMS + q.uri_encode())
	var now := int(Time.get_unix_time_from_system())
	var got := parse_store_assets(r.data) if r.ok else {}
	for id in batch:
		var k := str(id)
		if r.ok:
			# Auch „keine Bilder“ ist eine Antwort (nur _t): nicht gleich wieder fragen.
			var a: Dictionary = (got.get(k, {}) as Dictionary).duplicate()
			a["_t"] = now
			_assets[k] = a
			_asset_failed.erase(k)
		else:
			# Ältere Angaben bleiben stehen; neu gefragt wird frühestens nach ASSETS_RETRY.
			_asset_failed[k] = now
		_asset_waiting.erase(k)
	if r.ok:
		_save_assets()
	_assets_arrived.emit()
	for id in batch:
		var cbs: Array = _asset_cbs.get(str(id), [])
		_asset_cbs.erase(str(id))
		for cb in cbs:
			if (cb as Callable).is_valid():
				cb.call(cached_steam_assets(str(id)))


## Gebündelt speichern: Eine Shop-Liste meldet bis zu 150 Spiele in einem Bild – früher wurde die
## ganze Datei für jedes einzelne neu geschrieben (bei 3000 Einträgen fast 3 s Stillstand).
var _assets_save_due := false


func _save_assets() -> void:
	if _assets_save_due:
		return
	_assets_save_due = true
	get_tree().create_timer(2.0).timeout.connect(save_assets_now)


func save_assets_now() -> void:
	if not _assets_save_due:
		return
	_assets_save_due = false
	Config.write_json(Config.path(ASSETS_FILE), _assets)


func _exit_tree() -> void:
	save_assets_now()
	save_looks_now()
	save_grund_now()


func _fetch_remote(game: Dictionary, kind: String) -> String:
	var opts := { "steam": bool(Config.get_value("library.steam_images", true)), "libretro": bool(Config.get_value("library.libretro_images", true)),
		"sgdb": str(Config.get_value("accounts.sgdb_key", "")) != "", "ss": Screenscraper.verfuegbar(), "iidb": iidb.verbunden() }
	var got := ""
	for how in remote_sources(game, kind, opts):
		match how:
			"steam": got = await _from_steam(str(game.get("appid", "")), kind, game)
			"art": got = await _from_art(game, kind)
			"steam_match":
				var appid := await steam_match_id(game)
				if appid > 0:
					got = await _from_steam(str(appid), kind, game)
			"sgdb": got = await _from_sgdb(game, kind)
			"ss": got = await _from_ss(game, kind)
			"iidb": got = await iidb.bild(game, kind)
			"libretro": got = await libretro_find(game, "Named_Logos" if kind == "logo" else "Named_Boxarts")
			"shot": got = await _first_shot(game)
		if got != "":
			break
	if got != "":
		# Im Eintrag der Bibliothek merken (game kann eine Kopie sein), damit das Bild nach
		# einem Neustart sofort und ohne Internet da ist.
		for g in [game, Library.get_game(str(game.get("id", "")))]:
			if (g as Dictionary).is_empty():
				continue
			var auto := Fremd.verz(g.get("images_auto")).duplicate()
			auto[kind] = got
			g["images_auto"] = auto
		Library.mark_dirty()
	elif kind == "cover" and not bool(opts.sgdb) and not bool(opts.ss) and not bool(opts.iidb):
		_sgdb_hint()
	return got


var _no_cover := 0
var _sgdb_hinted := false


## Ohne SteamGridDB-Schlüssel fehlen Cover: einmal je Lauf ein klarer Hinweis statt still leerer
## Kacheln (erst ab drei Spielen ohne Cover, nie in der Vorführung).
func _sgdb_hint() -> void:
	_no_cover += 1
	if _sgdb_hinted or _no_cover < 3 or "--demo" in OS.get_cmdline_user_args():
		return
	_sgdb_hinted = true
	Toasts.show_toast("Bilder für fast jedes Spiel", "Mit SteamGridDB bekommst du für fast jedes Spiel Bilder – einrichten unter Einstellungen → Konten → Bilder.",
			"image", { "ms": 8000, "quiet": true })


## Bild eines Steam-Spiels vom Steam-Server: erst die Adressen aus dem Store (stimmen auch bei
## neuen Spielen mit Prüfsummen im Pfad), sonst der alte feste Pfad.
func _from_steam(appid: String, kind: String, game := {}) -> String:
	var id := int(appid) if appid.is_valid_int() else 0
	if id <= 0 or not STEAM_FILES.has(kind):
		return ""
	var file: String = STEAM_FILES[kind]
	var dest := Config.path("cache/img/steam/%d_%s.%s" % [id, kind, file.get_extension()])
	var urls := asset_urls(await steam_assets(str(id)), kind, str(id))
	urls.append(STEAM_CDN % [str(id), file])
	for url in urls:
		var got := await Net.download(str(url), dest)
		if got != "":
			note_url(game, got, str(url))
			return got
	return ""


# --- Steam-Bilder für Spiele aus anderen Quellen ------------------------------------------------
# Viele EA-, Epic- und eigene PC-Spiele gibt es auch bei Steam. Uzai sucht den Namen in Steams
# Shop-Suche (ohne Anmeldung, ohne Schlüssel) und nimmt nur einen Treffer mit genau gleichem Namen
# – „Battlefield 1“ bekommt nie die Bilder von „Battlefield 2042“. Das Ergebnis steht im Eintrag
# der Bibliothek (steam_match), damit nur einmal gefragt wird.

var _match_busy := {}     # Spiel-ID -> true (Suche läuft)


## Steam-App-ID zu einem Spiel aus einer anderen Quelle, 0 wenn es keins mit gleichem Namen gibt.
func steam_match_id(game: Dictionary) -> int:
	var title := str(game.get("title", "")).strip_edges()
	if title == "" or title.length() > 120:
		return 0
	var gid := str(game.get("id", ""))
	while gid != "" and _match_busy.has(gid):
		await get_tree().process_frame
	# Andere Bildarten desselben Spiels warten oben und finden das Ergebnis dann im Eintrag.
	var lib := Library.get_game(gid)
	var known: Dictionary = lib if not lib.is_empty() else game
	var now := int(Time.get_unix_time_from_system())
	if str(known.get("steam_match_title", "")) == title:
		var id := int(known.get("steam_match", 0))
		if id > 0 or now - int(known.get("steam_match_t", 0)) < STEAM_MATCH_RETRY:
			return maxi(id, 0)
	if gid != "":
		_match_busy[gid] = true
	var r := await Net.get_json(STEAM_SEARCH % [title.uri_encode(), Config.land()])
	_match_busy.erase(gid)
	if not r.ok or not (r.data is Dictionary):
		return 0          # keine Antwort (kein Netz): nichts merken, beim nächsten Mal neu fragen
	var found := steam_title_match(r.data.get("items", []), title)
	for g in [game, lib]:
		if not (g as Dictionary).is_empty():
			g["steam_match"] = found if found > 0 else -1
			g["steam_match_title"] = title
			g["steam_match_t"] = now
	Library.mark_dirty()
	return found


## Bilder, deren Adresse schon im Eintrag steht (Epic: keyImages aus dem Katalog des Launchers
## auf dem PC). Ohne Schlüssel, direkt von Epics Bildserver.
func _from_art(game: Dictionary, kind: String) -> String:
	var art: Variant = game.get("art", {})
	if not (art is Dictionary):
		return ""
	var url := str((art as Dictionary).get(kind, ""))
	if not url.begins_with("https://"):
		return ""
	var ext := url.get_slice("?", 0).get_extension().to_lower()
	if not ext in EXTS:
		ext = "jpg"
	var got := await Net.download(url, Config.path("cache/img/art/%s_%s.%s" % [url.md5_text().substr(0, 16), kind, ext]))
	note_url(game, got, url)
	return got


## Ein Bild von SteamGridDB. info (freiwillig) bekommt den Grund, wenn es keins gibt: "fehlt",
## "zugang" (Schlüssel abgelehnt), "kontingent" (zu viele Anfragen) oder "netz".
func _from_sgdb(game: Dictionary, kind: String, info: Dictionary = {}) -> String:
	if _sgdb_aus != "" and Time.get_ticks_msec() - _sgdb_aus_ms < AUS_MS:
		info["grund"] = _sgdb_aus
		return ""
	_sgdb_aus = ""
	var key := str(Config.get_value("accounts.sgdb_key", ""))
	if key == "":
		info["grund"] = "zugang"
		return ""
	var hdr := PackedStringArray(["Authorization: Bearer " + key])
	var api := "https://www.steamgriddb.com/api/v2"
	var gid := str(game.get("sgdb_id", ""))
	var path_kind: String = { "hero": "heroes", "logo": "logos", "icon": "icons" }.get(kind, "grids")
	var url := ""
	if game.get("source") == "steam" and str(game.get("appid", "")) != "":
		url = "%s/%s/steam/%s" % [api, path_kind, game.appid]
	else:
		if gid == "":
			var s := await Net.get_json("%s/search/autocomplete/%s" % [api, str(game.get("title", "")).uri_encode()], hdr)
			var treffer := Fremd.zeilen(s.data, "data") if s.ok else []
			var nummer := Fremd.zahl(treffer[0].get("id")) if not treffer.is_empty() else 0
			if nummer <= 0:
				info["grund"] = _sgdb_grund(int(s.code), bool(s.ok))
				if not bool(s.ok):
					log_line("scrape", "SteamGridDB Suche: HTTP %d (%s)" % [int(s.code), str(info.grund)])
				return ""
			gid = str(nummer)
			game["sgdb_id"] = gid
		url = "%s/%s/game/%s" % [api, path_kind, gid]
	if SGDB_MASSE.has(kind):
		url += "?dimensions=" + str(SGDB_MASSE[kind])
	var r := await Net.get_json(url, hdr)
	if not r.ok or not (r.data is Dictionary):
		info["grund"] = _sgdb_grund(int(r.code), false)
		log_line("sgdb", "%s → HTTP %d %s" % [url.get_slice("?", 0), int(r.code), str(r.get("text", "")).left(120)])
		return ""
	# Heroes nur in Hero-Größe (sgdb_wahl): Ein kleines Bild wäre auf voller Breite unscharf.
	var img_url := sgdb_wahl(r.data.get("data", []), kind)
	if img_url == "":
		info["grund"] = "fehlt"
		return ""
	var ext := img_url.get_extension().to_lower()
	if not ext in EXTS:
		ext = "png"
	var got := await Net.download(img_url, bild_ziel("sgdb", game, kind, img_url, ext))
	if got == "":
		info["grund"] = "netz"
		log_line("sgdb", "Bild nicht geladen: " + img_url)
	note_url(game, got, img_url)
	return got


## Antwort von SteamGridDB gedeutet; 401/403 und 429 stellen SteamGridDB für eine Weile ab.
func _sgdb_grund(code: int, ok: bool) -> String:
	var g := "fehlt" if ok or code == 404 else ("zugang" if code in [401, 403] else ("kontingent" if code == 429 else "netz"))
	if g in ["zugang", "kontingent"]:
		_sgdb_aus = g
		_sgdb_aus_ms = Time.get_ticks_msec()
	return g


## Wohin ein geholtes Bild kommt: je Spiel, Bildart und Adresse eine eigene Datei. Ein neues Bild
## (Alles ersetzen, andere Quelle) bekommt so einen neuen Pfad – nichts lädt die alte Datei weiter
## aus einem Zwischenspeicher (Texturen, Zuschnitt, Grundfarbe hängen am Pfad), und Net.download
## nimmt nie eine alte Datei unter demselben Namen als „schon geladen“.
static func bild_ziel(ordner: String, game: Dictionary, kind: String, url: String, ext: String) -> String:
	return Config.path("cache/img/%s/%s_%s_%s.%s" % [ordner, str(game.get("id", "x")).md5_text().substr(0, 12), kind,
			url.md5_text().substr(0, 10), ext])


# --- ScreenScraper (screenscraper.gd) -------------------------------------------------------------

const SS_FEHLT_TAGE := 14           ## nicht gefunden: erst nach zwei Wochen neu fragen
const SS_ALT_TAGE := 30             ## Alles ersetzen / Bildwahl: Gemerktes, das älter ist, neu fragen
const SS_KAND_DIR := "cache/ss"     ## Kandidaten je Spiel (Bildwahl), damit nicht jedes Mal gefragt wird
const AUS_MS := 10 * 60 * 1000      ## nach einer Ablehnung so lange nicht mehr fragen
var _ss_letzte_ms := -100000
var _ss_aus := ""                   ## "zugang" | "kontingent" | "zu": eine Weile nicht mehr fragen
var _ss_aus_ms := 0
var _ss_laufend := 0                ## so viele Anfragen laufen (höchstens Screenscraper.faeden, ohne Konto 1)
var _ss_grenzen := {}               ## Fäden und Minutenlimit aus der letzten Antwort (ssuser)
var _ss_busy := {}                  ## Spiel-ID → true, solange gefragt wird
var _ss_grund := {}                 ## Spiel-ID → warum zuletzt nichts kam
var _ss_kand := {}                  ## Spiel-ID → { id, name, liste, t } (Sitzung)
var _ss_treffer := {}               ## Kennung bei ScreenScraper → Spiel aus einer Suche (Anderes Spiel)
var ss_kontingent := {}             ## letzte Zahlen des Tageskontingents (Screenscraper.kontingent)
var ss_test := Callable()           ## nur für Tests (logic_screenscraper): Adresse → { ok, data, code } statt Netz
var _sgdb_aus := ""
var _sgdb_aus_ms := 0


## Eine Anfrage an ScreenScraper: eine nach der anderen, mit Pause. Ablehnungen (Zugang, Limit,
## geschlossen) stellen ScreenScraper eine Weile ab. { ok, data, code, grund }. Ins Protokoll kommt
## nie die Adresse (sie trägt die Zugangsdaten), nur Spiel, Status und der bereinigte Grund.
func _ss_fragen(url: String, wofuer: String) -> Dictionary:
	if url == "":
		return { "ok": false, "data": null, "code": 0, "grund": "fehlt" }
	if _ss_aus != "" and Time.get_ticks_msec() - _ss_aus_ms < AUS_MS:
		return { "ok": false, "data": null, "code": 0, "grund": _ss_aus }
	_ss_aus = ""
	# Fäden (maxthreads) und Abstand (mindestens Screenscraper.PAUSE_MS, Minutenlimit) nie überschreiten.
	while _ss_laufend >= Screenscraper.faeden(_ss_grenzen):
		await get_tree().process_frame
	_ss_laufend += 1
	while Time.get_ticks_msec() - _ss_letzte_ms < Screenscraper.pause_ms(_ss_grenzen):
		await get_tree().process_frame
	_ss_letzte_ms = Time.get_ticks_msec()
	var r: Dictionary = (await ss_test.call(url)) if ss_test.is_valid() else (await Net.get_json(url))
	if Screenscraper.faeden(_ss_grenzen) <= 1:
		_ss_letzte_ms = Time.get_ticks_msec()     # ein Faden: die Pause zählt ab dem Ende der Anfrage
	_ss_laufend -= 1
	var out := { "ok": bool(r.ok), "data": r.data, "code": int(r.code), "grund": "" }
	if bool(r.ok):
		var k := Screenscraper.kontingent(r.data)
		if int(k.faeden) > 0 or int(k.pro_min) > 0:
			_ss_grenzen = { "faeden": int(k.faeden), "pro_min": int(k.pro_min) }
		if int(k.max) > 0:
			ss_kontingent = k
		if Screenscraper.kontingent_voll(k):
			_ss_aus_setzen("kontingent")
	else:
		var g := Screenscraper.fehler(int(r.code), str(r.get("text", "")))
		out.grund = g
		if g != "fehlt":
			log_line("scrape", "ScreenScraper · %s: HTTP %d (%s) %s" % [wofuer.left(80), int(r.code), g,
					Screenscraper.sauber(str(r.get("text", "")), Screenscraper.zugang())])
		if g in ["zugang", "kontingent", "zu"]:
			_ss_aus_setzen(g)
	return out


func _ss_aus_setzen(g: String) -> void:
	_ss_aus = g
	_ss_aus_ms = Time.get_ticks_msec()


## Ein Spiel bei ScreenScraper finden: erst über die Datei (Name, Größe, bei kleinen Dateien die
## Prüfsumme), sonst nach dem Namen (jeuRecherche, nur ein Treffer mit gleichem System und fast
## gleichem Namen). PC-Spiele nur nach dem Namen: PC Windows, dann PC Dos (Screenscraper.PC_SUCHE).
## { info } (Screenscraper.jeu_lesen) oder { grund }.
func _ss_suchen(game: Dictionary) -> Dictionary:
	var z := Screenscraper.zugang()
	var sprache := "de" if TranslationServer.get_locale().begins_with("de") else "en"
	var titel := str(game.get("title", ""))
	if Screenscraper.ist_pc(game):
		for sys in Screenscraper.PC_SUCHE:
			var e := await _ss_nach_namen(titel, sys, int(game.get("year", 0)), z, sprache)
			if not e.is_empty():
				return e
		log_line("scrape", "ScreenScraper · %s: nicht gefunden (PC, Name)" % titel.left(80))
		return { "grund": "fehlt" }
	var p := str(game.get("path", ""))
	var groesse := -1
	if p != "" and Sicher.local_path_ok(p) and FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f:
			groesse = int(f.get_length())
			f.close()
	var md5 := ""
	if Screenscraper.md5_sinnvoll(p, groesse):
		md5 = await md5_datei(p)
	var r := await _ss_fragen(Screenscraper.anfrage(game, groesse, z, md5), titel)
	if bool(r.ok):
		var info := Screenscraper.lesen(r.data, sprache)
		if bool(info.ok):
			return { "info": info }
	elif str(r.grund) != "fehlt":
		return { "grund": r.grund }
	# Über die Datei nicht gefunden (anderer Dateiname, geändertes Abbild): nach dem Namen suchen.
	var e := await _ss_nach_namen(titel, str(game.get("system", "")), int(game.get("year", 0)), z, sprache)
	if e.is_empty():
		log_line("scrape", "ScreenScraper · %s: nicht gefunden (Datei und Name)" % titel.left(80))
		return { "grund": "fehlt" }
	return e


## Suche nach Namen in einem System (jeuRecherche), der beste Treffer nach Name und Jahr; fehlen
## ihm die Medien, noch ein Abruf nach Kennung. { info }, { grund } bei Ablehnung, {} ohne Treffer.
func _ss_nach_namen(titel: String, sys: String, jahr: int, z: Dictionary, sprache: String) -> Dictionary:
	var s := await _ss_fragen(Screenscraper.anfrage_suche(titel, sys, z), titel)
	if not bool(s.ok):
		return {} if str(s.grund) in ["", "fehlt"] else { "grund": s.grund }
	var t := Screenscraper.bester_treffer(Screenscraper.suche_lesen(s.data, sprache), titel, sys, jahr)
	if t.is_empty():
		return {}
	if (t.medien as Dictionary).is_empty():
		var r2 := await _ss_fragen(Screenscraper.anfrage_id(str(t.id), sys, z, int(t.get("system", 0))), titel)
		if not bool(r2.ok):
			return { "grund": "fehlt" if str(r2.grund) == "" else r2.grund }
		t = Screenscraper.lesen(r2.data, sprache)
		if not bool(t.ok):
			return {}
	return { "info": t }


## MD5 einer Datei, im Hintergrund gelesen ("" wenn nicht lesbar).
func md5_datei(p: String) -> String:
	if not Sicher.local_path_ok(p):
		return ""
	var md5: Variant = await Arbeit.ergebnis(_md5_lesen.bind(p), Arbeit.LANG)
	return md5 if md5 is String else ""


static func _md5_lesen(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	while f.get_position() < f.get_length():
		if Arbeit.endet:
			return ""
		ctx.update(f.get_buffer(1024 * 1024))
	return ctx.finish().hex_encode()


## Was ScreenScraper zu einem Spiel weiß (im Eintrag gemerkt, „ss“: { id, medien, v, t } ohne
## Zugangsdaten bzw. { fehlt: Zeitpunkt }). Eine Anfrage je Spiel, nacheinander mit Pause.
## neu: Alles ersetzen – auch „nicht gefunden“ neu fragen, Gemerktes ab SS_ALT_TAGE auch.
func ss_info(game: Dictionary, neu := false) -> Dictionary:
	var gid := str(game.get("id", ""))
	if _ss_frisch(game, neu):
		return game.ss
	var ss: Variant = game.get("ss")
	var jetzt := int(Time.get_unix_time_from_system())
	if not neu and ss is Dictionary and int((ss as Dictionary).get("fehlt", 0)) > jetzt - SS_FEHLT_TAGE * 86400:
		_ss_grund[gid] = "fehlt"
		return {}
	if not Screenscraper.kennt(game):
		_ss_grund[gid] = "fehlt"
		return {}
	# Abgelehnt (Limit, Zugang): Was schon gemerkt ist, gilt weiter.
	if _ss_aus != "" and Time.get_ticks_msec() - _ss_aus_ms < AUS_MS:
		_ss_grund[gid] = _ss_aus
		return ss if ss is Dictionary and (ss as Dictionary).has("medien") else {}
	while _ss_busy.has(gid):
		await get_tree().process_frame
	if _ss_frisch(game, neu):
		return game.ss
	_ss_busy[gid] = true
	var r := await _ss_suchen(game)
	var out := {}
	if r.has("info"):
		out = _ss_merken(game, r.info)
		_ss_grund.erase(gid)
	else:
		# Ohne Grund (die Suche brach ab): wie „Netz“, damit nichts für zwei Wochen als „fehlt“ gemerkt wird.
		var grund := str(r.get("grund", "netz"))
		_ss_grund[gid] = grund
		if grund == "fehlt":
			for g in [game, Library.get_game(gid)]:
				if not (g as Dictionary).is_empty():
					g["ss"] = { "fehlt": jetzt }
			Library.mark_dirty()
		elif ss is Dictionary and (ss as Dictionary).has("medien"):
			out = ss
	_ss_busy.erase(gid)
	return out


## Ist das Gemerkte zu einem Spiel gut genug (Stand, beim Ersetzen nicht zu alt)?
func _ss_frisch(game: Dictionary, neu: bool) -> bool:
	var ss: Variant = game.get("ss")
	if not (ss is Dictionary) or not (ss as Dictionary).has("medien") or int((ss as Dictionary).get("v", 1)) < Screenscraper.MEDIEN_STAND:
		return false
	return not neu or int(Time.get_unix_time_from_system()) - int((ss as Dictionary).get("t", 0)) < SS_ALT_TAGE * 86400


## Ein gefundenes Spiel merken: im Eintrag die besten Medien, im Cache alle Kandidaten.
func _ss_merken(game: Dictionary, info: Dictionary) -> Dictionary:
	var gid := str(game.get("id", ""))
	var jetzt := int(Time.get_unix_time_from_system())
	var out := { "id": str(info.id), "medien": info.medien, "v": Screenscraper.MEDIEN_STAND, "t": jetzt }
	for g in [game, Library.get_game(gid)]:
		if not (g as Dictionary).is_empty():
			g["ss"] = out
	Library.mark_dirty()
	var k := { "id": str(info.id), "name": str(info.get("name", "")), "liste": info.get("kandidaten", {}), "t": jetzt }
	if gid != "":
		_ss_kand[gid] = k
		Config.cap(_ss_kand, 200)
		DirAccess.make_dir_recursive_absolute(Config.path(SS_KAND_DIR))
		Config.write_json(_ss_kand_datei(gid), k)
	return out


func _ss_kand_datei(gid: String) -> String:
	return Config.path(SS_KAND_DIR).path_join(gid.md5_text() + ".json")


## Gibt es für dieses Spiel die Bildwahl von ScreenScraper? (Programmzugang im Paket; PC-Spiel oder
## Emulator-Spiel eines Systems, das ScreenScraper kennt.)
static func ss_bildwahl_ok(game: Dictionary) -> bool:
	return Screenscraper.zugang().has("devid") and Screenscraper.kennt(game) \
			and (str(game.get("source", "")) in ["rom", "disc"] or Screenscraper.ist_pc(game))


## Bildwahl eines Spiels: alle Bilder von ScreenScraper je Bildart (Screenscraper.kandidaten).
## Gemerkt je Spiel (Sitzung und SS_KAND_DIR) – das schont das Tageskontingent. neu: trotzdem fragen.
## { ok, grund, id, name, liste: { Bildart: [{ url, fmt, typ, region }] } }.
func ss_kandidaten(game: Dictionary, neu := false) -> Dictionary:
	var gid := str(game.get("id", ""))
	if not Screenscraper.zugang().has("devid"):
		return { "ok": false, "grund": "zugang", "liste": {} }
	if not Screenscraper.kennt(game) or gid == "":
		return { "ok": false, "grund": "fehlt", "liste": {} }
	if not neu:
		var k := _ss_kand_gemerkt(gid)
		if not k.is_empty():
			return k
	var r := await _ss_suchen(game)
	if not r.has("info"):
		return { "ok": false, "grund": str(r.get("grund", "netz")), "liste": {} }
	_ss_merken(game, r.info)
	return _ss_kand_gemerkt(gid)


## Gemerkte Kandidaten eines Spiels ({} wenn keine oder zu alt). Die Datei wird streng geprüft.
func _ss_kand_gemerkt(gid: String) -> Dictionary:
	var k: Variant = _ss_kand.get(gid)
	if not (k is Dictionary):
		var f := _ss_kand_datei(gid)
		var fa := FileAccess.open(f, FileAccess.READ) if FileAccess.file_exists(f) else null
		if fa == null or fa.get_length() > 512 * 1024:
			return {}
		fa.close()
		k = Config.read_json(f, {})
	if not (k is Dictionary) or int((k as Dictionary).get("t", 0)) < int(Time.get_unix_time_from_system()) - SS_ALT_TAGE * 86400:
		return {}
	var id := str((k as Dictionary).get("id", ""))
	if not id.is_valid_int():
		return {}
	var liste := Screenscraper.kandidaten_pruefen((k as Dictionary).get("liste"))
	var out := { "ok": true, "grund": "", "id": id, "name": str((k as Dictionary).get("name", "")).left(Screenscraper.NAME_MAX), "liste": liste,
		"t": int((k as Dictionary).get("t", 0)) }
	_ss_kand[gid] = out
	return out


## „Anderes Spiel“ in der Bildwahl: nach Namen suchen. [[Kennung, Name]], höchstens 12.
func ss_suche(game: Dictionary, wort: String) -> Array:
	var sprache := "de" if TranslationServer.get_locale().begins_with("de") else "en"
	var r := await _ss_fragen(Screenscraper.anfrage_suche(wort, Screenscraper.schluessel(game), Screenscraper.zugang()), wort)
	var out: Array = []
	if not bool(r.ok):
		return out
	for t in Screenscraper.suche_lesen(r.data, sprache).slice(0, 12):
		_ss_treffer[str(t.id)] = t
		out.append([str(t.id), str(t.name) if str(t.name) != "" else str(t.id)])
	Config.cap(_ss_treffer, 60)
	return out


## Ein anderes Spiel bei ScreenScraper fürs Spiel übernehmen (aus ss_suche) und seine Kandidaten.
func ss_kandidaten_id(game: Dictionary, jeu_id: String) -> Dictionary:
	var t: Variant = _ss_treffer.get(jeu_id)
	if not (t is Dictionary) or ((t as Dictionary).get("kandidaten", {}) as Dictionary).is_empty():
		var sys_nr := int((t as Dictionary).get("system", 0)) if t is Dictionary else 0
		var r := await _ss_fragen(Screenscraper.anfrage_id(jeu_id, Screenscraper.schluessel(game), Screenscraper.zugang(), sys_nr), str(game.get("title", "")))
		if not bool(r.ok):
			return { "ok": false, "grund": str(r.grund), "liste": {} }
		t = Screenscraper.lesen(r.data, "de" if TranslationServer.get_locale().begins_with("de") else "en")
		if not bool(t.ok):
			return { "ok": false, "grund": "fehlt", "liste": {} }
	_ss_merken(game, t)
	return _ss_kand_gemerkt(str(game.get("id", "")))


var _ss_vq: Array = []              ## Vorschauen der Bildwahl: eine nach der anderen (ein Faden)
var _ss_v_laeuft := false


## Läufe von ss_vorschau, die gerade unterwegs sind (siehe dort).
var _ss_vorschau_offen := 0


## Vorschau eines Kandidaten (Bildwahl): klein von ScreenScraper, nacheinander geladen.
func ss_vorschau(url: String, breite: int, cb: Callable) -> void:
	_ss_vorschau_offen += 1
	await _ss_vorschau_lauf(url, breite, cb)
	_ss_vorschau_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und ss_vorschau täte bis zum Neustart nichts mehr.
	if _ss_vorschau_offen == 0 and _ss_v_laeuft:
		_ss_v_laeuft = false


func _ss_vorschau_lauf(url: String, breite: int, cb: Callable) -> void:
	var u := Screenscraper.vorschau(url, breite)
	if u == "":
		if cb.is_valid():
			cb.call(null)
		return
	_ss_vq.append([u, breite, guard(cb)])
	if _ss_v_laeuft:
		return
	_ss_v_laeuft = true
	while not _ss_vq.is_empty():
		var e: Array = _ss_vq.pop_front()
		var c: Callable = e[2]
		if not c.is_valid():
			continue
		var box := { "fertig": false }
		url_texture(Screenscraper.mit_zugang(str(e[0]), Screenscraper.zugang()), int(e[1]), func(t: Variant) -> void:
			box.fertig = true
			if c.is_valid():
				c.call(t)
		)
		while not box.fertig:
			await get_tree().process_frame
	_ss_v_laeuft = false


## Einen Kandidaten als Datei laden (Bildwahl): nur erlaubte Adressen und Formate, Bilddaten geprüft
## (Net.download). "" wenn es nicht ging.
func ss_datei(url: String, fmt: String, dest: String) -> String:
	if not Screenscraper.bild_ok(url) or Screenscraper.ohne_zugang(url) != url or not fmt in EXTS:
		return ""
	return await Net.download(Screenscraper.mit_zugang(url, Screenscraper.zugang()), dest)


## Warum ScreenScraper gerade nichts mehr holt ("" = alles gut): "zugang", "kontingent" oder "zu".
func ss_grund() -> String:
	return _ss_aus


## Ein Bild von ScreenScraper laden (cover, hero, logo, ruecken). Die Adresse wird nicht gemerkt
## (note_url): Sie ist ohne die Zugangsdaten nicht abrufbar, mit ihnen nicht öffentlich.
## info (freiwillig): { neu } hinein, { grund } heraus, wenn es nichts gab.
func _from_ss(game: Dictionary, kind: String, info: Dictionary = {}) -> String:
	var si := await ss_info(game, bool(info.get("neu", false)))
	var art := "cover" if kind == "cover_scan" else kind
	var m: Variant = (si.get("medien", {}) as Dictionary).get(art) if si.get("medien") is Dictionary else null
	if not (m is Dictionary):
		info["grund"] = str(_ss_grund.get(str(game.get("id", "")), "fehlt")) if si.is_empty() else "fehlt"
		return ""
	var roh := str((m as Dictionary).get("url", ""))
	var fmt := str((m as Dictionary).get("fmt", "png"))
	var url := Screenscraper.mit_zugang(roh, Screenscraper.zugang())
	if url == "" or not fmt in EXTS:
		info["grund"] = "fehlt"
		return ""
	var got := await Net.download(url, bild_ziel("ss", game, art, roh, fmt))
	if got == "":
		info["grund"] = "netz"
	return got


# --- Woher ein Bild kommt (Discord-Status) -----------------------------------------------------
# Der Discord-Status zeigt das Cover über seine öffentliche Adresse (Discord lädt es selbst). Dafür
# merkt sich Uzai beim Laden, von welcher Adresse eine Bilddatei stammt: image_urls im Eintrag,
# Pfad → Adresse. So zeigt der Status dasselbe Cover wie Uzai – eigene Dateien haben keine Adresse
# und verlassen den PC nie.

const URLS_MAX := 8      ## gemerkte Adressen je Spiel (Cover, Hintergrund, Logo …)


## Herkunft einer geladenen Datei merken (game kann eine Kopie sein; ohne ID nichts).
func note_url(game: Dictionary, path: String, url: String) -> void:
	if path == "" or url == "" or str(game.get("id", "")) == "":
		return
	for g in [game, Library.get_game(str(game.get("id", "")))]:
		if (g as Dictionary).is_empty():
			continue
		var urls: Dictionary = (g.get("image_urls", {}) as Dictionary).duplicate() if g.get("image_urls") is Dictionary else {}
		if str(urls.get(path, "")) == url:
			continue
		urls.erase(path)
		urls[path] = url
		while urls.size() > URLS_MAX:
			urls.erase(urls.keys()[0])
		g["image_urls"] = urls
	Library.mark_dirty()


## Öffentliche Adresse des Covers für den Discord-Status, ohne zu warten ("" = gerade keine):
## die Herkunft des Covers, das Uzai zeigt, sonst Epics Katalogbild, sonst Steams Bild (auch für
## EA-/Epic-/PC-Spiele mit gleichnamigem Steam-Spiel) aus den gemerkten Shop-Angaben. Ein eigenes
## Bild hat keine Adresse – dann das offizielle Cover, nie die Datei.
func presence_image_known(game: Dictionary) -> String:
	var urls: Variant = game.get("image_urls", {})
	if urls is Dictionary:
		var shown := str((urls as Dictionary).get(local_path(game, "cover"), ""))
		if GamePresence.image_ok(shown):
			return shown
	var art: Variant = game.get("art", {})
	if art is Dictionary and GamePresence.image_ok(str((art as Dictionary).get("cover", ""))):
		return str(art.cover)
	var appid := presence_appid(game)
	if appid > 0:
		_load_assets()
		var u := asset_url_from(_assets.get(_akey(appid), {}), "cover", str(appid))
		if GamePresence.image_ok(u):
			return u
	return ""


## Wie presence_image_known, darf aber fragen: Steams Shop-Angaben (neue Spiele haben Prüfsummen
## im Bildpfad) und bei Emulator-Spielen, ob die offizielle Hülle bei Libretro unter dem Namen des
## Spiels liegt (ein HEAD-Abruf je Name, höchstens drei; nur mit Libretro-Bildern in den
## Einstellungen). Eigene Dateien verlassen den PC nie – statt ihrer darf das offizielle Cover in
## den Status. Gefundenes bleibt im Eintrag, „nichts“ gilt bis zum nächsten Start von Uzai.
func presence_image(game: Dictionary) -> String:
	var known := presence_image_known(game)
	if known != "":
		return known
	var appid := presence_appid(game)
	if appid > 0:
		var u := await steam_asset_url(str(appid), "cover")
		if u == "":
			u = STEAM_CDN % [str(appid), STEAM_FILES.cover]
		return u if GamePresence.image_ok(u) else ""
	var sys := str(LIBRETRO_SYSTEMS.get(str(game.get("system", "")), ""))
	var miss := "%s:presence" % str(game.get("id", ""))
	if sys == "" or _missing.has(miss) or not bool(Config.get_value("library.libretro_images", true)):
		return ""
	var names := PackedStringArray()
	for n in [str(game.get("libretro_name", ""))] + Array(libretro_candidates(game)):
		if n != "" and not names.has(n) and names.size() < 3:
			names.append(n)
	for n in names:
		var url := LIBRETRO_ANY % [sys.uri_encode(), "Named_Boxarts", libretro_name(n).uri_encode()]
		if not GamePresence.image_ok(url):
			continue
		var r := await Net.request(url, PackedStringArray(), HTTPClient.METHOD_HEAD, "", 4.0, "img")
		if r.ok:
			# Gehört zum Cover aus Libretro (dieselbe Datei): dann gilt die Adresse künftig sofort.
			var cover := local_path(game, "cover")
			if cover.contains("/cache/img/libretro/"):
				note_url(game, cover, url)
			return url
	_missing[miss] = true
	return ""


# --- Cover ohne Schlüssel: Libretro-Vorschaubilder ------------------------------------------
# RetroArch pflegt freie Bilder für Emulator-Spiele, sortiert nach System und benannt wie die
# üblichen ROM-Dateien ("Spiel (Region)"): Cover, Spielszenen, Titelbilder und für viele Systeme
# auch Schriftzüge (Named_Logos). Uzai versucht erst den Dateinamen, dann den Titel, dann unscharf.

const LIBRETRO_DIR := "https://thumbnails.libretro.com/%s/%s/"
const LIBRETRO_GH := "https://raw.githubusercontent.com/libretro-thumbnails/%s/master/%s/%s.png"
const GH_TREE := "https://api.github.com/repos/libretro-thumbnails/%s/git/trees/%s"


## Bilder aus dem Spiel für die Spielseite. Steam (und EA-/Epic-/PC-Spiele mit gleichem Namen bei
## Steam): Store-Screenshots. Emulator-Spiele: Szenen aus Wikipedia (groß), RetroAchievements
## (Spielszene, Titelbild) und Libretro (Spielszene, Titelbild), mit Schlüssel auch Hintergründe
## von SteamGridDB. Liefert Adressen oder Dateipfade.
func screenshots(game: Dictionary) -> Array:
	var out: Array = []
	var appid := int(game.get("appid", 0)) if game.get("source") == "steam" else 0
	if game.get("source") in STEAM_MATCH_SOURCES and Config.get_value("library.steam_images", true):
		appid = await steam_match_id(game)
	if appid > 0:
		var d := await Store.details(appid)
		out.append_array(d.get("screens", []))
	# iiDB: Screenshots eines zugeordneten Spiels (eine Anfrage je Spiel und Sitzung).
	var von_iidb: Array = await iidb.screenshots(game)
	var sgdb := str(Config.get_value("accounts.sgdb_key", "")) != ""
	if game.get("source") in ["rom", "disc"]:
		# Emulator-Spiele: alle Szenen der Quellen und (mit Schlüssel) die Hintergründe von SteamGridDB.
		# Deine eigenen Bildschirmfotos stehen nicht hier, sondern im eigenen Abschnitt der Spielseite
		# (game_page.gd _build_captures).
		out = []
		for u in await rom_shots(game):
			if not u in out:
				out.append(u)
		for u in von_iidb:
			if not u in out:
				out.append(u)
		if sgdb:
			for u in await sgdb_urls(game, "heroes", 12):
				if not u in out:
					out.append(u)
	elif out.size() < 4:
		out.append_array(von_iidb.slice(0, 6 - out.size()))
		if out.size() < 4 and sgdb:
			out.append_array(await sgdb_urls(game, "heroes", 6 - out.size()))
	return out


## Spielszenen eines Emulator-Spiels, beste zuerst. Wird pro Spiel zwischengespeichert.
func rom_shots(game: Dictionary) -> Array:
	var gid := str(game.get("id", ""))
	# Spielseite und Hintergrund fragen oft gleichzeitig: nur einmal suchen.
	while _shots_busy.has(gid):
		await get_tree().process_frame
	if _shots.has(gid):
		return _shots[gid]
	_shots_busy[gid] = true
	# In einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird der Eintrag hier trotzdem gelöst. Sonst warteten
	# alle späteren Aufrufe für dieses Spiel in der Schleife oben für immer.
	var out := await _rom_shots_suchen(game)
	_shots[gid] = out
	Config.cap(_shots, 300)
	_shots_busy.erase(gid)
	return out


func _rom_shots_suchen(game: Dictionary) -> Array:
	var out: Array = []
	var title_imgs: Array = []
	if Config.get_value("library.web_info", true):
		var w := await wiki(game)
		out.append_array(Fremd.liste(w.get("shots")))
	if Achievements.has_ra():
		var ach := await Achievements.for_game(game)
		for u in Fremd.liste(ach.get("shots")):
			if not u in out:
				out.append(u)
	if Config.get_value("library.libretro_images", true):
		var snap := await libretro_find(game, "Named_Snaps")
		if snap != "":
			out.append(snap)
		var ttl := await libretro_find(game, "Named_Titles")
		if ttl != "":
			title_imgs.append(ttl)
	out.append_array(title_imgs)
	return out


var _shots := {}          # Spiel-ID -> Array (pro Sitzung)
var _shots_busy := {}


## Ein einzelnes Bild aus dem Spiel als Datei (für Hintergrund und Spielseite).
func _first_shot(game: Dictionary) -> String:
	for u in await rom_shots(game):
		var src := str(u)
		if not src.begins_with("http"):
			if FileAccess.file_exists(src):
				return src
			continue
		var ext := src.get_extension().get_slice("?", 0).to_lower()
		if not ext in EXTS:
			ext = "jpg"
		var got := await Net.download(src, Config.path("cache/img/web/%s.%s" % [src.md5_text(), ext]))
		if got != "":
			return got
	return ""


## Mehrere Bildadressen einer Art von SteamGridDB (grids, heroes, logos, icons).
func sgdb_urls(game: Dictionary, path_kind: String, limit := 6) -> Array:
	var key := str(Config.get_value("accounts.sgdb_key", ""))
	if key == "" or limit <= 0:
		return []
	var hdr := PackedStringArray(["Authorization: Bearer " + key])
	var api := "https://www.steamgriddb.com/api/v2"
	var url := ""
	if game.get("source") == "steam" and str(game.get("appid", "")) != "":
		url = "%s/%s/steam/%s" % [api, path_kind, str(game.appid)]
	else:
		var gid := str(game.get("sgdb_id", ""))
		if gid == "":
			var s := await Net.get_json("%s/search/autocomplete/%s" % [api, str(game.get("title", "")).uri_encode()], hdr)
			var treffer := Fremd.zeilen(s.data, "data") if s.ok else []
			var nummer := Fremd.zahl(treffer[0].get("id")) if not treffer.is_empty() else 0
			if nummer <= 0:
				return []
			gid = str(nummer)
		url = "%s/%s/game/%s" % [api, path_kind, gid]
	var r := await Net.get_json(url, hdr)
	var out: Array = []
	if r.ok and r.data is Dictionary:
		for it in Fremd.zeilen(r.data, "data").slice(0, limit):
			if str(it.get("url", "")) != "":
				out.append(str(it.url))
	return out


## Bild aus Libretro als Datei ("" wenn keins): erst unter dem Dateinamen bzw. Titel, dann
## unscharf gesucht im Verzeichnis des Systems. Libretro-Server zuerst, sonst der GitHub-Spiegel.
func libretro_find(game: Dictionary, folder: String) -> String:
	var sys := str(LIBRETRO_SYSTEMS.get(str(game.get("system", "")), ""))
	if sys == "":
		return ""
	var tag: String = { "Named_Boxarts": "cover", "Named_Snaps": "snap", "Named_Titles": "title", "Named_Logos": "logo" }.get(folder, folder)
	var dest := Config.path("cache/img/libretro/%s_%s.png" % [str(game.get("id", "x")).md5_text().substr(0, 16), tag])
	if FileAccess.file_exists(dest):
		return dest
	var miss_key := "%s:lr:%s" % [game.get("id", ""), folder]
	if _missing.has(miss_key):
		return ""
	var tried := PackedStringArray()
	# 1. Gemerkter oder genauer Name
	var names := PackedStringArray()
	var known := str(game.get("libretro_name", ""))
	if known != "":
		names.append(known)
	for n in libretro_candidates(game):
		if not names.has(n):
			names.append(n)
	for n in names:
		tried.append(n)
		var got := await _libretro_get(sys, folder, n, dest, game)
		if got != "":
			return got
	# 2. Unscharf im Verzeichnis
	var idx := await libretro_index(sys, folder)
	var nkey := sys + "/" + folder
	if not _norms.has(nkey):
		# Das Verzeichnis eines großen Systems hat Tausende Namen: gemessen 80 ms für 12.000. Im Hilfsfaden,
		# und nur einmal, auch wenn mehrere Spiele desselben Systems zugleich danach fragen.
		if _norms_bau.has(nkey):
			while _norms_bau.has(nkey):
				await get_tree().process_frame
		else:
			_norms_bau[nkey] = true
			var gebaut: Variant = await Arbeit.ergebnis(RetroMatch.build_norms.bind(idx))
			_norms[nkey] = gebaut if gebaut is Dictionary else {}
			_norms_bau.erase(nkey)
	# Der unscharfe Vergleich geht durch das ganze Verzeichnis: gemessen 6 ms je Spiel bei 12.000 Namen. Kommen die
	# Antworten für eine ganze Reihe Cover im selben Bild zurück, stand so alles (100 Spiele: 0,6 s). Im Hilfsfaden;
	# Verzeichnis und vorbereitete Namen werden nach dem Laden nur noch gelesen.
	var best_v: Variant = await Arbeit.ergebnis(RetroMatch.best_name.bind(libretro_candidates(game), idx, _norms.get(nkey, {})))
	var best := str(best_v) if best_v is String else ""
	if best != "" and not tried.has(best):
		var got2 := await _libretro_get(sys, folder, best, dest, game)
		if got2 != "":
			_remember_name(game, best)
			return got2
	_missing[miss_key] = true
	return ""


func _libretro_get(sys: String, folder: String, name: String, dest: String, game := {}) -> String:
	var file := libretro_name(name).uri_encode()
	for url in [LIBRETRO_ANY % [sys.uri_encode(), folder, file], LIBRETRO_GH % [sys.replace(" ", "_"), folder, file]]:
		var got := await Net.download(url, dest)
		if got != "":
			note_url(game, got, url)
			return got
	return ""


func _remember_name(game: Dictionary, name: String) -> void:
	for g in [game, Library.get_game(str(game.get("id", "")))]:
		if not (g as Dictionary).is_empty():
			g["libretro_name"] = name
	Library.mark_dirty()


var _index := {}          # System/Ordner -> PackedStringArray
var _index_busy := {}
var _norms := {}          # System/Ordner -> vorbereitetes Verzeichnis
var _norms_bau := {}      # System/Ordner -> true, solange das Verzeichnis gerade vorbereitet wird


## Alle Bildnamen eines Libretro-Ordners (einmal geladen, 30 Tage auf der Platte gemerkt).
func libretro_index(sys: String, folder: String) -> PackedStringArray:
	var key := sys + "/" + folder
	while _index_busy.has(key):
		await get_tree().process_frame
	if _index.has(key):
		return _index[key]
	_index_busy[key] = true
	# In einer eigenen Funktion, aus demselben Grund wie bei rom_shots.
	var names := await _index_laden(sys, folder, key)
	_index[key] = names
	_index_busy.erase(key)
	return names


## Lesen der gemerkten Liste, Zerlegen der Antwort und Schreiben laufen im Hilfsfaden: Beim ersten Cover eines
## Systems stand sonst alles (gemessen an 12.000 Namen: Verzeichnisseite 35 ms, GitHub-Baum 151 ms, dazu Lesen bzw.
## Schreiben der gemerkten Liste) – im Raster der Bibliothek je System einmal, mitten im Blättern.
func _index_laden(sys: String, folder: String, key: String) -> PackedStringArray:
	var file := Config.path("cache/libretro/%s.json" % key.md5_text())
	var now := int(Time.get_unix_time_from_system())
	var gelesen: Variant = await Arbeit.ergebnis(_index_von_platte.bind(file))
	var disk: Dictionary = gelesen if gelesen is Dictionary else {}
	var names := PackedStringArray()
	var stale: PackedStringArray = disk.get("names", PackedStringArray())
	if not disk.is_empty() and now - int(disk.get("t", 0)) < 30 * 86400:
		names = stale
	else:
		var r := await Net.request(LIBRETRO_DIR % [sys.uri_encode(), folder], PackedStringArray(), HTTPClient.METHOD_GET, "", 40.0)
		if r.ok:
			names = await _listing(r.body)
		if names.is_empty():
			var repo := sys.replace(" ", "_")
			var root := await Net.get_json(GH_TREE % [repo, "master"])
			if root.ok and root.data is Dictionary:
				for e in Fremd.zeilen(root.data, "tree"):
					if str(e.get("path", "")) == folder:
						var sub := await Net.request(GH_TREE % [repo, str(e.get("sha", ""))], PackedStringArray(), HTTPClient.METHOD_GET, "", 40.0)
						if sub.ok:
							names = await _listing(sub.body)
		if not names.is_empty():
			Arbeit.los(Config.write_json.bind(file, { "t": now, "names": Array(names) }))
		elif not stale.is_empty():
			names = stale          # offline: die alte Liste tut es auch
		else:
			# Nichts bekommen: morgen wieder fragen, nicht bei jedem Spiel.
			Config.write_json(file, { "t": now - 29 * 86400, "names": [] })
	return names


## Die gemerkte Liste von der Platte: { t, names } oder {} (fehlt oder taugt nicht). Läuft im Hilfsfaden.
static func _index_von_platte(file: String) -> Dictionary:
	var disk: Variant = Config.read_json(file, {})
	if not (disk is Dictionary):
		return {}
	var roh: Variant = disk.get("names", [])
	var namen := PackedStringArray()
	if roh is Array:
		for n: Variant in roh:
			if n is String:
				namen.append(n)
	return { "t": Fremd.zahl(disk.get("t")), "names": namen }


func _listing(body: PackedByteArray) -> PackedStringArray:
	var v: Variant = await Arbeit.ergebnis(RetroMatch.parse_listing_bytes.bind(body))
	return v if v is PackedStringArray else PackedStringArray()


# --- Wikipedia: Spielszenen und Beschreibung für Emulator-Spiele -------------------------------
# Ohne Schlüssel. Englische Seite für die Bilder (dort gibt es fast immer eine Spielszene),
# die deutsche Seite (über den Sprachlink) für den Text.

const WIKI_EN := "https://en.wikipedia.org/w/api.php?"
const WIKI_DE := "https://de.wikipedia.org/w/api.php?"
var _wiki := {}


## { page, about, shots: [Adressen] } oder {} wenn nichts Passendes gefunden wurde.
func wiki(game: Dictionary) -> Dictionary:
	var gid := str(game.get("id", ""))
	if _wiki.has(gid):
		return _wiki[gid]
	var file := Config.path("cache/wiki/%s.json" % gid.md5_text())
	var now := int(Time.get_unix_time_from_system())
	var disk: Variant = Config.read_json(file, null)
	if disk is Dictionary and now - Fremd.zahl(disk.get("t")) < (30 if str(disk.get("page", "")) != "" else 7) * 86400:
		_wiki[gid] = disk
		Config.cap(_wiki, 300)
		return disk
	var res := await _wiki_fetch(game)
	if res.get("error", false):
		return {}
	res["t"] = now
	Config.write_json(file, res)
	_wiki[gid] = res
	Config.cap(_wiki, 300)
	return res


func _wiki_fetch(game: Dictionary) -> Dictionary:
	var title := str(Library.display_title(game))
	var sysname := str(Config.system(str(game.get("system", ""))).get("name", ""))
	var s := await Net.get_json(WIKI_EN + Net.query({ "action": "query", "format": "json", "formatversion": 2,
		"list": "search", "srlimit": 6, "srsearch": "%s %s video game" % [title, sysname] }))
	if not s.ok or not (s.data is Dictionary):
		return { "error": true }
	var page := RetroMatch.wiki_pick(Fremd.liste(s.data, "query/search"), title)
	if page == "":
		return {}
	var p := await Net.get_json(WIKI_EN + Net.query({ "action": "query", "format": "json", "formatversion": 2,
		"prop": "images|langlinks", "titles": page, "imlimit": 80, "lllang": "de", "redirects": 1 }))
	if not p.ok or not (p.data is Dictionary):
		return { "error": true }
	var pages := Fremd.zeilen(p.data, "query/pages")
	if pages.is_empty():
		return {}
	var pg: Dictionary = pages[0]
	var out := { "page": page, "about": "", "shots": [] }
	var files := RetroMatch.wiki_shots(Fremd.liste(pg.get("images"))).slice(0, 12)
	if not files.is_empty():
		var ii := await Net.get_json(WIKI_EN + Net.query({ "action": "query", "format": "json", "formatversion": 2,
			"prop": "imageinfo", "iiprop": "url", "iiurlwidth": 1600, "titles": "|".join(files) }))
		if ii.ok and ii.data is Dictionary:
			for f in Fremd.zeilen(ii.data, "query/pages"):
				var info := Fremd.zeilen(f.get("imageinfo"))
				if not info.is_empty():
					var u := str(info[0].get("thumburl", info[0].get("url", "")))
					if u != "":
						out.shots.append(u)
	var de := ""
	for l in Fremd.zeilen(pg.get("langlinks")):
		if str(l.get("lang", "")) == "de":
			de = str(l.get("title", l.get("*", "")))
	if de != "":
		var x := await Net.get_json(WIKI_DE + Net.query({ "action": "query", "format": "json", "formatversion": 2,
			"prop": "extracts", "exintro": 1, "explaintext": 1, "exsentences": 5, "titles": de, "redirects": 1 }))
		if x.ok and x.data is Dictionary:
			var xp := Fremd.zeilen(x.data, "query/pages")
			if not xp.is_empty():
				out.about = str(xp[0].get("extract", "")).strip_edges()
				out["page_de"] = de
	return out


# --- SteamGridDB: alles auf einmal holen -----------------------------------------------------

signal sgdb_progress(done: int, total: int, title: String)
## Spiele scrapen läuft (scrape_all): ein Ja/Nein, nur gemeldet – „laeuft“ oder nichts (leer: ruht).
var sgdb_running := false:
	set(neu):
		if neu != sgdb_running:
			Zustand.melden("bibliothek.scrapen", "laeuft" if neu else "")
		sgdb_running = neu
var _sgdb_stop := false
## Bildarten beim Scrapen: Symbol von SteamGridDB und iiDB, Rücken nur von ScreenScraper (box-2D-side).
const SCRAPE_KINDS := ["cover", "hero", "logo", "icon", "ruecken"]
const QUELLE_NAME := { "ss": "ScreenScraper", "sgdb": "SteamGridDB", "iidb": "iiDB" }
## Stand der Bilder: zählt hoch, wenn ein Bild ersetzt wurde (Scrapen, Bildwahl). Raster und Regal
## bauen dann neu, auch wenn dieselben Spiele dastehen.
var bilder_stand := 0
var scrape_test := {}    ## nur für Tests (logic_screenscraper): Quelle → Callable(game, kind, info) statt Netz


## Holt Cover, Hintergrund, Schriftzug und Symbol von SteamGridDB – nur für Emulator-Spiele (Steam,
## Epic und Co. bringen ihre Bilder selbst mit; für sie gilt „Spiele scrapen“).
## replace: auch Bilder ersetzen, die schon da sind (eigene, selbst gewählte Bilder bleiben immer).
## Gibt { games, images, failed } zurück.
func import_sgdb_all(replace := false) -> Dictionary:
	var sys := retro_systeme()
	if sys.is_empty():
		return scrape_leer(["sgdb"])
	return await scrape_all(["sgdb"], replace, sys)


## Systeme der Emulator-Spiele (für „nur Retro“ beim Scrapen).
static func retro_systeme() -> Array:
	var out: Array = []
	for g in sgdb_games():
		var s := str(g.get("system", ""))
		if s != "" and not s in out:
			out.append(s)
	return out


## Welche Quellen zum Bilderholen gerade gehen: "ss" (ScreenScraper, ohne eigenen Schlüssel),
## "sgdb" und "iidb" (jeweils mit eigenem Schlüssel).
func scrape_quellen() -> Array:
	var out: Array = []
	if str(Config.get_value("accounts.sgdb_key", "")) != "":
		out.append("sgdb")
	if Screenscraper.verfuegbar():
		out.append("ss")
	if iidb.verbunden():
		out.append("iidb")
	return out


## iiDB wurde verbunden: beim Scrapen mitnehmen (hinten, nach den bisherigen Quellen), wenn es dort
## noch nicht steht. Die Reihenfolge ändert das Menü „Spiele scrapen“.
func iidb_einschalten() -> void:
	var wahl := scrape_wahl_roh()
	if not wahl.has("iidb"):
		wahl.append("iidb")
		Config.set_value("library.scrape_quellen", wahl)


## Gewählte Quellen fürs Scrapen in ihrer Reihenfolge (Menü „Spiele scrapen“, library.scrape_quellen),
## so wie gespeichert – auch, wenn eine gerade nicht geht.
static func scrape_wahl_roh() -> Array:
	return quellen_pruefen(Config.get_value("library.scrape_quellen", null))


## Hat der Nutzer die Quellen selbst gewählt (Menü „Spiele scrapen“)? Sonst gilt die Vorgabe
## (scrape_quellen_fuer). library.scrape_quellen hat einen Standardwert, darum ein eigenes Merkmal.
static func scrape_wahl_gesetzt() -> bool:
	return bool(Config.get_value("library.scrape_quellen_eigen", false))


## Quellen für ein Spiel beim Scrapen: die Wahl gilt für alle Spiele. Ohne eigene Wahl bleibt bei
## PC-Spielen SteamGridDB vorn (ihre bisherige Quelle), ScreenScraper kommt danach.
static func scrape_quellen_fuer(g: Dictionary, quellen: Array, gesetzt: bool) -> Array:
	if gesetzt or not Screenscraper.ist_pc(g) or not quellen.has("sgdb"):
		return quellen
	var out: Array = ["sgdb"]
	out.append_array(quellen.filter(func(q: Variant) -> bool: return str(q) != "sgdb"))
	return out


## Gewählte Quellen, die gerade gehen (leer: die Wahl geht so nicht – das Menü sagt, warum).
func scrape_wahl() -> Array:
	var geht := scrape_quellen()
	return scrape_wahl_roh().filter(func(q: String) -> bool: return q in geht)


## Läufe von scrape_all, die gerade unterwegs sind (siehe dort).
var _scrape_all_offen := 0


## Bilder für alle Spiele holen (Spiele scrapen: Emulator- und PC-Spiele): je Spiel und Bildart die
## Quellen der Reihe nach, bis eine etwas hat. systeme: nur diese Systeme (leer: alle). Mit
## ScreenScraper so viele zugleich, wie das Konto Fäden hat (ohne Konto eins), sonst drei zugleich.
## sgdb_progress meldet den Fortschritt.
## Ergebnis: { games, images, failed, gleich, eigen, quellen: { ss|sgdb: { geholt, grund: { Grund: n } } } }
## – genug für eine ehrliche Mitteilung je Quelle (scrape_meldung); dazu logs/scrape.log.
func scrape_all(quellen: Array, replace := false, systeme: Array = []) -> Dictionary:
	_scrape_all_offen += 1
	var ergebnis: Dictionary = await _scrape_all_lauf(quellen, replace, systeme)
	_scrape_all_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und scrape_all täte bis zum Neustart nichts mehr.
	if _scrape_all_offen == 0 and sgdb_running:
		sgdb_running = false
		sgdb_progress.emit(0, 0, "")
		log_line("scrape", "Spiele scrapen: mit einem Fehler abgebrochen")
	# Nach einem Abbruch ist das Ergebnis leer: Die Mitteilung braucht trotzdem ihre Felder.
	return ergebnis if not ergebnis.is_empty() else scrape_leer(quellen)


func _scrape_all_lauf(quellen: Array, replace := false, systeme: Array = []) -> Dictionary:
	quellen = quellen.filter(func(q: Variant) -> bool: return str(q) in scrape_quellen())
	if sgdb_running or quellen.is_empty():
		return scrape_leer(quellen)
	sgdb_running = true
	_sgdb_stop = false
	_ss_aus = ""
	_sgdb_aus = ""
	ss_kontingent = {}
	var games: Array = scrape_spiele()
	var gesetzt := scrape_wahl_gesetzt()
	if not systeme.is_empty():
		games = games.filter(func(g: Dictionary) -> bool: return str(g.get("system", "")) in systeme)
	var res := scrape_leer(quellen)
	var namen := PackedStringArray(quellen.map(func(q: String) -> String: return str(QUELLE_NAME.get(q, q))))
	var nur := PackedStringArray(systeme.map(func(x: Variant) -> String: return str(x)))
	log_line("scrape", "— Spiele scrapen: %s · %s · %d Spiele%s" % [" → ".join(namen), "Alles ersetzen" if replace else "Fehlende holen", games.size(),
			(" · Systeme: " + ", ".join(nur)) if not nur.is_empty() else ""])
	if quellen.has("ss"):
		log_line("scrape", "ScreenScraper: Programmzugang da, %s" % ("eigenes Konto" if Screenscraper.zugang().has("ssid") else "ohne eigenes Konto"))
	var done := 0
	var box := { "running": 0 }
	if quellen.has("iidb"):
		# iiDB zuerst im Ganzen: 25 Spiele je Anfrage zuordnen und die empfohlenen Bilder merken.
		sgdb_progress.emit(0, games.size(), tr("iiDB ordnet Spiele zu …"))
		iidb.pause_aus()
		var warum: String = await iidb.zuordnen(games, IidbDienst.AUTO_SLOTS, replace, func() -> bool: return _sgdb_stop)
		if warum != "":
			log_line("scrape", "iiDB: Zuordnen abgebrochen (%s)" % warum)
	for g in games:
		if _sgdb_stop:
			break
		while int(box.running) >= (Screenscraper.faeden(_ss_grenzen) if quellen.has("ss") else 3):
			await get_tree().process_frame
		box.running = int(box.running) + 1
		_scrape_one(g, scrape_quellen_fuer(g, quellen, gesetzt), replace, res, box)
		done += 1
		sgdb_progress.emit(done, games.size(), str(Library.display_title(g)))
	while int(box.running) > 0:
		await get_tree().process_frame
	sgdb_running = false
	Library.mark_dirty()
	Library.changed.emit()
	sgdb_progress.emit(games.size(), games.size(), "")
	var m := scrape_meldung(res)
	var kont := (" · Kontingent heute %d/%d" % [int(ss_kontingent.heute), int(ss_kontingent.max)]) if int(ss_kontingent.get("max", -1)) > 0 else ""
	log_line("scrape", "Ergebnis: %s · %s%s" % [m[0], m[1], kont])
	return res


static func scrape_leer(quellen: Array) -> Dictionary:
	var q := {}
	for k in quellen:
		q[str(k)] = { "geholt": 0, "gleich": 0, "grund": {} }
	return { "games": 0, "images": 0, "failed": 0, "gleich": 0, "eigen": 0, "quellen": q }


## Mitteilung am Ende: [Titel, Zeile]. Je Quelle, was kam – oder ehrlich, warum nichts kam.
static func scrape_meldung(res: Dictionary) -> Array:
	var T := func(t: String) -> String: return TranslationServer.translate(t)
	var neu := int(res.get("images", 0))
	var titel: String = (T.call("Bilder geholt: %d neu") % neu) if neu > 0 else T.call("Keine neuen Bilder")
	var teile := PackedStringArray()
	var q: Dictionary = res.get("quellen", {}) if res.get("quellen") is Dictionary else {}
	for k in q.keys():
		var e: Dictionary = q[k]
		var name := str(QUELLE_NAME.get(k, k))
		var gr: Dictionary = e.get("grund", {}) if e.get("grund") is Dictionary else {}
		var stoer := ""
		for w in ["zugang", "kontingent", "zu", "netz"]:
			if int(gr.get(w, 0)) > 0:
				stoer = w
				break
		if stoer == "zugang" and k != "ss":
			teile.append(T.call("%s: Schlüssel abgelehnt") % name)
		elif stoer == "kontingent" and k != "ss":
			teile.append(T.call("%s: Limit erreicht") % name)
		elif stoer != "":
			teile.append("%s: %s" % [name, T.call(Screenscraper.grund_text(stoer))])
		elif int(e.get("geholt", 0)) > 0:
			teile.append("%s: %d" % [name, int(e.geholt)])
		elif int(e.get("gleich", 0)) > 0:
			teile.append(T.call("%s: schon aktuell") % name)
		else:
			teile.append(T.call("%s: nicht gefunden") % name)
	if int(res.get("wahl", 0)) > 0:
		teile.append(T.call("%d bei iiDB zur Wahl (Spieloptionen → Bild wählen)") % int(res.wahl))
	if int(res.get("eigen", 0)) > 0:
		teile.append(T.call("%d eigene behalten") % int(res.eigen))
	if int(res.get("failed", 0)) > 0:
		teile.append(T.call("%d Spiele ohne Treffer") % int(res.failed))
	return [titel, " · ".join(teile)]


## Ging beim Scrapen etwas schief (Ablehnung, Limit, Netz, Spiele ohne Treffer)? Dann lohnt das Protokoll.
static func scrape_problem(res: Dictionary) -> bool:
	if int(res.get("failed", 0)) > 0:
		return true
	var q: Dictionary = res.get("quellen", {}) if res.get("quellen") is Dictionary else {}
	for k in q.keys():
		var gr: Variant = (q[k] as Dictionary).get("grund", {})
		if gr is Dictionary:
			for w in ["zugang", "kontingent", "zu", "netz"]:
				if int((gr as Dictionary).get(w, 0)) > 0:
					return true
	return false


func stop_sgdb() -> void:
	_sgdb_stop = true


## Spiele, für die SteamGridDB Bilder holt: sichtbare Emulator-Spiele, auch von der Disc (sie haben
## sonst selten einen echten Hintergrund).
static func sgdb_games() -> Array:
	return Library.visible_games().filter(func(g: Dictionary) -> bool: return str(g.get("source", "")) in ["rom", "disc"])


## Wie viele davon noch ohne Cover sind (weder selbst gewählt noch geladen).
func sgdb_missing() -> int:
	return _fehlt_gemerkt("sgdb", sgdb_games)


## Spiele fürs Scrapen (Menü „Spiele scrapen“): alle sichtbaren Emulator- und PC-Spiele (keine Apps).
static func scrape_spiele() -> Array:
	return Library.visible_games().filter(func(g: Dictionary) -> bool:
		return str(g.get("source", "")) in ["rom", "disc"] or Screenscraper.ist_pc(g))


## Wie viele Spiele fürs Scrapen noch ohne Cover sind.
func scrape_fehlt() -> int:
	return _fehlt_gemerkt("scrape", scrape_spiele)


## Die Zahl gilt FEHLT_MS lang, solange sich weder die Bibliothek noch der Stand der Bilder geändert hat: Sie steht
## an fünf Stellen der Oberfläche, und zwei davon bauen bei jedem Schritt neu (Einstellungen › Spiele, die
## Filterleiste der Bibliothek) – je Mal ein Durchgang über alle Spiele (gemessen 50 bis 70 ms bei 1800).
## Bei unverändertem Stand kann sich die Zahl nur ändern, weil jemand Bilder von Hand in den Medienordner gelegt
## hat. Dann gilt die bekannte Zahl sofort weiter; ist sie älter als FEHLT_MS, zählt Uzai nebenbei nach (in
## Scheiben über mehrere Bilder) statt alle fünf Sekunden wieder in einem Zug.
const FEHLT_MS := 5000
const FEHLT_SCHEIBE := 150       ## so viele Spiele je Bild beim Nachzählen
var _fehlt_merk := {}            ## Art → [Zahl, wann (ms), Stand]
var _fehlt_zaehlt := {}          ## Art → true, solange nachgezählt wird


func _fehlt_gemerkt(art: String, liste: Callable) -> int:
	var stand := [Library.games.size(), Library.aenderung(), bilder_stand]
	var m: Variant = _fehlt_merk.get(art)
	if m is Array and m[2] == stand:
		if Time.get_ticks_msec() - int(m[1]) >= FEHLT_MS and not _fehlt_zaehlt.has(art):
			_fehlt_nachzaehlen(art, liste.call(), stand)
		return int(m[0])
	var n := _ohne_cover(liste.call())
	_fehlt_merk[art] = [n, Time.get_ticks_msec(), stand]
	return n


func _fehlt_nachzaehlen(art: String, spiele: Array, stand: Array) -> void:
	_fehlt_zaehlt[art] = true
	var n := 0
	var i := 0
	while i < spiele.size():
		n += _ohne_cover(spiele.slice(i, i + FEHLT_SCHEIBE))
		i += FEHLT_SCHEIBE
		if i < spiele.size():
			await get_tree().process_frame
	_fehlt_zaehlt.erase(art)
	# Hat sich inzwischen der Stand geändert, ist dort schon frisch gezählt.
	var m: Variant = _fehlt_merk.get(art)
	if m is Array and m[2] == stand:
		_fehlt_merk[art] = [n, Time.get_ticks_msec(), stand]


func _ohne_cover(liste: Array) -> int:
	var n := 0
	for g in liste:
		if str(Fremd.verz(g.get("images")).get("cover", "")) == "" and local_path(g, "cover") == "":
			n += 1
	return n


## Ein Bild wurde geholt: die Kachel weiß davon (scrape_bild meldet es für die Vorschau im Menü).
signal scrape_bild(game_id: String, kind: String, path: String)


## Kann diese Quelle diese Bildart? (Symbol von SteamGridDB und iiDB, Rücken nur ScreenScraper.)
static func quelle_kann(q: String, kind: String) -> bool:
	return (q in ["sgdb", "iidb"] and kind != "ruecken") or (q == "ss" and kind != "icon")


func _scrape_one(g: Dictionary, quellen: Array, replace: bool, res: Dictionary, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _scrape_one_arbeit(g, quellen, replace, res, box)
	box.running = int(box.running) - 1


func _scrape_one_arbeit(g: Dictionary, quellen: Array, replace: bool, res: Dictionary, box: Dictionary) -> void:
	var gid := str(g.get("id", ""))
	var teile := PackedStringArray()
	var gesucht := false
	var neu_da := false
	var schon_da := false
	for kind in SCRAPE_KINDS:
		if _sgdb_stop:
			break
		# PC-Spiele: kein Rücken beim Scrapen (sonst fragte jedes Spiel ScreenScraper; Bildwahl geht).
		if kind == "ruecken" and Screenscraper.ist_pc(g):
			continue
		var qs: Array = quellen.filter(func(q: String) -> bool: return quelle_kann(q, kind))
		if qs.is_empty():
			continue
		if str(Fremd.verz(g.get("images")).get(kind, "")) != "":
			# Selbst gewählt (Bildwahl, eigene Datei): nie anfassen – aber ehrlich mitzählen.
			if replace:
				res.eigen = int(res.eigen) + 1
				teile.append(kind + " eigenes")
			continue
		var vorher := local_path(g, kind)
		if not replace and vorher != "":
			continue
		gesucht = true
		var path := ""
		var von := ""
		for q in qs:
			var info := { "neu": replace }
			if scrape_test.has(q):
				path = str(await (scrape_test[q] as Callable).call(g, kind, info))
			elif q == "sgdb":
				path = await _from_sgdb(g, kind, info)
			elif q == "iidb":
				path = await iidb.bild(g, kind, info)
			else:
				path = await _from_ss(g, kind, info)
			if path != "":
				von = q
				break
			var gr: Dictionary = res.quellen[q].grund
			var w := str(info.get("grund", "fehlt"))
			gr[w] = int(gr.get(w, 0)) + 1
			if _sgdb_stop:
				break
		if path == "":
			teile.append(kind + " –")
			continue
		var auto: Dictionary = (g.get("images_auto", {}) as Dictionary).duplicate() if g.get("images_auto") is Dictionary else {}
		var alt := str(auto.get(kind, ""))
		_missing.erase("%s:%s" % [gid, kind])
		_local.erase("%s:%s" % [gid, kind])
		if path == vorher or path == alt:
			res.gleich = int(res.gleich) + 1
			res.quellen[von].gleich = int(res.quellen[von].gleich) + 1
			schon_da = true
			teile.append("%s %s =" % [kind, von])
			continue
		auto[kind] = path
		# Die Hülle im Regal zeigt zuerst den Scan der Verpackung: Ein Cover von ScreenScraper
		# (box-2D) ist einer und ersetzt ihn mit, sonst bliebe dort das alte Bild stehen.
		var alt_scan := ""
		if kind == "cover" and von == "ss" and (replace or local_path(g, "cover_scan") == ""):
			alt_scan = str(auto.get("cover_scan", ""))
			auto["cover_scan"] = path
			_missing.erase(gid + ":cover_scan")
			_local.erase(gid + ":cover_scan")
		_alt_weg(alt, auto)
		_alt_weg(alt_scan, auto)
		g["images_auto"] = auto
		res.images = int(res.images) + 1
		res.quellen[von].geholt = int(res.quellen[von].geholt) + 1
		neu_da = true
		teile.append("%s %s" % [kind, von])
		scrape_bild.emit(gid, kind, path)
	if neu_da:
		res.games = int(res.games) + 1
		bilder_stand += 1
	elif gesucht and not schon_da:
		res.failed = int(res.failed) + 1
		# iiDB kennt mehrere Spiele mit dem Namen: kein Fehltreffer, der Nutzer wählt (Bildwahl).
		if quellen.has("iidb") and Iidb.gemerkt(g).has("wahl"):
			res["wahl"] = int(res.get("wahl", 0)) + 1
	if gesucht or not teile.is_empty():
		log_line("scrape", "%s [%s]: %s" % [str(g.get("title", "")).left(80), str(g.get("system", "")), ", ".join(teile)])


## Ein ersetztes Bild aus Uzais Cache löschen – nur aus den Ordnern, deren Dateien je Spiel benannt
## sind (nie eigene Dateien, Medienordner oder Steam-Bilder, die sich Spiele teilen), und nur, wenn
## keine Bildart des Spiels es noch zeigt (auto ist schon neu belegt).
func _alt_weg(alt: String, auto: Dictionary) -> void:
	if alt == "" or alt.contains("..") or alt in auto.values():
		return
	for o in ["cache/img/ss/", "cache/img/sgdb/", "cache/img/libretro/", "cache/img/iidb/"]:
		if alt.begins_with(Config.path(o)) and FileAccess.file_exists(alt):
			DirAccess.remove_absolute(alt)
			return


## Bildschirmfaktor: Uzai rechnet in 1920 × 1080, auf 4K zeichnet Godot alles doppelt so groß.
## Bilder werden entsprechend größer geladen, sonst wirken sie auf 4K weich (hochgezogen).
func px_scale() -> float:
	if not is_inside_tree():
		return 1.0
	# Leichter Modus: Bilder in der Größe für 1080p, auch auf größeren Bildschirmen (ein Viertel
	# des Speichers in 4K, schneller geladen; gezeichnet wird weich hochgezogen).
	return clampf(get_tree().root.get_final_transform().get_scale().x, 1.0, 1.0 if Leicht.active else 2.0)


var _bad := {}             # Pfad -> Änderungszeit: ließ sich nicht dekodieren (nicht jedes Mal neu)


## Bild aus einer Datei laden (im Hintergrund dekodiert).
func file_texture(path: String, max_w: int, cb: Callable) -> void:
	max_w = int(max_w * px_scale())
	_load_tex(path, "%s@%d" % [path, max_w], max_w, Vector2i.ZERO, cb)


## Bild für eine feste Fläche, die es wie STRETCH_KEEP_ASPECT_COVERED füllt (das Spielbild oben
## rechts im Hintergrund). Geladen wird nur der Ausschnitt, der dort zu sehen ist, und höchstens
## so groß, wie die Fläche auf dem Schirm ist (area in Uzai-Punkten, 4K rechnet px_scale hoch);
## ohne Mipmaps – es wird nie verkleinert gezeichnet. Ein Hero (3840 × 1240) ist viel breiter als
## die Fläche: Früher kam er ganz samt Mipmaps auf die Grafikkarte (in 4K gut 25 MB, je
## Blätterschritt auf dem Hauptthread), jetzt etwa 4 MB (1080p) bzw. 12 MB (4K) – und in 1080p
## schärfer, weil er nicht mehr erst auf 1920 Punkte Breite gerechnet und dann hochgezogen wird.
func fit_texture(path: String, area: Vector2, cb: Callable) -> void:
	var a := fit_area(area)
	_load_tex(path, _fit_key(path, a), 0, a, cb)


## Schon hochgeladenes Bild zu fit_texture, sonst null – lädt nichts.
func cached_fit(path: String, area: Vector2) -> Texture2D:
	if path == "":
		return null
	return _tex.get(_fit_key(path, fit_area(area))) as Texture2D


## Liegt das Bild zu fit_texture schon bereit oder wird es gerade geladen (Vorab-Laden)?
func has_fit(path: String, area: Vector2) -> bool:
	if path == "":
		return false
	var key := _fit_key(path, fit_area(area))
	return _tex.has(key) or _pending.has(key)


func fit_area(area: Vector2) -> Vector2i:
	var a := (area * px_scale()).round()
	return Vector2i(maxi(16, int(a.x)), maxi(16, int(a.y)))


func _load_tex(path: String, key: String, max_w: int, area: Vector2i, cb: Callable) -> void:
	cb = guard(cb)
	if not Sicher.local_path_ok(path):
		if cb.is_valid():
			cb.call(null)
		return
	if _bad.has(path):
		if int(_bad[path]) == FileAccess.get_modified_time(path):
			if cb.is_valid():
				cb.call(null)
			return
		_bad.erase(path)
	if _tex.has(key):
		var t: Texture2D = _tex[key]
		_tex.erase(key)
		_tex[key] = t
		if cb.is_valid():
			cb.call(t)
		return
	if _pending.has(key):
		_pending[key].append(cb)
		return
	_pending[key] = [cb]
	Arbeit.los(_decode.bind(path, max_w, key, area))


## Größe der Bilddatei hinter einer Textur aus file_texture/url_texture (vor dem Verkleinern),
## sonst die Größe der Textur selbst.
static func orig_groesse(t: Texture2D) -> Vector2i:
	if t == null:
		return Vector2i.ZERO
	var o: Variant = t.get_meta("uz_orig", null)
	return o if o is Vector2i else Vector2i(t.get_width(), t.get_height())


## Schon hochgeladenes Bild zu Datei und Breite (wie file_texture), sonst null – lädt nichts.
func cached_texture(path: String, max_w: int) -> Texture2D:
	if path == "":
		return null
	return _tex.get("%s@%d" % [path, int(max_w * px_scale())]) as Texture2D


func _decode(path: String, max_w: int, key: String, area := Vector2i.ZERO) -> void:
	var img := load_image(path)
	if img and not img.is_empty() and img.is_compressed():
		img.decompress()
	# Zuschnitt und Farbe (Zuschnitt.gd) gleich hier mitrechnen, einmal je Datei, danach aus dem
	# Zwischenspeicher: später aus der Textur zu lesen hieße, sie von der Grafikkarte zurückzuholen
	# (get_image), und das hält in Uzai.exe das Bild an.
	var look := {}
	var col: Variant = null
	var orig := Vector2i.ZERO
	if img and not img.is_empty():
		orig = img.get_size()
		look = look_for(path, img)
		col = look.get("c")
		# Cover (nicht Hintergründe): hat es schon den Rahmen eines Systems (Scan)? Fürs Regal.
		if area.x <= 0 and max_w <= 1100 and not look.is_empty() and orig.x * 3 > orig.y and orig.y * 3 > orig.x:
			look["r"] = Regal.rahmen_merken(path, img)
		_grund_merken(path, img)
		if area.x > 0:
			img = cover_image(img, area, look)
		elif img.get_width() > max_w:
			shrink_to(img, max_w)
	if img and not img.is_empty():
		# RGBA statt RGB (JPG): Ein RGB-Bild wandelt der OpenGL-Treiber beim Hochladen erst um,
		# auf dem Hauptthread – gemessen bis zum Fünffachen der Zeit. Hier im Hintergrund-Thread.
		if img.get_format() == Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGBA8)
		# Mipmaps: Kleiner gezeichnete Bilder (Cover in Reihen, Vorschauen) bleiben ruhig statt zu
		# flimmern. Im Hintergrund-Thread gerechnet. (Bilder für eine Fläche nicht, siehe oben.)
		if area.x <= 0 and img.get_width() >= 96:
			img.generate_mipmaps()
	call_deferred("_decoded", key, img, path, [col], look, orig)


func _drop_tex(key: String) -> void:
	_tex.erase(key)
	_tex_total -= int(_tex_bytes.get(key, 0))
	_tex_bytes.erase(key)


## Fertig dekodiert: nur vormerken. Hochgeladen wird in _process, ein paar je Bild – kamen
## viele zugleich an (Raster, Shop-Reihe), landeten sonst alle Uploads im selben Bild.
var _uploads: Array = []    # [Schlüssel, Image, Pfad, [Farbe], Zuschnitt-Analyse]
const UPLOAD_MAX := 3       ## höchstens so viele Bilder je Bild hochladen …
const UPLOAD_USEC := 4000   ## … und nach 4 ms keins mehr anfangen (eins geht immer)
var _hold_until := 0        ## bis dahin (ms) nur dringende Bilder hochladen (Überblendung läuft)
var _urgent := {}           ## Schlüssel, die sofort gebraucht werden
var upload_log: Array = []  ## [ms, Schlüssel, Dauer µs] der letzten Uploads (Protokoll Ruckler)
const SLOW_UPLOAD_USEC := 8000
var _slow_uploads := 0


func _ready() -> void:
	set_process(false)
	iidb = IidbDienst.new()
	iidb.name = "Iidb"
	add_child(iidb)
	Arbeit.los(_load_looks)
	Arbeit.los(_load_grund)


func _decoded(key: String, img: Image, path := "", col: Array = [], look := {}, orig := Vector2i.ZERO) -> void:
	_uploads.append([key, img, path, col, look, orig])
	set_process(true)


func _process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var n := 0
	var held := Time.get_ticks_msec() < _hold_until
	var i := 0
	while i < _uploads.size() and n < UPLOAD_MAX and (n == 0 or Time.get_ticks_usec() - t0 < UPLOAD_USEC):
		var u: Array = _uploads[i]
		# Während einer Überblendung warten vorab geladene Bilder (Nachbarn im Regal): ihr Hochladen
		# fiel sonst genau in die Überblendung, und die stockte.
		if held and not _urgent.has(str(u[0])):
			i += 1
			continue
		_uploads.remove_at(i)
		var u0 := Time.get_ticks_usec()
		_upload(str(u[0]), u[1], str(u[2]), u[3], u[4], u[5] if u.size() > 5 else Vector2i.ZERO)
		_urgent.erase(str(u[0]))
		var dauer := Time.get_ticks_usec() - u0
		upload_log.append([Time.get_ticks_msec(), str(u[0]).get_file(), dauer])
		# Ziel: kein Bild länger als 8 ms im Hauptthread. Was darüber liegt, steht im Protokoll.
		if dauer > SLOW_UPLOAD_USEC and _slow_uploads < 100:
			_slow_uploads += 1
			log_line("leistung", "Bild hochladen dauerte %d ms: %s" % [dauer / 1000, str(u[0]).get_file()])
		if upload_log.size() > 8:
			upload_log.pop_front()
		n += 1
	if _uploads.is_empty():
		set_process(false)


## Eine Weile nur dringende Bilder hochladen (siehe urgent): Der Hintergrund blendet gerade über.
func hold_uploads(sec: float) -> void:
	_hold_until = maxi(_hold_until, Time.get_ticks_msec() + int(sec * 1000.0))


## Dieses Bild wird sofort gebraucht (das gewählte Spiel): nie zurückhalten.
func urgent_fit(path: String, area: Vector2) -> void:
	if path != "":
		_urgent[_fit_key(path, fit_area(area))] = true


func _upload(key: String, img: Image, path: String, col: Array, look := {}, orig := Vector2i.ZERO) -> void:
	var tex: Texture2D = null
	if (img == null or img.is_empty()) and path != "" and FileAccess.file_exists(path):
		_bad[path] = FileAccess.get_modified_time(path)
	if img and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
		# Quelle und Farbe merken: color_of und soft kommen so ohne Rücklesen aus.
		if path != "":
			tex.set_meta("uz_src", path)
		if not col.is_empty():
			tex.set_meta("uz_vivid", col)
		# Wo das Wichtige im Bild liegt und wie hell es ist (Zuschnitt.put).
		if look.has("x"):
			tex.set_meta("uz_look", look)
		# Größe der Datei vor dem Verkleinern: taugt das Bild als Hero (hero_tauglich)?
		if orig.x > 0:
			tex.set_meta("uz_orig", orig)
		_tex[key] = tex
		var bytes := int(img.get_width() * img.get_height() * 4 * (1.34 if img.has_mipmaps() else 1.0))
		_tex_total += bytes - int(_tex_bytes.get(key, 0))
		_tex_bytes[key] = bytes
		# Leichter Modus: halb so viele Bilder auf der Grafikkarte.
		var k := Leicht.TEX_BUDGET_K if Leicht.active else 1.0
		var budget := int(MAX_TEX_BYTES * minf(px_scale(), 1.6) * k)
		while _tex.size() > 1 and (_tex.size() > int(MAX_TEX * k) or _tex_total > budget):
			_drop_tex(str(_tex.keys()[0]))
	var cbs: Array = _pending.get(key, [])
	_pending.erase(key)
	for cb in cbs:
		if (cb as Callable).is_valid():
			cb.call(tex)


## Kurzes Protokoll in logs/<name>.log (z. B. sgdb: warum SteamGridDB nichts geschickt hat).
func log_line(name: String, text: String) -> void:
	Logdatei.zeile(Config.path("logs/%s.log" % name), text, 200000)


var _chain_failed := {}    # Adresse -> Zeitpunkt, an dem sie in einer Kette nichts lieferte


## Mehrere Adressen der Reihe nach: das erste Bild, das kommt (z. B. Hülle 2×, Hülle, Kapsel).
## Eine Adresse, die eben erst nichts lieferte, wird ein paar Minuten übersprungen (nicht die
## letzte): Der Shop baut seine Reihen oft neu auf und fragte sonst jedes Mal dieselben Fehlgriffe.
func url_texture_chain(urls: Array, max_w: int, cb: Callable, i := 0) -> void:
	_chain(urls, func(u: String, c: Callable) -> void: url_texture(u, max_w, c), guard(cb) if i == 0 else cb, i)


## Wie url_texture_chain, aber für eine feste Fläche (url_fit).
func url_fit_chain(urls: Array, area: Vector2, cb: Callable, dringend := false) -> void:
	_chain(urls, func(u: String, c: Callable) -> void: url_fit(u, area, c, dringend), guard(cb), 0)


func _chain(urls: Array, lade: Callable, cb: Callable, i: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	while i < urls.size() - 1 and now - int(_chain_failed.get(str(urls[i]), -600)) < 300:
		i += 1
	if i >= urls.size():
		if cb.is_valid():
			cb.call(null)
		return
	var url := str(urls[i])
	lade.call(url, func(t: Texture2D) -> void:
		if t:
			_chain_failed.erase(url)
			if cb.is_valid():
				cb.call(t)
		else:
			if url.begins_with("http"):
				_chain_failed[url] = int(Time.get_unix_time_from_system())
				Config.cap(_chain_failed, 2000)
			_chain(urls, lade, cb, i + 1)
	)


## Datei im Bild-Zwischenspeicher zu einer Adresse aus dem Netz (ob es sie schon gibt oder nicht).
func url_path(url: String) -> String:
	var ext := url.get_extension().get_slice("?", 0).to_lower()
	if not ext in EXTS:
		ext = "jpg"
	return Config.path("cache/img/web/%s.%s" % [url.md5_text(), ext])


## Bild aus dem Netz für eine feste Fläche (wie fit_texture: nur der sichtbare Ausschnitt, ohne
## Mipmaps, im Hintergrund-Thread zugeschnitten) – das große Bild der Medien-Bühne. dringend: das
## gewählte Bild; es wartet nicht, während der Hintergrund überblendet (hold_uploads).
func url_fit(url: String, area: Vector2, cb: Callable, dringend := false) -> void:
	cb = guard(cb)
	var path := url
	if url.begins_with("http"):
		path = url_path(url)
		if not FileAccess.file_exists(path):
			var got := await Net.download(url, path)
			if got == "":
				if cb.is_valid():
					cb.call(null)
				return
	elif url == "" or not (Sicher.local_path_ok(url) and FileAccess.file_exists(url)):
		if cb.is_valid():
			cb.call(null)
		return
	if dringend:
		urgent_fit(path, area)
	if cb.is_valid():
		fit_texture(path, area, cb)


## Schon fertiges Bild zu url_fit, sonst null – lädt nichts (beim Blättern: steht es sofort da?).
func cached_url_fit(url: String, area: Vector2) -> Texture2D:
	if url == "":
		return null
	return cached_fit(url_path(url) if url.begins_with("http") else url, area)


## Bild aus dem Internet (Avatare, Erfolgs-Symbole, Shop-Bilder), mit Datei-Cache.
func url_texture(url: String, max_w: int, cb: Callable) -> void:
	cb = guard(cb)
	if url == "":
		if cb.is_valid():
			cb.call(null)
		return
	if not url.begins_with("http"):
		# Eine Datei auf diesem PC – nie eine Freigabe im Netz (die Adresse kann aus einem Addon stammen).
		if Sicher.local_path_ok(url) and FileAccess.file_exists(url):
			file_texture(url, max_w, cb)
		elif cb.is_valid():
			cb.call(null)
		return
	var dest := url_path(url)
	if not FileAccess.file_exists(dest):
		var got := await Net.download(url, dest)
		if got == "":
			if cb.is_valid():
				cb.call(null)
			return
	if cb.is_valid():
		file_texture(dest, max_w, cb)


# --- Weichgezeichnet, ohne Rücklesen -----------------------------------------------------------
# Für Lichtschein-Hintergründe reicht ein winziges Bild (etwa 2 × steps Punkte breit), das der
# BLUR-Shader glättet. Gerechnet wird es im Hintergrund-Thread aus der Bilddatei; früher wurde
# dafür der Hero in voller Größe hochgeladen, von der Grafikkarte zurückgelesen und auf dem
# Hauptthread klein gerechnet (pro Blätterschritt gut 30 ms).

var _soft_tex := {}         # Pfad@steps -> kleine Textur
var _soft_order: Array = []
var _soft_pending := {}     # Pfad@steps -> Array[Callable]
const SOFT_KEEP := 64


## Weichgezeichnete Fassung des Bildes eines Spiels: cb(Texture2D oder null).
func game_soft(game: Dictionary, kind: String, steps: int, cb: Callable) -> void:
	cb = guard(cb)
	game_file(game, kind, func(path: String) -> void:
		if path != "":
			soft_file(path, steps, cb)
		elif cb.is_valid():
			cb.call(null)
	)


## Weichgezeichnete Fassung einer Textur. Aus file_texture/url_texture kennt sie ihre Datei; ohne
## Datei (selbst erzeugte Bilder) wird wie früher sofort gerechnet.
func soft(t: Texture2D, steps: int, cb: Callable) -> void:
	cb = guard(cb)
	if t == null:
		if cb.is_valid():
			cb.call(null)
		return
	var src := str(t.get_meta("uz_src", ""))
	if src != "":
		soft_file(src, steps, cb)
		return
	var img := soft_image(t.get_image(), steps)
	if cb.is_valid():
		cb.call(ImageTexture.create_from_image(img) if img else t)


## Weiche Fassung schon da (sofort zeigen, nicht erst warten)?
func has_soft(path: String, steps: int) -> bool:
	return path != "" and _soft_tex.has("%s@%d" % [path, steps])


func soft_file(path: String, steps: int, cb: Callable) -> void:
	cb = guard(cb)
	var key := "%s@%d" % [path, steps]
	if _soft_tex.has(key):
		if cb.is_valid():
			cb.call(_soft_tex[key])
		return
	if _soft_pending.has(key):
		_soft_pending[key].append(cb)
		return
	_soft_pending[key] = [cb]
	Arbeit.los(_soft_decode.bind(path, steps, key))


func _soft_decode(path: String, steps: int, key: String) -> void:
	var img := load_image(path)
	call_deferred("_soft_done", key, soft_image(img, steps) if img else null)


func _soft_done(key: String, img: Image) -> void:
	var tex: Texture2D = ImageTexture.create_from_image(img) if img and not img.is_empty() else null
	if tex:
		_soft_tex[key] = tex
		_soft_order.append(key)
		if _soft_order.size() > SOFT_KEEP:
			_soft_tex.erase(_soft_order.pop_front())
	var cbs: Array = _soft_pending.get(key, [])
	_soft_pending.erase(key)
	for cb in cbs:
		if (cb as Callable).is_valid():
			cb.call(tex)


# --- Zuschnitt und Farbe je Bild (Zuschnitt.gd) -------------------------------------------------
# Einmal je Datei gerechnet (im Hintergrund-Thread beim Dekodieren) und gemerkt, auch über einen
# Neustart: cache/bildlook.json, je Pfad [Änderungszeit, Spalten-Profil, Zeilen-Profil (je 16 Byte
# als Hex), Helligkeit in Tausendsteln, Akzentfarbe oder ""]. Eine geänderte Datei wird neu
# gerechnet. Bei 3000 Spielen kommen Spielfarben so ohne ein einziges geladenes Cover.

const LOOKS_FILE := "cache/bildlook.json"
const LOOKS_KEEP := 6000            ## höchstens so viele Bilder merken (älteste fliegen raus)
const LOOKS_FILE_MAX := 4 * 1024 * 1024
var _looks := {}                    # Pfad -> [Änderungszeit, x-Hex, y-Hex, Helligkeit ‰, Farbe]
var _looks_mx := Mutex.new()        # Hintergrund-Threads lesen und schreiben mit
var _looks_due := false


## Analyse für ein schon geladenes Bild: aus dem Zwischenspeicher, sonst jetzt gerechnet und
## gemerkt. Läuft im Hintergrund-Thread. { x, y, l, c } (siehe Zuschnitt.analyze).
func look_for(path: String, img: Image) -> Dictionary:
	var known := look_cached(path)
	if known.has("x"):
		return known
	var look := look_of(img)
	if path != "" and look.has("x"):
		var m := FileAccess.get_modified_time(path)
		_looks_mx.lock()
		_looks[path] = look_encode(look, m)
		Config.cap(_looks, LOOKS_KEEP)
		_looks_mx.unlock()
		call_deferred("_save_looks")
	return look


## Gemerkte Analyse zu einer Datei (nur, wenn die Datei seitdem nicht geändert wurde), sonst {}.
func look_cached(path: String) -> Dictionary:
	if path == "":
		return {}
	_looks_mx.lock()
	var e: Variant = _looks.get(path)
	_looks_mx.unlock()
	if not (e is Array) or int(e[0]) != FileAccess.get_modified_time(path):
		return {}
	return look_decode(e)


## Gemerktes beim Start laden (Hintergrund-Thread). Gelesen wird ohne Sperre; nur das Einfügen
## sperrt – was schon frisch gerechnet wurde, bleibt.
func _load_looks() -> void:
	var p := Config.path(LOOKS_FILE)
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() > LOOKS_FILE_MAX:
		return
	var data: Variant = Fremd.json_roh(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	var good := {}
	for k in data:
		if k is String and not look_decode(data[k]).is_empty():
			good[k] = data[k]
			if good.size() >= LOOKS_KEEP:
				break
	_looks_mx.lock()
	for k in good:
		if not _looks.has(k):
			_looks[k] = good[k]
	_looks_mx.unlock()


## Gebündelt speichern (wie die Steam-Angaben): höchstens alle paar Sekunden.
func _save_looks() -> void:
	if _looks_due or not is_inside_tree():
		return
	_looks_due = true
	get_tree().create_timer(5.0).timeout.connect(save_looks_now)


func save_looks_now() -> void:
	if not _looks_due:
		return
	_looks_due = false
	_looks_mx.lock()
	var copy := _looks.duplicate()
	_looks_mx.unlock()
	Config.write_json(Config.path(LOOKS_FILE), copy)


# --- Spielfarbe ------------------------------------------------------------------------------

var _tints := {}          # Spiel-ID -> Color (oder null, wenn das Cover keine hergibt)


## Akzentfarbe aus dem Cover eines Spiels (kräftigste Farbe, Zuschnitt.accent): cb(Color oder null).
func game_tint(game: Dictionary, cb: Callable) -> void:
	cb = guard(cb)
	var id := str(game.get("id", ""))
	if id != "" and _tints.has(id):
		cb.call(_tints[id])
		return
	var done := func(c: Variant) -> void:
		# Ohne ID nicht merken: sonst bekämen alle solchen Spiele dieselbe Farbe.
		if id != "":
			_tints[id] = c
			Config.cap(_tints, 3000)
		if cb.is_valid():
			cb.call(c)
	# Schon einmal ausgewertet (auch in einer früheren Sitzung): ohne das Cover zu laden.
	game_file(game, "cover", func(path: String) -> void:
		var look := look_cached(path)
		if look.has("x"):
			done.call(look.get("c"))
		else:
			game_texture(game, "cover", func(t: Texture2D) -> void: done.call(color_of(t)))
	)


func forget(game: Dictionary) -> void:
	# Auch die gemerkten Verzeichnisse des Medienordners: Ein eben dort abgelegtes Bild zählt sofort.
	_ordner.clear()
	_fehlt_merk.clear()
	for kind in ["cover", "hero", "logo", "wide", "shot", "icon", "cover_scan", "cover_hoch", "cover_quadrat", "cover_quer", "ruecken"]:
		_missing.erase("%s:%s" % [game.get("id", ""), kind])
		_local.erase("%s:%s" % [game.get("id", ""), kind])
	for folder in ["Named_Boxarts", "Named_Snaps", "Named_Titles", "Named_Logos"]:
		_missing.erase("%s:lr:%s" % [game.get("id", ""), folder])
	_missing.erase("%s:presence" % str(game.get("id", "")))
	_shots.erase(str(game.get("id", "")))


# --- Grundfarbe je Bild (Platzhalter in der Farbe des Bildes) -------------------------------------
# Die mittlere Farbe jedes dekodierten Bilds wird gemerkt (Hintergrund-Thread, beim Dekodieren mit),
# auch über einen Neustart: cache/grundfarbe.json, je Pfad "rrggbb". Beim nächsten Öffnen zeigt
# der Platzhalter sofort diese Fläche (Skeleton.fill(rad, farbe)), und das Bild „entwickelt“ sich
# nur noch darüber. Die Datei ist fremd lesbar: Länge, Schlüssel und Werte werden geprüft.

const GRUND_FILE := "cache/grundfarbe.json"
const GRUND_KEEP := 6000
const GRUND_FILE_MAX := 512 * 1024
var _grund := {}                    # Pfad -> "rrggbb"
var _grund_mx := Mutex.new()
var _grund_due := false


## Gemerkte Grundfarbe zu einer Bilddatei (Color), sonst null.
func grundfarbe(path: String) -> Variant:
	if path == "":
		return null
	_grund_mx.lock()
	var v: Variant = _grund.get(path)
	_grund_mx.unlock()
	return grund_pruefen(path, v)


## Eintrag prüfen: Schlüssel ein Pfad (Text, höchstens 1024 Zeichen), Wert sechs Hex-Ziffern.
## Liefert die Farbe oder null.
static func grund_pruefen(k: Variant, v: Variant) -> Variant:
	if not (k is String) or (k as String).is_empty() or (k as String).length() > 1024:
		return null
	if not (v is String) or (v as String).length() != 6 or not (v as String).is_valid_hex_number():
		return null
	return Color.html(v as String)


## Mittlere Farbe eines Bilds (über das verkleinerte Bild gemittelt, durchsichtige Punkte zählen
## nicht); null, wenn das Bild leer ist.
static func mittelfarbe(img: Image) -> Variant:
	var small := Zuschnitt.small_of(img, 16)
	if small == null or small.is_empty():
		return null
	var d := small.get_data()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0.0
	for i in range(0, d.size() - 3, 4):
		var a := d[i + 3] / 255.0
		r += d[i] * a
		g += d[i + 1] * a
		b += d[i + 2] * a
		n += a
	if n < 0.5:
		return null
	return Color(r / n / 255.0, g / n / 255.0, b / n / 255.0)


## Im Dekodier-Thread: Grundfarbe rechnen und merken (nur, wenn sie noch fehlt).
func _grund_merken(path: String, img: Image) -> void:
	if path == "" or grundfarbe(path) != null:
		return
	var c: Variant = mittelfarbe(img)
	if not (c is Color):
		return
	_grund_mx.lock()
	_grund[path] = (c as Color).to_html(false)
	Config.cap(_grund, GRUND_KEEP)
	_grund_mx.unlock()
	call_deferred("_save_grund")


func _load_grund() -> void:
	var f := FileAccess.open(Config.path(GRUND_FILE), FileAccess.READ)
	if f == null or f.get_length() > GRUND_FILE_MAX:
		return
	var data: Variant = Fremd.json_roh(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	var good := {}
	for k in data:
		if grund_pruefen(k, data[k]) != null:
			good[k] = data[k]
			if good.size() >= GRUND_KEEP:
				break
	_grund_mx.lock()
	for k in good:
		if not _grund.has(k):
			_grund[k] = good[k]
	_grund_mx.unlock()


func _save_grund() -> void:
	if _grund_due or not is_inside_tree():
		return
	_grund_due = true
	get_tree().create_timer(5.0).timeout.connect(save_grund_now)


func save_grund_now() -> void:
	if not _grund_due:
		return
	_grund_due = false
	_grund_mx.lock()
	var copy := _grund.duplicate()
	_grund_mx.unlock()
	Config.write_json(Config.path(GRUND_FILE), copy)

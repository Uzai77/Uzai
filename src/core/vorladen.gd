extends Node
## Gezieltes Vorladen (Punkt 93 „Nie warten“): was die Auswahl als Nächstes wahrscheinlich
## braucht, liegt schon bereit, wenn man es öffnet. Wer nur durchblättert, löst nichts aus – erst
## wenn die Auswahl einen Moment ruht (DWELL_MS), und dann nur für das, worauf sie ruht:
##   Spiel (Cover irgendwo): was die Spielseite braucht – Schriftzug, großes Bild in Schirmgröße,
##     bei Steam-Spielen die Angaben aus dem Store, bei Emulator-Spielen Wikipedia, Bilder aus
##     dem Spiel (Liste) und Erfolge.
##   Shop-Karte: die Angaben des Spiels aus dem Store, sein großes Bild und sein Schriftzug
##     (dieselben Adressen und Größen wie store_game.gd; im leichten Modus nur die Angaben).
##   Bereiche: ruht die Auswahl länger (REST_MS), baut main die beiden Nachbarn (LT/RT)
##     unsichtbar vor, wenn sie sich seit dem letzten Aufbau geändert haben (main._prebuild_rest).
## Raster mit Seiten (Filme, Alle anzeigen) holen die nächste Seite früher (rows_ahead).
##
## Budget: höchstens MAX_JOBS Aufträge je Ruhepunkt und RUNNING gleichzeitig; eine neue Auswahl
## bricht alles ab, was noch nicht läuft. Nie während eines Spiels (auch nicht beim Starten), nie
## mit offenem Guide über einem Spiel, nie im Ruhemodus. Leichter Modus: weniger und später.
## Alles bleibt in Uzais eigenen Zwischenspeichern (Media, Store) – geladen wird nur, was die
## Seiten ohnehin laden würden, nur früher. Nichts Neues verlässt den PC.

const Leicht := preload("res://src/core/leicht.gd")
const BG := preload("res://src/ui/components/background.gd")
const ShopCard := preload("res://src/ui/components/shop_card.gd")

const DWELL_MS := 650          ## so lange muss die Auswahl ruhen, bevor etwas geladen wird
const DWELL_LIGHT_MS := 1100
const REST_MS := 1800          ## Bereiche nebenan erst nach längerer Ruhe vorbauen
const MAX_JOBS := 6            ## Aufträge je Ruhepunkt
const MAX_JOBS_LIGHT := 3
const RUNNING := 2             ## gleichzeitig unterwegs
const ROWS_AHEAD := 4          ## Raster: nächste Seite holen, wenn die Auswahl so viele Reihen vor dem Ende ist
const ROWS_AHEAD_LIGHT := 2

const Main := preload("res://src/main.gd")
var main: Main
var stats := { "ruhe": 0, "auftraege": 0, "abgebrochen": 0 }   ## für Proben und die Leistungsseite

var _gen := 0
var _queue: Array = []         ## [Schlüssel, Callable]
var _running := 0
var _done := {}                ## Schlüssel -> true (in dieser Sitzung schon vorgeladen)


func _ready() -> void:
	Nav.focus_moved.connect(_on_focus)
	Launcher.started.connect(func(_g: Dictionary) -> void: cancel())


# --- Regeln (ohne Fenster, getestet in tests/logic_vorladen.gd) ----------------------------------

## Darf jetzt vorgeladen werden?
static func allowed(in_game: bool, launching: bool, resting: bool) -> bool:
	return not in_game and not launching and not resting


static func dwell_ms(light: bool) -> int:
	return DWELL_LIGHT_MS if light else DWELL_MS


static func max_jobs(light: bool) -> int:
	return MAX_JOBS_LIGHT if light else MAX_JOBS


static func rows_ahead(light: bool) -> int:
	return ROWS_AHEAD_LIGHT if light else ROWS_AHEAD


## Raster mit Seiten: ab welcher Karte (Index) die nächste Seite geholt wird.
static func page_from(count: int, columns: int, light: bool) -> int:
	return maxi(0, count - columns * rows_ahead(light))


## Was zu einem Spiel vorgeladen wird (Arten von Aufträgen, in dieser Reihenfolge). Steam-Spiele
## holen Store-Angaben, Emulator-Spiele Wikipedia (nur mit library.web_info).
static func game_jobs(g: Dictionary, light: bool, web_info := true) -> Array:
	var out: Array = ["logo", "hero"]
	var src := str(g.get("source", ""))
	if src == "steam" and int(g.get("appid", 0)) > 0:
		out.append("store")
	elif src == "rom" and web_info:
		out.append("wiki")
	if not light:
		out.append("shots")
		out.append("ach")
	return out


# --- Ablauf -------------------------------------------------------------------------------------

## Alles abbrechen, was noch nicht läuft (neue Auswahl, Spielstart).
func cancel() -> void:
	_gen += 1
	stats.abgebrochen = int(stats.abgebrochen) + _queue.size()
	_queue.clear()


func _ok() -> bool:
	var launching := bool(main._launching) if main else false
	var resting := false
	if main and main.rest != null:
		resting = bool(main.rest.get("active"))
	return allowed(Launcher.in_game, launching, resting) and is_inside_tree()


func _on_focus(c: Control) -> void:
	cancel()
	if c == null or not is_instance_valid(c) or not _ok():
		return
	var gen := _gen
	await get_tree().create_timer(dwell_ms(Leicht.active) / 1000.0).timeout
	if gen != _gen or not is_instance_valid(c) or not c.has_focus() or not _ok():
		return
	stats.ruhe = int(stats.ruhe) + 1
	var g: Variant = c.get("game")
	if g is Dictionary and not (g as Dictionary).is_empty() and str((g as Dictionary).get("id", "")) != "":
		_for_game(g)
	else:
		var it: Variant = c.get("item")
		if it is Dictionary and int((it as Dictionary).get("appid", 0)) > 0 and c.get_script() == ShopCard:
			_for_shop(it)
	_pump(gen)
	# Länger Ruhe: Bereiche nebenan vorbauen (main entscheidet, ob es nötig ist).
	await get_tree().create_timer(maxf(0.0, (REST_MS - dwell_ms(Leicht.active)) / 1000.0)).timeout
	if gen == _gen and _ok() and main:
		main.prebuild_neighbors()


func _add(key: String, job: Callable) -> void:
	if _done.has(key) or _queue.size() >= max_jobs(Leicht.active):
		return
	_queue.append([key, job])


func _pump(gen: int) -> void:
	while gen == _gen and _running < RUNNING and not _queue.is_empty():
		var it: Array = _queue.pop_front()
		_done[str(it[0])] = true
		Config.cap(_done, 2000)
		_run(it[1])


func _run(job: Callable) -> void:
	_running += 1
	stats.auftraege = int(stats.auftraege) + 1
	await job.call()
	_running -= 1
	_pump(_gen)


## Spielseite: dieselben Aufrufe mit denselben Größen wie game_page.gd, damit sie dort sofort
## aus dem Zwischenspeicher kommen.
func _for_game(g: Dictionary) -> void:
	if main and not main.game_page_on():
		return
	var gid := str(g.get("id", ""))
	for kind in game_jobs(g, Leicht.active, bool(Config.get_value("library.web_info", true))):
		match kind:
			"logo":
				_add("logo:" + gid, func() -> void:
					await _texture(g, "logo"))
			"hero":
				_add("hero:" + gid, func() -> void:
					await _hero(g))
			"store":
				_add("store:" + gid, func() -> void:
					await Store.details(int(g.appid)))
			"wiki":
				_add("wiki:" + gid, func() -> void:
					await Media.wiki(g))
			"shots":
				_add("shots:" + gid, func() -> void:
					await Media.screenshots(g))
			"ach":
				if Achievements.cached(g).is_empty() \
						and ((g.get("source") == "steam" and Achievements.has_steam()) or (g.get("source") == "rom" and Achievements.has_ra())):
					_add("ach:" + gid, func() -> void:
						await Achievements.for_game(g))


## Shop-Karte: Angaben (Store merkt sich die Antwort), großes Bild und Schriftzug.
func _for_shop(it: Dictionary) -> void:
	var appid := int(it.get("appid", 0))
	_add("sdet:%d" % appid, func() -> void:
		await Store.details(appid))
	if Leicht.active:
		return
	_add("sart:%d" % appid, func() -> void:
		var box := { "a": null }
		Media.with_steam_assets(appid, func(a: Dictionary) -> void: box.a = a)
		if not await _until(func() -> bool: return box.a != null):
			return
		var aa: Dictionary = box.a if not (box.a as Dictionary).is_empty() else Store.art_assets(it)
		var urls: Array = Store.hero_urls(appid, aa, int(1920 * Media.px_scale()))
		var got := { "n": 0 }
		if not urls.is_empty():
			Media.url_texture(str(urls[0]), 1920, func(_t: Variant) -> void: got.n += 1)
		else:
			got.n += 1
		Media.url_texture_chain(Store.logo_urls(appid, aa), 1000, func(_t: Variant) -> void: got.n += 1)
		await _until(func() -> bool: return int(got.n) >= 2))


## Warten, bis cond() stimmt (höchstens 8 s). false: kam nicht.
func _until(cond: Callable) -> bool:
	var until := Time.get_ticks_msec() + 8000
	while not cond.call():
		if Time.get_ticks_msec() > until or not is_inside_tree():
			return false
		await get_tree().process_frame
	return true


## Bild eines Spiels laden und warten, bis es da ist (oder nicht kommt).
func _texture(g: Dictionary, kind: String) -> void:
	var box := { "done": false }
	Media.game_texture(g, kind, func(_t: Variant) -> void: box.done = true)
	await _until(func() -> bool: return box.done)


## Großes Bild der Spielseite: nur, was schon auf der Platte liegt (wie games.gd), in Schirmgröße.
func _hero(g: Dictionary) -> void:
	var hp := Media.local_path(g, "hero")
	if hp == "" or not is_inside_tree():
		return
	var area := BG.page_hero_area(get_viewport().get_visible_rect().size)
	if Media.has_fit(hp, area):
		return
	var box := { "done": false }
	Media.fit_texture(hp, area, func(_t: Variant) -> void: box.done = true)
	await _until(func() -> bool: return box.done)

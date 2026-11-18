extends "res://src/ui/sections/section.gd"
## Eigene App (src/core/apps_extern.gd): Store-App oder Programm, oben in der Leiste mit ihrem
## App-Symbol (A dort startet sie gleich). Steht der Cursor auf dem Symbol, zeigt dieser Bereich eine
## Kachel wie beim Zimmer – Name, Art, ihr Logo; A startet sie bzw. holt sie zurück nach vorn, wenn
## sie nach „Zurück zu Uzai“ im Hintergrund weiterläuft. Darunter steht, was in ihr läuft – nur, was
## Windows offiziell über ihre Mediensitzung meldet (Helfer „app-media“), nie etwas aus dem Dienst.

const MediaTile := preload("res://src/ui/components/media_tile.gd")
const AppsExtern := preload("res://src/core/apps_extern.gd")

const MEDIA_S := 5.0            ## so oft fragt der Bereich die Mediensitzung ab, solange er zu sehen ist

var entry: Dictionary = {}
var _tile: Control
var _kept := false
var _media := {}                ## letzte Mediensitzung { title, artist, playing }
var _media_t: Timer
var _media_busy := false


func _init() -> void:
	super()
	icon_name = "tv"


func setup(e: Dictionary) -> Control:
	entry = e
	id = str(e.get("id", ""))
	title = str(e.get("name", ""))
	icon_name = "desktop" if str(e.get("kind", "")) == "prog" else "tv"
	return self


func build() -> void:
	mark_built()
	U.clear(self)
	var col := U.vbox(18)
	var sc := scroll_v(col)
	U.full_rect(sc)
	add_child(sc)
	col.add_child(U.spacer(0, 18, false))
	var shelf = Shelf.new().setup("app:" + id + ":tiles", 28, true, 26, GUTTER, 30)
	col.add_child(shelf)
	var prog := str(entry.get("kind", "")) == "prog"
	var t = MediaTile.new().setup(id, title, icon_name, hue_of(title), "Programm" if prog else "Store-App")
	t.logo_path = AppsExtern.logo_path(id)
	t.set_meta("uz_key", "app:%s:start" % id)
	t.set_meta("uz_default", true)
	t.set_meta("uz_entry", true)
	t.chosen.connect(func(_k: String) -> void: main.start_app(id))
	# Y (Menü-Taste, Rechtsklick): Optionen der App, darunter Entfernen.
	var menu := func() -> void: main.app_menu(id, title)
	t.set_meta("uz_on_y", menu)
	t.set_meta("uz_on_menu", menu)
	t.set_meta("uz_hint_y", "Optionen")
	shelf.add(t)
	_tile = t
	_paint(Launcher.kept.has(id))


func on_enter() -> void:
	_check_kept()
	_media_start()


func reenter() -> void:
	_check_kept()
	_media_start()


## Läuft sie noch im Hintergrund? (Nach außen geschlossen: die Kachel sagt wieder „Starten“.)
func _check_kept() -> void:
	if not Launcher.kept.has(id):
		_paint(false)
		return
	var on: bool = await Launcher.app_kept(id)
	_paint(on)


func _paint(kept: bool) -> void:
	_kept = kept
	if not is_instance_valid(_tile):
		return
	_tile.set_meta("uz_hint_a", "Zurück zur App" if kept else "Starten")
	var line := status_line(_media, kept)
	_tile.call("set_status", line, kept or bool(_media.get("playing", false)))
	if Nav.focused() == _tile:
		Nav.focus_moved.emit(_tile)


## Ruhiger Farbton je App, aus dem Namen (immer derselbe).
static func hue_of(name: String) -> float:
	return float(absi(name.to_lower().hash()) % 1000) / 1000.0


## Was auf der Kachel steht: was in der App läuft (Mediensitzung), sonst ob sie im Hintergrund läuft.
static func status_line(media: Dictionary, kept: bool) -> String:
	var t := str(media.get("title", ""))
	if t != "":
		var a := str(media.get("artist", ""))
		var head := TranslationServer.translate("Läuft gerade" if bool(media.get("playing", false)) else "Pausiert")
		return "%s: %s" % [head, ("%s – %s" % [t, a]) if a != "" else t]
	return TranslationServer.translate("Läuft im Hintergrund") if kept else ""


func _media_start() -> void:
	if not Config.is_windows() or not Helper.available:
		return
	if _media_t == null:
		_media_t = Timer.new()
		_media_t.wait_time = MEDIA_S
		_media_t.timeout.connect(_poll_media)
		add_child(_media_t)
	_media_t.start()
	_poll_media()


## Läufe von _poll_media, die gerade unterwegs sind (siehe dort).
var _poll_media_offen := 0


## Mediensitzung der App (nur Windows, nur solange der Bereich zu sehen ist).
func _poll_media() -> void:
	_poll_media_offen += 1
	await _poll_media_lauf()
	_poll_media_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und _poll_media täte bis zum Neustart nichts mehr.
	if _poll_media_offen == 0 and _media_busy:
		_media_busy = false


func _poll_media_lauf() -> void:
	if not is_visible_in_tree():
		if _media_t:
			_media_t.stop()
		return
	if _media_busy:
		return
	var mid := AppsExtern.media_id(entry)
	if not AppsExtern.valid_media_id(mid):
		return
	_media_busy = true
	var r := await Helper.run("app-media", { "id": mid }, 5.0)
	_media_busy = false
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	var m := {}
	if bool(res.get("active", false)):
		m = { "title": AppsExtern.clean_name(res.get("title", "")), "artist": AppsExtern.clean_name(res.get("artist", "")),
			"playing": bool(res.get("playing", false)) }
	if JSON.stringify(m) != JSON.stringify(_media) and is_instance_valid(self):
		_media = m
		_paint(_kept)

extends "res://src/ui/sections/medien_bereich.gd"
## Filme & Serien – aufgebaut wie Nuvio TV, in Uzais Gestaltung.
##
## Start: die Bühne (medien_buehne.gd) zeigt den Titel, auf dem man steht – Hintergrundbild oben
## rechts im Raum, unten links Schriftzug, Angaben, zwei Zeilen Beschreibung und die Tasten als
## Pillen –, darunter die Reihen (medien_reihen.gd): Weiterschauen zuerst, dann die Katalog-Reihen
## der Addons. Die Reihen rasten unter der Bühne ein; steht niemand auf einer Karte, wechselt die
## Bühne von selbst durch die Titelbilder (wie in Nuvio).
## Bibliothek und Suche (Bildschirmtastatur oder Handy). Addons und Plugins haben keinen eigenen
## Reiter: sie öffnen sich als Seite darüber (Einstellungen → Filme, Bibliothek, leere Startseite;
## main.goto("movies", "addons"/"plugins") geht weiter). Die früheren Reiter Filme und Serien
## führen auf Start – ganze Kataloge gibt es über „Alle anzeigen“ an jeder Reihe.
## Alles kommt über den Autoload Movies (src/core/movies.gd, Daten in movies_daten.gd).

const MovieCard := preload("res://src/ui/components/movie_card.gd")
const MedienBuehne := preload("res://src/ui/components/medien_buehne.gd")
const MedienReihen := preload("res://src/ui/components/medien_reihen.gd")
const PosterGrid := preload("res://src/ui/components/poster_grid.gd")
const Manage := preload("res://src/ui/components/movie_manage.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const FolderTile := preload("res://src/ui/components/nuvio_folder_tile.gd")
const MovieAddons := preload("res://src/ui/layers/movie_addons.gd")
const MovieCatalog := preload("res://src/ui/layers/movie_catalog.gd")
const Ladezeit := preload("res://src/core/ladezeit.gd")
const Zustand := preload("res://src/core/zustand.gd")

const HERO_EVERY := 8.0
## Reihen der Startseite: noch nie geholt, laden, da; eine neue Quelle setzt zurück.
const ZUSTAENDE_START := { "": ["laden"], "laden": ["da"], "da": ["laden", ""] }

var _buehne = null                 ## medien_buehne.gd
var _hero_list: Array = []
var _hero_i := 0
var _hero_timer: Timer
var _on_card := false
var _sig := ""
var _home: Array = []              ## Reihen der Startseite (Movies.home_rows() muss warten)
var _home_state := "":             ## "" noch nie, "laden", "da"
	set(neu):
		Zustand.wechsel("filme.start", ZUSTAENDE_START, _home_state, neu)
		_home_state = neu
var _home_again := false           ## home_ready kam während des Ladens: danach noch einmal holen
var _stale := false
var _building := false             ## build() läuft gerade (darf nicht in sich selbst neu bauen)
var _grid = null
var _lib_filter := ""
var _query := ""
var _results: Array = []
var _searching := false
static var _recent: Array = []


## Für medien_bereich._rebuild_keep: build() darf nicht in sich selbst neu bauen.
func _baut_gerade() -> bool:
	return _building


## Nur die Startseite hat Reihen, die nach dem Neuaufbau einrasten.
func _reihen_einrasten() -> bool:
	return sub == "start"


func _init() -> void:
	super()
	id = "movies"
	title = "Filme"
	icon_name = "film"
	Movies.changed.connect(_on_changed)
	Movies.progress_changed.connect(func(_mid: String) -> void: _on_changed())
	keep_built = true
	stale_keys = PackedStringArray(["movies.", "nuvio.", "accounts.", "plex.", "jellyfin.", "emby.", "stremio."])
	Movies.changed.connect(mark_stale)
	# Reihen kamen nach (langsames Addon) oder wurden im Hintergrund aufgefrischt.
	Movies.home_ready.connect(func() -> void:
		mark_stale()
		if _home_state == "laden":
			_home_again = true
		elif is_inside_tree() and main != null and main.current == id and sub == "start":
			_fetch_home()
	)
	Movies.progress_changed.connect(mark_stale)
	NuvioSync.changed.connect(mark_stale)
	# Profile geladen oder gewechselt (auch aus den Einstellungen): die Profil-Taste hinter den Reitern mitziehen.
	NuvioSync.changed.connect(func() -> void:
		if main != null and main.current == id:
			main.refresh_chips())
	Nav.focus_moved.connect(_on_nav_focus)


const SUBS := ["start", "bibliothek", "suche"]


func subtabs() -> Array:
	return [
		{ "id": "start", "label": TranslationServer.translate("Start", "tab") },
		{ "id": "bibliothek", "label": "Bibliothek", "count": Movies.library_items().size() },
		{ "id": "suche", "label": "Suche" },
	]


## After the tabs: the Nuvio profile, as in the top right of Nuvio TV, so switching profiles does not require a trip
## to the settings. Only with a Nuvio account and more than one profile; A selects.
func chip_aktionen() -> Array:
	if not NuvioSync.connected() or NuvioSync.profiles().size() < 2:
		return []
	return [{ "id": "nuvio_profil", "label": nuvio_profil_name(), "icon": "user", "tun": _nuvio_profil_waehlen }]


static func nuvio_profil_name() -> String:
	var n := NuvioSync.profile_name()
	return n if n != "" else TranslationServer.translate("Profil %d") % NuvioSync.profile_id()


func _nuvio_profil_waehlen() -> void:
	var opts: Array = NuvioSync.profiles().map(func(p: Dictionary) -> Array:
		var i := int(p.get("profile_index", 1))
		var n := str(p.get("name", ""))
		return [i, n if n != "" else TranslationServer.translate("Profil %d") % i])
	main.open_choice("Nuvio-Profil", opts, NuvioSync.profile_id(), func(v: Variant) -> void:
		NuvioSync.set_profile(int(v))
		main.refresh_chips()
	)


## Alte Reiter: Filme und Serien führen auf Start; Addons und Plugins öffnen ihre Seite über dem
## Bereich (main.goto bleibt dann auf dem Unterbereich, der gerade gilt).
func resolve_sub(sub_id: String) -> String:
	match sub_id:
		"filme", "serien":
			return "start"
		"addons", "plugins":
			open_manage.call_deferred(sub_id)
			return ""
	return sub_id


## Addons bzw. Plugins verwalten (Seite über dem Bereich; LB/RB wechselt zwischen beiden).
func open_manage(page := "addons") -> void:
	if main == null:
		return
	var top := Nav.top_layer()
	if top != null and top.get_script() == MovieAddons:
		top.call("show_page", page)
		return
	var l = MovieAddons.new()
	l.page = page
	main.open_layer(l)


func on_enter() -> void:
	NuvioSync.sync()
	# Addons (mit Nuvio) sind der Standard; eigene Medienserver wählt man unter Filme-Quellen.
	if Quellen.needs_choice():
		Quellen.mark_chosen()
	if sub == "start" and _buehne != null and is_instance_valid(_buehne):
		_buehne.wieder()
	_fetch_home()


## Beim Start (main._prebuild): die Reihen der Startseite holen, ohne aufzubauen (_fetch_home baut
## nur, solange Filme der gewählte Bereich ist).
func prefetch() -> void:
	if _home_state == "":
		_fetch_home()


func data_ready() -> bool:
	return _home_state == "da"


## Ansicht weg (Neuaufbau der Oberfläche; beim Wechsel des Bereichs bleibt sie): ihr Stand aus Zustand.lage().
func _exit_tree() -> void:
	Zustand.vergessen("filme.start")


## Bereich neu betreten (LT/RT): ganz nach oben – erste Reihe (Weiterschauen) direkt unter dem
## Kopf, alle Reihen wieder am Anfang, der Kopf wechselt wieder von selbst. Ohne Neuaufbau blieb
## die Seite sonst an der alten Reihe stehen (die Reihen darüber waren für die Steuerung aus, der
## Fokus landete in der alten Reihe). B aus einer Ebene (Detailseite) berührt das nicht.
func reset_position() -> void:
	super()
	_on_card = false
	_hero_i = 0
	if _reihen != null and is_instance_valid(_reihen):
		_reihen.reset()


## Steht die Seite nicht mehr oben (tiefere Reihe gewählt)? B zu den Unterreitern setzt sie dann zurück.
func scrolled() -> bool:
	return _reihen != null and is_instance_valid(_reihen) and _reihen.scrolled()


## Reihen holen (Movies hält sie zwischengespeichert) und die Startseite neu bauen, wenn sich
## etwas geändert hat. Beim allerersten Mal steht so lange „Kataloge werden geladen …“ da.
func _fetch_home() -> void:
	if _home_state == "laden":
		return
	_home_state = "laden"
	_home_again = false
	var got: Variant = await Movies.home_rows()
	_home = got if got is Array else []
	_home_state = "da"
	# Hat Movies die Reihen schon im Speicher, kommt die Antwort ohne Warten – mitten aus dem
	# Aufbau heraus. Dann nimmt der laufende Aufbau sie selbst; ein Neuaufbau hier legte eine
	# zweite Startseite (zweiter Kopf, zweite Reihen) über die erste: Texte übereinander.
	if _building:
		return
	if _home_again:
		# Während des Ladens kam Neues: gleich noch einmal (meist aus dem Zwischenspeicher).
		_home_again = false
		_fetch_home()
		return
	if not is_inside_tree() or main == null or main.current != id or not (sub in ["start", "suche"]):
		return
	if Nav.top_layer() != null or Video.active:
		_stale = true
		return
	if sub == "start" and _start_sig() != _sig:
		_rebuild_keep()
	elif sub == "suche" and _query == "" and not _searching:
		_rebuild_keep()
	Ladezeit.pruefen(self)


## Für die Ladezeit (src/core/ladezeit.gd): steht schon Inhalt, ist alles geladen?
func lade_stand() -> Dictionary:
	var laedt: bool = sub == "start" and (_home_state != "da" or Movies.home_busy())
	var inhalt: bool = _reihen != null and is_instance_valid(_reihen) and _reihen.row_count() > 0
	if sub != "start":
		inhalt = get_child_count() > 0
	return { "inhalt": inhalt, "fertig": not laedt, "quelle": "gemerkt" if laedt else "frisch" }


func on_leave() -> void:
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.verlassen()


# --- Änderungen von außen ----------------------------------------------------------------------

func _on_changed() -> void:
	if not visible or not is_inside_tree() or main == null or main.current != id:
		return
	if Nav.top_layer() != null or Video.active:
		# Etwas liegt darüber: danach nachholen (siehe _on_nav_focus).
		_stale = true
		return
	_apply_change()


func _apply_change() -> void:
	match sub:
		"start":
			_refresh_cards()
			_fetch_home()
		"bibliothek":
			_rebuild_keep()
		_:
			_refresh_cards()
	if main:
		main.refresh_chips()


func _on_nav_focus(c: Control) -> void:
	if sub == "start" and _reihen != null and is_instance_valid(_reihen):
		_on_card = c != null and _reihen.is_ancestor_of(c)
	if not _stale or not visible or not is_inside_tree() or Nav.top_layer() != null or Video.active:
		return
	if main == null or main.current != id:
		return
	_stale = false
	_apply_change()


## Hinweise und Haken auf den Karten auf den neuesten Stand bringen (ohne Neuaufbau).
func _refresh_cards() -> void:
	for c in find_children("*", "Control", true, false):
		if c.has_method("set_watched") and c.get("item") is Dictionary:
			var it: Dictionary = c.get("item")
			_card_hints(c as Control, it)
			if str(it.get("type", "")) == "movie" and c.get("mode") != "wide":
				c.call("set_watched", Movies.watched(str(it.get("id", "")), str(it.get("id", ""))))
	Nav.focus_moved.emit(Nav.focused())


func reenter() -> void:
	# Bild und Licht zum gezeigten Titel neu setzen (main.goto hat den Raum geleert).
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.wieder()


func build() -> void:
	if _building:
		return
	_building = true
	# Sicherheitsnetz: bricht ein Aufbau ab, gilt er spätestens am Ende des Bilds als fertig.
	set_deferred("_building", false)
	mark_built()
	if _buehne != null and is_instance_valid(_buehne):
		_buehne.verlassen()
	U.clear(self)
	_buehne = null
	_reihen = null
	_hero_timer = null
	_on_card = false
	_grid = null
	_stale = false
	if not sub in SUBS:
		sub = "start"
	match sub:
		"bibliothek": _build_library()
		"suche": _build_search()
		_: _build_start()
	_building = false


func focus_default() -> void:
	var d := Nav.default_in(self)
	if d:
		Nav.focus(d, true)


# --- Karten -------------------------------------------------------------------------------------

func _card(it: Dictionary, kind: String, row: Dictionary, prefix: String) -> Control:
	var c = MovieCard.new()
	c.setup(it, kind)
	c.key_prefix = prefix
	if kind != "wide" and kind != "more" and str(it.get("type", "")) == "movie":
		c.watched = Movies.watched(str(it.get("id", "")), str(it.get("id", "")))
	if kind == "more":
		c.set_meta("uz_hint_a", "Alle anzeigen")
		c.chosen.connect(func(_v: Dictionary) -> void: main.open_movie_catalog(row))
		return c
	_card_hints(c, it)
	if kind == "wide":
		c.chosen.connect(
				func(v: Dictionary) -> void: main.open_movie_streams(v, str(v.get("video_id", v.get("id", ""))), "start" if bool(v.get("next_up", false)) else "resume"))
		c.set_meta("uz_on_y", func() -> void: _cw_options(it))
	else:
		c.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
		c.set_meta("uz_on_x", func() -> void: _toggle_library(it))
		if bool(row.get("see_all", false)):
			c.set_meta("uz_hint_y", "Alle anzeigen")
			c.set_meta("uz_on_y", func() -> void: main.open_movie_catalog(row))
	return c


func _card_hints(c: Control, it: Dictionary) -> void:
	if str(c.get("mode")) == "wide":
		c.set_meta("uz_hint_a", "Abspielen" if bool(it.get("next_up", false)) else "Weiterschauen")
		c.set_meta("uz_hint_y", "Optionen")
		return
	c.set_meta("uz_hint_a", "Details")
	c.set_meta("uz_hint_x", "Aus der Bibliothek" if Movies.in_library(str(it.get("id", ""))) else "In die Bibliothek")


func _toggle_library(it: Dictionary) -> void:
	var on: bool = Movies.toggle_library(it)
	Toasts.show_toast("In der Bibliothek" if on else "Aus der Bibliothek entfernt", str(it.get("name", "")), "bookmark_f" if on else "bookmark",
			{ "sound": "select", "quiet": true })
	_refresh_cards()


## Weiterschauen, Y: wie im Menü von Nuvio – Details, von vorn, entfernen.
func _cw_options(it: Dictionary) -> void:
	var name_ := str(it.get("name", ""))
	var sub_t := Art.episode_code(int(it.get("season", 0)), int(it.get("episode", 0)), true) if int(it.get("episode", 0)) > 0 else Art.type_label(
			str(it.get("type", "")))
	Manage.open_actions(main, name_, sub_t, [
		["Details", "info", func() -> void: main.open_movie(it)],
		["Von vorn abspielen", "restart", func() -> void: main.open_movie_streams(it, str(it.get("video_id", it.get("id", ""))), "start")],
		["Aus „Weiterschauen“ entfernen", "close", func() -> void:
			Movies.remove_continue(str(it.get("id", "")))
			Toasts.show_toast("Entfernt", name_, "check", { "quiet": true })],
	])


# --- Start -------------------------------------------------------------------------------------

func _start_sig() -> String:
	var parts := PackedStringArray()
	for c in Movies.continue_watching():
		parts.append("%s@%s" % [c.get("id", ""), c.get("video_id", "")])
	parts.append("|")
	for r in _home:
		parts.append(str(r.get("key", "")) + ":" + str((r.get("items", []) as Array).size() + (r.get("folders", []) as Array).size()))
	return ",".join(parts)


func _build_start() -> void:
	# Erstes Mal (auch nach einem Neuaufbau der Oberfläche, etwa beim Wechsel von Farbschema oder
	# Akzent): Reihen holen, bevor sie gelesen werden – liegen sie bei Movies schon bereit, sind
	# sie gleich da und die Seite steht ohne Umweg über „Kataloge werden geladen …“.
	if _home_state == "":
		_fetch_home()
	var rows: Array = _home
	# Nuvio-Konto: „Weiterschauen“ und das wechselnde Titelbild wie in den Einstellungen der Nuvio-App.
	var cw: Array = Movies.continue_watching() if NuvioSync.continue_enabled() else []
	_sig = _start_sig()
	if rows.is_empty() and cw.is_empty():
		_build_home_empty()
		return
	_hero_list = Movies.hero_items()
	_buehne = MedienBuehne.new().setup(self, main)
	add_child(_buehne)
	_reihen = MedienReihen.new().setup(MedienBuehne.H)
	_reihen.instant = _instant
	_reihen.row_focused.connect(_on_row_card)
	add_child(_reihen)
	if not cw.is_empty():
		_add_row({ "key": "cw", "title": "Weiterschauen", "items": cw, "see_all": false }, "wide")
	for r in rows:
		if str(r.get("kind", "")) == "folders":
			if not (r.get("folders", []) as Array).is_empty():
				_add_folder_row(r)
		elif not (r.get("items", []) as Array).is_empty():
			_add_row(r, "poster")
	var fc: Control = _reihen.first_card()
	if fc:
		fc.set_meta("uz_default", true)
	# Die Bühne zeigt zuerst das erste Titelbild (Nuvio: Kataloge fürs Titelbild), sonst die erste Karte.
	var first: Dictionary = _hero_list[0] if not _hero_list.is_empty() else {}
	var fc_item: Dictionary = fc.get("item") if fc and fc.get("item") is Dictionary else {}
	if first.is_empty():
		first = fc_item
	_show_hero(first, 0, fc if not fc_item.is_empty() and str(fc_item.get("id", "")) == str(first.get("id", "")) else null)
	_hero_timer = Timer.new()
	_hero_timer.wait_time = HERO_EVERY
	_hero_timer.autostart = NuvioSync.hero_enabled()
	_hero_timer.timeout.connect(_hero_tick)
	add_child(_hero_timer)


## Eben eine Quelle eingerichtet (leer_buehne.gd): die Reihen neu holen – erst ruhige Platzhalter,
## dann kommen die Kataloge.
func _neu_nach_quelle() -> void:
	if _home_state != "laden":
		_home_state = ""
	build()


func _build_home_empty() -> void:
	if not Quellen.addons_on() and _home_state == "da" and Quellen.active_kinds().is_empty():
		add_child(leer_buehne({ "art": "poster", "symbol": "film", "titel": "Keine Quelle eingeschaltet.",
			"knopf": "Quellen wählen", "tun": func() -> void: main.open_movie_sources(),
			"neben": "Suchen", "neben_tun": func() -> void: main.goto("movies", "suche"),
			"fertig": func() -> bool: return Quellen.addons_on() or not Quellen.active_kinds().is_empty(), "neu": _neu_nach_quelle }))
	elif Movies.addons.is_empty() and _home_state == "da" and not NuvioSync.connected():
		# Noch nichts eingerichtet: die Bühne mit angedeuteten Plakaten; A meldet bei Nuvio an
		# (QR-Code wie die Nuvio-TV-App, deine Addons kommen mit). Danach kommen die Kataloge herein.
		add_child(leer_buehne({ "art": "poster", "symbol": "film", "titel": "Filme und Serien aus deinen Quellen.",
			"zeile": "Oder mit Nuvio-Konto.", "knopf": "Nuvio verbinden", "tun": LeerBuehne.weg(main, "nuvio"),
			"neben": "Andere Quellen", "neben_tun": func() -> void: main.open_movie_sources(),
			"fertig": func() -> bool: return NuvioSync.connected() or not Movies.addons.is_empty(), "neu": _neu_nach_quelle }))
	elif Movies.addons.is_empty() and _home_state == "da":
		var btns: Array = []
		if not NuvioSync.connected():
			btns.append(["Mit Nuvio anmelden", "qr", func() -> void: main.open_nuvio_login()])
		btns.append(["Addon installieren", "plus", func() -> void: Manage.ask_install(main)])
		btns.append(["Eigener Medienserver", "drive", func() -> void: main.open_movie_sources()])
		add_child(empty_state("Noch keine Addons", "Nuvio-Konto verbinden oder Addon installieren.", btns))
	else:
		var loading := _home_state != "da"
		if loading:
			# Platzhalter in der Form der Bühne und der ersten Reihen: wenn die Kataloge kommen, springt nichts.
			add_child(MedienReihen.skeleton(MedienBuehne.H, MovieCard.POSTER, 2, 24))
			return
		add_child(
				empty_state("Gerade keine Kataloge", Movies.error if Movies.error != "" else "Keine Titel. Filme-Quellen prüfen.", [
			["Erneut versuchen", "refresh", func() -> void:
				Movies.retry_home()
				_neu_nach_quelle()],
			["Filme-Quellen", "drive", func() -> void: main.open_movie_sources()],
			["Addons ansehen", "grid", func() -> void: open_manage("addons")],
			["Suchen", "search", func() -> void: main.goto("movies", "suche")],
		], "fehler" if Movies.error != "" else "leer"))


func _add_row(row: Dictionary, kind: String) -> void:
	var idx: int = _reihen.row_count()
	var h: float = MovieCard.WIDE.y if kind == "wide" else MovieCard.POSTER.y
	var r: Dictionary = _reihen.add_row(str(row.get("title", "")), str(row.get("source_label", "")), "m:%d" % idx, h, 24)
	var items: Array = row.get("items", [])
	var prefix := str(row.get("key", idx)) + ":"
	for it in items:
		_reihen.add_card(r, _card(it, kind, row, prefix), it)
	if bool(row.get("see_all", false)):
		var more := _card({ "id": "mehr:" + str(row.get("key", idx)) }, "more", row, prefix)
		_reihen.add_card(r, more, { "id": "mehr:" + str(row.get("key", idx)), "name": str(row.get("title", "")), "hero_line": str(row.get("source_label", "")), "_more": true })


## Nuvio-Sammlung: eine Reihe mit Ordner-Kacheln (wie Nuvio TV); A öffnet den Ordner.
func _add_folder_row(row: Dictionary) -> void:
	var idx: int = _reihen.row_count()
	var folders: Array = row.get("folders", [])
	var r: Dictionary = _reihen.add_row(str(row.get("title", "")), str(row.get("source_label", "")), "m:%d" % idx, FolderTile.row_height(folders), 24)
	for i in folders.size():
		var f: Dictionary = folders[i]
		var t = FolderTile.new().setup(f)
		t.set_meta("uz_key", "%s:%s" % [str(row.get("key", idx)), str(f.get("id", i))])
		t.set_meta("uz_hint_a", "Öffnen")
		t.chosen.connect(func(fo: Dictionary) -> void: main.open_movie_folder(fo, bool(row.get("show_all", true))))
		# Wie in Nuvio TV: Bühne und Hintergrund zeigen den Ordner (Name, Sammlung, sein Bild).
		_reihen.add_card(r, t, MovieCatalog.folder_item(f, _first_backdrop(f)))


## Ersatzbild für einen Ordner ohne eigenes: das Hintergrundbild des ersten Titels aus seinen
## Katalogen, sofern eine Reihe der Startseite ihn schon geladen hat (lädt nichts nach).
func _first_backdrop(f: Dictionary) -> String:
	if str(f.get("backdrop", "")) != "":
		return ""
	for s in f.get("sources", []):
		for r in _home:
			var ex: Dictionary = r.get("extra", {}) if r.get("extra") is Dictionary else {}
			if str(r.get("addon_id", "")) != str(s.get("addon_id", "")) or str(r.get("type", "")) != str(s.get("type", "")) \
					or str(r.get("catalog_id", "")) != str(s.get("catalog_id", "")) or str(ex.get("genre", "")) != str(s.get("genre", "")):
				continue
			for it in r.get("items", []):
				if Art.backdrop_url(it) != "":
					return Art.backdrop_url(it)
	return ""


## Eine Karte in einer Reihe ist gewählt: die Bühne zeigt sie (die Rotation hält an, solange man
## auf einer Karte steht – _on_card).
func _on_row_card(_idx: int, c: Control, it: Dictionary, dir: int) -> void:
	_on_card = true
	if it.is_empty():
		return
	_show_hero(it, dir, c)
	var hl := _hero_list.find(it)
	if hl >= 0:
		_hero_i = hl


## Die Bühne zu einem Titel, Ordner oder „Alle anzeigen“: Grund (nur beim Weiterschauen),
## Schriftzug oder Name, Art · Genre · Jahr · ★, zwei Zeilen Beschreibung, die Tasten der Karte;
## das Hintergrundbild oben rechts und das Licht im Raum. card: die gewählte Karte (null: Rotation).
func _show_hero(it: Dictionary, dir: int, card: Control = null) -> void:
	if it.is_empty() or _buehne == null or not is_instance_valid(_buehne):
		return
	var why := _reason(it)
	var zeile := str(it.get("hero_line", "")) if it.has("hero_line") else Art.meta_line(it)
	var rating := Art.rating_text(it.get("imdb_rating", ""))
	if rating != "":
		zeile += Art.SEP + "★ " + rating
	var text := { "grund": [why, "history"] if why != "" else [], "titel": str(it.get("name", "")), "logo": str(it.get("logo", "")), "zeile": zeile,
		"zeile2": str(it.get("description", "")), "tasten": MedienBuehne.tasten_von(card) }
	if bool(it.get("_more", false)):
		# „Alle anzeigen“: nur der Text wechselt, das Bild bleibt.
		_buehne.zeige(it, dir, text)
		return
	var key := str(it.get("id", ""))
	var url := Art.backdrop_url(it)
	var ph := Art.backdrop_tex(key)
	# Farbe des Farbfelds gleich mitgeben: sonst läse der Hintergrund sie von der Grafikkarte
	# zurück (get_image) – das hielt in Uzai.exe das Bild an, mitten im Überblenden der Bühne.
	if not ph.has_meta("uz_vivid"):
		ph.set_meta("uz_vivid", [Color.from_hsv(Art.hue_of(key), 0.42, 0.62)])
	var bild := { "key": "mv:" + key, "urls": [url] if url != "" else [], "ph": ph, "warm": [] }
	if card != null and is_instance_valid(card) and card.get_parent():
		var i := card.get_index()
		for j in [i + 1, i - 1]:
			var n := card.get_parent().get_child(j) if j >= 0 and j < card.get_parent().get_child_count() else null
			if n and n.get("item") is Dictionary and Art.backdrop_url(n.get("item")) != "":
				(bild.warm as Array).append(Art.backdrop_url(n.get("item")))
	_buehne.zeige(it, dir, text, bild)


## Ein echter Grund über dem Titel – nur beim Weiterschauen.
func _reason(it: Dictionary) -> String:
	if not it.has("position"):
		return ""
	var parts := PackedStringArray(["Als Nächstes" if bool(it.get("next_up", false)) else "Weiterschauen"])
	if int(it.get("episode", 0)) > 0:
		parts.append(Art.episode_code(int(it.get("season", 0)), int(it.episode)))
		var et := str(it.get("episode_title", ""))
		if et != "":
			parts.append("„%s“" % et)
	var lt := Art.left_text(float(it.get("position", 0.0)), float(it.get("duration", 0.0)))
	if lt != "" and not bool(it.get("next_up", false)):
		parts.append(lt)
	return Art.SEP.join(parts)


## Steht niemand auf einer Karte, wechselt die Bühne von selbst durch die Titelbilder (ohne Tasten).
func _hero_tick() -> void:
	if _on_card or _hero_list.size() < 2 or not visible or Nav.top_layer() != null or Video.active:
		return
	if main == null or main.current != id:
		return
	_hero_i = (_hero_i + 1) % _hero_list.size()
	_show_hero(_hero_list[_hero_i], 1)


func _decorate_grid(c: Control) -> void:
	var it: Dictionary = c.get("item")
	_card_hints(c, it)
	c.set_meta("uz_on_x", func() -> void: _toggle_library(it))
	if str(it.get("type", "")) == "movie":
		c.set("watched", Movies.watched(str(it.get("id", "")), str(it.get("id", ""))))


## Kleine Auswahl-Pille (Katalog, Genre, Art).
func _pill(text: String, icon: String, key: String) -> Button:
	var b := U.button(text, icon, "flat")
	b.custom_minimum_size.y = 60
	b.set_meta("uz_key", key)
	return b


# --- Bibliothek -------------------------------------------------------------------------------

func _build_library() -> void:
	var all: Array = Movies.library_items()
	if all.is_empty():
		add_child(empty_state("Deine Bibliothek ist leer", "Mit X merken.", [
			["Zur Startseite", "tv", func() -> void: main.goto("movies", "start")],
			["Suchen", "search", func() -> void: main.goto("movies", "suche")],
			["Addons und Plugins", "grid", func() -> void: open_manage("addons")],
		]))
		return
	var list := all.filter(func(m: Dictionary) -> bool: return _lib_filter == "" or str(m.get("type", "")) == _lib_filter)
	var head := U.margin(GUTTER, 4, GUTTER, 0)
	var row := U.hbox(14)
	row.set_meta("uz_group", "lib-kopf")
	head.add_child(row)
	var names := { "": "Alles", "movie": "Filme", "series": "Serien" }
	var fb := _pill(str(names.get(_lib_filter, "Alles")), "list", "lib:art")
	fb.set_meta("uz_hint_a", "Art wählen")
	fb.pressed.connect(func() -> void:
		main.open_choice("Was zeigen?", [["", "Alles"], ["movie", "Nur Filme"], ["series", "Nur Serien"]], _lib_filter, func(v: Variant) -> void:
			_lib_filter = str(v)
			_rebuild_keep()
		)
	)
	row.add_child(fb)
	var mb := _pill("Addons und Plugins", "grid", "lib:addons")
	mb.set_meta("uz_hint_a", "Verwalten")
	mb.pressed.connect(func() -> void: open_manage("addons"))
	row.add_child(mb)
	var qb := _pill("Filme-Quellen", "drive", "lib:quellen")
	qb.set_meta("uz_hint_a", "Auswählen")
	qb.pressed.connect(func() -> void: main.open_movie_sources())
	row.add_child(qb)
	row.add_child(U.spacer())
	var info := U.label(U.plural(list.size(), "Titel", "Titel") + Art.SEP + "zuletzt hinzugefügt zuerst", "m", "faint", "medium")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	_grid = PosterGrid.new()
	_grid.group = "lib"
	_grid.head = head
	_grid.empty_text = "Keine %s in der Bibliothek." % ("Filme" if _lib_filter == "movie" else "Serien")
	_grid.decorate = func(c: Control) -> void: _decorate_grid(c)
	_grid.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
	U.full_rect(_grid)
	add_child(_grid)
	_grid.set_items(list)
	var f: Control = _grid.first_card()
	if f:
		f.set_meta("uz_default", true)
	else:
		fb.set_meta("uz_default", true)


# --- Suche --------------------------------------------------------------------------------------

func _build_search() -> void:
	var col := U.vbox(0)
	var sc := scroll_v(col)
	sc.set_meta("uz_pad_v", 170.0)
	U.full_rect(sc)
	add_child(sc)
	var top := U.margin(GUTTER, 4, GUTTER, 6)
	var row := U.hbox(14)
	row.set_meta("uz_group", "msuche-kopf")
	top.add_child(row)
	var btn := U.button(_query if _query != "" else "Filme und Serien suchen", "search")
	if _query != "":
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Eingetipptes: nie übersetzen
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(720, 64)
	var sb := UzTheme.box(UzTheme.col("glass_hi"), 999, 1, UzTheme.col("stroke"))
	sb.content_margin_left = 26
	sb.content_margin_right = 30
	btn.add_theme_stylebox_override("normal", sb)
	var fbx := UzTheme.focus_fill(999)
	fbx.content_margin_left = 26
	fbx.content_margin_right = 30
	btn.add_theme_stylebox_override("focus", fbx)
	btn.add_theme_font_override("font", UzTheme.font("medium"))
	if _query == "":
		btn.add_theme_color_override("font_color", UzTheme.col("muted"))
	btn.set_meta("uz_key", "msuche:knopf")
	btn.set_meta("uz_hint_a", "Bildschirmtastatur" if _query == "" else "Neu suchen")
	btn.pressed.connect(_ask_search)
	row.add_child(btn)
	for q in _recent.slice(0, 4):
		if str(q) == _query:
			continue
		var chip := U.button(str(q), "history")
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.custom_minimum_size.y = 64
		chip.set_meta("uz_key", "msuche:" + str(q))
		chip.set_meta("uz_hint_a", "Suchen")
		var qq := str(q)
		chip.pressed.connect(func() -> void: _run_search(qq))
		row.add_child(chip)
	col.add_child(top)
	var first: Control = null
	if _searching:
		var m := U.margin(GUTTER, 34, GUTTER, 0)
		m.add_child(U.label("Suche nach „%s“ …" % _query, "l", "muted"))
		col.add_child(m)
	elif _query != "" and _results.is_empty():
		var m2 := U.margin(GUTTER, 34, GUTTER, 0)
		var box := U.vbox(10)
		m2.add_child(box)
		box.add_child(U.label("Nichts gefunden", "xl", "text", "bold"))
		box.add_child(
				U.label("Keine Treffer für „%s“." % _query, "l", "muted", "regular",
				true))
		col.add_child(m2)
	else:
		var rows: Array = _results
		if _query == "":
			# Leere Suche: statt einer leeren Fläche, was gerade beliebt ist.
			rows = _home.filter(func(r): return str(r.get("kind", "")) != "folders" and not (r.get("items", []) as Array).is_empty()).slice(0, 2)
		for i in rows.size():
			var r: Dictionary = rows[i]
			var items: Array = r.get("items", [])
			if items.is_empty():
				continue
			var tm2 := U.margin(0, 22 if i == 0 else 6, 0, 0)
			var extra := U.plural(items.size(), "Treffer", "Treffer") if _query != "" else ("zum Stöbern" if i == 0 else "")
			tm2.add_child(section_title(str(r.get("title", "")), extra))
			col.add_child(tm2)
			var shelf = Shelf.new().setup("msuche:%d" % i, 22, true, 32, GUTTER, 30)
			shelf.custom_minimum_size.y = MovieCard.POSTER.y + MovieCard.GRID_LABEL_H + 62
			for it in items:
				var c = MovieCard.new()
				c.setup(it, "grid")
				c.key_prefix = "msuche%d:" % i
				_decorate_grid(c)
				c.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
				shelf.add(c)
				if first == null:
					first = c
			col.add_child(shelf)
		col.add_child(U.spacer(0, 120, false))
	if first and _query != "":
		first.set_meta("uz_default", true)
	else:
		btn.set_meta("uz_default", true)


## Von der globalen Suche: gleich mit diesem Suchwort suchen (der Bereich steht schon auf „Suche“).
func search_for(q: String) -> void:
	_run_search(q)


func _ask_search() -> void:
	main.open_keyboard("Filme und Serien suchen", _query, func(t: String) -> void:
		if t.strip_edges() != "":
			_run_search(t)
	)


func _run_search(q: String) -> void:
	_query = q.strip_edges()
	_recent.erase(_query)
	_recent.push_front(_query)
	_recent = _recent.slice(0, 6)
	_searching = true
	_results = []
	build()
	var got: Variant = await Movies.search(_query)
	# Inzwischen neu gesucht: Die ältere Antwort gehört nicht unter das neue Suchwort (und die neue Suche läuft noch).
	if q.strip_edges() != _query:
		return
	_results = got if got is Array else []
	_searching = false
	if visible and sub == "suche":
		build()
		await get_tree().process_frame
		focus_default()

extends "res://src/ui/layers/layer.gd"
## Detailseite eines Films oder einer Serie – aufgebaut wie in Nuvio TV.
##
## Das Hintergrundbild füllt den Bildschirm und läuft nach links und unten in den Raum aus. Unten
## links der Schriftzug (oder Name), darunter Abspielen bzw. „S1 F3 fortsetzen“ und
## Gesehen (X: Bibliothek), Trailer, Regie, die Beschreibung und Genres, Laufzeit, Jahr und Bewertung.
## Bei Serien folgen die Staffeln als Reiter und die Folgen mit Vorschaubild; dann Besetzung,
## ähnliche Titel und Trailer (Reiter wie in Nuvio) und die Angaben. B zurück.

const MovieCard := preload("res://src/ui/components/movie_card.gd")
const MovieBackdrop := preload("res://src/ui/components/movie_backdrop.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")
const NavItem := preload("res://src/ui/components/nav_item.gd")
const TabStrip := preload("res://src/ui/components/tab_strip.gd")
const MoviesScript := preload("res://src/core/movies.gd")

const GUT := 96
## Höhe des Kopfs: darunter schauen die Staffeln gerade noch hervor.
const HERO_H := 830.0
const TEXT_W := 1120.0

var item: Dictionary = {}          ## MetaPreview, mit dem die Seite geöffnet wurde
const Main := preload("res://src/main.gd")
var main: Main
var meta: Dictionary = {}
var _bd: Control
var _sc: ScrollContainer
var _col: VBoxContainer
var _hero_col: VBoxContainer
var _play: Button
var _seen_btn: Button
var _next: Dictionary = {}
var _season := -1
var _ep_shelf: Control
var _ep_host: VBoxContainer
var _people_host: VBoxContainer
var _people_tab := ""
var _person_tiles: Array = []      ## WeakRefs auf die Personen-Kacheln (für nachgeladene Fotos)
var _loading := true
var _home: Array = []


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	# Geteilte Elemente (src/ui/flug.gd): Das Plakat geht im großen Bild der Seite auf.
	if str(item.get("id", "")) != "":
		set_meta("uz_flug", "m:" + str(item.id))
		set_meta("uz_flug_art", "aufloesen")
	meta = item.duplicate(true)
	_bd = MovieBackdrop.new()
	_bd.layout = "full"
	add_child(_bd)
	_bd.show_item(item, true)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sc.follow_focus = false
	_sc.set_meta("uz_pad_v", 330.0)
	U.full_rect(_sc)
	add_child(_sc)
	# Beim Blättern tritt das Bild zurück, damit Folgen und Besetzung ruhig darauf liegen.
	_sc.get_v_scroll_bar().value_changed.connect(func(v: float) -> void:
		if is_instance_valid(_bd):
			_bd.set_dim(clampf(v / 900.0, 0.0, 0.72))
	)
	_col = U.vbox(0)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_col)
	_build_hero()
	_ep_host = U.vbox(0)
	_col.add_child(_ep_host)
	_people_host = U.vbox(0)
	_col.add_child(_people_host)
	_col.add_child(U.spacer(0, 220, false))
	add_child(_bottom_fade())
	Movies.progress_changed.connect(_on_progress)
	Movies.changed.connect(_on_changed)
	_load()


func _first_focus() -> Control:
	return _play


func flug_ziel() -> Control:
	return _bd


## Seite (layer.gd): Sie selbst ist die deckende Fläche, der Bildlauf mit Titel und Knöpfen ihre
## Schrift – beim Öffnen kommt der Grund zuerst, die Schrift danach (nie Titel über Titel).
func flaeche() -> Control:
	return self


func schrift() -> Array:
	return [_sc] if is_instance_valid(_sc) else []


func _load() -> void:
	var got: Variant = await Movies.meta(str(item.get("type", "movie")), str(item.get("id", "")))
	if not is_inside_tree():
		return
	_loading = false
	var m: Dictionary = got if got is Dictionary else {}
	if not m.is_empty():
		# Was die Vorschau schon hatte, bleibt, wenn die Angaben es nicht liefern.
		for k in item.keys():
			if not m.has(k) or str(m[k]) == "" or (m[k] is Array and (m[k] as Array).is_empty() and item[k] is Array and not (item[k] as Array).is_empty()):
				m[k] = item[k]
		meta = m
	_update_hero(m.is_empty())
	_build_episodes()
	# „Ähnliche Titel“ kommen aus den Reihen der Startseite (Movies hält sie zwischengespeichert).
	var hr: Variant = await Movies.home_rows()
	if not is_inside_tree():
		return
	_home = hr if hr is Array else []
	_build_people()
	_load_cast_photos()


func _exit_tree() -> void:
	if Movies.progress_changed.is_connected(_on_progress):
		Movies.progress_changed.disconnect(_on_progress)
	if Movies.changed.is_connected(_on_changed):
		Movies.changed.disconnect(_on_changed)


# --- Kopf ----------------------------------------------------------------------------------------

func _build_hero() -> void:
	var host := Control.new()
	host.custom_minimum_size = Vector2(0, HERO_H)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(host)
	_sc.set_meta("uz_top_node", host)
	_hero_col = U.vbox(0)
	_hero_col.alignment = BoxContainer.ALIGNMENT_END
	_hero_col.position = Vector2(GUT, 0)
	_hero_col.size = Vector2(TEXT_W, HERO_H - 34)
	host.add_child(_hero_col)
	var name_ := str(item.get("name", ""))
	var title := U.label(name_, "hero", "text", "title", true)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Films bzw. der Serie
	title.custom_minimum_size = Vector2(TEXT_W * 0.8, 0)
	title.max_lines_visible = 2
	title.add_theme_constant_override("line_spacing", -8)
	U.shadow(title, 0.5)
	var logo_url := str(item.get("logo", ""))
	if logo_url != "":
		var logo := TextureRect.new()
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size = Vector2(560, 180)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero_col.add_child(logo)
		title.visible = false
		Art.load_image(logo_url, 560, func(t: Texture2D) -> void:
			if not is_instance_valid(logo):
				return
			if t:
				logo.texture = t
			else:
				logo.visible = false
				title.visible = true
		)
	_hero_col.add_child(title)
	_hero_col.add_child(U.spacer(0, 26, false))
	var btns := U.hbox(16)
	btns.set_meta("uz_group", "mdetail-knoepfe")
	_hero_col.add_child(btns)
	_play = U.button("Abspielen", "play", "primary")
	_play.set_meta("uz_key", "mdetail:play")
	_play.set_meta("uz_default", true)
	_play.pressed.connect(_play_main)
	btns.add_child(_play)
	# Bibliothek ohne eigenen Knopf: X auf den Knöpfen, unten in der Leiste angezeigt.
	_play.set_meta("uz_on_x", _toggle_library)
	if str(item.get("type", "")) == "movie":
		_seen_btn = U.button("Gesehen", "eye")
		_seen_btn.set_meta("uz_key", "mdetail:gesehen")
		_seen_btn.pressed.connect(func() -> void:
			var mid := str(meta.get("id", ""))
			Movies.set_watched(mid, mid, not Movies.watched(mid, mid))
			_update_buttons()
		)
		_seen_btn.set_meta("uz_on_x", _toggle_library)
		btns.add_child(_seen_btn)
	_hero_col.add_child(U.spacer(0, 26, false))
	var info := U.vbox(14)
	info.name = "Info"
	_hero_col.add_child(info)
	_fill_info(info)
	_update_buttons()


## Regie, Beschreibung und die Zeile mit Genres, Laufzeit, Jahr und Bewertung.
func _fill_info(info: VBoxContainer) -> void:
	U.clear(info)
	var credit := _credit()
	if credit != "":
		var cl := U.label(credit, "m", "muted", "medium")
		U.shadow(cl, 0.4)
		info.add_child(cl)
	var desc := str(meta.get("description", "")).strip_edges()
	if desc != "":
		var d := Art.fit_lines(U.label(desc, "m", "text", "regular", true), TEXT_W, 3)
		# Beschreibung vom Addon (langer fremder Text): nie durch die Übersetzung – sie suchte darin nach Bruchstücken.
		d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		d.modulate.a = 0.92
		U.shadow(d, 0.45)
		info.add_child(d)
	var row := U.hbox(18)
	var parts := PackedStringArray()
	var g: Array = meta.get("genres", []) if meta.get("genres") is Array else []
	if not g.is_empty():
		parts.append(", ".join(PackedStringArray(g.slice(0, 3))))
	var rt := Art.runtime_text(meta.get("runtime", ""))
	if rt != "":
		parts.append(rt)
	var y := str(meta.get("year", ""))
	if y != "":
		parts.append(y)
	if str(meta.get("type", "")) == "series":
		var ns := Art.season_order(meta).filter(func(s: int) -> bool: return s > 0).size()
		if ns > 0:
			parts.append(U.plural(ns, "Staffel", "Staffeln"))
	if str(meta.get("content_rating", "")) != "":
		parts.append(str(meta.content_rating))
	var ml := U.label(Art.SEP.join(parts), "m", "muted", "medium")
	U.shadow(ml, 0.4)
	row.add_child(ml)
	var r := Art.rating_text(meta.get("imdb_rating", ""))
	if r != "":
		var rb := U.hbox(6)
		var st := U.icon("star_f", 20, "accent")
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rb.add_child(st)
		rb.add_child(U.label(r, "m", "text", "ui_bold"))
		# Bewertungen eigener Medienserver (Publikum, Kritik) sind keine von IMDb.
		if str(meta.get("source", "")) == "":
			rb.add_child(U.label("IMDb", "s", "faint", "medium"))
		row.add_child(rb)
	info.add_child(row)


func _credit() -> String:
	var d: Array = meta.get("director", []) if meta.get("director") is Array else []
	if not d.is_empty():
		return "Regie: " + ", ".join(PackedStringArray(d.slice(0, 2)))
	var w: Array = meta.get("writer", []) if meta.get("writer") is Array else []
	if not w.is_empty():
		return "Drehbuch: " + ", ".join(PackedStringArray(w.slice(0, 2)))
	return ""


func _update_hero(failed: bool) -> void:
	var info := _hero_col.get_node_or_null("Info") as VBoxContainer
	if info:
		_fill_info(info)
		if failed and Movies.error != "":
			var e := U.label("Keine Angaben: " + Movies.error, "s", "warn", "medium")
			info.add_child(e)
	var trailers: Array = meta.get("trailers", []) if meta.get("trailers") is Array else []
	if not trailers.is_empty() and _play.get_parent().get_node_or_null("Trailer") == null:
		var tb := U.button("Trailer", "video")
		tb.name = "Trailer"
		tb.set_meta("uz_key", "mdetail:trailer")
		tb.set_meta("uz_hint_a", "Trailer ansehen")
		tb.pressed.connect(func() -> void: _play_trailer(trailers[0]))
		_play.get_parent().add_child(tb)
	_update_buttons()


func _toggle_library() -> void:
	var on: bool = Movies.toggle_library(meta)
	Toasts.show_toast("In der Bibliothek" if on else "Aus der Bibliothek entfernt", str(meta.get("name", "")), "bookmark_f" if on else "bookmark",
			{ "sound": "select", "quiet": true })
	_update_buttons()


## Abspielen-Knopf, Bibliothek (X) und Gesehen nach dem Stand von Movies.
func _update_buttons() -> void:
	var mid := str(meta.get("id", ""))
	var cw: Array = Movies.continue_watching()
	_next = Art.next_up(meta, cw,
			func(a: String, b: String) -> bool: return Movies.watched(a, b), func(a: String, b: String) -> Dictionary: return Movies.progress(a, b))
	if is_instance_valid(_play):
		var label := str(_next.get("label", "Abspielen"))
		if _loading and str(meta.get("type", "")) == "series":
			label = "Abspielen"
		_play.text = label
		_play.icon = Icons.tex("play", 26)
		_play.set_meta("uz_hint_a", "Quelle wählen")
	var lib: bool = Movies.in_library(mid)
	for b in [_play, _seen_btn]:
		if is_instance_valid(b):
			(b as Control).set_meta("uz_hint_x", "Aus der Bibliothek" if lib else "In die Bibliothek")
	if is_instance_valid(_seen_btn):
		var w: bool = Movies.watched(mid, mid)
		_seen_btn.text = "Gesehen" if w else "Als gesehen"
		_seen_btn.icon = Icons.tex("check" if w else "eye", 26)
		_seen_btn.set_meta("uz_hint_a", "Nicht gesehen" if w else "Gesehen")
	Nav.focus_moved.emit(Nav.focused())


func _play_main() -> void:
	if str(meta.get("type", "")) == "series":
		if _loading:
			Toasts.show_toast("Einen Moment", "Die Folgen werden noch geladen.", "clock", { "quiet": true })
			return
		var v: Dictionary = _next.get("video", {})
		if v.is_empty():
			Toasts.show_toast("Keine Folge zum Abspielen", "Keine Folgen.", "info")
			return
		main.open_movie_streams(meta, str(v.id), "resume" if bool(_next.get("resume", false)) else "ask")
		return
	main.open_movie_streams(meta, str(meta.get("id", "")), "resume" if bool(_next.get("resume", false)) else "ask")


func _play_trailer(t: Dictionary) -> void:
	var yt := str(t.get("yt_id", ""))
	if yt == "":
		return
	main.open_video([{ "id": yt, "title": "%s – %s" % [str(meta.get("name", "")), str(t.get("title", "Trailer"))], "channel": "Trailer" }], 0)


# --- Staffeln und Folgen --------------------------------------------------------------------------

func _build_episodes() -> void:
	U.clear(_ep_host)
	_ep_shelf = null
	if str(meta.get("type", "")) != "series":
		return
	var seasons := Art.season_order(meta)
	if seasons.is_empty():
		return
	if _season < 0 or not seasons.has(_season):
		var nv: Dictionary = _next.get("video", {})
		_season = int(nv.get("season", seasons[0])) if not nv.is_empty() else int(seasons[0])
	var tm := U.margin(GUT - 16, 18, GUT, 0)
	var strip := TabStrip.new()
	strip.style = "chip"
	strip.set_meta("uz_group", "staffeln")
	strip.set_meta("uz_enter", "sel")
	tm.add_child(strip)
	_ep_host.add_child(tm)
	for s in seasons:
		var it = NavItem.new()
		var count := (meta.get("videos", []) as Array).filter(func(v: Dictionary) -> bool: return int(v.get("season", -1)) == int(s)).size()
		it.setup(Art.season_name(int(s)), "", "chip", int(s) == _season, count)
		it.set_meta("uz_key", "staffel:%d" % int(s))
		it.set_meta("uz_hint_a", "Folgen")
		var sv := int(s)
		it.picked.connect(func() -> void:
			if _season != sv:
				_season = sv
				for c in strip.get_children():
					if c.has_method("set_selected"):
						c.set_selected(str(c.get_meta("uz_key", "")) == "staffel:%d" % sv)
				_fill_episodes(0)
		)
		it.opened.connect(func() -> void:
			var first := _first_episode()
			if first:
				Nav.focus(first)
		)
		strip.add_child(it)
	_ep_shelf = Shelf.new().setup("folgen", 22, true, 22, GUT, 34)
	_ep_shelf.custom_minimum_size.y = MovieCard.EPISODE.y + 22 + 34
	_ep_host.add_child(_ep_shelf)
	_fill_episodes(0)


func _fill_episodes(dir: int) -> void:
	if not is_instance_valid(_ep_shelf):
		return
	var shelf = _ep_shelf
	U.clear(shelf.row)
	shelf.scroll_horizontal = 0
	var mid := str(meta.get("id", ""))
	var target := str((_next.get("video", {}) as Dictionary).get("id", ""))
	for v in meta.get("videos", []):
		if int(v.get("season", -1)) != _season:
			continue
		var e: Dictionary = (v as Dictionary).duplicate()
		var vid := str(e.get("id", ""))
		var p: Dictionary = Movies.progress(mid, vid)
		e["_frac"] = Art.frac(float(p.get("position", 0.0)), float(p.get("duration", 0.0)))
		e["_watched"] = Movies.watched(mid, vid)
		e["_backdrop"] = Art.backdrop_url(meta)
		var c = MovieCard.new()
		c.setup(e, "episode")
		c.key_prefix = "%s:" % mid
		var seen := bool(e._watched)
		c.set_meta("uz_hint_a", "Abspielen" if bool(e.get("available", true)) else "Abspielen (noch nicht erschienen)")
		c.set_meta("uz_hint_x", "Nicht gesehen" if seen else "Gesehen")
		c.set_meta("uz_on_x", func() -> void:
			Movies.set_watched(mid, vid, not Movies.watched(mid, vid))
		)
		if vid == target:
			c.set_meta("uz_entry", true)
		c.chosen.connect(func(ep: Dictionary) -> void:
			var pp: Dictionary = Movies.progress(mid, str(ep.id))
			main.open_movie_streams(meta, str(ep.id), "ask" if Art.can_resume(float(pp.get("position", 0.0)), float(pp.get("duration", 0.0))) else "start")
		)
		shelf.add(c)
	if shelf.row.get_child_count() > 0 and not shelf.row.get_children().any(func(n: Node) -> bool: return n.has_meta("uz_entry")):
		shelf.row.get_child(0).set_meta("uz_entry", true)
	if dir != 0:
		shelf.modulate.a = 0.0
		U.tw(shelf, "uz_eps").tween_property(shelf, "modulate:a", 1.0, U.T_BASE)


func _first_episode() -> Control:
	if not is_instance_valid(_ep_shelf):
		return null
	for c in _ep_shelf.row.get_children():
		if c.has_meta("uz_entry"):
			return c
	return _ep_shelf.row.get_child(0) if _ep_shelf.row.get_child_count() > 0 else null


# --- Besetzung, Ähnliches, Trailer, Angaben ------------------------------------------------------

func _build_people() -> void:
	U.clear(_people_host)
	var tabs: Array = []
	var cast: Array = meta.get("cast", []) if meta.get("cast") is Array else []
	var crew: Array = []
	for d in (meta.get("director", []) if meta.get("director") is Array else []):
		crew.append([str(d), "Regie"])
	for w in (meta.get("writer", []) if meta.get("writer") is Array else []):
		if not crew.any(func(c: Array) -> bool: return c[0] == str(w)):
			crew.append([str(w), "Drehbuch"])
	if not cast.is_empty() or not crew.is_empty():
		tabs.append(["cast", "Besetzung und Team"])
	var sim := Art.similar(meta, _home)
	if not sim.is_empty():
		tabs.append(["similar", "Ähnliche Titel"])
	var trailers: Array = meta.get("trailers", []) if meta.get("trailers") is Array else []
	if not trailers.is_empty():
		tabs.append(["trailer", "Trailer"])
	if not tabs.is_empty():
		if _people_tab == "" or not tabs.any(func(t: Array) -> bool: return t[0] == _people_tab):
			_people_tab = str(tabs[0][0])
		var tm := U.margin(GUT - 16, 30, GUT, 0)
		var strip := TabStrip.new()
		strip.style = "chip"
		strip.set_meta("uz_group", "personen")
		strip.set_meta("uz_enter", "sel")
		tm.add_child(strip)
		_people_host.add_child(tm)
		var content := U.vbox(0)
		for t in tabs:
			var it = NavItem.new()
			it.setup(str(t[1]), "", "chip", t[0] == _people_tab)
			it.set_meta("uz_key", "ptab:" + str(t[0]))
			it.set_meta("uz_hint_a", "Ansehen")
			var tid := str(t[0])
			it.picked.connect(func() -> void:
				if _people_tab != tid:
					_people_tab = tid
					for c in strip.get_children():
						if c.has_method("set_selected"):
							c.set_selected(str(c.get_meta("uz_key", "")) == "ptab:" + tid)
					_fill_people(content, cast, crew, sim, trailers)
			)
			strip.add_child(it)
		_people_host.add_child(content)
		_fill_people(content, cast, crew, sim, trailers)
	_build_facts()


func _fill_people(host: VBoxContainer, cast: Array, crew: Array, sim: Array, trailers: Array) -> void:
	U.clear(host)
	match _people_tab:
		"cast":
			var shelf = Shelf.new().setup("besetzung", 30, true, 22, GUT, 20)
			shelf.custom_minimum_size.y = 250
			_person_tiles.clear()
			for c in crew:
				shelf.add(_person(str(c[0]), str(c[1]), false))
			for n in cast:
				shelf.add(_person(str(n), "Besetzung", true))
			host.add_child(shelf)
		"similar":
			var shelf2 = Shelf.new().setup("aehnlich", 22, true, 32, GUT, 34)
			shelf2.custom_minimum_size.y = MovieCard.POSTER.y + MovieCard.GRID_LABEL_H + 66
			for it in sim:
				var c = MovieCard.new()
				c.setup(it, "grid")
				c.key_prefix = "aehnlich:"
				c.set_meta("uz_hint_a", "Details")
				c.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
				shelf2.add(c)
			host.add_child(shelf2)
		"trailer":
			var shelf3 = Shelf.new().setup("trailer", 22, true, 22, GUT, 34)
			shelf3.custom_minimum_size.y = MovieCard.WIDE.y + 56
			for t in trailers:
				var c2 = MovieCard.new()
				c2.setup(
						{ "id": "trailer:" + str(t.get("yt_id", "")), "name": str(t.get("title", "Trailer")), "background": Art.backdrop_url(meta), "position": 0.0,
						"duration": 0.0 }, "wide")
				c2.set_meta("uz_hint_a", "Trailer ansehen")
				var tt: Dictionary = t
				c2.chosen.connect(func(_v: Dictionary) -> void: _play_trailer(tt))
				shelf3.add(c2)
			host.add_child(shelf3)


## Eine Person: rundes Foto (aus meta.people), bis es da ist und ohne Foto die Initialen in der
## Farbe des Namens; darunter Name und Rolle (bei der Besetzung die Figur, wenn bekannt).
func _person(name_: String, role: String, is_cast: bool) -> Control:
	var c := _Person.new()
	c.who = name_
	c.role = role
	c.is_cast = is_cast
	var info := _person_info(name_)
	c.photo = str(info.get("photo", ""))
	if is_cast and str(info.get("character", "")) != "":
		c.role = str(info.character)
		c.rolle_fremd = true
	c.set_meta("uz_key", "person:%s:%s" % [role, name_])
	c.set_meta("uz_hint_a", "—")
	_person_tiles.append(weakref(c))
	return c


func _person_info(name_: String) -> Dictionary:
	var people: Dictionary = meta.get("people", {}) if meta.get("people") is Dictionary else {}
	var v: Variant = people.get(MoviesScript.person_key(name_))
	return v if v is Dictionary else {}


## Lieferte das Addon nur Namen, holt Movies die Bilder nach (TMDB mit eigenem Schlüssel oder ein
## anderes Addon wie Cinemeta). Die Kacheln bekommen sie nachträglich, ohne neu aufgebaut zu werden.
func _load_cast_photos() -> void:
	var cast: Array = meta.get("cast", []) if meta.get("cast") is Array else []
	var dirs: Array = meta.get("director", []) if meta.get("director") is Array else []
	if cast.is_empty() and dirs.is_empty():
		return
	if MoviesScript.has_photos(meta.get("people")):
		return
	var got: Variant = await Movies.cast_photos(str(meta.get("type", item.get("type", "movie"))), meta)
	if not is_inside_tree() or not (got is Dictionary) or (got as Dictionary).is_empty():
		return
	meta["people"] = MoviesScript.merge_people(meta.get("people", {}) if meta.get("people") is Dictionary else {}, got)
	for w in _person_tiles:
		var t: Variant = w.get_ref()
		if t != null:
			var info := _person_info(str(t.who))
			t.call("set_photo", str(info.get("photo", "")), str(info.get("character", "")) if t.is_cast else "")


class _Person extends Control:
	const U2 := preload("res://src/ui/u.gd")
	const Art2 := preload("res://src/ui/components/movie_art.gd")
	const R := 60.0
	var who := ""
	var role := ""
	var rolle_fremd := false      ## role ist der Name der Figur (nie übersetzen), sonst „Regie“, „Besetzung“ …
	var photo := ""
	var is_cast := false
	var _f := 0.0
	var _tex: Texture2D
	var _tex_a := 0.0
	var _ini: Label
	var _role_l: Label
	var _in_ready := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(150, 206)
		_ini = U2.label(Art2.initials(who), "xl", "text", "bold")
		_ini.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Anfangsbuchstaben
		_ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_ini.position = Vector2(15, 0)
		_ini.size = Vector2(120, 120)
		add_child(_ini)
		var col := U2.vbox(2)
		col.position = Vector2(0, 132)
		col.size = Vector2(150, 72)
		add_child(col)
		var n := U2.label(who, "s", "text", "bold", true)
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Namen bleiben, wie sie sind
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size = Vector2(150, 0)
		n.max_lines_visible = 2
		col.add_child(n)
		_role_l = U2.label(role, "xs", "muted", "medium")
		if rolle_fremd:
			_role_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_role_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_role_l.custom_minimum_size = Vector2(150, 0)
		_role_l.clip_text = true
		_role_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(_role_l)
		focus_entered.connect(func() -> void: _anim(1.0))
		focus_exited.connect(func() -> void: _anim(0.0))
		_in_ready = true
		_request()
		_in_ready = false

	## Foto (und Figur) nachträglich, wenn Movies sie nachgeladen hat.
	func set_photo(url: String, character := "") -> void:
		if character != "" and is_instance_valid(_role_l):
			role = character
			rolle_fremd = true
			_role_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_role_l.text = character
		if url == "" or url == photo and _tex != null:
			return
		photo = url
		_request()

	func _request() -> void:
		if photo == "":
			return
		var me: WeakRef = weakref(self)
		var want := photo
		Art2.load_image(photo, int(R * 2.0), func(t: Texture2D) -> void:
			var p: Variant = me.get_ref()
			if p != null and t != null and str(p.photo) == want:
				p.call("_got", t)
		)

	func _got(t: Texture2D) -> void:
		_tex = t
		if _in_ready or not is_inside_tree():
			_set_a(1.0)
			return
		U2.tw(self, "uz_pa").tween_method(_set_a, _tex_a, 1.0, U2.T_BASE)

	func _set_a(v: float) -> void:
		_tex_a = v
		if is_instance_valid(_ini):
			_ini.modulate.a = 1.0 - v
		queue_redraw()

	func _anim(to: float) -> void:
		var tw := U2.tw(self, "uz_pf")
		tw.tween_method(func(v: float) -> void:
			_f = v
			queue_redraw()
		, _f, to, U2.T_BASE)

	func _draw() -> void:
		var c := Vector2(75, 60)
		var hue := Art2.hue_of(who)
		if _tex_a < 1.0:
			draw_circle(c, R, Color.from_hsv(hue, 0.38, 0.42), true, -1.0, true)
		if _tex != null and _tex_a > 0.0:
			# Ausschnitt quadratisch: Hochformat (Porträts) oben ausgerichtet, damit das Gesicht drin ist.
			var ts := _tex.get_size()
			var su := 1.0
			var sv := 1.0
			if ts.y > ts.x and ts.y > 0.0:
				sv = ts.x / ts.y
			elif ts.x > ts.y and ts.x > 0.0:
				su = ts.y / ts.x
			var u0 := (1.0 - su) * 0.5
			var v0 := (1.0 - sv) * 0.18
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 64:
				var a := TAU * i / 64.0
				var d := Vector2(cos(a), sin(a))
				pts.append(c + d * R)
				uvs.append(Vector2(u0 + (d.x * 0.5 + 0.5) * su, v0 + (d.y * 0.5 + 0.5) * sv))
			draw_colored_polygon(pts, Color(1, 1, 1, _tex_a), uvs, _tex)
			draw_arc(c, R - 0.5, 0.0, TAU, 72, Color(1, 1, 1, 0.07 * _tex_a), 1.0, true)
		if _f > 0.01:
			# Menschen bleiben rund; im eckigen Theme nur der Ring, ohne Glimmen darum.
			if not UzTheme.strict():
				draw_arc(c, 66.0, 0, TAU, 72, Color(UzTheme.col("accent"), 0.3 * _f), 8.0, true)
			draw_arc(c, 62.5, 0, TAU, 72, Color(UzTheme.col("focus"), _f), 3.0, true)


## Angaben: Regie, Drehbuch, Land, Erschienen, Auszeichnungen (nur was es gibt).
func _build_facts() -> void:
	var facts: Array = []
	var d: Array = meta.get("director", []) if meta.get("director") is Array else []
	if not d.is_empty():
		facts.append(["Regie", ", ".join(PackedStringArray(d))])
	var w: Array = meta.get("writer", []) if meta.get("writer") is Array else []
	if not w.is_empty():
		facts.append(["Drehbuch", ", ".join(PackedStringArray(w))])
	if str(meta.get("country", "")) != "":
		facts.append(["Land", str(meta.country)])
	var rel := str(meta.get("released", "")).get_slice("T", 0)
	if rel != "":
		var p := rel.split("-")
		facts.append(["Erschienen", "%s.%s.%s" % [p[2], p[1], p[0]] if p.size() == 3 else rel])
	if str(meta.get("awards", "")) != "":
		facts.append(["Auszeichnungen", str(meta.awards)])
	if facts.is_empty():
		return
	var tm := U.margin(GUT, 34, GUT, 0)
	tm.add_child(U.label("Angaben", "l", "text", "bold"))
	_people_host.add_child(tm)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 64)
	grid.add_theme_constant_override("v_separation", 18)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f in facts:
		var v := U.vbox(2)
		v.custom_minimum_size = Vector2(500, 0)
		v.add_child(U.label(str(f[0]), "s", "faint", "bold"))
		var wert := U.label(str(f[1]), "m", "text", "regular", true)
		wert.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Namen, Land, Datum, Auszeichnungen
		v.add_child(wert)
		grid.add_child(v)
	var gm := U.margin(GUT, 16, GUT, 0)
	gm.add_child(grid)
	_people_host.add_child(gm)


# --- Änderungen -------------------------------------------------------------------------------

func _on_progress(mid: String) -> void:
	if mid == str(meta.get("id", "")):
		_refresh()


func _on_changed() -> void:
	_update_buttons()


## Nach dem Abspielen oder „Gesehen“: Knöpfe und Folgen auf den neuesten Stand, Auswahl bleibt.
func _refresh() -> void:
	if not is_inside_tree():
		return
	_update_buttons()
	if not is_instance_valid(_ep_shelf):
		return
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", "")) if f and _ep_shelf.is_ancestor_of(f) else ""
	_fill_episodes(0)
	if key != "":
		await get_tree().process_frame
		for c in Nav.focusables(_ep_shelf):
			if str(c.get_meta("uz_key", "")) == key:
				Nav.focus(c, true)
				break


## Unten läuft die Seite in den Raum aus: Was unter die Hinweise rutscht, verschwindet ganz.
func _bottom_fade() -> Control:
	var g := Gradient.new()
	var bg := UzTheme.col("bg")
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.7, 1.0])
	g.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 0.78), Color(bg, 1.0), Color(bg, 1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var f := TextureRect.new()
	f.texture = gt
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.anchor_top = 1.0
	f.anchor_bottom = 1.0
	f.anchor_right = 1.0
	f.offset_top = -170
	return f

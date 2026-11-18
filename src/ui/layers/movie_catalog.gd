extends "res://src/ui/layers/layer.gd"
## „Alle anzeigen“ einer Reihe – wie die Katalogseite von Nuvio TV: oben der Name der Reihe und
## ein Genre-Filter, darunter alle Titel als Raster. Beim Blättern lädt die Seite weiter nach.
## X legt einen Titel in die Bibliothek, A öffnet ihn, B geht zurück.
##
## Als Ordner einer Nuvio-Sammlung (folder gesetzt): oben ein Reiter je Katalog im Ordner, davor
## „Alle“ (wie in Nuvio TV, wenn die Sammlung das will und es mehrere Kataloge gibt). Dahinter
## liegt groß das Hintergrundbild des Ordners (ohne eigenes das des ersten Titels).

const PosterGrid := preload("res://src/ui/components/poster_grid.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const MovieBackdrop := preload("res://src/ui/components/movie_backdrop.gd")

## Abdunklung des Ordner-Bilds: oben, und wenn das Raster ganz nach unten geblättert ist.
const BD_DIM := 0.18
const BD_DIM_MAX := 0.72

const Main := preload("res://src/main.gd")
var main: Main
var row: Dictionary = {}           ## Row von der Startseite (addon_id, type, catalog_id, extra)
var folder: Dictionary = {}        ## Ordner einer Nuvio-Sammlung { title, collection, sources, backdrop }
var show_all := true
var _tab := 0
var _tab_btns: Array = []
var _switched := false             ## Reiter gewechselt: der Fokus bleibt auf dem Reiter
var _genre := ""
var _grid = null
var _info: Label
var _genre_btn: Button
var _bd = null


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var ex: Dictionary = row.get("extra", {}) if row.get("extra") is Dictionary else {}
	_genre = str(ex.get("genre", ""))
	if not folder.is_empty():
		_bd = MovieBackdrop.new()
		_bd.layout = "full"
		add_child(_bd)
		_bd.set_dim(BD_DIM)
		_bd.show_item(folder_item(folder), true)
	_build_grid()


## Ordner als Eintrag für Kopf und Hintergrund (wie heroPreview in Nuvio TV): Name mit Emoji
## (ausgeblendet, wenn Nuvio es so will), Schriftzug, Hintergrundbild, darunter Sammlung und
## Zahl der Kataloge, als Beschreibung ihre Namen. fallback: Bild, wenn der Ordner keins hat.
static func folder_item(f: Dictionary, fallback := "") -> Dictionary:
	var srcs: Array = f.get("sources", []) if f.get("sources") is Array else []
	var title := str(f.get("title", ""))
	var emoji := str(f.get("emoji", ""))
	# Bibliotheken und Sammlungen eines Medienservers: eigene Zeile statt „Sammlung · 1 Katalog“.
	var server := f.has("label")
	var parts := PackedStringArray([str(f.get("label", "Sammlung"))])
	if str(f.get("collection", "")) != "":
		parts.append(str(f.collection))
	if not server:
		parts.append("%d %s" % [srcs.size(), "Katalog" if srcs.size() == 1 else "Kataloge"])
	var names := source_names(srcs, " – ") if not server else []
	var bd := str(f.get("backdrop", ""))
	return {
		"id": "ordner:%s/%s" % [str(f.get("collection", "")), str(f.get("id", title))], "kind": "folder",
		"name": "" if bool(f.get("hide_title", false)) else ((emoji + "  " if emoji != "" else "") + title),
		"logo": str(f.get("logo", "")), "background": bd if bd != "" else fallback, "hero_line": Art.SEP.join(parts),
		"description": ("Darin: " + ", ".join(PackedStringArray(names)) + ".") if not names.is_empty() else str(f.get("description", "")),
	}


func _first_focus() -> Control:
	var f: Control = _grid.first_card() if _grid != null and is_instance_valid(_grid) else null
	if f:
		return f
	return _tab_btns[_tab] if not folder.is_empty() and _tab < _tab_btns.size() else _genre_btn


## Reiter des Ordners: [Name, Quelle oder {} für „Alle“].
func _tabs() -> Array:
	var srcs: Array = folder.get("sources", [])
	var out: Array = []
	if show_all and srcs.size() >= 2:
		out.append(["Alle", {}])
	var names := source_names(srcs)
	for i in srcs.size():
		out.append([names[i], srcs[i]])
	return out


## Namen der Kataloge eines Ordners (Reiter, Kopf der Startseite); gleiche Namen bekommen
## „Filme“ bzw. „Serien“ dazu.
static func source_names(srcs: Array, sep := Art.SEP) -> Array:
	var names: Array = srcs.map(func(s): return source_name(s))
	var seen := {}
	for nm in names:
		seen[nm] = int(seen.get(nm, 0)) + 1
	for i in srcs.size():
		if int(seen[names[i]]) > 1:
			names[i] = str(names[i]) + sep + ("Filme" if type_key(str(srcs[i].get("type", ""))) == "movie" else "Serien")
	return names


## Name eines Katalogs im Ordner wie in Nuvio TV: der Name aus dem Addon (gesucht im Addon der
## Quelle, mit gleichem Typ, sonst Kennung bis zum ersten Komma, sonst in allen Addons), dazu das
## Genre. Ohne Treffer ein lesbarer Name aus der Kennung statt „trakt.list.…“.
static func source_name(s: Dictionary) -> String:
	# Bibliotheken und Sammlungen eines Medienservers tragen ihren Namen selbst.
	if str(s.get("name", "")) != "":
		return str(s.name)
	var c := find_catalog(Movies.addons, str(s.get("addon_id", "")), str(s.get("type", "")), str(s.get("catalog_id", "")))
	var base := str(c.get("name", "")).strip_edges() if not c.is_empty() else ""
	if base == "":
		base = readable_id(str(s.get("catalog_id", "")))
	if base == "":
		base = "Filme" if str(s.get("type", "")) == "movie" else "Serien"
	base = base.substr(0, 1).to_upper() + base.substr(1)
	var g := str(s.get("genre", ""))
	return base + (" · " + g if g != "" and g.to_lower() != "none" else "")


## Katalog einer Sammlungs-Quelle finden (wie findCollectionCatalog in Nuvio).
static func find_catalog(addons: Array, addon_id: String, type: String, catalog_id: String) -> Dictionary:
	var own: Array = []
	for a in addons:
		if str(a.get("id", "")) == addon_id:
			own = a.get("catalogs", [])
	var short := catalog_id.get_slice(",", 0)
	for id in [catalog_id, short]:
		var hit := _match(own, type, str(id))
		if not hit.is_empty():
			return hit
	for a in addons:
		var hit2 := _match(a.get("catalogs", []), type, catalog_id)
		if not hit2.is_empty():
			return hit2
	return {}


static func _match(cats: Array, type: String, id: String) -> Dictionary:
	var cands: Array = cats.filter(func(c): return c is Dictionary and str(c.get("id", "")) == id)
	for c in cands:
		if str(c.get("type", "")) == type.strip_edges():
			return c
	var same: Array = cands.filter(func(c): return type_key(str(c.get("type", ""))) == type_key(type))
	return same[0] if same.size() == 1 else {}


static func type_key(t: String) -> String:
	var k := t.strip_edges().to_lower()
	if k in ["movies", "film", "films"]:
		return "movie"
	if k in ["tv", "show", "shows", "serie"]:
		return "series"
	return k


## „trakt.list.jane.best-of-2024“ → „Best of 2024“.
static func readable_id(id: String) -> String:
	var parts := id.replace("_", ".").replace(":", ".").replace("/", ".").split(".", false)
	var last := ""
	for i in range(parts.size() - 1, -1, -1):
		var p := str(parts[i])
		if not p.is_valid_int() and not (p.to_lower() in ["list", "lists", "trakt", "movie", "movies", "series", "show", "shows"]):
			last = p
			break
	last = last.replace("-", " ").replace("+", " ").strip_edges()
	return last.substr(0, 1).to_upper() + last.substr(1) if last != "" else ""


## „Alle“: die erste Seite jedes Katalogs gleichzeitig, abwechselnd gemischt, ohne Doppelte.
## Wartet nicht auf den langsamsten: nach ALL_WAIT Sekunden zählt, was schon da ist.
const ALL_WAIT := 4.0
const ALL_TIMEOUT := 10.0


## Statisch, damit späte Antworten nichts mehr an einer inzwischen geschlossenen Seite anfassen.
static func _load_all(srcs: Array, skip: int) -> Array:
	if skip > 0:
		return []
	var tree := Engine.get_main_loop() as SceneTree
	var pages: Array = []
	var box := { "left": srcs.size() }
	for s in srcs:
		var page: Array = []
		pages.append(page)
		_load_src(s, page, box)
	var t0 := Time.get_ticks_msec()
	while int(box.left) > 0:
		if Time.get_ticks_msec() - t0 > ALL_WAIT * 1000.0 and pages.any(func(p): return not (p as Array).is_empty()):
			break
		await tree.create_timer(0.1).timeout
	var out: Array = []
	var seen := {}
	for i in 100:
		var any := false
		for p in pages:
			if i < (p as Array).size():
				any = true
				var it: Dictionary = p[i]
				if not seen.has(str(it.get("id", ""))):
					seen[str(it.get("id", ""))] = true
					out.append(it)
		if not any:
			break
	return out


static func _load_src(s: Dictionary, into: Array, box: Dictionary) -> void:
	# Die Arbeit läuft in einer eigenen Funktion: Bricht sie mit einem Fehler ab, wird hier trotzdem heruntergezählt.
	# Sonst wartete die Schleife des Aufrufers für immer.
	await _load_src_arbeit(s, into, box)
	box.left = int(box.left) - 1


static func _load_src_arbeit(s: Dictionary, into: Array, box: Dictionary) -> void:
	var ex := { "genre": str(s.genre) } if str(s.get("genre", "")) != "" else {}
	var got: Variant = await Movies.catalog_page(str(s.addon_id), str(s.type), str(s.catalog_id), 0, ex, ALL_TIMEOUT)
	if got is Array:
		into.append_array(got)


func _build_grid() -> void:
	if _grid != null and is_instance_valid(_grid):
		_grid.queue_free()
	var type := str(row.get("type", "movie"))
	var head := U.vbox(10)
	var hm := U.margin(UzTheme.GUTTER, 58, UzTheme.GUTTER, 0)
	var hv := U.vbox(12)
	hm.add_child(hv)
	head.add_child(hm)
	hv.add_child(U.label(str(row.get("title", "Alle anzeigen")), "xxl", "text", "title"))
	var line := U.hbox(14)
	line.set_meta("uz_group", "katalog-kopf")
	hv.add_child(line)
	if not folder.is_empty():
		_build_folder_grid(head, line)
		return
	_genre_btn = U.button("Alle Genres" if _genre == "" else _genre, "tag", "flat")
	_genre_btn.custom_minimum_size.y = 60
	_genre_btn.set_meta("uz_key", "katalog:genre")
	_genre_btn.set_meta("uz_hint_a", "Genre wählen")
	_genre_btn.pressed.connect(_pick_genre)
	line.add_child(_genre_btn)
	_info = U.label(_addon_text(type), "m", "faint", "medium")
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_info)
	_grid = PosterGrid.new()
	_grid.group = "katalog"
	_grid.head = head
	_grid.empty_text = "Hier gibt es nichts" + (" im Genre „%s“." % _genre if _genre != "" else ".")
	_grid.decorate = func(c: Control) -> void:
		var it: Dictionary = c.get("item")
		c.set_meta("uz_hint_a", "Details")
		c.set_meta("uz_hint_x", "Aus der Bibliothek" if Movies.in_library(str(it.get("id", ""))) else "In die Bibliothek")
		c.set_meta("uz_on_x", func() -> void:
			var on: bool = Movies.toggle_library(it)
			Toasts.show_toast("In der Bibliothek" if on else "Aus der Bibliothek entfernt", str(it.get("name", "")), "bookmark_f" if on else "bookmark",
					{ "sound": "select", "quiet": true })
			c.set_meta("uz_hint_x", "Aus der Bibliothek" if on else "In die Bibliothek")
			Nav.focus_moved.emit(Nav.focused())
		)
		if str(it.get("type", "")) == "movie":
			c.set("watched", Movies.watched(str(it.get("id", "")), str(it.get("id", ""))))
	var extra: Dictionary = (row.get("extra", {}) as Dictionary).duplicate() if row.get("extra") is Dictionary else {}
	if _genre != "":
		extra["genre"] = _genre
	else:
		extra.erase("genre")
	var aid := str(row.get("addon_id", ""))
	var cid := str(row.get("catalog_id", ""))
	_grid.loader = func(skip: int) -> Array:
		var got: Variant = await Movies.catalog_page(aid, type, cid, skip, extra)
		return got if got is Array else []
	_grid.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
	U.full_rect(_grid)
	add_child(_grid)
	_first_page()


## Ordnerseite: Reiter je Katalog, darunter das Raster des gewählten.
func _build_folder_grid(head: Control, line: HBoxContainer) -> void:
	var tabs := _tabs()
	_tab = clampi(_tab, 0, maxi(tabs.size() - 1, 0))
	_tab_btns.clear()
	for i in tabs.size():
		var b := U.button(str(tabs[i][0]), "", "primary" if i == _tab else "flat")
		b.custom_minimum_size.y = 56
		b.set_meta("uz_key", "ordner:tab:%d" % i)
		b.set_meta("uz_hint_a", "Anzeigen")
		var ti := i
		b.pressed.connect(func() -> void:
			if ti == _tab:
				return
			_tab = ti
			_switched = true
			_build_grid()
			await get_tree().process_frame
			if ti < _tab_btns.size() and is_instance_valid(_tab_btns[ti]):
				Nav.focus(_tab_btns[ti], true)
		)
		line.add_child(b)
		_tab_btns.append(b)
	if str(folder.get("collection", "")) != "":
		_info = U.label(str(folder.collection), "m", "faint", "medium")
		_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(_info)
	_grid = PosterGrid.new()
	_grid.group = "katalog"
	_grid.head = head
	_grid.empty_text = "Ordner ist leer."
	_grid.decorate = _decorate
	var src: Dictionary = tabs[_tab][1] if not tabs.is_empty() else {}
	var all_srcs: Array = folder.get("sources", [])
	_grid.loader = func(skip: int) -> Array:
		if src.is_empty():
			return await _load_all(all_srcs, skip)
		var ex := { "genre": str(src.genre) } if str(src.get("genre", "")) != "" else {}
		var got: Variant = await Movies.catalog_page(str(src.addon_id), str(src.type), str(src.catalog_id), skip, ex)
		return got if got is Array else []
	_grid.chosen.connect(func(v: Dictionary) -> void: main.open_movie(v))
	U.full_rect(_grid)
	add_child(_grid)
	# Beim Blättern tritt das Bild zurück (wie auf der Detailseite).
	_grid.get_v_scroll_bar().value_changed.connect(func(v: float) -> void:
		if is_instance_valid(_bd):
			_bd.set_dim(clampf(BD_DIM + v / 900.0, BD_DIM, BD_DIM_MAX))
	)
	_first_page()


func _decorate(c: Control) -> void:
	var it: Dictionary = c.get("item")
	c.set_meta("uz_hint_a", "Details")
	c.set_meta("uz_hint_x", "Aus der Bibliothek" if Movies.in_library(str(it.get("id", ""))) else "In die Bibliothek")
	c.set_meta("uz_on_x", func() -> void:
		var on: bool = Movies.toggle_library(it)
		Toasts.show_toast("In der Bibliothek" if on else "Aus der Bibliothek entfernt", str(it.get("name", "")), "bookmark_f" if on else "bookmark",
				{ "sound": "select", "quiet": true })
		c.set_meta("uz_hint_x", "Aus der Bibliothek" if on else "In die Bibliothek")
		Nav.focus_moved.emit(Nav.focused())
	)
	if str(it.get("type", "")) == "movie":
		c.set("watched", Movies.watched(str(it.get("id", "")), str(it.get("id", ""))))


func _addon_text(type: String) -> String:
	var own := Quellen.owner_of_addon(str(row.get("addon_id", "")))
	if own != "":
		return Quellen.label(own)
	var parts := PackedStringArray(["Filme" if type == "movie" else "Serien"])
	for a in Movies.addons:
		if str(a.get("id", "")) == str(row.get("addon_id", "")):
			parts.append(str(a.get("name", "")))
	return Art.SEP.join(parts)


func _first_page() -> void:
	var g = _grid
	await g.reload()
	if not is_instance_valid(g) or g != _grid or not is_inside_tree():
		return
	var f: Control = g.first_card()
	# Ordner ohne eigenes Bild: das Bild des ersten Titels (wie die Startseite, wenn sie ihn kennt).
	if is_instance_valid(_bd) and str(folder.get("backdrop", "")) == "" and str(_bd.item.get("background", "")) == "":
		for it in g.items():
			if Art.backdrop_url(it) != "":
				_bd.show_item(folder_item(folder, Art.backdrop_url(it)).merged({ "id": "ordner-titel:" + str(it.get("id", "")) }, true))
				break
	if f:
		f.set_meta("uz_default", true)
		var cur := Nav.focused()
		if Nav.top_layer() == self and (cur == null or cur == _genre_btn or (_tab_btns.has(cur) and not _switched) or not is_ancestor_of(cur)):
			Nav.focus(f, true)


func _pick_genre() -> void:
	var opts: Array = [["", "Alle Genres"]]
	var names: Array = await Movies.row_genres(row)
	if not is_inside_tree():
		return
	for g in names:
		opts.append([str(g), str(g)])
	main.open_choice("Genre", opts, _genre, func(v: Variant) -> void:
		if str(v) == _genre:
			return
		_genre = str(v)
		_build_grid()
		await get_tree().process_frame
		if is_instance_valid(_genre_btn):
			Nav.focus(_genre_btn, true)
	)

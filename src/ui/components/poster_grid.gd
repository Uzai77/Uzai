extends ScrollContainer
## Raster aus Plakaten (Filme, Serien, Alle anzeigen, Bibliothek): sieben Spalten bündig mit dem
## Rand. Mit loader lädt es Seite um Seite nach, schon wenn die Auswahl vier Reihen vor dem Ende
## ist (leichter Modus: zwei; Vorladen.page_from) – wie das Endlos-Raster in Nuvio, nur ohne
## Warten am Ende. Solange eine Seite lädt, stehen Platzhalter in Plakatform in den nächsten
## Zellen; die Karten treten an ihre Stelle, nichts verrutscht. Oben kann eine Kopfzeile stehen.

signal chosen(item: Dictionary)
signal focused_item(item: Dictionary)

const U := preload("res://src/ui/u.gd")
const MovieCard := preload("res://src/ui/components/movie_card.gd")
const Skeleton := preload("res://src/ui/components/skeleton.gd")
const Vorladen := preload("res://src/core/vorladen.gd")
const Leicht := preload("res://src/core/leicht.gd")

const COLUMNS := 7
const GAP_H := 22
const GAP_V := 30

var loader: Callable              ## func(skip: int) -> Array (darf warten)
var decorate: Callable            ## func(card) – Hinweise und X/Y je Karte
var group := "mgrid"
var head: Control
var empty_text := "Hier ist noch nichts."
var _col: VBoxContainer
var _grid: GridContainer
var _status: Label
var _items: Array = []
var _ids := {}
var _loading := false
var _ended := false
var _gen := 0
var _ghosts: Array = []


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	follow_focus = false
	set_meta("uz_pad_v", 170.0)
	_col = U.vbox(0)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_col)
	if head:
		_col.add_child(head)
	var m := U.margin(UzTheme.GUTTER, 36, UzTheme.GUTTER, 0)
	_col.add_child(m)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", GAP_H)
	_grid.add_theme_constant_override("v_separation", GAP_V)
	_grid.set_meta("uz_group", group)
	_grid.set_meta("uz_mem", true)
	m.add_child(_grid)
	var sm := U.margin(UzTheme.GUTTER, 24, UzTheme.GUTTER, 150)
	_status = U.label("", "m", "muted", "medium")
	sm.add_child(_status)
	_col.add_child(sm)


## Feste Liste ohne Nachladen.
func set_items(list: Array) -> void:
	_gen += 1
	_clear()
	_ended = true
	_append(list)
	_status.text = empty_text if _items.is_empty() else ""


## Von vorn laden (z. B. nach einem anderen Genre).
func reload() -> void:
	_gen += 1
	_clear()
	_ended = false
	_loading = false
	await load_more()


func _clear() -> void:
	_ghosts.clear()
	U.clear(_grid)
	_items.clear()
	_ids.clear()


func load_more() -> void:
	if _loading or _ended or not loader.is_valid():
		return
	_loading = true
	var gen := _gen
	_status.text = ""
	_add_ghosts()
	var got: Variant = await loader.call(_items.size())
	if gen != _gen or not is_instance_valid(_grid):
		return
	_loading = false
	_drop_ghosts()
	var list: Array = got if got is Array else []
	var added := _append(list)
	if added == 0:
		_ended = true
	_status.text = (empty_text if _items.is_empty() else "") if _ended or added == 0 else ""


func _append(list: Array) -> int:
	var added := 0
	for it in list:
		if not (it is Dictionary):
			continue
		var id := str(it.get("id", ""))
		if id == "" or _ids.has(id):
			continue
		_ids[id] = true
		_items.append(it)
		var c = MovieCard.new()
		c.setup(it, "grid")
		c.key_prefix = group + ":"
		var idx := _items.size() - 1
		c.focused_item.connect(func(v: Dictionary) -> void:
			focused_item.emit(v)
			if idx >= Vorladen.page_from(_items.size(), COLUMNS, Leicht.active):
				load_more()
		)
		c.chosen.connect(func(v: Dictionary) -> void: chosen.emit(v))
		if decorate.is_valid():
			decorate.call(c)
		_grid.add_child(c)
		added += 1
	return added


## Platzhalter in Plakatform: die Reihe bis zum Ende füllen und eine weitere (beim ersten Laden
## zwei Reihen). Größe wie die Karten davor bzw. wie eine Rasterkarte in dieser Breite.
func _add_ghosts() -> void:
	_drop_ghosts()
	var cell := Vector2.ZERO
	var last := _grid.get_child(_grid.get_child_count() - 1) as Control if _grid.get_child_count() > 0 else null
	if last:
		cell = last.get_combined_minimum_size()
	else:
		var w := floorf((U.view_size().x - UzTheme.GUTTER * 2.0 - GAP_H * (COLUMNS - 1)) / COLUMNS)
		cell = Vector2(w, roundf(w * 1.5) + MovieCard.GRID_LABEL_H)
	var poster_h := cell.y - MovieCard.GRID_LABEL_H
	var n := (COLUMNS - _grid.get_child_count() % COLUMNS) % COLUMNS + COLUMNS * (1 if _items.size() > 0 else 2)
	for i in n:
		var g = Skeleton.new()
		g.shapes = [
			{ "r": Rect2(0, 0, cell.x, poster_h) },
			{ "r": Rect2(2, poster_h + 12, cell.x * 0.75, 14), "rad": 6 },
			{ "r": Rect2(2, poster_h + 36, cell.x * 0.4, 11), "rad": 6, "a": 0.7 },
		]
		g.custom_minimum_size = cell
		_grid.add_child(g)
		_ghosts.append(g)


func _drop_ghosts() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			_grid.remove_child(g)
			g.queue_free()
	_ghosts.clear()


func first_card() -> Control:
	return _grid.get_child(0) as Control if _grid and _grid.get_child_count() > 0 else null


func items() -> Array:
	return _items

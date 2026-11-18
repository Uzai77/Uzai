extends RefCounted
## Level und Abzeichen im Profil (profile_page.gd): rechts im Banner das Uzai-Level (Ring mit
## Fortschritt, Punkte, „Noch 120 Punkte bis Level 13“), das Steam-Level wandert als Chip zu den
## anderen. Darunter die Reihe „Abzeichen“ mit den zuletzt verdienten und denen, die am nächsten
## dran sind, und am Ende „Alle Abzeichen“. Beides zieht sich nach, wenn Badges neu rechnet,
## ohne dass die Seite neu aufgebaut wird.

const U := preload("res://src/ui/u.gd")
const L := preload("res://src/core/badges_logic.gd")
const Ring := preload("res://src/ui/components/ach/ring.gd")
const Bar := preload("res://src/ui/components/progress_bar.gd")
const BadgeTile := preload("res://src/ui/components/badge_tile.gd")
const Shelf := preload("res://src/ui/components/shelf.gd")

const G := 96
const TILE := Vector2(224, 284)


## Uzai-Level rechts im Banner; steam_level ≥ 0 kommt als Chip dazu.
static func banner(b: Control, steam_level: int) -> void:
	var row: Variant = b.get("_row")
	if not (row is HBoxContainer):
		return
	if steam_level >= 0:
		var chips: Variant = b.get("chips")
		if chips is Control:
			(chips as Control).add_child(load("res://src/ui/sections/profile_page.gd").chip("steam", "Steam-Level %d" % steam_level))
			(chips as Control).visible = true
	var side := LevelSide.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	(row as HBoxContainer).add_child(side)


## Kompakte Zeile für Karten (Guide): „Level 22 · 14 Abzeichen“ mit schmalem Balken.
static func compact(width := 300.0) -> Control:
	var v := U.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(10)
	var l := U.label("Level %d" % Badges.level_number(), "s", "text", "ui_bold")
	l.clip_text = false
	h.add_child(l)
	var s := U.label("·  %s Abzeichen" % str(Badges.earned_count()), "s", "muted", "medium")
	s.clip_text = false
	h.add_child(s)
	v.add_child(h)
	v.add_child(Bar.new().setup(float(Badges.level.get("frac", 0.0)), "accent", 5.0, width))
	return v


## Kleines Etikett „Lv 22“ (Guide-Karte, Leiste oben); zieht sich selbst nach.
static func pill(size := "16") -> Control:
	var p := LevelPill.new()
	p.text_size = size
	return p


## Reihe „Abzeichen“ im Profil.
static func row(view: Control, col: VBoxContainer) -> void:
	var r := BadgeRow.new()
	r.view = view
	col.add_child(r)


class LevelPill extends PanelContainer:
	var text_size := "16"
	var _l: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := UzTheme.box(UzTheme.col("accent", 0.16), 999, 1, UzTheme.col("accent", 0.45))
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		add_theme_stylebox_override("panel", sb)
		_l = U.label("", text_size, "accent", "ui_bold")
		_l.clip_text = false
		add_child(_l)
		_fill()
		Badges.changed.connect(_fill)

	func _fill() -> void:
		_l.text = "Lv %d" % Badges.level_number()
		tooltip_text = "Uzai-Level %d · %s Abzeichen · %s" % [Badges.level_number(), Badges.earned_count(), L.level_left_text(Badges.total_points())]


class LevelSide extends VBoxContainer:
	var _ring: Control
	var _pts: Label
	var _left: Label
	var _bar: Control

	func _init() -> void:
		add_theme_constant_override("separation", 8)
		alignment = BoxContainer.ALIGNMENT_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_fill()
		Badges.changed.connect(_fill)

	func _fill() -> void:
		U.clear(self)
		var lv: Dictionary = Badges.level
		_ring = Ring.new().setup(float(lv.get("frac", 0.0)), 150, 10, str(Badges.level_number()), "", "Level")
		_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(_ring)
		var cap := U.label("Uzai-Level", "s", "text", "ui_bold")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(cap)
		_bar = Bar.new().setup(float(lv.get("frac", 0.0)), "accent", 5.0, 200.0)
		_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(_bar)
		_left = U.label(L.level_left_text(Badges.total_points()), "16", "muted", "medium")
		_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_left.clip_text = false
		add_child(_left)
		_pts = U.label("%s Uzai-Punkte" % L.num(Badges.total_points()), "16", "faint", "medium")
		_pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pts.clip_text = false
		add_child(_pts)


class BadgeRow extends VBoxContainer:
	var view: Control
	var _extra: Label
	var _shelf: ScrollContainer

	func _init() -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var m := U.margin(G, 0, G, 0)
		var h := U.hbox(14)
		m.add_child(h)
		var l := U.label("Abzeichen", "l", "text", "bold")
		l.clip_text = false
		h.add_child(l)
		_extra = U.label("", "m", "faint", "medium")
		_extra.clip_text = false
		h.add_child(_extra)
		add_child(m)
		_shelf = Shelf.new().setup("prof:badges", 24, true, 30, G, 36)
		add_child(_shelf)
		_fill()
		Badges.changed.connect(_refresh)

	## Neu füllen, außer die Auswahl steht gerade in der Reihe (sonst springt sie).
	func _refresh() -> void:
		var f := Nav.focused()
		if f and is_instance_valid(_shelf) and _shelf.is_ancestor_of(f):
			_extra.text = _extra_text()
			return
		_fill()

	func _extra_text() -> String:
		var all := Badges.entries()
		var got := all.filter(func(e): return int(e.tier) > 0).size()
		return "%d von %d  ·  Level %d" % [got, all.size(), Badges.level_number()]

	func _fill() -> void:
		_extra.text = _extra_text()
		var r: HBoxContainer = _shelf.get("row")
		U.clear(r)
		var list := Badges.showcase(10)
		for i in list.size():
			var e: Dictionary = list[i]
			var t = BadgeTile.new().setup(e, TILE)
			t.set_meta("uz_key", "prof:badge:" + str(e.id))
			t.set_meta("uz_hint_a", "Alle Abzeichen")
			if i == 0:
				t.set_meta("uz_entry", true)
			var id := str(e.id)
			t.chosen.connect(func() -> void: Badges.open_page(id))
			_shelf.call("add", t)
		var all = AllTile.new()
		all.set_meta("uz_key", "prof:badge:all")
		all.set_meta("uz_hint_a", "Alle Abzeichen")
		all.chosen.connect(func() -> void: Badges.open_page())
		_shelf.call("add", all)


## Letzte Kachel der Reihe: zur ganzen Seite.
class AllTile extends "res://src/ui/components/ach/tile.gd":
	func _init() -> void:
		super()
		tile_size = TILE
		bg_alpha = 0.55

	func build_body() -> void:
		var c := CenterContainer.new()
		U.full_rect(c)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(c)
		var v := U.vbox(12)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		c.add_child(v)
		var ic := U.icon("grid", 54, "accent")
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := U.label("Alle Abzeichen", "m", "text", "ui_bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		var all := Badges.entries()
		var s := U.label("%d von %d" % [all.filter(func(e): return int(e.tier) > 0).size(), all.size()], "s", "muted", "medium")
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)

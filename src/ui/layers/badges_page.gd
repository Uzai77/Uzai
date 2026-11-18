extends "res://src/ui/layers/layer.gd"
## Alle Abzeichen auf einer Seite. Oben das Uzai-Level (Ring, Punkte, wie viel bis zum nächsten,
## woher die Punkte kommen, Abzeichen je Stufe). Darunter links das Raster nach Kategorien,
## rechts die Einzelheiten des gewählten Abzeichens: große Medaille, was es zählt, alle vier
## Stufen mit Schwelle und Datum, der Weg zur nächsten. LB/RB springen zwischen den Kategorien.

const L := preload("res://src/core/badges_logic.gd")
const Medal := preload("res://src/ui/components/badge_medal.gd")
const BadgeTile := preload("res://src/ui/components/badge_tile.gd")
const Ring := preload("res://src/ui/components/ach/ring.gd")
const Bar := preload("res://src/ui/components/progress_bar.gd")
const EdgeFade := preload("res://src/ui/components/ach/edge_fade.gd")

const TILE := Vector2(206, 262)
const DETAIL_W := 540

const Main := preload("res://src/main.gd")
var main: Main
var focus_id := ""               ## dieses Abzeichen zuerst wählen
var _detail: VBoxContainer
var _cats: Array = []            ## [[Kategorie, erste Kachel]]
var _first: Control
var _shown := ""


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), 1.0)
	set_meta("uz_hint_b", "Zurück")
	set_meta("uz_hints", [["lb", ""], ["rb", "Kategorie"]])
	var root := U.margin(80, 56, 96, 96)
	U.full_rect(root)
	add_child(root)
	var col := U.vbox(26)
	root.add_child(col)
	var hm := U.margin(16, 0, 0, 0)
	hm.add_child(_header())
	col.add_child(hm)
	var row := U.hbox(40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var list := U.vbox(22)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = false
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.set_meta("uz_pad_v", 70.0)
	# Luft rundum: die gewählte Kachel hebt sich und trägt einen Ring, der nicht abgeschnitten wird.
	var pad := U.margin(16, 18, 16, 0)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(list)
	sc.add_child(pad)
	row.add_child(sc)
	EdgeFade.attach(sc, list)
	_grid(list)
	_detail = U.vbox(14)
	_detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	row.add_child(_detail)
	U.slide_x(root, 40.0, U.T_MOVE)


func _first_focus() -> Control:
	return _first


# --- Kopf --------------------------------------------------------------------------------------

func _header() -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface", 0.85), UzTheme.r_panel())
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := U.hbox(34)
	p.add_child(h)
	var lv: Dictionary = Badges.level
	var ring := Ring.new().setup(float(lv.get("frac", 0.0)), 132, 10, str(Badges.level_number()), "", "Level")
	h.add_child(ring)
	var info := U.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(info)
	var k := U.label("UZAI-LEVEL", "xs", "muted", "wide")
	info.add_child(k)
	var t := U.label("Level %d · %s Uzai-Punkte" % [Badges.level_number(), L.num(Badges.total_points())], "xl", "text", "black")
	t.clip_text = false
	info.add_child(t)
	var bar = Bar.new().setup(float(lv.get("frac", 0.0)), "accent", 8.0, 620.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(U.spacer(0, 4, false))
	info.add_child(bar)
	var pts: Dictionary = Badges.points
	var parts := PackedStringArray([L.level_left_text(Badges.total_points())])
	parts.append("Erfolge %s" % L.num(int(pts.get("ach", 0))))
	parts.append("Spielzeit %s" % L.num(int(pts.get("play", 0))))
	parts.append("Abzeichen %s" % L.num(int(pts.get("badges", 0))))
	var sub := U.label("  ·  ".join(parts), "s", "muted", "medium")
	sub.clip_text = false
	info.add_child(sub)
	# Rechts: Abzeichen je Stufe.
	var all := Badges.entries()
	var per := [0, 0, 0, 0, 0]
	for e in all:
		per[int(e.tier)] += 1
	var tiers := U.vbox(8)
	tiers.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := U.label("%d von %d Abzeichen" % [all.size() - int(per[0]), all.size()], "m", "text", "ui_bold")
	tl.clip_text = false
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tiers.add_child(tl)
	var trow := U.hbox(18)
	trow.alignment = BoxContainer.ALIGNMENT_END
	for i in range(1, 5):
		var cell := U.hbox(6)
		var m := Medal.new().setup({ "cat": "sozial", "glyph": "star" }, i, 40)
		m.pips = false
		cell.add_child(m)
		var n := U.label(str(per[i]), "m", "text", "bold")
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(n)
		trow.add_child(cell)
	tiers.add_child(trow)
	h.add_child(tiers)
	return p


# --- Raster ------------------------------------------------------------------------------------

func _grid(list: VBoxContainer) -> void:
	var all := Badges.entries()
	_cats.clear()
	for c in L.CATS:
		var cat := str(c[0])
		var items := all.filter(func(e): return str(e.def.cat) == cat)
		if items.is_empty():
			continue
		var got := items.filter(func(e): return int(e.tier) > 0).size()
		var head := U.hbox(14)
		var hl := U.label(str(c[1]), "l", "text", "bold")
		hl.clip_text = false
		head.add_child(hl)
		var hx := U.label("%s  ·  %d von %d" % [str(c[2]), got, items.size()], "m", "faint", "medium")
		hx.clip_text = false
		hx.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(hx)
		list.add_child(head)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 22)
		flow.add_theme_constant_override("v_separation", 22)
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(flow)
		var first: Control = null
		for e in items:
			var tile = BadgeTile.new().setup(e, TILE)
			tile.set_meta("uz_key", "badge:" + str(e.id))
			tile.set_meta("uz_hint_a", "Ansehen")
			tile.focus_entered.connect(_show_detail.bind(e))
			tile.chosen.connect(func() -> void: _celebrate(e))
			flow.add_child(tile)
			if first == null:
				first = tile
			if _first == null or (focus_id != "" and str(e.id) == focus_id):
				_first = tile
		_cats.append([cat, first])
		list.add_child(U.spacer(0, 6, false))
	list.add_child(U.spacer(0, 30, false))


func handle(cmd: String) -> bool:
	if cmd != "lb" and cmd != "rb":
		return false
	var f := Nav.focused()
	var cur := 0
	for i in _cats.size():
		var first: Control = _cats[i][1]
		if is_instance_valid(first) and f and first.get_parent() == f.get_parent():
			cur = i
	var to := clampi(cur + (1 if cmd == "rb" else -1), 0, _cats.size() - 1)
	if to == cur:
		Sfx.play("bump")
		return true
	Sfx.play("tab")
	Nav.focus(_cats[to][1])
	return true


## A auf einem Abzeichen: die Medaille blitzt kurz auf (verdient) – sonst nur der Fortschritt.
func _celebrate(e: Dictionary) -> void:
	var f := Nav.focused()
	if f and f.has_method("shine"):
		f.call("shine", 0.0)


# --- Einzelheiten ------------------------------------------------------------------------------

func _show_detail(e: Dictionary) -> void:
	if str(e.id) == _shown or not is_instance_valid(_detail):
		return
	_shown = str(e.id)
	U.clear(_detail)
	var d: Dictionary = e.def
	var t := int(e.tier)
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface", 0.7), UzTheme.r_panel())
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(p)
	var v := U.vbox(8)
	p.add_child(v)
	var top := U.hbox(26)
	v.add_child(top)
	var m := Medal.new().setup(d, t, 168)
	m.glow = 0.8 if t > 0 else 0.0
	top.add_child(m)
	var tv := U.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	var kick := U.label(tr(L.cat_name(str(d.cat))).to_upper(), "xs", "muted", "wide")
	kick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # schon übersetzt, dann groß geschrieben
	tv.add_child(kick)
	var nm := U.label(str(d.name), "xl", "text", "black", true)
	nm.custom_minimum_size.x = 280
	tv.add_child(nm)
	var st: String = (str(L.TIER_NAMES[t]) + " · " + L.tier_title(d, t)) if t > 0 else "Noch nicht erreicht"
	var sl := U.label(st, "m", "text" if t > 0 else "faint", "medium", true)
	sl.custom_minimum_size.x = 280
	if t > 0:
		sl.modulate = Color(str(Medal.METALS[t][1])).lerp(Color.WHITE, 0.35)
	tv.add_child(sl)
	v.add_child(U.spacer(0, 6, false))
	var desc := U.label(str(d.get("desc", "")), "s", "muted", "regular", true)
	desc.custom_minimum_size.x = DETAIL_W - 80
	v.add_child(desc)
	var pr: Dictionary = e.progress
	v.add_child(U.spacer(0, 6, false))
	if not bool(pr.get("done", false)):
		var nx := U.label("Nächste Stufe: %s" % L.tier_title(d, t + 1), "s", "text", "ui_bold")
		nx.clip_text = false
		v.add_child(nx)
		v.add_child(Bar.new().setup(float(pr.frac), "accent", 8.0, DETAIL_W - 80))
		var pl := U.label(str(pr.text), "s", "muted", "medium")
		v.add_child(pl)
	else:
		var dn := U.label("Höchste Stufe erreicht · " + str(pr.text), "s", "text", "ui_bold")
		dn.clip_text = false
		v.add_child(dn)
	v.add_child(U.spacer(0, 10, false))
	# Die vier Stufen.
	var at_list: Array = Badges.earned_at.get(str(e.id), [])
	var ts: Array = d.tiers
	for i in ts.size():
		var r := U.hbox(14)
		var mm := Medal.new().setup(d, i + 1 if t > i else 0, 46)
		mm.pips = false
		r.add_child(mm)
		var rl := U.vbox(0)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.alignment = BoxContainer.ALIGNMENT_CENTER
		var a := U.label("%s · %s" % [L.TIER_NAMES[i + 1], L.tier_title(d, i + 1)], "s", "text" if t > i else "muted", "ui_bold")
		a.clip_text = true
		rl.add_child(a)
		var b_text := ""
		if t > i:
			b_text = tr("Erreicht am %s") % U.date(int(at_list[i])) if at_list.size() > i and int(at_list[i]) > 0 else tr("Erreicht")
		else:
			var need := maxi(0, int(ts[i]) - int(floor(float(e.value) + 0.0001)))
			var u: Array = d.unit
			b_text = "Es fehlen %s %s · +%d Punkte" % [L.num(need), str(u[0]) if need == 1 else str(u[1]), int(L.TIER_POINTS[i + 1])] if not bool(
					d.get("no_points", false)) else "Es fehlen %s" % L.num(need)
		rl.add_child(U.label(b_text, "16", "faint", "regular"))
		r.add_child(rl)
		if t > i:
			r.add_child(U.icon("check", 24, "ok"))
		v.add_child(r)

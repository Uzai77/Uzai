extends "res://src/ui/components/ach/tile.gd"
## Ein frisch freigeschalteter Erfolg als Kachel: großes Abzeichen, Name, Spiel, Seltenheit
## (Steam) bzw. Punkte (RetroAchievements) und wann. Ganz neue tragen „Neu“.

const Ach := preload("res://src/core/achievements.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")

var a: Dictionary = {}
var fresh := false           ## in den letzten 24 Stunden freigeschaltet
var _emblem: Control


func _init() -> void:
	super()
	tile_size = Vector2(520, 176)


func build_body() -> void:
	var tier := Ach.rarity_tier(float(a.get("rarity", -1.0)))
	var m := U.margin(20, 20, 24, 20)
	U.full_rect(m)
	body.add_child(m)
	var row := U.hbox(22)
	m.add_child(row)
	_emblem = Emblem.new().setup(str(a.get("icon", "")), true, tier, 128)
	row.add_child(_emblem)
	var col := U.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var top := U.hbox(10)
	var t := U.ellipsis(U.label(str(a.get("title", "")), "m", "text", "ui_bold"))
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Name von Steam bzw. RetroAchievements
	top.add_child(t)
	if fresh:
		top.add_child(_pill("Neu"))
	col.add_child(top)
	col.add_child(U.ellipsis(U.label(str(a.get("game", "")), "s", "muted")))
	col.add_child(U.spacer(0, 12, false))
	var pct := float(a.get("rarity", -1.0))
	if tier >= 0:
		col.add_child(Rarity.tag(pct, "s"))
	else:
		var bits := PackedStringArray()
		if int(a.get("points", 0)) > 0:
			bits.append("%d Punkte" % int(a.points))
		if a.get("hardcore", false):
			bits.append("Hardcore")
		if not bits.is_empty():
			var pl := U.label("  ·  ".join(bits), "s", "text", "medium")
			pl.clip_text = false
			col.add_child(pl)
	var w := U.label(Rarity.when(int(a.get("date", 0))), "xs", "faint", "medium")
	w.clip_text = false
	col.add_child(w)


## Kleines Goldetikett (Neu).
func _pill(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("accent"), 999)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := U.label(text, "xs", "on_accent", "ui_bold")
	l.clip_text = false
	p.add_child(l)
	return p


## Auftritt eines Erfolgs, der gerade erst hereingekommen ist: Abzeichen glimmt auf, Licht zieht.
func celebrate(delay := 0.2) -> void:
	shine(delay)
	if _emblem == null:
		return
	var em := _emblem
	var base: float = em.get("glow")
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(em):
			em.call("set_glow", maxf(base, sin(v * PI)))
	, 0.0, 1.0, 1.2).set_trans(Tween.TRANS_SINE)

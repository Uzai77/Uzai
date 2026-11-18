extends "res://src/ui/components/ach/tile.gd"
## Kachel eines Abzeichens: Medaille, Name, erreichte Stufe und der Weg zur nächsten
## („37/50 Stunden“). Gewählt hebt sie sich wie alle Kacheln und die Medaille leuchtet auf.

const Medal := preload("res://src/ui/components/badge_medal.gd")
const L := preload("res://src/core/badges_logic.gd")
const Bar := preload("res://src/ui/components/progress_bar.gd")

var e: Dictionary = {}           ## Eintrag aus Badges.entries()
var medal: Control


func setup(entry: Dictionary, sz := Vector2(232, 292)) -> Control:
	e = entry
	tile_size = sz
	bg_alpha = 0.78
	return self


func build_body() -> void:
	var d: Dictionary = e.get("def", {})
	var t := int(e.get("tier", 0))
	var pr: Dictionary = e.get("progress", {})
	var m := U.margin(18, 20, 18, 18)
	U.full_rect(m)
	body.add_child(m)
	var col := U.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(col)
	var mp := int(minf(tile_size.x - 80.0, tile_size.y * 0.42))
	medal = Medal.new().setup(d, t, mp, float(pr.get("frac", 0.0)) if t < 4 else -1.0)
	medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(medal)
	col.add_child(U.spacer(0, 4, false))
	# Stufe als Kicker in der Farbe des Metalls, darunter Name und was die Stufe heißt.
	# Erst übersetzen, dann groß schreiben („SILBER“ steht so in keinem Katalog).
	var k := U.label((tr(str(L.TIER_NAMES[t])) if t > 0 else tr("Gesperrt", "abzeichen")).to_upper(), "cap", "text" if t > 0 else "faint", "wide")
	k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if t > 0:
		k.modulate = Color(str(Medal.METALS[t][1])).lerp(Color.WHITE, 0.3)
	col.add_child(k)
	var name_ := U.ellipsis(U.label(str(d.get("name", "")), "s", "text" if t > 0 else "muted", "ui_bold"))
	name_.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_)
	var tl := U.ellipsis(U.label(L.tier_title(d, t) if t > 0 else str(d.get("desc", "")), "16", "muted" if t > 0 else "faint", "regular"))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tl)
	col.add_child(U.spacer(0, 2, true))
	var done := bool(pr.get("done", false))
	if not done:
		col.add_child(Bar.new().setup(float(pr.get("frac", 0.0)), "accent", 5.0))
	var pl := U.ellipsis(U.label(str(pr.get("text", "")), "16", "text" if done else "muted", "medium"))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pl)


func _on_focus(on: bool) -> void:
	super(on)
	if is_instance_valid(medal):
		var wr: WeakRef = weakref(medal)
		U.tw(self, "uz_medal").tween_method(func(v: float) -> void:
			var me: Control = wr.get_ref()
			if me:
				me.call("set_glow", v)
		, float(medal.get("glow")), 1.0 if on and int(e.get("tier", 0)) > 0 else 0.0, U.T_BASE)

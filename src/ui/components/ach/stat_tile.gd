extends "res://src/ui/components/ach/tile.gd"
## Eine Kachel im Rückblick der Spielzeit: oben Symbol und Bezeichnung, groß der Wert,
## darunter ein Satz, was er bedeutet („an Sonntagen spielst du am längsten“).

var icon_name := "clock"
var label := ""
var value := ""
var sub := ""


func setup(ic: String, lab: String, val: String, s: String, sz := Vector2(414, 220)) -> Control:
	icon_name = ic
	label = lab
	value = val
	sub = s
	tile_size = sz
	return self


func build_body() -> void:
	var m := U.margin(28, 26, 28, 24)
	U.full_rect(m)
	body.add_child(m)
	var col := U.vbox(6)
	m.add_child(col)
	var head := U.hbox(12)
	head.add_child(U.icon(icon_name, 26, "accent"))
	var l := U.label(label, "s", "muted", "medium")
	l.clip_text = false
	head.add_child(l)
	col.add_child(head)
	col.add_child(U.spacer(0, 8, false))
	var v := U.ellipsis(U.label(value, "xl", "text", "black"))
	v.clip_text = true
	col.add_child(v)
	var s := U.label(sub, "s", "muted", "regular", true)
	s.max_lines_visible = 2
	col.add_child(s)

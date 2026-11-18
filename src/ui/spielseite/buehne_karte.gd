extends "res://src/ui/components/ach/tile.gd"
## Die Karte „Diese Woche“ im Profil: ruhige Fläche wie die anderen Kacheln (Anheben, Lichtkante, Schein), oben
## klein Symbol und Bezeichnung, darunter links die große Zahl mit einem Satz, rechts die Woche als sieben Säulen
## mit Tagen. Die Säulen füllen sich beim Erscheinen einmal (T_RAUM); die Zahl steht von Anfang an fest – nichts
## zählt hoch. „Animationen reduzieren“: alles steht sofort.
## (Die Spielseite hatte früher vier weitere Arten dieser Karte – Spielzeit, Erfolge, Freunde, Spielstand; seit den
## Pillen im Kopf baut sie niemand mehr, am 12.11.2026 entfernt.)

const Buehne := preload("res://src/ui/spielseite/buehne.gd")

var icon_name := "clock"
var label := ""
var value := ""
var sub := ""
var week: Array = []            ## Sekunden je Tag, älteste zuerst
var week_labels: Array = []     ## Kurzname je Tag; der letzte ist heute
var _t := 0.0


func setup_card(ic: String, lab: String, val: String, s: String, sz: Vector2) -> Control:
	icon_name = ic
	label = lab
	value = val
	sub = s
	tile_size = sz
	return self


func build_body() -> void:
	var m := U.margin(28, 22, 28, 22)
	U.full_rect(m)
	body.add_child(m)
	var col := U.vbox(4)
	m.add_child(col)
	var head := U.hbox(12)
	var ic := U.icon(icon_name, 24, "accent")
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var l := U.label(label, "s", "muted", "medium")
	l.clip_text = false
	head.add_child(l)
	col.add_child(head)
	col.add_child(U.spacer(0, 0, true))
	# Links die große Zahl mit Satz, rechts die Woche mit Tagen (_draw_extra).
	var row := U.hbox(16)
	var left := U.vbox(2)
	left.custom_minimum_size.x = tile_size.x * 0.4
	left.size_flags_vertical = Control.SIZE_SHRINK_END
	var v := U.label(value, "l", "text", "ui_bold")
	v.clip_text = true
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(v)
	var s := U.label(sub, "s", "muted", "regular", true)
	s.max_lines_visible = 1
	s.visible = sub != ""
	left.add_child(s)
	row.add_child(left)
	col.add_child(row)
	_fuellen()


## Die Säulen wachsen einmal hoch, im ruhigen Modus stehen sie sofort.
func _fuellen() -> void:
	if U.reduziert():
		_t = 1.0
		queue_redraw()
		return
	var wr: WeakRef = weakref(self)
	U.ankommen(self, U.T_RAUM, "uz_fill").tween_method(func(v: float) -> void:
		var me: Control = wr.get_ref()
		if me:
			me.set("_t", v)
			me.queue_redraw()
	, 0.0, 1.0, U.T_RAUM).set_delay(U.T_ANTWORT)


# --- Zeichnen -------------------------------------------------------------------------------

func _draw_extra(r: Rect2, _f: float) -> void:
	if not week.is_empty():
		_draw_week(Rect2(r.position.x + r.size.x * 0.44, r.position.y + 34.0, r.size.x * 0.56 - 32.0, r.size.y - 52.0))


## Sieben Säulen, heute im Akzent; Tage ohne Spiel als kleiner Punkt auf der Linie. Unter jeder Säule der
## Kurzname des Tags, über der stärksten und heute die Zeit.
func _draw_week(area: Rect2) -> void:
	var n := week.size()
	if n == 0 or area.size.x < 40.0:
		return
	var font := UzTheme.font("medium")
	var font_b := UzTheme.font("bold")
	var fs := UzTheme.size("xs")
	var bottom := fs + 14.0
	var top := fs + 10.0
	var base_y := area.end.y - bottom
	var area_h := maxf(16.0, base_y - area.position.y - top)
	var col_w := area.size.x / n
	var bar_w := minf(34.0, col_w * 0.58)
	var mx := 1
	var max_i := -1
	for i in n:
		if int(week[i]) > mx:
			mx = int(week[i])
			max_i = i
	draw_line(Vector2(area.position.x, base_y + 1.0), Vector2(area.end.x, base_y + 1.0), UzTheme.col("line"), 2.0)
	for i in n:
		var v := int(week[i])
		var today := i == n - 1
		var x := area.position.x + col_w * i + (col_w - bar_w) * 0.5
		var c := UzTheme.col("accent") if today else UzTheme.col("text", 0.26)
		if v > 0:
			var h := maxf(6.0, area_h * float(v) / float(mx)) * _t
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			var rr := int(minf(8.0, bar_w * 0.5))
			sb.corner_radius_top_left = rr
			sb.corner_radius_top_right = rr
			sb.corner_radius_bottom_left = 2
			sb.corner_radius_bottom_right = 2
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(x, base_y - h, bar_w, h))
			if (today or i == max_i) and _t > 0.95:
				draw_string(font_b, Vector2(area.position.x + col_w * i, base_y - h - 10.0), tr(Buehne.zeit_kurz(v)),
					HORIZONTAL_ALIGNMENT_CENTER, col_w, fs, UzTheme.col("accent") if today else UzTheme.col("muted"))
		else:
			draw_circle(Vector2(x + bar_w * 0.5, base_y - 5.0), 2.5, UzTheme.col("faint", 0.8))
		if i < week_labels.size():
			draw_string(font_b if today else font, Vector2(area.position.x + col_w * i, area.end.y - 2.0), tr(str(week_labels[i])),
				HORIZONTAL_ALIGNMENT_CENTER, col_w, fs, UzTheme.col("text") if today else UzTheme.col("faint"))

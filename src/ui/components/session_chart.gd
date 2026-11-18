extends "res://src/ui/components/ach/tile.gd"
## Die letzten Runden eines Spiels als Säulen (Spielseite, „Deine Spielzeit“): älteste links,
## neueste rechts, wie die Woche auf der Seite Spielzeit. Gewählt wandert mit links/rechts eine
## weiche Markierung über die Runden, oben steht dann, wann und wie lange – sonst die neueste.
## Die Säulen wachsen beim Öffnen einmal hoch.

const PlaytimePage := preload("res://src/ui/sections/playtime_page.gd")
const SessionSummary := preload("res://src/core/session_summary.gd")

var recent: Array = []        ## [{ secs, at (Ende) }], älteste zuerst (SessionSummary.per_game)
var bias := 0
var sel := 0
var _glide := 0.0             ## Markierung, gleitet zur gewählten Runde
var _t := 0.0
var _value: Label
var _when: Label


func setup(r: Array, b: int, sz: Vector2) -> Control:
	recent = r
	bias = b
	sel = r.size() - 1
	_glide = float(sel)
	tile_size = sz
	return self


func build_body() -> void:
	set_meta("uz_hint_a", "—")
	var m := U.margin(32, 26, 32, 0)
	m.set_anchors_preset(Control.PRESET_TOP_WIDE)
	body.add_child(m)
	var col := U.vbox(4)
	m.add_child(col)
	var head := U.hbox(12)
	head.add_child(U.icon("history", 26, "accent"))
	var l := U.label("Letzte Runden", "s", "muted", "medium")
	l.clip_text = false
	head.add_child(l)
	col.add_child(head)
	col.add_child(U.spacer(0, 6, false))
	_value = U.label("", "xl", "text", "black")
	col.add_child(_value)
	_when = U.label("", "s", "muted", "regular")
	col.add_child(_when)
	_show()
	var wr: WeakRef = weakref(self)
	create_tween().tween_method(func(v: float) -> void:
		var me: Control = wr.get_ref()
		if me:
			me.set("_t", v)
			me.queue_redraw()
	, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.15)


## Links/rechts: eine Runde weiter. Am Rand stößt die Auswahl an (der Verlauf ist so breit wie die
## Seite – links und rechts davon liegt nichts, sonst spränge der Fokus weit weg).
func nav_lr(d: int) -> bool:
	var n := sel + d
	if n < 0 or n >= recent.size():
		Nav._bump(self, "left" if d < 0 else "right")
		return true
	sel = n
	Sfx.play("tick")
	_show()
	U.tw(self, "uz_glide").tween_method(func(v: float) -> void:
		_glide = v
		queue_redraw()
	, _glide, float(sel), U.T_MOVE)
	return true


func _show() -> void:
	if recent.is_empty() or not is_instance_valid(_value):
		return
	var se: Dictionary = recent[sel]
	var now := int(Time.get_unix_time_from_system())
	var h24 := bool(Config.get_value("theme.clock_24h", true))
	_value.text = PlaytimePage.dur(int(se.secs))
	_when.text = "%s · %s – %s" % [SessionSummary.day_text(int(se.at) - int(se.secs), bias, now),
		SessionSummary.clock(int(se.at) - int(se.secs), bias, h24), SessionSummary.clock(int(se.at), bias, h24)]


func _draw_extra(r: Rect2, f: float) -> void:
	var n := recent.size()
	if n == 0:
		return
	# Feste Plätze (CHART_N), die neueste ganz rechts: wenige Runden stehen nicht verloren breit.
	var slots := maxi(SessionSummary.CHART_N, n)
	var left := r.position.x + 32.0
	var w := r.size.x - 64.0
	var top := r.position.y + 150.0
	var base_y := r.end.y - 44.0
	var area_h := maxf(20.0, base_y - top)
	var col_w := w / slots
	var bar_w := minf(46.0, col_w * 0.56)
	var maxv := 1
	for se in recent:
		maxv = maxi(maxv, int(se.secs))
	draw_line(Vector2(left, base_y + 1), Vector2(left + w, base_y + 1), UzTheme.col("line"), 2.0)
	var first := slots - n
	# Gewählt: ein heller Schein hinter der Säule, der beim Wechseln hinübergleitet.
	if f > 0.01:
		var gx := left + col_w * (first + _glide)
		draw_style_box(UzTheme.box(UzTheme.col("accent", 0.1 * f), 14), Rect2(gx + 4, top - 10, col_w - 8, base_y - top + 18))
	for i in slots:
		var cx := left + col_w * i + col_w * 0.5
		var k := i - first
		if k < 0:
			draw_circle(Vector2(cx, base_y - 6), 3.0, UzTheme.col("faint", 0.6))
			continue
		var v := int(recent[k].secs)
		var h := maxf(8.0, area_h * float(v) / maxv) * _t
		var sb := StyleBoxFlat.new()
		sb.bg_color = UzTheme.col("accent") if k == sel else UzTheme.col("text", 0.26)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(cx - bar_w * 0.5, base_y - h, bar_w, h))
	# Unten nur Anfang und Ende des gezeigten Zeitraums.
	var font := UzTheme.font("medium")
	var fs := UzTheme.size("xs")
	var now := int(Time.get_unix_time_from_system())
	var a := SessionSummary.day_text(int(recent[0].at), bias, now)
	var b := SessionSummary.day_text(int(recent[n - 1].at), bias, now)
	if n > 1 and a != b:
		draw_string(font, Vector2(left + col_w * first, r.end.y - 14), tr(a), HORIZONTAL_ALIGNMENT_LEFT, w * 0.5, fs, UzTheme.col("faint"))
	draw_string(font, Vector2(left + w * 0.5, r.end.y - 14), tr(b), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5, fs, UzTheme.col("faint"))

extends Control
## Sieben Säulen für die letzten sieben Tage, heute in der Akzentfarbe ganz rechts.
## Beschriftet sind nur heute und der stärkste Tag, damit es ruhig bleibt.
## ghost: nur Umrisse ohne Werte – als Bild auf der leeren Seite („so sieht es bald aus“).

const Lang := preload("res://src/core/lang.gd")

var values: Array = []        ## Sekunden pro Tag, ältester zuerst
var labels: Array = []        ## Kurzname pro Tag ("Mo", …); der letzte ist heute
var ghost := false
var _t := 0.0

const GHOST := [0.35, 0.6, 0.3, 0.82, 0.5, 1.0, 0.62]


func setup(v: Array, l: Array) -> Control:
	values = v
	labels = l
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(540, 250)
	resized.connect(queue_redraw)
	# Säulen wachsen beim Öffnen einmal kurz hoch.
	var wr: WeakRef = weakref(self)
	create_tween().tween_method(func(v: float) -> void:
		var me: Control = wr.get_ref()
		if me:
			me.set("_t", v)
			me.queue_redraw()
	, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.12)


func _draw() -> void:
	var n := values.size()
	if n == 0:
		return
	var font := UzTheme.font("bold")
	var font_m := UzTheme.font("medium")
	var fs := UzTheme.size("s")
	var top := 34.0
	var bottom := 40.0
	var area_h := size.y - top - bottom
	var col_w := size.x / n
	var bar_w := minf(46.0, col_w * 0.62)
	var maxv := 1
	var max_i := -1
	for i in n:
		if int(values[i]) > maxv:
			maxv = int(values[i])
			max_i = i
	var base_y := top + area_h
	draw_line(Vector2(0, base_y + 1), Vector2(size.x, base_y + 1), UzTheme.col("line"), 2.0)
	for i in n:
		var v := int(values[i])
		var today := i == n - 1 and not ghost
		var x := col_w * i + (col_w - bar_w) * 0.5
		var col := UzTheme.col("accent") if today else UzTheme.col("text", 0.26)
		if ghost:
			var gh := area_h * float(GHOST[i % GHOST.size()]) * _t
			var gsb := StyleBoxFlat.new()
			gsb.bg_color = UzTheme.col("text", 0.07)
			gsb.corner_radius_top_left = 10
			gsb.corner_radius_top_right = 10
			gsb.corner_radius_bottom_left = 3
			gsb.corner_radius_bottom_right = 3
			gsb.anti_aliasing = true
			draw_style_box(gsb, Rect2(x, base_y - gh, bar_w, gh))
		elif v > 0:
			var h := maxf(8.0, area_h * float(v) / maxv) * _t
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.corner_radius_top_left = 10
			sb.corner_radius_top_right = 10
			sb.corner_radius_bottom_left = 3
			sb.corner_radius_bottom_right = 3
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(x, base_y - h, bar_w, h))
			if today or i == max_i:
				var txt := _short(v)
				draw_string(font, Vector2(col_w * i, base_y - h - 12), tr(txt), HORIZONTAL_ALIGNMENT_CENTER, col_w, fs,
					UzTheme.col("accent") if today else UzTheme.col("muted"))
		else:
			# Kein Spiel an dem Tag: nur ein kleiner Punkt auf der Linie.
			draw_circle(Vector2(x + bar_w * 0.5, base_y - 6), 3.0, UzTheme.col("faint", 0.8))
		var lab := str(labels[i]) if i < labels.size() else ""
		draw_string(font if today else font_m, Vector2(col_w * i, size.y - 8), tr(lab), HORIZONTAL_ALIGNMENT_CENTER, col_w, fs,
			UzTheme.col("text") if today else UzTheme.col("faint"))


static func _short(secs: int) -> String:
	if secs < 3600:
		return "%d Min." % maxi(1, floori(secs / 60.0))
	var h := secs / 3600.0
	return Lang.dec("%.1f" % h) + " Std." if h < 10.0 else "%d Std." % int(h)

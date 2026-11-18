extends Control
## Kleines Akkusymbol eines Controllers (Statuszeile oben, Guide): Umriss mit Pol, darin bis zu
## drei Balken – grün ab mittel, gelb bei schwach, rot bei fast leer. Kabel ohne Akku (Xbox): ein
## Stecker-Blitz. Lädt er: Blitz über den Balken. Unbekannt: nur ein leiser Umriss.
## Mit number > 0 steht davor klein die Spieler-Nummer.

const U := preload("res://src/ui/u.gd")

var pad: Dictionary = {}
var h := 16.0                ## Höhe des Akkus
var number := 0
var ink_from: Control        ## gesetzt: auf dessen heller Auswahl dunkel zeichnen (Meta uz_f)


func setup(p: Dictionary, height := 16.0, num := 0) -> Control:
	pad = p
	h = height
	number = num
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var w := h * 1.9 + (_num_w() + 5.0 if number > 0 else 0.0)
	custom_minimum_size = Vector2(ceilf(w), ceilf(h + 2.0))
	if ink_from:
		ink_from.draw.connect(queue_redraw)


func _num_w() -> float:
	return UzTheme.font("bold").get_string_size(str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.95)).x


## Füllt box mit einem Akkusymbol je Controller (höchstens vier), davor einmal das Controller-Symbol.
static func fill(box: Container, pads: Array, height := 16.0, ink: Control = null) -> void:
	if not is_instance_valid(box):
		return
	U.clear(box)
	if pads.is_empty():
		return
	box.add_child(U.icon("controller", int(height * 1.4), "muted"))
	var many := pads.size() > 1
	for p in pads.slice(0, 4):
		var b: Control = (load("res://src/ui/components/pad_battery.gd") as GDScript).new()
		b.call("setup", p, height, int(p.get("slot", 0)) if many else 0)
		b.set("ink_from", ink)
		b.tooltip_text = "%s · %s" % [p.get("name", ""), p.get("slot", "")]
		box.add_child(b)


func _draw() -> void:
	var f := 0.0
	if is_instance_valid(ink_from):
		f = float(ink_from.get_meta("uz_f", 1.0 if ink_from.has_focus() else 0.0))
	var ink := UzTheme.col("muted").lerp(UzTheme.col("on_focus"), f)
	var x := 0.0
	var y := (size.y - h) * 0.5
	if number > 0:
		var fs := int(h * 0.95)
		var font := UzTheme.font("bold")
		draw_string(font, Vector2(0, y + h * 0.5 + font.get_ascent(fs) * 0.5 - 1.0), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		x = _num_w() + 5.0
	var bw := h * 1.75
	var nub := maxf(2.0, h * 0.14)
	var body := Rect2(x, y, bw - nub, h)
	var lvl := int(pad.get("level", -1))
	var wired := str(pad.get("power", "")) == "wired"
	var known := lvl >= 0 or wired
	var line := Color(ink, 0.95 if known else 0.45)
	var lw := maxf(1.4, h * 0.1)
	var rad := int(h * 0.22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = line
	sb.set_border_width_all(int(ceilf(lw)))
	sb.set_corner_radius_all(rad)
	sb.anti_aliasing = true
	draw_style_box(sb, body)
	draw_rect(Rect2(body.end.x + 0.5, y + h * 0.3, nub, h * 0.4), line)
	var inner := body.grow(-lw - maxf(1.0, h * 0.08))
	if lvl >= 0:
		var col := UzTheme.col("ok") if lvl >= 2 else (UzTheme.col("warn") if lvl == 1 else UzTheme.col("danger"))
		var gap := maxf(1.0, h * 0.08)
		var seg := (inner.size.x - gap * 2.0) / 3.0
		if lvl == 0:
			draw_rect(Rect2(inner.position, Vector2(maxf(2.0, seg * 0.35), inner.size.y)), col)
		for i in mini(lvl, 3):
			draw_rect(Rect2(inner.position + Vector2((seg + gap) * i, 0), Vector2(seg, inner.size.y)), col)
	if wired or bool(pad.get("charging", false)):
		_bolt(body.get_center(), h * 0.62, ink if wired else UzTheme.col("text"))


## Blitz: Kabel bzw. lädt.
func _bolt(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.12, -0.5) * s, c + Vector2(-0.28, 0.06) * s, c + Vector2(-0.02, 0.06) * s,
		c + Vector2(-0.12, 0.5) * s, c + Vector2(0.28, -0.06) * s, c + Vector2(0.02, -0.06) * s,
	])
	draw_colored_polygon(pts, col)

extends Control
## Rundes Profilbild. Ohne Bild: weicher Verlauf in der Farbe des Namens mit dem
## Anfangsbuchstaben. Das Bild blendet weich ein, sobald es geladen ist.
## Status als Punkt unten rechts, bei großen Bildern auf Wunsch als Ring (ring = true).

signal texture_loaded(t: Texture2D)

const U := preload("res://src/ui/u.gd")
const STATUS_COLORS := { "online": "ok", "game": "ok", "voice": "discord", "away": "warn", "idle": "warn", "busy": "live", "dnd": "live", "offline": "faint" }

var who := ""
var url := ""
var status := ""
var px := 52
var ring := false               ## Status als Ring um das Bild statt als Punkt
var _tex: Texture2D
var _tex_a := 0.0
var _in_ready := false


func setup(name_: String, image_url: String, st := "", size_px := 52) -> Control:
	who = name_
	url = image_url
	status = st
	px = size_px
	return self


## Farbe, die zu einem Namen gehört (auch für Lichter hinter großen Profilbildern).
static func hue_color(name_: String) -> Color:
	var h := float(absi(name_.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.5, 0.6)


func _ready() -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if url != "":
		var me: WeakRef = weakref(self)
		_in_ready = true
		Media.url_texture(url, 184 if px > 96 else 128, func(t: Texture2D) -> void:
			var a: Variant = me.get_ref()
			if a != null and t != null:
				a.call("_got", t)
		)
		_in_ready = false


func _got(t: Texture2D) -> void:
	_tex = t
	texture_loaded.emit(t)
	if _in_ready or not is_inside_tree():
		_tex_a = 1.0
		queue_redraw()
		return
	U.tw(self, "uz_av").tween_method(func(v: float) -> void:
		_tex_a = v
		queue_redraw()
	, 0.0, 1.0, U.T_BASE)


func texture() -> Texture2D:
	return _tex


## Geteilte Elemente (src/ui/flug.gd): das runde Bild (mit Ring rückt es etwas nach innen).
func flug_bild() -> Dictionary:
	if _tex == null:
		return {}
	var r := px * 0.5
	if ring and status != "" and STATUS_COLORS.has(status):
		r -= maxf(3.0, roundf(px * 0.028)) + maxf(3.0, roundf(px * 0.025))
	var c := Vector2(px, px) * 0.5
	return { "node": self, "tex": _tex, "rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), "rund": true, "tint": Color.WHITE }


func _draw() -> void:
	var c := Vector2(px, px) * 0.5
	var r := px * 0.5
	var st_col := ""
	if status != "" and STATUS_COLORS.has(status):
		st_col = str(STATUS_COLORS[status])
	# Großes Bild mit Ring: der Ring liegt außen, das Bild rückt etwas nach innen.
	if ring and st_col != "":
		var w := maxf(3.0, roundf(px * 0.028))
		var rc := UzTheme.col("text", 0.16) if status == "offline" else UzTheme.col(st_col)
		draw_arc(c, r - w * 0.5, 0.0, TAU, 96, rc, w, true)
		r -= w + maxf(3.0, roundf(px * 0.025))
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var p := Vector2(cos(a), sin(a))
		pts.append(c + p * r)
		uvs.append(Vector2(0.5, 0.5) + p * 0.5)
	if _tex == null or _tex_a < 1.0:
		# Ersatz: Fläche in der Farbe des Namens, oben ein weicher Glanz, der Buchstabe hell.
		var base := hue_color(who)
		draw_colored_polygon(pts, base.darkened(0.12))
		draw_colored_polygon(pts, Color(1, 1, 1, 0.16), uvs, U.fade_texture(true))
		var f := UzTheme.display("bold")
		var fs := int(px * 0.42)
		var ch := who.strip_edges().substr(0, 1).to_upper()
		if ch == "":
			ch = "?"
		# Aus einem fremden Namen: nie übersetzen (kein tr()).
		var sz := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - sz.x * 0.5, c.y - sz.y * 0.5 + f.get_ascent(fs)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.94))
	if _tex != null and _tex_a > 0.0:
		draw_colored_polygon(pts, Color(1, 1, 1, _tex_a), uvs, _tex)
	# Feine Kante, damit dunkle Bilder nicht im Raum verschwimmen.
	draw_arc(c, r - 0.5, 0.0, TAU, 72, Color(1, 1, 1, 0.07), 1.0, true)
	if st_col != "" and not ring:
		var dr := px * (0.16 if px <= 64 else 0.14)
		var d := Vector2(px, px) * 0.845
		draw_circle(d, dr, UzTheme.col("bg"))
		draw_circle(d, dr * 0.68, UzTheme.col(st_col))

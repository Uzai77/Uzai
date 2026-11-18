extends Control
## Bild für leere Seiten: drei Abzeichen wie in einer Vitrine, das mittlere größer und mit
## weichem Goldschein. „off“ (kein Netz, noch nichts verbunden): alles gedämpft und gesperrt.
## Ruhig und still: auf leeren Seiten passiert nichts, also bewegt sich auch nichts.

const Emblem := preload("res://src/ui/components/ach/emblem.gd")

var off := false


func setup(dimmed: bool) -> Control:
	off = dimmed
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(560, 360)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec in [[1, 112, Vector2(40, 150)], [2, 112, Vector2(408, 150)], [3, 168, Vector2(196, 70)]]:
		var e = Emblem.new().setup("", not off, int(spec[0]), int(spec[1]))
		e.check = false
		e.position = spec[2]
		if not off and int(spec[0]) == 3:
			e.glow = 0.9
		add_child(e)
	modulate.a = 0.55 if off else 1.0


func _draw() -> void:
	var c := Vector2(280, 154)
	if not off:
		var rr := 250.0
		draw_texture_rect(_radial(), Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(UzTheme.col("accent"), 0.16))
	# Boden der Vitrine: eine feine Linie, die zu den Seiten ausläuft.
	var y := 318.0
	for k in 28:
		var x0 := 20.0 + k * 19.0
		var a := sin(PI * float(k) / 27.0)
		draw_line(Vector2(x0, y), Vector2(x0 + 19.0, y), UzTheme.col("text", 0.1 * a), 2.0)


static var _glow: GradientTexture2D


## Weicher, runder Schein (weiß, wird eingefärbt).
static func _radial() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 256
		_glow.height = 256
	return _glow

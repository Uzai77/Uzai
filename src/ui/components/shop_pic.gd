extends Control
## Ein Spielbild im Shop, nie verzerrt: Hat das Bild die Form der Fläche, füllt es sie (mittig
## leicht beschnitten). Sonst – etwa nur ein Querformat-Bild in der Hochformat-Karte – liegt es
## ganz und scharf über einer weichgezeichneten Fassung von sich selbst. Der Weichzeichner läuft
## wie beim Hintergrund von Uzai: Bild auf der CPU klein gerechnet, dann im Shader gestreut
## (glatt auch auf großen Flächen wie dem Rampenlicht).

## Wie BLUR in background.gd (Spirale aus 12 Proben), aber mit der Farbe der Fläche multipliziert:
## So wirken Abdunkeln (self_modulate) und Einblenden der Karte (modulate) auch hier.
const BLUR := """shader_type canvas_item;
uniform float radius = 0.0;
uniform int taps = 12;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 acc = vec4(0.0);
	float ws = 0.0;
	for (int i = 0; i < taps; i++) {
		float f = (float(i) + 0.5) / float(taps);
		float a = float(i) * 2.39996;
		vec2 o = vec2(cos(a), sin(a)) * sqrt(f) * radius;
		float w = exp(-f * 2.2);
		acc += texture(TEXTURE, clamp(UV + o, vec2(0.002), vec2(0.998))) * w;
		ws += w;
	}
	COLOR = acc / ws * tint;
}
"""

const ShopArt := preload("res://src/ui/components/shop_art.gd")
const BG := preload("res://src/ui/components/background.gd")
const SOFT_STEPS := 10

var box := Vector2.ZERO                ## Größe der Fläche, wenn sie schon vor dem Aufbau feststeht
var align := Vector2(0.5, 0.42)        ## wohin ein eingepasstes Bild rückt (0…1 je Achse)
var fill := Vector2(0.8, 1.25)         ## so weit darf das Seitenverhältnis abweichen und trotzdem füllen
var texture: Texture2D:
	set(v):
		texture = v
		_prep()
var _bg: TextureRect
var _front: Control
static var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg.self_modulate = Color(0.6, 0.6, 0.6)
	_bg.material = _blur()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_front = _Front.new()
	_front.set("pic", self)
	_front.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_front)
	resized.connect(_prep)
	_prep()


static func _blur() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = BLUR
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("radius", BG.soft_radius(SOFT_STEPS))
		_mat.set_shader_parameter("taps", BG.blur_taps())
	return _mat


func area() -> Vector2:
	return size if size.x >= 1.0 and size.y >= 1.0 else box


## Wird das Bild eingepasst statt randvoll gezeigt?
func fitted() -> bool:
	return texture != null and not ShopArt.fits(texture.get_size(), area(), fill)


## Die weiche Fassung nur, wenn sie gebraucht wird (einmal je Bild).
func _prep() -> void:
	if _bg == null:
		return
	var need := fitted() and area().x >= 1.0
	if need and _bg.get_meta("src", 0) != texture.get_instance_id():
		_bg.texture = ShopArt.soft_of(texture, SOFT_STEPS)
		_bg.set_meta("src", texture.get_instance_id())
	_bg.visible = need and _bg.texture != null
	_front.queue_redraw()


## Vorn: das Bild selbst (randvoll oder eingepasst mit weichem Schatten).
class _Front extends Control:
	var pic: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var t: Texture2D = pic.get("texture")
		if t == null:
			return
		var r := Rect2(Vector2.ZERO, pic.call("area"))
		if bool(pic.call("fitted")) and not (pic.get("_bg") as Control).visible:
			draw_rect(r, Color(0.06, 0.065, 0.08))
		ShopArt.draw_art(self, t, r, null, 1.0, 1.0, pic.get("align"), false, pic.get("fill"))
